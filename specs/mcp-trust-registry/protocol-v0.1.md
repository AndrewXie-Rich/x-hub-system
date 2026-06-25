# MCP Trust Registry — Protocol Specification v0.1 (Draft)

**Status:** Draft RFC, pre-submission to the MCP community
**Editor:** X-Hub-System project (reference implementation)
**Date:** 2026-06-25
**License of this document:** CC BY 4.0

---

## Abstract

The Model Context Protocol (MCP) defines how AI clients connect to tool/data servers. It does **not** define how clients should decide whether a given MCP server is trustworthy, what host resources it is permitted to touch, or how to detect when a previously-installed server silently expands its scope. This specification defines a **trust layer** that sits above MCP without modifying it: a federated, git-backed registry of signed attestations describing each MCP server's publisher identity, version hash, and declared capabilities, plus a runtime enforcement contract that gates host-resource access at a local proxy.

This document specifies version **0.1** of the protocol. The protocol is intentionally minimal; complexity is deferred to future versions only when forced by interoperability needs.

---

## 1. Status of This Document

This is a draft. It is not endorsed by the MCP working group at the time of writing. It is published to invite review, criticism, and replacement. Implementations are encouraged but must declare conformance to **v0.1** and SHOULD NOT claim compatibility with future versions.

The protocol uses RFC 2119 keywords (MUST, SHOULD, MAY, etc.).

---

## 2. Terminology

| Term | Definition |
|---|---|
| **MCP server** | A process implementing the Model Context Protocol's server side, providing tools/resources/prompts to an MCP client. |
| **MCP client** | A consumer (IDE, agent runtime) that loads and calls one or more MCP servers. |
| **Publisher** | An identity that releases versions of an MCP server. Identified by an ed25519 public key. Optionally bound to an OIDC subject (e.g., a GitHub identity) via keyless signing. |
| **Manifest** | A machine-readable declaration of an MCP server version's identity, capabilities, and signing metadata. |
| **Capability** | A scoped permission token granting access to a class of host resource (filesystem path, network host, environment variable, etc.). |
| **Attestation** | A signed statement binding a manifest to a specific artifact hash, asserting that this publisher endorses this version. |
| **Pin** | A consumer-side commitment to a specific (manifest hash, artifact hash) tuple. Subsequent versions are not auto-trusted. |
| **Trust Policy** | A consumer-side configuration mapping publishers and capabilities to allow / deny / require-grant decisions. |
| **Verifier** | A process (typically the `mcp-trust-proxy`) that enforces policy at runtime by mediating between MCP client and MCP server. |
| **Registry** | A git repository serving as a content-addressed index of attestations, mirrorable, queryable. |

---

## 3. Architecture

```
+----------------+        stdio / tcp        +------------------+
|   MCP client   | <-----------------------> |  mcp-trust-proxy |
| (Claude Code,  |                           |   (Verifier)     |
|  Cursor, ...)  |                           +---------+--------+
+----------------+                                     |
                                                       | spawn + supervise
                                                       v
                                              +------------------+
                                              |   MCP server     |
                                              | (untrusted code) |
                                              +------------------+

                Verifier resolves at startup:
                    1. Manifest for server image
                    2. Attestations for manifest hash
                    3. Local trust policy
                    4. Pinned versions (if any)
                Verifier enforces at runtime:
                    1. Capability tokens on every host syscall the server
                       makes via known MCP extensions
                    2. Capability tokens on every tool result that exfiltrates
                       host data
                    3. Revocation list checks (periodic)
```

Three roles:
- **Publishers** sign manifests and push attestations to one or more registries.
- **Registries** store attestations as a content-addressed git index, replicable.
- **Verifiers** consult registries + local policy, then enforce at runtime.

The MCP client itself MAY remain unmodified; the proxy MAY be transparent (spawned as the MCP server entrypoint, then itself spawning the real server).

---

## 4. Manifest

### 4.1 Format

A manifest is a JSON document. Field ordering is unspecified; canonicalization for hashing is defined in §4.4.

