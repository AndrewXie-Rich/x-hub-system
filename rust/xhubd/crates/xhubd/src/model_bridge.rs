use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::thread;
use std::time::{Duration, Instant, UNIX_EPOCH};

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
const MODEL_LOCAL_CAPABILITY_SUMMARY_SCHEMA_VERSION: &str =
    "xhub.model_local_capability_summary.v1";
const MODEL_LOCAL_RUNTIME_REPAIR_PLAN_SCHEMA_VERSION: &str =
    "xhub.model_local_runtime_repair_plan.v1";
const MODEL_LOCAL_RUNTIME_REPAIR_APPLY_SCHEMA_VERSION: &str =
    "xhub.model_local_runtime_repair_apply.v1";
const MODEL_LOCAL_RUNTIME_REPAIR_JOB_SCHEMA_VERSION: &str =
    "xhub.model_local_runtime_repair_job.v1";
const MODEL_LOCAL_RUNTIME_REPAIR_JOBS_SCHEMA_VERSION: &str =
    "xhub.model_local_runtime_repair_jobs.v1";
const MODEL_BRIDGE_SCHEMA_VERSION: &str = "xhub.model_bridge.v1";
const MODEL_INVENTORY_COMPONENT: &str = "model_inventory";
const MODEL_ROUTE_COMPONENT: &str = "model_route";
static MODEL_INVENTORY_COMPARE_REPORT_COUNTER: AtomicU64 = AtomicU64::new(1);
static MODEL_REPAIR_JOB_COUNTER: AtomicU64 = AtomicU64::new(1);

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
        "capabilities" | "local-capabilities" | "local_capabilities" => {
            local_capabilities_json(config, FlagArgs::parse(&args[1..])?)
        }
        "repair-plan" | "repair_plan" | "local-repair-plan" | "local_repair_plan" => {
            local_repair_plan_json(config, FlagArgs::parse(&args[1..])?)
        }
        "repair-apply" | "repair_apply" | "local-repair-apply" | "local_repair_apply" => {
            local_repair_apply_json(config, FlagArgs::parse(&args[1..])?)
        }
        "repair-jobs" | "repair_jobs" | "local-repair-jobs" | "local_repair_jobs" => {
            local_repair_jobs_json(config, FlagArgs::parse(&args[1..])?)
        }
        "repair-executor"
        | "repair_executor"
        | "local-repair-executor"
        | "local_repair_executor" => {
            local_repair_executor_json(config, FlagArgs::parse(&args[1..])?)
        }
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
    let local_capability_summary =
        local_capability_summary_value(&runtime_base_dir, &local_models, now);
    Ok(json!({
        "schema_version": MODEL_INVENTORY_SCHEMA_VERSION,
        "ok": true,
        "command": "inventory",
        "runtime_base_dir": runtime_base_dir.display().to_string(),
        "updated_at_ms": now,
        "remote_models": remote_models,
        "local_models": local_models,
        "local_capability_summary": local_capability_summary,
    }))
}

fn local_capabilities_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let runtime_base_dir = flags
        .optional("runtime-base-dir")
        .map(PathBuf::from)
        .unwrap_or_else(|| config.runtime_base_dir.clone());
    let now = flags.optional_u128("now-ms")?.unwrap_or_else(now_ms);
    local_capabilities_json_from_parts(config, Some(runtime_base_dir), Some(now))
}

pub fn local_capabilities_json_from_parts(
    config: &HubConfig,
    runtime_base_dir: Option<PathBuf>,
    now_ms_value: Option<u128>,
) -> Result<String, String> {
    let runtime_base_dir = runtime_base_dir.unwrap_or_else(|| config.runtime_base_dir.clone());
    let now = now_ms_value.unwrap_or_else(now_ms);
    let local_models = local_model_inventory_rows(&runtime_base_dir);
    Ok(local_capability_summary_value(&runtime_base_dir, &local_models, now).to_string())
}

fn local_repair_plan_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let runtime_base_dir = flags
        .optional("runtime-base-dir")
        .map(PathBuf::from)
        .unwrap_or_else(|| config.runtime_base_dir.clone());
    let now = flags.optional_u128("now-ms")?.unwrap_or_else(now_ms);
    let request = ModelLocalRepairPlanRequest {
        action: flags.optional("action").unwrap_or_default(),
        task_kind: flags
            .optional("task-kind")
            .or_else(|| flags.optional("task"))
            .unwrap_or_default(),
        provider_id: flags
            .optional("provider-id")
            .or_else(|| flags.optional("provider"))
            .unwrap_or_default(),
    };
    local_repair_plan_json_from_parts(config, Some(runtime_base_dir), request, Some(now))
}

#[derive(Debug, Clone, Default)]
pub struct ModelLocalRepairPlanRequest {
    pub action: String,
    pub task_kind: String,
    pub provider_id: String,
}

pub fn local_repair_plan_json_from_parts(
    config: &HubConfig,
    runtime_base_dir: Option<PathBuf>,
    request: ModelLocalRepairPlanRequest,
    now_ms_value: Option<u128>,
) -> Result<String, String> {
    let runtime_base_dir = runtime_base_dir.unwrap_or_else(|| config.runtime_base_dir.clone());
    let now = now_ms_value.unwrap_or_else(now_ms);
    let local_models = local_model_inventory_rows(&runtime_base_dir);
    let provider_summaries = runtime_provider_summaries(&runtime_base_dir);
    Ok(local_repair_plan_value(
        &runtime_base_dir,
        &request,
        &local_models,
        &provider_summaries,
        now,
    )
    .to_string())
}

fn local_repair_apply_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let runtime_base_dir = flags
        .optional("runtime-base-dir")
        .map(PathBuf::from)
        .unwrap_or_else(|| config.runtime_base_dir.clone());
    let now = flags.optional_u128("now-ms")?.unwrap_or_else(now_ms);
    let request = ModelLocalRepairApplyRequest {
        action: flags.optional("action").unwrap_or_default(),
        task_kind: flags
            .optional("task-kind")
            .or_else(|| flags.optional("task"))
            .unwrap_or_default(),
        provider_id: flags
            .optional("provider-id")
            .or_else(|| flags.optional("provider"))
            .unwrap_or_default(),
        confirm: flags.optional_bool("confirm")?.unwrap_or(false),
        dry_run: flags.optional_bool("dry-run")?.unwrap_or(false),
        confirmation_token: flags.optional("confirmation-token").unwrap_or_default(),
        requested_by: flags
            .optional("requested-by")
            .unwrap_or_else(|| "cli".to_string()),
        model_id: flags.optional("model-id").unwrap_or_default(),
        display_name: flags
            .optional("display-name")
            .or_else(|| flags.optional("name"))
            .unwrap_or_default(),
        artifact_path: flags
            .optional("artifact-path")
            .or_else(|| flags.optional("model-path"))
            .or_else(|| flags.optional("path"))
            .unwrap_or_default(),
        format: flags.optional("format").unwrap_or_default(),
        quantization: flags
            .optional("quantization")
            .or_else(|| flags.optional("quant"))
            .unwrap_or_default(),
        capabilities: first_non_empty_vec(vec![
            flags.optional_list("capability"),
            flags.optional_list("capabilities"),
        ]),
        task_kinds: first_non_empty_vec(vec![
            flags.optional_list("task-kind"),
            flags.optional_list("task-kinds"),
            flags.optional_list("taskKinds"),
        ]),
        context_length: flags.optional_u64("context-length")?.unwrap_or(0),
        memory_bytes: flags.optional_u64("memory-bytes")?.unwrap_or(0),
    };
    local_repair_apply_json_from_parts(config, Some(runtime_base_dir), request, Some(now))
}

fn local_repair_jobs_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let runtime_base_dir = flags
        .optional("runtime-base-dir")
        .map(PathBuf::from)
        .unwrap_or_else(|| config.runtime_base_dir.clone());
    let limit = flags.optional_usize("limit")?.unwrap_or(20);
    let now = flags.optional_u128("now-ms")?.unwrap_or_else(now_ms);
    local_repair_jobs_json_from_parts(config, Some(runtime_base_dir), limit, Some(now))
}

fn local_repair_executor_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let runtime_base_dir = flags
        .optional("runtime-base-dir")
        .map(PathBuf::from)
        .unwrap_or_else(|| config.runtime_base_dir.clone());
    let now = flags.optional_u128("now-ms")?.unwrap_or_else(now_ms);
    let request = ModelLocalRepairExecutorRequest {
        allow_network: flags.optional_bool("allow-network")?.unwrap_or(false),
        dry_run: flags.optional_bool("dry-run")?.unwrap_or(false),
        python: flags.optional("python").unwrap_or_default(),
        timeout_ms: flags.optional_u64("timeout-ms")?.unwrap_or(600_000),
        requested_by: flags
            .optional("requested-by")
            .unwrap_or_else(|| "cli".to_string()),
    };
    local_repair_executor_json_from_parts(config, Some(runtime_base_dir), request, Some(now))
}

#[derive(Debug, Clone, Default)]
pub struct ModelLocalRepairApplyRequest {
    pub action: String,
    pub task_kind: String,
    pub provider_id: String,
    pub confirm: bool,
    pub dry_run: bool,
    pub confirmation_token: String,
    pub requested_by: String,
    pub model_id: String,
    pub display_name: String,
    pub artifact_path: String,
    pub format: String,
    pub quantization: String,
    pub capabilities: Vec<String>,
    pub task_kinds: Vec<String>,
    pub context_length: u64,
    pub memory_bytes: u64,
}

#[derive(Debug, Clone, Default)]
pub struct ModelLocalRepairExecutorRequest {
    pub allow_network: bool,
    pub dry_run: bool,
    pub python: String,
    pub timeout_ms: u64,
    pub requested_by: String,
}

pub fn local_repair_apply_json_from_parts(
    config: &HubConfig,
    runtime_base_dir: Option<PathBuf>,
    request: ModelLocalRepairApplyRequest,
    now_ms_value: Option<u128>,
) -> Result<String, String> {
    let runtime_base_dir = runtime_base_dir.unwrap_or_else(|| config.runtime_base_dir.clone());
    let now = now_ms_value.unwrap_or_else(now_ms);
    let local_models = local_model_inventory_rows(&runtime_base_dir);
    let provider_summaries = runtime_provider_summaries(&runtime_base_dir);
    let plan_request = ModelLocalRepairPlanRequest {
        action: request.action.clone(),
        task_kind: request.task_kind.clone(),
        provider_id: request.provider_id.clone(),
    };
    let plan = local_repair_plan_value(
        &runtime_base_dir,
        &plan_request,
        &local_models,
        &provider_summaries,
        now,
    );
    Ok(local_repair_apply_value(&runtime_base_dir, &request, plan, now)?.to_string())
}

pub fn local_repair_jobs_json_from_parts(
    config: &HubConfig,
    runtime_base_dir: Option<PathBuf>,
    limit: usize,
    now_ms_value: Option<u128>,
) -> Result<String, String> {
    let runtime_base_dir = runtime_base_dir.unwrap_or_else(|| config.runtime_base_dir.clone());
    Ok(local_repair_jobs_value(
        &runtime_base_dir,
        limit,
        now_ms_value.unwrap_or_else(now_ms),
    )
    .to_string())
}

