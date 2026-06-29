use serde_json::Value;
use xhub_core::json_escape;

pub(crate) fn parse_optional_json_body(body: &str) -> Result<Value, String> {
    if body.trim().is_empty() {
        Ok(Value::Object(Default::default()))
    } else {
        serde_json::from_str::<Value>(body).map_err(|err| err.to_string())
    }
}

pub(crate) fn body_or_query_string(
    value: &Value,
    query: &str,
    key: &str,
    alias: &str,
) -> Option<String> {
    body_string(value, key)
        .or_else(|| body_string(value, alias))
        .or_else(|| query_param(query, key))
        .or_else(|| query_param(query, alias))
}

pub(crate) fn merge_skills_preflight_query(body: &mut Value, query: &str) {
    let Some(map) = body.as_object_mut() else {
        return;
    };
    for (query_key, body_key) in [
        ("skills_dir", "skills_dir"),
        ("skillsDir", "skillsDir"),
        ("request_id", "request_id"),
        ("requestId", "requestId"),
        ("audit_ref", "audit_ref"),
        ("auditRef", "auditRef"),
        ("scope_key", "scope_key"),
        ("scopeKey", "scopeKey"),
        ("skill_id", "skill_id"),
        ("skillId", "skillId"),
        ("requested_capabilities", "requested_capabilities"),
        ("requestedCapabilities", "requestedCapabilities"),
        ("pinned_skill_ids", "pinned_skill_ids"),
        ("pinnedSkillIds", "pinnedSkillIds"),
        ("granted_capabilities", "granted_capabilities"),
        ("grantedCapabilities", "grantedCapabilities"),
    ] {
        if !map.contains_key(body_key) {
            if let Some(value) = query_param(query, query_key) {
                map.insert(body_key.to_string(), Value::String(value));
            }
        }
    }
}

pub(crate) fn body_string(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string)
}

pub(crate) fn body_string_list(value: &Value, key: &str) -> Vec<String> {
    match value.get(key) {
        Some(Value::Array(items)) => items
            .iter()
            .filter_map(Value::as_str)
            .flat_map(split_string_list)
            .collect(),
        Some(Value::String(raw)) => split_string_list(raw),
        _ => Vec::new(),
    }
}

pub(crate) fn body_string_alias(value: &Value, key: &str, alias: &str) -> Option<String> {
    body_string(value, key).or_else(|| body_string(value, alias))
}

pub(crate) fn body_bool_alias(value: &Value, key: &str, alias: &str) -> Option<bool> {
    body_bool(value, key).or_else(|| body_bool(value, alias))
}

pub(crate) fn body_bool(value: &Value, key: &str) -> Option<bool> {
    value.get(key).and_then(|item| {
        item.as_bool().or_else(|| {
            let normalized = item.as_str()?.trim().to_ascii_lowercase();
            match normalized.as_str() {
                "1" | "true" | "yes" | "y" | "on" => Some(true),
                "0" | "false" | "no" | "n" | "off" => Some(false),
                _ => None,
            }
        })
    })
}

pub(crate) fn body_i32(value: &Value, key: &str) -> Option<i32> {
    value.get(key).and_then(|item| {
        item.as_i64()
            .and_then(|number| i32::try_from(number).ok())
            .or_else(|| item.as_str().and_then(|raw| raw.trim().parse::<i32>().ok()))
    })
}

pub(crate) fn body_i64_alias(value: &Value, key: &str, alias: &str) -> Option<i64> {
    body_i64(value, key).or_else(|| body_i64(value, alias))
}

pub(crate) fn body_i64(value: &Value, key: &str) -> Option<i64> {
    value.get(key).and_then(|item| {
        item.as_i64()
            .or_else(|| item.as_str().and_then(|raw| raw.trim().parse::<i64>().ok()))
    })
}

pub(crate) fn body_u64_alias(value: &Value, key: &str, alias: &str) -> Option<u64> {
    body_u64(value, key).or_else(|| body_u64(value, alias))
}

pub(crate) fn body_u64(value: &Value, key: &str) -> Option<u64> {
    value.get(key).and_then(|item| {
        item.as_u64()
            .or_else(|| item.as_str().and_then(|raw| raw.trim().parse::<u64>().ok()))
    })
}

pub(crate) fn body_u128(value: &Value, key: &str) -> Option<u128> {
    value.get(key).and_then(Value::as_u64).map(u128::from)
}

pub(crate) fn push_required_flag(
    args: &mut Vec<String>,
    name: &str,
    value: Option<String>,
) -> Result<(), String> {
    let value = value
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| format!("missing required field for --{name}"))?;
    push_value_flag(args, name, value);
    Ok(())
}

