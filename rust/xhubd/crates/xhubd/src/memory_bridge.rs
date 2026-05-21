use std::collections::{BTreeMap, BTreeSet};
use std::env;
use std::fmt::Write as _;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};

use serde_json::{json, Value};
use xhub_core::{now_ms, HubConfig};
use xhub_db::{
    apply_baseline_migrations, create_memory_object_with_event, list_memory_object_index,
    list_memory_objects, read_memory_object, read_memory_object_history,
    read_memory_object_index_summary, read_memory_object_store_summary,
    rebuild_memory_object_index, update_memory_object_with_event, MemoryEventRecord,
    MemoryObjectIndexFilter, MemoryObjectIndexRecord, MemoryObjectIndexSummary,
    MemoryObjectListFilter, MemoryObjectRecord,
};
use xhub_memory::{
    readiness_from_snapshot, retrieve_memory, retrieve_memory_from_snapshot, scan_memory_snapshot,
    write_memory_entry, MemoryIndexSnapshot, MemoryMode, MemoryRetrievalRequest,
    MemoryWriteRequest, MEMORY_RETRIEVAL_RESULT_SCHEMA, MEMORY_WRITE_RESULT_SCHEMA,
    RUST_MEMORY_SHADOW_SOURCE,
};

const SCHEMA_VERSION: &str = "xhub.memory_bridge.v1";
const MEMORY_OBJECT_SCHEMA: &str = "xhub.memory.object.v1";
const MEMORY_OBJECT_RESULT_SCHEMA: &str = "xhub.memory.object_result.v1";
const MEMORY_OBJECT_LIST_SCHEMA: &str = "xhub.memory.object_list.v1";
const MEMORY_OBJECT_HISTORY_SCHEMA: &str = "xhub.memory.object_history.v1";
const MEMORY_POLICY_RESULT_SCHEMA: &str = "xhub.memory.policy_result.v1";
const MEMORY_PROJECT_CANONICAL_SYNC_SCHEMA: &str = "xhub.memory.project_canonical_sync.v1";
const MEMORY_GATEWAY_PREPARE_SCHEMA: &str = "xhub.memory.gateway_prepare.v1";
const MEMORY_OBJECT_RETRIEVAL_SOURCE: &str = "rust_memory_objects_hybrid_v1";
const MEMORY_RETRIEVAL_TRACE_LIMIT: usize = 32;
static MEMORY_OBJECT_COUNTER: AtomicU64 = AtomicU64::new(1);

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

pub fn retrieve_json_from_request(request: MemoryRetrievalRequest) -> Result<String, String> {
    let out = retrieve_memory(request);
    serde_json::to_string(&out).map_err(|err| format!("memory retrieve serialize failed: {err}"))
}

pub fn retrieve_json_from_request_with_config(
    config: &HubConfig,
    request: MemoryRetrievalRequest,
) -> Result<String, String> {
    let snapshot = scan_memory_snapshot(&request.memory_dir);
    retrieve_json_from_request_with_config_and_snapshot(config, request, &snapshot)
}

pub fn retrieve_json_from_request_with_snapshot(
    request: MemoryRetrievalRequest,
    snapshot: &MemoryIndexSnapshot,
) -> Result<String, String> {
    let out = retrieve_memory_from_snapshot(request, snapshot);
    serde_json::to_string(&out).map_err(|err| format!("memory retrieve serialize failed: {err}"))
}

pub fn retrieve_json_from_request_with_config_and_snapshot(
    config: &HubConfig,
    request: MemoryRetrievalRequest,
    snapshot: &MemoryIndexSnapshot,
) -> Result<String, String> {
    if let Some(value) = memory_object_retrieval_value(config, &request)? {
        return Ok(value.to_string());
    }
    retrieve_json_from_request_with_snapshot(request, snapshot)
}

fn memory_object_retrieval_value(
    config: &HubConfig,
    request: &MemoryRetrievalRequest,
) -> Result<Option<Value>, String> {
    let query_text = first_non_empty_text(&[&request.query, &request.latest_user]);
    if looks_like_secret_public(&query_text) {
        return Ok(Some(memory_retrieval_denied_value(
            request,
            "query_secret_pattern_denied",
        )));
    }

    let scope = memory_retrieval_object_scope(&request.scope);
    let project_id = sanitize_public_token(&request.project_id).unwrap_or_default();
    let explicit_object_ids = request
        .explicit_refs
        .iter()
        .filter_map(|value| memory_object_id_from_ref(value))
        .collect::<BTreeSet<_>>();
    if scope != "project" || project_id.is_empty() {
        return Ok(None);
    }

    let retrieval_kind = request.retrieval_kind.trim().to_ascii_lowercase();
    let exact_ref_lookup = retrieval_kind == "get_ref" && !explicit_object_ids.is_empty();
    let requested_source_kinds = request
        .requested_kinds
        .iter()
        .map(|value| normalize_source_kind_for_object(value))
        .collect::<BTreeSet<_>>();
    let requested_layers = request
        .requested_layers
        .iter()
        .map(|value| normalize_memory_layer(value))
        .filter(|value| !value.is_empty())
        .collect::<BTreeSet<_>>();
    let visibility_filter = normalize_visibility_filter(&request.visibility);
    let sensitivity_max = normalize_sensitivity_filter(&request.sensitivity_max);
    let read_limit = request.max_results.saturating_mul(20).clamp(50, 500);

    let mut index_summary = read_memory_object_index_summary(&config.db_path).unwrap_or_default();
    let mut index_rebuilt = false;
    let mut index_rebuild_error = String::new();
    if index_summary.active_indexable_object_count > 0
        && (index_summary.index_row_count == 0 || index_summary.stale_index_count > 0)
    {
        match rebuild_memory_object_index(&config.db_path) {
            Ok(report) => {
                index_rebuilt = report.rebuilt;
                index_summary = read_memory_object_index_summary(&config.db_path)
                    .unwrap_or_else(|_| index_summary.clone());
            }
            Err(err) => {
                index_rebuild_error = err.to_string();
            }
        }
    }

    let index_filter = MemoryObjectIndexFilter {
        scope: Some("project".to_string()),
        owner_id: None,
        project_id: Some(project_id.clone()),
        agent_id: None,
        source_kind: None,
        layer: None,
        sensitivity: None,
        visibility: None,
        limit: read_limit,
    };
    let indexed_rows = if index_summary.index_ready
        && index_summary.index_row_count > 0
        && index_summary.stale_index_count == 0
    {
        list_memory_object_index(&config.db_path, &index_filter)
            .map_err(|err| format!("memory object index retrieval list failed: {err}"))?
    } else {
        Vec::new()
    };
    let mut index_source = "rust_hub_memory_object_index";
    let mut documents = indexed_rows
        .into_iter()
        .map(memory_object_document_from_index)
        .collect::<Vec<_>>();

    if documents.is_empty() {
        index_source = "rust_hub_memory_objects";
        let filter = MemoryObjectListFilter {
            scope: Some("project".to_string()),
            owner_id: None,
            project_id: Some(project_id.clone()),
            agent_id: None,
            source_kind: None,
            layer: None,
            status: Some("active".to_string()),
            sensitivity: None,
            visibility: None,
            limit: read_limit,
        };
        let objects = list_memory_objects(&config.db_path, &filter)
            .map_err(|err| format!("memory object retrieval list failed: {err}"))?;
        documents = objects
            .into_iter()
            .map(memory_object_document_from_object)
            .collect::<Vec<_>>();
    }

    if documents.is_empty() {
        return Ok(None);
    }

    let query_tokens = object_retrieval_tokens(&query_text);
    let mut scored = Vec::<ObjectRetrievalCandidate>::new();
    let mut skipped_policy_or_filter = 0usize;
    let mut skipped_secret = 0usize;
    let mut skipped_deleted = 0usize;
    let mut skipped_no_match = 0usize;
    let mut omitted_trace = Vec::<Value>::new();
    for document in documents {
        if document.status != "active" {
            skipped_deleted += 1;
            push_object_omission_trace(
                request,
                &mut omitted_trace,
                &document,
                "deleted_or_inactive",
                index_source,
            );
            continue;
        }
        if document.sensitivity == "secret"
            || looks_like_secret_public(&document.text)
            || looks_like_secret_public(&document.title)
            || looks_like_secret_public(&document.summary)
        {
            skipped_secret += 1;
            push_object_omission_trace(
                request,
                &mut omitted_trace,
                &document,
                "secret_or_secret_like",
                index_source,
            );
            continue;
        }
        if !requested_source_kinds.is_empty()
            && !requested_source_kinds.contains(&document.source_kind)
        {
            skipped_policy_or_filter += 1;
            push_object_omission_trace(
                request,
                &mut omitted_trace,
                &document,
                "source_kind_filter",
                index_source,
            );
            continue;
        }
        if !requested_layers.is_empty() && !requested_layers.contains(&document.layer) {
            skipped_policy_or_filter += 1;
            push_object_omission_trace(
                request,
                &mut omitted_trace,
                &document,
                "layer_filter",
                index_source,
            );
            continue;
        }
        if !visibility_filter.is_empty() && document.visibility != visibility_filter {
            skipped_policy_or_filter += 1;
            push_object_omission_trace(
                request,
                &mut omitted_trace,
                &document,
                "visibility_filter",
                index_source,
            );
            continue;
        }
        if !sensitivity_max.is_empty()
            && !memory_sensitivity_allowed(&document.sensitivity, &sensitivity_max)
        {
            skipped_policy_or_filter += 1;
            push_object_omission_trace(
                request,
                &mut omitted_trace,
                &document,
                "sensitivity_filter",
                index_source,
            );
            continue;
        }
        if request.created_after_ms > 0 && document.created_at_ms < request.created_after_ms {
            skipped_policy_or_filter += 1;
            push_object_omission_trace(
                request,
                &mut omitted_trace,
                &document,
                "created_after_ms_filter",
                index_source,
            );
            continue;
        }
        if request.updated_after_ms > 0 && document.updated_at_ms < request.updated_after_ms {
            skipped_policy_or_filter += 1;
            push_object_omission_trace(
                request,
                &mut omitted_trace,
                &document,
                "updated_after_ms_filter",
                index_source,
            );
            continue;
        }
        if exact_ref_lookup && !explicit_object_ids.contains(&document.memory_id) {
            skipped_policy_or_filter += 1;
            push_object_omission_trace(
                request,
                &mut omitted_trace,
                &document,
                "explicit_ref_filter",
                index_source,
            );
            continue;
        }

        let lexical_score = if exact_ref_lookup {
            1.0
        } else {
            object_lexical_score(&query_tokens, &document.searchable_text)
        };
        let properties = document.properties.clone();
        let property_boost = if exact_ref_lookup {
            0.0
        } else {
            memory_object_property_boost(&query_tokens, &query_text, &properties, &document.title)
        };
        let pinned_boost = if document.pinned { 0.04 } else { 0.0 };
        let score = lexical_score + property_boost + pinned_boost;
        if !exact_ref_lookup && !query_tokens.is_empty() && score <= 0.0 {
            skipped_no_match += 1;
            push_object_omission_trace(
                request,
                &mut omitted_trace,
                &document,
                "no_lexical_or_property_match",
                index_source,
            );
            continue;
        }
        scored.push(ObjectRetrievalCandidate {
            document,
            lexical_score,
            property_boost,
            pinned_boost,
            score,
            properties,
        });
    }

    if scored.is_empty() {
        return Ok(None);
    }

    scored.sort_by(|left, right| {
        right
            .score
            .partial_cmp(&left.score)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| {
                right
                    .document
                    .updated_at_ms
                    .cmp(&left.document.updated_at_ms)
            })
            .then_with(|| left.document.memory_id.cmp(&right.document.memory_id))
    });

    let limit = request.max_results.clamp(1, 50);
    let max_snippet_chars = request.max_snippet_chars.clamp(80, 4000);
    let mut budget_used_chars = 0_i32;
    let mut results = Vec::new();
    let mut selected_trace = Vec::<Value>::new();
    for (rank, candidate) in scored.iter().take(limit).enumerate() {
        let snippet =
            object_snippet_for(&candidate.document.text, &query_tokens, max_snippet_chars);
        budget_used_chars += snippet.chars().count() as i32;
        let mut item = json!({
            "ref": format!("memory://rust/object/{}", candidate.document.memory_id),
            "source_kind": &candidate.document.source_kind,
            "summary": &candidate.document.summary,
            "snippet": snippet,
            "score": round6(candidate.score),
            "redacted": false,
            "memory_id": &candidate.document.memory_id,
            "layer": &candidate.document.layer,
            "title": &candidate.document.title,
            "sensitivity": &candidate.document.sensitivity,
            "visibility": &candidate.document.visibility,
            "updated_at_ms": candidate.document.updated_at_ms,
        });
        if request.explain {
            item["explain"] = json!({
                "score": round6(candidate.score),
                "lexical_score": round6(candidate.lexical_score),
                "property_boost": round6(candidate.property_boost),
                "pinned_boost": round6(candidate.pinned_boost),
                "policy_filter": "project_active_non_secret",
                "properties": &candidate.properties,
                "index_source": index_source,
                "indexed_at_ms": candidate.document.indexed_at_ms,
                "content_hash": candidate.document.content_hash,
            });
        }
        if request.explain {
            selected_trace.push(object_selection_trace_value(
                candidate,
                rank + 1,
                index_source,
            ));
        }
        results.push(item);
    }

    let truncated_items = scored.len().saturating_sub(results.len()) as i32;
    let status = if truncated_items > 0 {
        "truncated"
    } else {
        "ok"
    };
    let retrieval_trace = if request.explain {
        let selected_count = results.len();
        let omitted_count =
            skipped_policy_or_filter + skipped_secret + skipped_deleted + skipped_no_match;
        let omitted_trace_capped = omitted_trace.len() >= MEMORY_RETRIEVAL_TRACE_LIMIT;
        json!({
            "schema_version": "xhub.memory.retrieval_trace.v1",
            "source": MEMORY_OBJECT_RETRIEVAL_SOURCE,
            "index_source": index_source,
            "selected": selected_trace,
            "omitted": omitted_trace,
            "selected_count": selected_count,
            "matched_count": scored.len(),
            "omitted_count": omitted_count,
            "omitted_trace_capped": omitted_trace_capped,
            "trace_limit": MEMORY_RETRIEVAL_TRACE_LIMIT,
            "semantic_used": false,
            "rerank_used": false,
        })
    } else {
        Value::Null
    };
    Ok(Some(json!({
        "schema_version": MEMORY_RETRIEVAL_RESULT_SCHEMA,
        "request_id": &request.request_id,
        "status": status,
        "resolved_scope": "project",
        "source": MEMORY_OBJECT_RETRIEVAL_SOURCE,
        "scope": &request.scope,
        "project_id": project_id,
        "audit_ref": &request.audit_ref,
        "reason_code": "rust_memory_object_index",
        "deny_code": "",
        "results": results,
        "truncated": truncated_items > 0,
        "budget_used_chars": budget_used_chars,
        "truncated_items": truncated_items,
        "redacted_items": skipped_secret as i32,
        "retrieval_trace": retrieval_trace,
        "retrieval_engine": {
            "schema_version": "xhub.memory.hybrid_retrieval.v1",
            "stage": "uml_w6_persistent_derived_index_slice",
            "index_source": index_source,
            "index_ready": index_summary.index_ready,
            "index_row_count": index_summary.index_row_count,
            "active_indexable_object_count": index_summary.active_indexable_object_count,
            "stale_index_count": index_summary.stale_index_count,
            "latest_indexed_at_ms": index_summary.latest_indexed_at_ms,
            "index_rebuilt": index_rebuilt,
            "index_rebuild_error": index_rebuild_error,
            "semantic_used": false,
            "rerank_used": false,
            "fts": if index_source == "rust_hub_memory_object_index" { "derived_index_lexical" } else { "in_memory_lexical" },
            "property_boost": true,
            "candidate_count": scored.len()
                + skipped_policy_or_filter
                + skipped_secret
                + skipped_deleted
                + skipped_no_match,
            "matched_count": scored.len(),
            "query_token_count": query_tokens.len(),
            "filters": {
                "scope": "project",
                "project_id": project_id,
                "status": "active",
                "source_kinds": requested_source_kinds.iter().cloned().collect::<Vec<_>>(),
                "layers": requested_layers.iter().cloned().collect::<Vec<_>>(),
                "sensitivity_max": sensitivity_max,
                "visibility": visibility_filter,
                "created_after_ms": request.created_after_ms,
                "updated_after_ms": request.updated_after_ms,
            },
            "omitted": {
                "policy_or_filter": skipped_policy_or_filter,
                "secret": skipped_secret,
                "deleted_or_inactive": skipped_deleted,
                "no_match": skipped_no_match,
            },
        },
        "production_authority_change": false,
    })))
}

