use std::collections::{BTreeMap, BTreeSet};
use std::env;
use std::fs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};

use serde_json::Value;
use xhub_core::{json_escape, now_ms, HubConfig};
use xhub_db::{
    apply_baseline_migrations, read_shadow_compare_report_summary, write_shadow_compare_report,
    ShadowCompareReport, ShadowCompareReportSummary,
};
use xhub_scheduler::{
    EnqueueRunRequest, LeaseShadowEvidence, ReleaseOutcome, SchedulerConfig, SchedulerStatusView,
    SchedulerStore,
};

const SCHEMA_VERSION: &str = "xhub.scheduler_bridge.v1";
static COMPARE_REPORT_COUNTER: AtomicU64 = AtomicU64::new(1);

pub fn effective_scheduler_config(config: &HubConfig) -> SchedulerConfig {
    let policy = load_model_concurrency_policy(config);
    let fallback = SchedulerConfig::default();
    SchedulerConfig {
        global_concurrency: env_u32(
            &[
                "HUB_PAID_AI_GLOBAL_CONCURRENCY",
                "XHUB_PAID_MODEL_GLOBAL_CONCURRENCY",
            ],
            policy_u32(
                &policy,
                &[
                    "paidModelGlobalConcurrencyLimit",
                    "paid_model_global_concurrency_limit",
                ],
                fallback.global_concurrency,
            ),
            1,
            64,
        ),
        per_scope_concurrency: env_u32(
            &[
                "HUB_PAID_AI_PER_PROJECT_CONCURRENCY",
                "XHUB_PAID_MODEL_PER_PROJECT_CONCURRENCY",
            ],
            policy_u32(
                &policy,
                &[
                    "paidModelPerProjectConcurrencyLimit",
                    "paid_model_per_project_concurrency_limit",
                ],
                fallback.per_scope_concurrency,
            ),
            1,
            16,
        ),
        queue_limit: env_u32(
            &["HUB_PAID_AI_QUEUE_LIMIT", "XHUB_PAID_MODEL_QUEUE_LIMIT"],
            policy_u32(
                &policy,
                &["paidModelQueueLimit", "paid_model_queue_limit"],
                fallback.queue_limit,
            ),
            1,
            4096,
        ),
        queue_timeout_ms: env_u64(
            &[
                "HUB_PAID_AI_QUEUE_TIMEOUT_MS",
                "XHUB_PAID_MODEL_QUEUE_TIMEOUT_MS",
            ],
            policy_u64(
                &policy,
                &["paidModelQueueTimeoutMs", "paid_model_queue_timeout_ms"],
                fallback.queue_timeout_ms,
            ),
            1_000,
            300_000,
        ),
    }
}

fn load_model_concurrency_policy(config: &HubConfig) -> Value {
    let explicit_path = env::var("XHUB_MODEL_CONCURRENCY_POLICY_PATH")
        .ok()
        .or_else(|| env::var("HUB_MODEL_CONCURRENCY_POLICY_PATH").ok())
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .map(PathBuf::from);
    let fallback_path = if config.runtime_base_dir.as_os_str().is_empty() {
        None
    } else {
        Some(
            config
                .runtime_base_dir
                .join("model_concurrency_policy.json"),
        )
    };
    let Some(path) = explicit_path.or(fallback_path) else {
        return Value::Null;
    };
    fs::read_to_string(path)
        .ok()
        .and_then(|body| serde_json::from_str::<Value>(&body).ok())
        .unwrap_or(Value::Null)
}

fn policy_u32(policy: &Value, keys: &[&str], fallback: u32) -> u32 {
    keys.iter()
        .find_map(|key| policy.get(*key).and_then(|value| value.as_u64()))
        .and_then(|value| u32::try_from(value).ok())
        .unwrap_or(fallback)
}

fn policy_u64(policy: &Value, keys: &[&str], fallback: u64) -> u64 {
    keys.iter()
        .find_map(|key| policy.get(*key).and_then(|value| value.as_u64()))
        .unwrap_or(fallback)
}

fn env_u32(keys: &[&str], fallback: u32, min_value: u32, max_value: u32) -> u32 {
    keys.iter()
        .find_map(|key| env::var(key).ok())
        .and_then(|value| value.trim().parse::<u32>().ok())
        .unwrap_or(fallback)
        .clamp(min_value, max_value)
}

fn env_u64(keys: &[&str], fallback: u64, min_value: u64, max_value: u64) -> u64 {
    keys.iter()
        .find_map(|key| env::var(key).ok())
        .and_then(|value| value.trim().parse::<u64>().ok())
        .unwrap_or(fallback)
        .clamp(min_value, max_value)
}

pub fn run(config: &HubConfig, args: &[String]) -> Result<(), String> {
    let body = dispatch_json(config, args)?;
    println!("{body}");
    Ok(())
}

pub fn dispatch_json(config: &HubConfig, args: &[String]) -> Result<String, String> {
    let command = args.first().map(|value| value.as_str()).unwrap_or("help");
    if matches!(command, "help" | "-h" | "--help") {
        return Ok(help_json());
    }

    apply_baseline_migrations(&config.db_path)
        .map_err(|err| format!("scheduler bridge migration failed: {err}"))?;
    let scheduler = SchedulerStore::new(config.db_path.clone(), effective_scheduler_config(config));

    match command {
        "enqueue" => enqueue_json(&scheduler, FlagArgs::parse(&args[1..])?),
        "claim" => claim_json(&scheduler, FlagArgs::parse(&args[1..])?),
        "acquire" => acquire_json(&scheduler, FlagArgs::parse(&args[1..])?),
        "acquire-run" => acquire_run_json(&scheduler, FlagArgs::parse(&args[1..])?),
        "heartbeat" => heartbeat_json(&scheduler, FlagArgs::parse(&args[1..])?),
        "release" => release_json(&scheduler, FlagArgs::parse(&args[1..])?),
        "cancel" => cancel_json(&scheduler, FlagArgs::parse(&args[1..])?),
        "status" => status_json(&scheduler, FlagArgs::parse(&args[1..])?),
        "lease-shadow-report" => lease_shadow_report_json(&scheduler, FlagArgs::parse(&args[1..])?),
        "cutover-readiness" => {
            cutover_readiness_json(config, &scheduler, FlagArgs::parse(&args[1..])?)
        }
        "compare" => compare_json(config, &scheduler, FlagArgs::parse(&args[1..])?),
        "reports" => reports_json(config, FlagArgs::parse(&args[1..])?),
        other => Err(format!("unknown scheduler command: {other}")),
    }
}