```json
{
  "schema": "mcp-trust/manifest/v0.1",
  "name": "browser-tools",
  "version": "1.4.2",
  "publisher": {
    "key_id": "ed25519:k0a7…",
    "oidc_subject": "https://github.com/jane-doe",
    "oidc_issuer": "https://token.actions.githubusercontent.com"
  },
  "artifact": {
    "type": "npm",
    "name": "@acme/browser-tools",
    "version": "1.4.2",
    "sha256": "9f3c…ab2e",
    "fetch_url": "https://registry.npmjs.org/@acme/browser-tools/-/browser-tools-1.4.2.tgz"
  },
  "mcp": {
    "transport": ["stdio"],
    "tools": ["screenshot", "navigate", "extract_text"],
    "resources": [],
    "prompts": []
  },
  "capabilities": {
    "required": [
      "fs:read:/tmp/**",
      "net:fetch:*"
    ],
    "optional": [
      "shell:exec",
      "secret:read:GITHUB_TOKEN"
    ]
  },
  "metadata": {
    "homepage": "https://github.com/acme/browser-tools",
    "source_repo": "https://github.com/acme/browser-tools",
    "license": "MIT",
    "released_at": "2026-06-12T10:14:00Z"
  }
}
```

### 4.2 Required fields

- `schema` MUST be exactly `mcp-trust/manifest/v0.1`.
- `name` MUST match `^[a-z0-9][a-z0-9-]{0,63}$`.
- `version` MUST be a semver 2.0 string.
- `publisher.key_id` MUST be `ed25519:<base32-no-padding lowercase>` of the public key.
- `artifact.sha256` MUST be the lowercase hex SHA-256 of the on-disk artifact contents (tarball, binary, or directory tarball — see §4.5).
- `mcp.transport` MUST be a non-empty subset of the MCP transports declared by MCP itself.
- `capabilities.required` and `capabilities.optional` MUST each be a JSON array of capability tokens (§5). Arrays MAY be empty.

### 4.3 Optional fields

- `publisher.oidc_subject` and `publisher.oidc_issuer` together establish keyless identity (Sigstore-style). When present, verifiers MAY require both to be valid for an attestation to be accepted.
- `metadata` is informational; verifiers MUST NOT make trust decisions from it.

### 4.4 Canonicalization for hashing

A manifest's canonical form is its JSON representation with:
- UTF-8 encoding, no BOM.
- Keys sorted lexicographically at every depth.
- No whitespace between tokens.
- Numbers in their shortest unambiguous form (no trailing zeros, no leading zeros, no `+` sign).
- Unicode strings in NFC.

The **manifest hash** is `sha256` of the canonical form, lowercase hex.

### 4.5 Artifact hashing

For npm tarballs: `sha256` of the tarball as published.
For directory artifacts (rare; only for local development): `sha256` of a deterministic tar archive of the directory tree, using `tar` with `--sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner`.
For single-file binaries: `sha256` of the file contents.

A `artifact.type` field MUST be set so verifiers know which hashing convention applies. Allowed values in v0.1: `npm`, `dir-tar`, `binary`.

---

## 5. Capability Tokens

Capability tokens are scoped strings of the form `category:action[:scope]`. v0.1 defines the following categories:

### 5.1 Filesystem

- `fs:read:<glob>` — read access to files matching glob.
- `fs:write:<glob>` — write access to files matching glob.
- `fs:list:<glob>` — directory listing.

Globs use the standard POSIX `**` semantics. A capability of `fs:read:/**` is "read all files"; verifiers SHOULD treat this as an explicit broad grant and warn.

### 5.2 Network

- `net:fetch:<host>[:<port>]` — outbound TCP/HTTPS to host. Host MAY be `*` for any.
- `net:listen:<port>` — bind a listening socket. v0.1 MAY refuse to grant this category by default.

### 5.3 Process / shell

