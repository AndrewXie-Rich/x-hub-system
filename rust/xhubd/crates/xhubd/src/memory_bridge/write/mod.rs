use std::path::PathBuf;

use serde_json::Value;
use xhub_core::HubConfig;
use xhub_memory::{write_memory_entry, MemoryMode, MemoryWriteRequest};

use super::shared::{
    memory_dir_from_env, memory_writer_authority_enabled, value_string, value_string_list, FlagArgs,
};

pub(crate) mod candidate;
pub(crate) mod canonical;
pub(crate) mod object;

pub(crate) fn write_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let memory_dir = flags
        .optional("memory-dir")
        .map(PathBuf::from)
        .unwrap_or_else(|| memory_dir_from_env(config));
    let mut request = MemoryWriteRequest::with_defaults(memory_dir);
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
    request.source_kind = flags
        .optional("source-kind")
        .unwrap_or_else(|| "project_capsule".to_string());
    request.title = flags.optional("title").unwrap_or_default();
    request.text = flags.optional("text").unwrap_or_default();
    request.tags = flags.optional_list("tags");
    request.audit_ref = flags.optional("audit-ref").unwrap_or_default();
    request.actor = flags
        .optional("actor")
        .unwrap_or_else(|| "rust_hub_operator".to_string());
    write_json_from_request(request)
}

pub fn write_json_from_value(config: &HubConfig, body: &Value) -> Result<String, String> {
    let memory_dir = value_string(&body, "memory_dir")
        .or_else(|| value_string(&body, "memoryDir"))
        .map(PathBuf::from)
        .unwrap_or_else(|| memory_dir_from_env(config));
    let mut request = MemoryWriteRequest::with_defaults(memory_dir);
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
    request.source_kind = value_string(&body, "source_kind")
        .or_else(|| value_string(&body, "sourceKind"))
        .unwrap_or_else(|| "project_capsule".to_string());
    request.title = value_string(&body, "title").unwrap_or_default();
    request.text = value_string(&body, "text")
        .or_else(|| value_string(&body, "content"))
        .unwrap_or_default();
    request.tags = value_string_list(&body, "tags").unwrap_or_default();
    request.audit_ref = value_string(&body, "audit_ref")
        .or_else(|| value_string(&body, "auditRef"))
        .unwrap_or_default();
    request.actor = value_string(&body, "actor").unwrap_or_else(|| "rust_hub".to_string());
    write_json_from_request(request)
}

pub fn write_json_from_request(request: MemoryWriteRequest) -> Result<String, String> {
    let out = write_memory_entry(request, memory_writer_authority_enabled());
    serde_json::to_string(&out).map_err(|err| format!("memory write serialize failed: {err}"))
}
