#!/usr/bin/env node
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { pathToFileURL } = require("node:url");

const REPO_ROOT = path.resolve(__dirname, "..");
const DEFAULT_BASELINE_PATH = path.join(REPO_ROOT, "official-agent-skills", "default_agent_baseline.v1.json");
const DEFAULT_OUTPUT_PATH = path.join(REPO_ROOT, "build", "reports", "w8_c1_starter_pack_baseline_evidence.v1.json");

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
    const current = safeString(argv[index]);
    if (!current.startsWith("--")) continue;
    const key = current.slice(2);
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
  const baselinePath = path.resolve(args["baseline-path"] || DEFAULT_BASELINE_PATH);
  const outputPath = path.resolve(args.out || DEFAULT_OUTPUT_PATH);
  const sourceRoot = path.resolve(args["source-root"] || path.join(REPO_ROOT, "official-agent-skills"));
  const distRoot = path.resolve(args["dist-root"] || path.join(sourceRoot, "dist"));
  const baseline = readJson(baselinePath);
  const baselineSkills = Array.isArray(baseline?.skills) ? baseline.skills : [];
  const baselineSkillIDs = baselineSkills.map((row) => safeString(row?.skill_id)).filter(Boolean);
  const runtimeBaseDir = fs.mkdtempSync(path.join(os.tmpdir(), "w8-c1-starter-pack-"));
  const generatedAt = new Date().toISOString();

  process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIR = sourceRoot;
  process.env.XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR = distRoot;

  const index = readJson(path.join(distRoot, "index.json"));
  const indexSkills = new Map();
  for (const row of Array.isArray(index?.skills) ? index.skills : []) {
    const skillID = safeString(row?.skill_id);
    if (!skillID) continue;
    indexSkills.set(skillID, row);
  }

  const {
    evaluateSkillExecutionGate,
    listOfficialSkillPackageDoctorSummaries,
    resolveSkillsWithTrace,
    searchSkills,
    setSkillPin,
  } = await loadSkillsStoreModule();

  const searchRows = [];
  const gateRows = [];
  const pinRows = [];
  const missingCatalogSkills = [];

  try {
    for (const skill of baselineSkills) {
      const skillID = safeString(skill?.skill_id);
      if (!skillID) continue;
      const indexEntry = indexSkills.get(skillID);
      if (!indexEntry) {
        missingCatalogSkills.push(skillID);
        continue;
      }

      const results = searchSkills(runtimeBaseDir, { query: skillID, limit: 20 });
      const candidate = selectCandidate({
        skillId: skillID,
        publisherId: index.publisher_id,
        expectedPackageSHA256: indexEntry.package_sha256,
        results,
      });

      searchRows.push({
        skill_id: skillID,
        result_count: Array.isArray(results) ? results.length : 0,
        selected_package_sha256: safeString(candidate?.package_sha256).toLowerCase(),
      });

      if (!candidate) continue;

      const gate = evaluateSkillExecutionGate(runtimeBaseDir, {
        packageSha256: candidate.package_sha256,
        skillId: skillID,
        publisherId: candidate.publisher_id || index.publisher_id,
      });
      gateRows.push({
        skill_id: skillID,
        allowed: !!gate.allowed,
        deny_code: safeString(gate.deny_code),
      });
      if (!gate.allowed) continue;

      const pin = setSkillPin(runtimeBaseDir, {
        scope: "project",
        userId: "w8-c1-evidence-user",
        projectId: "w8-c1-evidence-project",
        skillId: skillID,
        packageSha256: candidate.package_sha256,
        note: `w8_c1_starter_pack_baseline:${skillID}`,
      });
      pinRows.push({
        skill_id: safeString(pin.skill_id),
        package_sha256: safeString(pin.package_sha256).toLowerCase(),
        scope: safeString(pin.scope),
      });
    }

    const doctorSummaries = listOfficialSkillPackageDoctorSummaries(runtimeBaseDir, { limit: 200 });
    const doctorBySkill = new Map();
    for (const row of doctorSummaries) {
      const skillID = safeString(row?.skill_id);
      if (!skillID || doctorBySkill.has(skillID)) continue;
      doctorBySkill.set(skillID, row);
    }

    const resolved = resolveSkillsWithTrace(runtimeBaseDir, {
      userId: "w8-c1-evidence-user",
      projectId: "w8-c1-evidence-project",
    });
    const resolvedSkillIDs = (Array.isArray(resolved?.resolved) ? resolved.resolved : [])
      .map((row) => safeString(row?.skill?.skill_id))
      .filter(Boolean)
      .sort();

    const catalogRows = baselineSkills.map((skill) => {
      const skillID = safeString(skill?.skill_id);
      const expectedQuality = skill?.required_quality_evidence_status || {};
      const indexEntry = indexSkills.get(skillID) || null;
      const actualQuality = indexEntry?.quality_evidence_status || {};
      return {
        skill_id: skillID,
        display_name: safeString(skill?.display_name),
        expected_quality_evidence_status: {
          doctor: safeString(expectedQuality.doctor || "missing"),
          smoke: safeString(expectedQuality.smoke || "missing"),
        },
        actual_quality_evidence_status: {
          replay: safeString(actualQuality.replay || "missing"),
          fuzz: safeString(actualQuality.fuzz || "missing"),
          doctor: safeString(actualQuality.doctor || "missing"),
          smoke: safeString(actualQuality.smoke || "missing"),
        },
      };
    });

    const doctorRows = baselineSkillIDs.map((skillID) => {
      const summary = doctorBySkill.get(skillID) || {};
      return {
        skill_id: skillID,
        overall_state: safeString(summary.overall_state),
        package_state: safeString(summary.package_state),
        blocking_failures: Number(summary.blocking_failures || 0),
        passed_checks: Number(summary?.summary?.passed || 0),
      };
    });

    const catalogQualityOK = catalogRows.every((row) => (
      row.actual_quality_evidence_status.doctor === row.expected_quality_evidence_status.doctor
      && row.actual_quality_evidence_status.smoke === row.expected_quality_evidence_status.smoke
    ));
    const doctorReady = doctorRows.every((row) => row.overall_state === "ready" && row.blocking_failures === 0);
    const gatesAllowed = gateRows.length === baselineSkillIDs.length && gateRows.every((row) => row.allowed);
    const smokeResolved = resolvedSkillIDs.length === baselineSkillIDs.length
      && baselineSkillIDs.every((skillID) => resolvedSkillIDs.includes(skillID));
    const ready = missingCatalogSkills.length === 0 && catalogQualityOK && doctorReady && gatesAllowed && smokeResolved;

    const payload = {
      schema_version: "xhub.w8_c1_starter_pack_baseline_evidence.v1",
      generated_at: generatedAt,
      status: ready
        ? "ready"
        : "blocked",
      baseline: {
        baseline_id: safeString(baseline?.baseline_id),
        title: safeString(baseline?.title),
        skill_ids: baselineSkillIDs,
        baseline_ref: path.relative(REPO_ROOT, baselinePath),
      },
      catalog_alignment: {
        all_baseline_skills_present: missingCatalogSkills.length === 0,
        missing_skill_ids: missingCatalogSkills,
        quality_status_matches_required_surface: catalogQualityOK,
        rows: catalogRows,
      },
      doctor_snapshot: {
        all_baseline_skills_ready: doctorReady,
        rows: doctorRows,
      },
      smoke_snapshot: {
        all_execution_gates_allowed: gatesAllowed,
        all_baseline_skills_resolved: smokeResolved,
        search_rows: searchRows,
        gate_rows: gateRows,
        pin_rows: pinRows,
        resolved_skill_ids: resolvedSkillIDs,
        blocked_rows: Array.isArray(resolved?.blocked) ? resolved.blocked : [],
      },
      machine_verdict: ready
        ? "PASS(starter_pack_baseline_frozen_with_doctor_and_smoke_evidence)"
        : "NO_GO(starter_pack_baseline_missing_catalog_or_quality_or_resolution_truth)",
      source_refs: [
        "official-agent-skills/default_agent_baseline.v1.json",
        "official-agent-skills/dist/index.json",
        "scripts/smoke_local_dev_agent_skills_baseline.js",
        "x-hub/grpc-server/hub_grpc_server/src/skills_store.js",
      ],
    };

    writeJson(outputPath, payload);
    process.stdout.write(`${JSON.stringify({ output_path: outputPath, status: payload.status }, null, 2)}\n`);
    if (!ready) process.exitCode = 1;
  } finally {
    fs.rmSync(runtimeBaseDir, { recursive: true, force: true });
  }
}

main().catch((error) => {
  process.stderr.write(`${String(error && error.stack ? error.stack : error)}\n`);
  process.exit(1);
});
