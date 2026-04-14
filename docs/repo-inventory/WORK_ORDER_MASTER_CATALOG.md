# Work Order Master Catalog

This page is the repo-wide catalog for active work-order documents.

It exists because the repository currently splits planning across:

- XT execution packs in `x-terminal/work-orders/`
- repo-level parent work orders and control-plane packs in `docs/memory-new/`

Without one shared catalog, AI collaborators tend to read only the XT packs and miss the parent docs that define the actual system boundary.

## Scope

This catalog counts active work-order documents after excluding:

- `archive/`
- `build/`
- `data/`
- `**/node_modules/`
- `x-terminal/.axcoder/reports/**`

Active work-order counts at the time of this inventory:

- XT work-order docs: `52`
- repo-level `docs/memory-new/*work-order*` docs: `25`
- active proper work-order docs total: `77`

This page also lists a small set of companion docs that are not themselves work orders but are required to use the packs correctly.

## Precedence Rules

When documents disagree, use this order:

1. `docs/open-source/XHUB_V1_PRODUCT_BOUNDARY_AND_PRIORITIES_v1.md`
2. `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md`
3. `docs/open-source/XHUB_NEXT_10_WORK_ORDERS_v1.md`
4. this catalog
5. `x-terminal/work-orders/README.md`

## Snapshot And Noise Paths To Ignore

Do not catalog or assign work from these generated copies:

- `x-terminal/.axcoder/reports/.xt_w3_36_source_snapshot/x-terminal/work-orders/*`
- `x-terminal/.axcoder/reports/.xt_w3_40_source_snapshot/x-terminal/work-orders/*`
- any future `x-terminal/.axcoder/reports/**/work-orders/*`

## Shared Metadata

Each entry in this catalog uses four fields:

- `scope`: `repo`, `hub`, `xt`, or `cross-cutting`
- `priority`: `P0`, `P1`, `P2`, or `Frozen`
- `role`: `parent`, `child`, `checklist`, `gate`, or `index`
- `start-here`: `yes` or `no`

## Companion Entry Docs

These are not counted as work orders, but they should be read before assigning work:

| Path | Role |
|---|---|
| `docs/open-source/XHUB_V1_PRODUCT_BOUNDARY_AND_PRIORITIES_v1.md` | v1 scope and prioritization authority |
| `docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md` | feature status authority |
| `docs/open-source/XHUB_NEXT_10_WORK_ORDERS_v1.md` | default mainline next backlog |
| `x-terminal/work-orders/README.md` | XT-only work-order index |

## Repo-Level Parent Work Orders

### Memory / Memory Control Plane

| Path | Scope | Priority | Role | Start-Here |
|---|---|---|---|---|
| `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md` | repo | P0 | parent | yes |
| `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md` | repo | P0 | parent | yes |
| `docs/memory-new/xhub-memory-capability-leapfrog-work-orders-v1.md` | repo | P1 | parent | no |
| `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md` | cross-cutting | P0 | parent | yes |
| `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md` | cross-cutting | P0 | parent | yes |
| `docs/memory-new/xhub-supervisor-memory-serving-work-orders-v1.md` | cross-cutting | P1 | parent | no |

### Governance / Supervisor / Autonomy

| Path | Scope | Priority | Role | Start-Here |
|---|---|---|---|---|
| `docs/memory-new/xhub-governed-autonomy-switchboard-productization-work-orders-v1.md` | cross-cutting | P0 | parent | yes |
| `docs/memory-new/xhub-supervisor-adaptive-intervention-and-work-order-depth-work-orders-v1.md` | cross-cutting | P1 | parent | no |
| `docs/memory-new/xhub-supervisor-event-loop-stability-work-orders-v1.md` | cross-cutting | P1 | parent | no |
| `docs/memory-new/xhub-multimodal-supervisor-control-plane-work-orders-v1.md` | repo | P1 | parent | no |

### Skills / Packages / Trust Chain

