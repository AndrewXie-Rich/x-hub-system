use std::env;
use std::fs::{self, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use serde_json::{json, Value};
use xhub_core::{json_escape, now_ms, path_exists, HubConfig};

pub const LOCAL_ML_BRIDGE_SCHEMA: &str = "xhub.rust_hub.local_ml_execution_bridge.v1";
pub const LOCAL_ML_READINESS_SCHEMA: &str = "xhub.rust_hub.local_ml_execution_readiness.v1";
const LOCAL_RUNTIME_COMMAND_IPC_VERSION: &str = "xhub.local_runtime_command_ipc.v1";
const LOCAL_RUNTIME_COMMAND_POLL_MS: u64 = 30;

#[cfg(unix)]
unsafe extern "C" {
    #[link_name = "kill"]
    fn libc_kill(pid: i32, sig: i32) -> i32;
}

#[derive(Debug, Clone)]
pub struct LocalMlReadiness {
    pub enabled: bool,
    pub ready: bool,
    pub runtime_base_dir: PathBuf,
    pub runtime_base_dir_exists: bool,
    pub script_path: PathBuf,
    pub script_exists: bool,
    pub python_executable: String,
    pub python_available: bool,
    pub command_proxy_ready: bool,
    pub authority: String,
    pub blocker: String,
}

pub fn authority_enabled() -> bool {
    env_bool("XHUB_RUST_ML_EXECUTION_AUTHORITY", false)
        || env_bool("XHUB_RUST_LOCAL_ML_EXECUTION_AUTHORITY", false)
        || env_bool("XHUB_ENABLE_RUST_ML_EXECUTION", false)
}

pub fn readiness(config: &HubConfig) -> LocalMlReadiness {
    let runtime_base_dir = config.runtime_base_dir.clone();
    readiness_for_runtime_base_dir(config, &runtime_base_dir)
}

fn readiness_for_runtime_base_dir(config: &HubConfig, runtime_base_dir: &Path) -> LocalMlReadiness {
    let enabled = authority_enabled();
    let runtime_base_dir_exists = path_exists(runtime_base_dir);
    let script_path = resolve_local_runtime_script(config);
    let script_exists = script_path.is_file();
    let python_executable = resolve_python_executable(runtime_base_dir).unwrap_or_default();
    let python_available = !python_executable.is_empty();
    let command_proxy_ready =
        local_runtime_command_proxy_ready(runtime_base_dir, Duration::from_secs(5));
    let ready = enabled && runtime_base_dir_exists && script_exists && python_available;
    let blocker = if !enabled {
        "authority_disabled"
    } else if !runtime_base_dir_exists {
        "runtime_base_dir_missing"
    } else if !script_exists {
        "local_runtime_script_missing"
    } else if !python_available {
        "python_unavailable"
    } else {
        ""
    };
    LocalMlReadiness {
        enabled,
        ready,
        runtime_base_dir: runtime_base_dir.to_path_buf(),
        runtime_base_dir_exists,
        script_path,
        script_exists,
        python_executable,
        python_available,
        command_proxy_ready,
        authority: if ready {
            "rust_admission_python_engine".to_string()
        } else if enabled {
            "rust_admission_blocked".to_string()
        } else {
            "disabled".to_string()
        },
        blocker: blocker.to_string(),
    }
}

pub fn readiness_value(config: &HubConfig) -> Value {
    readiness_to_value(&readiness(config))
}

pub fn readiness_http_json(config: &HubConfig, query: &str) -> (&'static str, String) {
    let runtime_base_dir = query_param(query, "runtime_base_dir")
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from)
        .unwrap_or_else(|| config.runtime_base_dir.clone());
    let status = readiness_for_runtime_base_dir(config, &runtime_base_dir);
    ("200 OK", format!("{}\n", readiness_to_value(&status)))
}

pub fn start_resident_runtime_preheat_if_enabled(config: &HubConfig) {
    if !env_bool("XHUB_RUST_LOCAL_ML_RESIDENT_RUNTIME_PREHEAT", true) {
        return;
    }
    let config = config.clone();
    thread::spawn(move || {
        let delay_ms =
            env_u64("XHUB_RUST_LOCAL_ML_RESIDENT_RUNTIME_PREHEAT_DELAY_MS", 500).clamp(0, 60_000);
        if delay_ms > 0 {
            thread::sleep(Duration::from_millis(delay_ms));
        }
        let _ = resident_runtime_preheat_once(&config);
    });
}

pub fn execute_http_json(config: &HubConfig, method: &str, body: &str) -> (&'static str, String) {
    if method != "POST" {
        return (
            "405 Method Not Allowed",
            format!(
                "{{\"schema_version\":\"{}\",\"ok\":false,\"error\":\"method_not_allowed\"}}\n",
                LOCAL_ML_BRIDGE_SCHEMA
            ),
        );
    }
    match execute_from_body(config, body) {
        Ok(value) => ("200 OK", format!("{value}\n")),
        Err(value) => ("200 OK", format!("{value}\n")),
    }
}

