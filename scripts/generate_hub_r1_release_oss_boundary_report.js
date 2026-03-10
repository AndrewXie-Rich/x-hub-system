#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..');
const OUT_DIR = path.join(ROOT, 'build', 'reports');
const TIMEZONE = process.env.TZ || 'Asia/Shanghai';
const MAINLINE = ['XT-W3-23', 'XT-W3-24', 'XT-W3-25'];

function readText(relPath) {
  return fs.readFileSync(path.join(ROOT, relPath), 'utf8');
}

function readJson(relPath) {
  return JSON.parse(readText(relPath));
}

function exists(relPath) {
  return fs.existsSync(path.join(ROOT, relPath));
}

function writeJson(relPath, payload) {
  const absPath = path.join(ROOT, relPath);
  fs.mkdirSync(path.dirname(absPath), { recursive: true });
  fs.writeFileSync(absPath, `${JSON.stringify(payload, null, 2)}\n`, 'utf8');
}

function isoNow() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
}

function includesAll(text, patterns) {
  return patterns.map((pattern) => ({ pattern, ok: String(text).includes(String(pattern)) }));
}

function walk(dirPath, acc = []) {
  const entries = fs.readdirSync(dirPath, { withFileTypes: true });
  for (const entry of entries) {
    const abs = path.join(dirPath, entry.name);
    const rel = path.relative(ROOT, abs).split(path.sep).join('/');
    if (entry.isDirectory()) {
      if (
        entry.name === 'build' ||
        entry.name === 'node_modules' ||
        entry.name === '.build' ||
        entry.name === '.axcoder' ||
        entry.name === '.sandbox_home' ||
        entry.name === '.sandbox_tmp' ||
        rel === 'x-terminal- legacy'
      ) {
        continue;
      }
      walk(abs, acc);
      continue;
    }
    acc.push(rel);
  }
  return acc;
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

function blacklistCovers(relPath) {
  return (
    /(^|\/)build\//.test(relPath) ||
    /(^|\/)data\//.test(relPath) ||
    /(^|\/)node_modules\//.test(relPath) ||
    /(^|\/)\.build\//.test(relPath) ||
    /(^|\/)\.axcoder\//.test(relPath) ||
    /(^|\/)\.sandbox_home\//.test(relPath) ||
    /(^|\/)\.sandbox_tmp\//.test(relPath) ||
    /(^|\/)DerivedData\//.test(relPath) ||
    /(^|\/)__pycache__\//.test(relPath) ||
    /\.sqlite3?$/i.test(relPath) ||
    /\.sqlite3-(shm|wal)$/i.test(relPath) ||
    /(^|\/)\.env$/i.test(relPath) ||
    /kek/i.test(relPath) ||
    /dek/i.test(relPath) ||
    /secret/i.test(relPath) ||
    /token/i.test(relPath) ||
    /password/i.test(relPath)
  );
}

function pick(obj, keys) {
  const out = {};
  for (const key of keys) out[key] = obj[key];
  return out;
}

function main() {
  const docs = {
    minimal: readText('docs/open-source/OSS_MINIMAL_RUNNABLE_PACKAGE_CHECKLIST_v1.md'),
    release: readText('docs/open-source/OSS_RELEASE_CHECKLIST_v1.md'),
    paths: readText('docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.md'),
  };

  const governanceFiles = [
    'README.md',
    'LICENSE',
    'NOTICE.md',
    'SECURITY.md',
    'CONTRIBUTING.md',
    'CODE_OF_CONDUCT.md',
    'CODEOWNERS',
    'CHANGELOG.md',
    'RELEASE.md',
    '.gitignore',
  ];
  const governanceChecks = governanceFiles.map((relPath) => ({ relPath, ok: exists(relPath) }));

  const releaseDecision = readJson('build/reports/xt_w3_release_ready_decision.v1.json');
  const provenance = readJson('build/reports/xt_w3_require_real_provenance.v2.json');
  const xtReady = readJson('build/xt_ready_gate_e2e_report.json');
  const xtReadySource = readJson('build/xt_ready_evidence_source.json');
  const connectorGate = readJson('build/connector_ingress_gate_snapshot.json');
  const internalPassGlobal = readJson('build/hub_l5_release_internal_pass_lines_report.json');
  const internalPassW3 = readJson('build/reports/xt_w3_internal_pass_lines_release_ready.v1.json');
  const rollback = readJson('build/reports/xt_w3_25_competitive_rollback.v1.json');

  const docChecks = {
    minimal: includesAll(docs.minimal, ['OSS-G0', 'OSS-G5', 'GO|NO-GO|INSUFFICIENT_EVIDENCE', 'build/reports/oss_secret_scrub_report.v1.json']),
    release: includesAll(docs.release, ['OSS-G0', 'OSS-G5', 'build/reports/oss_secret_scrub_report.v1.json', 'rollback']),
    paths: includesAll(docs.paths, ['allowlist-first + fail-closed', 'build/**', '**/*kek*.json', '**/*secret*', 'GO|NO-GO|INSUFFICIENT_EVIDENCE']),
  };

  const sensitiveFindings = walk(ROOT)
    .filter((relPath) => isSensitiveFilename(relPath))
    .map((relPath) => ({ relPath, blacklist_covered: blacklistCovers(relPath) }));

  const boundaryEvidence = [
    'build/reports/xt_w3_23_direct_require_real_provenance_binding.v1.json',
    'build/reports/xt_w3_24_direct_require_real_provenance_binding.v1.json',
    'build/reports/xt_w3_require_real_provenance.v2.json',
    'build/reports/xt_w3_release_ready_decision.v1.json',
    'build/xt_ready_gate_e2e_report.json',
    'build/xt_ready_evidence_source.json',
    'build/connector_ingress_gate_snapshot.json',
    'build/hub_l5_release_internal_pass_lines_report.json',
    'build/reports/xt_w3_24_e_onboard_bootstrap_evidence.v1.json',
    'build/reports/xt_w3_25_e_bootstrap_templates_evidence.v1.json',
    'build/reports/xt_w3_24_f_channel_hub_boundary_evidence.v1.json',
    'build/reports/xt_w3_25_competitive_rollback.v1.json',
  ];
  const boundaryEvidenceChecks = boundaryEvidence.map((relPath) => ({ relPath, ok: exists(relPath) }));

  const outOfScopeCoverageFalse = Object.entries((internalPassW3.checks || {}).coverage_checks || {})
    .filter(([key, value]) => !value && !MAINLINE.includes(key))
    .map(([key]) => key);
  const internalPassAlignment = {
    w3_report_release_decision: String(internalPassW3.release_decision || ''),
    global_report_release_decision: String(internalPassGlobal.release_decision || ''),
    out_of_scope_coverage_false: outOfScopeCoverageFalse,
    release_ready_non_scope_note_present: String(releaseDecision.non_scope_note || '').trim().length > 0,
    effective_source_ref: 'build/hub_l5_release_internal_pass_lines_report.json',
    superseded_ref: 'build/reports/xt_w3_internal_pass_lines_release_ready.v1.json',
    alignment_status:
      String(internalPassGlobal.release_decision || '') === 'GO' &&
      outOfScopeCoverageFalse.length > 0 &&
      String(releaseDecision.non_scope_note || '').trim().length > 0
        ? 'pass(scope_frozen_effective_source_selected)'
        : 'blocked(scope_frozen_internal_pass_lines_alignment_missing)',
  };

  const gateSummary = {
    'OSS-G0': governanceChecks.every((item) => item.ok) ? 'PASS' : 'FAIL',
    'OSS-G1': sensitiveFindings.every((item) => item.blacklist_covered) ? 'PASS' : 'FAIL',
    'OSS-G2': boundaryEvidenceChecks.filter((item) => /bootstrap|onboard/.test(item.relPath)).every((item) => item.ok) ? 'PASS' : 'FAIL',
    'OSS-G3': xtReady.ok === true && connectorGate.snapshot?.pass === true ? 'PASS' : 'FAIL',
    'OSS-G4': governanceChecks.every((item) => item.ok) && docChecks.minimal.every((item) => item.ok) && docChecks.release.every((item) => item.ok) ? 'PASS' : 'FAIL',
    'OSS-G5': rollback.rollback_ready === true && String(internalPassGlobal.release_decision || '') === 'GO' ? 'PASS' : 'FAIL',
  };

  const blockers = [];
  if (!(releaseDecision.release_ready === true && provenance.summary?.release_stance === 'release_ready')) {
    blockers.push('validated_mainline_release_ready_not_bound');
  }
  if (!(xtReady.ok === true && xtReady.require_real_audit_source === true && xtReadySource.selected_source !== 'sample_fixture')) {
    blockers.push('require_real_or_audit_source_not_strict');
  }
  if (!(connectorGate.source_used === 'audit' && connectorGate.snapshot?.pass === true)) {
    blockers.push('connector_gate_not_audit_green');
  }
  if (!(String(internalPassGlobal.release_decision || '') === 'GO' && internalPassAlignment.alignment_status.startsWith('pass'))) {
    blockers.push('internal_pass_lines_scope_alignment_missing');
  }
  if (!(rollback.rollback_ready === true)) {
    blockers.push('rollback_ready_missing');
  }
  if (!sensitiveFindings.every((item) => item.blacklist_covered)) {
    blockers.push('sensitive_path_outside_blacklist_coverage');
  }
  if (!governanceChecks.every((item) => item.ok)) {
    blockers.push('governance_file_missing');
  }
  if (!boundaryEvidenceChecks.every((item) => item.ok)) {
    blockers.push('boundary_evidence_missing');
  }

  const consumerEvidence = {
    xt_main: [
      'build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json',
      'build/reports/xt_w3_release_ready_decision.v1.json',
      'build/reports/xt_w3_require_real_provenance.v2.json',
      'build/xt_ready_gate_e2e_report.json',
      'build/reports/xt_w3_25_competitive_rollback.v1.json',
    ],
    qa_main: [
      'build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json',
      'build/hub_l5_release_internal_pass_lines_report.json',
      'build/xt_ready_evidence_source.json',
      'build/connector_ingress_gate_snapshot.json',
      'docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.md',
    ],
  };

  const readiness = {
    schema_version: 'xhub.hub_l5_r1_release_oss_boundary_readiness.v1',
    generated_at: isoNow(),
    timezone: TIMEZONE,
    lane: 'Hub-L5',
    slice_id: 'R1',
    status: blockers.length === 0
      ? 'delivered(validated_mainline_release_oss_boundary_ready)'
      : 'blocked(validated_mainline_release_oss_boundary_gap)',
    scope_boundary: {
      validated_mainline_only: true,
      mainline_chain: MAINLINE,
      no_scope_expansion: true,
      no_unverified_claims: true,
      effective_release_scope_ref: 'build/reports/xt_w3_release_ready_decision.v1.json',
      external_claims_limited_to: [
        'XT memory UX adapter backed by Hub truth-source',
        'Hub-governed multi-channel gateway',
        'Hub-first governed automations',
      ],
    },
    gates: gateSummary,
    release_alignment: {
      require_real: pick(provenance.summary, ['strict_xt_ready_require_real_pass', 'unified_release_ready_provenance_pass', 'release_stance']),
      xt_ready: {
        ok: xtReady.ok === true,
        require_real_audit_source: xtReady.require_real_audit_source === true,
        selected_audit_source: xtReadySource.selected_source,
      },
      connector_gate: {
        source_used: connectorGate.source_used,
        pass: connectorGate.snapshot?.pass === true,
        blocked_event_miss_rate: connectorGate.summary?.blocked_event_miss_rate,
      },
      internal_pass_lines: internalPassAlignment,
      rollback: {
        rollback_ready: rollback.rollback_ready === true,
        rollback_scope: rollback.rollback_scope,
        rollback_mode: rollback.rollback_mode,
      },
    },
    oss_boundary: {
      governance_files: governanceChecks,
      doc_checks: docChecks,
      sensitive_findings: sensitiveFindings,
      public_path_policy: {
        allowlist_first: true,
        fail_closed_blacklist: true,
        must_exclude_paths: sensitiveFindings.map((item) => item.relPath),
      },
    },
    blockers,
    next_action: blockers.length === 0
      ? [
          'XT-Main consumes this report as the Hub-side R1 boundary packet and keeps release messaging frozen to XT-W3-23->24->25 mainline only',
          'QA-Main reuses this report for OSS/public-path review and does not broaden validation scope',
        ]
      : [
          'keep_release_scope_frozen',
          'fix_only_remaining_boundary_blockers',
        ],
    consumer_min_evidence: consumerEvidence,
    evidence_refs: [
      'build/reports/xt_w3_release_ready_decision.v1.json',
      'build/reports/xt_w3_require_real_provenance.v2.json',
      'build/xt_ready_gate_e2e_report.json',
      'build/xt_ready_evidence_source.json',
      'build/connector_ingress_gate_snapshot.json',
      'build/hub_l5_release_internal_pass_lines_report.json',
      'build/reports/xt_w3_internal_pass_lines_release_ready.v1.json',
      'build/reports/xt_w3_25_competitive_rollback.v1.json',
      'docs/open-source/OSS_MINIMAL_RUNNABLE_PACKAGE_CHECKLIST_v1.md',
      'docs/open-source/OSS_RELEASE_CHECKLIST_v1.md',
      'docs/open-source/GITHUB_OSS_PUBLIC_FILE_PATHS_v1.md',
    ],
  };

  const delta = {
    schema_version: 'xhub.hub_l5_r1_release_oss_boundary_delta_3line.v1',
    generated_at: readiness.generated_at,
    timezone: TIMEZONE,
    lane: 'Hub-L5',
    mode: 'delta_3line_only',
    status: readiness.status,
    scope_boundary: readiness.scope_boundary,
    blockers: readiness.blockers,
    next_action: readiness.next_action,
    evidence_refs: [
      'build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json',
      'build/reports/xt_w3_release_ready_decision.v1.json',
      'build/reports/xt_w3_require_real_provenance.v2.json',
    ],
  };

  writeJson('build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json', readiness);
  writeJson('build/reports/hub_l5_r1_release_oss_boundary_delta_3line.v1.json', delta);
  console.log('ok - wrote build/reports/hub_l5_r1_release_oss_boundary_readiness.v1.json');
  console.log('ok - wrote build/reports/hub_l5_r1_release_oss_boundary_delta_3line.v1.json');
}

main();
