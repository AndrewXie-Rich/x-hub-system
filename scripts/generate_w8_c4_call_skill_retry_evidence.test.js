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

run("W8-C4 call skill retry evidence stays ready", () => {
  const repoRoot = path.resolve(__dirname, "..");
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "w8-c4-call-skill-evidence-"));
  try {
    const outputPath = path.join(tempRoot, "w8_c4_call_skill_retry_evidence.v1.json");
    const result = childProcess.spawnSync(process.execPath, [
      path.join(repoRoot, "scripts", "generate_w8_c4_call_skill_retry_evidence.js"),
      "--out", outputPath,
    ], {
      cwd: repoRoot,
      encoding: "utf8",
    });
    assert.equal(result.status, 0, result.stderr || result.stdout);

    const payload = JSON.parse(fs.readFileSync(outputPath, "utf8"));
    assert.equal(payload.status, "ready");
    assert.equal(payload.categories.skill_registry_unavailable, true);
    assert.equal(payload.categories.skill_not_registered, true);
    assert.equal(payload.categories.skill_mapping_missing, true);
    assert.equal(payload.categories.payload_validation_failed, true);
    assert.equal(payload.categories.grant_resume_success, true);
    assert.equal(payload.categories.retry_from_persisted_governed_dispatch, true);

    const registryUnavailable = payload.rows.find((row) => row.case_id === "skill_registry_unavailable");
    assert.ok(registryUnavailable);
    assert.equal(registryUnavailable.ready, true);

    const notRegistered = payload.rows.find((row) => row.case_id === "skill_not_registered");
    assert.ok(notRegistered);
    assert.equal(notRegistered.ready, true);

    const grantResume = payload.rows.find((row) => row.case_id === "grant_resume_success");
    assert.ok(grantResume);
    assert.equal(grantResume.ready, true);
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});
