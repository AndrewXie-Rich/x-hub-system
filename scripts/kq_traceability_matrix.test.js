#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const {
  buildTraceabilityMatrix,
} = require("./kq_traceability_matrix.js");

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

run("KQ-W1-02/buildTraceabilityMatrix validates mapped requirements without orphans", () => {
  const requirementsMarkdown = [
    "### RQ-001 Spec Triad Completeness (P0)",
    "",
    "### RQ-002 Requirement-Task Traceability (P0)",
    "",
    "### RQ-003 Security Invariants as Tests (P0)",
  ].join("\n");

  const tasksMarkdown = [
    "- [ ] `KQ-W1-01` Create spec triad files and ID conventions.",
    "  - requirement_ids: `RQ-001`",
    "  - property_ids: `CP-Trace-004`",
    "",
    "- [ ] `KQ-W1-02` Implement traceability matrix checker and CI validation.",
    "  - requirement_ids: `RQ-002`",
    "  - property_ids: `CP-Trace-004`",
    "",
    "- [ ] `KQ-W1-03` Add security invariants test suite.",
    "  - requirement_ids: `RQ-003`",
    "  - property_ids: `CP-Grant-001`, `CP-Secret-002`",
  ].join("\n");

  const matrix = buildTraceabilityMatrix({
    specId: "xhub-memory-quality-v1",
    requirementsMarkdown,
    tasksMarkdown,
    sourceRequirementsPath: "specs/xhub-memory-quality-v1/requirements.md",
    sourceTasksPath: "specs/xhub-memory-quality-v1/tasks.md",
  });

  assert.equal(matrix.summary.requirement_total, 3);
  assert.equal(matrix.summary.task_total, 3);
  assert.equal(matrix.summary.orphan_requirements_count, 0);
  assert.equal(matrix.summary.orphan_tasks_count, 0);
  assert.equal(matrix.summary.unknown_requirement_references_count, 0);
  assert.equal(matrix.summary.validation_passed, true);

  const mapByRequirement = new Map(matrix.requirements.map((item) => [item.requirement_id, item.mapped_task_ids]));
  assert.deepEqual(mapByRequirement.get("RQ-001"), ["KQ-W1-01"]);
  assert.deepEqual(mapByRequirement.get("RQ-002"), ["KQ-W1-02"]);
  assert.deepEqual(mapByRequirement.get("RQ-003"), ["KQ-W1-03"]);
});

run("KQ-W1-02/buildTraceabilityMatrix flags orphan task and unknown requirement references", () => {
  const requirementsMarkdown = [
    "### RQ-001 Spec Triad Completeness (P0)",
    "",
    "### RQ-002 Requirement-Task Traceability (P0)",
  ].join("\n");

  const tasksMarkdown = [
    "- [ ] `KQ-W1-01` Create spec triad files and ID conventions.",
    "  - property_ids: `CP-Trace-004`",
    "",
    "- [ ] `KQ-W1-02` Implement traceability matrix checker and CI validation.",
    "  - requirement_ids: `RQ-999`",
    "  - property_ids: `CP-Trace-004`",
  ].join("\n");

  const matrix = buildTraceabilityMatrix({
    specId: "xhub-memory-quality-v1",
    requirementsMarkdown,
    tasksMarkdown,
    sourceRequirementsPath: "specs/xhub-memory-quality-v1/requirements.md",
    sourceTasksPath: "specs/xhub-memory-quality-v1/tasks.md",
  });

  assert.equal(matrix.summary.validation_passed, false);
  assert.equal(matrix.summary.orphan_requirements_count, 2);
  assert.equal(matrix.summary.orphan_tasks_count, 2);
  assert.equal(matrix.summary.unknown_requirement_references_count, 1);
  assert.deepEqual(matrix.orphans.requirement_ids, ["RQ-001", "RQ-002"]);
  assert.deepEqual(matrix.orphans.task_ids, ["KQ-W1-01", "KQ-W1-02"]);
  assert.deepEqual(matrix.unknown_requirement_references, [{ task_id: "KQ-W1-02", requirement_id: "RQ-999" }]);
});

run("KQ-W1-02/cli check mode catches stale matrix", () => {
  const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), "kq_traceability_"));
  const specDir = path.join(tmpRoot, "spec");
  fs.mkdirSync(specDir, { recursive: true });

  const requirementsPath = path.join(specDir, "requirements.md");
  const tasksPath = path.join(specDir, "tasks.md");
  const outJsonPath = path.join(specDir, "traceability_matrix_v1.json");

  fs.writeFileSync(requirementsPath, "### RQ-001 Demo Requirement\n", "utf8");
  fs.writeFileSync(tasksPath, "- [ ] `KQ-W1-01` Demo task\n  - requirement_ids: `RQ-001`\n", "utf8");

  const scriptPath = path.join(__dirname, "kq_traceability_matrix.js");

  const firstRun = spawnSync(process.execPath, [
    scriptPath,
    "--spec-dir",
    specDir,
    "--out-json",
    outJsonPath,
  ], {
    encoding: "utf8",
  });
  assert.equal(firstRun.status, 0, `first run failed: ${firstRun.stderr}`);

  const checkPass = spawnSync(process.execPath, [
    scriptPath,
    "--spec-dir",
    specDir,
    "--out-json",
    outJsonPath,
    "--check",
    "1",
  ], {
    encoding: "utf8",
  });
  assert.equal(checkPass.status, 0, `check run should pass: ${checkPass.stderr}`);

  fs.writeFileSync(tasksPath, "- [ ] `KQ-W1-01` Demo task\n  - requirement_ids: `RQ-001`, `RQ-002`\n", "utf8");

  const checkFail = spawnSync(process.execPath, [
    scriptPath,
    "--spec-dir",
    specDir,
    "--out-json",
    outJsonPath,
    "--check",
    "1",
  ], {
    encoding: "utf8",
  });
  assert.notEqual(checkFail.status, 0, "stale matrix check should fail");
  assert.equal(checkFail.stderr.includes("stale"), true);
});
