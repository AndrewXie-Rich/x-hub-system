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
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "xt_w3_24_n_finalize_test."));
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

run("XT-W3-24-N finalize helper closes a scaffolded sample and refreshes the pending report", () => {
  withTempReportsDir((tempDir) => {
    const bundleLib = loadFresh("./xt_w3_24_n_whatsapp_cloud_require_real_bundle_lib.js");
    const prepareHelper = loadFresh("./prepare_xt_w3_24_n_whatsapp_cloud_require_real_sample.js");
    const finalizeHelper = loadFresh("./finalize_xt_w3_24_n_whatsapp_cloud_require_real_sample.js");

    const bundle = bundleLib.readCaptureBundle({
      generatedAt: "2026-03-22T15:00:00Z",
    });
    const sample = bundle.samples[0];
    prepareHelper.prepareSampleScaffold(sample, {
      reportsDir: tempDir,
    });
    const scaffoldDir = path.join(tempDir, "xt_w3_24_n_whatsapp_cloud_require_real", sample.sample_id);
    const templatePath = path.join(scaffoldDir, "machine_readable_template.v1.json");
    const notePath = path.join(scaffoldDir, "completion_notes.txt");

    const template = JSON.parse(fs.readFileSync(templatePath, "utf8"));
    template.evidence_origin = "real_runtime";
    fs.writeFileSync(templatePath, `${JSON.stringify(template, null, 2)}\n`, "utf8");
    fs.writeFileSync(path.join(scaffoldDir, "capture-1.png"), "png\n", "utf8");
    fs.writeFileSync(notePath, "# comment\n真实状态查询已通过 WhatsApp Cloud 回传。\n", "utf8");

    const result = finalizeHelper.finalizeSample({
      scaffoldDir,
      reportsDir: tempDir,
    }, "2026-03-22T15:05:00Z");

    assert.equal(result.sample_id, sample.sample_id);
    assert.equal(result.status, "passed");
    assert.equal(result.success_boolean, true);
    assert.equal(result.performed_at, "2026-03-22T15:05:00Z");
    assert.equal(result.evidence_ref_count, 1);
    assert.match(result.operator_note_source, /completion_notes\.txt$/);
    assert.match(result.report_path, /xt_w3_24_n_action_grant_whatsapp_evidence\.v1\.json$/);
    assert.equal(result.qa_gate_verdict, "NO_GO(require_real_samples_pending)");
    assert.equal(result.next_pending_sample_id, "xt_w3_24_n_rr_02_deploy_execute_stays_pending_until_grant_approval");

    const updatedBundle = bundleLib.readCaptureBundle({
      reportsDir: tempDir,
    });
    const updatedSample = updatedBundle.samples.find((item) => item.sample_id === sample.sample_id);
    assert.equal(updatedSample.operator_notes, "真实状态查询已通过 WhatsApp Cloud 回传。");
    assert.deepEqual(updatedSample.evidence_refs, [path.join(scaffoldDir, "capture-1.png")]);
    assert.ok(fs.existsSync(path.join(tempDir, "xt_w3_24_n_action_grant_whatsapp_evidence.v1.json")));
  });
});
