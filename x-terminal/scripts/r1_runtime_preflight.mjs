import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import http from 'node:http';
import https from 'node:https';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import {
  assertRunRoot, isInside, readJSON, regularFile, requireCondition, sha256,
  safeOutputDirectory, sourceSnapshot, writeNewJSON,
} from './lib/r1_evidence.mjs';
import { sourceTree } from '../tools/build_provenance.mjs';

const xtRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repositoryRoot = path.dirname(xtRoot);
const generatedReportRoot = path.join(repositoryRoot, 'build', 'reports', 'xt-v1-product-readiness');
const defaultHubApp = path.join(repositoryRoot, 'build', 'X-Hub.app');
const defaultXTApp = path.join(repositoryRoot, 'build', 'X-Terminal.app');
const defaultPairingURL = 'http://127.0.0.1:50052/pairing/discovery';
const discoveryBodyLimit = 64 * 1024;

export function parseArguments(args) {
  const options = {
    profileRoot: '',
    report: '',
    hubApp: defaultHubApp,
    xtApp: defaultXTApp,
    pairingURL: defaultPairingURL,
    timeoutMs: 2_000,
  };
  const names = {
    '--profile-root': 'profileRoot', '--report': 'report', '--hub-app': 'hubApp',
    '--xt-app': 'xtApp', '--pairing-url': 'pairingURL', '--timeout-ms': 'timeoutMs',
  };
  const seen = new Set();
  for (let index = 0; index < args.length; index += 1) {
    const argument = args[index];
    if (argument === '--help' || argument === '-h') return { help: true };
    requireCondition(names[argument] && args[index + 1] && !args[index + 1].startsWith('--'), 'invalid_argument');
    requireCondition(!seen.has(argument), 'duplicate_argument');
    seen.add(argument);
    options[names[argument]] = args[++index];
  }
  requireCondition(options.profileRoot, 'profile_root_required');
  requireCondition(options.report, 'report_required');
  const timeout = Number(options.timeoutMs);
  requireCondition(Number.isInteger(timeout) && timeout >= 250 && timeout <= 30_000, 'invalid_timeout');
  options.timeoutMs = timeout;
  const parsed = new URL(options.pairingURL);
  requireCondition(parsed.pathname === '/pairing/discovery' && !parsed.search && !parsed.hash, 'invalid_pairing_url');
  if (parsed.protocol === 'http:') {
    requireCondition(parsed.hostname === '127.0.0.1' || parsed.hostname === 'localhost' || parsed.hostname === '[::1]', 'plaintext_pairing_requires_loopback');
  } else requireCondition(parsed.protocol === 'https:', 'pairing_transport_requires_https');
  return options;
}

function redactedPath(value) {
  const absolute = path.resolve(value);
  if (absolute === repositoryRoot || isInside(repositoryRoot, absolute)) {
    return '<repository-root>/' + path.relative(repositoryRoot, absolute).split(path.sep).join('/');
  }
  if (absolute === xtRoot || isInside(xtRoot, absolute)) {
    return '<x-terminal-root>/' + path.relative(xtRoot, absolute).split(path.sep).join('/');
  }
  if (absolute === '/Applications' || isInside('/Applications', absolute)) {
    return '<applications>/' + path.relative('/Applications', absolute).split(path.sep).join('/');
  }
  if (absolute === os.tmpdir() || isInside(os.tmpdir(), absolute)) return '<temporary-root>/' + path.relative(os.tmpdir(), absolute).split(path.sep).join('/');
  return '<external-path>';
}

