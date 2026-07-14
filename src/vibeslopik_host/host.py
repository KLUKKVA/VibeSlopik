from __future__ import annotations

import base64
import binascii
import hashlib
import hmac
import json
import mimetypes
import os
import re
import shutil
import threading
import time
import uuid
from collections import OrderedDict, deque
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, unquote, urlparse

from .config import ConfigStore, data_dir
from .rpc import CodexRPC
from .speech import SpeechService


MAX_BODY = 32 * 1024 * 1024


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def normalize_cwd(value: str) -> str:
    return value.replace("\\", "/").rstrip("/").lower()


def text_from_content(value: Any) -> str:
    if isinstance(value, str):
        return value
    if not isinstance(value, list):
        return ""
    return "\n".join(str(part.get("text") or part.get("content") or "") for part in value if isinstance(part, dict))


def localize_codex_error(value: str, language: str = "ru") -> str:
    text = value.strip()
    lowered = text.lower()
    english = language == "en"
    if "reconnecting" in lowered:
        return "Codex lost its OpenAI connection and is reconnecting..." if english else "Codex потерял соединение с OpenAI и переподключается..."
    if "stream disconnected" in lowered or "error sending request" in lowered or "socket" in lowered:
        return "Codex could not connect to OpenAI. Check VPN and internet on the computer." if english else "Codex не смог подключиться к OpenAI. Проверьте VPN и интернет на компьютере."
    if "usage limit" in lowered or "session budget" in lowered:
        return "The Codex limit is exhausted. Check the next reset time." if english else "Лимит Codex исчерпан. Проверьте время следующего сброса."
    if "unauthorized" in lowered:
        return "Codex authorization expired. Sign in again on the computer." if english else "Авторизация Codex истекла. Войдите в аккаунт на компьютере заново."
    if "context window" in lowered:
        return "The thread context is full. Run /compact." if english else "Контекст ветки переполнен. Выполните /compact."
    if "model" in lowered and "not found" in lowered:
        return "The selected model is no longer available. Choose another model." if english else "Выбранная модель больше недоступна. Выберите другую модель."
    return text or ("Unknown Codex error" if english else "Неизвестная ошибка Codex")


