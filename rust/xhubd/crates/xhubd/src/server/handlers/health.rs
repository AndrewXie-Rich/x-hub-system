use std::path::PathBuf;
use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::thread;

use serde_json::{json, Value};
use xhub_core::{json_escape, now_ms, path_exists, HubConfig, DAEMON_NAME, SCHEMA_HEALTH_V1};
use xhub_memory::{MemoryIndexSnapshot, RetrievalPlan};
use xhub_scheduler::{SchedulerSnapshot, SchedulerStore};
use xhub_skills::{
    scan_skill_catalog, SkillBoundary, SkillCatalog, SKILL_CATALOG_SCHEMA,
    SKILL_POLICY_EVENTS_PRUNE_SCHEMA, SKILL_POLICY_EVENTS_SCHEMA,
    SKILL_POLICY_STORE_READINESS_SCHEMA, SKILL_PREFLIGHT_AUDIT_SCHEMA,
    SKILL_PREFLIGHT_AUDIT_SUMMARY_SCHEMA, SKILL_PREFLIGHT_SCHEMA, SKILL_READINESS_SCHEMA,
};

use crate::cli::display_optional_path;
use crate::config::{
    cross_network_public_endpoint_enabled, env_bool, env_path_or_default, env_string,
    env_u128_in_range, env_usize_in_range, is_loopback_host,
    model_route_production_authority_enabled, provider_route_production_authority_enabled,
    public_base_url_ready, scheduler_production_authority_enabled,
    xt_file_ipc_production_authority_enabled,
};
use crate::server::state::HubState;
use crate::{
    local_ml_bridge, memory_bridge, memory_role_projection, scheduler_bridge, skills_bridge,
    xt_compat,
};

pub(crate) fn value_path<'a>(value: &'a Value, path: &[&str]) -> Option<&'a Value> {
    let mut current = value;
    for key in path {
        current = current.get(*key)?;
    }
    Some(current)
}

pub(crate) fn health_json(config: &HubConfig) -> String {
    let proto_ok = path_exists(&config.proto_path);
    format!(
        "{{\"schema_version\":\"{}\",\"ok\":true,\"daemon\":\"{}\",\"version\":\"{}\",\"mode\":\"shadow_http\",\"grpc_compat\":\"not_started\",\"http_addr\":\"{}\",\"proto_ok\":{},\"db_path\":\"{}\"}}\n",
        SCHEMA_HEALTH_V1,
        DAEMON_NAME,
        env!("CARGO_PKG_VERSION"),
        json_escape(&config.http_addr()),
        proto_ok,
        json_escape(&config.db_path.display().to_string())
    )
}

pub(crate) fn product_kernel_json(state: &Arc<HubState>) -> String {
    let readiness_body = product_kernel_readiness_json_cached(state);
    product_kernel_json_from_readiness(&state.config, readiness_body.as_str())
}

