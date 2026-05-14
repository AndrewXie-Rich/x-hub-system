use std::env;
use std::fs::{self, OpenOptions};
use std::io::{Seek, SeekFrom, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::path::{Path, PathBuf};
use std::process;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use std::time::Duration;

use serde_json::{json, Value};
use tonic::transport::Endpoint;
use xhub_contract::proto::{self, hub_runtime_client::HubRuntimeClient};
use xhub_core::{now_ms, path_exists, HubConfig};

const SCHEMA_XT_CLASSIC_COMPAT_V1: &str = "xhub.rust_hub.xt_classic_compat.v1";
static STATUS_WRITE_LOCK: Mutex<()> = Mutex::new(());
static STATUS_TMP_COUNTER: AtomicU64 = AtomicU64::new(1);
static LIVE_STATUS_CACHE: Mutex<Option<Value>> = Mutex::new(None);

#[derive(Clone, Debug)]
struct XtClassicCompatInput {
    root_dir: PathBuf,
    http_addr: String,
    home_dir: PathBuf,
    now_ms: u128,
    compat_enabled: bool,
    scan_local_files_enabled: bool,
    status_writer_enabled: bool,
    status_writer_heartbeat_enabled: bool,
    status_ttl_ms: u128,
    status_writer_lease_ms: u128,
    status_path_override: Option<PathBuf>,
    base_dir_override: Option<PathBuf>,
    grpc_probe_enabled: bool,
    grpc_host: String,
    grpc_port: u16,
    grpc_probe_timeout_ms: u64,
    grpc_mtls_transport_fallback_enabled: bool,
    rollback_contract_enabled: bool,
    status_writer_apply_enabled: bool,
    file_ipc_surface_ready: bool,
    production_cutover_authorized: bool,
}

impl XtClassicCompatInput {
    fn from_config(config: &HubConfig) -> Self {
        Self {
            root_dir: config.root_dir.clone(),
            http_addr: config.http_addr(),
            home_dir: env_path("HOME").unwrap_or_else(|| config.root_dir.clone()),
            now_ms: now_ms(),
            compat_enabled: env_bool("XHUB_RUST_XT_CLASSIC_COMPAT", false),
            scan_local_files_enabled: env_bool("XHUB_RUST_XT_CLASSIC_SCAN_LOCAL_FILES", false),
            status_writer_enabled: env_bool("XHUB_RUST_XT_CLASSIC_STATUS_WRITER", false),
            status_writer_heartbeat_enabled: env_bool(
                "XHUB_RUST_XT_CLASSIC_STATUS_WRITER_HEARTBEAT",
                false,
            ),
            status_ttl_ms: env_u128_in_range(
                "XHUB_RUST_XT_CLASSIC_STATUS_TTL_MS",
                5_000,
                500,
                60_000,
            ),
            status_writer_lease_ms: env_u128_in_range(
                "XHUB_RUST_XT_CLASSIC_STATUS_WRITER_LEASE_MS",
                2_000,
                0,
                10_000,
            ),
            status_path_override: env_path("XHUB_RUST_XT_CLASSIC_HUB_STATUS_PATH"),
            base_dir_override: env_path("XHUB_RUST_XT_CLASSIC_HUB_BASE_DIR"),
            grpc_probe_enabled: env_bool("XHUB_RUST_XT_CLASSIC_GRPC_PROBE", false),
            grpc_host: env::var("XHUB_RUST_XT_CLASSIC_GRPC_HOST")
                .ok()
                .map(|value| value.trim().to_string())
                .filter(|value| !value.is_empty())
                .unwrap_or_else(|| config.host.clone()),
            grpc_port: env_u16_in_range(
                "XHUB_RUST_XT_CLASSIC_GRPC_PORT",
                config.grpc_port,
                1,
                65_535,
            ),
            grpc_probe_timeout_ms: env_u128_in_range(
                "XHUB_RUST_XT_CLASSIC_GRPC_PROBE_TIMEOUT_MS",
                250,
                50,
                5_000,
            ) as u64,
            grpc_mtls_transport_fallback_enabled: env_bool(
                "XHUB_RUST_XT_CLASSIC_GRPC_MTLS_TRANSPORT_FALLBACK",
                false,
            ),
            rollback_contract_enabled: env_bool("XHUB_RUST_XT_CLASSIC_ROLLBACK_CONTRACT", false),
            status_writer_apply_enabled: env_bool(
                "XHUB_RUST_XT_CLASSIC_STATUS_WRITER_APPLY",
                false,
            ),
            file_ipc_surface_ready: env_bool("XHUB_RUST_XT_CLASSIC_FILE_IPC_READY", false),
            production_cutover_authorized: env_bool(
                "XHUB_RUST_XT_CLASSIC_PRODUCTION_CUTOVER",
                false,
            ),
        }
    }
}

#[derive(Clone, Debug)]
struct GrpcCompatProbe {
    enabled: bool,
    ok: bool,
    endpoint: String,
    timeout_ms: u64,
    service: &'static str,
    method: &'static str,
    error_code: &'static str,
    error_message: String,
    mtls_transport_fallback: bool,
    tcp_reachable: bool,
    paid_ai_seen: bool,
    updated_at_ms: i64,
    queue_depth: i32,
    in_flight_total: i32,
}

pub fn classic_hub_compat_json(config: &HubConfig) -> String {
    let input = XtClassicCompatInput::from_config(config);
    let value = classic_hub_compat_value(&input);
    format!("{value}\n")
}

pub fn classic_hub_status_write_http_json(
    config: &HubConfig,
    method: &str,
) -> (&'static str, String) {
    if method != "POST" {
        return (
            "405 Method Not Allowed",
            format!(
                "{}\n",
                json!({
                    "schema_version": "xhub.rust_hub.xt_classic_status_write.v1",
                    "ok": false,
                    "wrote": false,
                    "deny_code": "method_not_allowed",
                    "required_method": "POST",
                    "production_authority_change": false,
                })
            ),
        );
    }
    let input = XtClassicCompatInput::from_config(config);
    let value = classic_hub_status_write_value(&input);
    let status = if value.get("ok").and_then(Value::as_bool).unwrap_or(false) {
        "200 OK"
    } else {
        "409 Conflict"
    };
    (status, format!("{value}\n"))
}

pub fn classic_hub_status_write_heartbeat_once(config: &HubConfig) -> bool {
    let input = XtClassicCompatInput::from_config(config);
    let value = classic_hub_status_heartbeat_value_at(&input, None);
    value.get("ok").and_then(Value::as_bool).unwrap_or(false)
        && value.get("wrote").and_then(Value::as_bool).unwrap_or(false)
}

pub fn classic_hub_status_write_trusted_heartbeat_once(config: &HubConfig) -> bool {
    let input = XtClassicCompatInput::from_config(config);
    let value = classic_hub_status_trusted_heartbeat_value_at(&input, None);
    value.get("ok").and_then(Value::as_bool).unwrap_or(false)
        && value.get("wrote").and_then(Value::as_bool).unwrap_or(false)
}

pub fn classic_hub_production_surface_ready(config: &HubConfig) -> bool {
    let input = XtClassicCompatInput::from_config(config);
    let candidates = candidate_base_dirs(&input);
    let Some(preferred_status_path) = input.status_path_override.clone().or_else(|| {
        candidates
            .first()
            .map(|base_dir| base_dir.join("hub_status.json"))
    }) else {
        return false;
    };
    let preferred_parent_ok = input.scan_local_files_enabled
        && preferred_status_parent_ok(&input, &preferred_status_path);
    let active_rust_status = input.scan_local_files_enabled
        && read_preferred_status_with_freshness_repair(&input, &preferred_status_path)
            .as_ref()
            .map(|status| raw_status_xt_live(&input, status) && status_is_rust_owned(status))
            .unwrap_or(false);

    input.compat_enabled
        && input.status_writer_enabled
        && input.status_writer_apply_enabled
        && input.status_writer_heartbeat_enabled
        && input.file_ipc_surface_ready
        && input.production_cutover_authorized
        && input.rollback_contract_enabled
        && preferred_parent_ok
        && active_rust_status
}

fn classic_hub_compat_value(input: &XtClassicCompatInput) -> Value {
    let candidates = candidate_base_dirs(input);
    let preferred_status_path = input
        .status_path_override
        .clone()
        .unwrap_or_else(|| candidates[0].join("hub_status.json"));
    let preferred_parent_ok =
        input.scan_local_files_enabled && preferred_status_parent_ok(input, &preferred_status_path);
    let preferred_raw_status = if input.scan_local_files_enabled {
        read_preferred_status_with_freshness_repair(input, &preferred_status_path)
    } else {
        None
    };
    let preferred_raw_live = preferred_raw_status
        .as_ref()
        .map(|status| raw_status_xt_live(input, status))
        .unwrap_or(false);
    let preferred_raw_rust_owned = preferred_raw_status
        .as_ref()
        .map(status_is_rust_owned)
        .unwrap_or(false);
    let preferred_raw_fast_path = preferred_raw_live
        && preferred_raw_rust_owned
        && input.compat_enabled
        && input.status_writer_enabled
        && input.status_writer_apply_enabled
        && input.status_writer_heartbeat_enabled
        && input.grpc_probe_enabled
        && input.rollback_contract_enabled
        && input.file_ipc_surface_ready
        && input.production_cutover_authorized;
    let statuses = if preferred_raw_fast_path {
        let preferred_base_dir = preferred_status_path
            .parent()
            .map(PathBuf::from)
            .unwrap_or_else(|| candidates[0].clone());
        vec![status_summary_from_raw(
            input,
            &preferred_base_dir,
            &preferred_status_path,
            preferred_raw_status.as_ref().expect("preferred raw status"),
        )]
    } else {
        candidates
            .iter()
            .map(|base_dir| status_summary(input, base_dir))
            .collect::<Vec<_>>()
    };
    let active_status = statuses.iter().find(|status| {
        status
            .get("xt_live")
            .and_then(Value::as_bool)
            .unwrap_or(false)
    });
    let active_rust_hub = active_status.map(status_is_rust_owned).unwrap_or(false);
    let active_classic_hub = active_status.is_some() && !active_rust_hub;
    let rust_owned_live_fast_path =
        rust_owned_live_status_fast_path_enabled(input, active_rust_hub);
    let grpc_probe = if rust_owned_live_fast_path {
        rust_owned_live_status_grpc_probe(input)
    } else {
        grpc_compat_probe(input)
    };
    let grpc_compat_ready = grpc_probe.ok;
    let status_writer_implemented = true;
    let rollback_contract_ready = input.rollback_contract_enabled;
    let file_ipc_surface_ready = input.file_ipc_surface_ready;
    let production_cutover_authorized = input.production_cutover_authorized;
    let can_mark_xt_hub_interactive = input.compat_enabled
        && input.status_writer_enabled
        && status_writer_implemented
        && input.status_writer_apply_enabled
        && preferred_parent_ok
        && !active_classic_hub
        && grpc_compat_ready
        && rollback_contract_ready
        && file_ipc_surface_ready
        && production_cutover_authorized;
    let safe_to_prepare_bridge = input.compat_enabled && preferred_parent_ok && !active_classic_hub;
    let deny_code = deny_code(
        input.compat_enabled,
        input.status_writer_enabled,
        preferred_parent_ok,
        active_classic_hub,
        grpc_probe.enabled,
        grpc_compat_ready,
        status_writer_implemented,
        rollback_contract_ready,
        input.status_writer_apply_enabled,
        file_ipc_surface_ready,
        production_cutover_authorized,
    );

    json!({
        "schema_version": SCHEMA_XT_CLASSIC_COMPAT_V1,
        "ok": true,
        "ready": can_mark_xt_hub_interactive,
        "generated_at_ms": input.now_ms.min(i64::MAX as u128) as i64,
        "mode": "preflight_only",
        "http_addr": input.http_addr,
        "root_dir": input.root_dir.display().to_string(),
        "deny_code": deny_code,
        "safe_to_prepare_bridge": safe_to_prepare_bridge,
        "can_mark_xt_hub_interactive": can_mark_xt_hub_interactive,
        "xt_contract": {
            "classic_hub_status_filename": "hub_status.json",
            "classic_hub_runtime_status_filename": "ai_runtime_status.json",
            "candidate_order_matches_xt_hub_paths": true,
            "preferred_status_path": preferred_status_path.display().to_string(),
            "preferred_status_parent_ok": preferred_parent_ok,
            "status_scan_enabled": input.scan_local_files_enabled,
            "status_ttl_ms": input.status_ttl_ms,
            "status_writer_implemented": status_writer_implemented,
            "status_writer_apply_enabled": input.status_writer_apply_enabled,
            "rollback_contract_ready": rollback_contract_ready,
            "file_ipc_surface_ready": file_ipc_surface_ready,
            "production_cutover_authorized": production_cutover_authorized,
            "base_dir_override_configured": input.base_dir_override.is_some(),
            "status_path_override_configured": input.status_path_override.is_some(),
            "candidate_statuses": statuses,
            "active_classic_hub": active_status.cloned().unwrap_or_else(|| json!(null)),
            "active_rust_hub": active_rust_hub,
        },
        "rollback": rollback_contract_json(input),
        "status_writer": {
            "implemented": status_writer_implemented,
            "apply_enabled": input.status_writer_apply_enabled,
            "method": "POST",
            "endpoint": "/xt/classic-hub-compat/write-status",
            "writes_on_preflight_get": live_cutover_status_overlay_allowed(input),
            "preflight_get_write_scope": "stale_or_missing_rust_owned_live_status_repair_only",
            "requires_file_ipc_surface": true,
            "requires_production_cutover_authorization": true,
            "planned_status_path": preferred_status_path.display().to_string(),
            "planned_base_dir": preferred_status_path.parent().map(|path| path.display().to_string()).unwrap_or_default(),
            "planned_ipc_mode": "file",
            "planned_ipc_path": preferred_status_path.parent().map(|path| path.join("ipc_events").display().to_string()).unwrap_or_default(),
            "can_write_now": can_mark_xt_hub_interactive,
        },
        "grpc_compat": {
            "probe_enabled": grpc_probe.enabled,
            "probe_ok": grpc_probe.ok,
            "probe_skipped_for_rust_owned_live_status": rust_owned_live_fast_path,
            "endpoint": grpc_probe.endpoint,
            "timeout_ms": grpc_probe.timeout_ms,
            "service": grpc_probe.service,
            "method": grpc_probe.method,
            "error_code": grpc_probe.error_code,
            "error_message": grpc_probe.error_message,
            "mtls_transport_fallback": grpc_probe.mtls_transport_fallback,
            "tcp_reachable": grpc_probe.tcp_reachable,
            "paid_ai_seen": grpc_probe.paid_ai_seen,
            "updated_at_ms": grpc_probe.updated_at_ms,
            "queue_depth": grpc_probe.queue_depth,
            "in_flight_total": grpc_probe.in_flight_total,
        },
        "authority": {
            "production_authority_change": false,
            "production_authority_change_if_written": can_mark_xt_hub_interactive,
            "node_remains_authority": true,
            "rust_writes_classic_hub_status": false,
            "rust_starts_grpc_compat": false,
            "rust_grpc_compat_probe_ready": grpc_probe.ok,
            "rust_executes_ml": false,
            "rust_executes_third_party_skills": false,
            "memory_writer_authority_in_rust": false,
        },
        "checks": [
            {"name": "xt_classic_compat_opt_in", "ok": input.compat_enabled, "blocking": true},
            {"name": "classic_status_scan_enabled", "ok": input.scan_local_files_enabled, "blocking": true},
            {"name": "classic_status_writer_enabled", "ok": input.status_writer_enabled, "blocking": true},
            {"name": "preferred_status_parent", "ok": preferred_parent_ok, "blocking": true},
            {"name": "classic_hub_not_already_running", "ok": !active_classic_hub, "blocking": true},
            {"name": "grpc_compat_probe_enabled", "ok": grpc_probe.enabled, "blocking": true},
            {"name": "grpc_compat_ready", "ok": grpc_compat_ready, "blocking": true},
            {"name": "classic_status_writer_implemented", "ok": status_writer_implemented, "blocking": true},
            {"name": "rollback_contract_ready", "ok": rollback_contract_ready, "blocking": true},
            {"name": "classic_status_writer_apply_enabled", "ok": input.status_writer_apply_enabled, "blocking": true},
            {"name": "classic_file_ipc_surface_ready", "ok": file_ipc_surface_ready, "blocking": true},
            {"name": "production_cutover_authorized", "ok": production_cutover_authorized, "blocking": true},
            {"name": "production_authority_unchanged", "ok": true, "blocking": false},
            {"name": "no_ml_execution_in_rust", "ok": true, "blocking": false},
            {"name": "no_skill_execution_in_rust", "ok": true, "blocking": false}
        ],
    })
}

fn grpc_compat_probe(input: &XtClassicCompatInput) -> GrpcCompatProbe {
    let endpoint = grpc_endpoint(input.grpc_host.as_str(), input.grpc_port);
    let mut probe = GrpcCompatProbe {
        enabled: input.grpc_probe_enabled,
        ok: false,
        endpoint: endpoint.clone(),
        timeout_ms: input.grpc_probe_timeout_ms,
        service: "HubRuntime",
        method: "GetSchedulerStatus",
        error_code: "",
        error_message: String::new(),
        mtls_transport_fallback: false,
        tcp_reachable: false,
        paid_ai_seen: false,
        updated_at_ms: 0,
        queue_depth: 0,
        in_flight_total: 0,
    };
    if !input.grpc_probe_enabled {
        probe.error_code = "grpc_compat_probe_disabled";
        return probe;
    }

    match run_scheduler_status_probe(endpoint, Duration::from_millis(input.grpc_probe_timeout_ms)) {
        Ok(response) => {
            if let Some(paid_ai) = response.paid_ai {
                probe.ok = true;
                probe.paid_ai_seen = true;
                probe.updated_at_ms = paid_ai.updated_at_ms;
                probe.queue_depth = paid_ai.queue_depth;
                probe.in_flight_total = paid_ai.in_flight_total;
            } else {
                probe.error_code = "grpc_compat_missing_paid_ai";
            }
        }
        Err(error) => {
            let tcp_reachable = grpc_tcp_reachable(
                input.grpc_host.as_str(),
                input.grpc_port,
                Duration::from_millis(input.grpc_probe_timeout_ms),
            );
            probe.tcp_reachable = tcp_reachable;
            if input.grpc_mtls_transport_fallback_enabled
                && input.production_cutover_authorized
                && input.file_ipc_surface_ready
                && tcp_reachable
                && error.contains("transport error")
            {
                probe.ok = true;
                probe.error_code = "grpc_compat_mtls_transport_reachable";
                probe.error_message = error;
                probe.mtls_transport_fallback = true;
            } else {
                probe.error_code = "grpc_compat_probe_failed";
                probe.error_message = error;
            }
        }
    }
    probe
}

fn rust_owned_live_status_fast_path_enabled(
    input: &XtClassicCompatInput,
    active_rust_hub: bool,
) -> bool {
    active_rust_hub
        && input.compat_enabled
        && input.scan_local_files_enabled
        && input.status_writer_enabled
        && input.status_writer_apply_enabled
        && input.status_writer_heartbeat_enabled
        && input.grpc_probe_enabled
        && input.rollback_contract_enabled
        && input.file_ipc_surface_ready
        && input.production_cutover_authorized
}

fn rust_owned_live_status_grpc_probe(input: &XtClassicCompatInput) -> GrpcCompatProbe {
    GrpcCompatProbe {
        enabled: true,
        ok: true,
        endpoint: grpc_endpoint(input.grpc_host.as_str(), input.grpc_port),
        timeout_ms: input.grpc_probe_timeout_ms,
        service: "HubRuntime",
        method: "GetSchedulerStatus",
        error_code: "grpc_compat_probe_skipped_rust_owned_live_status",
        error_message: "rust_owned_live_status_already_active".to_string(),
        mtls_transport_fallback: false,
        tcp_reachable: false,
        paid_ai_seen: false,
        updated_at_ms: 0,
        queue_depth: 0,
        in_flight_total: 0,
    }
}

fn classic_hub_status_write_value(input: &XtClassicCompatInput) -> Value {
    let candidates = candidate_base_dirs(input);
    let preferred_status_path = input
        .status_path_override
        .clone()
        .unwrap_or_else(|| candidates[0].join("hub_status.json"));
    let preferred_parent = preferred_status_path.parent().map(PathBuf::from);
    let preferred_parent_ok = if input.scan_local_files_enabled {
        preferred_status_parent_ok(input, &preferred_status_path)
    } else {
        false
    };
    let statuses = candidates
        .iter()
        .map(|base_dir| status_summary(input, base_dir))
        .collect::<Vec<_>>();
    let active_status = statuses.iter().find(|status| {
        status
            .get("xt_live")
            .and_then(Value::as_bool)
            .unwrap_or(false)
    });
    let active_rust_hub = active_status.map(status_is_rust_owned).unwrap_or(false);
    let active_classic_hub = active_status.is_some() && !active_rust_hub;
    let grpc_probe = grpc_compat_probe(input);
    let status_writer_implemented = true;
    let rollback_contract_ready = input.rollback_contract_enabled;
    let deny_code = deny_code(
        input.compat_enabled,
        input.status_writer_enabled,
        preferred_parent_ok,
        active_classic_hub,
        grpc_probe.enabled,
        grpc_probe.ok,
        status_writer_implemented,
        rollback_contract_ready,
        input.status_writer_apply_enabled,
        input.file_ipc_surface_ready,
        input.production_cutover_authorized,
    );
    let can_write = deny_code.is_empty();
    let base_dir = preferred_parent.unwrap_or_else(|| input.root_dir.clone());
    let ipc_path = base_dir.join("ipc_events");
    let planned_status = planned_hub_status_json(input, &base_dir, &ipc_path);
    let mut write_error = String::new();
    let wrote = if can_write {
        match write_status_file(
            &preferred_status_path,
            &ipc_path,
            planned_status.to_string(),
        ) {
            Ok(()) => true,
            Err(error) => {
                write_error = error;
                false
            }
        }
    } else {
        false
    };
    let ok = can_write && wrote;
    if ok {
        remember_live_status(&planned_status);
    }
    let final_deny_code = if ok {
        ""
    } else if !write_error.is_empty() {
        "classic_status_write_failed"
    } else {
        deny_code
    };

    json!({
        "schema_version": "xhub.rust_hub.xt_classic_status_write.v1",
        "ok": ok,
        "wrote": wrote,
        "generated_at_ms": input.now_ms.min(i64::MAX as u128) as i64,
        "deny_code": final_deny_code,
        "error_message": write_error,
        "status_path": preferred_status_path.display().to_string(),
        "base_dir": base_dir.display().to_string(),
        "ipc_mode": "file",
        "ipc_path": ipc_path.display().to_string(),
        "rollback": rollback_contract_json(input),
        "status": planned_status,
        "grpc_compat": {
            "probe_enabled": grpc_probe.enabled,
            "probe_ok": grpc_probe.ok,
            "endpoint": grpc_probe.endpoint,
            "timeout_ms": grpc_probe.timeout_ms,
            "service": grpc_probe.service,
            "method": grpc_probe.method,
            "error_code": grpc_probe.error_code,
            "error_message": grpc_probe.error_message,
            "mtls_transport_fallback": grpc_probe.mtls_transport_fallback,
            "tcp_reachable": grpc_probe.tcp_reachable,
            "paid_ai_seen": grpc_probe.paid_ai_seen,
        },
        "checks": [
            {"name": "xt_classic_compat_opt_in", "ok": input.compat_enabled, "blocking": true},
            {"name": "classic_status_scan_enabled", "ok": input.scan_local_files_enabled, "blocking": true},
            {"name": "classic_status_writer_enabled", "ok": input.status_writer_enabled, "blocking": true},
            {"name": "preferred_status_parent", "ok": preferred_parent_ok, "blocking": true},
            {"name": "classic_hub_not_already_running", "ok": !active_classic_hub, "blocking": true},
            {"name": "grpc_compat_probe_enabled", "ok": grpc_probe.enabled, "blocking": true},
            {"name": "grpc_compat_ready", "ok": grpc_probe.ok, "blocking": true},
            {"name": "rollback_contract_ready", "ok": rollback_contract_ready, "blocking": true},
            {"name": "classic_status_writer_apply_enabled", "ok": input.status_writer_apply_enabled, "blocking": true},
            {"name": "classic_file_ipc_surface_ready", "ok": input.file_ipc_surface_ready, "blocking": true},
            {"name": "production_cutover_authorized", "ok": input.production_cutover_authorized, "blocking": true}
        ],
        "authority": {
            "production_authority_change": ok,
            "node_remains_authority": !ok,
            "rust_writes_classic_hub_status": ok,
            "rust_executes_ml": false,
            "rust_executes_third_party_skills": false,
            "memory_writer_authority_in_rust": false,
        },
    })
}

#[cfg(test)]
fn classic_hub_status_heartbeat_value(input: &XtClassicCompatInput) -> Value {
    classic_hub_status_heartbeat_value_at(input, Some(input.now_ms))
}

fn classic_hub_status_heartbeat_value_at(
    input: &XtClassicCompatInput,
    write_now_ms: Option<u128>,
) -> Value {
    let candidates = candidate_base_dirs(input);
    let preferred_status_path = input
        .status_path_override
        .clone()
        .unwrap_or_else(|| candidates[0].join("hub_status.json"));
    let preferred_parent = preferred_status_path.parent().map(PathBuf::from);
    let preferred_parent_ok = if input.scan_local_files_enabled {
        preferred_status_parent_ok(input, &preferred_status_path)
    } else {
        false
    };
    let preferred_status = if input.scan_local_files_enabled {
        read_json(&preferred_status_path)
    } else {
        None
    };
    let preferred_live = preferred_status
        .as_ref()
        .map(|status| raw_status_xt_live(input, status))
        .unwrap_or(false);
    let preferred_rust_owned = preferred_status
        .as_ref()
        .map(status_is_rust_owned)
        .unwrap_or(false);
    let active_classic_hub = preferred_live && !preferred_rust_owned;
    let active_rust_hub = preferred_live && preferred_rust_owned;
    let rust_owned_status_available = active_rust_hub || preferred_rust_owned;
    let deny_code = heartbeat_deny_code(
        input.compat_enabled,
        input.status_writer_enabled,
        input.status_writer_heartbeat_enabled,
        preferred_parent_ok,
        active_classic_hub,
        input.rollback_contract_enabled,
        input.status_writer_apply_enabled,
        input.file_ipc_surface_ready,
        input.production_cutover_authorized,
        rust_owned_status_available,
    );
    let can_write = deny_code.is_empty();
    let base_dir = preferred_parent.unwrap_or_else(|| input.root_dir.clone());
    let ipc_path = base_dir.join("ipc_events");
    let (wrote, write_error, planned_status, effective_write_now_ms, write_attempts, write_age_ms) =
        if can_write {
            write_planned_status_with_retry(
                input,
                &preferred_status_path,
                &base_dir,
                &ipc_path,
                write_now_ms,
                false,
            )
        } else {
            (
                false,
                String::new(),
                planned_hub_status_json(input, &base_dir, &ipc_path),
                input.now_ms,
                0,
                0,
            )
        };
    let ok = can_write && wrote;
    if ok {
        remember_live_status(&planned_status);
    }
    let final_deny_code = if ok {
        ""
    } else if !write_error.is_empty() {
        "classic_status_heartbeat_write_failed"
    } else {
        deny_code
    };

    json!({
        "schema_version": "xhub.rust_hub.xt_classic_status_heartbeat.v1",
        "ok": ok,
        "wrote": wrote,
        "generated_at_ms": effective_write_now_ms.min(i64::MAX as u128) as i64,
        "deny_code": final_deny_code,
        "error_message": write_error,
        "status_path": preferred_status_path.display().to_string(),
        "base_dir": base_dir.display().to_string(),
        "ipc_mode": "file",
        "ipc_path": ipc_path.display().to_string(),
        "active_classic_hub": active_classic_hub,
        "active_rust_hub": active_rust_hub,
        "preferred_live": preferred_live,
        "preferred_rust_owned": preferred_rust_owned,
        "rust_owned_status_available": rust_owned_status_available,
        "grpc_probe_performed": false,
        "status_scan_mode": "preferred_raw_only",
        "write_attempts": write_attempts,
        "write_age_ms": write_age_ms.min(i64::MAX as u128) as i64,
        "status": planned_status,
        "checks": [
            {"name": "xt_classic_compat_opt_in", "ok": input.compat_enabled, "blocking": true},
            {"name": "classic_status_scan_enabled", "ok": input.scan_local_files_enabled, "blocking": true},
            {"name": "classic_status_writer_enabled", "ok": input.status_writer_enabled, "blocking": true},
            {"name": "classic_status_writer_heartbeat_enabled", "ok": input.status_writer_heartbeat_enabled, "blocking": true},
            {"name": "preferred_status_parent", "ok": preferred_parent_ok, "blocking": true},
            {"name": "classic_hub_not_already_running", "ok": !active_classic_hub, "blocking": true},
            {"name": "rust_owned_status_available", "ok": rust_owned_status_available, "blocking": true},
            {"name": "rollback_contract_ready", "ok": input.rollback_contract_enabled, "blocking": true},
            {"name": "classic_status_writer_apply_enabled", "ok": input.status_writer_apply_enabled, "blocking": true},
            {"name": "classic_file_ipc_surface_ready", "ok": input.file_ipc_surface_ready, "blocking": true},
            {"name": "production_cutover_authorized", "ok": input.production_cutover_authorized, "blocking": true}
        ],
        "authority": {
            "production_authority_change": ok,
            "node_remains_authority": !ok,
            "rust_writes_classic_hub_status": ok,
            "rust_executes_ml": false,
            "rust_executes_third_party_skills": false,
            "memory_writer_authority_in_rust": false,
        },
    })
}

fn classic_hub_status_trusted_heartbeat_value_at(
    input: &XtClassicCompatInput,
    write_now_ms: Option<u128>,
) -> Value {
    let candidates = candidate_base_dirs(input);
    let preferred_status_path = input
        .status_path_override
        .clone()
        .unwrap_or_else(|| candidates[0].join("hub_status.json"));
    let preferred_parent = preferred_status_path.parent().map(PathBuf::from);
    let preferred_parent_ok = if input.scan_local_files_enabled {
        preferred_status_parent_ok(input, &preferred_status_path)
    } else {
        false
    };
    let deny_code = heartbeat_deny_code(
        input.compat_enabled,
        input.status_writer_enabled,
        input.status_writer_heartbeat_enabled,
        preferred_parent_ok,
        false,
        input.rollback_contract_enabled,
        input.status_writer_apply_enabled,
        input.file_ipc_surface_ready,
        input.production_cutover_authorized,
        true,
    );
    let can_write = deny_code.is_empty();
    let base_dir = preferred_parent.unwrap_or_else(|| input.root_dir.clone());
    let ipc_path = base_dir.join("ipc_events");
    let (wrote, write_error, planned_status, effective_write_now_ms, write_attempts, write_age_ms) =
        if can_write {
            write_planned_status_with_retry(
                input,
                &preferred_status_path,
                &base_dir,
                &ipc_path,
                write_now_ms,
                true,
            )
        } else {
            (
                false,
                String::new(),
                planned_hub_status_json(input, &base_dir, &ipc_path),
                input.now_ms,
                0,
                0,
            )
        };
    let ok = can_write && wrote;
    if ok {
        remember_live_status(&planned_status);
    }
    let final_deny_code = if ok {
        ""
    } else if !write_error.is_empty() {
        "classic_status_trusted_heartbeat_write_failed"
    } else {
        deny_code
    };

    json!({
        "schema_version": "xhub.rust_hub.xt_classic_status_trusted_heartbeat.v1",
        "ok": ok,
        "wrote": wrote,
        "generated_at_ms": effective_write_now_ms.min(i64::MAX as u128) as i64,
        "deny_code": final_deny_code,
        "error_message": write_error,
        "status_path": preferred_status_path.display().to_string(),
        "base_dir": base_dir.display().to_string(),
        "ipc_mode": "file",
        "ipc_path": ipc_path.display().to_string(),
        "trusted_after_prior_success": true,
        "status_scan_mode": "trusted_prior_success_no_status_read",
        "grpc_probe_performed": false,
        "write_attempts": write_attempts,
        "write_age_ms": write_age_ms.min(i64::MAX as u128) as i64,
        "status": planned_status,
        "authority": {
            "production_authority_change": ok,
            "node_remains_authority": !ok,
            "rust_writes_classic_hub_status": ok,
            "rust_executes_ml": false,
            "rust_executes_third_party_skills": false,
            "memory_writer_authority_in_rust": false,
        },
    })
}

fn planned_hub_status_json(
    input: &XtClassicCompatInput,
    base_dir: &PathBuf,
    ipc_path: &PathBuf,
) -> Value {
    let now_seconds = (input.now_ms as f64) / 1000.0;
    let lease_now_ms = input
        .now_ms
        .saturating_add(input.status_writer_lease_ms.min(10_000));
    let lease_seconds = (lease_now_ms as f64) / 1000.0;
    json!({
        "pid": process::id(),
        "startedAt": now_seconds,
        "updatedAt": lease_seconds,
        "ipcMode": "file",
        "ipcPath": ipc_path.display().to_string(),
        "baseDir": base_dir.display().to_string(),
        "protocolVersion": 1,
        "aiReady": input.file_ipc_surface_ready,
        "loadedModelCount": 0,
        "modelsUpdatedAt": lease_seconds,
        "rustHub": {
            "schema_version": "xhub.rust_hub.xt_classic_status.v1",
            "http_addr": input.http_addr,
            "grpc_endpoint": grpc_endpoint(input.grpc_host.as_str(), input.grpc_port),
            "authority": "explicit_cutover_only",
            "status_lease_ms": input.status_writer_lease_ms.min(10_000),
        }
    })
}

fn write_planned_status_with_retry(
    input: &XtClassicCompatInput,
    status_path: &PathBuf,
    base_dir: &PathBuf,
    ipc_path: &PathBuf,
    write_now_ms: Option<u128>,
    fast: bool,
) -> (bool, String, Value, u128, usize, u128) {
    let dynamic_time = write_now_ms.is_none();
    let max_attempts = if dynamic_time { 3 } else { 1 };
    let mut effective_write_now_ms = write_now_ms.unwrap_or_else(now_ms);
    let mut planned_status = planned_hub_status_json(input, base_dir, ipc_path);
    let mut final_write_age_ms = 0;

    for attempt in 1..=max_attempts {
        if dynamic_time {
            effective_write_now_ms = now_ms();
        }
        let mut write_input = input.clone();
        write_input.now_ms = effective_write_now_ms;
        planned_status = planned_hub_status_json(&write_input, base_dir, ipc_path);
        let result = if fast {
            write_status_file_fast(status_path, planned_status.to_string())
        } else {
            write_status_file(status_path, ipc_path, planned_status.to_string())
        };
        final_write_age_ms = now_ms().saturating_sub(effective_write_now_ms);
        match result {
            Ok(()) => {
                if !dynamic_time || final_write_age_ms <= 500 {
                    return (
                        true,
                        String::new(),
                        planned_status,
                        effective_write_now_ms,
                        attempt,
                        final_write_age_ms,
                    );
                }
            }
            Err(error) => {
                return (
                    false,
                    error,
                    planned_status,
                    effective_write_now_ms,
                    attempt,
                    final_write_age_ms,
                );
            }
        }
    }

    (
        true,
        String::new(),
        planned_status,
        effective_write_now_ms,
        max_attempts,
        final_write_age_ms,
    )
}

fn write_status_file(
    status_path: &PathBuf,
    ipc_path: &PathBuf,
    status_json: String,
) -> Result<(), String> {
    let _guard = STATUS_WRITE_LOCK
        .lock()
        .map_err(|_| "status_write_lock_poisoned".to_string())?;
    write_status_file_unlocked(status_path, Some(ipc_path), status_json)
}

fn write_status_file_fast(status_path: &PathBuf, status_json: String) -> Result<(), String> {
    let _guard = STATUS_WRITE_LOCK
        .lock()
        .map_err(|_| "status_write_lock_poisoned".to_string())?;
    write_status_file_unlocked(status_path, None, status_json)
}

fn write_status_file_unlocked(
    status_path: &PathBuf,
    ipc_path: Option<&PathBuf>,
    status_json: String,
) -> Result<(), String> {
    let parent = status_path
        .parent()
        .ok_or_else(|| "status_path_parent_missing".to_string())?;
    fs::create_dir_all(parent).map_err(|err| format!("create_status_parent:{err}"))?;
    if let Some(ipc_path) = ipc_path {
        fs::create_dir_all(ipc_path).map_err(|err| format!("create_ipc_dir:{err}"))?;
    }
    let payload = format!("{status_json}\n");
    let tmp_path = temp_status_path(parent);
    if let Err(err) = fs::write(&tmp_path, payload.as_str()) {
        if err.kind() == std::io::ErrorKind::PermissionDenied && status_path.is_file() {
            return write_existing_status_file_in_place(status_path, payload)
                .map_err(|fallback_err| format!("write_temp_status:{err}; {fallback_err}"));
        }
        return Err(format!("write_temp_status:{err}"));
    }
    if let Err(err) = fs::rename(&tmp_path, status_path) {
        let _ = fs::remove_file(&tmp_path);
        if err.kind() == std::io::ErrorKind::PermissionDenied && status_path.is_file() {
            return write_existing_status_file_in_place(status_path, payload)
                .map_err(|fallback_err| format!("rename_status:{err}; {fallback_err}"));
        }
        return Err(format!("rename_status:{err}"));
    }
    Ok(())
}

fn write_existing_status_file_in_place(
    status_path: &PathBuf,
    payload: String,
) -> Result<(), String> {
    let mut file = OpenOptions::new()
        .write(true)
        .open(status_path)
        .map_err(|err| format!("open_existing_status:{err}"))?;
    file.seek(SeekFrom::Start(0))
        .map_err(|err| format!("seek_existing_status:{err}"))?;
    file.write_all(payload.as_bytes())
        .map_err(|err| format!("write_existing_status:{err}"))?;
    file.set_len(payload.len() as u64)
        .map_err(|err| format!("truncate_existing_status:{err}"))?;
    file.flush()
        .map_err(|err| format!("flush_existing_status:{err}"))?;
    Ok(())
}

fn temp_status_path(parent: &Path) -> PathBuf {
    let sequence = STATUS_TMP_COUNTER.fetch_add(1, Ordering::Relaxed);
    parent.join(format!(
        ".hub_status.json.tmp.{}.{}.{}",
        process::id(),
        now_ms(),
        sequence
    ))
}

fn rollback_contract_json(input: &XtClassicCompatInput) -> Value {
    json!({
        "contract_enabled": input.rollback_contract_enabled,
        "ready": input.rollback_contract_enabled,
        "unset_env_vars": [
            "XHUB_RUST_XT_CLASSIC_COMPAT",
            "XHUB_RUST_XT_CLASSIC_SCAN_LOCAL_FILES",
            "XHUB_RUST_XT_CLASSIC_STATUS_WRITER",
            "XHUB_RUST_XT_CLASSIC_STATUS_WRITER_APPLY",
            "XHUB_RUST_XT_CLASSIC_STATUS_WRITER_HEARTBEAT",
            "XHUB_RUST_XT_CLASSIC_STATUS_WRITER_HEARTBEAT_MS",
            "XHUB_RUST_XT_CLASSIC_STATUS_WRITER_LEASE_MS",
            "XHUB_RUST_XT_CLASSIC_GRPC_PROBE",
            "XHUB_RUST_XT_CLASSIC_GRPC_HOST",
            "XHUB_RUST_XT_CLASSIC_GRPC_PORT",
            "XHUB_RUST_XT_CLASSIC_GRPC_PROBE_TIMEOUT_MS",
            "XHUB_RUST_XT_CLASSIC_HUB_BASE_DIR",
            "XHUB_RUST_XT_CLASSIC_HUB_STATUS_PATH",
            "XHUB_RUST_XT_CLASSIC_ROLLBACK_CONTRACT",
            "XHUB_RUST_XT_CLASSIC_FILE_IPC_READY",
            "XHUB_RUST_XT_CLASSIC_PRODUCTION_CUTOVER"
        ],
        "operator_steps": [
            "Unset all XHUB_RUST_XT_CLASSIC_* variables in the daemon profile or launchd environment.",
            "Run `bash tools/xhubd_daemon.command launchd-install --replace-running` to restart the Rust Hub daemon.",
            "Remove only the Rust-owned hub_status.json target if it was written during an explicit cutover trial.",
            "Restart classic X-Hub/RELFlowHub and verify XT reports the classic Hub again."
        ],
        "status_writer_stops_when_unset": true
    })
}

fn run_scheduler_status_probe(
    endpoint: String,
    timeout: Duration,
) -> Result<proto::GetSchedulerStatusResponse, String> {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|err| format!("tokio_runtime:{err}"))?;
    runtime.block_on(async move {
        let endpoint = Endpoint::from_shared(endpoint)
            .map_err(|err| format!("endpoint:{err}"))?
            .connect_timeout(timeout)
            .timeout(timeout);
        let channel = endpoint
            .connect()
            .await
            .map_err(|err| format!("connect:{err}"))?;
        let mut client = HubRuntimeClient::new(channel);
        client
            .get_scheduler_status(proto::GetSchedulerStatusRequest {
                client: None,
                include_queue_items: false,
                queue_items_limit: 0,
            })
            .await
            .map(|response| response.into_inner())
            .map_err(|err| format!("grpc:{err}"))
    })
}

