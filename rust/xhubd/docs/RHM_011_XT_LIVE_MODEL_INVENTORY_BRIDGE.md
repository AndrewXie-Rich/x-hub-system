# RHM-011 XT Live Model Inventory Bridge

Status: implemented as default-off bridge on 2026-05-05.

This bridge lets XT consume Rust `xhub.model_inventory.v1` live inventory without
moving production routing authority. It is only a visible inventory/truth
presentation source until separate real-traffic evidence gates pass.

## Default-Off Switches

XT bridge enablement:

```bash
export XHUB_RUST_MODEL_INVENTORY_BRIDGE=1
```

Equivalent XT defaults key:

- `xterminal_rust_model_inventory_bridge_enabled`

At least one source must also be configured:

```bash
export XHUB_RUST_MODEL_INVENTORY_SNAPSHOT_PATH=/path/to/inventory.json
export XHUB_RUST_MODEL_INVENTORY_HTTP_BASE_URL=http://127.0.0.1:50151
```

Equivalent XT defaults keys:

- `xterminal_rust_model_inventory_snapshot_path`
- `xterminal_rust_model_inventory_http_base_url`

## Rust HTTP Surface

`xhubd serve` exposes:

- `GET /model/inventory?runtime_base_dir=<path>&now_ms=<ms>`
- `POST /model/compare`
- `GET /model/reports?limit=<n>`
- `GET /model/readiness?min_compare_reports=<n>&max_mismatches=<n>&limit=<n>`

The HTTP surface mirrors the existing `xhubd model ...` CLI commands. It is
read-only for inventory and evidence-gated for readiness.

## Fail-Closed Rules

XT must not mark Rust inventory as ready when any of these occurs:

- bridge switch is disabled
- no snapshot path or HTTP base URL is configured
- snapshot file cannot be read
- HTTP request fails or returns non-2xx
- schema is not `xhub.model_inventory.v1`
- raw inventory JSON contains likely secret material such as `api_key`,
  `refresh_token`, `password`, or `sk-`
- projected model fields contain likely secret material

When the bridge is unavailable, XT falls back to the existing model inventory
path. It does not treat the Rust bridge itself as authoritative.

## XT Consumption Boundary

XT still consumes only fields listed in
`docs/RHM_010_XT_MODEL_INVENTORY_FIELDS.md`.

`HubModelManager.fetchModels()` can use the Rust projection when explicitly
enabled. Model settings, model selector, project settings, and supervisor
settings truth cards prefer the Rust projection so quota, scope, runtime, and
capability blockers remain visible.

The bridge does not read:

- Codex auth files
- provider token stores
- provider passwords
- API keys
- refresh tokens

The bridge does not change:

- `HubAI.Generate` routing
- provider key selection authority
- local runtime execution
- Node Hub production catalog authority

## Validation

```bash
bash "tools/model_inventory_http_bridge_smoke.command"
swift test --filter 'XTRustModelInventoryLiveBridgeTests|HubModelManagerFetchTests|XTRustModelInventoryProjectionTests'
```
