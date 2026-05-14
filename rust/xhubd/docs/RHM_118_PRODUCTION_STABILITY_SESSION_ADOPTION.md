# RHM-118 Production Stability Session Adoption

## Goal

Make post-cutover package updates smoother while a long production stability
session is already running.

Before this slice, a new package could discover a long-running
`production_live_stability_gate.js` process from an older package root, but it
did not write local state for that process. That made status readable but left
stop/replace behavior tied to whichever dist directory originally launched the
session.

## Change

- `tools/production_live_stability_session.command --adopt` now writes a local
  `session_state.json` for an active stability gate process discovered in
  another package root.
- `--status` reports:
  - the current package root;
  - the active managed root;
  - the original package root when the process was adopted;
  - whether the active session is managed by the current package root.
- `--stop` can stop a discovered active session even when local state is
  missing.
- `--start` now refuses to create a duplicate long stability session when an
  active session is discovered in another package root. `--start --replace`
  can intentionally stop the discovered process first.

## Safety

This is an ops-management change only. It does not restart `xhubd`, change
provider/model/scheduler authority, write memory, execute skills, touch SwiftUI
files, or change product UI.

The command is explicit. `--status` remains read-only. `--adopt` only writes the
current package's session state file so future package-local `--status`,
`--stop`, and `--start --replace` behavior is deterministic.

## Verification

Source gates:

```bash
node --check tools/production_live_stability_session.js
bash tools/production_live_stability_session.command --status
```

Packaged live gate:

```bash
bash dist/<latest>/tools/production_live_stability_session.command --adopt
bash dist/<latest>/tools/production_live_stability_session.command --status
```
