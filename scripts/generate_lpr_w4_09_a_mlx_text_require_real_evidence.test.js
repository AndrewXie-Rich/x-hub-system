#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");

const {
  buildMLXTextRequireRealReport,
  summarizeTextTaskResponse,
} = require("./generate_lpr_w4_09_a_mlx_text_require_real_evidence.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

run("text task response summary requires done event and non-empty output", () => {
  const summary = summarizeTextTaskResponse([
    {
      type: "start",
      req_id: "req-1",
      model_id: "mlx-text-1",
      instance_key: "mlx:mlx-text-1:legacy_runtime",
    },
    {
      type: "delta",
      req_id: "req-1",
      seq: 1,
      text: "legacy path is alive",
    },
    {
      type: "done",
      req_id: "req-1",
      ok: true,
      reason: "eos",
      promptTokens: 7,
      generationTokens: 4,
      generationTPS: 22.5,
      instance_key: "mlx:mlx-text-1:legacy_runtime",
    },
  ]);

  assert.equal(summary.ok, true);
  assert.equal(summary.outputCharCount > 0, true);
  assert.equal(summary.reason, "eos");
  assert.equal(summary.instanceKey, "mlx:mlx-text-1:legacy_runtime");
});

run("mlx text require-real report passes when load task bench and runtime truth align", () => {
  const report = buildMLXTextRequireRealReport({
    generatedAt: "2026-03-27T13:48:00Z",
    modelId: "mlx-text-1",
    modelPath: "/models/Llama-3.2-3B-Instruct-4bit",
    modelExists: true,
    loadResult: {
      ok: true,
      action: "load",
      msg: "ok",
      model_id: "mlx-text-1",
    },
    task: {
      ok: true,
      provider: "mlx",
      taskKind: "text_generate",
      modelId: "mlx-text-1",
      instanceKey: "mlx:mlx-text-1:legacy_runtime",
      reason: "eos",
      outputCharCount: 42,
      outputTextExcerpt: "local mlx text works",
    },
    benchResult: {
      ok: true,
      action: "bench",
      msg: "ok",
      model_id: "mlx-text-1",
    },
    runtimeStatus: {
      updatedAt: 1711547280,
      loadedInstanceCount: 1,
      loadedInstances: [
        {
          instanceKey: "mlx:mlx-text-1:legacy_runtime",
          modelId: "mlx-text-1",
          taskKinds: ["text_generate"],
        },
      ],
      providers: {
        mlx: {
          ok: true,
          lifecycleMode: "mlx_legacy",
          runtimeSource: "user_python_custom",
          availableTaskKinds: ["text_generate"],
          loadedInstances: [
            {
              instanceKey: "mlx:mlx-text-1:legacy_runtime",
              modelId: "mlx-text-1",
              taskKinds: ["text_generate"],
            },
          ],
        },
      },
    },
    modelsBench: {
      results: [
        {
          modelId: "mlx-text-1",
          taskKind: "text_generate",
          resultKind: "legacy_text_bench",
          ok: true,
          throughputValue: 24.3,
          peakMemoryBytes: 3221225472,
        },
      ],
    },
    evidenceRefs: ["build/reports/lpr_w4_09_a_mlx_text_require_real/task_output.json"],
  });

  assert.equal(report.status, "PASS(mlx_text_require_real_closure_ready)");
  assert.equal(report.machine_decision.require_real_evidence_complete, true);
  assert.equal(report.machine_decision.primary_blocker_reason_code, "");
  assert.equal(report.summary.runtime_truth_visible, true);
  assert.equal(report.summary.generation_tps, 24.3);
});

run("mlx text require-real report fails closed when legacy bench row is missing", () => {
  const report = buildMLXTextRequireRealReport({
    generatedAt: "2026-03-27T13:48:00Z",
    modelId: "mlx-text-1",
    modelPath: "/models/Llama-3.2-3B-Instruct-4bit",
    modelExists: true,
    loadResult: {
      ok: true,
      action: "load",
      msg: "ok",
      model_id: "mlx-text-1",
    },
    task: {
      ok: true,
      provider: "mlx",
      taskKind: "text_generate",
      modelId: "mlx-text-1",
      instanceKey: "mlx:mlx-text-1:legacy_runtime",
      reason: "eos",
      outputCharCount: 42,
    },
    benchResult: {
      ok: true,
      action: "bench",
      msg: "ok",
      model_id: "mlx-text-1",
    },
    runtimeStatus: {
      updatedAt: 1711547280,
      loadedInstanceCount: 1,
      loadedInstances: [
        {
          instanceKey: "mlx:mlx-text-1:legacy_runtime",
          modelId: "mlx-text-1",
          taskKinds: ["text_generate"],
        },
      ],
      providers: {
        mlx: {
          ok: true,
          availableTaskKinds: ["text_generate"],
          loadedInstances: [
            {
              instanceKey: "mlx:mlx-text-1:legacy_runtime",
              modelId: "mlx-text-1",
            },
          ],
        },
      },
    },
    modelsBench: {
      results: [],
    },
  });

  assert.equal(report.machine_decision.gate_verdict, "NO_GO(mlx_text_require_real_blocked)");
  assert.equal(report.machine_decision.primary_blocker_reason_code, "legacy_bench_missing");
  assert.ok(
    report.next_required_artifacts.includes(
      "models_bench.json row with resultKind=legacy_text_bench for the selected model"
    )
  );
});
