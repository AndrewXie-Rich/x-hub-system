# X-Hub-System for Teams and Enterprises

> Self-hosted AI control plane for organizations that can't put trust, keys, prompts, memory, or audit truth into a vendor cloud.

[中文版](ENTERPRISE_zh.md) · [Capability matrix](docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md) · [Back to README](README.md)

## Who this is for

- **Regulated industries** — finance, healthcare, legal, public sector — where AI activity must be auditable end-to-end
- **Engineering orgs** whose source code, prompts, or internal knowledge cannot leave the corporate network
- **Compliance teams** that need a single boundary to govern model access, key custody, and high-risk-action review
- **Anyone scaling AI usage** where "one prompt injection ➜ org-wide blast radius" is unacceptable

## The control plane, not the chat box

![X-Hub deployment and runtime topology](docs/open-source/assets/xhub_deployment_runtime_topology.svg)

In most agent stacks, the terminal owns prompts, tools, browser state, memory, secrets, and execution together. One prompt injection or one compromised plugin expands the trust boundary across the whole stack.

X-Hub-System inverts that. Terminals, skills, MCP servers, browser tabs, and operator channels are **governed surfaces** that call into your Hub. The Hub is the trust anchor. The Hub holds the keys. The Hub decides what runs, who can ask it to run, and what gets logged when it does.

## What you can govern

Every row maps to one or more rows in the [capability matrix](docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md).

| Surface | Control you get | Audit evidence |
|---|---|---|
| Model routing | One plane for Claude / GPT / Gemini / local; fallback and downgrade visible as truth, not silent | `route_truth` events, configured-vs-actual model record |
| API keys & OAuth | Hub-held; clients never see keys; per-provider quota and reset windows are first-class | grant records, key custody log |
| Skills / MCP servers | Pinned, signed via publisher trust root, revokable; preflight gate before execution | skills policy events, audit prune trail |
| Memory | `Writer + Gate` is the only durable-write boundary; clients consume governed projections | memory event chain, gate decisions |
| High-risk actions | A-Tier (execution authority), S-Tier (supervision depth), Heartbeat/Review (cadence) — three separate controls, not one autonomy slider | autonomy clamp logs, review event stream |
| Operator channels | Slack / Telegram / Feishu / voice / mobile-confirmation, with replay guard and grant gating before high-trust execution | channel ingress audit, second-factor latch records |
| Local model runtime | Transformers / MLX governed under the same routing, capability, and kill-switch posture as paid models | runtime readiness, doctor evidence |

## Deployment topology

- **Hub daemon** — self-hosted; today macOS, **Linux daemon on the 90-day roadmap** (see below)
- **Admin client** — macOS X-Hub app, embedding the Rust kernel; used by Hub administrators for grants, audit review, and skill governance
- **End-user clients** — X-Terminal today (macOS); **Web thin client on the roadmap** so Windows/Linux teammates can participate
- **Network posture** — Hub binds to localhost by default; LAN / cross-device exposure requires explicit readiness gates (`tools/cross_network_readiness_gate.command`)

For the full per-surface state, the [capability matrix](docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md) is authoritative. We do not claim beyond it in release notes.

## Compliance alignment (alignment, not certification)

X-Hub-System is **architected to support** the controls these frameworks require. The repository itself is not certified — bring your own auditor when you need a formal attestation.

- **EU AI Act** — data-sovereignty by default, audit trail per execution, kill-switch, fail-closed defaults, governed autonomy tiers with documented supervision
- **China GenAI 备案 / 网信办** — 本地化部署可选、内容审计链路、可控模型路由、可审计的提示词与输出记录
- **ISO 42001** — AI management system posture: explicit roles, governed change to policy, documented incident response surfaces
- **SOC 2 Type II posture** — access logging, change audit, capability state matrix as a working SoR — auditor still required for the actual report

A side-by-side comparison vs LangSmith, Pangea AI Guard, Lakera, and Portkey will land in a follow-up doc as competitive evaluation requests come in.

## SIEM and observability integration

**Status: planned, not shipped.** The 90-day P0 plan adds a JSON Lines audit export with the following schema:

```jsonl
{"ts":"2026-06-24T08:00:00Z","actor":"alice@team","action":"skill.execute","resource":"web-search","decision":"allow","evidence_ref":"audit-2026-06/0001"}
```

Splunk / Datadog / Elastic / OpenSearch compatible. Until that lands, audit truth lives in Hub-local SQLite plus `evidence_bridge` JSONL files — usable but not yet SIEM-shaped.

## Open Core model

| Tier | License | What's included | Who pays |
|---|---|---|---|
| Kernel | MIT | Hub daemon, single-user grants/audit, basic routing, governed skills, local model runtime | Free forever |
| Commercial | Commercial license | Multi-user roles, SSO / OIDC, SIEM export, compliance report generators, support SLA | Teams / enterprises |
| Services | Engagement | Private deployment, security review, integration build-out | Per-engagement |

Individual developers, families, and open-source contributors stay on the kernel tier indefinitely. There is no plan to take features back into the commercial tier once they ship as MIT.

## Roadmap blocks gating enterprise readiness

These are the things we are honestly not done with yet, prioritized:

1. **Multi-user role model** (admin / operator / observer) with `actor_id` on every grant and audit event
2. **SIEM-friendly audit export** (JSONL with the schema above)
3. **Linux Hub daemon** — abstract macOS-specific calls (launchd, keychain) behind traits in the Rust kernel; `docker-compose up` deployment
4. **OIDC login** against existing IdPs (Okta / Google Workspace / Feishu / Azure AD) — read-only first, SCIM later
5. **Web thin client** — covers Windows and Linux teammates without a per-OS native build

Items 1-4 are the 90-day P0. Item 5 follows on a 6-month horizon. Until they land, X-Hub-System is enterprise-ready in architecture but operations-ready only for small teams on macOS with shared Hub access.

## Get in touch

- **Pilot inquiry** — <contact@xhubsystem.com>. Tell us your industry, team size, regulatory framework, and which surface is most pressing for you.
- **Security disclosure** — see [SECURITY.md](SECURITY.md). Please don't file as a public GitHub issue.
- **License questions** — [LICENSE_POLICY.md](LICENSE_POLICY.md) and [TRADEMARKS.md](TRADEMARKS.md)
- **Architecture questions / contribution** — [GOVERNANCE.md](GOVERNANCE.md) and [CONTRIBUTING.md](CONTRIBUTING.md)
