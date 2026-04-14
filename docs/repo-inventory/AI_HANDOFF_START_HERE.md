# AI Handoff Start Here

This is the single-file handoff entrypoint for AI collaborators.

Use it when a new AI needs to pick up work without rediscovering the repo structure, or when the branch is noisy enough that old status files and generated reports are more confusing than helpful.

## Mandatory Read Order

Read these files in order before writing code:

1. `README.md`
2. `X_MEMORY.md`
3. `docs/WORKING_INDEX.md`
4. `docs/repo-inventory/README.md`
5. this file
6. `docs/repo-inventory/MULTI_AI_LANE_DISPATCH_2026-03-27.md`
7. `docs/repo-inventory/MULTI_AI_SECONDARY_WORK_ORDERS_2026-03-27.md` when one feature is being assigned to one AI
8. the owning work-order pack for the lane you are taking

## Specialized Entry

If the immediate task is specifically capability semantics, grant/readiness interpretation, project capability bundle ceiling, runtime deny vocabulary, doctor truth, or route truth, read this right after the mandatory list above before claiming a lane:

- `docs/repo-inventory/CAPABILITY_AI_HANDOFF_2026-03-30.md`

## Ignore First

These paths are not valid default entrypoints for implementation handoff:

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

If a file only exists under one of those paths, do not assign it to another AI unless the task explicitly targets generated evidence or recovery artifacts.

## Do Not Start From These By Default

These files may still contain useful history, but they are not the default handoff truth anymore:

- `x-terminal/PROJECT_STATUS.md`
- `x-terminal/DOC_STATUS_DASHBOARD.md`
- ad hoc evidence bundles under `docs/open-source/evidence/`
- runtime snapshots under `build/` or `.axcoder/reports/`

Primary coordination truth has moved to `docs/repo-inventory/`.

For the current parallel round, prefer `docs/repo-inventory/MULTI_AI_SECONDARY_WORK_ORDERS_2026-03-27.md` over broad lane-level dispatch whenever one AI is expected to own exactly one feature.

## Lane Pick Guide

### Lane A

- label: `Trust / Connect foundation`
- read next:
  - `docs/repo-inventory/MULTI_AI_LANE_DISPATCH_2026-03-27.md`
  - `x-terminal/work-orders/xt-w1-02-route-state-machine.md`
  - `x-terminal/work-orders/xt-w1-03-pending-grants-source-of-truth.md`
  - `x-terminal/work-orders/xt-w1-04-high-risk-grant-enforcement.md`
- own by default:
  - `x-terminal/Sources/Hub/`
  - `x-terminal/Tests/Hub*`
- avoid:
  - `x-terminal/Sources/Supervisor/`
  - `x-terminal/Sources/UI/`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/`
  - `x-hub/grpc-server/hub_grpc_server/src/`
- validation:
  - `cd x-terminal && swift test --filter HubRouteStateMachineTests`
  - `cd x-terminal && swift run XTerminal --xt-route-smoke`
  - `cd x-terminal && swift run XTerminal --xt-grant-smoke`
  - `bash x-terminal/scripts/ci/xt_route_truth_snapshot_check.sh`
- current status:
  - first transport-truth slice landed on `2026-03-27`
  - pending-grant route semantics aligned for `auto | grpc | file`

### Lane B

- label: `Memory / Governance trunk`
- read next:
  - `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
  - `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-36-b-project-governance-surface-split-implementation-pack-v1.md`
- own by default:
  - `x-terminal/Sources/Project/`
  - selected governance presentation seams
- avoid:
  - `x-terminal/Sources/UI/ProjectSettingsView.swift`
  - `x-terminal/Sources/UI/Projects/`
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - repo-wide schema or Hub runtime roots unless the work order explicitly expands scope
- validation:
  - `cd x-terminal && swift test --filter ProjectGovernanceResolverTests`
  - `cd x-terminal && swift test --filter XTGovernanceTruthPresentationTests`
  - `cd x-terminal && swift test --filter XTDoctorMemoryTruthClosureEvidenceTests`
  - `bash x-terminal/scripts/ci/xt_w3_36_project_governance_evidence.sh`
- current status:
  - XT-only governance truth closure landed on `2026-03-27`
  - targeted tests passed
  - evidence script still fails on pre-existing `SupervisorMultilaneFlowTests`

### Lane C

- label: `Supervisor / Voice / main interaction loop`
- read next:
  - `x-terminal/work-orders/xt-w3-21-w3-22-supervisor-intake-acceptance-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-26-supervisor-one-shot-intake-adaptive-pool-planner-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-29-supervisor-conversation-window-persistent-session-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-29-supervisor-voice-progress-and-guided-authorization-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-39-hub-voice-pack-and-supervisor-tts-implementation-pack-v1.md`
- own by default:
  - `x-terminal/Sources/Supervisor/`
  - `x-terminal/Sources/Voice/`
  - selected XT supervisor UI seams
- avoid:
  - `x-terminal/Sources/Project/`
  - large dashboard reshapes in `SupervisorView*`
  - Hub runtime roots
- validation:
  - `cd x-terminal && swift run XTerminal --xt-supervisor-voice-smoke --project-root "$(pwd)" --out-json .axcoder/reports/xt_supervisor_voice_smoke.runtime.json`
  - `bash x-terminal/scripts/ci/xt_release_gate.sh`
  - `bash x-terminal/scripts/ci/xt_w3_40_calendar_boundary_evidence.sh`
- current status:
  - first session-seam slice landed on `2026-03-27`
  - voice smoke and calendar boundary evidence passed
  - release gate and governance evidence script still fail on pre-existing branch noise
  - treat this lane as the noisiest lane; take only narrow seams

### Lane D

- label: `Capability productization`
- read next:
  - `docs/memory-new/xhub-governed-package-productization-work-orders-v1.md`
  - `docs/memory-new/xhub-local-provider-runtime-transformers-work-orders-v1.md`
  - `docs/memory-new/xhub-work-order-8-9-closure-checklist-v1.md`
  - `x-terminal/work-orders/xt-skills-compat-reliability-work-orders-v1.md`
- own by default:
  - `x-hub/python-runtime/`
  - package/schema/docs seams
  - narrow skills/package tests
- avoid:
  - `README.md`
  - `website/`
  - `x-hub/macos/RELFlowHub/Sources/RELFlowHub/`
  - `x-terminal/Sources/UI/`
- validation:
  - `node x-hub/grpc-server/hub_grpc_server/src/skills_store_manifest_compat.test.js`
  - `node x-hub/grpc-server/hub_grpc_server/src/skills_store_official_package_doctor.test.js`
  - `node x-hub/grpc-server/hub_grpc_server/src/skills_store_official_agent_catalog.test.js`
  - `node scripts/m3_check_skills_grant_chain_contract.js`
  - `node x-terminal/scripts/check_skills_xt_l1_contract.js`
- current status:
  - governed package contract-freeze slice landed on `2026-03-27`
  - schema-level validation passed

## Required Handoff Block

Before an AI starts implementation, it should restate these fields:

- `scope`
- `priority`
- `role`
- `start-here`
- `write-scope`
- `avoid`
- `validate`

If any of those are missing, the AI is not ready to write.

## Completion Rule

After landing a slice:

1. update `docs/repo-inventory/MULTI_AI_LANE_DISPATCH_2026-03-27.md`
2. map the landed behavior back into `docs/repo-inventory/FEATURE_VALIDATION_CHECKLIST.md`
3. note any new non-source noise path here if the branch produced one
