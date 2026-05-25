# Status & Roadmap

<p class="lead">
X-Hub-System already has a runnable product path and is moving from public preview toward a fuller productized release. This page explains what is established, what is still being productized, and what the current public release scope covers.
</p>

<div class="preview-note">
  <strong>Public preview</strong>
  The current release focuses on Hub-first trust, governed memory, model routing, X-Terminal execution surfaces, and the Rust kernel migration path. Deeper execution surfaces, Memory Inspector, signing / notarization, and enterprise-grade SLA commitments will expand as evidence and release scope mature.
</div>

## Current Product Shape

X-Hub-System should currently be read as:

- `X-Hub.app`: the user-facing Hub product entry, Swift macOS UI shell, with Rust kernel/runtime being embedded and migrated
- `X-Terminal.app`: paired terminal, project workspace, and Supervisor surface
- Node Hub service layer: still the production authority for many current paths
- Rust Hub / `xhubd`: migration lane for efficiency, stability, and deterministic kernel work; some paths are shadow, candidate, or diagnostics-only
- official skill packages: productization path for governed skill distribution, manifests, trust roots, and pinning

The current product shape is: users launch `X-Hub.app`; the Hub anchors models, memory, skills, grants, audit, and shutdown authority; `X-Terminal.app` acts as the paired project workspace and Supervisor surface; the Rust kernel/runtime takes over more deterministic and performance-sensitive paths as they mature.

## Established

<div class="story-grid">
  <div class="story-card">
    <span>Product shell</span>
    <strong>Swift Hub UI + Rust kernel/runtime direction</strong>
    <p>The public Hub product should not be daemon-only. The intended shape is `X-Hub.app` for users, with Rust runtime embedded inside the app bundle and X-Terminal as the paired operator surface.</p>
  </div>
  <div class="story-card">
    <span>Trust</span>
    <strong>Hub-first trust and fail-closed posture</strong>
    <p>Pairing, grants, memory truth, model routing, skill trust, audit, and shutdown authority converge on the Hub instead of terminals or remote entry points becoming the default control plane.</p>
  </div>
  <div class="story-card">
    <span>Memory</span>
    <strong>Governed Memory Control Plane is taking shape</strong>
    <p>Hub-first memory truth, policy-gated retrieval, role-aware assembly, candidate writeback, readiness, doctor, and audit evidence now define the core direction.</p>
  </div>
  <div class="story-card">
    <span>Execution</span>
    <strong>X-Terminal + Supervisor governance model</strong>
    <p>A-Tier, S-Tier, Heartbeat / Review, safe-point guidance, and ack form a governance spine that is different from a normal coding bot.</p>
  </div>
  <div class="story-card">
    <span>Skills</span>
    <strong>Governed skill package direction</strong>
    <p>official catalog, manifests, publisher trust, pins, compatibility, vetting, grants, revocation, and audit are forming reusable capability boundaries.</p>
  </div>
  <div class="story-card">
    <span>Release</span>
    <strong>Source and release artifacts stay separate</strong>
    <p>Git keeps source, scripts, docs, and tests. DMG, ZIP, and `.app` artifacts are uploaded as GitHub Release assets, not committed to the repository.</p>
  </div>
</div>

## Being Productized

| Area | Current focus |
| --- | --- |
| A4 execution surface | browser, device, connector, extension, plan graph, and richer skill result contracts |
| Memory Inspector | visible candidate, approval, lineage, selected / omitted trace surfaces |
| semantic retrieval | stronger semantic recall and rerank after authority, policy, and evidence are stable |
| temporal graph | Observations / Longterm handling for changing, stale, or conflicting facts |
| Hub Run Scheduler | first-class run truth, wake, grants, audit, clamps, and recovery |
| Release packaging | combined DMG, Hub-only / XT-only assets, SHA256, signing, notarization notes |
| low-friction mode | fast prototype mode for small work so not every task pays the cost of heavy governance |

## Current Release Scope

The public preview is not a claim that every automation surface is complete. It is a working product direction for safer AI execution: the Hub is the control plane, while terminals and remote entry points remain governed execution surfaces. Memory, models, skills, quotas, grants, and audit converge into one boundary.

The parts that are ready to show publicly:

- Swift Hub UI + Rust kernel/runtime product shape
- X-Terminal pairing, project workspace, and Supervisor governance model
- Hub-first trust, first pairing on the same network, grants, policy, audit, and kill-switch direction
- Governed Memory Control Plane core mechanisms and roadmap
- governed skills, model routing, local-first operation, and paid-provider access under one control plane

Release notes and this roadmap will expand the public scope as more surfaces mature, especially the full A4 execution surface, Memory Inspector, semantic retrieval, temporal graph, signing / notarization, and higher release guarantees.

## Roadmap Priority

1. Keep Hub-first authority, policy, readiness, and audit stable.
2. Complete Memory Control Plane candidate, approval, semantic retrieval, and Inspector paths.
3. Deepen Coding Runtime step, verify, retry, blocked, checkpoint, guidance ack, and done contract.
4. Expand A4 execution surfaces while preserving grants, scope, TTL, clamps, and recovery.
5. Improve release packaging, signing posture, install experience, and contributor path.

Continue with:
[Get Started](/get-started), [Memory Control Plane](/memory), and [Coding Runtime](/coding-runtime).
