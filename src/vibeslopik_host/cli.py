from __future__ import annotations

import argparse
import getpass
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

from .config import ConfigStore, data_dir, validate_config
from . import autostart
from .host import HostHTTPServer, HostService
from .relay import RelayAgent
from .speech import PROFILES, SpeechService, download_model, install_backend, remove_speech_pack, speech_status, verify_model


TEXT = {
    "title": {"en": "VibeSlopik Host 1.0.0", "ru": "VibeSlopik Host 1.0.0"},
    "menu": {"en": "1. Start Host\n2. Stop Host\n3. Status\n4. Initial setup\n5. Diagnostics\n6. Speech Pack\n7. Settings summary\n8. Clear cache\n9. Change language\n10. Autostart\n11. View logs\n0. Exit", "ru": "1. Запустить Host\n2. Остановить Host\n3. Состояние\n4. Первичная настройка\n5. Диагностика\n6. Распознавание речи\n7. Сводка настроек\n8. Очистить кэш\n9. Сменить язык\n10. Автозапуск\n11. Посмотреть логи\n0. Выход"},
    "choice": {"en": "Choose", "ru": "Выберите пункт"},
    "invalid": {"en": "Invalid value. Nothing was changed.", "ru": "Некорректное значение. Настройки не изменены."},
    "press": {"en": "Press Enter to continue...", "ru": "Нажмите Enter, чтобы продолжить..."},
    "setup": {"en": "Initial setup", "ru": "Первичная настройка"},
    "saved": {"en": "Settings saved atomically.", "ru": "Настройки сохранены атомарно."},
    "stopped": {"en": "Host stopped.", "ru": "Host остановлен."},
}


def tr(store: ConfigStore, key: str) -> str:
    language = store.value.get("app", {}).get("language", "en")
    return TEXT[key].get(language, TEXT[key]["en"])


def localized(store: ConfigStore, english: str, russian: str) -> str:
    return russian if store.value.get("app", {}).get("language") == "ru" else english


def say(store: ConfigStore, english: str, russian: str) -> None:
    print(localized(store, english, russian))


def root_from_args(args: argparse.Namespace) -> Path:
    if args.root:
        return Path(args.root).expanduser().resolve()
    configured = os.environ.get("VIBESLOPIK_HOME")
    return Path(configured).expanduser().resolve() if configured else Path.cwd().resolve()


def ask(label: str, default: str = "") -> str:
    suffix = f" [{default}]" if default else ""
    value = input(f"{label}{suffix}: ").strip()
    return value or default


def ask_yes_no(label: str, default: bool = False) -> bool:
    marker = "Y/n" if default else "y/N"
    while True:
        value = input(f"{label} [{marker}]: ").strip().lower()
        if not value:
            return default
        if value in {"y", "yes", "д", "да"}:
            return True
        if value in {"n", "no", "н", "нет"}:
            return False
        print("Enter yes/no or да/нет.")


def ask_local(store: ConfigStore, english: str, russian: str, default: str = "") -> str:
    return ask(localized(store, english, russian), default)


def ask_secret_local(store: ConfigStore, english: str, russian: str, current: str = "") -> str:
    suffix = localized(store, " [saved; Enter keeps it]", " [сохранён; Enter оставит его]") if current else ""
    value = getpass.getpass(f"{localized(store, english, russian)}{suffix}: ").strip()
    return value or current


def ask_yes_no_local(store: ConfigStore, english: str, russian: str, default: bool = False) -> bool:
    marker = "Y/n" if default else "y/N"
    while True:
        value = input(f"{localized(store, english, russian)} [{marker}]: ").strip().lower()
        if not value:
            return default
        if value in {"y", "yes", "д", "да"}:
            return True
        if value in {"n", "no", "н", "нет"}:
            return False
        say(store, "Enter yes or no.", "Введите да или нет.")


def verify_codex_binary(binary: str) -> tuple[bool, str]:
    try:
        result = subprocess.run([binary, "--version"], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=15)
    except (OSError, subprocess.SubprocessError) as error:
        return False, str(error)
    detail = (result.stdout or result.stderr).strip()
    return result.returncode == 0, detail or f"exit code {result.returncode}"


def choose_language(store: ConfigStore) -> None:
    while True:
        value = ask("Language / Язык (en/ru)", store.value.get("app", {}).get("language", "en")).lower()
        if value in {"en", "ru"}:
            store.value["app"]["language"] = value
            store.save()
            return
        print("Use en or ru / Введите en или ru")


