# RHM-117 XT Live Status On-Demand Disk Repair

## Goal

Close the last live cutover gap where `/ready` and
`/xt/classic-hub-compat` could return fresh Rust-owned live status from an
in-memory overlay while the durable `hub_status.json` file on disk stayed
stale.

That gap showed up during rolling production checkpoints as a single
`status_stale` heartbeat sample. The HTTP daemon was healthy and recent slow
request count stayed at zero, but the XT file heartbeat verifier correctly
failed because the live status file itself had not been refreshed.

## Change

- Request-path repair now writes the planned Rust-owned live status back to
  `hub_status.json` using the fast status writer.
- The repair remains gated by the same explicit live cutover controls:
  compatibility enabled, local scan enabled, status writer enabled, heartbeat
  enabled, apply enabled, rollback contract enabled, file IPC production
  surface ready, and production cutover authorized.
- When no live status file exists under an explicitly authorized live base dir,
  the repair creates it and stores it in the process-local live status cache.
- When an existing Rust-owned status file is stale, the repair refreshes the
  disk file and cache.
- When an active non-Rust classic status file is present, the preflight path
  reads it and does not overwrite it.
- If the disk write fails, the request no longer returns a fresh in-memory
  overlay. Callers see no fresh Rust-owned live status, so readiness and
  stability gates fail closed instead of hiding a disk write problem.

## Safety

This does not change SwiftUI or product UI files. It does not enable Rust
memory writer authority or Rust skills execution authority. It does not execute
ML or third-party skills.

The only new write is the already-authorized Rust-owned `hub_status.json`
repair under explicit XT live cutover gates. This intentionally supersedes the
RHM-108 read-only request-path overlay because live production authority must be
based on the durable status file, not only an in-memory view.

## Verification

Source gates:

```bash
cargo fmt
cargo test -p xhubd compat_get_live_cutover_writes_status_file_on_demand
cargo test -p xhubd compat_get_repairs_stale_rust_owned_live_status_with_fast_write
cargo test -p xhubd xt_compat
```

Production follow-up gates after packaging:

```bash
bash dist/<latest>/tools/production_live_stability_session.command --checkpoint \
  --live-base-dir /Users/andrew.xie/RELFlowHub

bash dist/<latest>/tools/production_live_stability_session.command \
  --start-checkpoint-loop --replace \
  --live-base-dir /Users/andrew.xie/RELFlowHub
```
