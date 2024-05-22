#!/usr/bin/env bash

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

# REMOVE ANY OLD ARTEFACTS
rm -f platform/macos-arm64.a
rm -f platform/linux-arm64.a
rm -f platform/linux-x64.a
rm -f platform/macos-x64.a

# ADD TARGETS
rustup target add aarch64-apple-darwin
rustup target add x86_64-unknown-linux-gnu
rustup target add x86_64-apple-darwin
rustup target add aarch64-unknown-linux-gnu

# LEGACY LINKER ARTEFACTS
cargo build --release --target=aarch64-apple-darwin
cp target/aarch64-apple-darwin/release/libhost.a platform/macos-arm64.a

cargo build --release --target=aarch64-unknown-linux-gnu
cp target/aarch64-unknown-linux-gnu/release/libhost.a platform/linux-arm64.a

cargo build --release --target=x86_64-unknown-linux-gnu
cp target/x86_64-unknown-linux-gnu/release/libhost.a platform/linux-x64.a

cargo build --release --target=x86_64-apple-darwin
cp target/aarch64-apple-darwin/release/libhost.a platform/macos-x64.a

# SURGICAL LINKER ARTEFACTS
# TODO
# linux-x64.rh
# metadata_linux-x64.rm

# BUNDLE INTO PACKAGE
roc build --bundle .tar.br platform/main.roc
