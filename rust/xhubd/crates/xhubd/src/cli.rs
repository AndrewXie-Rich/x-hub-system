use std::env;

use xhub_contract::{expected_package, summarize_proto, ProtoSummary};
use xhub_core::{json_escape, now_ms, resolve_runtime_root, HubConfig, DAEMON_NAME};
use xhub_db::{apply_baseline_migrations, baseline_migrations, recommended_sqlite_pragmas};
use xhub_memory::RetrievalPlan;
use xhub_policy::default_fail_closed_policy;
use xhub_scheduler::{EnqueueRunRequest, ReleaseOutcome, SchedulerStore};
use xhub_skills::SkillBoundary;

use std::path::Path;
use std::process::Command;

use crate::server::serve_http;
use crate::{
    evidence_bridge, grpc_runtime, memory_bridge, model_bridge, network_bridge, provider_bridge,
    scheduler_bridge, skills_bridge, xt_contract,
};

pub(crate) async fn run() -> Result<(), String> {
    let root = resolve_runtime_root(env!("CARGO_MANIFEST_DIR"));
    let config = HubConfig::from_env(root);
    let args: Vec<String> = env::args().collect();
    let cmd = args.get(1).map(|s| s.as_str()).unwrap_or("doctor");

    match cmd {
        "doctor" => {
            doctor(&config);
            Ok(())
        }
        "migrate" => migrate(&config),
        "scheduler" => scheduler_bridge::run(&config, &args[2..]),
        "network" => network_bridge::run(&config, &args[2..]),
        "provider" => provider_bridge::run(&config, &args[2..]),
        "model" => model_bridge::run(&config, &args[2..]),
        "local-ml" | "local-ml-execution" => Err(
            "local-ml is served over HTTP at /local-ml/execute and /local-ml/readiness".to_string(),
        ),
        "memory" => memory_bridge::run(&config, &args[2..]),
        "evidence" => evidence_bridge::run(&config, &args[2..]),
        "skills" => skills_bridge::run(&config, &args[2..]),
        "xt" => xt_contract::run(&config, &args[2..]),
        "scheduler-smoke" => scheduler_smoke(&config),
        "serve" => {
            if args.iter().any(|arg| arg == "--grpc" || arg == "grpc") {
                grpc_runtime::serve_grpc(config)
                    .await
                    .map_err(|err| err.to_string())
            } else {
                serve_http(config)
            }
        }
        "serve-grpc" => grpc_runtime::serve_grpc(config)
            .await
            .map_err(|err| err.to_string()),
        "version" => {
            println!("{} {}", DAEMON_NAME, env!("CARGO_PKG_VERSION"));
            Ok(())
        }
        "plan" => {
            println!(
                "{}",
                config
                    .root_dir
                    .join("docs")
                    .join("RUST_HUB_EXECUTION_PLAN.md")
                    .display()
            );
            Ok(())
        }
        "-h" | "--help" | "help" => {
            print_help();
            Ok(())
        }
        other => Err(format!("unknown command: {other}. Try `xhubd help`.")),
    }
}

