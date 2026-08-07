#!/usr/bin/env python3
"""Validate every documented example and run its declarative behavior cases."""

from __future__ import annotations

import argparse
import contextlib
import functools
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import urllib.request
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Iterator

from build import ROC_TARGETS, detect_native_target
from roc_version import active_roc_version, require_pinned_roc
from update_app_platform_urls import update_apps


ROOT = Path(__file__).resolve().parents[1]
EXAMPLES_DIR = ROOT / "examples"
SPEC_PATH = ROOT / "scripts" / "test_spec.json"
STAGES = ("fmt", "check", "test", "build", "run")


def configure_console() -> None:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="backslashreplace")


def executable(command_name: str) -> str:
    path = Path(command_name)
    if path.is_absolute() or path.parent != Path("."):
        path = path if path.is_absolute() else ROOT / path
        resolved = str(path.resolve()) if path.is_file() else None
    else:
        resolved = shutil.which(command_name)
    if resolved is None:
        raise SystemExit(f"Could not find Roc executable {command_name!r}.")
    return resolved


def command(*args: str | Path) -> None:
    values = [str(value) for value in args]
    print(f"+ {subprocess.list2cmdline(values)}", flush=True)
    subprocess.run(values, cwd=ROOT, check=True)


def roc_extra_args() -> tuple[str, ...]:
    args = ("--max-transitive-mb=256",)
    return (*args, "--no-cache") if os.name == "nt" else args


def declared_targets() -> tuple[str, ...]:
    source = (ROOT / "platform" / "main.roc").read_text(encoding="utf-8")
    match = re.search(r"(?ms)^\s*targets:\s*\{(.*?)^\s*\}", source)
    if match is None:
        raise SystemExit("platform/main.roc: no targets block found")
    targets = tuple(re.findall(r"(?m)^\s+([A-Za-z0-9_]+):\s*\{\s*inputs:", match.group(1)))
    if set(targets) != set(ROC_TARGETS):
        raise SystemExit(f"Platform/build target mismatch: platform={targets}, build={ROC_TARGETS}")
    return targets


def load_spec() -> dict[str, Any]:
    spec = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
    if set(spec.get("stages", {})) != set(STAGES):
        raise SystemExit(f"{SPEC_PATH}: stages must be exactly {', '.join(STAGES)}")
    apps = spec.get("apps")
    if not isinstance(apps, list) or not apps:
        raise SystemExit(f"{SPEC_PATH}: apps must be a non-empty list")
    declared = [str(app.get("path", "")) for app in apps]
    if len(declared) != len(set(declared)):
        raise SystemExit(f"{SPEC_PATH}: each app path must be unique")
    discovered = sorted(path.relative_to(ROOT).as_posix() for path in EXAMPLES_DIR.glob("*/main.roc"))
    if sorted(declared) != discovered:
        raise SystemExit(f"Example/spec mismatch; declared={sorted(declared)}, discovered={discovered}")
    for app in apps:
        cases = app.get("cases", [])
        names = [case.get("name") for case in cases]
        if not names or len(names) != len(set(names)) or any(not name for name in names):
            raise SystemExit(f"{app['path']}: cases need unique, non-empty names")
    return spec


def create_bundle(roc: str) -> Path:
    result = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "bundle.py"), "--roc", roc],
        cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=True,
    )
    print(result.stdout, end="")
    matches = re.findall(r"^Created:\s+(.+\.tar\.zst)\s*$", result.stdout, re.MULTILINE)
    if not matches:
        raise SystemExit("Bundle creation did not report a .tar.zst archive")
    path = Path(matches[-1])
    path = path if path.is_absolute() else ROOT / path
    if not path.is_file():
        raise SystemExit(f"Bundle creation did not produce an archive: {path}")
    return path.resolve()


class BundleServer:
    def __init__(self, bundle: Path) -> None:
        class QuietHandler(SimpleHTTPRequestHandler):
            def log_message(self, _format: str, *_args: object) -> None:
                pass
        handler = functools.partial(QuietHandler, directory=str(bundle.parent))
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.url = f"http://127.0.0.1:{self.server.server_port}/{bundle.name}"

    def __enter__(self) -> str:
        self.thread.start()
        try:
            request = urllib.request.Request(self.url, method="HEAD")
            with urllib.request.urlopen(request, timeout=5):
                pass
        except BaseException:
            self.server.shutdown()
            self.server.server_close()
            self.thread.join()
            raise
        return self.url

    def __exit__(self, *_args: object) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()


@contextlib.contextmanager
def served_bundle(path: Path) -> Iterator[str]:
    with BundleServer(path) as url:
        print(f"Bundle: {url}")
        yield url


