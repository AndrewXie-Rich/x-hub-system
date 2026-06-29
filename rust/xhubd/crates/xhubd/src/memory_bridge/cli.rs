use std::fmt::Write as _;
use std::path::PathBuf;

use serde_json::{json, Value};
use xhub_core::HubConfig;
use xhub_db::{
    apply_baseline_migrations, read_memory_object_index_summary, rebuild_memory_object_index,
};
use xhub_memory::{
    MemoryMode, MemoryRetrievalRequest, MEMORY_RETRIEVAL_RESULT_SCHEMA, MEMORY_WRITE_RESULT_SCHEMA,
    RUST_MEMORY_SHADOW_SOURCE,
};

use super::gate::evaluate_memory_policy_json;
use super::projection::memory_gateway_prepare_json_from_value;
use super::read::retrieve_json_from_request_with_config;
use super::shared::{
    memory_dir_from_env, memory_writer_authority_enabled, FlagArgs, HttpJsonError,
    MEMORY_GATEWAY_PREPARE_SCHEMA, MEMORY_OBJECT_RESULT_SCHEMA, MEMORY_OBJECT_SCHEMA,
    MEMORY_POLICY_RESULT_SCHEMA, MEMORY_WRITEBACK_CANDIDATE_EXTRACT_SCHEMA,
    MEMORY_WRITEBACK_CANDIDATE_SCHEMA, SCHEMA_VERSION,
};
use super::snapshot::{
    memory_object_index_rebuild_report_to_json, memory_object_index_summary_to_json, readiness_json,
};
use super::write::candidate::{
    create_writeback_candidate_json_from_body, list_writeback_candidates_json,
    transition_memory_object_candidate_json, writeback_candidate_extract_json_from_value,
};
use super::write::canonical::project_canonical_sync_json_from_value;
use super::write::object::{
    create_memory_object_json_from_body, get_memory_object_json, list_memory_objects_json,
    memory_object_history_json,
};
use super::write::write_json;

pub fn run(config: &HubConfig, args: &[String]) -> Result<(), String> {
    let body = dispatch(config, args)?;
    println!("{body}");
    Ok(())
}

