#![allow(unused_imports)]
use super::cli::{dispatch, object_index_rebuild_cli_json};
use super::gate::*;
use super::http::*;
use super::projection::*;
use super::read::*;
use super::shared::*;
use super::snapshot::*;
use super::write::candidate::*;
use super::write::canonical::*;
use super::write::object::*;
use super::write::*;
use super::*;
use serde_json::{json, Value};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::PathBuf;
use xhub_core::HubConfig;
use xhub_db::{
    apply_baseline_migrations, create_memory_object_with_event, list_memory_object_index,
    list_memory_objects, read_memory_object, read_memory_object_history,
    read_memory_object_index_summary, read_memory_object_store_summary,
    rebuild_memory_object_index, update_memory_object_with_event, MemoryEventRecord,
    MemoryObjectIndexFilter, MemoryObjectIndexRecord, MemoryObjectIndexSummary,
    MemoryObjectListFilter, MemoryObjectRecord,
};
use xhub_memory::{
    retrieve_memory, retrieve_memory_from_snapshot, scan_memory_snapshot, write_memory_entry,
    MemoryIndexSnapshot, MemoryMode, MemoryRetrievalRequest, MemoryWriteRequest,
    MEMORY_RETRIEVAL_RESULT_SCHEMA, MEMORY_WRITE_RESULT_SCHEMA, RUST_MEMORY_SHADOW_SOURCE,
};

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

fn test_config(label: &str) -> HubConfig {
    let root = temp_dir(label);
    HubConfig {
        root_dir: root.clone(),
        host: "127.0.0.1".to_string(),
        http_port: 0,
        grpc_port: 0,
        db_path: root.join("hub.sqlite3"),
        runtime_base_dir: root.join("runtime"),
        proto_path: root.join("hub_protocol_v1.proto"),
        canonical_proto_path: root.join("hub_protocol_v1.proto"),
        http_access_key: None,
        http_access_key_source: "none".to_string(),
        http_access_key_required: false,
    }
}

fn args(values: &[&str]) -> Vec<String> {
    values.iter().map(|value| value.to_string()).collect()
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
    let raw = read::retrieve_json_from_request(request).expect("retrieve");
    let value: Value = serde_json::from_str(&raw).expect("json");
    assert_eq!(value["schema_version"], "xt.memory_retrieval_result.v1");
    assert_eq!(value["source"], "rust_hub_memory_shadow_v1");
    assert_eq!(value["request_id"], "mem-1");
    assert!(value["results"].as_array().unwrap().len() >= 1);
    let _ = fs::remove_dir_all(dir);
}

#[test]
fn memory_object_hybrid_retrieval_finds_decision_with_explain() {
    let config = test_config("object_hybrid_retrieve");
    let decision_body = json!({
            "memory_id": "mem_hybrid_decision",
            "requester_role": "chat",
            "use_mode": "project_chat",
            "scope": "project",
            "owner_id": "project-hybrid",
            "project_id": "project-hybrid",
            "source_kind": "decision_track",
            "layer": "l1_canonical",
            "title": "Memory gateway decision",
            "text": "Decision: route project model calls through the Rust memory gateway before provider selection.",
            "tags": ["memory", "decision"],
            "audit_ref": "hybrid-test",
        })
        .to_string();
    create_memory_object_json_from_body(&config, &decision_body).expect("create decision");
    let risk_body = json!({
        "memory_id": "mem_hybrid_risk",
        "requester_role": "chat",
        "use_mode": "project_chat",
        "scope": "project",
        "owner_id": "project-hybrid",
        "project_id": "project-hybrid",
        "source_kind": "risk",
        "layer": "l2_observations",
        "title": "Memory gateway risk",
        "text": "Risk: raw evidence must stay out of default model context.",
        "tags": ["memory", "risk"],
        "audit_ref": "hybrid-test",
    })
    .to_string();
    create_memory_object_json_from_body(&config, &risk_body).expect("create risk");

    let mut request = MemoryRetrievalRequest::with_defaults(config.root_dir.join("memory"));
    request.request_id = "hybrid-1".to_string();
    request.scope = "project".to_string();
    request.project_id = "project-hybrid".to_string();
    request.query = "why decision memory gateway provider".to_string();
    request.explain = true;
    let raw = retrieve_json_from_request_with_config(&config, request).expect("retrieve");
    let value: Value = serde_json::from_str(&raw).expect("json");
    assert_eq!(value["schema_version"], MEMORY_RETRIEVAL_RESULT_SCHEMA);
    assert_eq!(value["source"], MEMORY_OBJECT_RETRIEVAL_SOURCE);
    assert_eq!(value["production_authority_change"], false);
    assert_eq!(value["retrieval_engine"]["semantic_used"], false);
    assert_eq!(
        value["retrieval_engine"]["stage"],
        "uml_w6_persistent_derived_index_bm25_slice"
    );
    assert_eq!(
        value["retrieval_engine"]["index_source"],
        "rust_hub_memory_object_index"
    );
    assert_eq!(value["retrieval_engine"]["index_rebuilt"], true);
    assert_eq!(value["retrieval_engine"]["stale_index_count"], 0);
    assert_eq!(value["retrieval_engine"]["bm25_used"], true);
    assert_eq!(value["retrieval_engine"]["fts"], "derived_index_bm25_rust");
    let results = value["results"].as_array().expect("results");
    assert_eq!(results[0]["memory_id"], "mem_hybrid_decision");
    assert_eq!(results[0]["layer"], "l1_canonical");
    assert_eq!(
        results[0]["explain"]["policy_filter"],
        "project_active_non_secret"
    );
    assert_eq!(results[0]["explain"]["properties"]["has_decision"], true);
    assert!(results[0]["explain"]["bm25_score"].as_f64().unwrap() > 0.0);
    assert_eq!(
        value["retrieval_trace"]["schema_version"],
        "xhub.memory.retrieval_trace.v1"
    );
    assert_eq!(
        value["retrieval_trace"]["selected"][0]["memory_id"],
        "mem_hybrid_decision"
    );
    assert_eq!(
        value["retrieval_trace"]["selected"][0]["reason_code"],
        "selected"
    );

    let _ = fs::remove_dir_all(config.root_dir);
}

