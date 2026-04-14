# Multi-AI Lane Dispatch

- date: `2026-03-27`
- source:
  - `docs/repo-inventory/ACTIVE_DEVELOPMENT_SURFACES.md`
  - `docs/repo-inventory/WORK_ORDER_MASTER_CATALOG.md`
  - `docs/repo-inventory/FEATURE_VALIDATION_CHECKLIST.md`
  - `docs/open-source/XHUB_NEXT_10_WORK_ORDERS_v1.md`
- purpose:
  - start parallel AI execution from one shared dispatch board
  - keep write scopes disjoint
  - stop agents from wandering into generated paths or frozen branches

For the current branch, lane-level dispatch is only the first split.
When you need one feature per AI, continue from `docs/repo-inventory/MULTI_AI_SECONDARY_WORK_ORDERS_2026-03-27.md`.

## Global Rules

1. Ignore these paths unless a task explicitly says otherwise:
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

2. Keep ownership disjoint.
   One lane should own one primary write surface at a time.

3. Do not reopen frozen branches by default:
   - persona / personal assistant expansion
   - OpenClaw full parity chase
   - channel-count expansion

4. Validate every landed change back against:
   - `docs/repo-inventory/FEATURE_VALIDATION_CHECKLIST.md`

## Status Snapshot

- Lane A:
  - first slice landed on `2026-03-27`
  - pending-grant route truth aligned for `auto | grpc | file`
  - targeted tests and XT route smoke passed
- Lane B:
  - first slice landed on `2026-03-27`
  - governance truth presentation closure landed
  - targeted tests passed
  - evidence script still fails on pre-existing `SupervisorMultilaneFlowTests`
- Lane C:
  - first slice landed on `2026-03-27`
  - conversation session seam landed
  - voice smoke and calendar boundary evidence passed
  - release gate and governance evidence still fail on broader branch noise
- Lane D:
  - first slice landed on `2026-03-27`
  - governed package schema freeze landed
  - targeted schema/package checks passed

## Lane A

- label: `Trust / Connect foundation`
- next-10 mapping:
  - item `1`
  - item `2`
- primary packs:
  - `x-terminal/work-orders/xt-w1-02-route-state-machine.md`
  - `x-terminal/work-orders/xt-w1-03-pending-grants-source-of-truth.md`
  - `x-terminal/work-orders/xt-w1-04-high-risk-grant-enforcement.md`
  - `x-terminal/work-orders/xt-w3-27-hub-xt-ui-productization-r1-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-28-paired-terminal-trust-profile-and-budget-visibility-implementation-pack-v1.md`
- default ownership:
  - `x-terminal/Sources/Hub/`
  - `x-terminal/Sources/Project/`
  - selected Hub pairing / trust surfaces when needed
- status:
  - first slice landed
  - implementation worker: `Rawls`
  - validation:
    - `HubRouteStateMachineTests` passed
    - `swift run XTerminal --xt-route-smoke` passed
    - `swift run XTerminal --xt-grant-smoke` passed
    - `bash x-terminal/scripts/ci/xt_route_truth_snapshot_check.sh` passed
- first slice:
  - align XT transport truth for pending grants in `requestPendingGrantRequests(...)`
  - normalize `auto / grpc / file` route decision, remote failure taxonomy, fallback-used vs fail-closed semantics
  - do not start from UI shells yet
- concrete write scopes:
  - `x-terminal/Sources/Hub/HubRouteStateMachine.swift`
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - `x-terminal/Tests/HubRouteStateMachineTests.swift`
  - optional thin extension only if needed: `x-terminal/Sources/Hub/HubPairingCoordinator.swift`
