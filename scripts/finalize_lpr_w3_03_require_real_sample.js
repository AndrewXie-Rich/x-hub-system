#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");

const {
  readCaptureBundle,
  resolveBundlePath,
  resolveRequireRealEvidencePath,
  writeJSON: writeBundleJSON,
} = require("./lpr_w3_03_require_real_bundle_lib.js");
const {
  buildRequireRealEvidence,
  writeJSON: writeReportJSON,
} = require("./generate_lpr_w3_03_a_require_real_evidence.js");
const {
  applyFromJSONArgs,
  applyEvidenceDirArgs,
  applyScaffoldDirArgs,
  readJSON,
  relativeOrAbsolute,
  updateBundle,
} = require("./update_lpr_w3_03_require_real_capture_bundle.js");
const {
  buildSummary,
  findFocusSample,
} = require("./lpr_w3_03_require_real_status.js");

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
    noteFile: "",
    fromJson: "",
    setFields: {},
    reportsDir: "",
    bundlePath: "",
    reportPath: "",
    skipRegenerateReport: false,
    json: false,
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
      case "--note-file":
        out.noteFile = String(argv[++i] || "").trim();
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
      case "--reports-dir":
        out.reportsDir = String(argv[++i] || "").trim();
        break;
      case "--bundle-path":
        out.bundlePath = String(argv[++i] || "").trim();
        break;
      case "--report-path":
        out.reportPath = String(argv[++i] || "").trim();
        break;
      case "--skip-regenerate-report":
        out.skipRegenerateReport = true;
        break;
      case "--json":
        out.json = true;
        break;
      case "--help":
      case "-h":
        printUsage(0);
        break;
      default:
        throw new Error(`unknown arg: ${token}`);
    }
  }

  if (!out.sampleId && !out.scaffoldDir) {
    throw new Error("--sample-id or --scaffold-dir is required");
  }
  return out;
}

function printUsage(exitCode) {
  const message = [
    "usage:",
    "  node scripts/finalize_lpr_w3_03_require_real_sample.js \\",
    "    --scaffold-dir build/reports/lpr_w3_03_require_real/lpr_rr_01_embedding_real_model_dir_executes",
    "",
    "defaults:",
    "  - status=passed",
    "  - success=true",
    "  - performed_at=now",
    "  - note-file=<scaffold-dir>/completion_notes.txt",
    "  - regenerate report after bundle update",
    "",
  ].join("\n");
  if (exitCode === 0) process.stdout.write(message);
  else process.stderr.write(message);
  process.exit(exitCode);
}

function resolveDefaultNotePath(args) {
  if (args.noteFile) {
    return path.resolve(args.noteFile);
  }
  if (args.scaffoldDir) {
    return path.join(path.resolve(args.scaffoldDir), "completion_notes.txt");
  }
  return "";
}

function readOperatorNoteFromFile(filePath) {
  if (!filePath || !fs.existsSync(filePath)) {
    return "";
  }
  const lines = fs.readFileSync(filePath, "utf8")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith("#"));
  return lines.join("\n").trim();
}

function normalizeFinalizeIntent(args) {
  const explicitStatus = String(args.status || "").trim().toLowerCase();
  let success = args.success === undefined ? null : args.success;
  if (success === null) {
    if (!explicitStatus || explicitStatus === "passed") success = true;
    else if (explicitStatus === "failed") success = false;
  }
  return {
    status: explicitStatus || (success === false ? "failed" : "passed"),
    success,
  };
}

