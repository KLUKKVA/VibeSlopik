#!/usr/bin/env python3
"""Checks the full iPhone -> VPS relay -> Python Host request path."""
from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
import urllib.error
from pathlib import Path
from PIL import Image

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "src"))
from vibeslopik_host.config import ConfigStore
from vibeslopik_host.host import HostHTTPServer, HostService
from vibeslopik_host.relay import RelayAgent


def free_port() -> int:
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return int(probe.getsockname()[1])


def wait_relay(process: subprocess.Popen[str], port: int, timeout: float = 30) -> None:
    deadline = time.time() + timeout
    while True:
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/healthz", timeout=1):
                return
        except Exception:
            if process.poll() is not None:
                raise RuntimeError(process.stderr.read() if process.stderr else "Relay exited")
            if time.time() >= deadline:
                raise RuntimeError("Go relay did not start")
            time.sleep(0.2)


def main() -> int:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp); relay_port = free_port(); host_port = free_port()
        relay_binary = os.environ.get("VIBESLOPIK_RELAY_BIN")
        relay_command = [relay_binary] if relay_binary else [shutil.which("go") or "go", "-C", str(REPO / "relay-go"), "run", "-buildvcs=false", "."]
        relay_environment = {**os.environ, "GOCACHE": str(root / "go-cache"), "VIBESLOPIK_RELAY_PORT": str(relay_port), "VIBESLOPIK_RELAY_ADMIN_KEY": "admin", "VIBESLOPIK_RELAY_STATE": str(root / "relay.json")}
        relay = subprocess.Popen(relay_command, cwd=REPO, env=relay_environment, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        try:
            wait_relay(relay, relay_port)
            store = ConfigStore.load(root)
            store.value["host"].update({"port": host_port, "default_cwd": str(root), "codex_bin": shutil.which("node") or "node", "codex_args_json": json.dumps([str(REPO / "bridge" / "dev" / "fake-codex-app-server.mjs")])})
            store.value["relay"].update({"url": f"http://127.0.0.1:{relay_port}", "host_id": "test-host", "enabled": True})
            store.secrets.update({"RELAY_HOST_SECRET": "host-secret", "RELAY_ADMIN_KEY": "admin"}); store.save()
            service = HostService(store); service.start()
            server = HostHTTPServer(("127.0.0.1", host_port), service); threading.Thread(target=server.serve_forever, daemon=True).start()
            agent = RelayAgent(store, host_port); agent.start(); time.sleep(1)
            req = urllib.request.Request(f"http://127.0.0.1:{relay_port}/v1/client/test-host/api/capabilities", headers={"Authorization": f"Bearer {store.client_token}"})
            with urllib.request.urlopen(req, timeout=20) as response:
                payload = json.loads(response.read())
            assert response.status == 200 and payload["apiVersion"] == 2
            image_path = root / "relay-media.png"
            Image.new("RGB", (1000, 700), "green").save(image_path)
            media = service.register_media(str(image_path), "codex")
            req = urllib.request.Request(f"http://127.0.0.1:{relay_port}/v1/client/test-host/api/media/{media['id']}?variant=thumbnail", headers={"Authorization": f"Bearer {store.client_token}"})
            with urllib.request.urlopen(req, timeout=20) as response:
                media_payload = json.loads(response.read())
            assert response.status == 200 and media_payload["mime"] == "image/jpeg" and media_payload["base64"]
            # A phone can close its request before Host finishes. The relay
            # then legitimately returns 404 to a late reply; this must not
            # crash the delivery thread or reconnect the whole agent.
            agent._deliver({"requestId": "expired-request", "method": "GET", "path": "/api/capabilities", "query": ""}, {"X-VibeSlopik-Host-Secret": "host-secret"})
            relay.terminate()
            relay.wait(timeout=5)
            relay = subprocess.Popen(relay_command, cwd=REPO, env=relay_environment, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
            wait_relay(relay, relay_port)
            deadline = time.time() + 30
            while True:
                try:
                    reconnect = urllib.request.Request(f"http://127.0.0.1:{relay_port}/v1/client/test-host/api/capabilities", headers={"Authorization": f"Bearer {store.client_token}"})
                    with urllib.request.urlopen(reconnect, timeout=5) as response:
                        assert json.loads(response.read())["apiVersion"] == 2
                    break
                except (OSError, urllib.error.URLError):
                    if time.time() >= deadline:
                        raise RuntimeError("Host agent did not reconnect after Relay restart")
                    time.sleep(0.5)
            relay_log = (root / "data" / "logs" / "relay-agent.jsonl").read_text(encoding="utf-8")
            assert "relay_connected" in relay_log and "late_reply_ignored" in relay_log
            assert store.client_token not in relay_log and "host-secret" not in relay_log and "admin" not in relay_log
            print("Python Host relay integration test passed.")
            server.shutdown(); service.stop(); agent.stop()
            return 0
        finally:
            relay.terminate(); relay.wait(timeout=5)


if __name__ == "__main__":
    raise SystemExit(main())