fn execute_from_body(config: &HubConfig, body: &str) -> Result<Value, Value> {
    let started_at_ms = now_ms_u64();
    let parsed: Value = serde_json::from_str(body.trim()).map_err(|err| {
        fail_value(
            "",
            started_at_ms,
            "invalid_json",
            format!("invalid local ML execution JSON: {err}"),
            json!({}),
        )
    })?;
    let envelope = parsed.as_object().ok_or_else(|| {
        fail_value(
            "",
            started_at_ms,
            "invalid_request",
            "local ML execution body must be a JSON object",
            json!({}),
        )
    })?;

    let command = first_string(&parsed, &["command", "runtime_command", "runtimeCommand"])
        .unwrap_or_else(|| "run-local-task".to_string());
    if !matches!(command.as_str(), "run-local-task" | "run_local_task") {
        return Err(fail_value(
            request_id_from_envelope(&parsed).as_str(),
            started_at_ms,
            "unsupported_local_ml_command",
            format!("unsupported local ML command: {command}"),
            json!({ "command": command }),
        ));
    }

    let request = envelope
        .get("request")
        .or_else(|| envelope.get("local_runtime_request"))
        .or_else(|| envelope.get("localRuntimeRequest"))
        .cloned()
        .unwrap_or_else(|| parsed.clone());
    let request_obj = request.as_object().ok_or_else(|| {
        fail_value(
            request_id_from_envelope(&parsed).as_str(),
            started_at_ms,
            "invalid_local_runtime_request",
            "local runtime request must be a JSON object",
            json!({}),
        )
    })?;
    if let Some(path) = secret_field_path(&request) {
        return Err(fail_value(
            request_id_from_envelope(&parsed).as_str(),
            started_at_ms,
            "local_ml_request_secret_material",
            format!("local ML execution request contains secret field: {path}"),
            json!({ "secret_path": path }),
        ));
    }

    let runtime_base_dir = first_string(&parsed, &["runtime_base_dir", "runtimeBaseDir"])
        .or_else(|| {
            first_string(
                &request,
                &["runtime_base_dir", "runtimeBaseDir", "_base_dir"],
            )
        })
        .map(PathBuf::from)
        .unwrap_or_else(|| config.runtime_base_dir.clone());
    let request_id = first_string(&parsed, &["request_id", "requestId"])
        .or_else(|| first_string(&request, &["request_id", "requestId", "req_id", "reqId"]))
        .unwrap_or_default();
    let timeout_ms = first_u64(&parsed, &["timeout_ms", "timeoutMs"])
        .or_else(|| first_u64(&request, &["timeout_ms", "timeoutMs"]))
        .unwrap_or(60_000)
        .clamp(1_000, 300_000);

    let status = readiness_for_runtime_base_dir(config, &runtime_base_dir);
    if !status.ready {
        let value = fail_value(
            request_id.as_str(),
            started_at_ms,
            status.blocker.as_str(),
            format!(
                "local ML execution authority is not ready: {}",
                status.blocker
            ),
            json!({
                "readiness": readiness_to_value(&status),
            }),
        );
        append_audit(&runtime_base_dir, &value);
        return Err(value);
    }

    let mut normalized_request = Value::Object(request_obj.clone());
    ensure_local_text_task_kind(&mut normalized_request);
    if let Value::Object(map) = &mut normalized_request {
        map.insert(
            "_base_dir".to_string(),
            Value::String(runtime_base_dir.display().to_string()),
        );
    }

    maybe_start_resident_local_runtime(&status);

    let proxy_ready_for_execution =
        local_runtime_command_proxy_ready(&runtime_base_dir, Duration::from_secs(5));
    let execution =
        if env_bool("XHUB_RUST_LOCAL_ML_COMMAND_PROXY", true) && proxy_ready_for_execution {
            match run_local_runtime_command_proxy(
                "run_local_task",
                &normalized_request,
                &runtime_base_dir,
                timeout_ms,
                &request_id,
                started_at_ms,
            ) {
                Ok(result) => Ok((result, "resident_command_proxy")),
                Err(err) if command_proxy_error_safe_to_fallback(&err) => {
                    let fallback_request = disable_short_process_daemon_proxy(&normalized_request);
                    run_python_local_runtime(
                        &status.python_executable,
                        &status.script_path,
                        "run-local-task",
                        &fallback_request,
                        &runtime_base_dir,
                        timeout_ms,
                    )
                    .map(|result| (result, "short_process_after_proxy_submit_error"))
                }
                Err(err) => Err(err),
            }
        } else {
            let fallback_request = disable_short_process_daemon_proxy(&normalized_request);
            run_python_local_runtime(
                &status.python_executable,
                &status.script_path,
                "run-local-task",
                &fallback_request,
                &runtime_base_dir,
                timeout_ms,
            )
            .map(|result| (result, "short_process"))
        };
    let finished_at_ms = now_ms_u64();
    let duration_ms = finished_at_ms.saturating_sub(started_at_ms);
    let audit_ref = format!("rust-local-ml-{request_id}-{started_at_ms}");
    let (result, execution_path) = match execution {
        Ok(result) => result,
        Err(err) => {
            let value = fail_value(
                request_id.as_str(),
                started_at_ms,
                "local_ml_execution_failed",
                err,
                json!({
                    "finished_at_ms": finished_at_ms,
                    "duration_ms": duration_ms,
                    "audit_ref": audit_ref,
                }),
            );
            append_audit(&runtime_base_dir, &value);
            return Err(value);
        }
    };
    let ok = result.get("ok").and_then(Value::as_bool).unwrap_or(false);
    let error_code = if ok {
        ""
    } else {
        result
            .get("reasonCode")
            .or_else(|| result.get("reason_code"))
            .or_else(|| result.get("error"))
            .and_then(Value::as_str)
            .unwrap_or("local_runtime_failed")
    };
    let value = json!({
        "schema_version": LOCAL_ML_BRIDGE_SCHEMA,
        "ok": ok,
        "command": "execute",
        "engine": "python_local_runtime",
        "execution_authority_in_rust": true,
        "request_id": request_id,
        "runtime_base_dir": runtime_base_dir.display().to_string(),
        "started_at_ms": started_at_ms,
        "finished_at_ms": finished_at_ms,
        "duration_ms": duration_ms,
        "audit_ref": audit_ref,
        "error_code": error_code,
        "execution_path": execution_path,
        "command_proxy_ready_for_execution": proxy_ready_for_execution,
        "readiness": readiness_to_value(&status),
        "result": result,
    });
    append_audit(&runtime_base_dir, &value);
    if ok {
        Ok(value)
    } else {
        Err(value)
    }
}