pub fn local_repair_executor_json_from_parts(
    config: &HubConfig,
    runtime_base_dir: Option<PathBuf>,
    request: ModelLocalRepairExecutorRequest,
    now_ms_value: Option<u128>,
) -> Result<String, String> {
    let runtime_base_dir = runtime_base_dir.unwrap_or_else(|| config.runtime_base_dir.clone());
    Ok(local_repair_executor_value(
        &runtime_base_dir,
        request,
        now_ms_value.unwrap_or_else(now_ms),
    )
    .to_string())
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

#[derive(Debug, Clone, Copy)]
struct LocalCapabilityTaskSpec {
    task_kind: &'static str,
    capability: &'static str,
    label: &'static str,
}

const LOCAL_CAPABILITY_TASK_SPECS: &[LocalCapabilityTaskSpec] = &[
    LocalCapabilityTaskSpec {
        task_kind: "text_generate",
        capability: "text.generate",
        label: "Text generation",
    },
    LocalCapabilityTaskSpec {
        task_kind: "embedding",
        capability: "embedding.generate",
        label: "Embeddings",
    },
    LocalCapabilityTaskSpec {
        task_kind: "vision_understand",
        capability: "vision.describe",
        label: "Vision understanding",
    },
    LocalCapabilityTaskSpec {
        task_kind: "ocr",
        capability: "vision.ocr",
        label: "OCR",
    },
    LocalCapabilityTaskSpec {
        task_kind: "speech_to_text",
        capability: "audio.transcribe",
        label: "Speech to text",
    },
    LocalCapabilityTaskSpec {
        task_kind: "text_to_speech",
        capability: "audio.tts",
        label: "Text to speech",
    },
];

#[derive(Debug, Clone)]
struct RuntimeProviderSummary {
    provider_id: String,
    ok: bool,
    reason_code: String,
    import_error: String,
    runtime_source: String,
    runtime_source_path: String,
    available_capabilities: Vec<String>,
    available_task_kinds: Vec<String>,
    runtime_missing_requirements: Vec<String>,
    updated_at_ms: u64,
    repair_action: String,
}

fn local_capability_summary_value(
    runtime_base_dir: &Path,
    local_models: &[xhub_runtime::LocalModelInventoryRow],
    updated_at_ms: u128,
) -> Value {
    let provider_summaries = runtime_provider_summaries(runtime_base_dir);
    let ready_task_count = LOCAL_CAPABILITY_TASK_SPECS
        .iter()
        .filter(|spec| {
            local_models.iter().any(|row| {
                local_model_has_capability(row, spec.capability) && local_model_row_is_ready(row)
            })
        })
        .count();
    let all_tasks_ready = ready_task_count == LOCAL_CAPABILITY_TASK_SPECS.len();
    let coverage_state = if all_tasks_ready {
        "complete"
    } else if ready_task_count > 0 {
        "partial"
    } else {
        "blocked"
    };
    let mut by_task = serde_json::Map::new();
    for spec in LOCAL_CAPABILITY_TASK_SPECS {
        by_task.insert(
            spec.task_kind.to_string(),
            local_capability_task_value(spec, local_models, &provider_summaries),
        );
    }

    json!({
        "schema_version": MODEL_LOCAL_CAPABILITY_SUMMARY_SCHEMA_VERSION,
        "ok": true,
        "updated_at_ms": updated_at_ms.min(i64::MAX as u128) as i64,
        "runtime_base_dir": runtime_base_dir.display().to_string(),
        "ready": ready_task_count > 0,
        "all_tasks_ready": all_tasks_ready,
        "coverage_state": coverage_state,
        "ready_task_count": ready_task_count,
        "task_count": LOCAL_CAPABILITY_TASK_SPECS.len(),
        "by_task": by_task,
        "providers": provider_summaries
            .iter()
            .map(runtime_provider_summary_json)
            .collect::<Vec<Value>>(),
        "secret_fields_included": false,
        "xt_guidance": {
            "source_of_truth": "hub",
            "consume_for": "local_model_task_coverage_and_repair_hints",
            "route_policy": "XT should route through Hub /model/route and use this summary for UI readiness only.",
            "must_not_include_secret_material": true
        }
    })
}

fn local_capability_task_value(
    spec: &LocalCapabilityTaskSpec,
    local_models: &[xhub_runtime::LocalModelInventoryRow],
    provider_summaries: &[RuntimeProviderSummary],
) -> Value {
    let candidates = local_models
        .iter()
        .filter(|row| local_model_has_capability(row, spec.capability))
        .collect::<Vec<&xhub_runtime::LocalModelInventoryRow>>();
    let ready_models = candidates
        .iter()
        .copied()
        .filter(|row| local_model_row_is_ready(row))
        .collect::<Vec<&xhub_runtime::LocalModelInventoryRow>>();
    let blocked_models = candidates
        .iter()
        .copied()
        .filter(|row| !local_model_row_is_ready(row))
        .collect::<Vec<&xhub_runtime::LocalModelInventoryRow>>();
    let primary_blocking_reason_code = blocked_models
        .iter()
        .find_map(|row| {
            let reason = local_model_primary_blocker(row);
            if reason.is_empty() {
                None
            } else {
                Some(reason)
            }
        })
        .or_else(|| primary_provider_blocker(provider_summaries, spec.capability))
        .unwrap_or_default();
    let state = local_capability_task_state(
        ready_models.len(),
        candidates.len(),
        primary_blocking_reason_code.as_str(),
    );
    let mut candidate_providers = BTreeSet::new();
    for row in &candidates {
        if !row.runtime_provider.trim().is_empty() {
            candidate_providers.insert(row.runtime_provider.clone());
        }
    }
    for provider in provider_summaries {
        if provider
            .available_capabilities
            .iter()
            .any(|capability| capability == spec.capability)
        {
            candidate_providers.insert(provider.provider_id.clone());
        }
    }

    json!({
        "task_kind": spec.task_kind,
        "capability": spec.capability,
        "label": spec.label,
        "ready": !ready_models.is_empty(),
        "state": state,
        "ready_model_count": ready_models.len(),
        "candidate_model_count": candidates.len(),
        "blocked_model_count": blocked_models.len(),
        "candidate_provider_ids": candidate_providers.into_iter().collect::<Vec<String>>(),
        "ready_model_ids": ready_models
            .iter()
            .map(|row| row.model_id.clone())
            .collect::<Vec<String>>(),
        "blocked_model_refs": blocked_models
            .iter()
            .take(8)
            .map(|row| local_model_ref_value(row))
            .collect::<Vec<Value>>(),
        "primary_blocking_reason_code": primary_blocking_reason_code,
        "repair_action": local_capability_repair_action(
            state,
            spec.task_kind,
            primary_blocking_reason_code.as_str(),
            &blocked_models,
            provider_summaries,
        ),
    })
}

fn local_capability_task_state(
    ready_model_count: usize,
    candidate_model_count: usize,
    primary_blocking_reason_code: &str,
) -> &'static str {
    if ready_model_count > 0 {
        return "ready";
    }
    if candidate_model_count == 0 {
        return "no_model";
    }
    let reason = normalized_token(primary_blocking_reason_code);
    if reason.contains("missing")
        || reason.contains("not_found")
        || reason.contains("unavailable")
        || reason.contains("helper_binary")
    {
        return "missing_runtime";
    }
    if reason.contains("capability_mismatch") {
        return "capability_blocked";
    }
    "blocked"
}

fn local_capability_repair_action(
    state: &str,
    task_kind: &str,
    primary_blocking_reason_code: &str,
    blocked_models: &[&xhub_runtime::LocalModelInventoryRow],
    provider_summaries: &[RuntimeProviderSummary],
) -> String {
    if state == "ready" {
        return "none".to_string();
    }
    if state == "no_model" {
        return format!("add_local_model:{task_kind}");
    }
    if let Some(provider) = blocked_models
        .iter()
        .filter_map(|row| {
            provider_summaries
                .iter()
                .find(|provider| provider.provider_id == row.runtime_provider)
        })
        .find(|provider| !provider.ok || !provider.runtime_missing_requirements.is_empty())
    {
        return provider.repair_action.clone();
    }
    let reason = normalized_token(primary_blocking_reason_code);
    if reason.contains("capability_mismatch") {
        return format!("enable_provider_capability:{task_kind}");
    }
    "inspect_model_runtime_preflight".to_string()
}

fn local_model_has_capability(
    row: &xhub_runtime::LocalModelInventoryRow,
    required_capability: &str,
) -> bool {
    row.capabilities
        .iter()
        .any(|capability| normalized_capability(capability) == required_capability)
}

fn local_model_row_is_ready(row: &xhub_runtime::LocalModelInventoryRow) -> bool {
    row.availability_state == "ready"
        && row.blocking_reason_code.trim().is_empty()
        && row.runtime_preflight.availability_state == "ready"
        && row.runtime_preflight.blocking_reason_code.trim().is_empty()
}

fn local_model_primary_blocker(row: &xhub_runtime::LocalModelInventoryRow) -> String {
    if !row.blocking_reason_code.trim().is_empty() {
        return row.blocking_reason_code.clone();
    }
    if !row.runtime_preflight.blocking_reason_code.trim().is_empty() {
        return row.runtime_preflight.blocking_reason_code.clone();
    }
    if !row
        .runtime_preflight
        .runtime_missing_requirements
        .is_empty()
    {
        return format!(
            "missing_requirements:{}",
            row.runtime_preflight.runtime_missing_requirements.join(",")
        );
    }
    if row.availability_state != "ready" {
        return row.availability_state.clone();
    }
    String::new()
}

fn local_model_ref_value(row: &xhub_runtime::LocalModelInventoryRow) -> Value {
    json!({
        "model_id": row.model_id,
        "display_name": row.display_name,
        "runtime_provider": row.runtime_provider,
        "availability_state": row.availability_state,
        "blocking_reason_code": row.blocking_reason_code,
        "runtime_preflight": {
            "availability_state": row.runtime_preflight.availability_state,
            "blocking_reason_code": row.runtime_preflight.blocking_reason_code,
            "runtime_missing_requirements": row.runtime_preflight.runtime_missing_requirements,
        }
    })
}

fn primary_provider_blocker(
    provider_summaries: &[RuntimeProviderSummary],
    capability: &str,
) -> Option<String> {
    provider_summaries
        .iter()
        .find(|provider| {
            !provider.ok
                && provider
                    .available_capabilities
                    .iter()
                    .any(|available| available == capability)
        })
        .map(|provider| first_non_empty(&provider.reason_code, "runtime_provider_unavailable"))
}

fn runtime_provider_summaries(runtime_base_dir: &Path) -> Vec<RuntimeProviderSummary> {
    let path = runtime_base_dir.join("ai_runtime_status.json");
    let Ok(raw) = fs::read_to_string(path) else {
        return Vec::new();
    };
    let Ok(value) = serde_json::from_str::<Value>(&raw) else {
        return Vec::new();
    };
    let mut out = Vec::new();
    if let Some(providers) = value.get("providers").and_then(Value::as_object) {
        for (provider_id, provider_value) in providers {
            out.push(runtime_provider_summary_from_value(
                provider_id,
                provider_value,
            ));
        }
    }
    if out.is_empty() {
        let provider = first_non_empty(
            &first_value_string(&value, &["provider", "provider_id", "providerId"]),
            "mlx",
        );
        if value.get("ok").is_some() || value.get("reasonCode").is_some() {
            out.push(runtime_provider_summary_from_value(&provider, &value));
        }
    }
    out.sort_by(|lhs, rhs| lhs.provider_id.cmp(&rhs.provider_id));
    out
}

fn runtime_provider_summary_from_value(provider_id: &str, value: &Value) -> RuntimeProviderSummary {
    let provider_id = normalized_provider_id(&first_non_empty(
        &first_value_string(value, &["provider", "provider_id", "providerId"]),
        provider_id,
    ));
    let available_capabilities = normalized_capability_values(
        value,
        &[
            "available_task_kinds",
            "availableTaskKinds",
            "real_task_kinds",
            "realTaskKinds",
            "capabilities",
        ],
    );
    let runtime_missing_requirements = sorted_string_values(
        value,
        &[
            "runtime_missing_requirements",
            "runtimeMissingRequirements",
            "missing_requirements",
            "missingRequirements",
        ],
    );
    let ok = value.get("ok").and_then(Value::as_bool).unwrap_or(false);
    let reason_code = normalized_token(&first_value_string(
        value,
        &["reason_code", "reasonCode", "error"],
    ));
    let import_error = first_value_string(value, &["import_error", "importError"]);
    let repair_action = provider_repair_action(
        &provider_id,
        ok,
        &reason_code,
        &runtime_missing_requirements,
        &import_error,
    );
    RuntimeProviderSummary {
        provider_id,
        ok,
        reason_code,
        import_error,
        runtime_source: first_value_string(value, &["runtime_source", "runtimeSource"]),
        runtime_source_path: first_value_string(
            value,
            &["runtime_source_path", "runtimeSourcePath"],
        ),
        available_task_kinds: task_kinds_for_capabilities(&available_capabilities),
        available_capabilities,
        runtime_missing_requirements,
        updated_at_ms: first_value_u64(value, &["updated_at_ms", "updatedAtMs", "updatedAt"])
            .unwrap_or(0),
        repair_action,
    }
}

fn runtime_provider_summary_json(provider: &RuntimeProviderSummary) -> Value {
    json!({
        "provider_id": provider.provider_id,
        "ok": provider.ok,
        "reason_code": provider.reason_code,
        "import_error": provider.import_error,
        "runtime_source": provider.runtime_source,
        "runtime_source_path": provider.runtime_source_path,
        "available_task_kinds": provider.available_task_kinds,
        "available_capabilities": provider.available_capabilities,
        "runtime_missing_requirements": provider.runtime_missing_requirements,
        "updated_at_ms": provider.updated_at_ms,
        "repair_action": provider.repair_action,
    })
}

fn normalized_provider_id(raw: &str) -> String {
    match normalized_token(raw).replace('-', "_").as_str() {
        "llamacpp" | "llama_cpp" => "llama.cpp".to_string(),
        other => other.to_string(),
    }
}

fn provider_repair_action(
    provider_id: &str,
    ok: bool,
    reason_code: &str,
    missing_requirements: &[String],
    import_error: &str,
) -> String {
    if ok {
        return "none".to_string();
    }
    let joined = format!(
        "{} {} {} {}",
        provider_id,
        reason_code,
        import_error,
        missing_requirements.join(" ")
    )
    .to_ascii_lowercase();
    if joined.contains("mlx_vlm") {
        return "install_provider_pack:mlx_vlm".to_string();
    }
    if joined.contains("torch") || joined.contains("transformers") {
        return "install_provider_pack:transformers".to_string();
    }
    if joined.contains("helper_binary") || joined.contains("llama.cpp") {
        return "install_helper_binary:llama.cpp".to_string();
    }
    if reason_code == "no_registered_models" {
        return format!("register_local_model:{provider_id}");
    }
    format!("repair_provider_runtime:{provider_id}")
}

#[derive(Debug, Clone)]
struct ResolvedLocalRepairAction {
    action: String,
    task_kind: String,
    provider_id: String,
    source: String,
}

#[derive(Debug, Clone, Copy)]
struct ProviderPackRepairSpec {
    engine: &'static str,
    execution_mode: &'static str,
    supported_domains: &'static [&'static str],
    expected_task_kinds: &'static [&'static str],
    python_import_modules: &'static [&'static str],
    python_packages: &'static [&'static str],
    helper_binary: &'static str,
    notes: &'static [&'static str],
}

fn local_repair_plan_value(
    runtime_base_dir: &Path,
    request: &ModelLocalRepairPlanRequest,
    local_models: &[xhub_runtime::LocalModelInventoryRow],
    provider_summaries: &[RuntimeProviderSummary],
    updated_at_ms: u128,
) -> Value {
    let resolved = resolve_local_repair_action(request, local_models, provider_summaries);
    let details = local_repair_plan_details(&resolved, provider_summaries);
    let mut root = serde_json::Map::new();
    root.insert(
        "schema_version".to_string(),
        json!(MODEL_LOCAL_RUNTIME_REPAIR_PLAN_SCHEMA_VERSION),
    );
    root.insert("ok".to_string(), json!(true));
    root.insert(
        "updated_at_ms".to_string(),
        json!(updated_at_ms.min(i64::MAX as u128) as i64),
    );
    root.insert(
        "runtime_base_dir".to_string(),
        json!(runtime_base_dir.display().to_string()),
    );
    root.insert(
        "request".to_string(),
        json!({
            "action": request.action.trim(),
            "task_kind": request.task_kind.trim(),
            "provider_id": request.provider_id.trim(),
        }),
    );
    root.insert(
        "resolved".to_string(),
        json!({
            "action": resolved.action,
            "task_kind": resolved.task_kind,
            "provider_id": resolved.provider_id,
            "source": resolved.source,
        }),
    );
    root.insert("secret_fields_included".to_string(), json!(false));
    root.insert(
        "xt_guidance".to_string(),
        json!({
            "source_of_truth": "hub",
            "consume_for": "local_model_runtime_repair_ui",
            "must_request_user_confirmation_before_install": true,
            "must_not_auto_install_network_dependencies": true,
            "rerun_after_repair": ["/model/capabilities", "/local-ml/readiness"],
        }),
    );
    root.insert(
        "confirmation".to_string(),
        json!({
            "required_for_apply": resolved.action != "none",
            "token_hint": local_repair_confirmation_token(&resolved.action),
            "apply_endpoint": "/model/repair-apply",
            "heavy_work_policy": "never_run_installs_on_ui_or_http_request_thread"
        }),
    );
    if let Value::Object(details) = details {
        for (key, value) in details {
            root.insert(key, value);
        }
    }
    Value::Object(root)
}

