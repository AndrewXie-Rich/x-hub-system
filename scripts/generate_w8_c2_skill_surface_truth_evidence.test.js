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

run("W8-C2 skill governance surface evidence stays ready", () => {
  const repoRoot = path.resolve(__dirname, "..");
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "w8-c2-surface-evidence-"));
  try {
    const outputPath = path.join(tempRoot, "w8_c2_skill_surface_truth_evidence.v1.json");
    const result = childProcess.spawnSync(process.execPath, [
      path.join(repoRoot, "scripts", "generate_w8_c2_skill_surface_truth_evidence.js"),
      "--out", outputPath,
    ], {
      cwd: repoRoot,
      encoding: "utf8",
    });
    assert.equal(result.status, 0, result.stderr || result.stdout);

    const payload = JSON.parse(fs.readFileSync(outputPath, "utf8"));
    assert.equal(payload.status, "ready");
    assert.equal(payload.categories.supported, true);
    assert.equal(payload.categories.grant_required, true);
    assert.equal(payload.categories.partial_or_quarantined, true);

    const supported = payload.rows.find((row) => row.case_id === "supported");
    assert.ok(supported);
    assert.equal(supported.field_presence.trust_root, true);
    assert.equal(supported.field_presence.pinned_version, true);
    assert.equal(supported.field_presence.runner_requirement, true);
    assert.equal(supported.field_presence.compatibility_status, true);
    assert.equal(supported.field_presence.preflight_result, true);

    const grantRequired = payload.rows.find((row) => row.case_id === "grant_required");
    assert.ok(grantRequired);
    assert.match(String(grantRequired.preflight_result || ""), /grant required/i);

    const quarantined = payload.rows.find((row) => row.case_id === "partial_quarantined");
    assert.ok(quarantined);
    assert.match(String(quarantined.preflight_result || ""), /quarantined/i);
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});
