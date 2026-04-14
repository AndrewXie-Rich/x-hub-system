#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");

const {
  buildProductExitMatrixReport,
  classifyReportReady,
} = require("./generate_lpr_w4_09_a_product_exit_matrix.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

run("report readiness accepts PASS status and require-real completion", () => {
  const readiness = classifyReportReady({
    status: "PASS(gguf_require_real_closure_ready)",
    machine_decision: {
      gate_verdict: "PASS(gguf_require_real_closure_ready)",
      require_real_evidence_complete: true,
    },
  });

  assert.equal(readiness.ready, true);
  assert.equal(readiness.reason_code, "");
});

run("product exit matrix fails closed when upstream artifacts are missing", () => {
  const report = buildProductExitMatrixReport({
    generatedAt: "2026-03-26T07:35:00Z",
    mlxTextReportPath: "/reports/mlx_text.json",
    mlxVLMReportPath: "/reports/mlx_vlm.json",
    transformersReportPath: "/reports/transformers.json",
    ggufReportPath: "/reports/gguf.json",
    mlxTextReport: null,
    mlxVLMReport: {
      status: "PASS(mlx_vlm_require_real_closure_ready)",
      machine_decision: {
        gate_verdict: "PASS(mlx_vlm_require_real_closure_ready)",
        require_real_evidence_complete: true,
      },
    },
    transformersReport: null,
    ggufReport: {
      status: "PASS(gguf_require_real_closure_ready)",
      machine_decision: {
        gate_verdict: "PASS(gguf_require_real_closure_ready)",
        require_real_evidence_complete: true,
      },
    },
  });

  assert.equal(report.status, "FAIL(product_exit_matrix_incomplete)");
  assert.ok(report.machine_decision.current_blockers.includes("mlx_text:artifact_missing"));
  assert.ok(report.machine_decision.current_blockers.includes("transformers_embed_asr:artifact_missing"));
});

run("product exit matrix turns green only when all four real-machine cells are ready", () => {
  const readyReport = {
    status: "PASS(require_real_ready)",
    machine_decision: {
      gate_verdict: "PASS(require_real_ready)",
      require_real_evidence_complete: true,
    },
  };
  const report = buildProductExitMatrixReport({
    generatedAt: "2026-03-26T07:35:00Z",
    mlxTextReportPath: "build/reports/mlx_text.json",
    mlxVLMReportPath: "build/reports/mlx_vlm.json",
    transformersReportPath: "build/reports/transformers.json",
    ggufReportPath: "build/reports/gguf.json",
    mlxTextReport: readyReport,
    mlxVLMReport: readyReport,
    transformersReport: readyReport,
    ggufReport: readyReport,
  });

  assert.equal(report.status, "PASS(product_exit_matrix_ready)");
  assert.equal(report.machine_decision.product_exit_ready, true);
  assert.deepEqual(report.machine_decision.current_blockers, []);
  assert.deepEqual(report.summary.ready_cell_ids, [
    "mlx_text",
    "mlx_vlm",
    "transformers_embed_asr",
    "gguf",
  ]);
});
