# X-Hub-System

<p>
  <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License MIT" />
  <img src="https://img.shields.io/badge/status-public%20tech%20preview-yellow.svg" alt="Public tech preview" />
  <img src="https://img.shields.io/badge/deployment-self--hosted-blue.svg" alt="Self-hosted" />
  <img src="https://img.shields.io/badge/security-fail--closed-critical.svg" alt="Fail-closed" />
  <img src="https://img.shields.io/badge/model-open--core-orange.svg" alt="Open core" />
</p>

> **Self-hosted governance plane for AI agents.**
> Route Claude, GPT, and local models across your team or family with audit, grants, fail-closed boundaries, and data sovereignty.

[中文 README](README_zh.md) · [Capability matrix](docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md) · [Releases](https://github.com/AndrewXie-Rich/x-hub-system/releases)

## Who it's for

- **Teams and enterprises** that can't ship code, prompts, or memory through SaaS-only AI tools → see [ENTERPRISE.md](ENTERPRISE.md)
- **Families** that want shared AI with parent-controlled limits and high-risk-action confirmation → see [FAMILY.md](FAMILY.md) (中文主)
- **Developers** who want to see and audit what actually ran, route truth and fallback included → keep reading

## The boundary in one diagram

![X-Hub trust and control plane](docs/open-source/assets/xhub_trust_control_plane.svg)

The terminal is not the trust root. Model routing, memory truth, grants, audit, skill trust, and execution readiness are governed from the Hub. Terminals and other clients are replaceable governed surfaces.

## What's working today

Each bullet maps to a `validated` or `preview-working` row in the [capability matrix](docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md):

- Hub-first trust anchor with fail-closed defaults on pairing, grants, readiness, and policy gates
- One control plane routing both local models (Transformers / MLX) and paid providers (Claude / GPT / others)
- Hub-backed memory UX with `Writer + Gate` as the only durable-write boundary
- Governed skills catalog with publisher trust roots, pin / grant / revoke, and preflight gating
- Project governance with separate `A-Tier` (execution authority), `S-Tier` (supervision depth), and `Heartbeat / Review` (cadence) controls
- Hub-governed multi-channel ingress (Slack / Telegram / Feishu / voice / mobile-confirmation) with replay guard and grant gating
- Honest runtime visibility — configured vs actual model, fallback, downgrade, blocked reason, and recovery evidence all surfaced

Anything not in the matrix as `validated` or `preview-working` should be read as implementation-in-progress or direction-only.

## Quick start (macOS, 5 min)

```bash
git clone https://github.com/AndrewXie-Rich/x-hub-system.git
cd x-hub-system && ./x-hub/tools/build_hub_app.command
open build/X-Hub.app   # pair X-Terminal once Hub is up
```

For full source-run / Rust kernel / packaged release flows see [`docs/REPO_LAYOUT.md`](docs/REPO_LAYOUT.md) and [`RELEASE.md`](RELEASE.md).

## Architecture in 30 seconds

Pair → resolve client capability → retrieve governed memory and policy → resolve model and capability route → check grants and readiness → execute through a governed surface → audit and report runtime truth. All authority sits in the Hub; terminals call into it.

Deep dives: [`docs/REPO_LAYOUT.md`](docs/REPO_LAYOUT.md), [`docs/xhub-hub-architecture-tradeoffs-v1.md`](docs/xhub-hub-architecture-tradeoffs-v1.md), [archived long-form README](docs/legacy/README_full_v1.md).

## Specs (extracted)

Two protocol specs have been extracted from X-Hub for independent community review. X-Hub-System is their reference implementation:

- [**mcp-trust-registry**](specs/mcp-trust-registry/) — federated attestation + capability tokens above MCP. Pre-RFC, v0.1 draft.
- [**agent-2fa**](specs/agent-2fa/) — Touch ID / dual-confirm for AI agent actions. Pre-RFC, v0.1 draft.
- [**hub-receipt**](specs/hub-receipt/) — shared signed-receipt primitive used by both specs above.

## License and commercial

X-Hub-System ships under an **open-core** model:

- **MIT-licensed kernel** — Hub daemon, single-user grants/audit, basic routing, governed skills, local model runtime. Free for personal, family, and open-source use, forever.
- **Commercial license** — multi-user roles, SSO/OIDC, SIEM export, compliance report generators, support SLA, private deployment and integration. See [ENTERPRISE.md](ENTERPRISE.md).
- Pilot inquiry: <contact@xhubsystem.com>

Repository license details: [LICENSE](LICENSE), [LICENSE_POLICY.md](LICENSE_POLICY.md), [TRADEMARKS.md](TRADEMARKS.md). The MIT license does not grant trademark rights.

## Status

Public tech preview. Core paths run; onboarding, packaging, and surface UX are still moving. Per-surface truth: **[capability matrix](docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md)**. Release notes must not claim beyond it.

## Community

Issues: <https://github.com/AndrewXie-Rich/x-hub-system/issues> · Security: [SECURITY.md](SECURITY.md) · Governance: [GOVERNANCE.md](GOVERNANCE.md) · Contributing: [CONTRIBUTING.md](CONTRIBUTING.md)
