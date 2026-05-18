# RHM-135 Cross Network Provider Candidate Plan

Date: 2026-05-15

## Scope

Add a non-mutating provider planner for the real XT cross-network entry.

The planner answers which route should be used next:

- same-tailnet Tailscale Serve;
- public Tailscale Funnel;
- Cloudflare Tunnel;
- user-managed HTTPS reverse proxy.

## Tooling

- `tools/cross_network_provider_candidate_plan.command`
- `tools/cross_network_provider_candidate_plan.js`

The planner emits `xhub.rust_hub.cross_network_provider_candidate_plan.v1`.

It does not run `tailscale serve`, `tailscale funnel`, `cloudflared`, launchd
install, daemon restart, pairing export, or product UI changes. It only detects
local provider availability and prints the next commands.

## Current Host Finding

On this machine, Tailscale is installed and the current backend state is
`Running`. The detected MagicDNS candidate is:

```text
https://andrew.tailbe79cd.ts.net
```

That is the best immediate route for XT devices signed into the same tailnet,
but `tailscale serve --bg 50151` is currently blocked because Serve is not
enabled on this tailnet. `tailscale serve status --json` currently returns an
empty config. For XT devices not on the same tailnet, use Tailscale Funnel or a
user-owned HTTPS tunnel/reverse proxy and rerun the planner with the final
public URL.

## Policy

- Rust Hub stays loopback-bound behind the provider route.
- `/health` remains unauthenticated.
- `/ready` and operational APIs require the access key once the public endpoint
  profile is applied.
- Same-tailnet Serve is not the same as public internet exposure.
- Public internet exposure requires Funnel, Cloudflare Tunnel, or a user-managed
  HTTPS reverse proxy.

## Verification

- `node --check tools/cross_network_provider_candidate_plan.js`: ok
- `bash -n tools/cross_network_provider_candidate_plan.command`: ok
- `bash tools/cross_network_provider_candidate_plan.command --self-test`: ok
- provider auto detection with Tailscale MagicDNS candidate: ok
- readiness bundle planning for `https://andrew.tailbe79cd.ts.net`: ok
- packaged access-key fallback from dist root to source repo secrets: ok
- Tailscale backend moved to `Running`, Health empty: ok
- strict live readiness remains blocked while tailnet Serve is disabled: ok
