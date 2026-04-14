import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import { upsertSupervisorOperatorChannelBinding } from './channel_bindings_store.js';
import {
  evaluateChannelCommandGateWithAudit,
  getChannelActionPolicy,
  listChannelActionPolicies,
} from './channel_command_gate.js';
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

run('XT-W3-24-N/channel action catalog freezes risk tier and grant scope metadata', () => {
  const policies = listChannelActionPolicies();
  assert.equal(policies.length, 11);
  assert.equal(String(getChannelActionPolicy('grant.approve')?.risk_tier || ''), 'high');
  assert.equal(String(getChannelActionPolicy('grant.approve')?.required_grant_scope || ''), 'project_approval');
  assert.equal(String(getChannelActionPolicy('deploy.execute')?.risk_tier || ''), 'critical');
  assert.equal(String(getChannelActionPolicy('device.doctor.get')?.required_grant_scope || ''), 'device_observe');
});

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
          access_groups: ['group_allowlist', 'approval_only_identity'],
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
      assert.equal(String(decision.risk_tier || ''), 'high');
      assert.equal(String(decision.required_grant_scope || ''), 'project_approval');

      const audit = db.listAuditEvents({ request_id: 'gate-allow-1' })
        .find((item) => String(item?.event_type || '') === 'channel.command.allowed');
      assert.ok(audit);
      assert.equal(String(audit?.app_id || ''), 'channel-command-tests');
      assert.match(String(audit?.ext_json || ''), /"risk_tier":"high"/);
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
          access_groups: ['group_allowlist'],
          status: 'active',
        },
      });
      upsertChannelIdentityBinding(db, {
        binding: {
          provider: 'slack',
          external_user_id: 'U_approval_only',
          hub_user_id: 'user_approval',
          roles: ['approver'],
          access_groups: ['group_allowlist', 'approval_only_identity'],
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

run('XT-W3-24-I/command gate enforces project-first action scopes and requires explicit device diagnostics binding', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      upsertChannelIdentityBinding(db, {
        binding: {
          provider: 'slack',
          external_user_id: 'U_operator_scope',
          hub_user_id: 'user_operator_scope',
          roles: ['operator'],
          access_groups: ['group_allowlist'],
          status: 'active',
        },
      });
      upsertSupervisorOperatorChannelBinding(db, {
        binding: {
          provider: 'slack',
          account_id: 'ops_bot',
          conversation_id: 'CPROJ',
          channel_scope: 'group',
          scope_type: 'project',
          scope_id: 'payments-prod',
          allowed_actions: ['supervisor.status.get', 'deploy.plan', 'device.doctor.get'],
          status: 'active',
        },
      });
      upsertSupervisorOperatorChannelBinding(db, {
        binding: {
          provider: 'slack',
          account_id: 'ops_bot',
          conversation_id: 'CINC',
          channel_scope: 'group',
          scope_type: 'incident',
          scope_id: 'incident-payments-p1',
          allowed_actions: ['supervisor.status.get', 'deploy.plan'],
          status: 'active',
        },
      });
      upsertSupervisorOperatorChannelBinding(db, {
        binding: {
          provider: 'slack',
          account_id: 'ops_bot',
          conversation_id: 'CDEV',
          channel_scope: 'group',
          scope_type: 'device',
          scope_id: 'xt-mac-mini-bj-01',
          allowed_actions: ['device.doctor.get'],
          status: 'active',
        },
      });

      const projectStatus = evaluateChannelCommandGateWithAudit({
        db,
        actor: {
          provider: 'slack',
          external_user_id: 'U_operator_scope',
        },
        channel: {
          provider: 'slack',
          account_id: 'ops_bot',
          conversation_id: 'CPROJ',
          channel_scope: 'group',
        },
        action: {
          action_name: 'deploy.plan',
        },
        request_id: 'gate-scope-project-ok',
      });
      assert.equal(!!projectStatus.allowed, true);

      const projectDeviceDenied = evaluateChannelCommandGateWithAudit({
        db,
        actor: {
          provider: 'slack',
          external_user_id: 'U_operator_scope',
        },
        channel: {
          provider: 'slack',
          account_id: 'ops_bot',
          conversation_id: 'CPROJ',
          channel_scope: 'group',
        },
        action: {
          action_name: 'device.doctor.get',
        },
        request_id: 'gate-scope-project-device-deny',
      });
      assert.equal(!!projectDeviceDenied.allowed, false);
      assert.equal(String(projectDeviceDenied.deny_code || ''), 'scope_switch_required');

      const incidentStatus = evaluateChannelCommandGateWithAudit({
        db,
        actor: {
          provider: 'slack',
          external_user_id: 'U_operator_scope',
        },
        channel: {
          provider: 'slack',
          account_id: 'ops_bot',
          conversation_id: 'CINC',
          channel_scope: 'group',
        },
        action: {
          action_name: 'supervisor.status.get',
        },
        request_id: 'gate-scope-incident-status-ok',
      });
      assert.equal(!!incidentStatus.allowed, true);

      const incidentDeployDenied = evaluateChannelCommandGateWithAudit({
        db,
        actor: {
          provider: 'slack',
          external_user_id: 'U_operator_scope',
        },
        channel: {
          provider: 'slack',
          account_id: 'ops_bot',
          conversation_id: 'CINC',
          channel_scope: 'group',
        },
        action: {
          action_name: 'deploy.plan',
        },
        request_id: 'gate-scope-incident-deploy-deny',
      });
      assert.equal(!!incidentDeployDenied.allowed, false);
      assert.equal(String(incidentDeployDenied.deny_code || ''), 'scope_switch_required');

      const deviceDoctorAllowed = evaluateChannelCommandGateWithAudit({
        db,
        actor: {
          provider: 'slack',
          external_user_id: 'U_operator_scope',
        },
        channel: {
          provider: 'slack',
          account_id: 'ops_bot',
          conversation_id: 'CDEV',
          channel_scope: 'group',
        },
        action: {
          action_name: 'device.doctor.get',
        },
        request_id: 'gate-scope-device-ok',
      });
      assert.equal(!!deviceDoctorAllowed.allowed, true);
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
          access_groups: ['group_allowlist', 'approval_only_identity'],
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
