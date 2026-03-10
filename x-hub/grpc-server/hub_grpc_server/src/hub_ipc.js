import fs from 'node:fs';
import path from 'node:path';

import { uuid } from './util.js';

function safeString(v) {
  return String(v ?? '').trim();
}

function readJsonSafe(filePath) {
  try {
    const raw = fs.readFileSync(String(filePath || ''), 'utf8');
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function writeJsonAtomic(dirPath, fileName, obj) {
  const dir = safeString(dirPath);
  if (!dir) return false;
  try {
    fs.mkdirSync(dir, { recursive: true });
  } catch {
    // ignore
  }
  const outPath = path.join(dir, fileName);
  const tmp = path.join(dir, `.${fileName}.tmp_${process.pid}_${Math.random().toString(16).slice(2)}`);
  try {
    fs.writeFileSync(tmp, JSON.stringify(obj), { encoding: 'utf8' });
    fs.renameSync(tmp, outPath);
    return true;
  } catch {
    try {
      fs.unlinkSync(tmp);
    } catch {
      // ignore
    }
    return false;
  }
}

function discoverIpcEventsDir(runtimeBaseDir) {
  const base = safeString(runtimeBaseDir);
  if (!base) return '';

  // Prefer hub_status.json when present (authoritative IPC location).
  const st = readJsonSafe(path.join(base, 'hub_status.json'));
  const ipcPath = safeString(st?.ipcPath || st?.ipc_path || '');
  if (ipcPath) return ipcPath;

  // Fallback: standard folder under base dir.
  return path.join(base, 'ipc_events');
}

export function enqueueIpcEvent(runtimeBaseDir, payload) {
  const dir = discoverIpcEventsDir(runtimeBaseDir);
  if (!dir) return false;
  const name = `${uuid()}.json`;
  return writeJsonAtomic(dir, name, payload);
}

export function pushHubNotification(runtimeBaseDir, { source, title, body, dedupe_key, action_url, unread }) {
  const nowSec = Date.now() / 1000.0;
  const payload = {
    type: 'push_notification',
    req_id: uuid(),
    notification: {
      id: '',
      source: safeString(source) || 'Hub',
      title: safeString(title),
      body: safeString(body),
      created_at: nowSec,
      dedupe_key: dedupe_key != null ? safeString(dedupe_key) : null,
      action_url: action_url != null ? safeString(action_url) : null,
      unread: unread == null ? true : !!unread,
    },
  };
  return enqueueIpcEvent(runtimeBaseDir, payload);
}

