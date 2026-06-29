use super::*;
use serde_json::{json, Map, Value};

pub(super) fn quota_failure_backoff_ms(
    failure_count: u32,
    base_backoff_ms: u64,
    max_backoff_ms: u64,
) -> u64 {
    let base = base_backoff_ms.max(100);
    let max = max_backoff_ms.max(base);
    let mut delay = base;
    for _ in 1..failure_count.max(1) {
        delay = delay.saturating_mul(2).min(max);
    }
    delay.min(max)
}

pub(super) fn quota_managed_error_state(error_state: &Value) -> bool {
    let status = normalized_token(&json_string(error_state, "status"));
    let reason = normalized_token(
        &first_non_empty(&[
            &json_string(error_state, "reason_code"),
            &json_string(error_state, "last_error_code"),
        ])
        .unwrap_or_default(),
    );
    let retry_at_source = normalized_token(&json_string(error_state, "retry_at_source"));
    reason == "blocked_quota"
        || reason == "rate_limited"
        || retry_at_source == QUOTA_REFRESH_RETRY_SOURCE
        || status == "blocked_quota"
        || status == "rate_limited"
}

pub(super) fn auth_managed_error_state(error_state: &Value) -> bool {
    let status = normalized_token(&json_string(error_state, "status"));
    let reason = normalized_token(
        &first_non_empty(&[
            &json_string(error_state, "reason_code"),
            &json_string(error_state, "last_error_code"),
        ])
        .unwrap_or_default(),
    );
    let retry_at_source = normalized_token(&json_string(error_state, "retry_at_source"));
    retry_at_source == OAUTH_REFRESH_RETRY_SOURCE
        || matches!(
            status.as_str(),
            "auth_failed" | "blocked_auth" | "blocked_config"
        )
        || matches!(
            reason.as_str(),
            "auth_missing"
                | "auth_failed"
                | "blocked_auth"
                | "invalid_api_key"
                | "authentication_failed"
                | "missing_scope"
                | "scope_missing"
                | "token_expired"
                | "invalid_grant"
                | "invalid_client"
                | "unauthorized_client"
                | "access_denied"
                | "refresh_token_reused"
                | "missing_refresh_token"
                | "unsupported_refresh_schema"
                | "missing_oauth_client"
                | "missing_oauth_client_id"
                | "missing_oauth_client_secret"
                | "refresh_failed"
                | "refresh_request_failed"
                | "refresh_timeout"
        )
        || reason.starts_with("refresh_http_401")
        || reason.starts_with("refresh_http_403")
}

pub(super) fn normalized_error_state_object(error_state: &Value) -> Map<String, Value> {
    let status =
        non_empty_json_string(error_state, "status").unwrap_or_else(|| "healthy".to_string());
    let reason_code = first_non_empty(&[
        &json_string(error_state, "reason_code"),
        &json_string(error_state, "last_error_code"),
    ])
    .unwrap_or_default();
    let mut out = Map::new();
    out.insert("status".to_string(), Value::String(status));
    out.insert(
        "status_message".to_string(),
        Value::String(json_string(error_state, "status_message")),
    );
    out.insert("reason_code".to_string(), Value::String(reason_code));
    out.insert(
        "last_error_code".to_string(),
        Value::String(json_string(error_state, "last_error_code")),
    );
    out.insert(
        "last_error_at_ms".to_string(),
        json!(json_u64(error_state, "last_error_at_ms")),
    );
    out.insert(
        "next_retry_at_ms".to_string(),
        json!(json_u64(error_state, "next_retry_at_ms")),
    );
    out.insert(
        "retry_at_source".to_string(),
        Value::String(json_string(error_state, "retry_at_source")),
    );
    out.insert(
        "auto_disabled".to_string(),
        Value::Bool(json_bool(error_state, "auto_disabled")),
    );
    out
}

pub(super) fn normalized_refresh_state_object(refresh_state: &Value) -> Map<String, Value> {
    let status =
        non_empty_json_string(refresh_state, "status").unwrap_or_else(|| "idle".to_string());
    let mut out = Map::new();
    out.insert("status".to_string(), Value::String(status));
    out.insert(
        "last_attempt_at_ms".to_string(),
        json!(json_u64(refresh_state, "last_attempt_at_ms")),
    );
    out.insert(
        "last_success_at_ms".to_string(),
        json!(json_u64(refresh_state, "last_success_at_ms")),
    );
    out.insert(
        "next_refresh_at_ms".to_string(),
        json!(json_u64(refresh_state, "next_refresh_at_ms")),
    );
    out.insert(
        "failure_count".to_string(),
        json!(json_u64(refresh_state, "failure_count")),
    );
    out.insert(
        "last_error_code".to_string(),
        Value::String(json_string(refresh_state, "last_error_code")),
    );
    out.insert(
        "last_error_message".to_string(),
        Value::String(json_string(refresh_state, "last_error_message")),
    );
    out
}

