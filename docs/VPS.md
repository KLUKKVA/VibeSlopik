# VPS Relay

Supported systems: Ubuntu 22.04/24.04 and Debian 12/13 on amd64 or arm64.
Recommended minimum: 1 vCPU, 256 MiB RAM, 100 MiB free disk and one TCP port.

```sh
curl -fsSL https://github.com/KLUKKVA/VibeSlopik/releases/latest/download/install-relay-vps.sh -o /tmp/vibeslopik-install.sh
sudo sh /tmp/vibeslopik-install.sh
```

The installer verifies the OS, architecture, systemd, disk and selected port.
It verifies SHA-256 checksums, keeps a previous binary for rollback, creates a
hardened systemd unit and waits for `/healthz`. It does not alter Docker, VPN,
other services or firewall rules.

Installation and upgrades are transactional. If the new service does not become
healthy, the previous binary, environment, systemd unit and management command
are restored together. A failed first installation removes every file it
created. The selected English or Russian language is saved for the manager.

Run `sudo vibeslopik-relay` for the menu, or use `status`, `start`, `stop`,
`restart`, `diagnostics`, `credentials`, `logs`, `set-port PORT`, `update` and
`uninstall`. During Host setup, run `sudo vibeslopik-relay credentials`; copy
the admin key privately and combine the VPS IP with the displayed port.
The service starts automatically after reboot. Keep `/etc/vibeslopik-relay.env`
private and back up `/opt/vibeslopik-relay/relay-state.json`.
