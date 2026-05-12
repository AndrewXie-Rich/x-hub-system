use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::UNIX_EPOCH;

use serde_json::{json, Value};
use xhub_core::{now_ms, HubConfig};
use xhub_db::{
    apply_baseline_migrations, read_shadow_compare_report_summary, write_shadow_compare_report,
    ShadowCompareReport, ShadowCompareReportSummary,
};
use xhub_provider::remote_model_inventory_from_runtime_base_dir;
use xhub_runtime::local_model_inventory_rows;

const MODEL_INVENTORY_SCHEMA_VERSION: &str = "xhub.model_inventory.v1";
const MODEL_ROUTE_SCHEMA_VERSION: &str = "xhub.model_route_decision.v1";
const MODEL_ROUTE_DIAGNOSTICS_SCHEMA_VERSION: &str = "xhub.model_route_diagnostics.v1";
const MODEL_BRIDGE_SCHEMA_VERSION: &str = "xhub.model_bridge.v1";
const MODEL_INVENTORY_COMPONENT: &str = "model_inventory";
const MODEL_ROUTE_COMPONENT: &str = "model_route";
static MODEL_INVENTORY_COMPARE_REPORT_COUNTER: AtomicU64 = AtomicU64::new(1);

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
        "inventory" => inventory_json(config, FlagArgs::parse(&args[1..])?),
        "route" => route_json(config, FlagArgs::parse(&args[1..])?),
        "compare" => compare_json(config, FlagArgs::parse(&args[1..])?),
        "reports" => reports_json(config, FlagArgs::parse(&args[1..])?),
        "readiness" | "cutover-readiness" => readiness_json(config, FlagArgs::parse(&args[1..])?),
        "diagnostics" | "route-diagnostics" => {
            diagnostics_json(config, FlagArgs::parse(&args[1..])?)
        }
        other => Err(format!("unknown model command: {other}")),
    }
}

fn inventory_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let runtime_base_dir = flags
        .optional("runtime-base-dir")
        .map(PathBuf::from)
        .unwrap_or_else(|| config.runtime_base_dir.clone());
    let now = flags.optional_u128("now-ms")?.unwrap_or_else(now_ms);
    inventory_json_from_parts(config, Some(runtime_base_dir), Some(now))
}

pub fn inventory_json_from_parts(
    config: &HubConfig,
    runtime_base_dir: Option<PathBuf>,
    inventory_now_ms: Option<u128>,
) -> Result<String, String> {
    inventory_value_from_parts(config, runtime_base_dir, inventory_now_ms)
        .map(|value| value.to_string())
}

fn inventory_value_from_parts(
    config: &HubConfig,
    runtime_base_dir: Option<PathBuf>,
    inventory_now_ms: Option<u128>,
) -> Result<Value, String> {
    let runtime_base_dir = runtime_base_dir.unwrap_or_else(|| config.runtime_base_dir.clone());
    let now = inventory_now_ms.unwrap_or_else(now_ms);
    let remote_models = remote_model_inventory_from_runtime_base_dir(&runtime_base_dir, now)
        .map_err(|err| format!("model inventory remote provider read failed: {err}"))?;
    let local_models = local_model_inventory_rows(&runtime_base_dir);
    Ok(json!({
        "schema_version": MODEL_INVENTORY_SCHEMA_VERSION,
        "ok": true,
        "command": "inventory",
        "runtime_base_dir": runtime_base_dir.display().to_string(),
        "updated_at_ms": now,
        "remote_models": remote_models,
        "local_models": local_models,
    }))
}

fn route_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let runtime_base_dir = flags
        .optional("runtime-base-dir")
        .map(PathBuf::from)
        .unwrap_or_else(|| config.runtime_base_dir.clone());
    let now = flags.optional_u128("now-ms")?.unwrap_or_else(now_ms);
    let request = ModelRouteRequest {
        task_type: flags
            .optional("task-type")
            .or_else(|| flags.optional("task"))
            .unwrap_or_else(|| "text_generate".to_string()),
        model_id: flags
            .optional("model-id")
            .or_else(|| flags.optional("preferred-model-id"))
            .unwrap_or_else(|| "auto".to_string()),
        required_capabilities: first_non_empty_vec(vec![
            flags.optional_list("required-capability"),
            flags.optional_list("required-capabilities"),
            flags.optional_list("capabilities"),
        ]),
        privacy_mode: flags
            .optional("privacy-mode")
            .unwrap_or_else(|| "standard".to_string()),
        cost_preference: flags
            .optional("cost-preference")
            .unwrap_or_else(|| "balanced".to_string()),
    };
    route_json_from_parts(config, Some(runtime_base_dir), request, Some(now))
}

#[derive(Debug, Clone)]
pub struct ModelRouteRequest {
    pub task_type: String,
    pub model_id: String,
    pub required_capabilities: Vec<String>,
    pub privacy_mode: String,
    pub cost_preference: String,
}

pub fn route_json_from_parts(
    config: &HubConfig,
    runtime_base_dir: Option<PathBuf>,
    request: ModelRouteRequest,
    route_now_ms: Option<u128>,
) -> Result<String, String> {
    let runtime_base_dir = runtime_base_dir.unwrap_or_else(|| config.runtime_base_dir.clone());
    let now = route_now_ms.unwrap_or_else(now_ms);
    let remote_models = remote_model_inventory_from_runtime_base_dir(&runtime_base_dir, now)
        .map_err(|err| format!("model route remote provider read failed: {err}"))?;
    let local_models = local_model_inventory_rows(&runtime_base_dir);
    Ok(model_route_decision_json(
        runtime_base_dir.display().to_string(),
        request,
        remote_models,
        local_models,
        now,
    ))
}

fn compare_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let runtime_base_dir = flags
        .optional("runtime-base-dir")
        .map(PathBuf::from)
        .unwrap_or_else(|| config.runtime_base_dir.clone());
    let raw_node_inventory = flags.required("node-inventory-json")?;
    let node_value: Value = serde_json::from_str(&raw_node_inventory)
        .map_err(|err| format!("invalid node-inventory-json: {err}"))?;
    compare_inventory_json_from_parts(
        config,
        Some(runtime_base_dir),
        node_value,
        flags.optional_u128("now-ms")?,
    )
}

pub fn compare_inventory_json_from_parts(
    config: &HubConfig,
    runtime_base_dir: Option<PathBuf>,
    node_value: Value,
    compare_now_ms: Option<u128>,
) -> Result<String, String> {
    apply_baseline_migrations(&config.db_path)
        .map_err(|err| format!("model inventory compare migration failed: {err}"))?;
    let rust_value = inventory_value_from_parts(config, runtime_base_dir, compare_now_ms)?;
    let node_normalized = normalize_model_inventory(&node_value);
    let rust_normalized = normalize_model_inventory(&rust_value);
    let mut mismatches = Vec::new();
    collect_value_mismatches("", &node_normalized, &rust_normalized, &mut mismatches);

    let compared_at_ms = now_ms().min(i64::MAX as u128) as i64;
    let report_id = format!(
        "model_inventory_compare_{}_{}_{}",
        compared_at_ms,
        std::process::id(),
        MODEL_INVENTORY_COMPARE_REPORT_COUNTER.fetch_add(1, Ordering::Relaxed)
    );
    let match_result = if mismatches.is_empty() {
        "match"
    } else {
        "mismatch"
    };
    let rust_status_json = serde_json::to_string(&rust_normalized)
        .map_err(|err| format!("model inventory compare rust normalize failed: {err}"))?;
    let node_status_json = serde_json::to_string(&node_normalized)
        .map_err(|err| format!("model inventory compare node normalize failed: {err}"))?;
    let mismatch_json = serde_json::to_string(&mismatches)
        .map_err(|err| format!("model inventory compare mismatch serialize failed: {err}"))?;

    write_shadow_compare_report(
        &config.db_path,
        &ShadowCompareReport {
            report_id: report_id.clone(),
            component: MODEL_INVENTORY_COMPONENT.to_string(),
            compared_at_ms,
            match_result: match_result.to_string(),
            rust_status_json,
            node_status_json,
            mismatch_json,
        },
    )
    .map_err(|err| format!("model inventory compare report write failed: {err}"))?;

    Ok(json!({
        "schema_version": MODEL_BRIDGE_SCHEMA_VERSION,
        "ok": true,
        "command": "compare",
        "component": MODEL_INVENTORY_COMPONENT,
        "report_id": report_id,
        "match": mismatches.is_empty(),
        "match_result": match_result,
        "inventory_schema_version": MODEL_INVENTORY_SCHEMA_VERSION,
        "node": node_normalized,
        "rust": rust_normalized,
        "mismatches": mismatches,
    })
    .to_string())
}

