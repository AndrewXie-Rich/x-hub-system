# Feature Validation Checklist

This page is the manual validation checklist for the full system surface.

Use it to test feature-by-feature without mixing:

- validated public claims
- preview-working internal surfaces
- protocol-frozen contracts
- implementation-in-progress branches
- frozen/deprioritized branches

Status words below follow `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md` whenever possible. A small number of internal dashboard rows are explicitly marked as inferred internal status.

## How To Use This Checklist

For each feature:

1. read the status first
2. open the linked work order or parent doc
3. validate the concrete behavior
4. record what passed, what was partial, and what still feels broken

## Trust, Policy, And Control Plane

### Hub-First Trust Anchor

- Status: `validated`
- What to validate:
  - trust, grant, and final policy authority still terminate in Hub
  - XT remains a powerful client, not the trust root
- Primary refs:
  - `README.md`
  - `x-hub/README.md`
  - `docs/xhub-hub-architecture-tradeoffs-v1.md`
- Known gaps:
  - implementation still carries naming debt and some legacy paths

### Fail-Closed Safety Gates

- Status: `validated`
- What to validate:
  - missing readiness, pairing, grant, or policy signals stop execution
  - the UI surfaces blocked state instead of silently proceeding
- Primary refs:
  - `README.md`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
  - `scripts/m3_check_xt_ready_gate.js`
- Known gaps:
  - individual outer surfaces may still need wording / repair UX cleanup

### Pairing / Discovery / Doctor / Repair Loop

- Status: `preview-working`
- What to validate:
  - XT can discover or connect to Hub
  - doctor can explain blocked reasons
  - repair or re-pair flow has a concrete next step
- Primary refs:
  - `docs/xhub-runtime-stability-and-launch-recovery-v1.md`
  - `x-terminal/work-orders/xt-w3-27-hub-xt-ui-productization-r1-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-28-paired-terminal-trust-profile-and-budget-visibility-implementation-pack-v1.md`
- Known gaps:
  - first-run success shell is still not fully productized

### Route Truth, Fallback, And Actual-Route Visibility

- Status: `preview-working`
- What to validate:
  - configured route, actual route, fallback reason, and deny reason stay visible
  - project chat, doctor, and Supervisor agree on route truth
- Primary refs:
  - `x-terminal/Sources/Hub/`
  - `x-terminal/Sources/Project/XTRouteTruthPresentation.swift`
  - `x-terminal/work-orders/xt-w1-02-route-state-machine.md`
- Known gaps:
  - some outer surfaces are still being normalized onto one presentation path

### Trusted Automation Four-Plane Readiness

- Status: `preview-working`
- What to validate:
  - higher-risk automation requires the expected readiness and clamp conditions
  - Hub-side posture can still clamp or deny the automation run
- Primary refs:
  - `docs/memory-new/xhub-trusted-automation-mode-work-orders-v1.md`
  - `docs/memory-new/xhub-trusted-automation-device-execution-plane-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`
- Known gaps:
  - not all device-facing surfaces are equally mature yet

## Memory, Constitution, And Governance

### Hub-Backed Memory UX And Governed Memory Truth

- Status: `validated`
- What to validate:
  - XT reads and presents memory from Hub-backed truth sources
  - XT does not become the durable memory authority
- Primary refs:
  - `README.md`
  - `X_MEMORY.md`
  - `x-terminal/work-orders/xt-w3-23-memory-ux-adapter-implementation-pack-v1.md`
- Known gaps:
  - broader memory productization is still underway beyond the validated slice

### Durable Writer Boundary And Memory Export Guardrails

- Status: `validated` for boundary, `preview-working` for broader product shell
- What to validate:
  - durable memory truth still terminates through `Writer + Gate`
  - memory source labels do not lie about `hub`, `overlay`, or `fallback`
  - remote export / privacy posture remains visible
