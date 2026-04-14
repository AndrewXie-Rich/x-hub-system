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
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "xt_w3_24_n_bundle_lib_test."));
  const previous = process.env.XT_W3_24_N_REQUIRE_REAL_REPORTS_DIR;
  process.env.XT_W3_24_N_REQUIRE_REAL_REPORTS_DIR = tempDir;
  try {
    fn(tempDir);
  } finally {
    if (previous === undefined) delete process.env.XT_W3_24_N_REQUIRE_REAL_REPORTS_DIR;
    else process.env.XT_W3_24_N_REQUIRE_REAL_REPORTS_DIR = previous;
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

run("XT-W3-24-N bundle lib exposes the expected default capture bundle contract", () => {
  withTempReportsDir(() => {
    const bundleLib = loadFresh("./xt_w3_24_n_whatsapp_cloud_require_real_bundle_lib.js");
    const bundle = bundleLib.buildDefaultCaptureBundle({
      generatedAt: "2026-03-22T13:00:00Z",
    });

    assert.equal(bundle.schema_version, "xhub.xt_w3_24_n_whatsapp_cloud_require_real_capture_bundle.v1");
    assert.equal(bundle.generated_at, "2026-03-22T13:00:00Z");
    assert.equal(bundle.updated_at, "2026-03-22T13:00:00Z");
    assert.equal(bundle.status, "ready_for_execution");
    assert.equal(bundle.samples.length, 4);
    assert.deepEqual(bundle.execution_order, bundle.samples.map((sample) => sample.sample_id));
    assert.equal(bundle.samples[0].sample_id, "xt_w3_24_n_rr_01_status_query_is_hub_only_and_audited");
    assert.equal(bundle.samples[3].sample_id, "xt_w3_24_n_rr_04_grant_approve_requires_pending_scope_match");
  });
});

run("XT-W3-24-N bundle lib bootstraps a capture bundle only once per target reports dir", () => {
  withTempReportsDir((tempDir) => {
    const bundleLib = loadFresh("./xt_w3_24_n_whatsapp_cloud_require_real_bundle_lib.js");
    const first = bundleLib.ensureCaptureBundleFile({
      generatedAt: "2026-03-22T13:10:00Z",
    });
    const second = bundleLib.ensureCaptureBundleFile({
      generatedAt: "2026-03-22T13:11:00Z",
    });

    const expectedBundlePath = path.join(tempDir, "xt_w3_24_n_whatsapp_cloud_require_real_capture_bundle.v1.json");
    assert.equal(first.created, true);
    assert.equal(second.created, false);
    assert.equal(first.bundlePath, expectedBundlePath);
    assert.equal(second.bundlePath, expectedBundlePath);
    assert.equal(bundleLib.resolveReportsDir(), tempDir);
    assert.equal(bundleLib.resolveBundlePath(), expectedBundlePath);
    assert.equal(
      bundleLib.resolveRequireRealEvidencePath(),
      path.join(tempDir, "xt_w3_24_n_action_grant_whatsapp_evidence.v1.json")
    );

    const onDisk = JSON.parse(fs.readFileSync(expectedBundlePath, "utf8"));
    assert.equal(onDisk.generated_at, "2026-03-22T13:10:00Z");
    assert.equal(onDisk.samples.length, 4);
  });
});

run("XT-W3-24-N bootstrapped bundle can be consumed by updater without a preexisting file", () => {
  withTempReportsDir(() => {
    const bundleLib = loadFresh("./xt_w3_24_n_whatsapp_cloud_require_real_bundle_lib.js");
    const updater = loadFresh("./update_xt_w3_24_n_whatsapp_cloud_require_real_capture_bundle.js");

    const bundle = bundleLib.readCaptureBundle({
      generatedAt: "2026-03-22T13:20:00Z",
    });
    const result = updater.updateBundle(bundle, {
      sampleId: "xt_w3_24_n_rr_01_status_query_is_hub_only_and_audited",
      status: "passed",
      success: true,
      performedAt: "2026-03-22T13:21:00Z",
      evidenceRefs: ["build/reports/proof-1.png", "build/reports/proof-1.png"],
      operatorNote: "real execution",
      setFields: {
        provider: "whatsapp_cloud_api",
        structured_action_name: "supervisor.status.get",
        route_mode: "hub_only_status",
        project_binding_enforced: true,
        provider_reply_mode: "text_only",
        side_effect_executed: false,
        audit_chain_complete: true,
        evidence_origin: "real_runtime",
        synthetic_runtime_evidence: false,
        synthetic_markers: [],
      },
    }, "2026-03-22T13:21:00Z");

    assert.equal(result.sample.sample_id, "xt_w3_24_n_rr_01_status_query_is_hub_only_and_audited");
    assert.equal(result.sample.success_boolean, true);
    assert.deepEqual(result.sample.evidence_refs, ["build/reports/proof-1.png"]);
    assert.equal(result.sample.provider_reply_mode, "text_only");
    assert.equal(result.bundle.status, "ready_for_execution");
  });
});
