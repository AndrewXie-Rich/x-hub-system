# X-Terminal Scripts

`x-terminal/scripts/` contains terminal-local gates, probes, fixtures, and support utilities.

These scripts exist to validate the terminal surface, not to replace Hub-side trust logic.

## Main Areas

- `ci/`: release gates, smoke checks, and CI-facing entrypoints
- `fixtures/`: sample inputs, contract fixtures, and probe support data

## Most Important Entry Point

```bash
bash x-terminal/scripts/ci/xt_release_gate.sh
```

That gate's `XT-G4 / Reliability` slice now exercises terminal-local route, grant, and Supervisor voice-call smoke paths together.

## Route Truth Isolation Check

Use this when the working tree is noisy and `swift test` is getting interrupted by external file writes:

```bash
bash x-terminal/scripts/ci/xt_route_truth_snapshot_check.sh
```

The script copies `x-terminal/` into a `/tmp` snapshot, reuses one SwiftPM scratch path, and runs the targeted route-truth suites there.

## Boundary

Keep repo-wide release reporting and cross-module packaging scripts in the top-level `scripts/` directory. Use this directory for terminal-scoped validation only.
