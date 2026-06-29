use std::net::TcpStream;
use std::sync::Arc;

use xhub_core::now_ms;

use crate::cli::proto_summary_json;
use crate::local_ml_bridge;
use crate::memory_bridge;
use crate::network_bridge;
use crate::server::auth::http_access_key_failure;
use crate::server::handlers::evidence::*;
use crate::server::handlers::health::*;
use crate::server::handlers::memory::*;
use crate::server::handlers::metrics::*;
use crate::server::handlers::model::*;
use crate::server::handlers::provider::*;
use crate::server::handlers::root::*;
use crate::server::handlers::scheduler::*;
use crate::server::handlers::skills::*;
use crate::server::request::{read_http_request, split_path_query};
use crate::server::response::{
    acquire_http_inflight_slot, apply_http_io_timeouts, record_http_route_metrics,
    write_http_response, write_http_response_with_content_type,
};
use crate::server::state::HubState;
use crate::xt_compat;
use crate::xt_contract;
use crate::xt_file_ipc;

pub(crate) fn handle_client(mut stream: TcpStream, state: &Arc<HubState>) -> Result<(), String> {
    apply_http_io_timeouts(&stream, state)?;
    let config = &state.config;
    let peer_addr = stream.peer_addr().ok();
    let request = read_http_request(&mut stream)?;
    let path = request.path.as_str();

    let (route_path, query) = split_path_query(path);
    let request_started_ms = now_ms();
    let _inflight_guard = match acquire_http_inflight_slot(state, route_path) {
        Ok(guard) => guard,
        Err(response) => {
            let elapsed_ms = now_ms().saturating_sub(request_started_ms);
            record_http_route_metrics(state, route_path, "503 Service Unavailable", elapsed_ms);
            return write_http_response(&mut stream, "503 Service Unavailable", response.as_str());
        }
    };
    let (status, body) = if let Some(failure) =
        http_access_key_failure(&request, config, peer_addr, route_path)
    {
        failure
    } else {
        match route_path {
            "/" => ("200 OK", root_body()),
            "/health" => ("200 OK", health_json(config)),
            "/product/kernel" | "/kernel/status" => ("200 OK", product_kernel_json(state)),
            "/ready" | "/readiness" | "/runtime/readiness" => {
                ("200 OK", readiness_json_cached(state))
            }
            "/runtime/scheduler_status" => ("200 OK", scheduler_status_json()),
            "/runtime/http-metrics" | "/http/metrics" => http_metrics_json(state),
            "/network/remote-entry-candidates"
            | "/network/remote-entry"
            | "/remote/entry-candidates" => {
                network_bridge::remote_entry_candidates_http_json(config, query)
            }
            "/xt/hub-contract" | "/xt/contract" | "/contract/xt" => {
                xt_contract::contract_http_json(config)
            }
            "/xt/classic-hub-compat" | "/compat/xt-classic-hub" | "/compat/classic-hub" => {
                ("200 OK", xt_compat::classic_hub_compat_json(config))
            }
            "/xt/classic-hub-compat/write-status"
            | "/compat/xt-classic-hub/write-status"
            | "/compat/classic-hub/write-status" => {
                xt_compat::classic_hub_status_write_http_json(config, request.method.as_str())
            }
            "/xt/file-ipc/live-status"
            | "/xt/file-ipc-live-status"
            | "/compat/xt-file-ipc/live-status" => {
                xt_file_ipc::live_status_http_json(config, request.method.as_str())
            }
            "/xt/file-ipc/runtime-authority-sync"
            | "/xt/file-ipc-runtime-authority-sync"
            | "/compat/xt-file-ipc/runtime-authority-sync" => {
                xt_file_ipc::runtime_authority_sync_http_json(
                    config,
                    request.method.as_str(),
                    request.body.as_str(),
                )
            }
            "/xt/file-ipc-shadow"
            | "/xt/file-ipc-shadow/respond-once"
            | "/xt/file-ipc-shadow/drain"
            | "/xt/file-ipc-shadow/cycle"
            | "/xt/file-ipc-shadow/supervise"
            | "/xt/file-ipc-shadow/watcher-smoke"
            | "/xt/file-ipc-shadow/watcher-rollback-smoke"
            | "/xt/file-ipc-shadow/watcher-readiness"
            | "/xt/file-ipc-shadow/watcher-start-plan"
            | "/xt/file-ipc-shadow/watcher-run-once"
            | "/xt/file-ipc-shadow/watcher-session"
            | "/xt/file-ipc-shadow/runtime-execution-plan"
            | "/xt/file-ipc-shadow/runtime-adapter-candidate"
            | "/xt/file-ipc-shadow/watcher-background-start"
            | "/xt/file-ipc-shadow/watcher-background-stop"
            | "/xt/file-ipc-shadow/watcher-background-status"
            | "/compat/xt-file-ipc-shadow"
            | "/compat/xt-file-ipc-shadow/drain"
            | "/compat/xt-file-ipc-shadow/cycle"
            | "/compat/xt-file-ipc-shadow/supervise"
            | "/compat/xt-file-ipc-shadow/watcher-smoke"
            | "/compat/xt-file-ipc-shadow/watcher-rollback-smoke"
            | "/compat/xt-file-ipc-shadow/watcher-readiness"
            | "/compat/xt-file-ipc-shadow/watcher-start-plan"
            | "/compat/xt-file-ipc-shadow/watcher-run-once"
            | "/compat/xt-file-ipc-shadow/watcher-session"
            | "/compat/xt-file-ipc-shadow/runtime-execution-plan"
            | "/compat/xt-file-ipc-shadow/runtime-adapter-candidate"
            | "/compat/xt-file-ipc-shadow/watcher-background-start"
            | "/compat/xt-file-ipc-shadow/watcher-background-stop"
            | "/compat/xt-file-ipc-shadow/watcher-background-status" => {
                xt_file_ipc::shadow_http_json(
                    config,
                    route_path,
                    request.method.as_str(),
                    request.body.as_str(),
                )
            }
            "/scheduler/status" => scheduler_status_http_json(config, query),
            "/scheduler/cutover-readiness" | "/scheduler/readiness" => {
                scheduler_readiness_http_json(config, query)
            }
            "/scheduler/enqueue" => {
                scheduler_command_http_json(config, "enqueue", request.body.as_str())
            }
            "/scheduler/claim" => {
                scheduler_command_http_json(config, "claim", request.body.as_str())
            }
            "/scheduler/acquire-run" => {
                scheduler_command_http_json(config, "acquire-run", request.body.as_str())
            }
            "/scheduler/release" => {
                scheduler_command_http_json(config, "release", request.body.as_str())
            }
            "/scheduler/cancel" => {
                scheduler_command_http_json(config, "cancel", request.body.as_str())
            }
            "/contract/proto_summary" => ("200 OK", proto_summary_json(config)),
            "/provider/route" => provider_route_http_json(config, query),
            "/provider/pools" | "/provider/key-pools" => provider_pools_http_json(config, query),
            "/provider/runtime-snapshot" | "/provider/snapshot" => {
                provider_runtime_snapshot_http_json(config, query)
            }
            "/provider/import" | "/provider/keys/import" => {
                provider_import_http_json(config, query, request.body.as_str())
            }
            "/provider/openai-quota-refresh/plan" | "/provider/quota/openai/plan" => {
                provider_openai_quota_plan_http_json(config, query, request.body.as_str())
            }
            "/provider/openai-quota-refresh/apply" | "/provider/quota/openai/apply" => {
                provider_openai_quota_apply_http_json(config, query, request.body.as_str())
            }
            "/provider/openai-quota-refresh/failure" | "/provider/quota/openai/failure" => {
                provider_openai_quota_failure_http_json(config, query, request.body.as_str())
            }
            "/provider/oauth-refresh/apply" | "/provider/oauth/apply" => {
                provider_oauth_refresh_apply_http_json(config, query, request.body.as_str())
            }
            "/provider/oauth-refresh/failure" | "/provider/oauth/failure" => {
                provider_oauth_refresh_failure_http_json(config, query, request.body.as_str())
            }
            "/provider/oauth-refresh/codex/plan"
            | "/provider/oauth/codex-refresh/plan"
            | "/provider/codex-oauth-refresh/plan" => {
                provider_codex_oauth_plan_http_json(config, query, request.body.as_str())
            }
            "/provider/oauth-refresh/codex" | "/provider/oauth/codex-refresh" => {
                provider_codex_oauth_refresh_http_json(config, query, request.body.as_str())
            }
            "/provider/compare" => provider_compare_http_json(config, query, request.body.as_str()),
            "/provider/reports" => provider_reports_http_json(config, query),
            "/provider/readiness" => provider_readiness_http_json(config, query),
            "/memory/search" => memory_search_http_json(state, query),
            "/memory/retrieve" => memory_retrieve_http_json(state, query, request.body.as_str()),
            "/memory/project-role-transcript"
            | "/memory/project-role-transcript-projection"
            | "/memory/role-transcript" => memory_role_transcript_http_json(config, query),
            "/memory/write" | "/memory/append" => {
                memory_write_http_json(config, request.body.as_str())
            }
            "/memory/readiness" | "/memory/status" => memory_readiness_http_json(state, query),
            "/memory/object-index/rebuild" | "/memory/reindex" => {
                memory_bridge::object_index_rebuild_http_json(config, request.method.as_str())
            }
            "/memory/objects" => memory_bridge::object_collection_http_json(
                config,
                request.method.as_str(),
                query,
                request.body.as_str(),
            ),
            path if path == "/memory/writeback/candidates"
                || path.starts_with("/memory/writeback/candidates/") =>
            {
                memory_bridge::writeback_candidates_http_json(
                    config,
                    path,
                    request.method.as_str(),
                    query,
                    request.body.as_str(),
                )
            }
            path if path.starts_with("/memory/objects/") => memory_bridge::object_item_http_json(
                config,
                path,
                request.method.as_str(),
                query,
                request.body.as_str(),
            ),
            "/memory/policy/evaluate" => {
                memory_bridge::policy_evaluate_http_json(request.body.as_str())
            }
            "/memory/project-canonical-sync" | "/memory/project-canonical" => {
                memory_bridge::project_canonical_sync_http_json(
                    config,
                    request.method.as_str(),
                    query,
                    request.body.as_str(),
                )
            }
            "/memory/gateway/prepare" | "/memory/context" => {
                memory_bridge::memory_gateway_prepare_http_json(
                    config,
                    request.method.as_str(),
                    request.body.as_str(),
                )
            }
            "/evidence/ledger" | "/evidence/list" => evidence_ledger_http_json(config, query),
            "/evidence/write" => evidence_write_http_json(config, request.body.as_str()),
            "/skills/catalog" => skills_catalog_http_json(state, query),
            "/skills/readiness" | "/skills/status" => skills_readiness_http_json(state, query),
            "/skills/policy-readiness" | "/skills/policy-maintenance" => {
                skills_policy_readiness_http_json(config, query, request.body.as_str())
            }
            "/skills/pin" => skills_pin_http_json(config, query, request.body.as_str()),
            "/skills/grant" => skills_grant_http_json(config, query, request.body.as_str()),
            "/skills/unpin" | "/skills/revoke-pin" => {
                skills_unpin_http_json(config, query, request.body.as_str())
            }
            "/skills/revoke-grant" => {
                skills_revoke_grant_http_json(config, query, request.body.as_str())
            }
            "/skills/policy" => skills_policy_http_json(config, query, request.body.as_str()),
            "/skills/policy-events" | "/skills/policy-audit" => {
                skills_policy_events_http_json(config, query, request.body.as_str())
            }
            "/skills/policy-events-prune" | "/skills/policy-audit-prune" => {
                skills_policy_events_prune_http_json(config, query, request.body.as_str())
            }
            "/skills/audit" => skills_audit_http_json(config, query, request.body.as_str()),
            "/skills/audit-prune" => {
                skills_audit_prune_http_json(config, query, request.body.as_str())
            }
            "/skills/preflight" => skills_preflight_http_json(config, query, request.body.as_str()),
            "/skills/execute" | "/skills/run" => {
                skills_execute_http_json(config, query, request.body.as_str())
            }
            "/model/inventory" => model_inventory_http_json(config, query),
            "/model/capabilities" | "/model/local-capabilities" => {
                model_capabilities_http_json(config, query)
            }
            "/model/concurrency-policy" | "/model/capacity-policy" => {
                model_concurrency_policy_http_json(config)
            }
            "/model/repair-plan" | "/model/local-repair-plan" => {
                model_repair_plan_http_json(config, query)
            }
            "/model/repair-apply" | "/model/local-repair-apply" => {
                model_repair_apply_http_json(config, query, request.body.as_str())
            }
            "/model/repair-jobs" | "/model/local-repair-jobs" => {
                model_repair_jobs_http_json(config, query)
            }
            "/model/route" => model_route_http_json(config, query, request.body.as_str()),
            "/model/compare" => model_compare_http_json(config, query, request.body.as_str()),
            "/model/reports" => model_reports_http_json(config, query),
            "/model/diagnostics" | "/model/route-diagnostics" => {
                model_diagnostics_http_json(config, query)
            }
            "/model/readiness" | "/model/cutover-readiness" => {
                model_readiness_http_json(config, query)
            }
            "/local-ml/readiness"
            | "/local-ml/status"
            | "/runtime/local-ml/readiness"
            | "/runtime/ml-execution/readiness" => {
                local_ml_bridge::readiness_http_json(config, query)
            }
            "/local-ml/execute"
            | "/local-ml/run-local-task"
            | "/runtime/local-ml/execute"
            | "/runtime/ml-execution/execute" => local_ml_bridge::execute_http_json(
                config,
                request.method.as_str(),
                request.body.as_str(),
            ),
            _ => (
                "404 Not Found",
                "{\"ok\":false,\"error\":\"not_found\"}\n".to_string(),
            ),
        }
    };

    let content_type = if body.trim_start().starts_with("<!doctype html") {
        "text/html; charset=utf-8"
    } else {
        "application/json; charset=utf-8"
    };
    let elapsed_ms = now_ms().saturating_sub(request_started_ms);
    record_http_route_metrics(state, route_path, status, elapsed_ms);
    write_http_response_with_content_type(&mut stream, status, body.as_str(), content_type)?;
    Ok(())
}
