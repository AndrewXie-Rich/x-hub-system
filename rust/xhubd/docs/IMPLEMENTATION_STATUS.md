# Rust Hub Implementation Status

Updated: 2026-05-13

## Active Slice

Execution plan: `docs/RUST_HUB_EXECUTION_PLAN.md`
Model management plan: `docs/MODEL_MANAGEMENT_EXECUTION_PLAN.md`

Current slice:

- Work claim 2026-04-30: `RHM-002` and `RHM-004` were executed in
  `crates/xhub-provider`; no other local `cargo`/`xhubd`/provider-route process
  was running at claim time.
- Work claim 2026-04-30: `RHM-003` was executed in `crates/xhub-provider` and
  `crates/xhubd`; no other persistent local `cargo`/`xhubd`/provider-route
  process was running at claim time.
- Work claim 2026-04-30: `RHM-005` was executed in `crates/xhub-provider`,
  `crates/xhub-runtime`, and `crates/xhubd`; no other persistent local
  `cargo`/`xhubd`/model-inventory process was running at claim time.
- Work claim 2026-05-05: `RHM-006` and `RHM-007` were executed in
  `crates/xhub-runtime` and `crates/xhubd`; no other persistent local
  `cargo`/`xhubd`/model-inventory process was running at claim time.
- Work claim 2026-05-05: `RHM-008` was executed in
  `crates/xhubd/src/model_bridge.rs`; no other persistent local
  `cargo`/`xhubd`/model-route process was running at claim time.
- Work claim 2026-05-05: `RHM-010` fixture/presentation parity was executed in
  `x-hub-system/x-terminal`; no other persistent local
  `cargo`/`xhubd`/Swift/Xcode model-inventory process was running at claim
  time.
- Work claim 2026-05-05: `RHM-011` default-off live XT/Rust model inventory
  bridge was executed in `crates/xhubd` and `x-hub-system/x-terminal`; no
  other persistent local `cargo`/`xhubd`/Swift/Xcode model-inventory process was
  running at claim time.
- Work claim 2026-05-05: `RHM-012` sustained model inventory shadow evidence
  runner was executed in `tools` and `docs`; no persistent local
  `cargo`/`xhubd`/Swift/Xcode model-inventory process was running at claim
  time.
- Work claim 2026-05-06: `RHM-013` real-runtime model inventory evidence mode
  was executed in `tools` and `docs`; no persistent local `cargo`/`xhubd`
  model-inventory process was running at claim time.
- Work claim 2026-05-06: `RHM-014` model route HTTP prep was executed in
  `crates/xhubd`, `tools`, and `docs`; no persistent local `cargo`/`xhubd`
  model-route process was running at claim time.
- Work claim 2026-05-06: browser status page for Rust Hub daemon was executed
  in `crates/xhubd` and docs; existing local `xhubd` was restarted after tests
  passed.
- Work claim 2026-05-06: `RH-0005c` LAN HTTP access-key gate was executed in
  `crates/xhub-core`, `crates/xhubd`, `tools`, `config`, and `docs`; no
  persistent local `xhubd` process was running at claim time.
- Work claim 2026-05-06: `RH-0005d` LAN access-key and LaunchAgent smoke was
  executed in `tools`, packaging, and docs; no persistent local `xhubd` process
  was running at claim time.
- Work claim 2026-05-06: `RH-0401` through `RH-0403` first Rust memory
  retrieval shadow read path was executed in `crates/xhub-memory`, `crates/xhubd`,
  `tools`, packaging, and docs; no persistent local `xhubd` process was running
  at claim time.
- Work claim 2026-05-06: `RH-0403b` memory retrieval warm daemon HTTP smoke was
  executed in `tools`, packaging, and docs; no persistent local `xhubd` process
  was running at claim time.
- Work claim 2026-05-06: `RHM-015` UI compatibility preservation contract was
  executed in `docs`; no persistent local `cargo`/`xhubd`/Swift/Xcode UI
  compatibility process was running at claim time.
- Work claim 2026-05-06: `RHM-015b` UI compatibility no-product-change package
  gate was executed in `tools`, packaging, and docs; no SwiftUI product surface
  files were edited.
- Work claim 2026-05-06: `RHM-016` model route authority prep bridge was
  executed in `x-hub-system/x-hub/grpc-server/hub_grpc_server` and `docs`;
  only the existing local `xhubd` daemon was running at claim time.
- Work claim 2026-05-06: `RHM-017` model route candidate evidence runner was
  executed in `tools` and `docs`; only the existing local `xhubd` daemon was
  visible at claim time.
- Work claim 2026-05-06: `RHM-018` local model route candidate coverage was
  executed in `tools` and `docs`; no persistent local `xhubd`/cargo/Swift
  process was visible at claim time.
- Work claim 2026-05-06: `RHM-019` skills catalog policy gate was executed in
  `crates/xhub-skills`, `crates/xhubd`, `tools`, packaging, and docs; no Swift
  UI files were edited and Rust skill execution authority remained disabled.
- Work claim 2026-05-06: `RHM-020` model route combined candidate evidence
  report was executed in `tools`, packaging, and docs; only the existing local
  `xhubd` daemon was visible at claim time.
- Work claim 2026-05-06: `RHM-021` skills preflight grant/audit gate was
  executed in `crates/xhub-skills`, `crates/xhubd`, `tools`, and docs; no
  Swift UI files were edited and Rust still does not execute third-party skill
  code.
- Work claim 2026-05-06: `RHM-022` skills durable pin/grant/audit storage was
  executed in `crates/xhub-db`, `crates/xhub-skills`, `crates/xhubd`, `tools`,
  migrations, and docs; no Swift UI files were edited and Rust skill execution
  authority remained disabled.
- Work claim 2026-05-06: `RHM-023` model route selected-model authority plan
  was executed in `tools`, packaging, and docs; no Node/XT selected-model
  authority was changed.
- Work claim 2026-05-06: `RHM-024` skills preflight audit retention was
  executed in `crates/xhub-db`, `crates/xhub-skills`, `crates/xhubd`, `tools`,
  and docs; no Swift UI files were edited and Rust skill execution authority
  remained disabled.
- Work claim 2026-05-06: `RHM-025` skills policy revocation was executed in
  `crates/xhub-db`, `crates/xhubd`, `tools`, and docs; no Swift UI files were
  edited and Rust skill execution authority remained disabled.
- Work claim 2026-05-06: `RHM-027` skills policy event audit trail was
  executed in `crates/xhub-db`, `crates/xhub-skills`, `crates/xhubd`,
  migrations, `tools`, and docs; no Swift UI files were edited and Rust skill
  execution authority remained disabled.
- Work claim 2026-05-06: `RHM-029` skills policy event retention was executed
  in `crates/xhub-db`, `crates/xhub-skills`, `crates/xhubd`, `tools`, and docs;
  no Swift UI files were edited and Rust skill execution authority remained
  disabled.
- Work claim 2026-05-06: `RHM-026` model route prep trial smoke was executed
  in `tools`, packaging, and docs; Node/XT selected-model authority remained
  unchanged.
- Work claim 2026-05-06: `RHM-028` model route prep sustained evidence was
  executed in `tools`, packaging, and docs; only the existing local `xhubd`
  daemon was visible at claim time and Node/XT selected-model authority
  remained unchanged.
- Work claim 2026-05-06: `RHM-030` skills policy store readiness was executed
  in `crates/xhub-db`, `crates/xhub-skills`, `crates/xhubd`, `tools`, and
  docs; no Swift UI files were edited and Rust skill execution authority
  remained disabled.
- Work claim 2026-05-07: `RHM-031` model route report diagnostics was
  executed in `crates/xhubd`, packaging, and docs; no persistent local
  `xhubd`/cargo/Swift/model-route process was visible at claim time and
  Node/XT selected-model authority remained unchanged.
- Work claim 2026-05-07: `RHM-032` ops readiness gate was executed in `tools`,
  packaging, and docs; no Swift UI files were edited, Node remains production
  authority, and Rust memory/skills execution authority remains disabled.
- Work claim 2026-05-07: `RHM-033` ready cache stutter guard was executed in
  `crates/xhubd`, `tools`, packaging, and docs; no Swift UI files were edited
  and cached readiness does not enable production authority.
- Work claim 2026-05-07: `RHM-034` memory/skills snapshot cache was executed in
  `crates/xhub-memory`, `crates/xhubd`, `tools`, packaging, and docs; no Swift
  UI files were edited and Rust memory writer plus skills execution authority
  remain disabled.
- Work claim 2026-05-07: `RHM-035` HTTP backpressure guard was executed in
  `crates/xhubd`, `tools`, packaging, and docs; `/health` remains exempt,
  business routes are bounded, and production authority remains unchanged.
- Work claim 2026-05-07: `RHM-036` HTTP latency metrics was executed in
  `crates/xhubd`, `tools`, packaging, and docs; metrics are diagnostics-only,
  sanitized, and do not expose request bodies or `detail_json`.
- Work claim 2026-05-07: `RHM-037` ops soak runner was executed in `tools`,
  packaging, and docs; it uses one temporary warm daemon for sustained latency,
  cache, memory, skills, HTTP metrics, and UI compatibility evidence while
  leaving Node/XT authority unchanged.
- Work claim 2026-05-07: `RHM-038` launchd activation was executed in
  `tools/xhubd_daemon.js`, `README.md`, `docs/RHM_038_LAUNCHD_ACTIVATION.md`,
  and this status file. Scope: user-level LaunchAgent install/status/uninstall
  for the existing Rust Hub shadow HTTP daemon only. No production authority
  change, no memory/skills/model authority transfer. The user LaunchAgent runs
  from an Application Support runtime copy to avoid macOS Documents privacy
  denial for background services.
- Work claim 2026-05-07: `RHM-039` daemon ops report was executed in
  `tools/xhubd_daemon.js`, `tools/daemon_ops_report.command`, packaging, and
  docs. Scope: read-only health/readiness/launchd/http-metrics/UI/redacted-log
  evidence for long-running daemons. No daemon restart, no production authority
  change, no memory write authority, no skills execution authority, and no XT
  UI change.
- Work claim 2026-05-07: `RHM-040` daemon maintenance retention was executed in
  `tools/xhubd_daemon.js`, `tools/daemon_maintenance.command`, packaging, and
  docs. Scope: dry-run-by-default log/report retention for long-running daemon
  installs. It only mutates local log/report files when `--apply` is passed and
  never restarts the daemon or changes production authority.
- Work claim 2026-05-07: `RHM-041` XT classic Hub compatibility preflight was
  executed in `crates/xhubd/src/xt_compat.rs`, `crates/xhubd/src/main.rs`, and
  docs. Scope: read-only HTTP preflight for XT classic `hub_status.json`
  candidate paths and compatibility cutover blockers. Existing XT, classic
  X-Hub, Node sidecar, Python runtime, and launchd Rust xhubd daemons were
  running; no local `cargo`/Swift build or test process was running at claim
  time. Default diagnostics and launchd profiles still do not write
  `hub_status.json`, do not mark XT `hubInteractive`, do not start production
  gRPC compatibility, and do not change production authority.
- Work claim 2026-05-07: `RHM-038b` launchd runtime signing follow-up was
  executed in `tools/xhubd_daemon.js`, `README.md`,
  `docs/RHM_038_LAUNCHD_ACTIVATION.md`, and this status file. Existing XT,
  classic X-Hub, Node sidecar, Python runtime, and launchd Rust xhubd daemons
  were running; no local `cargo`/Swift build or test process was running at
  claim time. Scope: sign the copied launchd runtime binary before bootstrap to
  avoid stale macOS code-signature rejection. No production authority change.
- Work claim 2026-05-07: `RHM-042` XT classic gRPC compatibility probe was
  executed in `crates/xhubd/src/xt_compat.rs`, `crates/xhubd/src/main.rs`,
  `README.md`, `docs/RHM_041_XT_CLASSIC_COMPAT_PREFLIGHT.md`,
  `docs/RHM_042_XT_CLASSIC_GRPC_COMPAT_PROBE.md`, and this status file.
  Existing XT, classic X-Hub, Node sidecar, Python runtime, and launchd Rust
  xhubd daemons were running; no local `cargo`/Swift build or test process was
  running at claim time. Scope: opt-in `HubRuntime.GetSchedulerStatus` probe
  for the XT classic compatibility gate. Default launchd/local profiles still
  do not write `hub_status.json`, do not mark XT `hubInteractive`, and do not
  change production authority.
- Work claim 2026-05-07: `RHM-043` daemon ops gate was executed in
  `tools/xhubd_daemon.js`, `tools/daemon_ops_gate.command`, packaging, README,
  and docs. Existing XT, classic X-Hub, Node sidecar, Python runtime, and the
  launchd Rust xhubd daemon were running; no local `cargo`/Swift build or test
  process was running at claim time. Scope: read-only daily/manual gate for
  health, readiness, launchd status, HTTP latency metrics, maintenance dry-run,
  redacted logs, UI compatibility, and authority boundaries. It never restarts
  or stops the daemon, never applies retention, never changes production
  authority, never writes canonical memory, never executes third-party skills,
  and does not change XT UI.
- Work claim 2026-05-07: `RHM-044` HTTP metrics recent window was executed in
  `crates/xhubd/src/main.rs`, `tools/xhubd_daemon.js`,
  `tools/ops_soak_runner.js`, README, and docs. Existing XT, classic X-Hub,
  Node sidecar, Python runtime, and the launchd Rust xhubd daemon were running;
  no local `cargo`/Swift build or test process was running at claim time.
  Scope: bounded in-memory recent HTTP latency samples for current stutter
  diagnosis, plus ops-gate recent slow-request budget fallback. It records no
  request bodies, no query strings, no `detail_json`, and no secrets. It does
  not change production authority, memory writer authority, skills execution
  authority, or XT UI.
- Work claim 2026-05-07: `RHM-045` XT classic status writer rollback gate was
  executed in `crates/xhubd/src/xt_compat.rs`, `crates/xhubd/src/main.rs`,
  `README.md`, `docs/RHM_042_XT_CLASSIC_GRPC_COMPAT_PROBE.md`,
  `docs/RHM_045_XT_CLASSIC_STATUS_WRITER_ROLLBACK_GATE.md`, and this status
  file. Existing XT, classic X-Hub, Node sidecar, Python runtime, and the
  launchd Rust xhubd daemon were running; no local `cargo`/Swift build or test
  process was running at claim time. Scope: explicit-cutover-only POST writer
  and rollback contract. Default launchd/local profiles still cannot write
  `hub_status.json`; real profiles must not enable the file-IPC-ready gate until
  Rust implements XT local file IPC execution.
- Work claim 2026-05-07: `RHM-046` HTTP I/O timeouts were executed in
  `crates/xhubd/src/main.rs`, `tools/ops_soak_runner.js`, README, and docs.
  Existing XT, classic X-Hub, Node sidecar, Python runtime, and the launchd
  Rust xhubd daemon were running; no local `cargo`/Swift build or test process
  was running at claim time. Scope: bounded per-connection HTTP read/write
  timeouts to prevent slow or half-open clients from holding worker threads
  indefinitely. It does not change production authority, memory writer
  authority, skills execution authority, or XT UI.
- Work claim 2026-05-07: `RHM-047` XT file IPC shadow responder was executed
  in `crates/xhubd/src/xt_file_ipc.rs`, `crates/xhubd/src/main.rs`, README,
  and docs. Existing XT, classic X-Hub, Node sidecar, Python runtime, and the
  launchd Rust xhubd daemon were running; no local `cargo`/Swift build or test
  process was running at claim time. Scope: temporary-dir-only one-shot
  fail-closed response writer for XT `ai_requests` / `ai_responses` contract
  validation. It does not watch real XT directories, does not execute ML, does
  not set `XHUB_RUST_XT_CLASSIC_FILE_IPC_READY`, and does not change
  production authority.
