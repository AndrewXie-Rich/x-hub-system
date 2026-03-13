#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { pathToFileURL } = require("node:url");

const REPO_ROOT = path.resolve(__dirname, "..");
const DEFAULT_SCOPE = "project";
const DEFAULT_USER_ID = "xt-smoke-user";
const DEFAULT_PROJECT_ID = "xt-smoke-project";
const DEFAULT_BASELINE_SKILLS = [
  "find-skills",
  "agent-browser",
  "self-improving-agent",
  "summarize",
];

function safeString(value) {
  return String(value == null ? "" : value).trim();
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function parseArgs(argv) {
  const out = {};
  for (let index = 2; index < argv.length; index += 1) {
    const cur = safeString(argv[index]);
    if (!cur.startsWith("--")) continue;
    const key = cur.slice(2);
    const next = argv[index + 1];
    if (next && !safeString(next).startsWith("--")) {
      out[key] = String(next);
      index += 1;
      continue;
    }
    out[key] = "1";
  }
  return out;
}

function usage() {
  return [
    "Usage:",
    "  node scripts/smoke_local_dev_agent_skills_baseline.js [flags]",
    "",
    "Flags:",
    `  --scope <global|project>    default: ${DEFAULT_SCOPE}`,
    `  --user-id <id>             default: ${DEFAULT_USER_ID}`,
    `  --project-id <id>          default: ${DEFAULT_PROJECT_ID}`,
    "  --runtime-base-dir <path>  optional; defaults to a temporary runtime dir",
    "  --publisher-id <id>        optional; defaults to dist/index.json publisher_id",
    "  --skills <csv>             optional; defaults to the default Agent baseline skill IDs",
    "  --json-out <path>          optional; write full smoke summary to disk",
    "  --keep-runtime             keep temporary runtime directory instead of deleting it",
  ].join("\n");
}

function fail(message, extra = {}) {
  const error = new Error(message);
  error.extra = extra;
  throw error;
}

function normalizeSkillList(text) {
  const rows = safeString(text)
    .split(",")
    .map((item) => safeString(item))
    .filter(Boolean);
  return rows.length > 0 ? rows : [...DEFAULT_BASELINE_SKILLS];
}

function selectCandidate({ skillId, publisherId, expectedPackageSHA256, results }) {
  const normalizedSkillId = safeString(skillId).toLowerCase();
  const normalizedPublisherId = safeString(publisherId);
  const expectedSHA = safeString(expectedPackageSHA256).toLowerCase();
  const exact = (Array.isArray(results) ? results : []).filter((row) => {
    const rowSkillId = safeString(row?.skill_id || row?.skillID).toLowerCase();
    return rowSkillId === normalizedSkillId;
  });
  const packaged = exact.filter((row) => safeString(row?.package_sha256 || row?.packageSHA256));

  const exactPublisherAndSHA = packaged.find((row) => {
    const rowPublisher = safeString(row?.publisher_id || row?.publisherID);
    const rowSHA = safeString(row?.package_sha256 || row?.packageSHA256).toLowerCase();
    return rowPublisher === normalizedPublisherId && rowSHA === expectedSHA;
  });
  if (exactPublisherAndSHA) return exactPublisherAndSHA;

  const exactPublisher = packaged.find((row) => {
    const rowPublisher = safeString(row?.publisher_id || row?.publisherID);
    return rowPublisher === normalizedPublisherId;
  });
  if (exactPublisher) return exactPublisher;

  return packaged[0] || null;
}

async function loadSkillsStoreModule() {
  const modulePath = path.join(
    REPO_ROOT,
    "x-hub",
    "grpc-server",
    "hub_grpc_server",
    "src",
    "skills_store.js"
  );
  return import(pathToFileURL(modulePath).href);
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.help || args.h) {
    console.log(usage());
    return;
  }

  const sourceRoot = safeString(process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR);
  const distRoot = safeString(process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR);
  if (!sourceRoot || !distRoot) {
    fail(
      "missing XHUB_OFFICIAL_AGENT_SKILLS_DIR or XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR; load local dev agent skills env first",
      {
        hint: "bash scripts/with_local_dev_agent_skills_env.sh -- node scripts/smoke_local_dev_agent_skills_baseline.js",
      }
    );
  }

  const indexPath = path.join(distRoot, "index.json");
  if (!fs.existsSync(indexPath)) {
    fail(`dist index not found: ${indexPath}`);
  }
  const index = readJson(indexPath);
  const publisherId = safeString(args["publisher-id"] || index.publisher_id);
  if (!publisherId) {
    fail("publisher_id missing from dist index and --publisher-id was not provided");
  }

  const scope = safeString(args.scope || DEFAULT_SCOPE).toLowerCase();
  if (scope !== "global" && scope !== "project") {
    fail(`unsupported scope: ${scope}`, { supported_scopes: ["global", "project"] });
  }
  const userId = safeString(args["user-id"] || DEFAULT_USER_ID);
  const projectId = scope === "project"
    ? safeString(args["project-id"] || DEFAULT_PROJECT_ID)
    : safeString(args["project-id"] || "");
  if (scope === "project" && !projectId) {
    fail("project scope requires --project-id");
  }

  const baselineSkillIds = normalizeSkillList(args.skills);
  const runtimeBaseDir = args["runtime-base-dir"]
    ? path.resolve(String(args["runtime-base-dir"]))
    : fs.mkdtempSync(path.join(os.tmpdir(), "xhub-local-dev-baseline-smoke-"));
  const temporaryRuntime = !args["runtime-base-dir"];
  const keepRuntime = safeString(args["keep-runtime"]) === "1";

  const summary = {
    ok: false,
    publisher_id: publisherId,
    source_root: path.resolve(sourceRoot),
    dist_root: path.resolve(distRoot),
    runtime_base_dir: path.resolve(runtimeBaseDir),
    temporary_runtime: temporaryRuntime,
    scope,
    user_id: userId,
    project_id: projectId,
    baseline_skill_ids: baselineSkillIds,
    search: [],
    pins: [],
    gates: [],
    resolved: [],
    blocked: [],
    missing: [],
  };

  try {
    fs.mkdirSync(runtimeBaseDir, { recursive: true });
    const {
      searchSkills,
      setSkillPin,
      resolveSkillsWithTrace,
      evaluateSkillExecutionGate,
    } = await loadSkillsStoreModule();

    const indexSkills = new Map();
    for (const row of Array.isArray(index.skills) ? index.skills : []) {
      const skillId = safeString(row?.skill_id);
      if (!skillId) continue;
      indexSkills.set(skillId, row);
    }

    for (const skillId of baselineSkillIds) {
      const indexEntry = indexSkills.get(skillId);
      if (!indexEntry) {
        summary.missing.push({
          skill_id: skillId,
          phase: "dist-index",
          reason: "skill not found in dist/index.json",
        });
        continue;
      }

      const results = searchSkills(runtimeBaseDir, { query: skillId, limit: 20 });
      const candidate = selectCandidate({
        skillId,
        publisherId,
        expectedPackageSHA256: indexEntry.package_sha256,
        results,
      });

      summary.search.push({
        skill_id: skillId,
        expected_package_sha256: safeString(indexEntry.package_sha256).toLowerCase(),
        expected_version: safeString(indexEntry.version),
        results: results.map((row) => ({
          skill_id: safeString(row?.skill_id),
          publisher_id: safeString(row?.publisher_id),
          version: safeString(row?.version),
          package_sha256: safeString(row?.package_sha256).toLowerCase(),
          source_id: safeString(row?.source_id),
        })),
        selected_package_sha256: safeString(candidate?.package_sha256).toLowerCase(),
        selected_publisher_id: safeString(candidate?.publisher_id),
      });

      if (!candidate) {
        summary.missing.push({
          skill_id: skillId,
          phase: "search",
          reason: "no exact uploadable candidate returned by searchSkills",
        });
        continue;
      }

      const gate = evaluateSkillExecutionGate(runtimeBaseDir, {
        packageSha256: candidate.package_sha256,
        skillId,
        publisherId: candidate.publisher_id || publisherId,
      });
      summary.gates.push({
        skill_id: skillId,
        package_sha256: safeString(candidate.package_sha256).toLowerCase(),
        allowed: !!gate.allowed,
        deny_code: safeString(gate.deny_code),
        detail: gate.detail || {},
      });
      if (!gate.allowed) {
        summary.missing.push({
          skill_id: skillId,
          phase: "gate",
          reason: safeString(gate.deny_code || "gate_denied"),
        });
        continue;
      }

      const pin = setSkillPin(runtimeBaseDir, {
        scope,
        userId,
        projectId,
        skillId,
        packageSha256: candidate.package_sha256,
        note: `local_dev_agent_baseline_smoke:${scope}:${skillId}`,
      });
      summary.pins.push({
        skill_id: safeString(pin.skill_id),
        scope: safeString(pin.scope),
        package_sha256: safeString(pin.package_sha256).toLowerCase(),
        updated_at_ms: Number(pin.updated_at_ms || 0),
      });
    }

    const resolvedWithTrace = resolveSkillsWithTrace(runtimeBaseDir, { userId, projectId });
    summary.resolved = (Array.isArray(resolvedWithTrace.resolved) ? resolvedWithTrace.resolved : []).map((row) => ({
      skill_id: safeString(row?.skill?.skill_id),
      scope: safeString(row?.scope),
      package_sha256: safeString(row?.skill?.package_sha256).toLowerCase(),
      publisher_id: safeString(row?.skill?.publisher_id),
      version: safeString(row?.skill?.version),
    }));
    summary.blocked = Array.isArray(resolvedWithTrace.blocked) ? resolvedWithTrace.blocked : [];

    const resolvedSkillIds = new Set(summary.resolved.map((row) => safeString(row.skill_id)));
    for (const skillId of baselineSkillIds) {
      if (resolvedSkillIds.has(skillId)) continue;
      const alreadyMissing = summary.missing.some((row) => safeString(row.skill_id) === skillId);
      if (!alreadyMissing) {
        summary.missing.push({
          skill_id: skillId,
          phase: "resolved",
          reason: "skill not present in resolved set",
        });
      }
    }

    summary.ok = summary.missing.length === 0 && summary.blocked.length === 0;
  } finally {
    if (safeString(args["json-out"])) {
      writeJson(path.resolve(String(args["json-out"])), summary);
    }
    if (temporaryRuntime && !keepRuntime) {
      fs.rmSync(runtimeBaseDir, { recursive: true, force: true });
    }
  }

  const out = JSON.stringify(summary, null, 2);
  if (summary.ok) {
    console.log(out);
    return;
  }
  console.error(out);
  process.exitCode = 1;
}

main().catch((error) => {
  const payload = {
    ok: false,
    error: safeString(error?.message || error),
    extra: error?.extra || {},
  };
  console.error(JSON.stringify(payload, null, 2));
  process.exit(1);
});
