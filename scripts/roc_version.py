#!/usr/bin/env python3
"""Validate the active Roc compiler against the repository nightly pin."""

from __future__ import annotations

import argparse
import os
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ROC_VERSION_FILE = ROOT / ".roc-version"
NIGHTLY_TAG_PATTERN = re.compile(
    r"nightly-[0-9]{4}-(?:[0-9]{2}|[A-Za-z]+)-[0-9]{2}-"
    r"(?P<revision>[0-9a-f]{7})"
)
ROC_REVISION_PATTERN = re.compile(r"\b[0-9a-f]{7,40}\b")


def pinned_roc(version_file: Path = ROC_VERSION_FILE) -> tuple[str, str]:
    try:
        values = version_file.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError as error:
        raise SystemExit(f"Missing Roc version file: {version_file}") from error
    if len(values) != 1:
        raise SystemExit(f"{version_file} must contain exactly one Roc nightly tag")

    tag = values[0]
    match = NIGHTLY_TAG_PATTERN.fullmatch(tag)
    if match is None:
        raise SystemExit(f"Invalid Roc nightly tag in {version_file}: {tag!r}")
    return tag, match.group("revision")


def version_matches_revision(version: str, expected_revision: str) -> bool:
    revisions = ROC_REVISION_PATTERN.findall(version.lower())
    return any(revision.startswith(expected_revision) for revision in revisions)


def active_roc_version(
    roc: str,
    *,
    env: dict[str, str] | None = None,
) -> str:
    try:
        return subprocess.check_output(
            [roc, "version"], cwd=ROOT, env=env, text=True
        ).strip()
    except FileNotFoundError as error:
        raise SystemExit(f"Roc executable not found: {roc}") from error


def require_pinned_roc(
    roc: str,
    *,
    env: dict[str, str] | None = None,
) -> str:
    tag, revision = pinned_roc()
    version = active_roc_version(roc, env=env)
    if not version_matches_revision(version, revision):
        raise SystemExit(f"Roc nightly {tag} is required; found {version!r}")
    return version


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--roc", default=os.environ.get("ROC", "roc"))
    args = parser.parse_args()
    tag, _revision = pinned_roc()
    version = require_pinned_roc(args.roc)
    print(f"Pinned Roc nightly: {tag}")
    print(f"Active compiler: {version}")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from None
