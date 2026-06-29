---
layout: home

hero:
  name: X-Hub-System
  text: Don't trust AI to hold its own leash.
  tagline: A self-hosted Hub that sits between you and Claude, GPT, or local models, so you can see what actually ran and catch the bad calls before they land. Memory and audit follow you when you switch providers.
  actions:
    - theme: brand
      text: View on GitHub
      link: https://github.com/AndrewXie-Rich/x-hub-system
    - theme: alt
      text: How it works (30 sec)
      link: /architecture

features:
  - title: For my family
    details: Kids using AI shouldn't mean handing AI admin rights to your house. See what they ask. Set spending limits. Get a tap on your phone before AI deletes, sends, or pays. Parent runs the Hub; kids' clients can't go around it.
    link: /family
    linkText: How it works for families
  - title: For myself (developer)
    details: Self-host one Hub. Keep using Cursor, Claude Code, ChatGPT — they sit on top of it. See the actual model that ran, why a fallback happened, and what a rogue MCP server tried to do. Switch providers without rebuilding memory.
    link: /get-started
    linkText: Quick start
  - title: For my team or organization
    details: Code, prompts, memory can't go through SaaS-only AI tools. One Hub, multi-user roles, audit you can hand to compliance. EU AI Act / ISO 42001 procurement-ready under commercial license.
    link: /team
    linkText: How it works for teams
---

<section class="site-note">
  <strong>Public technical preview.</strong>
  Core paths run. Onboarding and packaging are still rough. Per-surface honest status:
  <a href="https://github.com/AndrewXie-Rich/x-hub-system/blob/main/docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md">capability matrix</a>.
</section>

<section class="home-capabilities">
  <div class="home-section-head">
    <p class="home-kicker">Capabilities</p>
    <h2>Eight things X-Hub does that the agent on its own doesn't.</h2>
    <p>Each card shows whether the capability is <code>validated</code> or in <code>preview</code>. The <a href="https://github.com/AndrewXie-Rich/x-hub-system/blob/main/docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md">capability matrix</a> remains the source of truth for exact status.</p>
  </div>

  <div class="home-capability-grid">
    <a class="home-capability-card" href="/security">
      <span>validated</span>
      <strong>Stop a wrong action before it runs.</strong>
      <p>When the AI tries to write the wrong file, hit the wrong endpoint, or call a tool it shouldn't, the system blocks it before it happens — not after.</p>
    </a>
    <a class="home-capability-card" href="/x-terminal">
      <span>preview</span>
      <strong>See the model that actually ran.</strong>
      <p>Configured vs actual model. Why the fallback fired. Which provider got billed. No silent route swaps hiding inside chat history.</p>
    </a>
    <a class="home-capability-card" href="/memory">
      <span>validated</span>
      <strong>Switch providers, keep your memory.</strong>
      <p>Project state, long-term facts, X-Constitution, and decisions live in the Hub — not inside Claude or Cursor. Move providers without rebuilding context.</p>
    </a>
    <a class="home-capability-card" href="/local-first">
      <span>preview</span>
      <strong>Mix local and paid AI under one budget.</strong>
      <p>Local models for sensitive work, paid Claude / GPT when you need them. One quota view. One fallback policy. One audit trail.</p>
    </a>
    <a class="home-capability-card" href="/skills">
      <span>preview</span>
      <strong>Install a tool without trusting its author.</strong>
      <p>MCP servers, plugins, skills — all checked for signed source, pinned version, declared capability. A "PDF parser" that quietly asks for shell access gets stopped.</p>
    </a>
    <a class="home-capability-card" href="/governed-autonomy">
      <span>preview</span>
      <strong>Set how much the AI can do on its own — separately from how often you watch.</strong>
      <p>Three independent dials: execution authority, supervision depth, review cadence. Not one autonomy slider that erases oversight.</p>
    </a>
    <a class="home-capability-card" href="/architecture">
      <span>validated</span>
      <strong>Use AI from anywhere, but trust it from one place.</strong>
      <p>Voice, Slack, Telegram, Feishu, mobile confirmation — all enter through identity binding and revocable grants. Never a direct line to your AI.</p>
    </a>
    <a class="home-capability-card" href="/coding-runtime">
      <span>preview</span>
      <strong>Leave AI running on a project, come back to evidence.</strong>
      <p>Plan, execute, verify, review, resume, recover. When AI claims "done," there's signed evidence — not just a model assertion.</p>
    </a>
  </div>
</section>

<section class="home-diagrams">
  <div class="home-section-head">
    <p class="home-kicker">The boundary</p>
    <h2>Terminals ask. The Hub decides.</h2>
    <p>Model routing, memory truth, grants, audit, skill trust, and execution readiness all live in the Hub. Terminals and other clients are replaceable surfaces.</p>
  </div>

  <div class="home-diagrams__grid">
    <div class="home-diagram-card">
      <img src="/xhub_trust_control_plane.svg" alt="X-Hub trust and control plane diagram" />
      <div class="home-diagram-card__copy">
        <strong>Trust and control plane</strong>
        Clients ask. The Hub decides. Execution surfaces act only after governance. Runtime truth returns to the Hub.
      </div>
    </div>
    <div class="home-diagram-card">
      <img src="/xhub_deployment_runtime_topology.svg" alt="X-Hub governed capability map diagram" />
      <div class="home-diagram-card__copy">
        <strong>Governed capability map</strong>
        Models, memory, skills, quotas, terminals, channels, Supervisor state, runtime evidence — converging through one management surface.
      </div>
    </div>
  </div>
