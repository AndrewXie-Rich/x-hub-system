# To Agent Users: X-Hub Security Upgrade Without Sacrificing Speed or Control

## 1) Core Conclusion

X-Hub is designed to preserve the agent-native experience (AI reads, writes, sends, and acts), while moving trust and risk control into a dedicated control plane.

You keep the same productivity flow. Security posture improves because:
- high-risk actions require Hub-signed manifests;
- paid/network/secrets are governed centrally;
- every action is auditable, revocable, and kill-switchable.

## 1.1) Why This Is More Than A Theory Now

This is already moving beyond architecture language.

In current preview builds:

- paid GPT-class routes can already be exercised through the same Hub-governed plane as local models;
- X-Terminal can surface configured model, actual model, and downgrade truth instead of pretending everything hit the preferred route;
- Supervisor and project execution loops are already becoming operational rather than remaining a pure roadmap concept.

So the real value proposition is now testable: stronger trust boundaries without collapsing the agent experience.

## 2) Trust Model

- **Only trusted source:** X-Hub.
- **Untrusted by default:** all terminals (including compromised local state, cache, clipboard, UI).
- **Execution rule:** terminals can only render/execute Hub-signed intent objects; local terminal payloads are never trusted.

## 3) What Improves for Regular Terminals

A generic terminal connected to X-Hub (default capability profile: Full) gains:
- centralized model routing (local + paid) and token/time quota control;
- paid API keys encrypted and stored on Hub, never exposed to terminals;
- per-device/user/app authorization and revocation;
- network and outbound actions audited at Hub;
- immediate per-device or global kill-switch.

Compromise containment: if a device is hijacked but uses Hub-provided AI capability, Hub can revoke AI access and web/paid capabilities immediately. A terminal compromise does not automatically compromise the Hub core.

Residual risk still exists on the terminal side (local context tampering/theft), because generic terminals do not use Hub memory by default.

## 4) Why X-Terminal Is Stronger

Compared with a generic agent terminal, X-Terminal adds:
- shared Hub memory and skills across devices;
- minimal local cache (display-only, non-authoritative);
- project continuity and supervisor orchestration;
- stronger policy coupling (X-Constitution + Memory-Core skill constraints).

Here `Memory-Core` should be read as a Hub-governed rule asset rather than a local plugin, user choice over which AI executes memory jobs remains in X-Hub, and durable memory writes still terminate through Writer/Gate.

Result: even if terminal state is compromised, attacker impact is constrained to local surface; Hub state and cross-project memory integrity remain protected.

## 5) Agent Integration Options (Email First: IMAP+SMTP)

X-Hub can support the full agent-style workflow (AI reads email, drafts, sends, archives) without removing capabilities. You can choose how much control moves into the Hub.

Two integration levels:

- Integration A: Hub as model router only (maximum freedom)
  - the agent terminal reads/drafts/sends/archives locally; Hub provides model routing (local + paid) and budgets;
  - paid keys stay on Hub; Hub can cut off AI usage and AI web/paid capabilities for a compromised device;
  - boundary: Hub cannot audit terminal-local side effects (including SMTP send), cannot provide the 30s undo window, and cannot kill-switch terminal-local actions.

- Integration B: Hub-managed Email Connector (recommended)
  - IMAP+SMTP runs on Hub connectors; terminals render and confirm;
  - send/archive are wrapped as Hub-signed ActionManifests + SAS, with optional cross-device confirmation (terminal B computes SAS independently);
  - default 30-second undo window before SMTP commit;
  - full audit trail in Hub (Raw Vault encrypted at rest).

## 6) Paid / Secrets / Remote Model Governance

- paid entitlement granularity: `(device_id, user_id, app_id)`;
- default policy: first manual approval once, then auto-renew (revocable anytime);
- pre-grants default TTL: 2h;
- secrets policy supports **local-only** mode (block remote model exfiltration).

## 7) Why This Fits Agent Users

Fast agent systems are strong at workflow speed. X-Hub adds a trust boundary that agent users can optionally adopt:
- no forced downgrade in agent capability;
- stronger containment for compromised terminals;
- clearer compliance and forensic audit surface for real deployments.

## 8) Practical Recommendation

- Use **X-Terminal + X-Hub** for long-running projects, shared memory, and highest security.
- Use **generic terminals + X-Hub** for lightweight access while still benefiting from model routing, paid controls, and audit.
- Enable cross-device confirmation for high-value actions (payments, external sending, irreversible writes).

## 9) Preview Status

X-Hub is still an early public preview, not a finished production product.

That is exactly why it is worth watching now: the architecture is already real enough to evaluate, while the implementation is still open enough for contributors to materially shape it.
