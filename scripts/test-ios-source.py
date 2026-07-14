from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "ios" / "LegacyRemote"
RUSSIAN = re.compile(r"[А-Яа-яЁё]|\\u04[0-9a-fA-F]{2}")


def main() -> int:
    failures: list[str] = []
    for path in sorted(SOURCE.glob("*.m")):
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if RUSSIAN.search(line) and "VSL(" not in line:
                failures.append(f"{path.name}:{number}: user-facing Russian text is not localized")
    plist = (SOURCE / "Resources" / "Info.plist").read_text(encoding="utf-8")
    if "<string>6.0</string>" not in plist:
        failures.append("Info.plist: deployment target is not iOS 6.0")
    makefile = (SOURCE / "Makefile").read_text(encoding="utf-8")
    if not re.search(r"^ARCHS\s*:?=\s*armv7\s*$", makefile, re.MULTILINE):
        failures.append("Makefile: release architecture is not armv7")
    if failures:
        raise SystemExit("iOS source audit failed:\n- " + "\n- ".join(failures))
    print("iOS source audit passed: localization, iOS 6 target and armv7.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
