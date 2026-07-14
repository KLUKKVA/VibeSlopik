#!/bin/sh
set -eu

VERSION="${VIBESLOPIK_VERSION:-1.0.0}"
REPOSITORY="${VIBESLOPIK_REPOSITORY:-KLUKKVA/VibeSlopik}"
INSTALL_DIR="/opt/vibeslopik-relay"
BIN="$INSTALL_DIR/vibeslopik-relay"
ENV_FILE="/etc/vibeslopik-relay.env"
UNIT_FILE="/etc/systemd/system/vibeslopik-relay.service"
MANAGER="/usr/local/sbin/vibeslopik-relay"
LANGUAGE="${VIBESLOPIK_LANG:-}"

die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }
is_ru() { [ "$LANGUAGE" = "ru" ]; }
msg() { if is_ru; then printf '%s\n' "$1"; else printf '%s\n' "$2"; fi; }
prompt() {
    label=$1 default=$2
    if [ ! -t 0 ]; then printf '%s' "$default"; return; fi
    printf '%s [%s]: ' "$label" "$default" >&2
    IFS= read -r answer || answer=""
    printf '%s' "${answer:-$default}"
}

[ "$(id -u)" = "0" ] || die "Run as root / Запустите от root: sudo sh install-relay-vps.sh"

if [ -z "$LANGUAGE" ]; then
    LANGUAGE=$(prompt "Language / Язык (en/ru)" "en")
fi
case "$LANGUAGE" in ru|en) ;; *) LANGUAGE=en ;; esac

[ -r /etc/os-release ] || die "Unsupported Linux: /etc/os-release is missing"
# The file is validated as readable immediately above.
# shellcheck disable=SC1091
. /etc/os-release
case "${ID:-}:${VERSION_ID:-}" in
    ubuntu:22.04|ubuntu:24.04|debian:12|debian:13) ;;
    *) die "Supported: Ubuntu 22.04/24.04, Debian 12/13. Detected: ${PRETTY_NAME:-unknown}" ;;
esac
command -v systemctl >/dev/null 2>&1 || die "systemd is required / Требуется systemd"
[ "$(cat /proc/1/comm 2>/dev/null || true)" = "systemd" ] || die "systemd is not PID 1"

case "$(uname -m)" in
    x86_64|amd64) ARCH=amd64 ;;
    aarch64|arm64) ARCH=arm64 ;;
    *) die "Unsupported architecture / Неподдерживаемая архитектура: $(uname -m)" ;;
esac

AVAILABLE_KB=$(df -Pk /opt 2>/dev/null | awk 'NR==2 {print $4}')
[ "${AVAILABLE_KB:-0}" -ge 51200 ] || die "At least 50 MiB free in /opt is required"

CURRENT_PORT=8788
SAVED_PORT=""
if [ -f "$ENV_FILE" ]; then
    SAVED_PORT=$(sed -n 's/^VIBESLOPIK_RELAY_PORT=//p' "$ENV_FILE" | tail -n 1)
    [ -n "$SAVED_PORT" ] && CURRENT_PORT=$SAVED_PORT
fi
PORT=${VIBESLOPIK_RELAY_INSTALL_PORT:-$(prompt "Relay port / Порт Relay" "$CURRENT_PORT")}
case "$PORT" in *[!0-9]*|'') die "Port must be a number / Порт должен быть числом" ;; esac
if [ "$PORT" -lt 1024 ] || [ "$PORT" -gt 65535 ]; then die "Use a port from 1024 to 65535"; fi

if command -v ss >/dev/null 2>&1 && ss -H -ltn "sport = :$PORT" 2>/dev/null | grep -q .; then
    if [ "$PORT" != "${SAVED_PORT:-}" ] || ! systemctl is-active --quiet vibeslopik-relay.service 2>/dev/null; then
        die "Port $PORT is occupied. Choose another port; no firewall or foreign service was changed."
    fi
fi