def validate_apps(roc: str, spec: dict[str, Any]) -> None:
    for stage in ("fmt", "check", "test"):
        if not spec["stages"][stage]:
            continue
        print(f"\n=== Example {stage} ===")
        for app in spec["apps"]:
            args = ("--check",) if stage == "fmt" else roc_extra_args()
            command(roc, stage, ROOT / app["path"], *args)


def build_apps(roc: str, target: str, output: Path, spec: dict[str, Any]) -> dict[str, Path]:
    print(f"\n=== Building examples for {target} ===")
    binaries: dict[str, Path] = {}
    for app in spec["apps"]:
        source = ROOT / app["path"]
        suffix = ".exe" if target == "x64win" else ""
        binary = output / f"{source.parent.name}{suffix}"
        command(roc, "build", source, f"--target={target}", f"--output={binary}", *roc_extra_args())
        if os.name == "posix":
            binary.chmod(binary.stat().st_mode | 0o111)
        binaries[app["path"]] = binary
    return binaries


def compiler_runtime_input(name: str) -> Path:
    value = subprocess.check_output(
        ["cc", f"-print-file-name={name}"], text=True
    ).strip()
    path = Path(value)
    if value == name or not path.is_file():
        raise SystemExit(f"C compiler could not locate required x64glibc input {name}")
    return path.resolve()


def build_valgrind_apps(
    roc: str, output: Path, spec: dict[str, Any]
) -> dict[str, Path]:
    print("\n=== Building examples for Valgrind (x64glibc) ===")
    command("cargo", "build", "--locked", "--lib", "--profile", "memcheck")

    platform_dir = output / "platform"
    target_dir = platform_dir / "targets" / "x64glibc"
    app_dir = output / "apps"
    binary_dir = output / "binaries"
    target_dir.mkdir(parents=True)
    app_dir.mkdir()
    binary_dir.mkdir()

    for source in sorted((ROOT / "platform").glob("*.roc")):
        shutil.copy2(source, platform_dir / source.name)

    runtime_inputs = (
        "Scrt1.o",
        "crti.o",
        "libgcc_s.so.1",
        "libm.so.6",
        "libc.so.6",
        "crtn.o",
    )
    shutil.copy2(ROOT / "target" / "memcheck" / "libhost.a", target_dir)
    for name in runtime_inputs:
        shutil.copy2(compiler_runtime_input(name), target_dir / name)

    main_path = platform_dir / "main.roc"
    main_source = main_path.read_text(encoding="utf-8")
    target_line = (
        '\t\tx64glibc: { inputs: ["Scrt1.o", "crti.o", "libhost.a", app, '
        '"libgcc_s.so.1", "libm.so.6", "libc.so.6", "crtn.o"] },'
    )
    main_source, count = re.subn(
        r"(?m)^(\s*x64mac:\s*\{[^\n]+\},)\s*$",
        lambda match: f"{target_line}\n{match.group(1)}",
        main_source,
        count=1,
    )
    if count != 1:
        raise SystemExit("Could not add the validation-only x64glibc target")
    main_path.write_text(main_source, encoding="utf-8", newline="\n")

    binaries: dict[str, Path] = {}
    for app in spec["apps"]:
        source = ROOT / app["path"]
        copied_source = app_dir / source.parent.name / source.name
        copied_source.parent.mkdir()
        app_source = source.read_text(encoding="utf-8")
        platform_path = os.path.relpath(main_path, copied_source.parent).replace(
            os.sep, "/"
        )
        app_source, count = re.subn(
            r'(?m)(\bplatform\s+)"[^"]+"',
            lambda match: f'{match.group(1)}"{platform_path}"',
            app_source,
            count=1,
        )
        if count != 1:
            raise SystemExit(f"{source}: expected exactly one platform dependency")
        copied_source.write_text(app_source, encoding="utf-8", newline="\n")

        binary = binary_dir / source.parent.name
        command(
            roc,
            "build",
            copied_source,
            "--target=x64glibc",
            "--opt=dev",
            f"--output={binary}",
            *roc_extra_args(),
        )
        command("strip", "--strip-debug", binary)
        binaries[app["path"]] = binary
    return binaries


def fail(case: str, message: str, result: subprocess.CompletedProcess[str] | None = None) -> None:
    details = f"\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}" if result else ""
    raise SystemExit(f"Case {case!r}: {message}{details}")


def assert_fragments(case_name: str, label: str, actual: str, expected: list[str], absent: list[str]) -> None:
    for fragment in expected:
        if fragment not in actual:
            fail(case_name, f"expected {fragment!r} in {label}")
    for fragment in absent:
        if fragment in actual:
            fail(case_name, f"did not expect {fragment!r} in {label}")


