# Static Site Generatation for Roc

A platform for Static Site Generation. Parse a directory of markdown files, and then transform the content using [roc](https://www.roc-lang.org) into an html site that is ready to be served from a web server or [CDN](https://en.wikipedia.org/wiki/Content_delivery_network).

**Supported Targets**

The following targets are included in each release. If you would like an additional target, let me know because it's probably supported by [rustc](https://doc.rust-lang.org/beta/rustc/platform-support.html) and easy to add.

- Arm64 MacOS
- Arm64 Linux
- x64 MacOS
- x64 Linux

## Getting Starting

Ensure you have [installed the roc cli](https://www.roc-lang.org/install).

Use the latest [release](https://github.com/lukewilliamboswell/basic-ssg/releases) of this platform by replacing the URL in the header.

```roc
app [main] { pf: platform "https://github.com/lukewilliamboswell/basic-ssg/releases/download/[REPLACE WITH LATEST RELEASE VERSION].tar.br" }

import pf.Task exposing [Task]
import pf.SSG
import pf.Types exposing [Args, toRelPath]
import pf.Html exposing [html, head, body, div, text, a, ul, li, link, meta]
import pf.Html.Attributes exposing [httpEquiv, content, href, rel, lang, class, title]
import "style.css" as styleCss : Str

main : Args -> Task {} _
main = \{ inputDir, outputDir } ->
    # ... use SSG.files!, SSG.parseMarkdown!, and SSG.writeFile! here to generate site
```

## Developing

Ensure you have [cargo and rustup installed](https://doc.rust-lang.org/cargo/getting-started/installation.html).

A few scripts are included to assist with common tasks.

- **run.sh** to build the platform in debug mode, and run the example
- **glue.sh** to re-generate glue types for the platform (note currently requires a copy of the roc repository)
- **bundle.sh** to cross-compile the platform in release mode for supported targets and package for distribution
