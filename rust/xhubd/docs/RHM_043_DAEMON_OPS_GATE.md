# RHM-043 Daemon Ops Gate

Status: implemented 2026-05-07

## Decision

Rust Hub has a daily/manual ops gate that combines daemon health, readiness,
launchd status, HTTP latency metrics, maintenance dry-run, redacted log
evidence, and UI/authority boundary checks into one report.

This is diagnostics only. It does not start, stop, restart, bootstrap, or
uninstall the daemon. It does not apply maintenance retention. It does not
switch production authority, does not execute third-party skills, does not
write canonical memory, and does not change XT UI.

## Implemented Commands

```bash
bash "tools/xhubd_daemon.command" ops-gate --max-slow-requests 0 --maintenance-max-log-bytes 10485760 --keep-report-files 100 --max-report-age-days 30
bash "tools/daemon_ops_gate.command" --max-slow-requests 0 --maintenance-max-log-bytes 10485760 --keep-report-files 100 --max-report-age-days 30
```

Options:

- `--report-path <path>`: JSON report path, default
  `reports/daemon_ops_gate_<UTC>.json`.
- `--max-slow-requests <n>`: allowed slow-request count from
  `/runtime/http-metrics`, default 0. New daemons apply this to
  `recent_slow_requests`; older daemons fall back to lifetime `slow_requests`.
- `--max-log-bytes <n>`: redacted tail bytes per log file included in the gate
  report, default 4096.
- `--maintenance-max-log-bytes <n>`: dry-run maintenance log budget, default
  10485760.
- `--keep-report-files <n>`: dry-run maintenance report count budget, default
  100.
- `--max-report-age-days <n>`: dry-run maintenance report age budget, default
  30.
- `--no-require-ready`: allow the gate to pass without health/readiness.

The report schema is:

```text
xhub.rust_hub.daemon_ops_gate.v1
```

## Pass Criteria

By default the gate passes only when:

- `/health` is available,
- `/ready` is ready,
- `/runtime/http-metrics` is available,
- recent-window slow requests are within budget when available,
- UI compatibility reports no product UI change,
- Rust browser page remains diagnostic-only,
- Node remains production authority,
- Rust memory writer authority remains disabled,
- Rust skills execution authority remains disabled,
- no secret-like evidence is returned.

Maintenance dry-run output is included as evidence. A maintenance need is
reported but does not fail the gate unless a future caller chooses to enforce
that outside this command.

## Safety Boundary

The gate keeps:

```json
{
  "maintenance_dry_run": true,
  "node_remains_authority": true,
  "production_authority_change": false,
  "daemon_restarted": false,
  "daemon_stopped": false,
  "memory_writer_authority_in_rust": false,
  "skills_execution_authority_in_rust": false,
  "secret_leak": false
}
```

## Verification

```bash
node --check "tools/xhubd_daemon.js"
bash -n "tools/daemon_ops_gate.command"
bash "tools/daemon_ops_gate.command" --max-slow-requests 0 --maintenance-max-log-bytes 10485760 --keep-report-files 100 --max-report-age-days 30
```

Package verification:

```bash
bash "tools/package_rust_hub.command"
bash "dist/<latest>/tools/daemon_ops_gate.command" --max-slow-requests 0 --maintenance-max-log-bytes 10485760 --keep-report-files 100 --max-report-age-days 30
```

The command is copied into packaged `dist/rust-hub-*` bundles.
