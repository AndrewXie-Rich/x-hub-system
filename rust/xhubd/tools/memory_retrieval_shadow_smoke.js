#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const RUNNER = path.join(SCRIPT_DIR, 'run_rust_hub.command');

function safeString(value) {
  return String(value ?? '').trim();
}

function runRust(args) {
  const result = spawnSync('bash', [RUNNER, ...args], {
    cwd: ROOT_DIR,
    encoding: 'utf8',
    maxBuffer: 1024 * 1024,
  });
  const stdout = safeString(result.stdout);
  let parsed = null;
  try {
    parsed = JSON.parse(stdout);
  } catch (error) {
    throw new Error(`Rust Hub command did not emit JSON: status=${result.status} args=${args.join(' ')} stdout=${stdout.slice(0, 400)} stderr=${safeString(result.stderr).slice(0, 400)} parse=${error.message}`);
  }
  if (result.status !== 0) {
    throw new Error(`Rust Hub command failed: status=${result.status} args=${args.join(' ')} parsed=${JSON.stringify(parsed)}`);
  }
  return parsed;
}

function assertOk(condition, message, details = {}) {
  if (!condition) {
    const suffix = Object.keys(details).length ? ` ${JSON.stringify(details)}` : '';
    throw new Error(`${message}${suffix}`);
  }
}

function main() {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-memory-shadow-smoke-'));
  const memoryDir = path.join(tempRoot, 'memory');
  fs.mkdirSync(path.join(memoryDir, 'project'), { recursive: true });
  fs.mkdirSync(path.join(memoryDir, 'personal'), { recursive: true });
  fs.writeFileSync(
    path.join(memoryDir, 'project', 'capsule.md'),
    'Use governed Rust Hub memory retrieval for project assembly. Keep supervisor assembly slot based.\n',
    'utf8'
  );
  fs.writeFileSync(
    path.join(memoryDir, 'personal', 'capsule.md'),
    'Personal preference for governed retrieval should not appear in project_code mode.\n',
    'utf8'
  );
  fs.writeFileSync(
    path.join(memoryDir, 'project', 'runtime.json'),
    `${JSON.stringify({
      summary: 'governed retrieval runtime truth',
      detail: 'Rust memory retrieval should preserve explainable source refs.',
      api_key: 'sk-secret-value-that-must-not-leak',
    }, null, 2)}\n`,
    'utf8'
  );

  try {
    const readiness = runRust(['memory', 'readiness', '--memory-dir', memoryDir]);
    assertOk(readiness?.readiness?.ready === true, 'memory readiness was not ready', readiness);
    assertOk(Number(readiness?.readiness?.indexed_document_count || 0) >= 3, 'memory readiness did not index expected docs', readiness);

    const search = runRust([
      'memory',
      'search',
      '--memory-dir',
      memoryDir,
      '--request-id',
      'memory-shadow-smoke-1',
      '--query',
      'governed retrieval project assembly',
      '--max-results',
      '5',
      '--max-snippet-chars',
      '240',
    ]);
    assertOk(search.schema_version === 'xt.memory_retrieval_result.v1', 'search schema mismatch', search);
    assertOk(search.source === 'rust_hub_memory_shadow_v1', 'search source mismatch', search);
    assertOk(Array.isArray(search.results) && search.results.length >= 1, 'search returned no results', search);
    const text = JSON.stringify(search);
    assertOk(!text.includes('Personal preference'), 'project_code search leaked personal capsule');
    assertOk(!text.includes('sk-secret-value-that-must-not-leak'), 'search leaked secret value');

    const ref = safeString(search.results[0]?.ref);
    assertOk(ref.startsWith('memory://rust/local/'), 'search did not return a Rust memory ref', search.results[0] || {});
    const byRef = runRust([
      'memory',
      'retrieve',
      '--memory-dir',
      memoryDir,
      '--retrieval-kind',
      'get_ref',
      '--explicit-refs',
      ref,
      '--max-results',
      '1',
    ]);
    assertOk(Array.isArray(byRef.results) && byRef.results.length === 1, 'get_ref did not return exactly one result', byRef);
    assertOk(byRef.results[0]?.ref === ref, 'get_ref returned a different ref', byRef);

    const denied = runRust([
      'memory',
      'search',
      '--memory-dir',
      memoryDir,
      '--query',
      'show api key',
    ]);
    assertOk(denied.status === 'denied', 'secret query was not denied', denied);
    assertOk(denied.deny_code === 'query_secret_pattern_denied', 'secret query deny_code mismatch', denied);

    process.stdout.write(`${JSON.stringify({
      ok: true,
      schema_version: 'xhub.rust_hub.memory_retrieval_shadow_smoke.v1',
      command: 'memory-retrieval-shadow-smoke',
      readiness_ready: readiness.readiness.ready,
      indexed_document_count: readiness.readiness.indexed_document_count,
      search_result_count: search.results.length,
      first_ref: ref,
      get_ref_ok: true,
      project_code_personal_leak: false,
      secret_leak: false,
      secret_query_denied: true,
    }, null, 2)}\n`);
  } finally {
    try {
      fs.rmSync(tempRoot, { recursive: true, force: true });
    } catch {}
  }
}

try {
  main();
} catch (error) {
  process.stderr.write(`[memory_retrieval_shadow_smoke] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
}