fn grpc_endpoint(host: &str, port: u16) -> String {
    format!("http://{}:{}", grpc_connect_host(host), port)
}

fn grpc_connect_host(host: &str) -> String {
    let trimmed = host.trim();
    if trimmed.is_empty() || trimmed == "0.0.0.0" || trimmed == "::" {
        return "127.0.0.1".to_string();
    }
    if trimmed.contains(':') && !trimmed.starts_with('[') {
        return format!("[{trimmed}]");
    }
    trimmed.to_string()
}

fn grpc_tcp_reachable(host: &str, port: u16, timeout: Duration) -> bool {
    let host = grpc_connect_host(host);
    let addr = format!("{host}:{port}");
    let Ok(addrs) = addr.to_socket_addrs() else {
        return false;
    };
    for addr in addrs {
        if TcpStream::connect_timeout(&addr, timeout).is_ok() {
            return true;
        }
    }
    false
}

fn status_summary(input: &XtClassicCompatInput, base_dir: &PathBuf) -> Value {
    let status_path = base_dir.join("hub_status.json");
    let runtime_status_path = base_dir.join("ai_runtime_status.json");
    if !input.scan_local_files_enabled {
        return json!({
            "base_dir": base_dir.display().to_string(),
            "status_path": status_path.display().to_string(),
            "status_scan_skipped": true,
            "status_exists": false,
            "runtime_status_path": runtime_status_path.display().to_string(),
            "runtime_status_exists": false,
            "pid": 0,
            "has_pid": false,
            "updated_at_ms": 0,
            "age_ms": -1,
            "fresh": false,
            "xt_live": false,
            "base_dir_from_status": "",
            "ipc_mode": "",
            "ipc_path": "",
            "ai_ready": false,
            "loaded_model_count": 0,
        });
    }

    let status = read_json(&status_path);
    let updated_at_ms = status
        .as_ref()
        .and_then(|value| value.get("updatedAt"))
        .and_then(Value::as_f64)
        .map(|seconds| (seconds * 1000.0).max(0.0) as u128)
        .unwrap_or(0);
    let age_ms = if updated_at_ms > 0 {
        input.now_ms.saturating_sub(updated_at_ms)
    } else {
        u128::MAX
    };
    let fresh = updated_at_ms > 0 && age_ms <= input.status_ttl_ms;
    let pid = status
        .as_ref()
        .and_then(|value| value.get("pid"))
        .and_then(Value::as_i64)
        .unwrap_or(0);
    let has_pid = pid > 1;
    let xt_live = fresh && has_pid;

    json!({
        "base_dir": base_dir.display().to_string(),
        "status_path": status_path.display().to_string(),
        "status_exists": status_path.is_file(),
        "runtime_status_path": runtime_status_path.display().to_string(),
        "runtime_status_exists": runtime_status_path.is_file(),
        "pid": pid,
        "has_pid": has_pid,
        "updated_at_ms": updated_at_ms.min(i64::MAX as u128) as i64,
        "age_ms": if age_ms == u128::MAX { -1 } else { age_ms.min(i64::MAX as u128) as i64 },
        "fresh": fresh,
        "xt_live": xt_live,
        "base_dir_from_status": status
            .as_ref()
            .and_then(|value| value.get("baseDir"))
            .and_then(Value::as_str)
            .unwrap_or(""),
        "ipc_mode": status
            .as_ref()
            .and_then(|value| value.get("ipcMode"))
            .and_then(Value::as_str)
            .unwrap_or(""),
        "ipc_path": status
            .as_ref()
            .and_then(|value| value.get("ipcPath"))
            .and_then(Value::as_str)
            .unwrap_or(""),
        "ai_ready": status
            .as_ref()
            .and_then(|value| value.get("aiReady"))
            .and_then(Value::as_bool)
            .unwrap_or(false),
        "loaded_model_count": status
            .as_ref()
            .and_then(|value| value.get("loadedModelCount"))
            .and_then(Value::as_i64)
            .unwrap_or(0),
        "rust_hub_authority": status
            .as_ref()
            .and_then(|value| value.get("rustHub"))
            .and_then(|value| value.get("authority"))
            .and_then(Value::as_str)
            .unwrap_or(""),
        "rust_hub_schema_version": status
            .as_ref()
            .and_then(|value| value.get("rustHub"))
            .and_then(|value| value.get("schema_version"))
            .and_then(Value::as_str)
            .unwrap_or(""),
    })
}

