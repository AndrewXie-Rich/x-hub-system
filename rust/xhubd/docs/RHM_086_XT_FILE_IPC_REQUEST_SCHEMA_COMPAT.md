# RHM-086 XT File IPC Request Schema Compatibility

## Goal

Make Rust Hub's XT file IPC shadow responder understand and report the request
shape that XT actually writes, while keeping execution fail-closed.

This step is schema compatibility only. Rust still does not execute ML, does
not write `hub_status.json`, does not touch live XT directories, and does not
become production file IPC authority.

## XT Request Shape

XT writes `ai_requests/req_<req_id>.json` using `HubAIRequest`:

- `type`
- `req_id`
- `app_id`
- `task_type`
- `preferred_model_id`
- `model_id`
- `prompt`
- `max_tokens`
- `temperature`
- `top_p`
- `created_at`
- `auto_load`
- `provider_key`

Rust now normalizes those fields into the shadow response report under
`request`, including:

- explicit and preferred model IDs;
- selected `requested_model_id` / `actual_model_id` metadata;
- `model_id_source`;
- prompt length and generation parameters;
- provider key presence with secret fields redacted.

## Response Events

The shadow JSONL response still emits exactly two events:

1. `start`
2. `done`

Both events now include XT-visible metadata:

- `requested_model_id`
- `preferred_model_id`
- `actual_model_id`
- `app_id`
- `runtime_provider`
- `execution_path`
- `authority`

The `done` event remains fail-closed:

```json
{
  "type": "done",
  "ok": false,
  "reason": "rust_file_ipc_not_authoritative",
  "deny_code": "rust_file_ipc_not_authoritative"
}
```

Cancel files continue to use `rust_file_ipc_cancel_observed`.

## Secret Handling

`provider_key` is never echoed raw. The shadow report only records:

- whether a provider key is present;
- provider and auth type;
- whether base/proxy URLs are present;
- custom header count;
- booleans showing API key / refresh token were redacted.

The raw API key, refresh token, account identifiers, source refs, and custom
header values are not written to reports or response JSONL.

## Validation

Covered by `cargo test -p xhubd xt_file_ipc`:

- `request_contract_preserves_xt_schema_without_leaking_provider_secret`
- `apply_writes_fail_closed_jsonl_only_when_shadow_apply_gate_passes`

This keeps the next implementation step focused: route a compatible request to
a real runtime only after explicit runtime, rollback, and production cutover
gates exist.