fn local_repair_apply_value(
    runtime_base_dir: &Path,
    request: &ModelLocalRepairApplyRequest,
    plan: Value,
    updated_at_ms: u128,
) -> Result<Value, String> {
    let resolved = plan.get("resolved").cloned().unwrap_or(Value::Null);
    let target = plan.get("target").cloned().unwrap_or(Value::Null);
    let requirements = plan.get("requirements").cloned().unwrap_or(Value::Null);
    let steps = plan.get("steps").cloned().unwrap_or_else(|| json!([]));
    let resolved_action = value_string(&resolved, "action");
    let requested_action = normalized_token(&request.action);
    let action_matches = requested_action.is_empty() || requested_action == resolved_action;
    let plan_state = value_string(&plan, "state");
    let confirmation_token = local_repair_confirmation_token(&resolved_action);
    let token_matches = request.confirmation_token.trim() == confirmation_token;
    let confirmation_passed = request.confirm && token_matches;
    let can_create_job =
        plan_state == "repair_required" && resolved_action != "none" && action_matches;
    let dry_run = request.dry_run || !confirmation_passed || !can_create_job;
    let job_policy = json!({
        "execution_mode": "queued_nonblocking",
        "ui_thread_blocking_allowed": false,
        "http_request_blocking_allowed": false,
        "network_install_requires_user_approval": true,
        "executor": "rust_model_repair_executor",
        "executor_ready": true,
        "executor_command": "model repair-executor --allow-network true",
    });

    if !can_create_job || dry_run {
        let status = if plan_state != "repair_required" || resolved_action == "none" {
            "not_required"
        } else if !action_matches {
            "stale_repair_action"
        } else if request.confirm && !token_matches {
            "confirmation_token_mismatch"
        } else {
            "confirmation_required"
        };
        return Ok(json!({
            "schema_version": MODEL_LOCAL_RUNTIME_REPAIR_APPLY_SCHEMA_VERSION,
            "ok": true,
            "accepted": false,
            "dry_run": true,
            "status": status,
            "updated_at_ms": updated_at_ms.min(i64::MAX as u128) as i64,
            "runtime_base_dir": runtime_base_dir.display().to_string(),
            "resolved": resolved,
            "target": target,
            "requirements": requirements,
            "steps": steps,
            "confirmation": {
                "required": plan_state == "repair_required" && resolved_action != "none",
                "confirm": request.confirm,
                "token_matches": token_matches,
                "token_hint": confirmation_token,
            },
            "job_policy": job_policy,
            "plan": plan,
            "secret_fields_included": false,
        }));
    }

    if local_registry_repair_action(&resolved_action) {
        return Ok(apply_local_model_registry_repair_value(
            runtime_base_dir,
            request,
            plan,
            updated_at_ms,
        ));
    }

    let job_id = local_repair_job_id(&resolved_action, updated_at_ms);
    let jobs_dir = local_repair_jobs_dir(runtime_base_dir);
    fs::create_dir_all(&jobs_dir)
        .map_err(|err| format!("model repair job dir create failed: {err}"))?;
    let job_path = jobs_dir.join(format!("{job_id}.json"));
    let job = json!({
        "schema_version": MODEL_LOCAL_RUNTIME_REPAIR_JOB_SCHEMA_VERSION,
        "job_id": job_id,
        "status": "queued_waiting_executor",
        "created_at_ms": updated_at_ms.min(i64::MAX as u128) as i64,
        "updated_at_ms": updated_at_ms.min(i64::MAX as u128) as i64,
        "runtime_base_dir": runtime_base_dir.display().to_string(),
        "requested_by": first_non_empty(&request.requested_by, "unknown"),
        "resolved": resolved,
        "target": target,
        "requirements": requirements,
        "steps": steps,
        "plan": plan,
        "job_policy": job_policy,
        "executor_state": {
            "ready": true,
            "reason_code": "rust_model_repair_executor_available",
            "next_step": "Run Rust model repair executor in a background process after explicit network approval; never execute installs on UI or HTTP request threads."
        },
        "secret_fields_included": false,
    });
    let raw = serde_json::to_vec_pretty(&job)
        .map_err(|err| format!("model repair job serialize failed: {err}"))?;
    fs::write(&job_path, raw).map_err(|err| format!("model repair job write failed: {err}"))?;

    Ok(json!({
        "schema_version": MODEL_LOCAL_RUNTIME_REPAIR_APPLY_SCHEMA_VERSION,
        "ok": true,
        "accepted": true,
        "dry_run": false,
        "status": "queued_waiting_executor",
        "updated_at_ms": updated_at_ms.min(i64::MAX as u128) as i64,
        "runtime_base_dir": runtime_base_dir.display().to_string(),
        "job_id": job_id,
        "job_path": job_path.display().to_string(),
        "resolved": job["resolved"].clone(),
        "target": job["target"].clone(),
        "requirements": job["requirements"].clone(),
        "steps": job["steps"].clone(),
        "job_policy": job_policy,
        "post_checks": [
            {"kind": "file", "path": job_path.display().to_string(), "expect": "job status is consumed by background executor"},
            {"kind": "http", "endpoint": "/model/capabilities", "expect": "task readiness changes after executor completes"},
            {"kind": "http", "endpoint": "/local-ml/readiness", "expect": "provider readiness changes after executor completes"}
        ],
        "secret_fields_included": false,
    }))
}

fn local_registry_repair_action(action: &str) -> bool {
    let (kind, _) = repair_action_parts(action);
    matches!(kind.as_str(), "add_local_model" | "register_local_model")
}

fn apply_local_model_registry_repair_value(
    runtime_base_dir: &Path,
    request: &ModelLocalRepairApplyRequest,
    plan: Value,
    updated_at_ms: u128,
) -> Value {
    let resolved = plan.get("resolved").cloned().unwrap_or(Value::Null);
    let target = plan.get("target").cloned().unwrap_or(Value::Null);
    let resolved_action = value_string(&resolved, "action");
    let row = match local_model_registry_row_from_request(
        runtime_base_dir,
        request,
        &resolved_action,
        &target,
        updated_at_ms,
    ) {
        Ok(row) => row,
        Err((status, message)) => {
            return json!({
                "schema_version": MODEL_LOCAL_RUNTIME_REPAIR_APPLY_SCHEMA_VERSION,
                "ok": true,
                "accepted": false,
                "dry_run": false,
                "status": status,
                "message": message,
                "updated_at_ms": updated_at_ms.min(i64::MAX as u128) as i64,
                "runtime_base_dir": runtime_base_dir.display().to_string(),
                "resolved": resolved,
                "target": target,
                "plan": plan,
                "secret_fields_included": false,
            });
        }
    };

    let catalog_path = runtime_base_dir.join("models_catalog.json");
    let state_path = runtime_base_dir.join("models_state.json");
    let catalog_write = upsert_local_model_registry_file(&catalog_path, &row, updated_at_ms);
    let state_write = match catalog_write {
        Ok(_) => upsert_local_model_registry_file(&state_path, &row, updated_at_ms),
        Err(err) => Err(err),
    };
    if let Err(err) = state_write {
        return json!({
            "schema_version": MODEL_LOCAL_RUNTIME_REPAIR_APPLY_SCHEMA_VERSION,
            "ok": false,
            "accepted": false,
            "dry_run": false,
            "status": "registry_write_failed",
            "error": err,
            "updated_at_ms": updated_at_ms.min(i64::MAX as u128) as i64,
            "runtime_base_dir": runtime_base_dir.display().to_string(),
            "resolved": resolved,
            "target": target,
            "registry_paths": {
                "models_catalog": catalog_path.display().to_string(),
                "models_state": state_path.display().to_string(),
            },
            "secret_fields_included": false,
        });
    }

    let local_models = local_model_inventory_rows(runtime_base_dir);
    let capability_summary =
        local_capability_summary_value(runtime_base_dir, &local_models, updated_at_ms);
    let model_id = value_string(&row, "id");
    let task_kinds = sorted_string_values(&row, &["taskKinds", "task_kinds"]);
    json!({
        "schema_version": MODEL_LOCAL_RUNTIME_REPAIR_APPLY_SCHEMA_VERSION,
        "ok": true,
        "accepted": true,
        "dry_run": false,
        "status": "applied_local_model_registry",
        "updated_at_ms": updated_at_ms.min(i64::MAX as u128) as i64,
        "runtime_base_dir": runtime_base_dir.display().to_string(),
        "resolved": resolved,
        "target": target,
        "registered_model": {
            "model_id": model_id,
            "display_name": value_string(&row, "name"),
            "provider_id": value_string(&row, "backend"),
            "artifact_path": value_string(&row, "modelPath"),
            "task_kinds": task_kinds.clone(),
            "capabilities": sorted_string_values(&row, &["capabilities"]),
        },
        "registry_paths": {
            "models_catalog": catalog_path.display().to_string(),
            "models_state": state_path.display().to_string(),
        },
        "local_model_count": local_models.len(),
        "local_capability_summary": capability_summary,
        "post_checks": local_repair_post_checks(
            &task_kinds.first().cloned().unwrap_or_default()
        ),
        "secret_fields_included": false,
    })
}

fn local_model_registry_row_from_request(
    runtime_base_dir: &Path,
    request: &ModelLocalRepairApplyRequest,
    resolved_action: &str,
    target: &Value,
    updated_at_ms: u128,
) -> Result<Value, (&'static str, String)> {
    let artifact_path = request.artifact_path.trim();
    if artifact_path.is_empty() {
        return Err((
            "artifact_path_required",
            "local model registry repair requires artifact_path or model_path".to_string(),
        ));
    }
    let artifact_path = resolve_runtime_relative_path_for_repair(runtime_base_dir, artifact_path);
    if !artifact_path.exists() {
        return Err((
            "artifact_not_found",
            format!(
                "local model artifact does not exist: {}",
                artifact_path.display()
            ),
        ));
    }

    let task_from_action = task_kind_for_repair_action(resolved_action).unwrap_or_default();
    let task_kind = normalized_task_kind(&first_non_empty(
        &first_non_empty(&request.task_kind, &value_string(target, "task_kind")),
        &task_from_action,
    ));
    let task_kinds = normalized_task_kind_values(&first_non_empty_vec(vec![
        request.task_kinds.clone(),
        if task_kind.is_empty() {
            Vec::new()
        } else {
            vec![task_kind.clone()]
        },
    ]));
    let primary_task = task_kinds
        .first()
        .cloned()
        .unwrap_or_else(|| "text_generate".to_string());
    let provider_id = first_non_empty(
        &normalized_provider_id(&first_non_empty(
            &first_non_empty(&request.provider_id, &value_string(target, "provider_id")),
            &provider_id_for_repair_action(resolved_action).unwrap_or_default(),
        )),
        default_provider_for_task(&primary_task).unwrap_or("mlx"),
    );
    let display_name = first_non_empty(
        &request.display_name,
        &artifact_path
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("local-model"),
    );
    let model_id = first_non_empty(
        &request.model_id,
        &format!(
            "{}-{}",
            provider_id.replace('.', "-"),
            safe_model_id_slug(&display_name)
        ),
    );
    let format = first_non_empty(
        &normalized_artifact_format_for_repair(&request.format),
        &infer_artifact_format_for_repair(&artifact_path, &provider_id),
    );
    let capabilities = normalized_capability_values_for_repair(
        &first_non_empty_vec(vec![
            request.capabilities.clone(),
            task_kinds
                .iter()
                .filter_map(|task| capability_for_task(task).map(str::to_string))
                .collect(),
        ]),
        &format,
    );
    let context_length = if request.context_length > 0 {
        request.context_length
    } else {
        8192
    };

    let mut row = serde_json::Map::new();
    row.insert("id".to_string(), json!(model_id));
    row.insert("name".to_string(), json!(display_name));
    row.insert("backend".to_string(), json!(provider_id));
    row.insert("runtimeProviderID".to_string(), json!(provider_id));
    row.insert(
        "modelPath".to_string(),
        json!(artifact_path.display().to_string()),
    );
    row.insert(
        "path".to_string(),
        json!(artifact_path.display().to_string()),
    );
    row.insert("format".to_string(), json!(format));
    row.insert(
        "quant".to_string(),
        json!(first_non_empty(&request.quantization, "unknown")),
    );
    row.insert("contextLength".to_string(), json!(context_length));
    row.insert("paramsB".to_string(), json!(0.0));
    row.insert("roles".to_string(), json!([]));
    row.insert("state".to_string(), json!("available"));
    row.insert("offlineReady".to_string(), json!(true));
    row.insert("note".to_string(), json!("rust_hub_local_model_registry"));
    row.insert("taskKinds".to_string(), json!(task_kinds));
    row.insert("capabilities".to_string(), json!(capabilities));
    row.insert(
        "registeredAtMs".to_string(),
        json!(updated_at_ms.min(i64::MAX as u128) as i64),
    );
    row.insert(
        "updatedAtMs".to_string(),
        json!(updated_at_ms.min(i64::MAX as u128) as i64),
    );
    row.insert("source".to_string(), json!("rust_model_repair_apply"));
    if request.memory_bytes > 0 {
        row.insert("memoryBytes".to_string(), json!(request.memory_bytes));
        row.insert(
            "estimatedMemoryBytes".to_string(),
            json!(request.memory_bytes),
        );
    }
    Ok(Value::Object(row))
}

