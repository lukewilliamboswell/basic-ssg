#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Roc's native glue plugin build currently requires one of TMPDIR/TEMP/TMP.
# Standard Unix systems always provide /tmp even when the shell omits TMPDIR.
export TMPDIR="${TMPDIR:-/tmp}"

ROC_BIN="${ROC:-roc}"
PLATFORM_FILE="${PLATFORM_FILE:-platform/main.roc}"
GLUE_OUT_DIR="${GLUE_OUT_DIR:-src}"
GLUE_OPT="${ROC_GLUE_OPT:-dev}"
MODE="write"

usage() {
    cat <<'EOF'
Usage: ci/regenerate_glue.sh [--check]

Regenerate Rust ABI bindings for the basic-ssg Roc platform.

Environment overrides:
  ROC             Roc executable to run. Default: roc
  ROC_RUST_GLUE   Rust glue spec provided by a Roc release/setup-roc
  ROC_GLUE_SPEC   Explicit glue spec path, URL, or installed shorthand
  ROC_GLUE_DIR    Directory containing RustGlue.roc
  ROC_GLUE_OPT    Glue compilation mode: dev, size, or speed. Default: dev
  ROC_SRC         Compatibility fallback: path to a Roc source checkout
  PLATFORM_FILE   Platform file to analyze. Default: platform/main.roc
  GLUE_OUT_DIR    Output directory. Default: src

Roc releases expose the compiler-owned Rust glue spec as ROC_RUST_GLUE.
For source builds, the script also looks next to the Roc binary and in a
sibling ../roc checkout.
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    exit 0
elif [ "${1:-}" = "--check" ]; then
    MODE="check"
elif [ "${1:-}" != "" ]; then
    usage >&2
    exit 2
fi

find_glue_spec() {
    if [ -n "${ROC_GLUE_SPEC:-}" ]; then
        echo "$ROC_GLUE_SPEC"
        return 0
    fi

    if [ -n "${ROC_RUST_GLUE:-}" ]; then
        echo "$ROC_RUST_GLUE"
        return 0
    fi

    candidates=()

    if [ -n "${ROC_GLUE_DIR:-}" ]; then
        candidates+=("${ROC_GLUE_DIR%/}/RustGlue.roc")
    fi

    if [ -n "${ROC_SRC:-}" ]; then
        candidates+=("${ROC_SRC%/}/src/glue/src/RustGlue.roc")
    fi

    roc_path="$(command -v "$ROC_BIN" 2>/dev/null || true)"
    if [ -n "$roc_path" ]; then
        roc_bin_dir="$(cd "$(dirname "$roc_path")" 2>/dev/null && pwd || true)"
        if [ -n "$roc_bin_dir" ]; then
            roc_source_root="$(cd "$roc_bin_dir/../.." 2>/dev/null && pwd || true)"
            if [ -n "$roc_source_root" ]; then
                candidates+=("$roc_source_root/src/glue/src/RustGlue.roc")
            fi

            if [ "$(basename "$roc_bin_dir")" = "bin" ] && [ "$(basename "$(dirname "$roc_bin_dir")")" = "zig-out" ]; then
                roc_checkout_root="$(cd "$roc_bin_dir/../../.." 2>/dev/null && pwd || true)"
                if [ -n "$roc_checkout_root" ]; then
                    candidates+=("$roc_checkout_root/src/glue/src/RustGlue.roc")
                fi
            fi
        fi
    fi

    candidates+=(
        "../roc/src/glue/src/RustGlue.roc"
        "../../roc/src/glue/src/RustGlue.roc"
    )

    for candidate in "${candidates[@]}"; do
        if [ -f "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done

    echo "Could not find the Rust glue spec." >&2
    echo "Install Roc via setup-roc, set ROC_RUST_GLUE, or set ROC_GLUE_SPEC." >&2
    return 1
}

GLUE_SPEC="$(find_glue_spec)"

case "$GLUE_OPT" in
    dev|size|speed) ;;
    *)
        echo "Invalid ROC_GLUE_OPT '$GLUE_OPT'; expected dev, size, or speed." >&2
        exit 2
        ;;
esac

if ! command -v "$ROC_BIN" >/dev/null 2>&1; then
    echo "Could not find roc executable '$ROC_BIN'. Set ROC=/path/to/roc." >&2
    exit 1
fi

if [ ! -f "$PLATFORM_FILE" ]; then
    echo "Platform file not found: $PLATFORM_FILE" >&2
    exit 1
fi

# `roc glue` also accepts bundle URLs and installed shorthands. Only validate
# the spec here when it names a local path.
case "$GLUE_SPEC" in
    http://*|https://*) ;;
    *)
        if [[ "$GLUE_SPEC" == */* || "$GLUE_SPEC" == *.roc ]] && [ ! -f "$GLUE_SPEC" ]; then
            echo "Glue spec not found: $GLUE_SPEC" >&2
            exit 1
        fi
        ;;
esac

run_glue() {
    local out_dir=$1
    mkdir -p "$out_dir"
    "$ROC_BIN" glue --opt="$GLUE_OPT" "$GLUE_SPEC" "$out_dir" "$PLATFORM_FILE"
}

if [ "$MODE" = "check" ]; then
    tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/basic-ssg-glue.XXXXXX")"
    cleanup() { rm -rf "$tmp_dir"; }
    trap cleanup EXIT

    run_glue "$tmp_dir"

    generated="$tmp_dir/roc_platform_abi.rs"
    committed="$GLUE_OUT_DIR/roc_platform_abi.rs"

    if [ ! -f "$committed" ]; then
        echo "Missing generated glue file: $committed" >&2
        exit 1
    fi

    if ! diff -u "$committed" "$generated"; then
        echo "Generated Rust glue is stale. Run ci/regenerate_glue.sh and commit the result." >&2
        exit 1
    fi

    echo "Rust glue is up to date: $committed"
else
    echo "Using roc: $ROC_BIN"
    echo "Using glue spec: $GLUE_SPEC"
    echo "Using glue opt: $GLUE_OPT"
    echo "Platform: $PLATFORM_FILE"
    echo "Output dir: $GLUE_OUT_DIR"
    run_glue "$GLUE_OUT_DIR"
    echo "Generated: $GLUE_OUT_DIR/roc_platform_abi.rs"
fi
