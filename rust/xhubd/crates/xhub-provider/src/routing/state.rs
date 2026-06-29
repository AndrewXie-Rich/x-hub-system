use std::collections::BTreeSet;

use super::*;

pub(super) fn account_availability_state(
    account: &ProviderAccount,
    now_ms: u128,
    model_id: &str,
) -> Availability {
    if !account.enabled {
        return availability("disabled", "disabled", 0);
    }
    if trim_string(&account.api_key).is_empty() {
        return availability("blocked", "auth_missing", 0);
    }
    if !model_id.trim().is_empty() && !matches_account_model(account, model_id) {
        return availability("blocked", "model_unsupported", 0);
    }
    if account.expires_at_ms > 0 && now_ms > account.expires_at_ms as u128 {
        return availability("blocked", "token_expired", 0);
    }

    let refresh_status = normalized_token(&account.refresh_state.status);
    let refresh_reason_code = first_non_empty(&[
        &account.refresh_state.last_error_code,
        &account.refresh_state.last_error_message,
    ]);
    if refresh_status == "pending" || refresh_status == "refreshing" {
        return availability(
            "cooldown",
            refresh_reason_code.as_deref().unwrap_or("refresh_pending"),
            account.refresh_state.next_refresh_at_ms,
        );
    }
    if refresh_status == "failed" || refresh_status == "cooldown" {
        return availability(
            if account.refresh_state.next_refresh_at_ms > 0
                && account.refresh_state.next_refresh_at_ms as u128 > now_ms
            {
                "cooldown"
            } else {
                "blocked"
            },
            refresh_reason_code.as_deref().unwrap_or("refresh_failed"),
            account.refresh_state.next_refresh_at_ms,
        );
    }

    let status = normalized_token(&account.error_state.status);
    let reason_code = normalized_reason_code(account, &status);
    let retry_at_ms = effective_retry_at_ms(account);

    if status == "disabled" || account.error_state.auto_disabled {
        return availability(
            "disabled",
            reason_code.as_deref().unwrap_or("disabled"),
            retry_at_ms,
        );
    }
    if status == "auth_failed" || status == "blocked_auth" {
        return availability(
            "blocked",
            reason_code.as_deref().unwrap_or("auth_failed"),
            retry_at_ms,
        );
    }
    if status == "blocked_config" {
        return availability(
            "blocked",
            reason_code.as_deref().unwrap_or("blocked_config"),
            retry_at_ms,
        );
    }

    if !model_id.trim().is_empty() {
        if let Some(model_state) = resolve_account_model_state(account, model_id) {
            if let Some(model_availability) = availability_from_model_state(model_state.state) {
                return model_availability;
            }
        }
    }

    if retry_at_ms > 0 && now_ms < retry_at_ms as u128 {
        return availability(
            "cooldown",
            reason_code.as_deref().unwrap_or("cooldown_active"),
            retry_at_ms,
        );
    }

    if account.quota.daily_token_cap > 0
        && account.quota.daily_tokens_used >= account.quota.daily_token_cap
    {
        return availability(
            "blocked",
            reason_code.as_deref().unwrap_or("daily_token_cap_exceeded"),
            retry_at_ms,
        );
    }
    if status == "unknown_stale" || reason_code.as_deref() == Some("runtime_stale") {
        return availability(
            "stale",
            reason_code.as_deref().unwrap_or("runtime_stale"),
            retry_at_ms,
        );
    }
    if status == "blocked_quota" || status == "rate_limited" {
        return availability(
            "blocked",
            reason_code.as_deref().unwrap_or(&status),
            retry_at_ms,
        );
    }
    if status == "blocked_provider" || status == "blocked_network" {
        return availability(
            "blocked",
            reason_code.as_deref().unwrap_or(&status),
            retry_at_ms,
        );
    }

    availability("ready", "", retry_at_ms)
}

pub(super) fn availability(state: &str, reason_code: &str, retry_at_ms: u64) -> Availability {
    Availability {
        state: state.to_string(),
        reason_code: normalized_token(reason_code),
        retry_at_ms,
    }
}

