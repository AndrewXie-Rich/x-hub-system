use std::collections::BTreeMap;
use std::env;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};

use serde_json::{json, Value};
use xhub_core::HubConfig;
use xhub_db::{
    apply_baseline_migrations, prune_skill_policy_events_by_max_rows,
    prune_skill_preflight_audit_by_max_rows, read_skill_policy_binding,
    read_skill_policy_event_summary, read_skill_policy_store_summary,
    read_skill_preflight_audit_summary, revoke_skill_grant, revoke_skill_pin, upsert_skill_grant,
    upsert_skill_pin, write_skill_policy_event, write_skill_preflight_audit, SkillGrantRecord,
    SkillPinRecord, SkillPolicyEventRecord, SkillPolicyEventRow, SkillPolicyEventSummary,
    SkillPolicyStoreSummary, SkillPreflightAuditRecord, SkillPreflightAuditRow,
    SkillPreflightAuditSummary,
};
use xhub_skills::{
    evaluate_skill_preflight, scan_skill_catalog, SkillCatalog, SkillCatalogEntry,
    SkillPreflightDecision, SkillPreflightRequest, SKILL_CATALOG_SCHEMA,
    SKILL_POLICY_EVENTS_PRUNE_SCHEMA, SKILL_POLICY_EVENTS_SCHEMA, SKILL_POLICY_SOURCE,
    SKILL_POLICY_STORE_READINESS_SCHEMA, SKILL_PREFLIGHT_AUDIT_PRUNE_SCHEMA,
    SKILL_PREFLIGHT_AUDIT_SCHEMA, SKILL_PREFLIGHT_AUDIT_SUMMARY_SCHEMA, SKILL_PREFLIGHT_SCHEMA,
    SKILL_READINESS_SCHEMA,
};

const SCHEMA_VERSION: &str = "xhub.skills_bridge.v1";
static SKILL_EVENT_COUNTER: AtomicU64 = AtomicU64::new(1);

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
        "catalog" | "list" => {
            let flags = FlagArgs::parse(&args[1..])?;
            let skills_dir = flags
                .optional("skills-dir")
                .map(PathBuf::from)
                .unwrap_or_else(|| skills_dir_from_env(config));
            catalog_json_from_dir(skills_dir)
        }
        "readiness" | "status" => {
            let flags = FlagArgs::parse(&args[1..])?;
            let skills_dir = flags
                .optional("skills-dir")
                .map(PathBuf::from)
                .unwrap_or_else(|| skills_dir_from_env(config));
            readiness_json_from_dir(skills_dir)
        }
        "policy-readiness" | "policy-maintenance" | "maintenance" => {
            let flags = FlagArgs::parse(&args[1..])?;
            policy_store_readiness_json_from_parts(
                config,
                parse_i64_flag(
                    flags.optional("max-preflight-audit-rows"),
                    100_000,
                    1,
                    10_000_000,
                    "max_preflight_audit_rows",
                )?,
                parse_i64_flag(
                    flags.optional("max-policy-event-rows"),
                    100_000,
                    1,
                    10_000_000,
                    "max_policy_event_rows",
                )?,
            )
        }
        "pin" => {
            let flags = FlagArgs::parse(&args[1..])?;
            pin_json_from_parts(
                config,
                flags
                    .optional("scope-key")
                    .unwrap_or_else(|| "default".to_string()),
                flags.optional("skill-id").unwrap_or_default(),
                flags
                    .optional("pinned-by")
                    .or_else(|| flags.optional("actor"))
                    .unwrap_or_else(|| "rust_hub_operator".to_string()),
            )
        }
        "grant" => {
            let flags = FlagArgs::parse(&args[1..])?;
            grant_json_from_parts(
                config,
                flags
                    .optional("scope-key")
                    .unwrap_or_else(|| "default".to_string()),
                flags.optional("skill-id").unwrap_or_default(),
                flags.optional("capability").unwrap_or_default(),
                flags
                    .optional("granted-by")
                    .or_else(|| flags.optional("actor"))
                    .unwrap_or_else(|| "rust_hub_operator".to_string()),
            )
        }
        "unpin" | "revoke-pin" => {
            let flags = FlagArgs::parse(&args[1..])?;
            unpin_json_from_parts(
                config,
                flags
                    .optional("scope-key")
                    .unwrap_or_else(|| "default".to_string()),
                flags.optional("skill-id").unwrap_or_default(),
                flags
                    .optional("revoked-by")
                    .or_else(|| flags.optional("actor"))
                    .unwrap_or_else(|| "rust_hub_operator".to_string()),
            )
        }
        "revoke-grant" | "ungrant" => {
            let flags = FlagArgs::parse(&args[1..])?;
            revoke_grant_json_from_parts(
                config,
                flags
                    .optional("scope-key")
                    .unwrap_or_else(|| "default".to_string()),
                flags.optional("skill-id").unwrap_or_default(),
                flags.optional("capability").unwrap_or_default(),
                flags
                    .optional("revoked-by")
                    .or_else(|| flags.optional("actor"))
                    .unwrap_or_else(|| "rust_hub_operator".to_string()),
            )
        }
        "policy" | "binding" => {
            let flags = FlagArgs::parse(&args[1..])?;
            policy_json_from_parts(
                config,
                flags
                    .optional("scope-key")
                    .unwrap_or_else(|| "default".to_string()),
                flags.optional("skill-id").unwrap_or_default(),
            )
        }
        "policy-events" | "policy-audit" => {
            let flags = FlagArgs::parse(&args[1..])?;
            policy_events_json_from_parts(
                config,
                flags.optional("scope-key"),
                flags.optional("skill-id"),
                parse_usize_flag(flags.optional("limit"), 20, 1, 500, "limit")?,
            )
        }
        "policy-events-prune" | "policy-audit-prune" => {
            let flags = FlagArgs::parse(&args[1..])?;
            policy_events_prune_json_from_parts(
                config,
                parse_usize_flag(flags.optional("max-rows"), 10_000, 1, 1_000_000, "max_rows")?,
            )
        }
        "audit" | "audit-summary" => {
            let flags = FlagArgs::parse(&args[1..])?;
            audit_json_from_parts(
                config,
                flags.optional("scope-key"),
                flags.optional("skill-id"),
                parse_usize_flag(flags.optional("limit"), 20, 1, 500, "limit")?,
            )
        }
        "audit-prune" | "prune-audit" => {
            let flags = FlagArgs::parse(&args[1..])?;
            audit_prune_json_from_parts(
                config,
                parse_usize_flag(flags.optional("max-rows"), 10_000, 1, 1_000_000, "max_rows")?,
            )
        }
        "preflight" => {
            let flags = FlagArgs::parse(&args[1..])?;
            let skills_dir = flags
                .optional("skills-dir")
                .map(PathBuf::from)
                .unwrap_or_else(|| skills_dir_from_env(config));
            let request = SkillPreflightRequest {
                request_id: flags.optional("request-id").unwrap_or_default(),
                audit_ref: flags.optional("audit-ref").unwrap_or_default(),
                scope_key: flags
                    .optional("scope-key")
                    .unwrap_or_else(|| "default".to_string()),
                skill_id: flags.optional("skill-id").unwrap_or_default(),
                requested_capabilities: flags.optional_list("requested-capabilities"),
                pinned_skill_ids: flags.optional_list("pinned-skill-ids"),
                granted_capabilities: flags.optional_list("granted-capabilities"),
            };
            preflight_json_from_request(config, skills_dir, request)
        }
        other => Err(format!("unknown skills command: {other}")),
    }
}