TMP_DIR=$(mktemp -d /tmp/vibeslopik-relay.XXXXXX)
cleanup() { rm -rf "$TMP_DIR"; }
mkdir -p "$TMP_DIR/rollback"
backup_file() {
    source_path=$1 backup_name=$2
    if [ -e "$source_path" ]; then
        cp -p "$source_path" "$TMP_DIR/rollback/$backup_name"
    else
        : >"$TMP_DIR/rollback/$backup_name.absent"
    fi
}
restore_file() {
    target_path=$1 backup_name=$2
    if [ -f "$TMP_DIR/rollback/$backup_name.absent" ]; then
        rm -f "$target_path"
    else
        cp -p "$TMP_DIR/rollback/$backup_name" "$target_path"
    fi
}
backup_file "$BIN" binary
backup_file "$ENV_FILE" environment
backup_file "$UNIT_FILE" unit
backup_file "$MANAGER" manager
INSTALL_DIR_EXISTED=0
[ -d "$INSTALL_DIR" ] && INSTALL_DIR_EXISTED=1
WAS_ENABLED=0
if systemctl is-enabled --quiet vibeslopik-relay.service 2>/dev/null; then WAS_ENABLED=1; fi
WAS_ACTIVE=0
if systemctl is-active --quiet vibeslopik-relay.service 2>/dev/null; then WAS_ACTIVE=1; fi
CHANGES_APPLIED=0
rollback_install() {
    msg "Новая установка Relay не завершилась. Полностью восстанавливаю прежнее состояние." "Relay installation did not complete. Restoring the complete previous state."
    restore_file "$BIN" binary
    restore_file "$ENV_FILE" environment
    restore_file "$UNIT_FILE" unit
    restore_file "$MANAGER" manager
    rm -f "$BIN.new" "$ENV_FILE.new" "$UNIT_FILE.new" "$MANAGER.new"
    systemctl daemon-reload >/dev/null 2>&1 || true
    if [ "$WAS_ENABLED" = "1" ]; then
        systemctl enable vibeslopik-relay.service >/dev/null 2>&1 || true
    else
        systemctl disable vibeslopik-relay.service >/dev/null 2>&1 || true
    fi
    if [ "$WAS_ACTIVE" = "1" ]; then
        systemctl restart vibeslopik-relay.service >/dev/null 2>&1 || true
    else
        systemctl stop vibeslopik-relay.service >/dev/null 2>&1 || true
    fi
    if [ "$INSTALL_DIR_EXISTED" = "0" ]; then rmdir "$INSTALL_DIR" 2>/dev/null || true; fi
}
on_exit() {
    code=$?
    trap - EXIT HUP INT TERM
    if [ "$code" -ne 0 ] && [ "$CHANGES_APPLIED" = "1" ]; then rollback_install; fi
    cleanup
    exit "$code"
}
trap on_exit EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
ASSET="vibeslopik-relay-linux-$ARCH"
MANAGER_ASSET="vibeslopik-relay-manager.sh"

if [ -n "${VIBESLOPIK_RELAY_BINARY:-}" ]; then
    [ -f "$VIBESLOPIK_RELAY_BINARY" ] || die "VIBESLOPIK_RELAY_BINARY does not exist"
    cp "$VIBESLOPIK_RELAY_BINARY" "$TMP_DIR/$ASSET"
    LOCAL_MANAGER="$(dirname "$0")/$MANAGER_ASSET"
    [ -f "$LOCAL_MANAGER" ] || die "Local manager script is missing: $LOCAL_MANAGER"
    cp "$LOCAL_MANAGER" "$TMP_DIR/$MANAGER_ASSET"
