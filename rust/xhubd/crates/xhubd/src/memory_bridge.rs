use std::collections::{BTreeMap, BTreeSet};
use std::env;
use std::fmt::Write as _;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};

use crate::local_ml_bridge;
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
const MEMORY_OBJECT_MUTATION_SCHEMA: &str = "xhub.memory.object_mutation.v1";
const MEMORY_USER_REVEAL_GRANT_SCHEMA: &str = "xhub.memory.user_reveal_grant.v1";
const MEMORY_USER_REVEAL_GRANT_SURFACE: &str = "assistant_user_memory_inspector";
const MEMORY_USER_REVEAL_GRANT_DEFAULT_TTL_MS: i64 = 5 * 60 * 1000;
const MEMORY_USER_REVEAL_GRANT_MAX_TTL_MS: i64 = 15 * 60 * 1000;
const MEMORY_POLICY_RESULT_SCHEMA: &str = "xhub.memory.policy_result.v1";
const MEMORY_PROJECT_CANONICAL_SYNC_SCHEMA: &str = "xhub.memory.project_canonical_sync.v1";
const MEMORY_GATEWAY_PREPARE_SCHEMA: &str = "xhub.memory.gateway_prepare.v1";
const MEMORY_GATEWAY_MODEL_CALL_PLAN_SCHEMA: &str = "xhub.memory.gateway_model_call_plan.v1";
const MEMORY_GATEWAY_MODEL_CALL_EXECUTION_GATE_SCHEMA: &str =
    "xhub.memory.gateway_model_call_execution_gate.v1";
const MEMORY_GATEWAY_MODEL_CALL_EXECUTE_SCHEMA: &str = "xhub.memory.gateway_model_call_execute.v1";
const MEMORY_WRITEBACK_CANDIDATE_SCHEMA: &str = "xhub.memory.writeback_candidate.v1";
const MEMORY_WRITEBACK_CANDIDATE_EXTRACT_SCHEMA: &str =
    "xhub.memory.writeback_candidate_extract.v1";
const MEMORY_WRITEBACK_CANDIDATE_MAINTENANCE_SCHEMA: &str =
    "xhub.memory.writeback_candidate_maintenance.v1";
const MEMORY_WRITEBACK_CANDIDATE_DIAGNOSTICS_SCHEMA: &str =
    "xhub.memory.writeback_candidate_diagnostics.v1";
