# Rust Hub

This directory contains the Rust rewrite of X-Hub core. It is intentionally
independent from the existing Node Hub so it can run side-by-side during the
migration.

Current slice:

- Workspace scaffold.
- Mirrored proto contract.
- `xhubd doctor`.
- `xhubd migrate`.
- `xhubd serve` shadow HTTP endpoints.
- `xhubd serve` browser status page at `/`.
- `xhubd serve` short-TTL `/ready` cache for high-frequency UI/bridge polling.
- `xhubd serve` nonblocking `/ready` cache refresh with a 5 second default TTL
  for post-cutover stutter reduction under live polling.
- `xhubd serve` explicit-cutover XT live status repair that writes stale or
  missing Rust-owned `hub_status.json` evidence back to disk instead of serving
  a fresh memory-only overlay.
- `xhubd serve` short-TTL memory snapshot and skills catalog caches for
  read-only HTTP paths.
- `xhubd serve` read-only role-aware project transcript projection over Hub
  SQLite turns for XT Supervisor/Coder/Reviewer continuity.
- `xhubd serve` Memory Gateway model-call execution gate at
  `/memory/gateway/model-call-execution-gate`: a non-executing Rust admission
  surface that proves execute intent remains blocked, redacts prompt/context
  text, and keeps provider/model execution untouched until a later explicit
  authority cutover.
- `xhubd serve` global HTTP in-flight backpressure guard for business routes.
- `xhubd serve` bounded HTTP socket read/write timeouts for slow or half-open
  client connections.
- `xhubd serve` route-level HTTP latency metrics and bounded recent-window
  stutter diagnostics for slow-request diagnosis.
- `tools/ops_soak_runner.command` long-running warm-daemon soak runner for
  stutter, cache, latency, HTTP metrics, memory, skills, and UI compatibility
  regression evidence.
- `tools/production_live_stability_session.command --adopt` can attach the
  current package's state to a long stability session discovered in an older
  package root, avoiding duplicate sessions during post-cutover updates.
- `tools/production_live_stability_session.command --adopt-checkpoint-loop`
  does the same for the rolling checkpoint sidecar.
- `tools/daemon_ops_report.command` non-mutating daemon ops report for
  health/readiness/launchd/http-metrics/redacted-log evidence. It can
  optionally include isolated XT file IPC run-once smoke evidence with
  `--xt-file-ipc-run-once-smoke`.
- `tools/daemon_maintenance.command` dry-run-by-default log/report retention
  maintenance for long-running daemon installs.
- `tools/daemon_ops_gate.command` daily/manual daemon ops gate combining
  readiness, HTTP metrics, maintenance dry-run, logs, and UI/authority checks.
  It can optionally run isolated XT file IPC run-once smoke evidence with
  `--xt-file-ipc-run-once-smoke`.
- `tools/production_live_stability_gate.command` post-cutover live stability
  gate combining XT heartbeat soak, daemon ops gate, production runtime guard,
  UI compatibility, and process sanity checks for 2 minute, 8 hour, or 24 hour
  validation without changing authority.
- `tools/production_live_stability_session.command` detached post-cutover live
  stability session runner for starting, checking, and stopping 8 hour or
  24 hour validation without blocking a shell, plus a rolling checkpoint
  sidecar for short RHM-112 slow-delta checkpoints during a long session,
  including next-checkpoint ETA, stop-safe incomplete status, and
  baseline-aware handling of pre-existing recent slow samples.
- `tools/daemon_watchdog.command` long-running daemon watchdog report for
  launchd, pid-file, readiness, stutter-guard, maintenance, and authority
  drift checks, with optional explicit stale-pid repair only.
- `xhubd_daemon.command watchdog-plist|watchdog-install|watchdog-status|watchdog-uninstall`
  user LaunchAgent timer support for periodic dry-run watchdog reports.
- `tools/cross_network_readiness_gate.command` LAN/cross-device readiness gate
  for access-key, public host, launchd, watchdog timer, UI, and authority
  boundary evidence before exposing Hub beyond localhost.
- `tools/cross_network_installed_gate.command` strict installed-state LAN gate
  requiring live readiness, daemon LaunchAgent, and watchdog timer LaunchAgent.
- `tools/cross_network_install_plan.command` non-mutating LAN daemon/watchdog
  install, validation, and rollback command plan.
- `xhubd serve` XT classic Hub compatibility preflight endpoint for the
  `hub_status.json` / `hubInteractive` contract, including a guarded gRPC
  compatibility probe and explicit-cutover status writer gate, without writing
  status files by default or changing production authority.
- `xhubd serve` XT file IPC shadow responder endpoint for temporary-dir
  `ai_requests` / `ai_responses` contract validation. It writes only
  fail-closed JSONL responses when explicitly enabled, supports bounded manual
  drain of temporary request directories, records Rust-owned manual processor
  cycle status, exposes a bounded synchronous shadow supervisor loop, supports
  lock/status watcher lifecycle and rollback smokes, exposes a read-only
  watcher readiness gate, start plan, one-shot watcher run, bounded watcher
  session, a default-off bounded background watcher lifecycle, runtime
  execution plans, and a fail-closed runtime adapter candidate, and does not
  make Rust the XT production IPC authority.
- `xhubd serve-grpc` with `HubRuntime.GetSchedulerStatus`.
- `xhubd scheduler ...` JSON bridge commands for Node/shadow integration.
- `xhubd provider route` JSON provider-routing shadow decision CLI.
- `xhubd model inventory` JSON remote/local model inventory CLI.
- `xhubd model route` JSON unified remote/local model route decision CLI.
- `xhubd model compare`, `model reports`, and `model readiness` inventory
  parity evidence CLI.
- `xhubd skills catalog`, `skills readiness`, `skills pin/grant/policy`,
  `skills policy-events`, `skills policy-events-prune`,
  `skills policy-readiness`, `skills preflight`, `skills audit`, and
  `skills audit-prune` policy-gate CLI.
- `xhubd skills preflight` emits Hub-authoritative XT-local skill
  preauthorization metadata: resolved pinned low/medium-risk skills with all
  required capability grants and no manifest `requires_grant` flag receive a
  short TTL `xhub.skills.preauthorized_lease.v1`; unpinned, missing-grant,
  high-risk, revoked, blocked, or grant-required skills stay pending/denied and
  cannot become XT-local durable authority.
- `xhubd serve` HTTP endpoints for Rust model inventory, compare reports, and
  readiness gates.
- `xhubd serve` HTTP `GET/POST /model/route` for read-only model route
  decisions.
- `xhubd serve` HTTP `/skills/*` endpoints for catalog, readiness, durable
  pin/grant policy, preflight, audit summary, store readiness, and explicit
  audit pruning.
- `xhubd scheduler claim` atomic enqueue-and-fair-lease primitive for the
  future authority switch.
- `tools/node_scheduler_shadow_compare.js` Node-side shadow caller prototype.
- `tools/node_hub_shadow_compare_smoke.js` one-shot Node Hub shadow-compare
  smoke.
- `tools/node_hub_shadow_compare_runner.js` live Node Hub shadow-compare
  runner/monitor.
- `tools/scheduler_cutover_readiness_runner.js` automated evidence collection
  and readiness runner.
- `tools/scheduler_authority_runner.js` full Node `HubAI.Generate` paid-path
  smoke through Rust scheduler authority, using an isolated fake Bridge.
- `tools/scheduler_production_authority_plan.js` scheduler-only production
  authority cutover plan with validation commands and rollback env output.
- `tools/scheduler_production_authority_apply.js` explicit Dock Agent
  LaunchAgent env apply/rollback for scheduler production authority.
- `tools/scheduler_production_authority_session.js` single-app X-Hub
  launchctl session env apply/rollback for scheduler production authority.
- `tools/scheduler_production_authority_session_launchd.js` reversible
  LaunchAgent that reapplies single-app scheduler authority env at login.
- `tools/scheduler_production_authority_guard.js` one-shot guard that verifies
  scheduler authority is effective, persistent, daemon-ready, and UI-safe.
- `tools/route_authority_cutover_guard.js` non-mutating provider/model route
  authority readiness gate before any manual prep trial.
- `tools/route_authority_prep_session.js` provider/model route prep session
  env apply/rollback, still production-authority-off.
- `tools/route_authority_prep_runtime_guard.js` checks whether the running
  X-Hub Node process has inherited the prep/candidate env.
- `tools/route_authority_prep_sustained_guard.js` repeated live prep runtime,
  route readiness, scheduler authority, and daemon slow-request guard.
- `tools/route_authority_prep_session_launchd.js` reversible LaunchAgent that
  reapplies provider/model route prep env at login.
- `tools/route_authority_production_cutover_blocker.js` machine-readable
  blocker report for provider/model production authority cutover, with an
  explicit production switch contract that keeps prep/candidate keys separate
  from real production authority keys.
- `tools/route_authority_production_session.js` explicit provider/model route
  production env apply/rollback tool. It manages only provider/model route
  production keys and keeps memory, skills, XT file IPC, and UI authority
  unchanged.
- `tools/route_authority_production_runtime_guard.js` verifies that launchctl
  and the running X-Hub Node process actually inherited provider/model
  production authority env, with fail-closed checks for scheduler authority,
  provider/model fallback policy, and unrelated memory writer / skills
  execution production keys. XT file IPC production keys are reported but not
  blocking by default because that surface is governed by its own cutover gate.
- `tools/xt_file_ipc_production_session.js` explicit XT file IPC production
  env apply/rollback tool. It requires `--live-base-dir` and
  `--confirm-live-cutover`, rejects temp directories, and keeps memory, skills,
  provider/model route, and UI authority unchanged.
- `tools/xt_file_ipc_production_cutover_blocker.js` read-only XT file IPC live
  cutover blocker report. It checks daemon health/readiness, classic compat,
  prep/production env state, live-base-dir validity, and UI compatibility
  before any live writer apply.
- `tools/xt_file_ipc_production_rollback_rehearsal.js` non-live apply/rollback
  rehearsal for XT file IPC production session keys. It uses a Rust-Hub-owned
  non-temp rehearsal base dir, does not restart the daemon, does not call
  write-status, and fails if env is not restored.
- `tools/xt_file_ipc_live_cutover_preflight.js` final live cutover preflight.
  It snapshots the live `hub_status.json` path, validates blocker/rehearsal
  evidence, and emits apply, daemon relaunch, write-status smoke, and rollback
  plans without executing them.
- `tools/active_root_upgrade_plan.js` non-mutating update plan that compares
  the current launchctl/Node `XHUB_RUST_HUB_ROOT` with a source or package
  target root, detects existing provider/model production authority, and prints
  apply, validation, and rollback commands without downgrading production route
  env back to prep.