fn enqueue_json(scheduler: &SchedulerStore, flags: FlagArgs) -> Result<String, String> {
    let request_id = flags.required("request-id")?;
    let scope_key = flags.required("scope-key")?;
    let idempotency_key = flags
        .optional("idempotency-key")
        .unwrap_or_else(|| request_id.clone());
    let result = scheduler
        .enqueue(EnqueueRunRequest {
            run_id: flags.optional("run-id"),
            request_id,
            scope_key,
            project_id: flags.optional("project-id"),
            device_id: flags.optional("device-id"),
            task_type: flags
                .optional("task-type")
                .unwrap_or_else(|| "paid_ai".to_string()),
            priority: flags.optional_i32("priority")?.unwrap_or(0),
            idempotency_key,
            not_before_ms: flags.optional_i64("not-before-ms")?,
            payload_json: flags.optional("payload-json"),
        })
        .map_err(|err| format!("scheduler enqueue failed: {err}"))?;

    Ok(format!(
        "{{\"schema_version\":\"{}\",\"ok\":true,\"command\":\"enqueue\",\"inserted\":{},\"run\":{}}}",
        SCHEMA_VERSION,
        result.inserted,
        run_json(
            result.run.run_id.as_str(),
            result.run.request_id.as_str(),
            result.run.scope_key.as_str(),
            result.run.task_type.as_str(),
            result.run.status.as_str(),
        )
    ))
}

fn claim_json(scheduler: &SchedulerStore, flags: FlagArgs) -> Result<String, String> {
    let request_id = flags.required("request-id")?;
    let scope_key = flags.required("scope-key")?;
    let idempotency_key = flags
        .optional("idempotency-key")
        .unwrap_or_else(|| request_id.clone());
    let lease_owner = flags.required("lease-owner")?;
    let lease_duration_ms = flags.optional_u64("lease-duration-ms")?.unwrap_or(30_000);
    let result = scheduler
        .claim(
            EnqueueRunRequest {
                run_id: flags.optional("run-id"),
                request_id,
                scope_key,
                project_id: flags.optional("project-id"),
                device_id: flags.optional("device-id"),
                task_type: flags
                    .optional("task-type")
                    .unwrap_or_else(|| "paid_ai".to_string()),
                priority: flags.optional_i32("priority")?.unwrap_or(0),
                idempotency_key,
                not_before_ms: flags.optional_i64("not-before-ms")?,
                payload_json: flags.optional("payload-json"),
            },
            lease_owner.as_str(),
            lease_duration_ms,
        )
        .map_err(|err| format!("scheduler claim failed: {err}"))?;

    let run = run_json(
        result.run.run_id.as_str(),
        result.run.request_id.as_str(),
        result.run.scope_key.as_str(),
        result.run.task_type.as_str(),
        result.run.status.as_str(),
    );
    let Some(leased) = result.leased else {
        return Ok(format!(
            "{{\"schema_version\":\"{}\",\"ok\":true,\"command\":\"claim\",\"inserted\":{},\"leased\":false,\"run\":{}}}",
            SCHEMA_VERSION, result.inserted, run
        ));
    };

    Ok(format!(
        "{{\"schema_version\":\"{}\",\"ok\":true,\"command\":\"claim\",\"inserted\":{},\"leased\":true,\"run\":{},\"run_id\":\"{}\",\"request_id\":\"{}\",\"scope_key\":\"{}\",\"task_type\":\"{}\",\"lease_owner\":\"{}\",\"lease_token\":\"{}\",\"lease_expires_at_ms\":{},\"attempt\":{},\"queued_ms\":{},\"payload_json\":\"{}\"}}",
        SCHEMA_VERSION,
        result.inserted,
        run,
        json_escape(&leased.run_id),
        json_escape(&leased.request_id),
        json_escape(&leased.scope_key),
        json_escape(&leased.task_type),
        json_escape(&leased.lease_owner),
        json_escape(&leased.lease_token),
        leased.lease_expires_at_ms,
        leased.attempt,
        leased.queued_ms,
        json_escape(&leased.payload_json)
    ))
}

fn acquire_json(scheduler: &SchedulerStore, flags: FlagArgs) -> Result<String, String> {
    let lease_owner = flags.required("lease-owner")?;
    let lease_duration_ms = flags.optional_u64("lease-duration-ms")?.unwrap_or(30_000);
    let result = scheduler
        .acquire_next(lease_owner.as_str(), lease_duration_ms)
        .map_err(|err| format!("scheduler acquire failed: {err}"))?;

    let Some(leased) = result else {
        return Ok(format!(
            "{{\"schema_version\":\"{}\",\"ok\":true,\"command\":\"acquire\",\"leased\":false}}",
            SCHEMA_VERSION
        ));
    };

    Ok(format!(
        "{{\"schema_version\":\"{}\",\"ok\":true,\"command\":\"acquire\",\"leased\":true,\"run_id\":\"{}\",\"request_id\":\"{}\",\"scope_key\":\"{}\",\"task_type\":\"{}\",\"lease_owner\":\"{}\",\"lease_token\":\"{}\",\"lease_expires_at_ms\":{},\"attempt\":{},\"queued_ms\":{},\"payload_json\":\"{}\"}}",
        SCHEMA_VERSION,
        json_escape(&leased.run_id),
        json_escape(&leased.request_id),
        json_escape(&leased.scope_key),
        json_escape(&leased.task_type),
        json_escape(&leased.lease_owner),
        json_escape(&leased.lease_token),
        leased.lease_expires_at_ms,
        leased.attempt,
        leased.queued_ms,
        json_escape(&leased.payload_json)
    ))
}

