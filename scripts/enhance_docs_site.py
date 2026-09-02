#!/usr/bin/env python3
"""Add shared, client-side enhancements to generated Roc documentation."""

from __future__ import annotations

import argparse
import os
from pathlib import Path

STYLESHEET_MARKUP = '<link rel="stylesheet" href="{source}">'
SCRIPT_MARKUP = '<script type="module" src="{source}"></script>'


def enhance_html(site: Path, html: Path) -> bool:
    document = html.read_text(encoding="utf-8")
    if "roc-highlight.js" in document and "roc-highlight.css" in document:
        return False
    relative_script = os.path.relpath(site / "roc-highlight.js", html.parent).replace(os.sep, "/")
    relative_stylesheet = os.path.relpath(site / "roc-highlight.css", html.parent).replace(os.sep, "/")
    stylesheet = STYLESHEET_MARKUP.format(source=relative_stylesheet)
    script = SCRIPT_MARKUP.format(source=relative_script)
    if "roc-highlight.css" not in document:
        if "</head>" not in document:
            raise ValueError(f"cannot enhance {html}: missing </head>")
        document = document.replace("</head>", f"    {stylesheet}\n</head>", 1)
    if "roc-highlight.js" in document:
        html.write_text(document, encoding="utf-8")
        return True
    if "</body>" not in document:
        raise ValueError(f"cannot enhance {html}: missing </body>")
    html.write_text(document.replace("</body>", f"    {script}\n</body>", 1), encoding="utf-8")
    return True


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("site", type=Path, help="assembled Pages site directory")
    args = parser.parse_args()
    site = args.site.resolve()
    for asset in ("roc-highlight.js", "roc-highlight.css"):
        if not (site / asset).is_file():
            raise SystemExit(f"Missing highlighter asset: {site / asset}")

    changed = sum(enhance_html(site, html) for html in site.rglob("*.html"))
    print(f"Added Roc syntax highlighting to {changed} HTML files")


if __name__ == "__main__":
    main()
