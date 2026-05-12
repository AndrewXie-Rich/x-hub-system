# RHM-013 Real Runtime Model Inventory Evidence

Status: implemented 2026-05-06

## Goal

Run model inventory shadow evidence against an existing Hub runtime directory or
an already running warm Rust daemon. This keeps the RHM-012 fixture runner for
repeatable regression, while adding a no-fixture path for real-machine evidence.

This remains default-off and authority-neutral. It does not switch model route
authority, mutate provider accounts, refresh tokens, or call model providers.

## Modes

### Isolated Fixture Regression

Default mode writes a temporary provider/runtime fixture and starts an isolated
Rust daemon:

```bash
bash "tools/model_inventory_shadow_compare_runner.command" \
  --runs 3 \
  --min-compare-reports 3 \
  --expect-ready \
  --expect-zero-mismatch
```

### Existing Runtime Directory

This mode starts an isolated Rust daemon but reads a supplied runtime directory.
It does not write fixture files into that directory.

```bash
bash "tools/model_inventory_shadow_compare_runner.command" \
  --use-existing-runtime \
  --runtime-base-dir "/path/to/runtime_base_dir" \
  --runs 10 \
  --min-compare-reports 10 \
  --expect-ready \
  --expect-zero-mismatch
```

### Existing Warm Daemon

This mode uses a daemon already started by `tools/xhubd_daemon.command start` or
another `xhubd serve` process.

```bash
bash "tools/model_inventory_shadow_compare_runner.command" \
  --use-existing-runtime \
  --runtime-base-dir "/path/to/runtime_base_dir" \
  --no-start \
  --http-base-url "http://127.0.0.1:50151" \
  --runs 10 \
  --min-compare-reports 10 \
  --expect-ready \
  --expect-zero-mismatch
```

Environment equivalents:

- `HUB_RUNTIME_BASE_DIR` or `XHUB_MODEL_INVENTORY_RUNTIME_BASE_DIR`
- `XHUB_RUST_MODEL_INVENTORY_HTTP_BASE_URL`
- `HUB_DB_PATH` when starting an isolated Rust daemon with a specific DB

## Secret Boundary

The real-runtime path only calls secret-free surfaces:

- Rust `GET /model/inventory`
- Rust `POST /model/compare`
- Rust `GET /model/reports`
- Rust `GET /model/readiness`
- Node Hub `runtimeModelsSnapshot()`
- Node Hub `listProviderKeyPools(..., include_members: false)`
- Node Hub `providerKeyStoreSummary()`

The runner fails if serialized evidence contains fixture secret markers,
`api_key`, or `refresh_token`.

## Validation

Validated on 2026-05-06:

```bash
node tools/model_inventory_shadow_compare_runner.js --self-test
node tools/model_inventory_shadow_compare_runner.js --dry-run \
  --use-existing-runtime \
  --runtime-base-dir /tmp/xhub-real-runtime \
  --no-start \
  --http-base-url http://127.0.0.1:50151 \
  --runs 5 \
  --min-compare-reports 5
bash tools/model_inventory_shadow_compare_runner.command \
  --use-existing-runtime \
  --runtime-base-dir ./build/reports/lpr_w4_09_a_mlx_text_require_real/runtime_base_dir \
  --runs 2 \
  --min-compare-reports 2 \
  --expect-ready \
  --expect-zero-mismatch \
  --timeout-ms 30000
```

Observed result for the existing runtime short run:

- reports added: 2
- matched: 2
- mismatched: 0
- readiness: ready
- remote models: 0
- local models: 1
- Node runtime models: 1