fn acquire_run_json(scheduler: &SchedulerStore, flags: FlagArgs) -> Result<String, String> {
    let run_id = flags.required("run-id")?;
    let lease_owner = flags.required("lease-owner")?;
    let lease_duration_ms = flags.optional_u64("lease-duration-ms")?.unwrap_or(30_000);
    let result = scheduler
        .acquire_run(run_id.as_str(), lease_owner.as_str(), lease_duration_ms)
        .map_err(|err| format!("scheduler acquire-run failed: {err}"))?;

    let Some(leased) = result else {
        return Ok(format!(
            "{{\"schema_version\":\"{}\",\"ok\":true,\"command\":\"acquire-run\",\"leased\":false,\"run_id\":\"{}\"}}",
            SCHEMA_VERSION,
            json_escape(&run_id)
        ));
    };

    Ok(format!(
        "{{\"schema_version\":\"{}\",\"ok\":true,\"command\":\"acquire-run\",\"leased\":true,\"run_id\":\"{}\",\"request_id\":\"{}\",\"scope_key\":\"{}\",\"task_type\":\"{}\",\"lease_owner\":\"{}\",\"lease_token\":\"{}\",\"lease_expires_at_ms\":{},\"attempt\":{},\"queued_ms\":{},\"payload_json\":\"{}\"}}",
        SCHEMA_VERSION,
        json_escape(&leased.run_id),
        json_escape(&leased.request_id),
        json_escape(&leased.scope_key),
        json_escape(&leased.task_type),
        json_escape(&leased.lease_owner),
        json_escape(&leased.lease_token),
        leased.lease_expires_at_ms,
        leased.attempt,
        leased.queued_ms,
        json_escape(&leased.payload_json)
    ))
}

fn heartbeat_json(scheduler: &SchedulerStore, flags: FlagArgs) -> Result<String, String> {
    let run_id = flags.required("run-id")?;
    let lease_token = flags.required("lease-token")?;
    let lease_duration_ms = flags.optional_u64("lease-duration-ms")?.unwrap_or(30_000);
    let result = scheduler
        .heartbeat(run_id.as_str(), lease_token.as_str(), lease_duration_ms)
        .map_err(|err| format!("scheduler heartbeat failed: {err}"))?;
    Ok(format!(
        "{{\"schema_version\":\"{}\",\"ok\":true,\"command\":\"heartbeat\",\"run_id\":\"{}\",\"lease_expires_at_ms\":{}}}",
        SCHEMA_VERSION,
        json_escape(&result.run_id),
        result.lease_expires_at_ms
    ))
}

fn release_json(scheduler: &SchedulerStore, flags: FlagArgs) -> Result<String, String> {
    let run_id = flags.required("run-id")?;
    let lease_token = flags.required("lease-token")?;
    let outcome = match flags
        .optional("outcome")
        .unwrap_or_else(|| "completed".to_string())
        .as_str()
    {
        "completed" => ReleaseOutcome::Completed,
        "failed" => ReleaseOutcome::Failed {
            error_code: flags
                .optional("error-code")
                .unwrap_or_else(|| "scheduler_run_failed".to_string()),
            error_message: flags.optional("error-message"),
        },
        "requeue" => ReleaseOutcome::Requeue {
            not_before_ms: flags.optional_i64("not-before-ms")?,
        },
        other => {
            return Err(format!(
                "unsupported release outcome: {other}. Use completed, failed, or requeue."
            ))
        }
    };
    let result = scheduler
        .release(run_id.as_str(), lease_token.as_str(), outcome)
        .map_err(|err| format!("scheduler release failed: {err}"))?;
    Ok(format!(
        "{{\"schema_version\":\"{}\",\"ok\":true,\"command\":\"release\",\"run_id\":\"{}\",\"status\":\"{}\"}}",
        SCHEMA_VERSION,
        json_escape(&result.run_id),
        json_escape(&result.status)
    ))
}

fn cancel_json(scheduler: &SchedulerStore, flags: FlagArgs) -> Result<String, String> {
    let run_id = flags.required("run-id")?;
    let reason = flags.optional("reason");
    let result = scheduler
        .cancel(run_id.as_str(), reason.as_deref())
        .map_err(|err| format!("scheduler cancel failed: {err}"))?;
    Ok(format!(
        "{{\"schema_version\":\"{}\",\"ok\":true,\"command\":\"cancel\",\"run_id\":\"{}\",\"status\":\"{}\"}}",
        SCHEMA_VERSION,
        json_escape(&result.run_id),
        json_escape(&result.status)
    ))
}

fn status_json(scheduler: &SchedulerStore, flags: FlagArgs) -> Result<String, String> {
    let include_queue_items = flags.enabled("include-queue-items");
    let queue_items_limit = flags.optional_usize("queue-items-limit")?.unwrap_or(50);
    status_json_from_scheduler(scheduler, include_queue_items, queue_items_limit)
}

fn status_json_from_scheduler(
    scheduler: &SchedulerStore,
    include_queue_items: bool,
    queue_items_limit: usize,
) -> Result<String, String> {
    let view = scheduler
        .status_view(include_queue_items, queue_items_limit)
        .map_err(|err| format!("scheduler status failed: {err}"))?;
    Ok(status_view_json(&view))
}