fn reports_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let limit = flags.optional_usize("limit")?.unwrap_or(20);
    reports_json_from_parts(config, limit)
}

pub fn reports_json_from_parts(config: &HubConfig, limit: usize) -> Result<String, String> {
    apply_baseline_migrations(&config.db_path)
        .map_err(|err| format!("model inventory reports migration failed: {err}"))?;
    let summary =
        read_shadow_compare_report_summary(&config.db_path, MODEL_INVENTORY_COMPONENT, limit)
            .map_err(|err| format!("model inventory reports read failed: {err}"))?;
    Ok(report_summary_json(&summary))
}

fn readiness_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let limit = flags.optional_usize("limit")?.unwrap_or(20);
    let min_compare_reports = flags
        .optional_i64("min-compare-reports")?
        .unwrap_or(10)
        .max(0);
    let max_mismatches = flags.optional_i64("max-mismatches")?.unwrap_or(0).max(0);
    readiness_json_from_parts(config, min_compare_reports, max_mismatches, limit)
}

pub fn readiness_json_from_parts(
    config: &HubConfig,
    min_compare_reports: i64,
    max_mismatches: i64,
    limit: usize,
) -> Result<String, String> {
    apply_baseline_migrations(&config.db_path)
        .map_err(|err| format!("model inventory readiness migration failed: {err}"))?;
    let min_compare_reports = min_compare_reports.max(0);
    let max_mismatches = max_mismatches.max(0);
    let summary =
        read_shadow_compare_report_summary(&config.db_path, MODEL_INVENTORY_COMPONENT, limit)
            .map_err(|err| format!("model inventory readiness report read failed: {err}"))?;
    let total_ok = summary.total >= min_compare_reports;
    let mismatch_ok = summary.mismatched <= max_mismatches;
    let ready = total_ok && mismatch_ok;
    Ok(json!({
        "schema_version": MODEL_BRIDGE_SCHEMA_VERSION,
        "ok": true,
        "command": "readiness",
        "component": MODEL_INVENTORY_COMPONENT,
        "ready": ready,
        "decision": if ready { "ready" } else { "not_ready" },
        "generated_at_ms": now_ms().min(i64::MAX as u128) as i64,
        "thresholds": {
            "min_compare_reports": min_compare_reports,
            "max_mismatches": max_mismatches,
        },
        "checks": [
            {
                "name": "model_inventory_min_reports",
                "ok": total_ok,
                "actual": summary.total,
                "threshold": min_compare_reports,
                "detail": "model inventory shadow compare evidence count"
            },
            {
                "name": "model_inventory_mismatches",
                "ok": mismatch_ok,
                "actual": summary.mismatched,
                "threshold": max_mismatches,
                "detail": "model inventory mismatches must stay within threshold"
            }
        ],
        "compare": {
            "component": summary.component,
            "total": summary.total,
            "matched": summary.matched,
            "mismatched": summary.mismatched,
            "latest_compared_at_ms": summary.latest_compared_at_ms,
        }
    })
    .to_string())
}

fn model_route_decision_json(
    runtime_base_dir: String,
    request: ModelRouteRequest,
    remote_models: Vec<xhub_provider::RemoteModelInventoryRow>,
    local_models: Vec<xhub_runtime::LocalModelInventoryRow>,
    updated_at_ms: u128,
) -> String {
    let task_type = normalized_token(&request.task_type).replace('_', ".");
    let requested_model_id = normalized_token(&request.model_id);
    let required_capabilities = normalize_required_capabilities(&request);
    let privacy_mode = normalized_token(&request.privacy_mode).replace('_', "-");
    let cost_preference = normalized_token(&request.cost_preference).replace('_', "-");
    let remote_allowed = !matches!(
        privacy_mode.as_str(),
        "local-only" | "offline" | "private" | "privacy-local"
    );
    let local_allowed = !matches!(privacy_mode.as_str(), "remote-only" | "paid-only");
    let high_risk = is_high_risk_task(&task_type, &required_capabilities);
    let prefer_local = matches!(
        cost_preference.as_str(),
        "prefer-local" | "prefer-free" | "local-first" | "free-first"
    );

    let mut remote_candidates = remote_models
        .iter()
        .map(|row| remote_candidate_json(row, &requested_model_id, remote_allowed))
        .collect::<Vec<Value>>();
    let mut local_candidates = local_models
        .iter()
        .map(|row| {
            local_candidate_json(
                row,
                &requested_model_id,
                local_allowed,
                high_risk,
                &required_capabilities,
            )
        })
        .collect::<Vec<Value>>();

    let mut selected = json!({});
    let mut selected_route_kind = String::new();
    let mut selected_model_id = String::new();
    let mut blocking_reason_code = String::new();

    if prefer_local && local_allowed {
        if let Some((idx, candidate)) = first_selectable_local_candidate(&local_candidates) {
            let candidate = candidate.clone();
            local_candidates[idx]["selected"] = json!(true);
            selected = selected_route_json(&candidate);
            selected_route_kind = "local".to_string();
            selected_model_id = value_string(&candidate, "model_id");
        }
    }

    if selected_model_id.is_empty() && remote_allowed {
        if let Some((idx, candidate)) = first_selectable_remote_candidate(&remote_candidates) {
            let candidate = candidate.clone();
            remote_candidates[idx]["selected"] = json!(true);
            selected = selected_route_json(&candidate);
            selected_route_kind = "remote".to_string();
            selected_model_id = value_string(&candidate, "model_id");
        }
    }

    if selected_model_id.is_empty() && local_allowed {
        if let Some((idx, candidate)) = first_selectable_local_candidate(&local_candidates) {
            let candidate = candidate.clone();
            local_candidates[idx]["selected"] = json!(true);
            selected = selected_route_json(&candidate);
            selected_route_kind = "local".to_string();
            selected_model_id = value_string(&candidate, "model_id");
        } else if high_risk
            && local_candidates.iter().any(|candidate| {
                value_bool(candidate, "candidate_model_match")
                    && !value_bool(candidate, "exact_capability_ok")
            })
        {
            blocking_reason_code = "high_risk_local_fallback_blocked".to_string();
        }
    }

    if selected_model_id.is_empty() && blocking_reason_code.is_empty() {
        blocking_reason_code = fallback_model_route_reason(
            remote_allowed,
            local_allowed,
            &remote_candidates,
            &local_candidates,
        );
    }

    json!({
        "schema_version": MODEL_ROUTE_SCHEMA_VERSION,
        "ok": true,
        "command": "route",
        "runtime_base_dir": runtime_base_dir,
        "updated_at_ms": updated_at_ms,
        "request": {
            "task_type": task_type,
            "model_id": if requested_model_id.is_empty() { "auto" } else { requested_model_id.as_str() },
            "required_capabilities": required_capabilities,
            "privacy_mode": privacy_mode,
            "cost_preference": cost_preference,
        },
        "selected_route_kind": selected_route_kind,
        "selected_model_id": selected_model_id,
        "blocking_reason_code": blocking_reason_code,
        "selected": selected,
        "remote_candidates": remote_candidates,
        "local_candidates": local_candidates,
    })
    .to_string()
}

fn diagnostics_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let limit = flags.optional_usize("limit")?.unwrap_or(3);
    diagnostics_json_from_parts(config, limit)
}

