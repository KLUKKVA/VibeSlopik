from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import platform
import shutil
import subprocess
import sys
import threading
import time
import urllib.request
import zipfile
from pathlib import Path


PROFILES = {
    "economy": {"model": "base", "label": {"en": "Economy", "ru": "Экономный"}, "disk": "~150 MiB", "diskBytes": 150 * 1024**2, "ram": "~400 MiB", "speed": "fast"},
    "recommended": {"model": "small", "label": {"en": "Recommended", "ru": "Рекомендуемый"}, "disk": "~500 MiB", "diskBytes": 500 * 1024**2, "ram": "~900 MiB", "speed": "balanced"},
    "quality": {"model": "medium", "label": {"en": "Quality", "ru": "Качественный"}, "disk": "~1.5 GiB", "diskBytes": 1536 * 1024**2, "ram": "~2.1 GiB", "speed": "slow"},
}


def model_path(models_dir: Path, profile: str) -> Path:
    return models_dir / ("faster-whisper-" + PROFILES[profile]["model"])


def model_directory(models_dir: Path, profile: str) -> Path:
    path = model_path(models_dir, profile)
    return path if (path / "model.bin").is_file() else Path()


def worker_path(pack_dir: Path) -> Path | None:
    name = "VibeSlopik-Speech.exe" if os.name == "nt" else "VibeSlopik-Speech"
    direct = pack_dir / name
    nested = pack_dir / "VibeSlopik-Speech" / name
    if direct.is_file():
        return direct
    if nested.is_file():
        return nested
    return None


def speech_status(models_dir: Path, profile: str, pack_dir: Path | None = None) -> dict:
    path = model_path(models_dir, profile)
    size = sum(item.stat().st_size for item in path.rglob("*") if item.is_file()) if path.exists() else 0
    return {
        "backendInstalled": bool(pack_dir and worker_path(pack_dir)) or importlib.util.find_spec("faster_whisper") is not None,
        "worker": str(worker_path(pack_dir)) if pack_dir and worker_path(pack_dir) else "",
        "profile": profile,
        "modelReady": (path / "model.bin").is_file(),
        "modelPath": str(path),
        "bytes": size,
        "manifestReady": (path / "vibeslopik-manifest.json").is_file(),
    }


def install_backend(pack_dir: Path, progress=print, version: str = "1.0.0") -> None:
    if not getattr(sys, "frozen", False):
        progress("Installing Speech Pack dependencies with this Python interpreter...")
        subprocess.run([sys.executable, "-m", "pip", "install", "faster-whisper>=1.1,<2"], check=True)
        return
    system = {"Windows": "windows", "Darwin": "macos", "Linux": "linux"}.get(platform.system())
    arch = "arm64" if platform.machine().lower() in {"arm64", "aarch64"} else "x64"
    if not system:
        raise RuntimeError("Speech Pack is unavailable for this operating system")
    asset = f"vibeslopik-speech-{system}-{arch}.zip"
    base = f"https://github.com/KLUKKVA/VibeSlopik/releases/download/v{version}"
    pack_dir.parent.mkdir(parents=True, exist_ok=True)
    archive = pack_dir.parent / (asset + ".download")
    sums = pack_dir.parent / "SHA256SUMS.download"

    def fetch(url: str, path: Path) -> None:
        progress(f"Downloading {url}")
        with urllib.request.urlopen(url, timeout=60) as response, path.open("wb") as output:
            total = int(response.headers.get("Content-Length", "0"))
            received = 0
            while True:
                block = response.read(1024 * 1024)
                if not block:
                    break
                output.write(block)
                received += len(block)
                if total:
                    progress(f"{received * 100 // total}% ({received // 1048576}/{total // 1048576} MiB)")

    try:
        fetch(f"{base}/{asset}", archive)
        fetch(f"{base}/SHA256SUMS", sums)
        expected = ""
        for line in sums.read_text(encoding="utf-8").splitlines():
            parts = line.split()
            if len(parts) >= 2 and parts[-1].lstrip("*") == asset:
                expected = parts[0]
        if not expected or _hash_file(archive) != expected:
            raise RuntimeError("Speech Pack checksum mismatch")
        temporary = pack_dir.with_name(pack_dir.name + ".new")
        shutil.rmtree(temporary, ignore_errors=True)
        temporary.mkdir()
        with zipfile.ZipFile(archive) as bundle:
            for member in bundle.infolist():
                destination = (temporary / member.filename).resolve()
                if temporary.resolve() not in destination.parents and destination != temporary.resolve():
                    raise RuntimeError("unsafe path in Speech Pack archive")
            bundle.extractall(temporary)
        candidate = worker_path(temporary)
        if not candidate:
            raise RuntimeError("Speech Pack executable is missing")
        candidate.chmod(candidate.stat().st_mode | 0o700)
        check = subprocess.run([str(candidate), "--check"], capture_output=True, text=True, timeout=30)
        if check.returncode != 0:
            raise RuntimeError(check.stdout or check.stderr or "Speech Pack self-test failed")
        backup = pack_dir.with_name(pack_dir.name + ".previous")
        shutil.rmtree(backup, ignore_errors=True)
        if pack_dir.exists():
            os.replace(pack_dir, backup)
        os.replace(temporary, pack_dir)
        shutil.rmtree(backup, ignore_errors=True)
    finally:
        archive.unlink(missing_ok=True)
        sums.unlink(missing_ok=True)


