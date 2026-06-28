# For teams and organizations

<p class="lead">
You started letting your team use AI six months ago. Now Engineering's on Cursor, Marketing's on ChatGPT, Ops is on Claude, and three people quietly installed MCP servers nobody reviewed. Compliance wants a single source of truth. You don't have one. X-Hub is the answer that doesn't require ripping out the tools your team likes.
</p>

<div class="preview-note">
  <strong>Same Hub. Single deployment. Free for evaluation.</strong> The MIT-licensed Hub is the entire system. The commercial license adds multi-user roles, SSO/OIDC, SIEM audit export, and compliance report generators — pay-as-you-grow, not seat-pricing.
</div>

## Five problems showing up in real organizations in 2026

<div class="story-grid">
  <div class="story-card story-card--risk">
    <span>Vendor cloud lock-out</span>
    <strong>Your code, prompts, or customer data can't go through a SaaS-only AI vendor.</strong>
    <p>Legal, financial services, healthcare, government work, anything with EU exposure post-AI-Act. You need self-hosted AI without losing access to Claude / GPT capability.</p>
  </div>
  <div class="story-card story-card--risk">
    <span>Tool fragmentation</span>
    <strong>You have 4–6 AI tools across the team and they share nothing.</strong>
    <p>Project context lives inside Cursor. Conversations live inside Claude. Audit logs live inside ChatGPT. When someone leaves, all of their AI work walks out with their account.</p>
  </div>
  <div class="story-card story-card--risk">
    <span>The audit question</span>
    <strong>"Who deployed the AI-generated migration that took down prod last month?"</strong>
    <p>The honest answer is "we'd have to ask Slack, git blame, the Cursor chat history, and that engineer who already left." With X-Hub, it's one query against the audit log.</p>
  </div>
  <div class="story-card story-card--risk">
    <span>Unvetted MCP servers</span>
    <strong>A junior dev installed a sketchy MCP server "to save time."</strong>
    <p>It runs in your agent's tool-calling loop with access to source code, secrets, and credentials. The patch update next week silently adds <code>shell:exec</code> — and nobody notices until exfiltration.</p>
  </div>
  <div class="story-card story-card--risk">
    <span>AI spend opacity</span>
    <strong>What does the team actually spend on AI?</strong>
    <p>Per-seat Cursor billing, per-team Claude billing, per-user ChatGPT billing, OpenAI API key billing, Anthropic API key billing — five invoices, no consolidated view, no way to attribute by project.</p>
  </div>
</div>

## How X-Hub answers all five

<img class="diagram-frame" src="/team_deployment.svg" alt="Team deployment: clients (Cursor, Claude Code, ChatGPT, Slack, MCP servers) route through one self-hosted X-Hub with admin/operator/observer roles, then to local + paid models, with SIEM audit, Hub Receipts, and compliance reports as outputs." />

The shape is simple: **one self-hosted Hub between your team and every AI tool.** Each team member keeps using the tools they like — Cursor in the IDE, Claude Code in the terminal, Slack for operator channels, ChatGPT in the browser. All of those route their actions, memory, and model calls through the Hub. The Hub enforces policy, logs everything, and produces signed receipts.

### Roles

| Role | What they can do | What they can't |
|---|---|---|
| `admin` | Set policy, manage users, revoke devices, see all audit | Bypass their own audit; admins are still audited |
| `operator` | Use AI tools, grant scoped capabilities to clients, see their own audit | Change policy, revoke other users' devices |
| `observer` | Read audit, read aggregated metrics | Execute, change policy, write any state |

A CTO might be admin. The Engineering team is operator. Compliance/Audit is observer. SOC analysts are observer. Roles are enforced in the Rust kernel (Phase 2 of the multi-user schema landed 2026-06-25 — see [status](/status-roadmap)).

### One audit log, one query

When the auditor asks "what did Engineering do last quarter," the answer is one SIEM query. The audit JSONL looks like this (sample event):

```json
{
  "ts": "2026-09-14T15:42:18Z",
  "actor_id": "alice@acme.com",
  "actor_role": "operator",
  "event_type": "skill_execute",
  "skill": "github-mcp-server",
  "skill_version": "1.4.2",
  "skill_manifest_hash": "sha256:9f3c...ab2e",
  "action": "fs:read",
  "scope": "/repos/payments-api/",
  "decision": "allow",
  "grant_id": "g_3a7f12bc",
  "receipt_id": "rcpt_a2fa-7c1e",
  "model_id": "claude-opus-4-7",
  "tokens_in": 8421,
  "tokens_out": 1632
}
```

That's not a vendor's chat transcript export. That's a structured audit event you can ship to Splunk / Datadog / Elastic and query like any other security log.

### MCP server trust, before they run