def process_command(
    binary: Path,
    args: list[str],
    temporary: Path,
    *,
    valgrind: bool,
) -> tuple[list[str], Path | None]:
    if not valgrind:
        return [str(binary), *args], None
    log_path = temporary / "valgrind.log"
    return (
        [
            "valgrind",
            "--tool=memcheck",
            "--error-exitcode=97",
            "--leak-check=full",
            "--show-leak-kinds=all",
            "--errors-for-leak-kinds=definite,indirect",
            "--track-origins=yes",
            "--realloc-zero-bytes-frees=no",
            "--num-callers=40",
            f"--log-file={log_path}",
            str(binary),
            *args,
        ],
        log_path,
    )


def validate_valgrind_log(log_path: Path | None, case_name: str) -> None:
    if log_path is None:
        return
    if not log_path.is_file():
        fail(case_name, "Valgrind did not produce its Memcheck log")
    log = log_path.read_text(encoding="utf-8", errors="replace")
    allocation_match = re.search(r"total heap usage:\s*([0-9,]+) allocs", log)
    if allocation_match is None:
        fail(case_name, f"Memcheck did not report allocator activity\n{log}")
    allocation_count = int(allocation_match.group(1).replace(",", ""))
    if allocation_count == 0:
        fail(
            case_name,
            "Memcheck observed zero allocations; allocator interception is not valid"
            f"\n{log}",
        )
    if "All heap blocks were freed -- no leaks are possible" not in log:
        for leak_kind in ("definitely lost", "indirectly lost"):
            leak_match = re.search(rf"{leak_kind}:\s*([0-9,]+) bytes", log)
            if leak_match is None:
                fail(case_name, f"Memcheck did not report {leak_kind} bytes\n{log}")
            if int(leak_match.group(1).replace(",", "")) != 0:
                fail(case_name, f"Memcheck reported memory that was {leak_kind}\n{log}")
    if re.search(r"ERROR SUMMARY:\s*0 errors", log) is None:
        fail(case_name, f"Memcheck reported an error\n{log}")


def run_case(
    binary: Path,
    app: dict[str, Any],
    case: dict[str, Any],
    *,
    valgrind: bool,
) -> None:
    label = f"{app['name']} / {case['name']}"
    print(f"\n--- {label} ---")
    with tempfile.TemporaryDirectory(prefix="basic-ssg-case-") as raw_temporary:
        temporary = Path(raw_temporary)
        root = temporary / ("ünicode-路径" if case.get("unicode_paths") else "workspace")
        input_dir, output_dir = root / "input", root / "output"
        root.mkdir(parents=True)
        if source := case.get("input"):
            shutil.copytree(ROOT / source, input_dir)
        else:
            input_dir.mkdir()
        if public := case.get("public"):
            shutil.copytree(ROOT / public, output_dir)
        else:
            output_dir.mkdir()
        for item in case.get("input_files", []):
            destination = input_dir / item["path"]
            destination.parent.mkdir(parents=True, exist_ok=True)
            if "hex" in item:
                destination.write_bytes(bytes.fromhex(item["hex"]))
            else:
                destination.write_text(item["text"], encoding="utf-8", newline="")
        for relative in case.get("remove", []):
            path = input_dir / relative
            if path.is_dir():
                shutil.rmtree(path)
            else:
                path.unlink(missing_ok=True)
        if case.get("output_as_file"):
            shutil.rmtree(output_dir)
            output_dir.write_text("not a directory", encoding="utf-8")
        values = {
            "root": str(root), "input": str(input_dir), "output": str(output_dir),
        }
        args = [arg.format(**values) for arg in case.get("args", [])]
        argv, valgrind_log = process_command(
            binary, args, temporary, valgrind=valgrind
        )
        print(f"+ {subprocess.list2cmdline(argv)}", flush=True)
        result = subprocess.run(argv, cwd=ROOT, text=True, encoding="utf-8", errors="replace",
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=300 if valgrind else 30, check=False)
        validate_valgrind_log(valgrind_log, label)
        expected_exit = case.get("exit_code", 0)
        if result.returncode != expected_exit:
            fail(label, f"expected exit {expected_exit}, got {result.returncode}", result)
        assert_fragments(label, "stdout", result.stdout, case.get("stdout_contains", []), case.get("stdout_not_contains", []))
        assert_fragments(label, "stderr", result.stderr, case.get("stderr_contains", []), case.get("stderr_not_contains", []))
        if "files" in case:
            actual = sorted(path.relative_to(output_dir).as_posix() for path in output_dir.rglob("*") if path.is_file()) if output_dir.is_dir() else []
            expected = sorted(case["files"])
            if actual != expected:
                fail(label, f"expected output files {expected}, got {actual}", result)
        for relative, fragments in case.get("file_contains", {}).items():
            path = output_dir / relative
            if not path.is_file():
                fail(label, f"expected output file {relative}", result)
            assert_fragments(label, relative, path.read_text(encoding="utf-8"), fragments, case.get("file_not_contains", {}).get(relative, []))