#[test]
fn memory_object_reindex_command_recovers_derived_index() {
    let config = test_config("object_reindex_command");
    let body = json!({
        "memory_id": "mem_reindex_decision",
        "requester_role": "chat",
        "use_mode": "project_chat",
        "scope": "project",
        "owner_id": "project-reindex",
        "project_id": "project-reindex",
        "source_kind": "decision_track",
        "layer": "l1_canonical",
        "title": "Reindex decision",
        "text": "Decision: rebuild the derived Rust memory index from canonical memory objects.",
        "audit_ref": "reindex-test",
    })
    .to_string();
    create_memory_object_json_from_body(&config, &body).expect("create object");

    let raw = object_index_rebuild_cli_json(&config).expect("reindex");
    let value: Value = serde_json::from_str(&raw).expect("json");
    assert_eq!(value["ok"], true);
    assert_eq!(value["production_authority_change"], false);
    assert_eq!(value["report"]["indexed_count"], 1);
    assert_eq!(value["index"]["row_count"], 1);
    assert_eq!(value["index"]["stale_count"], 0);

    let mut request = MemoryRetrievalRequest::with_defaults(config.root_dir.join("memory"));
    request.scope = "project".to_string();
    request.project_id = "project-reindex".to_string();
    request.query = "why rebuild derived index".to_string();
    request.explain = true;
    let raw = retrieve_json_from_request_with_config(&config, request).expect("retrieve");
    let value: Value = serde_json::from_str(&raw).expect("json");
    assert_eq!(
        value["retrieval_engine"]["index_source"],
        "rust_hub_memory_object_index"
    );
    assert_eq!(value["retrieval_engine"]["index_rebuilt"], false);
    assert_eq!(value["results"][0]["memory_id"], "mem_reindex_decision");

    let _ = fs::remove_dir_all(config.root_dir);
}

#[test]
fn memory_object_hybrid_retrieval_filters_layer_and_supports_get_ref() {
    let config = test_config("object_hybrid_filters");
    for (memory_id, layer, source_kind, title, text) in [
        (
            "mem_filter_goal",
            "l1_canonical",
            "project_goal",
            "Goal",
            "Build explainable Rust memory retrieval.",
        ),
        (
            "mem_filter_next",
            "l3_working_set",
            "next_step",
            "Next step",
            "Next step: collect W6 retrieval quality evidence.",
        ),
    ] {
        let body = json!({
            "memory_id": memory_id,
            "requester_role": "chat",
            "use_mode": "project_chat",
            "scope": "project",
            "owner_id": "project-filter",
            "project_id": "project-filter",
            "source_kind": source_kind,
            "layer": layer,
            "title": title,
            "text": text,
            "audit_ref": "filter-test",
        })
        .to_string();
        create_memory_object_json_from_body(&config, &body).expect("create object");
    }

    let mut filtered = MemoryRetrievalRequest::with_defaults(config.root_dir.join("memory"));
    filtered.scope = "project".to_string();
    filtered.project_id = "project-filter".to_string();
    filtered.query = "next retrieval evidence".to_string();
    filtered.requested_layers = vec!["l3_working_set".to_string()];
    filtered.explain = true;
    let raw = retrieve_json_from_request_with_config(&config, filtered).expect("retrieve");
    let value: Value = serde_json::from_str(&raw).expect("json");
    let results = value["results"].as_array().expect("results");
    assert_eq!(results.len(), 1);
    assert_eq!(results[0]["memory_id"], "mem_filter_next");
    assert_eq!(
        value["retrieval_engine"]["filters"]["layers"]
            .as_array()
            .unwrap(),
        &vec![json!("l3_working_set")]
    );
    assert!(value["retrieval_trace"]["omitted"]
        .as_array()
        .unwrap()
        .iter()
        .any(
            |item| item["reason_code"] == "layer_filter" && item["memory_id"] == "mem_filter_goal"
        ));

    let mut get_ref = MemoryRetrievalRequest::with_defaults(config.root_dir.join("memory"));
    get_ref.scope = "project".to_string();
    get_ref.project_id = "project-filter".to_string();
    get_ref.retrieval_kind = "get_ref".to_string();
    get_ref.explicit_refs = vec!["memory://rust/object/mem_filter_goal".to_string()];
    let raw = retrieve_json_from_request_with_config(&config, get_ref).expect("get ref");
    let value: Value = serde_json::from_str(&raw).expect("json");
    let results = value["results"].as_array().expect("results");
    assert_eq!(results.len(), 1);
    assert_eq!(results[0]["memory_id"], "mem_filter_goal");

    let _ = fs::remove_dir_all(config.root_dir);
}

#[test]
fn memory_hybrid_retrieval_filters_scope() {
    let config = test_config("object_hybrid_scope");
    for (memory_id, project_id, text) in [
        (
            "mem_scope_alpha",
            "project-scope-alpha",
            "Decision: alpha project owns the domain cutover memory scope.",
        ),
        (
            "mem_scope_beta",
            "project-scope-beta",
            "Decision: beta project owns the domain cutover memory scope.",
        ),
    ] {
        let body = json!({
            "memory_id": memory_id,
            "requester_role": "chat",
            "use_mode": "project_chat",
            "scope": "project",
            "owner_id": project_id,
            "project_id": project_id,
            "source_kind": "decision_track",
            "layer": "l1_canonical",
            "title": "Scoped memory decision",
            "text": text,
            "audit_ref": "scope-filter-test",
        })
        .to_string();
        create_memory_object_json_from_body(&config, &body).expect("create scoped object");
    }

    let mut alpha = MemoryRetrievalRequest::with_defaults(config.root_dir.join("memory"));
    alpha.scope = "project".to_string();
    alpha.project_id = "project-scope-alpha".to_string();
    alpha.query = "domain cutover memory scope decision".to_string();
    alpha.explain = true;
    let raw = retrieve_json_from_request_with_config(&config, alpha).expect("retrieve alpha");
    let value: Value = serde_json::from_str(&raw).expect("alpha json");
    let results = value["results"].as_array().expect("alpha results");
    assert_eq!(
        value["retrieval_engine"]["index_source"],
        "rust_hub_memory_object_index"
    );
    assert!(results
        .iter()
        .any(|item| item["memory_id"] == "mem_scope_alpha"));
    assert!(!results
        .iter()
        .any(|item| item["memory_id"] == "mem_scope_beta"));

    let mut beta = MemoryRetrievalRequest::with_defaults(config.root_dir.join("memory"));
    beta.scope = "project".to_string();
    beta.project_id = "project-scope-beta".to_string();
    beta.query = "domain cutover memory scope decision".to_string();
    beta.explain = true;
    let raw = retrieve_json_from_request_with_config(&config, beta).expect("retrieve beta");
    let value: Value = serde_json::from_str(&raw).expect("beta json");
    let results = value["results"].as_array().expect("beta results");
    assert!(results
        .iter()
        .any(|item| item["memory_id"] == "mem_scope_beta"));
    assert!(!results
        .iter()
        .any(|item| item["memory_id"] == "mem_scope_alpha"));

    let _ = fs::remove_dir_all(config.root_dir);
}

