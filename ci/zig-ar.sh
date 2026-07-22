#!/usr/bin/env bash
# Archiver companion to zig-cc.sh for musl cross-compilation.
set -euo pipefail

zig_bin="${ZIG:-zig}"
exec "$zig_bin" ar "$@"
