import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import https from 'node:https';
import path from 'node:path';
import { URL, URLSearchParams } from 'node:url';

import { importAuthDir, listProviderKeys } from './provider_key_store.js';
import {
  DEFAULT_ANTIGRAVITY_OAUTH_CLIENT_ID,
  DEFAULT_ANTIGRAVITY_OAUTH_CLIENT_SECRET,
  DEFAULT_CLAUDE_OAUTH_CLIENT_ID,
  DEFAULT_GEMINI_OAUTH_CLIENT_ID,
  DEFAULT_GEMINI_OAUTH_CLIENT_SECRET,
  DEFAULT_OPENAI_OAUTH_CLIENT_ID,
} from './provider_key_refresh_executors.js';

const SESSION_TTL_MS = 10 * 60 * 1000;
const RESULT_TTL_MS = 15 * 60 * 1000;
const SESSION_PURGE_GRACE_MS = 60 * 1000;
const HTTP_TIMEOUT_MS = 20_000;
const MANAGED_AUTH_DIRNAME = 'provider_key_oauth_auth';

const OPENAI_AUTH_URL = 'https://auth.openai.com/oauth/authorize';
const OPENAI_TOKEN_URL = 'https://auth.openai.com/oauth/token';
const OPENAI_REDIRECT_URI = 'http://localhost:1455/auth/callback';
const OPENAI_SCOPE = 'openid email profile offline_access';

const CLAUDE_AUTH_URL = 'https://claude.ai/oauth/authorize';
const CLAUDE_TOKEN_URL = 'https://api.anthropic.com/v1/oauth/token';
const CLAUDE_REDIRECT_URI = 'http://localhost:54545/callback';
const CLAUDE_SCOPE = 'user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload';

const GOOGLE_AUTH_URL = 'https://accounts.google.com/o/oauth2/v2/auth';
const GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token';
const GOOGLE_USERINFO_URL = 'https://www.googleapis.com/oauth2/v1/userinfo?alt=json';

const GEMINI_REDIRECT_URI = 'http://localhost:8085/oauth2callback';
const GEMINI_SCOPE = [
  'https://www.googleapis.com/auth/cloud-platform',
  'https://www.googleapis.com/auth/userinfo.email',
  'https://www.googleapis.com/auth/userinfo.profile',
];

const ANTIGRAVITY_REDIRECT_URI = 'http://localhost:51121/oauth-callback';
const ANTIGRAVITY_SCOPE = [
  'https://www.googleapis.com/auth/cloud-platform',
  'https://www.googleapis.com/auth/userinfo.email',
  'https://www.googleapis.com/auth/userinfo.profile',
  'https://www.googleapis.com/auth/cclog',
  'https://www.googleapis.com/auth/experimentsandconfigs',
];

function safeString(value) {
  return String(value ?? '').trim();
}

function safeInt(value, fallback = 0) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(0, Math.floor(number));
}

function safeObject(value) {
  return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
}

function nowMs() {
  return Date.now();
}

function normalizeProvider(raw) {
  const value = safeString(raw).toLowerCase();
  switch (value) {
    case 'openai':
    case 'codex':
    case 'chatgpt':
    case 'openai-chatgpt':
      return 'codex';
    case 'anthropic':
    case 'claude':
      return 'claude';
    case 'gemini':
    case 'google':
      return 'gemini';
    case 'antigravity':
    case 'anti-gravity':
      return 'antigravity';
    default:
      return '';
  }
}

function defaultRedirectURIForProvider(provider) {
  switch (provider) {
    case 'codex':
      return OPENAI_REDIRECT_URI;
    case 'claude':
      return CLAUDE_REDIRECT_URI;
    case 'gemini':
      return GEMINI_REDIRECT_URI;
    case 'antigravity':
      return ANTIGRAVITY_REDIRECT_URI;
    default:
      return '';
  }
}

