# WO-05 — Draft agent-2fa protocol-v0.1.md

**Owner:** AI · **Effort:** ~1 day · **Task ID:** #5 · **Dependencies:** WO-03 (Hub Receipt) must exist for reference

## Why this matters

agent-2fa is the second of the two spinoffs designed to solve X-Hub's "1 star recognition problem". Its product framing — **"Touch ID for AI agent actions"** — is the most viral of the project's possible standalone artifacts. No AI agent today (Cursor, Claude Code, Cline, Devin) has anything resembling a 2FA layer for destructive operations. The pitch is a single sentence: "AI tries to `rm -rf`; phone push; Touch ID; allowed/denied with signed receipt."

This WO produces the canonical v0.1 protocol spec, ~400–500 lines, structured identically to `mcp-trust-registry/protocol-v0.1.md` so reviewers familiar with one can read the other.

## Scope

**In scope:**
- One spec document defining: Challenge, Authorization, Policy, Modality, Pairing, Transport, Receipt-via-Hub-Receipt, Threat Model, Open Questions.
- The protocol must be MCP-orthogonal: it's invoked by AI agent runtimes (Claude Code, Cursor, etc.) but does not require MCP.
- Reference to Hub Receipt (WO-03) for the signed-receipt primitive — DO NOT re-define receipt format.

**Out of scope:**
- iOS app implementation. (Future WO.)
- Macro language for policy expression beyond the v0.1 DSL described below.
- Multi-tenant / enterprise SSO bindings — keep v0.1 single-user-multi-device.

## Deliverables

Create `specs/agent-2fa/protocol-v0.1.md` (~400–500 lines).

### Required spec sections (mirror mcp-trust-registry/protocol-v0.1.md ordering)

1. **Abstract** (2 paragraphs).
2. **Status of this document** — Draft, pre-RFC, intended for cross-agent community review (Cursor / Claude Code / Anthropic / IDE ecosystem).
3. **Terminology:** Agent, Action, Risk Level, Challenge, Authorization, Authorizer, Modality, Pairing, Verifier, Time-Box, Bypass.
4. **Architecture (§3)** — ASCII diagram: Agent → action gate → Challenge → Authorizer device(s) → Authorization → Receipt (Hub Receipt envelope).
5. **Risk levels (§4)** — three tiers:
   - `notify` — log only, no blocking
   - `confirm` — one Authorizer must approve
   - `dual_confirm` — two distinct Authorizers must approve (different devices, different identities)
   Each tier has a normative description and example use cases.
6. **Action classification policy (§5)** — DSL for matching actions to risk levels. Format: YAML/JSON with `match` (regex over command or structured fields) + `risk` (one of three levels). Provide reference templates: `personal`, `team`, `strict`. Show examples for matching `rm -rf`, `git push --force`, `kubectl delete`, SQL DELETE/DROP, etc.
7. **Challenge format (§6)** — JSON schema for the request sent from Agent to Authorizer device:
   - `schema` (const `agent-2fa/challenge/v0.1`)
   - `challenge_id`
   - `action` (object: command text or structured representation, sensitive field redaction)
   - `risk_level` (one of three)
   - `agent_id`, `agent_pubkey`
   - `requested_at`, `expires_at`
   - `signature` (Agent signs)
8. **Authorization format (§7)** — JSON schema for the response from Authorizer to Agent:
   - `schema` (const `agent-2fa/authorization/v0.1`)
   - `challenge_id` (echoes)
   - `decision` (enum: allow / deny / escalate)
   - `authorizer_id`, `authorizer_pubkey`
   - `modality_used` (touch_id / face_id / voice / yubikey / passphrase)
   - `decided_at`
   - `signature` (Authorizer signs)
9. **Modality definitions (§8)** — required modalities for v0.1: `touch_id`, `face_id`, `voice_phrase`, `passphrase`. Optional: `yubikey`, `apple_watch`. Each: what device produces the proof, what is signed, what is the proof-of-presence guarantee.
10. **Pairing (§9)** — QR code-based, LAN-preferred, BLE fallback. ed25519 long-term key per device. Pairing flow: device A shows QR with its pubkey + nonce; device B scans, signs, returns; mutual key store.
11. **Transport (§10)** — three modes:
    - LAN (mDNS discovery, TLS pinned to paired pubkeys)
    - APNs/FCM push (for off-LAN devices) — challenge body delivered via push, response over LAN/BLE if reachable, else encrypted push response
    - BLE (last resort, paired-only)
   Required: LAN. Optional: APNs/FCM, BLE.
