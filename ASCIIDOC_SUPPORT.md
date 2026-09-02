# AsciiDoc support research and implementation direction

## Goal

Add AsciiDoc as a first-class content format alongside Markdown in `basic-ssg`,
using the Rust [`asciidoc-parser`](https://crates.io/crates/asciidoc-parser)
crate. Keep Markdown as the zero-configuration default and expose parallel Roc
APIs for discovering and rendering `.adoc` pages.

As part of this work, update `.roc-version` from
`nightly-2026-08-06-61bbb59` to the latest compiler already validated in the
related parser work:

```text
nightly-2026-09-01-db83307
```

The Roc update must be made before regenerating the checked-in Rust ABI glue,
because `scripts/glue.py` selects the glue specification from the revision in
`.roc-version`.

## Repository findings

`basic-ssg` is a Rust-backed Roc platform. Markdown rendering lives in
`src/ssg.rs`, is exported through hosted functions in `src/lib.rs`, declared in
`platform/Host.roc`, and wrapped for applications in `platform/SSG.roc`.
`src/roc_platform_abi.rs` is generated and checked in; it must be regenerated
after changing the hosted Roc interface.

The existing public Markdown API is:

```roc
SSG.pages! : Path.Path => Try(List(SSG.Page), [PagesError(Str), ..])
SSG.parse_markdown! : Path.Path => Try(Str, [ParseError(Str), ..])
SSG.render_markdown! : { source_path : Path.Path, markdown : Str } => Try(Str, [ParseError(Str), ..])
```

`pages!` is only a convenience wrapper for `pages_with!` using the `md`
extension. Page discovery is already generic, so AsciiDoc discovery does not
need a new host effect.

The host currently pins every direct Rust dependency exactly and records
third-party licensing in `THIRD_PARTY_LICENSES.md`. CI validates Roc formatting,
generated glue, Rust formatting/tests/clippy, platform builds, examples, and
generated Roc documentation.

## Crate selection and constraints

Use an exact dependency on `asciidoc-parser = "=0.30.0"`. As of 2 September
2026 this is the latest crates.io release. It is licensed under MIT or
Apache-2.0, requires Rust 1.88, and therefore fits the repository's Rust 1.97
toolchain.

The crate provides a semantic `Parser`, a typed `Document`/block model, source
locations, warnings, attributes, cross-reference resolution, preprocessing,
and Asciidoctor-like inline HTML substitutions. It defaults to
`SafeMode::Secure`.

The crate does **not** provide a one-call, block-level document-to-HTML API.
Although inline content is available in rendered form, `basic-ssg` must walk
the public document/block model and generate the surrounding HTML elements.
This renderer should return an HTML fragment, matching
`SSG.render_markdown!`, rather than a complete HTML document.

The parser deliberately permits raw HTML through passthroughs and attribute
substitution. Its safe mode controls external file access, not HTML safety.
AsciiDoc output must therefore carry the same trusted-content warning already
documented for Markdown and `Html.raw`.

For the first implementation, retain the default secure mode and do not install
include, image-file, SVG-file, docinfo, or network handlers. This avoids giving
AsciiDoc sources filesystem or network access. Ordinary image and link targets
remain references in generated HTML.

## Implemented public API

Add these application-facing functions without changing the existing Markdown
functions:

```roc
SSG.asciidoc_pages! : Path.Path => Try(List(SSG.Page), [PagesError(Str), ..])
SSG.parse_asciidoc! : Path.Path => Try(AsciiDoc.Document, [ParseError(Str), ..])
SSG.parse_asciidoc_source! : { source_path : Path.Path, asciidoc : Str } => Try(AsciiDoc.Document, [ParseError(Str), ..])
SSG.render_asciidoc! : { source_path : Path.Path, asciidoc : Str } => Try(Str, [ParseError(Str), ..])
```

`asciidoc_pages!` delegates to `pages_with!` with `source_extension: "adoc"`.
The two render functions mirror their Markdown equivalents so applications can
render whole files or frontmatter-stripped bodies with the same control flow.
`source_path` supplies source identity and a future base for safely resolved
local resources; it must not enable resource loading in the initial release.

The parser returns the document to the Roc application. `AsciiDoc` exposes the
resolved document, block and inline model plus `view`, `render`, `view_block`,
and `view_inlines`; an application can use the default renderer or replace it.
`Html.Fragment` represents sibling output without an artificial wrapper.

The matching closed host declarations and direct symbols are:

```roc
Host.ssg_parse_asciidoc! : Raw => Try(AsciiDoc.Document, [ParseError(Str)])
Host.ssg_parse_asciidoc_source! : Raw, Str => Try(AsciiDoc.Document, [ParseError(Str)])
```

The Rust ABI ownership and result construction should exactly mirror the two
Markdown hosted functions, including decrementing incoming Roc values on every
success and error path.

## Initial renderer scope

Render the common article subset needed for static sites:

- document title/preamble and nested sections with stable IDs;
- paragraphs and inline formatting already rendered by the crate;
- unordered, ordered, and description lists, including nested blocks;
- literal, listing/source, quote, verse, example, sidebar, and open blocks;
- admonitions, thematic/page breaks, images, audio/video, and tables;
- block titles, roles, IDs, links, anchors, and cross-references;
- passthrough/raw blocks with the documented trusted-input semantics.

Reuse the existing Roc and `syntect` highlighting helpers for AsciiDoc source
blocks. A source block whose language is `roc` uses `roc_syntax`; recognized
other languages use `syntect`; unknown or absent languages are HTML-escaped.
Do not implement complete-document themes, embedded stylesheets, non-article
doctypes, extensions, remote includes, or sanitization in this change.

Treat parser warnings as non-fatal, consistent with the crate's model. Fatal
host errors cover UTF-8 file reads and failures that prevent rendering. If the
crate represents malformed input with warnings and a recoverable document,
return the rendered fragment rather than converting warnings into
`ParseError`.

## Implementation and validation

1. Update `.roc-version`, run the full compatibility suite with the new Roc
   binary, and fix any compiler migration issues before changing the ABI.
2. Add and lock `asciidoc-parser = "=0.30.0"`; update
   `THIRD_PARTY_LICENSES.md` for it and any newly introduced transitive licenses.
3. Add the AsciiDoc parse/render implementation and a dedicated block renderer
   in the Rust host. Keep shared code highlighting and HTML escaping behavior
   consistent with Markdown.
4. Add the two hosted functions and Roc wrappers, then regenerate
   `src/roc_platform_abi.rs` using `scripts/glue.py` with the newly pinned Roc.
5. Add Rust unit tests for basic documents, sections, inline markup, lists,
   source highlighting, tables, warnings/malformed input, raw HTML, and secure
   include behavior. Test both source-string and file entry points.
6. Add an `.adoc` page to an end-to-end example and assert that discovery,
   rendering, output paths, and generated HTML work through the Roc API.
7. Update the README/API docs and trusted-content warning to cover both
   Markdown and AsciiDoc, then run `python scripts/all_tests.py` and the release
   readiness checks.

## Acceptance criteria

- Existing Markdown behavior and public APIs remain unchanged.
- `.md` and `.adoc` pages can coexist in one site build without output-order or
  path regressions.
- AsciiDoc rendering returns embeddable HTML fragments through both file and
  string APIs.
- Common AsciiDoc article constructs render deterministically, with existing
  syntax highlighting applied to source blocks.
- Includes and embedded local/remote assets cannot read from the host in the
  initial secure configuration.
- Generated Rust glue is current, licensing is documented, examples pass, and
  the complete repository test suite passes with
  `nightly-2026-09-01-db83307`.
