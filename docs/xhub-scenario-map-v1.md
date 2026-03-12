# X-Hub Scenario Map v1

- Status: Working public-facing architecture map
- Updated: 2026-03-10
- Audience: product, release, whitepaper, README, demos, customer explanation

This document explains how to talk about X-Hub scenarios without mixing up three different things:

1. the validated public release slice
2. the broader architecture-backed operating model
3. future roadmap scenarios

It is intentionally written as a scenario map, not as a release-scope expansion document.

## 0) Hard Boundary

The validated public release slice for the current GitHub package remains limited to:

- `XT-W3-23 -> XT-W3-24 -> XT-W3-25`

Validated public claims remain limited to:

- `XT memory UX adapter backed by Hub truth-source`
- `Hub-governed multi-channel gateway`
- `Hub-first governed automations`

Everything else in this document must be presented either as:

- broader architecture-backed workflow fit
- or future roadmap

It must not be presented as an additional validated public release claim.

## 1) The Core Framing

X-Hub is best explained as a trusted control plane for AI execution.

That means the system is not only about model calls. It is about keeping these layers under one governed surface:

- model routing
- memory truth and behavioral context
- grants and approval policy
- readiness and fail-closed gates
- automation and external side effects
- evidence, audit, and rollback
- Supervisor orchestration across projects, pools, and lanes

The scenario question is therefore not "what can a chat window say?"

The real question is "what kinds of work become governable when trust, memory, approvals, and execution are centralized in the Hub?"

## 2) Scenario Tiers

### Tier A: Validated Public Mainline

These are the only scenarios that should currently be described as validated public delivery:

| Scenario | External wording |
|---|---|
| Hub-backed memory UX | X-Terminal can expose memory-aware UX while Hub remains the truth-source |
| Hub-governed multi-channel gateway | channel routing stays inside Hub policy instead of leaking across clients |
| Hub-first governed automations | automation flows are routed through Hub readiness, policy, and audit constraints |

Use this tier for:

- GitHub README core release wording
- release notes
- launch copy
- short external summaries

### Tier B: Architecture-Backed Broader Workflow Fit

These scenarios are grounded in the repository architecture and protocol surface, but they should still be described as broader workflow fit rather than as additional validated release claims.

#### B1. Multi-Project Supervisor Delivery

Best framing:

- X-Hub + X-Terminal can supervise multiple active projects under one orchestration surface
- complex engineering work can be decomposed into module-aware pools and then into parallel lanes
- blocked work can be advanced through wait-for graphs, dependency gates, directed unblocks, congestion control, and dynamic replanning

Why this matters:

- a large coding project stops being a single fragile conversation
- parallel work becomes inspectable, schedulable, and recoverable
- project progress can be expressed as lane state, blocker state, next action, and acceptance evidence instead of vague chat history

Anchor references:

- `x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md`
- `x-terminal/Sources/Supervisor/LaneAllocator.swift`
- `x-terminal/Sources/Supervisor/LaneRuntimeState.swift`

#### B2. Governed External Action Surfaces

Best framing:

- X-Hub is suitable for workflows where external actions must remain governed instead of being hidden inside terminal-local glue code
- that includes connectors, approvals, external side effects, and actions that should fail closed when readiness is incomplete

Why this matters:

- secrets and policy stay on the Hub side
- terminals do not quietly become the execution trust boundary
- kill-switch and audit remain meaningful

Anchor references:

- `docs/xhub-client-modes-and-connectors-v1.md`
- `docs/xhub-agent-efficiency-and-safety-governance-v1.md`
- `protocol/hub_protocol_v1.md`

#### B3. Evidence-First Robot Payment Approval

Best framing:

- X-Hub can support evidence-first payment approval flows instead of silent side effects
- the payment path is modeled as a governed state machine with challenge, anti-replay protection, timeout rollback, and audit

Why this matters:

- payment-like operations stop being "the agent just did it"
- authorization, evidence, confirmation, timeout, and compensation all become explicit

What is grounded in the repo:

- `CreatePaymentIntent`
- `AttachPaymentEvidence`
- `IssuePaymentChallenge`
- `ConfirmPaymentIntent`
- `AbortPaymentIntent`

Anchor references:

- `protocol/hub_protocol_v1.md`
- `docs/memory-new/xhub-memory-v3-execution-plan.md`

