from __future__ import annotations

import os
import shlex
import subprocess
import sys
from pathlib import Path


def _command(root: Path) -> list[str]:
    if getattr(sys, "frozen", False):
        return [str(Path(sys.executable).resolve()), "--root", str(root), "run"]
    return [str(Path(sys.executable).resolve()), "-m", "vibeslopik_host", "--root", str(root), "run"]


def target() -> Path:
    if sys.platform == "win32":
        appdata = Path(os.environ.get("APPDATA", Path.home() / "AppData/Roaming"))
        return appdata / "Microsoft/Windows/Start Menu/Programs/Startup/VibeSlopik Host.cmd"
    if sys.platform == "darwin":
        return Path.home() / "Library/LaunchAgents/com.vibeslopik.host.plist"
    return Path.home() / ".config/systemd/user/vibeslopik-host.service"


def status() -> dict:
    path = target()
    return {"enabled": path.is_file(), "path": str(path), "platform": sys.platform}


def install(root: Path) -> dict:
    path = target()
    path.parent.mkdir(parents=True, exist_ok=True)
    command = _command(root)
    if sys.platform == "win32":
        content = "@echo off\r\nstart \"VibeSlopik Host\" /min " + subprocess.list2cmdline(command) + "\r\n"
    elif sys.platform == "darwin":
        arguments = "".join(f"    <string>{_xml(item)}</string>\n" for item in command)
        content = f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.vibeslopik.host</string>
<key>ProgramArguments</key><array>
{arguments}</array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><false/>
<key>StandardOutPath</key><string>{_xml(str(root / 'data/logs/autostart.log'))}</string>
<key>StandardErrorPath</key><string>{_xml(str(root / 'data/logs/autostart-error.log'))}</string>
</dict></plist>
'''
    else:
        executable = " ".join(shlex.quote(item) for item in command)
        content = f'''[Unit]
Description=VibeSlopik Host
After=network-online.target

[Service]
Type=simple
ExecStart={executable}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
'''
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(content, encoding="utf-8")
    os.replace(temporary, path)
    if sys.platform == "darwin":
        subprocess.run(["launchctl", "unload", str(path)], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["launchctl", "load", str(path)], check=True)
    elif sys.platform != "win32":
        subprocess.run(["systemctl", "--user", "daemon-reload"], check=True)
        subprocess.run(["systemctl", "--user", "enable", "--now", "vibeslopik-host.service"], check=True)
    return status()


def remove() -> dict:
    path = target()
    if sys.platform == "darwin" and path.exists():
        subprocess.run(["launchctl", "unload", str(path)], check=False)
    elif sys.platform != "win32":
        subprocess.run(["systemctl", "--user", "disable", "--now", "vibeslopik-host.service"], check=False)
    path.unlink(missing_ok=True)
    return status()


def _xml(value: str) -> str:
    return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")
