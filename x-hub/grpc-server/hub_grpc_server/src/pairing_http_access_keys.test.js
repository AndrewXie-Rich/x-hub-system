import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';

import { startPairingHTTPServer } from './pairing_http.js';

function run(name, fn) {
  try {
    const maybePromise = fn();
    if (maybePromise && typeof maybePromise.then === 'function') {
      return maybePromise.then(() => {
        process.stdout.write(`ok - ${name}\n`);
      }).catch((error) => {
        process.stderr.write(`not ok - ${name}\n`);
        throw error;
      });
    }
    process.stdout.write(`ok - ${name}\n`);
    return Promise.resolve();
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

async function withEnvAsync(tempEnv, fn) {
  const previous = new Map();
  for (const key of Object.keys(tempEnv || {})) {
    previous.set(key, process.env[key]);
    const next = tempEnv[key];
    if (next == null) delete process.env[key];
    else process.env[key] = String(next);
  }
  try {
    return await fn();
  } finally {
    for (const [key, value] of previous.entries()) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, Math.max(0, Number(ms || 0))));
}

function requestJson({
  method = 'GET',
  url,
  headers = {},
  body,
  timeout_ms = 2_000,
} = {}) {
  const target = new URL(String(url || ''));
  const payload = body == null ? '' : (typeof body === 'string' ? body : JSON.stringify(body));
  const reqHeaders = { ...headers };
  if (payload) {
    if (!reqHeaders['content-type']) reqHeaders['content-type'] = 'application/json; charset=utf-8';
    reqHeaders['content-length'] = String(Buffer.byteLength(payload, 'utf8'));
  }

  return new Promise((resolve, reject) => {
    const req = http.request({
      method: String(method || 'GET').toUpperCase(),
      hostname: target.hostname,
      port: Number(target.port || 80),
      path: `${target.pathname}${target.search}`,
      headers: reqHeaders,
      timeout: Math.max(100, Number(timeout_ms || 0)),
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
          text,
          json,
        });
      });
    });
    req.on('error', reject);
    req.on('timeout', () => req.destroy(new Error('request_timeout')));
    if (payload) req.write(payload);
    req.end();
  });
}

function requestStreamAndAbort({
  method = 'GET',
  url,
  headers = {},
  body,
  abortWhenIncludes = 'data:',
  timeout_ms = 2_000,
} = {}) {
  const target = new URL(String(url || ''));
  const payload = body == null ? '' : (typeof body === 'string' ? body : JSON.stringify(body));
  const reqHeaders = { ...headers };
  if (payload) {
    if (!reqHeaders['content-type']) reqHeaders['content-type'] = 'application/json; charset=utf-8';
    reqHeaders['content-length'] = String(Buffer.byteLength(payload, 'utf8'));
  }

  return new Promise((resolve, reject) => {
    let settled = false;
    let abortTriggered = false;
    let collected = '';
    const req = http.request({
      method: String(method || 'GET').toUpperCase(),
      hostname: target.hostname,
      port: Number(target.port || 80),
      path: `${target.pathname}${target.search}`,
      headers: reqHeaders,
      timeout: Math.max(100, Number(timeout_ms || 0)),
    }, (res) => {
      res.on('data', (chunk) => {
        collected += Buffer.from(chunk).toString('utf8');
        if (!abortTriggered && collected.includes(abortWhenIncludes)) {
          abortTriggered = true;
          try {
            req.destroy(new Error('client_abort_after_first_frame'));
          } catch {
            // ignore
          }
        }
      });
      res.on('end', () => {
        if (settled) return;
        settled = true;
        resolve({
          status: Number(res.statusCode || 0),
          headers: res.headers || {},
          text: collected,
          aborted: abortTriggered,
        });
      });
      res.on('close', () => {
        if (settled) return;
        settled = true;
        resolve({
          status: Number(res.statusCode || 0),
          headers: res.headers || {},
          text: collected,
          aborted: abortTriggered,
        });
      });
    });
    req.on('error', (error) => {
      if (abortTriggered) {
        if (settled) return;
        settled = true;
        resolve({
          status: 0,
          headers: {},
          text: collected,
          aborted: true,
          error: String(error?.message || error || ''),
        });
        return;
      }
      reject(error);
    });
    req.on('timeout', () => req.destroy(new Error('request_timeout')));
    if (payload) req.write(payload);
    req.end();
  });
}