function appObservation(appPath, executableName, product) {
  const resolvedApp = path.resolve(appPath);
  const executablePath = path.join(resolvedApp, 'Contents', 'MacOS', executableName);
  const provenancePath = path.join(resolvedApp, 'Contents', 'Resources', 'xterminal-build-provenance.v1.json');
  const allowedLocation = resolvedApp === path.join(repositoryRoot, 'build', `${product}.app`)
    || resolvedApp === path.join('/Applications', `${product}.app`);
  const result = {
    product: product === 'X-Terminal' ? 'x-terminal' : 'x-hub',
    app_path: redactedPath(resolvedApp),
    executable_path: redactedPath(executablePath),
    executable_realpath: null,
    executable_sha256: null,
    executable_size_bytes: null,
    present: false,
    canonical_location_verified: allowedLocation,
    source_binding_verified: false,
    signature_verified: false,
    source_provenance: 'missing',
    blocked_reasons: [],
  };
  if (!allowedLocation) result.blocked_reasons.push('noncanonical_app_location');
  try {
    const stat = regularFile(executablePath);
    fs.accessSync(executablePath, fs.constants.X_OK);
    const realpath = fs.realpathSync(executablePath);
    result.present = true;
    result.executable_realpath = redactedPath(realpath);
    result.executable_sha256 = sha256(fs.readFileSync(executablePath));
    result.executable_size_bytes = stat.size;
    try {
      execFileSync('/usr/bin/codesign', ['--verify', '--deep', '--strict', resolvedApp], {
        stdio: 'ignore', timeout: 15_000,
      });
      result.signature_verified = true;
    } catch {
      result.blocked_reasons.push('app_signature_invalid');
    }
  } catch {
    result.blocked_reasons.push(`${result.product.replace('-', '_')}_executable_missing`);
    return result;
  }
  try {
    const provenance = readJSON(provenancePath);
    const currentTree = sourceTree(xtRoot).sha256;
    const sourceMatches = provenance.source?.source_tree_sha256 === currentTree;
    result.source_provenance = {
      schema_version: provenance.schema_version || null,
      source_tree_sha256: provenance.source?.source_tree_sha256 || null,
      file_count: Number(provenance.source?.file_count || 0),
      binary_sha256: provenance.binary?.sha256 || null,
      source_tree_matches_current: sourceMatches,
      binary_sha256_matches_current: provenance.binary?.sha256 === result.executable_sha256,
      binary_hash_scope: provenance.binary?.hash_scope || null,
      secrets_free: provenance.verification?.secrets_included === false,
    };
    if (provenance.schema_version !== 'xt.build_provenance.v1' || provenance.product !== 'x-terminal') {
      result.blocked_reasons.push('invalid_xt_source_provenance');
    } else if (!sourceMatches) {
      result.blocked_reasons.push('xt_source_snapshot_mismatch');
    } else if (result.product === 'x-terminal' && provenance.verification?.secrets_included === false && result.signature_verified) {
      result.source_binding_verified = true;
      result.source_provenance = { ...result.source_provenance, status: 'verified' };
    } else {
      result.blocked_reasons.push('hub_source_provenance_not_supported_by_xt_manifest');
    }
  } catch {
    result.blocked_reasons.push(`${result.product.replace('-', '_')}_source_provenance_missing`);
  }
  return result;
}

function validateDiscoveryPayload(payload, startedAtMs) {
  requireCondition(payload && typeof payload === 'object' && !Array.isArray(payload), 'discovery_invalid_json');
  requireCondition(payload.ok === true && payload.service === 'pairing' && payload.version === 'pairing.v1', 'discovery_contract_invalid');
  requireCondition(payload.pairing_enabled === true, 'pairing_disabled');
  for (const key of ['pairing_port', 'grpc_port']) {
    requireCondition(Number.isInteger(payload[key]) && payload[key] > 0 && payload[key] <= 65_535, 'discovery_port_invalid');
  }
  requireCondition(typeof payload.hub_instance_id === 'string' && payload.hub_instance_id.length > 0 && payload.hub_instance_id.length <= 160, 'discovery_identity_missing');
  requireCondition(Number.isFinite(Number(payload.now_ms)) && Math.abs(Number(payload.now_ms) - startedAtMs) <= 120_000, 'discovery_timestamp_invalid');
  if (payload.tls_mode !== undefined) requireCondition(['insecure', 'tls'].includes(payload.tls_mode), 'discovery_tls_mode_invalid');
  return {
    contract_status: 'pass',
    service: payload.service,
    version: payload.version,
    pairing_enabled: true,
    pairing_port: payload.pairing_port,
    grpc_port: payload.grpc_port,
    hub_instance_id_sha256: createHash('sha256').update(payload.hub_instance_id).digest('hex'),
    pairing_profile_epoch: Number.isInteger(payload.pairing_profile_epoch) ? payload.pairing_profile_epoch : null,
    route_pack_version: typeof payload.route_pack_version === 'string' ? payload.route_pack_version.slice(0, 160) : null,
    xt_contract_endpoint: typeof payload.xt_contract_endpoint === 'string' && payload.xt_contract_endpoint.startsWith('/')
      ? payload.xt_contract_endpoint.slice(0, 160) : null,
    tls_mode: payload.tls_mode === 'tls' ? 'tls' : 'insecure_loopback',
  };
}

