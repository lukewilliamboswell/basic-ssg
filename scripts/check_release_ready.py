#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PLATFORM = ROOT / "platform" / "main.roc"
PATH_DEPENDENCY_RE = re.compile(r'(?m)^\s*path:\s*"([^"]+)"')
IMMUTABLE_RELEASE_RE = re.compile(
    r"https://github\.com/roc-lang/path/releases/download/"
    r"(?!latest(?:/|$))[^/]+/[^/]+\.tar\.zst"
)


def main() -> None:
    source = PLATFORM.read_text(encoding="utf-8")
    match = PATH_DEPENDENCY_RE.search(source)
    if match is None:
        raise SystemExit(f"{PLATFORM}: could not find the path package dependency")
    dependency = match.group(1)
    if IMMUTABLE_RELEASE_RE.fullmatch(dependency) is None:
        raise SystemExit(
            "Release blocked: platform/main.roc still uses the temporary path "
            f"dependency {dependency!r}. Publish roc-lang/path, replace it with "
            "its immutable GitHub release .tar.zst URL, and rerun the release."
        )
    print(f"Release dependency is immutable: {dependency}")


if __name__ == "__main__":
    main()