const MEMORY_OBJECT_RETRIEVAL_SOURCE: &str = "rust_memory_objects_hybrid_v1";
const MEMORY_RETRIEVAL_TRACE_LIMIT: usize = 32;
static MEMORY_OBJECT_COUNTER: AtomicU64 = AtomicU64::new(1);
static MEMORY_USER_REVEAL_GRANT_COUNTER: AtomicU64 = AtomicU64::new(1);

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
        "object-archive" | "archive-object" => {
            object_mutation_cli_json(config, FlagArgs::parse(&args[1..])?, "archive")
        }
        "object-delete" | "delete-object" => {
            object_mutation_cli_json(config, FlagArgs::parse(&args[1..])?, "delete")
        }
        "object-pin" | "pin-object" => {
            object_mutation_cli_json(config, FlagArgs::parse(&args[1..])?, "pin")
        }
        "object-unpin" | "unpin-object" => {
            object_mutation_cli_json(config, FlagArgs::parse(&args[1..])?, "unpin")
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
        "candidate-maintenance" | "writeback-candidate-maintenance" => {
            writeback_candidate_maintenance_cli_json(config, FlagArgs::parse(&args[1..])?)
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
        "gateway-model-call-plan" | "model-call-plan" | "generate-plan" => {
            gateway_model_call_plan_cli_json(config, FlagArgs::parse(&args[1..])?)
        }
        "gateway-model-call-execution-gate" | "model-call-execution-gate" => {
            gateway_model_call_execution_gate_cli_json(config, FlagArgs::parse(&args[1..])?)
        }
        "gateway-model-call-execute" | "model-call-execute" | "generate-execute" => {
            gateway_model_call_execute_cli_json(config, FlagArgs::parse(&args[1..])?)
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
    let mut explicit_chunk_refs = BTreeMap::<String, BTreeSet<String>>::new();
    for (memory_id, chunk_id) in request
        .explicit_refs
        .iter()
        .filter_map(|value| memory_object_chunk_from_ref(value))
    {
        explicit_chunk_refs
            .entry(memory_id)
            .or_default()
            .insert(chunk_id);
    }
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
    let mut candidates_for_scoring = Vec::<ObjectRetrievalDocument>::new();
    let mut skipped_policy_or_filter = 0usize;
    let mut skipped_secret = 0usize;
    let mut skipped_deleted = 0usize;
    let mut skipped_no_match = 0usize;
    let mut omitted_reason_counts = BTreeMap::<String, usize>::new();
    let mut omitted_trace = Vec::<Value>::new();
    for document in documents {
        if document.status != "active" {
            skipped_deleted += 1;
            record_object_omission_trace(
                request,
                &mut omitted_trace,
                &mut omitted_reason_counts,
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
            record_object_omission_trace(
                request,
                &mut omitted_trace,
                &mut omitted_reason_counts,
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
            record_object_omission_trace(
                request,
                &mut omitted_trace,
                &mut omitted_reason_counts,
                &document,
                "source_kind_filter",
                index_source,
            );
            continue;
        }
        if !requested_layers.is_empty() && !requested_layers.contains(&document.layer) {
            skipped_policy_or_filter += 1;
            record_object_omission_trace(
                request,
                &mut omitted_trace,
                &mut omitted_reason_counts,
                &document,
                "layer_filter",
                index_source,
            );
            continue;
        }
        if !visibility_filter.is_empty() && document.visibility != visibility_filter {
            skipped_policy_or_filter += 1;
            record_object_omission_trace(
                request,
                &mut omitted_trace,
                &mut omitted_reason_counts,
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
            record_object_omission_trace(
                request,
                &mut omitted_trace,
                &mut omitted_reason_counts,
                &document,
                "sensitivity_filter",
                index_source,
            );
            continue;
        }
        if request.created_after_ms > 0 && document.created_at_ms < request.created_after_ms {
            skipped_policy_or_filter += 1;
            record_object_omission_trace(
                request,
                &mut omitted_trace,
                &mut omitted_reason_counts,
                &document,
                "created_after_ms_filter",
                index_source,
            );
            continue;
        }
        if request.updated_after_ms > 0 && document.updated_at_ms < request.updated_after_ms {
            skipped_policy_or_filter += 1;
            record_object_omission_trace(
                request,
                &mut omitted_trace,
                &mut omitted_reason_counts,
                &document,
                "updated_after_ms_filter",
                index_source,
            );
            continue;
        }
        if exact_ref_lookup && !explicit_object_ids.contains(&document.memory_id) {
            skipped_policy_or_filter += 1;
            record_object_omission_trace(
                request,
                &mut omitted_trace,
                &mut omitted_reason_counts,
                &document,
                "explicit_ref_filter",
                index_source,
            );
            continue;
        }
        if exact_ref_lookup
            && explicit_chunk_refs
                .get(&document.memory_id)
                .is_some_and(|chunks| !chunks.contains(&document.chunk_id))
        {
            skipped_policy_or_filter += 1;
            record_object_omission_trace(
                request,
                &mut omitted_trace,
                &mut omitted_reason_counts,
                &document,
                "explicit_chunk_filter",
                index_source,
            );
            continue;
        }

        candidates_for_scoring.push(document);
    }

    if candidates_for_scoring.is_empty() {
        return Ok(None);
    }

    let bm25_stats = memory_bm25_corpus_stats(&candidates_for_scoring, &query_tokens);
    let mut scored = Vec::<ObjectRetrievalCandidate>::new();
    for document in candidates_for_scoring {
        let bm25_score = if exact_ref_lookup {
            1.0
        } else {
            object_bm25_score(&query_tokens, &document.searchable_text, &bm25_stats)
        };
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
        let score = if exact_ref_lookup {
            1.0 + property_boost + pinned_boost
        } else {
            (lexical_score * 0.45) + (bm25_score * 0.55) + property_boost + pinned_boost
        };
        if !exact_ref_lookup && !query_tokens.is_empty() && score <= 0.0 {
            skipped_no_match += 1;
            record_object_omission_trace(
                request,
                &mut omitted_trace,
                &mut omitted_reason_counts,
                &document,
                "no_lexical_or_property_match",
                index_source,
            );
            continue;
        }
        scored.push(ObjectRetrievalCandidate {
            document,
            lexical_score,
            bm25_score,
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
        let object_ref = object_retrieval_ref(&candidate.document);
        let chunk_id = object_retrieval_chunk_id(&candidate.document);
        let chunk_ref = object_retrieval_chunk_ref(&candidate.document);
        let mut item = json!({
            "ref": object_ref,
            "chunk_ref": chunk_ref,
            "chunk_id": chunk_id,
            "chunk_identity_schema": "xhub.memory.object_chunk_identity.v1",
            "chunk_start_line": candidate.document.chunk_start_line,
            "chunk_end_line": candidate.document.chunk_end_line,
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
                "bm25_score": round6(candidate.bm25_score),
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
            "omitted_reason_counts": omitted_reason_counts.clone(),
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
            "stage": "uml_w6_persistent_derived_index_bm25_slice",
            "index_source": index_source,
            "index_granularity": "object_chunk",
            "chunk_identity_schema": "xhub.memory.object_chunk_identity.v1",
            "chunk_expand_via_get_ref": true,
            "index_ready": index_summary.index_ready,
            "index_row_count": index_summary.index_row_count,
            "active_indexable_object_count": index_summary.active_indexable_object_count,
            "stale_index_count": index_summary.stale_index_count,
            "latest_indexed_at_ms": index_summary.latest_indexed_at_ms,
            "index_rebuilt": index_rebuilt,
            "index_rebuild_error": index_rebuild_error,
            "semantic_used": false,
            "rerank_used": false,
            "fts": if index_source == "rust_hub_memory_object_index" { "derived_index_bm25_rust" } else { "live_scan_bm25_rust" },
            "bm25_used": true,
            "bm25_avg_doc_len": round6(bm25_stats.avg_doc_len),
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
            "omitted_reason_counts": omitted_reason_counts,
        },
        "production_authority_change": false,
    })))
}

#[derive(Debug)]
struct ObjectRetrievalCandidate {
    document: ObjectRetrievalDocument,
    lexical_score: f64,
    bm25_score: f64,
    property_boost: f64,
    pinned_boost: f64,
    score: f64,
    properties: BTreeMap<String, bool>,
}

#[derive(Debug, Clone)]
struct ObjectRetrievalDocument {
    memory_id: String,
    chunk_id: String,
    chunk_start_line: usize,
    chunk_end_line: usize,
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
    let content_hash = stable_fnv1a64_hex(&searchable_text);
    let chunk_end_line = object.text.lines().count().max(1);
    ObjectRetrievalDocument {
        memory_id: object.memory_id,
        chunk_id: format!("object-1-{chunk_end_line}-{content_hash}"),
        chunk_start_line: 1,
        chunk_end_line,
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
        content_hash: Some(content_hash),
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
        chunk_id: row.chunk_id,
        chunk_start_line: row.chunk_start_line.max(1) as usize,
        chunk_end_line: row.chunk_end_line.max(1) as usize,
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
    let object_ref = object_retrieval_ref(&candidate.document);
    let chunk_id = object_retrieval_chunk_id(&candidate.document);
    let chunk_ref = object_retrieval_chunk_ref(&candidate.document);
    json!({
        "rank": rank,
        "ref": object_ref,
        "chunk_ref": chunk_ref,
        "chunk_id": chunk_id,
        "chunk_identity_schema": "xhub.memory.object_chunk_identity.v1",
        "chunk_start_line": candidate.document.chunk_start_line,
        "chunk_end_line": candidate.document.chunk_end_line,
        "memory_id": &candidate.document.memory_id,
        "reason_code": "selected",
        "index_source": index_source,
        "score": round6(candidate.score),
        "lexical_score": round6(candidate.lexical_score),
        "bm25_score": round6(candidate.bm25_score),
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
    let object_ref = object_retrieval_ref(document);
    let chunk_id = object_retrieval_chunk_id(document);
    let chunk_ref = object_retrieval_chunk_ref(document);
    trace.push(json!({
        "ref": object_ref,
        "chunk_ref": chunk_ref,
        "chunk_id": chunk_id,
        "chunk_identity_schema": "xhub.memory.object_chunk_identity.v1",
        "chunk_start_line": document.chunk_start_line,
        "chunk_end_line": document.chunk_end_line,
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

fn object_retrieval_ref(document: &ObjectRetrievalDocument) -> String {
    format!("memory://rust/object/{}", document.memory_id)
}

fn object_retrieval_chunk_ref(document: &ObjectRetrievalDocument) -> String {
    format!(
        "{}#{}",
        object_retrieval_ref(document),
        object_retrieval_chunk_id(document)
    )
}

fn object_retrieval_chunk_id(document: &ObjectRetrievalDocument) -> String {
    document.chunk_id.clone()
}

fn record_object_omission_trace(
    request: &MemoryRetrievalRequest,
    trace: &mut Vec<Value>,
    reason_counts: &mut BTreeMap<String, usize>,
    document: &ObjectRetrievalDocument,
    reason_code: &str,
    index_source: &str,
) {
    increment_omitted_reason_count(reason_counts, reason_code);
    push_object_omission_trace(request, trace, document, reason_code, index_source);
}

fn increment_omitted_reason_count(reason_counts: &mut BTreeMap<String, usize>, reason_code: &str) {
    let normalized = reason_code.trim();
    if normalized.is_empty() {
        return;
    }
    *reason_counts.entry(normalized.to_string()).or_insert(0) += 1;
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

fn memory_object_chunk_from_ref(raw: &str) -> Option<(String, String)> {
    let trimmed = raw.trim();
    let (_, chunk) = trimmed.split_once('#')?;
    let memory_id = memory_object_id_from_ref(trimmed)?;
    let chunk_id = sanitize_public_token(chunk.split('?').next().unwrap_or("").trim())?;
    if chunk_id.starts_with("object-") {
        Some((memory_id, chunk_id))
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

#[derive(Debug, Clone, Default)]
struct Bm25CorpusStats {
    document_count: usize,
    avg_doc_len: f64,
    doc_freq: BTreeMap<String, usize>,
}

fn memory_bm25_corpus_stats(
    documents: &[ObjectRetrievalDocument],
    query_tokens: &[String],
) -> Bm25CorpusStats {
    if documents.is_empty() || query_tokens.is_empty() {
        return Bm25CorpusStats::default();
    }
    let query_set = query_tokens.iter().cloned().collect::<BTreeSet<_>>();
    let mut total_len = 0usize;
    let mut doc_freq = BTreeMap::<String, usize>::new();
    for document in documents {
        let tokens = object_retrieval_token_stream(&document.searchable_text);
        total_len += tokens.len();
        let mut seen = BTreeSet::<String>::new();
        for token in tokens {
            if query_set.contains(&token) {
                seen.insert(token);
            }
        }
        for token in seen {
            *doc_freq.entry(token).or_insert(0) += 1;
        }
    }
    Bm25CorpusStats {
        document_count: documents.len(),
        avg_doc_len: total_len as f64 / documents.len().max(1) as f64,
        doc_freq,
    }
}

fn object_bm25_score(query_tokens: &[String], text: &str, stats: &Bm25CorpusStats) -> f64 {
    if query_tokens.is_empty() || stats.document_count == 0 || stats.avg_doc_len <= 0.0 {
        return 0.0;
    }
    let tokens = object_retrieval_token_stream(text);
    if tokens.is_empty() {
        return 0.0;
    }
    let mut term_counts = BTreeMap::<String, usize>::new();
    for token in tokens {
        *term_counts.entry(token).or_insert(0) += 1;
    }
    let doc_len = term_counts.values().copied().sum::<usize>() as f64;
    let k1 = 1.2_f64;
    let b = 0.75_f64;
    let n = stats.document_count as f64;
    let mut raw_score = 0.0_f64;
    for token in query_tokens {
        let Some(tf) = term_counts.get(token).copied() else {
            continue;
        };
        let df = stats.doc_freq.get(token).copied().unwrap_or(0) as f64;
        if df <= 0.0 {
            continue;
        }
        let idf = (1.0 + ((n - df + 0.5) / (df + 0.5))).ln();
        let tf = tf as f64;
        let denom = tf + k1 * (1.0 - b + b * (doc_len / stats.avg_doc_len.max(1.0)));
        raw_score += idf * ((tf * (k1 + 1.0)) / denom.max(f64::EPSILON));
    }
    if raw_score <= 0.0 {
        0.0
    } else {
        raw_score / (raw_score + 3.0)
    }
}

fn object_retrieval_tokens(text: &str) -> Vec<String> {
    object_retrieval_token_stream(text)
        .into_iter()
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect()
}

fn object_retrieval_token_stream(text: &str) -> Vec<String> {
    let mut tokens = BTreeSet::new();
    let mut current = String::new();
    let mut stream = Vec::<String>::new();
    for ch in text.chars() {
        if ch.is_alphanumeric() || ch == '_' || ch == '-' {
            current.push(ch.to_ascii_lowercase());
        } else {
            push_object_token_stream(&mut tokens, &mut stream, &mut current);
        }
    }
    push_object_token_stream(&mut tokens, &mut stream, &mut current);
    stream
}

fn push_object_token_stream(
    unique_tokens: &mut BTreeSet<String>,
    stream: &mut Vec<String>,
    current: &mut String,
) {
    let token = current.trim_matches('-').to_string();
    if token.chars().count() >= 2 {
        unique_tokens.insert(token.clone());
        stream.push(token);
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

fn object_mutation_cli_json(
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
    insert_string_flag(&mut body, &flags, "confirmation", "confirmation");
    insert_bool_flag(&mut body, &flags, "confirm", "confirm");
    insert_bool_flag(&mut body, &flags, "confirm-archive", "confirm_archive");
    insert_bool_flag(&mut body, &flags, "confirm-delete", "confirm_delete");
    Ok(cli_http_body(memory_object_mutation_json(
        config,
        &memory_id,
        action,
        &Value::Object(body).to_string(),
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

fn writeback_candidate_maintenance_cli_json(
    config: &HubConfig,
    flags: FlagArgs,
) -> Result<String, String> {
    let mut body = serde_json::Map::new();
    insert_string_flag(&mut body, &flags, "project-id", "project_id");
    insert_string_flag(&mut body, &flags, "actor", "actor");
    insert_string_flag(&mut body, &flags, "audit-ref", "audit_ref");
    insert_string_flag(&mut body, &flags, "reason", "reason");
    insert_bool_flag(&mut body, &flags, "apply", "apply");
    insert_bool_flag(&mut body, &flags, "dry-run", "dry_run");
    if let Some(max_age_ms) = flags.optional_i64("max-age-ms")? {
        body.insert("max_age_ms".to_string(), json!(max_age_ms));
    }
    if let Some(limit) = flags.optional_usize("limit")? {
        body.insert("limit".to_string(), json!(limit));
    }
    Ok(cli_http_body(writeback_candidate_maintenance_json(
        config,
        "",
        &Value::Object(body).to_string(),
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

fn gateway_model_call_plan_cli_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let mut body = serde_json::Map::new();
    insert_string_flag(&mut body, &flags, "request-id", "request_id");
    insert_string_flag(&mut body, &flags, "audit-ref", "audit_ref");
    insert_string_flag(&mut body, &flags, "requester-role", "requester_role");
    insert_string_flag(&mut body, &flags, "use-mode", "use_mode");
    insert_string_flag(&mut body, &flags, "scope", "scope");
    insert_string_flag(&mut body, &flags, "project-id", "project_id");
    insert_string_flag(&mut body, &flags, "agent-id", "agent_id");
    insert_string_flag(&mut body, &flags, "provider-id", "provider_id");
    insert_string_flag(&mut body, &flags, "model-id", "model_id");
    insert_string_flag(&mut body, &flags, "task-kind", "task_kind");
    insert_string_flag(&mut body, &flags, "prompt", "prompt");
    insert_string_flag(&mut body, &flags, "latest-user", "latest_user");
    insert_string_flag(&mut body, &flags, "query", "query");
    insert_string_flag(
        &mut body,
        &flags,
        "serving-profile-id",
        "serving_profile_id",
    );
    insert_bool_flag(
        &mut body,
        &flags,
        "remote-export-requested",
        "remote_export_requested",
    );
    insert_bool_flag(&mut body, &flags, "execute", "execute");
    insert_bool_flag(&mut body, &flags, "apply", "apply");
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
    Ok(cli_http_body(
        memory_gateway_model_call_plan_json_from_value(config, &Value::Object(body)),
    ))
}

fn gateway_model_call_execution_gate_cli_json(
    config: &HubConfig,
    flags: FlagArgs,
) -> Result<String, String> {
    let mut body = serde_json::Map::new();
    insert_string_flag(&mut body, &flags, "request-id", "request_id");
    insert_string_flag(&mut body, &flags, "audit-ref", "audit_ref");
    insert_string_flag(&mut body, &flags, "requester-role", "requester_role");
    insert_string_flag(&mut body, &flags, "use-mode", "use_mode");
    insert_string_flag(&mut body, &flags, "scope", "scope");
    insert_string_flag(&mut body, &flags, "project-id", "project_id");
    insert_string_flag(&mut body, &flags, "provider-id", "provider_id");
    insert_string_flag(&mut body, &flags, "model-id", "model_id");
    insert_string_flag(&mut body, &flags, "task-kind", "task_kind");
    insert_string_flag(&mut body, &flags, "prompt", "prompt");
    insert_string_flag(&mut body, &flags, "latest-user", "latest_user");
    insert_string_flag(
        &mut body,
        &flags,
        "serving-profile-id",
        "serving_profile_id",
    );
    insert_bool_flag(&mut body, &flags, "execute", "execute");
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
    Ok(cli_http_body(
        memory_gateway_model_call_execution_gate_json_from_value(config, &Value::Object(body)),
    ))
}

fn gateway_model_call_execute_cli_json(
    config: &HubConfig,
    flags: FlagArgs,
) -> Result<String, String> {
    let mut body = serde_json::Map::new();
    insert_string_flag(&mut body, &flags, "request-id", "request_id");
    insert_string_flag(&mut body, &flags, "audit-ref", "audit_ref");
    insert_string_flag(&mut body, &flags, "requester-role", "requester_role");
    insert_string_flag(&mut body, &flags, "use-mode", "use_mode");
    insert_string_flag(&mut body, &flags, "scope", "scope");
    insert_string_flag(&mut body, &flags, "project-id", "project_id");
    insert_string_flag(&mut body, &flags, "provider-id", "provider_id");
    insert_string_flag(&mut body, &flags, "model-id", "model_id");
    insert_string_flag(&mut body, &flags, "task-kind", "task_kind");
    insert_string_flag(&mut body, &flags, "prompt", "prompt");
    insert_string_flag(&mut body, &flags, "latest-user", "latest_user");
    insert_string_flag(&mut body, &flags, "query", "query");
    insert_string_flag(
        &mut body,
        &flags,
        "serving-profile-id",
        "serving_profile_id",
    );
    insert_bool_flag(&mut body, &flags, "execute", "execute");
    insert_bool_flag(&mut body, &flags, "apply", "apply");
    insert_bool_flag(&mut body, &flags, "commit", "commit");
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
    if let Some(value) = flags.optional_u64("timeout-ms")? {
        body.insert("timeout_ms".to_string(), json!(value));
    }
    Ok(cli_http_body(
        memory_gateway_model_call_execute_json_from_value(config, &Value::Object(body)),
    ))
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

pub fn user_reveal_grant_http_json(
    config: &HubConfig,
    route_path: &str,
    method: &str,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    if method != "POST" {
        return (
            "405 Method Not Allowed",
            memory_user_reveal_grant_error_value(
                "error",
                "method_not_allowed",
                "POST is required for memory user reveal grants",
            )
            .to_string()
                + "\n",
        );
    }

    let parsed = match parse_json_body(body) {
        Ok(value) => value,
        Err(HttpJsonError { status, body }) => return (status, format!("{body}\n")),
    };
    let route_action = route_path
        .strip_prefix("/memory/user-reveal-grant")
        .and_then(|suffix| suffix.strip_prefix('/'))
        .map(|suffix| suffix.trim_matches('/'))
        .filter(|suffix| !suffix.is_empty())
        .map(|suffix| suffix.to_ascii_lowercase());
    let action = route_action
        .or_else(|| query_param(query, "action"))
        .or_else(|| value_string(&parsed, "action"))
        .unwrap_or_else(|| "evaluate".to_string())
        .trim()
        .to_ascii_lowercase()
        .replace('-', "_");

    let result = match action.as_str() {
        "issue" | "grant" => memory_user_reveal_grant_issue_json(config, &parsed),
        "revoke" | "end" => memory_user_reveal_grant_revoke_json(config, &parsed),
        "evaluate" | "status" | "check" => memory_user_reveal_grant_evaluate_json(config, &parsed),
        _ => Err(memory_user_reveal_grant_error(
            "400 Bad Request",
            "memory_user_reveal_grant_action_invalid",
            "unsupported memory user reveal grant action".to_string(),
        )),
    };

    match result {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(HttpJsonError { status, body }) => (status, format!("{body}\n")),
    }
}

pub fn object_item_http_json(
    config: &HubConfig,
    route_path: &str,
    method: &str,
    query: &str,
    body: &str,
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
    if matches!(action, "approve" | "reject") {
        if method != "POST" {
            return (
                "405 Method Not Allowed",
                json!({
                    "schema_version": MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
                    "ok": false,
                    "status": "error",
                    "error_code": "method_not_allowed",
                    "memory_id": memory_id,
                    "action": action,
                })
                .to_string()
                    + "\n",
            );
        }
        return match transition_memory_object_candidate_json(config, &memory_id, action, body) {
            Ok(body) => ("200 OK", format!("{body}\n")),
            Err(HttpJsonError { status, body }) => (status, format!("{body}\n")),
        };
    }
    if matches!(action, "archive" | "delete" | "pin" | "unpin") {
        if method != "POST" {
            return (
                "405 Method Not Allowed",
                json!({
                    "schema_version": MEMORY_OBJECT_MUTATION_SCHEMA,
                    "ok": false,
                    "status": "error",
                    "error_code": "method_not_allowed",
                    "memory_id": memory_id,
                    "action": action,
                })
                .to_string()
                    + "\n",
            );
        }
        return match memory_object_mutation_json(config, &memory_id, action, body) {
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
                "supported_actions": ["history", "approve", "reject", "archive", "delete", "pin", "unpin"],
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
                "supported_now": ["GET", "GET /history", "POST /archive", "POST /delete", "POST /pin", "POST /unpin"],
            })
            .to_string()
                + "\n",
        ),
    }
}

pub fn writeback_candidates_http_json(
    config: &HubConfig,
    route_path: &str,
    method: &str,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    let suffix = route_path
        .strip_prefix("/memory/writeback/candidates")
        .unwrap_or_default()
        .trim_start_matches('/');
    if suffix.is_empty() {
        return match method {
            "POST" => match create_writeback_candidate_json_from_body(config, body) {
                Ok(body) => ("200 OK", format!("{body}\n")),
                Err(HttpJsonError { status, body }) => (status, format!("{body}\n")),
            },
            "GET" => match list_writeback_candidates_json(config, query) {
                Ok(body) => ("200 OK", format!("{body}\n")),
                Err(HttpJsonError { status, body }) => (status, format!("{body}\n")),
            },
            _ => (
                "405 Method Not Allowed",
                json!({
                    "schema_version": MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
                    "ok": false,
                    "status": "error",
                    "error_code": "method_not_allowed",
                })
                .to_string()
                    + "\n",
            ),
        };
    }
    if matches!(suffix, "maintenance" | "maintain" | "stale-maintenance") {
        if method != "POST" {
            return (
                "405 Method Not Allowed",
                json!({
                    "schema_version": MEMORY_WRITEBACK_CANDIDATE_MAINTENANCE_SCHEMA,
                    "ok": false,
                    "status": "error",
                    "error_code": "method_not_allowed",
                })
                .to_string()
                    + "\n",
            );
        }
        return match writeback_candidate_maintenance_json(config, query, body) {
            Ok(body) => ("200 OK", format!("{body}\n")),
            Err(HttpJsonError { status, body }) => (status, format!("{body}\n")),
        };
    }
    if matches!(suffix, "extract" | "extract-from-delta" | "axmemory-delta") {
        if method != "POST" {
            return (
                "405 Method Not Allowed",
                json!({
                    "schema_version": MEMORY_WRITEBACK_CANDIDATE_EXTRACT_SCHEMA,
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
        let apply = query_bool(query, "apply", true)
            && !query_bool(query, "dry_run", false)
            && !query_bool(query, "dryRun", false);
        return match writeback_candidate_extract_json_from_value(config, &parsed, apply) {
            Ok(body) => ("200 OK", format!("{body}\n")),
            Err(HttpJsonError { status, body }) => (status, format!("{body}\n")),
        };
    }
    let (memory_id, action) = suffix.split_once('/').unwrap_or((suffix, ""));
    let memory_id = percent_decode(memory_id).unwrap_or_else(|_| memory_id.to_string());
    if !matches!(action, "approve" | "reject") {
        return (
            "404 Not Found",
            json!({
                "schema_version": MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
                "ok": false,
                "status": "not_found",
                "error_code": "memory_writeback_candidate_action_not_found",
                "memory_id": memory_id,
                "action": action,
                "supported_actions": ["approve", "reject"],
            })
            .to_string()
                + "\n",
        );
    }
    if method != "POST" {
        return (
            "405 Method Not Allowed",
            json!({
                "schema_version": MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
                "ok": false,
                "status": "error",
                "error_code": "method_not_allowed",
                "memory_id": memory_id,
                "action": action,
            })
            .to_string()
                + "\n",
        );
    }
    match transition_memory_object_candidate_json(config, &memory_id, action, body) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(HttpJsonError { status, body }) => (status, format!("{body}\n")),
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

pub fn memory_gateway_model_call_plan_http_json(
    config: &HubConfig,
    method: &str,
    body: &str,
) -> (&'static str, String) {
    if method != "POST" {
        return (
            "405 Method Not Allowed",
            json!({
                "schema_version": MEMORY_GATEWAY_MODEL_CALL_PLAN_SCHEMA,
                "ok": false,
                "status": "error",
                "error_code": "method_not_allowed",
                "production_authority_change": false,
                "model_call_executed": false,
            })
            .to_string()
                + "\n",
        );
    }
    let parsed = match parse_json_body(body) {
        Ok(value) => value,
        Err(err) => return (err.status, format!("{}\n", err.body)),
    };
    match memory_gateway_model_call_plan_json_from_value(config, &parsed) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(HttpJsonError { status, body }) => (status, format!("{body}\n")),
    }
}

pub fn memory_gateway_model_call_execution_gate_http_json(
    config: &HubConfig,
    method: &str,
    body: &str,
) -> (&'static str, String) {
    if method != "POST" {
        return (
            "405 Method Not Allowed",
            json!({
                "schema_version": MEMORY_GATEWAY_MODEL_CALL_EXECUTION_GATE_SCHEMA,
                "ok": false,
                "status": "error",
                "error_code": "method_not_allowed",
                "production_authority_change": false,
                "would_call_model": false,
                "model_call_executed": false,
            })
            .to_string()
                + "\n",
        );
    }
    let parsed = match parse_json_body(body) {
        Ok(value) => value,
        Err(err) => return (err.status, format!("{}\n", err.body)),
    };
    match memory_gateway_model_call_execution_gate_json_from_value(config, &parsed) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(HttpJsonError { status, body }) => (status, format!("{body}\n")),
    }
}

pub fn memory_gateway_model_call_execute_http_json(
    config: &HubConfig,
    method: &str,
    body: &str,
) -> (&'static str, String) {
    if method != "POST" {
        return (
            "405 Method Not Allowed",
            json!({
                "schema_version": MEMORY_GATEWAY_MODEL_CALL_EXECUTE_SCHEMA,
                "ok": false,
                "status": "error",
                "error_code": "method_not_allowed",
                "production_authority_change": false,
                "would_call_model": false,
                "model_call_executed": false,
            })
            .to_string()
                + "\n",
        );
    }
    let parsed = match parse_json_body(body) {
        Ok(value) => value,
        Err(err) => return (err.status, format!("{}\n", err.body)),
    };
    match memory_gateway_model_call_execute_json_from_value(config, &parsed) {
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

fn create_writeback_candidate_json_from_body(
    config: &HubConfig,
    body: &str,
) -> Result<String, HttpJsonError> {
    let mut parsed = parse_json_body(body)?;
    let Some(map) = parsed.as_object_mut() else {
        return Err(http_json_error(
            "400 Bad Request",
            "memory_writeback_candidate_json_object_required",
            "JSON object body is required".to_string(),
        ));
    };
    map.insert("status".to_string(), json!("candidate"));
    map.entry("requester_role".to_string())
        .or_insert_with(|| json!("tool"));
    map.entry("use_mode".to_string())
        .or_insert_with(|| json!("tool_plan"));
    map.entry("reason".to_string())
        .or_insert_with(|| json!("memory_writeback_candidate_create"));
    map.entry("source".to_string())
        .or_insert_with(|| json!("rust_memory_writeback_candidate_api"));
    let actor = sanitize_public_token(
        value_string(&parsed, "actor")
            .unwrap_or_else(|| "rust_hub".to_string())
            .as_str(),
    )
    .unwrap_or_else(|| "rust_hub".to_string());
    let audit_ref = value_string(&parsed, "audit_ref")
        .or_else(|| value_string(&parsed, "auditRef"))
        .unwrap_or_default();
    let created = create_memory_object_json_from_body(config, &parsed.to_string())?;
    let mut value = serde_json::from_str::<Value>(&created).map_err(|err| {
        http_json_error(
            "500 Internal Server Error",
            "memory_writeback_candidate_response_parse_failed",
            err.to_string(),
        )
    })?;
    if let Some(memory_id) = value_string(&value, "memory_id") {
        if let Some(object) = read_memory_object(&config.db_path, &memory_id).map_err(|err| {
            http_json_error(
                "500 Internal Server Error",
                "memory_object_read_failed",
                err.to_string(),
            )
        })? {
            let object =
                apply_writeback_candidate_conflict_metadata(config, object, &actor, &audit_ref)?;
            value["version"] = json!(object.version);
            value["object"] = memory_object_to_json(&object);
        }
    }
    value["schema_version"] = json!(MEMORY_WRITEBACK_CANDIDATE_SCHEMA);
    value["status"] = json!("candidate_created");
    value["candidate_writeback"] = json!({
        "enabled": true,
        "authority": "rust_policy_gated_candidate_queue",
        "requires_approval": true,
        "approved_status": "active",
        "rejected_status": "rejected",
        "production_authority_change": false,
    });
    value["production_authority_change"] = json!(false);
    Ok(value.to_string())
}

#[derive(Debug, Clone)]
struct WritebackCandidateExtractPlan {
    key: String,
    memory_id: String,
    operation: String,
    reason_code: String,
    source_kind: String,
    layer: String,
    title: String,
    text_preview: String,
    object: Option<MemoryObjectRecord>,
    event: Option<MemoryEventRecord>,
}

#[derive(Debug, Clone, Copy)]
struct AxMemoryDeltaCandidateKind {
    key: &'static str,
    camel_key: &'static str,
    suffix: &'static str,
    title: &'static str,
    source_kind: &'static str,
    layer: &'static str,
    text_prefix: &'static str,
    is_array: bool,
}

const AX_MEMORY_DELTA_CANDIDATE_KINDS: &[AxMemoryDeltaCandidateKind] = &[
    AxMemoryDeltaCandidateKind {
        key: "goal_update",
        camel_key: "goalUpdate",
        suffix: "goal",
        title: "Project goal candidate",
        source_kind: "project_goal",
        layer: "l1_canonical",
        text_prefix: "Goal",
        is_array: false,
    },
    AxMemoryDeltaCandidateKind {
        key: "requirements_add",
        camel_key: "requirementsAdd",
        suffix: "requirements",
        title: "Project requirement candidate",
        source_kind: "project_requirement",
        layer: "l1_canonical",
        text_prefix: "Requirement",
        is_array: true,
    },
    AxMemoryDeltaCandidateKind {
        key: "current_state_add",
        camel_key: "currentStateAdd",
        suffix: "current_state",
        title: "Current state candidate",
        source_kind: "current_state",
        layer: "l3_working_set",
        text_prefix: "Current state",
        is_array: true,
    },
    AxMemoryDeltaCandidateKind {
        key: "decisions_add",
        camel_key: "decisionsAdd",
        suffix: "decisions",
        title: "Decision candidate",
        source_kind: "decision_track",
        layer: "l1_canonical",
        text_prefix: "Decision",
        is_array: true,
    },
    AxMemoryDeltaCandidateKind {
        key: "next_steps_add",
        camel_key: "nextStepsAdd",
        suffix: "next_steps",
        title: "Next step candidate",
        source_kind: "next_step",
        layer: "l3_working_set",
        text_prefix: "Next step",
        is_array: true,
    },
    AxMemoryDeltaCandidateKind {
        key: "open_questions_add",
        camel_key: "openQuestionsAdd",
        suffix: "open_questions",
        title: "Open question candidate",
        source_kind: "open_question",
        layer: "l2_observations",
        text_prefix: "Open question",
        is_array: true,
    },
    AxMemoryDeltaCandidateKind {
        key: "risks_add",
        camel_key: "risksAdd",
        suffix: "risks",
        title: "Risk candidate",
        source_kind: "risk",
        layer: "l2_observations",
        text_prefix: "Risk",
        is_array: true,
    },
    AxMemoryDeltaCandidateKind {
        key: "recommendations_add",
        camel_key: "recommendationsAdd",
        suffix: "recommendations",
        title: "Recommendation candidate",
        source_kind: "recommendation",
        layer: "l2_observations",
        text_prefix: "Recommendation",
        is_array: true,
    },
];

fn writeback_candidate_extract_json_from_value(
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
    let delta = body
        .get("ax_memory_delta")
        .or_else(|| body.get("axMemoryDelta"))
        .or_else(|| body.get("memory_delta"))
        .or_else(|| body.get("memoryDelta"))
        .or_else(|| body.get("delta"))
        .unwrap_or(body);
    let project_id = sanitize_public_token(
        &value_string(body, "project_id")
            .or_else(|| value_string(body, "projectId"))
            .or_else(|| value_string(delta, "project_id"))
            .or_else(|| value_string(delta, "projectId"))
            .unwrap_or_default(),
    )
    .ok_or_else(|| {
        http_json_error(
            "400 Bad Request",
            "project_id_required",
            "project_id is required".to_string(),
        )
    })?;
    let owner_id = sanitize_public_token(
        &value_string(body, "owner_id")
            .or_else(|| value_string(body, "ownerId"))
            .unwrap_or_else(|| project_id.clone()),
    )
    .unwrap_or_else(|| project_id.clone());
    let run_id =
        optional_public_token(body, "run_id").or_else(|| optional_public_token(body, "runId"));
    let agent_id =
        optional_public_token(body, "agent_id").or_else(|| optional_public_token(body, "agentId"));
    let audit_ref = value_string(body, "audit_ref")
        .or_else(|| value_string(body, "auditRef"))
        .unwrap_or_else(|| format!("memory_writeback_candidate_extract:{project_id}"));
    if looks_like_secret_public(&audit_ref) {
        return Err(http_json_error_json(
            "403 Forbidden",
            json!({
                "schema_version": MEMORY_WRITEBACK_CANDIDATE_EXTRACT_SCHEMA,
                "ok": false,
                "status": "denied",
                "deny_code": "memory_secret_pattern_denied",
                "production_authority_change": false,
            }),
        ));
    }
    let actor = sanitize_public_token(
        value_string(body, "actor")
            .unwrap_or_else(|| "rust_hub".to_string())
            .as_str(),
    )
    .unwrap_or_else(|| "rust_hub".to_string());
    let evidence_refs = value_string_list(body, "evidence_refs")
        .or_else(|| value_string_list(body, "evidenceRefs"))
        .unwrap_or_default();
    let ttl_ms = value_i64(body, "ttl_ms").or_else(|| value_i64(body, "ttlMs"));

    let mut plans = Vec::<WritebackCandidateExtractPlan>::new();
    let mut seen_memory_ids = BTreeSet::<String>::new();
    for kind in AX_MEMORY_DELTA_CANDIDATE_KINDS {
        let texts = ax_memory_delta_texts(delta, kind);
        for (index, raw_text) in texts.into_iter().enumerate() {
            if plans.len() >= 128 {
                plans.push(WritebackCandidateExtractPlan {
                    key: format!("{}.{}", kind.key, index),
                    memory_id: String::new(),
                    operation: "skip".to_string(),
                    reason_code: "candidate_extract_limit_reached".to_string(),
                    source_kind: kind.source_kind.to_string(),
                    layer: kind.layer.to_string(),
                    title: kind.title.to_string(),
                    text_preview: String::new(),
                    object: None,
                    event: None,
                });
                continue;
            }
            let key = if kind.is_array {
                format!("{}.{}", kind.key, index)
            } else {
                kind.key.to_string()
            };
            let Some(clean_text) = sanitize_public_text(&raw_text, 4_000) else {
                plans.push(WritebackCandidateExtractPlan {
                    key,
                    memory_id: String::new(),
                    operation: "deny".to_string(),
                    reason_code: "memory_secret_pattern_denied".to_string(),
                    source_kind: kind.source_kind.to_string(),
                    layer: kind.layer.to_string(),
                    title: kind.title.to_string(),
                    text_preview: String::new(),
                    object: None,
                    event: None,
                });
                continue;
            };
            let text = format!("{}: {}", kind.text_prefix, clean_text);
            let memory_id = writeback_candidate_extract_memory_id(&project_id, kind.suffix, &text);
            if !seen_memory_ids.insert(memory_id.clone()) {
                plans.push(WritebackCandidateExtractPlan {
                    key,
                    memory_id,
                    operation: "duplicate".to_string(),
                    reason_code: "duplicate_in_request".to_string(),
                    source_kind: kind.source_kind.to_string(),
                    layer: kind.layer.to_string(),
                    title: kind.title.to_string(),
                    text_preview: summarize_memory_text(&text),
                    object: None,
                    event: None,
                });
                continue;
            }
            if let Some(existing) =
                read_memory_object(&config.db_path, &memory_id).map_err(|err| {
                    http_json_error(
                        "500 Internal Server Error",
                        "memory_object_read_failed",
                        err.to_string(),
                    )
                })?
            {
                plans.push(WritebackCandidateExtractPlan {
                    key,
                    memory_id,
                    operation: "duplicate".to_string(),
                    reason_code: format!("duplicate_{}", existing.status),
                    source_kind: kind.source_kind.to_string(),
                    layer: kind.layer.to_string(),
                    title: kind.title.to_string(),
                    text_preview: summarize_memory_text(&existing.text),
                    object: None,
                    event: None,
                });
                continue;
            }
            let policy = evaluate_memory_policy(&json!({
                "requester_role": "tool",
                "use_mode": "tool_plan",
                "scope": "project",
                "requested_layers": [kind.layer],
                "requested_source_kinds": [kind.source_kind],
                "remote_export_requested": false,
            }));
            if policy.decision != "allow" {
                plans.push(WritebackCandidateExtractPlan {
                    key,
                    memory_id,
                    operation: "deny".to_string(),
                    reason_code: policy.deny_code,
                    source_kind: kind.source_kind.to_string(),
                    layer: kind.layer.to_string(),
                    title: kind.title.to_string(),
                    text_preview: summarize_memory_text(&text),
                    object: None,
                    event: None,
                });
                continue;
            }

            let now = now_ms_i64();
            let policy_json = json!({
                "write_gate": "rust_policy_gated_candidate_queue",
                "allowed_roles": policy.allowed_roles,
                "denied_roles": policy.denied_roles,
                "remote_export": "local_only",
                "candidate_extractor": MEMORY_WRITEBACK_CANDIDATE_EXTRACT_SCHEMA,
                "requires_approval": true,
            })
            .to_string();
            let provenance_json = json!({
                "source": value_string(body, "source").unwrap_or_else(|| "xt_axmemory_delta_candidate_extract".to_string()),
                "audit_ref": audit_ref,
                "created_by": actor,
                "evidence_refs": &evidence_refs,
                "delta_key": kind.key,
                "candidate_reason": "deterministic_axmemory_delta",
                "production_authority_change": false,
            })
            .to_string();
            let object = MemoryObjectRecord {
                memory_id: memory_id.clone(),
                schema_version: MEMORY_OBJECT_SCHEMA.to_string(),
                scope: "project".to_string(),
                owner_id: owner_id.clone(),
                run_id: run_id.clone(),
                project_id: Some(project_id.clone()),
                agent_id: agent_id.clone(),
                source_kind: kind.source_kind.to_string(),
                layer: kind.layer.to_string(),
                title: kind.title.to_string(),
                text: text.clone(),
                summary: summarize_memory_text(&text),
                tags_json: json!(["candidate_extract", "ax_memory_delta", kind.suffix]).to_string(),
                sensitivity: "internal".to_string(),
                visibility: "local_only".to_string(),
                status: "candidate".to_string(),
                pinned: false,
                immutable: false,
                ttl_ms,
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
                operation: "candidate_extract".to_string(),
                actor: actor.clone(),
                reason: "deterministic_axmemory_delta".to_string(),
                before_version: None,
                after_version: Some(1),
                before_json: None,
                after_json: Some(after_json),
                policy_decision: "allow".to_string(),
                deny_code: String::new(),
                audit_ref: audit_ref.clone(),
                created_at_ms: now,
            };
            plans.push(WritebackCandidateExtractPlan {
                key,
                memory_id,
                operation: "create".to_string(),
                reason_code: String::new(),
                source_kind: kind.source_kind.to_string(),
                layer: kind.layer.to_string(),
                title: kind.title.to_string(),
                text_preview: summarize_memory_text(&text),
                object: Some(object),
                event: Some(event),
            });
        }
    }

    let blocking_count = plans.iter().filter(|plan| plan.operation == "deny").count();
    if apply && blocking_count > 0 {
        return Err(http_json_error_json(
            "403 Forbidden",
            writeback_candidate_extract_response(&project_id, true, false, &plans),
        ));
    }
    if apply {
        for plan in &plans {
            if plan.operation != "create" {
                continue;
            }
            let Some(object) = plan.object.as_ref() else {
                continue;
            };
            let Some(event) = plan.event.as_ref() else {
                continue;
            };
            create_memory_object_with_event(&config.db_path, object, event).map_err(|err| {
                http_json_error(
                    "500 Internal Server Error",
                    "memory_writeback_candidate_extract_failed",
                    err.to_string(),
                )
            })?;
        }
    }

    Ok(writeback_candidate_extract_response(&project_id, apply, apply, &plans).to_string())
}

fn writeback_candidate_extract_response(
    project_id: &str,
    apply_requested: bool,
    applied: bool,
    plans: &[WritebackCandidateExtractPlan],
) -> Value {
    let created_count = plans
        .iter()
        .filter(|plan| plan.operation == "create")
        .count();
    let duplicate_count = plans
        .iter()
        .filter(|plan| plan.operation == "duplicate")
        .count();
    let skipped_count = plans.iter().filter(|plan| plan.operation == "skip").count();
    let blocking_count = plans.iter().filter(|plan| plan.operation == "deny").count();
    json!({
        "schema_version": MEMORY_WRITEBACK_CANDIDATE_EXTRACT_SCHEMA,
        "ok": blocking_count == 0,
        "status": if blocking_count == 0 { "ok" } else { "denied" },
        "project_id": project_id,
        "apply_requested": apply_requested,
        "dry_run": !apply_requested,
        "applied": applied,
        "planned_count": plans.len(),
        "candidate_count": if applied { created_count } else { 0 },
        "created_count": if applied { created_count } else { 0 },
        "planned_create_count": created_count,
        "duplicate_count": duplicate_count,
        "skipped_count": skipped_count,
        "blocking_count": blocking_count,
        "items": plans.iter().map(|plan| {
            json!({
                "key": &plan.key,
                "memory_id": if plan.memory_id.is_empty() { Value::Null } else { json!(&plan.memory_id) },
                "operation": &plan.operation,
                "reason_code": &plan.reason_code,
                "source_kind": &plan.source_kind,
                "layer": &plan.layer,
                "title": &plan.title,
                "text_preview": &plan.text_preview,
            })
        }).collect::<Vec<_>>(),
        "candidate_writeback": {
            "enabled": true,
            "authority": "rust_policy_gated_candidate_queue",
            "requires_approval": true,
            "active_write": false,
            "production_authority_change": false,
        },
        "production_authority_change": false,
    })
}

fn ax_memory_delta_texts(delta: &Value, kind: &AxMemoryDeltaCandidateKind) -> Vec<String> {
    if kind.is_array {
        value_string_list(delta, kind.key)
            .or_else(|| value_string_list(delta, kind.camel_key))
            .unwrap_or_default()
    } else {
        value_string(delta, kind.key)
            .or_else(|| value_string(delta, kind.camel_key))
            .map(|value| vec![value])
            .unwrap_or_default()
    }
}

fn writeback_candidate_extract_memory_id(project_id: &str, suffix: &str, text: &str) -> String {
    let project = sanitize_id_segment(project_id, 56);
    let suffix = sanitize_id_segment(suffix, 40);
    let hash = stable_fnv1a64_hex(&format!(
        "{}\n{}\n{}",
        project,
        suffix,
        text.split_whitespace()
            .collect::<Vec<_>>()
            .join(" ")
            .to_ascii_lowercase()
    ));
    format!("mc_ax_{project}_{suffix}_{hash}")
}

fn apply_writeback_candidate_conflict_metadata(
    config: &HubConfig,
    object: MemoryObjectRecord,
    actor: &str,
    audit_ref: &str,
) -> Result<MemoryObjectRecord, HttpJsonError> {
    let active_conflicts = writeback_candidate_active_conflicts(config, &object)?;
    let peer_candidates = writeback_candidate_peer_candidates(config, &object)?;
    let duplicate_ids = peer_candidates
        .iter()
        .filter(|candidate| candidate.memory_id != object.memory_id)
        .filter(|candidate| writeback_candidate_same_text(candidate, &object))
        .map(|candidate| candidate.memory_id.clone())
        .collect::<Vec<_>>();
    let superseded_candidates = peer_candidates
        .into_iter()
        .filter(|candidate| candidate.memory_id != object.memory_id)
        .filter(|candidate| !writeback_candidate_same_text(candidate, &object))
        .filter(|candidate| !candidate.immutable)
        .filter(|candidate| !writeback_candidate_has_active_review_lock(candidate))
        .collect::<Vec<_>>();
    let active_conflict_ids = active_conflicts
        .iter()
        .map(|active| active.memory_id.clone())
        .collect::<Vec<_>>();
    let supersedes = superseded_candidates
        .iter()
        .map(|candidate| candidate.memory_id.clone())
        .collect::<Vec<_>>();
    let candidate_generation = (duplicate_ids.len() + supersedes.len() + 1) as i64;
    if active_conflict_ids.is_empty()
        && duplicate_ids.is_empty()
        && supersedes.is_empty()
        && candidate_generation <= 1
    {
        return Ok(object);
    }

    let now = now_ms_i64();
    for mut superseded in superseded_candidates {
        let before_version = superseded.version;
        let before_json = memory_object_to_json(&superseded).to_string();
        superseded.status = "archived".to_string();
        superseded.updated_at_ms = now;
        superseded.last_accessed_at_ms = now;
        superseded.version = superseded.version.saturating_add(1);
        superseded.policy_json = memory_policy_json_with_candidate_superseded_by(
            &superseded.policy_json,
            &object.memory_id,
            actor,
            audit_ref,
            now,
        );
        superseded.provenance_json = memory_provenance_json_with_candidate_superseded_by(
            &superseded.provenance_json,
            &object.memory_id,
            actor,
            audit_ref,
            now,
        );
        let after_json = memory_object_to_json(&superseded).to_string();
        let event = MemoryEventRecord {
            event_id: next_memory_event_id(),
            memory_id: superseded.memory_id.clone(),
            operation: "candidate_superseded".to_string(),
            actor: actor.to_string(),
            reason: "writeback_candidate_superseded_by_newer_candidate".to_string(),
            before_version: Some(before_version),
            after_version: Some(superseded.version),
            before_json: Some(before_json),
            after_json: Some(after_json),
            policy_decision: "allow".to_string(),
            deny_code: String::new(),
            audit_ref: audit_ref.to_string(),
            created_at_ms: now,
        };
        update_memory_object_with_event(&config.db_path, &superseded, &event).map_err(|err| {
            http_json_error(
                "500 Internal Server Error",
                "memory_writeback_candidate_supersession_failed",
                err.to_string(),
            )
        })?;
    }

    let before_json = memory_object_to_json(&object).to_string();
    let mut updated = object.clone();
    updated.updated_at_ms = now;
    updated.last_accessed_at_ms = now;
    updated.version = object.version.saturating_add(1);
    updated.policy_json = memory_policy_json_with_candidate_conflict_metadata(
        &object.policy_json,
        &active_conflict_ids,
        &duplicate_ids,
        &supersedes,
        candidate_generation,
        actor,
        audit_ref,
        now,
    );
    updated.provenance_json = memory_provenance_json_with_candidate_conflict_metadata(
        &object.provenance_json,
        &active_conflict_ids,
        &duplicate_ids,
        &supersedes,
        candidate_generation,
        actor,
        audit_ref,
        now,
    );
    let after_json = memory_object_to_json(&updated).to_string();
    let event = MemoryEventRecord {
        event_id: next_memory_event_id(),
        memory_id: updated.memory_id.clone(),
        operation: "candidate_conflict_scan".to_string(),
        actor: actor.to_string(),
        reason: "writeback_candidate_conflict_supersession_scan".to_string(),
        before_version: Some(object.version),
        after_version: Some(updated.version),
        before_json: Some(before_json),
        after_json: Some(after_json),
        policy_decision: "allow".to_string(),
        deny_code: String::new(),
        audit_ref: audit_ref.to_string(),
        created_at_ms: now,
    };
    update_memory_object_with_event(&config.db_path, &updated, &event).map_err(|err| {
        http_json_error(
            "500 Internal Server Error",
            "memory_writeback_candidate_conflict_metadata_failed",
            err.to_string(),
        )
    })?;
    Ok(updated)
}

fn writeback_candidate_active_conflicts(
    config: &HubConfig,
    object: &MemoryObjectRecord,
) -> Result<Vec<MemoryObjectRecord>, HttpJsonError> {
    let filter = writeback_candidate_peer_filter(object, "active", 128);
    let objects = list_memory_objects(&config.db_path, &filter).map_err(|err| {
        http_json_error(
            "500 Internal Server Error",
            "memory_writeback_candidate_conflict_scan_failed",
            err.to_string(),
        )
    })?;
    Ok(objects
        .into_iter()
        .filter(|candidate| candidate.memory_id != object.memory_id)
        .filter(|candidate| writeback_candidate_same_partition(candidate, object))
        .filter(|candidate| !writeback_candidate_same_text(candidate, object))
        .collect())
}

fn writeback_candidate_peer_candidates(
    config: &HubConfig,
    object: &MemoryObjectRecord,
) -> Result<Vec<MemoryObjectRecord>, HttpJsonError> {
    let filter = writeback_candidate_peer_filter(object, "candidate", 128);
    let objects = list_memory_objects(&config.db_path, &filter).map_err(|err| {
        http_json_error(
            "500 Internal Server Error",
            "memory_writeback_candidate_peer_scan_failed",
            err.to_string(),
        )
    })?;
    Ok(objects
        .into_iter()
        .filter(|candidate| writeback_candidate_same_partition(candidate, object))
        .collect())
}

fn writeback_candidate_peer_filter(
    object: &MemoryObjectRecord,
    status: &str,
    limit: usize,
) -> MemoryObjectListFilter {
    MemoryObjectListFilter {
        scope: Some(object.scope.clone()),
        owner_id: Some(object.owner_id.clone()),
        project_id: object.project_id.clone(),
        agent_id: object.agent_id.clone(),
        source_kind: Some(object.source_kind.clone()),
        layer: Some(object.layer.clone()),
        status: Some(status.to_string()),
        sensitivity: None,
        visibility: None,
        limit,
    }
}

fn writeback_candidate_same_partition(a: &MemoryObjectRecord, b: &MemoryObjectRecord) -> bool {
    a.scope == b.scope
        && a.owner_id == b.owner_id
        && a.project_id == b.project_id
        && a.agent_id == b.agent_id
        && a.source_kind == b.source_kind
        && a.layer == b.layer
}

fn writeback_candidate_same_text(a: &MemoryObjectRecord, b: &MemoryObjectRecord) -> bool {
    normalized_memory_compare_text(&a.text) == normalized_memory_compare_text(&b.text)
}

fn normalized_memory_compare_text(value: &str) -> String {
    value
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_ascii_lowercase()
}

#[derive(Debug, Clone)]
struct WritebackCandidateMaintenancePlan {
    memory_id: String,
    owner_id: String,
    project_id: Option<String>,
    source_kind: String,
    layer: String,
    current_status: String,
    planned_status: String,
    operation: String,
    reason_code: String,
    age_ms: i64,
    ttl_ms: i64,
    event_id: Option<String>,
    object: Option<MemoryObjectRecord>,
    event: Option<MemoryEventRecord>,
}

fn writeback_candidate_maintenance_json(
    config: &HubConfig,
    query: &str,
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
    if !parsed.is_object() {
        return Err(http_json_error(
            "400 Bad Request",
            "memory_writeback_candidate_maintenance_json_object_required",
            "JSON object body is required".to_string(),
        ));
    }
    let dry_run_requested = query_bool(query, "dry_run", false)
        || query_bool(query, "dryRun", false)
        || value_bool(&parsed, "dry_run", false)
        || value_bool(&parsed, "dryRun", false);
    let apply_requested = (query_bool(query, "apply", false)
        || value_bool(&parsed, "apply", false))
        && !dry_run_requested;
    let body_limit = value_usize(&parsed, "limit").unwrap_or(100);
    let limit = query_usize(query, "limit", body_limit)
        .map_err(|err| http_json_error("400 Bad Request", "invalid_query_parameter", err))?
        .clamp(1, 500);
    let body_max_age_ms = value_i64(&parsed, "max_age_ms")
        .or_else(|| value_i64(&parsed, "maxAgeMs"))
        .filter(|value| *value > 0);
    let max_age_ms = query_i64_optional(query, "max_age_ms")
        .map_err(|err| http_json_error("400 Bad Request", "invalid_query_parameter", err))?
        .or_else(|| query_i64_optional(query, "maxAgeMs").ok().flatten())
        .or(body_max_age_ms);
    let project_id = query_param(query, "project_id")
        .or_else(|| query_param(query, "projectId"))
        .or_else(|| value_string(&parsed, "project_id"))
        .or_else(|| value_string(&parsed, "projectId"))
        .map(|value| {
            sanitize_public_token(&value).ok_or_else(|| {
                http_json_error(
                    "400 Bad Request",
                    "project_id_invalid",
                    "project_id is invalid".to_string(),
                )
            })
        })
        .transpose()?;
    let actor = sanitize_public_token(
        value_string(&parsed, "actor")
            .unwrap_or_else(|| "rust_hub".to_string())
            .as_str(),
    )
    .unwrap_or_else(|| "rust_hub".to_string());
    let audit_ref = value_string(&parsed, "audit_ref")
        .or_else(|| value_string(&parsed, "auditRef"))
        .unwrap_or_else(|| "memory_writeback_candidate_maintenance".to_string());
    if looks_like_secret_public(&audit_ref) {
        return Err(http_json_error_json(
            "403 Forbidden",
            json!({
                "schema_version": MEMORY_WRITEBACK_CANDIDATE_MAINTENANCE_SCHEMA,
                "ok": false,
                "status": "denied",
                "deny_code": "memory_secret_pattern_denied",
                "production_authority_change": false,
            }),
        ));
    }
    let reason = sanitize_public_text(
        &value_string(&parsed, "reason")
            .unwrap_or_else(|| "memory_writeback_candidate_maintenance".to_string()),
        240,
    )
    .unwrap_or_else(|| "memory_writeback_candidate_maintenance".to_string());
    let mut plans = writeback_candidate_maintenance_plans(
        config,
        project_id.clone(),
        max_age_ms,
        limit,
        apply_requested,
        &actor,
        &audit_ref,
        &reason,
    )?;
    if apply_requested {
        for plan in plans.iter_mut() {
            let Some(object) = plan.object.as_ref() else {
                continue;
            };
            let Some(event) = plan.event.as_ref() else {
                continue;
            };
            update_memory_object_with_event(&config.db_path, object, event).map_err(|err| {
                http_json_error(
                    "500 Internal Server Error",
                    "memory_writeback_candidate_maintenance_update_failed",
                    err.to_string(),
                )
            })?;
        }
    }
    Ok(writeback_candidate_maintenance_response(
        project_id.as_deref(),
        apply_requested,
        max_age_ms,
        limit,
        &plans,
    )
    .to_string())
}

fn writeback_candidate_maintenance_plans(
    config: &HubConfig,
    project_id: Option<String>,
    max_age_ms: Option<i64>,
    limit: usize,
    prepare_events: bool,
    actor: &str,
    audit_ref: &str,
    reason: &str,
) -> Result<Vec<WritebackCandidateMaintenancePlan>, HttpJsonError> {
    let filter = MemoryObjectListFilter {
        scope: None,
        owner_id: None,
        project_id,
        agent_id: None,
        source_kind: None,
        layer: None,
        status: Some("candidate".to_string()),
        sensitivity: None,
        visibility: None,
        limit,
    };
    let objects = list_memory_objects(&config.db_path, &filter).map_err(|err| {
        http_json_error(
            "500 Internal Server Error",
            "memory_writeback_candidate_maintenance_list_failed",
            err.to_string(),
        )
    })?;
    let now = now_ms_i64();
    Ok(objects
        .into_iter()
        .map(|object| {
            writeback_candidate_maintenance_plan(
                object,
                max_age_ms,
                now,
                prepare_events,
                actor,
                audit_ref,
                reason,
            )
        })
        .collect())
}

fn writeback_candidate_maintenance_plan(
    object: MemoryObjectRecord,
    max_age_ms: Option<i64>,
    now: i64,
    prepare_event: bool,
    actor: &str,
    audit_ref: &str,
    reason: &str,
) -> WritebackCandidateMaintenancePlan {
    let age_ms = if now > object.created_at_ms {
        now - object.created_at_ms
    } else {
        0
    };
    let ttl_ms = writeback_candidate_effective_ttl_ms(&object, max_age_ms);
    let mut operation = "keep".to_string();
    let mut reason_code = String::new();
    let mut planned_status = object.status.clone();
    let mut updated_object = None;
    let mut event = None;
    let mut event_id = None;

    if object.immutable {
        operation = "skip".to_string();
        reason_code = "candidate_immutable".to_string();
    } else if writeback_candidate_has_active_review_lock(&object) {
        operation = "skip".to_string();
        reason_code = "candidate_review_locked".to_string();
    } else if age_ms >= ttl_ms {
        if writeback_candidate_requires_stale_review(&object) {
            if writeback_candidate_already_marked_stale_review(&object) {
                operation = "skip".to_string();
                reason_code = "stale_review_already_required".to_string();
            } else {
                operation = "stale_review_required".to_string();
                reason_code = "high_value_candidate_stale".to_string();
                planned_status = "candidate".to_string();
            }
        } else {
            operation = "archive".to_string();
            reason_code = "low_risk_candidate_stale".to_string();
            planned_status = "archived".to_string();
        }
    }

    if prepare_event && matches!(operation.as_str(), "archive" | "stale_review_required") {
        let before_json = memory_object_to_json(&object).to_string();
        let mut next = object.clone();
        next.status = planned_status.clone();
        next.updated_at_ms = now;
        next.last_accessed_at_ms = now;
        next.version = object.version.saturating_add(1);
        next.policy_json = memory_policy_json_with_candidate_maintenance(
            &object.policy_json,
            &operation,
            &reason_code,
            actor,
            audit_ref,
            now,
        );
        next.provenance_json = memory_provenance_json_with_candidate_maintenance(
            &object.provenance_json,
            &operation,
            &reason_code,
            actor,
            audit_ref,
            now,
        );
        let after_json = memory_object_to_json(&next).to_string();
        let generated_event_id = next_memory_event_id();
        event_id = Some(generated_event_id.clone());
        event = Some(MemoryEventRecord {
            event_id: generated_event_id,
            memory_id: object.memory_id.clone(),
            operation: format!("candidate_{operation}"),
            actor: actor.to_string(),
            reason: reason.to_string(),
            before_version: Some(object.version),
            after_version: Some(next.version),
            before_json: Some(before_json),
            after_json: Some(after_json),
            policy_decision: "allow".to_string(),
            deny_code: String::new(),
            audit_ref: audit_ref.to_string(),
            created_at_ms: now,
        });
        updated_object = Some(next);
    }

    WritebackCandidateMaintenancePlan {
        memory_id: object.memory_id,
        owner_id: object.owner_id,
        project_id: object.project_id,
        source_kind: object.source_kind,
        layer: object.layer,
        current_status: object.status,
        planned_status,
        operation,
        reason_code,
        age_ms,
        ttl_ms,
        event_id,
        object: updated_object,
        event,
    }
}

fn writeback_candidate_maintenance_response(
    project_id: Option<&str>,
    apply_requested: bool,
    max_age_ms: Option<i64>,
    limit: usize,
    plans: &[WritebackCandidateMaintenancePlan],
) -> Value {
    let stale_count = plans
        .iter()
        .filter(|plan| matches!(plan.operation.as_str(), "archive" | "stale_review_required"))
        .count();
    let archived_count = plans
        .iter()
        .filter(|plan| plan.operation == "archive")
        .count();
    let stale_review_required_count = plans
        .iter()
        .filter(|plan| plan.operation == "stale_review_required")
        .count();
    let skipped_count = plans.iter().filter(|plan| plan.operation == "skip").count();
    let mutation_count = plans.iter().filter(|plan| plan.event.is_some()).count();
    json!({
        "schema_version": MEMORY_WRITEBACK_CANDIDATE_MAINTENANCE_SCHEMA,
        "ok": true,
        "status": "ok",
        "project_id": project_id,
        "apply_requested": apply_requested,
        "dry_run": !apply_requested,
        "applied": apply_requested,
        "limit": limit,
        "max_age_ms": max_age_ms,
        "candidate_count": plans.len(),
        "stale_count": stale_count,
        "archived_count": if apply_requested { archived_count } else { 0 },
        "planned_archive_count": archived_count,
        "stale_review_required_count": if apply_requested { stale_review_required_count } else { 0 },
        "planned_stale_review_required_count": stale_review_required_count,
        "skipped_count": skipped_count,
        "mutation_count": if apply_requested { mutation_count } else { 0 },
        "items": plans.iter().map(writeback_candidate_maintenance_plan_to_json).collect::<Vec<_>>(),
        "candidate_writeback": {
            "enabled": true,
            "authority": "rust_policy_gated_candidate_queue",
            "active_write": false,
            "maintenance_only": true,
            "production_authority_change": false,
        },
        "production_authority_change": false,
    })
}

fn writeback_candidate_maintenance_plan_to_json(plan: &WritebackCandidateMaintenancePlan) -> Value {
    json!({
        "memory_id": &plan.memory_id,
        "owner_id": &plan.owner_id,
        "project_id": plan.project_id.as_deref(),
        "source_kind": &plan.source_kind,
        "layer": &plan.layer,
        "current_status": &plan.current_status,
        "planned_status": &plan.planned_status,
        "operation": &plan.operation,
        "reason_code": &plan.reason_code,
        "age_ms": plan.age_ms,
        "ttl_ms": plan.ttl_ms,
        "applied": plan.event.is_some(),
        "event_id": plan.event_id.as_deref(),
    })
}

fn writeback_candidate_maintenance_readiness_json(config: &HubConfig) -> Value {
    match writeback_candidate_maintenance_plans(
        config,
        None,
        None,
        500,
        false,
        "rust_hub",
        "memory_writeback_candidate_maintenance_readiness",
        "memory_writeback_candidate_maintenance_readiness",
    ) {
        Ok(plans) => {
            let stale_count = plans
                .iter()
                .filter(|plan| {
                    matches!(plan.operation.as_str(), "archive" | "stale_review_required")
                })
                .count();
            let archive_count = plans
                .iter()
                .filter(|plan| plan.operation == "archive")
                .count();
            let stale_review_required_count = plans
                .iter()
                .filter(|plan| plan.operation == "stale_review_required")
                .count();
            json!({
                "maintenance_ready": true,
                "candidate_maintenance_http": true,
                "candidate_maintenance_cli": true,
                "candidate_maintenance_schema": MEMORY_WRITEBACK_CANDIDATE_MAINTENANCE_SCHEMA,
                "candidate_maintenance_limit": 500,
                "stale_candidate_count": stale_count,
                "planned_archive_count": archive_count,
                "planned_stale_review_required_count": stale_review_required_count,
                "last_maintenance_report_path": "",
            })
        }
        Err(err) => json!({
            "maintenance_ready": false,
            "candidate_maintenance_http": true,
            "candidate_maintenance_cli": true,
            "candidate_maintenance_schema": MEMORY_WRITEBACK_CANDIDATE_MAINTENANCE_SCHEMA,
            "stale_candidate_count": 0,
            "planned_archive_count": 0,
            "planned_stale_review_required_count": 0,
            "last_maintenance_report_path": "",
            "error": serde_json::from_str::<Value>(&err.body).unwrap_or_else(|_| json!({ "message": err.body })),
        }),
    }
}

#[derive(Debug, Clone, Default)]
struct WritebackCandidateDiagnostics {
    candidate_count: usize,
    sample_limit: usize,
    conflict_candidate_count: usize,
    stale_review_required_count: usize,
    stale_candidate_count: usize,
    planned_archive_count: usize,
    planned_stale_review_required_count: usize,
    active_review_lock_count: usize,
    superseding_candidate_count: usize,
    archived_superseded_count: usize,
    conflict_candidate_ids: Vec<String>,
    stale_review_required_ids: Vec<String>,
    superseding_candidate_ids: Vec<String>,
    archived_superseded_ids: Vec<String>,
}

fn writeback_candidate_diagnostics_value(
    config: &HubConfig,
    filter: &MemoryObjectListFilter,
) -> Result<Value, HttpJsonError> {
    let mut candidate_filter = filter.clone();
    candidate_filter.status = Some("candidate".to_string());
    candidate_filter.limit = 500;
    let candidates = list_memory_objects(&config.db_path, &candidate_filter).map_err(|err| {
        http_json_error(
            "500 Internal Server Error",
            "memory_writeback_candidate_diagnostics_failed",
            err.to_string(),
        )
    })?;

    let mut archived_filter = filter.clone();
    archived_filter.status = Some("archived".to_string());
    archived_filter.limit = 500;
    let archived = list_memory_objects(&config.db_path, &archived_filter).map_err(|err| {
        http_json_error(
            "500 Internal Server Error",
            "memory_writeback_candidate_diagnostics_failed",
            err.to_string(),
        )
    })?;

    Ok(
        writeback_candidate_diagnostics_from_objects(&candidates, &archived, now_ms_i64(), 500)
            .to_json(),
    )
}

fn writeback_candidate_diagnostics_readiness_json(config: &HubConfig) -> Value {
    let filter = MemoryObjectListFilter {
        limit: 500,
        ..Default::default()
    };
    match writeback_candidate_diagnostics_value(config, &filter) {
        Ok(value) => value,
        Err(err) => json!({
            "schema_version": MEMORY_WRITEBACK_CANDIDATE_DIAGNOSTICS_SCHEMA,
            "ready": false,
            "candidate_count": 0,
            "conflict_candidate_count": 0,
            "stale_review_required_count": 0,
            "stale_candidate_count": 0,
            "planned_archive_count": 0,
            "planned_stale_review_required_count": 0,
            "superseding_candidate_count": 0,
            "archived_superseded_count": 0,
            "queue_pressure": "unknown",
            "noise_score": 0,
            "error": serde_json::from_str::<Value>(&err.body).unwrap_or_else(|_| json!({ "message": err.body })),
            "production_authority_change": false,
        }),
    }
}

fn writeback_candidate_diagnostics_from_objects(
    candidates: &[MemoryObjectRecord],
    archived: &[MemoryObjectRecord],
    now: i64,
    sample_limit: usize,
) -> WritebackCandidateDiagnostics {
    let mut diagnostics = WritebackCandidateDiagnostics {
        candidate_count: candidates.len(),
        sample_limit,
        ..Default::default()
    };

    for object in candidates {
        let conflict_ids = writeback_candidate_conflict_ids(object);
        if !conflict_ids.is_empty()
            || memory_json_any_bool(
                &object.policy_json,
                &[
                    "conflict_resolution_required",
                    "candidate_conflict_required",
                ],
            )
            || memory_json_any_bool(
                &object.provenance_json,
                &[
                    "conflict_resolution_required",
                    "candidate_conflict_required",
                ],
            )
        {
            diagnostics.conflict_candidate_count += 1;
            push_bounded_id(&mut diagnostics.conflict_candidate_ids, &object.memory_id);
        }
        if writeback_candidate_already_marked_stale_review(object) {
            diagnostics.stale_review_required_count += 1;
            push_bounded_id(
                &mut diagnostics.stale_review_required_ids,
                &object.memory_id,
            );
        }
        if writeback_candidate_has_active_review_lock(object) {
            diagnostics.active_review_lock_count += 1;
        }

        let age_ms = now.saturating_sub(object.updated_at_ms.max(object.created_at_ms));
        if age_ms >= writeback_candidate_effective_ttl_ms(object, None) {
            diagnostics.stale_candidate_count += 1;
            if writeback_candidate_requires_stale_review(object) {
                diagnostics.planned_stale_review_required_count += 1;
            } else {
                diagnostics.planned_archive_count += 1;
            }
        }

        if !writeback_candidate_supersedes_ids(object).is_empty() {
            diagnostics.superseding_candidate_count += 1;
            push_bounded_id(
                &mut diagnostics.superseding_candidate_ids,
                &object.memory_id,
            );
        }
    }

    for object in archived {
        if writeback_candidate_superseded_by(object).is_some() {
            diagnostics.archived_superseded_count += 1;
            push_bounded_id(&mut diagnostics.archived_superseded_ids, &object.memory_id);
        }
    }

    diagnostics
}

impl WritebackCandidateDiagnostics {
    fn queue_pressure(&self) -> &'static str {
        if self.conflict_candidate_count > 0 || self.stale_review_required_count > 0 {
            "high"
        } else if self.stale_candidate_count > 0
            || self.superseding_candidate_count > 0
            || self.archived_superseded_count > 0
        {
            "medium"
        } else {
            "low"
        }
    }

    fn noise_score(&self) -> usize {
        self.conflict_candidate_count.saturating_mul(5)
            + self.stale_review_required_count.saturating_mul(4)
            + self.stale_candidate_count.saturating_mul(2)
            + self.archived_superseded_count
            + self.superseding_candidate_count
    }

    fn to_json(&self) -> Value {
        json!({
            "schema_version": MEMORY_WRITEBACK_CANDIDATE_DIAGNOSTICS_SCHEMA,
            "ready": true,
            "source": "rust_memory_object_store",
            "candidate_count": self.candidate_count,
            "sample_limit": self.sample_limit,
            "bounded": self.candidate_count >= self.sample_limit,
            "conflict_candidate_count": self.conflict_candidate_count,
            "stale_review_required_count": self.stale_review_required_count,
            "stale_candidate_count": self.stale_candidate_count,
            "planned_archive_count": self.planned_archive_count,
            "planned_stale_review_required_count": self.planned_stale_review_required_count,
            "active_review_lock_count": self.active_review_lock_count,
            "superseding_candidate_count": self.superseding_candidate_count,
            "archived_superseded_count": self.archived_superseded_count,
            "superseded_candidate_count": self.archived_superseded_count,
            "queue_pressure": self.queue_pressure(),
            "noise_score": self.noise_score(),
            "conflict_candidate_ids": self.conflict_candidate_ids,
            "stale_review_required_ids": self.stale_review_required_ids,
            "superseding_candidate_ids": self.superseding_candidate_ids,
            "archived_superseded_ids": self.archived_superseded_ids,
            "production_authority_change": false,
        })
    }
}

fn push_bounded_id(items: &mut Vec<String>, memory_id: &str) {
    if items.len() < MEMORY_RETRIEVAL_TRACE_LIMIT {
        items.push(memory_id.to_string());
    }
}

fn writeback_candidate_effective_ttl_ms(
    object: &MemoryObjectRecord,
    max_age_ms: Option<i64>,
) -> i64 {
    if let Some(value) = max_age_ms.filter(|value| *value > 0) {
        return value;
    }
    if let Some(value) = object.ttl_ms.filter(|value| *value > 0) {
        return value;
    }
    const DAY_MS: i64 = 24 * 60 * 60 * 1000;
    if object.layer == "l3_working_set"
        || matches!(object.source_kind.as_str(), "current_state" | "next_step")
    {
        7 * DAY_MS
    } else if object.layer == "l2_observations"
        || matches!(
            object.source_kind.as_str(),
            "risk" | "open_question" | "recommendation"
        )
    {
        14 * DAY_MS
    } else {
        30 * DAY_MS
    }
}

fn writeback_candidate_requires_stale_review(object: &MemoryObjectRecord) -> bool {
    object.pinned
        || object.scope == "user"
        || object.layer == "l0_constitution"
        || object.layer == "l1_canonical"
        || object.visibility != "local_only"
        || matches!(
            object.source_kind.as_str(),
            "project_goal"
                | "project_requirement"
                | "decision_track"
                | "guidance_injection"
                | "personal_capsule"
        )
}

fn writeback_candidate_has_active_review_lock(object: &MemoryObjectRecord) -> bool {
    memory_json_any_bool(
        &object.policy_json,
        &["active_review_lock", "review_lock", "candidate_review_lock"],
    ) || memory_json_any_bool(
        &object.provenance_json,
        &["active_review_lock", "review_lock", "candidate_review_lock"],
    )
}

fn writeback_candidate_already_marked_stale_review(object: &MemoryObjectRecord) -> bool {
    memory_json_any_bool(
        &object.policy_json,
        &["stale_review_required", "candidate_stale_review_required"],
    ) || memory_json_any_bool(
        &object.provenance_json,
        &["stale_review_required", "candidate_stale_review_required"],
    )
}

fn memory_json_any_bool(raw_json: &str, keys: &[&str]) -> bool {
    let Ok(value) = serde_json::from_str::<Value>(raw_json) else {
        return false;
    };
    keys.iter()
        .any(|key| value.get(*key).and_then(Value::as_bool).unwrap_or(false))
}

fn memory_json_string_array_any(raw_json: &str, keys: &[&str]) -> Vec<String> {
    let Ok(value) = serde_json::from_str::<Value>(raw_json) else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for key in keys {
        match value.get(*key) {
            Some(Value::Array(items)) => {
                out.extend(
                    items
                        .iter()
                        .filter_map(Value::as_str)
                        .map(|item| item.trim().to_string())
                        .filter(|item| !item.is_empty()),
                );
            }
            Some(Value::String(item)) if !item.trim().is_empty() => {
                out.push(item.trim().to_string());
            }
            _ => {}
        }
    }
    unique_strings(out)
}

fn memory_json_any_string(raw_json: &str, keys: &[&str]) -> Option<String> {
    let Ok(value) = serde_json::from_str::<Value>(raw_json) else {
        return None;
    };
    keys.iter().find_map(|key| {
        value
            .get(*key)
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|item| !item.is_empty())
            .map(str::to_string)
    })
}

fn unique_strings(values: Vec<String>) -> Vec<String> {
    let mut seen = BTreeSet::new();
    let mut out = Vec::new();
    for value in values {
        let value = value.trim().to_string();
        if value.is_empty() || !seen.insert(value.clone()) {
            continue;
        }
        out.push(value);
    }
    out
}

fn writeback_candidate_conflict_ids(object: &MemoryObjectRecord) -> Vec<String> {
    unique_strings(
        memory_json_string_array_any(&object.policy_json, &["conflict_with"])
            .into_iter()
            .chain(memory_json_string_array_any(
                &object.provenance_json,
                &["conflict_with"],
            ))
            .collect(),
    )
}

fn writeback_candidate_supersedes_ids(object: &MemoryObjectRecord) -> Vec<String> {
    unique_strings(
        memory_json_string_array_any(&object.policy_json, &["supersedes"])
            .into_iter()
            .chain(memory_json_string_array_any(
                &object.provenance_json,
                &["supersedes"],
            ))
            .collect(),
    )
}

fn writeback_candidate_superseded_by(object: &MemoryObjectRecord) -> Option<String> {
    memory_json_any_string(&object.policy_json, &["superseded_by"])
        .or_else(|| memory_json_any_string(&object.provenance_json, &["superseded_by"]))
}

fn memory_policy_json_with_candidate_conflict_metadata(
    raw_policy_json: &str,
    conflict_with: &[String],
    duplicate_with: &[String],
    supersedes: &[String],
    candidate_generation: i64,
    actor: &str,
    audit_ref: &str,
    scanned_at_ms: i64,
) -> String {
    memory_json_with_candidate_conflict_metadata(
        raw_policy_json,
        conflict_with,
        duplicate_with,
        supersedes,
        candidate_generation,
        actor,
        audit_ref,
        scanned_at_ms,
    )
}

fn memory_provenance_json_with_candidate_conflict_metadata(
    raw_provenance_json: &str,
    conflict_with: &[String],
    duplicate_with: &[String],
    supersedes: &[String],
    candidate_generation: i64,
    actor: &str,
    audit_ref: &str,
    scanned_at_ms: i64,
) -> String {
    memory_json_with_candidate_conflict_metadata(
        raw_provenance_json,
        conflict_with,
        duplicate_with,
        supersedes,
        candidate_generation,
        actor,
        audit_ref,
        scanned_at_ms,
    )
}

fn memory_json_with_candidate_conflict_metadata(
    raw_json: &str,
    conflict_with: &[String],
    duplicate_with: &[String],
    supersedes: &[String],
    candidate_generation: i64,
    actor: &str,
    audit_ref: &str,
    scanned_at_ms: i64,
) -> String {
    let mut value = serde_json::from_str::<Value>(raw_json).unwrap_or_else(|_| json!({}));
    if !value.is_object() {
        value = json!({});
    }
    let conflict_with = unique_strings(conflict_with.to_vec());
    let duplicate_with = unique_strings(duplicate_with.to_vec());
    let supersedes = unique_strings(supersedes.to_vec());
    if let Some(map) = value.as_object_mut() {
        map.insert(
            "candidate_generation".to_string(),
            json!(candidate_generation),
        );
        if !conflict_with.is_empty() {
            map.insert("conflict_with".to_string(), json!(conflict_with));
            map.insert(
                "conflict_reason".to_string(),
                json!("same_scope_source_kind_layer_active_object"),
            );
            map.insert("conflict_resolution_required".to_string(), json!(true));
        }
        if !duplicate_with.is_empty() {
            map.insert("duplicate_with".to_string(), json!(duplicate_with));
        }
        if !supersedes.is_empty() {
            map.insert("supersedes".to_string(), json!(supersedes));
        }
        map.insert(
            "last_writeback_candidate_conflict_scan".to_string(),
            json!({
                "schema_version": MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
                "conflict_with": conflict_with,
                "duplicate_with": duplicate_with,
                "supersedes": supersedes,
                "candidate_generation": candidate_generation,
                "actor": actor,
                "audit_ref": audit_ref,
                "scanned_at_ms": scanned_at_ms,
                "production_authority_change": false,
            }),
        );
    }
    value.to_string()
}

fn memory_policy_json_with_candidate_superseded_by(
    raw_policy_json: &str,
    superseded_by: &str,
    actor: &str,
    audit_ref: &str,
    superseded_at_ms: i64,
) -> String {
    memory_json_with_candidate_superseded_by(
        raw_policy_json,
        superseded_by,
        actor,
        audit_ref,
        superseded_at_ms,
    )
}

fn memory_provenance_json_with_candidate_superseded_by(
    raw_provenance_json: &str,
    superseded_by: &str,
    actor: &str,
    audit_ref: &str,
    superseded_at_ms: i64,
) -> String {
    memory_json_with_candidate_superseded_by(
        raw_provenance_json,
        superseded_by,
        actor,
        audit_ref,
        superseded_at_ms,
    )
}

fn memory_json_with_candidate_superseded_by(
    raw_json: &str,
    superseded_by: &str,
    actor: &str,
    audit_ref: &str,
    superseded_at_ms: i64,
) -> String {
    let mut value = serde_json::from_str::<Value>(raw_json).unwrap_or_else(|_| json!({}));
    if !value.is_object() {
        value = json!({});
    }
    if let Some(map) = value.as_object_mut() {
        map.insert("superseded_by".to_string(), json!(superseded_by));
        map.insert(
            "supersession_reason".to_string(),
            json!("newer_candidate_same_scope_source_kind_layer"),
        );
        map.insert(
            "last_writeback_candidate_supersession".to_string(),
            json!({
                "schema_version": MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
                "operation": "candidate_superseded",
                "superseded_by": superseded_by,
                "actor": actor,
                "audit_ref": audit_ref,
                "superseded_at_ms": superseded_at_ms,
                "production_authority_change": false,
            }),
        );
    }
    value.to_string()
}

fn memory_policy_json_with_candidate_conflict_resolution(
    raw_policy_json: &str,
    conflict_with: &[String],
    resolution_reason: &str,
    actor: &str,
    audit_ref: &str,
    resolved_at_ms: i64,
) -> String {
    memory_json_with_candidate_conflict_resolution(
        raw_policy_json,
        conflict_with,
        resolution_reason,
        actor,
        audit_ref,
        resolved_at_ms,
    )
}

fn memory_provenance_json_with_candidate_conflict_resolution(
    raw_provenance_json: &str,
    conflict_with: &[String],
    resolution_reason: &str,
    actor: &str,
    audit_ref: &str,
    resolved_at_ms: i64,
) -> String {
    memory_json_with_candidate_conflict_resolution(
        raw_provenance_json,
        conflict_with,
        resolution_reason,
        actor,
        audit_ref,
        resolved_at_ms,
    )
}

fn memory_json_with_candidate_conflict_resolution(
    raw_json: &str,
    conflict_with: &[String],
    resolution_reason: &str,
    actor: &str,
    audit_ref: &str,
    resolved_at_ms: i64,
) -> String {
    let mut value = serde_json::from_str::<Value>(raw_json).unwrap_or_else(|_| json!({}));
    if !value.is_object() {
        value = json!({});
    }
    let conflict_with = unique_strings(conflict_with.to_vec());
    if let Some(map) = value.as_object_mut() {
        map.insert("conflict_resolution_required".to_string(), json!(false));
        map.insert("conflict_resolved".to_string(), json!(true));
        map.insert(
            "conflict_resolution_reason".to_string(),
            json!(resolution_reason),
        );
        map.insert(
            "last_writeback_candidate_conflict_resolution".to_string(),
            json!({
                "schema_version": MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
                "conflict_with": conflict_with,
                "resolution_reason": resolution_reason,
                "actor": actor,
                "audit_ref": audit_ref,
                "resolved_at_ms": resolved_at_ms,
                "production_authority_change": false,
            }),
        );
    }
    value.to_string()
}

fn memory_policy_json_with_candidate_maintenance(
    raw_policy_json: &str,
    operation: &str,
    reason_code: &str,
    actor: &str,
    audit_ref: &str,
    maintained_at_ms: i64,
) -> String {
    let mut value = serde_json::from_str::<Value>(raw_policy_json).unwrap_or_else(|_| json!({}));
    if !value.is_object() {
        value = json!({});
    }
    if let Some(map) = value.as_object_mut() {
        if operation == "stale_review_required" {
            map.insert("stale_review_required".to_string(), json!(true));
            map.insert("candidate_stale_review_required".to_string(), json!(true));
        }
        map.insert(
            "last_writeback_candidate_maintenance".to_string(),
            json!({
                "schema_version": MEMORY_WRITEBACK_CANDIDATE_MAINTENANCE_SCHEMA,
                "operation": operation,
                "reason_code": reason_code,
                "actor": actor,
                "audit_ref": audit_ref,
                "maintained_at_ms": maintained_at_ms,
                "production_authority_change": false,
            }),
        );
    }
    value.to_string()
}

fn memory_provenance_json_with_candidate_maintenance(
    raw_provenance_json: &str,
    operation: &str,
    reason_code: &str,
    actor: &str,
    audit_ref: &str,
    maintained_at_ms: i64,
) -> String {
    let mut value =
        serde_json::from_str::<Value>(raw_provenance_json).unwrap_or_else(|_| json!({}));
    if !value.is_object() {
        value = json!({});
    }
    if let Some(map) = value.as_object_mut() {
        if operation == "stale_review_required" {
            map.insert("stale_review_required".to_string(), json!(true));
            map.insert("candidate_stale_review_required".to_string(), json!(true));
        }
        map.insert(
            "last_writeback_candidate_maintenance".to_string(),
            json!({
                "schema_version": MEMORY_WRITEBACK_CANDIDATE_MAINTENANCE_SCHEMA,
                "operation": operation,
                "reason_code": reason_code,
                "actor": actor,
                "audit_ref": audit_ref,
                "maintained_at_ms": maintained_at_ms,
                "production_authority_change": false,
            }),
        );
    }
    value.to_string()
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

fn memory_user_reveal_grant_issue_json(
    config: &HubConfig,
    body: &Value,
) -> Result<String, HttpJsonError> {
    if let Some(deny_code) = memory_user_reveal_grant_deny_code(body) {
        return Err(memory_user_reveal_grant_denied_error(deny_code));
    }
    let now = memory_user_reveal_now_ms(body);
    let ttl_ms = value_i64(body, "ttl_ms")
        .or_else(|| value_i64(body, "ttlMs"))
        .unwrap_or(MEMORY_USER_REVEAL_GRANT_DEFAULT_TTL_MS)
        .clamp(1_000, MEMORY_USER_REVEAL_GRANT_MAX_TTL_MS);
    let expires_at_ms = now.saturating_add(ttl_ms);
    let actor = memory_user_reveal_actor(body);
    let grant_id = format!(
        "user_reveal_{}_{}",
        now,
        MEMORY_USER_REVEAL_GRANT_COUNTER.fetch_add(1, Ordering::Relaxed)
    );
    let response = memory_user_reveal_grant_value(
        true,
        "granted",
        &grant_id,
        &actor,
        now,
        expires_at_ms,
        ttl_ms,
        "",
        value_string(body, "audit_ref")
            .or_else(|| value_string(body, "auditRef"))
            .is_some(),
        now,
        None,
    );
    memory_user_reveal_write_state(config, &response)?;
    Ok(response.to_string())
}

fn memory_user_reveal_grant_revoke_json(
    config: &HubConfig,
    body: &Value,
) -> Result<String, HttpJsonError> {
    let now = memory_user_reveal_now_ms(body);
    let current = memory_user_reveal_read_state(config)?;
    let requested_grant_id =
        value_string(body, "grant_id").or_else(|| value_string(body, "grantId"));
    let current_grant_id = current
        .as_ref()
        .and_then(|value| value_string(value, "grant_id"))
        .unwrap_or_default();
    let grant_id = requested_grant_id
        .filter(|value| !value.is_empty())
        .unwrap_or(current_grant_id);
    let actor = memory_user_reveal_actor(body);
    let issued_at_ms = current
        .as_ref()
        .and_then(|value| value_i64(value, "issued_at_ms"))
        .unwrap_or(now);
    let ttl_ms = current
        .as_ref()
        .and_then(|value| value_i64(value, "ttl_ms"))
        .unwrap_or(0);
    let expires_at_ms = current
        .as_ref()
        .and_then(|value| value_i64(value, "expires_at_ms"))
        .unwrap_or(now);
    let response = memory_user_reveal_grant_value(
        true,
        "revoked",
        &grant_id,
        &actor,
        issued_at_ms,
        expires_at_ms,
        ttl_ms,
        if grant_id.is_empty() {
            "memory_user_reveal_grant_missing"
        } else {
            ""
        },
        value_string(body, "audit_ref")
            .or_else(|| value_string(body, "auditRef"))
            .is_some(),
        now,
        Some(now),
    );
    memory_user_reveal_write_state(config, &response)?;
    Ok(response.to_string())
}

fn memory_user_reveal_grant_evaluate_json(
    config: &HubConfig,
    body: &Value,
) -> Result<String, HttpJsonError> {
    if let Some(deny_code) = memory_user_reveal_grant_deny_code(body) {
        return Err(memory_user_reveal_grant_denied_error(deny_code));
    }
    let now = memory_user_reveal_now_ms(body);
    let requested_grant_id =
        value_string(body, "grant_id").or_else(|| value_string(body, "grantId"));
    let Some(current) = memory_user_reveal_read_state(config)? else {
        return Err(memory_user_reveal_grant_denied_error(
            "memory_user_reveal_grant_missing",
        ));
    };
    let current_grant_id = value_string(&current, "grant_id").unwrap_or_default();
    if let Some(requested_grant_id) = requested_grant_id {
        if requested_grant_id != current_grant_id {
            return Err(memory_user_reveal_grant_denied_error(
                "memory_user_reveal_grant_mismatch",
            ));
        }
    }
    let current_status = value_string(&current, "status").unwrap_or_default();
    if current_status != "granted" {
        return Err(memory_user_reveal_grant_denied_error(
            "memory_user_reveal_grant_not_active",
        ));
    }
    let scope = value_string(&current, "scope").unwrap_or_default();
    let surface = value_string(&current, "surface").unwrap_or_default();
    if scope != "user" || surface != MEMORY_USER_REVEAL_GRANT_SURFACE {
        return Err(memory_user_reveal_grant_denied_error(
            "memory_user_reveal_grant_scope_invalid",
        ));
    }
    let issued_at_ms = value_i64(&current, "issued_at_ms").unwrap_or(0);
    let expires_at_ms = value_i64(&current, "expires_at_ms").unwrap_or(0);
    let ttl_ms = value_i64(&current, "ttl_ms").unwrap_or(0);
    let actor = value_string(&current, "actor").unwrap_or_else(|| "xt_swift_shell".to_string());
    if expires_at_ms <= 0 || now >= expires_at_ms {
        let expired = memory_user_reveal_grant_value(
            false,
            "expired",
            &current_grant_id,
            &actor,
            issued_at_ms,
            expires_at_ms,
            ttl_ms,
            "memory_user_reveal_grant_expired",
            false,
            now,
            None,
        );
        let _ = memory_user_reveal_write_state(config, &expired);
        return Err(http_json_error_json("403 Forbidden", expired));
    }
    let response = memory_user_reveal_grant_value(
        true,
        "granted",
        &current_grant_id,
        &actor,
        issued_at_ms,
        expires_at_ms,
        ttl_ms,
        "",
        false,
        now,
        None,
    );
    Ok(response.to_string())
}

fn memory_user_reveal_grant_deny_code(body: &Value) -> Option<&'static str> {
    let scope = value_string(body, "scope").unwrap_or_else(|| "user".to_string());
    if scope.trim().to_ascii_lowercase() != "user" {
        return Some("memory_user_reveal_scope_denied");
    }
    let surface = value_string(body, "surface")
        .unwrap_or_else(|| MEMORY_USER_REVEAL_GRANT_SURFACE.to_string());
    if surface.trim().to_ascii_lowercase() != MEMORY_USER_REVEAL_GRANT_SURFACE {
        return Some("memory_user_reveal_surface_denied");
    }
    let requester_role = value_string(body, "requester_role")
        .or_else(|| value_string(body, "requesterRole"))
        .unwrap_or_else(|| "supervisor".to_string())
        .trim()
        .to_ascii_lowercase()
        .replace('-', "_");
    if matches!(
        requester_role.as_str(),
        "coder" | "project_coder" | "project_ai"
    ) {
        return Some("memory_user_reveal_project_coder_denied");
    }
    let use_mode = value_string(body, "use_mode")
        .or_else(|| value_string(body, "useMode"))
        .unwrap_or_else(|| "assistant_user_memory_inspector".to_string())
        .trim()
        .to_ascii_lowercase()
        .replace('-', "_");
    if matches!(
        use_mode.as_str(),
        "project_chat" | "project_coder" | "tool_plan" | "model_call" | "execution"
    ) {
        return Some("memory_user_reveal_project_use_mode_denied");
    }
    None
}

fn memory_user_reveal_actor(body: &Value) -> String {
    value_string(body, "actor")
        .and_then(|value| sanitize_public_token(&value))
        .unwrap_or_else(|| "xt_swift_shell".to_string())
}

fn memory_user_reveal_now_ms(body: &Value) -> i64 {
    value_i64(body, "now_ms")
        .or_else(|| value_i64(body, "nowMs"))
        .unwrap_or_else(now_ms_i64)
}

fn memory_user_reveal_state_path(config: &HubConfig) -> PathBuf {
    config
        .root_dir
        .join("data")
        .join("memory_user_reveal_grant_state.json")
}

fn memory_user_reveal_read_state(config: &HubConfig) -> Result<Option<Value>, HttpJsonError> {
    let path = memory_user_reveal_state_path(config);
    match std::fs::read_to_string(&path) {
        Ok(raw) => {
            let value = serde_json::from_str::<Value>(&raw).map_err(|err| {
                memory_user_reveal_grant_error(
                    "500 Internal Server Error",
                    "memory_user_reveal_grant_state_invalid",
                    err.to_string(),
                )
            })?;
            Ok(Some(value))
        }
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(err) => Err(memory_user_reveal_grant_error(
            "500 Internal Server Error",
            "memory_user_reveal_grant_state_read_failed",
            err.to_string(),
        )),
    }
}

fn memory_user_reveal_write_state(config: &HubConfig, value: &Value) -> Result<(), HttpJsonError> {
    let path = memory_user_reveal_state_path(config);
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|err| {
            memory_user_reveal_grant_error(
                "500 Internal Server Error",
                "memory_user_reveal_grant_state_parent_failed",
                err.to_string(),
            )
        })?;
    }
    let tmp_path = path.with_extension("json.tmp");
    std::fs::write(&tmp_path, format!("{}\n", value)).map_err(|err| {
        memory_user_reveal_grant_error(
            "500 Internal Server Error",
            "memory_user_reveal_grant_state_write_failed",
            err.to_string(),
        )
    })?;
    std::fs::rename(&tmp_path, &path).map_err(|err| {
        memory_user_reveal_grant_error(
            "500 Internal Server Error",
            "memory_user_reveal_grant_state_commit_failed",
            err.to_string(),
        )
    })?;
    Ok(())
}

fn memory_user_reveal_grant_value(
    ok: bool,
    status: &str,
    grant_id: &str,
    actor: &str,
    issued_at_ms: i64,
    expires_at_ms: i64,
    ttl_ms: i64,
    reason_code: &str,
    audit_ref_present: bool,
    generated_at_ms: i64,
    revoked_at_ms: Option<i64>,
) -> Value {
    json!({
        "schema_version": MEMORY_USER_REVEAL_GRANT_SCHEMA,
        "ok": ok,
        "source": "rust_memory_user_reveal_grant",
        "status": status,
        "grant_id": grant_id,
        "scope": "user",
        "surface": MEMORY_USER_REVEAL_GRANT_SURFACE,
        "actor": actor,
        "issued_at_ms": issued_at_ms,
        "expires_at_ms": expires_at_ms,
        "ttl_ms": ttl_ms,
        "reason_code": reason_code,
        "audit_ref_present": audit_ref_present,
        "revoked_at_ms": revoked_at_ms,
        "generated_at_ms": generated_at_ms,
        "content_included": false,
        "memory_ids_included": false,
        "project_coder_allowed": false,
        "model_context_authority": false,
        "memory_serving_authority_change": false,
        "production_authority_change": false,
    })
}

fn memory_user_reveal_grant_error(
    status: &'static str,
    error_code: &str,
    message: String,
) -> HttpJsonError {
    http_json_error_json(
        status,
        memory_user_reveal_grant_error_value("error", error_code, &message),
    )
}

fn memory_user_reveal_grant_denied_error(deny_code: &str) -> HttpJsonError {
    http_json_error_json(
        "403 Forbidden",
        memory_user_reveal_grant_error_value("denied", deny_code, deny_code),
    )
}

fn memory_user_reveal_grant_error_value(status: &str, reason_code: &str, message: &str) -> Value {
    json!({
        "schema_version": MEMORY_USER_REVEAL_GRANT_SCHEMA,
        "ok": false,
        "source": "rust_memory_user_reveal_grant",
        "status": status,
        "grant_id": "",
        "scope": "user",
        "surface": MEMORY_USER_REVEAL_GRANT_SURFACE,
        "reason_code": reason_code,
        "deny_code": if status == "denied" { reason_code } else { "" },
        "error_code": reason_code,
        "message": message,
        "content_included": false,
        "memory_ids_included": false,
        "project_coder_allowed": false,
        "model_context_authority": false,
        "memory_serving_authority_change": false,
        "production_authority_change": false,
    })
}

fn memory_user_reveal_grant_active_for_mutation(
    config: &HubConfig,
    requested_grant_id: Option<String>,
    now_ms: i64,
) -> Result<(), &'static str> {
    let requested_grant_id = requested_grant_id
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .ok_or("memory_user_reveal_grant_required")?;
    let current = match memory_user_reveal_read_state(config) {
        Ok(Some(current)) => current,
        Ok(None) => return Err("memory_user_reveal_grant_missing"),
        Err(_) => return Err("memory_user_reveal_grant_state_unavailable"),
    };
    let current_grant_id = value_string(&current, "grant_id").unwrap_or_default();
    if requested_grant_id != current_grant_id {
        return Err("memory_user_reveal_grant_mismatch");
    }
    let current_status = value_string(&current, "status").unwrap_or_default();
    if current_status != "granted" {
        return Err("memory_user_reveal_grant_not_active");
    }
    let scope = value_string(&current, "scope").unwrap_or_default();
    let surface = value_string(&current, "surface").unwrap_or_default();
    if scope != "user" || surface != MEMORY_USER_REVEAL_GRANT_SURFACE {
        return Err("memory_user_reveal_grant_scope_invalid");
    }
    if value_bool(&current, "content_included", false)
        || value_bool(&current, "memory_ids_included", false)
        || value_bool(&current, "project_coder_allowed", false)
        || value_bool(&current, "model_context_authority", false)
        || value_bool(&current, "memory_serving_authority_change", false)
        || value_bool(&current, "production_authority_change", false)
    {
        return Err("memory_user_reveal_grant_authority_invalid");
    }
    let expires_at_ms = value_i64(&current, "expires_at_ms").unwrap_or(0);
    if expires_at_ms <= 0 || now_ms >= expires_at_ms {
        let issued_at_ms = value_i64(&current, "issued_at_ms").unwrap_or(0);
        let ttl_ms = value_i64(&current, "ttl_ms").unwrap_or(0);
        let actor = value_string(&current, "actor").unwrap_or_else(|| "xt_swift_shell".to_string());
        let expired = memory_user_reveal_grant_value(
            false,
            "expired",
            &current_grant_id,
            &actor,
            issued_at_ms,
            expires_at_ms,
            ttl_ms,
            "memory_user_reveal_grant_expired",
            false,
            now_ms,
            None,
        );
        let _ = memory_user_reveal_write_state(config, &expired);
        return Err("memory_user_reveal_grant_expired");
    }
    Ok(())
}

fn list_writeback_candidates_json(
    config: &HubConfig,
    query: &str,
) -> Result<String, HttpJsonError> {
    let filter = MemoryObjectListFilter {
        scope: query_param(query, "scope"),
        owner_id: query_param(query, "owner_id").or_else(|| query_param(query, "ownerId")),
        project_id: query_param(query, "project_id").or_else(|| query_param(query, "projectId")),
        agent_id: query_param(query, "agent_id").or_else(|| query_param(query, "agentId")),
        source_kind: query_param(query, "source_kind").or_else(|| query_param(query, "sourceKind")),
        layer: query_param(query, "layer"),
        status: Some("candidate".to_string()),
        sensitivity: query_param(query, "sensitivity"),
        visibility: query_param(query, "visibility"),
        limit: query_usize(query, "limit", 50).unwrap_or(50),
    };
    let objects = list_memory_objects(&config.db_path, &filter).map_err(|err| {
        http_json_error(
            "500 Internal Server Error",
            "memory_writeback_candidate_list_failed",
            err.to_string(),
        )
    })?;
    let items = objects
        .iter()
        .map(memory_object_to_json)
        .collect::<Vec<_>>();
    let candidate_diagnostics = writeback_candidate_diagnostics_value(config, &filter)?;
    Ok(json!({
        "schema_version": MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
        "ok": true,
        "status": "ok",
        "candidate_count": items.len(),
        "objects": items,
        "candidate_diagnostics": candidate_diagnostics,
        "filter": {
            "scope": filter.scope,
            "owner_id": filter.owner_id,
            "project_id": filter.project_id,
            "agent_id": filter.agent_id,
            "source_kind": filter.source_kind,
            "layer": filter.layer,
            "status": "candidate",
            "sensitivity": filter.sensitivity,
            "visibility": filter.visibility,
            "limit": filter.limit,
        },
        "candidate_writeback": {
            "enabled": true,
            "authority": "rust_policy_gated_candidate_queue",
            "production_authority_change": false,
        },
    })
    .to_string())
}

#[derive(Debug, Clone)]
struct MemoryObjectMutationSpec {
    operation: &'static str,
    status_target: Option<&'static str>,
    pinned_target: Option<bool>,
    default_reason: &'static str,
    confirmation_required: bool,
    confirmation_field: &'static str,
    allowed_statuses: &'static [&'static str],
}

fn memory_object_mutation_spec(action: &str) -> Option<MemoryObjectMutationSpec> {
    match action {
        "archive" => Some(MemoryObjectMutationSpec {
            operation: "archive",
            status_target: Some("archived"),
            pinned_target: Some(false),
            default_reason: "memory_object_archive",
            confirmation_required: true,
            confirmation_field: "confirm_archive",
            allowed_statuses: &["active", "candidate", "rejected"],
        }),
        "delete" => Some(MemoryObjectMutationSpec {
            operation: "delete",
            status_target: Some("deleted"),
            pinned_target: Some(false),
            default_reason: "memory_object_delete_tombstone",
            confirmation_required: true,
            confirmation_field: "confirm_delete",
            allowed_statuses: &["active", "candidate", "archived", "rejected"],
        }),
        "pin" => Some(MemoryObjectMutationSpec {
            operation: "pin",
            status_target: None,
            pinned_target: Some(true),
            default_reason: "memory_object_pin",
            confirmation_required: false,
            confirmation_field: "",
            allowed_statuses: &["active", "candidate"],
        }),
        "unpin" => Some(MemoryObjectMutationSpec {
            operation: "unpin",
            status_target: None,
            pinned_target: Some(false),
            default_reason: "memory_object_unpin",
            confirmation_required: false,
            confirmation_field: "",
            allowed_statuses: &["active", "candidate"],
        }),
        _ => None,
    }
}

fn memory_object_mutation_json(
    config: &HubConfig,
    memory_id: &str,
    action: &str,
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
    let Some(spec) = memory_object_mutation_spec(action) else {
        return Err(http_json_error(
            "400 Bad Request",
            "memory_object_mutation_action_invalid",
            format!("unsupported memory object action: {action}"),
        ));
    };
    let memory_id = sanitize_public_token(memory_id).ok_or_else(|| {
        http_json_error(
            "400 Bad Request",
            "memory_id_required",
            "memory_id is required".to_string(),
        )
    })?;
    let existing = read_memory_object(&config.db_path, &memory_id).map_err(|err| {
        http_json_error(
            "500 Internal Server Error",
            "memory_object_read_failed",
            err.to_string(),
        )
    })?;
    let Some(existing) = existing else {
        return Err(http_json_error_json(
            "404 Not Found",
            json!({
                "schema_version": MEMORY_OBJECT_MUTATION_SCHEMA,
                "ok": false,
                "status": "not_found",
                "memory_id": memory_id,
                "error_code": "memory_object_not_found",
                "production_authority_change": false,
            }),
        ));
    };
    if existing.immutable {
        return Err(http_json_error_json(
            "403 Forbidden",
            json!({
                "schema_version": MEMORY_OBJECT_MUTATION_SCHEMA,
                "ok": false,
                "status": "denied",
                "deny_code": "memory_object_immutable",
                "memory_id": memory_id,
                "action": spec.operation,
                "production_authority_change": false,
            }),
        ));
    }
    if !spec
        .allowed_statuses
        .iter()
        .any(|status| status == &existing.status)
    {
        return Err(http_json_error_json(
            "409 Conflict",
            json!({
                "schema_version": MEMORY_OBJECT_MUTATION_SCHEMA,
                "ok": false,
                "status": "conflict",
                "error_code": "memory_object_status_not_mutable",
                "memory_id": memory_id,
                "action": spec.operation,
                "current_status": &existing.status,
                "allowed_statuses": spec.allowed_statuses,
                "production_authority_change": false,
            }),
        ));
    }
    if spec.confirmation_required && !memory_object_mutation_confirmed(&parsed, spec.operation) {
        return Err(http_json_error_json(
            "403 Forbidden",
            json!({
                "schema_version": MEMORY_OBJECT_MUTATION_SCHEMA,
                "ok": false,
                "status": "denied",
                "deny_code": "memory_object_confirmation_required",
                "memory_id": memory_id,
                "action": spec.operation,
                "required_field": spec.confirmation_field,
                "accepted_confirmation": ["confirm=true", format!("{}=true", spec.confirmation_field), format!("confirmation={}", spec.operation)],
                "production_authority_change": false,
            }),
        ));
    }

    let next_status = spec.status_target.unwrap_or(existing.status.as_str());
    let next_pinned = spec.pinned_target.unwrap_or(existing.pinned);
    if existing.status == next_status && existing.pinned == next_pinned {
        return Err(http_json_error_json(
            "409 Conflict",
            json!({
                "schema_version": MEMORY_OBJECT_MUTATION_SCHEMA,
                "ok": false,
                "status": "conflict",
                "error_code": "memory_object_mutation_noop",
                "memory_id": memory_id,
                "action": spec.operation,
                "current_status": &existing.status,
                "current_pinned": existing.pinned,
                "production_authority_change": false,
            }),
        ));
    }

    let now = now_ms_i64();
    if existing.scope == "user" {
        let requested_grant_id = value_string(&parsed, "user_reveal_grant_id")
            .or_else(|| value_string(&parsed, "userRevealGrantId"))
            .or_else(|| value_string(&parsed, "grant_id"))
            .or_else(|| value_string(&parsed, "grantId"));
        if let Err(deny_code) =
            memory_user_reveal_grant_active_for_mutation(config, requested_grant_id, now)
        {
            return Err(memory_object_mutation_user_reveal_denied(
                &memory_id,
                spec.operation,
                deny_code,
            ));
        }
    }

    let requester_role = value_string(&parsed, "requester_role")
        .or_else(|| value_string(&parsed, "requesterRole"))
        .unwrap_or_else(|| "tool".to_string());
    let use_mode = value_string(&parsed, "use_mode")
        .or_else(|| value_string(&parsed, "useMode"))
        .unwrap_or_else(|| "tool_plan".to_string());
    let policy = evaluate_memory_policy(&json!({
        "requester_role": requester_role,
        "use_mode": use_mode,
        "scope": &existing.scope,
        "requested_layers": [&existing.layer],
        "requested_source_kinds": [&existing.source_kind],
        "remote_export_requested": false,
    }));
    if policy.decision != "allow" {
        return Err(http_json_error_json(
            "403 Forbidden",
            json!({
                "schema_version": MEMORY_OBJECT_MUTATION_SCHEMA,
                "ok": false,
                "status": "denied",
                "deny_code": &policy.deny_code,
                "memory_id": memory_id,
                "action": spec.operation,
                "policy": policy.to_json(),
                "production_authority_change": false,
            }),
        ));
    }

    let actor = sanitize_public_token(
        value_string(&parsed, "actor")
            .unwrap_or_else(|| "rust_hub".to_string())
            .as_str(),
    )
    .unwrap_or_else(|| "rust_hub".to_string());
    let audit_ref = value_string(&parsed, "audit_ref")
        .or_else(|| value_string(&parsed, "auditRef"))
        .unwrap_or_else(|| format!("memory_object:{}:{memory_id}", spec.operation));
    if looks_like_secret_public(&audit_ref) {
        return Err(memory_object_mutation_secret_denied(
            &memory_id,
            spec.operation,
        ));
    }
    let raw_reason =
        value_string(&parsed, "reason").unwrap_or_else(|| spec.default_reason.to_string());
    let Some(reason) = sanitize_public_text(&raw_reason, 240) else {
        return Err(memory_object_mutation_secret_denied(
            &memory_id,
            spec.operation,
        ));
    };

    let before_json = memory_object_to_json(&existing).to_string();
    let mut object = existing.clone();
    object.status = next_status.to_string();
    object.pinned = next_pinned;
    object.updated_at_ms = now;
    object.last_accessed_at_ms = now;
    object.version = existing.version.saturating_add(1);
    object.policy_json = memory_policy_json_with_object_mutation(
        &existing.policy_json,
        &policy,
        spec.operation,
        &actor,
        &audit_ref,
        now,
    );
    object.provenance_json = memory_provenance_json_with_object_mutation(
        &existing.provenance_json,
        spec.operation,
        &actor,
        &audit_ref,
        now,
    );
    let after_json = memory_object_to_json(&object).to_string();
    let event = MemoryEventRecord {
        event_id: next_memory_event_id(),
        memory_id: memory_id.clone(),
        operation: spec.operation.to_string(),
        actor: actor.clone(),
        reason,
        before_version: Some(existing.version),
        after_version: Some(object.version),
        before_json: Some(before_json),
        after_json: Some(after_json),
        policy_decision: "allow".to_string(),
        deny_code: String::new(),
        audit_ref,
        created_at_ms: now,
    };
    update_memory_object_with_event(&config.db_path, &object, &event).map_err(|err| {
        http_json_error(
            "500 Internal Server Error",
            "memory_object_mutation_failed",
            err.to_string(),
        )
    })?;
    Ok(json!({
        "schema_version": MEMORY_OBJECT_MUTATION_SCHEMA,
        "ok": true,
        "status": spec.operation,
        "memory_id": memory_id,
        "version": object.version,
        "event_id": event.event_id,
        "deny_code": "",
        "policy": policy.to_json(),
        "mutation": {
            "operation": spec.operation,
            "from_status": &existing.status,
            "to_status": &object.status,
            "from_pinned": existing.pinned,
            "to_pinned": object.pinned,
            "confirmation_required": spec.confirmation_required,
            "confirmed": true,
            "confirmation_satisfied": true,
            "active_memory_mutation": true,
            "delete_mode": if spec.operation == "delete" { "tombstone" } else { "" },
            "authority": "rust_memory_object_store",
            "production_authority_change": false,
        },
        "object": memory_object_to_json(&object),
        "production_authority_change": false,
    })
    .to_string())
}

fn memory_object_mutation_confirmed(body: &Value, action: &str) -> bool {
    if value_bool(body, "confirm", false) {
        return true;
    }
    let confirm_key = format!("confirm_{action}");
    if value_bool(body, &confirm_key, false) {
        return true;
    }
    value_string(body, "confirmation")
        .map(|value| {
            let normalized = value.trim().to_ascii_lowercase();
            normalized == action
                || normalized == format!("memory_object_{action}")
                || normalized == format!("confirm_{action}")
        })
        .unwrap_or(false)
}

fn memory_object_mutation_user_reveal_denied(
    memory_id: &str,
    action: &str,
    deny_code: &str,
) -> HttpJsonError {
    http_json_error_json(
        "403 Forbidden",
        json!({
            "schema_version": MEMORY_OBJECT_MUTATION_SCHEMA,
            "ok": false,
            "status": "denied",
            "deny_code": deny_code,
            "reason_code": deny_code,
            "memory_id": memory_id,
            "action": action,
            "production_authority_change": false,
        }),
    )
}

fn memory_object_mutation_secret_denied(memory_id: &str, action: &str) -> HttpJsonError {
    http_json_error_json(
        "403 Forbidden",
        json!({
            "schema_version": MEMORY_OBJECT_MUTATION_SCHEMA,
            "ok": false,
            "status": "denied",
            "deny_code": "memory_secret_pattern_denied",
            "memory_id": memory_id,
            "action": action,
            "production_authority_change": false,
        }),
    )
}

fn transition_memory_object_candidate_json(
    config: &HubConfig,
    memory_id: &str,
    action: &str,
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
    let memory_id = sanitize_public_token(memory_id).ok_or_else(|| {
        http_json_error(
            "400 Bad Request",
            "memory_id_required",
            "memory_id is required".to_string(),
        )
    })?;
    let (target_status, operation, default_reason) = match action {
        "approve" => ("active", "approve", "memory_writeback_candidate_approve"),
        "reject" => ("rejected", "reject", "memory_writeback_candidate_reject"),
        _ => {
            return Err(http_json_error(
                "400 Bad Request",
                "memory_writeback_candidate_action_invalid",
                format!("unsupported candidate action: {action}"),
            ))
        }
    };
    let existing = read_memory_object(&config.db_path, &memory_id).map_err(|err| {
        http_json_error(
            "500 Internal Server Error",
            "memory_object_read_failed",
            err.to_string(),
        )
    })?;
    let Some(existing) = existing else {
        return Err(http_json_error_json(
            "404 Not Found",
            json!({
                "schema_version": MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
                "ok": false,
                "status": "not_found",
                "memory_id": memory_id,
                "error_code": "memory_object_not_found",
            }),
        ));
    };
    if existing.status != "candidate" {
        return Err(http_json_error_json(
            "409 Conflict",
            json!({
                "schema_version": MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
                "ok": false,
                "status": "conflict",
                "error_code": "memory_writeback_candidate_status_mismatch",
                "memory_id": memory_id,
                "current_status": &existing.status,
                "required_status": "candidate",
                "action": action,
                "production_authority_change": false,
            }),
        ));
    }
    if existing.immutable {
        return Err(http_json_error_json(
            "403 Forbidden",
            json!({
                "schema_version": MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
                "ok": false,
                "status": "denied",
                "deny_code": "memory_object_immutable",
                "memory_id": memory_id,
                "production_authority_change": false,
            }),
        ));
    }
    if operation == "approve"
        && (existing.sensitivity == "secret"
            || looks_like_secret_public(&existing.title)
            || looks_like_secret_public(&existing.summary)
            || looks_like_secret_public(&existing.text))
    {
        return Err(http_json_error_json(
            "403 Forbidden",
            json!({
                "schema_version": MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
                "ok": false,
                "status": "denied",
                "deny_code": "memory_writeback_candidate_secret_denied",
                "memory_id": memory_id,
                "production_authority_change": false,
            }),
        ));
    }

    let requester_role = value_string(&parsed, "requester_role")
        .or_else(|| value_string(&parsed, "requesterRole"))
        .unwrap_or_else(|| "tool".to_string());
    let use_mode = value_string(&parsed, "use_mode")
        .or_else(|| value_string(&parsed, "useMode"))
        .unwrap_or_else(|| "tool_plan".to_string());
    let policy = evaluate_memory_policy(&json!({
        "requester_role": requester_role,
        "use_mode": use_mode,
        "scope": &existing.scope,
        "requested_layers": [&existing.layer],
        "requested_source_kinds": [&existing.source_kind],
        "remote_export_requested": false,
    }));
    if policy.decision != "allow" {
        return Err(http_json_error_json(
            "403 Forbidden",
            json!({
                "schema_version": MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
                "ok": false,
                "status": "denied",
                "deny_code": &policy.deny_code,
                "memory_id": memory_id,
                "policy": policy.to_json(),
                "production_authority_change": false,
            }),
        ));
    }

    let now = now_ms_i64();
    let actor = sanitize_public_token(
        value_string(&parsed, "actor")
            .unwrap_or_else(|| "rust_hub".to_string())
            .as_str(),
    )
    .unwrap_or_else(|| "rust_hub".to_string());
    let audit_ref = value_string(&parsed, "audit_ref")
        .or_else(|| value_string(&parsed, "auditRef"))
        .unwrap_or_else(|| format!("memory_writeback_candidate:{operation}:{memory_id}"));
    if looks_like_secret_public(&audit_ref) {
        return Err(http_json_error_json(
            "403 Forbidden",
            json!({
                "schema_version": MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
                "ok": false,
                "status": "denied",
                "deny_code": "memory_secret_pattern_denied",
                "memory_id": memory_id,
                "production_authority_change": false,
            }),
        ));
    }
    let reason = sanitize_public_text(
        &value_string(&parsed, "reason").unwrap_or_else(|| default_reason.to_string()),
        240,
    )
    .unwrap_or_else(|| default_reason.to_string());
    let conflict_resolution_reason = value_string(&parsed, "conflict_resolution_reason")
        .or_else(|| value_string(&parsed, "conflictResolutionReason"))
        .map(|raw| {
            sanitize_public_text(&raw, 240).ok_or_else(|| {
                http_json_error_json(
                    "403 Forbidden",
                    json!({
                        "schema_version": MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
                        "ok": false,
                        "status": "denied",
                        "deny_code": "memory_secret_pattern_denied",
                        "memory_id": memory_id,
                        "production_authority_change": false,
                    }),
                )
            })
        })
        .transpose()?;
    let conflict_ids = if operation == "approve" {
        unique_strings(
            writeback_candidate_conflict_ids(&existing)
                .into_iter()
                .chain(
                    writeback_candidate_active_conflicts(config, &existing)?
                        .into_iter()
                        .map(|object| object.memory_id),
                )
                .collect(),
        )
    } else {
        Vec::new()
    };
    if operation == "approve" && !conflict_ids.is_empty() && conflict_resolution_reason.is_none() {
        return Err(http_json_error_json(
            "409 Conflict",
            json!({
                "schema_version": MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
                "ok": false,
                "status": "conflict",
                "error_code": "memory_writeback_candidate_conflict_resolution_required",
                "memory_id": memory_id,
                "conflict_with": conflict_ids,
                "required_field": "conflict_resolution_reason",
                "production_authority_change": false,
            }),
        ));
    }
    let before_json = memory_object_to_json(&existing).to_string();
    let mut object = existing.clone();
    object.status = target_status.to_string();
    object.updated_at_ms = now;
    object.last_accessed_at_ms = now;
    object.version = existing.version.saturating_add(1);
    object.policy_json = memory_policy_json_with_candidate_transition(
        &existing.policy_json,
        &policy,
        operation,
        &actor,
        &audit_ref,
        now,
    );
    if let Some(resolution_reason) = conflict_resolution_reason.as_ref() {
        object.policy_json = memory_policy_json_with_candidate_conflict_resolution(
            &object.policy_json,
            &conflict_ids,
            resolution_reason,
            &actor,
            &audit_ref,
            now,
        );
        object.provenance_json = memory_provenance_json_with_candidate_conflict_resolution(
            &object.provenance_json,
            &conflict_ids,
            resolution_reason,
            &actor,
            &audit_ref,
            now,
        );
    }
    let after_json = memory_object_to_json(&object).to_string();
    let conflict_resolution_json = conflict_resolution_reason
        .as_ref()
        .map(|resolution_reason| {
            json!({
                "required": !conflict_ids.is_empty(),
                "resolved": true,
                "conflict_with": conflict_ids,
                "resolution_reason": resolution_reason,
            })
        })
        .unwrap_or(Value::Null);
    let event = MemoryEventRecord {
        event_id: next_memory_event_id(),
        memory_id: memory_id.clone(),
        operation: operation.to_string(),
        actor: actor.clone(),
        reason,
        before_version: Some(existing.version),
        after_version: Some(object.version),
        before_json: Some(before_json),
        after_json: Some(after_json),
        policy_decision: "allow".to_string(),
        deny_code: String::new(),
        audit_ref,
        created_at_ms: now,
    };
    update_memory_object_with_event(&config.db_path, &object, &event).map_err(|err| {
        http_json_error(
            "500 Internal Server Error",
            "memory_writeback_candidate_transition_failed",
            err.to_string(),
        )
    })?;
    Ok(json!({
        "schema_version": MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
        "ok": true,
        "status": if operation == "approve" { "approved" } else { "rejected" },
        "memory_id": memory_id,
        "version": object.version,
        "event_id": event.event_id,
        "deny_code": "",
        "policy": policy.to_json(),
        "transition": {
            "operation": operation,
            "from_status": "candidate",
            "to_status": target_status,
            "candidate_writeback": true,
            "conflict_resolution": conflict_resolution_json,
        },
        "object": memory_object_to_json(&object),
        "production_authority_change": false,
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

#[derive(Debug, Clone)]
struct GatewayMemoryChunk {
    memory_id: String,
    chunk_id: String,
    chunk_start_line: usize,
    chunk_end_line: usize,
    scope: String,
    owner_id: String,
    project_id: Option<String>,
    agent_id: Option<String>,
    source_kind: String,
    layer: String,
    title: String,
    text: String,
    summary: String,
    sensitivity: String,
    visibility: String,
    updated_at_ms: i64,
    version: i64,
}

fn gateway_memory_chunk_from_index(row: MemoryObjectIndexRecord) -> GatewayMemoryChunk {
    GatewayMemoryChunk {
        memory_id: row.memory_id,
        chunk_id: row.chunk_id,
        chunk_start_line: row.chunk_start_line.max(1) as usize,
        chunk_end_line: row.chunk_end_line.max(1) as usize,
        scope: row.scope,
        owner_id: row.owner_id,
        project_id: row.project_id,
        agent_id: row.agent_id,
        source_kind: row.source_kind,
        layer: row.layer,
        title: row.title,
        text: row.text,
        summary: row.summary,
        sensitivity: row.sensitivity,
        visibility: row.visibility,
        updated_at_ms: row.object_updated_at_ms,
        version: row.object_version,
    }
}

fn gateway_memory_chunk_from_object(object: MemoryObjectRecord) -> GatewayMemoryChunk {
    let searchable_text = format!(
        "{}\n{}\n{}\n{}",
        object.title, object.summary, object.text, object.tags_json
    );
    let content_hash = stable_fnv1a64_hex(&searchable_text);
    let chunk_end_line = object.text.lines().count().max(1);
    GatewayMemoryChunk {
        memory_id: object.memory_id,
        chunk_id: format!("object-1-{chunk_end_line}-{content_hash}"),
        chunk_start_line: 1,
        chunk_end_line,
        scope: object.scope,
        owner_id: object.owner_id,
        project_id: object.project_id,
        agent_id: object.agent_id,
        source_kind: object.source_kind,
        layer: object.layer,
        title: object.title,
        text: object.text,
        summary: object.summary,
        sensitivity: object.sensitivity,
        visibility: object.visibility,
        updated_at_ms: object.updated_at_ms,
        version: object.version,
    }
}

fn gateway_memory_chunk_ref(chunk: &GatewayMemoryChunk) -> String {
    format!(
        "memory://rust/object/{}#{}",
        chunk.memory_id, chunk.chunk_id
    )
}

fn gateway_memory_object_ref(chunk: &GatewayMemoryChunk) -> String {
    format!("memory://rust/object/{}", chunk.memory_id)
}

fn gateway_memory_chunk_ref_summary(chunk: &GatewayMemoryChunk, reason_code: &str) -> Value {
    json!({
        "ref": gateway_memory_object_ref(chunk),
        "chunk_ref": gateway_memory_chunk_ref(chunk),
        "chunk_id": &chunk.chunk_id,
        "chunk_identity_schema": "xhub.memory.object_chunk_identity.v1",
        "chunk_start_line": chunk.chunk_start_line,
        "chunk_end_line": chunk.chunk_end_line,
        "memory_id": &chunk.memory_id,
        "layer": &chunk.layer,
        "source_kind": &chunk.source_kind,
        "scope": &chunk.scope,
        "project_id": chunk.project_id.as_deref(),
        "sensitivity": &chunk.sensitivity,
        "visibility": &chunk.visibility,
        "updated_at_ms": chunk.updated_at_ms,
        "version": chunk.version,
        "reason_code": reason_code,
        "content_included": false,
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
    let requested_profile_raw =
        value_string(body, "serving_profile_id").or_else(|| value_string(body, "servingProfileId"));
    let requested_profile_was_explicit = requested_profile_raw.is_some();
    let derived_profile = gateway_default_serving_profile(&use_mode, remote_export_requested);
    let selected_profile = match requested_profile_raw {
        Some(raw) => normalize_serving_profile_id(&raw).ok_or_else(|| {
            gateway_json_error(
                "400 Bad Request",
                "memory_gateway_serving_profile_invalid",
                format!("unsupported serving_profile_id: {raw}"),
            )
        })?,
        None => derived_profile.clone(),
    };
    let mut effective_profile = selected_profile.clone();
    let mut profile_reason = if requested_profile_was_explicit {
        "requested_by_client".to_string()
    } else {
        format!("derived_from_use_mode_{use_mode}")
    };
    if remote_export_requested && gateway_serving_profile_rank(&effective_profile) > 1 {
        effective_profile = "M1_Execute".to_string();
        profile_reason = "remote_export_profile_downgraded".to_string();
    }
    let profile_defaults = gateway_profile_defaults(&effective_profile);
    let requested_layers_explicit = value_string_list(body, "requested_layers")
        .or_else(|| value_string_list(body, "requestedLayers"));
    let requested_source_kinds_explicit = value_string_list(body, "requested_source_kinds")
        .or_else(|| value_string_list(body, "requestedSourceKinds"));
    let requested_layers = requested_layers_explicit
        .clone()
        .unwrap_or_else(|| profile_defaults.layers.clone());
    let requested_source_kinds = requested_source_kinds_explicit
        .clone()
        .unwrap_or_else(|| profile_defaults.source_kinds.clone());
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
                "serving_profile_id": &selected_profile,
                "selected_profile": &selected_profile,
                "effective_profile": &effective_profile,
                "profile_reason": &profile_reason,
                "production_authority_change": false,
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
        .unwrap_or(profile_defaults.max_items)
        .clamp(1, 64);
    let max_snippet_chars = value_usize(body, "max_snippet_chars")
        .or_else(|| value_usize(body, "maxSnippetChars"))
        .unwrap_or(profile_defaults.max_snippet_chars)
        .clamp(80, 2_000);
    let read_limit = value_usize(body, "read_limit")
        .or_else(|| value_usize(body, "readLimit"))
        .unwrap_or_else(|| max_items.saturating_mul(profile_defaults.read_multiplier))
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
        scope: Some(policy.scope.clone()),
        owner_id: None,
        project_id: if project_id.is_empty() {
            None
        } else {
            Some(project_id.clone())
        },
        agent_id: agent_id.clone(),
        source_kind: None,
        layer: None,
        sensitivity: None,
        visibility: None,
        limit: read_limit,
    };
    let mut index_source = "rust_hub_memory_object_index";
    let mut chunks = if index_summary.index_ready
        && index_summary.index_row_count > 0
        && index_summary.stale_index_count == 0
    {
        list_memory_object_index(&config.db_path, &index_filter)
            .map_err(|err| {
                gateway_json_error(
                    "500 Internal Server Error",
                    "memory_gateway_object_index_list_failed",
                    err.to_string(),
                )
            })?
            .into_iter()
            .map(gateway_memory_chunk_from_index)
            .collect::<Vec<_>>()
    } else {
        Vec::new()
    };

    if chunks.is_empty() {
        index_source = "rust_hub_memory_objects";
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
        chunks = objects
            .into_iter()
            .map(gateway_memory_chunk_from_object)
            .collect();
    }

    let mut selected = Vec::new();
    let mut skipped_for_policy = 0usize;
    let mut skipped_for_remote_visibility = 0usize;
    let mut skipped_secret = 0usize;
    let mut skipped_for_budget = 0usize;
    let mut omitted_reason_counts = BTreeMap::<String, usize>::new();
    let mut omitted_refs = Vec::<Value>::new();
    for chunk in chunks {
        if chunk.sensitivity == "secret" {
            skipped_secret += 1;
            increment_omitted_reason_count(&mut omitted_reason_counts, "secret_or_secret_like");
            if omitted_refs.len() < MEMORY_RETRIEVAL_TRACE_LIMIT {
                omitted_refs.push(gateway_memory_chunk_ref_summary(
                    &chunk,
                    "secret_or_secret_like",
                ));
            }
            continue;
        }
        if !allowed_layers.iter().any(|layer| layer == &chunk.layer) {
            skipped_for_policy += 1;
            increment_omitted_reason_count(&mut omitted_reason_counts, "layer_filter");
            if omitted_refs.len() < MEMORY_RETRIEVAL_TRACE_LIMIT {
                omitted_refs.push(gateway_memory_chunk_ref_summary(&chunk, "layer_filter"));
            }
            continue;
        }
        if !requested_source_filter.is_empty()
            && !requested_source_filter
                .iter()
                .any(|source_kind| source_kind == &chunk.source_kind)
        {
            skipped_for_policy += 1;
            increment_omitted_reason_count(&mut omitted_reason_counts, "source_kind_filter");
            if omitted_refs.len() < MEMORY_RETRIEVAL_TRACE_LIMIT {
                omitted_refs.push(gateway_memory_chunk_ref_summary(
                    &chunk,
                    "source_kind_filter",
                ));
            }
            continue;
        }
        if remote_export_requested && chunk.visibility != "sanitized_remote_ok" {
            skipped_for_remote_visibility += 1;
            increment_omitted_reason_count(&mut omitted_reason_counts, "remote_visibility_filter");
            if omitted_refs.len() < MEMORY_RETRIEVAL_TRACE_LIMIT {
                omitted_refs.push(gateway_memory_chunk_ref_summary(
                    &chunk,
                    "remote_visibility_filter",
                ));
            }
            continue;
        }
        if selected.len() >= max_items {
            skipped_for_budget += 1;
            increment_omitted_reason_count(&mut omitted_reason_counts, "budget_limit");
            if omitted_refs.len() < MEMORY_RETRIEVAL_TRACE_LIMIT {
                omitted_refs.push(gateway_memory_chunk_ref_summary(&chunk, "budget_limit"));
            }
            continue;
        }
        selected.push(chunk);
    }

    let mut slots: BTreeMap<String, Vec<Value>> = BTreeMap::new();
    for chunk in &selected {
        slots
            .entry(chunk.layer.clone())
            .or_default()
            .push(gateway_memory_chunk_to_json(chunk, max_snippet_chars));
    }
    let selected_refs = selected
        .iter()
        .map(|chunk| gateway_memory_chunk_ref_summary(chunk, "selected"))
        .collect::<Vec<_>>();
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
    let denied_count = skipped_for_policy + skipped_for_remote_visibility + skipped_secret;
    let profile_downgraded = selected_profile != effective_profile;
    let expanded = !profile_downgraded
        && gateway_serving_profile_rank(&effective_profile)
            > gateway_serving_profile_rank(&derived_profile);
    let expansion_reason = if expanded {
        "requested_profile_expansion"
    } else if profile_downgraded && remote_export_requested {
        "remote_export_no_auto_deep_expand"
    } else {
        ""
    };
    let raw_evidence_allowed = allowed_layers
        .iter()
        .any(|layer| layer == "l4_raw_evidence");

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
        "serving_profile_id": &selected_profile,
        "selected_profile": &selected_profile,
        "effective_profile": &effective_profile,
        "profile_reason": profile_reason,
        "expanded": expanded,
        "expansion_reason": expansion_reason,
        "project_id": if project_id.is_empty() { Value::Null } else { json!(project_id) },
        "remote_export_requested": remote_export_requested,
        "query_present": !latest_user.is_empty(),
        "policy": policy.to_json(),
        "object_count": selected.len(),
        "selected_count": selected.len(),
        "selected_chunk_count": selected.len(),
        "selected_refs": selected_refs,
        "omitted_count": skipped_for_budget,
        "omitted_ref_count": omitted_refs.len(),
        "omitted_refs": omitted_refs,
        "denied_count": denied_count,
        "max_items": max_items,
        "max_snippet_chars": max_snippet_chars,
        "index_source": index_source,
        "index_granularity": "object_chunk",
        "index_rebuilt": index_rebuilt,
        "index_rebuild_error": index_rebuild_error,
        "chunk_identity_schema": "xhub.memory.object_chunk_identity.v1",
        "chunk_expand_via_get_ref": true,
        "requested_layers": requested_layers,
        "effective_layers": allowed_layers,
        "requested_source_kinds": requested_source_kinds,
        "raw_evidence_allowed": raw_evidence_allowed,
        "remote_export_filtered_count": skipped_for_remote_visibility,
        "fallback_disabled": false,
        "fallback_reason": "",
        "slots": slot_values,
        "context_text": context_text,
        "skipped": {
            "policy_or_filter": skipped_for_policy,
            "remote_visibility": skipped_for_remote_visibility,
            "secret": skipped_secret,
            "budget": skipped_for_budget,
        },
        "omitted_reason_counts": omitted_reason_counts,
    })
    .to_string())
}

fn memory_gateway_model_call_plan_json_from_value(
    config: &HubConfig,
    body: &Value,
) -> Result<String, HttpJsonError> {
    let started_at_ms = now_ms_i64();
    let request_id = value_string(body, "request_id")
        .or_else(|| value_string(body, "requestId"))
        .or_else(|| value_string(body, "req_id"))
        .or_else(|| value_string(body, "reqId"))
        .unwrap_or_default();
    let audit_ref = value_string(body, "audit_ref")
        .or_else(|| value_string(body, "auditRef"))
        .unwrap_or_default();

    if gateway_model_call_execution_requested(body) {
        return Err(gateway_model_call_plan_json_error(
            "403 Forbidden",
            "memory_gateway_model_call_execute_not_enabled",
            "Rust Memory Gateway model-call execution is not enabled in this slice; request plan-only first.".to_string(),
            json!({
                "request_id": request_id,
                "audit_ref": audit_ref,
                "requested_execute": true,
            }),
        ));
    }

    let prompt_summary = gateway_model_call_prompt_summary(body)?;
    let mut prepare_body = body.clone();
    if let Some(prompt) = gateway_model_call_primary_prompt(body) {
        if let Some(map) = prepare_body.as_object_mut() {
            if !map.contains_key("latest_user")
                && !map.contains_key("latestUser")
                && !map.contains_key("query")
            {
                map.insert("latest_user".to_string(), json!(prompt));
            }
        }
    }

    let prepare_raw = memory_gateway_prepare_json_from_value(config, &prepare_body)
        .map_err(gateway_model_call_prepare_error)?;
    let prepare = serde_json::from_str::<Value>(&prepare_raw).map_err(|err| {
        gateway_model_call_plan_json_error(
            "500 Internal Server Error",
            "memory_gateway_model_call_prepare_parse_failed",
            format!("prepare output was not valid JSON: {err}"),
            json!({}),
        )
    })?;
    let finished_at_ms = now_ms_i64();
    let context_char_count = prepare
        .get("context_text")
        .and_then(Value::as_str)
        .map(|value| value.chars().count())
        .unwrap_or(0);
    let selected_refs = gateway_prepare_selected_refs(&prepare);
    let omitted_refs = prepare
        .get("omitted_refs")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let task_kind = first_public_token(body, &["task_kind", "taskKind", "task_type", "taskType"])
        .unwrap_or_else(|| "text_generate".to_string());
    let provider_id =
        first_public_token(body, &["provider_id", "providerId", "provider"]).unwrap_or_default();
    let model_id = first_public_token(
        body,
        &[
            "model_id",
            "modelId",
            "preferred_model_id",
            "preferredModelId",
        ],
    )
    .unwrap_or_default();
    let route_intent = if provider_id.is_empty() && model_id.is_empty() {
        "route_unspecified_plan_only"
    } else {
        "route_required_before_execute"
    };

    Ok(json!({
        "schema_version": MEMORY_GATEWAY_MODEL_CALL_PLAN_SCHEMA,
        "ok": true,
        "status": "planned",
        "command": "model-call-plan",
        "source": "rust_memory_gateway_model_call_plan",
        "mode": "plan_only_no_model_call",
        "authority": "rust_memory_gateway_plan_only",
        "production_authority_change": false,
        "would_call_model": false,
        "model_call_executed": false,
        "execution_blocker": "model_call_execution_not_enabled",
        "request_id": request_id,
        "audit_ref": audit_ref,
        "started_at_ms": started_at_ms,
        "finished_at_ms": finished_at_ms,
        "duration_ms": finished_at_ms.saturating_sub(started_at_ms),
        "prepare": gateway_prepare_plan_summary(&prepare),
        "memory_context": {
            "context_text_included": false,
            "context_char_count": context_char_count,
            "selected_ref_count": selected_refs.len(),
            "selected_refs": selected_refs,
            "omitted_ref_count": omitted_refs.len(),
            "omitted_refs": omitted_refs,
            "chunk_identity_schema": prepare.get("chunk_identity_schema").cloned().unwrap_or(Value::Null),
            "index_granularity": prepare.get("index_granularity").cloned().unwrap_or(Value::Null),
            "chunk_expand_via_get_ref": prepare.get("chunk_expand_via_get_ref").cloned().unwrap_or(Value::Bool(false)),
        },
        "model_request": {
            "task_kind": task_kind,
            "provider_id": provider_id,
            "model_id": model_id,
            "route_intent": route_intent,
            "prompt": prompt_summary,
        },
        "guards": {
            "execute_requested": false,
            "apply_requested": false,
            "commit_requested": false,
            "local_ml_execute_http_not_invoked": true,
            "provider_route_not_mutated": true,
            "node_not_authority": true,
            "context_text_redacted_from_plan": true,
        },
        "next_gate": {
            "required_before_execution_cutover": [
                "explicit_execute_gate",
                "model_route_authority_check",
                "local_ml_or_provider_execution_smoke",
                "doctor_and_ops_evidence",
                "rollback_gate"
            ],
            "safe_to_use_for_shadow_planning": true,
        }
    })
    .to_string())
}

fn memory_gateway_model_call_execution_gate_json_from_value(
    config: &HubConfig,
    body: &Value,
) -> Result<String, HttpJsonError> {
    let started_at_ms = now_ms_i64();
    let request_id = value_string(body, "request_id")
        .or_else(|| value_string(body, "requestId"))
        .or_else(|| value_string(body, "req_id"))
        .or_else(|| value_string(body, "reqId"))
        .unwrap_or_default();
    let audit_ref = value_string(body, "audit_ref")
        .or_else(|| value_string(body, "auditRef"))
        .unwrap_or_default();
    let execution_requested = gateway_model_call_execution_requested(body);
    let admission_enabled = gateway_model_call_execution_admission_enabled_for_body(body);

    if execution_requested
        && admission_enabled
        && gateway_model_call_fast_execution_gate_enabled_for_body(body)
    {
        return memory_gateway_model_call_fast_execution_gate_json_from_value(
            body,
            started_at_ms,
            request_id,
            audit_ref,
            execution_requested,
            admission_enabled,
        );
    }

    let mut plan_body = body.clone();
    strip_gateway_model_call_execution_flags(&mut plan_body);
    let plan_raw = memory_gateway_model_call_plan_json_from_value(config, &plan_body)?;
    let plan = serde_json::from_str::<Value>(&plan_raw).map_err(|err| {
        gateway_model_call_execution_gate_json_error(
            "500 Internal Server Error",
            "memory_gateway_model_call_execution_gate_plan_parse_failed",
            format!("plan output was not valid JSON: {err}"),
            json!({}),
        )
    })?;

    let plan_ok = plan.get("ok").and_then(Value::as_bool).unwrap_or(false);
    let route_intent = plan
        .pointer("/model_request/route_intent")
        .and_then(Value::as_str)
        .unwrap_or("");
    let route_unspecified = route_intent == "route_unspecified_plan_only";
    let provider_route_authority = gateway_model_call_provider_route_authority_ready_for_body(body);
    let model_route_authority = gateway_model_call_model_route_authority_ready_for_body(body);
    let mut blockers = Vec::new();
    if !admission_enabled {
        blockers.push("memory_gateway_model_call_execution_not_enabled".to_string());
    }
    if !execution_requested {
        blockers.push("explicit_execute_not_requested".to_string());
    }
    if route_unspecified {
        blockers.push("model_route_unspecified".to_string());
    }
    if admission_enabled && !provider_route_authority {
        blockers.push("provider_route_authority_not_in_rust".to_string());
    }
    if admission_enabled && !model_route_authority {
        blockers.push("model_route_authority_not_in_rust".to_string());
    }
    if !plan_ok {
        blockers.push("memory_gateway_model_call_plan_not_ok".to_string());
    }
    let ready_for_execution = blockers.is_empty();
    let status = if ready_for_execution {
        "admitted"
    } else {
        "blocked"
    };
    let mode = if admission_enabled {
        "execution_admission_no_model_call"
    } else {
        "gate_only_no_model_call"
    };
    let authority = if admission_enabled {
        "rust_memory_gateway_execution_admission"
    } else {
        "rust_memory_gateway_execution_gate_only"
    };
    let finished_at_ms = now_ms_i64();

    Ok(json!({
        "schema_version": MEMORY_GATEWAY_MODEL_CALL_EXECUTION_GATE_SCHEMA,
        "ok": true,
        "status": status,
        "command": "model-call-execution-gate",
        "source": "rust_memory_gateway_model_call_execution_gate",
        "authority": authority,
        "mode": mode,
        "production_authority_change": false,
        "execution_authority_in_rust": false,
        "execution_admission_authority_in_rust": admission_enabled,
        "execution_admission_enabled": admission_enabled,
        "execution_admission_ready": ready_for_execution,
        "execution_enabled": false,
        "ready_for_execution": ready_for_execution,
        "would_call_model": false,
        "model_call_executed": false,
        "execution_requested": execution_requested,
        "request_id": request_id,
        "audit_ref": audit_ref,
        "started_at_ms": started_at_ms,
        "finished_at_ms": finished_at_ms,
        "duration_ms": finished_at_ms.saturating_sub(started_at_ms),
        "blockers": blockers,
        "plan": {
            "ok": plan_ok,
            "schema_version": plan.get("schema_version").cloned().unwrap_or(Value::Null),
            "source": plan.get("source").cloned().unwrap_or(Value::Null),
            "mode": plan.get("mode").cloned().unwrap_or(Value::Null),
            "authority": plan.get("authority").cloned().unwrap_or(Value::Null),
            "status": plan.get("status").cloned().unwrap_or(Value::Null),
            "context_text_included": plan.pointer("/memory_context/context_text_included").and_then(Value::as_bool).unwrap_or(false),
            "context_char_count": plan.pointer("/memory_context/context_char_count").and_then(Value::as_u64).unwrap_or(0),
            "selected_ref_count": plan.pointer("/memory_context/selected_ref_count").and_then(Value::as_u64).unwrap_or(0),
            "prompt_text_included": plan.pointer("/model_request/prompt/text_included").and_then(Value::as_bool).unwrap_or(false),
            "prompt_char_count": plan.pointer("/model_request/prompt/prompt_char_count").and_then(Value::as_u64).unwrap_or(0),
            "message_count": plan.pointer("/model_request/prompt/message_count").and_then(Value::as_u64).unwrap_or(0),
            "route_intent": route_intent,
        },
        "route_authority": {
            "provider_route_authority_in_rust": provider_route_authority,
            "model_route_authority_in_rust": model_route_authority,
            "route_specified": !route_unspecified,
        },
        "guards": {
            "local_ml_execute_http_not_invoked": true,
            "provider_route_not_mutated": true,
            "node_not_authority": true,
            "context_text_redacted_from_gate": true,
            "prompt_text_redacted_from_gate": true,
        },
        "next_gate": {
            "required_before_execution_cutover": [
                "attach_memory_gateway_model_call_executor",
                "local_ml_or_provider_execution_smoke",
                "doctor_and_ops_evidence",
                "rollback_gate"
            ],
            "admission_contract_ready": ready_for_execution,
            "safe_to_use_for_execution_preflight": true,
            "safe_to_use_for_shadow_planning": true,
        }
    })
    .to_string())
}

fn memory_gateway_model_call_fast_execution_gate_json_from_value(
    body: &Value,
    started_at_ms: i64,
    request_id: String,
    audit_ref: String,
    execution_requested: bool,
    admission_enabled: bool,
) -> Result<String, HttpJsonError> {
    let prompt_summary = gateway_model_call_prompt_summary(body)?;
    let provider_id =
        first_public_token(body, &["provider_id", "providerId", "provider"]).unwrap_or_default();
    let model_id = first_public_token(
        body,
        &[
            "model_id",
            "modelId",
            "preferred_model_id",
            "preferredModelId",
        ],
    )
    .unwrap_or_default();
    let route_unspecified = provider_id.is_empty() && model_id.is_empty();
    let route_intent = if route_unspecified {
        "route_unspecified_fast_admission"
    } else {
        "route_required_before_execute"
    };
    let provider_route_authority = gateway_model_call_provider_route_authority_ready_for_body(body);
    let model_route_authority = gateway_model_call_model_route_authority_ready_for_body(body);
    let mut blockers = Vec::new();
    if !execution_requested {
        blockers.push("explicit_execute_not_requested".to_string());
    }
    if route_unspecified {
        blockers.push("model_route_unspecified".to_string());
    }
    if admission_enabled && !provider_route_authority {
        blockers.push("provider_route_authority_not_in_rust".to_string());
    }
    if admission_enabled && !model_route_authority {
        blockers.push("model_route_authority_not_in_rust".to_string());
    }
    let ready_for_execution = blockers.is_empty();
    let status = if ready_for_execution {
        "admitted"
    } else {
        "blocked"
    };
    let finished_at_ms = now_ms_i64();

    Ok(json!({
        "schema_version": MEMORY_GATEWAY_MODEL_CALL_EXECUTION_GATE_SCHEMA,
        "ok": true,
        "status": status,
        "command": "model-call-execution-gate",
        "source": "rust_memory_gateway_model_call_execution_gate",
        "authority": "rust_memory_gateway_execution_admission",
        "mode": "execution_admission_no_model_call",
        "production_authority_change": false,
        "execution_authority_in_rust": false,
        "execution_admission_authority_in_rust": true,
        "execution_admission_enabled": admission_enabled,
        "execution_admission_ready": ready_for_execution,
        "execution_enabled": false,
        "ready_for_execution": ready_for_execution,
        "would_call_model": false,
        "model_call_executed": false,
        "execution_requested": execution_requested,
        "request_id": request_id,
        "audit_ref": audit_ref,
        "started_at_ms": started_at_ms,
        "finished_at_ms": finished_at_ms,
        "duration_ms": finished_at_ms.saturating_sub(started_at_ms),
        "blockers": blockers,
        "plan": {
            "ok": true,
            "schema_version": MEMORY_GATEWAY_MODEL_CALL_PLAN_SCHEMA,
            "source": "rust_memory_gateway_model_call_fast_execution_summary",
            "mode": "fast_admission_no_prepare",
            "authority": "rust_memory_gateway_execution_admission",
            "status": "planned",
            "context_text_included": false,
            "context_char_count": 0,
            "selected_ref_count": 0,
            "prompt_text_included": false,
            "prompt_char_count": prompt_summary.get("prompt_char_count").and_then(Value::as_u64).unwrap_or(0),
            "message_count": prompt_summary.get("message_count").and_then(Value::as_u64).unwrap_or(0),
            "route_intent": route_intent,
            "fast_execution_gate": true,
        },
        "route_authority": {
            "provider_route_authority_in_rust": provider_route_authority,
            "model_route_authority_in_rust": model_route_authority,
            "route_specified": !route_unspecified,
        },
        "guards": {
            "local_ml_execute_http_not_invoked": true,
            "provider_route_not_mutated": true,
            "node_not_authority": true,
            "context_text_redacted_from_gate": true,
            "prompt_text_redacted_from_gate": true,
            "fast_execution_gate": true,
        },
        "next_gate": {
            "required_before_execution_cutover": [
                "attach_memory_gateway_model_call_executor",
                "local_ml_or_provider_execution_smoke",
                "doctor_and_ops_evidence",
                "rollback_gate"
            ],
            "admission_contract_ready": ready_for_execution,
            "safe_to_use_for_execution_preflight": true,
            "safe_to_use_for_shadow_planning": true,
        }
    })
    .to_string())
}

fn memory_gateway_model_call_execute_json_from_value(
    config: &HubConfig,
    body: &Value,
) -> Result<String, HttpJsonError> {
    let started_at_ms = now_ms_i64();
    let request_id = value_string(body, "request_id")
        .or_else(|| value_string(body, "requestId"))
        .or_else(|| value_string(body, "req_id"))
        .or_else(|| value_string(body, "reqId"))
        .unwrap_or_default();
    let audit_ref = value_string(body, "audit_ref")
        .or_else(|| value_string(body, "auditRef"))
        .unwrap_or_default();
    let execution_requested = gateway_model_call_execution_requested(body);

    let gate_started_at_ms = now_ms_i64();
    let gate_raw = memory_gateway_model_call_execution_gate_json_from_value(config, body)?;
    let gate_finished_at_ms = now_ms_i64();
    let gate = serde_json::from_str::<Value>(&gate_raw).map_err(|err| {
        gateway_model_call_execute_json_error(
            "500 Internal Server Error",
            "memory_gateway_model_call_execute_gate_parse_failed",
            format!("execution gate output was not valid JSON: {err}"),
            json!({}),
        )
    })?;
    let mut blockers = gate
        .get("blockers")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(Value::as_str)
                .map(ToString::to_string)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let gate_ready = gate
        .get("ready_for_execution")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let local_executor_enabled = gateway_model_call_local_executor_enabled_for_body(body);
    let local_executor_apply_enabled =
        gateway_model_call_local_executor_apply_enabled_for_body(body);
    let provider_id =
        first_public_token(body, &["provider_id", "providerId", "provider"]).unwrap_or_default();
    let model_id = first_public_token(
        body,
        &[
            "model_id",
            "modelId",
            "preferred_model_id",
            "preferredModelId",
        ],
    )
    .unwrap_or_default();
    let task_kind = first_public_token(body, &["task_kind", "taskKind", "task_type", "taskType"])
        .unwrap_or_else(|| "text_generate".to_string());
    let local_route = gateway_model_call_local_route_allowed(provider_id.as_str());
    let canary_scope = gateway_model_call_execute_canary_scope_for_body(
        body,
        request_id.as_str(),
        audit_ref.as_str(),
    );

    if !execution_requested {
        push_unique_string(&mut blockers, "explicit_execute_not_requested");
    }
    if !gate_ready {
        push_unique_string(
            &mut blockers,
            "memory_gateway_model_call_execution_gate_not_ready",
        );
    }
    if !local_executor_enabled {
        push_unique_string(
            &mut blockers,
            "memory_gateway_model_call_local_executor_not_enabled",
        );
    }
    if local_executor_enabled && !local_executor_apply_enabled {
        push_unique_string(
            &mut blockers,
            "memory_gateway_model_call_local_executor_apply_not_enabled",
        );
    }
    if !local_route {
        push_unique_string(
            &mut blockers,
            "memory_gateway_model_call_non_local_executor_not_supported",
        );
    }
    if !canary_scope.allowed {
        push_unique_string(&mut blockers, canary_scope.reason.as_str());
    }

    if !blockers.is_empty() {
        let finished_at_ms = now_ms_i64();
        return Ok(json!({
            "schema_version": MEMORY_GATEWAY_MODEL_CALL_EXECUTE_SCHEMA,
            "ok": true,
            "status": "blocked",
            "command": "model-call-execute",
            "source": "rust_memory_gateway_model_call_execute",
            "authority": "rust_memory_gateway_execute_guarded",
            "mode": "execute_guard_no_model_call",
            "production_authority_change": false,
            "execution_authority_in_rust": false,
            "execution_enabled": false,
            "ready_for_execution": false,
            "would_call_model": false,
            "model_call_invoked": false,
            "model_call_executed": false,
            "execution_requested": execution_requested,
            "request_id": request_id,
            "audit_ref": audit_ref,
            "started_at_ms": started_at_ms,
            "finished_at_ms": finished_at_ms,
            "duration_ms": finished_at_ms.saturating_sub(started_at_ms),
            "blockers": blockers,
            "gate": gateway_model_call_gate_summary(&gate),
            "executor": {
                "executor": "local_ml",
                "local_executor_enabled": local_executor_enabled,
                "local_executor_apply_enabled": local_executor_apply_enabled,
                "provider_id": provider_id,
                "model_id": model_id,
                "task_kind": task_kind,
                "local_route_allowed": local_route,
                "canary_only": canary_scope.enabled,
                "canary_scope_allowed": canary_scope.allowed,
                "canary_project_id": canary_scope.project_id,
                "canary_request_id_prefix": canary_scope.request_id_prefix,
                "canary_audit_ref_prefix": canary_scope.audit_ref_prefix,
            },
            "guards": {
                "context_text_redacted_from_execute": true,
                "prompt_text_redacted_from_execute": true,
                "local_ml_execute_http_invoked": false,
                "provider_route_not_mutated": true,
                "node_not_authority": true,
            },
        })
        .to_string());
    }

    if let Some(fake) = gateway_model_call_fake_local_ml_execution(body) {
        let finished_at_ms = now_ms_i64();
        return Ok(json!({
            "schema_version": MEMORY_GATEWAY_MODEL_CALL_EXECUTE_SCHEMA,
            "ok": fake.get("ok").and_then(Value::as_bool).unwrap_or(false),
            "status": if fake.get("ok").and_then(Value::as_bool).unwrap_or(false) { "executed" } else { "failed" },
            "command": "model-call-execute",
            "source": "rust_memory_gateway_model_call_execute",
            "authority": "rust_memory_gateway_local_ml_executor",
            "mode": "local_ml_execute",
            "production_authority_change": false,
            "execution_authority_in_rust": true,
            "execution_enabled": true,
            "ready_for_execution": true,
            "would_call_model": true,
            "model_call_invoked": true,
            "model_call_executed": fake.get("ok").and_then(Value::as_bool).unwrap_or(false),
            "execution_requested": execution_requested,
            "request_id": request_id,
            "audit_ref": audit_ref,
            "started_at_ms": started_at_ms,
            "finished_at_ms": finished_at_ms,
            "duration_ms": finished_at_ms.saturating_sub(started_at_ms),
            "blockers": [],
            "gate": gateway_model_call_gate_summary(&gate),
            "executor": {
                "executor": "local_ml",
                "local_executor_enabled": local_executor_enabled,
                "local_executor_apply_enabled": local_executor_apply_enabled,
                "provider_id": provider_id,
                "model_id": model_id,
                "task_kind": task_kind,
                "local_route_allowed": local_route,
                "canary_only": canary_scope.enabled,
                "canary_scope_allowed": canary_scope.allowed,
                "canary_project_id": canary_scope.project_id,
                "canary_request_id_prefix": canary_scope.request_id_prefix,
                "canary_audit_ref_prefix": canary_scope.audit_ref_prefix,
            },
            "local_ml": gateway_model_call_local_ml_summary(&fake),
            "execution_result": gateway_model_call_public_execution_result(&fake),
            "guards": {
                "context_text_redacted_from_execute": true,
                "prompt_text_redacted_from_execute": true,
                "local_ml_execute_http_invoked": true,
                "provider_route_not_mutated": true,
                "node_not_authority": true,
            },
        })
        .to_string());
    }

    let local_ml_readiness = local_ml_bridge::readiness(config);
    if !local_ml_readiness.ready {
        push_unique_string(&mut blockers, "local_ml_execution_not_ready");
        let finished_at_ms = now_ms_i64();
        return Ok(json!({
            "schema_version": MEMORY_GATEWAY_MODEL_CALL_EXECUTE_SCHEMA,
            "ok": true,
            "status": "blocked",
            "command": "model-call-execute",
            "source": "rust_memory_gateway_model_call_execute",
            "authority": "rust_memory_gateway_execute_guarded",
            "mode": "execute_guard_no_model_call",
            "production_authority_change": false,
            "execution_authority_in_rust": false,
            "execution_enabled": false,
            "ready_for_execution": false,
            "would_call_model": false,
            "model_call_invoked": false,
            "model_call_executed": false,
            "execution_requested": execution_requested,
            "request_id": request_id,
            "audit_ref": audit_ref,
            "started_at_ms": started_at_ms,
            "finished_at_ms": finished_at_ms,
            "duration_ms": finished_at_ms.saturating_sub(started_at_ms),
            "blockers": blockers,
            "gate": gateway_model_call_gate_summary(&gate),
            "executor": {
                "executor": "local_ml",
                "local_executor_enabled": local_executor_enabled,
                "local_executor_apply_enabled": local_executor_apply_enabled,
                "provider_id": provider_id,
                "model_id": model_id,
                "task_kind": task_kind,
                "local_route_allowed": local_route,
                "canary_only": canary_scope.enabled,
                "canary_scope_allowed": canary_scope.allowed,
                "canary_project_id": canary_scope.project_id,
                "canary_request_id_prefix": canary_scope.request_id_prefix,
                "canary_audit_ref_prefix": canary_scope.audit_ref_prefix,
            },
            "local_ml_readiness": local_ml_bridge::readiness_value(config),
            "guards": {
                "context_text_redacted_from_execute": true,
                "prompt_text_redacted_from_execute": true,
                "local_ml_execute_http_invoked": false,
                "provider_route_not_mutated": true,
                "node_not_authority": true,
            },
        })
        .to_string());
    }

    let local_body_started_at_ms = now_ms_i64();
    let local_body = gateway_model_call_local_ml_body(config, body, request_id.as_str())?;
    let local_body_finished_at_ms = now_ms_i64();
    let local_execute_started_at_ms = now_ms_i64();
    let (_status, local_raw) =
        local_ml_bridge::execute_http_json(config, "POST", local_body.to_string().as_str());
    let local_execute_finished_at_ms = now_ms_i64();
    let local_value = serde_json::from_str::<Value>(local_raw.trim()).map_err(|err| {
        gateway_model_call_execute_json_error(
            "500 Internal Server Error",
            "memory_gateway_model_call_local_ml_parse_failed",
            format!("local ML execution output was not valid JSON: {err}"),
            json!({}),
        )
    })?;
    let local_ok = local_value
        .get("ok")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let finished_at_ms = now_ms_i64();
    Ok(json!({
        "schema_version": MEMORY_GATEWAY_MODEL_CALL_EXECUTE_SCHEMA,
        "ok": local_ok,
        "status": if local_ok { "executed" } else { "failed" },
        "command": "model-call-execute",
        "source": "rust_memory_gateway_model_call_execute",
        "authority": "rust_memory_gateway_local_ml_executor",
        "mode": "local_ml_execute",
        "production_authority_change": false,
        "execution_authority_in_rust": true,
        "execution_enabled": true,
        "ready_for_execution": true,
        "would_call_model": true,
        "model_call_invoked": true,
        "model_call_executed": local_ok,
        "execution_requested": execution_requested,
        "request_id": request_id,
        "audit_ref": audit_ref,
        "started_at_ms": started_at_ms,
        "finished_at_ms": finished_at_ms,
        "duration_ms": finished_at_ms.saturating_sub(started_at_ms),
        "timings": {
            "gate_ms": gate_finished_at_ms.saturating_sub(gate_started_at_ms),
            "prepare_and_request_build_ms": local_body_finished_at_ms.saturating_sub(local_body_started_at_ms),
            "local_ml_bridge_ms": local_execute_finished_at_ms.saturating_sub(local_execute_started_at_ms),
            "total_ms": finished_at_ms.saturating_sub(started_at_ms),
        },
        "blockers": [],
        "gate": gateway_model_call_gate_summary(&gate),
        "executor": {
            "executor": "local_ml",
            "local_executor_enabled": local_executor_enabled,
            "local_executor_apply_enabled": local_executor_apply_enabled,
            "provider_id": provider_id,
            "model_id": model_id,
            "task_kind": task_kind,
            "local_route_allowed": local_route,
            "canary_only": canary_scope.enabled,
            "canary_scope_allowed": canary_scope.allowed,
            "canary_project_id": canary_scope.project_id,
            "canary_request_id_prefix": canary_scope.request_id_prefix,
            "canary_audit_ref_prefix": canary_scope.audit_ref_prefix,
        },
        "local_ml": gateway_model_call_local_ml_summary(&local_value),
        "execution_result": gateway_model_call_public_execution_result(&local_value),
        "guards": {
            "context_text_redacted_from_execute": true,
            "prompt_text_redacted_from_execute": true,
            "local_ml_execute_http_invoked": true,
            "provider_route_not_mutated": true,
            "node_not_authority": true,
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
            "assistant_personal",
            "assistant_user_memory_inspector",
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
        "assistant_personal" | "assistant_user_memory_inspector" => {
            vec!["supervisor".to_string()]
        }
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
    if scope == "user"
        && !matches!(
            use_mode.as_str(),
            "assistant_personal" | "assistant_user_memory_inspector"
        )
    {
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
    let candidate_maintenance = writeback_candidate_maintenance_readiness_json(config);
    let candidate_diagnostics = writeback_candidate_diagnostics_readiness_json(config);
    readiness_json_from_snapshot_inner(
        snapshot,
        Some(summary),
        Some(index_summary),
        Some(candidate_maintenance),
        Some(candidate_diagnostics),
    )
}

fn readiness_json_from_snapshot_inner(
    snapshot: &MemoryIndexSnapshot,
    object_summary: Option<xhub_db::MemoryObjectStoreSummary>,
    index_summary: Option<MemoryObjectIndexSummary>,
    candidate_maintenance: Option<Value>,
    candidate_diagnostics: Option<Value>,
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
            "mutation_gate": {
                "schema_version": MEMORY_OBJECT_MUTATION_SCHEMA,
                "ready": object_store_ready,
                "archive_http": true,
                "delete_tombstone_http": true,
                "pin_http": true,
                "unpin_http": true,
                "confirmation_required_for": ["archive", "delete"],
                "immutable_fail_closed": true,
                "delete_mode": "tombstone",
                "authority": "rust_memory_object_store",
                "production_authority_change": false,
            },
            "user_reveal_grant": {
                "schema_version": MEMORY_USER_REVEAL_GRANT_SCHEMA,
                "ready": object_store_ready,
                "issue_http": true,
                "evaluate_http": true,
                "revoke_http": true,
                "scope": "user",
                "surface": MEMORY_USER_REVEAL_GRANT_SURFACE,
                "default_ttl_ms": MEMORY_USER_REVEAL_GRANT_DEFAULT_TTL_MS,
                "max_ttl_ms": MEMORY_USER_REVEAL_GRANT_MAX_TTL_MS,
                "content_included": false,
                "memory_ids_included": false,
                "project_coder_allowed": false,
                "authority": "rust_memory_user_reveal_gate",
                "memory_serving_authority_change": false,
                "production_authority_change": false,
            },
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
            "writeback_candidates": {
                "schema_version": MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
                "ready": object_store_ready,
                "candidate_object_count": summary.candidate_object_count,
                "candidate_create_http": true,
                "candidate_list_http": true,
                "candidate_approve_reject_http": true,
                "candidate_maintenance_http": true,
                "secret_candidate_fail_closed": true,
                "authority": "rust_policy_gated_candidate_queue",
                "maintenance": candidate_maintenance.unwrap_or_else(|| json!({
                    "maintenance_ready": object_store_ready,
                    "candidate_maintenance_http": true,
                    "candidate_maintenance_cli": true,
                    "candidate_maintenance_schema": MEMORY_WRITEBACK_CANDIDATE_MAINTENANCE_SCHEMA,
                    "stale_candidate_count": 0,
                    "planned_archive_count": 0,
                    "planned_stale_review_required_count": 0,
                    "last_maintenance_report_path": "",
                })),
                "diagnostics": candidate_diagnostics.unwrap_or_else(|| json!({
                    "schema_version": MEMORY_WRITEBACK_CANDIDATE_DIAGNOSTICS_SCHEMA,
                    "ready": object_store_ready,
                    "candidate_count": summary.candidate_object_count,
                    "conflict_candidate_count": 0,
                    "stale_review_required_count": 0,
                    "stale_candidate_count": 0,
                    "planned_archive_count": 0,
                    "planned_stale_review_required_count": 0,
                    "superseding_candidate_count": 0,
                    "archived_superseded_count": 0,
                    "superseded_candidate_count": 0,
                    "queue_pressure": "low",
                    "noise_score": 0,
                    "production_authority_change": false,
                })),
                "production_authority_change": false,
            },
            "semantic_index_enabled": false,
        },
        "gateway_model_call_plan": {
            "schema_version": MEMORY_GATEWAY_MODEL_CALL_PLAN_SCHEMA,
            "ready": true,
            "endpoint": "POST /memory/gateway/model-call-plan",
            "aliases": ["POST /memory/gateway/generate-plan", "POST /memory/model-call-plan"],
            "authority": "rust_memory_gateway_plan_only",
            "mode": "plan_only_no_model_call",
            "model_call_execution": "not_started",
            "context_text_in_plan": false,
            "production_authority_change": false,
        },
        "gateway_model_call_execution_gate": memory_gateway_model_call_execution_status_value(),
        "gateway_model_call_execute": memory_gateway_model_call_execute_status_value(),
    })
    .to_string())
}

fn memory_object_index_summary_to_json(summary: &MemoryObjectIndexSummary) -> Value {
    json!({
        "source": "rust_hub_memory_object_index",
        "ready": summary.index_ready,
        "index_granularity": "object_chunk",
        "chunk_identity_schema": "xhub.memory.object_chunk_identity.v1",
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
            "object-archive",
            "object-delete",
            "object-pin",
            "object-unpin",
            "candidate-create",
            "candidate-extract",
            "candidate-list",
            "candidate-approve",
            "candidate-reject",
            "candidate-maintenance",
            "object-index-rebuild",
            "policy-evaluate",
            "project-canonical-sync",
            "gateway-prepare",
            "gateway-model-call-plan",
            "gateway-model-call-execution-gate",
            "gateway-model-call-execute",
            "readiness"
        ],
        "retrieval_result_schema": MEMORY_RETRIEVAL_RESULT_SCHEMA,
        "write_result_schema": MEMORY_WRITE_RESULT_SCHEMA,
        "memory_object_schema": MEMORY_OBJECT_SCHEMA,
        "memory_object_result_schema": MEMORY_OBJECT_RESULT_SCHEMA,
        "memory_object_mutation_schema": MEMORY_OBJECT_MUTATION_SCHEMA,
        "memory_policy_result_schema": MEMORY_POLICY_RESULT_SCHEMA,
        "memory_gateway_prepare_schema": MEMORY_GATEWAY_PREPARE_SCHEMA,
        "memory_gateway_model_call_plan_schema": MEMORY_GATEWAY_MODEL_CALL_PLAN_SCHEMA,
        "memory_gateway_model_call_execute_schema": MEMORY_GATEWAY_MODEL_CALL_EXECUTE_SCHEMA,
        "memory_writeback_candidate_schema": MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
        "memory_writeback_candidate_extract_schema": MEMORY_WRITEBACK_CANDIDATE_EXTRACT_SCHEMA,
        "memory_writeback_candidate_maintenance_schema": MEMORY_WRITEBACK_CANDIDATE_MAINTENANCE_SCHEMA,
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
        "object_mutation_http": {
            "archive": "POST /memory/objects/{memory_id}/archive",
            "delete": "POST /memory/objects/{memory_id}/delete",
            "pin": "POST /memory/objects/{memory_id}/pin",
            "unpin": "POST /memory/objects/{memory_id}/unpin",
            "confirmation_required_for": ["archive", "delete"],
            "delete_mode": "tombstone",
            "authority": "rust_memory_object_store",
            "production_authority_change": false
        },
        "object_mutation_flags": [
            "--memory-id",
            "--requester-role",
            "--use-mode",
            "--actor",
            "--audit-ref",
            "--reason",
            "--confirm",
            "--confirm-archive",
            "--confirm-delete",
            "--confirmation"
        ],
        "writeback_candidates_http": {
            "endpoint": "POST|GET /memory/writeback/candidates",
            "extract": "POST /memory/writeback/candidates/extract",
            "maintenance": "POST /memory/writeback/candidates/maintenance",
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
        "writeback_candidate_maintenance_flags": [
            "--project-id",
            "--max-age-ms",
            "--limit",
            "--apply",
            "--dry-run",
            "--actor",
            "--audit-ref",
            "--reason"
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
        "gateway_model_call_plan_http": {
            "endpoint": "POST /memory/gateway/model-call-plan",
            "aliases": ["POST /memory/gateway/generate-plan", "POST /memory/model-call-plan"],
            "mode": "plan_only_no_model_call",
            "model_call_execution": "not_started",
            "context_text_included": false,
            "production_authority_change": false
        },
        "gateway_model_call_execution_gate_http": memory_gateway_model_call_execution_status_value(),
        "gateway_model_call_execute_http": memory_gateway_model_call_execute_status_value(),
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
        ],
        "gateway_model_call_plan_flags": [
            "--request-id",
            "--audit-ref",
            "--requester-role",
            "--use-mode",
            "--scope",
            "--project-id",
            "--agent-id",
            "--provider-id",
            "--model-id",
            "--task-kind",
            "--prompt",
            "--latest-user",
            "--serving-profile-id",
            "--requested-layers",
            "--requested-source-kinds",
            "--remote-export-requested",
            "--max-items",
            "--max-snippet-chars"
        ],
        "gateway_model_call_execute_flags": [
            "--request-id",
            "--audit-ref",
            "--requester-role",
            "--use-mode",
            "--scope",
            "--project-id",
            "--provider-id",
            "--model-id",
            "--task-kind",
            "--prompt",
            "--latest-user",
            "--serving-profile-id",
            "--requested-layers",
            "--requested-source-kinds",
            "--execute",
            "--apply",
            "--commit",
            "--timeout-ms",
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

fn memory_policy_json_with_candidate_transition(
    raw_policy_json: &str,
    policy: &MemoryPolicyEvaluation,
    operation: &str,
    actor: &str,
    audit_ref: &str,
    transitioned_at_ms: i64,
) -> String {
    let mut value = serde_json::from_str::<Value>(raw_policy_json).unwrap_or_else(|_| json!({}));
    if !value.is_object() {
        value = json!({});
    }
    if let Some(map) = value.as_object_mut() {
        map.insert(
            "last_writeback_candidate_transition".to_string(),
            json!({
                "schema_version": MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
                "operation": operation,
                "actor": actor,
                "audit_ref": audit_ref,
                "transitioned_at_ms": transitioned_at_ms,
                "policy_decision": "allow",
                "policy": policy.to_json(),
                "production_authority_change": false,
            }),
        );
    }
    value.to_string()
}

fn memory_policy_json_with_object_mutation(
    raw_policy_json: &str,
    policy: &MemoryPolicyEvaluation,
    operation: &str,
    actor: &str,
    audit_ref: &str,
    mutated_at_ms: i64,
) -> String {
    let mut value = serde_json::from_str::<Value>(raw_policy_json).unwrap_or_else(|_| json!({}));
    if !value.is_object() {
        value = json!({});
    }
    if let Some(map) = value.as_object_mut() {
        map.insert(
            "last_memory_object_mutation".to_string(),
            json!({
                "schema_version": MEMORY_OBJECT_MUTATION_SCHEMA,
                "operation": operation,
                "actor": actor,
                "audit_ref": audit_ref,
                "mutated_at_ms": mutated_at_ms,
                "policy_decision": "allow",
                "policy": policy.to_json(),
                "authority": "rust_memory_object_store",
                "production_authority_change": false,
            }),
        );
    }
    value.to_string()
}

fn memory_provenance_json_with_object_mutation(
    raw_provenance_json: &str,
    operation: &str,
    actor: &str,
    audit_ref: &str,
    mutated_at_ms: i64,
) -> String {
    let mut value =
        serde_json::from_str::<Value>(raw_provenance_json).unwrap_or_else(|_| json!({}));
    if !value.is_object() {
        value = json!({});
    }
    if let Some(map) = value.as_object_mut() {
        map.insert(
            "last_memory_object_mutation".to_string(),
            json!({
                "schema_version": MEMORY_OBJECT_MUTATION_SCHEMA,
                "operation": operation,
                "actor": actor,
                "audit_ref": audit_ref,
                "mutated_at_ms": mutated_at_ms,
                "authority": "rust_memory_object_store",
                "production_authority_change": false,
            }),
        );
    }
    value.to_string()
}

#[derive(Debug, Clone)]
struct GatewayProfileDefaults {
    layers: Vec<String>,
    source_kinds: Vec<String>,
    max_items: usize,
    max_snippet_chars: usize,
    read_multiplier: usize,
}

fn normalize_serving_profile_id(raw: &str) -> Option<String> {
    let token = raw.trim().to_ascii_lowercase().replace('-', "_");
    match token.as_str() {
        "m0" | "heartbeat" | "m0_heartbeat" => Some("M0_Heartbeat".to_string()),
        "m1" | "execute" | "m1_execute" => Some("M1_Execute".to_string()),
        "m2" | "plan_review" | "planreview" | "m2_plan_review" | "m2_planreview" => {
            Some("M2_PlanReview".to_string())
        }
        "m3" | "deep_dive" | "deepdive" | "m3_deep_dive" | "m3_deepdive" => {
            Some("M3_DeepDive".to_string())
        }
        "m4" | "full_scan" | "fullscan" | "m4_full_scan" | "m4_fullscan" => {
            Some("M4_FullScan".to_string())
        }
        _ => None,
    }
}

fn gateway_default_serving_profile(use_mode: &str, _remote_export_requested: bool) -> String {
    match use_mode {
        "lane_handoff" | "remote_prompt_bundle" => "M0_Heartbeat".to_string(),
        _ => "M1_Execute".to_string(),
    }
}

fn gateway_serving_profile_rank(profile: &str) -> usize {
    match profile {
        "M0_Heartbeat" => 0,
        "M1_Execute" => 1,
        "M2_PlanReview" => 2,
        "M3_DeepDive" => 3,
        "M4_FullScan" => 4,
        _ => 1,
    }
}

fn gateway_profile_defaults(profile: &str) -> GatewayProfileDefaults {
    let project_source_kinds = vec![
        "project_goal".to_string(),
        "project_requirement".to_string(),
        "decision_track".to_string(),
        "current_state".to_string(),
        "next_step".to_string(),
        "open_question".to_string(),
        "risk".to_string(),
        "recommendation".to_string(),
    ];
    match profile {
        "M0_Heartbeat" => GatewayProfileDefaults {
            layers: vec!["l1_canonical".to_string(), "l3_working_set".to_string()],
            source_kinds: vec![
                "project_goal".to_string(),
                "decision_track".to_string(),
                "current_state".to_string(),
                "next_step".to_string(),
            ],
            max_items: 4,
            max_snippet_chars: 240,
            read_multiplier: 3,
        },
        "M2_PlanReview" => GatewayProfileDefaults {
            layers: vec![
                "l1_canonical".to_string(),
                "l2_observations".to_string(),
                "l3_working_set".to_string(),
            ],
            source_kinds: project_source_kinds,
            max_items: 20,
            max_snippet_chars: 640,
            read_multiplier: 5,
        },
        "M3_DeepDive" => {
            let mut source_kinds = project_source_kinds;
            source_kinds.push("memory_file".to_string());
            GatewayProfileDefaults {
                layers: vec![
                    "l1_canonical".to_string(),
                    "l2_observations".to_string(),
                    "l3_working_set".to_string(),
                ],
                source_kinds,
                max_items: 32,
                max_snippet_chars: 900,
                read_multiplier: 6,
            }
        }
        "M4_FullScan" => {
            let mut source_kinds = project_source_kinds;
            source_kinds.push("memory_file".to_string());
            GatewayProfileDefaults {
                layers: vec![
                    "l1_canonical".to_string(),
                    "l2_observations".to_string(),
                    "l3_working_set".to_string(),
                ],
                source_kinds,
                max_items: 48,
                max_snippet_chars: 1_200,
                read_multiplier: 8,
            }
        }
        _ => GatewayProfileDefaults {
            layers: vec![
                "l1_canonical".to_string(),
                "l2_observations".to_string(),
                "l3_working_set".to_string(),
            ],
            source_kinds: Vec::new(),
            max_items: 12,
            max_snippet_chars: 420,
            read_multiplier: 4,
        },
    }
}

fn gateway_allowed_layers(
    policy: &MemoryPolicyEvaluation,
    requested_layers: &[String],
) -> Vec<String> {
    let default_layers = gateway_profile_defaults("M1_Execute").layers;
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

fn gateway_model_call_plan_json_error(
    status: &'static str,
    error_code: &str,
    message: String,
    extra: Value,
) -> HttpJsonError {
    http_json_error_json(
        status,
        json!({
            "schema_version": MEMORY_GATEWAY_MODEL_CALL_PLAN_SCHEMA,
            "ok": false,
            "status": "error",
            "error_code": error_code,
            "message": message,
            "production_authority_change": false,
            "would_call_model": false,
            "model_call_executed": false,
            "extra": extra,
        }),
    )
}

fn gateway_model_call_execution_gate_json_error(
    status: &'static str,
    error_code: &str,
    message: String,
    extra: Value,
) -> HttpJsonError {
    http_json_error_json(
        status,
        json!({
            "schema_version": MEMORY_GATEWAY_MODEL_CALL_EXECUTION_GATE_SCHEMA,
            "ok": false,
            "status": "error",
            "error_code": error_code,
            "message": message,
            "production_authority_change": false,
            "would_call_model": false,
            "model_call_executed": false,
            "extra": extra,
        }),
    )
}

fn gateway_model_call_execute_json_error(
    status: &'static str,
    error_code: &str,
    message: String,
    extra: Value,
) -> HttpJsonError {
    http_json_error_json(
        status,
        json!({
            "schema_version": MEMORY_GATEWAY_MODEL_CALL_EXECUTE_SCHEMA,
            "ok": false,
            "status": "error",
            "error_code": error_code,
            "message": message,
            "production_authority_change": false,
            "would_call_model": false,
            "model_call_invoked": false,
            "model_call_executed": false,
            "extra": extra,
        }),
    )
}

fn gateway_model_call_prepare_error(err: HttpJsonError) -> HttpJsonError {
    let prepare_error = serde_json::from_str::<Value>(&err.body).unwrap_or_else(|_| json!({}));
    let prepare_error_code = prepare_error
        .get("error_code")
        .or_else(|| prepare_error.get("deny_code"))
        .and_then(Value::as_str)
        .unwrap_or("memory_gateway_prepare_failed")
        .to_string();
    http_json_error_json(
        err.status,
        json!({
            "schema_version": MEMORY_GATEWAY_MODEL_CALL_PLAN_SCHEMA,
            "ok": false,
            "status": if err.status.starts_with("403") { "denied" } else { "error" },
            "error_code": "memory_gateway_model_call_prepare_failed",
            "prepare_error_code": prepare_error_code,
            "production_authority_change": false,
            "would_call_model": false,
            "model_call_executed": false,
            "prepare_error": prepare_error,
        }),
    )
}

fn gateway_model_call_execution_requested(body: &Value) -> bool {
    value_bool(body, "execute", false)
        || value_bool(body, "execute_model_call", false)
        || value_bool(body, "executeModelCall", false)
        || value_bool(body, "model_call_execute", false)
        || value_bool(body, "modelCallExecute", false)
        || value_bool(body, "apply", false)
        || value_bool(body, "commit", false)
}

pub fn memory_gateway_model_call_execution_admission_enabled() -> bool {
    env_bool(
        "XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTION_ADMISSION",
        false,
    ) || env_bool("XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_ADMISSION", false)
}

fn gateway_model_call_fast_execution_gate_enabled_for_body(body: &Value) -> bool {
    gateway_model_call_fast_execution_gate_test_override(body)
        .unwrap_or_else(|| env_bool("XHUB_RUST_MEMORY_GATEWAY_FAST_EXECUTION_GATE", true))
}

pub fn memory_gateway_model_call_provider_route_authority_enabled() -> bool {
    env_bool("XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY", false)
        || env_bool("XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PRODUCTION", false)
        || (env_bool("XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CUTOVER", false)
            && env_bool("XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_APPLY", false))
}

pub fn memory_gateway_model_call_model_route_authority_enabled() -> bool {
    env_bool("XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY", false)
        || env_bool("XHUB_RUST_MODEL_ROUTE_AUTHORITY_PRODUCTION", false)
        || (env_bool("XHUB_RUST_MODEL_ROUTE_AUTHORITY_CUTOVER", false)
            && env_bool("XHUB_RUST_MODEL_ROUTE_AUTHORITY_APPLY", false))
}

pub fn memory_gateway_model_call_route_authority_ready() -> bool {
    memory_gateway_model_call_provider_route_authority_enabled()
        && memory_gateway_model_call_model_route_authority_enabled()
}

pub fn memory_gateway_model_call_execution_status_value() -> Value {
    let admission_enabled = memory_gateway_model_call_execution_admission_enabled();
    let provider_route_authority = memory_gateway_model_call_provider_route_authority_enabled();
    let model_route_authority = memory_gateway_model_call_model_route_authority_enabled();
    json!({
        "schema_version": MEMORY_GATEWAY_MODEL_CALL_EXECUTION_GATE_SCHEMA,
        "ready": true,
        "endpoint": "POST /memory/gateway/model-call-execution-gate",
        "aliases": ["POST /memory/gateway/generate-execution-gate", "POST /memory/model-call-execution-gate"],
        "authority": if admission_enabled { "rust_memory_gateway_execution_admission" } else { "rust_memory_gateway_execution_gate_only" },
        "mode": if admission_enabled { "execution_admission_no_model_call" } else { "gate_only_no_model_call" },
        "execution_admission_authority_in_rust": admission_enabled,
        "execution_admission_enabled": admission_enabled,
        "execution_admission_ready": admission_enabled && provider_route_authority && model_route_authority,
        "provider_route_authority_in_rust": provider_route_authority,
        "model_route_authority_in_rust": model_route_authority,
        "model_call_execution": "not_started",
        "model_call_execution_in_rust": false,
        "context_text_in_gate": false,
        "prompt_text_in_gate": false,
        "production_authority_change": false,
    })
}

pub fn memory_gateway_model_call_execute_status_value() -> Value {
    let admission_enabled = memory_gateway_model_call_execution_admission_enabled();
    let route_authority = memory_gateway_model_call_route_authority_ready();
    let local_executor_enabled = memory_gateway_model_call_local_executor_enabled();
    let local_executor_apply_enabled = memory_gateway_model_call_local_executor_apply_enabled();
    let canary_only = memory_gateway_model_call_execute_canary_only_enabled();
    let local_executor_ready_for_attempt = admission_enabled
        && route_authority
        && local_executor_enabled
        && local_executor_apply_enabled;
    json!({
        "schema_version": MEMORY_GATEWAY_MODEL_CALL_EXECUTE_SCHEMA,
        "ready": true,
        "endpoint": "POST /memory/gateway/model-call-execute",
        "aliases": ["POST /memory/gateway/generate", "POST /memory/model-call-execute"],
        "authority": if local_executor_enabled && local_executor_apply_enabled { "rust_memory_gateway_local_ml_executor" } else { "rust_memory_gateway_execute_guarded" },
        "mode": if local_executor_enabled && local_executor_apply_enabled && canary_only { "local_ml_execute_canary_available_after_admission" } else if local_executor_enabled && local_executor_apply_enabled { "local_ml_execute_available_after_admission" } else { "execute_guard_no_model_call" },
        "execution_admission_authority_in_rust": admission_enabled,
        "execution_admission_ready": admission_enabled && route_authority,
        "local_executor_enabled": local_executor_enabled,
        "local_executor_apply_enabled": local_executor_apply_enabled,
        "local_executor_ready_for_attempt": local_executor_ready_for_attempt,
        "canary_only_supported": true,
        "canary_only": canary_only,
        "canary_scope": {
            "enabled": canary_only,
            "project_id": memory_gateway_model_call_execute_canary_project_id(),
            "request_id_prefix": memory_gateway_model_call_execute_canary_request_prefix(),
            "audit_ref_prefix": memory_gateway_model_call_execute_canary_audit_prefix(),
        },
        "executor": "local_ml",
        "model_call_execution_in_rust": local_executor_ready_for_attempt,
        "local_ml_execution_readiness_required": true,
        "content_free_ops_summary_required": true,
        "production_authority_change": false,
    })
}

pub fn memory_gateway_model_call_local_executor_enabled() -> bool {
    env_bool("XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_LOCAL_EXECUTOR", false)
}

pub fn memory_gateway_model_call_local_executor_apply_enabled() -> bool {
    env_bool("XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_APPLY", false)
}

pub fn memory_gateway_model_call_execute_canary_only_enabled() -> bool {
    env_bool(
        "XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_CANARY_ONLY",
        false,
    )
}

fn memory_gateway_model_call_execute_canary_project_id() -> String {
    env_string_or_default(
        "XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_CANARY_PROJECT_ID",
        "xt-memory-gateway-live-canary",
    )
}

fn memory_gateway_model_call_execute_canary_request_prefix() -> String {
    env_string_or_default(
        "XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_CANARY_REQUEST_PREFIX",
        "memory_gateway_live_canary_",
    )
}

fn memory_gateway_model_call_execute_canary_audit_prefix() -> String {
    env_string_or_default(
        "XHUB_RUST_MEMORY_GATEWAY_MODEL_CALL_EXECUTE_CANARY_AUDIT_PREFIX",
        "memory_gateway_live_canary:",
    )
}

fn gateway_model_call_execute_canary_project_id_for_body(body: &Value) -> String {
    gateway_model_call_execute_canary_project_id_test_override(body)
        .unwrap_or_else(memory_gateway_model_call_execute_canary_project_id)
}

fn gateway_model_call_execute_canary_request_prefix_for_body(body: &Value) -> String {
    gateway_model_call_execute_canary_request_prefix_test_override(body)
        .unwrap_or_else(memory_gateway_model_call_execute_canary_request_prefix)
}

fn gateway_model_call_execute_canary_audit_prefix_for_body(body: &Value) -> String {
    gateway_model_call_execute_canary_audit_prefix_test_override(body)
        .unwrap_or_else(memory_gateway_model_call_execute_canary_audit_prefix)
}

fn gateway_model_call_execution_admission_enabled_for_body(body: &Value) -> bool {
    memory_gateway_model_call_execution_admission_enabled()
        || gateway_model_call_execution_admission_test_override(body)
}

fn gateway_model_call_local_executor_enabled_for_body(body: &Value) -> bool {
    memory_gateway_model_call_local_executor_enabled()
        || gateway_model_call_local_executor_test_override(body)
}

fn gateway_model_call_local_executor_apply_enabled_for_body(body: &Value) -> bool {
    memory_gateway_model_call_local_executor_apply_enabled()
        || gateway_model_call_local_executor_apply_test_override(body)
}

fn gateway_model_call_provider_route_authority_ready_for_body(body: &Value) -> bool {
    memory_gateway_model_call_provider_route_authority_enabled()
        || gateway_model_call_provider_route_authority_test_override(body)
}

fn gateway_model_call_model_route_authority_ready_for_body(body: &Value) -> bool {
    memory_gateway_model_call_model_route_authority_enabled()
        || gateway_model_call_model_route_authority_test_override(body)
}

fn gateway_model_call_local_route_allowed(provider_id: &str) -> bool {
    let normalized = provider_id.trim().to_ascii_lowercase().replace('-', "_");
    normalized.is_empty()
        || matches!(
            normalized.as_str(),
            "local" | "mlx" | "mlx_vlm" | "llama_cpp" | "llamacpp" | "transformers"
        )
}

#[derive(Debug, Clone)]
struct GatewayModelCallCanaryScope {
    enabled: bool,
    allowed: bool,
    reason: String,
    project_id: String,
    request_id_prefix: String,
    audit_ref_prefix: String,
}

fn gateway_model_call_execute_canary_scope_for_body(
    body: &Value,
    request_id: &str,
    audit_ref: &str,
) -> GatewayModelCallCanaryScope {
    let enabled = memory_gateway_model_call_execute_canary_only_enabled()
        || gateway_model_call_execute_canary_only_test_override(body);
    let project_id = gateway_model_call_execute_canary_project_id_for_body(body);
    let request_id_prefix = gateway_model_call_execute_canary_request_prefix_for_body(body);
    let audit_ref_prefix = gateway_model_call_execute_canary_audit_prefix_for_body(body);
    if !enabled {
        return GatewayModelCallCanaryScope {
            enabled,
            allowed: true,
            reason: String::new(),
            project_id,
            request_id_prefix,
            audit_ref_prefix,
        };
    }

    let body_project_id = value_string(body, "project_id")
        .or_else(|| value_string(body, "projectId"))
        .unwrap_or_default();
    let allowed = body_project_id == project_id
        && !request_id.is_empty()
        && request_id.starts_with(request_id_prefix.as_str())
        && !audit_ref.is_empty()
        && audit_ref.starts_with(audit_ref_prefix.as_str());
    GatewayModelCallCanaryScope {
        enabled,
        allowed,
        reason: if allowed {
            String::new()
        } else {
            "memory_gateway_model_call_execute_canary_scope_mismatch".to_string()
        },
        project_id,
        request_id_prefix,
        audit_ref_prefix,
    }
}

fn gateway_model_call_gate_summary(gate: &Value) -> Value {
    json!({
        "schema_version": gate.get("schema_version").cloned().unwrap_or(Value::Null),
        "ok": gate.get("ok").and_then(Value::as_bool).unwrap_or(false),
        "status": gate.get("status").cloned().unwrap_or(Value::Null),
        "source": gate.get("source").cloned().unwrap_or(Value::Null),
        "mode": gate.get("mode").cloned().unwrap_or(Value::Null),
        "authority": gate.get("authority").cloned().unwrap_or(Value::Null),
        "ready_for_execution": gate.get("ready_for_execution").and_then(Value::as_bool).unwrap_or(false),
        "execution_admission_authority_in_rust": gate.get("execution_admission_authority_in_rust").and_then(Value::as_bool).unwrap_or(false),
        "execution_authority_in_rust": gate.get("execution_authority_in_rust").and_then(Value::as_bool).unwrap_or(false),
        "would_call_model": gate.get("would_call_model").and_then(Value::as_bool).unwrap_or(false),
        "model_call_executed": gate.get("model_call_executed").and_then(Value::as_bool).unwrap_or(false),
        "blockers": gate.get("blockers").cloned().unwrap_or_else(|| json!([])),
        "context_text_included": gate.pointer("/plan/context_text_included").and_then(Value::as_bool).unwrap_or(false),
        "prompt_text_included": gate.pointer("/plan/prompt_text_included").and_then(Value::as_bool).unwrap_or(false),
    })
}

fn gateway_model_call_local_ml_summary(value: &Value) -> Value {
    json!({
        "schema_version": value.get("schema_version").cloned().unwrap_or(Value::Null),
        "ok": value.get("ok").and_then(Value::as_bool).unwrap_or(false),
        "command": value.get("command").cloned().unwrap_or(Value::Null),
        "engine": value.get("engine").cloned().unwrap_or(Value::Null),
        "execution_authority_in_rust": value.get("execution_authority_in_rust").and_then(Value::as_bool).unwrap_or(false),
        "duration_ms": value.get("duration_ms").cloned().unwrap_or(Value::Null),
        "execution_path": value.get("execution_path").cloned().unwrap_or(Value::Null),
        "command_proxy_ready_for_execution": value.get("command_proxy_ready_for_execution").and_then(Value::as_bool).unwrap_or(false),
        "error_code": value.get("error_code")
            .or_else(|| value.get("error"))
            .cloned()
            .unwrap_or(Value::Null),
        "result_ok": value.get("result").and_then(|result| result.get("ok")).and_then(Value::as_bool).unwrap_or(false),
        "result_error": value.get("result").and_then(|result| result.get("error")).cloned().unwrap_or(Value::Null),
        "result_latency_ms": value.get("result")
            .and_then(|result| result.get("latencyMs").or_else(|| result.get("latency_ms")))
            .cloned()
            .unwrap_or(Value::Null),
        "result_text_included": gateway_model_call_result_text_present(value),
    })
}

fn gateway_model_call_result_text_present(value: &Value) -> bool {
    fn visit(value: &Value) -> bool {
        match value {
            Value::String(text) => !text.trim().is_empty(),
            Value::Array(items) => items.iter().any(visit),
            Value::Object(map) => map.iter().any(|(key, item)| {
                let normalized = key.replace(['-', '_'], "").to_ascii_lowercase();
                matches!(
                    normalized.as_str(),
                    "text" | "output" | "response" | "content" | "completion"
                ) && visit(item)
            }),
            _ => false,
        }
    }
    value.get("result").map(visit).unwrap_or(false)
}

fn gateway_model_call_public_execution_result(value: &Value) -> Value {
    fn scrub(value: &Value) -> Value {
        match value {
            Value::Array(items) => Value::Array(items.iter().map(scrub).collect()),
            Value::Object(map) => {
                let mut out = serde_json::Map::new();
                for (key, item) in map {
                    let normalized = key.replace(['-', '_'], "").to_ascii_lowercase();
                    if matches!(
                        normalized.as_str(),
                        "request"
                            | "localruntimerequest"
                            | "prompt"
                            | "messages"
                            | "input"
                            | "query"
                            | "latestuser"
                            | "context"
                            | "contexttext"
                    ) {
                        continue;
                    }
                    out.insert(key.clone(), scrub(item));
                }
                Value::Object(out)
            }
            _ => value.clone(),
        }
    }
    scrub(value)
}

fn gateway_model_call_local_ml_body(
    config: &HubConfig,
    body: &Value,
    request_id: &str,
) -> Result<Value, HttpJsonError> {
    let prompt_summary = gateway_model_call_prompt_summary(body)?;
    let mut prepare_body = body.clone();
    strip_gateway_model_call_execution_flags(&mut prepare_body);
    if let Some(prompt) = gateway_model_call_primary_prompt(body) {
        if let Some(map) = prepare_body.as_object_mut() {
            if !map.contains_key("latest_user")
                && !map.contains_key("latestUser")
                && !map.contains_key("query")
            {
                map.insert("latest_user".to_string(), json!(prompt));
            }
        }
    }
    let prepare_raw = memory_gateway_prepare_json_from_value(config, &prepare_body)
        .map_err(gateway_model_call_prepare_error)?;
    let prepare = serde_json::from_str::<Value>(&prepare_raw).map_err(|err| {
        gateway_model_call_execute_json_error(
            "500 Internal Server Error",
            "memory_gateway_model_call_execute_prepare_parse_failed",
            format!("prepare output was not valid JSON: {err}"),
            json!({}),
        )
    })?;
    let context_text = prepare
        .get("context_text")
        .and_then(Value::as_str)
        .unwrap_or("");
    let prompt = gateway_model_call_primary_prompt(body).unwrap_or_default();
    let model_prompt = if context_text.trim().is_empty() {
        prompt
    } else if prompt.trim().is_empty() {
        context_text.to_string()
    } else {
        format!("Memory Context:\n{context_text}\n\nUser Request:\n{prompt}")
    };
    let provider_id =
        first_public_token(body, &["provider_id", "providerId", "provider"]).unwrap_or_default();
    let model_id = first_public_token(
        body,
        &[
            "model_id",
            "modelId",
            "preferred_model_id",
            "preferredModelId",
        ],
    )
    .unwrap_or_default();
    let task_kind = first_public_token(body, &["task_kind", "taskKind", "task_type", "taskType"])
        .unwrap_or_else(|| "text_generate".to_string());
    let timeout_ms = value_u64(body, "timeout_ms")
        .or_else(|| value_u64(body, "timeoutMs"))
        .unwrap_or(60_000)
        .clamp(1_000, 300_000);
    let mut request = serde_json::Map::new();
    request.insert("request_id".to_string(), json!(request_id));
    request.insert("task_kind".to_string(), json!(task_kind));
    request.insert("taskKind".to_string(), json!(task_kind));
    request.insert("task_type".to_string(), json!(task_kind));
    request.insert("prompt".to_string(), json!(model_prompt));
    request.insert(
        "memory_context_applied".to_string(),
        json!(!context_text.trim().is_empty()),
    );
    request.insert(
        "memory_context_char_count".to_string(),
        json!(context_text.chars().count()),
    );
    request.insert("prompt_summary".to_string(), prompt_summary);
    if !model_id.is_empty() {
        request.insert("model_id".to_string(), json!(model_id));
        request.insert("modelId".to_string(), json!(model_id));
    }
    let normalized_provider = provider_id.trim().to_ascii_lowercase().replace('-', "_");
    if gateway_model_call_local_route_allowed(provider_id.as_str())
        && !matches!(normalized_provider.as_str(), "" | "local")
    {
        request.insert("provider".to_string(), json!(normalized_provider));
    }
    Ok(json!({
        "command": "run-local-task",
        "request_id": request_id,
        "timeout_ms": timeout_ms,
        "request": Value::Object(request),
    }))
}

fn push_unique_string(values: &mut Vec<String>, value: &str) {
    if !values.iter().any(|item| item == value) {
        values.push(value.to_string());
    }
}

#[cfg(test)]
fn gateway_model_call_execution_admission_test_override(body: &Value) -> bool {
    value_bool(
        body,
        "__test_memory_gateway_model_call_execution_admission",
        false,
    )
}

#[cfg(not(test))]
fn gateway_model_call_execution_admission_test_override(_body: &Value) -> bool {
    false
}

#[cfg(test)]
fn gateway_model_call_fast_execution_gate_test_override(body: &Value) -> Option<bool> {
    if body
        .as_object()
        .map(|map| map.contains_key("__test_fast_execution_gate_enabled"))
        .unwrap_or(false)
    {
        Some(value_bool(body, "__test_fast_execution_gate_enabled", true))
    } else {
        None
    }
}

#[cfg(not(test))]
fn gateway_model_call_fast_execution_gate_test_override(_body: &Value) -> Option<bool> {
    None
}

#[cfg(test)]
fn gateway_model_call_provider_route_authority_test_override(body: &Value) -> bool {
    value_bool(body, "__test_provider_route_authority_in_rust", false)
}

#[cfg(not(test))]
fn gateway_model_call_provider_route_authority_test_override(_body: &Value) -> bool {
    false
}

#[cfg(test)]
fn gateway_model_call_model_route_authority_test_override(body: &Value) -> bool {
    value_bool(body, "__test_model_route_authority_in_rust", false)
}

#[cfg(not(test))]
fn gateway_model_call_model_route_authority_test_override(_body: &Value) -> bool {
    false
}

#[cfg(test)]
fn gateway_model_call_local_executor_test_override(body: &Value) -> bool {
    value_bool(body, "__test_local_executor_enabled", false)
}

#[cfg(not(test))]
fn gateway_model_call_local_executor_test_override(_body: &Value) -> bool {
    false
}

#[cfg(test)]
fn gateway_model_call_local_executor_apply_test_override(body: &Value) -> bool {
    value_bool(body, "__test_local_executor_apply_enabled", false)
}

#[cfg(not(test))]
fn gateway_model_call_local_executor_apply_test_override(_body: &Value) -> bool {
    false
}

#[cfg(test)]
fn gateway_model_call_execute_canary_only_test_override(body: &Value) -> bool {
    value_bool(body, "__test_model_call_execute_canary_only", false)
}

#[cfg(not(test))]
fn gateway_model_call_execute_canary_only_test_override(_body: &Value) -> bool {
    false
}

#[cfg(test)]
fn gateway_model_call_execute_canary_project_id_test_override(body: &Value) -> Option<String> {
    value_string(body, "__test_model_call_execute_canary_project_id")
}

#[cfg(not(test))]
fn gateway_model_call_execute_canary_project_id_test_override(_body: &Value) -> Option<String> {
    None
}

#[cfg(test)]
fn gateway_model_call_execute_canary_request_prefix_test_override(body: &Value) -> Option<String> {
    value_string(body, "__test_model_call_execute_canary_request_prefix")
}

#[cfg(not(test))]
fn gateway_model_call_execute_canary_request_prefix_test_override(_body: &Value) -> Option<String> {
    None
}

#[cfg(test)]
fn gateway_model_call_execute_canary_audit_prefix_test_override(body: &Value) -> Option<String> {
    value_string(body, "__test_model_call_execute_canary_audit_prefix")
}

#[cfg(not(test))]
fn gateway_model_call_execute_canary_audit_prefix_test_override(_body: &Value) -> Option<String> {
    None
}

#[cfg(test)]
fn gateway_model_call_fake_local_ml_execution(body: &Value) -> Option<Value> {
    if !value_bool(body, "__test_fake_local_ml_execute_ok", false) {
        return None;
    }
    Some(json!({
        "schema_version": local_ml_bridge::LOCAL_ML_BRIDGE_SCHEMA,
        "ok": true,
        "command": "execute",
        "engine": "test_fake_local_ml",
        "execution_authority_in_rust": true,
        "duration_ms": 1,
        "result": {
            "ok": true,
            "text": "Synthetic gateway execution output.",
            "request": {
                "prompt": "redact me"
            }
        }
    }))
}

#[cfg(not(test))]
fn gateway_model_call_fake_local_ml_execution(_body: &Value) -> Option<Value> {
    None
}

fn strip_gateway_model_call_execution_flags(body: &mut Value) {
    let Some(map) = body.as_object_mut() else {
        return;
    };
    for key in [
        "execute",
        "execute_model_call",
        "executeModelCall",
        "model_call_execute",
        "modelCallExecute",
        "apply",
        "commit",
    ] {
        map.remove(key);
    }
}

fn gateway_model_call_primary_prompt(body: &Value) -> Option<String> {
    value_string(body, "prompt")
        .or_else(|| value_string(body, "latest_user"))
        .or_else(|| value_string(body, "latestUser"))
        .or_else(|| value_string(body, "query"))
        .or_else(|| value_string(body, "input"))
}

fn gateway_model_call_prompt_summary(body: &Value) -> Result<Value, HttpJsonError> {
    let prompt = gateway_model_call_primary_prompt(body);
    let mut prompt_char_count = 0usize;
    if let Some(value) = &prompt {
        if looks_like_secret_public(value) {
            return Err(gateway_model_call_plan_json_error(
                "403 Forbidden",
                "memory_gateway_model_call_secret_like_prompt_denied",
                "secret-like prompt/query denied before model-call planning".to_string(),
                json!({ "prompt_present": true }),
            ));
        }
        prompt_char_count = value.chars().count();
    }
    let messages = body.get("messages").and_then(Value::as_array);
    let message_count = messages.map(|items| items.len()).unwrap_or(0);
    let mut message_char_count = 0usize;
    let mut message_secret_like = false;
    if let Some(items) = messages {
        for item in items {
            let (chars, secret) = gateway_model_call_value_text_summary(item);
            message_char_count = message_char_count.saturating_add(chars);
            message_secret_like |= secret;
        }
    }
    if message_secret_like {
        return Err(gateway_model_call_plan_json_error(
            "403 Forbidden",
            "memory_gateway_model_call_secret_like_message_denied",
            "secret-like message content denied before model-call planning".to_string(),
            json!({ "message_count": message_count }),
        ));
    }
    Ok(json!({
        "prompt_present": prompt.is_some(),
        "prompt_char_count": prompt_char_count,
        "message_count": message_count,
        "message_char_count": message_char_count,
        "text_included": false,
    }))
}

fn gateway_model_call_value_text_summary(value: &Value) -> (usize, bool) {
    match value {
        Value::String(text) => (text.chars().count(), looks_like_secret_public(text)),
        Value::Array(items) => items.iter().fold((0usize, false), |acc, item| {
            let (chars, secret) = gateway_model_call_value_text_summary(item);
            (acc.0.saturating_add(chars), acc.1 || secret)
        }),
        Value::Object(map) => map.values().fold((0usize, false), |acc, item| {
            let (chars, secret) = gateway_model_call_value_text_summary(item);
            (acc.0.saturating_add(chars), acc.1 || secret)
        }),
        _ => (0, false),
    }
}

fn gateway_prepare_plan_summary(prepare: &Value) -> Value {
    json!({
        "schema_version": prepare.get("schema_version").cloned().unwrap_or(Value::Null),
        "ok": prepare.get("ok").cloned().unwrap_or(Value::Bool(false)),
        "status": prepare.get("status").cloned().unwrap_or(Value::Null),
        "source": prepare.get("source").cloned().unwrap_or(Value::Null),
        "mode": prepare.get("mode").cloned().unwrap_or(Value::Null),
        "requester_role": prepare.get("requester_role").cloned().unwrap_or(Value::Null),
        "use_mode": prepare.get("use_mode").cloned().unwrap_or(Value::Null),
        "scope": prepare.get("scope").cloned().unwrap_or(Value::Null),
        "serving_profile_id": prepare.get("serving_profile_id").cloned().unwrap_or(Value::Null),
        "selected_profile": prepare.get("selected_profile").cloned().unwrap_or(Value::Null),
        "effective_profile": prepare.get("effective_profile").cloned().unwrap_or(Value::Null),
        "profile_reason": prepare.get("profile_reason").cloned().unwrap_or(Value::Null),
        "expanded": prepare.get("expanded").cloned().unwrap_or(Value::Bool(false)),
        "expansion_reason": prepare.get("expansion_reason").cloned().unwrap_or(Value::Null),
        "project_id": prepare.get("project_id").cloned().unwrap_or(Value::Null),
        "remote_export_requested": prepare.get("remote_export_requested").cloned().unwrap_or(Value::Bool(false)),
        "policy": prepare.get("policy").cloned().unwrap_or(Value::Null),
        "object_count": prepare.get("object_count").cloned().unwrap_or(Value::Null),
        "selected_count": prepare.get("selected_count").cloned().unwrap_or(Value::Null),
        "selected_chunk_count": prepare.get("selected_chunk_count").cloned().unwrap_or(Value::Null),
        "selected_refs": prepare.get("selected_refs").cloned().unwrap_or(Value::Null),
        "omitted_count": prepare.get("omitted_count").cloned().unwrap_or(Value::Null),
        "omitted_ref_count": prepare.get("omitted_ref_count").cloned().unwrap_or(Value::Null),
        "omitted_refs": prepare.get("omitted_refs").cloned().unwrap_or(Value::Null),
        "denied_count": prepare.get("denied_count").cloned().unwrap_or(Value::Null),
        "max_items": prepare.get("max_items").cloned().unwrap_or(Value::Null),
        "max_snippet_chars": prepare.get("max_snippet_chars").cloned().unwrap_or(Value::Null),
        "index_source": prepare.get("index_source").cloned().unwrap_or(Value::Null),
        "index_granularity": prepare.get("index_granularity").cloned().unwrap_or(Value::Null),
        "chunk_identity_schema": prepare.get("chunk_identity_schema").cloned().unwrap_or(Value::Null),
        "chunk_expand_via_get_ref": prepare.get("chunk_expand_via_get_ref").cloned().unwrap_or(Value::Bool(false)),
        "requested_layers": prepare.get("requested_layers").cloned().unwrap_or(Value::Null),
        "effective_layers": prepare.get("effective_layers").cloned().unwrap_or(Value::Null),
        "requested_source_kinds": prepare.get("requested_source_kinds").cloned().unwrap_or(Value::Null),
        "raw_evidence_allowed": prepare.get("raw_evidence_allowed").cloned().unwrap_or(Value::Bool(false)),
        "remote_export_filtered_count": prepare.get("remote_export_filtered_count").cloned().unwrap_or(Value::Null),
        "skipped": prepare.get("skipped").cloned().unwrap_or(Value::Null),
        "omitted_reason_counts": prepare.get("omitted_reason_counts").cloned().unwrap_or(Value::Null),
        "production_authority_change": false,
    })
}

fn gateway_prepare_selected_refs(prepare: &Value) -> Vec<Value> {
    if let Some(items) = prepare.get("selected_refs").and_then(Value::as_array) {
        return items.clone();
    }
    let mut refs = Vec::new();
    if let Some(slots) = prepare.get("slots").and_then(Value::as_array) {
        for slot in slots {
            let Some(objects) = slot.get("objects").and_then(Value::as_array) else {
                continue;
            };
            for object in objects {
                refs.push(json!({
                    "ref": object.get("ref").cloned().unwrap_or(Value::Null),
                    "chunk_ref": object.get("chunk_ref").cloned().unwrap_or(Value::Null),
                    "chunk_id": object.get("chunk_id").cloned().unwrap_or(Value::Null),
                    "chunk_identity_schema": object.get("chunk_identity_schema").cloned().unwrap_or(Value::Null),
                    "chunk_start_line": object.get("chunk_start_line").cloned().unwrap_or(Value::Null),
                    "chunk_end_line": object.get("chunk_end_line").cloned().unwrap_or(Value::Null),
                    "memory_id": object.get("memory_id").cloned().unwrap_or(Value::Null),
                    "layer": object.get("layer").cloned().unwrap_or_else(|| slot.get("layer").cloned().unwrap_or(Value::Null)),
                    "source_kind": object.get("source_kind").cloned().unwrap_or(Value::Null),
                    "scope": object.get("scope").cloned().unwrap_or(Value::Null),
                    "project_id": object.get("project_id").cloned().unwrap_or(Value::Null),
                    "sensitivity": object.get("sensitivity").cloned().unwrap_or(Value::Null),
                    "visibility": object.get("visibility").cloned().unwrap_or(Value::Null),
                    "updated_at_ms": object.get("updated_at_ms").cloned().unwrap_or(Value::Null),
                    "version": object.get("version").cloned().unwrap_or(Value::Null),
                    "content_included": false,
                }));
            }
        }
    }
    refs
}

fn first_public_token(value: &Value, keys: &[&str]) -> Option<String> {
    keys.iter()
        .find_map(|key| optional_public_token(value, key))
}

fn gateway_memory_chunk_to_json(chunk: &GatewayMemoryChunk, max_chars: usize) -> Value {
    json!({
        "ref": gateway_memory_object_ref(chunk),
        "chunk_ref": gateway_memory_chunk_ref(chunk),
        "chunk_id": &chunk.chunk_id,
        "chunk_identity_schema": "xhub.memory.object_chunk_identity.v1",
        "chunk_start_line": chunk.chunk_start_line,
        "chunk_end_line": chunk.chunk_end_line,
        "memory_id": &chunk.memory_id,
        "scope": &chunk.scope,
        "owner_id": &chunk.owner_id,
        "project_id": chunk.project_id.as_deref(),
        "agent_id": chunk.agent_id.as_deref(),
        "source_kind": &chunk.source_kind,
        "layer": &chunk.layer,
        "title": &chunk.title,
        "text": gateway_truncate_text(&chunk.text, max_chars),
        "summary": &chunk.summary,
        "sensitivity": &chunk.sensitivity,
        "visibility": &chunk.visibility,
        "updated_at_ms": chunk.updated_at_ms,
        "version": chunk.version,
    })
}

fn gateway_context_text(chunks: &[GatewayMemoryChunk], max_chars: usize) -> String {
    let mut out = String::new();
    let mut current_layer = String::new();
    for chunk in chunks {
        if chunk.layer != current_layer {
            if !out.is_empty() {
                out.push('\n');
            }
            current_layer = chunk.layer.clone();
            let _ = writeln!(&mut out, "## {}", current_layer);
        }
        let text = gateway_truncate_text(&chunk.text, max_chars);
        let _ = writeln!(
            &mut out,
            "- [{}] {}: {}",
            chunk.source_kind, chunk.title, text
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

fn value_u64(value: &Value, key: &str) -> Option<u64> {
    match value.get(key) {
        Some(Value::Number(value)) => value.as_u64(),
        Some(Value::String(value)) => value.trim().parse::<u64>().ok(),
        _ => None,
    }
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

fn stable_fnv1a64_hex(value: &str) -> String {
    let mut hash = 0xcbf29ce484222325_u64;
    for byte in value.as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    format!("{hash:016x}")
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

fn query_i64_optional(query: &str, key: &str) -> Result<Option<i64>, String> {
    match query_param(query, key) {
        Some(value) if !value.trim().is_empty() => value
            .trim()
            .parse::<i64>()
            .map(Some)
            .map_err(|_| format!("invalid query parameter: {key}")),
        _ => Ok(None),
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

fn env_string_or_default(key: &str, fallback: &str) -> String {
    env::var(key)
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| fallback.to_string())
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

    fn optional_u64(&self, key: &str) -> Result<Option<u64>, String> {
        match self.optional(key) {
            Some(value) => value
                .parse::<u64>()
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

    fn age_memory_object_for_test(config: &HubConfig, memory_id: &str, age_ms: i64) {
        let mut object = read_memory_object(&config.db_path, memory_id)
            .expect("read memory object")
            .expect("memory object exists");
        let before_json = memory_object_to_json(&object).to_string();
        let original_version = object.version;
        let now = now_ms_i64();
        let past = now.saturating_sub(age_ms);
        object.created_at_ms = past;
        object.updated_at_ms = past;
        object.last_accessed_at_ms = past;
        object.version = object.version.saturating_add(1);
        let after_json = memory_object_to_json(&object).to_string();
        let event = MemoryEventRecord {
            event_id: next_memory_event_id(),
            memory_id: memory_id.to_string(),
            operation: "test_age".to_string(),
            actor: "rust_hub_test".to_string(),
            reason: "age_memory_object_for_test".to_string(),
            before_version: Some(original_version),
            after_version: Some(object.version),
            before_json: Some(before_json),
            after_json: Some(after_json),
            policy_decision: "allow".to_string(),
            deny_code: String::new(),
            audit_ref: "memory-writeback-maintenance-test-age".to_string(),
            created_at_ms: now,
        };
        update_memory_object_with_event(&config.db_path, &object, &event).expect("age object");
    }

    fn create_candidate_for_test(
        config: &HubConfig,
        memory_id: &str,
        project_id: &str,
        source_kind: &str,
        layer: &str,
        text: &str,
    ) {
        let body = json!({
            "memory_id": memory_id,
            "requester_role": "tool",
            "use_mode": "tool_plan",
            "scope": "project",
            "owner_id": project_id,
            "project_id": project_id,
            "source_kind": source_kind,
            "layer": layer,
            "title": "Candidate",
            "text": text,
            "audit_ref": "candidate-maintenance-test",
        })
        .to_string();
        let (status, raw) = writeback_candidates_http_json(
            config,
            "/memory/writeback/candidates",
            "POST",
            "",
            &body,
        );
        assert_eq!(status, "200 OK", "{raw}");
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
            results[0]["chunk_identity_schema"],
            "xhub.memory.object_chunk_identity.v1"
        );
        assert!(results[0]["chunk_id"]
            .as_str()
            .unwrap()
            .starts_with("object-1-"));
        assert!(results[0]["chunk_ref"]
            .as_str()
            .unwrap()
            .starts_with("memory://rust/object/mem_hybrid_decision#object-1-"));
        assert!(results[0]["chunk_end_line"].as_u64().unwrap() >= 1);
        assert_eq!(
            results[0]["explain"]["policy_filter"],
            "project_active_non_secret"
        );
        assert_eq!(results[0]["explain"]["properties"]["has_decision"], true);
        assert!(
            results[0]["explain"]["content_hash"]
                .as_str()
                .unwrap()
                .len()
                >= 16
        );
        assert!(results[0]["explain"]["bm25_score"].as_f64().unwrap() > 0.0);
        assert_eq!(
            value["retrieval_trace"]["schema_version"],
            "xhub.memory.retrieval_trace.v1"
        );
        assert_eq!(
            value["retrieval_engine"]["chunk_identity_schema"],
            "xhub.memory.object_chunk_identity.v1"
        );
        assert_eq!(
            value["retrieval_trace"]["selected"][0]["memory_id"],
            "mem_hybrid_decision"
        );
        assert_eq!(
            value["retrieval_trace"]["selected"][0]["chunk_ref"],
            results[0]["chunk_ref"]
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
    fn memory_object_hybrid_retrieval_returns_long_object_chunk_ref() {
        let config = test_config("object_hybrid_chunk_ref");
        let text = (0..52)
            .map(|idx| {
                if idx == 31 {
                    "Line 31: Blocker: spectral websocket regression requires reviewer chunk expansion.".to_string()
                } else {
                    format!("Line {idx}: routine context for chunked retrieval fixture and stable indexing.")
                }
            })
            .collect::<Vec<_>>()
            .join("\n");
        let body = json!({
            "memory_id": "mem_hybrid_chunked",
            "requester_role": "chat",
            "use_mode": "project_chat",
            "scope": "project",
            "owner_id": "project-chunked",
            "project_id": "project-chunked",
            "source_kind": "blocker",
            "layer": "l2_observations",
            "title": "Chunked blocker object",
            "text": text,
            "audit_ref": "chunk-ref-test",
        })
        .to_string();
        create_memory_object_json_from_body(&config, &body).expect("create chunked object");

        let mut request = MemoryRetrievalRequest::with_defaults(config.root_dir.join("memory"));
        request.scope = "project".to_string();
        request.project_id = "project-chunked".to_string();
        request.query = "spectral websocket regression reviewer expansion".to_string();
        request.explain = true;
        let raw = retrieve_json_from_request_with_config(&config, request).expect("retrieve chunk");
        let value: Value = serde_json::from_str(&raw).expect("json");
        let first = &value["results"][0];
        assert_eq!(first["memory_id"], "mem_hybrid_chunked");
        assert_eq!(
            first["chunk_identity_schema"],
            "xhub.memory.object_chunk_identity.v1"
        );
        assert!(first["chunk_ref"]
            .as_str()
            .unwrap()
            .starts_with("memory://rust/object/mem_hybrid_chunked#object-"));
        assert!(first["chunk_start_line"].as_u64().unwrap() > 1);
        assert!(first["snippet"]
            .as_str()
            .unwrap()
            .contains("spectral websocket regression"));
        assert_eq!(
            value["retrieval_trace"]["selected"][0]["chunk_ref"],
            first["chunk_ref"]
        );

        let mut expand = MemoryRetrievalRequest::with_defaults(config.root_dir.join("memory"));
        expand.scope = "project".to_string();
        expand.project_id = "project-chunked".to_string();
        expand.retrieval_kind = "get_ref".to_string();
        expand.explicit_refs = vec![first["chunk_ref"].as_str().unwrap().to_string()];
        let raw = retrieve_json_from_request_with_config(&config, expand).expect("expand chunk");
        let expanded: Value = serde_json::from_str(&raw).expect("expanded json");
        let expanded_results = expanded["results"].as_array().expect("expanded results");
        assert_eq!(expanded_results.len(), 1);
        assert_eq!(expanded_results[0]["chunk_ref"], first["chunk_ref"]);

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
        let selected_chunk_ref = results[0]["chunk_ref"].as_str().unwrap().to_string();
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
        assert_eq!(
            value["retrieval_trace"]["omitted_reason_counts"]["layer_filter"],
            1
        );
        assert_eq!(
            value["retrieval_engine"]["omitted_reason_counts"]["layer_filter"],
            1
        );

        let mut get_ref = MemoryRetrievalRequest::with_defaults(config.root_dir.join("memory"));
        get_ref.scope = "project".to_string();
        get_ref.project_id = "project-filter".to_string();
        get_ref.retrieval_kind = "get_ref".to_string();
        get_ref.explicit_refs = vec![selected_chunk_ref.clone()];
        let raw = retrieve_json_from_request_with_config(&config, get_ref).expect("get ref");
        let value: Value = serde_json::from_str(&raw).expect("json");
        let results = value["results"].as_array().expect("results");
        assert_eq!(results.len(), 1);
        assert_eq!(results[0]["memory_id"], "mem_filter_next");
        assert_eq!(results[0]["chunk_ref"], selected_chunk_ref);

        let mut legacy_get_ref =
            MemoryRetrievalRequest::with_defaults(config.root_dir.join("memory"));
        legacy_get_ref.scope = "project".to_string();
        legacy_get_ref.project_id = "project-filter".to_string();
        legacy_get_ref.retrieval_kind = "get_ref".to_string();
        legacy_get_ref.explicit_refs = vec!["memory://rust/object/mem_filter_goal".to_string()];
        let raw = retrieve_json_from_request_with_config(&config, legacy_get_ref)
            .expect("legacy get ref");
        let value: Value = serde_json::from_str(&raw).expect("legacy json");
        let results = value["results"].as_array().expect("legacy results");
        assert_eq!(results.len(), 1);
        assert_eq!(results[0]["memory_id"], "mem_filter_goal");
        assert!(results[0]["chunk_ref"]
            .as_str()
            .unwrap()
            .starts_with("memory://rust/object/mem_filter_goal#object-1-"));
        assert!(selected_chunk_ref.starts_with("memory://rust/object/mem_filter_next#object-1-"));

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
    fn memory_user_reveal_grant_issue_evaluate_revoke_roundtrip() {
        let config = test_config("user_reveal_grant");
        let body = json!({
            "actor": "xt_swift_shell",
            "requester_role": "supervisor",
            "use_mode": "assistant_user_memory_inspector",
            "scope": "user",
            "surface": "assistant_user_memory_inspector",
            "ttl_ms": 60000,
            "now_ms": 1000,
            "audit_ref": "assistant-user-inspector-test",
        })
        .to_string();
        let (status, raw) = user_reveal_grant_http_json(
            &config,
            "/memory/user-reveal-grant/issue",
            "POST",
            "",
            &body,
        );
        assert_eq!(status, "200 OK", "{raw}");
        let issued: Value = serde_json::from_str(&raw).expect("issued json");
        assert_eq!(issued["schema_version"], MEMORY_USER_REVEAL_GRANT_SCHEMA);
        assert_eq!(issued["ok"], true);
        assert_eq!(issued["status"], "granted");
        assert_eq!(issued["scope"], "user");
        assert_eq!(issued["surface"], MEMORY_USER_REVEAL_GRANT_SURFACE);
        assert_eq!(issued["content_included"], false);
        assert_eq!(issued["memory_ids_included"], false);
        assert_eq!(issued["project_coder_allowed"], false);
        assert_eq!(issued["model_context_authority"], false);
        assert_eq!(issued["production_authority_change"], false);
        assert!(issued["grant_id"]
            .as_str()
            .unwrap_or_default()
            .starts_with("user_reveal_"));

        let grant_id = issued["grant_id"].as_str().expect("grant id");
        let evaluate = json!({
            "grant_id": grant_id,
            "scope": "user",
            "surface": "assistant_user_memory_inspector",
            "now_ms": 2000,
        })
        .to_string();
        let (status, raw) = user_reveal_grant_http_json(
            &config,
            "/memory/user-reveal-grant/evaluate",
            "POST",
            "",
            &evaluate,
        );
        assert_eq!(status, "200 OK", "{raw}");
        let evaluated: Value = serde_json::from_str(&raw).expect("evaluated json");
        assert_eq!(evaluated["ok"], true);
        assert_eq!(evaluated["status"], "granted");
        assert_eq!(evaluated["grant_id"], grant_id);

        let revoke = json!({
            "grant_id": grant_id,
            "actor": "xt_swift_shell",
            "now_ms": 3000,
        })
        .to_string();
        let (status, raw) = user_reveal_grant_http_json(
            &config,
            "/memory/user-reveal-grant/revoke",
            "POST",
            "",
            &revoke,
        );
        assert_eq!(status, "200 OK", "{raw}");
        let revoked: Value = serde_json::from_str(&raw).expect("revoked json");
        assert_eq!(revoked["ok"], true);
        assert_eq!(revoked["status"], "revoked");
        assert_eq!(revoked["revoked_at_ms"], 3000);

        let (status, raw) = user_reveal_grant_http_json(
            &config,
            "/memory/user-reveal-grant/evaluate",
            "POST",
            "",
            &evaluate,
        );
        assert_eq!(status, "403 Forbidden", "{raw}");
        let denied: Value = serde_json::from_str(&raw).expect("denied json");
        assert_eq!(denied["ok"], false);
        assert_eq!(denied["reason_code"], "memory_user_reveal_grant_not_active");

        let _ = fs::remove_dir_all(config.root_dir);
    }

    #[test]
    fn memory_user_reveal_grant_expired_evaluate_denies() {
        let config = test_config("user_reveal_grant_expired");
        let body = json!({
            "actor": "xt_swift_shell",
            "requester_role": "supervisor",
            "use_mode": "assistant_user_memory_inspector",
            "scope": "user",
            "surface": "assistant_user_memory_inspector",
            "ttl_ms": 1000,
            "now_ms": 1000,
        })
        .to_string();
        let (status, raw) = user_reveal_grant_http_json(
            &config,
            "/memory/user-reveal-grant/issue",
            "POST",
            "",
            &body,
        );
        assert_eq!(status, "200 OK", "{raw}");
        let issued: Value = serde_json::from_str(&raw).expect("issued json");
        let grant_id = issued["grant_id"].as_str().expect("grant id");
        let evaluate = json!({
            "grant_id": grant_id,
            "scope": "user",
            "surface": "assistant_user_memory_inspector",
            "now_ms": 2500,
        })
        .to_string();
        let (status, raw) = user_reveal_grant_http_json(
            &config,
            "/memory/user-reveal-grant/evaluate",
            "POST",
            "",
            &evaluate,
        );
        assert_eq!(status, "403 Forbidden", "{raw}");
        let expired: Value = serde_json::from_str(&raw).expect("expired json");
        assert_eq!(expired["ok"], false);
        assert_eq!(expired["status"], "expired");
        assert_eq!(expired["reason_code"], "memory_user_reveal_grant_expired");

        let _ = fs::remove_dir_all(config.root_dir);
    }

    #[test]
    fn memory_user_reveal_grant_denies_project_coder() {
        let config = test_config("user_reveal_grant_coder");
        let body = json!({
            "actor": "xt_swift_shell",
            "requester_role": "coder",
            "use_mode": "project_chat",
            "scope": "user",
            "surface": "assistant_user_memory_inspector",
            "ttl_ms": 60000,
            "now_ms": 1000,
        })
        .to_string();
        let (status, raw) = user_reveal_grant_http_json(
            &config,
            "/memory/user-reveal-grant/issue",
            "POST",
            "",
            &body,
        );
        assert_eq!(status, "403 Forbidden", "{raw}");
        let denied: Value = serde_json::from_str(&raw).expect("denied json");
        assert_eq!(denied["ok"], false);
        assert_eq!(
            denied["reason_code"],
            "memory_user_reveal_project_coder_denied"
        );
        assert_eq!(denied["content_included"], false);
        assert_eq!(denied["memory_ids_included"], false);
        assert_eq!(denied["project_coder_allowed"], false);
        assert_eq!(denied["production_authority_change"], false);

        let _ = fs::remove_dir_all(config.root_dir);
    }

    #[test]
    fn memory_object_http_mutation_gate_archives_deletes_and_pins() {
        let config = test_config("objects_mutation_gate");
        let body = json!({
            "memory_id": "mem_object_mutation_gate",
            "requester_role": "tool",
            "use_mode": "tool_plan",
            "scope": "project",
            "owner_id": "project-mutation",
            "project_id": "project-mutation",
            "source_kind": "decision_track",
            "layer": "l1_canonical",
            "title": "Mutable decision",
            "text": "Decision: object mutations must be Rust-owned and evented.",
            "audit_ref": "mutation-gate-create",
        })
        .to_string();
        let (status, _) = object_collection_http_json(&config, "POST", "", &body);
        assert_eq!(status, "200 OK");

        let (status, raw) = object_item_http_json(
            &config,
            "/memory/objects/mem_object_mutation_gate/pin",
            "POST",
            "",
            r#"{"actor":"tester","audit_ref":"mutation-pin"}"#,
        );
        assert_eq!(status, "200 OK");
        let pinned: Value = serde_json::from_str(&raw).expect("pin json");
        assert_eq!(pinned["schema_version"], MEMORY_OBJECT_MUTATION_SCHEMA);
        assert_eq!(pinned["mutation"]["operation"], "pin");
        assert_eq!(pinned["object"]["pinned"], true);
        assert_eq!(pinned["mutation"]["confirmation_required"], false);
        assert_eq!(pinned["mutation"]["confirmed"], true);
        assert_eq!(pinned["mutation"]["confirmation_satisfied"], true);
        assert_eq!(pinned["production_authority_change"], false);

        let (status, raw) = object_item_http_json(
            &config,
            "/memory/objects/mem_object_mutation_gate/archive",
            "POST",
            "",
            r#"{"actor":"tester","audit_ref":"mutation-archive-missing-confirm"}"#,
        );
        assert_eq!(status, "403 Forbidden");
        let missing_confirm: Value = serde_json::from_str(&raw).expect("missing confirmation json");
        assert_eq!(
            missing_confirm["deny_code"],
            "memory_object_confirmation_required"
        );

        let (status, raw) = object_item_http_json(
            &config,
            "/memory/objects/mem_object_mutation_gate/archive",
            "POST",
            "",
            r#"{"actor":"tester","audit_ref":"mutation-archive","confirm_archive":true}"#,
        );
        assert_eq!(status, "200 OK");
        let archived: Value = serde_json::from_str(&raw).expect("archive json");
        assert_eq!(archived["object"]["status"], "archived");
        assert_eq!(archived["object"]["pinned"], false);
        assert_eq!(archived["mutation"]["from_pinned"], true);
        assert_eq!(archived["mutation"]["to_pinned"], false);
        assert_eq!(archived["mutation"]["confirmation_required"], true);
        assert_eq!(archived["mutation"]["confirmed"], true);
        assert_eq!(archived["mutation"]["confirmation_satisfied"], true);
        assert_eq!(
            archived["mutation"]["authority"],
            "rust_memory_object_store"
        );

        let (status, raw) = object_item_http_json(
            &config,
            "/memory/objects/mem_object_mutation_gate/pin",
            "POST",
            "",
            r#"{"actor":"tester","audit_ref":"mutation-pin-archived"}"#,
        );
        assert_eq!(status, "409 Conflict");
        let pin_archived: Value = serde_json::from_str(&raw).expect("pin archived json");
        assert_eq!(
            pin_archived["error_code"],
            "memory_object_status_not_mutable"
        );

        let (status, raw) = object_item_http_json(
            &config,
            "/memory/objects/mem_object_mutation_gate/delete",
            "POST",
            "",
            r#"{"actor":"tester","audit_ref":"mutation-delete","confirmation":"delete"}"#,
        );
        assert_eq!(status, "200 OK");
        let deleted: Value = serde_json::from_str(&raw).expect("delete json");
        assert_eq!(deleted["object"]["status"], "deleted");
        assert_eq!(deleted["mutation"]["delete_mode"], "tombstone");

        let listed_raw =
            list_memory_objects_json(&config, "project_id=project-mutation").expect("list active");
        let listed: Value = serde_json::from_str(&listed_raw).expect("listed json");
        assert_eq!(listed["count"], 0);

        let history_raw =
            memory_object_history_json(&config, "mem_object_mutation_gate", "limit=10")
                .expect("history");
        let history: Value = serde_json::from_str(&history_raw).expect("history json");
        assert_eq!(history["count"], 4);
        assert_eq!(history["events"][0]["operation"], "delete");
        assert_eq!(history["events"][1]["operation"], "archive");

        let readiness_raw =
            readiness_json_from_dir(&config, config.root_dir.join("memory")).expect("readiness");
        let readiness: Value = serde_json::from_str(&readiness_raw).expect("readiness json");
        assert_eq!(
            readiness["object_store"]["mutation_gate"]["schema_version"],
            MEMORY_OBJECT_MUTATION_SCHEMA
        );
        assert_eq!(
            readiness["object_store"]["mutation_gate"]["archive_http"],
            true
        );
        assert_eq!(
            readiness["object_store"]["mutation_gate"]["delete_mode"],
            "tombstone"
        );

        let _ = fs::remove_dir_all(config.root_dir);
    }

    #[test]
    fn memory_object_user_scope_mutation_requires_active_reveal_grant() {
        let config = test_config("objects_user_mutation_reveal_grant");
        let body = json!({
            "memory_id": "mem_user_mutation_gate",
            "requester_role": "supervisor",
            "use_mode": "assistant_user_memory_inspector",
            "scope": "user",
            "owner_id": "user_local",
            "source_kind": "personal_capsule",
            "layer": "l1_canonical",
            "title": "User preference",
            "text": "Preference: keep Assistant/User memory mutation grant-gated.",
            "sensitivity": "private",
            "visibility": "never_export",
            "audit_ref": "user-mutation-gate-create",
        })
        .to_string();
        let (status, _) = object_collection_http_json(&config, "POST", "", &body);
        assert_eq!(status, "200 OK");

        let (status, raw) = object_item_http_json(
            &config,
            "/memory/objects/mem_user_mutation_gate/pin",
            "POST",
            "",
            r#"{"actor":"tester","requester_role":"supervisor","use_mode":"assistant_user_memory_inspector","audit_ref":"user-pin-missing-grant"}"#,
        );
        assert_eq!(status, "403 Forbidden");
        let missing_grant: Value = serde_json::from_str(&raw).expect("missing grant json");
        assert_eq!(
            missing_grant["deny_code"],
            "memory_user_reveal_grant_required"
        );
        assert_eq!(missing_grant["production_authority_change"], false);

        let (status, raw) = user_reveal_grant_http_json(
            &config,
            "/memory/user-reveal-grant/issue",
            "POST",
            "",
            r#"{"requester_role":"supervisor","use_mode":"assistant_user_memory_inspector","scope":"user","surface":"assistant_user_memory_inspector","actor":"tester","audit_ref":"user-mutation-reveal","ttl_ms":300000}"#,
        );
        assert_eq!(status, "200 OK");
        let issued: Value = serde_json::from_str(&raw).expect("issued grant json");
        let grant_id = issued["grant_id"].as_str().expect("grant id");

        let pin_body = format!(
            r#"{{"actor":"tester","requester_role":"supervisor","use_mode":"assistant_user_memory_inspector","audit_ref":"user-pin-with-grant","user_reveal_grant_id":"{}"}}"#,
            grant_id
        );
        let (status, raw) = object_item_http_json(
            &config,
            "/memory/objects/mem_user_mutation_gate/pin",
            "POST",
            "",
            &pin_body,
        );
        assert_eq!(status, "200 OK");
        let pinned: Value = serde_json::from_str(&raw).expect("pinned json");
        assert_eq!(pinned["object"]["scope"], "user");
        assert!(pinned["object"]["project_id"].is_null() || pinned["object"]["project_id"] == "");
        assert_eq!(pinned["object"]["pinned"], true);
        assert_eq!(pinned["mutation"]["authority"], "rust_memory_object_store");
        assert_eq!(pinned["production_authority_change"], false);

        let archive_body = format!(
            r#"{{"actor":"tester","requester_role":"supervisor","use_mode":"assistant_user_memory_inspector","audit_ref":"user-archive-with-grant","user_reveal_grant_id":"{}","confirm_archive":true}}"#,
            grant_id
        );
        let (status, raw) = object_item_http_json(
            &config,
            "/memory/objects/mem_user_mutation_gate/archive",
            "POST",
            "",
            &archive_body,
        );
        assert_eq!(status, "200 OK");
        let archived: Value = serde_json::from_str(&raw).expect("archived json");
        assert_eq!(archived["object"]["status"], "archived");
        assert_eq!(archived["object"]["pinned"], false);
        assert_eq!(archived["mutation"]["confirmation_satisfied"], true);

        let _ = fs::remove_dir_all(config.root_dir);
    }

    #[test]
    fn memory_object_http_mutation_gate_blocks_immutable_objects() {
        let config = test_config("objects_mutation_immutable");
        let body = json!({
            "memory_id": "mem_object_immutable",
            "requester_role": "tool",
            "use_mode": "tool_plan",
            "scope": "project",
            "owner_id": "project-immutable",
            "project_id": "project-immutable",
            "source_kind": "decision_track",
            "layer": "l1_canonical",
            "title": "Immutable decision",
            "text": "Decision: immutable memory cannot be changed by mutation controls.",
            "immutable": true,
            "audit_ref": "immutable-create",
        })
        .to_string();
        let (status, _) = object_collection_http_json(&config, "POST", "", &body);
        assert_eq!(status, "200 OK");

        let (status, raw) = object_item_http_json(
            &config,
            "/memory/objects/mem_object_immutable/archive",
            "POST",
            "",
            r#"{"confirm_archive":true,"audit_ref":"immutable-archive"}"#,
        );
        assert_eq!(status, "403 Forbidden");
        let denied: Value = serde_json::from_str(&raw).expect("immutable deny json");
        assert_eq!(denied["deny_code"], "memory_object_immutable");

        let object = read_memory_object(&config.db_path, "mem_object_immutable")
            .expect("read object")
            .expect("object exists");
        assert_eq!(object.status, "active");
        assert_eq!(object.version, 1);

        let _ = fs::remove_dir_all(config.root_dir);
    }

    #[test]
    fn memory_object_cli_pin_and_archive_use_rust_mutation_gate() {
        let config = test_config("objects_mutation_cli");
        let created_raw = dispatch(
            &config,
            &args(&[
                "object-create",
                "--memory-id",
                "mem_cli_mutation",
                "--requester-role",
                "tool",
                "--use-mode",
                "tool_plan",
                "--scope",
                "project",
                "--owner-id",
                "project-cli-mutation",
                "--project-id",
                "project-cli-mutation",
                "--source-kind",
                "decision_track",
                "--layer",
                "l1_canonical",
                "--title",
                "CLI mutable decision",
                "--text",
                "CLI mutation controls stay inside the Rust memory object store.",
                "--audit-ref",
                "cli-mutation-create",
            ]),
        )
        .expect("create object");
        let created: Value = serde_json::from_str(&created_raw).expect("created json");
        assert_eq!(created["memory_id"], "mem_cli_mutation");

        let pin_raw = dispatch(
            &config,
            &args(&[
                "object-pin",
                "--memory-id",
                "mem_cli_mutation",
                "--actor",
                "tester",
                "--audit-ref",
                "cli-mutation-pin",
            ]),
        )
        .expect("pin object");
        let pinned: Value = serde_json::from_str(&pin_raw).expect("pin json");
        assert_eq!(pinned["schema_version"], MEMORY_OBJECT_MUTATION_SCHEMA);
        assert_eq!(pinned["object"]["pinned"], true);

        let archive_raw = dispatch(
            &config,
            &args(&[
                "object-archive",
                "--memory-id",
                "mem_cli_mutation",
                "--confirm",
                "--actor",
                "tester",
                "--audit-ref",
                "cli-mutation-archive",
            ]),
        )
        .expect("archive object");
        let archived: Value = serde_json::from_str(&archive_raw).expect("archive json");
        assert_eq!(archived["object"]["status"], "archived");

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
        let (status, raw) = writeback_candidates_http_json(
            &config,
            "/memory/writeback/candidates",
            "POST",
            "",
            &body,
        );
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

        let history = read_memory_object_history(&config.db_path, "mem_candidate_approve", 10)
            .expect("history");
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
        let (status, _) = writeback_candidates_http_json(
            &config,
            "/memory/writeback/candidates",
            "POST",
            "",
            &body,
        );
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
        let (status, raw) = writeback_candidates_http_json(
            &config,
            "/memory/writeback/candidates",
            "POST",
            "",
            &body,
        );
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

        let listed_raw =
            list_writeback_candidates_json(&config, "project_id=project-extract&limit=10")
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
    fn memory_writeback_candidate_conflicting_candidate_requires_resolution() {
        let config = test_config("writeback_candidate_conflict");
        let active_body = json!({
            "memory_id": "mem_candidate_conflict_active",
            "requester_role": "chat",
            "use_mode": "project_chat",
            "scope": "project",
            "owner_id": "project-conflict",
            "project_id": "project-conflict",
            "source_kind": "decision_track",
            "layer": "l1_canonical",
            "title": "Active decision",
            "text": "Decision: keep the existing active memory authority.",
            "audit_ref": "candidate-conflict-test",
        })
        .to_string();
        create_memory_object_json_from_body(&config, &active_body).expect("create active object");

        let candidate_body = json!({
            "memory_id": "mem_candidate_conflict_pending",
            "requester_role": "tool",
            "use_mode": "tool_plan",
            "scope": "project",
            "owner_id": "project-conflict",
            "project_id": "project-conflict",
            "source_kind": "decision_track",
            "layer": "l1_canonical",
            "title": "Conflicting candidate",
            "text": "Decision: replace the existing active memory authority.",
            "audit_ref": "candidate-conflict-test",
        })
        .to_string();
        let (status, raw) = writeback_candidates_http_json(
            &config,
            "/memory/writeback/candidates",
            "POST",
            "",
            &candidate_body,
        );
        assert_eq!(status, "200 OK");
        let created: Value = serde_json::from_str(&raw).expect("created json");
        assert!(created["object"]["policy"]["conflict_with"]
            .as_array()
            .unwrap()
            .iter()
            .any(|item| item.as_str() == Some("mem_candidate_conflict_active")));
        assert_eq!(
            created["object"]["policy"]["conflict_resolution_required"],
            true
        );
        let listed =
            list_writeback_candidates_json(&config, "project_id=project-conflict&limit=10")
                .expect("list conflicting candidates");
        let listed: Value = serde_json::from_str(&listed).expect("listed json");
        assert_eq!(
            listed["candidate_diagnostics"]["schema_version"],
            MEMORY_WRITEBACK_CANDIDATE_DIAGNOSTICS_SCHEMA
        );
        assert_eq!(
            listed["candidate_diagnostics"]["conflict_candidate_count"],
            1
        );
        assert_eq!(listed["candidate_diagnostics"]["queue_pressure"], "high");
        assert!(listed["candidate_diagnostics"]["conflict_candidate_ids"]
            .as_array()
            .unwrap()
            .iter()
            .any(|item| item.as_str() == Some("mem_candidate_conflict_pending")));

        let readiness_raw =
            readiness_json_from_dir(&config, config.root_dir.join("memory")).expect("readiness");
        let readiness: Value = serde_json::from_str(&readiness_raw).expect("readiness json");
        assert_eq!(
            readiness["object_store"]["writeback_candidates"]["diagnostics"]
                ["conflict_candidate_count"],
            1
        );

        let approve_body = json!({
            "requester_role": "tool",
            "use_mode": "tool_plan",
            "actor": "reviewer",
            "audit_ref": "candidate-conflict-approve-test",
        })
        .to_string();
        let (status, raw) = writeback_candidates_http_json(
            &config,
            "/memory/writeback/candidates/mem_candidate_conflict_pending/approve",
            "POST",
            "",
            &approve_body,
        );
        assert_eq!(status, "409 Conflict");
        let conflict: Value = serde_json::from_str(&raw).expect("conflict json");
        assert_eq!(
            conflict["error_code"],
            "memory_writeback_candidate_conflict_resolution_required"
        );

        let approve_with_resolution = json!({
            "requester_role": "tool",
            "use_mode": "tool_plan",
            "actor": "reviewer",
            "audit_ref": "candidate-conflict-approve-test",
            "conflict_resolution_reason": "Reviewer accepts this candidate as an intentional replacement decision.",
        })
        .to_string();
        let (status, raw) = writeback_candidates_http_json(
            &config,
            "/memory/writeback/candidates/mem_candidate_conflict_pending/approve",
            "POST",
            "",
            &approve_with_resolution,
        );
        assert_eq!(status, "200 OK");
        let approved: Value = serde_json::from_str(&raw).expect("approved json");
        assert_eq!(approved["status"], "approved");
        assert_eq!(approved["object"]["status"], "active");
        assert_eq!(approved["object"]["policy"]["conflict_resolved"], true);
        assert_eq!(
            approved["transition"]["conflict_resolution"]["resolved"],
            true
        );

        let _ = fs::remove_dir_all(config.root_dir);
    }

    #[test]
    fn memory_writeback_candidate_supersedes_pending_candidate() {
        let config = test_config("writeback_candidate_supersedes");
        create_candidate_for_test(
            &config,
            "mem_candidate_superseded_old",
            "project-supersede",
            "next_step",
            "l3_working_set",
            "Next step: run the old candidate plan.",
        );
        create_candidate_for_test(
            &config,
            "mem_candidate_superseded_new",
            "project-supersede",
            "next_step",
            "l3_working_set",
            "Next step: run the newer candidate plan.",
        );

        let old = read_memory_object(&config.db_path, "mem_candidate_superseded_old")
            .expect("read old")
            .expect("old exists");
        assert_eq!(old.status, "archived");
        let old_policy: Value = serde_json::from_str(&old.policy_json).expect("old policy");
        assert_eq!(old_policy["superseded_by"], "mem_candidate_superseded_new");
        let history =
            read_memory_object_history(&config.db_path, "mem_candidate_superseded_old", 10)
                .expect("history");
        assert_eq!(history[0].operation, "candidate_superseded");

        let new = read_memory_object(&config.db_path, "mem_candidate_superseded_new")
            .expect("read new")
            .expect("new exists");
        assert_eq!(new.status, "candidate");
        let new_policy: Value = serde_json::from_str(&new.policy_json).expect("new policy");
        assert!(new_policy["supersedes"]
            .as_array()
            .unwrap()
            .iter()
            .any(|item| item.as_str() == Some("mem_candidate_superseded_old")));
        assert_eq!(new_policy["candidate_generation"], 2);

        let listed =
            list_writeback_candidates_json(&config, "project_id=project-supersede&limit=10")
                .expect("list superseded candidates");
        let listed: Value = serde_json::from_str(&listed).expect("listed json");
        assert_eq!(
            listed["candidate_diagnostics"]["superseding_candidate_count"],
            1
        );
        assert_eq!(
            listed["candidate_diagnostics"]["archived_superseded_count"],
            1
        );
        assert_eq!(
            listed["candidate_diagnostics"]["superseded_candidate_count"],
            1
        );
        assert_eq!(listed["candidate_diagnostics"]["queue_pressure"], "medium");

        let _ = fs::remove_dir_all(config.root_dir);
    }

    #[test]
    fn memory_writeback_candidate_rejected_candidate_is_not_resurrected_by_supersession() {
        let config = test_config("writeback_candidate_supersede_rejected");
        create_candidate_for_test(
            &config,
            "mem_candidate_rejected_old",
            "project-supersede",
            "next_step",
            "l3_working_set",
            "Next step: rejected candidate should stay rejected.",
        );
        let reject_body = json!({
            "requester_role": "tool",
            "use_mode": "tool_plan",
            "actor": "reviewer",
            "audit_ref": "candidate-rejected-supersession-test",
        })
        .to_string();
        let (status, _) = writeback_candidates_http_json(
            &config,
            "/memory/writeback/candidates/mem_candidate_rejected_old/reject",
            "POST",
            "",
            &reject_body,
        );
        assert_eq!(status, "200 OK");

        create_candidate_for_test(
            &config,
            "mem_candidate_rejected_new",
            "project-supersede",
            "next_step",
            "l3_working_set",
            "Next step: newer candidate should not resurrect rejected memory.",
        );
        let rejected = read_memory_object(&config.db_path, "mem_candidate_rejected_old")
            .expect("read rejected")
            .expect("rejected exists");
        assert_eq!(rejected.status, "rejected");
        let history = read_memory_object_history(&config.db_path, "mem_candidate_rejected_old", 10)
            .expect("history");
        assert_eq!(history[0].operation, "reject");

        let newer = read_memory_object(&config.db_path, "mem_candidate_rejected_new")
            .expect("read newer")
            .expect("newer exists");
        assert_eq!(newer.status, "candidate");

        let _ = fs::remove_dir_all(config.root_dir);
    }

    #[test]
    fn memory_writeback_candidate_maintenance_dry_run_does_not_mutate() {
        let config = test_config("writeback_candidate_maintenance_dry_run");
        create_candidate_for_test(
            &config,
            "mem_candidate_maintenance_dry",
            "project-maintenance",
            "next_step",
            "l3_working_set",
            "Next step: archive stale working-set candidates only after maintenance apply.",
        );
        age_memory_object_for_test(&config, "mem_candidate_maintenance_dry", 5_000);

        let (status, raw) = writeback_candidates_http_json(
            &config,
            "/memory/writeback/candidates/maintenance",
            "POST",
            "project_id=project-maintenance&max_age_ms=1000",
            "",
        );
        assert_eq!(status, "200 OK");
        let value: Value = serde_json::from_str(&raw).expect("maintenance json");
        assert_eq!(
            value["schema_version"],
            MEMORY_WRITEBACK_CANDIDATE_MAINTENANCE_SCHEMA
        );
        assert_eq!(value["dry_run"], true);
        assert_eq!(value["planned_archive_count"], 1);
        assert_eq!(value["archived_count"], 0);
        assert_eq!(value["mutation_count"], 0);
        assert_eq!(value["items"][0]["operation"], "archive");
        assert!(value["items"][0]["event_id"].is_null());

        let object = read_memory_object(&config.db_path, "mem_candidate_maintenance_dry")
            .expect("read candidate")
            .expect("candidate exists");
        assert_eq!(object.status, "candidate");
        let history =
            read_memory_object_history(&config.db_path, "mem_candidate_maintenance_dry", 10)
                .expect("history");
        assert!(history
            .iter()
            .all(|event| event.operation != "candidate_archive"));

        let _ = fs::remove_dir_all(config.root_dir);
    }

    #[test]
    fn memory_writeback_candidate_maintenance_archives_stale_working_set() {
        let config = test_config("writeback_candidate_maintenance_archive");
        create_candidate_for_test(
            &config,
            "mem_candidate_maintenance_archive",
            "project-maintenance",
            "current_state",
            "l3_working_set",
            "Current state: stale working-set candidates should leave the pending queue.",
        );
        age_memory_object_for_test(&config, "mem_candidate_maintenance_archive", 5_000);

        let body = json!({
            "apply": true,
            "project_id": "project-maintenance",
            "max_age_ms": 1000,
            "actor": "rust_hub_test",
            "audit_ref": "candidate-maintenance-archive-test",
        })
        .to_string();
        let (status, raw) = writeback_candidates_http_json(
            &config,
            "/memory/writeback/candidates/maintenance",
            "POST",
            "",
            &body,
        );
        assert_eq!(status, "200 OK");
        let value: Value = serde_json::from_str(&raw).expect("maintenance json");
        assert_eq!(value["applied"], true);
        assert_eq!(value["archived_count"], 1);
        assert_eq!(value["mutation_count"], 1);
        assert_eq!(value["items"][0]["operation"], "archive");
        assert_eq!(value["items"][0]["planned_status"], "archived");
        assert!(value["items"][0]["event_id"].as_str().is_some());

        let object = read_memory_object(&config.db_path, "mem_candidate_maintenance_archive")
            .expect("read archived")
            .expect("archived exists");
        assert_eq!(object.status, "archived");
        let policy: Value = serde_json::from_str(&object.policy_json).expect("policy json");
        assert_eq!(
            policy["last_writeback_candidate_maintenance"]["operation"],
            "archive"
        );
        assert_eq!(
            policy["last_writeback_candidate_maintenance"]["production_authority_change"],
            false
        );
        let history =
            read_memory_object_history(&config.db_path, "mem_candidate_maintenance_archive", 10)
                .expect("history");
        assert_eq!(history[0].operation, "candidate_archive");

        let listed =
            list_writeback_candidates_json(&config, "project_id=project-maintenance&limit=10")
                .expect("list candidates");
        let listed: Value = serde_json::from_str(&listed).expect("list json");
        assert_eq!(listed["candidate_count"], 0);

        let _ = fs::remove_dir_all(config.root_dir);
    }

    #[test]
    fn memory_writeback_candidate_maintenance_marks_canonical_stale_review_required() {
        let config = test_config("writeback_candidate_maintenance_canonical");
        create_candidate_for_test(
            &config,
            "mem_candidate_maintenance_canonical",
            "project-maintenance",
            "decision_track",
            "l1_canonical",
            "Decision: canonical candidates require explicit review instead of silent archive.",
        );
        age_memory_object_for_test(&config, "mem_candidate_maintenance_canonical", 5_000);

        let (status, raw) = writeback_candidates_http_json(
            &config,
            "/memory/writeback/candidates/maintenance",
            "POST",
            "apply=1&project_id=project-maintenance&max_age_ms=1000",
            "{}",
        );
        assert_eq!(status, "200 OK");
        let value: Value = serde_json::from_str(&raw).expect("maintenance json");
        assert_eq!(value["planned_stale_review_required_count"], 1);
        assert_eq!(value["stale_review_required_count"], 1);
        assert_eq!(value["items"][0]["operation"], "stale_review_required");
        assert_eq!(value["items"][0]["planned_status"], "candidate");

        let object = read_memory_object(&config.db_path, "mem_candidate_maintenance_canonical")
            .expect("read canonical")
            .expect("canonical exists");
        assert_eq!(object.status, "candidate");
        let policy: Value = serde_json::from_str(&object.policy_json).expect("policy json");
        let provenance: Value =
            serde_json::from_str(&object.provenance_json).expect("provenance json");
        assert_eq!(policy["stale_review_required"], true);
        assert_eq!(provenance["stale_review_required"], true);
        assert_eq!(
            policy["last_writeback_candidate_maintenance"]["operation"],
            "stale_review_required"
        );
        let history =
            read_memory_object_history(&config.db_path, "mem_candidate_maintenance_canonical", 10)
                .expect("history");
        assert_eq!(history[0].operation, "candidate_stale_review_required");

        let readiness_raw =
            readiness_json_from_dir(&config, config.root_dir.join("memory")).expect("readiness");
        let readiness: Value = serde_json::from_str(&readiness_raw).expect("readiness json");
        assert_eq!(
            readiness["object_store"]["writeback_candidates"]["candidate_maintenance_http"],
            true
        );
        assert_eq!(
            readiness["object_store"]["writeback_candidates"]["maintenance"]
                ["candidate_maintenance_schema"],
            MEMORY_WRITEBACK_CANDIDATE_MAINTENANCE_SCHEMA
        );
        assert_eq!(
            readiness["object_store"]["writeback_candidates"]["diagnostics"]
                ["stale_review_required_count"],
            1
        );

        let listed =
            list_writeback_candidates_json(&config, "project_id=project-maintenance&limit=10")
                .expect("list stale review candidate");
        let listed: Value = serde_json::from_str(&listed).expect("listed json");
        assert_eq!(
            listed["candidate_diagnostics"]["stale_review_required_count"],
            1
        );
        assert_eq!(listed["candidate_diagnostics"]["queue_pressure"], "high");

        let _ = fs::remove_dir_all(config.root_dir);
    }

    #[test]
    fn memory_writeback_candidate_maintenance_ignores_active_and_rejected() {
        let config = test_config("writeback_candidate_maintenance_ignored");
        create_candidate_for_test(
            &config,
            "mem_candidate_maintenance_active",
            "project-maintenance",
            "next_step",
            "l3_working_set",
            "Next step: active candidates should not be maintained as pending.",
        );
        create_candidate_for_test(
            &config,
            "mem_candidate_maintenance_rejected",
            "project-maintenance",
            "open_question",
            "l2_observations",
            "Next step: rejected candidates should not be maintained as pending.",
        );
        create_candidate_for_test(
            &config,
            "mem_candidate_maintenance_pending",
            "project-maintenance",
            "current_state",
            "l3_working_set",
            "Next step: pending stale candidate should be archived.",
        );
        for memory_id in [
            "mem_candidate_maintenance_active",
            "mem_candidate_maintenance_rejected",
            "mem_candidate_maintenance_pending",
        ] {
            age_memory_object_for_test(&config, memory_id, 5_000);
        }
        let transition_body = json!({
            "requester_role": "tool",
            "use_mode": "tool_plan",
            "actor": "reviewer",
            "audit_ref": "candidate-maintenance-transition-test",
        })
        .to_string();
        let (status, _) = writeback_candidates_http_json(
            &config,
            "/memory/writeback/candidates/mem_candidate_maintenance_active/approve",
            "POST",
            "",
            &transition_body,
        );
        assert_eq!(status, "200 OK");
        let (status, _) = writeback_candidates_http_json(
            &config,
            "/memory/writeback/candidates/mem_candidate_maintenance_rejected/reject",
            "POST",
            "",
            &transition_body,
        );
        assert_eq!(status, "200 OK");

        let (status, raw) = writeback_candidates_http_json(
            &config,
            "/memory/writeback/candidates/maintenance",
            "POST",
            "apply=1&project_id=project-maintenance&max_age_ms=1000",
            "",
        );
        assert_eq!(status, "200 OK");
        let value: Value = serde_json::from_str(&raw).expect("maintenance json");
        assert_eq!(value["candidate_count"], 1);
        assert_eq!(value["archived_count"], 1);

        let active = read_memory_object(&config.db_path, "mem_candidate_maintenance_active")
            .expect("read active")
            .expect("active exists");
        let rejected = read_memory_object(&config.db_path, "mem_candidate_maintenance_rejected")
            .expect("read rejected")
            .expect("rejected exists");
        let pending = read_memory_object(&config.db_path, "mem_candidate_maintenance_pending")
            .expect("read pending")
            .expect("pending exists");
        assert_eq!(active.status, "active");
        assert_eq!(rejected.status, "rejected");
        assert_eq!(pending.status, "archived");

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
        assert_eq!(prepared["serving_profile_id"], "M1_Execute");
        assert_eq!(prepared["selected_profile"], "M1_Execute");
        assert_eq!(prepared["effective_profile"], "M1_Execute");
        assert_eq!(
            prepared["profile_reason"],
            "derived_from_use_mode_project_chat"
        );
        assert_eq!(prepared["object_count"], 2);
        assert_eq!(prepared["selected_count"], 2);
        assert_eq!(prepared["selected_chunk_count"], 2);
        assert_eq!(prepared["index_granularity"], "object_chunk");
        assert_eq!(
            prepared["chunk_identity_schema"],
            "xhub.memory.object_chunk_identity.v1"
        );
        assert_eq!(prepared["chunk_expand_via_get_ref"], true);
        assert!(prepared["index_source"]
            .as_str()
            .unwrap()
            .contains("rust_hub_memory_object"));
        assert_eq!(
            prepared["selected_refs"][0]["chunk_identity_schema"],
            "xhub.memory.object_chunk_identity.v1"
        );
        assert!(prepared["selected_refs"][0]["chunk_ref"]
            .as_str()
            .unwrap()
            .starts_with("memory://rust/object/"));
        assert_eq!(prepared["selected_refs"][0]["content_included"], false);
        assert_eq!(prepared["omitted_reason_counts"]["layer_filter"], 1);
        assert_eq!(prepared["omitted_ref_count"], 1);
        assert_eq!(prepared["omitted_refs"][0]["reason_code"], "layer_filter");
        assert_eq!(prepared["omitted_refs"][0]["content_included"], false);
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
        assert_eq!(
            remote["omitted_reason_counts"]["remote_visibility_filter"],
            1
        );

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
    fn memory_gateway_model_call_plan_wraps_prepare_without_execution() {
        let config = test_config("gateway_model_call_plan");
        let payload = json!({
            "project_canonical_memory": {
                "project_id": "project-model-plan",
                "items": [
                    {
                        "key": "xterminal.project.memory.goal",
                        "value": "Use Rust Memory Gateway as the model-call admission boundary."
                    },
                    {
                        "key": "xterminal.project.memory.next_steps",
                        "value": "Add a non-executing model-call plan before execution cutover."
                    }
                ]
            }
        });
        project_canonical_sync_json_from_value(&config, &payload, true).expect("apply sync");

        let body = json!({
            "request_id": "plan-1",
            "audit_ref": "model-call-plan-test",
            "requester_role": "chat",
            "use_mode": "project_chat",
            "scope": "project",
            "project_id": "project-model-plan",
            "serving_profile_id": "M1_Execute",
            "provider_id": "local",
            "model_id": "test-model",
            "task_kind": "text_generate",
            "prompt": "Summarize the current project direction."
        })
        .to_string();
        let (status, raw) = memory_gateway_model_call_plan_http_json(&config, "POST", &body);
        assert_eq!(status, "200 OK");
        let planned: Value = serde_json::from_str(&raw).expect("model call plan json");
        assert_eq!(
            planned["schema_version"],
            MEMORY_GATEWAY_MODEL_CALL_PLAN_SCHEMA
        );
        assert_eq!(planned["source"], "rust_memory_gateway_model_call_plan");
        assert_eq!(planned["mode"], "plan_only_no_model_call");
        assert_eq!(planned["production_authority_change"], false);
        assert_eq!(planned["would_call_model"], false);
        assert_eq!(planned["model_call_executed"], false);
        assert_eq!(planned["prepare"]["source"], "rust_memory_gateway_prepare");
        assert_eq!(planned["prepare"]["mode"], "prepare_only_no_model_call");
        assert_eq!(
            planned["prepare"]["omitted_reason_counts"].is_object(),
            true
        );
        assert_eq!(planned["memory_context"]["context_text_included"], false);
        assert_eq!(planned["memory_context"]["selected_ref_count"], 2);
        assert_eq!(
            planned["memory_context"]["chunk_identity_schema"],
            "xhub.memory.object_chunk_identity.v1"
        );
        assert_eq!(
            planned["memory_context"]["index_granularity"],
            "object_chunk"
        );
        assert_eq!(planned["memory_context"]["chunk_expand_via_get_ref"], true);
        assert!(planned["memory_context"]["selected_refs"][0]["chunk_ref"]
            .as_str()
            .unwrap()
            .starts_with("memory://rust/object/"));
        assert_eq!(
            planned["memory_context"]["selected_refs"][0]["content_included"],
            false
        );
        assert_eq!(
            planned["prepare"]["selected_refs"][0]["chunk_ref"],
            planned["memory_context"]["selected_refs"][0]["chunk_ref"]
        );
        assert_eq!(planned["model_request"]["provider_id"], "local");
        assert_eq!(planned["model_request"]["model_id"], "test-model");
        assert_eq!(planned["model_request"]["prompt"]["text_included"], false);
        assert!(
            planned["memory_context"]["context_char_count"]
                .as_u64()
                .unwrap()
                > 0
        );
        assert!(!raw.contains("Use Rust Memory Gateway as the model-call admission boundary"));
        assert!(!raw.contains("Summarize the current project direction"));

        let _ = fs::remove_dir_all(config.root_dir);
    }

    #[test]
    fn memory_gateway_model_call_plan_fails_closed_when_execution_requested() {
        let config = test_config("gateway_model_call_execute_denied");
        let body = json!({
            "requester_role": "chat",
            "use_mode": "project_chat",
            "scope": "project",
            "project_id": "project-model-plan",
            "prompt": "Generate an answer.",
            "execute": true
        })
        .to_string();
        let (status, raw) = memory_gateway_model_call_plan_http_json(&config, "POST", &body);
        assert_eq!(status, "403 Forbidden");
        let denied: Value = serde_json::from_str(&raw).expect("denied json");
        assert_eq!(
            denied["error_code"],
            "memory_gateway_model_call_execute_not_enabled"
        );
        assert_eq!(denied["model_call_executed"], false);
        assert_eq!(denied["production_authority_change"], false);

        let _ = fs::remove_dir_all(config.root_dir);
    }

    #[test]
    fn memory_gateway_model_call_execution_gate_reports_blocked_without_execution() {
        let config = test_config("gateway_model_call_execution_gate");
        let payload = json!({
            "project_canonical_memory": {
                "project_id": "project-execution-gate",
                "items": [
                    {
                        "key": "xterminal.project.memory.goal",
                        "value": "Keep model-call execution behind a Rust admission gate."
                    }
                ]
            }
        });
        project_canonical_sync_json_from_value(&config, &payload, true).expect("apply sync");

        let body = json!({
            "request_id": "gate-1",
            "audit_ref": "model-call-execution-gate-test",
            "requester_role": "chat",
            "use_mode": "project_chat",
            "scope": "project",
            "project_id": "project-execution-gate",
            "serving_profile_id": "M1_Execute",
            "provider_id": "local",
            "model_id": "test-model",
            "task_kind": "text_generate",
            "prompt": "Use the project memory to draft a response.",
            "execute": true
        })
        .to_string();
        let (status, raw) =
            memory_gateway_model_call_execution_gate_http_json(&config, "POST", &body);
        assert_eq!(status, "200 OK");
        let gate: Value = serde_json::from_str(&raw).expect("execution gate json");
        assert_eq!(
            gate["schema_version"],
            MEMORY_GATEWAY_MODEL_CALL_EXECUTION_GATE_SCHEMA
        );
        assert_eq!(
            gate["source"],
            "rust_memory_gateway_model_call_execution_gate"
        );
        assert_eq!(gate["mode"], "gate_only_no_model_call");
        assert_eq!(gate["execution_requested"], true);
        assert_eq!(gate["ready_for_execution"], false);
        assert_eq!(gate["execution_admission_authority_in_rust"], false);
        assert_eq!(gate["execution_admission_ready"], false);
        assert_eq!(gate["would_call_model"], false);
        assert_eq!(gate["model_call_executed"], false);
        assert_eq!(gate["production_authority_change"], false);
        assert_eq!(
            gate["blockers"]
                .as_array()
                .unwrap()
                .contains(&json!("memory_gateway_model_call_execution_not_enabled")),
            true
        );
        assert_eq!(
            gate["plan"]["source"],
            "rust_memory_gateway_model_call_plan"
        );
        assert_eq!(gate["plan"]["mode"], "plan_only_no_model_call");
        assert_eq!(gate["plan"]["context_text_included"], false);
        assert_eq!(gate["plan"]["prompt_text_included"], false);
        assert_eq!(gate["guards"]["local_ml_execute_http_not_invoked"], true);
        assert!(!raw.contains("Keep model-call execution behind a Rust admission gate"));
        assert!(!raw.contains("Use the project memory to draft a response"));

        let _ = fs::remove_dir_all(config.root_dir);
    }

    #[test]
    fn memory_gateway_model_call_execution_gate_admits_when_explicitly_enabled() {
        let config = test_config("gateway_model_call_execution_admission");
        let payload = json!({
            "project_canonical_memory": {
                "project_id": "project-execution-admission",
                "items": [
                    {
                        "key": "xterminal.project.memory.goal",
                        "value": "Keep execution admission in Rust without leaking model-call content."
                    }
                ]
            }
        });
        project_canonical_sync_json_from_value(&config, &payload, true).expect("apply sync");

        let body = json!({
            "request_id": "gate-admit-1",
            "audit_ref": "model-call-execution-admission-test",
            "requester_role": "chat",
            "use_mode": "project_chat",
            "scope": "project",
            "project_id": "project-execution-admission",
            "serving_profile_id": "M1_Execute",
            "provider_id": "local",
            "model_id": "test-model",
            "task_kind": "text_generate",
            "prompt": "Use the project memory to draft an admitted response.",
            "execute": true,
            "__test_memory_gateway_model_call_execution_admission": true,
            "__test_provider_route_authority_in_rust": true,
            "__test_model_route_authority_in_rust": true
        })
        .to_string();
        let (status, raw) =
            memory_gateway_model_call_execution_gate_http_json(&config, "POST", &body);
        assert_eq!(status, "200 OK");
        let gate: Value = serde_json::from_str(&raw).expect("execution gate json");
        assert_eq!(
            gate["schema_version"],
            MEMORY_GATEWAY_MODEL_CALL_EXECUTION_GATE_SCHEMA
        );
        assert_eq!(gate["status"], "admitted");
        assert_eq!(gate["mode"], "execution_admission_no_model_call");
        assert_eq!(gate["authority"], "rust_memory_gateway_execution_admission");
        assert_eq!(gate["execution_admission_authority_in_rust"], true);
        assert_eq!(gate["execution_admission_ready"], true);
        assert_eq!(gate["ready_for_execution"], true);
        assert_eq!(gate["execution_authority_in_rust"], false);
        assert_eq!(gate["execution_enabled"], false);
        assert_eq!(gate["would_call_model"], false);
        assert_eq!(gate["model_call_executed"], false);
        assert_eq!(gate["blockers"].as_array().unwrap().len(), 0);
        assert_eq!(
            gate["plan"]["source"],
            "rust_memory_gateway_model_call_fast_execution_summary"
        );
        assert_eq!(gate["plan"]["fast_execution_gate"], true);
        assert_eq!(gate["plan"]["context_text_included"], false);
        assert_eq!(gate["plan"]["prompt_text_included"], false);
        assert_eq!(
            gate["route_authority"]["provider_route_authority_in_rust"],
            true
        );
        assert_eq!(
            gate["route_authority"]["model_route_authority_in_rust"],
            true
        );
        assert_eq!(gate["guards"]["local_ml_execute_http_not_invoked"], true);
        assert_eq!(gate["guards"]["fast_execution_gate"], true);
        assert!(!raw.contains("Keep execution admission in Rust"));
        assert!(!raw.contains("Use the project memory to draft an admitted response"));

        let _ = fs::remove_dir_all(config.root_dir);
    }

    #[test]
    fn memory_gateway_model_call_execution_gate_requires_route_authority_for_admission() {
        let config = test_config("gateway_model_call_execution_admission_route");
        let body = json!({
            "requester_role": "chat",
            "use_mode": "project_chat",
            "scope": "project",
            "project_id": "project-execution-admission-route",
            "provider_id": "local",
            "model_id": "test-model",
            "prompt": "Draft without route authority.",
            "execute": true,
            "__test_memory_gateway_model_call_execution_admission": true
        })
        .to_string();
        let (status, raw) =
            memory_gateway_model_call_execution_gate_http_json(&config, "POST", &body);
        assert_eq!(status, "200 OK");
        let gate: Value = serde_json::from_str(&raw).expect("execution gate json");
        assert_eq!(gate["status"], "blocked");
        assert_eq!(gate["ready_for_execution"], false);
        assert_eq!(gate["execution_admission_authority_in_rust"], true);
        assert!(gate["blockers"]
            .as_array()
            .unwrap()
            .contains(&json!("provider_route_authority_not_in_rust")));
        assert!(gate["blockers"]
            .as_array()
            .unwrap()
            .contains(&json!("model_route_authority_not_in_rust")));
        assert_eq!(gate["model_call_executed"], false);
        assert!(!raw.contains("Draft without route authority"));

        let _ = fs::remove_dir_all(config.root_dir);
    }

    #[test]
    fn memory_gateway_model_call_execute_defaults_to_guarded_no_model_call() {
        let config = test_config("gateway_model_call_execute_guarded");
        let body = json!({
            "request_id": "execute-guarded-1",
            "requester_role": "chat",
            "use_mode": "project_chat",
            "scope": "project",
            "project_id": "project-execute-guarded",
            "provider_id": "local",
            "model_id": "test-model",
            "prompt": "Do not execute by default.",
            "execute": true
        })
        .to_string();
        let (status, raw) = memory_gateway_model_call_execute_http_json(&config, "POST", &body);
        assert_eq!(status, "200 OK");
        let execute: Value = serde_json::from_str(&raw).expect("execute json");
        assert_eq!(
            execute["schema_version"],
            MEMORY_GATEWAY_MODEL_CALL_EXECUTE_SCHEMA
        );
        assert_eq!(execute["source"], "rust_memory_gateway_model_call_execute");
        assert_eq!(execute["status"], "blocked");
        assert_eq!(execute["mode"], "execute_guard_no_model_call");
        assert_eq!(execute["would_call_model"], false);
        assert_eq!(execute["model_call_invoked"], false);
        assert_eq!(execute["model_call_executed"], false);
        assert!(execute["blockers"].as_array().unwrap().contains(&json!(
            "memory_gateway_model_call_local_executor_not_enabled"
        )));
        assert_eq!(execute["guards"]["local_ml_execute_http_invoked"], false);
        assert!(!raw.contains("Do not execute by default"));

        let _ = fs::remove_dir_all(config.root_dir);
    }

    #[test]
    fn memory_gateway_model_call_execute_blocks_when_local_ml_not_ready() {
        let config = test_config("gateway_model_call_execute_local_ml_not_ready");
        let body = json!({
            "request_id": "execute-local-ml-not-ready-1",
            "requester_role": "chat",
            "use_mode": "project_chat",
            "scope": "project",
            "project_id": "project-execute-local-ml-not-ready",
            "provider_id": "mlx",
            "model_id": "test-model",
            "prompt": "Do not spawn local ML when readiness is false.",
            "execute": true,
            "__test_memory_gateway_model_call_execution_admission": true,
            "__test_provider_route_authority_in_rust": true,
            "__test_model_route_authority_in_rust": true,
            "__test_local_executor_enabled": true,
            "__test_local_executor_apply_enabled": true
        })
        .to_string();
        let (status, raw) = memory_gateway_model_call_execute_http_json(&config, "POST", &body);
        assert_eq!(status, "200 OK");
        let execute: Value = serde_json::from_str(&raw).expect("execute json");
        assert_eq!(execute["status"], "blocked");
        assert_eq!(execute["ready_for_execution"], false);
        assert_eq!(execute["model_call_invoked"], false);
        assert!(execute["blockers"]
            .as_array()
            .unwrap()
            .contains(&json!("local_ml_execution_not_ready")));
        assert_eq!(execute["guards"]["local_ml_execute_http_invoked"], false);
        assert!(!raw.contains("Do not spawn local ML"));

        let _ = fs::remove_dir_all(config.root_dir);
    }

    #[test]
    fn memory_gateway_model_call_execute_can_call_guarded_local_executor() {
        let config = test_config("gateway_model_call_execute_fake_local");
        let payload = json!({
            "project_canonical_memory": {
                "project_id": "project-execute-fake-local",
                "items": [
                    {
                        "key": "xterminal.project.memory.goal",
                        "value": "Apply memory context before guarded local execution."
                    }
                ]
            }
        });
        project_canonical_sync_json_from_value(&config, &payload, true).expect("apply sync");

        let body = json!({
            "request_id": "execute-fake-local-1",
            "requester_role": "chat",
            "use_mode": "project_chat",
            "scope": "project",
            "project_id": "project-execute-fake-local",
            "provider_id": "mlx",
            "model_id": "test-model",
            "prompt": "Use memory and produce a short answer.",
            "execute": true,
            "__test_memory_gateway_model_call_execution_admission": true,
            "__test_provider_route_authority_in_rust": true,
            "__test_model_route_authority_in_rust": true,
            "__test_local_executor_enabled": true,
            "__test_local_executor_apply_enabled": true,
            "__test_fake_local_ml_execute_ok": true
        })
        .to_string();
        let (status, raw) = memory_gateway_model_call_execute_http_json(&config, "POST", &body);
        assert_eq!(status, "200 OK");
        let execute: Value = serde_json::from_str(&raw).expect("execute json");
        assert_eq!(execute["status"], "executed");
        assert_eq!(execute["mode"], "local_ml_execute");
        assert_eq!(execute["execution_authority_in_rust"], true);
        assert_eq!(execute["ready_for_execution"], true);
        assert_eq!(execute["would_call_model"], true);
        assert_eq!(execute["model_call_invoked"], true);
        assert_eq!(execute["model_call_executed"], true);
        assert_eq!(execute["local_ml"]["result_text_included"], true);
        assert_eq!(
            execute["execution_result"]["result"]["text"],
            "Synthetic gateway execution output."
        );
        assert!(execute["execution_result"]["result"]
            .get("request")
            .is_none());
        assert!(!raw.contains("Use memory and produce"));
        assert!(!raw.contains("Apply memory context before guarded local execution"));
        assert!(!raw.contains("redact me"));

        let _ = fs::remove_dir_all(config.root_dir);
    }

    #[test]
    fn memory_gateway_model_call_execute_canary_only_blocks_non_canary_request() {
        let config = test_config("gateway_model_call_execute_canary_block");
        let body = json!({
            "request_id": "execute-normal-1",
            "audit_ref": "normal-execute:1",
            "requester_role": "chat",
            "use_mode": "project_chat",
            "scope": "project",
            "project_id": "ordinary-project",
            "provider_id": "mlx",
            "model_id": "test-model",
            "prompt": "This must not pass the canary gate.",
            "execute": true,
            "__test_memory_gateway_model_call_execution_admission": true,
            "__test_provider_route_authority_in_rust": true,
            "__test_model_route_authority_in_rust": true,
            "__test_local_executor_enabled": true,
            "__test_local_executor_apply_enabled": true,
            "__test_model_call_execute_canary_only": true,
            "__test_fake_local_ml_execute_ok": true
        })
        .to_string();
        let (status, raw) = memory_gateway_model_call_execute_http_json(&config, "POST", &body);
        assert_eq!(status, "200 OK");
        let execute: Value = serde_json::from_str(&raw).expect("execute json");
        assert_eq!(execute["status"], "blocked");
        assert_eq!(execute["model_call_invoked"], false);
        assert!(execute["blockers"].as_array().unwrap().contains(&json!(
            "memory_gateway_model_call_execute_canary_scope_mismatch"
        )));
        assert_eq!(execute["executor"]["canary_only"], true);
        assert_eq!(execute["executor"]["canary_scope_allowed"], false);
        assert!(!raw.contains("This must not pass the canary gate"));

        let _ = fs::remove_dir_all(config.root_dir);
    }

    #[test]
    fn memory_gateway_model_call_execute_canary_only_allows_matching_request() {
        let config = test_config("gateway_model_call_execute_canary_allow");
        let body = json!({
            "request_id": "memory_gateway_live_canary_1",
            "audit_ref": "memory_gateway_live_canary:1",
            "requester_role": "chat",
            "use_mode": "project_chat",
            "scope": "project",
            "project_id": "xt-memory-gateway-live-canary",
            "provider_id": "mlx",
            "model_id": "test-model",
            "prompt": "Only the scoped canary may execute.",
            "execute": true,
            "__test_memory_gateway_model_call_execution_admission": true,
            "__test_provider_route_authority_in_rust": true,
            "__test_model_route_authority_in_rust": true,
            "__test_local_executor_enabled": true,
            "__test_local_executor_apply_enabled": true,
            "__test_model_call_execute_canary_only": true,
            "__test_fake_local_ml_execute_ok": true
        })
        .to_string();
        let (status, raw) = memory_gateway_model_call_execute_http_json(&config, "POST", &body);
        assert_eq!(status, "200 OK");
        let execute: Value = serde_json::from_str(&raw).expect("execute json");
        assert_eq!(execute["status"], "executed");
        assert_eq!(execute["mode"], "local_ml_execute");
        assert_eq!(execute["model_call_invoked"], true);
        assert_eq!(execute["model_call_executed"], true);
        assert_eq!(execute["executor"]["canary_only"], true);
        assert_eq!(execute["executor"]["canary_scope_allowed"], true);
        assert_eq!(
            execute["executor"]["canary_project_id"],
            "xt-memory-gateway-live-canary"
        );
        assert!(!raw.contains("Only the scoped canary may execute"));

        let _ = fs::remove_dir_all(config.root_dir);
    }

    #[test]
    fn memory_gateway_model_call_plan_denies_secret_like_prompt() {
        let config = test_config("gateway_model_call_secret_denied");
        let body = json!({
            "requester_role": "chat",
            "use_mode": "project_chat",
            "scope": "project",
            "project_id": "project-model-plan",
            "prompt": "Use api key sk-secret-value"
        })
        .to_string();
        let (status, raw) = memory_gateway_model_call_plan_http_json(&config, "POST", &body);
        assert_eq!(status, "403 Forbidden");
        let denied: Value = serde_json::from_str(&raw).expect("denied json");
        assert_eq!(
            denied["error_code"],
            "memory_gateway_model_call_secret_like_prompt_denied"
        );
        assert_eq!(denied["model_call_executed"], false);

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
