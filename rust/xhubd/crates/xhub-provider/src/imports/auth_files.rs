use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};

use serde_json::{json, Map, Value};

use super::*;

pub(super) fn collect_auth_json_files(
    root_dir: &Path,
    matcher: Option<fn(&Path) -> bool>,
) -> Vec<PathBuf> {
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

pub(super) fn build_imported_auth_accounts(
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