- Work claim 2026-05-07: `RHM-048` XT file IPC shadow drain processor was
  executed in `crates/xhubd/src/xt_file_ipc.rs`, `crates/xhubd/src/main.rs`,
  README, and docs. Existing XT, classic X-Hub, Node sidecar, Python runtime,
  and the launchd Rust xhubd daemon were running; no local `cargo`/Swift build
  or test process was running at claim time. Scope: temporary-dir-only bounded
  manual drain for multiple XT `req_<id>.json` files, still writing only
  fail-closed JSONL responses when explicitly enabled. It does not start a
  watcher, does not publish heartbeat/status, does not execute ML, does not set
  `XHUB_RUST_XT_CLASSIC_FILE_IPC_READY`, and does not change production
  authority.
- Work claim 2026-05-07: `RHM-049` XT file IPC shadow processor cycle was
  executed in `crates/xhubd/src/xt_file_ipc.rs`, `crates/xhubd/src/main.rs`,
  README, and docs. Existing XT, classic X-Hub, Node sidecar, Python runtime,
  and the launchd Rust xhubd daemon were running; no local `cargo`/Swift build
  or test process was running at claim time. Scope: temporary-dir-only manual
  processor cycle that wraps bounded drain and writes a Rust-owned
  `rust_file_ipc_shadow_processor_status.json` status artifact only under
  explicit shadow apply gates. It does not write `hub_status.json`, does not
  start a watcher, does not execute ML, does not set
  `XHUB_RUST_XT_CLASSIC_FILE_IPC_READY`, and does not change production
  authority.
- Work claim 2026-05-07: `RHM-050` XT file IPC shadow supervisor loop was
  executed in `crates/xhubd/src/xt_file_ipc.rs`, `crates/xhubd/src/main.rs`,
  README, and docs. Existing XT, Python runtime, and the launchd Rust xhubd
  daemon were running; no local `cargo`/Swift build or test process was running
  at claim time, and classic X-Hub/Node was not visible in the process list.
  Scope: bounded synchronous HTTP supervisor loop over temporary-dir-only
  manual processor cycles. It stops before returning, does not leave a
  background watcher running, does not write `hub_status.json`, does not execute
  ML, does not set `XHUB_RUST_XT_CLASSIC_FILE_IPC_READY`, and does not change
  production authority.
- Work claim 2026-05-07: `RHM-051` daemon watchdog guard was executed in
  `tools/xhubd_daemon.js`, `tools/daemon_watchdog.command`, packaging, README,
  and docs. Existing XT, classic X-Hub, Node sidecar, Python runtime, and the
  launchd Rust xhubd daemon were running; no local `cargo`/Swift build or test
  process was running at claim time. Scope: dry-run/report-only long-running
  launchd/readiness/stutter/pid-file guard, with optional explicit stale-pid
  cleanup only. It does not stop, restart, bootstrap, uninstall, or change
  production authority.
- Work claim 2026-05-07: `RHM-052` watchdog launchd timer was executed in
  `tools/xhubd_daemon.js`, README, packaging, and docs. Existing XT, Python
  runtime, and the launchd Rust xhubd daemon were running; no local
  `cargo`/Swift build or test process was running at claim time. Scope:
  user-level LaunchAgent timer plist/install/status/uninstall support for
  periodic dry-run watchdog reports. Verification used dry-run timer install
  and uninstall only; it did not install a persistent timer, did not restart the
  daemon, and did not change production authority.
- Work claim 2026-05-07: `RHM-059` XT file IPC shadow watcher smoke was
  executed in `crates/xhubd/src/xt_file_ipc.rs`, `crates/xhubd/src/main.rs`,
  README, and docs. Existing XT, Python runtime, and the launchd Rust xhubd
  daemon were running; no local `cargo`/Swift build or test process was running
  at claim time, and classic X-Hub/Node was not visible in the process list.
  Scope: temporary-dir-only watcher lifecycle smoke with Rust-owned lock and
  watcher status artifacts. It stops before returning, does not leave a
  background watcher running, does not write `hub_status.json`, does not execute
  ML, does not set `XHUB_RUST_XT_CLASSIC_FILE_IPC_READY`, and does not change
  production authority.
- Work claim 2026-05-07: `RHM-061` XT file IPC shadow watcher rollback smoke
  was executed in `crates/xhubd/src/xt_file_ipc.rs`, `crates/xhubd/src/main.rs`,
  README, and docs. Existing XT, Python runtime, and the launchd Rust xhubd
  daemon were running; no local `cargo`/Swift build or test process was running
  at claim time, and classic X-Hub/Node was not visible in the process list.
  Scope: temporary-dir-only rollback smoke that can remove only Rust-owned
  shadow watcher/processor artifacts under explicit rollback apply gates. It
  never removes `hub_status.json` or XT response files, does not execute ML,
  does not set `XHUB_RUST_XT_CLASSIC_FILE_IPC_READY`, and does not change
  production authority.
- Work claim 2026-05-07: `RHM-064` XT file IPC watcher readiness gate was
  executed in `crates/xhubd/src/xt_file_ipc.rs`, `crates/xhubd/src/main.rs`,
  README, and docs. Existing XT, Python runtime, and the launchd Rust xhubd
  daemon were running; no local `cargo`/Swift build or test process was running
  at claim time, and classic X-Hub/Node was not visible in the process list.
  Scope: read-only temporary-dir watcher readiness diagnostics for directory
  shape, watcher enablement, runtime readiness, and rollback readiness. It
  writes no files, starts no watcher, keeps `ready=false`, does not set
  `XHUB_RUST_XT_CLASSIC_FILE_IPC_READY`, and does not change production
  authority.
- Work claim 2026-05-07: `RHM-066` XT file IPC watcher start plan was executed
  in `crates/xhubd/src/xt_file_ipc.rs`, `crates/xhubd/src/main.rs`, README,
  and docs. Existing XT, Python runtime, and the launchd Rust xhubd daemon were
  running; no local `cargo`/Swift build or test process was running at claim
  time, and classic X-Hub/Node was not visible in the process list. Scope:
  read-only default-off watcher start diagnostics that compose readiness with
  an explicit start-plan gate. It writes no files, starts no watcher, keeps
  `ready=false`, does not set `XHUB_RUST_XT_CLASSIC_FILE_IPC_READY`, and does
  not change production authority.
- Work claim 2026-05-07: `RHM-067` XT file IPC watcher run once was executed in
  `crates/xhubd/src/xt_file_ipc.rs`, `crates/xhubd/src/main.rs`, README, and
  docs. Existing XT, Python runtime, and the launchd Rust xhubd daemon were
  running; no local `cargo`/Swift build or test process was running at claim
  time, and classic X-Hub/Node was not visible in the process list. Scope:
  default-off temporary-dir one-shot watcher lifecycle that acquires/releases
  the Rust-owned lock, writes Rust-owned watcher status, and runs one bounded
  fail-closed processor cycle only under explicit apply gates. It starts no
  long-running watcher, keeps `ready=false`, does not set
  `XHUB_RUST_XT_CLASSIC_FILE_IPC_READY`, and does not change production
  authority.
- Work claim 2026-05-07: `RHM-068` XT file IPC watcher run once smoke was
  executed in `tools`, packaging, README, and docs. Existing XT, Python runtime,
  and the launchd Rust xhubd daemon were running; no local `cargo`/Swift build
  or test process was running at claim time, and classic X-Hub/Node was not
  visible in the process list. Scope: isolated temporary-daemon smoke evidence
  for one-shot watcher lock/status/response behavior. It uses temp directories,
  does not touch XT live paths, does not start launchd, does not execute ML,
  and does not change production authority.
- Work claim 2026-05-07: `RHM-071` XT file IPC watcher run once report was
  executed in `tools`, README, and docs. Existing XT, Python runtime, and the
  launchd Rust xhubd daemon were running; no local `cargo`/Swift build or test
  process was running at claim time, and classic X-Hub/Node was not visible in
  the process list. Scope: persisted JSON report support for the isolated
  run-once smoke. It changes only evidence collection and does not change Rust
  runtime behavior, XT live paths, ML execution, or production authority.
- Work claim 2026-05-07: `RHM-072` XT file IPC run once ops gate was executed
  in `tools/xhubd_daemon.js`, README, and docs. Existing XT, Python runtime,
  and the launchd Rust xhubd daemon were running; no local `cargo`/Swift build
  or test process was running at claim time, and classic X-Hub/Node was not
  visible in the process list. Scope: optional default-off ops-gate integration
  for isolated XT file IPC run-once smoke evidence. Default ops-gate behavior
  remains unchanged; the opt-in smoke uses temp directories, does not touch XT
  live paths, does not execute ML, and does not change production authority.
- Work claim 2026-05-07: `RHM-079` XT file IPC run once ops report was executed
  in `tools/xhubd_daemon.js`, README, and docs. Existing XT and the launchd
  Rust xhubd daemon were running; no local `cargo`/Swift build or test process
  was running at claim time, and classic X-Hub/Node was not visible in the
  process list. Scope: optional default-off ops-report integration for isolated
  XT file IPC run-once smoke evidence. It records evidence only, uses temp
  directories when enabled, and does not touch XT live paths, execute ML, start
  a long-running watcher, write `hub_status.json`, or change production
  authority.
- Work claim 2026-05-08: `RHM-080` XT file IPC watcher session was executed in
  `crates/xhubd/src/xt_file_ipc.rs`, `crates/xhubd/src/main.rs`, README, and
  docs. Existing XT and the launchd Rust xhubd daemon were running; no local
  `cargo`/Swift build or test process was running at claim time, and classic
  X-Hub/Node was not visible in the process list. Scope: default-off bounded
  watcher-session lifecycle under explicit temp-dir and apply gates. It does
  not touch XT live paths, execute ML, start a long-running watcher, write
  `hub_status.json`, mark production file IPC ready, or change production
  authority.
- Work claim 2026-05-08: `RHM-083` XT file IPC background watcher lifecycle was
  executed in `crates/xhubd/src/xt_file_ipc.rs`, `crates/xhubd/src/main.rs`,
  README, and docs. Existing XT and the launchd Rust xhubd daemon were running;
  no local `cargo`/Swift build or test process was running at claim time, and
  classic X-Hub/Node was not visible in the process list. Scope: default-off,
  bounded, single-instance background watcher lifecycle under explicit temp-dir
  and apply gates. It does not touch XT live paths, execute ML, write
  `hub_status.json`, mark production file IPC ready, or change production
  authority.
- Work claim 2026-05-07: `RHM-058` cross-network readiness gate was executed
  in `tools/xhubd_daemon.js`, `tools/cross_network_readiness_gate.command`,
  README, and docs. Existing XT, Python runtime, and the launchd Rust xhubd
  daemon were running; no local `cargo`/Swift build or test process was running
  at claim time. Scope: non-mutating LAN/cross-device deployment readiness
  evidence for public host, access-key file, launchd wiring, watchdog timer
  installability, UI compatibility, and authority boundaries. It does not start,
  stop, restart, bootstrap, install, uninstall, or change production authority.
- Work claim 2026-05-07: `RHM-062` cross-network installed gate was executed in
  `tools/cross_network_installed_gate.command`, packaging, README, and docs.
  Existing XT, Python runtime, and the launchd Rust xhubd daemon were running;
  no local `cargo`/Swift build or test process was running at claim time.
  Scope: strict read-only shortcut requiring live `/ready`, daemon LaunchAgent
  loaded state, and watchdog timer LaunchAgent loaded state for future LAN
  always-on deployment validation. It does not install or mutate launchd state.
- Work claim 2026-05-07: `RHM-065` cross-network install plan was executed in
  `tools/xhubd_daemon.js`, `tools/cross_network_install_plan.command`,
  packaging, README, and docs. Existing XT, Python runtime, and the launchd
  Rust xhubd daemon were running; no local `cargo`/Swift build or test process
  was running at claim time. Scope: non-mutating JSON command plan for LAN
  readiness, access-key init, daemon/timer dry-runs, install commands, strict
  installed gate, and rollback commands. It does not execute the plan.
- RH-0001 workspace: done
- RH-0002 proto mirror: done
- RH-0003 command wrappers: done
- RH-0003b warm daemon manager command (`tools/xhubd_daemon.command`): done
- RH-0004 doctor command: done
- RH-0005 shadow HTTP serve: done
- RH-0005b shadow HTTP readiness endpoint and LAN bind fail-closed guard: done
- RH-0005c non-loopback Rust HTTP access-key gate, readiness check, daemon
  profile wiring, and non-secret access key file init command: done
- RH-0005d packageable LAN access-key + LaunchAgent no-secret smoke command:
  done
- RH-0401 memory retrieval mode profiles for `project_code` and
  `assistant_personal`: first implementation done
- RH-0402 read-only retrieval document builder for local `.json`, `.jsonl`,
  `.md`, and `.txt` memory files: first implementation done
- RH-0403 local lexical index/scan path with `xt.memory_retrieval_result.v1`
  output, CLI, HTTP, readiness, and smoke: first implementation done
- RH-0403b packageable memory retrieval HTTP smoke covering `/ready`,
  `/memory/readiness`, `/memory/search`, and `POST /memory/retrieve`: done
- RH-0101 tonic/prost proto generation: done
- RH-0102 shadow gRPC server scaffold: done
- RH-0103 `HubRuntime.GetSchedulerStatus` shadow response: implemented,
  gRPC socket smoke passed
- RH-0201 scheduler schema: done
- RH-0202 scheduler fair queue core: first DB-backed implementation done
- RH-0203 `HubRuntime.GetSchedulerStatus` DB-backed read path: first
  compatible path done; write actions remain internal/shadow-only
- `xhubd scheduler-smoke`: done
- `xhubd scheduler ...` JSON bridge CLI: done
- `xhubd scheduler claim` atomic enqueue-and-fair-lease authority primitive:
  done
- scheduler shadow-compare reports: done
- `tools/node_scheduler_shadow_compare.js` Node shadow caller prototype: done
- Node Hub opt-in `GetSchedulerStatus` shadow compare hook: done
- `xhubd scheduler reports` evidence summary command: done
- `tools/node_hub_shadow_compare_smoke.js` one-shot Node service smoke: done
- `tools/node_hub_shadow_compare_runner.js` live Node Hub runner/monitor: done
- Node Hub opt-in Rust scheduler status read bridge: done
- Node Hub opt-in Rust scheduler status readiness gate: done
- Node Hub Rust scheduler status bridge async/non-blocking process execution:
  done
- Node Hub Rust scheduler status bridge short TTL cache and single-flight read
  coalescing: done
- `xhubd serve` daemon HTTP `GET /scheduler/status` and
  `GET /scheduler/cutover-readiness` endpoints: done
- Node Hub Rust scheduler status bridge default-off HTTP-first daemon read with
  CLI fallback: done
- `tools/scheduler_status_http_bridge_smoke.command`: done
- Node Hub opt-in Rust scheduler authority bridge using `scheduler claim`: done
- `xhubd serve` daemon HTTP `POST /scheduler/claim`,
  `POST /scheduler/acquire-run`, `POST /scheduler/release`, and
  `POST /scheduler/cancel` endpoints: done
- Node Hub Rust scheduler authority bridge default-off HTTP-first daemon
  readiness/claim/release/cancel with CLI fallback: done
- `tools/scheduler_authority_http_bridge_smoke.command`: done
- Node Hub opt-in Rust scheduler lease shadow bridge: done
- Node Hub Rust scheduler lease shadow bridge default-off HTTP-first daemon
  enqueue/acquire-run/release/cancel with CLI fallback: done
- `tools/scheduler_lease_shadow_http_bridge_smoke.command`: done
- `xhubd scheduler lease-shadow-report` evidence summary command: done
- `xhubd scheduler cutover-readiness` fail-closed readiness gate: done
- `tools/scheduler_cutover_readiness_runner.js` automated evidence runner: done
- `tools/scheduler_authority_runner.js` full Node paid AI Generate path through
  Rust scheduler authority with isolated fake Bridge: done
- `tools/scheduler_authority_runner.js` queued cancel/timeout terminal
  scenarios for Rust authority: done
- `tools/node_hub_authority_live_runner.js` real Node Hub process + gRPC paid
  AI authority smoke with shared Node/Rust SQLite state: done
- `tools/node_hub_authority_live_runner.js` queued cancel/timeout terminal
  scenarios through real gRPC streams: done
