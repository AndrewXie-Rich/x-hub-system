#!/usr/bin/env node
const assert = require("node:assert/strict");
const childProcess = require("node:child_process");
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

run("W8-C1 starter pack baseline evidence stays ready", () => {
  const repoRoot = path.resolve(__dirname, "..");
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "w8-c1-baseline-evidence-"));
  try {
    const outputPath = path.join(tempRoot, "w8_c1_starter_pack_baseline_evidence.v1.json");
    const result = childProcess.spawnSync(process.execPath, [
      path.join(repoRoot, "scripts", "generate_w8_c1_starter_pack_baseline_evidence.js"),
      "--out", outputPath,
    ], {
      cwd: repoRoot,
      encoding: "utf8",
    });
    assert.equal(result.status, 0, result.stderr || result.stdout);

    const payload = JSON.parse(fs.readFileSync(outputPath, "utf8"));
    assert.equal(payload.status, "ready");
    assert.equal(payload.catalog_alignment.all_baseline_skills_present, true);
    assert.equal(payload.catalog_alignment.quality_status_matches_required_surface, true);
    assert.equal(payload.doctor_snapshot.all_baseline_skills_ready, true);
    assert.equal(payload.smoke_snapshot.all_execution_gates_allowed, true);
    assert.equal(payload.smoke_snapshot.all_baseline_skills_resolved, true);
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});