pub fn status_json_from_parts(
    config: &HubConfig,
    include_queue_items: bool,
    queue_items_limit: usize,
) -> Result<String, String> {
    apply_baseline_migrations(&config.db_path)
        .map_err(|err| format!("scheduler status migration failed: {err}"))?;
    let scheduler = SchedulerStore::new(config.db_path.clone(), effective_scheduler_config(config));
    status_json_from_scheduler(&scheduler, include_queue_items, queue_items_limit)
}

fn lease_shadow_report_json(scheduler: &SchedulerStore, flags: FlagArgs) -> Result<String, String> {
    let prefix = flags
        .optional("run-id-prefix")
        .unwrap_or_else(|| "node_paid_ai_".to_string());
    let stale_after_ms = flags.optional_u64("stale-after-ms")?.unwrap_or(300_000);
    let limit = flags.optional_usize("limit")?.unwrap_or(20);
    let evidence = scheduler
        .lease_shadow_evidence(prefix.as_str(), stale_after_ms, limit)
        .map_err(|err| format!("scheduler lease shadow report failed: {err}"))?;
    Ok(lease_shadow_evidence_json(&evidence))
}

fn cutover_readiness_json(
    config: &HubConfig,
    scheduler: &SchedulerStore,
    flags: FlagArgs,
) -> Result<String, String> {
    let component = flags
        .optional("component")
        .unwrap_or_else(|| "scheduler".to_string());
    let compare_limit = flags.optional_usize("compare-limit")?.unwrap_or(20);
    let min_compare_reports = flags
        .optional_i64("min-compare-reports")?
        .unwrap_or(10)
        .max(0);
    let max_mismatches = flags.optional_i64("max-mismatches")?.unwrap_or(0).max(0);
    let run_id_prefix = flags
        .optional("run-id-prefix")
        .unwrap_or_else(|| "node_paid_ai_".to_string());
    let stale_after_ms = flags.optional_u64("stale-after-ms")?.unwrap_or(300_000);
    let lease_report_limit = flags.optional_usize("lease-report-limit")?.unwrap_or(20);
    let min_lease_shadow_runs = flags
        .optional_i64("min-lease-shadow-runs")?
        .unwrap_or(1)
        .max(0);
    let max_stale_active = flags.optional_i64("max-stale-active")?.unwrap_or(0).max(0);
    let max_orphaned_leases = flags
        .optional_i64("max-orphaned-leases")?
        .unwrap_or(0)
        .max(0);
    let allow_active_runs = flags.enabled("allow-active-runs");

    cutover_readiness_json_from_scheduler(
        config,
        scheduler,
        CutoverReadinessParams {
            component,
            compare_limit,
            min_compare_reports,
            max_mismatches,
            run_id_prefix,
            stale_after_ms,
            lease_report_limit,
            min_lease_shadow_runs,
            max_stale_active,
            max_orphaned_leases,
            allow_active_runs,
        },
    )
}

#[derive(Debug, Clone)]
pub struct CutoverReadinessParams {
    pub component: String,
    pub compare_limit: usize,
    pub min_compare_reports: i64,
    pub max_mismatches: i64,
    pub run_id_prefix: String,
    pub stale_after_ms: u64,
    pub lease_report_limit: usize,
    pub min_lease_shadow_runs: i64,
    pub max_stale_active: i64,
    pub max_orphaned_leases: i64,
    pub allow_active_runs: bool,
}

impl Default for CutoverReadinessParams {
    fn default() -> Self {
        Self {
            component: "scheduler".to_string(),
            compare_limit: 20,
            min_compare_reports: 10,
            max_mismatches: 0,
            run_id_prefix: "node_paid_ai_".to_string(),
            stale_after_ms: 300_000,
            lease_report_limit: 20,
            min_lease_shadow_runs: 1,
            max_stale_active: 0,
            max_orphaned_leases: 0,
            allow_active_runs: false,
        }
    }
}

pub fn cutover_readiness_json_from_parts(
    config: &HubConfig,
    params: CutoverReadinessParams,
) -> Result<String, String> {
    apply_baseline_migrations(&config.db_path)
        .map_err(|err| format!("scheduler readiness migration failed: {err}"))?;
    let scheduler = SchedulerStore::new(config.db_path.clone(), effective_scheduler_config(config));
    cutover_readiness_json_from_scheduler(config, &scheduler, params)
}

fn cutover_readiness_json_from_scheduler(
    config: &HubConfig,
    scheduler: &SchedulerStore,
    params: CutoverReadinessParams,
) -> Result<String, String> {
    let compare = read_shadow_compare_report_summary(
        &config.db_path,
        params.component.as_str(),
        params.compare_limit,
    )
    .map_err(|err| format!("scheduler readiness compare report read failed: {err}"))?;
    let lease = scheduler
        .lease_shadow_evidence(
            params.run_id_prefix.as_str(),
            params.stale_after_ms,
            params.lease_report_limit,
        )
        .map_err(|err| format!("scheduler readiness lease shadow report failed: {err}"))?;

    let mut ready = true;
    let mut checks = Vec::new();
    push_readiness_check(
        &mut checks,
        &mut ready,
        "compare_min_reports",
        compare.total >= params.min_compare_reports,
        compare.total,
        params.min_compare_reports,
        "shadow compare evidence count",
    );
    push_readiness_check(
        &mut checks,
        &mut ready,
        "compare_mismatches",
        compare.mismatched <= params.max_mismatches,
        compare.mismatched,
        params.max_mismatches,
        "shadow compare mismatches must stay within threshold",
    );
    push_readiness_check(
        &mut checks,
        &mut ready,
        "lease_shadow_min_runs",
        lease.total_runs >= params.min_lease_shadow_runs,
        lease.total_runs,
        params.min_lease_shadow_runs,
        "lease shadow mirrored run evidence count",
    );
    push_readiness_check(
        &mut checks,
        &mut ready,
        "lease_shadow_stale_active",
        lease.stale_active <= params.max_stale_active,
        lease.stale_active,
        params.max_stale_active,
        "stale queued or leased mirrored runs",
    );
    push_readiness_check(
        &mut checks,
        &mut ready,
        "lease_shadow_orphaned_leases",
        lease.orphaned_leases <= params.max_orphaned_leases,
        lease.orphaned_leases,
        params.max_orphaned_leases,
        "leases without run rows",
    );

    let active_runs = lease.queued + lease.leased;
    push_readiness_check(
        &mut checks,
        &mut ready,
        "lease_shadow_active_runs",
        params.allow_active_runs || active_runs == 0,
        active_runs,
        if params.allow_active_runs {
            active_runs
        } else {
            0
        },
        if params.allow_active_runs {
            "active mirrored runs allowed by flag"
        } else {
            "active mirrored runs must drain before cutover"
        },
    );

    Ok(format!(
        "{{\"schema_version\":\"{}\",\"ok\":true,\"command\":\"cutover-readiness\",\"ready\":{},\"decision\":\"{}\",\"generated_at_ms\":{},\"thresholds\":{{\"min_compare_reports\":{},\"max_mismatches\":{},\"min_lease_shadow_runs\":{},\"max_stale_active\":{},\"max_orphaned_leases\":{},\"allow_active_runs\":{}}},\"checks\":[{}],\"compare\":{},\"lease_shadow\":{}}}",
        SCHEMA_VERSION,
        ready,
        if ready { "ready" } else { "not_ready" },
        now_ms().min(i64::MAX as u128) as i64,
        params.min_compare_reports,
        params.max_mismatches,
        params.min_lease_shadow_runs,
        params.max_stale_active,
        params.max_orphaned_leases,
        params.allow_active_runs,
        checks.join(","),
        compare_readiness_json(&compare),
        lease_shadow_readiness_json(&lease)
    ))
}

