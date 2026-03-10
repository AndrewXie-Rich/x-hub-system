#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const {
  buildWeeklyReport,
  toMarkdown,
} = require("./m2_generate_weekly_regression_report.js");

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

run("W5-05/build weekly report compares baseline and emits trend/todos", () => {
  const baseline = {
    metrics: {
      golden: {
        precision_at_k_avg: 0.5,
        recall_at_k_avg: 0.9,
        latency_ms: { p95: 100 },
      },
      adversarial: {
        expected_match_rate: 0.8,
      },
    },
  };

  const current = {
    metrics: {
      golden: {
        precision_at_k_avg: 0.49,
        recall_at_k_avg: 0.84,
        latency_ms: { p95: 180 },
      },
      adversarial: {
        expected_match_rate: 0.58,
      },
    },
    gate_hints: {
      gate1_correctness: true,
      gate2_performance: true,
      gate3_security: false,
    },
  };

  const dashboard = {
    alerts: {
      summary: {
        critical: 1,
        warn: 4,
        no_data: 0,
        total: 5,
      },
      items: [
        { id: "p95.latency", status: "critical", stage_hint: "queue" },
        { id: "pipeline.stage.top_anomaly", status: "warn", suppressed_by_noise: false, stage_hint: "retrieval" },
        { id: "queue.wait.p95", status: "warn", suppressed_by_noise: true, stage_hint: "queue" },
      ],
    },
    pipeline_stages: {
      top_anomalies: [
        { stage: "retrieval", anomaly_score: 88 },
      ],
    },
  };

  const historyEntries = [
    {
      schema_version: "xhub.memory.weekly_regression_history.v1",
      generated_at_ms: 1771545600000,
      metrics: {
        precision_at_k_avg: 0.5,
        recall_at_k_avg: 0.9,
        p95_latency_ms: 100,
        adversarial_match_rate: 0.8,
      },
    },
  ];

  const report = buildWeeklyReport({
    nowMs: 1772150400000,
    currentReport: current,
    baselineReport: baseline,
    regressionThresholds: {
      recall_drop_max: 0.02,
      precision_drop_max: 0.03,
      p95_latency_growth_max: 0.5,
      adversarial_match_drop_max: 0.01,
    },
    dashboard,
    historyEntries,
    sourcePaths: {
      current_report: "fixture/current.json",
      baseline_report: "fixture/baseline.json",
      thresholds: "fixture/thresholds.json",
      dashboard: "fixture/dashboard.json",
      history: "fixture/history.jsonl",
    },
  });

  assert.equal(report.schema_version, "xhub.memory.weekly_regression_report.v1");
  assert.equal(report.summary.check_fail_count, 3);
  assert.equal(report.summary.critical_alerts, 1);
  assert.equal(report.summary.warn_alerts, 4);
  assert.equal(report.summary.gate3_security, false);

  const checksByKey = new Map((report.checks || []).map((it) => [it.key, it]));
  assert.equal(checksByKey.get("precision")?.pass, true);
  assert.equal(checksByKey.get("recall")?.pass, false);
  assert.equal(checksByKey.get("p95_latency")?.pass, false);
  assert.equal(checksByKey.get("adversarial_match")?.pass, false);

  const todoIds = new Set((report.todos || []).map((it) => it.id));
  assert.equal(todoIds.has("todo.regression.recall"), true);
  assert.equal(todoIds.has("todo.regression.p95_latency"), true);
  assert.equal(todoIds.has("todo.regression.adversarial_match"), true);
  assert.equal(todoIds.has("todo.security.gate3"), true);
  assert.equal(todoIds.has("todo.alerts.critical"), true);
  assert.equal(todoIds.has("todo.alerts.warn_noise"), true);
  assert.equal(todoIds.has("todo.regression.precision"), false);

  assert.deepEqual(report.trends.labels, ["02-20", "02-27"]);
  assert.equal(report.trends.points, 2);

  const markdown = toMarkdown(report);
  assert.equal(markdown.includes("## Trend Chart"), true);
  assert.equal(markdown.includes("```mermaid"), true);
  assert.equal(markdown.includes("[P0] gate3_security is failing in weekly snapshot"), true);
});

