# RHM-040 Daemon Maintenance Retention

Status: implemented 2026-05-07

## Decision

Rust Hub has an explicit daemon maintenance command for bounded log and report
retention. The command defaults to dry-run preview. It only changes files when
the operator passes `--apply`.

This is local file maintenance only. It does not start, stop, restart,
bootstrap, or uninstall the daemon. It does not switch production authority,
does not execute third-party skills, does not write canonical memory, and does
not change XT UI.

## Implemented Commands

Preview:

```bash
bash "tools/xhubd_daemon.command" maintenance --max-log-bytes 10485760 --keep-report-files 100 --max-report-age-days 30
bash "tools/daemon_maintenance.command" --max-log-bytes 10485760 --keep-report-files 100 --max-report-age-days 30
```

Apply:

```bash
bash "tools/daemon_maintenance.command" --apply --max-log-bytes 10485760 --keep-report-files 100 --max-report-age-days 30
```

Options:

- `--apply`: apply retention. Without this flag the command is dry-run only.
- `--max-log-bytes <n>`: keep only the newest tail bytes for each known daemon
  log file when over limit. Default 10485760.
- `--keep-report-files <n>`: keep newest report JSON files per report
  directory. Default 100.
- `--max-report-age-days <n>`: delete report JSON files older than this age.
  Default 30. Use `0` to disable age-based deletion.
- `--reports-dir <path>`: override report retention scope for targeted package
  or test cleanup.
- `--report-path <path>`: maintenance report path, default
  `reports/daemon_maintenance_<UTC>.json`.

The report schema is:

```text
xhub.rust_hub.daemon_maintenance_report.v1
```

## Behavior

Log maintenance scans the source/manual daemon log directory and the
Application Support launchd runtime log directory. Known log files:

- `xhubd.out.log`,
- `xhubd.err.log`,
- `xhubd.launchd.out.log`,
- `xhubd.launchd.err.log`.

When `--apply` is set and a log is over `--max-log-bytes`, the command keeps
the newest tail bytes in the same file. This preserves recent evidence while
bounding disk usage and keeps the daemon process running.

Report maintenance scans source/runtime `reports/` directories by default and
only targets `.json` files. It sorts newest first per directory, keeps the
configured newest count, and optionally deletes files older than the configured
age.

## Safety Boundary

The maintenance report keeps:

```json
{
  "dry_run": true,
  "node_remains_authority": true,
  "production_authority_change": false,
  "daemon_restarted": false,
  "daemon_stopped": false,
  "memory_writer_authority_in_rust": false,
  "skills_execution_authority_in_rust": false
}
```

When `--apply` is used, only local log/report files in the resolved retention
scope are changed.

## Verification

```bash
node --check "tools/xhubd_daemon.js"
bash -n "tools/daemon_maintenance.command"
bash "tools/daemon_maintenance.command" --max-log-bytes 1024 --keep-report-files 10 --max-report-age-days 30
```

Apply verification should use a temporary directory:

```bash
bash "tools/daemon_maintenance.command" --apply --log-dir /tmp/xhub-maint/logs --launchd-runtime-root /tmp/xhub-maint/runtime --reports-dir /tmp/xhub-maint/reports --report-path /tmp/xhub-maint/maintenance.json --max-log-bytes 10 --keep-report-files 1 --max-report-age-days 0
```

The command is copied into packaged `dist/rust-hub-*` bundles.
