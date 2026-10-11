#!/usr/bin/env python3
"""Replace examples-release with examples-dev, pointed at a published platform bundle."""

from __future__ import annotations

import argparse
import json
import os
import shutil
from pathlib import Path

from test import DEV_EXAMPLES, RELEASE_EXAMPLES, load_spec
from update_app_platform_urls import update_apps


def release_platform_url(manifest_path: Path, release_version: str, repository: str) -> str:
    bundles = json.loads(manifest_path.read_text(encoding="utf-8"))
    if not isinstance(bundles, list) or len(bundles) != 1:
        count = len(bundles) if isinstance(bundles, list) else "non-list"
        raise SystemExit(f"Expected exactly one release bundle, found {count}")
    artifact_file = bundles[0].get("artifact_file")
    if not isinstance(artifact_file, str) or not artifact_file:
        raise SystemExit(f"{manifest_path}: bundle is missing artifact_file")
    return f"https://github.com/{repository}/releases/download/{release_version}/{artifact_file}"


def sync(platform_url: str, source: Path = DEV_EXAMPLES, destination: Path = RELEASE_EXAMPLES) -> None:
    """The copied apps keep their dev compiler pin, which is the compiler the release was built with."""
    spec = load_spec(source)
    shutil.rmtree(destination, ignore_errors=True)
    shutil.copytree(source, destination, ignore=shutil.ignore_patterns("output"))
    update_apps([destination / app["path"] for app in spec["apps"]], platform_url)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--platform-url")
    source.add_argument("--release-manifest", type=Path)
    parser.add_argument("--release-version", default=os.environ.get("RELEASE_VERSION"))
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY"))
    args = parser.parse_args()
    platform_url = args.platform_url
    if args.release_manifest is not None:
        if not args.release_version or not args.repository:
            parser.error("release manifest requires a release version and repository")
        platform_url = release_platform_url(args.release_manifest, args.release_version, args.repository)
    assert platform_url is not None
    sync(platform_url)
    print(f"Synced {RELEASE_EXAMPLES.name} from {DEV_EXAMPLES.name} with platform {platform_url}")


if __name__ == "__main__":
    main()