pub fn catalog_json_from_dir(skills_dir: PathBuf) -> Result<String, String> {
    let catalog = scan_skill_catalog(&skills_dir);
    catalog_json_from_catalog(&catalog)
}

pub fn catalog_json_from_catalog(catalog: &SkillCatalog) -> Result<String, String> {
    Ok(json!({
        "schema_version": SCHEMA_VERSION,
        "ok": true,
        "command": "catalog",
        "catalog": catalog_to_value(&catalog),
    })
    .to_string())
}

pub fn readiness_json_from_dir(skills_dir: PathBuf) -> Result<String, String> {
    let catalog = scan_skill_catalog(&skills_dir);
    readiness_json_from_catalog(&catalog)
}

pub fn readiness_json_from_catalog(catalog: &SkillCatalog) -> Result<String, String> {
    Ok(json!({
        "schema_version": SCHEMA_VERSION,
        "ok": true,
        "command": "readiness",
        "readiness": readiness_to_value(&catalog),
    })
    .to_string())
}

pub fn policy_store_readiness_json_from_parts(
    config: &HubConfig,
    max_preflight_audit_rows: i64,
    max_policy_event_rows: i64,
) -> Result<String, String> {
    ensure_skill_policy_db(config)?;
    let summary = read_skill_policy_store_summary(&config.db_path)
        .map_err(|err| format!("skill policy store summary failed: {err}"))?;
    Ok(json!({
        "schema_version": SCHEMA_VERSION,
        "ok": true,
        "command": "policy-readiness",
        "policy_readiness": policy_store_readiness_to_value(
            &summary,
            max_preflight_audit_rows,
            max_policy_event_rows,
        ),
    })
    .to_string())
}

pub fn pin_json_from_parts(
    config: &HubConfig,
    scope_key: String,
    skill_id: String,
    pinned_by: String,
) -> Result<String, String> {
    ensure_skill_policy_db(config)?;
    let scope_key = public_token_or_default(&scope_key, "default")?;
    let skill_id = public_token_required(&skill_id, "skill_id")?;
    let pinned_by = public_token_or_default(&pinned_by, "rust_hub_operator")?;
    upsert_skill_pin(
        &config.db_path,
        &SkillPinRecord {
            scope_key: scope_key.clone(),
            skill_id: skill_id.clone(),
            pinned_by: pinned_by.clone(),
        },
    )
    .map_err(|err| format!("skill pin write failed: {err}"))?;
    let policy_event_id = write_policy_event(
        config,
        "pin",
        &scope_key,
        &skill_id,
        None,
        &pinned_by,
        "applied",
        json!({"pinned": true}),
    )?;
    Ok(json!({
        "schema_version": SCHEMA_VERSION,
        "ok": true,
        "command": "pin",
        "scope_key": scope_key,
        "skill_id": skill_id,
        "pinned_by": pinned_by,
        "policy_event_id": policy_event_id,
        "authority": "policy_gate_only",
        "execution_authority_in_rust": false,
    })
    .to_string())
}

pub fn grant_json_from_parts(
    config: &HubConfig,
    scope_key: String,
    skill_id: String,
    capability: String,
    granted_by: String,
) -> Result<String, String> {
    ensure_skill_policy_db(config)?;
    let scope_key = public_token_or_default(&scope_key, "default")?;
    let skill_id = public_token_required(&skill_id, "skill_id")?;
    let capability = public_token_required(&capability, "capability")?;
    let granted_by = public_token_or_default(&granted_by, "rust_hub_operator")?;
    upsert_skill_grant(
        &config.db_path,
        &SkillGrantRecord {
            scope_key: scope_key.clone(),
            skill_id: skill_id.clone(),
            capability: capability.clone(),
            granted_by: granted_by.clone(),
        },
    )
    .map_err(|err| format!("skill grant write failed: {err}"))?;
    let policy_event_id = write_policy_event(
        config,
        "grant",
        &scope_key,
        &skill_id,
        Some(&capability),
        &granted_by,
        "applied",
        json!({"granted": true}),
    )?;
    Ok(json!({
        "schema_version": SCHEMA_VERSION,
        "ok": true,
        "command": "grant",
        "scope_key": scope_key,
        "skill_id": skill_id,
        "capability": capability,
        "granted_by": granted_by,
        "policy_event_id": policy_event_id,
        "authority": "policy_gate_only",
        "execution_authority_in_rust": false,
    })
    .to_string())
}

