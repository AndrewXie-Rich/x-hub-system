import fs from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import {
  assertRunRoot, capture, evaluateGoldenResult, git, gitEnvironment, isInside,
  readJSON, regularFile, replaceJSON, requireCondition, safeOutputDirectory,
  sha256, sourceSnapshot, writeNewJSON,
} from './lib/r1_evidence.mjs';

const xtRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repositoryRoot = path.dirname(xtRoot);
const fixtureRoot = path.join(xtRoot, 'scripts', 'fixtures', 'xt_v1_golden_project');
const sourceSeam = 'Sources/GoldenProject/Greeting.swift';
const fixturePaths = [
  'Package.swift', 'TASK.md', sourceSeam, 'Sources/GoldenProjectTests/main.swift',
  'Tests/GoldenProjectAcceptanceTests/GreetingTests.swift',
];
const phaseDefinitions = {
  prepare: ['XT-R1-01', 'golden_project_baseline.v1.json'],
  pairing: ['XT-R1-02', 'pairing_reconnect.v1.json'],
  route: ['XT-R1-03', 'interactive_model_route.v1.json'],
  create: ['XT-R1-04', 'project_governance_binding.v1.json'],
  mutate: ['XT-R1-05', 'mutation_diagnostics.v1.json'],
  checkpoint: ['XT-R1-06', 'checkpoint_ready.v1.json'],
  resume: ['XT-R1-06', 'checkpoint_recovery.v1.json'],
  review: ['XT-R1-07', 'review_completion.v1.json'],
  negative: ['XT-R1-08', 'negative_repair.v1.json'],
};
const publicPhases = ['prepare', 'create', 'mutate', 'checkpoint', 'resume', 'review', 'negative', 'all'];
const livePhaseOrder = ['pairing', 'route', 'create', 'mutate', 'checkpoint', 'resume', 'review', 'negative'];

export function parseArguments(args) {
  const options = { testDriver: 'swift-test', selfTest: false };
  const names = {
    '--phase': 'phase', '--run-root': 'runRoot', '--report-root': 'reportRoot',
    '--report': 'report', '--hub-app': 'hubApp', '--xt-app': 'xtApp',
    '--checkpoint-id': 'checkpointID', '--test-driver': 'testDriver',
  };
  const seen = new Set();
  for (let index = 0; index < args.length; index += 1) {
    const argument = args[index];
    requireCondition(!seen.has(argument), 'duplicate_argument');
    seen.add(argument);
    if (argument === '--help' || argument === '-h') return { help: true };
    if (argument === '--self-test') {
      options.selfTest = true;
      continue;
    }
    requireCondition(names[argument] && args[index + 1] && !args[index + 1].startsWith('--'), 'invalid_argument');
    options[names[argument]] = args[++index];
  }
  requireCondition(publicPhases.includes(options.phase), 'invalid_phase');
  requireCondition(['swift-test', 'standalone'].includes(options.testDriver), 'invalid_test_driver');
  requireCondition(!(options.report && options.reportRoot), 'conflicting_report_options');
  requireCondition(!options.report || options.phase === 'prepare', 'report_requires_prepare');
  requireCondition(!options.checkpointID || options.phase === 'resume', 'checkpoint_requires_resume');
  requireCondition(!options.selfTest || ['prepare', 'all'].includes(options.phase), 'self_test_requires_prepare');
  return options;
}

function lineageIDs(manifest) {
  return {
    run_id: manifest.run_id,
    session_id: manifest.session_id,
    project_id: manifest.project_id,
    checkpoint_id: null,
    identity_state: 'reserved_for_disposable_project',
  };
}

