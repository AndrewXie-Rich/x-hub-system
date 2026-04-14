#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");

const {
  readCaptureBundle,
  resolveReportsDir,
  resolveRequireRealEvidencePath,
  writeJSON,
} = require("./lpr_w3_03_require_real_bundle_lib.js");
const {
  buildSummary,
  findFocusSample,
  readJSON,
} = require("./lpr_w3_03_require_real_status.js");

function readJSONIfExists(filePath) {
  try {
    if (!fs.existsSync(filePath)) return null;
    return readJSON(filePath);
  } catch {
    return null;
  }
}

function parseArgs(argv) {
  const out = {
    outJson: path.join(resolveReportsDir(), "lpr_w3_03_sample1_operator_handoff.v1.json"),
  };

  for (let i = 2; i < argv.length; i += 1) {
    const token = String(argv[i] || "").trim();
    switch (token) {
      case "--out-json":
        out.outJson = path.resolve(String(argv[++i] || "").trim());
        break;
      case "--help":
      case "-h":
        printUsage(0);
        break;
      default:
        throw new Error(`unknown arg: ${token}`);
    }
  }
  return out;
}

function printUsage(exitCode) {
  const message = [
    "usage:",
    "  node scripts/generate_lpr_w3_03_sample1_operator_handoff.js",
    "  node scripts/generate_lpr_w3_03_sample1_operator_handoff.js --out-json build/reports/lpr_w3_03_sample1_operator_handoff.v1.json",
    "",
  ].join("\n");
  if (exitCode === 0) process.stdout.write(message);
  else process.stderr.write(message);
  process.exit(exitCode);
}

function main() {
  try {
    const args = parseArgs(process.argv);
    const bundle = readCaptureBundle();
    const qa = readJSONIfExists(resolveRequireRealEvidencePath());
    const samples = Array.isArray(bundle.samples) ? bundle.samples : [];
    const sample1 = findFocusSample(samples, "lpr_rr_01_embedding_real_model_dir_executes");
    const summary = buildSummary(bundle, qa, sample1, false);
    writeJSON(args.outJson, summary.sample1_operator_handoff || {});
    process.stdout.write(`${args.outJson}\n`);
  } catch (error) {
    process.stderr.write(`${String(error.message || error)}\n`);
    printUsage(1);
  }
}

if (require.main === module) {
  main();
}
