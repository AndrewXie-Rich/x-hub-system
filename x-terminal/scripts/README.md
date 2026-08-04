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

## Release-Grade Gate

`XT_GATE_MODE=strict` and `XT_GATE_RELEASE_PRESET=1` both enable the mandatory
release-grade Swift sequence:

1. compile the `XTerminalTests` target with `swift build --build-tests`;
2. run the Hub-path, skills-isolation, and Supervisor guard/voice shards;
3. run an unfiltered `swift test` and require exit code `0`.

Any enabled environment variable whose name starts with `XT_GATE_SKIP_` is a
hard configuration error in either release-grade form. Baseline development
mode retains the existing opt-in skip behavior.

The sequence writes `xt-strict-test-evidence.json` beside the normal gate
report. It records the repository commit, dirty state, separate `Sources/` and
`Tests/` SHA-256 values, a combined hash before and after testing, and every
mandatory command with its log path and exit code.

The explicit release preset additionally requires the canonical runtime report
at `.axcoder/reports/xt_unified_doctor_report.json`. Its embedded generation
time must be no older than 15 minutes, `readyForFirstTask` must be `true`, and
the report must contain zero blocking sections. The age can only be tightened
with `XT_GATE_UNIFIED_DOCTOR_MAX_AGE_SECONDS` (range `1...900`). A strict
development gate without the release preset does not require this live report.

Run the fast shell/fixture regression without compiling Swift:

```bash
bash x-terminal/scripts/ci/tests/xt_release_gate_regression.sh
```

## Route Truth Isolation Check

Use this when the working tree is noisy and `swift test` is getting interrupted by external file writes:

```bash
bash x-terminal/scripts/ci/xt_route_truth_snapshot_check.sh
```

The script copies `x-terminal/` into a `/tmp` snapshot, reuses one SwiftPM scratch path, and runs the targeted route-truth suites there.

## Boundary

Keep repo-wide release reporting and cross-module packaging scripts in the top-level `scripts/` directory. Use this directory for terminal-scoped validation only.