- Primary refs:
  - `X_MEMORY.md`
  - `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
- Known gaps:
  - full memory control-plane migration and richer health reporting are still in flight

### Memory Serving Profiles `M0..M4`

- Status: `protocol-frozen`
- What to validate:
  - contracts and labels match the frozen serving-profile design
  - any implementation does not drift from the frozen contract
- Primary refs:
  - `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md`
- Known gaps:
  - complete end-user product shell is not the finished target yet

### X-Constitution And Policy Explain/Confirm Loop

- Status: `preview-working`
- What to validate:
  - Hub still exposes constitutional/policy state as a real control layer
  - higher-risk approvals preserve explanation, acknowledgement, or options metadata
- Primary refs:
  - `X_MEMORY.md`
  - `docs/memory-new/xhub-constitution-l0-injection-v2.md`
  - `docs/xhub-constitution-l1-guidance-v1.md`
  - `docs/xhub-constitution-policy-engine-checklist-v1.md`
- Known gaps:
  - broader policy engine productization is still incomplete

### Project Governance `A0..A4` + `S0..S4`

- Status: `preview-working`
- What to validate:
  - project settings expose A-Tier, S-Tier, and Heartbeat / Review separately
  - runtime clamps actually match the effective governance settings
- Primary refs:
  - `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
  - `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-36-b-project-governance-surface-split-implementation-pack-v1.md`
- Known gaps:
  - still outside the narrow validated public mainline

### Supervisor Project Transaction Integrity

- Status: `implementation-in-progress`
- What to validate:
  - ability/permission/status questions about project creation do not trigger project side effects
  - explicit user project name overrides inferred/default project name
  - after a mistaken create, Supervisor can delete, undo, or rename the last-created project through natural follow-up language
  - side-effect requests return real execution results rather than memory-style acknowledgement
- Primary refs:
  - `x-terminal/work-orders/xt-w3-42-supervisor-project-intent-and-transaction-repair-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-21-w3-22-supervisor-intake-acceptance-implementation-pack-v1.md`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- Known gaps:
  - current shipped behavior still has create-intent over-triggering and lacks a complete rename/delete/undo correction loop
  - this row should not be marked `preview-working` until the “坦克大战” regression script is automated and green

### Supervisor Personal Plane

- Status: `implementation-in-progress`
- What to validate:
  - persona, personal memory, personal review, and longterm assistant surfaces do something real
  - they do not override Hub-first durable truth boundaries
- Primary refs:
  - `x-terminal/work-orders/xt-w3-38-supervisor-personal-longterm-assistant-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-38-h-supervisor-persona-center-implementation-pack-v1.md`
  - `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
- Known gaps:
  - this branch is explicitly deprioritized for current v1 mainline

## Skills, Packages, And Runtime Safety

### Skills Control Plane

- Status: `preview-working`
- What to validate:
  - Hub can search skills, resolve pins, and return manifests/state
  - XT can consume real governed skill state instead of static assumptions
- Primary refs:
  - `X_MEMORY.md`
  - `docs/xhub-skills-discovery-and-import-v1.md`
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`
- Known gaps:
  - the overall package shell is still broader than the current finished UX

### Default Official Baseline Install

- Status: `preview-working`
- What to validate:
  - baseline official packages actually install/resolve through Hub-governed state
  - XT does not fake install state
- Primary refs:
  - `x-terminal/work-orders/xt-w3-34-openclaw-skill-reuse-and-execution-surface-implementation-pack-v1.md`
  - `x-terminal/Sources/AppModel.swift`
  - `x-terminal/Sources/UI/SettingsView.swift`
- Known gaps:
  - broader reuse/import flows are still in motion

### Official Skills Doctor

- Status: `preview-working`
- What to validate:
  - XT can show blocker ranking, primary actions, and recheck closure
  - deep-link repair flow reaches the right XT landing surface
- Primary refs:
  - `x-terminal/Sources/Project/AXSkillsLibrary+HubCompatibility.swift`
  - `x-terminal/Sources/XTOfficialSkillsBlockerActionSupport.swift`
  - `x-terminal/Sources/XTDeepLinkURLBuilder.swift`
- Known gaps:
  - this does not yet equal a full request/review/auto-retry chain

### Governed Package Shell

- Status: `protocol-frozen`
- What to validate:
  - manifest, registry, doctor, and lifecycle contracts are consistent
  - runtime implementations do not invent their own incompatible lifecycle model
- Primary refs:
  - `docs/memory-new/xhub-governed-package-productization-work-orders-v1.md`
  - `docs/memory-new/schema/xhub_governed_package_manifest.v1.json`
  - `docs/memory-new/schema/xhub_package_registry_entry.v1.json`
  - `docs/memory-new/schema/xhub_package_doctor_output_contract.v1.json`
