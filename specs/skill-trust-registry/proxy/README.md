# skill-trust-proxy

Reference Rust implementation of the [Skill Trust Registry v0.1 protocol](../protocol-v0.1.md). v0.1 reference scope: cryptographic primitives + capability decision logic. OS-level sandbox enforcement (macOS sandbox profiles, Linux Landlock/seccomp, Windows AppContainer) is deliberately deferred — see below.

The protocol mechanics are protocol-agnostic; v0.1 manifest examples use MCP servers, but the proxy itself imposes no MCP-specific assumptions. Other tool protocols (OpenAI tool calling, A2A, custom RPC) are forward-compatible via spec §1.5.

## Install

```
cargo install --git https://github.com/AndrewXie-Rich/skill-trust-registry skill-trust-proxy
```

Or from a local clone:

```
cd proxy && cargo install --path .
```

## Try it

```
# 1. Verify the bundled example end-to-end (signed manifest + attestation).
skill-trust-proxy verify --example

# 2. Same, also writing a signed session receipt.
skill-trust-proxy verify --example --receipt-out receipt.json

# 3. Resolve a capability request against the example manifest.
skill-trust-proxy check --manifest examples/manifest.json --capability "fs:read:/tmp/screenshots/a.png"   # ALLOW
skill-trust-proxy check --manifest examples/manifest.json --capability "shell:exec"                       # PROMPT (declared optional)
skill-trust-proxy check --manifest examples/manifest.json --capability "fs:read:/etc/passwd"              # DENY  (not declared)

# 4. Sign your own manifest.
skill-trust-proxy keygen --out mykey
skill-trust-proxy sign --manifest path/to/manifest.json --key mykey.secret.key --out attestation.json
skill-trust-proxy verify --manifest path/to/manifest.json --attestation attestation.json
```

`verify` exits 0 on PASS, non-zero on any failure (bad signature, hash mismatch, expired attestation, malformed input). Receipt JSON conforms to `../schemas/receipt.schema.json`.

## What this proves

- ed25519 publisher signatures over canonical (JCS) attestation bytes.
- Manifest hash binding: a single byte changed in the manifest invalidates the attestation.
- Capability decisions per protocol §5.6: required ⇒ `ALLOW`, optional ⇒ `PROMPT`, otherwise `DENY`.
- Session receipts signed by an ephemeral verifier key, schema-conformant for downstream audit.

## Deferred to v0.1.1+

- **Runtime sandbox enforcement.** Actually spawning the tool server under macOS sandbox-exec / Linux Landlock+seccomp / Windows AppContainer with capability tokens translated into syscall allowlists.
- **Federated registry fetch.** HTTP resolution across multiple registry roots with trust-policy ordering.
- **Sigstore keyless mode.** Spec §6.3 — `signature: null` with `sigstore_bundle` chain verification.
- **N-of-M co-attestation.** Spec §6.5.
- **TLS interception** for path-prefix `net:fetch` granularity.
- **Pin / Recall / Policy** primitives — schemas exist in `../schemas/` but no enforcement path in proxy yet.
- **Non-MCP protocol bindings** in manifest schema — v0.2 will add sibling blocks for OpenAI tools, A2A, custom RPC; proxy decision logic already covers them since it doesn't read the binding block.

## Layout

```
proxy/
├── src/
│   ├── main.rs            — entry point + module wiring
│   ├── cli.rs             — clap subcommand dispatch
│   ├── codec.rs           — ed25519 / base32 / base64 / sha256 helpers
│   ├── manifest.rs        — load + canonicalize (JCS) + hash
│   ├── attestation.rs     — sign + verify per §6.2
│   ├── capability.rs      — token parse + ALLOW / PROMPT / DENY decision
│   └── receipt.rs         — signed session receipts per receipt.schema.json
└── examples/
    ├── manifest.json              — signed MCP-server manifest (browser-tools)
    ├── attestation.json           — real ed25519 signature over the above
    ├── publisher.pub.txt          — example publisher's public key id
    └── manifest-openai.json       — unsigned illustrative non-MCP manifest (OpenAI tool calling)
```

`examples/publisher.secret.key` is gitignored — regenerate with `keygen` if needed.

## Test

```
cargo test
```

19 unit tests cover codec round-trips, canonical-form invariance under key reordering, sign-then-verify happy and tampered paths, capability decisions across all categories.

## License

MIT. See `../LICENSE`.
