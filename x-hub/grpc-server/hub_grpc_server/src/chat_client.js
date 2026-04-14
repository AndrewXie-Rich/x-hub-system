import readline from 'node:readline';

import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';
import { makeClientCredentials } from './client_credentials.js';
import { resolveHubProtoPath } from './proto_path.js';

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

function metadataFromEnv() {
  const tok = (process.env.HUB_CLIENT_TOKEN || '').trim();
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

function reqClientFromEnv() {
  return {
    device_id: (process.env.HUB_DEVICE_ID || 'terminal_device').trim(),
    user_id: (process.env.HUB_USER_ID || '').trim(),
    app_id: (process.env.HUB_APP_ID || 'x_terminal').trim(),
    project_id: (process.env.HUB_PROJECT_ID || '').trim(),
    session_id: (process.env.HUB_SESSION_ID || '').trim(),
  };
}

function parseArgs(argv) {
  const out = {
    list: false,
    model: '',
    prompt: '',
    system: '',
    threadKey: '',
    maxTokens: 512,
    temperature: 0.2,
    topP: 0.95,
    workingSetLimit: 20,
    grantTtlSec: 600,
    grantTokenCap: 2000,
    noAutoGrant: false,
    noMemory: false,
    noEvents: false,
  };

  const args = [...argv];
  while (args.length) {
    const a = String(args.shift() || '');
    if (!a) continue;
    if (a === '--list' || a === '-l') out.list = true;
    else if (a === '--model' || a === '-m') out.model = String(args.shift() || '').trim();
    else if (a === '--prompt' || a === '-p') out.prompt = String(args.shift() || '');
    else if (a === '--system' || a === '-s') out.system = String(args.shift() || '');
    else if (a === '--thread-key') out.threadKey = String(args.shift() || '').trim();
    else if (a === '--max-tokens') out.maxTokens = Number(args.shift() || out.maxTokens);
    else if (a === '--temperature') out.temperature = Number(args.shift() || out.temperature);
    else if (a === '--top-p') out.topP = Number(args.shift() || out.topP);
    else if (a === '--working-set-limit') out.workingSetLimit = Number(args.shift() || out.workingSetLimit);
    else if (a === '--grant-ttl-sec') out.grantTtlSec = Number(args.shift() || out.grantTtlSec);
    else if (a === '--grant-token-cap') out.grantTokenCap = Number(args.shift() || out.grantTokenCap);
    else if (a === '--no-auto-grant') out.noAutoGrant = true;
    else if (a === '--no-memory') out.noMemory = true;
    else if (a === '--no-events') out.noEvents = true;
    else if (a === '--help' || a === '-h') out.help = true;
  }

  if (!Number.isFinite(out.maxTokens) || out.maxTokens <= 0) out.maxTokens = 512;
  if (!Number.isFinite(out.temperature) || out.temperature < 0) out.temperature = 0.2;
  if (!Number.isFinite(out.topP) || out.topP <= 0) out.topP = 0.95;
  if (!Number.isFinite(out.workingSetLimit) || out.workingSetLimit <= 0) out.workingSetLimit = 20;
  if (!Number.isFinite(out.grantTtlSec) || out.grantTtlSec <= 0) out.grantTtlSec = 600;
  if (!Number.isFinite(out.grantTokenCap) || out.grantTokenCap < 0) out.grantTokenCap = 2000;

  return out;
}

function printUsage() {
  // eslint-disable-next-line no-console
  console.log(
    [
      'Usage:',
      '  npm run list-models  # see model_id',
      '  npm run chat -- --model <model_id>              # interactive',
      '  npm run chat -- --model <model_id> --prompt "hi" # one-shot',
      '',
      'Env:',
      '  HUB_HOST=... HUB_PORT=50051 HUB_CLIENT_TOKEN=... (optional)',
      '  HUB_PROJECT_ID=... HUB_THREAD_KEY=default (optional; enables Hub-side memory continuity)',
      '',
      'Tips (interactive):',
      '  /models            list models',
      '  /model <model_id>  switch model',
      '  /thread            show current thread',
      '  /memory            show recent working set',
      '  /system <text>     update canonical system prompt (memory mode)',
      '  /exit              quit',
    ].join('\n')
  );
}

async function getOrCreateThread(memoryClient, md, clientIdent, threadKey) {
  const resp = await new Promise((resolve, reject) => {
    memoryClient.GetOrCreateThread({ client: clientIdent, thread_key: threadKey || 'default' }, md, (err, out) => {
      if (err) reject(err);
      else resolve(out);
    });
  });
  return resp?.thread || null;
}

async function upsertSystemPrompt(memoryClient, md, clientIdent, threadId, systemText) {
  const v = String(systemText ?? '').trim();
  if (!v) return null;
  const resp = await new Promise((resolve, reject) => {
    memoryClient.UpsertCanonicalMemory(
      {
        client: clientIdent,
        scope: 'thread',
        thread_id: String(threadId || '').trim(),
        key: 'system_prompt',
        value: v,
        pinned: true,
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out);
      }
    );
  });
  return resp?.item || null;
}

