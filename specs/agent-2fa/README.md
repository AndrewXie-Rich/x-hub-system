# agent-2fa

<p>
  <img src="https://img.shields.io/badge/spec-v0.1%20draft-yellow.svg" alt="Spec v0.1 draft" />
  <img src="https://img.shields.io/badge/status-draft-orange.svg" alt="Draft" />
  <img src="https://img.shields.io/badge/license-MIT%20%2F%20CC--BY--4.0-blue.svg" alt="License" />
</p>

> **Touch ID for AI agent actions.** Per-action confirmation with paired authorizer devices, signed receipts, fail-closed defaults. So your AI agent can't `rm -rf` because a prompt injection convinced it to.

[Canonical repo](https://github.com/AndrewXie-Rich/agent-2fa) · [Local spec mirror](protocol-v0.1.md) · [60-second demo](demo-60s.md) · [Reference proxy](https://github.com/AndrewXie-Rich/agent-2fa/tree/main/proxy) · 中文 (TBD)

> Canonical public source lives at [`github.com/AndrewXie-Rich/agent-2fa`](https://github.com/AndrewXie-Rich/agent-2fa). This directory is the X-Hub-System mirror/reference pointer; public-facing spec and proxy changes should land in the standalone repo first, then be mirrored back here.

## What you see

```
$ agent2fa pair
  scan QR on paired device… ✓ touch ID confirmed
  paired: alice-iphone  (ed25519:k0a7…)

$ agent2fa policy load personal.yaml
  ✓ 11 rules loaded. default=confirm. notify allowlist=git-commit,git-push

$ agent2fa run -- agent-cli "drop the prod logs table"
  classified: dual_confirm  (matches: ^(DROP|TRUNCATE)\s+)
  challenge chg-3a7f12bc  → alice-iphone, bob-laptop
  alice-iphone: touch_id ✓ allow
  bob-laptop:   touch_id ✓ allow
  → executing…
  ✓ DROP TABLE completed
    receipt: a2fa-7c1e (signed, Hub Receipt envelope)
```

## Why this exists

AI agent runtimes today execute high-impact actions, like file deletions, force-pushes, database drops, deploys, and message sends, without any per-action human authorization layer. The blast radius of one prompt injection, one hallucinated tool call, or one bad context window is unbounded. The missing primitive is per-action 2FA for destructive operations.

Banks figured this out two decades ago. Per-transaction confirmation, with proof-of-presence (Touch ID, OTP, push) bound to a *separate* device, defeats both keylogged credentials and a compromised primary. agent-2fa applies the same shape: a local policy classifies actions into three risk tiers; high-risk actions raise a signed Challenge to paired Authorizer Devices; the human authorizes (or denies) on the second device.

## Install (preview)

> v0.1 is a draft. APIs may break. Not for production.

```bash
cargo install --git https://github.com/AndrewXie-Rich/agent-2fa agent-2fa-proxy
agent-2fa-proxy verify --example
```

Wrap your agent runtime (planned for v0.1.1 once cross-device transport lands):

```bash
# Before:  agent-cli "deploy to prod"
# After:   agent-2fa-proxy run -- agent-cli "deploy to prod"
```

## How it works

You **pair** the device that runs the agent with one or more **Authorizer Devices** (phone, watch, laptop, hardware key). Pairing is QR-based, mutual, and persists an ed25519 long-term key per device. You then **load a policy**, like `personal`, `team`, `strict`, or your own, that maps Actions to Risk Levels. When your agent attempts an Action, the local Action Gate classifies it; `notify` actions execute silently with a log line, `confirm` actions raise a Challenge to one Authorizer Device, `dual_confirm` actions require two distinct Authorizers. The Authorizer Device displays the Action verbatim, requires a Modality (Touch ID by default), and signs an Authorization. The Verifier (typically the agent process) checks the signature, executes (or denies) the Action, and emits a signed Receipt regardless of outcome.

The pieces that aren't in plain agent runtimes:

- **Policy decides what's high-risk.** A YAML file you own, with `personal` / `team` / `strict` templates and a regex-or-tool-call DSL.
- **Authorizers are cryptographically paired devices.** Not TOTP, not username/password. Pair once via QR; revoke when you lose the device.
- **Receipts are signed and Hub-Receipt-compatible.** Every `confirm`-or-higher Action produces a verifiable receipt. Same envelope as [Hub Receipt v0.1](../hub-receipt/v0.1.md).

Full data model and wire format: [`protocol-v0.1.md`](protocol-v0.1.md).

## Status

| Component | State |
|---|---|
| Specification v0.1 | Draft |
| JSON Schemas + examples | CI validated |
| Reference proxy (Rust) — keygen, challenge, authorize, verify, policy-check, receipts | ✓ shipped in the [standalone repo](https://github.com/AndrewXie-Rich/agent-2fa/tree/main/proxy) (v0.1.0, 13/13 tests, MIT) |
| Modalities | Touch ID / Face ID / voice / passphrase required; YubiKey, Apple Watch optional |
| Transport | LAN + mDNS + TLS-pinned required; APNs / FCM / BLE optional |
| Authorizer iOS app + cross-device transport | Deferred to v0.1.1 |

A reference deployment ships inside [X-Hub-System](https://github.com/AndrewXie-Rich/x-hub-system) as its mobile-confirmation-latch subsystem.

## Relationship to other protocols

agent-2fa is **not WebAuthn**. WebAuthn is per-website 2FA for human-initiated browser flows; agent-2fa is per-Action confirmation for AI agent flows. WebAuthn primitives MAY underlie the device-level proof for `touch_id`/`face_id` Modalities, but the cross-device protocol shape is different.

agent-2fa is **orthogonal to AI tool protocols** (MCP, A2A, OpenAI tool calling, custom RPC). A tool server MAY invoke `agent2fa.request_authorization` via a standard tool call interface, but the protocol does not depend on any specific tool RPC. Agents without tool-server integration use agent-2fa identically.

Receipts reuse the **Hub Receipt v0.1** envelope rather than redefining a signed-receipt format. See [`hub-receipt/v0.1.md`](../hub-receipt/v0.1.md).

A kin spec, [**skill-trust-registry**](../skill-trust-registry/), addresses a different layer: pre-install attestation and capability-scoping for tool servers themselves. agent-2fa covers the *per-action* confirmation; skill-trust-registry covers the *per-install* trust decision. Both use the same Hub Receipt envelope and the same ed25519 + JCS conventions.

## Contributing

This is a draft. The most valuable contribution right now is **review of the spec**, especially:

- Policy DSL granularity (§5) — regex vs structured tool-call matching.
- Action representation for structured tool calls (§16(a)).
- Latency target for `confirm` flow (§16(b)).

Open issues at <https://github.com/AndrewXie-Rich/agent-2fa/issues>.

## License

Specification: **CC BY 4.0**. Reference implementations: **MIT**.

Contributions to this project are accepted under the same licences. By contributing, you agree to the Developer Certificate of Origin.
