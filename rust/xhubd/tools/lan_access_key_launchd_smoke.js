#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const DAEMON_COMMAND = path.join(SCRIPT_DIR, 'xhubd_daemon.command');

function safeString(value) {
  return String(value ?? '').trim();
}

function runDaemon(args, options = {}) {
  const result = spawnSync('bash', [DAEMON_COMMAND, ...args], {
    cwd: ROOT_DIR,
    encoding: 'utf8',
    maxBuffer: 1024 * 1024,
    ...options,
  });
  const stdout = safeString(result.stdout);
  let parsed = null;
  try {
    parsed = JSON.parse(stdout);
  } catch (error) {
    throw new Error(`daemon command did not emit JSON: args=${args.join(' ')} status=${result.status} stdout=${stdout.slice(0, 400)} stderr=${safeString(result.stderr).slice(0, 400)} parse=${error.message}`);
  }
  return {
    status: result.status,
    stdout,
    stderr: safeString(result.stderr),
    parsed,
  };
}

function assertOk(condition, message, details = {}) {
  if (!condition) {
    const suffix = Object.keys(details).length ? ` ${JSON.stringify(details)}` : '';
    throw new Error(`${message}${suffix}`);
  }
}

function modeOctal(filePath) {
  const mode = fs.statSync(filePath).mode & 0o777;
  return mode.toString(8).padStart(4, '0');
}

function commandExists(command) {
  const result = spawnSync('command', ['-v', command], {
    shell: true,
    encoding: 'utf8',
  });
  return result.status === 0;
}

function lintPlist(plistPath) {
  if (!commandExists('plutil')) {
    return { checked: false, ok: true, reason: 'plutil_missing' };
  }
  const result = spawnSync('plutil', ['-lint', plistPath], {
    cwd: ROOT_DIR,
    encoding: 'utf8',
  });
  return {
    checked: true,
    ok: result.status === 0,
    stdout: safeString(result.stdout),
    stderr: safeString(result.stderr),
  };
}