run("W5-05/cli writes report files and honors --append-history", () => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "m2_w5_05_"));
  const baselinePath = path.join(tmpDir, "baseline.json");
  const currentPath = path.join(tmpDir, "current.json");
  const thresholdsPath = path.join(tmpDir, "thresholds.json");
  const dashboardPath = path.join(tmpDir, "dashboard.json");
  const historyPath = path.join(tmpDir, "history.jsonl");
  const outJsonPath = path.join(tmpDir, "weekly_report.json");
  const outMdPath = path.join(tmpDir, "weekly_report.md");

  const baseline = {
    metrics: {
      golden: {
        precision_at_k_avg: 0.7,
        recall_at_k_avg: 0.8,
        latency_ms: { p95: 120 },
      },
      adversarial: {
        expected_match_rate: 0.61,
      },
    },
    gate_hints: {
      gate1_correctness: true,
      gate2_performance: true,
      gate3_security: true,
    },
  };

  const current = {
    metrics: {
      golden: {
        precision_at_k_avg: 0.705,
        recall_at_k_avg: 0.805,
        latency_ms: { p95: 130 },
      },
      adversarial: {
        expected_match_rate: 0.615,
      },
    },
    gate_hints: {
      gate1_correctness: true,
      gate2_performance: true,
      gate3_security: true,
    },
  };

  const thresholds = {
    recall_drop_max: 0.02,
    precision_drop_max: 0.03,
    p95_latency_growth_max: 0.5,
    adversarial_match_drop_max: 0.01,
  };

  const dashboard = {
    alerts: {
      summary: { critical: 0, warn: 0, no_data: 0, total: 0 },
      items: [],
    },
    pipeline_stages: {
      top_anomalies: [],
    },
  };

  fs.writeFileSync(baselinePath, `${JSON.stringify(baseline, null, 2)}\n`, "utf8");
  fs.writeFileSync(currentPath, `${JSON.stringify(current, null, 2)}\n`, "utf8");
  fs.writeFileSync(thresholdsPath, `${JSON.stringify(thresholds, null, 2)}\n`, "utf8");
  fs.writeFileSync(dashboardPath, `${JSON.stringify(dashboard, null, 2)}\n`, "utf8");

  const seedHistory = {
    schema_version: "xhub.memory.weekly_regression_history.v1",
    generated_at_ms: 1771545600000,
    metrics: {
      precision_at_k_avg: 0.7,
      recall_at_k_avg: 0.8,
      p95_latency_ms: 120,
      adversarial_match_rate: 0.61,
      gate1_correctness: true,
      gate2_performance: true,
      gate3_security: true,
      failed_checks: [],
      alerts_critical: 0,
      alerts_warn: 0,
    },
  };
  fs.writeFileSync(historyPath, `${JSON.stringify(seedHistory)}\n{bad json}\n`, "utf8");

  const scriptPath = path.join(__dirname, "m2_generate_weekly_regression_report.js");
  const first = spawnSync(
    process.execPath,
    [
      scriptPath,
      "--current", currentPath,
      "--baseline", baselinePath,
      "--thresholds", thresholdsPath,
      "--dashboard", dashboardPath,
      "--history", historyPath,
      "--out-json", outJsonPath,
      "--out-md", outMdPath,
      "--append-history", "1",
      "--now-ms", "1772150400000",
    ],
    { encoding: "utf8" }
  );

  assert.equal(first.status, 0, first.stderr || first.stdout);
  assert.equal(fs.existsSync(outJsonPath), true);
  assert.equal(fs.existsSync(outMdPath), true);

  const firstOutput = JSON.parse(String(first.stdout || "{}"));
  assert.equal(firstOutput.ok, true);
  assert.equal(firstOutput.history_appended, true);

  const historyAfterFirst = fs.readFileSync(historyPath, "utf8").split(/\r?\n/).map((x) => x.trim()).filter(Boolean);
  assert.equal(historyAfterFirst.length, 3);

  const second = spawnSync(
    process.execPath,
    [
      scriptPath,
      "--current", currentPath,
      "--baseline", baselinePath,
      "--thresholds", thresholdsPath,
      "--dashboard", dashboardPath,
      "--history", historyPath,
      "--out-json", outJsonPath,
      "--out-md", outMdPath,
      "--append-history", "0",
      "--now-ms", "1772236800000",
    ],
    { encoding: "utf8" }
  );

  assert.equal(second.status, 0, second.stderr || second.stdout);

  const historyAfterSecond = fs.readFileSync(historyPath, "utf8").split(/\r?\n/).map((x) => x.trim()).filter(Boolean);
  assert.equal(historyAfterSecond.length, 3);

  const weeklyJson = JSON.parse(fs.readFileSync(outJsonPath, "utf8"));
  assert.equal(weeklyJson.trends.points >= 2, true);

  try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch { /* ignore */ }
});
