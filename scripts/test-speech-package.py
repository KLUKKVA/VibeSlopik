#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import stat
import subprocess
import tempfile
import zipfile
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", nargs="?", help="Speech Pack zip; autodetected from dist when omitted")
    args = parser.parse_args()
    archives = [Path(args.archive)] if args.archive else sorted(Path("dist").glob("vibeslopik-speech-*.zip"))
    if len(archives) != 1:
        raise SystemExit(f"expected one Speech Pack archive, found {len(archives)}")
    archive = archives[0]
    with zipfile.ZipFile(archive) as bundle:
        names = bundle.namelist()
        candidates = [name for name in names if not name.endswith(("/", "\\")) and Path(name).name in {"VibeSlopik-Speech", "VibeSlopik-Speech.exe"}]
        if len(candidates) != 1:
            raise SystemExit(f"expected one Speech worker, found {candidates}")
        if any("model.bin" in name.lower() or "secret.env" in name.lower() for name in names):
            raise SystemExit("Speech Pack contains a model or secret")
        with tempfile.TemporaryDirectory() as directory:
            bundle.extractall(directory)
            executable = Path(directory) / candidates[0]
            if os.name != "nt":
                executable.chmod(executable.stat().st_mode | stat.S_IXUSR)
            completed = subprocess.run([str(executable), "--check"], capture_output=True, text=True, timeout=60)
            try:
                payload = json.loads(completed.stdout.strip())
            except json.JSONDecodeError as error:
                raise SystemExit(f"Speech worker returned invalid JSON: {completed.stdout}\n{completed.stderr}") from error
            if completed.returncode != 0 or not payload.get("ok") or payload.get("backend") != "faster-whisper":
                raise SystemExit(f"Speech worker self-check failed: {payload}\n{completed.stderr}")
    print(f"Speech package test passed: {archive} ({archive.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
