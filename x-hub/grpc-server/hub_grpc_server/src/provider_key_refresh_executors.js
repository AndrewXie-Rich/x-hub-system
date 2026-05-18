import http from 'node:http';
import https from 'node:https';
import { URLSearchParams } from 'node:url';

const DEFAULT_OPENAI_OAUTH_REFRESH_URL = 'https://auth.openai.com/oauth/token';
const DEFAULT_OPENAI_OAUTH_CLIENT_ID = 'app_EMoamEEZ73f0CkXaXp7hrann';
const DEFAULT_CLAUDE_OAUTH_REFRESH_URL = 'https://api.anthropic.com/v1/oauth/token';
const DEFAULT_CLAUDE_OAUTH_CLIENT_ID = '9d1c250a-e61b-44d9-88ed-5944d1962f5e';
const DEFAULT_GEMINI_OAUTH_REFRESH_URL = 'https://oauth2.googleapis.com/token';
const DEFAULT_GEMINI_OAUTH_CLIENT_ID = '';
const DEFAULT_GEMINI_OAUTH_CLIENT_SECRET = '';
const DEFAULT_ANTIGRAVITY_OAUTH_REFRESH_URL = 'https://oauth2.googleapis.com/token';
const DEFAULT_ANTIGRAVITY_OAUTH_CLIENT_ID = '';
const DEFAULT_ANTIGRAVITY_OAUTH_CLIENT_SECRET = '';
const DEFAULT_KIRO_OAUTH_REFRESH_URL = 'https://prod.us-east-1.auth.desktop.kiro.dev/refreshToken';
const DEFAULT_KIRO_ACCESS_TOKEN_TTL_MS = 60 * 60 * 1000;
const DEFAULT_REFRESH_TIMEOUT_MS = 20_000;

const OPENAI_OAUTH_SOURCES = new Set([
  'chatgpt',
  'openai-chatgpt',
  'openai',
  'codex',
]);

const CLAUDE_OAUTH_SOURCES = new Set([
  'claude',
  'anthropic',
]);

const GEMINI_OAUTH_SOURCES = new Set([
  'gemini',
  'gemini-cli',
  'google',
]);

const ANTIGRAVITY_OAUTH_SOURCES = new Set([
  'antigravity',
]);

const KIRO_OAUTH_SOURCES = new Set([
  'kiro',
]);

function safeString(value) {
  return String(value ?? '').trim();
}

function safeInt(value, fallback = 0) {
  const number = Number(value || 0);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(0, Math.floor(number));
}

function sanitizeReasonCode(value, fallback = 'refresh_failed') {
  const normalized = safeString(value)
    .toLowerCase()
    .replace(/[^a-z0-9._:-]+/g, '_')
    .replace(/^_+|_+$/g, '');
  return normalized || fallback;
}

function truncateText(value, maxLength = 400) {
  const normalized = safeString(value);
  if (!normalized) return '';
  return normalized.length > maxLength
    ? `${normalized.slice(0, Math.max(0, maxLength - 3))}...`
    : normalized;
}

function parseJsonSafe(value) {
  const raw = safeString(value);
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === 'object' ? parsed : null;
  } catch {
    return null;
  }
}

function oauthRefreshConfigFromAccount(account) {
  return account?.oauth_refresh_config
    && typeof account.oauth_refresh_config === 'object'
    && !Array.isArray(account.oauth_refresh_config)
    ? account.oauth_refresh_config
    : {};
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
    return payload && typeof payload === 'object' ? payload : null;
  } catch {
    return null;
  }
}

function createRefreshError({
  code,
  message,
  statusCode = 0,
  details = '',
} = {}) {
  const error = new Error(safeString(message) || safeString(code) || 'refresh_failed');
  error.code = sanitizeReasonCode(code, 'refresh_failed');
  error.error_code = error.code;
  error.status_message = truncateText(details || message || code || 'refresh_failed');
  if (statusCode > 0) {
    error.http_status = statusCode;
  }
  return error;
}