function normalizeRedirectURI(provider, raw) {
  const candidate = safeString(raw) || defaultRedirectURIForProvider(provider);
  if (!candidate) return { ok: false, error: 'missing_redirect_uri', redirect_uri: '' };
  let parsed;
  try {
    parsed = new URL(candidate);
  } catch {
    return { ok: false, error: 'invalid_redirect_uri', redirect_uri: '' };
  }
  const protocol = safeString(parsed.protocol).toLowerCase();
  const host = safeString(parsed.hostname).toLowerCase();
  if (protocol !== 'http:' || !['localhost', '127.0.0.1', '::1'].includes(host)) {
    return { ok: false, error: 'redirect_uri_must_be_localhost_http', redirect_uri: '' };
  }
  if (parsed.username || parsed.password) {
    return { ok: false, error: 'redirect_uri_invalid_auth', redirect_uri: '' };
  }
  if (!safeString(parsed.pathname)) {
    parsed.pathname = '/';
  }
  parsed.search = '';
  parsed.hash = '';
  return { ok: true, error: '', redirect_uri: parsed.toString() };
}

function redactErrorForStatus(error) {
  const text = safeString(error);
  if (!text) return 'oauth_login_failed';
  return text.length > 240 ? `${text.slice(0, 237)}...` : text;
}

function generateState() {
  return crypto.randomBytes(18).toString('base64url');
}

function generatePKCEVerifier() {
  return crypto.randomBytes(48).toString('base64url');
}

function buildPKCEChallenge(verifier) {
  return crypto.createHash('sha256').update(String(verifier || ''), 'utf8').digest('base64url');
}

function decodeJwtPayload(token) {
  const raw = safeString(token);
  if (!raw) return null;
  const parts = raw.split('.');
  if (parts.length < 2) return null;
  try {
    const normalized = parts[1]
      .replace(/-/g, '+')
      .replace(/_/g, '/')
      .padEnd(Math.ceil(parts[1].length / 4) * 4, '=');
    const decoded = Buffer.from(normalized, 'base64').toString('utf8');
    const payload = JSON.parse(decoded);
    return payload && typeof payload === 'object' && !Array.isArray(payload) ? payload : null;
  } catch {
    return null;
  }
}

function sanitizeFilenamePart(raw, fallback = 'account') {
  const text = safeString(raw)
    .toLowerCase()
    .replace(/[^a-z0-9._@-]+/g, '_')
    .replace(/^_+|_+$/g, '');
  return text || fallback;
}

function managedAuthDir(runtimeBaseDir) {
  return path.join(path.resolve(String(runtimeBaseDir || '.')), MANAGED_AUTH_DIRNAME);
}