else
    command -v curl >/dev/null 2>&1 || { apt-get update; apt-get install -y --no-install-recommends curl ca-certificates; }
    BASE="https://github.com/$REPOSITORY/releases/download/v$VERSION"
    msg "Скачиваю Relay и контрольные суммы..." "Downloading Relay and checksums..."
    curl --fail --location --proto '=https' --tlsv1.2 --retry 3 -o "$TMP_DIR/$ASSET" "$BASE/$ASSET"
    curl --fail --location --proto '=https' --tlsv1.2 --retry 3 -o "$TMP_DIR/$MANAGER_ASSET" "$BASE/$MANAGER_ASSET"
    curl --fail --location --proto '=https' --tlsv1.2 --retry 3 -o "$TMP_DIR/SHA256SUMS" "$BASE/SHA256SUMS"
    for FILE in "$ASSET" "$MANAGER_ASSET"; do
        EXPECTED=$(awk -v name="$FILE" '$2 == name || $2 == "*" name {print $1}' "$TMP_DIR/SHA256SUMS")
        [ -n "$EXPECTED" ] || die "Checksum for $FILE is absent"
        ACTUAL=$(sha256sum "$TMP_DIR/$FILE" | awk '{print $1}')
        [ "$EXPECTED" = "$ACTUAL" ] || die "Checksum mismatch for $FILE; installation stopped"
    done
fi
chmod 0755 "$TMP_DIR/$ASSET"
"$TMP_DIR/$ASSET" --check >/dev/null 2>&1 || die "Downloaded Relay cannot run on this server"

CHANGES_APPLIED=1
install -d -m 0700 "$INSTALL_DIR"
install -m 0755 "$TMP_DIR/$ASSET" "$BIN.new"

if [ ! -f "$ENV_FILE" ]; then
    umask 077
    if command -v openssl >/dev/null 2>&1; then
        ADMIN_KEY=$(openssl rand -hex 32)
    else
        ADMIN_KEY=$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')
    fi
    cat >"$ENV_FILE.new" <<EOF
VIBESLOPIK_RELAY_ADMIN_KEY=$ADMIN_KEY
VIBESLOPIK_RELAY_PORT=$PORT
VIBESLOPIK_RELAY_STATE=$INSTALL_DIR/relay-state.json
VIBESLOPIK_LANG=$LANGUAGE
EOF
else
    sed -e "s/^VIBESLOPIK_RELAY_PORT=.*/VIBESLOPIK_RELAY_PORT=$PORT/" -e '/^VIBESLOPIK_LANG=/d' "$ENV_FILE" >"$ENV_FILE.new"
    printf 'VIBESLOPIK_LANG=%s\n' "$LANGUAGE" >>"$ENV_FILE.new"
fi
chmod 0600 "$ENV_FILE.new"

cat >"$UNIT_FILE.new" <<'UNIT'
[Unit]
Description=VibeSlopik Relay
Documentation=https://github.com/KLUKKVA/VibeSlopik
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/vibeslopik-relay.env
WorkingDirectory=/opt/vibeslopik-relay
ExecStart=/opt/vibeslopik-relay/vibeslopik-relay
Restart=on-failure
RestartSec=3
TimeoutStopSec=20
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/opt/vibeslopik-relay
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
LockPersonality=true
RestrictSUIDSGID=true

[Install]
WantedBy=multi-user.target
UNIT
chmod 0644 "$UNIT_FILE.new"

install -m 0755 "$TMP_DIR/$MANAGER_ASSET" "$MANAGER.new"
mv -f "$BIN.new" "$BIN"
mv -f "$ENV_FILE.new" "$ENV_FILE"
mv -f "$UNIT_FILE.new" "$UNIT_FILE"
mv -f "$MANAGER.new" "$MANAGER"
systemctl daemon-reload
systemctl enable vibeslopik-relay.service >/dev/null
READY_TIMEOUT=${VIBESLOPIK_RELAY_READY_TIMEOUT:-20}
case "$READY_TIMEOUT" in *[!0-9]*|'') READY_TIMEOUT=20 ;; esac
if ! systemctl restart vibeslopik-relay.service || ! "$MANAGER" wait-ready "$READY_TIMEOUT"; then
    exit 1
fi
CHANGES_APPLIED=0

msg "VibeSlopik Relay успешно установлен." "VibeSlopik Relay installed successfully."
msg "Управление: vibeslopik-relay" "Management: vibeslopik-relay"
msg "Данные для настройки Host: sudo vibeslopik-relay credentials" "Host setup values: sudo vibeslopik-relay credentials"
msg "Установщик не менял firewall. При необходимости разрешите TCP $PORT в панели провайдера." "The installer did not change the firewall. Allow TCP $PORT in your provider panel if required."
