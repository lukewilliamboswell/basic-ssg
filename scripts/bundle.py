#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from build import ROC_TARGETS, WINDOWS_SYSTEM_LIBRARIES
from roc_version import active_roc_version, require_pinned_roc


ROOT = Path(__file__).resolve().parents[1]
PLATFORM_DIR = ROOT / "platform"
MAX_PLATFORM_BYTES = 100 * 1024 * 1024
TARGET_INPUTS = {
    "x64mac": ("libhost.a",),
    "arm64mac": ("libhost.a",),
    "x64musl": ("crt1.o", "libhost.a", "libunwind.a", "libc.a"),
    "arm64musl": ("crt1.o", "libhost.a", "libunwind.a", "libc.a"),
    "x64win": ("host.lib", *WINDOWS_SYSTEM_LIBRARIES),
}
LICENSE_NAMES = ("LICENSE", "THIRD_PARTY_LICENSES.md")
RUNTIME_NOTICE = PLATFORM_DIR / "COPYING.MinGW-w64-runtime.txt"


def executable(command: str) -> str:
    command_path = Path(command)
    if command_path.is_absolute() or command_path.parent != Path("."):
        if not command_path.is_absolute():
            command_path = ROOT / command_path
        resolved = str(command_path.resolve()) if command_path.is_file() else None
    else:
        resolved = shutil.which(command)
    if resolved is None:
        raise SystemExit(
            f"Could not find Roc executable {command!r}. "
            "Use --roc, set ROC, or add roc to PATH."
        )
    return resolved


def relative_platform_path(path: Path) -> str:
    return path.relative_to(PLATFORM_DIR).as_posix()


def target_files(target: str | None = None) -> list[Path]:
    if set(TARGET_INPUTS) != set(ROC_TARGETS):
        raise SystemExit(
            f"Bundle/build target mismatch: bundle={tuple(TARGET_INPUTS)}, "
            f"build={ROC_TARGETS}"
        )
    files: list[Path] = []
    missing: list[str] = []
    selected_targets = (target,) if target is not None else tuple(TARGET_INPUTS)
    for selected_target in selected_targets:
        names = TARGET_INPUTS[selected_target]
        for name in names:
            path = PLATFORM_DIR / "targets" / selected_target / name
            if path.is_file():
                files.append(path)
            else:
                missing.append(relative_platform_path(path))
    if missing:
        raise SystemExit(
            "Missing release target inputs; build every release host first:\n- "
            + "\n- ".join(missing)
        )
    return files


def main() -> None:
    parser = argparse.ArgumentParser(description="Bundle the basic-ssg platform")
    parser.add_argument("--output-dir", type=Path, default=ROOT)
    parser.add_argument("--roc", default=os.environ.get("ROC", "roc"))
    parser.add_argument(
        "--target",
        choices=ROC_TARGETS,
        help="include only one target's host inputs for local testing",
    )
    parser.add_argument(
        "--allow-unpinned-roc",
        action="store_true",
        help="allow compatibility checks with a compiler different from the header pin",
    )
    args, roc_args = parser.parse_known_args()
    roc = executable(args.roc)
    if args.allow_unpinned_roc:
        active_roc_version(roc)
    else:
        require_pinned_roc(roc)

    output_dir = args.output_dir
    if not output_dir.is_absolute():
        output_dir = ROOT / output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    output_dir = output_dir.resolve()

    roc_files = sorted(PLATFORM_DIR.glob("*.roc"))
    library_files = target_files(args.target)
    license_sources = [ROOT / name for name in LICENSE_NAMES]
    missing_licenses = [path.name for path in license_sources if not path.is_file()]
    if missing_licenses:
        raise SystemExit(f"Missing required license files: {missing_licenses}")

    runtime_notices = [RUNTIME_NOTICE] if RUNTIME_NOTICE.is_file() else []
    source_files = [*roc_files, *library_files, *license_sources, *runtime_notices]
    unpacked_size = sum(path.stat().st_size for path in source_files)
    if unpacked_size > MAX_PLATFORM_BYTES:
        raise SystemExit(
            "Platform inputs exceed Roc's default 100 MiB transitive dependency limit: "
            f"{unpacked_size} bytes"
        )

    bundle_files = [
        *(relative_platform_path(path) for path in roc_files),
        *(relative_platform_path(path) for path in library_files),
        *(path.name for path in license_sources),
        *(relative_platform_path(path) for path in runtime_notices),
    ]
    print(
        f"Bundling {len(roc_files)} Roc files, {len(library_files)} target inputs, "
        f"and {len(license_sources) + len(runtime_notices)} license files."
    )
    print(f"Unpacked platform inputs: {unpacked_size} bytes\n")
    print("Files to bundle:")
    for path in bundle_files:
        print(f"  {path}")
    print(flush=True)

    with tempfile.TemporaryDirectory(prefix="basic-ssg-license-backup-") as temp:
        backup_dir = Path(temp)
        backups: dict[Path, Path] = {}
        staged: list[Path] = []
        try:
            for source in license_sources:
                target = PLATFORM_DIR / source.name
                if target.exists():
                    backup = backup_dir / source.name
                    shutil.copy2(target, backup)
                    backups[target] = backup
                staged.append(target)
                shutil.copy2(source, target)
            subprocess.run(
                [
                    roc,
                    "bundle",
                    *bundle_files,
                    "--output-dir",
                    str(output_dir),
                    *roc_args,
                ],
                cwd=PLATFORM_DIR,
                check=True,
            )
        finally:
            for target in staged:
                backup = backups.get(target)
                if backup is None:
                    target.unlink(missing_ok=True)
                else:
                    shutil.copy2(backup, target)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from None