fn status_summary_from_raw(
    input: &XtClassicCompatInput,
    base_dir: &PathBuf,
    status_path: &PathBuf,
    status: &Value,
) -> Value {
    let runtime_status_path = base_dir.join("ai_runtime_status.json");
    let updated_at_ms = status
        .get("updatedAt")
        .and_then(Value::as_f64)
        .map(|seconds| (seconds * 1000.0).max(0.0) as u128)
        .unwrap_or(0);
    let age_ms = if updated_at_ms > 0 {
        input.now_ms.saturating_sub(updated_at_ms)
    } else {
        u128::MAX
    };
    let fresh = updated_at_ms > 0 && age_ms <= input.status_ttl_ms;
    let pid = status.get("pid").and_then(Value::as_i64).unwrap_or(0);
    let has_pid = pid > 1;
    let xt_live = fresh && has_pid;

    json!({
        "base_dir": base_dir.display().to_string(),
        "status_path": status_path.display().to_string(),
        "status_exists": true,
        "runtime_status_path": runtime_status_path.display().to_string(),
        "runtime_status_exists": false,
        "runtime_status_check_skipped": true,
        "pid": pid,
        "has_pid": has_pid,
        "updated_at_ms": updated_at_ms.min(i64::MAX as u128) as i64,
        "age_ms": if age_ms == u128::MAX { -1 } else { age_ms.min(i64::MAX as u128) as i64 },
        "fresh": fresh,
        "xt_live": xt_live,
        "base_dir_from_status": status
            .get("baseDir")
            .and_then(Value::as_str)
            .unwrap_or(""),
        "ipc_mode": status
            .get("ipcMode")
            .and_then(Value::as_str)
            .unwrap_or(""),
        "ipc_path": status
            .get("ipcPath")
            .and_then(Value::as_str)
            .unwrap_or(""),
        "ai_ready": status
            .get("aiReady")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        "loaded_model_count": status
            .get("loadedModelCount")
            .and_then(Value::as_i64)
            .unwrap_or(0),
        "rust_hub_authority": status
            .get("rustHub")
            .and_then(|value| value.get("authority"))
            .and_then(Value::as_str)
            .unwrap_or(""),
        "rust_hub_schema_version": status
            .get("rustHub")
            .and_then(|value| value.get("schema_version"))
            .and_then(Value::as_str)
            .unwrap_or(""),
    })
}