function writeJsonFileAtomic(filePath, payload) {
  const target = path.resolve(String(filePath || ''));
  const dir = path.dirname(target);
  fs.mkdirSync(dir, { recursive: true });
  const tmp = `${target}.${process.pid}.${crypto.randomBytes(4).toString('hex')}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(payload, null, 2) + '\n', 'utf8');
  fs.renameSync(tmp, target);
  return target;
}

function createSessionSnapshot(session, overrideStatus = '') {
  if (!session) {
    return {
      ok: false,
      error: 'unknown_oauth_state',
      provider: '',
      state: '',
      status: 'unknown',
      expires_at_ms: 0,
      updated_at_ms: 0,
      auth_url: '',
      redirect_uri: '',
      status_message: '',
      account_key: '',
      email: '',
      auth_file_path: '',
      imported: 0,
    };
  }
  return {
    ok: session.status === 'ok',
    error: session.status === 'error' || overrideStatus === 'expired'
      ? safeString(session.error || session.status_message || 'oauth_login_failed')
      : '',
    provider: session.provider,
    state: session.state,
    status: overrideStatus || session.status,
    expires_at_ms: session.expires_at_ms,
    updated_at_ms: session.updated_at_ms,
    auth_url: session.auth_url,
    redirect_uri: session.redirect_uri,
    status_message: safeString(session.status_message),
    account_key: safeString(session.account_key),
    email: safeString(session.email),
    auth_file_path: safeString(session.auth_file_path),
    imported: safeInt(session.imported, 0),
  };
}

function purgeExpiredSessions(sessions) {
  const current = nowMs();
  for (const [state, session] of sessions.entries()) {
    if (!session || typeof session !== 'object') {
      sessions.delete(state);
      continue;
    }
    if (current <= safeInt(session.expires_at_ms, 0)) continue;
    if ((session.status === 'pending' || session.status === 'processing') && session.status !== 'expired') {
      session.status = 'expired';
      session.error = session.error || 'oauth_login_expired';
      session.status_message = session.status_message || 'OAuth login expired before completion';
      session.updated_at_ms = current;
      session.expires_at_ms = current + SESSION_PURGE_GRACE_MS;
      continue;
    }
    if (current > safeInt(session.expires_at_ms, 0) + SESSION_PURGE_GRACE_MS) {
      sessions.delete(state);
    }
  }
}

function normalizeHttpResponse(raw) {
  if (!raw || typeof raw !== 'object') {
    return { statusCode: 0, headers: {}, bodyText: '', json: null };
  }
  let bodyText = '';
  if (typeof raw.bodyText === 'string') bodyText = raw.bodyText;
  else if (typeof raw.body === 'string') bodyText = raw.body;
  else if (Buffer.isBuffer(raw.body)) bodyText = raw.body.toString('utf8');
  else if (raw.body && typeof raw.body === 'object') {
    try {
      bodyText = JSON.stringify(raw.body);
    } catch {
      bodyText = '';
    }
  }
  let parsed = null;
  try {
    parsed = JSON.parse(bodyText);
  } catch {
    parsed = null;
  }
  return {
    statusCode: safeInt(raw.statusCode ?? raw.status, 0),
    headers: safeObject(raw.headers),
    bodyText,
    json: parsed && typeof parsed === 'object' ? parsed : null,
  };
}

async function executeHttpRequest({
  url,
  method = 'POST',
  headers = {},
  body = '',
  timeoutMs = HTTP_TIMEOUT_MS,
  httpRequestFn,
} = {}) {
  if (typeof httpRequestFn === 'function') {
    return normalizeHttpResponse(await httpRequestFn({
      url: safeString(url),
      method: safeString(method) || 'POST',
      headers: safeObject(headers),
      body: typeof body === 'string' ? body : safeString(body),
      timeoutMs: safeInt(timeoutMs, HTTP_TIMEOUT_MS),
    }));
  }

  const target = new URL(String(url || ''));
  const transport = target.protocol === 'http:' ? http : https;
  const requestBody = typeof body === 'string' ? body : safeString(body);
  const requestHeaders = { ...headers };
  if (requestBody && !Object.keys(requestHeaders).some((key) => key.toLowerCase() === 'content-length')) {
    requestHeaders['Content-Length'] = Buffer.byteLength(requestBody);
  }

  return await new Promise((resolve, reject) => {
    const request = transport.request({
      protocol: target.protocol,
      hostname: target.hostname,
      port: target.port || undefined,
      path: `${target.pathname}${target.search}`,
      method: safeString(method) || 'POST',
      headers: requestHeaders,
    }, (response) => {
      const chunks = [];
      response.on('data', (chunk) => {
        chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
      });
      response.on('end', () => {
        resolve(normalizeHttpResponse({
          statusCode: response.statusCode || 0,
          headers: response.headers || {},
          bodyText: Buffer.concat(chunks).toString('utf8'),
        }));
      });
    });
    request.setTimeout(Math.max(500, safeInt(timeoutMs, HTTP_TIMEOUT_MS)), () => {
      request.destroy(Object.assign(new Error(`oauth request timed out after ${timeoutMs}ms`), { code: 'ETIMEDOUT' }));
    });
    request.on('error', (error) => reject(error));
    if (requestBody) request.write(requestBody);
    request.end();
  });
}

function httpErrorFromResponse(response, fallback = 'oauth_request_failed') {
  const payload = response?.json && typeof response.json === 'object' ? response.json : {};
  const detail = safeString(
    payload.error_description
    || payload.detail
    || payload.message
    || payload.error?.message
    || payload.error
    || response?.bodyText
    || fallback
  );
  const statusCode = safeInt(response?.statusCode, 0);
  return new Error(statusCode > 0 ? `${detail} (status=${statusCode})` : detail || fallback);
}

async function fetchGoogleUserInfo(accessToken, options = {}) {
  const response = await executeHttpRequest({
    url: GOOGLE_USERINFO_URL,
    method: 'GET',
    headers: {
      Accept: 'application/json',
      Authorization: `Bearer ${safeString(accessToken)}`,
    },
    timeoutMs: HTTP_TIMEOUT_MS,
    httpRequestFn: options.httpRequestFn,
  });
  if (safeInt(response.statusCode, 0) >= 400) {
    throw httpErrorFromResponse(response, 'google_userinfo_failed');
  }
  return response.json && typeof response.json === 'object' ? response.json : {};
}

async function exchangeCodexCode(session, code, options = {}) {
  const requestBody = new URLSearchParams();
  requestBody.set('grant_type', 'authorization_code');
  requestBody.set('client_id', DEFAULT_OPENAI_OAUTH_CLIENT_ID);
  requestBody.set('code', safeString(code));
  requestBody.set('redirect_uri', session.redirect_uri);
  requestBody.set('code_verifier', session.pkce_verifier);

  const response = await executeHttpRequest({
    url: OPENAI_TOKEN_URL,
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: requestBody.toString(),
    timeoutMs: HTTP_TIMEOUT_MS,
    httpRequestFn: options.httpRequestFn,
  });
  if (safeInt(response.statusCode, 0) >= 400) {
    throw httpErrorFromResponse(response, 'codex_token_exchange_failed');
  }

  const payload = response.json && typeof response.json === 'object' ? response.json : {};
  const accessToken = safeString(payload.access_token);
  const refreshToken = safeString(payload.refresh_token);
  if (!accessToken || !refreshToken) {
    throw new Error('codex token exchange response missing access_token or refresh_token');
  }

  const idClaims = decodeJwtPayload(payload.id_token) || {};
  const email = safeString(idClaims.email || idClaims.preferred_username || payload.email);
  const accountID = safeString(idClaims.chatgpt_account_id || idClaims.account_id || payload.account_id);
  const expiresAt = safeInt(payload.expires_in, 0) > 0
    ? new Date(nowMs() + safeInt(payload.expires_in, 0) * 1000).toISOString()
    : '';

  return {
    email,
    account_id: accountID,
    auth_payload: {
      provider: 'codex',
      oauth_source: 'chatgpt',
      token_type: 'bearer',
      access_token: accessToken,
      refresh_token: refreshToken,
      id_token: safeString(payload.id_token),
      email,
      account_id: accountID,
      expires_at: expiresAt,
    },
  };
}

async function exchangeClaudeCode(session, code, options = {}) {
  const response = await executeHttpRequest({
    url: CLAUDE_TOKEN_URL,
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      code: safeString(code),
      state: session.state,
      grant_type: 'authorization_code',
      client_id: DEFAULT_CLAUDE_OAUTH_CLIENT_ID,
      redirect_uri: session.redirect_uri,
      code_verifier: session.pkce_verifier,
    }),
    timeoutMs: HTTP_TIMEOUT_MS,
    httpRequestFn: options.httpRequestFn,
  });
  if (safeInt(response.statusCode, 0) >= 400) {
    throw httpErrorFromResponse(response, 'claude_token_exchange_failed');
  }

  const payload = response.json && typeof response.json === 'object' ? response.json : {};
  const accessToken = safeString(payload.access_token);
  const refreshToken = safeString(payload.refresh_token);
  if (!accessToken || !refreshToken) {
    throw new Error('claude token exchange response missing access_token or refresh_token');
  }
  const email = safeString(payload.account?.email_address);
  const accountID = safeString(payload.account?.uuid);
  const expiresAt = safeInt(payload.expires_in, 0) > 0
    ? new Date(nowMs() + safeInt(payload.expires_in, 0) * 1000).toISOString()
    : '';

  return {
    email,
    account_id: accountID,
    auth_payload: {
      provider: 'claude',
      oauth_source: 'claude',
      token_type: 'bearer',
      access_token: accessToken,
      refresh_token: refreshToken,
      email,
      account_id: accountID,
      expires_at: expiresAt,
    },
  };
}

async function exchangeGoogleAuthorizationCode({
  clientID,
  clientSecret,
  redirectURI,
  code,
  httpRequestFn,
} = {}) {
  const requestBody = new URLSearchParams();
  requestBody.set('code', safeString(code));
  requestBody.set('client_id', safeString(clientID));
  requestBody.set('client_secret', safeString(clientSecret));
  requestBody.set('redirect_uri', safeString(redirectURI));
  requestBody.set('grant_type', 'authorization_code');

  const response = await executeHttpRequest({
    url: GOOGLE_TOKEN_URL,
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: requestBody.toString(),
    timeoutMs: HTTP_TIMEOUT_MS,
    httpRequestFn,
  });
  if (safeInt(response.statusCode, 0) >= 400) {
    throw httpErrorFromResponse(response, 'google_token_exchange_failed');
  }

  const payload = response.json && typeof response.json === 'object' ? response.json : {};
  const accessToken = safeString(payload.access_token);
  const refreshToken = safeString(payload.refresh_token);
  if (!accessToken || !refreshToken) {
    throw new Error('google token exchange response missing access_token or refresh_token');
  }
  return payload;
}

async function exchangeGeminiCode(session, code, options = {}) {
  const tokenPayload = await exchangeGoogleAuthorizationCode({
    clientID: DEFAULT_GEMINI_OAUTH_CLIENT_ID,
    clientSecret: DEFAULT_GEMINI_OAUTH_CLIENT_SECRET,
    redirectURI: session.redirect_uri,
    code,
    httpRequestFn: options.httpRequestFn,
  });
  const userInfo = await fetchGoogleUserInfo(tokenPayload.access_token, options);
  const email = safeString(userInfo.email);
  const accountID = safeString(userInfo.id || decodeJwtPayload(tokenPayload.id_token)?.sub);
  const expiresAt = safeInt(tokenPayload.expires_in, 0) > 0
    ? new Date(nowMs() + safeInt(tokenPayload.expires_in, 0) * 1000).toISOString()
    : '';

  return {
    email,
    account_id: accountID,
    auth_payload: {
      provider: 'gemini',
      oauth_source: 'gemini',
      token_type: 'bearer',
      access_token: safeString(tokenPayload.access_token),
      refresh_token: safeString(tokenPayload.refresh_token),
      email,
      account_id: accountID,
      expires_at: expiresAt,
      oauth_refresh_config: {
        token_uri: GOOGLE_TOKEN_URL,
        client_id: DEFAULT_GEMINI_OAUTH_CLIENT_ID,
        client_secret: DEFAULT_GEMINI_OAUTH_CLIENT_SECRET,
        scopes: GEMINI_SCOPE,
        universe_domain: 'googleapis.com',
      },
    },
  };
}

async function exchangeAntigravityCode(session, code, options = {}) {
  const tokenPayload = await exchangeGoogleAuthorizationCode({
    clientID: DEFAULT_ANTIGRAVITY_OAUTH_CLIENT_ID,
    clientSecret: DEFAULT_ANTIGRAVITY_OAUTH_CLIENT_SECRET,
    redirectURI: session.redirect_uri,
    code,
    httpRequestFn: options.httpRequestFn,
  });
  const userInfo = await fetchGoogleUserInfo(tokenPayload.access_token, options);
  const email = safeString(userInfo.email);
  const accountID = safeString(userInfo.id || decodeJwtPayload(tokenPayload.id_token)?.sub);
  const expiresAt = safeInt(tokenPayload.expires_in, 0) > 0
    ? new Date(nowMs() + safeInt(tokenPayload.expires_in, 0) * 1000).toISOString()
    : '';

  return {
    email,
    account_id: accountID,
    auth_payload: {
      provider: 'antigravity',
      oauth_source: 'antigravity',
      token_type: 'bearer',
      access_token: safeString(tokenPayload.access_token),
      refresh_token: safeString(tokenPayload.refresh_token),
      email,
      account_id: accountID,
      expires_at: expiresAt,
      oauth_refresh_config: {
        token_uri: GOOGLE_TOKEN_URL,
        client_id: DEFAULT_ANTIGRAVITY_OAUTH_CLIENT_ID,
        client_secret: DEFAULT_ANTIGRAVITY_OAUTH_CLIENT_SECRET,
      },
    },
  };
}

function buildCodexAuthURL(session) {
  const params = new URLSearchParams();
  params.set('client_id', DEFAULT_OPENAI_OAUTH_CLIENT_ID);
  params.set('response_type', 'code');
  params.set('redirect_uri', session.redirect_uri);
  params.set('scope', OPENAI_SCOPE);
  params.set('state', session.state);
  params.set('code_challenge', session.pkce_challenge);
  params.set('code_challenge_method', 'S256');
  params.set('prompt', 'login');
  params.set('id_token_add_organizations', 'true');
  params.set('codex_cli_simplified_flow', 'true');
  return `${OPENAI_AUTH_URL}?${params.toString()}`;
}

function buildClaudeAuthURL(session) {
  const params = new URLSearchParams();
  params.set('code', 'true');
  params.set('client_id', DEFAULT_CLAUDE_OAUTH_CLIENT_ID);
  params.set('response_type', 'code');
  params.set('redirect_uri', session.redirect_uri);
  params.set('scope', CLAUDE_SCOPE);
  params.set('code_challenge', session.pkce_challenge);
  params.set('code_challenge_method', 'S256');
  params.set('state', session.state);
  return `${CLAUDE_AUTH_URL}?${params.toString()}`;
}

function buildGoogleAuthURL({ clientID, redirectURI, scope, state }) {
  const params = new URLSearchParams();
  params.set('client_id', safeString(clientID));
  params.set('redirect_uri', safeString(redirectURI));
  params.set('response_type', 'code');
  params.set('scope', scope.join(' '));
  params.set('state', safeString(state));
  params.set('access_type', 'offline');
  params.set('prompt', 'consent');
  return `${GOOGLE_AUTH_URL}?${params.toString()}`;
}

function buildAuthURLForSession(session) {
  switch (session.provider) {
    case 'codex':
      return buildCodexAuthURL(session);
    case 'claude':
      return buildClaudeAuthURL(session);
    case 'gemini':
      return buildGoogleAuthURL({
        clientID: DEFAULT_GEMINI_OAUTH_CLIENT_ID,
        redirectURI: session.redirect_uri,
        scope: GEMINI_SCOPE,
        state: session.state,
      });
    case 'antigravity':
      return buildGoogleAuthURL({
        clientID: DEFAULT_ANTIGRAVITY_OAUTH_CLIENT_ID,
        redirectURI: session.redirect_uri,
        scope: ANTIGRAVITY_SCOPE,
        state: session.state,
      });
    default:
      return '';
  }
}

function extractCallbackFields(request = {}) {
  let provider = normalizeProvider(request.provider);
  let state = safeString(request.state);
  let code = safeString(request.code);
  let errorMessage = safeString(request.error);
  const redirectURL = safeString(request.redirect_url);

  if (redirectURL) {
    let parsed;
    try {
      parsed = new URL(redirectURL);
    } catch {
      return { ok: false, error: 'invalid_redirect_url' };
    }
    if (!state) state = safeString(parsed.searchParams.get('state'));
    if (!code) code = safeString(parsed.searchParams.get('code'));
    if (!errorMessage) {
      errorMessage = safeString(
        parsed.searchParams.get('error')
        || parsed.searchParams.get('error_description')
      );
    }
  }

  if (!provider) provider = '';
  if (!state) return { ok: false, error: 'missing_oauth_state' };
  if (!code && !errorMessage) return { ok: false, error: 'missing_oauth_code' };
  return { ok: true, provider, state, code, errorMessage };
}

async function exchangeCodeForProvider(session, code, options = {}) {
  switch (session.provider) {
    case 'codex':
      return await exchangeCodexCode(session, code, options);
    case 'claude':
      return await exchangeClaudeCode(session, code, options);
    case 'gemini':
      return await exchangeGeminiCode(session, code, options);
    case 'antigravity':
      return await exchangeAntigravityCode(session, code, options);
    default:
      throw new Error('unsupported_oauth_provider');
  }
}

function resolveManagedAuthFilePath(runtimeBaseDir, provider, authPayload, session) {
  const dir = managedAuthDir(runtimeBaseDir);
  const label = sanitizeFilenamePart(
    authPayload?.email
      || authPayload?.account_id
      || session?.state
      || 'account'
  );
  return path.join(dir, `${sanitizeFilenamePart(provider, 'oauth')}-${label}.json`);
}

function trackImportedAccount(runtimeBaseDir, provider, authFilePath) {
  const normalizedPath = path.resolve(String(authFilePath || ''));
  const accounts = listProviderKeys(runtimeBaseDir, provider);
  return accounts.find((account) => path.resolve(String(account?.source_ref || '')) === normalizedPath) || null;
}

export function createProviderOAuthManager({
  importAuthDirFn = importAuthDir,
  listProviderKeysFn = listProviderKeys,
  httpRequestFn,
  logger = console,
} = {}) {
  const sessions = new Map();

  async function processCallback(runtimeBaseDir, session, code) {
    try {
      const exchange = await exchangeCodeForProvider(session, code, { httpRequestFn });
      const authFilePath = resolveManagedAuthFilePath(runtimeBaseDir, session.provider, exchange.auth_payload, session);
      writeJsonFileAtomic(authFilePath, exchange.auth_payload);

      const imported = importAuthDirFn(runtimeBaseDir, managedAuthDir(runtimeBaseDir));
      if (imported.ok !== true) {
        throw new Error((imported.errors || []).filter(Boolean).join('; ') || 'provider_key_import_failed');
      }

      const importedAccount = (typeof listProviderKeysFn === 'function'
        ? listProviderKeysFn(runtimeBaseDir, session.provider)
        : []).find((account) => path.resolve(String(account?.source_ref || '')) === path.resolve(authFilePath)) || null;

      session.status = 'ok';
      session.error = '';
      session.status_message = 'OAuth login imported into Hub provider key pool';
      session.account_key = safeString(importedAccount?.account_key);
      session.email = safeString(importedAccount?.email || exchange.email);
      session.auth_file_path = authFilePath;
      session.imported = safeInt(imported.imported, 0);
      session.updated_at_ms = nowMs();
      session.expires_at_ms = session.updated_at_ms + RESULT_TTL_MS;
    } catch (error) {
      session.status = 'error';
      session.error = redactErrorForStatus(error?.message || error);
      session.status_message = session.error;
      session.updated_at_ms = nowMs();
      session.expires_at_ms = session.updated_at_ms + RESULT_TTL_MS;
      if (logger && typeof logger.warn === 'function') {
        logger.warn(`[provider_key_oauth_manager] ${session.provider}:${session.state} failed: ${session.error}`);
      }
    }
  }

  function startLogin(runtimeBaseDir, request = {}) {
    purgeExpiredSessions(sessions);

    const provider = normalizeProvider(request.provider);
    if (!provider) {
      return {
        ok: false,
        error: 'unsupported_oauth_provider',
        provider: '',
        state: '',
        auth_url: '',
        redirect_uri: '',
        status: 'error',
        expires_at_ms: 0,
      };
    }

    const redirect = normalizeRedirectURI(provider, request.redirect_uri);
    if (!redirect.ok) {
      return {
        ok: false,
        error: redirect.error,
        provider,
        state: '',
        auth_url: '',
        redirect_uri: '',
        status: 'error',
        expires_at_ms: 0,
      };
    }

    const createdAtMs = nowMs();
    const state = generateState();
    const pkceVerifier = provider === 'codex' || provider === 'claude'
      ? generatePKCEVerifier()
      : '';
    const session = {
      provider,
      state,
      status: 'pending',
      error: '',
      status_message: 'Waiting for browser callback',
      auth_url: '',
      redirect_uri: redirect.redirect_uri,
      pkce_verifier: pkceVerifier,
      pkce_challenge: pkceVerifier ? buildPKCEChallenge(pkceVerifier) : '',
      account_key: '',
      email: '',
      auth_file_path: '',
      imported: 0,
      created_at_ms: createdAtMs,
      updated_at_ms: createdAtMs,
      expires_at_ms: createdAtMs + SESSION_TTL_MS,
    };
    session.auth_url = buildAuthURLForSession(session);
    if (!session.auth_url) {
      return {
        ok: false,
        error: 'unsupported_oauth_provider',
        provider,
        state: '',
        auth_url: '',
        redirect_uri: '',
        status: 'error',
        expires_at_ms: 0,
      };
    }

    sessions.set(state, session);
    return {
      ok: true,
      error: '',
      provider,
      state,
      auth_url: session.auth_url,
      redirect_uri: session.redirect_uri,
      status: session.status,
      expires_at_ms: session.expires_at_ms,
    };
  }

  function submitCallback(runtimeBaseDir, request = {}) {
    purgeExpiredSessions(sessions);

    const extracted = extractCallbackFields(request);
    if (!extracted.ok) {
      return {
        ok: false,
        error: extracted.error,
        provider: '',
        state: safeString(request.state),
        status: 'error',
      };
    }

    const session = sessions.get(extracted.state);
    if (!session) {
      return {
        ok: false,
        error: 'unknown_oauth_state',
        provider: extracted.provider,
        state: extracted.state,
        status: 'error',
      };
    }

    if (extracted.provider && extracted.provider !== session.provider) {
      return {
        ok: false,
        error: 'oauth_provider_mismatch',
        provider: session.provider,
        state: session.state,
        status: 'error',
      };
    }

    if (session.status !== 'pending') {
      return {
        ok: false,
        error: `oauth_session_not_pending:${session.status}`,
        provider: session.provider,
        state: session.state,
        status: session.status,
      };
    }

    if (extracted.errorMessage) {
      session.status = 'error';
      session.error = redactErrorForStatus(extracted.errorMessage);
      session.status_message = session.error;
      session.updated_at_ms = nowMs();
      session.expires_at_ms = session.updated_at_ms + RESULT_TTL_MS;
      return {
        ok: false,
        error: session.error,
        provider: session.provider,
        state: session.state,
        status: session.status,
      };
    }

    session.status = 'processing';
    session.status_message = 'Hub is exchanging OAuth code and importing credentials';
    session.updated_at_ms = nowMs();
    session.expires_at_ms = session.updated_at_ms + SESSION_TTL_MS;
    void processCallback(runtimeBaseDir, session, extracted.code);

    return {
      ok: true,
      error: '',
      provider: session.provider,
      state: session.state,
      status: session.status,
    };
  }

  function getStatus(request = {}) {
    purgeExpiredSessions(sessions);
    const state = safeString(request.state);
    if (!state) return createSessionSnapshot(null);
    const session = sessions.get(state);
    if (!session) return createSessionSnapshot(null);
    return createSessionSnapshot(session);
  }

  return {
    startLogin,
    submitCallback,
    getStatus,
  };
}