function initialize(options) {
  requireCondition(git(repositoryRoot, ['rev-parse', '--show-toplevel']).trim() === repositoryRoot, 'noncanonical_root');
  git(repositoryRoot, ['ls-files', '--error-unmatch', 'x-terminal/Package.swift', 'x-terminal/tools/build_xterminal_app.command']);
  const runRoot = assertRunRoot(options.runRoot, repositoryRoot);
  const manifestPath = path.join(runRoot, 'r1-lineage.v1.json');
  const existing = fs.existsSync(manifestPath) ? readJSON(manifestPath) : null;
  if (!existing) requireCondition(fs.readdirSync(runRoot).length === 0, 'new_run_root_must_be_empty');
  const reportName = options.report ? path.basename(options.report) : phaseDefinitions.prepare[1];
  requireCondition(reportName === phaseDefinitions.prepare[1], 'report_name_must_match_authority');
  const requestedReportRoot = options.report ? path.dirname(options.report)
    : (options.reportRoot || path.join(runRoot, 'reports'));
  const reportRoot = safeOutputDirectory(requestedReportRoot, runRoot, repositoryRoot);
  const source = sourceSnapshot(repositoryRoot);
  if (existing) {
    requireCondition(existing.schema_version === 'xt.r1_lineage_manifest.v1', 'invalid_lineage_schema');
    for (const key of ['run_id', 'session_id', 'project_id']) {
      requireCondition(/^[0-9a-f-]{36}$/.test(existing[key]), 'invalid_lineage_id');
    }
    requireCondition(existing.run_root === runRoot && existing.report_root === reportRoot, 'lineage_root_mismatch');
    requireCondition(existing.source.snapshot_sha256 === source.snapshot_sha256, 'source_snapshot_changed');
    requireCondition(existing.test_driver === options.testDriver, 'test_driver_changed');
  } else {
    requireCondition(fs.readdirSync(reportRoot).length === 0, 'report_root_not_empty');
  }
  const manifest = existing || {
    schema_version: 'xt.r1_lineage_manifest.v1',
    run_id: randomUUID(), session_id: randomUUID(), project_id: randomUUID(),
    run_root: runRoot, report_root: reportRoot, source,
    test_driver: options.testDriver,
    created_at: new Date().toISOString(),
    baseline: null,
  };
  const ownerPath = path.join(reportRoot, 'r1-report-owner.v1.json');
  if (existing) {
    requireCondition(readJSON(ownerPath).run_id === manifest.run_id, 'report_owner_mismatch');
  } else {
    writeNewJSON(ownerPath, { schema_version: 'xt.r1_report_owner.v1', run_id: manifest.run_id });
    writeNewJSON(manifestPath, manifest);
  }
  const attemptID = randomUUID();
  const attemptsRoot = path.join(reportRoot, 'attempts');
  if (fs.existsSync(attemptsRoot)) {
    requireCondition(fs.lstatSync(attemptsRoot).isDirectory() && fs.realpathSync(attemptsRoot) === attemptsRoot,
      'unsafe_attempt_directory');
  } else fs.mkdirSync(attemptsRoot, { mode: 0o700 });
  const attemptRoot = path.join(attemptsRoot, attemptID);
  fs.mkdirSync(attemptRoot, { mode: 0o700 });
  return { options, runRoot, reportRoot, manifest, manifestPath, attemptID, attemptRoot, reports: {} };
}

export function evidenceEnvelope(manifest, workOrderID, status, reasons = []) {
  return {
    schema_version: 'xt.v1_work_order_evidence.v1',
    work_order_id: workOrderID,
    generated_at: new Date().toISOString(),
    status,
    evidence_source: 'static_check',
    fixture: false,
    synthetic: false,
    source: manifest.source,
    runtime: {
      hub_build_id: null, hub_binary_sha256: null, xt_build_id: null,
      xt_binary_sha256: null, xtd_binary_sha256: null,
    },
    lineage: lineageIDs(manifest),
    release_eligible: false,
    checks: [],
    artifact_refs: [],
    audit_refs: [],
    blocked_reasons: reasons,
    known_limits: [],
  };
}

function savePhase(context, phase, report) {
  const filename = phaseDefinitions[phase][1];
  const artifact = path.join(context.attemptRoot, filename);
  writeNewJSON(artifact, report);
  context.reports[phase] = report;
}

