#!/usr/bin/env python3
"""Restore versioned API docs from docs.tar.gz assets on published releases."""

from __future__ import annotations

import argparse
import os
import subprocess
import tarfile
import tempfile
from pathlib import Path


ASSET = "docs.tar.gz"


def gh(*args: str) -> str:
    result = subprocess.run(["gh", *args], text=True, capture_output=True)
    if result.returncode:
        raise SystemExit(result.stderr.strip() or f"gh {' '.join(args)} failed")
    return result.stdout


def releases(repository: str) -> list[str]:
    output = gh(
        "api",
        "--paginate",
        f"repos/{repository}/releases?per_page=100",
        "--jq",
        f'.[] | select(.draft == false) | select([.assets[].name] | index("{ASSET}")) | .tag_name',
    )
    return [line for line in output.splitlines() if line]


def extract(archive: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive, "r:gz") as tar:
        members = []
        for member in tar.getmembers():
            parts = Path(member.name).parts
            if len(parts) < 2:
                continue
            relative = Path(*parts[1:])
            if relative.is_absolute() or ".." in relative.parts:
                raise SystemExit(f"unsafe docs archive member: {member.name}")
            member.name = relative.as_posix()
            members.append(member)
        if not members:
            raise SystemExit(f"docs archive is empty: {archive}")
        tar.extractall(destination, members=members, filter="data")


def restore(root: Path, repository: str) -> None:
    root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as temporary:
        download_root = Path(temporary)
        for release in releases(repository):
            release_root = download_root / release
            release_root.mkdir()
            gh("release", "download", release, "--repo", repository, "--pattern", ASSET, "--dir", str(release_root))
            extract(release_root / ASSET, root / release)
            print(f"Restored API docs for {release}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("docs_root", type=Path)
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY", "lukewilliamboswell/basic-ssg"))
    args = parser.parse_args()
    restore(args.docs_root, args.repository)


if __name__ == "__main__":
    main()
