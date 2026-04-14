# Active Development Surfaces

This page organizes the active development files and code roots of the repository.

It is not trying to list every file line-by-line. Its purpose is to make the repository navigable again by separating active code surfaces from generated outputs, archived history, and report snapshots.

## Active-Only Rule

Treat these as active development roots:

- `x-hub/`
- `x-terminal/`
- `protocol/`
- `docs/`
- `official-agent-skills/`
- `scripts/`
- `specs/`
- `website/`

Treat these as non-source or non-entrypoint paths:

- `archive/`
- `build/`
- `data/`
- `**/node_modules/`
- `x-terminal/.axcoder/reports/**`
- `x-terminal/.ax-test-cache/`
- `x-terminal/skills/_projects/`
- `x-terminal/voice_supervisor_smoke_project/`
- `x-hub-system/`
- root stray markers: `Scheduler`, `Worker`, `Writer`

## Top-Level Active Roots

| Path | Role | Notes |
|---|---|---|
| `x-hub/` | Trusted Hub control plane | Trust, grants, policy, routing, audit, memory-backed constitutional boundaries, shared runtime services |
| `x-terminal/` | Active terminal surface | Interaction, session runtime, Supervisor, tools, doctor/readiness UX |
| `protocol/` | Shared contracts | Hub/XT contracts and protocol docs |
| `docs/` | Operating model and planning | Product boundary, capability matrix, work orders, specs, release docs |
| `official-agent-skills/` | Official skill source + distribution metadata | Skill roots, dist manifests, trusted publishers |
| `scripts/` | Repo-wide validation and reporting | Packaging, release evidence, dashboard builders, smoke helpers |
| `specs/` | Traceability / spec packs | Narrower than `docs/`, but still active |
| `website/` | Public site and public-facing content layer | Not runtime logic, but active product surface |

## Hub Active Roots

The active Hub surface is concentrated in four roots:

| Path | Role | Notes |
|---|---|---|
| `x-hub/macos/RELFlowHub/` | Native Hub app | Main Swift package for X-Hub desktop control plane |
| `x-hub/grpc-server/hub_grpc_server/` | Node service layer | Pairing, grants, RPCs, skills, audit, routing helpers |
| `x-hub/python-runtime/python_service/` | Python runtime integration | Local model/runtime adapters and supporting runtime processes |
| `x-hub/tools/` | Build/run entrypoints | Build app, source-run Hub, source-run bridge, support utilities |

Current hotspot counts from the active tree:

- `x-hub/grpc-server/hub_grpc_server/`: about `272` tracked source/docs/support files
- `x-hub/macos/RELFlowHub/`: about `210` tracked source/docs/support files
- `x-hub/python-runtime/python_service/`: about `20` tracked source files

## X-Terminal Active Roots

The active XT surface is concentrated in the following roots:

| Path | Role | Notes |
|---|---|---|
| `x-terminal/Sources/Supervisor/` | Orchestration + dashboard-heavy runtime layer | Largest XT source area; owns many runtime presentations and boards |
| `x-terminal/Sources/UI/` | UI surfaces and setup flows | Window-level UI, settings, dashboards, detail views |
| `x-terminal/Sources/Project/` | Project metadata, governance, route truth, skills compatibility | Important for project governance and memory-facing behavior |
| `x-terminal/Sources/Tools/` | Tool execution and summaries | Tool runtime and operator-facing output |
| `x-terminal/Sources/Voice/` | Voice runtime surfaces | TTS/STT-adjacent XT logic |
| `x-terminal/Sources/Hub/` | Hub clients, route truth, pairing | XT-side Hub access layer |
| `x-terminal/Sources/Session/` | Session lifecycle | Smaller than expected; session ownership is shared across other areas |
| `x-terminal/Tests/` | XT test suite | Many Supervisor and presentation tests live here |
| `x-terminal/scripts/` | XT-only gates and probes | XT release gate, focused checks, fixtures |
| `x-terminal/work-orders/` | XT execution packs | XT-only work-order entrypoint |
| `x-terminal/skills/` | XT-local skill assets | Active development-time skill surface |

