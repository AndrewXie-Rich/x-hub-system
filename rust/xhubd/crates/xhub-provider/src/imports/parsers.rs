use std::fs;
use std::path::{Path, PathBuf};

use serde_json::{json, Value};

use super::*;

pub(super) fn normalize_path_ref(path: &Path) -> String {
    let raw = path.to_string_lossy().trim().to_string();
    if raw.is_empty() {
        return String::new();
    }
    fs::canonicalize(path)
        .unwrap_or_else(|_| {
            if path.is_absolute() {
                path.to_path_buf()
            } else {
                std::env::current_dir()
                    .unwrap_or_else(|_| PathBuf::from("."))
                    .join(path)
            }
        })
        .to_string_lossy()
        .trim()
        .to_string()
}

pub(super) fn json_u64_any(value: &Value, keys: &[&str]) -> u64 {
    keys.iter()
        .map(|key| json_u64(value, key))
        .find(|value| *value > 0)
        .unwrap_or(0)
}

pub(super) fn string_array_value(value: Option<&Value>) -> Vec<String> {
    value
        .and_then(Value::as_array)
        .map(|items| {
            let mut out: Vec<String> = items
                .iter()
                .filter_map(Value::as_str)
                .map(trim_string)
                .filter(|item| !item.is_empty())
                .collect();
            out.sort();
            out.dedup();
            out
        })
        .unwrap_or_default()
}

pub(super) fn string_list_from_value(value: &Value) -> Vec<String> {
    if let Some(items) = value.as_array() {
        let mut out: Vec<String> = items
            .iter()
            .filter_map(Value::as_str)
            .map(trim_string)
            .filter(|item| !item.is_empty())
            .collect();
        out.sort();
        out.dedup();
        return out;
    }
    json_string(&json!({"value": value}), "value")
        .split(|ch: char| ch == ',' || ch.is_whitespace())
        .map(trim_string)
        .filter(|item| !item.is_empty())
        .collect()
}

pub(super) fn date_like_to_ms(value: &Value) -> u64 {
    let parsed = value
        .as_u64()
        .or_else(|| {
            value
                .as_i64()
                .and_then(|number| u64::try_from(number.max(0)).ok())
        })
        .or_else(|| {
            value
                .as_str()
                .and_then(|raw| raw.trim().parse::<u64>().ok())
        })
        .unwrap_or(0);
    if parsed > 0 && parsed < 1_000_000_000_000 {
        parsed.saturating_mul(1000)
    } else {
        parsed
    }
}

pub(super) fn path_has_segment(path: &Path, segment: &str) -> bool {
    path.components().any(|component| {
        component
            .as_os_str()
            .to_string_lossy()
            .eq_ignore_ascii_case(segment)
    })
}

pub(super) fn host_from_url(raw: &str) -> String {
    let value = trim_string(raw);
    if value.is_empty() {
        return String::new();
    }
    let without_scheme = value
        .split_once("://")
        .map(|(_, rest)| rest)
        .unwrap_or(value.as_str());
    let authority = without_scheme.split('/').next().unwrap_or_default();
    let host_port = authority.rsplit('@').next().unwrap_or(authority);
    host_port
        .split(':')
        .next()
        .unwrap_or_default()
        .trim()
        .to_ascii_lowercase()
}

pub(super) fn stable_short_fingerprint(material: &str) -> String {
    let mut hash = 0xcbf29ce484222325_u64;
    for byte in material.as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    format!("{hash:016x}")
}

pub(super) fn fallback_if_empty(value: String, fallback: &str) -> String {
    if value.trim().is_empty() {
        fallback.to_string()
    } else {
        value
    }
}

pub(super) fn default_quota_value() -> Value {
    json!({
        "daily_token_cap": 0,
        "daily_tokens_used": 0,
        "daily_tokens_remaining": 0,
        "total_tokens_used": 0,
        "last_used_at_ms": 0,
        "last_error_at_ms": 0,
        "consecutive_errors": 0,
        "cooldown_until_ms": 0,
        "next_refresh_at_ms": 0,
        "usage_windows": [],
    })
}

pub(super) fn default_error_state_value() -> Value {
    json!({
        "status": "healthy",
        "status_message": "",
        "reason_code": "",
        "last_error_code": "",
        "last_error_at_ms": 0,
        "next_retry_at_ms": 0,
        "retry_at_source": "",
        "auto_disabled": false,
    })
}

pub(super) fn default_refresh_state_value() -> Value {
    json!({
        "status": "idle",
        "last_attempt_at_ms": 0,
        "last_success_at_ms": 0,
        "next_refresh_at_ms": 0,
        "failure_count": 0,
        "last_error_code": "",
        "last_error_message": "",
    })
}
