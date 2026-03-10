#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const cp = require("node:child_process");

const fixturesDir = path.resolve(__dirname, "fixtures");
const sampleFixturePath = path.join(fixturesDir, "split_flow_snapshot.sample.json");
const checker = path.resolve(__dirname, "check_split_flow_snapshot_generation_regression.js");

function writeJSON(filePath, payload) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
}

function run() {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "split-flow-regression-"));
  try {
    const sample = JSON.parse(fs.readFileSync(sampleFixturePath, "utf8"));
    const generatedPath = path.join(tempDir, "generated.json");
    writeJSON(generatedPath, sample);

    const pass = cp.spawnSync(
      process.execPath,
      [checker, "--generated", generatedPath, "--sample", sampleFixturePath],
      { encoding: "utf8" }
    );
    assert.equal(pass.status, 0, `regression check should pass: ${pass.stderr}`);

    const mismatch = JSON.parse(JSON.stringify(sample));
    mismatch.snapshots[2].snapshot.promptBlockingLintCodes.push("extra_lint_issue");
    writeJSON(generatedPath, mismatch);

    const fail = cp.spawnSync(
      process.execPath,
      [checker, "--generated", generatedPath, "--sample", sampleFixturePath],
      { encoding: "utf8" }
    );
    assert.notEqual(fail.status, 0, "regression check should fail on normalized mismatch");
    assert(
      fail.stderr.includes("normalized runtime fixture mismatch"),
      "regression check should explain mismatch reason"
    );

    console.log("[split-flow-gen-regression-test] all assertions passed");
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

run();
