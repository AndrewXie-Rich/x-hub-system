use std::collections::BTreeSet;

use super::*;

pub fn plan_openai_quota_refresh(
    store: &ProviderKeyStore,
    options: OpenAIQuotaRefreshPlanOptions,
) -> ProviderQuotaRefreshPlanResult {
    let now = options.now_ms;
    let include_skipped = options.include_skipped;
    let in_flight: BTreeSet<String> = options
        .in_flight_account_keys
        .iter()
        .map(|key| trim_string(key))
        .filter(|key| !key.is_empty())
        .collect();

    let mut accounts = Vec::new();
    let mut skipped_accounts = Vec::new();
    let mut total_accounts = 0_u32;
    let mut eligible_accounts = 0_u32;

    for provider_data in store.providers.values() {
        for account in &provider_data.accounts {
            total_accounts = total_accounts.saturating_add(1);
            let account_key = trim_string(&account.account_key);
            let provider = trim_string(&account.provider);
            if account_key.is_empty() {
                push_quota_plan_skip(
                    &mut skipped_accounts,
                    include_skipped,
                    account_key,
                    provider,
                    "missing_account_key",
                    account.quota.next_refresh_at_ms,
                );
                continue;
            }

            let metadata = openai_quota_metadata_for_account(account);
            if !supported_openai_quota_account_with_metadata(account, &metadata) {
                push_quota_plan_skip(
                    &mut skipped_accounts,
                    include_skipped,
                    account_key,
                    provider,
                    "unsupported_quota_metadata",
                    account.quota.next_refresh_at_ms,
                );
                continue;
            }
            eligible_accounts = eligible_accounts.saturating_add(1);

            if in_flight.contains(&account_key) {
                push_quota_plan_skip(
                    &mut skipped_accounts,
                    include_skipped,
                    account_key,
                    provider,
                    "in_flight",
                    account.quota.next_refresh_at_ms,
                );
                continue;
            }
            if !account.enabled {
                push_quota_plan_skip(
                    &mut skipped_accounts,
                    include_skipped,
                    account_key,
                    provider,
                    "disabled",
                    account.quota.next_refresh_at_ms,
                );
                continue;
            }

            let next_refresh_at_ms = account.quota.next_refresh_at_ms;
            if next_refresh_at_ms > 0 && next_refresh_at_ms > now {
                push_quota_plan_skip(
                    &mut skipped_accounts,
                    include_skipped,
                    account_key,
                    provider,
                    "not_due",
                    next_refresh_at_ms,
                );
                continue;
            }

            accounts.push(ProviderQuotaRefreshPlanAccount {
                account_key,
                provider,
                account_id: metadata.account_id,
                oauth_source_key: metadata.oauth_source_key,
                auth_index: account.auth_index,
                next_refresh_at_ms,
                failure_count: account.refresh_state.failure_count,
                last_refresh_at_ms: account
                    .last_refresh_at_ms
                    .max(account.refresh_state.last_success_at_ms),
                priority: account.priority,
                reason_code: if next_refresh_at_ms == 0 {
                    "initial_refresh".to_string()
                } else {
                    "refresh_due".to_string()
                },
            });
        }
    }

    accounts.sort_by(|lhs, rhs| {
        normalize_due_sort_ms(lhs.next_refresh_at_ms)
            .cmp(&normalize_due_sort_ms(rhs.next_refresh_at_ms))
            .then_with(|| rhs.priority.cmp(&lhs.priority))
            .then_with(|| lhs.account_key.cmp(&rhs.account_key))
    });

    let due_accounts = accounts.len().min(u32::MAX as usize) as u32;
    let skipped_count = eligible_accounts.saturating_sub(due_accounts);
    ProviderQuotaRefreshPlanResult {
        ok: true,
        accounts,
        skipped_accounts,
        total_accounts,
        eligible_accounts,
        due_accounts,
        skipped_count,
        updated_at_ms: store.updated_at_ms,
        now_ms: now,
    }
}