function normalizeHttpResponse(raw) {
  if (!raw || typeof raw !== 'object') {
    return { statusCode: 0, headers: {}, bodyText: '', json: null };
  }
  const statusCode = safeInt(raw.statusCode ?? raw.status, 0);
  const headers = raw.headers && typeof raw.headers === 'object' ? raw.headers : {};
  let bodyText = '';
  if (typeof raw.bodyText === 'string') {
    bodyText = raw.bodyText;
  } else if (typeof raw.body === 'string') {
    bodyText = raw.body;
  } else if (Buffer.isBuffer(raw.body)) {
    bodyText = raw.body.toString('utf8');
  } else if (raw.body && typeof raw.body === 'object') {
    try {
      bodyText = JSON.stringify(raw.body);
    } catch {
      bodyText = '';
    }
  }
  return {
    statusCode,
    headers,
    bodyText,
    json: parseJsonSafe(bodyText),
  };
}

async function executeHttpRequest({
  url,
  method = 'POST',
  headers = {},
  body = '',
  timeoutMs = DEFAULT_REFRESH_TIMEOUT_MS,
  httpRequestFn,
} = {}) {
  if (typeof httpRequestFn === 'function') {
    return normalizeHttpResponse(await httpRequestFn({
      url: safeString(url),
      method: safeString(method) || 'POST',
      headers: { ...headers },
      body: typeof body === 'string' ? body : safeString(body),
      timeoutMs: safeInt(timeoutMs, DEFAULT_REFRESH_TIMEOUT_MS),
    }));
  }

  const requestURL = safeString(url);
  if (!requestURL) {
    throw createRefreshError({
      code: 'invalid_refresh_url',
      message: 'missing refresh url',
    });
  }

  const timeout = Math.max(100, safeInt(timeoutMs, DEFAULT_REFRESH_TIMEOUT_MS));
  const bodyText = typeof body === 'string' ? body : safeString(body);
  const requestHeaders = { ...headers };
  if (bodyText && !Object.keys(requestHeaders).some((key) => key.toLowerCase() === 'content-length')) {
    requestHeaders['Content-Length'] = Buffer.byteLength(bodyText);
  }

  const target = new URL(requestURL);
  const transport = target.protocol === 'http:' ? http : https;

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
        const text = Buffer.concat(chunks).toString('utf8');
        resolve(normalizeHttpResponse({
          statusCode: response.statusCode || 0,
          headers: response.headers || {},
          bodyText: text,
        }));
      });
    });

    request.setTimeout(timeout, () => {
      request.destroy(Object.assign(new Error(`refresh request timed out after ${timeout}ms`), {
        code: 'ETIMEDOUT',
      }));
    });
    request.on('error', (error) => {
      reject(error);
    });
    if (bodyText) {
      request.write(bodyText);
    }
    request.end();
  });
}

function refreshErrorFromResponse(response, url) {
  const statusCode = safeInt(response?.statusCode, 0);
  const payload = response?.json && typeof response.json === 'object' ? response.json : {};
  const bodyText = truncateText(response?.bodyText || '');
  const code = sanitizeReasonCode(
    payload.code
    || payload.error_code
    || payload.error
    || (statusCode > 0 ? `refresh_http_${statusCode}` : 'refresh_failed'),
    statusCode > 0 ? `refresh_http_${statusCode}` : 'refresh_failed'
  );
  const details = truncateText(
    payload.detail
    || payload.error_description
    || payload.message
    || payload.error
    || bodyText
    || (statusCode > 0 ? `refresh request failed with status ${statusCode}` : `refresh request failed for ${safeString(url)}`)
  );
  return createRefreshError({
    code,
    message: details,
    statusCode,
    details,
  });
}