| Path | Scope | Priority | Role | Start-Here |
|---|---|---|---|---|
| `docs/memory-new/xhub-governed-package-productization-work-orders-v1.md` | repo | P0 | parent | yes |
| `docs/memory-new/xhub-dynamic-official-agent-skills-governance-work-orders-v1.md` | repo | P1 | parent | no |
| `docs/memory-new/xhub-official-agent-skills-signing-sync-and-hub-signer-work-orders-v1.md` | repo | P1 | parent | no |
| `docs/memory-new/xhub-agent-skill-vetter-gate-work-orders-v1.md` | repo | P1 | parent | no |
| `docs/memory-new/xhub-work-order-8-9-closure-checklist-v1.md` | repo | P1 | checklist | no |

### Runtime / Providers / Channels / Security

| Path | Scope | Priority | Role | Start-Here |
|---|---|---|---|---|
| `docs/memory-new/xhub-local-provider-runtime-transformers-work-orders-v1.md` | cross-cutting | P0 | parent | yes |
| `docs/memory-new/xhub-trusted-automation-mode-work-orders-v1.md` | cross-cutting | P0 | parent | yes |
| `docs/memory-new/xhub-connector-reliability-kernel-work-orders-v1.md` | cross-cutting | P1 | parent | no |
| `docs/memory-new/xhub-remote-pairing-autoreconnect-security-work-orders-v1.md` | cross-cutting | P0 | parent | yes |
| `docs/memory-new/xhub-security-innovation-work-orders-v1.md` | repo | P1 | parent | no |
| `docs/memory-new/xhub-spec-gates-work-orders-v1.md` | repo | P1 | parent | no |

### Product Shell / Adoption

| Path | Scope | Priority | Role | Start-Here |
|---|---|---|---|---|
| `docs/memory-new/xhub-product-experience-leapfrog-work-orders-v1.md` | repo | P1 | parent | no |

## XT Execution Packs

### XT Module Index

| Path | Scope | Priority | Role | Start-Here |
|---|---|---|---|---|
| `x-terminal/work-orders/README.md` | xt | P0 | index | yes |

### XT P0 Public Preview Mainline

| Path | Scope | Priority | Role | Start-Here |
|---|---|---|---|---|
| `x-terminal/work-orders/xt-w3-23-memory-ux-adapter-implementation-pack-v1.md` | xt | P0 | child | yes |
| `x-terminal/work-orders/xt-w3-24-multichannel-gateway-productization-implementation-pack-v1.md` | xt | P0 | child | yes |
| `x-terminal/work-orders/xt-w3-24-supervisor-operator-channels-implementation-pack-v1.md` | xt | P0 | child | yes |
| `x-terminal/work-orders/xt-w3-24-safe-operator-channel-onboarding-automation-implementation-pack-v1.md` | xt | P0 | child | yes |
| `x-terminal/work-orders/xt-w3-24-supervisor-operator-channels-hub-security-impact-gate-v1.md` | xt | P0 | gate | yes |
| `x-terminal/work-orders/xt-w3-25-automation-product-gap-closure-implementation-pack-v1.md` | xt | P0 | child | yes |
| `x-terminal/work-orders/xt-w3-25-governed-automation-recipe-runtime-implementation-pack-v1.md` | xt | P0 | child | yes |

### XT P0 Pairing / Trust / Route Truth / Repair

| Path | Scope | Priority | Role | Start-Here |
|---|---|---|---|---|
| `x-terminal/work-orders/xt-w1-02-route-state-machine.md` | xt | P0 | child | yes |
| `x-terminal/work-orders/xt-w1-03-pending-grants-source-of-truth.md` | xt | P0 | child | yes |
| `x-terminal/work-orders/xt-w1-04-high-risk-grant-enforcement.md` | xt | P0 | child | yes |
| `x-terminal/work-orders/xt-w3-27-hub-xt-ui-productization-r1-implementation-pack-v1.md` | xt | P0 | child | yes |
| `x-terminal/work-orders/xt-w3-28-paired-terminal-trust-profile-and-budget-visibility-implementation-pack-v1.md` | xt | P0 | child | yes |