Current XT source-root counts from `x-terminal/Sources/`:

- `Supervisor/`: `208` Swift files
- `UI/`: `97`
- `Project/`: `63`
- `Tools/`: `25`
- `Voice/`: `24`
- `Hub/`: `18`
- `LLM/`: `12`

## Dashboard And Board Surfaces

`dashboard` is not one file in this repository. It currently means three distinct surfaces.

### 1. Supervisor Operations Dashboard

This is the main XT runtime dashboard family.

Primary composition files:

- `x-terminal/Sources/Supervisor/SupervisorDashboardBoards.swift`
- `x-terminal/Sources/Supervisor/SupervisorOperationsDeck.swift`
- `x-terminal/Sources/Supervisor/SupervisorOperationsPanel.swift`
- `x-terminal/Sources/Supervisor/SupervisorViewContent.swift`
- `x-terminal/Sources/Supervisor/SupervisorViewRuntimePresentationSupport.swift`
- `x-terminal/Sources/Supervisor/SupervisorViewRuntimePresentationSupportBoards.swift`
- `x-terminal/Sources/Supervisor/SupervisorManager.swift`

Primary board sections:

- `x-terminal/Sources/UI/Supervisor/SupervisorHeartbeatFeedView.swift`
- `x-terminal/Sources/Supervisor/SupervisorRuntimeActivityBoardSection.swift`
- `x-terminal/Sources/Supervisor/SupervisorInfrastructureFeedBoardSection.swift`
- `x-terminal/Sources/Supervisor/SupervisorMemoryBoardSection.swift`
- `x-terminal/Sources/Supervisor/SupervisorDoctorBoardSection.swift`
- `x-terminal/Sources/Supervisor/SupervisorAutomationRuntimeBoardSection.swift`
- `x-terminal/Sources/Supervisor/SupervisorXTReadyIncidentBoardSection.swift`
- `x-terminal/Sources/UI/Supervisor/SupervisorPersonalAssistantSummaryBoard.swift`

Primary dashboard tests:

- `x-terminal/Tests/SupervisorDashboardFeedBoardPresentationTests.swift`
- `x-terminal/Tests/SupervisorMemoryBoardPresentationTests.swift`
- `x-terminal/Tests/SupervisorLaneHealthBoardPresentationTests.swift`
- `x-terminal/Tests/SupervisorDoctorBoardPresentationTests.swift`
- `x-terminal/Tests/SupervisorOperationsOverviewPresentationTests.swift`
- `x-terminal/Tests/SupervisorFocusPresentationTests.swift`
- `x-terminal/Tests/SupervisorViewRuntimePresentationSupportBoardsTests.swift`

### 2. Execution Dashboard

This is a distinct task-execution dashboard rather than the main Supervisor board stack.

Primary file:

- `x-terminal/Sources/UI/TaskDecomposition/ExecutionDashboard.swift`

Use this surface when the task is about execution monitoring, task progress visualization, or `ExecutionMonitor` state rather than the broader Supervisor operations deck.

### 3. Observability Dashboard

This is an internal data/benchmark/alert dashboard, not XT UI.

Primary files:

- `scripts/m2_build_observability_dashboard.js`
- `scripts/m2_check_observability_alerts.js`
- `scripts/m2_observability_dashboard.test.js`
- `scripts/m2_generate_weekly_regression_report.js`
- `docs/memory-new/benchmarks/m2-w5-observability/README.md`
- `docs/memory-new/benchmarks/m2-w5-observability/dashboard_snapshot.json`
- `docs/memory-new/benchmarks/m2-w5-observability/dashboard_snapshot.md`

### 4. Documentation Status Dashboard

This is a repo-maintenance dashboard, not a runtime product surface.

Primary file:

- `x-terminal/scripts/generate_doc_status_dashboard.py`

## Diagnostics, Doctor, And Gates

Most important live entrypoints:

### Hub build and source-run

- `x-hub/tools/build_hub_app.command`
- `x-hub/tools/run_xhub_from_source.command`
- `x-hub/tools/run_xhub_bridge_from_source_with_local_dev_agent_skills.command`

