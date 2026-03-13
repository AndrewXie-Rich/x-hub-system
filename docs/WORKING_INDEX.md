# Working Index

This is the operator-facing navigation page for the active repository surface.

Use it to answer three questions quickly:

1. What should I read first?
2. Where does the active code live?
3. Which document is the source of truth for the task I am touching?

This page is a working map, not a release-scope expansion document.

## Read Order

If you are entering the repository cold, read in this order:

1. `README.md`
2. `docs/REPO_LAYOUT.md`
3. `X_MEMORY.md`
4. `x-hub/README.md`
5. `x-terminal/README.md`

After that, choose the relevant track below.

## Current High-Value Tracks

### Product And Runtime

- `docs/xhub-scenario-map-v1.md`
- `docs/xhub-runtime-stability-and-launch-recovery-v1.md`
- `docs/xhub-local-provider-runtime-and-transformers-integration-v1.md`
- `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
- `docs/memory-new/schema/xhub_project_autonomy_and_supervisor_review_contract.v1.json`
- `docs/memory-new/xhub-local-provider-runtime-transformers-work-orders-v1.md`
- `docs/xhub-client-modes-and-connectors-v1.md`
- `docs/xhub-hub-architecture-tradeoffs-v1.md`
- `docs/memory-new/xhub-multimodal-supervisor-control-plane-architecture-memo-v1.md`
- `docs/memory-new/xhub-multimodal-supervisor-control-plane-contract-freeze-v1.md`
- `docs/memory-new/xhub-multimodal-supervisor-control-plane-work-orders-v1.md`

### Memory

- `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md`
- `docs/xhub-memory-system-spec-v2.md`
- `docs/xhub-memory-hybrid-index-v1.md`
- `docs/xhub-memory-fusion-v1.md`
- `specs/xhub-memory-quality-v1/`

### Memory And Constitutional Safety

- `X_MEMORY.md`
- `docs/xhub-constitution-l0-injection-v1.md`
- `docs/xhub-constitution-l1-guidance-v1.md`
- `docs/xhub-constitution-policy-engine-checklist-v1.md`

If you are tracing behavior boundaries, risk controls, or fail-closed reasoning, start here before reading feature-specific implementation packs.

### Skills

- `official-agent-skills/`
- `docs/xhub-skills-placement-and-execution-boundary-v1.md`
- `docs/xhub-skills-discovery-and-import-v1.md`
- `docs/xhub-skills-signing-distribution-and-runner-v1.md`
- `docs/skills_abi_compat.v1.md`
- `docs/skills_import_bridge_contract.v1.md`

### Security, Gates, And Governance

- `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
- `docs/memory-new/schema/xhub_project_autonomy_and_supervisor_review_contract.v1.json`
- `docs/memory-new/xhub-security-innovation-work-orders-v1.md`
- `docs/memory-new/xhub-spec-gates-work-orders-v1.md`
- `docs/memory-new/xhub-lane-command-board-v2.md`
- `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
- `docs/memory-new/xhub-trusted-automation-mode-work-orders-v1.md`
- `docs/memory-new/xhub-trusted-automation-device-execution-plane-implementation-pack-v1.md`
- `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`
- `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`

### X-Terminal Execution Packs

- `x-terminal/work-orders/README.md`
- `x-terminal/work-orders/xterminal-parallel-work-orders-v1.md`
- `x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md`
- `x-terminal/work-orders/xt-w3-23-memory-ux-adapter-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-24-multichannel-gateway-productization-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-24-supervisor-operator-channels-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-24-supervisor-operator-channels-hub-security-impact-gate-v1.md`
- `x-terminal/work-orders/xt-w3-25-automation-product-gap-closure-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-29-supervisor-voice-progress-and-guided-authorization-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-30-openclaw-mode-capability-gap-closure-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-31-supervisor-portfolio-awareness-and-project-action-feed-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-32-supervisor-skill-orchestration-and-governed-event-loop-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-33-supervisor-decision-kernel-routing-and-memory-governance-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-34-openclaw-skill-reuse-and-execution-surface-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-35-supervisor-memory-retrieval-progressive-disclosure-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`

### Project Governance And Supervisor Review

- `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
- `docs/memory-new/schema/xhub_project_autonomy_and_supervisor_review_contract.v1.json`
- `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
- `x-terminal/Sources/Project/AXProjectGovernanceBundle.swift`
- `x-terminal/Sources/Project/AXProjectExecutionTier.swift`
- `x-terminal/Sources/Project/AXProjectSupervisorInterventionTier.swift`
- `x-terminal/Sources/Project/AXProjectGovernanceResolver.swift`
- `x-terminal/Sources/Supervisor/SupervisorReviewNoteStore.swift`
- `x-terminal/Sources/Supervisor/SupervisorGuidanceInjectionStore.swift`
- `x-terminal/Sources/Supervisor/SupervisorSafePointCoordinator.swift`

## Validated Public Mainline

For GitHub-facing claims, the validated mainline is limited to:

- `XT-W3-23 -> XT-W3-24 -> XT-W3-25`

Validated public claims stay limited to:

- Hub-backed memory UX
- Hub-governed multi-channel gateway
- Hub-first governed automations

Use the root `README.md` for the external product narrative. Use this page for working navigation only.

## Active Code Map

### Hub App And Native Runtime

- Swift package root:
  - `x-hub/macos/RELFlowHub/`
- Most common files:
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubStore.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubGRPCServerSupport.swift`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryContextBuilder.swift`

### Hub Service Layer

- Node service root:
  - `x-hub/grpc-server/hub_grpc_server/`
- Most common files:
  - `x-hub/grpc-server/hub_grpc_server/src/server.js`
  - `x-hub/grpc-server/hub_grpc_server/src/services.js`
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`

