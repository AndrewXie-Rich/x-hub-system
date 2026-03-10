import crypto from 'node:crypto';

export function nowMs() {
  return Date.now();
}

export function uuid() {
  // Node 22: crypto.randomUUID() is available.
  return crypto.randomUUID();
}

export function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export function chunkText(s, chunkSize) {
  const out = [];
  const text = String(s ?? '');
  const n = Math.max(1, Math.floor(chunkSize || 64));
  for (let i = 0; i < text.length; i += n) {
    out.push(text.slice(i, i + n));
  }
  return out;
}

export function estimateTokens(text) {
  // Cheap heuristic until we wire real tokenizer usage from runtime.
  // English ~4 chars/token; CJK often ~1-2 chars/token. Use 3.2 as a compromise.
  const s = String(text ?? '');
  return Math.max(0, Math.ceil(s.length / 3.2));
}

export function requireHttpsUrl(urlText) {
  let u;
  try {
    u = new URL(String(urlText || '').trim());
  } catch {
    return { ok: false, error: 'bad_url' };
  }
  if ((u.protocol || '').toLowerCase() !== 'https:') {
    return { ok: false, error: 'reject_non_https' };
  }
  return { ok: true, url: u };
}