fn resident_runtime_preheat_once(config: &HubConfig) -> Value {
    let started_at_ms = now_ms_u64();
    let status = readiness(config);
    let before_command_proxy_ready = status.command_proxy_ready;
    let mut action = "skipped";
    let mut reason = String::new();
    if status.ready {
        if before_command_proxy_ready {
            action = "already_ready";
        } else {
            action = "start_resident_runtime";
        }
    } else {
        reason = status.blocker.clone();
    }
    let startup_wait_ms = env_u64(
        "XHUB_RUST_LOCAL_ML_RESIDENT_RUNTIME_PREHEAT_STARTUP_WAIT_MS",
        env_u64(
            "XHUB_RUST_LOCAL_ML_RESIDENT_RUNTIME_STARTUP_WAIT_MS",
            30_000,
        ),
    )
    .clamp(0, 60_000);
    let ready_after_start_wait = if status.ready && !before_command_proxy_ready {
        maybe_start_resident_local_runtime_with_wait(&status, startup_wait_ms)
    } else {
        before_command_proxy_ready
    };
    let after_command_proxy_ready =
        local_runtime_command_proxy_ready(&status.runtime_base_dir, Duration::from_secs(5));
    if status.ready && !after_command_proxy_ready && reason.is_empty() {
        reason = "resident_runtime_start_wait_timeout".to_string();
    }
    let model_prewarm = maybe_prewarm_resident_model(&status, after_command_proxy_ready);
    let finished_at_ms = now_ms_u64();
    let value = json!({
        "schema_version": "xhub.rust_hub.local_ml_resident_preheat.v1",
        "ok": status.ready && after_command_proxy_ready,
        "command": "resident-runtime-preheat",
        "action": action,
        "reason": reason,
        "production_authority_change": false,
        "runtime_base_dir": status.runtime_base_dir.display().to_string(),
        "started_at_ms": started_at_ms,
        "finished_at_ms": finished_at_ms,
        "duration_ms": finished_at_ms.saturating_sub(started_at_ms),
        "before_command_proxy_ready": before_command_proxy_ready,
        "startup_wait_ms": startup_wait_ms,
        "ready_after_start_wait": ready_after_start_wait,
        "after_command_proxy_ready": after_command_proxy_ready,
        "model_prewarm": model_prewarm,
        "readiness": readiness_to_value(&status),
    });
    append_audit(&status.runtime_base_dir, &value);
    value
}

fn maybe_prewarm_resident_model(status: &LocalMlReadiness, command_proxy_ready: bool) -> Value {
    if !env_bool("XHUB_RUST_LOCAL_ML_RESIDENT_MODEL_PREWARM", false) {
        return json!({
            "enabled": false,
            "attempted": false,
        });
    }
    if !status.ready || !command_proxy_ready {
        return json!({
            "enabled": true,
            "attempted": false,
            "ok": false,
            "reason": if status.ready { "command_proxy_not_ready" } else { "local_ml_not_ready" },
        });
    }
    let model_id = env_string("XHUB_RUST_LOCAL_ML_RESIDENT_MODEL_PREWARM_MODEL_ID")
        .or_else(|| env_string("XHUB_RUST_LOCAL_ML_MODEL_PREWARM_MODEL_ID"))
        .unwrap_or_default();
    if model_id.is_empty() {
        return json!({
            "enabled": true,
            "attempted": false,
            "ok": false,
            "reason": "model_id_missing",
        });
    }
    let provider = env_string("XHUB_RUST_LOCAL_ML_RESIDENT_MODEL_PREWARM_PROVIDER")
        .or_else(|| env_string("XHUB_RUST_LOCAL_ML_MODEL_PREWARM_PROVIDER"))
        .unwrap_or_default();
    let task_kind = env_string("XHUB_RUST_LOCAL_ML_RESIDENT_MODEL_PREWARM_TASK_KIND")
        .or_else(|| env_string("XHUB_RUST_LOCAL_ML_MODEL_PREWARM_TASK_KIND"))
        .unwrap_or_else(|| "text_generate".to_string());
    let timeout_ms = env_u64(
        "XHUB_RUST_LOCAL_ML_RESIDENT_MODEL_PREWARM_TIMEOUT_MS",
        120_000,
    )
    .clamp(1_000, 300_000);
    let started_at_ms = now_ms_u64();
    let mut request = serde_json::Map::new();
    request.insert("action".to_string(), json!("warmup_local_model"));
    request.insert("model_id".to_string(), json!(model_id));
    request.insert("modelId".to_string(), json!(model_id));
    request.insert("task_kind".to_string(), json!(task_kind));
    request.insert("taskKind".to_string(), json!(task_kind));
    request.insert(
        "source".to_string(),
        json!("rust_local_ml_resident_model_prewarm"),
    );
    if !provider.is_empty() {
        request.insert("provider".to_string(), json!(provider));
    }
    let result = run_local_runtime_command_proxy(
        "manage_local_model",
        &Value::Object(request),
        &status.runtime_base_dir,
        timeout_ms,
        "rust_local_ml_resident_model_prewarm",
        started_at_ms,
    );
    let finished_at_ms = now_ms_u64();
    match result {
        Ok(value) => json!({
            "enabled": true,
            "attempted": true,
            "ok": value.get("ok").and_then(Value::as_bool).unwrap_or(false),
            "action": value.get("action").cloned().unwrap_or(Value::Null),
            "provider": value.get("provider").cloned().unwrap_or(Value::Null),
            "model_id": value.get("modelId").or_else(|| value.get("model_id")).cloned().unwrap_or(Value::Null),
            "task_kind": value.get("taskKind").or_else(|| value.get("task_kind")).cloned().unwrap_or(Value::Null),
            "error": value.get("error").cloned().unwrap_or(Value::Null),
            "duration_ms": finished_at_ms.saturating_sub(started_at_ms),
        }),
        Err(err) => json!({
            "enabled": true,
            "attempted": true,
            "ok": false,
            "error": err,
            "duration_ms": finished_at_ms.saturating_sub(started_at_ms),
        }),
    }
}

