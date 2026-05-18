# RHM-132 Cross Network Remote Route Gate

Date: 2026-05-14

## Scope

Align Rust Hub domain activation with the updated X-Hub / XT remote-access
direction: XT should not treat raw LAN IPs, loopback, or brittle public IPs as
stable off-LAN connectivity. A real cutover must use a named HTTPS domain,
tailnet DNS name, managed tunnel, or an explicitly acknowledged VPN raw host.

## Tooling

- `tools/cross_network_remote_route_gate.command`
- `tools/cross_network_remote_route_gate.js`

The gate is non-mutating and prints
`xhub.rust_hub.cross_network_remote_route_gate.v1` evidence. It classifies the
remote entry as:

- `stable_named / dns_name`
- `stable_named / tailnet_dns`
- `vpn_raw / tailscale_headscale_ip`
- `vpn_raw / private_or_vpn_ip`
- `public_raw_ip`
- `lan_only`
- `loopback`
- `link_local`
- `wildcard`

Default policy:

- stable HTTPS DNS and tailnet DNS pass;
- raw VPN/tailnet/private IPs require `--allow-vpn-raw-host`;
- raw public IPs are blocked unless the explicit dev escape hatch
  `--allow-public-raw-ip` is passed;
- loopback, wildcard, link-local, `.local`, and single-label LAN names are
  blocked for remote-ready semantics;
- HTTP is blocked by default for remote routes.

## Activation Plan Integration

`tools/cross_network_domain_activation_plan.command` now embeds the route-gate
analysis and adds `remote_route_semantics_gate` as the second activation step.
The plan itself also fails if the route gate has blocking issues, so a raw
public IP cannot silently reach the launchd/watchdog/pairing steps.

## Operational Meaning

This does not enable public networking by itself and does not change the XT UI.
It prevents a false green state where a first-LAN pairing address or raw IP is
mistaken for stable home/office/road connectivity.

The intended production shape remains:

- localhost-bound Rust daemon;
- HTTPS domain/tunnel or tailnet DNS as the public entry;
- `/health` unauthenticated for process managers;
- `/ready` and operational APIs protected by the access-key gate;
- domain smoke before XT uses the endpoint off LAN.

The future official relay model is represented as `official_relay_default_ready:
false`; this gate prepares the naming/security semantics without pretending a
relay exists yet.

## Verification

- `node --check tools/cross_network_remote_route_gate.js`: ok
- `node --check tools/cross_network_domain_activation_plan.js`: ok
- `bash -n tools/cross_network_remote_route_gate.command`: ok
- `bash -n tools/cross_network_domain_activation_plan.command`: ok
- `bash tools/cross_network_remote_route_gate.command --self-test`: ok
- `bash tools/cross_network_domain_activation_plan.command --self-test`: ok
- stable HTTPS domain route gate: ok
- raw public IP route gate rejection: ok
- domain activation plan embeds route-gate evidence: ok
- domain activation plan rejects raw public IP by default: ok
- packaged Rust Hub doctor and route-gate self-test: ok
- packaged domain activation plan embeds and enforces route-gate evidence: ok
- active root converged to package `rust-hub-20260514T092945Z`: ok
- live daemon ops gate after active-root convergence: ok
- process sanity without `target/debug/xhubd` or `target/release/xhubd`: ok
