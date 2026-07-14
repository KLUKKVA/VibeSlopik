#!/bin/sh
set -eu

SERVICE=vibeslopik-relay.service
ENV_FILE=/etc/vibeslopik-relay.env

port() { sed -n 's/^VIBESLOPIK_RELAY_PORT=//p' "$ENV_FILE" 2>/dev/null | tail -n 1; }
language() { sed -n 's/^VIBESLOPIK_LANG=//p' "$ENV_FILE" 2>/dev/null | tail -n 1; }
is_ru() { [ "$(language)" = "ru" ]; }
label() { if is_ru; then printf '%b' "$1"; else printf '%b' "$2"; fi; }
ready() {
    p=$(port)
    [ -n "$p" ] || return 1
    if command -v curl >/dev/null 2>&1; then curl -fsS --max-time 2 "http://127.0.0.1:$p/healthz" >/dev/null
    else python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:$p/healthz', timeout=2)" >/dev/null 2>&1
    fi
}
wait_ready() { end=$(( $(date +%s) + ${1:-20} )); while [ "$(date +%s)" -lt "$end" ]; do ready && return 0; sleep 1; done; return 1; }
diagnostics() {
    label "Диагностика VibeSlopik Relay\n" "VibeSlopik Relay diagnostics\n"
    os_name=$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release 2>/dev/null | head -n 1)
    os_name=${os_name#\"}; os_name=${os_name%\"}
    printf '%s: %s\n' "$(label "ОС" "OS")" "${os_name:-unknown}"
    printf '%s: %s\n' "$(label "Архитектура" "Architecture")" "$(uname -m)"
    printf '%s: %s\n' "$(label "Порт" "Port")" "$(port || true)"
    printf '%s: %s\n' "$(label "Служба" "Service")" "$(systemctl is-active "$SERVICE" 2>/dev/null || true)"
    printf '%s: %s\n' "$(label "Автозапуск" "Enabled")" "$(systemctl is-enabled "$SERVICE" 2>/dev/null || true)"
    if ready; then label "Здоровье: OK\n" "Health: OK\n"; else label "Здоровье: ОШИБКА\n" "Health: FAILED\n"; fi
    label "Последние логи:\n" "Recent logs:\n"
    journalctl -u "$SERVICE" -n 20 --no-pager 2>/dev/null || true
}
credentials() {
    key=$(sed -n 's/^VIBESLOPIK_RELAY_ADMIN_KEY=//p' "$ENV_FILE" 2>/dev/null | tail -n 1)
    [ -n "$key" ] || { label "Админ-ключ не найден\n" "Admin key was not found\n" >&2; return 1; }
    label "Показывайте эти данные только владельцу Host.\n" "Show these values only to the Host owner.\n"
    printf 'Port: %s\nAdmin key: %s\n' "$(port)" "$key"
}
set_port() {
    new=${1:-}
    case "$new" in *[!0-9]*|'') echo "Port must be numeric / Порт должен быть числом" >&2; return 2 ;; esac
    if [ "$new" -lt 1024 ] || [ "$new" -gt 65535 ]; then echo "Port must be 1024..65535" >&2; return 2; fi
    old=$(port)
    [ "$new" = "$old" ] && { echo "Port is unchanged / Порт не изменён"; return 0; }
    if command -v ss >/dev/null 2>&1 && ss -H -ltn "sport = :$new" 2>/dev/null | grep -q .; then echo "Port $new is occupied / Порт занят" >&2; return 2; fi
    cp "$ENV_FILE" "$ENV_FILE.bak"
    sed "s/^VIBESLOPIK_RELAY_PORT=.*/VIBESLOPIK_RELAY_PORT=$new/" "$ENV_FILE.bak" >"$ENV_FILE.new"
    chmod 0600 "$ENV_FILE.new" && mv -f "$ENV_FILE.new" "$ENV_FILE"
    if ! systemctl restart "$SERVICE" || ! wait_ready 20; then
        mv -f "$ENV_FILE.bak" "$ENV_FILE"; systemctl restart "$SERVICE" || true
        echo "New port failed; previous settings restored / Выполнен откат" >&2; return 1
    fi
    rm -f "$ENV_FILE.bak"; echo "Port changed to $new. Update VPS firewall rules yourself if needed."
}
update_relay() {
    command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; return 1; }
    temporary=$(mktemp /tmp/vibeslopik-install.XXXXXX)
    trap 'rm -f "$temporary"' EXIT HUP INT TERM
    curl --fail --location --proto '=https' --tlsv1.2 --retry 3 -o "$temporary" https://github.com/KLUKKVA/VibeSlopik/releases/latest/download/install-relay-vps.sh
    VIBESLOPIK_LANG=$(language) sh "$temporary"
}
uninstall_relay() {
    keep=${1:-}
    if [ "$keep" != "--keep-data" ]; then
        printf 'Remove Relay and its registered hosts? Type REMOVE / Удалить Relay? Введите REMOVE: '
        IFS= read -r answer || answer=""
        [ "$answer" = "REMOVE" ] || { echo "Cancelled / Отменено"; return 0; }
    fi
    systemctl disable --now "$SERVICE" 2>/dev/null || true
    rm -f /etc/systemd/system/vibeslopik-relay.service /usr/local/sbin/vibeslopik-relay
    if [ "$keep" = "--keep-data" ]; then
        echo "Data kept in /opt/vibeslopik-relay and /etc/vibeslopik-relay.env"
    else
        rm -rf /opt/vibeslopik-relay /etc/vibeslopik-relay.env
    fi
    systemctl daemon-reload
    echo "Relay removed / Relay удалён"
}
menu() {
    while :; do
        if is_ru; then
            printf '\nVibeSlopik Relay\n1. Статус\n2. Запустить\n3. Остановить\n4. Перезапустить\n5. Диагностика\n6. Логи\n7. Изменить порт\n8. Обновить\n9. Удалить\n10. Данные подключения\n0. Выход\n> '
        else
            printf '\nVibeSlopik Relay\n1. Status\n2. Start\n3. Stop\n4. Restart\n5. Diagnostics\n6. Logs\n7. Change port\n8. Update\n9. Uninstall\n10. Connection credentials\n0. Exit\n> '
        fi
        IFS= read -r choice || exit 0
        case "$choice" in
            1) systemctl status "$SERVICE" --no-pager || true ;;
            2) systemctl start "$SERVICE" ;;
            3) systemctl stop "$SERVICE" ;;
            4) systemctl restart "$SERVICE" ;;
            5) diagnostics ;;
            6) journalctl -u "$SERVICE" -f ;;
            7) printf 'New port / Новый порт: '; IFS= read -r value; set_port "$value" ;;
            8) update_relay ;;
            9) uninstall_relay ; return ;;
            10) credentials ;;
            0) exit 0 ;;
            *) echo "Unknown option / Неизвестный пункт" ;;
        esac
    done
}

case "${1:-menu}" in
    status) systemctl status "$SERVICE" --no-pager ;;
    start|stop|restart) systemctl "$1" "$SERVICE" ;;
    logs) journalctl -u "$SERVICE" -f ;;
    diagnostics) diagnostics ;;
    credentials) credentials ;;
    set-port) set_port "${2:-}" ;;
    update) update_relay ;;
    uninstall) uninstall_relay "${2:-}" ;;
    wait-ready) wait_ready "${2:-20}" ;;
    menu) menu ;;
    *) echo "Usage: vibeslopik-relay [status|start|stop|restart|logs|diagnostics|credentials|set-port PORT|update|uninstall]"; exit 2 ;;
esac
