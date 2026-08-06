#!/usr/bin/env python3
"""Tests for deterministic Rust glue specification resolution."""

from __future__ import annotations

import io
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from glue import (
    find_glue_spec,
    generated_source_matches,
    materialize_remote_spec,
)


class GlueSpecTests(unittest.TestCase):
    def temporary_directory(self) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        return Path(temporary.name)

    @patch("glue.pinned_roc", return_value=("nightly-test", "61bbb59"))
    def test_default_spec_matches_the_pinned_revision(
        self, _pinned_roc: object
    ) -> None:
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(
                find_glue_spec(),
                "https://raw.githubusercontent.com/roc-lang/roc/"
                "61bbb59/src/glue/src/RustGlue.roc",
            )

    @patch("glue.urlopen", return_value=io.BytesIO(b"app [make_glue]\n"))
    def test_downloads_remote_spec_as_a_local_source(self, opener: object) -> None:
        directory = self.temporary_directory()
        url = "https://example.com/RustGlue.roc"

        result = Path(materialize_remote_spec(url, directory))

        self.assertEqual(result, directory / "RustGlue.roc")
        self.assertEqual(result.read_bytes(), b"app [make_glue]\n")
        opener.assert_called_once_with(url, timeout=30)

    @patch("glue.urlopen")
    def test_keeps_local_specs_local(self, opener: object) -> None:
        self.assertEqual(materialize_remote_spec("spec.roc", Path("unused")), "spec.roc")
        opener.assert_not_called()

    def test_generated_source_comparison_ignores_native_newlines(self) -> None:
        directory = self.temporary_directory()
        committed = directory / "committed.rs"
        generated = directory / "generated.rs"
        committed.write_bytes(b"pub struct Value;\nimpl Value {}\n")
        generated.write_bytes(b"pub struct Value;\r\nimpl Value {}\r\n")

        self.assertTrue(generated_source_matches(committed, generated))

        generated.write_bytes(b"pub struct Other;\r\nimpl Value {}\r\n")
        self.assertFalse(generated_source_matches(committed, generated))


if __name__ == "__main__":
    unittest.main()
