use std::path::PathBuf;

use serde_json::{json, Value};
use xhub_core::{json_escape, HubConfig};

use crate::server::handlers::evidence::maybe_attach_route_evidence;
use crate::server::parse::{
    body_bool_alias, body_string, body_string_alias, body_string_list, body_u128, body_u64_alias,
    first_non_empty_string, first_non_empty_string_list, optional_query_bool_alias,
    optional_query_i64_alias, optional_query_u128_alias, optional_query_u64_alias,
    optional_query_usize, query_param, query_string_list,
};
use crate::{model_bridge, scheduler_bridge};

pub(crate) fn model_inventory_http_json(config: &HubConfig, query: &str) -> (&'static str, String) {
    let runtime_base_dir = query_param(query, "runtime_base_dir")
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let request_now_ms = match optional_query_u128_alias(query, "now_ms", "nowMs") {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    match model_bridge::inventory_json_from_parts(config, runtime_base_dir, request_now_ms) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"model_inventory_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn model_capabilities_http_json(
    config: &HubConfig,
    query: &str,
) -> (&'static str, String) {
    let runtime_base_dir = query_param(query, "runtime_base_dir")
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let request_now_ms = match optional_query_u128_alias(query, "now_ms", "nowMs") {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    match model_bridge::local_capabilities_json_from_parts(config, runtime_base_dir, request_now_ms)
    {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"model_capabilities_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn model_concurrency_policy_http_json(config: &HubConfig) -> (&'static str, String) {
    let scheduler = scheduler_bridge::effective_scheduler_config(config);
    let policy_path = std::env::var("XHUB_MODEL_CONCURRENCY_POLICY_PATH")
        .ok()
        .or_else(|| std::env::var("HUB_MODEL_CONCURRENCY_POLICY_PATH").ok())
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| {
            if config.runtime_base_dir.as_os_str().is_empty() {
                String::new()
            } else {
                config
                    .runtime_base_dir
                    .join("model_concurrency_policy.json")
                    .display()
                    .to_string()
            }
        });
    let body = json!({
        "schema_version": "xhub.model_concurrency_policy_status.v1",
        "ok": true,
        "policy_path": policy_path,
        "paid_ai": {
            "global_concurrency": scheduler.global_concurrency,
            "per_project_concurrency": scheduler.per_scope_concurrency,
            "queue_limit": scheduler.queue_limit,
            "queue_timeout_ms": scheduler.queue_timeout_ms,
        },
    });
    ("200 OK", format!("{body}\n"))
}

pub(crate) fn model_repair_plan_http_json(
    config: &HubConfig,
    query: &str,
) -> (&'static str, String) {
    let runtime_base_dir = query_param(query, "runtime_base_dir")
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let request_now_ms = match optional_query_u128_alias(query, "now_ms", "nowMs") {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    let request = model_bridge::ModelLocalRepairPlanRequest {
        action: query_param(query, "action")
            .or_else(|| query_param(query, "repair_action"))
            .or_else(|| query_param(query, "repairAction"))
            .unwrap_or_default(),
        task_kind: query_param(query, "task_kind")
            .or_else(|| query_param(query, "taskKind"))
            .or_else(|| query_param(query, "task"))
            .unwrap_or_default(),
        provider_id: query_param(query, "provider_id")
            .or_else(|| query_param(query, "providerId"))
            .or_else(|| query_param(query, "provider"))
            .unwrap_or_default(),
    };
    match model_bridge::local_repair_plan_json_from_parts(
        config,
        runtime_base_dir,
        request,
        request_now_ms,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"model_repair_plan_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn model_repair_apply_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    let parsed_body = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        match serde_json::from_str::<Value>(body) {
            Ok(value) => value,
            Err(err) => {
                return (
                    "400 Bad Request",
                    format!(
                        "{{\"ok\":false,\"error\":\"invalid_model_repair_apply_json\",\"message\":\"{}\"}}\n",
                        json_escape(&err.to_string())
                    ),
                )
            }
        }
    };
    let runtime_base_dir = query_param(query, "runtime_base_dir")
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .or_else(|| body_string_alias(&parsed_body, "runtime_base_dir", "runtimeBaseDir"))
        .map(PathBuf::from);
    let request_now_ms = match optional_query_u128_alias(query, "now_ms", "nowMs") {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    let query_confirm = match optional_query_bool_alias(query, "confirm", "confirmed", false) {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    let query_dry_run = match optional_query_bool_alias(query, "dry_run", "dryRun", false) {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    let request = model_bridge::ModelLocalRepairApplyRequest {
        action: body_string(&parsed_body, "action")
            .or_else(|| body_string_alias(&parsed_body, "repair_action", "repairAction"))
            .or_else(|| query_param(query, "action"))
            .or_else(|| query_param(query, "repair_action"))
            .or_else(|| query_param(query, "repairAction"))
            .unwrap_or_default(),
        task_kind: body_string_alias(&parsed_body, "task_kind", "taskKind")
            .or_else(|| body_string(&parsed_body, "task"))
            .or_else(|| query_param(query, "task_kind"))
            .or_else(|| query_param(query, "taskKind"))
            .or_else(|| query_param(query, "task"))
            .unwrap_or_default(),
        provider_id: body_string_alias(&parsed_body, "provider_id", "providerId")
            .or_else(|| body_string(&parsed_body, "provider"))
            .or_else(|| query_param(query, "provider_id"))
            .or_else(|| query_param(query, "providerId"))
            .or_else(|| query_param(query, "provider"))
            .unwrap_or_default(),
        confirm: body_bool_alias(&parsed_body, "confirm", "confirmed").unwrap_or(query_confirm),
        dry_run: body_bool_alias(&parsed_body, "dry_run", "dryRun").unwrap_or(query_dry_run),
        confirmation_token: body_string_alias(
            &parsed_body,
            "confirmation_token",
            "confirmationToken",
        )
        .or_else(|| query_param(query, "confirmation_token"))
        .or_else(|| query_param(query, "confirmationToken"))
        .unwrap_or_default(),
        requested_by: body_string_alias(&parsed_body, "requested_by", "requestedBy")
            .or_else(|| query_param(query, "requested_by"))
            .or_else(|| query_param(query, "requestedBy"))
            .unwrap_or_else(|| "http".to_string()),
        model_id: body_string_alias(&parsed_body, "model_id", "modelId")
            .or_else(|| query_param(query, "model_id"))
            .or_else(|| query_param(query, "modelId"))
            .unwrap_or_default(),
        display_name: body_string_alias(&parsed_body, "display_name", "displayName")
            .or_else(|| query_param(query, "display_name"))
            .or_else(|| query_param(query, "displayName"))
            .unwrap_or_default(),
        artifact_path: body_string_alias(&parsed_body, "artifact_path", "artifactPath")
            .or_else(|| query_param(query, "artifact_path"))
            .or_else(|| query_param(query, "artifactPath"))
            .unwrap_or_default(),
        format: body_string(&parsed_body, "format")
            .or_else(|| query_param(query, "format"))
            .unwrap_or_default(),
        quantization: body_string(&parsed_body, "quantization")
            .or_else(|| query_param(query, "quantization"))
            .unwrap_or_default(),
        capabilities: {
            let body_values = body_string_list(&parsed_body, "capabilities");
            if body_values.is_empty() {
                query_string_list(query, "capabilities")
            } else {
                body_values
            }
        },
        task_kinds: {
            let body_values = body_string_list(&parsed_body, "task_kinds");
            if body_values.is_empty() {
                let alias_values = body_string_list(&parsed_body, "taskKinds");
                if alias_values.is_empty() {
                    query_string_list(query, "task_kinds")
                        .into_iter()
                        .chain(query_string_list(query, "taskKinds"))
                        .collect()
                } else {
                    alias_values
                }
            } else {
                body_values
            }
        },
        context_length: body_u64_alias(&parsed_body, "context_length", "contextLength")
            .or_else(|| optional_query_u64_alias(query, "context_length", "contextLength", 0).ok())
            .unwrap_or(0),
        memory_bytes: body_u64_alias(&parsed_body, "memory_bytes", "memoryBytes")
            .or_else(|| optional_query_u64_alias(query, "memory_bytes", "memoryBytes", 0).ok())
            .unwrap_or(0),
    };
    match model_bridge::local_repair_apply_json_from_parts(
        config,
        runtime_base_dir,
        request,
        request_now_ms,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"model_repair_apply_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn model_repair_jobs_http_json(
    config: &HubConfig,
    query: &str,
) -> (&'static str, String) {
    let runtime_base_dir = query_param(query, "runtime_base_dir")
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let request_now_ms = match optional_query_u128_alias(query, "now_ms", "nowMs") {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    let limit = match optional_query_usize(query, "limit", 20) {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    match model_bridge::local_repair_jobs_json_from_parts(
        config,
        runtime_base_dir,
        limit,
        request_now_ms,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"model_repair_jobs_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn model_route_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    match model_route_http_body(config, query, body) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"model_route_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn model_route_http_body(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> Result<String, String> {
    let parsed_body = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        serde_json::from_str::<Value>(body)
            .map_err(|err| format!("invalid model route request json: {err}"))?
    };

    let runtime_base_dir = body_string(&parsed_body, "runtime_base_dir")
        .or_else(|| body_string(&parsed_body, "runtimeBaseDir"))
        .or_else(|| query_param(query, "runtime_base_dir"))
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let route_now_ms = body_u128(&parsed_body, "now_ms")
        .or_else(|| body_u128(&parsed_body, "nowMs"))
        .or_else(|| query_param(query, "now_ms").and_then(|value| value.parse::<u128>().ok()))
        .or_else(|| query_param(query, "nowMs").and_then(|value| value.parse::<u128>().ok()));
    let request = model_bridge::ModelRouteRequest {
        task_type: first_non_empty_string(vec![
            body_string(&parsed_body, "task_type"),
            body_string(&parsed_body, "taskType"),
            body_string(&parsed_body, "task"),
            query_param(query, "task_type"),
            query_param(query, "taskType"),
            query_param(query, "task"),
        ])
        .unwrap_or_else(|| "text_generate".to_string()),
        model_id: first_non_empty_string(vec![
            body_string(&parsed_body, "model_id"),
            body_string(&parsed_body, "modelId"),
            body_string(&parsed_body, "preferred_model_id"),
            body_string(&parsed_body, "preferredModelId"),
            query_param(query, "model_id"),
            query_param(query, "modelId"),
            query_param(query, "preferred_model_id"),
            query_param(query, "preferredModelId"),
        ])
        .unwrap_or_else(|| "auto".to_string()),
        required_capabilities: first_non_empty_string_list(vec![
            body_string_list(&parsed_body, "required_capabilities"),
            body_string_list(&parsed_body, "requiredCapabilities"),
            body_string_list(&parsed_body, "required_capability"),
            body_string_list(&parsed_body, "requiredCapability"),
            body_string_list(&parsed_body, "capabilities"),
            query_string_list(query, "required_capabilities"),
            query_string_list(query, "requiredCapabilities"),
            query_string_list(query, "required_capability"),
            query_string_list(query, "requiredCapability"),
            query_string_list(query, "capabilities"),
        ]),
        privacy_mode: first_non_empty_string(vec![
            body_string(&parsed_body, "privacy_mode"),
            body_string(&parsed_body, "privacyMode"),
            query_param(query, "privacy_mode"),
            query_param(query, "privacyMode"),
        ])
        .unwrap_or_else(|| "standard".to_string()),
        cost_preference: first_non_empty_string(vec![
            body_string(&parsed_body, "cost_preference"),
            body_string(&parsed_body, "costPreference"),
            query_param(query, "cost_preference"),
            query_param(query, "costPreference"),
        ])
        .unwrap_or_else(|| "balanced".to_string()),
    };

    let body =
        model_bridge::route_json_from_parts(config, runtime_base_dir, request, route_now_ms)?;
    maybe_attach_route_evidence(config, query, &parsed_body, "model_route", body)
}

pub(crate) fn model_compare_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    match model_compare_http_body(config, query, body) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"model_compare_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn model_compare_http_body(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> Result<String, String> {
    let parsed_body = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        serde_json::from_str::<Value>(body)
            .map_err(|err| format!("invalid model compare request json: {err}"))?
    };

    let node_value = if let Some(value) = parsed_body.get("node_inventory") {
        value.clone()
    } else if let Some(value) = parsed_body.get("nodeInventory") {
        value.clone()
    } else if let Some(raw) = parsed_body
        .get("node_inventory_json")
        .or_else(|| parsed_body.get("nodeInventoryJson"))
        .and_then(Value::as_str)
    {
        serde_json::from_str::<Value>(raw)
            .map_err(|err| format!("invalid node_inventory_json: {err}"))?
    } else if let Some(raw) = query_param(query, "node_inventory_json")
        .or_else(|| query_param(query, "nodeInventoryJson"))
    {
        serde_json::from_str::<Value>(&raw)
            .map_err(|err| format!("invalid node_inventory_json: {err}"))?
    } else {
        return Err("model compare requires node_inventory".to_string());
    };

    let runtime_base_dir = body_string(&parsed_body, "runtime_base_dir")
        .or_else(|| body_string(&parsed_body, "runtimeBaseDir"))
        .or_else(|| query_param(query, "runtime_base_dir"))
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let compare_now_ms = body_u128(&parsed_body, "now_ms")
        .or_else(|| body_u128(&parsed_body, "nowMs"))
        .or_else(|| query_param(query, "now_ms").and_then(|value| value.parse::<u128>().ok()))
        .or_else(|| query_param(query, "nowMs").and_then(|value| value.parse::<u128>().ok()));

    model_bridge::compare_inventory_json_from_parts(
        config,
        runtime_base_dir,
        node_value,
        compare_now_ms,
    )
}

pub(crate) fn model_reports_http_json(config: &HubConfig, query: &str) -> (&'static str, String) {
    let limit = match optional_query_usize(query, "limit", 20) {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    match model_bridge::reports_json_from_parts(config, limit) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"model_reports_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn model_diagnostics_http_json(
    config: &HubConfig,
    query: &str,
) -> (&'static str, String) {
    let limit = match optional_query_usize(query, "limit", 3) {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    match model_bridge::diagnostics_json_from_parts(config, limit) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"model_diagnostics_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn model_readiness_http_json(config: &HubConfig, query: &str) -> (&'static str, String) {
    let limit = match optional_query_usize(query, "limit", 20) {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    let min_compare_reports =
        match optional_query_i64_alias(query, "min_compare_reports", "minCompareReports", 10) {
            Ok(value) => value,
            Err(body) => return ("400 Bad Request", body),
        };
    let max_mismatches = match optional_query_i64_alias(query, "max_mismatches", "maxMismatches", 0)
    {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    match model_bridge::readiness_json_from_parts(
        config,
        min_compare_reports,
        max_mismatches,
        limit,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"model_readiness_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}
