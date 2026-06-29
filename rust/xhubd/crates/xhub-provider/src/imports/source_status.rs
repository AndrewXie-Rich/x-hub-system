use serde_json::{json, Value};

use super::*;

pub(super) fn record_import_source_status_in_store(
    store_value: &mut Value,
    kind: &str,
    source_ref: &str,
    state: &str,
    imported: u32,
    errors: &[String],
    now_ms: u64,
) {
    ensure_provider_store_shape(store_value);
    let source_key = import_source_key(kind, source_ref);
    if source_key.is_empty() {
        return;
    }
    let import_sources = store_value
        .get_mut("import_sources")
        .and_then(Value::as_array_mut)
        .expect("import_sources is array");
    if !import_sources
        .iter()
        .any(|value| value.as_str() == Some(source_key.as_str()))
    {
        import_sources.push(Value::String(source_key.clone()));
        import_sources.sort_by(|lhs, rhs| lhs.as_str().cmp(&rhs.as_str()));
    }
    let owned_count = count_owned_accounts_for_source(store_value, &source_key);
    let status = json!({
        "kind": kind,
        "source_ref": source_ref,
        "state": if state == "ready" { "ready" } else { "sync_failed" },
        "last_sync_at_ms": now_ms,
        "last_imported_count": imported,
        "owned_account_count": owned_count,
        "last_error_count": errors.len() as u32,
        "last_errors": errors.iter().take(4).cloned().collect::<Vec<String>>(),
        "updated_at_ms": now_ms,
    });
    if let Some(statuses) = store_value
        .get_mut("import_source_statuses")
        .and_then(Value::as_object_mut)
    {
        statuses.insert(source_key, status);
    }
}

fn count_owned_accounts_for_source(store_value: &Value, owner_key: &str) -> u32 {
    let mut count = 0_u32;
    let Some(providers) = store_value.get("providers").and_then(Value::as_object) else {
        return 0;
    };
    for provider_value in providers.values() {
        let Some(accounts) = provider_value.get("accounts").and_then(Value::as_array) else {
            continue;
        };
        for account in accounts {
            if string_array_value(account.get("source_owners"))
                .iter()
                .any(|owner| owner == owner_key)
            {
                count = count.saturating_add(1);
            }
        }
    }
    count
}

pub(super) fn import_source_key(kind: &str, source_ref: &str) -> String {
    let kind = normalized_token(kind);
    let source_ref = trim_string(source_ref);
    if kind.is_empty() || source_ref.is_empty() {
        String::new()
    } else {
        format!("{kind}:{source_ref}")
    }
}
