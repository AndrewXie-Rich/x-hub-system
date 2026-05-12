# Scheduler Bridge CLI

The bridge CLI is the first stable handoff surface for Node Hub shadow
integration. It writes only to the Rust Hub SQLite DB and does not make Rust Hub
production authority.

All commands return one JSON object:

```bash
bash tools/run_rust_hub.command scheduler status --include-queue-items
```

## Commands

Enqueue:

```bash
bash tools/run_rust_hub.command scheduler enqueue \
  --request-id req-1 \
  --scope-key project:demo \
  --idempotency-key req-1 \
  --task-type paid_ai \
  --priority 0 \
  --payload-json '{"source":"node-shadow"}'
```

Claim:

```bash
bash tools/run_rust_hub.command scheduler claim \
  --request-id req-1 \
  --scope-key project:demo \
  --idempotency-key req-1 \
  --task-type paid_ai \
  --priority 0 \
  --lease-owner node-authority-worker \
  --lease-duration-ms 300000 \
  --payload-json '{"source":"node-authority"}'
```

`claim` is the authority-switch handoff primitive. It performs idempotent
enqueue and a fair lease attempt in one Rust transaction. It returns
`leased=true` only when the request is the next fair candidate and capacity is
available; otherwise it returns `leased=false` and leaves the run queued. This
avoids Node composing multiple bridge commands on the hot path.

Acquire:

```bash
bash tools/run_rust_hub.command scheduler acquire \
  --lease-owner node-shadow-worker \
  --lease-duration-ms 30000
```

Acquire exact run:

```bash
bash tools/run_rust_hub.command scheduler acquire-run \
  --run-id <run_id> \
  --lease-owner node-shadow-worker \
  --lease-duration-ms 30000
```

`acquire-run` is intended for Node shadow mirroring. It leases the specific run
that Node already selected, avoiding drift from an independent `acquire next`
ordering decision.

Heartbeat:

```bash
bash tools/run_rust_hub.command scheduler heartbeat \
  --run-id <run_id> \
  --lease-token <lease_token> \
  --lease-duration-ms 30000
```

Release:

```bash
bash tools/run_rust_hub.command scheduler release \
  --run-id <run_id> \
  --lease-token <lease_token> \
  --outcome completed
```

Cancel:

```bash
bash tools/run_rust_hub.command scheduler cancel \
  --run-id <run_id> \
  --reason operator_cancel
```

Status:

```bash
bash tools/run_rust_hub.command scheduler status \
  --include-queue-items \
  --queue-items-limit 50
```

Shadow compare:

```bash
bash tools/run_rust_hub.command scheduler compare \
  --node-in-flight-total 0 \
  --node-queue-depth 0 \
  --node-oldest-queued-ms 0
```

`compare` writes an append-only row to `rust_hub_shadow_compare_reports`. A
production switch should require sustained `match_result=match` evidence on real
traffic.

Reports:

```bash
bash tools/run_rust_hub.command scheduler reports \
  --component scheduler \
  --limit 20
```

`reports` summarizes recent `rust_hub_shadow_compare_reports` rows with total,
matched, mismatched, latest timestamp, and recent mismatch details.

Lease shadow evidence:

```bash
bash tools/run_rust_hub.command scheduler lease-shadow-report \
  --run-id-prefix node_paid_ai_ \
  --stale-after-ms 300000 \
  --limit 20
```

`lease-shadow-report` summarizes Node paid AI lifecycle mirroring from Rust
scheduler truth tables. It reports run totals by status, event counts, stale
active runs, orphaned leases, and recent mirrored runs. This command does not
write evidence; it reads existing `rust_hub_run_queue`,
`rust_hub_run_leases`, and `rust_hub_scheduler_events` rows created by the
lease shadow bridge.

Cutover readiness:

```bash
bash tools/run_rust_hub.command scheduler cutover-readiness \
  --min-compare-reports 10 \
  --max-mismatches 0 \
  --min-lease-shadow-runs 1 \
  --max-stale-active 0 \
  --max-orphaned-leases 0
```

`cutover-readiness` is fail-closed. The command returns `ok=true` when the
report was generated, but cutover is allowed only when `ready=true`. Default
checks require enough scheduler compare reports, zero mismatches, at least one
lease shadow run, zero stale active mirrored runs, zero orphaned leases, and no
currently active mirrored runs. Use `--allow-active-runs` only for controlled
tests, not production cutover.

Daemon HTTP form:

```bash
XHUB_RUST_HUB_HTTP_PORT=50151 HUB_DB_PATH=/path/to/hub.sqlite3 bash tools/run_rust_hub.command serve
curl -fsS "http://127.0.0.1:50151/scheduler/status?include_queue_items=1&queue_items_limit=50"
curl -fsS "http://127.0.0.1:50151/scheduler/cutover-readiness?min_compare_reports=0&max_mismatches=0&min_lease_shadow_runs=0&max_stale_active=0&max_orphaned_leases=0"
curl -fsS -X POST "http://127.0.0.1:50151/scheduler/claim" -H "content-type: application/json" --data '{"run_id":"node_paid_ai_authority_demo","request_id":"demo","scope_key":"project:demo","idempotency_key":"demo","task_type":"paid_ai","lease_owner":"node-authority-demo","lease_duration_ms":60000,"payload":{}}'
```

`GET /scheduler/status`, `GET /scheduler/cutover-readiness`,
`POST /scheduler/claim`, `POST /scheduler/acquire-run`,
`POST /scheduler/release`, and `POST /scheduler/cancel` return the same
`xhub.scheduler_bridge.v1` envelopes as their CLI equivalents. These endpoints
are useful for UI polling and paid-AI scheduler authority because Node can reuse
a warm `xhubd serve` process instead of spawning a Rust CLI process.

Node HTTP bridge smoke:

```bash
bash tools/scheduler_status_http_bridge_smoke.command
bash tools/scheduler_lease_shadow_http_bridge_smoke.command
bash tools/scheduler_authority_http_bridge_smoke.command
```

## Node Shadow Caller

`tools/node_scheduler_shadow_compare.js` is the Node-side caller prototype. It
normalizes Node scheduler snapshot shapes and invokes:

```bash
bash tools/run_rust_hub.command scheduler compare ...
```

Direct flags:

```bash
node tools/node_scheduler_shadow_compare.js \
  --node-in-flight-total 0 \
  --node-queue-depth 0 \
  --node-oldest-queued-ms 0
```

Snapshot JSON:

```bash
node tools/node_scheduler_shadow_compare.js \
  --snapshot-json '{"paid_ai":{"in_flight_total":0,"queue_depth":0,"oldest_queued_ms":0}}'
```

Stdin:

```bash
printf '%s\n' '{"paidAI":{"inFlightTotal":0,"queueDepth":0}}' \
  | node tools/node_scheduler_shadow_compare.js --snapshot-file -
```

Self-test:

```bash
node tools/node_scheduler_shadow_compare.js --self-test
```
