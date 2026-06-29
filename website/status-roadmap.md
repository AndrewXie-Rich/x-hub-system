# Status & Roadmap

<p class="lead">
X-Hub-System is a public technical preview. This roadmap separates what is already in main, what is being productized now, and what is deliberately out of scope for the current cycle. Per-surface status is governed by the <a href="https://github.com/AndrewXie-Rich/x-hub-system/blob/main/docs/open-source/XHUB_CAPABILITY_MATRIX_v1.md">capability matrix</a>.
</p>

<div class="preview-note">
  <strong>Public preview.</strong>
  Core paths run. Onboarding, packaging, and surface UX are still moving. The matrix is the truth source. No SLA is claimed for v0.x; SLA appears with the commercial license once Linux daemon and multi-user UI ship.
</div>

## Established (2026-06)

<div class="story-grid">
  <div class="story-card">
    <span>Specs extracted</span>
    <strong>Two protocol specs live as standalone repos</strong>
    <p><a href="https://github.com/AndrewXie-Rich/mcp-trust-registry">mcp-trust-registry</a> (federated attestation + capability tokens above MCP) and <a href="https://github.com/AndrewXie-Rich/agent-2fa">agent-2fa</a> (per-action 2FA for AI agents) shipped as independent v0.1 drafts in 2026-06. Schemas, examples, CI validation, and pre-RFC discussion bodies are in place.</p>
  </div>
  <div class="story-card">
    <span>Receipt primitive</span>
    <strong>Hub Receipt v0.1 envelope</strong>
    <p>A shared signed-receipt envelope used by both spinoff specs. Every authorized action produces a verifiable record that can be embedded in git commits, IDE metadata, and chat messages — verifiable outside X-Hub. Spec: <a href="https://github.com/AndrewXie-Rich/x-hub-system/blob/main/specs/hub-receipt/v0.1.md">hub-receipt/v0.1.md</a>.</p>
  </div>
  <div class="story-card">
    <span>Multi-user schema</span>
    <strong>Hub kernel multi-user foundation landed</strong>
    <p>2026-06 migration adds <code>rust_hub_users</code> + <code>actor_id</code> columns on seven audited-event tables. Admin / operator / observer roles can be enforced behind a feature flag. Hub admin UI for user management is the next step.</p>
  </div>
  <div class="story-card">
    <span>Trust posture</span>
    <strong>Hub-first trust + fail-closed defaults</strong>
    <p>Pairing, grants, memory truth, model routing, skill trust, audit, and shutdown authority converge on the Hub. Missing signal stops the system instead of guessing.</p>
  </div>
  <div class="story-card">
    <span>Memory plane</span>
    <strong>Governed memory control plane</strong>
    <p>Hub-first memory truth, policy-gated retrieval, role-aware assembly, candidate writeback, readiness, doctor, and audit evidence define the working surface.</p>
  </div>
  <div class="story-card">
    <span>Skills plane</span>
    <strong>Governed skills catalog</strong>
    <p>Official catalog, manifests, publisher trust roots, pins, preflight, vetting, grants, and revocation. This subsystem is the reference implementation for the mcp-trust-registry spec.</p>
  </div>
</div>

## Being productized (90-day P0)

| Area | Current focus |
| --- | --- |
| MCP RFC submission | Submit `mcp-trust-registry` v0.1 to the MCP community discussions; recruit 3–5 pilot publishers |
| `agent-2fa` reference CLI | Minimal Rust `agent2fa-cli` + paired-device iOS Authorizer to prove the wire protocol end to end |
| Hub admin multi-user UI | User management surface backed by the new multi-user schema; enforce flag in gate |
| SIEM audit export | JSONL export of the audit log with `actor_id`; SOC2-conscious format |
| Linux daemon | `docker-compose up` deployment; abstract launchd-specific calls behind a trait |
| Web thin client | Browser-based governed client; replaces the frozen rust-xtd direction |
| OIDC / SSO | Read-only OIDC against existing IdPs as the first SSO entry point |
| Release packaging | Combined DMG, Hub-only / XT-only artifacts, SHA256, signing, notarization notes |

## Deliberately out of scope (this cycle)

- **New ingress channels.** Slack / Telegram / Feishu / voice already shipped; no new ones until Linux + Web land.
- **Consumer IDE-killer features.** Cursor / Cline / Claude Code / Aider already own developer IDE UX. X-Hub sits next to them, not against them.
- **rust-xtd sidecar.** Frozen at the current scaffold; the Web thin client subsumes this direction.
- **SOC 2 / ISO 42001 certification.** Architectural alignment is being pursued; actual certification is a separate 9–12 month effort and is not in this cycle.

## Roadmap priority order

1. Ship the two spinoff specs into the relevant communities (MCP Discussions, AI runtime maintainer outreach).
2. Land the Hub admin multi-user UI + SIEM export so the open-core commercial line has a working surface to show.
3. Linux daemon → Web thin client → OIDC, in that order.
4. Keep the capability matrix in sync with every status change; never let the matrix lag the page.

Continue with:
[Get Started](/get-started), [Memory Control Plane](/memory), [Trust Model](/security).
