#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const path = require("node:path");

const {
  FIXTURE_SCHEMA_VERSION,
  validateSplitFlowSnapshotFixture,
  readJSON
} = require("./check_split_flow_snapshot_fixture_contract.js");

const fixturesDir = path.resolve(__dirname, "fixtures");
const validFixturePath = path.join(fixturesDir, "split_flow_snapshot.sample.json");
const invalidFixturePath = path.join(fixturesDir, "split_flow_snapshot.invalid.sample.json");

function run() {
  const validDoc = readJSON(validFixturePath);
  const validResult = validateSplitFlowSnapshotFixture(validDoc);
  assert.equal(validResult.ok, true, `valid fixture should pass: ${validResult.errors.join("; ")}`);
  assert.equal(validResult.schema_version, FIXTURE_SCHEMA_VERSION);
  assert.equal(validResult.snapshot_count, 4);
  assert.equal(validResult.summary.flow_state_counts.proposed, 1);
  assert.equal(validResult.summary.flow_state_counts.overridden, 1);
  assert.equal(validResult.summary.flow_state_counts.blocked, 1);
  assert.equal(validResult.summary.flow_state_counts.confirmed, 1);
  assert.equal(validResult.summary.override_total, 2);
  assert.equal(validResult.summary.prompt_status_counts.rejected, 1);
  assert.equal(validResult.summary.unique_override_lane_id_count, 1);

  const mismatchDoc = JSON.parse(JSON.stringify(validDoc));
  mismatchDoc.snapshots[1].snapshot.overrideCount = 2;
  const mismatchResult = validateSplitFlowSnapshotFixture(mismatchDoc);
  assert.equal(mismatchResult.ok, false, "override count mismatch fixture should fail");
  assert(
    mismatchResult.errors.some((line) => line.includes("overrideCount (2)")),
    "mismatch fixture should report overrideCount mismatch"
  );

  const invalidDoc = readJSON(invalidFixturePath);
  const invalidResult = validateSplitFlowSnapshotFixture(invalidDoc);
  assert.equal(invalidResult.ok, false, "invalid fixture should fail");
  assert(
    invalidResult.errors.some((line) => line.includes("schema_version must be")),
    "invalid fixture should report schema_version mismatch"
  );
  assert(
    invalidResult.errors.some((line) => line.includes("stateMachineVersion must be")),
    "invalid fixture should report stateMachineVersion mismatch"
  );
  assert(
    invalidResult.errors.some((line) => line.includes("transition idle -> confirmed")),
    "invalid fixture should report invalid transition"
  );
  assert(
    invalidResult.errors.some((line) => line.includes("lastAuditAt must be null or ISO8601")),
    "invalid fixture should report invalid date format"
  );

  console.log("[split-flow-snapshot-contract-test] all assertions passed");
}

run();