function refreshTimeoutMsFromEnv(env = process.env) {
  const explicit = safeInt(
    env.HUB_PROVIDER_KEY_REFRESH_HTTP_TIMEOUT_MS
    || env.HUB_PROVIDER_KEY_OPENAI_OAUTH_TIMEOUT_MS,
    0
  );
  return explicit > 0 ? explicit : DEFAULT_REFRESH_TIMEOUT_MS;
}

function openAIOAuthClientIDFromEnv(env = process.env) {
  return safeString(
    env.HUB_PROVIDER_KEY_OPENAI_OAUTH_CLIENT_ID
    || env.HUB_CODEX_OAUTH_CLIENT_ID
    || DEFAULT_OPENAI_OAUTH_CLIENT_ID
  ) || DEFAULT_OPENAI_OAUTH_CLIENT_ID;
}

function openAIOAuthRefreshURLFromEnv(env = process.env) {
  return safeString(
    env.HUB_PROVIDER_KEY_OPENAI_OAUTH_TOKEN_URL
    || env.HUB_CODEX_OAUTH_TOKEN_URL
    || DEFAULT_OPENAI_OAUTH_REFRESH_URL
  ) || DEFAULT_OPENAI_OAUTH_REFRESH_URL;
}

function claudeOAuthClientIDFromEnv(env = process.env) {
  return safeString(
    env.HUB_PROVIDER_KEY_CLAUDE_OAUTH_CLIENT_ID
    || env.HUB_CLAUDE_OAUTH_CLIENT_ID
    || DEFAULT_CLAUDE_OAUTH_CLIENT_ID
  ) || DEFAULT_CLAUDE_OAUTH_CLIENT_ID;
}

function claudeOAuthRefreshURLFromEnv(env = process.env) {
  return safeString(
    env.HUB_PROVIDER_KEY_CLAUDE_OAUTH_TOKEN_URL
    || env.HUB_CLAUDE_OAUTH_TOKEN_URL
    || DEFAULT_CLAUDE_OAUTH_REFRESH_URL
  ) || DEFAULT_CLAUDE_OAUTH_REFRESH_URL;
}

function geminiOAuthClientIDFromEnv(account, env = process.env) {
  const accountConfig = oauthRefreshConfigFromAccount(account);
  return safeString(
    accountConfig.client_id
    || env.HUB_PROVIDER_KEY_GEMINI_OAUTH_CLIENT_ID
    || env.GEMINI_CLIENT_ID
    || env.GOOGLE_CLIENT_ID
    || DEFAULT_GEMINI_OAUTH_CLIENT_ID
  ) || DEFAULT_GEMINI_OAUTH_CLIENT_ID;
}

function geminiOAuthClientSecretFromEnv(account, env = process.env) {
  const accountConfig = oauthRefreshConfigFromAccount(account);
  return safeString(
    accountConfig.client_secret
    || env.HUB_PROVIDER_KEY_GEMINI_OAUTH_CLIENT_SECRET
    || env.GEMINI_CLIENT_SECRET
    || env.GOOGLE_CLIENT_SECRET
    || DEFAULT_GEMINI_OAUTH_CLIENT_SECRET
  ) || DEFAULT_GEMINI_OAUTH_CLIENT_SECRET;
}

function geminiOAuthRefreshURLFromEnv(account, env = process.env) {
  const accountConfig = oauthRefreshConfigFromAccount(account);
  return safeString(
    accountConfig.token_uri
    || env.HUB_PROVIDER_KEY_GEMINI_OAUTH_TOKEN_URL
    || DEFAULT_GEMINI_OAUTH_REFRESH_URL
  ) || DEFAULT_GEMINI_OAUTH_REFRESH_URL;
}

function antigravityOAuthClientIDFromEnv(env = process.env) {
  return safeString(
    env.HUB_PROVIDER_KEY_ANTIGRAVITY_OAUTH_CLIENT_ID
    || env.GOOGLE_CLIENT_ID
    || DEFAULT_ANTIGRAVITY_OAUTH_CLIENT_ID
  ) || DEFAULT_ANTIGRAVITY_OAUTH_CLIENT_ID;
}