- `shell:exec[:<program>]` — execute a subprocess. Without scope: any executable. With scope: only the named program.
- `proc:spawn[:<image>]` — spawn an OCI image. Reserved; default-deny in v0.1.

### 5.4 Secrets and environment

- `secret:read:<NAME>` — read a named secret from the host secret store.
- `secret:write:<NAME>` — write a secret.
- `env:read:<NAME>` — read an environment variable by name.

Environment access to `PATH`, `HOME`, `USER` and other widely-relied-upon variables is implicitly granted; verifiers MUST NOT require capability tokens for them. The set of implicitly-granted env vars is published at `https://mcp-trust.org/spec/v0.1/env-allowlist.json`.

### 5.5 MCP-internal

- `mcp:call:<server>.<tool>` — call another MCP server's tool. Required for any MCP server that orchestrates other MCP servers.

### 5.6 Token semantics

- Capability tokens are **least-privilege requests**. A server requesting `fs:read:/**` is requesting global read; users grant or deny.
- A server's runtime behaviour MUST NOT exceed its **granted** capabilities — the union of (required ∩ granted) and (optional ∩ granted) at install time.
- Verifiers MUST enforce on a deny-by-default basis: any access not covered by a granted capability MUST be blocked.
- Capability **expansion** between versions (i.e., a new version requires a capability the previous one did not) MUST trigger re-grant. See §8.

### 5.7 Future categories (non-normative)

Categories `gpu:*`, `usb:*`, `audio:*`, `clipboard:*` are reserved for future versions. v0.1 verifiers MAY ignore them; v0.2+ MAY define them.

---

## 6. Attestation

An attestation is the publisher's signed assertion that a manifest is authentic for a specific artifact hash.

### 6.1 Format

```json
{
  "schema": "mcp-trust/attestation/v0.1",
  "manifest_hash": "sha256:1c2f…b07a",
  "artifact_hash": "sha256:9f3c…ab2e",
  "publisher_key_id": "ed25519:k0a7…",
  "issued_at": "2026-06-12T10:14:32Z",
  "expires_at": "2027-06-12T10:14:32Z",
  "signature": "ed25519:U2lnbmF0…d2g==",
  "sigstore_bundle": null
}
```

### 6.2 Signature

The signature is over the canonical form (§4.4) of the JSON document with the `signature` and `sigstore_bundle` fields removed. The publisher's ed25519 secret key is the signing key; the public key is referenced via `publisher_key_id`.

### 6.3 Keyless signing

A keyless attestation sets `signature` to `null` and provides a Sigstore bundle in `sigstore_bundle`. The bundle MUST chain to an OIDC subject matching the manifest's `publisher.oidc_subject` and `publisher.oidc_issuer`.

Verifiers MUST accept either form. Verifiers MAY require keyless attestation under specific trust policies.

### 6.4 Expiry

