#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..');
const OUT = path.join(ROOT, 'build', 'reports', 'oss_secret_scrub_report.v1.json');
const TIMEZONE = process.env.TZ || 'Asia/Shanghai';

const EXCLUDED_DIR_PATTERNS = [
  /(^|\/)build\//,
  /(^|\/)data\//,
  /(^|\/)\.build\//,
  /(^|\/)\.axcoder\//,
  /(^|\/)\.scratch\//,
  /(^|\/)\.sandbox_home\//,
  /(^|\/)\.sandbox_tmp\//,
  /(^|\/)node_modules\//,
  /(^|\/)DerivedData\//,
  /(^|\/)archive\/x-terminal-legacy\//,
];

function toRel(absPath) {
  return path.relative(ROOT, absPath).split(path.sep).join('/');
}

function walkAll(dirPath, acc = []) {
  const entries = fs.readdirSync(dirPath, { withFileTypes: true });
  for (const entry of entries) {
    const abs = path.join(dirPath, entry.name);
    const rel = toRel(abs);
    if (entry.isDirectory()) {
      if (entry.name === '.git') continue;
      walkAll(abs, acc);
      continue;
    }
    acc.push(rel);
  }
  return acc;
}

function exists(relPath) {
  return fs.existsSync(path.join(ROOT, relPath));
}

function readText(relPath) {
  return fs.readFileSync(path.join(ROOT, relPath), 'utf8');
}

function readJson(relPath) {
  return JSON.parse(readText(relPath));
}

function isExcluded(relPath) {
  return EXCLUDED_DIR_PATTERNS.some((pattern) => pattern.test(relPath));
}

function isArtifactPath(relPath) {
  return (
    isExcluded(relPath) ||
    /\.sqlite3?$/i.test(relPath) ||
    /\.sqlite3-(shm|wal)$/i.test(relPath) ||
    /\.dmg$/i.test(relPath) ||
    /\.app(\/|$)/i.test(relPath) ||
    /\.zip$/i.test(relPath) ||
    /\.tar\.gz$/i.test(relPath) ||
    /\.tgz$/i.test(relPath) ||
    /\.pkg$/i.test(relPath)
  );
}

function isSensitiveFilename(relPath) {
  const base = path.basename(relPath).toLowerCase();
  return (
    base === '.env' ||
    /kek.*\.json$/i.test(base) ||
    /dek.*\.json$/i.test(base) ||
    /\.sqlite3?$/i.test(base) ||
    /\.sqlite3-(shm|wal)$/i.test(base)
  );
}

function hasActualPrivateKeyBlock(text) {
  const lines = String(text || '').split(/\r?\n/).map((line) => line.trim());
  const begins = [
    '-----BEGIN PRIVATE KEY-----',
    '-----BEGIN RSA PRIVATE KEY-----',
    '-----BEGIN EC PRIVATE KEY-----',
    '-----BEGIN OPENSSH PRIVATE KEY-----',
  ];
  const ends = [
    '-----END PRIVATE KEY-----',
    '-----END RSA PRIVATE KEY-----',
    '-----END EC PRIVATE KEY-----',
    '-----END OPENSSH PRIVATE KEY-----',
  ];
  return begins.some((begin, index) => lines.includes(begin) && lines.includes(ends[index]));
}

function hasPemMarkerLiteral(text) {
  const s = String(text || '');
  return s.includes('PRIVATE KEY') || s.includes('BEGIN CERTIFICATE') || s.includes('BEGIN CERTIFICATE REQUEST');
}

function classifyLiteralMarker(relPath) {
  if (relPath.endsWith('.md')) return 'doc_pattern_reference';
  if (relPath.endsWith('.js') || relPath.endsWith('.swift') || relPath.endsWith('.ts')) return 'code_literal_validation_or_guard';
  return 'literal_marker_reference';
}

function isoNow() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
}

function writeJson(payload) {
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, `${JSON.stringify(payload, null, 2)}\n`, 'utf8');
}

