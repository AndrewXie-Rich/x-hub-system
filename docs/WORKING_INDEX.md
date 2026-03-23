# Working Index

This is the working navigation page for the active repository surface.

Use it to answer three questions quickly:

1. What should I read first?
2. Where does the active code live?
3. Which document is the source of truth for the task I am touching?

This page is a working map, not a release-scope expansion document.
Each document should appear here under one primary track whenever possible; if a topic spans multiple areas, prefer its primary track first and use the task sections below for code entry points.

## Read Order

If you are entering the repository cold, read in this order:

1. `README.md`
2. `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`
3. `docs/open-source/XHUB_V1_PRODUCT_BOUNDARY_AND_PRIORITIES_v1.md`
4. `docs/open-source/XHUB_NEXT_4_WEEKS_EXECUTION_PLAN_v1.md`
5. `docs/open-source/XHUB_NEXT_10_WORK_ORDERS_v1.md`
6. `docs/REPO_LAYOUT.md`
7. `X_MEMORY.md`
8. `docs/memory-new/xhub-memory-updates-2026q1.md`
9. `x-hub/README.md`
10. `x-terminal/README.md`

After that, choose the relevant track below.

## Primary Truth Sources

- `README.md`
  - Public product scope and validated preview claims.
- `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`
  - Surface-by-surface capability state for public preview and active delivery.
- `docs/open-source/XHUB_V1_PRODUCT_BOUNDARY_AND_PRIORITIES_v1.md`
  - V1 must-ship boundary, should-ship next, and what should be frozen or deprioritized.
- `docs/open-source/XHUB_NEXT_4_WEEKS_EXECUTION_PLAN_v1.md`
  - The current four-week execution sequence: three lanes, weekly demo loop, done criteria, and freeze list.
- `docs/open-source/XHUB_NEXT_10_WORK_ORDERS_v1.md`
  - Concrete next-10 backlog for human maintainers and AI collaborators.
- `X_MEMORY.md`
  - Fixed decisions, current state, current next steps.
- `docs/memory-new/xhub-memory-updates-2026q1.md`
  - Dated updates, rollout notes, and execution log moved out of `X_MEMORY.md`.
- `docs/WORKING_INDEX.md`
  - Curated working map and task-first navigation.
- `docs/memory-new/xhub-lane-command-board-v2.md`
  - Active multi-lane coordination board.
- `x-terminal/work-orders/README.md`
  - Priority-ordered X-Terminal work-order entrypoint for AI collaborators and human maintainers.

## Current High-Value Tracks

### Public Preview And External Positioning

- `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`
- `docs/open-source/XHUB_V1_PRODUCT_BOUNDARY_AND_PRIORITIES_v1.md`
- `docs/open-source/XHUB_NEXT_4_WEEKS_EXECUTION_PLAN_v1.md`
- `docs/open-source/XHUB_NEXT_10_WORK_ORDERS_v1.md`
- `docs/open-source/XHUB_PUBLIC_ADOPTION_ROADMAP_v1.md`
- `docs/open-source/PUBLIC_PREVIEW_SCRUB_NOTES_v1.md`
- `docs/memory-new/xhub-ironclaw-reference-adoption-checklist-v1.md`

Start here when the question is "what can we honestly claim now?", "what is actually in v1 scope?", "what should the next 4 weeks optimize for?", "which work-order family should land next?", "what are the next 10 concrete default tasks?", "which IronClaw-inspired shell should land next?", or "is this surface validated, preview-working, or only protocol-frozen?"

### Product And Runtime

- `docs/xhub-scenario-map-v1.md`
- `docs/xhub-runtime-stability-and-launch-recovery-v1.md`
- `docs/memory-new/schema/xhub_doctor_output_contract.v1.json`
- `docs/memory-new/schema/xt_unified_doctor_report_contract.v1.json`
- `docs/xhub-local-provider-runtime-and-transformers-integration-v1.md`
- `docs/memory-new/README-local-provider-runtime-productization-v1.md`
- `docs/memory-new/xhub-local-provider-runtime-require-real-runbook-v1.md`
- `scripts/lpr_w3_03_require_real_status.js`
- `docs/memory-new/xhub-local-bench-fixture-pack-v1.md`
- `docs/xhub-client-modes-and-connectors-v1.md`
- `docs/xhub-hub-architecture-tradeoffs-v1.md`
- `docs/memory-new/xhub-multimodal-supervisor-control-plane-architecture-memo-v1.md`
- `docs/memory-new/xhub-multimodal-supervisor-control-plane-contract-freeze-v1.md`
- `docs/memory-new/xhub-multimodal-supervisor-control-plane-work-orders-v1.md`

