# RHM-131 XT File IPC Live Base Discovery

RHM-131 hardens the XT file IPC live heartbeat verifier after production
cutover.

## Problem

The heartbeat soak defaulted to the historical Group Container path. The live
production session can point to a different non-temp base dir, currently
`/Users/andrew.xie/RELFlowHub`. When the old Group Container status file is
stale, using the historical default creates a false heartbeat failure even
though the actual Rust-owned live status is fresh.

## Change

`tools/xt_file_ipc_live_heartbeat_soak.command` now discovers the live base dir
from `GET /xt/classic-hub-compat` when `--live-base-dir` is not supplied.

Discovery order:

- `status_writer.planned_base_dir`
- `xt_contract.active_classic_hub.base_dir`
- `xt_contract.active_classic_hub.base_dir_from_status`
- parent of the planned or preferred status path

If discovery fails, the tool falls back to the historical Group Container path
and reports `live_base_dir_source=fallback_group_container`.

## Verification

Live verification without `--live-base-dir` now resolves to the active
production path and passes the heartbeat soak with memory/skills Rust authority
required.
