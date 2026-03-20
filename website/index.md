---
layout: home

hero:
  name: X-Hub
  text: The user-owned AI control plane.
  tagline: Governed execution for agents, terminals, local runtimes, and remote channels without making the client, plugin bundle, or cloud vendor the trust root.
  actions:
    - theme: brand
      text: Read the architecture
      link: /architecture
    - theme: alt
      text: Why not just an agent?
      link: /why-not-just-an-agent
    - theme: alt
      text: See the security model
      link: /security

features:
  - title: Hub-owned trust boundary
    details: Routing, memory truth, grants, policy, audit, and kill authority stay in the Hub instead of leaking into every client surface.
  - title: Governed autonomy
    details: Execution power, supervision depth, review cadence, and intervention behavior are treated as separate controls, not one vague auto mode.
  - title: Local-first multisurface runtime
    details: Local models, paid models, voice surfaces, and remote channels can sit under one governed control plane with user-controlled release timing.
---

<div class="hero-superframe">
  <div class="hero-stage">
    <div class="hero-story">
      <p class="hero-badge">Public technical preview</p>
      <h2>Build agents that can actually run projects, while keeping execution governable, inspectable, and locally owned.</h2>
      <p>
        X-Hub is for teams that have already realized raw agent capability is not the hard part. The hard part is
        trust geometry: where memory truth lives, who owns grants, where audit belongs, how supervision works, and
        which surface gets final authority. X-Hub moves those responsibilities into the Hub, so clients can stay fast
        without silently becoming the trust root.
      </p>
      <div class="hero-chip-row">
        <span class="hero-chip">Hub-first trust model</span>
        <span class="hero-chip">Governed autonomy tiers</span>
        <span class="hero-chip">Voice and channel supervision</span>
        <span class="hero-chip">Local-first provider packs</span>
      </div>
      <div class="hero-trust-grid">
        <div class="hero-trust-card">
          <strong>Memory, grants, and audit stay centralized.</strong>
          <span>Execution surfaces can change without rewriting the trust boundary.</span>
        </div>
        <div class="hero-trust-card">
          <strong>High autonomy does not mean root without oversight.</strong>
          <span>Supervision, intervention, and system safety controls still apply.</span>
        </div>
        <div class="hero-trust-card">
          <strong>Remote channels enter through one governed ingress.</strong>
          <span>External channels and paired interaction surfaces stay attached to the same control plane.</span>
        </div>
        <div class="hero-trust-card">
          <strong>User-owned local runtime remains a first-class path.</strong>
          <span>Models, keys, privacy posture, and release timing stay in the user's hands.</span>
        </div>
      </div>
    </div>

<HeroConsole />
  </div>
</div>

<div class="landing-band">
  <div class="landing-panel kicker">
    <p class="landing-eyebrow">Built for serious operators</p>
    <h2>For teams that want agents to execute without surrendering the trust boundary.</h2>
    <p>
      X-Hub is not another terminal wrapper. It is a system architecture for governed AI execution:
      one Hub for memory truth, constitutional policy, grants, audit, runtime truth, and execution safety;
      one paired X-Terminal for rich operator interaction; thinner generic clients that can consume governed
      capabilities without silently becoming the trust root.
    </p>
    <div class="landing-stat-grid">
      <div class="landing-stat">
        <strong>Hub-owned</strong>
        <span>Policy, grants, audit, routing, kill authority, and memory truth stay centralized.</span>
      </div>
      <div class="landing-stat">
        <strong>Fail-closed</strong>
        <span>Missing readiness, ambiguous grants, or broken trust state should stop execution rather than fake safety.</span>
      </div>
      <div class="landing-stat">
        <strong>Local-first</strong>
        <span>Run local models, multimodal runtimes, and user-owned infrastructure without giving up governance.</span>
      </div>
    </div>
  </div>

  <div class="landing-panel">
    <p class="landing-eyebrow">Why it feels different</p>
    <ul class="landing-slab-list">
      <li>
        <strong>Not terminal-first</strong>
        The terminal can be fast, replaceable, and productized without inheriting final trust authority.
      </li>
      <li>
        <strong>Not prompt-only safety</strong>
        Memory-backed constitutional guidance, grants, audit, and runtime clamps reinforce each other.
      </li>
      <li>
        <strong>Not black-box autonomy</strong>
        Higher execution range does not erase supervision, correction, or kill-switch posture.
      </li>
      <li>
        <strong>Not cloud-default control</strong>
        Permissions, keys, release timing, privacy posture, and remote-provider usage remain user decisions.
      </li>
    </ul>
  </div>
</div>

<div class="landing-proof">
  <p class="landing-eyebrow">Core system signature</p>
  <h2>One architecture, four reinforcing planes.</h2>
  <p>
    The strength of X-Hub is not one isolated feature. It is the combination of trust-plane redesign,
    governed autonomy, governed skills, memory truth, and multimodal supervision under one user-owned
    control plane.
  </p>
  <div class="landing-proof-grid">
    <div class="landing-proof-card">
      <strong>Trust plane</strong>
      <p>Move the trust anchor out of the terminal, plugin bundle, and vendor cloud default into the Hub.</p>
    </div>
    <div class="landing-proof-card">
      <strong>Governance plane</strong>
      <p>Separate execution rights, review depth, intervention mode, and cadence so autonomy remains governable.</p>
    </div>
    <div class="landing-proof-card">
      <strong>Execution plane</strong>
      <p>Treat skills, tools, automation, and channel actions as governed capability paths, not loose script power.</p>
    </div>
    <div class="landing-proof-card">
      <strong>Memory and evidence plane</strong>
      <p>Keep memory truth, audit, runtime truth, and review evidence attached to the system of record.</p>
    </div>
  </div>