- `tools/scheduler_production_authority_plan.js` scheduler-only production
  authority cutover plan with validation gates and rollback env: done
- `tools/scheduler_production_authority_apply.js` explicit Dock Agent
  LaunchAgent env apply/rollback for scheduler production authority: done
- `tools/scheduler_production_authority_session.js` single-app X-Hub launchctl
  session env apply/rollback for scheduler production authority: done
- `tools/scheduler_production_authority_session_launchd.js` persistent
  single-app session env LaunchAgent install/uninstall for scheduler production
  authority: done
- `tools/scheduler_production_authority_guard.js` one-shot scheduler production
  authority guard for effective/persistent authority, daemon health, slow
  request budget, and UI safety: done
- `tools/route_authority_cutover_guard.js` non-mutating provider/model route
  authority cutover readiness guard: done
- `tools/route_authority_prep_session.js` provider/model route prep session
  env apply/rollback with production authority still off: done
- `tools/route_authority_prep_runtime_guard.js` running X-Hub Node prep env
  inheritance guard: done
- `tools/route_authority_prep_sustained_guard.js` repeated live prep runtime,
  route readiness, scheduler authority, and daemon slow-request guard: done
- `tools/route_authority_prep_session_launchd.js` persistent provider/model
  route prep session LaunchAgent install/uninstall: done
- `tools/route_authority_production_cutover_blocker.js` machine-readable
  provider/model production authority blocker report: done
- `tools/route_authority_production_cutover_blocker.js` explicit provider/model
  production switch contract with prep/candidate-safe detection: done
- `tools/route_authority_production_session.js` explicit provider/model
  production env apply/rollback tool, managing only provider/model production
  keys: done
- Provider/model route production authority live cutover: done. The cutover was
  applied with a fresh sustained prep report, RELFlowHub was relaunched so the
  Node Hub process inherited provider/model production env, and the production
  runtime guard verified provider/model production authority effective while
  scheduler authority stayed effective and memory writer / skills execution
  production keys stayed absent.
- `tools/xt_file_ipc_production_session.js` explicit XT file IPC production
  env apply/rollback tool with non-temp live-base-dir and confirm-live-cutover
  gates, managing only file-IPC/classic-compat cutover keys: done
- `tools/xt_file_ipc_production_cutover_blocker.js` read-only XT file IPC live
  cutover blocker that checks daemon readiness, classic compat, prep/production
  env state, live-base-dir validity, and UI compatibility before any live
  writer apply: done
- `tools/xt_file_ipc_production_rollback_rehearsal.js` non-live XT file IPC
  production apply/rollback rehearsal that validates launchctl env restoration
  without daemon relaunch or write-status calls: done
- `tools/xt_file_ipc_live_cutover_preflight.js` final XT file IPC live cutover
  preflight that captures a write-before snapshot and emits apply, daemon
  relaunch, write-status smoke, and rollback plans without executing them: done
- `tools/active_root_upgrade_plan.js` non-mutating source/package active root
  alignment plan for smoother Rust Hub updates, with provider/model production
  authority detection that skips route prep commands after cutover: done
- `tools/active_root_upgrade_apply.js` dry-run-by-default source/package active
  root upgrade orchestrator with explicit apply/relaunch/validate gates and
  production-aware route guard selection: done
- Rust scheduler cross-process event/snapshot ID collision fix for concurrent
  CLI claims: done
- Node Hub authority runtime readiness allows active Rust authority runs by
  default to avoid mixed Rust/Node scheduling under concurrent load: done
- Rust provider routing shadow core and `xhubd provider route` JSON CLI: done
- `tools/provider_route_smoke.command` source/package provider routing smoke:
  done
- `xhubd serve` daemon HTTP `GET /provider/route` shadow route endpoint and
  `tools/provider_route_http_smoke.command`: done
- `xhubd serve` daemon HTTP `POST /provider/compare`, `GET /provider/reports`,
  and `GET /provider/readiness` provider evidence endpoints: done
- `xhubd serve` SQLite migration preflight before accepting HTTP requests to
  avoid first-request migration lock contention: done
- Node bridge HTTP-first provider route smoke with CLI fallback disabled:
  `tools/provider_route_http_bridge_smoke.command`: done
- Node shadow compare HTTP-first provider evidence smoke with CLI fallback
  disabled: `tools/provider_route_http_shadow_compare_smoke.command`: done
- Node Hub opt-in Rust provider route shadow compare for
  `HubProviderKeys.GetProviderKeyRouteDecision`: done
- `xhubd provider compare`, `provider reports`, and `provider readiness`
  evidence commands: done
- `tools/provider_route_shadow_compare_smoke.js` real Node service handler +
  Rust provider route shadow compare smoke: done
- `tools/provider_route_shadow_compare_runner.js` sustained provider route
  shadow compare evidence runner: done
- Node Hub read-only, readiness-gated Rust provider route authority prep bridge:
  done
- Node Hub default-off Rust provider route authority observe hook for
  paid-model `HubAI.Generate`, with per-key throttle and max in-flight cap:
  done
- Node Hub default-off Rust provider route candidate audit event for
  paid-model `HubAI.Generate`: done
- Node Hub Generate path skips duplicate observe route work when candidate
  audit is enabled, reducing candidate-readiness Rust CLI starts from two per
  request to one per request: done
- `tools/provider_route_generate_observe_runner.js` candidate audit readiness
  report and `--expect-candidate-ready` gate: done
- `tools/provider_route_cutover_readiness_runner.js` combined provider route
  cutover readiness gate: done
- `tools/provider_route_authority_plan_runner.js` default-off provider route
  authority dry-run plan: done
- Node Hub `GetProviderKeyRouteDecision` default-off, response-after Rust
  provider route authority prep service hook: done
- `tools/provider_route_shadow_compare_runner.js` validates the
  `GetProviderKeyRouteDecision` authority prep service hook and feeds
  `service_hook_ok` into combined cutover readiness: done
- Node provider route authority bridge default-off HTTP-first daemon route with
  CLI fallback: done
- Rust-specific remote/local model management execution plan: documented in
  `docs/MODEL_MANAGEMENT_EXECUTION_PLAN.md`
- `RHM-002` provider model ID alias normalization: done. Rust now canonicalizes
  `GPT5.5`, `gpt5.5`, and `openai/gpt5.5` to `gpt-5.5` for provider route
  output, account model matching, model-state lookup, and shadow compare
  normalization.
- `RHM-004` quota retry alignment: done. Rust provider routing now treats
  `quota.next_recover_at_ms` as a cooldown source alongside quota cooldown,
  error retry, and refresh retry timestamps.
- `RHM-003` provider candidate trace extension: done. Rust route decisions now
  include route-level `pool_id` and `routing_strategy`, and every candidate
  exposes `next_retry_at_ms` alongside `retry_at_ms` without serializing
  provider key or refresh-token material.
- `RHM-005` read-only model inventory CLI: done. `xhubd model inventory`
  returns `xhub.model_inventory.v1` with remote provider rows from
  `hub_provider_keys.json` and local rows from `models_state.json` when
  available; missing source files return empty arrays.
- `RHM-006` local artifact inventory reader: done. Local rows include display
  name, family key, artifact size, checksum, quantization, duplicate artifact
  marker, moved-artifact path resolution, known format detection, and
  stale/unsupported artifact blockers.
- `RHM-007` local runtime preflight: done. Local models are not marked ready
  unless the artifact, format, runtime provider status, capability tags, and
  conservative memory check pass; preflight is read-only and returns
  `unknown_stale` when runtime status is absent.
- `RHM-008` unified model route decision: done. `xhubd model route` returns
  `xhub.model_route_decision.v1`, accepts task/model/capability/privacy/cost
  inputs, tries remote routes when allowed, uses local fallback only when
  capability/risk policy allows, and blocks high-risk weak local fallback with
  machine-readable reason codes.
- `RHM-009` model inventory shadow compare evidence: done. `xhubd model
  compare` compares Node/Swift-style inventory JSON against Rust
  `model inventory`, normalizes presentation-only differences, persists reports
  under component `model_inventory`, and exposes `model reports` plus
  `model readiness` fail-closed gates.
- `tools/model_inventory_shadow_compare_smoke.js` fixture-backed inventory
  compare smoke: done. The smoke uses no network, verifies alias/camelCase/order
  normalization, checks no provider secret leaks, and proves report/readiness
  evidence can be generated.
- `RHM-010` XT Rust model inventory parity: done for fixture/presentation
  coverage. XT now projects Rust `xhub.model_inventory.v1` into
  `ModelStateSnapshot`, documents the exact consumed fields, and presents
  remote quota, missing scope, local runtime missing, and capability mismatch
  blockers without reading provider token/auth files.
- `RHM-011` default-off live XT/Rust model inventory bridge: implemented.
  `xhubd serve` now exposes model inventory HTTP endpoints, XT can opt in to
  load Rust inventory from a configured snapshot file or HTTP base URL, and the
  UI keeps Rust blocker truth while production routing remains unchanged.
- `RHM-012` sustained model inventory shadow evidence runner: implemented.
  The runner starts an isolated warm Rust HTTP daemon, uses Node Hub local
  runtime and provider pool helpers as secret-free evidence inputs, feeds
  Node/XT-shaped inventory into `/model/compare`, and gates completion through
  `/model/readiness` without changing production authority.
- `RHM-013` real-runtime model inventory evidence mode: implemented. The
  sustained runner can now read an existing runtime dir without writing fixture
  files, target an already warm Rust daemon with `--no-start --http-base-url`,
  and keep the same secret-free Node/Rust evidence boundary.
- `RHM-014` model route HTTP prep: implemented. `xhubd serve` exposes
  read-only `GET/POST /model/route` using the existing
  `xhub.model_route_decision.v1` schema, and the smoke validates remote plus
  local-only route decisions without changing production authority.
- Browser status page: implemented. `GET /` now returns a local HTML status
  page that fetches `/ready`, while `/health`, `/ready`, and all bridge APIs
  remain JSON for Node/XT callers.
- `RHM-015` UI compatibility preservation contract: implemented. The contract
  makes XT the preserved product UI, defines Rust browser status as diagnostics
  only, enumerates product surfaces that must remain stable, and adds per-bridge
  failure behavior plus test gates before any model route authority prep.
- `RHM-015b` UI compatibility no-product-change package gate: implemented.
  `tools/ui_compatibility_no_product_ui_change_gate.command` checks that the
  Rust package does not embed Swift UI sources, the Rust browser page remains
  diagnostic-only, Node/XT authority remains unchanged, and memory writer
  authority stays out of Rust.
- `RHM-016` model route authority prep bridge: implemented. Node Hub now has a
  default-off Rust model route bridge with HTTP-first/CLI fallback, readiness
  gate, Rust/Node selected model comparison, secret-response rejection, and
  `HubAI.Generate` candidate audit that does not change the Bridge payload,
  local runtime dispatch, or XT UI behavior.
- `RHM-017` model route candidate evidence runner: implemented. The runner
  starts an isolated Rust HTTP daemon, invokes Node `HubAI.Generate` in-process
  with a fake Bridge, enables the RHM-016 candidate bridge, and gates readiness
  on `ai.generate.model_route_candidate` audits with zero model/route-kind
  mismatches, zero fallbacks, and zero secret leakage.
- `RHM-018` local model route candidate coverage: implemented. The runner
  starts an isolated Rust HTTP daemon, invokes Node `HubAI.Generate` for a
  local `local.summary` fixture, simulates local runtime JSONL responses, and
  gates readiness on `ai.generate.model_route_candidate` audits with local
  route-kind match, selected-model match, zero fallbacks, and zero secret
  leakage.
- `RHM-019` skills catalog policy gate: implemented. Rust now exposes
  read-only `xhubd skills catalog/readiness` plus `/skills/catalog` and
  `/skills/readiness`, blocks secret-shaped skill manifests, and keeps
  `execution_authority_in_rust=false` and
  `hub_executes_third_party_code=false`.
- `RHM-020` model route combined candidate evidence report: implemented. The
  runner executes the remote paid-model and local runtime candidate runners,
  writes a persisted `xhub.model_route_candidate_evidence_report.v1` artifact,
  and keeps `production_authority_change=false` with
  `authority_mode=candidate_audit_only`.
- `RHM-021` skills preflight grant/audit gate: implemented. Rust now exposes
  read-only `xhubd skills preflight` plus `/skills/preflight`, returns
  `xhub.skills_preflight.v1`, emits a secret-free
  `xhub.skills_preflight.audit.v1` preview, and allows only when the skill is
  pinned and requested capabilities are granted.
- `RHM-022` skills durable pin/grant/audit storage: implemented.
  `migrations/0004_skill_policy.sql` adds namespaced SQLite tables for skill
  pins, capability grants, and preflight audit previews. `skills preflight`
  now merges durable policy with request-local policy while keeping
  `execution_authority_in_rust=false`.
- `RHM-023` model route selected-model authority plan: implemented. The runner
  consumes combined remote/local candidate evidence, writes a persisted
  `xhub.model_route_selected_model_authority_dry_run_plan.v1` artifact, and
  keeps Node as model-selection authority with
  `production_authority_change=false`.
- `RHM-024` skills preflight audit retention: implemented. Rust now exposes
  `xhubd skills audit`, `xhubd skills audit-prune`, `GET /skills/audit`, and
  `POST /skills/audit-prune` so durable preflight audit rows can be summarized
  without `detail_json` exposure and explicitly bounded by newest-row retention.
- `RHM-025` skills policy revocation: implemented. Rust now exposes
  `xhubd skills unpin`, `xhubd skills revoke-grant`, `POST /skills/unpin`,
  `POST /skills/revoke-pin`, and `POST /skills/revoke-grant`; active policy
  reads ignore revoked rows, so preflight returns to deny after revocation.
- `RHM-027` skills policy event audit trail: implemented.
  `migrations/0005_skill_policy_events.sql` adds append-only policy change
  events. Rust now exposes `xhubd skills policy-events`,
  `GET /skills/policy-events`, and `GET /skills/policy-audit` without exposing
  stored `detail_json`.
- `RHM-029` skills policy event retention: implemented. Rust now exposes
  `xhubd skills policy-events-prune`, `POST /skills/policy-events-prune`, and
  `POST /skills/policy-audit-prune` so policy event rows can be explicitly
  bounded by newest-row retention without exposing stored `detail_json`.
- `RHM-030` skills policy store readiness: implemented. Rust now exposes
  `xhubd skills policy-readiness`, `GET/POST /skills/policy-readiness`, and
  `GET/POST /skills/policy-maintenance` so long-running daemons can summarize
  active pin/grant counts, preflight audit rows, policy event rows, latest
  timestamps, and maintenance threshold readiness without exposing stored
  `detail_json`.
- `RHM-032` ops readiness gate: implemented. `tools/ops_readiness_gate.command`
  starts one temporary warm `xhubd serve` process, repeatedly checks `/ready`,
  memory retrieval readiness/search, skills readiness, skill policy store
  readiness, cross-network auth-gate flags, and the UI compatibility gate, then
  shuts the daemon down without leaving Rust authority enabled.
- `RHM-033` ready cache stutter guard: implemented. `xhubd serve` now caches
  `/ready`, `/readiness`, and `/runtime/readiness` for a short process-local TTL
  (`XHUB_RUST_READY_CACHE_TTL_MS`, default 250ms) and reports the stutter guard
  in `/ready.performance`; the ops readiness gate verifies immediate cache hits
  and endpoint/cycle latency budgets.
- `RHM-034` memory/skills snapshot cache: implemented. `xhubd serve` now caches
  read-only memory index snapshots and skills catalog scans for short
  process-local TTLs (`XHUB_RUST_MEMORY_SNAPSHOT_CACHE_TTL_MS` and
  `XHUB_RUST_SKILLS_CATALOG_CACHE_TTL_MS`, default 500ms) while leaving skill
  policy mutations, preflight, and execution authority uncached/default-off.