pub fn diagnostics_json_from_parts(config: &HubConfig, limit: usize) -> Result<String, String> {
    let limit = limit.clamp(1, 20);
    let reports_dir = config.root_dir.join("reports");
    let reports_dir_exists = reports_dir.is_dir();
    let authority_plan = route_report_summaries(
        config,
        &reports_dir,
        "authority_plan",
        "model_route_authority_plan_",
        limit,
    );
    let prep_trial = route_report_summaries(
        config,
        &reports_dir,
        "prep_trial",
        "model_route_prep_trial_",
        limit,
    );
    let prep_sustained = route_report_summaries(
        config,
        &reports_dir,
        "prep_sustained",
        "model_route_prep_sustained_",
        limit,
    );
    let candidate_evidence = route_report_summaries(
        config,
        &reports_dir,
        "candidate_evidence",
        "model_route_candidate_evidence_",
        limit,
    );
    let latest_authority_plan = authority_plan.first().cloned().unwrap_or(Value::Null);
    let latest_prep_trial = prep_trial.first().cloned().unwrap_or(Value::Null);
    let latest_prep_sustained = prep_sustained.first().cloned().unwrap_or(Value::Null);
    let latest_candidate_evidence = candidate_evidence.first().cloned().unwrap_or(Value::Null);
    let latest_reports = vec![
        &latest_authority_plan,
        &latest_prep_trial,
        &latest_prep_sustained,
        &latest_candidate_evidence,
    ];
    let production_authority_changes = latest_reports
        .iter()
        .filter(|report| value_bool(report, "production_authority_change"))
        .count();
    let selected_model_authority_enabled_reports = latest_reports
        .iter()
        .filter(|report| value_bool(report, "selected_model_authority_enabled"))
        .count();
    let node_authority_failures = latest_reports
        .iter()
        .filter(|report| report.is_object() && !value_bool(report, "node_authority_preserved"))
        .count();
    let authority_plan_present = latest_authority_plan.is_object();
    let prep_trial_present = latest_prep_trial.is_object();
    let prep_sustained_present = latest_prep_sustained.is_object();
    let authority_plan_ready = value_bool(&latest_authority_plan, "ready");
    let prep_trial_ready = value_bool(&latest_prep_trial, "ready");
    let prep_sustained_ready = value_bool(&latest_prep_sustained, "ready");
    let ready = reports_dir_exists
        && authority_plan_present
        && prep_trial_present
        && prep_sustained_present
        && authority_plan_ready
        && prep_trial_ready
        && prep_sustained_ready
        && production_authority_changes == 0
        && selected_model_authority_enabled_reports == 0
        && node_authority_failures == 0;
    Ok(json!({
        "schema_version": MODEL_ROUTE_DIAGNOSTICS_SCHEMA_VERSION,
        "ok": true,
        "command": "diagnostics",
        "component": MODEL_ROUTE_COMPONENT,
        "read_only": true,
        "diagnostics_only": true,
        "production_authority_change": false,
        "selected_model_authority_enabled": false,
        "node_remains_model_selection_authority": node_authority_failures == 0,
        "ready": ready,
        "decision": if ready { "ready" } else { "not_ready" },
        "generated_at_ms": now_ms().min(i64::MAX as u128) as i64,
        "reports_dir": reports_dir.display().to_string(),
        "reports_dir_exists": reports_dir_exists,
        "limit": limit,
        "latest": {
            "authority_plan": latest_authority_plan,
            "prep_trial": latest_prep_trial,
            "prep_sustained": latest_prep_sustained,
            "candidate_evidence": latest_candidate_evidence,
        },
        "recent": {
            "authority_plan": authority_plan,
            "prep_trial": prep_trial,
            "prep_sustained": prep_sustained,
            "candidate_evidence": candidate_evidence,
        },
        "observed_authority": {
            "production_authority_changes": production_authority_changes,
            "selected_model_authority_enabled_reports": selected_model_authority_enabled_reports,
            "node_authority_failures": node_authority_failures,
        },
        "checks": [
            {"name": "reports_dir", "ok": reports_dir_exists, "blocking": true},
            {"name": "latest_authority_plan_present", "ok": authority_plan_present, "blocking": true},
            {"name": "latest_authority_plan_ready", "ok": authority_plan_ready, "blocking": true},
            {"name": "latest_prep_trial_present", "ok": prep_trial_present, "blocking": true},
            {"name": "latest_prep_trial_ready", "ok": prep_trial_ready, "blocking": true},
            {"name": "latest_prep_sustained_present", "ok": prep_sustained_present, "blocking": true},
            {"name": "latest_prep_sustained_ready", "ok": prep_sustained_ready, "blocking": true},
            {"name": "production_authority_unchanged", "ok": production_authority_changes == 0, "blocking": true},
            {"name": "selected_model_authority_disabled", "ok": selected_model_authority_enabled_reports == 0, "blocking": true},
            {"name": "node_authority_preserved", "ok": node_authority_failures == 0, "blocking": true},
        ],
    })
    .to_string())
}

fn help_json() -> String {
    json!({
        "schema_version": MODEL_BRIDGE_SCHEMA_VERSION,
        "ok": true,
        "commands": ["inventory", "route", "compare", "reports", "readiness", "diagnostics"],
        "inventory_flags": ["--runtime-base-dir", "--now-ms"],
        "route_flags": ["--task-type", "--model-id", "--required-capability", "--privacy-mode", "--cost-preference", "--runtime-base-dir", "--now-ms"],
        "compare_flags": ["--node-inventory-json", "--runtime-base-dir", "--now-ms"],
        "reports_flags": ["--limit"],
        "readiness_flags": ["--min-compare-reports", "--max-mismatches", "--limit"],
        "diagnostics_flags": ["--limit"],
    })
    .to_string()
}

fn route_report_summaries(
    config: &HubConfig,
    reports_dir: &Path,
    kind: &str,
    file_prefix: &str,
    limit: usize,
) -> Vec<Value> {
    let Ok(entries) = fs::read_dir(reports_dir) else {
        return Vec::new();
    };
    let mut rows = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        let file_name = entry.file_name().to_string_lossy().to_string();
        if !file_name.starts_with(file_prefix) || !file_name.ends_with(".json") {
            continue;
        }
        let Ok(raw) = fs::read_to_string(&path) else {
            continue;
        };
        let Ok(report) = serde_json::from_str::<Value>(&raw) else {
            continue;
        };
        let generated_at_ms = first_value_u64(&report, &["generated_at_ms"]).unwrap_or(0);
        let modified_at_ms = file_modified_at_ms(&path);
        let sort_ms = generated_at_ms.max(modified_at_ms);
        let summary = summarize_route_report(
            config,
            kind,
            &path,
            &file_name,
            generated_at_ms,
            modified_at_ms,
            &report,
        );
        rows.push((sort_ms, file_name, summary));
    }
    rows.sort_by(|left, right| right.0.cmp(&left.0).then_with(|| right.1.cmp(&left.1)));
    rows.into_iter()
        .take(limit)
        .map(|(_, _, summary)| summary)
        .collect()
}

fn summarize_route_report(
    config: &HubConfig,
    kind: &str,
    path: &Path,
    file_name: &str,
    generated_at_ms: u64,
    modified_at_ms: u64,
    report: &Value,
) -> Value {
    let readiness = report.get("readiness").unwrap_or(&Value::Null);
    let ready = readiness
        .get("ready")
        .and_then(Value::as_bool)
        .or_else(|| report.get("ready").and_then(Value::as_bool))
        .unwrap_or(false);
    let decision = first_non_empty(
        &first_value_string(readiness, &["decision"]),
        &first_value_string(report, &["decision"]),
    );
    let production_authority_change =
        first_value_bool(report, &["production_authority_change"]).unwrap_or(false);
    let selected_model_authority_enabled =
        first_value_bool(report, &["selected_model_authority_enabled"]).unwrap_or(false);
    let node_authority_preserved = route_report_node_authority_preserved(report);
    json!({
        "kind": kind,
        "schema_version": first_value_string(report, &["schema_version"]),
        "file_name": file_name,
        "report_path": display_report_path(config, path),
        "generated_at_ms": generated_at_ms,
        "modified_at_ms": modified_at_ms,
        "ready": ready,
        "decision": decision,
        "authority_mode": first_value_string(report, &["authority_mode", "mode"]),
        "production_authority_change": production_authority_change,
        "selected_model_authority_enabled": selected_model_authority_enabled,
        "node_authority_preserved": node_authority_preserved,
        "readiness_schema_version": first_value_string(readiness, &["schema_version"]),
        "metrics": route_report_metrics(kind, report),
    })
}

fn route_report_node_authority_preserved(report: &Value) -> bool {
    let has_node_authority_fields = report
        .get("node_remains_model_selection_authority")
        .is_some()
        || report
            .get("bridge_payload_model_authority_remains_node")
            .is_some()
        || report
            .get("local_runtime_ipc_model_authority_remains_node")
            .is_some();
    if has_node_authority_fields {
        return first_value_bool(report, &["node_remains_model_selection_authority"])
            .unwrap_or(false)
            && first_value_bool(report, &["bridge_payload_model_authority_remains_node"])
                .unwrap_or(false)
            && first_value_bool(report, &["local_runtime_ipc_model_authority_remains_node"])
                .unwrap_or(false);
    }
    !first_value_bool(report, &["production_authority_change"]).unwrap_or(false)
}