- `tools/active_root_upgrade_apply.js` dry-run-by-default active-root upgrade
  orchestrator with explicit `--apply`, `--relaunch-xhub`, and `--validate`
  gates for smoother package updates. When provider/model production authority
  is already active it skips route prep apply/install and validates with the
  production runtime guard instead.
- `tools/node_hub_authority_live_runner.js` real Node Hub process + gRPC
  `HubAI.Generate` authority smoke with shared Node/Rust SQLite state.
- `tools/provider_route_smoke.command` source/package smoke for Rust provider
  route decisions.
- `tools/provider_route_shadow_compare_smoke.js` real Node service handler +
  Rust provider route shadow compare smoke.
- `tools/model_inventory_shadow_compare_smoke.js` fixture-backed Rust model
  inventory shadow compare smoke.
- `tools/model_inventory_http_bridge_smoke.js` Rust model inventory HTTP
  endpoint and readiness-gate smoke.
- `tools/model_inventory_shadow_compare_runner.js` sustained Node/XT-shaped
  model inventory shadow evidence runner, including existing-runtime and
  warm-daemon modes.
- `tools/model_route_http_smoke.js` read-only Rust model route HTTP smoke.
- `tools/model_route_generate_candidate_runner.js` sustained Node
  `HubAI.Generate` model-route candidate evidence runner.
- `tools/model_route_local_candidate_runner.js` local runtime
  `HubAI.Generate` model-route candidate evidence runner.
- `tools/model_route_candidate_evidence_runner.js` combined remote/local
  persisted model-route candidate evidence runner.
- `tools/model_route_authority_plan_runner.js` default-off selected-model
  authority dry-run plan generator.
- `tools/model_route_prep_trial_runner.js` default-off selected-model prep
  trial smoke/report runner.
- `tools/provider_route_shadow_compare_runner.js` sustained provider route
  shadow compare evidence runner.
- `tools/provider_route_generate_observe_runner.js` paid Generate hot-path
  observe and candidate-audit runner.
- `tools/provider_route_cutover_readiness_runner.js` combined provider route
  cutover readiness runner.
- `tools/provider_route_authority_plan_runner.js` default-off provider route
  authority dry-run plan generator.
- `docs/MODEL_MANAGEMENT_EXECUTION_PLAN.md` Rust-specific execution plan for
  remote paid model management, local model inventory/preflight, unified model
  route decisions, and XT parity gates.
- `docs/RHM_015_UI_COMPATIBILITY_PRESERVATION.md` contract that keeps XT as the
  product UI while Rust replaces backend truth sources behind default-off
  bridges.
- `tools/ui_compatibility_no_product_ui_change_gate.command` static package
  gate that verifies Rust Hub remains backend/diagnostics only and does not
  embed SwiftUI product UI files.
- `tools/ops_readiness_gate.command` warm-daemon operational readiness gate for
  repeated `/ready`, memory retrieval, skills readiness, skill policy store
  readiness, latency-budget, readiness-cache, and UI compatibility checks.
- `tools/ops_soak_runner.command` sustained warm-daemon soak runner that
  writes `xhub.rust_hub.ops_soak_report.v1` reports without changing Node/XT
  authority or product UI.
- `tools/daemon_ops_report.command` non-mutating operational report that
  persists `xhub.rust_hub.daemon_ops_report.v1` evidence for long-running
  launchd/manual daemons.
- `tools/daemon_maintenance.command` bounded log/report retention command that
  writes `xhub.rust_hub.daemon_maintenance_report.v1` and only mutates files
  when `--apply` is passed.
- `tools/daemon_ops_gate.command` daily/manual operational gate that writes
  `xhub.rust_hub.daemon_ops_gate.v1` and fails on readiness, metrics,
  slow-request, UI, authority, or secret-leak regressions.
- `tools/daemon_watchdog.command` long-running operational watchdog that writes
  `xhub.rust_hub.daemon_watchdog_report.v1` and can remove stale/invalid pid
  files only when `--apply --repair-stale-pid` is explicitly passed.
- `tools/skills_catalog_shadow_smoke.command` and
  `tools/skills_catalog_http_smoke.command` policy/readiness smokes that prove
  Rust does not execute third-party skill code or leak secret manifest content.
- `tools/xt_file_ipc_watcher_run_once_smoke.command` isolated XT file IPC
  one-shot watcher smoke that validates lock/status/response evidence without
  touching XT live directories or changing production authority. It can persist
  the JSON evidence with `--report-file`.
- `tools/xt_file_ipc_background_watcher_smoke.command` isolated XT file IPC
  background watcher lifecycle smoke that validates start/status/stop evidence
  without touching XT live directories or changing production authority.
  `tools/daemon_ops_report.command` and `tools/daemon_ops_gate.command` can
  include this evidence with `--xt-file-ipc-background-watcher-smoke`.
- `tools/xt_file_ipc_runtime_execution_plan_smoke.command` isolated XT file IPC
  runtime execution plan smoke that validates model-route adapter selection
  without writing responses, executing ML, or changing production authority.
- `tools/xt_file_ipc_runtime_adapter_candidate_smoke.command` isolated XT file
  IPC runtime adapter candidate smoke that writes only fail-closed response
  JSONL in a temporary directory, covers cancel-file handling and existing
  response collision protection, blocks explicit overwrite attempts without a
  separate overwrite env gate, rejects unsupported request types, blocks missing
  selected-model routes, oversized prompts, oversized request files, and
  malformed request JSON before any write, and does not execute ML or change
  production authority.
- `tools/xt_file_ipc_prep_session.command` default-off XT file IPC prep session
  env apply/rollback. It enables only shadow/watcher/runtime-adapter prep gates
  and intentionally leaves live base-dir and production cutover env unset.
- `tools/xt_file_ipc_production_session.command` explicit XT file IPC
  production env apply/rollback tool. It requires a non-temp live base dir and
  `--confirm-live-cutover`, manages only file-IPC/classic-compat cutover gates,
  and keeps memory, skills, provider/model routing, and UI authority unchanged.
- `tools/xt_file_ipc_production_cutover_blocker.command` read-only blocker
  report for XT file IPC live cutover. It does not apply env and does not call
  the guarded write-status endpoint.
- `tools/xt_file_ipc_production_rollback_rehearsal.command` non-live
  apply/rollback rehearsal for the XT file IPC production session.
- `tools/xt_file_ipc_live_cutover_preflight.command` final write-before
  snapshot and command plan for the XT file IPC live cutover.
- `docs/RHM_016_MODEL_ROUTE_AUTHORITY_PREP_BRIDGE.md` default-off Node bridge
  contract for Rust model-route candidate evidence.
- `docs/RHM_017_MODEL_ROUTE_CANDIDATE_EVIDENCE_RUNNER.md` runner contract for
  sustained model-route candidate audit readiness.
- `docs/RHM_018_LOCAL_MODEL_ROUTE_CANDIDATE_COVERAGE.md` runner contract for
  local runtime model-route candidate readiness.
- `docs/RHM_019_SKILLS_CATALOG_POLICY_GATE.md` read-only Rust skill catalog and
  readiness policy gate contract.
- `docs/RHM_021_SKILLS_PREFLIGHT_GRANT_AUDIT.md` fail-closed skill pin/grant
  preflight and audit-preview contract.
- `docs/RHM_022_SKILLS_DURABLE_PIN_GRANT_AUDIT_STORAGE.md` durable SQLite
  skill pin/grant/audit storage contract.
- `docs/RHM_024_SKILLS_PREFLIGHT_AUDIT_RETENTION.md` skill preflight audit
  summary and retention-prune contract.
- `docs/RHM_025_SKILLS_POLICY_REVOCATION.md` durable skill pin/grant
  revocation contract.
- `docs/RHM_027_SKILLS_POLICY_EVENT_AUDIT_TRAIL.md` append-only skill policy
  event audit trail contract.
- `docs/RHM_029_SKILLS_POLICY_EVENT_RETENTION.md` skill policy event
  retention-prune contract.
- `docs/RHM_030_SKILLS_POLICY_STORE_READINESS.md` skill policy store
  readiness and maintenance summary contract.
- `docs/RHM_032_OPS_READINESS_GATE.md` long-running daemon operational
  readiness gate contract.
- `docs/RHM_033_READY_CACHE_STUTTER_GUARD.md` short-TTL readiness cache and
  latency-budget gate contract.
- `docs/RHM_034_MEMORY_SKILLS_SNAPSHOT_CACHE.md` short-TTL memory/skills
  snapshot cache contract for reducing repeated scan cost.
- `docs/RHM_035_HTTP_BACKPRESSURE_GUARD.md` HTTP in-flight backpressure guard
  contract for multi-device polling bursts.
- `docs/RHM_046_HTTP_IO_TIMEOUTS.md` bounded HTTP socket read/write timeout
  contract for slow or half-open client connections.
- `docs/RHM_036_HTTP_LATENCY_METRICS.md` HTTP route latency metrics contract for
  slow-request diagnosis.
- `docs/RHM_044_HTTP_METRICS_RECENT_WINDOW.md` bounded recent-window HTTP
  stutter diagnostics contract.
- `docs/RHM_037_OPS_SOAK_RUNNER.md` sustained ops soak runner contract.
- `docs/RHM_039_DAEMON_OPS_REPORT.md` non-mutating daemon ops report contract.
- `docs/RHM_040_DAEMON_MAINTENANCE_RETENTION.md` dry-run-by-default log/report
  retention contract.
- `docs/RHM_043_DAEMON_OPS_GATE.md` daily/manual daemon ops gate contract.
- `docs/RHM_041_XT_CLASSIC_COMPAT_PREFLIGHT.md` read-only XT classic Hub
  compatibility preflight contract.
- `docs/RHM_042_XT_CLASSIC_GRPC_COMPAT_PROBE.md` fail-closed XT classic Hub
  gRPC compatibility probe contract.
- `docs/RHM_045_XT_CLASSIC_STATUS_WRITER_ROLLBACK_GATE.md` explicit-cutover XT
  classic status writer and rollback gate contract.
- `docs/RHM_047_XT_FILE_IPC_SHADOW_RESPONDER.md` temporary-dir-only XT file
  IPC shadow responder contract.
- `docs/RHM_048_XT_FILE_IPC_SHADOW_DRAIN_PROCESSOR.md` bounded manual XT file
  IPC shadow drain contract.
- `docs/RHM_049_XT_FILE_IPC_SHADOW_PROCESSOR_CYCLE.md` Rust-owned manual XT
  file IPC shadow processor cycle status contract.
- `docs/RHM_050_XT_FILE_IPC_SHADOW_SUPERVISOR_LOOP.md` bounded synchronous XT
  file IPC shadow supervisor loop contract.
- `docs/RHM_059_XT_FILE_IPC_SHADOW_WATCHER_SMOKE.md` lock/status XT file IPC
  shadow watcher lifecycle smoke contract.
