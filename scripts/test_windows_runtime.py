"""Manifest rejection tests, plus executable ABI checks on Windows."""
import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import build
import bundle
import windows_runtime as runtime


class ProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.output = Path(self.temporary.name)
        for name in (*runtime.LIBRARIES, "host.lib"):
            (self.output / name).write_bytes(name.encode())
        license_file = runtime.notice(self.output, "license.txt", b"original license")
        components = {"fixture": {
            "license": "MIT", "license_files": [license_file],
            "redistribution_basis": "fixture", "sources": [{"sha256": "fixture"}],
            "build_commands": [["fixture"]],
        }}
        runtime.write_manifest(self.output, components,
                               {name: "fixture" for name in (*runtime.LIBRARIES, "host.lib")})

    def test_complete_inventory_returns_notices(self):
        self.assertEqual(len(runtime.validate(self.output)), 2)

    def test_tampered_library_rejected(self):
        (self.output / "host.lib").write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "library hash mismatch"):
            runtime.validate(self.output)

    def test_tampered_notice_rejected(self):
        (self.output / "licenses/license.txt").write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "license hash mismatch"):
            runtime.validate(self.output)

    def test_missing_and_empty_inputs_rejected(self):
        (self.output / runtime.LIBRARIES[0]).write_bytes(b"")
        with self.assertRaisesRegex(ValueError, "inventory mismatch"):
            runtime.validate(self.output)

    def test_unexpected_sdk_archive_rejected(self):
        (self.output / "libcmt.lib").write_bytes(b"unapproved")
        with self.assertRaisesRegex(ValueError, "inventory mismatch"):
            runtime.validate(self.output)

    def test_unrecorded_binary_inputs_rejected_recursively(self):
        for relative in ("startup.obj", "startup.o", "extra.a", "EXTRA.LIB",
                         "nested/startup.OBJ", "licenses/extra.a"):
            for contents in (b"", b"unrecorded"):
                with self.subTest(relative=relative, contents=contents):
                    path = self.output / relative
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(contents)
                    with self.assertRaisesRegex(ValueError, "inventory mismatch"):
                        runtime.validate(self.output)
                    path.unlink()

    def test_previous_outputs_removed_before_build(self):
        for relative in ("advapi32.lib", "startup.obj", "licenses/cargo/old-1.0.0/LICENSE"):
            (self.output / relative).parent.mkdir(parents=True, exist_ok=True)
            (self.output / relative).write_bytes(b"stale")
        runtime.remove_previous_outputs(self.output)
        remaining = {p.relative_to(self.output).as_posix() for p in self.output.rglob("*") if p.is_file()}
        self.assertEqual(remaining, {runtime.MANIFEST_NAME})

    def test_license_path_escape_rejected(self):
        path = self.output / runtime.MANIFEST_NAME
        manifest = json.loads(path.read_text())
        manifest["components"]["fixture"]["license_files"] = ["../outside.txt"]
        path.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError, "invalid Windows license"):
            runtime.validate(self.output)

    def test_missing_rights_evidence_rejected(self):
        path = self.output / runtime.MANIFEST_NAME
        manifest = json.loads(path.read_text())
        del manifest["components"]["fixture"]["redistribution_basis"]
        path.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError, "redistribution_basis"):
            runtime.validate(self.output)

    def test_combined_archive_still_requires_each_components_rights(self):
        path = self.output / runtime.MANIFEST_NAME
        manifest = json.loads(path.read_text())
        manifest["components"]["child"] = dict(manifest["components"]["fixture"])
        manifest["components"]["fixture"]["subcomponents"] = ["child"]
        del manifest["components"]["child"]["redistribution_basis"]
        path.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError, "redistribution_basis.*child"):
            runtime.validate(self.output)

    def test_vendored_sources_must_match_pinned_hashes(self):
        upstream = json.loads((runtime.SOURCE_DIR / "UPSTREAM.json").read_text())
        runtime.verify_vendored(upstream)
        for path in (("files", "tls.zig"), ("license_sha256",),
                     ("basic_cli", "files", "security.zig"), ("basic_cli", "license_sha256")):
            with self.subTest(path=path):
                changed = json.loads(json.dumps(upstream))
                group = changed
                for key in path[:-1]:
                    group = group[key]
                group[path[-1]] = "0" * 64
                with self.assertRaisesRegex(SystemExit, "Vendored source changed"):
                    runtime.verify_vendored(changed)

    def test_stdcall_normalization_preserves_ordinals(self):
        definition = runtime.normalize_definition("EXPORTS\n Foo@8 @123\n Bar @4 DATA\n")
        self.assertIn("Foo @123", definition)
        self.assertIn("Bar @4 DATA", definition)

    def test_dual_licensed_crates_need_one_reviewed_option(self):
        self.assertTrue(runtime.permissive("Apache-2.0 OR GPL-2.0-only"))
        self.assertTrue(runtime.permissive("(MIT OR Apache-2.0) AND Unicode-3.0"))
        self.assertFalse(runtime.permissive("MIT AND GPL-2.0-only"))
        self.assertFalse(runtime.permissive("GPL-2.0-only"))
        self.assertTrue(runtime.permissive("Apache-2.0 WITH LLVM-exception"))
        self.assertTrue(runtime.permissive("Apache-2.0 WITH LLVM-exception OR GPL-2.0-only"))
        self.assertFalse(runtime.permissive("GPL-2.0-only WITH LLVM-exception"))
        self.assertFalse(runtime.permissive("Apache-2.0 WITH Unreviewed-exception"))
        for expression in ("(MIT", "MIT WITH"):
            with self.assertRaisesRegex(ValueError, "Malformed"):
                runtime.permissive(expression)

    def test_zig_is_resolved_from_zig_and_version_checked(self):
        with patch.dict(os.environ, {"ZIG": "selected-zig"}), \
             patch.object(runtime.shutil, "which", return_value=str(self.output / "zig")) as which, \
             patch.object(runtime.subprocess, "check_output", return_value=runtime.ZIG_VERSION) as output:
            zig = runtime.resolve_zig()
            which.assert_called_once_with("selected-zig")
            output.assert_called_once_with([zig, "version"], text=True)
        with patch.object(runtime.shutil, "which", return_value="zig"), \
             patch.object(runtime.subprocess, "check_output", return_value="0.16.0"):
            with self.assertRaisesRegex(SystemExit, "require Zig"):
                runtime.resolve_zig()

    def test_inherited_rust_flags_preserved_and_dynamic_crt_selected(self):
        with patch.dict(os.environ, {"CARGO_ENCODED_RUSTFLAGS": "-Ctarget-feature=+crt-static\x1f-Cdebuginfo=1"}):
            env = build.windows_build_env()
        self.assertEqual(env["CARGO_ENCODED_RUSTFLAGS"].split("\x1f"),
                         ["-Ctarget-feature=+crt-static", "-Cdebuginfo=1", "-Ctarget-feature=-crt-static"])

    def test_declared_windows_inputs_match_producer_inventory(self):
        source = (runtime.ROOT / "platform/main.roc").read_text(encoding="utf-8")
        inputs = re.search(r"^\s*x64win:\s*\{\s*inputs:\s*\[(.*)\]", source, re.MULTILINE)[1]
        declared = set(re.findall(r'"([^"]+)"', inputs)) - {"app"}
        self.assertEqual(declared, set(bundle.TARGET_INPUTS["x64win"]))
        self.assertEqual(declared, set(runtime.LIBRARIES) | {"host.lib"})