function buildUpdateArgs(args) {
  const notePath = resolveDefaultNotePath(args);
  const operatorNote = args.operatorNote || readOperatorNoteFromFile(notePath);
  const normalized = normalizeFinalizeIntent(args);
  let updateArgs = {
    sampleId: args.sampleId,
    scaffoldDir: args.scaffoldDir,
    evidenceDir: args.evidenceDir,
    status: normalized.status,
    success: normalized.success,
    performedAt: args.performedAt,
    evidenceRefs: Array.isArray(args.evidenceRefs) ? args.evidenceRefs.slice() : [],
    operatorNote,
    fromJson: args.fromJson,
    setFields: { ...(args.setFields || {}) },
  };

  updateArgs = applyScaffoldDirArgs(updateArgs);
  updateArgs = applyEvidenceDirArgs(updateArgs);
  if (updateArgs.fromJson) {
    const fromJsonPath = path.resolve(updateArgs.fromJson);
    if (!fs.existsSync(fromJsonPath)) {
      throw new Error(`--from-json file not found: ${fromJsonPath}`);
    }
    updateArgs = applyFromJSONArgs(updateArgs, readJSON(fromJsonPath));
  }

  return {
    notePath,
    operatorNote,
    updateArgs,
  };
}

function summarizeResult(bundle, report) {
  const samples = Array.isArray(bundle.samples) ? bundle.samples : [];
  const focusSample = findFocusSample(samples, "");
  return buildSummary(bundle, report, focusSample, false);
}

function finalizeSample(args, nowIso = new Date().toISOString()) {
  const options = {};
  if (args.reportsDir) options.reportsDir = args.reportsDir;
  if (args.bundlePath) options.bundlePath = args.bundlePath;
  if (args.reportPath) options.reportPath = args.reportPath;

  const { notePath, operatorNote, updateArgs } = buildUpdateArgs(args);
  const bundle = readCaptureBundle(options);
  const { bundle: updatedBundle, sample } = updateBundle(bundle, updateArgs, nowIso);

  const resolvedBundlePath = resolveBundlePath(options);
  writeBundleJSON(resolvedBundlePath, updatedBundle);

  let report = null;
  if (!args.skipRegenerateReport) {
    report = buildRequireRealEvidence(updatedBundle, options);
    writeReportJSON(resolveRequireRealEvidencePath(options), report);
  }

  const summary = summarizeResult(updatedBundle, report);
  return {
    ok: true,
    sample_id: sample.sample_id,
    status: sample.status,
    success_boolean: sample.success_boolean,
    performed_at: sample.performed_at || "",
    evidence_ref_count: Array.isArray(sample.evidence_refs) ? sample.evidence_refs.length : 0,
    operator_note_source: operatorNote ? relativeOrAbsolute(notePath || "") : "",
    bundle_path: relativeOrAbsolute(resolvedBundlePath),
    report_path: args.skipRegenerateReport ? "" : relativeOrAbsolute(resolveRequireRealEvidencePath(options)),
    qa_gate_verdict: summary.qa_gate_verdict,
    qa_release_stance: summary.qa_release_stance,
    next_pending_sample_id: summary.next_pending_sample_id,
  };
}

function main() {
  try {
    const args = parseArgs(process.argv);
    const output = finalizeSample(args);
    if (args.json) {
      process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
      return;
    }

    const lines = [
      `sample_id: ${output.sample_id}`,
      `status: ${output.status}`,
      `success_boolean: ${output.success_boolean}`,
      `performed_at: ${output.performed_at}`,
      `evidence_ref_count: ${output.evidence_ref_count}`,
      `bundle_path: ${output.bundle_path}`,
      `report_path: ${output.report_path}`,
      `qa_gate_verdict: ${output.qa_gate_verdict}`,
      `qa_release_stance: ${output.qa_release_stance}`,
      `next_pending_sample_id: ${output.next_pending_sample_id}`,
    ];
    if (output.operator_note_source) {
      lines.push(`operator_note_source: ${output.operator_note_source}`);
    }
    process.stdout.write(`${lines.join("\n")}\n`);
  } catch (error) {
    process.stderr.write(`${String(error.message || error)}\n`);
    printUsage(1);
  }
}

module.exports = {
  buildUpdateArgs,
  finalizeSample,
  normalizeFinalizeIntent,
  parseArgs,
  readOperatorNoteFromFile,
  resolveDefaultNotePath,
};

if (require.main === module) {
  main();
}