`expires_at` MUST be no more than 18 months after `issued_at` for non-keyless attestations. Keyless attestations have no expiry (their trust derives from Sigstore's transparency log). Expired attestations MUST NOT be used as the sole basis for trust at install time; they MAY be honoured for already-pinned versions.

### 6.5 Co-attestation

Multiple publishers MAY attest to the same `(manifest_hash, artifact_hash)` pair. Verifiers MAY require N-of-M co-attestation under strict trust policies (e.g., "publisher's own attestation plus one independent reviewer").

---

## 7. Registry

### 7.1 Storage model

A registry is a git repository with the following structure:

```
registry-root/
├── publishers/
│   └── <key_id-prefix-2>/<key_id>/
│       ├── pubkey.json          # ed25519 public key + optional OIDC binding
│       └── revocations.json     # publisher-side recall list
├── attestations/
│   └── <manifest-hash-prefix-2>/<manifest_hash>/
│       ├── manifest.json
│       └── attestations/
│           └── <publisher_key_id>.json
├── revocations/
│   └── <date>.json              # registry-side revocation log
└── meta/
    ├── registry.json            # registry name, operator, URL
    └── version.json             # spec version supported
```

### 7.2 Content addressing

Manifests are stored under their canonical hash. Attestations under that manifest are stored by publisher key id. A single manifest may have multiple attestations from different publishers (§6.5).

### 7.3 Federation

Multiple registries MAY exist. A registry is identified by its HTTPS URL (the location of `meta/registry.json`). Verifiers maintain a list of registries they consult; each is queried in order until either a sufficient attestation set is found or all are exhausted.

Registries MAY mirror each other. A registry mirror MUST preserve content addresses; mirroring is a verbatim copy of attestations and publisher records, NOT a re-attestation.

### 7.4 Query API

Registries MUST expose at least the following HTTP endpoints (static files acceptable):

| Endpoint | Returns |
|---|---|
| `GET /meta/registry.json` | Registry metadata |
| `GET /publishers/<key_id>/pubkey.json` | Public key record |
| `GET /attestations/<manifest_hash>/manifest.json` | Manifest |
| `GET /attestations/<manifest_hash>/attestations/` | List of attestations (JSON array of publisher key ids) |
| `GET /attestations/<manifest_hash>/attestations/<key_id>.json` | A specific attestation |
| `GET /revocations/latest.json` | The latest revocation log entry |
| `GET /index/by-name/<name>.json` | All `(manifest_hash, version)` tuples for the given server name |

Registries MAY expose richer search APIs; v0.1 verifiers MUST NOT require them.

### 7.5 Trust roots of registries

Registries themselves are not trust roots. Verifiers SHOULD treat registries as untrusted CDNs: every attestation is independently signature-verified. A registry that serves a malformed or unsigned attestation MUST be ignored.

---

## 8. Pinning

A **pin** is a consumer-side commitment to a specific `(manifest_hash, artifact_hash)` tuple. Pins are stored locally:

```json
{
  "schema": "mcp-trust/pin/v0.1",
  "server_name": "browser-tools",
  "manifest_hash": "sha256:1c2f…b07a",
  "artifact_hash": "sha256:9f3c…ab2e",
  "granted_capabilities": [
    "fs:read:/tmp/**",
    "net:fetch:*"
  ],
  "pinned_at": "2026-06-13T09:00:00Z",
  "pinned_by": "andrew"
}
```

### 8.1 Pin behaviour

- A pinned server MUST run at the pinned version regardless of newer attestations in the registry.
- An attempt to launch the server at a different version MUST be rejected unless the pin is explicitly updated.
- Granted capabilities are part of the pin; capability expansion in a newer version (the new version's `required ∪ optional` ⊃ old's) MUST trigger explicit re-grant.

### 8.2 Pin lifecycle

- `mcp-trust install` creates a pin.
- `mcp-trust update <name>` re-resolves and updates the pin; re-grant is required if capabilities expanded.
- `mcp-trust unpin <name>` removes the pin.

---

## 9. Trust Policy

A trust policy is a local YAML/JSON file that configures verifier behaviour. v0.1 defines the minimum required fields:

```yaml
schema: mcp-trust/policy/v0.1

registries:
  - url: https://registry.mcp-trust.org
  - url: https://registry.internal.acme.com   # private registry

trusted_publishers:
  - key_id: ed25519:k0a7…
    name: jane@acme.com
  - oidc_subject: https://github.com/acme-org
    oidc_issuer: https://token.actions.githubusercontent.com

require_keyless: false
require_co_attestations: 0          # N-of-M; 0 means "any single attestation"

default_capability_decision:
  fs:read:    grant_if_required
  fs:write:   grant_explicit
  net:fetch:  grant_if_required
  shell:exec: grant_explicit
  secret:*:   grant_explicit
  proc:spawn: deny

on_unsigned_server: quarantine      # quarantine | block | warn
on_revoked_publisher: block         # block | warn
on_expired_attestation: warn        # warn | block

revocation_check_interval: 1h
```

### 9.1 Quarantine mode

A server in quarantine MAY run but starts with an **empty** capability set. The verifier MUST refuse all host-resource access. This allows the client to inspect the server's behaviour without granting trust.

### 9.2 Policy templates

Three reference templates SHOULD ship with verifiers:

- **personal** — `on_unsigned_server: warn`, broad `grant_if_required` for low-risk categories.
- **team** — `on_unsigned_server: quarantine`, `require_co_attestations: 1`.
- **strict** — `on_unsigned_server: block`, `require_keyless: true`, `require_co_attestations: 2`.

---

## 10. Revocation

### 10.1 Publisher-side recall

A publisher MAY recall a specific manifest hash. Recalls are stored under `publishers/<key_id>/revocations.json`:

```json
{
  "schema": "mcp-trust/recall/v0.1",
  "publisher_key_id": "ed25519:k0a7…",
  "recalls": [
    {
      "manifest_hash": "sha256:1c2f…b07a",
      "reason": "vulnerability CVE-2026-1234",
      "recalled_at": "2026-06-22T08:00:00Z",
      "signature": "ed25519:…"
    }
  ]
}
```

Each entry MUST be individually signed (signature over the entry minus its own `signature` field, canonicalized).

### 10.2 Registry-side quarantine

A registry operator MAY add an entry to `revocations/<date>.json` declaring a manifest or publisher key untrusted. Registry-side revocations are NOT cryptographic statements about the publisher; they are operator decisions, signed by the registry's own key.

Verifiers MAY honour or ignore registry-side revocations based on policy.

### 10.3 Verifier behaviour on revocation

When a verifier polls (interval per §9, default 1h) and learns a previously-pinned server has been recalled:
- The verifier MUST log the revocation event.
- The verifier MUST surface the event to the user (mechanism unspecified — CLI banner, system notification, etc.).
- The verifier MUST NOT silently un-pin; the user decides.
- The verifier MAY refuse to launch the server until acknowledgement, depending on `on_revoked_publisher` policy.

---

## 11. Runtime Enforcement

This section is the contract the verifier (e.g., `mcp-trust-proxy`) MUST satisfy.

### 11.1 Process model

The verifier spawns the MCP server as a child process. The verifier mediates stdio between the MCP client and the server. The verifier supervises the server's host-resource access via OS-level mechanisms (sandboxing, namespaces, eBPF, ptrace, or whatever the platform offers).

Acceptable enforcement mechanisms in v0.1:
- macOS: `sandbox_init(3)` profiles + path-restricted spawn.
- Linux: seccomp + namespaces + path bind-mounts (or Landlock where available).
- Windows: AppContainer + Job Objects + RestrictedAccess.

A verifier on a platform without enforceable sandboxing (or running outside one) MUST refuse to launch any server whose granted capabilities do not equal `{}` (empty set). Such a verifier MAY only support **quarantine** mode.

### 11.2 Audit log

Every capability check MUST produce an audit record. Records are append-only JSON Lines under a verifier-managed log directory:

```json
{"ts":"2026-06-22T14:23:07.123Z","server":"browser-tools","cap":"fs:read","path":"/tmp/x","decision":"allow","pin":"sha256:9f3c…"}
{"ts":"2026-06-22T14:23:09.045Z","server":"browser-tools","cap":"fs:write","path":"/tmp/y","decision":"deny","reason":"not in granted set"}
```

The audit log format is normative; downstream SIEM integrations rely on it.

### 11.3 Receipt emission

For every server invocation (an MCP client session opening one MCP server), the verifier emits a **receipt** at session end:

```json
{
  "schema": "mcp-trust/receipt/v0.1",
  "session_id": "rcpt-7a2e…",
  "server_name": "browser-tools",
  "manifest_hash": "sha256:1c2f…b07a",
  "artifact_hash": "sha256:9f3c…ab2e",
  "started_at": "2026-06-22T14:23:00Z",
  "ended_at": "2026-06-22T14:31:42Z",
  "verifier_key_id": "ed25519:v9c1…",
  "tool_calls": 47,
  "capability_denials": 1,
  "policy_hash": "sha256:e0f2…",
  "signature": "ed25519:…"
}
```

Receipts are signed by the **verifier's** key (not the publisher's). Receipts provide downstream-auditable evidence that "this client, against this policy, ran this server under this enforcement".