- `docs/RHM_061_XT_FILE_IPC_SHADOW_WATCHER_ROLLBACK_SMOKE.md` XT file IPC
  shadow watcher rollback smoke contract.
- `docs/RHM_064_XT_FILE_IPC_WATCHER_READINESS_GATE.md` read-only XT file IPC
  watcher readiness gate contract.
- `docs/RHM_066_XT_FILE_IPC_WATCHER_START_PLAN.md` default-off XT file IPC
  watcher start plan contract.
- `docs/RHM_067_XT_FILE_IPC_WATCHER_RUN_ONCE.md` default-off XT file IPC
  one-shot watcher run contract.
- `docs/RHM_068_XT_FILE_IPC_WATCHER_RUN_ONCE_SMOKE.md` isolated XT file IPC
  one-shot watcher smoke contract.
- `docs/RHM_071_XT_FILE_IPC_WATCHER_RUN_ONCE_REPORT.md` persisted report
  support for the XT file IPC one-shot watcher smoke.
- `docs/RHM_072_XT_FILE_IPC_RUN_ONCE_OPS_GATE.md` optional ops-gate integration
  for isolated XT file IPC run-once smoke evidence.
- `docs/RHM_079_XT_FILE_IPC_RUN_ONCE_OPS_REPORT.md` optional ops-report
  integration for isolated XT file IPC run-once smoke evidence.
- `docs/RHM_080_XT_FILE_IPC_WATCHER_SESSION.md` default-off bounded XT file IPC
  watcher session contract.
- `docs/RHM_083_XT_FILE_IPC_BACKGROUND_WATCHER_LIFECYCLE.md` default-off bounded
  XT file IPC background watcher lifecycle contract.
- `docs/RHM_084_XT_FILE_IPC_BACKGROUND_WATCHER_SMOKE.md` packageable isolated
  XT file IPC background watcher lifecycle smoke.
- `docs/RHM_085_XT_FILE_IPC_BACKGROUND_WATCHER_OPS_EVIDENCE.md` optional
  ops-report/ops-gate integration for background watcher smoke evidence.
- `docs/RHM_086_XT_FILE_IPC_REQUEST_SCHEMA_COMPAT.md` XT file IPC request and
  response metadata compatibility for the shadow fail-closed responder.
- `docs/RHM_087_XT_FILE_IPC_RUNTIME_EXECUTION_PLAN.md` shadow-only model-route
  execution adapter plan for XT file IPC requests.
- `docs/RHM_088_XT_FILE_IPC_RUNTIME_ADAPTER_CANDIDATE.md` fail-closed runtime
  adapter candidate for XT file IPC requests.
- `docs/RHM_089_XT_FILE_IPC_RUNTIME_ADAPTER_CANCEL_CONTRACT.md` cancel-file
  contract for the fail-closed runtime adapter candidate.
- `docs/RHM_090_XT_FILE_IPC_RUNTIME_ADAPTER_RESPONSE_COLLISION.md` existing
  response collision contract for the fail-closed runtime adapter candidate.
- `docs/RHM_091_XT_FILE_IPC_RUNTIME_ADAPTER_UNSUPPORTED_REQUEST.md`
  unsupported request type contract for the fail-closed runtime adapter
  candidate.
- `docs/RHM_092_XT_FILE_IPC_RUNTIME_ADAPTER_NO_SELECTED_MODEL.md` missing
  selected-model route blocker for the fail-closed runtime adapter candidate.
- `docs/RHM_093_XT_FILE_IPC_RUNTIME_ADAPTER_OVERWRITE_GATE.md` explicit
  overwrite-response gate for the fail-closed runtime adapter candidate.
- `docs/RHM_094_XT_FILE_IPC_RUNTIME_ADAPTER_INPUT_SIZE_GUARD.md` request file
  and prompt size guard for the fail-closed runtime adapter candidate.
- `docs/RHM_095_XT_FILE_IPC_RUNTIME_ADAPTER_OVERSIZED_FILE_COVERAGE.md`
  oversized request-file smoke coverage for the fail-closed runtime adapter
  candidate.
- `docs/RHM_096_XT_FILE_IPC_RUNTIME_ADAPTER_INVALID_JSON_GATE.md` malformed
  request JSON gate for the fail-closed runtime adapter candidate.
- `docs/RHM_100_XT_FILE_IPC_PRODUCTION_SESSION.md` explicit XT file IPC
  production session contract with live-base-dir, rollback, and confirmation
  gates.
- `docs/RHM_101_XT_FILE_IPC_PRODUCTION_CUTOVER_BLOCKER.md` read-only XT file
  IPC live cutover blocker contract.
- `docs/RHM_102_XT_FILE_IPC_PRODUCTION_ROLLBACK_REHEARSAL.md` non-live
  apply/rollback rehearsal contract for XT file IPC production keys.
- `docs/RHM_103_XT_FILE_IPC_LIVE_CUTOVER_PREFLIGHT.md` final write-before
  snapshot and live cutover command-plan contract.
- `docs/RHM_104_XT_FILE_IPC_LIVE_HEARTBEAT_SOAK.md` live XT status heartbeat
  soak gate.
- `docs/RHM_105_XT_FILE_IPC_PRODUCTION_AWARE_SHADOW_SMOKES.md`
  production-aware shadow smoke reducers.
- `docs/RHM_106_XT_FILE_IPC_HEARTBEAT_FAST_REFRESH.md` Rust-owned live status
  fast refresh and compat fast path.
- `docs/RHM_107_XT_LIVE_HEARTBEAT_ON_DEMAND_REPAIR.md` on-demand repair for
  stale Rust-owned live status evidence during readiness and compat probes.
- `docs/RHM_108_XT_LIVE_STATUS_WRITE_LOCK_AND_NONBLOCKING_REPAIR.md` status
  write lock, unique temp files, and nonblocking request-path live repair.
- `docs/RHM_109_XT_LIVE_STARTUP_NONBLOCKING_STATUS.md` startup nonblocking live
  status overlay and lower Group Container write pressure.
- `docs/RHM_117_XT_LIVE_STATUS_ON_DEMAND_DISK_REPAIR.md` explicit-cutover
  request-path disk repair for stale or missing Rust-owned live status.
- `docs/RHM_118_PRODUCTION_STABILITY_SESSION_ADOPTION.md` package-root
  adoption for already-running production stability sessions.
- `docs/RHM_120_ROLLING_CHECKPOINT_SIDECAR_ADOPTION.md` package-root adoption
  for already-running rolling checkpoint sidecars.
- `docs/RHM_058_CROSS_NETWORK_READINESS_GATE.md` LAN/cross-device readiness
  gate contract.
- `docs/RHM_062_CROSS_NETWORK_INSTALLED_GATE.md` strict installed-state LAN
  gate contract.
- `docs/RHM_065_CROSS_NETWORK_INSTALL_PLAN.md` non-mutating LAN install and
  rollback plan contract.
- `docs/RHM_020_MODEL_ROUTE_COMBINED_CANDIDATE_EVIDENCE_REPORT.md` persisted
  remote/local model-route candidate evidence report contract.
- `docs/RHM_023_MODEL_ROUTE_SELECTED_MODEL_AUTHORITY_PLAN.md` selected-model
  authority dry-run plan and rollback contract.
- `docs/RHM_026_MODEL_ROUTE_PREP_TRIAL_SMOKE.md` default-off model-route prep
  trial smoke contract.
- Existing Node Hub opt-in shadow compare hook for `GetSchedulerStatus`.
- Existing Node Hub opt-in Rust scheduler status read bridge for
  `GetSchedulerStatus`, using async process execution on the Node side.
- Existing Node Hub opt-in Rust scheduler status cutover readiness gate.
- Existing Node Hub opt-in Rust scheduler authority bridge for paid AI slot
  lifecycle, guarded by readiness and fallback.
- Existing Node Hub opt-in Rust scheduler lease shadow bridge for paid AI slot
  lifecycle mirroring, with optional HTTP-first daemon mode.
- Existing Node Hub opt-in Rust provider route shadow compare for
  `HubProviderKeys.GetProviderKeyRouteDecision`.
- Existing Node Hub opt-in Rust provider route authority observe and
  candidate-audit hooks for paid-model `HubAI.Generate`.
- Existing Node Hub opt-in Rust model route authority prep bridge and
  candidate-audit hook for `HubAI.Generate`, preserving Node/XT execution
  authority by default.
- Rust scheduler DB core: enqueue, lease, heartbeat, release, cancel, counters,
  snapshots, and DB-backed status view.
- Scheduler shadow-compare reports.
- Scheduler lease shadow evidence reports.
- Scheduler cutover readiness gate.
- Build, run, and package command wrappers.

