---
layout: home

hero:
  name: X-Hub-System
  text: A secure AI Hub for real work.
  tagline: Manage models, memory, skills, quotas, grants, audit, and execution from one user-owned Hub.
  actions:
    - theme: brand
      text: Get started
      link: /get-started
    - theme: alt
      text: View GitHub
      link: https://github.com/AndrewXie-Rich/x-hub-system
    - theme: alt
      text: Check status
      link: /status-roadmap

features:
  - title: Security is a core capability
    details: High-risk actions pass through authorization, signed intent, audit, and revocable controls before execution.
  - title: Manage AI capability in one place
    details: Local models, paid providers, account quota, memory, skills, and channels are governed from the Hub.
  - title: Built for continuous work
    details: X-Terminal, Supervisor state, project continuity, governed skills, and local runtime paths support longer AI workflows without losing control.
---

<section class="site-note">
  <strong>Public technical preview</strong>
  X-Hub-System is already runnable and moving toward a Swift Hub UI with a Rust kernel/runtime. The product is still being hardened, but the direction is simple: let AI do more while permissions, memory, quota, and audit remain under control.
</section>

<section class="home-hero-band">
  <div class="home-hero-band__copy">
    <p class="home-kicker">Security-first AI Hub</p>
    <h2>Clients handle interaction. The Hub handles safety decisions.</h2>
    <p>
      X-Hub-System brings models, memory, skills, account quota, and external actions into one governed center. You can use multiple clients and channels, while permissions, routing, audit, and shutdown controls stay in the Hub.
    </p>
  </div>
  <div class="home-flow">
    <div class="home-flow__row">
      <span>Ask</span>
      <strong>X-Terminal, clients, voice, or remote channels submit work</strong>
    </div>
    <div class="home-flow__row">
      <span>Decide</span>
      <strong>Hub checks models, memory, quota, grants, and safety policy</strong>
    </div>
    <div class="home-flow__row">
      <span>Execute</span>
      <strong>local models, paid APIs, skills, tools, or connectors act within scope</strong>
    </div>
    <div class="home-flow__row">
      <span>Record</span>
      <strong>results, evidence, denial reasons, downgrade state, and audit return to the Hub</strong>
    </div>
  </div>
</section>

<section class="home-readpath home-readpath--compact">
  <div class="home-section-head">
    <p class="home-kicker">Quick entry</p>
    <h2>Download, build, or contribute.</h2>
  </div>
  <div class="home-readpath__grid">
    <a href="/get-started">Get started</a>
    <a href="https://github.com/AndrewXie-Rich/x-hub-system/releases">Download release</a>
    <a href="https://github.com/AndrewXie-Rich/x-hub-system">GitHub repo</a>
    <a href="/status-roadmap">Status & roadmap</a>
  </div>
</section>

<section class="home-problems">
  <div class="home-section-head">
    <p class="home-kicker">What it solves</p>
    <h2>As ordinary agents add more tools, permissions and risk spread out.</h2>
    <p>X-Hub-System pulls the important pieces back into one Hub: models, memory, skills, quota, grants, audit, and shutdown controls.</p>
  </div>

  <div class="home-problem-table">
    <div class="home-problem-row home-problem-row--head">
      <div>Common agent-stack failure mode</div>
      <div>X-Hub-System design response</div>
    </div>
    <div class="home-problem-row">
      <div>New devices and remote access can become trusted too casually.</div>
      <div>The Hub records and manages device access, network source, token state, and revocation.</div>
    </div>
    <div class="home-problem-row">
      <div>Prompts, tools, memory, secrets, and external actions are often mixed inside the active client.</div>
      <div>The Hub manages model routing, grants, memory, policy, audit, and shutdown controls. Clients focus on interaction and display.</div>
    </div>
    <div class="home-problem-row">
      <div>Prompt injection or hostile documents can steer the active agent toward exfiltration or destructive work.</div>
      <div>X-Constitution, policy, grants, signed intent, and audit make safety a system mechanism, not just another prompt instruction.</div>
    </div>
    <div class="home-problem-row">
      <div>Plugin installation silently expands privilege.</div>
      <div>Skills are governed capability packages with manifests, source checks, pinned versions, preflight, grants, denial, revocation, and audit.</div>
    </div>
    <div class="home-problem-row">
      <div>Local models, paid APIs, OAuth accounts, and quota screens split into separate operational worlds.</div>
      <div>Configured model, actual model, downgrade path, account state, and quota pressure are shown through the Hub.</div>
    </div>
  </div>
</section>

