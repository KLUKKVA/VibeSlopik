# Troubleshooting and compatibility

Run **Diagnostics** in Host and `sudo vibeslopik-relay diagnostics` on the VPS.
Check failures from the computer outward: Codex, local port, Relay health, then
iPhone URL/token. The diagnostic output does not contain secrets.

Compatibility modes:

- **normal:** safe protocol reads must pass or Host stops with an explanation.
- **compatible:** Host starts and reports unavailable features independently.
- **forced:** skips startup probes and tries the current protocol. Use only when
  a new Codex release is expected to remain compatible.
- **diagnostic:** runs all safe probes and exposes detailed feature state.

If a phone turn appears in VibeSlopik but not in an already open official Codex
desktop window, restart or refresh that official client. VibeSlopik uses the
supported app-server state but cannot force another UI process to repaint.
