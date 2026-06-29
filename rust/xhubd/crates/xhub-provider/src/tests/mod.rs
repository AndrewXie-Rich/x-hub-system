use super::*;
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::path::PathBuf;

const NOW: u128 = 1_000_000;

mod imports;
mod inventory;
mod oauth;
mod pools;
mod quota;
mod routing;

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

fn account(account_key: &str, provider: &str, priority: u32, models: &[&str]) -> ProviderAccount {
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
