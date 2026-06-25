# WO-01 — Write valid example payloads for each schema

**Owner:** AI · **Effort:** 30 min · **Task ID:** #1 · **Dependencies:** none

## Why this matters

The 6 JSON Schemas at `specs/mcp-trust-registry/schemas/*.schema.json` are valid (ajv-confirmed) but contain no example data. RFC reviewers — especially those evaluating the spec on GitHub — overwhelmingly read example payloads before they read schemas. Without examples, reviewers either skip the spec or ask "show me what real data looks like" in the discussion, costing momentum.

This WO produces one valid example payload per schema. Examples form a coherent narrative (the fictional `browser-tools` MCP server, same as in `protocol-v0.1.md` §4.1 and `demo-60s.md`), so a reader can trace a single artifact's journey through manifest → attestation → pin → receipt → recall.

## Scope

**In scope:**
- Six example JSON files, one per schema, validating cleanly against the corresponding schema.
- Cross-consistent values: the same `manifest_hash`, `artifact_hash`, `publisher_key_id`, and `server_name` thread through all examples so a reader sees one coherent story.

**Out of scope:**
- Generating real ed25519 signatures (use placeholder base64 strings that match the regex pattern but are not cryptographically meaningful).
- Adding example-specific docs / per-example comments.
- Changing any schema. If you find a schema bug, surface it as a separate blocker task; do not silently fix.

## Deliverables

Create these files in `specs/mcp-trust-registry/schemas/examples/`:

1. `manifest.example.json` — the fictional `browser-tools` v1.4.2 manifest from `protocol-v0.1.md` §4.1, with all required fields populated. Use the publisher `jane@acme.com` per the demo script. Use plausible npm artifact metadata.
2. `attestation.example.json` — the attestation for the manifest above. Use the standard (non-keyless) form: `signature` non-null, `sigstore_bundle: null`.
3. `policy.example.json` — a "personal" template policy. Reference the registry `https://registry.mcp-trust.org`, trust `jane@acme.com`, deny `secret:*`, grant_if_required for `fs:read` and `net:fetch`.
4. `pin.example.json` — a pin tying the example user (`andrew`) to the example manifest, with the granted capability subset matching `protocol-v0.1.md` §8 (granted: `fs:read:/tmp/**`, `net:fetch:*`; denied: `shell:exec`, `secret:read:GITHUB_TOKEN`).
5. `receipt.example.json` — a session receipt for a 47-call session with 1 denial (matches demo Scene 2). Include the optional `denial_summary` field with one entry.
6. `recall.example.json` — a recall list for `jane@acme.com` with one recall entry citing a fictional CVE-2026-1234, including the optional `severity: "high"` and `supersedes_with` pointing at a different sha256.

Each example MUST validate with:
```bash
npx --yes -p ajv-cli -p ajv-formats ajv validate --spec=draft2020 -c ajv-formats \
  -s schemas/<name>.schema.json -d schemas/examples/<name>.example.json
```

## Acceptance criteria

1. All 6 example files exist at the specified paths.
2. Each validates against its corresponding schema using the command above.
3. Cross-field consistency:
   - `manifest_hash` is identical across attestation, pin, receipt
   - `artifact_hash` is identical across attestation, pin, receipt
   - `publisher_key_id` is identical across manifest, attestation, recall
   - `server_name` is identical across manifest, pin, receipt
4. All placeholder hashes are 64 lowercase hex chars matching `^[0-9a-f]{64}$`.
5. All placeholder signatures match the regex in the schema and are exactly the length expected for ed25519 (88 base64 chars with padding).

## References (read first)

- `specs/mcp-trust-registry/protocol-v0.1.md` §4.1 (manifest example), §6.1 (attestation example), §8 (pin), §9 (policy YAML — convert to JSON), §10.1 (recall), §11.3 (receipt example)
- `specs/mcp-trust-registry/schemas/*.schema.json` — for exact field types and regexes

## Anti-patterns

- Don't generate real ed25519 keys / signatures. This is example data; cryptographic realism doesn't add value and risks confusing readers about which artifacts in the repo are "real" attestations.
- Don't introduce new fields or speculative metadata beyond what the schema specifies. Examples should be minimal-but-valid, not feature-showcases.
- Don't add a "fixture-generator" script. Keep it static JSON. The point is human-readable examples for spec reviewers, not test data for a unit test.

## Handoff notes

After completing, the next WO-02 (CI) will validate these examples as part of the schema CI run, so make sure they actually validate before marking the task complete. If you find a real schema bug while doing this, **stop**, surface it as a blocker task, and ask the user before fixing.
