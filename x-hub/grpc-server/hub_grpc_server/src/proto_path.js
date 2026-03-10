import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

function safeString(v) {
  return String(v ?? '').trim();
}

// Resolve the hub_protocol_v1.proto path across multiple layouts:
// - Packaged app Resources/ layout (protocol/ is a sibling of hub_grpc_server/)
// - Repo layout (protocol/ lives at repo root)
// - Legacy layout (protocol/ lives next to hub_grpc_server/)
export function resolveHubProtoPath(env = process.env) {
  const override = safeString(env?.HUB_PROTO_PATH);
  if (override && fs.existsSync(override)) return override;

  const here = path.dirname(fileURLToPath(import.meta.url)); // .../hub_grpc_server/src
  const candidates = [
    // Legacy: .../hub_grpc_server/src -> .../hub_grpc_server/../protocol
    path.resolve(here, '..', '..', 'protocol', 'hub_protocol_v1.proto'),
    // Packaged app: .../Resources/hub_grpc_server/src -> .../Resources/protocol
    path.resolve(here, '..', '..', '..', 'protocol', 'hub_protocol_v1.proto'),
    // Repo root: .../x-hub/grpc-server/hub_grpc_server/src -> .../x-hub-system/protocol
    path.resolve(here, '..', '..', '..', '..', 'protocol', 'hub_protocol_v1.proto'),
  ];

  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  // Best-effort default for error messages.
  return candidates[0];
}

