# Speech Pack

Speech recognition is optional and never downloads silently. Open **Speech
Pack** in Host, inspect disk/RAM estimates, select a profile and confirm the
download. Host shows progress, verifies the release checksum and creates a local
SHA-256 manifest for every model file.

- Economy: about 150 MiB model, about 400 MiB RAM.
- Recommended: about 500 MiB model, about 900 MiB RAM.
- Quality: about 1.5 GiB model, about 2.1 GiB RAM.

Models and the worker live under Host `data/`, can be disabled independently,
verified, changed or removed from the same menu. A speech failure does not stop
Codex or Relay.

Before downloading, Host checks free disk space. A model is downloaded into a
temporary directory, verified file-by-file and atomically replaces the previous
model only after success; interruption leaves the working model intact. Choose
**Test an audio recording** to select a WAV, M4A or MP3 file and verify the full
worker/model transcription path before using dictation from the iPhone.
