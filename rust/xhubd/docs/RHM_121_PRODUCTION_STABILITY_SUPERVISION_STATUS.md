# RHM-121 Production Stability Supervision Status

## Goal

Expose one read-only command that reports both layers of post-cutover
supervision:

- the long production live stability session;
- the rolling checkpoint sidecar.

Before this slice, operators had to call `--status` and
`--checkpoint-loop-status` separately, then manually combine whether the live
heartbeat, checkpoint cadence, slow-request budget, and authority guards were
still healthy.

## Command

```bash
bash tools/production_live_stability_session.command --supervision-status
```

The command returns schema
`xhub.rust_hub.production_live_stability_supervision_status.v1`.

## Contract

- Read-only.
- Does not write `hub_status.json`.
- Does not adopt, start, stop, or replace any process.
- Does not change provider/model, scheduler, memory writer, skills execution,
  or UI authority.
- Embeds the existing `--status` and `--checkpoint-loop-status` payloads so
  callers can inspect full detail when the compact fields are not enough.

## Summary Fields

- `supervision_ready`
- `long_session_running`
- `long_session_pid`
- `long_session_remaining_ms`
- `live_status_fresh`
- `heartbeat_child_running`
- `checkpoint_loop_running`
- `checkpoint_loop_pid`
- `checkpoint_loop_next_checkpoint_at_iso`
- `latest_checkpoint_ok`
- `slow_request_delta_budget_ok`
- `issues`
- `warnings`

`issues` covers missing long session, stale live status, missing checkpoint
loop, failed checkpoint report, Rust memory writer authority, Rust skills
execution authority, UI product drift, and secret leak. Missing heartbeat child
is a warning because the top-level gate can briefly move past the heartbeat
child into its final checks.

## Validation

- `node --check tools/production_live_stability_session.js`
- `tools/production_live_stability_session.command --supervision-status`
- packaged `tools/production_live_stability_session.command --supervision-status`

