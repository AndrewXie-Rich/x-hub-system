#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const {
  checkLineageContractCoverage,
} = require("./m3_check_lineage_contract_tests.js");

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

const SAMPLE_FREEZE = [
  "## 3) deny_code 字典（冻结）",
  "",
  "| deny_code | 触发条件 |",
  "|---|---|",
  "| `invalid_request` | ... |",
  "| `permission_denied` | ... |",
  "| `dispatch_rejected` | ... |",
  "",
  "## 4) 边界",
].join("\n");

const SAMPLE_CONTRACT = [
  "## 4) Contract Test Matrix（按 deny_code 分组）",
  "",
  "### 4.1 `invalid_request`",
  "| Test ID | RPC | 输入摘要 | 期望响应 |",
  "|---|---|---|---|",
  "| CT-LIN-D005 | UpsertProjectLineage | ... | deny |",
  "",
  "### 4.2 `permission_denied`",
  "| Test ID | RPC | 输入摘要 | 期望响应 |",
  "|---|---|---|---|",
  "| CT-LIN-D006 | UpsertProjectLineage | ... | deny |",
  "",
  "### 4.3 `dispatch_rejected`",
  "| Test ID | RPC | 输入摘要 | 期望响应 |",
  "|---|---|---|---|",
  "| CT-DIS-D007 | AttachDispatchContext | ... | deny |",
  "",
  "## 5) 成功路径最小集合",
  "| Test ID | RPC | 输入摘要 | 期望响应 |",
  "|---|---|---|---|",
  "| CT-LIN-S001 | UpsertProjectLineage | ... | accept |",
  "",
  "## 7) 当前实现映射",
  "- 已覆盖分组：",
  "  - `invalid_request`",
  "  - `permission_denied`",
  "  - `dispatch_rejected`",
].join("\n");

run("M3-W1-03/checkLineageContractCoverage passes when freeze/contract/test-source aligned", () => {
  const source = [
    "// CT-LIN-D005",
    "assert.equal(String(res.deny_code || ''), 'invalid_request');",
    "assertAuditEvent(db, { error_code: 'invalid_request' });",
    "// CT-LIN-D006",
    "assert.equal(String(res.deny_code || ''), 'permission_denied');",
    "assertAuditEvent(db, { error_code: 'permission_denied' });",
    "// CT-DIS-D007",
    "assert.equal(String(res.deny_code || ''), 'dispatch_rejected');",
    "assertAuditEvent(db, { error_code: 'dispatch_rejected' });",
    "// CT-LIN-S001",
  ].join("\n");

  const report = checkLineageContractCoverage({
    freezeMarkdown: SAMPLE_FREEZE,
    contractMarkdown: SAMPLE_CONTRACT,
    testSource: source,
  });

  assert.equal(report.ok, true, report.errors.join(" | "));
  assert.equal(report.summary.required_deny_code_total, 3);
  assert.equal(report.summary.contract_test_id_total, 4);
  assert.equal(report.summary.source_response_deny_code_total, 3);
  assert.equal(report.summary.source_audit_error_code_total, 3);
  assert.equal(report.summary.duplicate_contract_test_id_total, 0);
});

run("M3-W1-03/checkLineageContractCoverage fails when required deny_code missing in response assertion", () => {
  const source = [
    "// CT-LIN-D005",
    "assert.equal(String(res.deny_code || ''), 'invalid_request');",
    "assertAuditEvent(db, { error_code: 'invalid_request' });",
    "// CT-LIN-D006",
    "assertAuditEvent(db, { error_code: 'permission_denied' });",
    "// CT-DIS-D007",
    "assert.equal(String(res.deny_code || ''), 'dispatch_rejected');",
    "assertAuditEvent(db, { error_code: 'dispatch_rejected' });",
    "// CT-LIN-S001",
  ].join("\n");

  const report = checkLineageContractCoverage({
    freezeMarkdown: SAMPLE_FREEZE,
    contractMarkdown: SAMPLE_CONTRACT,
    testSource: source,
  });

  assert.equal(report.ok, false);
  assert.equal(
    report.errors.some((line) => line.includes("required deny_code not asserted in response deny_code path: permission_denied")),
    true
  );
});