fn push_readiness_check(
    checks: &mut Vec<String>,
    ready: &mut bool,
    name: &str,
    ok: bool,
    actual: i64,
    threshold: i64,
    detail: &str,
) {
    if !ok {
        *ready = false;
    }
    checks.push(format!(
        "{{\"name\":\"{}\",\"ok\":{},\"actual\":{},\"threshold\":{},\"detail\":\"{}\"}}",
        json_escape(name),
        ok,
        actual,
        threshold,
        json_escape(detail)
    ));
}

fn compare_readiness_json(summary: &ShadowCompareReportSummary) -> String {
    format!(
        "{{\"component\":\"{}\",\"total\":{},\"matched\":{},\"mismatched\":{},\"latest_compared_at_ms\":{}}}",
        json_escape(&summary.component),
        summary.total,
        summary.matched,
        summary.mismatched,
        summary.latest_compared_at_ms
    )
}

fn lease_shadow_readiness_json(evidence: &LeaseShadowEvidence) -> String {
    format!(
        "{{\"run_id_prefix\":\"{}\",\"stale_after_ms\":{},\"totals\":{{\"runs\":{},\"queued\":{},\"leased\":{},\"completed\":{},\"failed\":{},\"canceled\":{},\"stale_active\":{},\"orphaned_leases\":{}}}}}",
        json_escape(&evidence.run_id_prefix),
        evidence.stale_after_ms,
        evidence.total_runs,
        evidence.queued,
        evidence.leased,
        evidence.completed,
        evidence.failed,
        evidence.canceled,
        evidence.stale_active,
        evidence.orphaned_leases
    )
}

fn compare_json(
    config: &HubConfig,
    scheduler: &SchedulerStore,
    flags: FlagArgs,
) -> Result<String, String> {
    let node = NodeSchedulerStatus {
        in_flight_total: flags.required_i32("node-in-flight-total")?,
        queue_depth: flags.required_i32("node-queue-depth")?,
        oldest_queued_ms: flags.optional_i64("node-oldest-queued-ms")?,
    };
    let view = scheduler
        .status_view(false, 0)
        .map_err(|err| format!("scheduler compare status failed: {err}"))?;

    let mismatches = scheduler_mismatches(&view, &node);
    let mismatch_json = mismatch_json(&mismatches);
    let rust_status_json = status_view_json(&view);
    let node_status_json = node_status_json(&node);
    let compared_at_ms = now_ms().min(i64::MAX as u128) as i64;
    let report_id = format!(
        "scheduler_compare_{}_{}_{}",
        compared_at_ms,
        std::process::id(),
        COMPARE_REPORT_COUNTER.fetch_add(1, Ordering::Relaxed)
    );
    let match_result = if mismatches.is_empty() {
        "match"
    } else {
        "mismatch"
    };

    write_shadow_compare_report(
        &config.db_path,
        &ShadowCompareReport {
            report_id: report_id.clone(),
            component: "scheduler".to_string(),
            compared_at_ms,
            match_result: match_result.to_string(),
            rust_status_json: rust_status_json.clone(),
            node_status_json: node_status_json.clone(),
            mismatch_json: mismatch_json.clone(),
        },
    )
    .map_err(|err| format!("scheduler compare report write failed: {err}"))?;

    Ok(format!(
        "{{\"schema_version\":\"{}\",\"ok\":true,\"command\":\"compare\",\"report_id\":\"{}\",\"match\":{},\"match_result\":\"{}\",\"rust\":{},\"node\":{},\"mismatches\":{}}}",
        SCHEMA_VERSION,
        json_escape(&report_id),
        mismatches.is_empty(),
        match_result,
        rust_status_json,
        node_status_json,
        mismatch_json
    ))
}

