#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const { checkSkillsGrantChainContract } = require("./m3_check_skills_grant_chain_contract.js");

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

function readJson(filePath) {
  return JSON.parse(String(fs.readFileSync(filePath, "utf8") || "{}"));
}

function makeTmp(label, suffix = ".json") {
  const token = `${label}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  return path.join(os.tmpdir(), `${token}${suffix}`);
}

const CONTRACT_JSON = path.resolve("docs/memory-new/schema/xhub_skills_capability_grant_chain_contract.v1.json");

run("Hub-L3 contract checker passes canonical contract json", () => {
  const payload = readJson(CONTRACT_JSON);
  const report = checkSkillsGrantChainContract(payload);
  assert.equal(report.ok, true, report.errors.join(" | "));
  assert.equal(report.summary.capability_mapping_total >= 10, true);
  assert.equal(report.summary.incident_semantics_total >= 3, true);
});

run("Hub-L3 contract checker fails when required incident template is removed", () => {
  const payload = readJson(CONTRACT_JSON);
  payload.incident_semantics = (payload.incident_semantics || []).filter((row) => String(row.incident_code || "") !== "grant_pending");
  const report = checkSkillsGrantChainContract(payload);
  assert.equal(report.ok, false);
  assert.equal(report.errors.some((line) => line.includes("missing incident_semantics for grant_pending")), true);
});

run("Hub-L3 contract checker fails when capability scope is invalid", () => {
  const payload = readJson(CONTRACT_JSON);
  payload.capability_scope_map = Array.isArray(payload.capability_scope_map) ? payload.capability_scope_map.slice() : [];
  payload.capability_scope_map[0] = {
    ...(payload.capability_scope_map[0] || {}),
    required_grant_scope: "unsafe_scope",
  };
  const report = checkSkillsGrantChainContract(payload);
  assert.equal(report.ok, false);
  assert.equal(
    report.errors.some((line) => line.includes("unsupported required_grant_scope")),
    true
  );
});

run("CLI writes machine-readable report json", () => {
  const outJson = makeTmp("hubl3_contract_report");
  const proc = spawnSync(
    process.execPath,
    [
      path.resolve("scripts/m3_check_skills_grant_chain_contract.js"),
      "--contract-json",
      CONTRACT_JSON,
      "--out-json",
      outJson,
    ],
    { encoding: "utf8" }
  );
  assert.equal(proc.status, 0, `stdout=${proc.stdout}\nstderr=${proc.stderr}`);
  const report = readJson(outJson);
  assert.equal(report.ok, true);
  assert.equal(String(report.contract_json || ""), CONTRACT_JSON);
  try {
    fs.rmSync(outJson, { force: true });
  } catch {
    // ignore
  }
});