@unittest.skipUnless(os.name == "nt", "native Windows ABI execution")
class WindowsRuntimeTests(unittest.TestCase):
    def test_startup_tls_initializers_cookie_and_metadata(self):
        zig = runtime.resolve_zig()
        scratch = runtime.ROOT / "target/windows-runtime-fixture"
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory() as temporary:
            inputs = Path(temporary)
            runtime.build(inputs)
            for fail_initializer in (False, True):
                obj = scratch / "fixture.obj"
                exe = scratch / "fixture.exe"
                compile_args = [zig, "cc", "-target", "x86_64-windows-msvc", "-O2",
                                "-fstack-protector-strong", "-c",
                                str(runtime.SOURCE_DIR / "runtime_fixture.c"), "-o", str(obj)]
                if fail_initializer:
                    compile_args.append("-DFAIL_INITIALIZER")
                subprocess.run(compile_args, check=True)
                subprocess.run([zig, "lld-link", "/nodefaultlib", "/subsystem:console",
                                "/entry:mainCRTStartup", "/machine:x64", "/opt:ref",
                                f"/out:{exe}", str(obj),
                                *(str(inputs / name) for name in runtime.LIBRARIES)], check=True)
                readobj = build.find_llvm_strip().with_name("llvm-readobj.exe")
                imports = subprocess.check_output([str(readobj), "--coff-imports", str(exe)], text=True)
                self.assertNotIn("vcruntime", imports.lower())
                self.assertNotIn("msvcp", imports.lower())
                result = subprocess.run([str(exe), "a b"], timeout=20)
                self.assertEqual(result.returncode, 255 if fail_initializer else 37)
                if not fail_initializer:
                    result = subprocess.run([str(exe), "fail"], timeout=20)
                    self.assertEqual(result.returncode & 0xffffffff, 0xc0000409)


if __name__ == "__main__":
    unittest.main()
