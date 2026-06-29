use std::collections::BTreeSet;

use serde_json::{json, Map, Value};

use super::*;

pub(super) fn apply_imported_accounts_to_store(
    store_value: &mut Value,
    accounts: &[Value],
    source_kind: &str,
    source_ref: &str,
    prune_owned: bool,
    now_ms: u64,
) -> Result<ImportedAccountApply, ProviderRouteError> {
    ensure_provider_store_shape(store_value);
    let owner_key = import_source_key(source_kind, source_ref);
    let mut imported = 0_u32;
    let mut errors = Vec::new();
    let mut desired_keys = BTreeSet::new();

    for account in accounts {
        match upsert_imported_account_in_store(store_value, account, now_ms) {
            Ok(account_key) => {
                imported = imported.saturating_add(1);
                if !account_key.is_empty() {
                    desired_keys.insert(account_key);
                }
            }
            Err(err) => {
                let label = fallback_if_empty(
                    json_string(account, "source_ref"),
                    &json_string(account, "account_key"),
                );
                errors.push(format!("{label}: {err}"));
            }
        }
    }

    if prune_owned && errors.is_empty() && !owner_key.is_empty() {
        prune_import_source_owned_accounts(store_value, &owner_key, &desired_keys);
    }

    Ok(ImportedAccountApply { imported, errors })
}

fn upsert_imported_account_in_store(
    store_value: &mut Value,
    incoming: &Value,
    now_ms: u64,
) -> Result<String, String> {
    let mut normalized = incoming.clone();
    normalize_imported_account_value(&mut normalized, now_ms).map_err(|_| "invalid_account")?;
    let provider = json_string(&normalized, "provider");
    if provider.is_empty() {
        return Err("invalid_account".to_string());
    }
    let providers = store_value
        .get_mut("providers")
        .and_then(Value::as_object_mut)
        .ok_or_else(|| "missing_providers".to_string())?;
    let provider_value = providers.entry(provider.clone()).or_insert_with(|| {
        json!({
            "routing_strategy": default_routing_strategy(),
            "accounts": [],
        })
    });
    if !provider_value.is_object() {
        *provider_value = json!({
            "routing_strategy": default_routing_strategy(),
            "accounts": [],
        });
    }
    let provider_object = provider_value
        .as_object_mut()
        .ok_or_else(|| "invalid_provider".to_string())?;
    provider_object
        .entry("routing_strategy".to_string())
        .or_insert_with(|| Value::String(default_routing_strategy()));
    if !provider_object
        .get("accounts")
        .map(Value::is_array)
        .unwrap_or(false)
    {
        provider_object.insert("accounts".to_string(), Value::Array(Vec::new()));
    }
    let accounts = provider_object
        .get_mut("accounts")
        .and_then(Value::as_array_mut)
        .ok_or_else(|| "invalid_accounts".to_string())?;

    let incoming_key = json_string(&normalized, "account_key");
    let incoming_source_ref = json_string(&normalized, "source_ref");
    let incoming_api_key = json_string(&normalized, "api_key");
    let existing_idx = accounts.iter().position(|row| {
        json_string(row, "account_key") == incoming_key
            || (!incoming_source_ref.is_empty() && should_match_imported_source(row, &normalized))
            || (!incoming_api_key.is_empty() && json_string(row, "api_key") == incoming_api_key)
    });

    if let Some(idx) = existing_idx {
        update_existing_imported_account(&mut accounts[idx], &normalized, now_ms);
        return Ok(json_string(&accounts[idx], "account_key"));
    }

    if accounts.len() >= 32 {
        return Err("max_accounts_reached".to_string());
    }
    accounts.push(normalized);
    Ok(incoming_key)
}

pub(super) fn normalize_imported_account_value(value: &mut Value, now_ms: u64) -> Result<(), ()> {
    let object = value.as_object_mut().ok_or(())?;
    let provider = normalize_provider(
        object
            .get("provider")
            .and_then(Value::as_str)
            .unwrap_or_default(),
    )
    .ok_or(())?;
    let auth_type = match normalized_token(
        object
            .get("auth_type")
            .and_then(Value::as_str)
            .unwrap_or("api_key"),
    )
    .as_str()
    {
        "oauth" => "oauth",
        "copilot" => "copilot",
        _ => "api_key",
    };
    let api_key = object
        .get("api_key")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string();
    let refresh_token = object
        .get("refresh_token")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string();
    if auth_type == "api_key" && api_key.is_empty() {
        return Err(());
    }
    if auth_type == "oauth" && api_key.is_empty() && refresh_token.is_empty() {
        return Err(());
    }

    let base_url = object
        .get("base_url")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string();
    let proxy_url = object
        .get("proxy_url")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string();
    let wire_api = normalize_wire_api(
        object
            .get("wire_api")
            .and_then(Value::as_str)
            .unwrap_or_default(),
    );
    let provider_host = first_non_empty(&[
        &object
            .get("provider_host")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .trim()
            .to_string(),
        &host_from_url(&base_url),
        &host_from_url(&proxy_url),
        &default_provider_host(&provider),
    ])
    .unwrap_or_default()
    .to_ascii_lowercase();
    let pool_id = first_non_empty(&[&object
        .get("pool_id")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string()])
    .unwrap_or_else(|| {
        let canonical_provider = fallback_if_empty(canonical_pool_provider(&provider), "default");
        let host = fallback_if_empty(provider_host.clone(), "default");
        let wire = fallback_if_empty(wire_api.clone(), "default");
        format!("{canonical_provider}:{host}:{wire}")
    });

    object.insert("provider".to_string(), Value::String(provider.clone()));
    object.insert(
        "auth_type".to_string(),
        Value::String(auth_type.to_string()),
    );
    object.insert("api_key".to_string(), Value::String(api_key));
    object.insert("refresh_token".to_string(), Value::String(refresh_token));
    object.insert("wire_api".to_string(), Value::String(wire_api));
    object.insert("provider_host".to_string(), Value::String(provider_host));
    object.insert("pool_id".to_string(), Value::String(pool_id));
    object
        .entry("account_key".to_string())
        .or_insert_with(|| Value::String(format!("{provider}:{}", stable_short_fingerprint(""))));
    object
        .entry("enabled".to_string())
        .or_insert_with(|| Value::Bool(true));
    object
        .entry("created_at_ms".to_string())
        .or_insert_with(|| json!(now_ms));
    object.insert("updated_at_ms".to_string(), json!(now_ms));
    object
        .entry("last_refresh_at_ms".to_string())
        .or_insert_with(|| json!(0));
    object
        .entry("quota".to_string())
        .or_insert_with(default_quota_value);
    object
        .entry("error_state".to_string())
        .or_insert_with(default_error_state_value);
    object
        .entry("refresh_state".to_string())
        .or_insert_with(default_refresh_state_value);
    object
        .entry("model_states".to_string())
        .or_insert_with(|| Value::Object(Map::new()));
    object
        .entry("models".to_string())
        .or_insert_with(|| Value::Array(Vec::new()));
    let source_owners = string_array_value(object.get("source_owners"));
    object.insert(
        "source_owners".to_string(),
        Value::Array(source_owners.into_iter().map(Value::String).collect()),
    );
    Ok(())
}

