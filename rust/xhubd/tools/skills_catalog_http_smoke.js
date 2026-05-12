#!/usr/bin/env node
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function parseArgs(argv) {
  const out = {
    timeoutMs: 30000,
    port: 59000 + (process.pid % 1000),
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--timeout-ms':
        out.timeoutMs = parseIntInRange(next, out.timeoutMs, 1000, 120000);
        i += 1;
        break;
      case '--port':
        out.port = parseIntInRange(next, out.port, 1024, 65535);
        i += 1;
        break;
      case '--help':
      case '-h':
        out.help = true;
        break;
      default:
        throw new Error(`unknown argument: ${arg}`);
    }
  }
  return out;
}

function usage() {
  return [
    'skills_catalog_http_smoke.js',
    '',
    'Options:',
    '  --timeout-ms <ms>    Command timeout, default 30000',
    '  --port <port>        Local xhubd HTTP port',
  ].join('\n');
}

function safeString(value) {
  return String(value ?? '').trim();
}

function safeTail(value) {
  return String(value || '').split(/\r?\n/).slice(-25).join('\n');
}

function assertOk(condition, message, details = {}) {
  if (!condition) {
    const suffix = Object.keys(details).length ? ` ${JSON.stringify(details).slice(0, 600)}` : '';
    throw new Error(`${message}${suffix}`);
  }
}

function assertNoSecretLeak(value, label) {
  const raw = JSON.stringify(value);
  assertOk(!raw.includes('sk-skill-http-secret-that-must-not-leak'), `${label} leaked secret value`);
  assertOk(!/"api_key"\s*:/.test(raw), `${label} leaked api_key field`);
}

function writeValidSkill(skillsDir) {
  const skill = path.join(skillsDir, 'memory-core');
  fs.mkdirSync(skill, { recursive: true });
  fs.writeFileSync(
    path.join(skill, 'SKILL.md'),
    '# Memory Core\nUse memory and model context through Hub policy gates. No execution authority here.\n',
    'utf8'
  );
}

function writeLeakySkill(skillsDir) {
  const skill = path.join(skillsDir, 'leaky');
  fs.mkdirSync(skill, { recursive: true });
  fs.writeFileSync(
    path.join(skill, 'skill.json'),
    `${JSON.stringify({
      id: 'leaky',
      name: 'Leaky',
      capabilities: ['memory'],
      api_key: 'sk-skill-http-secret-that-must-not-leak',
    }, null, 2)}\n`,
    'utf8'
  );
}

function spawnSyncChecked(command, args, options = {}) {
  const result = spawnSync(command, args, {
    encoding: 'utf8',
    maxBuffer: 1024 * 1024,
    ...options,
  });
  return {
    status: Number(result.status ?? 1),
    stdout: String(result.stdout || ''),
    stderr: String(result.stderr || result.error?.message || ''),
  };
}

function startXhubd({ port, dbPath, runtimeDir, memoryDir, skillsDir }) {
  fs.mkdirSync(path.dirname(dbPath), { recursive: true });
  fs.mkdirSync(runtimeDir, { recursive: true });
  fs.mkdirSync(memoryDir, { recursive: true });
  fs.mkdirSync(skillsDir, { recursive: true });

  const env = {
    ...process.env,
    XHUB_RUST_HUB_ROOT: ROOT_DIR,
    XHUB_RUST_HUB_HOST: '127.0.0.1',
    XHUB_RUST_HUB_HTTP_PORT: String(port),
    HUB_DB_PATH: dbPath,
    HUB_RUNTIME_BASE_DIR: runtimeDir,
    XHUB_RUST_MEMORY_DIR: memoryDir,
    XHUB_RUST_SKILLS_DIR: skillsDir,
  };
  const packagedBin = path.join(ROOT_DIR, 'bin', 'xhubd');
  const debugBin = path.join(ROOT_DIR, 'target', 'debug', 'xhubd');
  let bin = '';
  if (fs.existsSync(packagedBin)) {
    bin = packagedBin;
  } else {
    const built = spawnSyncChecked('cargo', ['build', '--bin', 'xhubd'], { cwd: ROOT_DIR });
    if (built.status !== 0) {
      throw new Error(`cargo build failed before skills HTTP smoke: ${built.stderr}`);
    }
    bin = debugBin;
  }

  const child = spawn(bin, ['serve'], { cwd: ROOT_DIR, env, stdio: ['ignore', 'pipe', 'pipe'] });
  const output = { stdout: '', stderr: '' };
  child.stdout.on('data', (chunk) => { output.stdout += chunk.toString(); });
  child.stderr.on('data', (chunk) => { output.stderr += chunk.toString(); });
  return { child, output };
}

