# Building from source

Host requires Python 3.11. Install with `python -m pip install -e .`; run tests
with `python -m unittest discover -s tests -v`. Build a native archive with
`python scripts/build-host.py --install-build-deps`. Speech Worker uses
`scripts/build-speech-pack.py`.

Relay requires Go 1.22: `go -C relay-go test ./...` and `go -C relay-go build`.

iOS requires Theos and a legally obtained iPhoneOS 6.1 SDK. On Windows, install
a WSL distribution and run `scripts/setup-theos-wsl.sh`, then use
`scripts/build-ios-wsl-stable.ps1 -Distro YOUR_DISTRO`. The only final IPA path
is `dist/VibeSlopik.ipa`. SDK and Codex binaries must never be committed.

Before publishing, collect every platform archive, both Relay binaries, both
installer scripts and `VibeSlopik.ipa` in one directory. Run
`python scripts/verify-release-assets.py DIRECTORY --write`; it rejects missing
or extra files and verifies that `SHA256SUMS` covers every release asset.
