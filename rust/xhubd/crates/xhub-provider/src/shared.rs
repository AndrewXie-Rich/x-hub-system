use std::fs;
use std::path::Path;

use serde_json::{json, Map, Value};

use super::*;

pub(crate) fn load_provider_store_value_for_write(
    path: &Path,
) -> Result<Value, ProviderRouteError> {
    if !path.is_file() {
        return Err(ProviderRouteError::Invalid(format!(
            "provider store file not found: {}",
            path.display()
        )));
    }
    let raw = fs::read_to_string(path)
        .map_err(|err| ProviderRouteError::Io(format!("{}: {err}", path.display())))?;
    serde_json::from_str(&raw)
        .map_err(|err| ProviderRouteError::Json(format!("{}: {err}", path.display())))
}

pub(crate) fn write_provider_store_value_atomic(
    path: &Path,
    value: &Value,
) -> Result<(), ProviderRouteError> {
    let parent = path.parent().ok_or_else(|| {
        ProviderRouteError::Invalid(format!("provider store has no parent: {}", path.display()))
    })?;
    fs::create_dir_all(parent)
        .map_err(|err| ProviderRouteError::Io(format!("{}: {err}", parent.display())))?;
    let tmp = parent.join(format!(
        ".{}.tmp_{}_{}",
        path.file_name()
            .and_then(|name| name.to_str())
            .unwrap_or(PROVIDER_STORE_FILE_NAME),
        std::process::id(),
        current_process_unique_suffix()
    ));
    let body = serde_json::to_string_pretty(value)
        .map_err(|err| ProviderRouteError::Json(format!("serialize provider store: {err}")))?;
    fs::write(&tmp, format!("{body}\n"))
        .map_err(|err| ProviderRouteError::Io(format!("{}: {err}", tmp.display())))?;
    fs::rename(&tmp, path).map_err(|err| {
        let _ = fs::remove_file(&tmp);
        ProviderRouteError::Io(format!("{} -> {}: {err}", tmp.display(), path.display()))
    })
}

fn current_process_unique_suffix() -> String {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or(0);
    format!("{nanos:x}")
}

pub(crate) fn current_time_millis() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_millis().min(u64::MAX as u128) as u64)
        .unwrap_or(0)
}

pub(crate) fn decode_jwt_payload_value(token: &str) -> Option<Value> {
    let mut segments = token.trim().split('.');
    let _header = segments.next()?;
    let payload = segments.next()?;
    if payload.trim().is_empty() {
        return None;
    }
    let decoded = decode_base64_url(payload)?;
    serde_json::from_slice::<Value>(&decoded)
        .ok()
        .filter(Value::is_object)
}

fn decode_base64_url(input: &str) -> Option<Vec<u8>> {
    let mut out = Vec::with_capacity(input.len().saturating_mul(3) / 4);
    let mut buffer = 0_u32;
    let mut bits = 0_u8;
    for byte in input.bytes() {
        let value = match byte {
            b'A'..=b'Z' => u32::from(byte - b'A'),
            b'a'..=b'z' => u32::from(byte - b'a') + 26,
            b'0'..=b'9' => u32::from(byte - b'0') + 52,
            b'+' | b'-' => 62,
            b'/' | b'_' => 63,
            b'=' => break,
            b'\r' | b'\n' | b'\t' | b' ' => continue,
            _ => return None,
        };
        buffer = (buffer << 6) | value;
        bits = bits.saturating_add(6);
        if bits >= 8 {
            bits -= 8;
            out.push(((buffer >> bits) & 0xff) as u8);
            if bits > 0 {
                buffer &= (1 << bits) - 1;
            } else {
                buffer = 0;
            }
        }
    }
    Some(out)
}

pub(crate) fn set_json_u64_object(value: &mut Value, key: &str, number: u64) {
    if !value.is_object() {
        *value = Value::Object(Map::new());
    }
    if let Some(object) = value.as_object_mut() {
        object.insert(key.to_string(), json!(number));
    }
}

pub(crate) fn json_string(value: &Value, key: &str) -> String {
    value
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim()
        .to_string()
}

pub(crate) fn non_empty_json_string(value: &Value, key: &str) -> Option<String> {
    let raw = json_string(value, key);
    if raw.is_empty() {
        None
    } else {
        Some(raw)
    }
}

pub(crate) fn json_bool(value: &Value, key: &str) -> bool {
    value.get(key).and_then(Value::as_bool).unwrap_or(false)
}

pub(crate) fn json_u64(value: &Value, key: &str) -> u64 {
    value
        .get(key)
        .and_then(|item| {
            item.as_u64().or_else(|| {
                item.as_i64()
                    .and_then(|number| u64::try_from(number.max(0)).ok())
            })
        })
        .or_else(|| {
            value
                .get(key)
                .and_then(Value::as_str)
                .and_then(|raw| raw.trim().parse::<u64>().ok())
        })
        .unwrap_or(0)
}

pub(crate) fn json_f64(value: &Value, key: &str) -> f64 {
    value
        .get(key)
        .and_then(|item| {
            item.as_f64()
                .or_else(|| item.as_str()?.trim().parse::<f64>().ok())
        })
        .unwrap_or(0.0)
}

pub(crate) fn valid_routing_strategy(raw: &str) -> String {
    match normalized_token(raw).as_str() {
        "round-robin" => "round-robin".to_string(),
        "priority" => "priority".to_string(),
        "quota-aware" => "quota-aware".to_string(),
        _ => default_routing_strategy(),
    }
}

pub(crate) fn normalize_wire_api(raw: &str) -> String {
    match normalized_token(raw).as_str() {
        "responses" | "response" | "responses_api" => "responses".to_string(),
        "chat" | "chatcompletions" | "chat_completions" | "chat-completions"
        | "chat/completions" => "chat_completions".to_string(),
        _ => String::new(),
    }
}

pub(crate) fn first_non_empty(values: &[&str]) -> Option<String> {
    for value in values {
        let trimmed = trim_string(value);
        if !trimmed.is_empty() {
            return Some(trimmed);
        }
    }
    None
}

pub(crate) fn normalized_token(raw: &str) -> String {
    raw.trim().to_lowercase()
}

pub(crate) fn trim_string(raw: &str) -> String {
    raw.trim().to_string()
}
