#!/usr/bin/env node
"use strict";

const fs = require("fs");

function isNonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function asFiniteNumber(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) {
    return null;
  }
  return number;
}

function validateDoctorReport(report) {
  const errors = [];
  if (!report || typeof report !== "object" || Array.isArray(report)) {
    return { ok: false, errors: ["doctor report must be an object"] };
  }
  const doctor = report.doctor;
  if (!doctor || typeof doctor !== "object" || Array.isArray(doctor)) {
    return { ok: false, errors: ["doctor report missing doctor section"] };
  }

  if (!isNonEmptyString(doctor.dmPolicy)) {
    errors.push("doctor.dmPolicy must be a non-empty string");
  }
  if (!Array.isArray(doctor.allowFrom)) {
    errors.push("doctor.allowFrom must be an array");
  }
  if (!isNonEmptyString(doctor.ws_origin)) {
    errors.push("doctor.ws_origin must be a non-empty string");
  }
  if (typeof doctor.shared_token_auth !== "boolean") {
    errors.push("doctor.shared_token_auth must be boolean");
  }
  if (typeof doctor.authz_parity_for_all_ingress !== "boolean") {
    errors.push("doctor.authz_parity_for_all_ingress must be boolean");
  }

  const ingressCoverage = asFiniteNumber(doctor.non_message_ingress_policy_coverage);
  if (ingressCoverage === null || ingressCoverage < 0) {
    errors.push("doctor.non_message_ingress_policy_coverage must be >= 0");
  }

  const floodDropCount = asFiniteNumber(doctor.unauthorized_flood_drop_count);
  if (floodDropCount === null || floodDropCount < 0) {
    errors.push("doctor.unauthorized_flood_drop_count must be >= 0");
  }

  return { ok: errors.length === 0, errors };
}

function validateSecretsReport(report) {
  const errors = [];
  if (!report || typeof report !== "object" || Array.isArray(report)) {
    return { ok: false, errors: ["secrets report must be an object"] };
  }

  if (report.dry_run !== true) {
    errors.push("secrets report dry_run must be true");
  }

  const aggregateKeys = [
    "target_path_out_of_scope_count",
    "missing_variables_count",
    "permission_boundary_error_count"
  ];
  let hasAggregateShape = false;
  for (const key of aggregateKeys) {
    if (Object.prototype.hasOwnProperty.call(report, key)) {
      hasAggregateShape = true;
      const value = asFiniteNumber(report[key]);
      if (value === null || value < 0) {
        errors.push(`secrets report ${key} must be >= 0`);
      }
    }
  }

  const hasSimpleShape = (
    Object.prototype.hasOwnProperty.call(report, "target_path") ||
    Object.prototype.hasOwnProperty.call(report, "missing_variables") ||
    Object.prototype.hasOwnProperty.call(report, "permission_boundary")
  );

  if (hasSimpleShape) {
    if (!isNonEmptyString(report.target_path)) {
      errors.push("secrets report target_path must be a non-empty string");
    }
    if (!Array.isArray(report.missing_variables)) {
      errors.push("secrets report missing_variables must be an array");
    }
    if (!isNonEmptyString(report.permission_boundary)) {
      errors.push("secrets report permission_boundary must be a non-empty string");
    }
  }

  if (!hasAggregateShape && !hasSimpleShape) {
    errors.push("secrets report missing required aggregate or simple fields");
  }

  return { ok: errors.length === 0, errors };
}

function loadJSON(filePath) {
  const raw = fs.readFileSync(filePath, "utf8");
  return JSON.parse(raw);
}

function runCLI(argv) {
  const args = Array.from(argv);
  let kind = "";
  let file = "";
  for (let i = 0; i < args.length; i += 1) {
    if (args[i] === "--kind") {
      kind = args[i + 1] || "";
      i += 1;
    } else if (args[i] === "--file") {
      file = args[i + 1] || "";
      i += 1;
    }
  }

  if (!isNonEmptyString(kind) || !isNonEmptyString(file)) {
    console.error("usage: cm_w5_20_report_validator.js --kind doctor|secrets --file <path>");
    process.exit(2);
  }
  if (!fs.existsSync(file)) {
    console.error(`missing file: ${file}`);
    process.exit(2);
  }

  let payload;
  try {
    payload = loadJSON(file);
  } catch (error) {
    console.error(`invalid json: ${error.message}`);
    process.exit(1);
  }

  const result = kind === "doctor"
    ? validateDoctorReport(payload)
    : validateSecretsReport(payload);
  if (!result.ok) {
    console.error(result.errors.join("; "));
    process.exit(1);
  }
  process.stdout.write("ok\n");
}

module.exports = {
  validateDoctorReport,
  validateSecretsReport
};

if (require.main === module) {
  runCLI(process.argv.slice(2));
}
