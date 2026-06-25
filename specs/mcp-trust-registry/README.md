# mcp-trust-registry

<p>
  <img src="https://img.shields.io/badge/spec-v0.1%20draft-yellow.svg" alt="Spec v0.1 draft" />
  <img src="https://img.shields.io/badge/status-pre--MCP--RFC-orange.svg" alt="Pre RFC" />
  <img src="https://img.shields.io/badge/license-Apache--2.0-blue.svg" alt="Apache 2.0" />
</p>

> **A trust layer above MCP.** Sigstore-style attestations + capability tokens + a local enforcement proxy. So your AI agent can't `rm -rf` because an MCP server "just needed shell access".

[Specification (v0.1 draft)](spec/protocol-v0.1.md) · [60-second demo](demo-60s.md) · [中文](README_zh.md)

## What you see

```
$ mcp-trust install github.com/acme/browser-tools

publisher    : jane@acme.com  (verified via GitHub OIDC, 2026-06-12)
version      : 1.4.2  sha256:9f3c…ab2e
capabilities : ✓ fs:read:/tmp/**          ✓ net:fetch:*
               ⚠ shell:exec                ← needs grant
               ⚠ secret:read:GITHUB_TOKEN  ← needs grant
last audit   : 2026-05-20 (community, 3 reviewers)
decision     : 2 capabilities need explicit grant

grant shell:exec? [y/N] N
grant secret:read:GITHUB_TOKEN? [y/N] N

✓ installed with reduced capabilities (2 of 4 allowed)
  pinned at sha256:9f3c…ab2e — capability expansion will require re-grant
```

Later, when a silently-added capability or a revoked publisher key shows up, the proxy blocks the call and records a signed receipt — **before** the MCP server can touch the filesystem, the network, or your secrets.

## Why this exists

The Model Context Protocol standardized **how** AI clients talk to tool servers. It left **who you trust** as a vacuum. Today, anyone can publish an MCP server; clients load it with full access to your agent context — files, secrets, codebase, network.

This is the same shape of supply-chain risk that took npm a decade to address. MCP won't wait that long. The blast radius is also larger: MCP servers run inside your agent's tool-calling loop, not in a browser tab.

**mcp-trust-registry adds three things, without modifying MCP:**

1. **Signed attestations** — every MCP server version is content-addressed and signed by its publisher. Federated, git-backed registry. No central trust authority.
2. **Capability tokens** — manifests declare what host resources a server needs (`fs:read:/tmp/**`, `net:fetch:api.github.com`, `shell:exec`). Users grant explicitly; defaults are deny.
3. **Runtime enforcement** — a local proxy mediates between MCP clients (Claude Code, Cursor, Cline, …) and MCP servers, blocking out-of-scope access and emitting signed receipts.

## Install (preview)

> ⚠️ v0.1 is a draft. APIs may break. Not for production.

```bash
brew install mcp-trust            # macOS preview tap
cargo install mcp-trust-cli       # any platform with Rust
```

Wrap your MCP server invocations:

```bash
# Before:  claude mcp add ./browser-tools.js
# After:   claude mcp add "mcp-trust-proxy ./browser-tools.js"
```

Or use the `mcp-trust install` flow to fetch + pin + configure your client automatically.

## How it works (90 seconds)

A **publisher** signs a manifest declaring what their MCP server needs. The manifest goes into a **registry** (a git repo of signed attestations). When you install, the **proxy** verifies the signature, applies your **trust policy**, and asks you to grant the capabilities the manifest requested. From then on, every tool call is mediated: any out-of-scope filesystem read, network fetch, or process spawn is **blocked at the proxy**, not at the MCP server's discretion.

Three things you didn't have before:

- **Pin** — your client commits to a specific (manifest hash, artifact hash). Silent downgrades and upgrades are impossible.
- **Capability expansion guard** — if a new version asks for capabilities the old one didn't, you must explicitly re-grant. No silent privilege creep.
- **Two-way revocation** — publishers can recall versions; registries can quarantine bad actors; both are signed and verified locally.

Full data model and wire format: [`spec/protocol-v0.1.md`](spec/protocol-v0.1.md).

## Status

| Component | State |
|---|---|
| Specification v0.1 | Draft, pre-RFC |
| `mcp-trust-cli` (Rust) | Skeleton |
| `mcp-trust-proxy` (Rust) | Skeleton |
| Reference registry | Bootstrapping |
| Seed attestations (top 20 MCP servers) | In progress |
| Sigstore keyless signing | Planned for v0.2 |

Schemas validated in CI: see [`scripts/check_mcp_trust_schemas.sh`](../../scripts/check_mcp_trust_schemas.sh).

A reference deployment of the proxy ships inside [X-Hub-System](https://github.com/AndrewXie-Rich/x-hub-system) as its skills trust subsystem.

## Relationship to MCP

mcp-trust-registry does **not** modify the Model Context Protocol. It is a strict superset: MCP clients and servers that know nothing about the trust layer continue to work; clients that integrate the proxy gain enforcement; servers that sign manifests gain provenance.

This spec exists because we believe MCP itself should not absorb every concern. Trust, capability, and policy are a separate layer with a different deployment story (per-host, per-org) than MCP (per-connection).

## Contributing

We are pre-RFC. The most valuable contribution right now is **review of the spec**, especially:

- The capability token grammar (§5 of the spec) — is the granularity right?
- The federation model (§7) — does it survive realistic adversarial registries?
- The threat model (§12) — what did we miss?

Open issues at <https://github.com/mcp-trust/mcp-trust-registry/issues> (placeholder — repo not yet public). Until the repo is live, comment on the X-Hub-System repo's discussions.

## License

Specification: **CC BY 4.0**. Reference implementations: **Apache 2.0**.

Contributions to this project are accepted under the same licences. By contributing, you agree to the Developer Certificate of Origin.
