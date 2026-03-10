# OSS Release Checklist v1

- version: v1.0
- updatedAt: 2026-03-02
- owner: Core Maintainers / Security / QA / Release
- status: active
- scope: first public GitHub release for `x-hub-system`
- parent:
  - `README.md`
  - `SECURITY.md`
  - `CONTRIBUTING.md`
  - `docs/xhub-repo-structure-and-oss-plan-v1.md`
  - `docs/xhub-update-and-release-v1.md`
  - `docs/WORKING_INDEX.md`
  - `X_MEMORY.md`

## 0) Goal

Ship a public open-source release that is:
- legally clean
- secret-safe
- reproducible
- community-ready
- rollback-ready

This checklist is fail-closed: if required evidence is missing, release is `NO-GO`.

## 1) Release Profile

- recommended first public tag: `v0.1.0-alpha`
- required branch: protected release branch (for example `release/v0.1`)
- release decision states:
  - `GO`
  - `NO-GO`
  - `INSUFFICIENT_EVIDENCE`

## 2) Gate Matrix (must pass)

### OSS-G0 / Legal And Attribution

- [ ] `LICENSE` exists and matches intended license policy.
- [ ] `NOTICE.md` exists and includes third-party attribution policy.
- [ ] `SECURITY.md`, `CONTRIBUTING.md`, and `CODE_OF_CONDUCT.md` exist.
- [ ] Third-party license obligations are mapped for vendored components.

Evidence:
- `LICENSE`
- `NOTICE.md`
- `SECURITY.md`
- `CONTRIBUTING.md`
- `CODE_OF_CONDUCT.md`

DoD:
- legal review sign-off is recorded.

### OSS-G1 / Secret And Artifact Scrub

- [ ] No runtime secrets or private keys are committed.
- [ ] No local databases, private reports, or user content snapshots are committed.
- [ ] No local build outputs are committed.
- [ ] `.gitignore` covers data, build, and local runtime state.

Hard-block examples:
- `data/*.sqlite3`
- `data/*kek*.json`
- `build/**`
- `.axcoder/**`
- `.env` with real credentials

Evidence:
- scrub report file (recommended): `build/reports/oss_secret_scrub_report.v1.json`
- reviewer confirmation in release notes.

DoD:
- `high_risk_secret_findings = 0`
- `build_artifacts_committed = 0`

### OSS-G2 / Reproducible Quick Start

- [ ] README has a minimal "how to run" path.
- [ ] At least one smoke flow can be executed from docs.
- [ ] CI workflow exists and is green for release commit.

Evidence:
- `README.md`
- selected CI workflow reports

DoD:
- independent maintainer can reproduce quick start on clean machine.

### OSS-G3 / Security Baseline

- [ ] Fail-closed behavior is documented for high-risk actions.
- [ ] Security regression tests exist for critical invariants.
- [ ] Security response path (reporting and contact) is documented.

Evidence:
- `SECURITY.md`
- security workflow or test reports

DoD:
- known critical bypasses are closed or explicitly blocked from release.

### OSS-G4 / Community Readiness

- [ ] Issue templates are present (bug + feature).
- [ ] PR template is present.
- [ ] Maintainer ownership file exists (`CODEOWNERS` recommended).
- [ ] Basic roadmap/changelog is published.

Evidence:
- `.github/ISSUE_TEMPLATE/*`
- `.github/PULL_REQUEST_TEMPLATE.md`
- `CODEOWNERS`
- `CHANGELOG.md`

DoD:
- first external contributor can open issue/PR without hidden rules.

### OSS-G5 / Release And Rollback

- [ ] Release notes include scope, known limitations, and migration notes.
- [ ] Rollback procedure is documented.
- [ ] Tag strategy and branch strategy are documented.

Evidence:
- `CHANGELOG.md`
- `RELEASE.md` (or equivalent release runbook)

DoD:
- rollback can be executed within planned maintenance window.

## 3) Must-Exclude Paths For Public Repo

Minimum no-commit list for public release:
- `data/`
- `build/`
- `.axcoder/`
- `*.sqlite3`
- `*.sqlite3-shm`
- `*.sqlite3-wal`
- private key or secret files
- generated app bundles and local binaries

If history already contains sensitive files, perform history rewrite before publishing.

## 4) Preflight Commands (recommended)

Run these before creating a release candidate:

```bash
rg -n "BEGIN (RSA|EC|OPENSSH) PRIVATE KEY|api[_-]?key|secret|token|password" -S
rg --files | rg -n "(^|/)(build|data|\\.axcoder)(/|$)|\\.sqlite3$|\\.sqlite3-(shm|wal)$" -S
```

Optional: produce machine-readable summary report for release evidence.

## 5) Minimal Public Package (first release)

Must include:
- source code required for the documented quick start
- legal and security files
- docs needed to understand architecture and roadmap
- CI workflows required for public validation

Can be deferred to later releases:
- heavy local build products
- private operations scripts
- experimental modules that are not runnable in public setup

## 6) Release Evidence Bundle

Recommended files to attach to release approval:
- `build/reports/oss_release_readiness_v1.json`
- `build/reports/oss_secret_scrub_report.v1.json`
- CI run links or exported summaries
- final checklist decision (`GO|NO-GO|INSUFFICIENT_EVIDENCE`)

## 7) Decision Template

```text
Scope:
- <release tag and commit>

Gate:
- OSS-G0: PASS|FAIL
- OSS-G1: PASS|FAIL
- OSS-G2: PASS|FAIL
- OSS-G3: PASS|FAIL
- OSS-G4: PASS|FAIL
- OSS-G5: PASS|FAIL

Decision:
- GO|NO-GO|INSUFFICIENT_EVIDENCE

Top Risks:
- <risk 1>
- <risk 2>

Rollback:
- <rollback version/tag and steps>
```

## 8) Immediate TODOs Before First Public Tag

- [x] Add `CHANGELOG.md`
- [x] Add `RELEASE.md` (or `docs/release-checklist.md`)
- [x] Add issue templates and PR template under `.github/`
- [x] Add `CODEOWNERS`
- [x] Add `dependabot.yml` (recommended)