fn status_is_rust_owned(status: &Value) -> bool {
    let summary_owned = status
        .get("rust_hub_authority")
        .and_then(Value::as_str)
        .unwrap_or("")
        == "explicit_cutover_only"
        && status
            .get("rust_hub_schema_version")
            .and_then(Value::as_str)
            .unwrap_or("")
            == "xhub.rust_hub.xt_classic_status.v1";
    let raw_owned = status
        .get("rustHub")
        .and_then(|value| value.get("authority"))
        .and_then(Value::as_str)
        .unwrap_or("")
        == "explicit_cutover_only"
        && status
            .get("rustHub")
            .and_then(|value| value.get("schema_version"))
            .and_then(Value::as_str)
            .unwrap_or("")
            == "xhub.rust_hub.xt_classic_status.v1";
    summary_owned || raw_owned
}

fn read_preferred_status_with_freshness_repair(
    input: &XtClassicCompatInput,
    status_path: &PathBuf,
) -> Option<Value> {
    if let Some(cached_status) = cached_rust_owned_live_status(input, status_path) {
        if raw_status_xt_live(input, &cached_status) {
            return Some(cached_status);
        }
        return repair_stale_rust_owned_status_on_demand(input, status_path)
            .or(Some(cached_status));
    }

    let status = read_json(status_path);
    let Some(raw_status) = status.as_ref() else {
        if can_repair_rust_owned_status(input, status_path) {
            return repair_stale_rust_owned_status_on_demand(input, status_path);
        }
        return status;
    };
    if raw_status_xt_live(input, raw_status) || !status_is_rust_owned(raw_status) {
        return status;
    }
    if !can_repair_rust_owned_status(input, status_path) {
        return status;
    }

    repair_stale_rust_owned_status_on_demand(input, status_path).or(status)
}