#[test]
fn memory_hybrid_retrieval_omits_deleted() {
    let config = test_config("object_hybrid_deleted");
    for (memory_id, text) in [
        (
            "mem_deleted_stale",
            "Decision: obsolete deleted blocker should not surface in retrieval.",
        ),
        (
            "mem_deleted_survivor",
            "Decision: active blocker memory remains retrievable after tombstone reindex.",
        ),
    ] {
        let body = json!({
            "memory_id": memory_id,
            "requester_role": "chat",
            "use_mode": "project_chat",
            "scope": "project",
            "owner_id": "project-deleted",
            "project_id": "project-deleted",
            "source_kind": "decision_track",
            "layer": "l1_canonical",
            "title": "Deleted filter decision",
            "text": text,
            "audit_ref": "deleted-filter-test",
        })
        .to_string();
        create_memory_object_json_from_body(&config, &body).expect("create object");
    }

    let indexed_raw = object_index_rebuild_cli_json(&config).expect("initial reindex");
    let indexed: Value = serde_json::from_str(&indexed_raw).expect("index json");
    assert_eq!(indexed["index"]["row_count"], 2);

    let mut deleted = read_memory_object(&config.db_path, "mem_deleted_stale")
        .expect("read deleted candidate")
        .expect("deleted candidate exists");
    let before_json = memory_object_to_json(&deleted).to_string();
    let now = now_ms_i64();
    deleted.status = "deleted".to_string();
    deleted.updated_at_ms = now;
    deleted.last_accessed_at_ms = now;
    deleted.version += 1;
    let after_json = memory_object_to_json(&deleted).to_string();
    let event = MemoryEventRecord {
        event_id: next_memory_event_id(),
        memory_id: deleted.memory_id.clone(),
        operation: "delete".to_string(),
        actor: "rust_hub_test".to_string(),
        reason: "memory_hybrid_retrieval_omits_deleted".to_string(),
        before_version: Some(deleted.version - 1),
        after_version: Some(deleted.version),
        before_json: Some(before_json),
        after_json: Some(after_json),
        policy_decision: "allow".to_string(),
        deny_code: String::new(),
        audit_ref: "deleted-filter-test".to_string(),
        created_at_ms: now,
    };
    update_memory_object_with_event(&config.db_path, &deleted, &event).expect("mark deleted");

    let stale = read_memory_object_index_summary(&config.db_path).expect("stale summary");
    assert_eq!(stale.stale_index_count, 1);

    let mut request = MemoryRetrievalRequest::with_defaults(config.root_dir.join("memory"));
    request.scope = "project".to_string();
    request.project_id = "project-deleted".to_string();
    request.query = "deleted blocker decision".to_string();
    request.explain = true;
    let raw = retrieve_json_from_request_with_config(&config, request).expect("retrieve");
    let value: Value = serde_json::from_str(&raw).expect("json");
    assert_eq!(value["retrieval_engine"]["index_rebuilt"], true);
    assert_eq!(value["retrieval_engine"]["stale_index_count"], 0);
    let results = value["results"].as_array().expect("results");
    assert!(results
        .iter()
        .any(|item| item["memory_id"] == "mem_deleted_survivor"));
    assert!(!results
        .iter()
        .any(|item| item["memory_id"] == "mem_deleted_stale"));

    let _ = fs::remove_dir_all(config.root_dir);
}

#[test]
fn memory_object_http_create_get_list_history_roundtrip() {
    let config = test_config("objects");
    let body = json!({
        "requester_role": "chat",
        "use_mode": "project_chat",
        "scope": "project",
        "owner_id": "project-a",
        "project_id": "project-a",
        "source_kind": "project_capsule",
        "layer": "l1_canonical",
        "title": "Decision",
        "text": "Use Rust universal memory objects for model-agnostic memory.",
        "tags": ["memory", "rust"],
        "audit_ref": "audit-test",
    })
    .to_string();
    let (status, raw) = object_collection_http_json(&config, "POST", "", &body);
    assert_eq!(status, "200 OK");
    let created: Value = serde_json::from_str(&raw).expect("created json");
    assert_eq!(created["schema_version"], MEMORY_OBJECT_RESULT_SCHEMA);
    let memory_id = created["memory_id"].as_str().expect("memory id");

    let (status, raw) = object_item_http_json(
        &config,
        format!("/memory/objects/{memory_id}").as_str(),
        "GET",
        "",
        "",
    );
    assert_eq!(status, "200 OK");
    let fetched: Value = serde_json::from_str(&raw).expect("fetched json");
    assert_eq!(fetched["object"]["owner_id"], "project-a");

    let (status, raw) = object_collection_http_json(&config, "GET", "project_id=project-a", "");
    assert_eq!(status, "200 OK");
    let listed: Value = serde_json::from_str(&raw).expect("list json");
    assert_eq!(listed["count"], 1);

    let (status, raw) = object_item_http_json(
        &config,
        format!("/memory/objects/{memory_id}/history").as_str(),
        "GET",
        "",
        "",
    );
    assert_eq!(status, "200 OK");
    let history: Value = serde_json::from_str(&raw).expect("history json");
    assert_eq!(history["count"], 1);

    let _ = fs::remove_dir_all(config.root_dir);
}

