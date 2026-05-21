use std::env;

use serde_json::{json, Value};
use xhub_core::{now_ms, HubConfig, DAEMON_NAME};
use xhub_memory::{MEMORY_RETRIEVAL_RESULT_SCHEMA, MEMORY_WRITE_RESULT_SCHEMA};
use xhub_skills::{
    SkillBoundary, SKILL_CATALOG_SCHEMA, SKILL_POLICY_EVENTS_PRUNE_SCHEMA,
    SKILL_POLICY_EVENTS_SCHEMA, SKILL_POLICY_STORE_READINESS_SCHEMA, SKILL_PREFLIGHT_AUDIT_SCHEMA,
    SKILL_PREFLIGHT_AUDIT_SUMMARY_SCHEMA, SKILL_PREFLIGHT_SCHEMA, SKILL_READINESS_SCHEMA,
};

use crate::{memory_bridge, skills_bridge};

pub const XT_HUB_CONTRACT_SCHEMA: &str = "xhub.rust_hub.xt_contract.v1";

pub fn run(config: &HubConfig, args: &[String]) -> Result<(), String> {
    let command = args
        .first()
        .map(|value| value.as_str())
        .unwrap_or("contract");
    if matches!(command, "help" | "-h" | "--help") {
        println!("{}", help_json());
        return Ok(());
    }
    match command {
        "contract" | "hub-contract" | "capabilities" => {
            println!("{}", contract_json(config));
            Ok(())
        }
        other => Err(format!("unknown xt command: {other}")),
    }
}

pub fn contract_http_json(config: &HubConfig) -> (&'static str, String) {
    ("200 OK", contract_json(config))
}

pub fn contract_json(config: &HubConfig) -> String {
    serde_json::to_string(&contract_value(config)).unwrap_or_else(|err| {
        json!({
            "schema_version": XT_HUB_CONTRACT_SCHEMA,
            "ok": false,
            "error": "xt_contract_serialize_failed",
            "message": err.to_string(),
        })
        .to_string()
    })
}

pub fn contract_value(config: &HubConfig) -> Value {
    let loopback_bind = is_loopback_host(&config.host);
    let public_endpoint_enabled = env_bool("XHUB_RUST_CROSS_NETWORK_PUBLIC_ENDPOINT", false)
        || env_bool("XHUB_RUST_HUB_PUBLIC_ENDPOINT", false);
    let http_access_key_required =
        config.http_access_key_required || !loopback_bind || public_endpoint_enabled;
    let http_access_key_configured = config.http_access_key.is_some();
    let memory_writer_authority = memory_bridge::memory_writer_authority_enabled();
    let skills_execution_authority = skills_bridge::skills_execution_authority_enabled();
    let skill_boundary = SkillBoundary::default();

    json!({
        "schema_version": XT_HUB_CONTRACT_SCHEMA,
        "ok": true,
        "generated_at_ms": now_ms().min(i64::MAX as u128) as i64,
        "daemon": DAEMON_NAME,
        "version": env!("CARGO_PKG_VERSION"),
        "hub_product": {
            "kernel": "rust_core",
            "shell": "swift_macos",
            "xt_role": "paired_deep_client",
            "source_of_truth": "hub",
        },
        "transport_security": {
            "http_addr": config.http_addr(),
            "loopback_bind": loopback_bind,
            "http_access_key_required": http_access_key_required,
            "http_access_key_configured": http_access_key_configured,
            "http_access_key_source": if config.http_access_key_source.is_empty() { "none" } else { config.http_access_key_source.as_str() },
            "remote_xt_requires_pairing": true,
            "remote_xt_requires_mtls_for_runtime_channels": true,
            "remote_http_requires_access_key": http_access_key_required,
            "public_endpoint_enabled": public_endpoint_enabled,
            "secret_fields_included": false,
        },
        "xt_update_rule": {
            "must_read_contract_first": true,
            "must_not_recreate_hub_authority_locally": true,
            "must_fail_closed_on_missing_grant_or_stale_contract": true,
            "preferred_refresh_endpoint": "/xt/hub-contract",
            "recommended_contract_ttl_ms": 60_000,
        },
        "capabilities": {
            "pairing": pairing_contract(config),
            "remote_entry": remote_entry_contract(),
            "readiness": readiness_contract(),
            "models": models_contract(),
            "provider_route": provider_route_contract(),
            "memory": memory_contract(memory_writer_authority),
            "skills": skills_contract(skills_execution_authority, &skill_boundary),
            "grants": grants_contract(),
            "audit": audit_contract(),
        },
        "migration_notes_for_xt": [
            "XT should treat this document as the Hub capability registry before adding memory, skills, model route, or grant behavior.",
            "XT may cache Hub projections for UI speed, but durable memory, policy, grant, route, and audit truth remain in Hub.",
            "XT must call Hub preflight/grant endpoints before executing skill code with side effects.",
            "XT should prefer remote_entry candidates from Hub instead of deriving a public host from local UI state."
        ],
    })
}

