#!/usr/bin/env bash

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

# Get OS type and architecture
OS=$(uname -s)
ARCH=$(uname -m)

case "$OS" in
    "Darwin")
        case "$ARCH" in
            "arm64"|"aarch64")
                cargo build --target=aarch64-apple-darwin
                cp target/aarch64-apple-darwin/debug/libhost.a platform/macos-arm64.a
                ;;
            "x86_64")
                cargo build --target=x86_64-apple-darwin
                cp target/aarch64-apple-darwin/debug/libhost.a platform/macos-x64.a
                ;;
            *)
                echo "Unsupported architecture: $ARCH"
                exit 1
                ;;
        esac
        ;;
    "Linux")
        case "$ARCH" in
            "x86_64")
                cargo build --target=x86_64-unknown-linux-musl
                cp target/x86_64-unknown-linux-musl/debug/libhost.a platform/linux-x64.a
                ;;
            "aarch64")
                cargo build --target=aarch64-unknown-linux-musl
                cp target/aarch64-unknown-linux-musl/debug/libhost.a platform/linux-arm64.a
                ;;
            *)
                echo "Unsupported architecture: $ARCH"
                exit 1
                ;;
        esac
        ;;
    *)
        echo "Unsupported operating system: $OS"
        exit 1
        ;;
esac

roc dev --prebuilt-platform examples/main.roc -- examples/content/ examples/output/