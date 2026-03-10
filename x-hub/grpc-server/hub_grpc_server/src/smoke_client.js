import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';
import { makeClientCredentials } from './client_credentials.js';
import { resolveHubProtoPath } from './proto_path.js';

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
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

function mdFromEnv() {
  const tok = (process.env.HUB_CLIENT_TOKEN || '').trim();
  const md = new grpc.Metadata();
  if (tok) md.set('authorization', `Bearer ${tok}`);
  return md;
}

function streamToArray(stream, timeoutMs = 15000) {
  return new Promise((resolve, reject) => {
    const events = [];
    const t = setTimeout(() => {
      try {
        stream.cancel();
      } catch {
        // ignore
      }
      reject(new Error(`timeout after ${timeoutMs}ms`));
    }, timeoutMs);

    stream.on('data', (ev) => events.push(ev));
    stream.on('end', () => {
      clearTimeout(t);
      resolve(events);
    });
    stream.on('error', (err) => {
      clearTimeout(t);
      reject(err);
    });
  });
}

async function main() {
  const host = (process.env.HUB_HOST || '127.0.0.1').trim();
  const port = Number(process.env.HUB_PORT || 50051);
  const addr = `${host}:${port}`;

  const proto = loadProto(resolveHubProtoPath(process.env));
  const md = mdFromEnv();

  const { creds, options } = makeClientCredentials(process.env);
  const modelsClient = new proto.HubModels(addr, creds, options);
  const grantsClient = new proto.HubGrants(addr, creds, options);
  const aiClient = new proto.HubAI(addr, creds, options);
  const webClient = new proto.HubWeb(addr, creds, options);
  const eventsClient = new proto.HubEvents(addr, creds, options);
  const memoryClient = new proto.HubMemory(addr, creds, options);

  const clientIdent = { device_id: 'dev_device', user_id: 'dev_user', app_id: 'ax_coder_mac', project_id: 'proj_demo', session_id: 'sess_demo' };

  // Subscribe to Hub push events (device-scoped grants + request status).
  const pushed = [];
  const sub = eventsClient.Subscribe({ client: clientIdent, scopes: ['grants', 'requests'], last_event_id: '' }, md);
  sub.on('data', (ev) => pushed.push(ev));
  sub.on('error', () => {
    // ignore in smoke
  });

  const models = await new Promise((resolve, reject) => {
    modelsClient.ListModels({ client: clientIdent }, md, (err, resp) => {
      if (err) reject(err);
      else resolve(resp);
    });
  });
  // eslint-disable-next-line no-console
  console.log('ListModels:', models);
  const allModels = Array.isArray(models?.models) ? models.models : [];
  const localModel = allModels.find((m) => m && m.requires_grant === false) || allModels.find((m) => String(m?.kind || '') === 'MODEL_KIND_LOCAL_OFFLINE');
  const paidModel = allModels.find((m) => m && m.requires_grant === true) || allModels.find((m) => String(m?.kind || '') === 'MODEL_KIND_PAID_ONLINE');
  const localModelId = String(localModel?.model_id || 'mlx/qwen2.5-7b-instruct');
  const paidModelId = paidModel ? String(paidModel.model_id || '') : '';

  const thread = await new Promise((resolve, reject) => {
    memoryClient.GetOrCreateThread({ client: clientIdent, thread_key: 'default' }, md, (err, resp) => {
      if (err) reject(err);
      else resolve(resp);
    });
  });
  // eslint-disable-next-line no-console
  console.log('GetOrCreateThread:', thread);
  const threadId = thread?.thread?.thread_id || '';

  const appended = await new Promise((resolve, reject) => {
    memoryClient.AppendTurns(
      {
        request_id: `mem_append_${Date.now()}`,
        client: clientIdent,
        thread_id: threadId,
        messages: [{ role: 'user', content: 'hello <private>secret</private> world' }],
        created_at_ms: Date.now(),
        allow_private: false,
      },
      md,
      (err, resp) => {
        if (err) reject(err);
        else resolve(resp);
      }
    );
  });
  // eslint-disable-next-line no-console
  console.log('AppendTurns:', appended);

  const working = await new Promise((resolve, reject) => {
    memoryClient.GetWorkingSet({ client: clientIdent, thread_id: threadId, limit: 10 }, md, (err, resp) => {
      if (err) reject(err);
      else resolve(resp);
    });
  });
  // eslint-disable-next-line no-console
  console.log('GetWorkingSet:', working);

  const can1 = await new Promise((resolve, reject) => {
    memoryClient.UpsertCanonicalMemory(
      { client: clientIdent, scope: 'thread', thread_id: threadId, key: 'pref.language', value: 'zh', pinned: true },
      md,
      (err, resp) => {
        if (err) reject(err);
        else resolve(resp);
      }
    );
  });
  // eslint-disable-next-line no-console
  console.log('UpsertCanonicalMemory:', can1);

  const canList = await new Promise((resolve, reject) => {
    memoryClient.ListCanonicalMemory({ client: clientIdent, scope: 'thread', thread_id: threadId, limit: 10 }, md, (err, resp) => {
      if (err) reject(err);
      else resolve(resp);
    });
  });
  // eslint-disable-next-line no-console
  console.log('ListCanonicalMemory:', canList);

  // Web fetch should be gated by a grant (and HTTPS-only by default).
  const fetchDeniedEvents = await streamToArray(
    webClient.Fetch(
      {
        request_id: `fetch_no_grant_${Date.now()}`,
        client: clientIdent,
        url: 'https://example.com',
        method: 'GET',
        headers: {},
        timeout_sec: 5,
        max_bytes: 1000,
        created_at_ms: Date.now(),
        stream: false,
      },
      md
    )
  );
  // eslint-disable-next-line no-console
  console.log('Fetch(no grant) events:', fetchDeniedEvents);

  const webGrantResp = await new Promise((resolve, reject) => {
    grantsClient.RequestGrant(
      {
        request_id: `grant_web_${Date.now()}`,
        client: clientIdent,
        capability: 'CAPABILITY_WEB_FETCH',
        model_id: '',
        reason: 'smoke test web.fetch',
        requested_ttl_sec: 60,
        requested_token_cap: 1000,
        created_at_ms: Date.now(),
      },
      md,
      (err, resp) => {
        if (err) reject(err);
        else resolve(resp);
      }
    );
  });
  // eslint-disable-next-line no-console
  console.log('RequestGrant(web.fetch):', webGrantResp);

  const fetchNonHttpsEvents = await streamToArray(
    webClient.Fetch(
      {
        request_id: `fetch_http_${Date.now()}`,
        client: clientIdent,
        url: 'http://example.com',
        method: 'GET',
        headers: {},
        timeout_sec: 5,
        max_bytes: 1000,
        created_at_ms: Date.now(),
        stream: false,
      },
      md
    )
  );
  // eslint-disable-next-line no-console
  console.log('Fetch(http, with grant) events:', fetchNonHttpsEvents);

  // Local AI generate should succeed without a grant.
  const genLocalEvents = await streamToArray(
    aiClient.Generate(
      {
        request_id: `gen_local_${Date.now()}`,
        client: clientIdent,
        model_id: localModelId,
        messages: [
          { role: 'system', content: 'You are a helpful assistant.' },
          { role: 'user', content: 'Say hello in one sentence.' },
        ],
        max_tokens: 64,
        temperature: 0.2,
        top_p: 0.95,
        stream: true,
        created_at_ms: Date.now(),
      },
      md
    )
  );
  // eslint-disable-next-line no-console
  console.log('Generate(local) events:', genLocalEvents);

  // Paid model generate should be denied without an active grant.
  if (paidModelId) {
    const genPaidDeniedEvents = await streamToArray(
      aiClient.Generate(
        {
          request_id: `gen_paid_no_grant_${Date.now()}`,
          client: clientIdent,
          model_id: paidModelId,
          messages: [{ role: 'user', content: 'Hello' }],
          max_tokens: 16,
          temperature: 0.2,
          top_p: 0.95,
          stream: true,
          created_at_ms: Date.now(),
        },
        md
      )
    );
    // eslint-disable-next-line no-console
    console.log('Generate(paid, no grant) events:', genPaidDeniedEvents);
  } else {
    // eslint-disable-next-line no-console
    console.log('Generate(paid) skipped: no paid models in ListModels');
  }

  // Request a paid-model grant (auto-approve in MVP), then generate should succeed.
  if (paidModelId) {
    const paidGrantResp = await new Promise((resolve, reject) => {
      grantsClient.RequestGrant(
        {
          request_id: `grant_paid_${Date.now()}`,
          client: clientIdent,
          capability: 'CAPABILITY_AI_GENERATE_PAID',
          model_id: paidModelId,
          reason: 'smoke test ai.generate.paid',
          requested_ttl_sec: 60,
          requested_token_cap: 1000,
          created_at_ms: Date.now(),
        },
        md,
        (err, resp) => {
          if (err) reject(err);
          else resolve(resp);
        }
      );
    });
    // eslint-disable-next-line no-console
    console.log('RequestGrant(ai.generate.paid):', paidGrantResp);

    const genPaidOkEvents = await streamToArray(
      aiClient.Generate(
        {
          request_id: `gen_paid_ok_${Date.now()}`,
          client: clientIdent,
          model_id: paidModelId,
          messages: [{ role: 'user', content: 'Say hello.' }],
          max_tokens: 16,
          temperature: 0.2,
          top_p: 0.95,
          stream: true,
          created_at_ms: Date.now(),
        },
        md
      )
    );
    // eslint-disable-next-line no-console
    console.log('Generate(paid, with grant) events:', genPaidOkEvents);
  }

  // Allow push events to flush, then cancel subscription.
  await sleep(200);
  try {
    sub.cancel();
  } catch {
    // ignore
  }
  // eslint-disable-next-line no-console
  console.log(`Pushed events captured: ${pushed.length}`);
}

main().catch((e) => {
  // eslint-disable-next-line no-console
  console.error('smoke failed:', e);
  process.exit(1);
});
