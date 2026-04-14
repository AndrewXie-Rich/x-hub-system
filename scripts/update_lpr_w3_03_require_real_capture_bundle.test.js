#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

function loadFresh(relativePath) {
  const resolved = require.resolve(relativePath);
  delete require.cache[resolved];
  return require(relativePath);
}

function withTempDir(fn) {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "lpr_w3_03_update_scaffold_test."));
  try {
    fn(tempDir);
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

run("LPR-W3-03 updater collects evidence refs from scaffold dirs while excluding metadata files", () => {
  withTempDir((tempDir) => {
    const updater = loadFresh("./update_lpr_w3_03_require_real_capture_bundle.js");
    const scaffoldDir = path.join(tempDir, "sample");
    fs.mkdirSync(path.join(scaffoldDir, "nested"), { recursive: true });

    fs.writeFileSync(path.join(scaffoldDir, "README.md"), "readme\n", "utf8");
    fs.writeFileSync(path.join(scaffoldDir, "completion_notes.txt"), "# notes\n", "utf8");
    fs.writeFileSync(path.join(scaffoldDir, "finalize_sample.command.txt"), "cmd\n", "utf8");
    fs.writeFileSync(path.join(scaffoldDir, "sample_manifest.v1.json"), "{}\n", "utf8");
    fs.writeFileSync(path.join(scaffoldDir, "machine_readable_template.v1.json"), "{}\n", "utf8");
    fs.writeFileSync(path.join(scaffoldDir, "update_bundle.command.txt"), "cmd\n", "utf8");
    fs.writeFileSync(path.join(scaffoldDir, ".DS_Store"), "junk\n", "utf8");
    fs.writeFileSync(path.join(scaffoldDir, "capture-1.png"), "png\n", "utf8");
    fs.writeFileSync(path.join(scaffoldDir, "nested", "runtime.log"), "log\n", "utf8");

    const refs = updater.collectEvidenceRefsFromDir(scaffoldDir);
    assert.equal(refs.length, 2);
    assert.ok(refs.some((item) => String(item).endsWith("capture-1.png")));
    assert.ok(refs.some((item) => String(item).endsWith(path.join("nested", "runtime.log"))));
    assert.ok(!refs.some((item) => String(item).endsWith("sample_manifest.v1.json")));
  });
});

run("LPR-W3-03 updater can derive sample id, template and evidence refs from scaffold dir", () => {
  withTempDir((tempDir) => {
    const updater = loadFresh("./update_lpr_w3_03_require_real_capture_bundle.js");
    const scaffoldDir = path.join(tempDir, "sample");
    fs.mkdirSync(scaffoldDir, { recursive: true });

    fs.writeFileSync(path.join(scaffoldDir, "sample_manifest.v1.json"), JSON.stringify({
      sample_id: "lpr_rr_01_embedding_real_model_dir_executes",
    }, null, 2), "utf8");
    fs.writeFileSync(path.join(scaffoldDir, "machine_readable_template.v1.json"), JSON.stringify({
      evidence_origin: "real_local_runtime",
      synthetic_runtime_evidence: false,
      synthetic_markers: [],
    }, null, 2), "utf8");
    fs.writeFileSync(path.join(scaffoldDir, "capture-1.png"), "png\n", "utf8");

    const applied = updater.applyScaffoldDirArgs({
      sampleId: "",
      scaffoldDir,
      evidenceDir: "",
      fromJson: "",
      evidenceRefs: [],
      setFields: {},
    });

    assert.equal(applied.sampleId, "lpr_rr_01_embedding_real_model_dir_executes");
    assert.equal(applied.fromJson, path.join(scaffoldDir, "machine_readable_template.v1.json"));
    assert.ok(applied.evidenceRefs.some((item) => String(item).endsWith("capture-1.png")));
  });
});

run("LPR-W3-03 updater keeps native JSON field types and rejects placeholder scaffold values", () => {
  withTempDir(() => {
    const updater = loadFresh("./update_lpr_w3_03_require_real_capture_bundle.js");
    const bundle = {
      schema_version: "xhub.lpr_w3_03_require_real_capture_bundle.v1",
      generated_at: "2026-03-22T10:00:00Z",
      updated_at: "2026-03-22T10:00:00Z",
      status: "ready_for_execution",
      stop_on_first_defect: true,
      execution_order: ["lpr_rr_01_embedding_real_model_dir_executes"],
      samples: [
        {
          sample_id: "lpr_rr_01_embedding_real_model_dir_executes",
          status: "pending",
          performed_at: "",
          success_boolean: null,
          evidence_refs: [],
          operator_notes: "",
          machine_readable_fields_to_record: [
            "provider",
            "task_kind",
            "model_id",
            "model_path",
            "device_id",
            "route_source",
            "load_profile_hash",
            "effective_context_length",
            "input_artifact_ref",
            "vector_count",
            "latency_ms",
            "monitor_snapshot_captured",
            "diagnostics_export_captured",
            "evidence_origin",
            "synthetic_runtime_evidence",
            "synthetic_markers",
          ],
          required_checks: [
            { field: "provider", equals: "transformers" },
            { field: "task_kind", equals: "embedding" },
            { field: "model_path", not_equals: "" },
            { field: "device_id", not_equals: "" },
            { field: "route_source", not_equals: "" },
            { field: "load_profile_hash", not_equals: "" },
            { field: "effective_context_length", min: 1 },
            { field: "input_artifact_ref", not_equals: "" },
            { field: "vector_count", min: 1 },
            { field: "monitor_snapshot_captured", equals: true },
            { field: "diagnostics_export_captured", equals: true },
          ],
          synthetic_runtime_evidence: false,
          synthetic_markers: [],
        },
      ],
    };

    assert.throws(() => updater.updateBundle(bundle, {
      sampleId: "lpr_rr_01_embedding_real_model_dir_executes",
      status: "passed",
      success: true,
      performedAt: "2026-03-22T10:05:00Z",
      evidenceRefs: ["build/reports/proof.png"],
      setFields: {
        provider: "transformers",
        task_kind: "embedding",
        model_id: "embed-01",
        model_path: "/tmp/model",
        device_id: "xt-01",
        route_source: "hub_default",
        load_profile_hash: "hash-01",
        effective_context_length: 8192,
        input_artifact_ref: "<input_artifact_ref>",
        vector_count: 3,
        latency_ms: 214,
        monitor_snapshot_captured: true,
        diagnostics_export_captured: true,
        evidence_origin: "real_local_runtime",
        synthetic_runtime_evidence: false,
        synthetic_markers: [],
      },
    }, "2026-03-22T10:05:00Z"), /machine_readable_field_placeholder:input_artifact_ref/);

    const result = updater.updateBundle(bundle, {
      sampleId: "lpr_rr_01_embedding_real_model_dir_executes",
      status: "passed",
      success: true,
      performedAt: "2026-03-22T10:06:00Z",
      evidenceRefs: ["build/reports/proof.png"],
      setFields: {
        provider: "transformers",
        task_kind: "embedding",
        model_id: "embed-01",
        model_path: "/tmp/model",
        device_id: "xt-01",
        route_source: "hub_default",
        load_profile_hash: "hash-01",
        effective_context_length: 8192,
        input_artifact_ref: "build/reports/input.txt",
        vector_count: 3,
        latency_ms: 214,
        monitor_snapshot_captured: true,
        diagnostics_export_captured: true,
        evidence_origin: "real_local_runtime",
        synthetic_runtime_evidence: false,
        synthetic_markers: [],
      },
    }, "2026-03-22T10:06:00Z");

    assert.equal(result.sample.model_id, "embed-01");
    assert.equal(result.sample.vector_count, 3);
    assert.deepEqual(result.sample.synthetic_markers, []);
  });
});