pub fn unpin_json_from_parts(
    config: &HubConfig,
    scope_key: String,
    skill_id: String,
    revoked_by: String,
) -> Result<String, String> {
    ensure_skill_policy_db(config)?;
    let scope_key = public_token_or_default(&scope_key, "default")?;
    let skill_id = public_token_required(&skill_id, "skill_id")?;
    let revoked_by = public_token_or_default(&revoked_by, "rust_hub_operator")?;
    let report = revoke_skill_pin(&config.db_path, &scope_key, &skill_id)
        .map_err(|err| format!("skill pin revoke failed: {err}"))?;
    let result = if report.revoked_rows > 0 {
        "revoked"
    } else {
        "not_found"
    };
    let policy_event_id = write_policy_event(
        config,
        "unpin",
        &scope_key,
        &skill_id,
        None,
        &revoked_by,
        result,
        json!({"revoked_rows": report.revoked_rows}),
    )?;
    Ok(json!({
        "schema_version": SCHEMA_VERSION,
        "ok": true,
        "command": "unpin",
        "scope_key": scope_key,
        "skill_id": skill_id,
        "revoked_by": revoked_by,
        "revoked_rows": report.revoked_rows,
        "policy_event_id": policy_event_id,
        "pinned": false,
        "authority": "policy_gate_only",
        "execution_authority_in_rust": false,
        "hub_executes_third_party_code": false,
    })
    .to_string())
}

pub fn revoke_grant_json_from_parts(
    config: &HubConfig,
    scope_key: String,
    skill_id: String,
    capability: String,
    revoked_by: String,
) -> Result<String, String> {
    ensure_skill_policy_db(config)?;
    let scope_key = public_token_or_default(&scope_key, "default")?;
    let skill_id = public_token_required(&skill_id, "skill_id")?;
    let capability = public_token_required(&capability, "capability")?;
    let revoked_by = public_token_or_default(&revoked_by, "rust_hub_operator")?;
    let report = revoke_skill_grant(&config.db_path, &scope_key, &skill_id, &capability)
        .map_err(|err| format!("skill grant revoke failed: {err}"))?;
    let result = if report.revoked_rows > 0 {
        "revoked"
    } else {
        "not_found"
    };
    let policy_event_id = write_policy_event(
        config,
        "revoke_grant",
        &scope_key,
        &skill_id,
        Some(&capability),
        &revoked_by,
        result,
        json!({"revoked_rows": report.revoked_rows}),
    )?;
    Ok(json!({
        "schema_version": SCHEMA_VERSION,
        "ok": true,
        "command": "revoke-grant",
        "scope_key": scope_key,
        "skill_id": skill_id,
        "capability": capability,
        "revoked_by": revoked_by,
        "revoked_rows": report.revoked_rows,
        "policy_event_id": policy_event_id,
        "authority": "policy_gate_only",
        "execution_authority_in_rust": false,
        "hub_executes_third_party_code": false,
    })
    .to_string())
}

pub fn policy_json_from_parts(
    config: &HubConfig,
    scope_key: String,
    skill_id: String,
) -> Result<String, String> {
    ensure_skill_policy_db(config)?;
    let scope_key = public_token_or_default(&scope_key, "default")?;
    let skill_id = public_token_required(&skill_id, "skill_id")?;
    let binding = read_skill_policy_binding(&config.db_path, &scope_key, &skill_id)
        .map_err(|err| format!("skill policy read failed: {err}"))?;
    Ok(json!({
        "schema_version": SCHEMA_VERSION,
        "ok": true,
        "command": "policy",
        "policy": {
            "scope_key": binding.scope_key,
            "skill_id": binding.skill_id,
            "pinned": binding.pinned,
            "granted_capabilities": binding.granted_capabilities,
            "authority": "policy_gate_only",
            "execution_authority_in_rust": false,
        }
    })
    .to_string())
}

pub fn policy_events_json_from_parts(
    config: &HubConfig,
    scope_key: Option<String>,
    skill_id: Option<String>,
    limit: usize,
) -> Result<String, String> {
    ensure_skill_policy_db(config)?;
    let scope_key = optional_public_token(scope_key)?;
    let skill_id = optional_public_token(skill_id)?;
    let summary = read_skill_policy_event_summary(
        &config.db_path,
        scope_key.as_deref(),
        skill_id.as_deref(),
        limit,
    )
    .map_err(|err| format!("skill policy events read failed: {err}"))?;
    Ok(json!({
        "schema_version": SCHEMA_VERSION,
        "ok": true,
        "command": "policy-events",
        "policy_events": policy_events_to_value(&summary, limit),
    })
    .to_string())
}

pub fn policy_events_prune_json_from_parts(
    config: &HubConfig,
    max_rows: usize,
) -> Result<String, String> {
    ensure_skill_policy_db(config)?;
    let report = prune_skill_policy_events_by_max_rows(&config.db_path, max_rows)
        .map_err(|err| format!("skill policy events prune failed: {err}"))?;
    Ok(json!({
        "schema_version": SCHEMA_VERSION,
        "ok": true,
        "command": "policy-events-prune",
        "policy_events_prune": {
            "schema_version": SKILL_POLICY_EVENTS_PRUNE_SCHEMA,
            "max_rows": report.max_rows,
            "deleted_rows": report.deleted_rows,
            "remaining_rows": report.remaining_rows,
            "authority": "policy_gate_only",
            "execution_authority_in_rust": false,
            "hub_executes_third_party_code": false,
            "detail_json_included": false,
        }
    })
    .to_string())
}

pub fn audit_json_from_parts(
    config: &HubConfig,
    scope_key: Option<String>,
    skill_id: Option<String>,
    limit: usize,
) -> Result<String, String> {
    ensure_skill_policy_db(config)?;
    let scope_key = optional_public_token(scope_key)?;
    let skill_id = optional_public_token(skill_id)?;
    let summary = read_skill_preflight_audit_summary(
        &config.db_path,
        scope_key.as_deref(),
        skill_id.as_deref(),
        limit,
    )
    .map_err(|err| format!("skill preflight audit read failed: {err}"))?;
    Ok(json!({
        "schema_version": SCHEMA_VERSION,
        "ok": true,
        "command": "audit",
        "audit": audit_summary_to_value(&summary, limit),
    })
    .to_string())
}

