# RHM-134 Cross Network Domain Readiness Bundle

Date: 2026-05-14

## Scope

Add a single non-mutating bundle for the final real domain/tunnel preflight
before XT uses Rust Hub from another network.

The bundle combines:

- remote route semantics gate;
- remote route doctor;
- domain activation plan;
- strict domain smoke command generation.

## Tooling

- `tools/cross_network_domain_readiness_bundle.command`
- `tools/cross_network_domain_readiness_bundle.js`

The bundle emits `xhub.rust_hub.cross_network_domain_readiness_bundle.v1`.

It does not start, stop, relaunch, or reconfigure the daemon. It does not write
launchd plists, access keys, pairing bundles, XT settings, memory data, skills
state, or product UI files.

When run from a packaged dist, the default access-key path first checks
`dist/secrets/xhubd_domain_access_key`, then falls back to the source repo
`secrets/xhubd_domain_access_key` if present. The key is not copied into the
package and is never printed.

## Example

Planning mode before the public route exists:

```bash
bash tools/cross_network_domain_readiness_bundle.command \
  --public-base-url https://hub.your-domain.com \
  --no-network
```

Strict final preflight after the tunnel/domain is live:

```bash
bash tools/cross_network_domain_readiness_bundle.command \
  --public-base-url https://hub.your-domain.com \
  --access-key-file secrets/xhubd_domain_access_key \
  --require-live-http \
  --require-auth-ready
```

The generated `strict_domain_smoke_after_activation` command remains the final
post-activation pass/fail check.

## Policy

- Stable HTTPS DNS or tailnet DNS is the official route shape.
- Raw public IP remains blocked by default.
- Raw VPN/tailnet/private IP requires explicit `--allow-vpn-raw-host`.
- `/health` is the only unauthenticated public probe.
- `/ready` and operational APIs must stay behind the access-key gate.
- XT pairing export happens only after the bundle and strict domain smoke pass.

## Verification

- `node --check tools/cross_network_domain_readiness_bundle.js`: ok
- `bash -n tools/cross_network_domain_readiness_bundle.command`: ok
- `node --check tools/cross_network_domain_activation_plan.js`: ok
- activation plan pipe-safe JSON flush for bundled parsing: ok
- `bash tools/cross_network_domain_readiness_bundle.command --self-test`: ok
- stable HTTPS no-network readiness bundle: ok
- raw public IP no-network readiness bundle rejection: ok
- packaged dist `dist/rust-hub-20260514T122148Z`: ok
- packaged `xhubd doctor`, readiness bundle self-test, and UI compatibility gate: ok
- packaged stable HTTPS no-network bundle with packaged `bin/xhubd`: ok
- packaged access-key fallback from dist root to source repo secrets: ok
- packaged dist contains no Swift product UI files: ok
- active root converged to `rust-hub-20260514T122148Z`: ok
- X-Hub relaunched with relflowhub_node inheriting the new root: ok
- scheduler production guard and provider/model route production runtime guard: ok
- daemon ops gate after active-root convergence: ok
- process sanity: X-Hub PID 6113, relflowhub_node PID 6124, xhubd PID
  34694, no `target/debug/xhubd` or `target/release/xhubd`: ok