def setup(store: ConfigStore, non_interactive: bool = False) -> int:
    if non_interactive:
        errors = validate_config(store.value)
        if errors:
            print(json.dumps({"ok": False, "errors": errors}, ensure_ascii=False))
            return 2
        store.save()
        print(json.dumps({"ok": True, "config": store.masked()}, ensure_ascii=False, indent=2))
        return 0

    if not store.value["app"].get("configured"):
        choose_language(store)
    language = store.value["app"]["language"]
    print(f"\n{tr(store, 'setup')}")
    host = store.value["host"]
    current_codex = str(host.get("codex_bin", "codex"))
    discovered = shutil.which(current_codex)
    if not discovered and Path(current_codex).is_file():
        discovered = str(Path(current_codex).resolve())
    label = "Path to Codex" if language == "en" else "Путь к Codex"
    codex = ask(label, discovered or current_codex)
    resolved_codex = shutil.which(codex) or (str(Path(codex).resolve()) if Path(codex).is_file() else "")
    if not resolved_codex:
        say(store, "Codex was not found. Install Codex or enter a valid path.", "Codex не найден. Установите Codex или укажите правильный путь.")
        return 2
    codex_ok, codex_detail = verify_codex_binary(resolved_codex)
    if not codex_ok:
        print(localized(store, f"Codex cannot be launched: {codex_detail}", f"Codex не запускается: {codex_detail}"))
        say(store, "Install Codex CLI or enter another executable path. The WindowsApps alias may be inaccessible.", "Установите Codex CLI или укажите другой исполняемый файл. Псевдоним WindowsApps может быть недоступен.")
        return 2
    print(f"Codex: {codex_detail}")
    host["codex_bin"] = resolved_codex
    label = "Projects directory" if language == "en" else "Папка проектов"
    cwd = Path(ask(label, str(host["default_cwd"]))).expanduser().resolve()
    if not cwd.is_dir():
        say(store, "Directory does not exist.", "Папка не существует.")
        return 2
    host["default_cwd"] = str(cwd)

    relay = store.value["relay"]
    label = "VPS Relay URL, for example http://203.0.113.10:8788" if language == "en" else "URL VPS Relay, например http://203.0.113.10:8788"
    relay_url = ask(label, str(relay.get("url", ""))).rstrip("/")
    if relay_url and not relay_url.startswith(("http://", "https://")):
        print(tr(store, "invalid"))
        return 2
    relay["url"] = relay_url
    if relay_url:
        relay["host_id"] = ask_local(store, "Host ID", "ID Host", str(relay.get("host_id") or uuid.uuid4().hex))
        secret = ask_secret_local(store, "Host secret", "Секрет Host", store.secrets.get("RELAY_HOST_SECRET", ""))
        if not secret or len(secret) > 512:
            say(store, "Host secret is required and must be at most 512 characters.", "Требуется секрет Host не длиннее 512 символов.")
            return 2
        store.secrets["RELAY_HOST_SECRET"] = secret
        admin = ask_secret_local(store, "Relay admin key", "Админ-ключ Relay", store.secrets.get("RELAY_ADMIN_KEY", ""))
        if len(admin) > 512:
            say(store, "Relay admin key must be at most 512 characters.", "Админ-ключ Relay не должен превышать 512 символов.")
            return 2
        if admin:
            store.secrets["RELAY_ADMIN_KEY"] = admin

    say(
        store,
        "Codex modes: normal stops on an incompatible protocol; compatible keeps supported features; forced skips startup probes; diagnostic only reports capabilities.",
        "Режимы Codex: normal останавливается при несовместимом протоколе; compatible сохраняет доступные функции; forced пропускает стартовые проверки; diagnostic только показывает возможности.",
    )
    mode = ask_local(store, "Codex mode: normal/compatible/forced/diagnostic", "Режим Codex: normal/compatible/forced/diagnostic", str(host.get("compatibility_mode", "normal"))).lower()
    if mode not in {"normal", "compatible", "forced", "diagnostic"}:
        print(tr(store, "invalid"))
        return 2
    host["compatibility_mode"] = mode
    errors = validate_config(store.value)
    if errors:
        print(localized(store, "Configuration error:\n- ", "Ошибка конфигурации:\n- ") + "\n- ".join(errors))
        return 2
    store.value["app"]["configured"] = True
    store.save()
    print(tr(store, "saved"))
    return 0