pub(crate) fn push_optional_flag(args: &mut Vec<String>, name: &str, value: Option<String>) {
    if let Some(value) = value.filter(|value| !value.trim().is_empty()) {
        push_value_flag(args, name, value);
    }
}

pub(crate) fn push_optional_i32_flag(args: &mut Vec<String>, name: &str, value: Option<i32>) {
    if let Some(value) = value {
        push_value_flag(args, name, value.to_string());
    }
}

pub(crate) fn push_optional_i64_flag(args: &mut Vec<String>, name: &str, value: Option<i64>) {
    if let Some(value) = value {
        push_value_flag(args, name, value.to_string());
    }
}

pub(crate) fn push_payload_flag(args: &mut Vec<String>, body: &Value) -> Result<(), String> {
    let payload = if let Some(raw) = body_string_alias(body, "payload_json", "payloadJson") {
        raw
    } else if let Some(value) = body.get("payload") {
        serde_json::to_string(value).map_err(|err| format!("invalid payload json: {err}"))?
    } else {
        "{}".to_string()
    };
    push_value_flag(args, "payload-json", payload);
    Ok(())
}

pub(crate) fn push_value_flag(args: &mut Vec<String>, name: &str, value: String) {
    args.push(format!("--{name}"));
    args.push(value);
}

pub(crate) fn first_non_empty(values: &[&str]) -> String {
    values
        .iter()
        .map(|value| value.trim())
        .find(|value| !value.is_empty())
        .unwrap_or("")
        .to_string()
}

pub(crate) fn first_non_empty_string(values: Vec<Option<String>>) -> Option<String> {
    values
        .into_iter()
        .flatten()
        .map(|value| value.trim().to_string())
        .find(|value| !value.is_empty())
}

pub(crate) fn first_non_empty_string_list(values: Vec<Vec<String>>) -> Vec<String> {
    values
        .into_iter()
        .find(|items| items.iter().any(|item| !item.trim().is_empty()))
        .unwrap_or_default()
        .into_iter()
        .map(|item| item.trim().to_string())
        .filter(|item| !item.is_empty())
        .collect()
}

pub(crate) fn query_string_list(query: &str, key: &str) -> Vec<String> {
    query_param(query, key)
        .map(|value| split_string_list(&value))
        .unwrap_or_default()
}

pub(crate) fn split_string_list(raw: &str) -> Vec<String> {
    raw.split(',')
        .map(|item| item.trim().to_string())
        .filter(|item| !item.is_empty())
        .collect()
}

pub(crate) fn body_or_query_usize_in_range(
    value: &Value,
    query: &str,
    key: &str,
    alias: &str,
    fallback: usize,
    min: usize,
    max: usize,
) -> usize {
    body_u64_alias(value, key, alias)
        .and_then(|number| usize::try_from(number).ok())
        .or_else(|| {
            body_or_query_string(value, query, key, alias)?
                .trim()
                .parse()
                .ok()
        })
        .unwrap_or(fallback)
        .clamp(min, max)
}

pub(crate) fn body_or_query_i64_in_range(
    value: &Value,
    query: &str,
    key: &str,
    alias: &str,
    fallback: i64,
    min: i64,
    max: i64,
) -> i64 {
    body_i64_alias(value, key, alias)
        .or_else(|| {
            body_or_query_string(value, query, key, alias)?
                .trim()
                .parse()
                .ok()
        })
        .unwrap_or(fallback)
        .clamp(min, max)
}

pub(crate) fn optional_query_i64_alias(
    query: &str,
    key: &str,
    alias: &str,
    fallback: i64,
) -> Result<i64, String> {
    if query_param(query, key).is_some() {
        return optional_query_i64(query, key, fallback);
    }
    optional_query_i64(query, alias, fallback)
}

pub(crate) fn optional_query_usize_alias(
    query: &str,
    key: &str,
    alias: &str,
    fallback: usize,
) -> Result<usize, String> {
    if query_param(query, key).is_some() {
        return optional_query_usize(query, key, fallback);
    }
    optional_query_usize(query, alias, fallback)
}

pub(crate) fn optional_query_u64_alias(
    query: &str,
    key: &str,
    alias: &str,
    fallback: u64,
) -> Result<u64, String> {
    if query_param(query, key).is_some() {
        return optional_query_u64(query, key, fallback);
    }
    optional_query_u64(query, alias, fallback)
}

pub(crate) fn optional_query_u128_alias(
    query: &str,
    key: &str,
    alias: &str,
) -> Result<Option<u128>, String> {
    if query_param(query, key).is_some() {
        return optional_query_u128(query, key);
    }
    optional_query_u128(query, alias)
}

