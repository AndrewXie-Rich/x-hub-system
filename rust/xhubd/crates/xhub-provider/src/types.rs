use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

use serde::de::DeserializeOwned;
use serde::{Deserialize, Deserializer, Serialize};

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

pub(crate) fn default_routing_strategy() -> String {
    "fill-first".to_string()
}

fn default_enabled() -> bool {
    true
}

pub(crate) fn default_auth_type() -> String {
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
