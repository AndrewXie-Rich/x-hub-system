use std::path::Path;

use super::*;

pub fn provider_runtime_snapshot_from_runtime_base_dir(
    runtime_base_dir: &Path,
    provider_filter: &str,
) -> Result<ProviderKeyRuntimeSnapshotResponse, ProviderRouteError> {
    let store = ProviderKeyStore::load_runtime_base_dir(runtime_base_dir)?;
    Ok(provider_runtime_snapshot(&store, provider_filter))
}

pub fn provider_runtime_snapshot(
    store: &ProviderKeyStore,
    provider_filter: &str,
) -> ProviderKeyRuntimeSnapshotResponse {
    let provider_filter = trim_string(provider_filter);
    let mut accounts = Vec::new();
    let mut providers = Vec::new();

    for (provider_id, provider_data) in &store.providers {
        if !provider_filter.is_empty() && provider_id != &provider_filter {
            continue;
        }
        providers.push(ProviderSummarySnapshot {
            provider: provider_id.clone(),
            total_accounts: provider_data.accounts.len() as u32,
            enabled_accounts: provider_data
                .accounts
                .iter()
                .filter(|account| account.enabled)
                .count() as u32,
            routing_strategy: valid_routing_strategy(&provider_data.routing_strategy),
        });
        for account in &provider_data.accounts {
            accounts.push(runtime_account_snapshot(account));
        }
    }

    ProviderKeyRuntimeSnapshotResponse {
        accounts,
        import_source_statuses: import_source_status_snapshots(store),
        updated_at_ms: store.updated_at_ms,
        global_routing_strategy: valid_routing_strategy(&store.routing_strategy),
        providers,
    }
}

fn runtime_account_snapshot(account: &ProviderAccount) -> ProviderKeyRuntimeAccountSnapshot {
    ProviderKeyRuntimeAccountSnapshot {
        account_key: trim_string(&account.account_key),
        provider: trim_string(&account.provider),
        email: trim_string(&account.email),
        enabled: account.enabled,
        auth_type: auth_type_or_default(&account.auth_type),
        tier: trim_string(&account.tier),
        base_url: trim_string(&account.base_url),
        proxy_url: trim_string(&account.proxy_url),
        pool_id: trim_string(&account.pool_id),
        provider_host: trim_string(&account.provider_host),
        wire_api: trim_string(&account.wire_api),
        account_id: trim_string(&account.account_id),
        source_type: trim_string(&account.source_type),
        source_ref: trim_string(&account.source_ref),
        oauth_source_key: trim_string(&account.oauth_source_key),
        auth_index: account.auth_index,
        expires_at_ms: account.expires_at_ms,
        created_at_ms: account.created_at_ms,
        updated_at_ms: account.updated_at_ms,
        last_refresh_at_ms: account.last_refresh_at_ms,
        models: account.models.clone(),
        source_owners: account.source_owners.clone(),
        required_refresh_metadata: required_refresh_metadata_for_account(account),
        quota: quota_snapshot(&account.quota),
        error_state: error_state_snapshot(&account.error_state),
        refresh_state: refresh_state_snapshot(&account.refresh_state),
        model_states: account
            .model_states
            .iter()
            .map(|(key, state)| (key.clone(), model_state_snapshot(state)))
            .collect(),
        api_key_redacted: redact_api_key(&account.api_key),
        notes: trim_string(&account.notes),
        priority: account.priority,
    }
}

fn quota_snapshot(quota: &ProviderQuota) -> ProviderQuotaSnapshot {
    ProviderQuotaSnapshot {
        daily_token_cap: quota.daily_token_cap,
        daily_tokens_used: quota.daily_tokens_used,
        daily_tokens_remaining: quota.daily_tokens_remaining,
        total_tokens_used: quota.total_tokens_used,
        last_used_at_ms: quota.last_used_at_ms,
        last_error_at_ms: quota.last_error_at_ms,
        consecutive_errors: quota.consecutive_errors,
        cooldown_until_ms: quota.cooldown_until_ms,
        usage_windows: quota.usage_windows.clone(),
    }
}

fn error_state_snapshot(error_state: &ProviderErrorState) -> ProviderErrorStateSnapshot {
    ProviderErrorStateSnapshot {
        status: first_non_empty(&[&error_state.status]).unwrap_or_else(|| "healthy".to_string()),
        last_error_code: trim_string(&error_state.last_error_code),
        last_error_at_ms: error_state.last_error_at_ms,
        auto_disabled: error_state.auto_disabled,
        status_message: trim_string(&error_state.status_message),
        reason_code: trim_string(&error_state.reason_code),
        next_retry_at_ms: error_state.next_retry_at_ms,
        retry_at_source: trim_string(&error_state.retry_at_source),
    }
}

fn refresh_state_snapshot(refresh_state: &ProviderRefreshState) -> ProviderRefreshStateSnapshot {
    ProviderRefreshStateSnapshot {
        status: first_non_empty(&[&refresh_state.status]).unwrap_or_else(|| "idle".to_string()),
        last_attempt_at_ms: refresh_state.last_attempt_at_ms,
        last_success_at_ms: refresh_state.last_success_at_ms,
        next_refresh_at_ms: refresh_state.next_refresh_at_ms,
        failure_count: refresh_state.failure_count,
        last_error_code: trim_string(&refresh_state.last_error_code),
        last_error_message: trim_string(&refresh_state.last_error_message),
    }
}

fn model_state_snapshot(state: &ProviderModelState) -> ProviderModelStateSnapshot {
    ProviderModelStateSnapshot {
        status: trim_string(&state.status),
        reason_code: trim_string(&state.reason_code),
        status_message: trim_string(&state.status_message),
        next_retry_at_ms: state.next_retry_at_ms,
        retry_at_source: trim_string(&state.retry_at_source),
        last_error_code: trim_string(&state.last_error_code),
        last_error_at_ms: state.last_error_at_ms,
        updated_at_ms: state.updated_at_ms,
    }
}

fn import_source_status_snapshots(
    store: &ProviderKeyStore,
) -> Vec<ProviderImportSourceStatusSnapshot> {
    store
        .import_source_statuses
        .iter()
        .map(|(source_key, status)| {
            let (fallback_kind, fallback_ref) = parse_import_source_key(source_key);
            ProviderImportSourceStatusSnapshot {
                source_key: source_key.clone(),
                kind: first_non_empty(&[&status.kind, &fallback_kind]).unwrap_or_default(),
                source_ref: first_non_empty(&[&status.source_ref, &fallback_ref])
                    .unwrap_or_default(),
                state: first_non_empty(&[&status.state]).unwrap_or_else(|| "pending".to_string()),
                last_sync_at_ms: status.last_sync_at_ms,
                last_imported_count: status.last_imported_count,
                owned_account_count: status.owned_account_count,
                last_error_count: status.last_error_count.max(status.last_errors.len() as u32),
                last_errors: status.last_errors.clone(),
                updated_at_ms: status.updated_at_ms,
            }
        })
        .collect()
}

fn parse_import_source_key(source_key: &str) -> (String, String) {
    let Some((kind, source_ref)) = source_key.split_once(':') else {
        return (String::new(), String::new());
    };
    (trim_string(kind), trim_string(source_ref))
}
