#!/usr/bin/env python3
"""Create or verify the exact VibeSlopik release asset set."""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


CORE_ASSETS = {
    "install-relay-vps.sh",
    "vibeslopik-relay-manager.sh",
    "vibeslopik-relay-linux-amd64",
    "vibeslopik-relay-linux-arm64",
    "vibeslopik-host-windows-x64.zip",
    "vibeslopik-host-linux-x64.zip",
    "vibeslopik-host-macos-x64.zip",
    "vibeslopik-host-macos-arm64.zip",
    "vibeslopik-speech-windows-x64.zip",
    "vibeslopik-speech-linux-x64.zip",
    "vibeslopik-speech-macos-x64.zip",
    "vibeslopik-speech-macos-arm64.zip",
}
IPA = "VibeSlopik.ipa"
CHECKSUMS = "SHA256SUMS"


def digest(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--allow-missing-ipa", action="store_true", help="only for the unpublished CI draft")
    args = parser.parse_args()

    directory = args.directory.resolve()
    if not directory.is_dir():
        raise SystemExit(f"release directory does not exist: {directory}")
    actual = {item.name for item in directory.iterdir() if item.is_file() and item.name != CHECKSUMS}
    expected = set(CORE_ASSETS) | (set() if args.allow_missing_ipa else {IPA})
    missing, unexpected = sorted(expected - actual), sorted(actual - expected)
    if missing or unexpected:
        raise SystemExit(f"invalid release assets; missing={missing}, unexpected={unexpected}")

    checksum_path = directory / CHECKSUMS
    calculated = {name: digest(directory / name) for name in sorted(actual)}
    if args.write:
        checksum_path.write_text("".join(f"{value}  {name}\n" for name, value in calculated.items()), encoding="ascii")
    if not checksum_path.is_file():
        raise SystemExit("SHA256SUMS is missing; run with --write first")

    listed: dict[str, str] = {}
    for line in checksum_path.read_text(encoding="ascii").splitlines():
        value, separator, name = line.partition("  ")
        if not separator or len(value) != 64 or not name or name in listed:
            raise SystemExit(f"invalid SHA256SUMS line: {line!r}")
        listed[name] = value.lower()
    if set(listed) != actual:
        raise SystemExit("SHA256SUMS does not cover the exact release asset set")
    mismatches = [name for name in sorted(actual) if listed[name] != calculated[name]]
    if mismatches:
        raise SystemExit(f"checksum mismatch: {mismatches}")
    print(f"Release assets verified: {len(actual)} files, SHA256SUMS is complete.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
