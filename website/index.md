---
layout: home

hero:
  name: X-Hub-System
  text: Governed Agent control plane.
  tagline: X-Hub-System centralizes model routing, memory truth, skills, provider accounts, quotas, grants, policy, audit, and terminal execution under one user-owned Hub.
  actions:
    - theme: brand
      text: Read the architecture
      link: /architecture
    - theme: alt
      text: See what it governs
      link: /skills
    - theme: alt
      text: Browse docs
      link: /docs

features:
  - title: Hub-first trust root
    details: The terminal can execute, but the Hub owns route truth, grants, policy, memory truth, audit, and kill authority.
  - title: Governed autonomy
    details: A-Tier, S-Tier, heartbeat, review, grants, and runtime clamps make autonomy visible instead of vague.
  - title: One model and capability plane
    details: Local models, paid providers, skills, channels, quotas, and fallback truth converge through one control boundary.
---

<section class="site-note">
  <strong>Public technical preview</strong>
  X-Hub-System is already runnable, but still in active productization. This site focuses on the architecture, the governed capability surface, and the reading path for people evaluating the system.
</section>

<section class="home-hero-band">
  <div class="home-hero-band__copy">
    <p class="home-kicker">Why it exists</p>
    <h2>Most agents get powerful by putting too much trust in one runtime.</h2>
    <p>
      X-Hub-System moves the trust anchor out of terminals, plugins, browser context, and vendor defaults. Clients can still be useful execution surfaces, but authority to route, grant, deny, remember, audit, and stop execution stays in the Hub.
    </p>
  </div>
  <div class="home-flow">
    <div class="home-flow__row">
      <span>Client asks</span>
      <strong>X-Terminal / generic clients / channels</strong>
    </div>
    <div class="home-flow__row">
      <span>Hub decides</span>
      <strong>policy, grants, memory, quotas, route truth</strong>
    </div>
    <div class="home-flow__row">
      <span>Surface acts</span>
      <strong>local models, paid APIs, tools, skills, connectors</strong>
    </div>
    <div class="home-flow__row">
      <span>Truth returns</span>
      <strong>audit, evidence, fallback, deny reasons, quota state</strong>
    </div>
  </div>
</section>

<section class="home-problems">
  <div class="home-section-head">
    <p class="home-kicker">What it solves</p>
    <h2>Built for execution range without trust sprawl.</h2>
    <p>The difference is not one feature. It is where the trust root lives and how every higher-risk surface is forced back through a governed boundary.</p>
  </div>

  <div class="home-problem-table">
    <div class="home-problem-row home-problem-row--head">
      <div>Common agent-stack failure mode</div>
      <div>X-Hub-System design response</div>
    </div>
    <div class="home-problem-row">
      <div>Prompts, tools, memory, secrets, and execution collapse into one runtime trust zone.</div>
      <div>The Hub owns trust, grants, route truth, memory truth, policy, audit, and kill authority.</div>
    </div>
    <div class="home-problem-row">
      <div>Plugin installation silently expands privilege.</div>
      <div>Skills use manifests, trust roots, pins, preflight checks, grants, deny codes, revocation, and audit.</div>
    </div>
    <div class="home-problem-row">
      <div>Local models and paid APIs drift into separate governance paths.</div>
      <div>Model routing, provider accounts, OAuth/key state, quotas, fallback, and downgrade truth converge in one plane.</div>
    </div>
    <div class="home-problem-row">
      <div>Remote channels become shadow control planes.</div>
      <div>Slack, Telegram, Feishu, voice, and mobile-style ingress converge through authz, replay guard, grants, and audit.</div>
    </div>
    <div class="home-problem-row">
      <div>Auto mode hides risk and weakens supervision.</div>
      <div>A-Tier, S-Tier, heartbeat, review, grants, runtime clamps, and kill switches keep autonomy governable.</div>
    </div>
  </div>
</section>

<section class="home-capabilities">
  <div class="home-section-head">
    <p class="home-kicker">Governed capability surface</p>
    <h2>One Hub authority above many AI execution surfaces.</h2>
    <p>X-Hub-System is designed to govern a growing set of model, memory, skill, quota, terminal, channel, and evidence surfaces without making each one a new control plane.</p>
  </div>

  <div class="home-capability-grid">
    <a class="home-capability-card" href="/architecture">
      <span>Trust</span>
      <strong>Hub-owned control plane</strong>
      <p>Identity, pairing, policy, grants, readiness, and kill-switch posture stay centralized.</p>
    </a>
    <a class="home-capability-card" href="/local-first">
      <span>Models</span>
      <strong>Local + paid routing</strong>
      <p>Configured route, actual route, fallback, downgrade, and provider readiness stay visible.</p>
    </a>
    <a class="home-capability-card" href="/skills">
      <span>Skills</span>
      <strong>Governed skill packages</strong>
      <p>Official skills, manifests, trust roots, pins, preflight gates, grants, and revocation.</p>
    </a>
    <a class="home-capability-card" href="/governed-autonomy">
      <span>Autonomy</span>
      <strong>Supervisor-grade controls</strong>
      <p>Execution authority, review depth, heartbeat cadence, guidance, and intervention are separate controls.</p>
    </a>
    <a class="home-capability-card" href="/channels-and-voice">
      <span>Ingress</span>
      <strong>Channels and voice</strong>
      <p>Remote operator surfaces can enter through replay guard, challenge, grant, and audit paths.</p>
    </a>
    <a class="home-capability-card" href="/security">
      <span>Evidence</span>
      <strong>Runtime truth</strong>
      <p>Audit refs, evidence refs, denial reasons, quota pressure, and recovery signals remain operator-visible.</p>
    </a>
  </div>
</section>

<section class="home-diagrams">
  <div class="home-section-head">
    <p class="home-kicker">System shape</p>
    <h2>Two views: the authority boundary and the governed capability map.</h2>
    <p>These diagrams are the fastest way to see what X-Hub-System is trying to make governable.</p>
  </div>

  <div class="home-diagrams__grid">
    <div class="home-diagram-card">
      <img src="/xhub_trust_control_plane.svg" alt="X-Hub trust and control plane diagram" />
      <div class="home-diagram-card__copy">
        <strong>Trust and control plane</strong>
        Clients can ask. The Hub decides. Execution surfaces act only after governance, and runtime truth returns to the Hub.
      </div>
    </div>
    <div class="home-diagram-card">
      <img src="/xhub_deployment_runtime_topology.svg" alt="X-Hub governed capability map diagram" />
      <div class="home-diagram-card__copy">
        <strong>Governed capability map</strong>
        Models, memory, skills, quotas, terminals, channels, Supervisor state, and runtime evidence converge through one authority boundary.
      </div>
    </div>
  </div>
</section>

<section class="home-readpath">
  <div class="home-section-head">
    <p class="home-kicker">Reading path</p>
    <h2>Evaluate the system from architecture to operator surface.</h2>
  </div>
  <div class="home-readpath__grid">
    <a href="/architecture">Architecture</a>
    <a href="/security">Trust model</a>
    <a href="/why-not-just-an-agent">Why not just an agent?</a>
    <a href="/governed-autonomy">Governed autonomy</a>
    <a href="/skills">Governed skills</a>
    <a href="/docs">Documentation map</a>
  </div>
</section>
