# Contributing

This repository contains the Roc platform, the Rust host implementation,
release-bundling scripts, and examples.

## Prerequisites

- [Roc](https://www.roc-lang.org/install)
- [Rust and Cargo](https://doc.rust-lang.org/cargo/getting-started/installation.html)
- Nix, optionally, for the checked-in development shell
- `simple-http-server`, optionally, for `example/run.sh`

Use the Nix shell when you want the repo-managed tool environment:

```sh
nix develop
```

## Local Development

Build the host library for your native target:

```sh
./build.sh
```

Run the full local validation script:

```sh
./ci/all_tests.sh
```

The script builds the host, tests the examples, checks generated Rust glue when
the Roc glue spec is available, and builds platform docs. The full
`example/main.roc` binary build is currently allowed to fail while the upstream
Roc ARC-certifier issue for large HTML trees is open; `roc test` still checks
the example.

Examples in this repo use:

```roc
app [main!] { pf: platform "../platform/main.roc" }
```

Application docs should use a published release URL instead.

## Architecture

Hosted effects live in `platform/Host.roc`, which is intentionally not exposed
by `platform/main.roc`. Public modules such as `SSG`, `Stdout`, `Env`, and
`Utc` wrap those hosted effects.

Keep hosted effect errors closed in `Host.roc`, then expose open error unions
from the public modules. That lets application authors compose platform errors
with their own errors while keeping the host ABI precise.

The platform path type comes from [`roc-lang/path`](https://github.com/roc-lang/path).
Use that package type in public APIs instead of a project-local path wrapper.

## Style

Follow the Roc style notes in
[`style.md`](https://gist.githubusercontent.com/lukewilliamboswell/241a4e8adb7c89c7e0e02f1d303a8fa1/raw/style.md).

In particular:

- Add type annotations for top-level functions in examples and public modules.
- Prefer receiver-style calls such as `items.map(...)` and `args.drop_first(1)`.
- Use postfix `?` to propagate `Try` values.
- Use infix `?` to map low-level errors into app-domain errors.
- Use `??` only at a boundary where a fallback value is appropriate.
- Put a short doc comment before each top-level `expect`.

## Glue

Regenerate Rust glue after changing hosted Roc signatures:

```sh
./ci/regenerate_glue.sh
```

Use `--check` to verify the committed glue without rewriting it:

```sh
./ci/regenerate_glue.sh --check
```

The glue script needs `RustGlue.roc` from a Roc source checkout. It discovers a
sibling `../roc` checkout automatically, or you can set `ROC_SRC` or
`ROC_GLUE_SPEC`.

## Releases

Build all release targets before bundling:

```sh
./build.sh --all
```

Create a Roc platform bundle for upload:

```sh
./bundle.sh
```
