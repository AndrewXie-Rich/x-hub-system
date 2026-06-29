use std::collections::BTreeMap;
use std::env;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};

use serde_json::{json, Value};
use xhub_core::{now_ms, HubConfig};
use xhub_db::{MemoryEventRecord, MemoryObjectRecord};

// ---------------------------------------------------------------------------
// Schema-version constants
// ---------------------------------------------------------------------------

pub(crate) const SCHEMA_VERSION: &str = "xhub.memory_bridge.v1";
pub(crate) const MEMORY_OBJECT_SCHEMA: &str = "xhub.memory.object.v1";
pub(crate) const MEMORY_OBJECT_RESULT_SCHEMA: &str = "xhub.memory.object_result.v1";
pub(crate) const MEMORY_OBJECT_LIST_SCHEMA: &str = "xhub.memory.object_list.v1";
pub(crate) const MEMORY_OBJECT_HISTORY_SCHEMA: &str = "xhub.memory.object_history.v1";
pub(crate) const MEMORY_POLICY_RESULT_SCHEMA: &str = "xhub.memory.policy_result.v1";
pub(crate) const MEMORY_PROJECT_CANONICAL_SYNC_SCHEMA: &str =
    "xhub.memory.project_canonical_sync.v1";
pub(crate) const MEMORY_GATEWAY_PREPARE_SCHEMA: &str = "xhub.memory.gateway_prepare.v1";
pub(crate) const MEMORY_WRITEBACK_CANDIDATE_SCHEMA: &str = "xhub.memory.writeback_candidate.v1";
pub(crate) const MEMORY_WRITEBACK_CANDIDATE_EXTRACT_SCHEMA: &str =
    "xhub.memory.writeback_candidate_extract.v1";
pub(crate) const MEMORY_OBJECT_RETRIEVAL_SOURCE: &str = "rust_memory_objects_hybrid_v1";
pub(crate) const MEMORY_RETRIEVAL_TRACE_LIMIT: usize = 32;
pub(crate) static MEMORY_OBJECT_COUNTER: AtomicU64 = AtomicU64::new(1);

// ---------------------------------------------------------------------------
// Shared error / response types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub(crate) struct HttpJsonError {
    pub(crate) status: &'static str,
    pub(crate) body: String,
}

#[derive(Debug, Clone, Copy)]
pub(crate) struct ProjectCanonicalItemKind {
    pub(crate) suffix: &'static str,
    pub(crate) title: &'static str,
    pub(crate) source_kind: &'static str,
    pub(crate) layer: &'static str,
}

#[derive(Debug, Clone, Default)]
pub(crate) struct FlagArgs {
    pub(crate) values: BTreeMap<String, String>,
}

impl FlagArgs {
    pub(crate) fn parse(args: &[String]) -> Result<Self, String> {
        let mut values = BTreeMap::new();
        let mut index = 0;
        while index < args.len() {
            let item = &args[index];
            if !item.starts_with("--") {
                return Err(format!("unexpected positional argument: {item}"));
            }
            let body = &item[2..];
            if let Some((key, value)) = body.split_once('=') {
                values.insert(key.to_string(), value.to_string());
                index += 1;
                continue;
            }
            let key = body.to_string();
            let next = args.get(index + 1).cloned().unwrap_or_default();
            if next.starts_with("--") || next.is_empty() {
                values.insert(key, "1".to_string());
                index += 1;
            } else {
                values.insert(key, next);
                index += 2;
            }
        }
        Ok(Self { values })
    }

    pub(crate) fn optional(&self, key: &str) -> Option<String> {
        self.values
            .get(key)
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
    }

    pub(crate) fn optional_usize(&self, key: &str) -> Result<Option<usize>, String> {
        match self.optional(key) {
            Some(value) => value
                .parse::<usize>()
                .map(Some)
                .map_err(|_| format!("invalid --{key}: {value}")),
            None => Ok(None),
        }
    }

    pub(crate) fn optional_i64(&self, key: &str) -> Result<Option<i64>, String> {
        match self.optional(key) {
            Some(value) => value
                .parse::<i64>()
                .map(Some)
                .map_err(|_| format!("invalid --{key}: {value}")),
            None => Ok(None),
        }
    }