12. **Time-Box and Bypass (§11)** — fail-closed by default. Policy MAY allow `bypass_until: <timestamp>` to skip 2FA for a bounded window (e.g., during a deploy window). Bypasses MUST be signed by an Authorizer and logged in the Receipt.
13. **Session Receipt via Hub Receipt (§12)** — defer to `hub-receipt/v0.1.md`. Show how agent-2fa populates the envelope: `subject: {domain: "agent-2fa", action_id: <challenge_id>}`, claims include `risk_level`, `decision`, `authorizers` (list), `modalities_used`, `bypass_active` (bool).
14. **Security considerations (§13)** — threat model. In scope: phishing-style challenges (action description must be human-verifiable; agent attempts to mislead user); compromised agent; lost Authorizer device. Out of scope: compromised Authorizer device itself.
15. **Relationship to MCP, OS-level prompts, and other 2FA standards (§14)** — explicitly: this is NOT WebAuthn (different threat model, different ergonomics). It MAY layer on top of WebAuthn at the device level. It is orthogonal to MCP — MCP servers can invoke this protocol via a standard tool call interface, but the protocol itself doesn't depend on MCP.
16. **Conformance (§15)**.
17. **Open Questions (§16)** — propose at least 4: (a) action representation when actions are structured (e.g., tool calls) vs textual; (b) latency budget for `confirm` flow (target <5 sec); (c) offline operation policy; (d) integration points for VS Code / Cursor / Claude Code.
18. **JSON Schemas (§17)** — list URLs; actual schemas come from WO-06.
19. **Appendix A: Reference CLI** — sketch CLI similar to mcp-trust-registry's: `agent2fa pair`, `agent2fa run -- <command>`, `agent2fa policy`, `agent2fa list`, `agent2fa receipts`.
20. **Appendix B: Minimal verifier flow** — pseudocode.
21. **Change Log**.
22. **Acknowledgements**.

### Style

- Match the prose density of `mcp-trust-registry/protocol-v0.1.md`. Same RFC 2119 keyword usage.
- Use the same ASCII diagram style.
- Section numbering identical to mcp-trust-registry (skip numbers if needed to align — e.g., if mcp-trust §13 is "Relationship to MCP", agent-2fa §14 should be the analogous section).

## Acceptance criteria

1. File exists at `specs/agent-2fa/protocol-v0.1.md`.
2. Length: 400–550 lines.
3. References `specs/hub-receipt/v0.1.md` (WO-03) for receipt format, does NOT re-define it.
4. Section structure mirrors `mcp-trust-registry/protocol-v0.1.md` so a reader of one can navigate the other.
5. The four open questions are real, not boilerplate — each tied to a specific design choice with a concrete trade-off.
6. No re-definition of Hub Receipt; the agent-2fa receipt section is purely an "extension instance" of the envelope.

## References (read first)

- `specs/mcp-trust-registry/protocol-v0.1.md` — the structural template
- `specs/hub-receipt/v0.1.md` (from WO-03) — the receipt envelope
- `specs/mcp-trust-registry/README.md` and `demo-60s.md` — for the cross-product narrative voice (Touch ID demo is mentioned in mcp-trust README implicitly; you don't need to harmonize, but stay consistent on signing/key encoding)
- The "agent-2FA spec sketch" content in the parent conversation that led to this WO (see git history of this directory if needed)

## Anti-patterns

- Don't conflate this with WebAuthn. WebAuthn is per-website 2FA for human users; agent-2fa is per-action confirmation for AI actions. Different threat model, different UX.
- Don't make the policy DSL Turing-complete. Match + risk level. If you want more expressivity, defer to v0.2.
- Don't require cloud / SaaS push services. APNs is acceptable as an *optional* transport; the spec MUST allow fully-LAN deployment.
- Don't add "enterprise SSO" or "role-based authorizer chains" in v0.1. These are useful but defer them to v0.2.
- Don't speculate about integration with specific IDE products (Cursor v3.2, Claude Code, etc.). State the integration shape in abstract; let implementers handle the specifics.

## Handoff notes

After this spec lands, WO-06 produces the README, 60s demo script, and JSON schemas — those depend on this spec for canonical field definitions. If any choice in this WO is unresolved, leave a `TBD` block clearly marked and surface it; don't decide silently.

This is the longest of the AI work orders. Budget accordingly. If stopping mid-WO, leave the file at a section boundary (don't end mid-paragraph) and update the task with which sections are done.