function antigravityOAuthClientSecretFromEnv(env = process.env) {
  return safeString(
    env.HUB_PROVIDER_KEY_ANTIGRAVITY_OAUTH_CLIENT_SECRET
    || env.GOOGLE_CLIENT_SECRET
    || DEFAULT_ANTIGRAVITY_OAUTH_CLIENT_SECRET
  ) || DEFAULT_ANTIGRAVITY_OAUTH_CLIENT_SECRET;
}

function antigravityOAuthRefreshURLFromEnv(env = process.env) {
  return safeString(
    env.HUB_PROVIDER_KEY_ANTIGRAVITY_OAUTH_TOKEN_URL
    || DEFAULT_ANTIGRAVITY_OAUTH_REFRESH_URL
  ) || DEFAULT_ANTIGRAVITY_OAUTH_REFRESH_URL;
}

function kiroOAuthRefreshURLFromEnv(env = process.env) {
  return safeString(
    env.HUB_PROVIDER_KEY_KIRO_OAUTH_TOKEN_URL
    || DEFAULT_KIRO_OAUTH_REFRESH_URL
  ) || DEFAULT_KIRO_OAUTH_REFRESH_URL;
}

function isOpenAIOAuthAccount(account) {
  if (!account || typeof account !== 'object') return false;
  if (safeString(account.auth_type).toLowerCase() !== 'oauth') return false;
  if (!safeString(account.refresh_token)) return false;

  const provider = safeString(account.provider).toLowerCase();
  const oauthSourceKey = safeString(account.oauth_source_key).toLowerCase();
  const providerHost = safeString(account.provider_host).toLowerCase();

  if (oauthSourceKey && OPENAI_OAUTH_SOURCES.has(oauthSourceKey)) {
    return true;
  }
  if ((provider === 'codex' || provider === 'openai') && (!oauthSourceKey || providerHost === 'api.openai.com')) {
    return true;
  }
  return false;
}

function isClaudeOAuthAccount(account) {
  if (!account || typeof account !== 'object') return false;
  if (safeString(account.auth_type).toLowerCase() !== 'oauth') return false;
  if (!safeString(account.refresh_token)) return false;

  const provider = safeString(account.provider).toLowerCase();
  const oauthSourceKey = safeString(account.oauth_source_key).toLowerCase();
  return provider === 'claude'
    || (oauthSourceKey && CLAUDE_OAUTH_SOURCES.has(oauthSourceKey));
}

function isGeminiOAuthAccount(account) {
  if (!account || typeof account !== 'object') return false;
  if (safeString(account.auth_type).toLowerCase() !== 'oauth') return false;
  if (!safeString(account.refresh_token)) return false;

  const provider = safeString(account.provider).toLowerCase();
  const oauthSourceKey = safeString(account.oauth_source_key).toLowerCase();
  return provider === 'gemini'
    || (oauthSourceKey && GEMINI_OAUTH_SOURCES.has(oauthSourceKey));
}

function isAntigravityOAuthAccount(account) {
  if (!account || typeof account !== 'object') return false;
  if (safeString(account.auth_type).toLowerCase() !== 'oauth') return false;
  if (!safeString(account.refresh_token)) return false;

  const provider = safeString(account.provider).toLowerCase();
  const oauthSourceKey = safeString(account.oauth_source_key).toLowerCase();
  return provider === 'antigravity'
    || (oauthSourceKey && ANTIGRAVITY_OAUTH_SOURCES.has(oauthSourceKey));
}

function isKiroOAuthAccount(account) {
  if (!account || typeof account !== 'object') return false;
  if (safeString(account.auth_type).toLowerCase() !== 'oauth') return false;
  if (!safeString(account.refresh_token)) return false;

  const provider = safeString(account.provider).toLowerCase();
  const oauthSourceKey = safeString(account.oauth_source_key).toLowerCase();
  return provider === 'kiro'
    || (oauthSourceKey && KIRO_OAUTH_SOURCES.has(oauthSourceKey));
}

