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
  if (tok) {
    md.set('authorization', `Bearer ${tok}`);
  }
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

async function main() {
  const host = (process.env.HUB_HOST || '127.0.0.1').trim();
  const port = Number(process.env.HUB_PORT || 50051);
  const addr = `${host}:${port}`;

  const proto = loadProto(resolveHubProtoPath(process.env));
  if (!proto?.HubModels) {
    throw new Error('failed to load HubModels service from proto');
  }

  const md = metadataFromEnv();
  const { creds, options } = makeClientCredentials(process.env);
  const modelsClient = new proto.HubModels(addr, creds, options);

  const resp = await new Promise((resolve, reject) => {
    modelsClient.ListModels({ client: reqClientFromEnv() }, md, (err, out) => {
      if (err) reject(err);
      else resolve(out);
    });
  });

  const models = Array.isArray(resp?.models) ? resp.models : [];
  const trustProfilePresent = !!resp?.trust_profile_present;
  const paidModelPolicyMode = String(resp?.paid_model_policy_mode || '').trim() || 'unspecified';
  const dailyTokenLimit = Math.max(0, Number(resp?.daily_token_limit || 0) || 0);
  const singleRequestTokenLimit = Math.max(0, Number(resp?.single_request_token_limit || 0) || 0);
  // eslint-disable-next-line no-console
  console.log(`Hub connected: ${addr}`);
  // eslint-disable-next-line no-console
  console.log(`[paid-access] trust_profile_present=${trustProfilePresent ? 'true' : 'false'} paid_model_policy_mode=${paidModelPolicyMode} daily_token_limit=${dailyTokenLimit} single_request_token_limit=${singleRequestTokenLimit}`);
  // eslint-disable-next-line no-console
  console.log(`Models: ${models.length}`);
  for (const m of models) {
    const id = String(m?.model_id || '');
    const name = String(m?.name || id);
    const kind = String(m?.kind || '');
    const backend = String(m?.backend || '');
    const vis = String(m?.visibility || '');
    // eslint-disable-next-line no-console
    console.log(`- ${name} | ${id} | ${kind} | ${backend} | ${vis}`);
  }
}

main().catch((e) => {
  // eslint-disable-next-line no-console
  console.error('list-models failed:', e?.message || e);
  process.exit(1);
});
