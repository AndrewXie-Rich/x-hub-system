# agent-2fa — Protocol Specification v0.1 (Draft)

**Status:** Draft, pre-submission to cross-agent / IDE ecosystem community review
**Editor:** X-Hub-System project (reference implementation)
**Date:** 2026-06-25
**License of this document:** CC BY 4.0

---

## Abstract

AI agent runtimes today execute high-impact actions — file deletions, force-pushes, database drops, deploys, message sends — without any standard mechanism for per-action human authorization. The result is that any single prompt injection, model hallucination, or context error can trigger an unbounded blast radius. This specification defines a protocol for **per-action confirmation**: the Agent classifies an action against a local policy, builds a signed Challenge, sends it to one or more paired Authorizer devices, waits for a signed Authorization with a proof-of-presence modality (e.g. Touch ID), and emits a signed Receipt regardless of outcome.

The protocol is intentionally orthogonal to MCP, WebAuthn, and OS-level prompts: MCP servers MAY invoke it via a standard tool-call interface, WebAuthn MAY underlie device-level proof-of-presence, but the protocol itself defines its own Challenge/Authorization/Receipt envelopes. Receipts reuse the Hub Receipt v0.1 envelope rather than redefining a receipt format.

---

## 1. Status of This Document

This is a v0.1 draft. The intended community is cross-agent: AI agent runtime maintainers, IDE-ecosystem maintainers, and standards observers from WebAuthn and OS-level authentication communities. The protocol is published under CC BY 4.0; the recommended implementation license is Apache 2.0 to match the broader spinoff family.

This specification depends on [Hub Receipt v0.1](../hub-receipt/v0.1.md) for receipt envelope semantics. Implementations of agent-2fa MUST also implement the Hub Receipt envelope.

---

## 2. Terminology

The key words MUST, MUST NOT, SHOULD, SHOULD NOT, and MAY in this document are to be interpreted as described in RFC 2119.

- **Agent.** The AI runtime that wants to execute an Action. Examples: a coding agent, a deployment automation agent, a database administration agent.
- **Action.** A discrete operation the Agent intends to execute, identified either by a textual command (e.g. `rm -rf /tmp/cache`) or a structured tool call (e.g. `{"tool":"filesystem.delete","args":{"path":"/tmp/cache","recursive":true}}`).
- **Risk Level.** One of `notify`, `confirm`, `dual_confirm` (see §4).
- **Challenge.** A signed JSON envelope sent by the Agent to one or more Authorizer Devices, requesting authorization for an Action.
- **Authorization.** A signed JSON envelope returned by an Authorizer Device, conveying `allow`, `deny`, or `escalate`.
- **Authorizer.** A human principal whose presence is proven via a Modality.
- **Authorizer Device.** A device (phone, laptop, hardware key) that the Authorizer uses to produce the Authorization. Each device holds an ed25519 long-term key established at Pairing.
- **Modality.** The mechanism used to prove Authorizer presence at the moment of decision. See §8.
- **Pairing.** The one-time setup that establishes mutual trust between an Agent device and one or more Authorizer Devices. See §9.
- **Verifier.** The entity that produces and signs the Receipt at session end — typically the Agent itself, optionally a separate trusted process.
- **Time-Box.** A bounded time window during which a prior Authorization MAY substitute for a fresh one.
- **Bypass.** An explicit, signed, time-boxed permission to skip Challenge issuance for a class of Actions (e.g., during a deploy window).

---

## 3. Architecture

```
+------------------+
|     Agent        |
|  (AI runtime)    |
+--------+---------+
         |
         | action requested
         v
+------------------+      classify action      +-----------------+
|   Action Gate    | <----------------------- |  Policy (§5)    |
|   (in-process)   |                          +-----------------+
+--------+---------+
         |
         | risk != notify
         v
+------------------+
|   Challenge      |  signed by Agent (§6)
+--------+---------+
         |
         | LAN / APNs / FCM / BLE (§10)
         v
+------------------+         present action          +------------------+
| Authorizer       | -------------------------------> | Human Authorizer |
| Device(s) (1..N) | <------------------------------- |  + Modality (§8) |
+--------+---------+         decide                  +------------------+
         |
         | Authorization (§7)
         v
+------------------+
|   Verifier       |  validates + emits Receipt
|   (typically     |  via Hub Receipt v0.1 (§12)
|    the Agent)    |
+------------------+
```

