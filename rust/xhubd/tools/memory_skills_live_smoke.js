#!/usr/bin/env node
import http from 'node:http';

function parseArgs(argv) {
  const out = {
    httpBaseUrl: 'http://127.0.0.1:50151',
    timeoutMs: 5000,
    scopeKey: 'project:rust-live-cutover',
    skillId: 'rust-authority-healthcheck',
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--http-base-url':
        out.httpBaseUrl = String(next || '').trim() || out.httpBaseUrl;
        i += 1;
        break;
      case '--timeout-ms':
        out.timeoutMs = Math.max(100, Math.min(60000, Number.parseInt(String(next || ''), 10) || out.timeoutMs));
        i += 1;
        break;
      case '--scope-key':
        out.scopeKey = String(next || '').trim() || out.scopeKey;
        i += 1;
        break;
      case '--skill-id':
        out.skillId = String(next || '').trim() || out.skillId;
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
  out.httpBaseUrl = out.httpBaseUrl.replace(/\/$/, '');
  return out;
}

function usage() {
  return [
    'memory_skills_live_smoke.js',
    '',
    'Options:',
    '  --http-base-url <u>  Live xhubd HTTP base URL',
    '  --timeout-ms <n>    Request timeout, default 5000',
    '  --scope-key <s>     Skill policy scope for live smoke',
    '  --skill-id <id>     Built-in skill id, default rust-authority-healthcheck',
  ].join('\n');
}

function httpJson(method, url, body, timeoutMs, okStatuses = [200]) {
  return new Promise((resolve, reject) => {
    const payload = body === undefined ? '' : JSON.stringify(body);
    const parsed = new URL(url);
    const req = http.request({
      method,
      hostname: parsed.hostname,
      port: parsed.port,
      path: `${parsed.pathname}${parsed.search}`,
      timeout: timeoutMs,
      headers: payload ? {
        'content-type': 'application/json',
        'content-length': Buffer.byteLength(payload),
      } : {},
    }, (res) => {
      let data = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        let value = null;
        try {
          value = data ? JSON.parse(data) : {};
        } catch (error) {
          reject(new Error(`invalid JSON from ${url}: ${error.message}`));
          return;
        }
        if (!okStatuses.includes(Number(res.statusCode))) {
          reject(new Error(`unexpected HTTP ${res.statusCode} from ${url}: ${JSON.stringify(value).slice(0, 1000)}`));
          return;
        }
        resolve(value);
      });
    });
    req.on('timeout', () => req.destroy(new Error(`timeout after ${timeoutMs}ms: ${url}`)));
    req.on('error', reject);
    if (payload) req.write(payload);
    req.end();
  });
}

function assertOk(condition, message, detail = {}) {
  if (!condition) throw new Error(`${message}: ${JSON.stringify(detail).slice(0, 2000)}`);
}