fn upsert_local_model_registry_file(
    path: &Path,
    row: &Value,
    updated_at_ms: u128,
) -> Result<Value, String> {
    let mut root = read_local_model_registry_file(path)?;
    let model_id = value_string(row, "id");
    if model_id.is_empty() {
        return Err("local model registry row missing id".to_string());
    }
    let mut models = root
        .get("models")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    models.retain(|item| value_string(item, "id") != model_id);
    models.push(row.clone());
    models.sort_by(|left, right| value_string(left, "id").cmp(&value_string(right, "id")));
    if let Value::Object(map) = &mut root {
        map.insert(
            "updatedAtMs".to_string(),
            json!(updated_at_ms.min(i64::MAX as u128) as i64),
        );
        map.insert(
            "updatedAt".to_string(),
            json!((updated_at_ms as f64) / 1000.0),
        );
        map.insert("models".to_string(), Value::Array(models));
    }
    write_json_atomic_for_repair(path, &root)?;
    Ok(root)
}

fn read_local_model_registry_file(path: &Path) -> Result<Value, String> {
    if !path.exists() {
        return Ok(json!({ "models": [] }));
    }
    let raw = fs::read_to_string(path)
        .map_err(|err| format!("local model registry read failed: {err}"))?;
    if raw_contains_potential_secret_material(&raw) {
        return Err("refusing_to_read_secret_bearing_model_registry".to_string());
    }
    let value: Value = serde_json::from_str(&raw)
        .map_err(|err| format!("local model registry parse failed: {err}"))?;
    if value.is_array() {
        return Ok(json!({ "models": value }));
    }
    if value.is_object() {
        return Ok(value);
    }
    Err("local model registry must be a JSON object or array".to_string())
}

fn write_json_atomic_for_repair(path: &Path, value: &Value) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|err| format!("local model registry parent create failed: {err}"))?;
    }
    let raw = serde_json::to_vec_pretty(value)
        .map_err(|err| format!("local model registry serialize failed: {err}"))?;
    let tmp_path = path.with_extension(format!(
        "{}.tmp",
        path.extension()
            .and_then(|ext| ext.to_str())
            .unwrap_or("json")
    ));
    fs::write(&tmp_path, raw)
        .map_err(|err| format!("local model registry temp write failed: {err}"))?;
    fs::rename(&tmp_path, path).map_err(|err| format!("local model registry rename failed: {err}"))
}

fn resolve_runtime_relative_path_for_repair(runtime_base_dir: &Path, raw: &str) -> PathBuf {
    let path = PathBuf::from(raw.trim());
    if path.is_absolute() {
        path
    } else {
        runtime_base_dir.join(path)
    }
}

fn safe_model_id_slug(value: &str) -> String {
    let mut out = String::new();
    for ch in normalized_token(value).chars() {
        if ch.is_ascii_alphanumeric() {
            out.push(ch);
        } else if !out.ends_with('-') {
            out.push('-');
        }
    }
    let out = out.trim_matches('-');
    if out.is_empty() {
        "local-model".to_string()
    } else {
        out.to_string()
    }
}

fn infer_artifact_format_for_repair(path: &Path, provider_id: &str) -> String {
    let raw = normalized_token(path.to_string_lossy().as_ref());
    if raw.ends_with(".gguf") {
        return "gguf".to_string();
    }
    if raw.ends_with(".mlmodel") || raw.ends_with(".mlmodelc") {
        return "coreml".to_string();
    }
    if raw.ends_with(".safetensors") || raw.ends_with(".bin") {
        return "transformers".to_string();
    }
    match normalized_provider_id(provider_id).as_str() {
        "mlx" | "mlx_vlm" => "mlx".to_string(),
        "llama.cpp" => "gguf".to_string(),
        "transformers" => "transformers".to_string(),
        other if !other.is_empty() => other.to_string(),
        _ => "unknown".to_string(),
    }
}

fn normalized_artifact_format_for_repair(raw: &str) -> String {
    match normalized_token(raw).replace('_', "-").as_str() {
        "gguf" => "gguf".to_string(),
        "mlx" | "mlx-lm" => "mlx".to_string(),
        "coreml" | "core-ml" | "mlmodel" | "mlmodelc" => "coreml".to_string(),
        "transformers" | "safetensors" | "hf" | "huggingface" => "transformers".to_string(),
        "" => String::new(),
        other => other.to_string(),
    }
}

fn normalized_task_kind_values(values: &[String]) -> Vec<String> {
    let mut out = values
        .iter()
        .map(|value| normalized_task_kind(value))
        .filter(|value| !value.is_empty())
        .collect::<Vec<String>>();
    out.sort();
    out.dedup();
    out
}

fn normalized_capability_values_for_repair(values: &[String], format: &str) -> Vec<String> {
    let mut out = values
        .iter()
        .map(|value| normalized_capability(value))
        .filter(|value| !value.is_empty())
        .collect::<Vec<String>>();
    if out.is_empty() {
        out.push("text.generate".to_string());
        if format == "transformers" {
            out.push("embedding.generate".to_string());
        }
    }
    out.sort();
    out.dedup();
    out
}

fn local_repair_jobs_value(runtime_base_dir: &Path, limit: usize, updated_at_ms: u128) -> Value {
    let jobs_dir = local_repair_jobs_dir(runtime_base_dir);
    let jobs = local_repair_job_summaries(&jobs_dir, limit.clamp(1, 100));
    json!({
        "schema_version": MODEL_LOCAL_RUNTIME_REPAIR_JOBS_SCHEMA_VERSION,
        "ok": true,
        "runtime_base_dir": runtime_base_dir.display().to_string(),
        "jobs_dir": jobs_dir.display().to_string(),
        "count": jobs.len(),
        "limit": limit.clamp(1, 100),
        "jobs": jobs,
        "updated_at_ms": updated_at_ms.min(i64::MAX as u128) as i64,
        "secret_fields_included": false,
    })
}

fn local_repair_job_summaries(jobs_dir: &Path, limit: usize) -> Vec<Value> {
    let Ok(entries) = fs::read_dir(jobs_dir) else {
        return Vec::new();
    };
    let mut rows = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        let file_name = entry.file_name().to_string_lossy().to_string();
        if !file_name.ends_with(".json") {
            continue;
        }
        let Ok(raw) = fs::read_to_string(&path) else {
            continue;
        };
        if raw_contains_potential_secret_material(&raw) {
            continue;
        }
        let Ok(job) = serde_json::from_str::<Value>(&raw) else {
            continue;
        };
        if value_string(&job, "schema_version") != MODEL_LOCAL_RUNTIME_REPAIR_JOB_SCHEMA_VERSION {
            continue;
        }
        if job
            .get("secret_fields_included")
            .and_then(Value::as_bool)
            .unwrap_or(false)
        {
            continue;
        }
        let sort_ms = first_value_u64(&job, &["updated_at_ms"])
            .unwrap_or(0)
            .max(first_value_u64(&job, &["created_at_ms"]).unwrap_or(0))
            .max(file_modified_at_ms(&path));
        rows.push((
            sort_ms,
            file_name.clone(),
            summarize_local_repair_job(&path, &file_name, &job),
        ));
    }
    rows.sort_by(|left, right| right.0.cmp(&left.0).then_with(|| right.1.cmp(&left.1)));
    rows.into_iter()
        .take(limit)
        .map(|(_, _, summary)| summary)
        .collect()
}

fn summarize_local_repair_job(path: &Path, file_name: &str, job: &Value) -> Value {
    let resolved = job.get("resolved").cloned().unwrap_or(Value::Null);
    let target = job.get("target").cloned().unwrap_or(Value::Null);
    let job_policy = job.get("job_policy").cloned().unwrap_or(Value::Null);
    let executor_state = job.get("executor_state").cloned().unwrap_or(Value::Null);
    json!({
        "job_id": value_string(job, "job_id"),
        "status": value_string(job, "status"),
        "created_at_ms": first_value_u64(job, &["created_at_ms"]).unwrap_or(0),
        "updated_at_ms": first_value_u64(job, &["updated_at_ms"]).unwrap_or(0),
        "requested_by": value_string(job, "requested_by"),
        "file_name": file_name,
        "job_path": path.display().to_string(),
        "resolved": resolved,
        "target": target,
        "job_policy": job_policy,
        "executor_state": executor_state,
        "secret_fields_included": false,
    })
}

fn local_repair_executor_value(
    runtime_base_dir: &Path,
    request: ModelLocalRepairExecutorRequest,
    updated_at_ms: u128,
) -> Value {
    let jobs_dir = local_repair_jobs_dir(runtime_base_dir);
    let selected = select_next_local_repair_job(&jobs_dir);
    let Some((job_path, file_name, job)) = selected else {
        return json!({
            "schema_version": MODEL_LOCAL_RUNTIME_REPAIR_JOBS_SCHEMA_VERSION,
            "ok": true,
            "executed": false,
            "status": "no_queued_jobs",
            "runtime_base_dir": runtime_base_dir.display().to_string(),
            "jobs_dir": jobs_dir.display().to_string(),
            "updated_at_ms": updated_at_ms.min(i64::MAX as u128) as i64,
            "secret_fields_included": false,
        });
    };

    let planned = planned_local_repair_job_execution(runtime_base_dir, &job, &request);
    if value_bool(&planned, "requires_network") && !request.allow_network {
        return json!({
            "schema_version": MODEL_LOCAL_RUNTIME_REPAIR_JOBS_SCHEMA_VERSION,
            "ok": true,
            "executed": false,
            "status": "network_approval_required",
            "selected_job": summarize_local_repair_job(&job_path, &file_name, &job),
            "planned_execution": planned,
            "runtime_base_dir": runtime_base_dir.display().to_string(),
            "updated_at_ms": updated_at_ms.min(i64::MAX as u128) as i64,
            "secret_fields_included": false,
        });
    }
    if request.dry_run {
        return json!({
            "schema_version": MODEL_LOCAL_RUNTIME_REPAIR_JOBS_SCHEMA_VERSION,
            "ok": true,
            "executed": false,
            "status": "dry_run_ready",
            "selected_job": summarize_local_repair_job(&job_path, &file_name, &job),
            "planned_execution": planned,
            "runtime_base_dir": runtime_base_dir.display().to_string(),
            "updated_at_ms": updated_at_ms.min(i64::MAX as u128) as i64,
            "secret_fields_included": false,
        });
    }

    let mut running_job = job.clone();
    set_local_repair_job_running(&mut running_job, &request, updated_at_ms);
    if let Err(err) = write_local_repair_job(&job_path, &running_job) {
        return json!({
            "schema_version": MODEL_LOCAL_RUNTIME_REPAIR_JOBS_SCHEMA_VERSION,
            "ok": false,
            "executed": false,
            "status": "job_update_failed",
            "error": err,
            "selected_job": summarize_local_repair_job(&job_path, &file_name, &job),
            "runtime_base_dir": runtime_base_dir.display().to_string(),
            "updated_at_ms": updated_at_ms.min(i64::MAX as u128) as i64,
            "secret_fields_included": false,
        });
    }

    let outcome = execute_local_repair_job(runtime_base_dir, &running_job, &request);
    let success = value_bool(&outcome, "ok");
    let final_status = if success {
        "applied_pending_runtime_restart"
    } else {
        "failed"
    };
    let mut final_job = running_job;
    set_local_repair_job_finished(&mut final_job, final_status, &outcome, updated_at_ms);
    let write_error = write_local_repair_job(&job_path, &final_job).err();

    json!({
        "schema_version": MODEL_LOCAL_RUNTIME_REPAIR_JOBS_SCHEMA_VERSION,
        "ok": success && write_error.is_none(),
        "executed": true,
        "status": if write_error.is_some() { "job_update_failed" } else { final_status },
        "selected_job": summarize_local_repair_job(&job_path, &file_name, &final_job),
        "planned_execution": planned,
        "outcome": outcome,
        "write_error": write_error.unwrap_or_default(),
        "runtime_base_dir": runtime_base_dir.display().to_string(),
        "updated_at_ms": updated_at_ms.min(i64::MAX as u128) as i64,
        "secret_fields_included": false,
    })
}

fn select_next_local_repair_job(jobs_dir: &Path) -> Option<(PathBuf, String, Value)> {
    let entries = fs::read_dir(jobs_dir).ok()?;
    let mut rows = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        let file_name = entry.file_name().to_string_lossy().to_string();
        if !file_name.ends_with(".json") {
            continue;
        }
        let Ok(raw) = fs::read_to_string(&path) else {
            continue;
        };
        if raw_contains_potential_secret_material(&raw) {
            continue;
        }
        let Ok(job) = serde_json::from_str::<Value>(&raw) else {
            continue;
        };
        if value_string(&job, "schema_version") != MODEL_LOCAL_RUNTIME_REPAIR_JOB_SCHEMA_VERSION {
            continue;
        }
        if value_string(&job, "status") != "queued_waiting_executor" {
            continue;
        }
        let sort_ms = first_value_u64(&job, &["created_at_ms"])
            .unwrap_or(0)
            .max(file_modified_at_ms(&path));
        rows.push((sort_ms, file_name, path, job));
    }
    rows.sort_by(|left, right| left.0.cmp(&right.0).then_with(|| left.1.cmp(&right.1)));
    rows.into_iter()
        .next()
        .map(|(_, file_name, path, job)| (path, file_name, job))
}

fn planned_local_repair_job_execution(
    runtime_base_dir: &Path,
    job: &Value,
    request: &ModelLocalRepairExecutorRequest,
) -> Value {
    let resolved = job.get("resolved").unwrap_or(&Value::Null);
    let requirements = job.get("requirements").unwrap_or(&Value::Null);
    let action = value_string(resolved, "action");
    let packages = sorted_string_values(requirements, &["python_packages", "pythonPackages"]);
    let python = selected_repair_python(runtime_base_dir, &request.python);
    let py_deps_root = runtime_base_dir.join("py_deps");
    let site_packages = py_deps_root.join("site-packages");
    json!({
        "executor": "rust_model_repair_executor",
        "execution_mode": "background_cli_process",
        "action": action,
        "python": python,
        "py_deps_root": py_deps_root.display().to_string(),
        "site_packages": site_packages.display().to_string(),
        "marker_path": py_deps_root.join("USE_PYTHONPATH").display().to_string(),
        "python_packages": packages,
        "requires_network": action.starts_with("install_provider_pack:") && !packages.is_empty(),
        "timeout_ms": request.timeout_ms.max(1_000),
        "ui_thread_blocking_allowed": false,
        "http_request_blocking_allowed": false,
    })
}

