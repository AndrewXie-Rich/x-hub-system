# Release Guide

This document defines the minimum process for cutting a public release.

This guide is release-operations facing. Use `README.md` for the product narrative and validated public wording.

Repository license note:
- public messaging should describe this repository as open source under the MIT License
- keep trademark and validated-scope notes separate from the software-license statement

Primary gate source:
- `docs/open-source/OSS_RELEASE_CHECKLIST_v1.md`

System description references:
- `docs/system/CURRENT_STATUS.md`
- `docs/system/RUST_MIGRATION.md`
- `docs/system/AUTHORITY_BOUNDARIES.md`
- `docs/system/API_AND_CONTRACTS.md`

GitHub Release page template:
- `docs/open-source/GITHUB_RELEASE_NOTES_TEMPLATE_v1.md`
- `docs/open-source/GITHUB_RELEASE_NOTES_TEMPLATE_v1.en.md`


## 0) R1 Validated Scope

The validated public release slice is limited to `XT-W3-23 -> XT-W3-24 -> XT-W3-25`.

Validated external statements for R1 are limited to:
- `XT memory UX adapter backed by Hub truth-source`
- `Hub-governed multi-channel gateway`
- `Hub-first governed automations`

Hard lines:
- `no_scope_expansion=true`
- `no_unverified_claims=true`
- public package stays `allowlist-first + fail-closed`
- `build/**`, `data/**`, `*.sqlite*`, `*kek*.json`, and other restricted artifacts remain excluded from public Git

## 0.1 Security Posture Note

The repository also documents a broader safety posture around Hub-side memory, X-Constitution guidance, and policy-engine enforcement.

That posture should be described as a Hub-side, memory-backed behavioral boundary reinforced by policy controls, audit, grants, and fail-closed execution. It is not a license to describe terminal-local prompt wording as if it were the trust boundary.

If release wording needs to mention memory control at all, keep it inside the frozen public boundary: the user chooses which AI executes memory jobs in X-Hub, `Memory-Core` stays a governed Hub-side rule asset rather than a normal plugin, and durable writes still terminate through `Writer + Gate`.

That material may be referenced in release notes as part of the system's security posture, but it must not be used to expand the validated public release slice beyond the three approved statements above.

## 0.2 Authority And Rust Migration Note

Release wording must distinguish:

- `production authority`
- `preview-working`
- `shadow`
- `candidate authority`
- `diagnostics-only`
- `roadmap`

The current product line is still primarily Swift XT plus Node Hub production authority. Rust Hub / `xhubd` may implement scheduler, provider route, model route, skills policy, memory read-only retrieval, daemon ops, or XT compatibility paths ahead of public release scope, but that implementation does not automatically promote Rust to production authority.

For public release notes:

- Do not claim Rust owns `HubAI.Generate`, memory writes, third-party skill execution, pairing trust, or XT product UI unless that path has an explicit release gate.
- Do not describe shadow compare, candidate audit, readiness reports, or dry-run authority plans as production behavior.
- Do mention Rust work as migration infrastructure only when evidence and package boundaries are included in the release.
- If Rust is included, state the authority mode explicitly, for example `diagnostics-only`, `shadow compare`, `default-off candidate bridge`, or `production authority`.
- Keep `docs/system/*` aligned with validated behavior before using those files as public release references.

Any production authority migration requires:

- default-off bridge or explicit opt-in
- shadow or candidate evidence
- sustained runner evidence where applicable
- readiness gate
- rollback path
- no-secret evidence
- compatibility check for existing Node/XT clients

## 1) Release Types

- `alpha`: early public release, fast iteration, no API stability guarantee.
- `beta`: feature-complete candidate, stability and migration notes expected.
- `stable`: production-grade release, strict backward-compatibility policy.

Recommended first public tag:
- `v0.1.0-alpha`

## 2) Pre-Release Checklist

Before tagging, all required gates must pass:
- `build/reports/oss_public_manifest_v1.json` exists and matches the allowlist-first public boundary
- `OSS-G0` Legal and attribution
- `OSS-G1` Secret and artifact scrub
- `OSS-G2` Reproducible quick start
- `OSS-G3` Security baseline
- `OSS-G4` Community readiness
- `OSS-G5` Release and rollback

If any required evidence is missing, decision must be:
- `NO-GO` or `INSUFFICIENT_EVIDENCE`

For releases that include Rust migration artifacts, also confirm:

- release notes name the exact Rust authority mode
- diagnostics-only or shadow paths are not presented as production behavior
- no runtime database, report bundle with secrets, launchd plist with local private paths, or access-key material is staged
- rollback leaves Node Hub and Swift XT production paths usable
- compatibility with existing public source-run commands is preserved

## 3) Recommended Preflight Commands

Run from repository root:

```bash
rg -n "BEGIN (RSA|EC|OPENSSH) PRIVATE KEY|api[_-]?key|secret|token|password" -S
rg --files | rg -n "(^|/)(build|data|\\.axcoder)(/|$)|\\.sqlite3$|\\.sqlite3-(shm|wal)$" -S
```

Confirm no forbidden runtime artifacts are staged.

If the release includes Rust daemon or migration artifacts, additionally inspect for local runtime artifacts, SQLite files, launchd plists, and generated reports before staging. These must remain out of public Git unless explicitly allowlisted and scrubbed.

Additional engineering validation for the in-progress unified doctor shell:

