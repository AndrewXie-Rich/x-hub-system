import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { HubDB } from "./db.js";
import { HubEventBus } from "./event_bus.js";
import { makeServices } from "./services.js";

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

function withEnv(tempEnv, fn) {
  const prev = new Map();
  for (const key of Object.keys(tempEnv)) {
    prev.set(key, process.env[key]);
    const next = tempEnv[key];
    if (next == null) delete process.env[key];
    else process.env[key] = String(next);
  }
  try {
    return fn();
  } finally {
    for (const [key, val] of prev.entries()) {
      if (val == null) delete process.env[key];
      else process.env[key] = val;
    }
  }
}

function makeTmp(label, suffix = "") {
  const token = `${label}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  return path.join(os.tmpdir(), `hub_memory_risk_tuning_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
}

const KEK_V1 = `base64:${Buffer.alloc(32, 0x51).toString("base64")}`;

function baseEnv(runtimeBaseDir, extra = {}) {
  return {
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_CLIENT_TOKEN: "",
    HUB_MEMORY_AT_REST_ENABLED: "true",
    HUB_MEMORY_KEK_ACTIVE_VERSION: "kek_v1",
    HUB_MEMORY_KEK_RING_JSON: JSON.stringify({ kek_v1: KEK_V1 }),
    HUB_MEMORY_KEK_FILE: "",
    HUB_MEMORY_RETENTION_ENABLED: "true",
    HUB_MEMORY_RETENTION_AUTO_JOB_ENABLED: "false",
    HUB_MEMORY_RETENTION_BATCH_LIMIT: "200",
    HUB_MEMORY_RETENTION_TURNS_TTL_MS: "86400000",
    HUB_MEMORY_RETENTION_CANONICAL_TTL_MS: "86400000",
    HUB_MEMORY_RETENTION_CANONICAL_INCLUDE_PINNED: "false",
    HUB_MEMORY_RETENTION_TOMBSTONE_TTL_MS: String(60 * 1000),
    HUB_MEMORY_RETENTION_AUDIT_ENABLED: "true",
    ...extra,
  };
}

function invokeHubMemoryUnary(impl, methodName, request) {
  let outErr = null;
  let outRes = null;
  impl.HubMemory[methodName](
    {
      request,
      metadata: {
        get() {
          return [];
        },
      },
    },
    (err, res) => {
      outErr = err || null;
      outRes = res || null;
    }
  );
  return { err: outErr, res: outRes };
}

function makeClient(projectId = "root-risk") {
  return {
    device_id: "dev-risk-1",
    user_id: "user-risk-1",
    app_id: "ax-terminal",
    project_id: projectId,
    session_id: "sess-risk-1",
  };
}

function baselineMetrics() {
  return {
    recall: 0.99,
    p95_latency_ratio: 1.0,
    block_precision: 0.99,
    mean_final_score: 0.5,
  };
}

function assertAuditEvent(db, {
  device_id,
  user_id,
  request_id,
  event_type,
  error_code = null,
} = {}) {
  const row = db.listAuditEvents({
    device_id: String(device_id || ""),
    user_id: String(user_id || ""),
    request_id: String(request_id || ""),
  }).find((item) => String(item?.event_type || "") === String(event_type || ""));
  assert.ok(row, `expected audit event ${event_type} for request_id=${request_id}`);
  if (error_code != null) {
    assert.equal(String(row?.error_code || ""), String(error_code || ""));
  }
}

run("M3-W3-05/risk_tuning profile_invalid fail-closed", () => {
  const runtimeBaseDir = makeTmp("runtime");
  const dbPath = makeTmp("db", ".db");
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient();

      const out = invokeHubMemoryUnary(impl, "EvaluateRiskTuningProfile", {
        request_id: "req-risk-invalid",
        client,
        profile: {
          profile_id: "bad profile",
          vector_weight: 1,
          text_weight: 1,
          recency_weight: 1,
          risk_weight: 1,
          risk_penalty_low: 0.1,
          risk_penalty_medium: 0.2,
          risk_penalty_high: 0.3,
          recall_floor: 0.97,
          latency_ceiling_ratio: 1.5,
          block_precision_floor: 0.95,
          max_recall_drop: 0.03,
          max_latency_ratio_increase: 0.2,
          max_block_precision_drop: 0.02,
          max_online_offline_drift: 0.12,
        },
        baseline_metrics: baselineMetrics(),
        holdout_metrics: baselineMetrics(),
        online_metrics: baselineMetrics(),
        offline_metrics: baselineMetrics(),
        auto_rollback_on_violation: true,
      });
      assert.equal(out.err, null);
      assert.equal(!!out.res?.accepted, false);
      assert.equal(String(out.res?.deny_code || ""), "profile_invalid");
      assert.equal(!!out.res?.rollback_triggered, false);

      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: "req-risk-invalid",
        event_type: "memory.risk_tuning.evaluated",
        error_code: "profile_invalid",
      });
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
      try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
    }
  });
});

