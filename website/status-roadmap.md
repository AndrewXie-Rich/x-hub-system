# Status & Roadmap

<p class="lead">
X-Hub-System already has a runnable product path, but it remains a public technical preview. This page explains what is already established, what is still being productized, and what should not be treated as a public claim yet.
</p>

<div class="preview-note">
  <strong>Status language</strong>
  This is not a marketing roadmap. Public wording should distinguish production authority, preview-working, shadow, candidate, diagnostics-only, and roadmap paths so implementation progress is not confused with validated product authority.
</div>

## Current Product Shape

X-Hub-System should currently be read as:

- `X-Hub.app`: the user-facing Hub product entry, Swift macOS UI shell, with Rust kernel/runtime being embedded and migrated
- `X-Terminal.app`: paired terminal, project workspace, and Supervisor surface
- Node Hub service layer: still the production authority for many current paths
- Rust Hub / `xhubd`: migration lane for efficiency, stability, and deterministic kernel work; some paths are shadow, candidate, or diagnostics-only
- official skill packages: productization path for governed skill distribution, manifests, trust roots, and pinning

Key boundary: Rust implementation does not automatically mean Rust production authority. A Rust path becomes release-claimed authority only after readiness evidence, rollback, compatibility, and release-scope approval.

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

## What Not To Overclaim

The public story should not claim:

- this is complete unattended AGI
- A4 already means every browser / device / connector / extension surface is mature
- Rust already owns all Hub production authority
- Memory Control Plane already has complete semantic retrieval, temporal graph, and Memory Inspector UX
- the preview has production security certification or enterprise production SLA
- all release assets are signed and notarized unless Release notes say so

More accurate wording:

> X-Hub-System is a runnable, actively productizing Hub-governed AI execution system. The core security and governance direction is established, while public release scope should expand only with evidence.

## Roadmap Priority

1. Keep Hub-first authority, policy, readiness, and audit stable.
2. Complete Memory Control Plane candidate, approval, semantic retrieval, and Inspector paths.
3. Deepen Coding Runtime step, verify, retry, blocked, checkpoint, guidance ack, and done contract.
4. Expand A4 execution surfaces while preserving grants, scope, TTL, clamps, and recovery.
5. Improve release packaging, signing posture, install experience, and contributor path.

Continue with:
[Get Started](/get-started), [Memory Control Plane](/memory), and [Coding Runtime](/coding-runtime).