def _local_request(store: ConfigStore, path: str, method: str = "GET", timeout: float = 3.0) -> dict:
    host = store.value["host"]
    request = urllib.request.Request(
        f"http://127.0.0.1:{int(host['port'])}{path}",
        method=method,
        headers={"Authorization": f"Bearer {store.client_token}", "Accept": "application/json"},
    )
    if method == "POST":
        request.data = b"{}"
        request.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read(65536).decode("utf-8"))


def host_status(store: ConfigStore, quiet: bool = False) -> bool:
    try:
        response = _local_request(store, "/healthz")
        running = bool(response.get("ok"))
        detail = "Codex ready" if response.get("codexReady") else "Host runs; Codex is not ready"
    except (OSError, ValueError, urllib.error.URLError, json.JSONDecodeError):
        running, detail = False, "stopped"
    if not quiet:
        language = store.value["app"].get("language", "en")
        if language == "ru":
            detail = "Codex готов" if running and detail == "Codex ready" else ("Host запущен; Codex не готов" if running else "остановлен")
        print(f"Host: {detail}")
    return running


def _run_command(store: ConfigStore) -> list[str]:
    if getattr(sys, "frozen", False):
        return [str(Path(sys.executable).resolve()), "--root", str(store.root), "run"]
    return [str(Path(sys.executable).resolve()), "-m", "vibeslopik_host", "--root", str(store.root), "run"]


def start_background(store: ConfigStore) -> int:
    if host_status(store, quiet=True):
        say(store, "Host is already running.", "Host уже запущен.")
        return 0
    errors = validate_config(store.value)
    if errors:
        print(localized(store, "Configuration error:\n- ", "Ошибка конфигурации:\n- ") + "\n- ".join(errors))
        return 2
    log_dir = data_dir(store.root) / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    stdout = open(log_dir / "host.log", "a", encoding="utf-8", buffering=1)
    stderr = open(log_dir / "host-error.log", "a", encoding="utf-8", buffering=1)
    child_environment = os.environ.copy()
    child_environment["VIBESLOPIK_BACKGROUND"] = "1"
    options: dict[str, object] = {"stdin": subprocess.DEVNULL, "stdout": stdout, "stderr": stderr, "cwd": str(store.root), "env": child_environment}
    if os.name == "nt":
        options["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS
    else:
        options["start_new_session"] = True
    try:
        process = subprocess.Popen(_run_command(store), **options)
    except OSError as error:
        stdout.close(); stderr.close()
        print(localized(store, f"Host could not start: {error}", f"Host не запустился: {error}"))
        return 3
    finally:
        stdout.close(); stderr.close()
    for _ in range(60):
        if host_status(store, quiet=True):
            print(localized(store, f"Host started (PID {process.pid}).", f"Host запущен (PID {process.pid})."))
            relay = store.value["relay"]
            if relay.get("url") and relay.get("host_id"):
                print(f"iPhone URL: {str(relay['url']).rstrip('/')}/v1/client/{relay['host_id']}")
            print(f"iPhone token: {store.client_token}")
            return 0
        if process.poll() is not None:
            print(localized(store, f"Host exited with code {process.returncode}. View logs.", f"Host завершился с кодом {process.returncode}. Посмотрите логи."))
            return 3
        time.sleep(0.25)
    say(store, "Host startup timed out. View logs.", "Истекло время запуска Host. Посмотрите логи.")
    return 3


def stop_background(store: ConfigStore) -> int:
    if not host_status(store, quiet=True):
        say(store, "Host is already stopped.", "Host уже остановлен.")
        return 0
    try:
        _local_request(store, "/api/admin/shutdown", method="POST", timeout=5)
    except (OSError, ValueError, urllib.error.URLError, json.JSONDecodeError) as error:
        print(localized(store, f"Host did not accept shutdown: {error}", f"Host не принял остановку: {error}"))
        return 3
    for _ in range(40):
        if not host_status(store, quiet=True):
            print(tr(store, "stopped"))
            return 0
        time.sleep(0.25)
    say(store, "Host is still stopping; check status shortly.", "Host ещё останавливается; проверьте состояние позже.")
    return 1


def run(store: ConfigStore) -> int:
    errors = validate_config(store.value)
    if errors:
        print(localized(store, "Configuration error:\n- ", "Ошибка конфигурации:\n- ") + "\n- ".join(errors))
        return 2
    if not store.value["app"].get("configured"):
        result = setup(store)
        if result:
            return result
    service = HostService(store)
    try:
        service.start()
    except Exception as error:
        print(localized(store, f"Codex could not start: {error}", f"Codex не запустился: {error}"))
        say(store, "Run diagnostics.", "Запустите диагностику.")
        return 3
    host = store.value["host"]
    try:
        server = HostHTTPServer((host["bind"], int(host["port"])), service)
    except OSError as error:
        service.stop()
        print(localized(store, f"Local port {host['port']} is unavailable: {error}", f"Локальный порт {host['port']} недоступен: {error}"))
        return 4
    relay = RelayAgent(store, int(host["port"]))
    relay.start()
    print(f"\n{tr(store, 'title')}")
    print(f"Local URL: http://{host['bind']}:{host['port']}")
    relay_config = store.value["relay"]
    if relay_config.get("url") and relay_config.get("host_id"):
        print(f"iPhone URL: {relay_config['url'].rstrip('/')}/v1/client/{relay_config['host_id']}")
    if os.environ.get("VIBESLOPIK_BACKGROUND") != "1":
        print(f"iPhone token: {store.client_token}")
    say(store, "Press Ctrl+C to stop.", "Для остановки нажмите Ctrl+C.")

    stopping = threading.Event()

    def shutdown(*_args: object) -> None:
        if stopping.is_set():
            return
        stopping.set()
        relay.stop()
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGINT, shutdown)
    if hasattr(signal, "SIGTERM"):
        signal.signal(signal.SIGTERM, shutdown)
    try:
        server.serve_forever(poll_interval=0.5)
    finally:
        relay.stop()
        relay.join(timeout=5)
        service.stop()
        server.server_close()
    print(tr(store, "stopped"))
    return 0


