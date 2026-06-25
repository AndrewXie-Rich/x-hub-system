# RFC: A trust layer above MCP — federated attestation + capability tokens

> **Target venue:** GitHub Discussion on `modelcontextprotocol/specification`.
> **Tone:** community proposal, pre-spec. Not a competitor announcement.
> **Length target:** ~150 lines. Anything longer and it stops being read in one sitting.
> **Companion artifacts:** [Full spec v0.1 draft](spec/protocol-v0.1.md) (530 lines) · [README](README.md) · [60-second demo script](demo-60s.md)

---

## TL;DR

MCP standardized the protocol for connecting models to tool/data servers. It does not standardize how clients decide **which servers to trust**, what host resources each server is **permitted to touch**, or how to detect when a previously-installed server **silently expands its scope**.

We've drafted a v0.1 spec for a trust layer that sits *above* MCP, without modifying it: federated, signed manifests with capability tokens, plus a local proxy that enforces capability at runtime. Full draft: [protocol-v0.1.md](https://github.com/AndrewXie-Rich/x-hub-system/blob/main/specs/mcp-trust-registry/protocol-v0.1.md).

**What we want from this thread:**

1. Is there appetite in this community for a separate trust spec, or should this fold into the official MCP registry effort?
2. Specific feedback on three places we're least sure about (listed below).
3. Maintainers of widely-used MCP servers willing to be the first 3–5 pilot publishers.

---

## Why we think there is a gap

By mid-2026, MCP is mature enough that publishing a server is roughly an `npm publish` away. Clients (Claude Code, Cursor, Cline, Continue, custom agents) load these servers with whatever access the host process has — files, secrets, codebase, network, subprocess spawn. The trust signal between "I `mcp install`'d this" and "this thing runs inside my agent's tool-calling loop" is, today, vibes.

This is the same shape of supply-chain risk that took npm a decade to address with Sigstore-style provenance. We don't think MCP has a decade — the blast radius is larger (MCP servers run *inside* agent context, with read/write access to in-flight prompts, memory, and tool outputs), and the regulatory clock is faster (EU AI Act fully active, ISO 42001 adoption in enterprises).

The official MCP registry exists and does important work (discoverability, official curation). It is **not** the same shape as what we're proposing: a federated, signature-rooted trust spec that any registry implementation can satisfy. The two layers are complementary; this RFC is explicit about not replacing the official registry.

---

## What we're proposing

Three data primitives + one runtime contract:

### 1. Manifest

A JSON document, content-addressed by canonical SHA-256, declaring:

- Publisher identity (ed25519 key, optionally bound to OIDC subject — Sigstore keyless).
- The MCP server's artifact (npm package, binary, tar) by SHA-256.
- A list of **capability tokens** the server requires + optionally requests.
- Standard MCP fields (transport, tools, resources).

Capability tokens are scoped strings: `fs:read:/tmp/**`, `net:fetch:api.github.com`, `shell:exec`, `secret:read:GITHUB_TOKEN`, `mcp:call:other-server.tool`. We deliberately chose Android/iOS-style scoped strings over capability-based-security formalism. Lower implementation cost, higher chance of adoption.

### 2. Attestation

A signed statement binding a manifest hash to an artifact hash. Multiple parties can co-attest the same (manifest, artifact) tuple. Verifiers can require N-of-M co-attestation under strict trust policies. Signatures are ed25519 with optional Sigstore keyless.

### 3. Registry

A federated, git-backed content-addressed store of attestations. No central trust root. Verifiers treat registries as untrusted CDNs and verify signatures locally. Any number of registries can exist; clients consult them in trust-policy order. Mirroring is verbatim copy, not re-attestation.

### 4. Runtime enforcement contract (the proxy)

A local proxy mediates between an MCP client and the MCP server it spawned. The proxy:

- Resolves manifest + attestations on session start.
- Applies the user's trust policy (which publishers, which capabilities, what to do on revocation).
- Enforces capability tokens at every host-resource access using OS-level sandboxing (macOS sandbox profiles, Linux Landlock / seccomp, Windows AppContainer).
- Emits a signed receipt at session end.

**Critically, MCP itself is unmodified.** A trust-unaware client still loads the proxy transparently. A trust-unaware server still runs. Adoption is a per-host decision, not a protocol negotiation.

---

## What we are explicitly NOT proposing

We've been deliberate about scope:

- **No changes to MCP message formats.** The trust layer lives entirely outside the MCP wire protocol.
- **No central registry, no commercial registry, no paid tier.** v0.1 makes a paid registry mechanically impossible (signatures are verified locally; the registry is just a CDN).
- **No replacement for the official MCP registry.** The official registry is a curated directory; this is an attestation protocol. They compose.
- **No new identity system.** Publisher identity is ed25519 + optional Sigstore. No new account system, no new account directory.
- **No browser-only enforcement story (yet).** In v0.1, enforcement requires a host process that can sandbox a child process. Browser/web-extension MCP clients are a known gap — see open questions.

