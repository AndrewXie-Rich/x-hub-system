import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import {
  assertRunRoot, capture, evaluateGoldenResult, git, readJSON, safeOutputDirectory,
  sha256, sourceSnapshot, writeNewJSON,
} from '../scripts/lib/r1_evidence.mjs';
import {
  aggregateEvidence, evidenceEnvelope, negativeCaseContracts, parseArguments, validateBaseline,
} from '../scripts/r1_first_real_task.mjs';

function temporaryDirectory(context) {
  const directory = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'xt-r1-regression-')));
  context.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  return directory;
}

function initialCommit(directory) {
  git(directory, ['-c', 'init.templateDir=', 'init', '-q']);
  git(directory, ['add', '.']);
  git(directory, [
    '-c', 'user.name=R1 Test', '-c', 'user.email=r1-test@example.invalid',
    '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null',
    'commit', '-qm', 'fixture',
  ]);
}

function result(output, exitCode = 1) {
  return { output, exit_code: exitCode, signal: null, reason_code: '' };
}

const redOutput = 'XT_R1_TEST testNonemptyGreeting pass\nXT_R1_TEST testTaskGreeting fail\n';
const greenOutput = redOutput.replace('testTaskGreeting fail', 'testTaskGreeting pass');

test('red baseline requires exactly the expected failing test and a passing control', () => {
  assert.equal(evaluateGoldenResult(result(redOutput), true).status, 'pass');
  assert.equal(evaluateGoldenResult(result(greenOutput, 0), false).status, 'pass');
  assert.equal(evaluateGoldenResult(result(greenOutput, 0), true).status, 'fail');
  assert.equal(evaluateGoldenResult(result(redOutput.replace('testNonemptyGreeting pass', 'testNonemptyGreeting fail')), true).status, 'fail');
});

test('build errors containing a test name cannot masquerade as a red baseline', () => {
  for (const output of [
    'Compiling GreetingTests testTaskGreeting\nerror: fatalError',
    'XT_R1_TEST testTaskGreeting fail\n',
    redOutput + 'XT_R1_TEST testTaskGreeting fail\n',
  ]) {
    assert.equal(evaluateGoldenResult(result(output), true).status, 'fail');
  }
  assert.equal(evaluateGoldenResult(result("error: no such module 'Testing'"), true).status, 'blocked');
  assert.equal(evaluateGoldenResult(result('sandbox-exec: sandbox_apply: Operation not permitted'), true).status, 'blocked');
});

test('timeouts, signals and output truncation never satisfy the fixture contract', () => {
  assert.equal(evaluateGoldenResult({ ...result(redOutput), signal: 'SIGTERM' }, true).status, 'fail');
  for (const code of ['command_timeout', 'output_budget_exceeded', 'command_spawn_failed']) {
    assert.equal(evaluateGoldenResult({ ...result(redOutput), reason_code: code }, true).status, 'blocked');
  }
});

test('process capture enforces timeout and aggregate stdout/stderr budget', async () => {
  const timed = await capture(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], { timeoutMs: 100 });
  assert.equal(timed.reason_code, 'command_timeout');
  const oversized = await capture(process.execPath, ['-e', 'process.stdout.write("A".repeat(2048)); process.stderr.write("B".repeat(2048));'], { maxBytes: 128 });
  assert.equal(oversized.reason_code, 'output_budget_exceeded');
  assert(Buffer.byteLength(oversized.output) <= 128);
});

test('CLI rejects duplicate flags, raw keys, invalid phases and ignored checkpoint arguments', () => {
  assert.equal(parseArguments(['--phase', 'prepare', '--run-root', '/tmp/private']).testDriver, 'swift-test');
  for (const args of [
    ['--phase', 'prepare', '--phase', 'all'],
    ['--phase', 'invalid'],
    ['--phase', 'prepare', '--api-key', 'private-value'],
    ['--phase', 'prepare', '--checkpoint-id', 'checkpoint'],
    ['--phase', 'mutate', '--self-test'],
    ['--phase', 'prepare', '--test-driver', 'mock'],
    ['--phase', 'prepare', '--report-root', 'one', '--report', 'two'],
  ]) assert.throws(() => parseArguments(args));
});

test('disposable roots must be private temporary directories outside Git projects', (context) => {
  const root = temporaryDirectory(context);
  assert.equal(assertRunRoot(root, '/canonical/repository'), root);
  assert.throws(() => assertRunRoot('/tmp', '/canonical/repository'));
  assert.throws(() => assertRunRoot(root, root));
  fs.mkdirSync(path.join(root, '.git'));
  assert.throws(() => assertRunRoot(root, '/canonical/repository'), /inside_git_project/);
});

