use serde_json::{json, Map, Value};

use super::super::*;

mod metadata;
mod planning;
mod quota_windows;
mod runtime;
mod state;

pub use planning::{plan_codex_oauth_refresh, plan_openai_quota_refresh};
pub use runtime::{
    apply_openai_quota_usage_to_runtime_base_dir, apply_provider_oauth_refresh_to_runtime_base_dir,
    plan_codex_oauth_refresh_from_runtime_base_dir,
    plan_openai_quota_refresh_from_runtime_base_dir,
    record_openai_quota_refresh_failure_to_runtime_base_dir,
    record_provider_oauth_refresh_failure_to_runtime_base_dir,
};

use metadata::*;
use quota_windows::*;
use state::*;

const QUOTA_REFRESH_RETRY_SOURCE: &str = "usage_window";
const OAUTH_REFRESH_RETRY_SOURCE: &str = "refresh";
const QUOTA_BASIS_POINTS_CAP: u64 = 10_000;
const DEFAULT_OAUTH_REFRESH_LEAD_MS: u64 = 5 * 24 * 60 * 60 * 1000;
const DEFAULT_OAUTH_MIN_REFRESH_LEAD_MS: u64 = 5 * 60 * 1000;
const OPENAI_USAGE_WINDOW_OAUTH_SOURCES: &[&str] =
    &["chatgpt", "openai-chatgpt", "openai", "codex"];

fn record_openai_quota_refresh_failure_to_account(
    account_value: &mut Value,
    account_key: &str,
    options: &OpenAIQuotaRefreshFailureOptions,
) -> Result<ProviderQuotaRefreshFailureResult, ProviderRouteError> {
    let failed_at_ms = if options.failed_at_ms == 0 {
        current_time_millis()
    } else {
        options.failed_at_ms
    };
    let account_object = account_value
        .as_object_mut()
        .ok_or_else(|| ProviderRouteError::Invalid("account entry is not an object".to_string()))?;
    let current_refresh_state = account_object
        .get("refresh_state")
        .cloned()
        .unwrap_or(Value::Null);
    let previous_failure_count =
        json_u64(&current_refresh_state, "failure_count").min(u32::MAX as u64) as u32;
    let failure_count = previous_failure_count.saturating_add(1);
    let next_refresh_at_ms = failed_at_ms.saturating_add(quota_failure_backoff_ms(
        failure_count,
        options.base_failure_backoff_ms,
        options.max_failure_backoff_ms,
    ));
    let current_quota = account_object.get("quota").cloned().unwrap_or(Value::Null);
    let mut quota = normalized_quota_object(&current_quota);
    quota.insert("next_refresh_at_ms".to_string(), json!(next_refresh_at_ms));
    account_object.insert("quota".to_string(), Value::Object(quota));
    let mut refresh_state = normalized_refresh_state_object(&current_refresh_state);
    refresh_state.insert("status".to_string(), Value::String("idle".to_string()));
    refresh_state.insert("last_attempt_at_ms".to_string(), json!(failed_at_ms));
    refresh_state.insert(
        "last_success_at_ms".to_string(),
        json!(json_u64(&current_refresh_state, "last_success_at_ms")),
    );
    refresh_state.insert("next_refresh_at_ms".to_string(), json!(0));
    refresh_state.insert("failure_count".to_string(), json!(failure_count));
    refresh_state.insert(
        "last_error_code".to_string(),
        Value::String(trim_string(&options.error_code)),
    );
    refresh_state.insert(
        "last_error_message".to_string(),
        Value::String(trim_string(&options.error_message)),
    );
    account_object.insert("refresh_state".to_string(), Value::Object(refresh_state));
    account_object.insert("updated_at_ms".to_string(), json!(failed_at_ms));

    Ok(ProviderQuotaRefreshFailureResult {
        ok: true,
        account_key: account_key.to_string(),
        updated: true,
        failed_at_ms,
        failure_count,
        next_refresh_at_ms,
        error_code: trim_string(&options.error_code),
        error_message: trim_string(&options.error_message),
    })
}