### Hub Python Runtime

- `x-hub/python-runtime/python_service/relflowhub_local_runtime.py`
- `x-hub/python-runtime/python_service/relflowhub_mlx_runtime.py`
- `x-hub/python-runtime/python_service/relflowhub_ai_worker.py`
- `x-hub/python-runtime/python_service/relflowhub_model_worker.py`

### Official Agent Skills

- `official-agent-skills/`
- `official-agent-skills/dist/index.json`
- `official-agent-skills/dist/trusted_publishers.json`
- `official-agent-skills/publisher/trusted_publishers.json`

### X-Terminal

- Swift package root:
  - `x-terminal/`
- Most common areas:
  - `x-terminal/Sources/UI/`
  - `x-terminal/Sources/Supervisor/`
  - `x-terminal/Sources/Session/`
  - `x-terminal/Sources/Hub/`
  - `x-terminal/Sources/Tools/`
  - `x-terminal/Sources/Project/`

### Protocol

- `protocol/hub_protocol_v1.md`
- `protocol/hub_protocol_v1.proto`

### Active Specs And Work Orders

- `docs/xhub-skills-placement-and-execution-boundary-v1.md`
- `docs/xhub-skills-discovery-and-import-v1.md`
- `docs/memory-new/xhub-agent-skill-vetter-gate-work-orders-v1.md`
- `docs/memory-new/xhub-multimodal-supervisor-control-plane-contract-freeze-v1.md`
- `docs/memory-new/xhub-multimodal-supervisor-control-plane-work-orders-v1.md`
- `x-terminal/work-orders/xt-w3-34-openclaw-skill-reuse-and-execution-surface-implementation-pack-v1.md`

## Active Entry Points

### Build The Hub App

```bash
x-hub/tools/build_hub_app.command
```

### Run X-Hub

```bash
bash x-hub/tools/run_xhub_from_source.command
```

### Run X-Hub Bridge

```bash
bash x-hub/tools/run_xhub_bridge_from_source.command
```

### Run X-Terminal

```bash
cd x-terminal
swift run XTerminal
```

### Build X-Terminal

```bash
cd x-terminal
swift build
```

### Run The XT Release Gate

```bash
bash x-terminal/scripts/ci/xt_release_gate.sh
```

## Where To Look By Task

### Pairing, Trust, And Grants

- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubGRPCServerSupport.swift`
- `x-hub/grpc-server/hub_grpc_server/src/services.js`

### Remote Models And Provider Routing

- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/AddRemoteModelSheet.swift`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/RemoteProviderEndpoints.swift`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHubBridge/BridgeRunner.swift`

### Local Models And Provider Runtime

