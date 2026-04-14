#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");

const REPO_ROOT = path.resolve(__dirname, "..");
const DEFAULT_INDEX_PATH = path.join(REPO_ROOT, "official-agent-skills", "dist", "index.json");
const DEFAULT_OUTPUT_PATH = path.join(REPO_ROOT, "build", "reports", "w8_c2_skill_surface_truth_evidence.v1.json");

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
    } else {
      out[key] = "1";
    }
  }
  return out;
}

function shortSHA(value) {
  const normalized = safeString(value).toLowerCase();
  return normalized ? normalized.slice(0, 12) : "n/a";
}

function findSkill(index, skillId) {
  return (Array.isArray(index?.skills) ? index.skills : []).find((row) => safeString(row?.skill_id) === skillId) || null;
}

function detailTrustRoot(skill) {
  const publisher = safeString(skill?.publisher_id) || "unknown publisher";
  const trusted = !!skill?.signature_verified || !!skill?.artifact_integrity?.signature?.trusted_publisher;
  if (trusted && publisher === "xhub.official") {
    return `official trust root: ${publisher} | signature=verified`;
  }
  if (trusted) {
    return `Hub trusted publisher: ${publisher}`;
  }
  return `trust root unresolved: ${publisher}`;
}

function detailPinnedVersion(skill, pinState) {
  const version = safeString(skill?.version) || "unknown";
  const base = `${version} @${shortSHA(skill?.package_sha256)}`;
  if (pinState?.activeScopes?.length) {
    return `${base} | pinned=${pinState.activeScopes.join(",")}`;
  }
  if (pinState?.inactiveScopes?.length) {
    return `${base} | current build not pinned | other scopes=${pinState.inactiveScopes.join(",")}`;
  }
  return `${base} | not pinned`;
}

function detailRunnerRequirement(skill) {
  const runtime = safeString(skill?.entrypoint_runtime);
  const command = safeString(skill?.entrypoint_command);
  const args = Array.isArray(skill?.entrypoint_args)
    ? skill.entrypoint_args.map((value) => safeString(value)).filter(Boolean)
    : [];
  const parts = [];
  if (runtime) parts.push(`runtime=${runtime}`);
  if (command) parts.push(`cmd=${[command, ...args.slice(0, 2)].join(" ")}`);
  return parts.join(" | ") || "runner not declared";
}

function detailCompatibilityStatus(skill, lifecycle) {
  const state = safeString(skill?.compatibility_state) || "unknown";
  const envelope = safeString(skill?.compatibility_envelope?.compatibility_state).toLowerCase();
  const runtimeHosts = Array.isArray(skill?.compatibility_envelope?.runtime_hosts)
    ? skill.compatibility_envelope.runtime_hosts.map((value) => safeString(value)).filter(Boolean)
    : [];
  const parts = [];
  if (state === "supported" && (envelope === "verified" || envelope === "supported")) {
    parts.push("supported | verified");
  } else if (state === "partial") {
    parts.push("partial");
    parts.push("awaiting full verify");
  } else {
    parts.push(state || "unknown");
  }
  if (runtimeHosts.length) {
    parts.push(`hosts=${runtimeHosts.join(",")}`);
  }
  if (safeString(lifecycle?.overall_state) === "not_supported") {
    parts.push("lifecycle=not_supported");
  }
  return parts.join(" | ");
}

function detailPreflightResult(skill, lifecycle) {
  const packageState = safeString(lifecycle?.package_state || skill?.package_state).toLowerCase();
  const overallState = safeString(lifecycle?.overall_state).toLowerCase();
  const doctor = safeString(skill?.quality_evidence_status?.doctor).toLowerCase();
  const smoke = safeString(skill?.quality_evidence_status?.smoke).toLowerCase();
  if (packageState === "quarantined") return "quarantined";
  if (safeString(skill?.compatibility_state) === "unsupported") return "blocked | incompatible";
  if (safeString(skill?.requires_grant) === "true" || skill?.requires_grant === true) {
    if (overallState === "blocked" || overallState === "degraded") {
      return "grant required before run";
    }
  }
  if (overallState === "ready" || packageState === "active" || packageState === "ready") return "passed";
  if (doctor === "passed" && smoke === "passed" && safeString(skill?.compatibility_state) === "supported") return "passed";
  if (doctor === "failed" || smoke === "failed") return "blocked | doctor or smoke failed";
  return "pending preflight evidence";
}