- avoid:
  - `x-terminal/Sources/Supervisor/`
  - `x-terminal/Sources/UI/`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/`
  - `x-hub/grpc-server/hub_grpc_server/src/`
- validate with:
  - `cd x-terminal && swift test --filter HubRouteStateMachineTests`
  - `cd x-terminal && swift run XTerminal --xt-route-smoke`
  - `cd x-terminal && swift run XTerminal --xt-grant-smoke`
  - `bash x-terminal/scripts/ci/xt_route_truth_snapshot_check.sh`
- blockers:
  - current branch noise is high
  - item `1` still blocks full item `2` closure, so this slice is transport-truth only

## Lane B

- label: `Memory / Governance trunk`
- next-10 mapping:
  - item `3`
  - item `5`
- primary packs:
  - `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
  - `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`
  - `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md`
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-36-b-project-governance-surface-split-implementation-pack-v1.md`
- default ownership:
  - `x-terminal/Sources/Project/`
  - `x-terminal/Sources/Supervisor/`
  - repo-level memory/governance docs
- status:
  - first slice landed
  - implementation worker: `Lagrange`
  - validation:
    - `ProjectGovernanceResolverTests` passed
    - `XTGovernanceTruthPresentationTests` passed
    - `XTDoctorMemoryTruthClosureEvidenceTests` passed
  - open issue:
    - `bash x-terminal/scripts/ci/xt_w3_36_project_governance_evidence.sh` still fails on existing `SupervisorMultilaneFlowTests`
- first slice:
  - XT-only truth-surface closure
  - fix `configured vs effective` governance truth so settings/detail/doctor stop disagreeing
  - keep memory-source truth work limited to safe projection/evidence points, not full control-plane changes
- concrete write scopes:
  - `x-terminal/Sources/Project/AXProjectGovernanceResolver.swift`
  - `x-terminal/Sources/Project/XTGovernanceTruthPresentation.swift`
  - optional thin export touch only if needed: `x-terminal/Sources/UI/XHubDoctorOutput.swift`
  - tests:
  - `x-terminal/Tests/ProjectGovernanceResolverTests.swift`
  - `x-terminal/Tests/XTGovernanceTruthPresentationTests.swift`
  - `x-terminal/Tests/XTDoctorMemoryTruthClosureEvidenceTests.swift`
- avoid:
  - `x-terminal/Sources/UI/ProjectSettingsView.swift`
  - `x-terminal/Sources/UI/Projects/CreateProjectSheet.swift`
  - `x-terminal/Sources/UI/Projects/ProjectsGridView.swift`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Project/XTMemorySourceTruthPresentation.swift`
  - `x-terminal/scripts/ci/xt_release_gate.sh`
  - repo-level parent docs and `x-hub/*` runtime roots for this first slice
- validate with:
  - `cd x-terminal && swift test --filter ProjectGovernanceResolverTests`
  - `cd x-terminal && swift test --filter XTGovernanceTruthPresentationTests`
  - `cd x-terminal && swift test --filter XTDoctorMemoryTruthClosureEvidenceTests`
  - `bash x-terminal/scripts/ci/xt_w3_36_project_governance_evidence.sh`
- blockers:
  - UI and supervisor consumption layers are already noisy
  - safest first move is presentation-level compatibility, not schema breakage

## Lane C

- label: `Supervisor / Voice / main interaction loop`
- next-10 mapping:
  - item `4`
  - item `6`
- primary packs:
  - `x-terminal/work-orders/xt-w3-21-w3-22-supervisor-intake-acceptance-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-26-supervisor-one-shot-intake-adaptive-pool-planner-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-29-supervisor-conversation-window-persistent-session-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-29-supervisor-voice-progress-and-guided-authorization-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-29-supervisor-voice-productization-gap-closure-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-39-hub-voice-pack-and-supervisor-tts-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-40-supervisor-device-local-calendar-reminders-implementation-pack-v1.md`
- default ownership:
  - `x-terminal/Sources/Supervisor/`
  - `x-terminal/Sources/Voice/`
  - selected XT UI surfaces
- status:
  - first slice landed
  - implementation worker: `Mill`
  - validation:
    - `swift run XTerminal --xt-supervisor-voice-smoke` passed
    - `swift test --filter SupervisorConversationSessionControllerTests` passed
    - `swift test --filter SupervisorConversationWindowBridgeTests` passed
    - `bash x-terminal/scripts/ci/xt_w3_40_calendar_boundary_evidence.sh` passed
  - open issue:
    - `bash x-terminal/scripts/ci/xt_release_gate.sh` still fails on broader branch noise and script issues
    - `bash x-terminal/scripts/ci/xt_w3_36_project_governance_evidence.sh` still fails on existing Supervisor tests
- first slice:
  - land `CW-3 Conversation Session Controller` seam first
  - implement `hidden | armed | conversing`
  - support `wake_hit / user_turn / assistant_turn / tts_spoken / timeout`
  - expose `remaining_ttl_sec` and `reason_code`
- concrete write scopes:
  - `x-terminal/Sources/Supervisor/SupervisorConversationSessionController.swift`
  - `x-terminal/Sources/Supervisor/SupervisorConversationWindowBridge.swift`
  - optional thin wires only if needed:
  - `x-terminal/Sources/UI/Supervisor/SupervisorStatusBar.swift`
  - `x-terminal/Sources/Voice/VoiceSessionCoordinator.swift`
