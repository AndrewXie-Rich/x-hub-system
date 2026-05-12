use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

use serde::de::DeserializeOwned;
use serde::{Deserialize, Deserializer, Serialize};

pub const PROVIDER_ROUTE_SCHEMA_VERSION: &str = "xhub.provider_route_decision.v1";
pub const PROVIDER_STORE_FILE_NAME: &str = "hub_provider_keys.json";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RemoteModelInventoryRow {
    pub model_id: String,
    pub provider: String,
    pub provider_host: String,
    pub family_key: String,
    pub pool_id: String,
    pub availability_state: String,
    pub available_account_count: usize,
    pub total_account_count: usize,
    pub blocking_reason_code: String,
    pub next_retry_at_ms: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ProviderRouteDecision {
    pub requested_provider: String,
    pub requested_model_id: String,
    pub resolved_provider: String,
    pub pool_id: String,
    pub strategy: String,
    pub routing_strategy: String,
    pub selection_scope: String,
    pub selected_account_key: String,
    pub fallback_reason_code: String,
    pub available_count: usize,
    pub total_count: usize,
    pub candidates: Vec<ProviderRouteCandidate>,
    pub updated_at_ms: u128,
}

impl ProviderRouteDecision {
    pub fn unavailable(reason_code: &str) -> Self {
        Self {
            requested_provider: String::new(),
            requested_model_id: String::new(),
            resolved_provider: String::new(),
            pool_id: String::new(),
            strategy: "fill-first".to_string(),
            routing_strategy: "fill-first".to_string(),
            selection_scope: String::new(),
            selected_account_key: String::new(),
            fallback_reason_code: reason_code.to_string(),
            available_count: 0,
            total_count: 0,
            candidates: Vec::new(),
            updated_at_ms: 0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ProviderRouteCandidate {
    pub account_key: String,
    pub provider: String,
    pub provider_group: String,
    pub pool_id: String,
    pub provider_host: String,
    pub wire_api: String,
    pub state: String,
    pub reason_code: String,
    pub status_message: String,
    pub retry_at_ms: u64,
    pub next_retry_at_ms: u64,
    pub retry_at_source: String,
    pub score: f64,
    pub selected: bool,
    pub models: Vec<String>,
    pub source_owners: Vec<String>,
    pub required_refresh_metadata: Vec<String>,
    pub model_state_key: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderRouteRequest {
    pub model_id: String,
    #[serde(default)]
    pub provider: String,
    pub now_ms: u128,
}

#[derive(Debug, Clone)]
pub enum ProviderRouteError {
    Io(String),
    Json(String),
}

impl std::fmt::Display for ProviderRouteError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ProviderRouteError::Io(message) => write!(f, "provider store io error: {message}"),
            ProviderRouteError::Json(message) => write!(f, "provider store json error: {message}"),
        }
    }
}

impl std::error::Error for ProviderRouteError {}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct ProviderKeyStore {
    #[serde(default = "default_routing_strategy")]
    pub routing_strategy: String,
    #[serde(default)]
    pub providers: BTreeMap<String, ProviderData>,
}

impl ProviderKeyStore {
    pub fn empty() -> Self {
        Self {
            routing_strategy: default_routing_strategy(),
            providers: BTreeMap::new(),
        }
    }

    pub fn load_runtime_base_dir(runtime_base_dir: &Path) -> Result<Self, ProviderRouteError> {
        if runtime_base_dir.as_os_str().is_empty() {
            return Ok(Self::empty());
        }
        Self::load_file(runtime_base_dir.join(PROVIDER_STORE_FILE_NAME))
    }

    pub fn load_file(path: impl Into<PathBuf>) -> Result<Self, ProviderRouteError> {
        let path = path.into();
        if !path.is_file() {
            return Ok(Self::empty());
        }
        let raw = fs::read_to_string(&path)
            .map_err(|err| ProviderRouteError::Io(format!("{}: {err}", path.display())))?;
        serde_json::from_str(&raw)
            .map_err(|err| ProviderRouteError::Json(format!("{}: {err}", path.display())))
    }
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct ProviderData {
    #[serde(default = "default_routing_strategy")]
    pub routing_strategy: String,
    #[serde(default, deserialize_with = "deserialize_vec_or_default")]
    pub accounts: Vec<ProviderAccount>,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct ProviderAccount {
    #[serde(default)]
    pub account_key: String,
    #[serde(default)]
    pub provider: String,
    #[serde(default)]
    pub pool_id: String,
    #[serde(default)]
    pub provider_host: String,
    #[serde(default)]
    pub wire_api: String,
    #[serde(default = "default_enabled")]
    pub enabled: bool,
    #[serde(default)]
    pub api_key: String,
    #[serde(default)]
    pub refresh_token: String,
    #[serde(default = "default_auth_type")]
    pub auth_type: String,
    #[serde(default)]
    pub expires_at_ms: u64,
    #[serde(default)]
    pub priority: u32,
    #[serde(default, deserialize_with = "deserialize_vec_or_default")]
    pub models: Vec<String>,
    #[serde(default, deserialize_with = "deserialize_vec_or_default")]
    pub source_owners: Vec<String>,
    #[serde(default)]
    pub quota: ProviderQuota,
    #[serde(default)]
    pub error_state: ProviderErrorState,
    #[serde(default)]
    pub refresh_state: ProviderRefreshState,
    #[serde(default, deserialize_with = "deserialize_map_or_default")]
    pub model_states: BTreeMap<String, ProviderModelState>,
    #[serde(default)]
    pub oauth_source_key: String,
    #[serde(default, deserialize_with = "deserialize_map_or_default")]
    pub oauth_refresh_config: BTreeMap<String, serde_json::Value>,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct ProviderQuota {
    #[serde(default)]
    pub daily_token_cap: u64,
    #[serde(default)]
    pub daily_tokens_used: u64,
    #[serde(default)]
    pub daily_tokens_remaining: u64,
    #[serde(default)]
    pub cooldown_until_ms: u64,
    #[serde(default)]
    pub next_recover_at_ms: u64,
    #[serde(default)]
    pub consecutive_errors: u32,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct ProviderErrorState {
    #[serde(default)]
    pub status: String,
    #[serde(default)]
    pub reason_code: String,
    #[serde(default)]
    pub last_error_code: String,
    #[serde(default)]
    pub status_message: String,
    #[serde(default)]
    pub next_retry_at_ms: u64,
    #[serde(default)]
    pub retry_at_source: String,
    #[serde(default)]
    pub auto_disabled: bool,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct ProviderRefreshState {
    #[serde(default)]
    pub status: String,
    #[serde(default)]
    pub last_error_code: String,
    #[serde(default)]
    pub last_error_message: String,
    #[serde(default)]
    pub next_refresh_at_ms: u64,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct ProviderModelState {
    #[serde(default)]
    pub model_id: String,
    #[serde(default)]
    pub status: String,
    #[serde(default)]
    pub reason_code: String,
    #[serde(default)]
    pub last_error_code: String,
    #[serde(default)]
    pub status_message: String,
    #[serde(default)]
    pub next_retry_at_ms: u64,
    #[serde(default)]
    pub retry_at_source: String,
}

#[derive(Debug, Clone)]
struct AccountView<'a> {
    account: &'a ProviderAccount,
    provider_group: String,
}

#[derive(Debug, Clone)]
struct Availability {
    state: String,
    reason_code: String,
    retry_at_ms: u64,
}

#[derive(Debug, Clone)]
struct ModelStateMatch<'a> {
    key: String,
    state: &'a ProviderModelState,
}

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

pub fn infer_provider_from_model_id(model_id: &str) -> Option<String> {
    let candidates = model_lookup_keys(model_id);
    if candidates.is_empty() {
        return None;
    }

    for lower in &candidates {
        if lower.starts_with("openai/") {
            return Some("openai".to_string());
        }
        if lower.starts_with("codex/") {
            return Some("codex".to_string());
        }
    }

    for (provider, patterns) in provider_model_map() {
        for lower in &candidates {
            for pattern in *patterns {
                if lower.starts_with(pattern) || lower.contains(pattern) {
                    return Some((*provider).to_string());
                }
            }
        }
    }

    for lower in &candidates {
        if lower.starts_with("gpt-")
            || lower.starts_with("o1")
            || lower.starts_with("o3")
            || lower.starts_with("o4")
        {
            return Some("openai".to_string());
        }
        if lower.starts_with("claude") {
            return Some("claude".to_string());
        }
        if lower.starts_with("gemini") {
            return Some("gemini".to_string());
        }
        if lower.starts_with("deepseek") {
            return Some("openai".to_string());
        }
        if lower.starts_with("qwen") {
            return Some("qwen".to_string());
        }
    }

    None
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

fn account_availability_state(
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
            "cooldown",
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

fn availability(state: &str, reason_code: &str, retry_at_ms: u64) -> Availability {
    Availability {
        state: state.to_string(),
        reason_code: normalized_token(reason_code),
        retry_at_ms,
    }
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

fn matches_account_model(account: &ProviderAccount, model_id: &str) -> bool {
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

fn resolve_account_model_state<'a>(
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

fn model_state_output_key(map_key: &str, state: &ProviderModelState) -> String {
    let raw = first_non_empty(&[&state.model_id, map_key]).unwrap_or_default();
    normalized_model_id_for_routing(&raw)
}

fn availability_from_model_state(model_state: &ProviderModelState) -> Option<Availability> {
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

fn effective_retry_at_ms(account: &ProviderAccount) -> u64 {
    account
        .quota
        .cooldown_until_ms
        .max(account.quota.next_recover_at_ms)
        .max(account.error_state.next_retry_at_ms)
        .max(account.refresh_state.next_refresh_at_ms)
}

fn normalized_reason_code(account: &ProviderAccount, fallback: &str) -> Option<String> {
    first_non_empty(&[
        &account.error_state.reason_code,
        &account.error_state.last_error_code,
        fallback,
    ])
}

fn status_message(account: &ProviderAccount, model_state: Option<&ProviderModelState>) -> String {
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

fn retry_at_source(account: &ProviderAccount, model_state: Option<&ProviderModelState>) -> String {
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

fn required_refresh_metadata_for_account(account: &ProviderAccount) -> Vec<String> {
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
            && matches!(
                candidate.reason_code.as_str(),
                "auth_failed" | "blocked_auth" | "missing_scope" | "token_expired" | "auth_missing"
            )
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

pub fn normalized_model_id_for_routing(model_id: &str) -> String {
    canonical_model_alias(&normalized_token(model_id))
}

pub fn normalized_selection_scope_for_compare(selection_scope: &str) -> String {
    let token = normalized_token(selection_scope);
    let Some((provider, scope)) = token.split_once("::") else {
        return token;
    };
    let normalized_scope = normalized_model_id_for_routing(scope);
    if normalized_scope == scope {
        token
    } else {
        format!("{provider}::{normalized_scope}")
    }
}

pub fn model_family_key_for_inventory(model_id: &str) -> String {
    let model_id = normalized_model_id_for_routing(model_id);
    if model_id.is_empty() || model_id == "*" {
        return "all".to_string();
    }
    if model_id.contains("gpt-5.4") {
        return "gpt-5.4".to_string();
    }
    if model_id.starts_with("gpt-5.3-codex")
        || model_id.starts_with("gpt-5-codex")
        || model_id.contains("codex")
    {
        return "gpt-5-codex".to_string();
    }
    if model_id.starts_with("gpt-5") {
        return "gpt-5".to_string();
    }
    if model_id.starts_with("gpt-4") || model_id.starts_with("gpt-4o") {
        return "gpt-4".to_string();
    }
    if model_id.starts_with("o1") || model_id.starts_with("o3") || model_id.starts_with("o4") {
        return "o-series".to_string();
    }
    for family in [
        "claude",
        "gemini",
        "qwen",
        "kiro",
        "copilot",
        "iflow",
        "antigravity",
    ] {
        if model_id.starts_with(family) {
            return family.to_string();
        }
    }
    model_id
}

fn model_lookup_keys(model_id: &str) -> Vec<String> {
    let raw = normalized_token(model_id);
    if raw.is_empty() {
        return Vec::new();
    }
    let mut out = Vec::new();
    let mut seen = BTreeSet::new();
    push_unique(&mut out, &mut seen, &raw);
    push_model_aliases(&mut out, &mut seen, &raw);
    if raw.contains('/') {
        let parts: Vec<String> = raw
            .split('/')
            .map(normalized_token)
            .filter(|value| !value.is_empty())
            .collect();
        for part in &parts {
            push_unique(&mut out, &mut seen, part);
            push_model_aliases(&mut out, &mut seen, part);
        }
        if let Some(last) = parts.last() {
            push_unique(&mut out, &mut seen, last);
            push_model_aliases(&mut out, &mut seen, last);
        }
    }
    if let Some(stripped) = raw.strip_prefix("models/") {
        push_unique(&mut out, &mut seen, stripped);
        push_model_aliases(&mut out, &mut seen, stripped);
    }
    out
}

fn push_model_aliases(out: &mut Vec<String>, seen: &mut BTreeSet<String>, raw: &str) {
    let canonical = canonical_model_alias(raw);
    push_unique(out, seen, &canonical);
    if let Some(compact) = compact_openai_gpt_alias(&canonical) {
        push_unique(out, seen, &compact);
    }
}

fn canonical_model_alias(raw: &str) -> String {
    let mut token = normalized_token(raw);
    if let Some(stripped) = token.strip_prefix("models/") {
        token = stripped.to_string();
    }
    if let Some(stripped) = token.strip_prefix("openai/") {
        token = stripped.to_string();
    }

    if let Some(rest) = token.strip_prefix("gpt") {
        if !rest.is_empty() && rest.chars().next().is_some_and(|ch| ch.is_ascii_digit()) {
            return format!("gpt-{rest}");
        }
    }
    token
}

fn compact_openai_gpt_alias(raw: &str) -> Option<String> {
    let token = normalized_token(raw);
    let rest = token.strip_prefix("gpt-")?;
    if !rest.is_empty() && rest.chars().next().is_some_and(|ch| ch.is_ascii_digit()) {
        return Some(format!("gpt{rest}"));
    }
    None
}

fn push_unique(out: &mut Vec<String>, seen: &mut BTreeSet<String>, raw: &str) {
    let token = normalized_token(raw);
    if token.is_empty() || seen.contains(&token) {
        return;
    }
    seen.insert(token.clone());
    out.push(token);
}

fn provider_pool_candidates(provider: &str) -> Vec<String> {
    match normalized_token(provider).as_str() {
        "openai" => vec!["openai".to_string(), "codex".to_string()],
        "codex" => vec!["codex".to_string(), "openai".to_string()],
        other if !other.is_empty() => vec![other.to_string()],
        _ => Vec::new(),
    }
}

fn provider_model_map() -> &'static [(&'static str, &'static [&'static str])] {
    &[
        (
            "openai",
            &[
                "gpt-",
                "gpt-4",
                "gpt-4o",
                "gpt-4-turbo",
                "gpt-3.5-turbo",
                "o1",
                "o1-mini",
                "o3",
                "o3-mini",
                "o4",
                "o4-mini",
                "chatgpt",
                "dall-e",
                "deepseek",
            ],
        ),
        (
            "claude",
            &[
                "claude-3.5-sonnet",
                "claude-3-opus",
                "claude-3-haiku",
                "claude-3.5-haiku",
                "claude-sonnet-4",
                "claude-opus-4",
            ],
        ),
        (
            "gemini",
            &[
                "gemini-1.5-pro",
                "gemini-1.5-flash",
                "gemini-2.0-flash",
                "gemini-2.5-pro",
                "gemini-2.5-flash",
            ],
        ),
        (
            "codex",
            &["codex", "gpt-5.3-codex", "gpt-5-codex", "codex-mini"],
        ),
        ("kiro", &["kiro"]),
        ("copilot", &["copilot", "gpt-4", "gpt-4o", "o1", "o3-mini"]),
        ("antigravity", &["antigravity"]),
        ("qwen", &["qwen-turbo", "qwen-plus", "qwen-max", "qwen-vl"]),
        ("iflow", &["iflow"]),
        ("custom", &[]),
    ]
}

fn normalize_provider(raw: &str) -> Option<String> {
    let token = normalized_token(raw);
    let provider = match token.as_str() {
        "openai-chatgpt" | "chatgpt" => "codex",
        "github-copilot" => "copilot",
        "openai" | "claude" | "gemini" | "codex" | "kiro" | "copilot" | "antigravity" | "qwen"
        | "iflow" | "custom" => token.as_str(),
        _ => return None,
    };
    Some(provider.to_string())
}

fn valid_routing_strategy(raw: &str) -> String {
    match normalized_token(raw).as_str() {
        "round-robin" => "round-robin".to_string(),
        "priority" => "priority".to_string(),
        "quota-aware" => "quota-aware".to_string(),
        _ => default_routing_strategy(),
    }
}

fn first_non_empty(values: &[&str]) -> Option<String> {
    for value in values {
        let trimmed = trim_string(value);
        if !trimmed.is_empty() {
            return Some(trimmed);
        }
    }
    None
}

fn normalized_token(raw: &str) -> String {
    raw.trim().to_lowercase()
}

fn trim_string(raw: &str) -> String {
    raw.trim().to_string()
}

fn default_routing_strategy() -> String {
    "fill-first".to_string()
}

fn default_enabled() -> bool {
    true
}

fn default_auth_type() -> String {
    "api_key".to_string()
}

fn deserialize_vec_or_default<'de, D, T>(deserializer: D) -> Result<Vec<T>, D::Error>
where
    D: Deserializer<'de>,
    T: DeserializeOwned,
{
    Option::<Vec<T>>::deserialize(deserializer).map(|value| value.unwrap_or_default())
}

fn deserialize_map_or_default<'de, D, T>(deserializer: D) -> Result<BTreeMap<String, T>, D::Error>
where
    D: Deserializer<'de>,
    T: DeserializeOwned,
{
    Option::<BTreeMap<String, T>>::deserialize(deserializer).map(|value| value.unwrap_or_default())
}

#[cfg(test)]
mod tests {
    use super::*;

    const NOW: u128 = 1_000_000;

    #[test]
    fn chooses_enabled_matching_provider_account() {
        let store = store_with_accounts(
            "openai",
            "fill-first",
            vec![
                account("openai-low", "openai", 1, &["gpt-4o"]),
                account("openai-high", "openai", 5, &["gpt-4o"]),
            ],
        );

        let decision = build_provider_route_decision(
            &store,
            ProviderRouteRequest {
                model_id: "gpt-4o".to_string(),
                provider: String::new(),
                now_ms: NOW,
            },
        );

        assert_eq!(decision.requested_provider, "openai");
        assert_eq!(decision.selected_account_key, "openai-high");
        assert_eq!(decision.pool_id, "default");
        assert_eq!(decision.routing_strategy, "fill-first");
        assert_eq!(decision.available_count, 2);
        assert_eq!(decision.fallback_reason_code, "");
        assert_eq!(decision.candidates[0].reason_code, "selected_by_scheduler");
        assert_eq!(
            decision.candidates[0].next_retry_at_ms,
            decision.candidates[0].retry_at_ms
        );
    }

    #[test]
    fn skips_disabled_cooldown_and_quota_exhausted_candidates() {
        let mut disabled = account("disabled", "openai", 10, &["gpt-4o"]);
        disabled.enabled = false;

        let mut cooldown = account("cooldown", "openai", 9, &["gpt-4o"]);
        cooldown.error_state.next_retry_at_ms = (NOW as u64) + 30_000;
        cooldown.error_state.reason_code = "rate_limited".to_string();

        let mut exhausted = account("exhausted", "openai", 8, &["gpt-4o"]);
        exhausted.quota.daily_token_cap = 100;
        exhausted.quota.daily_tokens_used = 100;

        let ready = account("ready", "openai", 1, &["gpt-4o"]);
        let store = store_with_accounts(
            "openai",
            "priority",
            vec![disabled, cooldown, exhausted, ready],
        );

        let decision = build_provider_route_decision(
            &store,
            ProviderRouteRequest {
                model_id: "gpt-4o".to_string(),
                provider: "openai".to_string(),
                now_ms: NOW,
            },
        );

        assert_eq!(decision.selected_account_key, "ready");
        assert_eq!(decision.available_count, 1);
        assert!(decision
            .candidates
            .iter()
            .any(|candidate| candidate.account_key == "disabled" && candidate.state == "disabled"));
        assert!(decision
            .candidates
            .iter()
            .any(|candidate| candidate.account_key == "cooldown" && candidate.state == "cooldown"));
        assert!(decision.candidates.iter().any(|candidate| {
            candidate.account_key == "exhausted"
                && candidate.reason_code == "daily_token_cap_exceeded"
        }));
    }

    #[test]
    fn deterministic_tie_break_prefers_stable_account_key() {
        let store = store_with_accounts(
            "openai",
            "priority",
            vec![
                account("z-account", "openai", 3, &["gpt-4o"]),
                account("a-account", "openai", 3, &["gpt-4o"]),
            ],
        );

        let decision = build_provider_route_decision(
            &store,
            ProviderRouteRequest {
                model_id: "gpt-4o".to_string(),
                provider: "openai".to_string(),
                now_ms: NOW,
            },
        );

        assert_eq!(decision.selected_account_key, "a-account");
    }

    #[test]
    fn fails_closed_when_remote_export_provider_unknown() {
        let decision = build_provider_route_decision(
            &ProviderKeyStore::empty(),
            ProviderRouteRequest {
                model_id: "unknown-local-model".to_string(),
                provider: String::new(),
                now_ms: NOW,
            },
        );

        assert_eq!(decision.selected_account_key, "");
        assert_eq!(decision.fallback_reason_code, "unknown_model_provider");
        assert_eq!(decision.available_count, 0);
    }

    #[test]
    fn reports_all_keys_rate_limited_when_no_ready_key() {
        let mut one = account("one", "openai", 1, &["gpt-4o"]);
        one.quota.daily_token_cap = 10;
        one.quota.daily_tokens_used = 10;
        let mut two = account("two", "openai", 2, &["gpt-4o"]);
        two.error_state.status = "rate_limited".to_string();
        two.error_state.reason_code = "rate_limited".to_string();

        let store = store_with_accounts("openai", "priority", vec![one, two]);
        let decision = build_provider_route_decision(
            &store,
            ProviderRouteRequest {
                model_id: "gpt-4o".to_string(),
                provider: "openai".to_string(),
                now_ms: NOW,
            },
        );

        assert_eq!(decision.selected_account_key, "");
        assert_eq!(decision.available_count, 0);
        assert_eq!(decision.fallback_reason_code, "all_keys_rate_limited");
    }

    #[test]
    fn route_trace_exposes_no_secret_material() {
        let mut account = account("trace", "openai", 1, &["gpt-4o"]);
        account.api_key = "sk-secret-value".to_string();
        account.refresh_token = "refresh-secret-value".to_string();
        account.quota.next_recover_at_ms = NOW as u64 + 30_000;
        let store = store_with_accounts("openai", "priority", vec![account]);

        let decision = build_provider_route_decision(
            &store,
            ProviderRouteRequest {
                model_id: "gpt-4o".to_string(),
                provider: "openai".to_string(),
                now_ms: NOW,
            },
        );
        let trace = serde_json::to_value(&decision).expect("route decision should serialize");
        let candidate = trace["candidates"][0]
            .as_object()
            .expect("candidate should be an object");
        let trace_json = serde_json::to_string(&trace).expect("trace should stringify");

        assert_eq!(trace["pool_id"], "default");
        assert_eq!(trace["routing_strategy"], "priority");
        assert_eq!(
            candidate["next_retry_at_ms"].as_u64(),
            candidate["retry_at_ms"].as_u64()
        );
        assert!(!candidate.contains_key("api_key"));
        assert!(!candidate.contains_key("refresh_token"));
        assert!(!trace_json.contains("sk-secret-value"));
        assert!(!trace_json.contains("refresh-secret-value"));
    }

    #[test]
    fn remote_inventory_rows_are_secret_free_and_canonical() {
        let mut account = account("remote", "openai", 1, &["openai/gpt5.5"]);
        account.api_key = "sk-secret-value".to_string();
        account.provider_host = "api.openai.com".to_string();
        account.pool_id = "paid".to_string();
        let store = store_with_accounts("openai", "priority", vec![account]);

        let rows = remote_model_inventory_rows(&store, NOW);
        let serialized = serde_json::to_string(&rows).expect("rows should serialize");

        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].model_id, "gpt-5.5");
        assert_eq!(rows[0].provider, "openai");
        assert_eq!(rows[0].provider_host, "api.openai.com");
        assert_eq!(rows[0].family_key, "gpt-5");
        assert_eq!(rows[0].pool_id, "paid");
        assert_eq!(rows[0].availability_state, "ready");
        assert_eq!(rows[0].available_account_count, 1);
        assert_eq!(rows[0].blocking_reason_code, "");
        assert!(!serialized.contains("sk-secret-value"));
    }

    #[test]
    fn remote_inventory_reports_cooldown_retry_time() {
        let retry_at_ms = NOW as u64 + 30_000;
        let mut account = account("cooling", "openai", 1, &["gpt-4o"]);
        account.quota.next_recover_at_ms = retry_at_ms;
        let store = store_with_accounts("openai", "priority", vec![account]);

        let rows = remote_model_inventory_rows(&store, NOW);

        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].availability_state, "cooldown");
        assert_eq!(rows[0].blocking_reason_code, "all_keys_in_cooldown");
        assert_eq!(rows[0].next_retry_at_ms, retry_at_ms);
        assert_eq!(rows[0].available_account_count, 0);
        assert_eq!(rows[0].total_account_count, 1);
    }

    #[test]
    fn normalizes_openai_prefixed_gpt_alias_for_routing() {
        let store = store_with_accounts(
            "openai",
            "priority",
            vec![account("alias-account", "openai", 1, &["gpt-5.5"])],
        );

        let decision = build_provider_route_decision(
            &store,
            ProviderRouteRequest {
                model_id: "openai/GPT5.5".to_string(),
                provider: String::new(),
                now_ms: NOW,
            },
        );

        assert_eq!(decision.requested_provider, "openai");
        assert_eq!(decision.requested_model_id, "gpt-5.5");
        assert_eq!(decision.selected_account_key, "alias-account");
        assert_eq!(decision.available_count, 1);
    }

    #[test]
    fn matches_compact_and_hyphenated_openai_gpt_aliases() {
        let store = store_with_accounts(
            "openai",
            "priority",
            vec![account("compact-account", "openai", 1, &["gpt5.5"])],
        );

        let decision = build_provider_route_decision(
            &store,
            ProviderRouteRequest {
                model_id: "gpt-5.5".to_string(),
                provider: "openai".to_string(),
                now_ms: NOW,
            },
        );

        assert_eq!(decision.requested_model_id, "gpt-5.5");
        assert_eq!(decision.selected_account_key, "compact-account");
        assert_eq!(decision.fallback_reason_code, "");
    }

    #[test]
    fn resolves_model_state_by_alias_and_reports_canonical_key() {
        let retry_at_ms = NOW as u64 + 40_000;
        let mut cooling = account("cooling", "openai", 10, &["gpt-5.5"]);
        cooling.model_states.insert(
            "gpt5.5".to_string(),
            ProviderModelState {
                status: "cooldown".to_string(),
                reason_code: "rate_limited".to_string(),
                status_message: "quota recovering".to_string(),
                next_retry_at_ms: retry_at_ms,
                retry_at_source: "quota".to_string(),
                ..ProviderModelState::default()
            },
        );
        let ready = account("ready", "openai", 1, &["gpt-5.5"]);
        let store = store_with_accounts("openai", "priority", vec![cooling, ready]);

        let decision = build_provider_route_decision(
            &store,
            ProviderRouteRequest {
                model_id: "openai/gpt-5.5".to_string(),
                provider: String::new(),
                now_ms: NOW,
            },
        );

        let cooling_candidate = decision
            .candidates
            .iter()
            .find(|candidate| candidate.account_key == "cooling")
            .expect("cooling candidate should be present");
        assert_eq!(decision.selected_account_key, "ready");
        assert_eq!(cooling_candidate.state, "cooldown");
        assert_eq!(cooling_candidate.reason_code, "rate_limited");
        assert_eq!(cooling_candidate.retry_at_ms, retry_at_ms);
        assert_eq!(cooling_candidate.retry_at_source, "quota");
        assert_eq!(cooling_candidate.model_state_key, "gpt-5.5");
    }

    #[test]
    fn quota_next_recover_at_ms_blocks_selection_until_recovery() {
        let retry_at_ms = NOW as u64 + 30_000;
        let mut recovering = account("recovering", "openai", 10, &["gpt-4o"]);
        recovering.quota.next_recover_at_ms = retry_at_ms;
        let ready = account("ready", "openai", 1, &["gpt-4o"]);
        let store = store_with_accounts("openai", "priority", vec![recovering, ready]);

        let decision = build_provider_route_decision(
            &store,
            ProviderRouteRequest {
                model_id: "gpt-4o".to_string(),
                provider: "openai".to_string(),
                now_ms: NOW,
            },
        );

        let recovering_candidate = decision
            .candidates
            .iter()
            .find(|candidate| candidate.account_key == "recovering")
            .expect("recovering candidate should be present");
        assert_eq!(decision.selected_account_key, "ready");
        assert_eq!(decision.available_count, 1);
        assert_eq!(recovering_candidate.state, "cooldown");
        assert_eq!(recovering_candidate.reason_code, "cooldown_active");
        assert_eq!(recovering_candidate.retry_at_ms, retry_at_ms);
    }

    #[test]
    fn provider_store_deserializes_node_null_maps_as_empty() {
        let store: ProviderKeyStore = serde_json::from_str(
            r#"{
              "providers": {
                "openai": {
                  "routing_strategy": "fill-first",
                  "accounts": [
                    {
                      "account_key": "acct-null",
                      "provider": "openai",
                      "api_key": "sk-test",
                      "models": null,
                      "source_owners": null,
                      "model_states": null,
                      "oauth_refresh_config": null
                    }
                  ]
                }
              }
            }"#,
        )
        .expect("node provider store shape should parse");

        let account = &store.providers["openai"].accounts[0];
        assert!(account.models.is_empty());
        assert!(account.source_owners.is_empty());
        assert!(account.model_states.is_empty());
        assert!(account.oauth_refresh_config.is_empty());
    }

    fn store_with_accounts(
        provider: &str,
        strategy: &str,
        accounts: Vec<ProviderAccount>,
    ) -> ProviderKeyStore {
        let mut providers = BTreeMap::new();
        providers.insert(
            provider.to_string(),
            ProviderData {
                routing_strategy: strategy.to_string(),
                accounts,
            },
        );
        ProviderKeyStore {
            routing_strategy: default_routing_strategy(),
            providers,
        }
    }

    fn account(
        account_key: &str,
        provider: &str,
        priority: u32,
        models: &[&str],
    ) -> ProviderAccount {
        ProviderAccount {
            account_key: account_key.to_string(),
            provider: provider.to_string(),
            pool_id: "default".to_string(),
            provider_host: "api.example.test".to_string(),
            wire_api: "responses".to_string(),
            enabled: true,
            api_key: "sk-test".to_string(),
            auth_type: "api_key".to_string(),
            priority,
            models: models.iter().map(|value| value.to_string()).collect(),
            quota: ProviderQuota {
                daily_token_cap: 1000,
                daily_tokens_remaining: 1000,
                ..ProviderQuota::default()
            },
            ..ProviderAccount::default()
        }
    }
}
