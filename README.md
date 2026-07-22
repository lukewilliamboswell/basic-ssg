[![Roc-Lang][roc_badge]][roc_link]

[roc_badge]: https://img.shields.io/endpoint?url=https%3A%2F%2Fpastebin.com%2Fraw%2FcFzuCCd7
[roc_link]: https://github.com/roc-lang/roc

# Basic SSG

`basic-ssg` is a Roc platform for static site generators. It discovers
Markdown files, renders Markdown to HTML, and writes the generated files to an
output directory.

Application authors normally use a published platform release by putting the
release URL in the app header. The examples in this repository use a relative
`../platform/main.roc` path only because they exercise the local checkout.

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

Run the generated app with an input content directory and an output directory:

```sh
roc build site.roc --output=site
./site content/ www/
```

## API

`SSG.pages!` discovers Markdown files recursively and returns `List(SSG.Page)`.
Each page has:

- `source_path : Path.Path`, the Markdown source file.
- `output_path : Path.Path`, a path relative to the output directory with the
  extension rewritten to `.html`.
- `url : Str`, the site-absolute URL for the generated page.

`SSG.parse_markdown!` renders a Markdown file to an HTML string.

`SSG.write_file!` writes generated content underneath an output directory,
creating parent directories as needed.

The bundled `Html` module escapes `Html.text` content and attribute values by
default. Use `Html.raw` only for trusted markup, including
`SSG.parse_markdown!` output only when the source Markdown is trusted. Render
complete pages with `Html.render_document`, or markup fragments without a
doctype using `Html.render_fragment`. HTML void elements such as `meta`, `img`,
and `input` accept attributes but no children.

The platform uses [`roc-lang/path`][roc-path] for path values and passes command
line arguments as `OsStr`, preserving native Unix bytes or Windows UTF-16.
Use `Path.from_os_str` for path arguments and `Path.utf8` for portable text
paths created by the application.

## Examples

- [`example/main.roc`](example/main.roc) is a fuller site generator that renders
  pages with the bundled `Html` API.
- [`example/error-handling.roc`](example/error-handling.roc) shows infix `?` for
  mapping platform errors into an app error, postfix `?` for propagation, and
  `??` for a boundary fallback.

## Supported Targets

Published releases include these targets:

| Operating system | Architecture | Bundle target |
| --- | --- | --- |
| macOS | Apple Silicon | `arm64mac` |
| macOS | Intel | `x64mac` |
| Linux (musl) | ARM64 | `arm64musl` |
| Linux (musl) | x86_64 | `x64musl` |

Contributor setup, local platform development, glue regeneration, and release
bundling are covered in [CONTRIBUTING.md](CONTRIBUTING.md).

[releases]: https://github.com/lukewilliamboswell/basic-ssg/releases
[roc-path]: https://github.com/roc-lang/path
