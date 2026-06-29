use super::*;

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

    let result = import_auth_dir_to_runtime_base_dir(&dir, &auth_dir.to_string_lossy(), NOW as u64)
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

    let result =
        import_proxy_config_to_runtime_base_dir(&dir, &config_path.to_string_lossy(), NOW as u64)
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