async function getWorkingSet(memoryClient, md, clientIdent, threadId, limit) {
  const resp = await new Promise((resolve, reject) => {
    memoryClient.GetWorkingSet(
      {
        client: clientIdent,
        thread_id: String(threadId || '').trim(),
        limit: Math.max(1, Math.min(200, Number(limit || 30))),
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out);
      }
    );
  });
  return Array.isArray(resp?.messages) ? resp.messages : [];
}

async function listModels(modelsClient, md, clientIdent) {
  const resp = await new Promise((resolve, reject) => {
    modelsClient.ListModels({ client: clientIdent }, md, (err, out) => {
      if (err) reject(err);
      else resolve(out);
    });
  });
  return Array.isArray(resp?.models) ? resp.models : [];
}

function printModels(models) {
  // eslint-disable-next-line no-console
  console.log(`Models: ${models.length}`);
  let i = 0;
  for (const m of models) {
    i += 1;
    const id = String(m?.model_id || '').trim();
    const name = String(m?.name || id);
    const kind = String(m?.kind || '');
    const backend = String(m?.backend || '');
    const vis = String(m?.visibility || '');
    const rg = m?.requires_grant ? 'requires_grant' : 'no_grant';
    // eslint-disable-next-line no-console
    console.log(`${String(i).padStart(2, ' ')}. ${name} | ${id} | ${kind} | ${backend} | ${vis} | ${rg}`);
  }
}

function resolveModelSelection(input, models) {
  const raw = String(input || '').trim();
  if (!raw) return { ok: false, id: '', reason: 'empty' };

  const ms = Array.isArray(models) ? models : [];
  const byId = new Map(ms.map((m) => [String(m?.model_id || '').trim(), m]));
  if (byId.has(raw)) return { ok: true, id: raw, info: byId.get(raw) };

  // Allow selecting by the printed index (1-based).
  if (/^\d+$/.test(raw)) {
    const idx = Math.max(0, Number.parseInt(raw, 10) - 1);
    const m = ms[idx];
    const id = String(m?.model_id || '').trim();
    if (id) return { ok: true, id, info: m };
  }

  // Allow selecting by display name when unique.
  const nameMatches = ms.filter((m) => String(m?.name || '').trim() === raw);
  if (nameMatches.length === 1) {
    const id = String(nameMatches[0]?.model_id || '').trim();
    if (id) return { ok: true, id, info: nameMatches[0] };
  }

  // Allow selecting by suffix for namespaced ids like "openai/gpt-5.2-codex".
  const suffixMatches = ms.filter((m) => {
    const id = String(m?.model_id || '').trim();
    if (!id) return false;
    return id === raw || id.endsWith(`/${raw}`);
  });
  if (suffixMatches.length === 1) {
    const id = String(suffixMatches[0]?.model_id || '').trim();
    if (id) return { ok: true, id, info: suffixMatches[0] };
  }

  return { ok: false, id: '', reason: suffixMatches.length > 1 ? 'ambiguous' : 'not_found' };
}

