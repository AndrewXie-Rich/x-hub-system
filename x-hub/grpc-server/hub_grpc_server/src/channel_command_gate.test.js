import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import { upsertSupervisorOperatorChannelBinding } from './channel_bindings_store.js';
import { evaluateChannelCommandGateWithAudit } from './channel_command_gate.js';
import { upsertChannelIdentityBinding } from './channel_identity_store.js';

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
  return path.join(os.tmpdir(), `channel_command_gate_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch {}
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch {}
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch {}
}

const KEK_V1 = `base64:${Buffer.alloc(32, 0x43).toString('base64')}`;

function baseEnv(runtimeBaseDir) {
  return {
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_CLIENT_TOKEN: '',
    HUB_MEMORY_AT_REST_ENABLED: 'true',
    HUB_MEMORY_KEK_ACTIVE_VERSION: 'kek_v1',
    HUB_MEMORY_KEK_RING_JSON: JSON.stringify({ kek_v1: KEK_V1 }),
    HUB_MEMORY_KEK_FILE: '',
    HUB_MEMORY_RETENTION_ENABLED: 'false',
  };
}

run('XT-W3-24-H/command gate allows approver to approve matching pending grant and audits the decision', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      upsertChannelIdentityBinding(db, {
        binding: {
          provider: 'feishu',
          external_user_id: 'ou_123',
          external_tenant_id: 'tenant_001',
          hub_user_id: 'user_ops_alice',
          roles: ['approver'],
          status: 'active',
        },
      });
      upsertSupervisorOperatorChannelBinding(db, {
        binding: {
          provider: 'feishu',
          account_id: 'default',
          conversation_id: 'oc_payments_room',
          channel_scope: 'group',
          scope_type: 'project',
          scope_id: 'payments-prod',
          allowed_actions: ['grant.approve', 'supervisor.status.get'],
          status: 'active',
        },
      });

      const decision = evaluateChannelCommandGateWithAudit({
        db,
        actor: {
          provider: 'lark',
          external_user_id: 'ou_123',
          external_tenant_id: 'tenant_001',
        },
        channel: {
          provider: 'feishu',
          account_id: 'default',
          conversation_id: 'oc_payments_room',
          channel_scope: 'group',
        },
        action: {
          action_name: 'grant.approve',
          pending_grant: {
            grant_request_id: 'grant_req_1',
            project_id: 'payments-prod',
            status: 'pending',
          },
        },
        client: {
          device_id: 'hub-operator-gate',
          app_id: 'channel-command-tests',
        },
        request_id: 'gate-allow-1',
      });
      assert.equal(!!decision.allowed, true);
      assert.equal(!!decision.audit_logged, true);

      const audit = db.listAuditEvents({ request_id: 'gate-allow-1' })
        .find((item) => String(item?.event_type || '') === 'channel.command.allowed');
      assert.ok(audit);
      assert.equal(String(audit?.app_id || ''), 'channel-command-tests');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
});

run('XT-W3-24-H/command gate denies viewer approval, approval-only status query, and mismatched grant scope', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      upsertChannelIdentityBinding(db, {
        binding: {
          provider: 'slack',
          external_user_id: 'U_viewer',
          hub_user_id: 'user_viewer',
          roles: ['viewer'],
          status: 'active',
        },
      });
      upsertChannelIdentityBinding(db, {
        binding: {
          provider: 'slack',
          external_user_id: 'U_approval_only',
          hub_user_id: 'user_approval',
          roles: ['approver'],
          approval_only: true,
          status: 'active',
        },
      });
      upsertSupervisorOperatorChannelBinding(db, {
        binding: {
          provider: 'slack',
          account_id: 'ops_bot',
          conversation_id: 'C123',
          channel_scope: 'group',
          scope_type: 'project',
          scope_id: 'payments-prod',
          allowed_actions: ['grant.approve', 'supervisor.status.get'],
          status: 'active',
        },
      });

      const viewerDenied = evaluateChannelCommandGateWithAudit({
        db,
        actor: {
          provider: 'slack',
          external_user_id: 'U_viewer',
        },
        channel: {
          provider: 'slack',
          account_id: 'ops_bot',
          conversation_id: 'C123',
          channel_scope: 'group',
        },
        action: {
          action_name: 'grant.approve',
          pending_grant: {
            grant_request_id: 'grant_req_viewer',
            project_id: 'payments-prod',
            status: 'pending',
          },
        },
        request_id: 'gate-deny-viewer',
      });
      assert.equal(!!viewerDenied.allowed, false);
      assert.equal(String(viewerDenied.deny_code || ''), 'role_not_allowed');

      const approvalOnlyDenied = evaluateChannelCommandGateWithAudit({
        db,
        actor: {
          provider: 'slack',
          external_user_id: 'U_approval_only',
        },
        channel: {
          provider: 'slack',
          account_id: 'ops_bot',
          conversation_id: 'C123',
          channel_scope: 'group',
        },
        action: {
          action_name: 'supervisor.status.get',
        },
        request_id: 'gate-deny-approval-only',
      });
      assert.equal(!!approvalOnlyDenied.allowed, false);
      assert.equal(String(approvalOnlyDenied.deny_code || ''), 'identity_approval_only');

      const scopeDenied = evaluateChannelCommandGateWithAudit({
        db,
        actor: {
          provider: 'slack',
          external_user_id: 'U_approval_only',
        },
        channel: {
          provider: 'slack',
          account_id: 'ops_bot',
          conversation_id: 'C123',
          channel_scope: 'group',
        },
        action: {
          action_name: 'grant.approve',
          pending_grant: {
            grant_request_id: 'grant_req_wrong_scope',
            project_id: 'search-prod',
            status: 'pending',
          },
        },
        request_id: 'gate-deny-scope',
      });
      assert.equal(!!scopeDenied.allowed, false);
      assert.equal(String(scopeDenied.deny_code || ''), 'pending_grant_scope_mismatch');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
});

run('XT-W3-24-H/command gate fails closed when audit append throws', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      upsertChannelIdentityBinding(db, {
        binding: {
          provider: 'telegram',
          external_user_id: 'u123',
          hub_user_id: 'user_ops',
          roles: ['approver'],
          status: 'active',
        },
      });
      upsertSupervisorOperatorChannelBinding(db, {
        binding: {
          provider: 'telegram',
          account_id: 'ops_bot',
          conversation_id: '-1001',
          channel_scope: 'group',
          scope_type: 'project',
          scope_id: 'payments-prod',
          allowed_actions: ['grant.approve'],
          status: 'active',
        },
      });

      const originalAppendAudit = db.appendAudit.bind(db);
      db.appendAudit = () => {
        throw new Error('simulated_audit_failure');
      };
      try {
        const out = evaluateChannelCommandGateWithAudit({
          db,
          actor: {
            provider: 'telegram',
            external_user_id: 'u123',
          },
          channel: {
            provider: 'telegram',
            account_id: 'ops_bot',
            conversation_id: '-1001',
            channel_scope: 'group',
          },
          action: {
            action_name: 'grant.approve',
            pending_grant: {
              grant_request_id: 'grant_req_2',
              project_id: 'payments-prod',
              status: 'pending',
            },
          },
          request_id: 'gate-audit-fail',
        });
        assert.equal(!!out.allowed, false);
        assert.equal(String(out.deny_code || ''), 'audit_write_failed');
      } finally {
        db.appendAudit = originalAppendAudit;
      }
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
});
