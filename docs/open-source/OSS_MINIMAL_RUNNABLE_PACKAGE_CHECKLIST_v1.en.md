# Minimal Runnable OSS Package Checklist v1 (`v0.1.0-alpha`)

- version: `v1.0`
- updated_at: `2026-03-02`
- owner: `Core Maintainers / Security / QA / Release`
- release_profile: `minimal-runnable-package`
- companion:
  - `docs/open-source/OSS_RELEASE_CHECKLIST_v1.md`
  - `docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.md`
  - `docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.en.md`

## 0) Scope

This checklist is for the first public release using a **small-first** strategy.  
Goal: **runnable, secure, evidence-backed**, not full historical exposure.

---

## 1) Scope Freeze (check first)

- [ ] Release tag is `v0.1.0-alpha`
- [ ] Release branch is frozen (for example `release/v0.1`)
- [ ] Allowlist policy is enforced via `docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.md`
- [ ] Explicit first-release deferrals are documented (`x-terminal- legacy/**`, heavy artifacts, private runtime state)

DoD:
- [ ] One machine-readable manifest is produced (recommended: `build/reports/oss_public_manifest_v1.json`)

---

## 2) Minimal Runnable Package Content (must include)

### 2.1 Governance and legal

- [ ] `README.md`
- [ ] `LICENSE`
- [ ] `NOTICE.md`
- [ ] `SECURITY.md`
- [ ] `CONTRIBUTING.md`
- [ ] `CODE_OF_CONDUCT.md`
- [ ] `CHANGELOG.md`
- [ ] `RELEASE.md`

### 2.2 Minimum runnable code

- [ ] `x-hub/grpc-server/hub_grpc_server/**` (server-side minimum flow)
- [ ] `protocol/**` (contract files)
- [ ] `scripts/**` (smoke/gate helper scripts)
- [ ] `x-terminal/**` (minimum public client capability)

### 2.3 Documentation entrypoints

- [ ] `docs/WORKING_INDEX.md`
- [ ] `X_MEMORY.md`
- [ ] `docs/open-source/OSS_RELEASE_CHECKLIST_v1.md`
- [ ] `docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.md`
- [ ] this checklist (CN/EN)

---

## 3) Mandatory Exclusions (any hit = NO-GO)

- [ ] no `build/**`
- [ ] no `data/**`
- [ ] no `**/.axcoder/**` and `**/.build/**`
- [ ] no `*.sqlite*`, `*.log`, `.env`, or key material
- [ ] no `*.app`, `*.dmg`, `*.zip`, or other binary release payloads
- [ ] no real keys, real accounts, real tokens, or real payment credentials

Recommended commands:

```bash
rg -n "BEGIN (RSA|EC|OPENSSH) PRIVATE KEY|api[_-]?key|secret|token|password|kek|dek" -S
rg --files | rg -n "(^|/)(build|data|\\.axcoder|\\.build|\\.sandbox_home|\\.sandbox_tmp|node_modules|DerivedData)(/|$)|\\.sqlite$|\\.sqlite3$|\\.sqlite3-(shm|wal)$|\\.dmg$|\\.app$|\\.zip$|\\.tar\\.gz$|\\.tgz$" -S
```

---

## 4) Minimal Runnable Validation (must pass)

### 4.1 Docs reproducibility

- [ ] README Quick Start runs successfully on a clean environment
- [ ] a second maintainer reproduces successfully on another machine

### 4.2 Smoke flow

- [ ] at least one core smoke flow passes (recommended: Hub health check + minimal request loop)
- [ ] failure is diagnosable (request_id/trace_id or equivalent audit key exists)

### 4.3 Gate baseline

- [ ] `OSS-G0` Legal: PASS
- [ ] `OSS-G1` Secret Scrub: PASS
- [ ] `OSS-G2` Reproducibility: PASS
- [ ] `OSS-G3` Security Baseline: PASS
- [ ] `OSS-G4` Community Readiness: PASS
- [ ] `OSS-G5` Release/Rollback: PASS

---

## 5) Release Notes and Rollback (required)

- [ ] release notes include scope, known limitations, and next milestones
- [ ] alpha status is explicitly stated (API may change)
- [ ] rollback path is validated (previous tag rollback works)
- [ ] release decision is recorded: `GO|NO-GO|INSUFFICIENT_EVIDENCE`

Recommended evidence files:
- `build/reports/oss_release_readiness_v1.json`
- `build/reports/oss_secret_scrub_report.v1.json`

---

## 6) Final Decision Template (copy-paste)

```text
Scope:
- tag/commit: <...>
- profile: minimal-runnable-package

Gate:
- OSS-G0 Legal: PASS|FAIL
- OSS-G1 Secret Scrub: PASS|FAIL
- OSS-G2 Reproducibility: PASS|FAIL
- OSS-G3 Security Baseline: PASS|FAIL
- OSS-G4 Community Readiness: PASS|FAIL
- OSS-G5 Release/Rollback: PASS|FAIL

Decision:
- GO|NO-GO|INSUFFICIENT_EVIDENCE

Top Risks:
- <risk 1>
- <risk 2>

Rollback:
- <tag / branch / steps>
```

---

## 7) Suggested Release Cadence (first public drop)

1. Day 1: scope freeze + secret scrub + legal check  
2. Day 2: Quick Start reproduction + smoke + Gate summary  
3. Day 3: release notes + decision + tag `v0.1.0-alpha`
