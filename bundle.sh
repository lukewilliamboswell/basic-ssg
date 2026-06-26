#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$root_dir/platform"

# Collect all .roc files
roc_files=(*.roc)

# Collect all host libraries and runtime files from targets directories
lib_files=()
for lib in targets/*/*.a targets/*/*.o; do
    if [[ -f "$lib" ]]; then
        lib_files+=("$lib")
    fi
done

# Collect license files that live at the repo root (roc bundle doesn't allow
# `..` paths, so copy them into the platform dir and clean up afterwards).
license_files=()
copied_licenses=()
for license in LICENSE THIRD_PARTY_LICENSES.md; do
    if [[ -f "$root_dir/$license" ]]; then
        cp "$root_dir/$license" .
        copied_licenses+=("$license")
        license_files+=("$license")
    fi
done
cleanup() {
    for license in "${copied_licenses[@]:-}"; do
        [[ -n "$license" ]] && rm -f "$license"
    done
}
trap cleanup EXIT

echo "Bundling ${#roc_files[@]} .roc files, ${#lib_files[@]} library files, ${#license_files[@]} license files..."
echo ""
echo "Files to bundle:"
for f in "${roc_files[@]}" "${lib_files[@]}" "${license_files[@]}"; do
    echo "  $f"
done
echo ""

roc bundle "${roc_files[@]}" "${lib_files[@]}" "${license_files[@]}" --output-dir "$root_dir" "$@"
