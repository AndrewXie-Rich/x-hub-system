# RHM-039 Daemon Ops Report

Status: implemented 2026-05-07

## Decision

Rust Hub has a non-mutating daemon ops report command for long-running
deployments. It collects the current daemon health, readiness, launchd state,
HTTP latency metrics, UI compatibility status, and redacted log tails into one
persisted JSON report.

This is diagnostics only. It does not start, stop, restart, bootstrap, or
uninstall the daemon. It does not switch production authority, does not execute
third-party skills, does not write canonical memory, and does not change XT UI.

## Implemented Commands

```bash
bash "tools/xhubd_daemon.command" ops-report --require-ready --max-log-bytes 4096
bash "tools/daemon_ops_report.command" --require-ready --max-log-bytes 4096
```

Options:

- `--report-path <path>`: JSON report path, default
  `reports/daemon_ops_<UTC>.json`.
- `--max-log-bytes <n>`: redacted tail bytes per log file, default 8192.
- `--require-ready`: exit non-zero when health/readiness is unavailable.

The report schema is:

```text
xhub.rust_hub.daemon_ops_report.v1
```

## Coverage

The report includes:

- resolved daemon profile and HTTP base URL,
- source/manual daemon status,
- user LaunchAgent status when installed,
- `/health` and `/ready` responses,
- `/runtime/http-metrics` final snapshot,
- total and slow HTTP request counts,
- redacted tails for source and Application Support daemon logs,
- log size summary and rotation recommendation,
- UI compatibility gate result,
- authority-neutral flags.

## Redaction Boundary

The log evidence redacts:

- bearer tokens,
- `X-XHub-Access-Key`,
- `XHUB_RUST_HTTP_ACCESS_KEY`,
- `XHUB_RUST_HUB_ACCESS_KEY`,
- JSON/text `api_key`, `access_key`, `token`, and `secret` values,
- OpenAI-style `sk-*` tokens,
- long hex-like secrets.

The command keeps:

```json
{
  "node_remains_authority": true,
  "production_authority_change": false,
  "memory_writer_authority_in_rust": false,
  "skills_execution_authority_in_rust": false,
  "secret_leak": false
}
```

## Operational Use

Use this when the daemon has been running for hours or days and the UI feels
slow, a device cannot connect, or a memory/skills/model bridge appears stale.
The report gives one file with readiness, launchd, latency, and recent log
evidence without disturbing the running service.

## Verification

```bash
node --check "tools/xhubd_daemon.js"
bash -n "tools/daemon_ops_report.command"
bash "tools/daemon_ops_report.command" --require-ready --max-log-bytes 4096
```

Package verification:

```bash
bash "tools/package_rust_hub.command"
bash "dist/<latest>/tools/daemon_ops_report.command" --max-log-bytes 1024
```

The command is copied into packaged `dist/rust-hub-*` bundles.
