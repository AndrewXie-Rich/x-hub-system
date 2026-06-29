use serde_json::json;
use xhub_core::HubConfig;

use super::cli::object_index_rebuild_cli_json;
use super::gate::evaluate_memory_policy_json;
use super::projection::memory_gateway_prepare_json_from_value;
use super::shared::{
    parse_json_body, percent_decode, query_bool, HttpJsonError, MEMORY_GATEWAY_PREPARE_SCHEMA,
    MEMORY_OBJECT_HISTORY_SCHEMA, MEMORY_OBJECT_RESULT_SCHEMA,
    MEMORY_PROJECT_CANONICAL_SYNC_SCHEMA, MEMORY_WRITEBACK_CANDIDATE_EXTRACT_SCHEMA,
    MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
};
use super::write::candidate::{
    create_writeback_candidate_json_from_body, list_writeback_candidates_json,
    transition_memory_object_candidate_json, writeback_candidate_extract_json_from_value,
};
use super::write::canonical::project_canonical_sync_json_from_value;
use super::write::object::{
    create_memory_object_json_from_body, get_memory_object_json, list_memory_objects_json,
    memory_object_history_json,
};

pub fn object_collection_http_json(
    config: &HubConfig,
    method: &str,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    match method {
        "POST" => match create_memory_object_json_from_body(config, body) {
            Ok(body) => ("200 OK", format!("{body}\n")),
            Err(HttpJsonError { status, body }) => (status, format!("{body}\n")),
        },
        "GET" => match list_memory_objects_json(config, query) {
            Ok(body) => ("200 OK", format!("{body}\n")),
            Err(HttpJsonError { status, body }) => (status, format!("{body}\n")),
        },
        _ => (
            "405 Method Not Allowed",
            json!({
                "schema_version": MEMORY_OBJECT_RESULT_SCHEMA,
                "ok": false,
                "status": "error",
                "error_code": "method_not_allowed",
            })
            .to_string()
                + "\n",
        ),
    }
}

pub fn object_item_http_json(
    config: &HubConfig,
    route_path: &str,
    method: &str,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    let Some(suffix) = route_path.strip_prefix("/memory/objects/") else {
        return (
            "404 Not Found",
            json!({
                "schema_version": MEMORY_OBJECT_RESULT_SCHEMA,
                "ok": false,
                "status": "not_found",
                "error_code": "memory_object_route_not_found",
            })
            .to_string()
                + "\n",
        );
    };
    let (memory_id, action) = suffix.split_once('/').unwrap_or((suffix, ""));
    let memory_id = percent_decode(memory_id).unwrap_or_else(|_| memory_id.to_string());
    if action == "history" {
        if method != "GET" {
            return (
                "405 Method Not Allowed",
                json!({
                    "schema_version": MEMORY_OBJECT_HISTORY_SCHEMA,
                    "ok": false,
                    "status": "error",
                    "error_code": "method_not_allowed",
                    "memory_id": memory_id,
                })
                .to_string()
                    + "\n",
            );
        }
        return match memory_object_history_json(config, &memory_id, query) {
            Ok(body) => ("200 OK", format!("{body}\n")),
            Err(HttpJsonError { status, body }) => (status, format!("{body}\n")),
        };
    }
    if matches!(action, "approve" | "reject") {
        if method != "POST" {
            return (
                "405 Method Not Allowed",
                json!({
                    "schema_version": MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
                    "ok": false,
                    "status": "error",
                    "error_code": "method_not_allowed",
                    "memory_id": memory_id,
                    "action": action,
                })
                .to_string()
                    + "\n",
            );
        }
        return match transition_memory_object_candidate_json(config, &memory_id, action, body) {
            Ok(body) => ("200 OK", format!("{body}\n")),
            Err(HttpJsonError { status, body }) => (status, format!("{body}\n")),
        };
    }
    if !action.is_empty() {
        return (
            "404 Not Found",
            json!({
                "schema_version": MEMORY_OBJECT_RESULT_SCHEMA,
                "ok": false,
                "status": "not_found",
                "error_code": "memory_object_action_not_implemented",
                "memory_id": memory_id,
                "action": action,
                "supported_actions": ["history", "approve", "reject"],
            })
            .to_string()
                + "\n",
        );
    }
    match method {
        "GET" => match get_memory_object_json(config, &memory_id) {
            Ok(body) => ("200 OK", format!("{body}\n")),
            Err(HttpJsonError { status, body }) => (status, format!("{body}\n")),
        },
        _ => (
            "501 Not Implemented",
            json!({
                "schema_version": MEMORY_OBJECT_RESULT_SCHEMA,
                "ok": false,
                "status": "not_implemented",
                "error_code": "memory_object_mutation_not_implemented_in_first_slice",
                "memory_id": memory_id,
                "supported_now": ["GET", "GET /history"],
            })
            .to_string()
                + "\n",
        ),
    }
}

