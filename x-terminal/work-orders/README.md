# X-Terminal Work Orders Index

- updatedAt: 2026-03-21
- scope: `x-terminal/` module only

This page is the priority-ordered execution map for X-Terminal work orders.

It is not a dump of every active pack.
It exists to answer one practical question fast:

**If I am about to work on X-Terminal, which work-order family should I start from first?**

## Read This First

If you are resuming X-Terminal work, read in this order:

1. `README.md`
2. `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`
3. `docs/open-source/XHUB_V1_PRODUCT_BOUNDARY_AND_PRIORITIES_v1.md`
4. `docs/open-source/XHUB_NEXT_10_WORK_ORDERS_v1.md`
5. `docs/WORKING_INDEX.md`
6. `x-terminal/README.md`
7. this file

After that, open the matching pack family below.

## Default Rules

- If a pack conflicts with `docs/open-source/XHUB_V1_PRODUCT_BOUNDARY_AND_PRIORITIES_v1.md`, the v1 boundary doc wins.
- If you need a concrete default task instead of a pack family, use `docs/open-source/XHUB_NEXT_10_WORK_ORDERS_v1.md`.
- If a pack is technically active but sits outside the current v1 mainline, do not treat it as the default starting point.
- If you are unsure where to start, choose a `P0` family first.
- Do not start from `P2` or `Frozen / Deprioritized` unless the user explicitly asks for that direction.

## Concrete Next Backlog

When another AI collaborator joins mid-stream, do not start by browsing random packs.
Use `docs/open-source/XHUB_NEXT_10_WORK_ORDERS_v1.md` first:

- items `1-5` are the default mainline blockers
- items `6-9` are important follow-ups once the blockers above have owners
- item `10` is the public-layer packaging pass and should not replace core product work

## P0 - Current Default Starting Points

These are the work-order families that best match the current v1 product boundary.

### P0-A Public Preview Mainline

Start here when the task touches the current GitHub-facing preview slice.

- `xt-w3-23-memory-ux-adapter-implementation-pack-v1.md`
- `xt-w3-24-multichannel-gateway-productization-implementation-pack-v1.md`
- `xt-w3-24-supervisor-operator-channels-implementation-pack-v1.md`
- `xt-w3-24-safe-operator-channel-onboarding-automation-implementation-pack-v1.md`
- `xt-w3-24-supervisor-operator-channels-hub-security-impact-gate-v1.md`
- `xt-w3-25-automation-product-gap-closure-implementation-pack-v1.md`
- `xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md`

Use this family when the question is:

- what is in the validated or preview-working public slice?
- what should remain strong in the current preview?
- what should not be regressed while adding new surface polish?

### P0-B Pairing, Trust, Route Truth, And Repair

Start here when the task touches connection state, grants, route truth, trust profile, or operator recovery.

- `xt-w1-02-route-state-machine.md`
- `xt-w1-03-pending-grants-source-of-truth.md`
- `xt-w1-04-high-risk-grant-enforcement.md`
- `xt-w3-27-hub-xt-ui-productization-r1-implementation-pack-v1.md`
- `xt-w3-28-paired-terminal-trust-profile-and-budget-visibility-implementation-pack-v1.md`

Use this family when the question is:

- why pairing or reconnect feels unreliable
- how blocked / denied / downgraded truth should surface
- where doctor / setup / trust-profile UX should land

### P0-C Project Governance And The Main Supervisor Execution Loop

Start here when the task touches project execution tiers, supervision depth, review cadence, big-task intake, or the single main Supervisor flow.

