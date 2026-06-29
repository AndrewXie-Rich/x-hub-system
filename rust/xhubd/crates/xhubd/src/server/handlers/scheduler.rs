use serde_json::Value;
use xhub_core::{json_escape, HubConfig};

use crate::scheduler_bridge;
use crate::server::parse::{
    body_i32, body_i64_alias, body_string, body_string_alias, body_u64_alias, first_non_empty,
    optional_query_bool_alias, optional_query_i64_alias, optional_query_u64_alias,
    optional_query_usize_alias, push_optional_flag, push_optional_i32_flag, push_optional_i64_flag,
    push_payload_flag, push_required_flag, push_value_flag, query_param,
};

pub(crate) fn scheduler_status_http_json(
    config: &HubConfig,
    query: &str,
) -> (&'static str, String) {
    let include_queue_items =
        match optional_query_bool_alias(query, "include_queue_items", "includeQueueItems", true) {
            Ok(value) => value,
            Err(body) => return ("400 Bad Request", body),
        };
    let queue_items_limit =
        match optional_query_usize_alias(query, "queue_items_limit", "queueItemsLimit", 100) {
            Ok(value) => value,
            Err(body) => return ("400 Bad Request", body),
        };
    match scheduler_bridge::status_json_from_parts(config, include_queue_items, queue_items_limit) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"scheduler_status_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn scheduler_readiness_http_json(
    config: &HubConfig,
    query: &str,
) -> (&'static str, String) {
    let compare_limit = match optional_query_usize_alias(query, "compare_limit", "compareLimit", 20)
    {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    let min_compare_reports =
        match optional_query_i64_alias(query, "min_compare_reports", "minCompareReports", 10) {
            Ok(value) => value.max(0),
            Err(body) => return ("400 Bad Request", body),
        };
    let max_mismatches = match optional_query_i64_alias(query, "max_mismatches", "maxMismatches", 0)
    {
        Ok(value) => value.max(0),
        Err(body) => return ("400 Bad Request", body),
    };
    let min_lease_shadow_runs =
        match optional_query_i64_alias(query, "min_lease_shadow_runs", "minLeaseShadowRuns", 1) {
            Ok(value) => value.max(0),
            Err(body) => return ("400 Bad Request", body),
        };
    let max_stale_active =
        match optional_query_i64_alias(query, "max_stale_active", "maxStaleActive", 0) {
            Ok(value) => value.max(0),
            Err(body) => return ("400 Bad Request", body),
        };
    let max_orphaned_leases =
        match optional_query_i64_alias(query, "max_orphaned_leases", "maxOrphanedLeases", 0) {
            Ok(value) => value.max(0),
            Err(body) => return ("400 Bad Request", body),
        };
    let lease_report_limit =
        match optional_query_usize_alias(query, "lease_report_limit", "leaseReportLimit", 20) {
            Ok(value) => value,
            Err(body) => return ("400 Bad Request", body),
        };
    let stale_after_ms =
        match optional_query_u64_alias(query, "stale_after_ms", "staleAfterMs", 300_000) {
            Ok(value) => value,
            Err(body) => return ("400 Bad Request", body),
        };
    let allow_active_runs =
        match optional_query_bool_alias(query, "allow_active_runs", "allowActiveRuns", false) {
            Ok(value) => value,
            Err(body) => return ("400 Bad Request", body),
        };
    let component = query_param(query, "component")
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "scheduler".to_string());
    let run_id_prefix = query_param(query, "run_id_prefix")
        .or_else(|| query_param(query, "runIdPrefix"))
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "node_paid_ai_".to_string());

    match scheduler_bridge::cutover_readiness_json_from_parts(
        config,
        scheduler_bridge::CutoverReadinessParams {
            component,
            compare_limit,
            min_compare_reports,
            max_mismatches,
            run_id_prefix,
            stale_after_ms,
            lease_report_limit,
            min_lease_shadow_runs,
            max_stale_active,
            max_orphaned_leases,
            allow_active_runs,
        },
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"scheduler_readiness_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn scheduler_command_http_json(
    config: &HubConfig,
    command: &str,
    body: &str,
) -> (&'static str, String) {
    match scheduler_command_http_body(config, command, body) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"scheduler_command_failed\",\"command\":\"{}\",\"message\":\"{}\"}}\n",
                json_escape(command),
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn scheduler_command_http_body(
    config: &HubConfig,
    command: &str,
    body: &str,
) -> Result<String, String> {
    let parsed_body = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        serde_json::from_str::<Value>(body)
            .map_err(|err| format!("invalid scheduler request json: {err}"))?
    };
    let args = scheduler_command_args(command, &parsed_body)?;
    scheduler_bridge::dispatch_json(config, &args)
}