#[test]
fn memory_object_cli_create_get_list_history_roundtrip() {
    let config = test_config("objects_cli");
    let created_raw = dispatch(
        &config,
        &args(&[
            "object-create",
            "--memory-id",
            "mem_cli_1",
            "--requester-role",
            "chat",
            "--use-mode",
            "project_chat",
            "--scope",
            "project",
            "--owner-id",
            "project-cli",
            "--project-id",
            "project-cli",
            "--source-kind",
            "project_capsule",
            "--layer",
            "l1_canonical",
            "--title",
            "CLI Decision",
            "--text",
            "CLI memory object creation stays model agnostic and policy gated.",
            "--tags",
            "memory,cli",
            "--audit-ref",
            "cli-test",
        ]),
    )
    .expect("create object");
    let created: Value = serde_json::from_str(&created_raw).expect("created json");
    assert_eq!(created["schema_version"], MEMORY_OBJECT_RESULT_SCHEMA);
    assert_eq!(created["memory_id"], "mem_cli_1");

    let listed_raw = dispatch(
        &config,
        &args(&["object-list", "--project-id", "project-cli", "--limit", "5"]),
    )
    .expect("list objects");
    let listed: Value = serde_json::from_str(&listed_raw).expect("listed json");
    assert_eq!(listed["schema_version"], MEMORY_OBJECT_LIST_SCHEMA);
    assert_eq!(listed["count"], 1);

    let fetched_raw =
        dispatch(&config, &args(&["object-get", "--memory-id", "mem_cli_1"])).expect("get object");
    let fetched: Value = serde_json::from_str(&fetched_raw).expect("fetched json");
    assert_eq!(fetched["object"]["owner_id"], "project-cli");

    let history_raw = dispatch(
        &config,
        &args(&["object-history", "--memory-id", "mem_cli_1"]),
    )
    .expect("history");
    let history: Value = serde_json::from_str(&history_raw).expect("history json");
    assert_eq!(history["schema_version"], MEMORY_OBJECT_HISTORY_SCHEMA);
    assert_eq!(history["count"], 1);

    let policy_raw = dispatch(
        &config,
        &args(&[
            "policy-evaluate",
            "--requester-role",
            "chat",
            "--use-mode",
            "project_chat",
            "--scope",
            "user",
        ]),
    )
    .expect("policy");
    let policy: Value = serde_json::from_str(&policy_raw).expect("policy json");
    assert_eq!(policy["decision"], "deny");
    assert_eq!(policy["deny_code"], "user_memory_grant_required");

    let _ = fs::remove_dir_all(config.root_dir);
}

#[test]
fn memory_writeback_candidate_create_list_approve_roundtrip() {
    let config = test_config("writeback_candidate_approve");
    let body = json!({
            "memory_id": "mem_candidate_approve",
            "requester_role": "tool",
            "use_mode": "tool_plan",
            "scope": "project",
            "owner_id": "project-candidate",
            "project_id": "project-candidate",
            "source_kind": "decision_track",
            "layer": "l1_canonical",
            "title": "Candidate decision",
            "text": "Decision: approved writeback candidates become active Rust memory only after policy-gated review.",
            "tags": ["memory", "candidate"],
            "audit_ref": "candidate-test",
        })
        .to_string();
    let (status, raw) =
        writeback_candidates_http_json(&config, "/memory/writeback/candidates", "POST", "", &body);
    assert_eq!(status, "200 OK");
    let created: Value = serde_json::from_str(&raw).expect("created json");
    assert_eq!(created["schema_version"], MEMORY_WRITEBACK_CANDIDATE_SCHEMA);
    assert_eq!(created["status"], "candidate_created");
    assert_eq!(created["object"]["status"], "candidate");
    assert_eq!(
        created["candidate_writeback"]["authority"],
        "rust_policy_gated_candidate_queue"
    );

    let (status, raw) = writeback_candidates_http_json(
        &config,
        "/memory/writeback/candidates",
        "GET",
        "project_id=project-candidate",
        "",
    );
    assert_eq!(status, "200 OK");
    let listed: Value = serde_json::from_str(&raw).expect("list json");
    assert_eq!(listed["candidate_count"], 1);

    let readiness_raw =
        readiness_json_from_dir(&config, config.root_dir.join("memory")).expect("readiness");
    let readiness: Value = serde_json::from_str(&readiness_raw).expect("readiness json");
    assert_eq!(
        readiness["object_store"]["writeback_candidates"]["candidate_object_count"],
        1
    );
    assert_eq!(
        readiness["object_store"]["writeback_candidates"]["candidate_approve_reject_http"],
        true
    );

    let approve_body = json!({
        "requester_role": "tool",
        "use_mode": "tool_plan",
        "actor": "reviewer",
        "audit_ref": "candidate-approve-test",
    })
    .to_string();
    let (status, raw) = writeback_candidates_http_json(
        &config,
        "/memory/writeback/candidates/mem_candidate_approve/approve",
        "POST",
        "",
        &approve_body,
    );
    assert_eq!(status, "200 OK");
    let approved: Value = serde_json::from_str(&raw).expect("approved json");
    assert_eq!(
        approved["schema_version"],
        MEMORY_WRITEBACK_CANDIDATE_SCHEMA
    );
    assert_eq!(approved["status"], "approved");
    assert_eq!(approved["object"]["status"], "active");
    assert_eq!(approved["transition"]["from_status"], "candidate");
    assert_eq!(approved["transition"]["to_status"], "active");
    assert_eq!(approved["production_authority_change"], false);

    let (status, raw) = writeback_candidates_http_json(
        &config,
        "/memory/writeback/candidates",
        "GET",
        "project_id=project-candidate",
        "",
    );
    assert_eq!(status, "200 OK");
    let listed: Value = serde_json::from_str(&raw).expect("list after approve json");
    assert_eq!(listed["candidate_count"], 0);

    let history =
        read_memory_object_history(&config.db_path, "mem_candidate_approve", 10).expect("history");
    assert_eq!(history.len(), 2);
    assert_eq!(history[0].operation, "approve");

    let mut request = MemoryRetrievalRequest::with_defaults(config.root_dir.join("memory"));
    request.scope = "project".to_string();
    request.project_id = "project-candidate".to_string();
    request.query = "policy gated review approved writeback".to_string();
    request.explain = true;
    let raw = retrieve_json_from_request_with_config(&config, request).expect("retrieve");
    let value: Value = serde_json::from_str(&raw).expect("retrieve json");
    assert_eq!(value["results"][0]["memory_id"], "mem_candidate_approve");

    let _ = fs::remove_dir_all(config.root_dir);
}