def diagnostics(store: ConfigStore) -> int:
    report: list[tuple[str, bool, str]] = []
    errors = validate_config(store.value)
    report.append((localized(store, "Configuration", "Конфигурация"), not errors, "; ".join(errors) if errors else "OK"))
    codex = str(store.value["host"]["codex_bin"])
    codex_path = shutil.which(codex) or (codex if Path(codex).is_file() else "")
    detail = codex_path or localized(store, "not found", "не найден")
    if codex_path:
        try:
            result = subprocess.run([codex_path, "--version"], capture_output=True, text=True, timeout=10)
            detail = (result.stdout or result.stderr).strip() or detail
        except (OSError, subprocess.SubprocessError) as error:
            detail = str(error)
    report.append(("Codex", bool(codex_path), detail))
    port = int(store.value["host"]["port"])
    probe = socket.socket()
    try:
        probe.bind(("127.0.0.1", port))
        port_ok, port_detail = True, localized(store, "available", "свободен")
    except OSError as error:
        port_ok, port_detail = False, str(error)
    finally:
        probe.close()
    report.append((localized(store, "Local port", "Локальный порт"), port_ok, port_detail))
    relay_url = str(store.value["relay"].get("url", ""))
    if relay_url:
        try:
            with urllib.request.urlopen(relay_url.rstrip("/") + "/healthz", timeout=8) as response:
                relay_ok, relay_detail = response.status == 200, response.read(2048).decode("utf-8", "replace")
        except (OSError, urllib.error.URLError) as error:
            relay_ok, relay_detail = False, str(error)
        report.append(("VPS Relay", relay_ok, relay_detail))
    speech = store.value["speech"]
    status = speech_status(data_dir(store.root) / "models", str(speech["profile"]), data_dir(store.root) / "speech-pack")
    speech_ok = not speech["enabled"] or (status["backendInstalled"] and status["modelReady"])
    report.append((localized(store, "Speech Pack", "Распознавание речи"), speech_ok, json.dumps(status, ensure_ascii=False)))
    for name, ok, detail in report:
        print(f"[{'OK' if ok else 'FAIL'}] {name}: {detail}")
    return 0 if all(item[1] for item in report) else 1