Current tree note:

- the checked-in bridge source-run wrapper currently present in the repo is the local-dev-skills variant above

### XT build and source-run

- `x-terminal/tools/run_xterminal_from_source.command`
- `x-terminal/scripts/ci/xt_release_gate.sh`

### Repo-level doctor wrappers

- `scripts/run_xhub_doctor_from_source.command`
- `scripts/smoke_xhub_doctor_xt_source_export.sh`
- `scripts/smoke_xhub_doctor_all_source_export.sh`
- `scripts/ci/xhub_doctor_source_gate.sh`

## Work-Order And Planning Roots

Planning is split across two real families:

| Path | Role | Notes |
|---|---|---|
| `x-terminal/work-orders/` | XT-only implementation packs | Best when the write set is mostly XT |
| `docs/memory-new/` | Repo-level parent work orders, protocol freezes, runbooks, and control-plane work orders | Best when the task affects Hub + XT + docs together |

Do not let XT-only packs hide repo-level parent docs. Many active XT features are downstream of parent work orders in `docs/memory-new/`.

## Where To Start By Task

| Task | Start Here |
|---|---|
| Hub trust, grants, pairing, policy | `x-hub/grpc-server/hub_grpc_server/`, `x-hub/macos/RELFlowHub/`, `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md` |
| Capability derivation, readiness, grant floor, bundle ceiling, runtime deny, doctor/route truth | `docs/repo-inventory/CAPABILITY_AI_HANDOFF_2026-03-30.md`, `docs/memory-new/xhub-capability-operating-model-and-ai-handoff-v1.md`, `x-terminal/Sources/Project/XTSkillCapabilityProfileSupport.swift`, `x-terminal/Sources/Project/AXSkillsLibrary+HubCompatibility.swift`, `x-hub/grpc-server/hub_grpc_server/src/skill_capability_derivation.js`, `x-terminal/Sources/Tools/XTToolRuntimePolicy.swift` |
| XT route truth, pairing UX, trust profile | `x-terminal/Sources/Hub/`, `x-terminal/Sources/Project/`, `x-terminal/work-orders/xt-w1-02-route-state-machine.md`, `x-terminal/work-orders/xt-w3-28-paired-terminal-trust-profile-and-budget-visibility-implementation-pack-v1.md` |
| Project governance / Supervisor loop | `x-terminal/Sources/Supervisor/`, `x-terminal/Sources/Project/`, `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md` |
| Voice / remote approval | `x-terminal/Sources/Voice/`, `x-terminal/Sources/Supervisor/`, `x-terminal/work-orders/xt-w3-29-supervisor-voice-progress-and-guided-authorization-implementation-pack-v1.md`, `x-terminal/work-orders/xt-w3-39-hub-voice-pack-and-supervisor-tts-implementation-pack-v1.md` |
| Memory control plane | `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`, `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`, `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`, `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md` |
| Skills / package governance | `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`, `x-terminal/Sources/Project/`, `docs/memory-new/xhub-governed-package-productization-work-orders-v1.md`, `x-terminal/work-orders/xt-skills-compat-reliability-work-orders-v1.md` |
| Local provider runtime | `x-hub/python-runtime/python_service/`, `x-hub/macos/RELFlowHub/`, `docs/xhub-local-provider-runtime-and-transformers-integration-v1.md`, `docs/memory-new/xhub-local-provider-runtime-transformers-work-orders-v1.md` |
| Dashboard work | `x-terminal/Sources/Supervisor/`, `x-terminal/Sources/UI/TaskDecomposition/ExecutionDashboard.swift`, `scripts/m2_build_observability_dashboard.js` |

## Practical Rule

If a file is under:

- `.axcoder/reports/`
- `.ax-test-cache/`
- `build/`
- `data/`
- `archive/`
- `x-terminal/skills/_projects/`
- `x-terminal/voice_supervisor_smoke_project/`

then it should not be the first file you edit, cite, or assign to another AI without an explicit reason.
