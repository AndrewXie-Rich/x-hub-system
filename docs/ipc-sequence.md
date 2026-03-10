# IPC Sequences (AX Coder <-> AX Flow Hub)

This document defines the minimal IPC flow, message envelope, and key payload fields
for AX Coder and AX Flow Hub. It is intentionally small and implementation-agnostic.

## 0) Scope
- Transport: file-based IPC (requests/responses/events directories)
- Roles: AX Coder (client) and AX Flow Hub (provider)
- Bridge: only component allowed to access the network

## 1) IPC Directory Layout (v1)
- `~/Library/Application Support/AXFlowHub/ipc/requests/`
- `~/Library/Application Support/AXFlowHub/ipc/responses/`
- `~/Library/Application Support/AXFlowHub/ipc/events/`
- `~/Library/Application Support/AXFlowHub/ipc/bridge_inbox/`
- `~/Library/Application Support/AXFlowHub/ipc/bridge_outbox/`
- `~/Library/Application Support/AXFlowHub/ipc/state/`
- `~/Library/Application Support/AXFlowHub/ipc/locks/` (optional)

Naming:
- `requests/{requestId}.json`
- `responses/{requestId}.json`
- `events/{eventId}.json`

## 2) Message Envelope (all requests/responses/events)
```json
{
  "version": "1.0",
  "id": "uuid",
  "type": "request|response|event",
  "action": "list_models|chat|agent_spawn|agent_release|status|need_network|web_fetch|schedule_report|project_sync",
  "from": "ax_coder|ax_flow_hub|bridge",
  "to": "ax_flow_hub|ax_coder|bridge",
  "timestamp": "2026-02-05T12:34:56Z",
  "correlation_id": "uuid-of-request",
  "priority": "low|normal|high",
  "timeout_ms": 60000,
  "payload": {},
  "error": {
    "code": "",
    "message": "",
    "retryable": false
  }
}
```

Required fields:
- `id`, `type`, `action`, `from`, `to`, `timestamp`, `payload`
- `correlation_id` required for responses and events related to a request

Recommended:
- `priority` for scheduling decisions
- `timeout_ms` used by Hub for time-bounded work

## 3) Core Sequence Diagrams

### A) Startup: model list and status
```
AX Coder                         AX Flow Hub
   |  list_models request  --------> |
   |  (roles needed)                 |
   | <-------- list_models response  |
   |  (models + routing)             |
   |                                 |
   |  status request  -------------->|
   | <-------------- status response |
```

### B) Resident Butler lifecycle (per project)
```
AX Coder                         AX Flow Hub
   |  agent_spawn (resident) -----> |
   | <---- agent_spawn response     |
   |                                 |
   |---- heartbeats (optional) ---->|
   |<--- agent_status (events) -----|
```

### C) Worker lifecycle (on demand)
```
AX Coder                         AX Flow Hub
   |  agent_spawn (reviewer) ----> |
   | <---- agent_spawn response     |
   |                                 |
   |  chat (role=reviewer) -------> |
   | <----- chat response            |
   |                                 |
   |  agent_release --------------> |
   | <---- agent_release response    |
```

### D) Memory update and project status sync
```
AX Coder                         AX Flow Hub
   |  (local) update .axcoder/AX_MEMORY.md
   |  project_sync (status_digest) ------>|
   | <----- project_sync response          |
```

### E) Scheduled and event-triggered reports
```
AX Flow Hub                 AX Coder
   |  schedule_report -------->|
   |<-------- ack              |
   |                            |
   | (cron/event triggers)      |
   |---- event(report_ready) -->|
   |<--- report_delivered ----- |
```

### F) Network request (all outbound traffic via Hub/Bridge)
```
AX Coder         Hub IPC            Bridge (Network)
   | need_network -> |                 |
   |                 | -> bridge_outbox|
   |                 |                 |  HTTP/WS
   |                 | <- bridge_inbox |
   | <- response ----|                 |
```

### G) Global Butler summary flow
```
AX Flow Hub
   | (collect all projects status_digest)
   | generate global report
   | emit event(global_report_ready) -> AX Coder
```

## 4) Lifecycle States (minimal)
Resident Butler:
- IDLE -> SUMMARIZE -> UPDATE_MEMORY -> IDLE
- IDLE -> SPAWN_WORKER -> SYNTHESIZE -> IDLE

Worker:
- SPAWNED -> RUNNING -> DONE -> RELEASED

## 5) Key Payload Fields (minimal)

### list_models
```json
{ "roles": ["resident", "coder", "reviewer", "advisor", "global_butler"] }
```

### chat
```json
{
  "project_id": "hash",
  "role": "coder",
  "model_id": "optional_override",
  "messages": [{ "role": "user", "content": "..." }],
  "context": { "memory_ref": ".axcoder/AX_MEMORY.md" }
}
```

### agent_spawn
```json
{
  "project_id": "hash",
  "role": "reviewer",
  "model_id": "paid_x",
  "ttl_ms": 1800000
}
```

### agent_release
```json
{ "agent_id": "uuid" }
```

### schedule_report
```json
{
  "daily_times": ["08:00", "20:00"],
  "quiet_hours": { "start": "23:00", "end": "08:00" }
}
```

### project_sync
```json
{
  "project_id": "hash",
  "status_digest": "short summary",
  "last_event_at": "2026-02-05T10:30:00Z"
}
```

### need_network / web_fetch
```json
{
  "reason": "need docs",
  "url": "https://example.com",
  "method": "GET",
  "headers": {},
  "max_bytes": 2000000
}
```

## 6) Event Types (minimal)
- `agent_status`
- `report_ready`
- `global_report_ready`
- `network_error`
- `project_changed`

## 7) Notes
- Timestamps use ISO-8601 in UTC ("Z").
- Hub is the only provider with model access and outbound network capability.
- Quiet hours suppress push delivery; events are queued and merged on resume.

## 8) project_sync (optional)
AX Coder can send `project_sync` to Hub to keep a centralized project registry:
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
