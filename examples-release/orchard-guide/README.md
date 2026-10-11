# The Orchard Guide

A conventional Markdown site with nested pages, navigation, trusted rendered
Markdown, a stylesheet, syntax highlighting, and neighboring source inclusion.

From the repository root, build, generate, and serve the site with the
cross-platform helper:

```sh
python scripts/serve_example.py
```

This serves the `examples-dev` copy against a local bundle of the checkout. Pass
`--release` to serve the `examples-release` copy with its published platform and
pinned compiler instead. Pass `--no-open` to keep the browser closed or
`--no-serve` to generate the site and exit.
