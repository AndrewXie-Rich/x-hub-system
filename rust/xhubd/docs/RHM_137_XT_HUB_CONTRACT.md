# RHM-137 XT Hub Contract

Date: 2026-05-15

## Scope

Make Rust Hub expose a single machine-readable capability contract for
X-Terminal and for AI agents that update X-Terminal.

The contract prevents XT from reimplementing Hub authority locally when adding
memory, skills, model-route, provider-route, grant, audit, or remote-entry
behavior.

## Interfaces

- `xhubd xt contract`
- `GET /xt/hub-contract`
- compatibility aliases:
  - `GET /xt/contract`
  - `GET /contract/xt`

The response schema is `xhub.rust_hub.xt_contract.v1`.

## Product Boundary

XT is a paired deep client. Hub remains the source of truth for:

- durable memory and memory write authority;
- model and provider route decisions;
- skill catalog, pin, grant, preflight, revocation, and audit;
- high-risk grants and Supervisor policy gates;
- append-only audit and evidence references;
- remote-entry candidates for domain, tunnel, and no-domain private-network
  users.

XT may cache projections for UI speed, but it must fail closed when Hub truth is
missing, stale, revoked, or inconsistent.

## Skills Boundary

The contract intentionally uses a lease model:

- Hub owns catalog, pin, grant, preflight, revocation, and audit.
- XT or a sandbox runner executes skill code only after a fresh
  `/skills/preflight` allow decision.
- Third-party skill code must not run inside the Hub trust root by default.
- Skill execution must bind scope, skill id, requested capabilities, package
  hash/pin, and revocation epoch.

Missing pin, missing grant, stale lease, hash drift, scope drift, or revocation
drift must fail closed.

## Verification

- `cargo test -p xhubd xt_contract`: ok
- `bash tools/xt_hub_contract_smoke.command`: ok