    pub(crate) fn optional_bool(&self, key: &str) -> Option<bool> {
        self.optional(key).map(|value| {
            matches!(
                value.trim().to_ascii_lowercase().as_str(),
                "1" | "true" | "yes" | "on"
            )
        })
    }

    pub(crate) fn optional_list(&self, key: &str) -> Vec<String> {
        self.optional(key)
            .map(|value| split_list(&value))
            .unwrap_or_default()
    }
}

// ---------------------------------------------------------------------------
// Time and id generators
// ---------------------------------------------------------------------------

pub(crate) fn now_ms_i64() -> i64 {
    now_ms().min(i64::MAX as u128) as i64
}

pub(crate) fn next_memory_id() -> String {
    let next = MEMORY_OBJECT_COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("mem_{}_{}", now_ms_i64(), next)
}

pub(crate) fn next_memory_event_id() -> String {
    let next = MEMORY_OBJECT_COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("mev_{}_{}", now_ms_i64(), next)
}

// ---------------------------------------------------------------------------
// JSON value extractors
// ---------------------------------------------------------------------------

pub(crate) fn value_string(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

pub(crate) fn value_usize(value: &Value, key: &str) -> Option<usize> {
    value
        .get(key)
        .and_then(Value::as_u64)
        .and_then(|value| usize::try_from(value).ok())
}

pub(crate) fn value_i64(value: &Value, key: &str) -> Option<i64> {
    value.get(key).and_then(Value::as_i64)
}

pub(crate) fn value_bool(value: &Value, key: &str, fallback: bool) -> bool {
    match value.get(key) {
        Some(Value::Bool(value)) => *value,
        Some(Value::String(value)) => matches!(
            value.trim().to_ascii_lowercase().as_str(),
            "1" | "true" | "yes" | "on"
        ),
        Some(Value::Number(value)) => value.as_i64().unwrap_or(0) != 0,
        _ => fallback,
    }
}

pub(crate) fn value_string_list(value: &Value, key: &str) -> Option<Vec<String>> {
    let raw = value.get(key)?;
    if let Some(array) = raw.as_array() {
        return Some(
            array
                .iter()
                .filter_map(Value::as_str)
                .map(|value| value.trim().to_string())
                .filter(|value| !value.is_empty())
                .collect(),
        );
    }
    raw.as_str().map(split_list)
}

pub(crate) fn split_list(input: &str) -> Vec<String> {
    input
        .split(',')
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .collect()
}

// ---------------------------------------------------------------------------
// Public-text sanitizers
// ---------------------------------------------------------------------------

pub(crate) fn optional_public_token(value: &Value, key: &str) -> Option<String> {
    value_string(value, key).and_then(|raw| sanitize_public_token(&raw))
}

pub(crate) fn sanitize_public_token(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() || looks_like_secret_public(trimmed) {
        return None;
    }
    let out = trimmed
        .chars()
        .filter(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '_' | '-' | '.' | ':' | '/'))
        .take(180)
        .collect::<String>();
    if out.is_empty() {
        None
    } else {
        Some(out)
    }
}

pub(crate) fn sanitize_public_text_value(value: &Value, key: &str) -> Option<String> {
    value_string(value, key).and_then(|raw| sanitize_public_text(&raw, 240))
}

pub(crate) fn sanitize_public_text(value: &str, max_chars: usize) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() || looks_like_secret_public(trimmed) {
        return None;
    }
    Some(
        trimmed
            .chars()
            .filter(|ch| !ch.is_control() || *ch == '\n' || *ch == '\t')
            .take(max_chars)
            .collect::<String>(),
    )
}

pub(crate) fn looks_like_secret_public(value: &str) -> bool {
    let lower = value.to_ascii_lowercase();
    lower.contains("api key")
        || lower.contains("apikey")
        || lower.contains("secret")
        || lower.contains("password")
        || lower.contains("private key")
        || lower.contains("authorization:")
        || lower.contains("bearer ")
        || lower.contains("sk-")
        || lower.contains("xoxb-")
        || lower.contains("aws_secret_access_key")
}

// ---------------------------------------------------------------------------
// Enum / token normalizers (shared between retrieval and projection)
// ---------------------------------------------------------------------------

