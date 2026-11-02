"""A local target bundle must declare exactly the host inputs it carries."""
import unittest
from pathlib import Path
import bundle

class TargetBundleTests(unittest.TestCase):
    def test_single_target_header_keeps_only_selected_native_host(self):
        source = (Path(__file__).resolve().parents[1] / "platform/main.roc").read_text()
        for target in bundle.TARGET_INPUTS:
            with self.subTest(target=target):
                staged = bundle.single_target_source(source, target)
                self.assertIn(f"\t\t{target}: {{ inputs:", staged)
                for other in set(bundle.TARGET_INPUTS) - {target}:
                    self.assertNotIn(f"\t\t{other}: {{ inputs:", staged)
                self.assertIn('inputs_dir: "targets/"', staged)

    def test_changed_target_syntax_cannot_silently_omit_a_host(self):
        with self.assertRaises(ValueError):
            bundle.single_target_source('platform ""\n', 'x64musl')
