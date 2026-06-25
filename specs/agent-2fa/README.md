# agent-2fa

<p>
  <img src="https://img.shields.io/badge/spec-v0.1%20draft-yellow.svg" alt="Spec v0.1 draft" />
  <img src="https://img.shields.io/badge/status-pre--RFC-orange.svg" alt="Pre RFC" />
  <img src="https://img.shields.io/badge/license-Apache--2.0-blue.svg" alt="Apache 2.0" />
</p>

> **Touch ID for AI agent actions.** Per-action confirmation with paired authorizer devices, signed receipts, fail-closed defaults. So your AI agent can't `rm -rf` because a prompt injection convinced it to.

[Specification (v0.1 draft)](protocol-v0.1.md) · [60-second demo](demo-60s.md) · 中文 (TBD)

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

AI agent runtimes today execute high-impact actions — file deletions, force-pushes, database drops, deploys, message sends — without any per-action human authorization layer. The blast radius of one prompt injection, one hallucinated tool call, or one bad context window is unbounded. The missing primitive is per-action 2FA for destructive operations.

Banks figured this out two decades ago. Per-transaction confirmation, with proof-of-presence (Touch ID, OTP, push) bound to a *separate* device, defeats both keylogged credentials and a compromised primary. agent-2fa applies the same shape: a local policy classifies actions into three risk tiers; high-risk actions raise a signed Challenge to paired Authorizer Devices; the human authorizes (or denies) on the second device.

## Install (preview)

> v0.1 is a draft. APIs may break. Not for production.

```bash
brew install agent2fa            # macOS preview tap
cargo install agent2fa-cli       # any platform with Rust
```

Wrap your agent runtime:

```bash
# Before:  agent-cli "deploy to prod"
# After:   agent2fa run -- agent-cli "deploy to prod"
```

## How it works (90 seconds)

You **pair** the device that runs the agent with one or more **Authorizer Devices** (phone, watch, laptop, hardware key). Pairing is QR-based, mutual, and persists an ed25519 long-term key per device. You then **load a policy** — `personal`, `team`, `strict`, or your own — that maps Actions to Risk Levels. When your agent attempts an Action, the local Action Gate classifies it; `notify` actions execute silently with a log line, `confirm` actions raise a Challenge to one Authorizer Device, `dual_confirm` actions require two distinct Authorizers. The Authorizer Device displays the Action verbatim, requires a Modality (Touch ID by default), and signs an Authorization. The Verifier (typically the agent process) checks the signature, executes (or denies) the Action, and emits a signed Receipt regardless of outcome.

Three things you didn't have before:

- **Policy decides what's high-risk.** A YAML file you own, with `personal` / `team` / `strict` templates and a regex-or-tool-call DSL.
- **Authorizers are cryptographically paired devices.** Not TOTP, not username/password. Pair once via QR; revoke when you lose the device.
- **Receipts are signed and Hub-Receipt-compatible.** Every `confirm`-or-higher Action produces a verifiable receipt. Same envelope as [Hub Receipt v0.1](../hub-receipt/v0.1.md).

Full data model and wire format: [`protocol-v0.1.md`](protocol-v0.1.md).

## Status

| Component | State |
|---|---|
| Specification v0.1 | Draft, pre-RFC |
| Modalities | Touch ID / Face ID / voice / passphrase required; YubiKey, Apple Watch optional |
| Transport | LAN + mDNS + TLS-pinned required; APNs / FCM / BLE optional |
| `agent2fa-cli` (Rust) + Authorizer iOS app | Skeleton |

A reference deployment ships inside [X-Hub-System](https://github.com/AndrewXie-Rich/x-hub-system) as its mobile-confirmation-latch subsystem.

## Relationship to other protocols

agent-2fa is **not WebAuthn**. WebAuthn is per-website 2FA for human-initiated browser flows; agent-2fa is per-Action confirmation for AI agent flows. WebAuthn primitives MAY underlie the device-level proof for `touch_id`/`face_id` Modalities, but the cross-device protocol shape is different.

agent-2fa is **orthogonal to MCP**. MCP servers MAY invoke `agent2fa.request_authorization` via a standard tool call interface, but the protocol does not depend on MCP. Agents without MCP integration use agent-2fa identically.

Receipts reuse the **Hub Receipt v0.1** envelope rather than redefining a signed-receipt format. See [`hub-receipt/v0.1.md`](../hub-receipt/v0.1.md).

## Contributing

We are pre-RFC. The most valuable contribution right now is **review of the spec**, especially:

- Policy DSL granularity (§5) — regex vs structured tool-call matching.
- Action representation for structured tool calls (§16(a)).
- Latency target for `confirm` flow (§16(b)).

Open issues at <https://github.com/AndrewXie-Rich/agent-2fa/issues> (placeholder). Until that repo is live, comment on the X-Hub-System repo's discussions.

## License

Specification: **CC BY 4.0**. Reference implementations: **Apache 2.0**.

Contributions to this project are accepted under the same licences. By contributing, you agree to the Developer Certificate of Origin.