The Action Gate is process-local to the Agent. Transport to an Authorizer Device is over LAN by default, with APNs/FCM and BLE as optional fallbacks (§10). Verifier and Agent MAY be the same process; high-assurance deployments MAY separate them.

---

## 4. Risk Levels

A Risk Level classifies how an Action MUST be gated.

**`notify`.** The Action is logged but not blocked. No Challenge is issued. A Receipt MAY still be emitted for audit purposes but is OPTIONAL at this tier.

**`confirm`.** Exactly one Authorization with `decision: allow` from any paired Authorizer Device MUST be obtained before the Action executes. Use for: file writes inside the working tree, package installs, outbound HTTP to known hosts.

**`dual_confirm`.** Two Authorizations with `decision: allow` MUST be obtained from two distinct Authorizer Devices belonging to two distinct authorizer identities (i.e., two different humans, or one human on two paired devices that the policy explicitly counts as distinct). Use for: irreversible operations such as `rm -rf` outside the working tree, `git push --force`, schema drops, secret rotation, prod deploys.

Implementations MUST treat unknown Risk Level values as `dual_confirm` (fail-closed).

---

## 5. Action Classification Policy

A Policy is a YAML document that maps Actions to Risk Levels via ordered match rules. The first match wins; an unmatched Action falls through to a `default` clause that MUST be specified.

```yaml
schema: agent-2fa/policy/v0.1
rules:
  - match: { command: "^rm -rf\\s+/" }
    risk: dual_confirm
  - match: { command: "^git push.*--force" }
    risk: dual_confirm
  - match: { tool: "filesystem.delete", args: { recursive: true } }
    risk: confirm
  - match: { command: "^kubectl delete\\s+namespace" }
    risk: dual_confirm
  - match: { command: "^(DROP|TRUNCATE)\\s+" }
    risk: dual_confirm
  - match: { command: "^git commit" }
    risk: notify
default: confirm
```

A `match` clause MUST contain either `command` (regex, anchored if desired by the policy author) or `tool` + optional `args` (exact-match on `tool`, substring or recursive equality on `args`). Implementations MUST NOT extend the DSL to be Turing-complete in v0.1.

Three reference templates accompany this specification:

- **`personal`** — `default: confirm`; `notify` for `git commit`, `git push` (without `--force`); `dual_confirm` for `rm -rf` outside the working tree, force-push, and shell `curl ... | sh`.
- **`team`** — same as `personal` plus `dual_confirm` for every `kubectl delete`, `terraform apply`, and SQL DDL.
- **`strict`** — `default: dual_confirm`; whitelisted `notify` for read-only operations only.

Policies MUST be loaded from a file the user owns; Agents MUST NOT accept policy from untrusted sources at runtime (a malicious policy can downgrade `dual_confirm` to `notify`).

---

## 6. Challenge Format

A Challenge is a JSON object with the following required fields:

```json
{
  "schema": "agent-2fa/challenge/v0.1",
  "challenge_id": "chg-3a7f12bc",
  "action": {
    "command": "rm -rf /var/cache/old",
    "redacted_fields": []
  },
  "risk_level": "confirm",
  "agent_id": "agent-coding-bot-1",
  "agent_pubkey": "ed25519:abcdefghijklmnopqrstuvwxyz234567abcdefghijklmnopqrst",
  "requested_at": "2026-06-25T12:00:00Z",
  "expires_at": "2026-06-25T12:00:30Z",
  "signature": "ed25519:<base64 payload>"
}
```

| Field | Type | Constraint |
|---|---|---|
| `schema` | string | MUST equal `agent-2fa/challenge/v0.1`. |
| `challenge_id` | string | MUST match `^chg-[a-f0-9]{6,32}$`. Globally unique per (Agent, requested_at) at minimum. |
| `action` | object | MUST contain either `command` (string) or `tool` (string) + optional `args` (object). MAY contain `redacted_fields` (array of strings). |
| `risk_level` | string | One of `notify`, `confirm`, `dual_confirm`. |
| `agent_id` | string | Human-readable agent identifier; MUST match `^[a-z][a-z0-9-]{0,63}$`. |
| `agent_pubkey` | string | MUST match `^ed25519:[a-z2-7]{52}$`. |
| `requested_at` | string | RFC 3339 date-time, UTC. |
| `expires_at` | string | RFC 3339 date-time, UTC, strictly later than `requested_at`. Authorizer Devices MUST reject Challenges past `expires_at`. |
| `signature` | string | ed25519 signature by `agent_pubkey` over the canonical bytes of the Challenge minus the `signature` field. |