pub(crate) fn product_kernel_json_from_readiness(
    config: &HubConfig,
    readiness_body: &str,
) -> String {
    let generated_at_ms = now_ms().min(i64::MAX as u128) as i64;
    let readiness =
        serde_json::from_str::<Value>(readiness_body.trim()).unwrap_or_else(|_| json!({}));
    let public_base_url = value_path_string(&readiness, &["network", "public_base_url"]);
    let public_base_url_ready = value_path_bool(&readiness, &["network", "public_base_url_ready"]);
    let domain_public_endpoint_ready =
        value_path_bool(
            &readiness,
            &["capabilities", "domain_public_endpoint_ready"],
        ) || value_path_bool(&readiness, &["network", "public_endpoint_ready"]);
    let cross_network_ready = value_path_bool(&readiness, &["capabilities", "cross_network_ready"]);
    let xt_file_ipc_surface_ready = value_path_bool(
        &readiness,
        &["capabilities", "xt_file_ipc_production_surface_ready"],
    );
    let xt_file_ipc_authority = xt_file_ipc_production_authority_enabled(xt_file_ipc_surface_ready);
    let local_ml_enabled =
        value_path_bool(&readiness, &["runtime", "ml_execution_authority_enabled"]);
    let local_ml_ready = value_path_bool(&readiness, &["runtime", "ml_execution_in_rust"]);
    let local_ml_authority = local_ml_enabled && local_ml_ready;
    let provider_route_authority = provider_route_production_authority_enabled();
    let model_route_authority = model_route_production_authority_enabled();
    let scheduler_authority = scheduler_production_authority_enabled();
    let memory_writer_authority =
        value_path_bool(&readiness, &["memory", "canonical_writer_in_rust"]);
    let skills_execution_authority =
        value_path_bool(&readiness, &["skills", "execution_authority_in_rust"]);

    let body = json!({
        "schema_version": "xhub.product_kernel.v1",
        "ok": value_path_bool(&readiness, &["ok"]),
        "ready": value_path_bool(&readiness, &["ready"]),
        "generated_at_ms": generated_at_ms,
        "product": {
            "name": "X-Hub",
            "boundary": "rust_product_kernel_swift_shell",
        },
        "kernel": {
            "name": "rust",
            "daemon": DAEMON_NAME,
            "version": value_path_string(&readiness, &["version"]),
            "mode": value_path_string(&readiness, &["mode"]),
            "http_addr": value_path_string(&readiness, &["http_addr"]),
            "http_base_url": format!("http://{}", config.http_addr()),
            "runtime_root": config.root_dir.display().to_string(),
            "runtime_base_dir": value_path_string(&readiness, &["runtime", "runtime_base_dir"]),
        },
        "shell": {
            "name": "swift",
            "role": "product_ui_shell",
            "owns_product_ui": true,
            "embeds_kernel_ui": false,
        },
        "interfaces": {
            "product_kernel_http": true,
            "readiness_http": true,
            "http_base_url": format!("http://{}", config.http_addr()),
            "public_base_url": public_base_url,
        },
        "network": {
            "cross_network_ready": cross_network_ready,
            "domain_public_endpoint_ready": domain_public_endpoint_ready,
            "public_base_url": public_base_url,
            "public_base_url_ready": public_base_url_ready,
            "http_access_key_required": value_path_bool(&readiness, &["network", "http_access_key_required"]),
            "http_access_key_configured": value_path_bool(&readiness, &["network", "http_access_key_configured"]),
        },
        "storage": {
            "db_path": value_path_string(&readiness, &["storage", "db_path"]),
        },
        "authority": {
            "provider_route_in_rust": provider_route_authority,
            "model_route_in_rust": model_route_authority,
            "scheduler_in_rust": scheduler_authority,
            "memory_writer_in_rust": memory_writer_authority,
            "skills_execution_in_rust": skills_execution_authority,
            "xt_file_ipc_in_rust": xt_file_ipc_authority,
            "local_ml_execution_in_rust": local_ml_authority,
            "node_compatibility_layer": true,
            "node_remains_authority": false,
            "swift_shell_owns_ui": true,
            "rust_browser_product_ui": false,
            "ui_product_change": false,
        },
        "readiness": {
            "schema_version": value_path_string(&readiness, &["schema_version"]),
            "ready": value_path_bool(&readiness, &["ready"]),
            "checks": readiness.get("checks").cloned().unwrap_or_else(|| json!([])),
        },
    });
    format!("{body}\n")
}

pub(crate) fn value_path_bool(value: &Value, path: &[&str]) -> bool {
    match value_path(value, path) {
        Some(Value::Bool(value)) => *value,
        Some(Value::Number(value)) => value.as_i64().unwrap_or(0) != 0,
        Some(Value::String(value)) => matches!(
            value.trim().to_ascii_lowercase().as_str(),
            "1" | "true" | "yes" | "y" | "on"
        ),
        _ => false,
    }
}

pub(crate) fn value_path_string(value: &Value, path: &[&str]) -> String {
    match value_path(value, path) {
        Some(Value::String(value)) => value.trim().to_string(),
        Some(Value::Number(value)) => value.to_string(),
        Some(Value::Bool(value)) => value.to_string(),
        _ => String::new(),
    }
}

