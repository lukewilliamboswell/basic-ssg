#!/usr/bin/env python3
"""Tests for public-example release URL updates."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from update_app_platform_urls import release_platform_url, update_apps


class UpdateAppPlatformUrlsTests(unittest.TestCase):
    def test_derives_immutable_url_from_single_bundle_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "bundles.json"
            manifest.write_text(json.dumps([{"artifact_file": "hash.tar.zst"}]))
            self.assertEqual(
                release_platform_url(manifest, "1.2.3", "owner/repository"),
                "https://github.com/owner/repository/releases/download/1.2.3/hash.tar.zst",
            )

    def test_updates_platform_without_changing_compiler_pin(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "main.roc"
            app.write_text(
                'app [main!] { roc: "nightly-2026-09-01-db83307", pf: platform "old" }\n'
            )
            update_apps([app], "https://example.invalid/new.tar.zst")
            source = app.read_text()
            self.assertIn('roc: "nightly-2026-09-01-db83307"', source)
            self.assertIn('platform "https://example.invalid/new.tar.zst"', source)

    def test_rejects_ambiguous_release_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "bundles.json"
            manifest.write_text("[]")
            with self.assertRaisesRegex(SystemExit, "exactly one"):
                release_platform_url(manifest, "1.2.3", "owner/repository")


if __name__ == "__main__":
    unittest.main()