- `xt-w3-21-w3-22-supervisor-intake-acceptance-implementation-pack-v1.md`
- `xt-w3-26-supervisor-one-shot-intake-adaptive-pool-planner-implementation-pack-v1.md`
- `xt-w3-29-supervisor-conversation-window-persistent-session-implementation-pack-v1.md`
- `xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
- `xt-w3-36-b-project-governance-surface-split-implementation-pack-v1.md`

Completed child pack:

- `xt-w3-36-b-project-governance-surface-split-implementation-pack-v1.md`

Governance product truth:

- `Execution Tier` = `A0..A4`, with highest user-facing label `A4 Agent`
- `Supervisor Tier` = `S0..S4`
- `Heartbeat & Review` stays independent from the tier dials

Evidence and release hooks:

- `x-terminal/scripts/ci/xt_w3_36_project_governance_evidence.sh`
- `x-terminal/scripts/ci/xt_release_gate.sh`

Use this family when the question is:

- how users start a real project or big task
- how `A0..A4` and `S0..S4` should behave
- how one Supervisor window should own the main execution loop

### P0-D Voice, Guided Authorization, And Governed Remote Approval

Start here when the task touches voice briefing, challenge flows, TTS quality, remote-channel approval, or source-aware grant targeting.

- `xt-w3-29-whisperkit-funasr-voice-runtime-implementation-pack-v1.md`
- `xt-w3-29-supervisor-voice-progress-and-guided-authorization-implementation-pack-v1.md`
- `xt-w3-29-supervisor-voice-productization-gap-closure-implementation-pack-v1.md`
- `xt-w3-39-hub-voice-pack-and-supervisor-tts-implementation-pack-v1.md`
- `xt-w3-40-supervisor-device-local-calendar-reminders-implementation-pack-v1.md`
- `xt-w3-24-safe-operator-channel-onboarding-automation-implementation-pack-v1.md`

Use this family when the question is:

- how the voice loop should actually feel in product
- how remote requests become guided approval instead of shadow control
- how TTS / voice readiness should improve without bypassing Hub governance
- how XT should own personal calendar reminders so Hub launch stays permission-free

Evidence hook:

- `x-terminal/scripts/ci/xt_w3_40_calendar_boundary_evidence.sh`

### P0-E Governed Skills, Skill Doctor, And Safe Runtime Surfaces

Start here when the task touches skills UX, compatibility, preflight, manifest boundaries, or governed reuse.

- `xt-skills-compat-reliability-work-orders-v1.md`
- `xt-l1-skills-ux-preflight-runner-contract-v1.md`
- `xt-assistant-runtime-alignment-implementation-pack-v1.md`

Use this family when the question is:

- how skills become usable without becoming plugin roulette
- how doctor / preflight / runner constraints should work
- how assistant-runtime ideas can be absorbed without weakening Hub authority

## P1 - Important Next, But Not The First Default

These packs are still important, but they should usually follow after the `P0` line above is stable.

### P1-A Portfolio Depth And Governed Orchestration Depth

- `xt-w3-31-supervisor-portfolio-awareness-and-project-action-feed-implementation-pack-v1.md`
- `xt-w3-32-supervisor-skill-orchestration-and-governed-event-loop-implementation-pack-v1.md`
- `xt-w3-33-supervisor-decision-kernel-routing-and-memory-governance-implementation-pack-v1.md`
- `xt-w3-35-supervisor-memory-retrieval-progressive-disclosure-implementation-pack-v1.md`

Use these only when the task truly needs more orchestration depth.
Do not start here for basic first-run, pairing, governance, or single-project execution issues.

### P1-B Local Runtime And Richer Review Surfaces

- `xt-w3-37-agent-ui-observation-and-governed-visual-review-implementation-pack-v1.md`

Use this when the task is explicitly about governed UI observation, visual review, or objective diagnostics.
Do not let this family replace the simpler v1 pairing / governance / voice / skill mainline.

### P1-C Release Gates And Evidence Spine

- `xt-w3-08-release-gate-skeleton.md`

Use this when the task is explicitly about release-go / no-go criteria, evidence regeneration, or keeping the main XT gate contract aligned with landed packs.

## P2 - Keep Available, But Do Not Default To

These packs represent system depth, experimentation, or earlier execution shells.
They are not the recommended default entrypoint for current v1 work.

### P2-A Multipool, Multilane, And Deep Orchestration Shells

- `xterminal-parallel-work-orders-v1.md`
- `xt-supervisor-autosplit-multilane-work-orders-v1.md`
- `xt-supervisor-multipool-adaptive-work-orders-v1.md`
- `xt-supervisor-multipool-lane-execution-pack-v1.md`
- `xt-supervisor-rhythm-user-explainability-implementation-pack-v1.md`
- `xt-cbl-anti-block-context-governor-implementation-pack-v1.md`
- `xt-w2-23-w2-26-autocontinue-autonomy-implementation-pack-v1.md`
- `xt-w2-24-token-optimal-context-capsule-implementation-pack-v1.md`
- `xt-w2-27-anti-block-unblock-orchestration-implementation-pack-v1.md`
- `xt-w2-28-jamless-anti-congestion-protocol-implementation-pack-v1.md`
- `xt-w2-09-w2-11-split-proposal-prompt-contract.md`
- `xt-w3-26-w3-27-4ai-parallel-dispatch-pack-v1.md`

Rule:

- use these when a task explicitly targets deep multi-lane orchestration behavior
- do not start here for normal v1 product shaping

## Frozen / Deprioritized For Current V1 Mainline

These packs are not deleted.
They are simply not the default place to spend mainline v1 effort right now.

### Frozen-A Persona / Personal Assistant Expansion

- `xt-w3-38-supervisor-personal-longterm-assistant-implementation-pack-v1.md`
- `xt-w3-38-i6-supervisor-memory-routing-and-assembly-implementation-pack-v1.md`
- `xt-w3-38-i7-supervisor-continuity-floor-and-context-depth-implementation-pack-v1.md`
- `xt-w3-38-i7-d2-hub-first-supervisor-durable-memory-handoff-implementation-pack-v1.md`
- `xt-w3-38-h-supervisor-persona-center-implementation-pack-v1.md`

Rule:

- maintain or fix if necessary
- do not let this family take priority over pairing, governance, skills, voice, or first-run success
- if the task is explicitly about Supervisor forgetting recent turns, recent raw context control, personal/project memory merge quality, or project coder context depth, start with `xt-w3-38-i7-supervisor-continuity-floor-and-context-depth-implementation-pack-v1.md`
- if the task is explicitly about Hub-first durable personal/cross-link writeback or Supervisor durable handoff, also read `xt-w3-38-i7-d2-hub-first-supervisor-durable-memory-handoff-implementation-pack-v1.md`
- for back-compat guardrails, read `docs/memory-new/xhub-supervisor-memory-compatibility-guardrails-v1.md` first

### Frozen-B OpenClaw Parity Chase

- `xt-w3-30-openclaw-mode-capability-gap-closure-implementation-pack-v1.md`
- `xt-w3-34-openclaw-skill-reuse-and-execution-surface-implementation-pack-v1.md`

Rule:

- borrow engineering shells if useful
- do not treat full feature parity as the v1 target

## Quick Task-To-Pack Map

Use this section when you need a fast starting point.

- pairing / reconnect / route truth / deny reason
  - `xt-w1-02-route-state-machine.md`
  - `xt-w1-03-pending-grants-source-of-truth.md`
  - `xt-w1-04-high-risk-grant-enforcement.md`
  - `xt-w3-27-hub-xt-ui-productization-r1-implementation-pack-v1.md`

- project governance / `A0..A4` / `S0..S4` / review cadence
  - `xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
  - `xt-w3-36-b-project-governance-surface-split-implementation-pack-v1.md`