pub(crate) fn readiness_json_cached(state: &HubState) -> String {
    readiness_json_cached_with_stale_budget(state, 0)
}

pub(crate) fn product_kernel_readiness_json_cached(state: &Arc<HubState>) -> String {
    let max_stale_ms = product_kernel_stale_readiness_max_ms();
    let ttl_ms = state.readiness_cache_ttl_ms;
    if ttl_ms == 0 {
        return readiness_json_uncached(state);
    }

    let now = now_ms();
    if let Ok(cache) = state.readiness_cache.try_lock() {
        if !cache.body.is_empty() {
            if cache.expires_at_ms > now {
                return cache.body.clone();
            }
            if max_stale_ms > 0
                && cache
                    .refreshed_at_ms
                    .saturating_add(ttl_ms)
                    .saturating_add(max_stale_ms)
                    > now
            {
                let body = cache.body.clone();
                drop(cache);
                refresh_product_kernel_readiness_cache_in_background(Arc::clone(state));
                return body;
            }
        }
    }

    let body = readiness_json_uncached(state);
    store_readiness_cache_body(state, body.clone());
    body
}

pub(crate) fn product_kernel_stale_readiness_max_ms() -> u128 {
    env_u128_in_range(
        "XHUB_RUST_PRODUCT_KERNEL_STALE_READINESS_MAX_MS",
        600_000,
        0,
        3_600_000,
    )
}

pub(crate) fn refresh_product_kernel_readiness_cache_in_background(state: Arc<HubState>) {
    if !env_bool("XHUB_RUST_PRODUCT_KERNEL_STALE_READINESS_REFRESH", true) {
        return;
    }
    if state
        .product_kernel_readiness_refresh_in_flight
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
        .is_err()
    {
        return;
    }
    thread::spawn(move || {
        let body = readiness_json_uncached(&state);
        store_readiness_cache_body(&state, body);
        state
            .product_kernel_readiness_refresh_in_flight
            .store(false, Ordering::Release);
    });
}

pub(crate) fn readiness_json_cached_with_stale_budget(
    state: &HubState,
    max_stale_ms: u128,
) -> String {
    let ttl_ms = state.readiness_cache_ttl_ms;
    if ttl_ms == 0 {
        return readiness_json_uncached(state);
    }

    let now = now_ms();
    if let Ok(cache) = state.readiness_cache.try_lock() {
        if !cache.body.is_empty() {
            if cache.expires_at_ms > now {
                return cache.body.clone();
            }
            if max_stale_ms > 0
                && cache
                    .refreshed_at_ms
                    .saturating_add(ttl_ms)
                    .saturating_add(max_stale_ms)
                    > now
            {
                return cache.body.clone();
            }
        }
    }

    let body = readiness_json_uncached(state);
    store_readiness_cache_body(state, body.clone());
    body
}

pub(crate) fn readiness_json_uncached(state: &HubState) -> String {
    readiness_json(
        &state.config,
        state.readiness_cache_ttl_ms,
        state.http_max_in_flight,
        state.http_read_timeout_ms,
        state.http_write_timeout_ms,
    )
}

pub(crate) fn store_readiness_cache_body(state: &HubState, body: String) {
    if let Ok(mut cache) = state.readiness_cache.try_lock() {
        let now = now_ms();
        cache.refreshed_at_ms = now;
        cache.expires_at_ms = now.saturating_add(state.readiness_cache_ttl_ms);
        cache.body = body;
    }
}

