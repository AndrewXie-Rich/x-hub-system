#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");
const childProcess = require("node:child_process");

const { buildOfficialAgentSkills } = require("./build_official_agent_skills.js");

const REPO_ROOT = path.resolve(__dirname, "..");
const DEFAULT_CANONICAL_SOURCE_ROOT = path.join(REPO_ROOT, "official-agent-skills");
const DEFAULT_BUILD_ROOT = path.join(REPO_ROOT, "build", "local-dev-agent-skills");
const DEFAULT_PUBLISHER_ID = "xhub.local.dev";

function safeString(value) {
  return String(value == null ? "" : value).trim();
}

function ensureDirectory(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJson(filePath, value) {
  ensureDirectory(path.dirname(filePath));
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function sanitizePublisherId(publisherId) {
  const normalized = safeString(publisherId)
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, "-")
    .replace(/^-+/g, "")
    .replace(/-+$/g, "");
  return normalized || DEFAULT_PUBLISHER_ID;
}

function usage() {
  return [
    "Usage:",
    "  node scripts/build_local_dev_agent_skills_release.js [flags]",
    "",
    "Flags:",
    `  --publisher-id <id>     default: ${DEFAULT_PUBLISHER_ID}`,
    `  --source-root <path>    default: ${DEFAULT_CANONICAL_SOURCE_ROOT}`,
    "  --staging-root <path>   default: build/local-dev-agent-skills/<publisher>/source",
    "  --output-root <path>    default: <staging-root>/dist",
    "  --private-key-out <p>   default: build/local-dev-agent-skills/<publisher>/<publisher>.pem",
    "  --trust-out <path>      default: <staging-root>/publisher/trusted_publishers.json",
    "  --env-out <path>        default: build/local-dev-agent-skills/<publisher>/use_local_dev_agent_skills.env.sh",
    "  --meta-out <path>       default: build/local-dev-agent-skills/<publisher>/release.json",
    "  --force                 recreate staged source root and signing material if targets already exist",
  ].join("\n");
}

function copyTree(sourceRoot, targetRoot) {
  const source = path.resolve(sourceRoot);
  const target = path.resolve(targetRoot);
  const rows = fs.readdirSync(source, { withFileTypes: true });
  rows.sort((lhs, rhs) => lhs.name.localeCompare(rhs.name));
  for (const row of rows) {
    const name = safeString(row.name);
    if (!name || name.startsWith(".")) continue;
    if (name === "dist" || name === "dist-dev") continue;
    const from = path.join(source, name);
    const to = path.join(target, name);
    if (row.isDirectory()) {
      ensureDirectory(to);
      copyTree(from, to);
      continue;
    }
    ensureDirectory(path.dirname(to));
    fs.copyFileSync(from, to);
    fs.chmodSync(to, fs.statSync(from).mode & 0o777);
  }
}

function patchStagedSkillManifests(stagingRoot, publisherId) {
  const rows = fs.readdirSync(stagingRoot, { withFileTypes: true });
  for (const row of rows) {
    if (!row.isDirectory()) continue;
    const dirName = safeString(row.name);
    if (!dirName || dirName.startsWith(".") || dirName === "dist" || dirName === "publisher") continue;
    const manifestPath = path.join(stagingRoot, dirName, "skill.json");
    if (!fs.existsSync(manifestPath)) continue;
    const manifest = readJson(manifestPath);
    const publisher = manifest.publisher && typeof manifest.publisher === "object"
      ? { ...manifest.publisher }
      : {};
    publisher.publisher_id = publisherId;
    delete publisher.public_key_ed25519;
    manifest.publisher = publisher;
    writeJson(manifestPath, manifest);
  }
}

function writeEnvFile(envPath, stagingRoot, outputRoot) {
  const contents = [
    "#!/usr/bin/env bash",
    `export XHUB_OFFICIAL_AGENT_SKILLS_DIR=${shellQuote(path.resolve(stagingRoot))}`,
    `export XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR=${shellQuote(path.resolve(outputRoot))}`,
    "",
  ].join("\n");
  ensureDirectory(path.dirname(envPath));
  fs.writeFileSync(envPath, contents, "utf8");
}

function shellQuote(value) {
  const text = String(value == null ? "" : value);
  return `'${text.replace(/'/g, `'\"'\"'`)}'`;
}

function ensureDevSigningMaterial({
  publisherId,
  privateKeyOut,
  trustOut,
  force,
}) {
  const keyExists = fs.existsSync(privateKeyOut);
  const trustExists = fs.existsSync(trustOut);
  if (keyExists && trustExists && !force) {
    return {
      publisher_id: publisherId,
      private_key_out: path.resolve(privateKeyOut),
      trust_out: path.resolve(trustOut),
      reused_existing: true,
    };
  }
  if (keyExists && !trustExists && !force) {
    throw new Error(`refusing to overwrite partial signing material without --force: ${keyExists ? privateKeyOut : trustOut}`);
  }

  const generator = path.join(__dirname, "generate_official_agent_signing_keypair.js");
  const args = [
    generator,
    "--publisher-id", publisherId,
    "--private-key-out", privateKeyOut,
    "--trust-out", trustOut,
  ];
  if (force || trustExists) {
    args.push("--force");
  }
  const result = childProcess.spawnSync(process.execPath, args, {
    cwd: REPO_ROOT,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    throw new Error((result.stderr || result.stdout || "generate_official_agent_signing_keypair failed").trim());
  }
  const parsed = JSON.parse(result.stdout || "{}");
  return {
    ...parsed,
    reused_existing: false,
  };
}

function prepareStagingRoot({
  canonicalSourceRoot,
  stagingRoot,
  publisherId,
  force,
}) {
  const resolvedStagingRoot = path.resolve(stagingRoot);
  if (fs.existsSync(resolvedStagingRoot)) {
    if (!force) {
      throw new Error(`staging root already exists; rerun with --force to recreate: ${resolvedStagingRoot}`);
    }
    fs.rmSync(resolvedStagingRoot, { recursive: true, force: true });
  }
  ensureDirectory(resolvedStagingRoot);
  copyTree(canonicalSourceRoot, resolvedStagingRoot);
  patchStagedSkillManifests(resolvedStagingRoot, publisherId);
}

function main(argv) {
  const args = Array.isArray(argv) ? [...argv] : process.argv.slice(2);
  let publisherId = DEFAULT_PUBLISHER_ID;
  let canonicalSourceRoot = DEFAULT_CANONICAL_SOURCE_ROOT;
  let stagingRoot = "";
  let outputRoot = "";
  let privateKeyOut = "";
  let trustOut = "";
  let envOut = "";
  let metaOut = "";
  let force = false;

  for (let index = 0; index < args.length; index += 1) {
    const flag = safeString(args[index]);
    if (flag === "--publisher-id") {
      publisherId = safeString(args[index + 1]);
      index += 1;
      continue;
    }
    if (flag === "--source-root") {
      canonicalSourceRoot = path.resolve(String(args[index + 1] || ""));
      index += 1;
      continue;
    }
    if (flag === "--staging-root") {
      stagingRoot = path.resolve(String(args[index + 1] || ""));
      index += 1;
      continue;
    }
    if (flag === "--output-root") {
      outputRoot = path.resolve(String(args[index + 1] || ""));
      index += 1;
      continue;
    }
    if (flag === "--private-key-out") {
      privateKeyOut = path.resolve(String(args[index + 1] || ""));
      index += 1;
      continue;
    }
    if (flag === "--trust-out") {
      trustOut = path.resolve(String(args[index + 1] || ""));
      index += 1;
      continue;
    }
    if (flag === "--env-out") {
      envOut = path.resolve(String(args[index + 1] || ""));
      index += 1;
      continue;
    }
    if (flag === "--meta-out") {
      metaOut = path.resolve(String(args[index + 1] || ""));
      index += 1;
      continue;
    }
    if (flag === "--force") {
      force = true;
      continue;
    }
    if (flag === "--help" || flag === "-h") {
      process.stdout.write(`${usage()}\n`);
      return;
    }
    throw new Error(`unknown flag: ${flag}\n\n${usage()}`);
  }

  const normalizedPublisherId = safeString(publisherId) || DEFAULT_PUBLISHER_ID;
  const publisherSlug = sanitizePublisherId(normalizedPublisherId);
  const buildRoot = path.join(DEFAULT_BUILD_ROOT, publisherSlug);
  const resolvedStagingRoot = stagingRoot || path.join(buildRoot, "source");
  const resolvedOutputRoot = outputRoot || path.join(resolvedStagingRoot, "dist");
  const resolvedPrivateKeyOut = privateKeyOut || path.join(buildRoot, `${publisherSlug}.pem`);
  const resolvedTrustOut = trustOut || path.join(resolvedStagingRoot, "publisher", "trusted_publishers.json");
  const resolvedEnvOut = envOut || path.join(buildRoot, "use_local_dev_agent_skills.env.sh");
  const resolvedMetaOut = metaOut || path.join(buildRoot, "release.json");

  if (!fs.existsSync(canonicalSourceRoot)) {
    throw new Error(`source root not found: ${canonicalSourceRoot}`);
  }

  prepareStagingRoot({
    canonicalSourceRoot,
    stagingRoot: resolvedStagingRoot,
    publisherId: normalizedPublisherId,
    force,
  });
  const signing = ensureDevSigningMaterial({
    publisherId: normalizedPublisherId,
    privateKeyOut: resolvedPrivateKeyOut,
    trustOut: resolvedTrustOut,
    force,
  });

  const index = buildOfficialAgentSkills({
    sourceRoot: resolvedStagingRoot,
    outputRoot: resolvedOutputRoot,
    publisherTrustFile: resolvedTrustOut,
    signingPrivateKeyFile: resolvedPrivateKeyOut,
    publisherIdOverride: normalizedPublisherId,
  });
  writeEnvFile(resolvedEnvOut, resolvedStagingRoot, resolvedOutputRoot);

  const metadata = {
    publisher_id: normalizedPublisherId,
    canonical_source_root: path.resolve(canonicalSourceRoot),
    staging_source_root: path.resolve(resolvedStagingRoot),
    dist_root: path.resolve(resolvedOutputRoot),
    private_key_out: path.resolve(resolvedPrivateKeyOut),
    trust_out: path.resolve(resolvedTrustOut),
    env_out: path.resolve(resolvedEnvOut),
    reused_existing_signing_material: Boolean(signing.reused_existing),
    package_count: index.skills.length,
    skill_ids: index.skills.map((skill) => skill.skill_id),
  };
  writeJson(resolvedMetaOut, metadata);

  process.stdout.write(`${JSON.stringify(metadata, null, 2)}\n`);
}

if (require.main === module) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`${String(error && error.stack ? error.stack : error)}\n`);
    process.exitCode = 1;
  }
}
