#!/usr/bin/env python3
"""cc-rs compiler shim that targets musl through Zig."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys


RUST_MUSL_TARGETS = {
    "x86_64-unknown-linux-musl",
    "aarch64-unknown-linux-musl",
}


def forwarded_args(args: list[str]) -> list[str]:
    forwarded: list[str] = []
    skip_next = False
    for arg in args:
        if skip_next:
            skip_next = False
            continue
        if arg.startswith(("--target=", "-target=")):
            continue
        if arg in {"-target", "--target"}:
            skip_next = True
            continue
        if arg in RUST_MUSL_TARGETS:
            continue
        forwarded.append(arg)
    return forwarded


def main() -> int:
    target = os.environ.get("ZIG_CC_TARGET")
    if not target:
        raise SystemExit(
            "error: ZIG_CC_TARGET must be set (for example, x86_64-linux-musl)"
        )
    zig = os.environ.get("ZIG", "zig")
    executable = shutil.which(zig)
    if executable is None:
        raise SystemExit(f"error: could not find Zig executable {zig!r}")
    command = [executable, "cc", "-target", target, *forwarded_args(sys.argv[1:])]
    try:
        return subprocess.run(command, check=False).returncode
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
