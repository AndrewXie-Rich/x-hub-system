# Governed Skills

<p class="lead">
You install one MCP server today. Next week the maintainer ships "a small update" that quietly adds <code>shell:exec</code> to its required capabilities. Your IDE auto-upgrades. By the time you notice, your <code>GITHUB_TOKEN</code> is on an attacker server. X-Hub's skill subsystem, along with the <a href="https://github.com/AndrewXie-Rich/mcp-trust-registry">mcp-trust-registry</a> spec extracted from it, is built to make that story impossible.
</p>

<div class="preview-note">
  <strong>This subsystem is the reference implementation for the <a href="https://github.com/AndrewXie-Rich/mcp-trust-registry">mcp-trust-registry</a> spec.</strong>
  The registry, attestations, capability tokens, and runtime enforcement are independent of X-Hub. You can take the spec without taking the implementation. This page describes what X-Hub does; the spec describes the interoperable shape.
</div>

## The Skill Boundary

Many agent stacks expose tools directly and let the model improvise everything else.

X-Hub moves one level up:

- skills can carry structured inputs and outputs
- execution mapping can be stabilized
- risk boundaries can be attached
- routing and review can happen before side effects

## The Dispatch Path

The intended runtime path is:

`skill intent -> governed dispatch -> tool execution`

That matters because it creates room for:

- policy checks
- grants
- deny codes
- audit references
- evidence references
- fail-closed rejection before execution

## Why This Is Stronger Than Loose Plugins

| Loose plugin model | Governed skill model |
| --- | --- |
| install often implies trust | trust can be separated from local enablement |
| tool usage dissolves into chat logs | skill activity can keep structured records |
| retry means "ask the model again" | retry can replay governed dispatch with the same guarded arguments |
| local client often becomes the final authority | the Hub can pin, audit, revoke, and route the package |

## Trust Chain Direction (and how it maps to the spec)

The current direction includes:

| X-Hub component | mcp-trust-registry v0.1 spec section |
| --- | --- |
| Official skill catalog + governed import flow | §3 Registry — federated, signed, content-addressed |
| Publisher trust roots (ed25519 + optional Sigstore keyless) | §2 Attestation — signed binding of manifest hash to artifact hash |
| Package manifest (capability declarations) | §1 Manifest — `fs:read:/tmp/**`, `net:fetch:host`, `shell:exec`, etc. |
| Package pinning (`(manifest_hash, artifact_hash)`) | §4 Pin — pinned by the local trust policy |
| Compatibility checks + doctor surfaces | §4 Runtime contract — capability enforcement |
| Grants, deny codes, revocation, audit | §6 Recall + §5 Receipts |

The Hub becomes the place where skill trust is held without turning the Hub into a place where arbitrary third-party code automatically becomes the trust anchor.

## Why This Matters For Long-Running Systems

If you want AI systems to operate across longer projects and higher-risk surfaces, skill quality has to be durable.

That is why governed skills matter:

- they are more reusable than one-off prompt plans
- they are more observable than raw tool calls
- they are easier to audit and recover
- they attach better to memory, review, and project continuity

That does not make the skill runtime the memory authority: the user still chooses which AI executes memory jobs in X-Hub, `Memory-Core` remains the governed rule layer, and durable memory writes still terminate through `Writer + Gate`.

The result is not just more capability.
It is a more governable execution substrate, and the substrate's wire format is an open spec rather than X-Hub-specific glue.