fn set_local_repair_job_running(
    job: &mut Value,
    request: &ModelLocalRepairExecutorRequest,
    updated_at_ms: u128,
) {
    if let Value::Object(object) = job {
        object.insert("status".to_string(), json!("running_install_provider_pack"));
        object.insert(
            "updated_at_ms".to_string(),
            json!(updated_at_ms.min(i64::MAX as u128) as i64),
        );
        object.insert(
            "executor_state".to_string(),
            json!({
                "ready": true,
                "reason_code": "rust_model_repair_executor_running",
                "requested_by": first_non_empty(&request.requested_by, "unknown"),
                "ui_thread_blocking_allowed": false,
                "http_request_blocking_allowed": false,
            }),
        );
    }
}

fn set_local_repair_job_finished(
    job: &mut Value,
    status: &str,
    outcome: &Value,
    updated_at_ms: u128,
) {
    if let Value::Object(object) = job {
        object.insert("status".to_string(), json!(status));
        object.insert(
            "updated_at_ms".to_string(),
            json!(updated_at_ms.min(i64::MAX as u128) as i64),
        );
        object.insert("repair_result".to_string(), outcome.clone());
        object.insert(
            "executor_state".to_string(),
            json!({
                "ready": true,
                "reason_code": if value_bool(outcome, "ok") {
                    "rust_model_repair_executor_completed"
                } else {
                    "rust_model_repair_executor_failed"
                },
                "ui_thread_blocking_allowed": false,
                "http_request_blocking_allowed": false,
            }),
        );
    }
}

fn execute_local_repair_job(
    runtime_base_dir: &Path,
    job: &Value,
    request: &ModelLocalRepairExecutorRequest,
) -> Value {
    let resolved = job.get("resolved").unwrap_or(&Value::Null);
    let requirements = job.get("requirements").unwrap_or(&Value::Null);
    let action = value_string(resolved, "action");
    if !action.starts_with("install_provider_pack:") {
        return json!({
            "ok": false,
            "error_code": "unsupported_repair_action",
            "action": action,
        });
    }
    let packages = sorted_string_values(requirements, &["python_packages", "pythonPackages"]);
    if packages.is_empty() {
        return json!({
            "ok": false,
            "error_code": "missing_python_packages",
            "action": action,
        });
    }
    let py_deps_root = runtime_base_dir.join("py_deps");
    let site_packages = py_deps_root.join("site-packages");
    if let Err(err) = fs::create_dir_all(&site_packages) {
        return json!({
            "ok": false,
            "error_code": "py_deps_create_failed",
            "message": err.to_string(),
        });
    }
    let python = selected_repair_python(runtime_base_dir, &request.python);
    let mut args = vec![
        "-m".to_string(),
        "pip".to_string(),
        "install".to_string(),
        "--upgrade".to_string(),
        "--disable-pip-version-check".to_string(),
        "--no-input".to_string(),
        "--target".to_string(),
        site_packages.display().to_string(),
    ];
    args.extend(packages.iter().cloned());
    let output = run_command_capture(
        &python,
        &args,
        runtime_base_dir,
        request.timeout_ms.max(1_000),
    );
    if !output.ok {
        return json!({
            "ok": false,
            "error_code": output.error_code,
            "exit_code": output.exit_code,
            "stdout": safe_output_excerpt(&output.stdout),
            "stderr": safe_output_excerpt(&output.stderr),
            "python": python,
            "site_packages": site_packages.display().to_string(),
            "packages": packages,
        });
    }
    let marker = py_deps_root.join("USE_PYTHONPATH");
    if let Err(err) = fs::write(&marker, b"1\n") {
        return json!({
            "ok": false,
            "error_code": "py_deps_marker_write_failed",
            "message": err.to_string(),
            "python": python,
            "site_packages": site_packages.display().to_string(),
            "packages": packages,
        });
    }
    json!({
        "ok": true,
        "status": "installed_provider_pack_dependencies",
        "python": python,
        "site_packages": site_packages.display().to_string(),
        "marker_path": marker.display().to_string(),
        "packages": packages,
        "stdout": safe_output_excerpt(&output.stdout),
        "stderr": safe_output_excerpt(&output.stderr),
        "next_step": "Restart or refresh the Hub local AI runtime, then re-check /model/capabilities and /local-ml/readiness.",
    })
}

struct RepairCommandOutput {
    ok: bool,
    exit_code: i32,
    error_code: String,
    stdout: String,
    stderr: String,
}

fn run_command_capture(
    executable: &str,
    args: &[String],
    runtime_base_dir: &Path,
    timeout_ms: u64,
) -> RepairCommandOutput {
    let mut child = match Command::new(executable)
        .args(args)
        .env("REL_FLOW_HUB_BASE_DIR", runtime_base_dir)
        .env("PYTHONUNBUFFERED", "1")
        .env("PIP_DISABLE_PIP_VERSION_CHECK", "1")
        .env("PIP_NO_INPUT", "1")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
    {
        Ok(child) => child,
        Err(err) => {
            return RepairCommandOutput {
                ok: false,
                exit_code: -1,
                error_code: format!("spawn_failed:{err}"),
                stdout: String::new(),
                stderr: String::new(),
            }
        }
    };

    let mut stdout = child.stdout.take();
    let mut stderr = child.stderr.take();
    let stdout_handle = thread::spawn(move || {
        let mut out = String::new();
        if let Some(ref mut handle) = stdout {
            let _ = handle.read_to_string(&mut out);
        }
        out
    });
    let stderr_handle = thread::spawn(move || {
        let mut out = String::new();
        if let Some(ref mut handle) = stderr {
            let _ = handle.read_to_string(&mut out);
        }
        out
    });

    let deadline = Instant::now() + Duration::from_millis(timeout_ms);
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) => {
                if Instant::now() >= deadline {
                    let _ = child.kill();
                    let _ = child.wait();
                    let stdout = stdout_handle.join().unwrap_or_default();
                    let stderr = stderr_handle.join().unwrap_or_default();
                    return RepairCommandOutput {
                        ok: false,
                        exit_code: -1,
                        error_code: "timeout".to_string(),
                        stdout,
                        stderr,
                    };
                }
                thread::sleep(Duration::from_millis(100));
            }
            Err(err) => {
                let _ = child.kill();
                let stdout = stdout_handle.join().unwrap_or_default();
                let stderr = stderr_handle.join().unwrap_or_default();
                return RepairCommandOutput {
                    ok: false,
                    exit_code: -1,
                    error_code: format!("wait_failed:{err}"),
                    stdout,
                    stderr,
                };
            }
        }
    };
    let stdout = stdout_handle.join().unwrap_or_default();
    let stderr = stderr_handle.join().unwrap_or_default();
    RepairCommandOutput {
        ok: status.success(),
        exit_code: status.code().unwrap_or(-1),
        error_code: if status.success() {
            String::new()
        } else {
            "process_exit_failed".to_string()
        },
        stdout,
        stderr,
    }
}

fn selected_repair_python(runtime_base_dir: &Path, requested: &str) -> String {
    let trimmed = requested.trim();
    if !trimmed.is_empty() {
        return trimmed.to_string();
    }
    python_from_runtime_status(runtime_base_dir).unwrap_or_else(|| "python3".to_string())
}

fn python_from_runtime_status(runtime_base_dir: &Path) -> Option<String> {
    let raw = fs::read_to_string(runtime_base_dir.join("ai_runtime_status.json")).ok()?;
    let value = serde_json::from_str::<Value>(&raw).ok()?;
    let direct = first_value_string(
        &value,
        &[
            "pythonExecutable",
            "python_executable",
            "pythonPath",
            "python_path",
            "resolvedPythonPath",
            "resolved_python_path",
        ],
    );
    if !direct.is_empty() {
        return Some(direct);
    }
    None
}

fn write_local_repair_job(path: &Path, job: &Value) -> Result<(), String> {
    if job
        .get("secret_fields_included")
        .and_then(Value::as_bool)
        .unwrap_or(false)
    {
        return Err("refusing_to_write_secret_bearing_repair_job".to_string());
    }
    let raw = serde_json::to_vec_pretty(job)
        .map_err(|err| format!("model repair job serialize failed: {err}"))?;
    fs::write(path, raw).map_err(|err| format!("model repair job write failed: {err}"))
}

fn safe_output_excerpt(raw: &str) -> String {
    if raw_contains_potential_secret_material(raw) {
        return "[redacted_potential_secret_material]".to_string();
    }
    raw.chars().take(800).collect::<String>()
}

fn resolve_local_repair_action(
    request: &ModelLocalRepairPlanRequest,
    local_models: &[xhub_runtime::LocalModelInventoryRow],
    provider_summaries: &[RuntimeProviderSummary],
) -> ResolvedLocalRepairAction {
    let requested_action = normalized_token(&request.action);
    let requested_task_kind = normalized_task_kind(&request.task_kind);
    let requested_provider_id = normalized_provider_id(&request.provider_id);
    if !requested_action.is_empty() && requested_action != "auto" {
        return ResolvedLocalRepairAction {
            provider_id: provider_id_for_repair_action(&requested_action)
                .or_else(|| {
                    if requested_provider_id.is_empty() {
                        None
                    } else {
                        Some(requested_provider_id.clone())
                    }
                })
                .or_else(|| default_provider_for_task(&requested_task_kind).map(str::to_string))
                .unwrap_or_default(),
            task_kind: task_kind_for_repair_action(&requested_action)
                .or_else(|| {
                    if requested_task_kind.is_empty() {
                        None
                    } else {
                        Some(requested_task_kind.clone())
                    }
                })
                .unwrap_or_default(),
            action: requested_action,
            source: "request_action".to_string(),
        };
    }
    if !requested_task_kind.is_empty() {
        if let Some(spec) = local_capability_task_spec(&requested_task_kind) {
            let task_value = local_capability_task_value(spec, local_models, provider_summaries);
            let action = value_string(&task_value, "repair_action");
            return ResolvedLocalRepairAction {
                provider_id: provider_id_for_repair_action(&action)
                    .or_else(|| default_provider_for_task(&requested_task_kind).map(str::to_string))
                    .unwrap_or_default(),
                task_kind: requested_task_kind,
                action,
                source: "request_task_kind".to_string(),
            };
        }
        return ResolvedLocalRepairAction {
            action: format!("inspect_task:{requested_task_kind}"),
            task_kind: requested_task_kind,
            provider_id: String::new(),
            source: "request_task_kind_unknown".to_string(),
        };
    }
    if !requested_provider_id.is_empty() {
        let action = provider_summaries
            .iter()
            .find(|provider| provider.provider_id == requested_provider_id)
            .map(|provider| provider.repair_action.clone())
            .unwrap_or_else(|| format!("repair_provider_runtime:{requested_provider_id}"));
        return ResolvedLocalRepairAction {
            action,
            task_kind: String::new(),
            provider_id: requested_provider_id,
            source: "request_provider_id".to_string(),
        };
    }
    for spec in LOCAL_CAPABILITY_TASK_SPECS {
        let task_value = local_capability_task_value(spec, local_models, provider_summaries);
        let action = value_string(&task_value, "repair_action");
        if !action.is_empty() && action != "none" {
            return ResolvedLocalRepairAction {
                provider_id: provider_id_for_repair_action(&action)
                    .or_else(|| default_provider_for_task(spec.task_kind).map(str::to_string))
                    .unwrap_or_default(),
                task_kind: spec.task_kind.to_string(),
                action,
                source: "first_blocking_task".to_string(),
            };
        }
    }
    ResolvedLocalRepairAction {
        action: "none".to_string(),
        task_kind: String::new(),
        provider_id: String::new(),
        source: "all_tasks_ready".to_string(),
    }
}

fn local_repair_plan_details(
    resolved: &ResolvedLocalRepairAction,
    provider_summaries: &[RuntimeProviderSummary],
) -> Value {
    let (action_kind, action_target) = repair_action_parts(&resolved.action);
    match action_kind.as_str() {
        "none" => json!({
            "state": "ready",
            "safe_to_auto_apply": true,
            "requires_user_approval": false,
            "requires_network": false,
            "requires_download": false,
            "offline_bundle_supported": true,
            "summary": "Local model runtime coverage is already ready for the selected scope.",
            "target": {
                "kind": "none",
                "provider_id": resolved.provider_id,
                "task_kind": resolved.task_kind,
            },
            "requirements": {},
            "current_provider_status": Value::Null,
            "missing_requirements": [],
            "steps": [],
            "post_checks": local_repair_post_checks(&resolved.task_kind),
        }),
        "install_provider_pack" => provider_pack_repair_plan(
            &first_non_empty(&action_target, &resolved.provider_id),
            &resolved.task_kind,
            provider_summaries,
        ),
        "install_helper_binary" => helper_binary_repair_plan(
            &first_non_empty(&action_target, &resolved.provider_id),
            &resolved.task_kind,
            provider_summaries,
        ),
        "add_local_model" => {
            add_local_model_repair_plan(&first_non_empty(&action_target, &resolved.task_kind))
        }
        "register_local_model" => register_local_model_repair_plan(&first_non_empty(
            &action_target,
            &resolved.provider_id,
        )),
        "enable_provider_capability" => enable_provider_capability_repair_plan(
            &first_non_empty(&action_target, &resolved.task_kind),
            &resolved.provider_id,
            provider_summaries,
        ),
        "repair_provider_runtime" => inspect_provider_runtime_repair_plan(
            &first_non_empty(&action_target, &resolved.provider_id),
            &resolved.task_kind,
            provider_summaries,
        ),
        _ => inspect_generic_repair_plan(&resolved.action, &resolved.task_kind, provider_summaries),
    }
}

