#!/usr/bin/env node
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const LARGE_PROMPT_CHARS = 200001;
const LARGE_REQUEST_FILE_PADDING_BYTES = 1048576;

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function parseArgs(argv) {
  const out = {
    timeoutMs: 30000,
    port: 60800 + (process.pid % 1000),
    reportFile: '',
    keepTemp: false,
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
      case '--report-file':
        out.reportFile = String(next || '').trim();
        if (!out.reportFile) throw new Error('--report-file requires a path');
        i += 1;
        break;
      case '--keep-temp':
        out.keepTemp = true;
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
    'xt_file_ipc_runtime_adapter_candidate_smoke.js',
    '',
    'Options:',
    '  --timeout-ms <ms>    Command timeout, default 30000',
    '  --port <port>        Local xhubd HTTP port',
    '  --report-file <path> Write the JSON report to a file',
    '  --keep-temp          Keep the temporary smoke directory',
  ].join('\n');
}

function resolveXhubdBinary() {
  const packagedBin = path.join(ROOT_DIR, 'bin', 'xhubd');
  const debugBin = path.join(ROOT_DIR, 'target', 'debug', 'xhubd');
  if (fs.existsSync(packagedBin)) return packagedBin;
  const built = spawnSync('cargo', ['build', '--bin', 'xhubd'], {
    cwd: ROOT_DIR,
    encoding: 'utf8',
    maxBuffer: 1024 * 1024,
  });
  if (built.status !== 0) {
    throw new Error(`cargo build failed before runtime adapter candidate smoke: ${built.stderr}`);
  }
  return debugBin;
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
        try {
          resolve({ statusCode: res.statusCode || 0, body: JSON.parse(raw) });
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

function assertOk(condition, message, details = {}) {
  if (!condition) {
    const suffix = Object.keys(details).length ? ` ${JSON.stringify(details).slice(0, 800)}` : '';
    throw new Error(`${message}${suffix}`);
  }
}

function pidAlive(pid) {
  if (!pid) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

async function waitForHealth(baseUrl, child, output, timeoutMs) {
  const startedAt = Date.now();
  while (Date.now() - startedAt < timeoutMs) {
    if (child.exitCode !== null) {
      throw new Error(`xhubd exited before health: ${child.exitCode}\n${output.stderr.slice(-1000)}`);
    }
    try {
      const response = await httpJson('GET', `${baseUrl}/health`, undefined, 750);
      if (response.statusCode >= 200 && response.statusCode < 300) return;
    } catch {
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  }
  throw new Error(`xhubd health timeout\n${output.stderr.slice(-1000)}`);
}

async function stopChild(child) {
  if (!child || !child.pid || child.exitCode !== null) return;
  child.kill('SIGTERM');
  spawnSync('kill', ['-TERM', String(child.pid)], { encoding: 'utf8' });
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    if (child.exitCode !== null || !pidAlive(child.pid)) return;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  if (child.exitCode === null && pidAlive(child.pid)) {
    child.kill('SIGKILL');
    spawnSync('kill', ['-KILL', String(child.pid)], { encoding: 'utf8' });
  }
}

function writeRequest(baseDir, reqId, modelId, prompt) {
  fs.mkdirSync(path.join(baseDir, 'ai_requests'), { recursive: true });
  fs.mkdirSync(path.join(baseDir, 'ai_responses'), { recursive: true });
  fs.mkdirSync(path.join(baseDir, 'ai_cancels'), { recursive: true });
  fs.writeFileSync(path.join(baseDir, 'ai_requests', `req_${reqId}.json`), `${JSON.stringify({
    type: 'generate',
    req_id: reqId,
    app_id: 'x-terminal',
    task_type: 'text_generate',
    preferred_model_id: modelId,
    prompt,
    max_tokens: 8,
    temperature: 0.2,
    top_p: 0.95,
    created_at: 100.5,
    auto_load: true,
  })}\n`, 'utf8');
}

function writeRuntime(baseDir, modelId) {
  const artifact = path.join(baseDir, 'model.gguf');
  fs.writeFileSync(artifact, 'fixture', 'utf8');
  fs.writeFileSync(path.join(baseDir, 'models_state.json'), `${JSON.stringify({
    models: [{ id: modelId, backend: 'mlx', modelPath: artifact, capabilities: ['text_generate'] }],
  }, null, 2)}\n`, 'utf8');
  fs.writeFileSync(path.join(baseDir, 'ai_runtime_status.json'), `${JSON.stringify({
    providers: {
      mlx: {
        provider: 'mlx',
        ok: true,
        availableTaskKinds: ['text_generate'],
        runtimeSource: 'fixture',
        runtimeSourcePath: '/tmp/fixture-runtime',
        runtimeResolutionState: 'resolved',
        updatedAtMs: 1000,
      },
    },
  }, null, 2)}\n`, 'utf8');
}

function writeRequestAndRuntime(baseDir, reqId, modelId) {
  writeRequest(baseDir, reqId, modelId, 'runtime adapter candidate smoke');
  writeRuntime(baseDir, modelId);
}

function readJsonl(filePath) {
  return fs.readFileSync(filePath, 'utf8')
    .split('\n')
    .filter(Boolean)
    .map((line) => JSON.parse(line));
}

function resolveReportFile(reportFile) {
  if (!reportFile) return '';
  const resolved = path.resolve(process.cwd(), reportFile);
  fs.mkdirSync(path.dirname(resolved), { recursive: true });
  return resolved;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(usage());
    return;
  }

  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-xt-file-ipc-runtime-adapter-smoke-'));
  const hubRoot = path.join(tempRoot, 'hub-root');
  const ipcDir = path.join(tempRoot, 'xt-ipc');
  const modelId = 'local.adapter-smoke';
  const reqId = 'runtime_adapter_smoke';
  const cancelReqId = 'runtime_adapter_cancel_smoke';
  const existingReqId = 'runtime_adapter_existing_smoke';
  const unsupportedReqId = 'runtime_adapter_unsupported_smoke';
  const noModelReqId = 'runtime_adapter_no_model_smoke';
  const largePromptReqId = 'runtime_adapter_large_prompt_smoke';
  const largeFileReqId = 'runtime_adapter_large_file_smoke';
  const invalidJsonReqId = 'runtime_adapter_invalid_json_smoke';
  let child = null;
  let output = { stdout: '', stderr: '' };

  try {
    writeRequestAndRuntime(ipcDir, reqId, modelId);
    writeRequest(ipcDir, cancelReqId, modelId, 'runtime adapter candidate cancel smoke');
    fs.writeFileSync(path.join(ipcDir, 'ai_cancels', `cancel_${cancelReqId}.json`), '{"reason":"smoke_cancel"}\n', 'utf8');
    writeRequest(ipcDir, existingReqId, modelId, 'runtime adapter candidate existing response smoke');
    const existingResponsePath = path.join(ipcDir, 'ai_responses', `resp_${existingReqId}.jsonl`);
    const existingResponse = '{"type":"done","ok":true,"source":"existing"}\n';
    fs.writeFileSync(existingResponsePath, existingResponse, 'utf8');
    fs.writeFileSync(path.join(ipcDir, 'ai_requests', `req_${unsupportedReqId}.json`), `${JSON.stringify({
      type: 'embed',
      req_id: unsupportedReqId,
      app_id: 'x-terminal',
      task_type: 'embedding',
      preferred_model_id: modelId,
      prompt: 'unsupported runtime adapter candidate smoke',
      created_at: 100.5,
    })}\n`, 'utf8');
    const noModelIpcDir = path.join(tempRoot, 'xt-ipc-no-model');
    fs.mkdirSync(path.join(noModelIpcDir, 'ai_requests'), { recursive: true });
    fs.mkdirSync(path.join(noModelIpcDir, 'ai_responses'), { recursive: true });
    fs.mkdirSync(path.join(noModelIpcDir, 'ai_cancels'), { recursive: true });
    writeRequest(noModelIpcDir, noModelReqId, 'local.missing-model', 'runtime adapter candidate no selected model smoke');
    const largePromptIpcDir = path.join(tempRoot, 'xt-ipc-large-prompt');
    fs.mkdirSync(path.join(largePromptIpcDir, 'ai_requests'), { recursive: true });
    fs.mkdirSync(path.join(largePromptIpcDir, 'ai_responses'), { recursive: true });
    fs.mkdirSync(path.join(largePromptIpcDir, 'ai_cancels'), { recursive: true });
    writeRequest(largePromptIpcDir, largePromptReqId, modelId, 'x'.repeat(LARGE_PROMPT_CHARS));
    writeRuntime(largePromptIpcDir, modelId);
    const largeFileIpcDir = path.join(tempRoot, 'xt-ipc-large-file');
    fs.mkdirSync(path.join(largeFileIpcDir, 'ai_requests'), { recursive: true });
    fs.mkdirSync(path.join(largeFileIpcDir, 'ai_responses'), { recursive: true });
    fs.mkdirSync(path.join(largeFileIpcDir, 'ai_cancels'), { recursive: true });
    fs.writeFileSync(path.join(largeFileIpcDir, 'ai_requests', `req_${largeFileReqId}.json`), `${JSON.stringify({
      type: 'generate',
      req_id: largeFileReqId,
      app_id: 'x-terminal',
      task_type: 'text_generate',
      preferred_model_id: modelId,
      prompt: 'runtime adapter candidate oversized file smoke',
      padding: 'x'.repeat(LARGE_REQUEST_FILE_PADDING_BYTES),
      max_tokens: 8,
      created_at: 100.5,
    })}\n`, 'utf8');
    writeRuntime(largeFileIpcDir, modelId);
    const invalidJsonIpcDir = path.join(tempRoot, 'xt-ipc-invalid-json');
    fs.mkdirSync(path.join(invalidJsonIpcDir, 'ai_requests'), { recursive: true });
    fs.mkdirSync(path.join(invalidJsonIpcDir, 'ai_responses'), { recursive: true });
    fs.mkdirSync(path.join(invalidJsonIpcDir, 'ai_cancels'), { recursive: true });
    fs.writeFileSync(
      path.join(invalidJsonIpcDir, 'ai_requests', `req_${invalidJsonReqId}.json`),
      `{"type":"generate","req_id":"${invalidJsonReqId}","preferred_model_id":"${modelId}","prompt":"broken"\n`,
      'utf8',
    );
    writeRuntime(invalidJsonIpcDir, modelId);
    fs.mkdirSync(path.join(tempRoot, 'data'), { recursive: true });
    const env = {
      ...process.env,
      XHUB_RUST_HUB_ROOT: hubRoot,
      XHUB_RUST_HUB_HOST: '127.0.0.1',
      XHUB_RUST_HUB_HTTP_PORT: String(args.port),
      HUB_DB_PATH: path.join(tempRoot, 'data', 'hub.sqlite3'),
      HUB_RUNTIME_BASE_DIR: ipcDir,
      XHUB_RUST_MEMORY_DIR: path.join(tempRoot, 'memory'),
      XHUB_RUST_SKILLS_DIR: path.join(tempRoot, 'skills'),
      XHUB_RUST_XT_FILE_IPC_SHADOW: '1',
      XHUB_RUST_XT_FILE_IPC_SHADOW_APPLY: '1',
      XHUB_RUST_XT_FILE_IPC_RUNTIME_PLAN: '1',
      XHUB_RUST_XT_FILE_IPC_RUNTIME_ADAPTER_CANDIDATE: '1',
    };
    child = spawn(resolveXhubdBinary(), ['serve'], {
      cwd: ROOT_DIR,
      env,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    child.stdout.on('data', (chunk) => { output.stdout += chunk.toString(); });
    child.stderr.on('data', (chunk) => { output.stderr += chunk.toString(); });

    const baseUrl = `http://127.0.0.1:${args.port}`;
    await waitForHealth(baseUrl, child, output, args.timeoutMs);
    const ready = await httpJson('GET', `${baseUrl}/ready`, undefined, 2000);
    assertOk(ready.body?.capabilities?.xt_file_ipc_shadow_runtime_adapter_candidate_http === true, 'runtime adapter candidate capability missing');
    assertOk(ready.body?.capabilities?.xt_file_ipc_production_surface_ready !== undefined, 'production file IPC readiness missing');

    const candidate = await httpJson('POST', `${baseUrl}/xt/file-ipc-shadow/runtime-adapter-candidate`, {
      base_dir: ipcDir,
      runtime_base_dir: ipcDir,
      req_id: reqId,
      apply: true,
    }, args.timeoutMs);
    assertOk(candidate.statusCode === 200, 'runtime adapter candidate HTTP status failed', candidate);
    assertOk(candidate.body?.ok === true, 'runtime adapter candidate failed', candidate.body);
    assertOk(candidate.body?.ready === false, 'runtime adapter candidate marked ready');
    assertOk(candidate.body?.wrote === true, 'runtime adapter candidate did not write fail-closed response');
    assertOk(candidate.body?.runtime_adapter_candidate?.adapter_kind === 'local_runtime_file_ipc', 'adapter kind mismatch', candidate.body?.runtime_adapter_candidate);
    assertOk(candidate.body?.runtime_adapter_candidate?.executes_ml === false, 'ML execution unexpectedly true', candidate.body?.runtime_adapter_candidate);
    assertOk(candidate.body?.runtime_adapter_candidate?.production_file_ipc_ready === false, 'production file IPC ready unexpectedly true');
    assertOk(candidate.body?.authority?.production_authority_change === false, 'production authority changed');
    assertOk(candidate.body?.authority?.rust_executes_ml === false, 'Rust ML execution authority changed');
    assertOk(!fs.existsSync(path.join(ipcDir, 'hub_status.json')), 'hub_status.json was written');

    const responsePath = path.join(ipcDir, 'ai_responses', `resp_${reqId}.jsonl`);
    assertOk(fs.existsSync(responsePath), 'response JSONL missing');
    const events = readJsonl(responsePath);
    assertOk(events.length === 2, 'response JSONL event count mismatch', { events });
    assertOk(events[0]?.type === 'start', 'start event missing', events[0]);
    assertOk(events[1]?.type === 'done', 'done event missing', events[1]);
    assertOk(events[1]?.ok === false, 'done event was successful unexpectedly', events[1]);
    assertOk(events[1]?.reason === 'rust_runtime_adapter_candidate_not_executing', 'fail-closed reason mismatch', events[1]);
    assertOk(events[1]?.runtime_adapter_candidate === true, 'adapter candidate marker missing', events[1]);

    const canceled = await httpJson('POST', `${baseUrl}/xt/file-ipc-shadow/runtime-adapter-candidate`, {
      base_dir: ipcDir,
      runtime_base_dir: ipcDir,
      req_id: cancelReqId,
      apply: true,
    }, args.timeoutMs);
    assertOk(canceled.statusCode === 200, 'cancel adapter candidate HTTP status failed', canceled);
    assertOk(canceled.body?.ok === true, 'cancel adapter candidate failed', canceled.body);
    assertOk(canceled.body?.cancel_observed === true, 'cancel marker was not observed', canceled.body);
    assertOk(canceled.body?.runtime_adapter_candidate?.executes_ml === false, 'cancel path executed ML unexpectedly', canceled.body?.runtime_adapter_candidate);
    assertOk(canceled.body?.authority?.production_authority_change === false, 'cancel path changed production authority');
    const cancelResponsePath = path.join(ipcDir, 'ai_responses', `resp_${cancelReqId}.jsonl`);
    const cancelEvents = readJsonl(cancelResponsePath);
    assertOk(cancelEvents.length === 2, 'cancel response JSONL event count mismatch', { cancelEvents });
    assertOk(cancelEvents[1]?.ok === false, 'cancel done event was successful unexpectedly', cancelEvents[1]);
    assertOk(cancelEvents[1]?.reason === 'rust_file_ipc_cancel_observed', 'cancel reason mismatch', cancelEvents[1]);
    assertOk(cancelEvents[1]?.runtime_adapter_candidate === true, 'cancel adapter candidate marker missing', cancelEvents[1]);
    assertOk(!fs.existsSync(path.join(ipcDir, 'hub_status.json')), 'hub_status.json was written after cancel path');

    const existing = await httpJson('POST', `${baseUrl}/xt/file-ipc-shadow/runtime-adapter-candidate`, {
      base_dir: ipcDir,
      runtime_base_dir: ipcDir,
      req_id: existingReqId,
      apply: true,
    }, args.timeoutMs);
    assertOk(existing.statusCode === 409, 'existing response HTTP status failed', existing);
    assertOk(existing.body?.ok === false, 'existing response collision unexpectedly succeeded', existing.body);
    assertOk(existing.body?.wrote === false, 'existing response collision wrote unexpectedly', existing.body);
    assertOk(existing.body?.deny_code === 'response_already_exists', 'existing response deny code mismatch', existing.body);
    assertOk(existing.body?.authority?.production_authority_change === false, 'existing response collision changed production authority');
    assertOk(fs.readFileSync(existingResponsePath, 'utf8') === existingResponse, 'existing response file was modified');
    assertOk(!fs.existsSync(path.join(ipcDir, 'hub_status.json')), 'hub_status.json was written after existing response path');

    const overwrite = await httpJson('POST', `${baseUrl}/xt/file-ipc-shadow/runtime-adapter-candidate`, {
      base_dir: ipcDir,
      runtime_base_dir: ipcDir,
      req_id: existingReqId,
      apply: true,
      overwrite_response: true,
    }, args.timeoutMs);
    assertOk(overwrite.statusCode === 409, 'overwrite gate HTTP status failed', overwrite);
    assertOk(overwrite.body?.ok === false, 'overwrite gate unexpectedly succeeded', overwrite.body);
    assertOk(overwrite.body?.wrote === false, 'overwrite gate wrote unexpectedly', overwrite.body);
    assertOk(overwrite.body?.deny_code === 'response_overwrite_not_enabled', 'overwrite gate deny code mismatch', overwrite.body);
    assertOk(overwrite.body?.authority?.production_authority_change === false, 'overwrite gate changed production authority');
    assertOk(fs.readFileSync(existingResponsePath, 'utf8') === existingResponse, 'overwrite gate modified existing response');
    assertOk(!fs.existsSync(path.join(ipcDir, 'hub_status.json')), 'hub_status.json was written after overwrite gate path');

    const unsupported = await httpJson('POST', `${baseUrl}/xt/file-ipc-shadow/runtime-adapter-candidate`, {
      base_dir: ipcDir,
      runtime_base_dir: ipcDir,
      req_id: unsupportedReqId,
      apply: true,
    }, args.timeoutMs);
    assertOk(unsupported.statusCode === 409, 'unsupported request HTTP status failed', unsupported);
    assertOk(unsupported.body?.ok === false, 'unsupported request unexpectedly succeeded', unsupported.body);
    assertOk(unsupported.body?.wrote === false, 'unsupported request wrote unexpectedly', unsupported.body);
    assertOk(unsupported.body?.deny_code === 'unsupported_request_type', 'unsupported request deny code mismatch', unsupported.body);
    assertOk(unsupported.body?.error_message === 'embed', 'unsupported request type was not reported', unsupported.body);
    assertOk(unsupported.body?.authority?.production_authority_change === false, 'unsupported request changed production authority');
    assertOk(!fs.existsSync(path.join(ipcDir, 'ai_responses', `resp_${unsupportedReqId}.jsonl`)), 'unsupported request response file was written');
    assertOk(!fs.existsSync(path.join(ipcDir, 'hub_status.json')), 'hub_status.json was written after unsupported request path');

    const noModel = await httpJson('POST', `${baseUrl}/xt/file-ipc-shadow/runtime-adapter-candidate`, {
      base_dir: noModelIpcDir,
      runtime_base_dir: noModelIpcDir,
      req_id: noModelReqId,
      apply: true,
    }, args.timeoutMs);
    assertOk(noModel.statusCode === 409, 'no selected model HTTP status failed', noModel);
    assertOk(noModel.body?.ok === false, 'no selected model unexpectedly succeeded', noModel.body);
    assertOk(noModel.body?.wrote === false, 'no selected model wrote unexpectedly', noModel.body);
    assertOk(noModel.body?.deny_code === 'runtime_adapter_candidate_blocked', 'no selected model deny code mismatch', noModel.body);
    assertOk(Array.isArray(noModel.body?.runtime_adapter_candidate?.blockers), 'no selected model blockers missing', noModel.body);
    assertOk(noModel.body.runtime_adapter_candidate.blockers.includes('runtime_execution_plan_not_candidate'), 'runtime execution plan blocker missing', noModel.body.runtime_adapter_candidate);
    assertOk(noModel.body?.runtime_execution_plan?.execution_adapter_plan?.blockers?.includes('model_route_no_selected_model'), 'model route no selected model blocker missing', noModel.body?.runtime_execution_plan);
    assertOk(noModel.body?.runtime_adapter_candidate?.selected_model_id === '', 'no selected model id should be empty', noModel.body?.runtime_adapter_candidate);
    assertOk(noModel.body?.authority?.production_authority_change === false, 'no selected model changed production authority');
    assertOk(!fs.existsSync(path.join(noModelIpcDir, 'ai_responses', `resp_${noModelReqId}.jsonl`)), 'no selected model response file was written');
    assertOk(!fs.existsSync(path.join(noModelIpcDir, 'hub_status.json')), 'hub_status.json was written after no selected model path');

    const largePrompt = await httpJson('POST', `${baseUrl}/xt/file-ipc-shadow/runtime-adapter-candidate`, {
      base_dir: largePromptIpcDir,
      runtime_base_dir: largePromptIpcDir,
      req_id: largePromptReqId,
      apply: true,
    }, args.timeoutMs);
    assertOk(largePrompt.statusCode === 409, 'large prompt HTTP status failed', largePrompt);
    assertOk(largePrompt.body?.ok === false, 'large prompt unexpectedly succeeded', largePrompt.body);
    assertOk(largePrompt.body?.wrote === false, 'large prompt wrote unexpectedly', largePrompt.body);
    assertOk(largePrompt.body?.deny_code === 'request_prompt_too_large', 'large prompt deny code mismatch', largePrompt.body);
    assertOk(largePrompt.body?.error_message === String(LARGE_PROMPT_CHARS), 'large prompt size was not reported', largePrompt.body);
    assertOk(largePrompt.body?.authority?.production_authority_change === false, 'large prompt changed production authority');
    assertOk(!fs.existsSync(path.join(largePromptIpcDir, 'ai_responses', `resp_${largePromptReqId}.jsonl`)), 'large prompt response file was written');
    assertOk(!fs.existsSync(path.join(largePromptIpcDir, 'hub_status.json')), 'hub_status.json was written after large prompt path');

    const largeFile = await httpJson('POST', `${baseUrl}/xt/file-ipc-shadow/runtime-adapter-candidate`, {
      base_dir: largeFileIpcDir,
      runtime_base_dir: largeFileIpcDir,
      req_id: largeFileReqId,
      apply: true,
    }, args.timeoutMs);
    assertOk(largeFile.statusCode === 409, 'large request file HTTP status failed', largeFile);
    assertOk(largeFile.body?.ok === false, 'large request file unexpectedly succeeded', largeFile.body);
    assertOk(largeFile.body?.wrote === false, 'large request file wrote unexpectedly', largeFile.body);
    assertOk(largeFile.body?.deny_code === 'request_file_too_large', 'large request file deny code mismatch', largeFile.body);
    assertOk(Number.parseInt(largeFile.body?.error_message || '0', 10) > LARGE_REQUEST_FILE_PADDING_BYTES, 'large request file size was not reported', largeFile.body);
    assertOk(largeFile.body?.authority?.production_authority_change === false, 'large request file changed production authority');
    assertOk(!fs.existsSync(path.join(largeFileIpcDir, 'ai_responses', `resp_${largeFileReqId}.jsonl`)), 'large request file response file was written');
    assertOk(!fs.existsSync(path.join(largeFileIpcDir, 'hub_status.json')), 'hub_status.json was written after large request file path');

    const invalidJson = await httpJson('POST', `${baseUrl}/xt/file-ipc-shadow/runtime-adapter-candidate`, {
      base_dir: invalidJsonIpcDir,
      runtime_base_dir: invalidJsonIpcDir,
      req_id: invalidJsonReqId,
      apply: true,
    }, args.timeoutMs);
    assertOk(invalidJson.statusCode === 409, 'invalid request JSON HTTP status failed', invalidJson);
    assertOk(invalidJson.body?.ok === false, 'invalid request JSON unexpectedly succeeded', invalidJson.body);
    assertOk(invalidJson.body?.wrote === false, 'invalid request JSON wrote unexpectedly', invalidJson.body);
    assertOk(invalidJson.body?.deny_code === 'request_json_invalid', 'invalid request JSON deny code mismatch', invalidJson.body);
    assertOk(invalidJson.body?.authority?.production_authority_change === false, 'invalid request JSON changed production authority');
    assertOk(!fs.existsSync(path.join(invalidJsonIpcDir, 'ai_responses', `resp_${invalidJsonReqId}.jsonl`)), 'invalid request JSON response file was written');
    assertOk(!fs.existsSync(path.join(invalidJsonIpcDir, 'hub_status.json')), 'hub_status.json was written after invalid request JSON path');

    const report = {
      schema_version: 'xhub.rust_hub.xt_file_ipc_runtime_adapter_candidate_smoke.v1',
      ok: true,
      production_authority_change: false,
      temp_root: tempRoot,
      base_url: baseUrl,
      request_id: reqId,
      cancel_request_id: cancelReqId,
      existing_response_request_id: existingReqId,
      unsupported_request_id: unsupportedReqId,
      no_selected_model_request_id: noModelReqId,
      large_prompt_request_id: largePromptReqId,
      large_request_file_request_id: largeFileReqId,
      invalid_json_request_id: invalidJsonReqId,
      model_id: modelId,
      report_file: '',
      checks: {
        ready_capability: true,
        candidate_ok: true,
        response_written: true,
        response_fail_closed: true,
        cancel_observed: true,
        cancel_response_fail_closed: true,
        existing_response_preserved: true,
        overwrite_response_gate: true,
        unsupported_request_rejected: true,
        no_selected_model_blocked: true,
        large_prompt_rejected: true,
        large_request_file_rejected: true,
        invalid_request_json_rejected: true,
        hub_status_written: false,
        production_file_ipc_ready: false,
        ml_execution_in_rust: false,
      },
    };
    report.report_file = resolveReportFile(args.reportFile);
    if (report.report_file) {
      fs.writeFileSync(report.report_file, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
    }
    console.log(JSON.stringify(report, null, 2));
  } finally {
    await stopChild(child);
    if (!args.keepTemp) {
      fs.rmSync(tempRoot, { recursive: true, force: true });
    }
  }
}

main().catch((error) => {
  console.error(JSON.stringify({
    schema_version: 'xhub.rust_hub.xt_file_ipc_runtime_adapter_candidate_smoke.v1',
    ok: false,
    error_message: error?.stack || error?.message || String(error),
  }, null, 2));
  process.exit(1);
});
