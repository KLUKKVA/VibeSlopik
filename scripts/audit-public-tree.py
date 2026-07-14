from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXCLUDED_PARTS = {
    ".agents",
    ".codex-remote-attachments",
    ".git",
    ".gocache",
    ".test-venv",
    ".theos",
    ".venv",
    ".wsl-build",
    "__pycache__",
    "build",
    "data",
    "dist",
    "node_modules",
    "packages",
    "sdk",
    "tools",
    "venv",
}
EXCLUDED_PREFIXES = (".relay-", ".thread-")
EXCLUDED_NAMES = {
    ".vibeslopik-relay-admin-key",
    ".vibeslopik-relay.txt",
    ".vibeslopik-token",
}
TEXT_SUFFIXES = {
    ".c",
    ".go",
    ".h",
    ".json",
    ".md",
    ".m",
    ".plist",
    ".ps1",
    ".py",
    ".sh",
    ".toml",
    ".txt",
    ".xml",
    ".yml",
    ".yaml",
}
SECRET_PREFIXES = ("bdk" + "MJ1", "9dI" + "dWbs", "0U8" + "LZX")
FORBIDDEN = {
    "private Windows workspace path": re.compile(r"[A-Za-z]:\\(?:Users|ClaudeProjects)\\", re.I),
    "known private VPS address": re.compile(r"\b31\.76\.10\.38\b"),
    "embedded bearer-like secret": re.compile(r"\b(?:" + "|".join(SECRET_PREFIXES) + r")[A-Za-z0-9_-]*"),
    "probable UTF-8 mojibake": re.compile(r"(?:Р[°µёѕїЅґ]|С[‚ѓЏ])"),
}


def public_files(tracked_only: bool = False) -> list[Path]:
    if tracked_only:
        result = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, capture_output=True, check=True).stdout
        return [ROOT / item.decode("utf-8") for item in result.split(b"\0") if item]
    result: list[Path] = []
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(ROOT)
        if any(part in EXCLUDED_PARTS for part in relative.parts):
            continue
        if path.name in EXCLUDED_NAMES or path.name.startswith(EXCLUDED_PREFIXES):
            continue
        result.append(path)
    return result


def main() -> int:
    unknown = [argument for argument in sys.argv[1:] if argument != "--tracked"]
    if unknown:
        print("usage: audit-public-tree.py [--tracked]", file=sys.stderr)
        return 2
    tracked_only = "--tracked" in sys.argv[1:]
    failures: list[str] = []
    files = public_files(tracked_only)
    for path in files:
        if path.suffix.lower() not in TEXT_SUFFIXES and path.name not in {"LICENSE", ".gitignore"}:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            failures.append(f"non-UTF-8 public text file: {path.relative_to(ROOT)}")
            continue
        for label, pattern in FORBIDDEN.items():
            match = pattern.search(text)
            if match:
                line = text.count("\n", 0, match.start()) + 1
                failures.append(f"{path.relative_to(ROOT)}:{line}: {label}")
        if path.suffix.lower() == ".md":
            for match in re.finditer(r"\[[^\]]+\]\(([^)]+)\)", text):
                destination = match.group(1).split("#", 1)[0]
                if not destination or destination.startswith(("http://", "https://", "mailto:")):
                    continue
                target = (path.parent / destination).resolve()
                try:
                    target.relative_to(ROOT)
                except ValueError:
                    failures.append(f"{path.relative_to(ROOT)}: link escapes repository: {destination}")
                    continue
                if not target.exists():
                    line = text.count("\n", 0, match.start()) + 1
                    failures.append(f"{path.relative_to(ROOT)}:{line}: missing local link: {destination}")
    if failures:
        print("Public tree audit failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    scope = "tracked " if tracked_only else ""
    print(f"Public tree audit passed ({len(files)} {scope}files checked).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