pub(super) fn dispatch(config: &HubConfig, args: &[String]) -> Result<String, String> {
    let command = args.first().map(|value| value.as_str()).unwrap_or("help");
    if matches!(command, "help" | "-h" | "--help") {
        return Ok(help_json());
    }
    match command {
        "retrieve" | "search" => retrieve_json(config, FlagArgs::parse(&args[1..])?),
        "write" | "append" => write_json(config, FlagArgs::parse(&args[1..])?),
        "object-create" | "objects-create" | "create-object" => {
            object_create_cli_json(config, FlagArgs::parse(&args[1..])?)
        }
        "object-list" | "objects-list" | "list-objects" => {
            object_list_cli_json(config, FlagArgs::parse(&args[1..])?)
        }
        "object-get" | "get-object" => object_get_cli_json(config, FlagArgs::parse(&args[1..])?),
        "object-history" | "history" => {
            object_history_cli_json(config, FlagArgs::parse(&args[1..])?)
        }
        "candidate-create" | "writeback-candidate-create" => {
            writeback_candidate_create_cli_json(config, FlagArgs::parse(&args[1..])?)
        }
        "candidate-extract" | "writeback-candidate-extract" | "extract-candidates" => {
            writeback_candidate_extract_cli_json(config, FlagArgs::parse(&args[1..])?)
        }
        "candidate-list" | "writeback-candidate-list" => {
            writeback_candidate_list_cli_json(config, FlagArgs::parse(&args[1..])?)
        }
        "candidate-approve" | "writeback-candidate-approve" => {
            writeback_candidate_transition_cli_json(config, FlagArgs::parse(&args[1..])?, "approve")
        }
        "candidate-reject" | "writeback-candidate-reject" => {
            writeback_candidate_transition_cli_json(config, FlagArgs::parse(&args[1..])?, "reject")
        }
        "object-index-rebuild" | "objects-index-rebuild" | "reindex" => {
            object_index_rebuild_cli_json(config)
        }
        "policy" | "policy-evaluate" | "evaluate-policy" => {
            policy_evaluate_cli_json(FlagArgs::parse(&args[1..])?)
        }
        "project-canonical-sync" | "canonical-sync" => {
            project_canonical_sync_cli_json(config, FlagArgs::parse(&args[1..])?)
        }
        "gateway-prepare" | "context" | "prepare-context" => {
            gateway_prepare_cli_json(config, FlagArgs::parse(&args[1..])?)
        }
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
    request.requested_layers = flags.optional_list("requested-layers");
    request.explicit_refs = flags.optional_list("explicit-refs");
    request.sensitivity_max = flags.optional("sensitivity-max").unwrap_or_default();
    request.visibility = flags.optional("visibility").unwrap_or_default();
    request.created_after_ms = flags.optional_i64("created-after-ms")?.unwrap_or(0);
    request.updated_after_ms = flags.optional_i64("updated-after-ms")?.unwrap_or(0);
    request.explain = flags.optional_bool("explain").unwrap_or(false);
    request.audit_ref = flags.optional("audit-ref").unwrap_or_default();
    retrieve_json_from_request_with_config(config, request)
}

fn object_create_cli_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let mut body = serde_json::Map::new();
    insert_string_flag(&mut body, &flags, "memory-id", "memory_id");
    insert_string_flag(&mut body, &flags, "requester-role", "requester_role");
    insert_string_flag(&mut body, &flags, "use-mode", "use_mode");
    insert_string_flag(&mut body, &flags, "scope", "scope");
    insert_string_flag(&mut body, &flags, "owner-id", "owner_id");
    insert_string_flag(&mut body, &flags, "project-id", "project_id");
    insert_string_flag(&mut body, &flags, "run-id", "run_id");
    insert_string_flag(&mut body, &flags, "agent-id", "agent_id");
    insert_string_flag(&mut body, &flags, "source-kind", "source_kind");
    insert_string_flag(&mut body, &flags, "layer", "layer");
    insert_string_flag(&mut body, &flags, "title", "title");
    insert_string_flag(&mut body, &flags, "text", "text");
    insert_string_flag(&mut body, &flags, "summary", "summary");
    insert_string_flag(&mut body, &flags, "sensitivity", "sensitivity");
    insert_string_flag(&mut body, &flags, "visibility", "visibility");
    insert_string_flag(&mut body, &flags, "status", "status");
    insert_string_flag(&mut body, &flags, "audit-ref", "audit_ref");
    insert_string_flag(&mut body, &flags, "actor", "actor");
    insert_string_flag(&mut body, &flags, "reason", "reason");
    insert_string_flag(&mut body, &flags, "source", "source");
    insert_list_flag(&mut body, &flags, "tags", "tags");
    insert_list_flag(&mut body, &flags, "evidence-refs", "evidence_refs");
    insert_bool_flag(&mut body, &flags, "pinned", "pinned");
    insert_bool_flag(&mut body, &flags, "immutable", "immutable");
    if let Some(ttl_ms) = flags.optional_i64("ttl-ms")? {
        body.insert("ttl_ms".to_string(), json!(ttl_ms));
    }
    Ok(cli_http_body(create_memory_object_json_from_body(
        config,
        &Value::Object(body).to_string(),
    )))
}

fn object_list_cli_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let query = query_from_flag_pairs(
        &flags,
        &[
            ("scope", "scope"),
            ("owner-id", "owner_id"),
            ("project-id", "project_id"),
            ("agent-id", "agent_id"),
            ("source-kind", "source_kind"),
            ("layer", "layer"),
            ("status", "status"),
            ("sensitivity", "sensitivity"),
            ("visibility", "visibility"),
            ("limit", "limit"),
        ],
    );
    Ok(cli_http_body(list_memory_objects_json(config, &query)))
}

fn object_get_cli_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let memory_id = flags
        .optional("memory-id")
        .ok_or_else(|| "--memory-id is required".to_string())?;
    Ok(cli_http_body(get_memory_object_json(config, &memory_id)))
}

fn object_history_cli_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let memory_id = flags
        .optional("memory-id")
        .ok_or_else(|| "--memory-id is required".to_string())?;
    let query = query_from_flag_pairs(&flags, &[("limit", "limit")]);
    Ok(cli_http_body(memory_object_history_json(
        config, &memory_id, &query,
    )))
}

