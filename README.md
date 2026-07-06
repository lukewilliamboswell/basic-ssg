# Static Site Generation for Roc

A platform for Static Site Generation. Parse a directory of markdown files, and then transform the content using [roc](https://www.roc-lang.org) into an html site that is ready to be served from a web server or [CDN](https://en.wikipedia.org/wiki/Content_delivery_network).

**Supported Targets**

The following targets are included in each release.

- MacOS aarch64 and x86_64
- Linux aarch64 and x86_64

If you would like an additional target, let me know because it's probably supported by [rustc](https://doc.rust-lang.org/beta/rustc/platform-support.html) and very easy to add.

## Getting Started

Ensure you have [installed the roc cli](https://www.roc-lang.org/install).

Use the latest [release](https://github.com/lukewilliamboswell/basic-ssg/releases) of this platform by replacing the URL in the header.

```roc
app [main!] { pf: platform "<REPLACE WITH URL TO PLATFORM RELEASE>" }

import pf.SSG
import pf.Path

main! : List(Str) => Try({}, [Exit(I32), PagesError(Str), ParseError(Str), WriteError(Str), ..])
main! = |args|
    match args.drop_first(1) {
        [input_dir_arg, output_dir_arg] => {
            input_dir = Path.unix(input_dir_arg)
            output_dir = Path.unix(output_dir_arg)

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
            _ = SSG.write_file!({ output_dir, output_path: page.output_path, content: page_html })?

            render_pages!(rest, output_dir)
        }
    }
```

`SSG.pages!` discovers markdown files recursively and returns `List(SSG.Page)`.
Each page has:

- `source_path : Path.Path`, the markdown source file.
- `output_path : Path.Path`, a path relative to the output directory with the extension rewritten to `.html`.
- `url : Str`, the site-absolute URL for the generated page.

The platform uses [`roc-lang/path`](https://github.com/roc-lang/path) for path values. The bundled targets are Unix-like, so examples that convert CLI strings use `Path.unix`; use `Path.unix_bytes` when preserving raw Unix path bytes matters.

## Platform Development

Ensure you have [roc](https://www.roc-lang.org/install) & [cargo](https://doc.rust-lang.org/cargo/getting-started/installation.html) installed.

Using nix (optional)

```
$ nix develop
```

```
$ ./build.sh
$ roc check ./example/main.roc
$ roc build ./example/main.roc --output=./example/main
$ ./example/main ./example/content/ ./example/www/
```

Regenerate Rust glue after changing hosted Roc signatures:

```
$ ./ci/regenerate_glue.sh
```

You can generate a new package for distribution using `./bundle.sh --release`.