The `action` MUST be human-meaningful: if the Agent uses a structured tool call, the Authorizer Device MUST be able to render it (e.g. as `tool(arg1=value1, ...)`). Fields named in `redacted_fields` MUST be omitted from human display; secrets MUST NOT appear in plain text.

---

## 7. Authorization Format

An Authorization is a JSON object with the following required fields:

```json
{
  "schema": "agent-2fa/authorization/v0.1",
  "challenge_id": "chg-3a7f12bc",
  "decision": "allow",
  "authorizer_id": "alice-iphone",
  "authorizer_pubkey": "ed25519:zyxwvutsrqponmlkjihgfedcba765432zyxwvutsrqponmlkjihg",
  "modality_used": "touch_id",
  "decided_at": "2026-06-25T12:00:08Z",
  "signature": "ed25519:<base64 payload>"
}
```

| Field | Type | Constraint |
|---|---|---|
| `schema` | string | MUST equal `agent-2fa/authorization/v0.1`. |
| `challenge_id` | string | MUST echo the corresponding Challenge's `challenge_id` verbatim. |
| `decision` | string | One of `allow`, `deny`, `escalate`. `escalate` requests that the Verifier upgrade the Risk Level (e.g., from `confirm` to `dual_confirm`) and re-issue the Challenge. |
| `authorizer_id` | string | Authorizer identifier; MUST match `^[a-z][a-z0-9-]{0,63}$`. |
| `authorizer_pubkey` | string | MUST match `^ed25519:[a-z2-7]{52}$`. |
| `modality_used` | string | One of the modalities defined in §8. |
| `decided_at` | string | RFC 3339 date-time, UTC. MUST be no later than the Challenge's `expires_at`. |
| `signature` | string | ed25519 signature by `authorizer_pubkey` over the canonical Authorization minus `signature`. |

A Verifier MUST reject Authorizations whose `signature` does not verify under `authorizer_pubkey`, whose `challenge_id` does not match an outstanding Challenge, or whose `decided_at` is past the Challenge's `expires_at`. A `decision: escalate` Authorization MUST NOT count toward any `allow` quorum.

---

## 8. Modality Definitions

A Modality is the mechanism by which an Authorizer Device proves human presence at the moment of decision. Modalities required for v0.1 conformance:

- **`touch_id`** — fingerprint biometric on macOS, iOS, Windows Hello, or Android equivalents. The Authorizer Device's OS produces the proof-of-presence; the Authorizer software then signs the Authorization with the device's ed25519 key.
- **`face_id`** — facial biometric, analogous to `touch_id`. Required only if the device supports it; devices without face biometric fall back to `touch_id` or `passphrase`.
- **`voice_phrase`** — a speech sample whose content is constrained by the Challenge (e.g., "I authorize action `chg-3a7f12bc`"). Used for accessibility scenarios and remote-channel authorization. The Authorizer Device MUST run liveness checks before counting the modality as satisfied.
- **`passphrase`** — a stored secret known only to the Authorizer. Required as a baseline so that devices without biometric capability are not excluded.

Modalities optional in v0.1:

- **`yubikey`** — FIDO2 hardware key tap. The hardware key's signature is incorporated into the Authorization signature input.
- **`apple_watch`** — wrist-detection presence + tap-to-approve.

For every Modality, the proof-of-presence is local to the Authorizer Device. The Authorization carries only the device's ed25519 signature; the underlying biometric or hardware-key data MUST NOT cross the wire. Policies MAY require specific Modalities for specific Risk Levels (e.g., `dual_confirm` requires at least one biometric modality).

---

## 9. Pairing

Pairing establishes mutual trust between an Agent device and one or more Authorizer Devices. Each device holds a long-term ed25519 key generated at first launch and stored in the device's secure enclave (Keychain on macOS/iOS, TPM on Windows, Keystore on Android, or filesystem with appropriate permissions on Linux).

Pairing flow:

1. Agent device displays a QR code containing: its `agent_pubkey`, an `agent_id` chosen by the user, and a 16-byte random `pairing_nonce`. The QR code MAY also include a LAN endpoint URL for follow-up.
2. Authorizer Device scans the QR code. It verifies the `pairing_nonce` is unused, generates a Pairing-Response signed by the Authorizer's long-term key, and returns it over LAN (preferred) or by display of a second QR code that the Agent device scans.
3. Both devices persist the other's `*_id`, `*_pubkey`, and a `paired_at` timestamp. Pairing is mutual: neither side proceeds until both have stored the counterpart.

