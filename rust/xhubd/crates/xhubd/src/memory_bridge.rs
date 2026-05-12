use std::collections::BTreeMap;
use std::env;
use std::path::PathBuf;

use serde_json::{json, Value};
use xhub_core::HubConfig;
use xhub_memory::{
    readiness_from_snapshot, retrieve_memory, retrieve_memory_from_snapshot, scan_memory_snapshot,
    MemoryIndexSnapshot, MemoryMode, MemoryRetrievalRequest, MEMORY_RETRIEVAL_RESULT_SCHEMA,
    RUST_MEMORY_SHADOW_SOURCE,
};

const SCHEMA_VERSION: &str = "xhub.memory_bridge.v1";

pub fn run(config: &HubConfig, args: &[String]) -> Result<(), String> {
    let body = dispatch(config, args)?;
    println!("{body}");
    Ok(())
}

fn dispatch(config: &HubConfig, args: &[String]) -> Result<String, String> {
    let command = args.first().map(|value| value.as_str()).unwrap_or("help");
    if matches!(command, "help" | "-h" | "--help") {
        return Ok(help_json());
    }
    match command {
        "retrieve" | "search" => retrieve_json(config, FlagArgs::parse(&args[1..])?),
        "readiness" | "status" => readiness_json(config, FlagArgs::parse(&args[1..])?),
        other => Err(format!("unknown memory command: {other}")),
    }
}

fn retrieve_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let memory_dir = flags
        .optional("memory-dir")
        .map(PathBuf::from)
        .unwrap_or_else(|| memory_dir_from_env(config));
    let mut request = MemoryRetrievalRequest::with_defaults(memory_dir);
    request.request_id = flags.optional("request-id").unwrap_or_default();
    request.scope = flags
        .optional("scope")
        .unwrap_or_else(|| "current_project".to_string());
    request.mode = MemoryMode::from_str(
        flags
            .optional("mode")
            .unwrap_or_else(|| "project_code".to_string())
            .as_str(),
    );
    request.project_id = flags.optional("project-id").unwrap_or_default();
    request.query = flags.optional("query").unwrap_or_default();
    request.latest_user = flags.optional("latest-user").unwrap_or_default();
    request.retrieval_kind = flags
        .optional("retrieval-kind")
        .unwrap_or_else(|| "search".to_string());
    request.max_results = flags.optional_usize("max-results")?.unwrap_or(5);
    request.max_snippet_chars = flags.optional_usize("max-snippet-chars")?.unwrap_or(480);
    request.requested_kinds = flags.optional_list("requested-kinds");
    request.explicit_refs = flags.optional_list("explicit-refs");
    request.audit_ref = flags.optional("audit-ref").unwrap_or_default();
    retrieve_json_from_request(request)
}

pub fn retrieve_json_from_request(request: MemoryRetrievalRequest) -> Result<String, String> {
    let out = retrieve_memory(request);
    serde_json::to_string(&out).map_err(|err| format!("memory retrieve serialize failed: {err}"))
}

pub fn retrieve_json_from_request_with_snapshot(
    request: MemoryRetrievalRequest,
    snapshot: &MemoryIndexSnapshot,
) -> Result<String, String> {
    let out = retrieve_memory_from_snapshot(request, snapshot);
    serde_json::to_string(&out).map_err(|err| format!("memory retrieve serialize failed: {err}"))
}

pub fn retrieve_request_from_value(config: &HubConfig, body: &Value) -> MemoryRetrievalRequest {
    let memory_dir = value_string(&body, "memory_dir")
        .or_else(|| value_string(&body, "memoryDir"))
        .map(PathBuf::from)
        .unwrap_or_else(|| memory_dir_from_env(config));
    let mut request = MemoryRetrievalRequest::with_defaults(memory_dir);
    request.request_id = value_string(&body, "request_id")
        .or_else(|| value_string(&body, "requestId"))
        .unwrap_or_default();
    request.scope = value_string(&body, "scope").unwrap_or_else(|| "current_project".to_string());
    request.mode = MemoryMode::from_str(
        value_string(&body, "mode")
            .unwrap_or_else(|| "project_code".to_string())
            .as_str(),
    );
    request.project_id = value_string(&body, "project_id")
        .or_else(|| value_string(&body, "projectId"))
        .unwrap_or_default();
    request.query = value_string(&body, "query").unwrap_or_default();
    request.latest_user = value_string(&body, "latest_user")
        .or_else(|| value_string(&body, "latestUser"))
        .unwrap_or_default();
    request.retrieval_kind = value_string(&body, "retrieval_kind")
        .or_else(|| value_string(&body, "retrievalKind"))
        .unwrap_or_else(|| "search".to_string());
    request.max_results = value_usize(&body, "max_results")
        .or_else(|| value_usize(&body, "maxResults"))
        .unwrap_or(5);
    request.max_snippet_chars = value_usize(&body, "max_snippet_chars")
        .or_else(|| value_usize(&body, "maxSnippetChars"))
        .unwrap_or(480);
    request.requested_kinds = value_string_list(&body, "requested_kinds")
        .or_else(|| value_string_list(&body, "requestedKinds"))
        .unwrap_or_default();
    request.explicit_refs = value_string_list(&body, "explicit_refs")
        .or_else(|| value_string_list(&body, "explicitRefs"))
        .unwrap_or_default();
    request.audit_ref = value_string(&body, "audit_ref")
        .or_else(|| value_string(&body, "auditRef"))
        .unwrap_or_default();
    request
}

