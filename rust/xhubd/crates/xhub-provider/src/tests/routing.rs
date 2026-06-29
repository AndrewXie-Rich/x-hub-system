use super::*;

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
        candidate.account_key == "exhausted" && candidate.reason_code == "daily_token_cap_exceeded"
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
