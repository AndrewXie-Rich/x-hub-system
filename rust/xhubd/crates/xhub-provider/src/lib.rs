use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

use serde::de::DeserializeOwned;
use serde::{Deserialize, Deserializer, Serialize};
use serde_json::{json, Map, Value};

pub const PROVIDER_ROUTE_SCHEMA_VERSION: &str = "xhub.provider_route_decision.v1";
pub const PROVIDER_KEY_SNAPSHOT_SCHEMA_VERSION: &str = "xhub.provider_key_snapshot.v1";
pub const PROVIDER_QUOTA_REFRESH_APPLY_SCHEMA_VERSION: &str =
    "xhub.provider_quota_refresh_apply.v1";
pub const PROVIDER_QUOTA_REFRESH_PLAN_SCHEMA_VERSION: &str = "xhub.provider_quota_refresh_plan.v1";
pub const PROVIDER_QUOTA_REFRESH_FAILURE_SCHEMA_VERSION: &str =
    "xhub.provider_quota_refresh_failure.v1";
pub const PROVIDER_OAUTH_REFRESH_SCHEMA_VERSION: &str = "xhub.provider_oauth_refresh.v1";
pub const PROVIDER_OAUTH_REFRESH_PLAN_SCHEMA_VERSION: &str = "xhub.provider_oauth_refresh_plan.v1";
pub const PROVIDER_KEY_IMPORT_SCHEMA_VERSION: &str = "xhub.provider_key_import.v1";
pub const PROVIDER_STORE_FILE_NAME: &str = "hub_provider_keys.json";
const QUOTA_REFRESH_RETRY_SOURCE: &str = "usage_window";
const OAUTH_REFRESH_RETRY_SOURCE: &str = "refresh";
const QUOTA_BASIS_POINTS_CAP: u64 = 10_000;
const DEFAULT_OAUTH_REFRESH_LEAD_MS: u64 = 5 * 24 * 60 * 60 * 1000;
const DEFAULT_OAUTH_MIN_REFRESH_LEAD_MS: u64 = 5 * 60 * 1000;
const OPENAI_USAGE_WINDOW_OAUTH_SOURCES: &[&str] =
    &["chatgpt", "openai-chatgpt", "openai", "codex"];

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

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ProviderKeyPoolSnapshotResponse {
    pub pools: Vec<ProviderKeyPoolSnapshot>,
    pub updated_at_ms: u64,
    pub routing_strategy: String,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ProviderKeyPoolSnapshot {
    pub pool_id: String,
    pub capability_pool_id: String,
    pub provider: String,
    pub provider_host: String,
    pub wire_api: String,
    pub model_id: String,
    pub model_family: String,
    pub state: String,
    pub source_providers: Vec<String>,
    pub total_accounts: u32,
    pub enabled_accounts: u32,
    pub ready_accounts: u32,
    pub cooldown_accounts: u32,
    pub blocked_accounts: u32,
    pub expired_accounts: u32,
    pub disabled_accounts: u32,
    pub stale_accounts: u32,
    pub auth_failed_accounts: u32,
    pub free_accounts: u32,
    pub paid_accounts: u32,
    pub unknown_tier_accounts: u32,
    pub removable_accounts: u32,
    pub known_quota_accounts: u32,
    pub daily_token_cap: u64,
    pub daily_tokens_used: u64,
    pub daily_tokens_remaining: u64,
    pub total_tokens_used: u64,
    pub next_retry_at_ms: u64,
    pub last_used_at_ms: u64,
    pub last_refresh_at_ms: u64,
    pub blocker_reason_codes: Vec<String>,
    pub members: Vec<ProviderKeyPoolMemberSnapshot>,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ProviderKeyPoolMemberSnapshot {
    pub account_key: String,
    pub provider: String,
    pub email: String,
    pub tier: String,
    pub enabled: bool,
    pub auth_type: String,
    pub account_id: String,
    pub source_ref: String,
    pub oauth_source_key: String,
    pub pool_id: String,
    pub state: String,
    pub reason_code: String,
    pub status_message: String,
    pub retry_at_ms: u64,
    pub expires_at_ms: u64,
    pub last_refresh_at_ms: u64,
    pub last_used_at_ms: u64,
    pub daily_token_cap: u64,
    pub daily_tokens_used: u64,
    pub daily_tokens_remaining: u64,
    pub total_tokens_used: u64,
    pub removable: bool,
    pub removal_reason: String,
    pub api_key_redacted: String,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ProviderKeyRuntimeSnapshotResponse {
    pub accounts: Vec<ProviderKeyRuntimeAccountSnapshot>,
    pub import_source_statuses: Vec<ProviderImportSourceStatusSnapshot>,
    pub updated_at_ms: u64,
    pub global_routing_strategy: String,
    pub providers: Vec<ProviderSummarySnapshot>,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ProviderSummarySnapshot {
    pub provider: String,
    pub total_accounts: u32,
    pub enabled_accounts: u32,
    pub routing_strategy: String,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ProviderKeyRuntimeAccountSnapshot {
    pub account_key: String,
    pub provider: String,
    pub email: String,
    pub enabled: bool,
    pub auth_type: String,
    pub tier: String,
    pub base_url: String,
    pub proxy_url: String,
    pub pool_id: String,
    pub provider_host: String,
    pub wire_api: String,
    pub account_id: String,
    pub source_type: String,
    pub source_ref: String,
    pub oauth_source_key: String,
    pub auth_index: u32,
    pub expires_at_ms: u64,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
    pub last_refresh_at_ms: u64,
    pub models: Vec<String>,
    pub source_owners: Vec<String>,
    pub required_refresh_metadata: Vec<String>,
    pub quota: ProviderQuotaSnapshot,
    pub error_state: ProviderErrorStateSnapshot,
    pub refresh_state: ProviderRefreshStateSnapshot,
    pub model_states: BTreeMap<String, ProviderModelStateSnapshot>,
    pub api_key_redacted: String,
    pub notes: String,
    pub priority: u32,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ProviderQuotaSnapshot {
    pub daily_token_cap: u64,
    pub daily_tokens_used: u64,
    pub daily_tokens_remaining: u64,
    pub total_tokens_used: u64,
    pub last_used_at_ms: u64,
    pub last_error_at_ms: u64,
    pub consecutive_errors: u32,
    pub cooldown_until_ms: u64,
    pub usage_windows: Vec<ProviderQuotaUsageWindow>,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ProviderErrorStateSnapshot {
    pub status: String,
    pub last_error_code: String,
    pub last_error_at_ms: u64,
    pub auto_disabled: bool,
    pub status_message: String,
    pub reason_code: String,
    pub next_retry_at_ms: u64,
    pub retry_at_source: String,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ProviderRefreshStateSnapshot {
    pub status: String,
    pub last_attempt_at_ms: u64,
    pub last_success_at_ms: u64,
    pub next_refresh_at_ms: u64,
    pub failure_count: u32,
    pub last_error_code: String,
    pub last_error_message: String,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ProviderModelStateSnapshot {
    pub status: String,
    pub reason_code: String,
    pub status_message: String,
    pub next_retry_at_ms: u64,
    pub retry_at_source: String,
    pub last_error_code: String,
    pub last_error_at_ms: u64,
    pub updated_at_ms: u64,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ProviderImportSourceStatusSnapshot {
    pub source_key: String,
    pub kind: String,
    pub source_ref: String,
    pub state: String,
    pub last_sync_at_ms: u64,
    pub last_imported_count: u32,
    pub owned_account_count: u32,
    pub last_error_count: u32,
    pub last_errors: Vec<String>,
    pub updated_at_ms: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct OpenAIQuotaApplyOptions {
    pub account_key: String,
    #[serde(default)]
    pub refreshed_at_ms: u64,
    #[serde(default)]
    pub success_interval_ms: u64,
    #[serde(default)]
    pub high_water_interval_ms: u64,
    #[serde(default)]
    pub account_id: String,
    #[serde(default)]
    pub oauth_source_key: String,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ProviderQuotaRefreshApplyResult {
    pub ok: bool,
    pub account_key: String,
    pub updated: bool,
    pub refreshed_at_ms: u64,
    pub next_refresh_at_ms: u64,
    pub limited: bool,
    pub error_code: String,
    pub error_message: String,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ProviderKeyImportResult {
    pub ok: bool,
    pub imported: u32,
    pub errors: Vec<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct OpenAIQuotaRefreshPlanOptions {
    #[serde(default)]
    pub now_ms: u64,
    #[serde(default)]
    pub include_skipped: bool,
    #[serde(default, deserialize_with = "deserialize_vec_or_default")]
    pub in_flight_account_keys: Vec<String>,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ProviderQuotaRefreshPlanResult {
    pub ok: bool,
    pub accounts: Vec<ProviderQuotaRefreshPlanAccount>,
    pub skipped_accounts: Vec<ProviderQuotaRefreshPlanSkippedAccount>,
    pub total_accounts: u32,
    pub eligible_accounts: u32,
    pub due_accounts: u32,
    pub skipped_count: u32,
    pub updated_at_ms: u64,
    pub now_ms: u64,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ProviderQuotaRefreshPlanAccount {
    pub account_key: String,
    pub provider: String,
    pub account_id: String,
    pub oauth_source_key: String,
    pub auth_index: u32,
    pub next_refresh_at_ms: u64,
    pub failure_count: u32,
    pub last_refresh_at_ms: u64,
    pub priority: u32,
    pub reason_code: String,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ProviderQuotaRefreshPlanSkippedAccount {
    pub account_key: String,
    pub provider: String,
    pub reason_code: String,
    pub next_refresh_at_ms: u64,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct OpenAIQuotaRefreshFailureOptions {
    pub account_key: String,
    #[serde(default)]
    pub failed_at_ms: u64,
    #[serde(default)]
    pub base_failure_backoff_ms: u64,
    #[serde(default)]
    pub max_failure_backoff_ms: u64,
    #[serde(default)]
    pub error_code: String,
    #[serde(default)]
    pub error_message: String,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ProviderQuotaRefreshFailureResult {
    pub ok: bool,
    pub account_key: String,
    pub updated: bool,
    pub failed_at_ms: u64,
    pub failure_count: u32,
    pub next_refresh_at_ms: u64,
    pub error_code: String,
    pub error_message: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct ProviderOAuthRefreshApplyOptions {
    pub account_key: String,
    #[serde(default)]
    pub refreshed_at_ms: u64,
    #[serde(default)]
    pub access_token: String,
    #[serde(default)]
    pub refresh_token: String,
    #[serde(default)]
    pub expires_at_ms: u64,
    #[serde(default)]
    pub account_id: String,
    #[serde(default)]
    pub email: String,
    #[serde(default)]
    pub oauth_source_key: String,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ProviderOAuthRefreshResult {
    pub ok: bool,
    pub account_key: String,
    pub updated: bool,
    pub refreshed_at_ms: u64,
    pub expires_at_ms: u64,
    pub next_refresh_at_ms: u64,
    pub error_code: String,
    pub error_message: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct ProviderOAuthRefreshPlanOptions {
    #[serde(default)]
    pub now_ms: u64,
    #[serde(default)]
    pub include_skipped: bool,
    #[serde(default, deserialize_with = "deserialize_vec_or_default")]
    pub in_flight_account_keys: Vec<String>,
    #[serde(default)]
    pub refresh_lead_ms: u64,
    #[serde(default)]
    pub min_refresh_lead_ms: u64,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ProviderOAuthRefreshPlanResult {
    pub ok: bool,
    pub accounts: Vec<ProviderOAuthRefreshPlanAccount>,
    pub skipped_accounts: Vec<ProviderOAuthRefreshPlanSkippedAccount>,
    pub total_accounts: u32,
    pub eligible_accounts: u32,
    pub due_accounts: u32,
    pub skipped_count: u32,
    pub refresh_lead_ms: u64,
    pub min_refresh_lead_ms: u64,
    pub updated_at_ms: u64,
    pub now_ms: u64,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ProviderOAuthRefreshPlanAccount {
    pub account_key: String,
    pub provider: String,
    pub account_id: String,
    pub email: String,
    pub oauth_source_key: String,
    pub auth_index: u32,
    pub expires_at_ms: u64,
    pub refresh_due_at_ms: u64,
    pub next_refresh_at_ms: u64,
    pub failure_count: u32,
    pub last_refresh_at_ms: u64,
    pub priority: u32,
    pub reason_code: String,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ProviderOAuthRefreshPlanSkippedAccount {
    pub account_key: String,
    pub provider: String,
    pub reason_code: String,
    pub expires_at_ms: u64,
    pub refresh_due_at_ms: u64,
    pub next_refresh_at_ms: u64,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct ProviderOAuthRefreshFailureOptions {
    pub account_key: String,
    #[serde(default)]
    pub failed_at_ms: u64,
    #[serde(default)]
    pub base_failure_backoff_ms: u64,
    #[serde(default)]
    pub max_failure_backoff_ms: u64,
    #[serde(default)]
    pub terminal: bool,
    #[serde(default)]
    pub error_code: String,
    #[serde(default)]
    pub error_message: String,
}

#[derive(Debug, Clone)]
pub enum ProviderRouteError {
    Io(String),
    Json(String),
    Invalid(String),
}

impl std::fmt::Display for ProviderRouteError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ProviderRouteError::Io(message) => write!(f, "provider store io error: {message}"),
            ProviderRouteError::Json(message) => write!(f, "provider store json error: {message}"),
            ProviderRouteError::Invalid(message) => {
                write!(f, "provider store invalid state: {message}")
            }
        }
    }
}

impl std::error::Error for ProviderRouteError {}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ProviderKeyStore {
    #[serde(default)]
    pub schema_version: String,
    #[serde(default)]
    pub updated_at_ms: u64,
    #[serde(default = "default_routing_strategy")]
    pub routing_strategy: String,
    #[serde(default)]
    pub providers: BTreeMap<String, ProviderData>,
    #[serde(default, deserialize_with = "deserialize_map_or_default")]
    pub import_source_statuses: BTreeMap<String, ProviderImportSourceStatus>,
}

impl ProviderKeyStore {
    pub fn empty() -> Self {
        Self {
            routing_strategy: default_routing_strategy(),
            providers: BTreeMap::new(),
            ..Self::default()
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

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ProviderData {
    #[serde(default = "default_routing_strategy")]
    pub routing_strategy: String,
    #[serde(default, deserialize_with = "deserialize_vec_or_default")]
    pub accounts: Vec<ProviderAccount>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ProviderAccount {
    #[serde(default)]
    pub account_key: String,
    #[serde(default)]
    pub provider: String,
    #[serde(default)]
    pub email: String,
    #[serde(default)]
    pub tier: String,
    #[serde(default)]
    pub base_url: String,
    #[serde(default)]
    pub proxy_url: String,
    #[serde(default)]
    pub account_id: String,
    #[serde(default)]
    pub source_type: String,
    #[serde(default)]
    pub source_ref: String,
    #[serde(default)]
    pub auth_index: u32,
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
    pub created_at_ms: u64,
    #[serde(default)]
    pub updated_at_ms: u64,
    #[serde(default)]
    pub last_refresh_at_ms: u64,
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
    #[serde(default)]
    pub notes: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ProviderQuota {
    #[serde(default)]
    pub daily_token_cap: u64,
    #[serde(default)]
    pub daily_tokens_used: u64,
    #[serde(default)]
    pub daily_tokens_remaining: u64,
    #[serde(default)]
    pub total_tokens_used: u64,
    #[serde(default)]
    pub last_used_at_ms: u64,
    #[serde(default)]
    pub last_error_at_ms: u64,
    #[serde(default)]
    pub cooldown_until_ms: u64,
    #[serde(default)]
    pub next_recover_at_ms: u64,
    #[serde(default)]
    pub next_refresh_at_ms: u64,
    #[serde(default)]
    pub consecutive_errors: u32,
    #[serde(default, deserialize_with = "deserialize_vec_or_default")]
    pub usage_windows: Vec<ProviderQuotaUsageWindow>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct ProviderQuotaUsageWindow {
    #[serde(default)]
    pub key: String,
    #[serde(default)]
    pub source: String,
    #[serde(default)]
    pub window_key: String,
    #[serde(default)]
    pub label: String,
    #[serde(default)]
    pub limit_window_seconds: u64,
    #[serde(default)]
    pub used_percent: f64,
    #[serde(default)]
    pub used_basis_points: u32,
    #[serde(default)]
    pub remaining_basis_points: u32,
    #[serde(default)]
    pub limited: bool,
    #[serde(default)]
    pub reset_at_ms: u64,
    #[serde(default)]
    pub updated_at_ms: u64,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ProviderErrorState {
    #[serde(default)]
    pub status: String,
    #[serde(default)]
    pub reason_code: String,
    #[serde(default)]
    pub last_error_code: String,
    #[serde(default)]
    pub last_error_at_ms: u64,
    #[serde(default)]
    pub status_message: String,
    #[serde(default)]
    pub next_retry_at_ms: u64,
    #[serde(default)]
    pub retry_at_source: String,
    #[serde(default)]
    pub auto_disabled: bool,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ProviderRefreshState {
    #[serde(default)]
    pub status: String,
    #[serde(default)]
    pub last_attempt_at_ms: u64,
    #[serde(default)]
    pub last_success_at_ms: u64,
    #[serde(default)]
    pub last_error_code: String,
    #[serde(default)]
    pub last_error_message: String,
    #[serde(default)]
    pub next_refresh_at_ms: u64,
    #[serde(default)]
    pub failure_count: u32,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
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
    pub last_error_at_ms: u64,
    #[serde(default)]
    pub updated_at_ms: u64,
    #[serde(default)]
    pub status_message: String,
    #[serde(default)]
    pub next_retry_at_ms: u64,
    #[serde(default)]
    pub retry_at_source: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ProviderImportSourceStatus {
    #[serde(default)]
    pub kind: String,
    #[serde(default)]
    pub source_ref: String,
    #[serde(default)]
    pub state: String,
    #[serde(default)]
    pub last_sync_at_ms: u64,
    #[serde(default)]
    pub last_imported_count: u32,
    #[serde(default)]
    pub owned_account_count: u32,
    #[serde(default)]
    pub last_error_count: u32,
    #[serde(default, deserialize_with = "deserialize_vec_or_default")]
    pub last_errors: Vec<String>,
    #[serde(default)]
    pub updated_at_ms: u64,
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
struct PoolState {
    state: String,
    reason_code: String,
    status_message: String,
    retry_at_ms: u64,
}

#[derive(Debug, Clone)]
struct MutablePoolSnapshot {
    pool_id: String,
    capability_pool_id: String,
    provider: String,
    provider_host: String,
    wire_api: String,
    model_id: String,
    model_family: String,
    total_accounts: u32,
    enabled_accounts: u32,
    ready_accounts: u32,
    cooldown_accounts: u32,
    blocked_accounts: u32,
    expired_accounts: u32,
    disabled_accounts: u32,
    stale_accounts: u32,
    auth_failed_accounts: u32,
    free_accounts: u32,
    paid_accounts: u32,
    unknown_tier_accounts: u32,
    removable_accounts: u32,
    known_quota_accounts: u32,
    daily_token_cap: u64,
    daily_tokens_used: u64,
    daily_tokens_remaining: u64,
    total_tokens_used: u64,
    next_retry_at_ms: u64,
    last_used_at_ms: u64,
    last_refresh_at_ms: u64,
    reason_counts: BTreeMap<String, u32>,
    source_providers: BTreeSet<String>,
    members: Vec<ProviderKeyPoolMemberSnapshot>,
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

pub fn provider_runtime_snapshot_from_runtime_base_dir(
    runtime_base_dir: &Path,
    provider_filter: &str,
) -> Result<ProviderKeyRuntimeSnapshotResponse, ProviderRouteError> {
    let store = ProviderKeyStore::load_runtime_base_dir(runtime_base_dir)?;
    Ok(provider_runtime_snapshot(&store, provider_filter))
}

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

pub fn import_provider_keys_to_runtime_base_dir(
    runtime_base_dir: &Path,
    auth_dir: &str,
    config_path: &str,
    imported_at_ms: u64,
) -> Result<ProviderKeyImportResult, ProviderRouteError> {
    let auth_dir = trim_string(auth_dir);
    let config_path = trim_string(config_path);
    if auth_dir.is_empty() && config_path.is_empty() {
        return Ok(ProviderKeyImportResult {
            ok: false,
            imported: 0,
            errors: vec!["missing_import_path".to_string()],
        });
    }

    let mut overall_ok = true;
    let mut imported = 0_u32;
    let mut errors = Vec::new();
    let now_ms = if imported_at_ms == 0 {
        current_time_millis()
    } else {
        imported_at_ms
    };

    if !auth_dir.is_empty() {
        let result = import_auth_dir_to_runtime_base_dir(runtime_base_dir, &auth_dir, now_ms)?;
        overall_ok = overall_ok && result.ok;
        imported = imported.saturating_add(result.imported);
        errors.extend(result.errors);
    }

    if !config_path.is_empty() {
        let result =
            import_proxy_config_to_runtime_base_dir(runtime_base_dir, &config_path, now_ms)?;
        overall_ok = overall_ok && result.ok;
        imported = imported.saturating_add(result.imported);
        errors.extend(result.errors);
    }

    Ok(ProviderKeyImportResult {
        ok: overall_ok && errors.is_empty(),
        imported,
        errors,
    })
}

pub fn import_auth_dir_to_runtime_base_dir(
    runtime_base_dir: &Path,
    auth_dir_path: &str,
    imported_at_ms: u64,
) -> Result<ProviderKeyImportResult, ProviderRouteError> {
    let source_ref = normalize_path_ref(Path::new(auth_dir_path));
    if source_ref.is_empty() || !Path::new(&source_ref).exists() {
        return Ok(ProviderKeyImportResult {
            ok: false,
            imported: 0,
            errors: Vec::new(),
        });
    }

    let now_ms = if imported_at_ms == 0 {
        current_time_millis()
    } else {
        imported_at_ms
    };
    let store_path = runtime_base_dir.join(PROVIDER_STORE_FILE_NAME);
    let mut store_value = load_provider_store_value_for_import(&store_path)?;
    let overlay = ImportOverlay {
        import_source_kind: "auth_dir".to_string(),
        import_source_ref: source_ref.clone(),
        ..ImportOverlay::default()
    };
    let build = build_imported_auth_accounts(
        &collect_auth_json_files(Path::new(&source_ref), None),
        &overlay,
        now_ms,
    );
    let applied = apply_imported_accounts_to_store(
        &mut store_value,
        &build.accounts,
        "auth_dir",
        &source_ref,
        build.errors.is_empty(),
        now_ms,
    )?;
    let mut errors = build.errors;
    errors.extend(applied.errors);
    record_import_source_status_in_store(
        &mut store_value,
        "auth_dir",
        &source_ref,
        if errors.is_empty() {
            "ready"
        } else {
            "sync_failed"
        },
        applied.imported,
        &errors,
        now_ms,
    );
    set_json_u64_object(&mut store_value, "updated_at_ms", now_ms);
    write_provider_store_value_atomic(&store_path, &store_value)?;

    Ok(ProviderKeyImportResult {
        ok: errors.is_empty(),
        imported: applied.imported,
        errors,
    })
}

pub fn import_proxy_config_to_runtime_base_dir(
    runtime_base_dir: &Path,
    config_path: &str,
    imported_at_ms: u64,
) -> Result<ProviderKeyImportResult, ProviderRouteError> {
    let source_ref = normalize_path_ref(Path::new(config_path));
    if source_ref.is_empty() || !Path::new(&source_ref).is_file() {
        return Ok(ProviderKeyImportResult {
            ok: false,
            imported: 0,
            errors: Vec::new(),
        });
    }

    let now_ms = if imported_at_ms == 0 {
        current_time_millis()
    } else {
        imported_at_ms
    };
    let store_path = runtime_base_dir.join(PROVIDER_STORE_FILE_NAME);
    let mut store_value = load_provider_store_value_for_import(&store_path)?;
    let build = build_imported_proxy_config_accounts(Path::new(&source_ref), now_ms);
    let applied = apply_imported_accounts_to_store(
        &mut store_value,
        &build.accounts,
        "config_path",
        &source_ref,
        build.errors.is_empty(),
        now_ms,
    )?;
    let mut errors = build.errors;
    errors.extend(applied.errors);
    record_import_source_status_in_store(
        &mut store_value,
        "config_path",
        &source_ref,
        if errors.is_empty() {
            "ready"
        } else {
            "sync_failed"
        },
        applied.imported,
        &errors,
        now_ms,
    );
    set_json_u64_object(&mut store_value, "updated_at_ms", now_ms);
    write_provider_store_value_atomic(&store_path, &store_value)?;

    Ok(ProviderKeyImportResult {
        ok: errors.is_empty(),
        imported: applied.imported,
        errors,
    })
}

#[derive(Debug, Clone, Default)]
struct ImportOverlay {
    provider: String,
    base_url: String,
    proxy_url: String,
    wire_api: String,
    source: String,
    import_source_kind: String,
    import_source_ref: String,
}

#[derive(Debug, Clone, Default)]
struct ImportedAccountBuild {
    accounts: Vec<Value>,
    errors: Vec<String>,
}

#[derive(Debug, Clone, Default)]
struct ImportedAccountApply {
    imported: u32,
    errors: Vec<String>,
}

fn load_provider_store_value_for_import(path: &Path) -> Result<Value, ProviderRouteError> {
    if !path.is_file() {
        return Ok(empty_provider_store_value());
    }
    let raw = fs::read_to_string(path)
        .map_err(|err| ProviderRouteError::Io(format!("{}: {err}", path.display())))?;
    let mut value: Value = serde_json::from_str(&raw)
        .map_err(|err| ProviderRouteError::Json(format!("{}: {err}", path.display())))?;
    ensure_provider_store_shape(&mut value);
    Ok(value)
}

fn empty_provider_store_value() -> Value {
    json!({
        "schema_version": "hub_provider_keys.v1",
        "updated_at_ms": 0,
        "routing_strategy": default_routing_strategy(),
        "import_sources": [],
        "import_source_statuses": {},
        "providers": {},
    })
}

fn ensure_provider_store_shape(value: &mut Value) {
    if !value.is_object() {
        *value = empty_provider_store_value();
        return;
    }
    let object = value.as_object_mut().expect("value is object");
    object
        .entry("schema_version".to_string())
        .or_insert_with(|| Value::String("hub_provider_keys.v1".to_string()));
    object
        .entry("updated_at_ms".to_string())
        .or_insert_with(|| json!(0));
    object
        .entry("routing_strategy".to_string())
        .or_insert_with(|| Value::String(default_routing_strategy()));
    if !object
        .get("import_sources")
        .map(Value::is_array)
        .unwrap_or(false)
    {
        object.insert("import_sources".to_string(), Value::Array(Vec::new()));
    }
    if !object
        .get("import_source_statuses")
        .map(Value::is_object)
        .unwrap_or(false)
    {
        object.insert(
            "import_source_statuses".to_string(),
            Value::Object(Map::new()),
        );
    }
    if !object
        .get("providers")
        .map(Value::is_object)
        .unwrap_or(false)
    {
        object.insert("providers".to_string(), Value::Object(Map::new()));
    }
}

fn normalize_path_ref(path: &Path) -> String {
    let raw = path.to_string_lossy().trim().to_string();
    if raw.is_empty() {
        return String::new();
    }
    fs::canonicalize(path)
        .unwrap_or_else(|_| {
            if path.is_absolute() {
                path.to_path_buf()
            } else {
                std::env::current_dir()
                    .unwrap_or_else(|_| PathBuf::from("."))
                    .join(path)
            }
        })
        .to_string_lossy()
        .trim()
        .to_string()
}

fn collect_auth_json_files(root_dir: &Path, matcher: Option<fn(&Path) -> bool>) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let mut seen = BTreeSet::new();
    let mut stack = Vec::new();

    if root_dir.is_file() {
        if root_dir
            .file_name()
            .and_then(|name| name.to_str())
            .map(|name| name.ends_with(".json"))
            .unwrap_or(false)
            && matcher.map(|f| f(root_dir)).unwrap_or(true)
        {
            out.push(root_dir.to_path_buf());
        }
        return out;
    }

    push_auth_scan_dir(&mut stack, &mut seen, root_dir);
    push_auth_scan_dir(&mut stack, &mut seen, &root_dir.join("auth"));
    push_auth_scan_dir(&mut stack, &mut seen, &root_dir.join("auth-disabled"));
    if let Some(parent) = root_dir.parent() {
        push_auth_scan_dir(&mut stack, &mut seen, &parent.join("auth-disabled"));
    }

    while let Some(current) = stack.pop() {
        let Ok(entries) = fs::read_dir(&current) else {
            continue;
        };
        for entry in entries.flatten() {
            let entry_path = entry.path();
            let Ok(file_type) = entry.file_type() else {
                continue;
            };
            if file_type.is_dir() {
                if entry.file_name().to_string_lossy().trim().starts_with('.') {
                    continue;
                }
                push_auth_scan_dir(&mut stack, &mut seen, &entry_path);
                continue;
            }
            if !file_type.is_file() {
                continue;
            }
            let is_json = entry_path
                .file_name()
                .and_then(|name| name.to_str())
                .map(|name| name.ends_with(".json"))
                .unwrap_or(false);
            if !is_json || !matcher.map(|f| f(&entry_path)).unwrap_or(true) {
                continue;
            }
            out.push(entry_path);
        }
    }

    out.sort();
    out
}

fn push_auth_scan_dir(stack: &mut Vec<PathBuf>, seen: &mut BTreeSet<String>, path: &Path) {
    if !path.is_dir() {
        return;
    }
    let normalized = normalize_path_ref(path);
    if normalized.is_empty() || seen.contains(&normalized) {
        return;
    }
    seen.insert(normalized);
    stack.push(path.to_path_buf());
}

fn build_imported_auth_accounts(
    files: &[PathBuf],
    overlay: &ImportOverlay,
    now_ms: u64,
) -> ImportedAccountBuild {
    let mut accounts = Vec::new();
    let mut errors = Vec::new();
    for file_path in files {
        let label = file_path
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("auth.json")
            .to_string();
        let raw = match fs::read_to_string(file_path) {
            Ok(raw) => raw,
            Err(err) => {
                errors.push(format!("{label}: {err}"));
                continue;
            }
        };
        let parsed = match serde_json::from_str::<Value>(&raw) {
            Ok(parsed) => parsed,
            Err(err) => {
                errors.push(format!("{label}: {err}"));
                continue;
            }
        };
        if let Some(account) = parse_imported_auth_account(file_path, &parsed, overlay, now_ms) {
            accounts.push(account);
        }
    }
    ImportedAccountBuild { accounts, errors }
}

fn parse_imported_auth_account(
    file_path: &Path,
    raw: &Value,
    overlay: &ImportOverlay,
    now_ms: u64,
) -> Option<Value> {
    let payload = raw
        .get("data")
        .filter(|value| value.is_object())
        .unwrap_or(raw);
    if !payload.is_object() {
        return None;
    }

    let file_name = file_path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or_default();
    let provider = normalize_provider(&overlay.provider)
        .or_else(|| parse_provider_from_payload(payload, file_name))?;

    let token_bag = merged_token_bag(payload);
    let id_token = first_non_empty(&[
        &json_string(payload, "id_token"),
        &map_string(&token_bag, "id_token"),
    ])
    .unwrap_or_default();
    let id_claims = decode_jwt_payload_value(&id_token).unwrap_or(Value::Null);
    let access_token = first_non_empty(&[
        &json_string(payload, "access_token"),
        &json_string(payload.get("token").unwrap_or(&Value::Null), "access_token"),
        &json_string(payload, "accessToken"),
        &map_string(&token_bag, "access_token"),
    ])
    .unwrap_or_default();
    let refresh_token = first_non_empty(&[
        &json_string(payload, "refresh_token"),
        &json_string(
            payload.get("token").unwrap_or(&Value::Null),
            "refresh_token",
        ),
        &json_string(payload, "refreshToken"),
        &map_string(&token_bag, "refresh_token"),
    ])
    .unwrap_or_default();
    if access_token.is_empty() && refresh_token.is_empty() {
        return None;
    }

    let auth_type = if normalized_token(&json_string(payload, "token_type")) == "bearer"
        || !refresh_token.is_empty()
    {
        "oauth"
    } else {
        "api_key"
    };
    let oauth_source_key = first_non_empty(&[
        &json_string(payload, "oauth_source"),
        &json_string(payload, "oauth-source"),
        &json_string(payload, "auth_mode"),
        &provider,
    ])
    .unwrap_or_else(|| provider.clone());
    let default_base_url = auth_file_default_base_url(&provider, auth_type, &oauth_source_key);
    let base_url = first_non_empty(&[
        &overlay.base_url,
        &json_string(payload, "base_url"),
        &json_string(payload, "baseUrl"),
        &default_base_url,
    ])
    .unwrap_or_default();
    let proxy_url = first_non_empty(&[
        &overlay.proxy_url,
        &json_string(payload, "proxy_url"),
        &json_string(payload, "proxyUrl"),
    ])
    .unwrap_or_default();
    let payload_wire = first_non_empty(&[
        &overlay.wire_api,
        &json_string(payload, "wire_api"),
        &json_string(payload, "wireAPI"),
    ])
    .unwrap_or_default();
    let wire_api = resolved_imported_wire_api(
        &payload_wire,
        &provider,
        auth_type,
        &oauth_source_key,
        &overlay.source,
    );
    let auth_index = json_u64_any(payload, &["auth_index", "authIndex"]);
    let email = first_non_empty(&[
        &json_string(payload, "email"),
        &json_string(payload, "username"),
        &json_string(payload, "account_email"),
        &json_string(&id_claims, "email"),
        &json_string(&id_claims, "preferred_username"),
    ])
    .unwrap_or_default();
    let account_id = first_non_empty(&[
        &json_string(payload, "account_id"),
        &json_string(payload, "accountId"),
        &map_string(&token_bag, "account_id"),
        &json_string(&id_claims, "chatgpt_account_id"),
        &json_string(&id_claims, "account_id"),
    ])
    .unwrap_or_default();
    let identity_source = if !account_id.is_empty() {
        format!("{oauth_source_key}:{account_id}:{auth_index}")
    } else if !email.is_empty() {
        format!("{oauth_source_key}:{email}:{auth_index}")
    } else {
        normalize_path_ref(file_path)
    };
    let account_key = format!(
        "{}:{}",
        provider,
        stable_short_fingerprint(&format!("{provider}:{identity_source}"))
    );
    let source_owner = import_source_key(&overlay.import_source_kind, &overlay.import_source_ref);
    let source_ref = normalize_path_ref(file_path);
    let disabled = path_has_segment(file_path, "auth-disabled");
    let expires_at_ms = date_like_to_ms(
        payload
            .get("expires_at")
            .or_else(|| payload.get("expired"))
            .or_else(|| payload.get("expiresAt"))
            .or_else(|| payload.get("token").and_then(|token| token.get("expiry")))
            .or_else(|| token_bag.get("expiry"))
            .or_else(|| id_claims.get("exp"))
            .unwrap_or(&Value::Null),
    );

    let mut account = json!({
        "account_key": account_key,
        "provider": provider,
        "email": email,
        "api_key": access_token,
        "refresh_token": refresh_token,
        "base_url": base_url,
        "proxy_url": proxy_url,
        "enabled": payload.get("enabled").and_then(Value::as_bool).unwrap_or(!disabled),
        "auth_type": auth_type,
        "wire_api": wire_api,
        "expires_at_ms": expires_at_ms,
        "tier": first_non_empty(&[
            &json_string(payload, "tier_name"),
            &json_string(payload, "account_type"),
        ]).unwrap_or_default(),
        "notes": format!("imported from {file_name}"),
        "priority": json_u64(payload, "priority"),
        "account_id": account_id,
        "source_type": "auth_file",
        "source_ref": source_ref,
        "oauth_source_key": oauth_source_key,
        "oauth_refresh_config": oauth_refresh_config_value(payload, &token_bag),
        "auth_index": auth_index,
        "source_owners": if source_owner.is_empty() { Vec::<String>::new() } else { vec![source_owner] },
        "created_at_ms": now_ms,
        "updated_at_ms": now_ms,
    });
    normalize_imported_account_value(&mut account, now_ms).ok()?;
    Some(account)
}

fn build_imported_proxy_config_accounts(config_path: &Path, now_ms: u64) -> ImportedAccountBuild {
    let source_ref = normalize_path_ref(config_path);
    let mut errors = Vec::new();
    let mut accounts = Vec::new();
    let extension = config_path
        .extension()
        .and_then(|ext| ext.to_str())
        .unwrap_or_default()
        .to_ascii_lowercase();
    if extension != "toml" {
        return ImportedAccountBuild {
            accounts,
            errors: vec!["unsupported_config_format".to_string()],
        };
    }

    let raw_toml = match fs::read_to_string(config_path) {
        Ok(raw) => raw,
        Err(err) => {
            errors.push(format!("toml_read_failed: {err}"));
            return ImportedAccountBuild { accounts, errors };
        }
    };
    if !looks_like_codex_cli_toml(&raw_toml) {
        errors.push("unsupported_toml_config".to_string());
        return ImportedAccountBuild { accounts, errors };
    }

    let provider_overlay = parse_codex_cli_provider_overlay(&raw_toml).unwrap_or_default();
    let explicit_auth_file = parse_toml_string_value(&raw_toml, "auth_file");
    let files = if explicit_auth_file.is_empty() {
        collect_auth_json_files(
            config_path.parent().unwrap_or_else(|| Path::new(".")),
            Some(is_likely_codex_auth_filename),
        )
    } else {
        let auth_path = if Path::new(&explicit_auth_file).is_absolute() {
            PathBuf::from(&explicit_auth_file)
        } else {
            config_path
                .parent()
                .unwrap_or_else(|| Path::new("."))
                .join(&explicit_auth_file)
        };
        if auth_path.exists() {
            collect_auth_json_files(&auth_path, None)
        } else {
            Vec::new()
        }
    };

    let overlay = ImportOverlay {
        import_source_kind: "config_path".to_string(),
        import_source_ref: source_ref,
        ..provider_overlay
    };
    let build = build_imported_auth_accounts(&files, &overlay, now_ms);
    accounts.extend(build.accounts);
    errors.extend(build.errors);
    ImportedAccountBuild { accounts, errors }
}

fn apply_imported_accounts_to_store(
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

fn normalize_imported_account_value(value: &mut Value, now_ms: u64) -> Result<(), ()> {
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

fn record_import_source_status_in_store(
    store_value: &mut Value,
    kind: &str,
    source_ref: &str,
    state: &str,
    imported: u32,
    errors: &[String],
    now_ms: u64,
) {
    ensure_provider_store_shape(store_value);
    let source_key = import_source_key(kind, source_ref);
    if source_key.is_empty() {
        return;
    }
    let import_sources = store_value
        .get_mut("import_sources")
        .and_then(Value::as_array_mut)
        .expect("import_sources is array");
    if !import_sources
        .iter()
        .any(|value| value.as_str() == Some(source_key.as_str()))
    {
        import_sources.push(Value::String(source_key.clone()));
        import_sources.sort_by(|lhs, rhs| lhs.as_str().cmp(&rhs.as_str()));
    }
    let owned_count = count_owned_accounts_for_source(store_value, &source_key);
    let status = json!({
        "kind": kind,
        "source_ref": source_ref,
        "state": if state == "ready" { "ready" } else { "sync_failed" },
        "last_sync_at_ms": now_ms,
        "last_imported_count": imported,
        "owned_account_count": owned_count,
        "last_error_count": errors.len() as u32,
        "last_errors": errors.iter().take(4).cloned().collect::<Vec<String>>(),
        "updated_at_ms": now_ms,
    });
    if let Some(statuses) = store_value
        .get_mut("import_source_statuses")
        .and_then(Value::as_object_mut)
    {
        statuses.insert(source_key, status);
    }
}

fn count_owned_accounts_for_source(store_value: &Value, owner_key: &str) -> u32 {
    let mut count = 0_u32;
    let Some(providers) = store_value.get("providers").and_then(Value::as_object) else {
        return 0;
    };
    for provider_value in providers.values() {
        let Some(accounts) = provider_value.get("accounts").and_then(Value::as_array) else {
            continue;
        };
        for account in accounts {
            if string_array_value(account.get("source_owners"))
                .iter()
                .any(|owner| owner == owner_key)
            {
                count = count.saturating_add(1);
            }
        }
    }
    count
}

fn import_source_key(kind: &str, source_ref: &str) -> String {
    let kind = normalized_token(kind);
    let source_ref = trim_string(source_ref);
    if kind.is_empty() || source_ref.is_empty() {
        String::new()
    } else {
        format!("{kind}:{source_ref}")
    }
}

fn parse_provider_from_payload(payload: &Value, filename: &str) -> Option<String> {
    let raw_provider = first_non_empty(&[
        &json_string(payload, "provider"),
        &json_string(payload, "type"),
        &json_string(payload, "account_type"),
        &json_string(payload, "accountType"),
        &json_string(payload, "auth_mode"),
        &json_string(payload, "auth_provider"),
        &json_string(payload, "oauth_source"),
        &json_string(payload, "oauth-source"),
    ])
    .unwrap_or_default();
    normalize_provider(&raw_provider).or_else(|| parse_provider_from_filename(filename))
}

fn parse_provider_from_filename(filename: &str) -> Option<String> {
    let lower = normalized_token(filename);
    for provider in [
        "codex",
        "antigravity",
        "claude",
        "gemini",
        "kiro",
        "copilot",
        "qwen",
        "iflow",
    ] {
        if lower.starts_with(provider) {
            return Some(provider.to_string());
        }
    }
    None
}

fn auth_file_default_base_url(provider: &str, auth_type: &str, oauth_source_key: &str) -> String {
    if auth_type == "oauth" && oauth_source_key == "chatgpt" {
        return "https://api.openai.com/v1".to_string();
    }
    match canonical_pool_provider(provider).as_str() {
        "openai" => "https://api.openai.com/v1".to_string(),
        "claude" => "https://api.anthropic.com".to_string(),
        "gemini" => "https://generativelanguage.googleapis.com".to_string(),
        _ => String::new(),
    }
}

fn auth_file_default_wire_api(provider: &str, auth_type: &str, oauth_source_key: &str) -> String {
    if auth_type == "oauth" && oauth_source_key == "chatgpt" {
        return "chat_completions".to_string();
    }
    if canonical_pool_provider(provider) == "openai" {
        return "chat_completions".to_string();
    }
    String::new()
}

fn resolved_imported_wire_api(
    explicit_wire_api: &str,
    provider: &str,
    auth_type: &str,
    oauth_source_key: &str,
    overlay_source: &str,
) -> String {
    let explicit = normalize_wire_api(explicit_wire_api);
    let fallback = auth_file_default_wire_api(provider, auth_type, oauth_source_key);
    if overlay_source == "fallback_openai" && !fallback.is_empty() {
        return fallback;
    }
    fallback_if_empty(explicit, &fallback)
}

fn parse_codex_cli_provider_overlay(raw_toml: &str) -> Option<ImportOverlay> {
    let mut preferred_provider = String::new();
    let mut preferred_model = String::new();
    let mut current: Option<CodexProviderTomlRow> = None;
    let mut rows = Vec::new();

    for raw_line in raw_toml.lines() {
        let line = raw_line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if line.starts_with('[') && line.ends_with(']') {
            if let Some(row) = current.take().filter(|row| !row.name.is_empty()) {
                rows.push(row);
            }
            let section = line.trim_start_matches('[').trim_end_matches(']').trim();
            if let Some(name) = section.strip_prefix("model_providers.") {
                current = Some(CodexProviderTomlRow {
                    name: name.trim().to_string(),
                    ..CodexProviderTomlRow::default()
                });
            }
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let key = key.trim();
        let value = value.trim();
        if let Some(row) = current.as_mut() {
            match key {
                "base_url" => row.base_url = unquote_toml_value(value),
                "requires_openai_auth" => {
                    row.requires_openai_auth = normalized_token(value) == "true"
                }
                "wire_api" => row.wire_api = normalize_wire_api(&unquote_toml_value(value)),
                _ => {}
            }
        } else if key == "model_provider" {
            preferred_provider = normalized_token(&unquote_toml_value(value));
        } else if key == "model" {
            preferred_model = unquote_toml_value(value);
        }
    }
    if let Some(row) = current.take().filter(|row| !row.name.is_empty()) {
        rows.push(row);
    }

    let explicit_rows: Vec<CodexProviderTomlRow> = rows
        .into_iter()
        .filter(|row| row.requires_openai_auth && !row.base_url.trim().is_empty())
        .collect();
    let selected = if preferred_provider.is_empty() {
        explicit_rows.first().cloned()
    } else {
        explicit_rows
            .iter()
            .find(|row| normalized_token(&row.name) == preferred_provider)
            .cloned()
            .or_else(|| explicit_rows.first().cloned())
    };
    if let Some(row) = selected {
        return Some(ImportOverlay {
            base_url: row.base_url,
            wire_api: normalize_wire_api(&row.wire_api),
            source: "explicit_provider".to_string(),
            ..ImportOverlay::default()
        });
    }

    if preferred_provider.is_empty()
        || preferred_provider == "openai"
        || preferred_provider == "chatgpt"
        || !preferred_model.trim().is_empty()
    {
        return Some(ImportOverlay {
            base_url: "https://api.openai.com/v1".to_string(),
            wire_api: "responses".to_string(),
            source: "fallback_openai".to_string(),
            ..ImportOverlay::default()
        });
    }

    None
}

#[derive(Debug, Clone, Default)]
struct CodexProviderTomlRow {
    name: String,
    base_url: String,
    requires_openai_auth: bool,
    wire_api: String,
}

fn parse_toml_string_value(raw_content: &str, key: &str) -> String {
    for raw_line in raw_content.lines() {
        let line = raw_line.trim();
        if line.starts_with('#') {
            continue;
        }
        let Some((line_key, value)) = line.split_once('=') else {
            continue;
        };
        if line_key.trim() == key {
            return unquote_toml_value(value.trim());
        }
    }
    String::new()
}

fn unquote_toml_value(raw: &str) -> String {
    let value = trim_string(raw);
    if value.len() >= 2 && value.starts_with('"') && value.ends_with('"') {
        value[1..value.len() - 1].to_string()
    } else {
        value
    }
}

fn looks_like_codex_cli_toml(raw_content: &str) -> bool {
    raw_content.lines().any(|line| {
        let trimmed = line.trim();
        trimmed.starts_with("model =")
            || trimmed.starts_with("model_reasoning_effort =")
            || trimmed.starts_with("[projects.")
    })
}

fn is_likely_codex_auth_filename(path: &Path) -> bool {
    let name = path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or_default()
        .to_ascii_lowercase();
    if !name.ends_with(".json") {
        return false;
    }
    let stem = name.trim_end_matches(".json");
    stem == "auth"
        || stem
            .strip_prefix("auth")
            .map(|tail| tail.chars().all(|c| c.is_ascii_digit()))
            .unwrap_or(false)
}

fn merged_token_bag(payload: &Value) -> Map<String, Value> {
    let mut out = Map::new();
    for key in ["token", "tokens"] {
        if let Some(object) = payload.get(key).and_then(Value::as_object) {
            for (item_key, item_value) in object {
                out.insert(item_key.clone(), item_value.clone());
            }
        }
    }
    out
}

fn oauth_refresh_config_value(payload: &Value, token_bag: &Map<String, Value>) -> Value {
    let mut source = Map::new();
    for (key, value) in token_bag {
        source.insert(key.clone(), value.clone());
    }
    for key in [
        "oauth_refresh_config",
        "oauthRefreshConfig",
        "oauth_refresh",
        "oauthRefresh",
        "oauth_metadata",
        "oauthMetadata",
    ] {
        if let Some(object) = payload.get(key).and_then(Value::as_object) {
            for (item_key, item_value) in object {
                source.insert(item_key.clone(), item_value.clone());
            }
        }
    }
    let mut out = Map::new();
    for (target, aliases) in [
        (
            "token_uri",
            &[
                "token_uri",
                "tokenURI",
                "tokenUrl",
                "token_url",
                "token-uri",
            ][..],
        ),
        ("client_id", &["client_id", "clientId", "client-id"][..]),
        (
            "client_secret",
            &["client_secret", "clientSecret", "client-secret"][..],
        ),
        (
            "universe_domain",
            &["universe_domain", "universeDomain", "universe-domain"][..],
        ),
    ] {
        for alias in aliases {
            let value = map_string(&source, alias);
            if !value.is_empty() {
                out.insert(target.to_string(), Value::String(value));
                break;
            }
        }
    }
    let scopes = source
        .get("scopes")
        .or_else(|| source.get("scope"))
        .map(string_list_from_value)
        .unwrap_or_default();
    if !scopes.is_empty() {
        out.insert(
            "scopes".to_string(),
            Value::Array(scopes.into_iter().map(Value::String).collect()),
        );
    }
    if out.is_empty() {
        Value::Null
    } else {
        Value::Object(out)
    }
}

fn map_string(map: &Map<String, Value>, key: &str) -> String {
    map.get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string()
}

fn json_u64_any(value: &Value, keys: &[&str]) -> u64 {
    keys.iter()
        .map(|key| json_u64(value, key))
        .find(|value| *value > 0)
        .unwrap_or(0)
}

fn string_array_value(value: Option<&Value>) -> Vec<String> {
    value
        .and_then(Value::as_array)
        .map(|items| {
            let mut out: Vec<String> = items
                .iter()
                .filter_map(Value::as_str)
                .map(trim_string)
                .filter(|item| !item.is_empty())
                .collect();
            out.sort();
            out.dedup();
            out
        })
        .unwrap_or_default()
}

fn string_list_from_value(value: &Value) -> Vec<String> {
    if let Some(items) = value.as_array() {
        let mut out: Vec<String> = items
            .iter()
            .filter_map(Value::as_str)
            .map(trim_string)
            .filter(|item| !item.is_empty())
            .collect();
        out.sort();
        out.dedup();
        return out;
    }
    json_string(&json!({"value": value}), "value")
        .split(|ch: char| ch == ',' || ch.is_whitespace())
        .map(trim_string)
        .filter(|item| !item.is_empty())
        .collect()
}

fn date_like_to_ms(value: &Value) -> u64 {
    let parsed = value
        .as_u64()
        .or_else(|| {
            value
                .as_i64()
                .and_then(|number| u64::try_from(number.max(0)).ok())
        })
        .or_else(|| {
            value
                .as_str()
                .and_then(|raw| raw.trim().parse::<u64>().ok())
        })
        .unwrap_or(0);
    if parsed > 0 && parsed < 1_000_000_000_000 {
        parsed.saturating_mul(1000)
    } else {
        parsed
    }
}

fn path_has_segment(path: &Path, segment: &str) -> bool {
    path.components().any(|component| {
        component
            .as_os_str()
            .to_string_lossy()
            .eq_ignore_ascii_case(segment)
    })
}

fn host_from_url(raw: &str) -> String {
    let value = trim_string(raw);
    if value.is_empty() {
        return String::new();
    }
    let without_scheme = value
        .split_once("://")
        .map(|(_, rest)| rest)
        .unwrap_or(value.as_str());
    let authority = without_scheme.split('/').next().unwrap_or_default();
    let host_port = authority.rsplit('@').next().unwrap_or(authority);
    host_port
        .split(':')
        .next()
        .unwrap_or_default()
        .trim()
        .to_ascii_lowercase()
}

fn stable_short_fingerprint(material: &str) -> String {
    let mut hash = 0xcbf29ce484222325_u64;
    for byte in material.as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    format!("{hash:016x}")
}

fn fallback_if_empty(value: String, fallback: &str) -> String {
    if value.trim().is_empty() {
        fallback.to_string()
    } else {
        value
    }
}

fn default_quota_value() -> Value {
    json!({
        "daily_token_cap": 0,
        "daily_tokens_used": 0,
        "daily_tokens_remaining": 0,
        "total_tokens_used": 0,
        "last_used_at_ms": 0,
        "last_error_at_ms": 0,
        "consecutive_errors": 0,
        "cooldown_until_ms": 0,
        "next_refresh_at_ms": 0,
        "usage_windows": [],
    })
}

fn default_error_state_value() -> Value {
    json!({
        "status": "healthy",
        "status_message": "",
        "reason_code": "",
        "last_error_code": "",
        "last_error_at_ms": 0,
        "next_retry_at_ms": 0,
        "retry_at_source": "",
        "auto_disabled": false,
    })
}

fn default_refresh_state_value() -> Value {
    json!({
        "status": "idle",
        "last_attempt_at_ms": 0,
        "last_success_at_ms": 0,
        "next_refresh_at_ms": 0,
        "failure_count": 0,
        "last_error_code": "",
        "last_error_message": "",
    })
}

fn load_provider_store_value_for_write(path: &Path) -> Result<Value, ProviderRouteError> {
    if !path.is_file() {
        return Err(ProviderRouteError::Invalid(format!(
            "provider store file not found: {}",
            path.display()
        )));
    }
    let raw = fs::read_to_string(path)
        .map_err(|err| ProviderRouteError::Io(format!("{}: {err}", path.display())))?;
    serde_json::from_str(&raw)
        .map_err(|err| ProviderRouteError::Json(format!("{}: {err}", path.display())))
}

fn write_provider_store_value_atomic(path: &Path, value: &Value) -> Result<(), ProviderRouteError> {
    let parent = path.parent().ok_or_else(|| {
        ProviderRouteError::Invalid(format!("provider store has no parent: {}", path.display()))
    })?;
    fs::create_dir_all(parent)
        .map_err(|err| ProviderRouteError::Io(format!("{}: {err}", parent.display())))?;
    let tmp = parent.join(format!(
        ".{}.tmp_{}_{}",
        path.file_name()
            .and_then(|name| name.to_str())
            .unwrap_or(PROVIDER_STORE_FILE_NAME),
        std::process::id(),
        current_process_unique_suffix()
    ));
    let body = serde_json::to_string_pretty(value)
        .map_err(|err| ProviderRouteError::Json(format!("serialize provider store: {err}")))?;
    fs::write(&tmp, format!("{body}\n"))
        .map_err(|err| ProviderRouteError::Io(format!("{}: {err}", tmp.display())))?;
    fs::rename(&tmp, path).map_err(|err| {
        let _ = fs::remove_file(&tmp);
        ProviderRouteError::Io(format!("{} -> {}: {err}", tmp.display(), path.display()))
    })
}

fn current_process_unique_suffix() -> String {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or(0);
    format!("{nanos:x}")
}

fn current_time_millis() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_millis().min(u64::MAX as u128) as u64)
        .unwrap_or(0)
}

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

fn quota_failure_backoff_ms(failure_count: u32, base_backoff_ms: u64, max_backoff_ms: u64) -> u64 {
    let base = base_backoff_ms.max(100);
    let max = max_backoff_ms.max(base);
    let mut delay = base;
    for _ in 1..failure_count.max(1) {
        delay = delay.saturating_mul(2).min(max);
    }
    delay.min(max)
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

fn openai_windows_from_usage(usage: &Value, base_now_ms: u64) -> Vec<ProviderQuotaUsageWindow> {
    let mut windows = Vec::new();
    if let Some(rate_limit) = usage.get("rate_limit").and_then(Value::as_object) {
        let limit_reached = rate_limit
            .get("limit_reached")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        push_openai_window(
            &mut windows,
            "rate_limit",
            "primary",
            rate_limit.get("primary_window"),
            limit_reached,
            "primary",
            base_now_ms,
        );
        push_openai_window(
            &mut windows,
            "rate_limit",
            "secondary",
            rate_limit.get("secondary_window"),
            false,
            "secondary",
            base_now_ms,
        );
    }
    if let Some(rate_limit) = usage
        .get("code_review_rate_limit")
        .and_then(Value::as_object)
    {
        let limit_reached = rate_limit
            .get("limit_reached")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        push_openai_window(
            &mut windows,
            "code_review_rate_limit",
            "primary",
            rate_limit.get("primary_window"),
            limit_reached,
            "code-review primary",
            base_now_ms,
        );
        push_openai_window(
            &mut windows,
            "code_review_rate_limit",
            "secondary",
            rate_limit.get("secondary_window"),
            false,
            "code-review secondary",
            base_now_ms,
        );
    }
    windows
}

fn push_openai_window(
    windows: &mut Vec<ProviderQuotaUsageWindow>,
    source: &str,
    window_key: &str,
    raw_window: Option<&Value>,
    limit_reached: bool,
    label_prefix: &str,
    base_now_ms: u64,
) {
    let Some(raw_window) = raw_window.filter(|value| value.is_object()) else {
        return;
    };
    let used_percent = safe_percent(json_f64(raw_window, "used_percent"));
    let used_basis_points = basis_points_from_percent(used_percent);
    let limit_window_seconds = json_u64(raw_window, "limit_window_seconds");
    let label = codex_window_label(raw_window, label_prefix);
    windows.push(ProviderQuotaUsageWindow {
        key: format!(
            "{}:{}:{}",
            source,
            window_key,
            if limit_window_seconds > 0 {
                limit_window_seconds.to_string()
            } else {
                codex_window_label(raw_window, "")
            }
        ),
        source: source.to_string(),
        window_key: window_key.to_string(),
        label,
        limit_window_seconds,
        used_percent,
        used_basis_points,
        remaining_basis_points: (QUOTA_BASIS_POINTS_CAP as u32).saturating_sub(used_basis_points),
        limited: limit_reached || used_percent >= 100.0,
        reset_at_ms: reset_at_ms_from_window(raw_window, base_now_ms),
        updated_at_ms: base_now_ms,
    });
}

fn sorted_quota_windows(
    mut windows: Vec<ProviderQuotaUsageWindow>,
) -> Vec<ProviderQuotaUsageWindow> {
    windows.sort_by(|lhs, rhs| {
        lhs.source
            .cmp(&rhs.source)
            .then_with(|| lhs.limit_window_seconds.cmp(&rhs.limit_window_seconds))
            .then_with(|| lhs.window_key.cmp(&rhs.window_key))
    });
    windows.dedup_by(|lhs, rhs| {
        lhs.key == rhs.key
            || (lhs.source == rhs.source
                && lhs.window_key == rhs.window_key
                && lhs.limit_window_seconds == rhs.limit_window_seconds)
    });
    windows
}

fn reset_at_ms_from_window(window: &Value, base_now_ms: u64) -> u64 {
    let explicit = json_u64(window, "reset_at");
    if explicit > 0 {
        let reset_at_ms = if explicit > 1_000_000_000_000 {
            explicit
        } else {
            explicit.saturating_mul(1000)
        };
        if reset_at_ms > base_now_ms {
            return reset_at_ms;
        }
    }
    let reset_after_seconds = json_u64(window, "reset_after_seconds");
    if reset_after_seconds > 0 {
        base_now_ms.saturating_add(reset_after_seconds.saturating_mul(1000))
    } else {
        0
    }
}

fn codex_window_label(window: &Value, prefix: &str) -> String {
    let seconds = json_u64(window, "limit_window_seconds");
    let label = if seconds >= 7 * 24 * 3600 {
        "7-day window"
    } else if seconds >= 24 * 3600 {
        "24-hour window"
    } else if seconds >= 5 * 3600 {
        "5-hour window"
    } else if seconds >= 3600 {
        "1-hour window"
    } else {
        "usage window"
    };
    let prefix = trim_string(prefix);
    if prefix.is_empty() {
        label.to_string()
    } else {
        format!("{prefix} {label}")
    }
}

fn quota_managed_error_state(error_state: &Value) -> bool {
    let status = normalized_token(&json_string(error_state, "status"));
    let reason = normalized_token(
        &first_non_empty(&[
            &json_string(error_state, "reason_code"),
            &json_string(error_state, "last_error_code"),
        ])
        .unwrap_or_default(),
    );
    let retry_at_source = normalized_token(&json_string(error_state, "retry_at_source"));
    reason == "blocked_quota"
        || reason == "rate_limited"
        || retry_at_source == QUOTA_REFRESH_RETRY_SOURCE
        || status == "blocked_quota"
        || status == "rate_limited"
}

fn auth_managed_error_state(error_state: &Value) -> bool {
    let status = normalized_token(&json_string(error_state, "status"));
    let reason = normalized_token(
        &first_non_empty(&[
            &json_string(error_state, "reason_code"),
            &json_string(error_state, "last_error_code"),
        ])
        .unwrap_or_default(),
    );
    let retry_at_source = normalized_token(&json_string(error_state, "retry_at_source"));
    retry_at_source == OAUTH_REFRESH_RETRY_SOURCE
        || matches!(
            status.as_str(),
            "auth_failed" | "blocked_auth" | "blocked_config"
        )
        || matches!(
            reason.as_str(),
            "auth_missing"
                | "auth_failed"
                | "blocked_auth"
                | "invalid_api_key"
                | "authentication_failed"
                | "missing_scope"
                | "scope_missing"
                | "token_expired"
                | "invalid_grant"
                | "invalid_client"
                | "unauthorized_client"
                | "access_denied"
                | "refresh_token_reused"
                | "missing_refresh_token"
                | "unsupported_refresh_schema"
                | "missing_oauth_client"
                | "missing_oauth_client_id"
                | "missing_oauth_client_secret"
                | "refresh_failed"
                | "refresh_request_failed"
                | "refresh_timeout"
        )
        || reason.starts_with("refresh_http_401")
        || reason.starts_with("refresh_http_403")
}

fn normalized_error_state_object(error_state: &Value) -> Map<String, Value> {
    let status =
        non_empty_json_string(error_state, "status").unwrap_or_else(|| "healthy".to_string());
    let reason_code = first_non_empty(&[
        &json_string(error_state, "reason_code"),
        &json_string(error_state, "last_error_code"),
    ])
    .unwrap_or_default();
    let mut out = Map::new();
    out.insert("status".to_string(), Value::String(status));
    out.insert(
        "status_message".to_string(),
        Value::String(json_string(error_state, "status_message")),
    );
    out.insert("reason_code".to_string(), Value::String(reason_code));
    out.insert(
        "last_error_code".to_string(),
        Value::String(json_string(error_state, "last_error_code")),
    );
    out.insert(
        "last_error_at_ms".to_string(),
        json!(json_u64(error_state, "last_error_at_ms")),
    );
    out.insert(
        "next_retry_at_ms".to_string(),
        json!(json_u64(error_state, "next_retry_at_ms")),
    );
    out.insert(
        "retry_at_source".to_string(),
        Value::String(json_string(error_state, "retry_at_source")),
    );
    out.insert(
        "auto_disabled".to_string(),
        Value::Bool(json_bool(error_state, "auto_disabled")),
    );
    out
}

fn normalized_refresh_state_object(refresh_state: &Value) -> Map<String, Value> {
    let status =
        non_empty_json_string(refresh_state, "status").unwrap_or_else(|| "idle".to_string());
    let mut out = Map::new();
    out.insert("status".to_string(), Value::String(status));
    out.insert(
        "last_attempt_at_ms".to_string(),
        json!(json_u64(refresh_state, "last_attempt_at_ms")),
    );
    out.insert(
        "last_success_at_ms".to_string(),
        json!(json_u64(refresh_state, "last_success_at_ms")),
    );
    out.insert(
        "next_refresh_at_ms".to_string(),
        json!(json_u64(refresh_state, "next_refresh_at_ms")),
    );
    out.insert(
        "failure_count".to_string(),
        json!(json_u64(refresh_state, "failure_count")),
    );
    out.insert(
        "last_error_code".to_string(),
        Value::String(json_string(refresh_state, "last_error_code")),
    );
    out.insert(
        "last_error_message".to_string(),
        Value::String(json_string(refresh_state, "last_error_message")),
    );
    out
}

fn normalized_oauth_refresh_error_code(raw: &str) -> String {
    let token = normalized_token(raw);
    if token.is_empty() {
        return "refresh_failed".to_string();
    }
    if token == "401" || token == "403" {
        return format!("refresh_http_{token}");
    }
    if token == "408" || token == "504" {
        return "refresh_timeout".to_string();
    }
    if token.contains("refresh_token_reused") {
        return "refresh_token_reused".to_string();
    }
    if token.contains("invalid_grant") {
        return "invalid_grant".to_string();
    }
    if token.contains("timed out") || token.contains("timeout") || token.contains("etimedout") {
        return "refresh_timeout".to_string();
    }
    if token.contains("network")
        || token.contains("dns")
        || token.contains("econnrefused")
        || token.contains("econnreset")
        || token.contains("enotfound")
    {
        return "refresh_request_failed".to_string();
    }
    let mut out = String::new();
    let mut previous_underscore = false;
    for ch in token.chars() {
        let next = if ch.is_ascii_alphanumeric() {
            ch
        } else if ch == '_' {
            '_'
        } else {
            '_'
        };
        if next == '_' {
            if previous_underscore {
                continue;
            }
            previous_underscore = true;
        } else {
            previous_underscore = false;
        }
        out.push(next);
    }
    let normalized = out.trim_matches('_').to_string();
    if normalized.is_empty() {
        "refresh_failed".to_string()
    } else if normalized.starts_with("http_") {
        format!("refresh_{normalized}")
    } else {
        normalized
    }
}

fn sanitized_status_message(raw: &str, fallback_code: &str) -> String {
    let fallback = first_non_empty(&[fallback_code, "refresh_failed"]).unwrap_or_default();
    let message = raw
        .split_whitespace()
        .collect::<Vec<&str>>()
        .join(" ")
        .trim()
        .to_string();
    if message.is_empty() {
        return fallback;
    }
    let lower = message.to_lowercase();
    if lower.contains("access_token")
        || lower.contains("refresh_token")
        || lower.contains("id_token")
        || lower.contains("authorization")
        || lower.contains("bearer ")
        || lower.contains("sk-")
        || lower.contains("session key")
    {
        return fallback;
    }
    if message.len() > 240 {
        let mut truncated = message.chars().take(240).collect::<String>();
        truncated.push_str("...");
        truncated
    } else {
        message
    }
}

fn oauth_refresh_terminal_error(error_code: &str) -> bool {
    let code = normalized_token(error_code);
    matches!(
        code.as_str(),
        "invalid_grant"
            | "refresh_token_reused"
            | "invalid_client"
            | "unauthorized_client"
            | "access_denied"
            | "missing_refresh_token"
            | "unsupported_refresh_schema"
            | "missing_oauth_client"
            | "missing_oauth_client_id"
            | "missing_oauth_client_secret"
    ) || code.starts_with("refresh_http_401")
        || code.starts_with("refresh_http_403")
}

fn oauth_refresh_error_status(error_code: &str) -> &'static str {
    let code = normalized_token(error_code);
    if matches!(
        code.as_str(),
        "missing_refresh_token"
            | "unsupported_refresh_schema"
            | "missing_oauth_client"
            | "missing_oauth_client_id"
            | "missing_oauth_client_secret"
    ) {
        return "blocked_config";
    }
    if matches!(
        code.as_str(),
        "invalid_grant"
            | "refresh_token_reused"
            | "invalid_client"
            | "unauthorized_client"
            | "access_denied"
    ) || code.starts_with("refresh_http_401")
        || code.starts_with("refresh_http_403")
    {
        return "blocked_auth";
    }
    if matches!(code.as_str(), "refresh_timeout" | "refresh_request_failed") {
        return "blocked_network";
    }
    "blocked_provider"
}

fn normalized_quota_object(quota: &Value) -> Map<String, Value> {
    let mut out = Map::new();
    out.insert(
        "daily_token_cap".to_string(),
        json!(json_u64(quota, "daily_token_cap")),
    );
    out.insert(
        "daily_tokens_used".to_string(),
        json!(json_u64(quota, "daily_tokens_used")),
    );
    out.insert(
        "daily_tokens_remaining".to_string(),
        json!(json_u64(quota, "daily_tokens_remaining")),
    );
    out.insert(
        "total_tokens_used".to_string(),
        json!(json_u64(quota, "total_tokens_used")),
    );
    out.insert(
        "last_used_at_ms".to_string(),
        json!(json_u64(quota, "last_used_at_ms")),
    );
    out.insert(
        "last_error_at_ms".to_string(),
        json!(json_u64(quota, "last_error_at_ms")),
    );
    out.insert(
        "consecutive_errors".to_string(),
        json!(json_u64(quota, "consecutive_errors")),
    );
    out.insert(
        "cooldown_until_ms".to_string(),
        json!(json_u64(quota, "cooldown_until_ms")),
    );
    out.insert(
        "next_refresh_at_ms".to_string(),
        json!(json_u64(quota, "next_refresh_at_ms")),
    );
    if let Some(windows) = quota.get("usage_windows").filter(|value| value.is_array()) {
        out.insert("usage_windows".to_string(), windows.clone());
    }
    out
}

#[derive(Debug, Clone, Default)]
struct OpenAIQuotaMetadata {
    account_id: String,
    oauth_source_key: String,
    can_use_direct_access_token: bool,
}

fn openai_quota_metadata_for_account(account: &ProviderAccount) -> OpenAIQuotaMetadata {
    let claims = decode_jwt_payload_value(&account.api_key);
    let auth_claims = claims
        .as_ref()
        .and_then(|value| value.get("https://api.openai.com/auth"));
    let account_id = first_non_empty(&[
        &account.account_id,
        &auth_claims
            .map(|value| json_string(value, "chatgpt_account_id"))
            .unwrap_or_default(),
        &claims
            .as_ref()
            .map(|value| json_string(value, "chatgpt_account_id"))
            .unwrap_or_default(),
        &claims
            .as_ref()
            .map(|value| json_string(value, "account_id"))
            .unwrap_or_default(),
    ])
    .unwrap_or_default();
    let oauth_source_key = first_non_empty(&[
        &account.oauth_source_key,
        if !account_id.is_empty() && claims.is_some() {
            "chatgpt"
        } else {
            ""
        },
    ])
    .unwrap_or_default();
    OpenAIQuotaMetadata {
        account_id: trim_string(&account_id),
        oauth_source_key: normalized_token(&oauth_source_key),
        can_use_direct_access_token: claims.is_some() && !account_id.trim().is_empty(),
    }
}

fn supported_openai_quota_account_with_metadata(
    account: &ProviderAccount,
    metadata: &OpenAIQuotaMetadata,
) -> bool {
    if metadata.account_id.is_empty() {
        return false;
    }
    let provider = normalized_token(&account.provider);
    if provider == "openai" || provider == "codex" {
        return account.auth_index > 0 || metadata.can_use_direct_access_token;
    }
    if OPENAI_USAGE_WINDOW_OAUTH_SOURCES
        .iter()
        .any(|source| *source == metadata.oauth_source_key.as_str())
    {
        return account.auth_index > 0 || metadata.can_use_direct_access_token;
    }
    metadata.can_use_direct_access_token
}

fn decode_jwt_payload_value(token: &str) -> Option<Value> {
    let mut segments = token.trim().split('.');
    let _header = segments.next()?;
    let payload = segments.next()?;
    if payload.trim().is_empty() {
        return None;
    }
    let decoded = decode_base64_url(payload)?;
    serde_json::from_slice::<Value>(&decoded)
        .ok()
        .filter(Value::is_object)
}

fn decode_base64_url(input: &str) -> Option<Vec<u8>> {
    let mut out = Vec::with_capacity(input.len().saturating_mul(3) / 4);
    let mut buffer = 0_u32;
    let mut bits = 0_u8;
    for byte in input.bytes() {
        let value = match byte {
            b'A'..=b'Z' => u32::from(byte - b'A'),
            b'a'..=b'z' => u32::from(byte - b'a') + 26,
            b'0'..=b'9' => u32::from(byte - b'0') + 52,
            b'+' | b'-' => 62,
            b'/' | b'_' => 63,
            b'=' => break,
            b'\r' | b'\n' | b'\t' | b' ' => continue,
            _ => return None,
        };
        buffer = (buffer << 6) | value;
        bits = bits.saturating_add(6);
        if bits >= 8 {
            bits -= 8;
            out.push(((buffer >> bits) & 0xff) as u8);
            if bits > 0 {
                buffer &= (1 << bits) - 1;
            } else {
                buffer = 0;
            }
        }
    }
    Some(out)
}

fn set_json_u64_object(value: &mut Value, key: &str, number: u64) {
    if !value.is_object() {
        *value = Value::Object(Map::new());
    }
    if let Some(object) = value.as_object_mut() {
        object.insert(key.to_string(), json!(number));
    }
}

fn json_string(value: &Value, key: &str) -> String {
    value
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim()
        .to_string()
}

fn non_empty_json_string(value: &Value, key: &str) -> Option<String> {
    let raw = json_string(value, key);
    if raw.is_empty() {
        None
    } else {
        Some(raw)
    }
}

fn json_bool(value: &Value, key: &str) -> bool {
    value.get(key).and_then(Value::as_bool).unwrap_or(false)
}

fn json_u64(value: &Value, key: &str) -> u64 {
    value
        .get(key)
        .and_then(|item| {
            item.as_u64().or_else(|| {
                item.as_i64()
                    .and_then(|number| u64::try_from(number.max(0)).ok())
            })
        })
        .or_else(|| {
            value
                .get(key)
                .and_then(Value::as_str)
                .and_then(|raw| raw.trim().parse::<u64>().ok())
        })
        .unwrap_or(0)
}

fn json_f64(value: &Value, key: &str) -> f64 {
    value
        .get(key)
        .and_then(|item| {
            item.as_f64()
                .or_else(|| item.as_str()?.trim().parse::<f64>().ok())
        })
        .unwrap_or(0.0)
}

fn safe_percent(value: f64) -> f64 {
    if value.is_finite() {
        value.clamp(0.0, 100.0)
    } else {
        0.0
    }
}

fn basis_points_from_percent(percent: f64) -> u32 {
    let basis_points = (safe_percent(percent) * 100.0).round();
    basis_points.clamp(0.0, QUOTA_BASIS_POINTS_CAP as f64) as u32
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

fn account_pool_state(account: &ProviderAccount, now_ms: u128, model_id: &str) -> PoolState {
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

fn pool_state(state: &str, reason_code: &str, status_message: &str, retry_at_ms: u64) -> PoolState {
    PoolState {
        state: normalized_token(state),
        reason_code: normalized_token(reason_code),
        status_message: trim_string(status_message),
        retry_at_ms,
    }
}

fn pool_state_from_model_state(model_state: &ProviderModelState) -> Option<PoolState> {
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

fn provider_matches_pool_filter(account: &ProviderAccount, provider_filter: &str) -> bool {
    let filter =
        normalize_provider(provider_filter).unwrap_or_else(|| normalized_token(provider_filter));
    if filter.is_empty() {
        return true;
    }
    canonical_pool_provider(&account.provider) == canonical_pool_provider(&filter)
}

fn account_supports_capability_target(account: &ProviderAccount, model_id: &str) -> bool {
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

fn canonical_pool_provider(raw: &str) -> String {
    let provider = normalize_provider(raw).unwrap_or_else(|| normalized_token(raw));
    match provider.as_str() {
        "chatgpt" | "openai-chatgpt" | "codex" | "openai" => "openai".to_string(),
        "anthropic" | "claude" => "claude".to_string(),
        "google" | "gemini" => "gemini".to_string(),
        _ => provider,
    }
}

fn account_effective_pool_id(account: &ProviderAccount) -> String {
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

fn default_provider_host(provider: &str) -> String {
    match canonical_pool_provider(provider).as_str() {
        "openai" => "api.openai.com".to_string(),
        "claude" => "api.anthropic.com".to_string(),
        "gemini" => "generativelanguage.googleapis.com".to_string(),
        _ => String::new(),
    }
}

fn normalize_wire_api(raw: &str) -> String {
    match normalized_token(raw).as_str() {
        "responses" | "response" | "responses_api" => "responses".to_string(),
        "chat" | "chatcompletions" | "chat_completions" | "chat-completions"
        | "chat/completions" => "chat_completions".to_string(),
        _ => String::new(),
    }
}

fn normalize_tier_bucket(raw: &str) -> String {
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

fn is_paid_tier_bucket(tier: &str) -> bool {
    matches!(
        normalized_token(tier).as_str(),
        "plus" | "pro" | "team" | "enterprise" | "paid"
    )
}

fn removal_reason_for_account_state(account: &ProviderAccount, state: &PoolState) -> String {
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

fn is_auth_failure_reason(reason_code: &str) -> bool {
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

fn known_quota_for_account(account: &ProviderAccount) -> bool {
    let quota = &account.quota;
    quota.daily_token_cap > 0
        || quota.daily_tokens_used > 0
        || quota.daily_tokens_remaining > 0
        || quota.total_tokens_used > 0
        || quota.last_used_at_ms > 0
        || quota.last_error_at_ms > 0
}

fn summarized_pool_state(
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

fn state_sort_weight(state: &str) -> u8 {
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

fn redact_api_key(key: &str) -> String {
    let value = trim_string(key);
    if value.len() <= 8 {
        return "****".to_string();
    }
    format!("{}...{}", &value[..4], &value[value.len() - 4..])
}

fn auth_type_or_default(raw: &str) -> String {
    first_non_empty(&[raw]).unwrap_or_else(default_auth_type)
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
    fn import_auth_dir_supports_codex_cli_nested_tokens() {
        let dir = unique_temp_dir("xhub-provider-import-auth-dir");
        let auth_dir = unique_temp_dir("xhub-provider-import-auth-source");
        std::fs::create_dir_all(&dir).expect("runtime dir should be created");
        std::fs::create_dir_all(&auth_dir).expect("auth dir should be created");
        std::fs::write(
            auth_dir.join("auth17.json"),
            r#"{
              "auth_mode": "chatgpt",
              "tokens": {
                "id_token": "h.eyJlbWFpbCI6ImNvZGV4LXVzZXJAdGVzdC5jb20iLCJjaGF0Z3B0X2FjY291bnRfaWQiOiJhY2N0LWNvZGV4LWNsaS0xIiwiZXhwIjoyMDAwMDAwMDAwfQ.s",
                "access_token": "codex-cli-access-token",
                "refresh_token": "codex-cli-refresh-token",
                "account_id": "acct-codex-cli-1"
              }
            }"#,
        )
        .expect("auth file should be written");

        let result =
            import_auth_dir_to_runtime_base_dir(&dir, &auth_dir.to_string_lossy(), NOW as u64)
                .expect("auth import should run");
        assert!(result.ok);
        assert_eq!(result.imported, 1);
        assert!(result.errors.is_empty());

        let store = ProviderKeyStore::load_runtime_base_dir(&dir).expect("store should load");
        let accounts = &store.providers["codex"].accounts;
        assert_eq!(accounts.len(), 1);
        assert_eq!(accounts[0].email, "codex-user@test.com");
        assert_eq!(accounts[0].auth_type, "oauth");
        assert_eq!(accounts[0].account_id, "acct-codex-cli-1");
        assert_eq!(accounts[0].source_type, "auth_file");
        assert!(accounts[0].source_ref.ends_with("auth17.json"));
        assert_eq!(accounts[0].oauth_source_key, "chatgpt");
        assert_eq!(accounts[0].wire_api, "chat_completions");
        assert_eq!(accounts[0].provider_host, "api.openai.com");
        assert!(accounts[0]
            .source_owners
            .iter()
            .any(|owner| owner.starts_with("auth_dir:")));

        let snapshot = provider_runtime_snapshot_from_runtime_base_dir(&dir, "codex")
            .expect("snapshot should load");
        assert_eq!(snapshot.accounts.len(), 1);
        assert_eq!(snapshot.accounts[0].api_key_redacted, "code...oken");
        assert_eq!(snapshot.import_source_statuses[0].state, "ready");
        assert_eq!(snapshot.import_source_statuses[0].owned_account_count, 1);
        let _ = std::fs::remove_dir_all(&dir);
        let _ = std::fs::remove_dir_all(&auth_dir);
    }

    #[test]
    fn import_codex_cli_config_imports_sibling_auth_files_with_config_owner() {
        let dir = unique_temp_dir("xhub-provider-import-config-dir");
        let codex_dir = unique_temp_dir("xhub-provider-import-codex-dir");
        std::fs::create_dir_all(&dir).expect("runtime dir should be created");
        std::fs::create_dir_all(&codex_dir).expect("codex dir should be created");
        let config_path = codex_dir.join("config.toml");
        std::fs::write(
            &config_path,
            r#"
model = "gpt-5.4"
model_reasoning_effort = "xhigh"
"#,
        )
        .expect("config should be written");
        std::fs::write(
            codex_dir.join("auth19.json"),
            r#"{
              "auth_mode": "chatgpt",
              "tokens": {
                "id_token": "h.eyJlbWFpbCI6ImNvZGV4LXVzZXJAdGVzdC5jb20iLCJjaGF0Z3B0X2FjY291bnRfaWQiOiJhY2N0LWNvZGV4LWNsaS0xIiwiZXhwIjoyMDAwMDAwMDAwfQ.s",
                "access_token": "codex-cli-access-token",
                "refresh_token": "codex-cli-refresh-token",
                "account_id": "acct-codex-cli-1"
              }
            }"#,
        )
        .expect("auth file should be written");

        let result = import_proxy_config_to_runtime_base_dir(
            &dir,
            &config_path.to_string_lossy(),
            NOW as u64,
        )
        .expect("config import should run");
        assert!(result.ok);
        assert_eq!(result.imported, 1);

        let store = ProviderKeyStore::load_runtime_base_dir(&dir).expect("store should load");
        let account = &store.providers["codex"].accounts[0];
        assert_eq!(account.base_url, "https://api.openai.com/v1");
        assert_eq!(account.provider_host, "api.openai.com");
        assert_eq!(account.wire_api, "chat_completions");
        assert!(account
            .source_owners
            .iter()
            .any(|owner| owner.starts_with("config_path:")));

        let snapshot = provider_runtime_snapshot_from_runtime_base_dir(&dir, "codex")
            .expect("snapshot should load");
        assert_eq!(snapshot.import_source_statuses[0].kind, "config_path");
        assert_eq!(snapshot.import_source_statuses[0].state, "ready");
        assert_eq!(snapshot.import_source_statuses[0].owned_account_count, 1);
        let _ = std::fs::remove_dir_all(&dir);
        let _ = std::fs::remove_dir_all(&codex_dir);
    }

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

    #[test]
    fn key_pool_snapshot_aggregates_shared_openai_codex_accounts() {
        let mut openai = account("openai-plus", "openai", 10, &["gpt-5.4"]);
        openai.pool_id = "shared-gpt54".to_string();
        openai.tier = "plus".to_string();
        openai.quota.daily_token_cap = 1000;
        openai.quota.daily_tokens_used = 250;
        openai.quota.daily_tokens_remaining = 750;
        openai.quota.total_tokens_used = 1250;

        let mut codex = account("codex-free", "codex", 1, &["gpt5.4"]);
        codex.pool_id = "shared-gpt54".to_string();
        codex.tier = "free".to_string();
        codex.quota.daily_token_cap = 100;
        codex.quota.daily_tokens_used = 10;
        codex.quota.daily_tokens_remaining = 90;

        let mut providers = BTreeMap::new();
        providers.insert(
            "openai".to_string(),
            ProviderData {
                routing_strategy: "fill-first".to_string(),
                accounts: vec![openai],
            },
        );
        providers.insert(
            "codex".to_string(),
            ProviderData {
                routing_strategy: "fill-first".to_string(),
                accounts: vec![codex],
            },
        );
        let store = ProviderKeyStore {
            updated_at_ms: 123,
            routing_strategy: "priority".to_string(),
            providers,
            ..ProviderKeyStore::default()
        };

        let snapshot = provider_key_pools(&store, "openai", "openai/gpt5.4", true, NOW);

        assert_eq!(snapshot.pools.len(), 1);
        let pool = &snapshot.pools[0];
        assert_eq!(pool.provider, "openai");
        assert_eq!(pool.pool_id, "shared-gpt54");
        assert_eq!(pool.capability_pool_id, "shared-gpt54#openai:gpt-5.4");
        assert_eq!(pool.total_accounts, 2);
        assert_eq!(pool.ready_accounts, 2);
        assert_eq!(pool.free_accounts, 1);
        assert_eq!(pool.paid_accounts, 1);
        assert_eq!(pool.daily_token_cap, 1100);
        assert_eq!(pool.daily_tokens_used, 260);
        assert_eq!(pool.daily_tokens_remaining, 840);
        assert_eq!(pool.members.len(), 2);
        assert!(pool.source_providers.contains(&"codex".to_string()));
        assert!(pool.source_providers.contains(&"openai".to_string()));
    }

    #[test]
    fn runtime_snapshot_preserves_quota_windows_without_secrets() {
        let mut acct = account("quota", "openai", 1, &["gpt-5.4"]);
        acct.api_key = "sk-secret-value".to_string();
        acct.email = "user@example.test".to_string();
        acct.quota.usage_windows = vec![ProviderQuotaUsageWindow {
            key: "rate_limit:5h".to_string(),
            source: "rate_limit".to_string(),
            window_key: "5h".to_string(),
            label: "5 hours".to_string(),
            limit_window_seconds: 18_000,
            used_percent: 42.5,
            used_basis_points: 4250,
            remaining_basis_points: 5750,
            limited: false,
            reset_at_ms: NOW as u64 + 1000,
            updated_at_ms: NOW as u64,
        }];
        let store = store_with_accounts("openai", "fill-first", vec![acct]);

        let snapshot = provider_runtime_snapshot(&store, "openai");
        let serialized = serde_json::to_string(&snapshot).expect("snapshot should serialize");

        assert_eq!(snapshot.accounts.len(), 1);
        assert_eq!(snapshot.accounts[0].email, "user@example.test");
        assert_eq!(snapshot.accounts[0].quota.usage_windows.len(), 1);
        assert_eq!(snapshot.accounts[0].quota.usage_windows[0].window_key, "5h");
        assert_eq!(snapshot.accounts[0].api_key_redacted, "sk-s...alue");
        assert!(!serialized.contains("sk-secret-value"));
        assert!(!serialized.contains("refresh_token"));
    }

    #[test]
    fn key_pool_snapshot_does_not_report_ready_as_blocker_reason() {
        let mut acct = account("ready-model-state", "openai", 1, &["gpt-5.4"]);
        acct.model_states.insert(
            "gpt-5.4".to_string(),
            ProviderModelState {
                status: "ready".to_string(),
                ..ProviderModelState::default()
            },
        );
        let store = store_with_accounts("openai", "fill-first", vec![acct]);

        let snapshot = provider_key_pools(&store, "openai", "gpt-5.4", false, NOW);

        assert_eq!(snapshot.pools.len(), 1);
        assert_eq!(snapshot.pools[0].state, "ready");
        assert!(snapshot.pools[0].blocker_reason_codes.is_empty());
    }

    #[test]
    fn openai_quota_apply_blocks_account_and_preserves_store_shape() {
        let dir = unique_temp_dir("xhub-provider-quota-apply");
        std::fs::create_dir_all(&dir).expect("temp dir should be created");
        std::fs::write(
            dir.join(PROVIDER_STORE_FILE_NAME),
            r#"{
              "schema_version": "xhub.provider_keys.v1",
              "updated_at_ms": 1,
              "routing_strategy": "fill-first",
              "custom_top_level": {"preserve": true},
              "providers": {
                "openai": {
                  "routing_strategy": "quota-aware",
                  "accounts": [
                    {
                      "account_key": "acct-quota",
                      "provider": "openai",
                      "api_key": "sk-secret",
                      "auth_type": "oauth",
                      "oauth_source_key": "chatgpt",
                      "account_id": "acct-old",
                      "models": ["gpt-5.4"],
                      "quota": {
                        "daily_token_cap": 1000,
                        "daily_tokens_used": 100,
                        "daily_tokens_remaining": 900,
                        "total_tokens_used": 1234,
                        "next_recover_at_ms": 999999
                      }
                    }
                  ]
                }
              }
            }"#,
        )
        .expect("provider store should be written");

        let result = apply_openai_quota_usage_to_runtime_base_dir(
            &dir,
            json!({
                "plan_type": "pro",
                "rate_limit": {
                    "limit_reached": true,
                    "primary_window": {
                        "used_percent": 100,
                        "limit_window_seconds": 5 * 60 * 60,
                        "reset_at": (NOW as u64 + 120_000) / 1000
                    },
                    "secondary_window": {
                        "used_percent": 65,
                        "limit_window_seconds": 7 * 24 * 60 * 60,
                        "reset_at": 0
                    }
                }
            }),
            OpenAIQuotaApplyOptions {
                account_key: "acct-quota".to_string(),
                refreshed_at_ms: NOW as u64,
                success_interval_ms: 300_000,
                high_water_interval_ms: 60_000,
                account_id: "acct-new".to_string(),
                oauth_source_key: "chatgpt".to_string(),
            },
        )
        .expect("quota apply should succeed");

        assert!(result.ok);
        assert!(result.limited);
        assert_eq!(result.account_key, "acct-quota");
        assert!(result.next_refresh_at_ms >= NOW as u64 + 119_000);

        let raw: Value = serde_json::from_str(
            &std::fs::read_to_string(dir.join(PROVIDER_STORE_FILE_NAME))
                .expect("provider store should be readable"),
        )
        .expect("store json should parse");
        assert_eq!(raw["custom_top_level"]["preserve"], true);
        let account = &raw["providers"]["openai"]["accounts"][0];
        assert_eq!(account["tier"], "pro");
        assert_eq!(account["account_id"], "acct-new");
        assert_eq!(account["quota"]["daily_token_cap"], 10_000);
        assert_eq!(account["quota"]["daily_tokens_used"], 10_000);
        assert_eq!(account["quota"]["daily_tokens_remaining"], 0);
        assert_eq!(account["quota"]["total_tokens_used"], 1234);
        assert_eq!(account["refresh_state"]["status"], "idle");
        assert_eq!(account["refresh_state"]["last_attempt_at_ms"], NOW as u64);
        assert_eq!(account["refresh_state"]["last_success_at_ms"], NOW as u64);
        assert_eq!(account["refresh_state"]["failure_count"], 0);
        assert!(account["quota"].get("next_recover_at_ms").is_none());
        assert_eq!(account["error_state"]["status"], "blocked_quota");
        assert_eq!(account["error_state"]["retry_at_source"], "usage_window");
        assert_eq!(
            account["quota"]["usage_windows"].as_array().unwrap().len(),
            2
        );

        let store = ProviderKeyStore::load_runtime_base_dir(&dir).expect("store should load");
        let snapshot = provider_key_pools(&store, "openai", "gpt-5.4", true, NOW);
        assert_eq!(snapshot.pools[0].state, "cooldown");
        assert_eq!(snapshot.pools[0].members[0].reason_code, "blocked_quota");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn openai_quota_refresh_plan_selects_due_supported_accounts() {
        let dir = unique_temp_dir("xhub-provider-quota-plan");
        std::fs::create_dir_all(&dir).expect("temp dir should be created");
        std::fs::write(
            dir.join(PROVIDER_STORE_FILE_NAME),
            r#"{
              "updated_at_ms": 900,
              "providers": {
                "openai": {
                  "accounts": [
                    {
                      "account_key": "due",
                      "provider": "openai",
                      "api_key": "sk-test",
                      "auth_index": 7,
                      "account_id": "acct-due",
                      "enabled": true,
                      "oauth_source_key": "chatgpt",
                      "quota": {
                        "next_refresh_at_ms": 1000
                      },
                      "refresh_state": {
                        "status": "idle",
                        "failure_count": 2
                      }
                    },
                    {
                      "account_key": "later",
                      "provider": "openai",
                      "api_key": "sk-test",
                      "auth_index": 8,
                      "account_id": "acct-later",
                      "enabled": true,
                      "oauth_source_key": "chatgpt",
                      "quota": {
                        "next_refresh_at_ms": 9999
                      }
                    },
                    {
                      "account_key": "disabled",
                      "provider": "openai",
                      "api_key": "sk-test",
                      "auth_index": 9,
                      "account_id": "acct-disabled",
                      "enabled": false,
                      "oauth_source_key": "chatgpt"
                    },
                    {
                      "account_key": "unsupported",
                      "provider": "openai",
                      "api_key": "sk-test",
                      "enabled": true
                    }
                  ]
                }
              }
            }"#,
        )
        .expect("provider store should be written");

        let result = plan_openai_quota_refresh_from_runtime_base_dir(
            &dir,
            OpenAIQuotaRefreshPlanOptions {
                now_ms: 1500,
                include_skipped: true,
                in_flight_account_keys: vec!["missing".to_string()],
            },
        )
        .expect("plan should load");

        assert_eq!(result.ok, true);
        assert_eq!(result.total_accounts, 4);
        assert_eq!(result.eligible_accounts, 3);
        assert_eq!(result.due_accounts, 1);
        assert_eq!(result.skipped_count, 2);
        assert_eq!(result.accounts[0].account_key, "due");
        assert_eq!(result.accounts[0].account_id, "acct-due");
        assert_eq!(result.accounts[0].failure_count, 2);
        assert!(result
            .skipped_accounts
            .iter()
            .any(|item| item.account_key == "later" && item.reason_code == "not_due"));
        assert!(result
            .skipped_accounts
            .iter()
            .any(|item| item.account_key == "disabled" && item.reason_code == "disabled"));
        assert!(result
            .skipped_accounts
            .iter()
            .any(|item| item.account_key == "unsupported"
                && item.reason_code == "unsupported_quota_metadata"));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn codex_oauth_refresh_plan_selects_due_accounts_without_secrets() {
        let mut expired = account("expired", "openai", 2, &["gpt-5.4"]);
        expired.auth_type = "oauth".to_string();
        expired.oauth_source_key = "chatgpt".to_string();
        expired.api_key = "old-access-expired".to_string();
        expired.refresh_token = "refresh-expired-secret".to_string();
        expired.expires_at_ms = NOW as u64 - 1;
        expired.last_refresh_at_ms = 1;

        let mut retry = account("retry", "openai", 1, &["gpt-5.4"]);
        retry.auth_type = "oauth".to_string();
        retry.oauth_source_key = "chatgpt".to_string();
        retry.api_key = "old-access-retry".to_string();
        retry.refresh_token = "refresh-retry-secret".to_string();
        retry.expires_at_ms = NOW as u64 + 3_600_000;
        retry.refresh_state.status = "failed".to_string();
        retry.refresh_state.last_error_code = "refresh_timeout".to_string();
        retry.refresh_state.next_refresh_at_ms = NOW as u64 - 10;
        retry.refresh_state.failure_count = 1;

        let mut fresh = account("fresh", "openai", 3, &["gpt-5.4"]);
        fresh.auth_type = "oauth".to_string();
        fresh.oauth_source_key = "chatgpt".to_string();
        fresh.api_key = "old-access-fresh".to_string();
        fresh.refresh_token = "refresh-fresh-secret".to_string();
        fresh.last_refresh_at_ms = NOW as u64;
        fresh.refresh_state.last_success_at_ms = NOW as u64;
        fresh.expires_at_ms = NOW as u64 + 3_600_000;

        let mut terminal = account("terminal", "openai", 4, &["gpt-5.4"]);
        terminal.auth_type = "oauth".to_string();
        terminal.oauth_source_key = "chatgpt".to_string();
        terminal.api_key = "old-access-terminal".to_string();
        terminal.refresh_token = "refresh-terminal-secret".to_string();
        terminal.refresh_state.status = "failed".to_string();
        terminal.refresh_state.last_error_code = "invalid_grant".to_string();

        let store = store_with_accounts(
            "openai",
            "fill-first",
            vec![fresh, expired, retry, terminal],
        );

        let result = plan_codex_oauth_refresh(
            &store,
            ProviderOAuthRefreshPlanOptions {
                now_ms: NOW as u64,
                include_skipped: true,
                in_flight_account_keys: Vec::new(),
                refresh_lead_ms: 5 * 24 * 60 * 60 * 1000,
                min_refresh_lead_ms: 5 * 60 * 1000,
            },
        );
        let serialized = serde_json::to_string(&result).expect("plan should serialize");

        assert_eq!(result.ok, true);
        assert_eq!(result.total_accounts, 4);
        assert_eq!(result.eligible_accounts, 4);
        assert_eq!(result.due_accounts, 2);
        assert_eq!(result.accounts[0].account_key, "expired");
        assert_eq!(result.accounts[0].reason_code, "token_expired");
        assert_eq!(result.accounts[1].account_key, "retry");
        assert_eq!(result.accounts[1].reason_code, "retry_due");
        assert!(result
            .skipped_accounts
            .iter()
            .any(|item| item.account_key == "fresh" && item.reason_code == "not_due"));
        assert!(result
            .skipped_accounts
            .iter()
            .any(|item| item.account_key == "terminal"
                && item.reason_code == "terminal_refresh_failed"));
        assert!(!serialized.contains("old-access"));
        assert!(!serialized.contains("refresh-"));
    }

    #[test]
    fn openai_quota_failure_records_idle_backoff_without_blocking_route() {
        let dir = unique_temp_dir("xhub-provider-quota-failure");
        std::fs::create_dir_all(&dir).expect("temp dir should be created");
        std::fs::write(
            dir.join(PROVIDER_STORE_FILE_NAME),
            r#"{
              "providers": {
                "openai": {
                  "accounts": [
                    {
                      "account_key": "quota-fail",
                      "provider": "openai",
                      "api_key": "sk-test",
                      "auth_index": 7,
                      "account_id": "acct-fail",
                      "enabled": true,
                      "oauth_source_key": "chatgpt",
                      "models": ["gpt-5.4"],
                      "refresh_state": {
                        "status": "idle",
                        "failure_count": 1,
                        "last_success_at_ms": 500
                      }
                    }
                  ]
                }
              }
            }"#,
        )
        .expect("provider store should be written");

        let result = record_openai_quota_refresh_failure_to_runtime_base_dir(
            &dir,
            OpenAIQuotaRefreshFailureOptions {
                account_key: "quota-fail".to_string(),
                failed_at_ms: 1_000,
                base_failure_backoff_ms: 100,
                max_failure_backoff_ms: 1_000,
                error_code: "ETIMEDOUT".to_string(),
                error_message: "timeout".to_string(),
            },
        )
        .expect("failure should record");

        assert_eq!(result.failure_count, 2);
        assert_eq!(result.next_refresh_at_ms, 1_200);

        let store = ProviderKeyStore::load_runtime_base_dir(&dir).expect("store should load");
        let account = &store.providers["openai"].accounts[0];
        assert_eq!(account.refresh_state.status, "idle");
        assert_eq!(account.refresh_state.last_error_code, "ETIMEDOUT");
        assert_eq!(account.refresh_state.next_refresh_at_ms, 0);
        assert_eq!(account.quota.next_refresh_at_ms, 1_200);

        let decision = route_from_runtime_base_dir(
            &dir,
            ProviderRouteRequest {
                model_id: "gpt-5.4".to_string(),
                provider: "openai".to_string(),
                now_ms: 1_100,
            },
        )
        .expect("route should load");
        assert_eq!(decision.available_count, 1);
        assert_eq!(decision.selected_account_key, "quota-fail");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn openai_quota_apply_clears_previous_quota_blocker_when_usage_recovers() {
        let dir = unique_temp_dir("xhub-provider-quota-recover");
        std::fs::create_dir_all(&dir).expect("temp dir should be created");
        std::fs::write(
            dir.join(PROVIDER_STORE_FILE_NAME),
            r#"{
              "providers": {
                "openai": {
                  "accounts": [
                    {
                      "account_key": "acct-recover",
                      "provider": "openai",
                      "api_key": "sk-secret",
                      "models": ["gpt-5.4"],
                      "quota": {
                        "daily_token_cap": 10000,
                        "daily_tokens_used": 10000,
                        "daily_tokens_remaining": 0,
                        "cooldown_until_ms": 1200000
                      },
                      "error_state": {
                        "status": "blocked_quota",
                        "reason_code": "blocked_quota",
                        "last_error_code": "blocked_quota",
                        "next_retry_at_ms": 1200000,
                        "retry_at_source": "usage_window"
                      }
                    }
                  ]
                }
              }
            }"#,
        )
        .expect("provider store should be written");

        apply_openai_quota_usage_to_runtime_base_dir(
            &dir,
            json!({
                "plan_type": "plus",
                "rate_limit": {
                    "limit_reached": false,
                    "primary_window": {
                        "used_percent": 22.5,
                        "limit_window_seconds": 5 * 60 * 60,
                        "reset_at": 0
                    }
                }
            }),
            OpenAIQuotaApplyOptions {
                account_key: "acct-recover".to_string(),
                refreshed_at_ms: NOW as u64,
                success_interval_ms: 300_000,
                high_water_interval_ms: 60_000,
                account_id: String::new(),
                oauth_source_key: String::new(),
            },
        )
        .expect("quota apply should succeed");

        let store = ProviderKeyStore::load_runtime_base_dir(&dir).expect("store should load");
        let account = &store.providers["openai"].accounts[0];
        assert_eq!(account.tier, "plus");
        assert_eq!(account.quota.daily_tokens_used, 2250);
        assert_eq!(account.quota.daily_tokens_remaining, 7750);
        assert_eq!(account.quota.cooldown_until_ms, 0);
        assert_eq!(account.error_state.status, "healthy");
        assert_eq!(account.error_state.reason_code, "");
        assert_eq!(account.error_state.next_retry_at_ms, 0);
        let snapshot = provider_key_pools(&store, "openai", "gpt-5.4", true, NOW);
        assert_eq!(snapshot.pools[0].state, "ready");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn oauth_refresh_apply_clears_expired_auth_blocker_without_exposing_secrets() {
        let dir = unique_temp_dir("xhub-provider-oauth-refresh-apply");
        std::fs::create_dir_all(&dir).expect("temp dir should be created");
        std::fs::write(
            dir.join(PROVIDER_STORE_FILE_NAME),
            r#"{
              "schema_version": "xhub.provider_keys.v1",
              "updated_at_ms": 1,
              "providers": {
                "openai": {
                  "accounts": [
                    {
                      "account_key": "oauth-apply",
                      "provider": "openai",
                      "api_key": "old-access-secret",
                      "refresh_token": "old-refresh-secret",
                      "auth_type": "oauth",
                      "expires_at_ms": 1,
                      "models": ["gpt-5.4"],
                      "error_state": {
                        "status": "blocked_auth",
                        "status_message": "token_expired",
                        "reason_code": "token_expired",
                        "last_error_code": "token_expired",
                        "last_error_at_ms": 100,
                        "next_retry_at_ms": 200,
                        "retry_at_source": "refresh",
                        "auto_disabled": false
                      },
                      "refresh_state": {
                        "status": "failed",
                        "last_attempt_at_ms": 100,
                        "last_success_at_ms": 0,
                        "next_refresh_at_ms": 200,
                        "failure_count": 2,
                        "last_error_code": "token_expired",
                        "last_error_message": "token_expired"
                      }
                    }
                  ]
                }
              }
            }"#,
        )
        .expect("provider store should be written");

        let result = apply_provider_oauth_refresh_to_runtime_base_dir(
            &dir,
            ProviderOAuthRefreshApplyOptions {
                account_key: "oauth-apply".to_string(),
                refreshed_at_ms: NOW as u64,
                access_token: "new-access-secret".to_string(),
                refresh_token: String::new(),
                expires_at_ms: NOW as u64 + 600_000,
                account_id: "acct-new".to_string(),
                email: "new@example.test".to_string(),
                oauth_source_key: "chatgpt".to_string(),
            },
        )
        .expect("oauth refresh apply should succeed");

        assert!(result.ok);
        assert_eq!(result.expires_at_ms, NOW as u64 + 600_000);
        let result_json = serde_json::to_string(&result).expect("result should serialize");
        assert!(!result_json.contains("new-access-secret"));
        assert!(!result_json.contains("old-refresh-secret"));

        let raw: Value = serde_json::from_str(
            &std::fs::read_to_string(dir.join(PROVIDER_STORE_FILE_NAME))
                .expect("provider store should be readable"),
        )
        .expect("store json should parse");
        let account = &raw["providers"]["openai"]["accounts"][0];
        assert_eq!(account["api_key"], "new-access-secret");
        assert_eq!(account["refresh_token"], "old-refresh-secret");
        assert_eq!(account["account_id"], "acct-new");
        assert_eq!(account["email"], "new@example.test");
        assert_eq!(account["refresh_state"]["status"], "idle");
        assert_eq!(account["refresh_state"]["failure_count"], 0);
        assert_eq!(account["error_state"]["status"], "healthy");
        assert_eq!(account["error_state"]["reason_code"], "");
        assert_eq!(account["error_state"]["retry_at_source"], "");

        let store = ProviderKeyStore::load_runtime_base_dir(&dir).expect("store should load");
        let snapshot = provider_key_pools(&store, "openai", "gpt-5.4", true, NOW);
        assert_eq!(snapshot.pools[0].state, "ready");
        let runtime_snapshot = provider_runtime_snapshot_from_runtime_base_dir(&dir, "openai")
            .expect("snapshot should load");
        let snapshot_json =
            serde_json::to_string(&runtime_snapshot).expect("snapshot should serialize");
        assert!(!snapshot_json.contains("new-access-secret"));
        assert!(!snapshot_json.contains("old-refresh-secret"));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn oauth_refresh_terminal_failure_blocks_auth_without_retry() {
        let dir = unique_temp_dir("xhub-provider-oauth-refresh-terminal-failure");
        std::fs::create_dir_all(&dir).expect("temp dir should be created");
        std::fs::write(
            dir.join(PROVIDER_STORE_FILE_NAME),
            r#"{
              "providers": {
                "openai": {
                  "accounts": [
                    {
                      "account_key": "oauth-terminal",
                      "provider": "openai",
                      "api_key": "old-access-secret",
                      "refresh_token": "old-refresh-secret",
                      "auth_type": "oauth",
                      "expires_at_ms": 999999999,
                      "models": ["gpt-5.4"],
                      "refresh_state": {
                        "status": "idle",
                        "failure_count": 1,
                        "last_success_at_ms": 500
                      }
                    }
                  ]
                }
              }
            }"#,
        )
        .expect("provider store should be written");

        let result = record_provider_oauth_refresh_failure_to_runtime_base_dir(
            &dir,
            ProviderOAuthRefreshFailureOptions {
                account_key: "oauth-terminal".to_string(),
                failed_at_ms: 1_000,
                base_failure_backoff_ms: 100,
                max_failure_backoff_ms: 1_000,
                terminal: false,
                error_code: "refresh_token_reused".to_string(),
                error_message: "refresh_token_reused".to_string(),
            },
        )
        .expect("oauth refresh failure should record");

        assert!(!result.ok);
        assert_eq!(result.error_code, "refresh_token_reused");
        assert_eq!(result.error_message, "refresh_token_reused");
        assert_eq!(result.next_refresh_at_ms, 0);
        let result_json = serde_json::to_string(&result).expect("result should serialize");
        assert!(!result_json.contains("old-access-secret"));
        assert!(!result_json.contains("old-refresh-secret"));

        let store = ProviderKeyStore::load_runtime_base_dir(&dir).expect("store should load");
        let account = &store.providers["openai"].accounts[0];
        assert_eq!(account.refresh_state.status, "failed");
        assert_eq!(account.refresh_state.failure_count, 2);
        assert_eq!(account.refresh_state.next_refresh_at_ms, 0);
        assert_eq!(account.error_state.status, "blocked_auth");
        assert_eq!(account.error_state.reason_code, "refresh_token_reused");
        assert_eq!(account.error_state.retry_at_source, "refresh");

        let decision = route_from_runtime_base_dir(
            &dir,
            ProviderRouteRequest {
                model_id: "gpt-5.4".to_string(),
                provider: "openai".to_string(),
                now_ms: 1_100,
            },
        )
        .expect("route should load");
        assert_eq!(decision.selected_account_key, "");
        assert_eq!(decision.fallback_reason_code, "all_keys_auth_blocked");
        assert_eq!(decision.candidates[0].state, "blocked");
        assert_eq!(decision.candidates[0].reason_code, "refresh_token_reused");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn oauth_refresh_retryable_failure_records_backoff_and_sanitizes_message() {
        let dir = unique_temp_dir("xhub-provider-oauth-refresh-retryable-failure");
        std::fs::create_dir_all(&dir).expect("temp dir should be created");
        std::fs::write(
            dir.join(PROVIDER_STORE_FILE_NAME),
            r#"{
              "providers": {
                "openai": {
                  "accounts": [
                    {
                      "account_key": "oauth-retry",
                      "provider": "openai",
                      "api_key": "old-access-secret",
                      "refresh_token": "old-refresh-secret",
                      "auth_type": "oauth",
                      "expires_at_ms": 999999999,
                      "models": ["gpt-5.4"],
                      "refresh_state": {
                        "status": "idle",
                        "failure_count": 0,
                        "last_success_at_ms": 500
                      }
                    }
                  ]
                }
              }
            }"#,
        )
        .expect("provider store should be written");

        let result = record_provider_oauth_refresh_failure_to_runtime_base_dir(
            &dir,
            ProviderOAuthRefreshFailureOptions {
                account_key: "oauth-retry".to_string(),
                failed_at_ms: 1_000,
                base_failure_backoff_ms: 500,
                max_failure_backoff_ms: 10_000,
                terminal: false,
                error_code: "ETIMEDOUT".to_string(),
                error_message: "access_token leaked-value refresh_token leaked-value".to_string(),
            },
        )
        .expect("oauth refresh failure should record");

        assert!(!result.ok);
        assert_eq!(result.error_code, "refresh_timeout");
        assert_eq!(result.error_message, "refresh_timeout");
        assert_eq!(result.next_refresh_at_ms, 1_500);
        let store = ProviderKeyStore::load_runtime_base_dir(&dir).expect("store should load");
        let account = &store.providers["openai"].accounts[0];
        assert_eq!(account.refresh_state.status, "failed");
        assert_eq!(account.refresh_state.next_refresh_at_ms, 1_500);
        assert_eq!(account.error_state.status, "blocked_network");
        assert_eq!(account.error_state.reason_code, "refresh_timeout");
        assert_eq!(account.error_state.status_message, "refresh_timeout");
        assert_eq!(account.error_state.retry_at_source, "refresh");

        let decision = route_from_runtime_base_dir(
            &dir,
            ProviderRouteRequest {
                model_id: "gpt-5.4".to_string(),
                provider: "openai".to_string(),
                now_ms: 1_100,
            },
        )
        .expect("route should load");
        assert_eq!(decision.fallback_reason_code, "all_keys_in_cooldown");
        assert_eq!(decision.candidates[0].state, "cooldown");
        assert_eq!(decision.candidates[0].next_retry_at_ms, 1_500);
        let _ = std::fs::remove_dir_all(&dir);
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
            ..ProviderKeyStore::default()
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

    fn unique_temp_dir(prefix: &str) -> PathBuf {
        std::env::temp_dir().join(format!(
            "{}-{}-{}",
            prefix,
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|duration| duration.as_nanos())
                .unwrap_or(0)
        ))
    }
}
