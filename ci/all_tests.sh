#!/usr/bin/env bash

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

# roc is expected on PATH (CI installs it via setup-roc; locally use your build).
ROC="${ROC:-$(command -v roc || true)}"
if [ -z "$ROC" ]; then
    echo "Could not find roc executable. Set ROC=/path/to/roc or add roc to PATH." >&2
    exit 1
fi

echo "=== basic-ssg CI ==="
echo ""
echo "Using roc version: $("$ROC" version)"

if [ "$(uname -s)" = "Darwin" ] && [ -z "${SDKROOT:-}" ]; then
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
    if [ -n "$SDKROOT" ]; then
        export SDKROOT
        echo "Using SDKROOT: $SDKROOT"
    fi
fi

# --- Roc sources --------------------------------------------------------------
echo ""
echo "=== Validating Roc sources ==="
"$ROC" fmt --check platform example docs
"$ROC" check ./example/main.roc
"$ROC" check ./example/error-handling.roc
"$ROC" check ./platform/Html.roc
"$ROC" check ./docs/basic-ssg.roc

# --- Generated Rust glue ------------------------------------------------------
# setup-roc will eventually provide the compiler-owned spec as ROC_RUST_GLUE,
# but current nightly archives do not contain a matching spec. Source builds
# and explicit environment overrides can still enable this check.
echo ""
echo "=== Checking generated Rust glue ==="
if [ -n "${ROC_RUST_GLUE:-}" ] \
    || [ -n "${ROC_GLUE_SPEC:-}" ] \
    || [ -n "${ROC_GLUE_DIR:-}" ] \
    || [ -n "${ROC_SRC:-}" ] \
    || [ -f "../roc/src/glue/src/RustGlue.roc" ] \
    || [ -f "../../roc/src/glue/src/RustGlue.roc" ]; then
    ROC="$ROC" ./ci/regenerate_glue.sh --check
else
    echo "Skipping glue check: no matching Rust glue spec is available."
fi

# --- Host ---------------------------------------------------------------------
echo ""
echo "=== Validating the platform host ==="
cargo fmt --check
cargo test --locked
cargo clippy --locked --lib --tests -- -D warnings

echo ""
echo "=== Building the platform host ==="
./build.sh

# --- Examples -----------------------------------------------------------------
echo ""
echo "=== Testing examples ==="
"$ROC" test ./example/main.roc
"$ROC" test ./example/error-handling.roc

echo ""
echo "=== Testing platform helper modules ==="
"$ROC" test ./platform/Html.roc
"$ROC" test ./platform/OsStr.roc

echo ""
echo "=== Building and running the example ==="
"$ROC" build ./example/main.roc --output=./example/main
mkdir -p ./example/www
find ./example/www -type f -name '*.html' -delete
./example/main ./example/content/ ./example/www/
echo "Generated pages:"
find ./example/www -type f -name '*.html' | sort

echo ""
echo "=== Building and running the error-handling example ==="
"$ROC" build ./example/error-handling.roc --output=./example/error-handling
./example/error-handling ./example/content/index.md

# --- Docs ---------------------------------------------------------------------
echo ""
echo "=== Building platform docs ==="
"$ROC" docs --output=generated-docs ./docs/basic-ssg.roc

echo ""
echo "=== Done ==="