pub(crate) fn cached_memory_snapshot(state: &HubState, memory_dir: PathBuf) -> MemoryIndexSnapshot {
    let ttl_ms = state.memory_snapshot_cache_ttl_ms;
    if ttl_ms == 0 {
        return memory_bridge::snapshot_from_dir(memory_dir);
    }

    let now = now_ms();
    let mut cache = match state.memory_snapshot_cache.lock() {
        Ok(cache) => cache,
        Err(_) => return memory_bridge::snapshot_from_dir(memory_dir),
    };
    if cache.memory_dir == memory_dir {
        if let Some(snapshot) = cache
            .snapshot
            .as_ref()
            .filter(|_| cache.expires_at_ms > now)
        {
            return snapshot.clone();
        }
    }

    let snapshot = memory_bridge::snapshot_from_dir(memory_dir.clone());
    cache.memory_dir = memory_dir;
    cache.expires_at_ms = now.saturating_add(ttl_ms);
    cache.snapshot = Some(snapshot.clone());
    snapshot
}

pub(crate) fn cached_skills_catalog(state: &HubState, skills_dir: PathBuf) -> SkillCatalog {
    let ttl_ms = state.skills_catalog_cache_ttl_ms;
    if ttl_ms == 0 {
        return scan_skill_catalog(&skills_dir);
    }

    let now = now_ms();
    let mut cache = match state.skills_catalog_cache.lock() {
        Ok(cache) => cache,
        Err(_) => return scan_skill_catalog(&skills_dir),
    };
    if cache.skills_dir == skills_dir {
        if let Some(catalog) = cache.catalog.as_ref().filter(|_| cache.expires_at_ms > now) {
            return catalog.clone();
        }
    }

    let catalog = scan_skill_catalog(&skills_dir);
    cache.skills_dir = skills_dir;
    cache.expires_at_ms = now.saturating_add(ttl_ms);
    cache.catalog = Some(catalog.clone());
    catalog
}