fn route_report_metrics(kind: &str, report: &Value) -> Value {
    match kind {
        "authority_plan" => json!({
            "remote_model_id": first_value_string(report, &["remote_model_id"]),
            "local_model_id": first_value_string(report, &["local_model_id"]),
            "provider": first_value_string(report, &["provider"]),
            "production_cutover_implemented": first_value_bool(report, &["production_cutover_implemented"]).unwrap_or(false),
            "rust_can_prepare_model_route_decision": first_value_bool(report, &["rust_can_prepare_model_route_decision"]).unwrap_or(false),
            "readiness_summary": report.get("readiness_summary").cloned().unwrap_or(Value::Null),
        }),
        "prep_trial" => json!({
            "remote": report.pointer("/readiness/remote").cloned().unwrap_or(Value::Null),
            "local": report.pointer("/readiness/local").cloned().unwrap_or(Value::Null),
            "thresholds": report.pointer("/readiness/thresholds").cloned().unwrap_or(Value::Null),
        }),
        "prep_sustained" => json!({
            "aggregate": report.pointer("/readiness/aggregate").cloned().unwrap_or(Value::Null),
            "thresholds": report.pointer("/readiness/thresholds").cloned().unwrap_or(Value::Null),
            "cycle_report_count": report.get("cycle_reports").and_then(Value::as_array).map(|items| items.len()).unwrap_or(0),
        }),
        "candidate_evidence" => json!({
            "remote": report.pointer("/readiness/remote").cloned().unwrap_or(Value::Null),
            "local": report.pointer("/readiness/local").cloned().unwrap_or(Value::Null),
            "thresholds": report.pointer("/readiness/thresholds").cloned().unwrap_or(Value::Null),
        }),
        _ => json!({}),
    }
}

fn display_report_path(config: &HubConfig, path: &Path) -> String {
    path.strip_prefix(&config.root_dir)
        .map(|relative| relative.display().to_string())
        .unwrap_or_else(|_| path.display().to_string())
}

fn file_modified_at_ms(path: &Path) -> u64 {
    fs::metadata(path)
        .and_then(|metadata| metadata.modified())
        .ok()
        .and_then(|modified| modified.duration_since(UNIX_EPOCH).ok())
        .map(|duration| duration.as_millis().min(u64::MAX as u128) as u64)
        .unwrap_or(0)
}

fn normalize_model_inventory(inventory: &Value) -> Value {
    let mut remote_models = first_value_array(inventory, &["remote_models", "remoteModels"])
        .into_iter()
        .map(|row| {
            json!({
                "model_id": xhub_provider::normalized_model_id_for_routing(&first_value_string(&row, &["model_id", "modelId", "id"])),
                "provider": normalized_token(&first_value_string(&row, &["provider"])),
                "provider_host": normalized_token(&first_value_string(&row, &["provider_host", "providerHost"])),
                "family_key": normalized_token(&first_value_string(&row, &["family_key", "familyKey", "family"])),
                "pool_id": first_value_string(&row, &["pool_id", "poolId"]),
                "availability_state": normalized_token(&first_value_string(&row, &["availability_state", "availabilityState", "state"])),
                "available_account_count": first_value_u64(&row, &["available_account_count", "availableAccountCount", "available_count", "availableCount"]).unwrap_or(0),
                "total_account_count": first_value_u64(&row, &["total_account_count", "totalAccountCount", "total_count", "totalCount"]).unwrap_or(0),
                "blocking_reason_code": normalized_token(&first_value_string(&row, &["blocking_reason_code", "blockingReasonCode", "reason_code", "reasonCode"])),
                "next_retry_at_ms": first_value_u64(&row, &["next_retry_at_ms", "nextRetryAtMs", "retry_at_ms", "retryAtMs"]).unwrap_or(0),
            })
        })
        .collect::<Vec<Value>>();
    remote_models.sort_by_key(remote_model_inventory_sort_key);

    let mut local_models = first_value_array(inventory, &["local_models", "localModels"])
        .into_iter()
        .map(|row| normalize_local_model_inventory_row(&row))
        .collect::<Vec<Value>>();
    local_models.sort_by_key(local_model_inventory_sort_key);

    json!({
        "schema_version": first_non_empty(
            &first_value_string(inventory, &["schema_version", "schemaVersion"]),
            MODEL_INVENTORY_SCHEMA_VERSION,
        ),
        "ok": first_value_bool(inventory, &["ok"]).unwrap_or(true),
        "remote_models": remote_models,
        "local_models": local_models,
    })
}

fn normalize_local_model_inventory_row(row: &Value) -> Value {
    let runtime_preflight =
        first_value_ref(row, &["runtime_preflight", "runtimePreflight"]).unwrap_or(&Value::Null);
    json!({
        "model_id": first_value_string(row, &["model_id", "modelId", "id"]),
        "display_name": first_value_string(row, &["display_name", "displayName", "name"]),
        "family_key": normalized_token(&first_value_string(row, &["family_key", "familyKey", "family"])),
        "artifact_path": first_value_string(row, &["artifact_path", "artifactPath", "model_path", "modelPath"]),
        "format": normalized_token(&first_value_string(row, &["format", "artifact_format", "artifactFormat"])),
        "artifact_size_bytes": first_value_u64(row, &["artifact_size_bytes", "artifactSizeBytes", "size_bytes", "sizeBytes"]).unwrap_or(0),
        "checksum": first_value_string(row, &["checksum", "sha256", "artifact_checksum", "artifactChecksum"]),
        "quantization": normalized_token(&first_value_string(row, &["quantization", "quant", "quantization_level", "quantizationLevel"])),
        "runtime_provider": normalized_token(&first_value_string(row, &["runtime_provider", "runtimeProvider", "backend"])),
        "availability_state": normalized_token(&first_value_string(row, &["availability_state", "availabilityState", "state"])),
        "blocking_reason_code": normalized_token(&first_value_string(row, &["blocking_reason_code", "blockingReasonCode", "reason_code", "reasonCode"])),
        "capabilities": normalized_capability_values(row, &["capabilities", "capability_tags", "capabilityTags", "availableTaskKinds"]),
        "memory_risk": normalized_token(&first_value_string(row, &["memory_risk", "memoryRisk"])),
        "duplicate_artifact_of": first_value_string(row, &["duplicate_artifact_of", "duplicateArtifactOf"]),
        "runtime_preflight": {
            "runtime_provider": normalized_token(&first_value_string(runtime_preflight, &["runtime_provider", "runtimeProvider", "provider"])),
            "availability_state": normalized_token(&first_value_string(runtime_preflight, &["availability_state", "availabilityState", "state"])),
            "blocking_reason_code": normalized_token(&first_value_string(runtime_preflight, &["blocking_reason_code", "blockingReasonCode", "reason_code", "reasonCode"])),
            "runtime_source": first_value_string(runtime_preflight, &["runtime_source", "runtimeSource"]),
            "runtime_source_path": first_value_string(runtime_preflight, &["runtime_source_path", "runtimeSourcePath"]),
            "supported_format": first_value_bool(runtime_preflight, &["supported_format", "supportedFormat"]).unwrap_or(false),
            "side_effect_free": first_value_bool(runtime_preflight, &["side_effect_free", "sideEffectFree"]).unwrap_or(false),
            "runtime_updated_at_ms": first_value_u64(runtime_preflight, &["runtime_updated_at_ms", "runtimeUpdatedAtMs", "updated_at_ms", "updatedAtMs"]).unwrap_or(0),
            "capability_tags": normalized_capability_values(runtime_preflight, &["capability_tags", "capabilityTags", "availableTaskKinds"]),
            "runtime_missing_requirements": sorted_string_values(runtime_preflight, &["runtime_missing_requirements", "runtimeMissingRequirements", "missing_requirements", "missingRequirements"]),
        },
    })
}

fn remote_model_inventory_sort_key(row: &Value) -> String {
    format!(
        "{}\n{}\n{}\n{}",
        value_string(row, "provider"),
        value_string(row, "model_id"),
        value_string(row, "pool_id"),
        value_string(row, "provider_host")
    )
}

fn local_model_inventory_sort_key(row: &Value) -> String {
    format!(
        "{}\n{}\n{}",
        value_string(row, "model_id"),
        value_string(row, "runtime_provider"),
        value_string(row, "artifact_path")
    )
}

fn collect_value_mismatches(path: &str, left: &Value, right: &Value, out: &mut Vec<String>) {
    match (left, right) {
        (Value::Object(left_obj), Value::Object(right_obj)) => {
            let keys: BTreeSet<String> = left_obj
                .keys()
                .chain(right_obj.keys())
                .map(|key| key.to_string())
                .collect();
            for key in keys {
                let next_path = if path.is_empty() {
                    key.clone()
                } else {
                    format!("{path}.{key}")
                };
                collect_value_mismatches(
                    &next_path,
                    left_obj.get(&key).unwrap_or(&Value::Null),
                    right_obj.get(&key).unwrap_or(&Value::Null),
                    out,
                );
            }
        }
        (Value::Array(left_items), Value::Array(right_items)) => {
            if left_items.len() != right_items.len() {
                out.push(format!(
                    "{} length {} != {}",
                    if path.is_empty() { "value" } else { path },
                    left_items.len(),
                    right_items.len()
                ));
                return;
            }
            for (idx, (left_item, right_item)) in
                left_items.iter().zip(right_items.iter()).enumerate()
            {
                collect_value_mismatches(&format!("{path}[{idx}]"), left_item, right_item, out);
            }
        }
        _ if left != right => out.push(format!(
            "{} {} != {}",
            if path.is_empty() { "value" } else { path },
            left,
            right
        )),
        _ => {}
    }
}

