#!/usr/bin/env python3
from __future__ import annotations

import argparse
import contextlib
import functools
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import urllib.request
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Iterator

from build import ALL_TARGETS, detect_native_target
from update_app_platform_urls import update_apps


ROOT = Path(__file__).resolve().parents[1]
EXAMPLE_DIR = ROOT / "example"
EXAMPLES = (EXAMPLE_DIR / "main.roc", EXAMPLE_DIR / "error-handling.roc")
SPEC_PATH = ROOT / "scripts" / "test_spec.json"


def command(*args: str | Path) -> None:
    values = [str(value) for value in args]
    print(f"+ {' '.join(values)}", flush=True)
    subprocess.run(values, cwd=ROOT, check=True)


def roc_extra_args() -> tuple[str, ...]:
    args = ("--max-transitive-mb=256",)
    return (*args, "--no-cache") if os.name == "nt" else args


def declared_targets() -> tuple[str, ...]:
    source = (ROOT / "platform" / "main.roc").read_text(encoding="utf-8")
    match = re.search(r"(?ms)^\s*targets:\s*\{(.*?)^\s*\}", source)
    if match is None:
        raise SystemExit("platform/main.roc: no targets block found")
    targets = tuple(
        re.findall(r"(?m)^\s+([A-Za-z0-9_]+):\s*\{\s*inputs:", match.group(1))
    )
    if set(targets) != set(ALL_TARGETS):
        raise SystemExit(
            f"Platform/build target mismatch: platform={targets}, build={ALL_TARGETS}"
        )
    return targets


def create_bundle() -> Path:
    result = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "bundle.py")],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=True,
    )
    print(result.stdout, end="")
    matches = re.findall(r"^Created:\s+(.+\.tar\.zst)\s*$", result.stdout, re.MULTILINE)
    if not matches:
        raise SystemExit("Bundle creation did not report a .tar.zst archive")
    path = Path(matches[-1])
    if not path.is_absolute():
        path = ROOT / path
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
        request = urllib.request.Request(self.url, method="HEAD")
        with urllib.request.urlopen(request, timeout=5):
            pass
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


def validate_examples() -> None:
    print("\n=== Validating bundled examples ===")
    for source in EXAMPLES:
        command("roc", "fmt", "--check", source)
        command("roc", "check", source, *roc_extra_args())
        command("roc", "test", source, *roc_extra_args())


def build_examples(target: str, output_dir: Path) -> dict[str, Path]:
    print(f"\n=== Building bundled examples for {target} ===")
    binaries: dict[str, Path] = {}
    for source in EXAMPLES:
        binary = output_dir / source.stem
        command(
            "roc",
            "build",
            source,
            f"--target={target}",
            f"--output={binary}",
            *roc_extra_args(),
        )
        binary.chmod(binary.stat().st_mode | 0o111)
        binaries[source.name] = binary
    return binaries


def run_process(binary: Path, *args: Path) -> subprocess.CompletedProcess[str]:
    values = [str(binary), *(str(arg) for arg in args)]
    print(f"+ {' '.join(values)}", flush=True)
    return subprocess.run(
        values,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=False,
    )


def require_exit(result: subprocess.CompletedProcess[str], expected: int) -> None:
    if result.returncode != expected:
        raise SystemExit(
            f"Expected exit {expected}, got {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )


def run_examples(binaries: dict[str, Path]) -> None:
    print("\n=== Running bundled examples ===")
    spec = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
    with tempfile.TemporaryDirectory(prefix="basic-ssg-output-") as temp:
        output_dir = Path(temp) / "www"
        output_dir.mkdir()
        result = run_process(
            binaries["main.roc"], EXAMPLE_DIR / "content", output_dir
        )
        require_exit(result, 0)
        generated = sorted(
            path.relative_to(output_dir).as_posix()
            for path in output_dir.rglob("*.html")
        )
        expected = sorted(spec["generated_pages"])
        if generated != expected:
            raise SystemExit(
                f"Generated page mismatch; expected={expected}, actual={generated}"
            )
        empty = [
            name
            for name in generated
            if not (output_dir / name).read_text(encoding="utf-8")
        ]
        if empty:
            raise SystemExit(f"Generated empty HTML pages: {empty}")

    result = run_process(
        binaries["error-handling.roc"], EXAMPLE_DIR / "content" / "index.md"
    )
    require_exit(result, 0)
    expected_title = str(spec["error_example_title"])
    if expected_title not in result.stdout:
        raise SystemExit(
            f"Expected {expected_title!r} in stdout, got:\n{result.stdout}"
        )

    require_exit(run_process(binaries["main.roc"]), 1)
    require_exit(run_process(binaries["error-handling.roc"]), 1)


def run_suite(bundle_url: str, target: str, operation: str) -> None:
    backups = {path: path.read_bytes() for path in EXAMPLES}
    try:
        update_apps([EXAMPLE_DIR], bundle_url)
        validate_examples()
        if operation == "all":
            with tempfile.TemporaryDirectory(prefix="basic-ssg-binaries-") as temp:
                binaries = build_examples(target, Path(temp))
                run_examples(binaries)
    finally:
        for path, contents in backups.items():
            path.write_bytes(contents)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Validate basic-ssg through a served platform bundle"
    )
    parser.add_argument("--bundle-path", type=Path)
    parser.add_argument("--bundle-url", default=os.environ.get("BUNDLE_URL"))
    parser.add_argument("--no-build", action="store_true")
    parser.add_argument("--operation", choices=("all", "validate"), default="all")
    parser.add_argument("--target", choices=declared_targets())
    args = parser.parse_args()
    if args.bundle_path and args.bundle_url:
        parser.error("--bundle-path and --bundle-url are mutually exclusive")
    if shutil.which("roc") is None:
        raise SystemExit("'roc' was not found on PATH")

    target = args.target or detect_native_target()
    if args.operation == "all" and target != detect_native_target():
        raise SystemExit(
            f"Cannot run {target} artifacts on native target {detect_native_target()}"
        )
    print(f"Using roc version: {subprocess.check_output(['roc', 'version'], text=True).strip()}")

    if not args.no_build and args.bundle_path is None and args.bundle_url is None:
        command(sys.executable, ROOT / "scripts" / "build.py", "--target", target)

    generated_bundle: Path | None = None
    try:
        if args.bundle_url:
            print(f"Bundle: {args.bundle_url}")
            run_suite(args.bundle_url, target, args.operation)
        else:
            bundle = args.bundle_path
            if bundle is None:
                generated_bundle = bundle = create_bundle()
            elif not bundle.is_absolute():
                bundle = ROOT / bundle
            bundle = bundle.resolve()
            if not bundle.is_file():
                raise SystemExit(f"Bundle does not exist: {bundle}")
            with served_bundle(bundle) as url:
                run_suite(url, target, args.operation)
    finally:
        if generated_bundle is not None:
            generated_bundle.unlink(missing_ok=True)

    print("\nAll bundled-platform checks passed!")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from None
    except subprocess.TimeoutExpired as error:
        raise SystemExit(f"Timed out after {error.timeout}s: {' '.join(error.cmd)}") from None