Receipts are interoperable with the X-Hub Hub Receipt format and MAY be the same artifact in practice.

---

## 12. Security Considerations

### 12.1 Threat model

In scope:
- **Malicious publisher** distributing a server that exfiltrates files, secrets, or makes unauthorised network calls.
- **Compromised publisher key** signing a new version that silently expands capabilities.
- **Compromised registry** serving forged attestations or hiding revocations.
- **Downgrade attack** forcing a verifier to accept an older, known-vulnerable version.
- **Side-channel exfiltration** via legitimate-looking tool outputs.

Out of scope (v0.1):
- **Verifier compromise** — if the verifier itself is compromised, all guarantees fail. Hardened verifier deployment is the operator's responsibility.
- **MCP protocol bugs** — flaws in MCP itself are out of scope; this layer assumes a correct MCP transport.
- **Steganography in tool outputs** — a server granted `net:fetch:*` can encode data however it likes. This is a granted-capability problem, not a verifier problem.

### 12.2 Specific defences

- **Forged manifest:** every manifest is content-addressed; attestations bind manifest hash to artifact hash. Forging requires breaking SHA-256 or stealing the publisher's key.
- **Compromised publisher key:** verifiers MUST honour publisher-side recalls (§10.1). Operators SHOULD configure short attestation expiry windows when keyless signing is unavailable.
- **Forged registry response:** registries are untrusted (§7.5); attestations are signature-verified locally.
- **Hidden revocations:** verifiers MUST consult publisher-side recall lists at every launch, not only registry-side revocations. Recall lists are themselves signed.
- **Downgrade:** pins (§8) prevent silent downgrades. A user wanting to downgrade MUST do so explicitly via `mcp-trust install --version`.