test('report paths cannot redirect into user state or the golden project', (context) => {
  const root = temporaryDirectory(context);
  const outside = temporaryDirectory(context);
  fs.symlinkSync(outside, path.join(root, 'redirect'));
  assert.throws(() => safeOutputDirectory(path.join(root, 'redirect', 'reports'), root, '/canonical/repository'), /unsafe_report_directory/);
  assert.throws(() => safeOutputDirectory(path.join(root, 'golden-project', 'reports'), root, '/canonical/repository'), /inside_project/);
  const reports = safeOutputDirectory(path.join(root, 'reports'), root, '/canonical/repository');
  const report = path.join(reports, 'first_real_task.v1.json');
  writeNewJSON(report, { status: 'fail' });
  assert.throws(() => writeNewJSON(report, { status: 'pass' }), /EEXIST/);
  assert.equal(readJSON(report).status, 'fail');
});

test('report reads refuse symlink and hardlink artifacts', (context) => {
  const root = temporaryDirectory(context);
  const target = path.join(root, 'target.json');
  writeNewJSON(target, {});
  fs.symlinkSync(target, path.join(root, 'symbolic.json'));
  assert.throws(() => readJSON(path.join(root, 'symbolic.json')), /unsafe_file_type/);
  fs.linkSync(target, path.join(root, 'hard.json'));
  assert.throws(() => readJSON(path.join(root, 'hard.json')), /unsafe_file_type/);
});

test('snapshot fingerprints include staged, unstaged, untracked and deleted source', (context) => {
  const root = temporaryDirectory(context);
  const tracked = path.join(root, 'tracked.swift');
  fs.writeFileSync(tracked, 'initial\n');
  initialCommit(root);
  const original = sourceSnapshot(root);
  fs.writeFileSync(tracked, 'modified\n');
  const unstaged = sourceSnapshot(root);
  assert.notEqual(unstaged.snapshot_sha256, original.snapshot_sha256);
  git(root, ['add', 'tracked.swift']);
  const staged = sourceSnapshot(root);
  assert.notEqual(staged.snapshot_sha256, unstaged.snapshot_sha256);
  const untracked = path.join(root, 'new.swift');
  fs.writeFileSync(untracked, 'new\n');
  const added = sourceSnapshot(root);
  assert.notEqual(added.snapshot_sha256, staged.snapshot_sha256);
  fs.writeFileSync(untracked, 'changed-new\n');
  const changed = sourceSnapshot(root);
  assert.notEqual(changed.snapshot_sha256, added.snapshot_sha256);
  fs.unlinkSync(tracked);
  assert.notEqual(sourceSnapshot(root).snapshot_sha256, changed.snapshot_sha256);
  assert.equal(original.dirty, false);
  assert.equal(added.dirty, true);
  assert.equal(added.git_head, original.git_head);
});

test('baseline validation binds IDs, hashes, realpath and the actual clean Git tree', (context) => {
  const runRoot = temporaryDirectory(context);
  const projectRoot = path.join(runRoot, 'golden-project');
  const fixtureRoot = fileURLToPath(new URL('../scripts/fixtures/xt_v1_golden_project/', import.meta.url));
  const relativeFiles = [
    'Package.swift', 'TASK.md', 'Sources/GoldenProject/Greeting.swift',
    'Sources/GoldenProjectTests/main.swift', 'Tests/GoldenProjectAcceptanceTests/GreetingTests.swift',
  ];
  fs.mkdirSync(projectRoot);
  for (const relative of relativeFiles) {
    const destination = path.join(projectRoot, relative);
    fs.mkdirSync(path.dirname(destination), { recursive: true });
    fs.copyFileSync(path.join(fixtureRoot, relative), destination);
  }
  initialCommit(projectRoot);
  const manifest = {
    run_id: randomUUID(), session_id: randomUUID(), project_id: randomUUID(),
    source: { snapshot_sha256: 'snapshot' },
  };
  const report = {
    ...evidenceEnvelope(manifest, 'XT-R1-01', 'insufficient_evidence'),
    fixture: true, baseline: { status: 'pass' }, reference_repair_applied: false,
    before: {
      file_sha256: Object.fromEntries(relativeFiles.map((relative) => [
        relative, sha256(fs.readFileSync(path.join(projectRoot, relative))),
      ])),
      git_tree: git(projectRoot, ['rev-parse', 'HEAD^{tree}']).trim(),
    },
  };
  const runContext = { runRoot, manifest };
  assert.equal(validateBaseline(runContext, report), true);
  const foreign = structuredClone(report);
  foreign.lineage.session_id = randomUUID();
  assert.throws(() => validateBaseline(runContext, foreign), /lineage_mismatch/);
  const old = structuredClone(report);
  old.source.snapshot_sha256 = 'old-snapshot';
  assert.throws(() => validateBaseline(runContext, old), /snapshot_mismatch/);
  fs.writeFileSync(path.join(projectRoot, 'unexpected.txt'), 'unexpected');
  assert.throws(() => validateBaseline(runContext, report), /tree_changed/);
  fs.writeFileSync(path.join(projectRoot, 'Sources/GoldenProject/Greeting.swift'), 'changed');
  assert.throws(() => validateBaseline(runContext, report), /project_changed/);
});

