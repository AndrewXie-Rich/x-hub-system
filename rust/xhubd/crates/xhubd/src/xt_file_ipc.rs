use std::env;
use std::fs;
use std::fs::OpenOptions;
use std::path::{Path, PathBuf};
use std::process;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread;
use std::time::Duration;

use serde_json::{json, Value};
use xhub_core::{now_ms, HubConfig};

use crate::model_bridge;

const SCHEMA_XT_FILE_IPC_SHADOW_V1: &str = "xhub.rust_hub.xt_file_ipc_shadow.v1";
const SCHEMA_XT_FILE_IPC_SHADOW_PROCESSOR_STATUS_V1: &str =
    "xhub.rust_hub.xt_file_ipc_shadow_processor_status.v1";
const SCHEMA_XT_FILE_IPC_SHADOW_WATCHER_STATUS_V1: &str =
    "xhub.rust_hub.xt_file_ipc_shadow_watcher_status.v1";
const SCHEMA_XT_FILE_IPC_LIVE_STATUS_V1: &str = "xhub.rust_hub.xt_file_ipc_live_status.v1";
const FAIL_CLOSED_REASON: &str = "rust_file_ipc_not_authoritative";
const PROCESSOR_STATUS_FILENAME: &str = "rust_file_ipc_shadow_processor_status.json";
const WATCHER_STATUS_FILENAME: &str = "rust_file_ipc_shadow_watcher_status.json";
const WATCHER_LOCK_FILENAME: &str = "rust_file_ipc_shadow_watcher.lock";
const MAX_REQUEST_FILE_BYTES: u64 = 1_048_576;
const MAX_REQUEST_PROMPT_CHARS: usize = 200_000;

#[derive(Clone, Debug)]
struct XtFileIpcShadowInput {
    root_dir: PathBuf,
    now_ms: u128,
    shadow_enabled: bool,
    shadow_apply_env_enabled: bool,
    requested_apply: bool,
    base_dir: Option<PathBuf>,
    runtime_base_dir: PathBuf,
    req_id: Option<String>,
    overwrite_response: bool,
    max_requests: usize,
    max_cycles: usize,
    cycle_interval_ms: u64,
}

#[derive(Clone, Debug, Default)]
struct BackgroundWatcherRuntime {
    active: bool,
    watcher_id: String,
    base_dir: String,
    started_at_ms: i64,
    finished_at_ms: i64,
    max_cycles: usize,
    cycle_interval_ms: u64,
    completed_cycles: usize,
    wrote_count: usize,
    stop_requested: bool,
    last_error: String,
    stop_flag: Option<Arc<AtomicBool>>,
}

static BACKGROUND_WATCHER: OnceLock<Mutex<BackgroundWatcherRuntime>> = OnceLock::new();

fn background_watcher_runtime() -> &'static Mutex<BackgroundWatcherRuntime> {
    BACKGROUND_WATCHER.get_or_init(|| Mutex::new(BackgroundWatcherRuntime::default()))
}

impl XtFileIpcShadowInput {
    fn from_http(config: &HubConfig, body: &Value) -> Self {
        Self {
            root_dir: config.root_dir.clone(),
            now_ms: now_ms(),
            shadow_enabled: env_bool("XHUB_RUST_XT_FILE_IPC_SHADOW", false),
            shadow_apply_env_enabled: env_bool("XHUB_RUST_XT_FILE_IPC_SHADOW_APPLY", false),
            requested_apply: value_bool(body, "apply").unwrap_or(false),
            base_dir: value_string(body, "base_dir")
                .or_else(|| value_string(body, "baseDir"))
                .map(PathBuf::from)
                .or_else(|| env_path("XHUB_RUST_XT_FILE_IPC_BASE_DIR")),
            runtime_base_dir: value_string(body, "runtime_base_dir")
                .or_else(|| value_string(body, "runtimeBaseDir"))
                .map(PathBuf::from)
                .or_else(|| env_path("XHUB_RUST_XT_RUNTIME_BASE_DIR"))
                .unwrap_or_else(|| config.runtime_base_dir.clone()),
            req_id: value_string(body, "req_id")
                .or_else(|| value_string(body, "reqId"))
                .or_else(|| value_string(body, "request_id"))
                .or_else(|| value_string(body, "requestId")),
            overwrite_response: value_bool(body, "overwrite_response")
                .or_else(|| value_bool(body, "overwriteResponse"))
                .unwrap_or(false),
            max_requests: value_usize(body, "max_requests")
                .or_else(|| value_usize(body, "maxRequests"))
                .unwrap_or(16)
                .clamp(1, 64),
            max_cycles: value_usize(body, "max_cycles")
                .or_else(|| value_usize(body, "maxCycles"))
                .unwrap_or(1)
                .clamp(1, 10),
            cycle_interval_ms: value_u64(body, "cycle_interval_ms")
                .or_else(|| value_u64(body, "cycleIntervalMs"))
                .unwrap_or(100)
                .min(5_000),
        }
    }
}

pub fn shadow_http_json(
    config: &HubConfig,
    route_path: &str,
    method: &str,
    body: &str,
) -> (&'static str, String) {
    if method == "GET" {
        return ("200 OK", format!("{}\n", shadow_status_value(config)));
    }
    if method != "POST" {
        return (
            "405 Method Not Allowed",
            format!(
                "{}\n",
                json!({
                    "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
                    "ok": false,
                    "wrote": false,
                    "deny_code": "method_not_allowed",
                    "required_method": "GET or POST",
                    "authority": authority_json(false),
                })
            ),
        );
    }

    let parsed = if body.trim().is_empty() {
        json!({})
    } else {
        match serde_json::from_str::<Value>(body) {
            Ok(value) => value,
            Err(error) => {
                return (
                    "400 Bad Request",
                    format!(
                        "{}\n",
                        json!({
                            "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
                            "ok": false,
                            "wrote": false,
                            "deny_code": "invalid_json_body",
                            "error_message": error.to_string(),
                            "authority": authority_json(false),
                        })
                    ),
                );
            }
        }
    };
    let input = XtFileIpcShadowInput::from_http(config, &parsed);
    let value = if route_path.ends_with("/watcher-background-start")
        || wants_watcher_background_start(&parsed)
    {
        watcher_background_start_value(
            &input,
            env_bool("XHUB_RUST_XT_FILE_IPC_WATCHER_ENABLE", false),
            env_bool("XHUB_RUST_XT_FILE_IPC_RUNTIME_READY", false),
            env_bool("XHUB_RUST_XT_FILE_IPC_ROLLBACK_APPLY", false),
            env_bool("XHUB_RUST_XT_FILE_IPC_WATCHER_START_APPLY", false),
            env_bool("XHUB_RUST_XT_FILE_IPC_WATCHER_BACKGROUND_APPLY", false),
        )
    } else if route_path.ends_with("/watcher-background-stop")
        || wants_watcher_background_stop(&parsed)
    {
        watcher_background_stop_value(&input)
    } else if route_path.ends_with("/watcher-background-status")
        || wants_watcher_background_status(&parsed)
    {
        watcher_background_status_value()
    } else if route_path.ends_with("/runtime-adapter-candidate")
        || wants_runtime_adapter_candidate(&parsed)
    {
        runtime_adapter_candidate_value(
            config,
            &input,
            env_bool("XHUB_RUST_XT_FILE_IPC_RUNTIME_PLAN", false),
            env_bool("XHUB_RUST_XT_FILE_IPC_RUNTIME_ADAPTER_CANDIDATE", false),
        )
    } else if route_path.ends_with("/runtime-execution-plan")
        || wants_runtime_execution_plan(&parsed)
    {
        runtime_execution_plan_value(
            config,
            &input,
            env_bool("XHUB_RUST_XT_FILE_IPC_RUNTIME_PLAN", false),
            env_bool("XHUB_RUST_XT_FILE_IPC_RUNTIME_READY", false),
            env_bool("XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER", false),
        )
    } else if route_path.ends_with("/watcher-session") || wants_watcher_session(&parsed) {
        watcher_session_value(
            &input,
            env_bool("XHUB_RUST_XT_FILE_IPC_WATCHER_ENABLE", false),
            env_bool("XHUB_RUST_XT_FILE_IPC_RUNTIME_READY", false),
            env_bool("XHUB_RUST_XT_FILE_IPC_ROLLBACK_APPLY", false),
            env_bool("XHUB_RUST_XT_FILE_IPC_WATCHER_START_APPLY", false),
            env_bool("XHUB_RUST_XT_FILE_IPC_WATCHER_SESSION_APPLY", false),
        )
    } else if route_path.ends_with("/watcher-run-once") || wants_watcher_run_once(&parsed) {
        watcher_run_once_value(
            &input,
            env_bool("XHUB_RUST_XT_FILE_IPC_WATCHER_ENABLE", false),
            env_bool("XHUB_RUST_XT_FILE_IPC_RUNTIME_READY", false),
            env_bool("XHUB_RUST_XT_FILE_IPC_ROLLBACK_APPLY", false),
            env_bool("XHUB_RUST_XT_FILE_IPC_WATCHER_START_APPLY", false),
            env_bool("XHUB_RUST_XT_FILE_IPC_WATCHER_RUN_ONCE_APPLY", false),
        )
    } else if route_path.ends_with("/watcher-start-plan") || wants_watcher_start_plan(&parsed) {
        watcher_start_plan_value(
            &input,
            env_bool("XHUB_RUST_XT_FILE_IPC_WATCHER_ENABLE", false),
            env_bool("XHUB_RUST_XT_FILE_IPC_RUNTIME_READY", false),
            env_bool("XHUB_RUST_XT_FILE_IPC_ROLLBACK_APPLY", false),
            env_bool("XHUB_RUST_XT_FILE_IPC_WATCHER_START_APPLY", false),
        )
    } else if route_path.ends_with("/watcher-readiness") || wants_watcher_readiness(&parsed) {
        watcher_readiness_value(
            &input,
            env_bool("XHUB_RUST_XT_FILE_IPC_WATCHER_ENABLE", false),
            env_bool("XHUB_RUST_XT_FILE_IPC_RUNTIME_READY", false),
            env_bool("XHUB_RUST_XT_FILE_IPC_ROLLBACK_APPLY", false),
        )
    } else if route_path.ends_with("/watcher-rollback-smoke")
        || wants_watcher_rollback_smoke(&parsed)
    {
        watcher_rollback_smoke_value(
            &input,
            env_bool("XHUB_RUST_XT_FILE_IPC_ROLLBACK_APPLY", false),
        )
    } else if route_path.ends_with("/watcher-smoke") || wants_watcher_smoke(&parsed) {
        watcher_smoke_value(&input)
    } else if route_path.ends_with("/supervise") || wants_supervise(&parsed) {
        supervise_bounded_value(&input)
    } else if route_path.ends_with("/cycle") || wants_cycle(&parsed) {
        cycle_once_value(&input)
    } else if route_path.ends_with("/drain") || wants_drain(&parsed) {
        drain_once_value(&input)
    } else {
        respond_once_value(&input)
    };
    let ok = value.get("ok").and_then(Value::as_bool).unwrap_or(false);
    let status = if ok { "200 OK" } else { "409 Conflict" };
    (status, format!("{value}\n"))
}

pub fn live_status_http_json(config: &HubConfig, method: &str) -> (&'static str, String) {
    if method != "GET" {
        return (
            "405 Method Not Allowed",
            format!(
                "{}\n",
                json!({
                    "schema_version": SCHEMA_XT_FILE_IPC_LIVE_STATUS_V1,
                    "ok": false,
                    "ready": false,
                    "deny_code": "method_not_allowed",
                    "required_method": "GET",
                    "authority": authority_json(false),
                })
            ),
        );
    }

    let value = live_status_value(config, now_ms());
    let ok = value.get("ok").and_then(Value::as_bool).unwrap_or(false);
    let status = if ok { "200 OK" } else { "409 Conflict" };
    (status, format!("{value}\n"))
}

fn shadow_status_value(config: &HubConfig) -> Value {
    let input = XtFileIpcShadowInput {
        root_dir: config.root_dir.clone(),
        now_ms: now_ms(),
        shadow_enabled: env_bool("XHUB_RUST_XT_FILE_IPC_SHADOW", false),
        shadow_apply_env_enabled: env_bool("XHUB_RUST_XT_FILE_IPC_SHADOW_APPLY", false),
        requested_apply: false,
        base_dir: env_path("XHUB_RUST_XT_FILE_IPC_BASE_DIR"),
        runtime_base_dir: env_path("XHUB_RUST_XT_RUNTIME_BASE_DIR")
            .unwrap_or_else(|| config.runtime_base_dir.clone()),
        req_id: None,
        overwrite_response: false,
        max_requests: 16,
        max_cycles: 1,
        cycle_interval_ms: 100,
    };

    let base_dir = input
        .base_dir
        .as_ref()
        .map(|path| path.display().to_string())
        .unwrap_or_default();
    let temp_base_allowed = input
        .base_dir
        .as_ref()
        .map(|path| shadow_safe_base_dir(path))
        .unwrap_or(false);

    json!({
        "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
        "ok": true,
        "ready": false,
        "generated_at_ms": input.now_ms.min(i64::MAX as u128) as i64,
        "mode": "shadow_fail_closed",
        "root_dir": input.root_dir.display().to_string(),
        "base_dir": base_dir,
        "shadow_enabled": input.shadow_enabled,
        "shadow_apply_env_enabled": input.shadow_apply_env_enabled,
        "max_drain_requests": input.max_requests,
        "max_supervisor_cycles": input.max_cycles,
        "supervisor_cycle_interval_ms": input.cycle_interval_ms,
        "base_dir_temp_safe": temp_base_allowed,
        "surface_contract": surface_contract_json(),
        "processor_status_filename": PROCESSOR_STATUS_FILENAME,
        "watcher_status_filename": WATCHER_STATUS_FILENAME,
        "watcher_lock_filename": WATCHER_LOCK_FILENAME,
        "authority": authority_json(false),
        "checks": [
            {"name": "shadow_enabled", "ok": input.shadow_enabled, "blocking": true},
            {"name": "shadow_apply_env_enabled", "ok": input.shadow_apply_env_enabled, "blocking": true},
            {"name": "base_dir_explicit", "ok": input.base_dir.is_some(), "blocking": true},
            {"name": "base_dir_temp_safe", "ok": temp_base_allowed, "blocking": true},
            {"name": "production_authority_unchanged", "ok": true, "blocking": false},
            {"name": "no_ml_execution_in_rust", "ok": true, "blocking": false}
        ]
    })
}

fn live_status_value(config: &HubConfig, generated_at_ms: u128) -> Value {
    let Some(base_dir) = live_status_base_dir(config) else {
        return json!({
            "schema_version": SCHEMA_XT_FILE_IPC_LIVE_STATUS_V1,
            "ok": false,
            "ready": false,
            "generated_at_ms": generated_at_ms.min(i64::MAX as u128) as i64,
            "mode": "rust_file_ipc_live_status_read_only",
            "deny_code": "live_base_dir_missing",
            "root_dir": config.root_dir.display().to_string(),
            "authority": authority_json(false),
            "checks": [
                {"name": "live_base_dir_configured", "ok": false, "blocking": true},
                {"name": "read_only_status_projection", "ok": true, "blocking": false},
                {"name": "hub_status_untouched", "ok": true, "blocking": false}
            ],
        });
    };
    let status_path = env_path("XHUB_RUST_XT_CLASSIC_HUB_STATUS_PATH")
        .unwrap_or_else(|| base_dir.join("hub_status.json"));
    live_status_value_for_base(config, generated_at_ms, &base_dir, &status_path)
}

fn live_status_value_for_base(
    config: &HubConfig,
    generated_at_ms: u128,
    base_dir: &Path,
    status_path: &Path,
) -> Value {
    let base_dir_display = base_dir.display().to_string();
    let events_dir = base_dir.join("ipc_events");
    let responses_dir = base_dir.join("ipc_responses");
    let status_file_exists = status_path.is_file();
    let status_file_modified_at_ms = file_modified_at_ms(status_path);
    let (mut status, status_file_read_ok, status_file_error) = match read_json(status_path) {
        Ok(Value::Object(map)) => (Value::Object(map), true, String::new()),
        Ok(_) => (json!({}), false, "status_json_not_object".to_string()),
        Err(error) if status_file_exists => (json!({}), false, error),
        Err(_) => (json!({}), false, String::new()),
    };
    let generated_at_sec = (generated_at_ms as f64) / 1000.0;

    if let Some(object) = status.as_object_mut() {
        object.insert("updatedAt".to_string(), json!(generated_at_sec));
        object.insert("ipcMode".to_string(), json!("file"));
        object.insert(
            "ipcPath".to_string(),
            json!(events_dir.display().to_string()),
        );
        object.insert("baseDir".to_string(), json!(base_dir_display.clone()));
        if !object.contains_key("protocolVersion") {
            object.insert("protocolVersion".to_string(), json!(1));
        }
        if !object.contains_key("pid") {
            object.insert("pid".to_string(), json!(process::id()));
        }
        if !object.contains_key("startedAt") {
            object.insert("startedAt".to_string(), json!(generated_at_sec));
        }
        if !object.contains_key("aiReady") {
            object.insert("aiReady".to_string(), json!(true));
        }
        if !object.contains_key("loadedModelCount") {
            object.insert("loadedModelCount".to_string(), json!(0));
        }
        if !object.contains_key("modelsUpdatedAt") {
            object.insert("modelsUpdatedAt".to_string(), json!(generated_at_sec));
        }

        let mut rust_hub = object
            .get("rustHub")
            .and_then(Value::as_object)
            .cloned()
            .unwrap_or_else(serde_json::Map::new);
        rust_hub.insert(
            "schema_version".to_string(),
            json!("xhub.rust_hub.xt_classic_status.v1"),
        );
        rust_hub.insert("authority".to_string(), json!("rust_live_status_http"));
        rust_hub.insert("http_addr".to_string(), json!(config.http_addr()));
        rust_hub.insert(
            "status_path".to_string(),
            json!(status_path.display().to_string()),
        );
        rust_hub.insert("read_only_projection".to_string(), json!(true));
        object.insert("rustHub".to_string(), Value::Object(rust_hub));
    }

    json!({
        "schema_version": SCHEMA_XT_FILE_IPC_LIVE_STATUS_V1,
        "ok": true,
        "ready": true,
        "generated_at_ms": generated_at_ms.min(i64::MAX as u128) as i64,
        "mode": "rust_file_ipc_live_status_read_only",
        "root_dir": config.root_dir.display().to_string(),
        "base_dir": base_dir_display,
        "events_dir": events_dir.display().to_string(),
        "responses_dir": responses_dir.display().to_string(),
        "status_path": status_path.display().to_string(),
        "status_file_exists": status_file_exists,
        "status_file_read_ok": status_file_read_ok,
        "status_file_error": status_file_error,
        "status_file_modified_at_ms": status_file_modified_at_ms,
        "status": status,
        "authority": {
            "production_authority_change": false,
            "rust_writes_classic_hub_status": false,
            "rust_serves_live_status_http": true,
            "rust_executes_ml": false,
            "rust_executes_third_party_skills": false,
            "memory_writer_authority_in_rust": false,
        },
        "checks": [
            {"name": "live_base_dir_configured", "ok": true, "blocking": true},
            {"name": "live_base_dir_exists", "ok": base_dir.is_dir(), "blocking": false},
            {"name": "status_file_readable", "ok": status_file_read_ok || !status_file_exists, "blocking": false},
            {"name": "read_only_status_projection", "ok": true, "blocking": false},
            {"name": "hub_status_untouched", "ok": true, "blocking": false}
        ],
    })
}

fn live_status_base_dir(config: &HubConfig) -> Option<PathBuf> {
    env_path("XHUB_RUST_XT_FILE_IPC_BASE_DIR")
        .or_else(|| env_path("XHUB_RUST_XT_CLASSIC_HUB_BASE_DIR"))
        .or_else(|| {
            if config.runtime_base_dir.as_os_str().is_empty() {
                None
            } else {
                Some(config.runtime_base_dir.clone())
            }
        })
}

fn file_modified_at_ms(path: &Path) -> i64 {
    fs::metadata(path)
        .and_then(|metadata| metadata.modified())
        .ok()
        .and_then(|modified| modified.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|duration| duration.as_millis().min(i64::MAX as u128) as i64)
        .unwrap_or(0)
}