#[derive(Debug)]
struct ObjectRetrievalCandidate {
    document: ObjectRetrievalDocument,
    lexical_score: f64,
    property_boost: f64,
    pinned_boost: f64,
    score: f64,
    properties: BTreeMap<String, bool>,
}

#[derive(Debug, Clone)]
struct ObjectRetrievalDocument {
    memory_id: String,
    source_kind: String,
    summary: String,
    text: String,
    searchable_text: String,
    layer: String,
    title: String,
    sensitivity: String,
    visibility: String,
    status: String,
    pinned: bool,
    created_at_ms: i64,
    updated_at_ms: i64,
    indexed_at_ms: Option<i64>,
    content_hash: Option<String>,
    properties: BTreeMap<String, bool>,
}

fn memory_object_document_from_object(object: MemoryObjectRecord) -> ObjectRetrievalDocument {
    let searchable_text = format!(
        "{}\n{}\n{}\n{}",
        object.title, object.summary, object.text, object.tags_json
    );
    let properties = memory_object_properties_from_text(
        &object.title,
        &object.summary,
        &object.text,
        &object.tags_json,
    );
    ObjectRetrievalDocument {
        memory_id: object.memory_id,
        source_kind: object.source_kind,
        summary: object.summary,
        text: object.text,
        searchable_text,
        layer: object.layer,
        title: object.title,
        sensitivity: object.sensitivity,
        visibility: object.visibility,
        status: object.status,
        pinned: object.pinned,
        created_at_ms: object.created_at_ms,
        updated_at_ms: object.updated_at_ms,
        indexed_at_ms: None,
        content_hash: None,
        properties,
    }
}

fn memory_object_document_from_index(row: MemoryObjectIndexRecord) -> ObjectRetrievalDocument {
    let mut properties = BTreeMap::new();
    properties.insert("has_code".to_string(), row.has_code);
    properties.insert("has_todo".to_string(), row.has_todo);
    properties.insert("has_error".to_string(), row.has_error);
    properties.insert("has_decision".to_string(), row.has_decision);
    properties.insert("has_approval".to_string(), row.has_approval);
    properties.insert("has_blocker".to_string(), row.has_blocker);
    properties.insert("has_link".to_string(), row.has_link);
    ObjectRetrievalDocument {
        memory_id: row.memory_id,
        source_kind: row.source_kind,
        summary: row.summary,
        text: row.text,
        searchable_text: row.searchable_text,
        layer: row.layer,
        title: row.title,
        sensitivity: row.sensitivity,
        visibility: row.visibility,
        status: "active".to_string(),
        pinned: row.pinned,
        created_at_ms: row.object_created_at_ms,
        updated_at_ms: row.object_updated_at_ms,
        indexed_at_ms: Some(row.indexed_at_ms),
        content_hash: Some(row.content_hash),
        properties,
    }
}

fn object_selection_trace_value(
    candidate: &ObjectRetrievalCandidate,
    rank: usize,
    index_source: &str,
) -> Value {
    json!({
        "rank": rank,
        "ref": format!("memory://rust/object/{}", candidate.document.memory_id),
        "memory_id": &candidate.document.memory_id,
        "reason_code": "selected",
        "index_source": index_source,
        "score": round6(candidate.score),
        "lexical_score": round6(candidate.lexical_score),
        "property_boost": round6(candidate.property_boost),
        "pinned_boost": round6(candidate.pinned_boost),
        "layer": &candidate.document.layer,
        "source_kind": &candidate.document.source_kind,
        "sensitivity": &candidate.document.sensitivity,
        "visibility": &candidate.document.visibility,
        "updated_at_ms": candidate.document.updated_at_ms,
        "properties": &candidate.properties,
    })
}

fn push_object_omission_trace(
    request: &MemoryRetrievalRequest,
    trace: &mut Vec<Value>,
    document: &ObjectRetrievalDocument,
    reason_code: &str,
    index_source: &str,
) {
    if !request.explain || trace.len() >= MEMORY_RETRIEVAL_TRACE_LIMIT {
        return;
    }
    trace.push(json!({
        "ref": format!("memory://rust/object/{}", document.memory_id),
        "memory_id": &document.memory_id,
        "reason_code": reason_code,
        "index_source": index_source,
        "layer": &document.layer,
        "source_kind": &document.source_kind,
        "sensitivity": &document.sensitivity,
        "visibility": &document.visibility,
        "status": &document.status,
        "updated_at_ms": document.updated_at_ms,
        "content_redacted": true,
    }));
}

fn memory_retrieval_denied_value(request: &MemoryRetrievalRequest, deny_code: &str) -> Value {
    json!({
        "schema_version": MEMORY_RETRIEVAL_RESULT_SCHEMA,
        "request_id": &request.request_id,
        "status": "denied",
        "resolved_scope": memory_retrieval_object_scope(&request.scope),
        "source": MEMORY_OBJECT_RETRIEVAL_SOURCE,
        "scope": &request.scope,
        "audit_ref": &request.audit_ref,
        "reason_code": "fail_closed",
        "deny_code": deny_code,
        "results": [],
        "truncated": false,
        "budget_used_chars": 0,
        "truncated_items": 0,
        "redacted_items": 0,
        "production_authority_change": false,
    })
}

