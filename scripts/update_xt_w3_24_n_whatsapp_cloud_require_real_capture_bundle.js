#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");
const {
  bundlePath,
  readCaptureBundle,
  writeJSON: writeBundleJSON,
} = require("./xt_w3_24_n_whatsapp_cloud_require_real_bundle_lib.js");
const {
  evaluateCheck,
  syntheticEvidenceReasons,
} = require("./generate_xt_w3_24_n_whatsapp_cloud_require_real_report.js");

const repoRoot = path.resolve(__dirname, "..");

function readJSON(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJSON(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function parseArgs(argv) {
  const out = {
    sampleId: "",
    scaffoldDir: "",
    evidenceDir: "",
    status: "",
    success: null,
    performedAt: "",
    evidenceRefs: [],
    operatorNote: "",
    fromJson: "",
    setFields: {},
  };

  for (let i = 2; i < argv.length; i += 1) {
    const token = String(argv[i] || "").trim();
    switch (token) {
      case "--sample-id":
        out.sampleId = String(argv[++i] || "").trim();
        break;
      case "--scaffold-dir":
        out.scaffoldDir = String(argv[++i] || "").trim();
        break;
      case "--evidence-dir":
        out.evidenceDir = String(argv[++i] || "").trim();
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
      case "--from-json":
        out.fromJson = String(argv[++i] || "").trim();
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

  if (!out.sampleId && !out.scaffoldDir) {
    throw new Error("--sample-id is required");
  }
  return out;
}

function normalizeFromJSONPayload(payload) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    throw new Error("--from-json payload must be a JSON object");
  }
  if (payload.machine_readable_template && typeof payload.machine_readable_template === "object" && !Array.isArray(payload.machine_readable_template)) {
    return payload.machine_readable_template;
  }
  if (payload.fields && typeof payload.fields === "object" && !Array.isArray(payload.fields)) {
    return payload.fields;
  }
  return payload;
}

function applyFromJSONArgs(args, payload) {
  const normalized = normalizeFromJSONPayload(payload);
  return {
    ...args,
    setFields: {
      ...normalized,
      ...args.setFields,
    },
  };
}

function relativeOrAbsolute(targetPath) {
  const relative = path.relative(repoRoot, targetPath);
  if (!relative.startsWith("..") && !path.isAbsolute(relative)) {
    return relative || ".";
  }
  return targetPath;
}

function coerceValue(raw) {
  if (raw === null || raw === undefined) return raw;
  if (typeof raw === "boolean" || typeof raw === "number") return raw;
  if (Array.isArray(raw)) return raw;
  if (typeof raw === "object") return raw;
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

function collectEvidenceRefsFromDir(evidenceDir) {
  const root = path.resolve(evidenceDir);
  if (!fs.existsSync(root)) {
    throw new Error(`evidence dir not found: ${root}`);
  }
  if (!fs.statSync(root).isDirectory()) {
    throw new Error(`evidence dir is not a directory: ${root}`);
  }

  const metadataBasenames = new Set([
    ".DS_Store",
    "README.md",
    "completion_notes.txt",
    "finalize_sample.command.txt",
    "sample_manifest.v1.json",
    "machine_readable_template.v1.json",
    "update_bundle.command.txt",
  ]);
  const refs = [];

  function walk(currentDir) {
    const entries = fs.readdirSync(currentDir, { withFileTypes: true })
      .sort((lhs, rhs) => lhs.name.localeCompare(rhs.name));
    for (const entry of entries) {
      const fullPath = path.join(currentDir, entry.name);
      if (entry.isDirectory()) {
        if (entry.name.startsWith(".")) {
          continue;
        }
        walk(fullPath);
        continue;
      }
      if (entry.name.startsWith(".") || metadataBasenames.has(entry.name)) {
        continue;
      }
      refs.push(relativeOrAbsolute(fullPath));
    }
  }

  walk(root);
  return refs;
}

function applyEvidenceDirArgs(args) {
  if (!args.evidenceDir) return args;
  return {
    ...args,
    evidenceRefs: dedupeStrings([
      ...args.evidenceRefs,
      ...collectEvidenceRefsFromDir(args.evidenceDir),
    ]),
  };
}

function applyScaffoldDirArgs(args) {
  if (!args.scaffoldDir) return args;

  const scaffoldDir = path.resolve(args.scaffoldDir);
  if (!fs.existsSync(scaffoldDir)) {
    throw new Error(`--scaffold-dir not found: ${scaffoldDir}`);
  }
  if (!fs.statSync(scaffoldDir).isDirectory()) {
    throw new Error(`--scaffold-dir is not a directory: ${scaffoldDir}`);
  }

  const manifestPath = path.join(scaffoldDir, "sample_manifest.v1.json");
  const templatePath = path.join(scaffoldDir, "machine_readable_template.v1.json");
  if (!fs.existsSync(manifestPath)) {
    throw new Error(`sample manifest not found in scaffold dir: ${manifestPath}`);
  }

  const manifest = readJSON(manifestPath);
  const next = {
    ...args,
    sampleId: args.sampleId || String(manifest.sample_id || "").trim(),
    fromJson: args.fromJson || (fs.existsSync(templatePath) ? templatePath : ""),
    evidenceDir: args.evidenceDir || scaffoldDir,
  };
  if (!next.sampleId) {
    throw new Error(`sample_id missing in scaffold manifest: ${manifestPath}`);
  }
  return applyEvidenceDirArgs(next);
}

function getByPath(value, dottedPath) {
  const parts = String(dottedPath || "").split(".").filter(Boolean);
  let current = value;
  for (const part of parts) {
    if (current === null || current === undefined) return undefined;
    current = current[part];
  }
  return current;
}

function hasRecordedValue(value) {
  if (value === null || value === undefined) return false;
  if (typeof value === "string") return value.trim() !== "";
  if (typeof value === "number") return Number.isFinite(value);
  if (typeof value === "boolean") return true;
  if (Array.isArray(value)) return true;
  if (typeof value === "object") return true;
  return false;
}

function hasPlaceholderValue(value) {
  if (typeof value === "string") {
    return /^<[^>\n]+>$/.test(value.trim());
  }
  if (Array.isArray(value)) {
    return value.some((entry) => hasPlaceholderValue(entry));
  }
  if (value && typeof value === "object") {
    return Object.values(value).some((entry) => hasPlaceholderValue(entry));
  }
  return false;
}

function validatePassedSample(sample) {
  const errors = [];
  if (typeof sample.performed_at !== "string" || sample.performed_at.trim() === "") {
    errors.push("performed_at_missing_for_passed_sample");
  }
  if (!Array.isArray(sample.evidence_refs) || sample.evidence_refs.length === 0) {
    errors.push("evidence_refs_missing_for_passed_sample");
  }

  const recordedFields = Array.isArray(sample.machine_readable_fields_to_record)
    ? sample.machine_readable_fields_to_record
    : [];
  for (const field of recordedFields) {
    const key = String(field || "").trim();
    if (!key) continue;
    const fieldValue = getByPath(sample, key);
    if (!hasRecordedValue(fieldValue)) {
      errors.push(`machine_readable_field_missing:${key}`);
      continue;
    }
    if (hasPlaceholderValue(fieldValue)) {
      errors.push(`machine_readable_field_placeholder:${key}`);
    }
  }

  const syntheticReasons = syntheticEvidenceReasons(sample);
  if (syntheticReasons.length > 0) {
    errors.push(...syntheticReasons.map((reason) => `synthetic_runtime_evidence_not_accepted:${reason}`));
  }

  const requiredChecks = Array.isArray(sample.required_checks) ? sample.required_checks : [];
  for (const check of requiredChecks) {
    const message = evaluateCheck(sample, check);
    if (message) {
      errors.push(`required_check_failed:${message}`);
    }
  }

  return errors;
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

  if (sample.status === "passed" || sample.success_boolean === true) {
    const validationErrors = validatePassedSample(sample);
    if (validationErrors.length > 0) {
      throw new Error(`passed sample validation failed: ${validationErrors.join("; ")}`);
    }
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
      "  node scripts/update_xt_w3_24_n_whatsapp_cloud_require_real_capture_bundle.js \\",
      "    --scaffold-dir build/reports/xt_w3_24_n_whatsapp_cloud_require_real/xt_w3_24_n_rr_03_deploy_plan_routes_project_first_to_preferred_xt \\",
      "    --status passed --success true \\",
      "    --note <operator_notes>",
      "",
    ].join("\n")
  );
}

function main() {
  try {
    let args = parseArgs(process.argv);
    args = applyScaffoldDirArgs(args);
    args = applyEvidenceDirArgs(args);
    if (args.fromJson) {
      const fromJsonPath = path.resolve(args.fromJson);
      if (!fs.existsSync(fromJsonPath)) {
        throw new Error(`--from-json file not found: ${fromJsonPath}`);
      }
      args = applyFromJSONArgs(args, readJSON(fromJsonPath));
    }
    const bundle = readCaptureBundle();
    const { bundle: updated, sample } = updateBundle(bundle, args);
    writeBundleJSON(bundlePath, updated);
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
  applyFromJSONArgs,
  applyEvidenceDirArgs,
  applyScaffoldDirArgs,
  bundlePath,
  collectEvidenceRefsFromDir,
  coerceValue,
  getByPath,
  hasPlaceholderValue,
  hasRecordedValue,
  normalizeFromJSONPayload,
  normalizeStatus,
  parseArgs,
  readJSON,
  relativeOrAbsolute,
  updateBundle,
  validatePassedSample,
  writeJSON,
};

if (require.main === module) {
  main();
}