function copyFixture(destination) {
  fs.mkdirSync(destination, { mode: 0o700 });
  for (const relative of fixturePaths) {
    const source = path.join(fixtureRoot, relative);
    regularFile(source);
    const target = path.join(destination, relative);
    fs.mkdirSync(path.dirname(target), { recursive: true, mode: 0o700 });
    fs.copyFileSync(source, target, fs.constants.COPYFILE_EXCL);
  }
}

export function negativeCaseContracts() {
  return [
    ['hub_unreachable_before_model_call', 'before_model_call', 'hub_unreachable', 'Restore the owned Hub route, verify it, then retry from the same checkpoint.'],
    ['hub_restart_after_tool_result', 'after_tool_result', 'hub_restarted_during_run', 'Reconnect to the owned Hub and resume the exact checkpoint without replaying mutation.'],
    ['model_route_cooldown', 'interactive_model_route', 'model_route_unavailable', 'Select an authorized ready route or wait for cooldown and repeat the canary.'],
    ['project_root_mismatch', 'create_project_scope_binding', 'project_root_mismatch', 'Repair the disposable root binding and re-read effective governance.'],
    ['grant_expired', 'governed_tool_dispatch', 'grant_expired', 'Request a fresh grant, verify its digest, then resume without skipping review.'],
  ].map(([caseID, injectionPoint, reasonCode, repair]) => ({
    case_id: caseID,
    injection_point: injectionPoint,
    proposed_reason_code: reasonCode,
    reason_code_mapping_verified: false,
    directed_repair: repair,
    status: 'insufficient_evidence',
    observed_reason_code: null,
    pre_mutation_count: null,
    post_mutation_count: null,
    duplicate_mutation_count: null,
    teardown_assertion: 'Only verified runner-owned resources may be changed; no repeated mutation or skipped review.',
    teardown_verified: false,
  }));
}

function runtimePreflight(context) {
  const probes = [
    ['hub', context.options.hubApp || path.join(repositoryRoot, 'build', 'X-Hub.app'), 'XHub'],
    ['xt', context.options.xtApp || path.join(repositoryRoot, 'build', 'X-Terminal.app'), 'XTerminal'],
  ];
  return probes.map(([component, app, executable]) => {
    const filename = path.join(path.resolve(app), 'Contents', 'MacOS', executable);
    let present = false;
    let digest = null;
    try {
      regularFile(filename);
      fs.accessSync(filename, fs.constants.X_OK);
      present = true;
      digest = sha256(fs.readFileSync(filename));
    } catch {}
    return {
      component,
      executable_present: present,
      observed_binary_sha256: digest,
      source_binding_verified: false,
      runner_started_process: false,
      live_readiness_verified: false,
    };
  });
}

function unavailablePhase(context, phase, preflight) {
  const reasons = ['live_phase_driver_not_implemented'];
  if (!context.manifest.baseline) reasons.push('verified_baseline_missing');
  if (phase === 'pairing') reasons.push('isolated_pairing_reconnect_evidence_missing');
  if (phase === 'route') reasons.push('live_model_usage_audit_lineage_missing');
  if (phase === 'resume') reasons.push(context.options.checkpointID ? 'checkpoint_not_produced_by_runtime' : 'checkpoint_id_missing');
  for (const probe of preflight) if (!probe.executable_present) reasons.push(probe.component + '_executable_missing');
  const report = evidenceEnvelope(context.manifest, phaseDefinitions[phase][0], 'blocked', reasons);
  report.checks = [{ check_id: phase + '_live_runtime', status: 'blocked', executed: false }];
  report.runtime_preflight = preflight;
  report.known_limits = [
    'This phase has no implemented live driver and cannot pass, even when application bundles exist.',
    'No old report, claimed checkpoint ID, or static fixture can unlock this phase.',
  ];
  if (phase === 'negative') report.negative_cases = negativeCaseContracts();
  savePhase(context, phase, report);
}

