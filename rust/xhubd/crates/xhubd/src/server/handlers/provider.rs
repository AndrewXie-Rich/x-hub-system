use std::path::PathBuf;

use serde_json::Value;
use xhub_core::{json_escape, now_ms, HubConfig};

use crate::provider_bridge;
use crate::server::handlers::evidence::maybe_attach_route_evidence;
use crate::server::parse::{
    body_bool, body_bool_alias, body_or_query_string, body_string, body_string_alias,
    body_string_list, body_u128, body_u64_alias, optional_query_bool_alias,
    optional_query_i64_alias, optional_query_u128_alias, optional_query_usize,
    parse_optional_json_body, query_param, query_param_list,
};

pub(crate) fn provider_route_http_json(config: &HubConfig, query: &str) -> (&'static str, String) {
    let model_id = match query_param(query, "model_id")
        .or_else(|| query_param(query, "modelId"))
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
    {
        Some(value) => value,
        None => {
            return (
                "400 Bad Request",
                "{\"ok\":false,\"error\":\"missing_model_id\"}\n".to_string(),
            )
        }
    };
    let provider = query_param(query, "provider").unwrap_or_default();
    let runtime_base_dir = query_param(query, "runtime_base_dir")
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let request_now_ms = match query_param(query, "now_ms").or_else(|| query_param(query, "nowMs"))
    {
        Some(value) if !value.trim().is_empty() => match value.trim().parse::<u128>() {
            Ok(parsed) => Some(parsed),
            Err(_) => {
                return (
                    "400 Bad Request",
                    "{\"ok\":false,\"error\":\"invalid_now_ms\"}\n".to_string(),
                )
            }
        },
        _ => None,
    };

    let body = match provider_bridge::route_json_from_parts(
        config,
        runtime_base_dir,
        model_id,
        provider,
        request_now_ms,
    ) {
        Ok(body) => body,
        Err(err) => {
            return (
                "400 Bad Request",
                format!(
                    "{{\"ok\":false,\"error\":\"provider_route_failed\",\"message\":\"{}\"}}\n",
                    json_escape(&err)
                ),
            )
        }
    };
    match maybe_attach_route_evidence(
        config,
        query,
        &Value::Null,
        "provider_route",
        body,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"provider_route_evidence_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn provider_pools_http_json(config: &HubConfig, query: &str) -> (&'static str, String) {
    let runtime_base_dir = query_param(query, "runtime_base_dir")
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let provider = query_param(query, "provider").unwrap_or_default();
    let model_id = query_param(query, "model_id")
        .or_else(|| query_param(query, "modelId"))
        .unwrap_or_default();
    let include_members =
        match optional_query_bool_alias(query, "include_members", "includeMembers", true) {
            Ok(value) => value,
            Err(body) => return ("400 Bad Request", body),
        };
    let request_now_ms = match optional_query_u128_alias(query, "now_ms", "nowMs") {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };

    match provider_bridge::pools_json_from_parts(
        config,
        runtime_base_dir,
        provider,
        model_id,
        include_members,
        request_now_ms,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"provider_pools_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn provider_runtime_snapshot_http_json(
    config: &HubConfig,
    query: &str,
) -> (&'static str, String) {
    let runtime_base_dir = query_param(query, "runtime_base_dir")
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let provider = query_param(query, "provider").unwrap_or_default();

    match provider_bridge::runtime_snapshot_json_from_parts(config, runtime_base_dir, provider) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"provider_runtime_snapshot_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn provider_import_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    let parsed_body = match parse_optional_json_body(body) {
        Ok(value) => value,
        Err(err) => {
            return (
                "400 Bad Request",
                format!(
                    "{{\"ok\":false,\"error\":\"invalid_json\",\"message\":\"{}\"}}\n",
                    json_escape(&err)
                ),
            )
        }
    };
    let runtime_base_dir =
        body_or_query_string(&parsed_body, query, "runtime_base_dir", "runtimeBaseDir")
            .map(PathBuf::from);
    let auth_dir = body_or_query_string(&parsed_body, query, "auth_dir", "authDir")
        .or_else(|| body_or_query_string(&parsed_body, query, "auth_path", "authPath"))
        .unwrap_or_default();
    let config_path =
        body_or_query_string(&parsed_body, query, "config_path", "configPath").unwrap_or_default();
    let imported_at_ms = body_u64_alias(&parsed_body, "now_ms", "nowMs")
        .or_else(|| query_param(query, "now_ms").and_then(|value| value.parse::<u64>().ok()))
        .or_else(|| query_param(query, "nowMs").and_then(|value| value.parse::<u64>().ok()));

    match provider_bridge::import_json_from_parts(
        config,
        runtime_base_dir,
        auth_dir,
        config_path,
        imported_at_ms,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"provider_import_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn provider_openai_quota_apply_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    match provider_openai_quota_apply_http_body(config, query, body) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"provider_openai_quota_apply_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn provider_openai_quota_plan_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    match provider_openai_quota_plan_http_body(config, query, body) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"provider_openai_quota_plan_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn provider_openai_quota_plan_http_body(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> Result<String, String> {
    let parsed_body = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        serde_json::from_str::<Value>(body)
            .map_err(|err| format!("invalid openai quota plan request json: {err}"))?
    };
    let runtime_base_dir = body_string(&parsed_body, "runtime_base_dir")
        .or_else(|| body_string(&parsed_body, "runtimeBaseDir"))
        .or_else(|| query_param(query, "runtime_base_dir"))
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let now = body_u64_alias(&parsed_body, "now_ms", "nowMs")
        .or_else(|| query_param(query, "now_ms").and_then(|value| value.parse::<u64>().ok()))
        .or_else(|| query_param(query, "nowMs").and_then(|value| value.parse::<u64>().ok()))
        .unwrap_or_else(|| now_ms().min(u64::MAX as u128) as u64);
    let include_skipped = body_bool_alias(&parsed_body, "include_skipped", "includeSkipped")
        .or_else(|| {
            optional_query_bool_alias(query, "include_skipped", "includeSkipped", false).ok()
        })
        .unwrap_or(false);
    let mut in_flight_account_keys = body_string_list(&parsed_body, "in_flight_account_keys");
    in_flight_account_keys.extend(body_string_list(&parsed_body, "inFlightAccountKeys"));
    if let Some(keys) = query_param_list(query, "in_flight_account_keys")
        .or_else(|| query_param_list(query, "inFlightAccountKeys"))
    {
        in_flight_account_keys.extend(keys);
    }
    in_flight_account_keys.sort();
    in_flight_account_keys.dedup();
    provider_bridge::plan_openai_quota_json_from_parts(
        config,
        runtime_base_dir,
        xhub_provider::OpenAIQuotaRefreshPlanOptions {
            now_ms: now,
            include_skipped,
            in_flight_account_keys,
        },
    )
}

pub(crate) fn provider_openai_quota_apply_http_body(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> Result<String, String> {
    let parsed_body = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        serde_json::from_str::<Value>(body)
            .map_err(|err| format!("invalid openai quota apply request json: {err}"))?
    };
    let usage = parsed_body
        .get("usage")
        .or_else(|| parsed_body.get("usage_payload"))
        .or_else(|| parsed_body.get("usagePayload"))
        .cloned()
        .ok_or_else(|| "provider openai quota apply requires usage".to_string())?;
    let runtime_base_dir = body_string(&parsed_body, "runtime_base_dir")
        .or_else(|| body_string(&parsed_body, "runtimeBaseDir"))
        .or_else(|| query_param(query, "runtime_base_dir"))
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let refreshed_at_ms = body_u64_alias(&parsed_body, "refreshed_at_ms", "refreshedAtMs")
        .or_else(|| body_u64_alias(&parsed_body, "now_ms", "nowMs"))
        .or_else(|| query_param(query, "now_ms").and_then(|value| value.parse::<u64>().ok()))
        .or_else(|| query_param(query, "nowMs").and_then(|value| value.parse::<u64>().ok()))
        .unwrap_or_else(|| now_ms().min(u64::MAX as u128) as u64);
    let options = xhub_provider::OpenAIQuotaApplyOptions {
        account_key: body_string_alias(&parsed_body, "account_key", "accountKey")
            .or_else(|| query_param(query, "account_key"))
            .or_else(|| query_param(query, "accountKey"))
            .ok_or_else(|| "provider openai quota apply requires account_key".to_string())?,
        refreshed_at_ms,
        success_interval_ms: body_u64_alias(
            &parsed_body,
            "success_interval_ms",
            "successIntervalMs",
        )
        .or_else(|| {
            query_param(query, "success_interval_ms").and_then(|value| value.parse::<u64>().ok())
        })
        .or_else(|| {
            query_param(query, "successIntervalMs").and_then(|value| value.parse::<u64>().ok())
        })
        .unwrap_or(5 * 60_000),
        high_water_interval_ms: body_u64_alias(
            &parsed_body,
            "high_water_interval_ms",
            "highWaterIntervalMs",
        )
        .or_else(|| {
            query_param(query, "high_water_interval_ms").and_then(|value| value.parse::<u64>().ok())
        })
        .or_else(|| {
            query_param(query, "highWaterIntervalMs").and_then(|value| value.parse::<u64>().ok())
        })
        .unwrap_or(60_000),
        account_id: body_string_alias(&parsed_body, "account_id", "accountId")
            .or_else(|| query_param(query, "account_id"))
            .or_else(|| query_param(query, "accountId"))
            .unwrap_or_default(),
        oauth_source_key: body_string_alias(&parsed_body, "oauth_source_key", "oauthSourceKey")
            .or_else(|| query_param(query, "oauth_source_key"))
            .or_else(|| query_param(query, "oauthSourceKey"))
            .unwrap_or_default(),
    };

    provider_bridge::apply_openai_quota_json_from_parts(config, runtime_base_dir, usage, options)
}

pub(crate) fn provider_openai_quota_failure_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    match provider_openai_quota_failure_http_body(config, query, body) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"provider_openai_quota_failure_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn provider_openai_quota_failure_http_body(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> Result<String, String> {
    let parsed_body = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        serde_json::from_str::<Value>(body)
            .map_err(|err| format!("invalid openai quota failure request json: {err}"))?
    };
    let runtime_base_dir = body_string(&parsed_body, "runtime_base_dir")
        .or_else(|| body_string(&parsed_body, "runtimeBaseDir"))
        .or_else(|| query_param(query, "runtime_base_dir"))
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let options = xhub_provider::OpenAIQuotaRefreshFailureOptions {
        account_key: body_string_alias(&parsed_body, "account_key", "accountKey")
            .or_else(|| query_param(query, "account_key"))
            .or_else(|| query_param(query, "accountKey"))
            .ok_or_else(|| "provider openai quota failure requires account_key".to_string())?,
        failed_at_ms: body_u64_alias(&parsed_body, "failed_at_ms", "failedAtMs")
            .or_else(|| body_u64_alias(&parsed_body, "now_ms", "nowMs"))
            .or_else(|| {
                query_param(query, "failed_at_ms").and_then(|value| value.parse::<u64>().ok())
            })
            .or_else(|| {
                query_param(query, "failedAtMs").and_then(|value| value.parse::<u64>().ok())
            })
            .or_else(|| query_param(query, "now_ms").and_then(|value| value.parse::<u64>().ok()))
            .or_else(|| query_param(query, "nowMs").and_then(|value| value.parse::<u64>().ok()))
            .unwrap_or_else(|| now_ms().min(u64::MAX as u128) as u64),
        base_failure_backoff_ms: body_u64_alias(
            &parsed_body,
            "base_failure_backoff_ms",
            "baseFailureBackoffMs",
        )
        .or_else(|| {
            query_param(query, "base_failure_backoff_ms")
                .and_then(|value| value.parse::<u64>().ok())
        })
        .or_else(|| {
            query_param(query, "baseFailureBackoffMs").and_then(|value| value.parse::<u64>().ok())
        })
        .unwrap_or(60_000),
        max_failure_backoff_ms: body_u64_alias(
            &parsed_body,
            "max_failure_backoff_ms",
            "maxFailureBackoffMs",
        )
        .or_else(|| {
            query_param(query, "max_failure_backoff_ms").and_then(|value| value.parse::<u64>().ok())
        })
        .or_else(|| {
            query_param(query, "maxFailureBackoffMs").and_then(|value| value.parse::<u64>().ok())
        })
        .unwrap_or(15 * 60_000),
        error_code: body_string_alias(&parsed_body, "error_code", "errorCode")
            .or_else(|| query_param(query, "error_code"))
            .or_else(|| query_param(query, "errorCode"))
            .unwrap_or_default(),
        error_message: body_string_alias(&parsed_body, "error_message", "errorMessage")
            .or_else(|| query_param(query, "error_message"))
            .or_else(|| query_param(query, "errorMessage"))
            .unwrap_or_default(),
    };
    provider_bridge::record_openai_quota_failure_json_from_parts(config, runtime_base_dir, options)
}

