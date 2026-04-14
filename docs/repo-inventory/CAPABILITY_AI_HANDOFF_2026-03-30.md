# Capability AI Handoff

- date: `2026-03-30`
- purpose:
  - give a new AI one narrow entrypoint for `grant / readiness / capability bundle / action denial / doctor truth / route truth`
  - avoid forcing the next AI to reconstruct capability semantics from chat history
  - keep capability work aligned across Hub JS, XT Swift, Supervisor preflight, runtime deny, and UI explanation layers

Use this file when the task sounds like:

- “capability 到底怎么定义 / 怎么运作”
- “为什么现在是 grant_required / policy_clamped / runtime_unavailable”
- “bundle / readiness / grant / deny / doctor truth / route truth 之间怎么配合”
- “下一位 AI 该改哪层，不该改哪层”

## Read Order

Read these files in order before writing code:

1. `README.md`
2. `X_MEMORY.md`
3. `docs/WORKING_INDEX.md`
4. `docs/memory-new/xhub-capability-operating-model-and-ai-handoff-v1.md`
5. `docs/memory-new/xhub-skill-capability-profiles-and-execution-readiness-contract-v1.md`
6. `docs/memory-new/xhub-skills-capability-grant-chain-contract-v1.md`
7. `docs/memory-new/xhub-ld-trust-capability-route-continuity-and-handoff-v1.md`

Then open the active code roots that match the slice you are taking.

## Capability Stack

Treat the stack as:

`package/manifest truth -> intent families -> capability families -> capability profiles -> grant/approval floor -> execution-tier capability bundle ceiling -> runtime surface clamp -> skill readiness -> supervisor preflight -> tool runtime deny -> governance/doctor/route truth`

Do not collapse these layers into one boolean “allowed / blocked” model.

## Write Scopes By Slice

### Slice A: Canonical Capability Derivation

- own by default:
  - `x-hub/grpc-server/hub_grpc_server/src/skill_capability_derivation.js`
  - `x-hub/grpc-server/hub_grpc_server/src/skills_store.js`
  - `x-hub/grpc-server/hub_grpc_server/src/skill_capability_derivation.test.js`
- use when:
  - family/profile/floor/runtime-surface derivation is wrong or incomplete
  - package normalize path and Hub canonical truth need alignment

### Slice B: XT Capability Helper And Effective Readiness

- own by default:
  - `x-terminal/Sources/Project/XTSkillCapabilityProfileSupport.swift`
  - `x-terminal/Sources/Project/AXSkillsLibrary+HubCompatibility.swift`
  - `x-terminal/Sources/Project/XTProjectSkillRouter.swift`
  - `x-terminal/Tests/AXSkillsCompatibilityTests.swift`
- use when:
  - effective readiness is wrong
  - grant_required / policy_clamped / runtime_unavailable mapping is wrong
  - project profile snapshot or requestable/runnable classification is wrong

### Slice C: Supervisor Preflight Consumption

- own by default:
  - `x-terminal/Sources/Supervisor/SupervisorSkillPreflightGate.swift`
  - narrow supervisor tests related to skill preflight
- use when:
  - Supervisor is interpreting typed readiness incorrectly
  - request-scoped grant override is not flowing into `pass / grantRequired / blocked`

### Slice D: Tool Runtime Deny And Human Explanation

- own by default:
  - `x-terminal/Sources/Tools/XTToolRuntimePolicy.swift`
  - `x-terminal/Sources/Tools/XTGuardrailMessagePresentation.swift`
  - `x-terminal/Sources/Tools/XTHubGrantPresentation.swift`
  - `x-terminal/Sources/Project/ProjectGovernanceInterceptionPresentation.swift`
- use when:
  - actual tool execution and user-facing explanation disagree
  - deny_code / policy_source / repair action drift across surfaces

### Slice E: Project Governance Bundle / Ceiling

- own by default:
  - `x-terminal/Sources/Project/AXProjectExecutionTier.swift`
  - `x-terminal/Sources/Project/AXProjectGovernanceBundle.swift`
  - `x-terminal/Sources/Project/AXProjectGovernanceResolver.swift`
- use when:
  - execution-tier capability ceiling itself is wrong
  - base capability bundle and runtime surface clamp semantics need to change

### Slice F: Route Truth / Doctor Truth