fn memory_retrieval_object_scope(raw: &str) -> String {
    match raw.trim().to_ascii_lowercase().replace('-', "_").as_str() {
        "project" | "project_code" | "current_project" | "project_chat" => "project".to_string(),
        "user" | "personal" | "assistant_personal" => "user".to_string(),
        "session" | "agent" | "org" | "device" => raw.trim().to_ascii_lowercase(),
        _ => "project".to_string(),
    }
}

fn memory_object_id_from_ref(raw: &str) -> Option<String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return None;
    }
    let candidate = trimmed
        .strip_prefix("memory://rust/object/")
        .unwrap_or(trimmed)
        .split(['#', '?'])
        .next()
        .unwrap_or("")
        .trim();
    if candidate.starts_with("mem_") || candidate.starts_with("memory_") {
        sanitize_public_token(candidate)
    } else {
        None
    }
}

fn normalize_memory_layer(raw: &str) -> String {
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

fn normalize_visibility_filter(raw: &str) -> String {
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

fn normalize_sensitivity_filter(raw: &str) -> String {
    normalize_enum_token(
        raw.to_string(),
        &["public", "internal", "private", "secret"],
        "",
    )
}

fn memory_sensitivity_allowed(actual: &str, max_allowed: &str) -> bool {
    sensitivity_rank(actual) <= sensitivity_rank(max_allowed)
}

fn sensitivity_rank(value: &str) -> i32 {
    match value.trim().to_ascii_lowercase().as_str() {
        "public" => 0,
        "internal" => 1,
        "private" => 2,
        "secret" => 3,
        _ => 3,
    }
}

fn memory_object_properties_from_text(
    title: &str,
    summary: &str,
    text: &str,
    tags_json: &str,
) -> BTreeMap<String, bool> {
    let lower = format!("{title}\n{summary}\n{text}\n{tags_json}").to_ascii_lowercase();
    let mut properties = BTreeMap::new();
    properties.insert(
        "has_code".to_string(),
        text.contains("```")
            || lower.contains("fn ")
            || lower.contains("func ")
            || lower.contains("class ")
            || lower.contains("struct "),
    );
    properties.insert(
        "has_todo".to_string(),
        lower.contains("todo") || lower.contains("next step") || lower.contains("next_steps"),
    );
    properties.insert(
        "has_error".to_string(),
        lower.contains("error") || lower.contains("failed") || lower.contains("exception"),
    );
    properties.insert(
        "has_decision".to_string(),
        lower.contains("decision")
            || lower.contains("decided")
            || lower.contains("choose")
            || lower.contains("chosen"),
    );
    properties.insert(
        "has_approval".to_string(),
        lower.contains("approval") || lower.contains("approved") || lower.contains("authorized"),
    );
    properties.insert(
        "has_blocker".to_string(),
        lower.contains("blocker") || lower.contains("blocked") || lower.contains("risk"),
    );
    properties.insert(
        "has_link".to_string(),
        lower.contains("http://") || lower.contains("https://") || lower.contains("memory://"),
    );
    properties
}

fn memory_object_property_boost(
    query_tokens: &[String],
    query_text: &str,
    properties: &BTreeMap<String, bool>,
    title: &str,
) -> f64 {
    let mut boost = 0.0;
    let query_lower = query_text.to_ascii_lowercase();
    if property_enabled(properties, "has_decision")
        && query_has_any(
            query_tokens,
            &query_lower,
            &["decision", "decided", "why", "choose"],
        )
    {
        boost += 0.18;
    }
    if property_enabled(properties, "has_todo")
        && query_has_any(
            query_tokens,
            &query_lower,
            &["todo", "next", "step", "plan"],
        )
    {
        boost += 0.12;
    }
    if property_enabled(properties, "has_error")
        && query_has_any(
            query_tokens,
            &query_lower,
            &["error", "fail", "failed", "bug"],
        )
    {
        boost += 0.14;
    }
    if property_enabled(properties, "has_approval")
        && query_has_any(
            query_tokens,
            &query_lower,
            &["approval", "approve", "authorized", "auth"],
        )
    {
        boost += 0.12;
    }
    if property_enabled(properties, "has_blocker")
        && query_has_any(query_tokens, &query_lower, &["blocker", "blocked", "risk"])
    {
        boost += 0.12;
    }
    if property_enabled(properties, "has_link")
        && query_has_any(query_tokens, &query_lower, &["link", "url", "ref"])
    {
        boost += 0.08;
    }
    let title_score = object_lexical_score(query_tokens, title);
    if title_score > 0.0 {
        boost += (title_score * 0.2).min(0.2);
    }
    boost
}

fn property_enabled(properties: &BTreeMap<String, bool>, key: &str) -> bool {
    properties.get(key).copied().unwrap_or(false)
}

fn query_has_any(query_tokens: &[String], query_lower: &str, needles: &[&str]) -> bool {
    needles.iter().any(|needle| {
        query_lower.contains(needle) || query_tokens.iter().any(|token| token == needle)
    })
}

fn object_lexical_score(query_tokens: &[String], text: &str) -> f64 {
    if query_tokens.is_empty() {
        return 0.05;
    }
    let doc_tokens = object_retrieval_tokens(text)
        .into_iter()
        .collect::<BTreeSet<_>>();
    if doc_tokens.is_empty() {
        return 0.0;
    }
    let matches = query_tokens
        .iter()
        .filter(|token| doc_tokens.contains(*token))
        .count();
    if matches == 0 {
        return 0.0;
    }
    let coverage = matches as f64 / query_tokens.len().max(1) as f64;
    let density = matches as f64 / doc_tokens.len().max(1) as f64;
    (coverage * 0.88) + (density * 0.12)
}

fn object_retrieval_tokens(text: &str) -> Vec<String> {
    let mut tokens = BTreeSet::new();
    let mut current = String::new();
    for ch in text.chars() {
        if ch.is_alphanumeric() || ch == '_' || ch == '-' {
            current.push(ch.to_ascii_lowercase());
        } else {
            push_object_token(&mut tokens, &mut current);
        }
    }
    push_object_token(&mut tokens, &mut current);
    tokens.into_iter().collect()
}

fn push_object_token(tokens: &mut BTreeSet<String>, current: &mut String) {
    let token = current.trim_matches('-').to_string();
    if token.chars().count() >= 2 {
        tokens.insert(token);
    }
    current.clear();
}

fn object_snippet_for(text: &str, query_tokens: &[String], max_chars: usize) -> String {
    let lower = text.to_ascii_lowercase();
    let start_byte = query_tokens
        .iter()
        .filter_map(|token| lower.find(token))
        .min()
        .unwrap_or(0);
    let start_char = text[..start_byte.min(text.len())].chars().count();
    let window_start = start_char.saturating_sub(max_chars / 5);
    text.chars()
        .skip(window_start)
        .take(max_chars)
        .collect::<String>()
        .replace('\n', " ")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

fn first_non_empty_text(values: &[&str]) -> String {
    values
        .iter()
        .map(|value| value.trim())
        .find(|value| !value.is_empty())
        .unwrap_or("")
        .to_string()
}

fn round6(value: f64) -> f64 {
    (value * 1_000_000.0).round() / 1_000_000.0
}

fn write_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
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

fn object_index_rebuild_cli_json(config: &HubConfig) -> Result<String, String> {
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

pub fn object_collection_http_json(
    config: &HubConfig,
    method: &str,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    match method {
        "POST" => match create_memory_object_json_from_body(config, body) {
            Ok(body) => ("200 OK", format!("{body}\n")),
            Err(HttpJsonError { status, body }) => (status, format!("{body}\n")),
        },
        "GET" => match list_memory_objects_json(config, query) {
            Ok(body) => ("200 OK", format!("{body}\n")),
            Err(HttpJsonError { status, body }) => (status, format!("{body}\n")),
        },
        _ => (
            "405 Method Not Allowed",
            json!({
                "schema_version": MEMORY_OBJECT_RESULT_SCHEMA,
                "ok": false,
                "status": "error",
                "error_code": "method_not_allowed",
            })
            .to_string()
                + "\n",
        ),
    }
}

pub fn object_item_http_json(
    config: &HubConfig,
    route_path: &str,
    method: &str,
    query: &str,
) -> (&'static str, String) {
    let Some(suffix) = route_path.strip_prefix("/memory/objects/") else {
        return (
            "404 Not Found",
            json!({
                "schema_version": MEMORY_OBJECT_RESULT_SCHEMA,
                "ok": false,
                "status": "not_found",
                "error_code": "memory_object_route_not_found",
            })
            .to_string()
                + "\n",
        );
    };
    let (memory_id, action) = suffix.split_once('/').unwrap_or((suffix, ""));
    let memory_id = percent_decode(memory_id).unwrap_or_else(|_| memory_id.to_string());
    if action == "history" {
        if method != "GET" {
            return (
                "405 Method Not Allowed",
                json!({
                    "schema_version": MEMORY_OBJECT_HISTORY_SCHEMA,
                    "ok": false,
                    "status": "error",
                    "error_code": "method_not_allowed",
                    "memory_id": memory_id,
                })
                .to_string()
                    + "\n",
            );
        }
        return match memory_object_history_json(config, &memory_id, query) {
            Ok(body) => ("200 OK", format!("{body}\n")),
            Err(HttpJsonError { status, body }) => (status, format!("{body}\n")),
        };
    }
    if !action.is_empty() {
        return (
            "404 Not Found",
            json!({
                "schema_version": MEMORY_OBJECT_RESULT_SCHEMA,
                "ok": false,
                "status": "not_found",
                "error_code": "memory_object_action_not_implemented",
                "memory_id": memory_id,
                "action": action,
            })
            .to_string()
                + "\n",
        );
    }
    match method {
        "GET" => match get_memory_object_json(config, &memory_id) {
            Ok(body) => ("200 OK", format!("{body}\n")),
            Err(HttpJsonError { status, body }) => (status, format!("{body}\n")),
        },
        _ => (
            "501 Not Implemented",
            json!({
                "schema_version": MEMORY_OBJECT_RESULT_SCHEMA,
                "ok": false,
                "status": "not_implemented",
                "error_code": "memory_object_mutation_not_implemented_in_first_slice",
                "memory_id": memory_id,
                "supported_now": ["GET", "GET /history"],
            })
            .to_string()
                + "\n",
        ),
    }
}

pub fn object_index_rebuild_http_json(config: &HubConfig, method: &str) -> (&'static str, String) {
    if method != "POST" {
        return (
            "405 Method Not Allowed",
            json!({
                "schema_version": "xhub.memory.object_index_rebuild.v1",
                "ok": false,
                "status": "error",
                "error_code": "method_not_allowed",
            })
            .to_string()
                + "\n",
        );
    }
    match object_index_rebuild_cli_json(config) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "500 Internal Server Error",
            json!({
                "schema_version": "xhub.memory.object_index_rebuild.v1",
                "ok": false,
                "status": "error",
                "error_code": "memory_object_index_rebuild_failed",
                "message": err,
                "production_authority_change": false,
            })
            .to_string()
                + "\n",
        ),
    }
}

pub fn policy_evaluate_http_json(body: &str) -> (&'static str, String) {
    let parsed = match parse_json_body(body) {
        Ok(value) => value,
        Err(err) => return (err.status, format!("{}\n", err.body)),
    };
    let result = evaluate_memory_policy_json(&parsed);
    ("200 OK", format!("{result}\n"))
}

pub fn project_canonical_sync_http_json(
    config: &HubConfig,
    method: &str,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    if method != "POST" {
        return (
            "405 Method Not Allowed",
            json!({
                "schema_version": MEMORY_PROJECT_CANONICAL_SYNC_SCHEMA,
                "ok": false,
                "status": "error",
                "error_code": "method_not_allowed",
            })
            .to_string()
                + "\n",
        );
    }
    let parsed = match parse_json_body(body) {
        Ok(value) => value,
        Err(err) => return (err.status, format!("{}\n", err.body)),
    };
    let apply = query_bool(query, "apply", false) && !query_bool(query, "dry_run", false);
    match project_canonical_sync_json_from_value(config, &parsed, apply) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(HttpJsonError { status, body }) => (status, format!("{body}\n")),
    }
}

pub fn memory_gateway_prepare_http_json(
    config: &HubConfig,
    method: &str,
    body: &str,
) -> (&'static str, String) {
    if method != "POST" {
        return (
            "405 Method Not Allowed",
            json!({
                "schema_version": MEMORY_GATEWAY_PREPARE_SCHEMA,
                "ok": false,
                "status": "error",
                "error_code": "method_not_allowed",
            })
            .to_string()
                + "\n",
        );
    }
    let parsed = match parse_json_body(body) {
        Ok(value) => value,
        Err(err) => return (err.status, format!("{}\n", err.body)),
    };
    match memory_gateway_prepare_json_from_value(config, &parsed) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(HttpJsonError { status, body }) => (status, format!("{body}\n")),
    }
}

