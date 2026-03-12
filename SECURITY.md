# Security Policy

X-Hub is built around a Hub-first trust model and fail-closed behavior for high-risk paths.

That makes security reports especially important for anything that could weaken pairing, grants, policy enforcement, audit integrity, route control, execution safety, or the memory-backed constitutional guardrails intended to stabilize agent behavior.

## Supported Versions

Security fixes are provided for:

- the default branch
- the most recent tagged release, when releases exist

## How To Report A Vulnerability

Please do **not** open public GitHub issues for security reports.

Use this repository's **GitHub Security Advisories** flow through "Report a vulnerability".

If that option is not available, open a minimal public issue asking for a private reporting channel and do not include exploit details, secrets, tokens, or sensitive reproduction artifacts.

## What To Include

Please include as much of the following as you can:

- affected component or path
  - examples: Hub app, gRPC server, Python runtime, terminal client, pairing flow, grant path, tool route
- version, tag, or commit hash
- deployment context
  - local only, LAN pairing, remote route, bridge-enabled runtime, and so on
- reproduction steps
- expected behavior
- actual behavior
- impact
  - what an attacker or unauthorized actor can do
- any logs, traces, or evidence references with secrets removed
- any mitigation, guardrail, or patch suggestion you already tested

## High-Priority Report Areas

We are especially interested in reports involving:

- trust-boundary bypass between terminal and Hub
- pairing or device-identity weaknesses
- grant or capability escalation
- memory- or constitution-layer bypass that weakens risk, privacy, or authorization guardrails
- policy or readiness bypass
- audit tampering or evidence-loss paths
- secret exposure, key handling, or insecure persistence
- bridge or tool execution routes that should fail closed but do not

## Response Targets

- acknowledge receipt within 7 days
- provide an initial assessment or next step within 14 days

Response times may be faster for clearly reproducible issues affecting the trust boundary or high-risk execution paths.

## Scope Notes

- Security-sensitive design intent is documented across `README.md`, `RELEASE.md`, and `docs/open-source/OSS_RELEASE_CHECKLIST_v1.md`.
- X-Constitution and related policy-engine references are documented in `X_MEMORY.md`, `docs/xhub-constitution-l0-injection-v1.md`, `docs/xhub-constitution-l1-guidance-v1.md`, and `docs/xhub-constitution-policy-engine-checklist-v1.md`.
- The intended model is Hub-side memory-backed constitutional guidance reinforced by policy controls, not terminal-only prompt text treated as a security boundary.
- Public capability claims remain limited to the validated release slice described in `README.md`.
- If you are unsure whether something is security-relevant, report it anyway.
