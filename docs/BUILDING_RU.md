# Сборка из исходников

Host требует Python 3.11. Установите `python -m pip install -e .`, тестируйте
`python -m unittest discover -s tests -v`, собирайте архив командой
`python scripts/build-host.py --install-build-deps`. Speech Worker собирается
через `scripts/build-speech-pack.py`.

Relay требует Go 1.22: `go -C relay-go test ./...` и `go -C relay-go build`.

Для iOS нужны Theos и легально полученный iPhoneOS 6.1 SDK. На Windows настройте
WSL через `scripts/setup-theos-wsl.sh`, затем запустите
`scripts/build-ios-wsl-stable.ps1 -Distro ИМЯ`. Итоговый путь всегда один:
`dist/VibeSlopik.ipa`. SDK и бинарники Codex нельзя коммитить.

Перед публикацией соберите архивы всех платформ, оба бинарника Relay, оба
установочных скрипта и `VibeSlopik.ipa` в одном каталоге. Выполните
`python scripts/verify-release-assets.py КАТАЛОГ --write`: команда отклонит
лишние или отсутствующие файлы и проверит, что `SHA256SUMS` охватывает каждый
релизный артефакт.