#[test]
fn memory_writeback_candidate_rejects_and_blocks_invalid_transitions() {
    let config = test_config("writeback_candidate_reject");
    let body = json!({
            "memory_id": "mem_candidate_reject",
            "requester_role": "tool",
            "use_mode": "tool_plan",
            "scope": "project",
            "owner_id": "project-candidate",
            "project_id": "project-candidate",
            "source_kind": "recommendation",
            "layer": "l2_observations",
            "title": "Candidate recommendation",
            "text": "Recommendation: rejected writeback candidates must not become retrievable active memory.",
            "audit_ref": "candidate-reject-test",
        })
        .to_string();
    let (status, _) =
        writeback_candidates_http_json(&config, "/memory/writeback/candidates", "POST", "", &body);
    assert_eq!(status, "200 OK");

    let reject_body = json!({
        "requester_role": "tool",
        "use_mode": "tool_plan",
        "actor": "reviewer",
        "audit_ref": "candidate-reject-test",
    })
    .to_string();
    let (status, raw) = object_item_http_json(
        &config,
        "/memory/objects/mem_candidate_reject/reject",
        "POST",
        "",
        &reject_body,
    );
    assert_eq!(status, "200 OK");
    let rejected: Value = serde_json::from_str(&raw).expect("rejected json");
    assert_eq!(rejected["status"], "rejected");
    assert_eq!(rejected["object"]["status"], "rejected");

    let (status, raw) = writeback_candidates_http_json(
        &config,
        "/memory/writeback/candidates/mem_candidate_reject/reject",
        "POST",
        "",
        &reject_body,
    );
    assert_eq!(status, "409 Conflict");
    let conflict: Value = serde_json::from_str(&raw).expect("conflict json");
    assert_eq!(
        conflict["error_code"],
        "memory_writeback_candidate_status_mismatch"
    );
    assert_eq!(conflict["current_status"], "rejected");

    let mut request = MemoryRetrievalRequest::with_defaults(config.root_dir.join("memory"));
    request.scope = "project".to_string();
    request.project_id = "project-candidate".to_string();
    request.query = "rejected writeback candidates retrievable active memory".to_string();
    let raw = retrieve_json_from_request_with_config(&config, request).expect("retrieve");
    let value: Value = serde_json::from_str(&raw).expect("retrieve json");
    assert_ne!(value["source"], MEMORY_OBJECT_RETRIEVAL_SOURCE);

    let _ = fs::remove_dir_all(config.root_dir);
}

#[test]
fn memory_writeback_candidate_secret_like_content_fails_closed() {
    let config = test_config("writeback_candidate_secret");
    let body = json!({
        "requester_role": "tool",
        "use_mode": "tool_plan",
        "scope": "project",
        "owner_id": "project-candidate",
        "project_id": "project-candidate",
        "source_kind": "decision_track",
        "layer": "l1_canonical",
        "title": "Secret candidate",
        "text": "store api key sk-secret-value",
    })
    .to_string();
    let (status, raw) =
        writeback_candidates_http_json(&config, "/memory/writeback/candidates", "POST", "", &body);
    assert_eq!(status, "403 Forbidden");
    let value: Value = serde_json::from_str(&raw).expect("denied json");
    assert_eq!(value["error_code"], "memory_secret_pattern_denied");
    assert!(
        read_memory_object_store_summary(&config.db_path)
            .expect("summary")
            .object_count
            == 0
    );

    let _ = fs::remove_dir_all(config.root_dir);
}

#[test]
fn memory_writeback_candidate_extracts_axmemory_delta_and_dedupes() {
    let config = test_config("writeback_candidate_extract");
    let payload = json!({
        "project_id": "project-extract",
        "audit_ref": "candidate-extract-test",
        "actor": "xt_memory_pipeline",
        "delta": {
            "goalUpdate": "Move project memory writeback through Rust candidates.",
            "decisionsAdd": [
                "Keep AXMemory delta extraction as candidate-only until approval.",
                "Keep AXMemory delta extraction as candidate-only until approval."
            ],
            "nextStepsAdd": [
                "Wire Swift shell to the Rust candidate extractor."
            ],
            "requirementsRemove": [
                "This removal should not create a candidate."
            ]
        }
    })
    .to_string();
    let (status, raw) = writeback_candidates_http_json(
        &config,
        "/memory/writeback/candidates/extract",
        "POST",
        "",
        &payload,
    );
    assert_eq!(status, "200 OK");
    let extracted: Value = serde_json::from_str(&raw).expect("extract json");
    assert_eq!(
        extracted["schema_version"],
        MEMORY_WRITEBACK_CANDIDATE_EXTRACT_SCHEMA
    );
    assert_eq!(extracted["ok"], true);
    assert_eq!(extracted["applied"], true);
    assert_eq!(extracted["planned_create_count"], 3);
    assert_eq!(extracted["created_count"], 3);
    assert_eq!(extracted["duplicate_count"], 1);
    assert_eq!(
        extracted["candidate_writeback"]["authority"],
        "rust_policy_gated_candidate_queue"
    );

    let listed_raw = list_writeback_candidates_json(&config, "project_id=project-extract&limit=10")
        .expect("list candidates");
    let listed: Value = serde_json::from_str(&listed_raw).expect("list json");
    assert_eq!(listed["candidate_count"], 3);
    assert!(listed["objects"]
        .as_array()
        .unwrap()
        .iter()
        .all(|item| item["status"] == "candidate"));

    let mut request = MemoryRetrievalRequest::with_defaults(config.root_dir.join("memory"));
    request.scope = "project".to_string();
    request.project_id = "project-extract".to_string();
    request.query = "Rust candidates approval".to_string();
    let raw = retrieve_json_from_request_with_config(&config, request).expect("retrieve");
    let value: Value = serde_json::from_str(&raw).expect("retrieve json");
    assert_ne!(value["source"], MEMORY_OBJECT_RETRIEVAL_SOURCE);

    let (status, raw) = writeback_candidates_http_json(
        &config,
        "/memory/writeback/candidates/extract",
        "POST",
        "",
        &payload,
    );
    assert_eq!(status, "200 OK");
    let duplicate: Value = serde_json::from_str(&raw).expect("duplicate json");
    assert_eq!(duplicate["created_count"], 0);
    assert_eq!(duplicate["duplicate_count"], 4);

    let _ = fs::remove_dir_all(config.root_dir);
}

