#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");

const {
  buildGGUFRequireRealReport,
  evaluateHelperBridge,
} = require("./generate_lpr_w4_08_b_gguf_require_real_evidence.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

run("helper bridge assessment requires daemon server and http model truth", () => {
  const assessment = evaluateHelperBridge({
    daemonStatus: { status: "running" },
    serverStatus: { running: true, port: 1234 },
    httpModels: [],
    loadedRows: [],
  });

  assert.equal(assessment.helper_ready, false);
  assert.equal(assessment.reason_code, "helper_http_models_unreachable");
});

run("gguf require-real report passes when helper warmup task and monitor truth align", () => {
  const report = buildGGUFRequireRealReport({
    generatedAt: "2026-03-26T06:52:00Z",
    warmup: {
      ok: true,
      provider: "llama.cpp",
      taskKind: "embedding",
      modelId: "nomic-embed-gguf-local",
      modelPath: "/models/nomic-embed.gguf",
      instanceKey: "llama.cpp:nomic-embed-gguf-local:abc123",
    },
    task: {
      ok: true,
      provider: "llama.cpp",
      taskKind: "embedding",
      modelId: "nomic-embed-gguf-local",
      modelPath: "/models/nomic-embed.gguf",
      vectorCount: 1,
      dims: 768,
      instanceKey: "llama.cpp:nomic-embed-gguf-local:abc123",
    },
    taskRequest: {
      provider: "llama.cpp",
      model_id: "nomic-embed-gguf-local",
    },
    helperProbe: {
      daemonStatus: { status: "running", pid: 62130, isDaemon: true },
      serverStatus: { running: true, port: 1234, host: "127.0.0.1" },
      loadedRows: [
        {
          identifier: "llama.cpp:nomic-embed-gguf-local:abc123",
        },
      ],
      httpModels: [
        {
          id: "llama.cpp:nomic-embed-gguf-local:abc123",
        },
      ],
    },
    runtimeStatus: {
      loadedInstanceCount: 1,
      loadedInstances: [
        {
          instanceKey: "llama.cpp:nomic-embed-gguf-local:abc123",
          modelId: "nomic-embed-gguf-local",
        },
      ],
      monitorSnapshot: {
        providers: [
          {
            provider: "llama.cpp",
            ok: true,
            reasonCode: "helper_bridge_loaded",
            loadedInstanceCount: 1,
          },
        ],
      },
      providers: {
        "llama.cpp": {
          ok: true,
          packInstalled: true,
          packState: "installed",
          runtimeSource: "helper_binary_bridge",
          runtimeReasonCode: "helper_bridge_loaded",
          loadedInstances: [
            {
              instanceKey: "llama.cpp:nomic-embed-gguf-local:abc123",
              modelId: "nomic-embed-gguf-local",
            },
          ],
        },
      },
    },
    evidenceRefs: ["build/reports/lpr_w4_08_b_gguf_require_real/task_output.json"],
  });

  assert.equal(report.status, "PASS(gguf_require_real_closure_ready)");
  assert.equal(report.machine_decision.require_real_evidence_complete, true);
  assert.equal(report.machine_decision.primary_blocker_reason_code, "");
  assert.equal(report.machine_decision.shared_runtime_truth, true);
  assert.equal(report.summary.dims, 768);
});

run("gguf require-real report fails closed when runtime monitor truth is missing", () => {
  const report = buildGGUFRequireRealReport({
    generatedAt: "2026-03-26T06:52:00Z",
    warmup: {
      ok: true,
      provider: "llama.cpp",
      taskKind: "embedding",
      modelId: "nomic-embed-gguf-local",
      instanceKey: "llama.cpp:nomic-embed-gguf-local:abc123",
    },
    task: {
      ok: true,
      provider: "llama.cpp",
      taskKind: "embedding",
      modelId: "nomic-embed-gguf-local",
      vectorCount: 1,
      dims: 768,
      instanceKey: "llama.cpp:nomic-embed-gguf-local:abc123",
    },
    taskRequest: {
      provider: "llama.cpp",
      model_id: "nomic-embed-gguf-local",
    },
    helperProbe: {
      daemonStatus: { status: "running" },
      serverStatus: { running: true, port: 1234 },
      loadedRows: [
        {
          identifier: "llama.cpp:nomic-embed-gguf-local:abc123",
        },
      ],
      httpModels: [
        {
          id: "llama.cpp:nomic-embed-gguf-local:abc123",
        },
      ],
    },
    runtimeStatus: {
      loadedInstanceCount: 0,
      loadedInstances: [],
      monitorSnapshot: {
        providers: [
          {
            provider: "llama.cpp",
            ok: true,
            reasonCode: "helper_bridge_ready",
            loadedInstanceCount: 0,
          },
        ],
      },
      providers: {
        "llama.cpp": {
          ok: true,
          packInstalled: true,
          packState: "installed",
          runtimeSource: "helper_binary_bridge",
          runtimeReasonCode: "helper_bridge_ready",
          loadedInstances: [],
        },
      },
    },
  });

  assert.equal(report.machine_decision.gate_verdict, "NO_GO(gguf_require_real_blocked)");
  assert.equal(report.machine_decision.primary_blocker_reason_code, "runtime_truth_missing_loaded_instance");
  assert.ok(report.next_required_artifacts.includes("ai_runtime_status.json monitor snapshot showing loaded llama.cpp instance truth"));
});
