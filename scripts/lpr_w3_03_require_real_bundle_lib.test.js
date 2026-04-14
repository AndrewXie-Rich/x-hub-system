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

function withTempReportsDir(fn) {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "lpr_w3_03_bundle_lib_test."));
  const previous = process.env.LPR_W3_03_REQUIRE_REAL_REPORTS_DIR;
  process.env.LPR_W3_03_REQUIRE_REAL_REPORTS_DIR = tempDir;
  try {
    fn(tempDir);
  } finally {
    if (previous === undefined) delete process.env.LPR_W3_03_REQUIRE_REAL_REPORTS_DIR;
    else process.env.LPR_W3_03_REQUIRE_REAL_REPORTS_DIR = previous;
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

run("LPR-W3-03 bundle lib exposes the expected default capture bundle contract", () => {
  withTempReportsDir(() => {
    const bundleLib = loadFresh("./lpr_w3_03_require_real_bundle_lib.js");
    const bundle = bundleLib.buildDefaultCaptureBundle({
      generatedAt: "2026-03-22T16:00:00Z",
    });

    assert.equal(bundle.schema_version, "xhub.lpr_w3_03_require_real_capture_bundle.v1");
    assert.equal(bundle.generated_at, "2026-03-22T16:00:00Z");
    assert.equal(bundle.updated_at, "2026-03-22T16:00:00Z");
    assert.equal(bundle.status, "ready_for_execution");
    assert.equal(bundle.samples.length, 4);
    assert.deepEqual(bundle.execution_order, bundle.samples.map((sample) => sample.sample_id));
    assert.equal(bundle.samples[0].sample_id, "lpr_rr_01_embedding_real_model_dir_executes");
    assert.equal(bundle.samples[3].sample_id, "lpr_rr_04_doctor_and_release_export_match_real_runs");
  });
});

run("LPR-W3-03 bundle lib bootstraps a capture bundle only once per target reports dir", () => {
  withTempReportsDir((tempDir) => {
    const bundleLib = loadFresh("./lpr_w3_03_require_real_bundle_lib.js");
    const first = bundleLib.ensureCaptureBundleFile({
      generatedAt: "2026-03-22T16:10:00Z",
    });
    const second = bundleLib.ensureCaptureBundleFile({
      generatedAt: "2026-03-22T16:11:00Z",
    });

    const expectedBundlePath = path.join(tempDir, "lpr_w3_03_require_real_capture_bundle.v1.json");
    assert.equal(first.created, true);
    assert.equal(second.created, false);
    assert.equal(first.bundlePath, expectedBundlePath);
    assert.equal(second.bundlePath, expectedBundlePath);
    assert.equal(bundleLib.resolveReportsDir(), tempDir);
    assert.equal(bundleLib.resolveBundlePath(), expectedBundlePath);
    assert.equal(
      bundleLib.resolveRequireRealEvidencePath(),
      path.join(tempDir, "lpr_w3_03_a_require_real_evidence.v1.json")
    );

    const onDisk = JSON.parse(fs.readFileSync(expectedBundlePath, "utf8"));
    assert.equal(onDisk.generated_at, "2026-03-22T16:10:00Z");
    assert.equal(onDisk.samples.length, 4);
  });
});

run("LPR-W3-03 bootstrapped bundle can be consumed by updater without a preexisting file", () => {
  withTempReportsDir(() => {
    const bundleLib = loadFresh("./lpr_w3_03_require_real_bundle_lib.js");
    const updater = loadFresh("./update_lpr_w3_03_require_real_capture_bundle.js");

    const bundle = bundleLib.readCaptureBundle({
      generatedAt: "2026-03-22T16:20:00Z",
    });
    const result = updater.updateBundle(bundle, {
      sampleId: "lpr_rr_01_embedding_real_model_dir_executes",
      status: "passed",
      success: true,
      performedAt: "2026-03-22T16:21:00Z",
      evidenceRefs: ["build/reports/proof-1.png", "build/reports/proof-1.png"],
      operatorNote: "real execution",
      setFields: {
        provider: "transformers",
        task_kind: "embedding",
        model_id: "local-embed",
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
    }, "2026-03-22T16:21:00Z");

    assert.equal(result.sample.sample_id, "lpr_rr_01_embedding_real_model_dir_executes");
    assert.equal(result.sample.success_boolean, true);
    assert.deepEqual(result.sample.evidence_refs, ["build/reports/proof-1.png"]);
    assert.equal(result.sample.vector_count, 3);
    assert.equal(result.bundle.status, "ready_for_execution");
  });
});
