#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def platform_name() -> str:
    system = {"Windows": "windows", "Darwin": "macos", "Linux": "linux"}.get(platform.system())
    machine = platform.machine().lower()
    arch = "arm64" if machine in {"arm64", "aarch64"} else "x64"
    if not system:
        raise RuntimeError(f"unsupported Host platform: {platform.system()}")
    return f"{system}-{arch}"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--install-build-deps", action="store_true")
    parser.add_argument("--expect-target", help="fail when the runner architecture does not match this target")
    args = parser.parse_args()
    if args.install_build_deps:
        subprocess.run([sys.executable, "-m", "pip", "install", "--disable-pip-version-check", "pyinstaller>=6.10,<7", "Pillow>=10,<13"], check=True)
    try:
        import PyInstaller  # noqa: F401
    except ImportError as error:
        raise RuntimeError("PyInstaller is missing; use --install-build-deps") from error

    target = platform_name()
    if args.expect_target and args.expect_target != target:
        raise RuntimeError(f"runner target is {target}, expected {args.expect_target}")
    build_root = ROOT / "build" / "host" / target
    dist_root = ROOT / "dist"
    shutil.rmtree(build_root, ignore_errors=True)
    build_root.mkdir(parents=True)
    dist_root.mkdir(exist_ok=True)
    name = "VibeSlopik-Host"
    command = [
        sys.executable, "-m", "PyInstaller", "--noconfirm", "--clean", "--onedir",
        "--name", name, "--distpath", str(build_root / "dist"), "--workpath", str(build_root / "work"),
        "--specpath", str(build_root), "--paths", str(ROOT / "src"),
        "--exclude-module", "faster_whisper", "--exclude-module", "ctranslate2", "--exclude-module", "huggingface_hub",
        "--exclude-module", "numpy", "--exclude-module", "onnxruntime", "--exclude-module", "av",
        str(ROOT / "scripts" / "host-entry.py"),
    ]
    subprocess.run(command, cwd=ROOT, check=True)
    package_dir = build_root / "dist" / name
    (package_dir / "README-FIRST.txt").write_text(
        "VibeSlopik Host 1.0.0\n\nRun VibeSlopik-Host and follow the menu.\n"
        "Запустите VibeSlopik-Host и следуйте меню.\n",
        encoding="utf-8",
    )
    archive_base = dist_root / f"vibeslopik-host-{target}"
    archive = Path(shutil.make_archive(str(archive_base), "zip", package_dir.parent, package_dir.name))
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    print(f"Built {archive} ({archive.stat().st_size} bytes)\nSHA256 {digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
