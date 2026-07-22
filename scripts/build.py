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
ROC_TARGETS = (*ALL_TARGETS, "x64win")
WINDOWS_TARGET = "x86_64-pc-windows-msvc"
WINDOWS_SYSTEM_LIBRARIES = (
    "advapi32.lib",
    "bcrypt.lib",
    "crypt32.lib",
    "dbghelp.lib",
    "iphlpapi.lib",
    "kernel32.lib",
    "ncrypt.lib",
    "ntdll.lib",
    "ole32.lib",
    "secur32.lib",
    "shell32.lib",
    "user32.lib",
    "userenv.lib",
    "ws2_32.lib",
)


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

    if system == "Windows" and machine in {"amd64", "x86_64"}:
        return "x64win"
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
    env[f"CC_{key}"] = str(ROOT / "scripts" / "zig_cc.py")
    env[f"AR_{key}"] = str(ROOT / "scripts" / "zig_ar.py")
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


def windows_sdk_version(path: Path) -> tuple[int, ...]:
    try:
        return tuple(int(part) for part in path.name.split("."))
    except ValueError:
        return ()


def find_windows_sdk_lib_dir() -> Path:
    program_files = os.environ.get("ProgramFiles(x86)")
    if not program_files:
        raise SystemExit("ProgramFiles(x86) is not set; cannot locate the Windows SDK")

    sdk_root = Path(program_files) / "Windows Kits" / "10" / "Lib"
    if not sdk_root.is_dir():
        raise SystemExit(f"Could not find Windows SDK library directory: {sdk_root}")
    candidates = sorted(
        (
            directory / "um" / "x64"
            for directory in sdk_root.iterdir()
            if directory.is_dir()
            and (directory / "um" / "x64" / "ws2_32.lib").is_file()
        ),
        key=lambda path: windows_sdk_version(path.parents[1]),
        reverse=True,
    )
    if not candidates:
        raise SystemExit(f"Could not find x64 Windows SDK libraries under {sdk_root}")
    return candidates[0]


def build_windows() -> None:
    print(f"Building for x64win ({WINDOWS_TARGET})...")
    install_rust_target(WINDOWS_TARGET)
    run(
        "cargo",
        "build",
        "--locked",
        "--release",
        "--lib",
        "--target",
        WINDOWS_TARGET,
    )

    output_dir = ROOT / "platform" / "targets" / "x64win"
    output_dir.mkdir(parents=True, exist_ok=True)
    host_destination = output_dir / "host.lib"
    shutil.copy2(
        ROOT / "target" / WINDOWS_TARGET / "release" / "host.lib",
        host_destination,
    )
    print(f"  -> {host_destination.relative_to(ROOT)}")

    sdk_lib_dir = find_windows_sdk_lib_dir()
    for name in WINDOWS_SYSTEM_LIBRARIES:
        source = sdk_lib_dir / name
        if not source.is_file():
            raise SystemExit(f"Could not find required Windows SDK library: {source}")
        destination = output_dir / name
        shutil.copy2(source, destination)
        print(f"  -> {destination.relative_to(ROOT)}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Build the basic-ssg platform host")
    parser.add_argument(
        "--all",
        action="store_true",
        help="cross-compile all supported macOS and Linux targets",
    )
    parser.add_argument(
        "--target",
        choices=ROC_TARGETS,
        help="build host inputs for one Roc platform target",
    )
    args = parser.parse_args()

    if args.all and args.target:
        parser.error("--all and --target are mutually exclusive")

    if args.target:
        if args.target == "x64win":
            if platform.system() != "Windows":
                parser.error("x64win host inputs must be built on Windows")
            build_windows()
        else:
            rust_target = TARGETS[args.target]
            install_rust_target(rust_target)
            build_target(args.target, native=args.target == detect_native_target())
        print("\nBuild complete!")
        return

    if args.all:
        if platform.system() not in {"Darwin", "Linux"}:
            parser.error("--all builds the macOS and Linux targets on a Unix host")
        print("Building all macOS and Linux targets...\n")
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
    if target_name == "x64win":
        build_windows()
    else:
        install_rust_target(TARGETS[target_name])
        build_target(target_name, native=True)
    print("\nBuild complete!")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from None
