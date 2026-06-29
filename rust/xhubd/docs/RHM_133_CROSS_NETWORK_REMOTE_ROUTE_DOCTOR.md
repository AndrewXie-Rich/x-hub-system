# RHM-133 Cross Network Remote Route Doctor

Date: 2026-05-14

## Scope

Add a non-mutating doctor for planned or live XT off-LAN Rust Hub routes. This
sits between the route semantics gate and the strict domain smoke:

- the gate decides whether the remote entry is allowed at all;
- the doctor explains DNS, tailnet, and HTTP readiness;
- the smoke remains the strict post-activation pass/fail check.

## Tooling

- `tools/cross_network_remote_route_doctor.command`
- `tools/cross_network_remote_route_doctor.js`
- `tools/xhubd_daemon.command cross-network-readiness --require-cross-network-remote-route-smoke`
- `tools/daemon_ops_gate.command --require-cross-network-remote-route-smoke`

The doctor emits `xhub.rust_hub.cross_network_remote_route_doctor.v1`.

It reuses `cross_network_remote_route_gate.js` and adds:

- DNS A/AAAA visibility for stable named hosts;
- local Tailscale/Headscale interface detection from macOS network interfaces;
- public `/health` probe;
- unauthenticated `/ready` probe, expected to be rejected for public endpoints;
- optional authenticated `/ready` probe when `--access-key-file` is supplied;
- planning-safe `--no-network` mode;
- strict post-activation `--require-live-http --require-auth-ready` mode.

## Policy

The doctor does not start, stop, or restart daemons. It does not change
launchctl env, launchd plists, XT settings, pairing bundles, memory authority,
skills authority, or product UI.

It never prints the access key. Output reports only whether the key file was
configured/readable/empty.

## Example

Planning before the tunnel exists:

```bash
bash tools/cross_network_remote_route_doctor.command \
  --public-base-url https://hub.your-domain.com \
  --no-network
```

Live post-activation check:

```bash
bash tools/cross_network_remote_route_doctor.command \
  --public-base-url https://hub.your-domain.com \
  --access-key-file secrets/xhubd_domain_access_key \
  --require-live-http \
  --require-auth-ready
```

Use `cross_network_domain_smoke.command` after this for the stricter final
domain pass/fail gate.

Installed/cutover gate:

```bash
bash tools/cross_network_installed_gate.command \
  --profile domain \
  --public-base-url https://hub.your-domain.com \
  --public-endpoint \
  --access-key-file secrets/xhubd_domain_access_key \
  --require-cross-network-remote-route-smoke
```

`--require-cross-network-remote-route-smoke` keeps `/ready` lightweight and local
but makes ops/cutover gates fail closed unless the public URL proves `/health`,
unauthenticated `/ready` rejection, and authenticated `/ready=true` through the
existing remote-route doctor.

## Verification

- `node --check tools/cross_network_remote_route_doctor.js`: ok
- `bash -n tools/cross_network_remote_route_doctor.command`: ok
- `bash -n tools/package_rust_hub.command`: ok
- `bash tools/cross_network_remote_route_doctor.command --self-test`: ok
- stable HTTPS no-network planning doctor: ok
- raw public IP no-network doctor rejection: ok
- packaged dist `dist/rust-hub-20260514T094114Z`: ok
- packaged doctor, route planning, and UI compatibility checks: ok
- active root converged to `rust-hub-20260514T094114Z`: ok
- live scheduler production guard after X-Hub relaunch: ok
- live provider/model route production runtime guard after X-Hub relaunch: ok
- live daemon ops gate after active-root convergence: ok
- process sanity: X-Hub PID 262, relflowhub_node PID 267, xhubd PID 34694,
  no `target/debug/xhubd` or `target/release/xhubd`: ok
