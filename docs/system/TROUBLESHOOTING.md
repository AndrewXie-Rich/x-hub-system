# Troubleshooting

Use failure codes and doctor output before changing implementation.

## Hub Management Page Cannot Be Reached

Likely causes:

- Hub app is not running.
- Node sidecar is not running.
- HTTP admin port changed.
- Browser is pointed at an old port.
- macOS privacy or launchd blocked a background runtime path.
- Rust daemon is running but production Node Hub is not.

Check:

- Hub app status.
- Node Hub process.
- Doctor output.
- configured admin URL and port.
- whether you are opening Rust diagnostic HTTP instead of Hub product UI.

## OAuth Does Not Open a Web Page

Likely causes:

- OAuth source is not wired to a browser launch path.
- callback server did not start.
- provider source key is wrong.
- browser open command was blocked.
- OAuth flow is being invoked from a non-GUI context.

Check:

- provider OAuth manager status.
- callback redirect URI.
- auth index/account id after import.
- Hub logs and Doctor.

## Quota Does Not Show

Quota windows require the right upstream account type.

For ChatGPT-style 5-hour and 7-day windows, Hub needs:

- ChatGPT/OAuth account metadata
- account id
- auth index or direct access token metadata
- successful call to upstream usage endpoint

Plain OpenAI-compatible API keys usually cannot expose ChatGPT subscription windows.

## Hub Is Slow

Check:

- Node sidecar process load.
- Rust daemon `/ready` and HTTP latency metrics.
- ops gate recent slow-request samples.
- repeated UI polling.
- model/runtime status scans.
- large local memory or model inventory files.

Rust Hub has backpressure, readiness cache, and latency diagnostics specifically to find these issues.

## XT Cannot Connect to Hub

Likely causes:

- pairing expired or invalid
- Hub route changed
- LAN/internet host mismatch
- first pair attempted off-LAN
- stale hub status file
- port conflict

Use XT Doctor. Do not bypass same-LAN first-pair or owner approval.

## Model Is Not Available

For local models:

- artifact path missing
- unsupported format
- runtime provider not ready
- insufficient memory
- stale runtime status

For paid models:

- key disabled
- account in cooldown
- quota blocked
- model not in allowlist
- grant/policy denied
- provider route has no ready candidate

## Skill Is Blocked

Likely causes:

- package not trusted
- manifest incompatible
- skill not pinned
- missing capability grant
- runtime surface not available
- local approval required
- package revoked or quarantined

Use skill readiness and preflight output instead of guessing.

## Rust Daemon Is Running But Product Behavior Did Not Change

This is usually expected.

Rust Hub is often running in shadow, diagnostic, or candidate mode. It does not become product authority unless a specific bridge/cutover gate enables it.