pub(crate) fn normalize_enum_token(raw: String, allowed: &[&str], fallback: &str) -> String {
    let token = raw.trim().to_ascii_lowercase().replace('-', "_");
    if allowed.iter().any(|item| *item == token) {
        token
    } else {
        fallback.to_string()
    }
}

pub(crate) fn normalize_source_kind_for_object(raw: &str) -> String {
    let normalized = raw.trim().to_ascii_lowercase().replace('-', "_");
    let allowed = [
        "personal_capsule",
        "project_capsule",
        "dialogue_window",
        "guidance_injection",
        "automation_checkpoint",
        "automation_handoff",
        "decision_track",
        "project_goal",
        "project_requirement",
        "current_state",
        "next_step",
        "open_question",
        "risk",
        "recommendation",
        "memory_file",
    ];
    if allowed.iter().any(|item| *item == normalized) {
        normalized
    } else {
        "memory_file".to_string()
    }
}

pub(crate) fn normalize_memory_layer(raw: &str) -> String {
    normalize_enum_token(
        raw.to_string(),
        &[
            "l0_constitution",
            "l1_canonical",
            "l2_observations",
            "l3_working_set",
            "l4_raw_evidence",
        ],
        "",
    )
}

pub(crate) fn normalize_visibility_filter(raw: &str) -> String {
    normalize_enum_token(
        raw.to_string(),
        &[
            "local_only",
            "sanitized_remote_ok",
            "refs_only",
            "never_export",
        ],
        "",
    )
}

pub(crate) fn normalize_sensitivity_filter(raw: &str) -> String {
    normalize_enum_token(
        raw.to_string(),
        &["public", "internal", "private", "secret"],
        "",
    )
}

pub(crate) fn memory_sensitivity_allowed(actual: &str, max_allowed: &str) -> bool {
    sensitivity_rank(actual) <= sensitivity_rank(max_allowed)
}

pub(crate) fn sensitivity_rank(value: &str) -> i32 {
    match value.trim().to_ascii_lowercase().as_str() {
        "public" => 0,
        "internal" => 1,
        "private" => 2,
        "secret" => 3,
        _ => 3,
    }
}

// ---------------------------------------------------------------------------
// Project canonical id helpers
// ---------------------------------------------------------------------------

pub(crate) fn project_canonical_item_kind(raw_key: &str) -> Option<ProjectCanonicalItemKind> {
    let suffix = raw_key
        .trim()
        .strip_prefix("xterminal.project.memory.")
        .unwrap_or_else(|| raw_key.trim());
    match suffix {
        "goal" => Some(ProjectCanonicalItemKind {
            suffix: "goal",
            title: "Project goal",
            source_kind: "project_goal",
            layer: "l1_canonical",
        }),
        "requirements" => Some(ProjectCanonicalItemKind {
            suffix: "requirements",
            title: "Project requirements",
            source_kind: "project_requirement",
            layer: "l1_canonical",
        }),
        "current_state" => Some(ProjectCanonicalItemKind {
            suffix: "current_state",
            title: "Current state",
            source_kind: "current_state",
            layer: "l3_working_set",
        }),
        "decisions" => Some(ProjectCanonicalItemKind {
            suffix: "decisions",
            title: "Decisions",
            source_kind: "decision_track",
            layer: "l1_canonical",
        }),
        "next_steps" => Some(ProjectCanonicalItemKind {
            suffix: "next_steps",
            title: "Next steps",
            source_kind: "next_step",
            layer: "l3_working_set",
        }),
        "open_questions" => Some(ProjectCanonicalItemKind {
            suffix: "open_questions",
            title: "Open questions",
            source_kind: "open_question",
            layer: "l2_observations",
        }),
        "risks" => Some(ProjectCanonicalItemKind {
            suffix: "risks",
            title: "Risks",
            source_kind: "risk",
            layer: "l2_observations",
        }),
        "recommendations" => Some(ProjectCanonicalItemKind {
            suffix: "recommendations",
            title: "Recommendations",
            source_kind: "recommendation",
            layer: "l2_observations",
        }),
        _ => None,
    }
}

pub(crate) fn project_canonical_memory_id(project_id: &str, suffix: &str) -> String {
    let project = sanitize_id_segment(project_id, 80);
    let suffix = sanitize_id_segment(suffix, 64);
    format!("mem_xt_project_{project}_{suffix}")
}