export function probeDiscovery(pairingURL, timeoutMs, now = Date.now()) {
  const parsed = new URL(pairingURL);
  const client = parsed.protocol === 'https:' ? https : http;
  return new Promise((resolve) => {
    let settled = false;
    let body = Buffer.alloc(0);
    let deadlineTimer;
    const finish = (result) => {
      if (settled) return;
      settled = true;
      clearTimeout(deadlineTimer);
      resolve(result);
    };
    const request = client.request({
      protocol: parsed.protocol,
      hostname: parsed.hostname,
      port: parsed.port || (parsed.protocol === 'https:' ? 443 : 80),
      path: parsed.pathname,
      method: 'GET',
      headers: { accept: 'application/json', connection: 'close' },
      agent: false,
      maxHeaderSize: 8 * 1024,
      rejectUnauthorized: true,
      timeout: timeoutMs,
    }, (response) => {
      if (response.statusCode >= 300 && response.statusCode < 400) {
        response.destroy();
        finish({ status: 'blocked', reason_code: 'discovery_redirect_refused' });
        return;
      }
      response.on('data', (chunk) => {
        body = Buffer.concat([body, chunk]);
        if (body.length > discoveryBodyLimit) {
          response.destroy();
          finish({ status: 'blocked', reason_code: 'discovery_body_too_large' });
        }
      });
      response.on('end', () => {
        if (settled) return;
        if (response.statusCode < 200 || response.statusCode >= 300) {
          finish({ status: 'blocked', reason_code: `discovery_http_${response.statusCode || 0}` });
          return;
        }
        try {
          finish({ status: 'pass', payload: validateDiscoveryPayload(JSON.parse(body.toString('utf8')), now) });
        } catch (error) {
          finish({ status: 'blocked', reason_code: error.message || 'discovery_contract_invalid' });
        }
      });
    });
    request.on('timeout', () => {
      request.destroy();
      finish({ status: 'blocked', reason_code: 'hub_discovery_timeout' });
    });
    request.on('error', (error) => {
      const code = error.code === 'ETIMEDOUT' ? 'hub_discovery_timeout'
        : error.code === 'EACCES' ? 'hub_discovery_permission_denied' : 'hub_discovery_unreachable';
      finish({ status: 'blocked', reason_code: code });
    });
    deadlineTimer = setTimeout(() => {
      request.destroy();
      finish({ status: 'blocked', reason_code: 'hub_discovery_timeout' });
    }, timeoutMs);
    request.end();
  });
}

function safeReportPath(rawPath, profileRoot) {
  const candidate = path.resolve(rawPath);
  const requestedParent = path.dirname(candidate);
  const parent = requestedParent === generatedReportRoot
    ? (fs.mkdirSync(requestedParent, { recursive: true, mode: 0o700 }), requestedParent)
    : safeOutputDirectory(requestedParent, profileRoot, repositoryRoot);
  requireCondition(fs.realpathSync(parent) === parent, 'report_parent_symlink');
  const resolvedCandidate = path.join(parent, path.basename(candidate));
  requireCondition(isInside(generatedReportRoot, resolvedCandidate), 'report_out_of_scope');
  if (fs.existsSync(resolvedCandidate)) {
    const stat = fs.lstatSync(resolvedCandidate);
    requireCondition(stat.isFile() && stat.nlink === 1, 'unsafe_existing_report');
    throw new Error('report_already_exists');
  }
  return resolvedCandidate;
}

