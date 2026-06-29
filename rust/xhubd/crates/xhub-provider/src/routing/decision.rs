use std::collections::BTreeSet;
use std::path::Path;

use super::*;

pub fn build_provider_route_decision(
    store: &ProviderKeyStore,
    request: ProviderRouteRequest,
) -> ProviderRouteDecision {
    let requested_model_id = normalized_model_id_for_routing(&request.model_id);
    let requested_provider = normalize_provider(&request.provider)
        .or_else(|| infer_provider_from_model_id(&request.model_id));

    let Some(requested_provider) = requested_provider else {
        return ProviderRouteDecision {
            requested_provider: String::new(),
            requested_model_id: requested_model_id.clone(),
            resolved_provider: String::new(),
            pool_id: String::new(),
            strategy: default_routing_strategy(),
            routing_strategy: default_routing_strategy(),
            selection_scope: format!("unknown::{requested_model_id}"),
            selected_account_key: String::new(),
            fallback_reason_code: "unknown_model_provider".to_string(),
            available_count: 0,
            total_count: 0,
            candidates: Vec::new(),
            updated_at_ms: request.now_ms,
        };
    };

    let pooled = pooled_provider_rows(store, &requested_provider);
    let strategy = pooled
        .strategy
        .unwrap_or_else(|| default_routing_strategy());
    let scoped_accounts = preferred_accounts_for_model(pooled.accounts, &request.model_id);
    let selection_scope =
        selection_scope_key(&requested_provider, &request.model_id, &scoped_accounts);

    if scoped_accounts.is_empty() {
        return ProviderRouteDecision {
            requested_provider: requested_provider.clone(),
            requested_model_id,
            resolved_provider: requested_provider,
            pool_id: String::new(),
            strategy: strategy.clone(),
            routing_strategy: strategy,
            selection_scope,
            selected_account_key: String::new(),
            fallback_reason_code: "no_keys_for_provider".to_string(),
            available_count: 0,
            total_count: 0,
            candidates: Vec::new(),
            updated_at_ms: request.now_ms,
        };
    }

    let available: Vec<AccountView<'_>> = scoped_accounts
        .iter()
        .filter(|view| {
            account_availability_state(view.account, request.now_ms, &request.model_id).state
                == "ready"
        })
        .cloned()
        .collect();
    let selected = select_account(&available, &strategy, request.now_ms, &request.model_id);
    let selected_key = selected
        .as_ref()
        .map(|view| trim_string(&view.account.account_key))
        .unwrap_or_default();

    let mut candidates: Vec<ProviderRouteCandidate> = scoped_accounts
        .iter()
        .map(|view| {
            let availability =
                account_availability_state(view.account, request.now_ms, &request.model_id);
            let matched_model_state = resolve_account_model_state(view.account, &request.model_id);
            let score = match strategy.as_str() {
                "priority" | "quota-aware" => {
                    score_account(view.account, request.now_ms, &request.model_id)
                }
                "round-robin" => {
                    if availability.state == "ready" {
                        0.0
                    } else {
                        -1e12
                    }
                }
                _ => fill_first_score(view.account, request.now_ms, &request.model_id),
            };
            let selected =
                !selected_key.is_empty() && trim_string(&view.account.account_key) == selected_key;
            let mut candidate = ProviderRouteCandidate {
                account_key: trim_string(&view.account.account_key),
                provider: trim_string(&view.account.provider),
                provider_group: view.provider_group.clone(),
                pool_id: trim_string(&view.account.pool_id),
                provider_host: trim_string(&view.account.provider_host),
                wire_api: trim_string(&view.account.wire_api),
                state: availability.state,
                reason_code: availability.reason_code,
                status_message: status_message(
                    view.account,
                    matched_model_state.as_ref().map(|matched| matched.state),
                ),
                retry_at_ms: availability.retry_at_ms,
                next_retry_at_ms: availability.retry_at_ms,
                retry_at_source: retry_at_source(
                    view.account,
                    matched_model_state.as_ref().map(|matched| matched.state),
                ),
                score: finite_decision_score(score),
                selected,
                models: view.account.models.clone(),
                source_owners: view.account.source_owners.clone(),
                required_refresh_metadata: required_refresh_metadata_for_account(view.account),
                model_state_key: matched_model_state
                    .as_ref()
                    .map(|matched| matched.key.clone())
                    .unwrap_or_default(),
            };
            candidate.reason_code = candidate_reason_code(&candidate);
            candidate
        })
        .collect();

    candidates.sort_by(sort_candidate_decision);
    let fallback_reason_code = if selected.is_some() {
        String::new()
    } else {
        fallback_reason_code(&candidates)
    };
    let resolved_provider = selected
        .as_ref()
        .map(|view| {
            if view.provider_group.is_empty() {
                trim_string(&view.account.provider)
            } else {
                view.provider_group.clone()
            }
        })
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| requested_provider.clone());
    let pool_id = route_pool_id(&scoped_accounts, selected.as_ref());

    ProviderRouteDecision {
        requested_provider,
        requested_model_id,
        resolved_provider,
        pool_id,
        strategy: strategy.clone(),
        routing_strategy: strategy,
        selection_scope,
        selected_account_key: selected_key,
        fallback_reason_code,
        available_count: available.len(),
        total_count: scoped_accounts.len(),
        candidates,
        updated_at_ms: request.now_ms,
    }
}