async function requestPaidGrant(grantsClient, md, clientIdent, modelId, ttlSec, tokenCap) {
  const resp = await new Promise((resolve, reject) => {
    grantsClient.RequestGrant(
      {
        request_id: `grant_paid_${Date.now()}`,
        client: clientIdent,
        capability: 'CAPABILITY_AI_GENERATE_PAID',
        model_id: modelId,
        reason: 'terminal chat',
        requested_ttl_sec: Math.max(10, Math.floor(Number(ttlSec || 0))),
        requested_token_cap: Math.max(0, Math.floor(Number(tokenCap || 0))),
        created_at_ms: Date.now(),
      },
      md,
      (err, out) => {
        if (err) reject(err);
        else resolve(out);
      }
    );
  });
  return resp;
}

function isGrantRequiredFromModelInfo(mi) {
  if (!mi) return false;
  if (mi.requires_grant === true) return true;
  const kind = String(mi.kind || '').toUpperCase();
  return kind === 'MODEL_KIND_PAID_ONLINE';
}

async function generateOnce(aiClient, md, req) {
  const stream = aiClient.Generate(req, md);
  return new Promise((resolve, reject) => {
    let assistantText = '';
    let doneObj = null;
    let errObj = null;

    stream.on('data', (ev) => {
      // With proto-loader(oneofs: true), oneof "ev" usually adds `ev: "<field>"`
      // plus the actual field.
      const which = String(ev?.ev || '').trim();
      const delta = ev?.delta || (which === 'delta' ? ev?.delta : null);
      const done = ev?.done || (which === 'done' ? ev?.done : null);
      const err = ev?.error || (which === 'error' ? ev?.error : null);

      if (delta && typeof delta.text === 'string' && delta.text) {
        assistantText += delta.text;
        process.stdout.write(delta.text);
      }
      if (done) doneObj = done;
      if (err) errObj = err;
    });

    stream.on('end', () => resolve({ assistantText, done: doneObj, error: errObj }));
    stream.on('error', (e) => reject(e));
  });
}

function startEventsStream(eventsClient, md, clientIdent, { onGrantDecision, onQuotaUpdated, onKillSwitchUpdated, onRequestStatus, onModelsUpdated }) {
  const stream = eventsClient.Subscribe(
    {
      client: clientIdent,
      scopes: ['models', 'grants', 'quota', 'killswitch', 'requests'],
      last_event_id: '',
    },
    md
  );

  stream.on('data', (ev) => {
    const which = String(ev?.ev || '').trim();
    if (which === 'models_updated') {
      onModelsUpdated?.(ev.models_updated || null, ev);
      return;
    }
    if (which === 'grant_decision') {
      onGrantDecision?.(ev.grant_decision || null, ev);
      return;
    }
    if (which === 'quota_updated') {
      onQuotaUpdated?.(ev.quota_updated || null, ev);
      return;
    }
    if (which === 'kill_switch_updated') {
      onKillSwitchUpdated?.(ev.kill_switch_updated || null, ev);
      return;
    }
    if (which === 'request_status') {
      onRequestStatus?.(ev.request_status || null, ev);
      return;
    }
  });

  stream.on('error', (e) => {
    // eslint-disable-next-line no-console
    console.error(`[events] error: ${e?.message || e}`);
  });
  stream.on('end', () => {
    // eslint-disable-next-line no-console
    console.error('[events] ended');
  });

  return stream;
}