- Known gaps:
  - unified manager/product shell is still being built

### Dynamic Official Skill Request

- Status: `implementation-in-progress`
- What to validate:
  - missing governed capability can be surfaced as a formal request idea
  - current chain does not overclaim full review/promotion closure
- Primary refs:
  - `docs/memory-new/xhub-dynamic-official-agent-skills-governance-work-orders-v1.md`
- Known gaps:
  - full proposal/review lifecycle is not complete yet

### Compatibility Gates

- Status: `preview-working`
- What to validate:
  - skill/package compatibility checks and preflight gates run as real gates
  - retry and preflight evidence stay machine-readable
- Primary refs:
  - `docs/skills_abi_compat.v1.md`
  - `x-terminal/work-orders/xt-skills-compat-reliability-work-orders-v1.md`
  - `x-terminal/work-orders/xt-l1-skills-ux-preflight-runner-contract-v1.md`
- Known gaps:
  - broader package-shell productization remains ongoing

## Channels, Automation, And External Execution Surfaces

### Multichannel Gateway

- Status: `validated`
- What to validate:
  - remote operator channels still enter through Hub-first routing/governance
  - at least the validated preview surfaces remain intact
- Primary refs:
  - `README.md`
  - `x-terminal/work-orders/xt-w3-24-multichannel-gateway-productization-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-24-supervisor-operator-channels-implementation-pack-v1.md`
- Known gaps:
  - broader channel expansion is intentionally not the current v1 goal

### Safe Channel Onboarding And Repair Path

- Status: `preview-working`
- What to validate:
  - onboarding can report invalid token, signature mismatch, replay suspicion, or other repairable failures
  - the repair path points to a concrete next step
- Primary refs:
  - `x-terminal/work-orders/xt-w3-24-safe-operator-channel-onboarding-automation-implementation-pack-v1.md`
  - `scripts/ci/xt_w3_24_s_safe_onboarding_gate.sh`
  - `docs/open-source/evidence/xt_w3_24_s_safe_onboarding_release_evidence.v1.json`
- Known gaps:
  - first-run polish is not finished enough to upgrade to validated

### Governed Automation Runtime

- Status: `validated`
- What to validate:
  - automation recipes execute under Hub governance, not as unbounded local macros
  - audit and clamp behavior remain present
- Primary refs:
  - `README.md`
  - `x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`
  - `docs/memory-new/xhub-trusted-automation-device-execution-plane-implementation-pack-v1.md`
- Known gaps:
  - richer device surfaces are still being expanded

### OpenClaw-Mode Parity Surfaces

- Status: `implementation-in-progress`
- What to validate:
  - browser/runtime/trigger surfaces land as governed extensions instead of ungated parity chasing
- Primary refs:
  - `x-terminal/work-orders/xt-w3-30-openclaw-mode-capability-gap-closure-implementation-pack-v1.md`
- Known gaps:
  - explicitly not a current mainline v1 target

### Agent Asset Reuse

- Status: `implementation-in-progress`
- What to validate:
  - third-party capability reuse stays behind governed compatibility and trust boundaries
- Primary refs:
  - `x-terminal/work-orders/xt-w3-34-openclaw-skill-reuse-and-execution-surface-implementation-pack-v1.md`
  - `docs/memory-new/xhub-agent-asset-reuse-map-v1.md`
- Known gaps:
  - still a continuing adoption path rather than a closed product feature

## Models, Providers, Diagnostics, And Release

### Unified Local + Paid Routing

- Status: `preview-working`
- What to validate:
  - local and paid routes live under one governed control plane
  - XT shows truthful route state rather than a stale local cache