def _hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_manifest(path: Path) -> None:
    files = {}
    for item in sorted(path.rglob("*")):
        if item.is_file() and item.name != "vibeslopik-manifest.json":
            files[item.relative_to(path).as_posix()] = {"size": item.stat().st_size, "sha256": _hash_file(item)}
    temporary = path / "vibeslopik-manifest.json.tmp"
    temporary.write_text(json.dumps({"version": 1, "files": files}, indent=2), encoding="utf-8")
    os.replace(temporary, path / "vibeslopik-manifest.json")


def verify_model(models_dir: Path, profile: str) -> tuple[bool, str]:
    path = model_path(models_dir, profile)
    manifest_path = path / "vibeslopik-manifest.json"
    if not manifest_path.is_file():
        return False, "checksum manifest is missing"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        for name, expected in manifest["files"].items():
            item = path / name
            if not item.is_file() or item.stat().st_size != expected["size"] or _hash_file(item) != expected["sha256"]:
                return False, f"checksum mismatch: {name}"
    except (OSError, KeyError, ValueError, TypeError) as error:
        return False, str(error)
    return True, "OK"


def download_model(models_dir: Path, profile: str, progress=print) -> Path:
    if profile not in PROFILES:
        raise ValueError("unknown speech profile")
    if importlib.util.find_spec("huggingface_hub") is None:
        raise RuntimeError("Speech Pack backend is not installed")
    from huggingface_hub import snapshot_download

    models_dir.mkdir(parents=True, exist_ok=True)
    required = int(PROFILES[profile]["diskBytes"] * 1.35)
    free = shutil.disk_usage(models_dir).free
    if free < required:
        raise RuntimeError(f"not enough disk space: need about {required // 1048576} MiB, available {free // 1048576} MiB")
    target = model_path(models_dir, profile)
    temporary = target.with_name(target.name + ".new")
    backup = target.with_name(target.name + ".previous")
    cache = models_dir / ".download-cache"
    shutil.rmtree(temporary, ignore_errors=True)
    shutil.rmtree(cache, ignore_errors=True)
    temporary.mkdir(parents=True)
    model = PROFILES[profile]["model"]
    progress(f"Downloading Systran/faster-whisper-{model} to temporary storage")
    try:
        snapshot_download(repo_id=f"Systran/faster-whisper-{model}", local_dir=str(temporary), cache_dir=str(cache))
        if not (temporary / "model.bin").is_file():
            raise RuntimeError("download completed but model.bin is missing")
        progress("Creating and verifying SHA-256 manifest...")
        write_manifest(temporary)
        manifest = json.loads((temporary / "vibeslopik-manifest.json").read_text(encoding="utf-8"))
        for name, expected in manifest["files"].items():
            item = temporary / name
            if item.stat().st_size != expected["size"] or _hash_file(item) != expected["sha256"]:
                raise RuntimeError(f"checksum mismatch: {name}")
        shutil.rmtree(backup, ignore_errors=True)
        if target.exists():
            os.replace(target, backup)
        try:
            os.replace(temporary, target)
        except Exception:
            if backup.exists() and not target.exists():
                os.replace(backup, target)
            raise
        shutil.rmtree(backup, ignore_errors=True)
    finally:
        shutil.rmtree(temporary, ignore_errors=True)
        shutil.rmtree(cache, ignore_errors=True)
    valid, detail = verify_model(models_dir, profile)
    if not valid:
        raise RuntimeError(detail)
    return target