#[test]
fn memory_writeback_candidate_extract_dry_run_and_secret_fail_closed() {
    let config = test_config("writeback_candidate_extract_secret");
    let payload = json!({
        "project_id": "project-extract",
        "audit_ref": "candidate-extract-dry-run-test",
        "delta": {
            "requirementsAdd": ["The extractor should support dry-run planning."]
        }
    })
    .to_string();
    let (status, raw) = writeback_candidates_http_json(
        &config,
        "/memory/writeback/candidates/extract",
        "POST",
        "dry_run=1",
        &payload,
    );
    assert_eq!(status, "200 OK");
    let dry_run: Value = serde_json::from_str(&raw).expect("dry run json");
    assert_eq!(dry_run["dry_run"], true);
    assert_eq!(dry_run["created_count"], 0);
    assert_eq!(dry_run["planned_create_count"], 1);
    assert_eq!(
        read_memory_object_store_summary(&config.db_path)
            .expect("summary after dry run")
            .object_count,
        0
    );
    let cli_raw = dispatch(
        &config,
        &args(&[
            "candidate-extract",
            "--payload-json",
            payload.as_str(),
            "--dry-run",
        ]),
    )
    .expect("cli dry run");
    let cli: Value = serde_json::from_str(&cli_raw).expect("cli json");
    assert_eq!(cli["dry_run"], true);
    assert_eq!(cli["planned_create_count"], 1);

    let secret_payload = json!({
        "project_id": "project-extract",
        "audit_ref": "candidate-extract-deny-test",
        "delta": {
            "decisionsAdd": ["Store api key sk-secret-value in memory."]
        }
    })
    .to_string();
    let (status, raw) = writeback_candidates_http_json(
        &config,
        "/memory/writeback/candidates/extract",
        "POST",
        "",
        &secret_payload,
    );
    assert_eq!(status, "403 Forbidden");
    let denied: Value = serde_json::from_str(&raw).expect("denied json");
    assert_eq!(denied["status"], "denied");
    assert_eq!(denied["blocking_count"], 1);
    assert_eq!(
        read_memory_object_store_summary(&config.db_path)
            .expect("summary after denied")
            .object_count,
        0
    );

    let _ = fs::remove_dir_all(config.root_dir);
}

#[test]
fn project_canonical_sync_dry_run_apply_and_update_roundtrip() {
    let config = test_config("project_canonical_sync");
    let payload = json!({
        "project_canonical_memory": {
            "project_id": "project-sync",
            "display_name": "Sync Project",
            "items": [
                {
                    "key": "xterminal.project.memory.schema_version",
                    "value": "xt.project_canonical_memory.v1"
                },
                {
                    "key": "xterminal.project.memory.goal",
                    "value": "Build a Rust-owned universal memory layer."
                },
                {
                    "key": "xterminal.project.memory.decisions",
                    "value": "Use Rust memory objects as canonical project memory."
                }
            ]
        }
    });
    let dry_raw =
        project_canonical_sync_json_from_value(&config, &payload, false).expect("dry run");
    let dry: Value = serde_json::from_str(&dry_raw).expect("dry json");
    assert_eq!(dry["schema_version"], MEMORY_PROJECT_CANONICAL_SYNC_SCHEMA);
    assert_eq!(dry["dry_run"], true);
    assert_eq!(dry["created_count"], 2);
    assert_eq!(dry["skipped_count"], 1);
    assert!(
        read_memory_object(&config.db_path, "mem_xt_project_project-sync_goal")
            .expect("read dry object")
            .is_none()
    );

    let applied_raw =
        project_canonical_sync_json_from_value(&config, &payload, true).expect("apply");
    let applied: Value = serde_json::from_str(&applied_raw).expect("applied json");
    assert_eq!(applied["applied"], true);
    assert_eq!(applied["created_count"], 2);
    let goal = read_memory_object(&config.db_path, "mem_xt_project_project-sync_goal")
        .expect("read goal")
        .expect("goal exists");
    assert_eq!(goal.source_kind, "project_goal");
    assert_eq!(goal.version, 1);

    let update_payload = json!({
        "project_canonical_memory": {
            "project_id": "project-sync",
            "display_name": "Sync Project",
            "items": [
                {
                    "key": "xterminal.project.memory.goal",
                    "value": "Build a Rust-owned universal memory layer with AXMemory sync."
                }
            ]
        }
    });
    let updated_raw = project_canonical_sync_json_from_value(&config, &update_payload, true)
        .expect("apply update");
    let updated: Value = serde_json::from_str(&updated_raw).expect("updated json");
    assert_eq!(updated["updated_count"], 1);
    let goal_after_update = read_memory_object(&config.db_path, "mem_xt_project_project-sync_goal")
        .expect("read updated goal")
        .expect("updated goal exists");
    assert_eq!(goal_after_update.version, 2);
    assert!(goal_after_update.text.contains("AXMemory sync"));
    let history =
        read_memory_object_history(&config.db_path, "mem_xt_project_project-sync_goal", 10)
            .expect("history");
    assert_eq!(history.len(), 2);
    assert_eq!(history[0].operation, "update");

    let _ = fs::remove_dir_all(config.root_dir);
}

#[test]
fn project_canonical_sync_fails_closed_on_secret_like_item() {
    let config = test_config("project_canonical_sync_secret");
    let payload = json!({
        "project_canonical_memory": {
            "project_id": "project-sync",
            "items": [
                {
                    "key": "xterminal.project.memory.goal",
                    "value": "store api key sk-secret-value"
                }
            ]
        }
    });
    let dry_raw =
        project_canonical_sync_json_from_value(&config, &payload, false).expect("dry run");
    let dry: Value = serde_json::from_str(&dry_raw).expect("dry json");
    assert_eq!(dry["ok"], false);
    assert_eq!(dry["blocking_count"], 1);

    let denied = project_canonical_sync_json_from_value(&config, &payload, true)
        .expect_err("apply should fail closed");
    assert_eq!(denied.status, "403 Forbidden");
    assert!(
        read_memory_object(&config.db_path, "mem_xt_project_project-sync_goal")
            .expect("read denied object")
            .is_none()
    );

    let _ = fs::remove_dir_all(config.root_dir);
}

