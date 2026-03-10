import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import { HubEventBus } from './event_bus.js';
import { makeServices } from './services.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

async function runAsync(name, fn) {
  try {
    await fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

function sleepMs(ms) {
  const wait = Math.max(0, Math.floor(Number(ms || 0)));
  return new Promise((resolve) => {
    setTimeout(resolve, wait);
  });
}

async function waitFor(predicate, { timeoutMs = 1500, stepMs = 50 } = {}) {
  const deadline = Date.now() + Math.max(1, Math.floor(Number(timeoutMs || 0)));
  const step = Math.max(5, Math.floor(Number(stepMs || 0)));
  while (Date.now() < deadline) {
    if (predicate()) return true;
    await sleepMs(step);
  }
  return !!predicate();
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

async function withEnvAsync(tempEnv, fn) {
  const prev = new Map();
  for (const key of Object.keys(tempEnv)) {
    prev.set(key, process.env[key]);
    const next = tempEnv[key];
    if (next == null) delete process.env[key];
    else process.env[key] = String(next);
  }
  try {
    return await fn();
  } finally {
    for (const [key, val] of prev.entries()) {
      if (val == null) delete process.env[key];
      else process.env[key] = val;
    }
  }
}

function makeTmp(label, suffix = '') {
  const token = `${label}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  return path.join(os.tmpdir(), `hub_memory_payment_intent_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
}

const KEK_V1 = `base64:${Buffer.alloc(32, 0x43).toString('base64')}`;

function baseEnv(runtimeBaseDir, extra = {}) {
  return {
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_CLIENT_TOKEN: '',
    HUB_MEMORY_AT_REST_ENABLED: 'true',
    HUB_MEMORY_KEK_ACTIVE_VERSION: 'kek_v1',
    HUB_MEMORY_KEK_RING_JSON: JSON.stringify({ kek_v1: KEK_V1 }),
    HUB_MEMORY_KEK_FILE: '',
    HUB_MEMORY_RETENTION_ENABLED: 'true',
    HUB_MEMORY_RETENTION_AUTO_JOB_ENABLED: 'false',
    HUB_MEMORY_RETENTION_BATCH_LIMIT: '200',
    HUB_MEMORY_RETENTION_TURNS_TTL_MS: '86400000',
    HUB_MEMORY_RETENTION_CANONICAL_TTL_MS: '86400000',
    HUB_MEMORY_RETENTION_CANONICAL_INCLUDE_PINNED: 'false',
    HUB_MEMORY_RETENTION_TOMBSTONE_TTL_MS: String(60 * 1000),
    HUB_MEMORY_RETENTION_AUDIT_ENABLED: 'true',
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

function makeClient(projectId = 'proj-payment-a') {
  return {
    device_id: 'dev-payment-1',
    user_id: 'user-payment-1',
    app_id: 'ax-terminal',
    project_id: projectId,
    session_id: 'sess-payment-1',
  };
}

function buildPaymentEvidenceSignaturePayload({ client, intent, evidence } = {}) {
  const safeClient = client && typeof client === 'object' ? client : {};
  const safeIntent = intent && typeof intent === 'object' ? intent : {};
  const safeEvidence = evidence && typeof evidence === 'object' ? evidence : {};
  return JSON.stringify({
    v: 1,
    intent_id: String(safeIntent.intent_id || ''),
    request_id: String(safeIntent.request_id || ''),
    device_id: String(safeClient.device_id || ''),
    user_id: String(safeClient.user_id || ''),
    app_id: String(safeClient.app_id || ''),
    project_id: String(safeClient.project_id || ''),
    amount_minor: Math.max(0, Math.floor(Number(safeIntent.amount_minor || 0))),
    currency: String(safeEvidence.currency || '').trim().toUpperCase(),
    merchant_id: String(safeEvidence.merchant_id || '').trim(),
    photo_hash: String(safeEvidence.photo_hash || '').trim(),
    geo_hash: String(safeEvidence.geo_hash || '').trim(),
    qr_payload_hash: String(safeEvidence.qr_payload_hash || '').trim(),
    nonce: String(safeEvidence.nonce || '').trim(),
    captured_at_ms: Math.max(0, Number(safeEvidence.captured_at_ms || 0)),
  });
}

function makePaymentEvidenceSignature({ client, intent, evidence, secret = '' } = {}) {
  const payload = buildPaymentEvidenceSignaturePayload({ client, intent, evidence });
  if (secret) {
    const hex = crypto.createHmac('sha256', String(secret)).update(payload, 'utf8').digest('hex');
    return `hmac-sha256:${hex}`;
  }
  const hex = crypto.createHash('sha256').update(payload, 'utf8').digest('hex');
  return `sha256:${hex}`;
}

function withEvidenceSignature({ client, intent, evidence, secret = '' } = {}) {
  const row = evidence && typeof evidence === 'object' ? { ...evidence } : {};
  row.device_signature = makePaymentEvidenceSignature({
    client,
    intent,
    evidence: row,
    secret,
  });
  return row;
}

function assertAuditEvent(db, {
  device_id,
  user_id,
  request_id,
  event_type,
  error_code = null,
} = {}) {
  const row = db.listAuditEvents({
    device_id: String(device_id || ''),
    user_id: String(user_id || ''),
    request_id: String(request_id || ''),
  }).find((item) => String(item?.event_type || '') === String(event_type || ''));
  assert.ok(row, `expected audit event ${event_type} for request_id=${request_id}`);
  if (error_code != null) {
    assert.equal(String(row?.error_code || ''), String(error_code || ''));
  }
}

function findAuditEvent(db, {
  device_id,
  user_id,
  request_id,
  event_type,
} = {}) {
  return db.listAuditEvents({
    device_id: String(device_id || ''),
    user_id: String(user_id || ''),
    request_id: String(request_id || ''),
  }).find((item) => String(item?.event_type || '') === String(event_type || '')) || null;
}

function parseAuditExt(row) {
  const raw = String(row?.ext_json || '').trim();
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) return parsed;
  } catch {
    // ignore
  }
  return {};
}

run('M3-W2-04/payment deny_code matrix: evidence_mismatch + amount_mismatch + replay_detected', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-payment-deny');

      const created = invokeHubMemoryUnary(impl, 'CreatePaymentIntent', {
        request_id: 'req-pay-create-1',
        client,
        amount_minor: 300,
        currency: 'CNY',
        merchant_id: 'merchant-water',
        source_terminal_id: 'robot-kiosk-1',
        allowed_mobile_terminal_id: 'mobile-1',
        expected_photo_hash: 'photo-ok',
        expected_geo_hash: 'geo-ok',
        expected_qr_payload_hash: 'qr-ok',
        ttl_ms: 120000,
        challenge_ttl_ms: 30000,
      });
      assert.equal(created.err, null);
      assert.equal(!!created.res?.accepted, true);
      assert.equal(!!created.res?.created, true);
      const createdIntent = created.res?.intent || {};
      const intentId = String(created.res?.intent?.intent_id || '');
      assert.ok(intentId.length > 0);
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay-create-1',
        event_type: 'payment.intent.created',
      });

      const evidenceMismatch = invokeHubMemoryUnary(impl, 'AttachPaymentEvidence', {
        request_id: 'req-pay-evidence-mismatch',
        client,
        intent_id: intentId,
        evidence: withEvidenceSignature({
          client,
          intent: createdIntent,
          evidence: {
          photo_hash: 'photo-bad',
          price_amount_minor: 300,
          currency: 'CNY',
          merchant_id: 'merchant-water',
          geo_hash: 'geo-ok',
          qr_payload_hash: 'qr-ok',
          nonce: 'nonce-evidence-1',
          captured_at_ms: 1730000001000,
          },
        }),
      });
      assert.equal(evidenceMismatch.err, null);
      assert.equal(!!evidenceMismatch.res?.accepted, false);
      assert.equal(String(evidenceMismatch.res?.deny_code || ''), 'evidence_mismatch');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay-evidence-mismatch',
        event_type: 'payment.evidence.verified',
        error_code: 'evidence_mismatch',
      });

      const amountMismatch = invokeHubMemoryUnary(impl, 'AttachPaymentEvidence', {
        request_id: 'req-pay-amount-mismatch',
        client,
        intent_id: intentId,
        evidence: withEvidenceSignature({
          client,
          intent: createdIntent,
          evidence: {
          photo_hash: 'photo-ok',
          price_amount_minor: 301,
          currency: 'CNY',
          merchant_id: 'merchant-water',
          geo_hash: 'geo-ok',
          qr_payload_hash: 'qr-ok',
          nonce: 'nonce-evidence-2',
          captured_at_ms: 1730000001100,
          },
        }),
      });
      assert.equal(amountMismatch.err, null);
      assert.equal(!!amountMismatch.res?.accepted, false);
      assert.equal(String(amountMismatch.res?.deny_code || ''), 'amount_mismatch');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay-amount-mismatch',
        event_type: 'payment.evidence.verified',
        error_code: 'amount_mismatch',
      });

      const evidenceOk = invokeHubMemoryUnary(impl, 'AttachPaymentEvidence', {
        request_id: 'req-pay-evidence-ok',
        client,
        intent_id: intentId,
        evidence: withEvidenceSignature({
          client,
          intent: createdIntent,
          evidence: {
          photo_hash: 'photo-ok',
          price_amount_minor: 300,
          currency: 'CNY',
          merchant_id: 'merchant-water',
          geo_hash: 'geo-ok',
          qr_payload_hash: 'qr-ok',
          nonce: 'nonce-replay-shared',
          captured_at_ms: 1730000001200,
          },
        }),
      });
      assert.equal(evidenceOk.err, null);
      assert.equal(!!evidenceOk.res?.accepted, true);

      const created2 = invokeHubMemoryUnary(impl, 'CreatePaymentIntent', {
        request_id: 'req-pay-create-2',
        client,
        amount_minor: 300,
        currency: 'CNY',
        merchant_id: 'merchant-water',
        source_terminal_id: 'robot-kiosk-1',
        allowed_mobile_terminal_id: 'mobile-1',
        expected_photo_hash: 'photo-ok',
        expected_geo_hash: 'geo-ok',
        expected_qr_payload_hash: 'qr-ok',
        ttl_ms: 120000,
        challenge_ttl_ms: 30000,
      });
      assert.equal(created2.err, null);
      assert.equal(!!created2.res?.accepted, true);
      const createdIntent2 = created2.res?.intent || {};
      const intentId2 = String(created2.res?.intent?.intent_id || '');
      assert.ok(intentId2.length > 0);

      const replayDetected = invokeHubMemoryUnary(impl, 'AttachPaymentEvidence', {
        request_id: 'req-pay-replay-detected',
        client,
        intent_id: intentId2,
        evidence: withEvidenceSignature({
          client,
          intent: createdIntent2,
          evidence: {
          photo_hash: 'photo-ok',
          price_amount_minor: 300,
          currency: 'CNY',
          merchant_id: 'merchant-water',
          geo_hash: 'geo-ok',
          qr_payload_hash: 'qr-ok',
          nonce: 'nonce-replay-shared',
          captured_at_ms: 1730000001300,
          },
        }),
      });
      assert.equal(replayDetected.err, null);
      assert.equal(!!replayDetected.res?.accepted, false);
      assert.equal(String(replayDetected.res?.deny_code || ''), 'replay_detected');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay-replay-detected',
        event_type: 'payment.evidence.verified',
        error_code: 'replay_detected',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W2-04/payment evidence signature verifier: hmac mode fail-closed', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir, {
    HUB_PAYMENT_EVIDENCE_SIGNING_SECRET: 'lane-g3-signing-secret',
  }), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-payment-signature');

      const created = invokeHubMemoryUnary(impl, 'CreatePaymentIntent', {
        request_id: 'req-pay-sign-create',
        client,
        amount_minor: 460,
        currency: 'CNY',
        merchant_id: 'merchant-water',
        source_terminal_id: 'robot-kiosk-sign',
        allowed_mobile_terminal_id: 'mobile-sign',
        expected_photo_hash: 'photo-sign',
        expected_geo_hash: 'geo-sign',
        expected_qr_payload_hash: 'qr-sign',
        ttl_ms: 120000,
      });
      assert.equal(created.err, null);
      assert.equal(!!created.res?.accepted, true);
      const createdIntent = created.res?.intent || {};
      const intentId = String(createdIntent.intent_id || '');
      assert.ok(intentId.length > 0);

      const invalidSignature = invokeHubMemoryUnary(impl, 'AttachPaymentEvidence', {
        request_id: 'req-pay-sign-invalid',
        client,
        intent_id: intentId,
        evidence: withEvidenceSignature({
          client,
          intent: createdIntent,
          evidence: {
            photo_hash: 'photo-sign',
            price_amount_minor: 460,
            currency: 'CNY',
            merchant_id: 'merchant-water',
            geo_hash: 'geo-sign',
            qr_payload_hash: 'qr-sign',
            nonce: 'nonce-pay-sign',
            captured_at_ms: 1730000001400,
          },
          // Deliberately use non-HMAC signature while server is in HMAC mode.
          secret: '',
        }),
      });
      assert.equal(invalidSignature.err, null);
      assert.equal(!!invalidSignature.res?.accepted, false);
      assert.equal(String(invalidSignature.res?.deny_code || ''), 'evidence_mismatch');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay-sign-invalid',
        event_type: 'payment.evidence.verified',
        error_code: 'evidence_mismatch',
      });

      const validSignature = invokeHubMemoryUnary(impl, 'AttachPaymentEvidence', {
        request_id: 'req-pay-sign-valid',
        client,
        intent_id: intentId,
        evidence: withEvidenceSignature({
          client,
          intent: createdIntent,
          evidence: {
            photo_hash: 'photo-sign',
            price_amount_minor: 460,
            currency: 'CNY',
            merchant_id: 'merchant-water',
            geo_hash: 'geo-sign',
            qr_payload_hash: 'qr-sign',
            nonce: 'nonce-pay-sign',
            captured_at_ms: 1730000001400,
          },
          secret: 'lane-g3-signing-secret',
        }),
      });
      assert.equal(validSignature.err, null);
      assert.equal(!!validSignature.res?.accepted, true);
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay-sign-valid',
        event_type: 'payment.evidence.verified',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W2-04/payment challenge path: terminal_not_allowed + challenge_expired (+ expire audit)', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-payment-challenge');

      const created = invokeHubMemoryUnary(impl, 'CreatePaymentIntent', {
        request_id: 'req-pay2-create',
        client,
        amount_minor: 500,
        currency: 'CNY',
        merchant_id: 'merchant-water',
        source_terminal_id: 'robot-kiosk-2',
        allowed_mobile_terminal_id: 'mobile-allow',
        expected_photo_hash: 'photo-2',
        expected_geo_hash: 'geo-2',
        expected_qr_payload_hash: 'qr-2',
        ttl_ms: 120000,
        challenge_ttl_ms: 2000,
      });
      assert.equal(created.err, null);
      assert.equal(!!created.res?.accepted, true);
      const createdIntent = created.res?.intent || {};
      const intentId = String(created.res?.intent?.intent_id || '');
      assert.ok(intentId.length > 0);

      const evidenceOk = invokeHubMemoryUnary(impl, 'AttachPaymentEvidence', {
        request_id: 'req-pay2-evidence',
        client,
        intent_id: intentId,
        evidence: withEvidenceSignature({
          client,
          intent: createdIntent,
          evidence: {
          photo_hash: 'photo-2',
          price_amount_minor: 500,
          currency: 'CNY',
          merchant_id: 'merchant-water',
          geo_hash: 'geo-2',
          qr_payload_hash: 'qr-2',
          nonce: 'nonce-pay2-evidence',
          captured_at_ms: 1730000002000,
          },
        }),
      });
      assert.equal(evidenceOk.err, null);
      assert.equal(!!evidenceOk.res?.accepted, true);

      const issued = invokeHubMemoryUnary(impl, 'IssuePaymentChallenge', {
        request_id: 'req-pay2-issue',
        client,
        intent_id: intentId,
        mobile_terminal_id: 'mobile-allow',
        challenge_nonce: 'challenge-pay2',
      });
      assert.equal(issued.err, null);
      assert.equal(!!issued.res?.issued, true);
      const challengeId = String(issued.res?.challenge_id || '');
      const challengeExpiresAt = Number(issued.res?.expires_at_ms || 0);
      assert.ok(challengeId.length > 0);
      assert.ok(challengeExpiresAt > 0);
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay2-issue',
        event_type: 'payment.challenge.issued',
      });

      const wrongTerminal = invokeHubMemoryUnary(impl, 'ConfirmPaymentIntent', {
        request_id: 'req-pay2-confirm-terminal',
        client,
        intent_id: intentId,
        challenge_id: challengeId,
        mobile_terminal_id: 'mobile-denied',
        auth_factor: 'tap_only',
        confirm_nonce: 'confirm-pay2-1',
        confirmed_at_ms: challengeExpiresAt - 10,
      });
      assert.equal(wrongTerminal.err, null);
      assert.equal(!!wrongTerminal.res?.committed, false);
      assert.equal(String(wrongTerminal.res?.deny_code || ''), 'terminal_not_allowed');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay2-confirm-terminal',
        event_type: 'payment.confirmed',
        error_code: 'terminal_not_allowed',
      });

      const challengeExpired = invokeHubMemoryUnary(impl, 'ConfirmPaymentIntent', {
        request_id: 'req-pay2-confirm-expired',
        client,
        intent_id: intentId,
        challenge_id: challengeId,
        mobile_terminal_id: 'mobile-allow',
        auth_factor: 'tap_only',
        confirm_nonce: 'confirm-pay2-2',
        confirmed_at_ms: challengeExpiresAt + 10,
      });
      assert.equal(challengeExpired.err, null);
      assert.equal(!!challengeExpired.res?.committed, false);
      assert.equal(String(challengeExpired.res?.deny_code || ''), 'challenge_expired');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay2-confirm-expired',
        event_type: 'payment.confirmed',
        error_code: 'challenge_expired',
      });
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay2-confirm-expired',
        event_type: 'payment.expired',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('M3-W2-04/payment challenge nonce replay is blocked until nonce expires', async () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir), async () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-payment-challenge-replay-ttl');

      const createdA = invokeHubMemoryUnary(impl, 'CreatePaymentIntent', {
        request_id: 'req-pay-ch-replay-create-a',
        client,
        amount_minor: 530,
        currency: 'CNY',
        merchant_id: 'merchant-water',
        source_terminal_id: 'robot-kiosk-ch-replay',
        allowed_mobile_terminal_id: 'mobile-ch-replay',
        expected_photo_hash: 'photo-ch-replay-a',
        expected_geo_hash: 'geo-ch-replay-a',
        expected_qr_payload_hash: 'qr-ch-replay-a',
        ttl_ms: 120000,
        challenge_ttl_ms: 2000,
      });
      assert.equal(createdA.err, null);
      assert.equal(!!createdA.res?.accepted, true);
      const intentA = createdA.res?.intent || {};
      const intentAId = String(intentA.intent_id || '');
      assert.ok(intentAId.length > 0);

      const evidenceA = invokeHubMemoryUnary(impl, 'AttachPaymentEvidence', {
        request_id: 'req-pay-ch-replay-evidence-a',
        client,
        intent_id: intentAId,
        evidence: withEvidenceSignature({
          client,
          intent: intentA,
          evidence: {
            photo_hash: 'photo-ch-replay-a',
            price_amount_minor: 530,
            currency: 'CNY',
            merchant_id: 'merchant-water',
            geo_hash: 'geo-ch-replay-a',
            qr_payload_hash: 'qr-ch-replay-a',
            nonce: 'nonce-pay-ch-replay-evidence-a',
            captured_at_ms: 1730000005600,
          },
        }),
      });
      assert.equal(evidenceA.err, null);
      assert.equal(!!evidenceA.res?.accepted, true);

      const challengeNonce = 'nonce-pay-ch-replay-shared';
      const issuedA = invokeHubMemoryUnary(impl, 'IssuePaymentChallenge', {
        request_id: 'req-pay-ch-replay-issue-a',
        client,
        intent_id: intentAId,
        mobile_terminal_id: 'mobile-ch-replay',
        challenge_nonce: challengeNonce,
      });
      assert.equal(issuedA.err, null);
      assert.equal(!!issuedA.res?.issued, true);
      assert.ok(String(issuedA.res?.challenge_id || '').length > 0);

      const createdB = invokeHubMemoryUnary(impl, 'CreatePaymentIntent', {
        request_id: 'req-pay-ch-replay-create-b',
        client,
        amount_minor: 540,
        currency: 'CNY',
        merchant_id: 'merchant-water',
        source_terminal_id: 'robot-kiosk-ch-replay',
        allowed_mobile_terminal_id: 'mobile-ch-replay',
        expected_photo_hash: 'photo-ch-replay-b',
        expected_geo_hash: 'geo-ch-replay-b',
        expected_qr_payload_hash: 'qr-ch-replay-b',
        ttl_ms: 120000,
        challenge_ttl_ms: 2000,
      });
      assert.equal(createdB.err, null);
      assert.equal(!!createdB.res?.accepted, true);
      const intentB = createdB.res?.intent || {};
      const intentBId = String(intentB.intent_id || '');
      assert.ok(intentBId.length > 0);

      const evidenceB = invokeHubMemoryUnary(impl, 'AttachPaymentEvidence', {
        request_id: 'req-pay-ch-replay-evidence-b',
        client,
        intent_id: intentBId,
        evidence: withEvidenceSignature({
          client,
          intent: intentB,
          evidence: {
            photo_hash: 'photo-ch-replay-b',
            price_amount_minor: 540,
            currency: 'CNY',
            merchant_id: 'merchant-water',
            geo_hash: 'geo-ch-replay-b',
            qr_payload_hash: 'qr-ch-replay-b',
            nonce: 'nonce-pay-ch-replay-evidence-b',
            captured_at_ms: 1730000005700,
          },
        }),
      });
      assert.equal(evidenceB.err, null);
      assert.equal(!!evidenceB.res?.accepted, true);

      const replayBlocked = invokeHubMemoryUnary(impl, 'IssuePaymentChallenge', {
        request_id: 'req-pay-ch-replay-issue-b-before-expire',
        client,
        intent_id: intentBId,
        mobile_terminal_id: 'mobile-ch-replay',
        challenge_nonce: challengeNonce,
      });
      assert.equal(replayBlocked.err, null);
      assert.equal(!!replayBlocked.res?.issued, false);
      assert.equal(String(replayBlocked.res?.deny_code || ''), 'replay_detected');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay-ch-replay-issue-b-before-expire',
        event_type: 'payment.challenge.issued',
        error_code: 'replay_detected',
      });
      const blockedAudit = findAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay-ch-replay-issue-b-before-expire',
        event_type: 'payment.challenge.issued',
      });
      assert.ok(blockedAudit);
      const blockedExt = parseAuditExt(blockedAudit);
      assert.equal(String(blockedExt.op || ''), 'issue_payment_challenge');
      assert.equal(String(blockedExt.challenge_id || ''), '');
      assert.equal(Number(blockedExt.expires_at_ms || 0), 0);

      await sleepMs(2300);

      const replayAllowedAfterExpiry = invokeHubMemoryUnary(impl, 'IssuePaymentChallenge', {
        request_id: 'req-pay-ch-replay-issue-b-after-expire',
        client,
        intent_id: intentBId,
        mobile_terminal_id: 'mobile-ch-replay',
        challenge_nonce: challengeNonce,
      });
      assert.equal(replayAllowedAfterExpiry.err, null);
      assert.equal(!!replayAllowedAfterExpiry.res?.issued, true);
      assert.equal(String(replayAllowedAfterExpiry.res?.deny_code || ''), '');
      assert.ok(String(replayAllowedAfterExpiry.res?.challenge_id || '').length > 0);
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay-ch-replay-issue-b-after-expire',
        event_type: 'payment.challenge.issued',
      });
      const allowedAudit = findAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay-ch-replay-issue-b-after-expire',
        event_type: 'payment.challenge.issued',
      });
      assert.ok(allowedAudit);
      const allowedExt = parseAuditExt(allowedAudit);
      assert.equal(String(allowedExt.op || ''), 'issue_payment_challenge');
      assert.ok(String(allowedExt.challenge_id || '').length > 0);
      assert.ok(Number(allowedExt.expires_at_ms || 0) > 0);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W2-04/payment evidence nonce replay is blocked until nonce record expires', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-payment-evidence-replay-ttl');

      const createdA = invokeHubMemoryUnary(impl, 'CreatePaymentIntent', {
        request_id: 'req-pay-ev-replay-create-a',
        client,
        amount_minor: 610,
        currency: 'CNY',
        merchant_id: 'merchant-water',
        source_terminal_id: 'robot-kiosk-ev-replay',
        allowed_mobile_terminal_id: 'mobile-ev-replay',
        expected_photo_hash: 'photo-ev-replay-a',
        expected_geo_hash: 'geo-ev-replay-a',
        expected_qr_payload_hash: 'qr-ev-replay-a',
        ttl_ms: 120000,
        challenge_ttl_ms: 30000,
      });
      assert.equal(createdA.err, null);
      assert.equal(!!createdA.res?.accepted, true);
      const intentA = createdA.res?.intent || {};
      const intentAId = String(intentA.intent_id || '');
      assert.ok(intentAId.length > 0);

      const sharedEvidenceNonce = 'nonce-pay-ev-replay-shared';
      const evidenceA = invokeHubMemoryUnary(impl, 'AttachPaymentEvidence', {
        request_id: 'req-pay-ev-replay-evidence-a',
        client,
        intent_id: intentAId,
        evidence: withEvidenceSignature({
          client,
          intent: intentA,
          evidence: {
            photo_hash: 'photo-ev-replay-a',
            price_amount_minor: 610,
            currency: 'CNY',
            merchant_id: 'merchant-water',
            geo_hash: 'geo-ev-replay-a',
            qr_payload_hash: 'qr-ev-replay-a',
            nonce: sharedEvidenceNonce,
            captured_at_ms: 1730000005800,
          },
        }),
      });
      assert.equal(evidenceA.err, null);
      assert.equal(!!evidenceA.res?.accepted, true);

      const createdB = invokeHubMemoryUnary(impl, 'CreatePaymentIntent', {
        request_id: 'req-pay-ev-replay-create-b',
        client,
        amount_minor: 620,
        currency: 'CNY',
        merchant_id: 'merchant-water',
        source_terminal_id: 'robot-kiosk-ev-replay',
        allowed_mobile_terminal_id: 'mobile-ev-replay',
        expected_photo_hash: 'photo-ev-replay-b',
        expected_geo_hash: 'geo-ev-replay-b',
        expected_qr_payload_hash: 'qr-ev-replay-b',
        ttl_ms: 120000,
        challenge_ttl_ms: 30000,
      });
      assert.equal(createdB.err, null);
      assert.equal(!!createdB.res?.accepted, true);
      const intentB = createdB.res?.intent || {};
      const intentBId = String(intentB.intent_id || '');
      assert.ok(intentBId.length > 0);

      const replayBlocked = invokeHubMemoryUnary(impl, 'AttachPaymentEvidence', {
        request_id: 'req-pay-ev-replay-evidence-b-before-expire',
        client,
        intent_id: intentBId,
        evidence: withEvidenceSignature({
          client,
          intent: intentB,
          evidence: {
            photo_hash: 'photo-ev-replay-b',
            price_amount_minor: 620,
            currency: 'CNY',
            merchant_id: 'merchant-water',
            geo_hash: 'geo-ev-replay-b',
            qr_payload_hash: 'qr-ev-replay-b',
            nonce: sharedEvidenceNonce,
            captured_at_ms: 1730000005900,
          },
        }),
      });
      assert.equal(replayBlocked.err, null);
      assert.equal(!!replayBlocked.res?.accepted, false);
      assert.equal(String(replayBlocked.res?.deny_code || ''), 'replay_detected');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay-ev-replay-evidence-b-before-expire',
        event_type: 'payment.evidence.verified',
        error_code: 'replay_detected',
      });
      const blockedAudit = findAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay-ev-replay-evidence-b-before-expire',
        event_type: 'payment.evidence.verified',
      });
      assert.ok(blockedAudit);
      const blockedExt = parseAuditExt(blockedAudit);
      assert.equal(String(blockedExt.op || ''), 'attach_payment_evidence');

      db.db
        .prepare(
          `UPDATE memory_payment_nonces
           SET expires_at_ms = ?
           WHERE nonce_key = ?`
        )
        .run(Date.now() - 1, `evidence:${sharedEvidenceNonce}`);

      const replayAllowedAfterExpiry = invokeHubMemoryUnary(impl, 'AttachPaymentEvidence', {
        request_id: 'req-pay-ev-replay-evidence-b-after-expire',
        client,
        intent_id: intentBId,
        evidence: withEvidenceSignature({
          client,
          intent: intentB,
          evidence: {
            photo_hash: 'photo-ev-replay-b',
            price_amount_minor: 620,
            currency: 'CNY',
            merchant_id: 'merchant-water',
            geo_hash: 'geo-ev-replay-b',
            qr_payload_hash: 'qr-ev-replay-b',
            nonce: sharedEvidenceNonce,
            captured_at_ms: 1730000005901,
          },
        }),
      });
      assert.equal(replayAllowedAfterExpiry.err, null);
      assert.equal(!!replayAllowedAfterExpiry.res?.accepted, true);
      assert.equal(String(replayAllowedAfterExpiry.res?.deny_code || ''), '');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay-ev-replay-evidence-b-after-expire',
        event_type: 'payment.evidence.verified',
      });
      const allowedAudit = findAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay-ev-replay-evidence-b-after-expire',
        event_type: 'payment.evidence.verified',
      });
      assert.ok(allowedAudit);
      const allowedExt = parseAuditExt(allowedAudit);
      assert.equal(String(allowedExt.op || ''), 'attach_payment_evidence');
      assert.equal(String(allowedExt.signature_scheme || ''), 'sha256');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W2-04/payment confirm nonce replay is blocked until nonce record expires', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-payment-confirm-replay-ttl');

      const createdA = invokeHubMemoryUnary(impl, 'CreatePaymentIntent', {
        request_id: 'req-pay-confirm-replay-create-a',
        client,
        amount_minor: 910,
        currency: 'CNY',
        merchant_id: 'merchant-water',
        source_terminal_id: 'robot-kiosk-confirm-replay',
        allowed_mobile_terminal_id: 'mobile-confirm-replay',
        expected_photo_hash: 'photo-confirm-replay-a',
        expected_geo_hash: 'geo-confirm-replay-a',
        expected_qr_payload_hash: 'qr-confirm-replay-a',
        ttl_ms: 120000,
        challenge_ttl_ms: 30000,
      });
      assert.equal(createdA.err, null);
      assert.equal(!!createdA.res?.accepted, true);
      const intentA = createdA.res?.intent || {};
      const intentAId = String(intentA.intent_id || '');
      assert.ok(intentAId.length > 0);

      const evidenceA = invokeHubMemoryUnary(impl, 'AttachPaymentEvidence', {
        request_id: 'req-pay-confirm-replay-evidence-a',
        client,
        intent_id: intentAId,
        evidence: withEvidenceSignature({
          client,
          intent: intentA,
          evidence: {
            photo_hash: 'photo-confirm-replay-a',
            price_amount_minor: 910,
            currency: 'CNY',
            merchant_id: 'merchant-water',
            geo_hash: 'geo-confirm-replay-a',
            qr_payload_hash: 'qr-confirm-replay-a',
            nonce: 'nonce-pay-confirm-replay-evidence-a',
            captured_at_ms: 1730000006000,
          },
        }),
      });
      assert.equal(evidenceA.err, null);
      assert.equal(!!evidenceA.res?.accepted, true);

      const issuedA = invokeHubMemoryUnary(impl, 'IssuePaymentChallenge', {
        request_id: 'req-pay-confirm-replay-issue-a',
        client,
        intent_id: intentAId,
        mobile_terminal_id: 'mobile-confirm-replay',
        challenge_nonce: 'nonce-pay-confirm-replay-challenge-a',
      });
      assert.equal(issuedA.err, null);
      assert.equal(!!issuedA.res?.issued, true);
      const challengeAId = String(issuedA.res?.challenge_id || '');
      assert.ok(challengeAId.length > 0);

      const sharedConfirmNonce = 'nonce-pay-confirm-replay-shared';
      const confirmedA = invokeHubMemoryUnary(impl, 'ConfirmPaymentIntent', {
        request_id: 'req-pay-confirm-replay-confirm-a',
        client,
        intent_id: intentAId,
        challenge_id: challengeAId,
        mobile_terminal_id: 'mobile-confirm-replay',
        auth_factor: 'tap_only',
        confirm_nonce: sharedConfirmNonce,
      });
      assert.equal(confirmedA.err, null);
      assert.equal(!!confirmedA.res?.committed, true);

      const createdB = invokeHubMemoryUnary(impl, 'CreatePaymentIntent', {
        request_id: 'req-pay-confirm-replay-create-b',
        client,
        amount_minor: 920,
        currency: 'CNY',
        merchant_id: 'merchant-water',
        source_terminal_id: 'robot-kiosk-confirm-replay',
        allowed_mobile_terminal_id: 'mobile-confirm-replay',
        expected_photo_hash: 'photo-confirm-replay-b',
        expected_geo_hash: 'geo-confirm-replay-b',
        expected_qr_payload_hash: 'qr-confirm-replay-b',
        ttl_ms: 120000,
        challenge_ttl_ms: 30000,
      });
      assert.equal(createdB.err, null);
      assert.equal(!!createdB.res?.accepted, true);
      const intentB = createdB.res?.intent || {};
      const intentBId = String(intentB.intent_id || '');
      assert.ok(intentBId.length > 0);

      const evidenceB = invokeHubMemoryUnary(impl, 'AttachPaymentEvidence', {
        request_id: 'req-pay-confirm-replay-evidence-b',
        client,
        intent_id: intentBId,
        evidence: withEvidenceSignature({
          client,
          intent: intentB,
          evidence: {
            photo_hash: 'photo-confirm-replay-b',
            price_amount_minor: 920,
            currency: 'CNY',
            merchant_id: 'merchant-water',
            geo_hash: 'geo-confirm-replay-b',
            qr_payload_hash: 'qr-confirm-replay-b',
            nonce: 'nonce-pay-confirm-replay-evidence-b',
            captured_at_ms: 1730000006100,
          },
        }),
      });
      assert.equal(evidenceB.err, null);
      assert.equal(!!evidenceB.res?.accepted, true);

      const issuedB = invokeHubMemoryUnary(impl, 'IssuePaymentChallenge', {
        request_id: 'req-pay-confirm-replay-issue-b',
        client,
        intent_id: intentBId,
        mobile_terminal_id: 'mobile-confirm-replay',
        challenge_nonce: 'nonce-pay-confirm-replay-challenge-b',
      });
      assert.equal(issuedB.err, null);
      assert.equal(!!issuedB.res?.issued, true);
      const challengeBId = String(issuedB.res?.challenge_id || '');
      assert.ok(challengeBId.length > 0);

      const replayBlocked = invokeHubMemoryUnary(impl, 'ConfirmPaymentIntent', {
        request_id: 'req-pay-confirm-replay-confirm-b-before-expire',
        client,
        intent_id: intentBId,
        challenge_id: challengeBId,
        mobile_terminal_id: 'mobile-confirm-replay',
        auth_factor: 'tap_only',
        confirm_nonce: sharedConfirmNonce,
      });
      assert.equal(replayBlocked.err, null);
      assert.equal(!!replayBlocked.res?.committed, false);
      assert.equal(String(replayBlocked.res?.deny_code || ''), 'replay_detected');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay-confirm-replay-confirm-b-before-expire',
        event_type: 'payment.confirmed',
        error_code: 'replay_detected',
      });
      const blockedAudit = findAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay-confirm-replay-confirm-b-before-expire',
        event_type: 'payment.confirmed',
      });
      assert.ok(blockedAudit);
      const blockedExt = parseAuditExt(blockedAudit);
      assert.equal(String(blockedExt.op || ''), 'confirm_payment_intent');
      assert.equal(!!blockedExt.idempotent, false);
      assert.equal(String(blockedExt.status || ''), 'pending_user_auth');
      assert.equal(String(blockedExt.receipt_delivery_state || ''), 'prepared');

      db.db
        .prepare(
          `UPDATE memory_payment_nonces
           SET expires_at_ms = ?
           WHERE nonce_key = ?`
        )
        .run(Date.now() - 1, `confirm:${sharedConfirmNonce}`);

      const replayAllowedAfterExpiry = invokeHubMemoryUnary(impl, 'ConfirmPaymentIntent', {
        request_id: 'req-pay-confirm-replay-confirm-b-after-expire',
        client,
        intent_id: intentBId,
        challenge_id: challengeBId,
        mobile_terminal_id: 'mobile-confirm-replay',
        auth_factor: 'tap_only',
        confirm_nonce: sharedConfirmNonce,
      });
      assert.equal(replayAllowedAfterExpiry.err, null);
      assert.equal(!!replayAllowedAfterExpiry.res?.committed, true);
      assert.equal(!!replayAllowedAfterExpiry.res?.idempotent, false);
      assert.equal(String(replayAllowedAfterExpiry.res?.deny_code || ''), '');
      const commitTxnId = String(replayAllowedAfterExpiry.res?.intent?.commit_txn_id || '');
      assert.ok(commitTxnId.length > 0);
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay-confirm-replay-confirm-b-after-expire',
        event_type: 'payment.confirmed',
      });
      const allowedAudit = findAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay-confirm-replay-confirm-b-after-expire',
        event_type: 'payment.confirmed',
      });
      assert.ok(allowedAudit);
      const allowedExt = parseAuditExt(allowedAudit);
      assert.equal(String(allowedExt.op || ''), 'confirm_payment_intent');
      assert.equal(!!allowedExt.idempotent, false);
      assert.equal(String(allowedExt.status || ''), 'committed');
      assert.equal(String(allowedExt.receipt_delivery_state || ''), 'committed');

      const replayIdempotentAfterCommit = invokeHubMemoryUnary(impl, 'ConfirmPaymentIntent', {
        request_id: 'req-pay-confirm-replay-confirm-b-idempotent',
        client,
        intent_id: intentBId,
        challenge_id: challengeBId,
        mobile_terminal_id: 'mobile-confirm-replay',
        auth_factor: 'tap_only',
        confirm_nonce: sharedConfirmNonce,
      });
      assert.equal(replayIdempotentAfterCommit.err, null);
      assert.equal(!!replayIdempotentAfterCommit.res?.committed, true);
      assert.equal(!!replayIdempotentAfterCommit.res?.idempotent, true);
      assert.equal(String(replayIdempotentAfterCommit.res?.deny_code || ''), '');
      assert.equal(String(replayIdempotentAfterCommit.res?.intent?.commit_txn_id || ''), commitTxnId);
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay-confirm-replay-confirm-b-idempotent',
        event_type: 'payment.confirmed',
      });
      const idempotentAudit = findAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay-confirm-replay-confirm-b-idempotent',
        event_type: 'payment.confirmed',
      });
      assert.ok(idempotentAudit);
      const idempotentExt = parseAuditExt(idempotentAudit);
      assert.equal(String(idempotentExt.op || ''), 'confirm_payment_intent');
      assert.equal(!!idempotentExt.idempotent, true);
      assert.equal(String(idempotentExt.status || ''), 'committed');
      assert.equal(String(idempotentExt.receipt_delivery_state || ''), 'committed');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W2-04/payment confirm idempotent commit + abort idempotency', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-payment-idem');

      const created = invokeHubMemoryUnary(impl, 'CreatePaymentIntent', {
        request_id: 'req-pay3-create',
        client,
        amount_minor: 800,
        currency: 'CNY',
        merchant_id: 'merchant-water',
        source_terminal_id: 'robot-kiosk-3',
        allowed_mobile_terminal_id: 'mobile-idem',
        expected_photo_hash: 'photo-3',
        expected_geo_hash: 'geo-3',
        expected_qr_payload_hash: 'qr-3',
        ttl_ms: 120000,
        challenge_ttl_ms: 30000,
      });
      assert.equal(created.err, null);
      assert.equal(!!created.res?.accepted, true);
      const createdIntent = created.res?.intent || {};
      const intentId = String(created.res?.intent?.intent_id || '');
      assert.ok(intentId.length > 0);

      const evidence = invokeHubMemoryUnary(impl, 'AttachPaymentEvidence', {
        request_id: 'req-pay3-evidence',
        client,
        intent_id: intentId,
        evidence: withEvidenceSignature({
          client,
          intent: createdIntent,
          evidence: {
          photo_hash: 'photo-3',
          price_amount_minor: 800,
          currency: 'CNY',
          merchant_id: 'merchant-water',
          geo_hash: 'geo-3',
          qr_payload_hash: 'qr-3',
          nonce: 'nonce-pay3-evidence',
          captured_at_ms: 1730000003000,
          },
        }),
      });
      assert.equal(evidence.err, null);
      assert.equal(!!evidence.res?.accepted, true);

      const issued = invokeHubMemoryUnary(impl, 'IssuePaymentChallenge', {
        request_id: 'req-pay3-issue',
        client,
        intent_id: intentId,
        mobile_terminal_id: 'mobile-idem',
        challenge_nonce: 'nonce-pay3-challenge',
      });
      assert.equal(issued.err, null);
      assert.equal(!!issued.res?.issued, true);
      const challengeId = String(issued.res?.challenge_id || '');
      assert.ok(challengeId.length > 0);

      const confirmed = invokeHubMemoryUnary(impl, 'ConfirmPaymentIntent', {
        request_id: 'req-pay3-confirm-1',
        client,
        intent_id: intentId,
        challenge_id: challengeId,
        mobile_terminal_id: 'mobile-idem',
        auth_factor: 'tap_only',
        confirm_nonce: 'nonce-pay3-confirm',
      });
      assert.equal(confirmed.err, null);
      assert.equal(!!confirmed.res?.committed, true);
      assert.equal(!!confirmed.res?.idempotent, false);
      const commitTxnId = String(confirmed.res?.intent?.commit_txn_id || '');
      assert.ok(commitTxnId.length > 0);
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay3-confirm-1',
        event_type: 'payment.confirmed',
      });

      const confirmedAgain = invokeHubMemoryUnary(impl, 'ConfirmPaymentIntent', {
        request_id: 'req-pay3-confirm-2',
        client,
        intent_id: intentId,
        challenge_id: challengeId,
        mobile_terminal_id: 'mobile-idem',
        auth_factor: 'tap_only',
        confirm_nonce: 'nonce-pay3-confirm',
      });
      assert.equal(confirmedAgain.err, null);
      assert.equal(!!confirmedAgain.res?.committed, true);
      assert.equal(!!confirmedAgain.res?.idempotent, true);
      assert.equal(String(confirmedAgain.res?.intent?.commit_txn_id || ''), commitTxnId);

      const createdAbort = invokeHubMemoryUnary(impl, 'CreatePaymentIntent', {
        request_id: 'req-pay3-create-abort',
        client,
        amount_minor: 120,
        currency: 'CNY',
        merchant_id: 'merchant-water',
        source_terminal_id: 'robot-kiosk-3',
        allowed_mobile_terminal_id: 'mobile-idem',
      });
      assert.equal(createdAbort.err, null);
      assert.equal(!!createdAbort.res?.accepted, true);
      const abortIntentId = String(createdAbort.res?.intent?.intent_id || '');

      const aborted = invokeHubMemoryUnary(impl, 'AbortPaymentIntent', {
        request_id: 'req-pay3-abort-1',
        client,
        intent_id: abortIntentId,
        reason: 'user_canceled',
      });
      assert.equal(aborted.err, null);
      assert.equal(!!aborted.res?.aborted, true);
      assert.equal(!!aborted.res?.idempotent, false);
      assert.equal(!!aborted.res?.compensation_pending, false);
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay3-abort-1',
        event_type: 'payment.aborted',
      });

      const abortedAgain = invokeHubMemoryUnary(impl, 'AbortPaymentIntent', {
        request_id: 'req-pay3-abort-2',
        client,
        intent_id: abortIntentId,
        reason: 'user_canceled',
      });
      assert.equal(abortedAgain.err, null);
      assert.equal(!!abortedAgain.res?.aborted, true);
      assert.equal(!!abortedAgain.res?.idempotent, true);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W2-04/payment committed re-confirm enforces challenge/mobile/nonce binding', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-payment-binding');

      const created = invokeHubMemoryUnary(impl, 'CreatePaymentIntent', {
        request_id: 'req-pay-binding-create',
        client,
        amount_minor: 920,
        currency: 'CNY',
        merchant_id: 'merchant-water',
        source_terminal_id: 'robot-kiosk-5',
        allowed_mobile_terminal_id: 'mobile-bind',
        expected_photo_hash: 'photo-bind',
        expected_geo_hash: 'geo-bind',
        expected_qr_payload_hash: 'qr-bind',
        ttl_ms: 120000,
        challenge_ttl_ms: 30000,
      });
      assert.equal(created.err, null);
      assert.equal(!!created.res?.accepted, true);
      const createdIntent = created.res?.intent || {};
      const intentId = String(created.res?.intent?.intent_id || '');
      assert.ok(intentId.length > 0);

      const evidence = invokeHubMemoryUnary(impl, 'AttachPaymentEvidence', {
        request_id: 'req-pay-binding-evidence',
        client,
        intent_id: intentId,
        evidence: withEvidenceSignature({
          client,
          intent: createdIntent,
          evidence: {
          photo_hash: 'photo-bind',
          price_amount_minor: 920,
          currency: 'CNY',
          merchant_id: 'merchant-water',
          geo_hash: 'geo-bind',
          qr_payload_hash: 'qr-bind',
          nonce: 'nonce-pay-binding-evidence',
          captured_at_ms: 1730000005000,
          },
        }),
      });
      assert.equal(evidence.err, null);
      assert.equal(!!evidence.res?.accepted, true);

      const issued = invokeHubMemoryUnary(impl, 'IssuePaymentChallenge', {
        request_id: 'req-pay-binding-issue',
        client,
        intent_id: intentId,
        mobile_terminal_id: 'mobile-bind',
        challenge_nonce: 'nonce-pay-binding-challenge',
      });
      assert.equal(issued.err, null);
      assert.equal(!!issued.res?.issued, true);
      const challengeId = String(issued.res?.challenge_id || '');
      assert.ok(challengeId.length > 0);

      const confirmed = invokeHubMemoryUnary(impl, 'ConfirmPaymentIntent', {
        request_id: 'req-pay-binding-confirm-1',
        client,
        intent_id: intentId,
        challenge_id: challengeId,
        mobile_terminal_id: 'mobile-bind',
        auth_factor: 'tap_only',
        confirm_nonce: 'nonce-pay-binding-confirm',
      });
      assert.equal(confirmed.err, null);
      assert.equal(!!confirmed.res?.committed, true);
      assert.equal(!!confirmed.res?.idempotent, false);

      const wrongTerminal = invokeHubMemoryUnary(impl, 'ConfirmPaymentIntent', {
        request_id: 'req-pay-binding-confirm-terminal',
        client,
        intent_id: intentId,
        challenge_id: challengeId,
        mobile_terminal_id: 'mobile-bind-other',
        auth_factor: 'tap_only',
        confirm_nonce: 'nonce-pay-binding-confirm',
      });
      assert.equal(wrongTerminal.err, null);
      assert.equal(!!wrongTerminal.res?.committed, false);
      assert.equal(String(wrongTerminal.res?.deny_code || ''), 'terminal_not_allowed');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay-binding-confirm-terminal',
        event_type: 'payment.confirmed',
        error_code: 'terminal_not_allowed',
      });

      const wrongChallenge = invokeHubMemoryUnary(impl, 'ConfirmPaymentIntent', {
        request_id: 'req-pay-binding-confirm-challenge',
        client,
        intent_id: intentId,
        challenge_id: 'challenge-other',
        mobile_terminal_id: 'mobile-bind',
        auth_factor: 'tap_only',
        confirm_nonce: 'nonce-pay-binding-confirm',
      });
      assert.equal(wrongChallenge.err, null);
      assert.equal(!!wrongChallenge.res?.committed, false);
      assert.equal(String(wrongChallenge.res?.deny_code || ''), 'invalid_request');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay-binding-confirm-challenge',
        event_type: 'payment.confirmed',
        error_code: 'invalid_request',
      });

      const newNonceAfterCommit = invokeHubMemoryUnary(impl, 'ConfirmPaymentIntent', {
        request_id: 'req-pay-binding-confirm-new-nonce',
        client,
        intent_id: intentId,
        challenge_id: challengeId,
        mobile_terminal_id: 'mobile-bind',
        auth_factor: 'tap_only',
        confirm_nonce: 'nonce-pay-binding-confirm-2',
      });
      assert.equal(newNonceAfterCommit.err, null);
      assert.equal(!!newNonceAfterCommit.res?.committed, false);
      assert.equal(String(newNonceAfterCommit.res?.deny_code || ''), 'intent_state_invalid');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay-binding-confirm-new-nonce',
        event_type: 'payment.confirmed',
        error_code: 'intent_state_invalid',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('M3-W2-04/payment receipt undo window + compensation worker closes committed intent', async () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir, {
    HUB_PAYMENT_INTENT_SWEEP_MS: '50',
    HUB_PAYMENT_INTENT_SWEEP_LIMIT: '100',
    HUB_PAYMENT_RECEIPT_COMPENSATION_DELAY_MS: '0',
    HUB_PAYMENT_RECEIPT_UNDO_WINDOW_MS: '1000',
  }), async () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-payment-receipt-worker');
      const created = invokeHubMemoryUnary(impl, 'CreatePaymentIntent', {
        request_id: 'req-pay-receipt-create',
        client,
        amount_minor: 660,
        currency: 'CNY',
        merchant_id: 'merchant-water',
        source_terminal_id: 'robot-kiosk-receipt',
        allowed_mobile_terminal_id: 'mobile-receipt',
        expected_photo_hash: 'photo-receipt',
        expected_geo_hash: 'geo-receipt',
        expected_qr_payload_hash: 'qr-receipt',
        ttl_ms: 120000,
        challenge_ttl_ms: 30000,
      });
      assert.equal(created.err, null);
      assert.equal(!!created.res?.accepted, true);
      const createdIntent = created.res?.intent || {};
      const intentId = String(createdIntent.intent_id || '');
      assert.ok(intentId.length > 0);

      const evidence = invokeHubMemoryUnary(impl, 'AttachPaymentEvidence', {
        request_id: 'req-pay-receipt-evidence',
        client,
        intent_id: intentId,
        evidence: withEvidenceSignature({
          client,
          intent: createdIntent,
          evidence: {
            photo_hash: 'photo-receipt',
            price_amount_minor: 660,
            currency: 'CNY',
            merchant_id: 'merchant-water',
            geo_hash: 'geo-receipt',
            qr_payload_hash: 'qr-receipt',
            nonce: 'nonce-pay-receipt-evidence',
            captured_at_ms: 1730000005200,
          },
        }),
      });
      assert.equal(evidence.err, null);
      assert.equal(!!evidence.res?.accepted, true);

      const issued = invokeHubMemoryUnary(impl, 'IssuePaymentChallenge', {
        request_id: 'req-pay-receipt-issue',
        client,
        intent_id: intentId,
        mobile_terminal_id: 'mobile-receipt',
        challenge_nonce: 'nonce-pay-receipt-challenge',
      });
      assert.equal(issued.err, null);
      assert.equal(!!issued.res?.issued, true);
      const challengeId = String(issued.res?.challenge_id || '');
      assert.ok(challengeId.length > 0);

      const confirmed = invokeHubMemoryUnary(impl, 'ConfirmPaymentIntent', {
        request_id: 'req-pay-receipt-confirm',
        client,
        intent_id: intentId,
        challenge_id: challengeId,
        mobile_terminal_id: 'mobile-receipt',
        auth_factor: 'tap_only',
        confirm_nonce: 'nonce-pay-receipt-confirm',
      });
      assert.equal(confirmed.err, null);
      assert.equal(!!confirmed.res?.committed, true);
      assert.equal(String(confirmed.res?.intent?.receipt_delivery_state || ''), 'committed');

      const abortReq = invokeHubMemoryUnary(impl, 'AbortPaymentIntent', {
        request_id: 'req-pay-receipt-abort',
        client,
        intent_id: intentId,
        reason: 'user_abort_requested',
      });
      assert.equal(abortReq.err, null);
      assert.equal(!!abortReq.res?.aborted, true);
      assert.equal(!!abortReq.res?.compensation_pending, true);
      assert.equal(String(abortReq.res?.intent?.status || ''), 'committed');
      assert.equal(String(abortReq.res?.intent?.receipt_delivery_state || ''), 'undo_pending');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay-receipt-abort',
        event_type: 'payment.aborted',
      });

      const abortReqAgain = invokeHubMemoryUnary(impl, 'AbortPaymentIntent', {
        request_id: 'req-pay-receipt-abort-2',
        client,
        intent_id: intentId,
        reason: 'user_abort_requested',
      });
      assert.equal(abortReqAgain.err, null);
      assert.equal(!!abortReqAgain.res?.aborted, true);
      assert.equal(!!abortReqAgain.res?.idempotent, true);
      assert.equal(!!abortReqAgain.res?.compensation_pending, true);
      assert.equal(String(abortReqAgain.res?.intent?.status || ''), 'committed');
      assert.equal(String(abortReqAgain.res?.intent?.receipt_delivery_state || ''), 'undo_pending');

      const compensatedReady = await waitFor(() => {
        const row = db._getPaymentIntentRowRaw({
          intent_id: intentId,
          device_id: client.device_id,
          user_id: client.user_id,
          app_id: client.app_id,
          project_id: client.project_id,
        });
        return String(row?.status || '') === 'aborted'
          && String(row?.receipt_delivery_state || '') === 'compensated';
      }, { timeoutMs: 2000, stepMs: 50 });
      assert.equal(compensatedReady, true);

      const post = db._getPaymentIntentRowRaw({
        intent_id: intentId,
        device_id: client.device_id,
        user_id: client.user_id,
        app_id: client.app_id,
        project_id: client.project_id,
      });
      assert.ok(post);
      assert.equal(String(post?.status || ''), 'aborted');
      assert.equal(String(post?.receipt_delivery_state || ''), 'compensated');
      assert.ok(Number(post?.receipt_compensated_at_ms || 0) > 0);

      const abortAfterCompensated = invokeHubMemoryUnary(impl, 'AbortPaymentIntent', {
        request_id: 'req-pay-receipt-abort-3',
        client,
        intent_id: intentId,
        reason: 'late_abort_after_compensated',
      });
      assert.equal(abortAfterCompensated.err, null);
      assert.equal(!!abortAfterCompensated.res?.aborted, true);
      assert.equal(!!abortAfterCompensated.res?.idempotent, true);
      assert.equal(!!abortAfterCompensated.res?.compensation_pending, false);
      assert.equal(String(abortAfterCompensated.res?.intent?.status || ''), 'aborted');
      assert.equal(String(abortAfterCompensated.res?.intent?.receipt_delivery_state || ''), 'compensated');

      const audits = db.listAuditEvents({
        project_id: client.project_id,
      });
      const workerAudit = audits.find((item) => (
        String(item?.event_type || '') === 'payment.aborted'
        && String(item?.ext_json || '').includes(`"intent_id":"${intentId}"`)
        && String(item?.ext_json || '').includes('"receipt_delivery_state":"compensated"')
        && !String(item?.request_id || '').trim()
      ));
      assert.ok(workerAudit, 'expected payment.aborted audit emitted by compensation worker');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('M3-W2-04/payment receipt auto-compensates after undo window timeout without abort RPC', async () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir, {
    HUB_PAYMENT_INTENT_SWEEP_MS: '50',
    HUB_PAYMENT_INTENT_SWEEP_LIMIT: '100',
    HUB_PAYMENT_RECEIPT_COMPENSATION_DELAY_MS: '0',
    HUB_PAYMENT_RECEIPT_UNDO_WINDOW_MS: '120',
  }), async () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-payment-receipt-timeout');
      const created = invokeHubMemoryUnary(impl, 'CreatePaymentIntent', {
        request_id: 'req-pay-receipt-timeout-create',
        client,
        amount_minor: 860,
        currency: 'CNY',
        merchant_id: 'merchant-water',
        source_terminal_id: 'robot-kiosk-timeout',
        allowed_mobile_terminal_id: 'mobile-timeout',
        expected_photo_hash: 'photo-timeout',
        expected_geo_hash: 'geo-timeout',
        expected_qr_payload_hash: 'qr-timeout',
        ttl_ms: 120000,
        challenge_ttl_ms: 30000,
      });
      assert.equal(created.err, null);
      assert.equal(!!created.res?.accepted, true);
      const createdIntent = created.res?.intent || {};
      const intentId = String(createdIntent.intent_id || '');
      assert.ok(intentId.length > 0);

      const evidence = invokeHubMemoryUnary(impl, 'AttachPaymentEvidence', {
        request_id: 'req-pay-receipt-timeout-evidence',
        client,
        intent_id: intentId,
        evidence: withEvidenceSignature({
          client,
          intent: createdIntent,
          evidence: {
            photo_hash: 'photo-timeout',
            price_amount_minor: 860,
            currency: 'CNY',
            merchant_id: 'merchant-water',
            geo_hash: 'geo-timeout',
            qr_payload_hash: 'qr-timeout',
            nonce: 'nonce-pay-receipt-timeout-evidence',
            captured_at_ms: 1730000005300,
          },
        }),
      });
      assert.equal(evidence.err, null);
      assert.equal(!!evidence.res?.accepted, true);

      const issued = invokeHubMemoryUnary(impl, 'IssuePaymentChallenge', {
        request_id: 'req-pay-receipt-timeout-issue',
        client,
        intent_id: intentId,
        mobile_terminal_id: 'mobile-timeout',
        challenge_nonce: 'nonce-pay-receipt-timeout-challenge',
      });
      assert.equal(issued.err, null);
      assert.equal(!!issued.res?.issued, true);
      const challengeId = String(issued.res?.challenge_id || '');
      assert.ok(challengeId.length > 0);

      const confirmed = invokeHubMemoryUnary(impl, 'ConfirmPaymentIntent', {
        request_id: 'req-pay-receipt-timeout-confirm',
        client,
        intent_id: intentId,
        challenge_id: challengeId,
        mobile_terminal_id: 'mobile-timeout',
        auth_factor: 'tap_only',
        confirm_nonce: 'nonce-pay-receipt-timeout-confirm',
      });
      assert.equal(confirmed.err, null);
      assert.equal(!!confirmed.res?.committed, true);
      assert.equal(String(confirmed.res?.intent?.status || ''), 'committed');
      assert.equal(String(confirmed.res?.intent?.receipt_delivery_state || ''), 'committed');

      const compensatedReady = await waitFor(() => {
        const row = db._getPaymentIntentRowRaw({
          intent_id: intentId,
          device_id: client.device_id,
          user_id: client.user_id,
          app_id: client.app_id,
          project_id: client.project_id,
        });
        return String(row?.status || '') === 'aborted'
          && String(row?.receipt_delivery_state || '') === 'compensated';
      }, { timeoutMs: 2500, stepMs: 50 });
      assert.equal(compensatedReady, true);

      const post = db._getPaymentIntentRowRaw({
        intent_id: intentId,
        device_id: client.device_id,
        user_id: client.user_id,
        app_id: client.app_id,
        project_id: client.project_id,
      });
      assert.ok(post);
      assert.equal(String(post?.status || ''), 'aborted');
      assert.equal(String(post?.receipt_delivery_state || ''), 'compensated');
      assert.equal(String(post?.abort_reason || ''), 'undo_window_expired');
      assert.equal(String(post?.receipt_compensation_reason || ''), 'undo_window_expired');
      assert.ok(Number(post?.receipt_compensated_at_ms || 0) > 0);

      const audits = db.listAuditEvents({
        project_id: client.project_id,
      });
      const workerAudit = audits.find((item) => (
        String(item?.event_type || '') === 'payment.aborted'
        && String(item?.ext_json || '').includes(`"intent_id":"${intentId}"`)
        && String(item?.ext_json || '').includes('"receipt_delivery_state":"compensated"')
        && !String(item?.request_id || '').trim()
      ));
      assert.ok(workerAudit, 'expected payment.aborted audit emitted by compensation worker');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('M3-W2-04/payment abort after undo window is denied fail-closed with audit', async () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir, {
    HUB_PAYMENT_INTENT_SWEEP_MS: '5000',
    HUB_PAYMENT_INTENT_SWEEP_LIMIT: '100',
    HUB_PAYMENT_RECEIPT_COMPENSATION_DELAY_MS: '0',
    HUB_PAYMENT_RECEIPT_UNDO_WINDOW_MS: '1000',
  }), async () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-payment-receipt-late-abort');
      const created = invokeHubMemoryUnary(impl, 'CreatePaymentIntent', {
        request_id: 'req-pay-receipt-late-abort-create',
        client,
        amount_minor: 990,
        currency: 'CNY',
        merchant_id: 'merchant-water',
        source_terminal_id: 'robot-kiosk-late-abort',
        allowed_mobile_terminal_id: 'mobile-late-abort',
        expected_photo_hash: 'photo-late-abort',
        expected_geo_hash: 'geo-late-abort',
        expected_qr_payload_hash: 'qr-late-abort',
        ttl_ms: 120000,
        challenge_ttl_ms: 30000,
      });
      assert.equal(created.err, null);
      assert.equal(!!created.res?.accepted, true);
      const createdIntent = created.res?.intent || {};
      const intentId = String(createdIntent.intent_id || '');
      assert.ok(intentId.length > 0);

      const evidence = invokeHubMemoryUnary(impl, 'AttachPaymentEvidence', {
        request_id: 'req-pay-receipt-late-abort-evidence',
        client,
        intent_id: intentId,
        evidence: withEvidenceSignature({
          client,
          intent: createdIntent,
          evidence: {
            photo_hash: 'photo-late-abort',
            price_amount_minor: 990,
            currency: 'CNY',
            merchant_id: 'merchant-water',
            geo_hash: 'geo-late-abort',
            qr_payload_hash: 'qr-late-abort',
            nonce: 'nonce-pay-receipt-late-abort-evidence',
            captured_at_ms: 1730000005400,
          },
        }),
      });
      assert.equal(evidence.err, null);
      assert.equal(!!evidence.res?.accepted, true);

      const issued = invokeHubMemoryUnary(impl, 'IssuePaymentChallenge', {
        request_id: 'req-pay-receipt-late-abort-issue',
        client,
        intent_id: intentId,
        mobile_terminal_id: 'mobile-late-abort',
        challenge_nonce: 'nonce-pay-receipt-late-abort-challenge',
      });
      assert.equal(issued.err, null);
      assert.equal(!!issued.res?.issued, true);
      const challengeId = String(issued.res?.challenge_id || '');
      assert.ok(challengeId.length > 0);

      const confirmed = invokeHubMemoryUnary(impl, 'ConfirmPaymentIntent', {
        request_id: 'req-pay-receipt-late-abort-confirm',
        client,
        intent_id: intentId,
        challenge_id: challengeId,
        mobile_terminal_id: 'mobile-late-abort',
        auth_factor: 'tap_only',
        confirm_nonce: 'nonce-pay-receipt-late-abort-confirm',
      });
      assert.equal(confirmed.err, null);
      assert.equal(!!confirmed.res?.committed, true);
      assert.equal(String(confirmed.res?.intent?.status || ''), 'committed');
      assert.equal(String(confirmed.res?.intent?.receipt_delivery_state || ''), 'committed');

      // Wait past undo window while compensation worker is intentionally slow (5s sweep) so abort hits the boundary.
      await sleepMs(1200);

      const lateAbort = invokeHubMemoryUnary(impl, 'AbortPaymentIntent', {
        request_id: 'req-pay-receipt-late-abort',
        client,
        intent_id: intentId,
        reason: 'late_abort_after_undo_window',
      });
      assert.equal(lateAbort.err, null);
      assert.equal(!!lateAbort.res?.aborted, false);
      assert.equal(!!lateAbort.res?.idempotent, false);
      assert.equal(String(lateAbort.res?.deny_code || ''), 'intent_state_invalid');
      assert.equal(!!lateAbort.res?.compensation_pending, false);
      assert.equal(String(lateAbort.res?.intent?.status || ''), 'committed');
      assert.equal(String(lateAbort.res?.intent?.receipt_delivery_state || ''), 'committed');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay-receipt-late-abort',
        event_type: 'payment.aborted',
        error_code: 'intent_state_invalid',
      });

      await sleepMs(300);
      const row = db._getPaymentIntentRowRaw({
        intent_id: intentId,
        device_id: client.device_id,
        user_id: client.user_id,
        app_id: client.app_id,
        project_id: client.project_id,
      });
      assert.ok(row);
      assert.equal(String(row?.status || ''), 'committed');
      assert.equal(String(row?.receipt_delivery_state || ''), 'committed');

      const promotedBeforeSweep = await waitFor(() => {
        const latest = db._getPaymentIntentRowRaw({
          intent_id: intentId,
          device_id: client.device_id,
          user_id: client.user_id,
          app_id: client.app_id,
          project_id: client.project_id,
        });
        const latestStatus = String(latest?.status || '');
        const latestReceiptState = String(latest?.receipt_delivery_state || '');
        return latestStatus === 'aborted'
          || latestReceiptState === 'undo_pending'
          || latestReceiptState === 'compensated';
      }, { timeoutMs: 1000, stepMs: 50 });
      assert.equal(promotedBeforeSweep, false);

      const audits = db.listAuditEvents({
        project_id: client.project_id,
      });
      const prematureWorkerAudit = audits.find((item) => (
        String(item?.event_type || '') === 'payment.aborted'
        && String(item?.ext_json || '').includes(`"intent_id":"${intentId}"`)
        && String(item?.ext_json || '').includes('"receipt_delivery_state":"compensated"')
        && !String(item?.request_id || '').trim()
      ));
      assert.ok(!prematureWorkerAudit, 'did not expect worker compensation audit before sweep interval');

      const compensatedAfterSweep = await waitFor(() => {
        const latest = db._getPaymentIntentRowRaw({
          intent_id: intentId,
          device_id: client.device_id,
          user_id: client.user_id,
          app_id: client.app_id,
          project_id: client.project_id,
        });
        return String(latest?.status || '') === 'aborted'
          && String(latest?.receipt_delivery_state || '') === 'compensated';
      }, { timeoutMs: 6500, stepMs: 100 });
      assert.equal(compensatedAfterSweep, true);

      const auditsAfterSweep = db.listAuditEvents({
        project_id: client.project_id,
      });
      const workerAuditAfterSweep = auditsAfterSweep.find((item) => (
        String(item?.event_type || '') === 'payment.aborted'
        && String(item?.ext_json || '').includes(`"intent_id":"${intentId}"`)
        && String(item?.ext_json || '').includes('"receipt_delivery_state":"compensated"')
        && !String(item?.request_id || '').trim()
      ));
      assert.ok(workerAuditAfterSweep, 'expected worker compensation audit after sweep interval');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('M3-W2-04/payment abort during worker-promoted undo_pending stays idempotent and compensation_pending', async () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir, {
    HUB_PAYMENT_INTENT_SWEEP_MS: '50',
    HUB_PAYMENT_INTENT_SWEEP_LIMIT: '100',
    HUB_PAYMENT_RECEIPT_COMPENSATION_DELAY_MS: '800',
    HUB_PAYMENT_RECEIPT_UNDO_WINDOW_MS: '1000',
  }), async () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-payment-receipt-auto-undo');
      const created = invokeHubMemoryUnary(impl, 'CreatePaymentIntent', {
        request_id: 'req-pay-receipt-auto-undo-create',
        client,
        amount_minor: 710,
        currency: 'CNY',
        merchant_id: 'merchant-water',
        source_terminal_id: 'robot-kiosk-auto-undo',
        allowed_mobile_terminal_id: 'mobile-auto-undo',
        expected_photo_hash: 'photo-auto-undo',
        expected_geo_hash: 'geo-auto-undo',
        expected_qr_payload_hash: 'qr-auto-undo',
        ttl_ms: 120000,
        challenge_ttl_ms: 30000,
      });
      assert.equal(created.err, null);
      assert.equal(!!created.res?.accepted, true);
      const createdIntent = created.res?.intent || {};
      const intentId = String(createdIntent.intent_id || '');
      assert.ok(intentId.length > 0);

      const evidence = invokeHubMemoryUnary(impl, 'AttachPaymentEvidence', {
        request_id: 'req-pay-receipt-auto-undo-evidence',
        client,
        intent_id: intentId,
        evidence: withEvidenceSignature({
          client,
          intent: createdIntent,
          evidence: {
            photo_hash: 'photo-auto-undo',
            price_amount_minor: 710,
            currency: 'CNY',
            merchant_id: 'merchant-water',
            geo_hash: 'geo-auto-undo',
            qr_payload_hash: 'qr-auto-undo',
            nonce: 'nonce-pay-receipt-auto-undo-evidence',
            captured_at_ms: 1730000005500,
          },
        }),
      });
      assert.equal(evidence.err, null);
      assert.equal(!!evidence.res?.accepted, true);

      const issued = invokeHubMemoryUnary(impl, 'IssuePaymentChallenge', {
        request_id: 'req-pay-receipt-auto-undo-issue',
        client,
        intent_id: intentId,
        mobile_terminal_id: 'mobile-auto-undo',
        challenge_nonce: 'nonce-pay-receipt-auto-undo-challenge',
      });
      assert.equal(issued.err, null);
      assert.equal(!!issued.res?.issued, true);
      const challengeId = String(issued.res?.challenge_id || '');
      assert.ok(challengeId.length > 0);

      const confirmed = invokeHubMemoryUnary(impl, 'ConfirmPaymentIntent', {
        request_id: 'req-pay-receipt-auto-undo-confirm',
        client,
        intent_id: intentId,
        challenge_id: challengeId,
        mobile_terminal_id: 'mobile-auto-undo',
        auth_factor: 'tap_only',
        confirm_nonce: 'nonce-pay-receipt-auto-undo-confirm',
      });
      assert.equal(confirmed.err, null);
      assert.equal(!!confirmed.res?.committed, true);
      assert.equal(String(confirmed.res?.intent?.status || ''), 'committed');
      assert.equal(String(confirmed.res?.intent?.receipt_delivery_state || ''), 'committed');

      const autoUndoPendingReady = await waitFor(() => {
        const row = db._getPaymentIntentRowRaw({
          intent_id: intentId,
          device_id: client.device_id,
          user_id: client.user_id,
          app_id: client.app_id,
          project_id: client.project_id,
        });
        return String(row?.status || '') === 'committed'
          && String(row?.receipt_delivery_state || '') === 'undo_pending';
      }, { timeoutMs: 2600, stepMs: 50 });
      assert.equal(autoUndoPendingReady, true);

      const abortInUndoPending = invokeHubMemoryUnary(impl, 'AbortPaymentIntent', {
        request_id: 'req-pay-receipt-auto-undo-abort',
        client,
        intent_id: intentId,
        reason: 'abort_during_auto_undo_pending',
      });
      assert.equal(abortInUndoPending.err, null);
      assert.equal(!!abortInUndoPending.res?.aborted, true);
      assert.equal(!!abortInUndoPending.res?.idempotent, true);
      assert.equal(!!abortInUndoPending.res?.compensation_pending, true);
      assert.equal(String(abortInUndoPending.res?.intent?.status || ''), 'committed');
      assert.equal(String(abortInUndoPending.res?.intent?.receipt_delivery_state || ''), 'undo_pending');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'req-pay-receipt-auto-undo-abort',
        event_type: 'payment.aborted',
      });

      const compensatedReady = await waitFor(() => {
        const row = db._getPaymentIntentRowRaw({
          intent_id: intentId,
          device_id: client.device_id,
          user_id: client.user_id,
          app_id: client.app_id,
          project_id: client.project_id,
        });
        return String(row?.status || '') === 'aborted'
          && String(row?.receipt_delivery_state || '') === 'compensated';
      }, { timeoutMs: 3000, stepMs: 50 });
      assert.equal(compensatedReady, true);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

