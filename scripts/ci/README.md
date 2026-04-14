# Repo CI Scripts

`scripts/ci/` contains repo-wide CI-facing entrypoints for cross-surface validation.

These scripts are for repository-level gates that span more than one product surface.

## Most Important Entry Point

```bash
bash scripts/ci/xhub_doctor_source_gate.sh
```

This gate currently runs eight repo-level checks:

- wrapper dispatch tests for `scripts/run_xhub_doctor_from_source.command`
- focused build snapshot retention smoke
- focused Hub local-service snapshot smoke
- focused XT source-export smoke
- focused XT pairing-repair closure smoke
- focused XT memory-truth and canonical-sync-closure smoke
- aggregate Hub + XT source-export smoke
- build snapshot inventory report export

When the gate is green it writes:

- `build/reports/xhub_doctor_source_gate_summary.v1.json`
- `build/reports/xhub_doctor_hub_local_service_snapshot_smoke_evidence.v1.json`
- `build/reports/xhub_doctor_xt_source_smoke_evidence.v1.json`
- `build/reports/xhub_doctor_xt_pairing_repair_smoke_evidence.v1.json`
- `build/reports/xhub_doctor_xt_memory_truth_closure_smoke_evidence.v1.json`
- `build/reports/xhub_doctor_all_source_smoke_evidence.v1.json`
- `build/reports/build_snapshot_inventory.v1.json`

The summary report also includes `hub_local_service_snapshot_support`, `project_context_summary_support`, `project_memory_policy_support`, `project_memory_assembly_resolution_support`, `hub_memory_prompt_projection_support`, `project_remote_snapshot_cache_support`, `heartbeat_governance_support`, `supervisor_memory_policy_support`, `supervisor_memory_assembly_resolution_support`, `supervisor_remote_snapshot_cache_support`, `durable_candidate_mirror_support`, `local_store_write_support`, `xt_pairing_readiness_support`, `memory_route_truth_support`, `xt_pairing_repair_support`, `xt_memory_truth_closure_support`, and `build_snapshot_inventory_support`, so release/operator paths can consume structured Hub local-service failure truth, XT route/context truth, XT governance-review pressure truth, XT role-aware memory policy truth, XT Hub prompt-assembly truth, XT remote snapshot cache provenance, XT pairing-readiness truth, and local build snapshot disk hygiene truth without reverse-parsing human text. `project_context_summary_support` keeps `source_badge / status_line` together with the dialogue/depth metrics, `project_memory_policy_support` keeps configured/recommended/effective Project AI dialogue/context depth plus the A-tier memory ceiling, `project_memory_assembly_resolution_support` keeps the selected/excluded project serving objects and clamp result, `hub_memory_prompt_projection_support` keeps `projection_source / canonical_item_count / working_set_turn_count / runtime_truth_item_count / runtime_truth_source_kinds` for the latest Hub-backed prompt assembly without letting XT infer prompt contents locally, `project_remote_snapshot_cache_support` keeps `source / freshness / cache_hit / scope / cached_at_ms / age_ms / ttl_remaining_ms` for Project AI remote snapshot cache provenance, `heartbeat_governance_support` keeps `latest_quality_band / open_anomaly_types / review_pulse_effective_seconds / next_review_kind / next_review_due / digest_visibility / digest_reason_codes / project_memory_ready` for heartbeat-governed review explainability, cadence reasoning, user-noise suppression, and attached Project AI memory-readiness context, `supervisor_memory_policy_support` keeps configured/recommended/effective Supervisor recent-raw/review depth plus the S-tier review-memory ceiling, `supervisor_memory_assembly_resolution_support` keeps the selected/excluded Supervisor review assembly objects and clamp result, `supervisor_remote_snapshot_cache_support` keeps the same cache provenance fields for Supervisor review assembly, `durable_candidate_mirror_support` keeps `status / target / attempted / local_store_role` for XT supervisor handoff evidence, `local_store_write_support` keeps `personal_memory_intent / cross_link_intent / personal_review_intent` for XT-local cache/fallback/edit-buffer provenance, `xt_pairing_readiness_support` keeps `first_pair_completion_proof / paired_route_set` snapshots for same-LAN verification, cached reconnect confidence, and stable remote route explainability, `xt_pairing_repair_support` keeps `failure_code / mapped_issue / wizard_primary_action_id / settings_primary_action_id / doctor_headline` for the common pairing/discovery repair closures, `xt_memory_truth_closure_support` keeps the explainable source labels plus `audit_ref / evidence_ref / writeback_ref` closure for canonical sync failures, and `build_snapshot_inventory_support` keeps the current snapshot roots plus retention-based prune preview. `hub_memory_prompt_projection_support` remains Hub-first explainability only; it does not upgrade XT into prompt authority. These remote snapshot cache support blocks remain cache provenance only; they do not reclassify XT cache as durable truth or bypass Hub-first routing.

