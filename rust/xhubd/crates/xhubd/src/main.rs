#![recursion_limit = "512"]

use std::collections::{BTreeMap, VecDeque};
use std::env;
use std::io::{Read, Write};
use std::net::{SocketAddr, TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::process::{self, Command};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use serde_json::{json, Value};
use xhub_contract::{expected_package, summarize_proto, ProtoSummary};
use xhub_core::{
    json_escape, now_ms, path_exists, resolve_runtime_root, HubConfig, DAEMON_NAME,
    SCHEMA_HEALTH_V1,
};
use xhub_db::{apply_baseline_migrations, baseline_migrations, recommended_sqlite_pragmas};
use xhub_memory::{MemoryIndexSnapshot, MemoryMode, MemoryRetrievalRequest, RetrievalPlan};
use xhub_policy::default_fail_closed_policy;
use xhub_scheduler::{
    EnqueueRunRequest, ReleaseOutcome, SchedulerConfig, SchedulerSnapshot, SchedulerStore,
};
use xhub_skills::{
    scan_skill_catalog, SkillBoundary, SkillCatalog, SKILL_CATALOG_SCHEMA,
    SKILL_POLICY_EVENTS_PRUNE_SCHEMA, SKILL_POLICY_EVENTS_SCHEMA,
    SKILL_POLICY_STORE_READINESS_SCHEMA, SKILL_PREFLIGHT_AUDIT_SCHEMA,
    SKILL_PREFLIGHT_AUDIT_SUMMARY_SCHEMA, SKILL_PREFLIGHT_SCHEMA, SKILL_READINESS_SCHEMA,
};

mod evidence_bridge;
mod grpc_runtime;
mod local_ml_bridge;
mod memory_bridge;
mod memory_role_projection;
mod model_bridge;
mod network_bridge;
mod provider_bridge;
mod scheduler_bridge;
mod skills_bridge;
mod xt_compat;
mod xt_contract;
mod xt_file_ipc;

#[tokio::main]
async fn main() {
    if let Err(err) = run().await {
        eprintln!("xhubd error: {err}");
        process::exit(1);
    }
}

async fn run() -> Result<(), String> {
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

fn print_help() {
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
        "  memory <retrieve|search|write|object-create|object-list|object-get|object-history|object-index-rebuild|policy-evaluate|project-canonical-sync|gateway-prepare|readiness>"
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

fn migrate(config: &HubConfig) -> Result<(), String> {
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

fn scheduler_smoke(config: &HubConfig) -> Result<(), String> {
    apply_baseline_migrations(&config.db_path)
        .map_err(|err| format!("scheduler smoke migration failed: {err}"))?;
    let scheduler = SchedulerStore::new(config.db_path.clone(), SchedulerConfig::default());
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

fn doctor(config: &HubConfig) {
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

struct HubState {
    config: HubConfig,
    http_in_flight: AtomicUsize,
    http_max_in_flight: usize,
    http_slow_ms: u128,
    http_read_timeout_ms: u64,
    http_write_timeout_ms: u64,
    http_metrics_recent_limit: usize,
    http_metrics: Mutex<HttpMetrics>,
    readiness_cache: Mutex<ReadinessCache>,
    readiness_cache_ttl_ms: u128,
    memory_snapshot_cache: Mutex<MemorySnapshotCache>,
    memory_snapshot_cache_ttl_ms: u128,
    skills_catalog_cache: Mutex<SkillsCatalogCache>,
    skills_catalog_cache_ttl_ms: u128,
}

#[derive(Debug, Clone)]
struct HttpMetrics {
    started_at_ms: u128,
    total_requests: u64,
    slow_requests: u64,
    max_elapsed_ms: u128,
    routes: BTreeMap<String, HttpRouteMetrics>,
    recent_samples: VecDeque<HttpMetricSample>,
    recent_dropped_samples: u64,
}

impl Default for HttpMetrics {
    fn default() -> Self {
        Self {
            started_at_ms: now_ms(),
            total_requests: 0,
            slow_requests: 0,
            max_elapsed_ms: 0,
            routes: BTreeMap::new(),
            recent_samples: VecDeque::new(),
            recent_dropped_samples: 0,
        }
    }
}

#[derive(Debug, Clone)]
struct HttpMetricSample {
    completed_at_ms: u128,
    route: String,
    status: String,
    elapsed_ms: u128,
    slow: bool,
}

#[derive(Debug, Clone, Default)]
struct HttpRouteMetrics {
    count: u64,
    slow_count: u64,
    total_elapsed_ms: u128,
    max_elapsed_ms: u128,
    last_elapsed_ms: u128,
    last_status: String,
}

#[derive(Debug, Clone, Default)]
struct ReadinessCache {
    body: String,
    expires_at_ms: u128,
}

#[derive(Debug, Clone, Default)]
struct MemorySnapshotCache {
    memory_dir: PathBuf,
    snapshot: Option<MemoryIndexSnapshot>,
    expires_at_ms: u128,
}

#[derive(Debug, Clone, Default)]
struct SkillsCatalogCache {
    skills_dir: PathBuf,
    catalog: Option<SkillCatalog>,
    expires_at_ms: u128,
}

struct HttpInflightGuard<'a> {
    state: &'a HubState,
}

impl Drop for HttpInflightGuard<'_> {
    fn drop(&mut self) {
        self.state.http_in_flight.fetch_sub(1, Ordering::AcqRel);
    }
}

impl HubState {
    fn new(config: HubConfig) -> Self {
        Self {
            config,
            http_in_flight: AtomicUsize::new(0),
            http_max_in_flight: env_usize_in_range("XHUB_RUST_HTTP_MAX_IN_FLIGHT", 128, 1, 10_000),
            http_slow_ms: env_u128_in_range("XHUB_RUST_HTTP_SLOW_MS", 2_000, 1, 300_000),
            http_read_timeout_ms: env_u128_in_range(
                "XHUB_RUST_HTTP_READ_TIMEOUT_MS",
                5_000,
                0,
                300_000,
            ) as u64,
            http_write_timeout_ms: env_u128_in_range(
                "XHUB_RUST_HTTP_WRITE_TIMEOUT_MS",
                5_000,
                0,
                300_000,
            ) as u64,
            http_metrics_recent_limit: env_usize_in_range(
                "XHUB_RUST_HTTP_METRICS_RECENT_LIMIT",
                256,
                0,
                10_000,
            ),
            http_metrics: Mutex::new(HttpMetrics::default()),
            readiness_cache: Mutex::new(ReadinessCache::default()),
            readiness_cache_ttl_ms: env_u128_in_range(
                "XHUB_RUST_READY_CACHE_TTL_MS",
                5_000,
                0,
                30_000,
            ),
            memory_snapshot_cache: Mutex::new(MemorySnapshotCache::default()),
            memory_snapshot_cache_ttl_ms: env_u128_in_range(
                "XHUB_RUST_MEMORY_SNAPSHOT_CACHE_TTL_MS",
                500,
                0,
                10_000,
            ),
            skills_catalog_cache: Mutex::new(SkillsCatalogCache::default()),
            skills_catalog_cache_ttl_ms: env_u128_in_range(
                "XHUB_RUST_SKILLS_CATALOG_CACHE_TTL_MS",
                500,
                0,
                10_000,
            ),
        }
    }
}

fn serve_http(config: HubConfig) -> Result<(), String> {
    enforce_http_bind_policy(&config)?;
    apply_baseline_migrations(&config.db_path)
        .map_err(|err| format!("serve migration preflight failed: {err}"))?;
    let addr = config.http_addr();
    let listener = TcpListener::bind(&addr).map_err(|err| format!("bind {addr} failed: {err}"))?;
    println!("[xhubd] shadow HTTP listening on http://{addr}");
    println!("[xhubd] health: http://{addr}/health");
    println!("[xhubd] mode=shadow_http grpc=not_started");

    let shared = Arc::new(HubState::new(config));
    start_xt_classic_status_heartbeat_if_enabled(&shared.config);
    for stream in listener.incoming() {
        match stream {
            Ok(stream) => {
                let state = Arc::clone(&shared);
                thread::spawn(move || {
                    if let Err(err) = handle_client(stream, &state) {
                        eprintln!("xhubd request error: {err}");
                    }
                });
            }
            Err(err) => eprintln!("xhubd accept error: {err}"),
        }
    }
    Ok(())
}

fn start_xt_classic_status_heartbeat_if_enabled(config: &HubConfig) {
    if !env_bool("XHUB_RUST_XT_CLASSIC_STATUS_WRITER_HEARTBEAT", false) {
        return;
    }
    let interval_ms = env_u128_in_range(
        "XHUB_RUST_XT_CLASSIC_STATUS_WRITER_HEARTBEAT_MS",
        1_000,
        100,
        60_000,
    ) as u64;
    let config = config.clone();
    let mut trusted_fast_refresh = env_bool("XHUB_RUST_XT_CLASSIC_PRODUCTION_CUTOVER", false)
        && env_bool("XHUB_RUST_XT_CLASSIC_STATUS_WRITER_APPLY", false)
        && env_bool("XHUB_RUST_XT_CLASSIC_FILE_IPC_READY", false)
        && env_bool("XHUB_RUST_XT_CLASSIC_ROLLBACK_CONTRACT", false);
    thread::spawn(move || loop {
        let ok = if trusted_fast_refresh {
            xt_compat::classic_hub_status_write_trusted_heartbeat_once(&config)
        } else {
            xt_compat::classic_hub_status_write_heartbeat_once(&config)
        };
        trusted_fast_refresh = ok;
        thread::sleep(Duration::from_millis(interval_ms));
    });
}

fn handle_client(mut stream: TcpStream, state: &HubState) -> Result<(), String> {
    apply_http_io_timeouts(&stream, state)?;
    let config = &state.config;
    let peer_addr = stream.peer_addr().ok();
    let request = read_http_request(&mut stream)?;
    let path = request.path.as_str();

    let (route_path, query) = split_path_query(path);
    let request_started_ms = now_ms();
    let _inflight_guard = match acquire_http_inflight_slot(state, route_path) {
        Ok(guard) => guard,
        Err(response) => {
            let elapsed_ms = now_ms().saturating_sub(request_started_ms);
            record_http_route_metrics(state, route_path, "503 Service Unavailable", elapsed_ms);
            return write_http_response(&mut stream, "503 Service Unavailable", response.as_str());
        }
    };
    let (status, body) = if let Some(failure) =
        http_access_key_failure(&request, config, peer_addr, route_path)
    {
        failure
    } else {
        match route_path {
            "/" => ("200 OK", root_body()),
            "/health" => ("200 OK", health_json(config)),
            "/product/kernel" | "/kernel/status" => ("200 OK", product_kernel_json(state)),
            "/ready" | "/readiness" | "/runtime/readiness" => {
                ("200 OK", readiness_json_cached(state))
            }
            "/runtime/scheduler_status" => ("200 OK", scheduler_status_json()),
            "/runtime/http-metrics" | "/http/metrics" => http_metrics_json(state),
            "/network/remote-entry-candidates"
            | "/network/remote-entry"
            | "/remote/entry-candidates" => {
                network_bridge::remote_entry_candidates_http_json(config, query)
            }
            "/xt/hub-contract" | "/xt/contract" | "/contract/xt" => {
                xt_contract::contract_http_json(config)
            }
            "/xt/classic-hub-compat" | "/compat/xt-classic-hub" | "/compat/classic-hub" => {
                ("200 OK", xt_compat::classic_hub_compat_json(config))
            }
            "/xt/classic-hub-compat/write-status"
            | "/compat/xt-classic-hub/write-status"
            | "/compat/classic-hub/write-status" => {
                xt_compat::classic_hub_status_write_http_json(config, request.method.as_str())
            }
            "/xt/file-ipc/live-status"
            | "/xt/file-ipc-live-status"
            | "/compat/xt-file-ipc/live-status" => {
                xt_file_ipc::live_status_http_json(config, request.method.as_str())
            }
            "/xt/file-ipc/runtime-authority-sync"
            | "/xt/file-ipc-runtime-authority-sync"
            | "/compat/xt-file-ipc/runtime-authority-sync" => {
                xt_file_ipc::runtime_authority_sync_http_json(
                    config,
                    request.method.as_str(),
                    request.body.as_str(),
                )
            }
            "/xt/file-ipc-shadow"
            | "/xt/file-ipc-shadow/respond-once"
            | "/xt/file-ipc-shadow/drain"
            | "/xt/file-ipc-shadow/cycle"
            | "/xt/file-ipc-shadow/supervise"
            | "/xt/file-ipc-shadow/watcher-smoke"
            | "/xt/file-ipc-shadow/watcher-rollback-smoke"
            | "/xt/file-ipc-shadow/watcher-readiness"
            | "/xt/file-ipc-shadow/watcher-start-plan"
            | "/xt/file-ipc-shadow/watcher-run-once"
            | "/xt/file-ipc-shadow/watcher-session"
            | "/xt/file-ipc-shadow/runtime-execution-plan"
            | "/xt/file-ipc-shadow/runtime-adapter-candidate"
            | "/xt/file-ipc-shadow/watcher-background-start"
            | "/xt/file-ipc-shadow/watcher-background-stop"
            | "/xt/file-ipc-shadow/watcher-background-status"
            | "/compat/xt-file-ipc-shadow"
            | "/compat/xt-file-ipc-shadow/drain"
            | "/compat/xt-file-ipc-shadow/cycle"
            | "/compat/xt-file-ipc-shadow/supervise"
            | "/compat/xt-file-ipc-shadow/watcher-smoke"
            | "/compat/xt-file-ipc-shadow/watcher-rollback-smoke"
            | "/compat/xt-file-ipc-shadow/watcher-readiness"
            | "/compat/xt-file-ipc-shadow/watcher-start-plan"
            | "/compat/xt-file-ipc-shadow/watcher-run-once"
            | "/compat/xt-file-ipc-shadow/watcher-session"
            | "/compat/xt-file-ipc-shadow/runtime-execution-plan"
            | "/compat/xt-file-ipc-shadow/runtime-adapter-candidate"
            | "/compat/xt-file-ipc-shadow/watcher-background-start"
            | "/compat/xt-file-ipc-shadow/watcher-background-stop"
            | "/compat/xt-file-ipc-shadow/watcher-background-status" => {
                xt_file_ipc::shadow_http_json(
                    config,
                    route_path,
                    request.method.as_str(),
                    request.body.as_str(),
                )
            }
            "/scheduler/status" => scheduler_status_http_json(config, query),
            "/scheduler/cutover-readiness" | "/scheduler/readiness" => {
                scheduler_readiness_http_json(config, query)
            }
            "/scheduler/enqueue" => {
                scheduler_command_http_json(config, "enqueue", request.body.as_str())
            }
            "/scheduler/claim" => {
                scheduler_command_http_json(config, "claim", request.body.as_str())
            }
            "/scheduler/acquire-run" => {
                scheduler_command_http_json(config, "acquire-run", request.body.as_str())
            }
            "/scheduler/release" => {
                scheduler_command_http_json(config, "release", request.body.as_str())
            }
            "/scheduler/cancel" => {
                scheduler_command_http_json(config, "cancel", request.body.as_str())
            }
            "/contract/proto_summary" => ("200 OK", proto_summary_json(config)),
            "/provider/route" => provider_route_http_json(config, query),
            "/provider/pools" | "/provider/key-pools" => provider_pools_http_json(config, query),
            "/provider/runtime-snapshot" | "/provider/snapshot" => {
                provider_runtime_snapshot_http_json(config, query)
            }
            "/provider/import" | "/provider/keys/import" => {
                provider_import_http_json(config, query, request.body.as_str())
            }
            "/provider/openai-quota-refresh/plan" | "/provider/quota/openai/plan" => {
                provider_openai_quota_plan_http_json(config, query, request.body.as_str())
            }
            "/provider/openai-quota-refresh/apply" | "/provider/quota/openai/apply" => {
                provider_openai_quota_apply_http_json(config, query, request.body.as_str())
            }
            "/provider/openai-quota-refresh/failure" | "/provider/quota/openai/failure" => {
                provider_openai_quota_failure_http_json(config, query, request.body.as_str())
            }
            "/provider/oauth-refresh/apply" | "/provider/oauth/apply" => {
                provider_oauth_refresh_apply_http_json(config, query, request.body.as_str())
            }
            "/provider/oauth-refresh/failure" | "/provider/oauth/failure" => {
                provider_oauth_refresh_failure_http_json(config, query, request.body.as_str())
            }
            "/provider/oauth-refresh/codex/plan"
            | "/provider/oauth/codex-refresh/plan"
            | "/provider/codex-oauth-refresh/plan" => {
                provider_codex_oauth_plan_http_json(config, query, request.body.as_str())
            }
            "/provider/oauth-refresh/codex" | "/provider/oauth/codex-refresh" => {
                provider_codex_oauth_refresh_http_json(config, query, request.body.as_str())
            }
            "/provider/compare" => provider_compare_http_json(config, query, request.body.as_str()),
            "/provider/reports" => provider_reports_http_json(config, query),
            "/provider/readiness" => provider_readiness_http_json(config, query),
            "/memory/search" => memory_search_http_json(state, query),
            "/memory/retrieve" => memory_retrieve_http_json(state, query, request.body.as_str()),
            "/memory/project-role-transcript"
            | "/memory/project-role-transcript-projection"
            | "/memory/role-transcript" => memory_role_transcript_http_json(config, query),
            "/memory/write" | "/memory/append" => {
                memory_write_http_json(config, request.body.as_str())
            }
            "/memory/readiness" | "/memory/status" => memory_readiness_http_json(state, query),
            "/memory/object-index/rebuild" | "/memory/reindex" => {
                memory_bridge::object_index_rebuild_http_json(config, request.method.as_str())
            }
            "/memory/objects" => memory_bridge::object_collection_http_json(
                config,
                request.method.as_str(),
                query,
                request.body.as_str(),
            ),
            path if path.starts_with("/memory/objects/") => {
                memory_bridge::object_item_http_json(config, path, request.method.as_str(), query)
            }
            "/memory/policy/evaluate" => {
                memory_bridge::policy_evaluate_http_json(request.body.as_str())
            }
            "/memory/project-canonical-sync" | "/memory/project-canonical" => {
                memory_bridge::project_canonical_sync_http_json(
                    config,
                    request.method.as_str(),
                    query,
                    request.body.as_str(),
                )
            }
            "/memory/gateway/prepare" | "/memory/context" => {
                memory_bridge::memory_gateway_prepare_http_json(
                    config,
                    request.method.as_str(),
                    request.body.as_str(),
                )
            }
            "/evidence/ledger" | "/evidence/list" => evidence_ledger_http_json(config, query),
            "/evidence/write" => evidence_write_http_json(config, request.body.as_str()),
            "/skills/catalog" => skills_catalog_http_json(state, query),
            "/skills/readiness" | "/skills/status" => skills_readiness_http_json(state, query),
            "/skills/policy-readiness" | "/skills/policy-maintenance" => {
                skills_policy_readiness_http_json(config, query, request.body.as_str())
            }
            "/skills/pin" => skills_pin_http_json(config, query, request.body.as_str()),
            "/skills/grant" => skills_grant_http_json(config, query, request.body.as_str()),
            "/skills/unpin" | "/skills/revoke-pin" => {
                skills_unpin_http_json(config, query, request.body.as_str())
            }
            "/skills/revoke-grant" => {
                skills_revoke_grant_http_json(config, query, request.body.as_str())
            }
            "/skills/policy" => skills_policy_http_json(config, query, request.body.as_str()),
            "/skills/policy-events" | "/skills/policy-audit" => {
                skills_policy_events_http_json(config, query, request.body.as_str())
            }
            "/skills/policy-events-prune" | "/skills/policy-audit-prune" => {
                skills_policy_events_prune_http_json(config, query, request.body.as_str())
            }
            "/skills/audit" => skills_audit_http_json(config, query, request.body.as_str()),
            "/skills/audit-prune" => {
                skills_audit_prune_http_json(config, query, request.body.as_str())
            }
            "/skills/preflight" => skills_preflight_http_json(config, query, request.body.as_str()),
            "/skills/execute" | "/skills/run" => {
                skills_execute_http_json(config, query, request.body.as_str())
            }
            "/model/inventory" => model_inventory_http_json(config, query),
            "/model/capabilities" | "/model/local-capabilities" => {
                model_capabilities_http_json(config, query)
            }
            "/model/repair-plan" | "/model/local-repair-plan" => {
                model_repair_plan_http_json(config, query)
            }
            "/model/repair-apply" | "/model/local-repair-apply" => {
                model_repair_apply_http_json(config, query, request.body.as_str())
            }
            "/model/repair-jobs" | "/model/local-repair-jobs" => {
                model_repair_jobs_http_json(config, query)
            }
            "/model/route" => model_route_http_json(config, query, request.body.as_str()),
            "/model/compare" => model_compare_http_json(config, query, request.body.as_str()),
            "/model/reports" => model_reports_http_json(config, query),
            "/model/diagnostics" | "/model/route-diagnostics" => {
                model_diagnostics_http_json(config, query)
            }
            "/model/readiness" | "/model/cutover-readiness" => {
                model_readiness_http_json(config, query)
            }
            "/local-ml/readiness"
            | "/local-ml/status"
            | "/runtime/local-ml/readiness"
            | "/runtime/ml-execution/readiness" => {
                local_ml_bridge::readiness_http_json(config, query)
            }
            "/local-ml/execute"
            | "/local-ml/run-local-task"
            | "/runtime/local-ml/execute"
            | "/runtime/ml-execution/execute" => local_ml_bridge::execute_http_json(
                config,
                request.method.as_str(),
                request.body.as_str(),
            ),
            _ => (
                "404 Not Found",
                "{\"ok\":false,\"error\":\"not_found\"}\n".to_string(),
            ),
        }
    };

    let content_type = if body.trim_start().starts_with("<!doctype html") {
        "text/html; charset=utf-8"
    } else {
        "application/json; charset=utf-8"
    };
    let elapsed_ms = now_ms().saturating_sub(request_started_ms);
    record_http_route_metrics(state, route_path, status, elapsed_ms);
    write_http_response_with_content_type(&mut stream, status, body.as_str(), content_type)?;
    Ok(())
}

fn apply_http_io_timeouts(stream: &TcpStream, state: &HubState) -> Result<(), String> {
    let read_timeout = duration_from_timeout_ms(state.http_read_timeout_ms);
    let write_timeout = duration_from_timeout_ms(state.http_write_timeout_ms);
    stream
        .set_read_timeout(read_timeout)
        .map_err(|err| format!("set_http_read_timeout:{err}"))?;
    stream
        .set_write_timeout(write_timeout)
        .map_err(|err| format!("set_http_write_timeout:{err}"))?;
    Ok(())
}

fn duration_from_timeout_ms(timeout_ms: u64) -> Option<Duration> {
    if timeout_ms == 0 {
        None
    } else {
        Some(Duration::from_millis(timeout_ms))
    }
}

fn write_http_response(
    stream: &mut TcpStream,
    status: &'static str,
    body: &str,
) -> Result<(), String> {
    write_http_response_with_content_type(stream, status, body, "application/json; charset=utf-8")
}

fn write_http_response_with_content_type(
    stream: &mut TcpStream,
    status: &'static str,
    body: &str,
    content_type: &str,
) -> Result<(), String> {
    let response = format!(
        "HTTP/1.1 {status}\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        body.as_bytes().len(),
        body
    );
    stream
        .write_all(response.as_bytes())
        .map_err(|err| err.to_string())?;
    Ok(())
}

fn acquire_http_inflight_slot<'a>(
    state: &'a HubState,
    route_path: &str,
) -> Result<Option<HttpInflightGuard<'a>>, String> {
    if route_path == "/health" {
        return Ok(None);
    }
    let max = state.http_max_in_flight.max(1);
    let mut current = state.http_in_flight.load(Ordering::Acquire);
    loop {
        if current >= max {
            return Err(format!(
                "{{\"ok\":false,\"error\":\"http_backpressure\",\"message\":\"Rust Hub HTTP in-flight limit reached\",\"in_flight\":{},\"max_in_flight\":{},\"retry_after_ms\":250}}\n",
                current, max
            ));
        }
        match state.http_in_flight.compare_exchange_weak(
            current,
            current + 1,
            Ordering::AcqRel,
            Ordering::Acquire,
        ) {
            Ok(_) => return Ok(Some(HttpInflightGuard { state })),
            Err(next) => current = next,
        }
    }
}

fn record_http_route_metrics(state: &HubState, route_path: &str, status: &str, elapsed_ms: u128) {
    let route = sanitized_route_label(route_path);
    let slow = elapsed_ms >= state.http_slow_ms;
    if slow {
        eprintln!(
            "xhubd slow request route={} status={} elapsed_ms={} slow_ms={}",
            route, status, elapsed_ms, state.http_slow_ms
        );
    }

    let Ok(mut metrics) = state.http_metrics.lock() else {
        return;
    };
    metrics.total_requests = metrics.total_requests.saturating_add(1);
    metrics.max_elapsed_ms = metrics.max_elapsed_ms.max(elapsed_ms);
    if slow {
        metrics.slow_requests = metrics.slow_requests.saturating_add(1);
    }
    let route_metrics = metrics.routes.entry(route.clone()).or_default();
    route_metrics.count = route_metrics.count.saturating_add(1);
    route_metrics.total_elapsed_ms = route_metrics.total_elapsed_ms.saturating_add(elapsed_ms);
    route_metrics.max_elapsed_ms = route_metrics.max_elapsed_ms.max(elapsed_ms);
    route_metrics.last_elapsed_ms = elapsed_ms;
    route_metrics.last_status = status.to_string();
    if slow {
        route_metrics.slow_count = route_metrics.slow_count.saturating_add(1);
    }
    if state.http_metrics_recent_limit > 0 {
        while metrics.recent_samples.len() >= state.http_metrics_recent_limit {
            metrics.recent_samples.pop_front();
            metrics.recent_dropped_samples = metrics.recent_dropped_samples.saturating_add(1);
        }
        metrics.recent_samples.push_back(HttpMetricSample {
            completed_at_ms: now_ms(),
            route,
            status: status.to_string(),
            elapsed_ms,
            slow,
        });
    }
}

fn sanitized_route_label(route_path: &str) -> String {
    let route_without_query = route_path.split(['?', '#']).next().unwrap_or(route_path);
    let cleaned = route_without_query
        .chars()
        .filter(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '/' | '-' | '_' | '.' | ':'))
        .take(120)
        .collect::<String>();
    if cleaned.is_empty() {
        "/unknown".to_string()
    } else {
        cleaned
    }
}

struct HttpRequest {
    method: String,
    path: String,
    body: String,
    headers: Vec<(String, String)>,
}

fn read_http_request(stream: &mut TcpStream) -> Result<HttpRequest, String> {
    const MAX_REQUEST_BYTES: usize = 1024 * 1024;
    let mut bytes = Vec::with_capacity(4096);
    let header_end = loop {
        if let Some(index) = find_bytes(&bytes, b"\r\n\r\n") {
            break index;
        }
        if bytes.len() >= MAX_REQUEST_BYTES {
            return Err("http request too large".to_string());
        }
        let mut chunk = [0_u8; 4096];
        let read = stream.read(&mut chunk).map_err(|err| err.to_string())?;
        if read == 0 {
            if bytes.is_empty() {
                return Err("empty http request".to_string());
            }
            return Err("incomplete http request headers".to_string());
        }
        bytes.extend_from_slice(&chunk[..read]);
    };
    let header_text = String::from_utf8_lossy(&bytes[..header_end]);
    let first_line = header_text.lines().next().unwrap_or("");
    let mut first_parts = first_line.split_whitespace();
    let method = first_parts.next().unwrap_or("GET").to_ascii_uppercase();
    let path = first_parts.next().unwrap_or("/").to_string();
    let headers = header_text
        .lines()
        .skip(1)
        .filter_map(|line| {
            let (name, value) = line.split_once(':')?;
            Some((name.trim().to_ascii_lowercase(), value.trim().to_string()))
        })
        .collect::<Vec<_>>();
    let content_length = header_text
        .lines()
        .find_map(|line| {
            let (name, value) = line.split_once(':')?;
            if name.trim().eq_ignore_ascii_case("content-length") {
                value.trim().parse::<usize>().ok()
            } else {
                None
            }
        })
        .unwrap_or(0);
    if content_length > MAX_REQUEST_BYTES {
        return Err("http request body too large".to_string());
    }
    let body_start = header_end + 4;
    while bytes.len().saturating_sub(body_start) < content_length {
        if bytes.len() >= MAX_REQUEST_BYTES {
            return Err("http request too large".to_string());
        }
        let mut chunk = [0_u8; 4096];
        let read = stream.read(&mut chunk).map_err(|err| err.to_string())?;
        if read == 0 {
            return Err("incomplete http request body".to_string());
        }
        bytes.extend_from_slice(&chunk[..read]);
    }
    let body_end = body_start + content_length;
    let body = String::from_utf8_lossy(&bytes[body_start..body_end]).to_string();
    Ok(HttpRequest {
        method,
        path,
        body,
        headers,
    })
}

fn find_bytes(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    haystack
        .windows(needle.len())
        .position(|window| window == needle)
}

fn split_path_query(path: &str) -> (&str, &str) {
    match path.split_once('?') {
        Some((route_path, query)) => (route_path, query.split('#').next().unwrap_or("")),
        None => (path.split('#').next().unwrap_or(path), ""),
    }
}

fn http_access_key_failure(
    request: &HttpRequest,
    config: &HubConfig,
    peer_addr: Option<SocketAddr>,
    route_path: &str,
) -> Option<(&'static str, String)> {
    http_access_key_failure_with_public_endpoint(
        request,
        config,
        peer_addr,
        route_path,
        cross_network_public_endpoint_enabled(),
    )
}

fn http_access_key_failure_with_public_endpoint(
    request: &HttpRequest,
    config: &HubConfig,
    peer_addr: Option<SocketAddr>,
    route_path: &str,
    public_endpoint_enabled: bool,
) -> Option<(&'static str, String)> {
    if !http_access_key_required_for_request_with_public_endpoint(
        config,
        peer_addr,
        route_path,
        public_endpoint_enabled,
    ) {
        return None;
    }

    let Some(expected) = config
        .http_access_key
        .as_deref()
        .filter(|value| !value.is_empty())
    else {
        return Some((
            "403 Forbidden",
            "{\"ok\":false,\"error\":\"access_key_not_configured\",\"message\":\"cross-network Rust Hub HTTP requires XHUB_RUST_HTTP_ACCESS_KEY_FILE or XHUB_RUST_HTTP_ACCESS_KEY\"}\n".to_string(),
        ));
    };

    match http_access_key_from_request(request) {
        Some(actual) if constant_time_eq(actual.as_bytes(), expected.as_bytes()) => None,
        Some(_) => Some((
            "401 Unauthorized",
            "{\"ok\":false,\"error\":\"invalid_access_key\"}\n".to_string(),
        )),
        None => Some((
            "401 Unauthorized",
            "{\"ok\":false,\"error\":\"missing_access_key\",\"message\":\"send Authorization: Bearer <key> or X-XHub-Access-Key\"}\n".to_string(),
        )),
    }
}

fn http_access_key_required_for_request_with_public_endpoint(
    config: &HubConfig,
    peer_addr: Option<SocketAddr>,
    route_path: &str,
    public_endpoint_enabled: bool,
) -> bool {
    if route_path == "/health" {
        return false;
    }
    if config.http_access_key_required {
        return true;
    }
    if public_endpoint_enabled {
        return true;
    }
    let peer_is_loopback = peer_addr
        .map(|addr| addr.ip().is_loopback())
        .unwrap_or_else(|| is_loopback_host(&config.host));
    !peer_is_loopback
}

fn http_access_key_from_request(request: &HttpRequest) -> Option<String> {
    request
        .header("authorization")
        .and_then(|value| {
            let trimmed = value.trim();
            let mut parts = trimmed.splitn(2, char::is_whitespace);
            let scheme = parts.next().unwrap_or("");
            let token = parts.next().unwrap_or("").trim();
            if scheme.eq_ignore_ascii_case("bearer") && !token.is_empty() {
                Some(token.to_string())
            } else {
                None
            }
        })
        .or_else(|| {
            request
                .header("x-xhub-access-key")
                .or_else(|| request.header("x-hub-access-key"))
                .map(|value| value.trim().to_string())
                .filter(|value| !value.is_empty())
        })
}

fn constant_time_eq(left: &[u8], right: &[u8]) -> bool {
    if left.len() != right.len() {
        return false;
    }
    let mut diff = 0_u8;
    for (a, b) in left.iter().zip(right.iter()) {
        diff |= a ^ b;
    }
    diff == 0
}

impl HttpRequest {
    fn header(&self, name: &str) -> Option<&str> {
        let normalized = name.to_ascii_lowercase();
        self.headers
            .iter()
            .find(|(header_name, _)| header_name == &normalized)
            .map(|(_, value)| value.as_str())
    }
}

fn provider_route_http_json(config: &HubConfig, query: &str) -> (&'static str, String) {
    let model_id = match query_param(query, "model_id")
        .or_else(|| query_param(query, "modelId"))
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
    {
        Some(value) => value,
        None => {
            return (
                "400 Bad Request",
                "{\"ok\":false,\"error\":\"missing_model_id\"}\n".to_string(),
            )
        }
    };
    let provider = query_param(query, "provider").unwrap_or_default();
    let runtime_base_dir = query_param(query, "runtime_base_dir")
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let request_now_ms = match query_param(query, "now_ms").or_else(|| query_param(query, "nowMs"))
    {
        Some(value) if !value.trim().is_empty() => match value.trim().parse::<u128>() {
            Ok(parsed) => Some(parsed),
            Err(_) => {
                return (
                    "400 Bad Request",
                    "{\"ok\":false,\"error\":\"invalid_now_ms\"}\n".to_string(),
                )
            }
        },
        _ => None,
    };

    let body = match provider_bridge::route_json_from_parts(
        config,
        runtime_base_dir,
        model_id,
        provider,
        request_now_ms,
    ) {
        Ok(body) => body,
        Err(err) => {
            return (
                "400 Bad Request",
                format!(
                    "{{\"ok\":false,\"error\":\"provider_route_failed\",\"message\":\"{}\"}}\n",
                    json_escape(&err)
                ),
            )
        }
    };
    match maybe_attach_route_evidence(
        config,
        query,
        &Value::Null,
        "provider_route",
        body,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"provider_route_evidence_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn provider_pools_http_json(config: &HubConfig, query: &str) -> (&'static str, String) {
    let runtime_base_dir = query_param(query, "runtime_base_dir")
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let provider = query_param(query, "provider").unwrap_or_default();
    let model_id = query_param(query, "model_id")
        .or_else(|| query_param(query, "modelId"))
        .unwrap_or_default();
    let include_members =
        match optional_query_bool_alias(query, "include_members", "includeMembers", true) {
            Ok(value) => value,
            Err(body) => return ("400 Bad Request", body),
        };
    let request_now_ms = match optional_query_u128_alias(query, "now_ms", "nowMs") {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };

    match provider_bridge::pools_json_from_parts(
        config,
        runtime_base_dir,
        provider,
        model_id,
        include_members,
        request_now_ms,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"provider_pools_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn provider_runtime_snapshot_http_json(config: &HubConfig, query: &str) -> (&'static str, String) {
    let runtime_base_dir = query_param(query, "runtime_base_dir")
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let provider = query_param(query, "provider").unwrap_or_default();

    match provider_bridge::runtime_snapshot_json_from_parts(config, runtime_base_dir, provider) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"provider_runtime_snapshot_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn provider_import_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    let parsed_body = match parse_optional_json_body(body) {
        Ok(value) => value,
        Err(err) => {
            return (
                "400 Bad Request",
                format!(
                    "{{\"ok\":false,\"error\":\"invalid_json\",\"message\":\"{}\"}}\n",
                    json_escape(&err)
                ),
            )
        }
    };
    let runtime_base_dir =
        body_or_query_string(&parsed_body, query, "runtime_base_dir", "runtimeBaseDir")
            .map(PathBuf::from);
    let auth_dir = body_or_query_string(&parsed_body, query, "auth_dir", "authDir")
        .or_else(|| body_or_query_string(&parsed_body, query, "auth_path", "authPath"))
        .unwrap_or_default();
    let config_path =
        body_or_query_string(&parsed_body, query, "config_path", "configPath").unwrap_or_default();
    let imported_at_ms = body_u64_alias(&parsed_body, "now_ms", "nowMs")
        .or_else(|| query_param(query, "now_ms").and_then(|value| value.parse::<u64>().ok()))
        .or_else(|| query_param(query, "nowMs").and_then(|value| value.parse::<u64>().ok()));

    match provider_bridge::import_json_from_parts(
        config,
        runtime_base_dir,
        auth_dir,
        config_path,
        imported_at_ms,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"provider_import_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn provider_openai_quota_apply_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    match provider_openai_quota_apply_http_body(config, query, body) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"provider_openai_quota_apply_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn provider_openai_quota_plan_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    match provider_openai_quota_plan_http_body(config, query, body) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"provider_openai_quota_plan_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn provider_openai_quota_plan_http_body(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> Result<String, String> {
    let parsed_body = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        serde_json::from_str::<Value>(body)
            .map_err(|err| format!("invalid openai quota plan request json: {err}"))?
    };
    let runtime_base_dir = body_string(&parsed_body, "runtime_base_dir")
        .or_else(|| body_string(&parsed_body, "runtimeBaseDir"))
        .or_else(|| query_param(query, "runtime_base_dir"))
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let now = body_u64_alias(&parsed_body, "now_ms", "nowMs")
        .or_else(|| query_param(query, "now_ms").and_then(|value| value.parse::<u64>().ok()))
        .or_else(|| query_param(query, "nowMs").and_then(|value| value.parse::<u64>().ok()))
        .unwrap_or_else(|| now_ms().min(u64::MAX as u128) as u64);
    let include_skipped = body_bool_alias(&parsed_body, "include_skipped", "includeSkipped")
        .or_else(|| {
            optional_query_bool_alias(query, "include_skipped", "includeSkipped", false).ok()
        })
        .unwrap_or(false);
    let mut in_flight_account_keys = body_string_list(&parsed_body, "in_flight_account_keys");
    in_flight_account_keys.extend(body_string_list(&parsed_body, "inFlightAccountKeys"));
    if let Some(keys) = query_param_list(query, "in_flight_account_keys")
        .or_else(|| query_param_list(query, "inFlightAccountKeys"))
    {
        in_flight_account_keys.extend(keys);
    }
    in_flight_account_keys.sort();
    in_flight_account_keys.dedup();
    provider_bridge::plan_openai_quota_json_from_parts(
        config,
        runtime_base_dir,
        xhub_provider::OpenAIQuotaRefreshPlanOptions {
            now_ms: now,
            include_skipped,
            in_flight_account_keys,
        },
    )
}

fn provider_openai_quota_apply_http_body(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> Result<String, String> {
    let parsed_body = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        serde_json::from_str::<Value>(body)
            .map_err(|err| format!("invalid openai quota apply request json: {err}"))?
    };
    let usage = parsed_body
        .get("usage")
        .or_else(|| parsed_body.get("usage_payload"))
        .or_else(|| parsed_body.get("usagePayload"))
        .cloned()
        .ok_or_else(|| "provider openai quota apply requires usage".to_string())?;
    let runtime_base_dir = body_string(&parsed_body, "runtime_base_dir")
        .or_else(|| body_string(&parsed_body, "runtimeBaseDir"))
        .or_else(|| query_param(query, "runtime_base_dir"))
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let refreshed_at_ms = body_u64_alias(&parsed_body, "refreshed_at_ms", "refreshedAtMs")
        .or_else(|| body_u64_alias(&parsed_body, "now_ms", "nowMs"))
        .or_else(|| query_param(query, "now_ms").and_then(|value| value.parse::<u64>().ok()))
        .or_else(|| query_param(query, "nowMs").and_then(|value| value.parse::<u64>().ok()))
        .unwrap_or_else(|| now_ms().min(u64::MAX as u128) as u64);
    let options = xhub_provider::OpenAIQuotaApplyOptions {
        account_key: body_string_alias(&parsed_body, "account_key", "accountKey")
            .or_else(|| query_param(query, "account_key"))
            .or_else(|| query_param(query, "accountKey"))
            .ok_or_else(|| "provider openai quota apply requires account_key".to_string())?,
        refreshed_at_ms,
        success_interval_ms: body_u64_alias(
            &parsed_body,
            "success_interval_ms",
            "successIntervalMs",
        )
        .or_else(|| {
            query_param(query, "success_interval_ms").and_then(|value| value.parse::<u64>().ok())
        })
        .or_else(|| {
            query_param(query, "successIntervalMs").and_then(|value| value.parse::<u64>().ok())
        })
        .unwrap_or(5 * 60_000),
        high_water_interval_ms: body_u64_alias(
            &parsed_body,
            "high_water_interval_ms",
            "highWaterIntervalMs",
        )
        .or_else(|| {
            query_param(query, "high_water_interval_ms").and_then(|value| value.parse::<u64>().ok())
        })
        .or_else(|| {
            query_param(query, "highWaterIntervalMs").and_then(|value| value.parse::<u64>().ok())
        })
        .unwrap_or(60_000),
        account_id: body_string_alias(&parsed_body, "account_id", "accountId")
            .or_else(|| query_param(query, "account_id"))
            .or_else(|| query_param(query, "accountId"))
            .unwrap_or_default(),
        oauth_source_key: body_string_alias(&parsed_body, "oauth_source_key", "oauthSourceKey")
            .or_else(|| query_param(query, "oauth_source_key"))
            .or_else(|| query_param(query, "oauthSourceKey"))
            .unwrap_or_default(),
    };

    provider_bridge::apply_openai_quota_json_from_parts(config, runtime_base_dir, usage, options)
}

fn provider_openai_quota_failure_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    match provider_openai_quota_failure_http_body(config, query, body) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"provider_openai_quota_failure_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn provider_openai_quota_failure_http_body(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> Result<String, String> {
    let parsed_body = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        serde_json::from_str::<Value>(body)
            .map_err(|err| format!("invalid openai quota failure request json: {err}"))?
    };
    let runtime_base_dir = body_string(&parsed_body, "runtime_base_dir")
        .or_else(|| body_string(&parsed_body, "runtimeBaseDir"))
        .or_else(|| query_param(query, "runtime_base_dir"))
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let options = xhub_provider::OpenAIQuotaRefreshFailureOptions {
        account_key: body_string_alias(&parsed_body, "account_key", "accountKey")
            .or_else(|| query_param(query, "account_key"))
            .or_else(|| query_param(query, "accountKey"))
            .ok_or_else(|| "provider openai quota failure requires account_key".to_string())?,
        failed_at_ms: body_u64_alias(&parsed_body, "failed_at_ms", "failedAtMs")
            .or_else(|| body_u64_alias(&parsed_body, "now_ms", "nowMs"))
            .or_else(|| {
                query_param(query, "failed_at_ms").and_then(|value| value.parse::<u64>().ok())
            })
            .or_else(|| {
                query_param(query, "failedAtMs").and_then(|value| value.parse::<u64>().ok())
            })
            .or_else(|| query_param(query, "now_ms").and_then(|value| value.parse::<u64>().ok()))
            .or_else(|| query_param(query, "nowMs").and_then(|value| value.parse::<u64>().ok()))
            .unwrap_or_else(|| now_ms().min(u64::MAX as u128) as u64),
        base_failure_backoff_ms: body_u64_alias(
            &parsed_body,
            "base_failure_backoff_ms",
            "baseFailureBackoffMs",
        )
        .or_else(|| {
            query_param(query, "base_failure_backoff_ms")
                .and_then(|value| value.parse::<u64>().ok())
        })
        .or_else(|| {
            query_param(query, "baseFailureBackoffMs").and_then(|value| value.parse::<u64>().ok())
        })
        .unwrap_or(60_000),
        max_failure_backoff_ms: body_u64_alias(
            &parsed_body,
            "max_failure_backoff_ms",
            "maxFailureBackoffMs",
        )
        .or_else(|| {
            query_param(query, "max_failure_backoff_ms").and_then(|value| value.parse::<u64>().ok())
        })
        .or_else(|| {
            query_param(query, "maxFailureBackoffMs").and_then(|value| value.parse::<u64>().ok())
        })
        .unwrap_or(15 * 60_000),
        error_code: body_string_alias(&parsed_body, "error_code", "errorCode")
            .or_else(|| query_param(query, "error_code"))
            .or_else(|| query_param(query, "errorCode"))
            .unwrap_or_default(),
        error_message: body_string_alias(&parsed_body, "error_message", "errorMessage")
            .or_else(|| query_param(query, "error_message"))
            .or_else(|| query_param(query, "errorMessage"))
            .unwrap_or_default(),
    };
    provider_bridge::record_openai_quota_failure_json_from_parts(config, runtime_base_dir, options)
}