</div>

<div class="landing-diagram-grid">
  <p class="landing-eyebrow">How the system is shaped</p>
  <h2>Product surface on top. Trusted control plane underneath.</h2>
  <div class="landing-diagrams">
    <div class="landing-diagram-card">
      <img src="/xhub_trust_control_plane.svg" alt="X-Hub trust and control plane diagram" />
      <div class="landing-diagram-copy">
        <strong>Trust and control plane</strong>
        X-Terminal follows the full governed path. Generic terminals can still use Hub capabilities without becoming equivalent trust roots.
      </div>
    </div>
    <div class="landing-diagram-card">
      <img src="/xhub_deployment_runtime_topology.svg" alt="X-Hub deployment and runtime topology diagram" />
      <div class="landing-diagram-copy">
        <strong>Deployment and runtime topology</strong>
        The user-owned Hub host stays central while local runtimes, channel workers, and optional external services remain governed boundaries.
      </div>
    </div>
  </div>
</div>

<div class="landing-grid">
  <div class="landing-proof-card">
    <strong>Source-aware voice authorization</strong>
    <p>Remote-channel pending grants can be announced, repeated, targeted, and approved through a Hub-governed voice challenge loop.</p>
  </div>
  <div class="landing-proof-card">
    <strong>Safe operator-channel onboarding</strong>
    <p>Slack, Telegram, and Feishu ingress can enter discovery, require local admin approval once, auto-bind, and run a first smoke under Hub control.</p>
  </div>
  <div class="landing-proof-card">
    <strong>Provider-pack truth for local runtime</strong>
    <p>Embeddings, speech, vision, and OCR are moving under one local-runtime product surface with compatibility policy, quick bench, and fail-closed provider truth.</p>
  </div>
</div>

<div class="landing-compare">
  <p class="landing-eyebrow">Why not just another agent stack</p>
  <h2>Capability matters. Trust geometry matters more.</h2>
  <div class="landing-compare-table">
    <div class="landing-compare-row landing-compare-head">
      <div>Typical terminal-first agent</div>
      <div>X-Hub</div>
    </div>
    <div class="landing-compare-row">
      <div>Prompts, tools, memory, secrets, and execution often collapse into one runtime trust zone.</div>
      <div>Trust anchor moves into the Hub so terminals can stay replaceable execution surfaces.</div>
    </div>
    <div class="landing-compare-row">
      <div>Higher autonomy often means blurrier supervision and weaker runtime truth.</div>
      <div>Autonomy, review, intervention, and clamps are separated into explicit controls.</div>
    </div>
    <div class="landing-compare-row">
      <div>Plugins and skills often expand privilege by default once installed.</div>
      <div>Skills are moving through a governed trust chain with manifests, pinning, review, and revocation.</div>
    </div>
    <div class="landing-compare-row">
      <div>Cloud defaults often become the hidden control plane.</div>
      <div>User-owned Hub keeps permissions, policy, keys, audit, and release timing under local control.</div>
    </div>
  </div>
  <p class="landing-compare-link">
    Want the fuller argument? <a href="/why-not-just-an-agent">Read why X-Hub is not just another agent stack.</a>
  </p>
</div>

<div class="landing-audience">
  <div class="landing-panel">
    <p class="landing-eyebrow">Who this is for</p>
    <h2>Teams that need real execution, but cannot afford soft trust boundaries.</h2>
    <p>
      X-Hub is especially well suited for security-conscious software teams, operator-led automation programs,
      public-sector and regulated environments, and serious individual builders who want a safer local-first posture
      than terminal-only AI tools usually provide.
    </p>
  </div>
  <div class="landing-panel">
    <p class="landing-eyebrow">What to expect now</p>
    <h2>Public tech preview, not a polished mass-market product.</h2>
    <p>
      The architecture thesis is already concrete. Core runtime paths are real. Product polish, onboarding,
      deployment UX, and some capability surfaces are still moving fast. This site is meant to make the system legible
      before every surrounding edge is finished.
    </p>
  </div>
</div>

<div class="landing-cta">
  <p class="landing-eyebrow">Start from the right layer</p>
  <h2>Start with the public architecture story. Deeper implementation detail will expand as the product surface stabilizes.</h2>
  <p>
    This site is the selective public narrative layer for the repository. The pages here are meant to make the system
    legible without turning every still-moving implementation path into front-page product copy.
  </p>
  <div class="landing-cta-links">
    <a href="/architecture">Architecture</a>
    <a href="/security">Security</a>
    <a href="/governed-autonomy">Governed Autonomy</a>
    <a href="/channels-and-voice">Channels and Voice</a>
    <a href="/local-first">Local First</a>
    <a href="/skills">Skills</a>
    <a href="/docs">Documentation Map</a>
  </div>
</div>