async function readStdinText() {
  return new Promise((resolve) => {
    if (process.stdin.isTTY) {
      resolve('');
      return;
    }
    let buf = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (c) => {
      buf += c;
    });
    process.stdin.on('end', () => resolve(buf));
  });
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help) {
    printUsage();
    process.exit(0);
  }

  const host = (process.env.HUB_HOST || '127.0.0.1').trim();
  const port = Number(process.env.HUB_PORT || 50051);
  const addr = `${host}:${port}`;

  const proto = loadProto(resolveHubProtoPath(process.env));
  if (!proto?.HubModels || !proto?.HubGrants || !proto?.HubAI || !proto?.HubEvents || !proto?.HubMemory) {
    throw new Error('failed to load required services from proto');
  }

  const md = metadataFromEnv();
  const clientIdent = reqClientFromEnv();

  const { creds, options } = makeClientCredentials(process.env);
  const modelsClient = new proto.HubModels(addr, creds, options);
  const grantsClient = new proto.HubGrants(addr, creds, options);
  const aiClient = new proto.HubAI(addr, creds, options);
  const eventsClient = new proto.HubEvents(addr, creds, options);
  const memoryClient = new proto.HubMemory(addr, creds, options);

  const models = await listModels(modelsClient, md, clientIdent);
  if (opts.list) {
    // eslint-disable-next-line no-console
    console.log(`Hub connected: ${addr}`);
    printModels(models);
    process.exit(0);
  }

  const pickModelId = () => {
    const wanted = String(opts.model || '').trim();
    if (wanted) {
      const resolved = resolveModelSelection(wanted, models);
      if (resolved.ok) return resolved.id;
      // eslint-disable-next-line no-console
      console.error(`Unknown model selection: "${wanted}" (use model_id from ListModels).`);
      printModels(models);
      process.exit(2);
    }
    // Default: prefer a local model (no grant) so first-run works.
    const local = models.find((m) => m && m.requires_grant === false) || models.find((m) => String(m?.kind || '') === 'MODEL_KIND_LOCAL_OFFLINE');
    if (local?.model_id) return String(local.model_id).trim();
    // Otherwise, fall back to the first model.
    if (models[0]?.model_id) return String(models[0].model_id).trim();
    return '';
  };

  let currentModelId = pickModelId();
  if (!currentModelId) {
    // eslint-disable-next-line no-console
    console.error('No models found. Run `npm run list-models` and make sure Hub is running.');
    process.exit(2);
  }

  const modelInfoById = new Map(models.map((m) => [String(m?.model_id || '').trim(), m]));
  const useMemory = !opts.noMemory;
  const threadKey = (opts.threadKey || process.env.HUB_THREAD_KEY || 'default').trim() || 'default';
  let threadId = '';

  const grantDecisionWaiters = new Map(); // grant_request_id -> (decision) => void
  let rl = null;

  if (useMemory) {
    try {
      const th = await getOrCreateThread(memoryClient, md, clientIdent, threadKey);
      threadId = String(th?.thread_id || '').trim();
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error(`[memory] GetOrCreateThread failed: ${e?.message || e}`);
      threadId = '';
    }
    if (threadId && String(opts.system || '').trim()) {
      try {
        await upsertSystemPrompt(memoryClient, md, clientIdent, threadId, opts.system);
      } catch (e) {
        // eslint-disable-next-line no-console
        console.error(`[memory] UpsertCanonicalMemory failed: ${e?.message || e}`);
      }
    }
  }

  const interactive = process.stdin.isTTY && !String(opts.prompt || '').trim();
  if (!opts.noEvents && interactive) {
    startEventsStream(eventsClient, md, clientIdent, {
      onModelsUpdated: (mu) => {
        const n = Array.isArray(mu?.models) ? mu.models.length : 0;
        // eslint-disable-next-line no-console
        console.error(`[models] updated (${n})`);
        if (rl && process.stdin.isTTY) rl.prompt(true);
      },
      onGrantDecision: (gd) => {
        const gid = String(gd?.grant_request_id || '').trim();
        const decision = String(gd?.decision || '').trim();
        const deny = String(gd?.deny_reason || '').trim();
        // eslint-disable-next-line no-console
        console.error(`[grant] ${decision}${deny ? ` (${deny})` : ''} id=${gid || 'unknown'}`);
        const waiter = gid ? grantDecisionWaiters.get(gid) : null;
        if (waiter) {
          grantDecisionWaiters.delete(gid);
          try {
            waiter(gd);
          } catch {
            // ignore
          }
        }
        if (rl && process.stdin.isTTY) rl.prompt(true);
      },
      onQuotaUpdated: (qu) => {
        const scope = String(qu?.scope || '').trim();
        const used = Number(qu?.daily_token_used || 0);
        const cap = Number(qu?.daily_token_cap || 0);
        // eslint-disable-next-line no-console
        console.error(`[quota] ${scope || 'unknown'} ${used}/${cap || 'unlimited'}`);
        if (rl && process.stdin.isTTY) rl.prompt(true);
      },
      onKillSwitchUpdated: (ks) => {
        const scope = String(ks?.scope || '').trim();
        // eslint-disable-next-line no-console
        console.error(`[killswitch] ${scope || 'unknown'} models=${!!ks?.models_disabled} network=${!!ks?.network_disabled}`);
        if (rl && process.stdin.isTTY) rl.prompt(true);
      },
      onRequestStatus: (rs) => {
        const rid = String(rs?.request_id || '').trim();
        const st = String(rs?.status || '').trim();
        if (!rid || !st) return;
        // eslint-disable-next-line no-console
        console.error(`[req] ${rid} ${st}`);
        if (rl && process.stdin.isTTY) rl.prompt(true);
      },
    });
  }

  // eslint-disable-next-line no-console
  console.log(`Hub connected: ${addr}`);
  // eslint-disable-next-line no-console
  console.log(`Using model: ${currentModelId}`);
  if (useMemory) {
    // eslint-disable-next-line no-console
    console.log(`Memory: ${threadId ? `on (thread_id=${threadId}, thread_key=${threadKey})` : 'failed to init (falling back to stateless)'}`);
  }

  function waitForGrantDecision(grantRequestId, timeoutMs = 60_000) {
    const gid = String(grantRequestId || '').trim();
    if (!gid) return Promise.resolve(null);
    return new Promise((resolve) => {
      const t = setTimeout(() => {
        grantDecisionWaiters.delete(gid);
        resolve(null);
      }, Math.max(1000, Number(timeoutMs || 0)));
      grantDecisionWaiters.set(gid, (gd) => {
        clearTimeout(t);
        resolve(gd);
      });
    });
  }

  async function ensureGrantIfNeeded(modelId) {
    const mi = modelInfoById.get(String(modelId || '').trim()) || null;
    if (!isGrantRequiredFromModelInfo(mi)) return;
    if (opts.noAutoGrant) return;
    const resp = await requestPaidGrant(grantsClient, md, clientIdent, modelId, opts.grantTtlSec, opts.grantTokenCap);
    const decision = String(resp?.decision || '').trim();
    if (decision && decision !== 'GRANT_DECISION_APPROVED') {
      // eslint-disable-next-line no-console
      console.log(`Grant decision: ${decision} (may require manual approval in Hub UI)`);
      const gid = String(resp?.grant_request_id || '').trim();
      if (gid && decision === 'GRANT_DECISION_QUEUED' && !opts.noEvents && interactive) {
        const gd = await waitForGrantDecision(gid, 120_000);
        if (gd && String(gd?.decision || '') === 'GRANT_DECISION_APPROVED') {
          // eslint-disable-next-line no-console
          console.log('Grant approved.');
        }
      }
    }
  }

  const stdinPrompt = opts.prompt || (await readStdinText());
  const oneShot = String(stdinPrompt || '').trim();

  const baseMessages = [];
  if (!useMemory && String(opts.system || '').trim()) baseMessages.push({ role: 'system', content: String(opts.system) });

  async function runGenerate(userText) {
    const req = {
      request_id: `chat_${Date.now()}`,
      client: clientIdent,
      model_id: currentModelId,
      messages: [...baseMessages, { role: 'user', content: String(userText) }],
      max_tokens: Math.max(1, Math.floor(opts.maxTokens)),
      temperature: Number(opts.temperature),
      top_p: Number(opts.topP),
      stream: true,
      created_at_ms: Date.now(),
    };
    if (useMemory && threadId) {
      req.thread_id = threadId;
      req.working_set_limit = Math.max(1, Math.min(200, Math.floor(Number(opts.workingSetLimit || 20))));
      // In memory mode, do not resend a system message every turn; store it as canonical memory instead.
      req.messages = [{ role: 'user', content: String(userText) }];
    }

    await ensureGrantIfNeeded(currentModelId);
    const out = await generateOnce(aiClient, md, req);

    // If the server ends the stream without any text and provides an error payload,
    // surface it. (Some transports map this to stream "end" rather than "error".)
    const errCode = String(out?.error?.error?.code || '').trim();
    const errMsg = String(out?.error?.error?.message || '').trim();
    if (errCode || errMsg) {
      // eslint-disable-next-line no-console
      console.error(`\n[error] ${errCode || 'unknown'}: ${errMsg || 'unknown error'}`);
      if (errCode === 'grant_required' && !opts.noAutoGrant) {
        // Try one more time after requesting a grant.
        await ensureGrantIfNeeded(currentModelId);
        const out2 = await generateOnce(aiClient, md, req);
        const err2Code = String(out2?.error?.error?.code || '').trim();
        const err2Msg = String(out2?.error?.error?.message || '').trim();
        if (err2Code || err2Msg) {
          // eslint-disable-next-line no-console
          console.error(`\n[error] ${err2Code || 'unknown'}: ${err2Msg || 'unknown error'}`);
        }
      }
    }

    const doneOk = out?.done?.ok;
    const doneReason = String(out?.done?.reason || '').trim();
    if (doneOk === false) {
      // eslint-disable-next-line no-console
      console.error(`\n[done] ok=false reason=${doneReason || 'failed'}`);
    } else if (!out?.assistantText?.trim()) {
      // eslint-disable-next-line no-console
      console.error('\n[done] (no text)');
    }

    // Ensure a trailing newline for nicer terminal UX.
    process.stdout.write('\n');
  }

  if (oneShot) {
    await runGenerate(oneShot);
    return;
  }

  if (!process.stdin.isTTY) {
    // Nothing to do; stdin ended.
    return;
  }

  printUsage();

  rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  rl.setPrompt('> ');
  rl.prompt();

  rl.on('line', async (line) => {
    const text = String(line || '').trim();
    if (!text) {
      rl.prompt();
      return;
    }

    try {
      if (text === '/exit' || text === '/quit') {
        rl.close();
        return;
      }
      if (text === '/help') {
        printUsage();
        rl.prompt();
        return;
      }
      if (text === '/models') {
        const ms = await listModels(modelsClient, md, clientIdent);
        // Refresh map so /model works after Hub changes.
        modelInfoById.clear();
        for (const m of ms) {
          modelInfoById.set(String(m?.model_id || '').trim(), m);
        }
        printModels(ms);
        rl.prompt();
        return;
      }
      if (text === '/thread') {
        // eslint-disable-next-line no-console
        console.log(threadId ? `thread_id=${threadId} thread_key=${threadKey}` : 'thread: (memory disabled)');
        rl.prompt();
        return;
      }
      if (text === '/memory') {
        if (!useMemory || !threadId) {
          // eslint-disable-next-line no-console
          console.log('memory: disabled');
          rl.prompt();
          return;
        }
        const msgs = await getWorkingSet(memoryClient, md, clientIdent, threadId, 30);
        // eslint-disable-next-line no-console
        console.log(`Working set (${msgs.length})`);
        for (const m of msgs) {
          const role = String(m?.role || '').trim();
          const content = String(m?.content || '').trim();
          if (!role || !content) continue;
          // eslint-disable-next-line no-console
          console.log(`[${role}] ${content}`);
        }
        rl.prompt();
        return;
      }
      if (text.startsWith('/system ')) {
        const next = text.slice('/system '.length);
        if (!useMemory || !threadId) {
          // eslint-disable-next-line no-console
          console.log('system: memory disabled (run without --no-memory)');
          rl.prompt();
          return;
        }
        await upsertSystemPrompt(memoryClient, md, clientIdent, threadId, next);
        // eslint-disable-next-line no-console
        console.log('system prompt updated (canonical memory: system_prompt)');
        rl.prompt();
        return;
      }
      if (text.startsWith('/model ')) {
        const next = text.slice('/model '.length).trim();
        if (!next) {
          // eslint-disable-next-line no-console
          console.log('Usage: /model <model_id>');
          rl.prompt();
          return;
        }
        const ms = await listModels(modelsClient, md, clientIdent);
        modelInfoById.clear();
        for (const m of ms) {
          modelInfoById.set(String(m?.model_id || '').trim(), m);
        }
        const resolved = resolveModelSelection(next, ms);
        if (!resolved.ok) {
          // eslint-disable-next-line no-console
          console.log(`Unknown model selection: ${next}`);
          printModels(ms);
          rl.prompt();
          return;
        }
        currentModelId = resolved.id;
        // eslint-disable-next-line no-console
        console.log(`Using model: ${currentModelId}`);
        rl.prompt();
        return;
      }

      await runGenerate(text);
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error('chat error:', e?.message || e);
    } finally {
      rl.prompt();
    }
  });

  rl.on('close', () => process.exit(0));
}

main().catch((e) => {
  // eslint-disable-next-line no-console
  console.error('chat failed:', e?.message || e);
  process.exit(1);
});