fn watcher_smoke_value(input: &XtFileIpcShadowInput) -> Value {
    let Some(base_dir) = input.base_dir.clone() else {
        return denied(input, "", "", "base_dir_required", "");
    };
    let base_dir_display = base_dir.display().to_string();
    if !input.shadow_enabled {
        return denied(
            input,
            &base_dir_display,
            "",
            "xt_file_ipc_shadow_not_enabled",
            "",
        );
    }
    if !shadow_safe_base_dir(&base_dir) {
        return denied(
            input,
            &base_dir_display,
            "",
            "base_dir_outside_shadow_sandbox",
            "",
        );
    }
    if !base_dir.is_dir() {
        return denied(input, &base_dir_display, "", "base_dir_missing", "");
    }
    if input.requested_apply && !input.shadow_apply_env_enabled {
        return denied(
            input,
            &base_dir_display,
            "",
            "xt_file_ipc_shadow_apply_not_enabled",
            "",
        );
    }

    let watcher_id = format!("watcher-smoke-{}-{}", process::id(), now_ms());
    let lock_path = base_dir.join(WATCHER_LOCK_FILENAME);
    let status_path = base_dir.join(WATCHER_STATUS_FILENAME);
    let start_status = watcher_status_json(input, &base_dir, &watcher_id, "starting", false, None);
    let mut start_status_wrote = false;
    let mut stop_status_wrote = false;
    let mut lock_acquired = false;
    let mut lock_released = false;
    let mut error_message = String::new();

    if input.requested_apply {
        match acquire_watcher_lock(&lock_path, &watcher_id) {
            Ok(()) => {
                lock_acquired = true;
                match write_json_atomic(&status_path, &start_status) {
                    Ok(()) => start_status_wrote = true,
                    Err(error) => error_message = error,
                }
            }
            Err(error) => error_message = error,
        }
    }

    let mut supervise_result = json!({
        "ok": true,
        "wrote": false,
        "mode": "shadow_supervise_dry_run",
        "supervisor": {
            "cycle_count": 0,
            "background_watcher_started": false,
            "stopped": true,
            "production_file_ipc_ready": false
        }
    });
    if !input.requested_apply || lock_acquired && error_message.is_empty() {
        supervise_result = supervise_bounded_value(input);
    }

    let supervise_ok = supervise_result
        .get("ok")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let supervise_wrote = supervise_result
        .get("wrote")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let supervise_response_wrote = supervise_result
        .get("supervisor")
        .and_then(|value| value.get("response_wrote_count"))
        .and_then(Value::as_u64)
        .unwrap_or(0)
        > 0;

    if input.requested_apply && lock_acquired {
        let stop_status = watcher_status_json(
            input,
            &base_dir,
            &watcher_id,
            "stopped",
            supervise_ok,
            Some(supervise_result.clone()),
        );
        match write_json_atomic(&status_path, &stop_status) {
            Ok(()) => stop_status_wrote = true,
            Err(error) => {
                if error_message.is_empty() {
                    error_message = error;
                }
            }
        }
        match fs::remove_file(&lock_path) {
            Ok(()) => lock_released = true,
            Err(error) => {
                if error_message.is_empty() {
                    error_message = format!("release_watcher_lock:{error}");
                }
            }
        }
    }

    let ok = if input.requested_apply {
        lock_acquired && start_status_wrote && stop_status_wrote && lock_released && supervise_ok
    } else {
        supervise_ok
    };
    let deny_code = if ok {
        ""
    } else if !error_message.is_empty() && error_message.starts_with("watcher_lock_busy") {
        "watcher_lock_busy"
    } else if !error_message.is_empty() {
        "watcher_lifecycle_failed"
    } else if !supervise_ok {
        "watcher_supervise_failed"
    } else {
        "unknown"
    };

    json!({
        "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
        "ok": ok,
        "ready": false,
        "wrote": start_status_wrote || stop_status_wrote || supervise_wrote,
        "generated_at_ms": now_ms().min(i64::MAX as u128) as i64,
        "mode": if input.requested_apply { "shadow_watcher_smoke_apply" } else { "shadow_watcher_smoke_dry_run" },
        "deny_code": deny_code,
        "error_message": error_message,
        "root_dir": input.root_dir.display().to_string(),
        "base_dir": base_dir_display,
        "watcher": {
            "watcher_id": watcher_id,
            "status_path": status_path.display().to_string(),
            "lock_path": lock_path.display().to_string(),
            "lock_acquired": lock_acquired,
            "lock_released": lock_released,
            "start_status_wrote": start_status_wrote,
            "stop_status_wrote": stop_status_wrote,
            "response_wrote": supervise_response_wrote,
            "background_watcher_started": false,
            "stopped": true,
            "production_file_ipc_ready": false,
            "hub_status_written": false,
        },
        "planned_start_status": start_status,
        "supervise_result": supervise_result,
        "surface_contract": surface_contract_json(),
        "authority": authority_json_with_watcher(supervise_response_wrote, start_status_wrote || stop_status_wrote),
        "checks": [
            {"name": "shadow_enabled", "ok": input.shadow_enabled, "blocking": true},
            {"name": "shadow_apply_env_enabled", "ok": input.shadow_apply_env_enabled, "blocking": input.requested_apply},
            {"name": "base_dir_explicit", "ok": true, "blocking": true},
            {"name": "base_dir_temp_safe", "ok": true, "blocking": true},
            {"name": "watcher_lock_owned_or_dry_run", "ok": !input.requested_apply || lock_acquired, "blocking": true},
            {"name": "watcher_stopped_before_return", "ok": true, "blocking": true},
            {"name": "watcher_status_not_hub_status", "ok": true, "blocking": true},
            {"name": "production_authority_unchanged", "ok": true, "blocking": false},
            {"name": "no_ml_execution_in_rust", "ok": true, "blocking": false}
        ],
    })
}

fn watcher_rollback_smoke_value(
    input: &XtFileIpcShadowInput,
    rollback_apply_enabled: bool,
) -> Value {
    let Some(base_dir) = input.base_dir.clone() else {
        return denied(input, "", "", "base_dir_required", "");
    };
    let base_dir_display = base_dir.display().to_string();
    if !input.shadow_enabled {
        return denied(
            input,
            &base_dir_display,
            "",
            "xt_file_ipc_shadow_not_enabled",
            "",
        );
    }
    if !shadow_safe_base_dir(&base_dir) {
        return denied(
            input,
            &base_dir_display,
            "",
            "base_dir_outside_shadow_sandbox",
            "",
        );
    }
    if !base_dir.is_dir() {
        return denied(input, &base_dir_display, "", "base_dir_missing", "");
    }
    if input.requested_apply && !input.shadow_apply_env_enabled {
        return denied(
            input,
            &base_dir_display,
            "",
            "xt_file_ipc_shadow_apply_not_enabled",
            "",
        );
    }
    if input.requested_apply && !rollback_apply_enabled {
        return denied(
            input,
            &base_dir_display,
            "",
            "xt_file_ipc_rollback_apply_not_enabled",
            "",
        );
    }

    let rust_owned_files = [
        ("watcher_lock", base_dir.join(WATCHER_LOCK_FILENAME)),
        ("watcher_status", base_dir.join(WATCHER_STATUS_FILENAME)),
        ("processor_status", base_dir.join(PROCESSOR_STATUS_FILENAME)),
    ];
    let planned_paths: Vec<Value> = rust_owned_files
        .iter()
        .map(|(name, path)| {
            json!({
                "name": name,
                "path": path.display().to_string(),
                "exists": path.exists(),
            })
        })
        .collect();
    let planned_remove_count = planned_paths
        .iter()
        .filter(|value| {
            value
                .get("exists")
                .and_then(Value::as_bool)
                .unwrap_or(false)
        })
        .count();

    let mut removed_paths = Vec::new();
    let mut error_message = String::new();
    if input.requested_apply {
        for (name, path) in rust_owned_files {
            if !path.exists() {
                continue;
            }
            match fs::remove_file(&path) {
                Ok(()) => removed_paths.push(json!({
                    "name": name,
                    "path": path.display().to_string(),
                })),
                Err(error) => {
                    error_message = format!("remove_shadow_file:{name}:{error}");
                    break;
                }
            }
        }
    }

    let removed_count = removed_paths.len();
    let ok = error_message.is_empty();
    json!({
        "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
        "ok": ok,
        "ready": false,
        "wrote": removed_count > 0,
        "generated_at_ms": now_ms().min(i64::MAX as u128) as i64,
        "mode": if input.requested_apply { "shadow_watcher_rollback_smoke_apply" } else { "shadow_watcher_rollback_smoke_dry_run" },
        "deny_code": if ok { "" } else { "watcher_rollback_failed" },
        "error_message": error_message,
        "root_dir": input.root_dir.display().to_string(),
        "base_dir": base_dir_display,
        "rollback": {
            "planned_paths": planned_paths,
            "planned_remove_count": planned_remove_count,
            "removed_paths": removed_paths,
            "removed_count": removed_count,
            "hub_status_removed": false,
            "xt_response_files_removed": false,
            "production_file_ipc_ready": false,
        },
        "surface_contract": surface_contract_json(),
        "authority": authority_json_with_watcher(false, false),
        "checks": [
            {"name": "shadow_enabled", "ok": input.shadow_enabled, "blocking": true},
            {"name": "shadow_apply_env_enabled", "ok": input.shadow_apply_env_enabled, "blocking": input.requested_apply},
            {"name": "rollback_apply_env_enabled", "ok": rollback_apply_enabled, "blocking": input.requested_apply},
            {"name": "base_dir_explicit", "ok": true, "blocking": true},
            {"name": "base_dir_temp_safe", "ok": true, "blocking": true},
            {"name": "removes_only_rust_shadow_files", "ok": true, "blocking": true},
            {"name": "hub_status_untouched", "ok": true, "blocking": true},
            {"name": "production_authority_unchanged", "ok": true, "blocking": false},
            {"name": "no_ml_execution_in_rust", "ok": true, "blocking": false}
        ],
    })
}

fn watcher_readiness_value(
    input: &XtFileIpcShadowInput,
    watcher_enable_env: bool,
    runtime_ready_env: bool,
    rollback_apply_enabled: bool,
) -> Value {
    let Some(base_dir) = input.base_dir.clone() else {
        return denied(input, "", "", "base_dir_required", "");
    };
    let base_dir_display = base_dir.display().to_string();
    if !input.shadow_enabled {
        return denied(
            input,
            &base_dir_display,
            "",
            "xt_file_ipc_shadow_not_enabled",
            "",
        );
    }
    if !shadow_safe_base_dir(&base_dir) {
        return denied(
            input,
            &base_dir_display,
            "",
            "base_dir_outside_shadow_sandbox",
            "",
        );
    }
    if !base_dir.is_dir() {
        return denied(input, &base_dir_display, "", "base_dir_missing", "");
    }

    let request_dir = base_dir.join("ai_requests");
    let response_dir = base_dir.join("ai_responses");
    let cancel_dir = base_dir.join("ai_cancels");
    let request_dir_ok = request_dir.is_dir();
    let response_dir_ok = response_dir.is_dir();
    let cancel_dir_ok = cancel_dir.is_dir();
    let dirs_ok = request_dir_ok && response_dir_ok && cancel_dir_ok;
    let smoke_surface_ok = watcher_enable_env && rollback_apply_enabled;
    let runtime_surface_ok = runtime_ready_env;
    let candidate_ready = dirs_ok && smoke_surface_ok && runtime_surface_ok;
    let deny_code = if dirs_ok { "" } else { "file_ipc_dirs_missing" };

    json!({
        "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
        "ok": dirs_ok,
        "ready": false,
        "wrote": false,
        "generated_at_ms": now_ms().min(i64::MAX as u128) as i64,
        "mode": "shadow_watcher_readiness_gate",
        "deny_code": deny_code,
        "root_dir": input.root_dir.display().to_string(),
        "base_dir": base_dir_display,
        "watcher_readiness": {
            "candidate_ready": candidate_ready,
            "production_file_ipc_ready": false,
            "background_watcher_started": false,
            "watcher_enable_env": watcher_enable_env,
            "runtime_ready_env": runtime_ready_env,
            "rollback_apply_env_enabled": rollback_apply_enabled,
            "request_dir": request_dir.display().to_string(),
            "response_dir": response_dir.display().to_string(),
            "cancel_dir": cancel_dir.display().to_string(),
            "request_dir_ok": request_dir_ok,
            "response_dir_ok": response_dir_ok,
            "cancel_dir_ok": cancel_dir_ok,
            "hub_status_written": false,
            "ml_execution_in_rust": false,
        },
        "surface_contract": surface_contract_json(),
        "authority": authority_json(false),
        "checks": [
            {"name": "shadow_enabled", "ok": input.shadow_enabled, "blocking": true},
            {"name": "base_dir_explicit", "ok": true, "blocking": true},
            {"name": "base_dir_temp_safe", "ok": true, "blocking": true},
            {"name": "request_dir", "ok": request_dir_ok, "blocking": true},
            {"name": "response_dir", "ok": response_dir_ok, "blocking": true},
            {"name": "cancel_dir", "ok": cancel_dir_ok, "blocking": true},
            {"name": "watcher_enable_env", "ok": watcher_enable_env, "blocking": true},
            {"name": "runtime_ready_env", "ok": runtime_ready_env, "blocking": true},
            {"name": "rollback_apply_env_enabled", "ok": rollback_apply_enabled, "blocking": true},
            {"name": "production_file_ipc_ready_remains_false", "ok": true, "blocking": true},
            {"name": "hub_status_untouched", "ok": true, "blocking": true},
            {"name": "production_authority_unchanged", "ok": true, "blocking": false},
            {"name": "no_ml_execution_in_rust", "ok": true, "blocking": false}
        ],
    })
}

fn watcher_start_plan_value(
    input: &XtFileIpcShadowInput,
    watcher_enable_env: bool,
    runtime_ready_env: bool,
    rollback_apply_enabled: bool,
    watcher_start_apply_env: bool,
) -> Value {
    let Some(base_dir) = input.base_dir.clone() else {
        return denied(input, "", "", "base_dir_required", "");
    };
    let base_dir_display = base_dir.display().to_string();
    if !input.shadow_enabled {
        return denied(
            input,
            &base_dir_display,
            "",
            "xt_file_ipc_shadow_not_enabled",
            "",
        );
    }
    if !shadow_safe_base_dir(&base_dir) {
        return denied(
            input,
            &base_dir_display,
            "",
            "base_dir_outside_shadow_sandbox",
            "",
        );
    }
    if !base_dir.is_dir() {
        return denied(input, &base_dir_display, "", "base_dir_missing", "");
    }

    let readiness = watcher_readiness_value(
        input,
        watcher_enable_env,
        runtime_ready_env,
        rollback_apply_enabled,
    );
    let candidate_ready = readiness
        .get("watcher_readiness")
        .and_then(|value| value.get("candidate_ready"))
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let request_dir_ok = readiness
        .get("watcher_readiness")
        .and_then(|value| value.get("request_dir_ok"))
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let response_dir_ok = readiness
        .get("watcher_readiness")
        .and_then(|value| value.get("response_dir_ok"))
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let cancel_dir_ok = readiness
        .get("watcher_readiness")
        .and_then(|value| value.get("cancel_dir_ok"))
        .and_then(Value::as_bool)
        .unwrap_or(false);

    let mut blockers = Vec::new();
    if !request_dir_ok {
        blockers.push("request_dir_missing");
    }
    if !response_dir_ok {
        blockers.push("response_dir_missing");
    }
    if !cancel_dir_ok {
        blockers.push("cancel_dir_missing");
    }
    if !watcher_enable_env {
        blockers.push("watcher_enable_env_missing");
    }
    if !runtime_ready_env {
        blockers.push("runtime_ready_env_missing");
    }
    if !rollback_apply_enabled {
        blockers.push("rollback_apply_env_missing");
    }
    if !watcher_start_apply_env {
        blockers.push("watcher_start_apply_env_missing");
    }

    let start_candidate = candidate_ready && watcher_start_apply_env;

    json!({
        "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
        "ok": true,
        "ready": false,
        "wrote": false,
        "generated_at_ms": now_ms().min(i64::MAX as u128) as i64,
        "mode": "shadow_watcher_start_plan",
        "deny_code": if blockers.is_empty() { "" } else { "watcher_start_blocked" },
        "root_dir": input.root_dir.display().to_string(),
        "base_dir": base_dir_display,
        "watcher_start_plan": {
            "start_candidate": start_candidate,
            "blockers": blockers,
            "background_watcher_started": false,
            "long_running_thread_started": false,
            "status_path": base_dir.join(WATCHER_STATUS_FILENAME).display().to_string(),
            "lock_path": base_dir.join(WATCHER_LOCK_FILENAME).display().to_string(),
            "hub_status_written": false,
            "production_file_ipc_ready": false,
            "ml_execution_in_rust": false,
            "requires_followup": "default_off_background_watcher_lifecycle",
        },
        "readiness_result": readiness,
        "surface_contract": surface_contract_json(),
        "authority": authority_json(false),
        "checks": [
            {"name": "shadow_enabled", "ok": input.shadow_enabled, "blocking": true},
            {"name": "base_dir_explicit", "ok": true, "blocking": true},
            {"name": "base_dir_temp_safe", "ok": true, "blocking": true},
            {"name": "watcher_readiness_candidate", "ok": candidate_ready, "blocking": true},
            {"name": "watcher_start_apply_env", "ok": watcher_start_apply_env, "blocking": true},
            {"name": "background_watcher_not_started", "ok": true, "blocking": true},
            {"name": "hub_status_untouched", "ok": true, "blocking": true},
            {"name": "production_file_ipc_ready_remains_false", "ok": true, "blocking": true},
            {"name": "production_authority_unchanged", "ok": true, "blocking": false},
            {"name": "no_ml_execution_in_rust", "ok": true, "blocking": false}
        ],
    })
}

