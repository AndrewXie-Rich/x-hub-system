# REL Flow Hub IPC (JSONL over Unix Domain Socket)

Transport

Two IPC modes exist:

1) JSONL over AF_UNIX socket (non-sandbox builds)
- path: `~/RELFlowHub/.rel_flow_hub.sock` (dev default) or `~/Library/Group Containers/group.rel.flowhub/.rel_flow_hub.sock` (signed builds)
- framing: JSON Lines (one JSON object per line; UTF-8)

2) File dropbox (App Sandbox builds)
- base: `~/Library/Group Containers/group.rel.flowhub/`
- clients write request files into: `ipc_events/*.json` (one request per file)
- hub writes heartbeat: `hub_status.json` (clients use it to detect if hub is running)


Hub heartbeat (file IPC)

In file-dropbox mode, the Hub writes `hub_status.json` with:
- `ipcPath`: the dropbox directory for request files (`ipc_events/`)
- `baseDir`: the base directory for all Hub file IPC state (`ai_requests/`, `clients/`, etc.)
- `protocolVersion`: contract version for forward compatibility

Note: On some macOS versions, sandboxed apps cannot accept external AF_UNIX connections reliably.
The file dropbox mode is the supported path for the sandboxed Hub.

General
- Requests and responses are independent JSON objects.
- Clients SHOULD include `req_id` (string) so they can correlate responses.

Message types

## ping
Request
```json
{"type":"ping","req_id":"..."}
```

Response
```json
{"type":"pong","req_id":"...","ok":true}
```

## push_notification
Request
```json
{
  "type": "push_notification",
  "req_id": "...",
  "notification": {
    "id": "uuid-string (optional)",
    "source": "FAtracker|Calendar|Mail|Messages|...",
    "title": "...",
    "body": "...",
    "created_at": 1730000000.0,
    "dedupe_key": "... (optional)",
    "action_url": "rdar://123456" 
  }
}
```

Response
```json
{"type":"push_ack","req_id":"...","ok":true,"id":"<final-notification-id>"}
```

Notes
- `dedupe_key` can be used to update/merge notifications (e.g. "FAtracker:today_new").
- `action_url` is opened via the system default handler (e.g. `rdar://`, `https://`, `fatracker://`).

## project_sync
Request
```json
{
  "type": "project_sync",
  "req_id": "...",
  "project": {
    "project_id": "hash",
    "root_path": "/path/to/project",
    "display_name": "My Project",
    "status_digest": "short summary",
    "last_summary_at": 1730000000.0,
    "last_event_at": 1730000000.0,
    "updated_at": 1730000000.0
  }
}
```

Response (socket mode)
```json
{"type":"project_ack","req_id":"...","ok":true,"id":"<project_id>"}
```

## project_canonical_memory
Request
```json
{
  "type": "project_canonical_memory",
  "req_id": "...",
  "project_canonical_memory": {
    "project_id": "hash",
    "project_root": "/path/to/project",
    "display_name": "My Project",
    "updated_at": 1730000000.0,
    "items": [
      {
        "key": "xterminal.project.memory.goal",
        "value": "Make Hub memory the default governed source."
      },
      {
        "key": "xterminal.project.memory.next_steps",
        "value": "1. Add file/socket IPC parity"
      }
    ]
  }
}
```

Response (socket mode)
```json
{"type":"project_canonical_memory_ack","req_id":"...","ok":true,"id":"<project_id>"}
```

## need_network
Request
```json
{
  "type": "need_network",
  "req_id": "...",
  "network": {
    "id": "uuid",
    "source": "ax_coder",
    "project_id": "hash",
    "root_path": "/path/to/project",
    "display_name": "My Project",
    "reason": "need docs",
    "requested_seconds": 900,
    "created_at": 1730000000.0
  }
}
```

Response (socket mode)
```json
{"type":"need_network_ack","req_id":"...","ok":true,"id":"<request_id>"}
```