function parseSSEFrames(rawText = '') {
  return String(rawText || '')
    .replaceAll('\r\n', '\n')
    .split('\n\n')
    .map((chunk) => chunk.trim())
    .filter(Boolean)
    .map((chunk) => {
      const lines = chunk.split('\n');
      let event = '';
      const dataLines = [];
      for (const line of lines) {
        if (line.startsWith('event:')) {
          event = line.slice('event:'.length).trim();
          continue;
        }
        if (line.startsWith('data:')) {
          dataLines.push(line.slice('data:'.length).trim());
        }
      }
      const data = dataLines.join('\n');
      let json = null;
      if (data && data !== '[DONE]') {
        try {
          json = JSON.parse(data);
        } catch {
          json = null;
        }
      }
      return { event, data, json };
    });
}

async function waitForHealth(baseUrl, timeoutMs = 2_000) {
  const deadline = Date.now() + Math.max(200, Number(timeoutMs || 0));
  let lastError = null;
  while (Date.now() < deadline) {
    try {
      const out = await requestJson({ url: `${baseUrl}/health`, timeout_ms: 300 });
      if (out.status === 200) return;
    } catch (error) {
      lastError = error;
    }
    await sleep(25);
  }
  if (lastError) throw lastError;
  throw new Error('pairing_server_not_ready');
}

function makeAuditDb() {
  return {
    rows: [],
    appendAudit(event) {
      this.rows.push(event);
    },
  };
}

async function withPairingServer({ env = {}, db = makeAuditDb(), hubServices = null } = {}, fn) {
  const port = 56200 + Math.floor(Math.random() * 4000);
  const baseUrl = `http://127.0.0.1:${port}`;
  await withEnvAsync({
    HUB_PAIRING_ENABLE: '1',
    HUB_PAIRING_HOST: '127.0.0.1',
    HUB_PAIRING_PORT: String(port),
    HUB_HOST: '127.0.0.1',
    HUB_PORT: '50051',
    HUB_PAIRING_ALLOWED_CIDRS: 'any',
    ...env,
  }, async () => {
    const stop = startPairingHTTPServer({ db, hubServices });
    try {
      await waitForHealth(baseUrl, 3_000);
      await fn({ baseUrl, db });
    } finally {
      try {
        stop?.();
      } catch {
        // ignore
      }
      await sleep(40);
    }
  });
}

function writeClientsSnapshot(runtimeBaseDir, clients) {
  fs.writeFileSync(
    path.join(runtimeBaseDir, 'hub_grpc_clients.json'),
    JSON.stringify({
      schema_version: 'hub_grpc_clients.v2',
      updated_at_ms: 1,
      clients,
    }, null, 2) + '\n',
    'utf8'
  );
}

