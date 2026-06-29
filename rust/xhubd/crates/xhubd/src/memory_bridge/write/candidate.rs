use std::collections::BTreeSet;

use serde_json::{json, Value};
use xhub_core::HubConfig;
use xhub_db::{
    apply_baseline_migrations, create_memory_object_with_event, list_memory_objects,
    read_memory_object, update_memory_object_with_event, MemoryEventRecord, MemoryObjectListFilter,
    MemoryObjectRecord,
};

use super::super::gate::{evaluate_memory_policy, memory_policy_json_with_candidate_transition};
use super::super::shared::{
    http_json_error, http_json_error_json, looks_like_secret_public, memory_object_to_json,
    next_memory_event_id, now_ms_i64, optional_public_token, parse_json_body, query_param,
    query_usize, sanitize_id_segment, sanitize_public_text, sanitize_public_token,
    stable_fnv1a64_hex, summarize_memory_text, value_i64, value_string, value_string_list,
    HttpJsonError, MEMORY_OBJECT_SCHEMA, MEMORY_WRITEBACK_CANDIDATE_EXTRACT_SCHEMA,
    MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
};
use super::object::create_memory_object_json_from_body;

pub(crate) fn create_writeback_candidate_json_from_body(
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
    let created = create_memory_object_json_from_body(config, &parsed.to_string())?;
    let mut value = serde_json::from_str::<Value>(&created).map_err(|err| {
        http_json_error(
            "500 Internal Server Error",
            "memory_writeback_candidate_response_parse_failed",
            err.to_string(),
        )
    })?;
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
pub(crate) struct WritebackCandidateExtractPlan {
    pub(crate) key: String,
    pub(crate) memory_id: String,
    pub(crate) operation: String,
    pub(crate) reason_code: String,
    pub(crate) source_kind: String,
    pub(crate) layer: String,
    pub(crate) title: String,
    pub(crate) text_preview: String,
    pub(crate) object: Option<MemoryObjectRecord>,
    pub(crate) event: Option<MemoryEventRecord>,
}

#[derive(Debug, Clone, Copy)]
pub(crate) struct AxMemoryDeltaCandidateKind {
    pub(crate) key: &'static str,
    pub(crate) camel_key: &'static str,
    pub(crate) suffix: &'static str,
    pub(crate) title: &'static str,
    pub(crate) source_kind: &'static str,
    pub(crate) layer: &'static str,
    pub(crate) text_prefix: &'static str,
    pub(crate) is_array: bool,
}

pub(crate) const AX_MEMORY_DELTA_CANDIDATE_KINDS: &[AxMemoryDeltaCandidateKind] = &[
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

pub(crate) fn writeback_candidate_extract_json_from_value(
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

pub(crate) fn writeback_candidate_extract_response(
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

pub(crate) fn ax_memory_delta_texts(
    delta: &Value,
    kind: &AxMemoryDeltaCandidateKind,
) -> Vec<String> {
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

pub(crate) fn writeback_candidate_extract_memory_id(
    project_id: &str,
    suffix: &str,
    text: &str,
) -> String {
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

pub(crate) fn list_writeback_candidates_json(
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
    Ok(json!({
        "schema_version": MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
        "ok": true,
        "status": "ok",
        "candidate_count": items.len(),
        "objects": items,
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

pub(crate) fn transition_memory_object_candidate_json(
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
    let after_json = memory_object_to_json(&object).to_string();
    let event = MemoryEventRecord {
        event_id: next_memory_event_id(),
        memory_id: memory_id.clone(),
        operation: operation.to_string(),
        actor: actor,
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
        },
        "object": memory_object_to_json(&object),
        "production_authority_change": false,
    })
    .to_string())
}