Pairing produces no Receipt. Pairing MUST be revocable; revocation deletes the local trust record and SHOULD inform the counterpart via a final signed `pairing_revoked` message. A revoked Authorizer Device's signatures on Authorizations MUST be rejected by Verifiers that have observed the revocation.

A single Authorizer MAY pair multiple devices (e.g., phone + watch + laptop). Policies that require `dual_confirm` SHOULD specify whether "two devices, same identity" counts as two distinct authorizers; v0.1 default is **no** — `dual_confirm` requires two distinct Authorizer identities.

---

## 10. Transport

Three transports are defined. LAN is REQUIRED for v0.1 conformance; APNs/FCM and BLE are OPTIONAL.

**LAN (REQUIRED).** Authorizer Devices advertise via mDNS under the service type `_agent2fa._tcp`. The Agent connects over TLS with certificate pinning: the Authorizer Device's TLS certificate MUST be issued under (or signed by) the device's paired ed25519 key. Discovery and connection MUST fail closed if no paired device is reachable; the protocol MUST NOT silently fall back to "allow without authorization" on transport failure.

**APNs/FCM push (OPTIONAL).** For off-LAN Authorizer Devices, the Agent MAY deliver the Challenge body via APNs or FCM push to a paired device's push token. The push payload MUST be the Challenge JSON encrypted to the Authorizer Device's ed25519 public key (using an X25519 conversion); APNs/FCM service operators MUST NOT be able to read Challenge contents. The Authorization MAY be returned over LAN (if the device returns to LAN reachability) or as an encrypted push response.

**BLE (OPTIONAL).** Bluetooth Low Energy fallback for close-range scenarios where LAN is unavailable. BLE pairing piggybacks on the existing ed25519 Pairing; the BLE connection is encrypted under a session key derived from the paired ed25519 keys.

A conformant Agent MUST support LAN. A conformant Authorizer Device MUST support LAN. APNs/FCM and BLE are interoperability bonuses, not conformance requirements.

---

## 11. Time-Box and Bypass

The protocol is **fail-closed by default**: if no Authorization satisfies the Risk Level requirement before the Challenge expires, the Action MUST NOT execute, and the Verifier MUST emit a Receipt with `decision: deny` and a reason indicating timeout.

Policies MAY introduce a `bypass_until` window for narrowly-scoped Actions:

```yaml
bypass:
  - match: { command: "^kubectl apply -f deploy/" }
    risk_during_bypass: notify
    bypass_until: "2026-06-25T18:00:00Z"
    authorized_by: "alice-iphone"
    bypass_signature: "ed25519:<base64 over canonical bypass entry>"
```

A bypass MUST be signed by an Authorizer using the same key they would use for an Authorization. The bypass signature MUST cover the `match` clause, `risk_during_bypass`, `bypass_until`, and `authorized_by` fields. Receipts MUST record `bypass_active: true` and the signed bypass entry's hash whenever a bypass shortcuts a Challenge. Bypasses MUST be time-bounded; v0.1 imposes no upper limit on the window but RECOMMENDS bypasses of more than 8 hours be discouraged in `team` and `strict` policy templates.

---

## 12. Session Receipt via Hub Receipt

agent-2fa receipts are Hub Receipt v0.1 envelopes (see `../hub-receipt/v0.1.md`). This document does NOT redefine the receipt format. The agent-2fa-specific population of the envelope is:

- `subject = { "domain": "agent-2fa", "identifier": <challenge_id> }`
- `issuer_key_id` = the Verifier's ed25519 key (typically the Agent device's key, optionally a separate hardened Verifier process).
- `claims` carries: `risk_level`, `decision`, `authorizers` (array of `{authorizer_id, authorizer_pubkey, modality_used, decided_at}`), `modalities_used` (deduplicated array), `bypass_active` (bool; with `bypass_entry_hash` if true), `action_summary` (human-meaningful redacted form), `granted_at`, `expires_at` (the Authorization's window, NOT the receipt's).

Verifiers MUST emit a Receipt for every `confirm`-or-higher Action, regardless of the `decision` value. Receipts for `notify`-tier Actions are OPTIONAL.

Per Hub Receipt §8, replay defense lives in the consumer specification: agent-2fa's `claims.expires_at` and the uniqueness of `subject.identifier` (= `challenge_id`) together prevent replay of an Authorization against a later, unrelated Challenge.

---

## 13. Security Considerations

The protocol's threat model addresses the following adversaries:

- **Misleading-action attacks (phishing-style).** A compromised or hallucinating Agent attempts to obtain Authorization for an Action by presenting a misleading description to the human. Mitigation: the Authorizer Device MUST display the Challenge's `action` field verbatim, with `redacted_fields` only hiding values (never restructuring the visible operation). Policies SHOULD treat structured tool calls as easier to audit than free-form shell commands and configure stricter Risk Levels for the latter.
- **Compromised Agent.** An attacker who controls the Agent process cannot forge an Authorization (no access to Authorizer keys). They MAY still execute `notify`-tier Actions silently; policy authors MUST classify destructive Actions above `notify`.
- **Lost Authorizer Device.** Revocation removes the lost device's pubkey from each paired counterpart. Receipts signed by the lost device's key before revocation remain verifiable post-hoc; downstream consumers MUST consult the revocation list when assessing receipt trust at audit time.
- **Replay of Authorization.** The combination of unique `challenge_id` in `subject.identifier` and the Authorization's `decided_at ≤ challenge.expires_at` bound prevents replay against later Challenges. Verifiers MUST track recently-seen `challenge_id` values and reject duplicates.

Out of scope:

- **Compromised Authorizer Device.** If the device that holds the Authorizer's private key is itself compromised (malware, jailbreak, physical compromise), no protocol-layer defense applies. This is a hardware/OS-layer problem.
- **Coerced Authorizer.** Physical or social coercion of the human Authorizer is not addressed; multi-Authorizer policies (`dual_confirm`) raise the bar but do not eliminate the risk.

---

## 14. Relationship to MCP, OS prompts, and WebAuthn

**MCP.** agent-2fa is orthogonal to MCP. An MCP server MAY invoke the protocol via a standard tool call exposing `agent2fa.request_authorization`; the protocol itself does not depend on MCP, and Agents without MCP integration use agent-2fa identically.

**OS-level confirmation prompts (`sudo`, Windows UAC, Polkit).** OS prompts are coarse-grained, locally-confined, and unsigned. agent-2fa is per-Action, remote-authorizable across paired devices, and produces a signed Receipt. The two MAY coexist: a high-risk Action might trigger `sudo` AND agent-2fa `dual_confirm`.

**WebAuthn / FIDO2.** WebAuthn is per-website 2FA for human-initiated browser flows. agent-2fa is per-Action confirmation for AI agent flows. The threat models differ: WebAuthn protects against credential phishing across websites; agent-2fa protects against AI agents executing destructive Actions without human review. WebAuthn primitives MAY underlie the device-level proof for `touch_id`/`face_id` Modalities (the Authorizer Device using a platform WebAuthn API internally), but the cross-device protocol shape of agent-2fa is not a WebAuthn relying-party flow.

---

## 15. Conformance

A **conformant Agent** MUST:

- Load a Policy from a user-owned file at startup and reject runtime policy injection.
- Classify every executed Action against the loaded Policy before execution.
- For every Action whose Risk Level is `confirm` or `dual_confirm`: produce a signed Challenge per §6, send it via at least the LAN transport per §10, wait for one or two valid Authorizations per the Risk Level, and refuse to execute the Action if the required quorum is not reached before `expires_at`.
- Emit a Hub Receipt envelope per §12 for every `confirm`-or-higher Action regardless of `decision`.
- Reject Authorizations whose signature, `challenge_id`, or `decided_at` fails the §7 checks.

A **conformant Authorizer Device** MUST:

- Verify a Challenge's signature under its `agent_pubkey` before presenting the Action to the human.
- Display the Challenge's `action` field verbatim (subject to `redacted_fields` substitution).
- Require successful Modality verification before signing an Authorization.
- Sign Authorizations only with the device's long-term ed25519 key established at Pairing.
- Honor revocation: refuse to sign Authorizations after the local trust record is revoked.

Optional behaviors (APNs/FCM, BLE, additional Modalities) MAY be advertised but are not required for conformance.

---

## 16. Open Questions

These questions remain open for v0.2 and are explicitly solicited from RFC reviewers.

**(a) Action representation: textual command vs structured tool call.** The current `action` field accepts either `command` (string) or `tool` + `args` (object). Structured representations are easier to audit and harder for an Agent to mislead, but textual commands are universal across shell-style agents. Should v0.2 normatively prefer one and degrade the other to OPTIONAL? Trade-off: stricter prefers structured; reach prefers textual.