pub(crate) fn provider_oauth_refresh_apply_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    match provider_oauth_refresh_apply_http_body(config, query, body) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"provider_oauth_refresh_apply_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn provider_oauth_refresh_apply_http_body(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> Result<String, String> {
    let parsed_body = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        serde_json::from_str::<Value>(body)
            .map_err(|err| format!("invalid oauth refresh apply request json: {err}"))?
    };
    let runtime_base_dir = body_string(&parsed_body, "runtime_base_dir")
        .or_else(|| body_string(&parsed_body, "runtimeBaseDir"))
        .or_else(|| query_param(query, "runtime_base_dir"))
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let refreshed_at_ms = body_u64_alias(&parsed_body, "refreshed_at_ms", "refreshedAtMs")
        .or_else(|| body_u64_alias(&parsed_body, "now_ms", "nowMs"))
        .or_else(|| {
            query_param(query, "refreshed_at_ms").and_then(|value| value.parse::<u64>().ok())
        })
        .or_else(|| query_param(query, "refreshedAtMs").and_then(|value| value.parse::<u64>().ok()))
        .or_else(|| query_param(query, "now_ms").and_then(|value| value.parse::<u64>().ok()))
        .or_else(|| query_param(query, "nowMs").and_then(|value| value.parse::<u64>().ok()))
        .unwrap_or_else(|| now_ms().min(u64::MAX as u128) as u64);
    let options = xhub_provider::ProviderOAuthRefreshApplyOptions {
        account_key: body_string_alias(&parsed_body, "account_key", "accountKey")
            .or_else(|| query_param(query, "account_key"))
            .or_else(|| query_param(query, "accountKey"))
            .ok_or_else(|| "provider oauth refresh apply requires account_key".to_string())?,
        refreshed_at_ms,
        access_token: body_string_alias(&parsed_body, "access_token", "accessToken")
            .or_else(|| query_param(query, "access_token"))
            .or_else(|| query_param(query, "accessToken"))
            .ok_or_else(|| "provider oauth refresh apply requires access_token".to_string())?,
        refresh_token: body_string_alias(&parsed_body, "refresh_token", "refreshToken")
            .or_else(|| query_param(query, "refresh_token"))
            .or_else(|| query_param(query, "refreshToken"))
            .unwrap_or_default(),
        expires_at_ms: body_u64_alias(&parsed_body, "expires_at_ms", "expiresAtMs")
            .or_else(|| {
                query_param(query, "expires_at_ms").and_then(|value| value.parse::<u64>().ok())
            })
            .or_else(|| {
                query_param(query, "expiresAtMs").and_then(|value| value.parse::<u64>().ok())
            })
            .unwrap_or(0),
        account_id: body_string_alias(&parsed_body, "account_id", "accountId")
            .or_else(|| query_param(query, "account_id"))
            .or_else(|| query_param(query, "accountId"))
            .unwrap_or_default(),
        email: body_string(&parsed_body, "email")
            .or_else(|| query_param(query, "email"))
            .unwrap_or_default(),
        oauth_source_key: body_string_alias(&parsed_body, "oauth_source_key", "oauthSourceKey")
            .or_else(|| query_param(query, "oauth_source_key"))
            .or_else(|| query_param(query, "oauthSourceKey"))
            .unwrap_or_default(),
    };
    provider_bridge::apply_oauth_refresh_json_from_parts(config, runtime_base_dir, options)
}