fn lease_shadow_evidence_json(evidence: &LeaseShadowEvidence) -> String {
    let event_counts: Vec<String> = evidence
        .event_counts
        .iter()
        .map(|item| {
            format!(
                "{{\"event_type\":\"{}\",\"count\":{}}}",
                json_escape(&item.event_type),
                item.count
            )
        })
        .collect();
    let recent: Vec<String> = evidence
        .recent
        .iter()
        .map(|item| {
            format!(
                "{{\"run_id\":\"{}\",\"request_id\":\"{}\",\"scope_key\":\"{}\",\"status\":\"{}\",\"created_at_ms\":{},\"updated_at_ms\":{},\"age_ms\":{},\"lease_owner\":\"{}\",\"lease_expires_at_ms\":{},\"event_count\":{},\"last_event_type\":\"{}\",\"last_event_at_ms\":{}}}",
                json_escape(&item.run_id),
                json_escape(&item.request_id),
                json_escape(&item.scope_key),
                json_escape(&item.status),
                item.created_at_ms,
                item.updated_at_ms,
                item.age_ms,
                json_escape(&item.lease_owner),
                item.lease_expires_at_ms,
                item.event_count,
                json_escape(&item.last_event_type),
                item.last_event_at_ms
            )
        })
        .collect();
    format!(
        "{{\"schema_version\":\"{}\",\"ok\":true,\"command\":\"lease-shadow-report\",\"generated_at_ms\":{},\"run_id_prefix\":\"{}\",\"stale_after_ms\":{},\"totals\":{{\"runs\":{},\"queued\":{},\"leased\":{},\"completed\":{},\"failed\":{},\"canceled\":{},\"stale_active\":{},\"orphaned_leases\":{}}},\"event_counts\":[{}],\"recent\":[{}]}}",
        SCHEMA_VERSION,
        evidence.generated_at_ms,
        json_escape(&evidence.run_id_prefix),
        evidence.stale_after_ms,
        evidence.total_runs,
        evidence.queued,
        evidence.leased,
        evidence.completed,
        evidence.failed,
        evidence.canceled,
        evidence.stale_active,
        evidence.orphaned_leases,
        event_counts.join(","),
        recent.join(",")
    )
}

fn reports_json(config: &HubConfig, flags: FlagArgs) -> Result<String, String> {
    let component = flags
        .optional("component")
        .unwrap_or_else(|| "scheduler".to_string());
    let limit = flags.optional_usize("limit")?.unwrap_or(20);
    let summary = read_shadow_compare_report_summary(&config.db_path, component.as_str(), limit)
        .map_err(|err| format!("scheduler reports read failed: {err}"))?;
    Ok(report_summary_json(&summary))
}

fn report_summary_json(summary: &ShadowCompareReportSummary) -> String {
    let rows: Vec<String> = summary
        .rows
        .iter()
        .map(|row| {
            format!(
                "{{\"report_id\":\"{}\",\"component\":\"{}\",\"compared_at_ms\":{},\"match_result\":\"{}\",\"mismatches\":{}}}",
                json_escape(&row.report_id),
                json_escape(&row.component),
                row.compared_at_ms,
                json_escape(&row.match_result),
                normalize_json_array_for_embed(&row.mismatch_json)
            )
        })
        .collect();
    format!(
        "{{\"schema_version\":\"{}\",\"ok\":true,\"command\":\"reports\",\"component\":\"{}\",\"total\":{},\"matched\":{},\"mismatched\":{},\"latest_compared_at_ms\":{},\"rows\":[{}]}}",
        SCHEMA_VERSION,
        json_escape(&summary.component),
        summary.total,
        summary.matched,
        summary.mismatched,
        summary.latest_compared_at_ms,
        rows.join(",")
    )
}

fn normalize_json_array_for_embed(value: &str) -> String {
    let trimmed = value.trim();
    if trimmed.starts_with('[') && trimmed.ends_with(']') {
        trimmed.to_string()
    } else {
        "[]".to_string()
    }
}

pub fn status_view_json(view: &SchedulerStatusView) -> String {
    format!(
        "{{\"schema_version\":\"{}\",\"ok\":true,\"command\":\"status\",\"updated_at_ms\":{},\"in_flight_total\":{},\"queue_depth\":{},\"oldest_queued_ms\":{},\"in_flight_by_scope\":{},\"queued_by_scope\":{},\"queue_items\":{}}}",
        SCHEMA_VERSION,
        view.updated_at_ms,
        view.in_flight_total,
        view.queue_depth,
        view.oldest_queued_ms,
        counters_json(&view.in_flight_by_scope),
        counters_json(&view.queued_by_scope),
        queue_items_json(&view.queue_items)
    )
}

fn counters_json(items: &[xhub_scheduler::ScopeCounter]) -> String {
    let rows: Vec<String> = items
        .iter()
        .map(|item| {
            format!(
                "{{\"scope_key\":\"{}\",\"count\":{}}}",
                json_escape(&item.scope_key),
                item.count
            )
        })
        .collect();
    format!("[{}]", rows.join(","))
}

