#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const {
  buildDashboard,
  mergeThresholds,
  DEFAULT_THRESHOLDS,
} = require("./m2_build_observability_dashboard.js");

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

function makeReportFixture() {
  return {
    schema_version: "xhub.memory.bench.report.v1",
    metrics: {
      golden: {
        queries: 4,
        precision_at_k_avg: 0.22,
        recall_at_k_avg: 0.91,
        mrr_at_k_avg: 0.73,
        latency_ms: { p50: 120, p95: 190, max: 260, avg: 155 },
      },
      adversarial: {
        queries: 20,
        blocked_count: 11,
        blocked_rate: 0.55,
        expected_match_count: 12,
        expected_match_rate: 0.6,
      },
    },
    details: {
      golden: [
        {
          id: "g1",
          latency_ms: 130,
          pipeline_stage_trace: [
            { stage: "scope_filter", in_count: 20, out_count: 18 },
            { stage: "retrieval", in_count: 18, out_count: 10 },
            { stage: "gate", in_count: 10, out_count: 0, blocked: true, reason: "query_pattern:dump" },
          ],
        },
        {
          id: "g2",
          latency_ms: 210,
          pipeline_stage_trace: [
            { stage: "scope_filter", in_count: 20, out_count: 18 },
            { stage: "retrieval", in_count: 18, out_count: 9 },
            { stage: "gate", in_count: 9, out_count: 2, blocked: false, reason: "allow" },
          ],
        },
      ],
      adversarial: [
        { id: "a1", ok: false, reason: "remote_export_blocked:credential_finding" },
        { id: "a2", ok: false, reason: "remote_secret_denied" },
      ],
    },
  };
}

function makeRuntimeEvents(sampleCount = 25) {
  const out = [];
  for (let i = 0; i < sampleCount; i += 1) {
    out.push({
      created_at_ms: 1_700_000_000_000 + i,
      event_type: "ai.generate.completed",
      ext_json: JSON.stringify({
        queue_depth: 24 + (i % 4),
        metrics: {
          event_kind: "ai.generate.completed",
          latency: {
            duration_ms: 900 + (i * 15),
            queue_wait_ms: 300 + (i * 10),
          },
          quality: {
            result_count: 5 + (i % 2),
          },
          cost: {
            prompt_tokens: 100 + i,
            completion_tokens: 40 + i,
            total_tokens: 140 + (i * 2),
          },
          freshness: {
            index_freshness_ms: 40_000 + (i * 1000),
          },
          security: {
            blocked: i < 2,
            downgraded: i === 0,
            deny_code: i < 2 ? "remote_export_blocked" : "",
          },
        },
      }),
    });
  }
  return out;
}

run("W5-04/dashboard build includes four panels and stage anomalies", () => {
  const thresholds = mergeThresholds(DEFAULT_THRESHOLDS, {
    latency: {
      runtime_queue_depth_p95_max: 10, // intentionally low to trigger alert
    },
    noise_control: {
      min_samples: 10,
      critical_margin_ratio: 0.15,
    },
  });
  const dashboard = buildDashboard({
    report: makeReportFixture(),
    rawEvents: makeRuntimeEvents(30),
    thresholds,
    nowMs: 1_800_000_000_000,
    reportPath: "fixture/report.json",
    dbPath: "fixture/db.sqlite3",
    windowMs: 60_000,
  });

  assert.equal(dashboard.schema_version, "xhub.memory.observability.dashboard.v1");
  assert.ok(dashboard.panels.latency && dashboard.panels.quality && dashboard.panels.cost && dashboard.panels.freshness);
  assert.equal(dashboard.panels.quality.benchmark.precision_at_k_avg, 0.22);
  assert.equal(dashboard.panels.security.benchmark.adversarial_block_rate, 0.55);
  assert.equal(Number(dashboard.panels.latency.runtime.duration_ms.samples || 0) >= 20, true);

  const queueDepthAlert = (dashboard.alerts.items || []).find((it) => it.id === "queue.depth.p95");
  assert.ok(queueDepthAlert);
  assert.equal(queueDepthAlert.status, "critical");
  assert.equal(queueDepthAlert.stage_hint, "queue");

  const topStage = dashboard.pipeline_stages?.top_anomalies?.[0] || null;
  assert.ok(topStage);
  assert.equal(topStage.stage, "gate");
  assert.equal(Number(topStage.anomaly_score || 0) > 0, true);
});

run("W5-04/noise control suppresses low-sample breaches", () => {
  const thresholds = mergeThresholds(DEFAULT_THRESHOLDS, {
    latency: {
      runtime_queue_wait_p95_ms_max: 50,
    },
    noise_control: {
      min_samples: 20,
      critical_margin_ratio: 0.1,
    },
  });
  const dashboard = buildDashboard({
    report: makeReportFixture(),
    rawEvents: makeRuntimeEvents(3), // below min_samples
    thresholds,
    nowMs: 1_800_000_000_000,
    reportPath: "fixture/report.json",
    dbPath: "fixture/db.sqlite3",
    windowMs: 60_000,
  });

  const queueWaitAlert = (dashboard.alerts.items || []).find((it) => it.id === "queue.wait.p95");
  assert.ok(queueWaitAlert);
  assert.equal(queueWaitAlert.status, "warn");
  assert.equal(queueWaitAlert.suppressed_by_noise, true);
});

run("W5-04/alert checker enforces critical limit", () => {
  const dashboard = buildDashboard({
    report: makeReportFixture(),
    rawEvents: makeRuntimeEvents(30),
    thresholds: mergeThresholds(DEFAULT_THRESHOLDS, {
      latency: { runtime_queue_depth_p95_max: 10 },
    }),
    nowMs: 1_800_000_000_000,
    reportPath: "fixture/report.json",
    dbPath: "fixture/db.sqlite3",
    windowMs: 60_000,
  });

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "m2_w5_04_"));
  const dashboardPath = path.join(tmpDir, "dashboard.json");
  fs.writeFileSync(dashboardPath, JSON.stringify(dashboard, null, 2));

  const failRun = spawnSync(
    process.execPath,
    [path.join(__dirname, "m2_check_observability_alerts.js"), "--dashboard", dashboardPath, "--max-critical", "0"],
    { encoding: "utf8" }
  );
  assert.notEqual(failRun.status, 0);

  const passRun = spawnSync(
    process.execPath,
    [path.join(__dirname, "m2_check_observability_alerts.js"), "--dashboard", dashboardPath, "--max-critical", "2"],
    { encoding: "utf8" }
  );
  assert.equal(passRun.status, 0);

  try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch { /* ignore */ }
});