fn writeback_candidate_create_cli_json(
    config: &HubConfig,
    flags: FlagArgs,
) -> Result<String, String> {
    let mut body = serde_json::Map::new();
    insert_string_flag(&mut body, &flags, "memory-id", "memory_id");
    insert_string_flag(&mut body, &flags, "requester-role", "requester_role");
    insert_string_flag(&mut body, &flags, "use-mode", "use_mode");
    insert_string_flag(&mut body, &flags, "scope", "scope");
    insert_string_flag(&mut body, &flags, "owner-id", "owner_id");
    insert_string_flag(&mut body, &flags, "project-id", "project_id");
    insert_string_flag(&mut body, &flags, "run-id", "run_id");
    insert_string_flag(&mut body, &flags, "agent-id", "agent_id");
    insert_string_flag(&mut body, &flags, "source-kind", "source_kind");
    insert_string_flag(&mut body, &flags, "layer", "layer");
    insert_string_flag(&mut body, &flags, "title", "title");
    insert_string_flag(&mut body, &flags, "text", "text");
    insert_string_flag(&mut body, &flags, "summary", "summary");
    insert_string_flag(&mut body, &flags, "sensitivity", "sensitivity");
    insert_string_flag(&mut body, &flags, "visibility", "visibility");
    insert_string_flag(&mut body, &flags, "audit-ref", "audit_ref");
    insert_string_flag(&mut body, &flags, "actor", "actor");
    insert_string_flag(&mut body, &flags, "reason", "reason");
    insert_string_flag(&mut body, &flags, "source", "source");
    insert_list_flag(&mut body, &flags, "tags", "tags");
    insert_list_flag(&mut body, &flags, "evidence-refs", "evidence_refs");
    insert_bool_flag(&mut body, &flags, "pinned", "pinned");
    if let Some(ttl_ms) = flags.optional_i64("ttl-ms")? {
        body.insert("ttl_ms".to_string(), json!(ttl_ms));
    }
    Ok(cli_http_body(create_writeback_candidate_json_from_body(
        config,
        &Value::Object(body).to_string(),
    )))
}

fn writeback_candidate_extract_cli_json(
    config: &HubConfig,
    flags: FlagArgs,
) -> Result<String, String> {
    let payload = flags
        .optional("payload-json")
        .ok_or_else(|| "--payload-json is required".to_string())?;
    let parsed = serde_json::from_str::<Value>(&payload)
        .map_err(|err| format!("invalid --payload-json: {err}"))?;
    let dry_run = flags.optional_bool("dry-run").unwrap_or(false);
    Ok(cli_http_body(writeback_candidate_extract_json_from_value(
        config, &parsed, !dry_run,
    )))
}

fn writeback_candidate_list_cli_json(
    config: &HubConfig,
    flags: FlagArgs,
) -> Result<String, String> {
    let query = query_from_flag_pairs(
        &flags,
        &[
            ("scope", "scope"),
            ("owner-id", "owner_id"),
            ("project-id", "project_id"),
            ("agent-id", "agent_id"),
            ("source-kind", "source_kind"),
            ("layer", "layer"),
            ("sensitivity", "sensitivity"),
            ("visibility", "visibility"),
            ("limit", "limit"),
        ],
    );
    Ok(cli_http_body(list_writeback_candidates_json(
        config, &query,
    )))
}

fn writeback_candidate_transition_cli_json(
    config: &HubConfig,
    flags: FlagArgs,
    action: &str,
) -> Result<String, String> {
    let memory_id = flags
        .optional("memory-id")
        .ok_or_else(|| "--memory-id is required".to_string())?;
    let mut body = serde_json::Map::new();
    insert_string_flag(&mut body, &flags, "requester-role", "requester_role");
    insert_string_flag(&mut body, &flags, "use-mode", "use_mode");
    insert_string_flag(&mut body, &flags, "actor", "actor");
    insert_string_flag(&mut body, &flags, "audit-ref", "audit_ref");
    insert_string_flag(&mut body, &flags, "reason", "reason");
    Ok(cli_http_body(transition_memory_object_candidate_json(
        config,
        &memory_id,
        action,
        &Value::Object(body).to_string(),
    )))
}

pub(super) fn object_index_rebuild_cli_json(config: &HubConfig) -> Result<String, String> {
    apply_baseline_migrations(&config.db_path)
        .map_err(|err| format!("memory object index migration failed: {err}"))?;
    let report = rebuild_memory_object_index(&config.db_path)
        .map_err(|err| format!("memory object index rebuild failed: {err}"))?;
    let summary = read_memory_object_index_summary(&config.db_path)
        .map_err(|err| format!("memory object index summary failed: {err}"))?;
    Ok(json!({
        "schema_version": "xhub.memory.object_index_rebuild.v1",
        "ok": true,
        "command": "object-index-rebuild",
        "status": "ok",
        "report": memory_object_index_rebuild_report_to_json(&report),
        "index": memory_object_index_summary_to_json(&summary),
        "production_authority_change": false,
    })
    .to_string())
}

