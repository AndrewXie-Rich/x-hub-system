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

function assertGovernedOfficialSkillRow(skill, packageFileCount, expectedQualityEvidence = {
  replay: "missing",
  fuzz: "missing",
  doctor: "missing",
  smoke: "missing",
}) {
  assert.equal(String(skill?.package_kind || ""), "official_skill");
  assert.equal(String(skill?.trust_tier || ""), "governed_package");
  assert.equal(String(skill?.contract_version || ""), "2026-03-18");
  assert.equal(String(skill?.package_state || ""), "discovered");
  assert.equal(String(skill?.catalog_tier || ""), "embedded_official");
  assert.equal(String(skill?.source_type || ""), "embedded_catalog");
  assert.equal(String(skill?.downloadability || ""), "offline_only");
  assert.equal(String(skill?.buildability || ""), "prebuilt_only");
  assert.equal(String(skill?.support_tier || ""), "official");
  assert.equal(String(skill?.revoke_state || ""), "active");
  assert.equal(String(skill?.artifact_resolution_mode || ""), "embedded_only");
  assert.deepEqual(skill?.doctor_bundles, ["official_skills"]);
  assert.equal(String(skill?.abi_compat_version || ""), "skills_abi_compat.v1");
  assert.equal(String(skill?.compatibility_state || ""), "supported");
  assert.equal(String(skill?.compatibility_envelope?.manifest_contract_version || ""), "xhub.skill_manifest.v1");
  assert.equal(String(skill?.compatibility_envelope?.compatibility_state || ""), "verified");
  assert.deepEqual(skill?.compatibility_envelope?.protocol_versions, ["skills_abi_compat.v1"]);
  assert.deepEqual(skill?.compatibility_envelope?.runtime_hosts, ["hub_runtime", "xt_runtime"]);
  assert.equal(Number(skill?.compatibility_envelope?.last_verified_at_ms || 0), 1710000000000);
  assert.equal(String(skill?.quality_evidence_status?.replay || ""), String(expectedQualityEvidence.replay || ""));
  assert.equal(String(skill?.quality_evidence_status?.fuzz || ""), String(expectedQualityEvidence.fuzz || ""));
  assert.equal(String(skill?.quality_evidence_status?.doctor || ""), String(expectedQualityEvidence.doctor || ""));
  assert.equal(String(skill?.quality_evidence_status?.smoke || ""), String(expectedQualityEvidence.smoke || ""));
  assert.equal(String(skill?.artifact_integrity?.package_sha256 || ""), String(skill?.package_sha256 || ""));
  assert.equal(String(skill?.artifact_integrity?.manifest_sha256 || ""), String(skill?.manifest_sha256 || ""));
  assert.equal(String(skill?.artifact_integrity?.package_format || ""), "tar.gz");
  assert.equal(Number(skill?.artifact_integrity?.file_hash_count || 0), packageFileCount);
  assert.equal(Number(skill?.artifact_integrity?.package_size_bytes || 0) > 0, true);
  assert.equal(String(skill?.artifact_integrity?.signature?.algorithm || ""), "ed25519");
  assert.equal(!!skill?.artifact_integrity?.signature?.present, true);
  assert.equal(!!skill?.artifact_integrity?.signature?.trusted_publisher, true);
  assert.equal(String(skill?.signature_alg || ""), "ed25519");
  assert.equal(!!skill?.signature_verified, true);
  assert.equal(!!skill?.signature_bypassed, false);
  assert.equal(String(skill?.security_profile || ""), "low_risk");
  assert.equal(String(skill?.package_format || ""), "tar.gz");
  assert.equal(Number(skill?.file_hash_count || 0), packageFileCount);
  assert.equal(Number(skill?.package_size_bytes || 0) > 0, true);
}

function assertRequiredAnyGroup(manifest, expectedArgs) {
  const groups = Array.isArray(manifest?.governed_dispatch?.required_any)
    ? manifest.governed_dispatch.required_any
    : [];
  const expected = [...expectedArgs].sort();
  assert.equal(
    groups.some((group) => (
      Array.isArray(group)
      && group.map((value) => String(value || "")).sort().join("\n") === expected.join("\n")
    )),
    true,
    `expected required_any to contain ${expected.join(", ")} for ${String(manifest?.skill_id || "")}`
  );
}