```bash
bash scripts/ci/xhub_doctor_source_gate.sh
```

Machine-readable supporting evidence produced by that gate:

- `build/reports/xhub_doctor_source_gate_summary.v1.json`
- `build/reports/xhub_doctor_xt_source_smoke_evidence.v1.json`
- `build/reports/xhub_doctor_all_source_smoke_evidence.v1.json`

For the current governed-skills preview surface, release-facing review may also reference these closure artifacts when checking whether the skills path is still only protocol-level or already has a working gate surface:

- `build/reports/w8_c1_starter_pack_baseline_evidence.v1.json`
- `build/reports/w8_c2_skill_surface_truth_evidence.v1.json`
- `build/reports/w8_c3_preflight_gate_evidence.v1.json`
- `build/reports/w8_c4_call_skill_retry_evidence.v1.json`

The gate summary now also carries `project_context_summary_support`, `heartbeat_governance_support`, `provider_key_selection_support`, `provider_key_route_context_support`, `durable_candidate_mirror_support`, and `memory_route_truth_support`, so release evidence can show that XT source-run export preserved the structured `session_runtime_readiness.project_context_summary`, `session_runtime_readiness.heartbeat_governance_snapshot`, `model_route_readiness.provider_key_selection_snapshot`, `model_route_readiness.provider_key_route_context_snapshot`, `session_runtime_readiness.durable_candidate_mirror_snapshot`, and `model_route_readiness.memory_route_truth_snapshot` rather than only reporting a green smoke status. The provider-key support block keeps `requested_provider / requested_model_id / selected_account_key / next_retry_at_ms` machine-readable for internal troubleshooting, while the route-context block keeps `model_id / import_issue_count / selected_account_key / primary_import_issue_ref` machine-readable for troubleshooting surface parity; both remain explainability only and do not upgrade release/support tooling into scheduler, import mutation, or auth authority.

The OSS refresh helper now also regenerates `build/reports/xhub_local_service_operator_recovery_report.v1.json` and `build/reports/xhub_operator_channel_recovery_report.v1.json`, so runtime/channel operator wording can reuse one machine-readable source instead of inventing separate diagnosis layers downstream.

For release/support operators who need a human-readable copy-paste surface, the same refresh helper now also writes `build/reports/oss_release_support_snippet.v1.md`. That markdown may carry preview-working operator-channel wording, but it must stay in the support/status lane and must not be promoted into validated release claims.

To refresh the OSS release evidence bundle after the upstream gates have produced their inputs:

```bash
bash scripts/refresh_oss_release_evidence.sh
```

CI workflow path for the same gate:

- `.github/workflows/xhub-doctor-source-gate.yml`

## 4) Version And Notes

1. Update `CHANGELOG.md`.
2. Confirm release scope and known limitations.
   - R1 wording must stay inside the validated release slice and the three approved statements.
   - If constitutional or memory-backed guardrails are mentioned, present them as system safety posture rather than as additional validated feature claims.
   - If Rust migration work is mentioned, state whether it is diagnostics-only, shadow, candidate, or production authority.
3. Prepare release notes with:
   - major changes
   - risk notes
   - rollback target

## 5) Tagging

Example:

```bash
git tag -a v0.1.0-alpha -m "v0.1.0-alpha"
git push origin v0.1.0-alpha
```

## 6) macOS Release Assets

Public users should download packaged builds from GitHub Releases. The repository should keep source, scripts, docs, and tests only; generated app bundles and DMGs stay out of Git.

Recommended assets for a macOS release:

```text
XHub-System-<version>-macos-arm64.dmg
X-Hub-<version>-macos-arm64.dmg
X-Terminal-<version>-macos-arm64.dmg
SHA256SUMS.txt
```

The combined `XHub-System` DMG is the primary user-facing package because it contains the native Swift `X-Hub.app` UI with the Rust Hub runtime embedded, plus `X-Terminal.app`. The separate `X-Hub` and `X-Terminal` DMGs are useful for partial updates and debugging.

The Rust daemon/status page is an internal runtime surface. It must not be the only Hub artifact in a public Rust preview release.

`scripts/package_macos_release.command` builds a fresh Rust Hub package from `rust/xhubd`, embeds it into `X-Hub.app`, builds `X-Terminal.app` plus the Rust `xtd` sidecar, then creates Hub, Terminal, and combined DMGs. If a release needs a separate daemon/runtime diagnostic bundle, publish it as an advanced/maintainer asset and keep the combined DMG as the primary user download.

Build release assets from the repository root:

```bash
XHUB_RELEASE_VERSION=v1.2.10 scripts/package_macos_release.command
```

The script writes assets to:

```text
build/release/<version>/
```

Upload those files to the matching GitHub Release. Do not commit `build/`, `.app`, or `.dmg` outputs.

If the apps are not signed with a Developer ID and notarized, mark the GitHub Release as a prerelease and state the signing status clearly in the release notes.

## 7) Rollback

Rollback must be documented in release notes and include:
- last known good tag
- impact scope
- operator steps
- validated release-slice rollback evidence: `build/reports/xt_w3_25_competitive_rollback.v1.json`

Minimal rollback example:

```bash
git checkout <last_known_good_tag>
```

## 8) Post-Release

- Announce release summary.
- Track first external feedback via issues.
- If critical issue appears, start hotfix branch and update changelog.