</section>

<section class="home-usecases">
  <div class="home-section-head">
    <p class="home-kicker">Why now</p>
    <h2>The last 18 months changed the shape of the problem.</h2>
  </div>

  <div class="home-usecase-grid">
    <div class="home-usecase-card">
      <span>AI does more than chat</span>
      <strong>It deletes files, edits code, sends emails, charges cards.</strong>
      <p>The "Are you sure?" prompt inside a chat window was built before AI could act. By 2026 your AI runs longer, touches more, and can do irreversible damage from one prompt injection or one bad token of context.</p>
    </div>
    <div class="home-usecase-card">
      <span>You probably use 3+ AI tools</span>
      <strong>Each has its own memory, its own keys, its own audit log, and they don't talk to each other.</strong>
      <p>Cursor knows your code, Claude knows your conversations, ChatGPT knows your work. Switching costs you context. Auditing means reading three histories. One place that sees the whole picture would help.</p>
    </div>
    <div class="home-usecase-card">
      <span>AI is no longer single-user</span>
      <strong>Families share it, teams share it, and every AI product is still built like one person uses it.</strong>
      <p>No admin / operator / observer concept. No way for a parent to set limits without taking the device. No way for a CTO to audit without watching every chat. X-Hub adds the multi-user shape AI tools haven't.</p>
    </div>
  </div>
  <p style="margin-top: 32px; text-align: center;">
    <a href="/why-now">Read the long version: timeline, regulations, and why the window closes around 2028 &rarr;</a>
  </p>
</section>

<section class="home-problems">
  <div class="home-section-head">
    <p class="home-kicker">Open source, open core</p>
    <h2>The Hub is free. Forever. Multi-user and compliance are paid.</h2>
    <p>The design that makes X-Hub work — Hub-first trust, fail-closed, grants, audit, memory truth, skill trust — stays MIT. The pieces only enterprise buyers need are the commercial lane.</p>
  </div>

  <div class="home-problem-table">
    <div class="home-problem-row home-problem-row--head">
      <div>MIT (free)</div>
      <div>Commercial</div>
    </div>
    <div class="home-problem-row">
      <div>The Hub itself. Single user. Audit log on disk. Skill trust. Local + paid model routing. X-Terminal client.</div>
      <div>Multi-user roles (admin / operator / observer). SSO / OIDC. SIEM-friendly audit export.</div>
    </div>
    <div class="home-problem-row">
      <div>Family use: one parent admin, kids as governed clients. No separate license, no separate product.</div>
      <div>EU AI Act / ISO 42001 / SOC 2 alignment evidence. Support SLA. Compliance report generators.</div>
    </div>
    <div class="home-problem-row">
      <div>Open-source contributions welcome. All extracted specs under CC BY 4.0.</div>
      <div>Private deployment + integration services. Pilot: <a href="mailto:contact@xhubsystem.com">contact@xhubsystem.com</a>.</div>
    </div>
  </div>
</section>

<section class="home-hero-band">
  <div class="home-hero-band__copy">
    <p class="home-kicker">Built in the open</p>
    <h2>Two pieces of X-Hub are also independent protocol specs you can use without us.</h2>
    <p>
      If you want the skill-trust layer without taking X-Hub, you can. If you want the per-action confirmation primitive for your own agent runtime, you can. X-Hub is one implementation of these specs — not the only one.
    </p>
  </div>
  <div class="home-flow">
    <div class="home-flow__row">
      <span>mcp-trust-registry</span>
      <strong>A trust layer above MCP — signed manifests, capability tokens, runtime enforcement. Stops "patch updates" from silently adding <code>shell:exec</code>.
        <a href="https://github.com/AndrewXie-Rich/mcp-trust-registry">github.com/AndrewXie-Rich/mcp-trust-registry</a></strong>
    </div>
    <div class="home-flow__row">
      <span>agent-2fa</span>
      <strong>Per-action 2FA for AI agent actions — Touch ID on a paired device before a destructive command lands. The "ask before deleting" your IDE agent doesn't have.
        <a href="https://github.com/AndrewXie-Rich/agent-2fa">github.com/AndrewXie-Rich/agent-2fa</a></strong>
    </div>
    <div class="home-flow__row">
      <span>hub-receipt</span>
      <strong>Signed receipts that work outside X-Hub. Every authorized action produces a verifiable record — embeddable in commits, IDE metadata, or chat messages.
        <a href="https://github.com/AndrewXie-Rich/x-hub-system/blob/main/specs/hub-receipt/v0.1.md">hub-receipt/v0.1.md</a></strong>
    </div>
  </div>
</section>

<section class="home-readpath">
  <div class="home-section-head">
    <p class="home-kicker">Reading path</p>
    <h2>Five pages to evaluate the system end to end.</h2>
  </div>
  <div class="home-readpath__grid">
    <a href="/security">Trust model</a>
    <a href="/architecture">Architecture</a>
    <a href="/memory">Memory control plane</a>
    <a href="/skills">Governed skills</a>
    <a href="/status-roadmap">Status &amp; roadmap</a>
  </div>
</section>