fn provider_oauth_refresh_apply_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    match provider_oauth_refresh_apply_http_body(config, query, body) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"provider_oauth_refresh_apply_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn provider_oauth_refresh_apply_http_body(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> Result<String, String> {
    let parsed_body = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        serde_json::from_str::<Value>(body)
            .map_err(|err| format!("invalid oauth refresh apply request json: {err}"))?
    };
    let runtime_base_dir = body_string(&parsed_body, "runtime_base_dir")
        .or_else(|| body_string(&parsed_body, "runtimeBaseDir"))
        .or_else(|| query_param(query, "runtime_base_dir"))
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let refreshed_at_ms = body_u64_alias(&parsed_body, "refreshed_at_ms", "refreshedAtMs")
        .or_else(|| body_u64_alias(&parsed_body, "now_ms", "nowMs"))
        .or_else(|| {
            query_param(query, "refreshed_at_ms").and_then(|value| value.parse::<u64>().ok())
        })
        .or_else(|| query_param(query, "refreshedAtMs").and_then(|value| value.parse::<u64>().ok()))
        .or_else(|| query_param(query, "now_ms").and_then(|value| value.parse::<u64>().ok()))
        .or_else(|| query_param(query, "nowMs").and_then(|value| value.parse::<u64>().ok()))
        .unwrap_or_else(|| now_ms().min(u64::MAX as u128) as u64);
    let options = xhub_provider::ProviderOAuthRefreshApplyOptions {
        account_key: body_string_alias(&parsed_body, "account_key", "accountKey")
            .or_else(|| query_param(query, "account_key"))
            .or_else(|| query_param(query, "accountKey"))
            .ok_or_else(|| "provider oauth refresh apply requires account_key".to_string())?,
        refreshed_at_ms,
        access_token: body_string_alias(&parsed_body, "access_token", "accessToken")
            .or_else(|| query_param(query, "access_token"))
            .or_else(|| query_param(query, "accessToken"))
            .ok_or_else(|| "provider oauth refresh apply requires access_token".to_string())?,
        refresh_token: body_string_alias(&parsed_body, "refresh_token", "refreshToken")
            .or_else(|| query_param(query, "refresh_token"))
            .or_else(|| query_param(query, "refreshToken"))
            .unwrap_or_default(),
        expires_at_ms: body_u64_alias(&parsed_body, "expires_at_ms", "expiresAtMs")
            .or_else(|| {
                query_param(query, "expires_at_ms").and_then(|value| value.parse::<u64>().ok())
            })
            .or_else(|| {
                query_param(query, "expiresAtMs").and_then(|value| value.parse::<u64>().ok())
            })
            .unwrap_or(0),
        account_id: body_string_alias(&parsed_body, "account_id", "accountId")
            .or_else(|| query_param(query, "account_id"))
            .or_else(|| query_param(query, "accountId"))
            .unwrap_or_default(),
        email: body_string(&parsed_body, "email")
            .or_else(|| query_param(query, "email"))
            .unwrap_or_default(),
        oauth_source_key: body_string_alias(&parsed_body, "oauth_source_key", "oauthSourceKey")
            .or_else(|| query_param(query, "oauth_source_key"))
            .or_else(|| query_param(query, "oauthSourceKey"))
            .unwrap_or_default(),
    };
    provider_bridge::apply_oauth_refresh_json_from_parts(config, runtime_base_dir, options)
}