await runAsync('M3-W2-04/payment timeout worker auto-expire within <=5s without follow-up RPC', async () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  await withEnvAsync(baseEnv(runtimeBaseDir, {
    HUB_PAYMENT_INTENT_SWEEP_MS: '50',
    HUB_PAYMENT_INTENT_SWEEP_LIMIT: '100',
  }), async () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-payment-expire-worker');
      const now = Date.now();
      const created = invokeHubMemoryUnary(impl, 'CreatePaymentIntent', {
        request_id: 'req-pay4-create',
        client,
        amount_minor: 260,
        currency: 'CNY',
        merchant_id: 'merchant-water',
        source_terminal_id: 'robot-kiosk-4',
        allowed_mobile_terminal_id: 'mobile-4',
        ttl_ms: 5 * 1000,
        challenge_ttl_ms: 2 * 1000,
      });
      assert.equal(created.err, null);
      assert.equal(!!created.res?.accepted, true);
      const intentId = String(created.res?.intent?.intent_id || '');
      assert.ok(intentId.length > 0);

      // Force timeout in-place to assert background sweep behavior independent of follow-up RPCs.
      db.db
        .prepare(
          `UPDATE memory_payment_intents
           SET expires_at_ms = ?, updated_at_ms = ?
           WHERE intent_id = ?`
        )
        .run(now - 1, now - 1, intentId);

      const expiredReady = await waitFor(() => {
        const row = db._getPaymentIntentRowRaw({
          intent_id: intentId,
          device_id: client.device_id,
          user_id: client.user_id,
          app_id: client.app_id,
          project_id: client.project_id,
        });
        return String(row?.status || '') === 'expired';
      }, { timeoutMs: 1500, stepMs: 50 });
      assert.equal(expiredReady, true);
      const row = db._getPaymentIntentRowRaw({
        intent_id: intentId,
        device_id: client.device_id,
        user_id: client.user_id,
        app_id: client.app_id,
        project_id: client.project_id,
      });
      assert.ok(row);
      assert.equal(String(row?.status || ''), 'expired');
      assert.equal(String(row?.deny_code || ''), 'intent_expired');

      const audits = db.listAuditEvents({
        project_id: client.project_id,
      });
      const workerAudit = audits.find((item) => (
        String(item?.event_type || '') === 'payment.expired'
        && String(item?.ext_json || '').includes(`"intent_id":"${intentId}"`)
        && String(item?.ext_json || '').includes('"op":"payment_expire_sweep"')
      ));
      assert.ok(workerAudit, 'expected payment.expired audit emitted by payment sweep worker');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});
