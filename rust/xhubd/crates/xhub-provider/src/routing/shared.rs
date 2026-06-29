use std::collections::{BTreeMap, BTreeSet};

use super::*;

#[derive(Debug, Clone)]
pub(super) struct AccountView<'a> {
    pub(super) account: &'a ProviderAccount,
    pub(super) provider_group: String,
}

#[derive(Debug, Clone)]
pub(super) struct Availability {
    pub(super) state: String,
    pub(super) reason_code: String,
    pub(super) retry_at_ms: u64,
}

#[derive(Debug, Clone)]
pub(super) struct PoolState {
    pub(super) state: String,
    pub(super) reason_code: String,
    pub(super) status_message: String,
    pub(super) retry_at_ms: u64,
}

#[derive(Debug, Clone)]
pub(super) struct MutablePoolSnapshot {
    pub(super) pool_id: String,
    pub(super) capability_pool_id: String,
    pub(super) provider: String,
    pub(super) provider_host: String,
    pub(super) wire_api: String,
    pub(super) model_id: String,
    pub(super) model_family: String,
    pub(super) total_accounts: u32,
    pub(super) enabled_accounts: u32,
    pub(super) ready_accounts: u32,
    pub(super) cooldown_accounts: u32,
    pub(super) blocked_accounts: u32,
    pub(super) expired_accounts: u32,
    pub(super) disabled_accounts: u32,
    pub(super) stale_accounts: u32,
    pub(super) auth_failed_accounts: u32,
    pub(super) free_accounts: u32,
    pub(super) paid_accounts: u32,
    pub(super) unknown_tier_accounts: u32,
    pub(super) removable_accounts: u32,
    pub(super) known_quota_accounts: u32,
    pub(super) daily_token_cap: u64,
    pub(super) daily_tokens_used: u64,
    pub(super) daily_tokens_remaining: u64,
    pub(super) total_tokens_used: u64,
    pub(super) next_retry_at_ms: u64,
    pub(super) last_used_at_ms: u64,
    pub(super) last_refresh_at_ms: u64,
    pub(super) reason_counts: BTreeMap<String, u32>,
    pub(super) source_providers: BTreeSet<String>,
    pub(super) members: Vec<ProviderKeyPoolMemberSnapshot>,
}

#[derive(Debug, Clone)]
pub(super) struct ModelStateMatch<'a> {
    pub(super) key: String,
    pub(super) state: &'a ProviderModelState,
}
