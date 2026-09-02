use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;

use serde_json::{json, Value};
use xhub_core::HubConfig;
use xhub_db::{
    list_memory_object_index, list_memory_objects, read_memory_object_index_summary,
    rebuild_memory_object_index, MemoryObjectIndexFilter, MemoryObjectIndexRecord,
    MemoryObjectListFilter, MemoryObjectRecord,
};
#[cfg(test)]
use xhub_memory::retrieve_memory;
use xhub_memory::{
    retrieve_memory_from_snapshot, scan_memory_snapshot, MemoryIndexSnapshot, MemoryMode,
    MemoryRetrievalRequest, MEMORY_RETRIEVAL_RESULT_SCHEMA,
};

use super::shared::{
    first_non_empty_text, looks_like_secret_public, memory_dir_from_env,
    memory_sensitivity_allowed, normalize_memory_layer, normalize_sensitivity_filter,
    normalize_source_kind_for_object, normalize_visibility_filter, property_enabled, query_has_any,
    round6, sanitize_public_token, value_bool, value_i64, value_string, value_string_list,
    value_usize, MEMORY_OBJECT_RETRIEVAL_SOURCE, MEMORY_RETRIEVAL_TRACE_LIMIT,
};

#[cfg(test)]
#[cfg(test)]
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
    let mut candidates_for_scoring = Vec::<ObjectRetrievalDocument>::new();
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

pub fn retrieve_request_from_value(config: &HubConfig, body: &Value) -> MemoryRetrievalRequest {
    let memory_dir = value_string(body, "memory_dir")
        .or_else(|| value_string(body, "memoryDir"))
        .map(PathBuf::from)
        .unwrap_or_else(|| memory_dir_from_env(config));
    let mut request = MemoryRetrievalRequest::with_defaults(memory_dir);
    request.request_id = value_string(body, "request_id")
        .or_else(|| value_string(body, "requestId"))
        .unwrap_or_default();
    request.scope = value_string(body, "scope").unwrap_or_else(|| "current_project".to_string());
    request.mode = MemoryMode::from_str(
        value_string(body, "mode")
            .unwrap_or_else(|| "project_code".to_string())
            .as_str(),
    );
    request.project_id = value_string(body, "project_id")
        .or_else(|| value_string(body, "projectId"))
        .unwrap_or_default();
    request.query = value_string(body, "query").unwrap_or_default();
    request.latest_user = value_string(body, "latest_user")
        .or_else(|| value_string(body, "latestUser"))
        .unwrap_or_default();
    request.retrieval_kind = value_string(body, "retrieval_kind")
        .or_else(|| value_string(body, "retrievalKind"))
        .unwrap_or_else(|| "search".to_string());
    request.max_results = value_usize(body, "max_results")
        .or_else(|| value_usize(body, "maxResults"))
        .unwrap_or(5);
    request.max_snippet_chars = value_usize(body, "max_snippet_chars")
        .or_else(|| value_usize(body, "maxSnippetChars"))
        .unwrap_or(480);
    request.requested_kinds = value_string_list(body, "requested_kinds")
        .or_else(|| value_string_list(body, "requestedKinds"))
        .unwrap_or_default();
    request.requested_layers = value_string_list(body, "requested_layers")
        .or_else(|| value_string_list(body, "requestedLayers"))
        .or_else(|| value_string_list(body, "layers"))
        .unwrap_or_default();
    request.explicit_refs = value_string_list(body, "explicit_refs")
        .or_else(|| value_string_list(body, "explicitRefs"))
        .unwrap_or_default();
    request.sensitivity_max = value_string(body, "sensitivity_max")
        .or_else(|| value_string(body, "sensitivityMax"))
        .unwrap_or_default();
    request.visibility = value_string(body, "visibility").unwrap_or_default();
    request.created_after_ms = value_i64(body, "created_after_ms")
        .or_else(|| value_i64(body, "createdAfterMs"))
        .unwrap_or(0);
    request.updated_after_ms = value_i64(body, "updated_after_ms")
        .or_else(|| value_i64(body, "updatedAfterMs"))
        .unwrap_or(0);
    request.explain = value_bool(body, "explain", false);
    request.audit_ref = value_string(body, "audit_ref")
        .or_else(|| value_string(body, "auditRef"))
        .unwrap_or_default();
    request
}
