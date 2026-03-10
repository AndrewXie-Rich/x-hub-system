import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import {
  authorizeConnectorIngress,
  buildNonMessageIngressGateEvidence,
  buildNonMessageIngressGateEvidenceFromAuditRows,
  buildNonMessageIngressGateSnapshot,
  buildNonMessageIngressGateSnapshotFromAuditRows,
  buildNonMessageIngressScanStats,
  buildNonMessageIngressScanStatsFromAuditRows,
  evaluateConnectorIngressWithAudit,
} from './connector_ingress_authorizer.js';

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

function makeTmp(label, suffix = '') {
  const token = `${label}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  return path.join(os.tmpdir(), `connector_ingress_auth_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
}

const KEK_V1 = `base64:${Buffer.alloc(32, 0x51).toString('base64')}`;

function baseEnv(runtimeBaseDir, extra = {}) {
  return {
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_CLIENT_TOKEN: '',
    HUB_MEMORY_AT_REST_ENABLED: 'true',
    HUB_MEMORY_KEK_ACTIVE_VERSION: 'kek_v1',
    HUB_MEMORY_KEK_RING_JSON: JSON.stringify({ kek_v1: KEK_V1 }),
    HUB_MEMORY_KEK_FILE: '',
    HUB_MEMORY_RETENTION_ENABLED: 'false',
    ...extra,
  };
}