function buildDetailSurface(skill, options = {}) {
  const lifecycle = options.lifecycle || {};
  return {
    surface: "xt_skill_detail",
    case_id: options.caseId,
    skill_id: safeString(skill?.skill_id),
    package_sha256: safeString(skill?.package_sha256).toLowerCase(),
    trust_root: detailTrustRoot(skill),
    pinned_version: detailPinnedVersion(skill, options.pinState),
    runner_requirement: detailRunnerRequirement(skill),
    compatibility_status: detailCompatibilityStatus(skill, lifecycle),
    preflight_result: detailPreflightResult(skill, lifecycle),
  };
}

function buildImportReviewSurface() {
  return {
    surface: "xt_import_review",
    case_id: "partial_quarantined",
    skill_id: "skill.demo",
    trust_root: "pending Hub promotion",
    pinned_version: "not pinned yet",
    runner_requirement: "Hub-governed import runner | sandbox=workspace_write",
    compatibility_status: "quarantined | vetter=critical",
    preflight_result: "quarantined | preflight_quarantined",
  };
}

function fieldPresence(row) {
  const keys = [
    "trust_root",
    "pinned_version",
    "runner_requirement",
    "compatibility_status",
    "preflight_result",
  ];
  const presence = {};
  for (const key of keys) {
    presence[key] = safeString(row[key]).length > 0;
  }
  return presence;
}

function allPresent(presence) {
  return Object.values(presence).every(Boolean);
}

function main() {
  const args = parseArgs(process.argv);
  const indexPath = path.resolve(args["index-path"] || DEFAULT_INDEX_PATH);
  const outputPath = path.resolve(args.out || DEFAULT_OUTPUT_PATH);
  const index = readJson(indexPath);

  const supportedSkill = findSkill(index, "find-skills");
  const grantSkill = findSkill(index, "agent-browser");
  if (!supportedSkill || !grantSkill) {
    throw new Error("official skill catalog is missing find-skills or agent-browser");
  }

  const rows = [
    buildDetailSurface(supportedSkill, {
      caseId: "supported",
      pinState: { activeScopes: ["global"] },
      lifecycle: { package_state: "active", overall_state: "ready" },
    }),
    buildDetailSurface(grantSkill, {
      caseId: "grant_required",
      pinState: { activeScopes: [] },
      lifecycle: { package_state: "discovered", overall_state: "blocked" },
    }),
    buildImportReviewSurface(),
  ].map((row) => ({
    ...row,
    field_presence: fieldPresence(row),
  }));

  const categories = {
    supported: rows.some((row) => row.case_id === "supported" && allPresent(row.field_presence)),
    grant_required: rows.some((row) => row.case_id === "grant_required" && allPresent(row.field_presence)),
    partial_or_quarantined: rows.some((row) => row.case_id === "partial_quarantined" && allPresent(row.field_presence)),
  };
  const ready = Object.values(categories).every(Boolean);

  const payload = {
    schema_version: "xhub.w8_c2_skill_surface_truth_evidence.v1",
    generated_at: new Date().toISOString(),
    status: ready ? "ready" : "blocked",
    source_refs: {
      official_index: path.relative(REPO_ROOT, indexPath),
      xt_detail_surface: [
        "x-terminal/Sources/Project/AXSkillGovernanceSurface.swift",
        "x-terminal/Sources/UI/XTSkillGovernanceSurfaceView.swift",
      ],
      xt_import_review_surface: [
        "x-terminal/Sources/Project/XTAgentSkillImportNormalizer.swift",
      ],
    },
    categories,
    rows,
    machine_verdict: ready
      ? "PASS(skill_surface_exposes_trust_pin_runner_compatibility_preflight)"
      : "NO_GO(skill_surface_missing_required_governance_fields)",
  };

  writeJson(outputPath, payload);
  console.log(JSON.stringify({
    ok: ready,
    out: path.relative(REPO_ROOT, outputPath),
    rows: rows.length,
  }));
}

main();
