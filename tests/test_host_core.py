from __future__ import annotations

import json
import os
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

from PIL import Image

from vibeslopik_host import autostart
from vibeslopik_host.cli import ask_secret_local, verify_codex_binary
from vibeslopik_host.config import ConfigStore, config_path, validate_config
from vibeslopik_host.host import HostService, localize_codex_error
from vibeslopik_host.rpc import CodexRPC
from vibeslopik_host.speech import download_model, model_path, verify_model, write_manifest


class ConfigTests(unittest.TestCase):
    def test_secret_prompt_never_contains_saved_value(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            store = ConfigStore.load(Path(directory))
            store.value["app"]["language"] = "ru"
            with mock.patch("vibeslopik_host.cli.getpass.getpass", return_value="") as prompt:
                self.assertEqual(ask_secret_local(store, "Secret", "Секрет", "private-value"), "private-value")
            self.assertNotIn("private-value", prompt.call_args.args[0])

    def test_corrupt_toml_is_preserved_and_safe_defaults_are_restored(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            broken = config_path(root)
            broken.parent.mkdir(parents=True)
            broken.write_text('[host\nport = "broken"', encoding="utf-8")
            store = ConfigStore.load(root)
            self.assertEqual(store.value["host"]["port"], 8787)
            self.assertTrue(store.recovery_messages)
            backups = list(broken.parent.glob("config.toml.corrupt-*"))
            self.assertEqual(len(backups), 1)
            self.assertIn('port = "broken"', backups[0].read_text(encoding="utf-8"))
            self.assertTrue(broken.exists())

    def test_atomic_round_trip_and_secret_permissions(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            store = ConfigStore.load(root)
            store.value["app"]["language"] = "ru"
            store.save()
            loaded = ConfigStore.load(root)
            self.assertEqual(loaded.value["app"]["language"], "ru")
            self.assertNotIn(loaded.client_token, config_path(root).read_text(encoding="utf-8"))

    def test_validation_rejects_remote_bind_and_bad_port(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            store = ConfigStore.load(Path(directory))
            store.value["host"].update({"bind": "0.0.0.0", "port": 80})
            errors = validate_config(store.value)
            self.assertGreaterEqual(len(errors), 2)
            with self.assertRaises(ValueError):
                store.save()

    def test_validation_rejects_ambiguous_relay_urls_and_host_ids(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            store = ConfigStore.load(Path(directory))
            store.value["relay"].update({"url": "http://user:pass@example.test:bad/path?secret=1", "host_id": "bad/id"})
            errors = validate_config(store.value)
            self.assertTrue(any("relay.url" in error for error in errors))
            self.assertTrue(any("relay.host_id" in error for error in errors))

    def test_codex_validation_reports_unlaunchable_binary(self) -> None:
        with mock.patch("vibeslopik_host.cli.subprocess.run", side_effect=PermissionError("denied")):
            ok, detail = verify_codex_binary("codex")
        self.assertFalse(ok)
        self.assertIn("denied", detail)


class SpeechManifestTests(unittest.TestCase):
    def test_manifest_detects_corruption(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            models = Path(directory)
            model = models / "faster-whisper-base"
            model.mkdir()
            (model / "model.bin").write_bytes(b"valid model")
            write_manifest(model)
            self.assertEqual(verify_model(models, "economy"), (True, "OK"))
            (model / "model.bin").write_bytes(b"corrupt")
            valid, detail = verify_model(models, "economy")
            self.assertFalse(valid)
            self.assertIn("mismatch", detail)

    def test_model_download_is_atomic_and_preserves_previous_model(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            models = Path(directory)
            target = model_path(models, "economy")
            target.mkdir()
            (target / "model.bin").write_bytes(b"previous")
            write_manifest(target)

            def broken_download(**kwargs: object) -> None:
                destination = Path(str(kwargs["local_dir"]))
                (destination / "model.bin").write_bytes(b"partial")
                raise RuntimeError("network interrupted")

            module = types.SimpleNamespace(snapshot_download=broken_download)
            with mock.patch("vibeslopik_host.speech.importlib.util.find_spec", return_value=True), mock.patch.dict("sys.modules", {"huggingface_hub": module}), mock.patch("vibeslopik_host.speech.shutil.disk_usage", return_value=types.SimpleNamespace(free=10 * 1024**3)):
                with self.assertRaisesRegex(RuntimeError, "network interrupted"):
                    download_model(models, "economy", progress=lambda message: None)
            self.assertEqual((target / "model.bin").read_bytes(), b"previous")
            self.assertFalse(target.with_name(target.name + ".new").exists())

            def successful_download(**kwargs: object) -> None:
                destination = Path(str(kwargs["local_dir"]))
                (destination / "model.bin").write_bytes(b"replacement")

            module.snapshot_download = successful_download
            with mock.patch("vibeslopik_host.speech.importlib.util.find_spec", return_value=True), mock.patch.dict("sys.modules", {"huggingface_hub": module}), mock.patch("vibeslopik_host.speech.shutil.disk_usage", return_value=types.SimpleNamespace(free=10 * 1024**3)):
                download_model(models, "economy", progress=lambda message: None)
            self.assertEqual((target / "model.bin").read_bytes(), b"replacement")
            self.assertEqual(verify_model(models, "economy"), (True, "OK"))

    def test_model_download_rejects_low_disk_space_before_network(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            module = types.SimpleNamespace(snapshot_download=mock.Mock())
            with mock.patch("vibeslopik_host.speech.importlib.util.find_spec", return_value=True), mock.patch.dict("sys.modules", {"huggingface_hub": module}), mock.patch("vibeslopik_host.speech.shutil.disk_usage", return_value=types.SimpleNamespace(free=1)):
                with self.assertRaisesRegex(RuntimeError, "not enough disk space"):
                    download_model(Path(directory), "economy", progress=lambda message: None)
            module.snapshot_download.assert_not_called()


class MediaTests(unittest.TestCase):
    def test_cache_cleanup_honors_age_lru_and_workspace_boundary(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            service = HostService(ConfigStore.load(root))
            service.config.value["cache"].update({"max_mebibytes": 16, "media_mebibytes": 8, "attachment_days": 1, "tmp_hours": 1})
            attachments = root / "data" / "attachments" / "thread"
            temporary = root / "data" / "tmp"
            attachments.mkdir(parents=True)
            old_attachment = attachments / "old.jpg"
            fresh_attachment = attachments / "fresh.jpg"
            old_audio = temporary / "old.wav"
            original = root / "user-original.jpg"
            for path in (old_attachment, fresh_attachment, old_audio, original):
                path.write_bytes(b"content")
            old_time = __import__("time").time() - 3 * 86400
            os.utime(old_attachment, (old_time, old_time))
            os.utime(old_audio, (old_time, old_time))
            result = service.cleanup_cache()
            self.assertTrue(result["ok"])
            self.assertFalse(old_attachment.exists())
            self.assertFalse(old_audio.exists())
            self.assertTrue(fresh_attachment.exists())
            self.assertTrue(original.exists())
            oldest = attachments / "lru-old.jpg"
            newest = attachments / "lru-new.jpg"
            with oldest.open("wb") as handle:
                handle.truncate(9 * 1024 * 1024)
            with newest.open("wb") as handle:
                handle.truncate(9 * 1024 * 1024)
            recent_old = __import__("time").time() - 120
            os.utime(oldest, (recent_old, recent_old))
            service.cleanup_cache()
            self.assertFalse(oldest.exists())
            self.assertTrue(newest.exists())

    def test_attachment_limits_fail_before_writing_temporary_files(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            service = HostService(ConfigStore.load(root))
            encoded = __import__("base64").b64encode(b"image").decode("ascii")
            with self.assertRaisesRegex(ValueError, "no more than 4"):
                service._write_images("thread", [encoded] * 5)
            self.assertFalse((root / "data" / "attachments" / "thread").exists())
            with self.assertRaisesRegex(ValueError, "valid base64"):
                service._write_images("thread", [encoded, "not-base64"])
            self.assertFalse((root / "data" / "attachments" / "thread").exists())

    def test_media_ids_hide_paths_and_thumbnails_are_bounded(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "private-name.png"
            Image.new("RGB", (1600, 1200), "blue").save(source)
            service = HostService(ConfigStore.load(root))
            media = service.register_media(str(source), "codex")
            self.assertIsNotNone(media)
            self.assertNotIn(str(source), json.dumps(media))
            payload = service.media_data(media["id"], "thumbnail")
            self.assertLess(payload["bytes"], source.stat().st_size)

    def test_thread_media_is_normalized_without_local_paths(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            user_image = root / "user-secret.png"
            codex_image = root / "codex-secret.jpg"
            Image.new("RGB", (64, 64), "red").save(user_image)
            Image.new("RGB", (64, 64), "green").save(codex_image)
            service = HostService(ConfigStore.load(root))
            thread = {
                "id": "thread-1",
                "turns": [{
                    "id": "turn-1",
                    "items": [
                        {"id": "user", "type": "userMessage", "content": [{"type": "inputText", "text": "look"}, {"type": "localImage", "path": str(user_image)}]},
                        {"id": "generated", "type": "imageGeneration", "savedPath": str(codex_image), "revisedPrompt": "result"},
                    ],
                }],
            }
            normalized = service.normalize_thread(thread)
            encoded = json.dumps(normalized)
            self.assertEqual(len(normalized["messages"]), 2)
            self.assertEqual(normalized["messages"][0]["media"][0]["source"], "user")
            self.assertEqual(normalized["messages"][1]["media"][0]["source"], "codex")
            self.assertNotIn(str(user_image), encoded)
            self.assertNotIn(str(codex_image), encoded)


class HomeTests(unittest.TestCase):
    def test_home_limits_recent_threads_to_ten(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            service = HostService(ConfigStore.load(Path(directory)))
            threads = [{"id": f"thread-{index}", "cwd": str(Path(directory) / "project"), "updatedAt": 100 - index} for index in range(15)]
            service.rpc.request = mock.Mock(return_value={"data": threads})
            home = service.projects_and_recent()
            self.assertEqual(len(home["recentThreads"]), 10)
            self.assertEqual(home["recentThreads"][0]["id"], "thread-0")

    def test_codex_errors_follow_host_language(self) -> None:
        self.assertIn("VPN", localize_codex_error("stream disconnected", "ru"))
        self.assertIn("Check VPN", localize_codex_error("stream disconnected", "en"))
        self.assertIn("/compact", localize_codex_error("context window exceeded", "en"))


class RPCTests(unittest.TestCase):
    def test_compatibility_modes_probe_features_independently(self) -> None:
        rpc = CodexRPC("codex", ".", lambda event: None)

        def partial_protocol(method: str, params: dict, timeout: float = 0) -> dict:
            if method == "model/list":
                return {"data": []}
            raise RuntimeError("method not found")

        rpc.request = mock.Mock(side_effect=partial_protocol)
        compatible = rpc.probe_features("compatible")
        self.assertEqual(compatible["models"]["state"], "available")
        self.assertEqual(compatible["threads"]["state"], "unavailable")
        with self.assertRaisesRegex(RuntimeError, "threads"):
            rpc.probe_features("normal")

    def test_forced_mode_skips_safe_protocol_probes(self) -> None:
        rpc = CodexRPC("codex", ".", lambda event: None)
        rpc.request = mock.Mock(side_effect=AssertionError("must not probe"))
        status = rpc.probe_features("forced")
        self.assertEqual(status["models"]["state"], "unchecked")
        self.assertEqual(status["threads"]["state"], "unchecked")
        rpc.request.assert_not_called()

    def test_diagnostic_mode_reports_failures_without_stopping(self) -> None:
        rpc = CodexRPC("codex", ".", lambda event: None)
        rpc.request = mock.Mock(side_effect=RuntimeError("new protocol"))
        status = rpc.probe_features("diagnostic")
        self.assertEqual(status["models"]["state"], "unavailable")
        self.assertIn("new protocol", status["models"]["reason"])

    def test_runtime_feature_status_replaces_assumptions(self) -> None:
        rpc = CodexRPC("codex", ".", lambda event: None)
        rpc.request = mock.Mock(return_value={"ok": True})
        self.assertEqual(rpc.request_feature("turns", "turn/start", {}), {"ok": True})
        self.assertEqual(rpc.feature_status["turns"]["state"], "available")
        rpc.request.side_effect = RuntimeError("method changed")
        with self.assertRaisesRegex(RuntimeError, "method changed"):
            rpc.request_feature("turns", "turn/start", {})
        self.assertEqual(rpc.feature_status["turns"]["state"], "unavailable")
        self.assertIn("method changed", rpc.feature_status["turns"]["reason"])

    def test_pending_requests_fail_immediately_when_process_stops(self) -> None:
        rpc = CodexRPC("codex", ".", lambda event: None)
        waiter = __import__("queue").Queue(maxsize=1)
        rpc.pending[1] = waiter
        rpc._fail_pending("stopped")
        self.assertEqual(waiter.get_nowait()["error"]["message"], "stopped")
        self.assertFalse(rpc.pending)

    def test_string_rpc_error_is_supported(self) -> None:
        rpc = CodexRPC("codex", ".", lambda event: None)
        rpc.process = mock.Mock()
        rpc.process.poll.return_value = None

        def respond(message: dict) -> None:
            rpc.pending[message["id"]].put({"id": message["id"], "error": "new protocol error"})

        rpc._send = respond
        with self.assertRaisesRegex(RuntimeError, "new protocol error"):
            rpc.request("test", {}, timeout=0.1)


@unittest.skipUnless(os.name == "nt", "Windows startup folder test")
class AutostartTests(unittest.TestCase):
    def test_windows_autostart_install_remove(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with mock.patch.dict(os.environ, {"APPDATA": str(root / "appdata")}):
                result = autostart.install(root)
                self.assertTrue(result["enabled"])
                content = Path(result["path"]).read_text(encoding="utf-8")
                self.assertIn("vibeslopik_host", content)
                self.assertFalse(autostart.remove()["enabled"])


class CrossPlatformAutostartTests(unittest.TestCase):
    def test_macos_launch_agent_install_remove(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root & project"
            target = Path(directory) / "com.vibeslopik.host.plist"
            with mock.patch.object(autostart.sys, "platform", "darwin"), mock.patch.object(autostart, "target", return_value=target), mock.patch("vibeslopik_host.autostart.subprocess.run") as run:
                result = autostart.install(root)
                self.assertTrue(result["enabled"])
                content = target.read_text(encoding="utf-8")
                self.assertIn("root &amp; project", content)
                self.assertIn("RunAtLoad", content)
                self.assertEqual(run.call_count, 2)
                self.assertFalse(autostart.remove()["enabled"])
                self.assertEqual(run.call_count, 3)

    def test_linux_user_service_install_remove(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "root with spaces"
            target = Path(directory) / "vibeslopik-host.service"
            with mock.patch.object(autostart.sys, "platform", "linux"), mock.patch.object(autostart, "target", return_value=target), mock.patch("vibeslopik_host.autostart.subprocess.run") as run:
                result = autostart.install(root)
                self.assertTrue(result["enabled"])
                content = target.read_text(encoding="utf-8")
                self.assertIn("ExecStart=", content)
                self.assertIn(autostart.shlex.quote(str(root)), content)
                run.assert_any_call(["systemctl", "--user", "enable", "--now", "vibeslopik-host.service"], check=True)
                self.assertFalse(autostart.remove()["enabled"])
                run.assert_any_call(["systemctl", "--user", "disable", "--now", "vibeslopik-host.service"], check=False)


if __name__ == "__main__":
    unittest.main()
