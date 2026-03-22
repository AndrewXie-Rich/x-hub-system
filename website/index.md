---
layout: home

hero:
  name: X-Hub
  text: Governed AI execution for teams that need real control.
  tagline: X-Hub unifies trust, routing, memory truth, grants, audit, and runtime posture in one user-owned control plane.
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
  - title: Hub-owned trust root
    details: Policy, routing, memory truth, grants, audit, and kill authority stay in the Hub instead of leaking into every client.
  - title: Governed execution model
    details: Autonomy, review, intervention, and runtime clamps remain explicit controls rather than collapsing into one vague auto mode.
  - title: Local-first runtime boundary
    details: Local models, paid models, paired terminals, and remote channels can all route through the same governed control plane.
---

<div class="preview-note">
  <strong>Public technical preview</strong>
  The architecture thesis is already real and runnable. Product polish, onboarding, and some capability surfaces are
  still moving quickly, so the homepage focuses on the core system shape and reading path rather than every evolving detail.
</div>

<div class="home-signal-strip">
  <span>Hub-first trust model</span>
  <span>Fail-closed by design</span>
  <span>Local-first, cloud-optional</span>
  <span>Governed autonomy</span>
</div>

<div class="home-citadel">
  <div class="home-citadel__story">
    <p class="home-kicker">Official site</p>
    <h2>The safer way to run serious AI systems.</h2>
    <p class="home-lead">
      Most AI products optimize for raw capability first and hope trust holds later. X-Hub starts from the control
      plane: who owns authority, how execution gets governed, where memory truth lives, and how runtime posture stays
      visible when the system moves from chat into action. For memory specifically, the user still chooses which AI
      executes memory jobs in X-Hub, and durable memory truth still lands through `Writer + Gate`.
    </p>
    <div class="home-assurance-grid">
      <div class="home-assurance">
        <strong>Hub-owned trust root</strong>
        <span>Policy, grants, audit, routing, and kill authority stay in one governed place.</span>
      </div>
      <div class="home-assurance">
        <strong>Fail-closed posture</strong>
        <span>Broken readiness or stale trust state should block execution instead of faking confidence.</span>
      </div>
      <div class="home-assurance">
        <strong>Local-first operating path</strong>
        <span>Local models, optional paid models, and user-owned infrastructure can share one policy boundary.</span>
      </div>
    </div>
  </div>

  <div class="home-citadel__panel">
    <div class="home-panel">
      <p class="home-panel__eyebrow">System posture</p>
      <div class="home-panel__row">
        <span>Trust root</span>
        <strong>Hub</strong>
      </div>
      <div class="home-panel__row">
        <span>Final authority</span>
        <strong>Explicit grants</strong>
      </div>
      <div class="home-panel__row">
        <span>Memory truth</span>
        <strong>Hub-anchored</strong>
      </div>
      <div class="home-panel__row">
        <span>Operating posture</span>
        <strong>Visible and governed</strong>
      </div>
    </div>

    <div class="home-stack">
      <div class="home-stack__card">
        <label>Product surface</label>
        <strong>X-Hub</strong>
        <p>The user-owned control plane for trust, routing, policy, grants, audit, and runtime posture.</p>
      </div>
      <div class="home-stack__card">
        <label>Paired surface</label>
        <strong>X-Terminal</strong>
        <p>The deep interaction surface for governed execution, review, and operator visibility.</p>
      </div>
      <div class="home-stack__card">
        <label>Governed runtime</label>
        <strong>Clients, channels, local and paid models</strong>
        <p>Execution surfaces remain useful and extensible without silently becoming the new trust boundary.</p>
      </div>
    </div>
  </div>
</div>

<div class="home-value">
  <div class="home-section-head">
    <p class="home-kicker">Why teams choose X-Hub</p>
    <h2>Built for execution range without trust sprawl.</h2>
    <p>X-Hub is for teams that need the system to act, but still need the operating boundary to remain defensible.</p>
  </div>

  <div class="home-value__grid">
    <a class="home-value-card" href="/architecture">
      <span>Authority</span>
      <strong>Keep the trust boundary where it belongs</strong>
      <p>The terminal, plugin bundle, remote channel, and model vendor do not become the default control plane.</p>
      <em>User-owned control plane</em>
    </a>

    <a class="home-value-card" href="/security">
      <span>Posture</span>
      <strong>Favor fail-closed behavior over false confidence</strong>
      <p>When readiness is broken or trust is stale, the system should block instead of pretending everything is fine.</p>
      <em>Security-first operating model</em>
    </a>

    <a class="home-value-card" href="/governed-autonomy">
      <span>Execution</span>
      <strong>Scale autonomy without turning it into black-box drift</strong>
      <p>Autonomy, review, intervention, and clamps remain visible controls instead of collapsing into one auto mode.</p>
      <em>Governed execution</em>
    </a>
  </div>
