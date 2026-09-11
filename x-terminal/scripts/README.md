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

## Execution Safety Regression

```bash
bash x-terminal/scripts/ci/xt_execution_safety_regression.sh
```

This checks the real process capture, shell session, local sandbox, and path-policy sources using temporary fixtures. It includes actual Seatbelt file/network denial tests and fails if sandbox enforcement cannot start. It does not require Swift Testing, does not replace the full release gate, and does not install or launch the app. The temporary compiler output directory is retained for diagnosis; the test's data fixtures are removed on completion.

The same script also runs `ManagedProcessSafetyRegression` against the actual managed-process store: group cleanup, restart fencing, bounded log rotation, and persisted-PID ownership checks. These checks are also available in Swift Testing via `swift test --package-path x-terminal --filter ProcessCaptureTests/managedProcessLifecycleAndLogSafetyContract`.

The release gate runs this script as a required check, including in baseline mode. OS sandbox failures remain failures. It also validates the product-readiness backlog against its Markdown authority and rejects dependency cycles:

```bash
node --test x-terminal/Tests/ProductReadinessBacklogTests.mjs
node x-terminal/scripts/check_product_readiness_backlog.mjs
```

Full `swift test` requires a toolchain that includes Swift Testing. A Command Line Tools installation can build the application while lacking `Testing`; this is not a passing test run. Select a compatible full Xcode toolchain explicitly with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` when installed, or run full tests on a CI host with that toolchain. The standalone script does not replace the full suite or live Hub/model acceptance.

## R1 First Real Task Bootstrap

The R1 entrypoints currently implement isolated golden-project preparation and
fail-closed evidence collection. They do **not** implement the live pairing,
model, project creation, governed mutation, checkpoint/resume, review, or fault
injection drivers yet. Merely supplying app bundles cannot unlock those phases.

Use a new, empty, private temporary directory for each source snapshot. The
runner accepts report directories beneath the run root or beneath the canonical
`build/reports/xt-v1-product-readiness/` directory, and refuses existing foreign
reports. From the repository root:

```bash
xt_r1_run_root="$(mktemp -d /tmp/xt-r1-run.XXXXXX)"
bash x-terminal/scripts/ci/xt_r1_first_real_task_gate.sh \
  --phase all --run-root "$xt_r1_run_root" --self-test
```

The default driver uses real `swift test` with Swift Testing. If that module is
not installed, the report is blocked with `swift_test_toolchain_unavailable`.
The explicit `--test-driver standalone` option runs the same two acceptance
conditions through `swift run GoldenProjectTests` as **contract diagnostics
only**. There is no automatic fallback, and it cannot satisfy the standard
Swift test or live-readiness requirements. `--self-test` repairs only a separate
authoring copy, verifies green, and deletes that copy; the formal project stays
red. Its package does not contain the expected-outcome file. Compiler caches
and the formal disposable repository are retained under the private run root.

Both entrypoints use the same manifest and IDs. Reusing a prepared run verifies
the actual project files, Git tree, artifact SHA-256, report owner, and source
snapshot, including staged and untracked files. Source edits require a new run.
Reports are immutable per attempt under `reports/attempts/`; the report root
contains the latest projections. Checkpoint and resume have separate artifacts.
Raw command output is not exported; reports contain result summaries and output
hashes. Unknown negative-case measurements stay `null`, never fabricated zeros.

Exit `1` means a failed check. Exit `2` means blocked/insufficient evidence or
invalid input. This bootstrap cannot emit release `GO`; even a verified red/green
fixture is not a completed R1 work order while the R0/live requirements are
unverified. The prior baseline release gate remains a separate contract gate.

The read-only R1 runtime preflight records canonical app hashes, verifies the
X-Terminal source-to-binary provenance written by the build, and probes only
the unauthenticated pairing discovery endpoint. It never starts or stops an
application and never reads credentials. A successful discovery probe is not a
pairing result: owner approval, first pairing, cached reconnect, and route
repair remain blocked until their live driver exists.

```bash
xt_r1_profile="$(mktemp -d /tmp/xt-r1-profile.XXXXXX)"
chmod 700 "$xt_r1_profile"
bash x-terminal/scripts/ci/xt_r1_runtime_preflight.sh \
  --profile-root "$xt_r1_profile" \
  --report "$PWD/build/reports/xt-v1-product-readiness/r1-runtime-preflight.v1.json"
```

The build writes `xterminal-build-provenance.v1.json` into the app bundle. The
manifest binds the executable hash to the exact source-tree fingerprint used
for the build; it contains no source text or secrets.

```bash
node --test x-terminal/Tests/R1FirstRealTaskTests.mjs
node --test x-terminal/Tests/R1RuntimePreflightTests.mjs
bash x-terminal/scripts/ci/xt_r1_golden_project_prepare.sh --help
```

## Route Truth Isolation Check

Use this when the working tree is noisy and `swift test` is getting interrupted by external file writes:

```bash
bash x-terminal/scripts/ci/xt_route_truth_snapshot_check.sh
```

The script copies `x-terminal/` into a `/tmp` snapshot, reuses one SwiftPM scratch path, and runs the targeted route-truth suites there.

## Boundary

Keep repo-wide release reporting and cross-module packaging scripts in the top-level `scripts/` directory. Use this directory for terminal-scoped validation only.