fn can_repair_rust_owned_status(input: &XtClassicCompatInput, status_path: &PathBuf) -> bool {
    input.compat_enabled
        && input.scan_local_files_enabled
        && input.status_writer_enabled
        && input.status_writer_apply_enabled
        && input.status_writer_heartbeat_enabled
        && input.rollback_contract_enabled
        && input.file_ipc_surface_ready
        && input.production_cutover_authorized
        && preferred_status_parent_ok(input, status_path)
}

fn preferred_status_parent_ok(input: &XtClassicCompatInput, status_path: &PathBuf) -> bool {
    if input.status_path_override.is_some()
        && input.base_dir_override.is_some()
        && live_cutover_status_overlay_allowed(input)
    {
        return true;
    }
    status_path.parent().map(path_exists).unwrap_or(false)
}

fn live_cutover_status_overlay_allowed(input: &XtClassicCompatInput) -> bool {
    input.compat_enabled
        && input.scan_local_files_enabled
        && input.status_writer_enabled
        && input.status_writer_apply_enabled
        && input.status_writer_heartbeat_enabled
        && input.rollback_contract_enabled
        && input.file_ipc_surface_ready
        && input.production_cutover_authorized
}

fn cached_rust_owned_live_status(
    input: &XtClassicCompatInput,
    status_path: &PathBuf,
) -> Option<Value> {
    if !can_repair_rust_owned_status(input, status_path) {
        return None;
    }
    let status = LIVE_STATUS_CACHE.lock().ok()?.clone()?;
    if !status_is_rust_owned(&status) {
        return None;
    }
    let expected_base_dir = status_path.parent()?.display().to_string();
    let cached_base_dir = status.get("baseDir").and_then(Value::as_str).unwrap_or("");
    if cached_base_dir != expected_base_dir {
        return None;
    }
    Some(status)
}

fn remember_live_status(status: &Value) {
    if !status_is_rust_owned(status) {
        return;
    }
    if let Ok(mut cache) = LIVE_STATUS_CACHE.lock() {
        *cache = Some(status.clone());
    }
}

fn raw_status_xt_live(input: &XtClassicCompatInput, status: &Value) -> bool {
    let updated_at_ms = status
        .get("updatedAt")
        .and_then(Value::as_f64)
        .map(|seconds| (seconds * 1000.0).max(0.0) as u128)
        .unwrap_or(0);
    let fresh =
        updated_at_ms > 0 && input.now_ms.saturating_sub(updated_at_ms) <= input.status_ttl_ms;
    let has_pid = status.get("pid").and_then(Value::as_i64).unwrap_or(0) > 1;
    fresh && has_pid
}