pub fn writeback_candidates_http_json(
    config: &HubConfig,
    route_path: &str,
    method: &str,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    let suffix = route_path
        .strip_prefix("/memory/writeback/candidates")
        .unwrap_or_default()
        .trim_start_matches('/');
    if suffix.is_empty() {
        return match method {
            "POST" => match create_writeback_candidate_json_from_body(config, body) {
                Ok(body) => ("200 OK", format!("{body}\n")),
                Err(HttpJsonError { status, body }) => (status, format!("{body}\n")),
            },
            "GET" => match list_writeback_candidates_json(config, query) {
                Ok(body) => ("200 OK", format!("{body}\n")),
                Err(HttpJsonError { status, body }) => (status, format!("{body}\n")),
            },
            _ => (
                "405 Method Not Allowed",
                json!({
                    "schema_version": MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
                    "ok": false,
                    "status": "error",
                    "error_code": "method_not_allowed",
                })
                .to_string()
                    + "\n",
            ),
        };
    }
    if matches!(suffix, "extract" | "extract-from-delta" | "axmemory-delta") {
        if method != "POST" {
            return (
                "405 Method Not Allowed",
                json!({
                    "schema_version": MEMORY_WRITEBACK_CANDIDATE_EXTRACT_SCHEMA,
                    "ok": false,
                    "status": "error",
                    "error_code": "method_not_allowed",
                })
                .to_string()
                    + "\n",
            );
        }
        let parsed = match parse_json_body(body) {
            Ok(value) => value,
            Err(err) => return (err.status, format!("{}\n", err.body)),
        };
        let apply = query_bool(query, "apply", true)
            && !query_bool(query, "dry_run", false)
            && !query_bool(query, "dryRun", false);
        return match writeback_candidate_extract_json_from_value(config, &parsed, apply) {
            Ok(body) => ("200 OK", format!("{body}\n")),
            Err(HttpJsonError { status, body }) => (status, format!("{body}\n")),
        };
    }
    let (memory_id, action) = suffix.split_once('/').unwrap_or((suffix, ""));
    let memory_id = percent_decode(memory_id).unwrap_or_else(|_| memory_id.to_string());
    if !matches!(action, "approve" | "reject") {
        return (
            "404 Not Found",
            json!({
                "schema_version": MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
                "ok": false,
                "status": "not_found",
                "error_code": "memory_writeback_candidate_action_not_found",
                "memory_id": memory_id,
                "action": action,
                "supported_actions": ["approve", "reject"],
            })
            .to_string()
                + "\n",
        );
    }
    if method != "POST" {
        return (
            "405 Method Not Allowed",
            json!({
                "schema_version": MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
                "ok": false,
                "status": "error",
                "error_code": "method_not_allowed",
                "memory_id": memory_id,
                "action": action,
            })
            .to_string()
                + "\n",
        );
    }
    match transition_memory_object_candidate_json(config, &memory_id, action, body) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(HttpJsonError { status, body }) => (status, format!("{body}\n")),
    }
}

pub fn object_index_rebuild_http_json(config: &HubConfig, method: &str) -> (&'static str, String) {
    if method != "POST" {
        return (
            "405 Method Not Allowed",
            json!({
                "schema_version": "xhub.memory.object_index_rebuild.v1",
                "ok": false,
                "status": "error",
                "error_code": "method_not_allowed",
            })
            .to_string()
                + "\n",
        );
    }
    match object_index_rebuild_cli_json(config) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "500 Internal Server Error",
            json!({
                "schema_version": "xhub.memory.object_index_rebuild.v1",
                "ok": false,
                "status": "error",
                "error_code": "memory_object_index_rebuild_failed",
                "message": err,
                "production_authority_change": false,
            })
            .to_string()
                + "\n",
        ),
    }
}

pub fn policy_evaluate_http_json(body: &str) -> (&'static str, String) {
    let parsed = match parse_json_body(body) {
        Ok(value) => value,
        Err(err) => return (err.status, format!("{}\n", err.body)),
    };
    let result = evaluate_memory_policy_json(&parsed);
    ("200 OK", format!("{result}\n"))
}

pub fn project_canonical_sync_http_json(
    config: &HubConfig,
    method: &str,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    if method != "POST" {
        return (
            "405 Method Not Allowed",
            json!({
                "schema_version": MEMORY_PROJECT_CANONICAL_SYNC_SCHEMA,
                "ok": false,
                "status": "error",
                "error_code": "method_not_allowed",
            })
            .to_string()
                + "\n",
        );
    }
    let parsed = match parse_json_body(body) {
        Ok(value) => value,
        Err(err) => return (err.status, format!("{}\n", err.body)),
    };
    let apply = query_bool(query, "apply", false) && !query_bool(query, "dry_run", false);
    match project_canonical_sync_json_from_value(config, &parsed, apply) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(HttpJsonError { status, body }) => (status, format!("{body}\n")),
    }
}

pub fn memory_gateway_prepare_http_json(
    config: &HubConfig,
    method: &str,
    body: &str,
) -> (&'static str, String) {
    if method != "POST" {
        return (
            "405 Method Not Allowed",
            json!({
                "schema_version": MEMORY_GATEWAY_PREPARE_SCHEMA,
                "ok": false,
                "status": "error",
                "error_code": "method_not_allowed",
            })
            .to_string()
                + "\n",
        );
    }
    let parsed = match parse_json_body(body) {
        Ok(value) => value,
        Err(err) => return (err.status, format!("{}\n", err.body)),
    };
    match memory_gateway_prepare_json_from_value(config, &parsed) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(HttpJsonError { status, body }) => (status, format!("{body}\n")),
    }
}
