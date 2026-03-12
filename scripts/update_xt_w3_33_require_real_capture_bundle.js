#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..");
const bundlePath = path.join(repoRoot, "build/reports/xt_w3_33_h_require_real_capture_bundle.v1.json");

function readJSON(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJSON(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function parseArgs(argv) {
  const out = {
    sampleId: "",
    status: "",
    success: null,
    performedAt: "",
    evidenceRefs: [],
    operatorNote: "",
    setFields: {},
  };

  for (let i = 2; i < argv.length; i += 1) {
    const token = argv[i];
    switch (token) {
      case "--sample-id":
        out.sampleId = String(argv[++i] || "").trim();
        break;
      case "--status":
        out.status = String(argv[++i] || "").trim();
        break;
      case "--success": {
        const raw = String(argv[++i] || "").trim().toLowerCase();
        if (["true", "1", "yes", "pass", "passed"].includes(raw)) out.success = true;
        else if (["false", "0", "no", "fail", "failed"].includes(raw)) out.success = false;
        else throw new Error(`invalid --success value: ${raw}`);
        break;
      }
      case "--performed-at":
        out.performedAt = String(argv[++i] || "").trim();
        break;
      case "--evidence-ref":
        out.evidenceRefs.push(String(argv[++i] || "").trim());
        break;
      case "--note":
        out.operatorNote = String(argv[++i] || "").trim();
        break;
      case "--set": {
        const pair = String(argv[++i] || "");
        const idx = pair.indexOf("=");
        if (idx <= 0) throw new Error(`invalid --set value: ${pair}`);
        const key = pair.slice(0, idx).trim();
        const value = pair.slice(idx + 1).trim();
        out.setFields[key] = value;
        break;
      }
      default:
        throw new Error(`unknown arg: ${token}`);
    }
  }

  if (!out.sampleId) {
    throw new Error("--sample-id is required");
  }
  return out;
}

function coerceValue(raw) {
  if (raw === "true") return true;
  if (raw === "false") return false;
  if (raw === "null") return null;
  if (/^-?\d+$/.test(raw)) return Number.parseInt(raw, 10);
  if (/^-?\d+\.\d+$/.test(raw)) return Number.parseFloat(raw);
  if ((raw.startsWith("[") && raw.endsWith("]")) || (raw.startsWith("{") && raw.endsWith("}"))) {
    try {
      return JSON.parse(raw);
    } catch {
      return raw;
    }
  }
  return raw;
}

function normalizeStatus(status, success) {
  const token = String(status || "").trim().toLowerCase();
  if (token) return token;
  if (success === true) return "passed";
  if (success === false) return "failed";
  return "pending";
}

function dedupeStrings(values) {
  const seen = new Set();
  const out = [];
  for (const value of values) {
    const trimmed = String(value || "").trim();
    if (!trimmed || seen.has(trimmed)) continue;
    seen.add(trimmed);
    out.push(trimmed);
  }
  return out;
}

function updateBundle(bundle, args, nowIso = new Date().toISOString()) {
  const samples = Array.isArray(bundle.samples) ? bundle.samples.slice() : [];
  const index = samples.findIndex((sample) => String(sample.sample_id || "").trim() === args.sampleId);
  if (index < 0) {
    throw new Error(`sample not found: ${args.sampleId}`);
  }

  const sample = { ...samples[index] };
  sample.status = normalizeStatus(args.status, args.success);
  if (args.performedAt) {
    sample.performed_at = args.performedAt;
  } else if (sample.status !== "pending" && !sample.performed_at) {
    sample.performed_at = nowIso;
  }
  if (args.success !== null) {
    sample.success_boolean = args.success;
  }
  if (args.evidenceRefs.length > 0) {
    sample.evidence_refs = dedupeStrings([...(sample.evidence_refs || []), ...args.evidenceRefs]);
  }
  if (args.operatorNote) {
    sample.operator_notes = args.operatorNote;
  }
  for (const [key, value] of Object.entries(args.setFields)) {
    sample[key] = coerceValue(value);
  }

  samples[index] = sample;
  bundle.samples = samples;
  bundle.status = samples.every((row) => String(row.status || "").trim().toLowerCase() !== "pending")
    ? "executed"
    : "ready_for_execution";
  bundle.updated_at = nowIso;
  return { bundle, sample };
}

function printUsage() {
  process.stderr.write(
    [
      "usage:",
      "  node scripts/update_xt_w3_33_require_real_capture_bundle.js \\",
      "    --sample-id xt_w3_33_rr_03_low_risk_default_proposal_stays_pending \\",
      "    --status passed --success true \\",
      "    --evidence-ref path/to/screenshot.png \\",
      "    --set proposal_generated=true --set approval_state=proposal_pending",
      "",
    ].join("\n")
  );
}

function main() {
  try {
    const args = parseArgs(process.argv);
    const bundle = readJSON(bundlePath);
    const { bundle: updated, sample } = updateBundle(bundle, args);
    writeJSON(bundlePath, updated);
    process.stdout.write(
      `${JSON.stringify({
        ok: true,
        bundle_path: path.relative(repoRoot, bundlePath),
        sample_id: sample.sample_id,
        status: sample.status,
        success_boolean: sample.success_boolean,
        evidence_ref_count: Array.isArray(sample.evidence_refs) ? sample.evidence_refs.length : 0,
      }, null, 2)}\n`
    );
  } catch (error) {
    printUsage();
    process.stderr.write(`${String(error.message || error)}\n`);
    process.exit(1);
  }
}

module.exports = {
  bundlePath,
  coerceValue,
  normalizeStatus,
  parseArgs,
  readJSON,
  updateBundle,
  writeJSON,
};

if (require.main === module) {
  main();
}
