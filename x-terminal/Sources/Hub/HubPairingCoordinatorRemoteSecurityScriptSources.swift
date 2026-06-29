import Foundation

extension HubPairingCoordinator {
    func remoteVoiceWakeProfileGetScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv() {
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: safe(process.env.HUB_PROJECT_ID || ''),
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }

  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

async function main() {
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  const desiredWakeMode = safe(process.env.XTERMINAL_VOICE_WAKE_DESIRED_MODE || 'wake_phrase') || 'wake_phrase';

  const resp = await new Promise((resolve, reject) => {
    memoryClient.GetVoiceWakeProfile(
      {
        client,
        desired_wake_mode: desiredWakeMode,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  const profile = resp?.profile || {};
  out({
    ok: true,
    source: 'hub_memory_v1_grpc',
    profile: {
      schema_version: safe(profile?.schema_version || ''),
      profile_id: safe(profile?.profile_id || 'default'),
      trigger_words: Array.isArray(profile?.trigger_words) ? profile.trigger_words.map((item) => safe(item)).filter(Boolean) : [],
      updated_at_ms: asMs(profile?.updated_at_ms || 0),
      wake_mode: safe(profile?.wake_mode || desiredWakeMode),
      requires_pairing_ready: !!profile?.requires_pairing_ready,
      audit_ref: safe(profile?.audit_ref || ''),
    },
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('unimplemented')
    ? 'hub_memory_unimplemented'
    : (msg || 'remote_voice_wake_profile_fetch_failed');
  out({
    ok: false,
    source: 'hub_memory_v1_grpc',
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    func remoteVoiceWakeProfileSetScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv() {
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: safe(process.env.HUB_PROJECT_ID || ''),
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }

  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function decodeProfileFromEnv() {
  const encoded = safe(process.env.XTERMINAL_VOICE_WAKE_PROFILE_JSON_B64 || '');
  if (!encoded) {
    throw new Error('voice_wake_profile_payload_missing');
  }
  const json = Buffer.from(encoded, 'base64').toString('utf8');
  const parsed = JSON.parse(json);
  return {
    schema_version: safe(parsed?.schema_version || ''),
    profile_id: safe(parsed?.profile_id || 'default'),
    trigger_words: Array.isArray(parsed?.trigger_words) ? parsed.trigger_words.map((item) => safe(item)).filter(Boolean) : [],
    updated_at_ms: asMs(parsed?.updated_at_ms || 0),
    scope: safe(parsed?.scope || ''),
    source: safe(parsed?.source || ''),
    wake_mode: safe(parsed?.wake_mode || 'wake_phrase'),
    requires_pairing_ready: !!parsed?.requires_pairing_ready,
    audit_ref: safe(parsed?.audit_ref || ''),
  };
}

async function main() {
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  const profile = decodeProfileFromEnv();

  const resp = await new Promise((resolve, reject) => {
    memoryClient.SetVoiceWakeProfile(
      {
        client,
        profile,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  const synced = resp?.profile || {};
  out({
    ok: true,
    source: 'hub_memory_v1_grpc',
    profile: {
      schema_version: safe(synced?.schema_version || ''),
      profile_id: safe(synced?.profile_id || profile.profile_id || 'default'),
      trigger_words: Array.isArray(synced?.trigger_words) ? synced.trigger_words.map((item) => safe(item)).filter(Boolean) : [],
      updated_at_ms: asMs(synced?.updated_at_ms || 0),
      wake_mode: safe(synced?.wake_mode || profile.wake_mode || 'wake_phrase'),
      requires_pairing_ready: !!synced?.requires_pairing_ready,
      audit_ref: safe(synced?.audit_ref || profile.audit_ref || ''),
    },
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('unimplemented')
    ? 'hub_memory_unimplemented'
    : (msg || 'remote_voice_wake_profile_set_failed');
  out({
    ok: false,
    source: 'hub_memory_v1_grpc',
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    func remoteVoiceGrantChallengeScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectOverride = '') {
  const projectId = safe(projectOverride || process.env.HUB_PROJECT_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }

  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function parseBool(v, fallback = false) {
  const raw = safe(v).toLowerCase();
  if (!raw) return fallback;
  if (['1', 'true', 'yes', 'y', 'on'].includes(raw)) return true;
  if (['0', 'false', 'no', 'n', 'off'].includes(raw)) return false;
  return fallback;
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

async function main() {
  const requestId = safe(process.env.XTERMINAL_VOICE_CHALLENGE_REQUEST_ID || '');
  const templateId = safe(process.env.XTERMINAL_VOICE_CHALLENGE_TEMPLATE_ID || '');
  const actionDigest = safe(process.env.XTERMINAL_VOICE_CHALLENGE_ACTION_DIGEST || '');
  const scopeDigest = safe(process.env.XTERMINAL_VOICE_CHALLENGE_SCOPE_DIGEST || '');
  if (!requestId || !templateId || !actionDigest || !scopeDigest) {
    throw new Error('invalid_request');
  }

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);

  const ttlRaw = Number.parseInt(safe(process.env.XTERMINAL_VOICE_CHALLENGE_TTL_MS || '120000'), 10);
  const resp = await new Promise((resolve, reject) => {
    memoryClient.IssueVoiceGrantChallenge(
      {
        request_id: requestId,
        client,
        template_id: templateId,
        action_digest: actionDigest,
        scope_digest: scopeDigest,
        amount_digest: safe(process.env.XTERMINAL_VOICE_CHALLENGE_AMOUNT_DIGEST || ''),
        challenge_code: safe(process.env.XTERMINAL_VOICE_CHALLENGE_CODE || ''),
        risk_level: safe(process.env.XTERMINAL_VOICE_CHALLENGE_RISK_LEVEL || 'high'),
        bound_device_id: safe(process.env.XTERMINAL_VOICE_CHALLENGE_BOUND_DEVICE_ID || ''),
        mobile_terminal_id: safe(process.env.XTERMINAL_VOICE_CHALLENGE_MOBILE_TERMINAL_ID || ''),
        allow_voice_only: parseBool(process.env.XTERMINAL_VOICE_CHALLENGE_ALLOW_VOICE_ONLY || '', false),
        requires_mobile_confirm: parseBool(process.env.XTERMINAL_VOICE_CHALLENGE_REQUIRES_MOBILE_CONFIRM || '', true),
        ttl_ms: Number.isFinite(ttlRaw) ? Math.max(10000, Math.min(600000, ttlRaw)) : 120000,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  const challenge = resp?.challenge || null;
  const challengeId = safe(challenge?.challenge_id || '');
  if (!challengeId) {
    out({
      ok: false,
      source: 'hub_memory_v1_grpc',
      reason: 'voice_grant_challenge_missing',
      error_code: 'voice_grant_challenge_missing',
      error_message: 'voice_grant_challenge_missing',
    });
    process.exit(1);
    return;
  }

  out({
    ok: true,
    source: 'hub_memory_v1_grpc',
    challenge: {
      challenge_id: challengeId,
      template_id: safe(challenge?.template_id || ''),
      action_digest: safe(challenge?.action_digest || ''),
      scope_digest: safe(challenge?.scope_digest || ''),
      amount_digest: safe(challenge?.amount_digest || ''),
      challenge_code: safe(challenge?.challenge_code || ''),
      risk_level: safe(challenge?.risk_level || 'high'),
      requires_mobile_confirm: !!challenge?.requires_mobile_confirm,
      allow_voice_only: !!challenge?.allow_voice_only,
      bound_device_id: safe(challenge?.bound_device_id || ''),
      mobile_terminal_id: safe(challenge?.mobile_terminal_id || ''),
      issued_at_ms: asMs(challenge?.issued_at_ms || 0),
      expires_at_ms: asMs(challenge?.expires_at_ms || 0),
    },
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('unimplemented')
    ? 'hub_memory_unimplemented'
    : (msg || 'remote_voice_grant_challenge_failed');
  out({
    ok: false,
    source: 'hub_memory_v1_grpc',
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    func remoteVoiceGrantVerifyScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectOverride = '') {
  const projectId = safe(projectOverride || process.env.HUB_PROJECT_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }

  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function parseBool(v, fallback = false) {
  const raw = safe(v).toLowerCase();
  if (!raw) return fallback;
  if (['1', 'true', 'yes', 'y', 'on'].includes(raw)) return true;
  if (['0', 'false', 'no', 'n', 'off'].includes(raw)) return false;
  return fallback;
}

function parseScore(v) {
  const n = Number(safe(v || ''));
  if (!Number.isFinite(n)) return 0;
  return n;
}

async function main() {
  const requestId = safe(process.env.XTERMINAL_VOICE_VERIFY_REQUEST_ID || '');
  const challengeId = safe(process.env.XTERMINAL_VOICE_VERIFY_CHALLENGE_ID || '');
  const verifyNonce = safe(process.env.XTERMINAL_VOICE_VERIFY_NONCE || '');
  if (!requestId || !challengeId || !verifyNonce) {
    throw new Error('invalid_request');
  }

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);

  const resp = await new Promise((resolve, reject) => {
    memoryClient.VerifyVoiceGrantResponse(
      {
        request_id: requestId,
        client,
        challenge_id: challengeId,
        challenge_code: safe(process.env.XTERMINAL_VOICE_VERIFY_CHALLENGE_CODE || ''),
        transcript: String(process.env.XTERMINAL_VOICE_VERIFY_TRANSCRIPT || ''),
        transcript_hash: safe(process.env.XTERMINAL_VOICE_VERIFY_TRANSCRIPT_HASH || ''),
        semantic_match_score: parseScore(process.env.XTERMINAL_VOICE_VERIFY_SEMANTIC_MATCH_SCORE || ''),
        parsed_action_digest: safe(process.env.XTERMINAL_VOICE_VERIFY_PARSED_ACTION_DIGEST || ''),
        parsed_scope_digest: safe(process.env.XTERMINAL_VOICE_VERIFY_PARSED_SCOPE_DIGEST || ''),
        parsed_amount_digest: safe(process.env.XTERMINAL_VOICE_VERIFY_PARSED_AMOUNT_DIGEST || ''),
        verify_nonce: verifyNonce,
        bound_device_id: safe(process.env.XTERMINAL_VOICE_VERIFY_BOUND_DEVICE_ID || ''),
        mobile_confirmed: parseBool(process.env.XTERMINAL_VOICE_VERIFY_MOBILE_CONFIRMED || '', false),
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  out({
    ok: true,
    source: 'hub_memory_v1_grpc',
    verified: !!resp?.verified,
    decision: safe(resp?.decision || (resp?.verified ? 'allow' : 'deny')),
    deny_code: safe(resp?.deny_code || ''),
    challenge_id: safe(resp?.challenge_id || challengeId),
    transcript_hash: safe(resp?.transcript_hash || ''),
    semantic_match_score: Number(resp?.semantic_match_score || 0),
    challenge_match: !!resp?.challenge_match,
    device_binding_ok: !!resp?.device_binding_ok,
    mobile_confirmed: !!resp?.mobile_confirmed,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('unimplemented')
    ? 'hub_memory_unimplemented'
    : (msg || 'remote_voice_grant_verify_failed');
  out({
    ok: false,
    source: 'hub_memory_v1_grpc',
    verified: false,
    decision: 'failed',
    deny_code: '',
    challenge_id: '',
    transcript_hash: '',
    semantic_match_score: 0,
    challenge_match: false,
    device_binding_ok: false,
    mobile_confirmed: false,
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    func remoteSecretVaultListScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv() {
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: safe(process.env.HUB_PROJECT_ID || ''),
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }

  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asInt(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

async function main() {
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  if (typeof memoryClient.ListSecretVaultItems !== 'function') {
    throw new Error('hub_secret_vault_unimplemented');
  }

  const scope = safe(process.env.XTERMINAL_SECRET_VAULT_SCOPE || '');
  const namePrefix = safe(process.env.XTERMINAL_SECRET_VAULT_NAME_PREFIX || '');
  const limitRaw = Number.parseInt(safe(process.env.XTERMINAL_SECRET_VAULT_LIMIT || '200'), 10);
  const limit = Math.max(1, Math.min(500, Number.isFinite(limitRaw) ? limitRaw : 200));

  const resp = await new Promise((resolve, reject) => {
    memoryClient.ListSecretVaultItems(
      {
        client,
        scope,
        name_prefix: namePrefix,
        limit,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out || {});
      }
    );
  });

  const items = Array.isArray(resp?.items)
    ? resp.items.map((it) => ({
        item_id: safe(it?.item_id || it?.id || ''),
        scope: safe(it?.scope || '').toLowerCase(),
        name: safe(it?.name || ''),
        sensitivity: safe(it?.sensitivity || 'secret').toLowerCase(),
        created_at_ms: asMs(it?.created_at_ms || 0),
        updated_at_ms: asMs(it?.updated_at_ms || 0),
      })).filter((it) => it.item_id && it.scope && it.name)
    : [];

  out({
    ok: true,
    source: 'hub_memory_v1_grpc',
    updated_at_ms: asMs(resp?.updated_at_ms || 0),
    items,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('hub_secret_vault_unimplemented') || lower.includes('unimplemented')
    ? 'hub_secret_vault_unimplemented'
    : (msg || 'remote_secret_vault_list_failed');
  out({
    ok: false,
    source: 'hub_memory_v1_grpc',
    updated_at_ms: 0,
    items: [],
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    func remoteSecretVaultCreateScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectOverride = '') {
  const projectId = safe(projectOverride || process.env.HUB_PROJECT_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }

  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

async function main() {
  const scope = safe(process.env.XTERMINAL_SECRET_VAULT_SCOPE || '').toLowerCase();
  const name = safe(process.env.XTERMINAL_SECRET_VAULT_NAME || '');
  const plaintextB64 = safe(process.env.XTERMINAL_SECRET_VAULT_PLAINTEXT_B64 || '');
  if (!scope || !name || !plaintextB64) {
    throw new Error('invalid_request');
  }

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  if (typeof memoryClient.CreateSecretVaultItem !== 'function') {
    throw new Error('hub_secret_vault_unimplemented');
  }

  const req = {
    client,
    scope,
    name,
    plaintext_b64: plaintextB64,
    plaintext_bytes: Buffer.from(plaintextB64, 'base64'),
    sensitivity: safe(process.env.XTERMINAL_SECRET_VAULT_SENSITIVITY || 'secret').toLowerCase(),
    display_name: safe(process.env.XTERMINAL_SECRET_VAULT_DISPLAY_NAME || ''),
    reason: safe(process.env.XTERMINAL_SECRET_VAULT_REASON || ''),
  };

  const resp = await new Promise((resolve, reject) => {
    memoryClient.CreateSecretVaultItem(req, md, (err, out) => {
      if (err) reject(err);
      else resolve(out || {});
    });
  });

  const item = resp?.item || resp?.secret_vault_item || {};
  const itemId = safe(item?.item_id || item?.id || '');
  if (!itemId) {
    out({
      ok: false,
      source: 'hub_memory_v1_grpc',
      reason: 'secret_vault_item_missing',
      error_code: 'secret_vault_item_missing',
      error_message: 'secret_vault_item_missing',
    });
    process.exit(1);
    return;
  }

  out({
    ok: true,
    source: 'hub_memory_v1_grpc',
    item: {
      item_id: itemId,
      scope: safe(item?.scope || scope).toLowerCase(),
      name: safe(item?.name || name),
      sensitivity: safe(item?.sensitivity || 'secret').toLowerCase(),
      created_at_ms: asMs(item?.created_at_ms || 0),
      updated_at_ms: asMs(item?.updated_at_ms || 0),
    },
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('hub_secret_vault_unimplemented') || lower.includes('unimplemented')
    ? 'hub_secret_vault_unimplemented'
    : (msg || 'remote_secret_vault_create_failed');
  out({
    ok: false,
    source: 'hub_memory_v1_grpc',
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    func remoteSecretVaultBeginUseScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectOverride = '') {
  const projectId = safe(projectOverride || process.env.HUB_PROJECT_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }

  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function asMs(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.floor(n));
}

async function main() {
  const itemId = safe(process.env.XTERMINAL_SECRET_VAULT_ITEM_ID || '');
  const scope = safe(process.env.XTERMINAL_SECRET_VAULT_SCOPE || '').toLowerCase();
  const name = safe(process.env.XTERMINAL_SECRET_VAULT_NAME || '');
  const purpose = safe(process.env.XTERMINAL_SECRET_VAULT_USE_PURPOSE || '');
  if (!purpose || (!itemId && !(scope && name))) {
    throw new Error('invalid_request');
  }

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  if (typeof memoryClient.BeginSecretVaultUse !== 'function') {
    throw new Error('hub_secret_vault_unimplemented');
  }

  const ttlRaw = Number.parseInt(safe(process.env.XTERMINAL_SECRET_VAULT_USE_TTL_MS || '60000'), 10);
  const req = {
    client,
    item_id: itemId,
    scope,
    name,
    purpose,
    target: safe(process.env.XTERMINAL_SECRET_VAULT_USE_TARGET || ''),
    ttl_ms: Number.isFinite(ttlRaw) ? Math.max(1000, Math.min(600000, ttlRaw)) : 60000,
  };

  const resp = await new Promise((resolve, reject) => {
    memoryClient.BeginSecretVaultUse(req, md, (err, out) => {
      if (err) reject(err);
      else resolve(out || {});
    });
  });

  out({
    ok: true,
    source: 'hub_memory_v1_grpc',
    lease_id: safe(resp?.lease_id || resp?.lease?.lease_id || ''),
    use_token: safe(resp?.use_token || resp?.lease?.use_token || ''),
    item_id: safe(resp?.item_id || itemId),
    expires_at_ms: asMs(resp?.expires_at_ms || resp?.lease?.expires_at_ms || 0),
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('hub_secret_vault_unimplemented') || lower.includes('unimplemented')
    ? 'hub_secret_vault_unimplemented'
    : (msg || 'remote_secret_vault_use_failed');
  out({
    ok: false,
    source: 'hub_memory_v1_grpc',
    lease_id: '',
    use_token: '',
    item_id: '',
    expires_at_ms: 0,
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    func remoteSecretVaultRedeemScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectOverride = '') {
  const projectId = safe(projectOverride || process.env.HUB_PROJECT_ID || '');
  return {
    device_id: safe(process.env.HUB_DEVICE_ID || 'terminal_device'),
    user_id: safe(process.env.HUB_USER_ID || ''),
    app_id: safe(process.env.HUB_APP_ID || 'x_terminal'),
    project_id: projectId,
    session_id: safe(process.env.HUB_SESSION_ID || ''),
  };
}

function metadataFromEnv() {
  const tok = safe(process.env.HUB_CLIENT_TOKEN || '');
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

async function resolveProtoPath() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'proto_path.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.resolveHubProtoPath === 'function') {
        const p = safe(mod.resolveHubProtoPath(process.env));
        if (p) return p;
      }
    } catch {}
  }

  const candidates = [
    path.resolve(process.cwd(), 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', 'protocol', 'hub_protocol_v1.proto'),
    path.resolve(process.cwd(), '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return candidates[0];
}

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  return loaded?.ax?.hub?.v1;
}

async function makeClientCreds() {
  const srcDir = path.resolve(process.cwd(), 'src');
  const helper = path.join(srcDir, 'client_credentials.js');
  if (fs.existsSync(helper)) {
    try {
      const mod = await import(pathToFileURL(helper).href);
      if (typeof mod.makeClientCredentials === 'function') {
        const built = mod.makeClientCredentials(process.env);
        if (built?.creds) {
          return { creds: built.creds, options: built.options || {} };
        }
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function writePlaintext(outputPath, buffer) {
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, buffer, { mode: 0o600 });
}

async function main() {
  const useToken = safe(process.env.XTERMINAL_SECRET_VAULT_USE_TOKEN || '');
  const outputPath = safe(process.env.XTERMINAL_SECRET_VAULT_REDEEM_OUTPUT || '');
  if (!useToken || !outputPath) {
    throw new Error('invalid_request');
  }

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const md = metadataFromEnv();
  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  if (typeof memoryClient.RedeemSecretVaultUse !== 'function') {
    throw new Error('hub_secret_vault_unimplemented');
  }

  const req = {
    client,
    use_token: useToken,
  };

  const resp = await new Promise((resolve, reject) => {
    memoryClient.RedeemSecretVaultUse(req, md, (err, out) => {
      if (err) reject(err);
      else resolve(out || {});
    });
  });

  let plaintextBuffer = Buffer.alloc(0);
  if (Buffer.isBuffer(resp?.plaintext_bytes)) {
    plaintextBuffer = Buffer.from(resp.plaintext_bytes);
  } else if (resp?.plaintext_bytes != null && typeof resp.plaintext_bytes === 'object' && typeof resp.plaintext_bytes.length === 'number') {
    plaintextBuffer = Buffer.from(resp.plaintext_bytes);
  }
  if (!plaintextBuffer.length) {
    throw new Error('secret_vault_plaintext_missing');
  }

  writePlaintext(outputPath, plaintextBuffer);
  out({
    ok: true,
    source: 'hub_memory_v1_grpc',
    lease_id: safe(resp?.lease_id || resp?.lease?.lease_id || ''),
    item_id: safe(resp?.item_id || resp?.item?.item_id || ''),
    plaintext_bytes: plaintextBuffer.length,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('hub_secret_vault_unimplemented') || lower.includes('unimplemented')
    ? 'hub_secret_vault_unimplemented'
    : (msg || 'remote_secret_vault_redeem_failed');
  out({
    ok: false,
    source: 'hub_memory_v1_grpc',
    lease_id: '',
    item_id: '',
    plaintext_bytes: 0,
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

}
