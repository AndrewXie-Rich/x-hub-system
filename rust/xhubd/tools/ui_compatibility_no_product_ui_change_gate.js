#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');

const REQUIRED_DOC_NEEDLES = [
  '# RHM-015 UI Compatibility Preservation Contract',
  'Rust Hub is a backend rewrite, not a product UI replacement',
  'Default UI stays XT',
  'Rust browser page is diagnostics only',
  'Rust bridges are default-off until gated',
  'No secret expansion into UI',
  'The Rust browser page remains diagnostic-only',
];

const REQUIRED_README_NEEDLES = [
  'docs/RHM_015_UI_COMPATIBILITY_PRESERVATION.md',
  'product UI',
  'default-off',
  'writer_authority_in_rust=false',
];

const REQUIRED_STATUS_NEEDLES = [
  '`RHM-015` UI compatibility preservation contract',
  'preserved product UI',
  'diagnostics',
];

const REQUIRED_MAIN_NEEDLES = [
  'Local shadow daemon',
  "fetch('/ready'",
  '<a href="/health">Health JSON</a>',
  '<a href="/ready">Ready JSON</a>',
  '"ml_execution_in_rust": false',
  '"canonical_writer_in_rust": memory_writer_authority',
  '"retrieval_shadow_http": true',
  '"skills_catalog_http": true',
  '"skills_preflight_http": true',
  '"scheduler_authority_http_opt_in": true',
  '"cross_network_auth_gate": true',
  '/skills/readiness',
  '/skills/preflight',
  'Skills Readiness',
  'Skills Preflight',
];

const FORBIDDEN_ROOT_PAGE_PHRASES = [
  'manage account',
  'manage skill',
  'manage model',
  'create account',
  'add account',
  'add provider key',
  'edit provider key',
  'delete provider key',
  'project settings',
  'supervisor settings',
  'hub setup wizard',
];

const FORBIDDEN_ROOT_SECRET_PHRASES = [
  'openai_api_key',
  'anthropic_api_key',
  'refresh_token',
  'provider_secret',
  'access_key_file',
];

const PROTECTED_PRODUCT_UI_SURFACES = [
  'x-terminal/Sources/UI/ModelSettingsView.swift',
  'x-terminal/Sources/UI/ModelSelectorView.swift',
  'x-terminal/Sources/UI/ProjectSettingsView.swift',
  'x-terminal/Sources/UI/SupervisorSettingsView.swift',
  'x-terminal/Sources/UI/MessageTimeline/DockInputView.swift',
  'x-terminal/Sources/UI/TerminalChatView.swift',
  'x-terminal/Sources/UI/HubSetupWizardView.swift',
  'x-terminal/Sources/UI/XTSettingsGuidancePresentation.swift',
  'x-terminal/Sources/UI/Supervisor/SupervisorPersonaCenterView.swift',
];

const SKIP_DIR_NAMES = new Set([
  '.git',
  'target',
  'dist',
  'logs',
  'run',
  'data',
  'secrets',
  'node_modules',
]);

function readText(relativePath) {
  return fs.readFileSync(path.join(ROOT_DIR, relativePath), 'utf8');
}

function readTextIfExists(relativePath) {
  const filePath = path.join(ROOT_DIR, relativePath);
  if (!fs.existsSync(filePath)) {
    return null;
  }
  return fs.readFileSync(filePath, 'utf8');
}

function assertOk(condition, message, details = {}) {
  if (!condition) {
    const suffix = Object.keys(details).length ? ` ${JSON.stringify(details)}` : '';
    throw new Error(`${message}${suffix}`);
  }
}

function requireNeedles(label, body, needles) {
  const missing = needles.filter((needle) => !body.includes(needle));
  assertOk(missing.length === 0, `${label} missing required UI compatibility markers`, { missing });
  return { label, ok: true, missing };
}

function extractRootBody(mainRs) {
  const start = mainRs.indexOf('fn root_body() -> String');
  const end = mainRs.indexOf('fn health_json', start);
  assertOk(start >= 0 && end > start, 'could not isolate xhubd root_body diagnostic page');
  return mainRs.slice(start, end);
}

function scanFiles(dir, files = []) {
  if (!fs.existsSync(dir)) {
    return files;
  }
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (!SKIP_DIR_NAMES.has(entry.name)) {
        scanFiles(fullPath, files);
      }
      continue;
    }
    if (entry.isFile()) {
      files.push(fullPath);
    }
  }
  return files;
}

function relativePosix(filePath) {
  return path.relative(ROOT_DIR, filePath).split(path.sep).join('/');
}

function checkNoSwiftProductUiInRustPackage() {
  const swiftFiles = scanFiles(ROOT_DIR)
    .filter((filePath) => filePath.endsWith('.swift'))
    .map(relativePosix);
  assertOk(swiftFiles.length === 0, 'Rust Hub package contains Swift files; UI must stay in x-hub-system/XT', {
    swift_files: swiftFiles.slice(0, 20),
  });
  return {
    label: 'no_swift_product_ui_files_in_rust_package',
    ok: true,
    swift_file_count: swiftFiles.length,
  };
}

