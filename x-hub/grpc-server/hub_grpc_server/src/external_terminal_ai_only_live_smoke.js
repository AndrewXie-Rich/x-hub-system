import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import https from 'node:https';
import os from 'node:os';
import path from 'node:path';
import { runExternalTerminalAiOnlyRemoteSmoke } from './external_terminal_ai_only_remote_smoke.js';

const SCHEMA_VERSION = 'xhub.external_terminal_ai_only_live_smoke.v1';

function safeString(value) {
  return String(value ?? '').trim();
}

function boolFlag(name) {
  return process.argv.includes(name);
}

function argValue(name, fallback = '') {
  const index = process.argv.indexOf(name);
  if (index >= 0 && index + 1 < process.argv.length) return safeString(process.argv[index + 1]);
  return safeString(fallback);
}

function homePath(...parts) {
  return path.join(os.homedir(), ...parts);
}

function firstExisting(paths) {
  return paths.find((candidate) => candidate && fs.existsSync(candidate)) || '';
}

function loadJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function decryptRemoteSecret(ciphertext, keyPath) {
  const raw = safeString(ciphertext);
  if (!raw) return '';
  const payload = raw.startsWith('v1:') ? raw.slice(3) : raw;
  const combined = Buffer.from(payload, 'base64');
  if (combined.length <= 28) throw new Error('invalid_ciphertext');
  const key = fs.readFileSync(keyPath);
  if (key.length !== 32) throw new Error('invalid_remote_secret_key');

  const nonce = combined.subarray(0, 12);
  const tag = combined.subarray(combined.length - 16);
  const encrypted = combined.subarray(12, combined.length - 16);
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, nonce);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(encrypted), decipher.final()]).toString('utf8').trim();
}

function loadAdminToken() {
  const explicit = safeString(process.env.HUB_ADMIN_TOKEN || argValue('--admin-token'));
  if (explicit) return explicit;

  const tokenFile = firstExisting([
    argValue('--tokens-file'),
    homePath('Library', 'Containers', 'com.rel.flowhub', 'Data', 'RELFlowHub', 'hub_grpc_tokens.json'),
    homePath('Library', 'Group Containers', 'group.rel.flowhub', 'hub_grpc_tokens.json'),
    homePath('RELFlowHub', 'hub_grpc_tokens.json'),
  ]);
  if (!tokenFile) throw new Error('hub_grpc_tokens_json_not_found');
  const tokens = loadJson(tokenFile);

  const plain = safeString(tokens.adminToken);
  if (plain) return plain;

  const encrypted = safeString(tokens.adminTokenCiphertext);
  if (!encrypted) throw new Error('admin_token_missing');

  const keyFile = firstExisting([
    argValue('--secret-key-file'),
    homePath('Library', 'Group Containers', 'group.rel.flowhub', '.remote_model_secrets_v1.key'),
    path.join(path.dirname(tokenFile), '.remote_model_secrets_v1.key'),
    homePath('RELFlowHub', '.remote_model_secrets_v1.key'),
  ]);
  if (!keyFile) throw new Error('remote_secret_key_not_found');
  return decryptRemoteSecret(encrypted, keyFile);
}

function requestJson({
  method = 'GET',
  url,
  token = '',
  body = null,
  timeoutMs = 4_000,
} = {}) {
  const target = new URL(String(url || ''));
  const transport = target.protocol === 'https:' ? https : http;
  const payload = body == null ? '' : JSON.stringify(body);
  const headers = {
    accept: 'application/json',
  };
  if (token) headers.authorization = `Bearer ${token}`;
  if (payload) {
    headers['content-type'] = 'application/json; charset=utf-8';
    headers['content-length'] = String(Buffer.byteLength(payload));
  }

  return new Promise((resolve, reject) => {
    const req = transport.request({
      method,
      hostname: target.hostname,
      port: target.port || (target.protocol === 'https:' ? '443' : '80'),
      path: `${target.pathname}${target.search}`,
      headers,
      timeout: timeoutMs,
    }, (res) => {
      const chunks = [];
      res.on('data', (chunk) => chunks.push(Buffer.from(chunk)));
      res.on('end', () => {
        const text = Buffer.concat(chunks).toString('utf8');
        let json = null;
        try {
          json = text ? JSON.parse(text) : null;
        } catch {
          json = null;
        }
        resolve({
          status: Number(res.statusCode || 0),
          headers: res.headers || {},
          json,
          text,
        });
      });
    });
    req.on('error', reject);
    req.on('timeout', () => req.destroy(new Error('request_timeout')));
    if (payload) req.write(payload);
    req.end();
  });
}

function hasCapability(list, capability) {
  return Array.isArray(list) && list.map(String).includes(capability);
}

function responseErrorSummary(response) {
  const err = response?.json?.error && typeof response.json.error === 'object'
    ? response.json.error
    : {};
  return {
    status: Number(response?.status || 0),
    code: safeString(err.code || response?.json?.code),
    message: safeString(err.message || response?.json?.message).slice(0, 240),
  };
}

function pickModelId(modelsJson) {
  const rows = Array.isArray(modelsJson?.data) ? modelsJson.data : [];
  const ids = rows
    .map((row) => ({
      id: safeString(row?.id),
      ownedBy: safeString(row?.owned_by || row?.ownedBy).toLowerCase(),
      requiresGrant: row?.requires_grant === true,
    }))
    .filter((row) => row.id && !row.requiresGrant);
  const local = ids.find((row) => {
    const text = `${row.id} ${row.ownedBy}`.toLowerCase();
    return text.includes('local')
      || text.includes('lmstudio')
      || text.includes('mlx')
      || text.includes('llama')
      || text.includes('qwen');
  });
  return safeString(local?.id || ids[0]?.id);
}

