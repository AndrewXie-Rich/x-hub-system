# Use Cases

<p class="lead">
If AI is just chatting, you don't need X-Hub. If AI is starting to delete files, send messages, charge cards, or work across multiple projects while you sleep — that's when control matters. Three audiences end up here for three different reasons.
</p>

<div class="preview-note">
  <strong>Three audiences, not six.</strong>
  This page expands the three audiences from the homepage. Personal builders are a sub-mode of developers, not a separate audience — same Hub, single user, no role split.
</div>

## The short version

If AI is only chatting, a simple client may be enough.
When AI starts using accounts, memory, skills, files, browsers, remote channels, paid models, or external actions, the important decisions should move back to the Hub.

## Teams and enterprises

<div class="story-grid">
  <div class="story-card">
    <span>Why this audience</span>
    <strong>Code, prompts, and memory can't go through SaaS-only AI tools.</strong>
    <p>Industries with EU AI Act exposure, ISO 42001 procurement requirements, or SOC2-conscious buyers cannot ship sensitive context through a vendor cloud they don't control. The commercial license adds multi-user roles (admin / operator / observer), SSO / OIDC, SIEM-friendly audit export, and compliance report generators on top of the MIT kernel.</p>
  </div>
  <div class="story-card story-card--risk">
    <span>Concrete evidence</span>
    <strong>A "PDF parser" skill should not quietly open a remote shell.</strong>
    <p>Before a team uses a skill, the Hub checks its manifest, source, pinned version, compatibility, and declared capability. Even when allowed, the skill acts only inside granted scope and leaves grant and audit records. This is the implementation reference behind the <a href="https://github.com/AndrewXie-Rich/mcp-trust-registry">mcp-trust-registry</a> spec.</p>
  </div>
  <div class="story-card story-card--risk">
    <span>Concrete evidence</span>
    <strong>"Done" needs evidence, budget, and review.</strong>
    <p>In multi-project Supervisor work, heartbeat checks meaningful progress, quota views expose pressure, and pre-done review checks evidence. The system does not mark work done only because the model says it is done. Signed Hub Receipts mean the audit trail is verifiable outside X-Hub.</p>
  </div>
</div>

See [ENTERPRISE.md](https://github.com/AndrewXie-Rich/x-hub-system/blob/main/ENTERPRISE.md) for procurement-facing details and the commercial license inquiry path.

## Families

<div class="story-grid">
  <div class="story-card">
    <span>Why this audience</span>
    <strong>Shared AI with parent-controlled limits, per-action confirmation, and a Hub the kids' clients cannot bypass.</strong>
    <p>The pivot here is structural, not feature-based: family use is the smallest multi-user team. Parent = Hub admin. Children = governed clients. No separate product line, no separate license — the same MIT kernel that powers teams powers families.</p>
  </div>
  <div class="story-card story-card--risk">
    <span>Concrete evidence</span>
    <strong>A link should not become a high-trust device.</strong>
    <p>First high-trust pairing stays on the same Wi-Fi with local confirmation. Remote channels can exist, but they build on bound devices, token state, and revocable access. A child clicking a chat link should never produce a new admin device.</p>
  </div>
  <div class="story-card story-card--risk">
    <span>Concrete evidence</span>
    <strong>High-risk actions need a paired-device tap.</strong>
    <p>Payment confirmations, account changes, destructive commands route through paired-device confirmation. This is the primitive the <a href="https://github.com/AndrewXie-Rich/agent-2fa">agent-2fa</a> spec formalizes — Touch ID / Face ID on the parent's phone before the action lands.</p>
  </div>
</div>

See [FAMILY.md](https://github.com/AndrewXie-Rich/x-hub-system/blob/main/FAMILY.md) for the family deployment shape.

## Developers (including individual / solo use)

<div class="story-grid">
  <div class="story-card">
    <span>Why this audience</span>
    <strong>Self-host the Hub, see and audit what actually ran.</strong>
    <p>Route truth, fallback, downgrade, blocked reason, and signed receipts are all surfaced. One Hub manages local models for sensitive work, paid providers when needed, project state across sessions, and long-term memory under Writer + Gate. Solo / personal use is just "one-user team" — no separate audience needed.</p>
  </div>
  <div class="story-card story-card--risk">
    <span>Concrete evidence</span>
    <strong>"Look up a public fact" should not read the whole machine.</strong>
    <p>When a developer asks AI to research public information, X-Hub scopes the task to browsing and relevant project files. SSH keys, API keys, browser cache, private chat, and durable memory do not enter context just because it's convenient.</p>
  </div>
  <div class="story-card story-card--risk">
    <span>Concrete evidence</span>
    <strong>The two specs are independently usable.</strong>
    <p>You can take just <a href="https://github.com/AndrewXie-Rich/mcp-trust-registry">mcp-trust-registry</a> as a trust layer above MCP, or just <a href="https://github.com/AndrewXie-Rich/agent-2fa">agent-2fa</a> as per-action confirmation, without taking X-Hub. X-Hub is one implementation of these specs, not the only one.</p>
  </div>
</div>

## The strongest point isn't "it can automate"

Most agent demos focus on what the agent can do. X-Hub-System asks the harder questions:

- If it's wrong, who can stop it?
- If it uses paid models, who can see quota pressure?
- If it reads long-term memory, who decides how much it gets?
- If it installs a skill or calls a connector, who checks source and scope?
- If it sends email, merges code, runs commands, or initiates payment, who signs the intent?
- If it claims the task is done, where is the evidence?

X-Hub puts those questions into product structure instead of forcing the operator to watch every step in a chat window.

## Not just another chat window

X-Hub-System is closer to an AI execution control plane. Chat, terminal, voice, remote channels, and local runtime can all become entry points — while models, memory, skills, quota, grants, audit, and shutdown authority stay governed by the Hub.

Continue with:
[X-Constitution](/constitution), [Governed Memory](/memory), [X-Terminal](/x-terminal), [Trust Model](/security).
