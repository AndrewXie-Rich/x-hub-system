# RHM-136 Swift Shell Remote Entry Authority

Date: 2026-05-15

## Scope

Make Rust Hub the authority for the remote-entry decision that the Swift Hub
settings shell presents to users.

Swift should keep the product UI, macOS permission prompts, and button actions.
Rust owns the policy and emits a stable JSON decision for:

- user-owned HTTPS domain or managed tunnel;
- no-domain private network entry, such as MagicDNS, Tailscale/Headscale IP,
  WireGuard, or ZeroTier-style tunnel address;
- blocked states when only LAN names, loopback, or raw public IP are available.

## Interfaces

- `xhubd network remote-entry-candidates`
- `GET /network/remote-entry-candidates`
- compatibility aliases:
  - `GET /network/remote-entry`
  - `GET /remote/entry-candidates`

The response schema is `xhub.rust_hub.remote_entry_candidates.v1`.

## Product Boundary

This makes the future single-Hub shape explicit:

- Rust core decides the recommended remote entry and reports policy.
- Swift shell displays the recommendation and applies user-approved settings.
- Pairing/export still happens only after readiness and smoke gates pass.

## No-Domain Policy

The Rust core may recommend a no-domain private entry only when it sees a stable
private-network candidate:

- tailnet DNS, such as `*.ts.net` or `*.tailscale.net`;
- Tailscale/Headscale `100.64.0.0/10`;
- private IP on a tunnel-looking interface, such as `utun`, `wg`, `zt`, or
  `zerotier`.

Normal LAN addresses, loopback, wildcard binds, `.local` names, and raw public IP
addresses are not presented as stable remote entries.

## Verification

- `cargo test -p xhubd network_bridge`: ok
- `cargo test -p xhubd public_base_url_readiness`: ok

## Implementation Update 2026-06-02

XT now consumes the Rust `GET /network/remote-entry-candidates` decision through
a lightweight background client. The paired-route snapshot can mark the stable
remote route source as `rust_remote_entry_candidate`, so stale cached profile
hosts no longer have to be the only source of the formal remote entry.

The XT refresh is intentionally non-blocking:

- fetch timeout: 0.8s;
- refresh throttle: 10s;
- route snapshot reads cached data only;
- raw public IP candidates remain ignored unless explicitly handled by the
  older manual endpoint path.

Verification:

- `swift test --filter 'HubAIClientRemoteConnectOptionsTests|RustHubRemoteEntryCandidatesClientTests|HubRemoteHostPolicyTests'`: ok
- live remote-entry preferred host: `andrew.tailbe79cd.ts.net`
- live domain smoke: `/health` 200, unauthenticated `/ready` 401,
  authenticated `/ready` 200 with `cross_network_ready=true`
- rebuilt XT bundle: `build/X-Terminal.app`
