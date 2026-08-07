#!/usr/bin/env python3
"""Archiver shim that delegates static archive creation to Zig."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys


def main() -> int:
    zig = os.environ.get("ZIG", "zig")
    executable = shutil.which(zig)
    if executable is None:
        raise SystemExit(f"error: could not find Zig executable {zig!r}")
    try:
        return subprocess.run(
            [executable, "ar", *sys.argv[1:]], check=False
        ).returncode
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