class HostService:
    def __init__(self, config: ConfigStore):
        self.config = config
        self.events: deque[dict] = deque(maxlen=1000)
        self.event_seq = 0
        self.approvals: dict[str, dict] = {}
        self.usage: dict[str, dict] = {}
        self.idempotency: OrderedDict[str, dict] = OrderedDict()
        self.thread_overrides: dict[str, dict] = {}
        self.thread_settings: dict[str, dict] = {}
        self.resumed_threads: set[str] = set()
        self.turns: dict[str, dict] = {}
        self.media: dict[str, dict] = {}
        self.thread_turns: dict[str, str] = {}
        self.lock = threading.RLock()
        self.turn_condition = threading.Condition(self.lock)
        try:
            codex_args = json.loads(config.value["host"].get("codex_args_json", "[\"app-server\"]"))
        except json.JSONDecodeError:
            codex_args = ["app-server"]
        self.rpc = CodexRPC(config.value["host"]["codex_bin"], config.value["host"]["default_cwd"], self._event, codex_args)
        speech = config.value["speech"]
        self.speech = SpeechService(data_dir(config.root) / "models", bool(speech["enabled"]), str(speech["profile"]), int(speech["idle_unload_seconds"]), data_dir(config.root) / "speech-pack")

    def start(self) -> None:
        self.cleanup_cache()
        try:
            self.rpc.start()
            mode = str(self.config.value["host"].get("compatibility_mode", "normal"))
            self.rpc.probe_features(mode)
        except Exception:
            self.rpc.stop()
            raise

    def stop(self) -> None:
        self.rpc.stop()

    def codex_error(self, value: str) -> str:
        return localize_codex_error(value, str(self.config.value.get("app", {}).get("language", "en")))

    def _event(self, event: dict) -> None:
        with self.lock:
            method = event.get("method") or event.get("type") or "message"
            if event.get("id") is not None and str(event.get("method", "")).endswith("requestApproval"):
                self.rpc.mark_feature("approvals", "available", "Codex emitted an approval request")
                key = str(event["id"])
                self.approvals[key] = {"id": key, "rpcId": event["id"], "method": event.get("method"), "params": event.get("params", {}), "createdAt": int(time.time() * 1000)}
            params = event.get("params") or event.get("payload") or {}
            thread_id = str(params.get("threadId") or params.get("thread_id") or "")
            turn_data = params.get("turn") if isinstance(params.get("turn"), dict) else {}
            turn_id = str(params.get("turnId") or params.get("turn_id") or turn_data.get("id") or "")
            if turn_id:
                state = self.turns.setdefault(turn_id, {
                    "id": turn_id, "threadId": thread_id, "status": "starting",
                    "assistantText": "", "error": "", "startedAt": now_iso(),
                    "completedAt": None, "model": None, "reasoningEffort": None,
                })
                if thread_id:
                    state["threadId"] = thread_id
                    self.thread_turns[thread_id] = turn_id
                if method == "turn/started":
                    state["status"] = "inProgress"
                    state["startedAt"] = turn_data.get("startedAt") or state["startedAt"]
                elif method == "item/agentMessage/delta":
                    state["status"] = "inProgress"
                    state["assistantText"] += str(params.get("delta") or "")
                elif method == "item/completed":
                    item = params.get("item") if isinstance(params.get("item"), dict) else {}
                    if item.get("type") == "agentMessage" and item.get("text"):
                        state["assistantText"] = str(item["text"])
                elif method == "error":
                    error = params.get("error") if isinstance(params.get("error"), dict) else {}
                    state["error"] = self.codex_error(str(error.get("message") or params.get("message") or "Codex error"))
                    state["willRetry"] = bool(params.get("willRetry"))
                    if not state["willRetry"]:
                        state["status"] = "failed"
                elif method == "turn/completed":
                    status = str(turn_data.get("status") or params.get("status") or "completed")
                    state["status"] = "failed" if status == "failed" else "completed"
                    error = turn_data.get("error") if isinstance(turn_data.get("error"), dict) else {}
                    if error:
                        state["error"] = self.codex_error(str(error.get("message") or "Codex error"))
                    state["completedAt"] = turn_data.get("completedAt") or now_iso()
                self.turn_condition.notify_all()
            if method == "thread/settings/updated" and thread_id:
                settings = params.get("threadSettings") if isinstance(params.get("threadSettings"), dict) else {}
                if settings:
                    self.thread_settings[thread_id] = dict(settings)
                    current_turn_id = self.thread_turns.get(thread_id)
                    current = self.turns.get(current_turn_id or "")
                    if current:
                        current["model"] = settings.get("model")
                        current["reasoningEffort"] = settings.get("effort")
                        current["approvalPolicy"] = settings.get("approvalPolicy")
                        current["approvalsReviewer"] = settings.get("approvalsReviewer")
                        current["settingsConfirmed"] = True
            if event.get("method") == "thread/tokenUsage/updated":
                if thread_id:
                    self.usage[thread_id] = params.get("tokenUsage") or params.get("token_usage") or params
            self.event_seq += 1
            self.events.append({"seq": self.event_seq, "time": now_iso(), "source": "codex", "type": method, "threadId": thread_id, "turnId": turn_id, "payload": params})

    def event_list(self, after: int, thread_id: str | None = None) -> dict:
        events = [event for event in self.events if event["seq"] > after and (not thread_id or event.get("threadId") == thread_id)]
        return {"ok": True, "events": events, "latestSeq": self.event_seq}

    def capabilities(self) -> dict:
        mode = str(self.config.value["host"].get("compatibility_mode", "normal"))
        return {"ok": True, "apiVersion": 2, "codexReady": self.rpc.ready, "compatibility": {"mode": mode, "features": self.rpc.feature_snapshot()}, "speech": self.speech.capabilities(), "attachments": {"images": True, "maxImages": 4, "maxBytesEach": 6 * 1024 * 1024}, "overrides": {"perThread": True, "persistentSync": False}}

    def info(self) -> dict:
        host_name = os.environ.get("COMPUTERNAME") or (os.uname().nodename if hasattr(os, "uname") else "Codex Host")
        return {"ok": True, "host": {"name": host_name, "version": "1.0.0"}, "codex": {"ready": self.rpc.ready, "binary": self.config.value["host"]["codex_bin"], "error": self.rpc.error}, "defaults": {"cwd": self.config.value["host"]["default_cwd"]}, "capabilities": self.capabilities()}

    def projects_and_recent(self) -> dict:
        result = self.rpc.request_feature("threads", "thread/list", {"archived": False, "limit": 100, "sortKey": "updated_at", "sortDirection": "desc", "useStateDbOnly": False})
        threads = result.get("data") or result.get("threads") or []
        projects: dict[str, dict] = {}
        for thread in threads:
            cwd = thread.get("cwd") or self.config.value["host"]["default_cwd"]
            item = projects.setdefault(cwd, {"path": cwd, "name": Path(cwd).name or cwd, "threadCount": 0, "updatedAt": 0})
            item["threadCount"] += 1
            item["updatedAt"] = max(item["updatedAt"], int(thread.get("updatedAt") or thread.get("recencyAt") or 0))
        return {"ok": True, "computer": self.info()["host"]["name"], "projects": sorted(projects.values(), key=lambda x: x["updatedAt"], reverse=True), "recentThreads": [self.thread_summary(thread) for thread in threads[:10]]}

    def thread_summary(self, thread: dict) -> dict:
        return {"id": thread.get("id", ""), "name": thread.get("name") or thread.get("preview") or "Новый чат", "preview": thread.get("preview", ""), "cwd": thread.get("cwd", ""), "status": thread.get("status"), "createdAt": thread.get("createdAt", 0), "updatedAt": thread.get("updatedAt") or thread.get("recencyAt") or 0, "source": thread.get("source") or thread.get("sourceKind")}

    def list_threads(self, query: dict[str, list[str]]) -> dict:
        params = {"archived": False, "limit": min(int(query.get("limit", ["100"])[0]), 100), "sortKey": "updated_at", "sortDirection": "desc", "useStateDbOnly": False}
        if query.get("cursor"):
            params["cursor"] = query["cursor"][0]
        if query.get("cwd"):
            params["cwd"] = query["cwd"][0]
        result = self.rpc.request_feature("threads", "thread/list", params)
        return {"ok": True, **result, "data": [self.thread_summary(item) for item in result.get("data", [])]}

    def normalize_thread(self, thread: dict) -> dict:
        messages: list[dict] = []
        for turn in thread.get("turns", []) or []:
            for item in turn.get("items", []) or []:
                kind, title, value = "status", "Codex", ""
                media: list[dict] = []
                item_type = item.get("type", "")
                if item_type == "userMessage":
                    kind, title, value = "user", "Вы", text_from_content(item.get("content"))
                    for part in item.get("content", []) if isinstance(item.get("content"), list) else []:
                        if isinstance(part, dict) and part.get("type") in {"localImage", "image"}:
                            media_item = self.register_media(str(part.get("path") or part.get("localPath") or ""), "user")
                            if media_item:
                                media.append(media_item)
                elif item_type == "agentMessage":
                    kind, title, value = "assistant", "Codex", item.get("text", "")
                elif item_type == "reasoning":
                    kind, title, value = "status", "Размышление", text_from_content(item.get("summary") or item.get("content"))
                elif item_type == "fileChange":
                    kind, title, value = "command", "Изменены файлы", "\n".join(str(change.get("path") if isinstance(change, dict) else change) for change in item.get("changes", []))
                elif item_type in {"mcpToolCall", "webSearch", "commandExecution"}:
                    kind, title, value = "command", item.get("tool") or item.get("title") or "Инструмент", item.get("result") or item.get("query") or item.get("status") or ""
                elif item_type == "contextCompaction":
                    kind, title, value = "status", "Контекст сжат", "Codex сжал контекст диалога."
                elif item_type in {"imageView", "imageGeneration"}:
                    result = item.get("result") if isinstance(item.get("result"), dict) else {}
                    image_path = item.get("path") or item.get("savedPath") or result.get("savedPath") or result.get("path")
                    media_item = self.register_media(str(image_path or ""), "codex")
                    if media_item:
                        kind, title, value, media = "assistant", "Codex", str(item.get("revisedPrompt") or result.get("revisedPrompt") or ""), [media_item]
                if value or media:
                    messages.append({
                        "id": item.get("id", ""), "turnId": turn.get("id", ""), "kind": kind,
                        "title": title, "text": str(value)[:12000],
                        "createdAt": item.get("createdAt") or turn.get("createdAt") or "",
                        "status": turn.get("status") or "",
                        "model": turn.get("model") or turn.get("modelId") or "",
                        "reasoningEffort": turn.get("reasoningEffort") or turn.get("effort") or "",
                        "media": media,
                    })
        thread_id = thread.get("id", "")

        active_turn = self.turn_state_for_thread(thread_id)
        if active_turn and active_turn.get("assistantText"):
            persisted = any(message.get("turnId") == active_turn["id"] and message.get("kind") == "assistant" for message in messages)
            if not persisted:
                messages.append({"id": "live-" + active_turn["id"], "turnId": active_turn["id"], "kind": "assistant", "title": "Codex", "text": active_turn["assistantText"][:12000], "streaming": active_turn.get("status") == "inProgress", "createdAt": active_turn.get("startedAt", ""), "status": active_turn.get("status", ""), "model": active_turn.get("model", ""), "reasoningEffort": active_turn.get("reasoningEffort", "")})
        result = {"id": thread_id, "name": thread.get("name") or thread.get("preview") or "Новый чат", "cwd": thread.get("cwd", ""), "status": thread.get("status", {}), "updatedAt": thread.get("updatedAt") or thread.get("recencyAt") or 0, "messages": messages[-200:], "messageCount": len(messages), "hasOlderMessages": len(messages) > 200, "tokenUsage": self.usage.get(thread_id), "override": self.thread_overrides.get(thread_id, {"mode": "inherit"}), "threadSettings": self.thread_settings.get(thread_id), "activeTurn": active_turn}
        return result

    def register_media(self, value: str, source: str) -> dict | None:
        if not value:
            return None
        try:
            path = Path(value).expanduser().resolve(strict=True)
            stat = path.stat()
        except (OSError, RuntimeError):
            return None
        if not path.is_file() or stat.st_size <= 0 or stat.st_size > 24 * 1024 * 1024:
            return None
        mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        if mime not in {"image/jpeg", "image/png", "image/gif", "image/webp"}:
            return None
        identity = f"{path}|{stat.st_size}|{stat.st_mtime_ns}".encode("utf-8", "surrogatepass")
        media_id = hmac.new(self.config.client_token.encode("utf-8"), identity, hashlib.sha256).hexdigest()[:32]
        with self.lock:
            self.media[media_id] = {"path": path, "mime": mime, "bytes": stat.st_size, "source": source}
        return {"id": media_id, "mime": mime, "bytes": stat.st_size, "source": source, "thumbnailPath": f"/api/media/{media_id}?variant=thumbnail", "originalPath": f"/api/media/{media_id}?variant=original"}

    def media_data(self, media_id: str, variant: str) -> dict:
        with self.lock:
            record = self.media.get(media_id)
        if not record:
            raise KeyError("media not found; reload the chat and try again")
        source = Path(record["path"])
        try:
            current = source.stat()
        except OSError as error:
            raise KeyError("media source is no longer available") from error
        if current.st_size != record["bytes"]:
            raise KeyError("media source changed; reload the chat")
        if variant == "thumbnail":
            cache_dir = data_dir(self.config.root) / "media-cache"
            cache_dir.mkdir(exist_ok=True)
            cached = cache_dir / f"{media_id}.jpg"
            if not cached.is_file():
                from PIL import Image, ImageOps

                temporary = cached.with_suffix(".tmp")
                with Image.open(source) as image:
                    image = ImageOps.exif_transpose(image)
                    image.thumbnail((480, 480))
                    if image.mode != "RGB":
                        background = Image.new("RGB", image.size, "white")
                        if "A" in image.getbands():
                            background.paste(image, mask=image.getchannel("A"))
                        else:
                            background.paste(image)
                        image = background
                    image.save(temporary, "JPEG", quality=72, optimize=True)
                os.replace(temporary, cached)
            path, mime = cached, "image/jpeg"
        elif variant == "original":
            path, mime = source, record["mime"]
        else:
            raise ValueError("variant must be thumbnail or original")
        raw = path.read_bytes()
        os.utime(path, None)
        return {"ok": True, "id": media_id, "variant": variant, "mime": mime, "bytes": len(raw), "base64": base64.b64encode(raw).decode("ascii")}

    def turn_state_for_thread(self, thread_id: str) -> dict | None:
        turn_id = self.thread_turns.get(thread_id)
        if not turn_id:
            return None
        state = self.turns.get(turn_id)
        return dict(state) if state else None

    def turn_state(self, thread_id: str, turn_id: str) -> dict:
        state = self.turns.get(turn_id)
        if not state or state.get("threadId") != thread_id:
            raise KeyError("turn not found")
        return {"ok": True, "turn": dict(state)}

    def read_thread(self, thread_id: str) -> dict:
        if thread_id not in self.resumed_threads:
            self.rpc.request_feature("threads", "thread/resume", {"threadId": thread_id, "excludeTurns": True})
            self.resumed_threads.add(thread_id)
        result = self.rpc.request_feature("threads", "thread/read", {"threadId": thread_id, "includeTurns": True})
        return {"ok": True, "thread": self.normalize_thread(result.get("thread") or result)}

    def models(self) -> dict:
        result = self.rpc.request_feature("models", "model/list", {"includeHidden": True, "limit": 100})
        visible = [model for model in result.get("data", []) if not model.get("hidden")]
        return {"ok": True, **result, "data": visible}

    def create_thread(self, body: dict) -> dict:
        cwd = body.get("cwd")
        if not cwd:
            raise ValueError("project cwd is required")
        result = self.rpc.request_feature("threads", "thread/start", {"cwd": cwd})
        thread = result.get("thread") if isinstance(result.get("thread"), dict) else result
        if thread.get("id"):
            self.resumed_threads.add(str(thread["id"]))
        return {"ok": True, **result}

    def set_override(self, thread_id: str, body: dict) -> dict:
        mode = body.get("mode", "inherit")
        if mode not in {"inherit", "persistent", "next_turn"}:
            raise ValueError("override mode is invalid")
        if mode == "inherit":
            self.thread_overrides.pop(thread_id, None)
            return {"ok": True, "override": {"mode": "inherit"}}
        # A mobile client is a second control surface for the same branch.
        # Keep explicit preferences until it asks to inherit again.
        # Older IPA builds sent ``next_turn``. Treat it as persistent too so
        # a user does not lose branch settings merely by updating the Host.
        override = {"mode": "persistent" if mode in {"persistent", "next_turn"} else "next_turn"}
        for key in ("model", "reasoningEffort", "approvalPolicy", "approvalsReviewer"):
            if body.get(key):
                override[key] = body[key]
        self.thread_overrides[thread_id] = override
        return {"ok": True, "override": override}

    def _record_delivery(self, thread_id: str, request_id: str, state: str, detail: str = "") -> None:
        entry = {"time": now_iso(), "threadId": thread_id, "requestId": request_id, "state": state, "detail": detail[:500]}
        path = data_dir(self.config.root) / "logs" / "deliveries.jsonl"
        with self.lock:
            with path.open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(entry, ensure_ascii=False) + "\n")

    def _turn_is_visible(self, thread_id: str, text: str, turn_id: str) -> bool:
        """Confirm that Codex persisted the submitted input in this branch."""
        try:
            result = self.rpc.request_feature("threads", "thread/read", {"threadId": thread_id, "includeTurns": True}, timeout=12)
        except Exception:
            return False
        thread = result.get("thread") or result
        for turn in thread.get("turns", []) or []:
            if turn_id and str(turn.get("id") or "") == turn_id:
                return True
            for item in turn.get("items", []) or []:
                if item.get("type") == "userMessage" and text and text_from_content(item.get("content")) == text:
                    return True
        return False

    def _confirm_turn_delivery(self, thread_id: str, text: str, result: dict) -> dict:
        turn = result.get("turn") if isinstance(result.get("turn"), dict) else {}
        turn_id = str(turn.get("id") or result.get("turnId") or result.get("id") or "")
        deadline = time.monotonic() + 18.0
        while time.monotonic() < deadline:
            if self._turn_is_visible(thread_id, text, turn_id):
                return {"confirmed": True, "turnId": turn_id}
            time.sleep(0.4)
        return {"confirmed": False, "turnId": turn_id}

    def _remember_result(self, request_id: str, response: dict) -> None:
        self.idempotency[request_id] = response
        self.idempotency.move_to_end(request_id)
        while len(self.idempotency) > 256:
            self.idempotency.popitem(last=False)

    def _write_images(self, thread_id: str, images: list[str]) -> list[dict]:
        if len(images) > 4:
            raise ValueError("no more than 4 images can be attached to one message")
        decoded: list[bytes] = []
        for encoded in images:
            try:
                raw = base64.b64decode(encoded, validate=True)
            except (ValueError, binascii.Error) as error:
                raise ValueError("image is not valid base64") from error
            if not raw or len(raw) > 6 * 1024 * 1024:
                raise ValueError("each image must be between 1 byte and 6 MiB")
            decoded.append(raw)
        result: list[dict] = []
        directory = data_dir(self.config.root) / "attachments" / thread_id
        directory.mkdir(parents=True, exist_ok=True)
        for raw in decoded:
            file_path = directory / f"{uuid.uuid4().hex}.jpg"
            file_path.write_bytes(raw)
            result.append({"type": "localImage", "path": str(file_path), "detail": "auto"})
        return result

    def start_turn(self, thread_id: str, body: dict) -> dict:
        request_id = str(body.get("clientRequestId") or uuid.uuid4())
        cached = self.idempotency.get(request_id)
        if cached:
            return {**cached, "idempotentReplay": True}
        text = str(body.get("text") or "")
        images = body.get("imagesBase64") or ([] if not body.get("imageBase64") else [body["imageBase64"]])
        if not text.strip() and not images:
            raise ValueError("text or image is required")
        command = text.strip().lower()
        if command in {"/compact", "/compact now"}:
            response = {"ok": True, "command": "compact", **self.rpc.request_feature("turns", "thread/compact/start", {"threadId": thread_id})}
            self._remember_result(request_id, response)
            return response
        if command in {"/refresh", "/status"}:
            response = self.read_thread(thread_id)
            self._remember_result(request_id, response)
            return response
        input_items: list[dict] = []
        if text.strip():
            input_items.append({"type": "text", "text": text})
        input_items.extend(self._write_images(thread_id, images))
        override = self.thread_overrides.get(thread_id, {"mode": "inherit"})
        resume = {"threadId": thread_id, "excludeTurns": True}
        if body.get("cwd"):
            resume["cwd"] = body["cwd"]
        if override["mode"] in {"next_turn", "persistent"}:
            for key in ("model", "approvalPolicy", "approvalsReviewer"):
                if override.get(key):
                    resume[key] = override[key]
        if thread_id not in self.resumed_threads:
            self.rpc.request_feature("threads", "thread/resume", resume)
            self.resumed_threads.add(thread_id)
        params = {"threadId": thread_id, "input": input_items}
        if body.get("cwd"):
            params["cwd"] = body["cwd"]
        if override["mode"] in {"next_turn", "persistent"}:
            if override.get("model"):
                params["model"] = override["model"]
            if override.get("reasoningEffort"):
                params["effort"] = override["reasoningEffort"]
            if override.get("approvalPolicy"):
                params["approvalPolicy"] = override["approvalPolicy"]
            if override.get("approvalsReviewer"):
                params["approvalsReviewer"] = override["approvalsReviewer"]
        rpc_result = self.rpc.request_feature("turns", "turn/start", params)
        turn_data = rpc_result.get("turn") if isinstance(rpc_result.get("turn"), dict) else {}
        turn_id = str(turn_data.get("id") or rpc_result.get("turnId") or rpc_result.get("id") or "")
        if turn_id:
            with self.lock:
                state = self.turns.setdefault(turn_id, {
                    "id": turn_id, "threadId": thread_id, "status": "starting",
                    "assistantText": "", "error": "", "startedAt": now_iso(),
                    "completedAt": None, "model": None, "reasoningEffort": None,
                })
                state["threadId"] = thread_id
                state["model"] = override.get("model")
                state["reasoningEffort"] = override.get("reasoningEffort")
                state["approvalPolicy"] = override.get("approvalPolicy")
                state["approvalsReviewer"] = override.get("approvalsReviewer")
                effective = self.thread_settings.get(thread_id, {})
                if effective:
                    state["model"] = effective.get("model") or state["model"]
                    state["reasoningEffort"] = effective.get("effort") or state["reasoningEffort"]
                    state["approvalPolicy"] = effective.get("approvalPolicy") or state["approvalPolicy"]
                    state["approvalsReviewer"] = effective.get("approvalsReviewer") or state["approvalsReviewer"]
                state["settingsConfirmed"] = bool(effective)
                self.thread_turns[thread_id] = turn_id
        receipt = self._confirm_turn_delivery(thread_id, text, rpc_result)
        if not receipt["confirmed"]:
            response = {"ok": False, "error": "Codex не подтвердил появление сообщения в ветке. Текст не был удалён.", "delivery": "unconfirmed", "turnId": receipt["turnId"]}
            self._record_delivery(thread_id, request_id, "unconfirmed", receipt["turnId"])
            self._remember_result(request_id, response)
            return response
        if override["mode"] == "next_turn":
            self.thread_overrides.pop(thread_id, None)
        response = {"ok": True, "delivery": "started", "turnId": receipt["turnId"], "turnState": self.turn_state_for_thread(thread_id), **rpc_result}
        self._record_delivery(thread_id, request_id, "confirmed", receipt["turnId"])
        self._remember_result(request_id, response)
        return response

    def approvals_list(self, thread_id: str | None) -> dict:
        items = []
        for item in self.approvals.values():
            params = item["params"]
            if thread_id and params.get("threadId") != thread_id:
                continue
            items.append({"id": item["id"], "method": item["method"], "createdAt": item["createdAt"], "threadId": params.get("threadId", ""), "command": params.get("command", ""), "reason": params.get("reason", "")})
        return {"ok": True, "data": items}

    def approval_reply(self, approval_id: str, body: dict) -> dict:
        approval = self.approvals.pop(approval_id, None)
        if not approval:
            raise KeyError("approval not found")
        decision = body.get("decision") if body.get("decision") in {"accept", "acceptForSession", "decline", "cancel"} else "decline"
        self.rpc.respond(approval["rpcId"], {"decision": decision})
        self.rpc.mark_feature("approvals", "available", "approval response was sent")
        return {"ok": True}

    def transcribe(self, body: dict) -> dict:
        encoded = body.get("audioBase64")
        if not isinstance(encoded, str):
            raise ValueError("audioBase64 is required")
        raw = base64.b64decode(encoded, validate=True)
        if not raw or len(raw) > 20 * 1024 * 1024:
            raise ValueError("audio is invalid or too large")
        suffix = ".m4a" if body.get("format") == "m4a" else ".wav"
        temp = data_dir(self.config.root) / "tmp" / f"{uuid.uuid4().hex}{suffix}"
        try:
            temp.write_bytes(raw)
            return {"ok": True, **self.speech.transcribe(temp)}
        finally:
            temp.unlink(missing_ok=True)

    def cleanup_cache(self) -> dict:
        now = time.time()
        cache = self.config.value["cache"]
        tmp_cutoff = now - int(cache["tmp_hours"]) * 3600
        attachment_cutoff = now - int(cache["attachment_days"]) * 86400
        removed = 0
        for parent, cutoff in ((data_dir(self.config.root) / "tmp", tmp_cutoff), (data_dir(self.config.root) / "attachments", attachment_cutoff)):
            for file_path in parent.rglob("*"):
                if file_path.is_file() and file_path.stat().st_mtime < cutoff:
                    removed += file_path.stat().st_size
                    file_path.unlink(missing_ok=True)
        files = sorted((path for path in (data_dir(self.config.root) / "attachments").rglob("*") if path.is_file()), key=lambda p: p.stat().st_mtime)
        limit = int(cache["max_mebibytes"]) * 1024 * 1024
        total = sum(path.stat().st_size for path in files)
        for file_path in files:
            if total <= limit:
                break
            size = file_path.stat().st_size
            file_path.unlink(missing_ok=True)
            total -= size
            removed += size
        media_files = sorted((path for path in (data_dir(self.config.root) / "media-cache").rglob("*") if path.is_file()), key=lambda p: p.stat().st_mtime)
        media_limit = int(cache.get("media_mebibytes", 128)) * 1024 * 1024
        media_total = sum(path.stat().st_size for path in media_files)
        for file_path in media_files:
            if media_total <= media_limit:
                break
            size = file_path.stat().st_size
            file_path.unlink(missing_ok=True)
            media_total -= size
            removed += size
        return {"ok": True, "removedBytes": removed, "cacheBytes": total, "mediaCacheBytes": media_total}