run("M3-W1-03/checkLineageContractCoverage fails when required deny_code missing in audit assertion", () => {
  const source = [
    "// CT-LIN-D005",
    "assert.equal(String(res.deny_code || ''), 'invalid_request');",
    "assertAuditEvent(db, { error_code: 'invalid_request' });",
    "// CT-LIN-D006",
    "assert.equal(String(res.deny_code || ''), 'permission_denied');",
    "// CT-DIS-D007",
    "assert.equal(String(res.deny_code || ''), 'dispatch_rejected');",
    "assertAuditEvent(db, { error_code: 'dispatch_rejected' });",
    "// CT-LIN-S001",
  ].join("\n");

  const report = checkLineageContractCoverage({
    freezeMarkdown: SAMPLE_FREEZE,
    contractMarkdown: SAMPLE_CONTRACT,
    testSource: source,
  });

  assert.equal(report.ok, false);
  assert.equal(
    report.errors.some((line) => line.includes("required deny_code not asserted in audit error_code path: permission_denied")),
    true
  );
});

run("M3-W1-03/checkLineageContractCoverage fails when CT-ID to deny_code mapping drifts", () => {
  const source = [
    "// CT-LIN-D005",
    "assert.equal(String(res.deny_code || ''), 'invalid_request');",
    "assertAuditEvent(db, { error_code: 'invalid_request' });",
    "// CT-LIN-D006",
    "assert.equal(String(res.deny_code || ''), 'invalid_request');",
    "assertAuditEvent(db, { error_code: 'invalid_request' });",
    "// CT-DIS-D007",
    "assert.equal(String(res.deny_code || ''), 'dispatch_rejected');",
    "assertAuditEvent(db, { error_code: 'dispatch_rejected' });",
    "// CT-LIN-S001",
    "assert.equal(String(other.deny_code || ''), 'permission_denied');",
    "assertAuditEvent(db, { error_code: 'permission_denied' });",
  ].join("\n");

  const report = checkLineageContractCoverage({
    freezeMarkdown: SAMPLE_FREEZE,
    contractMarkdown: SAMPLE_CONTRACT,
    testSource: source,
  });

  assert.equal(report.ok, false);
  assert.equal(
    report.errors.some((line) =>
      line.includes("contract deny test id mapped to deny_code mismatch in response path: CT-LIN-D006 -> permission_denied")
    ),
    true
  );
  assert.equal(
    report.errors.some((line) =>
      line.includes("contract deny test id mapped to deny_code mismatch in audit path: CT-LIN-D006 -> permission_denied")
    ),
    true
  );
});

run("M3-W1-03/checkLineageContractCoverage fails when deny group uses non-deny CT-ID", () => {
  const contractWrongDenyId = SAMPLE_CONTRACT.replace("CT-LIN-D006", "CT-LIN-S001");
  const source = [
    "// CT-LIN-D005",
    "assert.equal(String(res.deny_code || ''), 'invalid_request');",
    "assertAuditEvent(db, { error_code: 'invalid_request' });",
    "// CT-LIN-S001",
    "assert.equal(String(res.deny_code || ''), 'permission_denied');",
    "assertAuditEvent(db, { error_code: 'permission_denied' });",
    "// CT-DIS-D007",
    "assert.equal(String(res.deny_code || ''), 'dispatch_rejected');",
    "assertAuditEvent(db, { error_code: 'dispatch_rejected' });",
  ].join("\n");

  const report = checkLineageContractCoverage({
    freezeMarkdown: SAMPLE_FREEZE,
    contractMarkdown: contractWrongDenyId,
    testSource: source,
  });

  assert.equal(report.ok, false);
  assert.equal(
    report.errors.some((line) =>
      line.includes("contract deny_code group contains non-deny test id: permission_denied -> CT-LIN-S001")
    ),
    true
  );
});