fn apply_provider_oauth_refresh_to_account(
    account_value: &mut Value,
    account_key: &str,
    options: &ProviderOAuthRefreshApplyOptions,
    refreshed_at_ms: u64,
) -> Result<ProviderOAuthRefreshResult, ProviderRouteError> {
    let account_object = account_value
        .as_object_mut()
        .ok_or_else(|| ProviderRouteError::Invalid("account entry is not an object".to_string()))?;
    let current_refresh_state = account_object
        .get("refresh_state")
        .cloned()
        .unwrap_or(Value::Null);
    let current_error_state = account_object
        .get("error_state")
        .cloned()
        .unwrap_or(Value::Null);
    let access_token = trim_string(&options.access_token);
    let refresh_token = trim_string(&options.refresh_token);

    account_object.insert("api_key".to_string(), Value::String(access_token));
    if !refresh_token.is_empty() {
        account_object.insert("refresh_token".to_string(), Value::String(refresh_token));
    }
    if options.expires_at_ms > 0 {
        account_object.insert("expires_at_ms".to_string(), json!(options.expires_at_ms));
    }
    if !options.account_id.trim().is_empty() {
        account_object.insert(
            "account_id".to_string(),
            Value::String(trim_string(&options.account_id)),
        );
    }
    if !options.email.trim().is_empty() {
        account_object.insert(
            "email".to_string(),
            Value::String(trim_string(&options.email)),
        );
    }
    if !options.oauth_source_key.trim().is_empty() {
        account_object.insert(
            "oauth_source_key".to_string(),
            Value::String(trim_string(&options.oauth_source_key)),
        );
    }
    account_object.insert("last_refresh_at_ms".to_string(), json!(refreshed_at_ms));
    account_object.insert("updated_at_ms".to_string(), json!(refreshed_at_ms));

    let mut refresh_state = normalized_refresh_state_object(&current_refresh_state);
    refresh_state.insert("status".to_string(), Value::String("idle".to_string()));
    refresh_state.insert("last_attempt_at_ms".to_string(), json!(refreshed_at_ms));
    refresh_state.insert("last_success_at_ms".to_string(), json!(refreshed_at_ms));
    refresh_state.insert("next_refresh_at_ms".to_string(), json!(0));
    refresh_state.insert("failure_count".to_string(), json!(0));
    refresh_state.insert("last_error_code".to_string(), Value::String(String::new()));
    refresh_state.insert(
        "last_error_message".to_string(),
        Value::String(String::new()),
    );
    account_object.insert("refresh_state".to_string(), Value::Object(refresh_state));

    if auth_managed_error_state(&current_error_state) {
        let mut error_state = normalized_error_state_object(&current_error_state);
        error_state.insert("status".to_string(), Value::String("healthy".to_string()));
        error_state.insert("status_message".to_string(), Value::String(String::new()));
        error_state.insert("reason_code".to_string(), Value::String(String::new()));
        error_state.insert("last_error_code".to_string(), Value::String(String::new()));
        error_state.insert("last_error_at_ms".to_string(), json!(0));
        error_state.insert("next_retry_at_ms".to_string(), json!(0));
        error_state.insert("retry_at_source".to_string(), Value::String(String::new()));
        error_state.insert("auto_disabled".to_string(), Value::Bool(false));
        account_object.insert("error_state".to_string(), Value::Object(error_state));
    }

    Ok(ProviderOAuthRefreshResult {
        ok: true,
        account_key: account_key.to_string(),
        updated: true,
        refreshed_at_ms,
        expires_at_ms: options.expires_at_ms,
        next_refresh_at_ms: 0,
        error_code: String::new(),
        error_message: String::new(),
    })
}

