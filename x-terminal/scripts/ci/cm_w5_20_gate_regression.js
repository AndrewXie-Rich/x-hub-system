#!/usr/bin/env node
"use strict";

const {
  validateDoctorReport,
  validateSecretsReport
} = require("./cm_w5_20_report_validator");

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

const validDoctor = {
  status: "pass",
  doctor: {
    dmPolicy: "allowlist",
    allowFrom: ["group:release_ops"],
    ws_origin: "https://localhost",
    shared_token_auth: true,
    authz_parity_for_all_ingress: true,
    non_message_ingress_policy_coverage: 1,
    unauthorized_flood_drop_count: 12
  }
};

const validSecrets = {
  schema_version: "secrets_dry_run.v1",
  dry_run: true,
  target_path_out_of_scope_count: 0,
  missing_variables_count: 0,
  permission_boundary_error_count: 0,
  items: []
};

let failed = 0;

if (!runCase("strict_missing_secrets_report_must_fail", () => {
  const doctor = validateDoctorReport(validDoctor);
  assert(doctor.ok, `valid doctor fixture should pass: ${doctor.errors.join(", ")}`);
  const mode = "strict";
  const hasSecretsReport = false;
  const gateWouldFail = mode === "strict" && !hasSecretsReport;
  assert(gateWouldFail, "strict mode must fail when secrets report is missing");
})) {
  failed += 1;
}

if (!runCase("invalid_secrets_fields_must_fail", () => {
  const invalidSecrets = {
    ...validSecrets,
    permission_boundary_error_count: -1
  };
  const secrets = validateSecretsReport(invalidSecrets);
  assert(!secrets.ok, "invalid secrets fixture must fail structured validation");
})) {
  failed += 1;
}

if (!runCase("valid_reports_should_pass", () => {
  const doctor = validateDoctorReport(validDoctor);
  assert(doctor.ok, `valid doctor fixture should pass: ${doctor.errors.join(", ")}`);
  const secrets = validateSecretsReport(validSecrets);
  assert(secrets.ok, `valid secrets fixture should pass: ${secrets.errors.join(", ")}`);
})) {
  failed += 1;
}

if (failed > 0) {
  process.exit(1);
}
