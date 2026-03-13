import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';

function run(name, fn) {
  try {
    const maybePromise = fn();
    if (maybePromise && typeof maybePromise.then === 'function') {
      return maybePromise.then(() => {
        process.stdout.write(`ok - ${name}\n`);
      }).catch((error) => {
        process.stderr.write(`not ok - ${name}\n`);
        throw error;
      });
    }
    process.stdout.write(`ok - ${name}\n`);
    return Promise.resolve();
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

function makeTempDbPath() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-killswitch-db-'));
  return path.join(dir, 'hub.sqlite');
}

await run('HubDB kill-switch stores and unions local capability/provider arrays', async () => {
  const dbPath = makeTempDbPath();
  const db = new HubDB({ dbPath });

  db.upsertKillSwitch({
    scope: 'global:*',
    models_disabled: false,
    network_disabled: false,
    disabled_local_capabilities: ['ai.embed.local'],
    reason: 'global incident',
  });
  db.upsertKillSwitch({
    scope: 'device:dev-1',
    models_disabled: false,
    network_disabled: false,
    disabled_local_providers: ['transformers'],
    reason: 'device quarantine',
  });

  const globalKillSwitch = db.getKillSwitch('global:*');
  assert.deepEqual(globalKillSwitch.disabled_local_capabilities, ['ai.embed.local']);
  assert.deepEqual(globalKillSwitch.disabled_local_providers, []);

  const effective = db.getEffectiveKillSwitch({
    device_id: 'dev-1',
    user_id: '',
    project_id: '',
  });
  assert.equal(effective.models_disabled, false);
  assert.equal(effective.network_disabled, false);
  assert.deepEqual(effective.disabled_local_capabilities, ['ai.embed.local']);
  assert.deepEqual(effective.disabled_local_providers, ['transformers']);
  assert.equal(effective.matched_scopes.includes('global:*'), true);
  assert.equal(effective.matched_scopes.includes('device:dev-1'), true);
});
