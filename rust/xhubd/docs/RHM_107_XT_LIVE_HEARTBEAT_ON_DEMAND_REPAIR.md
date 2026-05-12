# RHM-107 XT Live Heartbeat On-Demand Repair

## Goal

Remove the remaining short live-status freshness dip observed after
provider/model production authority cutover.

During a 120 second live heartbeat soak, one sampling cycle saw the Rust-owned
`hub_status.json` age pass the 5 second readiness threshold before the
background heartbeat refreshed it. The next cycle recovered automatically, but
the brief false negative made `/ready` and `/xt/classic-hub-compat` report the
XT production surface as not ready for that sample.

## Change

- `GET /ready` and `GET /xt/classic-hub-compat` now repair stale Rust-owned
  preferred `hub_status.json` evidence before declaring the XT live surface not
  ready.
- The repair path reuses the trusted heartbeat status shape and is allowed only
  when the explicit live cutover gates are already present:
  - classic compatibility enabled,
  - local status scan enabled,
  - status writer enabled,
  - status writer apply enabled,
  - heartbeat enabled,
  - rollback contract enabled,
  - file IPC surface ready,
  - production cutover authorized,
  - preferred status parent exists,
  - the existing status file is Rust-owned.
- Fresh Rust-owned status still uses the fast read-only path.
- Fresh non-Rust classic Hub status still blocks the bridge.
- The production session heartbeat interval is reduced from `1000ms` to
  `500ms` for the live cutover session.
- RHM-108 later made this request-path repair read-only and nonblocking so
  diagnostics cannot stall on durable file writes. RHM-109 then kept live
  cutover probes off direct Group Container status reads and settled the
  production heartbeat at `1000ms` with a bounded lease.

## Safety

This does not change SwiftUI/UI files. It does not enable Rust memory writer
authority or Rust skills execution authority. It does not execute ML or
third-party skills. The durable writer remains the already-authorized
Rust-owned `hub_status.json` heartbeat refresh under explicit live cutover
gates.

## Verification

Source gates:

```bash
cargo fmt
node --check tools/xt_file_ipc_production_session.js
node --check tools/xt_file_ipc_live_heartbeat_soak.js
cargo test -p xhubd xt_compat
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
