import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

const gate = fileURLToPath(new URL('../scripts/ci/xt_release_gate.sh', import.meta.url));

function withFixture(body) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xt-gate-binary-'));
  const source = path.join(root, 'Sources/Fixture.swift');
  const defaultBinary = path.join(root, '.build/debug/XTerminal');
  const scratch = path.join(root, 'selected-scratch');
  const builtBinary = path.join(scratch, 'debug/XTerminal');
  for (const file of [source, defaultBinary, builtBinary]) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, 'fixture');
    fs.chmodSync(file, 0o700);
    fs.utimesSync(file, 100, file === source ? 100 : 200);
  }
  const resolve = () => spawnSync('bash', ['-c', 'source "$1"; ROOT_DIR="$2"; XT_GATE_SWIFT_SCRATCH_PATH="$3"; resolve_xt_cli_binary', 'xt-gate-test', gate, root, scratch], { encoding: 'utf8' });
  try { body({ source, defaultBinary, builtBinary, resolve }); }
  finally { fs.rmSync(root, { recursive: true, force: true }); }
}

test('gate prefers the binary built in its selected scratch path', () => {
  withFixture(({ builtBinary, resolve }) => {
    const result = resolve();
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout.trim(), builtBinary);
  });
});

test('gate refuses stale binaries after source changes', () => {
  withFixture(({ source, resolve }) => {
    fs.utimesSync(source, 300, 300);
    const result = resolve();
    assert.equal(result.status, 1);
    assert.equal(result.stdout, '');
  });
});

test('gate uses a fresh default binary only when scratch has no current build', () => {
  withFixture(({ defaultBinary, builtBinary, resolve }) => {
    fs.utimesSync(builtBinary, 50, 50);
    const result = resolve();
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout.trim(), defaultBinary);
  });
});