fn create_memory_object_json_from_body(
    config: &HubConfig,
    body: &str,
) -> Result<String, HttpJsonError> {
    apply_baseline_migrations(&config.db_path).map_err(|err| {
        http_json_error(
            "500 Internal Server Error",
            "memory_object_migration_failed",
            err.to_string(),
        )
    })?;
    let parsed = parse_json_body(body)?;
    let policy = evaluate_memory_policy(&parsed);
    if policy.decision != "allow" {
        return Err(http_json_error_json(
            "403 Forbidden",
            json!({
                "schema_version": MEMORY_OBJECT_RESULT_SCHEMA,
                "ok": false,
                "status": "denied",
                "deny_code": policy.deny_code,
                "policy": policy.to_json(),
            }),
        ));
    }

    let now = now_ms_i64();
    let memory_id = value_string(&parsed, "memory_id")
        .or_else(|| value_string(&parsed, "memoryId"))
        .unwrap_or_else(next_memory_id);
    let audit_ref = value_string(&parsed, "audit_ref")
        .or_else(|| value_string(&parsed, "auditRef"))
        .unwrap_or_default();
    let scope = normalize_enum_token(
        value_string(&parsed, "scope").unwrap_or_else(|| "project".to_string()),
        &["user", "project", "session", "agent", "org", "device"],
        "project",
    );
    let owner_id = sanitize_public_token(
        &value_string(&parsed, "owner_id")
            .or_else(|| value_string(&parsed, "ownerId"))
            .or_else(|| value_string(&parsed, "project_id"))
            .or_else(|| value_string(&parsed, "projectId"))
            .unwrap_or_default(),
    )
    .ok_or_else(|| {
        http_json_error(
            "400 Bad Request",
            "memory_owner_id_required",
            "owner_id or project_id is required".to_string(),
        )
    })?;
    let run_id = optional_public_token(&parsed, "run_id")
        .or_else(|| optional_public_token(&parsed, "runId"));
    let project_id = optional_public_token(&parsed, "project_id")
        .or_else(|| optional_public_token(&parsed, "projectId"));
    let agent_id = optional_public_token(&parsed, "agent_id")
        .or_else(|| optional_public_token(&parsed, "agentId"));
    let source_kind = normalize_source_kind_for_object(
        value_string(&parsed, "source_kind")
            .or_else(|| value_string(&parsed, "sourceKind"))
            .unwrap_or_else(|| "project_capsule".to_string())
            .as_str(),
    );
    let layer = normalize_enum_token(
        value_string(&parsed, "layer").unwrap_or_else(|| "l1_canonical".to_string()),
        &[
            "l0_constitution",
            "l1_canonical",
            "l2_observations",
            "l3_working_set",
            "l4_raw_evidence",
        ],
        "l1_canonical",
    );
    let sensitivity = normalize_enum_token(
        value_string(&parsed, "sensitivity").unwrap_or_else(|| "internal".to_string()),
        &["public", "internal", "private", "secret"],
        "internal",
    );
    if sensitivity == "secret" {
        return Err(http_json_error(
            "403 Forbidden",
            "memory_secret_sensitivity_denied",
            "secret memory objects cannot be created through this endpoint".to_string(),
        ));
    }
    let visibility = normalize_enum_token(
        value_string(&parsed, "visibility").unwrap_or_else(|| "local_only".to_string()),
        &[
            "local_only",
            "sanitized_remote_ok",
            "refs_only",
            "never_export",
        ],
        "local_only",
    );
    let status = normalize_enum_token(
        value_string(&parsed, "status").unwrap_or_else(|| "active".to_string()),
        &["active", "candidate", "archived", "deleted", "rejected"],
        "active",
    );
    let title =
        sanitize_public_text_value(&parsed, "title").unwrap_or_else(|| "Memory".to_string());
    let text = value_string(&parsed, "text")
        .or_else(|| value_string(&parsed, "content"))
        .unwrap_or_default()
        .trim()
        .to_string();
    if text.is_empty() {
        return Err(http_json_error(
            "400 Bad Request",
            "memory_text_required",
            "text is required".to_string(),
        ));
    }
    if text.len() > 32 * 1024 {
        return Err(http_json_error(
            "400 Bad Request",
            "memory_text_too_large",
            "text exceeds memory object limit".to_string(),
        ));
    }
    if looks_like_secret_public(&text)
        || looks_like_secret_public(&title)
        || looks_like_secret_public(&audit_ref)
    {
        return Err(http_json_error(
            "403 Forbidden",
            "memory_secret_pattern_denied",
            "secret-like memory object content denied".to_string(),
        ));
    }
    let tags = value_string_list(&parsed, "tags").unwrap_or_default();
    if tags.iter().any(|tag| looks_like_secret_public(tag)) {
        return Err(http_json_error(
            "403 Forbidden",
            "memory_secret_pattern_denied",
            "secret-like memory object tag denied".to_string(),
        ));
    }
    let summary = sanitize_public_text(
        value_string(&parsed, "summary")
            .unwrap_or_else(|| summarize_memory_text(&text))
            .as_str(),
        480,
    )
    .unwrap_or_else(|| summarize_memory_text(&text));
    let actor = sanitize_public_token(
        value_string(&parsed, "actor")
            .unwrap_or_else(|| "rust_hub".to_string())
            .as_str(),
    )
    .unwrap_or_else(|| "rust_hub".to_string());
    let provenance_json = json!({
        "source": value_string(&parsed, "source").unwrap_or_else(|| "rust_universal_memory_api".to_string()),
        "audit_ref": audit_ref,
        "created_by": actor,
        "evidence_refs": value_string_list(&parsed, "evidence_refs")
            .or_else(|| value_string_list(&parsed, "evidenceRefs"))
            .unwrap_or_default(),
    })
    .to_string();
    let policy_json = json!({
        "write_gate": if memory_writer_authority_enabled() { "canonical_writer" } else { "object_store_shadow" },
        "allowed_roles": &policy.allowed_roles,
        "denied_roles": &policy.denied_roles,
        "remote_export": &visibility,
    })
    .to_string();
    let object = MemoryObjectRecord {
        memory_id: memory_id.clone(),
        schema_version: MEMORY_OBJECT_SCHEMA.to_string(),
        scope: scope.clone(),
        owner_id: owner_id.clone(),
        run_id,
        project_id,
        agent_id,
        source_kind,
        layer,
        title,
        text,
        summary,
        tags_json: json!(tags).to_string(),
        sensitivity,
        visibility,
        status,
        pinned: value_bool(&parsed, "pinned", false),
        immutable: value_bool(&parsed, "immutable", false),
        ttl_ms: value_i64(&parsed, "ttl_ms").or_else(|| value_i64(&parsed, "ttlMs")),
        created_at_ms: now,
        updated_at_ms: now,
        last_accessed_at_ms: now,
        version: 1,
        provenance_json,
        policy_json,
    };
    let after_json = memory_object_to_json(&object).to_string();
    let event = MemoryEventRecord {
        event_id: next_memory_event_id(),
        memory_id: memory_id.clone(),
        operation: "create".to_string(),
        actor,
        reason: value_string(&parsed, "reason")
            .unwrap_or_else(|| "memory_object_create".to_string()),
        before_version: None,
        after_version: Some(1),
        before_json: None,
        after_json: Some(after_json),
        policy_decision: "allow".to_string(),
        deny_code: String::new(),
        audit_ref: audit_ref.clone(),
        created_at_ms: now,
    };
    create_memory_object_with_event(&config.db_path, &object, &event).map_err(|err| {
        let message = err.to_string();
        if message.contains("UNIQUE constraint failed") {
            http_json_error("409 Conflict", "memory_object_already_exists", message)
        } else {
            http_json_error(
                "500 Internal Server Error",
                "memory_object_create_failed",
                message,
            )
        }
    })?;
    Ok(json!({
        "schema_version": MEMORY_OBJECT_RESULT_SCHEMA,
        "ok": true,
        "status": "created",
        "memory_id": memory_id,
        "version": 1,
        "event_id": event.event_id,
        "deny_code": "",
        "audit_ref": audit_ref,
        "policy": policy.to_json(),
        "object": memory_object_to_json(&object),
    })
    .to_string())
}

