# Updating

## Relay

Run `sudo vibeslopik-relay update`. The installer verifies checksums and rolls
back the complete previous installation if health checks fail. Registered Hosts
remain in `/opt/vibeslopik-relay/relay-state.json`.

## Desktop Host

Stop Host, replace the extracted application directory with the new archive and
start it again. Keep its `data/` directory. Host migrates supported settings and
preserves a damaged configuration before restoring safe defaults.

## iOS

Install the new `VibeSlopik.ipa` over the existing application. Settings and
drafts are retained by iOS; make a backup before uninstalling the old app.

After a Codex update, run Host diagnostics. Read the per-feature compatibility
report before selecting compatible or forced mode.