fn update_existing_imported_account(existing: &mut Value, incoming: &Value, now_ms: u64) {
    if !existing.is_object() {
        *existing = incoming.clone();
        return;
    }
    let existing_object = existing
        .as_object_mut()
        .expect("existing account is object");
    for key in [
        "email",
        "api_key",
        "refresh_token",
        "base_url",
        "proxy_url",
        "enabled",
        "auth_type",
        "wire_api",
        "provider_host",
        "pool_id",
        "expires_at_ms",
        "tier",
        "custom_headers",
        "models",
        "notes",
        "priority",
        "oauth_refresh_config",
        "auth_index",
    ] {
        if let Some(value) = incoming.get(key) {
            existing_object.insert(key.to_string(), value.clone());
        }
    }
    for key in [
        "account_id",
        "source_type",
        "source_ref",
        "oauth_source_key",
        "last_refresh_at_ms",
    ] {
        let incoming_value = incoming.get(key).cloned().unwrap_or(Value::Null);
        let should_update = match &incoming_value {
            Value::String(value) => !value.trim().is_empty(),
            Value::Number(number) => number.as_u64().unwrap_or(0) > 0,
            _ => !incoming_value.is_null(),
        };
        if should_update {
            existing_object.insert(key.to_string(), incoming_value);
        }
    }
    let mut owners = string_array_value(existing_object.get("source_owners"));
    owners.extend(string_array_value(incoming.get("source_owners")));
    owners.sort();
    owners.dedup();
    existing_object.insert(
        "source_owners".to_string(),
        Value::Array(owners.into_iter().map(Value::String).collect()),
    );
    existing_object
        .entry("created_at_ms".to_string())
        .or_insert_with(|| {
            incoming
                .get("created_at_ms")
                .cloned()
                .unwrap_or(json!(now_ms))
        });
    existing_object.insert("updated_at_ms".to_string(), json!(now_ms));
    existing_object
        .entry("quota".to_string())
        .or_insert_with(default_quota_value);
    existing_object
        .entry("error_state".to_string())
        .or_insert_with(default_error_state_value);
    existing_object
        .entry("refresh_state".to_string())
        .or_insert_with(default_refresh_state_value);
    existing_object
        .entry("model_states".to_string())
        .or_insert_with(|| Value::Object(Map::new()));
}

fn should_match_imported_source(existing: &Value, incoming: &Value) -> bool {
    json_string(existing, "source_type") == json_string(incoming, "source_type")
        && json_string(incoming, "source_type") == "auth_file"
        && json_string(existing, "source_ref") == json_string(incoming, "source_ref")
}

fn prune_import_source_owned_accounts(
    store_value: &mut Value,
    owner_key: &str,
    desired_keys: &BTreeSet<String>,
) {
    let Some(providers) = store_value
        .get_mut("providers")
        .and_then(Value::as_object_mut)
    else {
        return;
    };
    for provider_value in providers.values_mut() {
        let Some(accounts) = provider_value
            .get_mut("accounts")
            .and_then(Value::as_array_mut)
        else {
            continue;
        };
        let mut next = Vec::new();
        for mut account in std::mem::take(accounts) {
            let account_key = json_string(&account, "account_key");
            let mut owners = string_array_value(account.get("source_owners"));
            if !owners.iter().any(|owner| owner == owner_key) {
                next.push(account);
                continue;
            }
            if desired_keys.contains(&account_key) {
                owners.push(owner_key.to_string());
                owners.sort();
                owners.dedup();
                if let Some(object) = account.as_object_mut() {
                    object.insert(
                        "source_owners".to_string(),
                        Value::Array(owners.into_iter().map(Value::String).collect()),
                    );
                }
                next.push(account);
                continue;
            }
            owners.retain(|owner| owner != owner_key);
            if !owners.is_empty() {
                if let Some(object) = account.as_object_mut() {
                    object.insert(
                        "source_owners".to_string(),
                        Value::Array(owners.into_iter().map(Value::String).collect()),
                    );
                }
                next.push(account);
            }
        }
        *accounts = next;
    }
}
