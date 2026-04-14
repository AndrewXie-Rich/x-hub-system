#!/usr/bin/env node
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const zlib = require("node:zlib");

const DEFAULT_SOURCE_ROOT = path.resolve(__dirname, "..", "official-agent-skills");
const DEFAULT_OUTPUT_ROOT = path.join(DEFAULT_SOURCE_ROOT, "dist");
const OFFICIAL_SOURCE_ID = "builtin:catalog";
const OFFICIAL_PUBLISHER_ID = "xhub.official";
const DEFAULT_SCHEMA_VERSION = "xhub.skill_manifest.v1";
const DEFAULT_PUBLISHER_TRUST_FILE = path.join(DEFAULT_SOURCE_ROOT, "publisher", "trusted_publishers.json");
const GOVERNED_PACKAGE_CONTRACT_VERSION = "2026-03-18";
const SKILL_ABI_COMPAT_VERSION = "skills_abi_compat.v1";
const OFFICIAL_PACKAGE_KIND = "official_skill";
const OFFICIAL_TRUST_TIER = "governed_package";
const OFFICIAL_PACKAGE_STATE = "discovered";
const OFFICIAL_CATALOG_TIER = "embedded_official";
const OFFICIAL_SOURCE_TYPE = "embedded_catalog";
const OFFICIAL_DOWNLOADABILITY = "offline_only";
const OFFICIAL_BUILDABILITY = "prebuilt_only";
const OFFICIAL_SUPPORT_TIER = "official";
const OFFICIAL_REVOKE_STATE = "active";
const OFFICIAL_ARTIFACT_RESOLUTION_MODE = "embedded_only";
const OFFICIAL_DOCTOR_BUNDLES = Object.freeze(["official_skills"]);
const OFFICIAL_RUNTIME_HOSTS = Object.freeze(["hub_runtime", "xt_runtime"]);
const QUALITY_EVIDENCE_STATES = new Set(["passed", "partial", "missing", "blocked"]);
const PACKAGE_INCLUDE_EXTENSIONS = new Set([
  ".bash",
  ".cjs",
  ".cts",
  ".js",
  ".json",
  ".md",
  ".mjs",
  ".mts",
  ".py",
  ".sh",
  ".text",
  ".ts",
  ".txt",
  ".yaml",
  ".yml",
  ".zsh",
]);
const HIGH_RISK_CAPABILITY_RE = [
  /^connectors?\./i,
  /^web\./i,
  /^network\./i,
  /^ai\.generate\.paid$/i,
  /^ai\.generate\.remote$/i,
  /^payments?\./i,
  /^shell\./i,
  /^filesystem\./i,
  /^fs\./i,
];

function safeString(value) {
  return String(value == null ? "" : value).trim();
}

function safeArray(value) {
  return Array.isArray(value) ? value : [];
}

function parseBoolLike(value) {
  if (typeof value === "boolean") return value;
  if (typeof value === "number") return Number.isFinite(value) ? value !== 0 : null;
  const normalized = safeString(value).toLowerCase();
  if (!normalized) return null;
  if (["1", "true", "yes", "y", "on"].includes(normalized)) return true;
  if (["0", "false", "no", "n", "off"].includes(normalized)) return false;
  return null;
}

function cloneJSONValue(value) {
  if (value == null) return undefined;
  return JSON.parse(JSON.stringify(value));
}

function normalizeQualityEvidenceState(value) {
  const normalized = safeString(value).toLowerCase();
  if (QUALITY_EVIDENCE_STATES.has(normalized)) return normalized;
  return "missing";
}

function normalizeQualityEvidenceStatus(value) {
  const input = value && typeof value === "object" ? value : {};
  return {
    replay: normalizeQualityEvidenceState(input.replay),
    fuzz: normalizeQualityEvidenceState(input.fuzz),
    doctor: normalizeQualityEvidenceState(input.doctor),
    smoke: normalizeQualityEvidenceState(input.smoke),
  };
}

function normalizedRiskLevel(value) {
  const normalized = safeString(value).toLowerCase();
  if (normalized === "moderate") return "medium";
  if (["low", "medium", "high", "critical"].includes(normalized)) return normalized;
  return "";
}