Low-disk guardrails:

- `scripts/smoke_xhub_doctor_all_source_export.sh` now fails early when the temp volume is below the default `2 GiB` floor. Override with `XHUB_DOCTOR_ALL_SOURCE_SMOKE_MIN_FREE_KB` for local retries.
- `scripts/smoke_xhub_doctor_xt_source_export.sh` now fails early when the temp volume is below the default `1.5 GiB` floor. Override with `XHUB_DOCTOR_XT_SOURCE_SMOKE_MIN_FREE_KB`.
- `scripts/smoke_xhub_doctor_hub_local_service_snapshot.sh` now fails early when the temp volume is below the default `1 GiB` floor. Override with `XHUB_DOCTOR_HUB_LOCAL_SERVICE_SMOKE_MIN_FREE_KB`.
- `scripts/ci/xhub_doctor_source_gate.sh` now only hydrates structured support blocks from evidence written by a passing step, so a failed smoke step no longer reuses stale evidence from an earlier run.

Build snapshot hygiene:

- `x-hub/tools/build_hub_app.command` prunes historical `build/.xhub-build-src-*` directories before recreating the current frozen source snapshot. Override the default retention of the newest `2` historical snapshots with `XHUB_BUILD_SNAPSHOT_RETENTION_COUNT`.
- `x-terminal/tools/build_xterminal_app.command` does the same for historical `build/.xterminal-build-src-*` directories. Override the default retention of the newest `2` historical snapshots with `XTERMINAL_BUILD_SNAPSHOT_RETENTION_COUNT`.
- The live snapshot roots remain `build/.xhub-build-src` and `build/.xterminal-build-src`; retention only targets timestamped historical siblings and leaves the current snapshot root alone.
- `bash scripts/smoke_build_snapshot_retention.sh` gives a focused regression check for the shared retention helper without running a full Hub or XT app build.
- `node scripts/generate_build_snapshot_inventory_report.js --out-json build/reports/build_snapshot_inventory.v1.json` exports the current snapshot roots, timestamped history siblings, and the retention-based prune preview so operators can see what the next local build would reclaim before deleting anything.

GitHub Actions entrypoints:

- `.github/workflows/xhub-doctor-source-gate.yml`
- `.github/workflows/xt-w3-24-safe-onboarding-gate.yml`

## Focused Work-Order Gate

```bash
bash scripts/ci/xt_w3_24_s_safe_onboarding_gate.sh
```

This focused gate packages the current `XT-W3-24-S` safe-onboarding release boundary into one rerunnable command. It currently runs:

- Hub live-test evidence repair-next-step regressions
- Hub admin HTTP onboarding evidence regression
- pairing preauth replay fail-closed regression
- RELFlowHub Swift onboarding evidence parity tests
- RELFlowHub model library section / usage description compile-parity regressions
- tracked evidence generator regression
- tracked release evidence packet refresh

When the gate is green it writes:

- `build/reports/xt_w3_24_s_safe_onboarding_gate_summary.v1.json`
- `build/reports/xt_w3_24_s_safe_onboarding_gate_logs/`
- `docs/open-source/evidence/xt_w3_24_s_safe_onboarding_release_evidence.v1.json`

## Boundary

- Keep terminal-only gates in `x-terminal/scripts/ci/`.
- Keep cross-surface source-run and release helpers in top-level `scripts/` and `scripts/ci/`.
