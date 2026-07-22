#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 -u "$root_dir/scripts/build.py" "$@"
