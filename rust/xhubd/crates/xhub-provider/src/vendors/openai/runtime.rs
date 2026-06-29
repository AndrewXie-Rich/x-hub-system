use std::path::Path;

use serde_json::Value;

use super::*;

pub fn plan_openai_quota_refresh_from_runtime_base_dir(
    runtime_base_dir: &Path,
    options: OpenAIQuotaRefreshPlanOptions,
) -> Result<ProviderQuotaRefreshPlanResult, ProviderRouteError> {
    let store = ProviderKeyStore::load_runtime_base_dir(runtime_base_dir)?;
    Ok(plan_openai_quota_refresh(&store, options))
}

pub fn plan_codex_oauth_refresh_from_runtime_base_dir(
    runtime_base_dir: &Path,
    options: ProviderOAuthRefreshPlanOptions,
) -> Result<ProviderOAuthRefreshPlanResult, ProviderRouteError> {
    let store = ProviderKeyStore::load_runtime_base_dir(runtime_base_dir)?;
    Ok(plan_codex_oauth_refresh(&store, options))
}

pub fn record_openai_quota_refresh_failure_to_runtime_base_dir(
    runtime_base_dir: &Path,
    options: OpenAIQuotaRefreshFailureOptions,
) -> Result<ProviderQuotaRefreshFailureResult, ProviderRouteError> {
    let account_key = trim_string(&options.account_key);
    if account_key.is_empty() {
        return Err(ProviderRouteError::Invalid(
            "missing account_key for quota failure".to_string(),
        ));
    }
    let store_path = runtime_base_dir.join(PROVIDER_STORE_FILE_NAME);
    let mut store_value = load_provider_store_value_for_write(&store_path)?;
    let providers = store_value
        .get_mut("providers")
        .and_then(Value::as_object_mut)
        .ok_or_else(|| ProviderRouteError::Invalid("missing providers map".to_string()))?;

    let mut recorded = None;
    'providers: for provider_value in providers.values_mut() {
        let Some(accounts) = provider_value
            .get_mut("accounts")
            .and_then(Value::as_array_mut)
        else {
            continue;
        };
        for account_value in accounts {
            if json_string(account_value, "account_key") != account_key {
                continue;
            }
            recorded = Some(record_openai_quota_refresh_failure_to_account(
                account_value,
                &account_key,
                &options,
            )?);
            break 'providers;
        }
    }

    let result = recorded.ok_or_else(|| {
        ProviderRouteError::Invalid(format!(
            "account not found for quota failure: {account_key}"
        ))
    })?;
    set_json_u64_object(&mut store_value, "updated_at_ms", result.failed_at_ms);
    write_provider_store_value_atomic(&store_path, &store_value)?;
    Ok(result)
}

pub fn apply_provider_oauth_refresh_to_runtime_base_dir(
    runtime_base_dir: &Path,
    options: ProviderOAuthRefreshApplyOptions,
) -> Result<ProviderOAuthRefreshResult, ProviderRouteError> {
    let account_key = trim_string(&options.account_key);
    if account_key.is_empty() {
        return Err(ProviderRouteError::Invalid(
            "missing account_key for oauth refresh apply".to_string(),
        ));
    }
    if trim_string(&options.access_token).is_empty() {
        return Err(ProviderRouteError::Invalid(
            "missing access_token for oauth refresh apply".to_string(),
        ));
    }
    let refreshed_at_ms = if options.refreshed_at_ms == 0 {
        current_time_millis()
    } else {
        options.refreshed_at_ms
    };
    if options.expires_at_ms > 0 && options.expires_at_ms <= refreshed_at_ms {
        return Err(ProviderRouteError::Invalid(
            "expired oauth token response".to_string(),
        ));
    }

    let store_path = runtime_base_dir.join(PROVIDER_STORE_FILE_NAME);
    let mut store_value = load_provider_store_value_for_write(&store_path)?;
    let providers = store_value
        .get_mut("providers")
        .and_then(Value::as_object_mut)
        .ok_or_else(|| ProviderRouteError::Invalid("missing providers map".to_string()))?;

    let mut applied = None;
    'providers: for provider_value in providers.values_mut() {
        let Some(accounts) = provider_value
            .get_mut("accounts")
            .and_then(Value::as_array_mut)
        else {
            continue;
        };
        for account_value in accounts {
            if json_string(account_value, "account_key") != account_key {
                continue;
            }
            applied = Some(apply_provider_oauth_refresh_to_account(
                account_value,
                &account_key,
                &options,
                refreshed_at_ms,
            )?);
            break 'providers;
        }
    }

    let result = applied.ok_or_else(|| {
        ProviderRouteError::Invalid(format!(
            "account not found for oauth refresh apply: {account_key}"
        ))
    })?;
    set_json_u64_object(&mut store_value, "updated_at_ms", result.refreshed_at_ms);
    write_provider_store_value_atomic(&store_path, &store_value)?;
    Ok(result)
}

