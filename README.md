# Roc-SSG 

A platform for Static Site Generation

**Status** Work In Progress

## Developing

**Run Example**

`bash run.sh`

**Packaging**

Add targets for cross-compilation

```sh
rustup target add aarch64-apple-darwin
rustup target add x86_64-unknown-linux-musl
rustup target add x86_64-apple-darwin
rustup target add aarch64-unknown-linux-musl
```

Package into a URL bundle using `bash bundle.sh`