pub fn plan_codex_oauth_refresh(
    store: &ProviderKeyStore,
    options: ProviderOAuthRefreshPlanOptions,
) -> ProviderOAuthRefreshPlanResult {
    let now = if options.now_ms == 0 {
        current_time_millis()
    } else {
        options.now_ms
    };
    let include_skipped = options.include_skipped;
    let refresh_lead_ms = if options.refresh_lead_ms == 0 {
        DEFAULT_OAUTH_REFRESH_LEAD_MS
    } else {
        options.refresh_lead_ms
    };
    let min_refresh_lead_ms = if options.min_refresh_lead_ms == 0 {
        DEFAULT_OAUTH_MIN_REFRESH_LEAD_MS
    } else {
        options.min_refresh_lead_ms
    };
    let in_flight: BTreeSet<String> = options
        .in_flight_account_keys
        .iter()
        .map(|key| trim_string(key))
        .filter(|key| !key.is_empty())
        .collect();

    let mut accounts = Vec::new();
    let mut skipped_accounts = Vec::new();
    let mut total_accounts = 0_u32;
    let mut eligible_accounts = 0_u32;

    for provider_data in store.providers.values() {
        for account in &provider_data.accounts {
            total_accounts = total_accounts.saturating_add(1);
            let account_key = trim_string(&account.account_key);
            let provider = trim_string(&account.provider);
            let last_refresh_at_ms = account
                .last_refresh_at_ms
                .max(account.refresh_state.last_success_at_ms);
            let refresh_due_at_ms = oauth_refresh_due_at_ms(
                account.expires_at_ms,
                last_refresh_at_ms,
                refresh_lead_ms,
                min_refresh_lead_ms,
            );

            if account_key.is_empty() {
                push_oauth_plan_skip(
                    &mut skipped_accounts,
                    include_skipped,
                    account_key,
                    provider,
                    "missing_account_key",
                    account.expires_at_ms,
                    refresh_due_at_ms,
                    account.refresh_state.next_refresh_at_ms,
                );
                continue;
            }
            if !supported_codex_oauth_refresh_account(account) {
                push_oauth_plan_skip(
                    &mut skipped_accounts,
                    include_skipped,
                    account_key,
                    provider,
                    "unsupported_refresh_schema",
                    account.expires_at_ms,
                    refresh_due_at_ms,
                    account.refresh_state.next_refresh_at_ms,
                );
                continue;
            }
            eligible_accounts = eligible_accounts.saturating_add(1);

            if in_flight.contains(&account_key) {
                push_oauth_plan_skip(
                    &mut skipped_accounts,
                    include_skipped,
                    account_key,
                    provider,
                    "in_flight",
                    account.expires_at_ms,
                    refresh_due_at_ms,
                    account.refresh_state.next_refresh_at_ms,
                );
                continue;
            }
            if !account.enabled {
                push_oauth_plan_skip(
                    &mut skipped_accounts,
                    include_skipped,
                    account_key,
                    provider,
                    "disabled",
                    account.expires_at_ms,
                    refresh_due_at_ms,
                    account.refresh_state.next_refresh_at_ms,
                );
                continue;
            }
            if trim_string(&account.refresh_token).is_empty() {
                push_oauth_plan_skip(
                    &mut skipped_accounts,
                    include_skipped,
                    account_key,
                    provider,
                    "missing_refresh_token",
                    account.expires_at_ms,
                    refresh_due_at_ms,
                    account.refresh_state.next_refresh_at_ms,
                );
                continue;
            }

            let refresh_status = normalized_token(&account.refresh_state.status);
            if matches!(refresh_status.as_str(), "pending" | "refreshing") {
                push_oauth_plan_skip(
                    &mut skipped_accounts,
                    include_skipped,
                    account_key,
                    provider,
                    "refresh_in_progress",
                    account.expires_at_ms,
                    refresh_due_at_ms,
                    account.refresh_state.next_refresh_at_ms,
                );
                continue;
            }

            let refresh_error_code =
                normalized_oauth_refresh_error_code(&account.refresh_state.last_error_code);
            if refresh_status == "failed" && oauth_refresh_terminal_error(&refresh_error_code) {
                push_oauth_plan_skip(
                    &mut skipped_accounts,
                    include_skipped,
                    account_key,
                    provider,
                    "terminal_refresh_failed",
                    account.expires_at_ms,
                    refresh_due_at_ms,
                    account.refresh_state.next_refresh_at_ms,
                );
                continue;
            }

            let next_refresh_at_ms = account.refresh_state.next_refresh_at_ms;
            if next_refresh_at_ms > 0 && next_refresh_at_ms > now {
                push_oauth_plan_skip(
                    &mut skipped_accounts,
                    include_skipped,
                    account_key,
                    provider,
                    "not_due",
                    account.expires_at_ms,
                    refresh_due_at_ms,
                    next_refresh_at_ms,
                );
                continue;
            }

            let reason_code = if next_refresh_at_ms > 0 && next_refresh_at_ms <= now {
                "retry_due"
            } else if trim_string(&account.api_key).is_empty() {
                "auth_missing"
            } else if account.expires_at_ms == 0 {
                "missing_expiry"
            } else if account.expires_at_ms <= now {
                "token_expired"
            } else if refresh_due_at_ms <= now {
                "expires_soon"
            } else {
                push_oauth_plan_skip(
                    &mut skipped_accounts,
                    include_skipped,
                    account_key,
                    provider,
                    "not_due",
                    account.expires_at_ms,
                    refresh_due_at_ms,
                    next_refresh_at_ms,
                );
                continue;
            };

            accounts.push(ProviderOAuthRefreshPlanAccount {
                account_key,
                provider,
                account_id: trim_string(&account.account_id),
                email: trim_string(&account.email),
                oauth_source_key: trim_string(&account.oauth_source_key),
                auth_index: account.auth_index,
                expires_at_ms: account.expires_at_ms,
                refresh_due_at_ms,
                next_refresh_at_ms,
                failure_count: account.refresh_state.failure_count,
                last_refresh_at_ms,
                priority: account.priority,
                reason_code: reason_code.to_string(),
            });
        }
    }

    accounts.sort_by(|lhs, rhs| {
        oauth_plan_sort_ms(lhs)
            .cmp(&oauth_plan_sort_ms(rhs))
            .then_with(|| rhs.priority.cmp(&lhs.priority))
            .then_with(|| lhs.account_key.cmp(&rhs.account_key))
    });

    let due_accounts = accounts.len().min(u32::MAX as usize) as u32;
    let skipped_count = eligible_accounts.saturating_sub(due_accounts);
    ProviderOAuthRefreshPlanResult {
        ok: true,
        accounts,
        skipped_accounts,
        total_accounts,
        eligible_accounts,
        due_accounts,
        skipped_count,
        refresh_lead_ms,
        min_refresh_lead_ms,
        updated_at_ms: store.updated_at_ms,
        now_ms: now,
    }
}

