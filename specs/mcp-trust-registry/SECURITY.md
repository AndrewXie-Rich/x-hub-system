# Security Policy

This repository is a draft security specification. Do not rely on the v0.1
draft, schemas, examples, or placeholder signatures for production enforcement.

## Reporting a vulnerability

If you find a vulnerability in the draft design, examples, schemas, or reference
tooling, prefer a private report when the issue could help an attacker bypass
verification or capability enforcement.

Use GitHub private vulnerability reporting if it is available for the public
`mcp-trust-registry` repository. If private reporting is not available, open a
minimal public issue that says you have a security report and asks for a private
contact channel. Do not include exploit details in the public issue.

For non-sensitive design concerns, open a normal issue and label it `security`
or `threat-model`.

## Scope

In scope for this draft:

- Schema ambiguity that lets a verifier accept malformed trust artifacts.
- Capability-token grammar gaps that create privilege escalation.
- Replay, downgrade, revocation, or confused-deputy cases in the protocol.
- Example payloads that imply unsafe defaults.

Out of scope:

- Production incidents in unrelated MCP servers.
- Vulnerabilities in placeholder signatures. The examples are intentionally not
  cryptographically valid.
- Bugs in code that has not been published as part of this repository.
