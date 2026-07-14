# VPS Relay

Поддерживаются Ubuntu 22.04/24.04 и Debian 12/13 на amd64/arm64. Минимально
достаточно 1 vCPU, 256 МБ RAM, 100 МБ диска и одного TCP-порта.

```sh
curl -fsSL https://github.com/KLUKKVA/VibeSlopik/releases/latest/download/install-relay-vps.sh -o /tmp/vibeslopik-install.sh
sudo sh /tmp/vibeslopik-install.sh
```

Установщик проверит ОС, архитектуру, systemd, диск и порт, сверит SHA-256,
сохранит прошлый бинарник для отката и дождётся ответа `/healthz`. Он не меняет
VPN, Docker, чужие службы и firewall.

Установка и обновление выполняются транзакционно. Если новая служба не выходит
в рабочее состояние, одновременно восстанавливаются прежние бинарник, env-файл,
systemd unit и команда управления. После неудачной первой установки созданные
файлы удаляются. Выбранный язык сохраняется для меню управления.

Команда `sudo vibeslopik-relay` открывает меню. Также доступны `status`, `start`,
`stop`, `restart`, `diagnostics`, `credentials`, `logs`, `set-port PORT`,
`update`, `uninstall`. При настройке Host выполните
`sudo vibeslopik-relay credentials`: приватно скопируйте админ-ключ и соедините
IP VPS с показанным портом.
Служба автоматически запускается после перезагрузки. Не публикуйте содержимое
`/etc/vibeslopik-relay.env`; резервируйте `relay-state.json`.
