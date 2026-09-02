[![Roc-Lang][roc_badge]][roc_link]

[roc_badge]: https://img.shields.io/endpoint?url=https%3A%2F%2Fpastebin.com%2Fraw%2FcFzuCCd7
[roc_link]: https://github.com/roc-lang/roc

# Basic SSG

`basic-ssg` is a Roc platform for static site generators. It discovers source
files, decodes application-defined page formats, renders Markdown when wanted,
and writes generated files to an output directory. Markdown remains the
zero-configuration default.

Application authors normally use a published platform release by putting the
release URL in the app header. The examples in this repository use a relative
platform path only because they exercise the local checkout.

## Getting Started

Install the [Roc CLI](https://www.roc-lang.org/install), then copy a platform
URL from the [basic-ssg releases][releases] page into your app header.

```roc
app [main!] { pf: platform "<basic-ssg release URL>" }

import pf.Path
import pf.OsStr exposing [OsStr]
import pf.SSG

main! : List(OsStr) => Try({}, [Exit(I32), PagesError(Str), ParseError(Str), WriteError(Str), ..])
main! = |args|
	match args.drop_first(1) {
		[input_dir_arg, output_dir_arg] => {
			input_dir = Path.from_os_str(input_dir_arg)
			output_dir = Path.from_os_str(output_dir_arg)

			pages = SSG.pages!(input_dir)?
			render_pages!(pages, output_dir)
		}

		_ => Err(Exit(1))
	}

render_pages! : List(SSG.Page), Path.Path => Try({}, [ParseError(Str), WriteError(Str), ..])
render_pages! = |pages, output_dir|
	match pages {
		[] => Ok({})
		[page, .. as rest] => {
			markdown_html = SSG.parse_markdown!(page.source_path)?
			page_html = "<!doctype html><html><body>${markdown_html}</body></html>"

			SSG.write_file!({
				output_dir,
				output_path: page.output_path,
				content: page_html,
			})?

			render_pages!(rest, output_dir)
		}
	}
```

Run the generated app with an input content directory and an output directory.
On macOS and Linux:

```sh
roc build site.roc --output=site
./site content/ www/
```

On Windows PowerShell, give the executable its native suffix:

```powershell
roc build site.roc --output=site.exe
.\site.exe .\content .\www
```

## API

`SSG.pages!` discovers Markdown files recursively and returns `List(SSG.Page)`.
Each page has:

- `source_path : Path.Path`, the application-defined page source file.
- `output_path : Path.Path`, a path relative to the output directory with the
  extension rewritten to `.html`.
- `url : Str`, the site-absolute URL for the generated page.

`SSG.parse_markdown!` renders a Markdown file to an HTML string.

AsciiDoc is also first-class. `SSG.asciidoc_pages!` discovers `.adoc` files,
`SSG.parse_asciidoc!` parses a file, and `SSG.parse_asciidoc_source!` parses a
string into an `AsciiDoc.Document`. Applications may inspect its resolved block
and inline semantics and warnings, customize rendering with
`AsciiDoc.view_block`/`AsciiDoc.view_inlines`, or use the Asciidoctor-like
default fragment from `AsciiDoc.render`. `SSG.render_asciidoc!` combines parsing
and default rendering for source strings.

`SSG.pages_with!` discovers another source extension, such as `json`, and maps
each source path to an `.html` output path. `SSG.decode_page!` reads the source
as UTF-8 and runs an application-supplied pure or effectful decoder.

`SSG.render_markdown!` renders Markdown supplied as text, resolving replacement
directives relative to a supplied source path. This lets a decoder strip and
parse frontmatter before rendering only the Markdown body.

`SSG.write_file!` writes generated content underneath an output directory,
creating parent directories as needed.

## Pluggable Page Decoders

`PageDecoder.Decoder(page, value, err)` is an effectful function from a page
and its source text to a typed value. The platform does not prescribe the
source format: pass `Json.parse`, a YAML parser, or a custom decoder using
`PageDecoder.from_source` or `PageDecoder.from_effect`.

Independent decoders compose with Roc's applicative record-builder syntax:

```roc
JsonPage : { title : Str, body : Str }

page_decoder! = {
	content: PageDecoder.from_source(Json.parse),
	generated_at: PageDecoder.from_effect(|_| Ok(Utc.now!())),
	page: PageDecoder.page!,
}.PageDecoder

decoded = SSG.decode_page!(page, page_decoder!)?
```

A frontmatter decoder uses the same interface. It splits the source into a
metadata string and body, applies the application's chosen metadata parser,
then can call `SSG.render_markdown!` on the body. Replacing `Json.parse` with a
YAML parser does not require a platform change. Whole-file JSON and frontmatter
Markdown pages can coexist in one build by discovering both extensions.

`PageDecoder.map2` runs fields from left to right and stops at the first error,
so effectful decoder fields retain normal `?` sequencing. The expected output
type supplies Roc's `parser_for` constraint to `Json.parse`; a different parser
can impose its own constraints without involving the platform.

The bundled `Html` module escapes `Html.text` content and attribute values by
default. Use `Html.raw` only for trusted markup, including Markdown or AsciiDoc
output only when the source is trusted. AsciiDoc secure mode prevents external
resource loading but does not sanitize passthroughs or attribute-generated HTML. Render
complete pages with `Html.render_document`, or markup fragments without a
doctype using `Html.render_fragment`. HTML void elements such as `meta`, `img`,
and `input` accept attributes but no children.

The platform uses [`roc-lang/path`][roc-path] for path values and passes command
line arguments as `OsStr`, preserving native Unix bytes or Windows UTF-16.
Use `Path.from_os_str` for path arguments and `Path.utf8` for portable text
paths created by the application.

## Examples

- [`examples/orchard-guide`](examples/orchard-guide) is a complete Markdown and AsciiDoc site
  with nested pages, navigation, styling, syntax highlighting, and neighboring
  source inclusion.
- [`examples/article-inspector`](examples/article-inspector) is a focused CLI
  utility that maps platform failures into an application error and prints a
  Markdown article's first heading.
- [`examples/travel-journal`](examples/travel-journal) builds whole-file JSON
  pages alongside Markdown pages with JSON frontmatter, deriving typed parsers
  and combining pure and effectful decoders with record-builder syntax.

## Supported Targets

Published releases include these targets:

| Operating system | Architecture | Bundle target |
| --- | --- | --- |
| macOS | Apple Silicon | `arm64mac` |
| macOS | Intel | `x64mac` |
| Linux (musl) | ARM64 | `arm64musl` |
| Linux (musl) | x86_64 | `x64musl` |
| Windows | x86-64 | `x64win` |

Contributor setup, local platform development, glue regeneration, and release
bundling are covered in [CONTRIBUTING.md](CONTRIBUTING.md).

[releases]: https://github.com/lukewilliamboswell/basic-ssg/releases
[roc-path]: https://github.com/roc-lang/path