fn report_summary_json(summary: &ShadowCompareReportSummary) -> String {
    let rows: Vec<Value> = summary
        .rows
        .iter()
        .map(|row| {
            json!({
                "report_id": row.report_id,
                "component": row.component,
                "compared_at_ms": row.compared_at_ms,
                "match_result": row.match_result,
                "mismatches": serde_json::from_str::<Value>(&row.mismatch_json).unwrap_or_else(|_| json!([])),
            })
        })
        .collect();
    json!({
        "schema_version": MODEL_BRIDGE_SCHEMA_VERSION,
        "ok": true,
        "command": "reports",
        "component": summary.component,
        "total": summary.total,
        "matched": summary.matched,
        "mismatched": summary.mismatched,
        "latest_compared_at_ms": summary.latest_compared_at_ms,
        "rows": rows,
    })
    .to_string()
}

fn remote_candidate_json(
    row: &xhub_provider::RemoteModelInventoryRow,
    requested_model_id: &str,
    remote_allowed: bool,
) -> Value {
    let candidate_model_match = model_matches_request(&row.model_id, requested_model_id);
    let mut reason_code = String::new();
    if !remote_allowed {
        reason_code = "privacy_remote_disabled".to_string();
    } else if !candidate_model_match {
        reason_code = "model_mismatch".to_string();
    } else if row.availability_state != "ready" {
        reason_code = first_non_empty(&row.blocking_reason_code, &row.availability_state);
    }
    let selectable = reason_code.is_empty();
    json!({
        "route_kind": "remote",
        "model_id": row.model_id,
        "provider": row.provider,
        "provider_host": row.provider_host,
        "family_key": row.family_key,
        "pool_id": row.pool_id,
        "availability_state": row.availability_state,
        "available_account_count": row.available_account_count,
        "total_account_count": row.total_account_count,
        "blocking_reason_code": row.blocking_reason_code,
        "next_retry_at_ms": row.next_retry_at_ms,
        "candidate_model_match": candidate_model_match,
        "selectable": selectable,
        "skip_reason_code": reason_code,
        "selected": false,
    })
}

fn local_candidate_json(
    row: &xhub_runtime::LocalModelInventoryRow,
    requested_model_id: &str,
    local_allowed: bool,
    high_risk: bool,
    required_capabilities: &[String],
) -> Value {
    let candidate_model_match = model_matches_request(&row.model_id, requested_model_id);
    let capability_ok = local_capabilities_satisfy(&row.capabilities, required_capabilities, false);
    let exact_capability_ok =
        local_capabilities_satisfy(&row.capabilities, required_capabilities, true);
    let weak_high_risk_fallback = high_risk && !exact_capability_ok;
    let mut reason_code = String::new();
    if !local_allowed {
        reason_code = "privacy_local_disabled".to_string();
    } else if !candidate_model_match {
        reason_code = "model_mismatch".to_string();
    } else if row.availability_state != "ready" {
        reason_code = first_non_empty(&row.blocking_reason_code, &row.availability_state);
    } else if !capability_ok {
        reason_code = "capability_mismatch".to_string();
    } else if row.memory_risk == "high" {
        reason_code = "memory_risk_high".to_string();
    } else if weak_high_risk_fallback {
        reason_code = "high_risk_local_fallback_blocked".to_string();
    }
    let selectable = reason_code.is_empty();
    json!({
        "route_kind": "local",
        "model_id": row.model_id,
        "display_name": row.display_name,
        "family_key": row.family_key,
        "artifact_path": row.artifact_path,
        "format": row.format,
        "runtime_provider": row.runtime_provider,
        "availability_state": row.availability_state,
        "blocking_reason_code": row.blocking_reason_code,
        "capabilities": row.capabilities,
        "memory_risk": row.memory_risk,
        "duplicate_artifact_of": row.duplicate_artifact_of,
        "runtime_preflight": row.runtime_preflight,
        "candidate_model_match": candidate_model_match,
        "capability_ok": capability_ok,
        "exact_capability_ok": exact_capability_ok,
        "selectable": selectable,
        "skip_reason_code": reason_code,
        "selected": false,
    })
}

fn selected_route_json(candidate: &Value) -> Value {
    json!({
        "route_kind": value_string(candidate, "route_kind"),
        "model_id": value_string(candidate, "model_id"),
        "provider": value_string(candidate, "provider"),
        "runtime_provider": value_string(candidate, "runtime_provider"),
        "pool_id": value_string(candidate, "pool_id"),
        "availability_state": value_string(candidate, "availability_state"),
        "reason_code": "",
    })
}

fn first_selectable_remote_candidate(candidates: &[Value]) -> Option<(usize, &Value)> {
    candidates
        .iter()
        .enumerate()
        .find(|(_, candidate)| value_bool(candidate, "selectable"))
}

fn first_selectable_local_candidate(candidates: &[Value]) -> Option<(usize, &Value)> {
    candidates
        .iter()
        .enumerate()
        .find(|(_, candidate)| value_bool(candidate, "selectable"))
}

fn fallback_model_route_reason(
    remote_allowed: bool,
    local_allowed: bool,
    remote_candidates: &[Value],
    local_candidates: &[Value],
) -> String {
    if !remote_allowed && !local_allowed {
        return "privacy_policy_blocks_all_routes".to_string();
    }
    let first_remote_reason = remote_candidates
        .iter()
        .map(|candidate| value_string(candidate, "skip_reason_code"))
        .find(|reason| !reason.is_empty());
    let first_local_reason = local_candidates
        .iter()
        .map(|candidate| value_string(candidate, "skip_reason_code"))
        .find(|reason| !reason.is_empty());
    first_remote_reason
        .or(first_local_reason)
        .unwrap_or_else(|| "no_model_route_available".to_string())
}

fn normalize_required_capabilities(request: &ModelRouteRequest) -> Vec<String> {
    let mut values = request
        .required_capabilities
        .iter()
        .map(|value| normalized_capability(value))
        .filter(|value| !value.is_empty())
        .collect::<Vec<String>>();
    if values.is_empty() {
        values.push(default_capability_for_task(&request.task_type));
    }
    values.sort();
    values.dedup();
    values
}

fn default_capability_for_task(task_type: &str) -> String {
    match normalized_token(task_type)
        .replace('_', ".")
        .replace('-', ".")
        .as_str()
    {
        "summarize" | "summary" | "text.summarize" => "text.summarize".to_string(),
        "coder" | "code" | "code.assist" => "code.assist".to_string(),
        "reviewer" | "code.review" | "review" => "code.review".to_string(),
        "embedding" | "embedding.generate" => "embedding.generate".to_string(),
        "vision" | "vision.describe" => "vision.describe".to_string(),
        "ocr" | "vision.ocr" => "vision.ocr".to_string(),
        "audio.transcribe" | "transcribe" => "audio.transcribe".to_string(),
        "audio.tts" | "tts" => "audio.tts".to_string(),
        "tool.calling" | "tool" => "tool.calling".to_string(),
        _ => "text.generate".to_string(),
    }
}

fn normalized_capability(value: &str) -> String {
    match normalized_token(value)
        .replace('_', ".")
        .replace('-', ".")
        .as_str()
    {
        "text.generate" | "generate.text" => "text.generate".to_string(),
        "text.summarize" | "summarize" => "text.summarize".to_string(),
        "code.assist" | "code" => "code.assist".to_string(),
        "code.review" | "review" => "code.review".to_string(),
        "embedding.generate" | "embedding" | "embeddings" => "embedding.generate".to_string(),
        "vision.describe" | "image.describe" => "vision.describe".to_string(),
        "vision.ocr" | "ocr" => "vision.ocr".to_string(),
        "audio.transcribe" | "transcribe" => "audio.transcribe".to_string(),
        "audio.tts" | "tts" => "audio.tts".to_string(),
        "tool.calling" | "tool.use" | "function.calling" => "tool.calling".to_string(),
        other => other.to_string(),
    }
}

