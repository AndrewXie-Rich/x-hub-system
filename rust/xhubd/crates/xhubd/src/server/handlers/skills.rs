use std::path::PathBuf;

use serde_json::Value;
use xhub_core::{json_escape, HubConfig};

use crate::server::handlers::health::cached_skills_catalog;
use crate::server::parse::{
    body_or_query_i64_in_range, body_or_query_string, body_or_query_usize_in_range,
    merge_skills_preflight_query, parse_optional_json_body, query_param,
};
use crate::server::state::HubState;
use crate::skills_bridge;

pub(crate) fn skills_catalog_http_json(state: &HubState, query: &str) -> (&'static str, String) {
    let config = &state.config;
    let skills_dir = query_param(query, "skills_dir")
        .or_else(|| query_param(query, "skillsDir"))
        .map(PathBuf::from)
        .unwrap_or_else(|| skills_bridge::skills_dir_from_env(config));
    let catalog = cached_skills_catalog(state, skills_dir);
    match skills_bridge::catalog_json_from_catalog(&catalog) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"skills_catalog_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn skills_readiness_http_json(state: &HubState, query: &str) -> (&'static str, String) {
    let config = &state.config;
    let skills_dir = query_param(query, "skills_dir")
        .or_else(|| query_param(query, "skillsDir"))
        .map(PathBuf::from)
        .unwrap_or_else(|| skills_bridge::skills_dir_from_env(config));
    let catalog = cached_skills_catalog(state, skills_dir);
    match skills_bridge::readiness_json_from_catalog(&catalog) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"skills_readiness_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn skills_policy_readiness_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    let parsed = parse_optional_json_body(body);
    let parsed = match parsed {
        Ok(value) => value,
        Err(err) => {
            return (
                "400 Bad Request",
                format!(
                    "{{\"ok\":false,\"error\":\"invalid_skills_policy_readiness_json\",\"message\":\"{}\"}}\n",
                    json_escape(&err)
                ),
            )
        }
    };
    let max_preflight_audit_rows = body_or_query_i64_in_range(
        &parsed,
        query,
        "max_preflight_audit_rows",
        "maxPreflightAuditRows",
        100_000,
        1,
        10_000_000,
    );
    let max_policy_event_rows = body_or_query_i64_in_range(
        &parsed,
        query,
        "max_policy_event_rows",
        "maxPolicyEventRows",
        100_000,
        1,
        10_000_000,
    );
    match skills_bridge::policy_store_readiness_json_from_parts(
        config,
        max_preflight_audit_rows,
        max_policy_event_rows,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"skills_policy_readiness_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn skills_pin_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    let parsed = parse_optional_json_body(body);
    let parsed = match parsed {
        Ok(value) => value,
        Err(err) => {
            return (
                "400 Bad Request",
                format!(
                    "{{\"ok\":false,\"error\":\"invalid_skills_pin_json\",\"message\":\"{}\"}}\n",
                    json_escape(&err)
                ),
            )
        }
    };
    match skills_bridge::pin_json_from_parts(
        config,
        body_or_query_string(&parsed, query, "scope_key", "scopeKey")
            .unwrap_or_else(|| "default".to_string()),
        body_or_query_string(&parsed, query, "skill_id", "skillId").unwrap_or_default(),
        body_or_query_string(&parsed, query, "pinned_by", "pinnedBy")
            .or_else(|| body_or_query_string(&parsed, query, "actor", "actor"))
            .unwrap_or_else(|| "rust_hub_operator".to_string()),
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"skills_pin_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn skills_grant_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    let parsed = parse_optional_json_body(body);
    let parsed = match parsed {
        Ok(value) => value,
        Err(err) => {
            return (
                "400 Bad Request",
                format!(
                    "{{\"ok\":false,\"error\":\"invalid_skills_grant_json\",\"message\":\"{}\"}}\n",
                    json_escape(&err)
                ),
            )
        }
    };
    match skills_bridge::grant_json_from_parts(
        config,
        body_or_query_string(&parsed, query, "scope_key", "scopeKey")
            .unwrap_or_else(|| "default".to_string()),
        body_or_query_string(&parsed, query, "skill_id", "skillId").unwrap_or_default(),
        body_or_query_string(&parsed, query, "capability", "capability").unwrap_or_default(),
        body_or_query_string(&parsed, query, "granted_by", "grantedBy")
            .or_else(|| body_or_query_string(&parsed, query, "actor", "actor"))
            .unwrap_or_else(|| "rust_hub_operator".to_string()),
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"skills_grant_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn skills_unpin_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    let parsed = parse_optional_json_body(body);
    let parsed = match parsed {
        Ok(value) => value,
        Err(err) => {
            return (
                "400 Bad Request",
                format!(
                    "{{\"ok\":false,\"error\":\"invalid_skills_unpin_json\",\"message\":\"{}\"}}\n",
                    json_escape(&err)
                ),
            )
        }
    };
    match skills_bridge::unpin_json_from_parts(
        config,
        body_or_query_string(&parsed, query, "scope_key", "scopeKey")
            .unwrap_or_else(|| "default".to_string()),
        body_or_query_string(&parsed, query, "skill_id", "skillId").unwrap_or_default(),
        body_or_query_string(&parsed, query, "revoked_by", "revokedBy")
            .or_else(|| body_or_query_string(&parsed, query, "actor", "actor"))
            .unwrap_or_else(|| "rust_hub_operator".to_string()),
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"skills_unpin_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn skills_revoke_grant_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    let parsed = parse_optional_json_body(body);
    let parsed = match parsed {
        Ok(value) => value,
        Err(err) => {
            return (
                "400 Bad Request",
                format!(
                    "{{\"ok\":false,\"error\":\"invalid_skills_revoke_grant_json\",\"message\":\"{}\"}}\n",
                    json_escape(&err)
                ),
            )
        }
    };
    match skills_bridge::revoke_grant_json_from_parts(
        config,
        body_or_query_string(&parsed, query, "scope_key", "scopeKey")
            .unwrap_or_else(|| "default".to_string()),
        body_or_query_string(&parsed, query, "skill_id", "skillId").unwrap_or_default(),
        body_or_query_string(&parsed, query, "capability", "capability").unwrap_or_default(),
        body_or_query_string(&parsed, query, "revoked_by", "revokedBy")
            .or_else(|| body_or_query_string(&parsed, query, "actor", "actor"))
            .unwrap_or_else(|| "rust_hub_operator".to_string()),
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"skills_revoke_grant_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn skills_policy_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    let parsed = parse_optional_json_body(body);
    let parsed = match parsed {
        Ok(value) => value,
        Err(err) => {
            return (
                "400 Bad Request",
                format!(
                "{{\"ok\":false,\"error\":\"invalid_skills_policy_json\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
            )
        }
    };
    match skills_bridge::policy_json_from_parts(
        config,
        body_or_query_string(&parsed, query, "scope_key", "scopeKey")
            .unwrap_or_else(|| "default".to_string()),
        body_or_query_string(&parsed, query, "skill_id", "skillId").unwrap_or_default(),
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"skills_policy_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn skills_policy_events_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    let parsed = parse_optional_json_body(body);
    let parsed = match parsed {
        Ok(value) => value,
        Err(err) => {
            return (
                "400 Bad Request",
                format!(
                    "{{\"ok\":false,\"error\":\"invalid_skills_policy_events_json\",\"message\":\"{}\"}}\n",
                    json_escape(&err)
                ),
            )
        }
    };
    let limit = body_or_query_usize_in_range(&parsed, query, "limit", "limit", 20, 1, 500);
    match skills_bridge::policy_events_json_from_parts(
        config,
        body_or_query_string(&parsed, query, "scope_key", "scopeKey"),
        body_or_query_string(&parsed, query, "skill_id", "skillId"),
        limit,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"skills_policy_events_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn skills_policy_events_prune_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    let parsed = parse_optional_json_body(body);
    let parsed = match parsed {
        Ok(value) => value,
        Err(err) => {
            return (
                "400 Bad Request",
                format!(
                    "{{\"ok\":false,\"error\":\"invalid_skills_policy_events_prune_json\",\"message\":\"{}\"}}\n",
                    json_escape(&err)
                ),
            )
        }
    };
    let max_rows =
        body_or_query_usize_in_range(&parsed, query, "max_rows", "maxRows", 10_000, 1, 1_000_000);
    match skills_bridge::policy_events_prune_json_from_parts(config, max_rows) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"skills_policy_events_prune_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn skills_audit_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    let parsed = parse_optional_json_body(body);
    let parsed = match parsed {
        Ok(value) => value,
        Err(err) => {
            return (
                "400 Bad Request",
                format!(
                    "{{\"ok\":false,\"error\":\"invalid_skills_audit_json\",\"message\":\"{}\"}}\n",
                    json_escape(&err)
                ),
            )
        }
    };
    let limit = body_or_query_usize_in_range(&parsed, query, "limit", "limit", 20, 1, 500);
    match skills_bridge::audit_json_from_parts(
        config,
        body_or_query_string(&parsed, query, "scope_key", "scopeKey"),
        body_or_query_string(&parsed, query, "skill_id", "skillId"),
        limit,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"skills_audit_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn skills_audit_prune_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    let parsed = parse_optional_json_body(body);
    let parsed = match parsed {
        Ok(value) => value,
        Err(err) => return (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"invalid_skills_audit_prune_json\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    };
    let max_rows =
        body_or_query_usize_in_range(&parsed, query, "max_rows", "maxRows", 10_000, 1, 1_000_000);
    match skills_bridge::audit_prune_json_from_parts(config, max_rows) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"skills_audit_prune_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn skills_preflight_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    let mut parsed = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        match serde_json::from_str::<Value>(body) {
            Ok(value) => value,
            Err(err) => {
                return (
                    "400 Bad Request",
                    format!(
                        "{{\"ok\":false,\"error\":\"invalid_skills_preflight_json\",\"message\":\"{}\"}}\n",
                        json_escape(&err.to_string())
                    ),
                )
            }
        }
    };
    merge_skills_preflight_query(&mut parsed, query);
    match skills_bridge::preflight_json_from_value(config, parsed) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"skills_preflight_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn skills_execute_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    let mut parsed = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        match serde_json::from_str::<Value>(body) {
            Ok(value) => value,
            Err(err) => {
                return (
                    "400 Bad Request",
                    format!(
                        "{{\"ok\":false,\"error\":\"invalid_skills_execute_json\",\"message\":\"{}\"}}\n",
                        json_escape(&err.to_string())
                    ),
                )
            }
        }
    };
    merge_skills_preflight_query(&mut parsed, query);
    match skills_bridge::execute_json_from_value(config, parsed) {
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
                "{{\"ok\":false,\"error\":\"skills_execute_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}
