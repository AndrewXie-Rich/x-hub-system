import path from 'node:path';
import fs from 'node:fs';
import grpc from '@grpc/grpc-js';
import protoLoader from '@grpc/proto-loader';

import { HubDB } from './db.js';
import { HubEventBus } from './event_bus.js';
import { makeServices } from './services.js';
import { startModelsWatcher } from './models_watcher.js';
import { startPairingHTTPServer } from './pairing_http.js';
import { makeServerCredentials, tlsModeFromEnv } from './tls_support.js';
import { resolveHubProtoPath } from './proto_path.js';

function loadProto(protoPath) {
  const packageDef = protoLoader.loadSync(protoPath, {
    keepCase: true, // snake_case fields
    longs: String,
    enums: String, // use enum names
    defaults: true,
    oneofs: true,
  });
  const loaded = grpc.loadPackageDefinition(packageDef);
  // ax.hub.v1
  return loaded?.ax?.hub?.v1;
}

function grpcMaxMessageBytesFromEnv(env = process.env) {
  const raw = String(env.HUB_GRPC_MAX_MESSAGE_MB || env.HUB_GRPC_MAX_MSG_MB || '').trim();
  const mb = raw ? Number.parseInt(raw, 10) : 0;
  if (!Number.isFinite(mb) || mb <= 0) return 32 * 1024 * 1024; // 32MB default
  return Math.max(4 * 1024 * 1024, Math.min(256 * 1024 * 1024, mb * 1024 * 1024));
}

function main() {
  const host = (process.env.HUB_HOST || '0.0.0.0').trim();
  const port = Number(process.env.HUB_PORT || 50051);
  const dbPath = (process.env.HUB_DB_PATH || './data/hub.sqlite3').trim();
  const tlsMode = tlsModeFromEnv(process.env);

  fs.mkdirSync(path.dirname(dbPath), { recursive: true });

  const protoPath = resolveHubProtoPath(process.env);
  if (!fs.existsSync(protoPath)) {
    throw new Error(`proto not found: ${protoPath}`);
  }

  const proto = loadProto(protoPath);
  if (!proto) {
    throw new Error('failed to load proto package ax.hub.v1');
  }

  const db = new HubDB({ dbPath });
  const bus = new HubEventBus();
  const impl = makeServices({ db, bus });
  const stopModelsWatcher = startModelsWatcher({ bus });
  const stopPairingHTTP = startPairingHTTPServer({ db });

  const maxMsg = grpcMaxMessageBytesFromEnv(process.env);
  const server = new grpc.Server({
    'grpc.max_receive_message_length': maxMsg,
    'grpc.max_send_message_length': maxMsg,
  });
  server.addService(proto.HubModels.service, impl.HubModels);
  server.addService(proto.HubGrants.service, impl.HubGrants);
  server.addService(proto.HubAI.service, impl.HubAI);
  server.addService(proto.HubWeb.service, impl.HubWeb);
  server.addService(proto.HubEvents.service, impl.HubEvents);
  if (proto.HubRuntime && impl.HubRuntime) {
    server.addService(proto.HubRuntime.service, impl.HubRuntime);
  }
  if (proto.HubSupervisor && impl.HubSupervisor) {
    server.addService(proto.HubSupervisor.service, impl.HubSupervisor);
  }
  server.addService(proto.HubAudit.service, impl.HubAudit);
  server.addService(proto.HubMemory.service, impl.HubMemory);
  if (proto.HubSkills && impl.HubSkills) {
    server.addService(proto.HubSkills.service, impl.HubSkills);
  }
  server.addService(proto.HubAdmin.service, impl.HubAdmin);

  const addr = `${host}:${port}`;
  const { creds } = makeServerCredentials({ runtimeBaseDir: process.env.HUB_RUNTIME_BASE_DIR || '' });
  server.bindAsync(addr, creds, (err) => {
    if (err) throw err;
    server.start();
    // eslint-disable-next-line no-console
    console.log(`[hub_grpc] listening on ${addr} tls=${tlsMode}`);
    // eslint-disable-next-line no-console
    console.log(`[hub_grpc] db=${dbPath}`);
    // eslint-disable-next-line no-console
    console.log(`[hub_grpc] proto=${protoPath}`);
  });

  // Graceful shutdown.
  const shutdown = () => {
    try {
      try {
        stopModelsWatcher?.();
      } catch {
        // ignore
      }
      try {
        stopPairingHTTP?.();
      } catch {
        // ignore
      }
      server.tryShutdown(() => {
        db.close();
        process.exit(0);
      });
    } catch {
      process.exit(0);
    }
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main();
