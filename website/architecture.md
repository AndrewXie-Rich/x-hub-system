# Architecture

<p class="lead">
Clients ask. The Hub decides. Execution surfaces act inside scope. Runtime truth returns to the Hub. The rest of this page is the long version: what each layer does, where the boundaries sit, and why this shape lets you run powerful AI without giving away the trust root.
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
- memory maintenance should stay on a Hub control plane where the user chooses which AI executes memory jobs, rather than turning memory into a terminal-local or plugin-local black box
- paired surfaces should be powerful without silently becoming sovereign runtimes
- thinner clients should be able to consume governed capabilities without inheriting equivalent authority
- external channels should converge through the same control plane before they can influence higher-trust execution

## System Shape

<img class="diagram-frame" src="/xhub_trust_control_plane.svg" alt="X-Hub trust and control plane" />

The trust and control plane diagram is meant to show three things:

- X-Terminal is one paired surface — the deepest one shipping today, not the only one. The same control plane direction supports a Web thin client (in flight) and Linux daemon deployments (90-day P0).
- Generic terminals and other clients can still attach to governed capability surfaces without becoming equivalent trust roots.
- The shared Hub layer is where system truth, policy, authorization, and user control stay anchored.

For memory specifically, the public boundary is intentionally simple:

- `Memory-Core` is a governed Hub-side rule asset, not an ordinary plugin tier
- the user still chooses which AI executes memory jobs in X-Hub
- durable memory truth still terminates through `Writer + Gate` instead of through an arbitrary client or skill runtime

## Governed Capability Map

<img class="diagram-frame" src="/xhub_deployment_runtime_topology.svg" alt="X-Hub governed capability map" />

The capability map is intentionally control-plane centered:

- model routing, memory, skills, provider accounts, quotas, terminal execution, channels, Supervisor state, and audit can converge through one Hub authority
- local and remote runtime surfaces remain attached boundaries rather than hidden replacement control planes
- cloud services can be used, but they do not have to become the place where policy or runtime truth lives
- implementation details can evolve while the authority boundary stays legible

## Surface Roles

| Surface | Role in the architecture |
| --- | --- |
| Hub | Control plane for trust, routing, memory truth, authorization, and audit |
| X-Terminal | Deep paired surface for governed interaction, supervision, and operator visibility (one of several paired surfaces; not the only one) |
| Web thin client | Browser-based governed surface, in flight. Covers Windows / Linux teams without per-platform native builds |
| Linux daemon | `docker-compose`-friendly Hub deployment, 90-day P0 |
| Generic terminal / third-party client | Thin capability consumer that can attach to governed surfaces without inheriting the full trust boundary |
| External services and runtimes | Optional execution or inference surfaces that remain subordinate to the user-owned control plane |
| [Hub Receipt v0.1](https://github.com/AndrewXie-Rich/x-hub-system/blob/main/specs/hub-receipt/v0.1.md) | Cross-surface, cross-spec signed-receipt envelope. Skill execution receipts (mcp-trust-registry) and per-action confirmation receipts (agent-2fa) share this format, so a single audit chain covers both |

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
