"""Source-preserving reader for compiler pins in Roc root headers.

Vendored from roc-automation commit
5c1f09b7190118f43eb901eaed0110cd53029199.
"""

import re
from pathlib import Path


TOKEN = re.compile(r'#[^\n]*|"(?:\\.|[^"\\])*"|[A-Za-z_][A-Za-z_0-9!]*|[^\s]', re.DOTALL)
NUMBER = r"(?:0|[1-9][0-9]*)"
IDENTIFIER = rf"(?:{NUMBER}|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
PIN = re.compile(
    rf"(?:nightly-[0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}}-[0-9a-f]{{7,40}}|"
    rf"{NUMBER}\.{NUMBER}\.{NUMBER}(?:-{IDENTIFIER}(?:\.{IDENTIFIER})*)?)"
)


def header_pin(source: str) -> tuple[int, int, str] | None:
    tokens = (match for match in TOKEN.finditer(source) if not match.group().startswith("#"))
    first = next(tokens, None)
    if first is None or first.group() not in {"app", "package", "platform"}:
        return None
    platform = first.group() == "platform"
    stack: list[str] = []
    packages = not platform
    record = False
    fields: list[tuple[int, int, str]] = []
    previous: str | None = None
    for token in tokens:
        value = token.group()
        if not record:
            if platform and not stack and value == "packages":
                packages = True
            if packages and not stack and value == "{":
                record = True
                stack.append("}")
                previous = "{"
                continue
            if value in {"[", "{", "("}:
                stack.append({"[": "]", "{": "}", "(": ")"}[value])
            elif value in {"]", "}", ")"}:
                if not stack or stack.pop() != value:
                    raise ValueError("Malformed Roc header delimiters")
            continue
        if len(stack) == 1 and value == "roc" and previous in {"{", ","}:
            colon = next(tokens, None)
            literal = next(tokens, None)
            if colon is None or colon.group() != ":" or literal is None:
                raise ValueError("Malformed Roc compiler pin field")
            spelling = literal.group()
            if not spelling.startswith('"') or not PIN.fullmatch(spelling[1:-1]):
                raise ValueError("Roc compiler pin must be a supported literal version")
            fields.append((literal.start() + 1, literal.end() - 1, spelling[1:-1]))
            previous = spelling
            continue
        if value in {"[", "{", "("}:
            stack.append({"[": "]", "{": "}", "(": ")"}[value])
        elif value in {"]", "}", ")"}:
            if not stack or stack.pop() != value:
                raise ValueError("Malformed Roc header delimiters")
            if not stack:
                if len(fields) > 1:
                    raise ValueError("Duplicate Roc compiler pins")
                return fields[0] if fields else None
        previous = value
    if fields:
        raise ValueError("Incomplete pinned Roc root header")
    return None


def discover(sources: dict[str, str]) -> dict[str, tuple[str, tuple[int, int, str]]]:
    result = {}
    for path, source in sources.items():
        if path.endswith(".roc"):
            pin = header_pin(source)
            if pin is None:
                raise ValueError(f"Configured Roc compiler root has no literal pin: {path}")
            result[path] = (source, pin)
    if result and ".roc-version" in sources:
        raise ValueError("Header pins and .roc-version are competing compiler authorities")
    if not result:
        if ".roc-version" not in sources or not PIN.fullmatch(sources[".roc-version"].strip()):
            raise ValueError("No supported compiler pin found")
        source = sources[".roc-version"]
        pin = source.strip()
        start = source.index(pin)
        result[".roc-version"] = (source, (start, start + len(pin), pin))
    if len({pin[2] for _, pin in result.values()}) != 1:
        raise ValueError("Compiler header pins disagree")
    return result


def version(pins: dict[str, tuple[str, tuple[int, int, str]]]) -> str:
    return next(iter(pins.values()))[1][2]


def replace(pins: dict[str, tuple[str, tuple[int, int, str]]], pin: str) -> dict[str, str]:
    if not PIN.fullmatch(pin):
        raise ValueError("Invalid replacement compiler pin")
    return {
        path: source[:start] + pin + source[end:]
        for path, (source, (start, end, _)) in pins.items()
    }


def read_pin(path: str | Path) -> str:
    found = header_pin(Path(path).read_text(encoding="utf-8"))
    if found is None:
        raise ValueError("Roc root header has no compiler pin")
    return found[2]


def replace_pin(source: str, pin: str) -> str:
    found = header_pin(source)
    if found is None or not PIN.fullmatch(pin):
        raise ValueError("Existing header pin and valid replacement required")
    start, end, _ = found
    return source[:start] + pin + source[end:]


def validate_paths(paths: object) -> list[str]:
    if (
        not isinstance(paths, list)
        or not paths
        or len(paths) > 100
        or not all(isinstance(path, str) for path in paths)
        or len(paths) != len(set(paths))
    ):
        raise ValueError("compiler_roots must be a nonempty unique list")
    for path in paths:
        if (
            not re.fullmatch(r"[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*\.roc", path)
            or any(part in {".", "..", ".git"} for part in path.split("/"))
        ):
            raise ValueError("compiler_roots must be safe repository-relative Roc files")
    return paths


def local_sources(root: Path, paths: object) -> dict[str, str]:
    valid_paths = validate_paths(paths)
    sources = {}
    for path in valid_paths:
        location = root / path
        if (
            location.is_symlink()
            or not location.is_file()
            or not location.resolve().is_relative_to(root.resolve())
        ):
            raise ValueError("Compiler source must be a regular file inside the repository")
        sources[path] = location.read_text(encoding="utf-8")
    return sources
