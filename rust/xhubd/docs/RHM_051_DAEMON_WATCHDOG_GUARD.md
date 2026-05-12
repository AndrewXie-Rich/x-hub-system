# RHM-051 Daemon Watchdog Guard

## Goal

Keep long-running Rust Hub daemon installs easier to operate without changing
XT UI or moving production authority into Rust.

The watchdog is a local ops guard for launchd/manual daemon health. It produces
a compact evidence report that can be run manually, by cron, or by a future
LaunchAgent timer.

## Commands

```bash
bash tools/xhubd_daemon.command watchdog \
  --max-slow-requests 0 \
  --maintenance-max-log-bytes 10485760 \
  --keep-report-files 100 \
  --max-report-age-days 30

bash tools/daemon_watchdog.command \
  --max-slow-requests 0 \
  --maintenance-max-log-bytes 10485760 \
  --keep-report-files 100 \
  --max-report-age-days 30
```

Report schema:

```text
xhub.rust_hub.daemon_watchdog_report.v1
```

Default output path:

```text
reports/daemon_watchdog_<UTC>.json
```

## Checks

The watchdog checks:

- launchd loaded/running state on macOS,
- `/health` and `/ready`,
- `/runtime/http-metrics`,
- recent-window slow-request budget,
- HTTP I/O timeout and backpressure readiness flags,
- source and launchd runtime pid-file staleness,
- maintenance dry-run summary,
- UI no-product-change gate,
- memory writer and skills execution authority boundaries,
- cross-network auth gate visibility,
- secret-leak guard on the report.

## Mutations

Default behavior is dry-run/report-only.

The only supported mutation is stale or invalid pid-file removal:

```bash
bash tools/daemon_watchdog.command --apply --repair-stale-pid
```

The watchdog does not stop, restart, bootstrap, kickstart, uninstall, or
otherwise mutate the daemon process. If launchd needs repair, the report emits
a recommended action instead of performing it.

## Authority Boundary

The watchdog keeps:

- `production_authority_change=false`,
- `daemon_restarted=false`,
- `daemon_stopped=false`,
- `memory_writer_authority_in_rust=false`,
- `skills_execution_authority_in_rust=false`,
- no SwiftUI product files in the Rust package.

## Verification

```bash
node --check tools/xhubd_daemon.js
bash -n tools/daemon_watchdog.command
bash tools/daemon_watchdog.command --max-slow-requests 0
bash tools/ui_compatibility_no_product_ui_change_gate.command
bash tools/package_rust_hub.command
```