fn run_local_runtime_command_proxy(
    command: &str,
    request: &Value,
    runtime_base_dir: &Path,
    timeout_ms: u64,
    request_id: &str,
    started_at_ms: u64,
) -> Result<Value, String> {
    let command_dir = runtime_base_dir.join("local_runtime_commands");
    let result_dir = runtime_base_dir.join("local_runtime_command_results");
    fs::create_dir_all(&command_dir)
        .map_err(|err| format!("create_local_runtime_command_dir_failed:{err}"))?;
    fs::create_dir_all(&result_dir)
        .map_err(|err| format!("create_local_runtime_result_dir_failed:{err}"))?;

    let req_id = local_runtime_command_req_id(request_id, started_at_ms);
    let command_path = command_dir.join(format!("cmd_{req_id}.json"));
    let tmp_path = command_dir.join(format!(".cmd_{req_id}.tmp"));
    let result_path = result_dir.join(format!("resp_{req_id}.json"));
    let _ = fs::remove_file(&result_path);

    let payload = json!({
        "type": "local_runtime_command",
        "req_id": req_id,
        "command": command,
        "request": request,
        "requested_at": now_ms_u64() as f64 / 1000.0,
        "requested_at_ms": now_ms_u64(),
    });
    let payload_text = serde_json::to_string(&payload)
        .map_err(|err| format!("serialize_proxy_request_failed:{err}"))?;
    fs::write(&tmp_path, payload_text)
        .map_err(|err| format!("local_runtime_command_submit_failed:write:{err}"))?;
    fs::rename(&tmp_path, &command_path)
        .map_err(|err| format!("local_runtime_command_submit_failed:rename:{err}"))?;

    let deadline = Instant::now() + Duration::from_millis(timeout_ms.max(1_000));
    loop {
        if result_path.exists() {
            let raw = fs::read_to_string(&result_path)
                .map_err(|err| format!("local_runtime_command_response_read_failed:{err}"))?;
            let _ = fs::remove_file(&result_path);
            let value = serde_json::from_str::<Value>(&raw)
                .map_err(|err| format!("local_runtime_command_response_invalid_json:{err}"))?;
            if value.as_object().is_none() {
                return Err("local_runtime_command_response_invalid_shape".to_string());
            }
            return Ok(value);
        }
        if Instant::now() >= deadline {
            let _ = fs::remove_file(&command_path);
            return Err(format!(
                "local_runtime_command_timeout:{}",
                if command.trim().is_empty() {
                    "unknown"
                } else {
                    command.trim()
                }
            ));
        }
        thread::sleep(Duration::from_millis(LOCAL_RUNTIME_COMMAND_POLL_MS));
    }
}

fn command_proxy_error_safe_to_fallback(error: &str) -> bool {
    error.starts_with("create_local_runtime_command_dir_failed:")
        || error.starts_with("create_local_runtime_result_dir_failed:")
        || error.starts_with("serialize_proxy_request_failed:")
        || error.starts_with("local_runtime_command_submit_failed:")
}

fn local_runtime_command_req_id(request_id: &str, started_at_ms: u64) -> String {
    let seed = if request_id.trim().is_empty() {
        "rust_local_ml".to_string()
    } else {
        request_id.trim().to_string()
    };
    let mut sanitized = String::with_capacity(seed.len().min(80));
    for ch in seed.chars() {
        if ch.is_ascii_alphanumeric() || matches!(ch, '-' | '_' | '.') {
            sanitized.push(ch);
        } else {
            sanitized.push('_');
        }
        if sanitized.len() >= 80 {
            break;
        }
    }
    let prefix = sanitized.trim_matches('_');
    if prefix.is_empty() {
        format!("rust_local_ml_{started_at_ms}")
    } else {
        format!("{prefix}_{started_at_ms}")
    }
}

fn run_python_local_runtime(
    python_executable: &str,
    script_path: &Path,
    command: &str,
    request: &Value,
    runtime_base_dir: &Path,
    timeout_ms: u64,
) -> Result<Value, String> {
    let payload =
        serde_json::to_string(request).map_err(|err| format!("serialize_request_failed:{err}"))?;
    let mut child = Command::new(python_executable)
        .arg(script_path)
        .arg(command)
        .arg("-")
        .env("REL_FLOW_HUB_BASE_DIR", runtime_base_dir)
        .env("PYTHONUNBUFFERED", "1")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|err| format!("spawn_local_runtime_failed:{err}"))?;

    if let Some(mut stdin) = child.stdin.take() {
        stdin
            .write_all(payload.as_bytes())
            .map_err(|err| format!("write_local_runtime_stdin_failed:{err}"))?;
    }

    let mut stdout = child
        .stdout
        .take()
        .ok_or_else(|| "local_runtime_stdout_unavailable".to_string())?;
    let mut stderr = child
        .stderr
        .take()
        .ok_or_else(|| "local_runtime_stderr_unavailable".to_string())?;
    let stdout_handle = thread::spawn(move || {
        let mut out = String::new();
        let _ = stdout.read_to_string(&mut out);
        out
    });
    let stderr_handle = thread::spawn(move || {
        let mut out = String::new();
        let _ = stderr.read_to_string(&mut out);
        out
    });

    let deadline = Instant::now() + Duration::from_millis(timeout_ms);
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) => {
                if Instant::now() >= deadline {
                    let _ = child.kill();
                    let _ = child.wait();
                    return Err("local_runtime_run_local_task_timeout".to_string());
                }
                thread::sleep(Duration::from_millis(20));
            }
            Err(err) => {
                let _ = child.kill();
                return Err(format!("wait_local_runtime_failed:{err}"));
            }
        }
    };
    let stdout_text = stdout_handle.join().unwrap_or_default();
    let stderr_text = stderr_handle.join().unwrap_or_default();
    if !status.success() {
        let detail = if stderr_text.trim().is_empty() {
            stdout_text.trim()
        } else {
            stderr_text.trim()
        };
        return Err(format!(
            "local_runtime_run_local_task_exit_{}:{}",
            status.code().unwrap_or(-1),
            detail.chars().take(240).collect::<String>()
        ));
    }
    serde_json::from_str(stdout_text.trim()).map_err(|err| {
        format!(
            "local_runtime_run_local_task_invalid_json:{err}:{}",
            stdout_text.chars().take(240).collect::<String>()
        )
    })
}

