# RHM-120 Rolling Checkpoint Sidecar Adoption

## Goal

Make package updates smoother while a rolling production checkpoint sidecar is
already running.

RHM-118 made the long production stability session adoptable from a newer
package. This slice applies the same package-root handoff behavior to
`--checkpoint-loop-worker`, so a new dist can manage an active sidecar that was
started by an older dist.

## Change

- `tools/production_live_stability_session.command --adopt-checkpoint-loop`
  writes current-package state for an active checkpoint loop process discovered
  in another package root.
- `--checkpoint-loop-status` reports:
  - current package root;
  - active managed root;
  - original process root;
  - whether the active sidecar is managed by the current package root.
- `--stop-checkpoint-loop` can stop a discovered sidecar even when local state
  is missing.
- `--start-checkpoint-loop` refuses to create duplicate sidecars when one is
  discovered in another package root. `--start-checkpoint-loop --replace`
  intentionally stops the discovered process first.

## Safety

This is ops state management only. It does not restart `xhubd`, change
production authority, write memory, execute skills, touch SwiftUI files, or
change product UI.

`--checkpoint-loop-status` remains read-only. `--adopt-checkpoint-loop` only
writes the current package's checkpoint loop state file.

## Verification

Source gates:

```bash
node --check tools/production_live_stability_session.js
bash tools/production_live_stability_session.command --checkpoint-loop-status
```

Packaged live gates:

```bash
bash dist/<latest>/tools/production_live_stability_session.command \
  --adopt-checkpoint-loop

bash dist/<latest>/tools/production_live_stability_session.command \
  --checkpoint-loop-status
```
