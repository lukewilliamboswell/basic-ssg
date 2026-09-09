# Runtime-input releases

`runtime-inputs.yml` builds the target files that do not depend on this
repository's Rust host. It compiles them twice with Zig 0.16.0 in separate
caches, requires byte-identical output, tests the resulting archive with fresh
hosts, creates signed provenance and SBOM attestations, and publishes an
independent `runtime-inputs-vX.Y.Z` release without changing the latest platform
release.

The archive contains real musl `crt1.o`, `libc.a`, and `libunwind.a` files for
x64 and ARM64. Its Windows files are generated COFF import stubs from Zig's
mingw-w64 definitions, not Microsoft SDK libraries. `libhost.a` and `host.lib`
are intentionally excluded and remain source-build outputs.

## First release and adoption

1. Merge the producer workflow and dispatch `Runtime inputs` on `main` with
   version `1.0.0`.
2. Verify the release asset, its `SHA256SUMS`, SPDX SBOM, workflow run, and both
   GitHub attestations.
3. Add `.github/runtime-inputs.json` in a reviewed follow-up PR:

   ```json
   {
     "version": "1.0.0",
     "url": "https://github.com/lukewilliamboswell/basic-ssg/releases/download/runtime-inputs-v1.0.0/basic-ssg-runtime-inputs-v1.0.0.zip",
     "sha256": "<archive SHA-256>",
     "repository": "lukewilliamboswell/basic-ssg",
     "signer_workflow": "lukewilliamboswell/basic-ssg/.github/workflows/runtime-inputs.yml",
     "source_digest": "<40-character producer commit SHA>"
   }
   ```

4. Delete the six tracked musl files. The consumer then downloads and verifies
   the immutable archive; CI additionally requires its signer workflow and
   producer commit. Remove the transitional Windows SDK fallback from
   `scripts/build.py` in the same follow-up.

Do not add a moving release URL, skip attestation verification in CI, publish a
runtime release from a pull request, or include a host library in this package.