fn record_provider_oauth_refresh_failure_to_account(
    account_value: &mut Value,
    account_key: &str,
    options: &ProviderOAuthRefreshFailureOptions,
) -> Result<ProviderOAuthRefreshResult, ProviderRouteError> {
    let failed_at_ms = if options.failed_at_ms == 0 {
        current_time_millis()
    } else {
        options.failed_at_ms
    };
    let account_object = account_value
        .as_object_mut()
        .ok_or_else(|| ProviderRouteError::Invalid("account entry is not an object".to_string()))?;
    let current_refresh_state = account_object
        .get("refresh_state")
        .cloned()
        .unwrap_or(Value::Null);
    let previous_failure_count =
        json_u64(&current_refresh_state, "failure_count").min(u32::MAX as u64) as u32;
    let failure_count = previous_failure_count.saturating_add(1);
    let error_code = normalized_oauth_refresh_error_code(&options.error_code);
    let error_message = sanitized_status_message(&options.error_message, &error_code);
    let terminal = options.terminal || oauth_refresh_terminal_error(&error_code);
    let next_refresh_at_ms = if terminal {
        0
    } else {
        failed_at_ms.saturating_add(quota_failure_backoff_ms(
            failure_count,
            options.base_failure_backoff_ms,
            options.max_failure_backoff_ms,
        ))
    };

    let mut refresh_state = normalized_refresh_state_object(&current_refresh_state);
    refresh_state.insert("status".to_string(), Value::String("failed".to_string()));
    refresh_state.insert("last_attempt_at_ms".to_string(), json!(failed_at_ms));
    refresh_state.insert(
        "last_success_at_ms".to_string(),
        json!(json_u64(&current_refresh_state, "last_success_at_ms")),
    );
    refresh_state.insert("next_refresh_at_ms".to_string(), json!(next_refresh_at_ms));
    refresh_state.insert("failure_count".to_string(), json!(failure_count));
    refresh_state.insert(
        "last_error_code".to_string(),
        Value::String(error_code.clone()),
    );
    refresh_state.insert(
        "last_error_message".to_string(),
        Value::String(error_message.clone()),
    );
    account_object.insert("refresh_state".to_string(), Value::Object(refresh_state));
    account_object.insert("updated_at_ms".to_string(), json!(failed_at_ms));

    let current_error_state = account_object
        .get("error_state")
        .cloned()
        .unwrap_or(Value::Null);
    let mut error_state = normalized_error_state_object(&current_error_state);
    error_state.insert(
        "status".to_string(),
        Value::String(oauth_refresh_error_status(&error_code).to_string()),
    );
    error_state.insert(
        "status_message".to_string(),
        Value::String(error_message.clone()),
    );
    error_state.insert("reason_code".to_string(), Value::String(error_code.clone()));
    error_state.insert(
        "last_error_code".to_string(),
        Value::String(error_code.clone()),
    );
    error_state.insert("last_error_at_ms".to_string(), json!(failed_at_ms));
    error_state.insert("next_retry_at_ms".to_string(), json!(next_refresh_at_ms));
    error_state.insert(
        "retry_at_source".to_string(),
        Value::String(OAUTH_REFRESH_RETRY_SOURCE.to_string()),
    );
    error_state.insert("auto_disabled".to_string(), Value::Bool(false));
    account_object.insert("error_state".to_string(), Value::Object(error_state));

    Ok(ProviderOAuthRefreshResult {
        ok: false,
        account_key: account_key.to_string(),
        updated: true,
        refreshed_at_ms: failed_at_ms,
        expires_at_ms: json_u64(account_value, "expires_at_ms"),
        next_refresh_at_ms,
        error_code,
        error_message,
    })
}

