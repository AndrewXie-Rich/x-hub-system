import assert from 'node:assert/strict';

import {
  createRustLocalMlExecutionBridge,
  normalizeRustLocalMlExecutionResult,
  resolveRustLocalMlExecutionConfig,
} from './rust_local_ml_execution_bridge.js';

async function run(name, fn) {
  try {
    await fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

await run('Rust local ML execution is disabled by default', () => {
  const config = resolveRustLocalMlExecutionConfig({});
  assert.equal(config.enabled, false);
  assert.equal(config.fallbackOnError, false);
  assert.equal(config.httpBaseUrl, 'http://127.0.0.1:50151');
});

await run('Rust local ML execution bridge posts run-local-task to xhubd', async () => {
  const calls = [];
  const bridge = createRustLocalMlExecutionBridge({
    env: {
      XHUB_RUST_ML_EXECUTION_AUTHORITY: '1',
      XHUB_RUST_HUB_HTTP_BASE_URL: 'http://127.0.0.1:55151',
      XHUB_RUST_ML_EXECUTION_TIMEOUT_MS: '12345',
    },
    httpPostJsonImpl: async (url, payload, options) => {
      calls.push({ url: String(url), payload, options });
      return {
        ok: true,
        schema_version: 'xhub.rust_hub.local_ml_execution_bridge.v1',
        request_id: payload.request_id,
        runtime_base_dir: payload.runtime_base_dir,
        audit_ref: 'rust-local-ml-1',
        result: {
          ok: true,
          provider: 'transformers',
          taskKind: 'text_generate',
          modelId: 'local-model',
          text: 'hello',
          usage: {
            promptTokens: 2,
            completionTokens: 1,
            totalTokens: 3,
          },
        },
      };
    },
    logger: { log() {}, warn() {} },
  });
  const out = await bridge.executeLocalTask({
    runtimeBaseDir: '/tmp/runtime',
    requestId: 'req-1',
    request: {
      request_id: 'req-1',
      model_id: 'local-model',
      task_kind: 'text_generate',
      prompt: 'hi',
    },
  });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'http://127.0.0.1:55151/local-ml/execute');
  assert.equal(calls[0].payload.command, 'run-local-task');
  assert.equal(calls[0].payload.runtime_base_dir, '/tmp/runtime');
  assert.equal(calls[0].options.timeoutMs, 12345);
  assert.equal(out.ok, true);
  assert.equal(out.text, 'hello');
  assert.equal(out.usage.total_tokens, 3);
  assert.equal(out.auditRef, 'rust-local-ml-1');
});

await run('Rust local ML execution normalization preserves failed reason codes', () => {
  const out = normalizeRustLocalMlExecutionResult({
    ok: false,
    error_code: 'local_runtime_failed',
    result: {
      ok: false,
      reasonCode: 'missing_runtime',
      error: 'missing_runtime',
    },
  });
  assert.equal(out.ok, false);
  assert.equal(out.errorCode, 'local_runtime_failed');
  assert.equal(out.errorMessage, 'missing_runtime');
});
