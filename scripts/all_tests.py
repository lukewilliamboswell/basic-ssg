#!/usr/bin/env python3
"""Run the complete basic-ssg source, host, example, and docs validation."""

from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

from roc_version import active_roc_version, require_pinned_roc


ROOT = Path(__file__).resolve().parents[1]
SECTIONS = ("roc", "glue", "host", "examples", "docs")


def configure_console() -> None:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="backslashreplace")


def executable(command: str, description: str) -> str:
    command_path = Path(command)
    if command_path.is_absolute() or command_path.parent != Path("."):
        if not command_path.is_absolute():
            command_path = ROOT / command_path
        resolved = str(command_path.resolve()) if command_path.is_file() else None
    else:
        resolved = shutil.which(command)
    if resolved is None:
        raise SystemExit(
            f"Could not find {description} executable {command!r}. "
            f"Set the corresponding option or add it to PATH."
        )
    return resolved


def command(
    *args: str | Path,
    cwd: Path = ROOT,
    env: dict[str, str] | None = None,
) -> None:
    values = [str(value) for value in args]
    print(f"+ {subprocess.list2cmdline(values)}", flush=True)
    subprocess.run(values, cwd=cwd, env=env, check=True)


def heading(title: str) -> None:
    print(f"\n=== {title} ===", flush=True)


def roc_extra_args() -> tuple[str, ...]:
    return ("--no-cache",) if os.name == "nt" else ()


def macos_environment() -> dict[str, str]:
    env = os.environ.copy()
    if platform.system() != "Darwin" or env.get("SDKROOT"):
        return env
    xcrun = shutil.which("xcrun")
    if xcrun is None:
        return env
    result = subprocess.run(
        [xcrun, "--sdk", "macosx", "--show-sdk-path"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    sdkroot = result.stdout.strip()
    if result.returncode == 0 and sdkroot:
        env["SDKROOT"] = sdkroot
        print(f"Using SDKROOT: {sdkroot}")
    return env


def validate_roc_sources(roc: str, env: dict[str, str]) -> None:
    heading("Validating Roc sources")
    roc_sources = sorted(
        source
        for directory in (ROOT / "platform", ROOT / "examples")
        for source in directory.rglob("*.roc")
    )
    for source in roc_sources:
        command(roc, "fmt", "--check", source, env=env)
    for source in (
        "platform/Html.roc",
        "platform/PageDecoder.roc",
        "platform/main.roc",
    ):
        command(roc, "check", source, *roc_extra_args(), env=env)


def validate_glue(roc: str, env: dict[str, str]) -> None:
    heading("Checking generated Rust glue")
    command(
        sys.executable,
        ROOT / "scripts" / "glue.py",
        "--check",
        "--roc",
        roc,
        env=env,
    )


def validate_host(cargo: str, env: dict[str, str]) -> None:
    heading("Validating repository test infrastructure")
    command(
        sys.executable,
        "-m",
        "unittest",
        "discover",
        "-s",
        "scripts",
        "-p",
        "test_*.py",
        env=env,
    )

    heading("Validating the platform host")
    command(cargo, "fmt", "--check", env=env)
    command(cargo, "test", "--locked", env=env)
    command(cargo, "clippy", "--locked", "--lib", "--tests", "--", "-D", "warnings", env=env)

    heading("Building the platform host")
    command(sys.executable, ROOT / "scripts" / "build.py", env=env)


def validate_examples(
    roc: str,
    env: dict[str, str],
    *,
    allow_unpinned_roc: bool,
    valgrind: bool,
) -> None:
    heading("Testing documented examples")
    command(
        sys.executable,
        ROOT / "scripts" / "test.py",
        "--roc",
        roc,
        "--platform-url",
        "../../platform/main.roc",
        "--no-build",
        *(["--allow-unpinned-roc"] if allow_unpinned_roc else []),
        *(["--valgrind"] if valgrind else []),
        env=env,
    )


def validate_docs(roc: str, env: dict[str, str]) -> None:
    heading("Building platform docs")
    command(
        roc,
        "docs",
        f"--output={ROOT / 'generated-docs'}",
        ROOT / "platform" / "main.roc",
        env=env,
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run basic-ssg validation.")
    parser.add_argument("--roc", default=os.environ.get("ROC", "roc"))
    parser.add_argument("--cargo", default=os.environ.get("CARGO", "cargo"))
    parser.add_argument(
        "--allow-unpinned-roc",
        action="store_true",
        help="allow compatibility checks with a compiler newer than .roc-version",
    )
    parser.add_argument(
        "--section",
        action="append",
        choices=SECTIONS,
        help="run only this section; may be repeated (default: all sections)",
    )
    parser.add_argument(
        "--valgrind",
        action="store_true",
        help="run x64 Linux example behavior cases under Valgrind Memcheck",
    )
    return parser.parse_args()


def main() -> None:
    configure_console()
    args = parse_args()
    sections = set(args.section or SECTIONS)
    if args.valgrind and "examples" not in sections:
        raise SystemExit("--valgrind requires the examples section")
    roc_sections = sections - {"host"}
    roc = executable(args.roc, "Roc") if roc_sections else None
    cargo = executable(args.cargo, "Cargo") if "host" in sections else args.cargo
    env = macos_environment()

    print("=== basic-ssg CI ===")
    if roc is not None:
        version = (
            active_roc_version(roc, env=env)
            if args.allow_unpinned_roc
            else require_pinned_roc(roc, env=env)
        )
        print(f"Using roc version: {version}")

    if "roc" in sections:
        assert roc is not None
        validate_roc_sources(roc, env)
    if "glue" in sections:
        assert roc is not None
        validate_glue(roc, env)
    if "host" in sections:
        validate_host(cargo, env)
    if "examples" in sections:
        assert roc is not None
        validate_examples(
            roc,
            env,
            allow_unpinned_roc=args.allow_unpinned_roc,
            valgrind=args.valgrind,
        )
    if "docs" in sections:
        assert roc is not None
        validate_docs(roc, env)
    heading("Done")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from None
