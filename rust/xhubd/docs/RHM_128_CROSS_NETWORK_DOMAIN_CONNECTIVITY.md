# RHM-128 Cross Network Domain Connectivity

Date: 2026-05-13

## Scope

Prepare Rust Hub for XT clients that pair on the same network, then continue
connecting from home, office, and road networks through a stable domain.

## Design

The domain path is explicit and fail-closed:

- local profile remains `127.0.0.1`;
- LAN profile still requires `--profile lan` or `--allow-lan`;
- domain/tunnel profile uses `--public-base-url https://hub.example.com`;
- `--public-endpoint` forces access-key auth even when the daemon only binds
  localhost behind a tunnel;
- `/health` stays unauthenticated for process managers;
- `/ready` and all operational APIs require `Authorization: Bearer <key>` or
  `X-XHub-Access-Key` once a public endpoint is enabled;
- `/ready.capabilities.cross_network_ready` can become true for either
  non-loopback LAN bind or explicit domain/tunnel readiness.

## New Tooling

- `config/daemon_profile.domain.example.json`
- `tools/cross_network_domain_activation_plan.command`
- `tools/cross_network_pairing_export.command`
- `tools/cross_network_domain_smoke.command`

`cross_network_domain_activation_plan.command` prints a real-domain activation
sequence without mutating state. It rejects placeholder URLs, makes the existing
local launchd label the default activation target, and includes rollback steps.

`cross_network_pairing_export.command` writes a `0600` XT pairing JSON bundle
with endpoint, hub id, reconnect policy, and access key. The command output
does not print the key.

`cross_network_domain_smoke.command` validates a real public URL:

- `/health` reachable;
- unauthenticated `/ready` rejected;
- authenticated `/ready` accepted;
- cross-network auth gate present;
- optional cross-network readiness required by default.

## Example

```bash
bash tools/xhubd_daemon.command access-key-init \
  --profile domain \
  --public-base-url https://hub.example.com \
  --public-endpoint

bash tools/cross_network_readiness_gate.command \
  --profile domain \
  --public-base-url https://hub.example.com \
  --public-endpoint

bash tools/cross_network_pairing_export.command \
  --profile domain \
  --public-base-url https://hub.example.com \
  --public-endpoint

bash tools/cross_network_domain_smoke.command \
  --public-base-url https://hub.example.com \
  --access-key-file secrets/xhubd_domain_access_key
```

## Verification

- `node --check tools/xhubd_daemon.js`: ok
- `node --check tools/cross_network_domain_smoke.js`: ok
- `bash -n tools/cross_network_pairing_export.command`: ok
- `bash -n tools/cross_network_domain_smoke.command`: ok
- `bash -n tools/package_rust_hub.command`: ok
- `cargo test -p xhubd public_base_url_readiness`: ok
- `cargo test -p xhubd`: ok
- domain readiness dry run with `https://hub.example.com`: ok
- pairing export dry run with redacted stdout: ok
- localhost domain-smoke script self-check: ok