run("M3-W1-03/checkLineageContractCoverage fails when freeze dictionary has duplicate deny_code rows", () => {
  const freezeWithDuplicate = SAMPLE_FREEZE.replace(
    "| `dispatch_rejected` | ... |",
    "| `dispatch_rejected` | ... |\n| `invalid_request` | duplicate |"
  );
  const source = [
    "// CT-LIN-D005",
    "assert.equal(String(res.deny_code || ''), 'invalid_request');",
    "assertAuditEvent(db, { error_code: 'invalid_request' });",
    "// CT-LIN-D006",
    "assert.equal(String(res.deny_code || ''), 'permission_denied');",
    "assertAuditEvent(db, { error_code: 'permission_denied' });",
    "// CT-DIS-D007",
    "assert.equal(String(res.deny_code || ''), 'dispatch_rejected');",
    "assertAuditEvent(db, { error_code: 'dispatch_rejected' });",
    "// CT-LIN-S001",
  ].join("\n");

  const report = checkLineageContractCoverage({
    freezeMarkdown: freezeWithDuplicate,
    contractMarkdown: SAMPLE_CONTRACT,
    testSource: source,
  });

  assert.equal(report.ok, false);
  assert.equal(
    report.errors.some((line) => line.includes("duplicate freeze deny_code entry(s): invalid_request")),
    true
  );
});

run("M3-W1-03/checkLineageContractCoverage fails when contract has duplicate deny_code group headings", () => {
  const contractWithDuplicateGroup = [
    SAMPLE_CONTRACT,
    "",
    "### 4.4 `permission_denied`",
    "| Test ID | RPC | 输入摘要 | 期望响应 |",
    "|---|---|---|---|",
    "| CT-LIN-D106 | UpsertProjectLineage | ... | deny |",
  ].join("\n");

  const source = [
    "// CT-LIN-D005",
    "assert.equal(String(res.deny_code || ''), 'invalid_request');",
    "assertAuditEvent(db, { error_code: 'invalid_request' });",
    "// CT-LIN-D006",
    "assert.equal(String(res.deny_code || ''), 'permission_denied');",
    "assertAuditEvent(db, { error_code: 'permission_denied' });",
    "// CT-LIN-D106",
    "assert.equal(String(res.deny_code || ''), 'permission_denied');",
    "assertAuditEvent(db, { error_code: 'permission_denied' });",
    "// CT-DIS-D007",
    "assert.equal(String(res.deny_code || ''), 'dispatch_rejected');",
    "assertAuditEvent(db, { error_code: 'dispatch_rejected' });",
    "// CT-LIN-S001",
  ].join("\n");

  const report = checkLineageContractCoverage({
    freezeMarkdown: SAMPLE_FREEZE,
    contractMarkdown: contractWithDuplicateGroup,
    testSource: source,
  });

  assert.equal(report.ok, false);
  assert.equal(
    report.errors.some((line) => line.includes("duplicate contract deny_code group heading(s): permission_denied")),
    true
  );
});

run("M3-W1-03/checkLineageContractCoverage fails when source CT-ID block duplicates", () => {
  const source = [
    "// CT-LIN-D005",
    "assert.equal(String(res.deny_code || ''), 'invalid_request');",
    "assertAuditEvent(db, { error_code: 'invalid_request' });",
    "// CT-LIN-D006",
    "assert.equal(String(res.deny_code || ''), 'permission_denied');",
    "assertAuditEvent(db, { error_code: 'permission_denied' });",
    "// CT-LIN-D006",
    "assert.equal(String(res.deny_code || ''), 'permission_denied');",
    "assertAuditEvent(db, { error_code: 'permission_denied' });",
    "// CT-DIS-D007",
    "assert.equal(String(res.deny_code || ''), 'dispatch_rejected');",
    "assertAuditEvent(db, { error_code: 'dispatch_rejected' });",
    "// CT-LIN-S001",
  ].join("\n");

  const report = checkLineageContractCoverage({
    freezeMarkdown: SAMPLE_FREEZE,
    contractMarkdown: SAMPLE_CONTRACT,
    testSource: source,
  });

  assert.equal(report.ok, false);
  assert.equal(
    report.errors.some((line) => line.includes("duplicate source deny test id block(s): CT-LIN-D006")),
    true
  );
  assert.equal(
    report.errors.some((line) => line.includes("contract deny test id has duplicate source blocks: CT-LIN-D006")),
    true
  );
});