fn maybe_start_resident_local_runtime(status: &LocalMlReadiness) {
    let wait_ms =
        env_u64("XHUB_RUST_LOCAL_ML_RESIDENT_RUNTIME_STARTUP_WAIT_MS", 8_000).clamp(0, 30_000);
    let _ = maybe_start_resident_local_runtime_with_wait(status, wait_ms);
}

fn maybe_start_resident_local_runtime_with_wait(status: &LocalMlReadiness, wait_ms: u64) -> bool {
    if !env_bool("XHUB_RUST_LOCAL_ML_RESIDENT_RUNTIME_AUTOSTART", true) {
        return false;
    }
    if !status.ready || status.command_proxy_ready {
        return status.command_proxy_ready;
    }
    if local_runtime_command_proxy_ready(&status.runtime_base_dir, Duration::from_secs(5)) {
        return true;
    }

    let spawn_result = Command::new(&status.python_executable)
        .arg(&status.script_path)
        .env("REL_FLOW_HUB_BASE_DIR", &status.runtime_base_dir)
        .env("PYTHONUNBUFFERED", "1")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
    let Ok(mut child) = spawn_result else {
        return false;
    };

    let deadline = Instant::now() + Duration::from_millis(wait_ms);
    loop {
        match child.try_wait() {
            Ok(Some(_)) => return false,
            Ok(None) => {}
            Err(_) => return false,
        }
        if local_runtime_command_proxy_ready(&status.runtime_base_dir, Duration::from_secs(5)) {
            return true;
        }
        if Instant::now() >= deadline {
            return false;
        }
        thread::sleep(Duration::from_millis(100));
    }
}

fn local_runtime_command_proxy_ready(runtime_base_dir: &Path, max_age: Duration) -> bool {
    let path = runtime_base_dir.join("ai_runtime_status.json");
    let Ok(raw) = fs::read_to_string(path) else {
        return false;
    };
    let Ok(value) = serde_json::from_str::<Value>(&raw) else {
        return false;
    };
    let version = first_string(
        &value,
        &["localCommandIpcVersion", "local_command_ipc_version"],
    )
    .unwrap_or_default();
    if version != LOCAL_RUNTIME_COMMAND_IPC_VERSION {
        return false;
    }
    let updated_at = value_f64(&value, "updatedAt")
        .or_else(|| value_f64(&value, "updated_at"))
        .unwrap_or(0.0);
    if updated_at <= 0.0 {
        return false;
    }
    let age_sec = (now_ms_u64() as f64 / 1000.0) - updated_at;
    if age_sec.is_sign_negative() || age_sec > max_age.as_secs_f64().max(1.0) {
        return false;
    }
    let pid = value_u64(&value, "pid")
        .or_else(|| value_u64(&value, "runtime_pid"))
        .unwrap_or(0);
    process_alive(pid)
}

fn readiness_to_value(status: &LocalMlReadiness) -> Value {
    json!({
        "schema_version": LOCAL_ML_READINESS_SCHEMA,
        "ok": true,
        "enabled": status.enabled,
        "ready": status.ready,
        "authority": status.authority,
        "execution_authority_in_rust": status.ready,
        "bridge_http": true,
        "engine": "python_local_runtime",
        "runtime_base_dir": status.runtime_base_dir.display().to_string(),
        "runtime_base_dir_exists": status.runtime_base_dir_exists,
        "script_path": status.script_path.display().to_string(),
        "script_exists": status.script_exists,
        "python_available": status.python_available,
        "python_executable": status.python_executable,
        "command_proxy_ready": status.command_proxy_ready,
        "blocker": status.blocker,
    })
}

fn fail_value(
    request_id: &str,
    started_at_ms: u64,
    error_code: &str,
    error_message: impl Into<String>,
    extra: Value,
) -> Value {
    let finished_at_ms = now_ms_u64();
    json!({
        "schema_version": LOCAL_ML_BRIDGE_SCHEMA,
        "ok": false,
        "command": "execute",
        "engine": "python_local_runtime",
        "execution_authority_in_rust": authority_enabled(),
        "request_id": request_id,
        "started_at_ms": started_at_ms,
        "finished_at_ms": finished_at_ms,
        "duration_ms": finished_at_ms.saturating_sub(started_at_ms),
        "error_code": error_code,
        "error_message": error_message.into(),
        "extra": extra,
    })
}

fn resolve_local_runtime_script(config: &HubConfig) -> PathBuf {
    for key in [
        "XHUB_RUST_LOCAL_RUNTIME_SCRIPT",
        "XHUB_LOCAL_RUNTIME_SCRIPT",
        "RELFLOWHUB_LOCAL_RUNTIME_SCRIPT",
    ] {
        if let Some(path) = env_path(key) {
            return path;
        }
    }
    if let Some(root) = env_path("XHUB_SYSTEM_ROOT") {
        let candidate = root
            .join("x-hub")
            .join("python-runtime")
            .join("python_service")
            .join("relflowhub_local_runtime.py");
        if candidate.is_file() {
            return candidate;
        }
    }
    for candidate in [
        PathBuf::from(
            "/Applications/X-Hub.app/Contents/Resources/python_service/relflowhub_local_runtime.py",
        ),
        config
            .root_dir
            .join("..")
            .join("..")
            .join("x-hub-system")
            .join("x-hub")
            .join("python-runtime")
            .join("python_service")
            .join("relflowhub_local_runtime.py"),
        config
            .root_dir
            .join("..")
            .join("x-hub-system")
            .join("x-hub")
            .join("python-runtime")
            .join("python_service")
            .join("relflowhub_local_runtime.py"),
    ] {
        if candidate.is_file() {
            return candidate;
        }
    }
    PathBuf::from(
        "/Applications/X-Hub.app/Contents/Resources/python_service/relflowhub_local_runtime.py",
    )
}