pub(crate) fn provider_oauth_refresh_failure_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    match provider_oauth_refresh_failure_http_body(config, query, body) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"provider_oauth_refresh_failure_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn provider_oauth_refresh_failure_http_body(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> Result<String, String> {
    let parsed_body = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        serde_json::from_str::<Value>(body)
            .map_err(|err| format!("invalid oauth refresh failure request json: {err}"))?
    };
    let runtime_base_dir = body_string(&parsed_body, "runtime_base_dir")
        .or_else(|| body_string(&parsed_body, "runtimeBaseDir"))
        .or_else(|| query_param(query, "runtime_base_dir"))
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let options = xhub_provider::ProviderOAuthRefreshFailureOptions {
        account_key: body_string_alias(&parsed_body, "account_key", "accountKey")
            .or_else(|| query_param(query, "account_key"))
            .or_else(|| query_param(query, "accountKey"))
            .ok_or_else(|| "provider oauth refresh failure requires account_key".to_string())?,
        failed_at_ms: body_u64_alias(&parsed_body, "failed_at_ms", "failedAtMs")
            .or_else(|| body_u64_alias(&parsed_body, "now_ms", "nowMs"))
            .or_else(|| {
                query_param(query, "failed_at_ms").and_then(|value| value.parse::<u64>().ok())
            })
            .or_else(|| {
                query_param(query, "failedAtMs").and_then(|value| value.parse::<u64>().ok())
            })
            .or_else(|| query_param(query, "now_ms").and_then(|value| value.parse::<u64>().ok()))
            .or_else(|| query_param(query, "nowMs").and_then(|value| value.parse::<u64>().ok()))
            .unwrap_or_else(|| now_ms().min(u64::MAX as u128) as u64),
        base_failure_backoff_ms: body_u64_alias(
            &parsed_body,
            "base_failure_backoff_ms",
            "baseFailureBackoffMs",
        )
        .or_else(|| {
            query_param(query, "base_failure_backoff_ms")
                .and_then(|value| value.parse::<u64>().ok())
        })
        .or_else(|| {
            query_param(query, "baseFailureBackoffMs").and_then(|value| value.parse::<u64>().ok())
        })
        .unwrap_or(60_000),
        max_failure_backoff_ms: body_u64_alias(
            &parsed_body,
            "max_failure_backoff_ms",
            "maxFailureBackoffMs",
        )
        .or_else(|| {
            query_param(query, "max_failure_backoff_ms").and_then(|value| value.parse::<u64>().ok())
        })
        .or_else(|| {
            query_param(query, "maxFailureBackoffMs").and_then(|value| value.parse::<u64>().ok())
        })
        .unwrap_or(15 * 60_000),
        terminal: body_bool(&parsed_body, "terminal").unwrap_or_else(|| {
            optional_query_bool_alias(query, "terminal", "terminal", false).unwrap_or(false)
        }),
        error_code: body_string_alias(&parsed_body, "error_code", "errorCode")
            .or_else(|| query_param(query, "error_code"))
            .or_else(|| query_param(query, "errorCode"))
            .unwrap_or_default(),
        error_message: body_string_alias(&parsed_body, "error_message", "errorMessage")
            .or_else(|| query_param(query, "error_message"))
            .or_else(|| query_param(query, "errorMessage"))
            .unwrap_or_default(),
    };
    provider_bridge::record_oauth_refresh_failure_json_from_parts(config, runtime_base_dir, options)
}

