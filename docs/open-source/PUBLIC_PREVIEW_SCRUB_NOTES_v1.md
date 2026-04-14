# Public Preview Scrub Notes

This note is the current public-preview scrub recommendation for `x-hub-system`.

It is intentionally pragmatic:

- keep the active product and runtime surface public
- keep generated state, local-only probes, temporary notes, and host-specific scripts out
- keep the first public GitHub view readable instead of flooding it with internal execution debris

## Recommended Public Scope

High-confidence public paths for the first preview:

- `.github/`
- `README.md`
- `CHANGELOG.md`
- `CONTRIBUTING.md`
- `LICENSE`
- `NOTICE.md`
- `RELEASE.md`
- `SECURITY.md`
- `docs/REPO_LAYOUT.md`
- `docs/WORKING_INDEX.md`
- `docs/whitepaper-submodule.md`
- `docs/xhub-scenario-map-v1.md`
- `docs/open-source/`
- `protocol/`
- `specs/`
- `scripts/`
- `x-hub/`
- `x-terminal/`

## Hold Back In This Round

These files are not good first-public-preview material and should stay out of the initial GitHub presentation unless you explicitly want to publish internal execution context.

### Red: local-only or temporary

- `docs/_TEMP_STASH_2026-02-13.md`
- `archive/`
- local generated outputs under `build/`
- local generated outputs under `data/`
- `.DS_Store`

### Red: host-specific helper scripts with personal absolute paths

- `check_hub_db.sh`
- `check_hub_status.sh`
- `check_report.sh`
- `check_supervisor_incident_db.sh`
- `generate_xt_script.sh`
- `run_supervisor_incident_db_probe.sh`
- `run_xt_ready_db_check.sh`
- `xt_ready_require_real_run.sh`

These are useful locally, but they currently encode one-machine assumptions such as `/Users/andrew.xie/...` and local container paths.

### Yellow: internal operating memory / internal delivery material

- `X_MEMORY.md`
- `docs/memory-new/`
- `x-terminal/PHASE1_COMPLETION_RECORD.md`
- `x-terminal/PHASE2_COMPLETE.md`
- `x-terminal/PHASE2_PENDING_TASKS.md`
- `x-terminal/PHASE2_SUMMARY.md`
- `x-terminal/PHASE3_EXECUTIVE_SUMMARY.md`
- `x-terminal/PHASE3_PLAN.md`
- `x-terminal/PHASE3_PROGRESS.md`
- `x-terminal/PROJECT_STATUS.md`

These are not secret by default, but they read more like internal execution logs, milestone bookkeeping, and operating memory than public product docs.

If any of these memory-facing docs are later promoted into public product-facing material, rewrite their memory posture using the same public boundary: the user chooses which AI executes memory jobs in X-Hub, `Memory-Core` stays a governed Hub-side rule asset, and durable writes still terminate through `Writer + Gate`.

## Naming / Cleanup Debt To Be Aware Of

Not a hard blocker for publishing the preview, but still visible:

- residual `openclaw` naming remains in some work-orders, tests, and mode names
- residual `x-terminal-legacy` references remain in some docs and generators
- some large board / roadmap docs still contain local report paths or local runtime references

If the goal is a cleaner public first impression, scrub those next.

## Suggested Staging Command

This stages the core public-preview delta while intentionally excluding the main hold-back set above.

```bash
git add .gitignore .github README.md CHANGELOG.md CONTRIBUTING.md LICENSE NOTICE.md RELEASE.md SECURITY.md \
  docs/REPO_LAYOUT.md docs/WORKING_INDEX.md docs/whitepaper-submodule.md docs/xhub-scenario-map-v1.md docs/open-source \
  protocol specs scripts x-hub x-terminal \
  ':(exclude)docs/_TEMP_STASH_2026-02-13.md' \
  ':(exclude)docs/memory-new/**' \
  ':(exclude)check_hub_db.sh' \
  ':(exclude)check_hub_status.sh' \
  ':(exclude)check_report.sh' \
  ':(exclude)check_supervisor_incident_db.sh' \
  ':(exclude)generate_xt_script.sh' \
  ':(exclude)run_supervisor_incident_db_probe.sh' \
  ':(exclude)run_xt_ready_db_check.sh' \
  ':(exclude)xt_ready_require_real_run.sh' \
  ':(exclude)x-terminal/PHASE*.md' \
  ':(exclude)x-terminal/PROJECT_STATUS.md'
```

## Suggested Review Before Push

Run these before the public push:

```bash
git diff --cached --stat
git diff --cached --name-only
```

If you decide `X_MEMORY.md` should remain private for the first public preview, handle it separately instead of staging it implicitly.
