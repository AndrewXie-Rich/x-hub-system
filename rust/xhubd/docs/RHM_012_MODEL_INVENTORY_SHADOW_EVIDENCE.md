# RHM-012 Model Inventory Shadow Evidence Runner

Status: implemented 2026-05-05

## Goal

Collect sustained model inventory parity evidence before any production
authority switch. This is a default-off evidence path. It does not change model
routing, provider selection, XT model loading authority, or paid/local runtime
execution.

## Runner

`tools/model_inventory_shadow_compare_runner.js` starts an isolated Rust
`xhubd serve` process, writes a temporary runtime fixture, reads Node Hub helper
views, compares Node/XT-style inventory against Rust HTTP inventory, and gates
readiness through Rust compare reports.

Command:

```bash
bash "tools/model_inventory_shadow_compare_runner.command" \
  --runs 3 \
  --min-compare-reports 3 \
  --expect-ready \
  --expect-zero-mismatch
```

Useful flags:

- `--runs <n>`: number of compare iterations.
- `--interval-ms <n>`: delay between iterations.
- `--use-existing-runtime`: read an existing runtime dir instead of writing
  fixture files.
- `--runtime-base-dir <path>`: runtime dir for existing-runtime evidence.
- `--no-start --http-base-url <url>`: use an already warm Rust daemon.
- `--min-compare-reports <n>`: readiness evidence threshold.
- `--max-mismatches <n>`: allowed mismatch threshold.
- `--expect-ready`: fail unless `/model/readiness` returns ready.
- `--expect-zero-mismatch`: fail if newly added reports include mismatches.
- `--continue-after-ready`: keep collecting after readiness is reached.
- `--self-test`: parser and transform self-test without starting `xhubd`.

## Evidence Chain

The runner uses a temporary runtime base dir and SQLite DB. It writes:

- `hub_provider_keys.json` with one ready free OpenAI account and one quota
  cooldown OpenAI account.
- `models_state.json` with one local MLX model.
- `ai_runtime_status.json` with a ready MLX runtime status.

Then every iteration:

1. Calls Rust `GET /model/inventory`.
2. Uses Node Hub `runtimeModelsSnapshot()` to verify the local model view.
3. Uses Node Hub `listProviderKeyPools(..., include_members: false)` and
   `providerKeyStoreSummary()` to verify secret-free provider pool summaries.
4. Builds a Node/XT-shaped inventory with camelCase fields, provider/model case
   differences, capability spelling differences, and reversed row order.
5. Calls Rust `POST /model/compare`.
6. Reads `GET /model/reports`.
7. Reads `GET /model/readiness`.

This proves the Rust normalizer accepts the presentation differences XT and
Node expose while preserving blocker truth such as quota cooldown,
availability, retry timestamps, runtime preflight, and local capabilities.

## Fail-Closed Rules

The runner fails when:

- Rust inventory has an unexpected schema.
- Node runtime helper cannot see the local model.
- Node provider pool helpers cannot summarize provider accounts.
- Any inventory, helper evidence, or compare response leaks fixture secret
  markers, `api_key`, or `refresh_token`.
- Compare reports include more mismatches than the configured threshold.
- `--expect-ready` is set and readiness stays false.

## Warm Daemon Env

`tools/xhubd_daemon.js env` now prints the XT model inventory bridge variables:

```bash
export XHUB_RUST_MODEL_INVENTORY_BRIDGE=1
export XHUB_RUST_MODEL_INVENTORY_HTTP_BASE_URL=http://127.0.0.1:<port>
```

These variables only opt XT into reading Rust model inventory truth. Production
route authority remains unchanged.
