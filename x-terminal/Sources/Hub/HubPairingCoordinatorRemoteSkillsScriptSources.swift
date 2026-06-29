import Foundation

extension HubPairingCoordinator {
    func remoteSkillsSearchScriptSource() -> String {
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

function reqClientFromEnv(projectIdOverride) {
  const projectId = projectIdOverride === undefined || projectIdOverride === null
    ? safe(process.env.HUB_PROJECT_ID || '')
    : safe(projectIdOverride);
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
        if (built?.creds) return { creds: built.creds, options: built.options || {} };
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function main() {
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubSkills) throw new Error('hub_skills_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const query = safe(process.env.XTERMINAL_SKILLS_QUERY || '');
  const sourceFilter = safe(process.env.XTERMINAL_SKILLS_SOURCE_FILTER || '');
  const limit = Number.parseInt(safe(process.env.XTERMINAL_SKILLS_LIMIT || '20'), 10) || 20;
  const projectId = safe(process.env.XTERMINAL_SKILLS_PROJECT_ID || '');

  const { creds, options } = await makeClientCreds();
  const skillsClient = new proto.HubSkills(addr, creds, options);
  const md = metadataFromEnv();
  const client = reqClientFromEnv(projectId);

  const resp = await new Promise((resolve, reject) => {
    skillsClient.SearchSkills(
      {
        client,
        query,
        source_filter: sourceFilter,
        limit,
      },
      md,
      (err, result) => {
        if (err) reject(err);
        else resolve(result || {});
      }
    );
  });

  const results = Array.isArray(resp?.results) ? resp.results : [];
  const officialChannelStatus = resp?.official_channel_status && typeof resp.official_channel_status === 'object'
    ? {
      channel_id: safe(resp.official_channel_status.channel_id || ''),
      status: safe(resp.official_channel_status.status || ''),
      updated_at_ms: Number(resp.official_channel_status.updated_at_ms || 0),
      last_attempt_at_ms: Number(resp.official_channel_status.last_attempt_at_ms || 0),
      last_success_at_ms: Number(resp.official_channel_status.last_success_at_ms || 0),
      skill_count: Number(resp.official_channel_status.skill_count || 0),
      error_code: safe(resp.official_channel_status.error_code || ''),
      maintenance_enabled: !!resp.official_channel_status.maintenance_enabled,
      maintenance_interval_ms: Number(resp.official_channel_status.maintenance_interval_ms || 0),
      maintenance_last_run_at_ms: Number(resp.official_channel_status.maintenance_last_run_at_ms || 0),
      maintenance_source_kind: safe(resp.official_channel_status.maintenance_source_kind || ''),
      last_transition_at_ms: Number(resp.official_channel_status.last_transition_at_ms || 0),
      last_transition_kind: safe(resp.official_channel_status.last_transition_kind || ''),
      last_transition_summary: safe(resp.official_channel_status.last_transition_summary || ''),
    }
    : null;
  out({
    ok: true,
    source: 'hub_runtime_grpc',
    updated_at_ms: Number(resp?.updated_at_ms || 0),
    results: results.map((row) => ({
      skill_id: safe(row?.skill_id || ''),
      name: safe(row?.name || ''),
      version: safe(row?.version || ''),
      description: safe(row?.description || ''),
      publisher_id: safe(row?.publisher_id || ''),
      capabilities_required: Array.isArray(row?.capabilities_required) ? row.capabilities_required.map((item) => safe(item)).filter(Boolean) : [],
      source_id: safe(row?.source_id || ''),
      package_sha256: safe(row?.package_sha256 || ''),
      install_hint: safe(row?.install_hint || ''),
      risk_level: safe(row?.risk_level || ''),
      requires_grant: !!row?.requires_grant,
      side_effect_class: safe(row?.side_effect_class || ''),
    })),
    official_channel_status: officialChannelStatus,
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    updated_at_ms: 0,
    results: [],
    reason: msg || 'remote_skills_search_failed',
    error_code: msg || 'remote_skills_search_failed',
    error_message: msg || 'remote_skills_search_failed',
  });
  process.exit(1);
});
"""#
    }

    func remoteSkillPinScriptSource() -> String {
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

function reqClientFromEnv(projectIdOverride) {
  const projectId = projectIdOverride === undefined || projectIdOverride === null
    ? safe(process.env.HUB_PROJECT_ID || '')
    : safe(projectIdOverride);
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
        if (built?.creds) return { creds: built.creds, options: built.options || {} };
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function protoScope(scope) {
  if (scope === 'global') return 'SKILL_PIN_SCOPE_GLOBAL';
  if (scope === 'project') return 'SKILL_PIN_SCOPE_PROJECT';
  throw new Error('unsupported_skill_pin_scope');
}

function normalizedScope(scope) {
  if (scope === 'SKILL_PIN_SCOPE_GLOBAL') return 'global';
  if (scope === 'SKILL_PIN_SCOPE_PROJECT') return 'project';
  return safe(scope).toLowerCase();
}

async function main() {
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubSkills) throw new Error('hub_skills_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const scope = safe(process.env.XTERMINAL_SKILLS_PIN_SCOPE || '').toLowerCase();
  const skillId = safe(process.env.XTERMINAL_SKILLS_PIN_SKILL_ID || '');
  const packageSha = safe(process.env.XTERMINAL_SKILLS_PIN_PACKAGE_SHA256 || '').toLowerCase();
  const projectId = scope === 'project'
    ? safe(process.env.XTERMINAL_SKILLS_PIN_PROJECT_ID || '')
    : '';
  const note = safe(process.env.XTERMINAL_SKILLS_PIN_NOTE || '');
  const requestId = safe(process.env.XTERMINAL_SKILLS_PIN_REQUEST_ID || '');
  if (!skillId) throw new Error('missing_skill_id');
  if (!packageSha) throw new Error('missing_package_sha256');

  const { creds, options } = await makeClientCreds();
  const skillsClient = new proto.HubSkills(addr, creds, options);
  const md = metadataFromEnv();
  const client = reqClientFromEnv(projectId);

  const resp = await new Promise((resolve, reject) => {
    skillsClient.SetSkillPin(
      {
        client,
        request_id: requestId,
        scope: protoScope(scope),
        skill_id: skillId,
        package_sha256: packageSha,
        note,
        created_at_ms: Date.now(),
      },
      md,
      (err, result) => {
        if (err) reject(err);
        else resolve(result || {});
      }
    );
  });

  out({
    ok: true,
    source: 'hub_runtime_grpc',
    scope: normalizedScope(resp?.scope || scope),
    user_id: safe(resp?.user_id || ''),
    project_id: safe(resp?.project_id || projectId),
    skill_id: safe(resp?.skill_id || skillId),
    package_sha256: safe(resp?.package_sha256 || packageSha),
    previous_package_sha256: safe(resp?.previous_package_sha256 || ''),
    updated_at_ms: Number(resp?.updated_at_ms || 0),
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    scope: safe(process.env.XTERMINAL_SKILLS_PIN_SCOPE || ''),
    user_id: '',
    project_id: safe(process.env.XTERMINAL_SKILLS_PIN_PROJECT_ID || ''),
    skill_id: safe(process.env.XTERMINAL_SKILLS_PIN_SKILL_ID || ''),
    package_sha256: safe(process.env.XTERMINAL_SKILLS_PIN_PACKAGE_SHA256 || ''),
    previous_package_sha256: '',
    updated_at_ms: 0,
    reason: msg || 'remote_skill_pin_failed',
    error_code: msg || 'remote_skill_pin_failed',
    error_message: msg || 'remote_skill_pin_failed',
  });
  process.exit(1);
});
"""#
    }