pub fn audit_prune_json_from_parts(config: &HubConfig, max_rows: usize) -> Result<String, String> {
    ensure_skill_policy_db(config)?;
    let report = prune_skill_preflight_audit_by_max_rows(&config.db_path, max_rows)
        .map_err(|err| format!("skill preflight audit prune failed: {err}"))?;
    Ok(json!({
        "schema_version": SCHEMA_VERSION,
        "ok": true,
        "command": "audit-prune",
        "audit_prune": {
            "schema_version": SKILL_PREFLIGHT_AUDIT_PRUNE_SCHEMA,
            "max_rows": report.max_rows,
            "deleted_rows": report.deleted_rows,
            "remaining_rows": report.remaining_rows,
            "authority": "policy_gate_only",
            "execution_authority_in_rust": false,
            "hub_executes_third_party_code": false,
            "detail_json_included": false,
        }
    })
    .to_string())
}

pub fn preflight_json_from_request(
    config: &HubConfig,
    skills_dir: PathBuf,
    mut request: SkillPreflightRequest,
) -> Result<String, String> {
    ensure_skill_policy_db(config)?;
    merge_durable_policy(config, &mut request)?;
    let catalog = scan_skill_catalog(&skills_dir);
    let decision = evaluate_skill_preflight(&catalog, request);
    write_preflight_audit(config, &decision)?;
    Ok(json!({
        "schema_version": SCHEMA_VERSION,
        "ok": true,
        "command": "preflight",
        "preflight": preflight_to_value(&decision),
    })
    .to_string())
}

pub fn preflight_json_from_value(config: &HubConfig, body: Value) -> Result<String, String> {
    let skills_dir = value_string(&body, "skills_dir")
        .or_else(|| value_string(&body, "skillsDir"))
        .map(PathBuf::from)
        .unwrap_or_else(|| skills_dir_from_env(config));
    let request = SkillPreflightRequest {
        request_id: value_string(&body, "request_id")
            .or_else(|| value_string(&body, "requestId"))
            .unwrap_or_default(),
        audit_ref: value_string(&body, "audit_ref")
            .or_else(|| value_string(&body, "auditRef"))
            .unwrap_or_default(),
        scope_key: value_string(&body, "scope_key")
            .or_else(|| value_string(&body, "scopeKey"))
            .unwrap_or_else(|| "default".to_string()),
        skill_id: value_string(&body, "skill_id")
            .or_else(|| value_string(&body, "skillId"))
            .unwrap_or_default(),
        requested_capabilities: value_string_list(&body, "requested_capabilities")
            .or_else(|| value_string_list(&body, "requestedCapabilities"))
            .unwrap_or_default(),
        pinned_skill_ids: value_string_list(&body, "pinned_skill_ids")
            .or_else(|| value_string_list(&body, "pinnedSkillIds"))
            .unwrap_or_default(),
        granted_capabilities: value_string_list(&body, "granted_capabilities")
            .or_else(|| value_string_list(&body, "grantedCapabilities"))
            .unwrap_or_default(),
    };
    preflight_json_from_request(config, skills_dir, request)
}

pub fn skills_dir_from_env(config: &HubConfig) -> PathBuf {
    env::var("XHUB_RUST_SKILLS_DIR")
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| config.root_dir.join("skills"))
}

pub fn help_json() -> String {
    json!({
        "schema_version": SCHEMA_VERSION,
        "ok": true,
        "commands": ["catalog", "readiness", "policy-readiness", "pin", "grant", "unpin", "revoke-grant", "policy", "policy-events", "policy-events-prune", "audit", "audit-prune", "preflight"],
        "catalog_schema": SKILL_CATALOG_SCHEMA,
        "readiness_schema": SKILL_READINESS_SCHEMA,
        "preflight_schema": SKILL_PREFLIGHT_SCHEMA,
        "preflight_audit_schema": SKILL_PREFLIGHT_AUDIT_SCHEMA,
        "preflight_audit_summary_schema": SKILL_PREFLIGHT_AUDIT_SUMMARY_SCHEMA,
        "preflight_audit_prune_schema": SKILL_PREFLIGHT_AUDIT_PRUNE_SCHEMA,
        "policy_events_schema": SKILL_POLICY_EVENTS_SCHEMA,
        "policy_events_prune_schema": SKILL_POLICY_EVENTS_PRUNE_SCHEMA,
        "policy_store_readiness_schema": SKILL_POLICY_STORE_READINESS_SCHEMA,
        "policy_source": SKILL_POLICY_SOURCE,
        "authority": "policy_gate_only",
        "execution_authority_in_rust": false,
        "hub_executes_third_party_code": false,
        "requires_pin_or_grant": true,
        "flags": [
            "--skills-dir",
            "--scope-key",
            "--skill-id",
            "--capability",
            "--actor",
            "--revoked-by",
            "--requested-capabilities",
            "--pinned-skill-ids",
            "--granted-capabilities",
            "--request-id",
            "--audit-ref",
            "--limit",
            "--max-rows",
            "--max-preflight-audit-rows",
            "--max-policy-event-rows"
        ],
    })
    .to_string()
}

pub fn catalog_to_value(catalog: &SkillCatalog) -> Value {
    json!({
        "schema_version": SKILL_CATALOG_SCHEMA,
        "source": SKILL_POLICY_SOURCE,
        "ready": catalog.ready,
        "skills_dir": catalog.skills_dir.display().to_string(),
        "skills_dir_exists": catalog.skills_dir_exists,
        "skill_count": catalog.skill_count(),
        "accepted_skill_count": catalog.accepted_count(),
        "blocked_skill_count": catalog.blocked_count(),
        "issue_count": catalog.issues.len(),
        "authority": "policy_gate_only",
        "execution_authority_in_rust": false,
        "hub_executes_third_party_code": catalog.boundary.hub_executes_third_party_code,
        "requires_pin_or_grant": catalog.boundary.requires_pin_or_grant,
        "entries": catalog.entries.iter().map(entry_to_value).collect::<Vec<_>>(),
        "issues": catalog.issues.iter().map(|issue| json!({
            "code": issue.code,
            "path": issue.path,
        })).collect::<Vec<_>>(),
    })
}

