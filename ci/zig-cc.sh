#!/usr/bin/env bash
# C-compiler shim for musl cross-compilation. scripts/build.py sets the Zig
# target and points Cargo build scripts at this wrapper.
set -euo pipefail

: "${ZIG_CC_TARGET:?ZIG_CC_TARGET must be set (e.g. x86_64-linux-musl)}"
zig_bin="${ZIG:-zig}"

args=()
skip_next=false
for arg in "$@"; do
    if [ "$skip_next" = true ]; then
        skip_next=false
        continue
    fi
    case "$arg" in
        --target=*) continue ;;
        -target) skip_next=true; continue ;;
        x86_64-unknown-linux-musl|aarch64-unknown-linux-musl) continue ;;
        *) args+=("$arg") ;;
    esac
done

exec "$zig_bin" cc -target "$ZIG_CC_TARGET" "${args[@]}"
