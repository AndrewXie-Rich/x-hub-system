# RHM-052 Watchdog Launchd Timer

## Goal

Make the Rust Hub watchdog installable as a user-level macOS LaunchAgent timer
so long-running installs can keep writing health evidence without manual runs.

This timer only runs the dry-run watchdog report. It does not restart, stop,
bootstrap, uninstall, or repair the daemon process.

## Commands

```bash
bash tools/xhubd_daemon.command watchdog-plist
bash tools/xhubd_daemon.command watchdog-install --dry-run
bash tools/xhubd_daemon.command watchdog-status
bash tools/xhubd_daemon.command watchdog-uninstall --dry-run
```

The installed timer command is:

```text
watchdog
```

It writes:

```text
reports/daemon_watchdog_<UTC>.json
```

## Defaults

- LaunchAgent label: `<daemon-label>.watchdog`
- Start interval: `900` seconds
- Install plist path: `~/Library/LaunchAgents/<watchdog-label>.plist`
- Preview plist path: `run/<watchdog-label>.plist`
- stdout log: `logs/xhubd.watchdog.out.log`
- stderr log: `logs/xhubd.watchdog.err.log`

## Options

- `--watchdog-launchd-label <label>`
- `--watchdog-plist-path <path>`
- `--watchdog-install-plist-path <path>`
- `--watchdog-interval-sec <seconds>`
- `--watchdog-max-slow-requests <n>`
- `--watchdog-maintenance-max-log-bytes <bytes>`
- `--watchdog-keep-report-files <n>`
- `--watchdog-max-report-age-days <days>`

## Boundary

The timer keeps:

- `production_authority_change=false`,
- `daemon_restarted=false`,
- `daemon_stopped=false`,
- no memory writer authority in Rust,
- no skills execution authority in Rust,
- no SwiftUI product UI changes.

## Verification

```bash
node --check tools/xhubd_daemon.js
bash tools/xhubd_daemon.command watchdog-plist
plutil -lint run/com.ax.xhubd.local.watchdog.plist
bash tools/xhubd_daemon.command watchdog-install --dry-run
bash tools/xhubd_daemon.command watchdog-status
bash tools/xhubd_daemon.command watchdog-uninstall --dry-run
bash tools/ui_compatibility_no_product_ui_change_gate.command
```
