"""Rewrite the platform reference in Roc app headers."""

from __future__ import annotations

import re
from pathlib import Path


PLATFORM_RE = re.compile(r'(?m)(\bplatform\s+)"[^"]+"')
APPLICATION_HEADER = re.compile(r"(?m)^\s*app\s+\[")


def update_apps(paths: list[Path], platform_url: str) -> list[Path]:
    roc_files: list[Path] = []
    for path in paths:
        if path.is_dir():
            roc_files.extend(sorted(path.rglob("*.roc")))
        elif path.suffix == ".roc":
            roc_files.append(path)
        else:
            raise SystemExit(f"Expected a Roc app or directory: {path}")
    roc_files = [
        path for path in roc_files
        if APPLICATION_HEADER.search(path.read_text(encoding="utf-8")) is not None
    ]
    if not roc_files:
        raise SystemExit("No Roc apps found")

    updated: list[Path] = []
    for roc_file in roc_files:
        source = roc_file.read_text(encoding="utf-8")
        rewritten, count = PLATFORM_RE.subn(
            lambda match: f'{match.group(1)}"{platform_url}"', source, count=1
        )
        if count != 1:
            raise SystemExit(
                f"Expected exactly one platform URL in {roc_file}, found {count}"
            )
        if rewritten != source:
            roc_file.write_text(rewritten, encoding="utf-8", newline="\n")
            updated.append(roc_file)
    return updated
