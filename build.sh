#!/usr/bin/env bash

# This script is used for testing the platform locally, building the host in debug mode.

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

echo "Cleaning up old build artifacts"
rm -rf target/
find . -name "*.a" -delete
find . -name "*.tar.br" -delete

echo "Building for native"
cargo build

echo "Copy prebuilt artifact to platform/ NOTE the hack for all platforms"
cp target/debug/libhost.a platform/macos-arm64.a
cp target/debug/libhost.a platform/linux-arm64.a
cp target/debug/libhost.a platform/linux-x64.a
cp target/debug/libhost.a platform/macos-x64.a

echo "run the example"
roc dev --prebuilt-platform example/main.roc -- example/content/ example/www/
