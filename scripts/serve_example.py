#!/usr/bin/env python3
"""Build the example site and serve it with Python's HTTP server."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import webbrowser
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXAMPLE_DIR = ROOT / "examples" / "orchard-guide"


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, format: str, *args: object) -> None:
        print(f"HTTP: {format % args}")


def executable(command: str) -> str:
    command_path = Path(command)
    if command_path.is_absolute() or command_path.parent != Path("."):
        if not command_path.is_absolute():
            command_path = ROOT / command_path
        resolved = str(command_path.resolve()) if command_path.is_file() else None
    else:
        resolved = shutil.which(command)
    if resolved is None:
        raise SystemExit(
            f"Could not find Roc executable {command!r}. Use --roc or add roc to PATH."
        )
    return resolved


def command(*args: str | Path) -> None:
    values = [str(value) for value in args]
    print(f"+ {subprocess.list2cmdline(values)}", flush=True)
    subprocess.run(values, cwd=ROOT, check=True)


def native_binary(path: Path) -> Path:
    if os.name == "nt" and path.suffix.lower() != ".exe":
        return path.with_name(f"{path.name}.exe")
    return path


def roc_extra_args() -> tuple[str, ...]:
    return ("--no-cache",) if os.name == "nt" else ()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build and serve the Orchard Guide example site."
    )
    parser.add_argument("--roc", default=os.environ.get("ROC", "roc"))
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--source", type=Path, default=EXAMPLE_DIR / "main.roc")
    parser.add_argument("--content", type=Path, default=EXAMPLE_DIR / "content")
    parser.add_argument("--output", type=Path, default=EXAMPLE_DIR / "output")
    parser.add_argument(
        "--binary", type=Path, default=ROOT / "target" / "examples" / "orchard-guide"
    )
    parser.add_argument("--skip-check", action="store_true")
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument(
        "--no-open", action="store_true", help="do not open the site in a browser"
    )
    parser.add_argument(
        "--no-serve",
        action="store_true",
        help="generate the site and exit without starting the HTTP server",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if not 0 <= args.port <= 65535:
        raise SystemExit("--port must be between 0 and 65535")

    roc = executable(args.roc)
    source = args.source.resolve()
    content = args.content.resolve()
    output = args.output.resolve()
    binary = native_binary(args.binary.resolve())

    if not source.is_file():
        raise SystemExit(f"Example source not found: {source}")
    if not content.is_dir():
        raise SystemExit(f"Content directory not found: {content}")
    output.mkdir(parents=True, exist_ok=True)
    for html_file in output.rglob("*.html"):
        html_file.unlink()
    public_dir = source.parent / "public"
    if public_dir.is_dir():
        shutil.copytree(public_dir, output, dirs_exist_ok=True)

    if not args.skip_check:
        command(roc, "check", source, *roc_extra_args())
    if not args.skip_build:
        binary.parent.mkdir(parents=True, exist_ok=True)
        command(roc, "build", source, f"--output={binary}", *roc_extra_args())
    if not binary.is_file():
        raise SystemExit(f"Example binary not found: {binary}")

    command(binary, content, output)
    if args.no_serve:
        print(f"Generated site: {output}")
        return

    handler = partial(QuietHandler, directory=str(output))
    try:
        server = ThreadingHTTPServer((args.host, args.port), handler)
    except OSError as error:
        raise SystemExit(
            f"Could not listen on {args.host}:{args.port}: {error}"
        ) from None
    server.daemon_threads = True
    host, port = server.server_address[:2]
    display_host = "127.0.0.1" if host in {"0.0.0.0", "::"} else host
    if ":" in display_host:
        display_host = f"[{display_host}]"
    url = f"http://{display_host}:{port}/"
    print(f"Serving {output} at {url}")
    if not args.no_open and not webbrowser.open(url):
        print("Could not open a browser automatically; open the URL above.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping server.")
    finally:
        server.server_close()


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from None
