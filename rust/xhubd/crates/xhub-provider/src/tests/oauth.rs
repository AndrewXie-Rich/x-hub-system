use super::*;

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
    assert!(result.skipped_accounts.iter().any(
        |item| item.account_key == "terminal" && item.reason_code == "terminal_refresh_failed"
    ));
    assert!(!serialized.contains("old-access"));
    assert!(!serialized.contains("refresh-"));
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
