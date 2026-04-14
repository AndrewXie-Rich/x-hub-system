#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const {
  run,
} = require("./m3_prepare_internal_pass_inputs.js");

function runTest(name, fn) {
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

function createFixtureRoot() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "internal-pass-prep-"));
  writeText(root, "x-terminal/.axcoder/reports/xt-gate-report.md", "PASS: XT-G0\nPASS: XT-G1\n");
  writeJson(root, "x-terminal/.axcoder/metrics/xt-kpi-latest.json", {
    queue_wait_p90_ms: 1200,
    token_budget_overrun_rate: 1.1,
  });
  writeJson(root, "x-terminal/.axcoder/reports/xt-overflow-fairness-report.json", {
    kpi_snapshot: {
      parent_fork_overflow_silent_fail: 0,
    },
  });
  writeJson(root, "x-terminal/.axcoder/reports/xt-origin-fallback-report.json", {
    kpi_snapshot: {
      route_origin_fallback_violations: 0,
    },
  });
  writeJson(root, "x-terminal/.axcoder/reports/xt-dispatch-cleanup-report.json", {
    kpi_snapshot: {
      dispatch_idle_stuck_incidents: 0,
    },
  });
  writeJson(root, "x-terminal/.axcoder/reports/doctor-report.json", {
    doctor: {
      non_message_ingress_policy_coverage: 1,
    },
  });
  writeJson(root, "build/connector_ingress_gate_snapshot.json", {
    blocked_event_miss_rate: 0.2,
  });
  writeJson(root, "build/xt_ready_incident_events.effective.json", {
    summary: {
      high_risk_lane_without_grant: 0,
      high_risk_bypass_count: 0,
      unaudited_auto_resolution: 0,
    },
  });
  return root;
}

function executePrep(root) {
  const cwd = process.cwd();
  try {
    process.chdir(root);
    return run(["node", "m3_prepare_internal_pass_inputs.js"]);
  } finally {
    process.chdir(cwd);
  }
}

function canonical(filePath) {
  return fs.realpathSync(filePath);
}

runTest("internal pass input preparer prefers require-real XT-ready gate artifact", () => {
  const root = createFixtureRoot();
  try {
    writeJson(root, "build/xt_ready_gate_e2e_require_real_report.json", {
      ok: true,
      require_real_audit_source: true,
    });
    writeJson(root, "build/xt_ready_gate_e2e_report.json", {
      ok: true,
      require_real_audit_source: false,
    });

    const result = executePrep(root);
    const expectedPath = path.join(root, "build/xt_ready_gate_e2e_require_real_report.json");

    assert.equal(canonical(result.prep.inputs.xt_ready_gate_report), canonical(expectedPath));
    assert.equal(
      canonical(result.metrics.metric_sources.find((item) => item.metric === "xt_ready_g0_status")?.source),
      canonical(expectedPath)
    );
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

runTest("internal pass input preparer falls back to db-real XT-ready gate artifact", () => {
  const root = createFixtureRoot();
  try {
    writeJson(root, "build/xt_ready_gate_e2e_db_real_report.json", {
      ok: true,
      require_real_audit_source: true,
    });
    writeJson(root, "build/xt_ready_gate_e2e_report.json", {
      ok: true,
      require_real_audit_source: false,
    });

    const result = executePrep(root);
    const expectedPath = path.join(root, "build/xt_ready_gate_e2e_db_real_report.json");

    assert.equal(canonical(result.prep.inputs.xt_ready_gate_report), canonical(expectedPath));
    assert.equal(
      canonical(result.metrics.metric_sources.find((item) => item.metric === "xt_ready_g0_status")?.source),
      canonical(expectedPath)
    );
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

runTest("internal pass input preparer prefers require-real connector snapshot", () => {
  const root = createFixtureRoot();
  try {
    writeJson(root, "build/connector_ingress_gate_snapshot.require_real.json", {
      source_used: "audit",
      blocked_event_miss_rate: 0,
    });
    const result = executePrep(root);
    const expectedPath = path.join(
      root,
      "build/connector_ingress_gate_snapshot.require_real.json"
    );

    assert.equal(
      canonical(result.prep.inputs.connector_gate_json),
      canonical(expectedPath)
    );
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
