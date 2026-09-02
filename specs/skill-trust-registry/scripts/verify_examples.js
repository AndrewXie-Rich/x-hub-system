#!/usr/bin/env node
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const examplesDir = path.join(root, "schemas", "examples");

function readExample(name) {
  const file = path.join(examplesDir, `${name}.example.json`);
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function expectPattern(value, pattern, label) {
  assert(typeof value === "string", `${label} must be a string`);
  assert(pattern.test(value), `${label} has unexpected shape: ${value}`);
}

const sha256Pattern = /^sha256:[0-9a-f]{64}$/;
const bareSha256Pattern = /^[0-9a-f]{64}$/;
const ed25519KeyPattern = /^ed25519:[a-z2-7]{52}$/;
const ed25519SignaturePattern = /^ed25519:[A-Za-z0-9+/]+={0,2}$/;

function main() {
  const manifest = readExample("manifest");
  const attestation = readExample("attestation");
  const pin = readExample("pin");
  const policy = readExample("policy");
  const recall = readExample("recall");
  const receipt = readExample("receipt");

  expectPattern(manifest.artifact.sha256, bareSha256Pattern, "manifest.artifact.sha256");
  expectPattern(attestation.manifest_hash, sha256Pattern, "attestation.manifest_hash");
  expectPattern(attestation.artifact_hash, sha256Pattern, "attestation.artifact_hash");
  expectPattern(attestation.publisher_key_id, ed25519KeyPattern, "attestation.publisher_key_id");
  expectPattern(attestation.signature, ed25519SignaturePattern, "attestation.signature");
  expectPattern(receipt.signature, ed25519SignaturePattern, "receipt.signature");

  const expectedArtifactHash = `sha256:${manifest.artifact.sha256}`;
  assert(attestation.artifact_hash === expectedArtifactHash, "attestation artifact_hash must match manifest artifact sha256");
  assert(pin.artifact_hash === expectedArtifactHash, "pin artifact_hash must match manifest artifact sha256");
  assert(receipt.artifact_hash === expectedArtifactHash, "receipt artifact_hash must match manifest artifact sha256");

  assert(pin.server_name === manifest.name, "pin server_name must match manifest name");
  assert(receipt.server_name === manifest.name, "receipt server_name must match manifest name");

  assert(pin.manifest_hash === attestation.manifest_hash, "pin manifest_hash must match attestation");
  assert(receipt.manifest_hash === attestation.manifest_hash, "receipt manifest_hash must match attestation");
  assert(recall.recalls.some((entry) => entry.manifest_hash === attestation.manifest_hash), "recall must include the attested manifest hash");

  assert(manifest.publisher.key_id === attestation.publisher_key_id, "attestation publisher key must match manifest publisher");
  assert(recall.publisher_key_id === manifest.publisher.key_id, "recall publisher key must match manifest publisher");
  assert(
    policy.trusted_publishers.some((publisher) => publisher.key_id === manifest.publisher.key_id),
    "policy must trust the manifest publisher key"
  );

  assert(pin.policy_hash === receipt.policy_hash, "receipt policy_hash must match pin policy_hash");

  const declaredCapabilities = new Set([
    ...manifest.capabilities.required,
    ...manifest.capabilities.optional,
  ]);
  for (const capability of pin.granted_capabilities) {
    assert(declaredCapabilities.has(capability), `granted capability is not declared by manifest: ${capability}`);
  }

  for (const entry of recall.recalls) {
    expectPattern(entry.signature, ed25519SignaturePattern, "recall entry signature");
  }

  console.log("PASS example chain: manifest -> attestation -> pin -> receipt -> recall");
}

try {
  main();
} catch (error) {
  console.error(`FAIL example chain: ${error.message}`);
  process.exit(1);
}