fn watcher_run_once_value(
    input: &XtFileIpcShadowInput,
    watcher_enable_env: bool,
    runtime_ready_env: bool,
    rollback_apply_enabled: bool,
    watcher_start_apply_env: bool,
    watcher_run_once_apply_env: bool,
) -> Value {
    let Some(base_dir) = input.base_dir.clone() else {
        return denied(input, "", "", "base_dir_required", "");
    };
    let base_dir_display = base_dir.display().to_string();
    if !input.shadow_enabled {
        return denied(
            input,
            &base_dir_display,
            "",
            "xt_file_ipc_shadow_not_enabled",
            "",
        );
    }
    if !shadow_safe_base_dir(&base_dir) {
        return denied(
            input,
            &base_dir_display,
            "",
            "base_dir_outside_shadow_sandbox",
            "",
        );
    }
    if !base_dir.is_dir() {
        return denied(input, &base_dir_display, "", "base_dir_missing", "");
    }
    if input.requested_apply && !input.shadow_apply_env_enabled {
        return denied(
            input,
            &base_dir_display,
            "",
            "xt_file_ipc_shadow_apply_not_enabled",
            "",
        );
    }

    let start_plan = watcher_start_plan_value(
        input,
        watcher_enable_env,
        runtime_ready_env,
        rollback_apply_enabled,
        watcher_start_apply_env,
    );
    let start_candidate = start_plan
        .get("watcher_start_plan")
        .and_then(|value| value.get("start_candidate"))
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let mut blockers = start_plan
        .get("watcher_start_plan")
        .and_then(|value| value.get("blockers"))
        .and_then(Value::as_array)
        .map(|values| {
            values
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_string)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    if !watcher_run_once_apply_env {
        blockers.push("watcher_run_once_apply_env_missing".to_string());
    }
    let run_candidate = start_candidate && watcher_run_once_apply_env;

    if input.requested_apply && !run_candidate {
        return json!({
            "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
            "ok": false,
            "ready": false,
            "wrote": false,
            "generated_at_ms": now_ms().min(i64::MAX as u128) as i64,
            "mode": "shadow_watcher_run_once_blocked",
            "deny_code": "watcher_run_once_blocked",
            "root_dir": input.root_dir.display().to_string(),
            "base_dir": base_dir_display,
            "watcher_run_once": {
                "run_candidate": false,
                "blockers": blockers,
                "background_watcher_started": false,
                "long_running_thread_started": false,
                "lock_acquired": false,
                "lock_released": false,
                "start_status_wrote": false,
                "stop_status_wrote": false,
                "cycle_executed": false,
                "hub_status_written": false,
                "production_file_ipc_ready": false,
                "ml_execution_in_rust": false,
            },
            "start_plan_result": start_plan,
            "surface_contract": surface_contract_json(),
            "authority": authority_json(false),
        });
    }

    if !input.requested_apply {
        return json!({
            "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
            "ok": true,
            "ready": false,
            "wrote": false,
            "generated_at_ms": now_ms().min(i64::MAX as u128) as i64,
            "mode": "shadow_watcher_run_once_dry_run",
            "deny_code": if blockers.is_empty() { "" } else { "watcher_run_once_blocked" },
            "root_dir": input.root_dir.display().to_string(),
            "base_dir": base_dir_display,
            "watcher_run_once": {
                "run_candidate": run_candidate,
                "blockers": blockers,
                "background_watcher_started": false,
                "long_running_thread_started": false,
                "lock_acquired": false,
                "lock_released": false,
                "start_status_wrote": false,
                "stop_status_wrote": false,
                "cycle_executed": false,
                "hub_status_written": false,
                "production_file_ipc_ready": false,
                "ml_execution_in_rust": false,
            },
            "start_plan_result": start_plan,
            "surface_contract": surface_contract_json(),
            "authority": authority_json(false),
        });
    }

    let watcher_id = format!("watcher-run-once-{}-{}", process::id(), now_ms());
    let lock_path = base_dir.join(WATCHER_LOCK_FILENAME);
    let status_path = base_dir.join(WATCHER_STATUS_FILENAME);
    let start_status = watcher_status_json(input, &base_dir, &watcher_id, "starting", false, None);
    let mut start_status_wrote = false;
    let mut stop_status_wrote = false;
    let mut lock_acquired = false;
    let mut lock_released = false;
    let mut error_message = String::new();

    match acquire_watcher_lock(&lock_path, &watcher_id) {
        Ok(()) => {
            lock_acquired = true;
            match write_json_atomic(&status_path, &start_status) {
                Ok(()) => start_status_wrote = true,
                Err(error) => error_message = error,
            }
        }
        Err(error) => error_message = error,
    }

    let mut cycle_result = json!({
        "ok": false,
        "wrote": false,
        "deny_code": "watcher_lock_not_acquired",
    });
    if lock_acquired && error_message.is_empty() {
        cycle_result = cycle_once_value(input);
    }
    let cycle_ok = cycle_result
        .get("ok")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let cycle_wrote = cycle_result
        .get("wrote")
        .and_then(Value::as_bool)
        .unwrap_or(false);

    if lock_acquired {
        let stop_status = watcher_status_json(
            input,
            &base_dir,
            &watcher_id,
            "stopped",
            cycle_ok,
            Some(cycle_result.clone()),
        );
        match write_json_atomic(&status_path, &stop_status) {
            Ok(()) => stop_status_wrote = true,
            Err(error) => {
                if error_message.is_empty() {
                    error_message = error;
                }
            }
        }
        match fs::remove_file(&lock_path) {
            Ok(()) => lock_released = true,
            Err(error) => {
                if error_message.is_empty() {
                    error_message = format!("release_watcher_lock:{error}");
                }
            }
        }
    }

    let ok = lock_acquired
        && start_status_wrote
        && stop_status_wrote
        && lock_released
        && cycle_ok
        && error_message.is_empty();
    let deny_code = if ok {
        ""
    } else if !error_message.is_empty() && error_message.starts_with("watcher_lock_busy") {
        "watcher_lock_busy"
    } else if !error_message.is_empty() {
        "watcher_run_once_failed"
    } else {
        "watcher_cycle_failed"
    };

    json!({
        "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
        "ok": ok,
        "ready": false,
        "wrote": start_status_wrote || stop_status_wrote || cycle_wrote,
        "generated_at_ms": now_ms().min(i64::MAX as u128) as i64,
        "mode": "shadow_watcher_run_once_apply",
        "deny_code": deny_code,
        "error_message": error_message,
        "root_dir": input.root_dir.display().to_string(),
        "base_dir": base_dir_display,
        "watcher_run_once": {
            "run_candidate": run_candidate,
            "blockers": blockers,
            "watcher_id": watcher_id,
            "status_path": status_path.display().to_string(),
            "lock_path": lock_path.display().to_string(),
            "background_watcher_started": false,
            "long_running_thread_started": false,
            "lock_acquired": lock_acquired,
            "lock_released": lock_released,
            "start_status_wrote": start_status_wrote,
            "stop_status_wrote": stop_status_wrote,
            "cycle_executed": lock_acquired && error_message.is_empty(),
            "cycle_wrote": cycle_wrote,
            "hub_status_written": false,
            "production_file_ipc_ready": false,
            "ml_execution_in_rust": false,
        },
        "start_plan_result": start_plan,
        "cycle_result": cycle_result,
        "surface_contract": surface_contract_json(),
        "authority": authority_json_with_watcher(cycle_wrote, start_status_wrote || stop_status_wrote),
    })
}

fn watcher_session_value(
    input: &XtFileIpcShadowInput,
    watcher_enable_env: bool,
    runtime_ready_env: bool,
    rollback_apply_enabled: bool,
    watcher_start_apply_env: bool,
    watcher_session_apply_env: bool,
) -> Value {
    let Some(base_dir) = input.base_dir.clone() else {
        return denied(input, "", "", "base_dir_required", "");
    };
    let base_dir_display = base_dir.display().to_string();
    if !input.shadow_enabled {
        return denied(
            input,
            &base_dir_display,
            "",
            "xt_file_ipc_shadow_not_enabled",
            "",
        );
    }
    if !shadow_safe_base_dir(&base_dir) {
        return denied(
            input,
            &base_dir_display,
            "",
            "base_dir_outside_shadow_sandbox",
            "",
        );
    }
    if !base_dir.is_dir() {
        return denied(input, &base_dir_display, "", "base_dir_missing", "");
    }
    if input.requested_apply && !input.shadow_apply_env_enabled {
        return denied(
            input,
            &base_dir_display,
            "",
            "xt_file_ipc_shadow_apply_not_enabled",
            "",
        );
    }

    let start_plan = watcher_start_plan_value(
        input,
        watcher_enable_env,
        runtime_ready_env,
        rollback_apply_enabled,
        watcher_start_apply_env,
    );
    let start_candidate = start_plan
        .get("watcher_start_plan")
        .and_then(|value| value.get("start_candidate"))
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let mut blockers = start_plan
        .get("watcher_start_plan")
        .and_then(|value| value.get("blockers"))
        .and_then(Value::as_array)
        .map(|values| {
            values
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_string)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    if !watcher_session_apply_env {
        blockers.push("watcher_session_apply_env_missing".to_string());
    }
    let session_candidate = start_candidate && watcher_session_apply_env;

    if input.requested_apply && !session_candidate {
        return json!({
            "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
            "ok": false,
            "ready": false,
            "wrote": false,
            "generated_at_ms": now_ms().min(i64::MAX as u128) as i64,
            "mode": "shadow_watcher_session_blocked",
            "deny_code": "watcher_session_blocked",
            "root_dir": input.root_dir.display().to_string(),
            "base_dir": base_dir_display,
            "watcher_session": {
                "session_candidate": false,
                "blockers": blockers,
                "background_watcher_started": false,
                "long_running_thread_started": false,
                "lock_acquired": false,
                "lock_released": false,
                "start_status_wrote": false,
                "stop_status_wrote": false,
                "supervisor_executed": false,
                "hub_status_written": false,
                "production_file_ipc_ready": false,
                "ml_execution_in_rust": false,
            },
            "start_plan_result": start_plan,
            "surface_contract": surface_contract_json(),
            "authority": authority_json(false),
        });
    }

    if !input.requested_apply {
        return json!({
            "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
            "ok": true,
            "ready": false,
            "wrote": false,
            "generated_at_ms": now_ms().min(i64::MAX as u128) as i64,
            "mode": "shadow_watcher_session_dry_run",
            "deny_code": if blockers.is_empty() { "" } else { "watcher_session_blocked" },
            "root_dir": input.root_dir.display().to_string(),
            "base_dir": base_dir_display,
            "watcher_session": {
                "session_candidate": session_candidate,
                "blockers": blockers,
                "max_cycles": input.max_cycles,
                "cycle_interval_ms": input.cycle_interval_ms,
                "background_watcher_started": false,
                "long_running_thread_started": false,
                "lock_acquired": false,
                "lock_released": false,
                "start_status_wrote": false,
                "stop_status_wrote": false,
                "supervisor_executed": false,
                "hub_status_written": false,
                "production_file_ipc_ready": false,
                "ml_execution_in_rust": false,
            },
            "start_plan_result": start_plan,
            "surface_contract": surface_contract_json(),
            "authority": authority_json(false),
        });
    }

    let watcher_id = format!("watcher-session-{}-{}", process::id(), now_ms());
    let lock_path = base_dir.join(WATCHER_LOCK_FILENAME);
    let status_path = base_dir.join(WATCHER_STATUS_FILENAME);
    let start_status = watcher_status_json(input, &base_dir, &watcher_id, "starting", false, None);
    let mut start_status_wrote = false;
    let mut stop_status_wrote = false;
    let mut lock_acquired = false;
    let mut lock_released = false;
    let mut error_message = String::new();

    match acquire_watcher_lock(&lock_path, &watcher_id) {
        Ok(()) => {
            lock_acquired = true;
            match write_json_atomic(&status_path, &start_status) {
                Ok(()) => start_status_wrote = true,
                Err(error) => error_message = error,
            }
        }
        Err(error) => error_message = error,
    }

    let mut supervise_result = json!({
        "ok": false,
        "wrote": false,
        "deny_code": "watcher_lock_not_acquired",
    });
    if lock_acquired && error_message.is_empty() {
        supervise_result = supervise_bounded_value(input);
    }
    let supervise_ok = supervise_result
        .get("ok")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let supervise_wrote = supervise_result
        .get("wrote")
        .and_then(Value::as_bool)
        .unwrap_or(false);

    if lock_acquired {
        let stop_status = watcher_status_json(
            input,
            &base_dir,
            &watcher_id,
            "stopped",
            supervise_ok,
            Some(supervise_result.clone()),
        );
        match write_json_atomic(&status_path, &stop_status) {
            Ok(()) => stop_status_wrote = true,
            Err(error) => {
                if error_message.is_empty() {
                    error_message = error;
                }
            }
        }
        match fs::remove_file(&lock_path) {
            Ok(()) => lock_released = true,
            Err(error) => {
                if error_message.is_empty() {
                    error_message = format!("release_watcher_lock:{error}");
                }
            }
        }
    }

    let ok = lock_acquired
        && start_status_wrote
        && stop_status_wrote
        && lock_released
        && supervise_ok
        && error_message.is_empty();
    let deny_code = if ok {
        ""
    } else if !error_message.is_empty() && error_message.starts_with("watcher_lock_busy") {
        "watcher_lock_busy"
    } else if !error_message.is_empty() {
        "watcher_session_failed"
    } else {
        "watcher_session_supervisor_failed"
    };

    json!({
        "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
        "ok": ok,
        "ready": false,
        "wrote": start_status_wrote || stop_status_wrote || supervise_wrote,
        "generated_at_ms": now_ms().min(i64::MAX as u128) as i64,
        "mode": "shadow_watcher_session_apply",
        "deny_code": deny_code,
        "error_message": error_message,
        "root_dir": input.root_dir.display().to_string(),
        "base_dir": base_dir_display,
        "watcher_session": {
            "session_candidate": session_candidate,
            "blockers": blockers,
            "watcher_id": watcher_id,
            "status_path": status_path.display().to_string(),
            "lock_path": lock_path.display().to_string(),
            "max_cycles": input.max_cycles,
            "cycle_interval_ms": input.cycle_interval_ms,
            "background_watcher_started": false,
            "long_running_thread_started": false,
            "lock_acquired": lock_acquired,
            "lock_released": lock_released,
            "start_status_wrote": start_status_wrote,
            "stop_status_wrote": stop_status_wrote,
            "supervisor_executed": lock_acquired && error_message.is_empty(),
            "supervisor_wrote": supervise_wrote,
            "hub_status_written": false,
            "production_file_ipc_ready": false,
            "ml_execution_in_rust": false,
        },
        "start_plan_result": start_plan,
        "supervisor_result": supervise_result,
        "surface_contract": surface_contract_json(),
        "authority": authority_json_with_watcher(supervise_wrote, start_status_wrote || stop_status_wrote),
        "checks": [
            {"name": "shadow_enabled", "ok": input.shadow_enabled, "blocking": true},
            {"name": "shadow_apply_env_enabled", "ok": input.shadow_apply_env_enabled, "blocking": true},
            {"name": "watcher_session_apply_env", "ok": watcher_session_apply_env, "blocking": true},
            {"name": "base_dir_explicit", "ok": true, "blocking": true},
            {"name": "base_dir_temp_safe", "ok": true, "blocking": true},
            {"name": "bounded_cycles", "ok": input.max_cycles <= 10, "blocking": true},
            {"name": "background_watcher_not_started", "ok": true, "blocking": true},
            {"name": "hub_status_untouched", "ok": true, "blocking": true},
            {"name": "production_file_ipc_ready_remains_false", "ok": true, "blocking": true},
            {"name": "production_authority_unchanged", "ok": true, "blocking": false},
            {"name": "no_ml_execution_in_rust", "ok": true, "blocking": false}
        ],
    })
}

fn watcher_background_start_value(
    input: &XtFileIpcShadowInput,
    watcher_enable_env: bool,
    runtime_ready_env: bool,
    rollback_apply_enabled: bool,
    watcher_start_apply_env: bool,
    watcher_background_apply_env: bool,
) -> Value {
    let Some(base_dir) = input.base_dir.clone() else {
        return denied(input, "", "", "base_dir_required", "");
    };
    let base_dir_display = base_dir.display().to_string();
    if !input.shadow_enabled {
        return denied(
            input,
            &base_dir_display,
            "",
            "xt_file_ipc_shadow_not_enabled",
            "",
        );
    }
    if !shadow_safe_base_dir(&base_dir) {
        return denied(
            input,
            &base_dir_display,
            "",
            "base_dir_outside_shadow_sandbox",
            "",
        );
    }
    if !base_dir.is_dir() {
        return denied(input, &base_dir_display, "", "base_dir_missing", "");
    }
    if input.requested_apply && !input.shadow_apply_env_enabled {
        return denied(
            input,
            &base_dir_display,
            "",
            "xt_file_ipc_shadow_apply_not_enabled",
            "",
        );
    }

    let start_plan = watcher_start_plan_value(
        input,
        watcher_enable_env,
        runtime_ready_env,
        rollback_apply_enabled,
        watcher_start_apply_env,
    );
    let start_candidate = start_plan
        .get("watcher_start_plan")
        .and_then(|value| value.get("start_candidate"))
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let mut blockers = start_plan
        .get("watcher_start_plan")
        .and_then(|value| value.get("blockers"))
        .and_then(Value::as_array)
        .map(|values| {
            values
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_string)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    if !watcher_background_apply_env {
        blockers.push("watcher_background_apply_env_missing".to_string());
    }
    let background_candidate = start_candidate && watcher_background_apply_env;

    if input.requested_apply && !background_candidate {
        return json!({
            "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
            "ok": false,
            "ready": false,
            "wrote": false,
            "generated_at_ms": now_ms().min(i64::MAX as u128) as i64,
            "mode": "shadow_watcher_background_start_blocked",
            "deny_code": "watcher_background_start_blocked",
            "root_dir": input.root_dir.display().to_string(),
            "base_dir": base_dir_display,
            "watcher_background": background_contract_json(false, false, false, input.max_cycles, input.cycle_interval_ms, blockers),
            "start_plan_result": start_plan,
            "surface_contract": surface_contract_json(),
            "authority": authority_json(false),
        });
    }

    if !input.requested_apply {
        return json!({
            "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
            "ok": true,
            "ready": false,
            "wrote": false,
            "generated_at_ms": now_ms().min(i64::MAX as u128) as i64,
            "mode": "shadow_watcher_background_start_dry_run",
            "deny_code": if blockers.is_empty() { "" } else { "watcher_background_start_blocked" },
            "root_dir": input.root_dir.display().to_string(),
            "base_dir": base_dir_display,
            "watcher_background": background_contract_json(background_candidate, false, false, input.max_cycles, input.cycle_interval_ms, blockers),
            "start_plan_result": start_plan,
            "surface_contract": surface_contract_json(),
            "authority": authority_json(false),
        });
    }

    let watcher_id = format!("watcher-background-{}-{}", process::id(), now_ms());
    let lock_path = base_dir.join(WATCHER_LOCK_FILENAME);
    let status_path = base_dir.join(WATCHER_STATUS_FILENAME);
    let stop_flag = Arc::new(AtomicBool::new(false));

    {
        let runtime = background_watcher_runtime().lock();
        let Ok(runtime) = runtime else {
            return denied(
                input,
                &base_dir_display,
                "",
                "watcher_background_runtime_lock_failed",
                "",
            );
        };
        if runtime.active {
            return json!({
                "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
                "ok": false,
                "ready": false,
                "wrote": false,
                "generated_at_ms": now_ms().min(i64::MAX as u128) as i64,
                "mode": "shadow_watcher_background_start_blocked",
                "deny_code": "watcher_background_already_active",
                "root_dir": input.root_dir.display().to_string(),
                "base_dir": base_dir_display,
                "watcher_background": background_runtime_json(&runtime),
                "surface_contract": surface_contract_json(),
                "authority": authority_json(false),
            });
        }
    }

    if let Err(error) = acquire_watcher_lock(&lock_path, &watcher_id) {
        let deny_code = if error.starts_with("watcher_lock_busy") {
            "watcher_lock_busy"
        } else {
            "watcher_background_lock_failed"
        };
        return json!({
            "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
            "ok": false,
            "ready": false,
            "wrote": false,
            "generated_at_ms": now_ms().min(i64::MAX as u128) as i64,
            "mode": "shadow_watcher_background_start_failed",
            "deny_code": deny_code,
            "error_message": error,
            "root_dir": input.root_dir.display().to_string(),
            "base_dir": base_dir_display,
            "watcher_background": background_contract_json(true, false, false, input.max_cycles, input.cycle_interval_ms, Vec::new()),
            "surface_contract": surface_contract_json(),
            "authority": authority_json(false),
        });
    }

    let started_at_ms = now_ms().min(i64::MAX as u128) as i64;
    let start_status =
        background_watcher_status_json(input, &base_dir, &watcher_id, "running", 0, 0, json!(null));
    if let Err(error) = write_json_atomic(&status_path, &start_status) {
        let _ = fs::remove_file(&lock_path);
        return json!({
            "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
            "ok": false,
            "ready": false,
            "wrote": false,
            "generated_at_ms": now_ms().min(i64::MAX as u128) as i64,
            "mode": "shadow_watcher_background_start_failed",
            "deny_code": "watcher_status_write_failed",
            "error_message": error,
            "root_dir": input.root_dir.display().to_string(),
            "base_dir": base_dir_display,
            "watcher_background": background_contract_json(true, false, false, input.max_cycles, input.cycle_interval_ms, Vec::new()),
            "surface_contract": surface_contract_json(),
            "authority": authority_json(false),
        });
    }

    {
        let runtime = background_watcher_runtime().lock();
        if let Ok(mut runtime) = runtime {
            *runtime = BackgroundWatcherRuntime {
                active: true,
                watcher_id: watcher_id.clone(),
                base_dir: base_dir_display.clone(),
                started_at_ms,
                finished_at_ms: 0,
                max_cycles: input.max_cycles,
                cycle_interval_ms: input.cycle_interval_ms,
                completed_cycles: 0,
                wrote_count: 0,
                stop_requested: false,
                last_error: String::new(),
                stop_flag: Some(Arc::clone(&stop_flag)),
            };
        }
    }

    let mut thread_input = input.clone();
    thread_input.req_id = None;
    thread::spawn(move || {
        run_background_watcher_thread(thread_input, base_dir, watcher_id, lock_path, stop_flag);
    });

    json!({
        "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
        "ok": true,
        "ready": false,
        "wrote": true,
        "generated_at_ms": now_ms().min(i64::MAX as u128) as i64,
        "mode": "shadow_watcher_background_start_apply",
        "deny_code": "",
        "root_dir": input.root_dir.display().to_string(),
        "base_dir": base_dir_display,
        "watcher_background": background_contract_json(true, true, true, input.max_cycles, input.cycle_interval_ms, Vec::new()),
        "start_plan_result": start_plan,
        "surface_contract": surface_contract_json(),
        "authority": authority_json_with_watcher(false, true),
        "checks": [
            {"name": "shadow_enabled", "ok": input.shadow_enabled, "blocking": true},
            {"name": "shadow_apply_env_enabled", "ok": input.shadow_apply_env_enabled, "blocking": true},
            {"name": "watcher_background_apply_env", "ok": watcher_background_apply_env, "blocking": true},
            {"name": "base_dir_explicit", "ok": true, "blocking": true},
            {"name": "base_dir_temp_safe", "ok": true, "blocking": true},
            {"name": "background_watcher_started", "ok": true, "blocking": true},
            {"name": "bounded_cycles", "ok": input.max_cycles <= 10, "blocking": true},
            {"name": "hub_status_untouched", "ok": true, "blocking": true},
            {"name": "production_file_ipc_ready_remains_false", "ok": true, "blocking": true},
            {"name": "production_authority_unchanged", "ok": true, "blocking": false},
            {"name": "no_ml_execution_in_rust", "ok": true, "blocking": false}
        ],
    })
}

fn watcher_background_stop_value(input: &XtFileIpcShadowInput) -> Value {
    let stop_flag = {
        let runtime = background_watcher_runtime().lock();
        let Ok(mut runtime) = runtime else {
            return denied(input, "", "", "watcher_background_runtime_lock_failed", "");
        };
        if !runtime.active {
            return json!({
                "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
                "ok": true,
                "ready": false,
                "wrote": false,
                "generated_at_ms": now_ms().min(i64::MAX as u128) as i64,
                "mode": "shadow_watcher_background_stop_noop",
                "deny_code": "",
                "watcher_background": background_runtime_json(&runtime),
                "surface_contract": surface_contract_json(),
                "authority": authority_json(false),
            });
        }
        runtime.stop_requested = true;
        runtime.stop_flag.clone()
    };
    if let Some(flag) = stop_flag {
        flag.store(true, Ordering::SeqCst);
    }

    for _ in 0..100 {
        let inactive = background_watcher_runtime()
            .lock()
            .map(|runtime| !runtime.active)
            .unwrap_or(false);
        if inactive {
            break;
        }
        thread::sleep(Duration::from_millis(10));
    }

    let runtime = background_watcher_runtime().lock();
    let runtime_json = runtime
        .as_ref()
        .map(|runtime| background_runtime_json(runtime))
        .unwrap_or_else(|_| json!({ "active": false, "lock_error": true }));
    let stopped = runtime_json
        .get("active")
        .and_then(Value::as_bool)
        .map(|active| !active)
        .unwrap_or(false);
    json!({
        "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
        "ok": stopped,
        "ready": false,
        "wrote": false,
        "generated_at_ms": now_ms().min(i64::MAX as u128) as i64,
        "mode": "shadow_watcher_background_stop",
        "deny_code": if stopped { "" } else { "watcher_background_stop_pending" },
        "watcher_background": runtime_json,
        "surface_contract": surface_contract_json(),
        "authority": authority_json(false),
    })
}

fn watcher_background_status_value() -> Value {
    let runtime = background_watcher_runtime().lock();
    let runtime_json = runtime
        .as_ref()
        .map(|runtime| background_runtime_json(runtime))
        .unwrap_or_else(|_| json!({ "active": false, "lock_error": true }));
    json!({
        "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
        "ok": true,
        "ready": false,
        "wrote": false,
        "generated_at_ms": now_ms().min(i64::MAX as u128) as i64,
        "mode": "shadow_watcher_background_status",
        "deny_code": "",
        "watcher_background": runtime_json,
        "surface_contract": surface_contract_json(),
        "authority": authority_json(false),
    })
}

fn runtime_execution_plan_value(
    config: &HubConfig,
    input: &XtFileIpcShadowInput,
    runtime_plan_env: bool,
    runtime_ready_env: bool,
    production_cutover_env: bool,
) -> Value {
    let Some(base_dir) = input.base_dir.clone() else {
        return denied(input, "", "", "base_dir_required", "");
    };
    let base_dir_display = base_dir.display().to_string();
    if !input.shadow_enabled {
        return denied(
            input,
            &base_dir_display,
            "",
            "xt_file_ipc_shadow_not_enabled",
            "",
        );
    }
    if !shadow_safe_base_dir(&base_dir) {
        return denied(
            input,
            &base_dir_display,
            "",
            "base_dir_outside_shadow_sandbox",
            "",
        );
    }
    if !base_dir.is_dir() {
        return denied(input, &base_dir_display, "", "base_dir_missing", "");
    }

    let req_id = match input
        .req_id
        .clone()
        .filter(|value| !value.trim().is_empty())
    {
        Some(value) => value,
        None => match discover_single_request_id(&base_dir.join("ai_requests")) {
            Ok(value) => value,
            Err(code) => return denied(input, &base_dir_display, "", code.as_str(), ""),
        },
    };
    if !safe_request_id(&req_id) {
        return denied(input, &base_dir_display, &req_id, "unsafe_request_id", "");
    }

    let req_path = request_path(&base_dir, &req_id);
    let request = match read_json(&req_path) {
        Ok(value) => value,
        Err(error) => {
            if let Some(bytes) = error.strip_prefix("request_file_too_large:") {
                return denied(
                    input,
                    &base_dir_display,
                    &req_id,
                    "request_file_too_large",
                    bytes,
                );
            }
            if let Some(message) = error.strip_prefix("request_json_invalid:") {
                return denied(
                    input,
                    &base_dir_display,
                    &req_id,
                    "request_json_invalid",
                    message,
                );
            }
            return denied(
                input,
                &base_dir_display,
                &req_id,
                "request_read_failed",
                error.as_str(),
            );
        }
    };
    let request_type = value_string(&request, "type").unwrap_or_else(|| "generate".to_string());
    if request_type != "generate" {
        return denied(
            input,
            &base_dir_display,
            &req_id,
            "unsupported_request_type",
            request_type.as_str(),
        );
    }
    if let Some(prompt_chars) = oversized_prompt_chars(&request) {
        return denied(
            input,
            &base_dir_display,
            &req_id,
            "request_prompt_too_large",
            prompt_chars.to_string().as_str(),
        );
    }

    let model_id = effective_request_model_id(&request);
    let task_type =
        value_string(&request, "task_type").unwrap_or_else(|| "text_generate".to_string());
    let request_contract = request_contract_json(&request, &model_id, &task_type);
    let route_request = model_bridge::ModelRouteRequest {
        task_type: task_type.clone(),
        model_id: if model_id.trim().is_empty() {
            "auto".to_string()
        } else {
            model_id.clone()
        },
        required_capabilities: Vec::new(),
        privacy_mode: "standard".to_string(),
        cost_preference: "balanced".to_string(),
    };
    let route_value = model_bridge::route_json_from_parts(
        config,
        Some(input.runtime_base_dir.clone()),
        route_request,
        Some(input.now_ms),
    )
    .ok()
    .and_then(|raw| serde_json::from_str::<Value>(&raw).ok())
    .unwrap_or_else(|| {
        json!({
            "schema_version": "xhub.model_route_decision.v1",
            "ok": false,
            "selected_route_kind": "",
            "selected_model_id": "",
            "blocking_reason_code": "model_route_failed"
        })
    });

    let selected_model_id = route_value
        .get("selected_model_id")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    let selected_route_kind = route_value
        .get("selected_route_kind")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    let model_route_ready = !selected_model_id.trim().is_empty();
    let mut blockers = Vec::new();
    if !runtime_plan_env {
        blockers.push("runtime_plan_env_missing");
    }
    if !model_route_ready {
        blockers.push("model_route_no_selected_model");
    }
    if !runtime_ready_env {
        blockers.push("runtime_ready_env_missing");
    }
    if !production_cutover_env {
        blockers.push("production_cutover_env_missing");
    }
    let dry_run_candidate = runtime_plan_env && model_route_ready;
    let production_candidate = dry_run_candidate && runtime_ready_env && production_cutover_env;
    let adapter_kind = match selected_route_kind.as_str() {
        "local" => "local_runtime_file_ipc",
        "remote" => "remote_provider_route",
        _ => "none",
    };

    json!({
        "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
        "ok": true,
        "ready": false,
        "wrote": false,
        "generated_at_ms": input.now_ms.min(i64::MAX as u128) as i64,
        "mode": "shadow_runtime_execution_plan",
        "deny_code": if blockers.is_empty() { "" } else { "runtime_execution_plan_blocked" },
        "root_dir": input.root_dir.display().to_string(),
        "base_dir": base_dir_display,
        "runtime_base_dir": input.runtime_base_dir.display().to_string(),
        "req_id": req_id,
        "request_path": req_path.display().to_string(),
        "request": request_contract,
        "model_route": route_value,
        "execution_adapter_plan": {
            "dry_run_candidate": dry_run_candidate,
            "production_candidate": production_candidate,
            "adapter_kind": adapter_kind,
            "selected_route_kind": selected_route_kind,
            "selected_model_id": selected_model_id,
            "blockers": blockers,
            "requires_runtime_plan_env": true,
            "requires_runtime_ready_env": true,
            "requires_production_cutover_env": true,
            "writes_response": false,
            "executes_ml": false,
            "hub_status_written": false,
            "production_file_ipc_ready": false,
        },
        "surface_contract": surface_contract_json(),
        "authority": authority_json(false),
        "checks": [
            {"name": "shadow_enabled", "ok": input.shadow_enabled, "blocking": true},
            {"name": "runtime_plan_env", "ok": runtime_plan_env, "blocking": false},
            {"name": "request_file_exists", "ok": true, "blocking": true},
            {"name": "model_route_ready", "ok": model_route_ready, "blocking": false},
            {"name": "runtime_ready_env", "ok": runtime_ready_env, "blocking": false},
            {"name": "production_cutover_env", "ok": production_cutover_env, "blocking": false},
            {"name": "response_not_written", "ok": true, "blocking": true},
            {"name": "production_file_ipc_ready_remains_false", "ok": true, "blocking": true},
            {"name": "no_ml_execution_in_rust", "ok": true, "blocking": false}
        ],
    })
}

fn runtime_adapter_candidate_value(
    config: &HubConfig,
    input: &XtFileIpcShadowInput,
    runtime_plan_env: bool,
    adapter_candidate_env: bool,
) -> Value {
    let plan = runtime_execution_plan_value(config, input, runtime_plan_env, false, false);
    if plan.get("ok").and_then(Value::as_bool).unwrap_or(false) != true {
        return plan;
    }

    let base_dir = match input.base_dir.clone() {
        Some(value) => value,
        None => return denied(input, "", "", "base_dir_required", ""),
    };
    let base_dir_display = base_dir.display().to_string();
    let req_id = plan
        .get("req_id")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    if !safe_request_id(&req_id) {
        return denied(input, &base_dir_display, &req_id, "unsafe_request_id", "");
    }
    let resp_path = response_path(&base_dir, &req_id);
    let cancel_path = cancel_path(&base_dir, &req_id);
    if resp_path.exists() {
        if !input.overwrite_response {
            return denied(
                input,
                &base_dir_display,
                &req_id,
                "response_already_exists",
                "",
            );
        }
        if !overwrite_response_env_enabled() {
            return denied(
                input,
                &base_dir_display,
                &req_id,
                "response_overwrite_not_enabled",
                "",
            );
        }
    }

    let execution_plan = plan
        .get("execution_adapter_plan")
        .cloned()
        .unwrap_or_else(|| json!({}));
    let dry_run_candidate = execution_plan
        .get("dry_run_candidate")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let adapter_kind = execution_plan
        .get("adapter_kind")
        .and_then(Value::as_str)
        .unwrap_or("none")
        .to_string();
    let selected_route_kind = execution_plan
        .get("selected_route_kind")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    let selected_model_id = execution_plan
        .get("selected_model_id")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    let mut blockers = Vec::new();
    if !runtime_plan_env {
        blockers.push("runtime_plan_env_missing");
    }
    if !adapter_candidate_env {
        blockers.push("runtime_adapter_candidate_env_missing");
    }
    if !dry_run_candidate {
        blockers.push("runtime_execution_plan_not_candidate");
    }
    if !input.requested_apply {
        blockers.push("apply_required");
    }
    if !input.shadow_apply_env_enabled {
        blockers.push("shadow_apply_env_missing");
    }

    if !blockers.is_empty() {
        return json!({
            "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
            "ok": false,
            "ready": false,
            "wrote": false,
            "generated_at_ms": input.now_ms.min(i64::MAX as u128) as i64,
            "mode": "shadow_runtime_adapter_candidate_blocked",
            "deny_code": "runtime_adapter_candidate_blocked",
            "root_dir": input.root_dir.display().to_string(),
            "base_dir": base_dir_display,
            "runtime_base_dir": input.runtime_base_dir.display().to_string(),
            "req_id": req_id,
            "runtime_execution_plan": plan,
            "runtime_adapter_candidate": {
                "candidate": false,
                "adapter_kind": adapter_kind,
                "selected_route_kind": selected_route_kind,
                "selected_model_id": selected_model_id,
                "blockers": blockers,
                "writes_response": false,
                "executes_ml": false,
                "hub_status_written": false,
                "production_file_ipc_ready": false,
                "timeout_ms": 2000,
            },
            "surface_contract": surface_contract_json(),
            "authority": authority_json(false),
        });
    }

    let request_contract = plan.get("request").cloned().unwrap_or_else(|| json!({}));
    let task_type = request_contract
        .get("task_type")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    let canceled = cancel_path.is_file();
    let reason = if canceled {
        "rust_file_ipc_cancel_observed"
    } else {
        "rust_runtime_adapter_candidate_not_executing"
    };
    let lines = planned_adapter_candidate_response_lines(
        input,
        &req_id,
        &selected_model_id,
        &task_type,
        reason,
        &request_contract,
        &adapter_kind,
        &selected_route_kind,
    );
    let mut write_error = String::new();
    let wrote = match write_jsonl_atomic(&resp_path, &lines) {
        Ok(()) => true,
        Err(error) => {
            write_error = error;
            false
        }
    };
    let ok = wrote && write_error.is_empty();
    json!({
        "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
        "ok": ok,
        "ready": false,
        "wrote": wrote,
        "generated_at_ms": input.now_ms.min(i64::MAX as u128) as i64,
        "mode": "shadow_runtime_adapter_candidate_apply",
        "deny_code": if ok { "" } else { "runtime_adapter_candidate_write_failed" },
        "error_message": write_error,
        "root_dir": input.root_dir.display().to_string(),
        "base_dir": base_dir_display,
        "runtime_base_dir": input.runtime_base_dir.display().to_string(),
        "req_id": req_id,
        "response_path": resp_path.display().to_string(),
        "cancel_path": cancel_path.display().to_string(),
        "cancel_observed": canceled,
        "runtime_execution_plan": plan,
        "runtime_adapter_candidate": {
            "candidate": true,
            "adapter_kind": adapter_kind,
            "selected_route_kind": selected_route_kind,
            "selected_model_id": selected_model_id,
            "blockers": [],
            "writes_response": wrote,
            "executes_ml": false,
            "hub_status_written": false,
            "production_file_ipc_ready": false,
            "timeout_ms": 2000,
            "fail_closed_reason": reason,
        },
        "planned_events": lines,
        "surface_contract": surface_contract_json(),
        "authority": authority_json(wrote),
        "checks": [
            {"name": "shadow_enabled", "ok": input.shadow_enabled, "blocking": true},
            {"name": "shadow_apply_env_enabled", "ok": input.shadow_apply_env_enabled, "blocking": true},
            {"name": "runtime_plan_env", "ok": runtime_plan_env, "blocking": true},
            {"name": "runtime_adapter_candidate_env", "ok": adapter_candidate_env, "blocking": true},
            {"name": "dry_run_candidate", "ok": dry_run_candidate, "blocking": true},
            {"name": "response_written_fail_closed", "ok": wrote, "blocking": true},
            {"name": "production_file_ipc_ready_remains_false", "ok": true, "blocking": true},
            {"name": "no_ml_execution_in_rust", "ok": true, "blocking": false}
        ],
    })
}

fn run_background_watcher_thread(
    input: XtFileIpcShadowInput,
    base_dir: PathBuf,
    watcher_id: String,
    lock_path: PathBuf,
    stop_flag: Arc<AtomicBool>,
) {
    let status_path = base_dir.join(WATCHER_STATUS_FILENAME);
    let mut completed_cycles = 0usize;
    let mut wrote_count = 0usize;
    let mut last_result = json!(null);
    let mut last_error = String::new();

    for index in 0..input.max_cycles {
        if stop_flag.load(Ordering::SeqCst) {
            break;
        }
        if index > 0 && input.cycle_interval_ms > 0 {
            thread::sleep(Duration::from_millis(input.cycle_interval_ms));
        }
        let mut cycle_input = input.clone();
        cycle_input.now_ms = now_ms();
        cycle_input.req_id = None;
        let cycle = cycle_once_value(&cycle_input);
        let wrote = cycle.get("wrote").and_then(Value::as_bool).unwrap_or(false);
        if wrote {
            wrote_count += 1;
        }
        completed_cycles += 1;
        last_result = cycle.clone();
        let running_status = background_watcher_status_json(
            &cycle_input,
            &base_dir,
            &watcher_id,
            "running",
            completed_cycles,
            wrote_count,
            cycle,
        );
        if let Err(error) = write_json_atomic(&status_path, &running_status) {
            last_error = error;
            break;
        }
        if let Ok(mut runtime) = background_watcher_runtime().lock() {
            runtime.completed_cycles = completed_cycles;
            runtime.wrote_count = wrote_count;
            runtime.last_error = last_error.clone();
        }
    }

    let mut stop_input = input.clone();
    stop_input.now_ms = now_ms();
    let stopped_status = background_watcher_status_json(
        &stop_input,
        &base_dir,
        &watcher_id,
        "stopped",
        completed_cycles,
        wrote_count,
        last_result,
    );
    if last_error.is_empty() {
        if let Err(error) = write_json_atomic(&status_path, &stopped_status) {
            last_error = error;
        }
    }
    if let Err(error) = fs::remove_file(&lock_path) {
        if last_error.is_empty() {
            last_error = format!("release_watcher_lock:{error}");
        }
    }
    if let Ok(mut runtime) = background_watcher_runtime().lock() {
        runtime.active = false;
        runtime.finished_at_ms = now_ms().min(i64::MAX as u128) as i64;
        runtime.completed_cycles = completed_cycles;
        runtime.wrote_count = wrote_count;
        runtime.stop_requested = stop_flag.load(Ordering::SeqCst);
        runtime.last_error = last_error;
        runtime.stop_flag = None;
    }
}

fn supervise_bounded_value(input: &XtFileIpcShadowInput) -> Value {
    let Some(base_dir) = input.base_dir.clone() else {
        return denied(input, "", "", "base_dir_required", "");
    };
    let base_dir_display = base_dir.display().to_string();
    if !input.shadow_enabled {
        return denied(
            input,
            &base_dir_display,
            "",
            "xt_file_ipc_shadow_not_enabled",
            "",
        );
    }
    if !shadow_safe_base_dir(&base_dir) {
        return denied(
            input,
            &base_dir_display,
            "",
            "base_dir_outside_shadow_sandbox",
            "",
        );
    }
    if !base_dir.is_dir() {
        return denied(input, &base_dir_display, "", "base_dir_missing", "");
    }
    if input.requested_apply && !input.shadow_apply_env_enabled {
        return denied(
            input,
            &base_dir_display,
            "",
            "xt_file_ipc_shadow_apply_not_enabled",
            "",
        );
    }

    let mut cycle_results = Vec::new();
    let mut failed_count = 0usize;
    let mut status_wrote_count = 0usize;
    let mut response_wrote_count = 0usize;
    let mut total_attempted_count = 0usize;
    let mut total_skipped_existing_response_count = 0usize;
    let supervisor_started_ms = now_ms();

    for index in 0..input.max_cycles {
        if index > 0 && input.cycle_interval_ms > 0 {
            thread::sleep(Duration::from_millis(input.cycle_interval_ms));
        }
        let mut cycle_input = input.clone();
        cycle_input.now_ms = now_ms();
        cycle_input.req_id = None;
        let cycle = cycle_once_value(&cycle_input);
        let ok = cycle.get("ok").and_then(Value::as_bool).unwrap_or(false);
        let status_wrote = cycle
            .get("cycle")
            .and_then(|value| value.get("status_wrote"))
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let drain_wrote = cycle
            .get("cycle")
            .and_then(|value| value.get("drain_wrote"))
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let attempted_count = cycle
            .get("drain_result")
            .and_then(|value| value.get("drain"))
            .and_then(|value| value.get("attempted_count"))
            .and_then(Value::as_u64)
            .unwrap_or(0) as usize;
        let skipped_existing_response_count = cycle
            .get("drain_result")
            .and_then(|value| value.get("drain"))
            .and_then(|value| value.get("skipped_existing_response_count"))
            .and_then(Value::as_u64)
            .unwrap_or(0) as usize;
        if !ok {
            failed_count += 1;
        }
        if status_wrote {
            status_wrote_count += 1;
        }
        if drain_wrote {
            response_wrote_count += 1;
        }
        total_attempted_count += attempted_count;
        total_skipped_existing_response_count += skipped_existing_response_count;
        cycle_results.push(json!({
            "index": index,
            "ok": ok,
            "wrote": cycle.get("wrote").and_then(Value::as_bool).unwrap_or(false),
            "deny_code": cycle.get("deny_code").and_then(Value::as_str).unwrap_or(""),
            "cycle_id": cycle.get("cycle").and_then(|value| value.get("cycle_id")).and_then(Value::as_str).unwrap_or(""),
            "status_wrote": status_wrote,
            "drain_wrote": drain_wrote,
            "attempted_count": attempted_count,
            "skipped_existing_response_count": skipped_existing_response_count,
        }));
    }

    let ok = failed_count == 0;
    json!({
        "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
        "ok": ok,
        "ready": false,
        "wrote": status_wrote_count > 0 || response_wrote_count > 0,
        "generated_at_ms": now_ms().min(i64::MAX as u128) as i64,
        "mode": if input.requested_apply { "shadow_supervise_apply" } else { "shadow_supervise_dry_run" },
        "deny_code": if ok { "" } else { "supervisor_cycle_failed" },
        "root_dir": input.root_dir.display().to_string(),
        "base_dir": base_dir_display,
        "supervisor": {
            "started_at_ms": supervisor_started_ms.min(i64::MAX as u128) as i64,
            "finished_at_ms": now_ms().min(i64::MAX as u128) as i64,
            "max_cycles": input.max_cycles,
            "cycle_interval_ms": input.cycle_interval_ms,
            "cycle_count": cycle_results.len(),
            "failed_count": failed_count,
            "status_wrote_count": status_wrote_count,
            "response_wrote_count": response_wrote_count,
            "total_attempted_count": total_attempted_count,
            "total_skipped_existing_response_count": total_skipped_existing_response_count,
            "background_watcher_started": false,
            "stopped": true,
            "production_file_ipc_ready": false,
        },
        "cycles": cycle_results,
        "surface_contract": surface_contract_json(),
        "authority": authority_json_with_status(response_wrote_count > 0, status_wrote_count > 0),
        "checks": [
            {"name": "shadow_enabled", "ok": input.shadow_enabled, "blocking": true},
            {"name": "shadow_apply_env_enabled", "ok": input.shadow_apply_env_enabled, "blocking": input.requested_apply},
            {"name": "base_dir_explicit", "ok": true, "blocking": true},
            {"name": "base_dir_temp_safe", "ok": true, "blocking": true},
            {"name": "bounded_cycles", "ok": input.max_cycles <= 10, "blocking": true},
            {"name": "background_watcher_not_started", "ok": true, "blocking": true},
            {"name": "processor_status_not_hub_status", "ok": true, "blocking": true},
            {"name": "production_authority_unchanged", "ok": true, "blocking": false},
            {"name": "no_ml_execution_in_rust", "ok": true, "blocking": false}
        ],
    })
}

fn cycle_once_value(input: &XtFileIpcShadowInput) -> Value {
    let Some(base_dir) = input.base_dir.clone() else {
        return denied(input, "", "", "base_dir_required", "");
    };
    let base_dir_display = base_dir.display().to_string();
    if !input.shadow_enabled {
        return denied(
            input,
            &base_dir_display,
            "",
            "xt_file_ipc_shadow_not_enabled",
            "",
        );
    }
    if !shadow_safe_base_dir(&base_dir) {
        return denied(
            input,
            &base_dir_display,
            "",
            "base_dir_outside_shadow_sandbox",
            "",
        );
    }
    if !base_dir.is_dir() {
        return denied(input, &base_dir_display, "", "base_dir_missing", "");
    }
    if input.requested_apply && !input.shadow_apply_env_enabled {
        return denied(
            input,
            &base_dir_display,
            "",
            "xt_file_ipc_shadow_apply_not_enabled",
            "",
        );
    }

    let drain = if base_dir.join("ai_requests").is_dir() {
        drain_once_value(input)
    } else {
        empty_drain_value(input, &base_dir)
    };
    let drain_ok = drain.get("ok").and_then(Value::as_bool).unwrap_or(false);
    let drain_wrote = drain.get("wrote").and_then(Value::as_bool).unwrap_or(false);
    let cycle_id = format!("cycle-{}-{}", process::id(), input.now_ms);
    let status_path = base_dir.join(PROCESSOR_STATUS_FILENAME);
    let planned_status = processor_status_json(
        input,
        &base_dir,
        &cycle_id,
        drain_ok,
        drain_wrote,
        drain.get("drain").cloned().unwrap_or_else(|| json!({})),
    );

    let mut write_error = String::new();
    let status_wrote = if input.requested_apply {
        match write_json_atomic(&status_path, &planned_status) {
            Ok(()) => true,
            Err(error) => {
                write_error = error;
                false
            }
        }
    } else {
        false
    };
    let ok = drain_ok && (!input.requested_apply || status_wrote);
    let deny_code = if ok {
        ""
    } else if !write_error.is_empty() {
        "processor_status_write_failed"
    } else if !drain_ok {
        "cycle_drain_failed"
    } else {
        "unknown"
    };

    json!({
        "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
        "ok": ok,
        "ready": false,
        "wrote": drain_wrote || status_wrote,
        "generated_at_ms": input.now_ms.min(i64::MAX as u128) as i64,
        "mode": if input.requested_apply { "shadow_cycle_apply" } else { "shadow_cycle_dry_run" },
        "deny_code": deny_code,
        "error_message": write_error,
        "root_dir": input.root_dir.display().to_string(),
        "base_dir": base_dir_display,
        "cycle": {
            "cycle_id": cycle_id,
            "status_path": status_path.display().to_string(),
            "status_wrote": status_wrote,
            "drain_ok": drain_ok,
            "drain_wrote": drain_wrote,
            "watcher_active": false,
            "heartbeat_active": input.requested_apply && status_wrote,
            "production_file_ipc_ready": false,
        },
        "planned_processor_status": planned_status,
        "drain_result": drain,
        "surface_contract": surface_contract_json(),
        "authority": authority_json_with_status(drain_wrote, status_wrote),
        "checks": [
            {"name": "shadow_enabled", "ok": input.shadow_enabled, "blocking": true},
            {"name": "shadow_apply_env_enabled", "ok": input.shadow_apply_env_enabled, "blocking": input.requested_apply},
            {"name": "base_dir_explicit", "ok": true, "blocking": true},
            {"name": "base_dir_temp_safe", "ok": true, "blocking": true},
            {"name": "processor_status_not_hub_status", "ok": true, "blocking": true},
            {"name": "production_authority_unchanged", "ok": true, "blocking": false},
            {"name": "no_ml_execution_in_rust", "ok": true, "blocking": false},
            {"name": "watcher_not_active", "ok": true, "blocking": false}
        ],
    })
}

fn empty_drain_value(input: &XtFileIpcShadowInput, base_dir: &Path) -> Value {
    json!({
        "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
        "ok": true,
        "ready": false,
        "wrote": false,
        "generated_at_ms": input.now_ms.min(i64::MAX as u128) as i64,
        "mode": if input.requested_apply { "shadow_drain_apply" } else { "shadow_drain_dry_run" },
        "deny_code": "",
        "root_dir": input.root_dir.display().to_string(),
        "base_dir": base_dir.display().to_string(),
        "drain": {
            "max_requests": input.max_requests,
            "pending_request_count": 0,
            "attempted_count": 0,
            "wrote_count": 0,
            "denied_count": 0,
            "remaining_unattempted_count": 0,
            "cancel_observed_count": 0,
            "skipped_existing_response_count": 0,
            "request_dir_exists": false,
        },
        "results": [],
        "surface_contract": surface_contract_json(),
        "authority": authority_json(false),
    })
}

fn drain_once_value(input: &XtFileIpcShadowInput) -> Value {
    let Some(base_dir) = input.base_dir.clone() else {
        return denied(input, "", "", "base_dir_required", "");
    };
    let base_dir_display = base_dir.display().to_string();
    if !input.shadow_enabled {
        return denied(
            input,
            &base_dir_display,
            "",
            "xt_file_ipc_shadow_not_enabled",
            "",
        );
    }
    if !shadow_safe_base_dir(&base_dir) {
        return denied(
            input,
            &base_dir_display,
            "",
            "base_dir_outside_shadow_sandbox",
            "",
        );
    }
    if !base_dir.is_dir() {
        return denied(input, &base_dir_display, "", "base_dir_missing", "");
    }
    if input.requested_apply && !input.shadow_apply_env_enabled {
        return denied(
            input,
            &base_dir_display,
            "",
            "xt_file_ipc_shadow_apply_not_enabled",
            "",
        );
    }

    let req_dir = base_dir.join("ai_requests");
    let request_ids = match pending_request_ids(&req_dir) {
        Ok(value) => value,
        Err(code) => return denied(input, &base_dir_display, "", code.as_str(), ""),
    };
    let pending_request_count = request_ids.len();
    let mut skipped_existing_response_count = 0usize;
    let selected_ids = request_ids
        .into_iter()
        .filter(|req_id| {
            let should_attempt =
                input.overwrite_response || !response_path(&base_dir, req_id).exists();
            if !should_attempt {
                skipped_existing_response_count += 1;
            }
            should_attempt
        })
        .take(input.max_requests)
        .collect::<Vec<_>>();
    let mut results = Vec::new();
    let mut wrote_count = 0usize;
    let mut denied_count = 0usize;
    let mut cancel_observed_count = 0usize;

    for req_id in selected_ids {
        let mut item_input = input.clone();
        item_input.req_id = Some(req_id.clone());
        let value = respond_once_value(&item_input);
        let ok = value.get("ok").and_then(Value::as_bool).unwrap_or(false);
        let wrote = value.get("wrote").and_then(Value::as_bool).unwrap_or(false);
        let cancel_observed = value
            .get("cancel_observed")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        if wrote {
            wrote_count += 1;
        }
        if !ok {
            denied_count += 1;
        }
        if cancel_observed {
            cancel_observed_count += 1;
        }
        results.push(json!({
            "req_id": req_id,
            "ok": ok,
            "wrote": wrote,
            "deny_code": value.get("deny_code").and_then(Value::as_str).unwrap_or(""),
            "response_path": value.get("response_path").and_then(Value::as_str).unwrap_or(""),
            "cancel_observed": cancel_observed,
        }));
    }

    let attempted_count = results.len();
    let ok = denied_count == 0;
    json!({
        "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
        "ok": ok,
        "ready": false,
        "wrote": wrote_count > 0,
        "generated_at_ms": input.now_ms.min(i64::MAX as u128) as i64,
        "mode": if input.requested_apply { "shadow_drain_apply" } else { "shadow_drain_dry_run" },
        "deny_code": if ok { "" } else { "drain_item_failed" },
        "root_dir": input.root_dir.display().to_string(),
        "base_dir": base_dir_display,
        "drain": {
            "max_requests": input.max_requests,
            "pending_request_count": pending_request_count,
            "attempted_count": attempted_count,
            "wrote_count": wrote_count,
            "denied_count": denied_count,
            "remaining_unattempted_count": pending_request_count.saturating_sub(attempted_count),
            "cancel_observed_count": cancel_observed_count,
            "skipped_existing_response_count": skipped_existing_response_count,
        },
        "results": results,
        "surface_contract": surface_contract_json(),
        "authority": authority_json(wrote_count > 0),
        "checks": [
            {"name": "shadow_enabled", "ok": input.shadow_enabled, "blocking": true},
            {"name": "shadow_apply_env_enabled", "ok": input.shadow_apply_env_enabled, "blocking": input.requested_apply},
            {"name": "base_dir_explicit", "ok": true, "blocking": true},
            {"name": "base_dir_temp_safe", "ok": true, "blocking": true},
            {"name": "production_authority_unchanged", "ok": true, "blocking": false},
            {"name": "no_ml_execution_in_rust", "ok": true, "blocking": false},
            {"name": "watcher_not_active", "ok": true, "blocking": false}
        ],
    })
}

fn respond_once_value(input: &XtFileIpcShadowInput) -> Value {
    let Some(base_dir) = input.base_dir.clone() else {
        return denied(input, "", "", "base_dir_required", "");
    };
    let base_dir_display = base_dir.display().to_string();
    if !input.shadow_enabled {
        return denied(
            input,
            &base_dir_display,
            "",
            "xt_file_ipc_shadow_not_enabled",
            "",
        );
    }
    if !shadow_safe_base_dir(&base_dir) {
        return denied(
            input,
            &base_dir_display,
            "",
            "base_dir_outside_shadow_sandbox",
            "",
        );
    }
    if !base_dir.is_dir() {
        return denied(input, &base_dir_display, "", "base_dir_missing", "");
    }

    let req_id = match input
        .req_id
        .clone()
        .filter(|value| !value.trim().is_empty())
    {
        Some(value) => value,
        None => match discover_single_request_id(&base_dir.join("ai_requests")) {
            Ok(value) => value,
            Err(code) => return denied(input, &base_dir_display, "", code.as_str(), ""),
        },
    };
    if !safe_request_id(&req_id) {
        return denied(input, &base_dir_display, &req_id, "unsafe_request_id", "");
    }

    let req_path = request_path(&base_dir, &req_id);
    let resp_path = response_path(&base_dir, &req_id);
    let cancel_path = cancel_path(&base_dir, &req_id);
    let request = match read_json(&req_path) {
        Ok(value) => value,
        Err(error) => {
            if let Some(bytes) = error.strip_prefix("request_file_too_large:") {
                return denied(
                    input,
                    &base_dir_display,
                    &req_id,
                    "request_file_too_large",
                    bytes,
                );
            }
            if let Some(message) = error.strip_prefix("request_json_invalid:") {
                return denied(
                    input,
                    &base_dir_display,
                    &req_id,
                    "request_json_invalid",
                    message,
                );
            }
            return denied(
                input,
                &base_dir_display,
                &req_id,
                "request_read_failed",
                error.as_str(),
            );
        }
    };
    let request_type = value_string(&request, "type").unwrap_or_else(|| "generate".to_string());
    if request_type != "generate" {
        return denied(
            input,
            &base_dir_display,
            &req_id,
            "unsupported_request_type",
            request_type.as_str(),
        );
    }
    if let Some(prompt_chars) = oversized_prompt_chars(&request) {
        return denied(
            input,
            &base_dir_display,
            &req_id,
            "request_prompt_too_large",
            prompt_chars.to_string().as_str(),
        );
    }
    if resp_path.exists() {
        if !input.overwrite_response {
            return denied(
                input,
                &base_dir_display,
                &req_id,
                "response_already_exists",
                "",
            );
        }
        if !overwrite_response_env_enabled() {
            return denied(
                input,
                &base_dir_display,
                &req_id,
                "response_overwrite_not_enabled",
                "",
            );
        }
    }
    if input.requested_apply && !input.shadow_apply_env_enabled {
        return denied(
            input,
            &base_dir_display,
            &req_id,
            "xt_file_ipc_shadow_apply_not_enabled",
            "",
        );
    }

    let canceled = cancel_path.is_file();
    let model_id = effective_request_model_id(&request);
    let task_type = value_string(&request, "task_type").unwrap_or_default();
    let reason = if canceled {
        "rust_file_ipc_cancel_observed"
    } else {
        FAIL_CLOSED_REASON
    };
    let request_contract = request_contract_json(&request, &model_id, &task_type);
    let lines = planned_response_lines(
        input,
        &req_id,
        &model_id,
        &task_type,
        reason,
        &request_contract,
    );

    let mut write_error = String::new();
    let wrote = if input.requested_apply {
        match write_jsonl_atomic(&resp_path, &lines) {
            Ok(()) => true,
            Err(error) => {
                write_error = error;
                false
            }
        }
    } else {
        false
    };
    let ok = if input.requested_apply {
        wrote && write_error.is_empty()
    } else {
        true
    };
    let deny_code = if ok {
        ""
    } else if !write_error.is_empty() {
        "response_write_failed"
    } else {
        "unknown"
    };

    json!({
        "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
        "ok": ok,
        "ready": false,
        "wrote": wrote,
        "generated_at_ms": input.now_ms.min(i64::MAX as u128) as i64,
        "mode": if input.requested_apply { "shadow_apply" } else { "dry_run" },
        "deny_code": deny_code,
        "error_message": write_error,
        "root_dir": input.root_dir.display().to_string(),
        "base_dir": base_dir_display,
        "req_id": req_id,
        "request_path": req_path.display().to_string(),
        "response_path": resp_path.display().to_string(),
        "cancel_path": cancel_path.display().to_string(),
        "cancel_observed": canceled,
        "request": request_contract,
        "planned_events": lines,
        "surface_contract": surface_contract_json(),
        "authority": authority_json(wrote),
        "checks": [
            {"name": "shadow_enabled", "ok": input.shadow_enabled, "blocking": true},
            {"name": "shadow_apply_env_enabled", "ok": input.shadow_apply_env_enabled, "blocking": input.requested_apply},
            {"name": "base_dir_explicit", "ok": true, "blocking": true},
            {"name": "base_dir_temp_safe", "ok": true, "blocking": true},
            {"name": "request_file_exists", "ok": true, "blocking": true},
            {"name": "response_not_preexisting_or_overwrite_enabled", "ok": true, "blocking": true},
            {"name": "production_authority_unchanged", "ok": true, "blocking": false},
            {"name": "no_ml_execution_in_rust", "ok": true, "blocking": false}
        ]
    })
}

fn denied(
    input: &XtFileIpcShadowInput,
    base_dir: &str,
    req_id: &str,
    deny_code: &str,
    error_message: &str,
) -> Value {
    json!({
        "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_V1,
        "ok": false,
        "ready": false,
        "wrote": false,
        "generated_at_ms": input.now_ms.min(i64::MAX as u128) as i64,
        "mode": "shadow_fail_closed",
        "deny_code": deny_code,
        "error_message": error_message,
        "root_dir": input.root_dir.display().to_string(),
        "base_dir": base_dir,
        "req_id": req_id,
        "surface_contract": surface_contract_json(),
        "authority": authority_json(false),
    })
}

fn planned_response_lines(
    input: &XtFileIpcShadowInput,
    req_id: &str,
    model_id: &str,
    task_type: &str,
    reason: &str,
    request_contract: &Value,
) -> Vec<Value> {
    let started_at = (input.now_ms as f64) / 1000.0;
    let preferred_model_id = request_contract
        .get("preferred_model_id")
        .and_then(Value::as_str)
        .unwrap_or("");
    let requested_model_id = request_contract
        .get("requested_model_id")
        .and_then(Value::as_str)
        .unwrap_or(model_id);
    let app_id = request_contract
        .get("app_id")
        .and_then(Value::as_str)
        .unwrap_or("");
    vec![
        json!({
            "type": "start",
            "req_id": req_id,
            "model_id": model_id,
            "task_type": task_type,
            "requested_model_id": requested_model_id,
            "preferred_model_id": preferred_model_id,
            "actual_model_id": model_id,
            "app_id": app_id,
            "started_at": started_at,
            "runtime_provider": "Rust Hub Shadow",
            "execution_path": "rust_file_ipc_shadow",
            "authority": "shadow_only",
            "fail_closed": true,
        }),
        json!({
            "type": "done",
            "req_id": req_id,
            "ok": false,
            "reason": reason,
            "model_id": model_id,
            "task_type": task_type,
            "requested_model_id": requested_model_id,
            "preferred_model_id": preferred_model_id,
            "actual_model_id": model_id,
            "app_id": app_id,
            "promptTokens": 0,
            "generationTokens": 0,
            "deny_code": reason,
            "runtime_provider": "Rust Hub Shadow",
            "execution_path": "rust_file_ipc_shadow",
            "authority": "shadow_only",
            "fail_closed": true,
        }),
    ]
}

fn planned_adapter_candidate_response_lines(
    input: &XtFileIpcShadowInput,
    req_id: &str,
    model_id: &str,
    task_type: &str,
    reason: &str,
    request_contract: &Value,
    adapter_kind: &str,
    selected_route_kind: &str,
) -> Vec<Value> {
    let mut lines =
        planned_response_lines(input, req_id, model_id, task_type, reason, request_contract);
    for line in &mut lines {
        if let Some(object) = line.as_object_mut() {
            object.insert(
                "runtime_provider".to_string(),
                json!("Rust Hub Runtime Adapter Candidate"),
            );
            object.insert(
                "execution_path".to_string(),
                json!("rust_runtime_adapter_candidate"),
            );
            object.insert("adapter_kind".to_string(), json!(adapter_kind));
            object.insert(
                "selected_route_kind".to_string(),
                json!(selected_route_kind),
            );
            object.insert("runtime_adapter_candidate".to_string(), json!(true));
            object.insert("timeout_ms".to_string(), json!(2000));
        }
    }
    lines
}

fn effective_request_model_id(request: &Value) -> String {
    value_string(request, "model_id")
        .or_else(|| value_string(request, "preferred_model_id"))
        .unwrap_or_default()
}

fn request_contract_json(request: &Value, model_id: &str, task_type: &str) -> Value {
    let explicit_model_id = value_string(request, "model_id").unwrap_or_default();
    let preferred_model_id = value_string(request, "preferred_model_id").unwrap_or_default();
    let model_id_source = if !explicit_model_id.is_empty() {
        "model_id"
    } else if !preferred_model_id.is_empty() {
        "preferred_model_id"
    } else {
        "none"
    };
    let provider_key = request.get("provider_key").unwrap_or(&Value::Null);
    let provider_key_object = provider_key.as_object();
    let custom_header_count = provider_key_object
        .and_then(|_| provider_key.get("custom_headers"))
        .and_then(Value::as_object)
        .map(|headers| headers.len())
        .unwrap_or(0);

    json!({
        "type": value_string(request, "type").unwrap_or_else(|| "generate".to_string()),
        "req_id": value_string(request, "req_id").unwrap_or_default(),
        "app_id": value_string(request, "app_id").unwrap_or_default(),
        "task_type": task_type,
        "model_id": explicit_model_id,
        "preferred_model_id": preferred_model_id,
        "requested_model_id": model_id,
        "actual_model_id": model_id,
        "model_id_source": model_id_source,
        "prompt_chars": value_string(request, "prompt").unwrap_or_default().chars().count(),
        "max_tokens": value_i64(request, "max_tokens").unwrap_or(0),
        "temperature": value_f64(request, "temperature").unwrap_or(0.0),
        "top_p": value_f64(request, "top_p").unwrap_or(0.0),
        "created_at": value_f64(request, "created_at").unwrap_or(0.0),
        "auto_load": value_bool(request, "auto_load").unwrap_or(false),
        "provider_key": {
            "present": provider_key_object.is_some(),
            "provider": provider_key.get("provider").and_then(Value::as_str).unwrap_or(""),
            "auth_type": provider_key.get("auth_type").and_then(Value::as_str).unwrap_or(""),
            "base_url_present": provider_key.get("base_url").and_then(Value::as_str).map(|value| !value.trim().is_empty()).unwrap_or(false),
            "proxy_url_present": provider_key.get("proxy_url").and_then(Value::as_str).map(|value| !value.trim().is_empty()).unwrap_or(false),
            "custom_header_count": custom_header_count,
            "api_key_redacted": provider_key.get("api_key").and_then(Value::as_str).map(|value| !value.trim().is_empty()).unwrap_or(false),
            "refresh_token_redacted": provider_key.get("refresh_token").and_then(Value::as_str).map(|value| !value.trim().is_empty()).unwrap_or(false),
        },
        "schema_compat": {
            "xt_request_schema": "HubAIRequest",
            "xt_response_event_schema": "HubAIResponseEvent",
            "response_format": "jsonl",
            "start_event_required": true,
            "done_event_required": true,
            "fail_closed": true,
            "ml_execution_in_rust": false,
        }
    })
}

fn surface_contract_json() -> Value {
    json!({
        "request_dir": "ai_requests",
        "response_dir": "ai_responses",
        "cancel_dir": "ai_cancels",
        "request_filename": "req_<req_id>.json",
        "response_filename": "resp_<req_id>.jsonl",
        "cancel_filename": "cancel_<req_id>.json",
        "processor_status_filename": PROCESSOR_STATUS_FILENAME,
        "watcher_status_filename": WATCHER_STATUS_FILENAME,
        "watcher_lock_filename": WATCHER_LOCK_FILENAME,
        "response_format": "jsonl",
        "implemented_mode": "respond_once_manual_drain_cycle_bounded_supervise_watcher_smoke_rollback_readiness_start_plan_run_once_session_and_background_shadow_fail_closed",
        "watcher_active": false,
        "processor_lifecycle": "manual_http_watcher_smoke_with_rollback",
        "heartbeat_active": false,
        "background_watcher_available": true,
        "ml_execution": false,
        "production_file_ipc_ready": false,
    })
}

fn background_contract_json(
    candidate: bool,
    active: bool,
    started: bool,
    max_cycles: usize,
    cycle_interval_ms: u64,
    blockers: Vec<String>,
) -> Value {
    json!({
        "background_candidate": candidate,
        "background_watcher_started": started,
        "active": active,
        "blockers": blockers,
        "max_cycles": max_cycles,
        "cycle_interval_ms": cycle_interval_ms,
        "long_running_thread_started": started,
        "bounded": true,
        "hub_status_written": false,
        "production_file_ipc_ready": false,
        "ml_execution_in_rust": false,
    })
}

fn background_runtime_json(runtime: &BackgroundWatcherRuntime) -> Value {
    json!({
        "active": runtime.active,
        "watcher_id": runtime.watcher_id,
        "base_dir": runtime.base_dir,
        "started_at_ms": runtime.started_at_ms,
        "finished_at_ms": runtime.finished_at_ms,
        "max_cycles": runtime.max_cycles,
        "cycle_interval_ms": runtime.cycle_interval_ms,
        "completed_cycles": runtime.completed_cycles,
        "wrote_count": runtime.wrote_count,
        "stop_requested": runtime.stop_requested,
        "last_error": runtime.last_error,
        "hub_status_written": false,
        "production_file_ipc_ready": false,
        "ml_execution_in_rust": false,
        "production_authority_change": false,
    })
}

fn authority_json(wrote: bool) -> Value {
    authority_json_with_status(wrote, false)
}

fn authority_json_with_status(response_wrote: bool, status_wrote: bool) -> Value {
    authority_json_full(response_wrote, status_wrote, false)
}

fn authority_json_with_watcher(response_wrote: bool, watcher_status_wrote: bool) -> Value {
    authority_json_full(response_wrote, false, watcher_status_wrote)
}

fn authority_json_full(
    response_wrote: bool,
    processor_status_wrote: bool,
    watcher_status_wrote: bool,
) -> Value {
    json!({
        "production_authority_change": false,
        "node_remains_authority": true,
        "rust_writes_classic_hub_status": false,
        "rust_writes_xt_response_file": response_wrote,
        "rust_writes_shadow_processor_status": processor_status_wrote,
        "rust_writes_shadow_watcher_status": watcher_status_wrote,
        "rust_executes_ml": false,
        "rust_executes_third_party_skills": false,
        "memory_writer_authority_in_rust": false,
    })
}

fn request_path(base_dir: &Path, req_id: &str) -> PathBuf {
    base_dir
        .join("ai_requests")
        .join(format!("req_{req_id}.json"))
}

fn response_path(base_dir: &Path, req_id: &str) -> PathBuf {
    base_dir
        .join("ai_responses")
        .join(format!("resp_{req_id}.jsonl"))
}

fn cancel_path(base_dir: &Path, req_id: &str) -> PathBuf {
    base_dir
        .join("ai_cancels")
        .join(format!("cancel_{req_id}.json"))
}

fn discover_single_request_id(req_dir: &Path) -> Result<String, String> {
    let mut request_ids = pending_request_ids(req_dir)?;
    match request_ids.len() {
        0 => Err("request_file_missing".to_string()),
        1 => Ok(request_ids.remove(0)),
        _ => Err("request_id_ambiguous".to_string()),
    }
}

fn pending_request_ids(req_dir: &Path) -> Result<Vec<String>, String> {
    let entries = fs::read_dir(req_dir).map_err(|_| "request_dir_missing".to_string())?;
    let mut request_ids = Vec::new();
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        if let Some(req_id) = name
            .strip_prefix("req_")
            .and_then(|value| value.strip_suffix(".json"))
        {
            if safe_request_id(req_id) {
                request_ids.push(req_id.to_string());
            }
        }
    }
    request_ids.sort();
    request_ids.dedup();
    Ok(request_ids)
}

fn safe_request_id(value: &str) -> bool {
    let trimmed = value.trim();
    !trimmed.is_empty()
        && trimmed.len() <= 200
        && !trimmed.starts_with('.')
        && !trimmed.contains('/')
        && !trimmed.contains('\\')
        && !trimmed.contains('\0')
}

fn shadow_safe_base_dir(path: &Path) -> bool {
    let Ok(canonical) = path.canonicalize() else {
        return false;
    };
    let temp_ok = env::temp_dir()
        .canonicalize()
        .map(|temp| canonical.starts_with(temp))
        .unwrap_or(false);
    if temp_ok {
        return true;
    }
    canonical.starts_with(Path::new("/private/tmp")) || canonical.starts_with(Path::new("/tmp"))
}

fn read_json(path: &Path) -> Result<Value, String> {
    if let Ok(metadata) = fs::metadata(path) {
        if metadata.len() > MAX_REQUEST_FILE_BYTES {
            return Err(format!("request_file_too_large:{}", metadata.len()));
        }
    }
    let data = fs::read_to_string(path).map_err(|err| err.to_string())?;
    serde_json::from_str(&data).map_err(|err| format!("request_json_invalid:{err}"))
}

fn oversized_prompt_chars(request: &Value) -> Option<usize> {
    let chars = value_string(request, "prompt")
        .map(|value| value.chars().count())
        .unwrap_or(0);
    if chars > MAX_REQUEST_PROMPT_CHARS {
        Some(chars)
    } else {
        None
    }
}

fn write_jsonl_atomic(path: &Path, lines: &[Value]) -> Result<(), String> {
    let parent = path
        .parent()
        .ok_or_else(|| "response_parent_missing".to_string())?;
    fs::create_dir_all(parent).map_err(|err| format!("create_response_dir:{err}"))?;
    let tmp_path = parent.join(format!(
        ".{}.tmp.{}.{}",
        path.file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("response.jsonl"),
        process::id(),
        now_ms()
    ));
    let mut out = String::new();
    for line in lines {
        let line = serde_json::to_string(line).map_err(|err| err.to_string())?;
        out.push_str(&line);
        out.push('\n');
    }
    fs::write(&tmp_path, out).map_err(|err| format!("write_temp_response:{err}"))?;
    fs::rename(&tmp_path, path).map_err(|err| {
        let _ = fs::remove_file(&tmp_path);
        format!("rename_response:{err}")
    })
}

fn processor_status_json(
    input: &XtFileIpcShadowInput,
    base_dir: &Path,
    cycle_id: &str,
    drain_ok: bool,
    drain_wrote: bool,
    drain_summary: Value,
) -> Value {
    json!({
        "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_PROCESSOR_STATUS_V1,
        "ok": drain_ok,
        "ready": false,
        "cycle_id": cycle_id,
        "pid": process::id(),
        "generated_at_ms": input.now_ms.min(i64::MAX as u128) as i64,
        "updated_at_ms": input.now_ms.min(i64::MAX as u128) as i64,
        "base_dir": base_dir.display().to_string(),
        "mode": "manual_http_cycle_once",
        "watcher_active": false,
        "heartbeat_active": true,
        "production_file_ipc_ready": false,
        "hub_status_written": false,
        "ml_execution": false,
        "drain_ok": drain_ok,
        "drain_wrote": drain_wrote,
        "drain": drain_summary,
        "authority": authority_json(drain_wrote),
    })
}

fn write_json_atomic(path: &Path, value: &Value) -> Result<(), String> {
    let parent = path
        .parent()
        .ok_or_else(|| "json_parent_missing".to_string())?;
    fs::create_dir_all(parent).map_err(|err| format!("create_json_dir:{err}"))?;
    let tmp_path = parent.join(format!(
        ".{}.tmp.{}.{}",
        path.file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("status.json"),
        process::id(),
        now_ms()
    ));
    let data = serde_json::to_string_pretty(value).map_err(|err| err.to_string())?;
    fs::write(&tmp_path, format!("{data}\n")).map_err(|err| format!("write_temp_json:{err}"))?;
    fs::rename(&tmp_path, path).map_err(|err| {
        let _ = fs::remove_file(&tmp_path);
        format!("rename_json:{err}")
    })
}

fn watcher_status_json(
    input: &XtFileIpcShadowInput,
    base_dir: &Path,
    watcher_id: &str,
    state: &str,
    supervise_ok: bool,
    supervise_result: Option<Value>,
) -> Value {
    json!({
        "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_WATCHER_STATUS_V1,
        "ok": supervise_ok || state == "starting",
        "ready": false,
        "watcher_id": watcher_id,
        "pid": process::id(),
        "state": state,
        "generated_at_ms": input.now_ms.min(i64::MAX as u128) as i64,
        "updated_at_ms": now_ms().min(i64::MAX as u128) as i64,
        "base_dir": base_dir.display().to_string(),
        "mode": "manual_http_watcher_smoke",
        "background_watcher_started": false,
        "watcher_active": false,
        "stopped_before_return": state == "stopped",
        "production_file_ipc_ready": false,
        "hub_status_written": false,
        "ml_execution": false,
        "supervise_ok": supervise_ok,
        "supervise_result": supervise_result.unwrap_or_else(|| json!(null)),
        "authority": authority_json(false),
    })
}

fn background_watcher_status_json(
    input: &XtFileIpcShadowInput,
    base_dir: &Path,
    watcher_id: &str,
    state: &str,
    completed_cycles: usize,
    wrote_count: usize,
    last_result: Value,
) -> Value {
    json!({
        "schema_version": SCHEMA_XT_FILE_IPC_SHADOW_WATCHER_STATUS_V1,
        "ok": state == "running" || state == "stopped",
        "ready": false,
        "watcher_id": watcher_id,
        "pid": process::id(),
        "state": state,
        "generated_at_ms": input.now_ms.min(i64::MAX as u128) as i64,
        "updated_at_ms": now_ms().min(i64::MAX as u128) as i64,
        "base_dir": base_dir.display().to_string(),
        "mode": "background_shadow_watcher_bounded",
        "background_watcher_started": true,
        "watcher_active": state == "running",
        "stopped_before_return": false,
        "completed_cycles": completed_cycles,
        "wrote_count": wrote_count,
        "production_file_ipc_ready": false,
        "hub_status_written": false,
        "ml_execution": false,
        "last_result": last_result,
        "authority": authority_json(false),
    })
}

fn acquire_watcher_lock(lock_path: &Path, watcher_id: &str) -> Result<(), String> {
    let parent = lock_path
        .parent()
        .ok_or_else(|| "watcher_lock_parent_missing".to_string())?;
    fs::create_dir_all(parent).map_err(|err| format!("create_watcher_lock_dir:{err}"))?;
    match OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(lock_path)
    {
        Ok(mut file) => {
            use std::io::Write;
            file.write_all(format!("{watcher_id}\n").as_bytes())
                .map_err(|err| format!("write_watcher_lock:{err}"))
        }
        Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
            Err("watcher_lock_busy".to_string())
        }
        Err(error) => Err(format!("acquire_watcher_lock:{error}")),
    }
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

fn overwrite_response_env_enabled() -> bool {
    env_bool("XHUB_RUST_XT_FILE_IPC_OVERWRITE_RESPONSE", false)
}

fn env_path(key: &str) -> Option<PathBuf> {
    env::var(key)
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
}

fn value_string(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn value_bool(value: &Value, key: &str) -> Option<bool> {
    value.get(key).and_then(Value::as_bool)
}

fn value_i64(value: &Value, key: &str) -> Option<i64> {
    value.get(key).and_then(Value::as_i64)
}

fn value_f64(value: &Value, key: &str) -> Option<f64> {
    value.get(key).and_then(Value::as_f64)
}

fn value_usize(value: &Value, key: &str) -> Option<usize> {
    value
        .get(key)
        .and_then(Value::as_u64)
        .and_then(|value| usize::try_from(value).ok())
}

fn value_u64(value: &Value, key: &str) -> Option<u64> {
    value.get(key).and_then(Value::as_u64)
}

fn wants_drain(value: &Value) -> bool {
    value_bool(value, "drain").unwrap_or(false)
        || value_string(value, "operation")
            .map(|operation| operation == "drain")
            .unwrap_or(false)
}

fn wants_cycle(value: &Value) -> bool {
    value_bool(value, "cycle").unwrap_or(false)
        || value_string(value, "operation")
            .map(|operation| operation == "cycle")
            .unwrap_or(false)
}

fn wants_supervise(value: &Value) -> bool {
    value_bool(value, "supervise").unwrap_or(false)
        || value_string(value, "operation")
            .map(|operation| operation == "supervise")
            .unwrap_or(false)
}

fn wants_watcher_smoke(value: &Value) -> bool {
    value_bool(value, "watcher_smoke").unwrap_or(false)
        || value_bool(value, "watcherSmoke").unwrap_or(false)
        || value_string(value, "operation")
            .map(|operation| operation == "watcher-smoke" || operation == "watcher_smoke")
            .unwrap_or(false)
}

fn wants_watcher_rollback_smoke(value: &Value) -> bool {
    value_bool(value, "watcher_rollback_smoke").unwrap_or(false)
        || value_bool(value, "watcherRollbackSmoke").unwrap_or(false)
        || value_string(value, "operation")
            .map(|operation| {
                operation == "watcher-rollback-smoke" || operation == "watcher_rollback_smoke"
            })
            .unwrap_or(false)
}

fn wants_watcher_readiness(value: &Value) -> bool {
    value_bool(value, "watcher_readiness").unwrap_or(false)
        || value_bool(value, "watcherReadiness").unwrap_or(false)
        || value_string(value, "operation")
            .map(|operation| operation == "watcher-readiness" || operation == "watcher_readiness")
            .unwrap_or(false)
}

fn wants_watcher_start_plan(value: &Value) -> bool {
    value_bool(value, "watcher_start_plan").unwrap_or(false)
        || value_bool(value, "watcherStartPlan").unwrap_or(false)
        || value_string(value, "operation")
            .map(|operation| operation == "watcher-start-plan" || operation == "watcher_start_plan")
            .unwrap_or(false)
}

fn wants_watcher_run_once(value: &Value) -> bool {
    value_bool(value, "watcher_run_once").unwrap_or(false)
        || value_bool(value, "watcherRunOnce").unwrap_or(false)
        || value_string(value, "operation")
            .map(|operation| operation == "watcher-run-once" || operation == "watcher_run_once")
            .unwrap_or(false)
}

fn wants_watcher_session(value: &Value) -> bool {
    value_bool(value, "watcher_session").unwrap_or(false)
        || value_bool(value, "watcherSession").unwrap_or(false)
        || value_string(value, "operation")
            .map(|operation| operation == "watcher-session" || operation == "watcher_session")
            .unwrap_or(false)
}

fn wants_watcher_background_start(value: &Value) -> bool {
    value_bool(value, "watcher_background_start").unwrap_or(false)
        || value_bool(value, "watcherBackgroundStart").unwrap_or(false)
        || value_string(value, "operation")
            .map(|operation| {
                operation == "watcher-background-start"
                    || operation == "watcher_background_start"
                    || operation == "background-start"
            })
            .unwrap_or(false)
}

fn wants_watcher_background_stop(value: &Value) -> bool {
    value_bool(value, "watcher_background_stop").unwrap_or(false)
        || value_bool(value, "watcherBackgroundStop").unwrap_or(false)
        || value_string(value, "operation")
            .map(|operation| {
                operation == "watcher-background-stop"
                    || operation == "watcher_background_stop"
                    || operation == "background-stop"
            })
            .unwrap_or(false)
}

fn wants_watcher_background_status(value: &Value) -> bool {
    value_bool(value, "watcher_background_status").unwrap_or(false)
        || value_bool(value, "watcherBackgroundStatus").unwrap_or(false)
        || value_string(value, "operation")
            .map(|operation| {
                operation == "watcher-background-status"
                    || operation == "watcher_background_status"
                    || operation == "background-status"
            })
            .unwrap_or(false)
}

fn wants_runtime_execution_plan(value: &Value) -> bool {
    value_bool(value, "runtime_execution_plan").unwrap_or(false)
        || value_bool(value, "runtimeExecutionPlan").unwrap_or(false)
        || value_string(value, "operation")
            .map(|operation| {
                operation == "runtime-execution-plan"
                    || operation == "runtime_execution_plan"
                    || operation == "execution-plan"
            })
            .unwrap_or(false)
}

fn wants_runtime_adapter_candidate(value: &Value) -> bool {
    value_bool(value, "runtime_adapter_candidate").unwrap_or(false)
        || value_bool(value, "runtimeAdapterCandidate").unwrap_or(false)
        || value_string(value, "operation")
            .map(|operation| {
                operation == "runtime-adapter-candidate"
                    || operation == "runtime_adapter_candidate"
                    || operation == "adapter-candidate"
            })
            .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn live_status_projects_file_ipc_paths_without_writing_hub_status() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-live-status");
        fs::create_dir_all(temp.join("ipc_events")).unwrap();
        let status_path = temp.join("hub_status.json");
        fs::write(
            &status_path,
            r#"{"updatedAt":1,"baseDir":"/old","ipcPath":"/old/ipc_events","protocolVersion":1,"rustHub":{"authority":"explicit_cutover_only"}}"#,
        )
        .unwrap();
        let before = fs::read_to_string(&status_path).unwrap();
        let config = config_for_runtime_dir(temp.clone());

        let value = live_status_value_for_base(&config, 123_456, &temp, &status_path);

        assert_eq!(value["ok"], true);
        assert_eq!(value["ready"], true);
        assert_eq!(value["base_dir"], temp.display().to_string());
        assert_eq!(
            value["events_dir"],
            temp.join("ipc_events").display().to_string()
        );
        assert_eq!(
            value["responses_dir"],
            temp.join("ipc_responses").display().to_string()
        );
        assert_eq!(value["status_file_read_ok"], true);
        assert_eq!(value["status"]["baseDir"], temp.display().to_string());
        assert_eq!(
            value["status"]["ipcPath"],
            temp.join("ipc_events").display().to_string()
        );
        assert_eq!(
            value["status"]["rustHub"]["authority"],
            "rust_live_status_http"
        );
        assert_eq!(value["authority"]["rust_writes_classic_hub_status"], false);
        assert_eq!(fs::read_to_string(&status_path).unwrap(), before);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn live_status_http_get_only_and_fails_closed_without_base_dir() {
        let config = HubConfig {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            db_path: PathBuf::from("/tmp/rust-hub/hub.sqlite3"),
            runtime_base_dir: PathBuf::new(),
            proto_path: PathBuf::from("/tmp/hub_protocol_v1.proto"),
            canonical_proto_path: PathBuf::from("/tmp/canonical_hub_protocol_v1.proto"),
            host: "127.0.0.1".to_string(),
            http_port: 0,
            grpc_port: 0,
            http_access_key: None,
            http_access_key_source: String::new(),
            http_access_key_required: false,
        };

        let (method_status, method_body) = live_status_http_json(&config, "POST");
        assert_eq!(method_status, "405 Method Not Allowed");
        let method_value: Value = serde_json::from_str(method_body.trim()).unwrap();
        assert_eq!(method_value["ok"], false);
        assert_eq!(method_value["deny_code"], "method_not_allowed");

        let (status, body) = live_status_http_json(&config, "GET");
        assert_eq!(status, "409 Conflict");
        let value: Value = serde_json::from_str(body.trim()).unwrap();
        assert_eq!(value["ok"], false);
        assert_eq!(value["deny_code"], "live_base_dir_missing");
    }

    #[test]
    fn post_defaults_fail_closed_without_shadow_opt_in() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-default");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        fs::write(
            temp.join("ai_requests/req_r1.json"),
            r#"{"type":"generate","req_id":"r1","model_id":"mlx/test","task_type":"text_generate","prompt":"hello","max_tokens":8}"#,
        )
        .unwrap();
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: false,
            shadow_apply_env_enabled: false,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: Some("r1".to_string()),
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = respond_once_value(&input);

        assert_eq!(value["ok"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["deny_code"], "xt_file_ipc_shadow_not_enabled");
        assert_eq!(temp.join("ai_responses/resp_r1.jsonl").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn dry_run_reads_request_and_plans_fail_closed_response_without_writing() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-dry-run");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        fs::write(
            temp.join("ai_requests/req_r2.json"),
            r#"{"type":"generate","req_id":"r2","model_id":"mlx/test","task_type":"text_generate","prompt":"hello","max_tokens":8}"#,
        )
        .unwrap();
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: false,
            requested_apply: false,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: Some("r2".to_string()),
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = respond_once_value(&input);

        assert_eq!(value["ok"], true);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["mode"], "dry_run");
        assert_eq!(value["planned_events"][0]["type"], "start");
        assert_eq!(value["planned_events"][1]["type"], "done");
        assert_eq!(value["planned_events"][1]["ok"], false);
        assert_eq!(
            value["planned_events"][1]["reason"],
            "rust_file_ipc_not_authoritative"
        );
        assert_eq!(temp.join("ai_responses/resp_r2.jsonl").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn request_contract_preserves_xt_schema_without_leaking_provider_secret() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-schema");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        fs::write(
            temp.join("ai_requests/req_schema1.json"),
            r#"{"type":"generate","req_id":"schema1","app_id":"x-terminal","task_type":"summarize","preferred_model_id":"openai/gpt-4.1","prompt":"hello","max_tokens":42,"temperature":0.3,"top_p":0.9,"created_at":100.5,"auto_load":true,"provider_key":{"provider":"openai","api_key":"test-secret-value","refresh_token":"refresh-secret","base_url":"https://api.openai.com/v1","auth_type":"bearer","custom_headers":{"X-Test":"secret"}}}"#,
        )
        .unwrap();
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: false,
            requested_apply: false,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: Some("schema1".to_string()),
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = respond_once_value(&input);
        let serialized = serde_json::to_string(&value).unwrap();

        assert_eq!(value["ok"], true);
        assert_eq!(value["request"]["app_id"], "x-terminal");
        assert_eq!(value["request"]["task_type"], "summarize");
        assert_eq!(value["request"]["model_id"], "");
        assert_eq!(value["request"]["preferred_model_id"], "openai/gpt-4.1");
        assert_eq!(value["request"]["requested_model_id"], "openai/gpt-4.1");
        assert_eq!(value["request"]["actual_model_id"], "openai/gpt-4.1");
        assert_eq!(value["request"]["model_id_source"], "preferred_model_id");
        assert_eq!(value["request"]["max_tokens"], 42);
        assert_eq!(value["request"]["auto_load"], true);
        assert_eq!(value["request"]["provider_key"]["present"], true);
        assert_eq!(value["request"]["provider_key"]["provider"], "openai");
        assert_eq!(value["request"]["provider_key"]["api_key_redacted"], true);
        assert_eq!(
            value["request"]["provider_key"]["refresh_token_redacted"],
            true
        );
        assert_eq!(
            value["planned_events"][0]["requested_model_id"],
            "openai/gpt-4.1"
        );
        assert_eq!(
            value["planned_events"][0]["actual_model_id"],
            "openai/gpt-4.1"
        );
        assert_eq!(
            value["planned_events"][1]["deny_code"],
            "rust_file_ipc_not_authoritative"
        );
        assert!(!serialized.contains("test-secret-value"));
        assert!(!serialized.contains("refresh-secret"));
        assert!(!serialized.contains("X-Test"));

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn apply_writes_fail_closed_jsonl_only_when_shadow_apply_gate_passes() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-apply");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        fs::write(
            temp.join("ai_requests/req_r3.json"),
            r#"{"type":"generate","req_id":"r3","model_id":"mlx/test","task_type":"text_generate","prompt":"hello","max_tokens":8}"#,
        )
        .unwrap();
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: true,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: Some("r3".to_string()),
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = respond_once_value(&input);

        assert_eq!(value["ok"], true);
        assert_eq!(value["wrote"], true);
        assert_eq!(value["ready"], false);
        assert_eq!(value["authority"]["production_authority_change"], false);
        assert_eq!(value["authority"]["rust_executes_ml"], false);
        let response = fs::read_to_string(temp.join("ai_responses/resp_r3.jsonl")).unwrap();
        let lines = response.lines().collect::<Vec<_>>();
        assert_eq!(lines.len(), 2);
        let start: Value = serde_json::from_str(lines[0]).unwrap();
        let done: Value = serde_json::from_str(lines[1]).unwrap();
        assert_eq!(start["type"], "start");
        assert_eq!(start["requested_model_id"], "mlx/test");
        assert_eq!(start["actual_model_id"], "mlx/test");
        assert_eq!(done["type"], "done");
        assert_eq!(done["ok"], false);
        assert_eq!(done["requested_model_id"], "mlx/test");
        assert_eq!(done["actual_model_id"], "mlx/test");
        assert_eq!(done["promptTokens"], 0);
        assert_eq!(done["generationTokens"], 0);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn non_temp_base_dir_is_rejected_by_default() {
        let base = PathBuf::from("/Users/andrew.xie/Library/Group Containers/group.rel.flowhub");
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: true,
            requested_apply: true,
            base_dir: Some(base),
            runtime_base_dir: PathBuf::from("/tmp/rust-hub-runtime"),
            req_id: Some("r4".to_string()),
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = respond_once_value(&input);

        assert_eq!(value["ok"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["deny_code"], "base_dir_outside_shadow_sandbox");
    }

    #[test]
    fn cancel_file_is_reported_as_fail_closed_cancel_observed() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-cancel");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        fs::create_dir_all(temp.join("ai_cancels")).unwrap();
        fs::write(
            temp.join("ai_requests/req_r5.json"),
            r#"{"type":"generate","req_id":"r5","model_id":"mlx/test","task_type":"text_generate","prompt":"hello","max_tokens":8}"#,
        )
        .unwrap();
        fs::write(
            temp.join("ai_cancels/cancel_r5.json"),
            r#"{"req_id":"r5","created_at":100.0}"#,
        )
        .unwrap();
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: true,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: Some("r5".to_string()),
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = respond_once_value(&input);

        assert_eq!(value["ok"], true);
        assert_eq!(value["cancel_observed"], true);
        let response = fs::read_to_string(temp.join("ai_responses/resp_r5.jsonl")).unwrap();
        let done: Value = serde_json::from_str(response.lines().nth(1).unwrap()).unwrap();
        assert_eq!(done["reason"], "rust_file_ipc_cancel_observed");

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn runtime_execution_plan_routes_local_candidate_without_writes() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-runtime-plan");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        write_request(&temp, "plan1", "local.gguf");
        write_local_runtime_state(&temp, "local.gguf");
        let config = config_for_runtime_dir(temp.clone());
        let input = XtFileIpcShadowInput {
            root_dir: temp.clone(),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: false,
            requested_apply: false,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: Some("plan1".to_string()),
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = runtime_execution_plan_value(&config, &input, true, false, false);

        assert_eq!(value["ok"], true);
        assert_eq!(value["ready"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["request"]["requested_model_id"], "local.gguf");
        assert_eq!(value["model_route"]["selected_model_id"], "local.gguf");
        assert_eq!(value["model_route"]["selected_route_kind"], "local");
        assert_eq!(
            value["execution_adapter_plan"]["adapter_kind"],
            "local_runtime_file_ipc"
        );
        assert_eq!(value["execution_adapter_plan"]["dry_run_candidate"], true);
        assert_eq!(
            value["execution_adapter_plan"]["production_candidate"],
            false
        );
        assert_eq!(
            value["execution_adapter_plan"]["blockers"][0],
            "runtime_ready_env_missing"
        );
        assert_eq!(value["authority"]["production_authority_change"], false);
        assert_eq!(temp.join("ai_responses/resp_plan1.jsonl").exists(), false);
        assert_eq!(temp.join("hub_status.json").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn runtime_adapter_candidate_writes_fail_closed_response_under_explicit_gates() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-runtime-adapter");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        fs::create_dir_all(temp.join("ai_responses")).unwrap();
        write_request(&temp, "adapter1", "local.adapter");
        write_local_runtime_state(&temp, "local.adapter");
        let config = config_for_runtime_dir(temp.clone());
        let input = XtFileIpcShadowInput {
            root_dir: temp.clone(),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: true,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: Some("adapter1".to_string()),
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = runtime_adapter_candidate_value(&config, &input, true, true);

        assert_eq!(value["ok"], true);
        assert_eq!(value["ready"], false);
        assert_eq!(value["wrote"], true);
        assert_eq!(
            value["runtime_adapter_candidate"]["adapter_kind"],
            "local_runtime_file_ipc"
        );
        assert_eq!(value["runtime_adapter_candidate"]["executes_ml"], false);
        assert_eq!(
            value["runtime_adapter_candidate"]["production_file_ipc_ready"],
            false
        );
        let response = fs::read_to_string(temp.join("ai_responses/resp_adapter1.jsonl")).unwrap();
        let lines = response.lines().collect::<Vec<_>>();
        assert_eq!(lines.len(), 2);
        let start: Value = serde_json::from_str(lines[0]).unwrap();
        let done: Value = serde_json::from_str(lines[1]).unwrap();
        assert_eq!(start["type"], "start");
        assert_eq!(start["runtime_adapter_candidate"], true);
        assert_eq!(start["adapter_kind"], "local_runtime_file_ipc");
        assert_eq!(done["type"], "done");
        assert_eq!(done["ok"], false);
        assert_eq!(
            done["reason"],
            "rust_runtime_adapter_candidate_not_executing"
        );
        assert_eq!(done["runtime_adapter_candidate"], true);
        assert_eq!(done["adapter_kind"], "local_runtime_file_ipc");
        assert_eq!(temp.join("hub_status.json").exists(), false);
        assert_eq!(value["authority"]["production_authority_change"], false);
        assert_eq!(value["authority"]["rust_executes_ml"], false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn runtime_adapter_candidate_blocks_before_writes_without_candidate_gate() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-runtime-adapter-block");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        fs::create_dir_all(temp.join("ai_responses")).unwrap();
        write_request(&temp, "adapter2", "local.adapter");
        write_local_runtime_state(&temp, "local.adapter");
        let config = config_for_runtime_dir(temp.clone());
        let input = XtFileIpcShadowInput {
            root_dir: temp.clone(),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: true,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: Some("adapter2".to_string()),
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = runtime_adapter_candidate_value(&config, &input, true, false);

        assert_eq!(value["ok"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["deny_code"], "runtime_adapter_candidate_blocked");
        assert_eq!(
            value["runtime_adapter_candidate"]["blockers"][0],
            "runtime_adapter_candidate_env_missing"
        );
        assert_eq!(
            temp.join("ai_responses/resp_adapter2.jsonl").exists(),
            false
        );
        assert_eq!(temp.join("hub_status.json").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn runtime_adapter_candidate_blocks_without_apply_and_candidate_env() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-runtime-adapter-blocked");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        fs::create_dir_all(temp.join("ai_responses")).unwrap();
        write_request(&temp, "adapter1", "local.gguf");
        write_local_runtime_state(&temp, "local.gguf");
        let config = config_for_runtime_dir(temp.clone());
        let input = XtFileIpcShadowInput {
            root_dir: temp.clone(),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: false,
            requested_apply: false,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: Some("adapter1".to_string()),
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = runtime_adapter_candidate_value(&config, &input, true, false);

        assert_eq!(value["ok"], false);
        assert_eq!(value["ready"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["deny_code"], "runtime_adapter_candidate_blocked");
        assert_eq!(
            value["runtime_adapter_candidate"]["blockers"][0],
            "runtime_adapter_candidate_env_missing"
        );
        assert_eq!(
            value["runtime_adapter_candidate"]["blockers"][1],
            "apply_required"
        );
        assert_eq!(value["authority"]["production_authority_change"], false);
        assert_eq!(
            temp.join("ai_responses/resp_adapter1.jsonl").exists(),
            false
        );
        assert_eq!(temp.join("hub_status.json").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn runtime_adapter_candidate_writes_fail_closed_response_only() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-runtime-adapter-apply");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        fs::create_dir_all(temp.join("ai_responses")).unwrap();
        write_request(&temp, "adapter2", "local.gguf");
        write_local_runtime_state(&temp, "local.gguf");
        let config = config_for_runtime_dir(temp.clone());
        let input = XtFileIpcShadowInput {
            root_dir: temp.clone(),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: true,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: Some("adapter2".to_string()),
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = runtime_adapter_candidate_value(&config, &input, true, true);

        assert_eq!(value["ok"], true);
        assert_eq!(value["ready"], false);
        assert_eq!(value["wrote"], true);
        assert_eq!(
            value["runtime_adapter_candidate"]["adapter_kind"],
            "local_runtime_file_ipc"
        );
        assert_eq!(
            value["runtime_adapter_candidate"]["fail_closed_reason"],
            "rust_runtime_adapter_candidate_not_executing"
        );
        assert_eq!(value["runtime_adapter_candidate"]["executes_ml"], false);
        assert_eq!(
            value["runtime_adapter_candidate"]["production_file_ipc_ready"],
            false
        );
        assert_eq!(value["authority"]["production_authority_change"], false);
        assert_eq!(value["authority"]["rust_executes_ml"], false);
        let response = fs::read_to_string(temp.join("ai_responses/resp_adapter2.jsonl")).unwrap();
        let done: Value = serde_json::from_str(response.lines().nth(1).unwrap()).unwrap();
        assert_eq!(done["ok"], false);
        assert_eq!(
            done["reason"],
            "rust_runtime_adapter_candidate_not_executing"
        );
        assert_eq!(done["runtime_adapter_candidate"], true);
        assert_eq!(done["execution_path"], "rust_runtime_adapter_candidate");
        assert_eq!(temp.join("hub_status.json").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn runtime_adapter_candidate_reports_cancel_without_executing() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-runtime-adapter-cancel");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        fs::create_dir_all(temp.join("ai_responses")).unwrap();
        fs::create_dir_all(temp.join("ai_cancels")).unwrap();
        write_request(&temp, "adapter_cancel", "local.gguf");
        fs::write(
            temp.join("ai_cancels/cancel_adapter_cancel.json"),
            "{\"reason\":\"user_cancel\"}\n",
        )
        .unwrap();
        write_local_runtime_state(&temp, "local.gguf");
        let config = config_for_runtime_dir(temp.clone());
        let input = XtFileIpcShadowInput {
            root_dir: temp.clone(),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: true,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: Some("adapter_cancel".to_string()),
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = runtime_adapter_candidate_value(&config, &input, true, true);

        assert_eq!(value["ok"], true);
        assert_eq!(value["ready"], false);
        assert_eq!(value["wrote"], true);
        assert_eq!(value["cancel_observed"], true);
        assert_eq!(
            value["runtime_adapter_candidate"]["fail_closed_reason"],
            "rust_file_ipc_cancel_observed"
        );
        assert_eq!(value["runtime_adapter_candidate"]["executes_ml"], false);
        assert_eq!(value["authority"]["production_authority_change"], false);
        assert_eq!(value["authority"]["rust_executes_ml"], false);
        let response =
            fs::read_to_string(temp.join("ai_responses/resp_adapter_cancel.jsonl")).unwrap();
        let done: Value = serde_json::from_str(response.lines().nth(1).unwrap()).unwrap();
        assert_eq!(done["ok"], false);
        assert_eq!(done["reason"], "rust_file_ipc_cancel_observed");
        assert_eq!(done["runtime_adapter_candidate"], true);
        assert_eq!(temp.join("hub_status.json").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn runtime_adapter_candidate_preserves_existing_response_without_overwrite() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-runtime-adapter-existing-response");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        fs::create_dir_all(temp.join("ai_responses")).unwrap();
        write_request(&temp, "adapter_existing", "local.gguf");
        let response_path = temp.join("ai_responses/resp_adapter_existing.jsonl");
        let original = "{\"type\":\"done\",\"ok\":true,\"source\":\"existing\"}\n";
        fs::write(&response_path, original).unwrap();
        write_local_runtime_state(&temp, "local.gguf");
        let config = config_for_runtime_dir(temp.clone());
        let input = XtFileIpcShadowInput {
            root_dir: temp.clone(),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: true,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: Some("adapter_existing".to_string()),
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = runtime_adapter_candidate_value(&config, &input, true, true);

        assert_eq!(value["ok"], false);
        assert_eq!(value["ready"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["deny_code"], "response_already_exists");
        assert_eq!(value["authority"]["production_authority_change"], false);
        assert_eq!(value["authority"]["rust_executes_ml"], false);
        assert_eq!(fs::read_to_string(&response_path).unwrap(), original);
        assert_eq!(temp.join("hub_status.json").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn runtime_adapter_candidate_rejects_explicit_overwrite_without_env_gate() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-runtime-adapter-overwrite-gate");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        fs::create_dir_all(temp.join("ai_responses")).unwrap();
        write_request(&temp, "adapter_overwrite", "local.gguf");
        let response_path = temp.join("ai_responses/resp_adapter_overwrite.jsonl");
        let original = "{\"type\":\"done\",\"ok\":true,\"source\":\"existing\"}\n";
        fs::write(&response_path, original).unwrap();
        write_local_runtime_state(&temp, "local.gguf");
        let config = config_for_runtime_dir(temp.clone());
        let input = XtFileIpcShadowInput {
            root_dir: temp.clone(),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: true,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: Some("adapter_overwrite".to_string()),
            overwrite_response: true,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = runtime_adapter_candidate_value(&config, &input, true, true);

        assert_eq!(value["ok"], false);
        assert_eq!(value["ready"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["deny_code"], "response_overwrite_not_enabled");
        assert_eq!(value["authority"]["production_authority_change"], false);
        assert_eq!(value["authority"]["rust_executes_ml"], false);
        assert_eq!(fs::read_to_string(&response_path).unwrap(), original);
        assert_eq!(temp.join("hub_status.json").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn drain_dry_run_plans_multiple_requests_without_writing() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-drain-dry");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        write_request(&temp, "d1", "mlx/a");
        write_request(&temp, "d2", "mlx/b");
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: false,
            requested_apply: false,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = drain_once_value(&input);

        assert_eq!(value["ok"], true);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["drain"]["pending_request_count"], 2);
        assert_eq!(value["drain"]["attempted_count"], 2);
        assert_eq!(value["results"].as_array().unwrap().len(), 2);
        assert_eq!(temp.join("ai_responses/resp_d1.jsonl").exists(), false);
        assert_eq!(temp.join("ai_responses/resp_d2.jsonl").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn runtime_adapter_candidate_rejects_unsupported_request_without_write() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-runtime-adapter-unsupported");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        fs::create_dir_all(temp.join("ai_responses")).unwrap();
        fs::write(
            temp.join("ai_requests/req_adapter_unsupported.json"),
            r#"{"type":"embed","req_id":"adapter_unsupported","task_type":"embedding","preferred_model_id":"local.gguf"}"#,
        )
        .unwrap();
        write_local_runtime_state(&temp, "local.gguf");
        let config = config_for_runtime_dir(temp.clone());
        let input = XtFileIpcShadowInput {
            root_dir: temp.clone(),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: true,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: Some("adapter_unsupported".to_string()),
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = runtime_adapter_candidate_value(&config, &input, true, true);

        assert_eq!(value["ok"], false);
        assert_eq!(value["ready"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["deny_code"], "unsupported_request_type");
        assert_eq!(value["error_message"], "embed");
        assert_eq!(value["authority"]["production_authority_change"], false);
        assert_eq!(value["authority"]["rust_executes_ml"], false);
        assert_eq!(
            temp.join("ai_responses/resp_adapter_unsupported.jsonl")
                .exists(),
            false
        );
        assert_eq!(temp.join("hub_status.json").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn runtime_adapter_candidate_blocks_without_selected_model() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-runtime-adapter-no-model");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        fs::create_dir_all(temp.join("ai_responses")).unwrap();
        write_request(&temp, "adapter_no_model", "local.missing-model");
        let config = config_for_runtime_dir(temp.clone());
        let input = XtFileIpcShadowInput {
            root_dir: temp.clone(),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: true,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: Some("adapter_no_model".to_string()),
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = runtime_adapter_candidate_value(&config, &input, true, true);

        assert_eq!(value["ok"], false);
        assert_eq!(value["ready"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["deny_code"], "runtime_adapter_candidate_blocked");
        assert_eq!(
            value["runtime_adapter_candidate"]["blockers"]
                .as_array()
                .unwrap()
                .iter()
                .any(|item| item == "runtime_execution_plan_not_candidate"),
            true
        );
        assert_eq!(
            value["runtime_execution_plan"]["execution_adapter_plan"]["blockers"]
                .as_array()
                .unwrap()
                .iter()
                .any(|item| item == "model_route_no_selected_model"),
            true
        );
        assert_eq!(value["runtime_adapter_candidate"]["selected_model_id"], "");
        assert_eq!(value["authority"]["production_authority_change"], false);
        assert_eq!(value["authority"]["rust_executes_ml"], false);
        assert_eq!(
            temp.join("ai_responses/resp_adapter_no_model.jsonl")
                .exists(),
            false
        );
        assert_eq!(temp.join("hub_status.json").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn runtime_adapter_candidate_rejects_oversized_prompt_without_write() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-runtime-adapter-large-prompt");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        fs::create_dir_all(temp.join("ai_responses")).unwrap();
        fs::write(
            temp.join("ai_requests/req_adapter_large_prompt.json"),
            format!(
                r#"{{"type":"generate","req_id":"adapter_large_prompt","task_type":"text_generate","preferred_model_id":"local.gguf","prompt":"{}","max_tokens":8}}"#,
                "x".repeat(MAX_REQUEST_PROMPT_CHARS + 1)
            ),
        )
        .unwrap();
        write_local_runtime_state(&temp, "local.gguf");
        let config = config_for_runtime_dir(temp.clone());
        let input = XtFileIpcShadowInput {
            root_dir: temp.clone(),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: true,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: Some("adapter_large_prompt".to_string()),
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = runtime_adapter_candidate_value(&config, &input, true, true);

        assert_eq!(value["ok"], false);
        assert_eq!(value["ready"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["deny_code"], "request_prompt_too_large");
        assert_eq!(
            value["error_message"],
            (MAX_REQUEST_PROMPT_CHARS + 1).to_string()
        );
        assert_eq!(value["authority"]["production_authority_change"], false);
        assert_eq!(value["authority"]["rust_executes_ml"], false);
        assert_eq!(
            temp.join("ai_responses/resp_adapter_large_prompt.jsonl")
                .exists(),
            false
        );
        assert_eq!(temp.join("hub_status.json").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn runtime_adapter_candidate_rejects_oversized_request_file_before_parse() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-runtime-adapter-large-file");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        fs::create_dir_all(temp.join("ai_responses")).unwrap();
        fs::write(
            temp.join("ai_requests/req_adapter_large_file.json"),
            format!(
                r#"{{"type":"generate","req_id":"adapter_large_file","task_type":"text_generate","preferred_model_id":"local.gguf","prompt":"ok","padding":"{}"}}"#,
                "x".repeat(MAX_REQUEST_FILE_BYTES as usize)
            ),
        )
        .unwrap();
        write_local_runtime_state(&temp, "local.gguf");
        let config = config_for_runtime_dir(temp.clone());
        let input = XtFileIpcShadowInput {
            root_dir: temp.clone(),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: true,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: Some("adapter_large_file".to_string()),
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = runtime_adapter_candidate_value(&config, &input, true, true);

        assert_eq!(value["ok"], false);
        assert_eq!(value["ready"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["deny_code"], "request_file_too_large");
        assert_eq!(value["authority"]["production_authority_change"], false);
        assert_eq!(value["authority"]["rust_executes_ml"], false);
        assert_eq!(
            temp.join("ai_responses/resp_adapter_large_file.jsonl")
                .exists(),
            false
        );
        assert_eq!(temp.join("hub_status.json").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn runtime_adapter_candidate_rejects_invalid_request_json_without_write() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-runtime-adapter-invalid-json");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        fs::create_dir_all(temp.join("ai_responses")).unwrap();
        fs::write(
            temp.join("ai_requests/req_adapter_invalid_json.json"),
            r#"{"type":"generate","req_id":"adapter_invalid_json","preferred_model_id":"local.gguf","prompt":"broken""#,
        )
        .unwrap();
        write_local_runtime_state(&temp, "local.gguf");
        let config = config_for_runtime_dir(temp.clone());
        let input = XtFileIpcShadowInput {
            root_dir: temp.clone(),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: true,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: Some("adapter_invalid_json".to_string()),
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = runtime_adapter_candidate_value(&config, &input, true, true);

        assert_eq!(value["ok"], false);
        assert_eq!(value["ready"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["deny_code"], "request_json_invalid");
        assert_eq!(value["authority"]["production_authority_change"], false);
        assert_eq!(value["authority"]["rust_executes_ml"], false);
        assert_eq!(
            temp.join("ai_responses/resp_adapter_invalid_json.jsonl")
                .exists(),
            false
        );
        assert_eq!(temp.join("hub_status.json").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn drain_apply_respects_max_requests_and_writes_fail_closed_responses() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-drain-apply");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        write_request(&temp, "d3", "mlx/a");
        write_request(&temp, "d4", "mlx/b");
        write_request(&temp, "d5", "mlx/c");
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: true,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 2,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = drain_once_value(&input);

        assert_eq!(value["ok"], true);
        assert_eq!(value["wrote"], true);
        assert_eq!(value["drain"]["pending_request_count"], 3);
        assert_eq!(value["drain"]["attempted_count"], 2);
        assert_eq!(value["drain"]["wrote_count"], 2);
        assert_eq!(value["drain"]["remaining_unattempted_count"], 1);
        assert_eq!(temp.join("ai_responses/resp_d3.jsonl").exists(), true);
        assert_eq!(temp.join("ai_responses/resp_d4.jsonl").exists(), true);
        assert_eq!(temp.join("ai_responses/resp_d5.jsonl").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn drain_apply_gate_blocks_all_writes_when_disabled() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-drain-apply-disabled");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        write_request(&temp, "d6", "mlx/a");
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: false,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = drain_once_value(&input);

        assert_eq!(value["ok"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["deny_code"], "xt_file_ipc_shadow_apply_not_enabled");
        assert_eq!(temp.join("ai_responses/resp_d6.jsonl").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn cycle_dry_run_reports_processor_status_without_writing() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-cycle-dry");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        write_request(&temp, "c1", "mlx/a");
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: false,
            requested_apply: false,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = cycle_once_value(&input);

        assert_eq!(value["ok"], true);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["cycle"]["status_wrote"], false);
        assert_eq!(value["cycle"]["watcher_active"], false);
        assert_eq!(value["planned_processor_status"]["ready"], false);
        assert_eq!(value["drain_result"]["drain"]["attempted_count"], 1);
        assert_eq!(temp.join(PROCESSOR_STATUS_FILENAME).exists(), false);
        assert_eq!(temp.join("ai_responses/resp_c1.jsonl").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn cycle_apply_writes_shadow_status_and_fail_closed_responses() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-cycle-apply");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        write_request(&temp, "c2", "mlx/a");
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: true,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = cycle_once_value(&input);

        assert_eq!(value["ok"], true);
        assert_eq!(value["wrote"], true);
        assert_eq!(value["cycle"]["status_wrote"], true);
        assert_eq!(value["cycle"]["drain_wrote"], true);
        assert_eq!(value["authority"]["rust_writes_xt_response_file"], true);
        assert_eq!(
            value["authority"]["rust_writes_shadow_processor_status"],
            true
        );
        assert_eq!(temp.join("hub_status.json").exists(), false);
        assert_eq!(temp.join(PROCESSOR_STATUS_FILENAME).exists(), true);
        assert_eq!(temp.join("ai_responses/resp_c2.jsonl").exists(), true);
        let status: Value = serde_json::from_str(
            &fs::read_to_string(temp.join(PROCESSOR_STATUS_FILENAME)).unwrap(),
        )
        .unwrap();
        assert_eq!(
            status["schema_version"],
            SCHEMA_XT_FILE_IPC_SHADOW_PROCESSOR_STATUS_V1
        );
        assert_eq!(status["ready"], false);
        assert_eq!(status["watcher_active"], false);
        assert_eq!(status["hub_status_written"], false);
        assert_eq!(status["production_file_ipc_ready"], false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn cycle_apply_empty_request_dir_writes_only_shadow_status() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-cycle-empty");
        fs::create_dir_all(&temp).unwrap();
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: true,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = cycle_once_value(&input);

        assert_eq!(value["ok"], true);
        assert_eq!(value["wrote"], true);
        assert_eq!(value["cycle"]["status_wrote"], true);
        assert_eq!(value["cycle"]["drain_wrote"], false);
        assert_eq!(value["drain_result"]["drain"]["pending_request_count"], 0);
        assert_eq!(value["authority"]["rust_writes_xt_response_file"], false);
        assert_eq!(
            value["authority"]["rust_writes_shadow_processor_status"],
            true
        );
        assert_eq!(temp.join(PROCESSOR_STATUS_FILENAME).exists(), true);
        assert_eq!(temp.join("hub_status.json").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn supervise_dry_run_runs_bounded_cycles_without_writing() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-supervise-dry");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        write_request(&temp, "s1", "mlx/a");
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: false,
            requested_apply: false,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 3,
            cycle_interval_ms: 0,
        };

        let value = supervise_bounded_value(&input);

        assert_eq!(value["ok"], true);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["supervisor"]["cycle_count"], 3);
        assert_eq!(value["supervisor"]["background_watcher_started"], false);
        assert_eq!(value["supervisor"]["stopped"], true);
        assert_eq!(value["supervisor"]["total_attempted_count"], 3);
        assert_eq!(temp.join(PROCESSOR_STATUS_FILENAME).exists(), false);
        assert_eq!(temp.join("ai_responses/resp_s1.jsonl").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn supervise_apply_writes_status_each_cycle_and_response_once() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-supervise-apply");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        write_request(&temp, "s2", "mlx/a");
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: true,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 3,
            cycle_interval_ms: 0,
        };

        let value = supervise_bounded_value(&input);

        assert_eq!(value["ok"], true);
        assert_eq!(value["wrote"], true);
        assert_eq!(value["supervisor"]["cycle_count"], 3);
        assert_eq!(value["supervisor"]["status_wrote_count"], 3);
        assert_eq!(value["supervisor"]["response_wrote_count"], 1);
        assert_eq!(value["supervisor"]["total_attempted_count"], 1);
        assert_eq!(
            value["supervisor"]["total_skipped_existing_response_count"],
            2
        );
        assert_eq!(
            value["authority"]["rust_writes_shadow_processor_status"],
            true
        );
        assert_eq!(temp.join(PROCESSOR_STATUS_FILENAME).exists(), true);
        assert_eq!(temp.join("ai_responses/resp_s2.jsonl").exists(), true);
        assert_eq!(temp.join("hub_status.json").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn supervise_apply_gate_blocks_before_any_cycle_write() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-supervise-apply-disabled");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        write_request(&temp, "s3", "mlx/a");
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: false,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 3,
            cycle_interval_ms: 0,
        };

        let value = supervise_bounded_value(&input);

        assert_eq!(value["ok"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["deny_code"], "xt_file_ipc_shadow_apply_not_enabled");
        assert_eq!(temp.join(PROCESSOR_STATUS_FILENAME).exists(), false);
        assert_eq!(temp.join("ai_responses/resp_s3.jsonl").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn watcher_smoke_dry_run_plans_without_lock_or_status_write() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-watcher-dry");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        write_request(&temp, "w1", "mlx/a");
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: false,
            requested_apply: false,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 2,
            cycle_interval_ms: 0,
        };

        let value = watcher_smoke_value(&input);

        assert_eq!(value["ok"], true);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["watcher"]["lock_acquired"], false);
        assert_eq!(value["watcher"]["background_watcher_started"], false);
        assert_eq!(value["watcher"]["stopped"], true);
        assert_eq!(temp.join(WATCHER_LOCK_FILENAME).exists(), false);
        assert_eq!(temp.join(WATCHER_STATUS_FILENAME).exists(), false);
        assert_eq!(temp.join("ai_responses/resp_w1.jsonl").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn watcher_smoke_apply_acquires_releases_lock_and_writes_stopped_status() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-watcher-apply");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        write_request(&temp, "w2", "mlx/a");
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: true,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 2,
            cycle_interval_ms: 0,
        };

        let value = watcher_smoke_value(&input);

        assert_eq!(value["ok"], true);
        assert_eq!(value["wrote"], true);
        assert_eq!(value["watcher"]["lock_acquired"], true);
        assert_eq!(value["watcher"]["lock_released"], true);
        assert_eq!(value["watcher"]["start_status_wrote"], true);
        assert_eq!(value["watcher"]["stop_status_wrote"], true);
        assert_eq!(value["watcher"]["hub_status_written"], false);
        assert_eq!(
            value["authority"]["rust_writes_shadow_watcher_status"],
            true
        );
        assert_eq!(temp.join(WATCHER_LOCK_FILENAME).exists(), false);
        assert_eq!(temp.join(WATCHER_STATUS_FILENAME).exists(), true);
        assert_eq!(temp.join("ai_responses/resp_w2.jsonl").exists(), true);
        assert_eq!(temp.join("hub_status.json").exists(), false);
        let status: Value =
            serde_json::from_str(&fs::read_to_string(temp.join(WATCHER_STATUS_FILENAME)).unwrap())
                .unwrap();
        assert_eq!(
            status["schema_version"],
            SCHEMA_XT_FILE_IPC_SHADOW_WATCHER_STATUS_V1
        );
        assert_eq!(status["state"], "stopped");
        assert_eq!(status["ready"], false);
        assert_eq!(status["background_watcher_started"], false);
        assert_eq!(status["stopped_before_return"], true);
        assert_eq!(status["hub_status_written"], false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn watcher_smoke_apply_rejects_busy_lock_without_writes() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-watcher-busy");
        fs::create_dir_all(&temp).unwrap();
        fs::write(temp.join(WATCHER_LOCK_FILENAME), "other-watcher\n").unwrap();
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: true,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 2,
            cycle_interval_ms: 0,
        };

        let value = watcher_smoke_value(&input);

        assert_eq!(value["ok"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["deny_code"], "watcher_lock_busy");
        assert_eq!(value["watcher"]["lock_acquired"], false);
        assert_eq!(temp.join(WATCHER_LOCK_FILENAME).exists(), true);
        assert_eq!(temp.join(WATCHER_STATUS_FILENAME).exists(), false);
        assert_eq!(temp.join("hub_status.json").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn watcher_rollback_smoke_dry_run_plans_without_removing_files() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-rollback-dry");
        fs::create_dir_all(temp.join("ai_responses")).unwrap();
        fs::write(temp.join(WATCHER_LOCK_FILENAME), "stale\n").unwrap();
        fs::write(temp.join(WATCHER_STATUS_FILENAME), "{}\n").unwrap();
        fs::write(temp.join(PROCESSOR_STATUS_FILENAME), "{}\n").unwrap();
        fs::write(temp.join("hub_status.json"), "{}\n").unwrap();
        fs::write(temp.join("ai_responses/resp_r1.jsonl"), "{}\n").unwrap();
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: false,
            requested_apply: false,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = watcher_rollback_smoke_value(&input, false);

        assert_eq!(value["ok"], true);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["rollback"]["planned_remove_count"], 3);
        assert_eq!(value["rollback"]["removed_count"], 0);
        assert_eq!(temp.join(WATCHER_LOCK_FILENAME).exists(), true);
        assert_eq!(temp.join(WATCHER_STATUS_FILENAME).exists(), true);
        assert_eq!(temp.join(PROCESSOR_STATUS_FILENAME).exists(), true);
        assert_eq!(temp.join("hub_status.json").exists(), true);
        assert_eq!(temp.join("ai_responses/resp_r1.jsonl").exists(), true);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn watcher_rollback_smoke_apply_gate_blocks_before_removing_files() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-rollback-blocked");
        fs::create_dir_all(&temp).unwrap();
        fs::write(temp.join(WATCHER_LOCK_FILENAME), "stale\n").unwrap();
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: true,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = watcher_rollback_smoke_value(&input, false);

        assert_eq!(value["ok"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["deny_code"], "xt_file_ipc_rollback_apply_not_enabled");
        assert_eq!(temp.join(WATCHER_LOCK_FILENAME).exists(), true);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn watcher_rollback_smoke_apply_removes_only_rust_shadow_files() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-rollback-apply");
        fs::create_dir_all(temp.join("ai_responses")).unwrap();
        fs::write(temp.join(WATCHER_LOCK_FILENAME), "stale\n").unwrap();
        fs::write(temp.join(WATCHER_STATUS_FILENAME), "{}\n").unwrap();
        fs::write(temp.join(PROCESSOR_STATUS_FILENAME), "{}\n").unwrap();
        fs::write(temp.join("hub_status.json"), "{}\n").unwrap();
        fs::write(temp.join("ai_responses/resp_r2.jsonl"), "{}\n").unwrap();
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: true,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = watcher_rollback_smoke_value(&input, true);

        assert_eq!(value["ok"], true);
        assert_eq!(value["wrote"], true);
        assert_eq!(value["rollback"]["removed_count"], 3);
        assert_eq!(value["rollback"]["hub_status_removed"], false);
        assert_eq!(value["rollback"]["xt_response_files_removed"], false);
        assert_eq!(temp.join(WATCHER_LOCK_FILENAME).exists(), false);
        assert_eq!(temp.join(WATCHER_STATUS_FILENAME).exists(), false);
        assert_eq!(temp.join(PROCESSOR_STATUS_FILENAME).exists(), false);
        assert_eq!(temp.join("hub_status.json").exists(), true);
        assert_eq!(temp.join("ai_responses/resp_r2.jsonl").exists(), true);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn watcher_readiness_defaults_fail_closed_without_shadow_opt_in() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-watch-ready-default");
        fs::create_dir_all(&temp).unwrap();
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: false,
            shadow_apply_env_enabled: false,
            requested_apply: false,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = watcher_readiness_value(&input, false, false, false);

        assert_eq!(value["ok"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["deny_code"], "xt_file_ipc_shadow_not_enabled");
        assert_eq!(value["authority"]["production_authority_change"], false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn watcher_readiness_requires_xt_file_ipc_dirs() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-watch-ready-dirs");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: false,
            requested_apply: false,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = watcher_readiness_value(&input, true, true, true);

        assert_eq!(value["ok"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["deny_code"], "file_ipc_dirs_missing");
        assert_eq!(value["watcher_readiness"]["request_dir_ok"], true);
        assert_eq!(value["watcher_readiness"]["response_dir_ok"], false);
        assert_eq!(value["watcher_readiness"]["cancel_dir_ok"], false);
        assert_eq!(
            value["watcher_readiness"]["production_file_ipc_ready"],
            false
        );

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn watcher_readiness_candidate_ready_does_not_mark_production_ready() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-watch-ready-candidate");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        fs::create_dir_all(temp.join("ai_responses")).unwrap();
        fs::create_dir_all(temp.join("ai_cancels")).unwrap();
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: false,
            requested_apply: false,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = watcher_readiness_value(&input, true, true, true);

        assert_eq!(value["ok"], true);
        assert_eq!(value["ready"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["watcher_readiness"]["candidate_ready"], true);
        assert_eq!(
            value["watcher_readiness"]["production_file_ipc_ready"],
            false
        );
        assert_eq!(
            value["watcher_readiness"]["background_watcher_started"],
            false
        );
        assert_eq!(value["authority"]["production_authority_change"], false);
        assert_eq!(temp.join("hub_status.json").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn watcher_start_plan_defaults_fail_closed_without_shadow_opt_in() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-start-plan-default");
        fs::create_dir_all(&temp).unwrap();
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: false,
            shadow_apply_env_enabled: false,
            requested_apply: false,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = watcher_start_plan_value(&input, false, false, false, false);

        assert_eq!(value["ok"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["deny_code"], "xt_file_ipc_shadow_not_enabled");
        assert_eq!(value["authority"]["production_authority_change"], false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn watcher_start_plan_reports_blockers_without_starting_watcher() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-start-plan-blocked");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        fs::create_dir_all(temp.join("ai_responses")).unwrap();
        fs::create_dir_all(temp.join("ai_cancels")).unwrap();
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: false,
            requested_apply: false,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = watcher_start_plan_value(&input, true, true, true, false);

        assert_eq!(value["ok"], true);
        assert_eq!(value["ready"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["deny_code"], "watcher_start_blocked");
        assert_eq!(value["watcher_start_plan"]["start_candidate"], false);
        assert_eq!(
            value["watcher_start_plan"]["background_watcher_started"],
            false
        );
        assert_eq!(
            value["watcher_start_plan"]["blockers"][0],
            "watcher_start_apply_env_missing"
        );
        assert_eq!(temp.join(WATCHER_LOCK_FILENAME).exists(), false);
        assert_eq!(temp.join(WATCHER_STATUS_FILENAME).exists(), false);
        assert_eq!(temp.join("hub_status.json").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn watcher_start_plan_candidate_still_does_not_start_or_mark_ready() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-start-plan-candidate");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        fs::create_dir_all(temp.join("ai_responses")).unwrap();
        fs::create_dir_all(temp.join("ai_cancels")).unwrap();
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: false,
            requested_apply: false,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = watcher_start_plan_value(&input, true, true, true, true);

        assert_eq!(value["ok"], true);
        assert_eq!(value["ready"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["deny_code"], "");
        assert_eq!(value["watcher_start_plan"]["start_candidate"], true);
        assert_eq!(
            value["watcher_start_plan"]["background_watcher_started"],
            false
        );
        assert_eq!(
            value["watcher_start_plan"]["production_file_ipc_ready"],
            false
        );
        assert_eq!(value["watcher_start_plan"]["ml_execution_in_rust"], false);
        assert_eq!(value["authority"]["production_authority_change"], false);
        assert_eq!(temp.join(WATCHER_LOCK_FILENAME).exists(), false);
        assert_eq!(temp.join(WATCHER_STATUS_FILENAME).exists(), false);
        assert_eq!(temp.join("hub_status.json").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn watcher_run_once_defaults_fail_closed_without_shadow_opt_in() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-run-once-default");
        fs::create_dir_all(&temp).unwrap();
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: false,
            shadow_apply_env_enabled: false,
            requested_apply: false,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = watcher_run_once_value(&input, false, false, false, false, false);

        assert_eq!(value["ok"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["deny_code"], "xt_file_ipc_shadow_not_enabled");

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn watcher_run_once_apply_gate_blocks_before_any_write() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-run-once-blocked");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        fs::create_dir_all(temp.join("ai_responses")).unwrap();
        fs::create_dir_all(temp.join("ai_cancels")).unwrap();
        write_request(&temp, "ro1", "mlx/a");
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: true,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = watcher_run_once_value(&input, true, true, true, true, false);

        assert_eq!(value["ok"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["deny_code"], "watcher_run_once_blocked");
        assert_eq!(
            value["watcher_run_once"]["blockers"][0],
            "watcher_run_once_apply_env_missing"
        );
        assert_eq!(temp.join(WATCHER_LOCK_FILENAME).exists(), false);
        assert_eq!(temp.join(WATCHER_STATUS_FILENAME).exists(), false);
        assert_eq!(temp.join(PROCESSOR_STATUS_FILENAME).exists(), false);
        assert_eq!(temp.join("ai_responses/resp_ro1.jsonl").exists(), false);
        assert_eq!(temp.join("hub_status.json").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn watcher_run_once_apply_runs_one_fail_closed_cycle_and_releases_lock() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-run-once-apply");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        fs::create_dir_all(temp.join("ai_responses")).unwrap();
        fs::create_dir_all(temp.join("ai_cancels")).unwrap();
        write_request(&temp, "ro2", "mlx/a");
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: true,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 1,
            cycle_interval_ms: 0,
        };

        let value = watcher_run_once_value(&input, true, true, true, true, true);

        assert_eq!(value["ok"], true);
        assert_eq!(value["ready"], false);
        assert_eq!(value["wrote"], true);
        assert_eq!(value["watcher_run_once"]["run_candidate"], true);
        assert_eq!(value["watcher_run_once"]["lock_acquired"], true);
        assert_eq!(value["watcher_run_once"]["lock_released"], true);
        assert_eq!(value["watcher_run_once"]["cycle_executed"], true);
        assert_eq!(
            value["watcher_run_once"]["background_watcher_started"],
            false
        );
        assert_eq!(
            value["watcher_run_once"]["production_file_ipc_ready"],
            false
        );
        assert_eq!(value["watcher_run_once"]["ml_execution_in_rust"], false);
        assert_eq!(temp.join(WATCHER_LOCK_FILENAME).exists(), false);
        assert_eq!(temp.join(WATCHER_STATUS_FILENAME).exists(), true);
        assert_eq!(temp.join(PROCESSOR_STATUS_FILENAME).exists(), true);
        assert_eq!(temp.join("ai_responses/resp_ro2.jsonl").exists(), true);
        assert_eq!(temp.join("hub_status.json").exists(), false);
        let status: Value =
            serde_json::from_str(&fs::read_to_string(temp.join(WATCHER_STATUS_FILENAME)).unwrap())
                .unwrap();
        assert_eq!(status["state"], "stopped");
        assert_eq!(status["ready"], false);
        assert_eq!(status["background_watcher_started"], false);
        assert_eq!(status["hub_status_written"], false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn watcher_session_defaults_fail_closed_without_shadow_opt_in() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-session-default");
        fs::create_dir_all(&temp).unwrap();
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: false,
            shadow_apply_env_enabled: false,
            requested_apply: false,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 2,
            cycle_interval_ms: 0,
        };

        let value = watcher_session_value(&input, false, false, false, false, false);

        assert_eq!(value["ok"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["deny_code"], "xt_file_ipc_shadow_not_enabled");
        assert_eq!(temp.join(WATCHER_LOCK_FILENAME).exists(), false);
        assert_eq!(temp.join(WATCHER_STATUS_FILENAME).exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn watcher_session_apply_gate_blocks_before_any_write() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-session-blocked");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        fs::create_dir_all(temp.join("ai_responses")).unwrap();
        fs::create_dir_all(temp.join("ai_cancels")).unwrap();
        write_request(&temp, "ws1", "mlx/a");
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: true,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 2,
            cycle_interval_ms: 0,
        };

        let value = watcher_session_value(&input, true, true, true, true, false);

        assert_eq!(value["ok"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["deny_code"], "watcher_session_blocked");
        assert_eq!(
            value["watcher_session"]["blockers"][0],
            "watcher_session_apply_env_missing"
        );
        assert_eq!(temp.join(WATCHER_LOCK_FILENAME).exists(), false);
        assert_eq!(temp.join(WATCHER_STATUS_FILENAME).exists(), false);
        assert_eq!(temp.join(PROCESSOR_STATUS_FILENAME).exists(), false);
        assert_eq!(temp.join("ai_responses/resp_ws1.jsonl").exists(), false);
        assert_eq!(temp.join("hub_status.json").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn watcher_session_apply_runs_bounded_fail_closed_session_and_releases_lock() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-session-apply");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        fs::create_dir_all(temp.join("ai_responses")).unwrap();
        fs::create_dir_all(temp.join("ai_cancels")).unwrap();
        write_request(&temp, "ws2", "mlx/a");
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: true,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 2,
            cycle_interval_ms: 0,
        };

        let value = watcher_session_value(&input, true, true, true, true, true);

        assert_eq!(value["ok"], true);
        assert_eq!(value["ready"], false);
        assert_eq!(value["wrote"], true);
        assert_eq!(value["watcher_session"]["session_candidate"], true);
        assert_eq!(value["watcher_session"]["lock_acquired"], true);
        assert_eq!(value["watcher_session"]["lock_released"], true);
        assert_eq!(value["watcher_session"]["supervisor_executed"], true);
        assert_eq!(
            value["watcher_session"]["background_watcher_started"],
            false
        );
        assert_eq!(value["watcher_session"]["production_file_ipc_ready"], false);
        assert_eq!(value["watcher_session"]["ml_execution_in_rust"], false);
        assert_eq!(temp.join(WATCHER_LOCK_FILENAME).exists(), false);
        assert_eq!(temp.join(WATCHER_STATUS_FILENAME).exists(), true);
        assert_eq!(temp.join(PROCESSOR_STATUS_FILENAME).exists(), true);
        assert_eq!(temp.join("ai_responses/resp_ws2.jsonl").exists(), true);
        assert_eq!(temp.join("hub_status.json").exists(), false);
        let status: Value =
            serde_json::from_str(&fs::read_to_string(temp.join(WATCHER_STATUS_FILENAME)).unwrap())
                .unwrap();
        assert_eq!(status["state"], "stopped");
        assert_eq!(status["ready"], false);
        assert_eq!(status["background_watcher_started"], false);
        assert_eq!(status["hub_status_written"], false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn watcher_background_start_defaults_fail_closed_without_shadow_opt_in() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-background-default");
        fs::create_dir_all(&temp).unwrap();
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: false,
            shadow_apply_env_enabled: false,
            requested_apply: false,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 2,
            cycle_interval_ms: 0,
        };

        let value = watcher_background_start_value(&input, false, false, false, false, false);

        assert_eq!(value["ok"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["deny_code"], "xt_file_ipc_shadow_not_enabled");
        assert_eq!(temp.join(WATCHER_LOCK_FILENAME).exists(), false);
        assert_eq!(temp.join(WATCHER_STATUS_FILENAME).exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn watcher_background_start_apply_gate_blocks_before_any_write() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-background-blocked");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        fs::create_dir_all(temp.join("ai_responses")).unwrap();
        fs::create_dir_all(temp.join("ai_cancels")).unwrap();
        write_request(&temp, "bg1", "mlx/a");
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: true,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 2,
            cycle_interval_ms: 0,
        };

        let value = watcher_background_start_value(&input, true, true, true, true, false);

        assert_eq!(value["ok"], false);
        assert_eq!(value["wrote"], false);
        assert_eq!(value["deny_code"], "watcher_background_start_blocked");
        assert_eq!(
            value["watcher_background"]["blockers"][0],
            "watcher_background_apply_env_missing"
        );
        assert_eq!(temp.join(WATCHER_LOCK_FILENAME).exists(), false);
        assert_eq!(temp.join(WATCHER_STATUS_FILENAME).exists(), false);
        assert_eq!(temp.join("ai_responses/resp_bg1.jsonl").exists(), false);
        assert_eq!(temp.join("hub_status.json").exists(), false);

        let _ = fs::remove_dir_all(temp);
    }

    #[test]
    fn watcher_background_start_status_stop_runs_bounded_shadow_thread() {
        let temp = unique_temp_dir("xhub-xt-file-ipc-background-apply");
        fs::create_dir_all(temp.join("ai_requests")).unwrap();
        fs::create_dir_all(temp.join("ai_responses")).unwrap();
        fs::create_dir_all(temp.join("ai_cancels")).unwrap();
        write_request(&temp, "bg2", "mlx/a");
        let input = XtFileIpcShadowInput {
            root_dir: PathBuf::from("/tmp/rust-hub"),
            now_ms: 100_000,
            shadow_enabled: true,
            shadow_apply_env_enabled: true,
            requested_apply: true,
            base_dir: Some(temp.clone()),
            runtime_base_dir: temp.clone(),
            req_id: None,
            overwrite_response: false,
            max_requests: 16,
            max_cycles: 10,
            cycle_interval_ms: 20,
        };

        let start = watcher_background_start_value(&input, true, true, true, true, true);
        assert_eq!(start["ok"], true);
        assert_eq!(start["wrote"], true);
        assert_eq!(
            start["watcher_background"]["background_watcher_started"],
            true
        );
        wait_for_path(&temp.join(PROCESSOR_STATUS_FILENAME), 500);

        let status = watcher_background_status_value();
        assert_eq!(status["ok"], true);
        assert_eq!(
            status["watcher_background"]["production_file_ipc_ready"],
            false
        );

        let stop = watcher_background_stop_value(&input);
        assert_eq!(stop["ok"], true);
        assert_eq!(stop["watcher_background"]["active"], false);
        assert_eq!(temp.join(WATCHER_LOCK_FILENAME).exists(), false);
        assert_eq!(temp.join(WATCHER_STATUS_FILENAME).exists(), true);
        assert_eq!(temp.join(PROCESSOR_STATUS_FILENAME).exists(), true);
        assert_eq!(temp.join("ai_responses/resp_bg2.jsonl").exists(), true);
        assert_eq!(temp.join("hub_status.json").exists(), false);
        let file_status: Value =
            serde_json::from_str(&fs::read_to_string(temp.join(WATCHER_STATUS_FILENAME)).unwrap())
                .unwrap();
        assert_eq!(file_status["state"], "stopped");
        assert_eq!(file_status["ready"], false);
        assert_eq!(file_status["hub_status_written"], false);

        let _ = fs::remove_dir_all(temp);
    }

    fn write_request(base_dir: &Path, req_id: &str, model_id: &str) {
        fs::write(
            base_dir
                .join("ai_requests")
                .join(format!("req_{req_id}.json")),
            format!(
                r#"{{"type":"generate","req_id":"{req_id}","model_id":"{model_id}","task_type":"text_generate","prompt":"hello","max_tokens":8}}"#
            ),
        )
        .unwrap();
    }

    fn write_local_runtime_state(base_dir: &Path, model_id: &str) {
        let artifact_path = base_dir.join("model.gguf");
        fs::write(&artifact_path, "fixture").unwrap();
        fs::write(
            base_dir.join("models_state.json"),
            format!(
                r#"{{
                  "models": [
                    {{
                      "id": "{model_id}",
                      "backend": "mlx",
                      "modelPath": "{}",
                      "capabilities": ["text_generate"]
                    }}
                  ]
                }}"#,
                artifact_path.display()
            ),
        )
        .unwrap();
        fs::write(
            base_dir.join("ai_runtime_status.json"),
            r#"{
              "providers": {
                "mlx": {
                  "provider": "mlx",
                  "ok": true,
                  "availableTaskKinds": ["text_generate"],
                  "runtimeSource": "fixture",
                  "runtimeSourcePath": "/tmp/fixture-runtime",
                  "runtimeResolutionState": "resolved",
                  "updatedAtMs": 1000
                }
              }
            }"#,
        )
        .unwrap();
    }

    fn config_for_runtime_dir(runtime_base_dir: PathBuf) -> HubConfig {
        HubConfig {
            root_dir: runtime_base_dir.clone(),
            db_path: runtime_base_dir.join("hub.sqlite3"),
            runtime_base_dir,
            proto_path: PathBuf::from("/tmp/hub_protocol_v1.proto"),
            canonical_proto_path: PathBuf::from("/tmp/canonical_hub_protocol_v1.proto"),
            host: "127.0.0.1".to_string(),
            http_port: 0,
            grpc_port: 0,
            http_access_key: None,
            http_access_key_source: String::new(),
            http_access_key_required: false,
        }
    }

    fn wait_for_path(path: &Path, timeout_ms: u64) {
        let deadline = std::time::Instant::now() + Duration::from_millis(timeout_ms);
        while std::time::Instant::now() < deadline {
            if path.exists() {
                return;
            }
            thread::sleep(Duration::from_millis(10));
        }
    }

    fn unique_temp_dir(label: &str) -> PathBuf {
        let dir = env::temp_dir().join(format!("{}-{}-{}", label, process::id(), now_ms()));
        let _ = fs::remove_dir_all(&dir);
        dir
    }
}