pub(crate) fn sanitize_id_segment(raw: &str, max_chars: usize) -> String {
    let value = raw
        .trim()
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || matches!(ch, '_' | '-' | '.') {
                ch.to_ascii_lowercase()
            } else {
                '_'
            }
        })
        .take(max_chars)
        .collect::<String>();
    let trimmed = value.trim_matches('_').to_string();
    if trimmed.is_empty() {
        "unknown".to_string()
    } else {
        trimmed
    }
}

pub(crate) fn stable_fnv1a64_hex(value: &str) -> String {
    let mut hash = 0xcbf29ce484222325_u64;
    for byte in value.as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    format!("{hash:016x}")
}

pub(crate) fn summarize_memory_text(text: &str) -> String {
    let one_line = text
        .split_whitespace()
        .take(80)
        .collect::<Vec<_>>()
        .join(" ");
    if one_line.chars().count() <= 240 {
        one_line
    } else {
        one_line.chars().take(240).collect()
    }
}

pub(crate) fn raw_evidence_requested(layers: &[String], source_kinds: &[String]) -> bool {
    layers
        .iter()
        .any(|layer| layer.trim().eq_ignore_ascii_case("l4_raw_evidence"))
        || source_kinds.iter().any(|kind| {
            let lower = kind.trim().to_ascii_lowercase();
            lower.contains("raw") || lower.contains("evidence")
        })
}

// ---------------------------------------------------------------------------
// Query string helpers
// ---------------------------------------------------------------------------

pub(crate) fn query_param(query: &str, key: &str) -> Option<String> {
    for pair in query.split('&') {
        if pair.is_empty() {
            continue;
        }
        let (raw_key, raw_value) = pair.split_once('=').unwrap_or((pair, ""));
        if percent_decode(raw_key).ok()?.as_str() == key {
            return percent_decode(raw_value).ok();
        }
    }
    None
}

pub(crate) fn query_usize(query: &str, key: &str, fallback: usize) -> Result<usize, String> {
    match query_param(query, key) {
        Some(value) if !value.trim().is_empty() => value
            .trim()
            .parse::<usize>()
            .map_err(|_| format!("invalid query parameter: {key}")),
        _ => Ok(fallback),
    }
}

pub(crate) fn query_bool(query: &str, key: &str, fallback: bool) -> bool {
    query_param(query, key)
        .map(|value| {
            matches!(
                value.trim().to_ascii_lowercase().as_str(),
                "1" | "true" | "yes" | "on"
            )
        })
        .unwrap_or(fallback)
}

pub(crate) fn percent_decode(input: &str) -> Result<String, String> {
    let bytes = input.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        match bytes[index] {
            b'+' => {
                out.push(b' ');
                index += 1;
            }
            b'%' if index + 2 < bytes.len() => {
                let hex = std::str::from_utf8(&bytes[index + 1..index + 3])
                    .map_err(|err| err.to_string())?;
                let value = u8::from_str_radix(hex, 16).map_err(|err| err.to_string())?;
                out.push(value);
                index += 3;
            }
            value => {
                out.push(value);
                index += 1;
            }
        }
    }
    String::from_utf8(out).map_err(|err| err.to_string())
}

// ---------------------------------------------------------------------------
// Env helpers
// ---------------------------------------------------------------------------

pub(crate) fn env_bool(key: &str, fallback: bool) -> bool {
    match env::var(key) {
        Ok(value) => matches!(
            value.trim().to_ascii_lowercase().as_str(),
            "1" | "true" | "yes" | "on"
        ),
        Err(_) => fallback,
    }
}

pub fn memory_writer_authority_enabled() -> bool {
    env_bool("XHUB_RUST_MEMORY_WRITER_AUTHORITY", false)
        && env_bool("XHUB_RUST_MEMORY_WRITE_AUTHORITY", false)
        && env_bool("XHUB_RUST_MEMORY_PRODUCTION_AUTHORITY", false)
}

pub fn memory_dir_from_env(config: &HubConfig) -> PathBuf {
    env::var("XHUB_RUST_MEMORY_DIR")
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| config.root_dir.join("data").join("memory"))
}