fn get_memory_object_json(config: &HubConfig, memory_id: &str) -> Result<String, HttpJsonError> {
    let memory_id = sanitize_public_token(memory_id).ok_or_else(|| {
        http_json_error(
            "400 Bad Request",
            "memory_id_required",
            "memory_id is required".to_string(),
        )
    })?;
    let object = read_memory_object(&config.db_path, &memory_id).map_err(|err| {
        http_json_error(
            "500 Internal Server Error",
            "memory_object_read_failed",
            err.to_string(),
        )
    })?;
    let Some(object) = object else {
        return Err(http_json_error_json(
            "404 Not Found",
            json!({
                "schema_version": MEMORY_OBJECT_RESULT_SCHEMA,
                "ok": false,
                "status": "not_found",
                "memory_id": memory_id,
                "error_code": "memory_object_not_found",
            }),
        ));
    };
    Ok(json!({
        "schema_version": MEMORY_OBJECT_RESULT_SCHEMA,
        "ok": true,
        "status": "ok",
        "memory_id": memory_id,
        "object": memory_object_to_json(&object),
    })
    .to_string())
}

fn list_memory_objects_json(config: &HubConfig, query: &str) -> Result<String, HttpJsonError> {
    let filter = MemoryObjectListFilter {
        scope: query_param(query, "scope"),
        owner_id: query_param(query, "owner_id").or_else(|| query_param(query, "ownerId")),
        project_id: query_param(query, "project_id").or_else(|| query_param(query, "projectId")),
        agent_id: query_param(query, "agent_id").or_else(|| query_param(query, "agentId")),
        source_kind: query_param(query, "source_kind").or_else(|| query_param(query, "sourceKind")),
        layer: query_param(query, "layer"),
        status: Some(query_param(query, "status").unwrap_or_else(|| "active".to_string())),
        sensitivity: query_param(query, "sensitivity"),
        visibility: query_param(query, "visibility"),
        limit: query_usize(query, "limit", 50).unwrap_or(50),
    };
    let objects = list_memory_objects(&config.db_path, &filter).map_err(|err| {
        http_json_error(
            "500 Internal Server Error",
            "memory_object_list_failed",
            err.to_string(),
        )
    })?;
    let items = objects
        .iter()
        .map(memory_object_to_json)
        .collect::<Vec<_>>();
    Ok(json!({
        "schema_version": MEMORY_OBJECT_LIST_SCHEMA,
        "ok": true,
        "status": "ok",
        "count": items.len(),
        "objects": items,
        "filter": {
            "scope": filter.scope,
            "owner_id": filter.owner_id,
            "project_id": filter.project_id,
            "agent_id": filter.agent_id,
            "source_kind": filter.source_kind,
            "layer": filter.layer,
            "status": filter.status,
            "sensitivity": filter.sensitivity,
            "visibility": filter.visibility,
            "limit": filter.limit,
        },
    })
    .to_string())
}

fn memory_object_history_json(
    config: &HubConfig,
    memory_id: &str,
    query: &str,
) -> Result<String, HttpJsonError> {
    let memory_id = sanitize_public_token(memory_id).ok_or_else(|| {
        http_json_error(
            "400 Bad Request",
            "memory_id_required",
            "memory_id is required".to_string(),
        )
    })?;
    let limit = query_usize(query, "limit", 50).unwrap_or(50);
    let events = read_memory_object_history(&config.db_path, &memory_id, limit).map_err(|err| {
        http_json_error(
            "500 Internal Server Error",
            "memory_object_history_failed",
            err.to_string(),
        )
    })?;
    let items = events.iter().map(memory_event_to_json).collect::<Vec<_>>();
    Ok(json!({
        "schema_version": MEMORY_OBJECT_HISTORY_SCHEMA,
        "ok": true,
        "status": "ok",
        "memory_id": memory_id,
        "count": items.len(),
        "events": items,
    })
    .to_string())
}

#[derive(Debug, Clone)]
struct ProjectCanonicalSyncPlan {
    key: String,
    memory_id: String,
    operation: String,
    reason_code: String,
    object: Option<MemoryObjectRecord>,
    event: Option<MemoryEventRecord>,
}

fn project_canonical_sync_json_from_value(
    config: &HubConfig,
    body: &Value,
    apply: bool,
) -> Result<String, HttpJsonError> {
    apply_baseline_migrations(&config.db_path).map_err(|err| {
        http_json_error(
            "500 Internal Server Error",
            "memory_object_migration_failed",
            err.to_string(),
        )
    })?;
    let payload = body
        .get("project_canonical_memory")
        .or_else(|| body.get("projectCanonicalMemory"))
        .unwrap_or(body);
    let project_id = sanitize_public_token(
        &value_string(payload, "project_id")
            .or_else(|| value_string(payload, "projectId"))
            .unwrap_or_default(),
    )
    .ok_or_else(|| {
        http_json_error(
            "400 Bad Request",
            "project_id_required",
            "project_id is required".to_string(),
        )
    })?;
    let display_name = sanitize_public_text(
        &value_string(payload, "display_name")
            .or_else(|| value_string(payload, "displayName"))
            .unwrap_or_default(),
        240,
    )
    .unwrap_or_else(|| project_id.clone());
    let audit_ref = value_string(body, "audit_ref")
        .or_else(|| value_string(body, "auditRef"))
        .or_else(|| value_string(payload, "audit_ref"))
        .or_else(|| value_string(payload, "auditRef"))
        .unwrap_or_else(|| format!("project_canonical_sync:{project_id}"));
    let items = payload
        .get("items")
        .and_then(Value::as_array)
        .ok_or_else(|| {
            http_json_error(
                "400 Bad Request",
                "canonical_memory_items_required",
                "items array is required".to_string(),
            )
        })?;
    if items.len() > 128 {
        return Err(http_json_error(
            "400 Bad Request",
            "canonical_memory_items_too_many",
            "items exceeds 128".to_string(),
        ));
    }

    let mut plans = Vec::<ProjectCanonicalSyncPlan>::new();
    for item in items {
        let raw_key = value_string(item, "key").unwrap_or_default();
        let raw_value = value_string(item, "value").unwrap_or_default();
        let Some(kind) = project_canonical_item_kind(&raw_key) else {
            plans.push(ProjectCanonicalSyncPlan {
                key: raw_key,
                memory_id: String::new(),
                operation: "skip".to_string(),
                reason_code: "canonical_memory_metadata_or_unknown_key".to_string(),
                object: None,
                event: None,
            });
            continue;
        };
        let Some(text) = sanitize_public_text(&raw_value, 32 * 1024) else {
            plans.push(ProjectCanonicalSyncPlan {
                key: raw_key,
                memory_id: String::new(),
                operation: "deny".to_string(),
                reason_code: "memory_secret_pattern_denied".to_string(),
                object: None,
                event: None,
            });
            continue;
        };
        let policy = evaluate_memory_policy(&json!({
            "requester_role": "tool",
            "use_mode": "tool_plan",
            "scope": "project",
            "requested_layers": [kind.layer],
            "requested_source_kinds": [kind.source_kind],
        }));
        if policy.decision != "allow" {
            plans.push(ProjectCanonicalSyncPlan {
                key: raw_key,
                memory_id: String::new(),
                operation: "deny".to_string(),
                reason_code: policy.deny_code,
                object: None,
                event: None,
            });
            continue;
        }

        let memory_id = project_canonical_memory_id(&project_id, kind.suffix);
        let existing = read_memory_object(&config.db_path, &memory_id).map_err(|err| {
            http_json_error(
                "500 Internal Server Error",
                "memory_object_read_failed",
                err.to_string(),
            )
        })?;
        if let Some(existing) = existing {
            if existing.immutable {
                plans.push(ProjectCanonicalSyncPlan {
                    key: raw_key,
                    memory_id,
                    operation: "deny".to_string(),
                    reason_code: "memory_object_immutable".to_string(),
                    object: None,
                    event: None,
                });
                continue;
            }
            if existing.text == text
                && existing.title == kind.title
                && existing.source_kind == kind.source_kind
                && existing.layer == kind.layer
                && existing.status == "active"
            {
                plans.push(ProjectCanonicalSyncPlan {
                    key: raw_key,
                    memory_id,
                    operation: "unchanged".to_string(),
                    reason_code: String::new(),
                    object: None,
                    event: None,
                });
                continue;
            }
            let now = now_ms_i64();
            let before_json = memory_object_to_json(&existing).to_string();
            let mut object = existing.clone();
            object.source_kind = kind.source_kind.to_string();
            object.layer = kind.layer.to_string();
            object.title = kind.title.to_string();
            object.text = text.clone();
            object.summary = summarize_memory_text(&text);
            object.tags_json = json!(["canonical_sync", "ax_memory", kind.suffix]).to_string();
            object.status = "active".to_string();
            object.updated_at_ms = now;
            object.last_accessed_at_ms = now;
            object.version = existing.version.saturating_add(1);
            object.provenance_json = json!({
                "source": "xt_project_canonical_memory_sync",
                "audit_ref": audit_ref,
                "created_by": "rust_hub",
                "evidence_refs": [],
                "project_display_name": display_name,
            })
            .to_string();
            let after_json = memory_object_to_json(&object).to_string();
            let event = MemoryEventRecord {
                event_id: next_memory_event_id(),
                memory_id: memory_id.clone(),
                operation: "update".to_string(),
                actor: "rust_hub".to_string(),
                reason: "project_canonical_memory_sync".to_string(),
                before_version: Some(existing.version),
                after_version: Some(object.version),
                before_json: Some(before_json),
                after_json: Some(after_json),
                policy_decision: "allow".to_string(),
                deny_code: String::new(),
                audit_ref: audit_ref.clone(),
                created_at_ms: now,
            };
            plans.push(ProjectCanonicalSyncPlan {
                key: raw_key,
                memory_id,
                operation: "update".to_string(),
                reason_code: String::new(),
                object: Some(object),
                event: Some(event),
            });
        } else {
            let now = now_ms_i64();
            let policy_json = json!({
                "write_gate": if memory_writer_authority_enabled() { "canonical_writer" } else { "object_store_shadow" },
                "allowed_roles": policy.allowed_roles,
                "denied_roles": policy.denied_roles,
                "remote_export": "local_only",
            })
            .to_string();
            let provenance_json = json!({
                "source": "xt_project_canonical_memory_sync",
                "audit_ref": audit_ref,
                "created_by": "rust_hub",
                "evidence_refs": [],
                "project_display_name": display_name,
            })
            .to_string();
            let object = MemoryObjectRecord {
                memory_id: memory_id.clone(),
                schema_version: MEMORY_OBJECT_SCHEMA.to_string(),
                scope: "project".to_string(),
                owner_id: project_id.clone(),
                run_id: None,
                project_id: Some(project_id.clone()),
                agent_id: None,
                source_kind: kind.source_kind.to_string(),
                layer: kind.layer.to_string(),
                title: kind.title.to_string(),
                text: text.clone(),
                summary: summarize_memory_text(&text),
                tags_json: json!(["canonical_sync", "ax_memory", kind.suffix]).to_string(),
                sensitivity: "internal".to_string(),
                visibility: "local_only".to_string(),
                status: "active".to_string(),
                pinned: false,
                immutable: false,
                ttl_ms: None,
                created_at_ms: now,
                updated_at_ms: now,
                last_accessed_at_ms: now,
                version: 1,
                provenance_json,
                policy_json,
            };
            let after_json = memory_object_to_json(&object).to_string();
            let event = MemoryEventRecord {
                event_id: next_memory_event_id(),
                memory_id: memory_id.clone(),
                operation: "create".to_string(),
                actor: "rust_hub".to_string(),
                reason: "project_canonical_memory_sync".to_string(),
                before_version: None,
                after_version: Some(1),
                before_json: None,
                after_json: Some(after_json),
                policy_decision: "allow".to_string(),
                deny_code: String::new(),
                audit_ref: audit_ref.clone(),
                created_at_ms: now,
            };
            plans.push(ProjectCanonicalSyncPlan {
                key: raw_key,
                memory_id,
                operation: "create".to_string(),
                reason_code: String::new(),
                object: Some(object),
                event: Some(event),
            });
        }
    }

    let blocking_count = plans.iter().filter(|plan| plan.operation == "deny").count();
    if apply && blocking_count > 0 {
        return Err(http_json_error_json(
            "403 Forbidden",
            project_canonical_sync_response(&project_id, true, false, &plans, blocking_count),
        ));
    }
    if apply {
        for plan in &plans {
            let Some(object) = plan.object.as_ref() else {
                continue;
            };
            let Some(event) = plan.event.as_ref() else {
                continue;
            };
            match plan.operation.as_str() {
                "create" => create_memory_object_with_event(&config.db_path, object, event),
                "update" => update_memory_object_with_event(&config.db_path, object, event),
                _ => Ok(()),
            }
            .map_err(|err| {
                http_json_error(
                    "500 Internal Server Error",
                    "project_canonical_memory_apply_failed",
                    err.to_string(),
                )
            })?;
        }
    }

    Ok(
        project_canonical_sync_response(&project_id, apply, apply, &plans, blocking_count)
            .to_string(),
    )
}

