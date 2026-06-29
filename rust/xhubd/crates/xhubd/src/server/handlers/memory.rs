use std::path::PathBuf;

use serde_json::Value;
use xhub_core::{json_escape, HubConfig};
use xhub_memory::{MemoryMode, MemoryRetrievalRequest};

use crate::memory_bridge;
use crate::memory_role_projection;
use crate::server::handlers::health::cached_memory_snapshot;
use crate::server::parse::{
    optional_query_bool_alias, optional_query_i64_alias, optional_query_usize_alias, query_param,
    query_param_list,
};
use crate::server::state::HubState;

pub(crate) fn memory_search_http_json(state: &HubState, query: &str) -> (&'static str, String) {
    let config = &state.config;
    let memory_dir = query_param(query, "memory_dir")
        .or_else(|| query_param(query, "memoryDir"))
        .map(PathBuf::from)
        .unwrap_or_else(|| memory_bridge::memory_dir_from_env(config));
    let snapshot = cached_memory_snapshot(state, memory_dir.clone());
    let mut request = MemoryRetrievalRequest::with_defaults(memory_dir);
    request.request_id = query_param(query, "request_id")
        .or_else(|| query_param(query, "requestId"))
        .unwrap_or_default();
    request.scope = query_param(query, "scope").unwrap_or_else(|| "current_project".to_string());
    request.mode = MemoryMode::from_str(
        query_param(query, "mode")
            .unwrap_or_else(|| "project_code".to_string())
            .as_str(),
    );
    request.project_id = query_param(query, "project_id")
        .or_else(|| query_param(query, "projectId"))
        .unwrap_or_default();
    request.query = query_param(query, "query").unwrap_or_default();
    request.latest_user = query_param(query, "latest_user")
        .or_else(|| query_param(query, "latestUser"))
        .unwrap_or_default();
    request.retrieval_kind = query_param(query, "retrieval_kind")
        .or_else(|| query_param(query, "retrievalKind"))
        .unwrap_or_else(|| "search".to_string());
    request.max_results = match optional_query_usize_alias(query, "max_results", "maxResults", 5) {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    request.max_snippet_chars =
        match optional_query_usize_alias(query, "max_snippet_chars", "maxSnippetChars", 480) {
            Ok(value) => value,
            Err(body) => return ("400 Bad Request", body),
        };
    request.requested_kinds = query_param_list(query, "requested_kinds")
        .or_else(|| query_param_list(query, "requestedKinds"))
        .unwrap_or_default();
    request.requested_layers = query_param_list(query, "requested_layers")
        .or_else(|| query_param_list(query, "requestedLayers"))
        .or_else(|| query_param_list(query, "layers"))
        .unwrap_or_default();
    request.explicit_refs = query_param_list(query, "explicit_refs")
        .or_else(|| query_param_list(query, "explicitRefs"))
        .unwrap_or_default();
    request.sensitivity_max = query_param(query, "sensitivity_max")
        .or_else(|| query_param(query, "sensitivityMax"))
        .unwrap_or_default();
    request.visibility = query_param(query, "visibility").unwrap_or_default();
    request.created_after_ms =
        match optional_query_i64_alias(query, "created_after_ms", "createdAfterMs", 0) {
            Ok(value) => value,
            Err(body) => return ("400 Bad Request", body),
        };
    request.updated_after_ms =
        match optional_query_i64_alias(query, "updated_after_ms", "updatedAfterMs", 0) {
            Ok(value) => value,
            Err(body) => return ("400 Bad Request", body),
        };
    request.explain = match optional_query_bool_alias(query, "explain", "explain", false) {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    request.audit_ref = query_param(query, "audit_ref")
        .or_else(|| query_param(query, "auditRef"))
        .unwrap_or_default();
    match memory_bridge::retrieve_json_from_request_with_config_and_snapshot(
        config, request, &snapshot,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"memory_search_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn memory_retrieve_http_json(
    state: &HubState,
    _query: &str,
    body: &str,
) -> (&'static str, String) {
    let config = &state.config;
    let parsed = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        match serde_json::from_str::<Value>(body) {
            Ok(value) => value,
            Err(err) => {
                return (
                    "400 Bad Request",
                    format!(
                        "{{\"ok\":false,\"error\":\"invalid_memory_retrieve_json\",\"message\":\"{}\"}}\n",
                        json_escape(&err.to_string())
                    ),
                )
            }
        }
    };
    let request = memory_bridge::retrieve_request_from_value(config, &parsed);
    let snapshot = cached_memory_snapshot(state, request.memory_dir.clone());
    match memory_bridge::retrieve_json_from_request_with_config_and_snapshot(
        config, request, &snapshot,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"memory_retrieve_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn memory_role_transcript_http_json(
    config: &HubConfig,
    query: &str,
) -> (&'static str, String) {
    let project_id = query_param(query, "project_id")
        .or_else(|| query_param(query, "projectId"))
        .unwrap_or_default();
    let thread_key = query_param(query, "thread_key")
        .or_else(|| query_param(query, "threadKey"))
        .unwrap_or_else(|| {
            if project_id.trim().is_empty() {
                String::new()
            } else {
                format!("xterminal_project_{}", project_id.trim())
            }
        });
    let limit = match optional_query_usize_alias(query, "limit", "limit", 50) {
        Ok(value) => value.clamp(1, 500),
        Err(body) => return ("400 Bad Request", body),
    };
    let include_content =
        match optional_query_bool_alias(query, "include_content", "includeContent", false) {
            Ok(value) => value,
            Err(body) => return ("400 Bad Request", body),
        };
    if project_id.trim().is_empty() || thread_key.trim().is_empty() {
        return (
            "400 Bad Request",
            "{\"ok\":false,\"error\":\"invalid_project_role_transcript_request\",\"message\":\"project_id and thread_key are required\"}\n".to_string(),
        );
    }
    match memory_role_projection::projection_json_from_parts(
        config,
        query_param(query, "device_id").or_else(|| query_param(query, "deviceId")),
        query_param(query, "app_id").or_else(|| query_param(query, "appId")),
        project_id,
        thread_key,
        limit,
        include_content,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) if err == "role_metadata_project_mismatch" => (
            "409 Conflict",
            "{\"ok\":false,\"error\":\"role_metadata_project_mismatch\"}\n".to_string(),
        ),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"project_role_transcript_projection_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn memory_write_http_json(config: &HubConfig, body: &str) -> (&'static str, String) {
    let parsed = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        match serde_json::from_str::<Value>(body) {
            Ok(value) => value,
            Err(err) => {
                return (
                    "400 Bad Request",
                    format!(
                    "{{\"ok\":false,\"error\":\"invalid_memory_write_json\",\"message\":\"{}\"}}\n",
                    json_escape(&err.to_string())
                ),
                )
            }
        }
    };
    match memory_bridge::write_json_from_value(config, &parsed) {
        Ok(body) => {
            let status = if body.contains("\"status\":\"denied\"") {
                "403 Forbidden"
            } else if body.contains("\"status\":\"error\"") {
                "500 Internal Server Error"
            } else {
                "200 OK"
            };
            (status, format!("{body}\n"))
        }
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"memory_write_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn memory_readiness_http_json(state: &HubState, query: &str) -> (&'static str, String) {
    let config = &state.config;
    let memory_dir = query_param(query, "memory_dir")
        .or_else(|| query_param(query, "memoryDir"))
        .map(PathBuf::from)
        .unwrap_or_else(|| memory_bridge::memory_dir_from_env(config));
    let snapshot = cached_memory_snapshot(state, memory_dir);
    match memory_bridge::readiness_json_from_snapshot_with_config(config, &snapshot) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"memory_readiness_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}
