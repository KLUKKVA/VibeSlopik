from __future__ import annotations

import os
import copy
import secrets
import shutil
import tempfile
import time
import tomllib
import re
from dataclasses import dataclass, asdict
from pathlib import Path
from urllib.parse import urlsplit


DEFAULT_CONFIG = {
    "app": {"language": "en", "configured": False},
    "host": {"bind": "127.0.0.1", "port": 8787, "default_cwd": "", "codex_bin": "codex", "codex_args_json": "[\\\"app-server\\\"]", "compatibility_mode": "normal"},
    "relay": {"url": "", "host_id": "", "enabled": True},
    "speech": {"enabled": False, "backend": "faster-whisper", "profile": "recommended", "idle_unload_seconds": 300},
    "cache": {"max_mebibytes": 1024, "media_mebibytes": 128, "attachment_days": 30, "tmp_hours": 1},
    "logging": {"level": "info"},
}


def data_dir(root: Path) -> Path:
    return root / "data"


def config_path(root: Path) -> Path:
    return data_dir(root) / "config.toml"


def secrets_path(root: Path) -> Path:
    return data_dir(root) / "secret.env"


def _merge(base: dict, override: dict) -> dict:
    result = copy.deepcopy(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = _merge(result[key], value)
        else:
            result[key] = value
    return result


def _toml_value(value: object) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"') + '"'


def write_config(path: Path, value: dict) -> None:
    lines: list[str] = ["# VibeSlopik Host configuration. Tokens live in secret.env, not here.\n"]
    for section, entries in value.items():
        lines.append(f"[{section}]")
        for key, item in entries.items():
            lines.append(f"{key} = {_toml_value(item)}")
        lines.append("")
    _atomic_write(path, "\n".join(lines), 0o600)


def read_secrets(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    result: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" not in line or line.lstrip().startswith("#"):
            continue
        key, value = line.split("=", 1)
        result[key.strip()] = value.strip()
    return result


def write_secrets(path: Path, value: dict[str, str]) -> None:
    _atomic_write(path, "\n".join(f"{key}={item}" for key, item in sorted(value.items())) + "\n", 0o600)


def _atomic_write(path: Path, content: str, mode: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def validate_config(value: dict) -> list[str]:
    errors: list[str] = []
    if value.get("app", {}).get("language") not in {"en", "ru"}:
        errors.append("app.language must be en or ru")
    host = value.get("host", {})
    try:
        port = int(host.get("port", 0))
        if not 1024 <= port <= 65535:
            errors.append("host.port must be between 1024 and 65535")
    except (TypeError, ValueError):
        errors.append("host.port must be a number")
    if host.get("bind") not in {"127.0.0.1", "localhost"}:
        errors.append("host.bind must remain local; remote access goes through Relay")
    if host.get("compatibility_mode") not in {"normal", "compatible", "forced", "diagnostic"}:
        errors.append("unknown compatibility mode")
    if value.get("speech", {}).get("profile") not in {"economy", "recommended", "quality"}:
        errors.append("unknown speech profile")
    cache = value.get("cache", {})
    for key, minimum, maximum in (("max_mebibytes", 16, 102400), ("media_mebibytes", 8, 10240), ("attachment_days", 1, 3650), ("tmp_hours", 1, 168)):
        try:
            number = int(cache.get(key, 0))
            if not minimum <= number <= maximum:
                errors.append(f"cache.{key} must be between {minimum} and {maximum}")
        except (TypeError, ValueError):
            errors.append(f"cache.{key} must be a number")
    relay_url = str(value.get("relay", {}).get("url", ""))
    relay = value.get("relay", {})
    if relay_url:
        try:
            parsed = urlsplit(relay_url)
            if parsed.scheme not in {"http", "https"} or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
                errors.append("relay.url must be a plain http(s) server URL without credentials, query or fragment")
            _ = parsed.port
        except ValueError:
            errors.append("relay.url contains an invalid port or address")
    host_id = str(relay.get("host_id", ""))
    if relay_url and not re.fullmatch(r"[A-Za-z0-9._-]{1,128}", host_id):
        errors.append("relay.host_id must contain 1..128 letters, numbers, dots, dashes or underscores")
    return errors


@dataclass
class ConfigStore:
    root: Path
    value: dict
    secrets: dict[str, str]
    recovery_messages: list[str]

    @classmethod
    def load(cls, root: Path) -> "ConfigStore":
        root = root.resolve()
        data_dir(root).mkdir(parents=True, exist_ok=True)
        for name in ("models", "speech-pack", "attachments", "media-cache", "tmp", "logs"):
            (data_dir(root) / name).mkdir(exist_ok=True)
        path = config_path(root)
        recovery_messages: list[str] = []
        if path.exists():
            try:
                saved = tomllib.loads(path.read_text(encoding="utf-8"))
            except (OSError, UnicodeError, tomllib.TOMLDecodeError) as error:
                backup = path.with_name(f"config.toml.corrupt-{int(time.time())}")
                os.replace(path, backup)
                saved = {}
                recovery_messages.append(
                    f"Damaged configuration was preserved as {backup.name}; safe defaults were restored ({error})."
                )
        else:
            saved = {}
        value = _merge(DEFAULT_CONFIG, saved)
        store = cls(root=root, value=value, secrets=read_secrets(secrets_path(root)), recovery_messages=recovery_messages)
        changed = not path.exists() or bool(recovery_messages)
        configured_codex = str(store.value["host"].get("codex_bin", "codex"))
        discovered_codex = shutil.which(configured_codex)
        local_app_data = os.environ.get("LOCALAPPDATA", "")
        desktop_candidates = []
        if local_app_data:
            desktop_candidates = list((Path(local_app_data) / "OpenAI" / "Codex" / "bin").glob("*/codex.exe"))
        if configured_codex == "codex" and discovered_codex:
            store.value["host"]["codex_bin"] = discovered_codex
            changed = True
        elif configured_codex == "codex" and desktop_candidates:
            newest = max(desktop_candidates, key=lambda path: path.stat().st_mtime)
            store.value["host"]["codex_bin"] = str(newest)
            changed = True
        # One schema migration is retained because it removes a secret from TOML.
        legacy_secret = store.value.get("relay", {}).pop("host_secret", "")
        if legacy_secret and "RELAY_HOST_SECRET" not in store.secrets:
            store.secrets["RELAY_HOST_SECRET"] = legacy_secret
            changed = True
        if not store.value["host"]["default_cwd"]:
            store.value["host"]["default_cwd"] = str(root)
            changed = True
        if "CLIENT_TOKEN" not in store.secrets:
            store.secrets["CLIENT_TOKEN"] = secrets.token_urlsafe(32)
            changed = True
        errors = validate_config(store.value)
        if errors:
            raise ValueError("Invalid VibeSlopik configuration: " + "; ".join(errors))
        if changed:
            store.save()
        return store

    def save(self) -> None:
        errors = validate_config(self.value)
        if errors:
            raise ValueError("Invalid VibeSlopik configuration: " + "; ".join(errors))
        write_config(config_path(self.root), self.value)
        write_secrets(secrets_path(self.root), self.secrets)

    @property
    def client_token(self) -> str:
        return self.secrets["CLIENT_TOKEN"]

    def masked(self) -> dict:
        result = _merge({}, self.value)
        result["secrets"] = {key: (value[:4] + "..." if value else "") for key, value in self.secrets.items()}
        return result