    func remoteResolvedSkillsScriptSource() -> String {
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

function reqClientFromEnv(projectIdOverride) {
  const projectId = projectIdOverride === undefined || projectIdOverride === null
    ? safe(process.env.HUB_PROJECT_ID || '')
    : safe(projectIdOverride);
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
        if (built?.creds) return { creds: built.creds, options: built.options || {} };
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function normalizedScope(scope) {
  if (scope === 'SKILL_PIN_SCOPE_GLOBAL') return 'global';
  if (scope === 'SKILL_PIN_SCOPE_PROJECT') return 'project';
  return safe(scope).toLowerCase();
}

async function main() {
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubSkills) throw new Error('hub_skills_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const projectId = safe(process.env.XTERMINAL_RESOLVED_SKILLS_PROJECT_ID || '');

  const { creds, options } = await makeClientCreds();
  const skillsClient = new proto.HubSkills(addr, creds, options);
  const md = metadataFromEnv();
  const client = reqClientFromEnv(projectId);

  const resp = await new Promise((resolve, reject) => {
    skillsClient.ListResolvedSkills(
      { client },
      md,
      (err, result) => {
        if (err) reject(err);
        else resolve(result || {});
      }
    );
  });

  const skills = Array.isArray(resp?.skills) ? resp.skills : [];
  out({
    ok: true,
    source: 'hub_runtime_grpc',
    skills: skills.map((row) => ({
      scope: normalizedScope(row?.scope || ''),
      skill: {
        skill_id: safe(row?.skill?.skill_id || ''),
        name: safe(row?.skill?.name || ''),
        version: safe(row?.skill?.version || ''),
        description: safe(row?.skill?.description || ''),
        publisher_id: safe(row?.skill?.publisher_id || ''),
        capabilities_required: Array.isArray(row?.skill?.capabilities_required) ? row.skill.capabilities_required.map((item) => safe(item)).filter(Boolean) : [],
        source_id: safe(row?.skill?.source_id || ''),
        package_sha256: safe(row?.skill?.package_sha256 || ''),
        install_hint: safe(row?.skill?.install_hint || ''),
        risk_level: safe(row?.skill?.risk_level || ''),
        requires_grant: !!row?.skill?.requires_grant,
        side_effect_class: safe(row?.skill?.side_effect_class || ''),
      },
    })),
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    skills: [],
    reason: msg || 'remote_resolved_skills_failed',
    error_code: msg || 'remote_resolved_skills_failed',
    error_message: msg || 'remote_resolved_skills_failed',
  });
  process.exit(1);
});
"""#
    }

    func remoteSkillManifestScriptSource() -> String {
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
        if (built?.creds) return { creds: built.creds, options: built.options || {} };
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function main() {
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubSkills) throw new Error('hub_skills_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const packageSHA256 = safe(process.env.XTERMINAL_SKILL_MANIFEST_PACKAGE_SHA256 || '');
  if (!packageSHA256) throw new Error('missing_package_sha256');

  const { creds, options } = await makeClientCreds();
  const skillsClient = new proto.HubSkills(addr, creds, options);
  const md = metadataFromEnv();
  const client = reqClientFromEnv();

  const resp = await new Promise((resolve, reject) => {
    skillsClient.GetSkillManifest(
      { client, package_sha256: packageSHA256 },
      md,
      (err, result) => {
        if (err) reject(err);
        else resolve(result || {});
      }
    );
  });

  out({
    ok: true,
    source: 'hub_runtime_grpc',
    package_sha256: packageSHA256,
    manifest_json: safe(resp?.manifest_json || ''),
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    package_sha256: safe(process.env.XTERMINAL_SKILL_MANIFEST_PACKAGE_SHA256 || ''),
    manifest_json: '',
    reason: msg || 'remote_skill_manifest_failed',
    error_code: msg || 'remote_skill_manifest_failed',
    error_message: msg || 'remote_skill_manifest_failed',
  });
  process.exit(1);
});
"""#
    }