def remove_speech_pack(models_dir: Path, pack_dir: Path | None = None) -> None:
    for profile in PROFILES:
        shutil.rmtree(model_path(models_dir, profile), ignore_errors=True)
    if pack_dir:
        shutil.rmtree(pack_dir, ignore_errors=True)


class SpeechService:
    def __init__(self, models_dir: Path, enabled: bool, profile: str, idle_unload_seconds: int, pack_dir: Path | None = None):
        self.models_dir, self.enabled, self.profile, self.idle = models_dir, enabled, profile, idle_unload_seconds
        self.pack_dir = pack_dir or models_dir.parent / "speech-pack"
        self.model = None
        self.loaded_at = 0.0
        self.lock = threading.Lock()

    def capabilities(self) -> dict:
        status = speech_status(self.models_dir, self.profile, self.pack_dir)
        return {
            "enabled": self.enabled and status["backendInstalled"] and status["modelReady"],
            "configured": self.enabled,
            "backend": "faster-whisper",
            "installed": status["backendInstalled"],
            "modelReady": status["modelReady"],
            "profiles": PROFILES,
            "profile": self.profile,
        }

    def transcribe(self, audio_path: Path) -> dict:
        if not self.enabled:
            raise RuntimeError("speech_disabled")
        worker = worker_path(self.pack_dir)
        if worker:
            local_model = model_directory(self.models_dir, self.profile)
            if not local_model:
                raise RuntimeError("speech_model_missing")
            completed = subprocess.run([str(worker), "--audio", str(audio_path), "--model", str(local_model)], capture_output=True, text=True, encoding="utf-8", timeout=1800)
            try:
                result = json.loads(completed.stdout.strip() or "{}")
            except json.JSONDecodeError as error:
                raise RuntimeError(completed.stderr.strip() or "Speech Pack returned invalid data") from error
            if completed.returncode != 0 or not result.get("ok"):
                raise RuntimeError(str(result.get("error") or completed.stderr or "Speech Pack failed"))
            return {key: result.get(key) for key in ("text", "language", "languageProbability")}
        if importlib.util.find_spec("faster_whisper") is None:
            raise RuntimeError("speech_backend_missing")
        from faster_whisper import WhisperModel

        with self.lock:
            if self.model is None:
                local_model = model_directory(self.models_dir, self.profile)
                if not local_model:
                    raise RuntimeError("speech_model_missing")
                self.model = WhisperModel(str(local_model), device="cpu", compute_type="int8")
            self.loaded_at = time.time()
            segments, info = self.model.transcribe(str(audio_path), vad_filter=True, language=None, beam_size=5)
            text = "".join(segment.text for segment in segments).strip()
            return {"text": text, "language": getattr(info, "language", None), "languageProbability": getattr(info, "language_probability", None)}

    def maybe_unload(self) -> None:
        with self.lock:
            if self.model is not None and time.time() - self.loaded_at > self.idle:
                self.model = None