fn policy_evaluate_cli_json(flags: FlagArgs) -> Result<String, String> {
    let mut body = serde_json::Map::new();
    insert_string_flag(&mut body, &flags, "requester-role", "requester_role");
    insert_string_flag(&mut body, &flags, "use-mode", "use_mode");
    insert_string_flag(&mut body, &flags, "scope", "scope");
    insert_bool_flag(
        &mut body,
        &flags,
        "remote-export-requested",
        "remote_export_requested",
    );
    insert_list_flag(&mut body, &flags, "requested-layers", "requested_layers");
    insert_list_flag(
        &mut body,
        &flags,
        "requested-source-kinds",
        "requested_source_kinds",
    );
    Ok(evaluate_memory_policy_json(&Value::Object(body)))
}

fn project_canonical_sync_cli_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let payload = flags
        .optional("payload-json")
        .ok_or_else(|| "--payload-json is required".to_string())?;
    let parsed = serde_json::from_str::<Value>(&payload)
        .map_err(|err| format!("invalid --payload-json: {err}"))?;
    let apply = flags.optional_bool("apply").unwrap_or(false);
    Ok(cli_http_body(project_canonical_sync_json_from_value(
        config, &parsed, apply,
    )))
}

fn gateway_prepare_cli_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let mut body = serde_json::Map::new();
    insert_string_flag(&mut body, &flags, "requester-role", "requester_role");
    insert_string_flag(&mut body, &flags, "use-mode", "use_mode");
    insert_string_flag(&mut body, &flags, "scope", "scope");
    insert_string_flag(&mut body, &flags, "project-id", "project_id");
    insert_string_flag(&mut body, &flags, "agent-id", "agent_id");
    insert_string_flag(&mut body, &flags, "latest-user", "latest_user");
    insert_string_flag(&mut body, &flags, "query", "query");
    insert_bool_flag(
        &mut body,
        &flags,
        "remote-export-requested",
        "remote_export_requested",
    );
    insert_list_flag(&mut body, &flags, "requested-layers", "requested_layers");
    insert_list_flag(
        &mut body,
        &flags,
        "requested-source-kinds",
        "requested_source_kinds",
    );
    if let Some(value) = flags.optional_usize("max-items")? {
        body.insert("max_items".to_string(), json!(value));
    }
    if let Some(value) = flags.optional_usize("max-snippet-chars")? {
        body.insert("max_snippet_chars".to_string(), json!(value));
    }
    Ok(cli_http_body(memory_gateway_prepare_json_from_value(
        config,
        &Value::Object(body),
    )))
}

fn cli_http_body(result: Result<String, HttpJsonError>) -> String {
    match result {
        Ok(body) => body,
        Err(err) => err.body,
    }
}

fn insert_string_flag(
    body: &mut serde_json::Map<String, Value>,
    flags: &FlagArgs,
    flag_key: &str,
    json_key: &str,
) {
    if let Some(value) = flags.optional(flag_key) {
        body.insert(json_key.to_string(), json!(value));
    }
}

fn insert_list_flag(
    body: &mut serde_json::Map<String, Value>,
    flags: &FlagArgs,
    flag_key: &str,
    json_key: &str,
) {
    let values = flags.optional_list(flag_key);
    if !values.is_empty() {
        body.insert(json_key.to_string(), json!(values));
    }
}

fn insert_bool_flag(
    body: &mut serde_json::Map<String, Value>,
    flags: &FlagArgs,
    flag_key: &str,
    json_key: &str,
) {
    if let Some(value) = flags.optional_bool(flag_key) {
        body.insert(json_key.to_string(), json!(value));
    }
}

fn query_from_flag_pairs(flags: &FlagArgs, pairs: &[(&str, &str)]) -> String {
    pairs
        .iter()
        .filter_map(|(flag_key, query_key)| {
            flags.optional(flag_key).map(|value| {
                format!(
                    "{}={}",
                    percent_encode_query_component(query_key),
                    percent_encode_query_component(&value)
                )
            })
        })
        .collect::<Vec<_>>()
        .join("&")
}

fn percent_encode_query_component(input: &str) -> String {
    let mut out = String::new();
    for byte in input.bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b'~') {
            out.push(byte as char);
        } else {
            let _ = write!(&mut out, "%{byte:02X}");
        }
    }
    out
}

