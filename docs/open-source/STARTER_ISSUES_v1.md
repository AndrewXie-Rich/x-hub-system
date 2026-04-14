# Starter Issues v1

This page is the initial public starter-issue pool for X-Hub-System.

The goal is not to describe every possible task. The goal is to keep a small
set of contribution candidates that:

- are understandable without reading every internal planning document
- have clear entrypoints
- are small enough for a first or second pull request
- do not require changing the core trust model

Use this page when turning contribution ideas into GitHub issues.

## Suggested Labels

Use some combination of:

- `good first issue`
- `help wanted`
- `docs`
- `tests`
- `runtime`
- `ui`
- `security`
- `diagnostics`

## Docs And Onramp

### Issue 1: Add a public "run from source" troubleshooting page

- Size: `S`
- Labels: `good first issue`, `docs`, `diagnostics`
- Why:
  new contributors can find the build commands, but the likely failure modes
  are still spread across multiple documents and runtime status files.
- Suggested entrypoints:
  - `README.md`
  - `CONTRIBUTING.md`
  - `docs/WORKING_INDEX.md`
  - `x-hub/macos/README.md`
  - `x-terminal/README.md`
- Acceptance criteria:
  - add one short doc that explains the first places to look when Hub or
    X-Terminal does not come up cleanly
  - mention the main runtime signal files without expanding public scope claims
  - link the page from an existing contributor-facing document

### Issue 2: Tighten module README cross-links for first-time contributors

- Size: `S`
- Labels: `good first issue`, `docs`
- Why:
  several module READMEs explain local details well, but contributor flow still
  depends on jumping back to top-level docs manually.
- Suggested entrypoints:
  - `x-hub/README.md`
  - `x-hub/grpc-server/README.md`
  - `x-hub/python-runtime/README.md`
  - `x-terminal/README.md`
  - `x-terminal/Sources/README.md`
- Acceptance criteria:
  - each active module README links back to the right top-level navigation docs
  - archived paths remain clearly marked as non-runtime history
  - no public claim expansion is introduced

### Issue 3: Publish a "how to choose your first PR" section in CONTRIBUTING

- Size: `S`
- Labels: `good first issue`, `docs`
- Why:
  this helps contributors self-select into docs, tests, diagnostics, or runtime
  work before they touch architecture-sensitive areas.
- Suggested entrypoints:
  - `CONTRIBUTING.md`
  - `docs/open-source/CONTRIBUTOR_START_HERE.md`
- Acceptance criteria:
  - contribution lanes are described in plain language
  - issue-first areas stay explicit
  - guidance stays aligned with the Hub-first boundary

## Tests And Gates

### Issue 4: Add regression tests for sandbox provider availability detection

- Size: `S`
- Labels: `good first issue`, `tests`, `runtime`
- Why:
  `SandboxProviderType.isAvailable` currently returns hardcoded `false` for
  Docker and Kubernetes availability, which makes it a clean starter target.
- Suggested entrypoints:
  - `x-terminal/Sources/Models/SandboxProvider.swift`
  - `x-terminal/Tests/`
- Acceptance criteria:
  - add tests covering availability detection behavior
  - document the expected behavior for environments without Docker or K8s
  - preserve fail-closed behavior when availability cannot be confirmed

### Issue 5: Add tests for monitored command execution fallback behavior

- Size: `S`
- Labels: `good first issue`, `tests`, `runtime`
- Why:
  `executeWithMonitoring` currently falls back to buffered execution and has an
  explicit TODO for real-time output monitoring.
- Suggested entrypoints:
  - `x-terminal/Sources/Models/LocalSandboxProvider.swift`
  - `x-terminal/Tests/`
- Acceptance criteria:
  - add tests for current fallback behavior
  - cover success and failure paths
  - make future real-time implementation easier to verify

### Issue 6: Add doc-to-test traceability for contributor-facing run commands

- Size: `S`
- Labels: `good first issue`, `tests`, `docs`
- Why:
  public entrypoints change over time, and drift between docs and test coverage
  is costly for new contributors.
- Suggested entrypoints:
  - `README.md`
  - `CONTRIBUTING.md`
  - `docs/WORKING_INDEX.md`
  - `.github/workflows/`