- `RHM-035` HTTP backpressure guard: implemented. `xhubd serve` now limits
  concurrent business HTTP request handling with `XHUB_RUST_HTTP_MAX_IN_FLIGHT`
  (default 128), returns `503 http_backpressure` when saturated, and keeps
  `/health` exempt for process managers.
- `RHM-046` HTTP I/O timeouts: implemented. `xhubd serve` now applies bounded
  per-connection socket read/write timeouts
  (`XHUB_RUST_HTTP_READ_TIMEOUT_MS` and `XHUB_RUST_HTTP_WRITE_TIMEOUT_MS`,
  defaults 5000ms) and reports the guard in `/ready.performance` plus
  `/ready.capabilities`.
- `RHM-047` XT file IPC shadow responder: implemented. `xhubd serve` now
  exposes `GET /xt/file-ipc-shadow` and
  `POST /xt/file-ipc-shadow/respond-once` for temporary-dir-only fail-closed
  validation of XT `req_<id>.json` to `resp_<id>.jsonl`. It is default-off for
  writes, does not execute ML, and does not satisfy the real file IPC readiness
  gate.
- `RHM-048` XT file IPC shadow drain processor: implemented. `xhubd serve` now
  exposes `POST /xt/file-ipc-shadow/drain` for bounded, deterministic,
  temporary-dir-only draining of multiple XT request files. It is manually
  triggered, default-off for writes, max-request limited, and still not a
  production watcher.
- `RHM-049` XT file IPC shadow processor cycle: implemented. `xhubd serve` now
  exposes `POST /xt/file-ipc-shadow/cycle` to run one bounded temporary-dir
  cycle and optionally write Rust-owned shadow processor status. It never
  writes `hub_status.json` and still does not mark production file IPC ready.
- `RHM-050` XT file IPC shadow supervisor loop: implemented. `xhubd serve` now
  exposes `POST /xt/file-ipc-shadow/supervise` to run a bounded synchronous
  loop over manual cycles. It does not leave a background watcher running and
  still does not mark production file IPC ready.
- `RHM-059` XT file IPC shadow watcher smoke: implemented. `xhubd serve` now
  exposes `POST /xt/file-ipc-shadow/watcher-smoke` to validate watcher lock,
  starting/stopped status, bounded work, and lock release semantics under the
  same temporary-dir-only fail-closed gates. It does not leave a background
  watcher running and still does not mark production file IPC ready.
- `RHM-061` XT file IPC shadow watcher rollback smoke: implemented.
  `xhubd serve` now exposes
  `POST /xt/file-ipc-shadow/watcher-rollback-smoke` to plan and, only under
  explicit rollback apply gates, remove Rust-owned shadow watcher/processor
  artifacts from temporary directories. It never removes XT live status or
  response files and still does not mark production file IPC ready.
- `RHM-064` XT file IPC watcher readiness gate: implemented. `xhubd serve` now
  exposes `POST /xt/file-ipc-shadow/watcher-readiness` as a read-only,
  temporary-dir-only diagnostic gate for the future real watcher. Candidate
  readiness is reported separately from production readiness, which remains
  false.
- `RHM-066` XT file IPC watcher start plan: implemented. `xhubd serve` now
  exposes `POST /xt/file-ipc-shadow/watcher-start-plan` as a read-only,
  default-off plan that reports start blockers and future lock/status paths
  without starting a watcher or marking production file IPC ready.
- `RHM-067` XT file IPC watcher run once: implemented. `xhubd serve` now
  exposes `POST /xt/file-ipc-shadow/watcher-run-once` as a default-off,
  temporary-dir one-shot lifecycle that can run one fail-closed cycle under
  explicit apply gates. It still does not start a long-running watcher or mark
  production file IPC ready.
- `RHM-068` XT file IPC watcher run once smoke: implemented.
  `tools/xt_file_ipc_watcher_run_once_smoke.command` starts an isolated
  temporary daemon, writes one temporary XT request, calls the run-once
  endpoint, and validates lock release, stopped watcher status, shadow-only
  processor status, fail-closed JSONL, and absent `hub_status.json`.
- `RHM-071` XT file IPC watcher run once report: implemented.
  `tools/xt_file_ipc_watcher_run_once_smoke.command` now accepts
  `--report-file <path>` and persists the same JSON evidence that it prints to
  stdout.
- `RHM-072` XT file IPC run once ops gate: implemented.
  `tools/daemon_ops_gate.command` accepts `--xt-file-ipc-run-once-smoke` and
  records child smoke evidence in the ops-gate report. The check is default-off.
- `RHM-079` XT file IPC run once ops report: implemented.
  `tools/daemon_ops_report.command` accepts `--xt-file-ipc-run-once-smoke` and
  records child smoke evidence in the ops report. The check is default-off.
- `RHM-080` XT file IPC watcher session: implemented.
  `xhubd serve` now exposes `POST /xt/file-ipc-shadow/watcher-session` as a
  default-off, temporary-dir bounded watcher lifecycle that acquires/releases
  the Rust-owned watcher lock, writes Rust-owned watcher status, and runs the
  bounded supervisor under explicit apply gates. It still does not start a
  long-running watcher or mark production file IPC ready.
- `RHM-083` XT file IPC background watcher lifecycle: implemented.
  `xhubd serve` now exposes `POST /xt/file-ipc-shadow/watcher-background-start`,
  `watcher-background-status`, and `watcher-background-stop` as a default-off,
  temporary-dir-only, bounded background watcher lifecycle. It is single-instance
  per xhubd process, writes only Rust-owned shadow files and fail-closed JSONL,
  and still does not mark production file IPC ready.
- `RHM-084` XT file IPC background watcher smoke: implemented.
  `tools/xt_file_ipc_background_watcher_smoke.command` starts an isolated
  temporary daemon and validates background watcher start/status/stop, lock
  release, stopped watcher status, shadow-only processor status, fail-closed
  JSONL, and absent `hub_status.json`.
- `RHM-085` XT file IPC background watcher ops evidence: implemented.
  `tools/daemon_ops_report.command` and `tools/daemon_ops_gate.command` accept
  `--xt-file-ipc-background-watcher-smoke` and persist child smoke evidence next
  to the parent ops report. The check remains default-off and fails closed if
  the child evidence does not prove stopped lifecycle state, lock release,
  fail-closed response, no `hub_status.json`, no ML execution, and no production
  authority change.
- `RHM-086` XT file IPC request schema compatibility: implemented.
  The Rust shadow responder now normalizes XT `HubAIRequest` fields into its
  report, emits `requested_model_id`, `preferred_model_id`, `actual_model_id`,
  and `app_id` on fail-closed `start`/`done` JSONL events, and redacts
  `provider_key` secrets while preserving provider/auth presence evidence.
  Execution remains fail-closed and non-production.
- `RHM-087` XT file IPC runtime execution plan: implemented.
  `xhubd serve` now exposes
  `POST /xt/file-ipc-shadow/runtime-execution-plan` and compat route to map an
  XT request to Rust `model_route` selection and report the candidate adapter
  (`local_runtime_file_ipc` or `remote_provider_route`). The route is
  shadow-only, temporary-dir bounded, writes no response, executes no ML, and
  reports blockers for missing runtime/cutover gates. The isolated smoke lives
  at `tools/xt_file_ipc_runtime_execution_plan_smoke.command`.
- `RHM-088` XT file IPC runtime adapter candidate: implemented.
  `xhubd serve` now exposes
  `POST /xt/file-ipc-shadow/runtime-adapter-candidate` and compat route as a
  gated writable candidate. It requires shadow apply, runtime plan, adapter
  candidate env, and request `apply: true`; then writes only a two-line
  fail-closed XT response JSONL in an explicit temporary directory. It does not
  execute ML, write `hub_status.json`, or mark production file IPC ready. The
  isolated smoke lives at
  `tools/xt_file_ipc_runtime_adapter_candidate_smoke.command`.
- `RHM-092` XT file IPC runtime adapter no selected model gate: implemented.
  The runtime adapter candidate now blocks before any response write when the
  Rust model route cannot select a model. The response remains HTTP 409 with
  `runtime_adapter_candidate_blocked`, includes nested
  `model_route_no_selected_model` evidence, writes no response JSONL, writes no
  `hub_status.json`, executes no ML, and leaves production authority unchanged.
  The isolated smoke covers this path with a separate temporary IPC directory
  that intentionally has no runtime model inventory.
- `RHM-093` XT file IPC runtime adapter overwrite gate: implemented.
  The runtime adapter candidate now rejects `overwrite_response: true` unless
  `XHUB_RUST_XT_FILE_IPC_OVERWRITE_RESPONSE=1` is explicitly set. The default
  path preserves the existing response file byte-for-byte, writes no
  replacement JSONL, writes no `hub_status.json`, executes no ML, and leaves
  production authority unchanged. The isolated adapter smoke covers the
  explicit overwrite request as a fail-closed path.
- `RHM-094` XT file IPC runtime adapter input size guard: implemented.
  XT request JSON files are capped before read at 1 MiB and request prompts are
  capped at 200,000 characters after parse. Oversized requests fail closed with
  `request_file_too_large` or `request_prompt_too_large`, write no response
  JSONL, write no `hub_status.json`, execute no ML, and leave production
  authority unchanged. The isolated adapter smoke covers the oversized prompt
  path.
- `RHM-095` XT file IPC runtime adapter oversized file coverage: implemented.
  The isolated runtime adapter smoke now also writes a request JSON file larger
  than the 1 MiB guard and verifies `request_file_too_large` is returned before
  parse, with no response JSONL, no `hub_status.json`, no ML execution, and no
  authority change.
- `RHM-096` XT file IPC runtime adapter invalid JSON gate: implemented.
  Malformed XT request JSON now fails closed with `request_json_invalid` before
  model routing or response writing. The adapter writes no response JSONL,
  writes no `hub_status.json`, executes no ML, and leaves production authority
  unchanged. The isolated adapter smoke covers this malformed JSON path.
- `RHM-105` XT file IPC production-aware shadow smokes: implemented.
  The run-once and background watcher smokes now report live production-surface
  observation separately from isolated shadow processor status. The daemon ops
  gate accepts either live production-surface state while still requiring no
  isolated `hub_status.json` write, no Rust ML execution, no production
  authority change, and non-production shadow processor status.
- `RHM-107`/`RHM-108`/`RHM-109` XT live heartbeat repair hardening:
  implemented.
  Readiness and classic compat probes keep stale Rust-owned preferred
  `hub_status.json` evidence from falsely dropping the live production surface.
  RHM-108 made request-path repair read-only, used a process-local live status
  cache for readiness/compat probes, and kept durable writes in the background
  heartbeat. RHM-117 supersedes that overlay during explicit live cutover by
  writing stale or missing Rust-owned status back to disk and failing closed if
  the write fails. RHM-109 starts heartbeat in trusted live mode, keeps live cutover
  request-path probes off direct Group Container status reads/metadata checks, and uses a
  `1000ms` heartbeat with a bounded `2000ms` status lease. Live Group Container
  writes prefer temp-file atomic rename but can fall back to a locked in-place
  update of an existing Rust-owned status file when macOS denies temp-file
  creation. The live heartbeat soak verifier uses a bounded child-process
  status read so Group Container open delays cannot hang the gate. The repair
  path is gated by the same explicit live cutover flags, does not touch UI, and
  leaves Rust memory writer and skills execution authority disabled.
- `RHM-110` production live stability gate: implemented. The new
  `tools/production_live_stability_gate.command` composes the bounded live
  heartbeat soak, daemon ops gate, production runtime guard, UI compatibility
  gate, and process sanity checks into a single read-only report for 2 minute,
  8 hour, or 24 hour post-cutover validation. By default it validates the live
  `launchctl getenv XHUB_RUST_HUB_ROOT` root when present, so newer packages can
  run the gate against the currently active production root without forcing an
  upgrade. It fails closed on stale XT heartbeat, recent slow requests, missing
  production authority in the running X-Hub process, product UI drift, secret
  leak, memory writer or skills execution authority drift, or accidental
  `target/debug` / `target/release` xhubd processes. The detached
  `tools/production_live_stability_session.command` wrapper starts, checks, and
  stops long runs without blocking a terminal, recording state under
  `reports/production_live_stability/session_state.json`.
- `RHM-111` production live stability checkpoint: implemented. The session
  wrapper now supports `--checkpoint` for immediate short live health checks
  while an 8 hour or 24 hour session is still running. It also discovers active
  `production_live_stability_gate.js` processes started from another package
  root, parses PID, report path, duration, interval, and inferred start/end
  timing, and keeps the checkpoint read-only with no authority or UI changes.
- `RHM-112` production live slow delta guard: implemented. The stability gate
  now records an HTTP metrics baseline before the soak and compares it with
  final daemon ops metrics, failing closed if cumulative slow-request delta
  exceeds `--max-slow-requests`. This catches transient stutter even if samples
  have aged out of the bounded recent window by the time a long run finishes.
- `RHM-117` XT live status on-demand disk repair: implemented. Explicit
  cutover readiness and classic compat probes now repair stale or missing
  Rust-owned `hub_status.json` by performing a gated fast disk write and
  updating the live status cache. If the write fails, the probe no longer
  returns a fresh memory-only overlay, so live heartbeat and production
  stability gates fail closed on durable status-file problems.
- `RHM-118` production stability session adoption: implemented.
  `tools/production_live_stability_session.command --adopt` writes current
  package state for an active long stability gate discovered in another package
  root. `--status` now reports current, managed, and original process roots,
  while `--start` refuses to create duplicate long sessions unless
  `--replace` is explicit and `--stop` can stop a discovered session even when
  local state is missing.
- `RHM-119` production stability active status observability: implemented.
  `tools/production_live_stability_session.command --status` remains read-only
  but now reports the active gate process tree, the live heartbeat soak child
  when present, report-file metadata, and a bounded `hub_status.json` freshness
  sample. This lets an 8 hour or overnight stability session be inspected
  without stopping it, without writing live status, and without changing
  provider/model, scheduler, memory writer, skills execution, or UI authority.
- `RHM-120` rolling checkpoint sidecar adoption: implemented.
  `tools/production_live_stability_session.command --adopt-checkpoint-loop`
  writes current package state for an active checkpoint loop worker discovered
  in another package root. `--checkpoint-loop-status` now reports current,
  managed, and original sidecar roots, while `--start-checkpoint-loop` refuses
  duplicate sidecars unless `--replace` is explicit and `--stop-checkpoint-loop`
  can stop a discovered sidecar even when local state is missing.
- `RHM-121` production stability supervision status: implemented.
  `tools/production_live_stability_session.command --supervision-status`
  combines the long production stability session and rolling checkpoint sidecar
  into one read-only payload. It reports compact supervision readiness, live
  status freshness, heartbeat child presence, next checkpoint timing, latest
  checkpoint result, slow-request delta budget, and authority/UI/secret drift
  while embedding the full existing status payloads for diagnostics.
- `RHM-122` production stability CLI context: implemented.
  `tools/production_live_stability_session.command --status` now preserves
  explicit `--http-base-url` and `--live-base-dir` values as fallback context
  when the current package has no local session state yet. Existing adopted
  state and discovered process metadata still take precedence, so package
  migration and recovery output stays accurate without changing authority.
- `RHM-036` HTTP latency metrics: implemented. `xhubd serve` now records
  route-level request counts, average/max latency, slow counts, and last status
  in memory, exposes them at `/runtime/http-metrics` and `/http/metrics`, and
  reports the diagnostics capability from `/ready`.
- `RHM-044` HTTP metrics recent window: implemented. `xhubd serve` now keeps a
  bounded recent latency sample window (`XHUB_RUST_HTTP_METRICS_RECENT_LIMIT`,
  default 256), exposes recent slow count, recent route summaries, and a capped
  newest-first sample tail without query strings or request bodies. The daemon
  ops gate applies slow-request budgets to the recent window when available and
  falls back to lifetime counters for older daemons.
- `RHM-037` ops soak runner: implemented. `tools/ops_soak_runner.command`
  keeps one temporary `xhubd serve` warm across sustained readiness, memory,
  skills, policy-store, latency-budget, HTTP metrics, and UI compatibility
  checks, then writes `xhub.rust_hub.ops_soak_report.v1` under `reports/`
  without enabling Rust production authority or changing XT UI.
