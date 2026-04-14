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
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "lpr_w3_03_finalize_test."));
  const previous = process.env.LPR_W3_03_REQUIRE_REAL_REPORTS_DIR;
  process.env.LPR_W3_03_REQUIRE_REAL_REPORTS_DIR = tempDir;
  try {
    const prerequisiteFiles = [
      "lpr_w2_01_a_embedding_contract_evidence.v1.json",
      "lpr_w2_02_a_asr_contract_evidence.v1.json",
      "lpr_w3_01_a_vision_preview_contract_evidence.v1.json",
      "lpr_w3_05_d_resident_runtime_proxy_evidence.v1.json",
      "lpr_w3_06_d_bench_fixture_pack_evidence.v1.json",
      "lpr_w3_07_c_monitor_export_evidence.v1.json",
      "lpr_w3_08_c_task_resolution_evidence.v1.json",
    ];
    for (const filename of prerequisiteFiles) {
      fs.writeFileSync(path.join(tempDir, filename), "{}\n", "utf8");
    }
    fn(tempDir);
  } finally {
    if (previous === undefined) delete process.env.LPR_W3_03_REQUIRE_REAL_REPORTS_DIR;
    else process.env.LPR_W3_03_REQUIRE_REAL_REPORTS_DIR = previous;
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

run("LPR-W3-03 finalize helper closes a scaffolded sample and refreshes the pending report", () => {
  withTempReportsDir((tempDir) => {
    const bundleLib = loadFresh("./lpr_w3_03_require_real_bundle_lib.js");
    const prepareHelper = loadFresh("./prepare_lpr_w3_03_require_real_sample.js");
    const finalizeHelper = loadFresh("./finalize_lpr_w3_03_require_real_sample.js");

    const bundle = bundleLib.readCaptureBundle({
      generatedAt: "2026-03-22T18:00:00Z",
    });
    const sample = bundle.samples[0];
    prepareHelper.prepareSampleScaffold(sample, {
      reportsDir: tempDir,
    });
    const scaffoldDir = path.join(tempDir, "lpr_w3_03_require_real", sample.sample_id);
    const templatePath = path.join(scaffoldDir, "machine_readable_template.v1.json");
    const notePath = path.join(scaffoldDir, "completion_notes.txt");

    const template = JSON.parse(fs.readFileSync(templatePath, "utf8"));
    template.model_id = "local-embed";
    template.model_path = "/tmp/model";
    template.device_id = "xt-01";
    template.route_source = "hub_default";
    template.load_profile_hash = "hash-01";
    template.effective_context_length = 8192;
    template.input_artifact_ref = "build/reports/input.txt";
    template.vector_count = 3;
    template.latency_ms = 214;
    template.monitor_snapshot_captured = true;
    template.diagnostics_export_captured = true;
    template.evidence_origin = "real_local_runtime";
    fs.writeFileSync(templatePath, `${JSON.stringify(template, null, 2)}\n`, "utf8");
    fs.writeFileSync(path.join(scaffoldDir, "capture-1.png"), "png\n", "utf8");
    fs.writeFileSync(notePath, "# comment\n真实 embedding 执行已完成。\n", "utf8");

    const result = finalizeHelper.finalizeSample({
      scaffoldDir,
      reportsDir: tempDir,
    }, "2026-03-22T18:05:00Z");

    assert.equal(result.sample_id, sample.sample_id);
    assert.equal(result.status, "passed");
    assert.equal(result.success_boolean, true);
    assert.equal(result.performed_at, "2026-03-22T18:05:00Z");
    assert.equal(result.evidence_ref_count, 1);
    assert.match(result.operator_note_source, /completion_notes\.txt$/);
    assert.match(result.report_path, /lpr_w3_03_a_require_real_evidence\.v1\.json$/);
    assert.equal(result.qa_gate_verdict, "NO_GO(require_real_samples_pending)");
    assert.equal(result.next_pending_sample_id, "lpr_rr_02_asr_real_model_dir_executes");

    const updatedBundle = bundleLib.readCaptureBundle({
      reportsDir: tempDir,
    });
    const updatedSample = updatedBundle.samples.find((item) => item.sample_id === sample.sample_id);
    assert.equal(updatedSample.operator_notes, "真实 embedding 执行已完成。");
    assert.equal(updatedSample.model_id, "local-embed");
    assert.deepEqual(updatedSample.evidence_refs, [path.join(scaffoldDir, "capture-1.png")]);
    assert.ok(fs.existsSync(path.join(tempDir, "lpr_w3_03_a_require_real_evidence.v1.json")));
  });
});
