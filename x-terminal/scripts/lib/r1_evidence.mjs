import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { createHash } from 'node:crypto';
import { spawn, execFileSync } from 'node:child_process';

export function requireCondition(condition, code) {
  if (!condition) throw new Error(code);
}

export function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

export function isInside(parent, candidate) {
  const relative = path.relative(parent, candidate);
  return relative !== '' && relative !== '..' && !relative.startsWith('..' + path.sep) && !path.isAbsolute(relative);
}

export function regularFile(filename) {
  const stat = fs.lstatSync(filename);
  requireCondition(stat.isFile() && stat.nlink === 1, 'unsafe_file_type');
  return stat;
}

export function readJSON(filename) {
  regularFile(filename);
  return JSON.parse(fs.readFileSync(filename, 'utf8'));
}

export function writeNewJSON(filename, payload) {
  fs.writeFileSync(filename, JSON.stringify(payload, null, 2) + '\n', { flag: 'wx', mode: 0o600 });
}

export function replaceJSON(filename, payload) {
  regularFile(filename);
  const temporary = filename + '.next';
  writeNewJSON(temporary, payload);
  fs.renameSync(temporary, filename);
}

export function assertRunRoot(rawRoot, repositoryRoot) {
  requireCondition(typeof rawRoot === 'string' && rawRoot.length > 0, 'run_root_required');
  const stat = fs.lstatSync(rawRoot);
  requireCondition(stat.isDirectory() && stat.uid === process.getuid() && (stat.mode & 0o077) === 0,
    'run_root_must_be_private_directory');
  const root = fs.realpathSync(rawRoot);
  const temporaryRoots = [...new Set([os.tmpdir(), '/tmp'].map((entry) => fs.realpathSync(entry)))];
  requireCondition(temporaryRoots.some((temporaryRoot) => isInside(temporaryRoot, root)), 'run_root_must_be_temporary');
  requireCondition(root !== repositoryRoot && !isInside(repositoryRoot, root), 'run_root_inside_repository');
  for (let ancestor = root; ancestor !== path.dirname(ancestor); ancestor = path.dirname(ancestor)) {
    requireCondition(!fs.existsSync(path.join(ancestor, '.git')), 'run_root_inside_git_project');
  }
  return root;
}

export function safeOutputDirectory(rawDirectory, runRoot, repositoryRoot) {
  const candidate = path.resolve(rawDirectory);
  const missing = [];
  let ancestor = candidate;
  while (!fs.existsSync(ancestor)) {
    missing.unshift(path.basename(ancestor));
    ancestor = path.dirname(ancestor);
  }
  requireCondition(fs.lstatSync(ancestor).isDirectory(), 'unsafe_report_directory');
  const resolved = path.join(fs.realpathSync(ancestor), ...missing);
  const generatedRoot = path.join(repositoryRoot, 'build', 'reports', 'xt-v1-product-readiness');
  requireCondition(isInside(runRoot, resolved) || isInside(generatedRoot, resolved), 'report_root_out_of_scope');
  requireCondition(!isInside(path.join(runRoot, 'golden-project'), resolved)
    && resolved !== path.join(runRoot, 'golden-project'), 'report_root_inside_project');
  fs.mkdirSync(resolved, { recursive: true, mode: 0o700 });
  requireCondition(fs.realpathSync(resolved) === resolved, 'report_root_symlink');
  return resolved;
}

export function gitEnvironment() {
  return {
    PATH: '/usr/bin:/bin:/usr/sbin:/sbin',
    LANG: 'C',
    GIT_CONFIG_NOSYSTEM: '1',
    GIT_CONFIG_GLOBAL: '/dev/null',
    GIT_TERMINAL_PROMPT: '0',
    GIT_OPTIONAL_LOCKS: '0',
  };
}

