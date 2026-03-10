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
  return path.join(os.tmpdir(), `hub_memory_voice_grant_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
}

const KEK_V1 = `base64:${Buffer.alloc(32, 0x52).toString("base64")}`;

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

function makeClient(projectId = "root-voice") {
  return {
    device_id: "dev-voice-1",
    user_id: "user-voice-1",
    app_id: "ax-terminal",
    project_id: projectId,
    session_id: "sess-voice-1",
  };
}

function issueChallenge(impl, client, {
  request_id,
  challenge_code,
  risk_level = "high",
  bound_device_id = "bt-headset-1",
  allow_voice_only = false,
  requires_mobile_confirm = true,
} = {}) {
  return invokeHubMemoryUnary(impl, "IssueVoiceGrantChallenge", {
    request_id,
    client,
    template_id: "voice.grant.v1",
    action_digest: "act:pay",
    scope_digest: "scope:project",
    amount_digest: "amount:500",
    challenge_code,
    risk_level,
    bound_device_id,
    mobile_terminal_id: "mobile-1",
    allow_voice_only,
    requires_mobile_confirm,
    ttl_ms: 120000,
  });
}

function verifyChallenge(impl, client, {
  request_id,
  challenge_id,
  challenge_code,
  verify_nonce,
  semantic_match_score = 0.99,
  parsed_action_digest = "act:pay",
  parsed_scope_digest = "scope:project",
  parsed_amount_digest = "amount:500",
  bound_device_id = "bt-headset-1",
  mobile_confirmed = true,
  transcript = "Authorize payment now",
} = {}) {
  return invokeHubMemoryUnary(impl, "VerifyVoiceGrantResponse", {
    request_id,
    client,
    challenge_id,
    challenge_code,
    transcript,
    semantic_match_score,
    parsed_action_digest,
    parsed_scope_digest,
    parsed_amount_digest,
    verify_nonce,
    bound_device_id,
    mobile_confirmed,
  });
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

run("M3-W3-06/voice_grant challenge_missing + semantic_ambiguous + device_not_bound", () => {
  const runtimeBaseDir = makeTmp("runtime");
  const dbPath = makeTmp("db", ".db");
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient();

      const missing = verifyChallenge(impl, client, {
        request_id: "req-voice-challenge-missing",
        challenge_id: "voice_chal_missing",
        challenge_code: "123456",
        verify_nonce: "nonce-missing",
      });
      assert.equal(missing.err, null);
      assert.equal(!!missing.res?.verified, false);
      assert.equal(String(missing.res?.deny_code || ""), "challenge_missing");

      const issued1 = issueChallenge(impl, client, {
        request_id: "req-voice-issue-semantic",
        challenge_code: "111111",
      });
      assert.equal(issued1.err, null);
      const challenge1 = issued1.res?.challenge || {};

      const semanticAmbiguous = verifyChallenge(impl, client, {
        request_id: "req-voice-semantic-ambiguous",
        challenge_id: String(challenge1.challenge_id || ""),
        challenge_code: "111111",
        verify_nonce: "nonce-semantic",
        semantic_match_score: 0.6,
      });
      assert.equal(semanticAmbiguous.err, null);
      assert.equal(!!semanticAmbiguous.res?.verified, false);
      assert.equal(String(semanticAmbiguous.res?.deny_code || ""), "semantic_ambiguous");

      const issued2 = issueChallenge(impl, client, {
        request_id: "req-voice-issue-device",
        challenge_code: "222222",
      });
      assert.equal(issued2.err, null);
      const challenge2 = issued2.res?.challenge || {};

      const deviceNotBound = verifyChallenge(impl, client, {
        request_id: "req-voice-device-not-bound",
        challenge_id: String(challenge2.challenge_id || ""),
        challenge_code: "222222",
        verify_nonce: "nonce-device",
        bound_device_id: "bt-headset-999",
      });
      assert.equal(deviceNotBound.err, null);
      assert.equal(!!deviceNotBound.res?.verified, false);
      assert.equal(String(deviceNotBound.res?.deny_code || ""), "device_not_bound");

      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: "req-voice-semantic-ambiguous",
        event_type: "supervisor.voice.denied",
        error_code: "semantic_ambiguous",
      });
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: "req-voice-device-not-bound",
        event_type: "supervisor.voice.denied",
        error_code: "device_not_bound",
      });
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
      try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
    }
  });
});

run("M3-W3-06/voice_grant replay_detected + high-risk voice-only forbidden", () => {
  const runtimeBaseDir = makeTmp("runtime");
  const dbPath = makeTmp("db", ".db");
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient();

      const issued = issueChallenge(impl, client, {
        request_id: "req-voice-issue-replay",
        challenge_code: "333333",
      });
      assert.equal(issued.err, null);
      const challenge = issued.res?.challenge || {};

      const firstVerify = verifyChallenge(impl, client, {
        request_id: "req-voice-verify-ok",
        challenge_id: String(challenge.challenge_id || ""),
        challenge_code: "333333",
        verify_nonce: "nonce-ok-1",
        mobile_confirmed: true,
      });
      assert.equal(firstVerify.err, null);
      assert.equal(!!firstVerify.res?.verified, true);
      assert.equal(String(firstVerify.res?.decision || ""), "allow");

      const replayVerify = verifyChallenge(impl, client, {
        request_id: "req-voice-replay-detected",
        challenge_id: String(challenge.challenge_id || ""),
        challenge_code: "333333",
        verify_nonce: "nonce-ok-2",
        mobile_confirmed: true,
      });
      assert.equal(replayVerify.err, null);
      assert.equal(!!replayVerify.res?.verified, false);
      assert.equal(String(replayVerify.res?.deny_code || ""), "replay_detected");

      const issuedHighRisk = issueChallenge(impl, client, {
        request_id: "req-voice-issue-high-risk",
        challenge_code: "444444",
        risk_level: "high",
        allow_voice_only: true,
        requires_mobile_confirm: false,
      });
      assert.equal(issuedHighRisk.err, null);
      const challengeHighRisk = issuedHighRisk.res?.challenge || {};

      const voiceOnlyDenied = verifyChallenge(impl, client, {
        request_id: "req-voice-only-denied",
        challenge_id: String(challengeHighRisk.challenge_id || ""),
        challenge_code: "444444",
        verify_nonce: "nonce-high-1",
        mobile_confirmed: false,
      });
      assert.equal(voiceOnlyDenied.err, null);
      assert.equal(!!voiceOnlyDenied.res?.verified, false);
      assert.equal(String(voiceOnlyDenied.res?.deny_code || ""), "voice_only_forbidden");

      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: "req-voice-verify-ok",
        event_type: "supervisor.voice.verified",
      });
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: "req-voice-replay-detected",
        event_type: "supervisor.voice.denied",
        error_code: "replay_detected",
      });
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: "req-voice-only-denied",
        event_type: "supervisor.voice.denied",
        error_code: "voice_only_forbidden",
      });
    } finally {
      db.close();
      cleanupDbArtifacts(dbPath);
      try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
    }
  });
});