    func remoteSkillPackageDownloadScriptSource() -> String {
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
        if (built?.creds) return { creds: built.creds, options: built.options || {} };
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function main() {
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubSkills) throw new Error('hub_skills_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const packageSHA256 = safe(process.env.XTERMINAL_SKILL_PACKAGE_DOWNLOAD_SHA256 || '');
  if (!packageSHA256) throw new Error('missing_package_sha256');

  const { creds, options } = await makeClientCreds();
  const skillsClient = new proto.HubSkills(addr, creds, options);
  const md = metadataFromEnv();
  const client = reqClientFromEnv();

  const chunks = await new Promise((resolve, reject) => {
    const rows = [];
    const stream = skillsClient.DownloadSkillPackage({ client, package_sha256: packageSHA256 }, md);
    stream.on('data', (chunk) => {
      if (chunk?.data && chunk.data.length > 0) rows.push(Buffer.from(chunk.data));
    });
    stream.on('error', reject);
    stream.on('end', () => resolve(rows));
  });
  const data = Buffer.concat(chunks);

  out({
    ok: data.length > 0,
    source: 'hub_runtime_grpc',
    package_sha256: packageSHA256,
    package_base64: data.toString('base64'),
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    package_sha256: safe(process.env.XTERMINAL_SKILL_PACKAGE_DOWNLOAD_SHA256 || ''),
    package_base64: '',
    reason: msg || 'remote_skill_package_download_failed',
    error_code: msg || 'remote_skill_package_download_failed',
    error_message: msg || 'remote_skill_package_download_failed',
  });
  process.exit(1);
});
"""#
    }

    func remoteSkillRunnerGateScriptSource() -> String {
        #"""
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

const safe = (v) => String(v ?? '').trim();
const idToken = (v) => safe(v).toLowerCase().replace(/[^a-z0-9_.-]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 64);
const out = (obj) => {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
};

function reqClientFromEnv(projectIdOverride) {
  const projectId = projectIdOverride === undefined || projectIdOverride === null
    ? safe(process.env.HUB_PROJECT_ID || '')
    : safe(projectIdOverride);
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
        if (built?.creds) return { creds: built.creds, options: built.options || {} };
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

function parseExecArgv() {
  try {
    const parsed = JSON.parse(safe(process.env.XTERMINAL_SKILL_RUNNER_EXEC_ARGV_JSON || '[]'));
    return Array.isArray(parsed) ? parsed.map((item) => String(item ?? '')) : [];
  } catch {
    return [];
  }
}

async function unary(client, method, request, md) {
  return await new Promise((resolve, reject) => {
    client[method](request, md, (err, result) => {
      if (err) reject(err);
      else resolve(result || {});
    });
  });
}

async function main() {
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubMemory) throw new Error('hub_memory_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const requestId = safe(process.env.XTERMINAL_SKILL_RUNNER_REQUEST_ID || `skill-runner-${Date.now()}`);
  const projectId = safe(process.env.XTERMINAL_SKILL_RUNNER_PROJECT_ID || '');
  const executionRole = safe(process.env.XTERMINAL_SKILL_RUNNER_EXECUTION_ROLE || 'coder');
  const agentMode = safe(process.env.XTERMINAL_SKILL_RUNNER_AGENT_MODE || '');
  const laneId = safe(process.env.XTERMINAL_SKILL_RUNNER_LANE_ID || '');
  const auditRef = safe(process.env.XTERMINAL_SKILL_RUNNER_AUDIT_REF || '');
  const skillId = safe(process.env.XTERMINAL_SKILL_RUNNER_SKILL_ID || '');
  const packageSHA256 = safe(process.env.XTERMINAL_SKILL_RUNNER_PACKAGE_SHA256 || '');
  const toolName = safe(process.env.XTERMINAL_SKILL_RUNNER_TOOL_NAME || 'skills.run.runner');
  const toolArgsHash = safe(process.env.XTERMINAL_SKILL_RUNNER_TOOL_ARGS_HASH || '');
  const riskTier = safe(process.env.XTERMINAL_SKILL_RUNNER_RISK_TIER || 'medium');
  const requiredGrantScope = safe(process.env.XTERMINAL_SKILL_RUNNER_REQUIRED_GRANT_SCOPE || 'readonly');
  const execArgv = parseExecArgv();
  const execCwd = safe(process.env.XTERMINAL_SKILL_RUNNER_EXEC_CWD || process.cwd());
  if (!skillId) throw new Error('missing_skill_id');
  if (!packageSHA256) throw new Error('missing_package_sha256');
  if (!toolArgsHash) throw new Error('missing_tool_args_hash');
  if (execArgv.length <= 0) throw new Error('approval_binding_invalid');

  const { creds, options } = await makeClientCreds();
  const memoryClient = new proto.HubMemory(addr, creds, options);
  const md = metadataFromEnv();
  const client = reqClientFromEnv(projectId);
  const contextTokens = [
    idToken(executionRole),
    idToken(agentMode),
    idToken(laneId),
  ].filter(Boolean);
  const agentInstanceId = ['x-terminal-skill-runner', ...contextTokens].join(':');
  const agentNameSuffix = [
    executionRole && `role=${executionRole}`,
    agentMode && `mode=${agentMode}`,
    laneId && `lane=${laneId}`,
    auditRef && `audit=${auditRef}`,
  ].filter(Boolean).join(' ');

  const opened = await unary(memoryClient, 'AgentSessionOpen', {
    request_id: `${requestId}:session`,
    client,
    agent_instance_id: agentInstanceId,
    agent_name: agentNameSuffix ? `X-Terminal Skill Runner (${agentNameSuffix})` : 'X-Terminal Skill Runner',
    agent_version: '1',
    gateway_provider: 'x_terminal',
  }, md);
  if (!opened?.opened || !safe(opened?.session_id)) {
    out({
      ok: false,
      source: 'hub_runtime_grpc',
      skill_id: skillId,
      package_sha256: packageSHA256,
      tool_name: toolName,
      decision: 'deny',
      deny_code: safe(opened?.deny_code || 'session_open_failed'),
      tool_request_id: '',
      grant_id: '',
      execution_id: '',
      result_json: '',
      executed_at_ms: 0,
    });
    return;
  }

  const sessionId = safe(opened.session_id);
  const requested = await unary(memoryClient, 'AgentToolRequest', {
    request_id: `${requestId}:request`,
    client,
    session_id: sessionId,
    agent_instance_id: agentInstanceId,
    tool_name: toolName,
    tool_args_hash: toolArgsHash,
    risk_tier: riskTier,
    required_grant_scope: requiredGrantScope,
    exec_argv: execArgv,
    exec_cwd: execCwd,
  }, md);
  const decision = safe(requested?.decision || 'deny');
  const toolRequestId = safe(requested?.tool_request_id || '');
  const requestDeny = safe(requested?.deny_code || '');
  if (!requested?.accepted || !toolRequestId || decision !== 'approve') {
    out({
      ok: false,
      source: 'hub_runtime_grpc',
      skill_id: skillId,
      package_sha256: packageSHA256,
      tool_name: toolName,
      decision,
      deny_code: requestDeny || (decision === 'pending' ? 'grant_pending' : 'agent_tool_request_denied'),
      tool_request_id: toolRequestId,
      grant_id: safe(requested?.grant_id || ''),
      execution_id: '',
      result_json: '',
      executed_at_ms: 0,
    });
    return;
  }

  const grantId = safe(requested?.grant_id || '');
  const executed = await unary(memoryClient, 'AgentToolExecute', {
    request_id: `${requestId}:execute`,
    client,
    session_id: sessionId,
    tool_request_id: toolRequestId,
    tool_name: toolName,
    tool_args_hash: toolArgsHash,
    grant_id: grantId,
    exec_argv: execArgv,
    exec_cwd: execCwd,
  }, md);
  const denyCode = safe(executed?.deny_code || '');
  out({
    ok: !!executed?.executed && !denyCode,
    source: 'hub_runtime_grpc',
    skill_id: skillId,
    package_sha256: packageSHA256,
    tool_name: toolName,
    decision,
    tool_request_id: toolRequestId,
    grant_id: grantId,
    execution_id: safe(executed?.execution_id || ''),
    deny_code: denyCode,
    result_json: safe(executed?.result_json || ''),
    executed_at_ms: Number(executed?.executed_at_ms || 0),
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    skill_id: safe(process.env.XTERMINAL_SKILL_RUNNER_SKILL_ID || ''),
    package_sha256: safe(process.env.XTERMINAL_SKILL_RUNNER_PACKAGE_SHA256 || ''),
    tool_name: safe(process.env.XTERMINAL_SKILL_RUNNER_TOOL_NAME || 'skills.run.runner'),
    decision: 'deny',
    deny_code: msg || 'remote_skill_runner_gate_failed',
    tool_request_id: '',
    grant_id: '',
    execution_id: '',
    result_json: '',
    executed_at_ms: 0,
    reason: msg || 'remote_skill_runner_gate_failed',
    error_code: msg || 'remote_skill_runner_gate_failed',
    error_message: msg || 'remote_skill_runner_gate_failed',
  });
  process.exit(1);
});
"""#
    }

    func remoteAgentImportStageScriptSource() -> String {
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
        if (built?.creds) return { creds: built.creds, options: built.options || {} };
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function main() {
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubSkills) throw new Error('hub_skills_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();

  const importManifestJson = safe(process.env.XTERMINAL_AGENT_IMPORT_MANIFEST_JSON || '');
  if (!importManifestJson) throw new Error('missing_agent_import_manifest');
  const findingsJson = safe(process.env.XTERMINAL_AGENT_IMPORT_FINDINGS_JSON || '');
  const scanInputJson = safe(process.env.XTERMINAL_AGENT_IMPORT_SCAN_INPUT_JSON || '');
  const requestedBy = safe(process.env.XTERMINAL_AGENT_IMPORT_REQUESTED_BY || '');
  const note = safe(process.env.XTERMINAL_AGENT_IMPORT_NOTE || '');
  const requestId = safe(process.env.XTERMINAL_AGENT_IMPORT_REQUEST_ID || '');

  const { creds, options } = await makeClientCreds();
  const skillsClient = new proto.HubSkills(addr, creds, options);
  const md = metadataFromEnv();
  if (typeof skillsClient.StageAgentImport !== 'function') {
    throw new Error('hub_agent_import_unimplemented');
  }

  const resp = await new Promise((resolve, reject) => {
    skillsClient.StageAgentImport(
      {
        client,
        request_id: requestId,
        import_manifest_json: importManifestJson,
        findings_json: findingsJson,
        scan_input_json: scanInputJson,
        requested_by: requestedBy,
        note,
        created_at_ms: Date.now(),
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
    source: 'hub_runtime_grpc',
    staging_id: safe(resp?.staging_id || ''),
    status: safe(resp?.status || ''),
    audit_ref: safe(resp?.audit_ref || ''),
    preflight_status: safe(resp?.preflight_status || ''),
    skill_id: safe(resp?.skill_id || ''),
    policy_scope: safe(resp?.policy_scope || ''),
    findings_count: Number(resp?.findings_count || 0),
    vetter_status: safe(resp?.vetter_status || ''),
    vetter_critical_count: Number(resp?.vetter_critical_count || 0),
    vetter_warn_count: Number(resp?.vetter_warn_count || 0),
    vetter_audit_ref: safe(resp?.vetter_audit_ref || ''),
    record_path: safe(resp?.record_path || ''),
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  const lower = msg.toLowerCase();
  const code = lower.includes('hub_agent_import_unimplemented') || lower.includes('unimplemented')
    ? 'hub_agent_import_unimplemented'
    : (msg || 'remote_agent_import_stage_failed');
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    reason: code,
    error_code: code,
    error_message: msg || code,
  });
  process.exit(1);
});
"""#
    }

    func remoteAgentImportRecordScriptSource() -> String {
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
        if (built?.creds) return { creds: built.creds, options: built.options || {} };
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function main() {
  const stagingId = safe(process.env.XTERMINAL_AGENT_IMPORT_STAGING_ID || '');
  if (!stagingId) throw new Error('missing_agent_staging_id');
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubSkills) throw new Error('hub_skills_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const { creds, options } = await makeClientCreds();
  const skillsClient = new proto.HubSkills(addr, creds, options);
  const md = metadataFromEnv();

  const resp = await new Promise((resolve, reject) => {
    skillsClient.GetAgentImportRecord(
      {
        client,
        staging_id: stagingId,
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
    source: 'hub_runtime_grpc',
    staging_id: safe(resp?.staging_id || ''),
    status: safe(resp?.status || ''),
    audit_ref: safe(resp?.audit_ref || ''),
    schema_version: safe(resp?.schema_version || ''),
    skill_id: safe(resp?.skill_id || ''),
    record_json: safe(resp?.record_json || ''),
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    reason: msg || 'remote_agent_import_record_failed',
    error_code: msg || 'remote_agent_import_record_failed',
    error_message: msg || 'remote_agent_import_record_failed',
  });
  process.exit(1);
});
"""#
    }

    func remoteResolvedAgentImportRecordScriptSource() -> String {
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
        if (built?.creds) return { creds: built.creds, options: built.options || {} };
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function main() {
  const selector = safe(process.env.XTERMINAL_AGENT_IMPORT_SELECTOR || '');
  const skillId = safe(process.env.XTERMINAL_AGENT_IMPORT_SKILL_ID || '');
  const projectId = safe(process.env.XTERMINAL_AGENT_IMPORT_PROJECT_ID || '');
  if (!selector) throw new Error('missing_agent_import_selector');
  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubSkills) throw new Error('hub_skills_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const { creds, options } = await makeClientCreds();
  const skillsClient = new proto.HubSkills(addr, creds, options);
  const md = metadataFromEnv();

  const resp = await new Promise((resolve, reject) => {
    skillsClient.ResolveAgentImportRecord(
      {
        client,
        selector,
        skill_id: skillId,
        project_id: projectId,
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
    source: 'hub_runtime_grpc',
    selector: safe(resp?.selector || ''),
    staging_id: safe(resp?.staging_id || ''),
    status: safe(resp?.status || ''),
    audit_ref: safe(resp?.audit_ref || ''),
    schema_version: safe(resp?.schema_version || ''),
    skill_id: safe(resp?.skill_id || ''),
    project_id: safe(resp?.project_id || ''),
    record_json: safe(resp?.record_json || ''),
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    selector: safe(process.env.XTERMINAL_AGENT_IMPORT_SELECTOR || ''),
    reason: msg || 'remote_agent_import_record_resolve_failed',
    error_code: msg || 'remote_agent_import_record_resolve_failed',
    error_message: msg || 'remote_agent_import_record_resolve_failed',
  });
  process.exit(1);
});
"""#
    }

    func remoteSkillPackageUploadScriptSource() -> String {
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
        if (built?.creds) return { creds: built.creds, options: built.options || {} };
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function main() {
  const packagePath = safe(process.env.XTERMINAL_UPLOAD_SKILL_PACKAGE_PATH || '');
  const manifestJSON = safe(process.env.XTERMINAL_UPLOAD_SKILL_MANIFEST_JSON || '');
  const sourceId = safe(process.env.XTERMINAL_UPLOAD_SKILL_SOURCE_ID || 'local:xt-import');
  const requestId = safe(process.env.XTERMINAL_UPLOAD_SKILL_REQUEST_ID || '');
  if (!packagePath) throw new Error('missing_package_path');
  if (!manifestJSON) throw new Error('missing_manifest_json');

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubSkills) throw new Error('hub_skills_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const { creds, options } = await makeClientCreds();
  const skillsClient = new proto.HubSkills(addr, creds, options);
  const md = metadataFromEnv();
  const packageBytes = fs.readFileSync(packagePath);

  const resp = await new Promise((resolve, reject) => {
    skillsClient.UploadSkillPackage(
      {
        client,
        request_id: requestId,
        source_id: sourceId,
        package_bytes: packageBytes,
        manifest_json: manifestJSON,
        created_at_ms: Date.now(),
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
    source: 'hub_runtime_grpc',
    package_sha256: safe(resp?.package_sha256 || ''),
    already_present: !!resp?.already_present,
    skill_id: safe(resp?.skill?.skill_id || ''),
    version: safe(resp?.skill?.version || ''),
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    reason: msg || 'remote_skill_package_upload_failed',
    error_code: msg || 'remote_skill_package_upload_failed',
    error_message: msg || 'remote_skill_package_upload_failed',
  });
  process.exit(1);
});
"""#
    }

    func remoteAgentImportPromoteScriptSource() -> String {
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
        if (built?.creds) return { creds: built.creds, options: built.options || {} };
      }
    } catch {}
  }
  return { creds: grpc.credentials.createInsecure(), options: {} };
}

async function main() {
  const stagingId = safe(process.env.XTERMINAL_AGENT_IMPORT_STAGING_ID || '');
  const packageSHA256 = safe(process.env.XTERMINAL_AGENT_IMPORT_PACKAGE_SHA256 || '');
  const note = safe(process.env.XTERMINAL_AGENT_IMPORT_NOTE || '');
  const requestId = safe(process.env.XTERMINAL_AGENT_IMPORT_REQUEST_ID || '');
  if (!stagingId) throw new Error('missing_agent_staging_id');
  if (!packageSHA256) throw new Error('missing_package_sha256');

  const protoPath = await resolveProtoPath();
  const proto = loadProto(protoPath);
  if (!proto?.HubSkills) throw new Error('hub_skills_missing');

  const host = safe(process.env.HUB_HOST || '127.0.0.1');
  const port = Number.parseInt(safe(process.env.HUB_PORT || '50051'), 10) || 50051;
  const addr = `${host}:${port}`;
  const client = reqClientFromEnv();
  const { creds, options } = await makeClientCreds();
  const skillsClient = new proto.HubSkills(addr, creds, options);
  const md = metadataFromEnv();

  const resp = await new Promise((resolve, reject) => {
    skillsClient.PromoteAgentImport(
      {
        client,
        request_id: requestId,
        staging_id: stagingId,
        package_sha256: packageSHA256,
        note,
        created_at_ms: Date.now(),
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
    source: 'hub_runtime_grpc',
    staging_id: safe(resp?.staging_id || ''),
    status: safe(resp?.status || ''),
    audit_ref: safe(resp?.audit_ref || ''),
    package_sha256: safe(resp?.package_sha256 || ''),
    scope: safe(resp?.scope || ''),
    skill_id: safe(resp?.skill_id || ''),
    previous_package_sha256: safe(resp?.previous_package_sha256 || ''),
    record_path: safe(resp?.record_path || ''),
  });
}

main().catch((err) => {
  const msg = safe(err?.message || err);
  out({
    ok: false,
    source: 'hub_runtime_grpc',
    reason: msg || 'remote_agent_import_promote_failed',
    error_code: msg || 'remote_agent_import_promote_failed',
    error_message: msg || 'remote_agent_import_promote_failed',
  });
  process.exit(1);
});
"""#
    }





}
