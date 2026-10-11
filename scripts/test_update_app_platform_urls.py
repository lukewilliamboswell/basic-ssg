#!/usr/bin/env python3
"""Tests for app platform reference updates."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from update_app_platform_urls import update_apps


class UpdateAppPlatformUrlsTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
