#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

function writeText(root, relPath, text) {
  const absPath = path.join(root, relPath);
  fs.mkdirSync(path.dirname(absPath), { recursive: true });
  fs.writeFileSync(absPath, text, "utf8");
}

function writeJson(root, relPath, payload) {
  writeText(root, relPath, `${JSON.stringify(payload, null, 2)}\n`);
}

function stubNodeScript(root, relPath) {
  writeText(
    root,
    relPath,
    [
      "#!/usr/bin/env node",
      'const fs = require("node:fs");',
      'const path = require("node:path");',
      "const root = path.resolve(__dirname, '..');",
      "const logPath = path.join(root, 'build', 'refresh_invocations.log');",
      "fs.mkdirSync(path.dirname(logPath), { recursive: true });",
      "fs.appendFileSync(logPath, `${path.basename(__filename)}\\n`, 'utf8');",
      "",
    ].join("\n")
  );
}

function stubPythonScript(root, relPath) {
  writeText(
    root,
    relPath,
    [
      "#!/usr/bin/env python3",
      "from pathlib import Path",
      "root = Path(__file__).resolve().parents[1]",
      "log_path = root / 'build' / 'refresh_invocations.log'",
      "log_path.parent.mkdir(parents=True, exist_ok=True)",
      "with log_path.open('a', encoding='utf-8') as handle:",
      "    handle.write(f\"{Path(__file__).name}\\n\")",
      "",
    ].join("\n")
  );
}

function makeTempRefreshFixture({ xtReadyReportRef, xtReadySourceRef, connectorGateRef }) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "refresh-oss-release-"));
  const sourceScript = path.join(__dirname, "refresh_oss_release_evidence.sh");
  writeText(root, "scripts/refresh_oss_release_evidence.sh", fs.readFileSync(sourceScript, "utf8"));

  writeJson(root, "build/reports/lpr_w3_03_a_require_real_evidence.v1.json", { status: "pass" });
  writeJson(root, "build/reports/xhub_doctor_source_gate_summary.v1.json", { status: "pass" });
  writeJson(root, "build/reports/xhub_doctor_hub_local_service_snapshot_smoke_evidence.v1.json", { status: "pass" });
  writeJson(root, "x-terminal/.axcoder/reports/xt-report-index.json", { release_decision: "GO" });
  writeText(root, "x-terminal/.axcoder/reports/xt-gate-report.md", "- decision: GO\n");
  writeJson(root, "x-terminal/.axcoder/reports/xt-rollback-last.json", { status: "pass" });
  writeJson(root, "x-terminal/.axcoder/reports/xt-rollback-verify.json", { status: "pass" });
  writeJson(root, "x-terminal/.axcoder/reports/secrets-dry-run-report.json", { status: "pass" });
  writeJson(root, xtReadyReportRef, { ok: true, require_real_audit_source: true });
  writeJson(root, xtReadySourceRef, { selected_source: "audit_export" });
  writeJson(root, connectorGateRef, { source_used: "audit", snapshot: { pass: true } });

  stubNodeScript(root, "scripts/generate_release_legacy_compat_artifacts.js");
  stubNodeScript(root, "scripts/generate_xhub_local_service_operator_recovery_report.js");
  stubNodeScript(root, "scripts/generate_xhub_operator_channel_recovery_report.js");
  stubNodeScript(root, "scripts/generate_hub_r1_release_oss_boundary_report.js");
  stubNodeScript(root, "scripts/generate_oss_secret_scrub_report.js");
  stubNodeScript(root, "scripts/generate_lpr_w4_09_c_product_exit_packet.js");
  stubNodeScript(root, "scripts/generate_oss_release_support_snippet.js");
  stubPythonScript(root, "scripts/generate_oss_release_readiness_report.py");

  return root;
}

run("refresh helper prefers require-real XT-ready evidence chain", () => {
  const root = makeTempRefreshFixture({
    xtReadyReportRef: "build/xt_ready_gate_e2e_require_real_report.json",
    xtReadySourceRef: "build/xt_ready_evidence_source.require_real.json",
    connectorGateRef: "build/connector_ingress_gate_snapshot.require_real.json",
  });

  try {
    const result = spawnSync("bash", [path.join(root, "scripts/refresh_oss_release_evidence.sh")], {
      cwd: root,
      encoding: "utf8",
    });

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.match(
      result.stdout,
      /\[refresh-oss-release-evidence\] XT-ready evidence: build\/xt_ready_gate_e2e_require_real_report\.json \+ build\/xt_ready_evidence_source\.require_real\.json \+ build\/connector_ingress_gate_snapshot\.require_real\.json/
    );
    const invocationLog = fs.readFileSync(path.join(root, "build/refresh_invocations.log"), "utf8");
    assert.match(invocationLog, /generate_release_legacy_compat_artifacts\.js/);
    assert.match(invocationLog, /generate_xhub_operator_channel_recovery_report\.js/);
    assert.match(invocationLog, /generate_oss_release_readiness_report\.py/);
    assert.match(invocationLog, /generate_lpr_w4_09_c_product_exit_packet\.js/);
    assert.match(invocationLog, /generate_oss_release_support_snippet\.js/);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

run("refresh helper falls back to db-real XT-ready evidence chain when require-real is absent", () => {
  const root = makeTempRefreshFixture({
    xtReadyReportRef: "build/xt_ready_gate_e2e_db_real_report.json",
    xtReadySourceRef: "build/xt_ready_evidence_source.db_real.json",
    connectorGateRef: "build/connector_ingress_gate_snapshot.db_real.json",
  });

  try {
    const result = spawnSync("bash", [path.join(root, "scripts/refresh_oss_release_evidence.sh")], {
      cwd: root,
      encoding: "utf8",
    });

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.match(
      result.stdout,
      /\[refresh-oss-release-evidence\] XT-ready evidence: build\/xt_ready_gate_e2e_db_real_report\.json \+ build\/xt_ready_evidence_source\.db_real\.json \+ build\/connector_ingress_gate_snapshot\.db_real\.json/
    );
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

run("refresh helper reports missing preferred connector evidence when XT-ready strict chain lacks connector snapshot", () => {
  const root = makeTempRefreshFixture({
    xtReadyReportRef: "build/xt_ready_gate_e2e_require_real_report.json",
    xtReadySourceRef: "build/xt_ready_evidence_source.require_real.json",
    connectorGateRef: "build/connector_ingress_gate_snapshot.require_real.json",
  });

  try {
    fs.rmSync(path.join(root, "build/connector_ingress_gate_snapshot.require_real.json"), {
      force: true,
    });
    const result = spawnSync("bash", [path.join(root, "scripts/refresh_oss_release_evidence.sh")], {
      cwd: root,
      encoding: "utf8",
    });

    assert.notEqual(result.status, 0);
    assert.match(
      result.stderr,
      /build\/connector_ingress_gate_snapshot\.require_real\.json \| build\/connector_ingress_gate_snapshot\.json/
    );
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
