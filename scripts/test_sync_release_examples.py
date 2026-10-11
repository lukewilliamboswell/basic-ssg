#!/usr/bin/env python3
"""Tests for refreshing examples-release from examples-dev."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from sync_release_examples import release_platform_url, sync
from test import STAGES

PIN = "nightly-2026-09-01-db83307"
URL = "https://example.invalid/new.tar.zst"


class SyncReleaseExamplesTests(unittest.TestCase):
    def test_derives_immutable_url_from_single_bundle_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "bundles.json"
            manifest.write_text(json.dumps([{"artifact_file": "hash.tar.zst"}]))
            self.assertEqual(
                release_platform_url(manifest, "1.2.3", "owner/repository"),
                "https://github.com/owner/repository/releases/download/1.2.3/hash.tar.zst",
            )

    def test_rejects_ambiguous_release_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "bundles.json"
            manifest.write_text("[]")
            with self.assertRaisesRegex(SystemExit, "exactly one"):
                release_platform_url(manifest, "1.2.3", "owner/repository")

    def test_replaces_release_examples_and_points_apps_at_the_release(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            dev, release = root / "examples-dev", root / "examples-release"
            content = dev / "app" / "content" / "snippet.roc"
            content.parent.mkdir(parents=True)
            content.write_text(f'app [f] {{ pf: platform "platform/main.roc", roc: "{PIN}" }}\n')
            (dev / "app" / "main.roc").write_text(
                f'app [main!] {{ pf: platform "../../platform/main.roc", roc: "{PIN}" }}\n'
            )
            (dev / "app" / "output").mkdir()
            (dev / "test_spec.json").write_text(json.dumps({
                "stages": {stage: True for stage in STAGES},
                "apps": [{"path": "app/main.roc", "cases": [{"name": "case"}]}],
            }))
            (release / "removed").mkdir(parents=True)

            sync(URL, dev, release)

            self.assertEqual(
                (release / "app" / "main.roc").read_text(),
                f'app [main!] {{ pf: platform "{URL}", roc: "{PIN}" }}\n',
            )
            self.assertEqual((release / "app" / "content" / "snippet.roc").read_text(), content.read_text())
            self.assertTrue((release / "test_spec.json").is_file())
            self.assertFalse((release / "removed").exists())
            self.assertFalse((release / "app" / "output").exists())


if __name__ == "__main__":
    unittest.main()
