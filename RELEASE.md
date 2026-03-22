# Release Guide

This document defines the minimum process for cutting a public release.

This guide is release-operations facing. Use `README.md` for the product narrative and validated public wording.

Repository license note:
- public messaging should describe this repository as open source under the MIT License
- keep trademark and validated-scope notes separate from the software-license statement

Primary gate source:
- `docs/open-source/OSS_RELEASE_CHECKLIST_v1.md`

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

## 3) Recommended Preflight Commands

Run from repository root:

```bash
rg -n "BEGIN (RSA|EC|OPENSSH) PRIVATE KEY|api[_-]?key|secret|token|password" -S
rg --files | rg -n "(^|/)(build|data|\\.axcoder)(/|$)|\\.sqlite3$|\\.sqlite3-(shm|wal)$" -S
```

Confirm no forbidden runtime artifacts are staged.

Additional engineering validation for the in-progress unified doctor shell:

```bash
bash scripts/ci/xhub_doctor_source_gate.sh
```

Machine-readable supporting evidence produced by that gate:

- `build/reports/xhub_doctor_source_gate_summary.v1.json`
- `build/reports/xhub_doctor_xt_source_smoke_evidence.v1.json`
- `build/reports/xhub_doctor_all_source_smoke_evidence.v1.json`

The gate summary now also carries `project_context_summary_support`, `durable_candidate_mirror_support`, and `memory_route_truth_support`, so release evidence can show that XT source-run export preserved the structured `session_runtime_readiness.project_context_summary`, `session_runtime_readiness.durable_candidate_mirror_snapshot`, and `model_route_readiness.memory_route_truth_snapshot` rather than only reporting a green smoke status.

The OSS refresh helper now also regenerates `build/reports/xhub_local_service_operator_recovery_report.v1.json`, so boundary/readiness reports can reuse the same machine-readable `action_category / external_status_line / top_recommended_action` instead of inventing a second wording layer.

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

## 6) Rollback

Rollback must be documented in release notes and include:
- last known good tag
- impact scope
- operator steps
- validated release-slice rollback evidence: `build/reports/xt_w3_25_competitive_rollback.v1.json`

Minimal rollback example:

```bash
git checkout <last_known_good_tag>
```

## 7) Post-Release

- Announce release summary.
- Track first external feedback via issues.
- If critical issue appears, start hotfix branch and update changelog.