- avoid:
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/SupervisorView.swift`
  - `x-terminal/Sources/Supervisor/SupervisorViewContent.swift`
  - `x-terminal/Sources/Supervisor/SupervisorDashboardBoards.swift`
  - `x-terminal/Sources/Supervisor/SupervisorViewRuntimePresentationSupport.swift`
  - `x-terminal/Sources/Supervisor/SupervisorViewRuntimePresentationSupportBoards.swift`
  - `x-terminal/Sources/Project/`
- validate with:
  - `cd x-terminal && swift run XTerminal --xt-supervisor-voice-smoke --project-root "$(pwd)" --out-json .axcoder/reports/xt_supervisor_voice_smoke.runtime.json`
  - `bash x-terminal/scripts/ci/xt_release_gate.sh`
  - `bash x-terminal/scripts/ci/xt_w3_36_project_governance_evidence.sh`
  - `bash x-terminal/scripts/ci/xt_w3_40_calendar_boundary_evidence.sh`
- blockers:
  - do not mix TTS-provider work or dashboard reshaping into the first slice
  - current branch is noisy across Supervisor/UI/Voice

## Lane D

- label: `Capability productization`
- next-10 mapping:
  - item `7`
  - item `8`
  - item `9`
  - item `10`
- primary packs:
  - `x-terminal/work-orders/xt-skills-compat-reliability-work-orders-v1.md`
  - `x-terminal/work-orders/xt-l1-skills-ux-preflight-runner-contract-v1.md`
  - `docs/memory-new/xhub-governed-package-productization-work-orders-v1.md`
  - `docs/memory-new/xhub-local-provider-runtime-transformers-work-orders-v1.md`
  - `docs/memory-new/xhub-work-order-8-9-closure-checklist-v1.md`
  - `x-terminal/work-orders/xt-w3-24-safe-operator-channel-onboarding-automation-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-24-supervisor-operator-channels-implementation-pack-v1.md`
  - `docs/open-source/XHUB_PUBLIC_ADOPTION_ROADMAP_v1.md`
- default ownership:
  - `x-hub/python-runtime/`
  - selected skills/package docs and scripts
  - selected public docs / `website/`
- status:
  - first slice landed
  - implementation worker: `Aquinas`
  - validation:
    - `skills_store_manifest_compat.test.js` passed
    - `skills_store_official_package_doctor.test.js` passed
    - `skills_store_official_agent_catalog.test.js` passed
    - `scripts/m3_check_skills_grant_chain_contract.js` passed
    - `x-terminal/scripts/check_skills_xt_l1_contract.js` passed
- first slice:
  - take `GP-W1-01 + GP-W1-02` together as one atomic package shell slice
  - freeze governed package `manifest + registry + checksum/source-fallback` contracts
  - add one official skill, one operator-channel, and one local-provider-pack minimal example shape only if required by the contract/tests
- concrete write scopes:
  - `docs/memory-new/schema/xhub_governed_package_manifest.v1.json`
  - `docs/memory-new/schema/xhub_package_registry_entry.v1.json`
  - `docs/memory-new/schema/xhub_package_doctor_output_contract.v1.json`
  - optional very narrow tests only if required:
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store_manifest_compat.test.js`
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store_official_package_doctor.test.js`
- avoid:
  - `README.md`
  - `website/`
  - `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`
  - `docs/open-source/XHUB_NEXT_10_WORK_ORDERS_v1.md`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/`
  - `x-hub/python-runtime/python_service/`
  - `x-terminal/Sources/Project/`
  - `x-terminal/Sources/UI/SettingsView.swift`
  - `x-terminal/Sources/UI/HubSetupWizardView.swift`
- validate with:
  - `node x-hub/grpc-server/hub_grpc_server/src/skills_store_manifest_compat.test.js`
  - `node x-hub/grpc-server/hub_grpc_server/src/skills_store_official_package_doctor.test.js`
  - `node x-hub/grpc-server/hub_grpc_server/src/skills_store_official_agent_catalog.test.js`
  - `node scripts/m3_check_skills_grant_chain_contract.js`
  - `node x-terminal/scripts/check_skills_xt_l1_contract.js`
- blockers:
  - W8 skills basics are already closure-complete, so do not reopen starter-pack basics
  - public docs/website are too noisy for the first slice
  - confirm current schema docs are the intended source files before editing

## Dispatch Template

Fill this block after each lane brief lands:

- first slice:
- write scopes:
- avoid:
- validate with:
- blockers:
