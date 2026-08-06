#!/usr/bin/env python3
"""Tests for the example behavior runner."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import test as test_runner


class ValgrindTests(unittest.TestCase):
    def test_command_keeps_valgrind_output_separate(self) -> None:
        with tempfile.TemporaryDirectory() as raw_directory:
            temporary = Path(raw_directory)
            binary = Path("/tmp/app")
            command, log = test_runner.process_command(
                binary, ["one", "two"], temporary, valgrind=True
            )

            self.assertEqual(command[0:2], ["valgrind", "--tool=memcheck"])
            self.assertEqual(command[-3:], [str(binary), "one", "two"])
            self.assertIn(f"--log-file={temporary / 'valgrind.log'}", command)
            self.assertEqual(log, temporary / "valgrind.log")

    def test_plain_command_has_no_log(self) -> None:
        binary = Path("/tmp/app")
        command, log = test_runner.process_command(
            binary, ["argument"], Path("/tmp"), valgrind=False
        )

        self.assertEqual(command, [str(binary), "argument"])
        self.assertIsNone(log)

    def test_log_requires_observed_allocations_and_no_errors(self) -> None:
        with tempfile.TemporaryDirectory() as raw_directory:
            log = Path(raw_directory) / "valgrind.log"
            log.write_text(
                "total heap usage: 1,234 allocs, 1,234 frees, 99 bytes allocated\n"
                "definitely lost: 0 bytes in 0 blocks\n"
                "indirectly lost: 0 bytes in 0 blocks\n"
                "ERROR SUMMARY: 0 errors from 0 contexts\n",
                encoding="utf-8",
            )
            test_runner.validate_valgrind_log(log, "case")

            log.write_text(
                "total heap usage: 0 allocs, 0 frees, 0 bytes allocated\n"
                "definitely lost: 0 bytes in 0 blocks\n"
                "indirectly lost: 0 bytes in 0 blocks\n"
                "ERROR SUMMARY: 0 errors from 0 contexts\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(SystemExit, "zero allocations"):
                test_runner.validate_valgrind_log(log, "case")

            log.write_text(
                "total heap usage: 10 allocs, 9 frees, 99 bytes allocated\n"
                "definitely lost: 0 bytes in 0 blocks\n"
                "indirectly lost: 0 bytes in 0 blocks\n"
                "ERROR SUMMARY: 1 errors from 1 contexts\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(SystemExit, "reported an error"):
                test_runner.validate_valgrind_log(log, "case")

            log.write_text(
                "total heap usage: 10 allocs, 9 frees, 99 bytes allocated\n"
                "definitely lost: 8 bytes in 1 blocks\n"
                "indirectly lost: 4 bytes in 1 blocks\n"
                "ERROR SUMMARY: 2 errors from 2 contexts\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(SystemExit, "definitely lost"):
                test_runner.validate_valgrind_log(log, "case")

    def test_log_must_exist(self) -> None:
        with tempfile.TemporaryDirectory() as raw_directory:
            log = Path(raw_directory) / "missing.log"
            with self.assertRaisesRegex(SystemExit, "did not produce"):
                test_runner.validate_valgrind_log(log, "case")

    def test_log_accepts_all_heap_blocks_freed_summary(self) -> None:
        with tempfile.TemporaryDirectory() as raw_directory:
            log = Path(raw_directory) / "valgrind.log"
            log.write_text(
                "total heap usage: 15 allocs, 15 frees, 1,433 bytes allocated\n"
                "All heap blocks were freed -- no leaks are possible\n"
                "ERROR SUMMARY: 0 errors from 0 contexts\n",
                encoding="utf-8",
            )
            test_runner.validate_valgrind_log(log, "case")


if __name__ == "__main__":
    unittest.main()