pub(crate) fn readiness_json(
    config: &HubConfig,
    readiness_cache_ttl_ms: u128,
    http_max_in_flight: usize,
    http_read_timeout_ms: u64,
    http_write_timeout_ms: u64,
) -> String {
    let generated_at_ms = now_ms().min(i64::MAX as u128) as i64;
    let proto_ok = path_exists(&config.proto_path);
    let canonical_proto_ok = path_exists(&config.canonical_proto_path);
    let db_parent_ok = config.db_path.parent().map(path_exists).unwrap_or(false);
    let scheduler = SchedulerStore::new(
        config.db_path.clone(),
        scheduler_bridge::effective_scheduler_config(config),
    );
    let scheduler_status = scheduler.status_view(false, 0);
    let scheduler_ok = scheduler_status.is_ok();
    let runtime_configured = !config.runtime_base_dir.as_os_str().is_empty();
    let runtime_exists = runtime_configured && path_exists(&config.runtime_base_dir);
    let memory_dir = env_path_or_default(
        "XHUB_RUST_MEMORY_DIR",
        config.root_dir.join("data").join("memory"),
    );
    let skills_dir = env_path_or_default("XHUB_RUST_SKILLS_DIR", config.root_dir.join("skills"));
    let memory_dir_exists = path_exists(&memory_dir);
    let skills_catalog = scan_skill_catalog(&skills_dir);
    let skills_dir_exists = skills_catalog.skills_dir_exists;
    let skill_manifest_count = skills_catalog.skill_count();
    let skills_catalog_ok = skills_catalog.ready;
    let xt_file_ipc_production_surface_ready =
        xt_compat::classic_hub_production_surface_ready(config);
    let loopback_bind = is_loopback_host(&config.host);
    let lan_allowed = env_bool("XHUB_RUST_HUB_ALLOW_LAN", false);
    let bind_policy_ok = loopback_bind || lan_allowed;
    let public_base_url = env_string("XHUB_RUST_HUB_PUBLIC_BASE_URL");
    let public_endpoint_enabled = cross_network_public_endpoint_enabled();
    let public_base_url_ready = public_base_url_ready(public_base_url.as_str());
    let http_access_key_configured = config.http_access_key.is_some();
    let http_access_key_required =
        config.http_access_key_required || !loopback_bind || public_endpoint_enabled;
    let http_access_key_ok = !http_access_key_required || http_access_key_configured;
    let network_ok = bind_policy_ok && http_access_key_ok;
    let public_endpoint_ready = public_endpoint_enabled
        && public_base_url_ready
        && http_access_key_required
        && http_access_key_ok;
    let cross_network_ready = network_ok && (!loopback_bind || public_endpoint_ready);
    let memory_plan = RetrievalPlan::project_default();
    let skill_boundary = SkillBoundary::default();
    let memory_writer_authority = memory_bridge::memory_writer_authority_enabled();
    let skills_execution_authority = skills_bridge::skills_execution_authority_enabled();
    let local_ml_readiness = local_ml_bridge::readiness(config);
    let provider_route_authority = provider_route_production_authority_enabled();
    let model_route_authority = model_route_production_authority_enabled();
    let scheduler_authority = scheduler_production_authority_enabled();
    let xt_file_ipc_production_authority =
        xt_file_ipc_production_authority_enabled(xt_file_ipc_production_surface_ready);
    let ready = proto_ok
        && canonical_proto_ok
        && db_parent_ok
        && scheduler_ok
        && network_ok
        && memory_dir_exists
        && skills_catalog_ok
        && (!local_ml_readiness.enabled || local_ml_readiness.ready);
    let scheduler_error = match scheduler_status {
        Ok(_) => String::new(),
        Err(err) => err.to_string(),
    };

    let body = json!({
        "schema_version": "xhub.rust_hub.readiness.v1",
        "ok": true,
        "ready": ready,
        "generated_at_ms": generated_at_ms,
        "daemon": DAEMON_NAME,
        "version": env!("CARGO_PKG_VERSION"),
        "mode": "shadow_http",
        "http_addr": config.http_addr(),
        "performance": {
            "readiness_cache_ttl_ms": readiness_cache_ttl_ms,
            "memory_snapshot_cache_ttl_ms": env_u128_in_range("XHUB_RUST_MEMORY_SNAPSHOT_CACHE_TTL_MS", 500, 0, 10_000),
            "skills_catalog_cache_ttl_ms": env_u128_in_range("XHUB_RUST_SKILLS_CATALOG_CACHE_TTL_MS", 500, 0, 10_000),
            "http_max_in_flight": http_max_in_flight,
            "http_read_timeout_ms": http_read_timeout_ms,
            "http_write_timeout_ms": http_write_timeout_ms,
            "http_slow_ms": env_u128_in_range("XHUB_RUST_HTTP_SLOW_MS", 2_000, 1, 300_000),
            "http_metrics_recent_limit": env_usize_in_range("XHUB_RUST_HTTP_METRICS_RECENT_LIMIT", 256, 0, 10_000),
            "http_io_timeouts": true,
            "http_metrics": true,
            "http_backpressure": true,
            "readiness_cache_scope": "process_memory",
            "read_only_snapshot_cache_scope": "process_memory",
            "stutter_guard": true,
            "blocks_production_authority": false,
        },
        "network": {
            "host": config.host,
            "port": config.http_port,
            "loopback_bind": loopback_bind,
            "cross_network_bind": !loopback_bind,
            "cross_network_public_endpoint": public_endpoint_enabled,
            "public_base_url": public_base_url,
            "public_base_url_ready": public_base_url_ready,
            "public_endpoint_ready": public_endpoint_ready,
            "lan_allowed": lan_allowed,
            "bind_policy_ok": bind_policy_ok,
            "http_access_key_required": http_access_key_required,
            "http_access_key_configured": http_access_key_configured,
            "http_access_key_source": if config.http_access_key_source.is_empty() { "none" } else { config.http_access_key_source.as_str() },
            "ok": network_ok,
            "deny_code": if network_ok {
                ""
            } else if !bind_policy_ok {
                "lan_bind_requires_xhub_rust_hub_allow_lan"
            } else {
                "cross_network_requires_http_access_key"
            },
        },
        "storage": {
            "db_path": config.db_path.display().to_string(),
            "db_parent_ok": db_parent_ok,
            "sqlite_scheduler_view_ok": scheduler_ok,
            "scheduler_error": scheduler_error,
        },
        "contract": {
            "proto_path": config.proto_path.display().to_string(),
            "proto_ok": proto_ok,
            "canonical_proto_path": config.canonical_proto_path.display().to_string(),
            "canonical_proto_ok": canonical_proto_ok,
        },
        "runtime": {
            "runtime_base_dir": display_optional_path(&config.runtime_base_dir),
            "runtime_base_dir_configured": runtime_configured,
            "runtime_base_dir_exists": runtime_exists,
            "runtime_status_file_exists": runtime_exists && path_exists(&config.runtime_base_dir.join("ai_runtime_status.json")),
            "provider_store_file_exists": runtime_exists && path_exists(&config.runtime_base_dir.join("hub_provider_keys.json")),
            "provider_route_http": true,
            "provider_key_pools_http": true,
            "provider_key_runtime_snapshot_http": true,
            "provider_key_import_http": true,
            "provider_openai_quota_plan_http": true,
            "provider_openai_quota_apply_http": true,
            "provider_openai_quota_failure_http": true,
            "provider_oauth_refresh_apply_http": true,
            "provider_oauth_refresh_failure_http": true,
            "provider_oauth_refresh_codex_plan_http": true,
            "provider_oauth_refresh_codex_http": true,
            "account_portfolio_snapshot_in_rust": true,
            "quota_refresh_scheduler_in_rust": true,
            "quota_refresh_state_writer_in_rust": true,
            "provider_route_authority_in_rust": provider_route_authority,
            "model_inventory_http": true,
            "model_local_capabilities_http": true,
            "model_concurrency_policy_http": true,
            "model_local_repair_plan_http": true,
            "model_local_repair_apply_http": true,
            "model_local_repair_jobs_http": true,
            "model_route_diagnostics_http": true,
            "model_route_authority_in_rust": model_route_authority,
            "local_ml_execution_bridge_http": true,
            "ml_execution_in_rust": local_ml_readiness.ready,
            "ml_execution_authority_enabled": local_ml_readiness.enabled,
            "ml_execution_authority": local_ml_readiness.authority,
            "ml_execution_blocker": local_ml_readiness.blocker,
            "ml_execution_readiness": local_ml_bridge::readiness_value(config),
        },
        "memory": {
            "memory_dir": memory_dir.display().to_string(),
            "memory_dir_exists": memory_dir_exists,
            "mode": memory_plan.mode.as_str(),
            "include_dialogue_window": memory_plan.include_dialogue_window,
            "include_project_capsule": memory_plan.include_project_capsule,
            "include_personal_capsule": memory_plan.include_personal_capsule,
            "fail_closed": memory_plan.fail_closed,
            "authority": if memory_writer_authority { "canonical_writer" } else { "shadow_plan" },
            "canonical_writer_in_rust": memory_writer_authority,
            "retrieval_shadow_http": true,
            "write_http": true,
            "gateway_prepare_http": true,
            "role_transcript_projection_http": true,
            "role_transcript_projection_schema": memory_role_projection::PROJECT_ROLE_TRANSCRIPT_PROJECTION_SCHEMA,
            "role_transcript_projection_authority": "shadow_read_only",
            "gateway_prepare_authority": "prepare_only_no_model_call",
            "write_result_schema": xhub_memory::MEMORY_WRITE_RESULT_SCHEMA,
            "retrieval_result_schema": xhub_memory::MEMORY_RETRIEVAL_RESULT_SCHEMA,
        },
        "skills": {
            "skills_dir": skills_dir.display().to_string(),
            "skills_dir_exists": skills_dir_exists,
            "skill_manifest_count": skill_manifest_count,
            "accepted_skill_count": skills_catalog.accepted_count(),
            "blocked_skill_count": skills_catalog.blocked_count(),
            "issue_count": skills_catalog.issues.len(),
            "authority": if skills_execution_authority { "RustExecutionAuthority".to_string() } else { format!("{:?}", skill_boundary.authority) },
            "hub_executes_third_party_code": skill_boundary.hub_executes_third_party_code,
            "requires_pin_or_grant": skill_boundary.requires_pin_or_grant,
            "execution_policy": if skills_execution_authority { "preflight_policy_execute" } else { "policy_gate_only" },
            "execution_authority_in_rust": skills_execution_authority,
            "catalog_shadow_http": true,
            "preflight_shadow_http": true,
            "execute_http": true,
            "audit_shadow_http": true,
            "policy_revoke_http": true,
            "policy_events_http": true,
            "policy_events_prune_http": true,
            "policy_store_readiness_http": true,
            "catalog_schema": SKILL_CATALOG_SCHEMA,
            "readiness_schema": SKILL_READINESS_SCHEMA,
            "preflight_schema": SKILL_PREFLIGHT_SCHEMA,
            "preflight_audit_schema": SKILL_PREFLIGHT_AUDIT_SCHEMA,
            "preflight_audit_summary_schema": SKILL_PREFLIGHT_AUDIT_SUMMARY_SCHEMA,
            "policy_events_schema": SKILL_POLICY_EVENTS_SCHEMA,
            "policy_events_prune_schema": SKILL_POLICY_EVENTS_PRUNE_SCHEMA,
            "policy_store_readiness_schema": SKILL_POLICY_STORE_READINESS_SCHEMA,
            "ready": skills_catalog_ok,
        },
        "capabilities": {
            "scheduler_status_http": true,
            "scheduler_authority_http_opt_in": true,
            "scheduler_authority_in_rust": scheduler_authority,
            "provider_route_http": true,
            "provider_key_pools_http": true,
            "provider_key_runtime_snapshot_http": true,
            "provider_key_import_http": true,
            "provider_openai_quota_plan_http": true,
            "provider_openai_quota_apply_http": true,
            "provider_openai_quota_failure_http": true,
            "provider_oauth_refresh_apply_http": true,
            "provider_oauth_refresh_failure_http": true,
            "provider_oauth_refresh_codex_plan_http": true,
            "provider_oauth_refresh_codex_http": true,
            "account_portfolio_snapshot_in_rust": true,
            "quota_refresh_scheduler_in_rust": true,
            "quota_refresh_state_writer_in_rust": true,
            "provider_route_authority_in_rust": provider_route_authority,
            "model_inventory_http": true,
            "model_local_capabilities_http": true,
            "model_concurrency_policy_http": true,
            "model_local_repair_plan_http": true,
            "model_local_repair_apply_http": true,
            "model_local_repair_jobs_http": true,
            "model_route_diagnostics_http": true,
            "model_route_authority_in_rust": model_route_authority,
            "local_ml_execution_bridge_http": true,
            "ml_execution_authority_in_rust": local_ml_readiness.ready,
            "ml_execution_authority_enabled": local_ml_readiness.enabled,
            "http_backpressure": true,
            "http_metrics": true,
            "http_metrics_recent_window": true,
            "http_io_timeouts": true,
            "remote_entry_candidates_http": true,
            "swift_shell_remote_entry_authority": true,
            "memory_retrieval_http": true,
            "memory_write_http": true,
            "memory_gateway_prepare_http": true,
            "memory_role_transcript_projection_http": true,
            "memory_writer_authority_in_rust": memory_writer_authority,
            "xt_classic_hub_compat_preflight_http": true,
            "xt_classic_hub_grpc_probe_http": true,
            "xt_classic_hub_compat_authority": "preflight_only",
            "xt_classic_hub_status_writer_http": true,
            "xt_classic_hub_status_writer_authority": "explicit_cutover_only",
            "xt_file_ipc_runtime_authority_sync_http": true,
            "xt_file_ipc_shadow_responder_http": true,
            "xt_file_ipc_shadow_drain_http": true,
            "xt_file_ipc_shadow_cycle_http": true,
            "xt_file_ipc_shadow_supervise_http": true,
            "xt_file_ipc_shadow_watcher_smoke_http": true,
            "xt_file_ipc_shadow_watcher_rollback_smoke_http": true,
            "xt_file_ipc_shadow_watcher_readiness_http": true,
            "xt_file_ipc_shadow_watcher_start_plan_http": true,
            "xt_file_ipc_shadow_watcher_run_once_http": true,
            "xt_file_ipc_shadow_watcher_session_http": true,
            "xt_file_ipc_shadow_watcher_background_lifecycle_http": true,
            "xt_file_ipc_shadow_runtime_execution_plan_http": true,
            "xt_file_ipc_shadow_runtime_adapter_candidate_http": true,
            "xt_file_ipc_shadow_authority": if xt_file_ipc_production_authority { "production_status_writer" } else { "temp_dir_only_fail_closed" },
            "xt_file_ipc_production_surface_ready": xt_file_ipc_production_surface_ready,
            "xt_file_ipc_production_authority_in_rust": xt_file_ipc_production_authority,
            "xt_classic_hub_status_writer_heartbeat": xt_file_ipc_production_surface_ready,
            "readiness_cache_http": readiness_cache_ttl_ms > 0,
            "memory_snapshot_cache_http": env_u128_in_range("XHUB_RUST_MEMORY_SNAPSHOT_CACHE_TTL_MS", 500, 0, 10_000) > 0,
            "skills_catalog_cache_http": env_u128_in_range("XHUB_RUST_SKILLS_CATALOG_CACHE_TTL_MS", 500, 0, 10_000) > 0,
            "skills_catalog_http": true,
            "skills_preflight_http": true,
            "skills_execute_http": true,
            "skills_execution_authority_in_rust": skills_execution_authority,
            "skills_audit_http": true,
            "skills_policy_revoke_http": true,
            "skills_policy_events_http": true,
            "skills_policy_events_prune_http": true,
            "skills_policy_store_readiness_http": true,
            "cross_network_ready": cross_network_ready,
            "cross_network_public_endpoint": public_endpoint_enabled,
            "domain_public_endpoint_ready": public_endpoint_ready,
            "cross_network_auth_gate": true,
        },
        "checks": [
            {"name": "proto", "ok": proto_ok, "blocking": true},
            {"name": "canonical_proto", "ok": canonical_proto_ok, "blocking": true},
            {"name": "sqlite_parent", "ok": db_parent_ok, "blocking": true},
            {"name": "scheduler_view", "ok": scheduler_ok, "blocking": true},
            {"name": "network_bind_policy", "ok": bind_policy_ok, "blocking": true},
            {"name": "http_access_key", "ok": http_access_key_ok, "blocking": true},
            {"name": "runtime_base_dir", "ok": runtime_exists, "blocking": false},
            {"name": "memory_dir", "ok": memory_dir_exists, "blocking": true},
            {"name": "skills_dir", "ok": skills_dir_exists, "blocking": true},
            {"name": "skills_catalog", "ok": skills_catalog_ok, "blocking": true},
            {"name": "local_ml_execution_authority", "ok": !local_ml_readiness.enabled || local_ml_readiness.ready, "blocking": local_ml_readiness.enabled},
            {"name": "memory_policy", "ok": memory_plan.fail_closed, "blocking": false},
            {"name": "skills_policy", "ok": !skill_boundary.hub_executes_third_party_code, "blocking": false},
        ],
    });
    format!("{body}\n")
}

pub(crate) fn scheduler_status_json() -> String {
    let snapshot = SchedulerSnapshot::shadow_empty();
    format!(
        "{{\"schema_version\":\"{}\",\"source\":\"{}\",\"captured_at_ms\":{},\"in_flight_total\":{},\"queue_depth\":{},\"oldest_queued_ms\":{}}}\n",
        snapshot.schema_version,
        snapshot.source,
        snapshot.captured_at_ms,
        snapshot.in_flight_total,
        snapshot.queue_depth,
        snapshot.oldest_queued_ms
    )
}
