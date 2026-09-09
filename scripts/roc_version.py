#!/usr/bin/env python3
"""Resolve and validate the compiler pin declared by selected Roc headers."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
from pathlib import Path

import compiler_pins


ROOT = Path(__file__).resolve().parents[1]
NIGHTLY_TAG_PATTERN = re.compile(
    r"nightly-[0-9]{4}-[0-9]{2}-[0-9]{2}-(?P<revision>[0-9a-f]{7,40})"
)
ROC_REVISION_PATTERN = re.compile(r"\b[0-9a-f]{7,40}\b")


def pinned_roc(root: Path = ROOT, config_file: Path | None = None) -> tuple[str, str]:
    config_path = config_file or root / ".github" / "roc-nightly.json"
    try:
        config = json.loads(config_path.read_text(encoding="utf-8"))
        sources = compiler_pins.local_sources(root, config["compiler_roots"])
        if (root / ".roc-version").exists():
            raise ValueError("legacy .roc-version must be removed when using header pins")
        tag = compiler_pins.version(compiler_pins.discover(sources))
    except (FileNotFoundError, KeyError, json.JSONDecodeError, ValueError) as error:
        raise SystemExit(f"Could not resolve Roc compiler header pins: {error}") from error
    match = NIGHTLY_TAG_PATTERN.fullmatch(tag)
    if match is None:
        raise SystemExit(f"Development compiler must be an exact Roc nightly: {tag!r}")
    return tag, match.group("revision")


def version_matches_revision(version: str, expected_revision: str) -> bool:
    revisions = ROC_REVISION_PATTERN.findall(version.lower())
    return any(revision.startswith(expected_revision) for revision in revisions)


def active_roc_version(roc: str, *, env: dict[str, str] | None = None) -> str:
    try:
        return subprocess.check_output([roc, "version"], cwd=ROOT, env=env, text=True).strip()
    except FileNotFoundError as error:
        raise SystemExit(f"Roc executable not found: {roc}") from error


def require_pinned_roc(roc: str, *, env: dict[str, str] | None = None) -> str:
    tag, revision = pinned_roc()
    version = active_roc_version(roc, env=env)
    if not version_matches_revision(version, revision):
        raise SystemExit(f"Roc nightly {tag} is required; found {version!r}")
    return version


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--roc", default=os.environ.get("ROC", "roc"))
    parser.add_argument(
        "--print-tag", action="store_true",
        help="print only the agreed immutable header pin without running Roc",
    )
    args = parser.parse_args()
    tag, _revision = pinned_roc()
    if args.print_tag:
        print(tag)
        return
    version = require_pinned_roc(args.roc)
    print(f"Pinned Roc nightly: {tag}")
    print(f"Active compiler: {version}")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from None
