from __future__ import annotations

import json
import queue
import subprocess
import threading
import time
from collections import deque
from typing import Any, Callable


class CodexRPC:
    """Small stdio JSON-RPC client for codex app-server."""

    def __init__(self, binary: str, cwd: str, on_event: Callable[[dict], None], args: list[str] | None = None):
        self.binary, self.cwd, self.on_event, self.args = binary, cwd, on_event, args or ["app-server"]
        self.process: subprocess.Popen[str] | None = None
        self.pending: dict[int, queue.Queue[dict]] = {}
        self.pending_lock = threading.Lock()
        self.next_id = 1
        self.ready = False
        self.error = "not started"
        self.initialize_result: dict = {}
        self.feature_status: dict[str, dict] = {}
        self.feature_lock = threading.Lock()

    def start(self) -> None:
        if self.process and self.process.poll() is None:
            return
        self.process = subprocess.Popen([self.binary, *self.args], cwd=self.cwd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf-8", bufsize=1)
        threading.Thread(target=self._read_stdout, daemon=True, name="codex-rpc-out").start()
        threading.Thread(target=self._read_stderr, daemon=True, name="codex-rpc-err").start()
        self.initialize_result = self.request("initialize", {"clientInfo": {"name": "vibeslopik_host", "title": "VibeSlopik Host", "version": "1.0.0"}, "capabilities": {"experimentalApi": True}})
        self.notify("initialized", {})
        self.ready = True
        self.error = ""

    def probe_features(self, mode: str) -> dict[str, dict]:
        """Probe non-mutating protocol features independently.

        Codex does not expose a stable all-method manifest, so compatibility
        is established from safe reads instead of its package version.
        """
        probes = {
            "models": ("model/list", {"includeHidden": True, "limit": 1}),
            "threads": ("thread/list", {"archived": False, "limit": 1, "sortKey": "updated_at", "sortDirection": "desc", "useStateDbOnly": False}),
        }
        status: dict[str, dict] = {
            "initialize": {"state": "available", "reason": "initialize succeeded"},
            "turns": {"state": "assumed", "reason": "turn/start is mutating and is checked on first use"},
            "approvals": {"state": "assumed", "reason": "approval requests are event driven"},
            "rateLimits": {"state": "assumed", "reason": "rate-limit events are optional"},
        }
        if mode == "forced":
            for name in probes:
                status[name] = {"state": "unchecked", "reason": "forced mode skips startup probes"}
            self.feature_status = status
            return status
        for name, (method, params) in probes.items():
            try:
                self.request(method, params, timeout=20)
                status[name] = {"state": "available", "reason": f"{method} succeeded"}
            except Exception as error:
                status[name] = {"state": "unavailable", "reason": str(error)[:500]}
        self.feature_status = status
        if mode == "normal":
            unavailable = [name for name in probes if status[name]["state"] != "available"]
            if unavailable:
                raise RuntimeError("Codex protocol check failed: " + ", ".join(unavailable) + ". Use compatible or forced mode after reviewing diagnostics.")
        return status

    def mark_feature(self, name: str, state: str, reason: str) -> None:
        with self.feature_lock:
            self.feature_status[name] = {"state": state, "reason": reason[:500]}

    def feature_snapshot(self) -> dict[str, dict]:
        with self.feature_lock:
            return {name: dict(value) for name, value in self.feature_status.items()}

    def request_feature(self, feature: str, method: str, params: dict, timeout: float = 120.0) -> dict:
        try:
            result = self.request(method, params, timeout=timeout)
        except Exception as error:
            self.mark_feature(feature, "unavailable", f"{method} failed: {error}")
            raise
        self.mark_feature(feature, "available", f"{method} succeeded")
        return result

    def stop(self) -> None:
        process = self.process
        self.ready = False
        if process and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        self.process = None
        self._fail_pending("codex app-server stopped")

    def _fail_pending(self, message: str) -> None:
        with self.pending_lock:
            waiters = list(self.pending.values())
            self.pending.clear()
        for waiter in waiters:
            try:
                waiter.put_nowait({"error": {"message": message}})
            except queue.Full:
                pass

    def _read_stdout(self) -> None:
        assert self.process and self.process.stdout
        for line in self.process.stdout:
            try:
                message = json.loads(line)
            except json.JSONDecodeError:
                self.on_event({"type": "codex.invalid_json", "payload": {"line": line[:500]}})
                continue
            if "id" in message and message["id"] in self.pending:
                with self.pending_lock:
                    waiter = self.pending.pop(message["id"], None)
                if waiter:
                    waiter.put(message)
            else:
                self.on_event(message)
        self.ready = False
        self.error = "codex app-server stopped"
        self._fail_pending(self.error)

    def _read_stderr(self) -> None:
        assert self.process and self.process.stderr
        for line in self.process.stderr:
            text = line.strip()
            if text:
                self.error = text
                self.on_event({"type": "codex.stderr", "payload": {"text": text[:1000]}})

    def _send(self, message: dict) -> None:
        if not self.process or self.process.poll() is not None or not self.process.stdin:
            raise RuntimeError("codex app-server is not running")
        self.process.stdin.write(json.dumps(message, ensure_ascii=False) + "\n")
        self.process.stdin.flush()

    def notify(self, method: str, params: dict) -> None:
        self._send({"method": method, "params": params})

    def respond(self, request_id: int, result: dict) -> None:
        self._send({"id": request_id, "result": result})

    def request(self, method: str, params: dict, timeout: float = 120.0) -> dict:
        if not self.process or self.process.poll() is not None:
            raise RuntimeError("codex app-server is not running")
        with self.pending_lock:
            request_id = self.next_id
            self.next_id += 1
            waiter: queue.Queue[dict] = queue.Queue(maxsize=1)
            self.pending[request_id] = waiter
        self._send({"id": request_id, "method": method, "params": params})
        try:
            reply = waiter.get(timeout=timeout)
        except queue.Empty as error:
            with self.pending_lock:
                self.pending.pop(request_id, None)
            raise TimeoutError(f"codex RPC timed out: {method}") from error
        if "error" in reply:
            error_value = reply["error"]
            if isinstance(error_value, dict):
                message = error_value.get("message") or error_value.get("code") or "codex RPC error"
            else:
                message = str(error_value) or "codex RPC error"
            raise RuntimeError(str(message))
        return reply.get("result", {})
