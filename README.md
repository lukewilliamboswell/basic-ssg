# Static Site Generatation for Roc

A platform for Static Site Generation. Parse a directory of markdown files, and then transform the content using [roc](https://www.roc-lang.org) into an html site that is ready to be served from a web server or [CDN](https://en.wikipedia.org/wiki/Content_delivery_network).

**Supported Targets**

The following targets are included in each release.

- MacOS aarch64 and x86_64
- Linux aarch64 and x86_64

If you would like an additional target, let me know because it's probably supported by [rustc](https://doc.rust-lang.org/beta/rustc/platform-support.html) and very easy to add.

## Getting Starting

Ensure you have [installed the roc cli](https://www.roc-lang.org/install).

Use the latest [release](https://github.com/lukewilliamboswell/basic-ssg/releases) of this platform by replacing the URL in the header.

```roc
app [main!] { pf: platform "<REPLACE WITH URL TO PLATFORM RELEASE>" }

import pf.SSG
import pf.Types exposing [Args]
import pf.Html exposing [div, link, text, a, html, head, body, meta, ul, li]
import pf.Html.Attributes exposing [class, httpEquiv, href, rel, content, lang, title]

main! : Args => Result {} _
main! = \{ inputDir, outputDir } ->
    # ... use SSG.files!, SSG.parseMarkdown!, and SSG.writeFile! here to generate site
```

## Platform Development

Ensure you have [roc](https://www.roc-lang.org/install) & [cargo](https://doc.rust-lang.org/cargo/getting-started/installation.html) installed.

Using nix (optional)

```
$ nix develop
```

```
$ roc build.roc
$ roc example/main.roc -- example/content/ example/output/
```

You can generate a new package for distribution using `roc build.roc --release --bundle`
