#!/usr/bin/env python3
"""End-to-end contract test for the Python Host using the bundled fake app-server."""
from __future__ import annotations

import json
import http.client
import os
import socket
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "src"))

from vibeslopik_host.config import ConfigStore
from vibeslopik_host.host import HostHTTPServer, HostService, localize_codex_error
from vibeslopik_host.cli import host_status, run, start_background, stop_background
from PIL import Image


def free_port() -> int:
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return int(probe.getsockname()[1])


def request(port: int, token: str, method: str, path: str, body: dict | None = None) -> tuple[int, dict]:
    raw = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"http://127.0.0.1:{port}{path}", data=raw, method=method, headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            return response.status, json.loads(response.read())
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read())


def main() -> int:
    assert "VPN" in localize_codex_error("stream disconnected before completion")
    assert "/compact" in localize_codex_error("context window exceeded")
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        host_port = free_port()
        store = ConfigStore.load(root)
        store.value["host"].update({"port": host_port, "default_cwd": str(root), "codex_bin": shutil.which("node") or "node", "codex_args_json": json.dumps([str(REPO / "bridge" / "dev" / "fake-codex-app-server.mjs")])})
        store.save()
        service = HostService(store); service.start()
        media_source = root / "test-image.png"
        Image.new("RGB", (1200, 800), "red").save(media_source)
        media = service.register_media(str(media_source), "codex")
        assert media and str(media_source) not in json.dumps(media)
        thumbnail = service.media_data(media["id"], "thumbnail")
        assert thumbnail["mime"] == "image/jpeg" and thumbnail["bytes"] > 0
        original = service.media_data(media["id"], "original")
        assert original["bytes"] == media_source.stat().st_size
        server = HostHTTPServer(("127.0.0.1", host_port), service)
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        try:
            token = store.client_token
            assert request(host_port, token, "GET", "/healthz")[1]["ok"]
            assert service.info()["host"]["version"] == "1.0.0"
            assert request(host_port, token, "GET", "/api/capabilities")[1]["apiVersion"] == 2
            models = request(host_port, token, "GET", "/api/models")[1]["data"]
            assert [model["model"] for model in models] == ["fake"]
            status, created = request(host_port, token, "POST", "/api/threads", {"cwd": str(root)})
            assert status == 200 and created["thread"]["id"] == "thr_fake"
            status, override = request(host_port, token, "POST", "/api/threads/thr_fake/overrides", {"mode": "next_turn", "model": "fake", "reasoningEffort": "low"})
            assert status == 200 and override["override"]["model"] == "fake"
            body = {"text": "hello", "clientRequestId": "same-id", "cwd": str(root)}
            status, sent = request(host_port, token, "POST", "/api/threads/thr_fake/turns", body)
            assert status == 200 and sent["ok"]
            assert sent["delivery"] == "started" and sent["turnState"]["status"] == "completed"
            assert sent["turnState"]["settingsConfirmed"] and sent["turnState"]["model"] == "fake"
            status, loaded = request(host_port, token, "GET", "/api/threads/thr_fake")
            assert status == 200 and loaded["thread"]["activeTurn"]["assistantText"] == "Fake Codex app-server response."
            assert loaded["thread"]["threadSettings"]["effort"] == "low"
            status, replay = request(host_port, token, "POST", "/api/threads/thr_fake/turns", body)
            assert status == 200 and replay.get("idempotentReplay")
            status, failed = request(host_port, token, "POST", "/api/threads/thr_fake/turns", {"text": "FAIL_TEST", "clientRequestId": "fail-id"})
            assert status == 200 and failed["turnState"]["status"] == "failed"
            assert failed["turnState"]["error"] == "Synthetic Codex failure"
            assert request(host_port, token, "POST", "/api/speech/transcriptions", {})[0] == 400
            assert request(host_port, "wrong", "GET", "/api/home")[0] == 401
            assert request(host_port, "wrong", "POST", "/api/admin/shutdown", {})[0] == 401
            connection = http.client.HTTPConnection("127.0.0.1", host_port, timeout=5)
            connection.putrequest("POST", "/api/cache/clear")
            connection.putheader("Authorization", f"Bearer {token}")
            connection.putheader("Content-Length", str(32 * 1024 * 1024 + 1))
            connection.endheaders()
            assert connection.getresponse().status == 400
            connection.close()
            connection = http.client.HTTPConnection("127.0.0.1", host_port, timeout=5)
            connection.putrequest("POST", "/api/cache/clear")
            connection.putheader("Authorization", f"Bearer {token}")
            connection.putheader("Content-Length", "invalid")
            connection.endheaders()
            assert connection.getresponse().status == 400
            connection.close()
            status, stopping = request(host_port, token, "POST", "/api/admin/shutdown", {})
            assert status == 200 and stopping["stopping"]
            thread.join(timeout=3)
            assert not thread.is_alive()
            print("Python Host HTTP integration test passed.")
        finally:
            server.shutdown(); service.stop()
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        occupied = socket.socket()
        occupied.bind(("127.0.0.1", 0))
        occupied.listen(1)
        store = ConfigStore.load(root)
        store.value["app"]["configured"] = True
        store.value["host"].update({"port": occupied.getsockname()[1], "default_cwd": str(root), "codex_bin": shutil.which("node") or "node", "codex_args_json": json.dumps([str(REPO / "bridge" / "dev" / "fake-codex-app-server.mjs")])})
        store.save()
        try:
            assert run(store) == 4
        finally:
            occupied.close()
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        store = ConfigStore.load(root)
        store.value["app"]["configured"] = True
        store.value["host"].update({"port": free_port(), "default_cwd": str(root), "codex_bin": shutil.which("node") or "node", "codex_args_json": json.dumps([str(REPO / "bridge" / "dev" / "fake-codex-app-server.mjs")])})
        store.save()
        old_pythonpath = os.environ.get("PYTHONPATH", "")
        os.environ["PYTHONPATH"] = str(REPO / "src") + (os.pathsep + old_pythonpath if old_pythonpath else "")
        try:
            assert start_background(store) == 0
            assert host_status(store, quiet=True)
            assert stop_background(store) == 0
            assert not host_status(store, quiet=True)
            logs = "\n".join(path.read_text(encoding="utf-8", errors="replace") for path in (root / "data" / "logs").glob("*.log"))
            assert store.client_token not in logs
        finally:
            os.environ["PYTHONPATH"] = old_pythonpath
            if host_status(store, quiet=True):
                stop_background(store)
    print("Python Host integration test passed.")
    return 0


if __name__ == "__main__":
    import shutil
    raise SystemExit(main())