export function defaultRefreshExecutorForAccount(account, options = {}) {
  if (isOpenAIOAuthAccount(account)) {
    return async (currentAccount, context = {}) => (
      await refreshOpenAIOAuthAccount(currentAccount, {
        env: options.env,
        httpRequestFn: options.httpRequestFn,
        context,
      })
    );
  }
  if (isClaudeOAuthAccount(account)) {
    return async (currentAccount, context = {}) => (
      await refreshClaudeOAuthAccount(currentAccount, {
        env: options.env,
        httpRequestFn: options.httpRequestFn,
        context,
      })
    );
  }
  if (isGeminiOAuthAccount(account)) {
    return async (currentAccount, context = {}) => (
      await refreshGeminiOAuthAccount(currentAccount, {
        env: options.env,
        httpRequestFn: options.httpRequestFn,
        context,
      })
    );
  }
  if (isAntigravityOAuthAccount(account)) {
    return async (currentAccount, context = {}) => (
      await refreshAntigravityOAuthAccount(currentAccount, {
        env: options.env,
        httpRequestFn: options.httpRequestFn,
        context,
      })
    );
  }
  if (isKiroOAuthAccount(account)) {
    return async (currentAccount, context = {}) => (
      await refreshKiroOAuthAccount(currentAccount, {
        env: options.env,
        httpRequestFn: options.httpRequestFn,
        context,
      })
    );
  }
  return null;
}

export async function refreshOpenAIOAuthAccount(account, {
  env = process.env,
  httpRequestFn,
} = {}) {
  const refreshToken = safeString(account?.refresh_token);
  if (!refreshToken) {
    throw createRefreshError({
      code: 'missing_refresh_token',
      message: 'provider key is missing refresh_token',
    });
  }

  const requestBody = new URLSearchParams();
  requestBody.set('client_id', openAIOAuthClientIDFromEnv(env));
  requestBody.set('grant_type', 'refresh_token');
  requestBody.set('refresh_token', refreshToken);
  requestBody.set('scope', 'openid profile email');

  let response;
  try {
    response = await executeHttpRequest({
      url: openAIOAuthRefreshURLFromEnv(env),
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: requestBody.toString(),
      timeoutMs: refreshTimeoutMsFromEnv(env),
      httpRequestFn,
    });
  } catch (error) {
    const code = sanitizeReasonCode(
      error?.code === 'ETIMEDOUT'
        ? 'refresh_timeout'
        : (error?.code || error?.name || 'refresh_request_failed'),
      'refresh_request_failed'
    );
    throw createRefreshError({
      code,
      message: safeString(error?.message || error) || 'refresh request failed',
      details: safeString(error?.message || error) || 'refresh request failed',
    });
  }

  if (safeInt(response.statusCode, 0) >= 400) {
    throw refreshErrorFromResponse(response, openAIOAuthRefreshURLFromEnv(env));
  }

  const payload = response.json && typeof response.json === 'object'
    ? response.json
    : parseJsonSafe(response.bodyText);
  const accessToken = safeString(payload?.access_token);
  if (!accessToken) {
    throw createRefreshError({
      code: 'refresh_invalid_payload',
      message: 'refresh response missing access_token',
    });
  }

  const expiresInSeconds = safeInt(payload?.expires_in, 0);
  const expiresAtMs = expiresInSeconds > 0 ? Date.now() + (expiresInSeconds * 1000) : 0;
  const idClaims = decodeJwtPayload(payload?.id_token) || {};
  const email = safeString(
    payload?.email
    || idClaims.email
    || idClaims.preferred_username
    || ''
  );
  const accountID = safeString(
    payload?.account_id
    || idClaims.chatgpt_account_id
    || idClaims.account_id
    || ''
  );

  const accountUpdates = {
    api_key: accessToken,
  };
  const nextRefreshToken = safeString(payload?.refresh_token);
  if (nextRefreshToken) {
    accountUpdates.refresh_token = nextRefreshToken;
  }
  if (expiresAtMs > 0) {
    accountUpdates.expires_at_ms = expiresAtMs;
  }
  if (email) {
    accountUpdates.email = email;
  }
  if (accountID) {
    accountUpdates.account_id = accountID;
  }

  return {
    ok: true,
    account_updates: accountUpdates,
  };
}