pub fn record_provider_oauth_refresh_failure_to_runtime_base_dir(
    runtime_base_dir: &Path,
    options: ProviderOAuthRefreshFailureOptions,
) -> Result<ProviderOAuthRefreshResult, ProviderRouteError> {
    let account_key = trim_string(&options.account_key);
    if account_key.is_empty() {
        return Err(ProviderRouteError::Invalid(
            "missing account_key for oauth refresh failure".to_string(),
        ));
    }

    let store_path = runtime_base_dir.join(PROVIDER_STORE_FILE_NAME);
    let mut store_value = load_provider_store_value_for_write(&store_path)?;
    let providers = store_value
        .get_mut("providers")
        .and_then(Value::as_object_mut)
        .ok_or_else(|| ProviderRouteError::Invalid("missing providers map".to_string()))?;

    let mut recorded = None;
    'providers: for provider_value in providers.values_mut() {
        let Some(accounts) = provider_value
            .get_mut("accounts")
            .and_then(Value::as_array_mut)
        else {
            continue;
        };
        for account_value in accounts {
            if json_string(account_value, "account_key") != account_key {
                continue;
            }
            recorded = Some(record_provider_oauth_refresh_failure_to_account(
                account_value,
                &account_key,
                &options,
            )?);
            break 'providers;
        }
    }

    let result = recorded.ok_or_else(|| {
        ProviderRouteError::Invalid(format!(
            "account not found for oauth refresh failure: {account_key}"
        ))
    })?;
    set_json_u64_object(&mut store_value, "updated_at_ms", result.refreshed_at_ms);
    write_provider_store_value_atomic(&store_path, &store_value)?;
    Ok(result)
}

pub fn apply_openai_quota_usage_to_runtime_base_dir(
    runtime_base_dir: &Path,
    usage: Value,
    options: OpenAIQuotaApplyOptions,
) -> Result<ProviderQuotaRefreshApplyResult, ProviderRouteError> {
    let account_key = trim_string(&options.account_key);
    if account_key.is_empty() {
        return Err(ProviderRouteError::Invalid(
            "missing account_key for quota apply".to_string(),
        ));
    }
    let store_path = runtime_base_dir.join(PROVIDER_STORE_FILE_NAME);
    let mut store_value = load_provider_store_value_for_write(&store_path)?;
    let providers = store_value
        .get_mut("providers")
        .and_then(Value::as_object_mut)
        .ok_or_else(|| ProviderRouteError::Invalid("missing providers map".to_string()))?;

    let mut applied = None;
    'providers: for provider_value in providers.values_mut() {
        let Some(accounts) = provider_value
            .get_mut("accounts")
            .and_then(Value::as_array_mut)
        else {
            continue;
        };
        for account_value in accounts {
            if json_string(account_value, "account_key") != account_key {
                continue;
            }
            applied = Some(apply_openai_quota_usage_to_account(
                account_value,
                &usage,
                &options,
                &account_key,
            )?);
            break 'providers;
        }
    }

    let result = applied.ok_or_else(|| {
        ProviderRouteError::Invalid(format!("account not found for quota apply: {account_key}"))
    })?;
    set_json_u64_object(&mut store_value, "updated_at_ms", result.refreshed_at_ms);
    write_provider_store_value_atomic(&store_path, &store_value)?;
    Ok(result)
}