class Handler(BaseHTTPRequestHandler):
    server: "HostHTTPServer"

    def log_message(self, fmt: str, *args: Any) -> None:
        return

    def _json(self, status: int, body: dict) -> None:
        raw = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.close_connection = True
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(raw)

    def _body(self) -> dict:
        length = int(self.headers.get("Content-Length", "0"))
        if length > MAX_BODY:
            raise ValueError("request body too large")
        raw = self.rfile.read(length) if length else b"{}"
        return json.loads(raw.decode("utf-8"))

    def _authorized(self) -> bool:
        return self.headers.get("Authorization") == f"Bearer {self.server.service.config.client_token}"

    def _route(self) -> None:
        parsed = urlparse(self.path)
        path, query = parsed.path, parse_qs(parsed.query)
        if self.command == "GET" and path == "/healthz":
            return self._json(200, {"ok": True, "name": "vibeslopik-host", "codexReady": self.server.service.rpc.ready})
        if not path.startswith("/api/"):
            return self._json(404, {"ok": False, "error": "not found"})
        if not self._authorized():
            return self._json(401, {"ok": False, "error": "unauthorized"})
        service = self.server.service
        if self.command == "GET" and path == "/api/info": return self._json(200, service.info())
        if self.command == "GET" and path == "/api/capabilities": return self._json(200, service.capabilities())
        if self.command == "GET" and path == "/api/home": return self._json(200, service.projects_and_recent())
        if self.command == "GET" and path == "/api/projects": return self._json(200, service.projects_and_recent())
        if self.command == "GET" and path == "/api/threads": return self._json(200, service.list_threads(query))
        if self.command == "GET" and path == "/api/models": return self._json(200, service.models())
        if self.command == "GET" and path == "/api/events": return self._json(200, service.event_list(int(query.get("after", ["0"])[0]), query.get("threadId", [None])[0]))
        if self.command == "GET" and path == "/api/approvals": return self._json(200, service.approvals_list(query.get("threadId", [None])[0]))
        if self.command == "POST" and path == "/api/admin/shutdown":
            self._json(200, {"ok": True, "stopping": True})
            threading.Thread(target=self.server.shutdown, daemon=True).start()
            return
        match = re.match(r"^/api/media/([a-f0-9]{32})$", path)
        if self.command == "GET" and match: return self._json(200, service.media_data(match.group(1), query.get("variant", ["thumbnail"])[0]))
        if self.command == "GET" and path == "/api/account/limits":
            return self._json(200, {"ok": True, **service.rpc.request_feature("rateLimits", "account/rateLimits/read", {})})
        match = re.match(r"^/api/threads/([^/]+)$", path)
        if self.command == "GET" and match: return self._json(200, service.read_thread(unquote(match.group(1))))
        match = re.match(r"^/api/threads/([^/]+)/turns/([^/]+)$", path)
        if self.command == "GET" and match: return self._json(200, service.turn_state(unquote(match.group(1)), unquote(match.group(2))))
        body = self._body() if self.command == "POST" else {}
        if self.command == "POST" and path == "/api/threads": return self._json(200, service.create_thread(body))
        match = re.match(r"^/api/threads/([^/]+)/overrides$", path)
        if self.command == "POST" and match: return self._json(200, service.set_override(unquote(match.group(1)), body))
        match = re.match(r"^/api/threads/([^/]+)/turns$", path)
        if self.command == "POST" and match: return self._json(200, service.start_turn(unquote(match.group(1)), body))
        match = re.match(r"^/api/approvals/([^/]+)$", path)
        if self.command == "POST" and match: return self._json(200, service.approval_reply(unquote(match.group(1)), body))
        if self.command == "POST" and path == "/api/speech/transcriptions": return self._json(200, service.transcribe(body))
        if self.command == "POST" and path == "/api/cache/clear": return self._json(200, service.cleanup_cache())
        return self._json(404, {"ok": False, "error": "not found"})

    def do_GET(self) -> None:
        try: self._route()
        except Exception as error: self._json(500, {"ok": False, "error": str(error)})

    def do_POST(self) -> None:
        try: self._route()
        except KeyError as error: self._json(404, {"ok": False, "error": str(error)})
        except ValueError as error: self._json(400, {"ok": False, "error": str(error)})
        except Exception as error: self._json(500, {"ok": False, "error": str(error)})


class HostHTTPServer(ThreadingHTTPServer):
    def __init__(self, address: tuple[str, int], service: HostService):
        self.service = service
        super().__init__(address, Handler)
