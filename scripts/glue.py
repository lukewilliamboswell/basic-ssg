#!/usr/bin/env python3
"""Generate or verify the Rust ABI bindings for the Roc platform."""

from __future__ import annotations

import argparse
import difflib
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import urlopen

from roc_version import pinned_roc, require_pinned_roc


ROOT = Path(__file__).resolve().parents[1]
GENERATED_FILE = "roc_platform_abi.rs"
VALID_OPT_LEVELS = ("dev", "size", "speed")


class GlueError(RuntimeError):
    pass


def find_executable(command: str) -> str:
    command_path = Path(command)
    if command_path.is_absolute() or command_path.parent != Path("."):
        if not command_path.is_absolute():
            command_path = ROOT / command_path
        executable = str(command_path.resolve()) if command_path.is_file() else None
    else:
        executable = shutil.which(command)
    if executable is None:
        raise GlueError(
            f"Could not find Roc executable {command!r}. "
            "Use --roc, set ROC, or add roc to PATH."
        )
    return executable


def find_glue_spec() -> str:
    """Return an explicit spec or the immutable spec matching .roc-version."""
    for key in ("ROC_GLUE_SPEC", "ROC_RUST_GLUE"):
        if value := os.environ.get(key):
            return value

    candidates: list[Path] = []
    if glue_dir := os.environ.get("ROC_GLUE_DIR"):
        path = Path(glue_dir)
        candidates.append(
            (path if path.is_absolute() else ROOT / path) / "RustGlue.roc"
        )
    if roc_src := os.environ.get("ROC_SRC"):
        path = Path(roc_src)
        candidates.append(
            (path if path.is_absolute() else ROOT / path)
            / "src"
            / "glue"
            / "src"
            / "RustGlue.roc"
        )

    for candidate in candidates:
        if candidate.is_file():
            return str(candidate.resolve())

    _tag, revision = pinned_roc()
    return (
        "https://raw.githubusercontent.com/roc-lang/roc/"
        f"{revision}/src/glue/src/RustGlue.roc"
    )


def local_spec_path(spec: str) -> Path | None:
    parsed = urlparse(spec)
    if parsed.scheme in {"http", "https"}:
        return None

    # Roc also accepts installed package shorthands. Treat only strings that
    # visibly name a filesystem path as local paths.
    path = Path(spec)
    if not (
        path.is_absolute()
        or path.suffix == ".roc"
        or "/" in spec
        or "\\" in spec
    ):
        return None
    return path if path.is_absolute() else ROOT / path


def materialize_remote_spec(spec: str, directory: Path) -> str:
    """Download an HTTP glue source so Roc treats it as a source file."""
    parsed = urlparse(spec)
    if parsed.scheme not in {"http", "https"}:
        return spec

    destination = directory / "RustGlue.roc"
    try:
        with urlopen(spec, timeout=30) as response:
            content = response.read()
    except OSError as error:
        raise GlueError(f"Could not download glue spec {spec}: {error}") from error
    if not content:
        raise GlueError(f"Downloaded glue spec is empty: {spec}")
    destination.write_bytes(content)
    return str(destination)


def roc_environment() -> dict[str, str]:
    env = os.environ.copy()
    if os.name == "nt":
        # Native tools need a native absolute path even when launched from a
        # Unix-like shell that exports TMPDIR=/tmp.
        native_temp = str(Path(tempfile.gettempdir()).resolve())
        env.update({"TMPDIR": native_temp, "TEMP": native_temp, "TMP": native_temp})
        return env
    if not any(env.get(name) for name in ("TMPDIR", "TEMP", "TMP")):
        # Roc's native glue plugin build requires a temp variable. Python gives
        # us a native path on both Windows and Unix.
        env["TMPDIR"] = tempfile.gettempdir()
    return env


def run_glue(
    roc: str,
    spec: str,
    output_dir: Path,
    platform_file: Path,
    opt_level: str,
) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    command = [
        roc,
        "glue",
        f"--opt={opt_level}",
        spec,
        str(output_dir),
        str(platform_file),
    ]
    print(f"+ {subprocess.list2cmdline(command)}", flush=True)
    subprocess.run(command, cwd=ROOT, env=roc_environment(), check=True)