fn queue_items_json(items: &[xhub_scheduler::QueueItemView]) -> String {
    let rows: Vec<String> = items
        .iter()
        .map(|item| {
            format!(
                "{{\"request_id\":\"{}\",\"scope_key\":\"{}\",\"enqueued_at_ms\":{},\"queued_ms\":{}}}",
                json_escape(&item.request_id),
                json_escape(&item.scope_key),
                item.enqueued_at_ms,
                item.queued_ms
            )
        })
        .collect();
    format!("[{}]", rows.join(","))
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct NodeSchedulerStatus {
    in_flight_total: i32,
    queue_depth: i32,
    oldest_queued_ms: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct SchedulerMismatch {
    field: &'static str,
    rust_value: i64,
    node_value: i64,
}

fn scheduler_mismatches(
    rust: &SchedulerStatusView,
    node: &NodeSchedulerStatus,
) -> Vec<SchedulerMismatch> {
    let mut mismatches = Vec::new();
    push_mismatch(
        &mut mismatches,
        "in_flight_total",
        rust.in_flight_total as i64,
        node.in_flight_total as i64,
    );
    push_mismatch(
        &mut mismatches,
        "queue_depth",
        rust.queue_depth as i64,
        node.queue_depth as i64,
    );
    if let Some(node_oldest) = node.oldest_queued_ms {
        push_mismatch(
            &mut mismatches,
            "oldest_queued_ms",
            rust.oldest_queued_ms,
            node_oldest,
        );
    }
    mismatches
}

fn push_mismatch(
    out: &mut Vec<SchedulerMismatch>,
    field: &'static str,
    rust_value: i64,
    node_value: i64,
) {
    if rust_value != node_value {
        out.push(SchedulerMismatch {
            field,
            rust_value,
            node_value,
        });
    }
}

fn node_status_json(status: &NodeSchedulerStatus) -> String {
    let oldest = status
        .oldest_queued_ms
        .map(|value| value.to_string())
        .unwrap_or_else(|| "null".to_string());
    format!(
        "{{\"in_flight_total\":{},\"queue_depth\":{},\"oldest_queued_ms\":{}}}",
        status.in_flight_total, status.queue_depth, oldest
    )
}

fn mismatch_json(mismatches: &[SchedulerMismatch]) -> String {
    let rows: Vec<String> = mismatches
        .iter()
        .map(|item| {
            format!(
                "{{\"field\":\"{}\",\"rust\":{},\"node\":{}}}",
                item.field, item.rust_value, item.node_value
            )
        })
        .collect();
    format!("[{}]", rows.join(","))
}

fn run_json(
    run_id: &str,
    request_id: &str,
    scope_key: &str,
    task_type: &str,
    status: &str,
) -> String {
    format!(
        "{{\"run_id\":\"{}\",\"request_id\":\"{}\",\"scope_key\":\"{}\",\"task_type\":\"{}\",\"status\":\"{}\"}}",
        json_escape(run_id),
        json_escape(request_id),
        json_escape(scope_key),
        json_escape(task_type),
        json_escape(status)
    )
}

fn help_json() -> String {
    format!(
        "{{\"schema_version\":\"{}\",\"ok\":true,\"commands\":[\"enqueue\",\"claim\",\"acquire\",\"acquire-run\",\"heartbeat\",\"release\",\"cancel\",\"status\",\"lease-shadow-report\",\"cutover-readiness\",\"compare\",\"reports\"]}}",
        SCHEMA_VERSION
    )
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
struct FlagArgs {
    values: BTreeMap<String, String>,
    switches: BTreeSet<String>,
}

impl FlagArgs {
    fn parse(args: &[String]) -> Result<Self, String> {
        let mut parsed = Self::default();
        let mut index = 0;
        while index < args.len() {
            let token = &args[index];
            if !token.starts_with("--") {
                return Err(format!("unexpected positional argument: {token}"));
            }

            let body = token.trim_start_matches("--");
            if body.is_empty() {
                return Err("empty flag is not supported".to_string());
            }

            if let Some((key, value)) = body.split_once('=') {
                parsed.insert_value(key, value)?;
                index += 1;
                continue;
            }

            if index + 1 < args.len() && !args[index + 1].starts_with("--") {
                parsed.insert_value(body, &args[index + 1])?;
                index += 2;
            } else {
                parsed.switches.insert(body.to_string());
                index += 1;
            }
        }
        Ok(parsed)
    }

    fn insert_value(&mut self, key: &str, value: &str) -> Result<(), String> {
        if key.trim().is_empty() {
            return Err("empty flag key is not supported".to_string());
        }
        self.values.insert(key.to_string(), value.to_string());
        Ok(())
    }

    fn required(&self, key: &str) -> Result<String, String> {
        self.optional(key)
            .filter(|value| !value.trim().is_empty())
            .ok_or_else(|| format!("missing required flag --{key}"))
    }

    fn required_i32(&self, key: &str) -> Result<i32, String> {
        self.required(key)?
            .parse::<i32>()
            .map_err(|err| format!("invalid --{key}: {err}"))
    }

    fn optional(&self, key: &str) -> Option<String> {
        self.values.get(key).cloned()
    }

    fn enabled(&self, key: &str) -> bool {
        self.switches.contains(key)
            || self
                .values
                .get(key)
                .map(|value| matches!(value.as_str(), "1" | "true" | "yes" | "on"))
                .unwrap_or(false)
    }

    fn optional_i32(&self, key: &str) -> Result<Option<i32>, String> {
        self.optional_parse(key)
    }

    fn optional_i64(&self, key: &str) -> Result<Option<i64>, String> {
        self.optional_parse(key)
    }

    fn optional_u64(&self, key: &str) -> Result<Option<u64>, String> {
        self.optional_parse(key)
    }

    fn optional_usize(&self, key: &str) -> Result<Option<usize>, String> {
        self.optional_parse(key)
    }

    fn optional_parse<T>(&self, key: &str) -> Result<Option<T>, String>
    where
        T: std::str::FromStr,
        T::Err: std::fmt::Display,
    {
        self.values
            .get(key)
            .map(|value| {
                value
                    .parse::<T>()
                    .map_err(|err| format!("invalid --{key}: {err}"))
            })
            .transpose()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use xhub_core::HubConfig;

    #[test]
    fn flag_parser_supports_values_switches_and_equals() {
        let parsed = FlagArgs::parse(&[
            "--request-id=req-1".to_string(),
            "--scope-key".to_string(),
            "project:a".to_string(),
            "--include-queue-items".to_string(),
            "--priority".to_string(),
            "-2".to_string(),
        ])
        .expect("parse flags");

        assert_eq!(parsed.required("request-id").unwrap(), "req-1");
        assert_eq!(parsed.required("scope-key").unwrap(), "project:a");
        assert!(parsed.enabled("include-queue-items"));
        assert_eq!(parsed.optional_i32("priority").unwrap(), Some(-2));
    }

    #[test]
    fn dispatch_runs_enqueue_acquire_release_bridge_flow() {
        let db_path = unique_temp_db_path("xhub_scheduler_bridge");
        let config = test_config(db_path.clone());
        let enqueue = dispatch_json(
            &config,
            &[
                "enqueue".to_string(),
                "--request-id".to_string(),
                "req-bridge-1".to_string(),
                "--scope-key".to_string(),
                "project:bridge".to_string(),
                "--idempotency-key".to_string(),
                "bridge-idem-1".to_string(),
            ],
        )
        .expect("enqueue");
        assert!(enqueue.contains("\"command\":\"enqueue\""));
        assert!(enqueue.contains("\"inserted\":true"));

        let acquire = dispatch_json(
            &config,
            &[
                "acquire-run".to_string(),
                "--run-id".to_string(),
                extract_json_string(enqueue.as_str(), "run_id").expect("run_id"),
                "--lease-owner".to_string(),
                "bridge-worker".to_string(),
                "--lease-duration-ms".to_string(),
                "30000".to_string(),
            ],
        )
        .expect("acquire");
        assert!(acquire.contains("\"leased\":true"));
        assert!(acquire.contains("\"command\":\"acquire-run\""));
        let run_id = extract_json_string(acquire.as_str(), "run_id").expect("run_id");
        let lease_token =
            extract_json_string(acquire.as_str(), "lease_token").expect("lease_token");

        let release = dispatch_json(
            &config,
            &[
                "release".to_string(),
                "--run-id".to_string(),
                run_id,
                "--lease-token".to_string(),
                lease_token,
                "--outcome".to_string(),
                "completed".to_string(),
            ],
        )
        .expect("release");
        assert!(release.contains("\"status\":\"completed\""));

        let status = dispatch_json(&config, &["status".to_string()]).expect("status");
        assert!(status.contains("\"queue_depth\":0"));
        assert!(status.contains("\"in_flight_total\":0"));

        let compare = dispatch_json(
            &config,
            &[
                "compare".to_string(),
                "--node-in-flight-total".to_string(),
                "0".to_string(),
                "--node-queue-depth".to_string(),
                "0".to_string(),
            ],
        )
        .expect("compare");
        assert!(compare.contains("\"command\":\"compare\""));
        assert!(compare.contains("\"match\":true"));

        let reports = dispatch_json(&config, &["reports".to_string()]).expect("reports");
        assert!(reports.contains("\"command\":\"reports\""));
        assert!(reports.contains("\"total\":1"));
        assert!(reports.contains("\"matched\":1"));
        assert!(reports.contains("\"mismatched\":0"));

        let lease_report = dispatch_json(
            &config,
            &[
                "lease-shadow-report".to_string(),
                "--run-id-prefix".to_string(),
                "run_".to_string(),
            ],
        )
        .expect("lease shadow report");
        assert!(lease_report.contains("\"command\":\"lease-shadow-report\""));
        assert!(lease_report.contains("\"completed\":1"));

        let readiness = dispatch_json(
            &config,
            &[
                "cutover-readiness".to_string(),
                "--run-id-prefix".to_string(),
                "run_".to_string(),
                "--min-compare-reports".to_string(),
                "1".to_string(),
                "--min-lease-shadow-runs".to_string(),
                "1".to_string(),
            ],
        )
        .expect("cutover readiness");
        assert!(readiness.contains("\"command\":\"cutover-readiness\""));
        assert!(readiness.contains("\"ready\":true"));

        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn dispatch_runs_claim_bridge_flow() {
        let db_path = unique_temp_db_path("xhub_scheduler_bridge_claim");
        let config = test_config(db_path.clone());
        let claim = dispatch_json(
            &config,
            &[
                "claim".to_string(),
                "--request-id".to_string(),
                "req-claim-bridge-1".to_string(),
                "--scope-key".to_string(),
                "project:claim-bridge".to_string(),
                "--idempotency-key".to_string(),
                "claim-bridge-idem-1".to_string(),
                "--lease-owner".to_string(),
                "claim-bridge-worker".to_string(),
                "--lease-duration-ms".to_string(),
                "30000".to_string(),
            ],
        )
        .expect("claim");
        assert!(claim.contains("\"command\":\"claim\""));
        assert!(claim.contains("\"inserted\":true"));
        assert!(claim.contains("\"leased\":true"));
        assert!(claim.contains("\"lease_token\":\""));

        let release = dispatch_json(
            &config,
            &[
                "release".to_string(),
                "--run-id".to_string(),
                extract_json_string(claim.as_str(), "run_id").expect("run_id"),
                "--lease-token".to_string(),
                extract_json_string(claim.as_str(), "lease_token").expect("lease token"),
                "--outcome".to_string(),
                "completed".to_string(),
            ],
        )
        .expect("release");
        assert!(release.contains("\"status\":\"completed\""));

        let help = dispatch_json(&config, &["help".to_string()]).expect("help");
        assert!(help.contains("\"claim\""));

        let _ = std::fs::remove_file(&db_path);
    }

    fn test_config(db_path: std::path::PathBuf) -> HubConfig {
        let root = std::env::temp_dir().join("xhub_scheduler_bridge_root");
        HubConfig {
            root_dir: root.clone(),
            host: "127.0.0.1".to_string(),
            http_port: 0,
            grpc_port: 0,
            db_path,
            runtime_base_dir: std::path::PathBuf::new(),
            proto_path: root.join("hub_protocol_v1.proto"),
            canonical_proto_path: root.join("hub_protocol_v1.proto"),
            http_access_key: None,
            http_access_key_source: String::new(),
            http_access_key_required: false,
        }
    }

    fn unique_temp_db_path(prefix: &str) -> std::path::PathBuf {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        std::env::temp_dir().join(format!("{prefix}_{}_{}.sqlite3", std::process::id(), now))
    }

    fn extract_json_string(body: &str, key: &str) -> Option<String> {
        let needle = format!("\"{key}\":\"");
        let start = body.find(&needle)? + needle.len();
        let rest = &body[start..];
        let end = rest.find('"')?;
        Some(rest[..end].to_string())
    }
}
