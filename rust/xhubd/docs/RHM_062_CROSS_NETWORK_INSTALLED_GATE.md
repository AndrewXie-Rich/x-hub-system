# RHM-062 Cross-Network Installed Gate

## Goal

Add a strict shortcut command for validating an already installed LAN/cross-device
Rust Hub deployment.

The command is still read-only. It does not start, stop, restart, bootstrap,
install, uninstall, repair, or rotate keys.

## Command

```bash
bash tools/cross_network_installed_gate.command --profile lan --public-host <LAN-IP>
```

This wraps:

```bash
bash tools/cross_network_readiness_gate.command \
  --require-live-ready \
  --require-launchd-loaded \
  --require-watchdog-timer \
  --profile lan \
  --public-host <LAN-IP>
```

## Required Installed State

- LAN profile is explicit.
- Bind host is non-loopback.
- Public host is not a placeholder.
- Access-key file exists, is non-empty, and is mode `0600`.
- Live `/ready` reports ready.
- Daemon LaunchAgent is loaded.
- Watchdog timer LaunchAgent is loaded.
- UI compatibility gate passes.
- Rust memory writer authority remains disabled.
- Rust skills execution authority remains disabled.

## Boundary

The gate preserves:

- `production_authority_change=false`,
- `daemon_restarted=false`,
- `daemon_stopped=false`,
- `key_printed=false`,
- no SwiftUI product UI changes,
- Node/XT production authority unchanged.

## Verification

```bash
bash -n tools/cross_network_installed_gate.command
bash tools/cross_network_installed_gate.command --profile lan --public-host 192.0.2.10 --access-key-file /tmp/xhub-cross-network/secrets/xhubd_lan_access_key
```

The second command should fail until a real LAN daemon and watchdog timer are
installed and loaded. That fail-closed result is expected for source/package
tests that do not mutate launchd state.