Run:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/build_rust_hub.command"
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" migrate
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" doctor
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" scheduler-smoke
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" scheduler claim --request-id req-1 --scope-key project:demo --idempotency-key req-1 --lease-owner node-authority-worker
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" scheduler status --include-queue-items
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" scheduler lease-shadow-report --limit 20
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" scheduler cutover-readiness
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/provider_route_smoke.command" --model-id gpt-4o
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/provider_route_shadow_compare_smoke.command" --model-id gpt-4o
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/model_inventory_shadow_compare_smoke.command"
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/model_inventory_http_bridge_smoke.command"
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/model_inventory_shadow_compare_runner.command" --runs 3 --min-compare-reports 3 --expect-ready --expect-zero-mismatch
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/model_inventory_shadow_compare_runner.command" --use-existing-runtime --runtime-base-dir "/path/to/runtime_base_dir" --runs 10 --min-compare-reports 10 --expect-ready --expect-zero-mismatch
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/model_route_http_smoke.command" --timeout-ms 30000
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/model_route_generate_candidate_runner.command" --runs 2 --concurrency 1 --expect-ready --min-candidate-audits 2 --timeout-ms 45000
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/model_route_local_candidate_runner.command" --runs 2 --concurrency 1 --expect-ready --min-candidate-audits 2 --timeout-ms 45000
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/model_route_candidate_evidence_runner.command" --remote-runs 1 --local-runs 1 --concurrency 1 --expect-ready --timeout-ms 45000
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/model_route_authority_plan_runner.command" --remote-runs 1 --local-runs 1 --concurrency 1 --expect-ready --timeout-ms 45000
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/model_route_prep_trial_runner.command" --remote-runs 1 --local-runs 1 --concurrency 1 --expect-ready --timeout-ms 45000
node "/Users/andrew.xie/Documents/AX/x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_model_route_authority_bridge.test.js"
node "/Users/andrew.xie/Documents/AX/x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_provider_route_authority_generate_hook.test.js"
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/provider_route_shadow_compare_runner.command" --runs 10 --expect-ready --expect-zero-mismatch
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/provider_route_generate_observe_runner.command" --runs 1 --concurrency 1 --enable-candidate-audit --expect-candidate-ready --min-candidate-audits 1 --max-generate-ms 3000
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/provider_route_cutover_readiness_runner.command" --shadow-runs 3 --candidate-runs 3 --expect-ready
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/provider_route_authority_plan_runner.command" --shadow-runs 3 --candidate-runs 3 --expect-ready
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" provider reports --limit 20
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" provider readiness
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" model inventory
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" model route --task-type summarize --required-capability text.summarize --model-id auto
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" model readiness --min-compare-reports 0 --max-mismatches 0
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" memory readiness
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/memory_retrieval_shadow_smoke.command"
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/memory_retrieval_http_smoke.command"
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" skills readiness
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" skills pin --scope-key project:demo --skill-id memory-core --actor operator
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" skills grant --scope-key project:demo --skill-id memory-core --capability memory --actor operator
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" skills preflight --scope-key project:demo --skill-id memory-core --requested-capabilities memory
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/skills_catalog_shadow_smoke.command"
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/skills_catalog_http_smoke.command"
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/ui_compatibility_no_product_ui_change_gate.command"
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/ops_readiness_gate.command" --cycles 3 --interval-ms 250 --timeout-ms 30000 --max-endpoint-ms 2000 --max-cycle-ms 5000
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/ops_soak_runner.command" --cycles 5 --interval-ms 100 --timeout-ms 30000 --max-endpoint-ms 2000 --max-cycle-ms 5000
node "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/node_scheduler_shadow_compare.js" --self-test
node "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/node_hub_shadow_compare_smoke.js" --runs 3 --interval-ms 250 --timeout-ms 15000 --expect-zero-mismatch
node "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/node_hub_shadow_compare_runner.js" --no-start --duration-ms 1000 --report-interval-ms 500 --expect-zero-mismatch
node "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/scheduler_cutover_readiness_runner.js" --runs 3 --expect-ready --expect-zero-mismatch
node "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/scheduler_authority_runner.js" --runs 1 --timeout-ms 45000
node "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/scheduler_authority_runner.js" --runs 1 --concurrency 3 --bridge-response-delay-ms 3000 --timeout-ms 70000 --expect-queued
node "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/scheduler_authority_runner.js" --scenario queued-cancel --bridge-response-delay-ms 3000 --timeout-ms 70000
node "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/scheduler_authority_runner.js" --scenario queued-timeout --timeout-ms 70000
node "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/node_hub_authority_live_runner.js" --runs 1 --timeout-ms 45000
node "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/node_hub_authority_live_runner.js" --runs 3 --concurrency 3 --bridge-response-delay-ms 2500 --timeout-ms 90000 --expect-queued
node "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/node_hub_authority_live_runner.js" --scenario queued-cancel --timeout-ms 70000
node "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/node_hub_authority_live_runner.js" --scenario queued-timeout --timeout-ms 70000
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" serve
```

Warm daemon manager:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/xhubd_daemon.command" start
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/xhubd_daemon.command" health
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/xhubd_daemon.command" ready
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/xhubd_daemon.command" profile
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/xhubd_daemon.command" launchd-plist
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/xhubd_daemon.command" launchd-install --replace-running
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/xhubd_daemon.command" launchd-status
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/xhubd_daemon.command" launchd-uninstall
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/xhubd_daemon.command" ops-report --require-ready --max-log-bytes 4096
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/daemon_ops_report.command" --require-ready --max-log-bytes 4096
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/daemon_maintenance.command" --max-log-bytes 10485760 --keep-report-files 100 --max-report-age-days 30
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/daemon_ops_gate.command" --max-slow-requests 0 --maintenance-max-log-bytes 10485760 --keep-report-files 100 --max-report-age-days 30
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/daemon_watchdog.command" --max-slow-requests 0 --maintenance-max-log-bytes 10485760 --keep-report-files 100 --max-report-age-days 30
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/xhubd_daemon.command" watchdog-plist
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/xhubd_daemon.command" watchdog-install --dry-run
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/xhubd_daemon.command" watchdog-status
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/xhubd_daemon.command" watchdog-uninstall --dry-run
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/xhubd_daemon.command" access-key-init --profile lan
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/lan_access_key_launchd_smoke.command"
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/memory_retrieval_shadow_smoke.command"
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/memory_retrieval_http_smoke.command"
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/skills_catalog_shadow_smoke.command"
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/skills_catalog_http_smoke.command"
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/xhubd_daemon.command" env
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/xhubd_daemon.command" stop
```

`xhubd_daemon.command` starts `xhubd serve` in the background, waits for
`/health`, writes `run/xhubd.pid`, and writes logs under `logs/`. `ready`
checks `/ready`, which reports contract, SQLite, scheduler, network bind,
memory policy, skills policy, provider/model HTTP capability, and cross-network
readiness in one JSON document. `xhubd serve` caches `/ready` for a short
process-local TTL (`XHUB_RUST_READY_CACHE_TTL_MS`, default `250`) to absorb
high-frequency UI/bridge polling without repeatedly scanning the same local
state. It also caches read-only memory snapshots and skills catalogs for short
process-local TTLs (`XHUB_RUST_MEMORY_SNAPSHOT_CACHE_TTL_MS` and
`XHUB_RUST_SKILLS_CATALOG_CACHE_TTL_MS`, defaults `500`) so repeated
`/memory/*` and `/skills/readiness|catalog` polling does not rescan the same
files on every request. Business HTTP routes are also guarded by
`XHUB_RUST_HTTP_MAX_IN_FLIGHT` (default `128`); `/health` remains exempt for
process managers, while excess business requests receive a 503
`http_backpressure` response. Each HTTP connection also gets bounded socket
read/write timeouts (`XHUB_RUST_HTTP_READ_TIMEOUT_MS` and
`XHUB_RUST_HTTP_WRITE_TIMEOUT_MS`, defaults `5000`) so slow or half-open
connections cannot hold worker threads indefinitely. Route latency metrics are
available at
`/runtime/http-metrics`, with slow-request threshold
`XHUB_RUST_HTTP_SLOW_MS` (default `2000`) and without request-body/detail
payloads. They also keep a bounded recent window
(`XHUB_RUST_HTTP_METRICS_RECENT_LIMIT`, default `256`) so daily/manual gates can
judge current stutter without being stuck on old lifetime slow-request counts.
`ops_soak_runner.command` keeps one temporary daemon warm across repeated checks
and persists `reports/ops_soak_*.json` so latency/cycle trends can be compared
before packaging. `access-key-init` creates a `0600` HTTP
access key file without printing the key. `lan_access_key_launchd_smoke.command`
verifies the LAN profile, access-key file mode, LaunchAgent plist generation,
and no-secret-output behavior without starting a network listener. The `env`
command prints only HTTP transport variables for Node Hub bridges; it does not
enable scheduler authority, provider authority, or lease shadow by itself, and
it does not print secrets.

Persistent daemon profiles live in `config/`:

- `daemon_profile.local.json` is the default long-running local profile.
- `daemon_profile.lan.example.json` is the explicit cross-device template.

Profile values are resolved as default profile file, then environment
variables, then command-line flags. The daemon manager creates the configured
runtime, memory, skills, run, log, and SQLite parent directories before launch
so `/ready` can verify durable local state instead of relying on transient env.
`launchd-plist` writes a macOS LaunchAgent plist under `run/` with absolute
paths, direct foreground `xhubd serve` execution, `RunAtLoad`, `KeepAlive`, and
launchd stdout/stderr logs under `logs/`. `launchd-install` writes the
persistent LaunchAgent plist to `~/Library/LaunchAgents` by default, copies the
daemon binary plus required assets/config/migrations/reports into
`~/Library/Application Support/AX/rust-hub/<profile>`, ad-hoc signs the copied
runtime binary on macOS, bootstraps that runtime copy into the current user
domain, enables it, kickstarts it, and waits for `/health` plus `/ready`. The
runtime copy keeps launchd out of `~/Documents`, which avoids macOS
background-service privacy denial for the source checkout.
Use `--replace-running` when a manually started daemon already owns the same
port. `launchd-status` reports launchd load state, HTTP health/readiness, and
the pid from the runtime pid file or `launchctl print`. `launchd-uninstall`
boots the service out and removes the installed plist unless `--keep-plist` is
passed. These launchd commands are process-management only; they do not enable
scheduler authority, provider authority, model-selection authority, memory
writes, or skills execution.

`ops-report` and `daemon_ops_report.command` are read-only diagnostics. They
collect source/manual daemon status, launchd status, `/health`, `/ready`,
`/runtime/http-metrics`, UI compatibility, and redacted log tails into
`reports/daemon_ops_*.json` without starting, stopping, or restarting the
daemon. Use `--require-ready` when the command should fail a CI/ops gate if the
daemon is not healthy and ready.

`maintenance` and `daemon_maintenance.command` bound daemon log and report
growth. They default to dry-run preview and write
`reports/daemon_maintenance_*.json`; only `--apply` truncates over-limit logs
to their newest tail bytes or deletes old/excess `.json` reports. The command
does not restart or stop the daemon.

`ops-gate` and `daemon_ops_gate.command` are the daily/manual health gate. They
require `/health`, `/ready`, and `/runtime/http-metrics`, enforce the
slow-request budget, include maintenance dry-run evidence, and verify UI plus
authority boundaries. They write `reports/daemon_ops_gate_*.json` and never
apply maintenance or restart the daemon. Post-cutover, the default boundary
requires Rust memory writer and skills execution authority; use
`--no-require-memory-skills-production` only for explicit pre-cutover rehearsal.

`product_process_sanity.command` is the lightweight performance hygiene gate.
It takes one `ps` snapshot, detects stale mounted `/Volumes/X-Hub...` app
sidecars, flags ad-hoc `target/debug|release/xhubd` processes, and can enforce a product CPU budget with
`--max-product-cpu-percent`. It writes `reports/product_process_sanity_*.json`
and is report-only: no kill, restart, UI change, or authority change. A separate
`RELFlowHub.app` is reported as external diagnostics only; it is not part of the
X-Hub product shell, CPU budget, or stale-mounted failure condition. `ops-gate`
and `watchdog` run it by default; pass `--skip-product-process-sanity` only when
process inspection is unavailable. The Rust daemon also exposes the same
diagnostic surface at authenticated `GET /runtime/product-process-sanity` for XT
Doctor and report projections.

`watchdog` and `daemon_watchdog.command` are the long-running daemon guard. They
check launchd load/running state, `/health`, `/ready`, HTTP recent-window slow
requests, HTTP I/O timeout/backpressure readiness flags, pid-file health,
maintenance need, UI compatibility, and authority boundaries. They write
`reports/daemon_watchdog_*.json`. By default the command is dry-run/report-only;
the only mutation it can perform is removing stale or invalid pid files, and
only when both `--apply` and `--repair-stale-pid` are passed. It does not stop,
restart, bootstrap, or uninstall the daemon.