pub(crate) fn print_help() {
    println!("xhubd commands:");
    println!("  doctor   Check Rust Hub scaffold, toolchain, proto, and defaults");
    println!("  migrate  Apply Rust Hub baseline SQLite migrations");
    println!("  scheduler <enqueue|claim|acquire|heartbeat|release|cancel|status>");
    println!("           JSON bridge commands for Node/shadow integration");
    println!("  network <remote-entry-candidates>");
    println!("           JSON remote-entry candidates for Swift Hub shell setup");
    println!(
        "  model <inventory|capabilities|repair-plan|repair-apply|repair-jobs|repair-executor|route|compare|reports|readiness|diagnostics>"
    );
    println!("           JSON remote/local model inventory and route bridge commands");
    println!("  local-ml HTTP: /local-ml/execute, /local-ml/readiness");
    println!("           Rust-governed local ML execution bridge, opt-in only");
    println!(
        "  memory <retrieve|search|write|object-create|object-list|object-get|object-history|object-archive|object-delete|object-pin|object-unpin|candidate-create|candidate-list|candidate-approve|candidate-reject|object-index-rebuild|policy-evaluate|project-canonical-sync|gateway-prepare|readiness>"
    );
    println!(
        "           JSON memory retrieval, object store, project canonical sync, policy, and readiness commands"
    );
    println!("  evidence <write|list>");
    println!("           JSON unified evidence ledger commands");
    println!("  skills <catalog|readiness|policy-readiness|pin|grant|unpin|revoke-grant|policy|policy-events|policy-events-prune|audit|audit-prune|preflight>");
    println!("           JSON skill catalog, policy, and preflight audit commands without code execution");
    println!("  xt <contract>");
    println!("           JSON Hub capability contract for X-Terminal integrations");
    println!("  provider <route>");
    println!("           JSON provider routing shadow commands");
    println!("  scheduler-smoke");
    println!("           Run enqueue/acquire/release against the Rust scheduler DB");
    println!("  serve    Start shadow HTTP daemon");
    println!("  serve --grpc | serve-grpc");
    println!("           Start shadow gRPC daemon with HubRuntime.GetSchedulerStatus");
    println!("  version  Print daemon version");
    println!("  plan     Print execution plan path");
}

pub(crate) fn migrate(config: &HubConfig) -> Result<(), String> {
    let reports = apply_baseline_migrations(&config.db_path)
        .map_err(|err| format!("migrate failed: {err}"))?;
    println!("xhubd migrate");
    println!("db_path={}", config.db_path.display());
    for report in reports {
        println!(
            "migration={} file={} status={}",
            report.migration_id,
            report.file_name,
            if report.applied {
                "applied"
            } else {
                "already_applied"
            }
        );
    }
    Ok(())
}

pub(crate) fn scheduler_smoke(config: &HubConfig) -> Result<(), String> {
    apply_baseline_migrations(&config.db_path)
        .map_err(|err| format!("scheduler smoke migration failed: {err}"))?;
    let scheduler = SchedulerStore::new(
        config.db_path.clone(),
        scheduler_bridge::effective_scheduler_config(config),
    );
    let stamp = now_ms();
    let request_id = format!("scheduler-smoke-{stamp}");
    let enqueue = scheduler
        .enqueue(EnqueueRunRequest {
            run_id: None,
            request_id: request_id.clone(),
            scope_key: "project:scheduler-smoke".to_string(),
            project_id: Some("scheduler-smoke".to_string()),
            device_id: None,
            task_type: "paid_ai_smoke".to_string(),
            priority: 1,
            idempotency_key: request_id,
            not_before_ms: None,
            payload_json: Some("{\"source\":\"xhubd scheduler-smoke\"}".to_string()),
        })
        .map_err(|err| format!("scheduler smoke enqueue failed: {err}"))?;
    let leased = scheduler
        .acquire_next("xhubd-scheduler-smoke", 30_000)
        .map_err(|err| format!("scheduler smoke acquire failed: {err}"))?
        .ok_or_else(|| "scheduler smoke acquire returned no run".to_string())?;
    let release = scheduler
        .release(
            leased.run_id.as_str(),
            leased.lease_token.as_str(),
            ReleaseOutcome::Completed,
        )
        .map_err(|err| format!("scheduler smoke release failed: {err}"))?;
    let view = scheduler
        .status_view(true, 8)
        .map_err(|err| format!("scheduler smoke status failed: {err}"))?;

    println!("xhubd scheduler-smoke");
    println!("db_path={}", config.db_path.display());
    println!(
        "enqueue=ok inserted={} run_id={} request_id={}",
        enqueue.inserted, enqueue.run.run_id, enqueue.run.request_id
    );
    println!(
        "lease=ok owner={} run_id={} attempt={} queued_ms={}",
        leased.lease_owner, leased.run_id, leased.attempt, leased.queued_ms
    );
    println!(
        "release=ok run_id={} status={}",
        release.run_id, release.status
    );
    println!(
        "status=ok in_flight_total={} queue_depth={} oldest_queued_ms={} queue_items={}",
        view.in_flight_total,
        view.queue_depth,
        view.oldest_queued_ms,
        view.queue_items.len()
    );
    Ok(())
}

