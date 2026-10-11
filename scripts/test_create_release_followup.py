#!/usr/bin/env python3
"""Tests for release follow-up change validation."""

from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import create_release_followup as followup

EXAMPLE = "examples-release/app/main.roc"
CONTENT = "examples-release/app/content/index.md"
REPO_ROOT = Path(__file__).resolve().parent.parent


def git(root: Path, *args: str) -> None:
    subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *args], cwd=root, check=True)


class ChangedExamplesTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        for path in (EXAMPLE, CONTENT, "examples-dev/app/main.roc", "platform/main.roc"):
            self.write(path, "old\n")
        git(self.root, "init", "-q")
        git(self.root, "add", ".")
        git(self.root, "commit", "-q", "-m", "init")
        patcher = patch.object(followup, "ROOT", self.root)
        patcher.start()
        self.addCleanup(patcher.stop)

    def write(self, path: str, text: str) -> None:
        (self.root / path).parent.mkdir(parents=True, exist_ok=True)
        (self.root / path).write_text(text)

    def test_release_example_additions_modifications_and_deletions_are_allowed(self) -> None:
        added = "examples-release/new/main.roc"
        self.write(EXAMPLE, "new\n")
        self.write(added, "new\n")
        (self.root / CONTENT).unlink()
        self.assertEqual(followup.changed_examples(), ([EXAMPLE, added], [CONTENT]))

    def test_no_changes_are_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "only examples-release files"):
            followup.changed_examples()

    def test_other_deletions_are_rejected(self) -> None:
        self.write(EXAMPLE, "new\n")
        (self.root / "platform/main.roc").unlink()
        with self.assertRaisesRegex(ValueError, "only examples-release files"):
            followup.changed_examples()

    def test_dev_example_and_untracked_changes_are_rejected(self) -> None:
        for path in ("examples-dev/app/main.roc", "untracked.txt"):
            with self.subTest(path=path):
                self.write(EXAMPLE, f"new {path}\n")
                self.write(path, "new\n")
                with self.assertRaisesRegex(ValueError, "only examples-release files"):
                    followup.changed_examples()
                git(self.root, "reset", "-q", "--hard")
                git(self.root, "clean", "-qfd")

    def test_ci_roc_install_and_cache_are_ignored(self) -> None:
        (self.root / ".gitignore").write_text((REPO_ROOT / ".gitignore").read_text())
        git(self.root, "add", ".gitignore")
        git(self.root, "commit", "-q", "-m", "ignore")
        self.write(EXAMPLE, "new\n")
        self.write(".roc-cache/nightly-2026-10-09-258ab27/mod/07/abc", "cache\n")
        self.write("roc_nightly-linux_x86_64-2026-10-09-258ab27/roc", "bin\n")
        self.assertEqual(followup.changed_examples(), ([EXAMPLE], []))


if __name__ == "__main__":
    unittest.main()
