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
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "xt_w3_31_bundle_lib_test."));
  const previous = process.env.XT_W3_31_REQUIRE_REAL_REPORTS_DIR;
  process.env.XT_W3_31_REQUIRE_REAL_REPORTS_DIR = tempDir;
  try {
    fn(tempDir);
  } finally {
    if (previous === undefined) delete process.env.XT_W3_31_REQUIRE_REAL_REPORTS_DIR;
    else process.env.XT_W3_31_REQUIRE_REAL_REPORTS_DIR = previous;
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

run("XT-W3-31 bundle lib exposes the expected default capture bundle contract", () => {
  withTempReportsDir(() => {
    const bundleLib = loadFresh("./xt_w3_31_require_real_bundle_lib.js");
    const bundle = bundleLib.buildDefaultCaptureBundle({
      generatedAt: "2026-03-22T12:00:00Z",
    });

    assert.equal(bundle.schema_version, "xhub.xt_w3_31_require_real_capture_bundle.v1");
    assert.equal(bundle.generated_at, "2026-03-22T12:00:00Z");
    assert.equal(bundle.updated_at, "2026-03-22T12:00:00Z");
    assert.equal(bundle.status, "ready_for_execution");
    assert.equal(bundle.samples.length, 7);
    assert.deepEqual(bundle.execution_order, bundle.samples.map((sample) => sample.sample_id));
    assert.equal(bundle.samples[0].sample_id, "xt_spf_rr_01_new_project_visible_within_3s");
    assert.equal(bundle.samples[6].sample_id, "xt_spf_rr_07_stale_capsule_not_promoted_as_fresh");
  });
});

run("XT-W3-31 bundle lib bootstraps a capture bundle only once per target reports dir", () => {
  withTempReportsDir((tempDir) => {
    const bundleLib = loadFresh("./xt_w3_31_require_real_bundle_lib.js");
    const first = bundleLib.ensureCaptureBundleFile({
      generatedAt: "2026-03-22T12:10:00Z",
    });
    const second = bundleLib.ensureCaptureBundleFile({
      generatedAt: "2026-03-22T12:11:00Z",
    });

    const expectedBundlePath = path.join(tempDir, "xt_w3_31_require_real_capture_bundle.v1.json");
    assert.equal(first.created, true);
    assert.equal(second.created, false);
    assert.equal(first.bundlePath, expectedBundlePath);
    assert.equal(second.bundlePath, expectedBundlePath);
    assert.equal(bundleLib.resolveReportsDir(), tempDir);
    assert.equal(bundleLib.resolveBundlePath(), expectedBundlePath);
    assert.equal(
      bundleLib.resolveRequireRealEvidencePath(),
      path.join(tempDir, "xt_w3_31_h_require_real_evidence.v1.json")
    );

    const onDisk = JSON.parse(fs.readFileSync(expectedBundlePath, "utf8"));
    assert.equal(onDisk.generated_at, "2026-03-22T12:10:00Z");
    assert.equal(onDisk.samples.length, 7);
  });
});

run("XT-W3-31 bundle lib bootstrapped bundle can be consumed by updater without a preexisting file", () => {
  withTempReportsDir(() => {
    const bundleLib = loadFresh("./xt_w3_31_require_real_bundle_lib.js");
    const updater = loadFresh("./update_xt_w3_31_require_real_capture_bundle.js");

    const bundle = bundleLib.readCaptureBundle({
      generatedAt: "2026-03-22T12:20:00Z",
    });
    const result = updater.updateBundle(bundle, {
      sampleId: "xt_spf_rr_01_new_project_visible_within_3s",
      status: "passed",
      success: true,
      performedAt: "2026-03-22T12:21:00Z",
      evidenceRefs: ["build/reports/proof-1.png", "build/reports/proof-1.png"],
      operatorNote: "real execution",
      setFields: {
        project_id: "proj_alpha",
        project_name: "Alpha",
        jurisdiction_role: "owner",
        observed_result: "visible_in_1800ms",
        first_visible_latency_ms: 1800,
        evidence_origin: "real_runtime",
        synthetic_runtime_evidence: false,
        synthetic_markers: [],
      },
    }, "2026-03-22T12:21:00Z");

    assert.equal(result.sample.sample_id, "xt_spf_rr_01_new_project_visible_within_3s");
    assert.equal(result.sample.success_boolean, true);
    assert.deepEqual(result.sample.evidence_refs, ["build/reports/proof-1.png"]);
    assert.equal(result.sample.first_visible_latency_ms, 1800);
    assert.equal(result.bundle.status, "ready_for_execution");
  });
});