### XT P0 Governance / Main Supervisor Loop

| Path | Scope | Priority | Role | Start-Here |
|---|---|---|---|---|
| `x-terminal/work-orders/xt-w3-21-w3-22-supervisor-intake-acceptance-implementation-pack-v1.md` | xt | P0 | child | yes |
| `x-terminal/work-orders/xt-w3-26-supervisor-one-shot-intake-adaptive-pool-planner-implementation-pack-v1.md` | xt | P0 | child | yes |
| `x-terminal/work-orders/xt-w3-29-supervisor-conversation-window-persistent-session-implementation-pack-v1.md` | xt | P0 | child | yes |
| `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md` | xt | P0 | child | yes |
| `x-terminal/work-orders/xt-w3-36-b-project-governance-surface-split-implementation-pack-v1.md` | xt | P0 | child | yes |
| `x-terminal/work-orders/xt-w3-42-supervisor-project-intent-and-transaction-repair-implementation-pack-v1.md` | xt | P0 | child | yes |

### XT P0 Voice / Guided Authorization / Remote Approval

| Path | Scope | Priority | Role | Start-Here |
|---|---|---|---|---|
| `x-terminal/work-orders/xt-w3-29-whisperkit-funasr-voice-runtime-implementation-pack-v1.md` | xt | P0 | child | yes |
| `x-terminal/work-orders/xt-w3-29-supervisor-voice-progress-and-guided-authorization-implementation-pack-v1.md` | xt | P0 | child | yes |
| `x-terminal/work-orders/xt-w3-29-supervisor-voice-productization-gap-closure-implementation-pack-v1.md` | xt | P0 | child | yes |
| `x-terminal/work-orders/xt-w3-39-hub-voice-pack-and-supervisor-tts-implementation-pack-v1.md` | xt | P0 | child | yes |
| `x-terminal/work-orders/xt-w3-40-supervisor-device-local-calendar-reminders-implementation-pack-v1.md` | xt | P0 | child | yes |

### XT P0 Governed Skills / Runtime Safety

| Path | Scope | Priority | Role | Start-Here |
|---|---|---|---|---|
| `x-terminal/work-orders/xt-skills-compat-reliability-work-orders-v1.md` | xt | P0 | child | yes |
| `x-terminal/work-orders/xt-l1-skills-ux-preflight-runner-contract-v1.md` | xt | P0 | child | yes |
| `x-terminal/work-orders/xt-assistant-runtime-alignment-implementation-pack-v1.md` | xt | P0 | child | yes |

### XT P1 Orchestration Depth / Portfolio

| Path | Scope | Priority | Role | Start-Here |
|---|---|---|---|---|
| `x-terminal/work-orders/xt-w3-31-supervisor-portfolio-awareness-and-project-action-feed-implementation-pack-v1.md` | xt | P1 | child | no |
| `x-terminal/work-orders/xt-w3-32-supervisor-skill-orchestration-and-governed-event-loop-implementation-pack-v1.md` | xt | P1 | child | no |
| `x-terminal/work-orders/xt-w3-33-supervisor-decision-kernel-routing-and-memory-governance-implementation-pack-v1.md` | xt | P1 | child | no |
| `x-terminal/work-orders/xt-w3-35-supervisor-memory-retrieval-progressive-disclosure-implementation-pack-v1.md` | xt | P1 | child | no |

### XT P1 Review / Release Spine

| Path | Scope | Priority | Role | Start-Here |
|---|---|---|---|---|
| `x-terminal/work-orders/xt-w3-37-agent-ui-observation-and-governed-visual-review-implementation-pack-v1.md` | xt | P1 | child | no |
| `x-terminal/work-orders/xt-w3-08-release-gate-skeleton.md` | xt | P1 | gate | no |

