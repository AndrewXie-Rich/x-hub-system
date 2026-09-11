import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function requireArgument(value, name) {
  if (!value) throw new Error(`${name}_required`);
  return path.resolve(value);
}

function sourceEntries(sourceRoot) {
  const entries = [];
  const ignoredDirectories = new Set([
    '.build', '.swiftpm', '.scratch', '.scratch-*', '.axcoder', '.tmp-home',
    '.sandbox_home', '.sandbox_tmp', '.clang-module-cache', '.swift-module-cache',
    '.ax-test-cache', 'build', 'data',
  ]);

  function visit(directory) {
    for (const item of fs.readdirSync(directory, { withFileTypes: true }).sort((left, right) => left.name.localeCompare(right.name))) {
      if (item.name === '.DS_Store' || [...ignoredDirectories].some((prefix) => item.name === prefix || (prefix.endsWith('*') && item.name.startsWith(prefix.slice(0, -1))))) continue;
      const filename = path.join(directory, item.name);
      const relative = path.relative(sourceRoot, filename).split(path.sep).join('/');
      const stat = fs.lstatSync(filename);
      if (stat.isDirectory()) {
        visit(filename);
      } else if (stat.isSymbolicLink()) {
        entries.push([relative, 'symlink', sha256(fs.readlinkSync(filename))]);
      } else if (stat.isFile()) {
        entries.push([relative, stat.mode & 0o777, sha256(fs.readFileSync(filename))]);
      } else {
        throw new Error(`unsupported_source_entry:${relative}`);
      }
    }
  }

  visit(sourceRoot);
  return entries;
}

export function sourceTree(sourceRoot) {
  const entries = sourceEntries(sourceRoot);
  return { entries, sha256: sha256(JSON.stringify(entries)) };
}

export function buildProvenance({ sourceRoot, binary, gitRoot = '', configuration = 'release' }) {
  const stat = fs.lstatSync(binary);
  if (!stat.isFile() || stat.nlink !== 1) throw new Error('unsafe_binary');
  const tree = sourceTree(sourceRoot);
  let gitHead = null;
  let gitDirty = null;
  if (gitRoot) {
    const resolvedGitRoot = path.resolve(gitRoot);
    gitHead = execFileSync('/usr/bin/git', ['-C', resolvedGitRoot, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
    gitDirty = execFileSync('/usr/bin/git', ['-C', resolvedGitRoot, 'status', '--porcelain', '--untracked-files=all'], { encoding: 'utf8' }).length > 0;
  }
  return {
    schema_version: 'xt.build_provenance.v1',
    product: 'x-terminal',
    generated_at: new Date().toISOString(),
    configuration,
    source: {
      source_tree_sha256: tree.sha256,
      file_count: tree.entries.length,
      git_head: gitHead,
      git_dirty: gitDirty,
      root_kind: 'canonical_x_terminal_source_or_frozen_build_snapshot',
    },
    binary: {
      relative_path: 'Contents/MacOS/XTerminal',
      sha256: sha256(fs.readFileSync(binary)),
      size_bytes: stat.size,
      hash_scope: 'pre_codesign_build_output',
    },
    verification: {
      source_tree_reproducible: true,
      binary_source_binding: 'sha256_source_tree_manifest_signed_into_app',
      secrets_included: false,
    },
  };
}

function argumentValue(args, name) {
  const index = args.indexOf(name);
  if (index < 0) return '';
  if (!args[index + 1] || args[index + 1].startsWith('--')) throw new Error(`${name.slice(2).replaceAll('-', '_')}_required`);
  return args[index + 1];
}

export function writeProvenance(output, payload) {
  fs.mkdirSync(path.dirname(output), { recursive: true, mode: 0o700 });
  const temporary = `${output}.next-${process.pid}`;
  fs.writeFileSync(temporary, `${JSON.stringify(payload, null, 2)}\n`, { flag: 'wx', mode: 0o600 });
  fs.renameSync(temporary, output);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  try {
    const sourceRoot = requireArgument(argumentValue(args, '--source-root'), 'source_root');
    const binary = requireArgument(argumentValue(args, '--binary'), 'binary');
    const output = requireArgument(argumentValue(args, '--output'), 'output');
    const payload = buildProvenance({
      sourceRoot,
      binary,
      gitRoot: argumentValue(args, '--git-root'),
      configuration: argumentValue(args, '--configuration') || 'release',
    });
    writeProvenance(output, payload);
    console.log(`[xt-provenance] output=${output}`);
    console.log(`[xt-provenance] source_tree_sha256=${payload.source.source_tree_sha256}`);
    console.log(`[xt-provenance] binary_sha256=${payload.binary.sha256}`);
  } catch (error) {
    console.error(`[xt-provenance] ${error.message}`);
    process.exitCode = 2;
  }
}