pub fn readiness_to_value(catalog: &SkillCatalog) -> Value {
    json!({
        "schema_version": SKILL_READINESS_SCHEMA,
        "source": SKILL_POLICY_SOURCE,
        "ready": catalog.ready,
        "skills_dir": catalog.skills_dir.display().to_string(),
        "skills_dir_exists": catalog.skills_dir_exists,
        "skill_count": catalog.skill_count(),
        "accepted_skill_count": catalog.accepted_count(),
        "blocked_skill_count": catalog.blocked_count(),
        "issue_count": catalog.issues.len(),
        "authority": "policy_gate_only",
        "catalog_shadow_http": true,
        "execution_authority_in_rust": false,
        "hub_executes_third_party_code": catalog.boundary.hub_executes_third_party_code,
        "requires_pin_or_grant": catalog.boundary.requires_pin_or_grant,
        "deny_code": if catalog.ready { "" } else { "skills_catalog_not_ready" },
    })
}

pub fn policy_store_readiness_to_value(
    summary: &SkillPolicyStoreSummary,
    max_preflight_audit_rows: i64,
    max_policy_event_rows: i64,
) -> Value {
    let mut issue_codes = Vec::new();
    if summary.preflight_audit_count > max_preflight_audit_rows {
        issue_codes.push("preflight_audit_rows_exceed_limit");
    }
    if summary.policy_event_count > max_policy_event_rows {
        issue_codes.push("policy_event_rows_exceed_limit");
    }
    let ready = issue_codes.is_empty();
    json!({
        "schema_version": SKILL_POLICY_STORE_READINESS_SCHEMA,
        "source": SKILL_POLICY_SOURCE,
        "ready": ready,
        "issue_codes": issue_codes,
        "active_pin_count": summary.active_pin_count,
        "active_grant_count": summary.active_grant_count,
        "preflight_audit_count": summary.preflight_audit_count,
        "policy_event_count": summary.policy_event_count,
        "latest_preflight_audit_ms": summary.latest_preflight_audit_ms,
        "latest_policy_event_ms": summary.latest_policy_event_ms,
        "max_preflight_audit_rows": max_preflight_audit_rows,
        "max_policy_event_rows": max_policy_event_rows,
        "authority": "policy_gate_only",
        "execution_authority_in_rust": false,
        "hub_executes_third_party_code": false,
        "detail_json_included": false,
    })
}

fn entry_to_value(entry: &SkillCatalogEntry) -> Value {
    json!({
        "skill_id": entry.skill_id,
        "display_name": entry.display_name,
        "directory_name": entry.directory_name,
        "manifest_path": entry.manifest_path,
        "manifest_kind": entry.manifest_kind.as_str(),
        "status": entry.status.as_str(),
        "reason_codes": entry.reason_codes,
        "capability_tags": entry.capability_tags,
        "requires_pin_or_grant": entry.requires_pin_or_grant,
        "hub_executes_third_party_code": entry.hub_executes_third_party_code,
    })
}

pub fn preflight_to_value(decision: &SkillPreflightDecision) -> Value {
    json!({
        "schema_version": decision.schema_version,
        "source": decision.source,
        "allowed": decision.allowed,
        "decision": decision.decision,
        "reason_codes": decision.reason_codes,
        "request_id": decision.request_id,
        "audit_ref": decision.audit_ref,
        "scope_key": decision.scope_key,
        "skill_id": decision.skill_id,
        "skill_found": decision.skill_found,
        "skill_status": decision.skill_status,
        "requested_capabilities": decision.requested_capabilities,
        "declared_capabilities": decision.declared_capabilities,
        "granted_capabilities": decision.granted_capabilities,
        "missing_capabilities": decision.missing_capabilities,
        "undeclared_capabilities": decision.undeclared_capabilities,
        "pinned": decision.pinned,
        "requires_pin_or_grant": decision.requires_pin_or_grant,
        "execution_authority_in_rust": decision.execution_authority_in_rust,
        "hub_executes_third_party_code": decision.hub_executes_third_party_code,
        "audit_event": {
            "schema_version": decision.audit_schema_version,
            "event_type": "skills.preflight",
            "source": decision.source,
            "request_id": decision.request_id,
            "audit_ref": decision.audit_ref,
            "scope_key": decision.scope_key,
            "skill_id": decision.skill_id,
            "decision": decision.decision,
            "reason_codes": decision.reason_codes,
            "requested_capabilities": decision.requested_capabilities,
            "pinned": decision.pinned,
            "execution_authority_in_rust": decision.execution_authority_in_rust,
            "hub_executes_third_party_code": decision.hub_executes_third_party_code,
        }
    })
}

pub fn audit_summary_to_value(
    summary: &SkillPreflightAuditSummary,
    requested_limit: usize,
) -> Value {
    json!({
        "schema_version": SKILL_PREFLIGHT_AUDIT_SUMMARY_SCHEMA,
        "source": SKILL_POLICY_SOURCE,
        "scope_key": summary.scope_key.clone(),
        "skill_id": summary.skill_id.clone(),
        "total": summary.total,
        "allowed": summary.allowed,
        "denied": summary.denied,
        "latest_created_at_ms": summary.latest_created_at_ms,
        "limit": requested_limit.clamp(1, 500),
        "returned_row_count": summary.rows.len(),
        "detail_json_included": false,
        "authority": "policy_gate_only",
        "execution_authority_in_rust": false,
        "hub_executes_third_party_code": false,
        "rows": summary.rows.iter().map(audit_row_to_value).collect::<Vec<_>>(),
    })
}