fn help_json() -> String {
    json!({
        "schema_version": "xhub.rust_hub.xt_bridge.v1",
        "ok": true,
        "commands": ["contract"],
        "http_routes": ["/xt/hub-contract", "/xt/contract", "/contract/xt"],
        "contract_schema": XT_HUB_CONTRACT_SCHEMA,
        "description": "Machine-readable Hub capability contract for X-Terminal and XT-updating agents.",
    })
    .to_string()
}

fn pairing_contract(config: &HubConfig) -> Value {
    json!({
        "authority": "swift_shell_pairing_service",
        "xt_role": "pair_once_then_use_route_pack",
        "grpc_port": config.grpc_port,
        "pairing_port": 50059,
        "requires_auth": true,
        "requires_mtls": true,
        "cache_policy": "cache_pairing_profile_and_route_pack_until_epoch_change",
        "fallback_policy": "fail_closed_then_repair_pairing",
        "endpoints": {
            "discovery": "/pairing/discovery",
            "grpc_runtime": "HubRuntime on configured grpc_port"
        }
    })
}

fn remote_entry_contract() -> Value {
    json!({
        "authority": "rust_core_network_bridge",
        "endpoint": "/network/remote-entry-candidates",
        "aliases": ["/network/remote-entry", "/remote/entry-candidates"],
        "xt_role": "consume_route_candidates",
        "requires_auth": true,
        "requires_mtls": true,
        "cache_policy": "short_ttl_route_pack",
        "fallback_policy": "use_last_known_good_route_pack_then_prompt_repair",
        "supports_domain_users": true,
        "supports_no_domain_users": true,
        "preferred_routes": ["stable_domain_or_tunnel", "no_domain_private_network"],
        "unsafe_routes": ["raw_public_ip_without_tunnel_or_mtls"],
    })
}

fn readiness_contract() -> Value {
    json!({
        "authority": "rust_core",
        "endpoint": "/ready",
        "aliases": ["/readiness", "/runtime/readiness"],
        "xt_role": "display_and_gate_runtime_use",
        "requires_auth": true,
        "requires_mtls": false,
        "cache_policy": "short_ttl_readiness",
        "fallback_policy": "show_degraded_state_do_not_invent_readiness",
    })
}

fn models_contract() -> Value {
    json!({
        "authority": "hub_model_route",
        "endpoints": {
            "inventory": "/model/inventory",
            "local_capabilities": "/model/capabilities",
            "repair_plan": "/model/repair-plan",
            "repair_apply": "/model/repair-apply",
            "repair_jobs": "/model/repair-jobs",
            "route": "/model/route",
            "diagnostics": "/model/diagnostics",
            "readiness": "/model/readiness"
        },
        "inventory_fields": {
            "local_capability_summary": "task-level local text/embedding/vision/ocr/speech readiness for XT UI and repair hints"
        },
        "repair_plan_fields": {
            "resolved": "Hub-normalized local model repair action, task kind, provider id, and source",
            "requirements": "safe dependency, helper, model registry, or capability metadata requirements without secrets",
            "steps": "UI-ready repair steps; install steps require explicit user approval",
            "apply": "confirmed apply only queues a non-blocking repair job; heavy installs must run in a background executor"
        },
        "xt_role": "request_route_and_display_truth",
        "requires_auth": true,
        "requires_mtls": false,
        "cache_policy": "cache_inventory_only_route_each_run",
        "fallback_policy": "fail_closed_or_hub_declared_downgrade_only",
        "xt_must_not_select_paid_provider_directly": true,
    })
}