### Memory And Constitutional Safety

- `X_MEMORY.md`
- `docs/memory-new/xhub-memory-updates-2026q1.md`
- `docs/memory-new/xhub-memory-control-plane-migration-impact-table-v1.md`
- `docs/memory-new/xhub-memory-control-plane-gap-check-v1.md`
- `docs/memory-new/xhub-memory-core-recipe-asset-versioning-freeze-v1.md`
- `docs/memory-new/xhub-memory-model-preferences-and-routing-contract-v1.md`
- `docs/memory-new/xhub-memory-open-source-reference-adoption-checklist-v1.md`
- `docs/memory-new/xhub-memory-open-source-reference-wave0-execution-pack-v1.md`
- `docs/memory-new/xhub-memory-open-source-reference-wave0-implementation-slices-v1.md`
- `docs/memory-new/xhub-memory-open-source-reference-wave1-execution-pack-v1.md`
- `docs/memory-new/xhub-memory-open-source-reference-wave1-implementation-slices-v1.md`
- `docs/memory-new/xhub-memory-serving-profiles-and-adaptive-context-v1.md`
- `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`
- `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md`
- `docs/xhub-memory-system-spec-v2.md`
- `docs/xhub-memory-hybrid-index-v1.md`
- `docs/xhub-memory-fusion-v1.md`
- `specs/xhub-memory-quality-v1/`
- `docs/xhub-constitution-l0-injection-v1.md`
- `docs/xhub-constitution-l1-guidance-v1.md`
- `docs/xhub-constitution-policy-engine-checklist-v1.md`

If you are tracing behavior boundaries, risk controls, fail-closed reasoning, the current Wave-0 / Wave-1 hardening path for memory routing / retrieval / reconcile / sidecar / blob ACL, or the current “memory control-plane migration” decision about `Memory-Core` vs `Scheduler/Worker/Writer`, start here before reading feature-specific implementation packs. The current frozen interpretation is: user chooses which AI executes memory jobs, `Memory-Core` remains a governed rule asset, and durable truth still only lands through `Writer + Gate`. If the immediate question is “do we really need new work orders for this control-plane migration, or can existing packs absorb it?”, read `docs/memory-new/xhub-memory-control-plane-gap-check-v1.md` right after the migration impact table, then read `docs/memory-new/xhub-memory-core-recipe-asset-versioning-freeze-v1.md` before opening any new work-order family; that freeze doc is the current minimum scope guardrail for `Memory-Core` versioning, cold update, rollback, audit, and doctor exposure. For live Wave-1 parent landing, continue from this track into the surface-specific parent docs under Security / Governance / Product tracks: `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`, `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`, `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`, and `docs/memory-new/xhub-multimodal-supervisor-control-plane-work-orders-v1.md`.

Docs-truth hook for this boundary:

- `x-terminal/Tests/MemoryControlPlaneDocsSyncTests.swift`

### Governed Packages And Skills

- `official-agent-skills/`
- `docs/memory-new/xhub-governed-package-productization-work-orders-v1.md`
- `docs/memory-new/schema/xhub_governed_package_manifest.v1.json`
- `docs/memory-new/schema/xhub_package_registry_entry.v1.json`
- `docs/memory-new/schema/xhub_package_doctor_output_contract.v1.json`
- `docs/memory-new/xhub-agent-asset-reuse-map-v1.md`
- `docs/memory-new/xhub-dynamic-official-agent-skills-governance-work-orders-v1.md`
- `docs/memory-new/xhub-official-agent-skills-signing-sync-and-hub-signer-work-orders-v1.md`
- `docs/xhub-skills-placement-and-execution-boundary-v1.md`
- `docs/xhub-skills-discovery-and-import-v1.md`
- `docs/xhub-skills-signing-distribution-and-runner-v1.md`
- `docs/skills_abi_compat.v1.md`
- `docs/skills_import_bridge_contract.v1.md`

