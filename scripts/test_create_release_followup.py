#!/usr/bin/env python3
"""Tests for release follow-up change validation."""

from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import create_release_followup as followup

EXAMPLE = "examples/app/main.roc"


def git(root: Path, *args: str) -> None:
    subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *args], cwd=root, check=True)


class ChangedExamplesTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        for path in (EXAMPLE, followup.PENDING_MARKER, "platform/main.roc"):
            (self.root / path).parent.mkdir(parents=True, exist_ok=True)
            (self.root / path).write_text("old\n")
        git(self.root, "init", "-q")
        git(self.root, "add", ".")
        git(self.root, "commit", "-q", "-m", "init")
        patcher = patch.object(followup, "ROOT", self.root)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_marker_deletion_is_allowed_with_example_changes(self) -> None:
        (self.root / EXAMPLE).write_text("new\n")
        (self.root / followup.PENDING_MARKER).unlink()
        self.assertEqual(followup.changed_examples(), ([EXAMPLE], [followup.PENDING_MARKER]))

    def test_example_changes_without_marker_are_allowed(self) -> None:
        (self.root / EXAMPLE).write_text("new\n")
        self.assertEqual(followup.changed_examples(), ([EXAMPLE], []))

    def test_other_deletions_are_rejected(self) -> None:
        (self.root / EXAMPLE).write_text("new\n")
        (self.root / "platform/main.roc").unlink()
        with self.assertRaisesRegex(ValueError, "only existing example files"):
            followup.changed_examples()

    def test_non_example_modifications_are_rejected(self) -> None:
        (self.root / EXAMPLE).write_text("new\n")
        (self.root / "platform/main.roc").write_text("new\n")
        with self.assertRaisesRegex(ValueError, "only existing example files"):
            followup.changed_examples()


if __name__ == "__main__":
    unittest.main()
