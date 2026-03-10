import fs from 'node:fs';

import grpc from '@grpc/grpc-js';

import { tlsModeFromEnv, tlsServerNameFromEnv } from './tls_support.js';

function safeString(v) {
  return String(v ?? '').trim();
}

function readFileBuf(fp) {
  return fs.readFileSync(String(fp || ''));
}

function grpcMaxMessageBytesFromEnv(env = process.env) {
  const raw = safeString(env.HUB_GRPC_MAX_MESSAGE_MB || env.HUB_GRPC_MAX_MSG_MB || '');
  const mb = raw ? Number.parseInt(raw, 10) : 0;
  if (!Number.isFinite(mb) || mb <= 0) return 32 * 1024 * 1024; // match server default
  return Math.max(4 * 1024 * 1024, Math.min(256 * 1024 * 1024, mb * 1024 * 1024));
}

export function makeClientCredentials(env = process.env) {
  const mode = tlsModeFromEnv(env);
  const maxMsg = grpcMaxMessageBytesFromEnv(env);
  const sizeOpts = {
    'grpc.max_receive_message_length': maxMsg,
    'grpc.max_send_message_length': maxMsg,
  };
  if (mode === 'insecure') {
    return { mode, creds: grpc.credentials.createInsecure(), options: sizeOpts };
  }

  const caPath = safeString(env.HUB_GRPC_TLS_CA_CERT_PATH || env.HUB_TLS_CA_CERT_PATH || '');
  if (!caPath) {
    throw new Error('Missing HUB_GRPC_TLS_CA_CERT_PATH (required for TLS/mTLS)');
  }
  const rootCerts = readFileBuf(caPath);

  if (mode === 'tls') {
    const serverName = tlsServerNameFromEnv(env);
    return {
      mode,
      creds: grpc.credentials.createSsl(rootCerts),
      options: serverName
        ? {
            'grpc.ssl_target_name_override': serverName,
            'grpc.default_authority': serverName,
            ...sizeOpts,
          }
        : sizeOpts,
    };
  }

  // mtls
  const certPath = safeString(env.HUB_GRPC_TLS_CLIENT_CERT_PATH || env.HUB_TLS_CLIENT_CERT_PATH || '');
  const keyPath = safeString(env.HUB_GRPC_TLS_CLIENT_KEY_PATH || env.HUB_TLS_CLIENT_KEY_PATH || '');
  if (!certPath || !keyPath) {
    throw new Error('Missing HUB_GRPC_TLS_CLIENT_CERT_PATH/HUB_GRPC_TLS_CLIENT_KEY_PATH (required for mTLS)');
  }
  const clientCert = readFileBuf(certPath);
  const clientKey = readFileBuf(keyPath);
  const serverName = tlsServerNameFromEnv(env);
  return {
    mode,
    creds: grpc.credentials.createSsl(rootCerts, clientKey, clientCert),
    options: serverName
      ? {
          'grpc.ssl_target_name_override': serverName,
          'grpc.default_authority': serverName,
          ...sizeOpts,
        }
      : sizeOpts,
  };
}