fn audit_row_to_value(row: &SkillPreflightAuditRow) -> Value {
    json!({
        "event_id": row.event_id.clone(),
        "created_at_ms": row.created_at_ms,
        "scope_key": row.scope_key.clone(),
        "request_id": row.request_id.clone(),
        "audit_ref": row.audit_ref.clone(),
        "skill_id": row.skill_id.clone(),
        "decision": row.decision.clone(),
        "ok": row.ok,
        "reason_codes": parse_json_or_empty_array(&row.reason_json),
        "detail_json_included": false,
    })
}

pub fn policy_events_to_value(summary: &SkillPolicyEventSummary, requested_limit: usize) -> Value {
    json!({
        "schema_version": SKILL_POLICY_EVENTS_SCHEMA,
        "source": SKILL_POLICY_SOURCE,
        "scope_key": summary.scope_key.clone(),
        "skill_id": summary.skill_id.clone(),
        "total": summary.total,
        "latest_created_at_ms": summary.latest_created_at_ms,
        "limit": requested_limit.clamp(1, 500),
        "returned_row_count": summary.rows.len(),
        "detail_json_included": false,
        "authority": "policy_gate_only",
        "execution_authority_in_rust": false,
        "hub_executes_third_party_code": false,
        "rows": summary.rows.iter().map(policy_event_row_to_value).collect::<Vec<_>>(),
    })
}

fn policy_event_row_to_value(row: &SkillPolicyEventRow) -> Value {
    json!({
        "event_id": row.event_id.clone(),
        "created_at_ms": row.created_at_ms,
        "operation": row.operation.clone(),
        "scope_key": row.scope_key.clone(),
        "skill_id": row.skill_id.clone(),
        "capability": row.capability.clone(),
        "actor": row.actor.clone(),
        "result": row.result.clone(),
        "detail_json_included": false,
    })
}

fn value_string(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
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

fn parse_json_or_empty_array(raw: &str) -> Value {
    serde_json::from_str::<Value>(raw).unwrap_or_else(|_| json!([]))
}

fn ensure_skill_policy_db(config: &HubConfig) -> Result<(), String> {
    apply_baseline_migrations(&config.db_path)
        .map(|_| ())
        .map_err(|err| format!("skill policy migration failed: {err}"))
}

fn merge_durable_policy(
    config: &HubConfig,
    request: &mut SkillPreflightRequest,
) -> Result<(), String> {
    let scope_key = public_token_or_default(&request.scope_key, "default")?;
    let skill_id = public_token_required(&request.skill_id, "skill_id")?;
    let binding = read_skill_policy_binding(&config.db_path, &scope_key, &skill_id)
        .map_err(|err| format!("skill policy read failed: {err}"))?;
    request.scope_key = scope_key;
    if binding.pinned
        && !request
            .pinned_skill_ids
            .iter()
            .any(|item| item == &skill_id)
    {
        request.pinned_skill_ids.push(skill_id);
    }
    for capability in binding.granted_capabilities {
        if !request
            .granted_capabilities
            .iter()
            .any(|item| item == &capability)
        {
            request.granted_capabilities.push(capability);
        }
    }
    Ok(())
}

fn write_preflight_audit(
    config: &HubConfig,
    decision: &SkillPreflightDecision,
) -> Result<(), String> {
    let event_id = unique_skill_event_id();
    let reason_json = serde_json::to_string(&decision.reason_codes)
        .map_err(|err| format!("skill preflight reason serialize failed: {err}"))?;
    let detail_json = serde_json::to_string(&preflight_to_value(decision))
        .map_err(|err| format!("skill preflight detail serialize failed: {err}"))?;
    write_skill_preflight_audit(
        &config.db_path,
        &SkillPreflightAuditRecord {
            event_id,
            scope_key: decision.scope_key.clone(),
            request_id: decision.request_id.clone(),
            audit_ref: decision.audit_ref.clone(),
            skill_id: decision.skill_id.clone(),
            decision: decision.decision.clone(),
            ok: decision.allowed,
            reason_json,
            detail_json,
        },
    )
    .map_err(|err| format!("skill preflight audit write failed: {err}"))
}

fn write_policy_event(
    config: &HubConfig,
    operation: &str,
    scope_key: &str,
    skill_id: &str,
    capability: Option<&str>,
    actor: &str,
    result: &str,
    detail: Value,
) -> Result<String, String> {
    let event_id = unique_skill_policy_event_id();
    let detail_json = serde_json::to_string(&detail)
        .map_err(|err| format!("skill policy event detail serialize failed: {err}"))?;
    write_skill_policy_event(
        &config.db_path,
        &SkillPolicyEventRecord {
            event_id: event_id.clone(),
            operation: operation.to_string(),
            scope_key: scope_key.to_string(),
            skill_id: skill_id.to_string(),
            capability: capability.map(str::to_string),
            actor: actor.to_string(),
            result: result.to_string(),
            detail_json,
        },
    )
    .map_err(|err| format!("skill policy event write failed: {err}"))?;
    Ok(event_id)
}

fn optional_public_token(raw: Option<String>) -> Result<Option<String>, String> {
    let Some(value) = raw else {
        return Ok(None);
    };
    let value = public_token_or_default(&value, "")?;
    if value.is_empty() {
        Ok(None)
    } else {
        Ok(Some(value))
    }
}

fn public_token_required(raw: &str, label: &str) -> Result<String, String> {
    let value = public_token_or_default(raw, "")?;
    if value.is_empty() {
        Err(format!("{label} is required"))
    } else {
        Ok(value)
    }
}

fn public_token_or_default(raw: &str, fallback: &str) -> Result<String, String> {
    if contains_secret_pattern(raw) {
        return Err("secret-shaped policy input denied".to_string());
    }
    let value = raw.trim();
    let chosen = if value.is_empty() { fallback } else { value };
    let out = chosen
        .chars()
        .filter(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '-' | '_' | '.' | ':' | '/'))
        .collect::<String>();
    Ok(out.chars().take(128).collect())
}