fn provider_pack_repair_plan(
    provider_id: &str,
    task_kind: &str,
    provider_summaries: &[RuntimeProviderSummary],
) -> Value {
    let provider_id = normalized_provider_id(provider_id);
    let status = provider_status_json(provider_summaries, &provider_id);
    let missing_requirements = provider_missing_requirements(provider_summaries, &provider_id)
        .unwrap_or_else(|| {
            provider_pack_repair_spec(&provider_id)
                .map(|spec| {
                    spec.python_import_modules
                        .iter()
                        .map(|module| format!("python_module:{module}"))
                        .collect::<Vec<String>>()
                })
                .unwrap_or_default()
        });
    let spec = provider_pack_repair_spec(&provider_id);
    let python_import_modules = spec
        .map(|spec| static_string_values(spec.python_import_modules))
        .unwrap_or_default();
    let python_packages = spec
        .map(|spec| static_string_values(spec.python_packages))
        .unwrap_or_default();
    let expected_task_kinds = spec
        .map(|spec| static_string_values(spec.expected_task_kinds))
        .unwrap_or_else(|| {
            if task_kind.is_empty() {
                Vec::new()
            } else {
                vec![task_kind.to_string()]
            }
        });
    let supported_domains = spec
        .map(|spec| static_string_values(spec.supported_domains))
        .unwrap_or_default();
    let execution_mode = spec
        .map(|spec| spec.execution_mode.to_string())
        .unwrap_or_else(|| "builtin_python".to_string());
    let engine = spec
        .map(|spec| spec.engine.to_string())
        .unwrap_or_else(|| provider_id.clone());
    let notes = spec
        .map(|spec| static_string_values(spec.notes))
        .unwrap_or_default();

    json!({
        "state": "repair_required",
        "safe_to_auto_apply": false,
        "requires_user_approval": true,
        "requires_network": true,
        "requires_download": true,
        "offline_bundle_supported": true,
        "summary": format!("Install or repair Hub local provider pack `{provider_id}` before XT uses local model tasks."),
        "target": {
            "kind": "provider_pack",
            "provider_id": provider_id,
            "task_kind": task_kind,
        },
        "requirements": {
            "engine": engine,
            "execution_mode": execution_mode,
            "install_target": "hub_managed_python_runtime",
            "python_import_modules": python_import_modules,
            "python_packages": python_packages,
            "supported_domains": supported_domains,
            "expected_task_kinds": expected_task_kinds,
            "notes": notes,
        },
        "current_provider_status": status,
        "missing_requirements": missing_requirements,
        "steps": [
            {
                "step_id": "confirm_provider_pack_repair",
                "action_kind": "request_user_approval",
                "title": "Confirm provider pack repair",
                "description": "Hub or XT UI must ask the user before installing runtime dependencies.",
                "requires_user_approval": true,
                "requires_network": false
            },
            {
                "step_id": "install_provider_pack_dependencies",
                "action_kind": "install_provider_pack",
                "title": "Install Hub-managed provider dependencies",
                "description": "Install the required Python modules into Hub's managed runtime, or use a trusted offline bundle.",
                "requires_user_approval": true,
                "requires_network": true
            },
            {
                "step_id": "restart_local_runtime",
                "action_kind": "restart_local_runtime",
                "title": "Restart local AI runtime",
                "description": "Restart the Hub local runtime so the provider probe can reload the installed modules.",
                "requires_user_approval": false,
                "requires_network": false
            }
        ],
        "post_checks": local_repair_post_checks(task_kind),
    })
}

fn helper_binary_repair_plan(
    provider_id: &str,
    task_kind: &str,
    provider_summaries: &[RuntimeProviderSummary],
) -> Value {
    let provider_id = normalized_provider_id(provider_id);
    json!({
        "state": "repair_required",
        "safe_to_auto_apply": false,
        "requires_user_approval": true,
        "requires_network": true,
        "requires_download": true,
        "offline_bundle_supported": true,
        "summary": format!("Install or configure the `{provider_id}` helper binary for Hub local models."),
        "target": {
            "kind": "helper_binary",
            "provider_id": provider_id,
            "task_kind": task_kind,
        },
        "requirements": {
            "execution_mode": "helper_binary_bridge",
            "install_target": "local_helper_binary",
            "helper_binary": provider_pack_repair_spec(&provider_id)
                .map(|spec| spec.helper_binary)
                .filter(|value| !value.is_empty())
                .unwrap_or("helper binary"),
            "expected_task_kinds": provider_pack_repair_spec(&provider_id)
                .map(|spec| static_string_values(spec.expected_task_kinds))
                .unwrap_or_default(),
            "notes": provider_pack_repair_spec(&provider_id)
                .map(|spec| static_string_values(spec.notes))
                .unwrap_or_default(),
        },
        "current_provider_status": provider_status_json(provider_summaries, &provider_id),
        "missing_requirements": provider_missing_requirements(provider_summaries, &provider_id)
            .unwrap_or_else(|| vec![format!("helper_binary:{provider_id}")]),
        "steps": [
            {
                "step_id": "confirm_helper_install",
                "action_kind": "request_user_approval",
                "title": "Confirm helper binary install",
                "description": "Ask the user before downloading or selecting a helper binary.",
                "requires_user_approval": true,
                "requires_network": false
            },
            {
                "step_id": "configure_helper_binary",
                "action_kind": "configure_helper_binary",
                "title": "Configure helper binary path",
                "description": "Install or select the helper binary path in Hub settings, then keep execution local.",
                "requires_user_approval": true,
                "requires_network": true
            },
            {
                "step_id": "restart_local_runtime",
                "action_kind": "restart_local_runtime",
                "title": "Restart local AI runtime",
                "description": "Restart the Hub local runtime and rerun provider readiness.",
                "requires_user_approval": false,
                "requires_network": false
            }
        ],
        "post_checks": local_repair_post_checks(task_kind),
    })
}

fn add_local_model_repair_plan(task_kind: &str) -> Value {
    let task_kind = normalized_task_kind(task_kind);
    json!({
        "state": "repair_required",
        "safe_to_auto_apply": false,
        "requires_user_approval": true,
        "requires_network": false,
        "requires_download": false,
        "offline_bundle_supported": true,
        "summary": format!("Register a local model for `{}` before XT routes that task locally.", first_non_empty(&task_kind, "requested_task")),
        "target": {
            "kind": "local_model",
            "provider_id": default_provider_for_task(&task_kind).unwrap_or(""),
            "task_kind": task_kind,
        },
        "requirements": {
            "expected_capability": capability_for_task(&task_kind).unwrap_or(""),
            "expected_task_kind": task_kind,
            "may_require_model_download": true,
            "install_target": "hub_local_model_registry",
        },
        "current_provider_status": Value::Null,
        "missing_requirements": [],
        "steps": [
            {
                "step_id": "select_or_download_model",
                "action_kind": "select_local_model_artifact",
                "title": "Select a local model artifact",
                "description": "Import an existing local model file or use an approved model source.",
                "requires_user_approval": true,
                "requires_network": false
            },
            {
                "step_id": "register_model_task",
                "action_kind": "register_local_model",
                "title": "Register model task kind",
                "description": "Register the model in Hub with the expected task kind and provider.",
                "requires_user_approval": false,
                "requires_network": false
            }
        ],
        "post_checks": local_repair_post_checks(&task_kind),
    })
}

fn register_local_model_repair_plan(provider_id: &str) -> Value {
    let provider_id = normalized_provider_id(provider_id);
    json!({
        "state": "repair_required",
        "safe_to_auto_apply": false,
        "requires_user_approval": true,
        "requires_network": false,
        "requires_download": false,
        "offline_bundle_supported": true,
        "summary": format!("Register at least one local model for provider `{provider_id}`."),
        "target": {
            "kind": "local_model_registry",
            "provider_id": provider_id,
            "task_kind": "",
        },
        "requirements": {
            "install_target": "hub_local_model_registry",
            "provider_id": provider_id,
        },
        "current_provider_status": Value::Null,
        "missing_requirements": [],
        "steps": [
            {
                "step_id": "open_model_import",
                "action_kind": "open_hub_model_import",
                "title": "Open Hub model import",
                "description": "Import or register a model artifact that matches the provider.",
                "requires_user_approval": true,
                "requires_network": false
            }
        ],
        "post_checks": local_repair_post_checks(""),
    })
}

fn enable_provider_capability_repair_plan(
    task_kind: &str,
    provider_id: &str,
    provider_summaries: &[RuntimeProviderSummary],
) -> Value {
    let task_kind = normalized_task_kind(task_kind);
    let provider_id = first_non_empty(
        &normalized_provider_id(provider_id),
        default_provider_for_task(&task_kind).unwrap_or(""),
    );
    json!({
        "state": "repair_required",
        "safe_to_auto_apply": false,
        "requires_user_approval": true,
        "requires_network": false,
        "requires_download": false,
        "offline_bundle_supported": true,
        "summary": format!("Enable or correct provider capability mapping for `{}`.", first_non_empty(&task_kind, "requested_task")),
        "target": {
            "kind": "provider_capability",
            "provider_id": provider_id,
            "task_kind": task_kind,
        },
        "requirements": {
            "expected_capability": capability_for_task(&task_kind).unwrap_or(""),
            "install_target": "hub_provider_capability_registry",
        },
        "current_provider_status": provider_status_json(provider_summaries, &provider_id),
        "missing_requirements": [],
        "steps": [
            {
                "step_id": "inspect_capability_mapping",
                "action_kind": "inspect_provider_capability",
                "title": "Inspect provider capability mapping",
                "description": "Verify the model task kind, provider pack domains, and capability tags are aligned.",
                "requires_user_approval": false,
                "requires_network": false
            },
            {
                "step_id": "save_capability_mapping",
                "action_kind": "save_provider_capability",
                "title": "Save corrected capability mapping",
                "description": "Update Hub registry metadata so routing and readiness agree.",
                "requires_user_approval": true,
                "requires_network": false
            }
        ],
        "post_checks": local_repair_post_checks(&task_kind),
    })
}

fn inspect_provider_runtime_repair_plan(
    provider_id: &str,
    task_kind: &str,
    provider_summaries: &[RuntimeProviderSummary],
) -> Value {
    let provider_id = normalized_provider_id(provider_id);
    json!({
        "state": "inspect_required",
        "safe_to_auto_apply": false,
        "requires_user_approval": false,
        "requires_network": false,
        "requires_download": false,
        "offline_bundle_supported": true,
        "summary": format!("Inspect provider `{provider_id}` runtime status before choosing a repair."),
        "target": {
            "kind": "provider_runtime",
            "provider_id": provider_id,
            "task_kind": task_kind,
        },
        "requirements": {},
        "current_provider_status": provider_status_json(provider_summaries, &provider_id),
        "missing_requirements": provider_missing_requirements(provider_summaries, &provider_id)
            .unwrap_or_default(),
        "steps": [
            {
                "step_id": "inspect_provider_status",
                "action_kind": "inspect_provider_status",
                "title": "Inspect provider status",
                "description": "Read current provider reason code, import error, and missing requirements.",
                "requires_user_approval": false,
                "requires_network": false
            }
        ],
        "post_checks": local_repair_post_checks(task_kind),
    })
}

fn inspect_generic_repair_plan(
    action: &str,
    task_kind: &str,
    provider_summaries: &[RuntimeProviderSummary],
) -> Value {
    json!({
        "state": "inspect_required",
        "safe_to_auto_apply": false,
        "requires_user_approval": false,
        "requires_network": false,
        "requires_download": false,
        "offline_bundle_supported": true,
        "summary": format!("Inspect local model runtime repair action `{}`.", first_non_empty(action, "unknown")),
        "target": {
            "kind": "runtime_preflight",
            "provider_id": provider_id_for_repair_action(action).unwrap_or_default(),
            "task_kind": task_kind,
        },
        "requirements": {},
        "current_provider_status": provider_id_for_repair_action(action)
            .map(|provider_id| provider_status_json(provider_summaries, &provider_id))
            .unwrap_or(Value::Null),
        "missing_requirements": provider_id_for_repair_action(action)
            .and_then(|provider_id| provider_missing_requirements(provider_summaries, &provider_id))
            .unwrap_or_default(),
        "steps": [
            {
                "step_id": "inspect_model_runtime_preflight",
                "action_kind": "inspect_model_runtime_preflight",
                "title": "Inspect model runtime preflight",
                "description": "Use Hub diagnostics to identify the concrete provider or model registry blocker.",
                "requires_user_approval": false,
                "requires_network": false
            }
        ],
        "post_checks": local_repair_post_checks(task_kind),
    })
}

fn provider_pack_repair_spec(provider_id: &str) -> Option<ProviderPackRepairSpec> {
    match normalized_provider_id(provider_id).as_str() {
        "mlx" => Some(ProviderPackRepairSpec {
            engine: "mlx-llm",
            execution_mode: "builtin_python",
            supported_domains: &["text"],
            expected_task_kinds: &["text_generate"],
            python_import_modules: &["mlx", "mlx_lm"],
            python_packages: &["mlx", "mlx-lm"],
            helper_binary: "",
            notes: &["offline_execution", "legacy_runtime_compatible"],
        }),
        "mlx_vlm" => Some(ProviderPackRepairSpec {
            engine: "mlx-vlm",
            execution_mode: "builtin_python",
            supported_domains: &["vision", "ocr"],
            expected_task_kinds: &["vision_understand", "ocr"],
            python_import_modules: &["mlx", "mlx_lm", "mlx_vlm", "transformers", "PIL"],
            python_packages: &["mlx", "mlx-lm", "mlx-vlm", "transformers", "Pillow"],
            helper_binary: "",
            notes: &["offline_execution", "native_mlx_multimodal_runtime"],
        }),
        "transformers" => Some(ProviderPackRepairSpec {
            engine: "hf-transformers",
            execution_mode: "builtin_python",
            supported_domains: &["embedding", "audio", "vision", "ocr"],
            expected_task_kinds: &[
                "embedding",
                "speech_to_text",
                "text_to_speech",
                "vision_understand",
                "ocr",
            ],
            python_import_modules: &["transformers", "torch", "tokenizers", "PIL"],
            python_packages: &["transformers", "torch", "tokenizers", "Pillow"],
            helper_binary: "",
            notes: &["offline_execution", "processor_required_for_multimodal"],
        }),
        "llama.cpp" => Some(ProviderPackRepairSpec {
            engine: "llama.cpp",
            execution_mode: "helper_binary_bridge",
            supported_domains: &["text", "embedding"],
            expected_task_kinds: &["text_generate", "embedding"],
            python_import_modules: &[],
            python_packages: &[],
            helper_binary: "llama-server",
            notes: &["offline_execution", "external_local_engine_required"],
        }),
        _ => None,
    }
}