export function aggregateEvidence(manifest, reports) {
  const statuses = Object.fromEntries(Object.keys(phaseDefinitions).map((phase) => [
    phase, reports[phase]?.status || 'insufficient_evidence',
  ]));
  const failure = Object.values(statuses).includes('fail');
  const report = evidenceEnvelope(manifest, 'XT-R1-08', failure ? 'fail' : 'insufficient_evidence',
    ['r1_live_chain_not_implemented', 'r0_live_readiness_not_verified']);
  report.report_schema_version = 'xt.r1_first_real_task.v1';
  report.decision = failure ? 'NO-GO' : 'INSUFFICIENT_EVIDENCE';
  report.product_verdict = report.decision;
  report.phase_statuses = statuses;
  report.required_work_order_ids = [...new Set(Object.values(phaseDefinitions).map(([identifier]) => identifier))];
  report.negative_cases = reports.negative?.negative_cases || negativeCaseContracts();
  report.known_limits = [
    'Baseline/authoring contract checks do not establish live product readiness.',
    'Pairing, route, create, mutate, checkpoint, resume, review, and fault-injection live drivers remain unimplemented.',
    'No release GO is available in this bootstrap runner.',
  ];
  return report;
}

function assertContentFree(value) {
  const serialized = JSON.stringify(value);
  requireCondition(!/-----BEGIN [A-Z ]*PRIVATE KEY-----|\bBearer\s+\S+|\bsk-[A-Za-z0-9_-]{16,}|\/Users\/|\/home\//.test(serialized),
    'report_secret_or_private_path_detected');
}

function exportReports(context) {
  const cleanup = {
    schema_version: 'xt.r1_cleanup_ledger.v1',
    lineage: lineageIDs(context.manifest),
    formal_project_retained: fs.existsSync(path.join(context.runRoot, 'golden-project')),
    authoring_copy_removed: context.reports.prepare?.authoring_self_test?.reference_copy_removed === true,
    runner_owned_application_process_count: 0,
    user_processes_touched: false,
    user_profiles_touched: false,
    automatic_project_cleanup: false,
  };
  writeNewJSON(path.join(context.attemptRoot, 'cleanup_ledger.v1.json'), cleanup);
  const summary = aggregateEvidence(context.manifest, context.reports);
  summary.artifact_refs = fs.readdirSync(context.attemptRoot).sort()
    .map((filename) => path.relative(context.reportRoot, path.join(context.attemptRoot, filename)));
  writeNewJSON(path.join(context.attemptRoot, 'first_real_task.v1.json'), summary);
  const artifacts = fs.readdirSync(context.attemptRoot).sort().map((filename) => {
    const artifact = path.join(context.attemptRoot, filename);
    const payload = readJSON(artifact);
    assertContentFree(payload);
    return { ref: path.relative(context.reportRoot, artifact), sha256: sha256(fs.readFileSync(artifact)) };
  });
  writeNewJSON(path.join(context.attemptRoot, 'artifact_index.v1.json'), {
    schema_version: 'xt.r1_artifact_index.v1',
    lineage: lineageIDs(context.manifest),
    attempt_id: context.attemptID,
    artifacts,
    secret_scrub: { status: 'pass', scope: 'exported_json_only', raw_command_output_exported: false },
  });
  for (const filename of fs.readdirSync(context.attemptRoot)) {
    const payload = readJSON(path.join(context.attemptRoot, filename));
    const latest = path.join(context.reportRoot, filename);
    if (fs.existsSync(latest)) {
      requireCondition(readJSON(latest).lineage?.run_id === context.manifest.run_id, 'foreign_latest_report');
      replaceJSON(latest, payload);
    } else writeNewJSON(latest, payload);
  }
  console.log('[xt-r1] decision=' + summary.decision);
  console.log('[xt-r1] report=' + path.join(context.reportRoot, 'first_real_task.v1.json'));
  return summary.status === 'fail' ? 1 : 2;
}