</div>

<div class="home-product">
  <div class="home-section-head">
    <p class="home-kicker">Product surface</p>
    <h2>One control plane. Multiple governed surfaces.</h2>
    <p>X-Hub is not one chat window. It is a Hub-first product surface built for real execution.</p>
  </div>

  <div class="home-product__grid">
    <div class="home-product-card">
      <label>Control plane</label>
      <strong>X-Hub</strong>
      <p>The core product surface for policy, routing, memory truth, grants, audit, and runtime posture, including Hub-side memory control where the user chooses the executor and durable writes still terminate through `Writer + Gate`.</p>
    </div>
    <div class="home-product-card">
      <label>Paired surface</label>
      <strong>X-Terminal</strong>
      <p>The deep paired experience for execution, review, visibility, and governed interaction.</p>
    </div>
    <div class="home-product-card">
      <label>Governed runtime</label>
      <strong>Local models, paid models, channels, and tools</strong>
      <p>Execution can expand across surfaces without letting the execution surface become sovereign.</p>
    </div>
  </div>
</div>

<div class="home-diagrams">
  <div class="home-section-head">
    <p class="home-kicker">System shape</p>
    <h2>Product surface above. Trusted control plane underneath.</h2>
    <p>These two diagrams are the shortest visual explanation of how X-Hub is meant to be read.</p>
  </div>

  <div class="home-diagrams__grid">
    <div class="home-diagram-card">
      <img src="/xhub_trust_control_plane.svg" alt="X-Hub trust and control plane diagram" />
      <div class="home-diagram-card__copy">
        <strong>Trust and control plane</strong>
        X-Terminal follows the deep governed path. Other clients can still consume Hub capabilities without becoming equivalent trust roots.
      </div>
    </div>
    <div class="home-diagram-card">
      <img src="/xhub_deployment_runtime_topology.svg" alt="X-Hub deployment and runtime topology diagram" />
      <div class="home-diagram-card__copy">
        <strong>Deployment and runtime topology</strong>
        The user-owned Hub host stays central while local runtimes, channel workers, and optional external services remain governed edges.
      </div>
    </div>
  </div>
</div>

<div class="home-contrast">
  <div class="home-section-head">
    <p class="home-kicker">Why it feels different</p>
    <h2>Not another terminal-first agent wrapper.</h2>
    <p>The difference is not a feature list. The difference is where the trust root lives and how execution stays governable.</p>
  </div>

  <div class="home-contrast__table">
    <div class="home-contrast__row home-contrast__row--head">
      <div>Typical terminal-first agent</div>
      <div>X-Hub</div>
    </div>
    <div class="home-contrast__row">
      <div>Prompts, tools, memory, secrets, and execution often collapse into one runtime trust zone.</div>
      <div>The trust anchor moves into the Hub so clients can stay useful, replaceable execution surfaces.</div>
    </div>
    <div class="home-contrast__row">
      <div>Higher autonomy often means blurrier supervision and weaker runtime truth.</div>
      <div>Autonomy, review, intervention, and clamps stay separated into explicit controls.</div>
    </div>
    <div class="home-contrast__row">
      <div>Remote providers, plugins, or channels often become hidden control surfaces by default.</div>
      <div>The Hub keeps policy, grants, audit, keys, and release timing under user control.</div>
    </div>
  </div>

  <p class="home-contrast__link">
    Want the fuller argument? <a href="/why-not-just-an-agent">Read why X-Hub is not just another agent stack.</a>
  </p>
</div>

<div class="home-cta-band">
  <div class="home-section-head">
    <p class="home-kicker">Start here</p>
    <h2>Use X-Hub like a platform, not just another agent demo.</h2>
    <p>Start with the control plane story, inspect the trust model, or go straight into the docs.</p>
  </div>

  <div class="home-cta-band__actions">
    <a href="/architecture">Explore Architecture</a>
    <a href="/security">Read the Trust Model</a>
    <a href="/docs">Browse Documentation</a>
  </div>
</div>