pub(crate) fn provider_codex_oauth_plan_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    match provider_codex_oauth_plan_http_body(config, query, body) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"provider_codex_oauth_plan_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn provider_codex_oauth_plan_http_body(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> Result<String, String> {
    let parsed_body = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        serde_json::from_str::<Value>(body)
            .map_err(|err| format!("invalid codex oauth plan request json: {err}"))?
    };
    let runtime_base_dir = body_string(&parsed_body, "runtime_base_dir")
        .or_else(|| body_string(&parsed_body, "runtimeBaseDir"))
        .or_else(|| query_param(query, "runtime_base_dir"))
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let now = body_u64_alias(&parsed_body, "now_ms", "nowMs")
        .or_else(|| query_param(query, "now_ms").and_then(|value| value.parse::<u64>().ok()))
        .or_else(|| query_param(query, "nowMs").and_then(|value| value.parse::<u64>().ok()))
        .unwrap_or_else(|| now_ms().min(u64::MAX as u128) as u64);
    let include_skipped = body_bool_alias(&parsed_body, "include_skipped", "includeSkipped")
        .or_else(|| {
            optional_query_bool_alias(query, "include_skipped", "includeSkipped", false).ok()
        })
        .unwrap_or(false);
    let mut in_flight_account_keys = body_string_list(&parsed_body, "in_flight_account_keys");
    in_flight_account_keys.extend(body_string_list(&parsed_body, "inFlightAccountKeys"));
    if let Some(keys) = query_param_list(query, "in_flight_account_keys")
        .or_else(|| query_param_list(query, "inFlightAccountKeys"))
    {
        in_flight_account_keys.extend(keys);
    }
    in_flight_account_keys.sort();
    in_flight_account_keys.dedup();
    provider_bridge::plan_codex_oauth_refresh_json_from_parts(
        config,
        runtime_base_dir,
        xhub_provider::ProviderOAuthRefreshPlanOptions {
            now_ms: now,
            include_skipped,
            in_flight_account_keys,
            refresh_lead_ms: body_u64_alias(&parsed_body, "refresh_lead_ms", "refreshLeadMs")
                .or_else(|| {
                    query_param(query, "refresh_lead_ms")
                        .and_then(|value| value.parse::<u64>().ok())
                })
                .or_else(|| {
                    query_param(query, "refreshLeadMs").and_then(|value| value.parse::<u64>().ok())
                })
                .unwrap_or(0),
            min_refresh_lead_ms: body_u64_alias(
                &parsed_body,
                "min_refresh_lead_ms",
                "minRefreshLeadMs",
            )
            .or_else(|| {
                query_param(query, "min_refresh_lead_ms")
                    .and_then(|value| value.parse::<u64>().ok())
            })
            .or_else(|| {
                query_param(query, "minRefreshLeadMs").and_then(|value| value.parse::<u64>().ok())
            })
            .unwrap_or(0),
        },
    )
}