pub(crate) fn optional_query_bool_alias(
    query: &str,
    key: &str,
    alias: &str,
    fallback: bool,
) -> Result<bool, String> {
    if query_param(query, key).is_some() {
        return optional_query_bool(query, key, fallback);
    }
    optional_query_bool(query, alias, fallback)
}

pub(crate) fn optional_query_u128(query: &str, key: &str) -> Result<Option<u128>, String> {
    match query_param(query, key) {
        Some(value) if !value.trim().is_empty() => {
            value.trim().parse::<u128>().map(Some).map_err(|_| {
                format!(
                    "{{\"ok\":false,\"error\":\"invalid_{}\"}}\n",
                    json_escape(key)
                )
            })
        }
        _ => Ok(None),
    }
}

pub(crate) fn optional_query_usize(
    query: &str,
    key: &str,
    fallback: usize,
) -> Result<usize, String> {
    match query_param(query, key) {
        Some(value) if !value.trim().is_empty() => value.trim().parse::<usize>().map_err(|_| {
            format!(
                "{{\"ok\":false,\"error\":\"invalid_{}\"}}\n",
                json_escape(key)
            )
        }),
        _ => Ok(fallback),
    }
}

pub(crate) fn optional_query_i64(query: &str, key: &str, fallback: i64) -> Result<i64, String> {
    match query_param(query, key) {
        Some(value) if !value.trim().is_empty() => value.trim().parse::<i64>().map_err(|_| {
            format!(
                "{{\"ok\":false,\"error\":\"invalid_{}\"}}\n",
                json_escape(key)
            )
        }),
        _ => Ok(fallback),
    }
}

pub(crate) fn optional_query_u64(query: &str, key: &str, fallback: u64) -> Result<u64, String> {
    match query_param(query, key) {
        Some(value) if !value.trim().is_empty() => value.trim().parse::<u64>().map_err(|_| {
            format!(
                "{{\"ok\":false,\"error\":\"invalid_{}\"}}\n",
                json_escape(key)
            )
        }),
        _ => Ok(fallback),
    }
}

pub(crate) fn optional_query_bool(query: &str, key: &str, fallback: bool) -> Result<bool, String> {
    match query_param(query, key) {
        Some(value) if !value.trim().is_empty() => {
            let normalized = value.trim().to_ascii_lowercase();
            match normalized.as_str() {
                "1" | "true" | "yes" | "y" | "on" => Ok(true),
                "0" | "false" | "no" | "n" | "off" => Ok(false),
                _ => Err(format!(
                    "{{\"ok\":false,\"error\":\"invalid_{}\"}}\n",
                    json_escape(key)
                )),
            }
        }
        Some(_) => Ok(fallback),
        None => Ok(fallback),
    }
}

pub(crate) fn query_param(query: &str, key: &str) -> Option<String> {
    for pair in query.split('&') {
        if pair.is_empty() {
            continue;
        }
        let (raw_key, raw_value) = pair.split_once('=').unwrap_or((pair, ""));
        if percent_decode_query(raw_key).ok()?.as_str() == key {
            return percent_decode_query(raw_value).ok();
        }
    }
    None
}

pub(crate) fn query_param_list(query: &str, key: &str) -> Option<Vec<String>> {
    query_param(query, key).map(|value| {
        value
            .split(',')
            .map(|item| item.trim().to_string())
            .filter(|item| !item.is_empty())
            .collect()
    })
}

pub(crate) fn percent_decode_query(input: &str) -> Result<String, String> {
    let bytes = input.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        match bytes[index] {
            b'+' => {
                out.push(b' ');
                index += 1;
            }
            b'%' => {
                if index + 2 >= bytes.len() {
                    return Err("truncated percent escape".to_string());
                }
                let hi = hex_value(bytes[index + 1])
                    .ok_or_else(|| "invalid percent escape".to_string())?;
                let lo = hex_value(bytes[index + 2])
                    .ok_or_else(|| "invalid percent escape".to_string())?;
                out.push((hi << 4) | lo);
                index += 3;
            }
            value => {
                out.push(value);
                index += 1;
            }
        }
    }
    String::from_utf8(out).map_err(|err| format!("invalid utf8: {err}"))
}

pub(crate) fn hex_value(value: u8) -> Option<u8> {
    match value {
        b'0'..=b'9' => Some(value - b'0'),
        b'a'..=b'f' => Some(value - b'a' + 10),
        b'A'..=b'F' => Some(value - b'A' + 10),
        _ => None,
    }
}
