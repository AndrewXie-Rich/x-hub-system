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

run("W8-C3 preflight gate evidence stays ready", () => {
  const repoRoot = path.resolve(__dirname, "..");
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "w8-c3-preflight-evidence-"));
  try {
    const outputPath = path.join(tempRoot, "w8_c3_preflight_gate_evidence.v1.json");
    const result = childProcess.spawnSync(process.execPath, [
      path.join(repoRoot, "scripts", "generate_w8_c3_preflight_gate_evidence.js"),
      "--out", outputPath,
    ], {
      cwd: repoRoot,
      encoding: "utf8",
    });
    assert.equal(result.status, 0, result.stderr || result.stdout);

    const payload = JSON.parse(fs.readFileSync(outputPath, "utf8"));
    assert.equal(payload.status, "ready");
    assert.equal(payload.categories.missing_bin_env_config, true);
    assert.equal(payload.categories.high_risk_capability_grant_missing, true);
    assert.equal(payload.categories.skill_quarantined, true);
    assert.equal(payload.categories.execute_path_preflight_gate, true);

    const missing = payload.rows.find((row) => row.case_id === "missing_bin_env_config");
    assert.ok(missing);
    assert.equal(missing.deny_code, "preflight_failed");
    assert.equal(missing.ready, true);

    const grant = payload.rows.find((row) => row.case_id === "capability_grant_missing");
    assert.ok(grant);
    assert.equal(grant.deny_code, "grant_required");
    assert.equal(grant.ready, true);

    const quarantined = payload.rows.find((row) => row.case_id === "skill_quarantined");
    assert.ok(quarantined);
    assert.equal(quarantined.deny_code, "preflight_quarantined");
    assert.equal(quarantined.ready, true);
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});
