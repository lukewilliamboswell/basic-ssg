#!/usr/bin/env python3
"""Build, package, and verify reusable compiler runtime linker inputs."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import tempfile
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath


ROOT = Path(__file__).resolve().parents[1]
ZIG_VERSION = "0.16.0"
MINGW_LICENSE_URL = (
    "https://raw.githubusercontent.com/mingw-w64/mingw-w64/"
    "aa96035ea5edd244502bd3e1550d4a801c12033e/"
    "COPYING.MinGW-w64-runtime/COPYING.MinGW-w64-runtime.txt"
)
MINGW_LICENSE_SHA256 = "1db8da07b436c68833c0673ffee3d9fcb2526047f3820b81661865dfedc79a1f"
MUSL_TARGETS = {
    "x64musl": "x86_64-linux-musl",
    "arm64musl": "aarch64-linux-musl",
}
MUSL_FILES = ("crt1.o", "libc.a", "libunwind.a")
ZIG_MUSL_ARCHIVES = ("libc.a", "libzigc.a", "libcompiler_rt.a")
WINDOWS_FILES = (
    "advapi32.lib", "bcrypt.lib", "crypt32.lib", "dbghelp.lib",
    "iphlpapi.lib", "kernel32.lib", "ncrypt.lib", "ntdll.lib", "ole32.lib",
    "secur32.lib", "shell32.lib", "user32.lib", "userenv.lib", "ws2_32.lib",
)
EXPECTED_FILES = tuple(
    [f"targets/{target}/{name}" for target in MUSL_TARGETS for name in MUSL_FILES]
    + [f"targets/x64win/{name}" for name in WINDOWS_FILES]
)
CONSUMER_CONFIG = ROOT / ".github" / "runtime-inputs.json"
MAX_ARCHIVE_BYTES = 128 * 1024 * 1024
MAX_UNPACKED_BYTES = 100 * 1024 * 1024


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require_zig() -> None:
    version = subprocess.check_output(["zig", "version"], text=True).strip()
    if version != ZIG_VERSION:
        raise SystemExit(f"Zig {ZIG_VERSION} is required; found {version}")


def canonicalize_archives(
    sources: tuple[Path, ...],
    destination: Path,
    *,
    replacements: tuple[tuple[bytes, bytes], ...] = (),
) -> None:
    """Combine ar archives with deterministic, path-independent member names."""
    members: list[tuple[str, bytes]] = []
    for source in sources:
        data = source.read_bytes()
        if not data.startswith(b"!<arch>\n"):
            raise SystemExit(f"Unsupported archive format: {source}")
        offset = 8
        long_names = b""
        while offset < len(data):
            header = data[offset : offset + 60]
            if len(header) != 60 or header[58:60] != b"`\n":
                raise SystemExit(f"Malformed archive member in {source}")
            raw_name = header[:16].decode("ascii").strip()
            try:
                size = int(header[48:58].decode("ascii").strip())
            except ValueError as error:
                raise SystemExit(f"Malformed archive size in {source}") from error
            content = data[offset + 60 : offset + 60 + size]
            offset += 60 + size + (size % 2)
            if raw_name == "//":
                long_names = content
                continue
            if raw_name in {"/", "/SYM64/"}:
                continue
            if raw_name.startswith("/") and raw_name[1:].isdigit():
                start = int(raw_name[1:])
                end = long_names.find(b"/\n", start)
                if end < 0:
                    raise SystemExit(f"Malformed long archive name in {source}")
                name = long_names[start:end].decode("utf-8")
            else:
                name = raw_name.removesuffix("/")
            for old, new in replacements:
                if len(old) != len(new):
                    raise SystemExit("Archive path replacements must preserve byte length")
                content = content.replace(old, new)
            members.append((name, content))
    with tempfile.TemporaryDirectory(prefix="basic-ssg-ar-") as raw_directory:
        directory = Path(raw_directory)
        canonical_members = []
        for index, (name, content) in enumerate(members):
            member_path = directory / f"{index:05d}-{Path(name).name}"
            member_path.write_bytes(content)
            canonical_members.append(member_path)
        rebuilt = directory / destination.name
        subprocess.run(
            ["zig", "ar", "rcsD", str(rebuilt), *(str(member) for member in canonical_members)],
            check=True,
        )
        shutil.copyfile(rebuilt, destination)


def copy_canonical_object(
    source: Path,
    destination: Path,
    replacements: tuple[tuple[bytes, bytes], ...],
) -> None:
    content = source.read_bytes()
    for old, new in replacements:
        if len(old) != len(new):
            raise SystemExit("Object path replacements must preserve byte length")
        content = content.replace(old, new)
    destination.write_bytes(content)


def locate_artifacts(
    trace: str, wanted: tuple[str, ...], *, relative_to: Path
) -> dict[str, Path]:
    found: dict[str, Path] = {}
    for line in trace.splitlines():
        try:
            tokens = shlex.split(line, posix=os.name != "nt")
        except ValueError:
            continue
        for token in tokens:
            candidate = Path(token.strip('"'))
            if not candidate.is_absolute():
                candidate = relative_to / candidate
            for name in wanted:
                if candidate.name.lower() == name.lower() and candidate.is_file():
                    found[name] = candidate
    return found


def zig_link(
    target: str, work: Path, wanted: tuple[str, ...], *, windows: bool = False
) -> dict[str, Path]:
    target_work = work / target.replace("-", "_")
    target_work.mkdir(parents=True)
    source = target_work / "probe.cpp"
    source.write_text(
        "int main() { try { throw 1; } catch (...) { return 0; } }\n",
        encoding="utf-8",
    )
    env = os.environ.copy()
    env["ZIG_GLOBAL_CACHE_DIR"] = "global-cache"
    env["ZIG_LOCAL_CACHE_DIR"] = "local-cache"
    libraries = [f"-l{Path(name).stem}" for name in wanted] if windows else []
    command = [
        "zig", "c++", "-target", target, "-O2", "-g0", "-fno-sanitize=all",
        "-static", "-v", source.name, *libraries, "-o", "probe.exe",
    ]
    result = subprocess.run(
        command, cwd=target_work, env=env, text=True, stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE, check=False,
    )
    trace = target_work / "zig-link.trace"
    trace.write_text(result.stderr, encoding="utf-8")
    if result.returncode != 0:
        raise SystemExit(f"Zig link failed for {target}; inspect {trace}")
    found = locate_artifacts(result.stderr, wanted, relative_to=target_work)
    missing = sorted(set(wanted) - set(found))
    if missing:
        raise SystemExit(f"Zig did not expose {', '.join(missing)} for {target}; inspect {trace}")
    return found


def build(output: Path) -> None:
    require_zig()
    output.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(
        prefix="basic-ssg-runtime-build-", dir="/tmp"
    ) as raw_work:
        work = Path(raw_work)
        canonical_work = Path("/tmp/basic-ssg-runtime-build-00000000")
        path_replacements = ((os.fsencode(work), os.fsencode(canonical_work)),)
        for roc_target, zig_target in MUSL_TARGETS.items():
            wanted = (*MUSL_FILES, *ZIG_MUSL_ARCHIVES[1:])
            found = zig_link(zig_target, work, wanted)
            destination = output / "targets" / roc_target
            destination.mkdir(parents=True)
            copy_canonical_object(
                found["crt1.o"], destination / "crt1.o", path_replacements
            )
            canonicalize_archives(
                tuple(found[name] for name in ZIG_MUSL_ARCHIVES),
                destination / "libc.a",
                replacements=path_replacements,
            )
            canonicalize_archives(
                (found["libunwind.a"],),
                destination / "libunwind.a",
                replacements=path_replacements,
            )
        found = zig_link("x86_64-windows-gnu", work, WINDOWS_FILES, windows=True)
        destination = output / "targets" / "x64win"
        destination.mkdir(parents=True)
        for name in WINDOWS_FILES:
            shutil.copyfile(found[name], destination / name)


def inventory(directory: Path) -> list[dict[str, object]]:
    actual = sorted(
        path.relative_to(directory).as_posix()
        for path in directory.rglob("*") if path.is_file()
    )
    if actual != sorted(EXPECTED_FILES):
        raise SystemExit(f"Runtime input inventory mismatch: {actual}")
    return [
        {"path": relative, "sha256": sha256(directory / relative), "size": (directory / relative).stat().st_size}
        for relative in sorted(EXPECTED_FILES)
    ]


def compare(first: Path, second: Path) -> None:
    first_inventory = inventory(first)
    second_inventory = inventory(second)
    if first_inventory != second_inventory:
        raise SystemExit("Two clean runtime-input builds produced different bytes")
    print("Two clean runtime-input builds are byte-identical.")


def download_mingw_license() -> bytes:
    with urllib.request.urlopen(MINGW_LICENSE_URL, timeout=30) as response:
        content = response.read()
    if hashlib.sha256(content).hexdigest() != MINGW_LICENSE_SHA256:
        raise SystemExit("Pinned mingw-w64 license digest mismatch")
    return content


def zip_write(archive: zipfile.ZipFile, name: str, content: bytes) -> None:
    info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o100644 << 16
    archive.writestr(info, content)


def package(directory: Path, output: Path, version: str) -> None:
    if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version) is None:
        raise SystemExit(f"Invalid runtime-input version: {version!r}")
    files = inventory(directory)
    manifest = {
        "schema": 1,
        "name": "basic-ssg-runtime-inputs",
        "version": version,
        "zig_version": ZIG_VERSION,
        "files": files,
    }
    sbom = {
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT",
        "name": f"basic-ssg-runtime-inputs-{version}",
        "documentNamespace": f"https://github.com/lukewilliamboswell/basic-ssg/runtime-inputs/{version}",
        "creationInfo": {"creators": ["Tool: scripts/runtime_inputs.py"], "created": "1980-01-01T00:00:00Z"},
        "packages": [
            {
                "name": name, "SPDXID": spdx_id, "downloadLocation": "NOASSERTION",
                "filesAnalyzed": False, "licenseConcluded": license_id,
                "licenseDeclared": license_id, "copyrightText": "NOASSERTION",
            }
            for name, spdx_id, license_id in (
                ("musl", "SPDXRef-musl", "MIT"),
                ("LLVM-libunwind", "SPDXRef-libunwind", "Apache-2.0 WITH LLVM-exception"),
                ("mingw-w64-import-definitions", "SPDXRef-mingw", "NOASSERTION"),
            )
        ],
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    sbom_content = (json.dumps(sbom, indent=2, sort_keys=True) + "\n").encode()
    sbom_path = output.with_suffix(".spdx.json")
    sbom_path.write_bytes(sbom_content)
    with zipfile.ZipFile(output, "w") as archive:
        for item in files:
            relative = str(item["path"])
            zip_write(archive, relative, (directory / relative).read_bytes())
        zip_write(archive, "manifest.json", (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode())
        zip_write(archive, "sbom.spdx.json", sbom_content)
        zip_write(archive, "LICENSES/COPYING.MinGW-w64-runtime.txt", download_mingw_license())
        zip_write(archive, "LICENSES/THIRD_PARTY_LICENSES.md", (ROOT / "THIRD_PARTY_LICENSES.md").read_bytes())
    (output.parent / "SHA256SUMS").write_text(f"{sha256(output)}  {output.name}\n", encoding="utf-8")
    print(f"Created {output} ({sha256(output)})")


def verify_archive(archive_path: Path, expected_digest: str | None = None) -> dict[str, object]:
    if archive_path.stat().st_size > MAX_ARCHIVE_BYTES:
        raise SystemExit("Runtime archive exceeds the download size limit")
    if expected_digest and sha256(archive_path) != expected_digest:
        raise SystemExit("Runtime archive SHA-256 mismatch")
    allowed_metadata = {
        "manifest.json", "sbom.spdx.json",
        "LICENSES/COPYING.MinGW-w64-runtime.txt", "LICENSES/THIRD_PARTY_LICENSES.md",
    }
    with zipfile.ZipFile(archive_path) as archive:
        if sum(item.file_size for item in archive.infolist()) > MAX_UNPACKED_BYTES:
            raise SystemExit("Runtime archive exceeds the unpacked size limit")
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise SystemExit("Runtime archive contains duplicate paths")
        for name in names:
            path = PurePosixPath(name)
            if path.is_absolute() or ".." in path.parts or "\\" in name:
                raise SystemExit(f"Unsafe runtime archive path: {name}")
        if set(names) != set(EXPECTED_FILES) | allowed_metadata:
            raise SystemExit("Runtime archive has an unexpected file inventory")
        manifest = json.loads(archive.read("manifest.json"))
        if manifest.get("schema") != 1 or manifest.get("zig_version") != ZIG_VERSION:
            raise SystemExit("Unsupported runtime archive manifest")
        expected = {item["path"]: item for item in manifest.get("files", [])}
        if set(expected) != set(EXPECTED_FILES):
            raise SystemExit("Runtime manifest has an unexpected file inventory")
        for name in EXPECTED_FILES:
            content = archive.read(name)
            if hashlib.sha256(content).hexdigest() != expected[name]["sha256"] or len(content) != expected[name]["size"]:
                raise SystemExit(f"Runtime input digest mismatch: {name}")
    return manifest


def extract_archive(archive_path: Path, destination: Path) -> None:
    manifest = verify_archive(archive_path)
    with zipfile.ZipFile(archive_path) as archive:
        for relative in EXPECTED_FILES:
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            temporary = target.with_suffix(target.suffix + ".tmp")
            temporary.write_bytes(archive.read(relative))
            temporary.replace(target)
        notice = destination / "COPYING.MinGW-w64-runtime.txt"
        notice.write_bytes(archive.read("LICENSES/COPYING.MinGW-w64-runtime.txt"))
    print(f"Extracted runtime inputs {manifest['version']} into {destination}")


def hydrate(config_path: Path, destination: Path, *, verify_attestation: bool) -> None:
    config = json.loads(config_path.read_text(encoding="utf-8"))
    required = {"version", "url", "sha256", "repository", "signer_workflow", "source_digest"}
    if set(config) != required or not all(isinstance(config[key], str) and config[key] for key in required):
        raise SystemExit(f"{config_path}: expected exactly {', '.join(sorted(required))}")
    if (
        not config["url"].startswith("https://github.com/")
        or re.fullmatch(r"[0-9a-f]{64}", config["sha256"]) is None
        or re.fullmatch(r"[0-9a-f]{40}", config["source_digest"]) is None
    ):
        raise SystemExit(f"{config_path}: runtime URL or SHA-256 is invalid")
    cache = ROOT / "target" / "runtime-inputs" / config["sha256"]
    archive_path = cache / "runtime-inputs.zip"
    cache.mkdir(parents=True, exist_ok=True)
    if not archive_path.is_file() or sha256(archive_path) != config["sha256"]:
        temporary = cache / "runtime-inputs.download"
        try:
            with urllib.request.urlopen(config["url"], timeout=60) as response, temporary.open("wb") as output:
                downloaded = 0
                while chunk := response.read(1024 * 1024):
                    downloaded += len(chunk)
                    if downloaded > MAX_ARCHIVE_BYTES:
                        raise SystemExit("Runtime archive exceeds the download size limit")
                    output.write(chunk)
            if sha256(temporary) != config["sha256"]:
                raise SystemExit("Downloaded runtime archive SHA-256 mismatch")
            temporary.replace(archive_path)
        finally:
            temporary.unlink(missing_ok=True)
    manifest = verify_archive(archive_path, config["sha256"])
    if manifest["version"] != config["version"]:
        raise SystemExit("Runtime archive version does not match consumer configuration")
    if verify_attestation:
        subprocess.run(
            [
                "gh", "attestation", "verify", str(archive_path),
                "--repo", config["repository"],
                "--signer-workflow", config["signer_workflow"],
                "--source-digest", config["source_digest"],
            ],
            cwd=ROOT,
            check=True,
        )
    with zipfile.ZipFile(archive_path) as archive:
        for relative in EXPECTED_FILES:
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            temporary = target.with_suffix(target.suffix + ".tmp")
            temporary.write_bytes(archive.read(relative))
            temporary.replace(target)
        notice = destination / "COPYING.MinGW-w64-runtime.txt"
        notice.write_bytes(archive.read("LICENSES/COPYING.MinGW-w64-runtime.txt"))
    print(f"Hydrated runtime inputs {manifest['version']} into {destination}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    build_parser = subparsers.add_parser("build")
    build_parser.add_argument("--output", required=True, type=Path)
    compare_parser = subparsers.add_parser("compare")
    compare_parser.add_argument("first", type=Path)
    compare_parser.add_argument("second", type=Path)
    package_parser = subparsers.add_parser("package")
    package_parser.add_argument("--input", required=True, type=Path)
    package_parser.add_argument("--output", required=True, type=Path)
    package_parser.add_argument("--version", required=True)
    verify_parser = subparsers.add_parser("verify")
    verify_parser.add_argument("archive", type=Path)
    verify_parser.add_argument("--sha256")
    hydrate_parser = subparsers.add_parser("hydrate")
    hydrate_parser.add_argument("--config", type=Path, default=CONSUMER_CONFIG)
    hydrate_parser.add_argument("--destination", type=Path, default=ROOT / "platform")
    hydrate_parser.add_argument(
        "--verify-attestation", action="store_true",
        help="require a GitHub artifact attestation from the configured workflow",
    )
    extract_parser = subparsers.add_parser("extract")
    extract_parser.add_argument("archive", type=Path)
    extract_parser.add_argument("--destination", required=True, type=Path)
    args = parser.parse_args()
    if args.command == "build":
        build(args.output)
    elif args.command == "compare":
        compare(args.first, args.second)
    elif args.command == "package":
        package(args.input, args.output, args.version)
    elif args.command == "verify":
        manifest = verify_archive(args.archive, args.sha256)
        print(f"Verified runtime inputs {manifest['version']} from Zig {manifest['zig_version']}")
    elif args.command == "hydrate":
        hydrate(args.config, args.destination, verify_attestation=args.verify_attestation)
    else:
        extract_archive(args.archive, args.destination)


if __name__ == "__main__":
    main()