function isHighRiskCapability(capability) {
  const normalized = safeString(capability).toLowerCase();
  return !!normalized && HIGH_RISK_CAPABILITY_RE.some((re) => re.test(normalized));
}

function inferRiskLevel(explicit, capabilities) {
  const normalizedExplicit = normalizedRiskLevel(explicit);
  if (normalizedExplicit) return normalizedExplicit;
  const normalizedCapabilities = safeArray(capabilities).map((value) => safeString(value).toLowerCase()).filter(Boolean);
  if (normalizedCapabilities.some((capability) => isHighRiskCapability(capability))) return "high";
  if (normalizedCapabilities.some((capability) => (
    capability.startsWith("browser.")
    || capability.startsWith("email.")
    || capability.startsWith("repo.")
  ))) {
    return "medium";
  }
  return "low";
}

function inferRequiresGrant(rawValue, capabilities, riskLevel) {
  const explicit = parseBoolLike(rawValue);
  if (explicit != null) return explicit;
  const normalizedRisk = normalizedRiskLevel(riskLevel) || inferRiskLevel("", capabilities);
  if (normalizedRisk === "high" || normalizedRisk === "critical") return true;
  return safeArray(capabilities).some((capability) => isHighRiskCapability(capability));
}

function inferSideEffectClass(explicit, capabilities, riskLevel) {
  const explicitValue = safeString(explicit);
  if (explicitValue) return explicitValue;
  const normalizedCapabilities = safeArray(capabilities).map((value) => safeString(value).toLowerCase()).filter(Boolean);
  const normalizedRisk = normalizedRiskLevel(riskLevel) || inferRiskLevel("", capabilities);
  if (normalizedCapabilities.length === 0) return normalizedRisk === "low" ? "read_only" : "external_side_effect";
  if (normalizedCapabilities.every((capability) => (
    capability.includes("status")
    || capability.includes("read")
    || capability.includes("list")
    || capability.includes("search")
    || capability.includes("snapshot")
    || capability.includes("inspect")
  ))) {
    return "read_only";
  }
  if (normalizedCapabilities.some((capability) => isHighRiskCapability(capability))) {
    return "external_side_effect";
  }
  if (normalizedCapabilities.some((capability) => (
    capability.startsWith("repo.")
    || capability.startsWith("filesystem.")
    || capability.startsWith("fs.")
  ))) {
    return "project_write";
  }
  return normalizedRisk === "low" ? "read_only" : "project_write";
}

function inferSecurityProfile(riskLevel) {
  const normalizedRisk = normalizedRiskLevel(riskLevel);
  return normalizedRisk === "high" || normalizedRisk === "critical" ? "high_risk" : "low_risk";
}

function sha256Hex(data) {
  return crypto.createHash("sha256").update(data).digest("hex");
}

function toCanonicalValue(value) {
  if (Array.isArray(value)) return value.map((entry) => toCanonicalValue(entry));
  if (!value || typeof value !== "object") return value;
  const output = {};
  for (const key of Object.keys(value).sort()) {
    output[key] = toCanonicalValue(value[key]);
  }
  return output;
}

function canonicalManifestBytes(manifestObj) {
  const plain = manifestObj && typeof manifestObj === "object" ? { ...manifestObj } : {};
  delete plain.signature;
  return Buffer.from(JSON.stringify(toCanonicalValue(plain)), "utf8");
}