- Acceptance criteria:
  - identify the main public build/run/gate commands
  - add or extend an automated check that these command references stay current
  - avoid checking archived or generated paths as active entrypoints

## Runtime And Diagnostics

### Issue 7: Implement Docker availability detection in X-Terminal sandbox provider

- Size: `M`
- Labels: `help wanted`, `runtime`
- Why:
  Docker is already modeled as a sandbox provider type, but availability
  detection is not implemented yet.
- Suggested entrypoints:
  - `x-terminal/Sources/Models/SandboxProvider.swift`
  - `x-terminal/Tests/`
- Acceptance criteria:
  - detect whether Docker is actually available on the machine
  - fail closed when detection errors or times out
  - add focused tests for the detection logic

### Issue 8: Implement Kubernetes availability detection in X-Terminal sandbox provider

- Size: `M`
- Labels: `help wanted`, `runtime`
- Why:
  Kubernetes is already exposed as a provider type, but currently behaves as
  permanently unavailable.
- Suggested entrypoints:
  - `x-terminal/Sources/Models/SandboxProvider.swift`
  - `x-terminal/Tests/`
- Acceptance criteria:
  - define what "available" means for the current product surface
  - keep the implementation explicit and testable
  - do not imply K8s support beyond what runtime code can really do

### Issue 9: Implement real-time stdout/stderr monitoring for local sandbox execution

- Size: `M`
- Labels: `help wanted`, `runtime`, `diagnostics`
- Why:
  command execution monitoring currently buffers output and invokes the callback
  only after the command finishes.
- Suggested entrypoints:
  - `x-terminal/Sources/Models/LocalSandboxProvider.swift`
  - `x-terminal/Tests/`
- Acceptance criteria:
  - stream output incrementally to the callback
  - preserve timeout and error handling behavior
  - include tests for partial output and command completion

### Issue 10: Improve blocked-capability explanations in Hub diagnostics surfaces

- Size: `M`
- Labels: `help wanted`, `diagnostics`, `ui`
- Why:
  the project already exposes launch status and blocked capabilities, but
  contributor and operator comprehension can still improve.
- Suggested entrypoints:
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubLaunchStateMachine.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubDiagnosticsBundleExporter.swift`
- Acceptance criteria:
  - explanations are clearer without hiding fail-closed state
  - users can tell what is blocked and what to check next
  - diagnostics exports remain redacted where required

## Hub Service Reliability

### Issue 11: Add one focused operator-channel regression test for a fail-closed path

- Size: `S`
- Labels: `good first issue`, `tests`, `security`
- Why:
  operator-channel code already has good test coverage, but a single targeted
  regression issue is a good entrypoint for contributors who want to learn the
  Hub service without redesigning it.
- Suggested entrypoints:
  - `x-hub/grpc-server/hub_grpc_server/src/operator_channels_service_api.test.js`
  - `x-hub/grpc-server/hub_grpc_server/src/supervisor_channel_route_facade.test.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_command_gate.test.js`
- Acceptance criteria:
  - pick one concrete fail-closed behavior
  - express it as a regression test with a clear name
  - avoid changing the protocol or public claims

### Issue 12: Add one focused memory-route audit regression test

- Size: `S`
- Labels: `good first issue`, `tests`, `security`
- Why:
  memory routing and audit semantics are central to the architecture and already
  have test scaffolding that a contributor can extend safely.
- Suggested entrypoints:
  - `x-hub/grpc-server/hub_grpc_server/src/memory_trust_router.test.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_score_explain.test.js`
  - `x-hub/grpc-server/hub_grpc_server/src/memory_metrics_audit.test.js`
- Acceptance criteria:
  - add a small regression around routing, explainability, or audit output
  - keep the assertion scoped to existing runtime behavior
  - do not redefine who chooses the memory executor or imply a new durable memory authority outside `Writer + Gate`
  - document any assumptions in the test name or comments

## How To Use This Pool

Recommended flow:

1. Open 5 to 8 of these as public issues first, not all 12 at once.
2. Keep the first batch biased toward docs, tests, and diagnostics.
3. Add `good first issue` only when the task is genuinely scoped and has clear entrypoints.
4. When an issue is claimed, link the relevant files and acceptance criteria directly in the issue body.
5. When the pool changes, update this page so the public backlog stays curated instead of drifting into an unreviewed list.
