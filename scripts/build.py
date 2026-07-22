#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TARGETS = {
    "x64mac": "x86_64-apple-darwin",
    "arm64mac": "aarch64-apple-darwin",
    "x64musl": "x86_64-unknown-linux-musl",
    "arm64musl": "aarch64-unknown-linux-musl",
}
ALL_TARGETS = tuple(TARGETS)


def run(*args: str, env: dict[str, str] | None = None) -> None:
    subprocess.run(args, cwd=ROOT, env=env, check=True)


def rust_host_target() -> str:
    output = subprocess.check_output(["rustc", "-vV"], text=True)
    for line in output.splitlines():
        if line.startswith("host: "):
            return line.removeprefix("host: ")
    raise SystemExit("Could not determine the Rust host target")


def find_llvm_strip() -> Path:
    executable = shutil.which("llvm-strip")
    if executable:
        return Path(executable)

    sysroot = Path(
        subprocess.check_output(["rustc", "--print", "sysroot"], text=True).strip()
    )
    executable = (
        sysroot / "lib" / "rustlib" / rust_host_target() / "bin" / "llvm-strip"
    )
    if executable.is_file():
        return executable

    raise SystemExit(
        "llvm-strip was not found; install it with "
        "`rustup component add llvm-tools-preview`"
    )


def strip_linux_host(target_name: str) -> None:
    if not target_name.endswith("musl"):
        return

    path = ROOT / "platform" / "targets" / target_name / "libhost.a"
    before = path.stat().st_size
    # Retain symbols referenced by relocations while removing debug data and
    # unused symbols from the archive shipped in the platform bundle.
    run(str(find_llvm_strip()), "--strip-unneeded", str(path))
    after = path.stat().st_size
    print(f"Stripped {target_name} libhost.a: {before} -> {after} bytes")


def detect_native_target() -> str:
    system = platform.system()
    machine = platform.machine().lower()

    if system == "Darwin":
        if machine in {"arm64", "aarch64"}:
            return "arm64mac"
        if machine in {"x86_64", "amd64"}:
            return "x64mac"
    elif system == "Linux":
        if machine in {"aarch64", "arm64"}:
            return "arm64musl"
        if machine in {"x86_64", "amd64"}:
            return "x64musl"

    raise SystemExit(f"Unsupported native platform: {system} {machine}")


def musl_build_env(rust_target: str) -> dict[str, str]:
    env = os.environ.copy()
    zig_targets = {
        "x86_64-unknown-linux-musl": "x86_64-linux-musl",
        "aarch64-unknown-linux-musl": "aarch64-linux-musl",
    }
    zig_target = zig_targets.get(rust_target)
    zig_bin = env.get("ZIG", "zig")
    if zig_target is None or shutil.which(zig_bin) is None:
        return env

    key = rust_target.replace("-", "_")
    env["ZIG"] = zig_bin
    env["ZIG_CC_TARGET"] = zig_target
    env[f"CC_{key}"] = str(ROOT / "ci" / "zig-cc.sh")
    env[f"AR_{key}"] = str(ROOT / "ci" / "zig-ar.sh")
    env[f"CFLAGS_{key}"] = "-Wno-error"
    print(f"  (using zig cc for {rust_target})")
    return env


def install_rust_target(rust_target: str) -> None:
    run("rustup", "target", "add", rust_target)


def copy_host(target_name: str, rust_target: str, *, native: bool) -> None:
    output_dir = ROOT / "platform" / "targets" / target_name
    output_dir.mkdir(parents=True, exist_ok=True)

    if native and target_name in {"x64mac", "arm64mac"}:
        run("cargo", "build", "--locked", "--release", "--lib")
        source = ROOT / "target" / "release" / "libhost.a"
    else:
        run(
            "cargo",
            "build",
            "--locked",
            "--release",
            "--lib",
            "--target",
            rust_target,
            env=musl_build_env(rust_target),
        )
        source = ROOT / "target" / rust_target / "release" / "libhost.a"

    destination = output_dir / "libhost.a"
    shutil.copy2(source, destination)
    print(f"  -> {destination.relative_to(ROOT)}")


def build_target(target_name: str, *, native: bool = False) -> None:
    rust_target = TARGETS[target_name]
    qualifier = "native" if native else rust_target
    print(f"Building for {target_name} ({qualifier})...")
    copy_host(target_name, rust_target, native=native)
    strip_linux_host(target_name)


def main() -> None:
    parser = argparse.ArgumentParser(description="Build the basic-ssg platform host")
    parser.add_argument(
        "--all",
        action="store_true",
        help="cross-compile all supported macOS and Linux targets",
    )
    parser.add_argument(
        "--target",
        choices=ALL_TARGETS,
        help="build host inputs for one Roc platform target",
    )
    args = parser.parse_args()

    if args.all and args.target:
        parser.error("--all and --target are mutually exclusive")

    if args.target:
        rust_target = TARGETS[args.target]
        install_rust_target(rust_target)
        build_target(args.target, native=args.target == detect_native_target())
        print("\nBuild complete!")
        return

    if args.all:
        if platform.system() not in {"Darwin", "Linux"}:
            parser.error("--all requires a macOS or Linux host")
        print("Building for all supported targets...\n")
        for rust_target in TARGETS.values():
            install_rust_target(rust_target)
        print()
        for target_name in ALL_TARGETS:
            build_target(target_name)
            print()
        print("All targets built successfully!")
        return

    target_name = detect_native_target()
    print(f"Building for native target: {target_name}\n")
    install_rust_target(TARGETS[target_name])
    build_target(target_name, native=True)
    print("\nBuild complete!")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from None
