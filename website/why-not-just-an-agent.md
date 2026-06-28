# Why Not Just Use An Agent?

<p class="lead">
X-Hub isn't trying to win the same game as Cursor or Cline or Claude Code. Those products solve "give me a great AI IDE." X-Hub solves "give me a governable control plane that sits next to those tools."
</p>

<div class="preview-note">
  <strong>This page names names.</strong>
  By 2026, "the agent" isn't a hypothetical. It's Cursor / Cline / Claude Code / Aider / Continue / Roo for IDE work; Devin / Manus / Replit Agent for project-shaped autonomy. The right comparison isn't X-Hub against an abstract agent — it's "what does X-Hub do that those don't."
</div>

## The Short Answer

If you want an AI that's great in your editor, **use one of the existing agents**:

- [Cursor](https://cursor.com), [Cline](https://github.com/cline/cline), [Claude Code](https://www.anthropic.com/claude-code), [Aider](https://aider.chat), [Continue](https://continue.dev), [Roo](https://github.com/RooVetGit/Roo-Cline) — IDE-shaped agents
- [Devin](https://devin.ai), [Manus](https://manus.im), [Replit Agent](https://replit.com/ai) — project-shaped autonomy

These are good products. They're not control planes.

X-Hub exists for the harder problem one layer up:

- when the IDE / agent client should not be the trust root
- when one MCP server or plugin should not silently expand full-system privilege
- when higher autonomy should not erase per-action confirmation
- when memory, grants, audit, and runtime truth need to converge on one system of record across multiple AI tools
- when the control plane should stay user-owned instead of disappearing into a vendor cloud

## What An IDE Agent Doesn't Solve

| Concern | A good IDE agent (Cursor / Cline / Claude Code / etc.) | What X-Hub adds |
| --- | --- | --- |
| Trust root | The agent itself, often running in the IDE's process space | A separate Hub that decides what the agent is allowed to do |
| MCP server trust | "Install this MCP server" — accept or decline, that's it | [mcp-trust-registry](https://github.com/AndrewXie-Rich/mcp-trust-registry): signed attestations, capability tokens, runtime enforcement |
| High-risk action confirmation | "Are you sure?" inline dialog inside the IDE process — bypassable by the same compromise that started the action | [agent-2fa](https://github.com/AndrewXie-Rich/agent-2fa): paired-device Touch ID / Face ID, signed authorization on a separate device |
| Memory across tools | Each agent has its own memory; switching tools = losing context | Hub-backed memory truth with Writer + Gate; any client reads from the same governed plane |
| Audit | Best-effort transcript inside the agent's UI | Signed [Hub Receipt](https://github.com/AndrewXie-Rich/x-hub-system/blob/main/specs/hub-receipt/v0.1.md) envelopes — verifiable outside X-Hub, embeddable in commits |
| Multi-user | Per-seat licenses; per-user memory and tools | Single Hub, multi-user roles (admin / operator / observer), one audit chain |

The two products don't compete. **Use Cursor or Claude Code in your editor. Wrap them under an X-Hub if you need the control plane.**

## What X-Hub Is Actually Optimizing For

- **User-owned control plane**: permissions, keys, memory truth, audit, release timing, and runtime posture stay under the user's authority — not the vendor's
- **Governed autonomy**: higher execution range does not mean weaker supervision
- **Governed skills**: reusable capability units routed, approved, denied, audited, retried, and revoked — through a spec ([mcp-trust-registry](https://github.com/AndrewXie-Rich/mcp-trust-registry)) other implementations can also use
- **Per-action authorization**: irreversible actions hit a separate paired device before they hit the world — through a spec ([agent-2fa](https://github.com/AndrewXie-Rich/agent-2fa)) other agent runtimes can adopt
- **Fail-closed runtime truth**: missing readiness, broken pairing, or ambiguous authorization blocks instead of pretending success

## When A Standalone Agent Is Enough

You don't need X-Hub if:

- you only use one AI tool, in one IDE, on one machine
- your code, prompts, and memory can go through SaaS-only AI tools without compliance friction
- you don't share AI tooling with other people (family / team / org)
- you don't need per-action confirmation on destructive actions
- fast experimentation matters more than auditable execution

## When X-Hub Starts Making Sense

X-Hub becomes useful when one or more of these is true:

- you use multiple AI tools and want one place to govern them
- code, prompts, or memory can't go through SaaS-only tools (EU AI Act exposure, ISO 42001 procurement, SOC2-conscious buyers, internal compliance)
- you share AI tooling with family or team members and need role separation
- you need verifiable audit trails — receipts that hold up outside the agent's UI
- you need per-action confirmation on destructive operations on a *separate* device

## The Tradeoff

X-Hub isn't the shortest path to "look, the agent acted." It adds a layer.

The tradeoff is deliberate: a little more structure, a clearer trust boundary, a more credible governance story, a better foundation for higher-consequence and longer-horizon execution.

The right framing isn't capability versus capability. It's **capability under a governed boundary** versus **capability with soft trust boundaries**.
