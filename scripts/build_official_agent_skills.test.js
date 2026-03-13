#!/usr/bin/env node
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const {
  buildOfficialAgentSkills,
} = require("./build_official_agent_skills.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

function writeFile(filePath, contents) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, contents, "utf8");
}

function fromBase64Url(text) {
  const raw = String(text || "").replace(/-/g, "+").replace(/_/g, "/");
  const padded = raw.padEnd(Math.ceil(raw.length / 4) * 4, "=");
  return Buffer.from(padded, "base64");
}

function makePublisherTrust(publisherId = "xhub.official") {
  const pair = crypto.generateKeyPairSync("ed25519");
  const jwk = pair.publicKey.export({ format: "jwk" });
  const rawPublic = fromBase64Url(String(jwk.x || ""));
  return {
    publisher_id: publisherId,
    public_key_ed25519: `base64:${rawPublic.toString("base64")}`,
    private_pem: pair.privateKey.export({ format: "pem", type: "pkcs8" }).toString("utf8"),
  };
}

run("official skill builder emits deterministic packages and index entries", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "official-agent-skills-"));
  try {
    const sourceRoot = path.join(root, "official-agent-skills");
    const outputRoot = path.join(sourceRoot, "dist");
    const publisherDir = path.join(sourceRoot, "publisher");
    const publisher = makePublisherTrust();
    const privateKeyPath = path.join(root, "xhub_official_ed25519.pem");
    writeFile(path.join(publisherDir, "trusted_publishers.json"), JSON.stringify({
      schema_version: "xhub.trusted_publishers.v1",
      updated_at_ms: 1710000000000,
      publishers: [
        {
          publisher_id: publisher.publisher_id,
          public_key_ed25519: publisher.public_key_ed25519,
          enabled: true,
        },
      ],
    }, null, 2));
    writeFile(privateKeyPath, publisher.private_pem);
    writeFile(path.join(sourceRoot, "find-skills", "SKILL.md"), `---
name: find-skills
version: 1.0.0
description: Discover governed skills.
---

# Find Skills
`);
    writeFile(path.join(sourceRoot, "find-skills", "skill.json"), JSON.stringify({
      schema_version: "xhub.skill_manifest.v1",
      skill_id: "find-skills",
      name: "Find Skills",
      version: "1.0.0",
      description: "Discover governed skills.",
      input_schema_ref: "schema://find-skills.input",
      output_schema_ref: "schema://find-skills.output",
      side_effect_class: "read_only",
      risk_level: "low",
      requires_grant: false,
      timeout_ms: 10000,
      max_retries: 1,
      entrypoint: {
        runtime: "text",
        command: "cat",
        args: ["SKILL.md"],
      },
      capabilities_required: ["skills.search"],
      publisher: {
        publisher_id: "xhub.official",
      },
      install_hint: "Install via baseline.",
    }, null, 2));
    writeFile(
      path.join(sourceRoot, "find-skills", "scripts", "main.js"),
      "export function run() { return 'ok'; }\n"
    );

    const first = buildOfficialAgentSkills({
      sourceRoot,
      outputRoot,
      generatedAtMs: 1710000000000,
      publisherTrustFile: path.join(publisherDir, "trusted_publishers.json"),
      signingPrivateKeyFile: privateKeyPath,
    });
    const second = buildOfficialAgentSkills({
      sourceRoot,
      outputRoot,
      generatedAtMs: 1710000000000,
      publisherTrustFile: path.join(publisherDir, "trusted_publishers.json"),
      signingPrivateKeyFile: privateKeyPath,
    });

    assert.equal(first.skills.length, 1);
    assert.deepEqual(first, second);

    const skill = first.skills[0];
    assert.equal(skill.skill_id, "find-skills");
    assert.match(skill.package_sha256, /^[0-9a-f]{64}$/);
    assert.equal(skill.source_id, "builtin:catalog");

    const packagePath = path.join(outputRoot, skill.package_path);
    const manifestPath = path.join(outputRoot, skill.manifest_path);
    assert.equal(fs.existsSync(packagePath), true);
    assert.equal(fs.existsSync(manifestPath), true);

    const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
    assert.equal(manifest.skill_id, "find-skills");
    assert.equal(manifest.package_sha256, skill.package_sha256);
    assert.equal(String(manifest.publisher?.publisher_id || ""), "xhub.official");
    assert.equal(String(manifest.publisher?.public_key_ed25519 || ""), publisher.public_key_ed25519);
    assert.equal(String(manifest.input_schema_ref || ""), "schema://find-skills.input");
    assert.equal(String(manifest.output_schema_ref || ""), "schema://find-skills.output");
    assert.equal(String(manifest.side_effect_class || ""), "read_only");
    assert.equal(String(manifest.risk_level || ""), "low");
    assert.equal(Boolean(manifest.requires_grant), false);
    assert.equal(Number(manifest.timeout_ms || 0), 10000);
    assert.equal(Number(manifest.max_retries || 0), 1);
    assert.equal(String(manifest.signature?.alg || ""), "ed25519");
    assert.equal(typeof manifest.signature?.sig, "string");
    assert.deepEqual(
      manifest.files.map((row) => row.path).sort(),
      ["SKILL.md", "skill.json", "scripts/main.js"].sort()
    );
    const distTrusted = JSON.parse(fs.readFileSync(path.join(outputRoot, "trusted_publishers.json"), "utf8"));
    assert.equal(distTrusted.publishers.length, 1);
    assert.equal(String(distTrusted.publishers[0]?.publisher_id || ""), "xhub.official");
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

run("official skill builder can publish under a local dev publisher id", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "official-agent-skills-dev-publisher-"));
  try {
    const sourceRoot = path.join(root, "official-agent-skills");
    const outputRoot = path.join(sourceRoot, "dist");
    const publisherDir = path.join(sourceRoot, "publisher");
    const publisher = makePublisherTrust("xhub.local.dev");
    const privateKeyPath = path.join(root, "xhub_local_dev_ed25519.pem");
    writeFile(path.join(publisherDir, "trusted_publishers.json"), JSON.stringify({
      schema_version: "xhub.trusted_publishers.v1",
      updated_at_ms: 1710000000000,
      publishers: [
        {
          publisher_id: publisher.publisher_id,
          public_key_ed25519: publisher.public_key_ed25519,
          enabled: true,
        },
      ],
    }, null, 2));
    writeFile(privateKeyPath, publisher.private_pem);
    writeFile(path.join(sourceRoot, "find-skills", "SKILL.md"), `---
name: find-skills
version: 1.0.0
description: Discover governed skills.
---

# Find Skills
`);
    writeFile(path.join(sourceRoot, "find-skills", "skill.json"), JSON.stringify({
      schema_version: "xhub.skill_manifest.v1",
      skill_id: "find-skills",
      name: "Find Skills",
      version: "1.0.0",
      description: "Discover governed skills.",
      entrypoint: {
        runtime: "text",
        command: "cat",
        args: ["SKILL.md"],
      },
      capabilities_required: ["skills.search"],
      publisher: {
        publisher_id: "xhub.official",
      },
      install_hint: "Install via baseline.",
    }, null, 2));

    const index = buildOfficialAgentSkills({
      sourceRoot,
      outputRoot,
      generatedAtMs: 1710000000000,
      publisherTrustFile: path.join(publisherDir, "trusted_publishers.json"),
      signingPrivateKeyFile: privateKeyPath,
      publisherIdOverride: "xhub.local.dev",
    });

    assert.equal(index.publisher_id, "xhub.local.dev");
    assert.equal(index.skills.length, 1);
    assert.equal(index.skills[0].publisher_id, "xhub.local.dev");

    const manifest = JSON.parse(fs.readFileSync(path.join(outputRoot, index.skills[0].manifest_path), "utf8"));
    assert.equal(String(manifest.publisher?.publisher_id || ""), "xhub.local.dev");
    assert.equal(String(manifest.publisher?.public_key_ed25519 || ""), publisher.public_key_ed25519);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
