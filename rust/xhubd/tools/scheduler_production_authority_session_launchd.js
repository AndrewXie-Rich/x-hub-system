#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const LABEL = 'com.ax.xhub.scheduler-authority-env';
const PLIST_PATH = path.join(os.homedir(), 'Library', 'LaunchAgents', `${LABEL}.plist`);
const STATE_DIR = path.join(ROOT_DIR, 'reports', 'scheduler_production_authority');
const STATE_FILE = path.join(STATE_DIR, 'session_launchd_state.json');
const SESSION_COMMAND = path.join(ROOT_DIR, 'tools', 'scheduler_production_authority_session.command');

function parseArgs(argv) {
  const out = {
    mode: 'status',
    rustHubRoot: ROOT_DIR,
    httpBaseUrl: 'http://127.0.0.1:50151',
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--status':
        out.mode = 'status';
        break;
      case '--install':
        out.mode = 'install';
        break;
      case '--uninstall':
        out.mode = 'uninstall';
        break;
      case '--rust-hub-root':
        out.rustHubRoot = String(next || '').trim() || out.rustHubRoot;
        i += 1;
        break;
      case '--http-base-url':
        out.httpBaseUrl = String(next || '').trim() || out.httpBaseUrl;
        i += 1;
        break;
      case '--self-test':
        out.selfTest = true;
        break;
      case '--help':
      case '-h':
        out.help = true;
        break;
      default:
        throw new Error(`unknown argument: ${arg}`);
    }
  }
  return out;
}

function usage() {
  return [
    'scheduler_production_authority_session_launchd.js',
    '',
    'Options:',
    '  --status              Inspect persistent session-env LaunchAgent',
    '  --install             Install/load LaunchAgent that reapplies scheduler authority env at login',
    '  --uninstall           Unload and remove LaunchAgent, restoring previous plist if backed up',
    '  --rust-hub-root <p>   Rust Hub root exported to X-Hub/Node',
    '  --http-base-url <u>   Rust xhubd HTTP base URL',
    '  --self-test           Validate plist generation only',
  ].join('\n');
}

function plist(config) {
  const outDir = path.join(ROOT_DIR, 'reports', 'scheduler_production_authority');
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${escapeXml(LABEL)}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${escapeXml(SESSION_COMMAND)}</string>
    <string>--apply</string>
    <string>--rust-hub-root</string>
    <string>${escapeXml(config.rustHubRoot)}</string>
    <string>--http-base-url</string>
    <string>${escapeXml(config.httpBaseUrl)}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${escapeXml(path.join(outDir, 'session_env_launchd.out.log'))}</string>
  <key>StandardErrorPath</key>
  <string>${escapeXml(path.join(outDir, 'session_env_launchd.err.log'))}</string>
</dict>
</plist>
`;
}

function escapeXml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
}

function runSelfTest() {
  const text = plist({ rustHubRoot: '/tmp/rust-hub', httpBaseUrl: 'http://127.0.0.1:50151' });
  if (!text.includes(LABEL)) throw new Error('label missing');
  if (!text.includes('scheduler_production_authority_session.command')) throw new Error('session command missing');
  if (text.includes('--open-xhub')) throw new Error('LaunchAgent must not open UI automatically');
}

function bootout() {
  try {
    execFileSync('launchctl', ['bootout', `gui/${process.getuid()}`, PLIST_PATH], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch {
    try {
      execFileSync('launchctl', ['remove', LABEL], {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'pipe'],
      });
    } catch {
      // Already unloaded or unavailable.
    }
  }
}

function bootstrap() {
  execFileSync('launchctl', ['bootstrap', `gui/${process.getuid()}`, PLIST_PATH], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
}

function kickstart() {
  try {
    execFileSync('launchctl', ['kickstart', '-k', `gui/${process.getuid()}/${LABEL}`], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch {
    // bootstrap RunAtLoad is enough; kickstart may fail if launchd already ran it.
  }
}

function printService() {
  try {
    return execFileSync('launchctl', ['print', `gui/${process.getuid()}/${LABEL}`], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch {
    return '';
  }
}

function writeState(state) {
  fs.mkdirSync(STATE_DIR, { recursive: true });
  fs.writeFileSync(STATE_FILE, `${JSON.stringify(state, null, 2)}\n`);
}

function readState() {
  if (!fs.existsSync(STATE_FILE)) return null;
  return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
}

function install(config) {
  if (!fs.existsSync(SESSION_COMMAND)) throw new Error(`missing session command: ${SESSION_COMMAND}`);
  fs.mkdirSync(path.dirname(PLIST_PATH), { recursive: true });
  fs.mkdirSync(STATE_DIR, { recursive: true });
  const previous = fs.existsSync(PLIST_PATH) ? fs.readFileSync(PLIST_PATH, 'utf8') : '';
  const backupPath = previous ? `${PLIST_PATH}.rhm072.${Date.now()}.bak` : '';
  if (backupPath) fs.writeFileSync(backupPath, previous);
  bootout();
  fs.writeFileSync(PLIST_PATH, plist(config));
  execFileSync('plutil', ['-lint', PLIST_PATH], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  bootstrap();
  kickstart();
  writeState({
    schema_version: 'xhub.scheduler_production_authority_session_launchd_state.v1',
    generated_at: new Date().toISOString(),
    plist_path: PLIST_PATH,
    backup_path: backupPath,
    had_previous_plist: Boolean(previous),
  });
}

function uninstall() {
  bootout();
  const state = readState();
  if (state?.backup_path && fs.existsSync(state.backup_path)) {
    fs.copyFileSync(state.backup_path, PLIST_PATH);
  } else if (fs.existsSync(PLIST_PATH)) {
    fs.unlinkSync(PLIST_PATH);
  }
}

function status() {
  const loadedText = printService();
  return {
    plist_path: PLIST_PATH,
    plist_exists: fs.existsSync(PLIST_PATH),
    loaded: loadedText.includes(`"${LABEL}"`) || loadedText.includes(LABEL),
    state_file: STATE_FILE,
    state_exists: fs.existsSync(STATE_FILE),
  };
}

async function main() {
  const config = parseArgs(process.argv.slice(2));
  if (config.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  if (config.selfTest) {
    runSelfTest();
    process.stdout.write('scheduler_production_authority_session_launchd self-test ok\n');
    return;
  }
  if (config.mode === 'install') install(config);
  if (config.mode === 'uninstall') uninstall();
  process.stdout.write(`${JSON.stringify({
    ok: true,
    schema_version: 'xhub.scheduler_production_authority_session_launchd.v1',
    mode: config.mode,
    install_performed: config.mode === 'install',
    uninstall_performed: config.mode === 'uninstall',
    launchd_installed: config.mode === 'install' || status().plist_exists,
    production_authority_persistence_installed: status().plist_exists,
    memory_writer_authority_target: false,
    skills_execution_authority_target: false,
    provider_route_authority_target: false,
    model_route_authority_target: false,
    ui_product_change: false,
    secret_leak: false,
    ...status(),
  }, null, 2)}\n`);
}

main().catch((error) => {
  process.stderr.write(`[scheduler_production_authority_session_launchd] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
});
