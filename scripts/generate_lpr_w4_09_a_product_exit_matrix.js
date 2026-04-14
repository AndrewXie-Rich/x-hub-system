#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..");
const defaultOutputPath = path.join(
  repoRoot,
  "build/reports/lpr_w4_09_a_product_exit_evidence.v1.json"
);
const defaultMLXTextPath = path.join(
  repoRoot,
  "build/reports/lpr_w4_09_a_mlx_text_require_real_evidence.v1.json"
);
const defaultMLXVLMPath = path.join(
  repoRoot,
  "build/reports/lpr_w4_07_b_mlx_vlm_require_real_evidence.v1.json"
);
const defaultTransformersPath = path.join(
  repoRoot,
  "build/reports/lpr_w3_03_a_require_real_evidence.v1.json"
);
const defaultGGUFPath = path.join(
  repoRoot,
  "build/reports/lpr_w4_08_b_gguf_require_real_evidence.v1.json"
);

function isoNow() {
  return new Date().toISOString();
}

function normalizeString(value, fallback = "") {
  const trimmed = String(value ?? "").trim();
  return trimmed || fallback;
}

function normalizeArray(value) {
  return Array.isArray(value) ? value : [];
}

function normalizeObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function writeJSON(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function readJSONIfExists(filePath) {
  try {
    if (!filePath || !fs.existsSync(filePath)) return null;
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return null;
  }
}

function relPath(targetPath) {
  const normalized = normalizeString(targetPath);
  if (!normalized) return "";
  if (!path.isAbsolute(normalized)) return normalized.split(path.sep).join("/");
  if (!normalized.startsWith(repoRoot)) return normalized;
  return path.relative(repoRoot, normalized).split(path.sep).join("/");
}

function uniqueStrings(values = []) {
  const seen = new Set();
  const out = [];
  for (const value of values) {
    const normalized = normalizeString(value);
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);
    out.push(normalized);
  }
  return out;
}

function printUsage(exitCode) {
  const message = [
    "usage:",
    "  node scripts/generate_lpr_w4_09_a_product_exit_matrix.js",
    "options:",
    "  --mlx-text-report <path>",
    "  --mlx-vlm-report <path>",
    "  --transformers-report <path>",
    "  --gguf-report <path>",
    "  --out <path>",
    "",
  ].join("\n");
  if (exitCode === 0) process.stdout.write(message);
  else process.stderr.write(message);
  process.exit(exitCode);
}

function parseArgs(argv) {
  const options = {
    mlxTextReportPath: defaultMLXTextPath,
    mlxVLMReportPath: defaultMLXVLMPath,
    transformersReportPath: defaultTransformersPath,
    ggufReportPath: defaultGGUFPath,
    outputPath: defaultOutputPath,
  };

  for (let i = 2; i < argv.length; i += 1) {
    const token = normalizeString(argv[i]);
    switch (token) {
      case "--mlx-text-report":
        options.mlxTextReportPath = path.resolve(normalizeString(argv[++i]));
        break;
      case "--mlx-vlm-report":
        options.mlxVLMReportPath = path.resolve(normalizeString(argv[++i]));
        break;
      case "--transformers-report":
        options.transformersReportPath = path.resolve(normalizeString(argv[++i]));
        break;
      case "--gguf-report":
        options.ggufReportPath = path.resolve(normalizeString(argv[++i]));
        break;
      case "--out":
        options.outputPath = path.resolve(normalizeString(argv[++i]));
        break;
      case "--help":
      case "-h":
        printUsage(0);
        break;
      default:
        throw new Error(`unknown arg: ${token}`);
    }
  }

  return options;
}

