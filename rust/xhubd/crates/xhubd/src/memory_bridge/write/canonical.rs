use serde_json::{json, Value};
use xhub_core::HubConfig;
use xhub_db::{
    apply_baseline_migrations, create_memory_object_with_event, read_memory_object,
    update_memory_object_with_event, MemoryEventRecord, MemoryObjectRecord,
};

use super::super::gate::evaluate_memory_policy;
use super::super::shared::{
    http_json_error, http_json_error_json, memory_object_to_json, memory_writer_authority_enabled,
    next_memory_event_id, now_ms_i64, project_canonical_item_kind, project_canonical_memory_id,
    sanitize_public_text, sanitize_public_token, summarize_memory_text, value_string,
    HttpJsonError, MEMORY_OBJECT_SCHEMA, MEMORY_PROJECT_CANONICAL_SYNC_SCHEMA,
};

#[derive(Debug, Clone)]
pub(crate) struct ProjectCanonicalSyncPlan {
    pub(crate) key: String,
    pub(crate) memory_id: String,
    pub(crate) operation: String,
    pub(crate) reason_code: String,
    pub(crate) object: Option<MemoryObjectRecord>,
    pub(crate) event: Option<MemoryEventRecord>,
}

pub(crate) fn project_canonical_sync_json_from_value(
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

pub(crate) fn project_canonical_sync_response(
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