#[test]
fn memory_gateway_prepare_returns_policy_gated_project_slots() {
    let config = test_config("gateway_prepare");
    let payload = json!({
        "project_canonical_memory": {
            "project_id": "project-gateway",
            "display_name": "Gateway Project",
            "items": [
                {
                    "key": "xterminal.project.memory.goal",
                    "value": "Route all model calls through a Rust memory gateway."
                },
                {
                    "key": "xterminal.project.memory.risks",
                    "value": "Keep raw evidence out of default prompt context."
                }
            ]
        }
    });
    project_canonical_sync_json_from_value(&config, &payload, true).expect("apply sync");
    let raw_evidence_body = json!({
        "requester_role": "chat",
        "use_mode": "project_chat",
        "scope": "project",
        "owner_id": "project-gateway",
        "project_id": "project-gateway",
        "source_kind": "memory_file",
        "layer": "l4_raw_evidence",
        "title": "Raw trace",
        "text": "Raw evidence should require explicit gateway opt-in.",
        "visibility": "local_only",
        "audit_ref": "gateway-test",
    })
    .to_string();
    create_memory_object_json_from_body(&config, &raw_evidence_body).expect("create raw");

    let body = json!({
        "requester_role": "chat",
        "use_mode": "project_chat",
        "scope": "project",
        "project_id": "project-gateway",
        "latest_user": "what should the model remember",
        "max_items": 10
    })
    .to_string();
    let (status, raw) = memory_gateway_prepare_http_json(&config, "POST", &body);
    assert_eq!(status, "200 OK");
    let prepared: Value = serde_json::from_str(&raw).expect("gateway json");
    assert_eq!(prepared["schema_version"], MEMORY_GATEWAY_PREPARE_SCHEMA);
    assert_eq!(prepared["source"], "rust_memory_gateway_prepare");
    assert_eq!(prepared["mode"], "prepare_only_no_model_call");
    assert_eq!(prepared["production_authority_change"], false);
    assert_eq!(prepared["serving_profile_id"], "M1_Execute");
    assert_eq!(prepared["selected_profile"], "M1_Execute");
    assert_eq!(prepared["effective_profile"], "M1_Execute");
    assert_eq!(
        prepared["profile_reason"],
        "derived_from_use_mode_project_chat"
    );
    assert_eq!(prepared["object_count"], 2);
    assert_eq!(prepared["selected_count"], 2);
    assert_eq!(prepared["raw_evidence_allowed"], false);
    assert!(prepared["context_text"]
        .as_str()
        .unwrap()
        .contains("Route all model calls"));
    assert!(prepared["context_text"]
        .as_str()
        .unwrap()
        .contains("Keep raw evidence out"));
    assert!(!prepared["context_text"]
        .as_str()
        .unwrap()
        .contains("Raw evidence should require explicit"));
    assert_eq!(
        prepared["effective_layers"].as_array().unwrap(),
        &vec![
            json!("l1_canonical"),
            json!("l2_observations"),
            json!("l3_working_set")
        ]
    );

    let remote_body = json!({
        "requester_role": "remote_export",
        "use_mode": "remote_prompt_bundle",
        "scope": "project",
        "project_id": "project-gateway",
        "remote_export_requested": true,
        "requested_layers": ["l1_canonical"],
        "max_items": 10
    })
    .to_string();
    let (status, raw) = memory_gateway_prepare_http_json(&config, "POST", &remote_body);
    assert_eq!(status, "200 OK");
    let remote: Value = serde_json::from_str(&raw).expect("remote gateway json");
    assert_eq!(remote["serving_profile_id"], "M0_Heartbeat");
    assert_eq!(remote["effective_profile"], "M0_Heartbeat");
    assert_eq!(remote["object_count"], 0);
    assert_eq!(remote["remote_export_filtered_count"], 1);
    assert_eq!(remote["skipped"]["remote_visibility"], 1);

    let _ = fs::remove_dir_all(config.root_dir);
}

#[test]
fn memory_gateway_prepare_applies_serving_profile_defaults() {
    let config = test_config("gateway_prepare_profiles");
    let payload = json!({
        "project_canonical_memory": {
            "project_id": "project-profile",
            "display_name": "Profile Project",
            "items": [
                {
                    "key": "xterminal.project.memory.goal",
                    "value": "Keep the gateway profile contract stable."
                },
                {
                    "key": "xterminal.project.memory.current_state",
                    "value": "Profile alignment is under implementation."
                },
                {
                    "key": "xterminal.project.memory.next_steps",
                    "value": "Add Rust profile evidence tests."
                },
                {
                    "key": "xterminal.project.memory.risks",
                    "value": "Do not treat serving profile as an authority grant."
                },
                {
                    "key": "xterminal.project.memory.open_questions",
                    "value": "Which profile is ready for require-mode cutover?"
                }
            ]
        }
    });
    project_canonical_sync_json_from_value(&config, &payload, true).expect("apply sync");

    let m0_body = json!({
        "requester_role": "chat",
        "use_mode": "project_chat",
        "scope": "project",
        "project_id": "project-profile",
        "serving_profile_id": "M0_Heartbeat"
    })
    .to_string();
    let (status, raw) = memory_gateway_prepare_http_json(&config, "POST", &m0_body);
    assert_eq!(status, "200 OK");
    let m0: Value = serde_json::from_str(&raw).expect("m0 json");
    assert_eq!(m0["serving_profile_id"], "M0_Heartbeat");
    assert_eq!(m0["selected_profile"], "M0_Heartbeat");
    assert_eq!(m0["effective_profile"], "M0_Heartbeat");
    assert_eq!(m0["profile_reason"], "requested_by_client");
    assert_eq!(m0["max_items"], 4);
    assert_eq!(m0["max_snippet_chars"], 240);
    assert_eq!(
        m0["effective_layers"].as_array().unwrap(),
        &vec![json!("l1_canonical"), json!("l3_working_set")]
    );
    assert_eq!(m0["raw_evidence_allowed"], false);
    assert!(!m0["context_text"]
        .as_str()
        .unwrap()
        .contains("authority grant"));

    let m2_body = json!({
        "requester_role": "chat",
        "use_mode": "project_chat",
        "scope": "project",
        "project_id": "project-profile",
        "serving_profile_id": "M2_PlanReview"
    })
    .to_string();
    let (status, raw) = memory_gateway_prepare_http_json(&config, "POST", &m2_body);
    assert_eq!(status, "200 OK");
    let m2: Value = serde_json::from_str(&raw).expect("m2 json");
    assert_eq!(m2["serving_profile_id"], "M2_PlanReview");
    assert_eq!(m2["selected_profile"], "M2_PlanReview");
    assert_eq!(m2["effective_profile"], "M2_PlanReview");
    assert_eq!(m2["expanded"], true);
    assert_eq!(m2["expansion_reason"], "requested_profile_expansion");
    assert_eq!(m2["max_items"], 20);
    assert_eq!(m2["max_snippet_chars"], 640);
    assert_eq!(m2["raw_evidence_allowed"], false);
    assert!(m2["object_count"].as_u64().unwrap() > m0["object_count"].as_u64().unwrap());
    assert!(m2["requested_source_kinds"]
        .as_array()
        .unwrap()
        .iter()
        .any(|kind| kind == "risk"));

    let _ = fs::remove_dir_all(config.root_dir);
}

