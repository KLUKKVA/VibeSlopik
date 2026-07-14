# Desktop Host

Download the archive matching Windows x64, Linux x64, macOS Intel or Apple
Silicon. Unpack it to a permanent directory and run `VibeSlopik-Host`. Python is
not required for release archives.

Without arguments Host opens a menu. First-run setup validates Codex, the
projects directory, Relay URL, credentials and compatibility mode before saving
an atomic configuration under `data/`. Secrets are stored separately in
`data/secret.env`. The menu controls diagnostics, cache, language, autostart and
the optional Speech Pack.

If `config.toml` is syntactically damaged, Host preserves it as
`config.toml.corrupt-TIMESTAMP`, restores safe defaults and reports the recovery.
Semantic mistakes are not silently replaced: diagnostics identifies the invalid
setting so it can be corrected.

Choose **Start Host** from the menu (or run `VibeSlopik-Host start`). Host runs
in the background and writes logs under `data/logs`. Use **Stop Host** or
`VibeSlopik-Host stop` for a clean authenticated shutdown. `status`, `logs` and
`diagnostics` are also available as commands; diagnostics never include tokens
or chat content. `run` remains available for foreground/service use.

Host validates `codex --version` during setup. If Windows resolves `codex` to an
inaccessible WindowsApps alias, install the Codex CLI or enter the path to a
launchable Codex executable; Host will not save a path that fails its probe.
