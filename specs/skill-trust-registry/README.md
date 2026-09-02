# skill-trust-registry

<p>
  <img src="https://img.shields.io/badge/spec-v0.1%20draft-yellow.svg" alt="Spec v0.1 draft" />
  <img src="https://img.shields.io/badge/status-draft-orange.svg" alt="Draft" />
  <img src="https://img.shields.io/badge/license-MIT%20%2F%20CC--BY--4.0-blue.svg" alt="License" />
</p>

> **A trust layer for AI agent tool servers.** Sigstore-style attestations + capability tokens + a local enforcement proxy. So a tool server can't silently start reading your secrets between point releases. Compatible with MCP today; A2A / OpenAI tools / custom RPC via sibling protocol bindings in future versions.

[Specification (v0.1 draft)](protocol-v0.1.md) · [60-second demo](demo-60s.md) · [Reference proxy](proxy/README.md) · [Examples](examples/README.md) · 中文 (TBD)

## What you see

```
$ skill-trust install github.com/acme/browser-tools

publisher    : jane@acme.com  (verified via GitHub OIDC, 2026-06-12)
version      : 1.4.2  sha256:9f3c…ab2e
protocol     : MCP (stdio)
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

Later, when a silently-added capability or a revoked publisher key shows up, the proxy blocks the call and records a signed receipt — **before** the tool server can touch the filesystem, the network, or your secrets.

## Why this exists

Tool protocols — MCP, A2A, OpenAI tool calling, custom RPC — standardize **how** AI clients talk to tool servers. They leave **who you trust** as a vacuum. Today, anyone can publish a tool server; clients load it with full access to your agent context — files, secrets, codebase, network. The trust signal between `install` and "this thing now runs inside your agent's tool-calling loop" is, in practice, absent.

This is the same shape of supply-chain risk that took npm a decade to address with Sigstore-style provenance. Agent tool ecosystems don't have a decade. The blast radius is also larger: tool servers run *inside* agent context with read/write access to in-flight prompts, memory, and tool outputs.

**skill-trust-registry adds three things, without modifying the underlying tool protocol:**

1. **Signed attestations** — every tool server version is content-addressed and signed by its publisher. Federated, git-backed registry. No central trust authority.
2. **Capability tokens** — manifests declare what host resources a server needs (`fs:read:/tmp/**`, `net:fetch:api.github.com`, `shell:exec`). Users grant explicitly; defaults are deny.
3. **Runtime enforcement** — a local proxy mediates between tool clients (Claude Code, Cursor, Cline, …) and tool servers, blocking out-of-scope access and emitting signed receipts.

## Install (preview)

> ⚠️ v0.1 is a draft. APIs may break. Not for production.

Reference proxy (Rust, no OS-level sandboxing yet — see [`proxy/README.md`](proxy/README.md) for v0.1.1 deferred list):

```bash
cargo install --git https://github.com/AndrewXie-Rich/skill-trust-registry skill-trust-proxy
skill-trust-proxy verify --example
```

Wrap your tool server invocations (planned for v0.1.1 once OS sandbox enforcement lands):

```bash
# Before:  claude mcp add ./browser-tools.js
# After:   claude mcp add "skill-trust-proxy run ./browser-tools.js"
```

## How it works

A **publisher** signs a manifest declaring what their tool server needs. The manifest goes into a **registry** (a git repo of signed attestations). When you install, the **proxy** verifies the signature, applies your **trust policy**, and asks you to grant the capabilities the manifest requested. From then on, every tool call is mediated: any out-of-scope filesystem read, network fetch, or process spawn is blocked at the proxy, not at the tool server's discretion.

The pieces that aren't in any underlying tool protocol:

- **Pin.** Your client commits to a specific (manifest hash, artifact hash). Silent downgrades and upgrades are impossible.
- **Capability expansion guard.** If a new version asks for capabilities the old one didn't, you re-grant explicitly. No silent privilege creep.
- **Two-way revocation.** Publishers can recall versions; registries can quarantine bad actors. Both are signed and verified locally.

Full data model and wire format: [`protocol-v0.1.md`](protocol-v0.1.md).

## Status

| Component | State |
|---|---|
| Specification v0.1 | Draft |
| JSON Schemas + examples | CI validated |
| Example-chain verifier | Available at `scripts/verify_examples.js` |
| Reference proxy (Rust) — keygen, sign, verify, check, receipts | ✓ shipped at [`proxy/`](proxy/) (v0.1.0, 19/19 tests, MIT) |
| `skill-trust install` / wrap-runtime sandbox enforcement | Deferred to v0.1.1 |
| Reference registry | Bootstrapping |
| Seed attestations (top tool servers across protocols) | In progress |
| Sibling protocol bindings (OpenAI tools, A2A) in manifest schema | Planned for v0.2 |
| Sigstore keyless signing | Planned for v0.2 |

Schemas validate with the root repo script and the standalone repo script. Example cross-field consistency validates with `node specs/skill-trust-registry/scripts/verify_examples.js --example`.

The reference proxy under [`proxy/`](proxy/) implements the cryptographic + capability-decision half of v0.1 today (ed25519 sign/verify over JCS-canonical attestation bytes, ALLOW/PROMPT/DENY decisions per §5.6, schema-conformant signed receipts). The runtime sandbox half (macOS sandbox-exec, Linux Landlock/seccomp, Windows AppContainer) is deferred to v0.1.1.

X-Hub-System integrates this same protocol as its skills trust subsystem.

## Supported tool protocols

v0.1 ships with MCP protocol bindings in the manifest schema (the `mcp` block in §4 of the spec). The trust primitives — manifest, attestation, registry, capability tokens, pin, policy, recall, receipt — are protocol-independent. v0.2+ will add sibling binding blocks for OpenAI tool calling, A2A endpoints, and custom RPC bridges. See spec §1.5 for the compatibility envelope.

skill-trust-registry does **not** modify the Model Context Protocol or any other underlying tool protocol. It is a strict superset over each: clients and servers that know nothing about the trust layer continue to work; clients that integrate the proxy gain enforcement; servers that sign manifests gain provenance.

## Contributing

This is a draft. The most valuable contribution right now is **review of the spec**, especially:

- The capability token grammar (§5 of the spec) — is the granularity right?
- The federation model (§7) — does it survive realistic adversarial registries?
- The threat model (§12) — what did we miss?
- The compatibility envelope (§1.5) — what does a non-MCP protocol binding actually need to add?

Open issues at <https://github.com/AndrewXie-Rich/skill-trust-registry/issues>.

## License

Specification: **CC BY 4.0**. Reference implementations: **MIT**.

Contributions to this project are accepted under the same licences. By contributing, you agree to the Developer Certificate of Origin.
