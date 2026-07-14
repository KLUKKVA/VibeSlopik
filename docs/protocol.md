# VibeSlopik protocol v2

All transport payloads are JSON. Client and Host secrets are independent.

## Relay

- `GET /healthz` is public and contains no secret data.
- `POST /v1/hosts/register` requires `X-VibeSlopik-Admin-Key`.
- `GET /v1/host/{id}/poll` and `POST /v1/host/{id}/reply` require
  `X-VibeSlopik-Host-Secret`.
- `/v1/client/{id}/...` requires `Authorization: Bearer <client token>` and
  forwards the remaining path/query to Host.

Relay limits request bodies to 32 MiB, each Host queue to 128 requests, global
waiters to 1024 and client waiting time to five minutes. A disconnected client
is removed from both queue and waiter maps.

## Host API

`GET /healthz` is local health. Every `/api/` endpoint requires the client
Bearer token.

- `GET /api/info`, `/api/capabilities`, `/api/home`, `/api/projects`
- `GET /api/threads?cwd=...&cursor=...&limit=...`
- `POST /api/threads` with an existing project `cwd`
- `GET /api/threads/{threadId}`
- `POST /api/threads/{threadId}/overrides`
- `POST /api/threads/{threadId}/turns`
- `GET /api/threads/{threadId}/turns/{turnId}`
- `GET /api/models`, `/api/events`, `/api/approvals`, `/api/account/limits`
- `POST /api/approvals/{approvalId}`
- `POST /api/speech/transcriptions`
- `GET /api/media/{opaqueId}?variant=thumbnail|original`
- `POST /api/cache/clear`

Turn requests use `clientRequestId` for idempotency. Images are sent as at most
four base64 values, each at most 6 MiB. Media responses use opaque IDs and never
contain desktop filesystem paths. Unknown Codex events remain bounded diagnostic
events; normal thread rendering is produced from `thread/read`.