- `RHM-039` daemon ops report: implemented. `xhubd_daemon.command ops-report`
  and `tools/daemon_ops_report.command` collect source/manual daemon status,
  launchd status, health/readiness, HTTP latency metrics, UI compatibility, and
  redacted log tails into `xhub.rust_hub.daemon_ops_report.v1` without
  mutating the running service.
- `RHM-040` daemon maintenance retention: implemented.
  `xhubd_daemon.command maintenance` and `tools/daemon_maintenance.command`
  preview/apply bounded log and report retention, write
  `xhub.rust_hub.daemon_maintenance_report.v1`, default to dry-run, and do not
  start/stop/restart the daemon.
- `RHM-051` daemon watchdog guard: implemented.
  `xhubd_daemon.command watchdog` and `tools/daemon_watchdog.command` write
  `xhub.rust_hub.daemon_watchdog_report.v1` with launchd, health/readiness,
  HTTP metrics, recent slow-request, HTTP I/O timeout/backpressure, pid-file,
  maintenance, UI, and authority-boundary checks. It is dry-run by default; the
  only mutation is stale/invalid pid-file removal when both `--apply` and
  `--repair-stale-pid` are explicit.
- `RHM-052` watchdog launchd timer: implemented.
  `xhubd_daemon.command watchdog-plist`, `watchdog-install`, `watchdog-status`,
  and `watchdog-uninstall` manage a separate user LaunchAgent timer for
  periodic dry-run watchdog reports. The generated plist uses `StartInterval`
  and never restarts, repairs, bootstraps, or uninstalls the daemon.
- `RHM-058` cross-network readiness gate: implemented.
  `xhubd_daemon.command cross-network-readiness` and
  `tools/cross_network_readiness_gate.command` write
  `xhub.rust_hub.cross_network_readiness.v1` evidence for LAN profile,
  non-loopback bind, public host, `0600` access-key file, launchd key-file
  wiring, watchdog timer installability, UI compatibility, and authority
  boundaries. Optional flags can require live `/ready`, daemon launchd loaded
  state, and watchdog timer loaded state.
- `RHM-062` cross-network installed gate: implemented.
  `tools/cross_network_installed_gate.command` wraps the RHM-058 readiness gate
  with `--require-live-ready`, `--require-launchd-loaded`, and
  `--require-watchdog-timer`. It is read-only and intentionally fails closed
  until a real LAN daemon LaunchAgent plus watchdog timer are installed and
  loaded.
- `RHM-065` cross-network install plan: implemented.
  `xhubd_daemon.command cross-network-install-plan` and
  `tools/cross_network_install_plan.command` print
  `xhub.rust_hub.cross_network_install_plan.v1` with ordered LAN install,
  validation, and rollback commands without executing or mutating launchd state.
- `RHM-026` model route prep trial smoke: implemented. The remote and local
  Generate runners support explicit `--prep-trial`, and the combined runner
  writes `xhub.model_route_prep_trial_report.v1` while keeping
  `production_authority_change=false` and Node-selected remote Bridge payloads
  plus local runtime IPC models authoritative.

## Files Added

- `Cargo.toml`
- `README.md`
- `config/default.toml`
- `config/daemon_profile.local.json`
- `config/daemon_profile.lan.example.json`
- `assets/proto/hub_protocol_v1.proto`
- `migrations/0001_runtime_baseline.sql`
- `migrations/0002_scheduler_truth.sql`
- `migrations/0003_shadow_compare_reports.sql`
- `migrations/0004_skill_policy.sql`
- `migrations/0005_skill_policy_events.sql`
- `docs/SCHEDULER_BRIDGE_CLI.md`
- `docs/PROVIDER_ROUTE_CLI.md`
- `docs/MODEL_MANAGEMENT_EXECUTION_PLAN.md`
- `docs/RHM_010_XT_MODEL_INVENTORY_FIELDS.md`
- `docs/RHM_011_XT_LIVE_MODEL_INVENTORY_BRIDGE.md`
- `docs/RHM_012_MODEL_INVENTORY_SHADOW_EVIDENCE.md`
- `docs/RHM_013_REAL_RUNTIME_MODEL_INVENTORY_EVIDENCE.md`
- `docs/RHM_014_MODEL_ROUTE_HTTP_PREP.md`
- `docs/RHM_015_UI_COMPATIBILITY_PRESERVATION.md`
- `docs/RHM_016_MODEL_ROUTE_AUTHORITY_PREP_BRIDGE.md`
- `docs/RHM_017_MODEL_ROUTE_CANDIDATE_EVIDENCE_RUNNER.md`
- `docs/RHM_018_LOCAL_MODEL_ROUTE_CANDIDATE_COVERAGE.md`
- `docs/RHM_020_MODEL_ROUTE_COMBINED_CANDIDATE_EVIDENCE_REPORT.md`
- `docs/RHM_023_MODEL_ROUTE_SELECTED_MODEL_AUTHORITY_PLAN.md`
- `docs/RHM_024_SKILLS_PREFLIGHT_AUDIT_RETENTION.md`
- `docs/RHM_025_SKILLS_POLICY_REVOCATION.md`
- `docs/RHM_027_SKILLS_POLICY_EVENT_AUDIT_TRAIL.md`
- `docs/RHM_029_SKILLS_POLICY_EVENT_RETENTION.md`
- `docs/RHM_030_SKILLS_POLICY_STORE_READINESS.md`
- `docs/RHM_032_OPS_READINESS_GATE.md`
- `docs/RHM_033_READY_CACHE_STUTTER_GUARD.md`
- `docs/RHM_034_MEMORY_SKILLS_SNAPSHOT_CACHE.md`
- `docs/RHM_035_HTTP_BACKPRESSURE_GUARD.md`
- `docs/RHM_046_HTTP_IO_TIMEOUTS.md`
- `docs/RHM_036_HTTP_LATENCY_METRICS.md`
- `docs/RHM_037_OPS_SOAK_RUNNER.md`
- `docs/RHM_039_DAEMON_OPS_REPORT.md`
- `docs/RHM_040_DAEMON_MAINTENANCE_RETENTION.md`
- `docs/RHM_043_DAEMON_OPS_GATE.md`
- `docs/RHM_044_HTTP_METRICS_RECENT_WINDOW.md`
- `docs/RHM_051_DAEMON_WATCHDOG_GUARD.md`
- `docs/RHM_052_WATCHDOG_LAUNCHD_TIMER.md`
- `docs/RHM_058_CROSS_NETWORK_READINESS_GATE.md`
- `docs/RHM_062_CROSS_NETWORK_INSTALLED_GATE.md`
- `docs/RHM_065_CROSS_NETWORK_INSTALL_PLAN.md`
- `docs/RHM_026_MODEL_ROUTE_PREP_TRIAL_SMOKE.md`
- `docs/NODE_HUB_SHADOW_COMPARE_INTEGRATION.md`
- `tools/build_rust_hub.command`
- `tools/run_rust_hub.command`
- `tools/package_rust_hub.command`
- `tools/run_packaged_rust_hub.command`
- `tools/node_scheduler_shadow_compare.js`
- `tools/node_scheduler_shadow_compare.command`
- `tools/node_hub_shadow_compare_smoke.js`
- `tools/node_hub_shadow_compare_smoke.command`
- `tools/node_hub_shadow_compare_runner.js`
- `tools/node_hub_shadow_compare_runner.command`
- `tools/node_hub_authority_live_runner.js`
- `tools/node_hub_authority_live_runner.command`
- `tools/scheduler_cutover_readiness_runner.js`
- `tools/scheduler_cutover_readiness_runner.command`
- `tools/scheduler_authority_runner.js`
- `tools/scheduler_authority_runner.command`
- `tools/xhubd_daemon.js`
- `tools/xhubd_daemon.command`
- `tools/daemon_ops_report.command`
- `tools/daemon_maintenance.command`
- `tools/daemon_ops_gate.command`
- `tools/daemon_watchdog.command`
- `tools/cross_network_readiness_gate.command`
- `tools/cross_network_installed_gate.command`
- `tools/cross_network_install_plan.command`
- `tools/scheduler_status_http_bridge_smoke.js`
- `tools/scheduler_status_http_bridge_smoke.command`
- `tools/scheduler_lease_shadow_http_bridge_smoke.js`
- `tools/scheduler_lease_shadow_http_bridge_smoke.command`
- `tools/scheduler_authority_http_bridge_smoke.js`
- `tools/scheduler_authority_http_bridge_smoke.command`
- `tools/provider_route_smoke.command`
- `tools/provider_route_http_smoke.command`
- `tools/provider_route_http_bridge_smoke.js`
- `tools/provider_route_http_bridge_smoke.command`
- `tools/provider_route_http_shadow_compare_smoke.js`
- `tools/provider_route_http_shadow_compare_smoke.command`
- `tools/provider_route_shadow_compare_smoke.js`
- `tools/provider_route_shadow_compare_smoke.command`
- `tools/model_inventory_shadow_compare_smoke.js`
- `tools/model_inventory_shadow_compare_smoke.command`
- `tools/model_inventory_shadow_compare_runner.js`
- `tools/model_inventory_shadow_compare_runner.command`
- `tools/model_inventory_http_bridge_smoke.js`
- `tools/model_inventory_http_bridge_smoke.command`
- `tools/model_route_http_smoke.js`
- `tools/model_route_http_smoke.command`
- `tools/model_route_generate_candidate_runner.js`
- `tools/model_route_generate_candidate_runner.command`
- `tools/model_route_local_candidate_runner.js`
- `tools/model_route_local_candidate_runner.command`
- `tools/model_route_candidate_evidence_runner.js`
- `tools/model_route_candidate_evidence_runner.command`
- `tools/model_route_authority_plan_runner.js`
- `tools/model_route_authority_plan_runner.command`
- `tools/model_route_prep_trial_runner.js`
- `tools/model_route_prep_trial_runner.command`
- `tools/provider_route_shadow_compare_runner.js`
- `tools/provider_route_shadow_compare_runner.command`
- `tools/provider_route_generate_observe_runner.js`
- `tools/provider_route_generate_observe_runner.command`
- `tools/provider_route_cutover_readiness_runner.js`
- `tools/provider_route_cutover_readiness_runner.command`
- `tools/provider_route_authority_plan_runner.js`
- `tools/provider_route_authority_plan_runner.command`
- `tools/ops_readiness_gate.js`
- `tools/ops_readiness_gate.command`
- `tools/ops_soak_runner.js`
- `tools/ops_soak_runner.command`
- `crates/xhubd`
- `crates/xhub-core`
- `crates/xhub-contract`
- `crates/xhub-db`
- `crates/xhub-scheduler`
- `crates/xhub-policy`
- `crates/xhub-memory`
- `crates/xhub-skills`
- `crates/xhub-provider`
- `crates/xhub-runtime`
- `crates/xhub-contract/build.rs`
- `crates/xhubd/src/grpc_runtime.rs`
- `crates/xhubd/src/model_bridge.rs`

## Current Scheduler Core

Implemented in `crates/xhub-scheduler`:

- idempotent enqueue by `(scope_key, idempotency_key)`
- global concurrency guard
- per-scope concurrency guard
- queue limit
- queue timeout handling
- lease acquire
- lease heartbeat
- lease release as completed, failed, or requeued
- expired lease requeue
- cancel
- scope counter rebuild
- scheduler snapshot writer
- DB-backed status view with optional queue items

Implemented in `crates/xhubd/src/scheduler_bridge.rs`:

- `scheduler enqueue`
- `scheduler claim`
- `scheduler acquire`
- `scheduler acquire-run`
- `scheduler heartbeat`
- `scheduler release`
- `scheduler cancel`
- `scheduler status`
- `scheduler lease-shadow-report`
- `scheduler cutover-readiness`
- `scheduler compare`
- `scheduler reports`

`scheduler compare` persists append-only reports to
`rust_hub_shadow_compare_reports` so Node-vs-Rust scheduler parity can be
measured before cutover.
`scheduler reports` summarizes recent compare evidence without manual SQLite
inspection.
`scheduler lease-shadow-report` summarizes Node paid AI lease shadow mirror
health from Rust scheduler run, lease, and event tables without extra hot-path
evidence writes.
`scheduler cutover-readiness` combines compare and lease shadow evidence into a
single `ready=true|false` gate.
`scheduler claim` is the next authority-switch primitive: it performs
idempotent enqueue and fair lease attempt in one Rust transaction, returning
`leased=false` instead of bypassing older fair candidates.

Implemented in `tools/node_scheduler_shadow_compare.js`:

- normalizes Node scheduler snapshot JSON
- accepts direct flags, `--snapshot-json`, or `--snapshot-file -`
- invokes `xhubd scheduler compare`
- supports `--dry-run` and `--self-test`

Implemented in `tools/node_hub_shadow_compare_smoke.js`:

- creates temporary Node Hub DB/runtime state
- enables `XHUB_RUST_SCHEDULER_SHADOW_COMPARE=1`
- invokes the real Node Hub `HubRuntime.GetSchedulerStatus` service handler
- waits for Rust Hub report totals to increase
- prints before/after `scheduler reports` summaries
- supports continuous evidence collection with `--runs`, `--interval-ms`, and
  `--expect-zero-mismatch`

Implemented in `tools/node_hub_shadow_compare_runner.js`:

- starts the existing Node Hub with `XHUB_RUST_SCHEDULER_SHADOW_COMPARE=1`
- prints Rust scheduler report summaries at a fixed interval
- supports monitor-only mode with `--no-start`
- supports packaging/CI checks with `--dry-run`, `--self-test`, and
  `--expect-zero-mismatch`
- fails non-zero if the runner-started Node Hub exits unexpectedly

Implemented in `tools/scheduler_cutover_readiness_runner.js`:

- invokes the real Node Hub `GetSchedulerStatus` service handler
- waits for Rust scheduler compare report totals to increase
- mirrors paid AI lease shadow enqueue/acquire-run/release
- reads `scheduler cutover-readiness` after each iteration
- exits non-zero when `--expect-ready` or `--expect-zero-mismatch` is not met

Implemented in `tools/scheduler_authority_runner.js`:

- creates temporary Node Hub runtime, Bridge IPC directory, Node SQLite DB, and
  Rust scheduler SQLite DB
- enables `XHUB_RUST_SCHEDULER_AUTHORITY=1` and status read in-process
- seeds a paid model and trusted paired-client profile
- simulates Bridge `ai_generate` through the production filesystem IPC shape
- invokes the real Node `HubAI.Generate` handler
- verifies `done_ok=true`, one completed Rust authority run, and clean Rust
  scheduler status after release
- supports `--concurrency`, delayed fake Bridge responses, non-blocking status
  sampling, and `--expect-queued` to verify Rust queueing under pressure

Implemented in `tools/node_hub_authority_live_runner.js`:

- starts the real Node Hub `src/server.js` with Rust scheduler authority enabled
- uses one temporary SQLite DB for both Node Hub tables and Rust scheduler truth
- writes a temporary trusted paired-client profile and seeds a paid model
- simulates Bridge `ai_generate` through the production filesystem IPC shape
- sends real gRPC `HubAI.Generate` traffic into the Node Hub process
- supports concurrent gRPC batches and `--expect-queued` to verify Rust
  per-scope queueing through the production service boundary
- supports `--scenario queued-cancel` and `--scenario queued-timeout` to verify
  Rust queued terminal paths through real gRPC stream cancellation and queue
  timeout

Implemented in existing Node Hub as opt-in integration:

- `rust_scheduler_bridge.js`
- `rust_scheduler_bridge.test.js`
- `rust_scheduler_authority_bridge.js`
- `rust_scheduler_authority_bridge.test.js`
- `rust_scheduler_lease_shadow_bridge.js`
- `rust_scheduler_lease_shadow_bridge.test.js`
- `rust_scheduler_shadow_compare.js`
- `rust_scheduler_shadow_compare.test.js`
- `rust_scheduler_shadow_compare_service_hook.test.js`
- `services.js` can read `HubRuntime.GetSchedulerStatus` from Rust status when
  `XHUB_RUST_SCHEDULER_STATUS_READ=1`; the bridge uses async `execFile` so
  Rust status polling does not block the Node Hub event loop, and it coalesces
  concurrent status reads with a short TTL cache to reduce rapid UI polling
  overhead