pub(super) fn matches_account_model(account: &ProviderAccount, model_id: &str) -> bool {
    let raw_patterns: Vec<String> = account
        .models
        .iter()
        .map(|value| normalized_token(value))
        .filter(|value| !value.is_empty())
        .collect();
    if raw_patterns.is_empty() {
        return true;
    }

    let lookup: BTreeSet<String> = model_lookup_keys(model_id).into_iter().collect();
    if lookup.is_empty() {
        return false;
    }

    for raw_pattern in raw_patterns {
        let patterns = model_lookup_keys(&raw_pattern);
        let patterns = if patterns.is_empty() {
            vec![raw_pattern]
        } else {
            patterns
        };
        for pattern in patterns {
            if pattern == "*" || lookup.contains(&pattern) {
                return true;
            }
            if let Some(prefix) = pattern.strip_suffix('*') {
                if lookup.iter().any(|candidate| candidate.starts_with(prefix)) {
                    return true;
                }
            }
        }
    }
    false
}

pub(super) fn resolve_account_model_state<'a>(
    account: &'a ProviderAccount,
    model_id: &str,
) -> Option<ModelStateMatch<'a>> {
    let lookup = model_lookup_keys(model_id);
    if lookup.is_empty() {
        return None;
    }
    for key in &lookup {
        if let Some((matched_key, state)) = account.model_states.get_key_value(key) {
            return Some(ModelStateMatch {
                key: model_state_output_key(matched_key, state),
                state,
            });
        }
    }
    let lookup_set: BTreeSet<String> = lookup.into_iter().collect();
    for (key, state) in &account.model_states {
        if model_lookup_keys(key)
            .into_iter()
            .any(|candidate| lookup_set.contains(&candidate))
        {
            return Some(ModelStateMatch {
                key: model_state_output_key(key, state),
                state,
            });
        }
    }
    for (key, state) in &account.model_states {
        let Some(prefix) = key.strip_suffix('*') else {
            continue;
        };
        let prefix_keys = model_lookup_keys(prefix);
        if !prefix.is_empty()
            && prefix_keys.iter().any(|prefix| {
                lookup_set
                    .iter()
                    .any(|candidate| candidate.starts_with(prefix))
            })
        {
            return Some(ModelStateMatch {
                key: model_state_output_key(key, state),
                state,
            });
        }
    }
    None
}

pub(super) fn model_state_output_key(map_key: &str, state: &ProviderModelState) -> String {
    let raw = first_non_empty(&[&state.model_id, map_key]).unwrap_or_default();
    normalized_model_id_for_routing(&raw)
}

pub(super) fn availability_from_model_state(
    model_state: &ProviderModelState,
) -> Option<Availability> {
    let status = normalized_token(&model_state.status);
    let reason_code = first_non_empty(&[
        &model_state.reason_code,
        &model_state.last_error_code,
        &model_state.status,
    ]);
    match status.as_str() {
        "ready" => Some(availability("ready", "", 0)),
        "cooldown" => Some(availability(
            "cooldown",
            reason_code.as_deref().unwrap_or("cooldown_active"),
            model_state.next_retry_at_ms,
        )),
        "disabled" => Some(availability(
            "disabled",
            reason_code.as_deref().unwrap_or("disabled"),
            model_state.next_retry_at_ms,
        )),
        "stale" => Some(availability(
            "stale",
            reason_code.as_deref().unwrap_or("runtime_stale"),
            model_state.next_retry_at_ms,
        )),
        "blocked" => Some(availability(
            "blocked",
            reason_code.as_deref().unwrap_or("blocked"),
            model_state.next_retry_at_ms,
        )),
        _ => None,
    }
}