fn provider_route_contract() -> Value {
    json!({
        "authority": "hub_provider_route",
        "endpoints": {
            "route": "/provider/route",
            "compare": "/provider/compare",
            "reports": "/provider/reports",
            "readiness": "/provider/readiness"
        },
        "xt_role": "consume_provider_selection_projection",
        "requires_auth": true,
        "requires_mtls": false,
        "cache_policy": "cache_explainability_not_secret_material",
        "fallback_policy": "never_read_or_export_provider_secret_values",
        "secret_fields_included": false,
    })
}

fn memory_contract(memory_writer_authority: bool) -> Value {
    json!({
        "authority": if memory_writer_authority { "rust_core_memory_writer" } else { "hub_memory_writer_gate" },
        "endpoints": {
            "search": "/memory/search",
            "retrieve": "/memory/retrieve",
            "write": "/memory/write",
            "readiness": "/memory/readiness"
        },
        "xt_role": "consume_projection_submit_candidates",
        "requires_auth": true,
        "requires_mtls": false,
        "cache_policy": "short_local_context_window_only",
        "fallback_policy": "local_ephemeral_context_only_no_durable_claim",
        "canonical_writer": "hub_only",
        "writer_authority_in_rust": memory_writer_authority,
        "durable_truth_in_xt": false,
        "schemas": {
            "retrieval_result": MEMORY_RETRIEVAL_RESULT_SCHEMA,
            "write_result": MEMORY_WRITE_RESULT_SCHEMA
        }
    })
}

fn skills_contract(skills_execution_authority: bool, skill_boundary: &SkillBoundary) -> Value {
    json!({
        "authority": "hub_policy_gate",
        "endpoints": {
            "catalog": "/skills/catalog",
            "readiness": "/skills/readiness",
            "policy": "/skills/policy",
            "policy_readiness": "/skills/policy-readiness",
            "policy_events": "/skills/policy-events",
            "policy_events_prune": "/skills/policy-events-prune",
            "pin": "/skills/pin",
            "grant": "/skills/grant",
            "revoke_grant": "/skills/revoke-grant",
            "unpin": "/skills/unpin",
            "preflight": "/skills/preflight",
            "audit": "/skills/audit",
            "audit_prune": "/skills/audit-prune",
            "execute": "/skills/execute"
        },
        "xt_role": "resolve_catalog_request_preflight_execute_only_with_lease",
        "requires_auth": true,
        "requires_mtls": false,
        "cache_policy": "cache_catalog_and_pins_short_ttl_revalidate_preflight_before_execution",
        "fallback_policy": "fail_closed_on_missing_pin_grant_or_preflight",
        "execution_model": "hub_authorizes_xt_or_sandbox_runner_executes",
        "execution_locations": ["xt_local", "sandbox_runner", "hub_builtin_or_opt_in_runner"],
        "preferred_execution_location": "xt_local_or_sandbox_runner",
        "lease_required": true,
        "lease_source_endpoint": "/skills/preflight",
        "recommended_lease_ttl_ms": 300_000,
        "revocation_epoch_required": true,
        "package_hash_pin_required": true,
        "secret_redaction_required": true,
        "requires_pin_or_grant": skill_boundary.requires_pin_or_grant,
        "third_party_code_in_hub_trust_root": false,
        "hub_executes_third_party_code": skill_boundary.hub_executes_third_party_code,
        "execution_authority_in_rust": skills_execution_authority,
        "rust_execute_http_enabled_but_guarded": true,
        "schemas": {
            "catalog": SKILL_CATALOG_SCHEMA,
            "readiness": SKILL_READINESS_SCHEMA,
            "preflight": SKILL_PREFLIGHT_SCHEMA,
            "preflight_audit": SKILL_PREFLIGHT_AUDIT_SCHEMA,
            "preflight_audit_summary": SKILL_PREFLIGHT_AUDIT_SUMMARY_SCHEMA,
            "policy_events": SKILL_POLICY_EVENTS_SCHEMA,
            "policy_events_prune": SKILL_POLICY_EVENTS_PRUNE_SCHEMA,
            "policy_store_readiness": SKILL_POLICY_STORE_READINESS_SCHEMA
        }
    })
}