Every MCP server gets checked against the [mcp-trust-registry](https://github.com/AndrewXie-Rich/mcp-trust-registry) spec before it loads: signed publisher manifest, content-addressed artifact, declared capability tokens, version pin. A patch update that quietly adds `shell:exec` triggers a re-grant prompt — it can't silently expand privilege.

### Cost and quota visibility

Every model call carries the model that was *configured* and the model that *actually ran*. Fallbacks are visible. Quota pressure is visible. Per-project attribution is built in. You get one dashboard showing total AI spend by team, by project, by user — across local models, Claude, GPT, Gemini, whatever you route through the Hub.

## Compliance posture (in pragmatic terms)

The compliance story is usually the longest section in a B2B brochure. Here's the short, honest version:

| Framework | What X-Hub gives you | What's still on you |
|---|---|---|
| EU AI Act (active mid-2025, fully applicable Aug 2026) | Self-hosted control plane. Signed audit trail by default. Hub Receipts as verifiable evidence. Capability of identifying actor / model / scope per action. | Your own risk classification of the use cases. Your own conformity assessment. Your own DPIA. |
| ISO 42001 (in procurement 2026) | The structural ingredients an auditor maps to most of Annex A: governance roles, data sovereignty, audit trails, control monitoring, incident response paths. | The management-system policies, the documented processes, the review cadence. |
| SOC 2 (US enterprise procurement) | Audit log integrity, access controls, change-management evidence. Multi-user role enforcement. SIEM export for the security operations team. | Type II audit costs ~9–12 months + auditor fees. X-Hub gives you the technical controls; you do the management ones. |
| GDPR / data residency | Self-hosted deployment. Memory and audit stay on infrastructure you choose. | Your DPO. Your record-of-processing-activities. Your consent workflows. |

We are not a compliance product. We are the *infrastructure* a compliance program plugs into. Don't buy us if you need someone to sign your SOC 2 attestation; do buy us if your auditor keeps asking for evidence and your AI tools can't produce it.

## The pilot path — 30 / 60 / 90 days

**Day 0–30 — Single team, single AI tool.**
- Stand up X-Hub on one Mac or in `docker-compose` (Linux daemon target — see [status](/status-roadmap)).
- Pair 3–5 engineers. They keep using Cursor, plus their existing AI workflow.
- All AI calls now log through the Hub. Compare the Hub's audit log against what your team thought was happening.

**Day 30–60 — Expand tools, add policy.**
- Onboard Claude Code, ChatGPT, Slack bot, any MCP servers.
- Define your policy: what's notify, what's confirm, what's dual_confirm. Three starter templates ship: `team`, `strict`, `personal`.
- Add observer accounts for compliance / security team.

**Day 60–90 — SIEM, SSO, compliance handoff.**
- Wire SIEM export to Splunk / Datadog / Elastic.
- (When OIDC ships — Q4 2026 P1 target) connect to your IdP.
- Generate first compliance report. Hand it to your auditor. See if they recognize the controls.

If by day 90 the answer is "this didn't change anything," you've spent zero on commercial licensing — the kernel is MIT, free forever. If it did change something, the commercial license is the natural next step.

## Pricing

**MIT (free).** The Hub itself. Single user OR multi-user with manual role config. Audit log on disk. Skill trust. Local + paid model routing. X-Terminal client. Family use. Open-source contributions.

**Commercial.** Per organization, not per seat:
- Multi-user role enforcement + admin UI
- SSO / OIDC against your existing IdP
- SIEM-friendly audit export (JSONL with structured event schema)
- Compliance report generators (EU AI Act / ISO 42001 / SOC 2 alignment evidence)
- Support SLA
- Private deployment + integration services

We don't publish a per-seat price because per-seat AI pricing is the disease this product is treating. Talk to us: <contact@xhubsystem.com>.

## What X-Hub is NOT

| In scope | Not in scope |
|---|---|
| Govern actions AI takes through tools, models, channels | Pre-filter what people can ask AI to do |
| Enforce per-action confirmation on destructive operations | Run your AI for you — bring your own Claude/GPT/local |
| Audit the AI's effects (file changes, sends, payments) | Track what the AI generated, only what it acted on |
| Multi-user roles, SSO, SIEM | DLP for AI outputs (use a separate DLP tool, route through Hub) |
| Signed receipts for every authorized action | Stop AI from being wrong inside a single chat window |

## Where to start

1. [Get Started](/get-started) — install path
2. [Architecture](/architecture) — how the Hub sits between clients and execution
3. [Status & Roadmap](/status-roadmap) — multi-user / SIEM / SSO / Linux daemon — what's landed and what's coming
4. [Trust Model](/security) — the security claims, written plainly

Or contact <contact@xhubsystem.com> for a pilot conversation.

Continue with:
[Use Cases](/scenarios), [Why this matters now](/why-now), [For my family](/family).