**(b) Latency budget for `confirm` flow.** The protocol targets <5 seconds end-to-end from Challenge issuance to Authorization receipt on LAN. This is empirically achievable but constrains the human's reaction time. Should v0.2 introduce a "pre-warm" mode where an Authorizer Device displays a likely-imminent Challenge before the Agent fully decides? Trade-off: faster UX vs more spurious prompts.

**(c) Offline operation policy.** When no Authorizer Device is reachable, the protocol fails closed. Should v0.2 allow a policy to cache a prior Authorization for a bounded window (e.g., "the previous `confirm` for the same `match` clause within the last 5 minutes counts")? Trade-off: usability in poor-network environments vs preserved per-action auditability.

**(d) IDE integration shape.** IDEs and agent runtimes need a callback or hook to insert agent-2fa between Action emission and execution. Should this be a protocol-level callback API (defined here) or a CLI shim (`agent2fa run -- <cmd>`) that wraps the Agent's execution path? Trade-off: protocol-level API is more uniform but requires IDE buy-in; CLI shim works with any runtime but is awkward for structured tool calls.

---

## 17. Appendix A: JSON Schemas

The following JSON Schemas accompany this specification (authored in WO-06):

- `agent-2fa/challenge/v0.1` — Challenge envelope (see §6).
- `agent-2fa/authorization/v0.1` — Authorization envelope (see §7).
- `agent-2fa/policy/v0.1` — Policy document (see §5).

Receipt envelope: `hub-receipt/envelope/v0.1` from [Hub Receipt v0.1](../hub-receipt/v0.1.md). Not redefined here.

---

## 18. Appendix B: Reference CLI

A reference command-line interface for the v0.1 protocol. Implementations MAY provide a different surface; this appendix exists to anchor reviewer mental model.

```
agent2fa pair                                 Pair this device with another device (interactive QR flow)
agent2fa pair list                            List paired devices and roles
agent2fa pair revoke <device-id>              Revoke pairing with a device
agent2fa policy load <path>                   Load a policy YAML file
agent2fa policy show                          Print the active policy
agent2fa policy templates                     Print the bundled policy templates (personal/team/strict)
agent2fa run -- <command>                     Classify <command>, request authorization if needed, execute
agent2fa request <action.json>                Request authorization for a structured action; print decision
agent2fa receipts list                        List receipts emitted by this Verifier
agent2fa receipts show <receipt-id>           Print a single receipt in canonical form
agent2fa verify <receipt.json>                Verify a receipt's signature against the known pairing set
```

Output is JSON by default; `--human` MAY produce a non-machine format. Exit codes: 0 = action allowed and executed, 1 = action denied, 2 = configuration or policy error, 3 = transport failure (fail-closed).

---

## 19. Appendix C: Minimal verifier flow

```
on action_requested(action):
    risk = policy.classify(action)               # §5
    if risk == "notify":
        log(action)
        return ALLOW                              # no Challenge emitted

    if policy.bypass_active(action, now):         # §11
        receipt.emit(bypass_active=true, ...)
        return ALLOW

    chal = challenge.build(action, risk)          # §6
    chal.sign(agent_privkey)
    quorum_needed = 1 if risk == "confirm" else 2  # §4

    transport.broadcast_to_paired(chal)           # §10 — LAN first
    auths = transport.collect_authorizations(chal, until=chal.expires_at)
    valid_allows = [a for a in auths if verify(a, chal) and a.decision == "allow"]
    distinct_authorizers = unique(a.authorizer_id for a in valid_allows)

    if len(distinct_authorizers) >= quorum_needed:
        receipt.emit(decision=ALLOW, authorizers=valid_allows, ...)  # §12 → Hub Receipt
        return ALLOW
    receipt.emit(decision=DENY, reason="quorum_not_reached_or_timeout", ...)
    return DENY
```

The Verifier MUST emit the Receipt before returning the decision to the caller, so that the audit trail is persisted even if the caller aborts.

---

## 20. Change Log

- **v0.1 (2026-06-25)** — Initial draft. Three Risk Levels, LAN-required transport, four base modalities, receipts via Hub Receipt v0.1.

---

## 21. Acknowledgements

This specification builds on the [Hub Receipt v0.1](../hub-receipt/v0.1.md) envelope and shares its signing conventions with [mcp-trust-registry v0.1](../mcp-trust-registry/protocol-v0.1.md). Device-level proof-of-presence techniques for the `touch_id` and `face_id` Modalities are informed by the WebAuthn / FIDO2 specifications. The "per-action confirmation" UX framing is informed by per-transaction confirmation flows that exist in mobile banking and similar high-stakes consumer applications.
