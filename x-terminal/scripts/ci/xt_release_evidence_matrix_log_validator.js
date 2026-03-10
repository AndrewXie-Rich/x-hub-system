#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

function fail(message) {
  throw new Error(message);
}

function parseArgs(argv) {
  const args = { log: "", outJson: "" };
  for (let i = 2; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === "--log") {
      args.log = argv[i + 1] || "";
      i += 1;
      continue;
    }
    if (token === "--out-json") {
      args.outJson = argv[i + 1] || "";
      i += 1;
      continue;
    }
    fail(`unknown argument: ${token}`);
  }
  return args;
}

function validateLog(payload) {
  const requiredCases = [
    "baseline_release0_auto0",
    "baseline_release0_auto1",
    "baseline_release1_auto0_fail_closed",
    "baseline_release1_auto1_auto_prepare"
  ];

  const lines = payload
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0);

  const caseStatus = new Map();
  let summaryPass = null;
  let summaryFail = null;
  let workdir = "";

  for (const line of lines) {
    let match = line.match(/^\[(PASS|FAIL)\]\s+([a-z0-9_]+)$/);
    if (match) {
      const [, status, caseName] = match;
      if (caseStatus.has(caseName)) {
        fail(`duplicate case entry: ${caseName}`);
      }
      caseStatus.set(caseName, status);
      continue;
    }

    match = line.match(/^\[matrix\]\s+workdir=(.+)$/);
    if (match) {
      workdir = match[1];
      continue;
    }

    match = line.match(/^\[matrix\]\s+pass=(\d+)\s+fail=(\d+)$/);
    if (match) {
      summaryPass = Number(match[1]);
      summaryFail = Number(match[2]);
    }
  }

  for (const name of requiredCases) {
    if (!caseStatus.has(name)) {
      fail(`missing required case: ${name}`);
    }
  }

  const extraCases = Array.from(caseStatus.keys()).filter((name) => !requiredCases.includes(name));
  if (extraCases.length > 0) {
    fail(`unexpected extra cases: ${extraCases.join(",")}`);
  }

  const failedRequired = requiredCases.filter((name) => caseStatus.get(name) !== "PASS");
  if (failedRequired.length > 0) {
    fail(`required cases not PASS: ${failedRequired.join(",")}`);
  }

  if (summaryPass === null || summaryFail === null) {
    fail("missing matrix summary line [matrix] pass=<n> fail=<n>");
  }
  if (summaryPass !== requiredCases.length || summaryFail !== 0) {
    fail(`unexpected summary counts: pass=${summaryPass}, fail=${summaryFail}`);
  }

  const parsedPass = Array.from(caseStatus.values()).filter((status) => status === "PASS").length;
  const parsedFail = Array.from(caseStatus.values()).filter((status) => status === "FAIL").length;
  if (summaryPass !== parsedPass || summaryFail !== parsedFail) {
    fail(
      `summary mismatch: summary pass/fail=${summaryPass}/${summaryFail}, parsed pass/fail=${parsedPass}/${parsedFail}`
    );
  }

  if (!workdir) {
    fail("missing matrix workdir line [matrix] workdir=...");
  }

  return {
    schema_version: "xt_release_evidence_matrix.v1",
    generated_at: new Date().toISOString(),
    workdir,
    required_cases: requiredCases,
    cases: requiredCases.map((name) => ({ name, status: caseStatus.get(name) })),
    summary: {
      pass_count: summaryPass,
      fail_count: summaryFail,
      required_case_count: requiredCases.length,
      all_required_passed: failedRequired.length === 0
    }
  };
}

function main() {
  const args = parseArgs(process.argv);
  if (!args.log) {
    fail("missing required argument --log <path>");
  }
  const logPath = path.resolve(args.log);
  if (!fs.existsSync(logPath)) {
    fail(`log file not found: ${logPath}`);
  }

  const payload = fs.readFileSync(logPath, "utf8");
  const summary = validateLog(payload);
  summary.log_path = logPath;

  if (args.outJson) {
    const outputPath = path.resolve(args.outJson);
    fs.mkdirSync(path.dirname(outputPath), { recursive: true });
    fs.writeFileSync(outputPath, `${JSON.stringify(summary, null, 2)}\n`, "utf8");
  }

  process.stdout.write(
    `[ok] matrix log validated: pass=${summary.summary.pass_count}, fail=${summary.summary.fail_count}\n`
  );
}

try {
  main();
} catch (error) {
  process.stderr.write(`[error] ${(error && error.message) || String(error)}\n`);
  process.exit(1);
}
