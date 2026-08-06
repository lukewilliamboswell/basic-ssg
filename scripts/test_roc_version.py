#!/usr/bin/env python3
"""Tests for repository Roc version validation."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from roc_version import pinned_roc, require_pinned_roc, version_matches_revision


class RocVersionTests(unittest.TestCase):
    def write_version(self, value: str) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        path = Path(temporary.name) / ".roc-version"
        path.write_text(value, encoding="utf-8")
        return path

    def test_reads_one_immutable_nightly_tag(self) -> None:
        path = self.write_version("nightly-2026-08-06-61bbb59\n")
        self.assertEqual(
            pinned_roc(path),
            ("nightly-2026-08-06-61bbb59", "61bbb59"),
        )

    def test_accepts_previous_month_name_tag_format(self) -> None:
        path = self.write_version("nightly-2026-August-05-24f0b47\n")
        self.assertEqual(
            pinned_roc(path),
            ("nightly-2026-August-05-24f0b47", "24f0b47"),
        )

    def test_rejects_extra_lines(self) -> None:
        path = self.write_version(
            "nightly-2026-08-06-61bbb59\nnightly-2026-08-07-deadbee\n"
        )
        with self.assertRaises(SystemExit):
            pinned_roc(path)

    def test_rejects_moving_or_malformed_versions(self) -> None:
        for value in (
            "nightly-new-compiler\n",
            "nightly-2026-August-5-24f0b47\n",
            "nightly-2026-8-06-61bbb59\n",
            "nightly-2026-August-05-24F0B47\n",
        ):
            with self.subTest(value=value):
                with self.assertRaises(SystemExit):
                    pinned_roc(self.write_version(value))

    def test_matches_the_full_compiler_revision(self) -> None:
        self.assertTrue(
            version_matches_revision(
                "Roc compiler version release-fast-24f0b476", "24f0b47"
            )
        )
        self.assertFalse(
            version_matches_revision(
                "Roc compiler version release-fast-deadbeef", "24f0b47"
            )
        )

    @patch(
        "roc_version.active_roc_version",
        return_value="Roc compiler version nightly-2026-08-06-61bbb59",
    )
    def test_accepts_the_pinned_compiler(self, _active_version: object) -> None:
        self.assertEqual(
            require_pinned_roc("roc"),
            "Roc compiler version nightly-2026-08-06-61bbb59",
        )

    @patch(
        "roc_version.active_roc_version",
        return_value="Roc compiler version release-fast-deadbeef",
    )
    def test_rejects_an_unpinned_compiler(self, _active_version: object) -> None:
        with self.assertRaisesRegex(SystemExit, "61bbb59"):
            require_pinned_roc("roc")


if __name__ == "__main__":
    unittest.main()
