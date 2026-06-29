use serde_json::{json, Value};

use super::shared::{
    normalize_enum_token, raw_evidence_requested, value_bool, value_string, value_string_list,
    MEMORY_POLICY_RESULT_SCHEMA, MEMORY_WRITEBACK_CANDIDATE_SCHEMA,
};

#[derive(Debug, Clone)]
pub(crate) struct MemoryPolicyEvaluation {
    pub(crate) schema_version: String,
    pub(crate) ok: bool,
    pub(crate) decision: String,
    pub(crate) deny_code: String,
    pub(crate) downgrade_code: String,
    pub(crate) requester_role: String,
    pub(crate) use_mode: String,
    pub(crate) scope: String,
    pub(crate) allowed_roles: Vec<String>,
    pub(crate) denied_roles: Vec<String>,
    pub(crate) allowed_layers: Vec<String>,
    pub(crate) allowed_source_kinds: Vec<String>,
    pub(crate) visibility_floor: String,
    pub(crate) raw_evidence_allowed: bool,
    pub(crate) personal_memory_allowed: bool,
    pub(crate) requires_fresh_snapshot: bool,
}

impl MemoryPolicyEvaluation {
    pub(crate) fn deny(
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

    pub(crate) fn to_json(&self) -> Value {
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

pub(crate) fn evaluate_memory_policy_json(body: &Value) -> String {
    evaluate_memory_policy(body).to_json().to_string()
}

pub(crate) fn evaluate_memory_policy(body: &Value) -> MemoryPolicyEvaluation {
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

pub(crate) fn memory_policy_json_with_candidate_transition(
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
