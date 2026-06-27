#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const SOURCE_ROOT_DIR = path.resolve(ROOT_DIR, '..', '..');
const REPORT_DIR = defaultReportDir();

function defaultReportDir() {
  if (/\.app\/Contents\/Resources\/rust-hub$/.test(ROOT_DIR)) {
    return path.join(os.homedir(), 'Library', 'Application Support', 'AX', 'rust-hub', 'local', 'reports');
  }
  return path.join(ROOT_DIR, 'reports');
}

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function utcStamp() {
  return new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
}

function parseArgs(argv) {
  const out = {
    maxProductCpuPercent: 0,
    requireXhubd: true,
    requireProductShell: false,
    requireNoTargetXhubd: true,
    reportPath: '',
    help: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--max-product-cpu-percent':
        out.maxProductCpuPercent = parseIntInRange(next, out.maxProductCpuPercent, 0, 1000);
        i += 1;
        break;
      case '--allow-missing-xhubd':
        out.requireXhubd = false;
        break;
      case '--require-product-shell':
        out.requireProductShell = true;
        break;
      case '--allow-target-xhubd':
        out.requireNoTargetXhubd = false;
        break;
      case '--report-path':
        out.reportPath = String(next || '').trim();
        i += 1;
        break;
      case '--help':
      case '-h':
        out.help = true;
        break;
      default:
        throw new Error(`unknown argument: ${arg}`);
    }
  }
  if (!out.reportPath) {
    out.reportPath = path.join(REPORT_DIR, `product_process_sanity_${utcStamp()}.json`);
  } else if (!path.isAbsolute(out.reportPath)) {
    out.reportPath = path.resolve(ROOT_DIR, out.reportPath);
  }
  return out;
}

function usage() {
  return [
    'product_process_sanity.js',
    '',
    'Low-impact process hygiene gate for the single Hub product: Rust kernel plus Swift shell.',
    '',
    'Options:',
    '  --max-product-cpu-percent <n> Fail when total or per-process product CPU exceeds n, default 0 disabled',
    '  --allow-missing-xhubd         Do not fail if no xhubd serve process is found',
    '  --require-product-shell       Fail if no X-Hub shell or X-Hub Node bridge process is found',
    '  --allow-target-xhubd          Do not fail if target/debug or target/release xhubd is present',
    '  --report-path <p>             JSON report path',
  ].join('\n');
}