function readJsonFile(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function loadTrustedPublishersSnapshot(filePath) {
  const resolved = path.resolve(filePath);
  if (!fs.existsSync(resolved)) {
    return {
      schema_version: "xhub.trusted_publishers.v1",
      updated_at_ms: 0,
      publishers: [],
    };
  }
  const obj = readJsonFile(resolved);
  return {
    schema_version: safeString(obj.schema_version || "xhub.trusted_publishers.v1") || "xhub.trusted_publishers.v1",
    updated_at_ms: Math.max(0, Number(obj.updated_at_ms || 0)),
    publishers: safeArray(obj.publishers).map((publisher) => ({
      publisher_id: safeString(publisher.publisher_id || publisher.id),
      public_key_ed25519: safeString(publisher.public_key_ed25519),
      enabled: publisher.enabled !== false,
    })).filter((publisher) => publisher.publisher_id),
  };
}

function resolvePublisherTrustEntry(snapshot, publisherId) {
  const normalizedID = safeString(publisherId || OFFICIAL_PUBLISHER_ID) || OFFICIAL_PUBLISHER_ID;
  const rows = safeArray(snapshot && snapshot.publishers);
  return rows.find((publisher) => safeString(publisher.publisher_id) === normalizedID) || null;
}

function signManifest(manifestObj, {
  privateKeyPem,
  publicKeyBase64,
  signedAtMs,
}) {
  const manifest = JSON.parse(JSON.stringify(manifestObj));
  if (!manifest.publisher || typeof manifest.publisher !== "object") {
    manifest.publisher = {};
  }
  manifest.publisher.public_key_ed25519 = safeString(publicKeyBase64);
  const signatureBytes = crypto.sign(
    null,
    canonicalManifestBytes(manifest),
    String(privateKeyPem || "")
  );
  manifest.signature = {
    alg: "ed25519",
    signed_at_ms: Math.max(0, Number(signedAtMs || 0)),
    sig: `base64:${signatureBytes.toString("base64")}`,
  };
  return manifest;
}

function parseFrontmatter(markdownText) {
  const normalized = String(markdownText || "").replace(/\r\n/g, "\n");
  if (!normalized.startsWith("---\n")) return {};
  const remainder = normalized.slice(4);
  const closingIndex = remainder.indexOf("\n---");
  if (closingIndex < 0) return {};
  const block = remainder.slice(0, closingIndex);
  const values = {};
  for (const rawLine of block.split("\n")) {
    const line = String(rawLine || "");
    const colonIndex = line.indexOf(":");
    if (colonIndex < 0) continue;
    const key = line.slice(0, colonIndex).trim().toLowerCase();
    const value = line.slice(colonIndex + 1).trim().replace(/^["']|["']$/g, "");
    if (!key || !value) continue;
    values[key] = value;
  }
  return values;
}

function shouldIncludePath(relativePath) {
  const normalized = String(relativePath || "").replace(/\\/g, "/");
  if (!normalized || normalized === "dist") return false;
  const segments = normalized.split("/");
  if (segments.includes("node_modules")) return false;
  for (const segment of segments) {
    if (segment.startsWith(".") && segment.toLowerCase() !== "skill.md") return false;
  }
  const baseName = path.posix.basename(normalized).toLowerCase();
  if (baseName === "skill.md" || baseName === "skill.json" || baseName === "package.json") {
    return true;
  }
  return PACKAGE_INCLUDE_EXTENSIONS.has(path.posix.extname(normalized).toLowerCase());
}

function shouldTraverseDirectory(relativePath) {
  const normalized = String(relativePath || "").replace(/\\/g, "/");
  if (!normalized) return true;
  const segments = normalized.split("/");
  if (segments.includes("node_modules") || segments.includes("dist")) return false;
  for (const segment of segments) {
    if (segment.startsWith(".")) return false;
  }
  return true;
}

function collectSourceFiles(skillDir) {
  const root = path.resolve(skillDir);
  const files = [];

  function walk(currentDir) {
    const rows = fs.readdirSync(currentDir, { withFileTypes: true });
    rows.sort((lhs, rhs) => lhs.name.localeCompare(rhs.name));
    for (const row of rows) {
      const absolutePath = path.join(currentDir, row.name);
      const relativePath = path.relative(root, absolutePath).split(path.sep).join("/");
      if (row.isDirectory()) {
        if (!shouldTraverseDirectory(relativePath)) continue;
        walk(absolutePath);
        continue;
      }
      if (!shouldIncludePath(relativePath)) continue;
      files.push({
        absolutePath,
        relativePath,
        data: fs.readFileSync(absolutePath),
        mode: fs.statSync(absolutePath).mode & 0o777,
      });
    }
  }

  walk(root);
  files.sort((lhs, rhs) => lhs.relativePath.localeCompare(rhs.relativePath));
  return files;
}

function encodeTarString(value, length) {
  const buffer = Buffer.alloc(length, 0);
  Buffer.from(String(value || ""), "utf8").copy(buffer, 0, 0, length);
  return buffer;
}

function encodeTarOctal(value, length) {
  const buffer = Buffer.alloc(length, 0);
  const octal = Math.max(0, Number(value || 0)).toString(8);
  const padded = octal.padStart(length - 2, "0");
  Buffer.from(`${padded}\0 `, "ascii").copy(buffer, 0, 0, length);
  return buffer;
}

function encodeTarHeader(file) {
  const header = Buffer.alloc(512, 0);
  const nameBuffer = Buffer.from(file.relativePath, "utf8");
  if (nameBuffer.length > 100) {
    throw new Error(`relative path too long for tar header: ${file.relativePath}`);
  }

  encodeTarString(file.relativePath, 100).copy(header, 0);
  encodeTarOctal(file.mode || 0o644, 8).copy(header, 100);
  encodeTarOctal(0, 8).copy(header, 108);
  encodeTarOctal(0, 8).copy(header, 116);
  encodeTarOctal(file.data.length, 12).copy(header, 124);
  encodeTarOctal(0, 12).copy(header, 136);
  Buffer.from("        ", "ascii").copy(header, 148);
  header[156] = "0".charCodeAt(0);
  encodeTarString("ustar", 6).copy(header, 257);
  encodeTarString("00", 2).copy(header, 263);
  encodeTarString("root", 32).copy(header, 265);
  encodeTarString("root", 32).copy(header, 297);

  let checksum = 0;
  for (let index = 0; index < 512; index += 1) {
    checksum += header[index];
  }
  const checksumBuffer = Buffer.alloc(8, 0);
  const octal = checksum.toString(8).padStart(6, "0");
  Buffer.from(`${octal}\0 `, "ascii").copy(checksumBuffer, 0, 0, 8);
  checksumBuffer.copy(header, 148);
  return header;
}

function buildDeterministicTarGz(files) {
  const chunks = [];
  for (const file of files) {
    chunks.push(encodeTarHeader(file));
    chunks.push(file.data);
    const remainder = file.data.length % 512;
    if (remainder !== 0) {
      chunks.push(Buffer.alloc(512 - remainder, 0));
    }
  }
  chunks.push(Buffer.alloc(1024, 0));
  const tarBuffer = Buffer.concat(chunks);
  return zlib.gzipSync(tarBuffer, { level: 9, mtime: 0 });
}

function ensureDirectory(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function buildGovernedPackageMetadata({
  sourceManifest,
  files,
  packageBytes,
  packageSHA256,
  manifestSHA256,
  generatedAtMs,
  publisherTrust,
  manifest,
}) {
  const capabilities = safeArray(sourceManifest?.capabilities_required).map((value) => safeString(value)).filter(Boolean);
  const risk_level = inferRiskLevel(sourceManifest?.risk_level, capabilities);
  const requires_grant = inferRequiresGrant(sourceManifest?.requires_grant, capabilities, risk_level);
  const side_effect_class = inferSideEffectClass(sourceManifest?.side_effect_class, capabilities, risk_level);
  const signature_alg = safeString(manifest?.signature?.alg);
  const signature_present = !!safeString(manifest?.signature?.sig);
  return {
    side_effect_class,
    risk_level,
    requires_grant,
    package_kind: OFFICIAL_PACKAGE_KIND,
    trust_tier: OFFICIAL_TRUST_TIER,
    contract_version: GOVERNED_PACKAGE_CONTRACT_VERSION,
    package_state: OFFICIAL_PACKAGE_STATE,
    catalog_tier: OFFICIAL_CATALOG_TIER,
    source_type: OFFICIAL_SOURCE_TYPE,
    downloadability: OFFICIAL_DOWNLOADABILITY,
    buildability: OFFICIAL_BUILDABILITY,
    support_tier: OFFICIAL_SUPPORT_TIER,
    revoke_state: OFFICIAL_REVOKE_STATE,
    artifact_resolution_mode: OFFICIAL_ARTIFACT_RESOLUTION_MODE,
    doctor_bundles: [...OFFICIAL_DOCTOR_BUNDLES],
    abi_compat_version: SKILL_ABI_COMPAT_VERSION,
    compatibility_state: "supported",
    compatibility_envelope: {
      manifest_contract_version: safeString(sourceManifest?.schema_version || DEFAULT_SCHEMA_VERSION) || DEFAULT_SCHEMA_VERSION,
      protocol_versions: [SKILL_ABI_COMPAT_VERSION],
      min_hub_version: "",
      min_xt_version: "",
      runtime_hosts: [...OFFICIAL_RUNTIME_HOSTS],
      compatibility_state: "verified",
      last_verified_at_ms: Number(generatedAtMs || 0),
    },
    quality_evidence_status: normalizeQualityEvidenceStatus(sourceManifest?.quality_evidence_status),
    artifact_integrity: {
      package_sha256: packageSHA256,
      manifest_sha256: manifestSHA256,
      package_format: "tar.gz",
      package_size_bytes: Buffer.isBuffer(packageBytes) ? packageBytes.length : 0,
      file_hash_count: Array.isArray(files) ? files.length : 0,
      signature: {
        algorithm: signature_alg,
        present: signature_present,
        trusted_publisher: !!safeString(publisherTrust?.public_key_ed25519),
      },
    },
    signature_alg,
    signature_verified: signature_present && !!safeString(publisherTrust?.public_key_ed25519),
    signature_bypassed: false,
    security_profile: inferSecurityProfile(risk_level),
    package_format: "tar.gz",
    file_hash_count: Array.isArray(files) ? files.length : 0,
    package_size_bytes: Buffer.isBuffer(packageBytes) ? packageBytes.length : 0,
  };
}

function normalizeSourceManifest(skillDir, manifestObj, frontmatter) {
  const skillID = safeString(manifestObj.skill_id || manifestObj.id || path.basename(skillDir));
  const version = safeString(manifestObj.version);
  const name = safeString(manifestObj.name || frontmatter.name || skillID);
  const description = safeString(manifestObj.description || frontmatter.description);
  const command = safeString(
    manifestObj?.entrypoint?.command
    || manifestObj?.command
    || manifestObj?.main
  );
  if (!skillID) {
    throw new Error(`missing skill_id in ${path.join(skillDir, "skill.json")}`);
  }
  if (!version) {
    throw new Error(`missing version in ${path.join(skillDir, "skill.json")}`);
  }
  if (!command) {
    throw new Error(`missing entrypoint.command in ${path.join(skillDir, "skill.json")}`);
  }
  if (!name) {
    throw new Error(`missing name in ${path.join(skillDir, "skill.json")}`);
  }
  if (!description) {
    throw new Error(`missing description in ${path.join(skillDir, "skill.json")}`);
  }

  const entrypoint = {
    runtime: safeString(manifestObj?.entrypoint?.runtime || "text") || "text",
    command,
    args: safeArray(manifestObj?.entrypoint?.args).map((value) => safeString(value)).filter(Boolean),
  };
  const capabilities = safeArray(
    manifestObj.capabilities_required || manifestObj.capabilities || manifestObj.required_capabilities
  ).map((value) => safeString(value)).filter(Boolean);

  return {
    schema_version: safeString(manifestObj.schema_version || DEFAULT_SCHEMA_VERSION) || DEFAULT_SCHEMA_VERSION,
    skill_id: skillID,
    name,
    version,
    description,
    entrypoint,
    capabilities_required: capabilities,
    input_schema_ref: safeString(manifestObj.input_schema_ref),
    output_schema_ref: safeString(manifestObj.output_schema_ref),
    side_effect_class: safeString(manifestObj.side_effect_class),
    risk_level: safeString(manifestObj.risk_level),
    requires_grant: Boolean(manifestObj.requires_grant),
    timeout_ms: Number.isFinite(Number(manifestObj.timeout_ms)) ? Number(manifestObj.timeout_ms) : undefined,
    max_retries: Number.isFinite(Number(manifestObj.max_retries)) ? Number(manifestObj.max_retries) : undefined,
    governed_dispatch: cloneJSONValue(manifestObj.governed_dispatch),
    governed_dispatch_notes: cloneJSONValue(manifestObj.governed_dispatch_notes),
    governed_dispatch_variants: cloneJSONValue(manifestObj.governed_dispatch_variants),
    network_policy: {
      direct_network_forbidden: manifestObj?.network_policy?.direct_network_forbidden !== false,
    },
    publisher: {
      publisher_id: safeString(manifestObj?.publisher?.publisher_id || manifestObj.publisher_id || OFFICIAL_PUBLISHER_ID) || OFFICIAL_PUBLISHER_ID,
      public_key_ed25519: safeString(manifestObj?.publisher?.public_key_ed25519 || manifestObj.public_key_ed25519),
    },
    install_hint: safeString(manifestObj.install_hint || "Install from the Agent Baseline menu in X-Terminal or pin the official package from X-Hub."),
    quality_evidence_status: normalizeQualityEvidenceStatus(manifestObj.quality_evidence_status),
  };
}

function discoverSourceSkillDirs(sourceRoot) {
  if (!fs.existsSync(sourceRoot)) return [];
  const rows = fs.readdirSync(sourceRoot, { withFileTypes: true });
  return rows
    .filter((row) => row.isDirectory())
    .map((row) => row.name)
    .filter((name) => !name.startsWith(".") && name !== "dist" && name !== "publisher")
    .sort()
    .map((name) => path.join(sourceRoot, name));
}

function buildOfficialAgentSkills({
  sourceRoot = DEFAULT_SOURCE_ROOT,
  outputRoot = DEFAULT_OUTPUT_ROOT,
  generatedAtMs = Date.now(),
  publisherTrustFile = DEFAULT_PUBLISHER_TRUST_FILE,
  signingPrivateKeyFile = "",
  publisherIdOverride = "",
  signedAtMs = generatedAtMs,
} = {}) {
  ensureDirectory(outputRoot);
  const packagesDir = path.join(outputRoot, "packages");
  const manifestsDir = path.join(outputRoot, "manifests");
  ensureDirectory(packagesDir);
  ensureDirectory(manifestsDir);

  const trustedSnapshot = loadTrustedPublishersSnapshot(publisherTrustFile);
  const signingPrivateKeyPath = safeString(signingPrivateKeyFile || process.env.XHUB_OFFICIAL_AGENT_SIGNING_PRIVATE_KEY_FILE);
  const signingPrivateKeyPem = signingPrivateKeyPath
    ? fs.readFileSync(path.resolve(signingPrivateKeyPath), "utf8")
    : "";

  const skills = [];
  for (const skillDir of discoverSourceSkillDirs(sourceRoot)) {
    const skillMarkdownPath = path.join(skillDir, "SKILL.md");
    const sourceManifestPath = path.join(skillDir, "skill.json");
    if (!fs.existsSync(skillMarkdownPath) || !fs.existsSync(sourceManifestPath)) {
      throw new Error(`official skill source must contain SKILL.md and skill.json: ${skillDir}`);
    }

    const frontmatter = parseFrontmatter(fs.readFileSync(skillMarkdownPath, "utf8"));
    const sourceManifest = normalizeSourceManifest(
      skillDir,
      readJsonFile(sourceManifestPath),
      frontmatter
    );
    const normalizedPublisherIdOverride = safeString(publisherIdOverride);
    if (normalizedPublisherIdOverride) {
      sourceManifest.publisher.publisher_id = normalizedPublisherIdOverride;
    }
    const publisherTrust = resolvePublisherTrustEntry(
      trustedSnapshot,
      sourceManifest?.publisher?.publisher_id || OFFICIAL_PUBLISHER_ID
    );
    if (publisherTrust?.public_key_ed25519) {
      sourceManifest.publisher.public_key_ed25519 = publisherTrust.public_key_ed25519;
    }
    const files = collectSourceFiles(skillDir);
    if (files.length <= 0) {
      throw new Error(`no packageable files found under ${skillDir}`);
    }

    const packageBytes = buildDeterministicTarGz(files);
    const packageSHA256 = sha256Hex(packageBytes);
    let manifest = {
      ...sourceManifest,
      package_sha256: packageSHA256,
      files: files.map((file) => ({
        path: file.relativePath,
        sha256: sha256Hex(file.data),
      })),
    };
    if (signingPrivateKeyPem) {
      const publicKeyBase64 = safeString(manifest?.publisher?.public_key_ed25519);
      if (!publicKeyBase64) {
        throw new Error(`missing public_key_ed25519 for publisher ${safeString(manifest?.publisher?.publisher_id)} in ${publisherTrustFile}`);
      }
      manifest = signManifest(manifest, {
        privateKeyPem: signingPrivateKeyPem,
        publicKeyBase64,
        signedAtMs,
      });
    }

    const manifestBytes = Buffer.from(`${JSON.stringify(manifest, null, 2)}\n`, "utf8");
    const manifestSHA256 = sha256Hex(manifestBytes);
    const packageFileName = `${packageSHA256}.tgz`;
    const manifestFileName = `${packageSHA256}.json`;
    fs.writeFileSync(path.join(packagesDir, packageFileName), packageBytes);
    fs.writeFileSync(path.join(manifestsDir, manifestFileName), manifestBytes);
    const governedMeta = buildGovernedPackageMetadata({
      sourceManifest,
      files,
      packageBytes,
      packageSHA256,
      manifestSHA256: manifestSHA256,
      generatedAtMs,
      publisherTrust,
      manifest,
    });

    skills.push({
      skill_id: sourceManifest.skill_id,
      name: sourceManifest.name,
      version: sourceManifest.version,
      description: sourceManifest.description,
      publisher_id: sourceManifest.publisher.publisher_id,
      capabilities_required: sourceManifest.capabilities_required,
      source_id: OFFICIAL_SOURCE_ID,
      install_hint: sourceManifest.install_hint,
      entrypoint_runtime: sourceManifest.entrypoint.runtime,
      entrypoint_command: sourceManifest.entrypoint.command,
      entrypoint_args: sourceManifest.entrypoint.args,
      package_sha256: packageSHA256,
      manifest_sha256: manifestSHA256,
      package_path: `packages/${packageFileName}`,
      manifest_path: `manifests/${manifestFileName}`,
      source_dir: path.relative(sourceRoot, skillDir).split(path.sep).join("/"),
      updated_at_ms: generatedAtMs,
      ...governedMeta,
    });
  }

  skills.sort((lhs, rhs) => lhs.skill_id.localeCompare(rhs.skill_id));
  const index = {
    schema_version: "xhub.official_agent_skill_index.v1",
    generated_at_ms: generatedAtMs,
    publisher_id: safeString(publisherIdOverride || OFFICIAL_PUBLISHER_ID) || OFFICIAL_PUBLISHER_ID,
    source_root: path.relative(outputRoot, sourceRoot).split(path.sep).join("/") || "..",
    skills,
  };
  writeJson(path.join(outputRoot, "index.json"), index);
  writeJson(path.join(outputRoot, "trusted_publishers.json"), trustedSnapshot);
  return index;
}

function main(argv) {
  const args = Array.isArray(argv) ? [...argv] : process.argv.slice(2);
  let sourceRoot = DEFAULT_SOURCE_ROOT;
  let outputRoot = DEFAULT_OUTPUT_ROOT;
  let publisherTrustFile = DEFAULT_PUBLISHER_TRUST_FILE;
  let signingPrivateKeyFile = "";
  let publisherIdOverride = "";
  for (let index = 0; index < args.length; index += 1) {
    const flag = String(args[index] || "");
    if (flag === "--source-root") {
      sourceRoot = path.resolve(String(args[index + 1] || ""));
      index += 1;
      continue;
    }
    if (flag === "--output-root") {
      outputRoot = path.resolve(String(args[index + 1] || ""));
      index += 1;
      continue;
    }
    if (flag === "--publisher-trust-file") {
      publisherTrustFile = path.resolve(String(args[index + 1] || ""));
      index += 1;
      continue;
    }
    if (flag === "--sign-private-key-file") {
      signingPrivateKeyFile = path.resolve(String(args[index + 1] || ""));
      index += 1;
      continue;
    }
    if (flag === "--publisher-id-override") {
      publisherIdOverride = safeString(args[index + 1] || "");
      index += 1;
      continue;
    }
    throw new Error(`unknown flag: ${flag}`);
  }

  const index = buildOfficialAgentSkills({
    sourceRoot,
    outputRoot,
    publisherTrustFile,
    signingPrivateKeyFile,
    publisherIdOverride,
  });
  process.stdout.write(`${JSON.stringify({
    output_root: outputRoot,
    publisher_id: safeString(publisherIdOverride || index.publisher_id),
    package_count: index.skills.length,
    skill_ids: index.skills.map((skill) => skill.skill_id),
  }, null, 2)}\n`);
}

if (require.main === module) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`${String(error && error.stack ? error.stack : error)}\n`);
    process.exitCode = 1;
  }
}

module.exports = {
  buildOfficialAgentSkills,
  collectSourceFiles,
  parseFrontmatter,
};