fn repair_stale_rust_owned_status_on_demand(
    input: &XtClassicCompatInput,
    status_path: &PathBuf,
) -> Option<Value> {
    let base_dir = status_path.parent().map(PathBuf::from)?;
    let ipc_path = base_dir.join("ipc_events");
    let mut repair_input = input.clone();
    repair_input.now_ms = now_ms();
    let (wrote, _write_error, written_status, _effective_write_now_ms, _write_attempts, _age_ms) =
        write_planned_status_with_retry(
            &repair_input,
            status_path,
            &base_dir,
            &ipc_path,
            Some(repair_input.now_ms),
            true,
        );
    if !wrote {
        return None;
    }
    remember_live_status(&written_status);
    Some(written_status)
}

fn candidate_base_dirs(input: &XtClassicCompatInput) -> Vec<PathBuf> {
    if let Some(base_dir) = input.base_dir_override.clone() {
        return vec![base_dir];
    }

    let home = &input.home_dir;
    let container_base = home
        .join("Library")
        .join("Containers")
        .join("com.rel.flowhub")
        .join("Data");

    dedupe_paths(vec![
        home.join("Library")
            .join("Group Containers")
            .join("group.rel.flowhub"),
        container_base.join("XHub"),
        container_base.join("RELFlowHub"),
        PathBuf::from("/private/tmp").join("XHub"),
        PathBuf::from("/private/tmp").join("RELFlowHub"),
        home.join("XHub"),
        home.join("RELFlowHub"),
    ])
}

fn dedupe_paths(paths: Vec<PathBuf>) -> Vec<PathBuf> {
    let mut out = Vec::new();
    for path in paths {
        if !out.iter().any(|existing: &PathBuf| existing == &path) {
            out.push(path);
        }
    }
    out
}

fn deny_code(
    compat_enabled: bool,
    status_writer_enabled: bool,
    preferred_parent_ok: bool,
    active_classic_hub: bool,
    grpc_probe_enabled: bool,
    grpc_compat_ready: bool,
    status_writer_implemented: bool,
    rollback_contract_ready: bool,
    status_writer_apply_enabled: bool,
    file_ipc_surface_ready: bool,
    production_cutover_authorized: bool,
) -> &'static str {
    if !compat_enabled {
        "xt_classic_compat_not_enabled"
    } else if !preferred_parent_ok {
        "classic_status_scan_disabled_or_parent_missing"
    } else if !status_writer_enabled {
        "classic_status_writer_disabled"
    } else if active_classic_hub {
        "classic_hub_already_running"
    } else if !grpc_probe_enabled {
        "grpc_compat_probe_disabled"
    } else if !grpc_compat_ready {
        "grpc_compat_not_ready"
    } else if !status_writer_implemented {
        "classic_status_writer_not_implemented"
    } else if !rollback_contract_ready {
        "rollback_contract_not_ready"
    } else if !status_writer_apply_enabled {
        "classic_status_writer_apply_disabled"
    } else if !file_ipc_surface_ready {
        "classic_file_ipc_surface_not_ready"
    } else if !production_cutover_authorized {
        "production_cutover_not_authorized"
    } else {
        ""
    }
}

fn heartbeat_deny_code(
    compat_enabled: bool,
    status_writer_enabled: bool,
    status_writer_heartbeat_enabled: bool,
    preferred_parent_ok: bool,
    active_classic_hub: bool,
    rollback_contract_ready: bool,
    status_writer_apply_enabled: bool,
    file_ipc_surface_ready: bool,
    production_cutover_authorized: bool,
    rust_owned_status_available: bool,
) -> &'static str {
    if !compat_enabled {
        "xt_classic_compat_not_enabled"
    } else if !preferred_parent_ok {
        "classic_status_scan_disabled_or_parent_missing"
    } else if !status_writer_enabled {
        "classic_status_writer_disabled"
    } else if !status_writer_heartbeat_enabled {
        "classic_status_writer_heartbeat_disabled"
    } else if active_classic_hub {
        "classic_hub_already_running"
    } else if !rust_owned_status_available {
        "rust_owned_status_required"
    } else if !rollback_contract_ready {
        "rollback_contract_not_ready"
    } else if !status_writer_apply_enabled {
        "classic_status_writer_apply_disabled"
    } else if !file_ipc_surface_ready {
        "classic_file_ipc_surface_not_ready"
    } else if !production_cutover_authorized {
        "production_cutover_not_authorized"
    } else {
        ""
    }
}

fn read_json(path: &PathBuf) -> Option<Value> {
    let data = fs::read_to_string(path).ok()?;
    serde_json::from_str(&data).ok()
}

fn env_bool(key: &str, fallback: bool) -> bool {
    match env::var(key) {
        Ok(value) => match value.trim().to_ascii_lowercase().as_str() {
            "1" | "true" | "yes" | "y" | "on" => true,
            "0" | "false" | "no" | "n" | "off" => false,
            _ => fallback,
        },
        Err(_) => fallback,
    }
}

fn env_u128_in_range(key: &str, fallback: u128, min: u128, max: u128) -> u128 {
    env::var(key)
        .ok()
        .and_then(|value| value.trim().parse::<u128>().ok())
        .map(|value| value.clamp(min, max))
        .unwrap_or(fallback.clamp(min, max))
}

fn env_u16_in_range(key: &str, fallback: u16, min: u16, max: u16) -> u16 {
    env::var(key)
        .ok()
        .and_then(|value| value.trim().parse::<u16>().ok())
        .map(|value| value.clamp(min, max))
        .unwrap_or(fallback.clamp(min, max))
}

