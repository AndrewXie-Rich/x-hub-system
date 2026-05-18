import http from 'node:http';
import https from 'node:https';

const DEFAULT_BASE_URL = 'http://127.0.0.1:8310';
const DEFAULT_TIMEOUT_MS = 15_000;

function safeString(value) {
  return String(value ?? '').trim();
}

function safeInt(value, fallback = 0) {
  const number = Number(value || 0);
  if (!Number.isFinite(number)) return fallback;
  return Math.max(0, Math.floor(number));
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

  let json = null;
  try {
    json = JSON.parse(bodyText);
  } catch {
    json = null;
  }

  return {
    statusCode: safeInt(raw.statusCode ?? raw.status, 0),
    headers: raw.headers && typeof raw.headers === 'object' ? raw.headers : {},
    bodyText,
    json: json && typeof json === 'object' ? json : null,
  };
}

async function executeHttpRequest({
  url,
  method = 'GET',
  headers = {},
  body = '',
  timeoutMs = DEFAULT_TIMEOUT_MS,
  httpRequestFn,
} = {}) {
  if (typeof httpRequestFn === 'function') {
    return normalizeHttpResponse(await httpRequestFn({
      url: safeString(url),
      method: safeString(method) || 'GET',
      headers: { ...headers },
      body: typeof body === 'string' ? body : safeString(body),
      timeoutMs: safeInt(timeoutMs, DEFAULT_TIMEOUT_MS),
    }));
  }

  const requestURL = safeString(url);
  if (!requestURL) {
    throw Object.assign(new Error('missing management api url'), { code: 'invalid_management_url' });
  }

  const requestBody = typeof body === 'string' ? body : safeString(body);
  const requestHeaders = { ...headers };
  if (requestBody && !Object.keys(requestHeaders).some((key) => key.toLowerCase() === 'content-length')) {
    requestHeaders['Content-Length'] = Buffer.byteLength(requestBody);
  }

  const target = new URL(requestURL);
  const transport = target.protocol === 'http:' ? http : https;
  const timeout = Math.max(250, safeInt(timeoutMs, DEFAULT_TIMEOUT_MS));

  return await new Promise((resolve, reject) => {
    const request = transport.request({
      protocol: target.protocol,
      hostname: target.hostname,
      port: target.port || undefined,
      path: `${target.pathname}${target.search}`,
      method: safeString(method) || 'GET',
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
    request.setTimeout(timeout, () => {
      request.destroy(Object.assign(new Error(`management request timed out after ${timeout}ms`), {
        code: 'ETIMEDOUT',
      }));
    });
    request.on('error', (error) => reject(error));
    if (requestBody) request.write(requestBody);
    request.end();
  });
}

function managementAPIBaseURLFromEnv(env = process.env) {
  const explicit = safeString(
    env.HUB_PROVIDER_KEY_MANAGEMENT_API_BASE_URL
    || env.HUB_PROVIDER_KEY_MANAGEMENT_BASE_URL
  );
  if (explicit) {
    return explicit.replace(/\/+$/, '');
  }

  const scheme = safeString(
    env.HUB_PROVIDER_KEY_MANAGEMENT_API_SCHEME
    || env.HUB_PROVIDER_KEY_MANAGEMENT_SCHEME
    || 'http'
  ).toLowerCase();
  const host = safeString(
    env.HUB_PROVIDER_KEY_MANAGEMENT_API_HOST
    || env.HUB_PROVIDER_KEY_MANAGEMENT_HOST
    || '127.0.0.1'
  ) || '127.0.0.1';
  const port = safeInt(
    env.HUB_PROVIDER_KEY_MANAGEMENT_API_PORT
    || env.HUB_PROVIDER_KEY_MANAGEMENT_PORT,
    8310
  ) || 8310;

  return `${scheme}://${host}:${port}`;
}

function managementAPITimeoutMsFromEnv(env = process.env) {
  const explicit = safeInt(
    env.HUB_PROVIDER_KEY_MANAGEMENT_API_TIMEOUT_MS
    || env.HUB_PROVIDER_KEY_MANAGEMENT_TIMEOUT_MS,
    0
  );
  return explicit > 0 ? explicit : DEFAULT_TIMEOUT_MS;
}

function managementAPIAuthHeadersFromEnv(env = process.env) {
  const secret = safeString(
    env.HUB_PROVIDER_KEY_MANAGEMENT_API_SECRET
    || env.HUB_PROVIDER_KEY_MANAGEMENT_SECRET
  );
  return secret ? { Authorization: `Bearer ${secret}` } : {};
}

function httpErrorFromResponse(response, fallback = 'management_api_failed') {
  const statusCode = safeInt(response?.statusCode, 0);
  const payload = response?.json && typeof response.json === 'object' ? response.json : {};
  const detail = safeString(
    payload.detail
    || payload.error
    || payload.message
    || response?.bodyText
    || fallback
  );
  const error = new Error(statusCode > 0 ? `${detail} (status=${statusCode})` : detail || fallback);
  error.code = statusCode > 0 ? `management_http_${statusCode}` : fallback;
  error.http_status = statusCode;
  error.status_message = detail || fallback;
  return error;
}

export async function callManagementApi(params = {}, options = {}) {
  const env = options.env || process.env;
  const baseURL = safeString(options.baseURL) || managementAPIBaseURLFromEnv(env);
  const payload = {
    method: safeString(params.method || 'GET') || 'GET',
    url: safeString(params.url),
    header: params.header && typeof params.header === 'object' ? params.header : {},
  };
  if (params.authIndex !== undefined && params.authIndex !== null && safeString(params.authIndex)) {
    payload.authIndex = String(params.authIndex);
  }
  if (params.body !== undefined) {
    payload.data = typeof params.body === 'string'
      ? params.body
      : JSON.stringify(params.body);
  }

  const response = await executeHttpRequest({
    url: `${baseURL}/v0/management/api-call`,
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
      ...managementAPIAuthHeadersFromEnv(env),
    },
    body: JSON.stringify(payload),
    timeoutMs: managementAPITimeoutMsFromEnv(env),
    httpRequestFn: options.httpRequestFn,
  });

  if (safeInt(response.statusCode, 0) >= 400) {
    throw httpErrorFromResponse(response);
  }

  if (response.json && typeof response.json === 'object') {
    return response.json;
  }

  const error = new Error('management api returned non-json payload');
  error.code = 'invalid_management_payload';
  error.status_message = safeString(response.bodyText || 'management api returned non-json payload');
  throw error;
}

export async function listAuthFiles(options = {}) {
  const env = options.env || process.env;
  const baseURL = safeString(options.baseURL) || managementAPIBaseURLFromEnv(env);
  const response = await executeHttpRequest({
    url: `${baseURL}/v0/management/auth-files`,
    method: 'GET',
    headers: {
      Accept: 'application/json',
      ...managementAPIAuthHeadersFromEnv(env),
    },
    timeoutMs: managementAPITimeoutMsFromEnv(env),
    httpRequestFn: options.httpRequestFn,
  });
  if (safeInt(response.statusCode, 0) >= 400) {
    throw httpErrorFromResponse(response);
  }
  return response.json && typeof response.json === 'object' ? response.json : [];
}

export async function removeAuthFile(name, options = {}) {
  const env = options.env || process.env;
  const baseURL = safeString(options.baseURL) || managementAPIBaseURLFromEnv(env);
  const target = new URL(`${baseURL}/v0/management/auth-files`);
  target.searchParams.set('name', safeString(name));
  const response = await executeHttpRequest({
    url: target.toString(),
    method: 'DELETE',
    headers: {
      Accept: 'application/json',
      ...managementAPIAuthHeadersFromEnv(env),
    },
    timeoutMs: managementAPITimeoutMsFromEnv(env),
    httpRequestFn: options.httpRequestFn,
  });
  if (safeInt(response.statusCode, 0) >= 400) {
    throw httpErrorFromResponse(response);
  }
  return response.json && typeof response.json === 'object' ? response.json : {};
}
