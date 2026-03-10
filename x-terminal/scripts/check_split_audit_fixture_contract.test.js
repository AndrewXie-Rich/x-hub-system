#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const path = require("node:path");

const {
  REQUIRED_EVENT_TYPES,
  readJSON,
  validateSplitAuditFixture
} = require("./check_split_audit_fixture_contract.js");

const fixturesDir = path.resolve(__dirname, "fixtures");
const validFixturePath = path.join(fixturesDir, "split_audit_payload_events.sample.json");
const invalidFixturePath = path.join(fixturesDir, "split_audit_payload_events.invalid.sample.json");

function run() {
  const validDoc = readJSON(validFixturePath);
  const validResult = validateSplitAuditFixture(validDoc);
  assert.equal(validResult.ok, true, `valid fixture should pass: ${validResult.errors.join("; ")}`);
  assert.equal(validResult.event_count, REQUIRED_EVENT_TYPES.length);
  assert.equal(validResult.summary.split_overridden.event_count, 1);
  assert.equal(validResult.summary.split_overridden.override_count_total, 1);
  assert.equal(validResult.summary.split_overridden.blocking_issue_total, 0);
  assert.equal(validResult.summary.split_overridden.high_risk_hard_to_soft_confirmed_total, 1);
  assert.equal(validResult.summary.split_overridden.replay_event_count, 0);
  assert.equal(validResult.summary.event_type_counts["supervisor.split.overridden"], 1);

  const mismatchDoc = JSON.parse(JSON.stringify(validDoc));
  const overridden = mismatchDoc.events.find(
    (event) => event && event.event_type === "supervisor.split.overridden"
  );
  assert(overridden, "valid fixture should include supervisor.split.overridden");
  overridden.payload.high_risk_hard_to_soft_confirmed_count = "2";
  const mismatchResult = validateSplitAuditFixture(mismatchDoc);
  assert.equal(mismatchResult.ok, false, "mismatch fixture should fail");
  assert.equal(mismatchResult.summary.split_overridden.high_risk_hard_to_soft_confirmed_total, 2);
  assert(
    mismatchResult.errors.some((line) =>
      line.includes("high_risk_hard_to_soft_confirmed_count")
    ),
    "mismatch fixture should report confirmed count mismatch"
  );

  const invalidDoc = readJSON(invalidFixturePath);
  const invalidResult = validateSplitAuditFixture(invalidDoc);
  assert.equal(invalidResult.ok, false, "invalid fixture should fail");
  assert(
    invalidResult.errors.some((line) => line.includes("payload_version must be '1'")),
    "invalid fixture should report payload version mismatch"
  );
  assert(
    invalidResult.errors.some((line) => line.includes("payload.event_type must match event_type")),
    "invalid fixture should report payload event_type mismatch"
  );
  assert(
    invalidResult.errors.some((line) => line.includes("missing required event_type")),
    "invalid fixture should report missing required event_type entries"
  );

  console.log("[split-audit-contract-test] all assertions passed");
}

run();
