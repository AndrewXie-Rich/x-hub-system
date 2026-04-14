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
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "xt_w3_33_bundle_lib_test."));
  const previous = process.env.XT_W3_33_REQUIRE_REAL_REPORTS_DIR;
  process.env.XT_W3_33_REQUIRE_REAL_REPORTS_DIR = tempDir;
  try {
    fn(tempDir);
  } finally {
    if (previous === undefined) delete process.env.XT_W3_33_REQUIRE_REAL_REPORTS_DIR;
    else process.env.XT_W3_33_REQUIRE_REAL_REPORTS_DIR = previous;
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

run("XT-W3-33 bundle lib exposes the expected default capture bundle contract", () => {
  withTempReportsDir(() => {
    const bundleLib = loadFresh("./xt_w3_33_require_real_bundle_lib.js");
    const bundle = bundleLib.buildDefaultCaptureBundle({
      generatedAt: "2026-03-22T01:02:03Z",
    });

    assert.equal(bundle.schema_version, "xhub.xt_w3_33_require_real_capture_bundle.v1");
    assert.equal(bundle.generated_at, "2026-03-22T01:02:03Z");
    assert.equal(bundle.updated_at, "2026-03-22T01:02:03Z");
    assert.equal(bundle.status, "ready_for_execution");
    assert.equal(bundle.samples.length, 7);
    assert.deepEqual(bundle.execution_order, bundle.samples.map((sample) => sample.sample_id));
    assert.equal(bundle.samples[0].sample_id, "xt_w3_33_rr_01_formal_tech_stack_decision_track_persists");
    assert.equal(bundle.samples[6].sample_id, "xt_w3_33_rr_07_archive_rollup_keeps_traceability_refs");
  });
});

run("XT-W3-33 bundle lib bootstraps a capture bundle only once per target reports dir", () => {
  withTempReportsDir((tempDir) => {
    const bundleLib = loadFresh("./xt_w3_33_require_real_bundle_lib.js");
    const first = bundleLib.ensureCaptureBundleFile({
      generatedAt: "2026-03-22T02:00:00Z",
    });
    const second = bundleLib.ensureCaptureBundleFile({
      generatedAt: "2026-03-22T03:00:00Z",
    });

    const expectedBundlePath = path.join(tempDir, "xt_w3_33_h_require_real_capture_bundle.v1.json");
    assert.equal(first.created, true);
    assert.equal(second.created, false);
    assert.equal(first.bundlePath, expectedBundlePath);
    assert.equal(second.bundlePath, expectedBundlePath);
    assert.equal(bundleLib.resolveReportsDir(), tempDir);
    assert.equal(bundleLib.resolveBundlePath(), expectedBundlePath);
    assert.equal(
      bundleLib.resolveRequireRealEvidencePath(),
      path.join(tempDir, "xt_w3_33_h_require_real_evidence.v1.json")
    );
    assert.equal(
      bundleLib.resolveDecisionBlockerAssistEvidencePath(),
      path.join(tempDir, "xt_w3_33_f_decision_blocker_assist_evidence.v1.json")
    );
    assert.equal(
      bundleLib.resolveMemoryCompactionEvidencePath(),
      path.join(tempDir, "xt_w3_33_g_memory_compaction_evidence.v1.json")
    );

    const onDisk = JSON.parse(fs.readFileSync(expectedBundlePath, "utf8"));
    assert.equal(onDisk.generated_at, "2026-03-22T02:00:00Z");
    assert.equal(onDisk.samples.length, 7);
  });
});

run("XT-W3-33 bundle lib bootstrapped bundle can be consumed by the updater without a preexisting file", () => {
  withTempReportsDir(() => {
    const bundleLib = loadFresh("./xt_w3_33_require_real_bundle_lib.js");
    const updater = loadFresh("./update_xt_w3_33_require_real_capture_bundle.js");

    const bundle = bundleLib.readCaptureBundle({
      generatedAt: "2026-03-22T04:00:00Z",
    });
    const result = updater.updateBundle(bundle, {
      sampleId: "xt_w3_33_rr_01_formal_tech_stack_decision_track_persists",
      status: "passed",
      success: true,
      performedAt: "2026-03-22T04:05:00Z",
      evidenceRefs: ["build/reports/proof-1.png", "build/reports/proof-1.png"],
      operatorNote: "real execution",
      setFields: {
        decision_track_written: "true",
        decision_status: "approved",
        decision_category: "tech_stack",
        decision_audit_ref: "audit_ref_01",
        spec_capsule_sync: "true",
        evidence_origin: "real_runtime",
        synthetic_runtime_evidence: "false",
        synthetic_markers: "[]",
      },
    }, "2026-03-22T04:05:00Z");

    assert.equal(result.sample.sample_id, "xt_w3_33_rr_01_formal_tech_stack_decision_track_persists");
    assert.equal(result.sample.success_boolean, true);
    assert.deepEqual(result.sample.evidence_refs, ["build/reports/proof-1.png"]);
    assert.equal(result.sample.decision_track_written, true);
    assert.equal(result.sample.spec_capsule_sync, true);
    assert.equal(result.bundle.status, "ready_for_execution");
  });
});