fn project_canonical_sync_response(
    project_id: &str,
    apply_requested: bool,
    applied: bool,
    plans: &[ProjectCanonicalSyncPlan],
    blocking_count: usize,
) -> Value {
    let created_count = plans
        .iter()
        .filter(|plan| plan.operation == "create")
        .count();
    let updated_count = plans
        .iter()
        .filter(|plan| plan.operation == "update")
        .count();
    let unchanged_count = plans
        .iter()
        .filter(|plan| plan.operation == "unchanged")
        .count();
    let skipped_count = plans.iter().filter(|plan| plan.operation == "skip").count();
    json!({
        "schema_version": MEMORY_PROJECT_CANONICAL_SYNC_SCHEMA,
        "ok": blocking_count == 0,
        "status": if blocking_count == 0 { "ok" } else { "denied" },
        "project_id": project_id,
        "apply_requested": apply_requested,
        "dry_run": !apply_requested,
        "applied": applied,
        "planned_count": plans.len(),
        "created_count": created_count,
        "updated_count": updated_count,
        "unchanged_count": unchanged_count,
        "skipped_count": skipped_count,
        "blocking_count": blocking_count,
        "items": plans.iter().map(|plan| {
            json!({
                "key": &plan.key,
                "memory_id": if plan.memory_id.is_empty() { Value::Null } else { json!(&plan.memory_id) },
                "operation": &plan.operation,
                "reason_code": &plan.reason_code,
            })
        }).collect::<Vec<_>>(),
    })
}

fn memory_gateway_prepare_json_from_value(
    config: &HubConfig,
    body: &Value,
) -> Result<String, HttpJsonError> {
    let requester_role = value_string(body, "requester_role")
        .or_else(|| value_string(body, "requesterRole"))
        .unwrap_or_else(|| "chat".to_string());
    let use_mode = value_string(body, "use_mode")
        .or_else(|| value_string(body, "useMode"))
        .or_else(|| value_string(body, "mode"))
        .unwrap_or_else(|| "project_chat".to_string());
    let scope = normalize_enum_token(
        value_string(body, "scope").unwrap_or_else(|| "project".to_string()),
        &["user", "project", "session", "agent", "org", "device"],
        "unknown",
    );
    let remote_export_requested = value_bool(body, "remote_export_requested", false)
        || value_bool(body, "remoteExportRequested", false);
    let requested_layers = value_string_list(body, "requested_layers")
        .or_else(|| value_string_list(body, "requestedLayers"))
        .unwrap_or_default();
    let requested_source_kinds = value_string_list(body, "requested_source_kinds")
        .or_else(|| value_string_list(body, "requestedSourceKinds"))
        .unwrap_or_default();
    let latest_user = value_string(body, "latest_user")
        .or_else(|| value_string(body, "latestUser"))
        .or_else(|| value_string(body, "query"))
        .unwrap_or_default();
    if looks_like_secret_public(&latest_user) {
        return Err(gateway_json_error(
            "403 Forbidden",
            "memory_gateway_secret_like_query_denied",
            "secret-like latest_user/query denied".to_string(),
        ));
    }

    let policy_body = json!({
        "requester_role": requester_role,
        "use_mode": use_mode,
        "scope": scope,
        "remote_export_requested": remote_export_requested,
        "requested_layers": &requested_layers,
        "requested_source_kinds": &requested_source_kinds,
    });
    let policy = evaluate_memory_policy(&policy_body);
    if policy.decision != "allow" {
        return Err(http_json_error_json(
            "403 Forbidden",
            json!({
                "schema_version": MEMORY_GATEWAY_PREPARE_SCHEMA,
                "ok": false,
                "status": "denied",
                "deny_code": &policy.deny_code,
                "policy": policy.to_json(),
            }),
        ));
    }

    let project_id = value_string(body, "project_id")
        .or_else(|| value_string(body, "projectId"))
        .and_then(|value| sanitize_public_token(&value))
        .unwrap_or_default();
    let agent_id = value_string(body, "agent_id")
        .or_else(|| value_string(body, "agentId"))
        .and_then(|value| sanitize_public_token(&value));
    if policy.scope == "project" && project_id.is_empty() {
        return Err(gateway_json_error(
            "400 Bad Request",
            "memory_gateway_project_id_required",
            "project_id is required for project scope".to_string(),
        ));
    }

    let max_items = value_usize(body, "max_items")
        .or_else(|| value_usize(body, "maxItems"))
        .unwrap_or(12)
        .clamp(1, 64);
    let max_snippet_chars = value_usize(body, "max_snippet_chars")
        .or_else(|| value_usize(body, "maxSnippetChars"))
        .unwrap_or(420)
        .clamp(80, 2_000);
    let read_limit = value_usize(body, "read_limit")
        .or_else(|| value_usize(body, "readLimit"))
        .unwrap_or(max_items.saturating_mul(4))
        .clamp(max_items, 500);
    let allowed_layers = gateway_allowed_layers(&policy, &requested_layers);
    if allowed_layers.is_empty() {
        return Err(gateway_json_error(
            "403 Forbidden",
            "memory_gateway_no_allowed_layers",
            "no requested memory layers are allowed by Rust policy".to_string(),
        ));
    }
    let requested_source_filter = gateway_requested_source_kinds(&requested_source_kinds);

    let filter = MemoryObjectListFilter {
        scope: Some(policy.scope.clone()),
        owner_id: None,
        project_id: if project_id.is_empty() {
            None
        } else {
            Some(project_id.clone())
        },
        agent_id,
        source_kind: None,
        layer: None,
        status: Some("active".to_string()),
        sensitivity: None,
        visibility: None,
        limit: read_limit,
    };
    let objects = list_memory_objects(&config.db_path, &filter).map_err(|err| {
        gateway_json_error(
            "500 Internal Server Error",
            "memory_gateway_object_list_failed",
            err.to_string(),
        )
    })?;

    let mut selected = Vec::new();
    let mut skipped_for_policy = 0usize;
    let mut skipped_for_remote_visibility = 0usize;
    let mut skipped_secret = 0usize;
    for object in objects {
        if selected.len() >= max_items {
            break;
        }
        if object.sensitivity == "secret" {
            skipped_secret += 1;
            continue;
        }
        if !allowed_layers.iter().any(|layer| layer == &object.layer) {
            skipped_for_policy += 1;
            continue;
        }
        if !requested_source_filter.is_empty()
            && !requested_source_filter
                .iter()
                .any(|source_kind| source_kind == &object.source_kind)
        {
            skipped_for_policy += 1;
            continue;
        }
        if remote_export_requested && object.visibility != "sanitized_remote_ok" {
            skipped_for_remote_visibility += 1;
            continue;
        }
        selected.push(object);
    }

    let mut slots: BTreeMap<String, Vec<Value>> = BTreeMap::new();
    for object in &selected {
        slots
            .entry(object.layer.clone())
            .or_default()
            .push(gateway_memory_object_to_json(object, max_snippet_chars));
    }
    let slot_values = slots
        .iter()
        .map(|(layer, objects)| {
            json!({
                "layer": layer,
                "count": objects.len(),
                "objects": objects,
            })
        })
        .collect::<Vec<_>>();
    let context_text = gateway_context_text(&selected, max_snippet_chars);

    Ok(json!({
        "schema_version": MEMORY_GATEWAY_PREPARE_SCHEMA,
        "ok": true,
        "status": "prepared",
        "source": "rust_memory_gateway_prepare",
        "mode": "prepare_only_no_model_call",
        "production_authority_change": false,
        "requester_role": &policy.requester_role,
        "use_mode": &policy.use_mode,
        "scope": &policy.scope,
        "project_id": if project_id.is_empty() { Value::Null } else { json!(project_id) },
        "remote_export_requested": remote_export_requested,
        "query_present": !latest_user.is_empty(),
        "policy": policy.to_json(),
        "object_count": selected.len(),
        "max_items": max_items,
        "max_snippet_chars": max_snippet_chars,
        "requested_layers": requested_layers,
        "effective_layers": allowed_layers,
        "requested_source_kinds": requested_source_kinds,
        "slots": slot_values,
        "context_text": context_text,
        "skipped": {
            "policy_or_filter": skipped_for_policy,
            "remote_visibility": skipped_for_remote_visibility,
            "secret": skipped_secret,
        },
    })
    .to_string())
}

fn evaluate_memory_policy_json(body: &Value) -> String {
    evaluate_memory_policy(body).to_json().to_string()
}