pub(super) fn account_pool_state(
    account: &ProviderAccount,
    now_ms: u128,
    model_id: &str,
) -> PoolState {
    if !account.enabled {
        return pool_state(
            "disabled",
            normalized_reason_code(account, "disabled")
                .as_deref()
                .unwrap_or("disabled"),
            &account.error_state.status_message,
            effective_retry_at_ms(account),
        );
    }
    if trim_string(&account.api_key).is_empty() && trim_string(&account.refresh_token).is_empty() {
        return pool_state(
            "blocked",
            "auth_missing",
            "auth_missing",
            effective_retry_at_ms(account),
        );
    }
    if !model_id.trim().is_empty() && !account_supports_capability_target(account, model_id) {
        return pool_state("blocked", "model_unsupported", "model_unsupported", 0);
    }
    if account.expires_at_ms > 0 && now_ms > account.expires_at_ms as u128 {
        return pool_state(
            "expired",
            normalized_reason_code(account, "token_expired")
                .as_deref()
                .unwrap_or("token_expired"),
            &first_non_empty(&[
                &account.error_state.status_message,
                &account.refresh_state.last_error_message,
                "token_expired",
            ])
            .unwrap_or_else(|| "token_expired".to_string()),
            effective_retry_at_ms(account),
        );
    }

    let refresh_status = normalized_token(&account.refresh_state.status);
    let retry_at_ms = effective_retry_at_ms(account);
    if refresh_status == "pending" || refresh_status == "refreshing" {
        return pool_state(
            "cooldown",
            normalized_reason_code(account, "refresh_pending")
                .as_deref()
                .unwrap_or("refresh_pending"),
            &first_non_empty(&[
                &account.refresh_state.last_error_message,
                &account.refresh_state.status,
            ])
            .unwrap_or_default(),
            retry_at_ms,
        );
    }
    if refresh_status == "failed" || refresh_status == "cooldown" {
        return pool_state(
            if retry_at_ms as u128 > now_ms {
                "cooldown"
            } else {
                "blocked"
            },
            normalized_reason_code(account, "refresh_failed")
                .as_deref()
                .unwrap_or("refresh_failed"),
            &first_non_empty(&[
                &account.refresh_state.last_error_message,
                &account.error_state.status_message,
            ])
            .unwrap_or_default(),
            retry_at_ms,
        );
    }

    let error_status = normalized_token(&account.error_state.status);
    if error_status == "disabled" || account.error_state.auto_disabled {
        return pool_state(
            "disabled",
            normalized_reason_code(account, "disabled")
                .as_deref()
                .unwrap_or("disabled"),
            &account.error_state.status_message,
            retry_at_ms,
        );
    }
    if error_status == "auth_failed" || error_status == "blocked_auth" {
        return pool_state(
            "blocked",
            normalized_reason_code(account, "auth_failed")
                .as_deref()
                .unwrap_or("auth_failed"),
            &account.error_state.status_message,
            retry_at_ms,
        );
    }

    if !model_id.trim().is_empty() {
        if let Some(model_state) = resolve_account_model_state(account, model_id) {
            if let Some(pool_state_value) = pool_state_from_model_state(model_state.state) {
                return pool_state_value;
            }
        }
    }

    if error_status == "unknown_stale"
        || normalized_reason_code(account, "").as_deref() == Some("runtime_stale")
    {
        return pool_state(
            "stale",
            normalized_reason_code(account, "runtime_stale")
                .as_deref()
                .unwrap_or("runtime_stale"),
            &account.error_state.status_message,
            retry_at_ms,
        );
    }
    if retry_at_ms > 0 && now_ms < retry_at_ms as u128 {
        return pool_state(
            "cooldown",
            normalized_reason_code(account, "cooldown_active")
                .as_deref()
                .unwrap_or("cooldown_active"),
            &first_non_empty(&[
                &account.error_state.status_message,
                &account.refresh_state.last_error_message,
            ])
            .unwrap_or_default(),
            retry_at_ms,
        );
    }
    if error_status == "blocked_quota" || error_status == "rate_limited" {
        return pool_state(
            "blocked",
            normalized_reason_code(account, &error_status)
                .as_deref()
                .unwrap_or("blocked_quota"),
            &account.error_state.status_message,
            retry_at_ms,
        );
    }
    if matches!(
        error_status.as_str(),
        "blocked_provider" | "blocked_network" | "blocked_config" | "degraded"
    ) {
        return pool_state(
            "blocked",
            normalized_reason_code(account, &error_status)
                .as_deref()
                .unwrap_or("blocked_provider"),
            &account.error_state.status_message,
            retry_at_ms,
        );
    }
    if account.quota.daily_token_cap > 0
        && account.quota.daily_tokens_used >= account.quota.daily_token_cap
    {
        return pool_state(
            "blocked",
            normalized_reason_code(account, "daily_token_cap_exceeded")
                .as_deref()
                .unwrap_or("daily_token_cap_exceeded"),
            &account.error_state.status_message,
            retry_at_ms,
        );
    }
    pool_state("ready", "", "", retry_at_ms)
}

pub(super) fn pool_state(
    state: &str,
    reason_code: &str,
    status_message: &str,
    retry_at_ms: u64,
) -> PoolState {
    PoolState {
        state: normalized_token(state),
        reason_code: normalized_token(reason_code),
        status_message: trim_string(status_message),
        retry_at_ms,
    }
}