fn contains_secret_pattern(raw: &str) -> bool {
    let lower = raw.to_ascii_lowercase();
    [
        "api_key",
        "apikey",
        "access_key",
        "secret_key",
        "refresh_token",
        "client_secret",
        "private_key",
        "authorization: bearer",
        "sk-",
    ]
    .iter()
    .any(|needle| lower.contains(needle))
}

fn unique_skill_event_id() -> String {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis();
    let seq = SKILL_EVENT_COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("skill_preflight_{now}_{}_{seq}", std::process::id())
}

fn unique_skill_policy_event_id() -> String {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis();
    let seq = SKILL_EVENT_COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("skill_policy_{now}_{}_{seq}", std::process::id())
}

fn parse_usize_flag(
    raw: Option<String>,
    fallback: usize,
    min: usize,
    max: usize,
    label: &str,
) -> Result<usize, String> {
    let Some(raw) = raw else {
        return Ok(fallback.clamp(min, max));
    };
    let parsed = raw
        .trim()
        .parse::<usize>()
        .map_err(|_| format!("{label} must be an integer"))?;
    Ok(parsed.clamp(min, max))
}

fn parse_i64_flag(
    raw: Option<String>,
    fallback: i64,
    min: i64,
    max: i64,
    label: &str,
) -> Result<i64, String> {
    let Some(raw) = raw else {
        return Ok(fallback.clamp(min, max));
    };
    let parsed = raw
        .trim()
        .parse::<i64>()
        .map_err(|_| format!("{label} must be an integer"))?;
    Ok(parsed.clamp(min, max))
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
            "xhubd_skills_bridge_{label}_{}_{}",
            std::process::id(),
            now
        ))
    }

    #[test]
    fn readiness_json_keeps_execution_authority_false() {
        let dir = temp_dir("ready");
        let skill = dir.join("memory-core");
        fs::create_dir_all(&skill).expect("mkdir");
        fs::write(
            skill.join("SKILL.md"),
            "# Memory Core\nMemory retrieval helper.\n",
        )
        .expect("write");
        let raw = readiness_json_from_dir(dir.clone()).expect("readiness");
        let value: Value = serde_json::from_str(&raw).expect("json");
        assert_eq!(value["readiness"]["ready"], true);
        assert_eq!(value["readiness"]["execution_authority_in_rust"], false);
        assert_eq!(value["readiness"]["hub_executes_third_party_code"], false);
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn preflight_json_returns_audit_preview_without_execution_authority() {
        let dir = temp_dir("preflight");
        let skill = dir.join("memory-core");
        fs::create_dir_all(&skill).expect("mkdir");
        fs::write(
            skill.join("skill.json"),
            r#"{"id":"memory-core","name":"Memory Core","capabilities":["memory.read"]}"#,
        )
        .expect("write");
        let config = test_config(dir.clone());
        let raw = preflight_json_from_request(
            &config,
            dir.clone(),
            SkillPreflightRequest {
                request_id: "req-1".to_string(),
                skill_id: "memory-core".to_string(),
                requested_capabilities: vec!["memory.read".to_string()],
                pinned_skill_ids: vec!["memory-core".to_string()],
                granted_capabilities: vec!["memory.read".to_string()],
                ..Default::default()
            },
        )
        .expect("preflight");
        let value: Value = serde_json::from_str(&raw).expect("json");
        assert_eq!(value["preflight"]["allowed"], true);
        assert_eq!(
            value["preflight"]["audit_event"]["schema_version"],
            SKILL_PREFLIGHT_AUDIT_SCHEMA
        );
        assert_eq!(value["preflight"]["execution_authority_in_rust"], false);
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn durable_pin_and_grant_allow_preflight_without_request_overrides() {
        let dir = temp_dir("durable_preflight");
        let skill = dir.join("memory-core");
        fs::create_dir_all(&skill).expect("mkdir");
        fs::write(
            skill.join("skill.json"),
            r#"{"id":"memory-core","name":"Memory Core","capabilities":["memory.read"]}"#,
        )
        .expect("write");
        let config = test_config(dir.clone());
        pin_json_from_parts(
            &config,
            "project:demo".to_string(),
            "memory-core".to_string(),
            "test".to_string(),
        )
        .expect("pin");
        grant_json_from_parts(
            &config,
            "project:demo".to_string(),
            "memory-core".to_string(),
            "memory.read".to_string(),
            "test".to_string(),
        )
        .expect("grant");
        let raw = preflight_json_from_request(
            &config,
            dir.clone(),
            SkillPreflightRequest {
                request_id: "req-2".to_string(),
                scope_key: "project:demo".to_string(),
                skill_id: "memory-core".to_string(),
                requested_capabilities: vec!["memory.read".to_string()],
                ..Default::default()
            },
        )
        .expect("preflight");
        let value: Value = serde_json::from_str(&raw).expect("json");
        assert_eq!(value["preflight"]["allowed"], true);
        assert_eq!(value["preflight"]["pinned"], true);
        assert_eq!(value["preflight"]["granted_capabilities"][0], "memory.read");

        let raw = revoke_grant_json_from_parts(
            &config,
            "project:demo".to_string(),
            "memory-core".to_string(),
            "memory.read".to_string(),
            "test".to_string(),
        )
        .expect("revoke grant");
        let value: Value = serde_json::from_str(&raw).expect("json");
        assert_eq!(value["revoked_rows"], 1);
        let raw = unpin_json_from_parts(
            &config,
            "project:demo".to_string(),
            "memory-core".to_string(),
            "test".to_string(),
        )
        .expect("unpin");
        let value: Value = serde_json::from_str(&raw).expect("json");
        assert_eq!(value["revoked_rows"], 1);

        let raw = policy_json_from_parts(
            &config,
            "project:demo".to_string(),
            "memory-core".to_string(),
        )
        .expect("policy after revoke");
        let value: Value = serde_json::from_str(&raw).expect("json");
        assert_eq!(value["policy"]["pinned"], false);
        assert_eq!(
            value["policy"]["granted_capabilities"]
                .as_array()
                .unwrap()
                .len(),
            0
        );

        let raw = preflight_json_from_request(
            &config,
            dir.clone(),
            SkillPreflightRequest {
                request_id: "req-3".to_string(),
                scope_key: "project:demo".to_string(),
                skill_id: "memory-core".to_string(),
                requested_capabilities: vec!["memory.read".to_string()],
                ..Default::default()
            },
        )
        .expect("preflight after revoke");
        let value: Value = serde_json::from_str(&raw).expect("json");
        assert_eq!(value["preflight"]["allowed"], false);
        assert_eq!(value["preflight"]["pinned"], false);

        let raw = policy_events_json_from_parts(
            &config,
            Some("project:demo".to_string()),
            Some("memory-core".to_string()),
            10,
        )
        .expect("policy events");
        let value: Value = serde_json::from_str(&raw).expect("json");
        assert_eq!(
            value["policy_events"]["schema_version"],
            SKILL_POLICY_EVENTS_SCHEMA
        );
        assert_eq!(value["policy_events"]["total"], 4);
        assert_eq!(value["policy_events"]["detail_json_included"], false);
        assert!(!json_contains_key(&value, "detail_json"));

        let raw = policy_events_prune_json_from_parts(&config, 2).expect("policy events prune");
        let value: Value = serde_json::from_str(&raw).expect("json");
        assert_eq!(
            value["policy_events_prune"]["schema_version"],
            SKILL_POLICY_EVENTS_PRUNE_SCHEMA
        );
        assert_eq!(value["policy_events_prune"]["deleted_rows"], 2);
        assert_eq!(value["policy_events_prune"]["remaining_rows"], 2);

        let raw =
            policy_store_readiness_json_from_parts(&config, 10, 10).expect("policy readiness");
        let value: Value = serde_json::from_str(&raw).expect("json");
        assert_eq!(
            value["policy_readiness"]["schema_version"],
            SKILL_POLICY_STORE_READINESS_SCHEMA
        );
        assert_eq!(value["policy_readiness"]["ready"], true);
        assert_eq!(value["policy_readiness"]["preflight_audit_count"], 2);
        assert_eq!(value["policy_readiness"]["policy_event_count"], 2);
        assert_eq!(value["policy_readiness"]["detail_json_included"], false);
        assert!(!json_contains_key(&value, "detail_json"));

        let raw = policy_store_readiness_json_from_parts(&config, 1, 1)
            .expect("policy readiness over limit");
        let value: Value = serde_json::from_str(&raw).expect("json");
        assert_eq!(value["policy_readiness"]["ready"], false);
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn audit_json_reports_and_prunes_preflight_rows_without_detail_json() {
        let dir = temp_dir("audit_summary");
        let skill = dir.join("memory-core");
        fs::create_dir_all(&skill).expect("mkdir");
        fs::write(
            skill.join("skill.json"),
            r#"{"id":"memory-core","name":"Memory Core","capabilities":["memory"]}"#,
        )
        .expect("write");
        let config = test_config(dir.clone());
        preflight_json_from_request(
            &config,
            dir.clone(),
            SkillPreflightRequest {
                request_id: "req-deny".to_string(),
                scope_key: "project:demo".to_string(),
                skill_id: "memory-core".to_string(),
                requested_capabilities: vec!["memory".to_string()],
                ..Default::default()
            },
        )
        .expect("deny preflight");
        pin_json_from_parts(
            &config,
            "project:demo".to_string(),
            "memory-core".to_string(),
            "test".to_string(),
        )
        .expect("pin");
        grant_json_from_parts(
            &config,
            "project:demo".to_string(),
            "memory-core".to_string(),
            "memory".to_string(),
            "test".to_string(),
        )
        .expect("grant");
        preflight_json_from_request(
            &config,
            dir.clone(),
            SkillPreflightRequest {
                request_id: "req-allow".to_string(),
                scope_key: "project:demo".to_string(),
                skill_id: "memory-core".to_string(),
                requested_capabilities: vec!["memory".to_string()],
                ..Default::default()
            },
        )
        .expect("allow preflight");

        let raw = audit_json_from_parts(
            &config,
            Some("project:demo".to_string()),
            Some("memory-core".to_string()),
            10,
        )
        .expect("audit");
        let value: Value = serde_json::from_str(&raw).expect("json");
        assert_eq!(
            value["audit"]["schema_version"],
            SKILL_PREFLIGHT_AUDIT_SUMMARY_SCHEMA
        );
        assert_eq!(value["audit"]["total"], 2);
        assert_eq!(value["audit"]["allowed"], 1);
        assert_eq!(value["audit"]["denied"], 1);
        assert_eq!(value["audit"]["detail_json_included"], false);
        assert!(!json_contains_key(&value, "detail_json"));

        let raw = audit_prune_json_from_parts(&config, 1).expect("prune");
        let value: Value = serde_json::from_str(&raw).expect("json");
        assert_eq!(value["audit_prune"]["deleted_rows"], 1);
        assert_eq!(value["audit_prune"]["remaining_rows"], 1);
        let _ = fs::remove_dir_all(dir);
    }

    fn test_config(root: PathBuf) -> HubConfig {
        HubConfig {
            root_dir: root.clone(),
            host: "127.0.0.1".to_string(),
            http_port: 0,
            grpc_port: 0,
            db_path: root.join("hub.sqlite3"),
            runtime_base_dir: PathBuf::new(),
            proto_path: root.join("hub_protocol_v1.proto"),
            canonical_proto_path: root.join("hub_protocol_v1.proto"),
            http_access_key: None,
            http_access_key_source: String::new(),
            http_access_key_required: false,
        }
    }

    fn json_contains_key(value: &Value, key: &str) -> bool {
        match value {
            Value::Object(map) => map
                .iter()
                .any(|(item_key, item)| item_key == key || json_contains_key(item, key)),
            Value::Array(items) => items.iter().any(|item| json_contains_key(item, key)),
            _ => false,
        }
    }
}
