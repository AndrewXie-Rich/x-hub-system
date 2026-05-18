# X-Hub Remote Route Setup

Use `tools/hub_remote_route_doctor.command` before giving a remote address to
X-Terminal. The same command works for a public DNS name, MagicDNS/tailnet name,
or a VPN encrypted IP.

```bash
tools/hub_remote_route_doctor.command \
  --host hub.your-domain.example \
  --grpc-port 50058 \
  --pairing-port 50059
```

## Product Default

`hub.xhubsystem.com` is not a shared product endpoint. It is just one operator's
Hub domain. Each Hub owner should configure one of their own stable addresses:

- `hub.<their-domain>` for direct DNS or a raw TCP tunnel/reverse proxy
- `<machine>.<tailnet>.ts.net` for Tailscale/Headscale MagicDNS
- `100.x.y.z` for a Tailscale/Headscale IP
- another VPN/tunnel IP that every intended XT device can reach

The Hub invite link and secure remote setup pack should carry that configured
host. XT should not need to know any vendor-owned or Andrew-owned domain.

Recommended order:

1. **Own domain, DNS-only/raw TCP**: best default when the user controls DNS and
   can expose or tunnel TCP `50058/50059`.
2. **No domain: private VPN/MagicDNS**: safest self-hosted option when users do
   not own a domain and accept Tailscale/Headscale/WireGuard/ZeroTier on both
   Hub and XT.
3. **Raw public IP**: temporary only; avoid using it in long-lived invite packs.
4. **LAN-only**: fine for same-network use, but not a formal remote route.

## No-Domain Users

Users do not need to buy a domain just to get stable cross-network XT access.
The least complex no-domain path is a private network:

1. Install or join the same private network on the Hub Mac and every XT Mac.
   Tailscale/Headscale, WireGuard, and ZeroTier are all acceptable.
2. In Hub Settings > LAN/gRPC > Advanced Settings, use **No domain? Use private
   network entry**. If Hub detects a stable tunnel address such as `100.x.y.z`
   or a WireGuard/ZeroTier `10.x` address on a tunnel interface, it can apply
   that host as External Address.
3. Copy the invite link or secure remote setup pack from Hub and open it on XT.

This keeps the default user experience domain-free while avoiding brittle raw
public IPs. If no private network address is detected, the product should keep
the user in LAN-only mode and clearly ask them to choose one stable route:
their own domain, a private VPN, or a future X-Hub relay/tunnel.

## What Must Be Reachable

XT needs two TCP paths to the Hub:

- pairing: `host:50059`
- gRPC: `host:50058`

`/pairing/discovery` on the pairing port should return JSON with
`internet_host_hint`, `grpc_port`, and `pairing_port`.

## Stable DNS Name

Use a DNS name when the Hub has a stable public endpoint or a raw TCP tunnel.
If the domain is hosted on Cloudflare, keep the record DNS-only unless you have
a raw TCP product such as Spectrum. The normal orange-cloud proxy is not enough
for arbitrary gRPC/pairing TCP ports.

For a user-owned domain, the minimum DNS setup is:

- create an `A` record such as `hub.your-domain.example`
- point it to the Hub's public IP, or to the raw TCP tunnel/reverse-proxy
  endpoint that forwards TCP `50058/50059` to the Hub
- verify from outside the Hub network:

```bash
nc -vz hub.your-domain.example 50059
nc -vz hub.your-domain.example 50058
curl -fsS http://hub.your-domain.example:50059/pairing/discovery
```

If the ISP changes the public IP, use DDNS, a provider API update, or a raw TCP
tunnel/relay instead of asking XT users to re-enter a raw IP.

## VPN Or Encrypted IP

Tailscale, Headscale, WireGuard, and ZeroTier are preferred for long-term remote
XT access. Put the tailnet/MagicDNS name or encrypted IP in Hub Settings >
LAN/gRPC > Advanced Settings > External Address, then copy the Hub invite link
or secure remote setup pack.

Examples:

- `mini.tailnet.ts.net`
- `100.96.10.8`
- `10.7.0.12`

Only use these addresses when every XT device joins the same VPN/tailnet.
Tailscale/Headscale `100.64.0.0/10` addresses are treated as formal encrypted
IP entries directly. RFC1918 addresses such as `10.x`, `172.16-31.x`, or
`192.168.x` should be used only when they are assigned by a VPN; set them
explicitly in External Address if the app cannot infer the tunnel interface.

## Current Mac Tailscale Note

The Homebrew `tailscaled` daemon requires root on macOS unless it is run in
userspace networking mode. For normal desktop use, the official Tailscale macOS
app is the least surprising path.

Official install links:

- Tailscale download: https://tailscale.com/download
- macOS direct download: https://tailscale.com/download/mac
- macOS install guide: https://tailscale.com/kb/1016/install-mac

Install Tailscale on both sides of the private route: the Hub Mac and every XT
Mac that should reach the Hub through MagicDNS or a `100.x` Tailscale IP. All
machines must be signed into the same tailnet, or explicitly shared into a
tailnet that can reach the Hub.

For a long-running Hub host:

1. Install `/Applications/Tailscale.app`.
2. Approve `Tailscale Network Extension` in System Settings.
3. Add `Tailscale` to macOS Login Items.
4. Remove or disable `~/Library/LaunchAgents/homebrew.mxcl.tailscale.plist`
   if it exists; that user LaunchAgent cannot create the normal tunnel.
5. Put the MagicDNS name or `100.64.0.0/10` Tailscale IP in Hub Settings >
   LAN/gRPC > Advanced Settings > External Address.

Verify the full service path with:

```bash
tools/tailscale_hub_service_doctor.command
```

When MagicDNS is enabled, this doctor prefers the MagicDNS name as the default
External Address recommendation. If MagicDNS is not available, it falls back to
the local `100.x` Tailscale IP.

For a different tailnet host, MagicDNS name, or encrypted IP:

```bash
tools/tailscale_hub_service_doctor.command --host <magic-dns-or-100.x-ip>
```

You can still run the generic remote route doctor for DNS, public IP, and other
VPN/tunnel routes:

```bash
tools/hub_remote_route_doctor.command --host <magic-dns-or-100.x-ip>
```