- Supervisor main window / big-task entry / one clear execution loop
  - `xt-w3-21-w3-22-supervisor-intake-acceptance-implementation-pack-v1.md`
  - `xt-w3-26-supervisor-one-shot-intake-adaptive-pool-planner-implementation-pack-v1.md`
  - `xt-w3-29-supervisor-conversation-window-persistent-session-implementation-pack-v1.md`

- voice briefing / guided authorization / TTS productization
  - `xt-w3-29-whisperkit-funasr-voice-runtime-implementation-pack-v1.md`
  - `xt-w3-29-supervisor-voice-progress-and-guided-authorization-implementation-pack-v1.md`
  - `xt-w3-29-supervisor-voice-productization-gap-closure-implementation-pack-v1.md`
  - `xt-w3-39-hub-voice-pack-and-supervisor-tts-implementation-pack-v1.md`

- release gates / evidence / no-go criteria
  - `xt-w3-08-release-gate-skeleton.md`

- channels / safe onboarding / governed remote approval
  - `xt-w3-24-supervisor-operator-channels-implementation-pack-v1.md`
  - `xt-w3-24-safe-operator-channel-onboarding-automation-implementation-pack-v1.md`
  - `xt-w3-24-supervisor-operator-channels-hub-security-impact-gate-v1.md`

- governed skills / skill doctor / preflight / runner rules
  - `xt-skills-compat-reliability-work-orders-v1.md`
  - `xt-l1-skills-ux-preflight-runner-contract-v1.md`
  - `xt-assistant-runtime-alignment-implementation-pack-v1.md`

## Final Rule

Before choosing a pack, ask:

**Will this work help X-Hub v1 become a more user-owned, Hub-first, governed agent control plane?**

If the answer is not clear, pick a `P0` family instead of expanding the edge of the system.
