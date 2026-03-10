#!/usr/bin/env node
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

const validator = path.resolve(__dirname, "xt_release_evidence_matrix_log_validator.js");

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function runCase(name, fn) {
  try {
    fn();
    process.stdout.write(`[PASS] ${name}\n`);
    return true;
  } catch (error) {
    process.stderr.write(`[FAIL] ${name}: ${error.message}\n`);
    return false;
  }
}

function withTempCase(logPayload, fn) {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "xt_matrix_validator_case."));
  const logPath = path.join(tempDir, "matrix.log");
  const summaryPath = path.join(tempDir, "summary.json");
  fs.writeFileSync(logPath, `${logPayload}\n`, "utf8");
  try {
    fn({ tempDir, logPath, summaryPath });
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

function runValidator(logPath, summaryPath) {
  return spawnSync(
    process.execPath,
    [validator, "--log", logPath, "--out-json", summaryPath],
    { encoding: "utf8" }
  );
}

const validLog = [
  "[PASS] baseline_release0_auto0",
  "[PASS] baseline_release0_auto1",
  "[PASS] baseline_release1_auto0_fail_closed",
  "[PASS] baseline_release1_auto1_auto_prepare",
  "[matrix] workdir=/tmp/xt_release_evidence_matrix.example",
  "[matrix] pass=4 fail=0"
].join("\n");

let failed = 0;

if (!runCase("valid_log_should_pass", () => {
  withTempCase(validLog, ({ logPath, summaryPath }) => {
    const result = runValidator(logPath, summaryPath);
    assert(result.status === 0, `validator should pass valid log: ${result.stderr || result.stdout}`);
    const payload = JSON.parse(fs.readFileSync(summaryPath, "utf8"));
    assert(payload.schema_version === "xt_release_evidence_matrix.v1", "unexpected summary schema");
    assert(payload.summary && payload.summary.pass_count === 4, "summary pass_count must be 4");
    assert(payload.summary && payload.summary.fail_count === 0, "summary fail_count must be 0");
  });
})) {
  failed += 1;
}

if (!runCase("missing_case_should_fail", () => {
  const logPayload = [
    "[PASS] baseline_release0_auto0",
    "[PASS] baseline_release0_auto1",
    "[PASS] baseline_release1_auto0_fail_closed",
    "[matrix] workdir=/tmp/xt_release_evidence_matrix.example",
    "[matrix] pass=3 fail=0"
  ].join("\n");

  withTempCase(logPayload, ({ logPath, summaryPath }) => {
    const result = runValidator(logPath, summaryPath);
    assert(result.status !== 0, "validator should fail when a required case is missing");
    assert(
      (result.stderr || "").includes("missing required case"),
      `missing-case error not found in stderr: ${result.stderr || "(empty)"}`
    );
  });
})) {
  failed += 1;
}

if (!runCase("summary_mismatch_should_fail", () => {
  const logPayload = [
    "[PASS] baseline_release0_auto0",
    "[PASS] baseline_release0_auto1",
    "[PASS] baseline_release1_auto0_fail_closed",
    "[PASS] baseline_release1_auto1_auto_prepare",
    "[matrix] workdir=/tmp/xt_release_evidence_matrix.example",
    "[matrix] pass=4 fail=1"
  ].join("\n");

  withTempCase(logPayload, ({ logPath, summaryPath }) => {
    const result = runValidator(logPath, summaryPath);
    assert(result.status !== 0, "validator should fail for pass/fail summary mismatch");
    assert(
      (result.stderr || "").includes("unexpected summary counts"),
      `summary-mismatch error not found in stderr: ${result.stderr || "(empty)"}`
    );
  });
})) {
  failed += 1;
}

if (!runCase("duplicate_case_should_fail", () => {
  const logPayload = [
    "[PASS] baseline_release0_auto0",
    "[PASS] baseline_release0_auto1",
    "[PASS] baseline_release0_auto1",
    "[PASS] baseline_release1_auto0_fail_closed",
    "[PASS] baseline_release1_auto1_auto_prepare",
    "[matrix] workdir=/tmp/xt_release_evidence_matrix.example",
    "[matrix] pass=4 fail=0"
  ].join("\n");

  withTempCase(logPayload, ({ logPath, summaryPath }) => {
    const result = runValidator(logPath, summaryPath);
    assert(result.status !== 0, "validator should fail for duplicate case rows");
    assert(
      (result.stderr || "").includes("duplicate case entry"),
      `duplicate-case error not found in stderr: ${result.stderr || "(empty)"}`
    );
  });
})) {
  failed += 1;
}

if (failed > 0) {
  process.exit(1);
}
