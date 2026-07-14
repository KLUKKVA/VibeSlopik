#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import stat
import subprocess
import tempfile
import zipfile
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", nargs="?", help="Host zip; autodetected from dist when omitted")
    args = parser.parse_args()
    archives = [Path(args.archive)] if args.archive else sorted(Path("dist").glob("vibeslopik-host-*.zip"))
    if len(archives) != 1:
        raise SystemExit(f"expected one Host archive, found {len(archives)}")
    archive = archives[0]
    with zipfile.ZipFile(archive) as bundle:
        names = bundle.namelist()
        lowered = [name.lower().replace("\\", "/") for name in names]
        forbidden = ("/data/", "secret.env", "config.toml", ".log", "client-token")
        for name in lowered:
            if any(marker in name for marker in forbidden):
                raise SystemExit(f"private runtime file in Host archive: {name}")
        candidates = [name for name in names if not name.endswith(("/", "\\")) and Path(name).name in {"VibeSlopik-Host", "VibeSlopik-Host.exe"}]
        if len(candidates) != 1:
            raise SystemExit(f"expected one Host executable, found {candidates}")
        with tempfile.TemporaryDirectory() as directory:
            bundle.extractall(directory)
            executable = Path(directory) / candidates[0]
            if os.name != "nt":
                executable.chmod(executable.stat().st_mode | stat.S_IXUSR)
            completed = subprocess.run([str(executable), "--help"], capture_output=True, text=True, timeout=30)
            if completed.returncode != 0 or "vibeslopik-host" not in (completed.stdout + completed.stderr).lower():
                raise SystemExit(f"Host executable smoke test failed: {completed.stdout}\n{completed.stderr}")
            runtime = Path(directory) / "runtime-test"
            completed = subprocess.run([str(executable), "--root", str(runtime), "config"], capture_output=True, text=True, timeout=30)
            if completed.returncode != 0 or '"secrets"' not in completed.stdout or "CLIENT_TOKEN" not in completed.stdout:
                raise SystemExit(f"Host clean-runtime test failed: {completed.stdout}\n{completed.stderr}")
            config = runtime / "data" / "config.toml"
            secret = runtime / "data" / "secret.env"
            if not config.is_file() or not secret.is_file():
                raise SystemExit("Host did not create an isolated runtime configuration")
            secret_text = secret.read_text(encoding="utf-8")
            if secret_text and secret_text in completed.stdout:
                raise SystemExit("Host config output exposed secret.env")
            config.write_text('[host\nport = "broken"', encoding="utf-8")
            completed = subprocess.run([str(executable), "--root", str(runtime), "config"], capture_output=True, text=True, timeout=30)
            if completed.returncode != 0 or "recovered" not in completed.stderr.lower():
                raise SystemExit(f"Packaged Host did not recover a damaged config: {completed.stdout}\n{completed.stderr}")
            if len(list((runtime / "data").glob("config.toml.corrupt-*"))) != 1:
                raise SystemExit("Packaged Host did not preserve the damaged config")
            completed = subprocess.run([str(executable), "--root", str(runtime), "status"], capture_output=True, text=True, timeout=30)
            if completed.returncode != 1 or "stopped" not in (completed.stdout + completed.stderr).lower():
                raise SystemExit(f"Packaged Host status test failed: {completed.stdout}\n{completed.stderr}")
    print(f"Host package test passed: {archive} ({archive.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
