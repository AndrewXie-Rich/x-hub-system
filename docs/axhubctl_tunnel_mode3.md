# Mode 3 Remote (Tailscale/Headscale) + axhubctl tunnel

This guide is for teammates who want to connect to the Hub remotely without opening any public ports.

## One-time setup (LAN pairing)

1. On the Hub machine, open the Hub UI:
   - Settings -> gRPC -> Copy Bootstrap Command
2. On your terminal machine, paste and run the bootstrap command.
   - Replace `<device_name>` with something readable (e.g. "alice-mbp").
3. Wait for the Hub owner to approve the pairing request in the Hub UI.
4. Verify on your terminal machine:

```sh
~/.local/bin/axhubctl list-models
```

This creates:
- `~/.axhub/hub.env` (token + TLS/mTLS paths)
- `~/.axhub/client_kit/` (self-contained client kit)

## Remote usage (Mode 3)

Prereq: you are connected to the tailnet (Tailscale/Headscale) and can reach the Hub tailnet IP/hostname.

1. Install the local TCP tunnel as a background service (macOS):

```sh
~/.local/bin/axhubctl tunnel --hub <hub_tailnet_host_or_ip> --grpc-port 50051 --local-port 50051 --install
```

2. Check tunnel service status:

```sh
~/.local/bin/axhubctl tunnel --status
```

3. Use the Hub via the local tunnel:

```sh
~/.local/bin/axhubctl remote list-models
~/.local/bin/axhubctl remote chat --model <model_id> --prompt "hello"
```

## Troubleshooting

- Tunnel service logs:
  - `~/.axhub/tunnel_service.out.log`
  - `~/.axhub/tunnel_service.err.log`
- Reinstall service (macOS):

```sh
~/.local/bin/axhubctl tunnel --uninstall
~/.local/bin/axhubctl tunnel --hub <hub_tailnet_host_or_ip> --grpc-port 50051 --local-port 50051 --install
```

- If you see `source_ip_not_allowed` (IP allowlist):
  - Ask the Hub owner to check: Settings -> gRPC -> Denied (IP allowlist)
  - Add your tailnet IP/CIDR to your device entry (one-click in the Hub UI).