### 12.3 Capability bypass via MCP itself

A malicious server granted `mcp:call:other-server.tool` MAY use the orchestration capability to exfiltrate through another server's broader capabilities. Verifiers SHOULD treat `mcp:call:*` as a capability-amplifying token and recommend `grant_explicit` for it under all default policies.

### 12.4 Time-of-check / time-of-use

Capability checks MUST be enforced at every access, not only at server startup. A server that legitimately reads `/tmp/a` and then attempts to read `/tmp/../etc/passwd` MUST be blocked at the second access via path resolution at enforcement time.

---

## 13. Relationship to MCP

This specification does **not** modify the Model Context Protocol. Specifically:

- It does not change MCP message formats.
- It does not require MCP servers to be aware of the trust layer.
- It does not require MCP clients to be aware of the trust layer.
- The proxy MAY be transparently inserted into the spawn path.

A trust-aware MCP client MAY use registry information (capability declarations, attestation status) to render better UX (e.g., showing "this server is from a trusted publisher"). Such usage is optional and non-normative in v0.1.

---

## 14. Relationship to Sigstore, in-toto, SLSA

- **Sigstore** is the recommended (not required) backbone for keyless publisher identity (§6.3). The signing primitive is otherwise ed25519, allowing offline / air-gapped publishers.
- **in-toto** attestation formats are not used in v0.1; they may be adopted in a future version if community demand emerges.
- **SLSA** build-provenance attestations are orthogonal; an attestation in this protocol MAY reference a SLSA provenance under `metadata.slsa_provenance` (non-normative in v0.1).

---

## 15. Conformance

An implementation conforms to v0.1 if:

1. It can produce manifests matching §4 (`mcp-trust-publish`).
2. It can produce attestations matching §6 (`mcp-trust-sign`).
3. It can serve a registry matching §7 (or rely on a third-party registry).
4. It can verify attestations, apply policy, pin, and enforce at runtime per §§8–11 (`mcp-trust-proxy`).

