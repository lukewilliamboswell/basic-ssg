#!/usr/bin/env python3
"""Tests for reusable runtime-input packaging and verification."""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
import zipfile
from pathlib import Path

import runtime_inputs


class RuntimeInputsTests(unittest.TestCase):
    def fixture(self, *, extra: str | None = None, corrupt: bool = False) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        archive_path = Path(temporary.name) / "runtime.zip"
        files = []
        for name in runtime_inputs.EXPECTED_FILES:
            content = name.encode()
            files.append({"path": name, "sha256": hashlib.sha256(content).hexdigest(), "size": len(content)})
        manifest = {
            "schema": 1, "name": "basic-ssg-runtime-inputs", "version": "1.0.0",
            "zig_version": runtime_inputs.ZIG_VERSION, "files": files,
        }
        with zipfile.ZipFile(archive_path, "w") as archive:
            for name in runtime_inputs.EXPECTED_FILES:
                content = name.encode() + (b"corrupt" if corrupt and name == runtime_inputs.EXPECTED_FILES[0] else b"")
                runtime_inputs.zip_write(archive, name, content)
            runtime_inputs.zip_write(archive, "manifest.json", json.dumps(manifest).encode())
            runtime_inputs.zip_write(archive, "sbom.spdx.json", b"{}")
            runtime_inputs.zip_write(archive, "LICENSES/COPYING.MinGW-w64-runtime.txt", b"license")
            runtime_inputs.zip_write(archive, "LICENSES/THIRD_PARTY_LICENSES.md", b"licenses")
            if extra:
                runtime_inputs.zip_write(archive, extra, b"unexpected")
        return archive_path

    def test_verifies_exact_inventory_and_per_file_hashes(self) -> None:
        manifest = runtime_inputs.verify_archive(self.fixture())
        self.assertEqual(manifest["version"], "1.0.0")

    def test_rejects_outer_digest_mismatch(self) -> None:
        with self.assertRaisesRegex(SystemExit, "archive SHA-256"):
            runtime_inputs.verify_archive(self.fixture(), "0" * 64)

    def test_rejects_corrupt_runtime_input(self) -> None:
        with self.assertRaisesRegex(SystemExit, "digest mismatch"):
            runtime_inputs.verify_archive(self.fixture(corrupt=True))

    def test_rejects_unexpected_and_traversal_paths(self) -> None:
        for path in ("unexpected", "../escape"):
            with self.subTest(path=path):
                with self.assertRaisesRegex(SystemExit, "Unsafe|unexpected"):
                    runtime_inputs.verify_archive(self.fixture(extra=path))


if __name__ == "__main__":
    unittest.main()