`watchdog-plist`, `watchdog-install`, `watchdog-status`, and
`watchdog-uninstall` manage a separate user LaunchAgent timer that runs the
dry-run watchdog periodically. The timer uses `StartInterval` (default 900
seconds), writes `daemon_watchdog_*.json` reports, and logs to
`logs/xhubd.watchdog.out.log` / `logs/xhubd.watchdog.err.log`. It does not
restart or repair the daemon; use `watchdog-install --dry-run` to inspect the
planned plist and launchctl actions before installing.

`GET /xt/classic-hub-compat` is a read-only preflight for the XT classic Hub
contract. It scans the same candidate `hub_status.json` paths XT uses,
identifies an already-running classic X-Hub, and reports why Rust must not mark
XT `hubInteractive=true` yet. When explicitly enabled, it can probe
`HubRuntime.GetSchedulerStatus` on the Rust gRPC endpoint, but it still defaults
fail-closed and keeps `production_authority_change=false`. The guarded
write-status endpoint remains default-off and requires rollback, apply,
file-IPC, and explicit production-cutover gates before writing `hub_status.json`.

LAN / cross-device profile:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/xhubd_daemon.command" access-key-init --profile lan
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/xhubd_daemon.command" start --profile lan --public-host <LAN-IP>
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/xhubd_daemon.command" ready --profile lan --public-host <LAN-IP>
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/lan_access_key_launchd_smoke.command"
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/cross_network_readiness_gate.command" --profile lan --public-host <LAN-IP>
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/cross_network_installed_gate.command" --profile lan --public-host <LAN-IP>
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/cross_network_install_plan.command" --profile lan --public-host <LAN-IP>
```

Default `local` profile binds `127.0.0.1`. Non-loopback bind is rejected unless
`--profile lan`, `--allow-lan`, or `XHUB_RUST_HUB_ALLOW_LAN=1` is set. This
keeps long-running Hub deployment fail-closed while still allowing explicit
multi-device LAN setup. Cross-device HTTP requests must send
`Authorization: Bearer <key>` or `X-XHub-Access-Key`; `/health` remains
unauthenticated for local process managers. The LAN profile points at
`secrets/xhubd_lan_access_key`, and `/ready` is not cross-network ready until
that file exists and is non-empty.

`cross_network_readiness_gate.command` is a non-mutating deployment gate for
multi-device use. It requires an explicit LAN profile/non-loopback bind, a
non-placeholder public host, a non-empty `0600` access-key file, launchd plist
key-file wiring without key content, watchdog timer installability, UI
compatibility, and unchanged authority boundaries. Add `--require-live-ready`,
`--require-launchd-loaded`, and `--require-watchdog-timer` when validating an
already installed always-on LAN daemon.
`cross_network_installed_gate.command` is the strict shortcut for that installed
state and should fail until both the LAN daemon LaunchAgent and watchdog timer
LaunchAgent are actually loaded.
`cross_network_install_plan.command` prints the exact install, validation, and
rollback commands without executing them.

Domain / tunnel profile:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/cross_network_remote_route_gate.command" --public-base-url https://hub.your-domain.com
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/cross_network_remote_route_doctor.command" --public-base-url https://hub.your-domain.com --no-network
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/cross_network_domain_activation_plan.command" --public-base-url https://hub.your-domain.com --access-key-file secrets/xhubd_domain_access_key --require-memory-skills-production
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/xhubd_daemon.command" access-key-init --profile domain --public-base-url https://hub.example.com --public-endpoint
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/cross_network_readiness_gate.command" --profile domain --public-base-url https://hub.example.com --public-endpoint
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/cross_network_pairing_export.command" --profile domain --public-base-url https://hub.example.com --public-endpoint
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/cross_network_domain_smoke.command" --public-base-url https://hub.example.com --access-key-file secrets/xhubd_domain_access_key
```

Use the domain profile for Cloudflare Tunnel, Tailscale, Headscale, or a VPS
reverse tunnel. The daemon may still bind `127.0.0.1`, but
`--public-endpoint` forces HTTP access-key auth and lets `/ready` report
cross-network readiness once the public URL and key file are configured.
`cross_network_remote_route_gate.command` validates the remote entry semantics
before activation: stable HTTPS DNS and tailnet DNS pass; loopback, LAN-only
names, link-local hosts, and raw public IPs are blocked; raw VPN/tailnet/private
IPs require `--allow-vpn-raw-host` so they are not misrepresented as a domain.
`cross_network_remote_route_doctor.command` adds read-only diagnostics on top of
that gate: DNS A/AAAA visibility, local tailnet interface presence, public
`/health`, unauthenticated `/ready`, and optional authenticated `/ready` when an
access-key file is supplied. Use `--no-network` for planning evidence before the
tunnel is live; use `--require-live-http --require-auth-ready` after the public
endpoint is supposed to work.
`cross_network_domain_activation_plan.command` is the safest starting point for
the real cutover: it embeds the remote-route gate, rejects placeholder or unsafe
remote entries, prints the exact access-key, launchd, watchdog, pairing, smoke,
and rollback commands, and does not mutate state by itself.
`cross_network_pairing_export.command` writes a `0600` XT pairing bundle that
contains the access key; the command output never prints the key. The domain
smoke must reject unauthenticated `/ready` and pass authenticated `/ready`
before XT should use the domain outside the first LAN setup.

Swift-shell remote entry authority:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" network remote-entry-candidates
curl -fsS "http://127.0.0.1:50151/network/remote-entry-candidates"
```

`network remote-entry-candidates` and `/network/remote-entry-candidates` emit
`xhub.rust_hub.remote_entry_candidates.v1`. This is the Rust-core decision that
the Swift Hub settings shell should present: stable HTTPS domain/tunnel first,
then no-domain private-network entries such as MagicDNS, Tailscale/Headscale
`100.64.0.0/10`, WireGuard, or ZeroTier-style tunnel addresses. Normal LAN
addresses, loopback, wildcard binds, `.local` names, and raw public IPs are not
presented as stable remote entries.

Memory retrieval shadow path:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" memory readiness
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" memory search --query "governed retrieval" --max-results 5
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" memory object-index-rebuild
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/memory_retrieval_shadow_smoke.command"
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/memory_retrieval_http_smoke.command"
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/memory_hybrid_quality_bench.command"
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/memory_hybrid_quality_bench.command" --profile large
bash "/Users/andrew.xie/Documents/AX/x-hub-system/scripts/ci/rust_memory_hybrid_quality_gate.sh"
```

Rust memory retrieval is read-only and shadow-only. It scans supported local
memory files under `XHUB_RUST_MEMORY_DIR` or `data/memory` (`.json`, `.jsonl`,
`.md`, `.txt`), returns `xt.memory_retrieval_result.v1`, and keeps
`writer_authority_in_rust=false`. `project_code` mode excludes personal
capsules by default, denies secret-seeking queries, and skips secret-like
fields/content before returning snippets. Durable canonical memory writeback
still belongs to the existing Writer + Gate path.
`memory_retrieval_http_smoke.command` starts a temporary warm daemon and checks
`/ready`, `/memory/readiness`, `/memory/search`, `POST /memory/retrieve`, and
the role-aware `/memory/project-role-transcript` projection against a temporary
SQLite fixture. It also creates a temporary Rust memory object and verifies
`POST /memory/retrieve` can return the `rust_memory_objects_hybrid_v1` W6
retrieval path through the rebuildable `rust_hub_memory_object_index` derived
table without enabling semantic search or writer authority. The derived index is
not memory truth; `memory object-index-rebuild` and `POST /memory/reindex`
rebuild it from canonical Rust memory objects, and `/memory/readiness` reports
row count, stale count, and latest index generation evidence.
W6 retrieval uses a Rust BM25-style scorer over the policy-filtered derived
index (`retrieval_engine.fts=derived_index_bm25_rust`), so SQLite FTS5 is not a
runtime portability dependency.
When `explain=true`, object retrieval also returns
`xhub.memory.retrieval_trace.v1` with selected/omitted refs and redacted reason
codes for UI diagnostics. `memory_hybrid_quality_bench.command` runs a temporary
daemon fixture covering project chat, supervisor next-step, remote sanitized
visibility, raw evidence opt-in, and private sensitivity filter cases. Its
default `quick` profile is for daily validation; `--profile large` adds
deterministic distractors plus Chinese/domain/reviewer cases and reports
`precision_at_1`, `recall_at_k`, `filter_pass_rate`, and `trace_coverage`.
`scripts/ci/rust_memory_hybrid_quality_gate.sh` is the CI-facing quick gate: it
runs `node --check` for the bench script plus the default quick profile, writes
`build/reports/rust_memory_hybrid_quality_gate_summary.v1.json`, and leaves the
large profile as a manual/nightly validation target.

Governed memory writeback starts as a candidate queue, not direct durable
mutation. `POST /memory/writeback/candidates` creates `status=candidate` memory
objects, `GET /memory/writeback/candidates` lists pending candidates, and
`POST /memory/writeback/candidates/extract` deterministically maps AXMemory
delta fields into candidate objects without activating them. The extractor
supports `dry_run=1`, stable duplicate collapse, and secret fail-closed batch
blocking. CLI access is available through `xhubd memory candidate-extract
--payload-json ...`.
`POST /memory/writeback/candidates/{memory_id}/approve|reject` transitions only
candidate records to `active` or `rejected` with memory events. The same
transition is available through `/memory/objects/{memory_id}/approve|reject`.
Secret-like candidates fail closed, invalid transitions return conflict, and
`/memory/readiness` reports `writeback_candidates` evidence.
Candidate creation also records same scope/source_kind/layer active conflicts in
policy/provenance metadata. Approval of a conflicting candidate requires an
explicit `conflict_resolution_reason`; newer same-key pending candidates archive
older pending candidates with `superseded_by` without resurrecting rejected rows.
`GET /memory/writeback/candidates` also returns
`candidate_diagnostics` (`xhub.memory.writeback_candidate_diagnostics.v1`), and
`/memory/readiness` exposes the same bounded summary at
`object_store.writeback_candidates.diagnostics`. The diagnostics include
candidate/conflict/stale/stale-review/supersession counts, planned archive and
review counts, queue pressure, noise score, bounded IDs, and
`production_authority_change=false`. The Swift shell consumes this as read-only
evidence in the candidate queue and Unified Doctor; Rust still enforces conflict
approval reasons and remains the memory authority.
`POST /memory/writeback/candidates/maintenance` is the Rust stale queue hygiene
surface. It is dry-run by default; `apply=1` is required to mutate. Low-risk
stale working-set/observation candidates are archived with memory events, while
canonical/high-value candidates stay pending and get `stale_review_required`
metadata for explicit review. CLI access is available through `xhubd memory
candidate-maintenance --project-id ... --max-age-ms ... --apply`.
`tools/memory_writeback_candidate_smoke.command` runs an isolated temp daemon and
verifies the full candidate lifecycle without touching the live Hub database.
XT now calls this extractor from `AXMemoryPipeline` after model/fallback
`AXMemoryDelta` creation through `HubIPCClient.extractMemoryWritebackCandidatesViaRust`.
That caller is short-timeout, candidate-only, skips removal-only deltas, and logs
`active_write=false` / `production_authority_change=false` evidence while local
AXMemory files remain compatibility projection/fallback.