pub(crate) fn scheduler_command_args(command: &str, body: &Value) -> Result<Vec<String>, String> {
    let mut args = vec![command.to_string()];
    match command {
        "enqueue" => {
            push_optional_flag(
                &mut args,
                "run-id",
                body_string_alias(body, "run_id", "runId"),
            );
            push_required_flag(
                &mut args,
                "request-id",
                body_string_alias(body, "request_id", "requestId"),
            )?;
            push_required_flag(
                &mut args,
                "scope-key",
                body_string_alias(body, "scope_key", "scopeKey"),
            )?;
            let request_id = body_string_alias(body, "request_id", "requestId").unwrap_or_default();
            let run_id = body_string_alias(body, "run_id", "runId").unwrap_or_default();
            push_value_flag(
                &mut args,
                "idempotency-key",
                body_string_alias(body, "idempotency_key", "idempotencyKey")
                    .unwrap_or_else(|| first_non_empty(&[request_id.as_str(), run_id.as_str()])),
            );
            push_value_flag(
                &mut args,
                "task-type",
                body_string_alias(body, "task_type", "taskType")
                    .unwrap_or_else(|| "paid_ai".to_string()),
            );
            push_payload_flag(&mut args, body)?;
            push_optional_flag(
                &mut args,
                "project-id",
                body_string_alias(body, "project_id", "projectId"),
            );
            push_optional_flag(
                &mut args,
                "device-id",
                body_string_alias(body, "device_id", "deviceId"),
            );
            push_optional_i32_flag(&mut args, "priority", body_i32(body, "priority"));
            push_optional_i64_flag(
                &mut args,
                "not-before-ms",
                body_i64_alias(body, "not_before_ms", "notBeforeMs"),
            );
        }
        "claim" => {
            push_optional_flag(
                &mut args,
                "run-id",
                body_string_alias(body, "run_id", "runId"),
            );
            push_required_flag(
                &mut args,
                "request-id",
                body_string_alias(body, "request_id", "requestId"),
            )?;
            push_required_flag(
                &mut args,
                "scope-key",
                body_string_alias(body, "scope_key", "scopeKey"),
            )?;
            let request_id = body_string_alias(body, "request_id", "requestId").unwrap_or_default();
            let run_id = body_string_alias(body, "run_id", "runId").unwrap_or_default();
            push_value_flag(
                &mut args,
                "idempotency-key",
                body_string_alias(body, "idempotency_key", "idempotencyKey")
                    .unwrap_or_else(|| first_non_empty(&[request_id.as_str(), run_id.as_str()])),
            );
            push_value_flag(
                &mut args,
                "task-type",
                body_string_alias(body, "task_type", "taskType")
                    .unwrap_or_else(|| "paid_ai".to_string()),
            );
            push_required_flag(
                &mut args,
                "lease-owner",
                body_string_alias(body, "lease_owner", "leaseOwner"),
            )?;
            push_value_flag(
                &mut args,
                "lease-duration-ms",
                body_u64_alias(body, "lease_duration_ms", "leaseDurationMs")
                    .unwrap_or(30_000)
                    .to_string(),
            );
            push_payload_flag(&mut args, body)?;
            push_optional_flag(
                &mut args,
                "project-id",
                body_string_alias(body, "project_id", "projectId"),
            );
            push_optional_flag(
                &mut args,
                "device-id",
                body_string_alias(body, "device_id", "deviceId"),
            );
            push_optional_i32_flag(&mut args, "priority", body_i32(body, "priority"));
            push_optional_i64_flag(
                &mut args,
                "not-before-ms",
                body_i64_alias(body, "not_before_ms", "notBeforeMs"),
            );
        }
        "acquire-run" => {
            push_required_flag(
                &mut args,
                "run-id",
                body_string_alias(body, "run_id", "runId"),
            )?;
            push_required_flag(
                &mut args,
                "lease-owner",
                body_string_alias(body, "lease_owner", "leaseOwner"),
            )?;
            push_value_flag(
                &mut args,
                "lease-duration-ms",
                body_u64_alias(body, "lease_duration_ms", "leaseDurationMs")
                    .unwrap_or(30_000)
                    .to_string(),
            );
        }
        "release" => {
            push_required_flag(
                &mut args,
                "run-id",
                body_string_alias(body, "run_id", "runId"),
            )?;
            push_required_flag(
                &mut args,
                "lease-token",
                body_string_alias(body, "lease_token", "leaseToken"),
            )?;
            push_value_flag(
                &mut args,
                "outcome",
                body_string(body, "outcome").unwrap_or_else(|| "completed".to_string()),
            );
            push_optional_flag(
                &mut args,
                "error-code",
                body_string_alias(body, "error_code", "errorCode"),
            );
            push_optional_flag(
                &mut args,
                "error-message",
                body_string_alias(body, "error_message", "errorMessage"),
            );
            push_optional_i64_flag(
                &mut args,
                "not-before-ms",
                body_i64_alias(body, "not_before_ms", "notBeforeMs"),
            );
        }
        "cancel" => {
            push_required_flag(
                &mut args,
                "run-id",
                body_string_alias(body, "run_id", "runId"),
            )?;
            push_value_flag(
                &mut args,
                "reason",
                body_string(body, "reason").unwrap_or_else(|| "canceled".to_string()),
            );
        }
        _ => return Err(format!("unsupported scheduler command: {command}")),
    }
    Ok(args)
}
