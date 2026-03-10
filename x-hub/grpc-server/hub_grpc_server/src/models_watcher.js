import crypto from 'node:crypto';

import { makeProtoModelInfo } from './models_util.js';
import { resolveRuntimeBaseDir, runtimeModelsSnapshot } from './mlx_runtime_ipc.js';

function stableModelKey(models) {
  const rows = Array.isArray(models) ? models : [];
  const slim = rows
    .map((m) => ({
      model_id: String(m?.model_id || ''),
      name: String(m?.name || ''),
      kind: String(m?.kind || ''),
      backend: String(m?.backend || ''),
      context_length: Number(m?.context_length || 0),
      requires_grant: !!Number(m?.requires_grant || 0),
    }))
    .filter((m) => m.model_id)
    .sort((a, b) => a.model_id.localeCompare(b.model_id));
  return crypto.createHash('sha256').update(JSON.stringify(slim)).digest('hex');
}

export function startModelsWatcher({ bus, interval_ms }) {
  const interval = Math.max(250, Number(interval_ms || process.env.HUB_MODELS_WATCH_MS || 1500));
  const runtimeBaseDir = resolveRuntimeBaseDir();

  let lastHash = '';
  let started = false;

  const tick = () => {
    const snap = runtimeModelsSnapshot(runtimeBaseDir);
    if (!snap.ok || !Array.isArray(snap.models) || snap.models.length === 0) return;
    const h = stableModelKey(snap.models);
    if (!started) {
      started = true;
      lastHash = h;
      return;
    }
    if (h === lastHash) return;
    lastHash = h;
    const models = snap.models.map(makeProtoModelInfo).filter(Boolean);
    bus.emitHubEvent(bus.modelsUpdated(models));
  };

  // Prime once, then poll.
  try {
    tick();
  } catch {
    // ignore
  }
  const t = setInterval(() => {
    try {
      tick();
    } catch {
      // ignore
    }
  }, interval);
  try {
    t.unref();
  } catch {
    // ignore
  }
  return () => clearInterval(t);
}