fn apply_openai_quota_usage_to_account(
    account_value: &mut Value,
    usage: &Value,
    options: &OpenAIQuotaApplyOptions,
    account_key: &str,
) -> Result<ProviderQuotaRefreshApplyResult, ProviderRouteError> {
    let refreshed_at_ms = options.refreshed_at_ms;
    if refreshed_at_ms == 0 {
        return Err(ProviderRouteError::Invalid(
            "missing refreshed_at_ms for quota apply".to_string(),
        ));
    }
    let success_interval_ms = options.success_interval_ms.max(250);
    let high_water_interval_ms = options.high_water_interval_ms.max(250);
    let windows = openai_windows_from_usage(usage, refreshed_at_ms);
    let most_constrained =
        windows
            .iter()
            .cloned()
            .fold(None::<ProviderQuotaUsageWindow>, |best, candidate| {
                let Some(best_window) = best else {
                    return Some(candidate);
                };
                if (candidate.used_percent - best_window.used_percent).abs() > f64::EPSILON {
                    if candidate.used_percent > best_window.used_percent {
                        Some(candidate)
                    } else {
                        Some(best_window)
                    }
                } else if candidate.limited != best_window.limited {
                    if candidate.limited {
                        Some(candidate)
                    } else {
                        Some(best_window)
                    }
                } else {
                    Some(best_window)
                }
            });
    let limited = windows.iter().any(|window| window.limited);
    let next_retry_at_ms = windows
        .iter()
        .filter(|window| window.limited && window.reset_at_ms > refreshed_at_ms)
        .map(|window| window.reset_at_ms)
        .min()
        .unwrap_or(0);
    let used_basis_points = u64::from(basis_points_from_percent(
        most_constrained
            .as_ref()
            .map_or(0.0, |window| window.used_percent),
    ));
    let next_refresh_at_ms = if limited && next_retry_at_ms > refreshed_at_ms {
        next_retry_at_ms
    } else {
        let used_percent = most_constrained
            .as_ref()
            .map_or(0.0, |window| window.used_percent);
        refreshed_at_ms
            + if used_percent >= 90.0 {
                high_water_interval_ms
            } else {
                success_interval_ms
            }
    };

    let account_object = account_value
        .as_object_mut()
        .ok_or_else(|| ProviderRouteError::Invalid("account entry is not an object".to_string()))?;
    let current_quota = account_object.get("quota").cloned().unwrap_or(Value::Null);
    let current_error_state = account_object
        .get("error_state")
        .cloned()
        .unwrap_or(Value::Null);
    let current_refresh_state = account_object
        .get("refresh_state")
        .cloned()
        .unwrap_or(Value::Null);

    let mut quota = Map::new();
    quota.insert("daily_token_cap".to_string(), json!(QUOTA_BASIS_POINTS_CAP));
    quota.insert("daily_tokens_used".to_string(), json!(used_basis_points));
    quota.insert(
        "daily_tokens_remaining".to_string(),
        json!(QUOTA_BASIS_POINTS_CAP.saturating_sub(used_basis_points)),
    );
    quota.insert(
        "total_tokens_used".to_string(),
        json!(json_u64(&current_quota, "total_tokens_used")),
    );
    quota.insert(
        "last_used_at_ms".to_string(),
        json!(json_u64(&current_quota, "last_used_at_ms")),
    );
    quota.insert(
        "last_error_at_ms".to_string(),
        json!(json_u64(&current_quota, "last_error_at_ms")),
    );
    quota.insert(
        "consecutive_errors".to_string(),
        json!(json_u64(&current_quota, "consecutive_errors")),
    );
    quota.insert("cooldown_until_ms".to_string(), json!(next_retry_at_ms));
    quota.insert("next_refresh_at_ms".to_string(), json!(next_refresh_at_ms));
    quota.insert(
        "usage_windows".to_string(),
        serde_json::to_value(sorted_quota_windows(windows))
            .map_err(|err| ProviderRouteError::Json(format!("serialize quota windows: {err}")))?,
    );

    if let Some(plan_type) = non_empty_json_string(usage, "plan_type") {
        account_object.insert("tier".to_string(), Value::String(plan_type));
    }
    if !options.account_id.trim().is_empty() {
        account_object.insert(
            "account_id".to_string(),
            Value::String(trim_string(&options.account_id)),
        );
    }
    if !options.oauth_source_key.trim().is_empty() {
        account_object.insert(
            "oauth_source_key".to_string(),
            Value::String(trim_string(&options.oauth_source_key)),
        );
    }
    account_object.insert("quota".to_string(), Value::Object(quota));
    account_object.insert("last_refresh_at_ms".to_string(), json!(refreshed_at_ms));
    account_object.insert("updated_at_ms".to_string(), json!(refreshed_at_ms));
    let mut refresh_state = normalized_refresh_state_object(&current_refresh_state);
    refresh_state.insert("status".to_string(), Value::String("idle".to_string()));
    refresh_state.insert("last_attempt_at_ms".to_string(), json!(refreshed_at_ms));
    refresh_state.insert("last_success_at_ms".to_string(), json!(refreshed_at_ms));
    refresh_state.insert("next_refresh_at_ms".to_string(), json!(0));
    refresh_state.insert("failure_count".to_string(), json!(0));
    refresh_state.insert("last_error_code".to_string(), Value::String(String::new()));
    refresh_state.insert(
        "last_error_message".to_string(),
        Value::String(String::new()),
    );
    account_object.insert("refresh_state".to_string(), Value::Object(refresh_state));

    if limited {
        let label = most_constrained
            .as_ref()
            .map(|window| window.label.clone())
            .filter(|label| !label.trim().is_empty())
            .unwrap_or_else(|| "usage window".to_string());
        let used_percent = most_constrained
            .as_ref()
            .map_or(0.0, |window| window.used_percent);
        let mut error_state = normalized_error_state_object(&current_error_state);
        error_state.insert(
            "status".to_string(),
            Value::String("blocked_quota".to_string()),
        );
        error_state.insert(
            "status_message".to_string(),
            Value::String(format!("{label} exhausted ({used_percent:.1}%)")),
        );
        error_state.insert(
            "reason_code".to_string(),
            Value::String("blocked_quota".to_string()),
        );
        error_state.insert(
            "last_error_code".to_string(),
            Value::String("blocked_quota".to_string()),
        );
        error_state.insert("last_error_at_ms".to_string(), json!(refreshed_at_ms));
        error_state.insert("next_retry_at_ms".to_string(), json!(next_retry_at_ms));
        error_state.insert(
            "retry_at_source".to_string(),
            Value::String(QUOTA_REFRESH_RETRY_SOURCE.to_string()),
        );
        error_state.insert("auto_disabled".to_string(), Value::Bool(false));
        account_object.insert("error_state".to_string(), Value::Object(error_state));
    } else if quota_managed_error_state(&current_error_state) {
        let mut error_state = normalized_error_state_object(&current_error_state);
        error_state.insert("status".to_string(), Value::String("healthy".to_string()));
        error_state.insert("status_message".to_string(), Value::String(String::new()));
        error_state.insert("reason_code".to_string(), Value::String(String::new()));
        error_state.insert("last_error_code".to_string(), Value::String(String::new()));
        error_state.insert("last_error_at_ms".to_string(), json!(0));
        error_state.insert("next_retry_at_ms".to_string(), json!(0));
        error_state.insert("retry_at_source".to_string(), Value::String(String::new()));
        error_state.insert("auto_disabled".to_string(), Value::Bool(false));
        account_object.insert("error_state".to_string(), Value::Object(error_state));
    }

    Ok(ProviderQuotaRefreshApplyResult {
        ok: true,
        account_key: account_key.to_string(),
        updated: true,
        refreshed_at_ms,
        next_refresh_at_ms,
        limited,
        error_code: String::new(),
        error_message: String::new(),
    })
}
