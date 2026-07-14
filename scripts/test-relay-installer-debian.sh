#!/bin/sh
set -eu

cd /workspace
PORT=18888
NEXT_PORT=18889

env VIBESLOPIK_RELAY_BINARY=/workspace/vibeslopik-relay-test \
    VIBESLOPIK_RELAY_INSTALL_PORT="$PORT" VIBESLOPIK_LANG=en \
    sh scripts/install-relay-vps.sh </dev/null
curl -fsS "http://127.0.0.1:$PORT/healthz" >/dev/null

# A second run must preserve credentials and remain healthy.
before=$(sha256sum /etc/vibeslopik-relay.env | awk '{print $1}')
env VIBESLOPIK_RELAY_BINARY=/workspace/vibeslopik-relay-test \
    VIBESLOPIK_RELAY_INSTALL_PORT="$PORT" VIBESLOPIK_LANG=en \
    sh scripts/install-relay-vps.sh </dev/null
after=$(sha256sum /etc/vibeslopik-relay.env | awk '{print $1}')
[ "$before" = "$after" ]
vibeslopik-relay diagnostics

vibeslopik-relay set-port "$NEXT_PORT"
curl -fsS "http://127.0.0.1:$NEXT_PORT/healthz" >/dev/null
vibeslopik-relay uninstall --keep-data
[ ! -e /etc/systemd/system/vibeslopik-relay.service ]
[ ! -e /usr/local/sbin/vibeslopik-relay ]
rm -rf /opt/vibeslopik-relay /etc/vibeslopik-relay.env

printf 'Debian Relay installer integration test passed.\n'