- Primary refs:
  - `README.md`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubStore.swift`
  - `x-terminal/Sources/Hub/HubModelSelectionAdvisor.swift`
- Known gaps:
  - deeper product shell is still in progress

### Local Provider Runtime

- Status: `preview-working`
- What to validate:
  - local provider runtime can run real embedding / speech / vision flows
  - require-real evidence chain still matches current runtime behavior
- Primary refs:
  - `docs/xhub-local-provider-runtime-and-transformers-integration-v1.md`
  - `docs/memory-new/xhub-local-provider-runtime-transformers-work-orders-v1.md`
  - `x-hub/python-runtime/python_service/`
- Known gaps:
  - packaged shell, public wording, and broader provider productization are still moving

### Hub Diagnostics + XT Doctor

- Status: `preview-working`
- What to validate:
  - Hub settings and XT setup surfaces expose real diagnostics
  - repair-oriented suggested actions remain visible
- Primary refs:
  - `x-terminal/Sources/UI/SettingsView.swift`
  - `x-terminal/Sources/UI/HubSetupWizardView.swift`
  - `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
- Known gaps:
  - one unified cross-product doctor shell is not finished yet

### Unified Doctor Contract And Wrapper Shell

- Status: `implementation-in-progress`
- What to validate:
  - normalized doctor exports can be generated for Hub and XT
  - focused and aggregate source-run smokes still pass
- Primary refs:
  - `docs/memory-new/schema/xhub_doctor_output_contract.v1.json`
  - `docs/memory-new/schema/xt_unified_doctor_report_contract.v1.json`
  - `scripts/run_xhub_doctor_from_source.command`
  - `scripts/ci/xhub_doctor_source_gate.sh`
- Known gaps:
  - packaged cross-product CLI shell is not finished

### XT Release Gate

- Status: `preview-working`
- What to validate:
  - XT release gate still executes the expected smoke paths
  - route, grant, and Supervisor voice smokes remain covered
- Primary refs:
  - `x-terminal/scripts/ci/xt_release_gate.sh`
  - `x-terminal/scripts/README.md`
- Known gaps:
  - release discipline is real, but not every surface is equally closed

### Replay / Fuzz Discipline

- Status: `direction-only`
- What to validate:
  - only whether there is planning/design in place, not a finished engineering shell
- Primary refs:
  - `docs/memory-new/xhub-ironclaw-reference-adoption-checklist-v1.md`
- Known gaps:
  - no claim of delivered replay/fuzz rig should be made yet

## Internal Operational Surfaces

The rows below are internal operational surfaces. Their statuses are inferred from active code/tests, not from the public capability matrix.

### Supervisor Operations Dashboard

- Status: inferred `preview-working`
- What to validate:
  - board sections render coherent runtime state
  - memory, doctor, grants, automation, XT-ready incidents, and portfolio boards all wire up correctly
- Primary refs:
  - `x-terminal/Sources/Supervisor/SupervisorDashboardBoards.swift`
  - `x-terminal/Sources/Supervisor/SupervisorViewRuntimePresentationSupport.swift`
  - `x-terminal/Tests/SupervisorDashboardFeedBoardPresentationTests.swift`
- Known gaps:
  - this is an active XT internal surface, not a separately validated public claim

### Execution Dashboard

- Status: inferred `implementation-in-progress`
- What to validate:
  - task execution states, progress, and detail panes update correctly under `ExecutionMonitor`
- Primary refs:
  - `x-terminal/Sources/UI/TaskDecomposition/ExecutionDashboard.swift`
- Known gaps:
  - narrower and less central than the Supervisor operations dashboard

### Observability Dashboard

- Status: inferred `preview-working`
- What to validate:
  - benchmark and audit data can still build a usable dashboard snapshot
  - alert thresholds still produce expected warnings or failures
- Primary refs:
  - `scripts/m2_build_observability_dashboard.js`
  - `scripts/m2_check_observability_alerts.js`
  - `scripts/m2_observability_dashboard.test.js`
- Known gaps:
  - this is an internal engineering dashboard, not a public product feature

### Documentation Status Dashboard

- Status: inferred `preview-working`
- What to validate:
  - doc-status scanner still classifies stale vs active markdown docs sensibly
- Primary refs:
  - `x-terminal/scripts/generate_doc_status_dashboard.py`
- Known gaps:
  - this is a maintenance aid only

## Frozen / Deprioritized Tracks

These features exist in active code/docs, but they are not current v1 mainline priorities:

- Persona center / personal assistant expansion
- OpenClaw full parity chase
- broad channel proliferation
- decorative multi-surface UI expansion

Test them as regression or branch coverage, not as the first public validation sweep.