pub(crate) fn doctor(config: &HubConfig) {
    println!("xhubd doctor");
    println!("target_root={}", config.root_dir.display());
    println!("http_addr={}", config.http_addr());
    println!("grpc_addr={}:{}", config.host, config.grpc_port);
    println!("db_path={}", config.db_path.display());
    println!(
        "http_access_key_configured={} required={} source={}",
        config.http_access_key.is_some(),
        config.http_access_key_required,
        if config.http_access_key_source.is_empty() {
            "none"
        } else {
            config.http_access_key_source.as_str()
        }
    );
    println!(
        "runtime_base_dir={}",
        display_optional_path(&config.runtime_base_dir)
    );
    println!("proto_path={}", config.proto_path.display());
    println!(
        "canonical_proto_path={}",
        config.canonical_proto_path.display()
    );

    print_tool_status("rustc");
    print_tool_status("cargo");

    print_proto_status("mirrored_proto", &config.proto_path);
    print_proto_status("canonical_proto", &config.canonical_proto_path);

    let migrations = baseline_migrations();
    println!("migration_count={}", migrations.len());
    for migration in migrations {
        println!(
            "migration={} file={} desc={}",
            migration.id, migration.file_name, migration.description
        );
    }

    println!("sqlite_pragmas={}", recommended_sqlite_pragmas().join("; "));

    let policy = default_fail_closed_policy();
    println!(
        "policy_default_decision={:?} reason={}",
        policy.decision, policy.reason_code
    );

    let retrieval = RetrievalPlan::project_default();
    println!(
        "memory_default_mode={} dialogue={} project_capsule={} personal_capsule={}",
        retrieval.mode.as_str(),
        retrieval.include_dialogue_window,
        retrieval.include_project_capsule,
        retrieval.include_personal_capsule
    );

    let skill_boundary = SkillBoundary::default();
    println!(
        "skills_authority={:?} hub_executes_third_party_code={}",
        skill_boundary.authority, skill_boundary.hub_executes_third_party_code
    );
}

pub(crate) fn proto_summary_json(config: &HubConfig) -> String {
    match summarize_proto(&config.proto_path) {
        Ok(summary) => proto_summary_to_json(&summary, true),
        Err(err) => format!(
            "{{\"ok\":false,\"error\":\"{}\",\"path\":\"{}\"}}\n",
            json_escape(&err.to_string()),
            json_escape(&config.proto_path.display().to_string())
        ),
    }
}

pub(crate) fn proto_summary_to_json(summary: &ProtoSummary, ok: bool) -> String {
    format!(
        "{{\"ok\":{},\"path\":\"{}\",\"bytes\":{},\"package\":\"{}\",\"expected_package\":\"{}\",\"service_count\":{},\"rpc_count\":{},\"message_count\":{},\"enum_count\":{}}}\n",
        ok,
        json_escape(&summary.path.display().to_string()),
        summary.bytes,
        json_escape(&summary.package_name),
        expected_package(),
        summary.service_count,
        summary.rpc_count,
        summary.message_count,
        summary.enum_count
    )
}

pub(crate) fn print_tool_status(tool: &str) {
    match Command::new(tool).arg("--version").output() {
        Ok(output) if output.status.success() => {
            let stdout = String::from_utf8_lossy(&output.stdout);
            println!("tool_{}=ok {}", tool, stdout.trim());
        }
        Ok(output) => {
            println!("tool_{}=failed status={}", tool, output.status);
        }
        Err(err) => {
            println!("tool_{}=missing error={}", tool, err);
        }
    }
}

pub(crate) fn print_proto_status(label: &str, path: &Path) {
    match summarize_proto(path) {
        Ok(summary) => {
            println!(
                "{}=ok package={} services={} rpcs={} messages={} enums={} bytes={}",
                label,
                summary.package_name,
                summary.service_count,
                summary.rpc_count,
                summary.message_count,
                summary.enum_count,
                summary.bytes
            );
        }
        Err(err) => {
            println!("{}=missing path={} error={}", label, path.display(), err);
        }
    }
}

pub(crate) fn display_optional_path(path: &Path) -> String {
    let text = path.display().to_string();
    if text.is_empty() {
        "(none)".to_string()
    } else {
        text
    }
}
