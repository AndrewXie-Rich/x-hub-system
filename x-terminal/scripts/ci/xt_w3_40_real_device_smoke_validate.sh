#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORT_FILE="${1:-${XT_W3_40_REAL_SMOKE_REPORT_FILE:-${ROOT_DIR}/build/reports/xt_w3_40_real_device_smoke_evidence.v1.json}}"
REQUIRE_PASS="${XT_W3_40_REQUIRE_PASS:-0}"

REPORT_FILE="${REPORT_FILE}" REQUIRE_PASS="${REQUIRE_PASS}" node <<'NODE'
const fs = require("fs");
const path = require("path");

const reportFile = path.resolve(process.env.REPORT_FILE || "");
const requirePass = process.env.REQUIRE_PASS === "1";

if (!fs.existsSync(reportFile)) {
  throw new Error(`report file missing: ${reportFile}`);
}

const report = JSON.parse(fs.readFileSync(reportFile, "utf8"));
const requiredStepIDs = [
  "preview_voice_heads_up",
  "preview_voice_final_call",
  "preview_voice_start_now",
  "notification_fallback",
  "simulate_live_delivery",
  "refresh_meetings_after_calendar_grant",
  "real_heads_up_delivery",
  "real_final_call_delivery",
  "real_start_now_delivery",
  "active_conversation_behavior",
  "quiet_hours_behavior"
];
const validStatuses = new Set(["pending", "pass", "fail", "not_applicable"]);
const placeholderPattern = /\bfill_me\b/i;

function expect(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function isNonEmptyString(value) {
  return typeof value === "string" && value.trim() !== "";
}

function hasPlaceholder(value) {
  return typeof value === "string" && placeholderPattern.test(value);
}

expect(report.schema_version === "xt_w3_40_real_device_smoke_evidence.v1", `unexpected schema_version=${report.schema_version}`);
expect(["pending", "pass", "fail"].includes(report.status), `unexpected report status=${report.status}`);
expect(isNonEmptyString(report.claim), "claim must be non-empty");
expect(Array.isArray(report.claim_scope) && report.claim_scope.length > 0, "claim_scope must be non-empty");
expect(Array.isArray(report.contract_evidence_refs), "contract_evidence_refs must be an array");

const ctx = report.operator_run_context || {};
expect(isNonEmptyString(ctx.xt_app_path), "operator_run_context.xt_app_path must be non-empty");
expect(isNonEmptyString(ctx.device_label), "operator_run_context.device_label must be non-empty");
expect(isNonEmptyString(ctx.macos_version), "operator_run_context.macos_version must be non-empty");
expect(isNonEmptyString(ctx.run_started_at), "operator_run_context.run_started_at must be non-empty");
expect(isNonEmptyString(ctx.run_finished_at), "operator_run_context.run_finished_at must be non-empty");

const permissions = report.permission_snapshot || {};
for (const key of ["calendar", "notifications", "microphone", "speech_recognition"]) {
  expect(isNonEmptyString(permissions[key]), `permission_snapshot.${key} must be non-empty`);
}

const steps = Array.isArray(report.smoke_steps) ? report.smoke_steps : [];
expect(steps.length >= requiredStepIDs.length, "smoke_steps is missing required entries");
const stepByID = new Map(steps.map((step) => [step.id, step]));
for (const stepID of requiredStepIDs) {
  expect(stepByID.has(stepID), `missing required smoke step ${stepID}`);
}

let passedRequired = 0;
for (const stepID of requiredStepIDs) {
  const step = stepByID.get(stepID);
  expect(step.required === true, `required smoke step ${stepID} must keep required=true`);
  expect(validStatuses.has(step.status), `invalid status for ${stepID}: ${step.status}`);
  expect(isNonEmptyString(step.action), `step ${stepID} action must be non-empty`);
  expect(isNonEmptyString(step.expected_result), `step ${stepID} expected_result must be non-empty`);
  expect(Array.isArray(step.evidence_refs), `step ${stepID} evidence_refs must be an array`);
  expect(isNonEmptyString(step.detail), `step ${stepID} detail must be non-empty`);
  if (step.status === "pass") {
    passedRequired += 1;
  }
}

const summary = report.summary || {};
expect(Number(summary.required_step_count || 0) === requiredStepIDs.length, `summary.required_step_count must equal ${requiredStepIDs.length}`);
expect(Number(summary.passed_required_step_count || 0) === passedRequired, "summary.passed_required_step_count must match actual passed step count");
expect(isNonEmptyString(summary.human_summary), "summary.human_summary must be non-empty");

if (requirePass) {
  expect(report.status === "pass", "require-pass validation needs report.status=pass");
  const placeholderViolations = [];
  for (const [key, value] of Object.entries(ctx)) {
    if (hasPlaceholder(value)) placeholderViolations.push(`operator_run_context.${key}`);
  }
  for (const [key, value] of Object.entries(permissions)) {
    if (hasPlaceholder(value)) placeholderViolations.push(`permission_snapshot.${key}`);
  }
  for (const stepID of requiredStepIDs) {
    const step = stepByID.get(stepID);
    expect(step.status === "pass", `require-pass validation needs ${stepID}=pass`);
    expect(step.evidence_refs.length > 0, `require-pass validation needs evidence_refs for ${stepID}`);
    if (hasPlaceholder(step.detail)) placeholderViolations.push(`smoke_steps.${stepID}.detail`);
  }
  expect(placeholderViolations.length === 0, `require-pass validation found placeholder values: ${placeholderViolations.join(", ")}`);
}

console.log(
  `${passedRequired}/${requiredStepIDs.length} required real-device calendar smoke steps recorded` +
  ` on ${ctx.device_label} (${ctx.run_finished_at})`
);
NODE