#### B4. Enterprise Approval And High-Risk Execution Governance

Best framing:

- X-Hub is a fit for environments where high-risk execution needs grants, approval binding, deny codes, audit, and fail-closed handling
- this is particularly relevant for enterprise, regulated, public-sector, and security-sensitive teams

Why this matters:

- the system can explain why an action is blocked
- grants can be bound to identity, scope, argv, cwd, and execution context
- readiness does not silently degrade into unsafe execution

Anchor references:

- `protocol/hub_protocol_v1.md`
- `docs/xhub-agent-efficiency-and-safety-governance-v1.md`
- `SECURITY.md`

### Tier C: Future Roadmap Scenarios

These scenarios are strategically aligned with the architecture, but they should be presented as future direction unless and until the repository has explicit implementation, protocol, and evidence anchors for them.

#### C1. Voice Progress Conversations With Supervisor

Recommended framing:

- a user should be able to talk to Supervisor by voice and ask for project status, blockers, lane progress, and next actions
- the response should come from auditable project, lane, and acceptance state rather than from loose conversational memory

Good examples:

- "What is the current status of Project A?"
- "Which lanes are blocked right now?"
- "What is the next critical unblock?"
- "Give me the delivery summary for today."

Why this is a good future fit:

- Supervisor already has project and lane state surfaces
- the system already has a voice authorization foundation for high-risk actions
- the missing piece is a voice-first progress conversation layer for operational status, summaries, and guided follow-up

Current boundary:

- voice-based project progress conversations should be described as roadmap
- do not present them as current validated public capability

Relevant references:

- `x-terminal/work-orders/xt-w3-29-supervisor-voice-progress-and-guided-authorization-implementation-pack-v1.md`
- `x-terminal/Sources/Supervisor/`
- `docs/memory-new/xhub-memory-v3-execution-plan.md`

#### C2. Digital Asset Multi-Party Approval / Multi-Sign Flows

Recommended framing:

- future X-Hub deployments may extend the same governed approval pattern to digital-asset treasury or multi-party signing workflows
- the right analogy is not "crypto wallet UI"
- the right analogy is "evidence-first, policy-bound, fail-closed approval choreography for irreversible value transfer"

Why this is plausible:

- the architecture already favors explicit approval state, audit, challenge, replay protection, and bounded execution

Current boundary:

- do not present digital-asset multisig as a currently implemented repository capability
- keep it in whitepaper, strategy, or roadmap language unless a real protocol and implementation surface is added

## 3) What To Say Externally

### Safe External Wording

Use phrases like:

- trusted control plane for AI execution
- Hub-governed memory, routing, grants, and automation
- broader fit for supervised multi-project delivery and governed external actions
- architecture designed for high-risk workflows that must fail closed

### Wording To Keep In Architecture / Whitepaper Lane

Use with boundary language:

- Supervisor-led multi-project orchestration
- pool and lane based decomposition for complex engineering delivery
- evidence-first robot payment approval
- future voice-based Supervisor progress conversations
- future multi-party approval patterns for digital asset workflows

### Wording To Avoid Right Now

Do not say:

- "digital asset multisig is already shipped"
- "voice Supervisor project conversations are already productized"
- "the full internal orchestration stack is already the validated public release"

## 4) Recommended Messaging Hierarchy

When explaining X-Hub, use this order:

1. trusted control plane
2. validated public release slice
3. Supervisor orchestration core
4. memory-backed constitutional safety posture
5. broader workflow fit
6. roadmap scenarios

This order keeps the strongest product narrative without drifting into unverified claims.

## 5) Scenario Summary Table

| Scenario | Tier | How to present it now |
|---|---|---|
| Hub-backed memory UX | Tier A | validated public claim |
| Hub-governed multi-channel gateway | Tier A | validated public claim |
| Hub-first governed automations | Tier A | validated public claim |
| Multi-project Supervisor orchestration | Tier B | architecture-backed broader workflow fit |
| Module-aware pool split + multi-lane delivery | Tier B | architecture-backed broader workflow fit |
| Governed external actions / robot operations | Tier B | architecture-backed broader workflow fit |
| Evidence-first robot payment approval | Tier B | architecture-backed broader workflow fit |
| Voice conversations with Supervisor about project progress | Tier C | roadmap |
| Digital asset multi-party approval / multisig | Tier C | roadmap |