fn provider_oauth_refresh_failure_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    match provider_oauth_refresh_failure_http_body(config, query, body) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"provider_oauth_refresh_failure_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn provider_oauth_refresh_failure_http_body(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> Result<String, String> {
    let parsed_body = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        serde_json::from_str::<Value>(body)
            .map_err(|err| format!("invalid oauth refresh failure request json: {err}"))?
    };
    let runtime_base_dir = body_string(&parsed_body, "runtime_base_dir")
        .or_else(|| body_string(&parsed_body, "runtimeBaseDir"))
        .or_else(|| query_param(query, "runtime_base_dir"))
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let options = xhub_provider::ProviderOAuthRefreshFailureOptions {
        account_key: body_string_alias(&parsed_body, "account_key", "accountKey")
            .or_else(|| query_param(query, "account_key"))
            .or_else(|| query_param(query, "accountKey"))
            .ok_or_else(|| "provider oauth refresh failure requires account_key".to_string())?,
        failed_at_ms: body_u64_alias(&parsed_body, "failed_at_ms", "failedAtMs")
            .or_else(|| body_u64_alias(&parsed_body, "now_ms", "nowMs"))
            .or_else(|| {
                query_param(query, "failed_at_ms").and_then(|value| value.parse::<u64>().ok())
            })
            .or_else(|| {
                query_param(query, "failedAtMs").and_then(|value| value.parse::<u64>().ok())
            })
            .or_else(|| query_param(query, "now_ms").and_then(|value| value.parse::<u64>().ok()))
            .or_else(|| query_param(query, "nowMs").and_then(|value| value.parse::<u64>().ok()))
            .unwrap_or_else(|| now_ms().min(u64::MAX as u128) as u64),
        base_failure_backoff_ms: body_u64_alias(
            &parsed_body,
            "base_failure_backoff_ms",
            "baseFailureBackoffMs",
        )
        .or_else(|| {
            query_param(query, "base_failure_backoff_ms")
                .and_then(|value| value.parse::<u64>().ok())
        })
        .or_else(|| {
            query_param(query, "baseFailureBackoffMs").and_then(|value| value.parse::<u64>().ok())
        })
        .unwrap_or(60_000),
        max_failure_backoff_ms: body_u64_alias(
            &parsed_body,
            "max_failure_backoff_ms",
            "maxFailureBackoffMs",
        )
        .or_else(|| {
            query_param(query, "max_failure_backoff_ms").and_then(|value| value.parse::<u64>().ok())
        })
        .or_else(|| {
            query_param(query, "maxFailureBackoffMs").and_then(|value| value.parse::<u64>().ok())
        })
        .unwrap_or(15 * 60_000),
        terminal: body_bool(&parsed_body, "terminal").unwrap_or_else(|| {
            optional_query_bool_alias(query, "terminal", "terminal", false).unwrap_or(false)
        }),
        error_code: body_string_alias(&parsed_body, "error_code", "errorCode")
            .or_else(|| query_param(query, "error_code"))
            .or_else(|| query_param(query, "errorCode"))
            .unwrap_or_default(),
        error_message: body_string_alias(&parsed_body, "error_message", "errorMessage")
            .or_else(|| query_param(query, "error_message"))
            .or_else(|| query_param(query, "errorMessage"))
            .unwrap_or_default(),
    };
    provider_bridge::record_oauth_refresh_failure_json_from_parts(config, runtime_base_dir, options)
}

fn provider_codex_oauth_plan_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    match provider_codex_oauth_plan_http_body(config, query, body) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"provider_codex_oauth_plan_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn provider_codex_oauth_plan_http_body(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> Result<String, String> {
    let parsed_body = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        serde_json::from_str::<Value>(body)
            .map_err(|err| format!("invalid codex oauth plan request json: {err}"))?
    };
    let runtime_base_dir = body_string(&parsed_body, "runtime_base_dir")
        .or_else(|| body_string(&parsed_body, "runtimeBaseDir"))
        .or_else(|| query_param(query, "runtime_base_dir"))
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let now = body_u64_alias(&parsed_body, "now_ms", "nowMs")
        .or_else(|| query_param(query, "now_ms").and_then(|value| value.parse::<u64>().ok()))
        .or_else(|| query_param(query, "nowMs").and_then(|value| value.parse::<u64>().ok()))
        .unwrap_or_else(|| now_ms().min(u64::MAX as u128) as u64);
    let include_skipped = body_bool_alias(&parsed_body, "include_skipped", "includeSkipped")
        .or_else(|| {
            optional_query_bool_alias(query, "include_skipped", "includeSkipped", false).ok()
        })
        .unwrap_or(false);
    let mut in_flight_account_keys = body_string_list(&parsed_body, "in_flight_account_keys");
    in_flight_account_keys.extend(body_string_list(&parsed_body, "inFlightAccountKeys"));
    if let Some(keys) = query_param_list(query, "in_flight_account_keys")
        .or_else(|| query_param_list(query, "inFlightAccountKeys"))
    {
        in_flight_account_keys.extend(keys);
    }
    in_flight_account_keys.sort();
    in_flight_account_keys.dedup();
    provider_bridge::plan_codex_oauth_refresh_json_from_parts(
        config,
        runtime_base_dir,
        xhub_provider::ProviderOAuthRefreshPlanOptions {
            now_ms: now,
            include_skipped,
            in_flight_account_keys,
            refresh_lead_ms: body_u64_alias(&parsed_body, "refresh_lead_ms", "refreshLeadMs")
                .or_else(|| {
                    query_param(query, "refresh_lead_ms")
                        .and_then(|value| value.parse::<u64>().ok())
                })
                .or_else(|| {
                    query_param(query, "refreshLeadMs").and_then(|value| value.parse::<u64>().ok())
                })
                .unwrap_or(0),
            min_refresh_lead_ms: body_u64_alias(
                &parsed_body,
                "min_refresh_lead_ms",
                "minRefreshLeadMs",
            )
            .or_else(|| {
                query_param(query, "min_refresh_lead_ms")
                    .and_then(|value| value.parse::<u64>().ok())
            })
            .or_else(|| {
                query_param(query, "minRefreshLeadMs").and_then(|value| value.parse::<u64>().ok())
            })
            .unwrap_or(0),
        },
    )
}

fn provider_codex_oauth_refresh_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    match provider_codex_oauth_refresh_http_body(config, query, body) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"provider_codex_oauth_refresh_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn provider_codex_oauth_refresh_http_body(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> Result<String, String> {
    let parsed_body = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        serde_json::from_str::<Value>(body)
            .map_err(|err| format!("invalid codex oauth refresh request json: {err}"))?
    };
    let runtime_base_dir = body_string(&parsed_body, "runtime_base_dir")
        .or_else(|| body_string(&parsed_body, "runtimeBaseDir"))
        .or_else(|| query_param(query, "runtime_base_dir"))
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let options = provider_bridge::CodexOAuthRefreshOptions {
        account_key: body_string_alias(&parsed_body, "account_key", "accountKey")
            .or_else(|| query_param(query, "account_key"))
            .or_else(|| query_param(query, "accountKey"))
            .ok_or_else(|| "provider codex oauth refresh requires account_key".to_string())?,
        refreshed_at_ms: body_u64_alias(&parsed_body, "refreshed_at_ms", "refreshedAtMs")
            .or_else(|| body_u64_alias(&parsed_body, "now_ms", "nowMs"))
            .or_else(|| {
                query_param(query, "refreshed_at_ms").and_then(|value| value.parse::<u64>().ok())
            })
            .or_else(|| {
                query_param(query, "refreshedAtMs").and_then(|value| value.parse::<u64>().ok())
            })
            .or_else(|| query_param(query, "now_ms").and_then(|value| value.parse::<u64>().ok()))
            .or_else(|| query_param(query, "nowMs").and_then(|value| value.parse::<u64>().ok()))
            .unwrap_or_else(|| now_ms().min(u64::MAX as u128) as u64),
        timeout_ms: body_u64_alias(&parsed_body, "timeout_ms", "timeoutMs")
            .or_else(|| {
                query_param(query, "timeout_ms").and_then(|value| value.parse::<u64>().ok())
            })
            .or_else(|| query_param(query, "timeoutMs").and_then(|value| value.parse::<u64>().ok()))
            .unwrap_or(15_000),
        base_failure_backoff_ms: body_u64_alias(
            &parsed_body,
            "base_failure_backoff_ms",
            "baseFailureBackoffMs",
        )
        .or_else(|| {
            query_param(query, "base_failure_backoff_ms")
                .and_then(|value| value.parse::<u64>().ok())
        })
        .or_else(|| {
            query_param(query, "baseFailureBackoffMs").and_then(|value| value.parse::<u64>().ok())
        })
        .unwrap_or(60_000),
        max_failure_backoff_ms: body_u64_alias(
            &parsed_body,
            "max_failure_backoff_ms",
            "maxFailureBackoffMs",
        )
        .or_else(|| {
            query_param(query, "max_failure_backoff_ms").and_then(|value| value.parse::<u64>().ok())
        })
        .or_else(|| {
            query_param(query, "maxFailureBackoffMs").and_then(|value| value.parse::<u64>().ok())
        })
        .unwrap_or(15 * 60_000),
        token_url: body_string_alias(&parsed_body, "token_url", "tokenUrl")
            .or_else(|| query_param(query, "token_url"))
            .or_else(|| query_param(query, "tokenUrl"))
            .unwrap_or_default(),
        force: body_bool(&parsed_body, "force").unwrap_or_else(|| {
            optional_query_bool_alias(query, "force", "force", false).unwrap_or(false)
        }),
    };
    provider_bridge::refresh_codex_oauth_json_from_parts(config, runtime_base_dir, options)
}

fn scheduler_status_http_json(config: &HubConfig, query: &str) -> (&'static str, String) {
    let include_queue_items =
        match optional_query_bool_alias(query, "include_queue_items", "includeQueueItems", true) {
            Ok(value) => value,
            Err(body) => return ("400 Bad Request", body),
        };
    let queue_items_limit =
        match optional_query_usize_alias(query, "queue_items_limit", "queueItemsLimit", 100) {
            Ok(value) => value,
            Err(body) => return ("400 Bad Request", body),
        };
    match scheduler_bridge::status_json_from_parts(config, include_queue_items, queue_items_limit) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"scheduler_status_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn http_metrics_json(state: &HubState) -> (&'static str, String) {
    const RECENT_SAMPLE_OUTPUT_LIMIT: usize = 64;
    let now = now_ms();
    let Ok(metrics) = state.http_metrics.lock() else {
        return (
            "503 Service Unavailable",
            "{\"ok\":false,\"error\":\"http_metrics_unavailable\"}\n".to_string(),
        );
    };
    let routes = metrics
        .routes
        .iter()
        .map(|(route, item)| {
            let avg_elapsed_ms = if item.count == 0 {
                0.0
            } else {
                item.total_elapsed_ms as f64 / item.count as f64
            };
            json!({
                "route": route,
                "count": item.count,
                "slow_count": item.slow_count,
                "avg_elapsed_ms": round2(avg_elapsed_ms),
                "max_elapsed_ms": item.max_elapsed_ms.min(i64::MAX as u128) as i64,
                "last_elapsed_ms": item.last_elapsed_ms.min(i64::MAX as u128) as i64,
                "last_status": item.last_status,
            })
        })
        .collect::<Vec<_>>();
    let recent_sample_count = metrics.recent_samples.len();
    let recent_slow_requests = metrics
        .recent_samples
        .iter()
        .filter(|sample| sample.slow)
        .count();
    let recent_total_elapsed_ms = metrics
        .recent_samples
        .iter()
        .fold(0_u128, |acc, sample| acc.saturating_add(sample.elapsed_ms));
    let recent_avg_elapsed_ms = if recent_sample_count == 0 {
        0.0
    } else {
        recent_total_elapsed_ms as f64 / recent_sample_count as f64
    };
    let recent_max_elapsed_ms = metrics
        .recent_samples
        .iter()
        .map(|sample| sample.elapsed_ms)
        .max()
        .unwrap_or(0);
    let mut recent_routes: BTreeMap<String, HttpRouteMetrics> = BTreeMap::new();
    for sample in metrics.recent_samples.iter() {
        let route_metrics = recent_routes.entry(sample.route.clone()).or_default();
        route_metrics.count = route_metrics.count.saturating_add(1);
        route_metrics.total_elapsed_ms = route_metrics
            .total_elapsed_ms
            .saturating_add(sample.elapsed_ms);
        route_metrics.max_elapsed_ms = route_metrics.max_elapsed_ms.max(sample.elapsed_ms);
        route_metrics.last_elapsed_ms = sample.elapsed_ms;
        route_metrics.last_status = sample.status.clone();
        if sample.slow {
            route_metrics.slow_count = route_metrics.slow_count.saturating_add(1);
        }
    }
    let recent_route_summaries = recent_routes
        .iter()
        .map(|(route, item)| {
            let avg_elapsed_ms = if item.count == 0 {
                0.0
            } else {
                item.total_elapsed_ms as f64 / item.count as f64
            };
            json!({
                "route": route,
                "count": item.count,
                "slow_count": item.slow_count,
                "avg_elapsed_ms": round2(avg_elapsed_ms),
                "max_elapsed_ms": item.max_elapsed_ms.min(i64::MAX as u128) as i64,
                "last_elapsed_ms": item.last_elapsed_ms.min(i64::MAX as u128) as i64,
                "last_status": item.last_status,
            })
        })
        .collect::<Vec<_>>();
    let recent_samples = metrics
        .recent_samples
        .iter()
        .rev()
        .take(RECENT_SAMPLE_OUTPUT_LIMIT)
        .map(|sample| {
            json!({
                "completed_at_ms": sample.completed_at_ms.min(i64::MAX as u128) as i64,
                "route": sample.route,
                "status": sample.status,
                "elapsed_ms": sample.elapsed_ms.min(i64::MAX as u128) as i64,
                "slow": sample.slow,
            })
        })
        .collect::<Vec<_>>();
    let avg_elapsed_ms = if metrics.total_requests == 0 {
        0.0
    } else {
        let total = metrics.routes.values().fold(0_u128, |acc, item| {
            acc.saturating_add(item.total_elapsed_ms)
        });
        total as f64 / metrics.total_requests as f64
    };
    let body = json!({
        "schema_version": "xhub.rust_hub.http_metrics.v1",
        "ok": true,
        "generated_at_ms": now.min(i64::MAX as u128) as i64,
        "started_at_ms": metrics.started_at_ms.min(i64::MAX as u128) as i64,
        "uptime_ms": now.saturating_sub(metrics.started_at_ms).min(i64::MAX as u128) as i64,
        "total_requests": metrics.total_requests,
        "slow_requests": metrics.slow_requests,
        "avg_elapsed_ms": round2(avg_elapsed_ms),
        "max_elapsed_ms": metrics.max_elapsed_ms.min(i64::MAX as u128) as i64,
        "slow_threshold_ms": state.http_slow_ms.min(i64::MAX as u128) as i64,
        "recent_sample_capacity": state.http_metrics_recent_limit,
        "recent_sample_count": recent_sample_count,
        "recent_samples_output_limit": RECENT_SAMPLE_OUTPUT_LIMIT,
        "recent_samples_included": recent_samples.len(),
        "recent_dropped_samples": metrics.recent_dropped_samples,
        "recent_slow_requests": recent_slow_requests,
        "recent_avg_elapsed_ms": round2(recent_avg_elapsed_ms),
        "recent_max_elapsed_ms": recent_max_elapsed_ms.min(i64::MAX as u128) as i64,
        "recent_route_count": recent_route_summaries.len(),
        "recent_routes": recent_route_summaries,
        "recent_samples_newest_first": recent_samples,
        "http_max_in_flight": state.http_max_in_flight,
        "current_in_flight": state.http_in_flight.load(Ordering::Acquire),
        "route_count": routes.len(),
        "routes": routes,
        "authority": "diagnostics_only",
        "production_authority_change": false,
        "detail_json_included": false,
    });
    ("200 OK", format!("{body}\n"))
}

fn round2(value: f64) -> f64 {
    (value * 100.0).round() / 100.0
}

