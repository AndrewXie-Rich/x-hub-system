use std::collections::BTreeSet;
use std::path::Path;

use super::*;

pub fn remote_model_inventory_from_runtime_base_dir(
    runtime_base_dir: &Path,
    now_ms: u128,
) -> Result<Vec<RemoteModelInventoryRow>, ProviderRouteError> {
    let store = ProviderKeyStore::load_runtime_base_dir(runtime_base_dir)?;
    Ok(remote_model_inventory_rows(&store, now_ms))
}

pub fn remote_model_inventory_rows(
    store: &ProviderKeyStore,
    now_ms: u128,
) -> Vec<RemoteModelInventoryRow> {
    let mut specs = BTreeSet::new();
    for (provider_id, provider_data) in &store.providers {
        let provider_group = normalized_token(provider_id);
        if provider_group.is_empty() {
            continue;
        }
        if provider_data.accounts.is_empty() {
            specs.insert((provider_group.clone(), "*".to_string()));
            continue;
        }
        for account in &provider_data.accounts {
            let provider =
                normalize_provider(&account.provider).unwrap_or_else(|| provider_group.clone());
            if account.models.is_empty() {
                specs.insert((provider, "*".to_string()));
                continue;
            }
            for model in &account.models {
                let model_id = normalized_model_id_for_routing(model);
                if !model_id.is_empty() {
                    specs.insert((provider.clone(), model_id));
                }
            }
        }
    }

    specs
        .into_iter()
        .map(|(provider, model_id)| {
            let decision = build_provider_route_decision(
                store,
                ProviderRouteRequest {
                    model_id: model_id.clone(),
                    provider: provider.clone(),
                    now_ms,
                },
            );
            remote_inventory_row_from_decision(provider, model_id, &decision)
        })
        .collect()
}

fn remote_inventory_row_from_decision(
    provider: String,
    model_id: String,
    decision: &ProviderRouteDecision,
) -> RemoteModelInventoryRow {
    let selected_candidate = decision
        .candidates
        .iter()
        .find(|candidate| candidate.selected);
    let provider_host = selected_candidate
        .and_then(|candidate| {
            let host = trim_string(&candidate.provider_host);
            if host.is_empty() {
                None
            } else {
                Some(host)
            }
        })
        .or_else(|| {
            decision.candidates.iter().find_map(|candidate| {
                let host = trim_string(&candidate.provider_host);
                if host.is_empty() {
                    None
                } else {
                    Some(host)
                }
            })
        })
        .unwrap_or_default();
    let pool_id = if decision.pool_id.is_empty() {
        selected_candidate
            .map(|candidate| trim_string(&candidate.pool_id))
            .unwrap_or_default()
    } else {
        decision.pool_id.clone()
    };
    let next_retry_at_ms = decision
        .candidates
        .iter()
        .map(|candidate| candidate.next_retry_at_ms.max(candidate.retry_at_ms))
        .filter(|value| *value > 0)
        .min()
        .unwrap_or(0);
    let blocking_reason_code = if decision.selected_account_key.is_empty() {
        decision.fallback_reason_code.clone()
    } else {
        String::new()
    };

    RemoteModelInventoryRow {
        model_id: normalized_model_id_for_routing(&model_id),
        provider,
        provider_host,
        family_key: model_family_key_for_inventory(&model_id),
        pool_id,
        availability_state: remote_inventory_availability_state(decision),
        available_account_count: decision.available_count,
        total_account_count: decision.total_count,
        blocking_reason_code,
        next_retry_at_ms,
    }
}

fn remote_inventory_availability_state(decision: &ProviderRouteDecision) -> String {
    if !decision.selected_account_key.is_empty() || decision.available_count > 0 {
        return "ready".to_string();
    }
    match decision.fallback_reason_code.as_str() {
        "no_keys_for_provider" => "missing".to_string(),
        "all_keys_disabled" => "disabled".to_string(),
        "all_keys_in_cooldown" => "cooldown".to_string(),
        "all_keys_stale" => "stale".to_string(),
        _ if decision.total_count == 0 => "missing".to_string(),
        _ => "blocked".to_string(),
    }
}