---

## Where we're least sure (and want pushback)

These are the three places where we want your read before we go further:

### A. Capability token granularity for `net:fetch`

Current spec: host-level (`net:fetch:api.github.com`). Reasoning: deeper than host (e.g., URL-path prefix) requires MITM-ing TLS, which we consider unsafe for an open-source tool to default to. But host-level lets a granted-but-malicious server exfiltrate to any path on a permitted host.

Is host-level the right floor, or should v0.1 also define a normative path-prefix mode that requires opt-in MITM via user-installed CA?

### B. Federation vs. official-registry-only

Current spec: anyone can run a registry; verifiers consult a list. This is great for offline deployments and antitrust, costly for ecosystem cohesion (will every org have its own registry of slightly-stale attestations?).

Is the right v0.1 to ship federation, or to ship single-registry-with-mirroring (similar to Go's module proxy) and add federation in v0.2 once there's evidence of demand?

### C. The role of this spec relative to the official MCP registry

Most charitable reading: this spec is what a future "MCP server provenance" extension to the official registry would look like, and we're prototyping it in the open so the working group can fork / absorb / reject it on its merits. Least charitable reading: this is an end-run around the official registry.

Genuinely curious which reading lands with you. If the working group prefers the trust-layer concerns to land *inside* the official registry effort, we'll redirect — we care about the layer existing, not about who ships it.

Other open issues (full list in spec §16): publisher key rotation, in-toto / SLSA composition, telemetry of capability denials, capability composition syntax.

---

## What "v0.1 ships" looks like

If this RFC gets a "go ahead and develop further" signal:

- **Weeks 1–2:** finalize spec, write the 6 JSON schemas, publish under `mcp-trust-registry/spec/`.
- **Weeks 3–4:** reference `mcp-trust-proxy` (Rust) that wraps any MCP server with capability enforcement on macOS + Linux.
- **Weeks 5–6:** seed attestations for the top 20 most-installed MCP servers. (We're prepared to publish community attestations even where original publishers don't sign — clearly labelled as third-party — to bootstrap.)
- **Week 7:** open the RFC against the spec repo for v0.1 → v0.2.

If this RFC gets a "fold into the official registry" signal, we'll bring the data model into that effort instead and stop maintaining a separate spec.

---

## What we're asking from this thread

In rough order of value:

1. **Push back on the three "least sure" sections (A, B, C).** Strong opinions welcome.
2. **MCP server maintainers** of widely-installed servers (`browser-tools`, `git`, `sqlite`, `fs`, `puppeteer`, `slack`, etc.) — would you be willing to be a pilot publisher? It costs you ~30 minutes to set up an ed25519 key and run `mcp-trust sign`. We'll handle the registry side.
3. **Pointers to prior work we missed.** in-toto and SLSA are referenced in the spec; if there's other prior art for capability declarations in plugin ecosystems, we want to know before we re-invent it.
4. **Pointers to concrete recent incidents** — has anyone shipped or near-shipped a malicious MCP server in the wild? Public incidents make the gap arguable; we'd rather cite than speculate.
5. **Yes/no signals on the federation question.** Even a thumbs vote would help us decide where to spend the next two weeks.

---

## About us

The reference implementation lives inside [X-Hub-System](https://github.com/AndrewXie-Rich/x-hub-system) (a self-hosted AI agent governance plane) as its skills trust subsystem. We extracted the spec because the underlying primitive — attest, capability-scope, enforce, revoke — is independently useful to the MCP ecosystem regardless of whether anyone uses X-Hub.

We are a small project (solo maintainer + small reviewer pool). We mention this because it directly bounds what we can do alone: write the spec, ship a reference Rust implementation on macOS and Linux, seed initial attestations. We cannot run a global trust registry as a service. The federated design isn't only philosophical; it's also what one person can realistically maintain.

That bound is exactly why we're posting this here: if the design only makes sense with a working group behind it, we'd rather know now than after a year of solo work.

---

## TL;DR (again, because long threads need it twice)

- We drafted a spec for a trust layer above MCP. ([Full v0.1 draft.](https://github.com/AndrewXie-Rich/x-hub-system/blob/main/specs/mcp-trust-registry/protocol-v0.1.md))
- It doesn't modify MCP. It uses federated signed attestations + capability tokens + a local proxy.
- We want your pushback on three specific decisions (capability granularity, federation, relationship to the official registry) and pilot publishers from the maintainer community.
- If this should fold into another effort, please say so — we care about the layer, not the badge.

Thanks for reading. Comments on this thread, suggestions on the spec PR, and DMs all welcome.
