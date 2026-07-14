# FAQ / Частые вопросы

## Is a domain required? / Нужен ли домен?

No. An IP address and port work. A domain is useful only for conventional TLS.
Нет. Достаточно IP и порта; домен нужен только для обычной настройки TLS.

## Does Relay run Codex? / Codex работает на VPS?

No. Codex and projects remain on the desktop Host. Relay only joins two outbound
connections. Нет. Codex и проекты остаются на компьютере; Relay только связывает
два исходящих соединения.

## Will media fill the disk? / Фото забьют диск?

Host uses age and size limits; iPhone uses a 50 MiB LRU cache. Relay keeps media
only in memory while forwarding. Host ограничивает срок и размер, iPhone — 50 МБ
LRU, а Relay держит данные только в памяти на время передачи.

## Glossary / Словарь

- **Relay:** small VPS forwarding service / сервис-посредник на VPS.
- **Host:** desktop process connected to Codex / программа на компьютере.
- **turn:** one user request and Codex execution / один запрос и выполнение Codex.
- **thread/chat:** a persistent Codex conversation / постоянный диалог Codex.
- **project:** a working directory grouping chats / рабочая папка с чатами.
- **Speech Pack:** optional local transcription worker / необязательный локальный распознаватель.
- **compatibility mode:** Host behaviour after protocol changes / поведение Host при изменении протокола.