pub fn help_json() -> String {
    json!({
        "schema_version": SCHEMA_VERSION,
        "ok": true,
        "commands": [
            "retrieve",
            "search",
            "write",
            "object-create",
            "object-list",
            "object-get",
            "object-history",
            "candidate-create",
            "candidate-extract",
            "candidate-list",
            "candidate-approve",
            "candidate-reject",
            "object-index-rebuild",
            "policy-evaluate",
            "project-canonical-sync",
            "gateway-prepare",
            "readiness"
        ],
        "retrieval_result_schema": MEMORY_RETRIEVAL_RESULT_SCHEMA,
        "write_result_schema": MEMORY_WRITE_RESULT_SCHEMA,
        "memory_object_schema": MEMORY_OBJECT_SCHEMA,
        "memory_object_result_schema": MEMORY_OBJECT_RESULT_SCHEMA,
        "memory_policy_result_schema": MEMORY_POLICY_RESULT_SCHEMA,
        "memory_gateway_prepare_schema": MEMORY_GATEWAY_PREPARE_SCHEMA,
        "memory_writeback_candidate_schema": MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
        "memory_writeback_candidate_extract_schema": MEMORY_WRITEBACK_CANDIDATE_EXTRACT_SCHEMA,
        "source": RUST_MEMORY_SHADOW_SOURCE,
        "authority": if memory_writer_authority_enabled() { "canonical_writer" } else { "shadow_read_only" },
        "writer_authority_in_rust": memory_writer_authority_enabled(),
        "retrieve_flags": [
            "--memory-dir",
            "--query",
            "--latest-user",
            "--scope",
            "--mode",
            "--retrieval-kind",
            "--explicit-refs",
            "--requested-kinds",
            "--requested-layers",
            "--sensitivity-max",
            "--visibility",
            "--created-after-ms",
            "--updated-after-ms",
            "--explain",
            "--max-results",
            "--max-snippet-chars"
        ],
        "write_flags": [
            "--memory-dir",
            "--title",
            "--text",
            "--scope",
            "--mode",
            "--source-kind",
            "--tags",
            "--request-id",
            "--audit-ref",
            "--actor"
        ],
        "object_create_flags": [
            "--memory-id",
            "--requester-role",
            "--use-mode",
            "--scope",
            "--owner-id",
            "--project-id",
            "--source-kind",
            "--layer",
            "--title",
            "--text",
            "--tags",
            "--sensitivity",
            "--visibility",
            "--audit-ref",
            "--actor"
        ],
        "object_list_flags": [
            "--scope",
            "--owner-id",
            "--project-id",
            "--agent-id",
            "--source-kind",
            "--layer",
            "--status",
            "--sensitivity",
            "--visibility",
            "--limit"
        ],
        "writeback_candidates_http": {
            "endpoint": "POST|GET /memory/writeback/candidates",
            "extract": "POST /memory/writeback/candidates/extract",
            "approve": "POST /memory/writeback/candidates/{memory_id}/approve",
            "reject": "POST /memory/writeback/candidates/{memory_id}/reject",
            "object_aliases": ["POST /memory/objects/{memory_id}/approve", "POST /memory/objects/{memory_id}/reject"],
            "default_status": "candidate",
            "approval_status": "active",
            "rejection_status": "rejected",
            "authority": "rust_policy_gated_candidate_queue"
        },
        "writeback_candidate_flags": [
            "--memory-id",
            "--requester-role",
            "--use-mode",
            "--scope",
            "--owner-id",
            "--project-id",
            "--source-kind",
            "--layer",
            "--title",
            "--text",
            "--tags",
            "--sensitivity",
            "--visibility",
            "--audit-ref",
            "--actor"
        ],
        "writeback_candidate_extract_flags": [
            "--payload-json",
            "--dry-run"
        ],
        "policy_evaluate_flags": [
            "--requester-role",
            "--use-mode",
            "--scope",
            "--remote-export-requested",
            "--requested-layers",
            "--requested-source-kinds"
        ],
        "project_canonical_sync_http": {
            "endpoint": "POST /memory/project-canonical-sync",
            "apply_gate": "query parameter apply=1",
            "default": "dry_run",
            "payload": "existing XT project_canonical_memory envelope or raw project canonical memory payload"
        },
        "project_canonical_sync_cli_flags": [
            "--payload-json",
            "--apply"
        ],
        "gateway_prepare_http": {
            "endpoint": "POST /memory/gateway/prepare",
            "alias": "POST /memory/context",
            "mode": "prepare_only_no_model_call",
            "default_layers": ["l1_canonical", "l2_observations", "l3_working_set"]
        },
        "gateway_prepare_flags": [
            "--requester-role",
            "--use-mode",
            "--scope",
            "--project-id",
            "--agent-id",
            "--latest-user",
            "--requested-layers",
            "--requested-source-kinds",
            "--remote-export-requested",
            "--max-items",
            "--max-snippet-chars"
        ]
    })
    .to_string()
}