pub(crate) fn provider_codex_oauth_refresh_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    match provider_codex_oauth_refresh_http_body(config, query, body) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"provider_codex_oauth_refresh_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn provider_codex_oauth_refresh_http_body(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> Result<String, String> {
    let parsed_body = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        serde_json::from_str::<Value>(body)
            .map_err(|err| format!("invalid codex oauth refresh request json: {err}"))?
    };
    let runtime_base_dir = body_string(&parsed_body, "runtime_base_dir")
        .or_else(|| body_string(&parsed_body, "runtimeBaseDir"))
        .or_else(|| query_param(query, "runtime_base_dir"))
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let options = provider_bridge::CodexOAuthRefreshOptions {
        account_key: body_string_alias(&parsed_body, "account_key", "accountKey")
            .or_else(|| query_param(query, "account_key"))
            .or_else(|| query_param(query, "accountKey"))
            .ok_or_else(|| "provider codex oauth refresh requires account_key".to_string())?,
        refreshed_at_ms: body_u64_alias(&parsed_body, "refreshed_at_ms", "refreshedAtMs")
            .or_else(|| body_u64_alias(&parsed_body, "now_ms", "nowMs"))
            .or_else(|| {
                query_param(query, "refreshed_at_ms").and_then(|value| value.parse::<u64>().ok())
            })
            .or_else(|| {
                query_param(query, "refreshedAtMs").and_then(|value| value.parse::<u64>().ok())
            })
            .or_else(|| query_param(query, "now_ms").and_then(|value| value.parse::<u64>().ok()))
            .or_else(|| query_param(query, "nowMs").and_then(|value| value.parse::<u64>().ok()))
            .unwrap_or_else(|| now_ms().min(u64::MAX as u128) as u64),
        timeout_ms: body_u64_alias(&parsed_body, "timeout_ms", "timeoutMs")
            .or_else(|| {
                query_param(query, "timeout_ms").and_then(|value| value.parse::<u64>().ok())
            })
            .or_else(|| query_param(query, "timeoutMs").and_then(|value| value.parse::<u64>().ok()))
            .unwrap_or(15_000),
        base_failure_backoff_ms: body_u64_alias(
            &parsed_body,
            "base_failure_backoff_ms",
            "baseFailureBackoffMs",
        )
        .or_else(|| {
            query_param(query, "base_failure_backoff_ms")
                .and_then(|value| value.parse::<u64>().ok())
        })
        .or_else(|| {
            query_param(query, "baseFailureBackoffMs").and_then(|value| value.parse::<u64>().ok())
        })
        .unwrap_or(60_000),
        max_failure_backoff_ms: body_u64_alias(
            &parsed_body,
            "max_failure_backoff_ms",
            "maxFailureBackoffMs",
        )
        .or_else(|| {
            query_param(query, "max_failure_backoff_ms").and_then(|value| value.parse::<u64>().ok())
        })
        .or_else(|| {
            query_param(query, "maxFailureBackoffMs").and_then(|value| value.parse::<u64>().ok())
        })
        .unwrap_or(15 * 60_000),
        token_url: body_string_alias(&parsed_body, "token_url", "tokenUrl")
            .or_else(|| query_param(query, "token_url"))
            .or_else(|| query_param(query, "tokenUrl"))
            .unwrap_or_default(),
        force: body_bool(&parsed_body, "force").unwrap_or_else(|| {
            optional_query_bool_alias(query, "force", "force", false).unwrap_or(false)
        }),
    };
    provider_bridge::refresh_codex_oauth_json_from_parts(config, runtime_base_dir, options)
}

