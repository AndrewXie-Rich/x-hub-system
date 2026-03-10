# GitHub OSS Public Files & Paths v1 (`x-hub-system`)

- version: `v1.0`
- updated_at: `2026-03-02`
- owner: `Core Maintainers / Security / QA / Release`
- strategy: `allowlist-first + fail-closed`
- companion:
  - `docs/open-source/OSS_RELEASE_CHECKLIST_v1.md`
  - `docs/xhub-repo-structure-and-oss-plan-v1.md`

## 0) Goal

This document freezes the **public release scope** for the first GitHub release (recommended tag: `v0.1.0-alpha`).

Rules:
1. Define public scope with an allowlist first.
2. Enforce a hard denylist on top of allowlist scope.
3. If evidence is incomplete, release decision is `NO-GO`.

---

## 1) Public Allowlist (Directory-level recursive publish)

> Files under these paths are publishable by default, but still constrained by the denylist in Section 3.

- `.github/**`
- `.kiro/specs/**`
- `docs/**`
- `protocol/**`
- `scripts/**`
- `third_party/**`
- `x-hub/grpc-server/hub_grpc_server/**`
- `x-hub/macos/**`
- `x-hub/python-runtime/**`
- `x-hub/tools/**`
- `x-terminal/**`

---

## 2) Required Root Files (Exact paths)

### 2.1 Governance and compliance (required)

- `README.md`
- `LICENSE`
- `NOTICE.md`
- `SECURITY.md`
- `CONTRIBUTING.md`
- `CODE_OF_CONDUCT.md`
- `CODEOWNERS`
- `CHANGELOG.md`
- `RELEASE.md`
- `.gitignore`

### 2.2 Project navigation and status (recommended for first public release)

- `X_MEMORY.md`
- `docs/WORKING_INDEX.md`
- `docs/open-source/OSS_RELEASE_CHECKLIST_v1.md`
- `docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.md`
- `docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.en.md`

### 2.3 Utility scripts (public-safe)

- `check_hub_db.sh`
- `check_hub_status.sh`
- `check_report.sh`
- `check_supervisor_incident_db.sh`
- `run_supervisor_incident_db_probe.sh`
- `run_xt_ready_db_check.sh`
- `xt_ready_require_real_run.sh`
- `generate_xt_script.sh`

---

## 3) Hard Denylist (Must be excluded from public Git)

### 3.1 Runtime/build artifacts

- `build/**`
- `data/**`
- `**/.build/**`
- `**/.axcoder/**`
- `**/.scratch/**`
- `**/.sandbox_home/**`
- `**/.sandbox_tmp/**`
- `**/.clang-module-cache/**`
- `**/.swift-module-cache/**`
- `**/DerivedData/**`
- `**/node_modules/**`
- `**/__pycache__/**`

### 3.2 Local DB/log/sensitive files

- `**/*.sqlite`
- `**/*.sqlite3`
- `**/*.sqlite3-shm`
- `**/*.sqlite3-wal`
- `**/*.log`
- `**/.env`
- `**/*kek*.json`
- `**/*dek*.json`
- `**/*secret*`
- `**/*token*`
- `**/*password*`
- `**/*PRIVATE KEY*`

### 3.3 Binary/release artifacts

- `**/*.app`
- `**/*.dmg`
- `**/*.zip`
- `**/*.tar.gz`
- `**/*.tgz`
- `**/*.pkg`

### 3.4 Suggested deferrals for first release

- `x-terminal- legacy/**` (legacy implementation; archive separately later)
- `docs/legacy/**` (publish only after curation)
- root-level temporary status marker files (for example `conservative`, `in_progress）`)

---

## 4) Whitepaper and submodule policy

- Recommended submodule mount path: `docs/whitepaper/`
- If not mounted in v0.1.0-alpha, keep a stable whitepaper repo link in `README.md`.
- Keep whitepaper repo lifecycle decoupled from the main code repository.

---

## 5) Pre-release scan commands (recommended)

Run at repository root:

```bash
# 1) Sensitive keyword scan (any hit requires manual review)
rg -n "BEGIN (RSA|EC|OPENSSH) PRIVATE KEY|api[_-]?key|secret|token|password|kek|dek" -S

# 2) Denylist path scan (any hit is NO-GO)
rg --files | rg -n "(^|/)(build|data|\\.axcoder|\\.build|\\.sandbox_home|\\.sandbox_tmp|node_modules|DerivedData)(/|$)|\\.sqlite$|\\.sqlite3$|\\.sqlite3-(shm|wal)$|\\.dmg$|\\.app$|\\.zip$|\\.tar\\.gz$|\\.tgz$" -S

# 3) Candidate public file list for release review
find . -type f \
  -not -path "./build/*" \
  -not -path "./data/*" \
  -not -path "*/.build/*" \
  -not -path "*/.axcoder/*" \
  -not -path "*/.sandbox_home/*" \
  -not -path "*/.sandbox_tmp/*" \
  -not -path "*/node_modules/*" \
  -not -path "./x-terminal- legacy/*" \
  | sort
```

---

## 6) OSS recommendations (priority order)

1. **Ship a minimal runnable package first**: one Quick Start + one smoke flow; avoid release bloat.
2. **Freeze license boundaries**: keep only MIT-allowed vendoring in-repo; AGPL projects are links only.
3. **Evidence before claim**: every release gets a `GO|NO-GO|INSUFFICIENT_EVIDENCE` record.
4. **Fail-closed by default**: deny high-risk operations without valid grants.
5. **Single doc entry**: external contributors should onboard via `README.md -> docs/WORKING_INDEX.md -> target work-order`.
6. **Community-readiness first**: templates, CODEOWNERS, and security contact must be valid and monitored.
7. **Avoid legacy payload in first release**: split/archive legacy and temporary debug assets.
8. **Clear tag strategy**: `v0.1.0-alpha` (explore), `v0.2.0-beta` (stabilize), `v1.0.0` (compat commitment).

---

## 7) Release decision template (copy-paste)

```text
Scope:
- tag/commit: <...>

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
