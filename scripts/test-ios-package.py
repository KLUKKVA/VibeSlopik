#!/usr/bin/env python3
"""Validates the final legacy iOS IPA without requiring Apple tooling."""
from __future__ import annotations

import plistlib
import struct
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IPA = ROOT / "dist" / "VibeSlopik.ipa"


def png_size(data: bytes) -> tuple[int, int]:
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    return struct.unpack(">II", data[16:24])


def main() -> int:
    assert IPA.exists() and IPA.stat().st_size < 5 * 1024 * 1024
    with zipfile.ZipFile(IPA) as archive:
        names = set(archive.namelist())
        root = "Payload/VibeSlopik.app/"
        required = {root + "VibeSlopik", root + "Info.plist", root + "Icon.png", root + "Icon@2x.png"}
        assert required <= names
        info = plistlib.loads(archive.read(root + "Info.plist"))
        assert info["CFBundleShortVersionString"] == "1.0.0"
        assert info["CFBundleVersion"] == "1.0.0"
        assert info["MinimumOSVersion"] == "6.0"
        assert png_size(archive.read(root + "Icon.png")) == (57, 57)
        assert png_size(archive.read(root + "Icon@2x.png")) == (114, 114)
        assert not any("Master" in name for name in names)
    print(f"IPA package test passed: {IPA.stat().st_size} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