function httpJson(method, url, body = undefined, timeoutMs = 1000) {
  return new Promise((resolve, reject) => {
    const data = body === undefined ? undefined : Buffer.from(JSON.stringify(body));
    const req = http.request(url, {
      method,
      timeout: timeoutMs,
      headers: {
        accept: 'application/json',
        ...(data ? { 'content-type': 'application/json', 'content-length': String(data.length) } : {}),
      },
    }, (res) => {
      let raw = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => { raw += chunk; });
      res.on('end', () => {
        if ((res.statusCode || 0) < 200 || (res.statusCode || 0) >= 300) {
          reject(new Error(`http_status:${res.statusCode}:${raw.slice(0, 400)}`));
          return;
        }
        try {
          resolve(JSON.parse(raw));
        } catch (error) {
          reject(new Error(`invalid_json:${error.message}:${raw.slice(0, 400)}`));
        }
      });
    });
    req.on('timeout', () => req.destroy(new Error('http_timeout')));
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
  });
}

async function waitForHealth(baseUrl, child, output, timeoutMs) {
  const startedAt = Date.now();
  while (Date.now() - startedAt < timeoutMs) {
    if (child.exitCode !== null) {
      throw new Error(`xhubd exited before health was ready: ${child.exitCode}\nstdout=${safeTail(output.stdout)}\nstderr=${safeTail(output.stderr)}`);
    }
    try {
      await httpJson('GET', `${baseUrl}/health`, undefined, 750);
      return;
    } catch {
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  }
  throw new Error(`xhubd health timeout\nstdout=${safeTail(output.stdout)}\nstderr=${safeTail(output.stderr)}`);
}

async function stopChild(child) {
  if (!child || !child.pid || child.exitCode !== null) return;
  child.kill('SIGTERM');
  spawnSync('kill', ['-TERM', String(child.pid)], { encoding: 'utf8' });
  await waitForExit(child, 5000);
}

async function waitForExit(child, timeoutMs) {
  if (!child || !child.pid || child.exitCode !== null) return;
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (child.exitCode !== null || !pidAlive(child.pid)) return;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  if (child.exitCode === null && pidAlive(child.pid)) {
    child.kill('SIGKILL');
    spawnSync('kill', ['-KILL', String(child.pid)], { encoding: 'utf8' });
    for (let i = 0; i < 50; i += 1) {
      if (child.exitCode !== null || !pidAlive(child.pid)) return;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  }
}

function pidAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(usage());
    return;
  }

  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-skills-http-smoke-'));
  const runtimeDir = path.join(tempRoot, 'runtime');
  const memoryDir = path.join(tempRoot, 'memory');
  const skillsDir = path.join(tempRoot, 'skills');
  const leakySkillsDir = path.join(tempRoot, 'leaky-skills');
  const dbPath = path.join(tempRoot, 'data', 'hub.sqlite3');
  const baseUrl = `http://127.0.0.1:${args.port}`;
  let child;

  try {
    fs.mkdirSync(memoryDir, { recursive: true });
    fs.mkdirSync(skillsDir, { recursive: true });
    fs.mkdirSync(leakySkillsDir, { recursive: true });
    writeValidSkill(skillsDir);
    writeValidSkill(leakySkillsDir);
    writeLeakySkill(leakySkillsDir);

    const started = startXhubd({
      port: args.port,
      dbPath,
      runtimeDir,
      memoryDir,
      skillsDir,
    });
    child = started.child;
    await waitForHealth(baseUrl, child, started.output, args.timeoutMs);

    const ready = await httpJson('GET', `${baseUrl}/ready`, undefined, 1500);
    assertOk(ready?.capabilities?.skills_catalog_http === true, 'daemon readiness did not expose skills_catalog_http', ready);
    assertOk(ready?.skills?.execution_authority_in_rust === false, 'daemon reported Rust skill execution authority', ready?.skills || {});
    assertOk(ready?.skills?.hub_executes_third_party_code === false, 'daemon reported third-party skill execution', ready?.skills || {});
    assertOk(ready?.skills?.catalog_shadow_http === true, 'daemon did not expose skills catalog shadow HTTP', ready?.skills || {});
    assertOk(ready?.capabilities?.skills_audit_http === true, 'daemon readiness did not expose skills_audit_http', ready);
    assertOk(ready?.capabilities?.skills_policy_events_http === true, 'daemon readiness did not expose skills_policy_events_http', ready);
    assertOk(ready?.capabilities?.skills_policy_events_prune_http === true, 'daemon readiness did not expose skills_policy_events_prune_http', ready);
    assertOk(ready?.capabilities?.skills_policy_store_readiness_http === true, 'daemon readiness did not expose skills_policy_store_readiness_http', ready);

    const readiness = await httpJson('GET', `${baseUrl}/skills/readiness`, undefined, 1500);
    assertOk(readiness?.readiness?.ready === true, 'skills readiness was not ready', readiness);
    assertOk(readiness?.readiness?.execution_authority_in_rust === false, 'skills readiness reported Rust execution authority', readiness);
    assertOk(readiness?.readiness?.requires_pin_or_grant === true, 'skills readiness did not require pin/grant', readiness);

    const catalog = await httpJson('GET', `${baseUrl}/skills/catalog`, undefined, 1500);
    assertOk(catalog?.catalog?.schema_version === 'xhub.skills_catalog.v1', 'skills catalog schema mismatch', catalog);
    assertOk(Array.isArray(catalog?.catalog?.entries) && catalog.catalog.entries.length === 1, 'skills catalog count mismatch', catalog);
    assertOk(catalog.catalog.entries[0]?.status === 'accepted', 'valid skill was not accepted', catalog.catalog.entries[0] || {});

    const deniedPreflight = await httpJson('POST', `${baseUrl}/skills/preflight`, {
      scope_key: 'project:skills-http-smoke',
      skill_id: 'memory-core',
      requested_capabilities: ['memory'],
      request_id: 'skills-preflight-http-deny',
    }, 1500);
    assertOk(deniedPreflight?.preflight?.allowed === false, 'HTTP preflight without pin/grant did not deny', deniedPreflight);
    assertOk(JSON.stringify(deniedPreflight).includes('skill_pin_required'), 'HTTP denied preflight missing pin reason', deniedPreflight);
    assertOk(JSON.stringify(deniedPreflight).includes('capability_grant_required'), 'HTTP denied preflight missing grant reason', deniedPreflight);
    assertOk(deniedPreflight?.preflight?.execution_authority_in_rust === false, 'HTTP denied preflight reported execution authority', deniedPreflight);

    const pinned = await httpJson('POST', `${baseUrl}/skills/pin`, {
      scope_key: 'project:skills-http-smoke',
      skill_id: 'memory-core',
      actor: 'skills-http-smoke',
    }, 1500);
    assertOk(pinned?.ok === true && pinned?.execution_authority_in_rust === false, 'HTTP durable pin failed', pinned);

    const granted = await httpJson('POST', `${baseUrl}/skills/grant`, {
      scope_key: 'project:skills-http-smoke',
      skill_id: 'memory-core',
      capability: 'memory',
      actor: 'skills-http-smoke',
    }, 1500);
    assertOk(granted?.ok === true && granted?.execution_authority_in_rust === false, 'HTTP durable grant failed', granted);

    const policyParams = new URLSearchParams({
      scope_key: 'project:skills-http-smoke',
      skill_id: 'memory-core',
    });
    const policy = await httpJson('GET', `${baseUrl}/skills/policy?${policyParams.toString()}`, undefined, 1500);
    assertOk(policy?.policy?.pinned === true, 'HTTP durable policy did not report pinned skill', policy);
    assertOk(Array.isArray(policy?.policy?.granted_capabilities) && policy.policy.granted_capabilities.includes('memory'), 'HTTP durable policy did not report grant', policy);

    const allowedPreflight = await httpJson('POST', `${baseUrl}/skills/preflight`, {
      scope_key: 'project:skills-http-smoke',
      skill_id: 'memory-core',
      requested_capabilities: ['memory'],
      request_id: 'skills-preflight-http-allow',
      audit_ref: 'skills-http-smoke',
    }, 1500);
    assertOk(allowedPreflight?.preflight?.schema_version === 'xhub.skills_preflight.v1', 'HTTP preflight schema mismatch', allowedPreflight);
    assertOk(allowedPreflight?.preflight?.allowed === true, 'HTTP preflight with pin/grant did not allow', allowedPreflight);
    assertOk(allowedPreflight?.preflight?.audit_event?.schema_version === 'xhub.skills_preflight.audit.v1', 'HTTP preflight audit schema mismatch', allowedPreflight);
    assertOk(allowedPreflight?.preflight?.execution_authority_in_rust === false, 'HTTP allowed preflight reported execution authority', allowedPreflight);

    const auditParams = new URLSearchParams({
      scope_key: 'project:skills-http-smoke',
      skill_id: 'memory-core',
      limit: '10',
    });
    const audit = await httpJson('GET', `${baseUrl}/skills/audit?${auditParams.toString()}`, undefined, 1500);
    assertOk(audit?.audit?.schema_version === 'xhub.skills_preflight_audit_summary.v1', 'HTTP audit summary schema mismatch', audit);
    assertOk(Number(audit?.audit?.total || 0) === 2, 'HTTP audit summary total mismatch', audit);
    assertOk(Number(audit?.audit?.allowed || 0) === 1, 'HTTP audit summary allowed mismatch', audit);
    assertOk(Number(audit?.audit?.denied || 0) === 1, 'HTTP audit summary denied mismatch', audit);
    assertOk(audit?.audit?.detail_json_included === false, 'HTTP audit summary exposed detail json', audit);
    assertOk(!/"detail_json"\s*:/.test(JSON.stringify(audit)), 'HTTP audit summary leaked detail_json field', audit);

    const pruned = await httpJson('POST', `${baseUrl}/skills/audit-prune`, {
      max_rows: 1,
    }, 1500);
    assertOk(Number(pruned?.audit_prune?.deleted_rows || 0) >= 1, 'HTTP audit prune did not delete old rows', pruned);
    assertOk(Number(pruned?.audit_prune?.remaining_rows || 0) === 1, 'HTTP audit prune remaining count mismatch', pruned);

    const revokedGrant = await httpJson('POST', `${baseUrl}/skills/revoke-grant`, {
      scope_key: 'project:skills-http-smoke',
      skill_id: 'memory-core',
      capability: 'memory',
      actor: 'skills-http-smoke',
    }, 1500);
    assertOk(revokedGrant?.ok === true && Number(revokedGrant?.revoked_rows || 0) === 1, 'HTTP durable grant revoke failed', revokedGrant);

    const unpinned = await httpJson('POST', `${baseUrl}/skills/unpin`, {
      scope_key: 'project:skills-http-smoke',
      skill_id: 'memory-core',
      actor: 'skills-http-smoke',
    }, 1500);
    assertOk(unpinned?.ok === true && Number(unpinned?.revoked_rows || 0) === 1, 'HTTP durable pin revoke failed', unpinned);

    const revokedPolicy = await httpJson('GET', `${baseUrl}/skills/policy?${policyParams.toString()}`, undefined, 1500);
    assertOk(revokedPolicy?.policy?.pinned === false, 'HTTP revoked policy still reported pinned skill', revokedPolicy);
    assertOk(Array.isArray(revokedPolicy?.policy?.granted_capabilities) && revokedPolicy.policy.granted_capabilities.length === 0, 'HTTP revoked policy still reported grants', revokedPolicy);

    const revokedPreflight = await httpJson('POST', `${baseUrl}/skills/preflight`, {
      scope_key: 'project:skills-http-smoke',
      skill_id: 'memory-core',
      requested_capabilities: ['memory'],
      request_id: 'skills-preflight-http-revoked',
    }, 1500);
    assertOk(revokedPreflight?.preflight?.allowed === false, 'HTTP preflight after revoke did not deny', revokedPreflight);
    assertOk(JSON.stringify(revokedPreflight).includes('skill_pin_required'), 'HTTP revoked preflight missing pin reason', revokedPreflight);
    assertOk(JSON.stringify(revokedPreflight).includes('capability_grant_required'), 'HTTP revoked preflight missing grant reason', revokedPreflight);

    const policyEventsParams = new URLSearchParams({
      scope_key: 'project:skills-http-smoke',
      skill_id: 'memory-core',
      limit: '10',
    });
    const policyEvents = await httpJson('GET', `${baseUrl}/skills/policy-events?${policyEventsParams.toString()}`, undefined, 1500);
    assertOk(policyEvents?.policy_events?.schema_version === 'xhub.skills_policy_events.v1', 'HTTP policy events schema mismatch', policyEvents);
    assertOk(Number(policyEvents?.policy_events?.total || 0) === 4, 'HTTP policy event total mismatch', policyEvents);
    assertOk(policyEvents?.policy_events?.detail_json_included === false, 'HTTP policy events exposed detail json', policyEvents);
    assertOk(!/"detail_json"\s*:/.test(JSON.stringify(policyEvents)), 'HTTP policy events leaked detail_json field', policyEvents);
    const operations = new Set((policyEvents?.policy_events?.rows || []).map((row) => row.operation));
    for (const operation of ['pin', 'grant', 'revoke_grant', 'unpin']) {
      assertOk(operations.has(operation), `HTTP policy events missing ${operation}`, policyEvents);
    }

    const policyEventsPruned = await httpJson('POST', `${baseUrl}/skills/policy-events-prune`, {
      max_rows: 2,
    }, 1500);
    assertOk(policyEventsPruned?.policy_events_prune?.schema_version === 'xhub.skills_policy_events_prune.v1', 'HTTP policy events prune schema mismatch', policyEventsPruned);
    assertOk(Number(policyEventsPruned?.policy_events_prune?.deleted_rows || 0) >= 2, 'HTTP policy events prune did not delete old rows', policyEventsPruned);
    assertOk(Number(policyEventsPruned?.policy_events_prune?.remaining_rows || 0) === 2, 'HTTP policy events prune remaining count mismatch', policyEventsPruned);
    assertOk(!/"detail_json"\s*:/.test(JSON.stringify(policyEventsPruned)), 'HTTP policy events prune leaked detail_json field', policyEventsPruned);

    const policyReadinessParams = new URLSearchParams({
      max_preflight_audit_rows: '10',
      max_policy_event_rows: '10',
    });
    const policyReadiness = await httpJson('GET', `${baseUrl}/skills/policy-readiness?${policyReadinessParams.toString()}`, undefined, 1500);
    assertOk(policyReadiness?.policy_readiness?.schema_version === 'xhub.skills_policy_store_readiness.v1', 'HTTP policy readiness schema mismatch', policyReadiness);
    assertOk(policyReadiness?.policy_readiness?.ready === true, 'HTTP policy readiness was not ready', policyReadiness);
    assertOk(Number(policyReadiness?.policy_readiness?.preflight_audit_count || 0) === 2, 'HTTP policy readiness preflight audit count mismatch', policyReadiness);
    assertOk(Number(policyReadiness?.policy_readiness?.policy_event_count || 0) === 2, 'HTTP policy readiness event count mismatch', policyReadiness);
    assertOk(policyReadiness?.policy_readiness?.execution_authority_in_rust === false, 'HTTP policy readiness reported execution authority', policyReadiness);
    assertOk(!/"detail_json"\s*:/.test(JSON.stringify(policyReadiness)), 'HTTP policy readiness leaked detail_json field', policyReadiness);

    const leakyParams = new URLSearchParams({ skills_dir: leakySkillsDir });
    const blocked = await httpJson('GET', `${baseUrl}/skills/catalog?${leakyParams.toString()}`, undefined, 1500);
    assertOk(Number(blocked?.catalog?.blocked_skill_count || 0) === 1, 'leaky skill was not blocked', blocked);
    assertOk(JSON.stringify(blocked).includes('manifest_secret_pattern_denied'), 'blocked catalog missing deny code', blocked);
    assertNoSecretLeak(blocked, 'blocked skills catalog');

    process.stdout.write(`${JSON.stringify({
      ok: true,
      schema_version: 'xhub.rust_hub.skills_catalog_http_smoke.v1',
      command: 'skills-catalog-http-smoke',
      http_base_url: baseUrl,
      readiness_ready: readiness.readiness.ready,
      accepted_skill_count: catalog.catalog.accepted_skill_count,
      blocked_skill_count: blocked.catalog.blocked_skill_count,
      execution_authority_in_rust: false,
      hub_executes_third_party_code: false,
      requires_pin_or_grant: true,
      secret_manifest_denied: true,
      preflight_denied_without_pin_or_grant: true,
      durable_pin_grant_recorded: true,
      preflight_allowed_with_durable_pin_and_grant: true,
      audit_summary_recorded: true,
      audit_prune_bounded: true,
      durable_pin_grant_revoked: true,
      preflight_denied_after_revoke: true,
      policy_events_recorded: true,
      policy_events_prune_bounded: true,
      policy_store_readiness_ready: true,
      secret_leak: false,
    }, null, 2)}\n`);
  } finally {
    await stopChild(child);
    try {
      fs.rmSync(tempRoot, { recursive: true, force: true });
    } catch {}
  }
}

try {
  await main();
} catch (error) {
  process.stderr.write(`[skills_catalog_http_smoke] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
}
