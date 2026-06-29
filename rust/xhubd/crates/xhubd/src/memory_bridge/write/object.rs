use serde_json::json;
use xhub_core::HubConfig;
use xhub_db::{
    apply_baseline_migrations, create_memory_object_with_event, list_memory_objects,
    read_memory_object, read_memory_object_history, MemoryEventRecord, MemoryObjectListFilter,
    MemoryObjectRecord,
};

use super::super::gate::evaluate_memory_policy;
use super::super::shared::{
    http_json_error, http_json_error_json, looks_like_secret_public, memory_event_to_json,
    memory_object_to_json, memory_writer_authority_enabled, next_memory_event_id, next_memory_id,
    normalize_enum_token, normalize_source_kind_for_object, now_ms_i64, optional_public_token,
    parse_json_body, query_param, query_usize, sanitize_public_text, sanitize_public_text_value,
    sanitize_public_token, summarize_memory_text, value_bool, value_i64, value_string,
    value_string_list, HttpJsonError, MEMORY_OBJECT_HISTORY_SCHEMA, MEMORY_OBJECT_LIST_SCHEMA,
    MEMORY_OBJECT_RESULT_SCHEMA, MEMORY_OBJECT_SCHEMA,
};

pub(crate) fn create_memory_object_json_from_body(
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
        actor: actor,
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

pub(crate) fn get_memory_object_json(
    config: &HubConfig,
    memory_id: &str,
) -> Result<String, HttpJsonError> {
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

pub(crate) fn list_memory_objects_json(
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

pub(crate) fn memory_object_history_json(
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