<section class="home-capabilities">
  <div class="home-section-head">
    <p class="home-kicker">The governed surface</p>
    <h2>Bring AI capability into one controllable center.</h2>
    <p>This is not another chat UI. It is a place to authorize, inspect, audit, and revoke models, memory, skills, channels, quota, and external actions.</p>
  </div>

  <div class="home-capability-grid">
    <a class="home-capability-card" href="/security">
      <span>Pairing</span>
      <strong>Same-Wi-Fi first trust</strong>
      <p>Initial pairing is kept local, explicit, and revocable instead of turning every remote surface into a trusted doorway.</p>
    </a>
    <a class="home-capability-card" href="/architecture">
      <span>Trust</span>
      <strong>Hub-owned control plane</strong>
      <p>Identity, policy, grants, route truth, memory truth, readiness, audit, and kill-switch posture stay centralized.</p>
    </a>
    <a class="home-capability-card" href="/constitution">
      <span>Constitution</span>
      <strong>Value constraints above tasks</strong>
      <p>X-Constitution is designed as a pinned, governed constraint layer for prompt-injection, destructive, and privilege-escalation risks.</p>
    </a>
    <a class="home-capability-card" href="/local-first">
      <span>Models</span>
      <strong>Local + paid routing</strong>
      <p>Local runtimes and paid providers sit under the same route, quota, readiness, fallback, and downgrade truth plane.</p>
    </a>
    <a class="home-capability-card" href="/skills">
      <span>Skills</span>
      <strong>Governed skill packages</strong>
      <p>Official skills, manifests, trust roots, package pins, vetting, compatibility checks, grants, and revocation.</p>
    </a>
    <a class="home-capability-card" href="/x-terminal">
      <span>Autonomy</span>
      <strong>Supervisor-grade controls</strong>
      <p>Execution range, review depth, heartbeat cadence, intervention behavior, and runtime clamps are separate controls.</p>
    </a>
    <a class="home-capability-card" href="/channels-and-voice">
      <span>Ingress</span>
      <strong>Channels and voice</strong>
      <p>Remote operator surfaces can enter through identity binding, replay guard, challenge, grant targeting, and audit.</p>
    </a>
    <a class="home-capability-card" href="/memory">
      <span>Memory</span>
      <strong>Governed memory control plane</strong>
      <p>Durable facts, working state, role-aware context, writeback candidates, export gates, and audit evidence stay Hub-governed.</p>
    </a>
    <a class="home-capability-card" href="/coding-runtime">
      <span>Coding</span>
      <strong>Runtime for long-running projects</strong>
      <p>Plan, execute, verify, review, resume, and recover inside one governed coding chain.</p>
    </a>
  </div>
</section>

<section class="home-usecases">
  <div class="home-section-head">
    <p class="home-kicker">Where it becomes useful</p>
    <h2>Designed for AI work that keeps running after the first prompt.</h2>
    <p>The whitepaper scenarios point to the same product shape: AI can work across devices, projects, providers, and channels while the important controls stay in the Hub.</p>
  </div>

  <div class="home-usecase-grid">
    <div class="home-usecase-card">
      <span>Personal builders</span>
      <strong>One Hub for projects, models, quota, and memory</strong>
      <p>Use local models for private work, paid models when needed, and keep route truth, quota pressure, and long-running project state visible.</p>
    </div>
    <div class="home-usecase-card">
      <span>Family and device sharing</span>
      <strong>Useful terminals that do not control everything</strong>
      <p>Lightweight clients can consume AI capability while the Hub controls pairing, access, memory boundaries, provider accounts, and revocation.</p>
    </div>
    <div class="home-usecase-card">
      <span>Small teams</span>
      <strong>Auditable AI work without handing trust to every client</strong>
      <p>Team members can use governed AI capability while admins keep control over models, skills, external actions, and release posture.</p>
    </div>
    <div class="home-usecase-card">
      <span>Supervisor work</span>
      <strong>One operator, multiple active projects</strong>
      <p>Heartbeat, review, grants, safe-point guidance, and intervention are separated so multi-project automation stays legible.</p>
    </div>
    <div class="home-usecase-card">
      <span>High-risk execution</span>
      <strong>Signed intent before irreversible side effects</strong>
      <p>Payments, outbound actions, merges, and connector writes can be forced through Hub-signed manifests, SAS, grants, audit, and kill switches.</p>
    </div>
    <div class="home-usecase-card">
      <span>Skill ecosystems</span>
      <strong>Reusable capability without install-equals-trust</strong>
      <p>Skills can become durable execution units while remaining reviewable, pin-able, compatible, auditable, retryable, and revocable.</p>
    </div>
  </div>
</section>

<section class="home-diagrams">
  <div class="home-section-head">
    <p class="home-kicker">System shape</p>
    <h2>Two views: who decides, and what the Hub manages.</h2>
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
        Models, memory, skills, quotas, terminals, channels, Supervisor state, and runtime evidence converge through one Hub management surface.
      </div>
    </div>
  </div>
</section>

<section class="home-readpath">
  <div class="home-section-head">
    <p class="home-kicker">Reading path</p>
    <h2>Evaluate the system from safety boundary to operator surface.</h2>
  </div>
  <div class="home-readpath__grid">
    <a href="/scenarios">Use cases</a>
    <a href="/security">Trust model</a>
    <a href="/constitution">X-Constitution</a>
    <a href="/memory">Memory control plane</a>
    <a href="/x-terminal">X-Terminal</a>
    <a href="/coding-runtime">Coding runtime</a>
    <a href="/architecture">Architecture</a>
    <a href="/skills">Governed skills</a>
    <a href="/get-started">Get started</a>
    <a href="/status-roadmap">Status roadmap</a>
    <a href="/docs">Documentation map</a>
  </div>
</section>