run('non-message ingress unauthorized reaction/pin/member/webhook is denied with unified audit', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const policy = {
        dm_allow_from: [],
        dm_pairing_allow_from: [],
        group_allow_from: [],
        webhook_allow_from: [],
      };
      const client = {
        device_id: 'dev-ingress-1',
        user_id: 'user-ingress-1',
        app_id: 'connector-ingress-test',
        project_id: 'proj-ingress',
      };

      const events = [
        {
          request_id: 'evt-reaction-deny',
          event: { ingress_type: 'reaction', channel_scope: 'group', sender_id: 'u-unauthorized', channel_id: 'g-1' },
          expected_deny_code: 'sender_not_allowlisted',
        },
        {
          request_id: 'evt-pin-deny',
          event: { ingress_type: 'pin', channel_scope: 'group', sender_id: 'u-unauthorized', channel_id: 'g-1' },
          expected_deny_code: 'sender_not_allowlisted',
        },
        {
          request_id: 'evt-member-deny',
          event: { ingress_type: 'member', channel_scope: 'group', sender_id: 'u-unauthorized', channel_id: 'g-1' },
          expected_deny_code: 'sender_not_allowlisted',
        },
        {
          request_id: 'evt-webhook-deny',
          event: { ingress_type: 'webhook', source_id: 'wh-not-allowlisted', signature_valid: true, replay_detected: false },
          expected_deny_code: 'webhook_not_allowlisted',
        },
      ];

      for (const sample of events) {
        const out = evaluateConnectorIngressWithAudit({
          db,
          event: sample.event,
          policy,
          client,
          request_id: sample.request_id,
        });
        assert.equal(!!out.allowed, false);
        assert.equal(String(out.deny_code || ''), sample.expected_deny_code);
        assert.equal(!!out.audit_logged, true);

        const row = db.listAuditEvents({
          device_id: client.device_id,
          user_id: client.user_id,
          request_id: sample.request_id,
        }).find((item) => String(item?.event_type || '') === 'connector.ingress.denied');
        assert.ok(row, `expected connector.ingress.denied audit for request_id=${sample.request_id}`);
        assert.equal(String(row?.error_code || ''), sample.expected_deny_code);
      }
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('dm pairing allow never auto-expands into group allowlist', () => {
  const dmPairedOnlyPolicy = {
    dm_allow_from: [],
    dm_pairing_allow_from: ['u-dm-paired'],
    group_allow_from: [],
    webhook_allow_from: [],
  };

  const dmAllow = authorizeConnectorIngress({
    event: { ingress_type: 'message', channel_scope: 'dm', sender_id: 'u-dm-paired', channel_id: 'dm-1' },
    policy: dmPairedOnlyPolicy,
  });
  assert.equal(!!dmAllow.allowed, true);

  const groupDenied = authorizeConnectorIngress({
    event: { ingress_type: 'message', channel_scope: 'group', sender_id: 'u-dm-paired', channel_id: 'group-1' },
    policy: dmPairedOnlyPolicy,
  });
  assert.equal(!!groupDenied.allowed, false);
  assert.equal(String(groupDenied.deny_code || ''), 'dm_pairing_scope_violation');

  const upgradedPolicy = {
    ...dmPairedOnlyPolicy,
    group_allow_from: ['u-dm-paired'],
  };
  const groupAllow = authorizeConnectorIngress({
    event: { ingress_type: 'reaction', channel_scope: 'group', sender_id: 'u-dm-paired', channel_id: 'group-1' },
    policy: upgradedPolicy,
  });
  assert.equal(!!groupAllow.allowed, true);
});

run('blocked_event_miss_rate and non_message coverage stats are computed correctly', () => {
  const stats = buildNonMessageIngressScanStats([
    {
      ingress_type: 'reaction',
      allowed: false,
      deny_code: 'sender_not_allowlisted',
      policy_checked: true,
      audit_logged: true,
    },
    {
      ingress_type: 'pin',
      allowed: false,
      deny_code: 'sender_not_allowlisted',
      policy_checked: true,
      audit_logged: false,
    },
    {
      ingress_type: 'member',
      allowed: false,
      deny_code: 'sender_not_allowlisted',
      policy_checked: false,
      audit_logged: false,
    },
    {
      ingress_type: 'message',
      allowed: true,
      policy_checked: true,
      audit_logged: true,
    },
  ]);

  assert.equal(Number(stats.ingress_total || 0), 4);
  assert.equal(Number(stats.non_message_ingress_total || 0), 3);
  assert.equal(Number(stats.non_message_ingress_policy_checked || 0), 2);
  assert.equal(Number(stats.blocked_event_total || 0), 3);
  assert.equal(Number(stats.blocked_event_audited || 0), 1);
  assert.equal(Number(stats.blocked_event_miss_total || 0), 2);
  assert.equal(Number(stats.non_message_ingress_policy_coverage || 0), 2 / 3);
  assert.equal(Number(stats.blocked_event_miss_rate || 0), 2 / 3);
});

run('machine-readable ingress gate evidence reports pass/fail with stable incident codes', () => {
  const passEvidence = buildNonMessageIngressGateEvidence({
    stats: {
      non_message_ingress_policy_coverage: 1,
      blocked_event_miss_rate: 0,
      non_message_ingress_total: 4,
      blocked_event_total: 2,
    },
  });
  assert.equal(String(passEvidence.schema_version || ''), 'xhub.connector.non_message_ingress_gate.v1');
  assert.equal(!!passEvidence.pass, true);
  assert.deepEqual(passEvidence.incident_codes || [], []);
  assert.equal(Number(passEvidence.metrics?.non_message_ingress_policy_coverage || 0), 1);
  assert.equal(Number(passEvidence.metrics?.blocked_event_miss_rate || 0), 0);

  const failEvidence = buildNonMessageIngressGateEvidence({
    stats: {
      non_message_ingress_policy_coverage: 0.5,
      blocked_event_miss_rate: 0.2,
      non_message_ingress_total: 4,
      blocked_event_total: 5,
    },
  });
  assert.equal(!!failEvidence.pass, false);
  assert.deepEqual(
    failEvidence.incident_codes || [],
    ['non_message_ingress_policy_coverage_low', 'blocked_event_miss_rate_high']
  );
});

run('gate snapshot surfaces canonical release fields (pass/incident_codes/metrics)', () => {
  const snapshot = buildNonMessageIngressGateSnapshot({
    stats: {
      ingress_total: 5,
      non_message_ingress_total: 4,
      non_message_ingress_policy_checked: 4,
      non_message_ingress_policy_coverage: 1,
      blocked_event_total: 4,
      blocked_event_audited: 3,
      blocked_event_miss_total: 1,
      blocked_event_miss_rate: 0.25,
    },
  });

  assert.equal(String(snapshot.schema_version || ''), 'xhub.connector.non_message_ingress_gate.v1');
  assert.ok(Number(snapshot.measured_at_ms || 0) > 0);
  assert.equal(!!snapshot.pass, false);
  assert.deepEqual(snapshot.incident_codes || [], ['blocked_event_miss_rate_high']);
  assert.equal(Number(snapshot.metrics?.non_message_ingress_total || 0), 4);
  assert.equal(Number(snapshot.metrics?.blocked_event_miss_rate || 0), 0.25);
});

run('audit-backed ingress gate evidence is machine-readable and fail-closed on low policy coverage', () => {
  const evidence = buildNonMessageIngressGateEvidenceFromAuditRows([
    {
      event_type: 'connector.ingress.denied',
      ok: false,
      error_code: 'sender_not_allowlisted',
      ext_json: JSON.stringify({
        ingress_type: 'reaction',
        policy_checked: false,
      }),
    },
    {
      event_type: 'connector.ingress.allowed',
      ok: true,
      error_code: null,
      ext_json: JSON.stringify({
        ingress_type: 'message',
        policy_checked: true,
      }),
    },
  ]);
  assert.equal(String(evidence.schema_version || ''), 'xhub.connector.non_message_ingress_gate.v1');
  assert.equal(!!evidence.pass, false);
  assert.deepEqual(evidence.incident_codes || [], ['non_message_ingress_policy_coverage_low']);
  assert.equal(Number(evidence.metrics?.non_message_ingress_policy_coverage || 0), 0);
  assert.equal(Number(evidence.metrics?.blocked_event_miss_rate || 0), 0);
});

run('audit-backed gate snapshot preserves machine-readable checks for release gate ingestion', () => {
  const snapshot = buildNonMessageIngressGateSnapshotFromAuditRows([
    {
      event_type: 'connector.ingress.denied',
      ok: false,
      error_code: 'sender_not_allowlisted',
      ext_json: JSON.stringify({
        ingress_type: 'member',
        policy_checked: false,
      }),
    },
  ]);

  assert.equal(String(snapshot.schema_version || ''), 'xhub.connector.non_message_ingress_gate.v1');
  assert.equal(!!snapshot.pass, false);
  assert.deepEqual(snapshot.incident_codes || [], ['non_message_ingress_policy_coverage_low']);
  assert.equal(Number(snapshot.metrics?.non_message_ingress_policy_coverage || 0), 0);
  assert.equal(Number(snapshot.metrics?.blocked_event_miss_rate || 0), 0);
  assert.ok(Array.isArray(snapshot.checks), 'expected machine-readable checks');
  assert.equal(snapshot.checks.length >= 2, true);
});

run('audit-backed stats include non-message coverage fields and zero miss-rate when all blocked events are audited', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const policy = {
        dm_allow_from: ['u-dm-ok'],
        dm_pairing_allow_from: ['u-dm-paired'],
        group_allow_from: ['u-group-ok'],
        webhook_allow_from: ['wh-ok'],
      };
      const client = {
        device_id: 'dev-ingress-2',
        user_id: 'user-ingress-2',
        app_id: 'connector-ingress-test',
        project_id: 'proj-ingress',
      };

      evaluateConnectorIngressWithAudit({
        db,
        event: { ingress_type: 'message', channel_scope: 'dm', sender_id: 'u-dm-ok' },
        policy,
        client,
        request_id: 'evt-msg-allow',
      });
      evaluateConnectorIngressWithAudit({
        db,
        event: { ingress_type: 'reaction', channel_scope: 'group', sender_id: 'u-group-ok' },
        policy,
        client,
        request_id: 'evt-reaction-allow',
      });
      evaluateConnectorIngressWithAudit({
        db,
        event: { ingress_type: 'pin', channel_scope: 'group', sender_id: 'u-dm-paired' },
        policy,
        client,
        request_id: 'evt-pin-deny',
      });
      evaluateConnectorIngressWithAudit({
        db,
        event: { ingress_type: 'webhook', source_id: 'wh-bad', signature_valid: true },
        policy,
        client,
        request_id: 'evt-webhook-deny',
      });

      const rows = db.listAuditEvents({
        device_id: client.device_id,
        user_id: client.user_id,
      });
      const stats = buildNonMessageIngressScanStatsFromAuditRows(rows);
      assert.equal(Number(stats.ingress_total || 0), 4);
      assert.equal(Number(stats.non_message_ingress_total || 0), 3);
      assert.equal(Number(stats.non_message_ingress_policy_coverage || 0), 1);
      assert.equal(Number(stats.blocked_event_total || 0), 2);
      assert.equal(Number(stats.blocked_event_miss_rate || 0), 0);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});
