# Multi-AI Secondary Work Orders

- date: `2026-03-27`
- purpose:
  - split the current parallel round into one feature per AI
  - keep write scopes disjoint enough that workers do not collide
  - make handoff decisions from feature boundaries rather than from broad lanes
- use this board when:
  - 4 AI workers continue in parallel from the current branch
  - the goal is low-conflict progress instead of broad refactors

This board is the current execution split for the next parallel round.

Read this after:

1. `docs/repo-inventory/AI_HANDOFF_START_HERE.md`
2. `docs/repo-inventory/MULTI_AI_LANE_DISPATCH_2026-03-27.md`

## Assignment Rules

1. One AI owns one feature only.
2. If a task requires files outside its write-scope, stop and re-dispatch instead of expanding scope ad hoc.
3. Do not assign `SupervisorManager`, `SupervisorView*`, `ProjectSettingsView`, `ProjectsGridView`, `README.md`, `website/`, or repo-wide release gates as part of these secondary work orders.
4. All generated paths remain off-limits:
   - `archive/`
   - `build/`
   - `data/`
   - `**/node_modules/`
   - `x-terminal/.axcoder/reports/**`
   - `x-terminal/.ax-test-cache/`
   - `x-terminal/skills/_projects/`
   - `x-terminal/voice_supervisor_smoke_project/`
5. After landing a slice, update:
   - `docs/repo-inventory/MULTI_AI_LANE_DISPATCH_2026-03-27.md`
   - `docs/repo-inventory/FEATURE_VALIDATION_CHECKLIST.md`

## Current Split

| AI Slot | Work Order | Feature | Primary Write Root | Status |
|---|---|---|---|---|
| `AI-1` | `SWO-A1` | Pending grant action truth closure | `x-terminal/Sources/Hub/` | `ready` |
| `AI-2` | `SWO-B1` | Governance doctor snapshot closure | `x-terminal/Sources/Project/` + narrow doctor export | `ready` |
| `AI-3` | `SWO-C1` | Conversation status-bar presence | `x-terminal/Sources/Supervisor/` + `Sources/UI/Supervisor/` | `ready` |
| `AI-4` | `SWO-D1` | Official skills doctor contract adoption | `x-hub/grpc-server/hub_grpc_server/src/` | `ready` |

## SWO-A1

- id: `SWO-A1`
- owner slot: `AI-1`
- scope: `xt`
- priority: `P0`
- role: `child`
- start-here: `yes`
- label: `Pending grant action truth closure`
- parent refs:
  - `x-terminal/work-orders/xt-w1-03-pending-grants-source-of-truth.md`
  - `x-terminal/work-orders/xt-w1-04-high-risk-grant-enforcement.md`
  - `x-terminal/work-orders/xt-w1-02-route-state-machine.md`
- feature-checklist mapping:
  - `Route Truth, Fallback, And Actual-Route Visibility`
  - `Pairing / Discovery / Doctor / Repair Loop`
- objective:
  - finish the XT-side pending-grant truth chain so `approve / deny / open` actions and blocked reasons come from the same Hub snapshot semantics
  - eliminate dead-end states where XT knows execution is blocked but cannot explain whether the issue is missing pending grant, denied route, or unreachable remote snapshot
- write-scope:
  - `x-terminal/Sources/Hub/HubIPCClient.swift`
  - optional only if strictly required: `x-terminal/Sources/Hub/HubPairingCoordinator.swift`
  - `x-terminal/Tests/XTHubGrantPresentationTests.swift`
  - `x-terminal/Tests/SupervisorPendingHubGrantPresentationTests.swift`
  - `x-terminal/Tests/HubIPCClientRequestFailureDiagnosticsTests.swift`
- avoid:
  - `x-terminal/Sources/Supervisor/`
  - `x-terminal/Sources/UI/`
  - `x-terminal/Sources/Project/`
  - `x-hub/*`
- deliver:
  - one truth path for pending-grant action availability
  - one machine-readable fallback/unreachable reason vocabulary
  - no silent drift between Hub client diagnostics and Supervisor grant presentation
- validate:
  - `cd x-terminal && swift test --filter XTHubGrantPresentationTests`
  - `cd x-terminal && swift test --filter SupervisorPendingHubGrantPresentationTests`
  - `cd x-terminal && swift test --filter HubIPCClientRequestFailureDiagnosticsTests`
  - `cd x-terminal && swift run XTerminal --xt-grant-smoke`