export async function refreshClaudeOAuthAccount(account, {
  env = process.env,
  httpRequestFn,
} = {}) {
  const refreshToken = safeString(account?.refresh_token);
  if (!refreshToken) {
    throw createRefreshError({
      code: 'missing_refresh_token',
      message: 'provider key is missing refresh_token',
    });
  }

  let response;
  try {
    response = await executeHttpRequest({
      url: claudeOAuthRefreshURLFromEnv(env),
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        client_id: claudeOAuthClientIDFromEnv(env),
        grant_type: 'refresh_token',
        refresh_token: refreshToken,
      }),
      timeoutMs: refreshTimeoutMsFromEnv(env),
      httpRequestFn,
    });
  } catch (error) {
    const code = sanitizeReasonCode(
      error?.code === 'ETIMEDOUT'
        ? 'refresh_timeout'
        : (error?.code || error?.name || 'refresh_request_failed'),
      'refresh_request_failed'
    );
    throw createRefreshError({
      code,
      message: safeString(error?.message || error) || 'refresh request failed',
      details: safeString(error?.message || error) || 'refresh request failed',
    });
  }

  if (safeInt(response.statusCode, 0) >= 400) {
    throw refreshErrorFromResponse(response, claudeOAuthRefreshURLFromEnv(env));
  }

  const payload = response.json && typeof response.json === 'object'
    ? response.json
    : parseJsonSafe(response.bodyText);
  const accessToken = safeString(payload?.access_token);
  if (!accessToken) {
    throw createRefreshError({
      code: 'refresh_invalid_payload',
      message: 'refresh response missing access_token',
    });
  }

  const expiresInSeconds = safeInt(payload?.expires_in, 0);
  const expiresAtMs = expiresInSeconds > 0 ? Date.now() + (expiresInSeconds * 1000) : 0;
  const accountUpdates = {
    api_key: accessToken,
  };
  const nextRefreshToken = safeString(payload?.refresh_token);
  if (nextRefreshToken) {
    accountUpdates.refresh_token = nextRefreshToken;
  }
  if (expiresAtMs > 0) {
    accountUpdates.expires_at_ms = expiresAtMs;
  }
  const accountID = safeString(payload?.account?.uuid);
  if (accountID) {
    accountUpdates.account_id = accountID;
  }
  const email = safeString(payload?.account?.email_address);
  if (email) {
    accountUpdates.email = email;
  }

  return {
    ok: true,
    account_updates: accountUpdates,
  };
}

