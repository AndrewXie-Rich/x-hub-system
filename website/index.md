---
layout: home

hero:
  name: X-Hub
  text: Hub-first governed execution.
  tagline: X-Hub keeps routing, memory, grants, audit, and kill authority in a user-owned Hub so terminals, plugins, and remote channels do not quietly become the trust root.
  actions:
    - theme: brand
      text: Read the architecture
      link: /architecture
    - theme: alt
      text: See the security model
      link: /security
    - theme: alt
      text: Browse the docs
      link: /docs

features:
  - title: Trust stays in the Hub
    details: Routing, memory, grants, policy, audit, and kill authority remain centralized instead of leaking into every client surface.
  - title: Autonomy stays governable
    details: Execution rights, supervision depth, review cadence, and intervention are explicit controls, not one vague auto mode.
  - title: Local and remote share one control plane
    details: Local models, paid models, paired terminals, and remote channels can all route through the same governed boundary.
---

<div class="preview-note">
  <strong>Public technical preview</strong>
  The architecture thesis is already real and runnable. Product polish, onboarding, and some capability surfaces are
  still moving quickly, so this homepage now focuses on the core story instead of repeating every surrounding detail.
</div>

<div class="landing-band">
  <div class="landing-panel kicker">
    <p class="landing-eyebrow">What X-Hub is</p>
    <h2>A control plane for AI execution, not another terminal wrapper.</h2>
    <p>
      X-Hub is built for teams that want agents to actually execute work, while keeping trust, grants, memory,
      audit, and kill authority in one governed Hub. Clients stay useful and replaceable, but they do not silently
      become the final authority.
    </p>
    <div class="landing-stat-grid">
      <div class="landing-stat">
        <strong>Hub-owned</strong>
        <span>Policy, routing, grants, audit, kill authority, and memory truth stay centralized.</span>
      </div>
      <div class="landing-stat">
        <strong>Fail-closed</strong>
        <span>Missing readiness or broken trust state should stop execution instead of faking safety.</span>
      </div>
      <div class="landing-stat">
        <strong>Local-first</strong>
        <span>Local models, optional paid models, and user-owned infrastructure can share one control plane.</span>
      </div>
    </div>
  </div>

  <div class="landing-panel">
    <p class="landing-eyebrow">What stays in the Hub</p>
    <ul class="landing-slab-list">
      <li>
        <strong>Trust boundary</strong>
        Clients, plugin bundles, and remote channels do not automatically become the trust root.
      </li>
      <li>
        <strong>Governance</strong>
        Autonomy, review, intervention, and runtime clamps remain explicit system controls.
      </li>
      <li>
        <strong>Memory and audit</strong>
        System truth stays attached to the Hub instead of fragmenting across clients and sessions.
      </li>
      <li>
        <strong>Runtime path</strong>
        Local models, paid models, paired terminals, and channel workers can all route through governed boundaries.
      </li>
    </ul>
  </div>
</div>

<div class="landing-proof">
  <p class="landing-eyebrow">How to read the system</p>
  <h2>One Hub, paired surfaces, explicit boundaries.</h2>
  <p>
    The shortest way to understand X-Hub is to think in three layers: a Hub that owns trust and policy, paired
    surfaces that expose rich interaction, and runtime paths that stay governable whether they are local or remote.
  </p>
  <div class="landing-proof-grid">
    <div class="landing-proof-card">
      <strong>Hub control plane</strong>
      <p>Trust, grants, policy, audit, routing, and memory truth stay anchored in one user-owned place.</p>
    </div>
    <div class="landing-proof-card">
      <strong>Paired interaction surfaces</strong>
      <p>X-Terminal and other rich surfaces can stay powerful without inheriting final authority.</p>
    </div>
    <div class="landing-proof-card">
      <strong>Governed runtime paths</strong>
      <p>Local models, remote providers, skills, and channel actions stay attached to explicit policy boundaries.</p>
    </div>
  </div>
</div>

<div class="landing-diagram-grid">
  <p class="landing-eyebrow">System shape</p>
  <h2>Product surface on top. Trusted control plane underneath.</h2>
  <div class="landing-diagrams">
    <div class="landing-diagram-card">
      <img src="/xhub_trust_control_plane.svg" alt="X-Hub trust and control plane diagram" />
      <div class="landing-diagram-copy">
        <strong>Trust and control plane</strong>
        X-Terminal follows the full governed path. Other clients can still use Hub capabilities without becoming equivalent trust roots.
      </div>
    </div>
    <div class="landing-diagram-card">
      <img src="/xhub_deployment_runtime_topology.svg" alt="X-Hub deployment and runtime topology diagram" />
      <div class="landing-diagram-copy">
        <strong>Deployment and runtime topology</strong>
        The user-owned Hub host stays central while local runtimes, channel workers, and optional external services remain governed edges.
      </div>
    </div>
  </div>
</div>

<div class="landing-compare">
  <p class="landing-eyebrow">Why it differs</p>
  <h2>Capability matters. Trust geometry matters more.</h2>
  <div class="landing-compare-table">
    <div class="landing-compare-row landing-compare-head">
      <div>Typical terminal-first agent</div>
      <div>X-Hub</div>
    </div>
    <div class="landing-compare-row">
      <div>Prompts, tools, memory, secrets, and execution often collapse into one runtime trust zone.</div>
      <div>The trust anchor moves into the Hub so clients can stay replaceable execution surfaces.</div>
    </div>
    <div class="landing-compare-row">
      <div>Higher autonomy often means blurrier supervision and weaker runtime truth.</div>
      <div>Autonomy, review, intervention, and clamps stay separated into explicit controls.</div>
    </div>
    <div class="landing-compare-row">
      <div>Remote providers, plugins, or channels often become hidden control surfaces by default.</div>
      <div>The Hub keeps policy, grants, audit, keys, and release timing under user control.</div>
    </div>
  </div>
  <p class="landing-compare-link">
    Want the fuller argument? <a href="/why-not-just-an-agent">Read why X-Hub is not just another agent stack.</a>
  </p>
</div>

<div class="landing-cta">
  <p class="landing-eyebrow">Start here</p>
  <h2>Start with the architecture, then go one layer deeper only when you need it.</h2>
  <p>
    The website is now intentionally simpler: homepage for orientation, deeper pages for the actual model, security,
    governance, and runtime details.
  </p>
  <div class="landing-cta-links">
    <a href="/architecture">Architecture</a>
    <a href="/security">Security</a>
    <a href="/why-not-just-an-agent">Why Not Just an Agent?</a>
    <a href="/docs">Documentation Map</a>
  </div>
</div>
