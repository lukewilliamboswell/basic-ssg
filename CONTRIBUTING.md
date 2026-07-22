# Contributing

This repository contains the Roc platform, the Rust host implementation,
release-bundling scripts, and examples.

## Prerequisites

- The new Zig-based [Roc compiler](https://www.roc-lang.org/install), available
  as `nightly-new-compiler` through `roc-lang/setup-roc`
- [Rust and Cargo](https://doc.rust-lang.org/cargo/getting-started/installation.html)
- Python 3.10 or newer for the build, bundle, and release validation scripts
- Zig for reproducible cross-compilation of the Linux musl targets
- On Windows, Visual Studio Build Tools with the MSVC x64 toolchain and Windows
  SDK

Commands below use `python` as the Python 3.10+ launcher. If that command is not
available, substitute `python3` on macOS or Linux, or `py -3.10` on Windows.

## Local Development

Build the host library for your native target:

```sh
python scripts/build.py
```

Run the full local validation script:

```sh
python scripts/all_tests.py
```

The script format-checks the Roc and Rust sources, checks and tests the supported
entry points and Rust host, runs Clippy with warnings denied, builds the host and
examples, runs all examples, checks generated Rust glue, and builds platform
docs. The glue check runs when a matching compiler-owned specification is
available; otherwise the committed generated Rust remains the source of truth.
A failure in any enabled step fails validation.

Run one or more sections while iterating:

```sh
python scripts/all_tests.py --section host --section examples
```

The example section is driven by `scripts/test_spec.json`. Each
`examples/<name>/` directory is a user-facing project; behavior-only fixtures
are created in temporary directories by `scripts/test.py`. Add happy-path and
failure cases to the spec rather than adding artificial files to an example.
The runner also requires every `examples/*/main.roc` app to appear in the spec.
Pure platform behavior should normally be covered by documented top-level Roc
`expect`s; the Python cases cover executable, effect, and filesystem behavior.

Run the example specification directly while iterating:

```sh
python scripts/test.py --platform-url ../../platform/main.roc --no-build
```

Build and serve the Markdown example using only Python's standard library:

```sh
python scripts/serve_example.py
```

Examples in this repo use a path relative to their own directory:

```roc
app [main!] { pf: platform "../../platform/main.roc" }
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
python scripts/glue.py
```

Use `--check` to verify the committed glue without rewriting it:

```sh
python scripts/glue.py --check
```

The new compiler owns the `platform glue` specification. Compiler source builds
provide it directly, while a matching nightly archive may expose it as
`ROC_RUST_GLUE`. The script uses that variable automatically when present. It
also discovers a sibling `../roc` source checkout; `ROC_GLUE_SPEC` can override
the spec with a local path, bundle URL, or installed shorthand.

Glue specs are compiled as cached host dynamic libraries. The script defaults
to `--opt=dev`; set `ROC_GLUE_OPT` to `size` or `speed` to exercise an LLVM
build. The old `interpreter` mode is no longer supported.

## Releases

Build the four macOS and Linux release hosts from macOS or Linux:

```sh
python scripts/build.py --all
```

The `x64win` host must be built natively on x86-64 Windows because it uses the
MSVC toolchain and Windows SDK:

```sh
python scripts/build.py --target x64win
```

This produces `host.lib` and copies the required SDK import libraries into
`platform/targets/x64win/`. Release CI builds that target on `windows-2025`,
then combines its artifact with the four Unix hosts before bundling.

Create a Roc platform bundle for upload:

```sh
python scripts/bundle.py
```

Bundling requires every supported target library plus `LICENSE` and
`THIRD_PARTY_LICENSES.md`. Run `python scripts/test.py` to validate source
behavior and the served bundle. Use `--platform-url ../../platform/main.roc`
while iterating when a complete five-target bundle has not been assembled
locally; the URL is resolved from each app under `examples/<name>/`.

The release workflow performs the same build and bundle validation on pull
requests, including native Windows build and runtime coverage. Checked-in
examples continue to use the local platform path so regular CI always tests the
current checkout; user-facing examples should use a published release URL.

Release validation, bundle metadata and testing, publication, versioned docs,
and the docs follow-up pull request use the official
[`roc-lang/release-package`](https://github.com/roc-lang/release-package)
actions. A successful manual release publishes the bundle, deploys the new docs
version to Pages, and opens a pull request adding that generated version under
`www/`. The first new-compiler release starts this tree from scratch rather than
restoring the legacy-compiler Pages content.