function redactCommand(command) {
  return String(command || '')
    .replace(/(Authorization:\s*Bearer\s+)[^\s'"]+/gi, '$1[REDACTED]')
    .replace(/((?:access[_-]?key|api[_-]?key|token|secret|password)[=:]\s*)[^\s'"]+/gi, '$1[REDACTED]')
    .replace(/(--(?:access-key|token|secret|password)\s+)[^\s'"]+/gi, '$1[REDACTED]');
}

function collectProcessRows() {
  try {
    const stdout = execFileSync('ps', ['ax', '-o', 'pid=,ppid=,stat=,%cpu=,%mem=,etime=,command='], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: 3000,
      maxBuffer: 8 * 1024 * 1024,
    });
    return {
      ok: true,
      error: '',
      rows: stdout.split('\n').map((line) => line.trim()).filter(Boolean),
    };
  } catch (error) {
    return {
      ok: false,
      error: String(error?.message || error),
      rows: [],
    };
  }
}

function parseProcessRow(line) {
  const match = String(line || '').match(/^(\d+)\s+(\d+)\s+(\S+)\s+([0-9.]+)\s+([0-9.]+)\s+(\S+)\s+([\s\S]*)$/);
  if (!match) {
    return {
      pid: 0,
      ppid: 0,
      stat: '',
      cpu_percent: 0,
      mem_percent: 0,
      etime: '',
      command: redactCommand(line),
      raw: redactCommand(line),
    };
  }
  const command = redactCommand(match[7]);
  return {
    pid: Number(match[1]),
    ppid: Number(match[2]),
    stat: match[3],
    cpu_percent: Number(match[4] || 0),
    mem_percent: Number(match[5] || 0),
    etime: match[6],
    command,
    raw: `${match[1]} ${match[2]} ${match[3]} ${match[4]} ${match[5]} ${match[6]} ${command}`,
  };
}

function productProcessLabel(command) {
  const text = String(command || '');
  if (/\/(?:bin\/)?xhubd\s+serve(?:\s|$)/.test(text) || /(^|\s)xhubd\s+serve(?:\s|$)/.test(text)) {
    return 'xhubd';
  }
  if (/\/X-Hub\.app\/Contents\/MacOS\/XHub(?:\s|$)/.test(text)) return 'x_hub_app';
  if (/\/X-Terminal\.app\/Contents\/MacOS\/XTerminal(?:\s|$)/.test(text)) return 'x_terminal_app';
  if (isXHubNodeBridgeProcess(text)) return 'x_hub_node_bridge';
  if (isXHubPythonRuntimeProcess(text)) return 'python_ml_runtime';
  return '';
}

function isXHubScopedProcess(command) {
  const text = String(command || '');
  return /\/X-Hub\.app\//.test(text)
    || text.includes(`${SOURCE_ROOT_DIR}/x-hub/`)
    || /\/x-hub-system(?:-github-clean)?\/x-hub\//.test(text);
}

function isXHubNodeBridgeProcess(command) {
  const text = String(command || '');
  return isXHubScopedProcess(text)
    && !isExternalRelFlowHubProcess(text)
    && (/\/relflowhub_node(?:\s|$)/.test(text) || /hub_grpc_server\/src\/server\.js/.test(text));
}

function isXHubPythonRuntimeProcess(command) {
  const text = String(command || '');
  return isXHubScopedProcess(text)
    && !isExternalRelFlowHubProcess(text)
    && /relflowhub_(?:local|mlx)_runtime\.py/.test(text);
}

function isLegacyContainerRuntimeProcess(command) {
  const text = String(command || '');
  if (!/relflowhub_(?:local|mlx)_runtime\.py/.test(text) || /\/Applications\/X-Hub\.app\//.test(text)) {
    return false;
  }
  return /\/Library\/Containers\/com\.rel\.flowhub\/Data\/RELFlowHub\/ai_runtime\//.test(text)
    || /\/Library\/Containers\/com\.rel\.flowhub\/Data\/XHub\/ai_runtime\//.test(text)
    || /\/Library\/Group Containers\/group\.rel\.flowhub\//.test(text);
}

function isTargetXhubd(command) {
  return /\/target\/(?:debug|release)\/xhubd(?:\s|$)/.test(String(command || ''));
}

function isMountedAppProcess(command) {
  const text = String(command || '');
  return /\/Volumes\/(?:X-Hub|XHub)[^/]*\//.test(text)
    && (/\/X-Hub\.app\//.test(text)
      || isXHubNodeBridgeProcess(text)
      || isXHubPythonRuntimeProcess(text));
}

function isExternalRelFlowHubProcess(command) {
  const text = String(command || '');
  return !/\/X-Hub\.app\//.test(text)
    && (/\/RELFlowHub\.app\//.test(text) || /\/Volumes\/RELFlowHub[^/]*\//.test(text));
}

function summarize(config) {
  const snapshot = collectProcessRows();
  const processRows = snapshot.rows.map(parseProcessRow);
  const productProcesses = processRows
    .map((item) => ({ ...item, label: productProcessLabel(item.command) }))
    .filter((item) => item.label);
  const xhubdProcesses = productProcesses.filter((item) => item.label === 'xhubd');
  const productShellProcesses = productProcesses.filter((item) => (
    item.label === 'x_hub_app'
      || item.label === 'x_hub_node_bridge'
  ));
  const targetXhubdProcesses = processRows.filter((item) => isTargetXhubd(item.command));
  const mountedAppProcesses = processRows.filter((item) => isMountedAppProcess(item.command));
  const externalRelFlowHubProcesses = processRows.filter((item) => isExternalRelFlowHubProcess(item.command));
  const legacyContainerRuntimeProcesses = processRows.filter((item) => (
    isLegacyContainerRuntimeProcess(item.command)
  ));
  const threshold = Number(config.maxProductCpuPercent || 0);
  const highCpuProductProcesses = threshold > 0
    ? productProcesses.filter((item) => Number(item.cpu_percent || 0) > threshold)
    : [];
  const productTotalCpuPercent = productProcesses.reduce((sum, item) => sum + Number(item.cpu_percent || 0), 0);
  const productMaxCpuPercent = productProcesses.reduce((max, item) => Math.max(max, Number(item.cpu_percent || 0)), 0);
  const productCpuOverBudget = threshold > 0 && (
    productTotalCpuPercent > threshold || productMaxCpuPercent > threshold
  );

  const issues = [];
  if (!snapshot.ok) issues.push('process_snapshot_unavailable');
  if (config.requireXhubd && xhubdProcesses.length === 0) issues.push('xhubd_process_not_found');
  if (config.requireProductShell && productShellProcesses.length === 0) {
    issues.push('product_shell_process_not_found');
  }
  if (config.requireNoTargetXhubd && targetXhubdProcesses.length > 0) {
    issues.push('target_xhubd_process_present');
  }
  if (mountedAppProcesses.length > 0) issues.push('stale_mounted_app_process_present');
  if (legacyContainerRuntimeProcesses.length > 0) issues.push('legacy_container_runtime_process_present');
  if (productCpuOverBudget) issues.push('product_process_cpu_over_budget');

  const recommendations = [];
  if (mountedAppProcesses.length > 0) {
    recommendations.push('Close or terminate stale /Volumes X-Hub processes after confirming they are not the current /Applications app.');
  }
  if (legacyContainerRuntimeProcesses.length > 0) {
    recommendations.push('Stop stale container-hosted RELFlowHub local runtime processes; live local ML runtime should be owned by the Rust Hub launchd daemon and /Applications/X-Hub.app.');
  }
  if (productCpuOverBudget) {
    recommendations.push('Defer heavy gates or checkpoints until product CPU returns under budget.');
  }
  if (targetXhubdProcesses.length > 0 && config.requireNoTargetXhubd) {
    recommendations.push('Stop ad-hoc target/debug or target/release xhubd before production checks.');
  }

  return {
    ok: issues.length === 0,
    schema_version: 'xhub.product_process_sanity.v1',
    command: 'product-process-sanity',
    generated_at_iso: new Date().toISOString(),
    duration_ms: 0,
    production_authority_change: false,
    ui_product_change: false,
    rust_browser_product_ui: false,
    require_xhubd: config.requireXhubd,
    require_product_shell: config.requireProductShell,
    require_no_target_xhubd: config.requireNoTargetXhubd,
    max_product_cpu_percent: threshold,
    process_snapshot_ok: snapshot.ok,
    process_snapshot_error: snapshot.error,
    product_process_count: productProcesses.length,
    product_shell_process_count: productShellProcesses.length,
    xhubd_process_count: xhubdProcesses.length,
    target_xhubd_process_count: targetXhubdProcesses.length,
    mounted_app_process_count: mountedAppProcesses.length,
    external_relflowhub_process_count: externalRelFlowHubProcesses.length,
    legacy_container_runtime_process_count: legacyContainerRuntimeProcesses.length,
    high_cpu_product_process_count: highCpuProductProcesses.length,
    product_total_cpu_percent: Number(productTotalCpuPercent.toFixed(2)),
    product_max_cpu_percent: Number(productMaxCpuPercent.toFixed(2)),
    product_cpu_over_budget: productCpuOverBudget,
    product_processes: productProcesses,
    product_shell_processes: productShellProcesses,
    xhubd_processes: xhubdProcesses,
    target_xhubd_processes: targetXhubdProcesses,
    mounted_app_processes: mountedAppProcesses,
    external_relflowhub_processes: externalRelFlowHubProcesses,
    legacy_container_runtime_processes: legacyContainerRuntimeProcesses,
    high_cpu_product_processes: highCpuProductProcesses,
    issues,
    recommendations,
  };
}

function writeReport(report, reportPath) {
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`);
}

function main() {
  const startedAtMs = Date.now();
  const config = parseArgs(process.argv.slice(2));
  if (config.help) {
    console.log(usage());
    return;
  }
  const report = summarize(config);
  report.duration_ms = Date.now() - startedAtMs;
  report.report_path = config.reportPath;
  writeReport(report, config.reportPath);
  console.log(JSON.stringify(report, null, 2));
  if (!report.ok) process.exitCode = 1;
}

try {
  main();
} catch (error) {
  const payload = {
    ok: false,
    schema_version: 'xhub.product_process_sanity.v1',
    command: 'product-process-sanity',
    generated_at_iso: new Date().toISOString(),
    production_authority_change: false,
    ui_product_change: false,
    error: String(error?.message || error),
    issues: ['product_process_sanity_exception'],
  };
  console.log(JSON.stringify(payload, null, 2));
  process.exitCode = 1;
}