fn local_capability_task_spec(task_kind: &str) -> Option<&'static LocalCapabilityTaskSpec> {
    let task_kind = normalized_task_kind(task_kind);
    LOCAL_CAPABILITY_TASK_SPECS
        .iter()
        .find(|spec| spec.task_kind == task_kind)
}

fn normalized_task_kind(value: &str) -> String {
    match normalized_token(value)
        .replace(['-', '.', ' '], "_")
        .as_str()
    {
        "" => String::new(),
        "text" | "text_generate" | "generate" | "chat" => "text_generate".to_string(),
        "embedding" | "embeddings" | "embedding_generate" => "embedding".to_string(),
        "vision" | "vision_understand" | "vision_describe" | "image_understand"
        | "image_describe" => "vision_understand".to_string(),
        "ocr" | "vision_ocr" => "ocr".to_string(),
        "speech_to_text" | "audio_transcribe" | "transcribe" | "asr" => {
            "speech_to_text".to_string()
        }
        "text_to_speech" | "audio_tts" | "tts" => "text_to_speech".to_string(),
        other => other.to_string(),
    }
}

fn repair_action_parts(action: &str) -> (String, String) {
    let normalized = normalized_token(action);
    let (kind, target) = normalized
        .split_once(':')
        .unwrap_or((normalized.as_str(), ""));
    (kind.trim().to_string(), target.trim().to_string())
}

fn local_repair_confirmation_token(action: &str) -> String {
    let action = normalized_token(action);
    if action.is_empty() {
        "confirm:none".to_string()
    } else {
        format!("confirm:{action}")
    }
}

fn local_repair_jobs_dir(runtime_base_dir: &Path) -> PathBuf {
    runtime_base_dir.join("model_repair_jobs")
}

fn local_repair_job_id(action: &str, now: u128) -> String {
    let action = normalized_token(action);
    let mut safe_action = String::new();
    for ch in action.chars() {
        if ch.is_ascii_alphanumeric() {
            safe_action.push(ch);
        } else if !safe_action.ends_with('_') {
            safe_action.push('_');
        }
    }
    let safe_action = safe_action.trim_matches('_');
    let safe_action = if safe_action.is_empty() {
        "repair".to_string()
    } else {
        safe_action.to_string()
    };
    format!(
        "model_repair_{}_{}_{}_{}",
        now.min(i64::MAX as u128) as i64,
        std::process::id(),
        MODEL_REPAIR_JOB_COUNTER.fetch_add(1, Ordering::Relaxed),
        safe_action
    )
}

fn provider_id_for_repair_action(action: &str) -> Option<String> {
    let (kind, target) = repair_action_parts(action);
    match kind.as_str() {
        "install_provider_pack"
        | "install_helper_binary"
        | "repair_provider_runtime"
        | "register_local_model" => {
            let provider_id = normalized_provider_id(&target);
            if provider_id.is_empty() {
                None
            } else {
                Some(provider_id)
            }
        }
        _ => None,
    }
}

fn task_kind_for_repair_action(action: &str) -> Option<String> {
    let (kind, target) = repair_action_parts(action);
    match kind.as_str() {
        "add_local_model" | "enable_provider_capability" | "inspect_task" => {
            let task_kind = normalized_task_kind(&target);
            if task_kind.is_empty() {
                None
            } else {
                Some(task_kind)
            }
        }
        _ => None,
    }
}

fn default_provider_for_task(task_kind: &str) -> Option<&'static str> {
    match normalized_task_kind(task_kind).as_str() {
        "text_generate" => Some("mlx"),
        "embedding" => Some("transformers"),
        "vision_understand" | "ocr" => Some("mlx_vlm"),
        "speech_to_text" | "text_to_speech" => Some("transformers"),
        _ => None,
    }
}

fn capability_for_task(task_kind: &str) -> Option<&'static str> {
    local_capability_task_spec(task_kind).map(|spec| spec.capability)
}

fn provider_status_json(provider_summaries: &[RuntimeProviderSummary], provider_id: &str) -> Value {
    let provider_id = normalized_provider_id(provider_id);
    provider_summaries
        .iter()
        .find(|provider| provider.provider_id == provider_id)
        .map(runtime_provider_summary_json)
        .unwrap_or(Value::Null)
}

fn provider_missing_requirements(
    provider_summaries: &[RuntimeProviderSummary],
    provider_id: &str,
) -> Option<Vec<String>> {
    let provider_id = normalized_provider_id(provider_id);
    provider_summaries
        .iter()
        .find(|provider| provider.provider_id == provider_id)
        .map(|provider| provider.runtime_missing_requirements.clone())
        .filter(|requirements| !requirements.is_empty())
}

fn local_repair_post_checks(task_kind: &str) -> Vec<Value> {
    let task_kind = normalized_task_kind(task_kind);
    let mut checks = vec![
        json!({
            "kind": "http",
            "endpoint": "/model/capabilities",
            "expect": "selected task reports ready or a more specific repair_action",
        }),
        json!({
            "kind": "http",
            "endpoint": "/local-ml/readiness",
            "expect": "local runtime provider probe is ready for the repaired provider",
        }),
    ];
    if !task_kind.is_empty() {
        checks.push(json!({
            "kind": "http",
            "endpoint": format!("/model/repair-plan?task_kind={task_kind}"),
            "expect": "repair plan resolves to none or next concrete blocker",
        }));
    }
    checks
}

fn static_string_values(values: &[&str]) -> Vec<String> {
    values.iter().map(|value| value.to_string()).collect()
}

fn task_kinds_for_capabilities(capabilities: &[String]) -> Vec<String> {
    let mut values = capabilities
        .iter()
        .filter_map(|capability| task_kind_for_capability(capability))
        .map(|value| value.to_string())
        .collect::<Vec<String>>();
    values.sort();
    values.dedup();
    values
}

fn task_kind_for_capability(capability: &str) -> Option<&'static str> {
    match normalized_capability(capability).as_str() {
        "text.generate" | "text.summarize" | "code.assist" | "code.review" => Some("text_generate"),
        "embedding.generate" => Some("embedding"),
        "vision.describe" => Some("vision_understand"),
        "vision.ocr" => Some("ocr"),
        "audio.transcribe" => Some("speech_to_text"),
        "audio.tts" => Some("text_to_speech"),
        _ => None,
    }
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
        "commands": ["inventory", "capabilities", "repair-plan", "repair-apply", "repair-jobs", "repair-executor", "route", "compare", "reports", "readiness", "diagnostics"],
        "inventory_flags": ["--runtime-base-dir", "--now-ms"],
        "capabilities_flags": ["--runtime-base-dir", "--now-ms"],
        "repair_plan_flags": ["--action", "--task-kind", "--provider-id", "--runtime-base-dir", "--now-ms"],
        "repair_apply_flags": ["--action", "--task-kind", "--provider-id", "--confirm", "--confirmation-token", "--dry-run", "--requested-by", "--runtime-base-dir", "--now-ms"],
        "repair_jobs_flags": ["--limit", "--runtime-base-dir", "--now-ms"],
        "repair_executor_flags": ["--allow-network", "--dry-run", "--python", "--timeout-ms", "--requested-by", "--runtime-base-dir", "--now-ms"],
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

