from __future__ import annotations

import json
import random
import threading
import time
from http.client import HTTPConnection
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from .config import ConfigStore, data_dir


class RelayAgent(threading.Thread):
    """Long-poll relay client. It only forwards authenticated JSON requests."""

    def __init__(self, config: ConfigStore, local_port: int):
        super().__init__(daemon=True, name="vibeslopik-relay")
        self.config, self.local_port = config, local_port
        self.stop_event = threading.Event()
        self.inflight = threading.BoundedSemaphore(8)
        self.log_lock = threading.Lock()

    def _log(self, event: str, **fields: object) -> None:
        path = data_dir(self.config.root) / "logs" / "relay-agent.jsonl"
        safe = {"time": int(time.time() * 1000), "event": event}
        for key, value in fields.items():
            safe[key] = str(value).replace("\r", " ").replace("\n", " ")[:500]
        with self.log_lock:
            if path.exists() and path.stat().st_size > 2 * 1024 * 1024:
                path.replace(path.with_suffix(".jsonl.previous"))
            with path.open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(safe, ensure_ascii=False) + "\n")

    def stop(self) -> None:
        self.stop_event.set()

    def _call(self, path: str, method: str = "GET", body: dict | None = None, headers: dict | None = None, timeout: int = 40) -> dict:
        base = self.config.value["relay"]["url"].rstrip("/")
        request = Request(base + path, method=method, headers={"Connection": "close", "Content-Type": "application/json", **(headers or {})})
        payload = json.dumps(body).encode("utf-8") if body is not None else None
        try:
            with urlopen(request, data=payload, timeout=timeout) as response:
                data = json.loads(response.read().decode("utf-8") or "{}")
                if response.status >= 400:
                    raise RuntimeError(data.get("error", f"relay HTTP {response.status}"))
                return data
        except HTTPError as error:
            try:
                detail = json.loads(error.read().decode("utf-8") or "{}").get("error", "")
            except Exception:
                detail = ""
            raise RuntimeError(detail or f"relay HTTP {error.code}") from error
        except Exception as error:
            raise RuntimeError(str(error)) from error

    def _forward(self, request: dict) -> dict:
        try:
            conn_class = HTTPConnection
            conn = conn_class("127.0.0.1", self.local_port, timeout=120)
            body = json.dumps(request.get("body") or {}).encode("utf-8") if request.get("method") == "POST" else None
            conn.request(request.get("method", "GET"), request["path"] + request.get("query", ""), body=body, headers={"Authorization": f"Bearer {self.config.client_token}", "Content-Type": "application/json", "Connection": "close"})
            response = conn.getresponse()
            raw = response.read().decode("utf-8")
            conn.close()
            return {"status": response.status, "body": json.loads(raw) if raw else {}}
        except Exception as error:
            return {"status": 502, "body": {"ok": False, "error": str(error)}}

    def _deliver(self, request: dict, headers: dict) -> None:
        with self.inflight:
            reply = self._forward(request)
            try:
                self._call(f"/v1/host/{self.config.value['relay']['host_id']}/reply", method="POST", headers=headers, body={"requestId": request["requestId"], "response": reply}, timeout=30)
                self._log("request_delivered", request_id=request.get("requestId", ""), status=reply.get("status", ""))
            except RuntimeError as error:
                # The iPhone may have cancelled a long request. The relay has
                # already discarded its waiter, so do not restart the agent.
                message = str(error).lower()
                if "request not found" not in message and "relay http 404" not in message:
                    self._log("reply_failed", request_id=request.get("requestId", ""), error=error)
                    raise
                self._log("late_reply_ignored", request_id=request.get("requestId", ""))

    def _register(self, relay: dict, host_secret: str) -> None:
        admin_key = self.config.secrets.get("RELAY_ADMIN_KEY", "")
        if not admin_key:
            return
        self._call("/v1/hosts/register", method="POST", headers={"X-VibeSlopik-Admin-Key": admin_key}, body={"hostId": relay["host_id"], "hostSecret": host_secret, "clientToken": self.config.client_token, "name": self.config.value["host"].get("name", "Codex Host")}, timeout=15)

    def run(self) -> None:
        relay = self.config.value["relay"]
        host_secret = self.config.secrets.get("RELAY_HOST_SECRET", "")
        if not relay.get("enabled") or not relay.get("url") or not relay.get("host_id") or not host_secret:
            return
        delay = 1.0
        headers = {"X-VibeSlopik-Host-Secret": host_secret}
        needs_register = True
        while not self.stop_event.is_set():
            try:
                # Registration writes persistent relay state. Do it once per
                # connection cycle, never before every long-poll request.
                if needs_register:
                    self._register(relay, host_secret)
                    needs_register = False
                    self._log("relay_connected")
                result = self._call(f"/v1/host/{relay['host_id']}/poll", headers=headers, timeout=15)
                delay = 1.0
                request = result.get("request")
                if not request:
                    self.stop_event.wait(0.7)
                    continue
                # Voice model loading and long Codex turns must not stop the
                # polling loop; otherwise the iPhone appears disconnected.
                threading.Thread(target=self._deliver, args=(request, headers.copy()), daemon=True, name="vibeslopik-relay-request").start()
            except Exception as error:
                self._log("relay_retry", delay=delay, error=error)
                needs_register = True
                self.stop_event.wait(delay + random.uniform(0, 0.25))
                delay = min(delay * 2, 30.0)