test('negative scenario plans never contain fabricated observed counts', () => {
  const cases = negativeCaseContracts();
  assert.equal(cases.length, 5);
  for (const scenario of cases) {
    assert.equal(scenario.status, 'insufficient_evidence');
    assert.equal(scenario.pre_mutation_count, null);
    assert.equal(scenario.post_mutation_count, null);
    assert.equal(scenario.duplicate_mutation_count, null);
    assert.equal(scenario.observed_reason_code, null);
    assert.equal(scenario.reason_code_mapping_verified, false);
    assert.equal(scenario.teardown_verified, false);
  }
});

test('bootstrap aggregation includes pairing/route and never yields GO from claimed pass reports', () => {
  const manifest = { run_id: randomUUID(), session_id: randomUUID(), project_id: randomUUID(), source: { dirty: true } };
  const claimed = Object.fromEntries([
    'prepare', 'pairing', 'route', 'create', 'mutate', 'checkpoint', 'resume', 'review', 'negative',
  ].map((phase) => [phase, { status: 'pass' }]));
  const summary = aggregateEvidence(manifest, claimed);
  assert.equal(summary.decision, 'INSUFFICIENT_EVIDENCE');
  assert.equal(summary.release_eligible, false);
  assert(summary.required_work_order_ids.includes('XT-R1-02'));
  assert(summary.required_work_order_ids.includes('XT-R1-03'));
  assert.equal(aggregateEvidence(manifest, {}).phase_statuses.pairing, 'insufficient_evidence');
  assert.equal(aggregateEvidence(manifest, { prepare: { status: 'fail' } }).decision, 'NO-GO');
});

test('CLI preserves attempt history and refuses invented checkpoints without starting applications', (context) => {
  const parent = temporaryDirectory(context);
  const runRoot = path.join(parent, 'run with spaces');
  fs.mkdirSync(runRoot, { mode: 0o700 });
  const script = fileURLToPath(new URL('../scripts/r1_first_real_task.mjs', import.meta.url));
  const first = spawnSync(process.execPath, [script, '--phase', 'create', '--run-root', runRoot], {
    encoding: 'utf8', timeout: 20000,
  });
  assert.equal(first.status, 2, first.stderr);
  const reports = path.join(runRoot, 'reports');
  const firstIndex = readJSON(path.join(reports, 'artifact_index.v1.json'));
  for (const artifact of firstIndex.artifacts) {
    assert.equal(sha256(fs.readFileSync(path.join(reports, artifact.ref))), artifact.sha256);
  }
  const firstSummary = readJSON(path.join(reports, 'first_real_task.v1.json'));
  assert.equal(firstSummary.phase_statuses.create, 'blocked');
  assert.equal(firstSummary.phase_statuses.pairing, 'insufficient_evidence');
  const resumed = spawnSync(process.execPath, [
    script, '--phase', 'resume', '--run-root', runRoot, '--checkpoint-id', 'not-a-runtime-checkpoint',
  ], { encoding: 'utf8', timeout: 20000 });
  assert.equal(resumed.status, 2, resumed.stderr);
  const recovery = readJSON(path.join(reports, 'checkpoint_recovery.v1.json'));
  assert(recovery.blocked_reasons.includes('checkpoint_not_produced_by_runtime'));
  assert.equal(recovery.lineage.run_id, firstSummary.lineage.run_id);
  assert.equal(recovery.lineage.checkpoint_id, null);
  assert.equal(fs.readdirSync(path.join(reports, 'attempts')).length, 2);
  assert.equal(fs.existsSync(path.join(runRoot, 'golden-project')), false);
  for (const artifact of firstIndex.artifacts) {
    assert.equal(sha256(fs.readFileSync(path.join(reports, artifact.ref))), artifact.sha256);
  }
  const ledger = readJSON(path.join(reports, 'cleanup_ledger.v1.json'));
  assert.equal(ledger.runner_owned_application_process_count, 0);
  assert.equal(ledger.user_profiles_touched, false);
});

test('CLI refuses foreign run and report ownership before touching prior evidence', (context) => {
  const root = temporaryDirectory(context);
  const script = fileURLToPath(new URL('../scripts/r1_first_real_task.mjs', import.meta.url));
  const args = [script, '--phase', 'create', '--run-root', root];
  assert.equal(spawnSync(process.execPath, args, { timeout: 20000 }).status, 2);
  const summaryPath = path.join(root, 'reports', 'first_real_task.v1.json');
  const before = sha256(fs.readFileSync(summaryPath));
  const ownerPath = path.join(root, 'reports', 'r1-report-owner.v1.json');
  fs.writeFileSync(ownerPath, JSON.stringify({ run_id: randomUUID() }));
  const foreign = spawnSync(process.execPath, args, { timeout: 20000, encoding: 'utf8' });
  assert.equal(foreign.status, 2);
  assert.match(foreign.stderr, /report_owner_mismatch/);
  assert.equal(sha256(fs.readFileSync(summaryPath)), before);
});