pub(crate) fn provider_compare_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    match provider_compare_http_body(config, query, body) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"provider_compare_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn provider_compare_http_body(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> Result<String, String> {
    let parsed_body = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        serde_json::from_str::<Value>(body)
            .map_err(|err| format!("invalid compare request json: {err}"))?
    };

    let node_value = if let Some(value) = parsed_body.get("node_decision") {
        value.clone()
    } else if let Some(value) = parsed_body.get("nodeDecision") {
        value.clone()
    } else if let Some(raw) = parsed_body
        .get("node_decision_json")
        .or_else(|| parsed_body.get("nodeDecisionJson"))
        .and_then(Value::as_str)
    {
        serde_json::from_str::<Value>(raw)
            .map_err(|err| format!("invalid node_decision_json: {err}"))?
    } else if let Some(raw) =
        query_param(query, "node_decision_json").or_else(|| query_param(query, "nodeDecisionJson"))
    {
        serde_json::from_str::<Value>(&raw)
            .map_err(|err| format!("invalid node_decision_json: {err}"))?
    } else {
        return Err("provider compare requires node_decision".to_string());
    };

    let runtime_base_dir = body_string(&parsed_body, "runtime_base_dir")
        .or_else(|| body_string(&parsed_body, "runtimeBaseDir"))
        .or_else(|| query_param(query, "runtime_base_dir"))
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let model_id = body_string(&parsed_body, "model_id")
        .or_else(|| body_string(&parsed_body, "modelId"))
        .or_else(|| query_param(query, "model_id"))
        .or_else(|| query_param(query, "modelId"));
    let provider = body_string(&parsed_body, "provider").or_else(|| query_param(query, "provider"));
    let compare_now_ms = body_u128(&parsed_body, "now_ms")
        .or_else(|| body_u128(&parsed_body, "nowMs"))
        .or_else(|| query_param(query, "now_ms").and_then(|value| value.parse::<u128>().ok()))
        .or_else(|| query_param(query, "nowMs").and_then(|value| value.parse::<u128>().ok()));

    provider_bridge::compare_json_from_parts(
        config,
        runtime_base_dir,
        node_value,
        model_id,
        provider,
        compare_now_ms,
    )
}

pub(crate) fn provider_reports_http_json(
    config: &HubConfig,
    query: &str,
) -> (&'static str, String) {
    let limit = match optional_query_usize(query, "limit", 20) {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    match provider_bridge::reports_json_from_parts(config, limit) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"provider_reports_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn provider_readiness_http_json(
    config: &HubConfig,
    query: &str,
) -> (&'static str, String) {
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
    match provider_bridge::readiness_json_from_parts(
        config,
        min_compare_reports,
        max_mismatches,
        limit,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"provider_readiness_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}
