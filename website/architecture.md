# Architecture

<p class="lead">
X-Hub is a Hub-first governed execution architecture. The terminal is not the trust anchor. The Hub keeps routing truth, memory truth, grants, policy, audit, and kill authority together, while X-Terminal turns that control plane into a usable paired product surface.
</p>

<div class="preview-note">
  <strong>Public architecture view</strong>
  This page explains the system shape and trust boundaries at a product level. It is not intended to publish every
  internal runtime path, implementation edge, or still-changing UI detail.
</div>

## The Architectural Thesis

Many agent systems collapse prompts, tools, memory, secrets, and side-effect execution into one runtime trust zone.
X-Hub takes the opposite position:

- the Hub should own trust, policy, grants, audit, and memory truth
- paired surfaces should be powerful without silently becoming sovereign runtimes
- thinner clients should be able to consume governed capabilities without inheriting equivalent authority
- external channels should converge through the same control plane before they can influence higher-trust execution

## System Shape

<img class="diagram-frame" src="/xhub_trust_control_plane.svg" alt="X-Hub trust and control plane" />

The trust and control plane diagram is meant to show three things:

- X-Terminal follows the deep paired path and is designed as the primary high-trust product surface.
- Generic terminals and other clients can still attach to governed capability surfaces without becoming equivalent trust roots.
- The shared Hub layer is where system truth, policy, authorization, and user control stay anchored.

## Deployment Posture

<img class="diagram-frame" src="/xhub_deployment_runtime_topology.svg" alt="X-Hub deployment and runtime topology" />

The deployment topology is intentionally user-centered:

- the user-owned Hub host stays central
- paired interaction surfaces sit above the control plane, not beside it
- local runtimes and optional external services remain attached boundaries instead of hidden replacement control planes
- cloud services can be used, but they do not have to become the place where policy or runtime truth lives

## Surface Roles

| Surface | Role in the architecture |
| --- | --- |
| Hub | Control plane for trust, routing, memory truth, authorization, and audit |
| X-Terminal | Deep paired product surface for governed interaction, supervision, and operator visibility |
| Generic terminal / third-party client | Thin capability consumer that can attach to governed surfaces without inheriting the full trust boundary |
| External services and runtimes | Optional execution or inference surfaces that remain subordinate to the user-owned control plane |

This separation matters because it lets the system expose rich product UX where it is useful, without forcing every
surface to become the place where final authority resides.

## Public Design Principles

- Keep the trust anchor in the Hub rather than in the terminal, plugin bundle, or vendor default.
- Allow strong paired product surfaces without collapsing trust into the UI.
- Let local and remote execution paths coexist under one user-controlled plane.
- Make external ingress converge before it can influence higher-trust execution.
- Keep the architecture legible enough that operators can reason about where authority actually lives.

## Why This Shape Matters

This structure is what makes the rest of X-Hub possible:

- governed autonomy without unsupervised sprawl
- local-first operation without giving up policy and audit
- operator-channel ingress without creating shadow authority paths
- reusable skills without plugin roulette
- multimodal supervision without fragmenting memory and runtime truth