run("M3-W1-03/checkLineageContractCoverage fails when deny CT block asserts multiple deny codes", () => {
  const source = [
    "// CT-LIN-D005",
    "assert.equal(String(res.deny_code || ''), 'invalid_request');",
    "assertAuditEvent(db, { error_code: 'invalid_request' });",
    "// CT-LIN-D006",
    "assert.equal(String(res.deny_code || ''), 'permission_denied');",
    "assert.equal(String(other.deny_code || ''), 'invalid_request');",
    "assertAuditEvent(db, { error_code: 'permission_denied' });",
    "assertAuditEvent(db, { error_code: 'invalid_request' });",
    "// CT-DIS-D007",
    "assert.equal(String(res.deny_code || ''), 'dispatch_rejected');",
    "assertAuditEvent(db, { error_code: 'dispatch_rejected' });",
    "// CT-LIN-S001",
  ].join("\n");

  const report = checkLineageContractCoverage({
    freezeMarkdown: SAMPLE_FREEZE,
    contractMarkdown: SAMPLE_CONTRACT,
    testSource: source,
  });

  assert.equal(report.ok, false);
  assert.equal(
    report.errors.some((line) =>
      line.includes("contract deny test id response deny_code assertions must be exactly 1: CT-LIN-D006")
    ),
    true
  );
  assert.equal(
    report.errors.some((line) =>
      line.includes("contract deny test id audit error_code assertions must be exactly 1: CT-LIN-D006")
    ),
    true
  );
});

run("M3-W1-03/checkLineageContractCoverage fails when contract deny_code is not frozen", () => {
  const contractWithUnknown = `${SAMPLE_CONTRACT}\n\n### 4.3 \`lineage_cycle_detected\`\n| Test ID | RPC |\n|---|---|\n| CT-LIN-D002 | Upsert |\n`;
  const source = [
    "// CT-LIN-D005",
    "// CT-LIN-D006",
    "// CT-DIS-D007",
    "// CT-LIN-D002",
    "// CT-LIN-S001",
    "assert.equal(x, 'invalid_request');",
    "assert.equal(x, 'permission_denied');",
    "assert.equal(x, 'dispatch_rejected');",
    "assert.equal(x, 'lineage_cycle_detected');",
    "assertAuditEvent(db, { error_code: 'invalid_request' });",
    "assertAuditEvent(db, { error_code: 'permission_denied' });",
    "assertAuditEvent(db, { error_code: 'dispatch_rejected' });",
    "assertAuditEvent(db, { error_code: 'lineage_cycle_detected' });",
  ].join("\n");

  const report = checkLineageContractCoverage({
    freezeMarkdown: SAMPLE_FREEZE,
    contractMarkdown: contractWithUnknown,
    testSource: source,
  });

  assert.equal(report.ok, false);
  assert.equal(
    report.errors.some((line) => line.includes("contract deny_code group not present in freeze dictionary: lineage_cycle_detected")),
    true
  );
});