fn memory_search_http_json(state: &HubState, query: &str) -> (&'static str, String) {
    let config = &state.config;
    let memory_dir = query_param(query, "memory_dir")
        .or_else(|| query_param(query, "memoryDir"))
        .map(PathBuf::from)
        .unwrap_or_else(|| memory_bridge::memory_dir_from_env(config));
    let snapshot = cached_memory_snapshot(state, memory_dir.clone());
    let mut request = MemoryRetrievalRequest::with_defaults(memory_dir);
    request.request_id = query_param(query, "request_id")
        .or_else(|| query_param(query, "requestId"))
        .unwrap_or_default();
    request.scope = query_param(query, "scope").unwrap_or_else(|| "current_project".to_string());
    request.mode = MemoryMode::from_str(
        query_param(query, "mode")
            .unwrap_or_else(|| "project_code".to_string())
            .as_str(),
    );
    request.project_id = query_param(query, "project_id")
        .or_else(|| query_param(query, "projectId"))
        .unwrap_or_default();
    request.query = query_param(query, "query").unwrap_or_default();
    request.latest_user = query_param(query, "latest_user")
        .or_else(|| query_param(query, "latestUser"))
        .unwrap_or_default();
    request.retrieval_kind = query_param(query, "retrieval_kind")
        .or_else(|| query_param(query, "retrievalKind"))
        .unwrap_or_else(|| "search".to_string());
    request.max_results = match optional_query_usize_alias(query, "max_results", "maxResults", 5) {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    request.max_snippet_chars =
        match optional_query_usize_alias(query, "max_snippet_chars", "maxSnippetChars", 480) {
            Ok(value) => value,
            Err(body) => return ("400 Bad Request", body),
        };
    request.requested_kinds = query_param_list(query, "requested_kinds")
        .or_else(|| query_param_list(query, "requestedKinds"))
        .unwrap_or_default();
    request.requested_layers = query_param_list(query, "requested_layers")
        .or_else(|| query_param_list(query, "requestedLayers"))
        .or_else(|| query_param_list(query, "layers"))
        .unwrap_or_default();
    request.explicit_refs = query_param_list(query, "explicit_refs")
        .or_else(|| query_param_list(query, "explicitRefs"))
        .unwrap_or_default();
    request.sensitivity_max = query_param(query, "sensitivity_max")
        .or_else(|| query_param(query, "sensitivityMax"))
        .unwrap_or_default();
    request.visibility = query_param(query, "visibility").unwrap_or_default();
    request.created_after_ms =
        match optional_query_i64_alias(query, "created_after_ms", "createdAfterMs", 0) {
            Ok(value) => value,
            Err(body) => return ("400 Bad Request", body),
        };
    request.updated_after_ms =
        match optional_query_i64_alias(query, "updated_after_ms", "updatedAfterMs", 0) {
            Ok(value) => value,
            Err(body) => return ("400 Bad Request", body),
        };
    request.explain = match optional_query_bool_alias(query, "explain", "explain", false) {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    request.audit_ref = query_param(query, "audit_ref")
        .or_else(|| query_param(query, "auditRef"))
        .unwrap_or_default();
    match memory_bridge::retrieve_json_from_request_with_config_and_snapshot(
        config, request, &snapshot,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"memory_search_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn memory_retrieve_http_json(state: &HubState, _query: &str, body: &str) -> (&'static str, String) {
    let config = &state.config;
    let parsed = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        match serde_json::from_str::<Value>(body) {
            Ok(value) => value,
            Err(err) => {
                return (
                    "400 Bad Request",
                    format!(
                        "{{\"ok\":false,\"error\":\"invalid_memory_retrieve_json\",\"message\":\"{}\"}}\n",
                        json_escape(&err.to_string())
                    ),
                )
            }
        }
    };
    let request = memory_bridge::retrieve_request_from_value(config, &parsed);
    let snapshot = cached_memory_snapshot(state, request.memory_dir.clone());
    match memory_bridge::retrieve_json_from_request_with_config_and_snapshot(
        config, request, &snapshot,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"memory_retrieve_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn memory_role_transcript_http_json(config: &HubConfig, query: &str) -> (&'static str, String) {
    let project_id = query_param(query, "project_id")
        .or_else(|| query_param(query, "projectId"))
        .unwrap_or_default();
    let thread_key = query_param(query, "thread_key")
        .or_else(|| query_param(query, "threadKey"))
        .unwrap_or_else(|| {
            if project_id.trim().is_empty() {
                String::new()
            } else {
                format!("xterminal_project_{}", project_id.trim())
            }
        });
    let limit = match optional_query_usize_alias(query, "limit", "limit", 50) {
        Ok(value) => value.clamp(1, 500),
        Err(body) => return ("400 Bad Request", body),
    };
    let include_content =
        match optional_query_bool_alias(query, "include_content", "includeContent", false) {
            Ok(value) => value,
            Err(body) => return ("400 Bad Request", body),
        };
    if project_id.trim().is_empty() || thread_key.trim().is_empty() {
        return (
            "400 Bad Request",
            "{\"ok\":false,\"error\":\"invalid_project_role_transcript_request\",\"message\":\"project_id and thread_key are required\"}\n".to_string(),
        );
    }
    match memory_role_projection::projection_json_from_parts(
        config,
        query_param(query, "device_id").or_else(|| query_param(query, "deviceId")),
        query_param(query, "app_id").or_else(|| query_param(query, "appId")),
        project_id,
        thread_key,
        limit,
        include_content,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) if err == "role_metadata_project_mismatch" => (
            "409 Conflict",
            "{\"ok\":false,\"error\":\"role_metadata_project_mismatch\"}\n".to_string(),
        ),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"project_role_transcript_projection_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn memory_write_http_json(config: &HubConfig, body: &str) -> (&'static str, String) {
    let parsed = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        match serde_json::from_str::<Value>(body) {
            Ok(value) => value,
            Err(err) => {
                return (
                    "400 Bad Request",
                    format!(
                    "{{\"ok\":false,\"error\":\"invalid_memory_write_json\",\"message\":\"{}\"}}\n",
                    json_escape(&err.to_string())
                ),
                )
            }
        }
    };
    match memory_bridge::write_json_from_value(config, &parsed) {
        Ok(body) => {
            let status = if body.contains("\"status\":\"denied\"") {
                "403 Forbidden"
            } else if body.contains("\"status\":\"error\"") {
                "500 Internal Server Error"
            } else {
                "200 OK"
            };
            (status, format!("{body}\n"))
        }
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"memory_write_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn memory_readiness_http_json(state: &HubState, query: &str) -> (&'static str, String) {
    let config = &state.config;
    let memory_dir = query_param(query, "memory_dir")
        .or_else(|| query_param(query, "memoryDir"))
        .map(PathBuf::from)
        .unwrap_or_else(|| memory_bridge::memory_dir_from_env(config));
    let snapshot = cached_memory_snapshot(state, memory_dir);
    match memory_bridge::readiness_json_from_snapshot_with_config(config, &snapshot) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"memory_readiness_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn evidence_ledger_http_json(config: &HubConfig, query: &str) -> (&'static str, String) {
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

fn evidence_write_http_json(config: &HubConfig, body: &str) -> (&'static str, String) {
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

fn maybe_attach_route_evidence(
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

fn route_evidence_request(
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

fn route_evidence_verdict(component: &str, response: &Value) -> String {
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

fn route_evidence_reason(component: &str, response: &Value) -> Value {
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

fn route_evidence_input_ref(response: &Value) -> Value {
    json!({
        "schema_version": response.get("schema_version").cloned().unwrap_or(Value::Null),
        "command": response.get("command").cloned().unwrap_or(Value::Null),
        "request": response.get("request").cloned().unwrap_or(Value::Null),
        "updated_at_ms": response.get("updated_at_ms").cloned().unwrap_or(Value::Null),
    })
}

fn route_evidence_payload(component: &str, response: &Value) -> Value {
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

fn skills_catalog_http_json(state: &HubState, query: &str) -> (&'static str, String) {
    let config = &state.config;
    let skills_dir = query_param(query, "skills_dir")
        .or_else(|| query_param(query, "skillsDir"))
        .map(PathBuf::from)
        .unwrap_or_else(|| skills_bridge::skills_dir_from_env(config));
    let catalog = cached_skills_catalog(state, skills_dir);
    match skills_bridge::catalog_json_from_catalog(&catalog) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"skills_catalog_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn skills_readiness_http_json(state: &HubState, query: &str) -> (&'static str, String) {
    let config = &state.config;
    let skills_dir = query_param(query, "skills_dir")
        .or_else(|| query_param(query, "skillsDir"))
        .map(PathBuf::from)
        .unwrap_or_else(|| skills_bridge::skills_dir_from_env(config));
    let catalog = cached_skills_catalog(state, skills_dir);
    match skills_bridge::readiness_json_from_catalog(&catalog) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"skills_readiness_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn skills_policy_readiness_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    let parsed = parse_optional_json_body(body);
    let parsed = match parsed {
        Ok(value) => value,
        Err(err) => {
            return (
                "400 Bad Request",
                format!(
                    "{{\"ok\":false,\"error\":\"invalid_skills_policy_readiness_json\",\"message\":\"{}\"}}\n",
                    json_escape(&err)
                ),
            )
        }
    };
    let max_preflight_audit_rows = body_or_query_i64_in_range(
        &parsed,
        query,
        "max_preflight_audit_rows",
        "maxPreflightAuditRows",
        100_000,
        1,
        10_000_000,
    );
    let max_policy_event_rows = body_or_query_i64_in_range(
        &parsed,
        query,
        "max_policy_event_rows",
        "maxPolicyEventRows",
        100_000,
        1,
        10_000_000,
    );
    match skills_bridge::policy_store_readiness_json_from_parts(
        config,
        max_preflight_audit_rows,
        max_policy_event_rows,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"skills_policy_readiness_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn skills_pin_http_json(config: &HubConfig, query: &str, body: &str) -> (&'static str, String) {
    let parsed = parse_optional_json_body(body);
    let parsed = match parsed {
        Ok(value) => value,
        Err(err) => {
            return (
                "400 Bad Request",
                format!(
                    "{{\"ok\":false,\"error\":\"invalid_skills_pin_json\",\"message\":\"{}\"}}\n",
                    json_escape(&err)
                ),
            )
        }
    };
    match skills_bridge::pin_json_from_parts(
        config,
        body_or_query_string(&parsed, query, "scope_key", "scopeKey")
            .unwrap_or_else(|| "default".to_string()),
        body_or_query_string(&parsed, query, "skill_id", "skillId").unwrap_or_default(),
        body_or_query_string(&parsed, query, "pinned_by", "pinnedBy")
            .or_else(|| body_or_query_string(&parsed, query, "actor", "actor"))
            .unwrap_or_else(|| "rust_hub_operator".to_string()),
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"skills_pin_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn skills_grant_http_json(config: &HubConfig, query: &str, body: &str) -> (&'static str, String) {
    let parsed = parse_optional_json_body(body);
    let parsed = match parsed {
        Ok(value) => value,
        Err(err) => {
            return (
                "400 Bad Request",
                format!(
                    "{{\"ok\":false,\"error\":\"invalid_skills_grant_json\",\"message\":\"{}\"}}\n",
                    json_escape(&err)
                ),
            )
        }
    };
    match skills_bridge::grant_json_from_parts(
        config,
        body_or_query_string(&parsed, query, "scope_key", "scopeKey")
            .unwrap_or_else(|| "default".to_string()),
        body_or_query_string(&parsed, query, "skill_id", "skillId").unwrap_or_default(),
        body_or_query_string(&parsed, query, "capability", "capability").unwrap_or_default(),
        body_or_query_string(&parsed, query, "granted_by", "grantedBy")
            .or_else(|| body_or_query_string(&parsed, query, "actor", "actor"))
            .unwrap_or_else(|| "rust_hub_operator".to_string()),
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"skills_grant_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn skills_unpin_http_json(config: &HubConfig, query: &str, body: &str) -> (&'static str, String) {
    let parsed = parse_optional_json_body(body);
    let parsed = match parsed {
        Ok(value) => value,
        Err(err) => {
            return (
                "400 Bad Request",
                format!(
                    "{{\"ok\":false,\"error\":\"invalid_skills_unpin_json\",\"message\":\"{}\"}}\n",
                    json_escape(&err)
                ),
            )
        }
    };
    match skills_bridge::unpin_json_from_parts(
        config,
        body_or_query_string(&parsed, query, "scope_key", "scopeKey")
            .unwrap_or_else(|| "default".to_string()),
        body_or_query_string(&parsed, query, "skill_id", "skillId").unwrap_or_default(),
        body_or_query_string(&parsed, query, "revoked_by", "revokedBy")
            .or_else(|| body_or_query_string(&parsed, query, "actor", "actor"))
            .unwrap_or_else(|| "rust_hub_operator".to_string()),
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"skills_unpin_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn skills_revoke_grant_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    let parsed = parse_optional_json_body(body);
    let parsed = match parsed {
        Ok(value) => value,
        Err(err) => {
            return (
                "400 Bad Request",
                format!(
                    "{{\"ok\":false,\"error\":\"invalid_skills_revoke_grant_json\",\"message\":\"{}\"}}\n",
                    json_escape(&err)
                ),
            )
        }
    };
    match skills_bridge::revoke_grant_json_from_parts(
        config,
        body_or_query_string(&parsed, query, "scope_key", "scopeKey")
            .unwrap_or_else(|| "default".to_string()),
        body_or_query_string(&parsed, query, "skill_id", "skillId").unwrap_or_default(),
        body_or_query_string(&parsed, query, "capability", "capability").unwrap_or_default(),
        body_or_query_string(&parsed, query, "revoked_by", "revokedBy")
            .or_else(|| body_or_query_string(&parsed, query, "actor", "actor"))
            .unwrap_or_else(|| "rust_hub_operator".to_string()),
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"skills_revoke_grant_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn skills_policy_http_json(config: &HubConfig, query: &str, body: &str) -> (&'static str, String) {
    let parsed = parse_optional_json_body(body);
    let parsed = match parsed {
        Ok(value) => value,
        Err(err) => {
            return (
                "400 Bad Request",
                format!(
                "{{\"ok\":false,\"error\":\"invalid_skills_policy_json\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
            )
        }
    };
    match skills_bridge::policy_json_from_parts(
        config,
        body_or_query_string(&parsed, query, "scope_key", "scopeKey")
            .unwrap_or_else(|| "default".to_string()),
        body_or_query_string(&parsed, query, "skill_id", "skillId").unwrap_or_default(),
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"skills_policy_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn skills_policy_events_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    let parsed = parse_optional_json_body(body);
    let parsed = match parsed {
        Ok(value) => value,
        Err(err) => {
            return (
                "400 Bad Request",
                format!(
                    "{{\"ok\":false,\"error\":\"invalid_skills_policy_events_json\",\"message\":\"{}\"}}\n",
                    json_escape(&err)
                ),
            )
        }
    };
    let limit = body_or_query_usize_in_range(&parsed, query, "limit", "limit", 20, 1, 500);
    match skills_bridge::policy_events_json_from_parts(
        config,
        body_or_query_string(&parsed, query, "scope_key", "scopeKey"),
        body_or_query_string(&parsed, query, "skill_id", "skillId"),
        limit,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"skills_policy_events_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn skills_policy_events_prune_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    let parsed = parse_optional_json_body(body);
    let parsed = match parsed {
        Ok(value) => value,
        Err(err) => {
            return (
                "400 Bad Request",
                format!(
                    "{{\"ok\":false,\"error\":\"invalid_skills_policy_events_prune_json\",\"message\":\"{}\"}}\n",
                    json_escape(&err)
                ),
            )
        }
    };
    let max_rows =
        body_or_query_usize_in_range(&parsed, query, "max_rows", "maxRows", 10_000, 1, 1_000_000);
    match skills_bridge::policy_events_prune_json_from_parts(config, max_rows) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"skills_policy_events_prune_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn skills_audit_http_json(config: &HubConfig, query: &str, body: &str) -> (&'static str, String) {
    let parsed = parse_optional_json_body(body);
    let parsed = match parsed {
        Ok(value) => value,
        Err(err) => {
            return (
                "400 Bad Request",
                format!(
                    "{{\"ok\":false,\"error\":\"invalid_skills_audit_json\",\"message\":\"{}\"}}\n",
                    json_escape(&err)
                ),
            )
        }
    };
    let limit = body_or_query_usize_in_range(&parsed, query, "limit", "limit", 20, 1, 500);
    match skills_bridge::audit_json_from_parts(
        config,
        body_or_query_string(&parsed, query, "scope_key", "scopeKey"),
        body_or_query_string(&parsed, query, "skill_id", "skillId"),
        limit,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"skills_audit_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn skills_audit_prune_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    let parsed = parse_optional_json_body(body);
    let parsed = match parsed {
        Ok(value) => value,
        Err(err) => return (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"invalid_skills_audit_prune_json\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    };
    let max_rows =
        body_or_query_usize_in_range(&parsed, query, "max_rows", "maxRows", 10_000, 1, 1_000_000);
    match skills_bridge::audit_prune_json_from_parts(config, max_rows) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"skills_audit_prune_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn skills_preflight_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    let mut parsed = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        match serde_json::from_str::<Value>(body) {
            Ok(value) => value,
            Err(err) => {
                return (
                    "400 Bad Request",
                    format!(
                        "{{\"ok\":false,\"error\":\"invalid_skills_preflight_json\",\"message\":\"{}\"}}\n",
                        json_escape(&err.to_string())
                    ),
                )
            }
        }
    };
    merge_skills_preflight_query(&mut parsed, query);
    match skills_bridge::preflight_json_from_value(config, parsed) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"skills_preflight_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn skills_execute_http_json(config: &HubConfig, query: &str, body: &str) -> (&'static str, String) {
    let mut parsed = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        match serde_json::from_str::<Value>(body) {
            Ok(value) => value,
            Err(err) => {
                return (
                    "400 Bad Request",
                    format!(
                        "{{\"ok\":false,\"error\":\"invalid_skills_execute_json\",\"message\":\"{}\"}}\n",
                        json_escape(&err.to_string())
                    ),
                )
            }
        }
    };
    merge_skills_preflight_query(&mut parsed, query);
    match skills_bridge::execute_json_from_value(config, parsed) {
        Ok(body) => {
            let status = if body.contains("\"status\":\"denied\"") {
                "403 Forbidden"
            } else if body.contains("\"status\":\"error\"") {
                "500 Internal Server Error"
            } else {
                "200 OK"
            };
            (status, format!("{body}\n"))
        }
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"skills_execute_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn parse_optional_json_body(body: &str) -> Result<Value, String> {
    if body.trim().is_empty() {
        Ok(Value::Object(Default::default()))
    } else {
        serde_json::from_str::<Value>(body).map_err(|err| err.to_string())
    }
}

fn body_or_query_string(value: &Value, query: &str, key: &str, alias: &str) -> Option<String> {
    body_string(value, key)
        .or_else(|| body_string(value, alias))
        .or_else(|| query_param(query, key))
        .or_else(|| query_param(query, alias))
}

fn merge_skills_preflight_query(body: &mut Value, query: &str) {
    let Some(map) = body.as_object_mut() else {
        return;
    };
    for (query_key, body_key) in [
        ("skills_dir", "skills_dir"),
        ("skillsDir", "skillsDir"),
        ("request_id", "request_id"),
        ("requestId", "requestId"),
        ("audit_ref", "audit_ref"),
        ("auditRef", "auditRef"),
        ("scope_key", "scope_key"),
        ("scopeKey", "scopeKey"),
        ("skill_id", "skill_id"),
        ("skillId", "skillId"),
        ("requested_capabilities", "requested_capabilities"),
        ("requestedCapabilities", "requestedCapabilities"),
        ("pinned_skill_ids", "pinned_skill_ids"),
        ("pinnedSkillIds", "pinnedSkillIds"),
        ("granted_capabilities", "granted_capabilities"),
        ("grantedCapabilities", "grantedCapabilities"),
    ] {
        if !map.contains_key(body_key) {
            if let Some(value) = query_param(query, query_key) {
                map.insert(body_key.to_string(), Value::String(value));
            }
        }
    }
}

fn model_inventory_http_json(config: &HubConfig, query: &str) -> (&'static str, String) {
    let runtime_base_dir = query_param(query, "runtime_base_dir")
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let request_now_ms = match optional_query_u128_alias(query, "now_ms", "nowMs") {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    match model_bridge::inventory_json_from_parts(config, runtime_base_dir, request_now_ms) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"model_inventory_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn model_capabilities_http_json(config: &HubConfig, query: &str) -> (&'static str, String) {
    let runtime_base_dir = query_param(query, "runtime_base_dir")
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let request_now_ms = match optional_query_u128_alias(query, "now_ms", "nowMs") {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    match model_bridge::local_capabilities_json_from_parts(config, runtime_base_dir, request_now_ms)
    {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"model_capabilities_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn model_repair_plan_http_json(config: &HubConfig, query: &str) -> (&'static str, String) {
    let runtime_base_dir = query_param(query, "runtime_base_dir")
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let request_now_ms = match optional_query_u128_alias(query, "now_ms", "nowMs") {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    let request = model_bridge::ModelLocalRepairPlanRequest {
        action: query_param(query, "action")
            .or_else(|| query_param(query, "repair_action"))
            .or_else(|| query_param(query, "repairAction"))
            .unwrap_or_default(),
        task_kind: query_param(query, "task_kind")
            .or_else(|| query_param(query, "taskKind"))
            .or_else(|| query_param(query, "task"))
            .unwrap_or_default(),
        provider_id: query_param(query, "provider_id")
            .or_else(|| query_param(query, "providerId"))
            .or_else(|| query_param(query, "provider"))
            .unwrap_or_default(),
    };
    match model_bridge::local_repair_plan_json_from_parts(
        config,
        runtime_base_dir,
        request,
        request_now_ms,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"model_repair_plan_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn model_repair_apply_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    let parsed_body = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        match serde_json::from_str::<Value>(body) {
            Ok(value) => value,
            Err(err) => {
                return (
                    "400 Bad Request",
                    format!(
                        "{{\"ok\":false,\"error\":\"invalid_model_repair_apply_json\",\"message\":\"{}\"}}\n",
                        json_escape(&err.to_string())
                    ),
                )
            }
        }
    };
    let runtime_base_dir = query_param(query, "runtime_base_dir")
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .or_else(|| body_string_alias(&parsed_body, "runtime_base_dir", "runtimeBaseDir"))
        .map(PathBuf::from);
    let request_now_ms = match optional_query_u128_alias(query, "now_ms", "nowMs") {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    let query_confirm = match optional_query_bool_alias(query, "confirm", "confirmed", false) {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    let query_dry_run = match optional_query_bool_alias(query, "dry_run", "dryRun", false) {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    let request = model_bridge::ModelLocalRepairApplyRequest {
        action: body_string(&parsed_body, "action")
            .or_else(|| body_string_alias(&parsed_body, "repair_action", "repairAction"))
            .or_else(|| query_param(query, "action"))
            .or_else(|| query_param(query, "repair_action"))
            .or_else(|| query_param(query, "repairAction"))
            .unwrap_or_default(),
        task_kind: body_string_alias(&parsed_body, "task_kind", "taskKind")
            .or_else(|| body_string(&parsed_body, "task"))
            .or_else(|| query_param(query, "task_kind"))
            .or_else(|| query_param(query, "taskKind"))
            .or_else(|| query_param(query, "task"))
            .unwrap_or_default(),
        provider_id: body_string_alias(&parsed_body, "provider_id", "providerId")
            .or_else(|| body_string(&parsed_body, "provider"))
            .or_else(|| query_param(query, "provider_id"))
            .or_else(|| query_param(query, "providerId"))
            .or_else(|| query_param(query, "provider"))
            .unwrap_or_default(),
        confirm: body_bool_alias(&parsed_body, "confirm", "confirmed").unwrap_or(query_confirm),
        dry_run: body_bool_alias(&parsed_body, "dry_run", "dryRun").unwrap_or(query_dry_run),
        confirmation_token: body_string_alias(
            &parsed_body,
            "confirmation_token",
            "confirmationToken",
        )
        .or_else(|| query_param(query, "confirmation_token"))
        .or_else(|| query_param(query, "confirmationToken"))
        .unwrap_or_default(),
        requested_by: body_string_alias(&parsed_body, "requested_by", "requestedBy")
            .or_else(|| query_param(query, "requested_by"))
            .or_else(|| query_param(query, "requestedBy"))
            .unwrap_or_else(|| "http".to_string()),
    };
    match model_bridge::local_repair_apply_json_from_parts(
        config,
        runtime_base_dir,
        request,
        request_now_ms,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"model_repair_apply_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn model_repair_jobs_http_json(config: &HubConfig, query: &str) -> (&'static str, String) {
    let runtime_base_dir = query_param(query, "runtime_base_dir")
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let request_now_ms = match optional_query_u128_alias(query, "now_ms", "nowMs") {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    let limit = match optional_query_usize(query, "limit", 20) {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    match model_bridge::local_repair_jobs_json_from_parts(
        config,
        runtime_base_dir,
        limit,
        request_now_ms,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"model_repair_jobs_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn model_route_http_json(config: &HubConfig, query: &str, body: &str) -> (&'static str, String) {
    match model_route_http_body(config, query, body) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"model_route_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn model_route_http_body(config: &HubConfig, query: &str, body: &str) -> Result<String, String> {
    let parsed_body = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        serde_json::from_str::<Value>(body)
            .map_err(|err| format!("invalid model route request json: {err}"))?
    };

    let runtime_base_dir = body_string(&parsed_body, "runtime_base_dir")
        .or_else(|| body_string(&parsed_body, "runtimeBaseDir"))
        .or_else(|| query_param(query, "runtime_base_dir"))
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let route_now_ms = body_u128(&parsed_body, "now_ms")
        .or_else(|| body_u128(&parsed_body, "nowMs"))
        .or_else(|| query_param(query, "now_ms").and_then(|value| value.parse::<u128>().ok()))
        .or_else(|| query_param(query, "nowMs").and_then(|value| value.parse::<u128>().ok()));
    let request = model_bridge::ModelRouteRequest {
        task_type: first_non_empty_string(vec![
            body_string(&parsed_body, "task_type"),
            body_string(&parsed_body, "taskType"),
            body_string(&parsed_body, "task"),
            query_param(query, "task_type"),
            query_param(query, "taskType"),
            query_param(query, "task"),
        ])
        .unwrap_or_else(|| "text_generate".to_string()),
        model_id: first_non_empty_string(vec![
            body_string(&parsed_body, "model_id"),
            body_string(&parsed_body, "modelId"),
            body_string(&parsed_body, "preferred_model_id"),
            body_string(&parsed_body, "preferredModelId"),
            query_param(query, "model_id"),
            query_param(query, "modelId"),
            query_param(query, "preferred_model_id"),
            query_param(query, "preferredModelId"),
        ])
        .unwrap_or_else(|| "auto".to_string()),
        required_capabilities: first_non_empty_string_list(vec![
            body_string_list(&parsed_body, "required_capabilities"),
            body_string_list(&parsed_body, "requiredCapabilities"),
            body_string_list(&parsed_body, "required_capability"),
            body_string_list(&parsed_body, "requiredCapability"),
            body_string_list(&parsed_body, "capabilities"),
            query_string_list(query, "required_capabilities"),
            query_string_list(query, "requiredCapabilities"),
            query_string_list(query, "required_capability"),
            query_string_list(query, "requiredCapability"),
            query_string_list(query, "capabilities"),
        ]),
        privacy_mode: first_non_empty_string(vec![
            body_string(&parsed_body, "privacy_mode"),
            body_string(&parsed_body, "privacyMode"),
            query_param(query, "privacy_mode"),
            query_param(query, "privacyMode"),
        ])
        .unwrap_or_else(|| "standard".to_string()),
        cost_preference: first_non_empty_string(vec![
            body_string(&parsed_body, "cost_preference"),
            body_string(&parsed_body, "costPreference"),
            query_param(query, "cost_preference"),
            query_param(query, "costPreference"),
        ])
        .unwrap_or_else(|| "balanced".to_string()),
    };

    let body =
        model_bridge::route_json_from_parts(config, runtime_base_dir, request, route_now_ms)?;
    maybe_attach_route_evidence(config, query, &parsed_body, "model_route", body)
}

fn model_compare_http_json(config: &HubConfig, query: &str, body: &str) -> (&'static str, String) {
    match model_compare_http_body(config, query, body) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"model_compare_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn model_compare_http_body(config: &HubConfig, query: &str, body: &str) -> Result<String, String> {
    let parsed_body = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        serde_json::from_str::<Value>(body)
            .map_err(|err| format!("invalid model compare request json: {err}"))?
    };

    let node_value = if let Some(value) = parsed_body.get("node_inventory") {
        value.clone()
    } else if let Some(value) = parsed_body.get("nodeInventory") {
        value.clone()
    } else if let Some(raw) = parsed_body
        .get("node_inventory_json")
        .or_else(|| parsed_body.get("nodeInventoryJson"))
        .and_then(Value::as_str)
    {
        serde_json::from_str::<Value>(raw)
            .map_err(|err| format!("invalid node_inventory_json: {err}"))?
    } else if let Some(raw) = query_param(query, "node_inventory_json")
        .or_else(|| query_param(query, "nodeInventoryJson"))
    {
        serde_json::from_str::<Value>(&raw)
            .map_err(|err| format!("invalid node_inventory_json: {err}"))?
    } else {
        return Err("model compare requires node_inventory".to_string());
    };

    let runtime_base_dir = body_string(&parsed_body, "runtime_base_dir")
        .or_else(|| body_string(&parsed_body, "runtimeBaseDir"))
        .or_else(|| query_param(query, "runtime_base_dir"))
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let compare_now_ms = body_u128(&parsed_body, "now_ms")
        .or_else(|| body_u128(&parsed_body, "nowMs"))
        .or_else(|| query_param(query, "now_ms").and_then(|value| value.parse::<u128>().ok()))
        .or_else(|| query_param(query, "nowMs").and_then(|value| value.parse::<u128>().ok()));

    model_bridge::compare_inventory_json_from_parts(
        config,
        runtime_base_dir,
        node_value,
        compare_now_ms,
    )
}

fn model_reports_http_json(config: &HubConfig, query: &str) -> (&'static str, String) {
    let limit = match optional_query_usize(query, "limit", 20) {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    match model_bridge::reports_json_from_parts(config, limit) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"model_reports_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn model_diagnostics_http_json(config: &HubConfig, query: &str) -> (&'static str, String) {
    let limit = match optional_query_usize(query, "limit", 3) {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    match model_bridge::diagnostics_json_from_parts(config, limit) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"model_diagnostics_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn model_readiness_http_json(config: &HubConfig, query: &str) -> (&'static str, String) {
    let limit = match optional_query_usize(query, "limit", 20) {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    let min_compare_reports =
        match optional_query_i64_alias(query, "min_compare_reports", "minCompareReports", 10) {
            Ok(value) => value,
            Err(body) => return ("400 Bad Request", body),
        };
    let max_mismatches = match optional_query_i64_alias(query, "max_mismatches", "maxMismatches", 0)
    {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    match model_bridge::readiness_json_from_parts(
        config,
        min_compare_reports,
        max_mismatches,
        limit,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"model_readiness_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn scheduler_readiness_http_json(config: &HubConfig, query: &str) -> (&'static str, String) {
    let compare_limit = match optional_query_usize_alias(query, "compare_limit", "compareLimit", 20)
    {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    let min_compare_reports =
        match optional_query_i64_alias(query, "min_compare_reports", "minCompareReports", 10) {
            Ok(value) => value.max(0),
            Err(body) => return ("400 Bad Request", body),
        };
    let max_mismatches = match optional_query_i64_alias(query, "max_mismatches", "maxMismatches", 0)
    {
        Ok(value) => value.max(0),
        Err(body) => return ("400 Bad Request", body),
    };
    let min_lease_shadow_runs =
        match optional_query_i64_alias(query, "min_lease_shadow_runs", "minLeaseShadowRuns", 1) {
            Ok(value) => value.max(0),
            Err(body) => return ("400 Bad Request", body),
        };
    let max_stale_active =
        match optional_query_i64_alias(query, "max_stale_active", "maxStaleActive", 0) {
            Ok(value) => value.max(0),
            Err(body) => return ("400 Bad Request", body),
        };
    let max_orphaned_leases =
        match optional_query_i64_alias(query, "max_orphaned_leases", "maxOrphanedLeases", 0) {
            Ok(value) => value.max(0),
            Err(body) => return ("400 Bad Request", body),
        };
    let lease_report_limit =
        match optional_query_usize_alias(query, "lease_report_limit", "leaseReportLimit", 20) {
            Ok(value) => value,
            Err(body) => return ("400 Bad Request", body),
        };
    let stale_after_ms =
        match optional_query_u64_alias(query, "stale_after_ms", "staleAfterMs", 300_000) {
            Ok(value) => value,
            Err(body) => return ("400 Bad Request", body),
        };
    let allow_active_runs =
        match optional_query_bool_alias(query, "allow_active_runs", "allowActiveRuns", false) {
            Ok(value) => value,
            Err(body) => return ("400 Bad Request", body),
        };
    let component = query_param(query, "component")
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "scheduler".to_string());
    let run_id_prefix = query_param(query, "run_id_prefix")
        .or_else(|| query_param(query, "runIdPrefix"))
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "node_paid_ai_".to_string());

    match scheduler_bridge::cutover_readiness_json_from_parts(
        config,
        scheduler_bridge::CutoverReadinessParams {
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
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"scheduler_readiness_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn scheduler_command_http_json(
    config: &HubConfig,
    command: &str,
    body: &str,
) -> (&'static str, String) {
    match scheduler_command_http_body(config, command, body) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"scheduler_command_failed\",\"command\":\"{}\",\"message\":\"{}\"}}\n",
                json_escape(command),
                json_escape(&err)
            ),
        ),
    }
}

fn scheduler_command_http_body(
    config: &HubConfig,
    command: &str,
    body: &str,
) -> Result<String, String> {
    let parsed_body = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        serde_json::from_str::<Value>(body)
            .map_err(|err| format!("invalid scheduler request json: {err}"))?
    };
    let args = scheduler_command_args(command, &parsed_body)?;
    scheduler_bridge::dispatch_json(config, &args)
}

fn scheduler_command_args(command: &str, body: &Value) -> Result<Vec<String>, String> {
    let mut args = vec![command.to_string()];
    match command {
        "enqueue" => {
            push_optional_flag(
                &mut args,
                "run-id",
                body_string_alias(body, "run_id", "runId"),
            );
            push_required_flag(
                &mut args,
                "request-id",
                body_string_alias(body, "request_id", "requestId"),
            )?;
            push_required_flag(
                &mut args,
                "scope-key",
                body_string_alias(body, "scope_key", "scopeKey"),
            )?;
            let request_id = body_string_alias(body, "request_id", "requestId").unwrap_or_default();
            let run_id = body_string_alias(body, "run_id", "runId").unwrap_or_default();
            push_value_flag(
                &mut args,
                "idempotency-key",
                body_string_alias(body, "idempotency_key", "idempotencyKey")
                    .unwrap_or_else(|| first_non_empty(&[request_id.as_str(), run_id.as_str()])),
            );
            push_value_flag(
                &mut args,
                "task-type",
                body_string_alias(body, "task_type", "taskType")
                    .unwrap_or_else(|| "paid_ai".to_string()),
            );
            push_payload_flag(&mut args, body)?;
            push_optional_flag(
                &mut args,
                "project-id",
                body_string_alias(body, "project_id", "projectId"),
            );
            push_optional_flag(
                &mut args,
                "device-id",
                body_string_alias(body, "device_id", "deviceId"),
            );
            push_optional_i32_flag(&mut args, "priority", body_i32(body, "priority"));
            push_optional_i64_flag(
                &mut args,
                "not-before-ms",
                body_i64_alias(body, "not_before_ms", "notBeforeMs"),
            );
        }
        "claim" => {
            push_optional_flag(
                &mut args,
                "run-id",
                body_string_alias(body, "run_id", "runId"),
            );
            push_required_flag(
                &mut args,
                "request-id",
                body_string_alias(body, "request_id", "requestId"),
            )?;
            push_required_flag(
                &mut args,
                "scope-key",
                body_string_alias(body, "scope_key", "scopeKey"),
            )?;
            let request_id = body_string_alias(body, "request_id", "requestId").unwrap_or_default();
            let run_id = body_string_alias(body, "run_id", "runId").unwrap_or_default();
            push_value_flag(
                &mut args,
                "idempotency-key",
                body_string_alias(body, "idempotency_key", "idempotencyKey")
                    .unwrap_or_else(|| first_non_empty(&[request_id.as_str(), run_id.as_str()])),
            );
            push_value_flag(
                &mut args,
                "task-type",
                body_string_alias(body, "task_type", "taskType")
                    .unwrap_or_else(|| "paid_ai".to_string()),
            );
            push_required_flag(
                &mut args,
                "lease-owner",
                body_string_alias(body, "lease_owner", "leaseOwner"),
            )?;
            push_value_flag(
                &mut args,
                "lease-duration-ms",
                body_u64_alias(body, "lease_duration_ms", "leaseDurationMs")
                    .unwrap_or(30_000)
                    .to_string(),
            );
            push_payload_flag(&mut args, body)?;
            push_optional_flag(
                &mut args,
                "project-id",
                body_string_alias(body, "project_id", "projectId"),
            );
            push_optional_flag(
                &mut args,
                "device-id",
                body_string_alias(body, "device_id", "deviceId"),
            );
            push_optional_i32_flag(&mut args, "priority", body_i32(body, "priority"));
            push_optional_i64_flag(
                &mut args,
                "not-before-ms",
                body_i64_alias(body, "not_before_ms", "notBeforeMs"),
            );
        }
        "acquire-run" => {
            push_required_flag(
                &mut args,
                "run-id",
                body_string_alias(body, "run_id", "runId"),
            )?;
            push_required_flag(
                &mut args,
                "lease-owner",
                body_string_alias(body, "lease_owner", "leaseOwner"),
            )?;
            push_value_flag(
                &mut args,
                "lease-duration-ms",
                body_u64_alias(body, "lease_duration_ms", "leaseDurationMs")
                    .unwrap_or(30_000)
                    .to_string(),
            );
        }
        "release" => {
            push_required_flag(
                &mut args,
                "run-id",
                body_string_alias(body, "run_id", "runId"),
            )?;
            push_required_flag(
                &mut args,
                "lease-token",
                body_string_alias(body, "lease_token", "leaseToken"),
            )?;
            push_value_flag(
                &mut args,
                "outcome",
                body_string(body, "outcome").unwrap_or_else(|| "completed".to_string()),
            );
            push_optional_flag(
                &mut args,
                "error-code",
                body_string_alias(body, "error_code", "errorCode"),
            );
            push_optional_flag(
                &mut args,
                "error-message",
                body_string_alias(body, "error_message", "errorMessage"),
            );
            push_optional_i64_flag(
                &mut args,
                "not-before-ms",
                body_i64_alias(body, "not_before_ms", "notBeforeMs"),
            );
        }
        "cancel" => {
            push_required_flag(
                &mut args,
                "run-id",
                body_string_alias(body, "run_id", "runId"),
            )?;
            push_value_flag(
                &mut args,
                "reason",
                body_string(body, "reason").unwrap_or_else(|| "canceled".to_string()),
            );
        }
        _ => return Err(format!("unsupported scheduler command: {command}")),
    }
    Ok(args)
}

fn provider_compare_http_json(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> (&'static str, String) {
    match provider_compare_http_body(config, query, body) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"provider_compare_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn provider_compare_http_body(
    config: &HubConfig,
    query: &str,
    body: &str,
) -> Result<String, String> {
    let parsed_body = if body.trim().is_empty() {
        Value::Object(Default::default())
    } else {
        serde_json::from_str::<Value>(body)
            .map_err(|err| format!("invalid compare request json: {err}"))?
    };

    let node_value = if let Some(value) = parsed_body.get("node_decision") {
        value.clone()
    } else if let Some(value) = parsed_body.get("nodeDecision") {
        value.clone()
    } else if let Some(raw) = parsed_body
        .get("node_decision_json")
        .or_else(|| parsed_body.get("nodeDecisionJson"))
        .and_then(Value::as_str)
    {
        serde_json::from_str::<Value>(raw)
            .map_err(|err| format!("invalid node_decision_json: {err}"))?
    } else if let Some(raw) =
        query_param(query, "node_decision_json").or_else(|| query_param(query, "nodeDecisionJson"))
    {
        serde_json::from_str::<Value>(&raw)
            .map_err(|err| format!("invalid node_decision_json: {err}"))?
    } else {
        return Err("provider compare requires node_decision".to_string());
    };

    let runtime_base_dir = body_string(&parsed_body, "runtime_base_dir")
        .or_else(|| body_string(&parsed_body, "runtimeBaseDir"))
        .or_else(|| query_param(query, "runtime_base_dir"))
        .or_else(|| query_param(query, "runtimeBaseDir"))
        .map(PathBuf::from);
    let model_id = body_string(&parsed_body, "model_id")
        .or_else(|| body_string(&parsed_body, "modelId"))
        .or_else(|| query_param(query, "model_id"))
        .or_else(|| query_param(query, "modelId"));
    let provider = body_string(&parsed_body, "provider").or_else(|| query_param(query, "provider"));
    let compare_now_ms = body_u128(&parsed_body, "now_ms")
        .or_else(|| body_u128(&parsed_body, "nowMs"))
        .or_else(|| query_param(query, "now_ms").and_then(|value| value.parse::<u128>().ok()))
        .or_else(|| query_param(query, "nowMs").and_then(|value| value.parse::<u128>().ok()));

    provider_bridge::compare_json_from_parts(
        config,
        runtime_base_dir,
        node_value,
        model_id,
        provider,
        compare_now_ms,
    )
}

fn body_string(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string)
}

fn body_string_list(value: &Value, key: &str) -> Vec<String> {
    match value.get(key) {
        Some(Value::Array(items)) => items
            .iter()
            .filter_map(Value::as_str)
            .flat_map(split_string_list)
            .collect(),
        Some(Value::String(raw)) => split_string_list(raw),
        _ => Vec::new(),
    }
}

fn body_string_alias(value: &Value, key: &str, alias: &str) -> Option<String> {
    body_string(value, key).or_else(|| body_string(value, alias))
}

fn body_bool_alias(value: &Value, key: &str, alias: &str) -> Option<bool> {
    body_bool(value, key).or_else(|| body_bool(value, alias))
}

fn body_bool(value: &Value, key: &str) -> Option<bool> {
    value.get(key).and_then(|item| {
        item.as_bool().or_else(|| {
            let normalized = item.as_str()?.trim().to_ascii_lowercase();
            match normalized.as_str() {
                "1" | "true" | "yes" | "y" | "on" => Some(true),
                "0" | "false" | "no" | "n" | "off" => Some(false),
                _ => None,
            }
        })
    })
}

fn body_i32(value: &Value, key: &str) -> Option<i32> {
    value.get(key).and_then(|item| {
        item.as_i64()
            .and_then(|number| i32::try_from(number).ok())
            .or_else(|| item.as_str().and_then(|raw| raw.trim().parse::<i32>().ok()))
    })
}

fn body_i64_alias(value: &Value, key: &str, alias: &str) -> Option<i64> {
    body_i64(value, key).or_else(|| body_i64(value, alias))
}

fn body_i64(value: &Value, key: &str) -> Option<i64> {
    value.get(key).and_then(|item| {
        item.as_i64()
            .or_else(|| item.as_str().and_then(|raw| raw.trim().parse::<i64>().ok()))
    })
}

fn body_u64_alias(value: &Value, key: &str, alias: &str) -> Option<u64> {
    body_u64(value, key).or_else(|| body_u64(value, alias))
}

fn body_u64(value: &Value, key: &str) -> Option<u64> {
    value.get(key).and_then(|item| {
        item.as_u64()
            .or_else(|| item.as_str().and_then(|raw| raw.trim().parse::<u64>().ok()))
    })
}

fn body_u128(value: &Value, key: &str) -> Option<u128> {
    value.get(key).and_then(Value::as_u64).map(u128::from)
}

fn push_required_flag(
    args: &mut Vec<String>,
    name: &str,
    value: Option<String>,
) -> Result<(), String> {
    let value = value
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| format!("missing required field for --{name}"))?;
    push_value_flag(args, name, value);
    Ok(())
}

fn push_optional_flag(args: &mut Vec<String>, name: &str, value: Option<String>) {
    if let Some(value) = value.filter(|value| !value.trim().is_empty()) {
        push_value_flag(args, name, value);
    }
}

fn push_optional_i32_flag(args: &mut Vec<String>, name: &str, value: Option<i32>) {
    if let Some(value) = value {
        push_value_flag(args, name, value.to_string());
    }
}

fn push_optional_i64_flag(args: &mut Vec<String>, name: &str, value: Option<i64>) {
    if let Some(value) = value {
        push_value_flag(args, name, value.to_string());
    }
}

fn push_payload_flag(args: &mut Vec<String>, body: &Value) -> Result<(), String> {
    let payload = if let Some(raw) = body_string_alias(body, "payload_json", "payloadJson") {
        raw
    } else if let Some(value) = body.get("payload") {
        serde_json::to_string(value).map_err(|err| format!("invalid payload json: {err}"))?
    } else {
        "{}".to_string()
    };
    push_value_flag(args, "payload-json", payload);
    Ok(())
}

fn push_value_flag(args: &mut Vec<String>, name: &str, value: String) {
    args.push(format!("--{name}"));
    args.push(value);
}

fn first_non_empty(values: &[&str]) -> String {
    values
        .iter()
        .map(|value| value.trim())
        .find(|value| !value.is_empty())
        .unwrap_or("")
        .to_string()
}

fn first_non_empty_string(values: Vec<Option<String>>) -> Option<String> {
    values
        .into_iter()
        .flatten()
        .map(|value| value.trim().to_string())
        .find(|value| !value.is_empty())
}

fn first_non_empty_string_list(values: Vec<Vec<String>>) -> Vec<String> {
    values
        .into_iter()
        .find(|items| items.iter().any(|item| !item.trim().is_empty()))
        .unwrap_or_default()
        .into_iter()
        .map(|item| item.trim().to_string())
        .filter(|item| !item.is_empty())
        .collect()
}

fn query_string_list(query: &str, key: &str) -> Vec<String> {
    query_param(query, key)
        .map(|value| split_string_list(&value))
        .unwrap_or_default()
}

fn split_string_list(raw: &str) -> Vec<String> {
    raw.split(',')
        .map(|item| item.trim().to_string())
        .filter(|item| !item.is_empty())
        .collect()
}

fn body_or_query_usize_in_range(
    value: &Value,
    query: &str,
    key: &str,
    alias: &str,
    fallback: usize,
    min: usize,
    max: usize,
) -> usize {
    body_u64_alias(value, key, alias)
        .and_then(|number| usize::try_from(number).ok())
        .or_else(|| {
            body_or_query_string(value, query, key, alias)?
                .trim()
                .parse()
                .ok()
        })
        .unwrap_or(fallback)
        .clamp(min, max)
}

fn body_or_query_i64_in_range(
    value: &Value,
    query: &str,
    key: &str,
    alias: &str,
    fallback: i64,
    min: i64,
    max: i64,
) -> i64 {
    body_i64_alias(value, key, alias)
        .or_else(|| {
            body_or_query_string(value, query, key, alias)?
                .trim()
                .parse()
                .ok()
        })
        .unwrap_or(fallback)
        .clamp(min, max)
}

fn provider_reports_http_json(config: &HubConfig, query: &str) -> (&'static str, String) {
    let limit = match optional_query_usize(query, "limit", 20) {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    match provider_bridge::reports_json_from_parts(config, limit) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"provider_reports_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn provider_readiness_http_json(config: &HubConfig, query: &str) -> (&'static str, String) {
    let limit = match optional_query_usize(query, "limit", 20) {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    let min_compare_reports =
        match optional_query_i64_alias(query, "min_compare_reports", "minCompareReports", 10) {
            Ok(value) => value,
            Err(body) => return ("400 Bad Request", body),
        };
    let max_mismatches = match optional_query_i64_alias(query, "max_mismatches", "maxMismatches", 0)
    {
        Ok(value) => value,
        Err(body) => return ("400 Bad Request", body),
    };
    match provider_bridge::readiness_json_from_parts(
        config,
        min_compare_reports,
        max_mismatches,
        limit,
    ) {
        Ok(body) => ("200 OK", format!("{body}\n")),
        Err(err) => (
            "400 Bad Request",
            format!(
                "{{\"ok\":false,\"error\":\"provider_readiness_failed\",\"message\":\"{}\"}}\n",
                json_escape(&err)
            ),
        ),
    }
}

fn optional_query_i64_alias(
    query: &str,
    key: &str,
    alias: &str,
    fallback: i64,
) -> Result<i64, String> {
    if query_param(query, key).is_some() {
        return optional_query_i64(query, key, fallback);
    }
    optional_query_i64(query, alias, fallback)
}

fn optional_query_usize_alias(
    query: &str,
    key: &str,
    alias: &str,
    fallback: usize,
) -> Result<usize, String> {
    if query_param(query, key).is_some() {
        return optional_query_usize(query, key, fallback);
    }
    optional_query_usize(query, alias, fallback)
}

fn optional_query_u64_alias(
    query: &str,
    key: &str,
    alias: &str,
    fallback: u64,
) -> Result<u64, String> {
    if query_param(query, key).is_some() {
        return optional_query_u64(query, key, fallback);
    }
    optional_query_u64(query, alias, fallback)
}

fn optional_query_u128_alias(query: &str, key: &str, alias: &str) -> Result<Option<u128>, String> {
    if query_param(query, key).is_some() {
        return optional_query_u128(query, key);
    }
    optional_query_u128(query, alias)
}

fn optional_query_bool_alias(
    query: &str,
    key: &str,
    alias: &str,
    fallback: bool,
) -> Result<bool, String> {
    if query_param(query, key).is_some() {
        return optional_query_bool(query, key, fallback);
    }
    optional_query_bool(query, alias, fallback)
}

fn optional_query_u128(query: &str, key: &str) -> Result<Option<u128>, String> {
    match query_param(query, key) {
        Some(value) if !value.trim().is_empty() => {
            value.trim().parse::<u128>().map(Some).map_err(|_| {
                format!(
                    "{{\"ok\":false,\"error\":\"invalid_{}\"}}\n",
                    json_escape(key)
                )
            })
        }
        _ => Ok(None),
    }
}

fn optional_query_usize(query: &str, key: &str, fallback: usize) -> Result<usize, String> {
    match query_param(query, key) {
        Some(value) if !value.trim().is_empty() => value.trim().parse::<usize>().map_err(|_| {
            format!(
                "{{\"ok\":false,\"error\":\"invalid_{}\"}}\n",
                json_escape(key)
            )
        }),
        _ => Ok(fallback),
    }
}

fn optional_query_i64(query: &str, key: &str, fallback: i64) -> Result<i64, String> {
    match query_param(query, key) {
        Some(value) if !value.trim().is_empty() => value.trim().parse::<i64>().map_err(|_| {
            format!(
                "{{\"ok\":false,\"error\":\"invalid_{}\"}}\n",
                json_escape(key)
            )
        }),
        _ => Ok(fallback),
    }
}

fn optional_query_u64(query: &str, key: &str, fallback: u64) -> Result<u64, String> {
    match query_param(query, key) {
        Some(value) if !value.trim().is_empty() => value.trim().parse::<u64>().map_err(|_| {
            format!(
                "{{\"ok\":false,\"error\":\"invalid_{}\"}}\n",
                json_escape(key)
            )
        }),
        _ => Ok(fallback),
    }
}

fn optional_query_bool(query: &str, key: &str, fallback: bool) -> Result<bool, String> {
    match query_param(query, key) {
        Some(value) if !value.trim().is_empty() => {
            let normalized = value.trim().to_ascii_lowercase();
            match normalized.as_str() {
                "1" | "true" | "yes" | "y" | "on" => Ok(true),
                "0" | "false" | "no" | "n" | "off" => Ok(false),
                _ => Err(format!(
                    "{{\"ok\":false,\"error\":\"invalid_{}\"}}\n",
                    json_escape(key)
                )),
            }
        }
        Some(_) => Ok(fallback),
        None => Ok(fallback),
    }
}

fn query_param(query: &str, key: &str) -> Option<String> {
    for pair in query.split('&') {
        if pair.is_empty() {
            continue;
        }
        let (raw_key, raw_value) = pair.split_once('=').unwrap_or((pair, ""));
        if percent_decode_query(raw_key).ok()?.as_str() == key {
            return percent_decode_query(raw_value).ok();
        }
    }
    None
}

fn query_param_list(query: &str, key: &str) -> Option<Vec<String>> {
    query_param(query, key).map(|value| {
        value
            .split(',')
            .map(|item| item.trim().to_string())
            .filter(|item| !item.is_empty())
            .collect()
    })
}

fn percent_decode_query(input: &str) -> Result<String, String> {
    let bytes = input.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        match bytes[index] {
            b'+' => {
                out.push(b' ');
                index += 1;
            }
            b'%' => {
                if index + 2 >= bytes.len() {
                    return Err("truncated percent escape".to_string());
                }
                let hi = hex_value(bytes[index + 1])
                    .ok_or_else(|| "invalid percent escape".to_string())?;
                let lo = hex_value(bytes[index + 2])
                    .ok_or_else(|| "invalid percent escape".to_string())?;
                out.push((hi << 4) | lo);
                index += 3;
            }
            value => {
                out.push(value);
                index += 1;
            }
        }
    }
    String::from_utf8(out).map_err(|err| format!("invalid utf8: {err}"))
}

fn hex_value(value: u8) -> Option<u8> {
    match value {
        b'0'..=b'9' => Some(value - b'0'),
        b'a'..=b'f' => Some(value - b'a' + 10),
        b'A'..=b'F' => Some(value - b'A' + 10),
        _ => None,
    }
}

fn root_body() -> String {
    r#"<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Rust Hub</title>
  <style>
    :root {
      color-scheme: light dark;
      --bg: #f7f7f4;
      --panel: #ffffff;
      --text: #202124;
      --muted: #5f6368;
      --line: #d8d9d2;
      --ok: #16794c;
      --warn: #9a5b00;
      --bad: #b3261e;
      --chip: #eef2f0;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #111315;
        --panel: #1b1d20;
        --text: #f1f3f4;
        --muted: #bdc1c6;
        --line: #34373b;
        --chip: #252a2d;
      }
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: var(--bg);
      color: var(--text);
      font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      line-height: 1.45;
    }
    main {
      width: min(1040px, calc(100vw - 32px));
      margin: 0 auto;
      padding: 28px 0 40px;
    }
    header {
      display: flex;
      justify-content: space-between;
      gap: 16px;
      align-items: flex-start;
      padding-bottom: 20px;
      border-bottom: 1px solid var(--line);
    }
    h1 {
      margin: 0;
      font-size: 28px;
      line-height: 1.15;
      letter-spacing: 0;
    }
    h2 {
      margin: 0 0 12px;
      font-size: 16px;
      letter-spacing: 0;
    }
    p { margin: 6px 0 0; color: var(--muted); }
    a { color: inherit; }
    .status {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 7px 10px;
      border: 1px solid var(--line);
      background: var(--panel);
      border-radius: 8px;
      font-weight: 600;
      white-space: nowrap;
    }
    .dot {
      width: 9px;
      height: 9px;
      border-radius: 999px;
      background: var(--muted);
    }
    .ok .dot { background: var(--ok); }
    .warn .dot { background: var(--warn); }
    .bad .dot { background: var(--bad); }
    .grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 14px;
      margin-top: 18px;
    }
    .panel {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 16px;
      min-width: 0;
    }
    .full { grid-column: 1 / -1; }
    dl {
      margin: 0;
      display: grid;
      grid-template-columns: minmax(120px, 180px) minmax(0, 1fr);
      gap: 8px 12px;
    }
    dt { color: var(--muted); }
    dd {
      margin: 0;
      min-width: 0;
      overflow-wrap: anywhere;
    }
    .checks {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 8px;
    }
    .check {
      border: 1px solid var(--line);
      background: var(--chip);
      border-radius: 8px;
      padding: 9px 10px;
      display: flex;
      justify-content: space-between;
      gap: 10px;
    }
    .check span:last-child { font-weight: 700; }
    .check.good span:last-child { color: var(--ok); }
    .check.fail span:last-child { color: var(--bad); }
    .links {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
    }
    .links a {
      display: inline-flex;
      align-items: center;
      min-height: 34px;
      padding: 7px 10px;
      border: 1px solid var(--line);
      background: var(--chip);
      border-radius: 8px;
      text-decoration: none;
      font-weight: 600;
    }
    pre {
      margin: 0;
      padding: 12px;
      overflow: auto;
      border: 1px solid var(--line);
      background: var(--chip);
      border-radius: 8px;
      max-height: 360px;
      font-size: 12px;
    }
    @media (max-width: 760px) {
      header { display: block; }
      .status { margin-top: 14px; }
      .grid { grid-template-columns: 1fr; }
      dl { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <main>
    <header>
      <div>
        <h1>Rust Hub</h1>
        <p>Local shadow daemon for scheduler, provider, model inventory, and route readiness.</p>
      </div>
      <div id="overall" class="status"><span class="dot"></span><span>Loading</span></div>
    </header>

    <section class="grid">
      <div class="panel">
        <h2>Daemon</h2>
        <dl id="daemon"></dl>
      </div>
      <div class="panel">
        <h2>Runtime</h2>
        <dl id="runtime"></dl>
      </div>
      <div class="panel full">
        <h2>Checks</h2>
        <div id="checks" class="checks"></div>
      </div>
      <div class="panel">
        <h2>API</h2>
        <div class="links">
          <a href="/health">Health JSON</a>
          <a href="/ready">Ready JSON</a>
          <a href="/model/inventory">Model Inventory</a>
          <a href="/model/capabilities">Local Model Capabilities</a>
          <a href="/model/repair-plan">Local Model Repair Plan</a>
          <a href="/model/repair-apply">Local Model Repair Apply</a>
          <a href="/model/repair-jobs">Local Model Repair Jobs</a>
          <a href="/model/route">Model Route</a>
          <a href="/model/diagnostics">Model Diagnostics</a>
          <a href="/xt/hub-contract">XT Hub Contract</a>
          <a href="/network/remote-entry-candidates">Remote Entry Candidates</a>
          <a href="/provider/readiness">Provider Readiness</a>
          <a href="/skills/readiness">Skills Readiness</a>
          <a href="/skills/preflight">Skills Preflight</a>
        </div>
      </div>
      <div class="panel">
        <h2>Bridge Env</h2>
        <pre>export XHUB_RUST_MODEL_INVENTORY_BRIDGE=1
export XHUB_RUST_MODEL_INVENTORY_HTTP_BASE_URL=http://127.0.0.1:50151</pre>
      </div>
      <div class="panel full">
        <h2>Raw Readiness</h2>
        <pre id="raw">Loading...</pre>
      </div>
    </section>
  </main>
  <script>
    const text = (value) => value === undefined || value === null || value === '' ? '-' : String(value);
    const row = (name, value) => `<dt>${name}</dt><dd>${text(value)}</dd>`;
    async function load() {
      const overall = document.getElementById('overall');
      try {
        const response = await fetch('/ready', { headers: { accept: 'application/json' } });
        const ready = await response.json();
        overall.className = ready.ready ? 'status ok' : 'status bad';
        overall.lastElementChild.textContent = ready.ready ? 'Ready' : 'Not ready';
        document.getElementById('daemon').innerHTML = [
          row('Mode', ready.mode),
          row('Version', ready.version),
          row('HTTP', ready.http_addr),
          row('Schema', ready.schema_version),
          row('SQLite', ready.storage && ready.storage.db_path)
        ].join('');
        document.getElementById('runtime').innerHTML = [
          row('Runtime dir', ready.runtime && ready.runtime.runtime_base_dir),
          row('Runtime status', ready.runtime && ready.runtime.runtime_status_file_exists),
          row('Provider store', ready.runtime && ready.runtime.provider_store_file_exists),
          row('Model inventory HTTP', ready.capabilities && ready.capabilities.model_inventory_http),
          row('Local model repair plan HTTP', ready.capabilities && ready.capabilities.model_local_repair_plan_http),
          row('Local model repair apply HTTP', ready.capabilities && ready.capabilities.model_local_repair_apply_http),
          row('Local model repair jobs HTTP', ready.capabilities && ready.capabilities.model_local_repair_jobs_http),
          row('Model diagnostics HTTP', ready.capabilities && ready.capabilities.model_route_diagnostics_http),
          row('Provider route HTTP', ready.capabilities && ready.capabilities.provider_route_http),
          row('Provider import HTTP', ready.capabilities && ready.capabilities.provider_key_import_http),
          row('Provider quota plan HTTP', ready.capabilities && ready.capabilities.provider_openai_quota_plan_http),
          row('Provider quota apply HTTP', ready.capabilities && ready.capabilities.provider_openai_quota_apply_http),
          row('Provider quota failure HTTP', ready.capabilities && ready.capabilities.provider_openai_quota_failure_http),
          row('Provider OAuth apply HTTP', ready.capabilities && ready.capabilities.provider_oauth_refresh_apply_http),
          row('Provider OAuth failure HTTP', ready.capabilities && ready.capabilities.provider_oauth_refresh_failure_http),
          row('Provider Codex OAuth plan HTTP', ready.capabilities && ready.capabilities.provider_oauth_refresh_codex_plan_http),
          row('Provider Codex OAuth HTTP', ready.capabilities && ready.capabilities.provider_oauth_refresh_codex_http),
          row('Skills catalog HTTP', ready.capabilities && ready.capabilities.skills_catalog_http),
          row('Skills preflight HTTP', ready.capabilities && ready.capabilities.skills_preflight_http)
        ].join('');
        document.getElementById('checks').innerHTML = (ready.checks || []).map((item) => {
          const klass = item.ok ? 'check good' : 'check fail';
          return `<div class="${klass}"><span>${text(item.name)}</span><span>${item.ok ? 'OK' : 'FAIL'}</span></div>`;
        }).join('');
        document.getElementById('raw').textContent = JSON.stringify(ready, null, 2);
      } catch (error) {
        overall.className = 'status bad';
        overall.lastElementChild.textContent = 'Unavailable';
        document.getElementById('raw').textContent = String(error && error.message || error);
      }
    }
    load();
  </script>
</body>
</html>
"#
    .to_string()
}

fn health_json(config: &HubConfig) -> String {
    let proto_ok = path_exists(&config.proto_path);
    format!(
        "{{\"schema_version\":\"{}\",\"ok\":true,\"daemon\":\"{}\",\"version\":\"{}\",\"mode\":\"shadow_http\",\"grpc_compat\":\"not_started\",\"http_addr\":\"{}\",\"proto_ok\":{},\"db_path\":\"{}\"}}\n",
        SCHEMA_HEALTH_V1,
        DAEMON_NAME,
        env!("CARGO_PKG_VERSION"),
        json_escape(&config.http_addr()),
        proto_ok,
        json_escape(&config.db_path.display().to_string())
    )
}

fn product_kernel_json(state: &HubState) -> String {
    let readiness_body = readiness_json_cached(state);
    product_kernel_json_from_readiness(&state.config, readiness_body.as_str())
}

fn product_kernel_json_from_readiness(config: &HubConfig, readiness_body: &str) -> String {
    let generated_at_ms = now_ms().min(i64::MAX as u128) as i64;
    let readiness =
        serde_json::from_str::<Value>(readiness_body.trim()).unwrap_or_else(|_| json!({}));
    let public_base_url = value_path_string(&readiness, &["network", "public_base_url"]);
    let public_base_url_ready = value_path_bool(&readiness, &["network", "public_base_url_ready"]);
    let domain_public_endpoint_ready =
        value_path_bool(
            &readiness,
            &["capabilities", "domain_public_endpoint_ready"],
        ) || value_path_bool(&readiness, &["network", "public_endpoint_ready"]);
    let cross_network_ready = value_path_bool(&readiness, &["capabilities", "cross_network_ready"]);
    let xt_file_ipc_surface_ready = value_path_bool(
        &readiness,
        &["capabilities", "xt_file_ipc_production_surface_ready"],
    );
    let xt_file_ipc_authority = xt_file_ipc_production_authority_enabled(xt_file_ipc_surface_ready);
    let local_ml_enabled =
        value_path_bool(&readiness, &["runtime", "ml_execution_authority_enabled"]);
    let local_ml_ready = value_path_bool(&readiness, &["runtime", "ml_execution_in_rust"]);
    let local_ml_authority = local_ml_enabled && local_ml_ready;
    let provider_route_authority = provider_route_production_authority_enabled();
    let model_route_authority = model_route_production_authority_enabled();
    let scheduler_authority = scheduler_production_authority_enabled();
    let memory_writer_authority =
        value_path_bool(&readiness, &["memory", "canonical_writer_in_rust"]);
    let skills_execution_authority =
        value_path_bool(&readiness, &["skills", "execution_authority_in_rust"]);

    let body = json!({
        "schema_version": "xhub.product_kernel.v1",
        "ok": value_path_bool(&readiness, &["ok"]),
        "ready": value_path_bool(&readiness, &["ready"]),
        "generated_at_ms": generated_at_ms,
        "product": {
            "name": "X-Hub",
            "boundary": "rust_product_kernel_swift_shell",
        },
        "kernel": {
            "name": "rust",
            "daemon": DAEMON_NAME,
            "version": value_path_string(&readiness, &["version"]),
            "mode": value_path_string(&readiness, &["mode"]),
            "http_addr": value_path_string(&readiness, &["http_addr"]),
            "http_base_url": format!("http://{}", config.http_addr()),
            "runtime_root": config.root_dir.display().to_string(),
            "runtime_base_dir": value_path_string(&readiness, &["runtime", "runtime_base_dir"]),
        },
        "shell": {
            "name": "swift",
            "role": "product_ui_shell",
            "owns_product_ui": true,
            "embeds_kernel_ui": false,
        },
        "interfaces": {
            "product_kernel_http": true,
            "readiness_http": true,
            "http_base_url": format!("http://{}", config.http_addr()),
            "public_base_url": public_base_url,
        },
        "network": {
            "cross_network_ready": cross_network_ready,
            "domain_public_endpoint_ready": domain_public_endpoint_ready,
            "public_base_url": public_base_url,
            "public_base_url_ready": public_base_url_ready,
            "http_access_key_required": value_path_bool(&readiness, &["network", "http_access_key_required"]),
            "http_access_key_configured": value_path_bool(&readiness, &["network", "http_access_key_configured"]),
        },
        "storage": {
            "db_path": value_path_string(&readiness, &["storage", "db_path"]),
        },
        "authority": {
            "provider_route_in_rust": provider_route_authority,
            "model_route_in_rust": model_route_authority,
            "scheduler_in_rust": scheduler_authority,
            "memory_writer_in_rust": memory_writer_authority,
            "skills_execution_in_rust": skills_execution_authority,
            "xt_file_ipc_in_rust": xt_file_ipc_authority,
            "local_ml_execution_in_rust": local_ml_authority,
            "node_compatibility_layer": true,
            "node_remains_authority": false,
            "swift_shell_owns_ui": true,
            "rust_browser_product_ui": false,
            "ui_product_change": false,
        },
        "readiness": {
            "schema_version": value_path_string(&readiness, &["schema_version"]),
            "ready": value_path_bool(&readiness, &["ready"]),
            "checks": readiness.get("checks").cloned().unwrap_or_else(|| json!([])),
        },
    });
    format!("{body}\n")
}

fn value_path<'a>(value: &'a Value, path: &[&str]) -> Option<&'a Value> {
    let mut current = value;
    for key in path {
        current = current.get(*key)?;
    }
    Some(current)
}

fn value_path_bool(value: &Value, path: &[&str]) -> bool {
    match value_path(value, path) {
        Some(Value::Bool(value)) => *value,
        Some(Value::Number(value)) => value.as_i64().unwrap_or(0) != 0,
        Some(Value::String(value)) => matches!(
            value.trim().to_ascii_lowercase().as_str(),
            "1" | "true" | "yes" | "y" | "on"
        ),
        _ => false,
    }
}

fn value_path_string(value: &Value, path: &[&str]) -> String {
    match value_path(value, path) {
        Some(Value::String(value)) => value.trim().to_string(),
        Some(Value::Number(value)) => value.to_string(),
        Some(Value::Bool(value)) => value.to_string(),
        _ => String::new(),
    }
}

fn enforce_http_bind_policy(config: &HubConfig) -> Result<(), String> {
    if is_loopback_host(&config.host) || env_bool("XHUB_RUST_HUB_ALLOW_LAN", false) {
        return Ok(());
    }
    Err(format!(
        "refusing non-loopback HTTP bind host={} without XHUB_RUST_HUB_ALLOW_LAN=1",
        config.host
    ))
}

fn is_loopback_host(host: &str) -> bool {
    let normalized = host
        .trim()
        .trim_start_matches('[')
        .trim_end_matches(']')
        .to_ascii_lowercase();
    normalized == "localhost" || normalized == "::1" || normalized.starts_with("127.")
}

fn is_wildcard_host(host: &str) -> bool {
    let normalized = host
        .trim()
        .trim_start_matches('[')
        .trim_end_matches(']')
        .to_ascii_lowercase();
    normalized == "0.0.0.0" || normalized == "::" || normalized == "*"
}

fn env_string(key: &str) -> String {
    env::var(key)
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_default()
}

fn env_bool(key: &str, fallback: bool) -> bool {
    match env::var(key) {
        Ok(value) => match value.trim().to_ascii_lowercase().as_str() {
            "1" | "true" | "yes" | "y" | "on" => true,
            "0" | "false" | "no" | "n" | "off" => false,
            _ => fallback,
        },
        Err(_) => fallback,
    }
}

fn env_u128_in_range(key: &str, fallback: u128, min: u128, max: u128) -> u128 {
    env::var(key)
        .ok()
        .and_then(|value| value.trim().parse::<u128>().ok())
        .map(|value| value.clamp(min, max))
        .unwrap_or(fallback.clamp(min, max))
}

fn env_usize_in_range(key: &str, fallback: usize, min: usize, max: usize) -> usize {
    env::var(key)
        .ok()
        .and_then(|value| value.trim().parse::<usize>().ok())
        .map(|value| value.clamp(min, max))
        .unwrap_or(fallback.clamp(min, max))
}

fn env_path_or_default(key: &str, fallback: PathBuf) -> PathBuf {
    env::var(key)
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .unwrap_or(fallback)
}

fn cross_network_public_endpoint_enabled() -> bool {
    env_bool("XHUB_RUST_CROSS_NETWORK_PUBLIC_ENDPOINT", false)
        || env_bool("XHUB_RUST_HUB_PUBLIC_ENDPOINT", false)
}

fn provider_route_production_authority_enabled() -> bool {
    env_bool("XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY", false)
        || env_bool("XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PRODUCTION", false)
        || (env_bool("XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CUTOVER", false)
            && env_bool("XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_APPLY", false))
}

fn model_route_production_authority_enabled() -> bool {
    env_bool("XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY", false)
        || env_bool("XHUB_RUST_MODEL_ROUTE_AUTHORITY_PRODUCTION", false)
        || (env_bool("XHUB_RUST_MODEL_ROUTE_AUTHORITY_CUTOVER", false)
            && env_bool("XHUB_RUST_MODEL_ROUTE_AUTHORITY_APPLY", false))
}

fn scheduler_production_authority_enabled() -> bool {
    env_bool("XHUB_RUST_SCHEDULER_AUTHORITY", false)
}

fn xt_file_ipc_production_authority_enabled(surface_ready: bool) -> bool {
    surface_ready && env_bool("XHUB_RUST_XT_FILE_IPC_PRODUCTION_CUTOVER", false)
}

fn public_base_url_host(public_base_url: &str) -> Option<String> {
    let value = public_base_url.trim();
    let after_scheme = value
        .strip_prefix("https://")
        .or_else(|| value.strip_prefix("http://"))?;
    if after_scheme.is_empty() || after_scheme.contains(char::is_whitespace) {
        return None;
    }
    let authority = after_scheme
        .split(['/', '?', '#'])
        .next()
        .unwrap_or_default()
        .trim();
    if authority.is_empty() || authority.contains('@') {
        return None;
    }
    if let Some(rest) = authority.strip_prefix('[') {
        return rest
            .split(']')
            .next()
            .map(|host| host.trim().to_string())
            .filter(|host| !host.is_empty());
    }
    authority
        .split(':')
        .next()
        .map(|host| host.trim().to_string())
        .filter(|host| !host.is_empty())
}

fn public_base_url_ready(public_base_url: &str) -> bool {
    let value = public_base_url.trim();
    if value.is_empty() || value.to_ascii_lowercase().contains("replace_with") {
        return false;
    }
    if !(value.starts_with("https://") || value.starts_with("http://")) {
        return false;
    }
    let Some(host) = public_base_url_host(value) else {
        return false;
    };
    !is_loopback_host(host.as_str()) && !is_wildcard_host(host.as_str())
}

fn readiness_json_cached(state: &HubState) -> String {
    let ttl_ms = state.readiness_cache_ttl_ms;
    if ttl_ms == 0 {
        return readiness_json(
            &state.config,
            ttl_ms,
            state.http_max_in_flight,
            state.http_read_timeout_ms,
            state.http_write_timeout_ms,
        );
    }

    let now = now_ms();
    if let Ok(cache) = state.readiness_cache.try_lock() {
        if !cache.body.is_empty() && cache.expires_at_ms > now {
            return cache.body.clone();
        }
    }

    let body = readiness_json(
        &state.config,
        ttl_ms,
        state.http_max_in_flight,
        state.http_read_timeout_ms,
        state.http_write_timeout_ms,
    );
    if let Ok(mut cache) = state.readiness_cache.try_lock() {
        cache.expires_at_ms = now_ms().saturating_add(ttl_ms);
        cache.body = body.clone();
    }
    body
}

fn cached_memory_snapshot(state: &HubState, memory_dir: PathBuf) -> MemoryIndexSnapshot {
    let ttl_ms = state.memory_snapshot_cache_ttl_ms;
    if ttl_ms == 0 {
        return memory_bridge::snapshot_from_dir(memory_dir);
    }

    let now = now_ms();
    let mut cache = match state.memory_snapshot_cache.lock() {
        Ok(cache) => cache,
        Err(_) => return memory_bridge::snapshot_from_dir(memory_dir),
    };
    if cache.memory_dir == memory_dir {
        if let Some(snapshot) = cache
            .snapshot
            .as_ref()
            .filter(|_| cache.expires_at_ms > now)
        {
            return snapshot.clone();
        }
    }

    let snapshot = memory_bridge::snapshot_from_dir(memory_dir.clone());
    cache.memory_dir = memory_dir;
    cache.expires_at_ms = now.saturating_add(ttl_ms);
    cache.snapshot = Some(snapshot.clone());
    snapshot
}

fn cached_skills_catalog(state: &HubState, skills_dir: PathBuf) -> SkillCatalog {
    let ttl_ms = state.skills_catalog_cache_ttl_ms;
    if ttl_ms == 0 {
        return scan_skill_catalog(&skills_dir);
    }

    let now = now_ms();
    let mut cache = match state.skills_catalog_cache.lock() {
        Ok(cache) => cache,
        Err(_) => return scan_skill_catalog(&skills_dir),
    };
    if cache.skills_dir == skills_dir {
        if let Some(catalog) = cache.catalog.as_ref().filter(|_| cache.expires_at_ms > now) {
            return catalog.clone();
        }
    }

    let catalog = scan_skill_catalog(&skills_dir);
    cache.skills_dir = skills_dir;
    cache.expires_at_ms = now.saturating_add(ttl_ms);
    cache.catalog = Some(catalog.clone());
    catalog
}

fn readiness_json(
    config: &HubConfig,
    readiness_cache_ttl_ms: u128,
    http_max_in_flight: usize,
    http_read_timeout_ms: u64,
    http_write_timeout_ms: u64,
) -> String {
    let generated_at_ms = now_ms().min(i64::MAX as u128) as i64;
    let proto_ok = path_exists(&config.proto_path);
    let canonical_proto_ok = path_exists(&config.canonical_proto_path);
    let db_parent_ok = config.db_path.parent().map(path_exists).unwrap_or(false);
    let scheduler = SchedulerStore::new(config.db_path.clone(), SchedulerConfig::default());
    let scheduler_status = scheduler.status_view(false, 0);
    let scheduler_ok = scheduler_status.is_ok();
    let runtime_configured = !config.runtime_base_dir.as_os_str().is_empty();
    let runtime_exists = runtime_configured && path_exists(&config.runtime_base_dir);
    let memory_dir = env_path_or_default(
        "XHUB_RUST_MEMORY_DIR",
        config.root_dir.join("data").join("memory"),
    );
    let skills_dir = env_path_or_default("XHUB_RUST_SKILLS_DIR", config.root_dir.join("skills"));
    let memory_dir_exists = path_exists(&memory_dir);
    let skills_catalog = scan_skill_catalog(&skills_dir);
    let skills_dir_exists = skills_catalog.skills_dir_exists;
    let skill_manifest_count = skills_catalog.skill_count();
    let skills_catalog_ok = skills_catalog.ready;
    let xt_file_ipc_production_surface_ready =
        xt_compat::classic_hub_production_surface_ready(config);
    let loopback_bind = is_loopback_host(&config.host);
    let lan_allowed = env_bool("XHUB_RUST_HUB_ALLOW_LAN", false);
    let bind_policy_ok = loopback_bind || lan_allowed;
    let public_base_url = env_string("XHUB_RUST_HUB_PUBLIC_BASE_URL");
    let public_endpoint_enabled = cross_network_public_endpoint_enabled();
    let public_base_url_ready = public_base_url_ready(public_base_url.as_str());
    let http_access_key_configured = config.http_access_key.is_some();
    let http_access_key_required =
        config.http_access_key_required || !loopback_bind || public_endpoint_enabled;
    let http_access_key_ok = !http_access_key_required || http_access_key_configured;
    let network_ok = bind_policy_ok && http_access_key_ok;
    let public_endpoint_ready = public_endpoint_enabled
        && public_base_url_ready
        && http_access_key_required
        && http_access_key_ok;
    let cross_network_ready = network_ok && (!loopback_bind || public_endpoint_ready);
    let memory_plan = RetrievalPlan::project_default();
    let skill_boundary = SkillBoundary::default();
    let memory_writer_authority = memory_bridge::memory_writer_authority_enabled();
    let skills_execution_authority = skills_bridge::skills_execution_authority_enabled();
    let local_ml_readiness = local_ml_bridge::readiness(config);
    let provider_route_authority = provider_route_production_authority_enabled();
    let model_route_authority = model_route_production_authority_enabled();
    let scheduler_authority = scheduler_production_authority_enabled();
    let xt_file_ipc_production_authority =
        xt_file_ipc_production_authority_enabled(xt_file_ipc_production_surface_ready);
    let ready = proto_ok
        && canonical_proto_ok
        && db_parent_ok
        && scheduler_ok
        && network_ok
        && memory_dir_exists
        && skills_catalog_ok
        && (!local_ml_readiness.enabled || local_ml_readiness.ready);
    let scheduler_error = match scheduler_status {
        Ok(_) => String::new(),
        Err(err) => err.to_string(),
    };

    let body = json!({
        "schema_version": "xhub.rust_hub.readiness.v1",
        "ok": true,
        "ready": ready,
        "generated_at_ms": generated_at_ms,
        "daemon": DAEMON_NAME,
        "version": env!("CARGO_PKG_VERSION"),
        "mode": "shadow_http",
        "http_addr": config.http_addr(),
        "performance": {
            "readiness_cache_ttl_ms": readiness_cache_ttl_ms,
            "memory_snapshot_cache_ttl_ms": env_u128_in_range("XHUB_RUST_MEMORY_SNAPSHOT_CACHE_TTL_MS", 500, 0, 10_000),
            "skills_catalog_cache_ttl_ms": env_u128_in_range("XHUB_RUST_SKILLS_CATALOG_CACHE_TTL_MS", 500, 0, 10_000),
            "http_max_in_flight": http_max_in_flight,
            "http_read_timeout_ms": http_read_timeout_ms,
            "http_write_timeout_ms": http_write_timeout_ms,
            "http_slow_ms": env_u128_in_range("XHUB_RUST_HTTP_SLOW_MS", 2_000, 1, 300_000),
            "http_metrics_recent_limit": env_usize_in_range("XHUB_RUST_HTTP_METRICS_RECENT_LIMIT", 256, 0, 10_000),
            "http_io_timeouts": true,
            "http_metrics": true,
            "http_backpressure": true,
            "readiness_cache_scope": "process_memory",
            "read_only_snapshot_cache_scope": "process_memory",
            "stutter_guard": true,
            "blocks_production_authority": false,
        },
        "network": {
            "host": config.host,
            "port": config.http_port,
            "loopback_bind": loopback_bind,
            "cross_network_bind": !loopback_bind,
            "cross_network_public_endpoint": public_endpoint_enabled,
            "public_base_url": public_base_url,
            "public_base_url_ready": public_base_url_ready,
            "public_endpoint_ready": public_endpoint_ready,
            "lan_allowed": lan_allowed,
            "bind_policy_ok": bind_policy_ok,
            "http_access_key_required": http_access_key_required,
            "http_access_key_configured": http_access_key_configured,
            "http_access_key_source": if config.http_access_key_source.is_empty() { "none" } else { config.http_access_key_source.as_str() },
            "ok": network_ok,
            "deny_code": if network_ok {
                ""
            } else if !bind_policy_ok {
                "lan_bind_requires_xhub_rust_hub_allow_lan"
            } else {
                "cross_network_requires_http_access_key"
            },
        },
        "storage": {
            "db_path": config.db_path.display().to_string(),
            "db_parent_ok": db_parent_ok,
            "sqlite_scheduler_view_ok": scheduler_ok,
            "scheduler_error": scheduler_error,
        },
        "contract": {
            "proto_path": config.proto_path.display().to_string(),
            "proto_ok": proto_ok,
            "canonical_proto_path": config.canonical_proto_path.display().to_string(),
            "canonical_proto_ok": canonical_proto_ok,
        },
        "runtime": {
            "runtime_base_dir": display_optional_path(&config.runtime_base_dir),
            "runtime_base_dir_configured": runtime_configured,
            "runtime_base_dir_exists": runtime_exists,
            "runtime_status_file_exists": runtime_exists && path_exists(&config.runtime_base_dir.join("ai_runtime_status.json")),
            "provider_store_file_exists": runtime_exists && path_exists(&config.runtime_base_dir.join("hub_provider_keys.json")),
            "provider_route_http": true,
            "provider_key_pools_http": true,
            "provider_key_runtime_snapshot_http": true,
            "provider_key_import_http": true,
            "provider_openai_quota_plan_http": true,
            "provider_openai_quota_apply_http": true,
            "provider_openai_quota_failure_http": true,
            "provider_oauth_refresh_apply_http": true,
            "provider_oauth_refresh_failure_http": true,
            "provider_oauth_refresh_codex_plan_http": true,
            "provider_oauth_refresh_codex_http": true,
            "account_portfolio_snapshot_in_rust": true,
            "quota_refresh_scheduler_in_rust": true,
            "quota_refresh_state_writer_in_rust": true,
            "provider_route_authority_in_rust": provider_route_authority,
            "model_inventory_http": true,
            "model_local_capabilities_http": true,
            "model_local_repair_plan_http": true,
            "model_local_repair_apply_http": true,
            "model_local_repair_jobs_http": true,
            "model_route_diagnostics_http": true,
            "model_route_authority_in_rust": model_route_authority,
            "local_ml_execution_bridge_http": true,
            "ml_execution_in_rust": local_ml_readiness.ready,
            "ml_execution_authority_enabled": local_ml_readiness.enabled,
            "ml_execution_authority": local_ml_readiness.authority,
            "ml_execution_blocker": local_ml_readiness.blocker,
            "ml_execution_readiness": local_ml_bridge::readiness_value(config),
        },
        "memory": {
            "memory_dir": memory_dir.display().to_string(),
            "memory_dir_exists": memory_dir_exists,
            "mode": memory_plan.mode.as_str(),
            "include_dialogue_window": memory_plan.include_dialogue_window,
            "include_project_capsule": memory_plan.include_project_capsule,
            "include_personal_capsule": memory_plan.include_personal_capsule,
            "fail_closed": memory_plan.fail_closed,
            "authority": if memory_writer_authority { "canonical_writer" } else { "shadow_plan" },
            "canonical_writer_in_rust": memory_writer_authority,
            "retrieval_shadow_http": true,
            "write_http": true,
            "gateway_prepare_http": true,
            "role_transcript_projection_http": true,
            "role_transcript_projection_schema": memory_role_projection::PROJECT_ROLE_TRANSCRIPT_PROJECTION_SCHEMA,
            "role_transcript_projection_authority": "shadow_read_only",
            "gateway_prepare_authority": "prepare_only_no_model_call",
            "write_result_schema": xhub_memory::MEMORY_WRITE_RESULT_SCHEMA,
            "retrieval_result_schema": xhub_memory::MEMORY_RETRIEVAL_RESULT_SCHEMA,
        },
        "skills": {
            "skills_dir": skills_dir.display().to_string(),
            "skills_dir_exists": skills_dir_exists,
            "skill_manifest_count": skill_manifest_count,
            "accepted_skill_count": skills_catalog.accepted_count(),
            "blocked_skill_count": skills_catalog.blocked_count(),
            "issue_count": skills_catalog.issues.len(),
            "authority": if skills_execution_authority { "RustExecutionAuthority".to_string() } else { format!("{:?}", skill_boundary.authority) },
            "hub_executes_third_party_code": skill_boundary.hub_executes_third_party_code,
            "requires_pin_or_grant": skill_boundary.requires_pin_or_grant,
            "execution_policy": if skills_execution_authority { "preflight_policy_execute" } else { "policy_gate_only" },
            "execution_authority_in_rust": skills_execution_authority,
            "catalog_shadow_http": true,
            "preflight_shadow_http": true,
            "execute_http": true,
            "audit_shadow_http": true,
            "policy_revoke_http": true,
            "policy_events_http": true,
            "policy_events_prune_http": true,
            "policy_store_readiness_http": true,
            "catalog_schema": SKILL_CATALOG_SCHEMA,
            "readiness_schema": SKILL_READINESS_SCHEMA,
            "preflight_schema": SKILL_PREFLIGHT_SCHEMA,
            "preflight_audit_schema": SKILL_PREFLIGHT_AUDIT_SCHEMA,
            "preflight_audit_summary_schema": SKILL_PREFLIGHT_AUDIT_SUMMARY_SCHEMA,
            "policy_events_schema": SKILL_POLICY_EVENTS_SCHEMA,
            "policy_events_prune_schema": SKILL_POLICY_EVENTS_PRUNE_SCHEMA,
            "policy_store_readiness_schema": SKILL_POLICY_STORE_READINESS_SCHEMA,
            "ready": skills_catalog_ok,
        },
        "capabilities": {
            "scheduler_status_http": true,
            "scheduler_authority_http_opt_in": true,
            "scheduler_authority_in_rust": scheduler_authority,
            "provider_route_http": true,
            "provider_key_pools_http": true,
            "provider_key_runtime_snapshot_http": true,
            "provider_key_import_http": true,
            "provider_openai_quota_plan_http": true,
            "provider_openai_quota_apply_http": true,
            "provider_openai_quota_failure_http": true,
            "provider_oauth_refresh_apply_http": true,
            "provider_oauth_refresh_failure_http": true,
            "provider_oauth_refresh_codex_plan_http": true,
            "provider_oauth_refresh_codex_http": true,
            "account_portfolio_snapshot_in_rust": true,
            "quota_refresh_scheduler_in_rust": true,
            "quota_refresh_state_writer_in_rust": true,
            "provider_route_authority_in_rust": provider_route_authority,
            "model_inventory_http": true,
            "model_local_capabilities_http": true,
            "model_local_repair_plan_http": true,
            "model_local_repair_apply_http": true,
            "model_local_repair_jobs_http": true,
            "model_route_diagnostics_http": true,
            "model_route_authority_in_rust": model_route_authority,
            "local_ml_execution_bridge_http": true,
            "ml_execution_authority_in_rust": local_ml_readiness.ready,
            "ml_execution_authority_enabled": local_ml_readiness.enabled,
            "http_backpressure": true,
            "http_metrics": true,
            "http_metrics_recent_window": true,
            "http_io_timeouts": true,
            "remote_entry_candidates_http": true,
            "swift_shell_remote_entry_authority": true,
            "memory_retrieval_http": true,
            "memory_write_http": true,
            "memory_gateway_prepare_http": true,
            "memory_role_transcript_projection_http": true,
            "memory_writer_authority_in_rust": memory_writer_authority,
            "xt_classic_hub_compat_preflight_http": true,
            "xt_classic_hub_grpc_probe_http": true,
            "xt_classic_hub_compat_authority": "preflight_only",
            "xt_classic_hub_status_writer_http": true,
            "xt_classic_hub_status_writer_authority": "explicit_cutover_only",
            "xt_file_ipc_runtime_authority_sync_http": true,
            "xt_file_ipc_shadow_responder_http": true,
            "xt_file_ipc_shadow_drain_http": true,
            "xt_file_ipc_shadow_cycle_http": true,
            "xt_file_ipc_shadow_supervise_http": true,
            "xt_file_ipc_shadow_watcher_smoke_http": true,
            "xt_file_ipc_shadow_watcher_rollback_smoke_http": true,
            "xt_file_ipc_shadow_watcher_readiness_http": true,
            "xt_file_ipc_shadow_watcher_start_plan_http": true,
            "xt_file_ipc_shadow_watcher_run_once_http": true,
            "xt_file_ipc_shadow_watcher_session_http": true,
            "xt_file_ipc_shadow_watcher_background_lifecycle_http": true,
            "xt_file_ipc_shadow_runtime_execution_plan_http": true,
            "xt_file_ipc_shadow_runtime_adapter_candidate_http": true,
            "xt_file_ipc_shadow_authority": if xt_file_ipc_production_authority { "production_status_writer" } else { "temp_dir_only_fail_closed" },
            "xt_file_ipc_production_surface_ready": xt_file_ipc_production_surface_ready,
            "xt_file_ipc_production_authority_in_rust": xt_file_ipc_production_authority,
            "xt_classic_hub_status_writer_heartbeat": xt_file_ipc_production_surface_ready,
            "readiness_cache_http": readiness_cache_ttl_ms > 0,
            "memory_snapshot_cache_http": env_u128_in_range("XHUB_RUST_MEMORY_SNAPSHOT_CACHE_TTL_MS", 500, 0, 10_000) > 0,
            "skills_catalog_cache_http": env_u128_in_range("XHUB_RUST_SKILLS_CATALOG_CACHE_TTL_MS", 500, 0, 10_000) > 0,
            "skills_catalog_http": true,
            "skills_preflight_http": true,
            "skills_execute_http": true,
            "skills_execution_authority_in_rust": skills_execution_authority,
            "skills_audit_http": true,
            "skills_policy_revoke_http": true,
            "skills_policy_events_http": true,
            "skills_policy_events_prune_http": true,
            "skills_policy_store_readiness_http": true,
            "cross_network_ready": cross_network_ready,
            "cross_network_public_endpoint": public_endpoint_enabled,
            "domain_public_endpoint_ready": public_endpoint_ready,
            "cross_network_auth_gate": true,
        },
        "checks": [
            {"name": "proto", "ok": proto_ok, "blocking": true},
            {"name": "canonical_proto", "ok": canonical_proto_ok, "blocking": true},
            {"name": "sqlite_parent", "ok": db_parent_ok, "blocking": true},
            {"name": "scheduler_view", "ok": scheduler_ok, "blocking": true},
            {"name": "network_bind_policy", "ok": bind_policy_ok, "blocking": true},
            {"name": "http_access_key", "ok": http_access_key_ok, "blocking": true},
            {"name": "runtime_base_dir", "ok": runtime_exists, "blocking": false},
            {"name": "memory_dir", "ok": memory_dir_exists, "blocking": true},
            {"name": "skills_dir", "ok": skills_dir_exists, "blocking": true},
            {"name": "skills_catalog", "ok": skills_catalog_ok, "blocking": true},
            {"name": "local_ml_execution_authority", "ok": !local_ml_readiness.enabled || local_ml_readiness.ready, "blocking": local_ml_readiness.enabled},
            {"name": "memory_policy", "ok": memory_plan.fail_closed, "blocking": false},
            {"name": "skills_policy", "ok": !skill_boundary.hub_executes_third_party_code, "blocking": false},
        ],
    });
    format!("{body}\n")
}

fn scheduler_status_json() -> String {
    let snapshot = SchedulerSnapshot::shadow_empty();
    format!(
        "{{\"schema_version\":\"{}\",\"source\":\"{}\",\"captured_at_ms\":{},\"in_flight_total\":{},\"queue_depth\":{},\"oldest_queued_ms\":{}}}\n",
        snapshot.schema_version,
        snapshot.source,
        snapshot.captured_at_ms,
        snapshot.in_flight_total,
        snapshot.queue_depth,
        snapshot.oldest_queued_ms
    )
}

fn proto_summary_json(config: &HubConfig) -> String {
    match summarize_proto(&config.proto_path) {
        Ok(summary) => proto_summary_to_json(&summary, true),
        Err(err) => format!(
            "{{\"ok\":false,\"error\":\"{}\",\"path\":\"{}\"}}\n",
            json_escape(&err.to_string()),
            json_escape(&config.proto_path.display().to_string())
        ),
    }
}

fn proto_summary_to_json(summary: &ProtoSummary, ok: bool) -> String {
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

fn print_tool_status(tool: &str) {
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

fn print_proto_status(label: &str, path: &Path) {
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

fn display_optional_path(path: &Path) -> String {
    let text = path.display().to_string();
    if text.is_empty() {
        "(none)".to_string()
    } else {
        text
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_config(access_key: Option<&str>, require_access_key: bool) -> HubConfig {
        let root = PathBuf::from("/tmp/xhubd-test");
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
            http_access_key: access_key.map(str::to_string),
            http_access_key_source: if access_key.is_some() {
                "test".to_string()
            } else {
                String::new()
            },
            http_access_key_required: require_access_key,
        }
    }

    fn request(headers: Vec<(&str, &str)>) -> HttpRequest {
        HttpRequest {
            method: "GET".to_string(),
            path: "/ready".to_string(),
            body: String::new(),
            headers: headers
                .into_iter()
                .map(|(key, value)| (key.to_ascii_lowercase(), value.to_string()))
                .collect(),
        }
    }

    fn test_state(max_in_flight: usize) -> HubState {
        HubState {
            config: test_config(None, false),
            http_in_flight: AtomicUsize::new(0),
            http_max_in_flight: max_in_flight,
            http_slow_ms: 2_000,
            http_read_timeout_ms: 5_000,
            http_write_timeout_ms: 5_000,
            http_metrics_recent_limit: 3,
            http_metrics: Mutex::new(HttpMetrics::default()),
            readiness_cache: Mutex::new(ReadinessCache::default()),
            readiness_cache_ttl_ms: 250,
            memory_snapshot_cache: Mutex::new(MemorySnapshotCache::default()),
            memory_snapshot_cache_ttl_ms: 500,
            skills_catalog_cache: Mutex::new(SkillsCatalogCache::default()),
            skills_catalog_cache_ttl_ms: 500,
        }
    }

    #[test]
    fn readiness_cache_returns_hot_body_without_recompute() {
        let state = test_state(128);
        {
            let mut cache = state.readiness_cache.lock().unwrap();
            cache.body = "{\"cached\":true}\n".to_string();
            cache.expires_at_ms = now_ms().saturating_add(5_000);
        }

        assert_eq!(readiness_json_cached(&state), "{\"cached\":true}\n");
    }

    #[test]
    fn product_kernel_contract_declares_rust_kernel_and_swift_shell() {
        let config = test_config(None, false);
        let readiness = json!({
            "schema_version": "xhub.rust_hub.readiness.v1",
            "ok": true,
            "ready": true,
            "version": "0.1.0",
            "mode": "shadow_http",
            "http_addr": "127.0.0.1:50151",
            "network": {
                "public_base_url": "https://hub.example.com",
                "public_base_url_ready": true,
                "public_endpoint_ready": true,
                "http_access_key_required": true,
                "http_access_key_configured": true
            },
            "storage": {
                "db_path": "/tmp/xhubd-test/data/hub.sqlite3"
            },
            "runtime": {
                "runtime_base_dir": "/tmp/xhubd-test/runtime",
                "ml_execution_in_rust": true,
                "ml_execution_authority_enabled": true
            },
            "memory": {
                "canonical_writer_in_rust": true
            },
            "skills": {
                "execution_authority_in_rust": true
            },
            "capabilities": {
                "cross_network_ready": true,
                "domain_public_endpoint_ready": true,
                "xt_file_ipc_production_surface_ready": true
            },
            "checks": [{"name": "proto", "ok": true, "blocking": true}]
        })
        .to_string();

        let body = product_kernel_json_from_readiness(&config, readiness.as_str());
        let value: Value = serde_json::from_str(&body).expect("product kernel json should parse");

        assert_eq!(value["schema_version"], "xhub.product_kernel.v1");
        assert_eq!(value["product"]["name"], "X-Hub");
        assert_eq!(
            value["product"]["boundary"],
            "rust_product_kernel_swift_shell"
        );
        assert_eq!(value["kernel"]["name"], "rust");
        assert_eq!(value["shell"]["name"], "swift");
        assert_eq!(value["authority"]["memory_writer_in_rust"], true);
        assert_eq!(value["authority"]["skills_execution_in_rust"], true);
        assert_eq!(value["authority"]["local_ml_execution_in_rust"], true);
        assert_eq!(value["authority"]["node_compatibility_layer"], true);
        assert_eq!(value["authority"]["node_remains_authority"], false);
        assert_eq!(value["authority"]["swift_shell_owns_ui"], true);
        assert_eq!(value["authority"]["rust_browser_product_ui"], false);
        assert_eq!(value["network"]["cross_network_ready"], true);
        assert_eq!(value["network"]["domain_public_endpoint_ready"], true);
    }

    #[test]
    fn loopback_request_does_not_require_access_key_by_default() {
        let config = test_config(None, false);
        let peer = "127.0.0.1:49152".parse::<SocketAddr>().unwrap();
        assert!(http_access_key_failure(&request(vec![]), &config, Some(peer), "/ready").is_none());
    }

    #[test]
    fn non_loopback_request_requires_configured_access_key() {
        let config = test_config(None, false);
        let peer = "198.51.100.10:49152".parse::<SocketAddr>().unwrap();
        let failure = http_access_key_failure(&request(vec![]), &config, Some(peer), "/ready")
            .expect("remote request should be blocked");
        assert_eq!(failure.0, "403 Forbidden");
        assert!(failure.1.contains("access_key_not_configured"));
    }

    #[test]
    fn non_loopback_request_accepts_bearer_access_key() {
        let config = test_config(Some("secret-123"), false);
        let peer = "198.51.100.10:49152".parse::<SocketAddr>().unwrap();
        let request = request(vec![("authorization", "BEARER secret-123")]);
        assert!(http_access_key_failure(&request, &config, Some(peer), "/ready").is_none());
    }

    #[test]
    fn explicit_require_access_key_blocks_loopback_without_key() {
        let config = test_config(Some("secret-123"), true);
        let peer = "127.0.0.1:49152".parse::<SocketAddr>().unwrap();
        let failure = http_access_key_failure(&request(vec![]), &config, Some(peer), "/ready")
            .expect("explicit local auth should be enforced");
        assert_eq!(failure.0, "401 Unauthorized");
        assert!(failure.1.contains("missing_access_key"));
    }

    #[test]
    fn public_endpoint_blocks_loopback_ready_without_key() {
        let config = test_config(Some("secret-123"), false);
        let peer = "127.0.0.1:49152".parse::<SocketAddr>().unwrap();
        let failure = http_access_key_failure_with_public_endpoint(
            &request(vec![]),
            &config,
            Some(peer),
            "/ready",
            true,
        )
        .expect("public endpoint auth should apply before loopback exemption");
        assert_eq!(failure.0, "401 Unauthorized");
        assert!(failure.1.contains("missing_access_key"));
    }

    #[test]
    fn public_endpoint_accepts_loopback_bearer_access_key() {
        let config = test_config(Some("secret-123"), false);
        let peer = "127.0.0.1:49152".parse::<SocketAddr>().unwrap();
        let request = request(vec![("authorization", "Bearer secret-123")]);
        assert!(http_access_key_failure_with_public_endpoint(
            &request,
            &config,
            Some(peer),
            "/ready",
            true,
        )
        .is_none());
    }

    #[test]
    fn public_endpoint_accepts_loopback_header_access_key() {
        let config = test_config(Some("secret-123"), false);
        let peer = "127.0.0.1:49152".parse::<SocketAddr>().unwrap();
        let request = request(vec![("x-xhub-access-key", "secret-123")]);
        assert!(http_access_key_failure_with_public_endpoint(
            &request,
            &config,
            Some(peer),
            "/ready",
            true,
        )
        .is_none());
    }

    #[test]
    fn public_endpoint_keeps_health_unauthenticated_on_loopback() {
        let config = test_config(Some("secret-123"), false);
        let peer = "127.0.0.1:49152".parse::<SocketAddr>().unwrap();
        assert!(http_access_key_failure_with_public_endpoint(
            &request(vec![]),
            &config,
            Some(peer),
            "/health",
            true,
        )
        .is_none());
    }

    #[test]
    fn health_check_stays_unauthenticated_for_launchd_and_local_probes() {
        let config = test_config(Some("secret-123"), true);
        let peer = "198.51.100.10:49152".parse::<SocketAddr>().unwrap();
        assert!(
            http_access_key_failure(&request(vec![]), &config, Some(peer), "/health").is_none()
        );
    }

    #[test]
    fn public_base_url_readiness_rejects_loopback_and_placeholders() {
        assert!(!public_base_url_ready(""));
        assert!(!public_base_url_ready("https://replace_with_domain"));
        assert!(!public_base_url_ready("http://127.0.0.1:50151"));
        assert!(!public_base_url_ready("https://localhost"));
        assert!(!public_base_url_ready("https://0.0.0.0:50151"));
    }

    #[test]
    fn public_base_url_readiness_accepts_domain_and_lan_hosts() {
        assert!(public_base_url_ready("https://hub.example.com"));
        assert!(public_base_url_ready("https://hub.example.com/xhub"));
        assert!(public_base_url_ready("http://192.168.1.20:50151"));
    }

    #[test]
    fn http_backpressure_exempts_health_and_releases_slots() {
        let state = test_state(1);
        match acquire_http_inflight_slot(&state, "/health") {
            Ok(None) => {}
            _ => panic!("health should not consume an in-flight slot"),
        }

        let first = match acquire_http_inflight_slot(&state, "/ready") {
            Ok(Some(guard)) => guard,
            _ => panic!("first business request should acquire a slot"),
        };
        match acquire_http_inflight_slot(&state, "/ready") {
            Err(body) => {
                assert!(body.contains("http_backpressure"));
                assert!(body.contains("\"max_in_flight\":1"));
            }
            _ => panic!("second business request should be backpressured"),
        }

        drop(first);
        match acquire_http_inflight_slot(&state, "/ready") {
            Ok(Some(_guard)) => {}
            _ => panic!("slot should be released after guard drop"),
        };
    }

    #[test]
    fn http_metrics_records_route_without_detail_payloads() {
        let state = test_state(2);
        record_http_route_metrics(&state, "/memory/search", "200 OK", 7);
        record_http_route_metrics(&state, "/memory/search", "200 OK", state.http_slow_ms);
        let (_status, body) = http_metrics_json(&state);
        assert!(body.contains("xhub.rust_hub.http_metrics.v1"));
        assert!(body.contains("\"route\":\"/memory/search\""));
        assert!(body.contains("\"total_requests\":2"));
        assert!(body.contains("\"slow_requests\":1"));
        assert!(body.contains("\"recent_slow_requests\":1"));
        assert!(body.contains("\"recent_sample_capacity\":3"));
        assert!(body.contains("\"recent_samples_newest_first\""));
        assert!(body.contains("\"detail_json_included\":false"));
        assert!(!body.contains("api_key"));
    }

    #[test]
    fn http_metrics_recent_window_is_bounded_and_query_sanitized() {
        let state = test_state(2);
        record_http_route_metrics(&state, "/ready", "200 OK", 1);
        record_http_route_metrics(&state, "/memory/search?api_key=sk-secret", "200 OK", 2);
        record_http_route_metrics(&state, "/skills/readiness#token=secret", "200 OK", 3);
        record_http_route_metrics(&state, "/model/route", "200 OK", state.http_slow_ms);
        let (_status, body) = http_metrics_json(&state);
        assert!(body.contains("\"recent_sample_count\":3"));
        assert!(body.contains("\"recent_dropped_samples\":1"));
        assert!(body.contains("\"recent_slow_requests\":1"));
        assert!(body.contains("\"route\":\"/memory/search\""));
        assert!(body.contains("\"route\":\"/skills/readiness\""));
        assert!(body.contains("\"route\":\"/model/route\""));
        let parsed: Value = serde_json::from_str(&body).expect("metrics json should parse");
        let recent_routes = parsed["recent_samples_newest_first"]
            .as_array()
            .expect("recent samples should be an array")
            .iter()
            .map(|sample| sample["route"].as_str().unwrap_or(""))
            .collect::<Vec<_>>();
        assert!(!recent_routes.contains(&"/ready"));
        assert!(!body.contains("sk-secret"));
        assert!(!body.contains("api_key"));
        assert!(!body.contains("token=secret"));
    }

    #[test]
    fn route_evidence_is_opt_in_and_appends_evidence_id() {
        let mut config = test_config(None, false);
        let db_path = std::env::temp_dir().join(format!(
            "xhub_route_evidence_{}_{}.sqlite3",
            std::process::id(),
            now_ms()
        ));
        config.db_path = db_path.clone();
        let response_body = json!({
            "schema_version": "xhub.model_route_decision.v1",
            "ok": true,
            "command": "route",
            "updated_at_ms": 1000,
            "request": {"task_type":"summarize","model_id":"auto"},
            "selected_route_kind": "local",
            "selected_model_id": "local.summary",
            "blocking_reason_code": "",
            "selected": {"route_kind":"local","model_id":"local.summary"}
        })
        .to_string();

        let without_evidence = maybe_attach_route_evidence(
            &config,
            "",
            &Value::Null,
            "model_route",
            response_body.clone(),
        )
        .expect("route without evidence should pass through");
        let without_value: Value = serde_json::from_str(&without_evidence).expect("json");
        assert!(without_value.get("evidence_id").is_none());

        let with_evidence = maybe_attach_route_evidence(
            &config,
            "write_evidence=true&project_id=project-a&run_id=run-a",
            &Value::Null,
            "model_route",
            response_body,
        )
        .expect("route evidence should write");
        let with_value: Value = serde_json::from_str(&with_evidence).expect("json");
        assert!(with_value["evidence_id"]
            .as_str()
            .unwrap_or("")
            .starts_with("ev_model_route_"));
        assert_eq!(with_value["evidence"]["output_verdict"], "allow");
        assert_eq!(with_value["evidence"]["project_id"], "project-a");
        assert_eq!(with_value["evidence"]["run_id"], "run-a");
        assert_eq!(with_value["evidence"]["reason_codes"][0], "route_ready");

        let _ = std::fs::remove_file(db_path);
    }

    #[test]
    fn http_io_timeouts_are_applied_to_streams() {
        let state = test_state(2);
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind loopback test listener");
        let addr = listener.local_addr().expect("read listener address");
        let client = TcpStream::connect(addr).expect("connect test client");
        let (server, _) = listener.accept().expect("accept test stream");

        apply_http_io_timeouts(&server, &state).expect("apply http io timeouts");

        assert_eq!(
            server.read_timeout().expect("read timeout"),
            Some(Duration::from_millis(5_000))
        );
        assert_eq!(
            server.write_timeout().expect("write timeout"),
            Some(Duration::from_millis(5_000))
        );
        drop(client);
    }
}