pub fn route_from_runtime_base_dir(
    runtime_base_dir: &Path,
    request: ProviderRouteRequest,
) -> Result<ProviderRouteDecision, ProviderRouteError> {
    let store = ProviderKeyStore::load_runtime_base_dir(runtime_base_dir)?;
    Ok(build_provider_route_decision(&store, request))
}

fn pooled_provider_rows<'a>(
    store: &'a ProviderKeyStore,
    requested_provider: &str,
) -> PooledProviderRows<'a> {
    let mut accounts = Vec::new();
    let mut strategy = None;
    for provider_id in provider_pool_candidates(requested_provider) {
        let Some(group) = store.providers.get(&provider_id) else {
            continue;
        };
        if strategy.is_none() {
            strategy = Some(valid_routing_strategy(&group.routing_strategy));
        }
        for account in &group.accounts {
            accounts.push(AccountView {
                account,
                provider_group: provider_id.clone(),
            });
        }
    }
    PooledProviderRows { strategy, accounts }
}

#[derive(Debug, Clone)]
struct PooledProviderRows<'a> {
    strategy: Option<String>,
    accounts: Vec<AccountView<'a>>,
}

fn preferred_accounts_for_model<'a>(
    accounts: Vec<AccountView<'a>>,
    model_id: &str,
) -> Vec<AccountView<'a>> {
    let restricted_matching: Vec<_> = accounts
        .iter()
        .filter(|view| {
            !view.account.models.is_empty() && matches_account_model(view.account, model_id)
        })
        .cloned()
        .collect();
    if !restricted_matching.is_empty() {
        return restricted_matching;
    }

    let matching: Vec<_> = accounts
        .iter()
        .filter(|view| matches_account_model(view.account, model_id))
        .cloned()
        .collect();
    if matching.is_empty() {
        accounts
    } else {
        matching
    }
}

fn select_account<'a>(
    accounts: &'a [AccountView<'a>],
    strategy: &str,
    now_ms: u128,
    model_id: &str,
) -> Option<AccountView<'a>> {
    if accounts.is_empty() {
        return None;
    }
    let mut sorted = accounts.to_vec();
    match strategy {
        "round-robin" => return sorted.into_iter().next(),
        "priority" | "quota-aware" => sorted.sort_by(|lhs, rhs| {
            score_account(rhs.account, now_ms, model_id)
                .partial_cmp(&score_account(lhs.account, now_ms, model_id))
                .unwrap_or(std::cmp::Ordering::Equal)
                .then_with(|| {
                    trim_string(&lhs.account.account_key)
                        .cmp(&trim_string(&rhs.account.account_key))
                })
        }),
        _ => sorted.sort_by(|lhs, rhs| {
            fill_first_score(rhs.account, now_ms, model_id)
                .partial_cmp(&fill_first_score(lhs.account, now_ms, model_id))
                .unwrap_or(std::cmp::Ordering::Equal)
                .then_with(|| {
                    trim_string(&lhs.account.account_key)
                        .cmp(&trim_string(&rhs.account.account_key))
                })
        }),
    }
    sorted.into_iter().next()
}

fn score_account(account: &ProviderAccount, now_ms: u128, model_id: &str) -> f64 {
    if account_availability_state(account, now_ms, model_id).state != "ready" {
        return f64::NEG_INFINITY;
    }
    let mut score = 1000.0;
    if matches_account_model(account, model_id) {
        score += 250.0;
    }
    if account.priority > 0 {
        score += account.priority as f64 * 100.0;
    }

    let status = normalized_token(&account.error_state.status);
    if status == "healthy" {
        score += 150.0;
    }
    if status == "rate_limited" || status == "blocked_quota" {
        score -= 500.0;
    }
    if status == "degraded" {
        score -= 200.0;
    }

    if account.quota.daily_token_cap > 0 {
        let usage_ratio =
            account.quota.daily_tokens_used as f64 / account.quota.daily_token_cap as f64;
        score -= (usage_ratio * 300.0).floor();
    }
    if account.quota.consecutive_errors > 0 {
        score -= account.quota.consecutive_errors as f64 * 50.0;
    }
    if effective_retry_at_ms(account) as u128 > now_ms {
        score -= 500.0;
    }
    score
}

