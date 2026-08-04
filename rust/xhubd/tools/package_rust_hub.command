#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
OUTPUT_FILE=""
OUTPUT_PARENT=""
OUTPUT_TMP_FILE=""
PROVENANCE_OUTPUT_TMP=""
RELEASE_BUILD=0
EXPECTED_GIT_COMMIT=""

usage() {
  echo "Usage: $0 [--output-file <path>]" >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-file)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then
        echo "--output-file requires a path." >&2
        usage
        exit 64
      fi
      OUTPUT_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 64
      ;;
  esac
done

normalize_output_file() {
  local output_name=""
  [ -n "$OUTPUT_FILE" ] || return 0

  output_name="$(basename "$OUTPUT_FILE")"
  OUTPUT_PARENT="$(dirname "$OUTPUT_FILE")"
  if [ "$output_name" = "." ] || [ "$output_name" = "/" ] || \
     ! OUTPUT_PARENT="$(cd "$OUTPUT_PARENT" 2>/dev/null && pwd -P)"; then
    echo "--output-file parent directory does not exist: $OUTPUT_FILE" >&2
    exit 64
  fi
  if [ "$OUTPUT_PARENT" = "/" ]; then
    OUTPUT_FILE="/$output_name"
  else
    OUTPUT_FILE="$OUTPUT_PARENT/$output_name"
  fi
  if [ -e "$OUTPUT_FILE" ] && [ ! -f "$OUTPUT_FILE" ]; then
    echo "--output-file must name a regular file: $OUTPUT_FILE" >&2
    exit 64
  fi
  if [ ! -w "$OUTPUT_PARENT" ]; then
    echo "--output-file parent directory is not writable: $OUTPUT_PARENT" >&2
    exit 73
  fi
}

release_stamp() {
  if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
    date -u +%Y%m%dT%H%M%SZ
    return
  fi

  case "$SOURCE_DATE_EPOCH" in
    *[!0-9]*|'')
      echo "SOURCE_DATE_EPOCH must be a non-negative integer." >&2
      return 64
      ;;
  esac

  if date -u -r "$SOURCE_DATE_EPOCH" +%Y%m%dT%H%M%SZ 2>/dev/null; then
    return
  fi
  if date -u -d "@$SOURCE_DATE_EPOCH" +%Y%m%dT%H%M%SZ 2>/dev/null; then
    return
  fi

  echo "Unable to convert SOURCE_DATE_EPOCH with the installed date command." >&2
  return 1
}

DIST_ROOT="$ROOT_DIR/dist"
STAGING_DIR=""

cleanup() {
  if [ -n "$OUTPUT_TMP_FILE" ] && [ -f "$OUTPUT_TMP_FILE" ]; then
    rm -f -- "$OUTPUT_TMP_FILE"
  fi
  if [ -n "$PROVENANCE_OUTPUT_TMP" ] && [ -f "$PROVENANCE_OUTPUT_TMP" ]; then
    rm -f -- "$PROVENANCE_OUTPUT_TMP"
  fi
  if [ -n "$STAGING_DIR" ] && [ -d "$STAGING_DIR" ]; then
    case "$STAGING_DIR" in
      "$DIST_ROOT"/.rust-hub-stage.*)
        rm -rf -- "$STAGING_DIR"
        ;;
      *)
        echo "Refusing to clean unexpected staging path: $STAGING_DIR" >&2
        ;;
    esac
  fi
}
trap cleanup EXIT

normalize_output_file
STAMP="$(release_stamp)"

case "${XHUB_RELEASE_BUILD:-0}" in
  1|true|TRUE|yes|YES|on|ON) RELEASE_BUILD=1 ;;
esac

if [ "$RELEASE_BUILD" = "1" ]; then
  if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
    echo "SOURCE_DATE_EPOCH is required for a release package." >&2
    exit 1
  fi
  if ! command -v node >/dev/null 2>&1; then
    echo "node is required to verify release package identity." >&2
    exit 127
  fi
  if [ -n "$(git -C "$ROOT_DIR" status --porcelain=v1 --untracked-files=all)" ]; then
    echo "Refusing a release package from a dirty repository." >&2
    exit 1
  fi
  EXPECTED_GIT_COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD)"
fi

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo not found. Install Rust toolchain before packaging Rust Hub." >&2
  exit 127
fi

cd "$ROOT_DIR"
cargo build --release -p xhubd

mkdir -p "$DIST_ROOT"
STAGING_DIR="$(mktemp -d "$DIST_ROOT/.rust-hub-stage.XXXXXX")"
STAGING_SUFFIX="${STAGING_DIR##*.rust-hub-stage.}"
FINAL_DIR="$DIST_ROOT/rust-hub-$STAMP-$STAGING_SUFFIX"
if [ -e "$FINAL_DIR" ]; then
  echo "Refusing to reuse existing Rust Hub package directory: $FINAL_DIR" >&2
  exit 1
fi

DIST_DIR="$STAGING_DIR"
mkdir -p "$DIST_DIR/bin" "$DIST_DIR/config" "$DIST_DIR/assets/proto" "$DIST_DIR/migrations" "$DIST_DIR/tools" "$DIST_DIR/docs" "$DIST_DIR/skills" "$DIST_DIR/provenance"

