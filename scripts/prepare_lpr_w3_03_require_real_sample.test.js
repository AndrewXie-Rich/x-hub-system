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
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "lpr_w3_03_prepare_test."));
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

run("LPR-W3-03 sample prepare scaffolds the next pending sample by default", () => {
  withTempReportsDir((tempDir) => {
    const bundleLib = loadFresh("./lpr_w3_03_require_real_bundle_lib.js");
    const helper = loadFresh("./prepare_lpr_w3_03_require_real_sample.js");

    const bundle = bundleLib.readCaptureBundle({
      generatedAt: "2026-03-22T17:00:00Z",
    });
    const sample = bundle.samples[0];
    const output = helper.prepareSampleScaffold(sample, {
      reportsDir: tempDir,
    });

    assert.equal(output.sample_id, "lpr_rr_01_embedding_real_model_dir_executes");
    assert.equal(output.files.length, 6);
    const manifestPath = path.join(tempDir, "lpr_w3_03_require_real", sample.sample_id, "sample_manifest.v1.json");
    const templatePath = path.join(tempDir, "lpr_w3_03_require_real", sample.sample_id, "machine_readable_template.v1.json");
    const notePath = path.join(tempDir, "lpr_w3_03_require_real", sample.sample_id, "completion_notes.txt");
    const finalizeCommandPath = path.join(tempDir, "lpr_w3_03_require_real", sample.sample_id, "finalize_sample.command.txt");
    const commandPath = path.join(tempDir, "lpr_w3_03_require_real", sample.sample_id, "update_bundle.command.txt");
    assert.ok(fs.existsSync(manifestPath));
    assert.ok(fs.existsSync(templatePath));
    assert.ok(fs.existsSync(notePath));
    assert.ok(fs.existsSync(finalizeCommandPath));
    assert.ok(fs.existsSync(commandPath));
    const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
    const template = JSON.parse(fs.readFileSync(templatePath, "utf8"));
    assert.equal(manifest.sample_id, sample.sample_id);
    assert.equal(template.task_kind, "embedding");
    assert.match(fs.readFileSync(notePath, "utf8"), /finalize helper/);
    assert.match(fs.readFileSync(finalizeCommandPath, "utf8"), /finalize_lpr_w3_03_require_real_sample\.js/);
    assert.match(fs.readFileSync(commandPath, "utf8"), /update_lpr_w3_03_require_real_capture_bundle\.js/);
    assert.match(fs.readFileSync(commandPath, "utf8"), /--scaffold-dir build\/reports\/lpr_w3_03_require_real\//);
    assert.match(output.finalize_command, /--scaffold-dir build\/reports\/lpr_w3_03_require_real\//);
    assert.equal(output.recommended_completion_note_path, `build/reports/lpr_w3_03_require_real/${sample.sample_id}/completion_notes.txt`);
  });
});

run("LPR-W3-03 sample prepare can target a specific sample and preserve existing files without force", () => {
  withTempReportsDir((tempDir) => {
    const bundleLib = loadFresh("./lpr_w3_03_require_real_bundle_lib.js");
    const helper = loadFresh("./prepare_lpr_w3_03_require_real_sample.js");

    const bundle = bundleLib.readCaptureBundle({
      generatedAt: "2026-03-22T17:10:00Z",
    });
    const sample = bundle.samples.find((item) => item.sample_id === "lpr_rr_04_doctor_and_release_export_match_real_runs");
    assert.ok(sample);

    const evidenceDir = path.join(tempDir, "lpr_w3_03_require_real", sample.sample_id);
    fs.mkdirSync(evidenceDir, { recursive: true });
    const readmePath = path.join(evidenceDir, "README.md");
    fs.writeFileSync(readmePath, "manual note\n", "utf8");

    const output = helper.prepareSampleScaffold(sample, {
      reportsDir: tempDir,
      force: false,
    });

    const readmeEntry = output.files.find((file) => file.path.endsWith("README.md"));
    assert.equal(readmeEntry.status, "skipped_existing");
    assert.equal(fs.readFileSync(readmePath, "utf8"), "manual note\n");
    const manifest = JSON.parse(fs.readFileSync(path.join(evidenceDir, "sample_manifest.v1.json"), "utf8"));
    assert.equal(manifest.sample_id, sample.sample_id);
    assert.deepEqual(manifest.machine_readable_template.covered_task_kinds, ["embedding", "speech_to_text", "vision_understand"]);
    assert.match(output.suggested_update_command, /--scaffold-dir build\/reports\/lpr_w3_03_require_real\//);
  });
});