### XT P2 Deep Orchestration / Older Execution Shells

| Path | Scope | Priority | Role | Start-Here |
|---|---|---|---|---|
| `x-terminal/work-orders/xterminal-parallel-work-orders-v1.md` | xt | P2 | child | no |
| `x-terminal/work-orders/xt-supervisor-autosplit-multilane-work-orders-v1.md` | xt | P2 | child | no |
| `x-terminal/work-orders/xt-supervisor-multipool-adaptive-work-orders-v1.md` | xt | P2 | child | no |
| `x-terminal/work-orders/xt-supervisor-multipool-lane-execution-pack-v1.md` | xt | P2 | child | no |
| `x-terminal/work-orders/xt-supervisor-rhythm-user-explainability-implementation-pack-v1.md` | xt | P2 | child | no |
| `x-terminal/work-orders/xt-cbl-anti-block-context-governor-implementation-pack-v1.md` | xt | P2 | child | no |
| `x-terminal/work-orders/xt-w2-23-w2-26-autocontinue-autonomy-implementation-pack-v1.md` | xt | P2 | child | no |
| `x-terminal/work-orders/xt-w2-24-token-optimal-context-capsule-implementation-pack-v1.md` | xt | P2 | child | no |
| `x-terminal/work-orders/xt-w2-27-anti-block-unblock-orchestration-implementation-pack-v1.md` | xt | P2 | child | no |
| `x-terminal/work-orders/xt-w2-28-jamless-anti-congestion-protocol-implementation-pack-v1.md` | xt | P2 | child | no |
| `x-terminal/work-orders/xt-w2-09-w2-11-split-proposal-prompt-contract.md` | xt | P2 | child | no |
| `x-terminal/work-orders/xt-w3-26-w3-27-4ai-parallel-dispatch-pack-v1.md` | xt | P2 | child | no |

### XT Frozen / Deprioritized

| Path | Scope | Priority | Role | Start-Here |
|---|---|---|---|---|
| `x-terminal/work-orders/xt-w3-38-supervisor-personal-longterm-assistant-implementation-pack-v1.md` | xt | Frozen | child | no |
| `x-terminal/work-orders/xt-w3-38-i6-supervisor-memory-routing-and-assembly-implementation-pack-v1.md` | xt | Frozen | child | no |
| `x-terminal/work-orders/xt-w3-38-i7-supervisor-continuity-floor-and-context-depth-implementation-pack-v1.md` | xt | Frozen | child | no |
| `x-terminal/work-orders/xt-w3-38-i7-d2-hub-first-supervisor-durable-memory-handoff-implementation-pack-v1.md` | xt | Frozen | child | no |
| `x-terminal/work-orders/xt-w3-38-h-supervisor-persona-center-implementation-pack-v1.md` | xt | Frozen | child | no |
| `x-terminal/work-orders/xt-w3-30-openclaw-mode-capability-gap-closure-implementation-pack-v1.md` | xt | Frozen | child | no |
| `x-terminal/work-orders/xt-w3-34-openclaw-skill-reuse-and-execution-surface-implementation-pack-v1.md` | xt | Frozen | child | no |

## Companion Control Docs To Read Beside The Catalog

These are not part of the `77` proper work-order count, but they are needed to interpret the packs correctly.

### Protocols / Contracts / Freezes

- `docs/memory-new/xhub-project-autonomy-tier-and-supervisor-review-protocol-v1.md`
- `docs/memory-new/xhub-supervisor-memory-routing-and-assembly-protocol-v1.md`
- `docs/memory-new/xhub-supervisor-memory-serving-contract-v1.md`
- `docs/memory-new/xhub-local-service-runtime-contract-v1.md`
- `docs/memory-new/xhub-skills-capability-grant-chain-contract-v1.md`
- `docs/memory-new/xhub-memory-model-preferences-and-routing-contract-v1.md`
- `docs/memory-new/xhub-multimodal-supervisor-control-plane-contract-freeze-v1.md`
- `docs/memory-new/xhub-memory-core-recipe-asset-versioning-freeze-v1.md`
- `docs/memory-new/xhub-memory-v3-m2-spec-freeze-v1.md`
- `docs/memory-new/xhub-memory-v3-m3-lineage-contract-freeze-v1.md`
- `docs/memory-new/xhub-memory-v3-m3-lineage-contract-tests-v1.md`