Role-aware project transcript projection:

```bash
curl -fsS "http://127.0.0.1:50151/memory/project-role-transcript?project_id=<PROJECT_ID>&thread_key=xterminal_project_<PROJECT_ID>&limit=50"
```

`/memory/project-role-transcript` is a Rust shadow read-only endpoint. It reads
the Hub SQLite `threads`/`turns` rows, returns
`xhub.project_role_transcript_projection.v1`, preserves
`xhub.role_turn_metadata.v1` fields such as `source_role`, `target_role`, and
`dispatch_id`, and redacts encrypted `xhubenc:v1:` content when content is
requested. It does not write memory, grant skill/model/provider authority, or
replace the Node Hub memory writer; XT should consume this as Hub truth
projection and keep local transcript parsing as fallback only.

Skills catalog policy gate:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" skills readiness
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" skills catalog
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" skills pin --scope-key project:demo --skill-id memory-core --actor operator
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" skills grant --scope-key project:demo --skill-id memory-core --capability memory --actor operator
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" skills policy --scope-key project:demo --skill-id memory-core
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" skills preflight --scope-key project:demo --skill-id memory-core --requested-capabilities memory
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" skills policy-events --scope-key project:demo --skill-id memory-core --limit 20
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" skills policy-events-prune --max-rows 10000
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" skills policy-readiness --max-preflight-audit-rows 100000 --max-policy-event-rows 100000
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" skills audit --scope-key project:demo --skill-id memory-core --limit 20
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" skills audit-prune --max-rows 10000
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" skills revoke-grant --scope-key project:demo --skill-id memory-core --capability memory --actor operator
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/run_rust_hub.command" skills unpin --scope-key project:demo --skill-id memory-core --actor operator
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/skills_catalog_shadow_smoke.command"
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/skills_catalog_http_smoke.command"
```

Rust skills support is catalog/readiness/preflight policy only. It scans
`SKILL.md` and `skill.json` manifests under `XHUB_RUST_SKILLS_DIR` or `skills`,
returns `xhub.skills_catalog.v1` and `xhub.skills_readiness.v1`, blocks
secret-shaped manifest content, and keeps `execution_authority_in_rust=false`
plus `hub_executes_third_party_code=false`. `skills pin` and `skills grant`
persist durable SQLite policy records under `rust_hub_*` tables, but they do
not execute skills or grant OS/network/model access by themselves.
`skills preflight` and `/skills/preflight` allow only when the skill is pinned
and every requested capability is granted, and emit a secret-free
`xhub.skills_preflight.audit.v1` preview without starting any skill process.
`skills audit` and `/skills/audit` summarize durable preflight audit rows
without exposing stored `detail_json`; `skills audit-prune` and
`/skills/audit-prune` explicitly keep the newest `max_rows` rows so long-running
daemons have a bounded maintenance path. `skills revoke-grant` and
`skills unpin` mark durable policy rows revoked, so preflight returns to
fail-closed deny until the operator explicitly grants again.
`skills policy-events` and `/skills/policy-events` return append-only
pin/grant/revoke operation metadata without exposing stored `detail_json`.
`skills policy-events-prune` and `/skills/policy-events-prune` explicitly keep
the newest `max_rows` policy event rows for long-running maintenance.
`skills policy-readiness` and `/skills/policy-readiness` summarize active
pin/grant rows plus preflight-audit and policy-event row counts, latest event
timestamps, and operator row thresholds. They return
`xhub.skills_policy_store_readiness.v1` with `detail_json_included=false`, so
long-running daemons can detect when explicit prune maintenance is due without
reading secret-bearing detail payloads.

Optional Node Hub scheduler status read cutover gate:

```bash
export XHUB_RUST_SCHEDULER_STATUS_READ=1
export XHUB_RUST_SCHEDULER_STATUS_REQUIRE_READY=1
export XHUB_RUST_SCHEDULER_STATUS_HTTP=1
export XHUB_RUST_SCHEDULER_STATUS_HTTP_BASE_URL=http://127.0.0.1:50151
export XHUB_RUST_SCHEDULER_STATUS_HTTP_TIMEOUT_MS=750
export XHUB_RUST_SCHEDULER_STATUS_HTTP_FALLBACK_TO_CLI=1
export XHUB_RUST_HUB_ROOT="/Users/andrew.xie/Documents/AX/rust/rust hub"
```

With `STATUS_REQUIRE_READY=1`, Node Hub only answers
`HubRuntime.GetSchedulerStatus` from Rust after
`scheduler cutover-readiness` returns `ready=true`; otherwise it falls back to
the existing Node scheduler snapshot. The Node bridge uses async `execFile`
instead of synchronous process execution, so status polling does not block the
Hub event loop while Rust CLI reads are in flight. It also coalesces concurrent
reads and keeps a short status cache by default to avoid repeated process
startup during rapid UI polling. When `XHUB_RUST_SCHEDULER_STATUS_HTTP=1` is
enabled, the bridge tries warm daemon endpoints first:
`GET /scheduler/cutover-readiness` and `GET /scheduler/status`. CLI fallback is
still enabled by default.

HTTP status bridge smoke:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/scheduler_status_http_bridge_smoke.command"
```

HTTP lease-shadow bridge smoke:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/scheduler_lease_shadow_http_bridge_smoke.command"
```

Optional Node Hub scheduler authority bridge:

```bash
export XHUB_RUST_SCHEDULER_AUTHORITY=1
export XHUB_RUST_SCHEDULER_AUTHORITY_REQUIRE_READY=1
export XHUB_RUST_SCHEDULER_AUTHORITY_HTTP=1
export XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_BASE_URL=http://127.0.0.1:50151
export XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_TIMEOUT_MS=750
export XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_FALLBACK_TO_CLI=1
export XHUB_RUST_SCHEDULER_STATUS_READ=1
export XHUB_RUST_SCHEDULER_STATUS_REQUIRE_READY=1
export XHUB_RUST_HUB_ROOT="/Users/andrew.xie/Documents/AX/rust/rust hub"
```

With authority enabled, Node Hub tries Rust `scheduler claim` before its
in-memory paid AI queue. If Rust is not ready or unavailable, it falls back to
the existing Node queue. Keep status read enabled during authority tests so UI
status comes from Rust truth. When `XHUB_RUST_SCHEDULER_AUTHORITY_HTTP=1` is
enabled, readiness, claim, release, and cancel try the warm daemon endpoints
first and fall back to CLI by default.

Authority-path verification without external network calls:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/scheduler_authority_http_bridge_smoke.command"
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/scheduler_authority_runner.command" --runs 1 --timeout-ms 45000
```

Scheduler-only production authority cutover plan:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/scheduler_production_authority_plan.command"
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/scheduler_production_authority_plan.command" --run-gates --expect-ready
```

This emits `xhub.scheduler_production_authority_plan.v1` with the Node Hub env
to set, rollback `unset` commands, and explicit blocked authority scopes.
The gated plan requires sustained scheduler cutover readiness, HTTP bridge
smoke, single paid-path authority, queued backpressure, queued cancel, queued
timeout, and one live Node Hub authority smoke. Default thresholds require at
least 10 scheduler compare reports, zero mismatches, at least one lease-shadow
run, zero stale active runs, and zero orphaned leases.
It does not edit LaunchAgents, restart Node Hub, change XT UI files, enable
provider/model authority, enable memory writer authority, or enable skills
execution authority.

Scheduler-only production authority apply/rollback:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/scheduler_production_authority_apply.command" --status
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/scheduler_production_authority_apply.command" --apply --restart-dock-agent
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/scheduler_production_authority_apply.command" --rollback --restart-dock-agent
```

The apply command backs up the Dock Agent LaunchAgent plist and records prior
values under `reports/scheduler_production_authority/`. It only manages
scheduler authority env keys.

Single-app X-Hub production authority session env:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/scheduler_production_authority_session.command" --status
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/scheduler_production_authority_session.command" --apply --open-xhub
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/scheduler_production_authority_session.command" --rollback
```

Use this path when X-Hub is built in single-app Bridge mode and the standalone
Dock Agent LaunchAgent is absent.

Persistent single-app session env at login:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/scheduler_production_authority_session_launchd.command" --status
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/scheduler_production_authority_session_launchd.command" --install
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/scheduler_production_authority_session_launchd.command" --uninstall
```

This LaunchAgent only reapplies scheduler authority env and does not open or
modify the X-Hub UI.

Scheduler production authority guard:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/scheduler_production_authority_guard.command"
```

Use this after daemon restart, X-Hub restart, login, or package update. It
checks the running Node process, persistent LaunchAgent, daemon health, slow
request budget, and no-product-UI-change gate.

Provider/model route authority cutover guard:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/route_authority_cutover_guard.command"
```

This is a non-mutating readiness gate. It keeps provider/model authority off
and only reports whether both route layers are ready for a manual prep trial.
By default it accepts either an already-applied scheduler production authority
or a fresh scheduler production authority plan gate that is ready to apply.
Use `--scheduler-gate-mode applied` when validating an installed production
runtime that must already have inherited scheduler authority env, or
`--scheduler-gate-mode skip` only when scheduler readiness was checked by an
outer gate. The guard also runs the production cutover blocker, so provider and
model prep/candidate evidence cannot be mistaken for production authority.

For a fast local sanity run:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/route_authority_cutover_guard.command" --provider-shadow-runs 1 --provider-candidate-runs 1 --provider-min-compare-reports 1 --model-remote-runs 1 --model-local-runs 1 --max-generate-ms 5000 --no-report
```

Provider/model route prep session env:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/route_authority_prep_session.command" --status
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/route_authority_prep_session.command" --apply
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/route_authority_prep_session.command" --clear-production-env
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/route_authority_prep_session.command" --rollback
```

This only applies prep/candidate gates for newly launched X-Hub/Node
processes. It does not enable provider/model production authority. Use
`--clear-production-env` if launchctl contains old provider/model
production/cutover/apply keys; then relaunch X-Hub so Node inherits the
prep-only environment.

