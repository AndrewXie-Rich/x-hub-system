use super::*;

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