fn fill_first_score(account: &ProviderAccount, now_ms: u128, model_id: &str) -> f64 {
    if account_availability_state(account, now_ms, model_id).state != "ready" {
        return f64::NEG_INFINITY;
    }
    let mut score = 0.0;
    if matches_account_model(account, model_id) {
        score += 500.0;
    }

    let status = normalized_token(&account.error_state.status);
    if status.is_empty() || status == "healthy" {
        score += 500.0;
    }
    if status == "degraded" {
        score -= 200.0;
    }
    if status == "rate_limited" || status == "blocked_quota" {
        score -= 400.0;
    }

    if account.quota.consecutive_errors > 0 {
        score -= account.quota.consecutive_errors as f64 * 50.0;
    }
    if account.quota.daily_token_cap > 0 {
        score += (account.quota.daily_tokens_remaining as f64
            / account.quota.daily_token_cap as f64)
            * 100.0;
    }
    let retry_at_ms = effective_retry_at_ms(account);
    if retry_at_ms > 0 && now_ms < retry_at_ms as u128 {
        score -= 500.0;
    }
    score
}

fn selection_scope_key(provider: &str, model_id: &str, accounts: &[AccountView<'_>]) -> String {
    let pool_ids: BTreeSet<String> = accounts
        .iter()
        .map(|view| normalized_token(&view.account.pool_id))
        .filter(|value| !value.is_empty())
        .collect();
    if pool_ids.len() == 1 {
        if let Some(pool_id) = pool_ids.first() {
            return format!("{}::{}", normalized_token(provider), pool_id);
        }
    }
    format!(
        "{}::{}",
        normalized_token(provider),
        normalized_model_id_for_routing(model_id)
    )
}

fn route_pool_id(accounts: &[AccountView<'_>], selected: Option<&AccountView<'_>>) -> String {
    if let Some(selected) = selected {
        let pool_id = trim_string(&selected.account.pool_id);
        if !pool_id.is_empty() {
            return pool_id;
        }
    }
    let pool_ids: BTreeSet<String> = accounts
        .iter()
        .map(|view| trim_string(&view.account.pool_id))
        .filter(|value| !value.is_empty())
        .collect();
    if pool_ids.len() == 1 {
        return pool_ids.first().cloned().unwrap_or_default();
    }
    String::new()
}

fn candidate_reason_code(candidate: &ProviderRouteCandidate) -> String {
    if candidate.selected {
        return "selected_by_scheduler".to_string();
    }
    if candidate.state == "ready" {
        return "lower_ranked_by_strategy".to_string();
    }
    if candidate.reason_code.is_empty() {
        "unavailable".to_string()
    } else {
        normalized_token(&candidate.reason_code)
    }
}

fn fallback_reason_code(candidates: &[ProviderRouteCandidate]) -> String {
    if candidates.is_empty() {
        return "no_keys_for_provider".to_string();
    }
    if candidates
        .iter()
        .all(|candidate| candidate.state == "disabled")
    {
        return "all_keys_disabled".to_string();
    }
    if candidates
        .iter()
        .all(|candidate| candidate.state == "cooldown")
    {
        return "all_keys_in_cooldown".to_string();
    }
    if candidates
        .iter()
        .all(|candidate| candidate.state == "stale")
    {
        return "all_keys_stale".to_string();
    }
    if candidates.iter().all(|candidate| {
        (candidate.state == "blocked" || candidate.state == "disabled")
            && is_auth_failure_reason(&candidate.reason_code)
    }) {
        return "all_keys_auth_blocked".to_string();
    }
    if candidates.iter().all(|candidate| {
        candidate.state == "blocked"
            && matches!(
                candidate.reason_code.as_str(),
                "rate_limited" | "blocked_quota" | "quota_exceeded" | "daily_token_cap_exceeded"
            )
    }) {
        return "all_keys_rate_limited".to_string();
    }
    "all_keys_unavailable".to_string()
}

fn sort_candidate_decision(
    lhs: &ProviderRouteCandidate,
    rhs: &ProviderRouteCandidate,
) -> std::cmp::Ordering {
    if lhs.selected != rhs.selected {
        return rhs.selected.cmp(&lhs.selected);
    }
    let rank_order = availability_sort_rank(&lhs.state).cmp(&availability_sort_rank(&rhs.state));
    if rank_order != std::cmp::Ordering::Equal {
        return rank_order;
    }
    let score_order = rhs
        .score
        .partial_cmp(&lhs.score)
        .unwrap_or(std::cmp::Ordering::Equal);
    if score_order != std::cmp::Ordering::Equal {
        return score_order;
    }
    lhs.account_key.cmp(&rhs.account_key)
}

fn availability_sort_rank(state: &str) -> u8 {
    match normalized_token(state).as_str() {
        "ready" => 0,
        "cooldown" => 1,
        "stale" => 2,
        "blocked" | "expired" => 3,
        "disabled" => 4,
        _ => 5,
    }
}

fn finite_decision_score(value: f64) -> f64 {
    if value.is_finite() {
        value
    } else {
        -1e12
    }
}