fn push_quota_plan_skip(
    skipped_accounts: &mut Vec<ProviderQuotaRefreshPlanSkippedAccount>,
    include_skipped: bool,
    account_key: String,
    provider: String,
    reason_code: &str,
    next_refresh_at_ms: u64,
) {
    if !include_skipped {
        return;
    }
    skipped_accounts.push(ProviderQuotaRefreshPlanSkippedAccount {
        account_key,
        provider,
        reason_code: reason_code.to_string(),
        next_refresh_at_ms,
    });
}

fn push_oauth_plan_skip(
    skipped_accounts: &mut Vec<ProviderOAuthRefreshPlanSkippedAccount>,
    include_skipped: bool,
    account_key: String,
    provider: String,
    reason_code: &str,
    expires_at_ms: u64,
    refresh_due_at_ms: u64,
    next_refresh_at_ms: u64,
) {
    if !include_skipped {
        return;
    }
    skipped_accounts.push(ProviderOAuthRefreshPlanSkippedAccount {
        account_key,
        provider,
        reason_code: reason_code.to_string(),
        expires_at_ms,
        refresh_due_at_ms,
        next_refresh_at_ms,
    });
}

fn normalize_due_sort_ms(value: u64) -> u64 {
    if value == 0 {
        0
    } else {
        value
    }
}

fn oauth_plan_sort_ms(account: &ProviderOAuthRefreshPlanAccount) -> u64 {
    if account.next_refresh_at_ms > 0 {
        account.next_refresh_at_ms
    } else {
        account.refresh_due_at_ms
    }
}

fn supported_codex_oauth_refresh_account(account: &ProviderAccount) -> bool {
    if normalized_token(&account.auth_type) != "oauth" {
        return false;
    }
    let provider = normalized_token(&account.provider);
    let source = normalized_token(&account.oauth_source_key);
    matches!(provider.as_str(), "openai" | "codex")
        || matches!(
            source.as_str(),
            "chatgpt" | "openai" | "openai-chatgpt" | "codex"
        )
}

fn oauth_refresh_due_at_ms(
    expires_at_ms: u64,
    last_success_at_ms: u64,
    refresh_lead_ms: u64,
    min_refresh_lead_ms: u64,
) -> u64 {
    if expires_at_ms == 0 {
        return 0;
    }
    expires_at_ms.saturating_sub(effective_oauth_refresh_lead_ms(
        expires_at_ms,
        last_success_at_ms,
        refresh_lead_ms,
        min_refresh_lead_ms,
    ))
}

fn effective_oauth_refresh_lead_ms(
    expires_at_ms: u64,
    last_success_at_ms: u64,
    refresh_lead_ms: u64,
    min_refresh_lead_ms: u64,
) -> u64 {
    let configured_lead_ms = if refresh_lead_ms == 0 {
        DEFAULT_OAUTH_REFRESH_LEAD_MS
    } else {
        refresh_lead_ms
    };
    if last_success_at_ms == 0 || expires_at_ms <= last_success_at_ms {
        return configured_lead_ms;
    }
    let ttl_ms = expires_at_ms.saturating_sub(last_success_at_ms);
    let dynamic_lead_ms = ttl_ms / 5;
    let floor_ms = min_refresh_lead_ms.min(ttl_ms / 2);
    configured_lead_ms.min(dynamic_lead_ms.max(floor_ms))
}
