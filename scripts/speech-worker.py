#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--audio")
    parser.add_argument("--model")
    args = parser.parse_args()
    try:
        from faster_whisper import WhisperModel
    except Exception as error:
        print(json.dumps({"ok": False, "error": f"backend import failed: {error}"}))
        return 2
    if args.check:
        print(json.dumps({"ok": True, "backend": "faster-whisper"}))
        return 0
    if not args.audio or not args.model:
        print(json.dumps({"ok": False, "error": "--audio and --model are required"}))
        return 2
    if not Path(args.audio).is_file() or not (Path(args.model) / "model.bin").is_file():
        print(json.dumps({"ok": False, "error": "audio or model is missing"}))
        return 2
    try:
        model = WhisperModel(args.model, device="cpu", compute_type="int8")
        segments, info = model.transcribe(args.audio, vad_filter=True, language=None, beam_size=5)
        text = "".join(segment.text for segment in segments).strip()
        print(json.dumps({"ok": True, "text": text, "language": getattr(info, "language", None), "languageProbability": getattr(info, "language_probability", None)}, ensure_ascii=False))
        return 0
    except Exception as error:
        print(json.dumps({"ok": False, "error": str(error)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
