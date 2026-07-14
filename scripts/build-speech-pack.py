#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import platform
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def target_name() -> str:
    system = {"Windows": "windows", "Darwin": "macos", "Linux": "linux"}[platform.system()]
    arch = "arm64" if platform.machine().lower() in {"arm64", "aarch64"} else "x64"
    return f"{system}-{arch}"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--install-build-deps", action="store_true")
    parser.add_argument("--expect-target", help="fail when the runner architecture does not match this target")
    args = parser.parse_args()
    if args.install_build_deps:
        subprocess.run([sys.executable, "-m", "pip", "install", "pyinstaller>=6.10,<7", "faster-whisper>=1.1,<2"], check=True)
    target = target_name()
    if args.expect_target and args.expect_target != target:
        raise RuntimeError(f"runner target is {target}, expected {args.expect_target}")
    build = ROOT / "build" / "speech" / target
    shutil.rmtree(build, ignore_errors=True)
    build.mkdir(parents=True)
    subprocess.run([sys.executable, "-m", "PyInstaller", "--noconfirm", "--clean", "--onedir", "--name", "VibeSlopik-Speech", "--distpath", str(build / "dist"), "--workpath", str(build / "work"), "--specpath", str(build), str(ROOT / "scripts" / "speech-worker.py")], cwd=ROOT, check=True)
    output = ROOT / "dist"
    output.mkdir(exist_ok=True)
    archive = Path(shutil.make_archive(str(output / f"vibeslopik-speech-{target}"), "zip", build / "dist", "VibeSlopik-Speech"))
    print(f"Built {archive}\nSHA256 {hashlib.sha256(archive.read_bytes()).hexdigest()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