export async function refreshGeminiOAuthAccount(account, {
  env = process.env,
  httpRequestFn,
} = {}) {
  const refreshToken = safeString(account?.refresh_token);
  if (!refreshToken) {
    throw createRefreshError({
      code: 'missing_refresh_token',
      message: 'provider key is missing refresh_token',
    });
  }

  const clientID = geminiOAuthClientIDFromEnv(account, env);
  const clientSecret = geminiOAuthClientSecretFromEnv(account, env);
  if (!clientID || !clientSecret) {
    throw createRefreshError({
      code: 'missing_oauth_client',
      message: 'gemini refresh requires oauth client id and secret',
    });
  }

  const requestBody = new URLSearchParams();
  requestBody.set('client_id', clientID);
  requestBody.set('client_secret', clientSecret);
  requestBody.set('grant_type', 'refresh_token');
  requestBody.set('refresh_token', refreshToken);

  let response;
  try {
    response = await executeHttpRequest({
      url: geminiOAuthRefreshURLFromEnv(account, env),
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: requestBody.toString(),
      timeoutMs: refreshTimeoutMsFromEnv(env),
      httpRequestFn,
    });
  } catch (error) {
    const code = sanitizeReasonCode(
      error?.code === 'ETIMEDOUT'
        ? 'refresh_timeout'
        : (error?.code || error?.name || 'refresh_request_failed'),
      'refresh_request_failed'
    );
    throw createRefreshError({
      code,
      message: safeString(error?.message || error) || 'refresh request failed',
      details: safeString(error?.message || error) || 'refresh request failed',
    });
  }

  if (safeInt(response.statusCode, 0) >= 400) {
    throw refreshErrorFromResponse(response, geminiOAuthRefreshURLFromEnv(account, env));
  }

  const payload = response.json && typeof response.json === 'object'
    ? response.json
    : parseJsonSafe(response.bodyText);
  const accessToken = safeString(payload?.access_token);
  if (!accessToken) {
    throw createRefreshError({
      code: 'refresh_invalid_payload',
      message: 'refresh response missing access_token',
    });
  }

  const expiresInSeconds = safeInt(payload?.expires_in, 0);
  const expiresAtMs = expiresInSeconds > 0 ? Date.now() + (expiresInSeconds * 1000) : 0;
  const idClaims = decodeJwtPayload(payload?.id_token) || {};
  const accountUpdates = {
    api_key: accessToken,
  };
  const nextRefreshToken = safeString(payload?.refresh_token);
  if (nextRefreshToken) {
    accountUpdates.refresh_token = nextRefreshToken;
  }
  if (expiresAtMs > 0) {
    accountUpdates.expires_at_ms = expiresAtMs;
  }
  const email = safeString(payload?.email || idClaims.email);
  if (email) {
    accountUpdates.email = email;
  }
  const accountID = safeString(payload?.account_id || idClaims.sub || idClaims.account_id);
  if (accountID) {
    accountUpdates.account_id = accountID;
  }

  return {
    ok: true,
    account_updates: accountUpdates,
  };
}

export async function refreshAntigravityOAuthAccount(account, {
  env = process.env,
  httpRequestFn,
} = {}) {
  const refreshToken = safeString(account?.refresh_token);
  if (!refreshToken) {
    throw createRefreshError({
      code: 'missing_refresh_token',
      message: 'provider key is missing refresh_token',
    });
  }

  const clientID = antigravityOAuthClientIDFromEnv(env);
  const clientSecret = antigravityOAuthClientSecretFromEnv(env);
  if (!clientID || !clientSecret) {
    throw createRefreshError({
      code: 'missing_oauth_client',
      message: 'antigravity refresh requires oauth client id and secret',
    });
  }

  const requestBody = new URLSearchParams();
  requestBody.set('client_id', clientID);
  requestBody.set('client_secret', clientSecret);
  requestBody.set('grant_type', 'refresh_token');
  requestBody.set('refresh_token', refreshToken);

  let response;
  try {
    response = await executeHttpRequest({
      url: antigravityOAuthRefreshURLFromEnv(env),
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: requestBody.toString(),
      timeoutMs: refreshTimeoutMsFromEnv(env),
      httpRequestFn,
    });
  } catch (error) {
    const code = sanitizeReasonCode(
      error?.code === 'ETIMEDOUT'
        ? 'refresh_timeout'
        : (error?.code || error?.name || 'refresh_request_failed'),
      'refresh_request_failed'
    );
    throw createRefreshError({
      code,
      message: safeString(error?.message || error) || 'refresh request failed',
      details: safeString(error?.message || error) || 'refresh request failed',
    });
  }

  if (safeInt(response.statusCode, 0) >= 400) {
    throw refreshErrorFromResponse(response, antigravityOAuthRefreshURLFromEnv(env));
  }

  const payload = response.json && typeof response.json === 'object'
    ? response.json
    : parseJsonSafe(response.bodyText);
  const accessToken = safeString(payload?.access_token);
  if (!accessToken) {
    throw createRefreshError({
      code: 'refresh_invalid_payload',
      message: 'refresh response missing access_token',
    });
  }

  const expiresInSeconds = safeInt(payload?.expires_in, 0);
  const expiresAtMs = expiresInSeconds > 0 ? Date.now() + (expiresInSeconds * 1000) : 0;
  const accountUpdates = {
    api_key: accessToken,
  };
  const nextRefreshToken = safeString(payload?.refresh_token);
  if (nextRefreshToken) {
    accountUpdates.refresh_token = nextRefreshToken;
  }
  if (expiresAtMs > 0) {
    accountUpdates.expires_at_ms = expiresAtMs;
  }

  return {
    ok: true,
    account_updates: accountUpdates,
  };
}