### Governance And Supervisor

- `docs/memory-new/xhub-governed-autonomy-switchboard-productization-work-orders-v1.md`
- `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
- `docs/memory-new/schema/xhub_project_autonomy_and_supervisor_review_contract.v1.json`
- `docs/memory-new/xhub-supervisor-adaptive-intervention-and-work-order-depth-work-orders-v1.md`
- `docs/memory-new/xhub-supervisor-event-loop-stability-work-orders-v1.md`
- `docs/memory-new/xhub-supervisor-memory-serving-contract-v1.md`
- `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
- `docs/memory-new/xhub-supervisor-memory-compatibility-guardrails-v1.md`
- `docs/memory-new/xhub-supervisor-recent-raw-context-policy-v1.md`
- `docs/memory-new/xhub-supervisor-dual-plane-memory-assembly-v1.md`
- `docs/memory-new/xhub-project-ai-context-depth-policy-v1.md`
- `docs/memory-new/xhub-supervisor-memory-serving-work-orders-v1.md`
- `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-36-b-project-governance-surface-split-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-38-supervisor-personal-longterm-assistant-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-38-i6-supervisor-memory-routing-and-assembly-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-38-i7-supervisor-continuity-floor-and-context-depth-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-38-h-supervisor-persona-center-implementation-pack-v1.md`

`XT-W3-36-B` is now completed. Use the parent `XT-W3-36` pack as the live governance roadmap, and keep `x-terminal/work-orders/xt-w3-36-b-project-governance-surface-split-implementation-pack-v1.md` only as the landed UI split reference.

Governance product truth is now split into `Execution Tier` (`A0..A4`, with highest label `A4 Agent`), `Supervisor Tier` (`S0..S4`), and independent `Heartbeat & Review`.

Release and docs-truth hooks for this surface:

- `x-terminal/scripts/ci/xt_w3_36_project_governance_evidence.sh`
- `x-terminal/scripts/ci/xt_release_gate.sh`
- `x-terminal/Tests/ProjectGovernanceDocsTruthSyncTests.swift`

If the task is specifically about "Supervisor forgets recent turns", "personal + project memory should merge more naturally", or "project coder context is too thin", start from `docs/memory-new/xhub-supervisor-memory-compatibility-guardrails-v1.md`, `docs/memory-new/xhub-supervisor-recent-raw-context-policy-v1.md`, `docs/memory-new/xhub-supervisor-dual-plane-memory-assembly-v1.md`, `docs/memory-new/xhub-project-ai-context-depth-policy-v1.md`, and `x-terminal/work-orders/xt-w3-38-i7-supervisor-continuity-floor-and-context-depth-implementation-pack-v1.md`.

For current runtime truth, keep the explainability chain in mind: `ProjectSettingsView` shows `Last Runtime Assembly`, `XTUnifiedDoctor` shows a `Project Context` summary inside `session_runtime_readiness`, `XTUnifiedDoctor` also carries first-class `durableCandidateMirrorProjection` on `session_runtime_readiness` and `memoryRouteTruthProjection` on `model_route_readiness`, and the generic XT doctor export now mirrors those projections as `project_context_summary`, `durable_candidate_mirror_snapshot`, and `memory_route_truth_snapshot` instead of leaving them only in raw `detail_lines`.

### Security And Gates

