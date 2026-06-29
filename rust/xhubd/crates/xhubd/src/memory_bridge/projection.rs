use std::collections::BTreeMap;
use std::fmt::Write as _;

use serde_json::{json, Value};
use xhub_core::HubConfig;
use xhub_db::{list_memory_objects, MemoryObjectListFilter, MemoryObjectRecord};

use super::gate::{evaluate_memory_policy, MemoryPolicyEvaluation};
use super::shared::{
    http_json_error_json, looks_like_secret_public, normalize_enum_token,
    normalize_source_kind_for_object, sanitize_public_token, value_bool, value_string,
    value_string_list, value_usize, HttpJsonError, MEMORY_GATEWAY_PREPARE_SCHEMA,
};

#[derive(Debug, Clone)]
pub(crate) struct GatewayProfileDefaults {
    pub(crate) layers: Vec<String>,
    pub(crate) source_kinds: Vec<String>,
    pub(crate) max_items: usize,
    pub(crate) max_snippet_chars: usize,
    pub(crate) read_multiplier: usize,
}

pub(crate) fn normalize_serving_profile_id(raw: &str) -> Option<String> {
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

pub(crate) fn gateway_default_serving_profile(
    use_mode: &str,
    _remote_export_requested: bool,
) -> String {
    match use_mode {
        "lane_handoff" | "remote_prompt_bundle" => "M0_Heartbeat".to_string(),
        _ => "M1_Execute".to_string(),
    }
}

pub(crate) fn gateway_serving_profile_rank(profile: &str) -> usize {
    match profile {
        "M0_Heartbeat" => 0,
        "M1_Execute" => 1,
        "M2_PlanReview" => 2,
        "M3_DeepDive" => 3,
        "M4_FullScan" => 4,
        _ => 1,
    }
}

pub(crate) fn gateway_profile_defaults(profile: &str) -> GatewayProfileDefaults {
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

pub(crate) fn gateway_allowed_layers(
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

pub(crate) fn gateway_requested_source_kinds(requested_source_kinds: &[String]) -> Vec<String> {
    requested_source_kinds
        .iter()
        .map(|source_kind| normalize_source_kind_for_object(source_kind))
        .collect()
}

pub(crate) fn gateway_json_error(
    status: &'static str,
    error_code: &str,
    message: String,
) -> HttpJsonError {
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

pub(crate) fn gateway_memory_object_to_json(
    object: &MemoryObjectRecord,
    max_chars: usize,
) -> Value {
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

pub(crate) fn gateway_context_text(objects: &[MemoryObjectRecord], max_chars: usize) -> String {
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

pub(crate) fn gateway_truncate_text(value: &str, max_chars: usize) -> String {
    let normalized = value.split_whitespace().collect::<Vec<_>>().join(" ");
    if normalized.chars().count() <= max_chars {
        normalized
    } else {
        normalized.chars().take(max_chars).collect()
    }
}

pub(crate) fn memory_gateway_prepare_json_from_value(
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
    let mut skipped_for_budget = 0usize;
    for object in objects {
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
        if selected.len() >= max_items {
            skipped_for_budget += 1;
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
        "omitted_count": skipped_for_budget,
        "denied_count": denied_count,
        "max_items": max_items,
        "max_snippet_chars": max_snippet_chars,
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
    })
    .to_string())
}