A **verifier-only** implementation (no publishing) is permitted and MUST NOT claim publisher conformance.

---

## 16. Open Questions

Open issues to resolve before declaring v0.1 stable:

1. **Capability granularity for `net:fetch`** — should it allow path prefixes (`net:fetch:api.github.com/repos/**`)? Pro: tighter scope. Con: TLS-encrypted; path enforcement requires MITM.
2. **Capability composition** — should there be a way to express "the union of these other capabilities" for reusable bundles?
3. **Mobile / browser-extension MCP clients** — verifier deployment assumes a host process can spawn and sandbox child processes. What is the right architecture for in-browser MCP clients?
4. **Cross-registry trust delegation** — should a registry be able to declare "I trust these other registries' attestations transitively"?
5. **Publisher key rotation** — current draft has no formal rotation ceremony. Should there be?
6. **Telemetry of verifier denials** — should there be a standard channel for reporting capability denials back to publishers (opt-in)?

Feedback on these is the primary purpose of the v0.1 → v0.2 review cycle.

---

## 17. Appendix A: JSON Schemas

The following JSON schemas are normative and live at:

- `https://mcp-trust.org/spec/v0.1/manifest.schema.json`
- `https://mcp-trust.org/spec/v0.1/attestation.schema.json`
- `https://mcp-trust.org/spec/v0.1/policy.schema.json`
- `https://mcp-trust.org/spec/v0.1/pin.schema.json`
- `https://mcp-trust.org/spec/v0.1/receipt.schema.json`
- `https://mcp-trust.org/spec/v0.1/recall.schema.json`
- `https://mcp-trust.org/spec/v0.1/env-allowlist.json`

Reference copies live in this repository under `schemas/`.

---

## 18. Appendix B: Reference CLI

A reference implementation ships these CLIs:

```
mcp-trust publish   <path>           # build manifest, sign, push to registry
mcp-trust sign      <manifest>       # sign a manifest (publisher operation)
mcp-trust install   <ref>            # resolve, pin, grant capabilities
mcp-trust update    <name>           # re-resolve, re-grant if expanded
mcp-trust unpin     <name>           # remove pin
mcp-trust audit                      # scan installed servers, report status
mcp-trust verify    <ref>            # offline verification of a manifest
mcp-trust policy    show|set|template   # manage trust policy
mcp-trust-proxy     <server-spawn-cmd>  # the runtime enforcement proxy
```

Wire formats and behaviour follow this specification; the CLI surface itself is non-normative.

---

## 19. Appendix C: Minimal verifier flow

Pseudocode for the resolution / enforcement loop a conformant verifier follows:

```
on session_start(server_ref):
    1. Resolve server_ref to (name, version) or to manifest_hash directly.
    2. Look up pin for name; if pinned, use pinned manifest_hash.
    3. Else, query registries in trust policy order:
         a. Fetch index/by-name/<name>.json
         b. Fetch attestations/<manifest_hash>/...
         c. Verify each attestation's signature against publisher key
         d. Apply trust policy: keyless? co-attestations? expiry?
         e. Accept first manifest_hash meeting policy.
    4. Check publisher recall list. If recalled, refuse (per policy).
    5. Check registry-side revocation. If revoked, refuse (per policy).
    6. Diff capabilities (required ∪ optional) vs previously granted.
       If expanded, require user re-grant. If user declines, refuse.
    7. Fetch artifact, verify artifact_hash matches manifest.
    8. Spawn server in sandbox configured with granted capabilities.
    9. Mediate MCP traffic; enforce capabilities on every host access.
   10. On session end: emit signed receipt.
```

---

## 20. Change Log

- **v0.1 (2026-06-25)** — initial draft.

---

## 21. Acknowledgements

This spec stands on the shoulders of:
- The MCP working group (protocol definition).
- Sigstore / in-toto / SLSA (signing and attestation patterns).
- npm audit, Cargo crates.io index, Go module proxy (federation and content addressing patterns).
- The X-Hub-System project (reference governance design that motivated this draft).
