# Example Chain

The example payloads show the minimum trust chain that a verifier sees before
starting an MCP server session:

1. `schemas/examples/manifest.example.json`
   Declares the server name, artifact hash, publisher key, transport, tools,
   and requested capabilities.
2. `schemas/examples/attestation.example.json`
   Binds the manifest hash to the artifact hash and publisher key.
3. `schemas/examples/pin.example.json`
   Records the local install decision: which manifest/artifact pair was pinned
   and which capabilities were granted.
4. `schemas/examples/receipt.example.json`
   Records the session outcome, including the pinned hashes, policy hash,
   capability denials, and verifier key.
5. `schemas/examples/recall.example.json`
   Shows how a publisher can recall a previously attested manifest hash.

All signatures in the examples are placeholders. They are shaped like ed25519
signatures so schema validation and UI flows can be tested, but they are not
cryptographically valid and must never be accepted by a production verifier.

Run the lightweight consistency check:

```bash
node specs/mcp-trust-registry/scripts/verify_examples.js --example
```

The script checks cross-file consistency for the example chain:

- `server_name` threads through manifest, pin, and receipt.
- `manifest_hash` threads through attestation, pin, receipt, and recall.
- `artifact_hash` matches the manifest artifact SHA-256.
- publisher key IDs match across manifest, attestation, policy, and recall.
- granted capabilities are declared by the manifest.
- placeholder hashes and signatures have the expected structure.

This is not a cryptographic verifier. It is a guardrail that keeps the examples
coherent while the v0.1 draft evolves.
