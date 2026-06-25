# WO-03 — Draft Hub Receipt unified spec

**Owner:** AI · **Effort:** 2–3 hours · **Task ID:** #3 · **Dependencies:** none (but read mcp-trust-registry spec first)

## Why this matters

Both **mcp-trust-registry** §11.3 and the planned **agent-2fa** protocol reference "Hub Receipt" as the shared primitive: a signed JSON-LD-style execution receipt that any X-Hub-aligned tool can emit and verify. Today, neither spec defines this primitive — both say things like "interoperable with the X-Hub Hub Receipt format" without naming a canonical document.

RFC reviewers will notice. So will future implementers. Without a canonical Hub Receipt spec, every implementer ends up writing slightly different receipt formats, defeating the "one signed primitive across three projects" architecture choice.

This WO produces the canonical spec for Hub Receipt as a small, self-contained protocol artifact that the other specs reference rather than re-define.

## Scope

**In scope:**
- One spec document: format, signing, canonicalization, extensibility, verification, threat model.
- One JSON Schema for the base receipt envelope.
- Examples of how mcp-trust-registry's "session receipt" and agent-2fa's "authorization receipt" extend the envelope.

**Out of scope:**
- Implementation. No Rust, no library skeleton.
- Migration story from X-Hub's existing internal receipt formats (if any) — write the new canonical form and let the implementations migrate.
- JSON-LD context definitions (mention as a v0.2 candidate, do not author).

## Deliverables

Create `specs/hub-receipt/v0.1.md` (~80–120 lines) and `specs/hub-receipt/schema/receipt-envelope.schema.json`.

### Spec structure

Mirror the section style of `specs/mcp-trust-registry/protocol-v0.1.md`:

1. **Abstract** (1 paragraph) — what Hub Receipt is, what it is not.
2. **Status of this document** — Draft, pre-coordination with the two consumer specs.
3. **Terminology** — define: Issuer, Subject, Claim, Envelope, Signed Receipt.
4. **Envelope format** — required fields:
   - `schema` (const `hub-receipt/envelope/v0.1`)
   - `receipt_id` (pattern `^rcpt-[a-f0-9]{6,32}$`)
   - `issued_at` (date-time)
   - `issuer_key_id` (ed25519 key id)
   - `subject` (object: domain + identifier; e.g. `{"domain":"mcp-trust","name":"browser-tools"}` for mcp-trust receipts, `{"domain":"agent-2fa","action_id":"act-…"}` for 2fa receipts)
   - `claims` (object — domain-specific extension point; mcp-trust adds session_id/tool_calls/etc., agent-2fa adds risk_level/modality/authorizer)
   - `signature` (ed25519 over canonical envelope minus signature)
5. **Canonicalization** — reference the same rules as mcp-trust-registry §4.4 (sorted keys, no whitespace, UTF-8 NFC). Do not duplicate the prose; cite it.
6. **Signing** — ed25519 with the same encoding (`ed25519:` prefix, base64 padded for sig, base32 lowercase no padding for key id).
7. **Verification** — pseudocode for a verifier: parse, lookup issuer key, canonicalize sans signature, verify signature, validate `subject` and `claims` against domain rules.
8. **Extension by consumer specs** — show how mcp-trust-registry uses the envelope (claims include tool_calls, capability_denials, policy_hash; subject identifies the MCP server) and how agent-2fa would use it (claims include risk_level, modality, authorizer_id; subject identifies the gated action). One paragraph each, no schema duplication.
9. **Security considerations** — what the signed primitive does (binds a claim set to an issuer) and does not (does not certify the truth of the claims themselves — that's the consumer spec's job).
10. **Open questions** — JSON-LD `@context` for v0.2 (do we want machine-discoverable schema URIs?); transparency log (Sigstore Rekor) integration; key rotation.

### JSON Schema

`specs/hub-receipt/schema/receipt-envelope.schema.json`:
- Draft 2020-12.
- Required fields: schema, receipt_id, issued_at, issuer_key_id, subject, claims, signature.
- `subject` MUST be an object with required `domain` (string) and required `name` or `identifier` (one of). Use `oneOf`.
- `claims` MUST be a non-null object; specific keys are NOT enforced at envelope level (extension point).
- Validate cleanly with the same ajv command used for mcp-trust-registry schemas.

### One example file

`specs/hub-receipt/schema/examples/envelope.example.json` — a synthetic envelope. Make subject `{"domain":"hub-receipt-test","name":"example"}` and claims a simple `{"hello":"world"}`. Do NOT cross-reference mcp-trust or agent-2fa example data; the example here is the envelope itself, not a consumer-spec receipt.

## Acceptance criteria

1. Spec file exists, follows the mirror structure above, and is between 80 and 150 lines.
2. JSON Schema validates as Draft 2020-12 with ajv-formats.
3. Example envelope validates against the schema.
4. mcp-trust-registry's `receipt.schema.json` and the new `receipt-envelope.schema.json` are **compatible**: every field in the envelope that mcp-trust's session receipt names a similar field, the semantics agree. If you find an irreconcilable conflict, surface it as a blocker — **do not modify mcp-trust receipt.schema.json under this WO**. (A separate harmonization WO may be needed.)
5. Spec explicitly states that mcp-trust-registry's session receipt and agent-2fa's authorization receipt are extensions of this envelope (forward reference).

## References (read first)

- `specs/mcp-trust-registry/protocol-v0.1.md` §11.3 (session receipt definition)
- `specs/mcp-trust-registry/schemas/receipt.schema.json` (the consumer schema)
- `specs/mcp-trust-registry/schemas/examples/receipt.example.json` (if WO-01 done) — for compatibility check

## Anti-patterns

- Don't make Hub Receipt JSON-LD in v0.1. It's tempting but the cost is non-trivial: every consumer needs to handle `@context`, and JSON-LD processors are heavy. v0.2 can opt in.
- Don't add transparency log fields (Rekor index, etc.). v0.2 question.
- Don't try to harmonize mcp-trust receipt fields with the envelope inside this WO. That's a separate compatibility WO if the conflict turns out to be real.
- Don't pad the spec with prose. 80–120 lines is enough; longer drifts into manifesto territory.

## Handoff notes

This spec sits one layer below mcp-trust-registry and agent-2fa. Whoever takes WO-05 (agent-2fa protocol) will reference this; without it, WO-05 has to inline its own receipt format, which then conflicts with mcp-trust-registry's. So **WO-03 should land before WO-05** even though they're technically independent.