- done-when:
  - pending grant rows expose stable actions and failure reason text from the same route truth
  - `grpc` fail-closed behavior does not regress
  - no UI-only fallback wording is invented outside the Hub client path
- why-non-conflicting:
  - this feature stays inside XT Hub-client and grant-presentation files only

## SWO-B1

- id: `SWO-B1`
- owner slot: `AI-2`
- scope: `xt`
- priority: `P0`
- role: `child`
- start-here: `yes`
- label: `Governance doctor snapshot closure`
- parent refs:
  - `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-36-b-project-governance-surface-split-implementation-pack-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`
  - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
- feature-checklist mapping:
  - `Project Governance A0..A4 + S0..S4`
  - `Durable Writer Boundary And Memory Export Guardrails`
- objective:
  - close the last doctor/export projection gap so configured governance, effective governance, and memory truth labels stay consistent across project detail, doctor export, and runtime summary
  - keep this as a projection/evidence slice rather than a settings-page redesign
- write-scope:
  - `x-terminal/Sources/Project/XTGovernanceTruthPresentation.swift`
  - `x-terminal/Sources/UI/XHubDoctorOutput.swift`
  - `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
  - optional only if required for projection text: `x-terminal/Sources/Project/XTMemorySourceTruthPresentation.swift`
  - `x-terminal/Tests/XTDoctorMemoryTruthClosureEvidenceTests.swift`
  - `x-terminal/Tests/XHubDoctorOutputTests.swift`
  - `x-terminal/Tests/XTUnifiedDoctorReportTests.swift`
- avoid:
  - `x-terminal/Sources/Supervisor/`
  - `x-terminal/Sources/UI/ProjectSettingsView.swift`
  - `x-terminal/Sources/UI/Projects/`
  - `x-terminal/Sources/Project/AXProjectGovernanceResolver.swift`
  - `x-terminal/scripts/ci/xt_release_gate.sh`
- deliver:
  - doctor/export payload carries the same configured/effective governance snapshot used by XT presentation
  - memory-route truth fields do not invent a second local vocabulary
  - doctor output remains machine-readable and compatible with the current schema/export path
- validate:
  - `cd x-terminal && swift test --filter XTGovernanceTruthPresentationTests`
  - `cd x-terminal && swift test --filter XTDoctorMemoryTruthClosureEvidenceTests`
  - `cd x-terminal && swift test --filter XHubDoctorOutputTests`
  - `cd x-terminal && swift test --filter XTUnifiedDoctorReportTests`
- done-when:
  - doctor export, project detail, and runtime summary no longer disagree on configured vs effective labels
  - governance/memory source projections are stable enough to use for manual feature validation
- why-non-conflicting:
  - this feature stays in Project plus doctor-export seams and does not touch Supervisor runtime files

## SWO-C1

- id: `SWO-C1`
- owner slot: `AI-3`
- scope: `xt`
- priority: `P0`
- role: `child`
- start-here: `yes`
- label: `Conversation status-bar presence`
- parent refs:
  - `x-terminal/work-orders/xt-w3-29-supervisor-conversation-window-persistent-session-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-29-supervisor-voice-progress-and-guided-authorization-implementation-pack-v1.md`
  - `x-terminal/work-orders/xt-w3-40-supervisor-device-local-calendar-reminders-implementation-pack-v1.md`
- feature-checklist mapping:
  - `Supervisor Voice / Guided Authorization` implied under current Supervisor main loop
  - `Calendar reminder defer / notification fallback` runtime coupling
- objective:
  - make the conversation-session seam visible in the status-bar/window shell so the user can see active state, TTL, and reason/event without opening broad Supervisor dashboards
  - keep the change narrow and compatible with the landed session controller
- write-scope:
  - `x-terminal/Sources/Supervisor/SupervisorConversationWindowBridge.swift`
  - `x-terminal/Sources/UI/Supervisor/SupervisorStatusBar.swift`
  - optional only if wiring requires it: `x-terminal/Sources/Voice/VoiceSessionCoordinator.swift`
  - `x-terminal/Tests/SupervisorConversationWindowBridgeTests.swift`
  - `x-terminal/Tests/SupervisorConversationSessionIntegrationTests.swift`
  - optional only if touched: `x-terminal/Tests/VoiceSessionCoordinatorTests.swift`
- avoid:
  - `x-terminal/Sources/Supervisor/SupervisorManager.swift`
  - `x-terminal/Sources/Supervisor/SupervisorView.swift`
  - `x-terminal/Sources/Supervisor/SupervisorViewContent.swift`
  - `x-terminal/Sources/Supervisor/SupervisorDashboardBoards.swift`
  - `x-terminal/Sources/Project/`
  - doctor/export files owned by `SWO-B1`
- deliver:
  - status bar reflects `window_state`, `remaining_ttl_sec`, `reason_code`, and latest session-event semantics
  - timeout / user-turn / assistant-turn updates do not leave stale status-bar state behind
  - calendar-reminder defer behavior continues to respect active conversation state
- validate:
  - `cd x-terminal && swift test --filter SupervisorConversationWindowBridgeTests`
  - `cd x-terminal && swift test --filter SupervisorConversationSessionIntegrationTests`
  - `cd x-terminal && swift run XTerminal --xt-supervisor-voice-smoke --project-root "$(pwd)" --out-json .axcoder/reports/xt_supervisor_voice_smoke.runtime.json`
  - `bash x-terminal/scripts/ci/xt_w3_40_calendar_boundary_evidence.sh`
- done-when:
  - the status bar can explain whether conversation is hidden, armed, or conversing using the landed session seam
  - TTL expiry and session-event updates are visible without entering the large dashboard codepath
- why-non-conflicting:
  - this feature is isolated to Supervisor session shell and status-bar UI

## SWO-D1

- id: `SWO-D1`
- owner slot: `AI-4`
- scope: `hub`
- priority: `P0`
- role: `child`
- start-here: `yes`
- label: `Official skills doctor contract adoption`
- parent refs:
  - `docs/memory-new/xhub-governed-package-productization-work-orders-v1.md`
  - `x-terminal/work-orders/xt-skills-compat-reliability-work-orders-v1.md`
  - `x-terminal/work-orders/xt-l1-skills-ux-preflight-runner-contract-v1.md`
- feature-checklist mapping:
  - `Governed Package Shell`
  - `Official Skills Doctor`
  - `Compatibility Gates`
- objective:
  - adopt the newly frozen governed-package doctor/registry semantics inside the Hub official-skills runtime path
  - remove ad hoc doctor failure wording where stable `failure_code`, `failure_source`, `next_step`, and source-fallback semantics should exist
- write-scope:
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`
  - optional only if strictly required by runtime sync behavior: `x-hub/grpc-server/hub_grpc_server/src/official_skill_channel_sync.js`
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store_official_package_doctor.test.js`
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store_official_agent_catalog.test.js`
  - optional only if compatibility fixtures need a touch: `x-hub/grpc-server/hub_grpc_server/src/skills_store_manifest_compat.test.js`
