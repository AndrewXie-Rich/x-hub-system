# Security Model

<p class="lead">
One compromised terminal. One hostile webpage. One sketchy MCP server. One prompt injection. Any of those, today, can drag your whole AI setup down. X-Hub's job is to make sure they don't. This page walks through what we block, where we block it, and what we honestly can't promise.
</p>

<div class="preview-note">
  <strong>Public security position</strong>
  This page describes the public trust model and product direction. It intentionally explains the safety chain without publishing every internal implementation edge or still-evolving control detail.
</div>

## The Short Version

X-Hub treats security as the first product advantage:

- **first pairing is local**: a new trusted terminal should be established on the same Wi-Fi, not from an arbitrary remote surface
- **the Hub is the trust root**: terminals can execute, but they do not own policy, grants, memory truth, route truth, or final authority
- **missing trust fails closed**: no readiness, stale pairing, ambiguous grant target, invalid signature, or expired authorization should block instead of guessing
- **high-risk actions are signed**: irreversible or external side-effect paths should use Hub-generated manifests, Hub signatures, SAS checks, grants, and audit
- **memory and skills are governed**: long-term memory, X-Constitution, skill packages, pins, vetting, grants, and revocation live under Hub governance
- **local and paid models share one policy plane**: local runtimes and provider APIs are both governed by route truth, quota posture, and capability grants

## The Safety Chain

| Stage | What X-Hub tries to enforce |
| --- | --- |
| Pair | New high-trust clients begin with a same-Wi-Fi pairing ceremony, device identity, token state, and explicit revocation path |
| Authenticate | Device UUID, token state, optional certificates, allowed network posture, and source restrictions are treated as security inputs |
| Govern | Policy, grants, quota, route truth, memory truth, readiness, and capability scope are checked in the Hub |
| Execute | Terminals, local runtimes, paid APIs, skills, channels, and connectors act only inside the scope the Hub allowed |
| Verify | Signed manifests, SAS checks, deny reasons, evidence refs, and audit refs make execution explainable |
| Recover | Revocation, grant expiry, provider disablement, device freeze, and kill switches give the operator a way back |

## Why Same-Wi-Fi First Pairing Matters

Pairing is one of the highest-risk moments in any distributed agent system. If remote pairing is too easy, an attacker only needs to trick the operator once before an unknown client becomes a trusted doorway.

X-Hub's posture is stricter:

- first trust should be established from the local network where the operator can physically reason about the device
- the paired device should receive bounded identity and token state, not broad implicit authority
- later remote access can exist, but it should build on an explicit device binding and remain revocable
- denied source IPs, allowed networks, token rotation, and device freeze are part of the operating model

This does not make local networks magical. It reduces the chance that a public URL, tunnel, chat channel, or copied setup link becomes the first root of trust.

## Hub-First Authority

The terminal is not the authority boundary.

That design choice is the foundation for the rest of the system:

- a compromised terminal should not be able to rewrite durable memory truth
- a plugin or skill should not inherit high privilege just because it was imported
- a remote channel should not become a shadow control plane
- local UI state should not become the source of truth for high-risk execution
- cloud provider defaults should not silently own policy, route truth, or runtime evidence

The Hub is where durable authority should converge: pairing, grants, route truth, model readiness, memory governance, skill trust, quota posture, audit, and emergency controls.

## X-Constitution As A Safety Layer

X-Constitution is the value and behavior constraint layer for the system. It is designed to sit above any single task objective:

- pinned as durable governed memory
- updated only through authorized paths
- injected when high-risk, value-conflict, or policy-sensitive situations require it
- reinforced by policy, grants, audit, least privilege, and fail-closed behavior

The goal is practical, not decorative. It gives the system a persistent way to treat prompt injection, destructive misoperation, credential exfiltration, malicious skills, and silent privilege escalation as high-risk paths before the active model improvises a response.

For concrete examples such as hidden web prompts, hostile skills, fake completion, remote pairing inducement, and payment or outbound payload tampering, see the dedicated [X-Constitution page](/constitution).

## Memory Security

Memory is not just context. In an agent system, memory becomes operational authority: what the system believes, repeats, retrieves, and acts on later.

X-Hub's memory direction is built around five layers:

- Raw Vault for evidence
- Observations for structured facts and events
- Longterm for durable documents and constraints
- Canonical for compact injection truth
- Working Set for short-term active context

The security posture is:

- durable writes terminate through governed Hub-side paths, not arbitrary terminal-local state
- memory maintenance stays attached to user choice and Hub-side gates
- evidence-first and fail-closed rules reduce false completion and untraceable mutation
- X-Constitution remains a pinned long-term constraint instead of sinking into disposable chat history

More importantly, memory read, memory export, and memory writeback are security boundaries. X-Hub does not treat "relevant" as automatically visible, "extracted" as automatically durable, or "assembled into context" as automatically exportable to a remote model.

For the full memory control plane, five-layer memory model, role-aware serving, candidate writeback, and project recovery posture, see [Governed Memory Control Plane](/memory).

## Skill Security

Skills are treated as governed capability units, not install-equals-trust plugins.

The intended chain includes:

- package manifests
- publisher trust roots
- official catalog and package pins
- compatibility checks and package doctor surfaces
- vetting before risky execution
- grants, deny codes, revocation, and audit

This lets skills become reusable execution units without letting every package become a new trust root.

## Local Models, Paid Providers, And Quota

Local-first does not only mean "run a local model." It means the trusted control plane can remain user-owned.

X-Hub puts local and paid routes under the same governed plane:

- configured model and actual model should both be visible
- fallback and downgrade should be explicit, not hidden
- provider accounts, OAuth/key state, and quota pressure should be operator-visible
- paid capability should be grantable, revocable, auditable, and bounded by policy
- sensitive workloads can prefer local models while still using the same memory, skill, and audit posture

That is a stronger design than splitting local models and paid APIs into unrelated operational worlds.

## High-Risk Actions

For irreversible or externally visible actions, X-Hub's direction is:

- Hub creates the `ActionManifest` or `TxManifest`
- terminals render or execute signed intent instead of assembling trusted payloads locally
- confirmation surfaces verify Hub signatures and display SAS-style checks
- grants carry scope, TTL, and policy constraints
- execution returns evidence and audit references

The extracted protocol spec for this is [`agent-2fa`](https://github.com/AndrewXie-Rich/agent-2fa). Three risk tiers — `notify`, `confirm`, `dual_confirm` — map to per-action confirmation on paired Authorizer Devices (Touch ID, Face ID, voice phrase, passphrase). A prompt-injected `DROP TABLE prod_logs` hits the paired device before it hits the database; an outbound payment hits Face ID before the API call lands. agent-2fa is independent of X-Hub — you can take the spec without taking the implementation.

This pattern is relevant for payments, outbound messages, connector writes, code merges, remote commands, and other high-consequence actions.

## Receipts

Every authorized action — and every deny, downgrade, timeout, and escalation — produces a signed receipt using the [Hub Receipt v0.1](https://github.com/AndrewXie-Rich/x-hub-system/blob/main/specs/hub-receipt/v0.1.md) envelope. Receipts:

- bind a `subject` (the action, the skill call, the agent-2fa challenge, etc.) to an `issuer_key_id` and a verifiable signature
- are content-addressable and can be embedded in git commits, IDE metadata, chat messages, or compliance exports
- are verifiable outside X-Hub — any verifier with the issuer's public key can check authenticity without contacting the Hub
- are the same envelope used by `mcp-trust-registry` (skill execution receipts) and `agent-2fa` (per-action confirmation receipts), so a single audit trail covers both surfaces

Signed receipts move audit from "the system logged something" to "the system produced an externally verifiable artifact." That distinction is what makes the audit trail useful in EU AI Act / ISO 42001 / SOC2-conscious procurement contexts.

## Risk Pattern To Control Chain

| Risk pattern | What X-Hub uses to bound it |
| --- | --- |
| Full filesystem, mailbox, database, or memory reads | capability scope, project binding, role-aware memory, least privilege, audit |
| Sensitive-data sending, uploads, webhooks, external APIs | outbound grants, destination allowlists, signed intent, TTL, audit |
| Durable memory leakage or memory pollution | five-layer memory, durable write gate, pinned X-Constitution, memory export grants |
| Bulk delete, overwrite, or system configuration changes | destructive-action preflight, A-Tier, tool policy, manifests, safe-point review, [`agent-2fa`](https://github.com/AndrewXie-Rich/agent-2fa) `dual_confirm` |
| shell/root commands and dependency installation | command allow/deny policy, working-directory scope, runtime readiness, evidence refs |
| Plugin or skill supply-chain attacks | manifests, publisher trust, package pins, compatibility doctor, vetting, revocation, [`mcp-trust-registry`](https://github.com/AndrewXie-Rich/mcp-trust-registry) attestation chain |
| Public exposure, weak auth, mistaken pairing | same-Wi-Fi first trust, device identity, token rotation, allowed source, device freeze |
| Lateral movement and privilege escalation | scoped grants, connector boundaries, secret policy, audit trail, kill switch |
| Goal drift, over-execution, cost runaway | execution budgets, quota posture, TTL, heartbeat anomaly, Supervisor review, clamps |
| Fake completion, fabricated logs, weak evidence | evidence-first memory, pre-done review, audit refs, done-candidate state, [Hub Receipt](https://github.com/AndrewXie-Rich/x-hub-system/blob/main/specs/hub-receipt/v0.1.md) envelope |
| Impersonation, unauthorized approvals, transfers, sends | actor binding, grant target, SAS, approval surface, signed manifest, `agent-2fa` paired-device confirmation |
| Missing audit and untraceable incidents | Hub-side audit, denial reasons, evidence refs, grant history, doctor/explainability, signed Hub Receipts |

These controls do not erase all risk. They move risk away from "one active agent silently decided" and toward "the Hub visibly allowed, denied, downgraded, held for confirmation, or stopped it."

## What This Improves

| Common default | X-Hub position |
| --- | --- |
| Active client becomes the trust root | Hub remains the trust root |
| Remote pairing is treated as convenience | First trust is local and explicit |
| Plugin install implies capability trust | Skills are governed packages with vetting and revocation |
| Memory drifts across clients and prompts | Durable memory truth stays Hub-governed |
| Local and paid models have separate governance | Both routes sit under one model and quota plane |
| Auto mode hides risk | Autonomy, review, heartbeat, grants, and clamps remain explicit |
| Failures are smoothed over | Missing trust fails closed and produces runtime truth |

## Residual Risk

X-Hub is not a claim of perfect safety. Local compromise, malicious files, implementation bugs, leaked credentials, operator mistakes, and provider-side incidents can still exist.

The value of the architecture is that these risks should be bounded by:

- smaller blast radius
- clearer authority boundaries
- revocable device and grant state
- more visible runtime truth
- stronger audit and recovery paths
- less reliance on whichever prompt or terminal happened to be active

That is the security thesis: not "AI will never fail," but "AI execution should fail inside governed boundaries."