pub(super) fn pool_state_from_model_state(model_state: &ProviderModelState) -> Option<PoolState> {
    let status = normalized_token(&model_state.status);
    if !matches!(
        status.as_str(),
        "ready" | "cooldown" | "blocked" | "disabled" | "stale"
    ) {
        return None;
    }
    let reason_code = if status == "ready" {
        String::new()
    } else {
        first_non_empty(&[
            &model_state.reason_code,
            &model_state.last_error_code,
            &model_state.status,
        ])
        .unwrap_or_default()
    };
    Some(pool_state(
        &status,
        &reason_code,
        &model_state.status_message,
        model_state.next_retry_at_ms,
    ))
}

pub(super) fn provider_matches_pool_filter(
    account: &ProviderAccount,
    provider_filter: &str,
) -> bool {
    let filter =
        normalize_provider(provider_filter).unwrap_or_else(|| normalized_token(provider_filter));
    if filter.is_empty() {
        return true;
    }
    canonical_pool_provider(&account.provider) == canonical_pool_provider(&filter)
}

pub(super) fn account_supports_capability_target(
    account: &ProviderAccount,
    model_id: &str,
) -> bool {
    let target = trim_string(model_id);
    if target.is_empty() {
        return true;
    }
    if let Some(target_provider) = infer_provider_from_model_id(&target) {
        if canonical_pool_provider(&account.provider) != canonical_pool_provider(&target_provider) {
            return false;
        }
        return matches_account_model(account, &target);
    }
    if account.models.is_empty() {
        return false;
    }
    matches_account_model(account, &target)
}

pub(super) fn account_effective_pool_id(account: &ProviderAccount) -> String {
    let explicit = trim_string(&account.pool_id);
    if !explicit.is_empty() {
        return explicit;
    }
    let provider = canonical_pool_provider(&account.provider);
    let provider = if provider.is_empty() {
        "default".to_string()
    } else {
        provider
    };
    let host = first_non_empty(&[&account.provider_host])
        .unwrap_or_else(|| default_provider_host(&provider));
    let host = if host.is_empty() {
        "default".to_string()
    } else {
        host
    };
    let wire_api = normalize_wire_api(&account.wire_api);
    let wire_api = if wire_api.is_empty() {
        "default".to_string()
    } else {
        wire_api
    };
    format!("{provider}:{host}:{wire_api}")
}

pub(super) fn normalize_tier_bucket(raw: &str) -> String {
    let tier = normalized_token(raw);
    if tier.is_empty() {
        return "unknown".to_string();
    }
    if tier.contains("free") {
        return "free".to_string();
    }
    if tier.contains("plus") {
        return "plus".to_string();
    }
    if tier.contains("pro") {
        return "pro".to_string();
    }
    if tier.contains("team") {
        return "team".to_string();
    }
    if tier.contains("enterprise") {
        return "enterprise".to_string();
    }
    if tier.contains("paid") || tier.contains("premium") {
        return "paid".to_string();
    }
    tier
}

pub(super) fn is_paid_tier_bucket(tier: &str) -> bool {
    matches!(
        normalized_token(tier).as_str(),
        "plus" | "pro" | "team" | "enterprise" | "paid"
    )
}

pub(super) fn removal_reason_for_account_state(
    account: &ProviderAccount,
    state: &PoolState,
) -> String {
    let reason = normalized_token(&state.reason_code);
    if state.state == "expired" {
        return if reason.is_empty() {
            "token_expired".to_string()
        } else {
            reason
        };
    }
    if !account.enabled && !reason.is_empty() {
        return reason;
    }
    if matches!(
        reason.as_str(),
        "auth_failed"
            | "blocked_auth"
            | "invalid_api_key"
            | "authentication_failed"
            | "token_expired"
    ) || reason.starts_with("refresh_http_401")
        || reason.starts_with("refresh_http_403")
    {
        return reason;
    }
    String::new()
}

pub(super) fn is_auth_failure_reason(reason_code: &str) -> bool {
    let reason = normalized_token(reason_code);
    matches!(
        reason.as_str(),
        "auth_failed"
            | "blocked_auth"
            | "invalid_api_key"
            | "authentication_failed"
            | "auth_missing"
            | "missing_scope"
            | "scope_missing"
            | "token_expired"
            | "invalid_grant"
            | "invalid_client"
            | "unauthorized_client"
            | "access_denied"
            | "refresh_token_reused"
            | "missing_refresh_token"
    ) || reason.starts_with("refresh_http_401")
        || reason.starts_with("refresh_http_403")
}