- `docs/memory-new/xhub-security-innovation-work-orders-v1.md`
- `docs/memory-new/xhub-spec-gates-work-orders-v1.md`
- `docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md`
- `docs/memory-new/xhub-trusted-automation-mode-work-orders-v1.md`
- `docs/memory-new/xhub-trusted-automation-device-execution-plane-implementation-pack-v1.md`
- `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`
- `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
- `scripts/m3_check_xt_ready_gate.js`
- `scripts/m3_generate_xt_ready_e2e_evidence.js`
- `scripts/m3_extract_xt_ready_incident_events_from_audit.js`
- `scripts/m3_resolve_xt_ready_audit_input.js`
- `scripts/m3_export_xt_ready_audit_from_db.js`
- `scripts/m3_fetch_connector_ingress_gate_snapshot.js`
- `scripts/xt_ready_release_diagnostics.js`

### X-Terminal Execution Packs

- `x-terminal/work-orders/README.md`
- `x-terminal/work-orders/xterminal-parallel-work-orders-v1.md`
- `x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md`
- `x-terminal/work-orders/xt-w3-23-memory-ux-adapter-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-24-multichannel-gateway-productization-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-24-supervisor-operator-channels-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-24-safe-operator-channel-onboarding-automation-implementation-pack-v1.md`
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
- `x-terminal/work-orders/xt-w3-37-agent-ui-observation-and-governed-visual-review-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-39-hub-voice-pack-and-supervisor-tts-implementation-pack-v1.md`
  - XT side groundwork for `Speech Language / Voice Color / Speech Rate` is landed; use this pack as the parent truth before touching Hub TTS runtime or marketplace wiring.
- `x-terminal/work-orders/xt-w3-40-supervisor-device-local-calendar-reminders-implementation-pack-v1.md`
  - Use this pack when moving personal calendar reminders off Hub and into XT-local Supervisor voice reminders without syncing raw calendar events back to Hub.
  - Current state: Hub-side calendar de-scope is landed, XT-side preview/live reminder entrypoints are landed, and the next required step is real-device smoke on `X-Terminal.app`.
  - Evidence hook: `x-terminal/scripts/ci/xt_w3_40_calendar_boundary_evidence.sh`

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

Use the primary tracks above as the main document entrypoints.
This section only lists active packs that are still useful but are not the primary anchor for a top-level track:

- `docs/memory-new/xhub-agent-skill-vetter-gate-work-orders-v1.md`
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
bash x-terminal/tools/run_xterminal_from_source.command
```

### Run Unified Doctor From Source

```bash
bash scripts/run_xhub_doctor_from_source.command hub --out-json /tmp/xhub_doctor_output_hub.json
bash scripts/run_xhub_doctor_from_source.command xt --workspace-root /path/to/workspace --out-json /tmp/xhub_doctor_output_xt.json
bash scripts/run_xhub_doctor_from_source.command all --workspace-root /path/to/workspace --out-dir /tmp/xhub_doctor_bundle
```

The XT export includes a structured `project_context_summary` on `session_runtime_readiness` whenever recent coder usage exists for the active project. Use that field when you need a machine-readable explanation of what project dialogue window and context depth actually reached the project AI.

The XT export also includes a structured `memory_route_truth_snapshot` on `model_route_readiness` whenever XT has route diagnostics to project. Read `projection_source` and `completeness` first: they tell you whether you are looking at full upstream route truth or an explicit XT partial projection with `unknown` placeholders.

The XT-native source report envelope is frozen separately in `docs/memory-new/schema/xt_unified_doctor_report_contract.v1.json`, so `xt_unified_doctor_report.json` can evolve as a first-class XT contract while the normalized `xhub_doctor_output_xt.json` export remains surface-neutral. `consumedContracts` should therefore carry `xt.unified_doctor_report_contract.v1` rather than echoing the source report schema version as if it were an upstream dependency.

For a focused XT-only source smoke:

```bash
bash scripts/smoke_xhub_doctor_xt_source_export.sh
```

This focused smoke now verifies that XT export carries structured `project_context_summary` inside `session_runtime_readiness` and structured `memory_route_truth_snapshot` inside `model_route_readiness`.

For an isolated aggregate snapshot-based smoke of the current repo-level doctor shell:

```bash
bash scripts/smoke_xhub_doctor_all_source_export.sh
```

For a CI-facing wrapper test + aggregate source-run gate:

```bash
bash scripts/ci/xhub_doctor_source_gate.sh
```

That gate now emits `build/reports/xhub_doctor_source_gate_summary.v1.json`, `build/reports/xhub_doctor_xt_source_smoke_evidence.v1.json`, and `build/reports/xhub_doctor_all_source_smoke_evidence.v1.json`. The summary also exposes `project_context_summary_support`, `durable_candidate_mirror_support`, and `memory_route_truth_support` so release evidence can reuse the same structured XT project-context, supervisor handoff, and route-truth assertions. The project-context support block keeps `source_badge / status_line` together with the dialogue/depth metrics, while the durable-candidate mirror block keeps `status / target / attempted / local_store_role`, instead of forcing downstream tools to re-parse raw XT `detail_lines`.

