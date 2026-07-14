#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VERIFY = ROOT / "scripts" / "verify-release-assets.py"
CORE = {
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


def run(directory: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run([sys.executable, str(VERIFY), str(directory), *arguments], capture_output=True, text=True)


def main() -> int:
    with tempfile.TemporaryDirectory() as temporary:
        directory = Path(temporary)
        for name in CORE:
            (directory / name).write_bytes((name + "\n").encode("ascii"))
        draft = run(directory, "--allow-missing-ipa", "--write")
        assert draft.returncode == 0, draft.stderr
        (directory / "VibeSlopik.ipa").write_bytes(b"ipa")
        final = run(directory, "--write")
        assert final.returncode == 0, final.stderr
        assert len((directory / "SHA256SUMS").read_text(encoding="ascii").splitlines()) == len(CORE) + 1
        (directory / "VibeSlopik.ipa").write_bytes(b"tampered")
        assert run(directory).returncode != 0
        (directory / "unexpected.txt").write_text("no", encoding="ascii")
        assert run(directory, "--write").returncode != 0
    print("Release asset verifier tests passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