def print_diff(committed: Path, generated: Path) -> None:
    before = committed.read_text(encoding="utf-8", errors="replace").splitlines(
        keepends=True
    )
    after = generated.read_text(encoding="utf-8", errors="replace").splitlines(
        keepends=True
    )
    diff = difflib.unified_diff(
        before,
        after,
        fromfile=str(committed),
        tofile=str(generated),
    )
    sys.stdout.writelines(diff)


def generated_source_matches(committed: Path, generated: Path) -> bool:
    """Compare generated source without treating native newlines as ABI drift."""
    before = committed.read_text(encoding="utf-8", errors="replace").splitlines()
    after = generated.read_text(encoding="utf-8", errors="replace").splitlines()
    return before == after


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate Rust ABI bindings for the basic-ssg Roc platform."
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="generate into a temporary directory and compare with the committed file",
    )
    parser.add_argument("--roc", default=os.environ.get("ROC", "roc"))
    parser.add_argument(
        "--glue-spec",
        help="glue spec path, URL, or installed shorthand (overrides discovery)",
    )
    parser.add_argument(
        "--platform-file",
        type=Path,
        default=Path(os.environ.get("PLATFORM_FILE", "platform/main.roc")),
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(os.environ.get("GLUE_OUT_DIR", "src")),
    )
    parser.add_argument(
        "--opt",
        default=os.environ.get("ROC_GLUE_OPT", "dev"),
        metavar="LEVEL",
        help="glue compilation mode: dev, size, or speed (default: %(default)s)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.opt not in VALID_OPT_LEVELS:
        raise GlueError(
            f"Invalid glue optimization level {args.opt!r}; "
            f"expected one of {', '.join(VALID_OPT_LEVELS)}."
        )

    roc = find_executable(args.roc)
    version = require_pinned_roc(roc, env=roc_environment())
    platform_file = args.platform_file
    if not platform_file.is_absolute():
        platform_file = ROOT / platform_file
    if not platform_file.is_file():
        raise GlueError(f"Platform file not found: {platform_file}")

    output_dir = args.output_dir
    if not output_dir.is_absolute():
        output_dir = ROOT / output_dir

    spec = args.glue_spec or find_glue_spec()
    if (local_spec := local_spec_path(spec)) is not None:
        if not local_spec.is_file():
            raise GlueError(f"Glue spec not found: {local_spec}")
        spec = str(local_spec.resolve())

    with tempfile.TemporaryDirectory(prefix="basic-ssg-glue-spec-") as temporary:
        runnable_spec = materialize_remote_spec(spec, Path(temporary))

        print(f"Using roc: {roc}")
        print(f"Using roc version: {version}")
        print(f"Using glue spec: {spec}")
        print(f"Using glue opt: {args.opt}")
        print(f"Platform: {platform_file}")

        if args.check:
            committed = output_dir / GENERATED_FILE
            if not committed.is_file():
                raise GlueError(f"Missing generated glue file: {committed}")
            with tempfile.TemporaryDirectory(prefix="basic-ssg-glue-") as generated:
                generated_dir = Path(generated)
                run_glue(roc, runnable_spec, generated_dir, platform_file, args.opt)
                generated_file = generated_dir / GENERATED_FILE
                if not generated_file.is_file():
                    raise GlueError(
                        f"Roc did not generate the expected file: {generated_file}"
                    )
                if not generated_source_matches(committed, generated_file):
                    print_diff(committed, generated_file)
                    raise GlueError(
                        "Generated Rust glue is stale. Run scripts/glue.py and "
                        "commit the result."
                    )
            print(f"Rust glue is up to date: {committed}")
        else:
            print(f"Output directory: {output_dir}")
            run_glue(roc, runnable_spec, output_dir, platform_file, args.opt)
            generated_file = output_dir / GENERATED_FILE
            if not generated_file.is_file():
                raise GlueError(
                    f"Roc did not generate the expected file: {generated_file}"
                )
            print(f"Generated: {generated_file}")


if __name__ == "__main__":
    try:
        main()
    except GlueError as error:
        raise SystemExit(f"error: {error}") from None
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from None
