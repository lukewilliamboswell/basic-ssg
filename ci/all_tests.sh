#!/usr/bin/env bash

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

if [ -z "${ROC:-}" ]; then
  echo "INFO: The ROC environment variable is not set."
  export ROC=$(which roc)
fi

if [ -z "${CARGO:-}" ]; then
  echo "INFO: The CARGO environment variable is not set."
  export CARGO=$(which cargo)
fi

# List of files to ignore
IGNORED_FILES=("")

echo "check the example"
$ROC check ./example/main.roc

echo "Cleaning up old build artifacts"
rm -rf target/
find . -name "*.a" -delete
find . -name "*.tar.br" -delete

echo "Build the platform for native"
$CARGO build

echo "Copy prebuilt artifact to platform/ NOTE the hack for all platforms DO NOT COPY THIS"
cp target/debug/libhost.a platform/macos-arm64.a
cp target/debug/libhost.a platform/linux-arm64.a
cp target/debug/libhost.a platform/linux-x64.a
cp target/debug/libhost.a platform/macos-x64.a

echo "run the example"
$ROC --linker=legacy ./example/main.roc -- ./example/content/ ./example/www/

# test building docs website
$ROC docs ./platform/main.roc
