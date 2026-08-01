#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

const SCHEMA_VERSION = 'xhub.rust_memory_gateway_execution_release_gate.v1';
const COMMAND = 'rust-memory-gateway-execution-release-gate';

const CAPABILITIES = {
  executionGateHttp: 'execution_gate_http',
  executeHttp: 'execute_http',
  localExecutor: 'local_executor',
  executeApply: 'execute_apply',
  executeCanary: 'execute_canary',
};

const BOOLEAN_OPTIONS = new Map([
  ['--execution-admission', 'executionAdmission'],
  ['--local-executor', 'localExecutor'],
  ['--execute-apply', 'executeApply'],
  ['--canary-only', 'canaryOnly'],
]);

class GateError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function parseBoolean(value, option) {
  const normalized = String(value ?? '').trim().toLowerCase();
  if (['1', 'true', 'yes', 'y', 'on'].includes(normalized)) return true;
  if (['0', 'false', 'no', 'n', 'off'].includes(normalized)) return false;
  throw new GateError('invalid_boolean', `${option} expects a boolean value`);
}

function parseArgs(argv) {
  const out = {
    manifestPath: '',
    executionAdmission: false,
    localExecutor: false,
    executeApply: false,
    canaryOnly: false,
    selfTest: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--manifest') {
      const next = String(argv[i + 1] ?? '').trim();
      if (!next) throw new GateError('manifest_path_required', '--manifest requires a path');
      out.manifestPath = next;
      i += 1;
      continue;
    }
    if (arg === '--self-test') {
      out.selfTest = true;
      continue;
    }

    const equalsIndex = arg.indexOf('=');
    const option = equalsIndex === -1 ? arg : arg.slice(0, equalsIndex);
    const target = BOOLEAN_OPTIONS.get(option);
    if (target) {
      if (equalsIndex !== -1) {
        out[target] = parseBoolean(arg.slice(equalsIndex + 1), option);
        continue;
      }
      const next = argv[i + 1];
      if (next != null && !String(next).startsWith('--')) {
        out[target] = parseBoolean(next, option);
        i += 1;
      } else {
        out[target] = true;
      }
      continue;
    }

    throw new GateError('unknown_argument', `unknown argument: ${arg}`);
  }

  return out;
}

function uniqueStrings(values) {
  return [...new Set(values.map((value) => String(value ?? '').trim()).filter(Boolean))];
}

function memoryCapabilityTokens(manifest) {
  const memory = manifest?.capabilities?.memory;
  if (!Array.isArray(memory)) {
    throw new GateError(
      'memory_capabilities_missing',
      'manifest capabilities.memory must be an array of explicit capability tokens',
    );
  }
  return uniqueStrings(memory);
}

function dependencyIssues(config) {
  const issues = [];
  if (config.localExecutor && !config.executionAdmission) {
    issues.push('local_executor_requires_execution_admission');
  }
  if (config.executeApply && !config.executionAdmission) {
    issues.push('execute_apply_requires_execution_admission');
  }
  if (config.executeApply && !config.localExecutor) {
    issues.push('execute_apply_requires_local_executor');
  }
  if (config.canaryOnly && !config.executeApply) {
    issues.push('canary_only_requires_execute_apply');
  }
  return issues;
}

function requiredCapabilities(config) {
  const required = [];
  if (config.executionAdmission) {
    required.push(CAPABILITIES.executionGateHttp, CAPABILITIES.executeHttp);
  }
  if (config.localExecutor) required.push(CAPABILITIES.localExecutor);
  if (config.executeApply) {
    required.push(CAPABILITIES.executeHttp, CAPABILITIES.executeApply);
  }
  if (config.canaryOnly) required.push(CAPABILITIES.executeCanary);
  return uniqueStrings(required);
}

function evaluate(manifest, config, manifestPath = '') {
  const tokens = memoryCapabilityTokens(manifest);
  const required = requiredCapabilities(config);
  const present = required.filter((token) => tokens.includes(token));
  const missing = required.filter((token) => !tokens.includes(token));
  const dependencies = dependencyIssues(config);
  const issues = [
    ...dependencies,
    ...missing.map((token) => `missing_capability:${token}`),
  ];
  const allDisabled = !config.executionAdmission
    && !config.localExecutor
    && !config.executeApply
    && !config.canaryOnly;

  return {
    ok: issues.length === 0,
    schema_version: SCHEMA_VERSION,
    command: COMMAND,
    manifest_path: manifestPath,
    all_execution_features_disabled: allDisabled,
    requested: {
      execution_admission: config.executionAdmission,
      local_executor: config.localExecutor,
      execute_apply: config.executeApply,
      canary_only: config.canaryOnly,
    },
    memory_capability_tokens: tokens,
    required,
    present,
    missing,
    dependency_issues: dependencies,
    issues,
  };
}

function assert(condition, message) {
  if (!condition) throw new GateError('self_test_failed', message);
}

