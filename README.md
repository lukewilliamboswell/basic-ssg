# Roc-SSG

A platform for Static Site Generation

**Status** Alpha - please help me tests this, and let me know if you find any issues.

Use this platform to parse a directory of markdown files, and tranform this content using [roc-lang](https://www.roc-lang.org) into a html site ready to be served from a web server or [CDN](https://en.wikipedia.org/wiki/Content_delivery_network).

## Getting Starting

Ensure you have [installed the roc cli](https://www.roc-lang.org/install) and [installed cargo](https://doc.rust-lang.org/cargo/getting-started/installation.html).

Use the latest [release](https://github.com/lukewilliamboswell/basic-ssg/releases) of this platform by replacing the plaform URL in the header.

```roc
app "example"
    packages { pf: "https://github.com/lukewilliamboswell/basic-ssg/releases/download/[REPLACE WITH RELEASE URL].tar.br" }
    imports [
        pf.Task.{Task},
        pf.SSG,
    ]
    provides [main] to pf
```

## Developing

A few scripts are included to assist with common tasks.

- *run.sh* build the platform in debug mode, and run the `simple.roc` example
- *glue.sh* re-generate glue types for the platform (note currently requires a copy of the roc repository)
- *bundle.sh* cross-compile the platform in release mode for supported targets and package for distribution