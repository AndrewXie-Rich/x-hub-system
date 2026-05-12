# RHM-058 Cross-Network Readiness Gate

## Goal

Add a non-mutating readiness gate for LAN/cross-device Rust Hub deployment
before exposing the daemon beyond localhost.

This gate is for operator evidence only. It does not start, stop, restart,
bootstrap, uninstall, repair, or install anything.

## Command

```bash
bash tools/cross_network_readiness_gate.command --profile lan --public-host <LAN-IP>
```

Equivalent daemon-manager command:

```bash
bash tools/xhubd_daemon.command cross-network-readiness --profile lan --public-host <LAN-IP>
```

For installed always-on deployments, add:

```bash
--require-live-ready --require-launchd-loaded --require-watchdog-timer
```

## Checks

- explicit LAN profile or `--allow-lan`,
- non-loopback bind host,
- non-placeholder public host,
- configured access-key file,
- existing non-empty access-key file,
- `0600` access-key file mode,
- launchd plist environment carries only the access-key file path,
- watchdog timer plist is installable,
- UI compatibility gate passes,
- Rust memory writer authority stays disabled,
- Rust skills execution authority stays disabled,
- optional live `/ready`,
- optional daemon LaunchAgent loaded state,
- optional watchdog timer LaunchAgent loaded state.

## Boundary

The report keeps:

- `production_authority_change=false`,
- `daemon_restarted=false`,
- `daemon_stopped=false`,
- `key_printed=false`,
- `secret_leak=false`,
- no SwiftUI product UI changes,
- Node/XT production authority unchanged.

## Verification

```bash
node --check tools/xhubd_daemon.js
bash -n tools/cross_network_readiness_gate.command
bash tools/xhubd_daemon.command access-key-init --profile lan --public-host 192.0.2.10 --access-key-file /tmp/xhub-cross-network-readiness/secrets/xhubd_lan_access_key
bash tools/cross_network_readiness_gate.command --profile lan --public-host 192.0.2.10 --access-key-file /tmp/xhub-cross-network-readiness/secrets/xhubd_lan_access_key
bash tools/ui_compatibility_no_product_ui_change_gate.command
```
