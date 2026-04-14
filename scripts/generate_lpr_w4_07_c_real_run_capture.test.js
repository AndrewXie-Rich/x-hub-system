#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");

const {
  buildMLXVLMRealCaptureBundle,
  buildModelCatalog,
  buildProviderPackRegistry,
  deriveRealRuntimeTouched,
  normalizeTaskCapture,
} = require("./generate_lpr_w4_07_c_real_run_capture.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

run("mlx_vlm model catalog pins helper-routed runtime provider and task kinds", () => {
  const catalog = buildModelCatalog("qwen3-vl-helper-real", "/models/qwen3-vl");
  assert.equal(catalog.models.length, 1);
  assert.equal(catalog.models[0].backend, "mlx");
  assert.equal(catalog.models[0].runtimeProviderID, "mlx_vlm");
  assert.deepEqual(catalog.models[0].taskKinds, ["vision_understand", "ocr"]);
  assert.equal(catalog.models[0].default_load_config.vision.image_max_dimension, 2048);
});

run("provider pack registry targets helper binary bridge for mlx_vlm", () => {
  const registry = buildProviderPackRegistry("/tmp/lms");
  assert.equal(registry.schemaVersion, "xhub.provider_pack_registry.v1");
  assert.equal(registry.packs[0].providerId, "mlx_vlm");
  assert.equal(registry.packs[0].runtimeRequirements.executionMode, "helper_binary_bridge");
  assert.equal(registry.packs[0].runtimeRequirements.helperBinary, "/tmp/lms");
});

run("real runtime touch is derived from helper bridge route or backend truth", () => {
  assert.equal(
    deriveRealRuntimeTouched({
      routeTrace: { executionPath: "helper_bridge" },
    }),
    true
  );
  assert.equal(
    deriveRealRuntimeTouched({
      deviceBackend: "helper_binary_bridge",
    }),
    true
  );
  assert.equal(
    deriveRealRuntimeTouched({
      routeTrace: { executionPath: "synthetic_fallback" },
      deviceBackend: "preview_only",
    }),
    false
  );
});

run("task capture annotates real_runtime_touched for mlx_vlm task outputs", () => {
  const task = normalizeTaskCapture({
    ok: true,
    routeTrace: {
      executionPath: "helper_bridge",
    },
    text: "visible layout",
  });
  assert.equal(task.ok, true);
  assert.equal(task.real_runtime_touched, true);
  assert.equal(task.text, "visible layout");
});

run("capture bundle keeps vision task as primary and preserves ocr evidence", () => {
  const capture = buildMLXVLMRealCaptureBundle({
    generatedAt: "2026-03-26T08:00:00Z",
    performedAt: "2026-03-26T08:00:01Z",
    modelId: "qwen3-vl-helper-real",
    modelPath: "/models/qwen3-vl",
    helperBinaryPath: "/tmp/lms",
    pythonRuntime: {
      runtime_id: "lmstudio_cpython311_combo_transformers",
      label: "LM Studio combo runtime",
      command: "/tmp/python3",
      env: {
        PYTHONPATH: "/tmp/site-packages",
      },
    },
    warmup: { ok: true },
    task: {
      ok: true,
      routeTrace: { executionPath: "helper_bridge" },
    },
    ocrTask: {
      ok: true,
      deviceBackend: "helper_binary_bridge",
    },
    bench: { ok: true },
    monitor: { snapshot_captured: true },
    evidenceRefs: ["a.json", "b.json", "a.json"],
    commandRefs: ["cmd-1", "cmd-2", "cmd-1"],
  });

  assert.equal(capture.provider, "mlx_vlm");
  assert.equal(capture.task_kind, "vision_understand");
  assert.equal(capture.task.real_runtime_touched, true);
  assert.equal(capture.ocr_task.real_runtime_touched, true);
  assert.deepEqual(capture.evidence_refs, ["a.json", "b.json"]);
  assert.deepEqual(capture.command_refs, ["cmd-1", "cmd-2"]);
});