When you also need release/operator wording for Hub-managed local runtime recovery, run `node scripts/generate_xhub_local_service_operator_recovery_report.js` or just use `bash scripts/refresh_oss_release_evidence.sh`; the downstream boundary/readiness bundle and `build/reports/lpr_w4_09_c_product_exit_packet.v1.json` will consume the same machine-readable `action_category / external_status_line / top_recommended_action`. The product-exit packet also exposes `release_refresh_preflight.missing_inputs[]`, so you can see exactly which upstream release artifacts are still blocking the full refresh helper, including the selected XT-ready report/source plus matching connector snapshot chain.

The same XT-ready priority now applies consistently across refresh, compat, product-exit, and internal-pass helpers: `require_real -> db_real -> current`.

If the refresh helper is blocked only because older XT release-era file names disappeared from `build/reports/`, use `node scripts/generate_release_legacy_compat_artifacts.js`. That compat pack recreates the legacy artifact names from current XT/Hub source truth, writes `build/reports/release_legacy_compat_pack.v1.json`, and keeps release status fail-closed instead of fabricating green release readiness.

### Build X-Terminal

```bash
cd x-terminal
swift build
```

### Run The XT Release Gate

```bash
bash x-terminal/scripts/ci/xt_release_gate.sh
```

### Refresh OSS Release Evidence

```bash
bash scripts/refresh_oss_release_evidence.sh
```

The refresh helper now accepts the preferred XT-ready release evidence chain in this order: `build/xt_ready_gate_e2e_require_real_report.json`, then `build/xt_ready_gate_e2e_db_real_report.json`, then `build/xt_ready_gate_e2e_report.json`; it no longer fail-closes just because the legacy current-gate path is absent while a stricter release chain already exists.
The same preferred chain now applies to XT-ready evidence-source and connector-gate artifacts, and `build/reports/xt_ready_release_diagnostics.v1.json` records the selected mode plus the exact report/source/connector refs that were used.

That helper now refreshes `build/reports/xhub_local_service_operator_recovery_report.v1.json` before rebuilding the boundary, secret-scrub, OSS readiness, and `build/reports/lpr_w4_09_c_product_exit_packet.v1.json`.
It also refreshes `build/reports/release_legacy_compat_pack.v1.json` first, so legacy XT-W3 release artifact names are backfilled from current repo truth before the boundary/readiness scripts run.
The boundary step now also writes `build/reports/xt_ready_release_diagnostics.v1.json`, which expands why XT-ready strict release is still blocked, including source selection, runtime incident coverage gaps, Hub DB incident availability, and connector audit-vs-scan state.

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
- `docs/memory-new/xhub-supervisor-adaptive-intervention-and-work-order-depth-work-orders-v1.md`
- `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
- `x-terminal/work-orders/xt-w3-36-b-project-governance-surface-split-implementation-pack-v1.md`
- `x-terminal/scripts/ci/xt_w3_36_project_governance_evidence.sh`
- `x-terminal/scripts/ci/xt_release_gate.sh`
- `x-terminal/Sources/Project/AXProjectConfig.swift`
- `x-terminal/Sources/Project/AXProjectGovernanceResolver.swift`
- `x-terminal/Sources/UI/ProjectSettingsView.swift`
- `x-terminal/Sources/UI/Projects/CreateProjectSheet.swift`
- `x-terminal/Sources/UI/Projects/ProjectDetailView.swift`
- `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- `x-terminal/Tests/ProjectGovernanceDocsTruthSyncTests.swift`

Use the parent `XT-W3-36` pack as the live governance roadmap; keep `XT-W3-36-B` as the completed UI split reference for the dedicated `Execution Tier`, `Supervisor Tier`, and `Heartbeat & Review` surfaces. User-facing governance naming should stay on `A0..A4`, including `A4 Agent`.

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
2. Read `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`
3. Read `docs/open-source/XHUB_V1_PRODUCT_BOUNDARY_AND_PRIORITIES_v1.md`
4. Read `docs/REPO_LAYOUT.md`
5. Read `X_MEMORY.md`
6. Check `docs/memory-new/xhub-lane-command-board-v2.md`
7. Open the relevant module README before editing code