function checkNoEmbeddedProductUiDirs() {
  const forbiddenDirs = [
    'x-terminal/Sources/UI',
    'x-terminal/Sources/Hub',
    'x-hub/macos/RELFlowHub/Sources/RELFlowHub',
  ];
  const existing = forbiddenDirs.filter((relativeDir) => fs.existsSync(path.join(ROOT_DIR, relativeDir)));
  assertOk(existing.length === 0, 'Rust Hub package embedded product UI source directories', { existing });
  return {
    label: 'no_embedded_product_ui_source_dirs',
    ok: true,
    existing,
  };
}

function checkRootPageDiagnosticOnly(rootBody) {
  const lower = rootBody.toLowerCase();
  const forbiddenProduct = FORBIDDEN_ROOT_PAGE_PHRASES.filter((phrase) => lower.includes(phrase));
  const forbiddenSecrets = FORBIDDEN_ROOT_SECRET_PHRASES.filter((phrase) => lower.includes(phrase));
  assertOk(forbiddenProduct.length === 0, 'Rust browser root page contains product UI ownership wording', {
    forbidden: forbiddenProduct,
  });
  assertOk(forbiddenSecrets.length === 0, 'Rust browser root page contains secret-shaped wording', {
    forbidden: forbiddenSecrets,
  });
  return {
    label: 'rust_browser_root_diagnostic_only',
    ok: true,
    forbidden_product_phrase_count: forbiddenProduct.length,
    forbidden_secret_phrase_count: forbiddenSecrets.length,
  };
}

function checkPackageIncludesGate() {
  const packageScript = readTextIfExists('tools/package_rust_hub.command');
  if (packageScript === null) {
    const packagedGateJs = fs.existsSync(path.join(ROOT_DIR, 'tools', 'ui_compatibility_no_product_ui_change_gate.js'));
    const packagedGateCommand = fs.existsSync(path.join(ROOT_DIR, 'tools', 'ui_compatibility_no_product_ui_change_gate.command'));
    assertOk(packagedGateJs && packagedGateCommand, 'packaged UI compatibility gate files are missing', {
      packaged_gate_js: packagedGateJs,
      packaged_gate_command: packagedGateCommand,
    });
    return {
      label: 'packaged_ui_compatibility_gate_present',
      ok: true,
      packaged_mode: true,
    };
  }
  const required = [
    'ui_compatibility_no_product_ui_change_gate.js',
    'ui_compatibility_no_product_ui_change_gate.command',
  ];
  const missing = required.filter((needle) => !packageScript.includes(needle));
  assertOk(missing.length === 0, 'package script does not copy UI compatibility gate', { missing });
  return { label: 'package_includes_ui_compatibility_gate', ok: true };
}

function main() {
  const rhm015 = readText('docs/RHM_015_UI_COMPATIBILITY_PRESERVATION.md');
  const readme = readText('README.md');
  const status = readText('docs/IMPLEMENTATION_STATUS.md');
  const mainRs = readTextIfExists('crates/xhubd/src/main.rs');

  const checks = [
    requireNeedles('RHM-015 contract', rhm015, REQUIRED_DOC_NEEDLES),
    requireNeedles('README', readme, REQUIRED_README_NEEDLES),
    requireNeedles('implementation status', status, REQUIRED_STATUS_NEEDLES),
    checkNoSwiftProductUiInRustPackage(),
    checkNoEmbeddedProductUiDirs(),
    checkPackageIncludesGate(),
  ];
  if (mainRs === null) {
    checks.push({
      label: 'xhubd_source_page_static_check',
      ok: true,
      skipped: true,
      reason: 'source_not_packaged',
      packaged_binary_present: fs.existsSync(path.join(ROOT_DIR, 'bin', 'xhubd')),
    });
  } else {
    const rootBody = extractRootBody(mainRs);
    checks.push(
      requireNeedles('xhubd main readiness/page', mainRs, REQUIRED_MAIN_NEEDLES),
      checkRootPageDiagnosticOnly(rootBody),
    );
  }

  process.stdout.write(`${JSON.stringify({
    ok: true,
    schema_version: 'xhub.rust_hub.ui_compatibility_no_product_ui_change_gate.v1',
    command: 'ui-compatibility-no-product-ui-change-gate',
    product_ui_change: false,
    swift_ui_files_touched: false,
    rust_browser_product_ui: false,
    rust_browser_diagnostic_only: true,
    node_remains_authority: true,
    memory_writer_authority_in_rust: false,
    protected_product_ui_surface_count: PROTECTED_PRODUCT_UI_SURFACES.length,
    protected_product_ui_surfaces: PROTECTED_PRODUCT_UI_SURFACES,
    checks,
  }, null, 2)}\n`);
}

try {
  main();
} catch (error) {
  process.stderr.write(`[ui_compatibility_no_product_ui_change_gate] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
}