Provider/model route prep runtime guard:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/route_authority_prep_runtime_guard.command"
```

Use this after launching or relaunching X-Hub. If it reports
`xhub_node_process_needs_relaunch_for_prep_env`, restart X-Hub so Node inherits
the prep/candidate environment. It also fails closed if provider/model
production/cutover/apply env keys are present in launchctl or the running Node
process.

Provider/model route prep sustained guard:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/route_authority_prep_sustained_guard.command" --cycles 3 --interval-ms 500
```

This repeats runtime env, provider/model route readiness, and daemon
slow-request checks without changing production authority. It defaults to
`--scheduler-gate-mode skip` because scheduler production authority should be
validated by the scheduler-specific gate before entering provider/model prep.
Use `--scheduler-gate-mode applied` only when the sustained prep run must also
prove the installed scheduler authority runtime on every cycle. For interactive
local prep validation, `--max-slow-requests 1` can distinguish provider/model
route readiness from one unrelated recent daemon slow request; production soak
should return this budget to 0. When the slow-request gate fails, the report
includes `daemon_recent_slow_routes` so the offending endpoint is visible.

Persistent provider/model route prep env at login:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/route_authority_prep_session_launchd.command" --status
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/route_authority_prep_session_launchd.command" --install
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/route_authority_prep_session_launchd.command" --uninstall
```

This only reapplies prep/candidate env. It does not open X-Hub or enable
provider/model production authority.

Provider/model route production cutover blocker:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/route_authority_production_cutover_blocker.command"
```

This confirms provider/model production authority remains blocked until the
explicit production switch contract, apply/rollback tooling, long soak,
secret-redaction checks, UI compatibility, and manual approval all pass. The
companion session tool is:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/route_authority_production_session.command" --status
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/route_authority_prep_sustained_guard.command" --cycles 3 --interval-ms 500 --max-slow-requests 0
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/route_authority_production_session.command" --apply --dry-run --confirm-provider-model-production-authority --prep-sustained-report "/path/to/route_authority_prep_sustained_guard_*.json"
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/route_authority_production_session.command" --apply --confirm-provider-model-production-authority --prep-sustained-report "/path/to/route_authority_prep_sustained_guard_*.json"
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/route_authority_production_runtime_guard.command"
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/route_authority_production_session.command" --rollback
```

The production session apply path fails closed unless the explicit confirmation
flag is present and the prep sustained report is fresh, OK, has at least three
successful cycles, has zero daemon slow requests, and reports no production
authority change, UI product change, or secret leak. Use `--dry-run` first to
validate the preflight without writing provider/model production env. After a
real apply, relaunch X-Hub and run the production runtime guard; it requires the
running Node process to inherit provider/model production env, requires
provider/model fallback-on-error to be `0`, verifies scheduler authority is
still present, and fails if unrelated memory writer or skills execution
production keys are visible. XT file IPC production keys are reported but not
blocking by default; add `--fail-on-xt-file-ipc-production` when validating a
strict provider/model-only cutover rehearsal.

After provider/model production authority is live, keep the live XT status
heartbeat gate under soak. `RHM-107` lets readiness and compat probes repair a
stale Rust-owned `hub_status.json` sample through the same explicit cutover
gates before reporting the production surface unavailable. `RHM-108` keeps
request-path repair read-only and uses a process-local live status cache for
readiness/compat probes. `RHM-109` starts heartbeat in trusted live mode,
keeps request-path probes off direct Group Container status reads during live
cutover, and uses a `1000ms` heartbeat with a bounded `2000ms` status lease.
`RHM-110` wraps the live heartbeat soak, daemon ops gate, production runtime
guard, UI compatibility gate, and process sanity checks into one read-only live
stability gate:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/production_live_stability_gate.command" --duration-ms 120000 --interval-ms 2000 --max-status-age-ms 5000 --max-slow-requests 0
```

For overnight validation, increase `--duration-ms` to `28800000` for 8 hours or
`86400000` for 24 hours. The gate writes
`reports/production_live_stability_gate_*.json` and fails closed if Rust memory
writer authority, Rust skills execution authority, product UI, secrets, recent
slow requests, stale XT heartbeat, or temporary `target/*/xhubd` processes drift.
When `--rust-hub-root` is omitted, it uses the live
`launchctl getenv XHUB_RUST_HUB_ROOT` value if available.

Detached long-run session:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/production_live_stability_session.command" --start --duration-ms 28800000
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/production_live_stability_session.command" --status
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/production_live_stability_session.command" --supervision-status
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/production_live_stability_session.command" --checkpoint --duration-ms 10000
```

The session runner stores its state in
`reports/production_live_stability/session_state.json` and writes stdout/stderr
to `logs/production_live_stability_session_*.log`. `--checkpoint` performs a
short immediate gate while the long session continues, and `--status` can
discover a running session started from another package root. Status output is
read-only and also reports the active gate process tree, the heartbeat soak
child when present, report-file metadata, and a bounded live `hub_status.json`
freshness sample so a long run can be diagnosed without interrupting it.
When a freshly packaged root has not adopted state yet, explicit
`--http-base-url` and `--live-base-dir` values are still preserved in status
output, so package migration and recovery checks do not fall back to the wrong
live base dir.
`--supervision-status` combines the long session and rolling checkpoint sidecar
into one read-only payload with compact `supervision_ready`, live heartbeat,
latest checkpoint, slow-request delta, and authority-drift fields.
The gate also records cumulative HTTP slow-request delta across the run, so a
transient slow `/ready` or `/xt/classic-hub-compat` sample cannot disappear just
because it aged out of the bounded recent metrics window.

Active Rust Hub root upgrade plan:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/active_root_upgrade_plan.command" --target-root "/Users/andrew.xie/Documents/AX/rust/rust hub/dist/rust-hub-YYYYMMDDTHHMMSSZ"
```

This is non-mutating. It compares the target package/source root against the
current launchctl and running X-Hub Node root. If provider/model production
authority is already active, it prints scheduler/root commands only and skips
route prep commands so a package update does not overwrite production fallback
or cutover keys. Validation switches to the production runtime guard and
requires memory/skills production when those keys are detected.

Active Rust Hub root upgrade apply:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/active_root_upgrade_apply.command" --target-root "/Users/andrew.xie/Documents/AX/rust/rust hub/dist/rust-hub-YYYYMMDDTHHMMSSZ"
```

Default mode is dry-run. Add `--apply` to update launchctl/session and
persistent LaunchAgents. Add `--relaunch-xhub` only when the running X-Hub
process should be restarted to inherit the target root. Add `--validate` for
post-apply guards. After relaunch, the tool waits for X-Hub Node to report the
target root before validation; tune this with `--relaunch-wait-ms` and
`--relaunch-poll-ms`. If macOS is still closing the previous app instance, it
retries one more `open` and waits again; tune that with
`--relaunch-retry-wait-ms`. In provider/model production mode, the apply path
skips `route_authority_prep_session` and validates with
`route_authority_production_runtime_guard`. Use `--force-route-prep` only for
legacy prep sessions where intentionally returning to prep is acceptable.
This does not newly enable production authority; it preserves the authority
state that is already active while moving the package root.

The runner creates temporary Node/Rust DBs and a fake Bridge IPC responder,
then invokes the real Node `HubAI.Generate` handler. A healthy run returns
`done_ok=true`, one completed Rust authority run, and a clean Rust scheduler
status (`in_flight_total=0`, `queue_depth=0`).

For queue-pressure validation, run it with `--concurrency 3 --expect-queued`.
The Rust scheduler default per-scope concurrency is 2, so this verifies that a
third same-project request queues in Rust and drains cleanly after release.
For queued terminal validation, use `--scenario queued-cancel` and
`--scenario queued-timeout`. These keep the third same-project request queued,
then verify Rust records the terminal queued run as `canceled` and the final
scheduler snapshot is clean without sending the queued request to Bridge.

For process-level validation, use
`tools/node_hub_authority_live_runner.command`. It starts the real Node Hub
gRPC server with `XHUB_RUST_SCHEDULER_AUTHORITY=1`, writes a trusted temporary
client profile, shares one SQLite DB between Node Hub and Rust scheduler, and
sends gRPC `HubAI.Generate` traffic through the production service boundary.
It also supports `--scenario queued-cancel` and `--scenario queued-timeout` to
verify queued terminal paths through the real gRPC stream boundary.

Optional Node Hub provider route shadow compare:

```bash
export XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE=1
export XHUB_RUST_HUB_ROOT="/Users/andrew.xie/Documents/AX/rust/rust hub"
```

This keeps Node as provider-routing authority and compares Rust route decisions
after `HubProviderKeys.GetProviderKeyRouteDecision` responds. The hook uses
async process execution with per-key throttling, so it does not block the Node
event loop. Compare evidence is persisted under component `provider_route` and
can be inspected with `xhubd provider reports` or gated with
`xhubd provider readiness`.

Validation without external network calls:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/provider_route_http_smoke.command"
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/provider_route_http_bridge_smoke.command"
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/provider_route_http_shadow_compare_smoke.command"
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/provider_route_shadow_compare_smoke.command" --model-id gpt-4o
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/provider_route_shadow_compare_runner.command" --runs 10 --expect-ready --expect-zero-mismatch
```

`provider_route_http_smoke.command` starts a temporary `xhubd serve` process and
calls `GET /provider/route`, `GET /provider/reports`, and
`GET /provider/readiness`, then posts `POST /provider/compare` and verifies
readiness with at least one compare report. These daemon-backed provider
surfaces let Node bridge work reuse a warm Rust process instead of spawning a
CLI process for each route/readiness/compare check.
`provider_route_http_bridge_smoke.command` uses the Node bridge itself with
CLI fallback disabled and readiness enabled, proving the HTTP-first bridge can
use the warm daemon for both readiness and route checks.
`provider_route_http_shadow_compare_smoke.command` uses the Node shadow
comparer itself with CLI fallback disabled, proving the HTTP-first compare path
can write provider-route evidence through the warm daemon.

The sustained runner also exercises the readiness-gated provider authority prep
bridge after readiness is true. It verifies Rust can select the expected
`account_key` without exposing provider secrets or taking over production
routing.

Provider authority prep remains disconnected from production routing by default.
Direct prep calls require explicit opt-in:

```bash
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP=1
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_READY=1
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP_THROTTLE_MS=1000
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP_MAX_IN_FLIGHT=2
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP=1
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_BASE_URL=http://127.0.0.1:50151
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_TIMEOUT_MS=750
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP_FALLBACK_TO_CLI=1
```

When prep is enabled, `HubProviderKeys.GetProviderKeyRouteDecision` still
returns the Node-selected decision first. After the response, Node can
asynchronously ask Rust for a readiness-gated prep route and require the Rust
selected `account_key` to match Node. The result is evidence only; Node still
owns provider routing and Bridge payload construction. The service-boundary prep
hook is guarded by a per-route throttle and a process-wide max in-flight cap so
busy provider-key route checks cannot start unbounded Rust CLI work.
If `XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP=1` is enabled and a warm
`xhubd serve` daemon is listening, the bridge tries `GET /provider/route` before the
CLI route command. The HTTP path is still evidence only and falls back to the
CLI by default.

