use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone)]
pub struct PythonRuntimeBridge {
    pub base_url: String,
    pub health_path: String,
}

impl Default for PythonRuntimeBridge {
    fn default() -> Self {
        Self {
            base_url: "http://127.0.0.1:8765".to_string(),
            health_path: "/health".to_string(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct LocalModelInventoryRow {
    pub model_id: String,
    pub display_name: String,
    pub family_key: String,
    pub artifact_path: String,
    pub format: String,
    pub artifact_size_bytes: u64,
    pub checksum: String,
    pub quantization: String,
    pub runtime_provider: String,
    pub availability_state: String,
    pub blocking_reason_code: String,
    pub capabilities: Vec<String>,
    pub memory_risk: String,
    pub duplicate_artifact_of: String,
    pub runtime_preflight: LocalRuntimePreflight,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct LocalRuntimePreflight {
    pub runtime_provider: String,
    pub availability_state: String,
    pub blocking_reason_code: String,
    pub runtime_source: String,
    pub runtime_source_path: String,
    pub supported_format: bool,
    pub side_effect_free: bool,
    pub runtime_updated_at_ms: u64,
    pub capability_tags: Vec<String>,
    pub runtime_missing_requirements: Vec<String>,
}

pub fn local_model_inventory_rows(runtime_base_dir: &Path) -> Vec<LocalModelInventoryRow> {
    local_model_inventory_rows_with_host_memory(runtime_base_dir, host_memory_bytes())
}

fn local_model_inventory_rows_with_host_memory(
    runtime_base_dir: &Path,
    host_memory_bytes: Option<u64>,
) -> Vec<LocalModelInventoryRow> {
    let state_path = runtime_base_dir.join("models_state.json");
    let Ok(raw) = fs::read_to_string(&state_path) else {
        return Vec::new();
    };
    let Ok(value) = serde_json::from_str::<Value>(&raw) else {
        return Vec::new();
    };
    let Some(models) = value.get("models").and_then(Value::as_array) else {
        return Vec::new();
    };
    let runtime_status = RuntimeStatusSnapshot::load(runtime_base_dir);

    let mut rows = Vec::new();
    for model in models {
        let Some(row) =
            local_model_inventory_row(runtime_base_dir, model, &runtime_status, host_memory_bytes)
        else {
            continue;
        };
        rows.push(row);
    }
    rows.sort_by(|lhs, rhs| lhs.model_id.cmp(&rhs.model_id));
    rows.dedup_by(|lhs, rhs| lhs.model_id == rhs.model_id);
    mark_duplicate_artifacts(&mut rows);
    rows
}

fn local_model_inventory_row(
    runtime_base_dir: &Path,
    value: &Value,
    runtime_status: &RuntimeStatusSnapshot,
    host_memory_bytes: Option<u64>,
) -> Option<LocalModelInventoryRow> {
    let model_id = first_value_string(value, &["model_id", "modelId", "id"]);
    if model_id.is_empty() {
        return None;
    }
    let display_name = first_non_empty(
        &first_value_string(value, &["display_name", "displayName", "name"]),
        &model_id,
    );
    let artifact_path = resolve_artifact_path(runtime_base_dir, value);
    let backend = first_value_string(value, &["runtime_provider", "runtimeProvider", "backend"]);
    let kind = normalized_token(&first_value_string(value, &["kind"]));
    let is_remote_reference = kind == "paid_online"
        || (!backend.is_empty() && backend != "mlx" && artifact_path.is_empty());
    if is_remote_reference {
        return None;
    }

    let format = normalized_artifact_format(&first_non_empty(
        &first_value_string(value, &["format", "artifact_format", "artifactFormat"]),
        &infer_model_format(&artifact_path, &backend),
    ));
    let runtime_provider = normalized_runtime_provider(&backend, &format);
    let capabilities = capability_tags(value, &format);
    let artifact_size_bytes = artifact_size_bytes(&artifact_path);
    let estimated_memory_bytes = estimated_memory_bytes(value, artifact_size_bytes);
    let memory_risk = model_memory_risk(value, estimated_memory_bytes, host_memory_bytes);
    let runtime_preflight =
        runtime_preflight(&runtime_provider, &format, runtime_status, &capabilities);
    let artifact_exists = !artifact_path.is_empty() && Path::new(&artifact_path).exists();
    let (availability_state, blocking_reason_code) = local_availability_state(
        &artifact_path,
        artifact_exists,
        &format,
        &runtime_preflight,
        &memory_risk,
    );

    Some(LocalModelInventoryRow {
        model_id,
        display_name,
        family_key: first_non_empty(
            &normalized_token(&first_value_string(
                value,
                &["family_key", "familyKey", "family"],
            )),
            &family_key_for_local_model(value),
        ),
        artifact_path,
        format,
        artifact_size_bytes,
        checksum: first_value_string(
            value,
            &[
                "checksum",
                "sha256",
                "sha256_checksum",
                "sha256Checksum",
                "artifact_checksum",
                "artifactChecksum",
            ],
        ),
        quantization: first_non_empty(
            &normalized_token(&first_value_string(
                value,
                &[
                    "quantization",
                    "quant",
                    "quantization_level",
                    "quantizationLevel",
                ],
            )),
            "unknown",
        ),
        runtime_provider,
        availability_state,
        blocking_reason_code,
        capabilities,
        memory_risk,
        duplicate_artifact_of: String::new(),
        runtime_preflight,
    })
}

fn infer_model_format(artifact_path: &str, backend: &str) -> String {
    let path = normalized_token(artifact_path);
    if path.ends_with(".gguf") {
        return "gguf".to_string();
    }
    if path.ends_with(".mlmodel") || path.ends_with(".mlmodelc") {
        return "coreml".to_string();
    }
    if path.ends_with(".safetensors") || path.ends_with(".bin") {
        return "transformers".to_string();
    }
    let backend = normalized_token(backend);
    if backend == "mlx" {
        return "mlx".to_string();
    }
    if backend.is_empty() {
        "unknown".to_string()
    } else {
        backend
    }
}

fn normalized_artifact_format(raw: &str) -> String {
    match normalized_token(raw).replace('_', "-").as_str() {
        "gguf" => "gguf".to_string(),
        "mlx" | "mlx-lm" => "mlx".to_string(),
        "coreml" | "core-ml" | "mlmodel" | "mlmodelc" => "coreml".to_string(),
        "transformers" | "safetensors" | "hf" | "huggingface" => "transformers".to_string(),
        "" => "unknown".to_string(),
        other => other.to_string(),
    }
}

fn normalized_runtime_provider(backend: &str, format: &str) -> String {
    let backend = normalized_token(backend);
    if !backend.is_empty() {
        return match backend.as_str() {
            "llama.cpp" | "llama-cpp" | "llamacpp" => "llama.cpp".to_string(),
            "coreml" | "core-ml" => "coreml".to_string(),
            "hf" | "huggingface" => "transformers".to_string(),
            other => other.to_string(),
        };
    }
    match format {
        "gguf" => "llama.cpp".to_string(),
        "mlx" => "mlx".to_string(),
        "coreml" => "coreml".to_string(),
        "transformers" => "transformers".to_string(),
        _ => "unknown".to_string(),
    }
}

fn resolve_artifact_path(runtime_base_dir: &Path, value: &Value) -> String {
    let keys = [
        "resolved_artifact_path",
        "resolvedArtifactPath",
        "current_artifact_path",
        "currentArtifactPath",
        "moved_to_artifact_path",
        "movedToArtifactPath",
        "artifact_path",
        "artifactPath",
        "model_path",
        "modelPath",
        "path",
    ];
    let mut first = String::new();
    for key in keys {
        let raw = value.get(key).and_then(Value::as_str).unwrap_or("").trim();
        if raw.is_empty() {
            continue;
        }
        let candidate = resolve_runtime_relative_path(runtime_base_dir, raw);
        if first.is_empty() {
            first = candidate.display().to_string();
        }
        if candidate.exists() {
            return candidate.display().to_string();
        }
    }
    first
}

fn resolve_runtime_relative_path(runtime_base_dir: &Path, raw: &str) -> PathBuf {
    let path = PathBuf::from(raw);
    if path.is_absolute() || runtime_base_dir.as_os_str().is_empty() {
        path
    } else {
        runtime_base_dir.join(path)
    }
}

fn artifact_size_bytes(artifact_path: &str) -> u64 {
    if artifact_path.is_empty() {
        return 0;
    }
    fs::metadata(artifact_path)
        .map(|metadata| metadata.len())
        .unwrap_or(0)
}

fn estimated_memory_bytes(value: &Value, artifact_size_bytes: u64) -> u64 {
    first_value_u64(
        value,
        &[
            "estimated_memory_bytes",
            "estimatedMemoryBytes",
            "required_memory_bytes",
            "requiredMemoryBytes",
            "memory_bytes",
            "memoryBytes",
        ],
    )
    .unwrap_or_else(|| artifact_size_bytes.saturating_mul(2))
}

fn model_memory_risk(
    value: &Value,
    estimated_memory_bytes: u64,
    host_memory_bytes: Option<u64>,
) -> String {
    let explicit = normalized_token(&first_value_string(
        value,
        &["memory_risk", "memoryRisk", "memory_state", "memoryState"],
    ));
    if !explicit.is_empty() {
        return explicit;
    }
    let Some(host_memory_bytes) = host_memory_bytes.filter(|value| *value > 0) else {
        return if estimated_memory_bytes >= 32 * GIB {
            "high".to_string()
        } else if estimated_memory_bytes >= 12 * GIB {
            "medium".to_string()
        } else {
            "unknown".to_string()
        };
    };
    if estimated_memory_bytes == 0 {
        return "unknown".to_string();
    }
    if estimated_memory_bytes.saturating_mul(5) >= host_memory_bytes.saturating_mul(4) {
        "high".to_string()
    } else if estimated_memory_bytes.saturating_mul(2) >= host_memory_bytes {
        "medium".to_string()
    } else {
        "low".to_string()
    }
}

const GIB: u64 = 1024 * 1024 * 1024;

fn host_memory_bytes() -> Option<u64> {
    #[cfg(target_os = "macos")]
    {
        let output = Command::new("sysctl")
            .args(["-n", "hw.memsize"])
            .output()
            .ok()?;
        if !output.status.success() {
            return None;
        }
        String::from_utf8_lossy(&output.stdout)
            .trim()
            .parse::<u64>()
            .ok()
    }
    #[cfg(target_os = "linux")]
    {
        let raw = fs::read_to_string("/proc/meminfo").ok()?;
        for line in raw.lines() {
            let Some(rest) = line.strip_prefix("MemTotal:") else {
                continue;
            };
            let kb = rest
                .split_whitespace()
                .next()
                .and_then(|value| value.parse::<u64>().ok())?;
            return Some(kb.saturating_mul(1024));
        }
        None
    }
    #[cfg(not(any(target_os = "macos", target_os = "linux")))]
    {
        None
    }
}

fn local_availability_state(
    artifact_path: &str,
    artifact_exists: bool,
    format: &str,
    runtime_preflight: &LocalRuntimePreflight,
    memory_risk: &str,
) -> (String, String) {
    if artifact_path.is_empty() {
        return ("unknown".to_string(), "artifact_path_missing".to_string());
    }
    if !artifact_exists {
        return ("stale_artifact".to_string(), "artifact_missing".to_string());
    }
    if format == "unknown" {
        return ("blocked".to_string(), "unsupported_format".to_string());
    }
    if memory_risk == "high" {
        return ("blocked".to_string(), "memory_risk_high".to_string());
    }
    if runtime_preflight.availability_state != "ready" {
        return (
            runtime_preflight.availability_state.clone(),
            runtime_preflight.blocking_reason_code.clone(),
        );
    }
    ("ready".to_string(), String::new())
}

fn runtime_preflight(
    runtime_provider: &str,
    format: &str,
    runtime_status: &RuntimeStatusSnapshot,
    capabilities: &[String],
) -> LocalRuntimePreflight {
    let supported_format = format != "unknown" && runtime_provider != "unknown";
    let Some(status) = runtime_status.providers.get(runtime_provider) else {
        return LocalRuntimePreflight {
            runtime_provider: runtime_provider.to_string(),
            availability_state: "unknown_stale".to_string(),
            blocking_reason_code: if runtime_provider == "unknown" {
                "runtime_provider_missing".to_string()
            } else {
                "runtime_status_missing".to_string()
            },
            runtime_source: String::new(),
            runtime_source_path: String::new(),
            supported_format,
            side_effect_free: true,
            runtime_updated_at_ms: 0,
            capability_tags: capabilities.to_vec(),
            runtime_missing_requirements: Vec::new(),
        };
    };
    if !supported_format {
        return LocalRuntimePreflight {
            runtime_provider: runtime_provider.to_string(),
            availability_state: "blocked".to_string(),
            blocking_reason_code: "unsupported_format".to_string(),
            runtime_source: status.runtime_source.clone(),
            runtime_source_path: status.runtime_source_path.clone(),
            supported_format,
            side_effect_free: true,
            runtime_updated_at_ms: status.updated_at_ms,
            capability_tags: capabilities.to_vec(),
            runtime_missing_requirements: status.runtime_missing_requirements.clone(),
        };
    }
    if status.runtime_resolution_state == "missing"
        || status.runtime_resolution_state == "not_found"
        || status.runtime_reason_code.contains("missing")
        || status.pack_installed == Some(false)
    {
        return LocalRuntimePreflight {
            runtime_provider: runtime_provider.to_string(),
            availability_state: "blocked".to_string(),
            blocking_reason_code: first_non_empty(
                &status.runtime_reason_code,
                "runtime_provider_missing",
            ),
            runtime_source: status.runtime_source.clone(),
            runtime_source_path: status.runtime_source_path.clone(),
            supported_format,
            side_effect_free: true,
            runtime_updated_at_ms: status.updated_at_ms,
            capability_tags: capabilities.to_vec(),
            runtime_missing_requirements: status.runtime_missing_requirements.clone(),
        };
    }
    if !status.ok {
        return LocalRuntimePreflight {
            runtime_provider: runtime_provider.to_string(),
            availability_state: "blocked".to_string(),
            blocking_reason_code: first_non_empty(
                &status.reason_code,
                "runtime_provider_unavailable",
            ),
            runtime_source: status.runtime_source.clone(),
            runtime_source_path: status.runtime_source_path.clone(),
            supported_format,
            side_effect_free: true,
            runtime_updated_at_ms: status.updated_at_ms,
            capability_tags: capabilities.to_vec(),
            runtime_missing_requirements: status.runtime_missing_requirements.clone(),
        };
    }
    let missing = missing_runtime_capabilities(capabilities, &status.available_task_kinds);
    if !missing.is_empty() {
        return LocalRuntimePreflight {
            runtime_provider: runtime_provider.to_string(),
            availability_state: "blocked".to_string(),
            blocking_reason_code: format!("capability_mismatch:{}", missing.join(",")),
            runtime_source: status.runtime_source.clone(),
            runtime_source_path: status.runtime_source_path.clone(),
            supported_format,
            side_effect_free: true,
            runtime_updated_at_ms: status.updated_at_ms,
            capability_tags: capabilities.to_vec(),
            runtime_missing_requirements: missing,
        };
    }
    LocalRuntimePreflight {
        runtime_provider: runtime_provider.to_string(),
        availability_state: "ready".to_string(),
        blocking_reason_code: String::new(),
        runtime_source: status.runtime_source.clone(),
        runtime_source_path: status.runtime_source_path.clone(),
        supported_format,
        side_effect_free: true,
        runtime_updated_at_ms: status.updated_at_ms,
        capability_tags: capabilities.to_vec(),
        runtime_missing_requirements: Vec::new(),
    }
}

fn missing_runtime_capabilities(capabilities: &[String], available: &[String]) -> Vec<String> {
    if available.is_empty() {
        return Vec::new();
    }
    let available: BTreeSet<String> = available.iter().cloned().collect();
    capabilities
        .iter()
        .filter(|capability| !available.contains(*capability))
        .cloned()
        .collect()
}

#[derive(Debug, Clone, Default)]
struct RuntimeStatusSnapshot {
    providers: BTreeMap<String, RuntimeProviderStatus>,
}

impl RuntimeStatusSnapshot {
    fn load(runtime_base_dir: &Path) -> Self {
        let path = runtime_base_dir.join("ai_runtime_status.json");
        let Ok(raw) = fs::read_to_string(path) else {
            return Self::default();
        };
        let Ok(value) = serde_json::from_str::<Value>(&raw) else {
            return Self::default();
        };
        let mut providers = BTreeMap::new();
        if let Some(map) = value.get("providers").and_then(Value::as_object) {
            for (provider_id, provider_value) in map {
                let status = RuntimeProviderStatus::from_value(provider_id, provider_value);
                providers.insert(status.provider.clone(), status);
            }
        }
        if providers.is_empty() {
            let status = RuntimeProviderStatus::from_value("mlx", &value);
            if !status.provider.is_empty() && (status.ok || !status.reason_code.is_empty()) {
                providers.insert(status.provider.clone(), status);
            }
        }
        Self { providers }
    }
}

#[derive(Debug, Clone, Default)]
struct RuntimeProviderStatus {
    provider: String,
    ok: bool,
    reason_code: String,
    runtime_source: String,
    runtime_source_path: String,
    runtime_resolution_state: String,
    runtime_reason_code: String,
    runtime_missing_requirements: Vec<String>,
    available_task_kinds: Vec<String>,
    updated_at_ms: u64,
    pack_installed: Option<bool>,
}

impl RuntimeProviderStatus {
    fn from_value(provider_id: &str, value: &Value) -> Self {
        let provider = normalized_runtime_provider(
            &first_non_empty(
                &first_value_string(value, &["provider", "provider_id", "providerId"]),
                provider_id,
            ),
            "",
        );
        Self {
            provider,
            ok: value.get("ok").and_then(Value::as_bool).unwrap_or(false),
            reason_code: normalized_token(&first_value_string(
                value,
                &["reason_code", "reasonCode", "error"],
            )),
            runtime_source: normalized_token(&first_value_string(
                value,
                &["runtime_source", "runtimeSource"],
            )),
            runtime_source_path: first_value_string(
                value,
                &["runtime_source_path", "runtimeSourcePath"],
            ),
            runtime_resolution_state: normalized_token(&first_value_string(
                value,
                &["runtime_resolution_state", "runtimeResolutionState"],
            )),
            runtime_reason_code: normalized_token(&first_value_string(
                value,
                &["runtime_reason_code", "runtimeReasonCode"],
            )),
            runtime_missing_requirements: string_array_value(
                value,
                &["runtime_missing_requirements", "runtimeMissingRequirements"],
            ),
            available_task_kinds: capability_tags_from_strings(&string_array_value(
                value,
                &[
                    "available_task_kinds",
                    "availableTaskKinds",
                    "real_task_kinds",
                    "realTaskKinds",
                ],
            )),
            updated_at_ms: first_value_u64(value, &["updated_at_ms", "updatedAtMs", "updatedAt"])
                .unwrap_or(0),
            pack_installed: value
                .get("pack_installed")
                .or_else(|| value.get("packInstalled"))
                .and_then(Value::as_bool),
        }
    }
}

fn capability_tags(value: &Value, format: &str) -> Vec<String> {
    let raw = value
        .get("capabilities")
        .or_else(|| value.get("task_kinds"))
        .or_else(|| value.get("taskKinds"))
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(Value::as_str)
                .map(|item| item.to_string())
                .collect::<Vec<String>>()
        })
        .unwrap_or_default();
    let mut tags = capability_tags_from_strings(&raw);
    if tags.is_empty() {
        tags.push("text.generate".to_string());
        if format == "transformers" {
            tags.push("embedding.generate".to_string());
        }
    }
    tags.sort();
    tags.dedup();
    tags
}

fn capability_tags_from_strings(values: &[String]) -> Vec<String> {
    values
        .iter()
        .map(|value| {
            match normalized_token(value)
                .replace('_', ".")
                .replace('-', ".")
                .as_str()
            {
                "text.generate" | "generate.text" => "text.generate".to_string(),
                "text.summarize" | "summarize" => "text.summarize".to_string(),
                "code.assist" | "code" => "code.assist".to_string(),
                "code.review" => "code.review".to_string(),
                "embedding.generate" | "embeddings" | "embedding" => {
                    "embedding.generate".to_string()
                }
                "vision.describe" | "image.describe" => "vision.describe".to_string(),
                "vision.ocr" | "ocr" => "vision.ocr".to_string(),
                "audio.transcribe" | "transcribe" => "audio.transcribe".to_string(),
                "audio.tts" | "tts" => "audio.tts".to_string(),
                "tool.calling" | "tool.use" | "function.calling" => "tool.calling".to_string(),
                other => other.to_string(),
            }
        })
        .filter(|value| !value.is_empty())
        .collect()
}

fn family_key_for_local_model(value: &Value) -> String {
    let raw = normalized_token(&first_value_string(
        value,
        &[
            "model_id",
            "modelId",
            "id",
            "name",
            "display_name",
            "displayName",
        ],
    ));
    for family in [
        "llama",
        "qwen",
        "mistral",
        "mixtral",
        "gemma",
        "deepseek",
        "phi",
        "yi",
        "codellama",
        "starcoder",
    ] {
        if raw.contains(family) {
            return family.to_string();
        }
    }
    if raw.contains("gpt") {
        return "gpt".to_string();
    }
    "unknown".to_string()
}

fn mark_duplicate_artifacts(rows: &mut [LocalModelInventoryRow]) {
    let mut first_by_path = BTreeMap::<String, String>::new();
    for row in rows.iter_mut() {
        let path = normalized_token(&row.artifact_path);
        if path.is_empty() {
            continue;
        }
        if let Some(first_model_id) = first_by_path.get(&path) {
            row.duplicate_artifact_of = first_model_id.clone();
        } else {
            first_by_path.insert(path, row.model_id.clone());
        }
    }
}

fn first_value_string(value: &Value, keys: &[&str]) -> String {
    for key in keys {
        let raw = value.get(*key).and_then(Value::as_str).unwrap_or("").trim();
        if !raw.is_empty() {
            return raw.to_string();
        }
    }
    String::new()
}

fn first_value_u64(value: &Value, keys: &[&str]) -> Option<u64> {
    for key in keys {
        let Some(item) = value.get(*key) else {
            continue;
        };
        if let Some(number) = item.as_u64() {
            return Some(number);
        }
        if let Some(number) = item.as_i64() {
            return u64::try_from(number.max(0)).ok();
        }
        if let Some(raw) = item.as_str() {
            if let Ok(number) = raw.trim().parse::<u64>() {
                return Some(number);
            }
        }
    }
    None
}

fn string_array_value(value: &Value, keys: &[&str]) -> Vec<String> {
    for key in keys {
        let Some(item) = value.get(*key) else {
            continue;
        };
        if let Some(items) = item.as_array() {
            let values = items
                .iter()
                .filter_map(Value::as_str)
                .map(normalized_token)
                .filter(|item| !item.is_empty())
                .collect::<Vec<String>>();
            if !values.is_empty() {
                return values;
            }
        }
        if let Some(raw) = item.as_str() {
            let values = raw
                .split(|ch: char| ch == ',' || ch.is_whitespace())
                .map(normalized_token)
                .filter(|item| !item.is_empty())
                .collect::<Vec<String>>();
            if !values.is_empty() {
                return values;
            }
        }
    }
    Vec::new()
}

fn first_non_empty(value: &str, fallback: &str) -> String {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        fallback.trim().to_string()
    } else {
        trimmed.to_string()
    }
}

fn normalized_token(value: &str) -> String {
    value.trim().to_lowercase()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn local_inventory_returns_empty_when_models_state_is_absent() {
        let dir = unique_temp_dir("xhub-local-inventory-empty");
        fs::create_dir_all(&dir).expect("temp dir should be created");

        let rows = local_model_inventory_rows(&dir);

        assert!(rows.is_empty());
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn local_inventory_reads_local_rows_without_remote_references() {
        let dir = unique_temp_dir("xhub-local-inventory");
        fs::create_dir_all(&dir).expect("temp dir should be created");
        let artifact_path = dir.join("model.gguf");
        fs::write(&artifact_path, "fixture").expect("artifact should be written");
        fs::write(
            dir.join("models_state.json"),
            format!(
                r#"{{
                  "models": [
                    {{
                      "id": "local.gguf",
                      "backend": "mlx",
                      "modelPath": "{}",
                      "capabilities": ["text_generate"]
                    }},
                    {{
                      "id": "remote.paid",
                      "backend": "openai",
                      "kind": "paid_online"
                    }}
                  ]
                }}"#,
                artifact_path.display()
            ),
        )
        .expect("models_state should be written");
        write_runtime_status(&dir, "mlx", true, &["text_generate"]);

        let rows = local_model_inventory_rows(&dir);

        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].model_id, "local.gguf");
        assert_eq!(rows[0].format, "gguf");
        assert_eq!(rows[0].availability_state, "ready");
        assert_eq!(rows[0].blocking_reason_code, "");
        assert_eq!(rows[0].capabilities, vec!["text.generate"]);
        assert_eq!(rows[0].runtime_preflight.availability_state, "ready");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn local_inventory_does_not_mark_ready_without_runtime_status() {
        let dir = unique_temp_dir("xhub-local-inventory-runtime-missing");
        fs::create_dir_all(&dir).expect("temp dir should be created");
        let artifact_path = dir.join("model.gguf");
        fs::write(&artifact_path, "fixture").expect("artifact should be written");
        fs::write(
            dir.join("models_state.json"),
            format!(
                r#"{{
                  "models": [
                    {{
                      "id": "local.gguf",
                      "backend": "llama.cpp",
                      "modelPath": "{}"
                    }}
                  ]
                }}"#,
                artifact_path.display()
            ),
        )
        .expect("models_state should be written");

        let rows = local_model_inventory_rows(&dir);

        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].availability_state, "unknown_stale");
        assert_eq!(rows[0].blocking_reason_code, "runtime_status_missing");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn local_inventory_reports_unknown_format_as_unsupported() {
        let dir = unique_temp_dir("xhub-local-inventory-unknown-format");
        fs::create_dir_all(&dir).expect("temp dir should be created");
        let artifact_path = dir.join("model.unknown");
        fs::write(&artifact_path, "fixture").expect("artifact should be written");
        fs::write(
            dir.join("models_state.json"),
            format!(
                r#"{{
                  "models": [
                    {{
                      "id": "local.unknown",
                      "backend": "unknown",
                      "modelPath": "{}"
                    }}
                  ]
                }}"#,
                artifact_path.display()
            ),
        )
        .expect("models_state should be written");

        let rows = local_model_inventory_rows(&dir);

        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].format, "unknown");
        assert_eq!(rows[0].availability_state, "blocked");
        assert_eq!(rows[0].blocking_reason_code, "unsupported_format");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn local_inventory_marks_duplicate_artifact_rows_stably() {
        let dir = unique_temp_dir("xhub-local-inventory-duplicate");
        fs::create_dir_all(&dir).expect("temp dir should be created");
        let artifact_path = dir.join("model.gguf");
        fs::write(&artifact_path, "fixture").expect("artifact should be written");
        fs::write(
            dir.join("models_state.json"),
            format!(
                r#"{{
                  "models": [
                    {{
                      "id": "a-model",
                      "backend": "llama.cpp",
                      "modelPath": "{}"
                    }},
                    {{
                      "id": "b-model",
                      "backend": "llama.cpp",
                      "modelPath": "{}"
                    }}
                  ]
                }}"#,
                artifact_path.display(),
                artifact_path.display()
            ),
        )
        .expect("models_state should be written");
        write_runtime_status(&dir, "llama.cpp", true, &["text_generate"]);

        let rows = local_model_inventory_rows(&dir);

        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0].model_id, "a-model");
        assert_eq!(rows[0].duplicate_artifact_of, "");
        assert_eq!(rows[1].model_id, "b-model");
        assert_eq!(rows[1].duplicate_artifact_of, "a-model");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn local_inventory_reports_capability_mismatch() {
        let dir = unique_temp_dir("xhub-local-inventory-capability");
        fs::create_dir_all(&dir).expect("temp dir should be created");
        let artifact_path = dir.join("model.gguf");
        fs::write(&artifact_path, "fixture").expect("artifact should be written");
        fs::write(
            dir.join("models_state.json"),
            format!(
                r#"{{
                  "models": [
                    {{
                      "id": "vision-model",
                      "backend": "llama.cpp",
                      "modelPath": "{}",
                      "capabilities": ["vision_ocr"]
                    }}
                  ]
                }}"#,
                artifact_path.display()
            ),
        )
        .expect("models_state should be written");
        write_runtime_status(&dir, "llama.cpp", true, &["text_generate"]);

        let rows = local_model_inventory_rows(&dir);

        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].availability_state, "blocked");
        assert_eq!(
            rows[0].blocking_reason_code,
            "capability_mismatch:vision.ocr"
        );
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn local_inventory_uses_moved_artifact_path_when_present() {
        let dir = unique_temp_dir("xhub-local-inventory-moved");
        fs::create_dir_all(&dir).expect("temp dir should be created");
        let moved_path = dir.join("moved.gguf");
        fs::write(&moved_path, "fixture").expect("artifact should be written");
        fs::write(
            dir.join("models_state.json"),
            format!(
                r#"{{
                  "models": [
                    {{
                      "id": "moved-model",
                      "backend": "llama.cpp",
                      "modelPath": "{}",
                      "movedToArtifactPath": "{}"
                    }}
                  ]
                }}"#,
                dir.join("old.gguf").display(),
                moved_path.display()
            ),
        )
        .expect("models_state should be written");
        write_runtime_status(&dir, "llama.cpp", true, &["text_generate"]);

        let rows = local_model_inventory_rows(&dir);

        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].artifact_path, moved_path.display().to_string());
        assert_eq!(rows[0].availability_state, "ready");
        let _ = fs::remove_dir_all(&dir);
    }

    fn write_runtime_status(dir: &Path, provider: &str, ok: bool, capabilities: &[&str]) {
        let capability_json = capabilities
            .iter()
            .map(|capability| format!("\"{capability}\""))
            .collect::<Vec<String>>()
            .join(",");
        fs::write(
            dir.join("ai_runtime_status.json"),
            format!(
                r#"{{
                  "providers": {{
                    "{}": {{
                      "provider": "{}",
                      "ok": {},
                      "availableTaskKinds": [{}],
                      "runtimeSource": "fixture",
                      "runtimeSourcePath": "/tmp/fixture-runtime",
                      "runtimeResolutionState": "resolved",
                      "updatedAtMs": 1000
                    }}
                  }}
                }}"#,
                provider, provider, ok, capability_json
            ),
        )
        .expect("runtime status should be written");
    }

    fn unique_temp_dir(prefix: &str) -> std::path::PathBuf {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system time should be valid")
            .as_nanos();
        std::env::temp_dir().join(format!("{prefix}-{}-{stamp}", std::process::id()))
    }
}