### Runbooks / Checklists / Implementation Companions

- `docs/memory-new/xhub-local-provider-runtime-transformers-implementation-pack-v1.md`
- `docs/memory-new/xhub-trusted-automation-mode-implementation-pack-v1.md`
- `docs/memory-new/xhub-trusted-automation-device-execution-plane-implementation-pack-v1.md`
- `docs/memory-new/xhub-memory-open-source-reference-adoption-checklist-v1.md`
- `docs/memory-new/xhub-memory-open-source-reference-wave0-execution-pack-v1.md`
- `docs/memory-new/xhub-memory-open-source-reference-wave1-execution-pack-v1.md`
- `docs/memory-new/xhub-local-provider-runtime-require-real-runbook-v1.md`
- `docs/memory-new/xt-w3-24-n-whatsapp-cloud-require-real-runbook-v1.md`
- `docs/memory-new/xt-w3-31-require-real-runbook-v1.md`
- `docs/memory-new/hub-l5-skc-g5-release-runbook-v1.md`

## Recommended Multi-AI Split

If several AI collaborators continue after this catalog:

1. One AI on Hub trust/routing:
   - `x-hub/macos/`
   - `x-hub/grpc-server/`
   - `docs/memory-new/xhub-remote-pairing-autoreconnect-security-work-orders-v1.md`
   - `x-terminal/work-orders/xt-w1-02-route-state-machine.md`
   - `x-terminal/work-orders/xt-w1-03-pending-grants-source-of-truth.md`
   - `x-terminal/work-orders/xt-w1-04-high-risk-grant-enforcement.md`

2. One AI on memory/governance:
   - `docs/memory-new/xhub-terminal-hub-memory-governance-work-orders-v1.md`
   - `docs/memory-new/xhub-terminal-hub-memory-layer-usage-work-orders-v1.md`
   - `docs/memory-new/xhub-memory-v3-m2-work-orders-v1.md`
   - `docs/memory-new/xhub-memory-v3-m3-work-orders-v1.md`
   - `x-terminal/work-orders/xt-w3-36-project-autonomy-tier-and-supervisor-intervention-implementation-pack-v1.md`
   - `x-terminal/work-orders/xt-w3-36-b-project-governance-surface-split-implementation-pack-v1.md`

3. One AI on Supervisor/voice/product surfaces:
   - `x-terminal/work-orders/xt-w3-29-whisperkit-funasr-voice-runtime-implementation-pack-v1.md`
   - `x-terminal/work-orders/xt-w3-29-supervisor-voice-progress-and-guided-authorization-implementation-pack-v1.md`
   - `x-terminal/work-orders/xt-w3-29-supervisor-voice-productization-gap-closure-implementation-pack-v1.md`
   - `x-terminal/work-orders/xt-w3-39-hub-voice-pack-and-supervisor-tts-implementation-pack-v1.md`
   - `x-terminal/work-orders/xt-w3-40-supervisor-device-local-calendar-reminders-implementation-pack-v1.md`
   - `x-terminal/Sources/Supervisor/`

4. One AI on skills/packages/runtime productization:
   - `docs/memory-new/xhub-governed-package-productization-work-orders-v1.md`
   - `x-terminal/work-orders/xt-skills-compat-reliability-work-orders-v1.md`
   - `docs/memory-new/xhub-local-provider-runtime-transformers-work-orders-v1.md`

Keep write sets disjoint. The catalog is only useful if each AI owns a separate surface.