cp "$ROOT_DIR/target/release/xhubd" "$DIST_DIR/bin/xhubd"
cp "$ROOT_DIR/README.md" "$DIST_DIR/README.md"
cp "$ROOT_DIR/config/default.toml" "$DIST_DIR/config/default.toml"
cp "$ROOT_DIR"/config/daemon_profile*.json "$DIST_DIR/config/"
cp "$ROOT_DIR/assets/proto/hub_protocol_v1.proto" "$DIST_DIR/assets/proto/hub_protocol_v1.proto"
cp "$ROOT_DIR"/migrations/*.sql "$DIST_DIR/migrations/"
cp "$ROOT_DIR/provenance/capabilities.json" "$DIST_DIR/provenance/capabilities.json"
cp "$ROOT_DIR"/docs/*.md "$DIST_DIR/docs/"
cp -R "$ROOT_DIR"/skills/. "$DIST_DIR/skills/"
cp "$ROOT_DIR/tools/run_packaged_rust_hub.command" "$DIST_DIR/tools/run_rust_hub.command"
cp "$ROOT_DIR/tools/xhubd_daemon.js" "$DIST_DIR/tools/xhubd_daemon.js"
cp "$ROOT_DIR/tools/verify_release_package_identity.js" "$DIST_DIR/tools/verify_release_package_identity.js"
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
cp "$ROOT_DIR/tools/memory_gateway_cutover_smoke.js" "$DIST_DIR/tools/memory_gateway_cutover_smoke.js"
cp "$ROOT_DIR/tools/memory_gateway_cutover_smoke.command" "$DIST_DIR/tools/memory_gateway_cutover_smoke.command"
cp "$ROOT_DIR/tools/memory_gateway_model_call_execute_smoke.js" "$DIST_DIR/tools/memory_gateway_model_call_execute_smoke.js"
cp "$ROOT_DIR/tools/memory_gateway_model_call_execute_smoke.command" "$DIST_DIR/tools/memory_gateway_model_call_execute_smoke.command"
cp "$ROOT_DIR/tools/memory_gateway_model_call_local_executor_smoke.js" "$DIST_DIR/tools/memory_gateway_model_call_local_executor_smoke.js"
cp "$ROOT_DIR/tools/memory_gateway_model_call_local_executor_smoke.command" "$DIST_DIR/tools/memory_gateway_model_call_local_executor_smoke.command"
cp "$ROOT_DIR/tools/memory_gateway_model_call_live_canary_session.js" "$DIST_DIR/tools/memory_gateway_model_call_live_canary_session.js"
cp "$ROOT_DIR/tools/memory_gateway_model_call_live_canary_session.command" "$DIST_DIR/tools/memory_gateway_model_call_live_canary_session.command"
cp "$ROOT_DIR/tools/memory_gateway_cutover_session.js" "$DIST_DIR/tools/memory_gateway_cutover_session.js"
cp "$ROOT_DIR/tools/memory_gateway_cutover_session.command" "$DIST_DIR/tools/memory_gateway_cutover_session.command"
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
cp "$ROOT_DIR/tools/product_process_sanity.js" "$DIST_DIR/tools/product_process_sanity.js"
cp "$ROOT_DIR/tools/product_process_sanity.command" "$DIST_DIR/tools/product_process_sanity.command"
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
  "$DIST_DIR/tools/verify_release_package_identity.js" \
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
  "$DIST_DIR/tools/memory_gateway_cutover_smoke.js" \
  "$DIST_DIR/tools/memory_gateway_cutover_smoke.command" \
  "$DIST_DIR/tools/memory_gateway_model_call_execute_smoke.js" \
  "$DIST_DIR/tools/memory_gateway_model_call_execute_smoke.command" \
  "$DIST_DIR/tools/memory_gateway_model_call_local_executor_smoke.js" \
  "$DIST_DIR/tools/memory_gateway_model_call_local_executor_smoke.command" \
  "$DIST_DIR/tools/memory_gateway_model_call_live_canary_session.js" \
  "$DIST_DIR/tools/memory_gateway_model_call_live_canary_session.command" \
  "$DIST_DIR/tools/memory_gateway_cutover_session.js" \
  "$DIST_DIR/tools/memory_gateway_cutover_session.command" \
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
  "$DIST_DIR/tools/product_process_sanity.js" \
  "$DIST_DIR/tools/product_process_sanity.command" \
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

PROVENANCE_OUTPUT_TMP="$(mktemp "$DIST_ROOT/.rust-hub-provenance.XXXXXX")"
"$DIST_DIR/bin/xhubd" provenance --package-manifest > "$PROVENANCE_OUTPUT_TMP"
mv "$PROVENANCE_OUTPUT_TMP" "$DIST_DIR/provenance.json"
PROVENANCE_OUTPUT_TMP=""
XHUB_PROVENANCE_MANIFEST="$DIST_DIR/provenance.json" \
  "$DIST_DIR/bin/xhubd" provenance >/dev/null

if [ "$RELEASE_BUILD" = "1" ]; then
  node "$ROOT_DIR/tools/verify_release_package_identity.js" \
    --manifest "$DIST_DIR/provenance.json" \
    --expected-commit "$EXPECTED_GIT_COMMIT" \
    --expected-source-root "$ROOT_DIR" \
    --expected-source-date-epoch "$SOURCE_DATE_EPOCH" >/dev/null
fi

mv "$STAGING_DIR" "$FINAL_DIR"
STAGING_DIR=""

if [ -n "$OUTPUT_FILE" ]; then
  OUTPUT_TMP_FILE="$(mktemp "$OUTPUT_PARENT/.xhub-package-path.XXXXXX")"
  printf '%s\n' "$FINAL_DIR" > "$OUTPUT_TMP_FILE"
  mv "$OUTPUT_TMP_FILE" "$OUTPUT_FILE"
  OUTPUT_TMP_FILE=""
fi

echo "Packaged Rust Hub at: $FINAL_DIR"
