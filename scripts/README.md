# Repo Scripts

`scripts/` contains repository-level validation, packaging, reporting, and evidence-generation helpers.

These scripts are for cross-cutting repository workflows. They are not a replacement for Hub runtime code or terminal-local gates.

## What Lives Here

- Release-readiness checks
- Release evidence refresh helpers such as `scripts/refresh_oss_release_evidence.sh`, which now refreshes the legacy release compatibility pack, `build/reports/xhub_local_service_operator_recovery_report.v1.json`, `build/reports/xt_ready_release_diagnostics.v1.json`, and then the boundary/readiness bundle; the XT-ready preflight now accepts the preferred `require_real -> db_real -> current` evidence chain instead of hard-requiring only `build/xt_ready_gate_e2e_report.json`, and that same chain now covers the paired evidence-source plus connector-gate snapshot refs as well
- XT-ready capture helpers such as `scripts/m3_fetch_connector_ingress_gate_snapshot.js`, which now reuse `scripts/lib/xhub_local_admin_token.js` plus `scripts/resolve_xhub_local_admin_token.js` so encrypted local admin-token resolution follows the same `group.rel.flowhub` / `XHub|RELFlowHub` path policy as the live Hub and X-Terminal surfaces
- Hub pairing roundtrip smokes such as `scripts/smoke_xhub_background_pairing_roundtrip.sh`, which now support `auto`, `launch_only`, and `verify_only` modes so operators can either boot the packaged Hub in background mode without stealing focus or reuse an already-running Hub to verify the public pairing ingress plus admin pending-list/cleanup loop; the thin wrappers `scripts/smoke_xhub_background_launch_only.sh` and `scripts/smoke_xhub_pairing_roundtrip_verify_only.sh` expose the split phases directly and now default to separate report files under `build/reports/` so launch and verify evidence do not overwrite each other
- LPR require-real status helpers such as `scripts/lpr_w3_03_require_real_status.js`, which now collapse sample1 runtime/model/helper probes into a single `sample1_unblock_summary` and `sample1_operator_handoff` so operators can see both the preferred native-dir path and a fail-closed work order without hand-reading multiple reports
- LPR handoff generators such as `scripts/generate_lpr_w3_03_sample1_operator_handoff.js`, which persist the sample1 fail-closed work order into `build/reports/` and now carry compact acceptance/registration truth so downstream operator flows do not need to scrape multiple reports
- LPR candidate acceptance helpers such as `scripts/generate_lpr_w3_03_sample1_candidate_acceptance.js`, which turn the current machine truth plus sample contract into a hard accept/reject packet before an operator imports or validates a new embedding dir
- LPR helper local-service recovery helpers such as `scripts/generate_lpr_w3_03_sample1_helper_local_service_recovery.js`, which turn the LM Studio helper probe into a fail-closed secondary-route recovery packet with concrete enable-local-service steps, ready signals, and rerun commands
- LPR candidate registration helpers such as `scripts/generate_lpr_w3_03_sample1_candidate_registration_packet.js`, which normalize one exact candidate dir into a fail-closed import/register packet with a proposed catalog payload, target catalog paths, and exact validation commands without auto-writing any external catalog, and now embed a compact catalog patch plan summary so downstream operator flows can see when manual patch remains blocked
- LPR candidate catalog patch helpers such as `scripts/generate_lpr_w3_03_sample1_candidate_catalog_patch_plan.js`, which inspect the real `models_catalog.json` / `models_state.json` shapes in each target runtime base and produce a pair-safe manual patch plan without writing external files
- LPR sample1 bundle refresh helpers such as `scripts/refresh_lpr_w3_03_sample1_candidate_bundle.js`, which refresh shortlist, helper local-service recovery, exact-path validation, registration, operator handoff, acceptance, and require-real artifacts in one fail-closed sequence so operators do not have to remember the safe command order by hand
- LPR candidate shortlist helpers such as `scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js`, which flatten the default local scan roots including `~/.lmstudio/models`, `~/.cache/huggingface/hub`, `~/Library/Caches/huggingface/hub`, `~/Library/Application Support/LM Studio/models`, and `~/models` plus optional `--model-path/--scan-root` inputs into one ranked PASS/NO_GO shortlist, follow symlinked model directories during recursive discovery, and emit per-candidate validation artifacts
- LPR candidate validators such as `scripts/generate_lpr_w3_03_sample1_candidate_validation.js`, which let an operator hand one concrete model directory path to the repo and get an immediate `PASS/NO_GO` verdict for sample1 before touching the require-real bundle
- The require-real, operator recovery, product-exit, boundary, and OSS-readiness reports now carry the same sample1 `require_real_focus` / handoff truth upward, so release surfaces can show the real blocker and next action without re-parsing lower-level probe reports
- Human-readable release/support snippet generators such as `scripts/generate_oss_release_support_snippet.js`, which turn `build/reports/lpr_w4_09_c_product_exit_packet.v1.json` into a copy-paste-safe markdown handoff for release/support operators while explicitly keeping operator-channel wording in the preview/support lane rather than upgrading it into a validated release claim
- CI-facing repo-level entrypoints under `scripts/ci/`, such as `scripts/ci/xhub_doctor_source_gate.sh` and `scripts/ci/xt_w3_24_s_safe_onboarding_gate.sh`
- Recovery/report generators such as `scripts/generate_xhub_local_service_operator_recovery_report.js`
- Legacy release compatibility backfill such as `scripts/generate_release_legacy_compat_artifacts.js`, which recreates missing XT-W3 release-era artifact names from current source truth while preserving fail-closed semantics
- Product-exit aggregators such as `scripts/generate_lpr_w4_09_c_product_exit_packet.js`
- Export and reporting helpers
- Cross-surface source-run wrappers such as `run_xhub_doctor_from_source.command`, plus focused source-run smokes such as `smoke_xhub_doctor_xt_source_export.sh` and `smoke_xhub_doctor_all_source_export.sh`
- Build snapshot hygiene helpers such as `scripts/lib/build_snapshot_retention.sh` and the focused regression smoke `scripts/smoke_build_snapshot_retention.sh`, which keep timestamped `build/.xhub-build-src-*` / `build/.xterminal-build-src-*` snapshots from silently piling up across repeated local builds
- Build snapshot inventory generators such as `scripts/generate_build_snapshot_inventory_report.js`, which emit a machine-readable inventory of current frozen source snapshots, timestamped history siblings, and retention-based reclaim previews before anyone deletes local artifacts by hand
- Validation pipelines
- Evidence and traceability support scripts

## Why It Matters

This repository has active runtime surfaces, a validated release slice, and a large amount of machine-readable evidence.

The top-level `scripts/` directory is where repo-wide automation lives when it crosses module boundaries.

## Boundary

- Keep terminal-scoped gates in `x-terminal/scripts/`.
- Keep Hub packaging helpers in `x-hub/tools/`.
- Keep product/runtime logic in source trees, not in shell or report scripts.

## Read Next

- `scripts/ci/README.md`
- `x-terminal/scripts/README.md`
- `docs/WORKING_INDEX.md`
- `docs/open-source/OSS_RELEASE_CHECKLIST_v1.md`
