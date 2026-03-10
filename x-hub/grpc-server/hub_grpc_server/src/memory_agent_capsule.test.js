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
  return path.join(os.tmpdir(), `hub_memory_agent_capsule_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch { /* ignore */ }
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch { /* ignore */ }
}

const KEK_V1 = `base64:${Buffer.alloc(32, 0x52).toString('base64')}`;
const SIGNING_KEY = 'capsule-signing-key-v1';

function baseEnv(runtimeBaseDir, extra = {}) {
  return {
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_CLIENT_TOKEN: '',
    HUB_MEMORY_AT_REST_ENABLED: 'true',
    HUB_MEMORY_KEK_ACTIVE_VERSION: 'kek_v1',
    HUB_MEMORY_KEK_RING_JSON: JSON.stringify({ kek_v1: KEK_V1 }),
    HUB_MEMORY_KEK_FILE: '',
    HUB_MEMORY_RETENTION_ENABLED: 'false',
    HUB_AGENT_CAPSULE_SIGNING_KEY: SIGNING_KEY,
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

function makeClient(projectId = 'proj-capsule-main') {
  return {
    device_id: 'dev-capsule-1',
    user_id: 'user-capsule-1',
    app_id: 'ax-terminal',
    project_id: projectId,
    session_id: 'sess-capsule-1',
  };
}

function sha256Hex(text) {
  return crypto.createHash('sha256').update(String(text), 'utf8').digest('hex');
}

function signCapsule({ capsule_id, sha256, sbom_hash, key = SIGNING_KEY } = {}) {
  return crypto
    .createHmac('sha256', String(key || ''))
    .update(`${String(capsule_id || '')}:${String(sha256 || '')}:${String(sbom_hash || '')}`, 'utf8')
    .digest('hex');
}

function makeCapsulePayload(seed) {
  const manifest_payload = JSON.stringify({
    schema_version: 'agent_capsule_manifest.v1',
    seed,
    built_at_ms: 1731111000000,
    artifact_ref: `bundle://${seed}`,
  });
  const sbom_payload = JSON.stringify({
    schema_version: 'sbom.v1',
    seed,
    packages: ['pkg-a@1.0.0', 'pkg-b@2.1.0'],
  });
  return {
    manifest_payload,
    sbom_payload,
    sha256: sha256Hex(manifest_payload),
    sbom_hash: sha256Hex(sbom_payload),
  };
}

function registerCapsule(impl, client, fields = {}) {
  return invokeHubMemoryUnary(impl, 'RegisterAgentCapsule', {
    request_id: String(fields.request_id || ''),
    client,
    capsule_id: String(fields.capsule_id || ''),
    agent_name: String(fields.agent_name || 'codex'),
    agent_version: String(fields.agent_version || 'gpt-5'),
    platform: String(fields.platform || 'darwin-arm64'),
    sha256: String(fields.sha256 || ''),
    signature: String(fields.signature || ''),
    sbom_hash: String(fields.sbom_hash || ''),
    allowed_egress: Array.isArray(fields.allowed_egress)
      ? fields.allowed_egress
      : ['https://api.openai.com/v1/chat/completions'],
    risk_profile: String(fields.risk_profile || 'high'),
    manifest_payload: String(fields.manifest_payload || ''),
    sbom_payload: String(fields.sbom_payload || ''),
  });
}

function verifyCapsule(impl, client, { request_id, capsule_id } = {}) {
  return invokeHubMemoryUnary(impl, 'VerifyAgentCapsule', {
    request_id,
    client,
    capsule_id,
  });
}

function activateCapsule(impl, client, { request_id, capsule_id } = {}) {
  return invokeHubMemoryUnary(impl, 'ActivateAgentCapsule', {
    request_id,
    client,
    capsule_id,
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
    device_id: String(device_id || ''),
    user_id: String(user_id || ''),
    request_id: String(request_id || ''),
  }).find((item) => String(item?.event_type || '') === String(event_type || ''));
  assert.ok(row, `expected audit event ${event_type} for request_id=${request_id}`);
  if (error_code != null) {
    assert.equal(String(row?.error_code || ''), String(error_code || ''));
  }
}