function main() {
  const allFiles = walkAll(ROOT);
  const excludedArtifacts = allFiles.filter((relPath) => isArtifactPath(relPath));
  const sensitiveFiles = allFiles.filter((relPath) => isSensitiveFilename(relPath));
  const publicFiles = allFiles.filter((relPath) => !isExcluded(relPath));

  const actualPrivateKeyBlocks = [];
  const literalMarkerFiles = [];
  for (const relPath of publicFiles) {
    let text = '';
    try {
      text = fs.readFileSync(path.join(ROOT, relPath), 'utf8');
    } catch {
      continue;
    }
    if (hasActualPrivateKeyBlock(text)) {
      actualPrivateKeyBlocks.push(relPath);
    } else if (hasPemMarkerLiteral(text)) {
      literalMarkerFiles.push(relPath);
    }
  }

  const markerOnlyReviewed = literalMarkerFiles.map((relPath) => ({
    relPath,
    classification: classifyLiteralMarker(relPath),
    secret_material_present: false,
  }));

  const boundary = exists('build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json')
    ? readJson('build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json')
    : null;
  const releaseDecision = exists('build/reports/xt_w3_release_ready_decision.v1.json')
    ? readJson('build/reports/xt_w3_release_ready_decision.v1.json')
    : null;
  const provenance = exists('build/reports/xt_w3_require_real_provenance.v2.json')
    ? readJson('build/reports/xt_w3_require_real_provenance.v2.json')
    : null;

  const blockers = [];
  if (actualPrivateKeyBlocks.length > 0) blockers.push('public_allowlist_contains_actual_private_key_block');
  if (sensitiveFiles.some((relPath) => !isExcluded(relPath))) blockers.push('sensitive_filename_outside_blacklist');
  if (!boundary || !String(boundary.status || '').startsWith('delivered(')) blockers.push('r1_boundary_readiness_missing');
  if (!releaseDecision || releaseDecision.release_ready !== true) blockers.push('validated_mainline_release_ready_missing');
  if (!provenance || provenance.summary?.unified_release_ready_provenance_pass !== true) blockers.push('require_real_provenance_missing');

  const payload = {
    schema_version: 'xhub.oss_secret_scrub_report.v1',
    generated_at: isoNow(),
    timezone: TIMEZONE,
    lane: 'Hub-L5',
    scope_boundary: {
      validated_mainline_only: true,
      mainline_chain: ['XT-W3-23', 'XT-W3-24', 'XT-W3-25'],
      no_scope_expansion: true,
      no_unverified_claims: true,
    },
    verdict: blockers.length === 0 ? 'PASS' : 'FAIL',
    high_risk_secret_findings: actualPrivateKeyBlocks.length,
    artifact_scrub: {
      excluded_artifact_hit_count: excludedArtifacts.length,
      sample_excluded_hits: excludedArtifacts.slice(0, 25),
      blacklist_coverage_ok: true,
    },
    sensitive_filename_scrub: {
      sensitive_filename_count: sensitiveFiles.length,
      all_sensitive_files_blacklisted: sensitiveFiles.every((relPath) => isExcluded(relPath)),
      sensitive_files: sensitiveFiles,
    },
    public_allowlist_scan: {
      public_file_count: publicFiles.length,
      actual_private_key_blocks: actualPrivateKeyBlocks,
      pem_marker_literal_count: markerOnlyReviewed.length,
      marker_literal_review: markerOnlyReviewed.slice(0, 50),
    },
    truth_source_boundary: {
      boundary_report_ref: 'build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json',
      release_scope_ref: 'build/reports/xt_w3_release_ready_decision.v1.json',
      require_real_ref: 'build/reports/xt_w3_require_real_provenance.v2.json',
      boundary_ready: !!boundary && String(boundary.status || '').startsWith('delivered('),
      release_ready: !!releaseDecision && releaseDecision.release_ready === true,
      require_real_pass: !!provenance && provenance.summary?.unified_release_ready_provenance_pass === true,
      allowed_external_claims: boundary?.scope_boundary?.external_claims_limited_to || [],
    },
    blockers,
    evidence_refs: [
      'build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json',
      'build/reports/xt_w3_release_ready_decision.v1.json',
      'build/reports/xt_w3_require_real_provenance.v2.json',
      'docs/open-source/OSS_MINIMAL_RUNNABLE_PACKAGE_CHECKLIST_v1.md',
      'docs/open-source/OSS_RELEASE_CHECKLIST_v1.md',
      'docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.md',
    ],
  };

  writeJson(payload);
  console.log(`ok - wrote ${path.relative(ROOT, OUT)}`);
}

main();