def speech_menu(store: ConfigStore) -> int:
    models = data_dir(store.root) / "models"
    while True:
        speech = store.value["speech"]
        status = speech_status(models, str(speech["profile"]), data_dir(store.root) / "speech-pack")
        print("\n" + localized(store, "Speech Pack", "Распознавание речи"))
        if store.value["app"].get("language") == "ru":
            print(f"Включено: {speech['enabled']} | Профиль: {speech['profile']} | Компонент: {status['backendInstalled']} | Модель: {status['modelReady']} | Диск: {status['bytes'] // (1024 * 1024)} МБ")
            print("1. Установить или восстановить\n2. Включить или выключить\n3. Сменить модель\n4. Проверить контрольные суммы\n5. Проверить аудиозапись\n6. Удалить Speech Pack\n0. Назад")
        else:
            print(f"Enabled: {speech['enabled']} | Profile: {speech['profile']} | Backend: {status['backendInstalled']} | Model: {status['modelReady']} | Disk: {status['bytes'] // (1024 * 1024)} MiB")
            print("1. Install or repair\n2. Enable or disable\n3. Change model\n4. Verify checksums\n5. Test an audio recording\n6. Remove Speech Pack\n0. Back")
        choice = input("> ").strip()
        try:
            if choice == "1":
                profile = str(speech["profile"])
                info = PROFILES[profile]
                label = info["label"].get(store.value["app"].get("language", "en"), info["label"]["en"])
                speed = {"fast": ("fast", "быстро"), "balanced": ("balanced", "сбалансированно"), "slow": ("slow", "медленно")}[str(info["speed"])]
                print(f"{label} ({profile}): {info['disk']}, RAM {info['ram']}, {localized(store, *speed)}")
                if ask_yes_no_local(store, "Download and install this Speech Pack", "Скачать и установить этот Speech Pack", False):
                    if not status["backendInstalled"]:
                        install_backend(data_dir(store.root) / "speech-pack")
                    download_model(models, profile)
                    speech["enabled"] = True
                    store.save()
                    say(store, "Speech Pack is ready.", "Распознавание речи готово.")
            elif choice == "2":
                if not speech["enabled"] and not (status["backendInstalled"] and status["modelReady"]):
                    say(store, "Install the Speech Pack first.", "Сначала установите Speech Pack.")
                else:
                    speech["enabled"] = not speech["enabled"]
                    store.save()
            elif choice == "3":
                for key, value in PROFILES.items():
                    label = value["label"].get(store.value["app"].get("language", "en"), value["label"]["en"])
                    print(f"{label} ({key}): {value['disk']}, RAM {value['ram']}, {value['speed']}")
                profile = ask_local(store, "Profile", "Профиль", str(speech["profile"]))
                if profile not in PROFILES:
                    print(tr(store, "invalid"))
                else:
                    speech["profile"] = profile
                    speech["enabled"] = False
                    store.save()
                    say(store, "Install the selected model, then enable it.", "Установите выбранную модель, затем включите её.")
            elif choice == "4":
                ok, detail = verify_model(models, str(speech["profile"]))
                print(f"[{'OK' if ok else 'FAIL'}] {detail}")
            elif choice == "5":
                if not (status["backendInstalled"] and status["modelReady"]):
                    say(store, "Install or repair the Speech Pack first.", "Сначала установите или восстановите Speech Pack.")
                    continue
                audio = Path(ask_local(store, "Audio file (WAV, M4A, MP3)", "Аудиофайл (WAV, M4A, MP3)")).expanduser().resolve()
                if not audio.is_file():
                    say(store, "Audio file does not exist.", "Аудиофайл не существует.")
                    continue
                if audio.stat().st_size > 100 * 1024 * 1024:
                    say(store, "Audio file is larger than 100 MiB.", "Аудиофайл больше 100 МБ.")
                    continue
                say(store, "Transcribing; the first run may take longer.", "Распознаю; первый запуск может занять больше времени.")
                tester = SpeechService(models, True, str(speech["profile"]), int(speech["idle_unload_seconds"]), data_dir(store.root) / "speech-pack")
                result = tester.transcribe(audio)
                print(localized(store, "Language", "Язык") + f": {result.get('language') or '?'}")
                print(localized(store, "Text:\n", "Текст:\n") + str(result.get("text") or localized(store, "(empty)", "(пусто)")))
            elif choice == "6" and ask_yes_no_local(store, "Remove the Speech Pack and all downloaded speech models", "Удалить Speech Pack и все скачанные модели", False):
                speech["enabled"] = False
                store.save()
                remove_speech_pack(models, data_dir(store.root) / "speech-pack")
                say(store, "Speech Pack and models removed.", "Speech Pack и модели удалены.")
            elif choice == "0":
                return 0
        except (OSError, RuntimeError, subprocess.SubprocessError) as error:
            print(localized(store, f"Speech Pack error: {error}", f"Ошибка Speech Pack: {error}"))
            say(store, "Nothing else in Host was stopped. Retry or run diagnostics.", "Остальные функции Host не остановлены. Повторите попытку или запустите диагностику.")


