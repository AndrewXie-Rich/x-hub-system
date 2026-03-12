#!/usr/bin/env node
const fs = require("fs");
const path = require("path");

const repoRoot = path.resolve(__dirname, "..");
const bundlePath = path.join(repoRoot, "build/reports/xt_w3_31_require_real_capture_bundle.v1.json");

function readJSON(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJSON(filePath, value) {
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2) + "\n");
}

function parseArgs(argv) {
  const out = {
    sampleId: "",
    status: "",
    success: null,
    performedAt: "",
    evidenceRefs: [],
    operatorNote: "",
    setFields: {}
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
  if (raw.startsWith("[") || raw.startsWith("{")) {
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
  const out = [];
  const seen = new Set();
  for (const value of values) {
    const trimmed = String(value || "").trim();
    if (!trimmed || seen.has(trimmed)) continue;
    seen.add(trimmed);
    out.push(trimmed);
  }
  return out;
}

function updateBundle(bundle, args) {
  const samples = Array.isArray(bundle.samples) ? bundle.samples : [];
  const index = samples.findIndex((sample) => String(sample.sample_id || "").trim() === args.sampleId);
  if (index < 0) {
    throw new Error(`sample not found: ${args.sampleId}`);
  }

  const sample = { ...samples[index] };
  sample.status = normalizeStatus(args.status, args.success);
  if (args.performedAt) {
    sample.performed_at = args.performedAt;
  } else if (sample.status !== "pending" && !sample.performed_at) {
    sample.performed_at = new Date().toISOString();
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

  const allDone = samples.every((row) => String(row.status || "").trim().toLowerCase() !== "pending");
  bundle.status = allDone ? "executed" : "ready_for_execution";
  bundle.updated_at = new Date().toISOString();
  return { bundle, sample };
}

function printUsage() {
  process.stderr.write(
    [
      "usage:",
      "  node scripts/update_xt_w3_31_require_real_capture_bundle.js \\",
      "    --sample-id xt_spf_rr_01_new_project_visible_within_3s \\",
      "    --status passed --success true \\",
      "    --evidence-ref path/to/screenshot.png \\",
      "    --set project_id=proj_alpha --set first_visible_latency_ms=1800",
      ""
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
      JSON.stringify(
        {
          ok: true,
          bundle_path: path.relative(repoRoot, bundlePath),
          sample_id: sample.sample_id,
          status: sample.status,
          success_boolean: sample.success_boolean,
          evidence_ref_count: Array.isArray(sample.evidence_refs) ? sample.evidence_refs.length : 0
        },
        null,
        2
      ) + "\n"
    );
  } catch (error) {
    printUsage();
    process.stderr.write(`${String(error.message || error)}\n`);
    process.exit(1);
  }
}

main();
