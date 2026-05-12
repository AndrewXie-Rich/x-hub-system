# RHM-065 Cross-Network Install Plan

## Goal

Print a non-mutating LAN/cross-device install plan for the Rust Hub daemon,
watchdog timer, strict installed gate, and rollback.

The command does not execute any install, uninstall, restart, stop, or key
rotation. It only prints commands and paths.

## Command

```bash
bash tools/cross_network_install_plan.command --profile lan --public-host <LAN-IP>
```

Equivalent daemon-manager command:

```bash
bash tools/xhubd_daemon.command cross-network-install-plan --profile lan --public-host <LAN-IP>
```

## Output

The JSON report uses:

```text
xhub.rust_hub.cross_network_install_plan.v1
```

It includes ordered steps for:

- readiness preflight,
- access-key file initialization or permission repair,
- daemon LaunchAgent dry-run,
- watchdog timer dry-run,
- daemon LaunchAgent install,
- watchdog timer install,
- strict installed-state gate,
- watchdog rollback,
- daemon rollback.

## Boundary

The plan keeps:

- `production_authority_change=false`,
- `daemon_restarted=false`,
- `daemon_stopped=false`,
- `key_printed=false`,
- `secret_leak=false`,
- no SwiftUI product UI changes.

## Verification

```bash
node --check tools/xhubd_daemon.js
bash -n tools/cross_network_install_plan.command
bash tools/cross_network_install_plan.command --profile lan --public-host 192.0.2.10
bash tools/ui_compatibility_no_product_ui_change_gate.command
```
