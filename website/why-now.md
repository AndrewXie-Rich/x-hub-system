# Why this matters now

<p class="lead">
The short answer: AI started actually doing things in 2024. Regulation caught up in 2025–2026. By 2028, the foundation labs will fold basic governance into their own products and the open self-hosted alternative gets harder to launch. The two-year window in the middle is when X-Hub exists.
</p>

<div class="preview-note">
  <strong>Long version of the homepage "Why now" section.</strong>
  Skip if you already know why per-action confirmation, tool fragmentation, and the missing multi-user shape are problems by mid-2026.
</div>

## The timeline

<img class="diagram-frame" src="/why_now_timeline.svg" alt="Timeline 2022–2028: ChatGPT launches 2022, MCP draft and agentic frameworks 2024, EU AI Act enters force 2025, ISO 42001 in procurement 2026, predicted first major MCP supply-chain incident 2027, foundation labs absorb governance 2028. X-Hub window 2026–2028." />

Three forces converged. Each one alone produces friction; combined, they produce a structural gap that doesn't fix itself.

## AI now acts, not just answers

Nov 2022: ChatGPT launched. AI was a great conversationalist, but you had to copy-paste its output yourself. The blast radius of "AI saying the wrong thing" was the next message you'd send.

2024: tools, browsers, file systems, terminals. Cursor edits your code. Cline runs commands. Devin spins up VMs. Manus posts to social media. Claude calls APIs via MCP. The blast radius is now "anything connected to anything the AI can touch."

By mid-2026: every major AI tool can act on tools and resources. Agents run unattended for hours. The default assumption is that AI will probably get it right. When it doesn't, the action has already happened.

**Concrete failures we've seen by 2026** (composite of real incidents and obvious risks):

- Coding agents that ran `rm -rf` on the wrong directory because the AI confused paths
- AI ops bots that emailed customers about a "maintenance window" that wasn't real because of a prompt injection in a doc the AI read
- Agentic browser tools that signed up for SaaS subscriptions on saved cards while "researching pricing options"
- AI assistants that pushed force-pushes on the wrong branch, overwriting weeks of work
- Code agents that quietly modified `.env` files, exposing secrets that then got committed

None of these are exotic. They're the new failure mode. "Are you sure?" inside the chat window is the wrong place to confirm because:
- The chat window was built before AI could act
- The same compromised context that initiated the action sees the confirmation
- Reading the confirmation requires reading the AI's output as text, which is exactly what users stop doing once they trust the tool

Per-transaction confirmation, on a separate paired device, with cryptographic proof-of-presence — banks solved this for fund transfers in the early 2000s. AI hasn't.

## AI is no longer one tool

Count your AI tools. Most teams in 2026 have at least:
- An IDE coding agent (Cursor, Cline, Claude Code, Aider, Continue)
- A browser chat (Claude web, ChatGPT, Gemini)
- A terminal agent (Claude Code, Aider, Codex CLI)
- An autonomy-shaped agent (Devin, Manus, Replit Agent) — at least under evaluation
- Slack / Teams AI integrations
- Custom MCP servers for internal tools
- Sometimes a Slack-native or Discord-native bot the team built