- avoid:
  - `README.md`
  - `website/`
  - `x-hub/python-runtime/`
  - XT UI / XT Supervisor surfaces
- deliver:
  - official skills doctor output uses schema-aligned failure codes and next-step hints
  - source fallback is surfaced honestly rather than as generic catalog failure text
  - XT-side skills surfaces can trust Hub doctor output instead of guessing local categories
- validate:
  - `node x-hub/grpc-server/hub_grpc_server/src/skills_store_official_package_doctor.test.js`
  - `node x-hub/grpc-server/hub_grpc_server/src/skills_store_official_agent_catalog.test.js`
  - `node x-hub/grpc-server/hub_grpc_server/src/skills_store_manifest_compat.test.js`
  - `node scripts/m3_check_skills_grant_chain_contract.js`
  - `node x-terminal/scripts/check_skills_xt_l1_contract.js`
- done-when:
  - doctor/runtime output reflects the frozen package contract rather than free-form error text
  - no XT compatibility test needs to special-case legacy Hub doctor wording for this feature path
- why-non-conflicting:
  - this feature stays in Hub skills runtime and package tests only

## Not Safe To Split In Parallel Right Now

Do not assign these as part of the same round unless the branch becomes cleaner:

- `xt_release_gate.sh` repair
- `xt_w3_36_project_governance_evidence.sh` stabilization
- `SupervisorMultilaneFlowTests` fixes
- `SupervisorAutoContinueExecutorTests` fixes
- trust-profile full UI productization
- local-provider-pack broad runtime adoption

These are cross-surface and would pull multiple workers into the same files.