fn resolve_python_executable(runtime_base_dir: &Path) -> Option<String> {
    let mut candidates: Vec<String> = Vec::new();
    for key in [
        "RELFLOWHUB_AI_RUNTIME_PYTHON",
        "REL_FLOW_HUB_RUNTIME_PYTHON",
        "X_HUB_LOCAL_RUNTIME_PYTHON",
        "PYTHON3",
        "PYTHON",
    ] {
        if let Ok(value) = env::var(key) {
            push_candidate(&mut candidates, value.trim());
        }
    }
    for candidate in python_candidates_from_runtime_status(runtime_base_dir) {
        push_candidate(&mut candidates, candidate.as_str());
    }
    for candidate in [
        "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3",
        "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
        "/opt/homebrew/bin/python3",
        "/usr/local/bin/python3",
    ] {
        push_candidate(&mut candidates, candidate);
    }
    candidates
        .into_iter()
        .find(|candidate| candidate_python_executable(candidate))
}

fn python_candidates_from_runtime_status(runtime_base_dir: &Path) -> Vec<String> {
    let path = runtime_base_dir.join("ai_runtime_status.json");
    let Ok(raw) = fs::read_to_string(path) else {
        return Vec::new();
    };
    let Ok(value) = serde_json::from_str::<Value>(&raw) else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for key in ["pythonExecutable", "python_executable"] {
        if let Some(value) = value.get(key).and_then(Value::as_str) {
            push_candidate(&mut out, value);
        }
    }
    if let Some(providers) = value.get("providers").and_then(Value::as_object) {
        for provider in providers.values() {
            for key in ["pythonExecutable", "python_executable"] {
                if let Some(value) = provider.get(key).and_then(Value::as_str) {
                    push_candidate(&mut out, value);
                }
            }
        }
    }
    out
}

fn push_candidate(out: &mut Vec<String>, value: &str) {
    let cleaned = value.trim();
    if cleaned.is_empty() || !Path::new(cleaned).is_absolute() {
        return;
    }
    if out.iter().any(|item| item == cleaned) {
        return;
    }
    out.push(cleaned.to_string());
}

fn executable_file(path: &str) -> bool {
    let candidate = Path::new(path);
    candidate.is_file()
}

fn candidate_python_executable(path: &str) -> bool {
    executable_file(path) && !unsafe_python(path) && path_basename_contains_python(path)
}

fn path_basename_contains_python(path: &str) -> bool {
    Path::new(path)
        .file_name()
        .and_then(|name| name.to_str())
        .map(|name| name.to_ascii_lowercase().contains("python"))
        .unwrap_or(false)
}

fn unsafe_python(path: &str) -> bool {
    let normalized = path.trim().to_ascii_lowercase();
    normalized == "/usr/bin/python3"
        || normalized == "/usr/bin/python"
        || normalized.contains("/applications/xcode.app/contents/developer/")
        || normalized.contains("/library/developer/commandlinetools/")
}

fn ensure_local_text_task_kind(request: &mut Value) {
    let task_kind = first_string(request, &["task_kind", "taskKind"])
        .or_else(|| first_string(request, &["task_type", "taskType"]))
        .unwrap_or_default();
    if task_kind == "text_generate" {
        if let Value::Object(map) = request {
            map.entry("task_kind".to_string())
                .or_insert_with(|| Value::String("text_generate".to_string()));
            map.entry("taskKind".to_string())
                .or_insert_with(|| Value::String("text_generate".to_string()));
        }
    }
}

fn disable_short_process_daemon_proxy(request: &Value) -> Value {
    let mut out = request.clone();
    if let Value::Object(map) = &mut out {
        map.insert("allow_daemon_proxy".to_string(), Value::Bool(false));
        map.insert("allowDaemonProxy".to_string(), Value::Bool(false));
    }
    out
}

#[cfg(unix)]
fn process_alive(pid: u64) -> bool {
    if pid <= 1 || pid > i32::MAX as u64 {
        return false;
    }
    unsafe { libc_kill(pid as i32, 0) == 0 }
}

#[cfg(not(unix))]
fn process_alive(pid: u64) -> bool {
    pid > 1
}

fn request_id_from_envelope(value: &Value) -> String {
    first_string(value, &["request_id", "requestId", "req_id", "reqId"]).unwrap_or_default()
}

fn first_string(value: &Value, keys: &[&str]) -> Option<String> {
    let object = value.as_object()?;
    for key in keys {
        if let Some(raw) = object.get(*key) {
            if let Some(text) = raw.as_str() {
                let cleaned = text.trim();
                if !cleaned.is_empty() {
                    return Some(cleaned.to_string());
                }
            }
        }
    }
    None
}

fn first_u64(value: &Value, keys: &[&str]) -> Option<u64> {
    let object = value.as_object()?;
    for key in keys {
        if let Some(raw) = object.get(*key) {
            if let Some(number) = raw.as_u64() {
                return Some(number);
            }
            if let Some(text) = raw.as_str() {
                if let Ok(number) = text.trim().parse::<u64>() {
                    return Some(number);
                }
            }
        }
    }
    None
}