pub(super) fn known_quota_for_account(account: &ProviderAccount) -> bool {
    let quota = &account.quota;
    quota.daily_token_cap > 0
        || quota.daily_tokens_used > 0
        || quota.daily_tokens_remaining > 0
        || quota.total_tokens_used > 0
        || quota.last_used_at_ms > 0
        || quota.last_error_at_ms > 0
}

pub(super) fn summarized_pool_state(
    ready_accounts: u32,
    cooldown_accounts: u32,
    blocked_accounts: u32,
    expired_accounts: u32,
    disabled_accounts: u32,
    stale_accounts: u32,
    total_accounts: u32,
) -> String {
    if ready_accounts > 0 {
        return "ready".to_string();
    }
    if cooldown_accounts > 0 {
        return "cooldown".to_string();
    }
    if blocked_accounts > 0 {
        return "blocked".to_string();
    }
    if expired_accounts > 0 && expired_accounts == total_accounts {
        return "expired".to_string();
    }
    if disabled_accounts > 0 && disabled_accounts == total_accounts {
        return "disabled".to_string();
    }
    if stale_accounts > 0 && stale_accounts == total_accounts {
        return "stale".to_string();
    }
    if expired_accounts > 0 {
        return "blocked".to_string();
    }
    if disabled_accounts > 0 {
        return "disabled".to_string();
    }
    if stale_accounts > 0 {
        return "stale".to_string();
    }
    "empty".to_string()
}

pub(super) fn state_sort_weight(state: &str) -> u8 {
    match normalized_token(state).as_str() {
        "ready" => 0,
        "cooldown" => 1,
        "blocked" => 2,
        "expired" => 3,
        "disabled" => 4,
        "stale" => 5,
        _ => 6,
    }
}

pub(super) fn redact_api_key(key: &str) -> String {
    let value = trim_string(key);
    if value.len() <= 8 {
        return "****".to_string();
    }
    format!("{}...{}", &value[..4], &value[value.len() - 4..])
}

pub(super) fn auth_type_or_default(raw: &str) -> String {
    first_non_empty(&[raw]).unwrap_or_else(default_auth_type)
}

pub(super) fn effective_retry_at_ms(account: &ProviderAccount) -> u64 {
    account
        .quota
        .cooldown_until_ms
        .max(account.quota.next_recover_at_ms)
        .max(account.error_state.next_retry_at_ms)
        .max(account.refresh_state.next_refresh_at_ms)
}

pub(super) fn normalized_reason_code(account: &ProviderAccount, fallback: &str) -> Option<String> {
    first_non_empty(&[
        &account.error_state.reason_code,
        &account.error_state.last_error_code,
        fallback,
    ])
}

pub(super) fn status_message(
    account: &ProviderAccount,
    model_state: Option<&ProviderModelState>,
) -> String {
    trim_string(
        &first_non_empty(&[
            model_state
                .map(|state| state.status_message.as_str())
                .unwrap_or(""),
            &account.error_state.status_message,
            &account.refresh_state.last_error_message,
        ])
        .unwrap_or_default(),
    )
}

pub(super) fn retry_at_source(
    account: &ProviderAccount,
    model_state: Option<&ProviderModelState>,
) -> String {
    normalized_token(
        first_non_empty(&[
            model_state
                .map(|state| state.retry_at_source.as_str())
                .unwrap_or(""),
            &account.error_state.retry_at_source,
        ])
        .as_deref()
        .unwrap_or(""),
    )
}

pub(super) fn required_refresh_metadata_for_account(account: &ProviderAccount) -> Vec<String> {
    if normalized_token(&account.auth_type) != "oauth" {
        return Vec::new();
    }
    let source = normalized_token(&account.oauth_source_key);
    let source = if source.is_empty() {
        normalized_token(&account.provider)
    } else {
        source
    };
    let required: &[&str] = match source.as_str() {
        "gemini" | "gemini-cli" | "google" | "antigravity" => {
            &["client_id", "client_secret", "token_uri"]
        }
        _ => &[],
    };
    if required.is_empty() {
        return Vec::new();
    }
    let present: BTreeSet<String> = account
        .oauth_refresh_config
        .keys()
        .map(|key| normalized_token(&key.replace('-', "_")))
        .collect();
    required
        .iter()
        .filter(|field| !present.contains(**field))
        .map(|field| field.to_string())
        .collect()
}
