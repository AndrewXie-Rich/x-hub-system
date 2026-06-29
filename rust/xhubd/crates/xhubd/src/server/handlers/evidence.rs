use serde_json::{json, Value};
use xhub_core::{json_escape, HubConfig};

use crate::evidence_bridge;
use crate::server::parse::{
    body_bool_alias, body_string_alias, optional_query_bool_alias, optional_query_usize_alias,
    query_param,
};

pub(crate) fn evidence_ledger_http_json(config: &HubConfig, query: &str) -> (&'static str, String) {
    let limit = match optional_query_usize_alias(query, "limit", "limit", 50) {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    match evidence_bridge::list_json_from_parts(
        config,
        query_param(query, "component"),
        query_param(query, "project_id").or_else(|| query_param(query, "projectId")),
        query_param(query, "run_id").or_else(|| query_param(query, "runId")),
        limit,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"evidence_ledger_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn evidence_write_http_json(config: &HubConfig, body: &str) -> (&'static str, String) {
    match evidence_bridge::write_json_from_body(config, body) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"evidence_write_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

pub(crate) fn maybe_attach_route_evidence(
    config: &HubConfig,
    query: &str,
    request_body: &Value,
    component: &str,
    response_body: String,
) -> Result<String, String> {
    let write_evidence = body_bool_alias(request_body, "write_evidence", "writeEvidence")
        .unwrap_or_else(|| {
            optional_query_bool_alias(query, "write_evidence", "writeEvidence", false)
                .unwrap_or(false)
        });
    if !write_evidence {
        return Ok(response_body);
    }

    let mut response: Value = serde_json::from_str(&response_body)
        .map_err(|err| format!("route response parse failed before evidence write: {err}"))?;
    let evidence_request = route_evidence_request(
        query,
        request_body,
        component,
        &response,
        route_evidence_verdict(component, &response),
    );
    let evidence = evidence_bridge::write_value_to_ledger(config, evidence_request)?;
    response["evidence_id"] = evidence
        .get("evidence_id")
        .cloned()
        .unwrap_or_else(|| Value::String(String::new()));
    response["evidence"] = evidence;
    serde_json::to_string(&response)
        .map_err(|err| format!("route response serialize failed after evidence write: {err}"))
}

pub(crate) fn route_evidence_request(
    query: &str,
    request_body: &Value,
    component: &str,
    response: &Value,
    output_verdict: String,
) -> Value {
    let reason = route_evidence_reason(component, response);
    json!({
        "component": component,
        "authority_mode": body_string_alias(request_body, "authority_mode", "authorityMode")
            .or_else(|| query_param(query, "authority_mode"))
            .or_else(|| query_param(query, "authorityMode"))
            .unwrap_or_else(|| "candidate".to_string()),
        "project_id": body_string_alias(request_body, "project_id", "projectId")
            .or_else(|| query_param(query, "project_id"))
            .or_else(|| query_param(query, "projectId")),
        "run_id": body_string_alias(request_body, "run_id", "runId")
            .or_else(|| query_param(query, "run_id"))
            .or_else(|| query_param(query, "runId")),
        "output_verdict": output_verdict,
        "reason_codes": reason,
        "input_ref": route_evidence_input_ref(response),
        "payload": route_evidence_payload(component, response),
    })
}

pub(crate) fn route_evidence_verdict(component: &str, response: &Value) -> String {
    match component {
        "provider_route" => {
            if response
                .pointer("/decision/selected_account_key")
                .and_then(Value::as_str)
                .unwrap_or("")
                .is_empty()
            {
                "deny".to_string()
            } else {
                "allow".to_string()
            }
        }
        "model_route" => {
            if response
                .get("selected_route_kind")
                .and_then(Value::as_str)
                .unwrap_or("")
                .is_empty()
            {
                "deny".to_string()
            } else {
                "allow".to_string()
            }
        }
        _ => "recorded".to_string(),
    }
}

pub(crate) fn route_evidence_reason(component: &str, response: &Value) -> Value {
    let reason = match component {
        "provider_route" => response
            .pointer("/decision/fallback_reason_code")
            .and_then(Value::as_str)
            .unwrap_or(""),
        "model_route" => response
            .get("blocking_reason_code")
            .and_then(Value::as_str)
            .unwrap_or(""),
        _ => "",
    };
    if reason.is_empty() {
        json!(["route_ready"])
    } else {
        json!([reason])
    }
}

pub(crate) fn route_evidence_input_ref(response: &Value) -> Value {
    json!({
        "schema_version": response.get("schema_version").cloned().unwrap_or(Value::Null),
        "command": response.get("command").cloned().unwrap_or(Value::Null),
        "request": response.get("request").cloned().unwrap_or(Value::Null),
        "updated_at_ms": response.get("updated_at_ms").cloned().unwrap_or(Value::Null),
    })
}

pub(crate) fn route_evidence_payload(component: &str, response: &Value) -> Value {
    match component {
        "provider_route" => {
            let decision = response.get("decision").unwrap_or(&Value::Null);
            json!({
                "resolved_provider": decision.get("resolved_provider").cloned().unwrap_or(Value::Null),
                "requested_model_id": decision.get("requested_model_id").cloned().unwrap_or(Value::Null),
                "pool_id": decision.get("pool_id").cloned().unwrap_or(Value::Null),
                "selected_account_key": decision.get("selected_account_key").cloned().unwrap_or(Value::Null),
                "fallback_reason_code": decision.get("fallback_reason_code").cloned().unwrap_or(Value::Null),
                "available_count": decision.get("available_count").cloned().unwrap_or(Value::Null),
                "total_count": decision.get("total_count").cloned().unwrap_or(Value::Null),
            })
        }
        "model_route" => json!({
            "selected_route_kind": response.get("selected_route_kind").cloned().unwrap_or(Value::Null),
            "selected_model_id": response.get("selected_model_id").cloned().unwrap_or(Value::Null),
            "blocking_reason_code": response.get("blocking_reason_code").cloned().unwrap_or(Value::Null),
            "selected": response.get("selected").cloned().unwrap_or(Value::Null),
        }),
        _ => json!({}),
    }
}