fn grants_contract() -> Value {
    json!({
        "authority": "hub_supervisor_policy_gate",
        "xt_role": "request_and_display_grant_state_never_self_grant",
        "requires_auth": true,
        "requires_mtls": true,
        "cache_policy": "cache_pending_state_only_until_expiry",
        "fallback_policy": "fail_closed_on_missing_or_expired_grant",
        "high_risk_requires_bound_grant_id": true,
        "natural_language_direct_grant": false,
    })
}

fn audit_contract() -> Value {
    json!({
        "authority": "hub_append_only_audit",
        "xt_role": "attach_evidence_refs_and_display_truth",
        "requires_auth": true,
        "requires_mtls": false,
        "cache_policy": "append_only_refs_local_cache_ok",
        "fallback_policy": "do_not_synthesize_audit_refs",
        "endpoints": {
            "evidence_ledger": "/evidence/ledger",
            "evidence_write": "/evidence/write",
            "skills_audit": "/skills/audit",
            "skills_policy_events": "/skills/policy-events"
        }
    })
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

fn is_loopback_host(host: &str) -> bool {
    let value = host.trim().to_ascii_lowercase();
    matches!(value.as_str(), "127.0.0.1" | "::1" | "localhost")
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::*;

    fn test_config() -> HubConfig {
        let root = PathBuf::from("/tmp/xhubd-xt-contract-test");
        HubConfig {
            root_dir: root.clone(),
            host: "127.0.0.1".to_string(),
            http_port: 50151,
            grpc_port: 50152,
            db_path: root.join("data").join("hub.sqlite3"),
            runtime_base_dir: root.join("runtime"),
            proto_path: root
                .join("assets")
                .join("proto")
                .join("hub_protocol_v1.proto"),
            canonical_proto_path: root
                .join("assets")
                .join("proto")
                .join("hub_protocol_v1.proto"),
            http_access_key: Some("test-key".to_string()),
            http_access_key_source: "test".to_string(),
            http_access_key_required: true,
        }
    }

    #[test]
    fn xt_contract_lists_hub_owned_capabilities() {
        let value = contract_value(&test_config());
        assert_eq!(value["schema_version"], XT_HUB_CONTRACT_SCHEMA);
        assert_eq!(
            value["capabilities"]["memory"]["canonical_writer"],
            "hub_only"
        );
        assert_eq!(
            value["capabilities"]["memory"]["durable_truth_in_xt"],
            false
        );
        assert_eq!(
            value["capabilities"]["remote_entry"]["supports_no_domain_users"],
            true
        );
        assert_eq!(
            value["capabilities"]["models"]["xt_must_not_select_paid_provider_directly"],
            true
        );
        assert_eq!(
            value["capabilities"]["models"]["endpoints"]["local_capabilities"],
            "/model/capabilities"
        );
        assert_eq!(
            value["capabilities"]["models"]["endpoints"]["repair_plan"],
            "/model/repair-plan"
        );
        assert_eq!(
            value["capabilities"]["models"]["endpoints"]["repair_apply"],
            "/model/repair-apply"
        );
        assert_eq!(
            value["capabilities"]["models"]["endpoints"]["repair_jobs"],
            "/model/repair-jobs"
        );
    }

    #[test]
    fn xt_contract_freezes_skills_as_policy_gate_with_lease() {
        let value = contract_value(&test_config());
        let skills = &value["capabilities"]["skills"];
        assert_eq!(skills["authority"], "hub_policy_gate");
        assert_eq!(skills["lease_required"], true);
        assert_eq!(skills["lease_source_endpoint"], "/skills/preflight");
        assert_eq!(skills["third_party_code_in_hub_trust_root"], false);
        assert_eq!(skills["package_hash_pin_required"], true);
        assert_eq!(
            skills["fallback_policy"],
            "fail_closed_on_missing_pin_grant_or_preflight"
        );
    }
}