fn readiness_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let memory_dir = flags
        .optional("memory-dir")
        .map(PathBuf::from)
        .unwrap_or_else(|| memory_dir_from_env(config));
    readiness_json_from_dir(memory_dir)
}

pub fn readiness_json_from_dir(memory_dir: PathBuf) -> Result<String, String> {
    let snapshot = scan_memory_snapshot(&memory_dir);
    readiness_json_from_snapshot(&snapshot)
}

pub fn readiness_json_from_snapshot(snapshot: &MemoryIndexSnapshot) -> Result<String, String> {
    let status = readiness_from_snapshot(snapshot);
    Ok(json!({
        "schema_version": SCHEMA_VERSION,
        "ok": true,
        "command": "readiness",
        "readiness": status,
    })
    .to_string())
}

pub fn snapshot_from_dir(memory_dir: PathBuf) -> MemoryIndexSnapshot {
    scan_memory_snapshot(&memory_dir)
}

pub fn help_json() -> String {
    json!({
        "schema_version": SCHEMA_VERSION,
        "ok": true,
        "commands": ["retrieve", "search", "readiness"],
        "retrieval_result_schema": MEMORY_RETRIEVAL_RESULT_SCHEMA,
        "source": RUST_MEMORY_SHADOW_SOURCE,
        "authority": "shadow_read_only",
        "writer_authority_in_rust": false,
        "retrieve_flags": [
            "--memory-dir",
            "--query",
            "--latest-user",
            "--scope",
            "--mode",
            "--retrieval-kind",
            "--explicit-refs",
            "--requested-kinds",
            "--max-results",
            "--max-snippet-chars"
        ]
    })
    .to_string()
}

pub fn memory_dir_from_env(config: &HubConfig) -> PathBuf {
    env::var("XHUB_RUST_MEMORY_DIR")
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| config.root_dir.join("data").join("memory"))
}

fn value_string(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn value_usize(value: &Value, key: &str) -> Option<usize> {
    value
        .get(key)
        .and_then(Value::as_u64)
        .and_then(|value| usize::try_from(value).ok())
}

fn value_string_list(value: &Value, key: &str) -> Option<Vec<String>> {
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

fn split_list(input: &str) -> Vec<String> {
    input
        .split(',')
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .collect()
}

#[derive(Debug, Clone, Default)]
struct FlagArgs {
    values: BTreeMap<String, String>,
}

impl FlagArgs {
    fn parse(args: &[String]) -> Result<Self, String> {
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

    fn optional(&self, key: &str) -> Option<String> {
        self.values
            .get(key)
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
    }

    fn optional_usize(&self, key: &str) -> Result<Option<usize>, String> {
        match self.optional(key) {
            Some(value) => value
                .parse::<usize>()
                .map(Some)
                .map_err(|_| format!("invalid --{key}: {value}")),
            None => Ok(None),
        }
    }

    fn optional_list(&self, key: &str) -> Vec<String> {
        self.optional(key)
            .map(|value| split_list(&value))
            .unwrap_or_default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn temp_dir(label: &str) -> PathBuf {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        std::env::temp_dir().join(format!(
            "xhubd_memory_bridge_{label}_{}_{}",
            std::process::id(),
            now
        ))
    }

    #[test]
    fn retrieve_json_returns_xt_result_shape() {
        let dir = temp_dir("retrieve");
        fs::create_dir_all(&dir).expect("mkdir");
        fs::write(
            dir.join("project_memory.md"),
            "Governed retrieval should stay explainable and slot based.",
        )
        .expect("write");
        let mut request = MemoryRetrievalRequest::with_defaults(dir.clone());
        request.request_id = "mem-1".to_string();
        request.query = "governed retrieval".to_string();
        let raw = retrieve_json_from_request(request).expect("retrieve");
        let value: Value = serde_json::from_str(&raw).expect("json");
        assert_eq!(value["schema_version"], "xt.memory_retrieval_result.v1");
        assert_eq!(value["source"], "rust_hub_memory_shadow_v1");
        assert_eq!(value["request_id"], "mem-1");
        assert!(value["results"].as_array().unwrap().len() >= 1);
        let _ = fs::remove_dir_all(dir);
    }
}
