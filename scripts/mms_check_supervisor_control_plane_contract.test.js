#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const {
  checkMultimodalSupervisorControlPlaneContract,
} = require("./mms_check_supervisor_control_plane_contract.js");

function readJson(filePath) {
  return JSON.parse(String(fs.readFileSync(filePath, "utf8") || "{}"));
}

function readText(filePath) {
  return String(fs.readFileSync(filePath, "utf8") || "");
}

function makeTempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "mms-contract-test-"));
}

function run() {
  const repoRoot = path.resolve(__dirname, "..");
  const contractJsonPath = path.join(
    repoRoot,
    "docs/memory-new/schema/xhub_multimodal_supervisor_control_plane_contract.v1.json"
  );
  const protoPath = path.join(repoRoot, "protocol/hub_protocol_v1.proto");
  const protocolMdPath = path.join(repoRoot, "protocol/hub_protocol_v1.md");

  const baseline = checkMultimodalSupervisorControlPlaneContract({
    contractJson: readJson(contractJsonPath),
    protoText: readText(protoPath),
    protocolMarkdown: readText(protocolMdPath),
  });
  assert.equal(baseline.ok, true, `baseline contract should pass, got errors: ${baseline.errors.join("; ")}`);

  const tmpDir = makeTempDir();
  const badContract = readJson(contractJsonPath);
  badContract.route_decision_enum = ["hub_only", "hub_to_xt"];
  badContract.deny_code_dictionary = badContract.deny_code_dictionary.filter(
    (item) => item && item.deny_code !== "runtime_error"
  );
  const broken = checkMultimodalSupervisorControlPlaneContract({
    contractJson: badContract,
    protoText: readText(protoPath),
    protocolMarkdown: readText(protocolMdPath),
  });
  assert.equal(broken.ok, false, "broken contract should fail");
  assert.ok(
    broken.errors.some((msg) => msg.includes("route_decision_enum missing required value: hub_to_runner")),
    "missing hub_to_runner should be reported"
  );
  assert.ok(
    broken.errors.some((msg) => msg.includes("deny_code_dictionary missing required code: runtime_error")),
    "missing runtime_error deny code should be reported"
  );

  fs.rmSync(tmpDir, { recursive: true, force: true });
  console.log("mms_check_supervisor_control_plane_contract.test.js ok");
}

run();