def show_logs(store: ConfigStore, lines: int = 100) -> int:
    log_dir = data_dir(store.root) / "logs"
    files = sorted((path for path in log_dir.glob("*.log") if path.is_file()), key=lambda path: path.stat().st_mtime, reverse=True)
    if not files:
        say(store, "There are no log files yet.", "Файлов журналов пока нет.")
        return 0
    for path in files:
        print(f"\n--- {path.name} ---")
        try:
            content = path.read_text(encoding="utf-8", errors="replace").splitlines()
            print("\n".join(content[-lines:]) or localized(store, "(empty)", "(пусто)"))
        except OSError as error:
            print(localized(store, f"Could not read log: {error}", f"Не удалось прочитать журнал: {error}"))
    return 0


def menu(store: ConfigStore) -> int:
    if not store.value["app"].get("configured"):
        result = setup(store)
        if result:
            return result
    while True:
        print(f"\n{tr(store, 'title')}\n{tr(store, 'menu')}")
        choice = input(tr(store, "choice") + ": ").strip()
        if choice == "1":
            start_background(store)
        elif choice == "2":
            stop_background(store)
        elif choice == "3":
            host_status(store)
        elif choice == "4":
            setup(store)
        elif choice == "5":
            diagnostics(store)
        elif choice == "6":
            speech_menu(store)
        elif choice == "7":
            print(json.dumps(store.masked(), ensure_ascii=False, indent=2))
        elif choice == "8":
            print(json.dumps(HostService(store).cleanup_cache(), ensure_ascii=False, indent=2))
        elif choice == "9":
            choose_language(store)
        elif choice == "10":
            current = autostart.status()
            print(json.dumps(current, ensure_ascii=False, indent=2))
            enable = ask_yes_no_local(store, "Enable autostart", "Включить автозапуск", current["enabled"])
            try:
                result = autostart.install(store.root) if enable else autostart.remove()
                print(json.dumps(result, ensure_ascii=False, indent=2))
            except (OSError, subprocess.SubprocessError) as error:
                print(localized(store, f"Autostart error: {error}", f"Ошибка автозапуска: {error}"))
        elif choice == "11":
            show_logs(store)
        elif choice == "0":
            return 0
        else:
            print(tr(store, "invalid"))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="vibeslopik-host")
    parser.add_argument("--root", help="Host data directory / Папка данных Host")
    sub = parser.add_subparsers(dest="command")
    setup_parser = sub.add_parser("setup")
    setup_parser.add_argument("--non-interactive", action="store_true")
    sub.add_parser("run")
    sub.add_parser("start")
    sub.add_parser("stop")
    sub.add_parser("status")
    sub.add_parser("config")
    sub.add_parser("cache")
    sub.add_parser("diagnostics")
    sub.add_parser("speech")
    logs_parser = sub.add_parser("logs")
    logs_parser.add_argument("--lines", type=int, default=100)
    args = parser.parse_args(argv)
    try:
        store = ConfigStore.load(root_from_args(args))
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"Configuration could not be loaded / Конфигурация не загружена: {error}", file=sys.stderr)
        return 2
    for message in store.recovery_messages:
        print(localized(store, "Configuration recovered:", "Конфигурация восстановлена:"), message, file=sys.stderr)
    if args.command == "setup":
        return setup(store, args.non_interactive)
    if args.command == "run":
        return run(store)
    if args.command == "start":
        return start_background(store)
    if args.command == "stop":
        return stop_background(store)
    if args.command == "status":
        return 0 if host_status(store) else 1
    if args.command == "config":
        print(json.dumps(store.masked(), ensure_ascii=False, indent=2))
        return 0
    if args.command == "cache":
        print(json.dumps(HostService(store).cleanup_cache(), ensure_ascii=False))
        return 0
    if args.command == "diagnostics":
        return diagnostics(store)
    if args.command == "speech":
        return speech_menu(store)
    if args.command == "logs":
        return show_logs(store, max(1, min(args.lines, 5000)))
    return menu(store)
