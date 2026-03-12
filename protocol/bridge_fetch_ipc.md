# X-Hub Bridge Fetch IPC (MVP)

Goal
- Allow local apps (e.g. AX Coder) to request *networked* HTTP GET via X-Hub Bridge.
- Keep the core Hub offline-auditable; only the Bridge performs networking.

Transport (file IPC under Hub baseDir)
- Requests: `<baseDir>/bridge_requests/req_<req_id>.json`
- Responses: `<baseDir>/bridge_responses/resp_<req_id>.json`

Notes
- The Bridge must be running and enabled (see `bridge_settings.json` / `bridge_commands`).
- The Bridge SHOULD refuse non-HTTPS URLs by default.

Request schema
```json
{
  "type": "fetch",
  "req_id": "uuid",
  "url": "https://example.com/...",
  "method": "GET",
  "created_at": 1730000000.0,
  "timeout_sec": 12,
  "max_bytes": 1000000
}
```

Response schema
```json
{
  "type": "fetch_result",
  "req_id": "uuid",
  "ok": true,
  "status": 200,
  "final_url": "https://example.com/...",
  "content_type": "text/html; charset=utf-8",
  "truncated": false,
  "bytes": 12345,
  "text": "...",
  "error": ""
}
```
