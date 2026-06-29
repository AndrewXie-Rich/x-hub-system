use super::*;

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
