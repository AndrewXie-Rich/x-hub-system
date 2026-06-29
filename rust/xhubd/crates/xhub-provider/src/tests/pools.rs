use super::*;

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
