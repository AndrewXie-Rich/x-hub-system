# Security and Privacy

XHubSystem is designed around fail-closed trust boundaries.

## Core Rules

- Secrets must not be sent to remote models by default.
- Side-effect actions require grant and policy checks.
- First pair requires same-LAN trust establishment.
- Hub owner approval cannot be bypassed.
- High-risk skills require signed, audited, compatible packages.
- Runtime actions must produce evidence.
- Kill-switch and revocation paths must remain available.

## Secret Handling

Secrets include:

- API keys
- OAuth tokens
- refresh tokens
- account auth material
- local credentials
- provider key files
- secret-filled browser fields

Secrets should be:

- redacted in logs
- excluded from route evidence
- stored in Keychain or encrypted storage where applicable
- never embedded in public reports
- never exposed through skill manifests

## Pairing Security

Pairing is not just "connect to a port."

The first pair requires:

- same LAN
- invite/preauth checks
- replay defense
- Hub owner local approval
- trusted connection material

Remote reconnect can be smoother only after trust is established.

## Skill Security

Skill security is layered:

- package manifest compatibility
- ABI contract
- trusted publisher
- signing chain
- vetter gate
- catalog lifecycle
- pin/grant preflight
- runtime surface policy
- audit trail

Rust skill policy currently does not execute third-party code. That boundary is intentional.

## Capability Security

Capability is not a raw tool allowlist.

The system evaluates:

- capability family
- capability profile
- project capability bundle
- approval floor
- grant floor
- runtime surface
- preflight
- runtime deny
- doctor evidence

## Audit and Evidence

Important actions should leave machine-readable evidence:

- route decision
- grant decision
- skill preflight
- model fallback
- quota blocker
- scheduler lease
- doctor failure
- recovery action

The goal is not just to block unsafe actions. The goal is to answer why a decision was made.
