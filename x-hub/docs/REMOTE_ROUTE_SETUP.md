# X-Hub Remote Route Setup

Use `tools/hub_remote_route_doctor.command` before giving a remote address to
X-Terminal. XT needs two TCP paths to the Hub:

- pairing: `host:50059`
- gRPC: `host:50058`

`/pairing/discovery` on the pairing port should return JSON with
`internet_host_hint`, `grpc_port`, `pairing_port`, and `tls_mode`.

```bash
tools/hub_remote_route_doctor.command \
  --host hub.your-domain.example \
  --grpc-port 50058 \
  --pairing-port 50059
```

## Product Default

`hub.xhubsystem.com` is not a shared product endpoint. It is just one operator's
Hub domain. Each Hub owner should configure their own stable address and let the
Hub invite link or secure remote setup pack carry that host to XT.

Recommended order, from simple to difficult:

1. Same Wi-Fi / LAN for first pairing and local use.
2. Tailscale IP or MagicDNS when users accept installing Tailscale on roaming XT.
3. Tailscale subnet router for fixed networks.
4. Public IP direct for temporary validation.
5. DNS-only domain direct for user-owned domains.
6. Cloudflare Spectrum raw TCP when the account has Spectrum.
7. VPS raw TCP relay / reverse proxy.
8. Tailscale Funnel raw TCP after port/protocol adaptation.
9. HTTPS/WebSocket 443 gateway as future product work.

Out of scope for this route plan:

- Other VPN IP routes: WireGuard / ZeroTier / Headscale.
- Cloudflare Tunnel arbitrary TCP.

## Route Matrix

| Route | Current status | XT install | Security | Convenience | Use when |
| --- | --- | --- | --- | --- | --- |
| Same Wi-Fi / LAN | Supported | None | High | High on same network, none across networks | First pairing, home-only use |
| Tailscale IP / MagicDNS | Supported, auto-detects `100.x` | Tailscale on each roaming XT | High | Medium | No domain, stable cross-network use |
| Tailscale subnet router | Manual, verify first | Not needed only for fixed networks behind a subnet router | High | Medium | Office/home site-to-site routes |
| Public IP direct | Supported for temporary validation | None | Medium-low | High until IP changes | Quick smoke test, emergency access |
| DNS-only domain direct | Supported | None | Medium | High | User controls DNS and port forwarding |
| Cloudflare Spectrum raw TCP | Hub/XT compatible, external setup required | None | Medium-high | High | User has Spectrum and wants no XT network install |
| VPS raw TCP relay / reverse proxy | Hub/XT compatible, external deployment required | None | Medium-high | High | User wants self-controlled public relay |
| Tailscale Funnel raw TCP | Pending adaptation | None after public exposure | Medium | High | Later route, public endpoint acceptable |
| HTTPS/WebSocket 443 gateway | Not implemented | None | High | Highest | Future product-grade remote access |

All remote routes should keep mTLS enabled and use an invite token. Public,
DNS-only, Spectrum, and relay routes should also restrict allowed source IPs
where practical and keep paid AI / Web Fetch disabled unless explicitly needed.

## Same Wi-Fi / LAN

This is already supported and should remain the first-pairing path.

1. Put XT and Hub on the same Wi-Fi/LAN.
2. Open the invite link or scan the QR code from Hub Settings.
3. XT stores the Hub host, pairing port, gRPC port, invite token, and mTLS client
   material.

This route does not satisfy the cross-network requirement by itself. Once XT
leaves the LAN, it will reconnect only if a stable external address is also
configured.

## Tailscale IP Or MagicDNS

This is the simplest long-term no-domain route when installing Tailscale on XT
is acceptable.

1. Install the official Tailscale app on the Hub Mac and each XT Mac.
2. Sign all devices into the same tailnet.
3. In Hub Settings > LAN/gRPC > Advanced Settings, set External Address to:
   - the Hub `100.x.y.z` Tailscale IP, or
   - the Hub MagicDNS name such as `<machine>.<tailnet>.ts.net`.
4. Keep transport mode on mTLS.
5. Copy the secure remote setup pack or invite link to XT.
6. Verify:

```bash
tools/hub_remote_route_doctor.command --host 100.x.y.z
tools/hub_remote_route_doctor.command --host <machine>.<tailnet>.ts.net
```

Current implementation notes:

- Hub detects `100.64.0.0/10` Tailscale addresses as no-domain candidates.
- The no-domain button now recommends Tailscale only, not other VPN interfaces.
- XT must have a route into the same tailnet. For roaming XT, that normally
  means installing Tailscale on XT.

## Tailscale Subnet Router

This route can avoid installing Tailscale on every device only when the XT
device is inside another fixed network that already routes into the tailnet.
Roaming laptops still need their own route into Tailscale.

1. Deploy and approve a Tailscale subnet router for the Hub LAN.
2. Confirm the XT-side network can reach the Hub LAN IP.
3. Set Hub External Address to the reachable Hub LAN IP or internal DNS name.
4. Run the remote route doctor from a network equivalent to XT's network.

Use this only after both TCP ports and `/pairing/discovery` pass. The Hub app
does not auto-detect this route because a private `192.168.x` or `10.x` address
is ambiguous without a verified subnet route.

## Public IP Direct

This route is supported for temporary validation and emergency use. It is not a
good long-term default because the IP can change and both raw TCP ports are
exposed to the internet.

1. Find the Hub network's public IP.
2. On the router/NAT, forward TCP `50059` and `50058` to the Hub Mac.
3. In Hub Settings, set External Address to the public IP.
4. Use the invite link on XT.
5. Verify from outside the Hub network:

```bash
nc -vz <public-ip> 50059
nc -vz <public-ip> 50058
curl -fsS http://<public-ip>:50059/pairing/discovery
```

Keep mTLS and invite-token validation enabled. Restrict allowed source IPs if
the XT networks are predictable.

## DNS-Only Domain Direct

Use this when the user owns a domain and can expose TCP `50059/50058` directly.

1. Create `A`/`AAAA` records such as `hub.your-domain.example`.
2. Point them to the Hub public IP or to a raw TCP endpoint that forwards to the
   Hub.
3. If DNS is hosted on Cloudflare, keep the record DNS-only. The normal
   orange-cloud HTTP proxy does not forward these raw TCP ports.
4. Forward TCP `50059/50058` to the Hub Mac.
5. Set External Address to the DNS name.
6. Copy the secure remote setup pack or invite link.

If the ISP changes the public IP, use DDNS, provider API updates, Cloudflare
Spectrum, or a VPS relay instead of asking XT users to re-enter a raw IP.

## Cloudflare Spectrum Raw TCP

This is the Cloudflare route that can keep XT install-free while avoiding direct
router exposure. It requires Spectrum support on the Cloudflare account.

1. Put a hostname such as `hub.your-domain.example` in Cloudflare.
2. Create raw TCP Spectrum apps for:
   - external TCP `50059` -> origin `Hub-or-relay:50059`
   - external TCP `50058` -> origin `Hub-or-relay:50058`
3. Set Hub External Address to the Spectrum hostname.
4. Verify the same doctor command against the Spectrum hostname.

Do not use Cloudflare Tunnel arbitrary TCP for this plan. The Hub/XT protocol
expects raw TCP reachability on the pairing and gRPC ports.

## VPS Raw TCP Relay / Reverse Proxy

This is the self-controlled long-term route when users do not want Tailscale on
XT and do not have Spectrum.

1. Provision a VPS with a stable public IP and DNS name.
2. Run a raw TCP forwarder such as HAProxy, nginx `stream`, systemd socket
   forwarding, or a small relay service.
3. Forward VPS TCP `50059/50058` to the Hub reachable path.
4. Secure the VPS with a firewall, automatic restarts, logs, and source IP
   restrictions where possible.
5. Set Hub External Address to the VPS DNS name.
6. Verify with the doctor and then copy the secure remote setup pack.

Security depends on the relay hardening. Keep mTLS and invite tokens on, because
the relay is still carrying the Hub's raw pairing/gRPC traffic.

## Tailscale Funnel Raw TCP

This remains a later route. It is attractive because XT would not need
Tailscale after the Funnel endpoint is public, but the current Hub/XT pairing
ports still need explicit port/protocol adaptation and verification.

Do not present this as ready until:

- the public endpoint can carry both pairing and gRPC traffic,
- the external host/port mapping is encoded in the setup pack, and
- the doctor passes from a normal non-tailnet network.

## Future HTTPS/WebSocket 443 Gateway

This is the cleanest product experience but the largest development task. The
gateway should expose one HTTPS `443` hostname, authenticate with invite tokens
and mTLS-equivalent client identity, and bridge to the local pairing/gRPC
services behind the scenes.

Until this exists, XT must still receive a host plus pairing/gRPC ports.