fn evaluate_memory_policy(body: &Value) -> MemoryPolicyEvaluation {
    let requester_role = normalize_enum_token(
        value_string(body, "requester_role")
            .or_else(|| value_string(body, "requesterRole"))
            .unwrap_or_else(|| "chat".to_string()),
        &[
            "chat",
            "session",
            "supervisor",
            "tool",
            "lane",
            "remote_export",
        ],
        "unknown",
    );
    let use_mode = normalize_enum_token(
        value_string(body, "use_mode")
            .or_else(|| value_string(body, "useMode"))
            .or_else(|| value_string(body, "mode"))
            .unwrap_or_else(|| "project_chat".to_string()),
        &[
            "project_chat",
            "session_resume",
            "supervisor_orchestration",
            "tool_plan",
            "tool_act_low_risk",
            "tool_act_high_risk",
            "lane_handoff",
            "remote_prompt_bundle",
        ],
        "unknown",
    );
    let scope = normalize_enum_token(
        value_string(body, "scope").unwrap_or_else(|| "project".to_string()),
        &["user", "project", "session", "agent", "org", "device"],
        "unknown",
    );
    let remote_export_requested = value_bool(body, "remote_export_requested", false)
        || value_bool(body, "remoteExportRequested", false);
    let requested_layers = value_string_list(body, "requested_layers")
        .or_else(|| value_string_list(body, "requestedLayers"))
        .unwrap_or_default();
    let requested_source_kinds = value_string_list(body, "requested_source_kinds")
        .or_else(|| value_string_list(body, "requestedSourceKinds"))
        .unwrap_or_default();
    let mut allowed_layers = vec![
        "l0_constitution".to_string(),
        "l1_canonical".to_string(),
        "l2_observations".to_string(),
        "l3_working_set".to_string(),
    ];
    let mut raw_evidence_allowed = false;
    let mut personal_memory_allowed = false;
    let mut requires_fresh_snapshot = false;
    let mut visibility_floor = "local_only".to_string();
    let allowed_roles = match use_mode.as_str() {
        "project_chat" => vec!["chat".to_string(), "tool".to_string()],
        "session_resume" => vec!["session".to_string(), "tool".to_string()],
        "supervisor_orchestration" => vec!["supervisor".to_string(), "tool".to_string()],
        "tool_plan" | "tool_act_low_risk" | "tool_act_high_risk" => vec!["tool".to_string()],
        "lane_handoff" => vec!["lane".to_string()],
        "remote_prompt_bundle" => vec!["remote_export".to_string()],
        _ => Vec::new(),
    };
    if requester_role == "unknown" || use_mode == "unknown" || scope == "unknown" {
        return MemoryPolicyEvaluation::deny(
            requester_role,
            use_mode,
            scope,
            "memory_mode_contract_missing",
            allowed_roles,
        );
    }
    if !allowed_roles.iter().any(|role| role == &requester_role) {
        return MemoryPolicyEvaluation::deny(
            requester_role,
            use_mode,
            scope,
            "memory_route_policy_mismatch",
            allowed_roles,
        );
    }
    if scope == "user" && use_mode != "assistant_personal" {
        return MemoryPolicyEvaluation::deny(
            requester_role,
            use_mode,
            scope,
            "user_memory_grant_required",
            allowed_roles,
        );
    }
    match use_mode.as_str() {
        "project_chat" | "tool_plan" | "tool_act_low_risk" => {
            raw_evidence_allowed = true;
            allowed_layers.push("l4_raw_evidence".to_string());
        }
        "tool_act_high_risk" => {
            requires_fresh_snapshot = true;
        }
        "lane_handoff" => {
            visibility_floor = "refs_only".to_string();
            return MemoryPolicyEvaluation {
                schema_version: MEMORY_POLICY_RESULT_SCHEMA.to_string(),
                ok: false,
                decision: "deny".to_string(),
                deny_code: "lane_handoff_fulltext_denied".to_string(),
                downgrade_code: String::new(),
                requester_role,
                use_mode,
                scope,
                allowed_roles,
                denied_roles: Vec::new(),
                allowed_layers: Vec::new(),
                allowed_source_kinds: Vec::new(),
                visibility_floor,
                raw_evidence_allowed: false,
                personal_memory_allowed: false,
                requires_fresh_snapshot: true,
            };
        }
        "remote_prompt_bundle" => {
            requires_fresh_snapshot = true;
            visibility_floor = "sanitized_remote_ok".to_string();
        }
        _ => {}
    }
    if remote_export_requested && raw_evidence_requested(&requested_layers, &requested_source_kinds)
    {
        return MemoryPolicyEvaluation::deny(
            requester_role,
            use_mode,
            scope,
            "raw_evidence_remote_export_denied",
            allowed_roles,
        );
    }
    if !raw_evidence_allowed && raw_evidence_requested(&requested_layers, &requested_source_kinds) {
        return MemoryPolicyEvaluation::deny(
            requester_role,
            use_mode,
            scope,
            "memory_layer_not_allowed_for_mode",
            allowed_roles,
        );
    }
    if scope == "user" {
        personal_memory_allowed = true;
    }
    MemoryPolicyEvaluation {
        schema_version: MEMORY_POLICY_RESULT_SCHEMA.to_string(),
        ok: true,
        decision: "allow".to_string(),
        deny_code: String::new(),
        downgrade_code: String::new(),
        requester_role,
        use_mode,
        scope,
        allowed_roles,
        denied_roles: Vec::new(),
        allowed_layers,
        allowed_source_kinds: requested_source_kinds,
        visibility_floor,
        raw_evidence_allowed,
        personal_memory_allowed,
        requires_fresh_snapshot,
    }
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
    request.requested_layers = value_string_list(&body, "requested_layers")
        .or_else(|| value_string_list(&body, "requestedLayers"))
        .or_else(|| value_string_list(&body, "layers"))
        .unwrap_or_default();
    request.explicit_refs = value_string_list(&body, "explicit_refs")
        .or_else(|| value_string_list(&body, "explicitRefs"))
        .unwrap_or_default();
    request.sensitivity_max = value_string(&body, "sensitivity_max")
        .or_else(|| value_string(&body, "sensitivityMax"))
        .unwrap_or_default();
    request.visibility = value_string(&body, "visibility").unwrap_or_default();
    request.created_after_ms = value_i64(&body, "created_after_ms")
        .or_else(|| value_i64(&body, "createdAfterMs"))
        .unwrap_or(0);
    request.updated_after_ms = value_i64(&body, "updated_after_ms")
        .or_else(|| value_i64(&body, "updatedAfterMs"))
        .unwrap_or(0);
    request.explain = value_bool(&body, "explain", false);
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
    readiness_json_from_dir(config, memory_dir)
}

pub fn readiness_json_from_dir(config: &HubConfig, memory_dir: PathBuf) -> Result<String, String> {
    let snapshot = scan_memory_snapshot(&memory_dir);
    readiness_json_from_snapshot_with_config(config, &snapshot)
}

pub fn readiness_json_from_snapshot_with_config(
    config: &HubConfig,
    snapshot: &MemoryIndexSnapshot,
) -> Result<String, String> {
    let summary = read_memory_object_store_summary(&config.db_path)
        .map_err(|err| format!("memory object store summary failed: {err}"))?;
    let index_summary = read_memory_object_index_summary(&config.db_path)
        .map_err(|err| format!("memory object index summary failed: {err}"))?;
    readiness_json_from_snapshot_inner(snapshot, Some(summary), Some(index_summary))
}

fn readiness_json_from_snapshot_inner(
    snapshot: &MemoryIndexSnapshot,
    object_summary: Option<xhub_db::MemoryObjectStoreSummary>,
    index_summary: Option<MemoryObjectIndexSummary>,
) -> Result<String, String> {
    let mut status = readiness_from_snapshot(snapshot);
    status.writer_authority_in_rust = memory_writer_authority_enabled();
    let object_store_ready = object_summary.is_some();
    let summary = object_summary.unwrap_or_default();
    let index = index_summary.unwrap_or_default();
    Ok(json!({
        "schema_version": SCHEMA_VERSION,
        "ok": true,
        "command": "readiness",
        "readiness": status,
        "object_store": {
            "schema_version": MEMORY_OBJECT_SCHEMA,
            "ready": object_store_ready,
            "object_count": summary.object_count,
            "active_object_count": summary.active_object_count,
            "candidate_object_count": summary.candidate_object_count,
            "deleted_tombstone_count": summary.deleted_tombstone_count,
            "event_count": summary.event_count,
            "latest_object_updated_at_ms": summary.latest_object_updated_at_ms,
            "latest_event_created_at_ms": summary.latest_event_created_at_ms,
            "policy_gate_ready": true,
            "crud_create_get_list_history_http": true,
            "memory_index_ready": index.index_ready,
            "memory_index_row_count": index.index_row_count,
            "memory_index_stale_count": index.stale_index_count,
            "memory_index_active_indexable_object_count": index.active_indexable_object_count,
            "memory_index_latest_indexed_at_ms": index.latest_indexed_at_ms,
            "memory_index_generation": {
                "source": "rust_hub_memory_object_index",
                "row_count": index.index_row_count,
                "stale_count": index.stale_index_count,
                "latest_indexed_at_ms": index.latest_indexed_at_ms,
            },
            "semantic_index_enabled": false,
        },
    })
    .to_string())
}

fn memory_object_index_summary_to_json(summary: &MemoryObjectIndexSummary) -> Value {
    json!({
        "source": "rust_hub_memory_object_index",
        "ready": summary.index_ready,
        "row_count": summary.index_row_count,
        "active_indexable_object_count": summary.active_indexable_object_count,
        "stale_count": summary.stale_index_count,
        "latest_indexed_at_ms": summary.latest_indexed_at_ms,
    })
}

fn memory_object_index_rebuild_report_to_json(
    report: &xhub_db::MemoryObjectIndexRebuildReport,
) -> Value {
    json!({
        "schema_version": &report.schema_version,
        "rebuilt": report.rebuilt,
        "indexed_count": report.indexed_count,
        "skipped_secret_count": report.skipped_secret_count,
        "skipped_inactive_count": report.skipped_inactive_count,
        "stale_before_count": report.stale_before_count,
        "stale_after_count": report.stale_after_count,
        "generated_at_ms": report.generated_at_ms,
    })
}