#[test]
fn memory_gateway_prepare_downgrades_remote_deep_profile() {
    let config = test_config("gateway_prepare_remote_profile");
    for (memory_id, visibility, text) in [
        (
            "mem_remote_profile_safe",
            "sanitized_remote_ok",
            "Remote-safe canonical profile evidence.",
        ),
        (
            "mem_remote_profile_local",
            "local_only",
            "Local-only canonical profile evidence must not export.",
        ),
    ] {
        let body = json!({
            "memory_id": memory_id,
            "requester_role": "chat",
            "use_mode": "project_chat",
            "scope": "project",
            "owner_id": "project-remote-profile",
            "project_id": "project-remote-profile",
            "source_kind": "project_goal",
            "layer": "l1_canonical",
            "title": "Remote profile evidence",
            "text": text,
            "visibility": visibility,
            "audit_ref": "remote-profile-test",
        })
        .to_string();
        create_memory_object_json_from_body(&config, &body).expect("create object");
    }

    let body = json!({
        "requester_role": "remote_export",
        "use_mode": "remote_prompt_bundle",
        "scope": "project",
        "project_id": "project-remote-profile",
        "remote_export_requested": true,
        "serving_profile_id": "M4_FullScan"
    })
    .to_string();
    let (status, raw) = memory_gateway_prepare_http_json(&config, "POST", &body);
    assert_eq!(status, "200 OK");
    let prepared: Value = serde_json::from_str(&raw).expect("remote profile json");
    assert_eq!(prepared["serving_profile_id"], "M4_FullScan");
    assert_eq!(prepared["selected_profile"], "M4_FullScan");
    assert_eq!(prepared["effective_profile"], "M1_Execute");
    assert_eq!(
        prepared["profile_reason"],
        "remote_export_profile_downgraded"
    );
    assert_eq!(prepared["expanded"], false);
    assert_eq!(
        prepared["expansion_reason"],
        "remote_export_no_auto_deep_expand"
    );
    assert_eq!(prepared["max_items"], 12);
    assert_eq!(prepared["object_count"], 1);
    assert_eq!(prepared["remote_export_filtered_count"], 1);
    assert_eq!(prepared["raw_evidence_allowed"], false);
    assert!(prepared["context_text"]
        .as_str()
        .unwrap()
        .contains("Remote-safe canonical"));
    assert!(!prepared["context_text"]
        .as_str()
        .unwrap()
        .contains("Local-only canonical"));

    let _ = fs::remove_dir_all(config.root_dir);
}

#[test]
fn memory_gateway_prepare_fails_closed_for_disallowed_raw_layer() {
    let config = test_config("gateway_prepare_policy");
    let body = json!({
        "requester_role": "supervisor",
        "use_mode": "supervisor_orchestration",
        "scope": "project",
        "project_id": "project-gateway",
        "serving_profile_id": "M3_DeepDive",
        "requested_layers": ["l4_raw_evidence"]
    })
    .to_string();
    let (status, raw) = memory_gateway_prepare_http_json(&config, "POST", &body);
    assert_eq!(status, "403 Forbidden");
    let denied: Value = serde_json::from_str(&raw).expect("denied json");
    assert_eq!(denied["schema_version"], MEMORY_GATEWAY_PREPARE_SCHEMA);
    assert_eq!(denied["status"], "denied");
    assert_eq!(denied["deny_code"], "memory_layer_not_allowed_for_mode");
    assert_eq!(denied["serving_profile_id"], "M3_DeepDive");
    assert_eq!(denied["effective_profile"], "M3_DeepDive");

    let _ = fs::remove_dir_all(config.root_dir);
}

#[test]
fn memory_policy_denies_project_coder_user_memory() {
    let body = json!({
        "requester_role": "chat",
        "use_mode": "project_chat",
        "scope": "user",
    });
    let result = evaluate_memory_policy(&body);
    assert_eq!(result.decision, "deny");
    assert_eq!(result.deny_code, "user_memory_grant_required");
}

#[test]
fn memory_policy_covers_handoff_remote_supervisor_and_high_risk_modes() {
    let lane = evaluate_memory_policy(&json!({
        "requester_role": "lane",
        "use_mode": "lane_handoff",
        "scope": "project",
    }));
    assert_eq!(lane.decision, "deny");
    assert_eq!(lane.deny_code, "lane_handoff_fulltext_denied");
    assert_eq!(lane.visibility_floor, "refs_only");
    assert!(lane.requires_fresh_snapshot);

    let remote_raw = evaluate_memory_policy(&json!({
        "requester_role": "remote_export",
        "use_mode": "remote_prompt_bundle",
        "scope": "project",
        "remote_export_requested": true,
        "requested_layers": ["l4_raw_evidence"],
    }));
    assert_eq!(remote_raw.decision, "deny");
    assert_eq!(remote_raw.deny_code, "raw_evidence_remote_export_denied");

    let supervisor_raw = evaluate_memory_policy(&json!({
        "requester_role": "supervisor",
        "use_mode": "supervisor_orchestration",
        "scope": "project",
        "requested_source_kinds": ["raw_evidence"],
    }));
    assert_eq!(supervisor_raw.decision, "deny");
    assert_eq!(
        supervisor_raw.deny_code,
        "memory_layer_not_allowed_for_mode"
    );

    let high_risk = evaluate_memory_policy(&json!({
        "requester_role": "tool",
        "use_mode": "tool_act_high_risk",
        "scope": "project",
    }));
    assert_eq!(high_risk.decision, "allow");
    assert!(high_risk.requires_fresh_snapshot);
    assert!(!high_risk.raw_evidence_allowed);
    assert!(!high_risk
        .allowed_layers
        .iter()
        .any(|layer| layer == "l4_raw_evidence"));
}

#[test]
fn memory_object_http_rejects_secret_like_content() {
    let config = test_config("secret_object");
    let body = json!({
        "requester_role": "chat",
        "use_mode": "project_chat",
        "scope": "project",
        "owner_id": "project-a",
        "text": "store api key sk-secret-value",
    })
    .to_string();
    let (status, raw) = object_collection_http_json(&config, "POST", "", &body);
    assert_eq!(status, "403 Forbidden");
    let value: Value = serde_json::from_str(&raw).expect("json");
    assert_eq!(value["error_code"], "memory_secret_pattern_denied");
    let _ = fs::remove_dir_all(config.root_dir);
}