function assertMissingRequiredAnyGroup(manifest, expectedArgs) {
  const groups = Array.isArray(manifest?.governed_dispatch?.required_any)
    ? manifest.governed_dispatch.required_any
    : [];
  const expected = [...expectedArgs].sort();
  assert.equal(
    groups.some((group) => (
      Array.isArray(group)
      && group.map((value) => String(value || "")).sort().join("\n") === expected.join("\n")
    )),
    false,
    `expected required_any to omit ${expected.join(", ")} for ${String(manifest?.skill_id || "")}`
  );
}

function assertLocalTaskWrapperManifest(manifest, {
  skillID,
  capability,
  taskKind,
  sideEffectClass,
  riskLevel,
  requiredInputs,
  passthroughArgs = [],
}) {
  assert.equal(String(manifest?.skill_id || ""), skillID);
  assert.deepEqual(manifest?.capabilities_required, [capability]);
  assert.equal(String(manifest?.side_effect_class || ""), sideEffectClass);
  assert.equal(String(manifest?.risk_level || ""), riskLevel);
  assert.equal(Boolean(manifest?.requires_grant), false);
  assert.equal(Boolean(manifest?.network_policy?.direct_network_forbidden), true);
  assert.equal(String(manifest?.publisher?.publisher_id || ""), "xhub.official");
  assert.equal(String(manifest?.governed_dispatch?.tool || ""), "run_local_task");
  assert.equal(String(manifest?.governed_dispatch?.fixed_args?.task_kind || ""), taskKind);
  assertMissingRequiredAnyGroup(manifest, ["model_id", "preferred_model_id"]);
  assertRequiredAnyGroup(manifest, requiredInputs);
  for (const arg of passthroughArgs) {
    assert.equal(
      Array.isArray(manifest?.governed_dispatch?.passthrough_args)
      && manifest.governed_dispatch.passthrough_args.includes(arg),
      true,
      `expected passthrough_args to include ${arg} for ${skillID}`
    );
  }
  assert.equal(
    Array.isArray(manifest?.governed_dispatch_notes)
      && manifest.governed_dispatch_notes.some((line) => String(line || "").includes("If model_id/preferred_model_id is omitted")),
    true,
    `expected auto-binding governed_dispatch_notes for ${skillID}`
  );
  assert.equal(
    String(manifest?.install_hint || "").includes("source-present only"),
    true,
    `expected source-present install hint for ${skillID}`
  );
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
    assert.equal(String(skill.risk_level || ""), "low");
    assert.equal(Boolean(skill.requires_grant), false);
    assert.equal(String(skill.side_effect_class || ""), "read_only");
    assertGovernedOfficialSkillRow(skill, 3);

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
    assertGovernedOfficialSkillRow(index.skills[0], 2);

    const manifest = JSON.parse(fs.readFileSync(path.join(outputRoot, index.skills[0].manifest_path), "utf8"));
    assert.equal(String(manifest.publisher?.publisher_id || ""), "xhub.local.dev");
    assert.equal(String(manifest.publisher?.public_key_ed25519 || ""), publisher.public_key_ed25519);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

run("official skill builder preserves explicit quality evidence status when provided", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "official-agent-skills-quality-evidence-"));
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
    writeFile(path.join(sourceRoot, "find-skills", "SKILL.md"), "# Find Skills\n");
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
      quality_evidence_status: {
        replay: "missing",
        fuzz: "partial",
        doctor: "passed",
        smoke: "passed",
      },
    }, null, 2));

    const index = buildOfficialAgentSkills({
      sourceRoot,
      outputRoot,
      generatedAtMs: 1710000000000,
      publisherTrustFile: path.join(publisherDir, "trusted_publishers.json"),
      signingPrivateKeyFile: privateKeyPath,
    });

    assert.equal(index.skills.length, 1);
    assertGovernedOfficialSkillRow(index.skills[0], 2, {
      replay: "missing",
      fuzz: "partial",
      doctor: "passed",
      smoke: "passed",
    });
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