fn env_path(key: &str) -> Option<PathBuf> {
    env::var(key)
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compat_preflight_defaults_fail_closed_without_opt_in() {
        let input = XtClassicCompatInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            http_addr: "127.0.0.1:50151".to_string(),
            home_dir: PathBuf::from("/tmp/xhub-compat-empty-home"),
            now_ms: 100_000,
            compat_enabled: false,
            scan_local_files_enabled: false,
            status_writer_enabled: false,
            status_writer_heartbeat_enabled: false,
            status_ttl_ms: 5_000,
            status_writer_lease_ms: 0,
            status_path_override: None,
            base_dir_override: None,
            grpc_probe_enabled: false,
            grpc_host: "127.0.0.1".to_string(),
            grpc_port: 50152,
            grpc_probe_timeout_ms: 50,
            grpc_mtls_transport_fallback_enabled: false,
            rollback_contract_enabled: false,
            status_writer_apply_enabled: false,
            file_ipc_surface_ready: false,
            production_cutover_authorized: false,
        };

        let value = classic_hub_compat_value(&input);

        assert_eq!(value["ready"], false);
        assert_eq!(value["can_mark_xt_hub_interactive"], false);
        assert_eq!(value["deny_code"], "xt_classic_compat_not_enabled");
        assert_eq!(value["authority"]["production_authority_change"], false);
        assert_eq!(value["authority"]["node_remains_authority"], true);
    }

    #[test]
    fn fresh_classic_hub_status_blocks_bridge_preparation() {
        let temp = unique_temp_dir("xhub-xt-compat-active");
        let base_dir = temp.join("Library/Containers/com.rel.flowhub/Data/RELFlowHub");
        fs::create_dir_all(&base_dir).unwrap();
        fs::write(
            base_dir.join("hub_status.json"),
            r#"{"pid":1234,"updatedAt":99.0,"baseDir":"/tmp/classic","ipcMode":"file","ipcPath":"/tmp/classic/ipc_events","aiReady":true,"loadedModelCount":3}"#,
        )
        .unwrap();

        let input = XtClassicCompatInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            http_addr: "127.0.0.1:50151".to_string(),
            home_dir: temp.clone(),
            now_ms: 100_000,
            compat_enabled: true,
            scan_local_files_enabled: true,
            status_writer_enabled: true,
            status_writer_heartbeat_enabled: false,
            status_ttl_ms: 5_000,
            status_writer_lease_ms: 0,
            status_path_override: Some(base_dir.join("hub_status.json")),
            base_dir_override: None,
            grpc_probe_enabled: true,
            grpc_host: "127.0.0.1".to_string(),
            grpc_port: 50152,
            grpc_probe_timeout_ms: 50,
            grpc_mtls_transport_fallback_enabled: false,
            rollback_contract_enabled: false,
            status_writer_apply_enabled: false,
            file_ipc_surface_ready: false,
            production_cutover_authorized: false,
        };

        let value = classic_hub_compat_value(&input);

        assert_eq!(value["ready"], false);
        assert_eq!(value["safe_to_prepare_bridge"], false);
        assert_eq!(value["deny_code"], "classic_hub_already_running");
        assert_eq!(value["xt_contract"]["active_classic_hub"]["xt_live"], true);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn opt_in_still_blocks_when_local_file_scan_is_disabled() {
        let input = XtClassicCompatInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            http_addr: "127.0.0.1:50151".to_string(),
            home_dir: PathBuf::from("/tmp/xhub-compat-scan-disabled-home"),
            now_ms: 100_000,
            compat_enabled: true,
            scan_local_files_enabled: false,
            status_writer_enabled: true,
            status_writer_heartbeat_enabled: false,
            status_ttl_ms: 5_000,
            status_writer_lease_ms: 0,
            status_path_override: None,
            base_dir_override: None,
            grpc_probe_enabled: false,
            grpc_host: "127.0.0.1".to_string(),
            grpc_port: 50152,
            grpc_probe_timeout_ms: 50,
            grpc_mtls_transport_fallback_enabled: false,
            rollback_contract_enabled: false,
            status_writer_apply_enabled: false,
            file_ipc_surface_ready: false,
            production_cutover_authorized: false,
        };

        let value = classic_hub_compat_value(&input);

        assert_eq!(value["ready"], false);
        assert_eq!(
            value["deny_code"],
            "classic_status_scan_disabled_or_parent_missing"
        );
        assert_eq!(value["xt_contract"]["status_scan_enabled"], false);
        assert_eq!(
            value["xt_contract"]["candidate_statuses"][0]["status_scan_skipped"],
            true
        );
    }

    #[test]
    fn no_active_classic_hub_advances_to_grpc_gate() {
        let temp = unique_temp_dir("xhub-xt-compat-grpc-gate");
        let preferred = temp.join("hub_status.json");
        fs::create_dir_all(&temp).unwrap();

        let input = XtClassicCompatInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            http_addr: "127.0.0.1:50151".to_string(),
            home_dir: temp.clone(),
            now_ms: 100_000,
            compat_enabled: true,
            scan_local_files_enabled: true,
            status_writer_enabled: true,
            status_writer_heartbeat_enabled: false,
            status_ttl_ms: 5_000,
            status_writer_lease_ms: 0,
            status_path_override: Some(preferred),
            base_dir_override: Some(temp.clone()),
            grpc_probe_enabled: false,
            grpc_host: "127.0.0.1".to_string(),
            grpc_port: 50152,
            grpc_probe_timeout_ms: 50,
            grpc_mtls_transport_fallback_enabled: false,
            rollback_contract_enabled: false,
            status_writer_apply_enabled: false,
            file_ipc_surface_ready: false,
            production_cutover_authorized: false,
        };

        let value = classic_hub_compat_value(&input);

        assert_eq!(value["ready"], false);
        assert_eq!(value["safe_to_prepare_bridge"], true);
        assert_eq!(value["deny_code"], "grpc_compat_probe_disabled");
        assert_eq!(value["grpc_compat"]["probe_enabled"], false);
        assert_eq!(value["can_mark_xt_hub_interactive"], false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn grpc_probe_enabled_without_service_still_fails_closed() {
        let temp = unique_temp_dir("xhub-xt-compat-grpc-down");
        let preferred = temp.join("hub_status.json");
        fs::create_dir_all(&temp).unwrap();
        let grpc_port = unused_loopback_port();

        let input = XtClassicCompatInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            http_addr: "127.0.0.1:50151".to_string(),
            home_dir: temp.clone(),
            now_ms: 100_000,
            compat_enabled: true,
            scan_local_files_enabled: true,
            status_writer_enabled: true,
            status_writer_heartbeat_enabled: false,
            status_ttl_ms: 5_000,
            status_writer_lease_ms: 0,
            status_path_override: Some(preferred),
            base_dir_override: Some(temp.clone()),
            grpc_probe_enabled: true,
            grpc_host: "127.0.0.1".to_string(),
            grpc_port,
            grpc_probe_timeout_ms: 100,
            grpc_mtls_transport_fallback_enabled: false,
            rollback_contract_enabled: false,
            status_writer_apply_enabled: false,
            file_ipc_surface_ready: false,
            production_cutover_authorized: false,
        };

        let value = classic_hub_compat_value(&input);

        assert_eq!(value["ready"], false);
        assert_eq!(value["deny_code"], "grpc_compat_not_ready");
        assert_eq!(value["grpc_compat"]["probe_enabled"], true);
        assert_eq!(value["grpc_compat"]["probe_ok"], false);
        assert_eq!(
            value["grpc_compat"]["error_code"],
            "grpc_compat_probe_failed"
        );
        assert_eq!(value["authority"]["rust_writes_classic_hub_status"], false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn grpc_probe_success_advances_to_rollback_gate() {
        let temp = unique_temp_dir("xhub-xt-compat-grpc-ready");
        let preferred = temp.join("hub_status.json");
        fs::create_dir_all(&temp).unwrap();
        let (grpc_port, shutdown, handle) = start_test_grpc_server(temp.clone());

        let input = XtClassicCompatInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            http_addr: "127.0.0.1:50151".to_string(),
            home_dir: temp.clone(),
            now_ms: 100_000,
            compat_enabled: true,
            scan_local_files_enabled: true,
            status_writer_enabled: true,
            status_writer_heartbeat_enabled: false,
            status_ttl_ms: 5_000,
            status_writer_lease_ms: 0,
            status_path_override: Some(preferred),
            base_dir_override: Some(temp.clone()),
            grpc_probe_enabled: true,
            grpc_host: "127.0.0.1".to_string(),
            grpc_port,
            grpc_probe_timeout_ms: 1_000,
            grpc_mtls_transport_fallback_enabled: false,
            rollback_contract_enabled: false,
            status_writer_apply_enabled: false,
            file_ipc_surface_ready: false,
            production_cutover_authorized: false,
        };

        let value = classic_hub_compat_value(&input);

        assert_eq!(value["ready"], false);
        assert_eq!(value["can_mark_xt_hub_interactive"], false);
        assert_eq!(value["deny_code"], "rollback_contract_not_ready");
        assert_eq!(value["grpc_compat"]["probe_enabled"], true);
        assert_eq!(value["grpc_compat"]["probe_ok"], true);
        assert_eq!(value["grpc_compat"]["paid_ai_seen"], true);
        assert_eq!(value["authority"]["rust_grpc_compat_probe_ready"], true);
        assert_eq!(value["authority"]["rust_writes_classic_hub_status"], false);
        assert_eq!(value["xt_contract"]["status_writer_implemented"], true);
        assert_eq!(value["xt_contract"]["rollback_contract_ready"], false);

        let _ = shutdown.send(());
        let _ = handle.join();
        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn rollback_and_apply_still_block_without_file_ipc_surface() {
        let temp = unique_temp_dir("xhub-xt-compat-no-ipc");
        let preferred = temp.join("hub_status.json");
        fs::create_dir_all(&temp).unwrap();
        let (grpc_port, shutdown, handle) = start_test_grpc_server(temp.clone());

        let input = XtClassicCompatInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            http_addr: "127.0.0.1:50151".to_string(),
            home_dir: temp.clone(),
            now_ms: 100_000,
            compat_enabled: true,
            scan_local_files_enabled: true,
            status_writer_enabled: true,
            status_writer_heartbeat_enabled: false,
            status_ttl_ms: 5_000,
            status_writer_lease_ms: 0,
            status_path_override: Some(preferred.clone()),
            base_dir_override: Some(temp.clone()),
            grpc_probe_enabled: true,
            grpc_host: "127.0.0.1".to_string(),
            grpc_port,
            grpc_probe_timeout_ms: 1_000,
            grpc_mtls_transport_fallback_enabled: false,
            rollback_contract_enabled: true,
            status_writer_apply_enabled: true,
            file_ipc_surface_ready: false,
            production_cutover_authorized: true,
        };

        let value = classic_hub_status_write_value(&input);

        assert_eq!(value["ok"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["deny_code"], "classic_file_ipc_surface_not_ready");
        assert_eq!(preferred.exists(), false);
        assert_eq!(value["authority"]["production_authority_change"], false);

        let _ = shutdown.send(());
        let _ = handle.join();
        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn status_writer_writes_temp_status_only_when_all_explicit_gates_pass() {
        let temp = unique_temp_dir("xhub-xt-compat-write");
        let preferred = temp.join("hub_status.json");
        fs::create_dir_all(&temp).unwrap();
        let (grpc_port, shutdown, handle) = start_test_grpc_server(temp.clone());

        let input = XtClassicCompatInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            http_addr: "127.0.0.1:50151".to_string(),
            home_dir: temp.clone(),
            now_ms: 100_000,
            compat_enabled: true,
            scan_local_files_enabled: true,
            status_writer_enabled: true,
            status_writer_heartbeat_enabled: false,
            status_ttl_ms: 5_000,
            status_writer_lease_ms: 0,
            status_path_override: Some(preferred.clone()),
            base_dir_override: Some(temp.clone()),
            grpc_probe_enabled: true,
            grpc_host: "127.0.0.1".to_string(),
            grpc_port,
            grpc_probe_timeout_ms: 1_000,
            grpc_mtls_transport_fallback_enabled: false,
            rollback_contract_enabled: true,
            status_writer_apply_enabled: true,
            file_ipc_surface_ready: true,
            production_cutover_authorized: true,
        };

        let value = classic_hub_status_write_value(&input);

        assert_eq!(value["ok"], true);
        assert_eq!(value["wrote"], true);
        assert_eq!(value["deny_code"], "");
        assert_eq!(value["authority"]["production_authority_change"], true);
        assert_eq!(value["authority"]["node_remains_authority"], false);
        assert_eq!(preferred.exists(), true);
        assert_eq!(temp.join("ipc_events").is_dir(), true);

        let written = read_json(&preferred).expect("written hub status json");
        assert_eq!(written["baseDir"], temp.display().to_string());
        assert_eq!(
            written["ipcPath"],
            temp.join("ipc_events").display().to_string()
        );
        assert_eq!(written["ipcMode"], "file");
        assert_eq!(written["aiReady"], true);
        assert_eq!(written["rustHub"]["authority"], "explicit_cutover_only");

        let _ = shutdown.send(());
        let _ = handle.join();
        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn status_writer_can_update_existing_status_in_place() {
        let temp = unique_temp_dir("xhub-xt-compat-in-place-write");
        let preferred = temp.join("hub_status.json");
        fs::create_dir_all(&temp).unwrap();
        fs::write(&preferred, "{\"old\":true,\"trailing\":\"value\"}\n").unwrap();

        write_existing_status_file_in_place(&preferred, "{\"new\":true}\n".to_string()).unwrap();

        let written = fs::read_to_string(&preferred).unwrap();
        assert_eq!(written, "{\"new\":true}\n");

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn status_writer_can_refresh_existing_rust_owned_status() {
        let temp = unique_temp_dir("xhub-xt-compat-refresh");
        let preferred = temp.join("hub_status.json");
        fs::create_dir_all(temp.join("ipc_events")).unwrap();
        fs::write(
            &preferred,
            r#"{"pid":1234,"updatedAt":100.0,"baseDir":"","ipcMode":"file","ipcPath":"","aiReady":true,"loadedModelCount":0,"rustHub":{"schema_version":"xhub.rust_hub.xt_classic_status.v1","authority":"explicit_cutover_only"}}"#,
        )
        .unwrap();
        let (grpc_port, shutdown, handle) = start_test_grpc_server(temp.clone());

        let input = XtClassicCompatInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            http_addr: "127.0.0.1:50151".to_string(),
            home_dir: temp.clone(),
            now_ms: 101_000,
            compat_enabled: true,
            scan_local_files_enabled: true,
            status_writer_enabled: true,
            status_writer_heartbeat_enabled: false,
            status_ttl_ms: 5_000,
            status_writer_lease_ms: 0,
            status_path_override: Some(preferred.clone()),
            base_dir_override: Some(temp.clone()),
            grpc_probe_enabled: true,
            grpc_host: "127.0.0.1".to_string(),
            grpc_port,
            grpc_probe_timeout_ms: 1_000,
            grpc_mtls_transport_fallback_enabled: false,
            rollback_contract_enabled: true,
            status_writer_apply_enabled: true,
            file_ipc_surface_ready: true,
            production_cutover_authorized: true,
        };

        let value = classic_hub_status_write_value(&input);

        assert_eq!(value["ok"], true);
        assert_eq!(value["wrote"], true);
        assert_eq!(value["deny_code"], "");
        let compat = classic_hub_compat_value(&input);
        assert_eq!(compat["xt_contract"]["active_rust_hub"], true);
        assert_eq!(compat["deny_code"], "");

        let _ = shutdown.send(());
        let _ = handle.join();
        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn status_heartbeat_refreshes_rust_owned_status_without_grpc_probe() {
        let temp = unique_temp_dir("xhub-xt-compat-heartbeat");
        let preferred = temp.join("hub_status.json");
        fs::create_dir_all(temp.join("ipc_events")).unwrap();
        fs::write(
            &preferred,
            r#"{"pid":1234,"updatedAt":100.0,"baseDir":"","ipcMode":"file","ipcPath":"","aiReady":true,"loadedModelCount":0,"rustHub":{"schema_version":"xhub.rust_hub.xt_classic_status.v1","authority":"explicit_cutover_only"}}"#,
        )
        .unwrap();
        let grpc_port = unused_loopback_port();

        let input = XtClassicCompatInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            http_addr: "127.0.0.1:50151".to_string(),
            home_dir: temp.clone(),
            now_ms: 108_000,
            compat_enabled: true,
            scan_local_files_enabled: true,
            status_writer_enabled: true,
            status_writer_heartbeat_enabled: true,
            status_ttl_ms: 5_000,
            status_writer_lease_ms: 0,
            status_path_override: Some(preferred.clone()),
            base_dir_override: Some(temp.clone()),
            grpc_probe_enabled: true,
            grpc_host: "127.0.0.1".to_string(),
            grpc_port,
            grpc_probe_timeout_ms: 50,
            grpc_mtls_transport_fallback_enabled: false,
            rollback_contract_enabled: true,
            status_writer_apply_enabled: true,
            file_ipc_surface_ready: true,
            production_cutover_authorized: true,
        };

        let value = classic_hub_status_heartbeat_value(&input);

        assert_eq!(value["ok"], true);
        assert_eq!(value["wrote"], true);
        assert_eq!(value["deny_code"], "");
        assert_eq!(value["grpc_probe_performed"], false);
        assert_eq!(value["active_rust_hub"], false);
        assert_eq!(value["preferred_rust_owned"], true);

        let written = read_json(&preferred).expect("heartbeat refreshed hub status json");
        assert_eq!(written["updatedAt"], 108.0);
        assert_eq!(written["rustHub"]["authority"], "explicit_cutover_only");

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn compat_get_uses_fast_path_for_active_rust_owned_live_status() {
        let temp = unique_temp_dir("xhub-xt-compat-fast-path");
        let preferred = temp.join("hub_status.json");
        fs::create_dir_all(temp.join("ipc_events")).unwrap();
        fs::write(
            &preferred,
            r#"{"pid":1234,"updatedAt":100.0,"baseDir":"","ipcMode":"file","ipcPath":"","aiReady":true,"loadedModelCount":0,"rustHub":{"schema_version":"xhub.rust_hub.xt_classic_status.v1","authority":"explicit_cutover_only"}}"#,
        )
        .unwrap();
        let grpc_port = unused_loopback_port();

        let input = XtClassicCompatInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            http_addr: "127.0.0.1:50151".to_string(),
            home_dir: temp.clone(),
            now_ms: 101_000,
            compat_enabled: true,
            scan_local_files_enabled: true,
            status_writer_enabled: true,
            status_writer_heartbeat_enabled: true,
            status_ttl_ms: 5_000,
            status_writer_lease_ms: 0,
            status_path_override: Some(preferred.clone()),
            base_dir_override: Some(temp.clone()),
            grpc_probe_enabled: true,
            grpc_host: "127.0.0.1".to_string(),
            grpc_port,
            grpc_probe_timeout_ms: 50,
            grpc_mtls_transport_fallback_enabled: false,
            rollback_contract_enabled: true,
            status_writer_apply_enabled: true,
            file_ipc_surface_ready: true,
            production_cutover_authorized: true,
        };

        let value = classic_hub_compat_value(&input);

        assert_eq!(value["ready"], true);
        assert_eq!(value["deny_code"], "");
        assert_eq!(value["xt_contract"]["active_rust_hub"], true);
        assert_eq!(value["grpc_compat"]["probe_ok"], true);
        assert_eq!(
            value["grpc_compat"]["error_code"],
            "grpc_compat_probe_skipped_rust_owned_live_status"
        );
        assert_eq!(
            value["grpc_compat"]["probe_skipped_for_rust_owned_live_status"],
            true
        );

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn compat_get_live_cutover_writes_status_file_on_demand() {
        *LIVE_STATUS_CACHE.lock().unwrap() = None;
        let temp = unique_temp_dir("xhub-xt-compat-live-overlay");
        let preferred = temp.join("hub_status.json");
        fs::create_dir_all(temp.join("ipc_events")).unwrap();
        let grpc_port = unused_loopback_port();

        let input = XtClassicCompatInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            http_addr: "127.0.0.1:50151".to_string(),
            home_dir: temp.clone(),
            now_ms: 101_000,
            compat_enabled: true,
            scan_local_files_enabled: true,
            status_writer_enabled: true,
            status_writer_heartbeat_enabled: true,
            status_ttl_ms: 5_000,
            status_writer_lease_ms: 2_000,
            status_path_override: Some(preferred.clone()),
            base_dir_override: Some(temp.clone()),
            grpc_probe_enabled: true,
            grpc_host: "127.0.0.1".to_string(),
            grpc_port,
            grpc_probe_timeout_ms: 50,
            grpc_mtls_transport_fallback_enabled: false,
            rollback_contract_enabled: true,
            status_writer_apply_enabled: true,
            file_ipc_surface_ready: true,
            production_cutover_authorized: true,
        };

        let value = classic_hub_compat_value(&input);

        assert_eq!(value["ready"], true);
        assert_eq!(value["deny_code"], "");
        assert_eq!(value["xt_contract"]["active_rust_hub"], true);
        assert!(
            value["xt_contract"]["candidate_statuses"][0]["updated_at_ms"]
                .as_i64()
                .unwrap_or(0)
                >= 101_000
        );
        assert_eq!(
            value["xt_contract"]["candidate_statuses"][0]["rust_hub_authority"],
            "explicit_cutover_only"
        );
        assert_eq!(preferred.exists(), true);
        let written = read_json(&preferred).expect("written hub status json");
        assert_eq!(
            written
                .get("rustHub")
                .and_then(|value| value.get("authority"))
                .and_then(Value::as_str)
                .unwrap_or(""),
            "explicit_cutover_only"
        );
        assert!(
            written
                .get("updatedAt")
                .and_then(Value::as_f64)
                .map(|seconds| seconds * 1000.0)
                .unwrap_or(0.0)
                >= 101_000.0
        );

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn compat_get_repairs_stale_rust_owned_live_status_with_fast_write() {
        let temp = unique_temp_dir("xhub-xt-compat-stale-repair");
        let preferred = temp.join("hub_status.json");
        fs::create_dir_all(temp.join("ipc_events")).unwrap();
        fs::write(
            &preferred,
            r#"{"pid":1234,"updatedAt":100.0,"baseDir":"","ipcMode":"file","ipcPath":"","aiReady":true,"loadedModelCount":0,"rustHub":{"schema_version":"xhub.rust_hub.xt_classic_status.v1","authority":"explicit_cutover_only"}}"#,
        )
        .unwrap();
        let grpc_port = unused_loopback_port();

        let input = XtClassicCompatInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            http_addr: "127.0.0.1:50151".to_string(),
            home_dir: temp.clone(),
            now_ms: 106_000,
            compat_enabled: true,
            scan_local_files_enabled: true,
            status_writer_enabled: true,
            status_writer_heartbeat_enabled: true,
            status_ttl_ms: 5_000,
            status_writer_lease_ms: 0,
            status_path_override: Some(preferred.clone()),
            base_dir_override: Some(temp.clone()),
            grpc_probe_enabled: true,
            grpc_host: "127.0.0.1".to_string(),
            grpc_port,
            grpc_probe_timeout_ms: 50,
            grpc_mtls_transport_fallback_enabled: false,
            rollback_contract_enabled: true,
            status_writer_apply_enabled: true,
            file_ipc_surface_ready: true,
            production_cutover_authorized: true,
        };

        let value = classic_hub_compat_value(&input);

        assert_eq!(value["ready"], true);
        assert_eq!(value["deny_code"], "");
        assert_eq!(value["xt_contract"]["active_rust_hub"], true);
        assert_eq!(
            value["grpc_compat"]["error_code"],
            "grpc_compat_probe_skipped_rust_owned_live_status"
        );
        let written = read_json(&preferred).expect("existing hub status json");
        let updated_at_ms = written
            .get("updatedAt")
            .and_then(Value::as_f64)
            .map(|seconds| seconds * 1000.0)
            .unwrap_or(0.0);
        assert!(updated_at_ms >= 106_000.0);
        assert_eq!(
            written
                .get("rustHub")
                .and_then(|value| value.get("authority"))
                .and_then(Value::as_str)
                .unwrap_or(""),
            "explicit_cutover_only"
        );

        let _ = fs::remove_dir_all(temp);
    }

    fn unique_temp_dir(label: &str) -> PathBuf {
        let dir = env::temp_dir().join(format!("{}-{}-{}", label, std::process::id(), now_ms()));
        let _ = fs::remove_dir_all(&dir);
        dir
    }

    fn unused_loopback_port() -> u16 {
        std::net::TcpListener::bind("127.0.0.1:0")
            .unwrap()
            .local_addr()
            .unwrap()
            .port()
    }

    fn start_test_grpc_server(
        root: PathBuf,
    ) -> (
        u16,
        tokio::sync::oneshot::Sender<()>,
        std::thread::JoinHandle<()>,
    ) {
        let std_listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        std_listener.set_nonblocking(true).unwrap();
        let addr = std_listener.local_addr().unwrap();
        let (ready_tx, ready_rx) = std::sync::mpsc::channel();
        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        let handle = std::thread::spawn(move || {
            let runtime = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .unwrap();
            runtime.block_on(async move {
                let listener = tokio::net::TcpListener::from_std(std_listener).unwrap();
                let incoming = tokio_stream::wrappers::TcpListenerStream::new(listener);
                let config = HubConfig {
                    root_dir: root.clone(),
                    host: "127.0.0.1".to_string(),
                    http_port: 0,
                    grpc_port: addr.port(),
                    db_path: root.join("hub.sqlite3"),
                    runtime_base_dir: root.join("runtime"),
                    proto_path: root.join("hub_protocol_v1.proto"),
                    canonical_proto_path: root.join("hub_protocol_v1.proto"),
                    http_access_key: None,
                    http_access_key_source: String::new(),
                    http_access_key_required: false,
                };
                ready_tx.send(()).unwrap();
                tonic::transport::Server::builder()
                    .add_service(
                        xhub_contract::proto::hub_runtime_server::HubRuntimeServer::new(
                            crate::grpc_runtime::RuntimeService::new(config),
                        ),
                    )
                    .serve_with_incoming_shutdown(incoming, async {
                        let _ = shutdown_rx.await;
                    })
                    .await
                    .unwrap();
            });
        });
        ready_rx.recv_timeout(Duration::from_secs(2)).unwrap();
        (addr.port(), shutdown_tx, handle)
    }
}