async function main() {
  const baseUrl = argValue('--base-url', process.env.HUB_PAIRING_BASE_URL || 'http://127.0.0.1:50071').replace(/\/+$/, '');
  const probeBaseUrl = argValue('--probe-base-url', process.env.HUB_EXTERNAL_TERMINAL_PROBE_BASE_URL || baseUrl).replace(/\/+$/, '');
  const adminToken = loadAdminToken();
  const includeChat = boolFlag('--include-chat');
  const includeResponses = boolFlag('--include-responses');
  const issuedAt = Date.now();
  const accessKeyIdHint = `live_smoke_external_terminal_${issuedAt}`;

  let accessKeyId = '';
  let clientToken = '';
  let selectedModel = '';
  let modelCount = 0;
  let modelIdsSample = [];
  let deniedResults = {};
  const checks = [];

  try {
    const issued = await requestJson({
      method: 'POST',
      url: `${baseUrl}/admin/clients/access-keys`,
      token: adminToken,
      body: {
        access_key_id: accessKeyIdHint,
        name: 'Live Smoke External Terminal',
        user_id: 'live_smoke_external_terminal',
        app_id: 'external_terminal',
        capabilities: [
          'models',
          'ai.generate.local',
          'ai.generate.paid',
          'events',
          'memory',
          'skills',
          'skills.execute',
          'web.fetch',
          'hub_access_keys.manage',
        ],
        scopes: ['models', 'ai.generate.local', 'events', 'memory', 'skills', 'web.fetch'],
        default_web_fetch_enabled: true,
        ttl_sec: 600,
        note: 'temporary live smoke; revoke immediately',
      },
    });
    assert.equal(issued.status, 200, `issue_status_${issued.status}`);
    const key = issued.json?.access_key || {};
    accessKeyId = safeString(key.access_key_id);
    clientToken = safeString(issued.json?.client_token);
    assert.ok(accessKeyId, 'access_key_id_missing');
    assert.ok(clientToken, 'client_token_missing');
    assert.deepEqual(key.capabilities || [], ['models', 'ai.generate.local']);
    assert.deepEqual(key.scopes || [], ['models', 'ai.generate.local']);
    assert.equal(safeString(key.connector_profile), 'external_terminal_ai_only');
    assert.equal(safeString(key.authority_profile), 'ai_client_only');
    assert.equal(key.xt_pairing_authority, false);
    assert.equal(key.durable_memory_authority, false);
    assert.equal(key.skills_execution_authority, false);
    assert.equal(hasCapability(key.denied_capabilities, 'memory'), true);
    assert.equal(hasCapability(key.denied_capabilities, 'skills.execute'), true);
    assert.equal(hasCapability(key.denied_capabilities, 'web.fetch'), true);
    checks.push('issued_ai_only_key');

    const remoteSmoke = await runExternalTerminalAiOnlyRemoteSmoke({
      baseUrl: probeBaseUrl,
      token: clientToken,
      includeChat,
      includeResponses,
      model: argValue('--model', ''),
    });
    selectedModel = safeString(remoteSmoke.selected_model);
    modelCount = Number(remoteSmoke.model_count || 0);
    modelIdsSample = Array.isArray(remoteSmoke.model_ids_sample) ? remoteSmoke.model_ids_sample : [];
    deniedResults = remoteSmoke.denied_results || {};
    checks.push(...(Array.isArray(remoteSmoke.checks) ? remoteSmoke.checks : []));

    const detail = await requestJson({
      url: `${baseUrl}/admin/clients/access-keys/${encodeURIComponent(accessKeyId)}`,
      token: adminToken,
    });
    assert.equal(detail.status, 200, `detail_status_${detail.status}`);
    assert.equal(safeString(detail.json?.access_key?.connector_profile), 'external_terminal_ai_only');
    checks.push('detail_profile_preserved');
  } finally {
    if (accessKeyId) {
      const revoked = await requestJson({
        method: 'POST',
        url: `${baseUrl}/admin/clients/access-keys/${encodeURIComponent(accessKeyId)}/revoke`,
        token: adminToken,
        body: { note: 'live smoke complete' },
      });
      if (revoked.status === 200 && safeString(revoked.json?.access_key?.status) === 'revoked') {
        checks.push('temporary_key_revoked');
      } else {
        checks.push(`temporary_key_revoke_status_${revoked.status}`);
      }
    }
  }

  process.stdout.write(JSON.stringify({
    ok: true,
    schema_version: SCHEMA_VERSION,
    issue_base_url: baseUrl,
    probe_base_url: probeBaseUrl,
    access_key_id: accessKeyId,
    token_redacted: clientToken ? '[redacted]' : '',
    selected_model: selectedModel,
    model_count: modelCount,
    model_ids_sample: modelIdsSample,
    denied_results: deniedResults,
    checks,
    include_chat: includeChat,
    include_responses: includeResponses,
  }, null, 2) + '\n');
}

main().catch((error) => {
  process.stderr.write(JSON.stringify({
    ok: false,
    schema_version: SCHEMA_VERSION,
    error: safeString(error?.message || error),
  }, null, 2) + '\n');
  process.exitCode = 1;
});