pub fn snapshot_from_dir(memory_dir: PathBuf) -> MemoryIndexSnapshot {
    scan_memory_snapshot(&memory_dir)
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

#[derive(Debug, Clone)]
struct HttpJsonError {
    status: &'static str,
    body: String,
}

#[derive(Debug, Clone)]
struct MemoryPolicyEvaluation {
    schema_version: String,
    ok: bool,
    decision: String,
    deny_code: String,
    downgrade_code: String,
    requester_role: String,
    use_mode: String,
    scope: String,
    allowed_roles: Vec<String>,
    denied_roles: Vec<String>,
    allowed_layers: Vec<String>,
    allowed_source_kinds: Vec<String>,
    visibility_floor: String,
    raw_evidence_allowed: bool,
    personal_memory_allowed: bool,
    requires_fresh_snapshot: bool,
}

impl MemoryPolicyEvaluation {
    fn deny(
        requester_role: String,
        use_mode: String,
        scope: String,
        deny_code: &str,
        allowed_roles: Vec<String>,
    ) -> Self {
        Self {
            schema_version: MEMORY_POLICY_RESULT_SCHEMA.to_string(),
            ok: false,
            decision: "deny".to_string(),
            deny_code: deny_code.to_string(),
            downgrade_code: String::new(),
            requester_role,
            use_mode,
            scope,
            allowed_roles,
            denied_roles: Vec::new(),
            allowed_layers: Vec::new(),
            allowed_source_kinds: Vec::new(),
            visibility_floor: "local_only".to_string(),
            raw_evidence_allowed: false,
            personal_memory_allowed: false,
            requires_fresh_snapshot: false,
        }
    }

    fn to_json(&self) -> Value {
        json!({
            "schema_version": &self.schema_version,
            "ok": self.ok,
            "decision": &self.decision,
            "deny_code": &self.deny_code,
            "downgrade_code": &self.downgrade_code,
            "requester_role": &self.requester_role,
            "use_mode": &self.use_mode,
            "scope": &self.scope,
            "allowed_roles": &self.allowed_roles,
            "denied_roles": &self.denied_roles,
            "allowed_layers": &self.allowed_layers,
            "allowed_source_kinds": &self.allowed_source_kinds,
            "visibility_floor": &self.visibility_floor,
            "raw_evidence_allowed": self.raw_evidence_allowed,
            "personal_memory_allowed": self.personal_memory_allowed,
            "requires_fresh_snapshot": self.requires_fresh_snapshot,
        })
    }
}

fn parse_json_body(body: &str) -> Result<Value, HttpJsonError> {
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

fn http_json_error(status: &'static str, error_code: &str, message: String) -> HttpJsonError {
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

fn http_json_error_json(status: &'static str, body: Value) -> HttpJsonError {
    HttpJsonError {
        status,
        body: body.to_string(),
    }
}

fn memory_object_to_json(object: &MemoryObjectRecord) -> Value {
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

fn memory_event_to_json(event: &MemoryEventRecord) -> Value {
    json!({
        "schema_version": "xhub.memory.event.v1",
        "event_id": &event.event_id,
        "memory_id": &event.memory_id,
        "operation": &event.operation,
        "actor": &event.actor,
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

fn gateway_allowed_layers(
    policy: &MemoryPolicyEvaluation,
    requested_layers: &[String],
) -> Vec<String> {
    let default_layers = vec![
        "l1_canonical".to_string(),
        "l2_observations".to_string(),
        "l3_working_set".to_string(),
    ];
    let requested = if requested_layers.is_empty() {
        default_layers
    } else {
        requested_layers
            .iter()
            .map(|layer| {
                normalize_enum_token(
                    layer.to_string(),
                    &[
                        "l0_constitution",
                        "l1_canonical",
                        "l2_observations",
                        "l3_working_set",
                        "l4_raw_evidence",
                    ],
                    "unknown",
                )
            })
            .filter(|layer| layer != "unknown")
            .collect::<Vec<_>>()
    };
    requested
        .into_iter()
        .filter(|layer| policy.allowed_layers.iter().any(|allowed| allowed == layer))
        .collect()
}

fn gateway_requested_source_kinds(requested_source_kinds: &[String]) -> Vec<String> {
    requested_source_kinds
        .iter()
        .map(|source_kind| normalize_source_kind_for_object(source_kind))
        .collect()
}

fn gateway_json_error(status: &'static str, error_code: &str, message: String) -> HttpJsonError {
    http_json_error_json(
        status,
        json!({
            "schema_version": MEMORY_GATEWAY_PREPARE_SCHEMA,
            "ok": false,
            "status": "error",
            "error_code": error_code,
            "message": message,
        }),
    )
}

fn gateway_memory_object_to_json(object: &MemoryObjectRecord, max_chars: usize) -> Value {
    json!({
        "memory_id": &object.memory_id,
        "scope": &object.scope,
        "owner_id": &object.owner_id,
        "project_id": object.project_id.as_deref(),
        "agent_id": object.agent_id.as_deref(),
        "source_kind": &object.source_kind,
        "layer": &object.layer,
        "title": &object.title,
        "text": gateway_truncate_text(&object.text, max_chars),
        "summary": &object.summary,
        "sensitivity": &object.sensitivity,
        "visibility": &object.visibility,
        "updated_at_ms": object.updated_at_ms,
        "version": object.version,
    })
}

fn gateway_context_text(objects: &[MemoryObjectRecord], max_chars: usize) -> String {
    let mut out = String::new();
    let mut current_layer = String::new();
    for object in objects {
        if object.layer != current_layer {
            if !out.is_empty() {
                out.push('\n');
            }
            current_layer = object.layer.clone();
            let _ = writeln!(&mut out, "## {}", current_layer);
        }
        let text = gateway_truncate_text(&object.text, max_chars);
        let _ = writeln!(
            &mut out,
            "- [{}] {}: {}",
            object.source_kind, object.title, text
        );
    }
    out.trim().to_string()
}

fn gateway_truncate_text(value: &str, max_chars: usize) -> String {
    let normalized = value.split_whitespace().collect::<Vec<_>>().join(" ");
    if normalized.chars().count() <= max_chars {
        normalized
    } else {
        normalized.chars().take(max_chars).collect()
    }
}

fn next_memory_id() -> String {
    let next = MEMORY_OBJECT_COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("mem_{}_{}", now_ms_i64(), next)
}

fn next_memory_event_id() -> String {
    let next = MEMORY_OBJECT_COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("mev_{}_{}", now_ms_i64(), next)
}

fn now_ms_i64() -> i64 {
    now_ms().min(i64::MAX as u128) as i64
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

fn value_i64(value: &Value, key: &str) -> Option<i64> {
    value.get(key).and_then(Value::as_i64)
}

fn value_bool(value: &Value, key: &str, fallback: bool) -> bool {
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

fn optional_public_token(value: &Value, key: &str) -> Option<String> {
    value_string(value, key).and_then(|raw| sanitize_public_token(&raw))
}

fn sanitize_public_token(value: &str) -> Option<String> {
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

fn sanitize_public_text_value(value: &Value, key: &str) -> Option<String> {
    value_string(value, key).and_then(|raw| sanitize_public_text(&raw, 240))
}

fn sanitize_public_text(value: &str, max_chars: usize) -> Option<String> {
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

fn normalize_enum_token(raw: String, allowed: &[&str], fallback: &str) -> String {
    let token = raw.trim().to_ascii_lowercase().replace('-', "_");
    if allowed.iter().any(|item| *item == token) {
        token
    } else {
        fallback.to_string()
    }
}

fn normalize_source_kind_for_object(raw: &str) -> String {
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

#[derive(Debug, Clone, Copy)]
struct ProjectCanonicalItemKind {
    suffix: &'static str,
    title: &'static str,
    source_kind: &'static str,
    layer: &'static str,
}

fn project_canonical_item_kind(raw_key: &str) -> Option<ProjectCanonicalItemKind> {
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

fn project_canonical_memory_id(project_id: &str, suffix: &str) -> String {
    let project = sanitize_id_segment(project_id, 80);
    let suffix = sanitize_id_segment(suffix, 64);
    format!("mem_xt_project_{project}_{suffix}")
}

fn sanitize_id_segment(raw: &str, max_chars: usize) -> String {
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

fn summarize_memory_text(text: &str) -> String {
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

fn raw_evidence_requested(layers: &[String], source_kinds: &[String]) -> bool {
    layers
        .iter()
        .any(|layer| layer.trim().eq_ignore_ascii_case("l4_raw_evidence"))
        || source_kinds.iter().any(|kind| {
            let lower = kind.trim().to_ascii_lowercase();
            lower.contains("raw") || lower.contains("evidence")
        })
}

fn looks_like_secret_public(value: &str) -> bool {
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

fn query_param(query: &str, key: &str) -> Option<String> {
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

fn query_usize(query: &str, key: &str, fallback: usize) -> Result<usize, String> {
    match query_param(query, key) {
        Some(value) if !value.trim().is_empty() => value
            .trim()
            .parse::<usize>()
            .map_err(|_| format!("invalid query parameter: {key}")),
        _ => Ok(fallback),
    }
}

fn query_bool(query: &str, key: &str, fallback: bool) -> bool {
    query_param(query, key)
        .map(|value| {
            matches!(
                value.trim().to_ascii_lowercase().as_str(),
                "1" | "true" | "yes" | "on"
            )
        })
        .unwrap_or(fallback)
}

fn percent_decode(input: &str) -> Result<String, String> {
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

fn env_bool(key: &str, fallback: bool) -> bool {
    match env::var(key) {
        Ok(value) => matches!(
            value.trim().to_ascii_lowercase().as_str(),
            "1" | "true" | "yes" | "on"
        ),
        Err(_) => fallback,
    }
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

    fn optional_i64(&self, key: &str) -> Result<Option<i64>, String> {
        match self.optional(key) {
            Some(value) => value
                .parse::<i64>()
                .map(Some)
                .map_err(|_| format!("invalid --{key}: {value}")),
            None => Ok(None),
        }
    }

    fn optional_bool(&self, key: &str) -> Option<bool> {
        self.optional(key).map(|value| {
            matches!(
                value.trim().to_ascii_lowercase().as_str(),
                "1" | "true" | "yes" | "on"
            )
        })
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
        let raw = retrieve_json_from_request(request).expect("retrieve");
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
            "uml_w6_persistent_derived_index_slice"
        );
        assert_eq!(
            value["retrieval_engine"]["index_source"],
            "rust_hub_memory_object_index"
        );
        assert_eq!(value["retrieval_engine"]["index_rebuilt"], true);
        assert_eq!(value["retrieval_engine"]["stale_index_count"], 0);
        let results = value["results"].as_array().expect("results");
        assert_eq!(results[0]["memory_id"], "mem_hybrid_decision");
        assert_eq!(results[0]["layer"], "l1_canonical");
        assert_eq!(
            results[0]["explain"]["policy_filter"],
            "project_active_non_secret"
        );
        assert_eq!(results[0]["explain"]["properties"]["has_decision"], true);
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
            .any(|item| item["reason_code"] == "layer_filter"
                && item["memory_id"] == "mem_filter_goal"));

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

        let fetched_raw = dispatch(&config, &args(&["object-get", "--memory-id", "mem_cli_1"]))
            .expect("get object");
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
        let goal_after_update =
            read_memory_object(&config.db_path, "mem_xt_project_project-sync_goal")
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
        assert_eq!(prepared["object_count"], 2);
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
        assert_eq!(remote["object_count"], 0);
        assert_eq!(remote["skipped"]["remote_visibility"], 1);

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
            "requested_layers": ["l4_raw_evidence"]
        })
        .to_string();
        let (status, raw) = memory_gateway_prepare_http_json(&config, "POST", &body);
        assert_eq!(status, "403 Forbidden");
        let denied: Value = serde_json::from_str(&raw).expect("denied json");
        assert_eq!(denied["schema_version"], MEMORY_GATEWAY_PREPARE_SCHEMA);
        assert_eq!(denied["status"], "denied");
        assert_eq!(denied["deny_code"], "memory_layer_not_allowed_for_mode");

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
}
