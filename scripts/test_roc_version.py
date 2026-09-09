#!/usr/bin/env python3
"""Tests for repository Roc compiler header validation."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from roc_version import pinned_roc, require_pinned_roc, version_matches_revision


PIN = "nightly-2026-09-01-db83307"


class RocVersionTests(unittest.TestCase):
    def repository(self, sources: dict[str, str], *, legacy: bool = False) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        roots = []
        for relative, source in sources.items():
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(source, encoding="utf-8")
            roots.append(relative)
        config = root / ".github" / "roc-nightly.json"
        config.parent.mkdir()
        config.write_text(json.dumps({"workflows": ["ci.yml"], "compiler_roots": roots}))
        if legacy:
            (root / ".roc-version").write_text(PIN + "\n", encoding="utf-8")
        return root

    def test_reads_agreeing_app_and_platform_header_pins(self) -> None:
        root = self.repository({
            "platform/main.roc": f'platform "" packages {{ roc: "{PIN}" }}',
            "examples/hello/main.roc": f'app [main!] {{ roc: "{PIN}" }}',
        })
        self.assertEqual(pinned_roc(root), (PIN, "db83307"))

    def test_rejects_disagreeing_header_pins(self) -> None:
        root = self.repository({
            "platform/main.roc": f'platform "" packages {{ roc: "{PIN}" }}',
            "examples/hello/main.roc": 'app [main!] { roc: "nightly-2026-09-08-39a3f89" }',
        })
        with self.assertRaisesRegex(SystemExit, "disagree"):
            pinned_roc(root)

    def test_rejects_missing_or_malformed_pin(self) -> None:
        for source in ('app [main!] { pf: platform "main.roc" }', 'app [main!] { roc: "nightly-new-compiler" }'):
            with self.subTest(source=source):
                root = self.repository({"examples/hello/main.roc": source})
                with self.assertRaises(SystemExit):
                    pinned_roc(root)

    def test_rejects_legacy_version_file(self) -> None:
        root = self.repository(
            {"platform/main.roc": f'platform "" packages {{ roc: "{PIN}" }}'}, legacy=True
        )
        with self.assertRaisesRegex(SystemExit, "legacy .roc-version"):
            pinned_roc(root)

    def test_matches_the_full_compiler_revision(self) -> None:
        self.assertTrue(version_matches_revision("Roc compiler version release-fast-db833074", "db83307"))
        self.assertFalse(version_matches_revision("Roc compiler version release-fast-deadbeef", "db83307"))

    @patch("roc_version.active_roc_version", return_value=f"Roc compiler version {PIN}")
    @patch("roc_version.pinned_roc", return_value=(PIN, "db83307"))
    def test_accepts_the_pinned_compiler(self, _pinned: object, _active: object) -> None:
        self.assertEqual(require_pinned_roc("roc"), f"Roc compiler version {PIN}")

    @patch("roc_version.active_roc_version", return_value="Roc compiler version release-fast-deadbeef")
    @patch("roc_version.pinned_roc", return_value=(PIN, "db83307"))
    def test_rejects_an_unpinned_compiler(self, _pinned: object, _active: object) -> None:
        with self.assertRaisesRegex(SystemExit, "db83307"):
            require_pinned_roc("roc")


if __name__ == "__main__":
    unittest.main()