run("M3-W1-03/checkLineageContractCoverage fails when source asserts deny_code not declared in contract groups", () => {
  const source = [
    "// CT-LIN-D005",
    "assert.equal(String(res.deny_code || ''), 'invalid_request');",
    "assertAuditEvent(db, { error_code: 'invalid_request' });",
    "// CT-LIN-D006",
    "assert.equal(String(res.deny_code || ''), 'permission_denied');",
    "assertAuditEvent(db, { error_code: 'permission_denied' });",
    "// CT-DIS-D007",
    "assert.equal(String(res.deny_code || ''), 'dispatch_rejected');",
    "assertAuditEvent(db, { error_code: 'dispatch_rejected' });",
    "// CT-LIN-S001",
    "assert.equal(String(other.deny_code || ''), 'lineage_root_mismatch');",
    "assertAuditEvent(db, { error_code: 'lineage_root_mismatch' });",
  ].join("\n");

  const report = checkLineageContractCoverage({
    freezeMarkdown: SAMPLE_FREEZE,
    contractMarkdown: SAMPLE_CONTRACT,
    testSource: source,
  });

  assert.equal(report.ok, false);
  assert.equal(
    report.errors.some((line) => line.includes("source response deny_code missing contract group section: lineage_root_mismatch")),
    true
  );
  assert.equal(
    report.errors.some((line) => line.includes("source audit error_code missing contract group section: lineage_root_mismatch")),
    true
  );
});

run("M3-W1-03/checkLineageContractCoverage fails when source CT-ID is missing from contract doc", () => {
  const source = [
    "// CT-LIN-D005",
    "assert.equal(String(res.deny_code || ''), 'invalid_request');",
    "assertAuditEvent(db, { error_code: 'invalid_request' });",
    "// CT-LIN-D006",
    "assert.equal(String(res.deny_code || ''), 'permission_denied');",
    "assertAuditEvent(db, { error_code: 'permission_denied' });",
    "// CT-DIS-D007",
    "assert.equal(String(res.deny_code || ''), 'dispatch_rejected');",
    "assertAuditEvent(db, { error_code: 'dispatch_rejected' });",
    "// CT-LIN-S001",
    "// CT-LIN-D099",
    "assert.equal(Boolean(flag), true);",
  ].join("\n");

  const report = checkLineageContractCoverage({
    freezeMarkdown: SAMPLE_FREEZE,
    contractMarkdown: SAMPLE_CONTRACT,
    testSource: source,
  });

  assert.equal(report.ok, false);
  assert.equal(
    report.errors.some((line) => line.includes("source test id missing from contract doc: CT-LIN-D099")),
    true
  );
});

run("M3-W1-03/cli writes json report and validates gate", () => {
  const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), "m3_gate_ct_"));
  const freezePath = path.join(tmpRoot, "freeze.md");
  const contractPath = path.join(tmpRoot, "contract.md");
  const sourcePath = path.join(tmpRoot, "lineage.test.js");
  const outJson = path.join(tmpRoot, "report.json");

  fs.writeFileSync(freezePath, SAMPLE_FREEZE, "utf8");
  fs.writeFileSync(contractPath, SAMPLE_CONTRACT, "utf8");
  fs.writeFileSync(sourcePath, [
    "// CT-LIN-D005",
    "assert.equal(String(res.deny_code || ''), 'invalid_request');",
    "assertAuditEvent(db, { error_code: 'invalid_request' });",
    "// CT-LIN-D006",
    "assert.equal(String(res.deny_code || ''), 'permission_denied');",
    "assertAuditEvent(db, { error_code: 'permission_denied' });",
    "// CT-DIS-D007",
    "assert.equal(String(res.deny_code || ''), 'dispatch_rejected');",
    "assertAuditEvent(db, { error_code: 'dispatch_rejected' });",
    "// CT-LIN-S001",
  ].join("\n"), "utf8");

  const scriptPath = path.join(__dirname, "m3_check_lineage_contract_tests.js");
  const proc = spawnSync(process.execPath, [
    scriptPath,
    "--freeze-doc",
    freezePath,
    "--contract-doc",
    contractPath,
    "--test-source",
    sourcePath,
    "--out-json",
    outJson,
  ], {
    encoding: "utf8",
  });

  assert.equal(proc.status, 0, proc.stderr || proc.stdout);
  assert.equal(fs.existsSync(outJson), true);
  const report = JSON.parse(fs.readFileSync(outJson, "utf8"));
  assert.equal(report.ok, true);
  assert.equal(report.summary.source_test_id_total, 4);
});
