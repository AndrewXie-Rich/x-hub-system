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
    port: 57000 + (process.pid % 1000),
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
    'xt_hub_contract_smoke.js',
    '',
    'Options:',
    '  --timeout-ms <ms>    Command timeout, default 30000',
    '  --port <port>        Local xhubd HTTP port',
  ].join('\n');
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

function assertNoSecretFields(value, label) {
  const raw = JSON.stringify(value);
  assertOk(!/"api_key"\s*:/.test(raw), `${label} leaked api_key field`);
  assertOk(!/"access_key"\s*:/.test(raw), `${label} leaked access_key field`);
  assertOk(!/"secret"\s*:/.test(raw), `${label} leaked secret field`);
  assertOk(!raw.includes('sk-'), `${label} leaked secret-shaped token`);
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
      throw new Error(`cargo build failed before XT Hub contract smoke: ${built.stderr}`);
    }
    bin = debugBin;
  }

  const child = spawn(bin, ['serve'], { cwd: ROOT_DIR, env, stdio: ['ignore', 'pipe', 'pipe'] });
  const output = { stdout: '', stderr: '' };
  child.stdout.on('data', (chunk) => { output.stdout += chunk.toString(); });
  child.stderr.on('data', (chunk) => { output.stderr += chunk.toString(); });
  return { child, output };
}

function httpJson(method, url, timeoutMs = 1000) {
  return new Promise((resolve, reject) => {
    const req = http.request(url, {
      method,
      timeout: timeoutMs,
      headers: { accept: 'application/json' },
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
      await httpJson('GET', `${baseUrl}/health`, 750);
      return;
    } catch {
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  }
  throw new Error(`xhubd health timeout\nstdout=${safeTail(output.stdout)}\nstderr=${safeTail(output.stderr)}`);
}

function assertContract(contract, label) {
  assertOk(contract?.schema_version === 'xhub.rust_hub.xt_contract.v1', `${label} schema mismatch`, contract);
  assertOk(contract?.ok === true, `${label} did not report ok`, contract);
  assertOk(contract?.hub_product?.kernel === 'rust_core', `${label} kernel mismatch`, contract?.hub_product || {});
  assertOk(contract?.xt_update_rule?.must_read_contract_first === true, `${label} missing XT update rule`, contract?.xt_update_rule || {});
  assertOk(contract?.xt_update_rule?.must_not_recreate_hub_authority_locally === true, `${label} missing authority boundary`, contract?.xt_update_rule || {});
  assertOk(contract?.transport_security?.secret_fields_included === false, `${label} exposed secret fields`, contract?.transport_security || {});

  const capabilities = contract.capabilities || {};
  assertOk(capabilities.remote_entry?.supports_no_domain_users === true, `${label} missing no-domain remote entry support`, capabilities.remote_entry || {});
  assertOk(capabilities.remote_entry?.requires_mtls === true, `${label} remote entry must require mTLS`, capabilities.remote_entry || {});
  assertOk(capabilities.memory?.canonical_writer === 'hub_only', `${label} memory canonical writer boundary drifted`, capabilities.memory || {});
  assertOk(capabilities.memory?.durable_truth_in_xt === false, `${label} XT became durable memory truth`, capabilities.memory || {});
  assertOk(capabilities.models?.xt_must_not_select_paid_provider_directly === true, `${label} model route boundary drifted`, capabilities.models || {});
  assertOk(capabilities.provider_route?.secret_fields_included === false, `${label} provider route leaked secret posture`, capabilities.provider_route || {});
  assertOk(capabilities.skills?.authority === 'hub_policy_gate', `${label} skills authority drifted`, capabilities.skills || {});
  assertOk(capabilities.skills?.lease_required === true, `${label} skills lease boundary missing`, capabilities.skills || {});
  assertOk(capabilities.skills?.lease_source_endpoint === '/skills/preflight', `${label} skills preflight lease endpoint drifted`, capabilities.skills || {});
  assertOk(capabilities.skills?.third_party_code_in_hub_trust_root === false, `${label} Hub trust-root skill execution drifted`, capabilities.skills || {});
  assertOk(capabilities.skills?.package_hash_pin_required === true, `${label} skills package hash pin missing`, capabilities.skills || {});
  assertOk(capabilities.grants?.natural_language_direct_grant === false, `${label} grant boundary drifted`, capabilities.grants || {});
  assertOk(capabilities.audit?.fallback_policy === 'do_not_synthesize_audit_refs', `${label} audit fallback drifted`, capabilities.audit || {});
  assertNoSecretFields(contract, label);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(usage());
    return;
  }

  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-xt-contract-smoke-'));
  const memoryDir = path.join(tempRoot, 'memory');
  const runtimeDir = path.join(tempRoot, 'runtime');
  const skillsDir = path.join(tempRoot, 'skills');
  const dbPath = path.join(tempRoot, 'data', 'hub.sqlite3');
  const baseUrl = `http://127.0.0.1:${args.port}`;
  let child;

  try {
    const started = startXhubd({
      port: args.port,
      dbPath,
      runtimeDir,
      memoryDir,
      skillsDir,
    });
    child = started.child;
    await waitForHealth(baseUrl, child, started.output, args.timeoutMs);

    const ready = await httpJson('GET', `${baseUrl}/ready`, 1500);
    assertOk(ready?.capabilities?.xt_hub_contract_http === true, 'readiness did not expose xt_hub_contract_http', ready?.capabilities || {});
    assertOk(ready?.capabilities?.remote_entry_candidates_http === true, 'readiness did not expose remote_entry_candidates_http', ready?.capabilities || {});

    const contract = await httpJson('GET', `${baseUrl}/xt/hub-contract`, 1500);
    assertContract(contract, '/xt/hub-contract');

    const aliasContract = await httpJson('GET', `${baseUrl}/xt/contract`, 1500);
    assertContract(aliasContract, '/xt/contract');

    const legacyAliasContract = await httpJson('GET', `${baseUrl}/contract/xt`, 1500);
    assertContract(legacyAliasContract, '/contract/xt');

    const result = {
      ok: true,
      schema_version: 'xhub.rust_hub.xt_contract_smoke.v1',
      command: 'xt-hub-contract-smoke',
      http_base_url: baseUrl,
      contract_schema: contract.schema_version,
      aliases_checked: ['/xt/hub-contract', '/xt/contract', '/contract/xt'],
      memory_canonical_writer: contract.capabilities.memory.canonical_writer,
      skills_authority: contract.capabilities.skills.authority,
      skills_lease_required: contract.capabilities.skills.lease_required,
      remote_entry_no_domain_supported: contract.capabilities.remote_entry.supports_no_domain_users,
      secret_leak: false,
    };
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  } finally {
    if (child && child.exitCode === null) {
      child.kill('SIGTERM');
      spawnSync('kill', ['-TERM', String(child.pid)], { encoding: 'utf8' });
      await waitForExit(child, 5000);
    }
    try {
      fs.rmSync(tempRoot, { recursive: true, force: true });
    } catch {}
  }
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

try {
  await main();
} catch (error) {
  process.stderr.write(`[xt_hub_contract_smoke] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
}