export async function refreshKiroOAuthAccount(account, {
  env = process.env,
  httpRequestFn,
} = {}) {
  const refreshToken = safeString(account?.refresh_token);
  if (!refreshToken) {
    throw createRefreshError({
      code: 'missing_refresh_token',
      message: 'provider key is missing refresh_token',
    });
  }

  let response;
  try {
    response = await executeHttpRequest({
      url: kiroOAuthRefreshURLFromEnv(env),
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        refreshToken,
      }),
      timeoutMs: refreshTimeoutMsFromEnv(env),
      httpRequestFn,
    });
  } catch (error) {
    const code = sanitizeReasonCode(
      error?.code === 'ETIMEDOUT'
        ? 'refresh_timeout'
        : (error?.code || error?.name || 'refresh_request_failed'),
      'refresh_request_failed'
    );
    throw createRefreshError({
      code,
      message: safeString(error?.message || error) || 'refresh request failed',
      details: safeString(error?.message || error) || 'refresh request failed',
    });
  }

  if (safeInt(response.statusCode, 0) >= 400) {
    throw refreshErrorFromResponse(response, kiroOAuthRefreshURLFromEnv(env));
  }

  const payload = response.json && typeof response.json === 'object'
    ? response.json
    : parseJsonSafe(response.bodyText);
  const accessToken = safeString(payload?.accessToken || payload?.access_token);
  if (!accessToken) {
    throw createRefreshError({
      code: 'refresh_invalid_payload',
      message: 'refresh response missing access token',
    });
  }

  const expiresInSeconds = safeInt(payload?.expiresIn || payload?.expires_in, 0);
  const expiresAtMs = expiresInSeconds > 0
    ? Date.now() + (expiresInSeconds * 1000)
    : Date.now() + DEFAULT_KIRO_ACCESS_TOKEN_TTL_MS;
  const accountUpdates = {
    api_key: accessToken,
    expires_at_ms: expiresAtMs,
  };
  const nextRefreshToken = safeString(payload?.refreshToken || payload?.refresh_token);
  if (nextRefreshToken) {
    accountUpdates.refresh_token = nextRefreshToken;
  }

  return {
    ok: true,
    account_updates: accountUpdates,
  };
}

export {
  DEFAULT_ANTIGRAVITY_OAUTH_CLIENT_ID,
  DEFAULT_ANTIGRAVITY_OAUTH_CLIENT_SECRET,
  DEFAULT_ANTIGRAVITY_OAUTH_REFRESH_URL,
  DEFAULT_CLAUDE_OAUTH_CLIENT_ID,
  DEFAULT_CLAUDE_OAUTH_REFRESH_URL,
  DEFAULT_GEMINI_OAUTH_CLIENT_ID,
  DEFAULT_GEMINI_OAUTH_CLIENT_SECRET,
  DEFAULT_GEMINI_OAUTH_REFRESH_URL,
  DEFAULT_KIRO_OAUTH_REFRESH_URL,
  DEFAULT_OPENAI_OAUTH_CLIENT_ID,
  DEFAULT_OPENAI_OAUTH_REFRESH_URL,
};