export async function runR1(options) {
  const context = initialize(options);
  const preflight = runtimePreflight(context);
  try {
    if (options.phase === 'prepare' || options.phase === 'all') {
      await preparePhase(context);
    } else if (context.manifest.baseline) {
      await preparePhase(context);
    }
    if (options.phase !== 'prepare') {
      const phases = options.phase === 'all' ? livePhaseOrder : [options.phase];
      for (const phase of phases) unavailablePhase(context, phase, preflight);
    }
    const current = sourceSnapshot(repositoryRoot);
    requireCondition(current.snapshot_sha256 === context.manifest.source.snapshot_sha256, 'source_changed_during_run');
  } catch (error) {
    const phase = options.phase === 'all' ? 'prepare' : options.phase;
    const reason = /^[a-z0-9_]+$/.test(error.message) ? error.message : 'runner_operation_failed';
    const report = evidenceEnvelope(context.manifest, phaseDefinitions[phase][0], 'fail', [reason]);
    const artifactPath = path.join(context.attemptRoot, phaseDefinitions[phase][1]);
    if (fs.existsSync(artifactPath)) {
      writeNewJSON(path.join(context.attemptRoot, 'prior_phase_evidence.v1.json'), readJSON(artifactPath));
      replaceJSON(artifactPath, report);
      context.reports[phase] = report;
    } else savePhase(context, phase, report);
    console.error('[xt-r1] ' + reason);
  }
  return exportReports(context);
}

function projectHashes(projectRoot) {
  return Object.fromEntries(fixturePaths.map((relative) => {
    const filename = path.join(projectRoot, relative);
    regularFile(filename);
    requireCondition(fs.realpathSync(filename) === filename, 'project_file_symlink');
    return [relative, sha256(fs.readFileSync(filename))];
  }));
}

export function validateBaseline(context, report) {
  requireCondition(report.schema_version === 'xt.v1_work_order_evidence.v1'
    && report.work_order_id === 'XT-R1-01', 'baseline_schema_mismatch');
  for (const key of ['run_id', 'session_id', 'project_id']) {
    requireCondition(report.lineage[key] === context.manifest[key], 'baseline_lineage_mismatch');
  }
  requireCondition(report.source.snapshot_sha256 === context.manifest.source.snapshot_sha256, 'baseline_snapshot_mismatch');
  requireCondition(report.reference_repair_applied === false
    && report.baseline?.status === 'pass' && report.fixture === true, 'baseline_not_verified');
  const projectRoot = path.join(context.runRoot, 'golden-project');
  requireCondition(fs.realpathSync(projectRoot) === projectRoot, 'project_root_mismatch');
  const currentHashes = projectHashes(projectRoot);
  requireCondition(JSON.stringify(currentHashes) === JSON.stringify(report.before.file_sha256), 'baseline_project_changed');
  requireCondition(git(projectRoot, ['status', '--porcelain', '--untracked-files=all']) === '', 'baseline_tree_changed');
  requireCondition(git(projectRoot, ['rev-parse', 'HEAD^{tree}']).trim() === report.before.git_tree, 'baseline_git_tree_changed');
  return true;
}

async function goldenCommand(context, projectRoot, label) {
  const stateRoot = path.join(context.runRoot, 'tooling-' + label);
  requireCondition(!fs.existsSync(stateRoot), 'tooling_path_exists');
  fs.mkdirSync(stateRoot, { mode: 0o700 });
  const directories = ['tmp', 'clang', 'swift', 'cache', 'config', 'security', 'profile'];
  for (const directory of directories) fs.mkdirSync(path.join(stateRoot, directory), { mode: 0o700 });
  const command = '/usr/bin/swift';
  const args = [
    context.options.testDriver === 'swift-test' ? 'test' : 'run',
    '--package-path', projectRoot,
    '--scratch-path', path.join(stateRoot, 'scratch'),
    '--cache-path', path.join(stateRoot, 'cache'),
    '--config-path', path.join(stateRoot, 'config'),
    '--security-path', path.join(stateRoot, 'security'),
    '--manifest-cache', 'local', '--disable-netrc', '--disable-keychain',
    '-Xcc', '-fmodules-cache-path=' + path.join(stateRoot, 'clang'),
    '-Xswiftc', '-module-cache-path', '-Xswiftc', path.join(stateRoot, 'swift'),
  ];
  if (context.options.testDriver === 'standalone') args.push('GoldenProjectTests');
  const env = {
    ...gitEnvironment(),
    CFFIXED_USER_HOME: path.join(stateRoot, 'profile'),
    TMPDIR: path.join(stateRoot, 'tmp'),
    CLANG_MODULE_CACHE_PATH: path.join(stateRoot, 'clang'),
  };
  if (process.env.DEVELOPER_DIR) env.DEVELOPER_DIR = process.env.DEVELOPER_DIR;
  const result = await capture(command, args, { cwd: projectRoot, env });
  return {
    ...result,
    command: {
      executable: command, argv: args.map((argument) => argument.replaceAll(context.runRoot, '<run-root>')),
      timeout_seconds: 120, output_limit_bytes: 1048576,
      environment_policy: 'minimal_toolchain_environment',
      output_sha256: sha256(result.output),
    },
  };
}

