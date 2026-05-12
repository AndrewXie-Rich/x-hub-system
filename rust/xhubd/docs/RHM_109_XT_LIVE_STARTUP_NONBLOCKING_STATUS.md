# RHM-109 XT Live Startup Nonblocking Status

## Goal

Prevent live cutover startup from blocking `/ready` when macOS delays opening
`hub_status.json` inside the RELFlowHub Group Container.

## Change

- Under explicit XT live cutover gates, readiness and compat probes use the
  process-local Rust-owned live status overlay before opening or statting the
  live status file.
- The background heartbeat starts in trusted fast-refresh mode once the
  explicit live cutover gates are present, so it does not need a startup read of
  `hub_status.json`.
- The production heartbeat interval is `1000ms` with a bounded `2000ms` status
  lease, reducing Group Container write pressure while keeping status age inside
  the live heartbeat soak budget.
- Existing-file Group Container fallback writes flush process buffers but do
  not force `sync_data` on every heartbeat.
- The live heartbeat soak tool reads `hub_status.json` through a bounded child
  process, so a macOS Group Container file open delay cannot hang the verifier.

## Safety

This remains gated by explicit XT live cutover flags, rollback contract,
status-writer apply, and file IPC readiness. It does not modify SwiftUI/UI
files, does not enable Rust memory writer authority, and does not enable Rust
skills execution authority.

## Verification

```bash
cargo fmt
node --check tools/xt_file_ipc_production_session.js
node --check tools/xt_file_ipc_live_heartbeat_soak.js
cargo test -p xhubd xt_compat
cargo test -p xhubd
bash tools/ui_compatibility_no_product_ui_change_gate.command
```
