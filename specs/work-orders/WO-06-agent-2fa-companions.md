# WO-06 — agent-2fa README + 60s demo script + JSON Schemas

**Owner:** AI · **Effort:** half day · **Task ID:** #6 · **Dependencies:** WO-05 (protocol spec) must exist

## Why this matters

agent-2fa's protocol spec (WO-05) is the canonical document, but specs alone don't drive adoption. mcp-trust-registry's pattern proved that three companion artifacts make the difference between "interesting RFC" and "shareable project":

- A ~90-line **README** that an evaluator can read in 60 seconds
- A 60-second **demo script** that becomes the social-media artifact
- **JSON Schemas** that make the spec actually implementable

This WO produces all three for agent-2fa, mirroring mcp-trust-registry's structure exactly.

## Scope

**In scope:**
- `specs/agent-2fa/README.md` (~90 lines, English)
- `specs/agent-2fa/demo-60s.md` (asciinema-style script, 4 scenes)
- `specs/agent-2fa/schemas/*.schema.json` for: challenge, authorization, policy, receipt-extension (the agent-2fa-specific claims, not the envelope)
- One example payload per schema, under `schemas/examples/`

**Out of scope:**
- The protocol spec itself (WO-05).
- Chinese versions of README. (User decides when/whether to translate.)
- Asciinema recording. The artifact is the *script*; recording is a separate motion.
- iOS app stubs, CLI stubs.

## Deliverables

### 1. `specs/agent-2fa/README.md`

Mirror `specs/mcp-trust-registry/README.md`. Section order:

1. Title + badges (preview / pre-RFC / Apache 2.0)
2. One-line value prop: **"Touch ID for AI agent actions."**
3. **What you see** — a code block showing the install + intercept + approval flow (no real screen shot; ASCII terminal output). Pull from the conversation that produced WO-05.
4. **Why this exists** — 2 paragraphs: no AI agent has 2FA today; banks do; analogous shape needed.
5. **Install (preview)** — commands. `brew install agent2fa` placeholder OK; mark preview.
6. **How it works (90 seconds)** — narrative of pair → policy → wrap agent → on high-risk command, push to authorizer → Touch ID → signed receipt. Three takeaways:
   - Policy decides what's high-risk
   - Authorizers are cryptographically paired devices
   - Receipts are signed, verifiable, and inter-op with Hub Receipt
7. **Status table** — modalities supported (Touch ID, voice phrase, etc.), transports (LAN required, APNs/BLE optional), implementations.
8. **Relationship to other protocols** — NOT WebAuthn; orthogonal to MCP; uses Hub Receipt envelope.
9. **Contributing** — pre-RFC; want feedback on policy DSL granularity, action representation for tool calls, latency target.
10. **License** — Spec CC BY 4.0, implementations Apache 2.0.

Length: 80–100 lines.

### 2. `specs/agent-2fa/demo-60s.md`

Mirror `specs/mcp-trust-registry/demo-60s.md`. Four scenes, total 55–65 seconds:

- **Scene 1 (0:00–0:15)** — `agent2fa pair` flow. Show QR code (ASCII), Touch ID on second device, paired confirmation.
- **Scene 2 (0:15–0:30)** — `agent2fa run -- claude "deploy to staging"` — agent acts; no challenge fires (action below `confirm` threshold). Shows that 2FA is *not* in the way for routine actions.
- **Scene 3 (0:30–0:45)** — `agent2fa run -- claude "drop the prod logs table"` — action matches `confirm` rule; push to phone; Touch ID approves; SQL runs; signed receipt printed. **This is the keeper scene.**
- **Scene 4 (0:45–1:00)** — Same SQL action, but policy escalated to `dual_confirm`; first authorizer approves, second authorizer **denies**; action aborted; signed denial receipt.

Plus end frame, editing checklist, alt 30-second cut for Twitter/X, "what NOT to put in the demo" section. Same pattern as `mcp-trust-registry/demo-60s.md`.

### 3. JSON Schemas

Create under `specs/agent-2fa/schemas/`:

1. `challenge.schema.json` — fields from WO-05 §6
2. `authorization.schema.json` — fields from WO-05 §7
3. `policy.schema.json` — DSL from WO-05 §5+6 (risk levels, match rules)
4. `receipt-claims.schema.json` — the agent-2fa-specific shape of `claims` inside the Hub Receipt envelope (NOT the whole envelope — that lives in WO-03 / `hub-receipt/`)

All Draft 2020-12, validate cleanly with `ajv compile --spec=draft2020 -c ajv-formats`. Style follows `mcp-trust-registry/schemas/*.schema.json` exactly:
- Strict `additionalProperties: false`
- `$id` URLs at `https://mcp-trust.org/spec/agent-2fa/v0.1/<name>.schema.json`
- ed25519 / sha256 patterns identical to mcp-trust
- Use `$defs` for shared primitives

### 4. Example payloads

`specs/agent-2fa/schemas/examples/<name>.example.json` for each of the four schemas. Cross-consistent: same `challenge_id` threads through challenge → authorization → receipt-claims. Use the SQL DELETE scenario from Scene 3 of the demo.

## Acceptance criteria

1. All 8 files exist (README, demo, 4 schemas, 4 examples).
2. README is 80–100 lines.
3. Demo script is 100–180 lines (matches mcp-trust-registry/demo-60s.md length).
4. Every schema compiles via ajv with `--spec=draft2020 -c ajv-formats` and exits 0.
5. Every example validates against its schema.
6. Receipt-claims schema does NOT redefine the envelope — it's strictly the `claims` object's shape, intended to be embedded inside Hub Receipt envelope (WO-03).
7. Cross-field consistency: example challenge_id, agent_id, authorizer_id thread through all four examples.

## References (read first)

- `specs/mcp-trust-registry/README.md` — structural template for your README
- `specs/mcp-trust-registry/demo-60s.md` — structural template for your demo
- `specs/mcp-trust-registry/schemas/*.schema.json` — pattern templates for your schemas
- `specs/agent-2fa/protocol-v0.1.md` (from WO-05) — the canonical field definitions
- `specs/hub-receipt/v0.1.md` (from WO-03) — the envelope your claims schema extends

## Anti-patterns

- Don't restate the protocol spec in the README. Link to it; the README's job is the 60-second pitch.
- Don't include real ed25519 signatures in examples. Placeholders that match the regex are fine, same convention as mcp-trust-registry examples.
- Don't add a logo. SVG / image artifacts are out of scope.
- Don't add a "comparison vs WebAuthn / vs YubiKey / vs Sudo" table. The protocol spec handles this; the README must stay terse.
- Don't write Scene 3 with melodramatic capitalization. The danger of the action speaks for itself; over-emphasis is cringy.

## Handoff notes

After this WO completes, agent-2fa has all the same companion artifacts as mcp-trust-registry. The next motion is implementation (Rust skeleton + iOS app), which is a separate set of WOs not yet authored.

If WO-05 is incomplete when you start this, **stop**: the README, demo, and schemas all depend on canonical field definitions in the protocol spec. Don't paper over a missing protocol with speculative naming.