function assertContentFree(value) {
  const text = JSON.stringify(value);
  requireCondition(!/-----BEGIN [A-Z ]*PRIVATE KEY-----|\bBearer\s+\S+|\bsk-[A-Za-z0-9_-]{16,}|\/Users\/|\/home\//.test(text), 'report_secret_or_private_path_detected');
}

export async function runPreflight(options) {
  requireCondition(fs.existsSync(options.profileRoot), 'profile_root_missing');
  const profileRoot = assertRunRoot(options.profileRoot, repositoryRoot);
  const reportPath = safeReportPath(options.report, profileRoot);
  const source = sourceSnapshot(repositoryRoot);
  const bundles = [
    appObservation(options.hubApp, 'XHub', 'X-Hub'),
    appObservation(options.xtApp, 'XTerminal', 'X-Terminal'),
  ];
  const startedAtMs = Date.now();
  const discovery = await probeDiscovery(options.pairingURL, options.timeoutMs, startedAtMs);
  const blockedReasons = bundles.flatMap((bundle) => bundle.blocked_reasons)
    .concat(discovery.status === 'blocked' ? [discovery.reason_code] : [])
    .concat(['owner_local_approval_driver_not_implemented', 'cached_reconnect_driver_not_implemented']);
  const report = {
    schema_version: 'xt.v1_work_order_evidence.v1',
    work_order_id: 'XT-R1-02',
    generated_at: new Date().toISOString(),
    status: 'blocked',
    evidence_source: discovery.status === 'pass' ? 'live_runtime' : 'static_check',
    fixture: false,
    synthetic: false,
    source,
    runtime: {
      hub_build_id: null,
      hub_binary_sha256: bundles[0].executable_sha256,
      xt_build_id: null,
      xt_binary_sha256: bundles[1].executable_sha256,
      xtd_binary_sha256: null,
    },
    lineage: {
      run_id: null,
      session_id: null,
      project_id: null,
      checkpoint_id: null,
      identity_state: 'preflight_only_no_pairing_identity',
    },
    release_eligible: false,
    checks: [
      { check_id: 'canonical_hub_bundle', status: bundles[0].present && bundles[0].canonical_location_verified ? 'pass' : 'blocked', executed: true },
      { check_id: 'canonical_xt_bundle_source_binding', status: bundles[1].source_binding_verified ? 'pass' : 'blocked', executed: true },
      { check_id: 'hub_pairing_discovery', status: discovery.status, executed: true, reason_code: discovery.reason_code || null },
      { check_id: 'owner_local_approval', status: 'blocked', executed: false, reason_code: 'owner_local_approval_driver_not_implemented' },
      { check_id: 'cached_reconnect', status: 'blocked', executed: false, reason_code: 'cached_reconnect_driver_not_implemented' },
    ],
    artifact_refs: [redactedPath(reportPath)],
    audit_refs: [],
    blocked_reasons: [...new Set(blockedReasons)],
    known_limits: [
      'Read-only preflight never starts, stops, or restarts Hub or X-Terminal.',
      'No admin token, pairing secret, provider key, user profile, or pairing material is read or exported.',
      'Discovery is a live transport probe only; owner approval, XT pairing, cached reconnect, and route repair still require a dedicated driver.',
      'A signed app without matching source provenance remains blocked even when its executable exists.',
    ],
    runtime_preflight: {
      profile_root: '<profile-root>',
      profile_private: true,
      profile_realpath_verified: true,
      pairing_url: new URL(options.pairingURL).protocol + '//<redacted-host>:' + (new URL(options.pairingURL).port || (new URL(options.pairingURL).protocol === 'https:' ? 443 : 80)) + '/pairing/discovery',
      bundles,
      discovery: discovery.status === 'pass' ? discovery.payload : { status: 'blocked', reason_code: discovery.reason_code },
      application_processes_started: 0,
      application_processes_stopped: 0,
    },
  };
  assertContentFree(report);
  writeNewJSON(reportPath, report);
  console.log(`[xt-r1-preflight] status=${report.status}`);
  console.log(`[xt-r1-preflight] report=${redactedPath(reportPath)}`);
  console.log(`[xt-r1-preflight] discovery=${discovery.status}${discovery.reason_code ? ` reason=${discovery.reason_code}` : ''}`);
  return 2;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const options = parseArguments(process.argv.slice(2));
    if (options.help) {
      console.log('Usage: xt_r1_runtime_preflight.sh --profile-root <private-temp-dir> --report <build/reports/...json> [--hub-app PATH] [--xt-app PATH] [--pairing-url URL] [--timeout-ms N]');
    } else process.exitCode = await runPreflight(options);
  } catch (error) {
    const code = /^[a-z0-9_]+$/.test(error.message) ? error.message : 'preflight_failed';
    console.error(`[xt-r1-preflight] ${code}`);
    process.exitCode = 2;
  }
}
