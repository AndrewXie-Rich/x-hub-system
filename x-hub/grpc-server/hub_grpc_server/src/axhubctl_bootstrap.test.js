import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

function makeTempDir(label) {
  return fs.mkdtempSync(path.join(os.tmpdir(), `${label}_`));
}

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const AXHUBCTL_PATH = path.resolve(__dirname, '..', 'assets', 'axhubctl');

run('axhubctl knock with explicit hub preserves empty discovery metadata without crashing', () => {
  const tempRoot = makeTempDir('axhubctl_knock_explicit');
  const fakeBinDir = path.join(tempRoot, 'bin');
  const stateDir = path.join(tempRoot, 'state');
  fs.mkdirSync(fakeBinDir, { recursive: true });
  fs.mkdirSync(stateDir, { recursive: true });

  const fakeCurlPath = path.join(fakeBinDir, 'curl');
  fs.writeFileSync(
    fakeCurlPath,
    `#!/bin/sh
set -eu
out=""
write_code=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    -w)
      write_code="$2"
      shift 2
      ;;
    *)
      shift 1
      ;;
  esac
done
body='{"pairing_request_id":"req-explicit-host","status":"pending"}'
if [ -n "$out" ]; then
  printf '%s' "$body" >"$out"
else
  printf '%s' "$body"
fi
if [ -n "$write_code" ]; then
  printf '200'
fi
`,
    'utf8'
  );
  fs.chmodSync(fakeCurlPath, 0o755);

  const proc = spawnSync(
    '/bin/sh',
    [
      AXHUBCTL_PATH,
      'knock',
      '--hub', '17.81.11.116',
      '--pairing-port', '50054',
      '--grpc-port', '50053',
      '--app-id', 'x_terminal',
      '--device-name', 'XT Test Device',
    ],
    {
      env: {
        ...process.env,
        PATH: `${fakeBinDir}:${process.env.PATH || ''}`,
        AXHUBCTL_STATE_DIR: stateDir,
      },
      encoding: 'utf8',
    }
  );

  assert.equal(
    proc.status,
    0,
    `expected knock to succeed\nstdout:\n${proc.stdout}\nstderr:\n${proc.stderr}`
  );
  assert.ok(!/unbound variable/i.test(proc.stderr), proc.stderr);

  const pairingEnv = fs.readFileSync(path.join(stateDir, 'pairing.env'), 'utf8');
  assert.match(pairingEnv, /AXHUB_HUB_HOST='17\.81\.11\.116'/);
  assert.match(pairingEnv, /AXHUB_PAIRING_PORT='50054'/);
  assert.match(pairingEnv, /AXHUB_GRPC_PORT='50053'/);
  assert.match(pairingEnv, /AXHUB_PAIRING_REQUEST_ID='req-explicit-host'/);
});

run('axhubctl knock surfaces invite token requirement instead of generic source IP message', () => {
  const tempRoot = makeTempDir('axhubctl_knock_invite_token_required');
  const fakeBinDir = path.join(tempRoot, 'bin');
  const stateDir = path.join(tempRoot, 'state');
  fs.mkdirSync(fakeBinDir, { recursive: true });
  fs.mkdirSync(stateDir, { recursive: true });

  const fakeCurlPath = path.join(fakeBinDir, 'curl');
  fs.writeFileSync(
    fakeCurlPath,
    `#!/bin/sh
set -eu
out=""
write_code=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    -w)
      write_code="$2"
      shift 2
      ;;
    *)
      shift 1
      ;;
  esac
done
body='{"ok":false,"error":{"code":"invite_token_required","message":"invite_token_required","retryable":false}}'
if [ -n "$out" ]; then
  printf '%s' "$body" >"$out"
else
  printf '%s' "$body"
fi
if [ -n "$write_code" ]; then
  printf '403'
fi
`,
    'utf8'
  );
  fs.chmodSync(fakeCurlPath, 0o755);

  const proc = spawnSync(
    '/bin/sh',
    [
      AXHUBCTL_PATH,
      'knock',
      '--hub', '17.81.11.116',
      '--pairing-port', '50054',
      '--grpc-port', '50053',
      '--app-id', 'x_terminal',
      '--device-name', 'XT Test Device',
    ],
    {
      env: {
        ...process.env,
        PATH: `${fakeBinDir}:${process.env.PATH || ''}`,
        AXHUBCTL_STATE_DIR: stateDir,
      },
      encoding: 'utf8',
    }
  );

  assert.notEqual(proc.status, 0, 'expected knock to fail');
  assert.match(proc.stderr, /invite_token_required/);
  assert.doesNotMatch(proc.stderr, /source IP may not be allowed/i);
});

run('axhubctl knock surfaces source ip allowlist failures with canonical reason', () => {
  const tempRoot = makeTempDir('axhubctl_knock_source_ip_not_allowed');
  const fakeBinDir = path.join(tempRoot, 'bin');
  const stateDir = path.join(tempRoot, 'state');
  fs.mkdirSync(fakeBinDir, { recursive: true });
  fs.mkdirSync(stateDir, { recursive: true });

  const fakeCurlPath = path.join(fakeBinDir, 'curl');
  fs.writeFileSync(
    fakeCurlPath,
    `#!/bin/sh
set -eu
out=""
write_code=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    -w)
      write_code="$2"
      shift 2
      ;;
    *)
      shift 1
      ;;
  esac
done
body='{"ok":false,"error":{"code":"forbidden","message":"source_ip_not_allowed","retryable":false}}'
if [ -n "$out" ]; then
  printf '%s' "$body" >"$out"
else
  printf '%s' "$body"
fi
if [ -n "$write_code" ]; then
  printf '403'
fi
`,
    'utf8'
  );
  fs.chmodSync(fakeCurlPath, 0o755);

  const proc = spawnSync(
    '/bin/sh',
    [
      AXHUBCTL_PATH,
      'knock',
      '--hub', '17.81.11.116',
      '--pairing-port', '50054',
      '--grpc-port', '50053',
      '--app-id', 'x_terminal',
      '--device-name', 'XT Test Device',
    ],
    {
      env: {
        ...process.env,
        PATH: `${fakeBinDir}:${process.env.PATH || ''}`,
        AXHUBCTL_STATE_DIR: stateDir,
      },
      encoding: 'utf8',
    }
  );

  assert.notEqual(proc.status, 0, 'expected knock to fail');
  assert.match(proc.stderr, /source_ip_not_allowed/);
  assert.match(proc.stderr, /HUB_PAIRING_ALLOWED_CIDRS/);
});