run("M3-W3-05/risk_tuning holdout gate blocks promotion and auto-rolls back violated active profile", () => {
  const runtimeBaseDir = makeTmp("runtime");
  const dbPath = makeTmp("db", ".db");
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient();

      const snapshot0 = invokeHubMemoryUnary(impl, "GetRiskTuningProfile", { client });
      assert.equal(snapshot0.err, null);
      const activeProfile = snapshot0.res?.profile || {};
      const baselineProfileId = String(snapshot0.res?.active_profile_id || "risk_default_v1");

      const candidateProfile = {
        profile_id: "risk_candidate_v2",
        profile_label: "risk-candidate-v2",
        vector_weight: Number(activeProfile.vector_weight || 1),
        text_weight: Number(activeProfile.text_weight || 1),
        recency_weight: Number(activeProfile.recency_weight || 0.4),
        risk_weight: Number(activeProfile.risk_weight || 1),
        risk_penalty_low: Number(activeProfile.risk_penalty_low || 0.1),
        risk_penalty_medium: Number(activeProfile.risk_penalty_medium || 0.35),
        risk_penalty_high: Number(activeProfile.risk_penalty_high || 0.8),
        recall_floor: Number(activeProfile.recall_floor || 0.97),
        latency_ceiling_ratio: Number(activeProfile.latency_ceiling_ratio || 1.5),
        block_precision_floor: Number(activeProfile.block_precision_floor || 0.95),
        max_recall_drop: Number(activeProfile.max_recall_drop || 0.03),
        max_latency_ratio_increase: Number(activeProfile.max_latency_ratio_increase || 0.2),
        max_block_precision_drop: Number(activeProfile.max_block_precision_drop || 0.02),
        max_online_offline_drift: Number(activeProfile.max_online_offline_drift || 0.12),
      };

      const holdoutBlocked = invokeHubMemoryUnary(impl, "EvaluateRiskTuningProfile", {
        request_id: "req-risk-holdout-block",
        client,
        profile: candidateProfile,
        baseline_metrics: baselineMetrics(),
        holdout_metrics: {
          recall: 0.90,
          p95_latency_ratio: 1.4,
          block_precision: 0.92,
          mean_final_score: 0.48,
        },
        online_metrics: {
          recall: 0.98,
          p95_latency_ratio: 1.2,
          block_precision: 0.97,
          mean_final_score: 0.52,
        },
        offline_metrics: {
          recall: 0.98,
          p95_latency_ratio: 1.1,
          block_precision: 0.97,
          mean_final_score: 0.5,
        },
        auto_rollback_on_violation: false,
      });
      assert.equal(holdoutBlocked.err, null);
      assert.equal(!!holdoutBlocked.res?.accepted, false);
      assert.equal(!!holdoutBlocked.res?.holdout_passed, false);
      assert.equal(String(holdoutBlocked.res?.deny_code || ""), "holdout_regression");

      const promoteBlocked = invokeHubMemoryUnary(impl, "PromoteRiskTuningProfile", {
        request_id: "req-risk-promote-block",
        client,
        profile_id: candidateProfile.profile_id,
        expected_active_profile_id: baselineProfileId,
      });
      assert.equal(promoteBlocked.err, null);
      assert.equal(!!promoteBlocked.res?.promoted, false);
      assert.equal(String(promoteBlocked.res?.deny_code || ""), "holdout_regression");

      const evalPass = invokeHubMemoryUnary(impl, "EvaluateRiskTuningProfile", {
        request_id: "req-risk-eval-pass",
        client,
        profile: candidateProfile,
        baseline_metrics: baselineMetrics(),
        holdout_metrics: {
          recall: 0.98,
          p95_latency_ratio: 1.1,
          block_precision: 0.97,
          mean_final_score: 0.56,
        },
        online_metrics: {
          recall: 0.98,
          p95_latency_ratio: 1.2,
          block_precision: 0.97,
          mean_final_score: 0.55,
        },
        offline_metrics: {
          recall: 0.98,
          p95_latency_ratio: 1.15,
          block_precision: 0.97,
          mean_final_score: 0.53,
        },
      });
      assert.equal(evalPass.err, null);
      assert.equal(!!evalPass.res?.accepted, true);
      assert.equal(String(evalPass.res?.deny_code || ""), "");

      const promoteOk = invokeHubMemoryUnary(impl, "PromoteRiskTuningProfile", {
        request_id: "req-risk-promote-ok",
        client,
        profile_id: candidateProfile.profile_id,
        expected_active_profile_id: baselineProfileId,
      });
      assert.equal(promoteOk.err, null);
      assert.equal(!!promoteOk.res?.promoted, true);
      assert.equal(String(promoteOk.res?.active_profile_id || ""), candidateProfile.profile_id);
      assert.equal(String(promoteOk.res?.previous_active_profile_id || ""), baselineProfileId);

      const driftViolation = invokeHubMemoryUnary(impl, "EvaluateRiskTuningProfile", {
        request_id: "req-risk-drift-violation",
        client,
        profile: candidateProfile,
        baseline_metrics: baselineMetrics(),
        holdout_metrics: {
          recall: 0.98,
          p95_latency_ratio: 1.1,
          block_precision: 0.97,
          mean_final_score: 0.57,
        },
        online_metrics: {
          recall: 0.98,
          p95_latency_ratio: 1.2,
          block_precision: 0.97,
          mean_final_score: 1.1,
        },
        offline_metrics: {
          recall: 0.98,
          p95_latency_ratio: 1.1,
          block_precision: 0.97,
          mean_final_score: 0.2,
        },
        auto_rollback_on_violation: true,
      });
      assert.equal(driftViolation.err, null);
      assert.equal(!!driftViolation.res?.accepted, false);
      assert.equal(String(driftViolation.res?.deny_code || ""), "online_drift_exceeded");
      assert.equal(!!driftViolation.res?.rollback_triggered, true);
      assert.equal(String(driftViolation.res?.rollback_to_profile_id || ""), baselineProfileId);

      const snapshot1 = invokeHubMemoryUnary(impl, "GetRiskTuningProfile", { client });
      assert.equal(snapshot1.err, null);
      assert.equal(String(snapshot1.res?.active_profile_id || ""), baselineProfileId);

      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: "req-risk-drift-violation",
        event_type: "memory.risk_tuning.rollback",
      });
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
      try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
    }
  });
});