fn secret_field_path(value: &Value) -> Option<String> {
    fn visit(value: &Value, path: &str) -> Option<String> {
        match value {
            Value::Array(items) => {
                for (index, item) in items.iter().enumerate() {
                    if let Some(path) = visit(item, format!("{path}[{index}]").as_str()) {
                        return Some(path);
                    }
                }
                None
            }
            Value::Object(map) => {
                for (key, item) in map {
                    let normalized = key.replace(['-', '_'], "").to_ascii_lowercase();
                    if matches!(
                        normalized.as_str(),
                        "apikey"
                            | "accesstoken"
                            | "refreshtoken"
                            | "clientsecret"
                            | "authorization"
                            | "password"
                            | "providerkey"
                    ) {
                        return Some(format!("{path}.{key}"));
                    }
                    if let Some(path) = visit(item, format!("{path}.{key}").as_str()) {
                        return Some(path);
                    }
                }
                None
            }
            _ => None,
        }
    }
    visit(value, "request")
}

fn append_audit(runtime_base_dir: &Path, value: &Value) {
    if runtime_base_dir.as_os_str().is_empty() {
        return;
    }
    let path = runtime_base_dir.join("local_ml_execution_audit.jsonl");
    let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path) else {
        return;
    };
    let _ = writeln!(file, "{}", redact_for_audit(value));
}

fn redact_for_audit(value: &Value) -> String {
    match serde_json::to_string(value) {
        Ok(raw) => raw,
        Err(err) => format!(
            "{{\"schema_version\":\"{}\",\"ok\":false,\"error\":\"audit_serialize_failed\",\"message\":\"{}\"}}",
            LOCAL_ML_BRIDGE_SCHEMA,
            json_escape(err.to_string().as_str())
        ),
    }
}

fn query_param(query: &str, key: &str) -> Option<String> {
    for pair in query.split('&') {
        if pair.is_empty() {
            continue;
        }
        let (raw_key, raw_value) = pair.split_once('=').unwrap_or((pair, ""));
        if percent_decode_query(raw_key).ok()?.as_str() == key {
            return percent_decode_query(raw_value).ok();
        }
    }
    None
}

fn percent_decode_query(input: &str) -> Result<String, String> {
    let bytes = input.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        match bytes[index] {
            b'+' => {
                out.push(b' ');
                index += 1;
            }
            b'%' if index + 2 < bytes.len() => {
                let hex = std::str::from_utf8(&bytes[index + 1..index + 3])
                    .map_err(|err| err.to_string())?;
                let byte = u8::from_str_radix(hex, 16).map_err(|err| err.to_string())?;
                out.push(byte);
                index += 3;
            }
            byte => {
                out.push(byte);
                index += 1;
            }
        }
    }
    String::from_utf8(out).map_err(|err| err.to_string())
}

