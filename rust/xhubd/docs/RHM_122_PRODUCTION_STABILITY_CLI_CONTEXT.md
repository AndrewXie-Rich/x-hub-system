# RHM-122 Production Stability CLI Context

## Goal

Keep production live stability status output accurate during package migration
and recovery, even before the current package has local session state.

Before this slice, `--status` and failed `--adopt` output could fall back to the
default Group Container path when no local state was present. That made a live
session using `/Users/andrew.xie/RELFlowHub` look disconnected unless the
package had already adopted the active session.

## Behavior

`tools/production_live_stability_session.command` now preserves the active CLI
context in status output:

- `--http-base-url` is used as the fallback HTTP base URL when state and process
  discovery do not provide one.
- `--live-base-dir` is used as the fallback live base dir when state and process
  discovery do not provide one.
- Existing state and discovered process metadata still win over CLI fallback,
  so adopted or active sessions continue to report their real runtime settings.

## Authority

This is read-only observability hardening:

- no `hub_status.json` write;
- no provider/model authority change;
- no scheduler authority change;
- no Rust memory writer authority;
- no Rust skills execution authority;
- no product UI change.

## Validation

- `node --check tools/production_live_stability_session.js`
- isolated no-state status with explicit `--http-base-url`
- isolated no-state status with explicit `--live-base-dir`
- packaged active session and rolling checkpoint adoption
- packaged UI compatibility gate