- `docs/xhub-local-provider-runtime-and-transformers-integration-v1.md`
- `docs/memory-new/xhub-local-provider-runtime-transformers-work-orders-v1.md`
- `docs/memory-new/xhub-local-provider-runtime-transformers-implementation-pack-v1.md`
- `x-hub/python-runtime/python_service/relflowhub_local_runtime.py`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/AddModelSheet.swift`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubStore.swift`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/ModelModels.swift`
- `x-hub/python-runtime/python_service/relflowhub_mlx_runtime.py`
- `x-hub/python-runtime/python_service/relflowhub_model_worker.py`
- `x-hub/python-runtime/python_service/relflowhub_ai_worker.py`

### Launch Diagnostics And Recovery

- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubLaunchStateMachine.swift`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/HubLaunchStatus.swift`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubDiagnosticsBundleExporter.swift`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubStore.swift`

### Memory, X-Constitution, And Policy Guardrails

- `X_MEMORY.md`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubMemoryContextBuilder.swift`
- `x-hub/python-runtime/python_service/relflowhub_mlx_runtime.py`
- `docs/xhub-constitution-l0-injection-v1.md`
- `docs/xhub-constitution-l1-guidance-v1.md`
- `docs/xhub-constitution-policy-engine-checklist-v1.md`

### Project Governance, Review, And Intervention

- `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
- `x-terminal/Sources/Project/AXProjectConfig.swift`
- `x-terminal/Sources/Project/AXProjectGovernanceResolver.swift`
- `x-terminal/Sources/UI/ProjectSettingsView.swift`
- `x-terminal/Sources/UI/Projects/CreateProjectSheet.swift`
- `x-terminal/Sources/UI/Projects/ProjectDetailView.swift`
- `x-terminal/Sources/Supervisor/SupervisorManager.swift`

### Skills

- `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`
- `x-hub/grpc-server/hub_grpc_server/src/services.js`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubSkillsStoreStorage.swift`
- `docs/memory-new/schema/xhub_skills_capability_grant_chain_contract.v1.json`

### Session Runtime, Supervisor, And Tooling

- `x-terminal/Sources/Session/`

### Supervisor Portfolio And Multi-Project Control

- `x-terminal/Sources/Supervisor/SupervisorView.swift`
- `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- `x-terminal/Sources/AppModel+MultiProject.swift`
- `x-terminal/Sources/Project/MultiProjectManager.swift`
- `x-terminal/work-orders/xt-w3-31-supervisor-portfolio-awareness-and-project-action-feed-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-32-supervisor-skill-orchestration-and-governed-event-loop-implementation-pack-v1.md`
- `x-terminal/Sources/Supervisor/`
- `x-terminal/Sources/Hub/`
- `x-terminal/Sources/Tools/`

## Runtime Signals

These files are common first-stop signals during local debugging:

- `hub_launch_status.json`
- `hub_launch_history.json`
- `hub_status.json`
- `bridge_status.json`
- `ai_runtime_status.json`
- `grpc_denied_attempts.json`
- `grpc_devices_status.json`

Storage base selection reference:

- `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/HubLaunchStatus.swift`

## Working Source Of Truth

Use these documents as the primary state references:

- `X_MEMORY.md`
- `docs/memory-new/xhub-lane-command-board-v2.md`
- `x-terminal/work-orders/README.md`

For memory-backed safety and constitutional behavior, start with:

- `X_MEMORY.md`
- `docs/xhub-constitution-l0-injection-v1.md`
- `docs/xhub-constitution-l1-guidance-v1.md`
- `docs/xhub-constitution-policy-engine-checklist-v1.md`

If those disagree with an older task note, prefer the newer active source and verify before editing code.

## Archived And Generated Paths

Do not use these as active implementation entrypoints:

- `archive/x-terminal-legacy/`
- `build/`
- `data/`

Archived paths are history. Generated paths are outputs.

## When Resuming Work

If you are picking the project back up after a gap:

1. Read `README.md`
2. Read `docs/REPO_LAYOUT.md`
3. Read `X_MEMORY.md`
4. Check `docs/memory-new/xhub-lane-command-board-v2.md`
5. Open the relevant module README before editing code