async function preparePhase(context) {
  if (context.manifest.baseline) {
    const reference = context.manifest.baseline;
    requireCondition(typeof reference.ref === 'string', 'baseline_reference_invalid');
    const baselinePath = path.resolve(context.reportRoot, reference.ref);
    requireCondition(isInside(context.reportRoot, baselinePath), 'baseline_reference_escape');
    regularFile(baselinePath);
    requireCondition(fs.realpathSync(baselinePath) === baselinePath
      && sha256(fs.readFileSync(baselinePath)) === reference.sha256, 'baseline_artifact_changed');
    const report = readJSON(baselinePath);
    validateBaseline(context, report);
    requireCondition(!context.options.selfTest || report.authoring_self_test?.status === 'pass',
      'authoring_self_test_requires_new_run');
    report.baseline_reuse = {
      original_artifact_ref: reference.ref,
      original_artifact_sha256: reference.sha256,
      validated_at: new Date().toISOString(),
      project_rechecked: true,
    };
    savePhase(context, 'prepare', report);
    return;
  }
  const projectRoot = path.join(context.runRoot, 'golden-project');
  requireCondition(!fs.existsSync(projectRoot), 'project_already_exists');
  copyFixture(projectRoot);
  git(projectRoot, ['-c', 'init.templateDir=', 'init', '-q']);
  git(projectRoot, ['add', '--', ...fixturePaths]);
  git(projectRoot, [
    '-c', 'user.name=X-Terminal R1', '-c', 'user.email=xt-r1@example.invalid',
    '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null',
    'commit', '-qm', 'fixture: initialize R1 golden project',
  ]);
  const before = {
    file_sha256: projectHashes(projectRoot),
    source_sha256: sha256(fs.readFileSync(path.join(projectRoot, sourceSeam))),
    git_tree: git(projectRoot, ['rev-parse', 'HEAD^{tree}']).trim(),
  };
  console.log('[xt-r1] running isolated golden baseline (' + context.options.testDriver + ')');
  const result = await goldenCommand(context, projectRoot, 'baseline');
  const baseline = evaluateGoldenResult(result, true);
  const after = projectHashes(projectRoot);
  const sourceUnchanged = JSON.stringify(before.file_sha256) === JSON.stringify(after);
  const standalone = context.options.testDriver === 'standalone';
  let status = baseline.status;
  const reasons = [];
  if (baseline.reason_code) reasons.push(baseline.reason_code);
  if (!sourceUnchanged) {
    status = 'fail';
    reasons.push('baseline_changed_fixture');
  }
  const authoring = {
    requested: context.options.selfTest, status: 'not_run',
    reference_copy_retained: false, reference_copy_removed: false,
  };
  if (context.options.selfTest && baseline.status === 'pass' && sourceUnchanged) {
    const selfRoot = fs.mkdtempSync(path.join(context.runRoot, 'authoring-'));
    const selfProject = path.join(selfRoot, 'project');
    copyFixture(selfProject);
    authoring.reference_copy_retained = true;
    const outcome = readJSON(path.join(fixtureRoot, 'expected_outcome.v1.json'));
    requireCondition(outcome.required_source_path === sourceSeam
      && /^[A-Za-z -]+$/.test(outcome.expected_message), 'invalid_authoring_contract');
    const sourcePath = path.join(selfProject, sourceSeam);
    const original = fs.readFileSync(sourcePath, 'utf8');
    requireCondition(original.includes('"Needs repair"'), 'authoring_seam_changed');
    fs.writeFileSync(sourcePath, original.replace('"Needs repair"', JSON.stringify(outcome.expected_message)));
    console.log('[xt-r1] running reference repair in a separate authoring copy');
    const selfResult = await goldenCommand(context, selfProject, 'authoring');
    const evaluation = evaluateGoldenResult(selfResult, false);
    Object.assign(authoring, evaluation, { command: selfResult.command });
    requireCondition(fs.realpathSync(selfRoot) === selfRoot && isInside(context.runRoot, selfRoot), 'authoring_cleanup_ownership_mismatch');
    fs.rmSync(selfRoot, { recursive: true });
    authoring.reference_copy_retained = false;
    authoring.reference_copy_removed = true;
    if (evaluation.status !== 'pass') {
      status = evaluation.status;
      reasons.push(evaluation.reason_code || 'authoring_repair_failed');
    }
  }
  if (status === 'pass') {
    status = 'insufficient_evidence';
    reasons.push('r0_live_readiness_not_verified');
    if (!context.options.selfTest) reasons.push('authoring_self_test_not_run');
    if (standalone) reasons.push('standalone_not_standard_swift_test');
  }
  const report = evidenceEnvelope(context.manifest, 'XT-R1-01', status, reasons);
  Object.assign(report, {
    evidence_source: 'contract_test',
    fixture: true,
    task_id: 'XT-R1-GOLDEN-GREETING',
    task_schema_version: 'xt.r1_golden_project_expected_outcome.v1',
    project_ref: 'golden-project',
    allowed_paths: [sourceSeam],
    test_driver: context.options.testDriver,
    test_command: result.command,
    baseline,
    before,
    after: { file_sha256: after, source_sha256: after[sourceSeam] },
    authoring_self_test: authoring,
    reference_repair_applied: false,
    network_access: { external_dependencies: 0, kernel_network_isolation_verified: false },
    cleanup_status: 'retained_owned_disposable_resources',
    checks: [
      { check_id: 'deterministic_red_baseline', status: baseline.status },
      { check_id: 'fixture_unchanged', status: sourceUnchanged ? 'pass' : 'fail' },
      { check_id: 'r0_live_readiness', status: 'insufficient_evidence' },
    ],
    known_limits: [
      'Golden fixture execution is contract evidence, not live Hub/XT or Project Coder evidence.',
      'No user pairing profile, provider secret, or application process is read or modified.',
      'The formal disposable project and toolchain caches are retained; only the owned authoring copy is deleted.',
    ],
  });
  savePhase(context, 'prepare', report);
  if (baseline.status === 'pass' && sourceUnchanged && (!authoring.requested || authoring.status === 'pass')) {
    const filename = path.join(context.attemptRoot, phaseDefinitions.prepare[1]);
    context.manifest.baseline = {
      ref: path.relative(context.reportRoot, filename), sha256: sha256(fs.readFileSync(filename)),
    };
    replaceJSON(context.manifestPath, context.manifest);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const options = parseArguments(process.argv.slice(2));
    if (options.help) {
      console.log([
        'Usage: xt_r1_first_real_task_gate.sh --phase prepare|create|mutate|checkpoint|resume|review|negative|all --run-root <empty mktemp directory>',
        'Options: --report-root PATH | --report PATH (prepare only)',
        '         --test-driver swift-test|standalone --self-test',
        '         --hub-app PATH --xt-app PATH --checkpoint-id ID (resume only)',
        'Only fixture preparation is implemented. Other phases emit explicit blocker evidence.',
        'Exit codes: 0 reserved for live pass, 1 failed check, 2 blocked/insufficient evidence or invalid input.',
        'Default reports: <run-root>/reports. Existing runs require the same source snapshot and test driver.',
      ].join('\n'));
    } else process.exitCode = await runR1(options);
  } catch (error) {
    const code = /^[a-z0-9_]+$/.test(error.message) ? error.message : 'invalid_or_inaccessible_run_input';
    console.error('[xt-r1] ' + code);
    process.exitCode = 2;
  }
}