- `services.js` can try Rust scheduler authority for paid AI slots when
  `XHUB_RUST_SCHEDULER_AUTHORITY=1`; it uses readiness-gated `scheduler claim`
  and falls back to the existing Node queue when Rust is disabled, missing, or
  not ready
- `rust_scheduler_bridge.js` can require `scheduler cutover-readiness` to return
  `ready=true` before using Rust scheduler status when
  `XHUB_RUST_SCHEDULER_STATUS_REQUIRE_READY=1`
- `services.js` can mirror paid AI slot enqueue/acquire/release/cancel into
  Rust scheduler when `XHUB_RUST_SCHEDULER_LEASE_SHADOW=1`
- `rust_scheduler_lease_shadow_bridge.js` can prefer `xhubd serve`
  scheduler POST endpoints over CLI when
  `XHUB_RUST_SCHEDULER_LEASE_SHADOW_HTTP=1`, with CLI fallback enabled by
  default
- `services.js` can shadow-compare provider route decisions after
  `HubProviderKeys.GetProviderKeyRouteDecision` responds when
  `XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE=1`
- `rust_provider_route_authority_bridge.js` can prefer `xhubd serve`
  `GET /provider/route` over CLI when
  `XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP=1`, with CLI fallback enabled by
  default
- `services.js` can run a readiness-gated Rust provider route authority prep
  check after `HubProviderKeys.GetProviderKeyRouteDecision` responds when
  `XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP=1`; the Node response and Bridge
  payload remain unchanged; the prep hook is per-route throttled and capped by
  max in-flight work
- `services.js` can observe Rust provider route decisions after Node selects a
  paid-model provider key when
  `XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE=1`; the hook is async,
  throttled, bounded by max in-flight, and never changes the Bridge payload
- `services.js` can append Rust provider route candidate audit events for
  paid-model Generate requests when
  `XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE=1`; event type is
  `ai.generate.provider_route_candidate` and ext schema is
  `xhub.rust_provider_route_candidate.audit.v1`; candidate route checks use a
  short TTL cache and single-flight coalescing to reduce duplicate Rust CLI work
  during bursts
- `services.js` calls `schedulerShadowComparer.maybeCompare(paid_ai)` after
  `HubRuntime.GetSchedulerStatus` responds
- default behavior remains disabled unless
  `XHUB_RUST_SCHEDULER_SHADOW_COMPARE=1` or
  `XHUB_RUST_SCHEDULER_STATUS_READ=1` or
  `XHUB_RUST_SCHEDULER_AUTHORITY=1` or
  `XHUB_RUST_SCHEDULER_LEASE_SHADOW=1` or
  `XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE=1` or
  `XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE=1` or
  `XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE=1`

The gRPC surface still exposes only read status. Mutating Hub runtime RPCs keep
the existing shadow/fail-closed responses until cutover is explicit.

## Current Provider Routing Shadow Core

Implemented in `crates/xhub-provider`:

- provider inference from model ID using the Node Hub provider/model map
- shared OpenAI/Codex provider pools
- model-restricted account preference and wildcard model matching
- account availability states for disabled, missing auth, expired token,
  refresh cooldown, runtime cooldown, auth block, stale, provider block, and
  quota exhaustion
- `fill-first`, `priority`, and `quota-aware` scoring
- deterministic tie-break by score then `account_key`
- explicit fail-closed `fallback_reason_code`

Implemented in `crates/xhubd/src/provider_bridge.rs`:

- `provider route`
- `provider compare`
- `provider reports`
- `provider readiness`
- `--model-id`, `--provider`, `--runtime-base-dir`, `--request-json`,
  `--now-ms`
- one JSON response envelope for shadow compare and packaged smoke tools
- append-only `provider_route` evidence in `rust_hub_shadow_compare_reports`

Implemented in `crates/xhubd/src/main.rs` shadow HTTP serve:

- `GET /ready` / `GET /readiness` / `GET /runtime/readiness`
- `GET /provider/route`
- `GET /provider/reports`
- `GET /provider/readiness`
- query params `model_id`/`modelId`, `provider`, `runtime_base_dir`/
  `runtimeBaseDir`, `now_ms`/`nowMs`
- same `xhub.provider_bridge.v1` route/readiness/report envelopes as the CLI
- daemon-backed provider route/readiness surface for warm-process Node bridge
  use

Implemented in `tools/xhubd_daemon.js`:

- `start`, `health`, `ready`, `status`, `stop`, `restart`, `env`,
  `profile`, `launchd-plist`, `ops-report`, `maintenance`, `ops-gate`,
  `watchdog`, and `self-test`
- background `xhubd serve` launch with pid file under `run/`
- daemon stdout/stderr logs under `logs/`
- `/health` wait before reporting a successful start
- `/ready` operational readiness check covering contract, SQLite, scheduler,
  network bind, runtime, memory directory, skills directory, memory policy,
  skills policy, and provider/model HTTP surfaces
- persistent daemon profile loading from `config/daemon_profile.<profile>.json`
  with command-line overrides taking precedence
- macOS LaunchAgent plist generation under `run/`, using direct foreground
  `xhubd serve`, `RunAtLoad`, `KeepAlive`, and launchd stdout/stderr logs
- `local` and explicit `lan` profiles, with non-loopback bind rejected unless
  LAN mode is explicitly allowed
- HTTP-first Node Hub bridge environment output without enabling production
  authority flags
- non-mutating daemon ops report with health/readiness, launchd status,
  `/runtime/http-metrics`, UI compatibility, and redacted log-tail evidence
- dry-run-by-default daemon maintenance retention for bounded log tails and
  report JSON cleanup, with explicit `--apply`
- dry-run-by-default daemon watchdog for launchd/readiness/stutter/pid-file
  guard checks, with explicit stale-pid repair only
- LAN access-key + LaunchAgent no-secret smoke command
- memory retrieval shadow smoke command

This is wired into the Node provider route authority bridge only behind
`XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_HTTP=1`. Node remains provider-routing
authority until a later cutover gate is added.

Implemented in existing Node Hub as opt-in provider-route shadow compare:

- `rust_provider_route_shadow_compare.js`
- `rust_provider_route_shadow_compare.test.js`
- `rust_provider_route_shadow_compare_service_hook.test.js`
- `rust_provider_route_authority_bridge.js`
- `rust_provider_route_authority_bridge.test.js`
- `rust_provider_route_authority_generate_hook.test.js`
- `services.js` invokes the comparer after `GetProviderKeyRouteDecision`
  responds when `XHUB_RUST_PROVIDER_ROUTE_SHADOW_COMPARE=1`
- `services.js` also has a default-off `HubAI.Generate` observe-only hook via
  `XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE=1`; it fire-and-forgets the Rust
  provider route check after Node selects its account and never changes Bridge
  payload construction
- the observe hook has `XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE_THROTTLE_MS`
  and `XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE_MAX_IN_FLIGHT` guards to keep
  hot-path telemetry from spawning unbounded Rust CLI work
- authority prep defaults to
  `XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH=1`; if a caller passes
  Node's selected `account_key`, Rust must select the same account or return
  fallback with `rust_provider_route_authority_account_mismatch`
- `tools/provider_route_generate_observe_runner.command` repeatedly exercises
  real `HubAI.Generate` calls through a fake Bridge and verifies Node Bridge
  payloads, Rust observe matches, warning counts, and per-call latency
- the comparer uses async `execFile`, per-key throttling, and max in-flight
  limits so Rust CLI checks do not block the Node event loop
- the comparer calls `xhubd provider compare`, which records report evidence
  and returns a `report_id` for match/mismatch logs
- `rust_provider_route_authority_bridge.js` can call `provider readiness` and
  `provider route` when explicitly enabled with
  `XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP=1`; it returns selected
  `account_key` only and is not wired to replace the production route decision
  yet

## Verification

Completed in the current environment:

```bash
bash -n tools/build_rust_hub.command
bash -n tools/run_rust_hub.command
bash -n tools/package_rust_hub.command
bash -n tools/run_packaged_rust_hub.command
```

Completed after installing Rust 1.95.0 through Homebrew:

```bash
cargo fmt --all -- --check
cargo build --workspace
cargo test --workspace
cargo test -p xhub-memory
cargo test -p xhubd
cargo run --bin xhubd -- provider route --model-id gpt-4o
cargo run --bin xhubd -- provider route --request-json '{"model_id":"claude-3.5-sonnet","provider":"claude","now_ms":1000}'
node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_provider_route_shadow_compare.test.js
node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_provider_route_shadow_compare_service_hook.test.js
bash "rust/rust hub/tools/provider_route_shadow_compare_smoke.command" --model-id gpt-4o
bash "rust/rust hub/tools/provider_route_shadow_compare_runner.command" --runs 10 --expect-ready --expect-zero-mismatch
cargo run -p xhubd -- doctor
cargo run -p xhubd -- serve-grpc
bash tools/run_rust_hub.command migrate
bash tools/run_rust_hub.command doctor
bash tools/run_rust_hub.command scheduler-smoke
bash tools/run_rust_hub.command scheduler status --include-queue-items
bash tools/run_rust_hub.command scheduler compare --node-in-flight-total 0 --node-queue-depth 0 --node-oldest-queued-ms 0
bash tools/run_rust_hub.command scheduler reports --limit 5
bash tools/run_rust_hub.command scheduler lease-shadow-report --limit 10
bash tools/run_rust_hub.command scheduler cutover-readiness --lease-report-limit 5
node tools/node_scheduler_shadow_compare.js --self-test
node tools/node_scheduler_shadow_compare.js --snapshot-json '{"paid_ai":{"in_flight_total":0,"queue_depth":0,"oldest_queued_ms":0}}'
node tools/node_hub_shadow_compare_smoke.js --runs 3 --interval-ms 250 --timeout-ms 15000 --expect-zero-mismatch
node tools/node_hub_shadow_compare_runner.js --self-test
node tools/node_hub_shadow_compare_runner.js --dry-run --no-start --duration-ms 1000 --report-interval-ms 500
node tools/node_hub_shadow_compare_runner.js --no-start --duration-ms 1000 --report-interval-ms 500 --expect-zero-mismatch
node tools/node_hub_shadow_compare_runner.js --duration-ms 2500 --report-interval-ms 500 --hub-host 127.0.0.1 --hub-port 55051 --hub-db-path /tmp/xhub-runner-test.sqlite3 --runtime-base-dir /tmp/xhub-runner-runtime --pairing-enable 0 --expect-zero-mismatch
node tools/scheduler_cutover_readiness_runner.js --self-test
node tools/scheduler_cutover_readiness_runner.js --dry-run --runs 2 --interval-ms 0 --expect-ready
node tools/scheduler_cutover_readiness_runner.js --runs 3 --interval-ms 250 --expect-ready --expect-zero-mismatch --timeout-ms 15000
node tools/scheduler_authority_runner.js --self-test
node tools/scheduler_authority_runner.js --dry-run
node tools/scheduler_authority_runner.js --runs 1 --timeout-ms 45000
node tools/scheduler_authority_runner.js --runs 1 --concurrency 3 --bridge-response-delay-ms 3000 --timeout-ms 70000 --expect-queued
node tools/scheduler_authority_runner.js --scenario queued-cancel --bridge-response-delay-ms 3000 --timeout-ms 70000
node tools/scheduler_authority_runner.js --scenario queued-timeout --timeout-ms 70000
node tools/node_hub_authority_live_runner.js --self-test
node tools/node_hub_authority_live_runner.js --dry-run --concurrency 3 --expect-queued
node tools/node_hub_authority_live_runner.js --runs 1 --timeout-ms 45000
node tools/node_hub_authority_live_runner.js --runs 3 --concurrency 3 --bridge-response-delay-ms 2500 --timeout-ms 90000 --expect-queued
node tools/node_hub_authority_live_runner.js --scenario queued-cancel --timeout-ms 70000
node tools/node_hub_authority_live_runner.js --scenario queued-timeout --timeout-ms 70000
node ../../x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_scheduler_authority_bridge.test.js
node ../../x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_scheduler_lease_shadow_bridge.test.js
node ../../x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_scheduler_bridge.test.js
node ../../x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_scheduler_shadow_compare.test.js
node ../../x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_scheduler_shadow_compare_service_hook.test.js
node --input-type=module -e "import { createSchedulerStatusBridge } from './x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_scheduler_bridge.js'; const bridge = createSchedulerStatusBridge({ env: { XHUB_RUST_SCHEDULER_STATUS_READ: '1', XHUB_RUST_HUB_ROOT: '/Users/andrew.xie/Documents/AX/rust/rust hub' } }); console.log(JSON.stringify(bridge.maybeReadStatus({ includeQueueItems: false, fallback: { queue_depth: 0, in_flight_total: 0 } })));"
node --input-type=module -e "import { createSchedulerLeaseShadowBridge } from './x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_scheduler_lease_shadow_bridge.js'; const id='live_node_shadow_'+process.pid+'_'+Date.now(); const bridge=createSchedulerLeaseShadowBridge({ env: { XHUB_RUST_SCHEDULER_LEASE_SHADOW:'1', XHUB_RUST_HUB_ROOT:'/Users/andrew.xie/Documents/AX/rust/rust hub', XHUB_RUST_SCHEDULER_LEASE_SHADOW_TIMEOUT_MS:'10000' } }); bridge.mirrorImmediateAcquire({ requestId:id, scopeKey:'project:live-node-shadow', project_id:'live-node-shadow', device_id:'device-live' }); bridge.mirrorRelease({ requestId:id }); await bridge.flush(); console.log(JSON.stringify({ok:true,state_size:bridge._state.size,request_id:id}));"
bash tools/xhubd_daemon.command env
bash tools/xhubd_daemon.command self-test
bash tools/daemon_ops_report.command --require-ready --max-log-bytes 4096
bash tools/daemon_maintenance.command --max-log-bytes 1024 --keep-report-files 10 --max-report-age-days 30
bash tools/lan_access_key_launchd_smoke.command
bash tools/memory_retrieval_shadow_smoke.command
bash tools/memory_retrieval_http_smoke.command
bash tools/run_rust_hub.command skills policy-readiness --max-preflight-audit-rows 100000 --max-policy-event-rows 100000
bash tools/skills_catalog_shadow_smoke.command
bash tools/skills_catalog_http_smoke.command --timeout-ms 30000
bash tools/ui_compatibility_no_product_ui_change_gate.command
bash tools/ops_readiness_gate.command --cycles 3 --interval-ms 250 --timeout-ms 30000 --max-endpoint-ms 2000 --max-cycle-ms 5000
bash tools/ops_soak_runner.command --cycles 5 --interval-ms 100 --timeout-ms 30000 --max-endpoint-ms 2000 --max-cycle-ms 5000
bash tools/scheduler_lease_shadow_http_bridge_smoke.command
bash tools/package_rust_hub.command
bash dist/<latest>/tools/run_rust_hub.command doctor
bash dist/<latest>/tools/run_rust_hub.command scheduler compare --node-in-flight-total 0 --node-queue-depth 0 --node-oldest-queued-ms 0
bash dist/<latest>/tools/run_rust_hub.command scheduler reports --limit 5
node dist/<latest>/tools/node_hub_shadow_compare_smoke.js --runs 3 --interval-ms 250 --timeout-ms 15000 --expect-zero-mismatch
node dist/<latest>/tools/scheduler_authority_runner.js --self-test
node dist/<latest>/tools/scheduler_authority_runner.js --dry-run
node dist/<latest>/tools/scheduler_authority_runner.js --runs 1 --timeout-ms 30000
node dist/<latest>/tools/scheduler_authority_runner.js --runs 1 --concurrency 3 --bridge-response-delay-ms 3000 --timeout-ms 70000 --expect-queued
node dist/<latest>/tools/scheduler_authority_runner.js --scenario queued-cancel --bridge-response-delay-ms 3000 --timeout-ms 70000
node dist/<latest>/tools/scheduler_authority_runner.js --scenario queued-timeout --timeout-ms 70000
node dist/<latest>/tools/node_hub_authority_live_runner.js --self-test
node dist/<latest>/tools/node_hub_authority_live_runner.js --runs 1 --timeout-ms 45000
node dist/<latest>/tools/node_hub_authority_live_runner.js --scenario queued-cancel --timeout-ms 70000
node dist/<latest>/tools/node_hub_authority_live_runner.js --scenario queued-timeout --timeout-ms 70000
```