fn local_capabilities_satisfy(
    capabilities: &[String],
    required_capabilities: &[String],
    exact: bool,
) -> bool {
    let available: BTreeSet<String> = capabilities
        .iter()
        .map(|value| normalized_capability(value))
        .collect();
    required_capabilities.iter().all(|required| {
        let required = normalized_capability(required);
        available.contains(&required)
            || (!exact && required == "text.summarize" && available.contains("text.generate"))
    })
}

fn is_high_risk_task(task_type: &str, required_capabilities: &[String]) -> bool {
    let task_type = normalized_token(task_type)
        .replace('_', ".")
        .replace('-', ".");
    if task_type.contains("code") || task_type.contains("coder") || task_type.contains("review") {
        return true;
    }
    required_capabilities.iter().any(|capability| {
        let capability = normalized_capability(capability);
        capability == "code.assist" || capability == "code.review" || capability == "tool.calling"
    })
}

fn model_matches_request(candidate_model_id: &str, requested_model_id: &str) -> bool {
    let requested = normalized_token(requested_model_id);
    if requested.is_empty() || requested == "auto" || requested == "*" {
        return true;
    }
    xhub_provider::normalized_model_id_for_routing(candidate_model_id)
        == xhub_provider::normalized_model_id_for_routing(&requested)
}

fn first_non_empty(value: &str, fallback: &str) -> String {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        fallback.trim().to_string()
    } else {
        trimmed.to_string()
    }
}

fn first_non_empty_vec(values: Vec<Vec<String>>) -> Vec<String> {
    values
        .into_iter()
        .find(|items| !items.is_empty())
        .unwrap_or_default()
}

fn normalized_token(value: &str) -> String {
    value.trim().to_lowercase()
}

fn value_string(value: &Value, key: &str) -> String {
    value
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim()
        .to_string()
}

fn value_bool(value: &Value, key: &str) -> bool {
    value.get(key).and_then(Value::as_bool).unwrap_or(false)
}

fn first_value_ref<'a>(value: &'a Value, keys: &[&str]) -> Option<&'a Value> {
    keys.iter().find_map(|key| value.get(*key))
}

fn first_value_array(value: &Value, keys: &[&str]) -> Vec<Value> {
    first_value_ref(value, keys)
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
}

fn first_value_string(value: &Value, keys: &[&str]) -> String {
    for key in keys {
        let Some(item) = value.get(*key) else {
            continue;
        };
        let raw = item
            .as_str()
            .map(|raw| raw.trim().to_string())
            .or_else(|| item.as_u64().map(|number| number.to_string()))
            .or_else(|| item.as_i64().map(|number| number.to_string()))
            .or_else(|| item.as_bool().map(|flag| flag.to_string()))
            .unwrap_or_default();
        if !raw.is_empty() {
            return raw;
        }
    }
    String::new()
}

fn first_value_u64(value: &Value, keys: &[&str]) -> Option<u64> {
    keys.iter()
        .find_map(|key| value.get(*key).and_then(value_as_u64))
}

fn first_value_bool(value: &Value, keys: &[&str]) -> Option<bool> {
    keys.iter().find_map(|key| {
        value.get(*key).and_then(|item| {
            item.as_bool().or_else(|| {
                item.as_str()
                    .and_then(|raw| match normalized_token(raw).as_str() {
                        "true" | "1" | "yes" => Some(true),
                        "false" | "0" | "no" => Some(false),
                        _ => None,
                    })
            })
        })
    })
}

fn normalized_capability_values(value: &Value, keys: &[&str]) -> Vec<String> {
    let mut values = string_values(value, keys)
        .into_iter()
        .map(|item| normalized_capability(&item))
        .filter(|item| !item.is_empty())
        .collect::<Vec<String>>();
    values.sort();
    values.dedup();
    values
}

fn sorted_string_values(value: &Value, keys: &[&str]) -> Vec<String> {
    let mut values = string_values(value, keys)
        .into_iter()
        .map(|item| item.trim().to_string())
        .filter(|item| !item.is_empty())
        .collect::<Vec<String>>();
    values.sort();
    values.dedup();
    values
}

fn string_values(value: &Value, keys: &[&str]) -> Vec<String> {
    let Some(item) = first_value_ref(value, keys) else {
        return Vec::new();
    };
    if let Some(items) = item.as_array() {
        return items
            .iter()
            .filter_map(|item| item.as_str().map(|raw| raw.trim().to_string()))
            .filter(|item| !item.is_empty())
            .collect();
    }
    item.as_str()
        .unwrap_or("")
        .split(|ch: char| ch == ',' || ch.is_whitespace())
        .map(|item| item.trim().to_string())
        .filter(|item| !item.is_empty())
        .collect()
}

fn value_as_u64(value: &Value) -> Option<u64> {
    value
        .as_u64()
        .or_else(|| {
            value
                .as_i64()
                .and_then(|number| u64::try_from(number.max(0)).ok())
        })
        .or_else(|| {
            value
                .as_str()
                .and_then(|raw| raw.trim().parse::<u64>().ok())
        })
}

#[derive(Debug, Clone)]
struct FlagArgs {
    values: BTreeMap<String, String>,
}

impl FlagArgs {
    fn parse(args: &[String]) -> Result<Self, String> {
        let mut values = BTreeMap::new();
        let mut i = 0;
        while i < args.len() {
            let raw = &args[i];
            if !raw.starts_with("--") {
                return Err(format!("unexpected positional argument: {raw}"));
            }
            let key = raw.trim_start_matches("--").to_string();
            if key.is_empty() {
                return Err("empty flag name".to_string());
            }
            let value = args
                .get(i + 1)
                .ok_or_else(|| format!("missing value for --{key}"))?;
            if value.starts_with("--") {
                return Err(format!("missing value for --{key}"));
            }
            values.insert(key, value.clone());
            i += 2;
        }
        Ok(Self { values })
    }

    fn required(&self, key: &str) -> Result<String, String> {
        self.optional(key)
            .filter(|value| !value.trim().is_empty())
            .ok_or_else(|| format!("missing required flag --{key}"))
    }

    fn optional(&self, key: &str) -> Option<String> {
        self.values.get(key).cloned()
    }

    fn optional_list(&self, key: &str) -> Vec<String> {
        self.optional(key)
            .unwrap_or_default()
            .split(|ch: char| ch == ',' || ch.is_whitespace())
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
            .collect()
    }

    fn optional_u128(&self, key: &str) -> Result<Option<u128>, String> {
        let Some(value) = self.optional(key) else {
            return Ok(None);
        };
        value
            .parse::<u128>()
            .map(Some)
            .map_err(|err| format!("invalid --{key}: {err}"))
    }

    fn optional_i64(&self, key: &str) -> Result<Option<i64>, String> {
        let Some(value) = self.optional(key) else {
            return Ok(None);
        };
        value
            .parse::<i64>()
            .map(Some)
            .map_err(|err| format!("invalid --{key}: {err}"))
    }