function main() {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-lan-access-smoke-'));
  const keyFile = path.join(tempRoot, 'secrets', 'xhubd_lan_access_key');
  const plistPath = path.join(tempRoot, 'run', 'com.ax.xhubd.lan.plist');
  const lanProfile = path.join(ROOT_DIR, 'config', 'daemon_profile.lan.example.json');
  const common = [
    '--profile',
    'lan',
    '--profile-file',
    lanProfile,
    '--public-host',
    '127.0.0.1',
    '--access-key-file',
    keyFile,
    '--plist-path',
    plistPath,
  ];

  try {
    const profileBefore = runDaemon(['profile', ...common]);
    assertOk(profileBefore.status === 0 && profileBefore.parsed.ok === true, 'profile before access key failed', profileBefore.parsed);
    assertOk(profileBefore.parsed.profile === 'lan', 'profile did not resolve lan', profileBefore.parsed);
    assertOk(profileBefore.parsed.allow_lan === true, 'lan profile did not allow lan', profileBefore.parsed);
    assertOk(profileBefore.parsed.bind_url === 'http://0.0.0.0:50151', 'lan bind url mismatch', profileBefore.parsed);
    assertOk(profileBefore.parsed.http_access_key_configured === false, 'access key unexpectedly configured before init', profileBefore.parsed);

    const init = runDaemon(['access-key-init', ...common]);
    assertOk(init.status === 0 && init.parsed.ok === true, 'access-key-init failed', init.parsed);
    assertOk(init.parsed.key_printed === false, 'access-key-init reported key_printed=true', init.parsed);
    assertOk(fs.existsSync(keyFile), 'access key file missing after init', { keyFile });
    assertOk(modeOctal(keyFile) === '0600', 'access key file mode is not 0600', { mode: modeOctal(keyFile) });

    const secret = fs.readFileSync(keyFile, 'utf8').trim();
    assertOk(secret.length >= 32, 'generated access key is too short', { length: secret.length });
    assertOk(!init.stdout.includes(secret), 'access-key-init leaked the generated key in stdout');
    assertOk(!init.stderr.includes(secret), 'access-key-init leaked the generated key in stderr');

    const profileAfter = runDaemon(['profile', ...common]);
    assertOk(profileAfter.status === 0 && profileAfter.parsed.ok === true, 'profile after access key failed', profileAfter.parsed);
    assertOk(profileAfter.parsed.http_access_key_configured === true, 'profile did not detect access key file', profileAfter.parsed);

    const launchd = runDaemon(['launchd-plist', ...common]);
    assertOk(launchd.status === 0 && launchd.parsed.ok === true, 'launchd-plist failed', launchd.parsed);
    assertOk(fs.existsSync(plistPath), 'launchd plist missing', { plistPath });
    const plist = fs.readFileSync(plistPath, 'utf8');
    assertOk(plist.includes(keyFile), 'launchd plist does not include access key file path');
    assertOk(!plist.includes(secret), 'launchd plist leaked access key content');
    assertOk(!launchd.stdout.includes(secret), 'launchd-plist stdout leaked access key content');
    assertOk(!launchd.stderr.includes(secret), 'launchd-plist stderr leaked access key content');

    const plistLint = lintPlist(plistPath);
    assertOk(plistLint.ok === true, 'plutil rejected generated plist', plistLint);

    const domainSourceKey = path.join(tempRoot, 'source', 'secrets', 'xhubd_domain_access_key');
    const domainRuntimeRoot = path.join(tempRoot, 'runtime-domain');
    const domainRuntimeKey = path.join(domainRuntimeRoot, 'config', 'xhubd_domain_access_key');
    const domainInstallPlist = path.join(tempRoot, 'launch-agents', 'com.ax.xhubd.domain.smoke.plist');
    const domainProfile = path.join(tempRoot, 'daemon_profile.domain.smoke.json');
    const domainSecret = 'domain-runtime-access-key-smoke-secret-0000000000000000';
    fs.mkdirSync(path.dirname(domainSourceKey), { recursive: true });
    fs.writeFileSync(domainSourceKey, `${domainSecret}\n`, { mode: 0o600 });
    fs.writeFileSync(domainProfile, `${JSON.stringify({
      schema_version: 'xhub.rust_hub.daemon_profile.v1',
      profile: 'domain',
      host: '127.0.0.1',
      port: 50151,
      allow_lan: false,
      public_endpoint: true,
      public_base_url: 'https://hub.example.test',
      http_require_access_key: true,
      access_key_file: domainSourceKey,
      launchd_label: 'com.ax.xhubd.domain.smoke',
      wait_ms: 250,
    }, null, 2)}\n`, 'utf8');

    const domainDryRun = runDaemon([
      'launchd-install',
      '--dry-run',
      '--profile',
      'domain',
      '--profile-file',
      domainProfile,
      '--launchd-runtime-root',
      domainRuntimeRoot,
      '--install-plist-path',
      domainInstallPlist,
    ]);
    assertOk(domainDryRun.status === 0 && domainDryRun.parsed.ok === true, 'domain launchd dry-run failed', domainDryRun.parsed);
    assertOk(domainDryRun.parsed.deployment?.access_key_file_relocated === true, 'domain launchd did not relocate access key', domainDryRun.parsed.deployment);
    assertOk(domainDryRun.parsed.deployment?.access_key_file_runtime === domainRuntimeKey, 'domain launchd runtime key path mismatch', domainDryRun.parsed.deployment);
    assertOk(fs.existsSync(domainInstallPlist), 'domain launchd plist missing', { domainInstallPlist });
    const domainPlist = fs.readFileSync(domainInstallPlist, 'utf8');
    assertOk(domainPlist.includes(domainRuntimeKey), 'domain launchd plist does not use runtime access key file');
    assertOk(!domainPlist.includes(domainSourceKey), 'domain launchd plist still references source access key file');
    assertOk(!domainPlist.includes(domainSecret), 'domain launchd plist leaked domain access key content');

    process.stdout.write(`${JSON.stringify({
      ok: true,
      schema_version: 'xhub.rust_hub.lan_access_key_launchd_smoke.v1',
      command: 'lan-access-key-launchd-smoke',
      profile: profileAfter.parsed.profile,
      bind_url: profileAfter.parsed.bind_url,
      public_base_url: profileAfter.parsed.public_base_url,
      access_key_file: keyFile,
      access_key_file_mode: modeOctal(keyFile),
      key_printed: false,
      key_leaked: false,
      launchd_plist_path: plistPath,
      launchd_plist_linted: plistLint.checked,
      launchd_plist_ok: plistLint.ok,
      launchd_runtime_access_key_file: domainRuntimeKey,
      launchd_runtime_access_key_relocated: true,
    }, null, 2)}\n`);
  } finally {
    try {
      fs.rmSync(tempRoot, { recursive: true, force: true });
    } catch {}
  }
}

try {
  main();
} catch (error) {
  process.stderr.write(`[lan_access_key_launchd_smoke] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
}
