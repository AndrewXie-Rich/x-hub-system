# GitHub Release Notes Template v1

Purpose:

- This template is intended for direct use on the GitHub Release page
- External wording must stay inside the current validated release slice
- Do not use the release page to expand scope

Recommended companions:

- `README.md`
- `RELEASE.md`
- `docs/WORKING_INDEX.md`
- `docs/open-source/OSS_RELEASE_CHECKLIST_v1.md`

---

## Copy-Paste Template

```md
# X-Hub v0.1.0-alpha

X-Hub is a trusted control plane for AI execution.

This release is intentionally narrow and only reflects the currently validated public release slice.

Internal work-order packs, operator docs, and in-progress implementation slices in this repository may extend beyond this public release slice. Do not mirror that internal progress directly into external release messaging.

## What This Release Covers

Validated release slice:

- `XT-W3-23 -> XT-W3-24 -> XT-W3-25`

Validated public statements for this release:

- XT memory UX adapter backed by Hub truth-source, with user-selected memory executor and Writer + Gate durable-write boundary
- Hub-governed multi-channel gateway
- Hub-first governed automations

## Why It Matters

X-Hub keeps model routing, memory truth, grants, policy, audit, and execution safety inside one governed Hub, while terminals stay lightweight and untrusted by default.

If memory posture is mentioned in public wording, keep it inside this boundary: the user chooses which AI executes memory jobs in X-Hub, `Memory-Core` is a governed Hub-side rule asset rather than a normal plugin, and durable writes still terminate through `Writer + Gate`.

Compared with a terminal-only AI setup, this release emphasizes:

- Hub-first trust boundaries
- unified governance for local and paid models
- memory-backed constitutional guardrails reinforced by Hub policy controls
- fail-closed readiness and execution behavior
- safer automation paths under Hub control

## Recommended Host Hardware

X-Hub is recommended to run on Apple silicon desktop Macs.

- **Mac mini**: default recommendation for most deployments
- **Mac Studio**: higher-capacity recommendation for heavier local-model load, more memory, or more concurrency

This makes X-Hub a strong fit for:

- enterprises
- public-sector teams
- regulated or security-sensitive environments
- individuals who want a safer and more controlled AI setup

## Included In This Release

- root product and navigation docs
- active Hub and terminal source trees
- protocol contracts
- open-source release and packaging docs

## Quick Start

Build the Hub app:

```bash
x-hub/tools/build_hub_app.command
```

Launch the built X-Hub app:

```bash
open build/X-Hub.app
```

Run X-Terminal from source:

```bash
cd x-terminal
swift run XTerminal
```

Run the XT release gate:

```bash
bash x-terminal/scripts/ci/xt_release_gate.sh
```

Developer note: the public Hub source-run entrypoint is `bash x-hub/tools/run_xhub_from_source.command`. The internal Swift package still lives under the historical compatibility directory `x-hub/macos/RELFlowHub/`.

## Security Posture

- high-risk paths fail closed when critical readiness is incomplete
- the terminal is not the trust anchor
- constitutional guidance is intended to be pinned on the Hub side and reinforced by policy controls
- any memory-control wording should keep `Memory-Core` on the governed rule layer and keep durable writes on `Writer + Gate`
- grants, routing, and execution safety stay under Hub control

If you mention constitutional or memory-backed guardrails in release notes, keep them in the system safety posture lane. Do not present them as additional validated feature claims beyond the approved release slice.

## Known Scope Limits

This release does **not** claim the full internal document set as publicly validated capability.

If a capability is not explicitly covered by the validated release slice above, treat it as outside the scope of this release.

## Release References

- `README.md`
- `RELEASE.md`
- `docs/WORKING_INDEX.md`
- `docs/REPO_LAYOUT.md`
- `docs/open-source/OSS_RELEASE_CHECKLIST_v1.md`

## Rollback Reference

If rollback is required, use the last known good tag and the rollback procedure documented in `RELEASE.md`.
```

---

## Usage Rules

Before publishing, confirm:

1. the tag, scope, and validated claims match `README.md`
2. no unverified capability wording was added
3. if you add a “What changed” section, keep it inside the actual public release scope
4. if you mention host hardware, keep the wording as:
   - `Mac mini` as the default recommendation
   - `Mac Studio` as the higher-capacity recommendation
5. do not turn internal work-order names, internal slice progress, or operator navigation material into public release claims
6. if you need extra runtime/support wording, refresh `build/reports/oss_release_support_snippet.v1.md` first, but keep any operator-channel wording from that snippet in the preview/support lane rather than the validated public-statements lane
7. if you need safe-onboarding preview/support evidence, rerun `bash scripts/ci/xt_w3_24_s_safe_onboarding_gate.sh` first and treat `build/reports/xt_w3_24_s_safe_onboarding_gate_summary.v1.json` plus `docs/open-source/evidence/xt_w3_24_s_safe_onboarding_release_evidence.v1.json` as support material only, not as validated release claims