function classifyReportReady(report) {
  const normalizedReport = normalizeObject(report);
  const status = normalizeString(normalizedReport.status);
  const machineDecision = normalizeObject(normalizedReport.machine_decision);
  const gateVerdict = normalizeString(
    normalizedReport.gate_verdict || machineDecision.gate_verdict
  );
  const requireRealComplete = machineDecision.require_real_evidence_complete === true
    || machineDecision.all_samples_passed === true
    || normalizeString(normalizedReport.release_stance) === "candidate_go";
  const primaryBlocker = normalizeString(
    machineDecision.primary_blocker_reason_code
  );

  if (/^PASS\(/.test(status) || /^PASS\(/.test(gateVerdict) || requireRealComplete) {
    return {
      ready: true,
      reason_code: "",
      summary: status || gateVerdict || "report_passed",
    };
  }

  return {
    ready: false,
    reason_code: primaryBlocker || status || gateVerdict || "report_not_ready",
    summary: status || gateVerdict || "report_not_ready",
  };
}

function buildMatrixCell(cellId, label, reportPath, report) {
  const artifactPresent = !!((reportPath && fs.existsSync(reportPath)) || report);
  if (!artifactPresent) {
    return {
      cell_id: cellId,
      label,
      artifact_path: relPath(reportPath),
      artifact_present: false,
      ready: false,
      reason_code: "artifact_missing",
      summary: `${label} evidence artifact is missing.`,
      source_status: "",
      source_gate_verdict: "",
    };
  }

  const readiness = classifyReportReady(report);
  const normalizedReport = normalizeObject(report);
  return {
    cell_id: cellId,
    label,
    artifact_path: relPath(reportPath),
    artifact_present: true,
    ready: readiness.ready,
    reason_code: readiness.reason_code,
    summary: readiness.summary,
    source_status: normalizeString(normalizedReport.status || normalizedReport.release_stance),
    source_gate_verdict: normalizeString(
      normalizedReport.gate_verdict || normalizeObject(normalizedReport.machine_decision).gate_verdict
    ),
  };
}

function buildProductExitMatrixReport(input = {}) {
  const generatedAt = normalizeString(input.generatedAt, isoNow());
  const cells = [
    buildMatrixCell("mlx_text", "MLX text", input.mlxTextReportPath, input.mlxTextReport),
    buildMatrixCell("mlx_vlm", "MLX VLM", input.mlxVLMReportPath, input.mlxVLMReport),
    buildMatrixCell("transformers_embed_asr", "Transformers embed+ASR", input.transformersReportPath, input.transformersReport),
    buildMatrixCell("gguf", "GGUF / llama.cpp", input.ggufReportPath, input.ggufReport),
  ];

  const readyCellIds = cells.filter((cell) => cell.ready).map((cell) => cell.cell_id);
  const missingCellIds = cells.filter((cell) => !cell.artifact_present).map((cell) => cell.cell_id);
  const failingCellIds = cells
    .filter((cell) => cell.artifact_present && !cell.ready)
    .map((cell) => cell.cell_id);

  const blockers = uniqueStrings([
    ...cells.filter((cell) => !cell.artifact_present).map((cell) => `${cell.cell_id}:artifact_missing`),
    ...cells.filter((cell) => cell.artifact_present && !cell.ready).map((cell) => `${cell.cell_id}:${cell.reason_code}`),
  ]);
  const pass = blockers.length === 0;

  return {
    schema_version: "xhub.lpr_w4_09_a_product_exit_matrix.v1",
    generated_at: generatedAt,
    work_order: "LPR-W4-09-A",
    status: pass
      ? "PASS(product_exit_matrix_ready)"
      : "FAIL(product_exit_matrix_incomplete)",
    summary: {
      ready_cell_count: readyCellIds.length,
      total_cell_count: cells.length,
      ready_cell_ids: readyCellIds,
      missing_cell_ids: missingCellIds,
      failing_cell_ids: failingCellIds,
    },
    machine_decision: {
      gate_verdict: pass
        ? "PASS(product_exit_matrix_ready)"
        : "NO_GO(product_exit_matrix_incomplete)",
      product_exit_ready: pass,
      current_blockers: blockers,
      ready_cell_ids: readyCellIds,
      missing_cell_ids: missingCellIds,
      failing_cell_ids: failingCellIds,
    },
    cells,
    next_required_artifacts: uniqueStrings(
      cells
        .filter((cell) => !cell.ready)
        .map((cell) => `${cell.label}: ${cell.artifact_present ? cell.reason_code : cell.artifact_path}`)
    ),
  };
}

function main() {
  const options = parseArgs(process.argv);
  const report = buildProductExitMatrixReport({
    generatedAt: isoNow(),
    mlxTextReportPath: options.mlxTextReportPath,
    mlxVLMReportPath: options.mlxVLMReportPath,
    transformersReportPath: options.transformersReportPath,
    ggufReportPath: options.ggufReportPath,
    mlxTextReport: readJSONIfExists(options.mlxTextReportPath),
    mlxVLMReport: readJSONIfExists(options.mlxVLMReportPath),
    transformersReport: readJSONIfExists(options.transformersReportPath),
    ggufReport: readJSONIfExists(options.ggufReportPath),
  });
  writeJSON(options.outputPath, report);
  process.stdout.write(`${options.outputPath}\n`);
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${String(error && error.message ? error.message : error)}\n`);
    process.exit(1);
  }
}

module.exports = {
  buildProductExitMatrixReport,
  classifyReportReady,
};