// ---------------------------------------------------------------------------
// HTTP JSON shaping helpers
// ---------------------------------------------------------------------------

pub(crate) fn parse_json_body(body: &str) -> Result<Value, HttpJsonError> {
    if body.trim().is_empty() {
        return Ok(Value::Object(Default::default()));
    }
    serde_json::from_str::<Value>(body).map_err(|err| {
        http_json_error(
            "400 Bad Request",
            "invalid_memory_json",
            format!("invalid JSON body: {err}"),
        )
    })
}

pub(crate) fn http_json_error(
    status: &'static str,
    error_code: &str,
    message: String,
) -> HttpJsonError {
    http_json_error_json(
        status,
        json!({
            "schema_version": MEMORY_OBJECT_RESULT_SCHEMA,
            "ok": false,
            "status": "error",
            "error_code": error_code,
            "message": message,
        }),
    )
}

pub(crate) fn http_json_error_json(status: &'static str, body: Value) -> HttpJsonError {
    HttpJsonError {
        status,
        body: body.to_string(),
    }
}

pub(crate) fn memory_object_to_json(object: &MemoryObjectRecord) -> Value {
    json!({
        "schema_version": &object.schema_version,
        "memory_id": &object.memory_id,
        "scope": &object.scope,
        "owner_id": &object.owner_id,
        "run_id": object.run_id.as_deref(),
        "project_id": object.project_id.as_deref(),
        "agent_id": object.agent_id.as_deref(),
        "source_kind": &object.source_kind,
        "layer": &object.layer,
        "title": &object.title,
        "text": if object.sensitivity == "secret" { "redacted by Rust memory policy" } else { object.text.as_str() },
        "summary": &object.summary,
        "tags": serde_json::from_str::<Value>(&object.tags_json).unwrap_or_else(|_| json!([])),
        "sensitivity": &object.sensitivity,
        "visibility": &object.visibility,
        "status": &object.status,
        "pinned": object.pinned,
        "immutable": object.immutable,
        "ttl_ms": object.ttl_ms,
        "created_at_ms": object.created_at_ms,
        "updated_at_ms": object.updated_at_ms,
        "last_accessed_at_ms": object.last_accessed_at_ms,
        "version": object.version,
        "provenance": serde_json::from_str::<Value>(&object.provenance_json).unwrap_or_else(|_| json!({})),
        "policy": serde_json::from_str::<Value>(&object.policy_json).unwrap_or_else(|_| json!({})),
    })
}

pub(crate) fn memory_event_to_json(event: &MemoryEventRecord) -> Value {
    json!({
        "schema_version": "xhub.memory.event.v1",
        "event_id": &event.event_id,
        "memory_id": &event.memory_id,
        "operation": &event.operation,
        "actor_id": &event.actor,
        "actor": &event.actor, // deprecated alias — remove after Phase 3 consumers migrate
        "reason": &event.reason,
        "before_version": event.before_version,
        "after_version": event.after_version,
        "before_json": event.before_json.as_ref().and_then(|raw| serde_json::from_str::<Value>(raw).ok()),
        "after_json": event.after_json.as_ref().and_then(|raw| serde_json::from_str::<Value>(raw).ok()),
        "policy_decision": &event.policy_decision,
        "deny_code": &event.deny_code,
        "audit_ref": &event.audit_ref,
        "created_at_ms": event.created_at_ms,
    })
}

// ---------------------------------------------------------------------------
// Property / scoring micro-helpers (shared by retrieval and projection)
// ---------------------------------------------------------------------------

pub(crate) fn property_enabled(properties: &BTreeMap<String, bool>, key: &str) -> bool {
    properties.get(key).copied().unwrap_or(false)
}

pub(crate) fn query_has_any(query_tokens: &[String], query_lower: &str, needles: &[&str]) -> bool {
    needles.iter().any(|needle| {
        query_lower.contains(needle) || query_tokens.iter().any(|token| token == needle)
    })
}

pub(crate) fn first_non_empty_text(values: &[&str]) -> String {
    values
        .iter()
        .map(|value| value.trim())
        .find(|value| !value.is_empty())
        .unwrap_or("")
        .to_string()
}

pub(crate) fn round6(value: f64) -> f64 {
    (value * 1_000_000.0).round() / 1_000_000.0
}
