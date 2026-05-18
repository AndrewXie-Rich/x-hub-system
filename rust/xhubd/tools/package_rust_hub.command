#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo not found. Install Rust toolchain before packaging Rust Hub." >&2
  exit 127
fi

cd "$ROOT_DIR"
cargo build --release -p xhubd

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DIST_DIR="$ROOT_DIR/dist/rust-hub-$STAMP"
mkdir -p "$DIST_DIR/bin" "$DIST_DIR/config" "$DIST_DIR/assets/proto" "$DIST_DIR/migrations" "$DIST_DIR/tools" "$DIST_DIR/docs" "$DIST_DIR/skills"

cp "$ROOT_DIR/target/release/xhubd" "$DIST_DIR/bin/xhubd"
cp "$ROOT_DIR/README.md" "$DIST_DIR/README.md"
cp "$ROOT_DIR/config/default.toml" "$DIST_DIR/config/default.toml"
cp "$ROOT_DIR"/config/daemon_profile*.json "$DIST_DIR/config/"
cp "$ROOT_DIR/assets/proto/hub_protocol_v1.proto" "$DIST_DIR/assets/proto/hub_protocol_v1.proto"
cp "$ROOT_DIR"/migrations/*.sql "$DIST_DIR/migrations/"
cp "$ROOT_DIR"/docs/*.md "$DIST_DIR/docs/"
cp -R "$ROOT_DIR"/skills/. "$DIST_DIR/skills/"
cp "$ROOT_DIR/tools/run_packaged_rust_hub.command" "$DIST_DIR/tools/run_rust_hub.command"
cp "$ROOT_DIR/tools/xhubd_daemon.js" "$DIST_DIR/tools/xhubd_daemon.js"
cp "$ROOT_DIR/tools/xhubd_daemon.command" "$DIST_DIR/tools/xhubd_daemon.command"
cp "$ROOT_DIR/tools/daemon_ops_report.command" "$DIST_DIR/tools/daemon_ops_report.command"
cp "$ROOT_DIR/tools/daemon_ops_gate.command" "$DIST_DIR/tools/daemon_ops_gate.command"
cp "$ROOT_DIR/tools/daemon_maintenance.command" "$DIST_DIR/tools/daemon_maintenance.command"
cp "$ROOT_DIR/tools/daemon_watchdog.command" "$DIST_DIR/tools/daemon_watchdog.command"
cp "$ROOT_DIR/tools/cross_network_readiness_gate.command" "$DIST_DIR/tools/cross_network_readiness_gate.command"
cp "$ROOT_DIR/tools/cross_network_installed_gate.command" "$DIST_DIR/tools/cross_network_installed_gate.command"
cp "$ROOT_DIR/tools/cross_network_install_plan.command" "$DIST_DIR/tools/cross_network_install_plan.command"
cp "$ROOT_DIR/tools/cross_network_pairing_export.command" "$DIST_DIR/tools/cross_network_pairing_export.command"
cp "$ROOT_DIR/tools/cross_network_remote_route_gate.js" "$DIST_DIR/tools/cross_network_remote_route_gate.js"
cp "$ROOT_DIR/tools/cross_network_remote_route_gate.command" "$DIST_DIR/tools/cross_network_remote_route_gate.command"
cp "$ROOT_DIR/tools/cross_network_remote_route_doctor.js" "$DIST_DIR/tools/cross_network_remote_route_doctor.js"
cp "$ROOT_DIR/tools/cross_network_remote_route_doctor.command" "$DIST_DIR/tools/cross_network_remote_route_doctor.command"
cp "$ROOT_DIR/tools/cross_network_provider_candidate_plan.js" "$DIST_DIR/tools/cross_network_provider_candidate_plan.js"
cp "$ROOT_DIR/tools/cross_network_provider_candidate_plan.command" "$DIST_DIR/tools/cross_network_provider_candidate_plan.command"
cp "$ROOT_DIR/tools/cross_network_domain_readiness_bundle.js" "$DIST_DIR/tools/cross_network_domain_readiness_bundle.js"
cp "$ROOT_DIR/tools/cross_network_domain_readiness_bundle.command" "$DIST_DIR/tools/cross_network_domain_readiness_bundle.command"
cp "$ROOT_DIR/tools/cross_network_domain_activation_plan.js" "$DIST_DIR/tools/cross_network_domain_activation_plan.js"
cp "$ROOT_DIR/tools/cross_network_domain_activation_plan.command" "$DIST_DIR/tools/cross_network_domain_activation_plan.command"
cp "$ROOT_DIR/tools/cross_network_domain_smoke.js" "$DIST_DIR/tools/cross_network_domain_smoke.js"
cp "$ROOT_DIR/tools/cross_network_domain_smoke.command" "$DIST_DIR/tools/cross_network_domain_smoke.command"
cp "$ROOT_DIR/tools/lan_access_key_launchd_smoke.js" "$DIST_DIR/tools/lan_access_key_launchd_smoke.js"
cp "$ROOT_DIR/tools/lan_access_key_launchd_smoke.command" "$DIST_DIR/tools/lan_access_key_launchd_smoke.command"
cp "$ROOT_DIR/tools/memory_retrieval_shadow_smoke.js" "$DIST_DIR/tools/memory_retrieval_shadow_smoke.js"
cp "$ROOT_DIR/tools/memory_retrieval_shadow_smoke.command" "$DIST_DIR/tools/memory_retrieval_shadow_smoke.command"
cp "$ROOT_DIR/tools/memory_retrieval_http_smoke.js" "$DIST_DIR/tools/memory_retrieval_http_smoke.js"
cp "$ROOT_DIR/tools/memory_retrieval_http_smoke.command" "$DIST_DIR/tools/memory_retrieval_http_smoke.command"
cp "$ROOT_DIR/tools/memory_skills_production_smoke.js" "$DIST_DIR/tools/memory_skills_production_smoke.js"
cp "$ROOT_DIR/tools/memory_skills_production_smoke.command" "$DIST_DIR/tools/memory_skills_production_smoke.command"
cp "$ROOT_DIR/tools/memory_skills_live_smoke.js" "$DIST_DIR/tools/memory_skills_live_smoke.js"
cp "$ROOT_DIR/tools/memory_skills_live_smoke.command" "$DIST_DIR/tools/memory_skills_live_smoke.command"
cp "$ROOT_DIR/tools/local_ml_execution_smoke.js" "$DIST_DIR/tools/local_ml_execution_smoke.js"
cp "$ROOT_DIR/tools/local_ml_execution_smoke.command" "$DIST_DIR/tools/local_ml_execution_smoke.command"
cp "$ROOT_DIR/tools/skills_catalog_shadow_smoke.js" "$DIST_DIR/tools/skills_catalog_shadow_smoke.js"
cp "$ROOT_DIR/tools/skills_catalog_shadow_smoke.command" "$DIST_DIR/tools/skills_catalog_shadow_smoke.command"
cp "$ROOT_DIR/tools/skills_catalog_http_smoke.js" "$DIST_DIR/tools/skills_catalog_http_smoke.js"
cp "$ROOT_DIR/tools/skills_catalog_http_smoke.command" "$DIST_DIR/tools/skills_catalog_http_smoke.command"
cp "$ROOT_DIR/tools/xt_file_ipc_watcher_run_once_smoke.js" "$DIST_DIR/tools/xt_file_ipc_watcher_run_once_smoke.js"
cp "$ROOT_DIR/tools/xt_file_ipc_watcher_run_once_smoke.command" "$DIST_DIR/tools/xt_file_ipc_watcher_run_once_smoke.command"
cp "$ROOT_DIR/tools/xt_file_ipc_background_watcher_smoke.js" "$DIST_DIR/tools/xt_file_ipc_background_watcher_smoke.js"
cp "$ROOT_DIR/tools/xt_file_ipc_background_watcher_smoke.command" "$DIST_DIR/tools/xt_file_ipc_background_watcher_smoke.command"
cp "$ROOT_DIR/tools/xt_file_ipc_runtime_execution_plan_smoke.js" "$DIST_DIR/tools/xt_file_ipc_runtime_execution_plan_smoke.js"
cp "$ROOT_DIR/tools/xt_file_ipc_runtime_execution_plan_smoke.command" "$DIST_DIR/tools/xt_file_ipc_runtime_execution_plan_smoke.command"
cp "$ROOT_DIR/tools/xt_file_ipc_runtime_adapter_candidate_smoke.js" "$DIST_DIR/tools/xt_file_ipc_runtime_adapter_candidate_smoke.js"
cp "$ROOT_DIR/tools/xt_file_ipc_runtime_adapter_candidate_smoke.command" "$DIST_DIR/tools/xt_file_ipc_runtime_adapter_candidate_smoke.command"
cp "$ROOT_DIR/tools/xt_file_ipc_prep_session.js" "$DIST_DIR/tools/xt_file_ipc_prep_session.js"
cp "$ROOT_DIR/tools/xt_file_ipc_prep_session.command" "$DIST_DIR/tools/xt_file_ipc_prep_session.command"
cp "$ROOT_DIR/tools/xt_file_ipc_production_session.js" "$DIST_DIR/tools/xt_file_ipc_production_session.js"
cp "$ROOT_DIR/tools/xt_file_ipc_production_session.command" "$DIST_DIR/tools/xt_file_ipc_production_session.command"
cp "$ROOT_DIR/tools/xt_file_ipc_production_cutover_blocker.js" "$DIST_DIR/tools/xt_file_ipc_production_cutover_blocker.js"
cp "$ROOT_DIR/tools/xt_file_ipc_production_cutover_blocker.command" "$DIST_DIR/tools/xt_file_ipc_production_cutover_blocker.command"
cp "$ROOT_DIR/tools/xt_file_ipc_production_rollback_rehearsal.js" "$DIST_DIR/tools/xt_file_ipc_production_rollback_rehearsal.js"
cp "$ROOT_DIR/tools/xt_file_ipc_production_rollback_rehearsal.command" "$DIST_DIR/tools/xt_file_ipc_production_rollback_rehearsal.command"
cp "$ROOT_DIR/tools/xt_file_ipc_live_cutover_preflight.js" "$DIST_DIR/tools/xt_file_ipc_live_cutover_preflight.js"
cp "$ROOT_DIR/tools/xt_file_ipc_live_cutover_preflight.command" "$DIST_DIR/tools/xt_file_ipc_live_cutover_preflight.command"
cp "$ROOT_DIR/tools/xt_file_ipc_live_heartbeat_soak.js" "$DIST_DIR/tools/xt_file_ipc_live_heartbeat_soak.js"
cp "$ROOT_DIR/tools/xt_file_ipc_live_heartbeat_soak.command" "$DIST_DIR/tools/xt_file_ipc_live_heartbeat_soak.command"
cp "$ROOT_DIR/tools/production_live_stability_gate.js" "$DIST_DIR/tools/production_live_stability_gate.js"
cp "$ROOT_DIR/tools/production_live_stability_gate.command" "$DIST_DIR/tools/production_live_stability_gate.command"
cp "$ROOT_DIR/tools/production_live_stability_session.js" "$DIST_DIR/tools/production_live_stability_session.js"
cp "$ROOT_DIR/tools/production_live_stability_session.command" "$DIST_DIR/tools/production_live_stability_session.command"
cp "$ROOT_DIR/tools/ui_compatibility_no_product_ui_change_gate.js" "$DIST_DIR/tools/ui_compatibility_no_product_ui_change_gate.js"
cp "$ROOT_DIR/tools/ui_compatibility_no_product_ui_change_gate.command" "$DIST_DIR/tools/ui_compatibility_no_product_ui_change_gate.command"
cp "$ROOT_DIR/tools/ops_readiness_gate.js" "$DIST_DIR/tools/ops_readiness_gate.js"
cp "$ROOT_DIR/tools/ops_readiness_gate.command" "$DIST_DIR/tools/ops_readiness_gate.command"
cp "$ROOT_DIR/tools/ops_soak_runner.js" "$DIST_DIR/tools/ops_soak_runner.js"
cp "$ROOT_DIR/tools/ops_soak_runner.command" "$DIST_DIR/tools/ops_soak_runner.command"
cp "$ROOT_DIR/tools/node_scheduler_shadow_compare.js" "$DIST_DIR/tools/node_scheduler_shadow_compare.js"
cp "$ROOT_DIR/tools/node_scheduler_shadow_compare.command" "$DIST_DIR/tools/node_scheduler_shadow_compare.command"
cp "$ROOT_DIR/tools/node_hub_shadow_compare_smoke.js" "$DIST_DIR/tools/node_hub_shadow_compare_smoke.js"
cp "$ROOT_DIR/tools/node_hub_shadow_compare_smoke.command" "$DIST_DIR/tools/node_hub_shadow_compare_smoke.command"
cp "$ROOT_DIR/tools/node_hub_shadow_compare_runner.js" "$DIST_DIR/tools/node_hub_shadow_compare_runner.js"
cp "$ROOT_DIR/tools/node_hub_shadow_compare_runner.command" "$DIST_DIR/tools/node_hub_shadow_compare_runner.command"
cp "$ROOT_DIR/tools/node_hub_authority_live_runner.js" "$DIST_DIR/tools/node_hub_authority_live_runner.js"
cp "$ROOT_DIR/tools/node_hub_authority_live_runner.command" "$DIST_DIR/tools/node_hub_authority_live_runner.command"
cp "$ROOT_DIR/tools/scheduler_cutover_readiness_runner.js" "$DIST_DIR/tools/scheduler_cutover_readiness_runner.js"
cp "$ROOT_DIR/tools/scheduler_cutover_readiness_runner.command" "$DIST_DIR/tools/scheduler_cutover_readiness_runner.command"
cp "$ROOT_DIR/tools/scheduler_authority_runner.js" "$DIST_DIR/tools/scheduler_authority_runner.js"
cp "$ROOT_DIR/tools/scheduler_authority_runner.command" "$DIST_DIR/tools/scheduler_authority_runner.command"
cp "$ROOT_DIR/tools/scheduler_production_authority_plan.js" "$DIST_DIR/tools/scheduler_production_authority_plan.js"
cp "$ROOT_DIR/tools/scheduler_production_authority_plan.command" "$DIST_DIR/tools/scheduler_production_authority_plan.command"
cp "$ROOT_DIR/tools/scheduler_production_authority_apply.js" "$DIST_DIR/tools/scheduler_production_authority_apply.js"
cp "$ROOT_DIR/tools/scheduler_production_authority_apply.command" "$DIST_DIR/tools/scheduler_production_authority_apply.command"
cp "$ROOT_DIR/tools/scheduler_production_authority_session.js" "$DIST_DIR/tools/scheduler_production_authority_session.js"
cp "$ROOT_DIR/tools/scheduler_production_authority_session.command" "$DIST_DIR/tools/scheduler_production_authority_session.command"
cp "$ROOT_DIR/tools/scheduler_production_authority_session_launchd.js" "$DIST_DIR/tools/scheduler_production_authority_session_launchd.js"
cp "$ROOT_DIR/tools/scheduler_production_authority_session_launchd.command" "$DIST_DIR/tools/scheduler_production_authority_session_launchd.command"
cp "$ROOT_DIR/tools/scheduler_production_authority_guard.js" "$DIST_DIR/tools/scheduler_production_authority_guard.js"
cp "$ROOT_DIR/tools/scheduler_production_authority_guard.command" "$DIST_DIR/tools/scheduler_production_authority_guard.command"
cp "$ROOT_DIR/tools/route_authority_cutover_guard.js" "$DIST_DIR/tools/route_authority_cutover_guard.js"
cp "$ROOT_DIR/tools/route_authority_cutover_guard.command" "$DIST_DIR/tools/route_authority_cutover_guard.command"
cp "$ROOT_DIR/tools/route_authority_prep_session.js" "$DIST_DIR/tools/route_authority_prep_session.js"
cp "$ROOT_DIR/tools/route_authority_prep_session.command" "$DIST_DIR/tools/route_authority_prep_session.command"
cp "$ROOT_DIR/tools/route_authority_prep_runtime_guard.js" "$DIST_DIR/tools/route_authority_prep_runtime_guard.js"
cp "$ROOT_DIR/tools/route_authority_prep_runtime_guard.command" "$DIST_DIR/tools/route_authority_prep_runtime_guard.command"
cp "$ROOT_DIR/tools/route_authority_prep_sustained_guard.js" "$DIST_DIR/tools/route_authority_prep_sustained_guard.js"
cp "$ROOT_DIR/tools/route_authority_prep_sustained_guard.command" "$DIST_DIR/tools/route_authority_prep_sustained_guard.command"
cp "$ROOT_DIR/tools/route_authority_prep_session_launchd.js" "$DIST_DIR/tools/route_authority_prep_session_launchd.js"
cp "$ROOT_DIR/tools/route_authority_prep_session_launchd.command" "$DIST_DIR/tools/route_authority_prep_session_launchd.command"
cp "$ROOT_DIR/tools/route_authority_production_cutover_blocker.js" "$DIST_DIR/tools/route_authority_production_cutover_blocker.js"
cp "$ROOT_DIR/tools/route_authority_production_cutover_blocker.command" "$DIST_DIR/tools/route_authority_production_cutover_blocker.command"
cp "$ROOT_DIR/tools/route_authority_production_session.js" "$DIST_DIR/tools/route_authority_production_session.js"
cp "$ROOT_DIR/tools/route_authority_production_session.command" "$DIST_DIR/tools/route_authority_production_session.command"
cp "$ROOT_DIR/tools/route_authority_production_runtime_guard.js" "$DIST_DIR/tools/route_authority_production_runtime_guard.js"
cp "$ROOT_DIR/tools/route_authority_production_runtime_guard.command" "$DIST_DIR/tools/route_authority_production_runtime_guard.command"
cp "$ROOT_DIR/tools/active_root_upgrade_plan.js" "$DIST_DIR/tools/active_root_upgrade_plan.js"
cp "$ROOT_DIR/tools/active_root_upgrade_plan.command" "$DIST_DIR/tools/active_root_upgrade_plan.command"
cp "$ROOT_DIR/tools/active_root_upgrade_apply.js" "$DIST_DIR/tools/active_root_upgrade_apply.js"
cp "$ROOT_DIR/tools/active_root_upgrade_apply.command" "$DIST_DIR/tools/active_root_upgrade_apply.command"
cp "$ROOT_DIR/tools/scheduler_status_http_bridge_smoke.js" "$DIST_DIR/tools/scheduler_status_http_bridge_smoke.js"
cp "$ROOT_DIR/tools/scheduler_status_http_bridge_smoke.command" "$DIST_DIR/tools/scheduler_status_http_bridge_smoke.command"
cp "$ROOT_DIR/tools/scheduler_lease_shadow_http_bridge_smoke.js" "$DIST_DIR/tools/scheduler_lease_shadow_http_bridge_smoke.js"
cp "$ROOT_DIR/tools/scheduler_lease_shadow_http_bridge_smoke.command" "$DIST_DIR/tools/scheduler_lease_shadow_http_bridge_smoke.command"
cp "$ROOT_DIR/tools/scheduler_authority_http_bridge_smoke.js" "$DIST_DIR/tools/scheduler_authority_http_bridge_smoke.js"
cp "$ROOT_DIR/tools/scheduler_authority_http_bridge_smoke.command" "$DIST_DIR/tools/scheduler_authority_http_bridge_smoke.command"
cp "$ROOT_DIR/tools/provider_route_smoke.command" "$DIST_DIR/tools/provider_route_smoke.command"
cp "$ROOT_DIR/tools/provider_route_http_smoke.command" "$DIST_DIR/tools/provider_route_http_smoke.command"
cp "$ROOT_DIR/tools/provider_route_http_bridge_smoke.js" "$DIST_DIR/tools/provider_route_http_bridge_smoke.js"
cp "$ROOT_DIR/tools/provider_route_http_bridge_smoke.command" "$DIST_DIR/tools/provider_route_http_bridge_smoke.command"
cp "$ROOT_DIR/tools/provider_route_http_shadow_compare_smoke.js" "$DIST_DIR/tools/provider_route_http_shadow_compare_smoke.js"
cp "$ROOT_DIR/tools/provider_route_http_shadow_compare_smoke.command" "$DIST_DIR/tools/provider_route_http_shadow_compare_smoke.command"
cp "$ROOT_DIR/tools/provider_route_shadow_compare_smoke.js" "$DIST_DIR/tools/provider_route_shadow_compare_smoke.js"
cp "$ROOT_DIR/tools/provider_route_shadow_compare_smoke.command" "$DIST_DIR/tools/provider_route_shadow_compare_smoke.command"
cp "$ROOT_DIR/tools/model_inventory_shadow_compare_smoke.js" "$DIST_DIR/tools/model_inventory_shadow_compare_smoke.js"
cp "$ROOT_DIR/tools/model_inventory_shadow_compare_smoke.command" "$DIST_DIR/tools/model_inventory_shadow_compare_smoke.command"
cp "$ROOT_DIR/tools/model_inventory_shadow_compare_runner.js" "$DIST_DIR/tools/model_inventory_shadow_compare_runner.js"
cp "$ROOT_DIR/tools/model_inventory_shadow_compare_runner.command" "$DIST_DIR/tools/model_inventory_shadow_compare_runner.command"
cp "$ROOT_DIR/tools/model_inventory_http_bridge_smoke.js" "$DIST_DIR/tools/model_inventory_http_bridge_smoke.js"
cp "$ROOT_DIR/tools/model_inventory_http_bridge_smoke.command" "$DIST_DIR/tools/model_inventory_http_bridge_smoke.command"
cp "$ROOT_DIR/tools/model_route_http_smoke.js" "$DIST_DIR/tools/model_route_http_smoke.js"
cp "$ROOT_DIR/tools/model_route_http_smoke.command" "$DIST_DIR/tools/model_route_http_smoke.command"
cp "$ROOT_DIR/tools/model_route_generate_candidate_runner.js" "$DIST_DIR/tools/model_route_generate_candidate_runner.js"
cp "$ROOT_DIR/tools/model_route_generate_candidate_runner.command" "$DIST_DIR/tools/model_route_generate_candidate_runner.command"
cp "$ROOT_DIR/tools/model_route_local_candidate_runner.js" "$DIST_DIR/tools/model_route_local_candidate_runner.js"
cp "$ROOT_DIR/tools/model_route_local_candidate_runner.command" "$DIST_DIR/tools/model_route_local_candidate_runner.command"
cp "$ROOT_DIR/tools/model_route_candidate_evidence_runner.js" "$DIST_DIR/tools/model_route_candidate_evidence_runner.js"
cp "$ROOT_DIR/tools/model_route_candidate_evidence_runner.command" "$DIST_DIR/tools/model_route_candidate_evidence_runner.command"
cp "$ROOT_DIR/tools/model_route_authority_plan_runner.js" "$DIST_DIR/tools/model_route_authority_plan_runner.js"
cp "$ROOT_DIR/tools/model_route_authority_plan_runner.command" "$DIST_DIR/tools/model_route_authority_plan_runner.command"
cp "$ROOT_DIR/tools/model_route_prep_trial_runner.js" "$DIST_DIR/tools/model_route_prep_trial_runner.js"
cp "$ROOT_DIR/tools/model_route_prep_trial_runner.command" "$DIST_DIR/tools/model_route_prep_trial_runner.command"
cp "$ROOT_DIR/tools/model_route_prep_sustained_runner.js" "$DIST_DIR/tools/model_route_prep_sustained_runner.js"
cp "$ROOT_DIR/tools/model_route_prep_sustained_runner.command" "$DIST_DIR/tools/model_route_prep_sustained_runner.command"
cp "$ROOT_DIR/tools/provider_route_shadow_compare_runner.js" "$DIST_DIR/tools/provider_route_shadow_compare_runner.js"
cp "$ROOT_DIR/tools/provider_route_shadow_compare_runner.command" "$DIST_DIR/tools/provider_route_shadow_compare_runner.command"
cp "$ROOT_DIR/tools/provider_route_generate_observe_runner.js" "$DIST_DIR/tools/provider_route_generate_observe_runner.js"
cp "$ROOT_DIR/tools/provider_route_generate_observe_runner.command" "$DIST_DIR/tools/provider_route_generate_observe_runner.command"
cp "$ROOT_DIR/tools/provider_route_cutover_readiness_runner.js" "$DIST_DIR/tools/provider_route_cutover_readiness_runner.js"
cp "$ROOT_DIR/tools/provider_route_cutover_readiness_runner.command" "$DIST_DIR/tools/provider_route_cutover_readiness_runner.command"
cp "$ROOT_DIR/tools/provider_route_authority_plan_runner.js" "$DIST_DIR/tools/provider_route_authority_plan_runner.js"
cp "$ROOT_DIR/tools/provider_route_authority_plan_runner.command" "$DIST_DIR/tools/provider_route_authority_plan_runner.command"
chmod +x "$DIST_DIR/tools/run_rust_hub.command" \
  "$DIST_DIR/tools/xhubd_daemon.js" \
  "$DIST_DIR/tools/xhubd_daemon.command" \
  "$DIST_DIR/tools/daemon_ops_report.command" \
  "$DIST_DIR/tools/daemon_ops_gate.command" \
  "$DIST_DIR/tools/daemon_maintenance.command" \
  "$DIST_DIR/tools/daemon_watchdog.command" \
  "$DIST_DIR/tools/cross_network_readiness_gate.command" \
  "$DIST_DIR/tools/cross_network_installed_gate.command" \
  "$DIST_DIR/tools/cross_network_install_plan.command" \
  "$DIST_DIR/tools/cross_network_pairing_export.command" \
  "$DIST_DIR/tools/cross_network_remote_route_gate.js" \
  "$DIST_DIR/tools/cross_network_remote_route_gate.command" \
  "$DIST_DIR/tools/cross_network_remote_route_doctor.js" \
  "$DIST_DIR/tools/cross_network_remote_route_doctor.command" \
  "$DIST_DIR/tools/cross_network_provider_candidate_plan.js" \
  "$DIST_DIR/tools/cross_network_provider_candidate_plan.command" \
  "$DIST_DIR/tools/cross_network_domain_readiness_bundle.js" \
  "$DIST_DIR/tools/cross_network_domain_readiness_bundle.command" \
  "$DIST_DIR/tools/cross_network_domain_activation_plan.js" \
  "$DIST_DIR/tools/cross_network_domain_activation_plan.command" \
  "$DIST_DIR/tools/cross_network_domain_smoke.js" \
  "$DIST_DIR/tools/cross_network_domain_smoke.command" \
  "$DIST_DIR/tools/lan_access_key_launchd_smoke.js" \
  "$DIST_DIR/tools/lan_access_key_launchd_smoke.command" \
  "$DIST_DIR/tools/memory_retrieval_shadow_smoke.js" \
  "$DIST_DIR/tools/memory_retrieval_shadow_smoke.command" \
  "$DIST_DIR/tools/memory_retrieval_http_smoke.js" \
  "$DIST_DIR/tools/memory_retrieval_http_smoke.command" \
  "$DIST_DIR/tools/memory_skills_production_smoke.js" \
  "$DIST_DIR/tools/memory_skills_production_smoke.command" \
  "$DIST_DIR/tools/memory_skills_live_smoke.js" \
  "$DIST_DIR/tools/memory_skills_live_smoke.command" \
  "$DIST_DIR/tools/local_ml_execution_smoke.js" \
  "$DIST_DIR/tools/local_ml_execution_smoke.command" \
  "$DIST_DIR/tools/skills_catalog_shadow_smoke.js" \
  "$DIST_DIR/tools/skills_catalog_shadow_smoke.command" \
  "$DIST_DIR/tools/skills_catalog_http_smoke.js" \
  "$DIST_DIR/tools/skills_catalog_http_smoke.command" \
  "$DIST_DIR/tools/xt_file_ipc_watcher_run_once_smoke.js" \
  "$DIST_DIR/tools/xt_file_ipc_watcher_run_once_smoke.command" \
  "$DIST_DIR/tools/xt_file_ipc_background_watcher_smoke.js" \
  "$DIST_DIR/tools/xt_file_ipc_background_watcher_smoke.command" \
  "$DIST_DIR/tools/xt_file_ipc_runtime_execution_plan_smoke.js" \
  "$DIST_DIR/tools/xt_file_ipc_runtime_execution_plan_smoke.command" \
  "$DIST_DIR/tools/xt_file_ipc_runtime_adapter_candidate_smoke.js" \
  "$DIST_DIR/tools/xt_file_ipc_runtime_adapter_candidate_smoke.command" \
  "$DIST_DIR/tools/xt_file_ipc_prep_session.js" \
  "$DIST_DIR/tools/xt_file_ipc_prep_session.command" \
  "$DIST_DIR/tools/xt_file_ipc_production_session.js" \
  "$DIST_DIR/tools/xt_file_ipc_production_session.command" \
  "$DIST_DIR/tools/xt_file_ipc_production_cutover_blocker.js" \
  "$DIST_DIR/tools/xt_file_ipc_production_cutover_blocker.command" \
  "$DIST_DIR/tools/xt_file_ipc_production_rollback_rehearsal.js" \
  "$DIST_DIR/tools/xt_file_ipc_production_rollback_rehearsal.command" \
  "$DIST_DIR/tools/xt_file_ipc_live_cutover_preflight.js" \
  "$DIST_DIR/tools/xt_file_ipc_live_cutover_preflight.command" \
  "$DIST_DIR/tools/xt_file_ipc_live_heartbeat_soak.js" \
  "$DIST_DIR/tools/xt_file_ipc_live_heartbeat_soak.command" \
  "$DIST_DIR/tools/production_live_stability_gate.js" \
  "$DIST_DIR/tools/production_live_stability_gate.command" \
  "$DIST_DIR/tools/production_live_stability_session.js" \
  "$DIST_DIR/tools/production_live_stability_session.command" \
  "$DIST_DIR/tools/ui_compatibility_no_product_ui_change_gate.js" \
  "$DIST_DIR/tools/ui_compatibility_no_product_ui_change_gate.command" \
  "$DIST_DIR/tools/ops_readiness_gate.js" \
  "$DIST_DIR/tools/ops_readiness_gate.command" \
  "$DIST_DIR/tools/ops_soak_runner.js" \
  "$DIST_DIR/tools/ops_soak_runner.command" \
  "$DIST_DIR/tools/node_scheduler_shadow_compare.js" \
  "$DIST_DIR/tools/node_scheduler_shadow_compare.command" \
  "$DIST_DIR/tools/node_hub_shadow_compare_smoke.js" \
  "$DIST_DIR/tools/node_hub_shadow_compare_smoke.command" \
  "$DIST_DIR/tools/node_hub_shadow_compare_runner.js" \
  "$DIST_DIR/tools/node_hub_shadow_compare_runner.command" \
  "$DIST_DIR/tools/node_hub_authority_live_runner.js" \
  "$DIST_DIR/tools/node_hub_authority_live_runner.command" \
  "$DIST_DIR/tools/scheduler_cutover_readiness_runner.js" \
  "$DIST_DIR/tools/scheduler_cutover_readiness_runner.command" \
  "$DIST_DIR/tools/scheduler_authority_runner.js" \
  "$DIST_DIR/tools/scheduler_authority_runner.command" \
  "$DIST_DIR/tools/scheduler_production_authority_plan.js" \
  "$DIST_DIR/tools/scheduler_production_authority_plan.command" \
  "$DIST_DIR/tools/scheduler_production_authority_apply.js" \
  "$DIST_DIR/tools/scheduler_production_authority_apply.command" \
  "$DIST_DIR/tools/scheduler_production_authority_session.js" \
  "$DIST_DIR/tools/scheduler_production_authority_session.command" \
  "$DIST_DIR/tools/scheduler_production_authority_session_launchd.js" \
  "$DIST_DIR/tools/scheduler_production_authority_session_launchd.command" \
  "$DIST_DIR/tools/scheduler_production_authority_guard.js" \
  "$DIST_DIR/tools/scheduler_production_authority_guard.command" \
  "$DIST_DIR/tools/route_authority_cutover_guard.js" \
  "$DIST_DIR/tools/route_authority_cutover_guard.command" \
  "$DIST_DIR/tools/route_authority_prep_session.js" \
  "$DIST_DIR/tools/route_authority_prep_session.command" \
  "$DIST_DIR/tools/route_authority_prep_runtime_guard.js" \
  "$DIST_DIR/tools/route_authority_prep_runtime_guard.command" \
  "$DIST_DIR/tools/route_authority_prep_sustained_guard.js" \
  "$DIST_DIR/tools/route_authority_prep_sustained_guard.command" \
  "$DIST_DIR/tools/route_authority_prep_session_launchd.js" \
  "$DIST_DIR/tools/route_authority_prep_session_launchd.command" \
  "$DIST_DIR/tools/route_authority_production_cutover_blocker.js" \
  "$DIST_DIR/tools/route_authority_production_cutover_blocker.command" \
  "$DIST_DIR/tools/route_authority_production_session.js" \
  "$DIST_DIR/tools/route_authority_production_session.command" \
  "$DIST_DIR/tools/route_authority_production_runtime_guard.js" \
  "$DIST_DIR/tools/route_authority_production_runtime_guard.command" \
  "$DIST_DIR/tools/active_root_upgrade_plan.js" \
  "$DIST_DIR/tools/active_root_upgrade_plan.command" \
  "$DIST_DIR/tools/active_root_upgrade_apply.js" \
  "$DIST_DIR/tools/active_root_upgrade_apply.command" \
  "$DIST_DIR/tools/scheduler_status_http_bridge_smoke.js" \
  "$DIST_DIR/tools/scheduler_status_http_bridge_smoke.command" \
  "$DIST_DIR/tools/scheduler_lease_shadow_http_bridge_smoke.js" \
  "$DIST_DIR/tools/scheduler_lease_shadow_http_bridge_smoke.command" \
  "$DIST_DIR/tools/scheduler_authority_http_bridge_smoke.js" \
  "$DIST_DIR/tools/scheduler_authority_http_bridge_smoke.command" \
  "$DIST_DIR/tools/provider_route_smoke.command" \
  "$DIST_DIR/tools/provider_route_http_smoke.command" \
  "$DIST_DIR/tools/provider_route_http_bridge_smoke.js" \
  "$DIST_DIR/tools/provider_route_http_bridge_smoke.command" \
  "$DIST_DIR/tools/provider_route_http_shadow_compare_smoke.js" \
  "$DIST_DIR/tools/provider_route_http_shadow_compare_smoke.command" \
  "$DIST_DIR/tools/provider_route_shadow_compare_smoke.js" \
  "$DIST_DIR/tools/provider_route_shadow_compare_smoke.command" \
  "$DIST_DIR/tools/model_inventory_shadow_compare_smoke.js" \
  "$DIST_DIR/tools/model_inventory_shadow_compare_smoke.command" \
  "$DIST_DIR/tools/model_inventory_shadow_compare_runner.js" \
  "$DIST_DIR/tools/model_inventory_shadow_compare_runner.command" \
  "$DIST_DIR/tools/model_inventory_http_bridge_smoke.js" \
  "$DIST_DIR/tools/model_inventory_http_bridge_smoke.command" \
  "$DIST_DIR/tools/model_route_http_smoke.js" \
  "$DIST_DIR/tools/model_route_http_smoke.command" \
  "$DIST_DIR/tools/model_route_generate_candidate_runner.js" \
  "$DIST_DIR/tools/model_route_generate_candidate_runner.command" \
  "$DIST_DIR/tools/model_route_local_candidate_runner.js" \
  "$DIST_DIR/tools/model_route_local_candidate_runner.command" \
  "$DIST_DIR/tools/model_route_candidate_evidence_runner.js" \
  "$DIST_DIR/tools/model_route_candidate_evidence_runner.command" \
  "$DIST_DIR/tools/model_route_authority_plan_runner.js" \
  "$DIST_DIR/tools/model_route_authority_plan_runner.command" \
  "$DIST_DIR/tools/model_route_prep_trial_runner.js" \
  "$DIST_DIR/tools/model_route_prep_trial_runner.command" \
  "$DIST_DIR/tools/model_route_prep_sustained_runner.js" \
  "$DIST_DIR/tools/model_route_prep_sustained_runner.command" \
  "$DIST_DIR/tools/provider_route_shadow_compare_runner.js" \
  "$DIST_DIR/tools/provider_route_shadow_compare_runner.command" \
  "$DIST_DIR/tools/provider_route_generate_observe_runner.js" \
  "$DIST_DIR/tools/provider_route_generate_observe_runner.command" \
  "$DIST_DIR/tools/provider_route_cutover_readiness_runner.js" \
  "$DIST_DIR/tools/provider_route_cutover_readiness_runner.command" \
  "$DIST_DIR/tools/provider_route_authority_plan_runner.js" \
  "$DIST_DIR/tools/provider_route_authority_plan_runner.command"

echo "Packaged Rust Hub at: $DIST_DIR"