function runSelfTest() {
  const currentManifest = {
    capabilities: {
      memory: ['retrieve', 'write', 'gateway_context', 'readiness'],
    },
  };
  const allCapabilitiesManifest = {
    capabilities: {
      memory: Object.values(CAPABILITIES),
    },
  };

  const disabled = evaluate(currentManifest, parseArgs([]), '/tmp/current-capabilities.json');
  assert(disabled.ok === true, 'all-disabled configuration must pass the current manifest');
  assert(disabled.required.length === 0 && disabled.missing.length === 0, 'all-disabled configuration must require no execution capability');

  const dependencyFailure = evaluate(
    allCapabilitiesManifest,
    parseArgs(['--local-executor']),
    '/tmp/all-capabilities.json',
  );
  assert(dependencyFailure.ok === false, 'local executor without admission must fail');
  assert(
    dependencyFailure.dependency_issues.includes('local_executor_requires_execution_admission'),
    'local executor dependency issue must be reported',
  );

  const applyDependencyFailure = evaluate(
    allCapabilitiesManifest,
    parseArgs(['--execute-apply']),
    '/tmp/all-capabilities.json',
  );
  assert(applyDependencyFailure.ok === false, 'execute apply without admission and local executor must fail');
  assert(
    applyDependencyFailure.dependency_issues.includes('execute_apply_requires_execution_admission'),
    'execute apply admission dependency issue must be reported',
  );
  assert(
    applyDependencyFailure.dependency_issues.includes('execute_apply_requires_local_executor'),
    'execute apply local-executor dependency issue must be reported',
  );

  const canaryDependencyFailure = evaluate(
    allCapabilitiesManifest,
    parseArgs(['--execution-admission', '--local-executor', '--canary-only']),
    '/tmp/all-capabilities.json',
  );
  assert(canaryDependencyFailure.ok === false, 'canary without execute apply must fail');
  assert(
    canaryDependencyFailure.dependency_issues.includes('canary_only_requires_execute_apply'),
    'canary execute-apply dependency issue must be reported',
  );

  const missingCapabilities = evaluate(
    currentManifest,
    parseArgs(['--execution-admission']),
    '/tmp/current-capabilities.json',
  );
  assert(missingCapabilities.ok === false, 'explicit admission must fail without endpoint capabilities');
  assert(missingCapabilities.missing.includes(CAPABILITIES.executionGateHttp), 'execution gate capability must be missing');
  assert(missingCapabilities.missing.includes(CAPABILITIES.executeHttp), 'execute HTTP capability must be missing');

  const fullyEnabled = evaluate(
    allCapabilitiesManifest,
    parseArgs([
      '--execution-admission=1',
      '--local-executor', 'true',
      '--execute-apply',
      '--canary-only', 'yes',
    ]),
    '/tmp/all-capabilities.json',
  );
  assert(fullyEnabled.ok === true, 'fully enabled configuration must pass a complete manifest');
  assert(fullyEnabled.missing.length === 0, 'complete manifest must have no missing capabilities');

  return {
    ok: true,
    schema_version: `${SCHEMA_VERSION}.self_test`,
    command: COMMAND,
    cases: {
      all_disabled_current_manifest: disabled.ok,
      local_dependency_failure_detected: dependencyFailure.ok === false,
      apply_dependency_failure_detected: applyDependencyFailure.ok === false,
      canary_dependency_failure_detected: canaryDependencyFailure.ok === false,
      missing_capabilities_detected: missingCapabilities.ok === false,
      fully_enabled_complete_manifest: fullyEnabled.ok,
    },
  };
}

function readManifest(manifestPath) {
  const resolved = path.resolve(manifestPath);
  if (!fs.existsSync(resolved)) {
    throw new GateError('manifest_missing', `manifest does not exist: ${resolved}`);
  }
  try {
    return { resolved, value: JSON.parse(fs.readFileSync(resolved, 'utf8')) };
  } catch (error) {
    throw new GateError('manifest_not_parseable', `manifest is not valid JSON: ${error.message}`);
  }
}

function writeJson(value) {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

function main() {
  const config = parseArgs(process.argv.slice(2));
  if (config.selfTest) {
    writeJson(runSelfTest());
    return;
  }
  if (!config.manifestPath) {
    throw new GateError('manifest_required', '--manifest is required');
  }

  const manifest = readManifest(config.manifestPath);
  const report = evaluate(manifest.value, config, manifest.resolved);
  writeJson(report);
  if (!report.ok) process.exitCode = 2;
}

try {
  main();
} catch (error) {
  writeJson({
    ok: false,
    schema_version: SCHEMA_VERSION,
    command: COMMAND,
    error_code: String(error?.code || 'release_gate_failed'),
    message: String(error?.message || error),
    required: [],
    present: [],
    missing: [],
    dependency_issues: [],
    issues: [String(error?.code || 'release_gate_failed')],
  });
  process.exitCode = 1;
}