- own by default:
  - `x-terminal/Sources/Project/AXModelRouteDiagnostics.swift`
  - `x-terminal/Sources/Project/XTRouteTruthPresentation.swift`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_onboarding_delivery_readiness.js`
  - `x-hub/grpc-server/hub_grpc_server/src/channel_command_gate.js`
- use when:
  - model route truth or onboarding readiness truth is inconsistent with capability/readiness explanations

## Avoid By Default

Do not take these as part of a capability slice unless the work order explicitly demands them:

- `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- broad `x-terminal/Sources/UI/` reshapes
- `x-terminal/Sources/UI/ProjectSettingsView.swift`
- repo-wide release gates
- unrelated memory assembly roots
- `README.md`
- `website/`

If you need `SupervisorManager.swift`, prove the seam cannot be solved in typed readiness, preflight, or presentation first.

## No-Regression Rules

These are mandatory:

1. `capability bundle` is not the same as `runtime surface`.
2. `profile` is not authority; `verify / pin / revoke / grant / approval` remain authority.
3. `grantRequestId` is not an execution capability token.
4. do not invent a second blocked vocabulary outside typed readiness and runtime deny evidence.
5. keep request-scoped grant override narrow; do not downgrade all `policy_clamped` skills into `grant_required`.
6. if Hub JS derivation changes, review XT Swift derivation for semantic drift.

## Validate

Run only the narrow tests that match your slice.

### Hub Derivation

- `node x-hub/grpc-server/hub_grpc_server/src/skill_capability_derivation.test.js`
- `node scripts/m3_check_skills_grant_chain_contract.js`

### XT Readiness / Router / Capability Surface

- `cd x-terminal && swift test --filter AXSkillsCompatibilityTests`

### Grant / Preflight / Governed Wrapper

- `cd x-terminal && swift test --filter ToolExecutorWebSearchGrantGateTests`
- `cd x-terminal && swift test --filter supervisorSkillPreflightGatePromotesPolicyClampedAgentBrowserReadActionIntoGrantRequired`
- `cd x-terminal && swift test --filter projectAwareGovernanceSurfaceTreatsPureGovernedWebSearchWrapperAsGrantRequestable`
- `cd x-terminal && swift test --filter projectSkillRouterIntentFallbackTreatsPureGovernedWebSearchWrapperAsRequestable`

### Governance Presentation

- `cd x-terminal && swift test --filter XTGovernanceTruthPresentationTests`

## Required Handoff Block

Before writing code, restate:

- `scope`
- `priority`
- `role`
- `start-here`
- `write-scope`
- `avoid`
- `validate`
- `no-regression`

If any field is missing, the AI is not ready to take the slice.

## Single-Screen Prompt

Use this exact prompt when dispatching another AI:

```text
You are taking the X-Hub capability stack slice. Read in order:
1. README.md
2. X_MEMORY.md
3. docs/WORKING_INDEX.md
4. docs/memory-new/xhub-capability-operating-model-and-ai-handoff-v1.md
5. docs/memory-new/xhub-skill-capability-profiles-and-execution-readiness-contract-v1.md
6. docs/memory-new/xhub-skills-capability-grant-chain-contract-v1.md
7. docs/memory-new/xhub-ld-trust-capability-route-continuity-and-handoff-v1.md

Treat the stack as:
package truth -> intent families -> capability families -> capability profiles -> grant/approval floor -> execution-tier capability bundle ceiling -> runtime surface clamp -> skill readiness -> supervisor preflight -> tool runtime deny -> governance/doctor/route truth.

Do not collapse capability bundle, runtime surface, grant, and readiness into one layer.
Do not treat profile as authority.
Do not treat grantRequestId as execution token.
Do not invent a second blocked vocabulary.
Keep request-scoped grant override narrow.

Pick one write scope only:
- Hub derivation: x-hub/grpc-server/hub_grpc_server/src/skill_capability_derivation.js, skills_store.js
- XT readiness/router: x-terminal/Sources/Project/XTSkillCapabilityProfileSupport.swift, AXSkillsLibrary+HubCompatibility.swift, XTProjectSkillRouter.swift
- Supervisor preflight: x-terminal/Sources/Supervisor/SupervisorSkillPreflightGate.swift
- Runtime deny/presentation: x-terminal/Sources/Tools/XTToolRuntimePolicy.swift, XTGuardrailMessagePresentation.swift, XTHubGrantPresentation.swift, ProjectGovernanceInterceptionPresentation.swift
- Governance bundle: AXProjectExecutionTier.swift, AXProjectGovernanceBundle.swift, AXProjectGovernanceResolver.swift
- Route/doctor truth: AXModelRouteDiagnostics.swift, XTRouteTruthPresentation.swift, channel_onboarding_delivery_readiness.js, channel_command_gate.js

Avoid SupervisorManager.swift, broad UI reshapes, ProjectSettingsView.swift, release gates, README.md, website/.

Before coding, restate: scope, priority, role, start-here, write-scope, avoid, validate, no-regression.
```