run("repo official agent skill source tree includes governed review skills and source-present local model wrappers", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "official-agent-skills-repo-source-"));
  try {
    const sourceRoot = path.resolve(__dirname, "..", "official-agent-skills");
    const outputRoot = path.join(root, "dist");
    const index = buildOfficialAgentSkills({
      sourceRoot,
      outputRoot,
      generatedAtMs: 1710000000000,
      publisherTrustFile: path.join(sourceRoot, "publisher", "trusted_publishers.json"),
    });

    const skillIDs = index.skills.map((skill) => skill.skill_id).sort();
    assert.equal(skillIDs.includes("agent-backup"), true);
    assert.equal(skillIDs.includes("code-review"), true);
    assert.equal(skillIDs.includes("local-embeddings"), true);
    assert.equal(skillIDs.includes("local-ocr"), true);
    assert.equal(skillIDs.includes("local-transcribe"), true);
    assert.equal(skillIDs.includes("local-tts"), true);
    assert.equal(skillIDs.includes("local-vision"), true);
    assert.equal(skillIDs.includes("skill-creator"), true);
    assert.equal(skillIDs.includes("skill-vetter"), true);
    assert.equal(skillIDs.includes("tavily-websearch"), true);

    const agentBackup = index.skills.find((skill) => skill.skill_id === "agent-backup");
    const codeReview = index.skills.find((skill) => skill.skill_id === "code-review");
    const localEmbeddings = index.skills.find((skill) => skill.skill_id === "local-embeddings");
    const localOCR = index.skills.find((skill) => skill.skill_id === "local-ocr");
    const localTranscribe = index.skills.find((skill) => skill.skill_id === "local-transcribe");
    const localTTS = index.skills.find((skill) => skill.skill_id === "local-tts");
    const localVision = index.skills.find((skill) => skill.skill_id === "local-vision");
    const skillCreator = index.skills.find((skill) => skill.skill_id === "skill-creator");
    const skillVetter = index.skills.find((skill) => skill.skill_id === "skill-vetter");
    const tavily = index.skills.find((skill) => skill.skill_id === "tavily-websearch");
    assert.ok(agentBackup);
    assert.ok(codeReview);
    assert.ok(localEmbeddings);
    assert.ok(localOCR);
    assert.ok(localTranscribe);
    assert.ok(localTTS);
    assert.ok(localVision);
    assert.ok(skillCreator);
    assert.ok(skillVetter);
    assert.ok(tavily);

    const agentBackupManifest = JSON.parse(
      fs.readFileSync(path.join(outputRoot, agentBackup.manifest_path), "utf8")
    );
    assert.equal(agentBackupManifest.skill_id, "agent-backup");
    assert.equal(agentBackupManifest.governed_dispatch_variants.length, 3);
    assert.equal(
      agentBackupManifest.governed_dispatch_variants.some(
        (variant) => Array.isArray(variant.actions) && variant.actions.includes("create")
      ),
      true
    );

    const codeReviewManifest = JSON.parse(
      fs.readFileSync(path.join(outputRoot, codeReview.manifest_path), "utf8")
    );
    assert.equal(codeReviewManifest.skill_id, "code-review");
    assert.equal(codeReviewManifest.governed_dispatch_variants.length, 5);
    assert.equal(
      codeReviewManifest.governed_dispatch_variants.some(
        (variant) => Array.isArray(variant.actions) && variant.actions.includes("staged_diff")
      ),
      true
    );

    const localEmbeddingsManifest = JSON.parse(
      fs.readFileSync(path.join(outputRoot, localEmbeddings.manifest_path), "utf8")
    );
    assertLocalTaskWrapperManifest(localEmbeddingsManifest, {
      skillID: "local-embeddings",
      capability: "ai.embed.local",
      taskKind: "embedding",
      sideEffectClass: "read_only",
      riskLevel: "low",
      requiredInputs: ["text", "texts", "query", "documents"],
      passthroughArgs: ["text", "texts", "query", "documents"],
    });

    const localTranscribeManifest = JSON.parse(
      fs.readFileSync(path.join(outputRoot, localTranscribe.manifest_path), "utf8")
    );
    assertLocalTaskWrapperManifest(localTranscribeManifest, {
      skillID: "local-transcribe",
      capability: "ai.audio.local",
      taskKind: "speech_to_text",
      sideEffectClass: "read_only",
      riskLevel: "medium",
      requiredInputs: ["audio_path"],
      passthroughArgs: ["audio_path", "language"],
    });

    const localVisionManifest = JSON.parse(
      fs.readFileSync(path.join(outputRoot, localVision.manifest_path), "utf8")
    );
    assertLocalTaskWrapperManifest(localVisionManifest, {
      skillID: "local-vision",
      capability: "ai.vision.local",
      taskKind: "vision_understand",
      sideEffectClass: "read_only",
      riskLevel: "medium",
      requiredInputs: ["image_path", "image_paths", "image", "multimodal_messages"],
      passthroughArgs: ["image_path", "image_paths", "multimodal_messages", "text"],
    });

    const localOCRManifest = JSON.parse(
      fs.readFileSync(path.join(outputRoot, localOCR.manifest_path), "utf8")
    );
    assertLocalTaskWrapperManifest(localOCRManifest, {
      skillID: "local-ocr",
      capability: "ai.vision.local",
      taskKind: "ocr",
      sideEffectClass: "read_only",
      riskLevel: "medium",
      requiredInputs: ["image_path", "image_paths", "image", "multimodal_messages"],
      passthroughArgs: ["image_path", "image_paths", "multimodal_messages", "language"],
    });

    const localTTSManifest = JSON.parse(
      fs.readFileSync(path.join(outputRoot, localTTS.manifest_path), "utf8")
    );
    assertLocalTaskWrapperManifest(localTTSManifest, {
      skillID: "local-tts",
      capability: "ai.audio.tts.local",
      taskKind: "text_to_speech",
      sideEffectClass: "local_side_effect",
      riskLevel: "low",
      requiredInputs: ["text", "prompt"],
      passthroughArgs: ["text", "prompt", "voice", "output_path"],
    });

    const skillCreatorManifest = JSON.parse(
      fs.readFileSync(path.join(outputRoot, skillCreator.manifest_path), "utf8")
    );
    assert.equal(skillCreatorManifest.skill_id, "skill-creator");
    assert.equal(skillCreatorManifest.governed_dispatch_variants.length, 5);
    assert.equal(
      skillCreatorManifest.governed_dispatch_variants.some(
        (variant) => Array.isArray(variant.actions) && variant.actions.includes("write")
      ),
      true
    );

    const skillVetterManifest = JSON.parse(
      fs.readFileSync(path.join(outputRoot, skillVetter.manifest_path), "utf8")
    );
    assert.equal(skillVetterManifest.skill_id, "skill-vetter");
    assert.equal(skillVetterManifest.governed_dispatch_variants.length, 11);
    assert.equal(
      skillVetterManifest.governed_dispatch_variants.some(
        (variant) => Array.isArray(variant.actions) && variant.actions.includes("scan_exec")
      ),
      true
    );
    assert.equal(
      skillVetterManifest.governed_dispatch_variants.some(
        (variant) => Array.isArray(variant.actions) && variant.actions.includes("review_record")
      ),
      true
    );
    const reviewRecord = skillVetterManifest.governed_dispatch_variants.find(
      (variant) => Array.isArray(variant.actions) && variant.actions.includes("review_record")
    );
    assert.ok(reviewRecord);
    assert.equal(
      Array.isArray(reviewRecord.dispatch?.passthrough_args)
      && reviewRecord.dispatch.passthrough_args.includes("selector"),
      true
    );
    assert.equal(
      Array.isArray(reviewRecord.dispatch?.passthrough_args)
      && reviewRecord.dispatch.passthrough_args.includes("project_id"),
      true
    );

    const tavilyManifest = JSON.parse(
      fs.readFileSync(path.join(outputRoot, tavily.manifest_path), "utf8")
    );
    assert.equal(tavilyManifest.skill_id, "tavily-websearch");
    assert.equal(String(tavilyManifest.governed_dispatch?.tool || ""), "web_search");
    assert.equal(Boolean(tavilyManifest.requires_grant), true);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
