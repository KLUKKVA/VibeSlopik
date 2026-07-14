import sys

from vibeslopik_host.cli import main


for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8", errors="replace")

raise SystemExit(main())