def run_cases(
    binaries: dict[str, Path], spec: dict[str, Any], *, valgrind: bool
) -> None:
    suffix = " under Valgrind" if valgrind else ""
    print(f"\n=== Running example behavior specs{suffix} ===")
    for app in spec["apps"]:
        for case in app["cases"]:
            run_case(binaries[app["path"]], app, case, valgrind=valgrind)


def run_suite(
    roc: str,
    platform_url: str,
    target: str,
    operation: str,
    *,
    valgrind: bool,
) -> None:
    spec = load_spec()
    sources = [ROOT / app["path"] for app in spec["apps"]]
    backups = {path: path.read_bytes() for path in sources}
    try:
        update_apps(sources, platform_url)
        validate_apps(roc, spec)
        if operation == "all" and spec["stages"]["build"]:
            with tempfile.TemporaryDirectory(prefix="basic-ssg-binaries-") as temporary:
                binaries = (
                    build_valgrind_apps(roc, Path(temporary), spec)
                    if valgrind
                    else build_apps(roc, target, Path(temporary), spec)
                )
                if spec["stages"]["run"]:
                    run_cases(binaries, spec, valgrind=valgrind)
    finally:
        for path, contents in backups.items():
            path.write_bytes(contents)


def main() -> None:
    configure_console()
    parser = argparse.ArgumentParser(description="Validate basic-ssg examples from scripts/test_spec.json")
    parser.add_argument("--roc", default=os.environ.get("ROC", "roc"))
    parser.add_argument("--bundle-path", type=Path)
    parser.add_argument("--bundle-url", default=os.environ.get("BUNDLE_URL"))
    parser.add_argument("--platform-url", help="use platform source directly instead of a bundle")
    parser.add_argument("--no-build", action="store_true", help="do not rebuild the platform host")
    parser.add_argument(
        "--allow-unpinned-roc",
        action="store_true",
        help="allow the scheduled compatibility lane to test a newer Roc nightly",
    )
    parser.add_argument("--operation", choices=("all", "validate"), default="all")
    parser.add_argument("--target", choices=declared_targets())
    parser.add_argument(
        "--valgrind",
        action="store_true",
        help="run native x64 Linux example cases under Valgrind Memcheck",
    )
    args = parser.parse_args()
    if sum(value is not None for value in (args.bundle_path, args.bundle_url, args.platform_url)) > 1:
        parser.error("--bundle-path, --bundle-url, and --platform-url are mutually exclusive")
    roc = executable(args.roc)
    target = args.target or detect_native_target()
    if args.valgrind and args.operation != "all":
        parser.error("--valgrind requires --operation all")
    if args.valgrind and (
        platform.system() != "Linux"
        or platform.machine().lower() not in {"amd64", "x86_64"}
        or target != "x64musl"
    ):
        parser.error("--valgrind currently requires native x86-64 Linux (x64musl)")
    if args.valgrind and shutil.which("valgrind") is None:
        parser.error("--valgrind requires 'valgrind' on PATH")
    if args.valgrind and shutil.which("cc") is None:
        parser.error("--valgrind requires 'cc' on PATH")
    if args.valgrind and shutil.which("strip") is None:
        parser.error("--valgrind requires 'strip' on PATH")
    if args.operation == "all" and target != detect_native_target():
        raise SystemExit(f"Cannot run {target} artifacts on native target {detect_native_target()}")
    version = active_roc_version(roc) if args.allow_unpinned_roc else require_pinned_roc(roc)
    print(f"Using roc version: {version}")
    if not args.no_build and not any((args.bundle_path, args.bundle_url, args.platform_url)):
        command(sys.executable, ROOT / "scripts" / "build.py", "--target", target)
    generated_bundle: Path | None = None
    try:
        if args.platform_url:
            run_suite(
                roc, args.platform_url, target, args.operation, valgrind=args.valgrind
            )
        elif args.bundle_url:
            run_suite(
                roc, args.bundle_url, target, args.operation, valgrind=args.valgrind
            )
        else:
            bundle = args.bundle_path
            if bundle is None:
                generated_bundle = bundle = create_bundle(roc)
            bundle = bundle if bundle.is_absolute() else ROOT / bundle
            if not bundle.is_file():
                raise SystemExit(f"Bundle does not exist: {bundle}")
            with served_bundle(bundle.resolve()) as url:
                run_suite(roc, url, target, args.operation, valgrind=args.valgrind)
    finally:
        if generated_bundle is not None:
            generated_bundle.unlink(missing_ok=True)
    print("\nAll example specs passed!")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from None
    except subprocess.TimeoutExpired as error:
        raise SystemExit(f"Timed out after {error.timeout}s: {' '.join(error.cmd)}") from None