function assertNoLeak(value, label) {
  const text = JSON.stringify(value);
  assertOk(!/"detail_json"\s*:/.test(text), `${label} included detail_json`);
  assertOk(!/sk-[A-Za-z0-9_-]+|api_key|Bearer\s+\S+/i.test(text), `${label} leaked secret-shaped text`);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(usage());
    return;
  }
  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
  const actor = 'rust-memory-skills-live-smoke';

  const ready = await httpJson('GET', `${args.httpBaseUrl}/ready`, undefined, args.timeoutMs);
  assertOk(ready?.ready === true, 'live daemon not ready', ready);
  assertOk(ready?.memory?.canonical_writer_in_rust === true, 'memory writer authority not active', ready?.memory || {});
  assertOk(ready?.skills?.execution_authority_in_rust === true, 'skills execution authority not active', ready?.skills || {});
  assertOk(ready?.capabilities?.memory_write_http === true, 'memory write HTTP missing', ready?.capabilities || {});
  assertOk(ready?.capabilities?.skills_execute_http === true, 'skills execute HTTP missing', ready?.capabilities || {});

  const memoryText = `Rust live memory writer verification ${stamp} keeps governed Hub memory durable and responsive.`;
  const written = await httpJson('POST', `${args.httpBaseUrl}/memory/write`, {
    request_id: `rust-live-memory-${stamp}`,
    scope: args.scopeKey,
    title: 'Rust live memory writer verification',
    text: memoryText,
    tags: ['rust-live-cutover', 'memory.write'],
    actor,
  }, args.timeoutMs);
  assertOk(written?.ok === true && written?.writer_authority_in_rust === true, 'live memory write failed', written);
  assertNoLeak(written, 'memory write');

  const secretDenied = await httpJson('POST', `${args.httpBaseUrl}/memory/write`, {
    text: 'live smoke should deny sk-rust-live-cutover-secret',
    actor,
  }, args.timeoutMs, [403]);
  assertOk(secretDenied?.deny_code === 'memory_secret_pattern_denied', 'secret memory write was not denied', secretDenied);
  assertNoLeak(secretDenied, 'secret memory write denial');

  const search = await httpJson('GET', `${args.httpBaseUrl}/memory/search?${new URLSearchParams({
    query: 'Rust live memory writer verification governed durable responsive',
    max_results: '5',
  }).toString()}`, undefined, args.timeoutMs);
  assertOk(Array.isArray(search?.results) && search.results.length >= 1, 'live memory write was not retrievable', search);
  assertNoLeak(search, 'memory search');

  const pinned = await httpJson('POST', `${args.httpBaseUrl}/skills/pin`, {
    scope_key: args.scopeKey,
    skill_id: args.skillId,
    actor,
  }, args.timeoutMs);
  assertOk(pinned?.ok === true, 'live skill pin failed', pinned);

  const granted = await httpJson('POST', `${args.httpBaseUrl}/skills/grant`, {
    scope_key: args.scopeKey,
    skill_id: args.skillId,
    capability: 'health',
    actor,
  }, args.timeoutMs);
  assertOk(granted?.ok === true, 'live skill grant failed', granted);

  const executed = await httpJson('POST', `${args.httpBaseUrl}/skills/execute`, {
    scope_key: args.scopeKey,
    skill_id: args.skillId,
    requested_capabilities: ['health'],
    request_id: `rust-live-skill-${stamp}`,
    audit_ref: 'rust-live-cutover',
    actor,
    input: { ping: true },
  }, args.timeoutMs);
  assertOk(executed?.ok === true && executed?.status === 'executed', 'live skill execution failed', executed);
  assertOk(executed?.execution_authority_in_rust === true, 'live skill execution authority not reported', executed);
  assertOk(executed?.output?.status === 'ok', 'live skill output mismatch', executed);
  assertNoLeak(executed, 'skill execute');

  const deniedExecute = await httpJson('POST', `${args.httpBaseUrl}/skills/execute`, {
    scope_key: args.scopeKey,
    skill_id: args.skillId,
    requested_capabilities: ['health'],
    actor,
    input: { token: 'sk-rust-live-cutover-secret' },
  }, args.timeoutMs, [403]);
  assertOk(deniedExecute?.deny_code === 'skill_input_secret_pattern_denied', 'secret skill input was not denied', deniedExecute);
  assertNoLeak(deniedExecute, 'secret skill execute denial');

  process.stdout.write(`${JSON.stringify({
    ok: true,
    schema_version: 'xhub.rust_hub.memory_skills_live_smoke.v1',
    command: 'memory-skills-live-smoke',
    http_base_url: args.httpBaseUrl,
    scope_key: args.scopeKey,
    skill_id: args.skillId,
    memory_writer_authority_in_rust: true,
    skills_execution_authority_in_rust: true,
    memory_write_ok: true,
    memory_secret_denied: true,
    written_memory_retrievable: true,
    skill_execute_ok: true,
    skill_secret_input_denied: true,
    detail_json_included: false,
    secret_leak: false,
  }, null, 2)}\n`);
}

main().catch((error) => {
  process.stderr.write(`[memory_skills_live_smoke] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