run('M3-W1-01/register/verify/activate capsule state machine + generation pointer', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient();

      const capA = makeCapsulePayload('cap-a');
      const regA = registerCapsule(impl, client, {
        request_id: 'cap-register-a',
        capsule_id: 'cap_a',
        ...capA,
        signature: signCapsule({ capsule_id: 'cap_a', sha256: capA.sha256, sbom_hash: capA.sbom_hash }),
      });
      assert.equal(regA.err, null);
      assert.equal(!!regA.res?.registered, true);
      assert.equal(!!regA.res?.created, true);
      assert.equal(String(regA.res?.deny_code || ''), '');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'cap-register-a',
        event_type: 'agent.capsule.registered',
      });

      const verifyA = verifyCapsule(impl, client, {
        request_id: 'cap-verify-a',
        capsule_id: 'cap_a',
      });
      assert.equal(verifyA.err, null);
      assert.equal(!!verifyA.res?.verified, true);
      assert.equal(String(verifyA.res?.deny_code || ''), '');
      assert.ok(String(verifyA.res?.verification_report_ref || ''));
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'cap-verify-a',
        event_type: 'agent.capsule.verified',
      });

      const activateA = activateCapsule(impl, client, {
        request_id: 'cap-activate-a',
        capsule_id: 'cap_a',
      });
      assert.equal(activateA.err, null);
      assert.equal(!!activateA.res?.activated, true);
      assert.equal(!!activateA.res?.idempotent, false);
      assert.equal(String(activateA.res?.deny_code || ''), '');
      assert.equal(Number(activateA.res?.active_generation || 0), 1);
      assert.equal(Number(activateA.res?.previous_active_generation || 0), 0);
      assert.equal(String(activateA.res?.previous_active_capsule_id || ''), '');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'cap-activate-a',
        event_type: 'agent.capsule.activated',
      });

      const capB = makeCapsulePayload('cap-b');
      const regB = registerCapsule(impl, client, {
        request_id: 'cap-register-b',
        capsule_id: 'cap_b',
        ...capB,
        signature: signCapsule({ capsule_id: 'cap_b', sha256: capB.sha256, sbom_hash: capB.sbom_hash }),
      });
      assert.equal(regB.err, null);
      assert.equal(!!regB.res?.registered, true);

      const verifyB = verifyCapsule(impl, client, {
        request_id: 'cap-verify-b',
        capsule_id: 'cap_b',
      });
      assert.equal(verifyB.err, null);
      assert.equal(!!verifyB.res?.verified, true);

      const activateB = activateCapsule(impl, client, {
        request_id: 'cap-activate-b',
        capsule_id: 'cap_b',
      });
      assert.equal(activateB.err, null);
      assert.equal(!!activateB.res?.activated, true);
      assert.equal(String(activateB.res?.deny_code || ''), '');
      assert.equal(Number(activateB.res?.active_generation || 0), 2);
      assert.equal(Number(activateB.res?.previous_active_generation || 0), 1);
      assert.equal(String(activateB.res?.previous_active_capsule_id || ''), 'cap_a');

      const runtimeState = db.getAgentCapsuleRuntimeState({});
      assert.equal(String(runtimeState?.active_capsule_id || ''), 'cap_b');
      assert.equal(Number(runtimeState?.active_generation || 0), 2);
      assert.equal(String(runtimeState?.previous_active_capsule_id || ''), 'cap_a');
      assert.equal(Number(runtimeState?.previous_active_generation || 0), 1);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-01/verify deny matrix: hash_mismatch + signature_invalid + sbom_invalid + egress_policy_violation', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-capsule-deny-matrix');

      const base = makeCapsulePayload('cap-deny');
      const cases = [
        {
          suffix: 'hash',
          capsule_id: 'cap_hash_mismatch',
          request_id: 'cap-reg-hash',
          deny_code: 'hash_mismatch',
          sha256: '0'.repeat(64),
          signature: signCapsule({ capsule_id: 'cap_hash_mismatch', sha256: '0'.repeat(64), sbom_hash: base.sbom_hash }),
          sbom_hash: base.sbom_hash,
          allowed_egress: ['https://api.openai.com/v1'],
        },
        {
          suffix: 'sig',
          capsule_id: 'cap_signature_invalid',
          request_id: 'cap-reg-sig',
          deny_code: 'signature_invalid',
          sha256: base.sha256,
          signature: 'f'.repeat(64),
          sbom_hash: base.sbom_hash,
          allowed_egress: ['https://api.openai.com/v1'],
        },
        {
          suffix: 'sbom',
          capsule_id: 'cap_sbom_invalid',
          request_id: 'cap-reg-sbom',
          deny_code: 'sbom_invalid',
          sha256: base.sha256,
          signature: signCapsule({ capsule_id: 'cap_sbom_invalid', sha256: base.sha256, sbom_hash: '1'.repeat(64) }),
          sbom_hash: '1'.repeat(64),
          allowed_egress: ['https://api.openai.com/v1'],
        },
        {
          suffix: 'egress',
          capsule_id: 'cap_egress_invalid',
          request_id: 'cap-reg-egress',
          deny_code: 'egress_policy_violation',
          sha256: base.sha256,
          signature: signCapsule({ capsule_id: 'cap_egress_invalid', sha256: base.sha256, sbom_hash: base.sbom_hash }),
          sbom_hash: base.sbom_hash,
          allowed_egress: ['https://api.openai.com/v1', 'http://0.0.0.0/0'],
        },
      ];

      for (const item of cases) {
        const reg = registerCapsule(impl, client, {
          request_id: item.request_id,
          capsule_id: item.capsule_id,
          sha256: item.sha256,
          signature: item.signature,
          sbom_hash: item.sbom_hash,
          allowed_egress: item.allowed_egress,
          manifest_payload: base.manifest_payload,
          sbom_payload: base.sbom_payload,
        });
        assert.equal(reg.err, null);
        assert.equal(!!reg.res?.registered, true);

        const verify = verifyCapsule(impl, client, {
          request_id: `cap-verify-${item.suffix}`,
          capsule_id: item.capsule_id,
        });
        assert.equal(verify.err, null);
        assert.equal(!!verify.res?.verified, false);
        assert.equal(String(verify.res?.deny_code || ''), item.deny_code);
        assertAuditEvent(db, {
          device_id: client.device_id,
          user_id: client.user_id,
          request_id: `cap-verify-${item.suffix}`,
          event_type: 'agent.capsule.denied',
          error_code: item.deny_code,
        });
      }
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-01/activation failure keeps rollback pointer on previous active generation', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-capsule-rollback');

      const capA = makeCapsulePayload('rollback-a');
      const capB = makeCapsulePayload('rollback-b');

      const regA = registerCapsule(impl, client, {
        request_id: 'cap-reg-roll-a',
        capsule_id: 'cap_roll_a',
        ...capA,
        signature: signCapsule({ capsule_id: 'cap_roll_a', sha256: capA.sha256, sbom_hash: capA.sbom_hash }),
      });
      assert.equal(regA.err, null);
      const verifyA = verifyCapsule(impl, client, {
        request_id: 'cap-verify-roll-a',
        capsule_id: 'cap_roll_a',
      });
      assert.equal(verifyA.err, null);
      const activateA = activateCapsule(impl, client, {
        request_id: 'cap-activate-roll-a',
        capsule_id: 'cap_roll_a',
      });
      assert.equal(activateA.err, null);
      assert.equal(!!activateA.res?.activated, true);
      assert.equal(Number(activateA.res?.active_generation || 0), 1);

      const regB = registerCapsule(impl, client, {
        request_id: 'cap-reg-roll-b',
        capsule_id: 'cap_roll_b',
        ...capB,
        signature: signCapsule({ capsule_id: 'cap_roll_b', sha256: capB.sha256, sbom_hash: capB.sbom_hash }),
      });
      assert.equal(regB.err, null);
      const verifyB = verifyCapsule(impl, client, {
        request_id: 'cap-verify-roll-b',
        capsule_id: 'cap_roll_b',
      });
      assert.equal(verifyB.err, null);
      assert.equal(!!verifyB.res?.verified, true);

      const originalPrepare = db.db.prepare.bind(db.db);
      db.db.prepare = (sql) => {
        const text = String(sql || '');
        if (text.includes('UPDATE agent_capsule_runtime_state') && text.includes('active_capsule_id')) {
          throw new Error('simulated_activation_interrupt');
        }
        return originalPrepare(sql);
      };
      try {
        const failed = activateCapsule(impl, client, {
          request_id: 'cap-activate-roll-b-fail',
          capsule_id: 'cap_roll_b',
        });
        assert.equal(failed.err, null);
        assert.equal(!!failed.res?.activated, false);
        assert.equal(String(failed.res?.deny_code || ''), 'runtime_error');
        assertAuditEvent(db, {
          device_id: client.device_id,
          user_id: client.user_id,
          request_id: 'cap-activate-roll-b-fail',
          event_type: 'agent.capsule.denied',
          error_code: 'runtime_error',
        });
      } finally {
        db.db.prepare = originalPrepare;
      }

      const runtimeState = db.getAgentCapsuleRuntimeState({});
      assert.equal(String(runtimeState?.active_capsule_id || ''), 'cap_roll_a');
      assert.equal(Number(runtimeState?.active_generation || 0), 1);
      assert.equal(Number(runtimeState?.previous_active_generation || 0), 0);
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-01/verify runtime_error stays fail-closed', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-capsule-fail-closed');

      const cap = makeCapsulePayload('cap-fc');
      const reg = registerCapsule(impl, client, {
        request_id: 'cap-reg-fc',
        capsule_id: 'cap_fc',
        ...cap,
        signature: signCapsule({ capsule_id: 'cap_fc', sha256: cap.sha256, sbom_hash: cap.sbom_hash }),
      });
      assert.equal(reg.err, null);
      assert.equal(!!reg.res?.registered, true);

      const originalVerify = db.verifyAgentCapsule.bind(db);
      db.verifyAgentCapsule = () => {
        throw new Error('simulated_verify_runtime_error');
      };
      try {
        const verify = verifyCapsule(impl, client, {
          request_id: 'cap-verify-fc',
          capsule_id: 'cap_fc',
        });
        assert.equal(verify.err, null);
        assert.equal(!!verify.res?.verified, false);
        assert.equal(String(verify.res?.deny_code || ''), 'runtime_error');
        assertAuditEvent(db, {
          device_id: client.device_id,
          user_id: client.user_id,
          request_id: 'cap-verify-fc',
          event_type: 'agent.capsule.denied',
          error_code: 'runtime_error',
        });
      } finally {
        db.verifyAgentCapsule = originalVerify;
      }
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-01/activate without verify is denied as state_corrupt', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-capsule-state-corrupt');

      const cap = makeCapsulePayload('cap-state-corrupt');
      const reg = registerCapsule(impl, client, {
        request_id: 'cap-reg-state-corrupt',
        capsule_id: 'cap_state_corrupt',
        ...cap,
        signature: signCapsule({ capsule_id: 'cap_state_corrupt', sha256: cap.sha256, sbom_hash: cap.sbom_hash }),
      });
      assert.equal(reg.err, null);
      assert.equal(!!reg.res?.registered, true);

      const activate = activateCapsule(impl, client, {
        request_id: 'cap-activate-state-corrupt',
        capsule_id: 'cap_state_corrupt',
      });
      assert.equal(activate.err, null);
      assert.equal(!!activate.res?.activated, false);
      assert.equal(String(activate.res?.deny_code || ''), 'state_corrupt');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'cap-activate-state-corrupt',
        event_type: 'agent.capsule.denied',
        error_code: 'state_corrupt',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-01/verify fails closed when capsule signing key is missing', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-capsule-signing-key-missing');

      const cap = makeCapsulePayload('cap-signing-key');
      const reg = registerCapsule(impl, client, {
        request_id: 'cap-reg-signing-key',
        capsule_id: 'cap_signing_key',
        ...cap,
        signature: signCapsule({ capsule_id: 'cap_signing_key', sha256: cap.sha256, sbom_hash: cap.sbom_hash }),
      });
      assert.equal(reg.err, null);
      assert.equal(!!reg.res?.registered, true);

      process.env.HUB_AGENT_CAPSULE_SIGNING_KEY = '';
      const verify = verifyCapsule(impl, client, {
        request_id: 'cap-verify-signing-key-missing',
        capsule_id: 'cap_signing_key',
      });
      assert.equal(verify.err, null);
      assert.equal(!!verify.res?.verified, false);
      assert.equal(String(verify.res?.deny_code || ''), 'signature_invalid');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'cap-verify-signing-key-missing',
        event_type: 'agent.capsule.denied',
        error_code: 'signature_invalid',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-01/register enforces scope isolation + capsule_conflict fail-closed', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const clientA = makeClient('proj-capsule-scope-a');
      const clientB = {
        ...makeClient('proj-capsule-scope-b'),
        device_id: 'dev-capsule-2',
        user_id: 'user-capsule-2',
      };

      const cap = makeCapsulePayload('cap-scope');
      const regA = registerCapsule(impl, clientA, {
        request_id: 'cap-reg-scope-a',
        capsule_id: 'cap_scope_isolated',
        ...cap,
        signature: signCapsule({ capsule_id: 'cap_scope_isolated', sha256: cap.sha256, sbom_hash: cap.sbom_hash }),
      });
      assert.equal(regA.err, null);
      assert.equal(!!regA.res?.registered, true);
      assert.equal(!!regA.res?.created, true);

      const crossScope = registerCapsule(impl, clientB, {
        request_id: 'cap-reg-scope-cross',
        capsule_id: 'cap_scope_isolated',
        ...cap,
        signature: signCapsule({ capsule_id: 'cap_scope_isolated', sha256: cap.sha256, sbom_hash: cap.sbom_hash }),
      });
      assert.equal(crossScope.err, null);
      assert.equal(!!crossScope.res?.registered, false);
      assert.equal(String(crossScope.res?.deny_code || ''), 'permission_denied');
      assertAuditEvent(db, {
        device_id: clientB.device_id,
        user_id: clientB.user_id,
        request_id: 'cap-reg-scope-cross',
        event_type: 'agent.capsule.denied',
        error_code: 'permission_denied',
      });

      const conflict = registerCapsule(impl, clientA, {
        request_id: 'cap-reg-scope-conflict',
        capsule_id: 'cap_scope_isolated',
        ...cap,
        manifest_payload: JSON.stringify({ schema_version: 'agent_capsule_manifest.v1', seed: 'tampered' }),
        signature: signCapsule({ capsule_id: 'cap_scope_isolated', sha256: cap.sha256, sbom_hash: cap.sbom_hash }),
      });
      assert.equal(conflict.err, null);
      assert.equal(!!conflict.res?.registered, false);
      assert.equal(String(conflict.res?.deny_code || ''), 'capsule_conflict');
      assertAuditEvent(db, {
        device_id: clientA.device_id,
        user_id: clientA.user_id,
        request_id: 'cap-reg-scope-conflict',
        event_type: 'agent.capsule.denied',
        error_code: 'capsule_conflict',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-01/register idempotent replay keeps machine-readable stable response', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-capsule-idempotent');
      const cap = makeCapsulePayload('cap-idempotent');

      const requestId = 'cap-reg-idempotent';
      const first = registerCapsule(impl, client, {
        request_id: requestId,
        capsule_id: 'cap_idempotent',
        ...cap,
        signature: signCapsule({ capsule_id: 'cap_idempotent', sha256: cap.sha256, sbom_hash: cap.sbom_hash }),
      });
      assert.equal(first.err, null);
      assert.equal(!!first.res?.registered, true);
      assert.equal(!!first.res?.created, true);
      assert.equal(String(first.res?.deny_code || ''), '');

      const replay = registerCapsule(impl, client, {
        request_id: requestId,
        capsule_id: 'cap_idempotent',
        ...cap,
        signature: signCapsule({ capsule_id: 'cap_idempotent', sha256: cap.sha256, sbom_hash: cap.sbom_hash }),
      });
      assert.equal(replay.err, null);
      assert.equal(!!replay.res?.registered, true);
      assert.equal(!!replay.res?.created, false);
      assert.equal(String(replay.res?.deny_code || ''), '');
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-01/register invalid_request stays fail-closed with audit deny_code', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-capsule-invalid-register');

      const out = registerCapsule(impl, client, {
        request_id: 'cap-reg-invalid-request',
        capsule_id: 'cap_invalid_request',
        sha256: '',
        signature: '',
        sbom_hash: '',
        manifest_payload: '',
        sbom_payload: '',
      });
      assert.equal(out.err, null);
      assert.equal(!!out.res?.registered, false);
      assert.equal(String(out.res?.deny_code || ''), 'invalid_request');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'cap-reg-invalid-request',
        event_type: 'agent.capsule.denied',
        error_code: 'invalid_request',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-01/verify capsule_not_found stays fail-closed with audit deny_code', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-capsule-not-found-verify');

      const out = verifyCapsule(impl, client, {
        request_id: 'cap-verify-not-found',
        capsule_id: 'cap_missing',
      });
      assert.equal(out.err, null);
      assert.equal(!!out.res?.verified, false);
      assert.equal(String(out.res?.deny_code || ''), 'capsule_not_found');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'cap-verify-not-found',
        event_type: 'agent.capsule.denied',
        error_code: 'capsule_not_found',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});

run('M3-W1-01/activate capsule_not_found stays fail-closed with audit deny_code', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.db');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    try {
      const impl = makeServices({ db, bus: new HubEventBus() });
      const client = makeClient('proj-capsule-not-found-activate');

      const out = activateCapsule(impl, client, {
        request_id: 'cap-activate-not-found',
        capsule_id: 'cap_missing',
      });
      assert.equal(out.err, null);
      assert.equal(!!out.res?.activated, false);
      assert.equal(String(out.res?.deny_code || ''), 'capsule_not_found');
      assertAuditEvent(db, {
        device_id: client.device_id,
        user_id: client.user_id,
        request_id: 'cap-activate-not-found',
        event_type: 'agent.capsule.denied',
        error_code: 'capsule_not_found',
      });
    } finally {
      db.close();
    }
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch { /* ignore */ }
});