export function git(root, args) {
  return execFileSync('/usr/bin/git', ['-C', root, ...args], {
    env: gitEnvironment(), encoding: 'utf8', timeout: 15000, maxBuffer: 32 * 1024 * 1024,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
}

export function sourceSnapshot(repositoryRoot) {
  const head = git(repositoryRoot, ['rev-parse', 'HEAD']).trim();
  const index = git(repositoryRoot, ['ls-files', '--stage', '-z']);
  const paths = [...new Set(git(repositoryRoot, [
    'ls-files', '--cached', '--others', '--exclude-standard', '-z',
  ]).split('\0').filter(Boolean))].sort();
  const entries = paths.map((relativePath) => {
    const filename = path.join(repositoryRoot, relativePath);
    requireCondition(isInside(repositoryRoot, filename), 'source_path_escape');
    let stat;
    try {
      stat = fs.lstatSync(filename);
    } catch (error) {
      if (error.code === 'ENOENT') return [relativePath, 'deleted'];
      throw error;
    }
    if (stat.isSymbolicLink()) return [relativePath, 'symlink', sha256(fs.readlinkSync(filename))];
    requireCondition(stat.isFile(), 'source_snapshot_unsupported_entry');
    return [relativePath, stat.mode & 0o777, sha256(fs.readFileSync(filename))];
  });
  const digest = sha256(JSON.stringify([head, sha256(index), entries]));
  const dirty = git(repositoryRoot, ['status', '--porcelain', '--untracked-files=all']).length > 0;
  return {
    canonical_root: '<canonical-root>',
    git_head: head,
    dirty,
    snapshot_sha256: digest,
    dirty_snapshot_sha256: dirty ? digest : '',
  };
}

export function capture(command, args, { cwd, env, timeoutMs = 120000, maxBytes = 1024 * 1024 } = {}) {
  return new Promise((resolve) => {
    const child = spawn(command, args, { cwd, env, detached: true, stdio: ['ignore', 'pipe', 'pipe'] });
    let byteCount = 0;
    let reason = '';
    let killTimer;
    const chunks = [];
    const signalGroup = (signal) => {
      if (!child.pid) return;
      try { process.kill(-child.pid, signal); } catch (error) {
        if (error.code !== 'ESRCH') reason = 'process_cleanup_failed';
      }
    };
    const stop = (code) => {
      if (reason) return;
      reason = code;
      signalGroup('SIGTERM');
      killTimer = setTimeout(() => signalGroup('SIGKILL'), 250);
    };
    const timeout = setTimeout(() => stop('command_timeout'), timeoutMs);
    const cancel = () => stop('command_cancelled');
    process.once('SIGINT', cancel);
    process.once('SIGTERM', cancel);
    const append = (chunk) => {
      const remaining = maxBytes - byteCount;
      if (remaining > 0) chunks.push(chunk.subarray(0, remaining));
      byteCount += chunk.length;
      if (byteCount > maxBytes) stop('output_budget_exceeded');
    };
    child.stdout.on('data', append);
    child.stderr.on('data', append);
    child.on('error', () => { reason = 'command_spawn_failed'; });
    child.on('close', (exitCode, signal) => {
      clearTimeout(timeout);
      clearTimeout(killTimer);
      process.removeListener('SIGINT', cancel);
      process.removeListener('SIGTERM', cancel);
      if (reason) signalGroup('SIGKILL');
      resolve({ exit_code: exitCode, signal, reason_code: reason, output: Buffer.concat(chunks).toString('utf8') });
    });
  });
}

export function evaluateGoldenResult(result, expectedRed) {
  if (result.reason_code) return { status: 'blocked', reason_code: result.reason_code };
  if (/sandbox-exec:.*(permitted|denied)|sandbox_apply:.*(permitted|denied)/i.test(result.output)) {
    return { status: 'blocked', reason_code: 'toolchain_sandbox_permission_required' };
  }
  const matches = [...result.output.matchAll(/^XT_R1_TEST (testNonemptyGreeting|testTaskGreeting) (pass|fail)\r?$/gm)];
  if (matches.length !== 2 || new Set(matches.map((match) => match[1])).size !== 2) {
    const toolchainMissing = /no such module '(Testing|XCTest)'|SDK is not supported by the compiler/.test(result.output);
    return {
      status: toolchainMissing ? 'blocked' : 'fail',
      reason_code: toolchainMissing ? 'swift_test_toolchain_unavailable' : 'expected_test_results_missing',
    };
  }
  const tests = Object.fromEntries(matches.map((match) => [match[1], match[2]]));
  const correct = !result.signal && result.exit_code === (expectedRed ? 1 : 0)
    && tests.testNonemptyGreeting === 'pass' && tests.testTaskGreeting === (expectedRed ? 'fail' : 'pass');
  return {
    status: correct ? 'pass' : 'fail',
    reason_code: correct ? '' : 'unexpected_golden_test_outcome',
    test_results: tests,
    exit_code: result.exit_code,
  };
}
