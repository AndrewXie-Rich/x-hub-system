use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

use super::*;

pub fn provider_key_pools_from_runtime_base_dir(
    runtime_base_dir: &Path,
    provider_filter: &str,
    model_id: &str,
    include_members: bool,
    now_ms: u128,
) -> Result<ProviderKeyPoolSnapshotResponse, ProviderRouteError> {
    let store = ProviderKeyStore::load_runtime_base_dir(runtime_base_dir)?;
    Ok(provider_key_pools(
        &store,
        provider_filter,
        model_id,
        include_members,
        now_ms,
    ))
}

pub fn provider_key_pools(
    store: &ProviderKeyStore,
    provider_filter: &str,
    model_id: &str,
    include_members: bool,
    now_ms: u128,
) -> ProviderKeyPoolSnapshotResponse {
    let model_id = trim_string(model_id);
    let model_family = model_family_key_for_inventory(&model_id);
    let mut pools: BTreeMap<String, MutablePoolSnapshot> = BTreeMap::new();

    for provider_data in store.providers.values() {
        for account in &provider_data.accounts {
            if !provider_matches_pool_filter(account, provider_filter) {
                continue;
            }
            if !account_supports_capability_target(account, &model_id) {
                continue;
            }

            let canonical_provider = canonical_pool_provider(&account.provider);
            let provider = if canonical_provider.is_empty() {
                normalized_token(&account.provider)
            } else {
                canonical_provider
            };
            let pool_id = account_effective_pool_id(account);
            let capability_pool_id = format!("{pool_id}#{provider}:{model_family}");
            let state = account_pool_state(account, now_ms, &model_id);
            let tier_bucket = normalize_tier_bucket(&account.tier);
            let removal_reason = removal_reason_for_account_state(account, &state);
            let quota = &account.quota;
            let last_refresh_at_ms = account
                .last_refresh_at_ms
                .max(account.refresh_state.last_success_at_ms);

            let summary =
                pools
                    .entry(capability_pool_id.clone())
                    .or_insert_with(|| MutablePoolSnapshot {
                        pool_id: pool_id.clone(),
                        capability_pool_id: capability_pool_id.clone(),
                        provider: provider.clone(),
                        provider_host: trim_string(&account.provider_host),
                        wire_api: normalize_wire_api(&account.wire_api),
                        model_id: model_id.clone(),
                        model_family: model_family.clone(),
                        total_accounts: 0,
                        enabled_accounts: 0,
                        ready_accounts: 0,
                        cooldown_accounts: 0,
                        blocked_accounts: 0,
                        expired_accounts: 0,
                        disabled_accounts: 0,
                        stale_accounts: 0,
                        auth_failed_accounts: 0,
                        free_accounts: 0,
                        paid_accounts: 0,
                        unknown_tier_accounts: 0,
                        removable_accounts: 0,
                        known_quota_accounts: 0,
                        daily_token_cap: 0,
                        daily_tokens_used: 0,
                        daily_tokens_remaining: 0,
                        total_tokens_used: 0,
                        next_retry_at_ms: 0,
                        last_used_at_ms: 0,
                        last_refresh_at_ms: 0,
                        reason_counts: BTreeMap::new(),
                        source_providers: BTreeSet::new(),
                        members: Vec::new(),
                    });

            summary.total_accounts = summary.total_accounts.saturating_add(1);
            if account.enabled {
                summary.enabled_accounts = summary.enabled_accounts.saturating_add(1);
            }
            match state.state.as_str() {
                "ready" => summary.ready_accounts = summary.ready_accounts.saturating_add(1),
                "cooldown" => {
                    summary.cooldown_accounts = summary.cooldown_accounts.saturating_add(1)
                }
                "blocked" => summary.blocked_accounts = summary.blocked_accounts.saturating_add(1),
                "expired" => summary.expired_accounts = summary.expired_accounts.saturating_add(1),
                "disabled" => {
                    summary.disabled_accounts = summary.disabled_accounts.saturating_add(1)
                }
                "stale" => summary.stale_accounts = summary.stale_accounts.saturating_add(1),
                _ => {}
            }
            if is_auth_failure_reason(
                &first_non_empty(&[removal_reason.as_str(), state.reason_code.as_str()])
                    .unwrap_or_default(),
            ) {
                summary.auth_failed_accounts = summary.auth_failed_accounts.saturating_add(1);
            }
            if tier_bucket == "free" {
                summary.free_accounts = summary.free_accounts.saturating_add(1);
            } else if is_paid_tier_bucket(&tier_bucket) {
                summary.paid_accounts = summary.paid_accounts.saturating_add(1);
            } else {
                summary.unknown_tier_accounts = summary.unknown_tier_accounts.saturating_add(1);
            }
            if !removal_reason.is_empty() {
                summary.removable_accounts = summary.removable_accounts.saturating_add(1);
            }
            if known_quota_for_account(account) {
                summary.known_quota_accounts = summary.known_quota_accounts.saturating_add(1);
            }

            summary.daily_token_cap = summary
                .daily_token_cap
                .saturating_add(quota.daily_token_cap);
            summary.daily_tokens_used = summary
                .daily_tokens_used
                .saturating_add(quota.daily_tokens_used);
            summary.daily_tokens_remaining = summary
                .daily_tokens_remaining
                .saturating_add(quota.daily_tokens_remaining);
            summary.total_tokens_used = summary
                .total_tokens_used
                .saturating_add(quota.total_tokens_used);
            summary.last_used_at_ms = summary.last_used_at_ms.max(quota.last_used_at_ms);
            summary.last_refresh_at_ms = summary.last_refresh_at_ms.max(last_refresh_at_ms);
            if state.retry_at_ms > now_ms.min(u64::MAX as u128) as u64 {
                summary.next_retry_at_ms = if summary.next_retry_at_ms > 0 {
                    summary.next_retry_at_ms.min(state.retry_at_ms)
                } else {
                    state.retry_at_ms
                };
            }
            if !state.reason_code.is_empty() {
                *summary
                    .reason_counts
                    .entry(state.reason_code.clone())
                    .or_insert(0) += 1;
            }
            let source_provider = trim_string(&account.provider);
            if !source_provider.is_empty() {
                summary.source_providers.insert(source_provider);
            }

            if include_members {
                summary.members.push(ProviderKeyPoolMemberSnapshot {
                    account_key: trim_string(&account.account_key),
                    provider: trim_string(&account.provider),
                    email: trim_string(&account.email),
                    tier: trim_string(&account.tier),
                    enabled: account.enabled,
                    auth_type: trim_string(&account.auth_type),
                    account_id: trim_string(&account.account_id),
                    source_ref: trim_string(&account.source_ref),
                    oauth_source_key: trim_string(&account.oauth_source_key),
                    pool_id: pool_id.clone(),
                    state: state.state.clone(),
                    reason_code: trim_string(&state.reason_code),
                    status_message: trim_string(&state.status_message),
                    retry_at_ms: state.retry_at_ms,
                    expires_at_ms: account.expires_at_ms,
                    last_refresh_at_ms,
                    last_used_at_ms: quota.last_used_at_ms,
                    daily_token_cap: quota.daily_token_cap,
                    daily_tokens_used: quota.daily_tokens_used,
                    daily_tokens_remaining: quota.daily_tokens_remaining,
                    total_tokens_used: quota.total_tokens_used,
                    removable: !removal_reason.is_empty(),
                    removal_reason: removal_reason.clone(),
                    api_key_redacted: redact_api_key(&account.api_key),
                });
            }
        }
    }

    let mut out: Vec<ProviderKeyPoolSnapshot> = pools
        .into_values()
        .map(|mut summary| {
            let mut blocker_reason_codes: Vec<(String, u32)> =
                summary.reason_counts.into_iter().collect();
            blocker_reason_codes
                .sort_by(|lhs, rhs| rhs.1.cmp(&lhs.1).then_with(|| lhs.0.cmp(&rhs.0)));
            summary.members.sort_by(|lhs, rhs| {
                state_sort_weight(&lhs.state)
                    .cmp(&state_sort_weight(&rhs.state))
                    .then_with(|| lhs.retry_at_ms.cmp(&rhs.retry_at_ms))
                    .then_with(|| {
                        first_non_empty(&[&lhs.email, &lhs.account_key])
                            .unwrap_or_default()
                            .cmp(
                                &first_non_empty(&[&rhs.email, &rhs.account_key])
                                    .unwrap_or_default(),
                            )
                    })
            });
            ProviderKeyPoolSnapshot {
                pool_id: summary.pool_id,
                capability_pool_id: summary.capability_pool_id,
                provider: summary.provider,
                provider_host: summary.provider_host,
                wire_api: summary.wire_api,
                model_id: summary.model_id,
                model_family: summary.model_family,
                state: summarized_pool_state(
                    summary.ready_accounts,
                    summary.cooldown_accounts,
                    summary.blocked_accounts,
                    summary.expired_accounts,
                    summary.disabled_accounts,
                    summary.stale_accounts,
                    summary.total_accounts,
                ),
                source_providers: summary.source_providers.into_iter().collect(),
                total_accounts: summary.total_accounts,
                enabled_accounts: summary.enabled_accounts,
                ready_accounts: summary.ready_accounts,
                cooldown_accounts: summary.cooldown_accounts,
                blocked_accounts: summary.blocked_accounts,
                expired_accounts: summary.expired_accounts,
                disabled_accounts: summary.disabled_accounts,
                stale_accounts: summary.stale_accounts,
                auth_failed_accounts: summary.auth_failed_accounts,
                free_accounts: summary.free_accounts,
                paid_accounts: summary.paid_accounts,
                unknown_tier_accounts: summary.unknown_tier_accounts,
                removable_accounts: summary.removable_accounts,
                known_quota_accounts: summary.known_quota_accounts,
                daily_token_cap: summary.daily_token_cap,
                daily_tokens_used: summary.daily_tokens_used,
                daily_tokens_remaining: summary.daily_tokens_remaining,
                total_tokens_used: summary.total_tokens_used,
                next_retry_at_ms: summary.next_retry_at_ms,
                last_used_at_ms: summary.last_used_at_ms,
                last_refresh_at_ms: summary.last_refresh_at_ms,
                blocker_reason_codes: blocker_reason_codes
                    .into_iter()
                    .map(|(reason, _)| reason)
                    .collect(),
                members: if include_members {
                    summary.members
                } else {
                    Vec::new()
                },
            }
        })
        .collect();

    out.sort_by(|lhs, rhs| {
        rhs.ready_accounts
            .cmp(&lhs.ready_accounts)
            .then_with(|| rhs.total_accounts.cmp(&lhs.total_accounts))
            .then_with(|| lhs.capability_pool_id.cmp(&rhs.capability_pool_id))
    });

    ProviderKeyPoolSnapshotResponse {
        pools: out,
        updated_at_ms: store.updated_at_ms,
        routing_strategy: if provider_filter.trim().is_empty() {
            default_routing_strategy()
        } else {
            store
                .providers
                .get(provider_filter)
                .map(|provider| valid_routing_strategy(&provider.routing_strategy))
                .unwrap_or_else(default_routing_strategy)
        },
    }
}
