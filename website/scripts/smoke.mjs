import { access, readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { docOrder, docTitles, localizedPath } from '../src/docs.js';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const dist = join(root, '.vitepress', 'dist');
const publicDir = join(root, 'public');
const requiredAssets = [
  'xhub_trust_control_plane.svg',
  'xhub_deployment_runtime_topology.svg'
];

function argValue(name) {
  const prefix = `${name}=`;
  const inline = process.argv.find((arg) => arg.startsWith(prefix));
  if (inline) {
    return inline.slice(prefix.length);
  }
  const index = process.argv.indexOf(name);
  return index === -1 ? '' : process.argv[index + 1] || '';
}

function cleanPath(pathname) {
  return pathname.replace(/^\/+|\/+$/g, '');
}

function routeFile(pathname) {
  const clean = cleanPath(pathname);
  return clean ? join(dist, clean, 'index.html') : join(dist, 'index.html');
}

async function assertFile(path) {
  await access(path);
}

async function sha256(path) {
  const data = await readFile(path);
  return createHash('sha256').update(data).digest('hex');
}

function positiveInt(value, fallback) {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

const networkAttempts = positiveInt(
  argValue('--network-attempts') || process.env.XHUB_WEBSITE_SMOKE_ATTEMPTS,
  6
);

async function fetchWithRetry(url, init = {}, attempts = networkAttempts) {
  let lastError = null;
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      const response = await fetch(url, { redirect: 'follow', ...init });
      if (response.ok) {
        return response;
      }
      lastError = new Error(`HTTP ${response.status}`);
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 500 * attempt));
  }
  throw lastError;
}

const routes = ['', ...docOrder].flatMap((slug) => [
  localizedPath('en', slug),
  localizedPath('zh', slug)
]);
const routeSet = Array.from(new Set(routes));
const failures = [];

for (const slug of docOrder) {
  for (const locale of ['en', 'zh']) {
    if (!docTitles[locale]?.[slug]) {
      failures.push(`missing title: ${locale}:${slug}`);
    }
  }
}

if (localizedPath('en', 'memory') !== '/memory') {
  failures.push(`bad English memory path: ${localizedPath('en', 'memory')}`);
}
if (localizedPath('zh', 'memory') !== '/zh-CN/memory') {
  failures.push(`bad Chinese memory path: ${localizedPath('zh', 'memory')}`);
}

for (const pathname of routeSet) {
  try {
    await assertFile(routeFile(pathname));
  } catch {
    failures.push(`missing route entry: ${pathname}`);
  }
}

for (const file of ['404.html', 'sitemap.xml', 'robots.txt']) {
  try {
    await assertFile(join(dist, file));
  } catch {
    failures.push(`missing dist file: ${file}`);
  }
}

for (const asset of requiredAssets) {
  try {
    const sourceHash = await sha256(join(publicDir, asset));
    const distHash = await sha256(join(dist, asset));
    if (sourceHash !== distHash) {
      failures.push(`asset hash mismatch: ${asset}`);
    }
  } catch {
    failures.push(`missing asset: ${asset}`);
  }
}

const baseUrl = argValue('--base-url') || process.env.XHUB_WEBSITE_BASE_URL || '';
if (baseUrl) {
  const normalizedBase = baseUrl.replace(/\/+$/, '');
  for (const pathname of routeSet) {
    try {
      await fetchWithRetry(`${normalizedBase}${pathname || '/'}`, { method: 'HEAD' });
    } catch (error) {
      failures.push(`route fetch failed: ${pathname || '/'} (${error?.cause?.code || error.message})`);
    }
  }
  for (const asset of requiredAssets) {
    try {
      const response = await fetchWithRetry(`${normalizedBase}/${asset}`);
      const body = Buffer.from(await response.arrayBuffer());
      const remoteHash = createHash('sha256').update(body).digest('hex');
      const localHash = await sha256(join(publicDir, asset));
      if (remoteHash !== localHash) {
        failures.push(`remote asset hash mismatch: ${asset}`);
      }
    } catch (error) {
      failures.push(`asset fetch failed: ${asset} (${error?.cause?.code || error.message})`);
    }
  }
}

const result = {
  ok: failures.length === 0,
  checked_routes: routeSet.length,
  checked_assets: requiredAssets.length,
  base_url: baseUrl || null,
  network_attempts: baseUrl ? networkAttempts : null,
  failures
};

console.log(JSON.stringify(result, null, 2));
process.exit(result.ok ? 0 : 1);