Each of those has:
- Its own memory (you can't see what Cursor remembers vs Claude)
- Its own API keys (vendor by vendor, often per-person, often charged to whoever signed up)
- Its own audit trail (text logs at best)
- Its own MCP / plugin trust model (or none)
- Its own pricing (per-seat / per-token / per-call, no consolidation)

The friction is no longer "is AI capable enough." Capability is a solved problem. The friction is **operations across AI tools**:
- Switching providers means rebuilding memory
- Auditing means reading multiple chat histories
- Cost attribution is a spreadsheet of receipts
- Permission boundaries don't exist consistently

The control plane is missing. Or rather, the control plane *exists* — but it lives inside each vendor, separately, with no way to interoperate.

X-Hub is the bet that the control plane should be **outside the vendor**, owned by the user or the org, with the vendors becoming replaceable surfaces. Every cross-vendor question becomes a single query against the Hub.

## Regulation arrived

The EU AI Act was passed in 2024 and entered force in stages. By mid-2026 the high-risk-system obligations apply. ISO 42001 is starting to appear in enterprise procurement RFPs as a stated requirement. China's GenAI filing requirements have been live since 2024. The US has Executive Order frameworks plus state-level laws (Colorado, California). India has the DPDP Act.

The pattern across all of these is consistent:
- You must be able to identify what AI did what action
- You must have evidence the action was authorized
- You must have a control plane that can revoke / kill / contain
- You must produce audit logs an outside party can read

If your AI stack is "Cursor + Claude + ChatGPT + a few MCP servers, each with their own chat history," answering any of those questions is hard. If your AI stack is "all of the above, routed through a Hub that logs structured events," the answers are queries.

Self-hosted, signed-audit-by-default control planes go from "nice to have" to "required for procurement" right around 2026 Q3 in our read. That's not because anyone loves bureaucracy — it's because the alternative is too risky to deploy at scale.

## Why this window probably closes around 2028

Trust-root architecture is design DNA + first-mover advantage. It is not technically impossible to replicate. Anthropic added org policies in 2025-Q3. OpenAI shipped the Enterprise Compliance API. Cursor added team admin features. The foundation labs and the major IDE-agent vendors will continue eating the *basic* governance floor over the next 24 months.

By ~2028, our read is that:
- Vendor-managed governance becomes table-stakes inside the big AI products
- The "open, self-hosted, user-owns-the-Hub" proposition keeps working — but mainly in high-compliance niches (finance, medical, legal, government)
- General-purpose dev tools default to vendor governance, and the friction of self-hosting becomes harder to justify outside compliance contexts

That means **2026–2028 is the window where this proposition is most legible to the broadest audience.** After that, it still works — for the right buyers — but the audience narrows.

This isn't a doom prediction. It's a sober read of how product categories settle. Sigstore took years to displace ad-hoc supply-chain trust. Per-transaction 2FA in banking took ~5 years from "novel" to "expected." AI governance is probably similar. The interesting work happens before the standard congeals.

## The scope, honestly

X-Hub is a control plane product. It controls *what happens around AI*, not *what AI thinks*. So it handles destructive actions the AI takes when you didn't authorize them, the audit-gap and per-vendor-lockin mess across multiple AI tools, the trust gap on MCP servers and plugins, and the multi-user concept that AI products keep forgetting.

What it doesn't address: factual accuracy of model outputs, model bias or hallucination, the cost of running the underlying models, formal compliance certification (those are audits, not infrastructure), content moderation for what kids can ask AI, or whether AI should be allowed in your particular setting in the first place.

If your problem is "I want to know my AI is honest," that's a different category. If your problem is "I want to know what my AI did, and stop the wrong stuff before it lands," that's X-Hub.

## Two spinoff specs, because the control plane shouldn't be owned by us either

The trust layer above MCP, and the per-action confirmation primitive, are valuable independent of whether anyone uses X-Hub. So we extracted them as standalone specs:

- [mcp-trust-registry](https://github.com/AndrewXie-Rich/mcp-trust-registry) — federated attestation, capability tokens, signed manifests above MCP
- [agent-2fa](https://github.com/AndrewXie-Rich/agent-2fa) — per-action 2FA for AI agents
- [hub-receipt](https://github.com/AndrewXie-Rich/x-hub-system/blob/main/specs/hub-receipt/v0.1.md) — signed receipt envelope used by both

X-Hub is one reference implementation. Other implementations are welcome — including from vendors. If Anthropic, OpenAI, Cursor, Cline build their own implementations of these specs and they interoperate, that's a win. The point isn't us. The point is the layer.

## Where to start

- If you're a parent or running a family: [For families](/family)
- If you're at a team / org: [For teams and organizations](/team)
- If you're a developer evaluating it for yourself: [Get Started](/get-started)
- If you want the technical depth: [Architecture](/architecture), [Trust Model](/security), [Status & Roadmap](/status-roadmap)

Continue with:
[For families](/family), [For teams](/team), [Architecture](/architecture).
