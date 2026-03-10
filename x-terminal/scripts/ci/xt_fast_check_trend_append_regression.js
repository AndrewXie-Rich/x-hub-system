#!/usr/bin/env node
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

const appender = path.resolve(__dirname, "xt_fast_check_trend_append.js");

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

function withTempDir(fn) {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "xt_fast_check_trend_append_regression."));
  try {
    fn(tempDir);
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

function runAppender(summaryPath, historyPath, limit) {
  return spawnSync(
    process.execPath,
    [appender, "--summary", summaryPath, "--history", historyPath, "--limit", String(limit)],
    { encoding: "utf8" }
  );
}

function writeJson(filePath, payload) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function makeSummary({
  generatedAt,
  startedAt = generatedAt,
  exitCode = 0,
  overallStatus = "pass",
  swiftBuildStatus = "skipped",
  matrixValidatorStatus = "pass",
  matrixGateStatus = "skipped",
  baselineGateStatus = "skipped"
}) {
  return {
    schema_version: "xt_fast_checks.v1",
    generated_at: generatedAt,
    started_at: startedAt,
    elapsed_sec: 1,
    root: "/tmp/x-terminal",
    exit_code: exitCode,
    overall_status: overallStatus,
    config: {
      run_build: "0",
      run_validator: "1",
      run_matrix: "0",
      run_baseline_gate: "0"
    },
    steps: {
      swift_build: {
        status: swiftBuildStatus,
        note: ""
      },
      matrix_validator_regression: {
        status: matrixValidatorStatus,
        note: ""
      },
      baseline_matrix_gate: {
        status: matrixGateStatus,
        note: ""
      },
      baseline_gate: {
        status: baselineGateStatus,
        note: ""
      }
    }
  };
}

let failed = 0;

if (!runCase("valid_summary_should_append_history", () => {
  withTempDir((tempDir) => {
    const summaryPath = path.join(tempDir, "summary.json");
    const historyPath = path.join(tempDir, "history.json");
    writeJson(
      summaryPath,
      makeSummary({
        generatedAt: "2026-03-01T00:00:01Z",
        overallStatus: "pass",
        exitCode: 0
      })
    );

    const result = runAppender(summaryPath, historyPath, 20);
    assert(result.status === 0, `append should pass: ${result.stderr || result.stdout}`);

    const history = readJson(historyPath);
    assert(history.schema_version === "xt_fast_check_history.v1", "unexpected history schema");
    assert(history.total_entries === 1, `total_entries must be 1, got ${history.total_entries}`);
    assert((history.overview || {}).pass_count === 1, "overview pass_count must be 1");
    assert((history.overview || {}).fail_count === 0, "overview fail_count must be 0");
    assert((history.overview || {}).warn_step_runs === 0, "overview warn_step_runs must be 0");
    assert((history.latest_entry || {}).overall_status === "pass", "latest_entry overall_status must be pass");
    assert(
      (((history.step_status_counts || {}).matrix_validator_regression || {}).pass || 0) === 1,
      "matrix_validator_regression.pass must be 1"
    );
  });
})) {
  failed += 1;
}

if (!runCase("unsupported_summary_schema_should_fail", () => {
  withTempDir((tempDir) => {
    const summaryPath = path.join(tempDir, "summary_bad_schema.json");
    const historyPath = path.join(tempDir, "history.json");
    const payload = makeSummary({
      generatedAt: "2026-03-01T00:00:02Z"
    });
    payload.schema_version = "xt_fast_checks.v0";
    writeJson(summaryPath, payload);

    const result = runAppender(summaryPath, historyPath, 20);
    assert(result.status !== 0, "append should fail for unsupported schema");
    assert(
      (result.stderr || "").includes("unsupported summary schema_version"),
      `expected schema-version error in stderr, got: ${result.stderr || "(empty)"}`
    );
  });
})) {
  failed += 1;
}

if (!runCase("limit_should_keep_latest_entries", () => {
  withTempDir((tempDir) => {
    const summaryPath = path.join(tempDir, "summary.json");
    const historyPath = path.join(tempDir, "history.json");
    const summaries = [
      makeSummary({
        generatedAt: "2026-03-01T00:00:03Z",
        overallStatus: "pass",
        exitCode: 0
      }),
      makeSummary({
        generatedAt: "2026-03-01T00:00:04Z",
        overallStatus: "fail",
        exitCode: 1
      }),
      makeSummary({
        generatedAt: "2026-03-01T00:00:05Z",
        overallStatus: "pass",
        exitCode: 0
      })
    ];

    for (const summary of summaries) {
      writeJson(summaryPath, summary);
      const result = runAppender(summaryPath, historyPath, 2);
      assert(result.status === 0, `append should pass: ${result.stderr || result.stdout}`);
    }

    const history = readJson(historyPath);
    assert(history.total_entries === 2, `total_entries must be 2, got ${history.total_entries}`);
    assert(Array.isArray(history.entries), "history entries must be an array");
    assert(history.entries.length === 2, `entries length must be 2, got ${history.entries.length}`);
    assert(history.entries[0].generated_at === "2026-03-01T00:00:04Z", "oldest kept entry should be 00:00:04Z");
    assert(history.entries[1].generated_at === "2026-03-01T00:00:05Z", "latest kept entry should be 00:00:05Z");
    assert((history.overview || {}).pass_count === 1, "overview pass_count must be 1 after trim");
    assert((history.overview || {}).fail_count === 1, "overview fail_count must be 1 after trim");
    assert((history.latest_entry || {}).overall_status === "pass", "latest_entry overall_status must be pass");
  });
})) {
  failed += 1;
}

if (!runCase("warn_step_runs_should_be_counted", () => {
  withTempDir((tempDir) => {
    const summaryPath = path.join(tempDir, "summary.json");
    const historyPath = path.join(tempDir, "history.json");

    writeJson(
      summaryPath,
      makeSummary({
        generatedAt: "2026-03-01T00:00:06Z",
        overallStatus: "pass",
        exitCode: 0,
        swiftBuildStatus: "warn"
      })
    );
    let result = runAppender(summaryPath, historyPath, 20);
    assert(result.status === 0, `append should pass: ${result.stderr || result.stdout}`);

    writeJson(
      summaryPath,
      makeSummary({
        generatedAt: "2026-03-01T00:00:07Z",
        overallStatus: "pass",
        exitCode: 0,
        swiftBuildStatus: "skipped"
      })
    );
    result = runAppender(summaryPath, historyPath, 20);
    assert(result.status === 0, `append should pass: ${result.stderr || result.stdout}`);

    const history = readJson(historyPath);
    assert((history.overview || {}).warn_step_runs === 1, "overview warn_step_runs must be 1");
    assert(
      (((history.step_status_counts || {}).swift_build || {}).warn || 0) === 1,
      "swift_build.warn count must be 1"
    );
    assert(
      (((history.step_status_counts || {}).swift_build || {}).skipped || 0) === 1,
      "swift_build.skipped count must be 1"
    );
  });
})) {
  failed += 1;
}

if (failed > 0) {
  process.exit(1);
}