Smoke results:

```text
doctor proto summary: services=12 rpcs=107 messages=300 enums=5
doctor migration_count: 5
HTTP /health: ok
HTTP /runtime/scheduler_status: ok
HTTP /contract/proto_summary: ok
gRPC bind 127.0.0.1:50152: ok
gRPC HubRuntime.GetSchedulerStatus shadow response: ok
gRPC HubRuntime.GetSchedulerStatus DB-backed queue view: ok
scheduler-smoke enqueue/acquire/release: ok
scheduler bridge enqueue/acquire/release/status: ok
scheduler shadow compare: ok
scheduler reports summary: ok
scheduler lease shadow evidence summary: ok
scheduler cutover readiness gate: ok
Node scheduler shadow caller self-test: ok
Node scheduler shadow caller live compare: ok
Node Hub shadow compare continuous smoke: ok
Node Hub shadow compare runner self-test/dry-run/no-start: ok
Node Hub shadow compare runner real Node Hub start: ok
Scheduler cutover readiness runner self-test/dry-run/live readiness: ok
Scheduler authority runner self-test/dry-run/live Generate authority: ok
Scheduler authority runner concurrent queued Generate authority: ok
Scheduler authority runner queued cancel terminal path: ok
Scheduler authority runner queued timeout terminal path: ok
Node Hub authority live runner self-test/dry-run: ok
Node Hub authority live runner real gRPC Generate authority: ok
Node Hub authority live runner 3x3 concurrent queued gRPC authority: ok
Node Hub authority live runner queued cancel/timeout gRPC terminal paths: ok
RHM-069 scheduler production authority plan self-test/dry-run: ok
RHM-069 scheduler production authority validation gates: ok
RHM-070 scheduler production authority apply self-test/status: ok
RHM-071 scheduler production authority session self-test/apply/status: ok
RHM-072 scheduler production authority persistent session LaunchAgent self-test/status: ok
RHM-073 scheduler production authority guard self-test/source/package: ok
RHM-074 route authority cutover guard self-test/source/package: ok
RHM-075 route authority prep session self-test/apply/status/package: ok
RHM-076 route authority prep runtime guard self-test/source/package: ok
RHM-077 route authority prep sustained guard self-test/source/package: ok
RHM-078 route authority prep session LaunchAgent self-test/install/status/package: ok
RHM-079 route authority production cutover blocker self-test/source/package: ok
Node Hub Rust scheduler status bridge/readiness gate tests: ok
Node Hub Rust scheduler status bridge live read: ok
Node Hub Rust scheduler authority bridge tests: ok
Node Hub Rust scheduler authority bridge live claim/release: ok
Node Hub Rust scheduler lease shadow bridge tests: ok
Node Hub Rust scheduler lease shadow bridge live enqueue/acquire-run/release: ok
Node Hub opt-in shadow compare module tests: ok
Node Hub GetSchedulerStatus service hook test: ok
package latest dist: ok
packaged doctor: ok
packaged scheduler compare: ok
packaged scheduler reports: ok
packaged Node Hub shadow compare continuous smoke: ok
packaged scheduler authority runner self-test/dry-run/live: ok
packaged scheduler authority runner queued cancel/timeout: ok
packaged Node Hub authority live runner self-test/live/concurrent/terminal: ok
model inventory shadow compare smoke: ok
model inventory HTTP bridge smoke: ok
XT Rust model inventory live bridge tests: ok
model inventory shadow compare runner self-test/dry-run: ok
model inventory sustained HTTP runner 3 reports readiness: ok
model inventory existing-runtime runner 2 reports readiness: ok
model route HTTP smoke remote/local prep: ok
Rust Hub browser status page root HTML: ok
Rust workspace tests after RHM-012: ok
Rust workspace tests after RHM-014: ok
RHM-015 UI compatibility contract docs: ok
RHM-015b UI compatibility no-product-change gate: ok
RHM-016 Node model route authority bridge tests: ok
RHM-016 Generate model route candidate audit hook: ok
RHM-016 adjacent provider/model route regressions: ok
RHM-017 model route candidate runner self-test/dry-run: ok
RHM-017 model route candidate runner isolated E2E readiness: ok
RHM-018 local model route candidate runner self-test/dry-run: ok
RHM-018 local model route candidate runner isolated E2E readiness: ok
RHM-019 skills catalog policy gate tests: ok
RHM-019 skills catalog shadow smoke: ok
RHM-019 skills catalog HTTP smoke: ok
RHM-021 skills preflight grant/audit tests: ok
RHM-021 skills preflight shadow smoke paths: ok
RHM-021 skills preflight HTTP smoke paths: ok
RHM-022 skill policy migration and DB roundtrip tests: ok
RHM-022 durable pin/grant shadow smoke paths: ok
RHM-022 durable pin/grant HTTP smoke paths: ok
RHM-020 model route combined candidate runner self-test/dry-run: ok
RHM-020 model route combined candidate runner isolated E2E readiness: ok
RHM-020 model route candidate evidence report authority-neutral schema: ok
RHM-020 Rust workspace fmt/test after skills preflight compile fix: ok
RHM-023 model route authority plan runner self-test/dry-run: ok
RHM-023 model route authority plan E2E readiness: ok
RHM-023 model route authority plan production-neutral schema: ok
RHM-023 Rust workspace fmt/check/test after plan runner: ok
RHM-026 remote model route prep trial E2E readiness: ok
RHM-026 local model route prep trial E2E readiness: ok
RHM-026 combined model route prep trial E2E readiness: ok
RHM-026 model route prep trial production-neutral schema: ok
RHM-026 Rust workspace fmt/check/test after prep trial runner: ok
RHM-024 skills preflight audit summary/prune tests: ok
RHM-024 skills preflight audit shadow smoke paths: ok
RHM-024 skills preflight audit HTTP smoke paths: ok
RHM-024 UI compatibility no-product-change gate: ok
RHM-025 skills policy revocation tests: ok
RHM-025 skills policy revocation shadow smoke paths: ok
RHM-025 skills policy revocation HTTP smoke paths: ok
RHM-025 UI compatibility no-product-change gate: ok
RHM-027 skills policy event migration and DB roundtrip tests: ok
RHM-027 skills policy event shadow smoke paths: ok
RHM-027 skills policy event HTTP smoke paths: ok
RHM-027 UI compatibility no-product-change gate: ok
RHM-029 skills policy event retention tests: ok
RHM-029 skills policy event retention shadow smoke paths: ok
RHM-029 skills policy event retention HTTP smoke paths: ok
RHM-029 UI compatibility no-product-change gate: ok
RHM-030 skills policy store readiness tests: ok
RHM-030 skills policy store readiness shadow smoke paths: ok
RHM-030 skills policy store readiness HTTP smoke paths: ok
RHM-030 memory retrieval HTTP regression smoke: ok
RHM-030 UI compatibility no-product-change gate: ok
RHM-032 ops readiness gate source/package warm-daemon cycles: ok
RHM-032 ops readiness gate UI compatibility check: ok
RHM-032 ops readiness gate no residual xhubd: ok
RHM-033 ready cache hit gate: ok
RHM-033 endpoint/cycle latency budget gate: ok
RHM-033 no production authority or UI change gate: ok
RHM-034 memory snapshot cache gate: ok
RHM-034 skills catalog cache gate: ok
RHM-034 memory/skills authority-neutral smoke: ok
RHM-035 HTTP backpressure unit tests: ok
RHM-035 ops readiness backpressure capability gate: ok
RHM-035 health exemption and no residual xhubd: ok
RHM-036 HTTP metrics unit tests: ok
RHM-036 HTTP metrics ops readiness gate: ok
RHM-036 HTTP metrics no detail/secret payload gate: ok
RHM-037 ops soak runner source/package warm-daemon cycles: ok
RHM-037 ops soak report schema and persisted report: ok
RHM-037 ops soak UI/no-authority/no-secret gates: ok
RHM-038 daemon manager syntax check: ok
RHM-038 launchd install/uninstall dry-run: ok
RHM-038 generated LaunchAgent plist lint: ok
RHM-038 live user LaunchAgent install with Application Support runtime copy: ok
RHM-038 launchd-status loaded/running/ready: ok
RHM-038 browser root HTTP 200 HTML: ok
RHM-038 model diagnostics ready through launchd runtime: ok
RHM-038 KeepAlive restart after terminating xhubd pid: ok
RHM-038 XT app rebuild/relaunch against launchd Rust Hub: ok
RHM-038b daemon manager syntax check after runtime signing patch: ok
RHM-038b launchd dry-run reports signing plan without runtime mutation: ok
RHM-038b live launchd install signs Application Support runtime copy: ok
RHM-038b launchd-status/health/XT compat preflight after signed restart: ok
RHM-038b runtime copy codesign verification: ok
RHM-039 daemon ops report syntax check: ok
RHM-039 daemon ops report live health/ready/http-metrics: ok
RHM-039 daemon ops report redacted log evidence and UI/no-authority gates: ok
RHM-040 daemon maintenance syntax check: ok
RHM-040 daemon maintenance dry-run source preview: ok
RHM-040 daemon maintenance temp apply log/report retention: ok
RHM-041 XT classic compatibility preflight unit tests: ok
RHM-042 XT classic gRPC probe unit tests: ok
RHM-042 Rust xhubd full test suite after gRPC probe: ok
RHM-042 release build after gRPC probe: ok
RHM-042 launchd reinstall with signed runtime after gRPC probe: ok
RHM-042 launchd `/ready` exposes gRPC probe capability: ok
RHM-042 default live compat endpoint remains fail-closed with probe disabled: ok
RHM-042 isolated HTTP+gRPC opt-in probe E2E reaches fail-closed cutover gate: ok
RHM-043 daemon ops gate syntax checks: ok
RHM-043 source daemon ops gate live launchd health/ready/http-metrics: ok
RHM-043 source daemon ops gate UI/no-authority/no-secret gates: ok
RHM-043 packaged daemon ops gate live launchd health/ready/http-metrics: ok
RHM-043 packaged dist content and no SwiftUI product files: ok
RHM-044 HTTP metrics recent window unit tests: ok
RHM-044 Rust xhubd full test suite after recent window: ok
RHM-044 source ops soak recent-window HTTP metrics: ok
RHM-044 source daemon ops gate recent/cumulative slow-budget fallback: ok
RHM-044 packaged ops soak recent-window HTTP metrics: ok
RHM-044 packaged daemon ops gate health/ready/http-metrics: ok
RHM-044 UI compatibility and no SwiftUI product files: ok
XT classic status writer compile/test guard after concurrent writer slice: ok
RHM-045 XT classic status writer rollback gate unit tests: ok
RHM-045 Rust xhubd full test suite after status writer gate: ok
RHM-045 release build after status writer gate: ok
RHM-045 launchd reinstall after status writer gate: ok
RHM-045 launchd `/ready` exposes explicit-cutover writer capability: ok
RHM-045 default live status writer POST remains fail-closed and wrote=false: ok
RHM-046 HTTP I/O timeout unit test: ok
RHM-046 Rust xhubd full test suite after I/O timeout guard: ok
RHM-046 source ops soak HTTP I/O timeout readiness gate: ok
RHM-046 source daemon ops gate recent-window slow budget: ok
RHM-046 packaged ops soak HTTP I/O timeout readiness gate: ok
RHM-046 packaged daemon ops gate health/ready/http-metrics: ok
RHM-046 UI compatibility and no SwiftUI product files: ok
RHM-047 XT file IPC shadow responder unit tests: ok
RHM-047 Rust xhubd full test suite after file IPC shadow responder: ok
RHM-047 release build after file IPC shadow responder: ok
RHM-047 launchd reinstall after file IPC shadow responder: ok
RHM-047 launchd `/ready` exposes file IPC shadow capability: ok
RHM-047 default live file IPC shadow status remains ready=false: ok
RHM-048 XT file IPC shadow drain processor unit tests: ok
RHM-048 Rust xhubd full test suite after drain processor: ok
RHM-048 release build after drain processor: ok
RHM-048 launchd reinstall after drain processor: ok
RHM-048 launchd `/ready` exposes file IPC shadow drain capability: ok
RHM-048 default live drain POST remains fail-closed and wrote=false: ok
RHM-049 XT file IPC shadow processor cycle unit tests: ok
RHM-049 Rust xhubd full test suite after processor cycle: ok
RHM-049 release build after processor cycle: ok
RHM-049 launchd reinstall after processor cycle: ok
RHM-049 launchd `/ready` exposes file IPC shadow cycle capability: ok
RHM-049 default live cycle POST remains fail-closed and wrote=false: ok
RHM-050 XT file IPC shadow supervisor loop unit tests: ok
RHM-050 Rust xhubd full test suite after supervisor loop: ok
RHM-050 release build after supervisor loop: ok
RHM-050 launchd reinstall after supervisor loop: ok
RHM-050 launchd `/ready` exposes file IPC shadow supervise capability: ok
RHM-050 default live supervise POST remains fail-closed and wrote=false: ok
RHM-059 XT file IPC shadow watcher smoke unit tests: ok
RHM-059 Rust xhubd full test suite after watcher smoke: ok
RHM-059 release build after watcher smoke: ok
RHM-059 launchd reinstall after watcher smoke: ok
RHM-059 launchd `/ready` exposes file IPC shadow watcher smoke capability: ok
RHM-059 default live watcher smoke POST remains fail-closed and wrote=false: ok
RHM-061 XT file IPC shadow watcher rollback smoke unit tests: ok
RHM-061 Rust xhubd full test suite after watcher rollback smoke: ok
RHM-061 release build after watcher rollback smoke: ok
RHM-061 launchd reinstall after watcher rollback smoke: ok
RHM-061 launchd `/ready` exposes file IPC shadow watcher rollback smoke capability: ok
RHM-061 default live watcher rollback smoke POST remains fail-closed and wrote=false: ok
RHM-064 XT file IPC watcher readiness gate unit tests: ok
RHM-064 Rust xhubd full test suite after watcher readiness gate: ok
RHM-064 release build after watcher readiness gate: ok
RHM-064 launchd reinstall after watcher readiness gate: ok
RHM-064 launchd `/ready` exposes file IPC watcher readiness capability: ok
RHM-064 default live watcher readiness POST remains fail-closed and wrote=false: ok
RHM-066 XT file IPC watcher start plan unit tests: ok
RHM-066 Rust xhubd full test suite after watcher start plan: ok
RHM-066 release build after watcher start plan: ok
RHM-066 launchd reinstall after watcher start plan: ok
RHM-066 launchd `/ready` exposes file IPC watcher start plan capability: ok
RHM-066 default live watcher start plan POST remains fail-closed and wrote=false: ok
RHM-067 XT file IPC watcher run once unit tests: ok
RHM-067 Rust xhubd full test suite after watcher run once: ok
RHM-067 release build after watcher run once: ok
RHM-067 launchd reinstall after watcher run once: ok
RHM-067 launchd `/ready` exposes file IPC watcher run once capability: ok
RHM-067 default live watcher run once POST remains fail-closed and wrote=false: ok
RHM-068 XT file IPC watcher run once smoke script syntax: ok
RHM-068 XT file IPC watcher run once source smoke: ok
RHM-068 Rust xhubd full test suite after watcher run once smoke: ok
RHM-068 release build after watcher run once smoke: ok
RHM-068 packaged dist includes watcher run once smoke: ok
RHM-071 XT file IPC watcher run once smoke report script syntax: ok
RHM-071 XT file IPC watcher run once source smoke report file: ok
RHM-071 packaged dist includes watcher run once report support: ok
RHM-072 xhubd daemon ops-gate syntax: ok
RHM-072 default ops-gate skips XT file IPC run once smoke: ok
RHM-072 opt-in ops-gate runs XT file IPC run once smoke: ok
RHM-072 packaged dist includes XT file IPC ops-gate support: ok
RHM-079 xhubd daemon ops-report syntax: ok
RHM-079 default ops-report skips XT file IPC run once smoke: ok
RHM-079 opt-in ops-report runs XT file IPC run once smoke: ok
RHM-079 packaged dist includes XT file IPC ops-report support: ok
RHM-080 XT file IPC watcher session unit tests: ok
RHM-080 Rust xhubd full test suite after watcher session: ok
RHM-080 release build after watcher session: ok
RHM-080 packaged dist includes watcher session support: ok
RHM-080 launchd `/ready` exposes file IPC watcher session capability: ok
RHM-080 default live watcher session POST remains fail-closed and wrote=false: ok
RHM-083 XT file IPC background watcher lifecycle unit tests: ok
RHM-083 Rust xhubd full test suite after background watcher lifecycle: ok
RHM-083 release build after background watcher lifecycle: ok
RHM-083 packaged dist includes background watcher lifecycle support: ok
RHM-083 launchd `/ready` exposes file IPC background watcher capability: ok
RHM-083 default live background watcher start POST remains fail-closed and wrote=false: ok
RHM-084 XT file IPC background watcher smoke script syntax: ok
RHM-084 XT file IPC background watcher source smoke: ok
RHM-084 packaged dist includes background watcher smoke: ok
RHM-051 daemon watchdog syntax checks: ok
RHM-051 source watchdog launchd/readiness/stutter/pid guard: ok
RHM-051 source daemon ops gate after watchdog guard: ok
RHM-051 packaged watchdog launchd/readiness/stutter/pid guard: ok
RHM-051 packaged daemon ops gate after watchdog guard: ok
RHM-051 UI compatibility and no SwiftUI product files: ok
RHM-052 watchdog launchd timer syntax checks: ok
RHM-052 source watchdog LaunchAgent plist generation and lint: ok
RHM-052 source watchdog timer install/uninstall dry-run: ok
RHM-052 source watchdog timer status reports not-installed without mutation: ok
RHM-052 UI compatibility and no SwiftUI product files: ok
RHM-058 cross-network readiness syntax checks: ok
RHM-058 source LAN access-key readiness gate without mutation: ok
RHM-058 packaged LAN access-key readiness gate without mutation: ok
RHM-058 UI compatibility and no SwiftUI product files: ok
RHM-062 cross-network installed gate syntax checks: ok
RHM-062 source installed gate fail-closed without loaded LAN timer: ok
RHM-062 packaged installed gate fail-closed without loaded LAN timer: ok
RHM-062 UI compatibility and no SwiftUI product files: ok
RHM-065 cross-network install plan syntax checks: ok
RHM-065 source install plan prints non-mutating commands without secrets: ok
RHM-065 packaged install plan prints non-mutating commands without secrets: ok
RHM-065 UI compatibility and no SwiftUI product files: ok
RHM-012 packaged dist content: ok
RHM-013 packaged dist content: ok
RHM-014 packaged dist content: ok
browser status page packaged dist content: ok
RHM-015 packaged dist content: ok
RHM-015b packaged UI compatibility gate content: ok
RHM-016 packaged dist content: ok
RHM-020 packaged dist content: ok
RHM-023 packaged dist content: ok
RHM-026 packaged dist content: ok
RHM-028 model route prep sustained runner self-test/dry-run: ok
RHM-028 model route prep sustained E2E readiness: ok
RHM-028 model route prep sustained production-neutral schema: ok
RHM-028 model route prep sustained runner node syntax check: ok
RHM-028 Rust workspace fmt/check/test after sustained runner: ok
RHM-028 packaged dist content: ok
RHM-031 model route diagnostics unit test: ok
RHM-031 model route diagnostics CLI smoke: ok
RHM-031 model route diagnostics HTTP smoke: ok
RHM-031 browser status page diagnostics link: ok
RHM-031 Rust workspace fmt/check/test: ok
RHM-031 packaged dist content: ok
RHM-031 packaged binary diagnostics smoke with source reports root: ok
RHM-080 route authority production blocker syntax: ok
RHM-080 route authority production switch contract self-test: ok
RHM-080 source blocker reports prep/candidate-safe and production-blocked: ok
RHM-080 Rust xhubd full test suite after blocker hardening: ok
RHM-080 UI compatibility and no SwiftUI product files: ok
RHM-080 packaged blocker self-test and UI compatibility gate: ok
RHM-080 packaged blocker validates current active source-root authority state: ok
RHM-081 active root upgrade plan syntax and self-test: ok
RHM-081 source active root upgrade plan report: ok
RHM-081 packaged active root upgrade plan report: ok
RHM-082 active root upgrade apply syntax and self-test: ok
RHM-082 source active root upgrade apply dry-run: ok
RHM-082 packaged active root upgrade apply dry-run: ok
RHM-083 active root upgrade relaunch wait syntax and self-test: ok
RHM-083 source active root upgrade relaunch wait dry-run: ok
RHM-083 packaged active root upgrade relaunch wait dry-run: ok
RHM-084 active root upgrade relaunch retry-open syntax and self-test: ok
RHM-084 source active root upgrade relaunch retry-open dry-run: ok
RHM-084 packaged active root upgrade relaunch retry-open dry-run: ok
RHM-088 XT file IPC runtime adapter candidate unit tests: ok
RHM-088 XT file IPC runtime adapter candidate smoke: ok
RHM-088 packaged runtime adapter candidate smoke and UI compatibility: ok
RHM-089 XT file IPC runtime adapter cancel unit test: ok
RHM-089 XT file IPC runtime adapter cancel smoke: ok
RHM-089 packaged runtime adapter cancel smoke and UI compatibility: ok
RHM-090 XT file IPC runtime adapter response collision unit test: ok
RHM-090 XT file IPC runtime adapter response collision smoke: ok
RHM-090 packaged runtime adapter response collision smoke and UI compatibility: ok
RHM-091 XT file IPC runtime adapter unsupported request unit test: ok
RHM-091 XT file IPC runtime adapter unsupported request smoke: ok
RHM-091 packaged runtime adapter unsupported request smoke and UI compatibility: ok
RHM-092 XT file IPC runtime adapter no selected model unit test: ok
RHM-092 XT file IPC runtime adapter no selected model smoke: ok
RHM-092 packaged runtime adapter no selected model smoke and UI compatibility: ok
RHM-093 XT file IPC runtime adapter overwrite gate unit test: ok
RHM-093 XT file IPC runtime adapter overwrite gate smoke: ok
RHM-093 packaged runtime adapter overwrite gate smoke and UI compatibility: ok
RHM-094 XT file IPC runtime adapter input size guard unit test: ok
RHM-094 XT file IPC runtime adapter input size guard smoke: ok
RHM-094 packaged runtime adapter input size guard smoke and UI compatibility: ok
RHM-095 XT file IPC runtime adapter oversized file unit test: ok
RHM-095 XT file IPC runtime adapter oversized file smoke: ok
RHM-095 packaged runtime adapter oversized file smoke and UI compatibility: ok
RHM-096 XT file IPC runtime adapter invalid JSON unit test: ok
RHM-096 XT file IPC runtime adapter invalid JSON smoke: ok
RHM-096 packaged runtime adapter invalid JSON smoke and UI compatibility: ok
RHM-097 provider/model production switch contract node bridge tests: ok
RHM-097 provider/model production session tool self-test: ok
RHM-097 production cutover blocker recognizes switch and rollback tooling: ok
RHM-098 route authority cutover guard production-switch contract reducer: ok
RHM-098 route authority prep sustained guard no longer self-blocks on implemented default-off production switches: ok
RHM-099 XT file IPC prep session apply/rollback tool: ok
RHM-103 XT file IPC live cutover preflight, apply plan, daemon relaunch plan, and write-status smoke plan: ok
RHM-104 XT file IPC live status writer heartbeat and dynamic production readiness: ok
RHM-104 live heartbeat soak gate: ok
RHM-105 XT file IPC production-aware run-once smoke: ok
RHM-105 XT file IPC production-aware background watcher smoke: ok
RHM-105 daemon ops gate production-aware child smoke reducer: ok
RHM-105 packaged production-aware shadow smoke evidence: ok
RHM-106 XT file IPC Rust-owned heartbeat fast refresh unit test: ok
RHM-106 XT classic compat Rust-owned live fast path unit test: ok
RHM-106 XT live heartbeat trusted fast refresh loop: ok
RHM-106 Rust xhubd full suite after heartbeat fast refresh: ok
RHM-107 XT live stale Rust-owned status repair unit test: ok
RHM-107 Rust xhubd full suite after on-demand heartbeat repair: ok
RHM-108 XT live status write lock and nonblocking repair unit tests: ok
RHM-108 live heartbeat soak authority timeout classification: ok
RHM-108 Rust xhubd full suite after nonblocking repair hardening: ok
RHM-108 live Group Container existing-status write fallback unit test: ok
RHM-109 live cutover status overlay without request-path file read unit test: ok
RHM-109 live heartbeat soak bounded status reader syntax gate: ok
RHM-110 production live stability gate syntax: ok
RHM-110 production live stability gate 10s live smoke with active dist root: ok
RHM-110 production live stability gate compact report and process sanity: ok
RHM-110 production live stability gate launchctl active-root default: ok
RHM-110 packaged production live stability gate 10s live smoke: ok
RHM-110 production live stability detached session 15s smoke: ok
RHM-110 packaged production live stability detached session 15s smoke: ok
RHM-111 production live stability checkpoint syntax: ok
RHM-111 production live stability checkpoint during active 8h session: ok
RHM-111 production live stability cross-package active session discovery: ok
RHM-111 packaged production live stability checkpoint during active 8h session: ok
RHM-112 production live slow-request delta checkpoint: ok
RHM-112 packaged production live slow-request delta checkpoint: ok
RHM-113 production live rolling checkpoint sidecar syntax: ok
RHM-113 production live rolling checkpoint sidecar foreground loop: ok
RHM-113 production live rolling checkpoint sidecar detached start/status: ok
RHM-113 packaged production live rolling checkpoint sidecar: ok
RHM-114 rolling checkpoint status next checkpoint ETA: ok
RHM-114 rolling checkpoint stop-safe incomplete status: ok
RHM-114 packaged rolling checkpoint loop: ok
RHM-115 baseline-aware slow request carryover syntax: ok
RHM-115 baseline-aware slow request carryover live checkpoint: ok
RHM-115 packaged baseline-aware slow request carryover checkpoint: ok
RHM-116 readiness cache nonblocking hot-path unit test: ok
RHM-116 HTTP metrics regression tests after readiness hot-path change: ok
RHM-116 Rust xhubd full suite after readiness hot-path change: ok
RHM-117 live cutover on-demand status-file creation unit test: ok
RHM-117 stale Rust-owned status fast disk repair unit test: ok
RHM-117 XT classic compatibility unit suite: ok
RHM-117 Rust xhubd full suite after live status disk repair: ok
RHM-117 UI compatibility and no SwiftUI product files: ok
RHM-117 packaged Rust Hub doctor and UI compatibility gate: ok
RHM-117 live launchd deploy from packaged xhubd: ok
RHM-117 live daemon ops gate after deploy: ok
RHM-117 live write-status smoke on /Users/andrew.xie/RELFlowHub: ok
RHM-117 live production stability checkpoint after deploy: ok
RHM-117 rolling checkpoint sidecar restarted from packaged root: ok
RHM-118 production stability session script syntax: ok
RHM-118 cross-package active session status discovery: ok
RHM-118 packaged Rust Hub doctor and UI compatibility gate: ok
RHM-118 packaged active production session adoption: ok
RHM-118 packaged dist contains no SwiftUI product files: ok
RHM-119 production stability active status syntax: ok
RHM-119 active session status observability during active 8h session: ok
RHM-119 packaged active session status observability: ok
RHM-120 production stability session script syntax: ok
RHM-120 rolling checkpoint sidecar status discovery: ok
RHM-120 zero-preserving sidecar status merge: ok
RHM-120 packaged Rust Hub doctor and UI compatibility gate: ok
RHM-120 packaged active rolling checkpoint sidecar adoption: ok
RHM-120 packaged dist contains no SwiftUI product files: ok
RHM-121 production stability supervision status syntax: ok
RHM-121 active supervision status during active 8h session: ok
RHM-121 packaged supervision status: ok
RHM-122 production stability session script syntax: ok
RHM-122 no-state CLI context fallback: ok
RHM-123 X-Hub Node production env passthrough Swift test: ok
RHM-123 rebuilt X-Hub.app production runtime guard after relaunch: ok
RHM-123 live heartbeat soak after rebuilt X-Hub.app relaunch: ok
RHM-123 daemon ops and production live checkpoint after rebuilt X-Hub.app relaunch: ok
RHM-123 UI compatibility and no SwiftUI product files: ok
RHM-124 current active-root production authority status: ok
RHM-124 latest packaged Rust Hub doctor and UI compatibility gate: ok
RHM-124 refreshed 8h live stability session start: ok
RHM-124 refreshed rolling checkpoint sidecar first checkpoint: ok
RHM-124 daemon ops recent slow-request budget after refresh: ok
RHM-124 process sanity without target/debug or target/release xhubd: ok
RHM-125 Rust memory writer unit tests: ok
RHM-125 Rust skills execution manifest/preflight unit tests: ok
RHM-125 Rust xhubd full suite after memory/skills production surfaces: ok
RHM-125 memory writer and skills execution production smoke: ok
RHM-125 packaged memory writer and skills execution production smoke: ok
RHM-125 process sanity without target/debug or target/release xhubd: ok
RHM-126 memory/skills live-cutover guard implementation: ok
RHM-126 final dist packaged and doctor/UI/no-Swift checks: ok
RHM-126 live launchd relaunch with Rust memory writer and skills execution authority: ok
RHM-126 live memory write / retrieval / skill execute / secret-denial smoke: ok
RHM-126 ops gate with required memory/skills Rust authority: ok
RHM-127 active root converged to package-store final root: ok
RHM-127 X-Hub relaunch inherits final Rust Hub root: ok
RHM-127 production stability gate accepts memory/skills authority carryover: ok
RHM-127 package-store rolling checkpoint sidecar latest two checkpoints: ok
RHM-127 live memory/skills smoke after active-root convergence: ok
RHM-127 UI compatibility and no SwiftUI product files after convergence: ok
RHM-128 domain/public endpoint auth gate implementation: ok
RHM-128 domain readiness dry-run gate: ok
RHM-128 XT pairing export bundle without stdout key leak: ok
RHM-128 domain smoke script syntax and localhost self-check: ok
RHM-128 Rust xhubd full suite after domain readiness change: ok
RHM-129 domain activation plan implementation: ok
RHM-129 domain activation plan self-test and placeholder rejection: ok
RHM-130 active-root plan/apply production-aware syntax and self-tests: ok
RHM-130 live dry-run skips route prep under provider/model production authority: ok
RHM-130 packaged active-root plan/apply production-aware dry-run: ok
RHM-130 scheduler guard accepts required Rust memory/skills production authority: ok
RHM-131 XT file IPC heartbeat auto-discovers live base dir from classic compat: ok
```

## Next Task

Continue post-cutover hardening:

- let the package-store 8h live stability session and 4h rolling checkpoint
  sidecar continue to collect evidence;
- keep `current`, launchctl `XHUB_RUST_HUB_ROOT`, and X-Hub Node inherited root
  aligned to the same final package;
- keep `/ready` and `/xt/classic-hub-compat` under the recent slow-request
  budget while memory writer and skills execution stay in Rust authority;
- choose the real domain/tunnel provider, run
  `cross_network_domain_activation_plan.command` with the final HTTPS URL, then
  execute its access-key, launchd, watchdog, pairing, and domain-smoke steps in
  order before XT uses the domain outside the first LAN pairing;
- continue pruning old reports/logs through dry-run first, then apply only after
  the retention plan is reviewed.
