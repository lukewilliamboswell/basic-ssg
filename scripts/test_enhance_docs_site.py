from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from enhance_docs_site import enhance_html, html_pages


class EnhanceDocsSiteTests(unittest.TestCase):
    def test_adds_depth_relative_assets_once(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            site = Path(directory)
            page = site / "main" / "SSG" / "index.html"
            page.parent.mkdir(parents=True)
            page.write_text("<html><head></head><body></body></html>", encoding="utf-8")

            self.assertTrue(enhance_html(site, page))
            document = page.read_text(encoding="utf-8")
            self.assertIn('href="../../roc-highlight.css"', document)
            self.assertIn('src="../../roc-highlight.js"', document)
            self.assertFalse(enhance_html(site, page))
            self.assertEqual(document, page.read_text(encoding="utf-8"))

    def test_skips_search_index_fragment(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            site = Path(directory)
            page = site / "main" / "index.html"
            index = site / "main" / "search-index.html"
            page.parent.mkdir(parents=True)
            page.write_text("<html><head></head><body></body></html>", encoding="utf-8")
            index.write_text('<meta charset="utf-8"><article></article>', encoding="utf-8")

            self.assertEqual(html_pages(site), [page])


if __name__ == "__main__":
    unittest.main()