pub(super) fn normalized_oauth_refresh_error_code(raw: &str) -> String {
    let token = normalized_token(raw);
    if token.is_empty() {
        return "refresh_failed".to_string();
    }
    if token == "401" || token == "403" {
        return format!("refresh_http_{token}");
    }
    if token == "408" || token == "504" {
        return "refresh_timeout".to_string();
    }
    if token.contains("refresh_token_reused") {
        return "refresh_token_reused".to_string();
    }
    if token.contains("invalid_grant") {
        return "invalid_grant".to_string();
    }
    if token.contains("timed out") || token.contains("timeout") || token.contains("etimedout") {
        return "refresh_timeout".to_string();
    }
    if token.contains("network")
        || token.contains("dns")
        || token.contains("econnrefused")
        || token.contains("econnreset")
        || token.contains("enotfound")
    {
        return "refresh_request_failed".to_string();
    }
    let mut out = String::new();
    let mut previous_underscore = false;
    for ch in token.chars() {
        let next = if ch.is_ascii_alphanumeric() {
            ch
        } else if ch == '_' {
            '_'
        } else {
            '_'
        };
        if next == '_' {
            if previous_underscore {
                continue;
            }
            previous_underscore = true;
        } else {
            previous_underscore = false;
        }
        out.push(next);
    }
    let normalized = out.trim_matches('_').to_string();
    if normalized.is_empty() {
        "refresh_failed".to_string()
    } else if normalized.starts_with("http_") {
        format!("refresh_{normalized}")
    } else {
        normalized
    }
}

pub(super) fn sanitized_status_message(raw: &str, fallback_code: &str) -> String {
    let fallback = first_non_empty(&[fallback_code, "refresh_failed"]).unwrap_or_default();
    let message = raw
        .split_whitespace()
        .collect::<Vec<&str>>()
        .join(" ")
        .trim()
        .to_string();
    if message.is_empty() {
        return fallback;
    }
    let lower = message.to_lowercase();
    if lower.contains("access_token")
        || lower.contains("refresh_token")
        || lower.contains("id_token")
        || lower.contains("authorization")
        || lower.contains("bearer ")
        || lower.contains("sk-")
        || lower.contains("session key")
    {
        return fallback;
    }
    if message.len() > 240 {
        let mut truncated = message.chars().take(240).collect::<String>();
        truncated.push_str("...");
        truncated
    } else {
        message
    }
}

pub(super) fn oauth_refresh_terminal_error(error_code: &str) -> bool {
    let code = normalized_token(error_code);
    matches!(
        code.as_str(),
        "invalid_grant"
            | "refresh_token_reused"
            | "invalid_client"
            | "unauthorized_client"
            | "access_denied"
            | "missing_refresh_token"
            | "unsupported_refresh_schema"
            | "missing_oauth_client"
            | "missing_oauth_client_id"
            | "missing_oauth_client_secret"
    ) || code.starts_with("refresh_http_401")
        || code.starts_with("refresh_http_403")
}

pub(super) fn oauth_refresh_error_status(error_code: &str) -> &'static str {
    let code = normalized_token(error_code);
    if matches!(
        code.as_str(),
        "missing_refresh_token"
            | "unsupported_refresh_schema"
            | "missing_oauth_client"
            | "missing_oauth_client_id"
            | "missing_oauth_client_secret"
    ) {
        return "blocked_config";
    }
    if matches!(
        code.as_str(),
        "invalid_grant"
            | "refresh_token_reused"
            | "invalid_client"
            | "unauthorized_client"
            | "access_denied"
    ) || code.starts_with("refresh_http_401")
        || code.starts_with("refresh_http_403")
    {
        return "blocked_auth";
    }
    if matches!(code.as_str(), "refresh_timeout" | "refresh_request_failed") {
        return "blocked_network";
    }
    "blocked_provider"
}

pub(super) fn normalized_quota_object(quota: &Value) -> Map<String, Value> {
    let mut out = Map::new();
    out.insert(
        "daily_token_cap".to_string(),
        json!(json_u64(quota, "daily_token_cap")),
    );
    out.insert(
        "daily_tokens_used".to_string(),
        json!(json_u64(quota, "daily_tokens_used")),
    );
    out.insert(
        "daily_tokens_remaining".to_string(),
        json!(json_u64(quota, "daily_tokens_remaining")),
    );
    out.insert(
        "total_tokens_used".to_string(),
        json!(json_u64(quota, "total_tokens_used")),
    );
    out.insert(
        "last_used_at_ms".to_string(),
        json!(json_u64(quota, "last_used_at_ms")),
    );
    out.insert(
        "last_error_at_ms".to_string(),
        json!(json_u64(quota, "last_error_at_ms")),
    );
    out.insert(
        "consecutive_errors".to_string(),
        json!(json_u64(quota, "consecutive_errors")),
    );
    out.insert(
        "cooldown_until_ms".to_string(),
        json!(json_u64(quota, "cooldown_until_ms")),
    );
    out.insert(
        "next_refresh_at_ms".to_string(),
        json!(json_u64(quota, "next_refresh_at_ms")),
    );
    if let Some(windows) = quota.get("usage_windows").filter(|value| value.is_array()) {
        out.insert("usage_windows".to_string(), windows.clone());
    }
    out
}
