# RHM-108 XT Live Status Write Lock And Nonblocking Repair

## Goal

Remove the post-cutover 5 second request stalls observed during the live
heartbeat soak after RHM-107.

The stale-status false negative was fixed, but rare samples showed
`/xt/classic-hub-compat` or `/ready` spending about 5 seconds while refreshing
Rust-owned live status evidence. That made the diagnostic route itself a
source of UI-visible stutter risk.

## Change

- `hub_status.json` writes now use a process-local write lock.
- Temporary status files now include a monotonic per-process sequence suffix,
  so concurrent heartbeat/write attempts cannot collide on the same temp path
  when they land in the same millisecond.
- Request-path stale Rust-owned status repair is now read-only and
  nonblocking: the request returns a fresh in-memory Rust-owned live status
  overlay instead of writing `hub_status.json` itself.
- RHM-117 later supersedes this request-path overlay for explicit live cutover:
  stale or missing Rust-owned status is now repaired by a gated fast disk write
  so the durable XT heartbeat evidence cannot stay stale while HTTP appears
  ready.
- Heartbeat writes are also remembered in a process-local live status cache, so
  `/ready` and `/xt/classic-hub-compat` do not need to read the live status file
  on every request under explicit production cutover.
- The background heartbeat remains the durable file writer for the live
  `hub_status.json`.
- The production session heartbeat interval was reduced to `250ms` in this
  slice. RHM-109 later uses `1000ms` with the same bounded lease to reduce live
  Group Container write pressure.
- Heartbeat status now carries a bounded `2000ms` lease in `updatedAt` and
  `rustHub.status_lease_ms`, absorbing short macOS background scheduling gaps
  without making the status file appear permanently fresh.
- Live Group Container writes still prefer temporary file plus atomic rename.
  If macOS denies creating the temporary file in the Group Container, the
  writer can fall back to a locked in-place overwrite of an existing
  Rust-owned `hub_status.json` instead of dropping the heartbeat.
- The live heartbeat soak tool now reports memory writer or skills execution
  authority changes only when `/ready` returned a body that explicitly shows
  those authorities became true.

## Safety

This does not change SwiftUI/UI files. It does not enable Rust memory writer
authority or Rust skills execution authority. It does not execute ML or
third-party skills. It only hardens the already-authorized Rust-owned
`hub_status.json` heartbeat path under explicit XT live cutover gates.

## Verification

Source gates:

```bash
cargo fmt
node --check tools/xt_file_ipc_live_heartbeat_soak.js
cargo test -p xhubd xt_compat
cargo test -p xhubd http_metrics
cargo test -p xhubd
```

Live gates after packaging and active-root upgrade:

```bash
bash dist/<latest>/tools/xt_file_ipc_live_heartbeat_soak.command \
  --duration-ms 120000 \
  --interval-ms 2000 \
  --max-status-age-ms 5000

bash dist/<latest>/tools/daemon_ops_gate.command --max-slow-requests 0
```