fn env_path(key: &str) -> Option<PathBuf> {
    env::var(key)
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
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

fn env_string(key: &str) -> Option<String> {
    env::var(key)
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn env_u64(key: &str, fallback: u64) -> u64 {
    env::var(key)
        .ok()
        .and_then(|value| value.trim().parse::<u64>().ok())
        .unwrap_or(fallback)
}

fn value_u64(value: &Value, key: &str) -> Option<u64> {
    let raw = value.as_object()?.get(key)?;
    if let Some(number) = raw.as_u64() {
        return Some(number);
    }
    raw.as_str()?.trim().parse::<u64>().ok()
}

fn value_f64(value: &Value, key: &str) -> Option<f64> {
    let raw = value.as_object()?.get(key)?;
    if let Some(number) = raw.as_f64() {
        return Some(number);
    }
    raw.as_str()?.trim().parse::<f64>().ok()
}

fn now_ms_u64() -> u64 {
    now_ms().min(u64::MAX as u128) as u64
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    static TEMP_COUNTER: AtomicU64 = AtomicU64::new(0);

    fn unique_temp_dir(label: &str) -> PathBuf {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        let seq = TEMP_COUNTER.fetch_add(1, Ordering::Relaxed);
        env::temp_dir().join(format!("{label}-{}-{now}-{seq}", std::process::id()))
    }

    #[test]
    fn secret_field_path_rejects_secret_keys() {
        let value = json!({
            "model_id": "local",
            "nested": { "api_key": "secret" },
        });
        assert_eq!(
            secret_field_path(&value),
            Some("request.nested.api_key".to_string())
        );
    }

    #[test]
    fn ensure_local_text_task_kind_copies_task_type() {
        let mut value = json!({ "task_type": "text_generate" });
        ensure_local_text_task_kind(&mut value);
        assert_eq!(
            value.get("task_kind").and_then(Value::as_str),
            Some("text_generate")
        );
        assert_eq!(
            value.get("taskKind").and_then(Value::as_str),
            Some("text_generate")
        );
    }

    #[test]
    fn short_process_fallback_disables_daemon_proxy() {
        let value = disable_short_process_daemon_proxy(&json!({
            "model_id": "local-test",
            "allowDaemonProxy": true,
        }));
        assert_eq!(
            value.get("allow_daemon_proxy").and_then(Value::as_bool),
            Some(false)
        );
        assert_eq!(
            value.get("allowDaemonProxy").and_then(Value::as_bool),
            Some(false)
        );
    }

    #[test]
    fn runtime_status_python_candidates_ignore_runtime_source_path() {
        let dir = unique_temp_dir("xhub-local-ml-test");
        fs::create_dir_all(&dir).unwrap();
        fs::write(
            dir.join("ai_runtime_status.json"),
            json!({
                "runtimeSourcePath": "/Users/test/.lmstudio/bin/lms",
                "providers": {
                    "mlx": {
                        "runtime_source_path": "/Users/test/.lmstudio/bin/lms",
                        "pythonExecutable": "/opt/homebrew/bin/python3"
                    }
                }
            })
            .to_string(),
        )
        .unwrap();
        let candidates = python_candidates_from_runtime_status(&dir);
        let _ = fs::remove_dir_all(&dir);
        assert_eq!(candidates, vec!["/opt/homebrew/bin/python3".to_string()]);
    }

    #[test]
    fn python_executable_candidate_rejects_non_python_binary_names() {
        assert!(!path_basename_contains_python(
            "/Users/test/.lmstudio/bin/lms"
        ));
        assert!(path_basename_contains_python("/opt/homebrew/bin/python3"));
    }

    #[test]
    fn command_proxy_ready_requires_fresh_runtime_marker() {
        let dir = unique_temp_dir("xhub-local-ml-proxy");
        fs::create_dir_all(&dir).unwrap();
        fs::write(
            dir.join("ai_runtime_status.json"),
            json!({
                "localCommandIpcVersion": LOCAL_RUNTIME_COMMAND_IPC_VERSION,
                "updatedAt": now_ms_u64() as f64 / 1000.0,
                "pid": std::process::id(),
            })
            .to_string(),
        )
        .unwrap();
        assert!(local_runtime_command_proxy_ready(
            &dir,
            Duration::from_secs(5)
        ));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    #[cfg(unix)]
    fn command_proxy_ready_rejects_dead_runtime_pid() {
        let dir = unique_temp_dir("xhub-local-ml-proxy-dead");
        fs::create_dir_all(&dir).unwrap();
        let mut child = Command::new("sleep").arg("1").spawn().unwrap();
        let pid = child.id();
        child.kill().unwrap();
        let _ = child.wait();
        fs::write(
            dir.join("ai_runtime_status.json"),
            json!({
                "localCommandIpcVersion": LOCAL_RUNTIME_COMMAND_IPC_VERSION,
                "updatedAt": now_ms_u64() as f64 / 1000.0,
                "pid": pid,
            })
            .to_string(),
        )
        .unwrap();
        assert!(!local_runtime_command_proxy_ready(
            &dir,
            Duration::from_secs(5)
        ));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn command_proxy_ready_rejects_stale_runtime_marker() {
        let dir = unique_temp_dir("xhub-local-ml-proxy-stale");
        fs::create_dir_all(&dir).unwrap();
        fs::write(
            dir.join("ai_runtime_status.json"),
            json!({
                "localCommandIpcVersion": LOCAL_RUNTIME_COMMAND_IPC_VERSION,
                "updatedAt": (now_ms_u64() as f64 / 1000.0) - 60.0,
                "pid": 4242,
            })
            .to_string(),
        )
        .unwrap();
        assert!(!local_runtime_command_proxy_ready(
            &dir,
            Duration::from_secs(5)
        ));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn local_runtime_command_proxy_round_trips_result() {
        let dir = unique_temp_dir("xhub-local-ml-proxy-roundtrip");
        fs::create_dir_all(&dir).unwrap();
        let responder_dir = dir.clone();
        let handle = thread::spawn(move || {
            let command_dir = responder_dir.join("local_runtime_commands");
            let result_dir = responder_dir.join("local_runtime_command_results");
            let deadline = Instant::now() + Duration::from_secs(2);
            loop {
                if Instant::now() >= deadline {
                    panic!("proxy command was not observed");
                }
                let entries = fs::read_dir(&command_dir)
                    .ok()
                    .into_iter()
                    .flat_map(|items| items.filter_map(Result::ok))
                    .collect::<Vec<_>>();
                if let Some(entry) = entries
                    .into_iter()
                    .find(|entry| entry.file_name().to_string_lossy().starts_with("cmd_"))
                {
                    let command_path = entry.path();
                    let raw = fs::read_to_string(&command_path).unwrap();
                    let observed = serde_json::from_str::<Value>(&raw).unwrap();
                    let req_id = observed
                        .get("req_id")
                        .and_then(Value::as_str)
                        .unwrap()
                        .to_string();
                    fs::create_dir_all(&result_dir).unwrap();
                    fs::write(
                        result_dir.join(format!("resp_{req_id}.json")),
                        json!({
                            "ok": true,
                            "command": "run_local_task",
                            "via": "resident_command_proxy_test"
                        })
                        .to_string(),
                    )
                    .unwrap();
                    let _ = fs::remove_file(command_path);
                    return observed;
                }
                thread::sleep(Duration::from_millis(10));
            }
        });

        let result = run_local_runtime_command_proxy(
            "run_local_task",
            &json!({
                "provider": "transformers",
                "model_id": "hf-embed",
                "task_kind": "embedding"
            }),
            &dir,
            2_000,
            "req direct/proxy",
            now_ms_u64(),
        )
        .unwrap();
        let observed = handle.join().unwrap();

        assert_eq!(
            observed.get("type").and_then(Value::as_str),
            Some("local_runtime_command")
        );
        assert_eq!(
            observed.get("command").and_then(Value::as_str),
            Some("run_local_task")
        );
        assert_eq!(
            observed
                .get("request")
                .and_then(|request| request.get("model_id"))
                .and_then(Value::as_str),
            Some("hf-embed")
        );
        assert_eq!(result.get("ok").and_then(Value::as_bool), Some(true));
        assert_eq!(
            result.get("via").and_then(Value::as_str),
            Some("resident_command_proxy_test")
        );
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn local_runtime_command_proxy_timeout_cleans_command_file() {
        let dir = unique_temp_dir("xhub-local-ml-proxy-timeout");
        fs::create_dir_all(&dir).unwrap();

        let err = run_local_runtime_command_proxy(
            "run_local_task",
            &json!({ "provider": "mlx", "task_kind": "text_generate" }),
            &dir,
            1,
            "timeout-request",
            now_ms_u64(),
        )
        .unwrap_err();

        assert!(err.starts_with("local_runtime_command_timeout:"));
        let remaining = fs::read_dir(dir.join("local_runtime_commands"))
            .unwrap()
            .filter_map(Result::ok)
            .collect::<Vec<_>>();
        assert!(remaining.is_empty());
        let _ = fs::remove_dir_all(&dir);
    }
}
