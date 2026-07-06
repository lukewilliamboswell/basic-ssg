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
echo "Using roc version: $($ROC version)"

if [ "$(uname -s)" = "Darwin" ] && [ -z "${SDKROOT:-}" ]; then
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
    if [ -n "$SDKROOT" ]; then
        export SDKROOT
        echo "Using SDKROOT: $SDKROOT"
    fi
fi

# --- Generated Rust glue ------------------------------------------------------
# The --check step needs RustGlue.roc, which only ships in a roc *source*
# checkout (not the nightly release binary). Run it when a spec is reachable
# (ROC_SRC / ROC_GLUE_SPEC / sibling ../roc); otherwise skip -- the committed
# src/roc_platform_abi.rs is what `cargo build` relies on regardless.
echo ""
echo "=== Checking generated Rust glue ==="
if [ -n "${ROC_GLUE_SPEC:-}" ] || [ -n "${ROC_SRC:-}" ] || [ -f "../roc/src/glue/src/RustGlue.roc" ]; then
    ROC="$ROC" ./ci/regenerate_glue.sh --check
else
    echo "Skipping glue --check: no RustGlue.roc spec found (set ROC_SRC to enable)."
fi

# --- Host ---------------------------------------------------------------------
echo ""
echo "=== Building the platform host ==="
./build.sh

# --- Example ------------------------------------------------------------------
echo ""
echo "=== Testing examples ==="
$ROC test ./example/main.roc
$ROC test ./example/error-handling.roc

echo ""
echo "=== Testing platform helper modules ==="
$ROC test ./platform/Html.roc

echo ""
echo "=== Building and running the example ==="
$ROC build ./example/main.roc --output=./example/main
mkdir -p ./example/www
find ./example/www -type f -name '*.html' -delete
./example/main ./example/content/ ./example/www/
echo "Generated pages:"
find ./example/www -type f -name '*.html' | sort

echo ""
echo "=== Building and running the error-handling example ==="
$ROC build ./example/error-handling.roc --output=./example/error-handling
./example/error-handling ./example/content/index.md

# --- Docs ---------------------------------------------------------------------
echo ""
echo "=== Building platform docs ==="
$ROC docs --output=generated-docs ./docs/basic-ssg.roc

echo ""
echo "=== Done ==="