fn raw_contains_potential_secret_material(raw: &str) -> bool {
    let lower = raw.to_lowercase();
    lower.contains("sk-")
        || lower.contains("api_key")
        || lower.contains("refresh_token")
        || lower.contains("password")
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
        "text.generate" | "generate.text" | "text" => "text.generate".to_string(),
        "summarize" | "summary" | "text.summarize" => "text.summarize".to_string(),
        "coder" | "code" | "code.assist" => "code.assist".to_string(),
        "reviewer" | "code.review" | "review" => "code.review".to_string(),
        "embedding" | "embedding.generate" => "embedding.generate".to_string(),
        "vision" | "vision.understand" | "vision.describe" | "image.describe" => {
            "vision.describe".to_string()
        }
        "ocr" | "vision.ocr" => "vision.ocr".to_string(),
        "speech.to.text" | "audio.transcribe" | "transcribe" | "asr" => {
            "audio.transcribe".to_string()
        }
        "text.to.speech" | "audio.tts" | "tts" => "audio.tts".to_string(),
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
        "text.generate" | "generate.text" | "text" => "text.generate".to_string(),
        "text.summarize" | "summarize" => "text.summarize".to_string(),
        "code.assist" | "code" => "code.assist".to_string(),
        "code.review" | "review" => "code.review".to_string(),
        "embedding.generate" | "embedding" | "embeddings" => "embedding.generate".to_string(),
        "vision.understand" | "vision.describe" | "image.describe" | "image.understand" => {
            "vision.describe".to_string()
        }
        "vision.ocr" | "ocr" => "vision.ocr".to_string(),
        "speech.to.text" | "audio.transcribe" | "transcribe" | "asr" => {
            "audio.transcribe".to_string()
        }
        "text.to.speech" | "audio.tts" | "tts" => "audio.tts".to_string(),
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

    fn optional_u64(&self, key: &str) -> Result<Option<u64>, String> {
        let Some(value) = self.optional(key) else {
            return Ok(None);
        };
        value
            .parse::<u64>()
            .map(Some)
            .map_err(|err| format!("invalid --{key}: {err}"))
    }

    fn optional_bool(&self, key: &str) -> Result<Option<bool>, String> {
        let Some(value) = self.optional(key) else {
            return Ok(None);
        };
        match normalized_token(&value).as_str() {
            "1" | "true" | "yes" | "y" | "on" => Ok(Some(true)),
            "0" | "false" | "no" | "n" | "off" => Ok(Some(false)),
            _ => Err(format!("invalid --{key}: {value}")),
        }
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
    #[cfg(unix)]
    use std::os::unix::fs::PermissionsExt;
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
    fn inventory_local_capability_summary_explains_multimodal_runtime_gaps() {
        let dir = unique_temp_dir("xhub-model-capability-summary");
        fs::create_dir_all(&dir).expect("temp dir should be created");
        let text_path = dir.join("local-text.mlx");
        let vision_path = dir.join("local-vision.mlx");
        let speech_path = dir.join("local-speech.hf");
        let embedding_path = dir.join("local-embedding.hf");
        for path in [&text_path, &vision_path, &speech_path, &embedding_path] {
            fs::write(path, "fixture").expect("artifact should be written");
        }
        fs::write(
            dir.join("models_state.json"),
            format!(
                r#"{{
                  "models": [
                    {{
                      "id": "local.text",
                      "backend": "mlx",
                      "modelPath": "{}",
                      "taskKinds": ["text_generate"]
                    }},
                    {{
                      "id": "local.vision",
                      "backend": "mlx_vlm",
                      "modelPath": "{}",
                      "taskKinds": ["vision_understand", "ocr"]
                    }},
                    {{
                      "id": "local.speech",
                      "backend": "transformers",
                      "modelPath": "{}",
                      "taskKinds": ["speech_to_text"]
                    }},
                    {{
                      "id": "local.embedding",
                      "backend": "transformers",
                      "modelPath": "{}",
                      "taskKinds": ["embedding"]
                    }}
                  ]
                }}"#,
                text_path.display(),
                vision_path.display(),
                speech_path.display(),
                embedding_path.display()
            ),
        )
        .expect("models_state should be written");
        fs::write(
            dir.join("ai_runtime_status.json"),
            r#"{
              "providers": {
                "mlx": {
                  "provider": "mlx",
                  "ok": true,
                  "availableTaskKinds": ["text_generate"],
                  "runtimeSource": "fixture",
                  "updatedAtMs": 1000
                },
                "mlx_vlm": {
                  "provider": "mlx_vlm",
                  "ok": false,
                  "reasonCode": "missing_runtime",
                  "runtimeMissingRequirements": ["python_module:mlx_vlm"],
                  "importError": "missing_module:mlx_vlm",
                  "updatedAtMs": 1000
                },
                "transformers": {
                  "provider": "transformers",
                  "ok": false,
                  "reasonCode": "missing_runtime",
                  "runtimeMissingRequirements": ["python_module:torch"],
                  "importError": "missing_module:torch",
                  "updatedAtMs": 1000
                }
              }
            }"#,
        )
        .expect("runtime status should be written");
        let config = config_for_runtime_dir(dir.clone());

        let raw = inventory_json_from_parts(&config, Some(dir.clone()), Some(1000))
            .expect("inventory should read fixtures");
        let value: serde_json::Value =
            serde_json::from_str(&raw).expect("inventory json should parse");
        let summary = &value["local_capability_summary"];

        assert_eq!(
            summary["schema_version"],
            MODEL_LOCAL_CAPABILITY_SUMMARY_SCHEMA_VERSION
        );
        assert_eq!(summary["coverage_state"], "partial");
        assert_eq!(summary["all_tasks_ready"], false);
        assert_eq!(summary["by_task"]["text_generate"]["state"], "ready");
        assert_eq!(
            summary["by_task"]["vision_understand"]["state"],
            "missing_runtime"
        );
        assert_eq!(
            summary["by_task"]["vision_understand"]["repair_action"],
            "install_provider_pack:mlx_vlm"
        );
        assert_eq!(
            summary["by_task"]["speech_to_text"]["state"],
            "missing_runtime"
        );
        assert_eq!(
            summary["by_task"]["speech_to_text"]["repair_action"],
            "install_provider_pack:transformers"
        );
        assert_eq!(
            summary["providers"][1]["runtime_missing_requirements"][0],
            "python_module:mlx_vlm"
        );
        let vision_row = value["local_models"]
            .as_array()
            .unwrap()
            .iter()
            .find(|row| row["model_id"] == "local.vision")
            .expect("vision row should exist");
        assert!(vision_row["capabilities"]
            .as_array()
            .unwrap()
            .contains(&json!("vision.describe")));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn local_repair_plan_turns_capability_gap_into_safe_provider_pack_steps() {
        let dir = unique_temp_dir("xhub-model-repair-plan");
        fs::create_dir_all(&dir).expect("temp dir should be created");
        let vision_path = dir.join("local-vision.mlx");
        fs::write(&vision_path, "fixture").expect("artifact should be written");
        fs::write(
            dir.join("models_state.json"),
            format!(
                r#"{{
                  "models": [
                    {{
                      "id": "local.vision",
                      "backend": "mlx_vlm",
                      "modelPath": "{}",
                      "taskKinds": ["vision_understand", "ocr"]
                    }}
                  ]
                }}"#,
                vision_path.display()
            ),
        )
        .expect("models_state should be written");
        fs::write(
            dir.join("ai_runtime_status.json"),
            r#"{
              "providers": {
                "mlx_vlm": {
                  "provider": "mlx_vlm",
                  "ok": false,
                  "reasonCode": "missing_runtime",
                  "runtimeMissingRequirements": ["python_module:mlx_vlm"],
                  "importError": "missing_module:mlx_vlm",
                  "updatedAtMs": 1000
                }
              }
            }"#,
        )
        .expect("runtime status should be written");
        let config = config_for_runtime_dir(dir.clone());

        let raw = local_repair_plan_json_from_parts(
            &config,
            Some(dir.clone()),
            ModelLocalRepairPlanRequest {
                action: String::new(),
                task_kind: "vision_understand".to_string(),
                provider_id: String::new(),
            },
            Some(1000),
        )
        .expect("repair plan should build");
        let value: serde_json::Value =
            serde_json::from_str(&raw).expect("repair plan json should parse");

        assert_eq!(
            value["schema_version"],
            MODEL_LOCAL_RUNTIME_REPAIR_PLAN_SCHEMA_VERSION
        );
        assert_eq!(value["resolved"]["action"], "install_provider_pack:mlx_vlm");
        assert_eq!(value["target"]["provider_id"], "mlx_vlm");
        assert_eq!(value["target"]["task_kind"], "vision_understand");
        assert_eq!(value["safe_to_auto_apply"], false);
        assert_eq!(value["requires_user_approval"], true);
        assert_eq!(value["secret_fields_included"], false);
        assert!(value["requirements"]["python_import_modules"]
            .as_array()
            .unwrap()
            .contains(&json!("mlx_vlm")));
        assert_eq!(value["missing_requirements"][0], "python_module:mlx_vlm");
        assert_eq!(value["steps"][1]["action_kind"], "install_provider_pack");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn local_repair_apply_requires_confirmation_then_queues_nonblocking_job() {
        let dir = unique_temp_dir("xhub-model-repair-apply");
        fs::create_dir_all(&dir).expect("temp dir should be created");
        let vision_path = dir.join("local-vision.mlx");
        fs::write(&vision_path, "fixture").expect("artifact should be written");
        fs::write(
            dir.join("models_state.json"),
            format!(
                r#"{{
                  "models": [
                    {{
                      "id": "local.vision",
                      "backend": "mlx_vlm",
                      "modelPath": "{}",
                      "taskKinds": ["vision_understand", "ocr"]
                    }}
                  ]
                }}"#,
                vision_path.display()
            ),
        )
        .expect("models_state should be written");
        fs::write(
            dir.join("ai_runtime_status.json"),
            r#"{
              "providers": {
                "mlx_vlm": {
                  "provider": "mlx_vlm",
                  "ok": false,
                  "reasonCode": "missing_runtime",
                  "runtimeMissingRequirements": ["python_module:mlx_vlm"],
                  "importError": "missing_module:mlx_vlm"
                }
              }
            }"#,
        )
        .expect("runtime status should be written");
        let config = config_for_runtime_dir(dir.clone());

        let dry_run_raw = local_repair_apply_json_from_parts(
            &config,
            Some(dir.clone()),
            ModelLocalRepairApplyRequest {
                task_kind: "vision_understand".to_string(),
                requested_by: "test".to_string(),
                ..Default::default()
            },
            Some(1000),
        )
        .expect("dry-run apply should build");
        let dry_run: serde_json::Value =
            serde_json::from_str(&dry_run_raw).expect("apply json should parse");
        assert_eq!(
            dry_run["schema_version"],
            MODEL_LOCAL_RUNTIME_REPAIR_APPLY_SCHEMA_VERSION
        );
        assert_eq!(dry_run["accepted"], false);
        assert_eq!(dry_run["status"], "confirmation_required");
        assert_eq!(dry_run["dry_run"], true);
        assert_eq!(
            dry_run["confirmation"]["token_hint"],
            "confirm:install_provider_pack:mlx_vlm"
        );
        assert!(!local_repair_jobs_dir(&dir).exists());

        let accepted_raw = local_repair_apply_json_from_parts(
            &config,
            Some(dir.clone()),
            ModelLocalRepairApplyRequest {
                action: "install_provider_pack:mlx_vlm".to_string(),
                task_kind: "vision_understand".to_string(),
                confirm: true,
                confirmation_token: "confirm:install_provider_pack:mlx_vlm".to_string(),
                requested_by: "test".to_string(),
                ..Default::default()
            },
            Some(1001),
        )
        .expect("confirmed apply should queue");
        let accepted: serde_json::Value =
            serde_json::from_str(&accepted_raw).expect("apply json should parse");
        assert_eq!(accepted["accepted"], true);
        assert_eq!(accepted["status"], "queued_waiting_executor");
        assert_eq!(
            accepted["job_policy"]["execution_mode"],
            "queued_nonblocking"
        );
        assert_eq!(
            accepted["job_policy"]["http_request_blocking_allowed"],
            false
        );
        let job_path = PathBuf::from(accepted["job_path"].as_str().unwrap());
        assert!(job_path.exists());
        let job_raw = fs::read_to_string(job_path).expect("job should be readable");
        let job: serde_json::Value = serde_json::from_str(&job_raw).expect("job json should parse");
        assert_eq!(
            job["schema_version"],
            MODEL_LOCAL_RUNTIME_REPAIR_JOB_SCHEMA_VERSION
        );
        assert_eq!(job["status"], "queued_waiting_executor");
        assert_eq!(
            job["executor_state"]["reason_code"],
            "rust_model_repair_executor_available"
        );
        assert_eq!(job["executor_state"]["ready"], true);
        let jobs_raw =
            local_repair_jobs_json_from_parts(&config, Some(dir.clone()), 10, Some(1002))
                .expect("repair jobs should build");
        let jobs: serde_json::Value =
            serde_json::from_str(&jobs_raw).expect("repair jobs json should parse");
        assert_eq!(
            jobs["schema_version"],
            MODEL_LOCAL_RUNTIME_REPAIR_JOBS_SCHEMA_VERSION
        );
        assert_eq!(jobs["count"], 1);
        assert_eq!(jobs["jobs"][0]["job_id"], accepted["job_id"]);
        assert_eq!(jobs["jobs"][0]["status"], "queued_waiting_executor");
        assert_eq!(
            jobs["jobs"][0]["job_policy"]["http_request_blocking_allowed"],
            false
        );
        assert_eq!(jobs["secret_fields_included"], false);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn local_repair_apply_registers_existing_local_model_registry() {
        let dir = unique_temp_dir("xhub-model-repair-register-local-model");
        fs::create_dir_all(&dir).expect("temp dir should be created");
        let model_dir = dir.join("Llama-3.2-3B-Instruct-4bit");
        fs::create_dir_all(&model_dir).expect("model dir should be created");
        fs::write(model_dir.join("config.json"), "{}").expect("model config should be written");
        write_runtime_status(&dir, "mlx", true, &["text_generate"]);
        let config = config_for_runtime_dir(dir.clone());

        let raw = local_repair_apply_json_from_parts(
            &config,
            Some(dir.clone()),
            ModelLocalRepairApplyRequest {
                action: "add_local_model:text_generate".to_string(),
                task_kind: "text_generate".to_string(),
                provider_id: "mlx".to_string(),
                confirm: true,
                confirmation_token: "confirm:add_local_model:text_generate".to_string(),
                requested_by: "test".to_string(),
                model_id: "mlx-text-llama-3-2-3b-instruct-4bit-test".to_string(),
                display_name: "Llama-3.2-3B-Instruct-4bit".to_string(),
                artifact_path: model_dir.display().to_string(),
                format: "mlx".to_string(),
                quantization: "4bit".to_string(),
                task_kinds: vec!["text_generate".to_string()],
                memory_bytes: 2_338_355_490,
                ..Default::default()
            },
            Some(3000),
        )
        .expect("confirmed local registry repair should apply");
        let value: serde_json::Value = serde_json::from_str(&raw).expect("apply json should parse");

        assert_eq!(value["accepted"], true);
        assert_eq!(value["status"], "applied_local_model_registry");
        assert_eq!(
            value["registered_model"]["model_id"],
            "mlx-text-llama-3-2-3b-instruct-4bit-test"
        );
        assert!(dir.join("models_catalog.json").exists());
        assert!(dir.join("models_state.json").exists());
        assert_eq!(
            value["local_capability_summary"]["by_task"]["text_generate"]["ready"],
            true
        );
        assert_eq!(
            value["local_capability_summary"]["by_task"]["text_generate"]["ready_model_ids"][0],
            "mlx-text-llama-3-2-3b-instruct-4bit-test"
        );

        let rows = local_model_inventory_rows(&dir);
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].availability_state, "ready");
        assert_eq!(rows[0].runtime_provider, "mlx");
        assert_eq!(rows[0].capabilities, vec!["text.generate"]);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn local_repair_executor_installs_provider_pack_into_py_deps_with_fake_python() {
        let dir = unique_temp_dir("xhub-model-repair-executor");
        fs::create_dir_all(&dir).expect("temp dir should be created");
        let vision_path = dir.join("local-vision.mlx");
        fs::write(&vision_path, "fixture").expect("artifact should be written");
        fs::write(
            dir.join("models_state.json"),
            format!(
                r#"{{
                  "models": [
                    {{
                      "id": "local.vision",
                      "backend": "mlx_vlm",
                      "modelPath": "{}",
                      "taskKinds": ["vision_understand"]
                    }}
                  ]
                }}"#,
                vision_path.display()
            ),
        )
        .expect("models_state should be written");
        fs::write(
            dir.join("ai_runtime_status.json"),
            r#"{
              "pythonExecutable": "python3",
              "providers": {
                "mlx_vlm": {
                  "provider": "mlx_vlm",
                  "ok": false,
                  "reasonCode": "missing_runtime",
                  "runtimeMissingRequirements": ["python_module:mlx_vlm"],
                  "importError": "missing_module:mlx_vlm"
                }
              }
            }"#,
        )
        .expect("runtime status should be written");
        let fake_python = dir.join("fake-python.sh");
        fs::write(
            &fake_python,
            "#!/bin/sh\necho \"$@\" > \"$REL_FLOW_HUB_BASE_DIR/fake_python_args.txt\"\nexit 0\n",
        )
        .expect("fake python should be written");
        #[cfg(unix)]
        {
            let mut permissions = fs::metadata(&fake_python).unwrap().permissions();
            permissions.set_mode(0o755);
            fs::set_permissions(&fake_python, permissions).unwrap();
        }
        let config = config_for_runtime_dir(dir.clone());
        let _accepted = local_repair_apply_json_from_parts(
            &config,
            Some(dir.clone()),
            ModelLocalRepairApplyRequest {
                action: "install_provider_pack:mlx_vlm".to_string(),
                task_kind: "vision_understand".to_string(),
                confirm: true,
                confirmation_token: "confirm:install_provider_pack:mlx_vlm".to_string(),
                requested_by: "test".to_string(),
                ..Default::default()
            },
            Some(2000),
        )
        .expect("confirmed apply should queue");

        let preflight_raw = local_repair_executor_json_from_parts(
            &config,
            Some(dir.clone()),
            ModelLocalRepairExecutorRequest {
                python: fake_python.display().to_string(),
                requested_by: "test".to_string(),
                ..Default::default()
            },
            Some(2001),
        )
        .expect("executor preflight should build");
        let preflight: serde_json::Value =
            serde_json::from_str(&preflight_raw).expect("preflight should parse");
        assert_eq!(preflight["executed"], false);
        assert_eq!(preflight["status"], "network_approval_required");

        let run_raw = local_repair_executor_json_from_parts(
            &config,
            Some(dir.clone()),
            ModelLocalRepairExecutorRequest {
                allow_network: true,
                python: fake_python.display().to_string(),
                timeout_ms: 5_000,
                requested_by: "test".to_string(),
                ..Default::default()
            },
            Some(2002),
        )
        .expect("executor should run");
        let run: serde_json::Value =
            serde_json::from_str(&run_raw).expect("executor output should parse");
        assert_eq!(run["executed"], true);
        assert_eq!(run["ok"], true);
        assert_eq!(run["status"], "applied_pending_runtime_restart");
        assert!(dir.join("py_deps/USE_PYTHONPATH").exists());
        let args = fs::read_to_string(dir.join("fake_python_args.txt")).unwrap();
        assert!(args.contains("-m pip install"));

        let jobs_raw =
            local_repair_jobs_json_from_parts(&config, Some(dir.clone()), 10, Some(2003))
                .expect("repair jobs should build");
        let jobs: serde_json::Value =
            serde_json::from_str(&jobs_raw).expect("repair jobs should parse");
        assert_eq!(jobs["jobs"][0]["status"], "applied_pending_runtime_restart");
        assert_eq!(
            jobs["jobs"][0]["executor_state"]["reason_code"],
            "rust_model_repair_executor_completed"
        );
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