    fn optional_usize(&self, key: &str) -> Result<Option<usize>, String> {
        let Some(value) = self.optional(key) else {
            return Ok(None);
        };
        value
            .parse::<usize>()
            .map(Some)
            .map_err(|err| format!("invalid --{key}: {err}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};
    use xhub_core::HubConfig;

    #[test]
    fn inventory_json_works_against_empty_runtime_dir() {
        let dir = unique_temp_dir("xhub-model-inventory-empty");
        fs::create_dir_all(&dir).expect("temp dir should be created");
        let config = config_for_runtime_dir(dir.clone());

        let raw = inventory_json_from_parts(&config, Some(dir.clone()), Some(1000))
            .expect("inventory should read empty runtime dir");
        let value: serde_json::Value =
            serde_json::from_str(&raw).expect("inventory output should parse");

        assert_eq!(value["schema_version"], MODEL_INVENTORY_SCHEMA_VERSION);
        assert_eq!(value["ok"], true);
        assert_eq!(value["remote_models"].as_array().unwrap().len(), 0);
        assert_eq!(value["local_models"].as_array().unwrap().len(), 0);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn inventory_json_contains_remote_and_local_rows_without_secrets() {
        let dir = unique_temp_dir("xhub-model-inventory");
        fs::create_dir_all(&dir).expect("temp dir should be created");
        let artifact_path = dir.join("model.gguf");
        fs::write(&artifact_path, "fixture").expect("artifact should be written");
        fs::write(
            dir.join("hub_provider_keys.json"),
            r#"{
              "providers": {
                "openai": {
                  "routing_strategy": "priority",
                  "accounts": [
                    {
                      "account_key": "acct-remote",
                      "provider": "openai",
                      "api_key": "sk-secret-in-store",
                      "models": ["openai/gpt5.5"],
                      "provider_host": "api.openai.com",
                      "pool_id": "paid"
                    }
                  ]
                }
              }
            }"#,
        )
        .expect("provider store should be written");
        fs::write(
            dir.join("models_state.json"),
            format!(
                r#"{{
                  "models": [
                    {{
                      "id": "local.gguf",
                      "backend": "mlx",
                      "modelPath": "{}"
                    }}
                  ]
                }}"#,
                artifact_path.display()
            ),
        )
        .expect("models_state should be written");
        let config = config_for_runtime_dir(dir.clone());

        let raw = inventory_json_from_parts(&config, Some(dir.clone()), Some(1000))
            .expect("inventory should read fixtures");
        let value: serde_json::Value =
            serde_json::from_str(&raw).expect("inventory output should parse");

        assert_eq!(value["remote_models"][0]["model_id"], "gpt-5.5");
        assert_eq!(value["remote_models"][0]["provider"], "openai");
        assert_eq!(value["remote_models"][0]["pool_id"], "paid");
        assert_eq!(value["remote_models"][0]["availability_state"], "ready");
        assert_eq!(value["local_models"][0]["model_id"], "local.gguf");
        assert_eq!(value["local_models"][0]["format"], "gguf");
        assert!(!raw.contains("sk-secret-in-store"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn route_json_selects_remote_ready_candidate_first() {
        let dir = unique_temp_dir("xhub-model-route-remote");
        fs::create_dir_all(&dir).expect("temp dir should be created");
        write_provider_store(&dir, 0);
        write_local_model(&dir, "local.summary", &["text_generate"]);
        write_runtime_status(&dir, "mlx", true, &["text_generate"]);
        let config = config_for_runtime_dir(dir.clone());

        let raw = route_json_from_parts(
            &config,
            Some(dir.clone()),
            ModelRouteRequest {
                task_type: "summarize".to_string(),
                model_id: "auto".to_string(),
                required_capabilities: vec!["text.summarize".to_string()],
                privacy_mode: "standard".to_string(),
                cost_preference: "balanced".to_string(),
            },
            Some(1000),
        )
        .expect("model route should succeed");
        let value: serde_json::Value = serde_json::from_str(&raw).expect("route json should parse");

        assert_eq!(value["schema_version"], MODEL_ROUTE_SCHEMA_VERSION);
        assert_eq!(value["selected_route_kind"], "remote");
        assert_eq!(value["selected_model_id"], "gpt-4o");
        assert_eq!(value["blocking_reason_code"], "");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn route_json_uses_local_summary_when_remote_is_cooling() {
        let dir = unique_temp_dir("xhub-model-route-local-summary");
        fs::create_dir_all(&dir).expect("temp dir should be created");
        write_provider_store(&dir, 30_000);
        write_local_model(&dir, "local.summary", &["text_generate"]);
        write_runtime_status(&dir, "mlx", true, &["text_generate"]);
        let config = config_for_runtime_dir(dir.clone());

        let raw = route_json_from_parts(
            &config,
            Some(dir.clone()),
            ModelRouteRequest {
                task_type: "summarize".to_string(),
                model_id: "auto".to_string(),
                required_capabilities: vec!["text.summarize".to_string()],
                privacy_mode: "standard".to_string(),
                cost_preference: "balanced".to_string(),
            },
            Some(1000),
        )
        .expect("model route should succeed");
        let value: serde_json::Value = serde_json::from_str(&raw).expect("route json should parse");

        assert_eq!(value["selected_route_kind"], "local");
        assert_eq!(value["selected_model_id"], "local.summary");
        assert_eq!(
            value["remote_candidates"][0]["skip_reason_code"],
            "all_keys_in_cooldown"
        );
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn route_json_blocks_high_risk_weak_local_fallback() {
        let dir = unique_temp_dir("xhub-model-route-high-risk");
        fs::create_dir_all(&dir).expect("temp dir should be created");
        write_provider_store(&dir, 30_000);
        write_local_model(&dir, "local.text", &["text_generate"]);
        write_runtime_status(&dir, "mlx", true, &["text_generate"]);
        let config = config_for_runtime_dir(dir.clone());

        let raw = route_json_from_parts(
            &config,
            Some(dir.clone()),
            ModelRouteRequest {
                task_type: "code_review".to_string(),
                model_id: "auto".to_string(),
                required_capabilities: vec!["code.review".to_string()],
                privacy_mode: "standard".to_string(),
                cost_preference: "balanced".to_string(),
            },
            Some(1000),
        )
        .expect("model route should succeed");
        let value: serde_json::Value = serde_json::from_str(&raw).expect("route json should parse");

        assert_eq!(value["selected_route_kind"], "");
        assert_eq!(
            value["blocking_reason_code"],
            "high_risk_local_fallback_blocked"
        );
        assert_eq!(value["selected"].as_object().unwrap().len(), 0);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn route_json_respects_local_only_privacy_mode() {
        let dir = unique_temp_dir("xhub-model-route-local-only");
        fs::create_dir_all(&dir).expect("temp dir should be created");
        write_provider_store(&dir, 0);
        write_local_model(&dir, "local.summary", &["text_generate"]);
        write_runtime_status(&dir, "mlx", true, &["text_generate"]);
        let config = config_for_runtime_dir(dir.clone());

        let raw = route_json_from_parts(
            &config,
            Some(dir.clone()),
            ModelRouteRequest {
                task_type: "summarize".to_string(),
                model_id: "auto".to_string(),
                required_capabilities: vec!["text.summarize".to_string()],
                privacy_mode: "local-only".to_string(),
                cost_preference: "balanced".to_string(),
            },
            Some(1000),
        )
        .expect("model route should succeed");
        let value: serde_json::Value = serde_json::from_str(&raw).expect("route json should parse");

        assert_eq!(value["selected_route_kind"], "local");
        assert_eq!(
            value["remote_candidates"][0]["skip_reason_code"],
            "privacy_remote_disabled"
        );
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn compare_inventory_records_match_report() {
        let dir = unique_temp_dir("xhub-model-inventory-compare-match");
        fs::create_dir_all(&dir).expect("temp dir should be created");
        write_provider_store(&dir, 0);
        write_local_model(&dir, "local.summary", &["text_generate"]);
        write_runtime_status(&dir, "mlx", true, &["text_generate"]);
        let config = config_for_runtime_dir(dir.clone());
        let node_value = inventory_value_for_test(&config, &dir);

        let raw =
            compare_inventory_json_from_parts(&config, Some(dir.clone()), node_value, Some(1000))
                .expect("inventory compare should succeed");
        let value: serde_json::Value =
            serde_json::from_str(&raw).expect("compare json should parse");

        assert_eq!(value["schema_version"], MODEL_BRIDGE_SCHEMA_VERSION);
        assert_eq!(value["component"], MODEL_INVENTORY_COMPONENT);
        assert_eq!(value["match"], true);

        let reports = reports_json_from_parts(&config, 5).expect("reports should read");
        let reports: serde_json::Value =
            serde_json::from_str(&reports).expect("reports json should parse");
        assert_eq!(reports["total"], 1);
        assert_eq!(reports["matched"], 1);
        assert_eq!(reports["mismatched"], 0);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn compare_inventory_reports_field_level_mismatch() {
        let dir = unique_temp_dir("xhub-model-inventory-compare-mismatch");
        fs::create_dir_all(&dir).expect("temp dir should be created");
        write_provider_store(&dir, 0);
        write_local_model(&dir, "local.summary", &["text_generate"]);
        write_runtime_status(&dir, "mlx", true, &["text_generate"]);
        let config = config_for_runtime_dir(dir.clone());
        let mut node_value = inventory_value_for_test(&config, &dir);
        node_value["remote_models"][0]["availability_state"] = json!("blocked");

        let raw =
            compare_inventory_json_from_parts(&config, Some(dir.clone()), node_value, Some(1000))
                .expect("inventory compare should succeed");
        let value: serde_json::Value =
            serde_json::from_str(&raw).expect("compare json should parse");
        let mismatches = value["mismatches"]
            .as_array()
            .expect("mismatches should be an array")
            .iter()
            .map(|item| item.as_str().unwrap_or(""))
            .collect::<Vec<&str>>();

        assert_eq!(value["match"], false);
        assert!(mismatches
            .iter()
            .any(|item| item.contains("remote_models[0].availability_state")));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn inventory_readiness_is_ready_after_one_matching_report() {
        let dir = unique_temp_dir("xhub-model-inventory-readiness");
        fs::create_dir_all(&dir).expect("temp dir should be created");
        write_provider_store(&dir, 0);
        write_local_model(&dir, "local.summary", &["text_generate"]);
        write_runtime_status(&dir, "mlx", true, &["text_generate"]);
        let config = config_for_runtime_dir(dir.clone());
        let node_value = inventory_value_for_test(&config, &dir);
        compare_inventory_json_from_parts(&config, Some(dir.clone()), node_value, Some(1000))
            .expect("inventory compare should succeed");

        let raw = readiness_json_from_parts(&config, 1, 0, 5).expect("readiness should succeed");
        let value: serde_json::Value =
            serde_json::from_str(&raw).expect("readiness json should parse");

        assert_eq!(value["ready"], true);
        assert_eq!(value["compare"]["total"], 1);
        assert_eq!(value["compare"]["mismatched"], 0);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn diagnostics_reports_latest_route_evidence_without_raw_secret_material() {
        let dir = unique_temp_dir("xhub-model-route-diagnostics");
        let reports_dir = dir.join("reports");
        fs::create_dir_all(&reports_dir).expect("reports dir should be created");
        let config = config_for_runtime_dir(dir.clone());

        fs::write(
            reports_dir.join("model_route_authority_plan_20260506T010000Z.json"),
            r#"{
              "schema_version":"xhub.model_route_selected_model_authority_dry_run_plan.v1",
              "component":"model_route",
              "mode":"dry_run_only",
              "decision":"ready_for_manual_prep_trial",
              "ready":true,
              "generated_at_ms":1000,
              "remote_model_id":"gpt-5.5",
              "local_model_id":"local.summary",
              "provider":"openai",
              "production_authority_change":false,
              "node_remains_model_selection_authority":true,
              "bridge_payload_model_authority_remains_node":true,
              "local_runtime_ipc_model_authority_remains_node":true,
              "production_cutover_implemented":false,
              "rust_can_prepare_model_route_decision":true,
              "selected_model_authority_enabled":false,
              "readiness_summary":{"ready":true,"decision":"ready"},
              "required_env_for_manual_prep_trial":[{"name":"api_key","value":"sk-secret"}]
            }"#,
        )
        .expect("authority plan should write");
        fs::write(
            reports_dir.join("model_route_prep_trial_20260506T010000Z.json"),
            r#"{
              "schema_version":"xhub.model_route_prep_trial_report.v1",
              "generated_at_ms":2000,
              "component":"model_route",
              "production_authority_change":false,
              "selected_model_authority_enabled":false,
              "authority_mode":"prep_trial_only",
              "node_remains_model_selection_authority":true,
              "bridge_payload_model_authority_remains_node":true,
              "local_runtime_ipc_model_authority_remains_node":true,
              "readiness":{
                "schema_version":"xhub.model_route_prep_trial_readiness.v1",
                "decision":"ready",
                "ready":true,
                "remote":{"prep_match_count":1,"prep_warning_count":0,"node_authority_preserved":true},
                "local":{"prep_match_count":1,"prep_warning_count":0,"node_authority_preserved":true}
              },
              "runners":{"remote":{"stderr":"sk-secret"}}
            }"#,
        )
        .expect("prep trial report should write");
        fs::write(
            reports_dir.join("model_route_prep_sustained_20260506T010000Z.json"),
            r#"{
              "schema_version":"xhub.model_route_prep_sustained_report.v1",
              "generated_at_ms":3000,
              "component":"model_route",
              "production_authority_change":false,
              "selected_model_authority_enabled":false,
              "authority_mode":"prep_sustained_diagnostic_only",
              "node_remains_model_selection_authority":true,
              "bridge_payload_model_authority_remains_node":true,
              "local_runtime_ipc_model_authority_remains_node":true,
              "readiness":{
                "schema_version":"xhub.model_route_prep_sustained_readiness.v1",
                "decision":"ready",
                "ready":true,
                "aggregate":{
                  "ready_cycles":2,
                  "failed_cycles":0,
                  "total_remote_prep_matches":2,
                  "total_local_prep_matches":2,
                  "total_prep_warnings":0,
                  "node_authority_failures":0
                }
              }
            }"#,
        )
        .expect("sustained report should write");

        let raw = diagnostics_json_from_parts(&config, 1).expect("diagnostics should read");
        let value: serde_json::Value =
            serde_json::from_str(&raw).expect("diagnostics json should parse");

        assert_eq!(
            value["schema_version"],
            MODEL_ROUTE_DIAGNOSTICS_SCHEMA_VERSION
        );
        assert_eq!(value["ready"], true);
        assert_eq!(value["read_only"], true);
        assert_eq!(value["production_authority_change"], false);
        assert_eq!(value["selected_model_authority_enabled"], false);
        assert_eq!(
            value["latest"]["prep_sustained"]["metrics"]["aggregate"]["total_remote_prep_matches"],
            2
        );
        assert!(!raw.contains("api_key"));
        assert!(!raw.contains("sk-secret"));
        assert!(!raw.contains("required_env_for_manual_prep_trial"));
        let _ = fs::remove_dir_all(&dir);
    }

    fn config_for_runtime_dir(runtime_base_dir: PathBuf) -> HubConfig {
        let root_dir = runtime_base_dir.clone();
        HubConfig {
            root_dir: root_dir.clone(),
            db_path: root_dir.join("hub.sqlite3"),
            runtime_base_dir,
            proto_path: root_dir.join("hub_protocol_v1.proto"),
            canonical_proto_path: root_dir.join("canonical_hub_protocol_v1.proto"),
            host: "127.0.0.1".to_string(),
            http_port: 0,
            grpc_port: 0,
            http_access_key: None,
            http_access_key_source: String::new(),
            http_access_key_required: false,
        }
    }

    fn write_provider_store(dir: &std::path::Path, cooldown_ms: u64) {
        fs::write(
            dir.join("hub_provider_keys.json"),
            format!(
                r#"{{
                  "providers": {{
                    "openai": {{
                      "routing_strategy": "priority",
                      "accounts": [
                        {{
                          "account_key": "acct-remote",
                          "provider": "openai",
                          "api_key": "sk-secret-in-store",
                          "models": ["gpt-4o"],
                          "provider_host": "api.openai.com",
                          "pool_id": "paid",
                          "quota": {{
                            "next_recover_at_ms": {}
                          }}
                        }}
                      ]
                    }}
                  }}
                }}"#,
                cooldown_ms
            ),
        )
        .expect("provider store should be written");
    }

    fn write_local_model(dir: &std::path::Path, model_id: &str, capabilities: &[&str]) {
        let artifact_path = dir.join(format!("{model_id}.gguf"));
        fs::write(&artifact_path, "fixture").expect("artifact should be written");
        let capability_json = capabilities
            .iter()
            .map(|capability| format!("\"{capability}\""))
            .collect::<Vec<String>>()
            .join(",");
        fs::write(
            dir.join("models_state.json"),
            format!(
                r#"{{
                  "models": [
                    {{
                      "id": "{}",
                      "backend": "mlx",
                      "modelPath": "{}",
                      "capabilities": [{}]
                    }}
                  ]
                }}"#,
                model_id,
                artifact_path.display(),
                capability_json
            ),
        )
        .expect("models_state should be written");
    }

    fn write_runtime_status(
        dir: &std::path::Path,
        provider: &str,
        ok: bool,
        capabilities: &[&str],
    ) {
        let capability_json = capabilities
            .iter()
            .map(|capability| format!("\"{capability}\""))
            .collect::<Vec<String>>()
            .join(",");
        fs::write(
            dir.join("ai_runtime_status.json"),
            format!(
                r#"{{
                  "providers": {{
                    "{}": {{
                      "provider": "{}",
                      "ok": {},
                      "availableTaskKinds": [{}],
                      "runtimeSource": "fixture",
                      "runtimeSourcePath": "/tmp/fixture-runtime",
                      "runtimeResolutionState": "resolved",
                      "updatedAtMs": 1000
                    }}
                  }}
                }}"#,
                provider, provider, ok, capability_json
            ),
        )
        .expect("runtime status should be written");
    }

    fn inventory_value_for_test(config: &HubConfig, dir: &std::path::Path) -> serde_json::Value {
        let raw = inventory_json_from_parts(config, Some(dir.to_path_buf()), Some(1000))
            .expect("inventory should read fixtures");
        serde_json::from_str(&raw).expect("inventory json should parse")
    }

    fn unique_temp_dir(prefix: &str) -> PathBuf {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system time should be valid")
            .as_nanos();
        std::env::temp_dir().join(format!("{prefix}-{}-{stamp}", std::process::id()))
    }
}