Provider route authority observe is also default-off:

```bash
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE=1
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH=1
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE_THROTTLE_MS=1000
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE_MAX_IN_FLIGHT=2
```

This opt-in hook observes the paid-model `HubAI.Generate` hot path after Node
has selected its provider key. It fire-and-forgets the Rust route check, compares
only selected `account_key` truth, and never changes the Bridge request payload
or production provider routing. The hook exists to gather hot-path readiness
evidence without adding latency or moving provider secrets into Rust. The
observe hook has per-key throttling and a max in-flight cap so it cannot spawn
unbounded Rust CLI work during busy Generate traffic.

Authority prep also defaults to a Node/Rust account match gate. If a caller
passes the Node-selected `account_key`, Rust must select the same account or the
bridge returns fallback with
`rust_provider_route_authority_account_mismatch`. This keeps any future cutover
fail-closed instead of silently changing provider accounts.

Generate hot-path observe validation:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/provider_route_generate_observe_runner.command" --runs 5 --concurrency 1 --max-generate-ms 3000
```

Provider route candidate audit is a separate default-off evidence channel:

```bash
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE=1
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE_CACHE_MS=250
export XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE_CACHE_MAX_ENTRIES=128
```

When enabled, Node still selects the provider key and sends the existing Bridge
payload. The Rust route decision is collected asynchronously after Node's
selection and written as audit event
`ai.generate.provider_route_candidate` with ext schema
`xhub.rust_provider_route_candidate.audit.v1`. The event records Node/Rust
selected `account_key` match status, fallback reason codes, and decision counts;
it does not include provider API keys. The candidate hook never changes
production routing and any Rust failure is ignored by the Generate path.
When candidate audit is enabled, Generate skips the separate observe hook for
that request so the hot path starts only one Rust route process instead of two.
The candidate bridge also has a short TTL cache with single-flight coalescing:
identical in-flight route checks are merged, and recent decisions can be reused
briefly for audit-only evidence. Readiness runners set the cache to `0` so
gates still sample fresh Rust route decisions.

Candidate-audit smoke validation:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/provider_route_generate_observe_runner.command" --runs 3 --concurrency 1 --enable-candidate-audit --expect-candidate-ready --min-candidate-audits 3 --observe-throttle-ms 0 --observe-max-in-flight 2 --max-generate-ms 3000
```

The runner emits `candidate_readiness` with schema
`xhub.provider_route_candidate_audit_readiness.v1`. The readiness checks cover
event coverage, schema stability, Node/Rust selected account match, fallback
count, suspected secret leakage, and Generate latency.

Combined provider cutover readiness:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/provider_route_cutover_readiness_runner.command" --shadow-runs 3 --candidate-runs 3 --expect-ready
```

This emits `readiness` with schema
`xhub.provider_route_cutover_readiness.v1`. It combines provider shadow compare
readiness, readiness-gated authority prep, fail-closed account mismatch probing,
the `GetProviderKeyRouteDecision` service-boundary prep hook, Generate candidate
audit readiness, and Generate latency. It is still evidence only; no production
provider routing switch is performed.

Provider authority dry-run plan:

```bash
bash "/Users/andrew.xie/Documents/AX/rust/rust hub/tools/provider_route_authority_plan_runner.command" --shadow-runs 3 --candidate-runs 3 --expect-ready
```

This emits `plan` with schema
`xhub.provider_route_authority_dry_run_plan.v1`. The plan lists the environment
variables for a manual prep-only trial, rollback variables to unset, and
blocked actions. It explicitly reports `production_authority_change=false` and
`node_remains_provider_authority=true`.

Shadow HTTP endpoints:

- `GET /health`
- `GET /ready`
- `GET /runtime/scheduler_status`
- `GET /contract/proto_summary`
- `GET /xt/classic-hub-compat`
- `POST /xt/classic-hub-compat/write-status`
- `GET /xt/file-ipc-shadow`
- `POST /xt/file-ipc-shadow/respond-once`
- `POST /xt/file-ipc-shadow/drain`
- `POST /xt/file-ipc-shadow/cycle`
- `POST /xt/file-ipc-shadow/supervise`
- `POST /xt/file-ipc-shadow/runtime-execution-plan`
- `POST /xt/file-ipc-shadow/runtime-adapter-candidate`
- `GET /memory/readiness`
- `GET /memory/search`
- `GET /memory/project-role-transcript`
- `POST /memory/retrieve`
- `POST /memory/write`
- `POST /skills/execute`

For non-loopback clients, every endpoint except `/health` is protected by the
Rust HTTP access-key gate. Localhost bridges remain unchanged unless
`XHUB_RUST_HTTP_REQUIRE_ACCESS_KEY=1` is explicitly set.

Live XT file IPC status writing is explicit-cutover only. After production
session apply, `xhubd` refreshes the live `hub_status.json` heartbeat and
`/ready.capabilities.xt_file_ipc_production_surface_ready` reflects the fresh
live Rust-owned status. The background heartbeat uses a fast refresh path after
the first explicit cutover write, so classic gRPC transport jitter does not
stall the live file heartbeat. `GET /xt/classic-hub-compat` also uses that
Rust-owned live fast path after cutover, so monitoring does not add gRPC probe
latency to every cycle. The production session sets a 1000 ms heartbeat
interval with a bounded 2000 ms status lease. In explicit live cutover, the
heartbeat starts in trusted fast refresh and prefers write-temp plus atomic
rename under the same explicit production gates. If macOS denies temporary-file
creation in the live Group Container, the writer falls back to a locked
in-place overwrite of the existing Rust-owned status file. Request-path
readiness and compat probes use the process-local live overlay instead of
opening or statting the Group Container status file during live cutover. Long
filesystem writes are followed by an immediate
fresh-timestamp retry. Readiness and compat
diagnostics use raw Rust-owned live status summaries after cutover. The live
heartbeat soak verifier discovers the configured live base dir from
`/xt/classic-hub-compat` unless `--live-base-dir` is supplied, then reads the
status file through a bounded child process. That avoids false failures when an
old Group Container status exists but the current live base dir is
`/Users/andrew.xie/RELFlowHub`, and verifier-side filesystem stalls are
reported instead of hanging the gate. Validate it with:

```bash
bash tools/xt_file_ipc_live_heartbeat_soak.command --duration-ms 30000 --interval-ms 2000 --max-status-age-ms 5000
```

Post-cutover shadow smokes remain isolated and production-aware. The run-once
and background watcher smokes now report live production-surface observation
separately from their temporary shadow processor status, so ops gates can keep
verifying shadow safety after live cutover.

The production-compatible gRPC surface starts in Phase 1 of
`docs/RUST_HUB_EXECUTION_PLAN.md`.

Rust Hub now has explicit production-capable memory writer and skills execution
surfaces. They stay fail-closed unless the dedicated memory writer and skills
execution authority variables are all enabled. The XT classic `hub_status.json`
compatibility writer can be live only after explicit cutover and rollback gates
pass.

`RHM-123` hardens ordinary X-Hub.app restarts after production cutover. The
non-UI Node sidecar launcher now preserves launchd-provided provider/model and
scheduler production authority keys, preserves the live `XHUB_RUST_HUB_ROOT`,
and removes memory writer / skills execution authority keys from the Node
environment. This keeps provider/model and scheduler production authority stable
across app relaunches without changing SwiftUI product surfaces.

`RHM-124` refreshes live post-cutover supervision without changing the active
root. The current production root stays on the already applied package while a
new 8h live stability session and 4h rolling checkpoint sidecar monitor status
freshness, authority drift, recent slow-request deltas, UI compatibility, and
secret leakage. The first rolling checkpoint passed with memory writer and
skills execution authority still blocked.

`RHM-125` adds the production-gated Rust memory writer and governed skills
execution surface. `POST /memory/write` writes canonical JSON memory entries
only when all memory writer authority gates are set. `POST /skills/execute`
runs only after durable pin/grant preflight and audit, with built-in healthcheck
support and restricted process execution. The production smoke verifies writes,
retrieval, execution, secret denial, and no `detail_json` leakage.

`RHM-126` makes that migration live-cutover ready. The launchd manager now
passes explicit memory/skills authority keys into the Rust daemon, syncs the
built-in `rust-authority-healthcheck` skill, and ops/watchdog/stability gates
now default to requiring Rust memory writer plus skills execution authority.
Use `--no-require-memory-skills-production` only for explicit pre-cutover
rehearsal.

`RHM-127` converges the live active root to the final package-store Rust Hub
root after memory/skills cutover. Both launchctl `XHUB_RUST_HUB_ROOT` and the
`current` package symlink point at `rust-hub-20260513T072202Z`, X-Hub has been
relaunched so Node inherits that root, and the package-store long stability
session plus rolling checkpoint sidecar are supervising the live daemon with
Rust memory writer and skills execution required.

`RHM-128` adds the domain/tunnel cross-network path. `--public-base-url` and
`--public-endpoint` let a localhost-bound daemon sit behind Cloudflare Tunnel,
Tailscale, Headscale, or a VPS reverse tunnel while still forcing access-key
auth for operational APIs. The pairing export writes a private XT pairing
bundle, and the domain smoke verifies unauthorized rejection plus authenticated
readiness before XT uses the domain away from the first LAN setup.

`RHM-129` adds the domain activation plan. It keeps live local mode unchanged
until a real HTTPS domain/tunnel is supplied, then prints the exact commands to
initialize the key, update the existing local daemon label into public-endpoint
mode, install the watchdog, export the XT pairing bundle, smoke the public URL,
and roll back to local mode.

`RHM-132` adds a cross-network remote route semantics gate and wires it into the
domain activation plan. Stable HTTPS DNS and tailnet DNS are accepted, raw
VPN/tailnet/private IPs require an explicit allowance, and raw public IP,
loopback, LAN-only, link-local, and wildcard entries are blocked before the
daemon or XT pairing bundle can be activated as remote-ready.

`RHM-133` adds the cross-network remote route doctor. It reuses the route gate
and adds non-mutating DNS, tailnet, public `/health`, unauthorized `/ready`, and
optional authenticated `/ready` diagnostics, with planning-safe `--no-network`
mode and strict post-activation `--require-live-http --require-auth-ready` mode.

Bridge command details: `docs/SCHEDULER_BRIDGE_CLI.md`.
Provider route command details: `docs/PROVIDER_ROUTE_CLI.md`.
Remote/local model management plan: `docs/MODEL_MANAGEMENT_EXECUTION_PLAN.md`.
Node Hub opt-in details: `docs/NODE_HUB_SHADOW_COMPARE_INTEGRATION.md`.
