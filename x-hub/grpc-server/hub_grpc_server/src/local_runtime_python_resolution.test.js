import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import {
  buildLocalRuntimeSpawnConfig,
  isUnsafeLocalRuntimePython,
  resolveLocalRuntimePythonExecutable,
} from './local_runtime_ipc.js';

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

function makeTempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-local-runtime-python-'));
}

function makeExecutable(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, '#!/bin/sh\nexit 0\n', 'utf8');
  fs.chmodSync(filePath, 0o755);
}

function writeJson(filePath, obj) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(obj), 'utf8');
}

await run('isUnsafeLocalRuntimePython rejects Xcode and /usr/bin developer interpreters', () => {
  assert.equal(isUnsafeLocalRuntimePython('/usr/bin/python3'), true);
  assert.equal(
    isUnsafeLocalRuntimePython('/Applications/Xcode.app/Contents/Developer/usr/bin/python3'),
    true
  );
  assert.equal(
    isUnsafeLocalRuntimePython('/Library/Frameworks/Python.framework/Versions/3.11/bin/python3'),
    false
  );
});

await run('resolveLocalRuntimePythonExecutable prefers runtime status path over unsafe PATH python3', () => {
  const runtimeBaseDir = makeTempDir();
  const safePython = path.join(runtimeBaseDir, 'venv/bin/python3');
  const unsafeRoot = path.join(runtimeBaseDir, 'unsafe-bin');
  const unsafePython = path.join(unsafeRoot, 'python3');
  makeExecutable(safePython);
  makeExecutable(unsafePython);
  writeJson(path.join(runtimeBaseDir, 'ai_runtime_status.json'), {
    updatedAt: Date.now() / 1000.0,
    providers: {
      mlx: {
        runtimeSourcePath: safePython,
      },
    },
  });

  const resolved = resolveLocalRuntimePythonExecutable({
    runtimeBaseDir,
    env: {
      PATH: unsafeRoot,
    },
  });

  assert.equal(resolved, safePython);
});

await run('buildLocalRuntimeSpawnConfig falls back to builtin safe Python when PATH only exposes /usr/bin/python3', () => {
  const runtimeBaseDir = makeTempDir();
  const config = buildLocalRuntimeSpawnConfig({
    runtimeBaseDir,
    env: {
      PATH: '/usr/bin',
    },
  });

  assert.equal(
    config.executable,
    '/Library/Frameworks/Python.framework/Versions/3.11/bin/python3'
  );
  assert.equal(config.error, '');
  assert.equal(String(config.env.REL_FLOW_HUB_BASE_DIR || ''), runtimeBaseDir);
});