await run('Hub access key admin HTTP issues, lists, details, revokes, and fail-closes presence auth', async () => {
  const runtimeBaseDir = fs.mkdtempSync(path.join(os.tmpdir(), 'hub_access_keys_http_runtime_'));
  try {
    await withPairingServer({
      env: {
        HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
        HUB_ADMIN_TOKEN: 'admin-access-http',
        HUB_PAIRING_PUBLIC_HOST: 'hub.tailnet.example',
      },
    }, async ({ baseUrl }) => {
      const adminHeaders = {
        authorization: 'Bearer admin-access-http',
      };
      const expectedOpenAIBaseUrl = `http://hub.tailnet.example:${new URL(baseUrl).port}/v1`;

      const issued = await requestJson({
        method: 'POST',
        url: `${baseUrl}/admin/clients/access-keys`,
        headers: adminHeaders,
        body: {
          name: 'CI Runner',
          user_id: 'svc_ci',
          app_id: 'external_terminal',
          capabilities: ['models', 'ai.generate.local'],
          scopes: ['models', 'ai.generate.local'],
          note: 'for external terminal',
          ttl_sec: 3600,
        },
      });
      assert.equal(issued.status, 200);
      const rawToken = String(issued.json?.client_token || '');
      const accessKeyId = String(issued.json?.access_key?.access_key_id || '');
      assert.match(rawToken, /^axhub_client_/);
      assert.ok(accessKeyId);
      assert.equal(String(issued.json?.access_key?.auth_kind || ''), 'hub_access_key');
      assert.equal(String(issued.json?.access_key?.status || ''), 'ready');
      assert.equal(String(issued.json?.access_key?.connect?.hub_host || ''), 'hub.tailnet.example');
      assert.match(String(issued.json?.access_key?.connect_env || ''), /HUB_CLIENT_TOKEN=/);
      assert.equal(String(issued.json?.access_key?.openai_compat?.base_url || ''), expectedOpenAIBaseUrl);
      assert.equal(String(issued.json?.access_key?.openai_compat?.responses_url || ''), `${expectedOpenAIBaseUrl}/responses`);
      assert.match(
        String(issued.json?.access_key?.openai_compat_env || ''),
        new RegExp(`OPENAI_BASE_URL='${expectedOpenAIBaseUrl.replace(/[.*+?^${}()|[\]\\\\]/g, '\\$&')}'`)
      );
      assert.match(String(issued.json?.access_key?.openai_compat_env || ''), /OPENAI_API_KEY='axhub_client_/);

      const listed = await requestJson({
        url: `${baseUrl}/admin/clients/access-keys?auth_kind=hub_access_key`,
        headers: adminHeaders,
      });
      assert.equal(listed.status, 200);
      const listedKey = (listed.json?.access_keys || []).find((item) => String(item?.access_key_id || '') === accessKeyId);
      assert.ok(listedKey);
      assert.equal(String(listedKey?.status || ''), 'ready');
      assert.equal(String(listedKey?.token_redacted || '').includes(rawToken), false);
      assert.equal(Object.prototype.hasOwnProperty.call(listedKey, 'connect_env'), false);

      const detailBeforeUse = await requestJson({
        url: `${baseUrl}/admin/clients/access-keys/${accessKeyId}`,
        headers: adminHeaders,
      });
      assert.equal(detailBeforeUse.status, 200);
      assert.match(String(detailBeforeUse.json?.access_key?.connect_env_template || ''), /HUB_CLIENT_TOKEN=/);
      assert.match(String(detailBeforeUse.json?.access_key?.openai_compat_env_template || ''), /OPENAI_API_KEY='axhub/);
      assert.equal(Number(detailBeforeUse.json?.access_key?.last_used_at_ms || 0), 0);

      const presence = await requestJson({
        method: 'POST',
        url: `${baseUrl}/clients/presence`,
        headers: {
          authorization: `Bearer ${rawToken}`,
        },
        body: {
          app_id: 'external_terminal',
          device_name: 'CI Runner',
          route: 'internet',
          transport_mode: 'hub_grpc_internet',
        },
      });
      assert.equal(presence.status, 200);
      assert.equal(!!presence.json?.ok, true);

      const detailAfterUse = await requestJson({
        url: `${baseUrl}/admin/clients/access-keys/${accessKeyId}`,
        headers: adminHeaders,
      });
      assert.equal(detailAfterUse.status, 200);
      assert.ok(Number(detailAfterUse.json?.access_key?.last_used_at_ms || 0) > 0);
      assert.equal(String(detailAfterUse.json?.access_key?.last_used_transport || ''), 'http');
      assert.equal(String(detailAfterUse.json?.access_key?.last_used_peer_ip || ''), '127.0.0.1');

      const updatedBudget = await requestJson({
        method: 'POST',
        url: `${baseUrl}/admin/clients/access-keys/${accessKeyId}/update`,
        headers: adminHeaders,
        body: {
          daily_token_limit: 128000,
          note: 'rebudgeted key',
        },
      });
      assert.equal(updatedBudget.status, 200);
      assert.equal(Number(updatedBudget.json?.access_key?.approved_trust_profile?.budget_policy?.daily_token_limit || 0), 128000);
      assert.equal(String(updatedBudget.json?.access_key?.note || ''), 'rebudgeted key');

      const detailAfterBudgetUpdate = await requestJson({
        url: `${baseUrl}/admin/clients/access-keys/${accessKeyId}`,
        headers: adminHeaders,
      });
      assert.equal(detailAfterBudgetUpdate.status, 200);
      assert.equal(Number(detailAfterBudgetUpdate.json?.access_key?.approved_trust_profile?.budget_policy?.daily_token_limit || 0), 128000);

      const revoked = await requestJson({
        method: 'POST',
        url: `${baseUrl}/admin/clients/access-keys/${accessKeyId}/revoke`,
        headers: adminHeaders,
        body: {
          revoked_by_hub_user_id: 'ops_admin',
          revoked_via: 'hub_local_ui',
          note: 'retire key',
        },
      });
      assert.equal(revoked.status, 200);
      assert.equal(!!revoked.json?.ok, true);
      assert.equal(String(revoked.json?.access_key?.status || ''), 'revoked');
      assert.equal(String(revoked.json?.access_key?.revoke_reason || ''), 'retire key');

      const denied = await requestJson({
        method: 'POST',
        url: `${baseUrl}/clients/presence`,
        headers: {
          authorization: `Bearer ${rawToken}`,
        },
        body: {
          app_id: 'external_terminal',
        },
      });
      assert.equal(denied.status, 401);
      assert.equal(String(denied.json?.error?.code || ''), 'token_revoked');
    });
  } finally {
    try {
      fs.rmSync(runtimeBaseDir, { recursive: true, force: true });
    } catch {
      // ignore
    }
  }
});

await run('Hub access key OpenAI-compatible gateway lists models and returns chat completions', async () => {
  const runtimeBaseDir = fs.mkdtempSync(path.join(os.tmpdir(), 'hub_access_keys_openai_runtime_'));
  try {
    writeClientsSnapshot(runtimeBaseDir, [{
      access_key_id: 'ak_terminal_alpha',
      auth_kind: 'hub_access_key',
      device_id: 'client_terminal_alpha',
      user_id: 'terminal_alpha',
      app_id: 'external_terminal',
      name: 'Terminal Alpha',
      token: 'tok_terminal_alpha',
      enabled: true,
      created_at_ms: 1,
      capabilities: ['models', 'ai.generate.local', 'ai.generate.paid'],
      scopes: ['models', 'ai.generate.local', 'ai.generate.paid'],
      allowed_cidrs: ['any'],
    }]);

    const hubServices = {
      HubModels: {
        ListModels(call, callback) {
          callback(null, {
            updated_at_ms: 123,
            models: [{
              model_id: 'openai/gpt-5.4',
              backend: 'openai',
              kind: 'MODEL_KIND_PAID_ONLINE',
              visibility: 'MODEL_VISIBILITY_AVAILABLE',
              requires_grant: false,
              context_length: 200000,
            }],
            trust_profile_present: true,
            paid_model_policy_mode: 'all_paid_models',
            daily_token_limit: 64000,
            single_request_token_limit: 4000,
          });
        },
      },
      HubAI: {
        async Generate(call) {
          const requestId = String(call?.request?.request_id || '');
          call.write({
            start: {
              request_id: requestId,
              model_id: 'openai/gpt-5.4',
              started_at_ms: 111,
            },
          });
          call.write({
            delta: {
              request_id: requestId,
              seq: 1,
              text: 'hello',
            },
          });
          call.write({
            delta: {
              request_id: requestId,
              seq: 2,
              text: ' world',
            },
          });
          call.write({
            done: {
              request_id: requestId,
              ok: true,
              reason: 'eos',
              usage: {
                prompt_tokens: 11,
                completion_tokens: 2,
                total_tokens: 13,
              },
              finished_at_ms: 222,
              actual_model_id: 'openai/gpt-5.4',
              runtime_provider: 'Hub (Remote)',
              execution_path: 'remote_model',
              fallback_reason_code: '',
              audit_ref: 'audit_openai_1',
              deny_code: '',
            },
          });
          call.end();
        },
      },
    };

    await withPairingServer({
      env: {
        HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
        HUB_PAIRING_PUBLIC_HOST: 'hub.tailnet.example',
      },
      hubServices,
    }, async ({ baseUrl }) => {
      const headers = {
        authorization: 'Bearer tok_terminal_alpha',
      };

      const models = await requestJson({
        url: `${baseUrl}/v1/models`,
        headers,
      });
      assert.equal(models.status, 200);
      assert.equal(String(models.json?.object || ''), 'list');
      assert.equal(String(models.json?.data?.[0]?.id || ''), 'openai/gpt-5.4');
      assert.equal(Number(models.json?.daily_token_limit || 0), 64000);

      const completion = await requestJson({
        method: 'POST',
        url: `${baseUrl}/v1/chat/completions`,
        headers,
        body: {
          model: 'openai/gpt-5.4',
          messages: [
            { role: 'system', content: 'be concise' },
            { role: 'user', content: 'say hello' },
          ],
          max_tokens: 32,
        },
      });
      assert.equal(completion.status, 200);
      assert.equal(String(completion.json?.object || ''), 'chat.completion');
      assert.equal(String(completion.json?.model || ''), 'openai/gpt-5.4');
      assert.equal(String(completion.json?.choices?.[0]?.message?.content || ''), 'hello world');
      assert.equal(String(completion.json?.choices?.[0]?.finish_reason || ''), 'stop');
      assert.equal(Number(completion.json?.usage?.total_tokens || 0), 13);
      assert.equal(String(completion.json?.x_hub?.execution_path || ''), 'remote_model');

      const responses = await requestJson({
        method: 'POST',
        url: `${baseUrl}/v1/responses`,
        headers,
        body: {
          model: 'openai/gpt-5.4',
          instructions: 'be concise',
          input: [
            {
              role: 'user',
              content: [
                { type: 'input_text', text: 'say hello' },
              ],
            },
          ],
          max_output_tokens: 32,
        },
      });
      assert.equal(responses.status, 200);
      assert.equal(String(responses.json?.object || ''), 'response');
      assert.equal(String(responses.json?.status || ''), 'completed');
      assert.equal(String(responses.json?.model || ''), 'openai/gpt-5.4');
      assert.equal(String(responses.json?.output_text || ''), 'hello world');
      assert.equal(String(responses.json?.output?.[0]?.type || ''), 'message');
      assert.equal(String(responses.json?.output?.[0]?.content?.[0]?.type || ''), 'output_text');
      assert.equal(String(responses.json?.output?.[0]?.content?.[0]?.text || ''), 'hello world');
      assert.equal(Number(responses.json?.usage?.total_tokens || 0), 13);
      assert.equal(String(responses.json?.x_hub?.execution_path || ''), 'remote_model');

      const streamedResponses = await requestJson({
        method: 'POST',
        url: `${baseUrl}/v1/responses`,
        headers,
        body: {
          model: 'openai/gpt-5.4',
          input: 'say hello',
          stream: true,
        },
      });
      assert.equal(streamedResponses.status, 200);
      assert.match(String(streamedResponses.headers?.['content-type'] || ''), /text\/event-stream/i);
      const responseFrames = parseSSEFrames(streamedResponses.text);
      assert.equal(String(responseFrames[0]?.event || ''), 'response.created');
      assert.equal(String(responseFrames[0]?.json?.type || ''), 'response.created');
      assert.equal(String(responseFrames[1]?.event || ''), 'response.output_item.added');
      assert.equal(String(responseFrames[2]?.event || ''), 'response.content_part.added');
      assert.equal(String(responseFrames[3]?.event || ''), 'response.output_text.delta');
      assert.equal(String(responseFrames[3]?.json?.delta || ''), 'hello');
      assert.equal(String(responseFrames[4]?.event || ''), 'response.output_text.delta');
      assert.equal(String(responseFrames[4]?.json?.delta || ''), ' world');
      assert.equal(String(responseFrames[5]?.event || ''), 'response.output_text.done');
      assert.equal(String(responseFrames[5]?.json?.text || ''), 'hello world');
      assert.equal(String(responseFrames.at(-1)?.event || ''), 'response.completed');
      assert.equal(String(responseFrames.at(-1)?.json?.response?.output_text || ''), 'hello world');
      assert.equal(Number(responseFrames.at(-1)?.json?.response?.usage?.total_tokens || 0), 13);

      const streamed = await requestJson({
        method: 'POST',
        url: `${baseUrl}/v1/chat/completions`,
        headers,
        body: {
          model: 'openai/gpt-5.4',
          messages: [
            { role: 'user', content: 'say hello' },
          ],
          stream: true,
          stream_options: {
            include_usage: true,
          },
        },
      });
      assert.equal(streamed.status, 200);
      assert.match(String(streamed.headers?.['content-type'] || ''), /text\/event-stream/i);
      const chatFrames = parseSSEFrames(streamed.text);
      const jsonFrames = chatFrames.filter((frame) => frame.json);
      const doneFrame = chatFrames.find((frame) => frame.data === '[DONE]');
      assert.ok(doneFrame);
      assert.equal(String(jsonFrames[0]?.json?.object || ''), 'chat.completion.chunk');
      assert.equal(String(jsonFrames[0]?.json?.choices?.[0]?.delta?.role || ''), 'assistant');
      assert.equal(String(jsonFrames[1]?.json?.choices?.[0]?.delta?.content || ''), 'hello');
      assert.equal(String(jsonFrames[2]?.json?.choices?.[0]?.delta?.content || ''), ' world');
      assert.equal(String(jsonFrames[3]?.json?.choices?.[0]?.finish_reason || ''), 'stop');
      assert.equal(Number(jsonFrames[3]?.json?.usage?.total_tokens || 0), 13);

      const denied = await requestJson({
        url: `${baseUrl}/v1/models`,
      });
      assert.equal(denied.status, 401);
      assert.equal(String(denied.json?.error?.code || ''), 'unauthenticated');
    });
  } finally {
    try {
      fs.rmSync(runtimeBaseDir, { recursive: true, force: true });
    } catch {
      // ignore
    }
  }
});

await run('Hub access key streaming gateway cancels upstream generate when client disconnects', async () => {
  const runtimeBaseDir = fs.mkdtempSync(path.join(os.tmpdir(), 'hub_access_keys_stream_cancel_runtime_'));
  try {
    writeClientsSnapshot(runtimeBaseDir, [{
      access_key_id: 'ak_terminal_alpha',
      auth_kind: 'hub_access_key',
      device_id: 'client_terminal_alpha',
      user_id: 'terminal_alpha',
      app_id: 'external_terminal',
      name: 'Terminal Alpha',
      token: 'tok_terminal_alpha',
      enabled: true,
      created_at_ms: 1,
      capabilities: ['models', 'ai.generate.local', 'ai.generate.paid'],
      scopes: ['models', 'ai.generate.local', 'ai.generate.paid'],
      allowed_cidrs: ['any'],
    }]);

    let resolveCancelCalled = null;
    const cancelCalled = new Promise((resolve) => {
      resolveCancelCalled = resolve;
    });
    let cancelRequest = null;

    const hubServices = {
      HubAI: {
        async Generate(call) {
          const requestId = String(call?.request?.request_id || '');
          call.write({
            start: {
              request_id: requestId,
              model_id: 'openai/gpt-5.4',
              started_at_ms: 111,
            },
          });
          call.write({
            delta: {
              request_id: requestId,
              seq: 1,
              text: 'hello',
            },
          });
          await cancelCalled;
          call.write({
            done: {
              request_id: requestId,
              ok: false,
              reason: 'client_disconnected',
              usage: {
                prompt_tokens: 11,
                completion_tokens: 1,
                total_tokens: 12,
              },
              finished_at_ms: 222,
              actual_model_id: 'openai/gpt-5.4',
              runtime_provider: 'Hub (Remote)',
              execution_path: 'remote_model',
              fallback_reason_code: '',
              audit_ref: 'audit_openai_cancel_1',
              deny_code: '',
            },
          });
          call.end();
        },
        Cancel(call, callback) {
          cancelRequest = call?.request || null;
          if (typeof resolveCancelCalled === 'function') {
            resolveCancelCalled(cancelRequest);
            resolveCancelCalled = null;
          }
          callback(null, {
            request_id: String(call?.request?.request_id || ''),
            ok: true,
          });
        },
      },
    };

    await withPairingServer({
      env: {
        HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
        HUB_PAIRING_PUBLIC_HOST: 'hub.tailnet.example',
      },
      hubServices,
    }, async ({ baseUrl }) => {
      const streamed = await requestStreamAndAbort({
        method: 'POST',
        url: `${baseUrl}/v1/chat/completions`,
        headers: {
          authorization: 'Bearer tok_terminal_alpha',
        },
        body: {
          model: 'openai/gpt-5.4',
          messages: [
            { role: 'user', content: 'say hello' },
          ],
          stream: true,
        },
        abortWhenIncludes: 'chat.completion.chunk',
      });

      assert.equal(streamed.aborted, true);
      const chatFrames = parseSSEFrames(streamed.text);
      const firstJsonFrame = chatFrames.find((frame) => frame.json);
      assert.equal(String(firstJsonFrame?.json?.object || ''), 'chat.completion.chunk');
      assert.equal(String(firstJsonFrame?.json?.choices?.[0]?.delta?.role || ''), 'assistant');

      await cancelCalled;
      assert.ok(cancelRequest);
      assert.equal(String(cancelRequest?.reason || ''), 'http_client_disconnected');
      assert.match(String(cancelRequest?.request_id || ''), /\S+/);
    });
  } finally {
    try {
      fs.rmSync(runtimeBaseDir, { recursive: true, force: true });
    } catch {
      // ignore
    }
  }
});

await run('Hub access key rotate returns a fresh secret and keeps old secret unusable', async () => {
  const runtimeBaseDir = fs.mkdtempSync(path.join(os.tmpdir(), 'hub_access_keys_rotate_runtime_'));
  try {
    await withPairingServer({
      env: {
        HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
        HUB_ADMIN_TOKEN: 'admin-access-http',
        HUB_PAIRING_PUBLIC_HOST: 'hub.tailnet.example',
      },
    }, async ({ baseUrl }) => {
      const adminHeaders = {
        authorization: 'Bearer admin-access-http',
      };

      const issued = await requestJson({
        method: 'POST',
        url: `${baseUrl}/admin/clients/access-keys`,
        headers: adminHeaders,
        body: {
          name: 'Rotate Me',
          user_id: 'svc_rotate',
          app_id: 'external_terminal',
          capabilities: ['models'],
          scopes: ['models'],
        },
      });
      assert.equal(issued.status, 200);
      const accessKeyId = String(issued.json?.access_key?.access_key_id || '');
      const oldToken = String(issued.json?.client_token || '');

      const rotated = await requestJson({
        method: 'POST',
        url: `${baseUrl}/admin/clients/access-keys/${accessKeyId}/rotate`,
        headers: adminHeaders,
        body: {
          note: 'rotated',
        },
      });
      assert.equal(rotated.status, 200);
      const newToken = String(rotated.json?.client_token || '');
      assert.match(newToken, /^axhub_client_/);
      assert.notEqual(newToken, oldToken);
      assert.equal(String(rotated.json?.access_key?.status || ''), 'ready');
      assert.equal(Number(rotated.json?.access_key?.rotation_count || 0), 1);
      assert.ok(Number(rotated.json?.access_key?.last_rotated_at_ms || 0) > 0);

      const oldDenied = await requestJson({
        method: 'POST',
        url: `${baseUrl}/clients/presence`,
        headers: {
          authorization: `Bearer ${oldToken}`,
        },
        body: {
          app_id: 'external_terminal',
        },
      });
      assert.equal(oldDenied.status, 401);
      assert.equal(String(oldDenied.json?.error?.code || ''), 'unauthenticated');

      const newPresence = await requestJson({
        method: 'POST',
        url: `${baseUrl}/clients/presence`,
        headers: {
          authorization: `Bearer ${newToken}`,
        },
        body: {
          app_id: 'external_terminal',
          device_name: 'Rotate Me',
        },
      });
      assert.equal(newPresence.status, 200);
      assert.equal(!!newPresence.json?.ok, true);
    });
  } finally {
    try {
      fs.rmSync(runtimeBaseDir, { recursive: true, force: true });
    } catch {
      // ignore
    }
  }
});

await run('Hub access key rotate fails closed for paired client credentials', async () => {
  const runtimeBaseDir = fs.mkdtempSync(path.join(os.tmpdir(), 'hub_access_keys_rotate_guard_runtime_'));
  try {
    writeClientsSnapshot(runtimeBaseDir, [{
      access_key_id: 'dev_xt_alpha',
      auth_kind: 'paired_client',
      device_id: 'dev_xt_alpha',
      user_id: 'xt_alpha',
      app_id: 'x_terminal',
      name: 'XT Alpha',
      token: 'tok_xt_alpha',
      enabled: true,
      created_at_ms: 1,
      capabilities: ['models'],
      scopes: ['models'],
      allowed_cidrs: ['any'],
    }]);

    await withPairingServer({
      env: {
        HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
        HUB_ADMIN_TOKEN: 'admin-access-http',
      },
    }, async ({ baseUrl }) => {
      const rotated = await requestJson({
        method: 'POST',
        url: `${baseUrl}/admin/clients/access-keys/dev_xt_alpha/rotate`,
        headers: {
          authorization: 'Bearer admin-access-http',
        },
        body: {},
      });
      assert.equal(rotated.status, 400);
      assert.equal(String(rotated.json?.error?.code || ''), 'rotate_not_supported_for_paired_client');

      const updated = await requestJson({
        method: 'POST',
        url: `${baseUrl}/admin/clients/access-keys/dev_xt_alpha/update`,
        headers: {
          authorization: 'Bearer admin-access-http',
        },
        body: {
          daily_token_limit: 64000,
        },
      });
      assert.equal(updated.status, 400);
      assert.equal(String(updated.json?.error?.code || ''), 'update_not_supported_for_paired_client');
    });
  } finally {
    try {
      fs.rmSync(runtimeBaseDir, { recursive: true, force: true });
    } catch {
      // ignore
    }
  }
});

await run('Paired XT client can self-manage Hub access keys and export connect env', async () => {
  const runtimeBaseDir = fs.mkdtempSync(path.join(os.tmpdir(), 'hub_access_keys_xt_runtime_'));
  try {
    writeClientsSnapshot(runtimeBaseDir, [{
      access_key_id: 'dev_xt_alpha',
      auth_kind: 'paired_client',
      device_id: 'dev_xt_alpha',
      user_id: 'xt_alpha',
      app_id: 'x_terminal',
      name: 'XT Alpha',
      token: 'tok_xt_alpha',
      enabled: true,
      created_at_ms: 1,
      capabilities: ['models', 'events'],
      scopes: ['models'],
      allowed_cidrs: ['any'],
    }]);

    await withPairingServer({
      env: {
        HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
        HUB_PAIRING_PUBLIC_HOST: 'hub.tailnet.example',
      },
    }, async ({ baseUrl }) => {
      const xtHeaders = {
        authorization: 'Bearer tok_xt_alpha',
      };

      const issued = await requestJson({
        method: 'POST',
        url: `${baseUrl}/xt/clients/access-keys`,
        headers: xtHeaders,
        body: {
          name: 'Ops Shell',
          user_id: 'ops_shell',
          app_id: 'external_terminal',
          note: 'issued from xt',
          ttl_sec: 1800,
        },
      });
      assert.equal(issued.status, 200);
      const accessKeyId = String(issued.json?.access_key?.access_key_id || '');
      const oldToken = String(issued.json?.client_token || '');
      assert.ok(accessKeyId);
      assert.equal(String(issued.json?.access_key?.created_by_user_id || ''), 'xt_alpha');
      assert.equal(String(issued.json?.access_key?.created_by_app_id || ''), 'x_terminal');
      assert.equal(String(issued.json?.access_key?.created_via || ''), 'xt_settings_access_keys');
      assert.match(String(issued.json?.access_key?.connect_env || ''), /HUB_CLIENT_TOKEN=/);

      const listed = await requestJson({
        url: `${baseUrl}/xt/clients/access-keys`,
        headers: xtHeaders,
      });
      assert.equal(listed.status, 200);
      const listedKey = (listed.json?.access_keys || []).find((item) => String(item?.access_key_id || '') === accessKeyId);
      assert.ok(listedKey);
      assert.equal(String(listedKey?.auth_kind || ''), 'hub_access_key');

      const detail = await requestJson({
        url: `${baseUrl}/xt/clients/access-keys/${accessKeyId}`,
        headers: xtHeaders,
      });
      assert.equal(detail.status, 200);
      assert.equal(String(detail.json?.access_key?.access_key_id || ''), accessKeyId);

      const update = await requestJson({
        method: 'POST',
        url: `${baseUrl}/xt/clients/access-keys/${accessKeyId}/update`,
        headers: xtHeaders,
        body: {
          daily_token_limit: 88000,
          note: 'xt rebudgeted',
        },
      });
      assert.equal(update.status, 200);
      assert.equal(Number(update.json?.access_key?.approved_trust_profile?.budget_policy?.daily_token_limit || 0), 88000);
      assert.equal(String(update.json?.access_key?.note || ''), 'xt rebudgeted');

      const rotate = await requestJson({
        method: 'POST',
        url: `${baseUrl}/xt/clients/access-keys/${accessKeyId}/rotate`,
        headers: xtHeaders,
        body: {
          note: 'xt rotated',
        },
      });
      assert.equal(rotate.status, 200);
      const newToken = String(rotate.json?.client_token || '');
      assert.match(newToken, /^axhub_client_/);
      assert.notEqual(newToken, oldToken);

      const oldDenied = await requestJson({
        method: 'POST',
        url: `${baseUrl}/clients/presence`,
        headers: {
          authorization: `Bearer ${oldToken}`,
        },
        body: {
          app_id: 'external_terminal',
        },
      });
      assert.equal(oldDenied.status, 401);
      assert.equal(String(oldDenied.json?.error?.code || ''), 'unauthenticated');

      const revoke = await requestJson({
        method: 'POST',
        url: `${baseUrl}/xt/clients/access-keys/${accessKeyId}/revoke`,
        headers: xtHeaders,
        body: {
          note: 'xt revoked',
        },
      });
      assert.equal(revoke.status, 200);
      assert.equal(String(revoke.json?.access_key?.status || ''), 'revoked');
      assert.equal(String(revoke.json?.access_key?.revoked_by_user_id || ''), 'xt_alpha');
      assert.equal(String(revoke.json?.access_key?.revoked_via || ''), 'xt_settings_access_keys');

      const pairedClientDetail = await requestJson({
        url: `${baseUrl}/xt/clients/access-keys/dev_xt_alpha`,
        headers: xtHeaders,
      });
      assert.equal(pairedClientDetail.status, 404);
      assert.equal(String(pairedClientDetail.json?.error?.code || ''), 'access_key_not_found');
    });
  } finally {
    try {
      fs.rmSync(runtimeBaseDir, { recursive: true, force: true });
    } catch {
      // ignore
    }
  }
});

await run('Non-XT client is denied from XT access key management routes', async () => {
  const runtimeBaseDir = fs.mkdtempSync(path.join(os.tmpdir(), 'hub_access_keys_xt_guard_runtime_'));
  try {
    writeClientsSnapshot(runtimeBaseDir, [{
      access_key_id: 'dev_cli_alpha',
      auth_kind: 'paired_client',
      device_id: 'dev_cli_alpha',
      user_id: 'cli_alpha',
      app_id: 'external_terminal',
      name: 'CLI Alpha',
      token: 'tok_cli_alpha',
      enabled: true,
      created_at_ms: 1,
      capabilities: ['models'],
      scopes: ['models'],
      allowed_cidrs: ['any'],
    }]);

    await withPairingServer({
      env: {
        HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
      },
    }, async ({ baseUrl }) => {
      const denied = await requestJson({
        method: 'POST',
        url: `${baseUrl}/xt/clients/access-keys`,
        headers: {
          authorization: 'Bearer tok_cli_alpha',
        },
        body: {
          name: 'Should Fail',
        },
      });
      assert.equal(denied.status, 403);
      assert.equal(String(denied.json?.error?.code || ''), 'permission_denied');
    });
  } finally {
    try {
      fs.rmSync(runtimeBaseDir, { recursive: true, force: true });
    } catch {
      // ignore
    }
  }
});
