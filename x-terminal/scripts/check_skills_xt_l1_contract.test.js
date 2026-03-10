#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const path = require("node:path");

const {
  FIXTURE_SCHEMA_VERSION,
  validateSkillsXTl1ContractFixture,
  readJSON
} = require("./check_skills_xt_l1_contract.js");

const fixturesDir = path.resolve(__dirname, "fixtures");
const validFixturePath = path.join(fixturesDir, "skills_xt_l1_contract.sample.json");
const invalidFixturePath = path.join(fixturesDir, "skills_xt_l1_contract.invalid.sample.json");

function run() {
  const validDoc = readJSON(validFixturePath);
  const validResult = validateSkillsXTl1ContractFixture(validDoc);
  assert.equal(validResult.ok, true, `valid fixture should pass: ${validResult.errors.join("; ")}`);
  assert.equal(validResult.schema_version, FIXTURE_SCHEMA_VERSION);
  assert.equal(validResult.case_count, 5);
  assert.equal(validResult.required_case_count, 5);
  assert.equal(validResult.gate_pass, true);
  assert.equal(validResult.summary.blocked_case_count, 3);
  assert.equal(validResult.summary.rollback_case_count, 1);
  assert.equal(validResult.summary.preflight_failed_case_count, 2);
  assert.equal(validResult.summary.grant_pending_case_count, 1);
  assert.equal(validResult.summary.import_to_first_run_p95_ms, 10340);
  assert.equal(validResult.summary.skill_first_run_success_rate, 0.4);
  assert.equal(validResult.summary.preflight_false_positive_rate, 0);
  assert.equal(validResult.kpi_snapshot.import_to_first_run_p95_ms, 10920);
  assert.equal(validResult.kpi_snapshot.skill_first_run_success_rate, 0.96);
  assert.equal(validResult.kpi_snapshot.preflight_false_positive_rate, 0.02);

  const mismatchDoc = JSON.parse(JSON.stringify(validDoc));
  mismatchDoc.cases[2].trace[3].decision = "not_required";
  const mismatchResult = validateSkillsXTl1ContractFixture(mismatchDoc);
  assert.equal(mismatchResult.ok, false, "grant-pending mismatch should fail");
  assert(
    mismatchResult.errors.some((line) => line.includes("grant stage must be grant_pending")),
    "mismatch fixture should report grant_pending rule violation"
  );

  const invalidDoc = readJSON(invalidFixturePath);
  const invalidResult = validateSkillsXTl1ContractFixture(invalidDoc);
  assert.equal(invalidResult.ok, false, "invalid fixture should fail");
  assert(
    invalidResult.errors.some((line) => line.includes("schema_version")),
    "invalid fixture should report schema_version mismatch"
  );
  assert(
    invalidResult.errors.some((line) => line.includes("missing required stage 'risk_classify'")),
    "invalid fixture should report missing chain stage"
  );
  assert(
    invalidResult.errors.some((line) => line.includes("secret-like token detected")),
    "invalid fixture should report secret leak in fix card"
  );
  assert(
    invalidResult.errors.some((line) => line.includes("must be pass")),
    "invalid fixture should report gate or status drift"
  );

  console.log("[skills-xt-l1-contract-test] all assertions passed");
}

run();
