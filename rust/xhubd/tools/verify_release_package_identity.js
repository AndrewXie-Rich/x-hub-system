#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

function parseArgs(argv) {
  const out = {
    manifest: '',
    expectedCommit: '',
    expectedSourceRoot: '',
    expectedSourceDateEpoch: '',
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const value = argv[index + 1];
    if (!value) throw new Error(`${arg} requires a value`);
    switch (arg) {
      case '--manifest':
        out.manifest = value;
        break;
      case '--expected-commit':
        out.expectedCommit = value;
        break;
      case '--expected-source-root':
        out.expectedSourceRoot = value;
        break;
      case '--expected-source-date-epoch':
        out.expectedSourceDateEpoch = value;
        break;
      default:
        throw new Error(`unknown argument: ${arg}`);
    }
    index += 1;
  }
  for (const [key, value] of Object.entries(out)) {
    if (!String(value).trim()) throw new Error(`missing required ${key}`);
  }
  if (!/^[0-9a-f]{40,64}$/i.test(out.expectedCommit)) {
    throw new Error('expected commit must be a full hexadecimal object id');
  }
  if (!/^\d+$/.test(out.expectedSourceDateEpoch)) {
    throw new Error('expected SOURCE_DATE_EPOCH must be a non-negative integer');
  }
  return out;
}

function readManifest(manifestPath) {
  const metadata = fs.lstatSync(manifestPath);
  if (!metadata.isFile() || metadata.isSymbolicLink()) {
    throw new Error('release provenance manifest must be a regular non-symlink file');
  }
  return JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
}

export function verifyReleaseIdentity(manifest, expected) {
  const issues = [];
  const build = manifest?.build_provenance;
  if (manifest?.schema_version !== 'xhub.rust_hub.package_provenance.v2') {
    issues.push('package_schema_mismatch');
  }
  if (manifest?.ok !== true) issues.push('package_manifest_not_ok');
  if (build?.metadata_complete !== true) issues.push('build_metadata_incomplete');
  if (build?.source?.git_commit !== expected.commit) issues.push('git_commit_mismatch');
  if (build?.source?.git_dirty !== false) issues.push('git_dirty_not_false');
  if (build?.build?.timestamp_source !== 'SOURCE_DATE_EPOCH') {
    issues.push('build_timestamp_source_mismatch');
  }
  if (String(build?.build?.timestamp_unix_seconds ?? '') !== expected.sourceDateEpoch) {
    issues.push('build_timestamp_mismatch');
  }

  let embeddedRoot = '';
  let expectedRoot = '';
  try {
    embeddedRoot = fs.realpathSync(String(build?.source?.root || ''));
  } catch {
    issues.push('embedded_source_root_unavailable');
  }
  try {
    expectedRoot = fs.realpathSync(expected.sourceRoot);
  } catch {
    issues.push('expected_source_root_unavailable');
  }
  if (embeddedRoot && expectedRoot && path.resolve(embeddedRoot) !== path.resolve(expectedRoot)) {
    issues.push('source_root_mismatch');
  }

  const files = build && manifest?.contents?.package_files;
  if (!Array.isArray(files) || files.length === 0) {
    issues.push('package_file_inventory_missing');
  }
  if (Number(manifest?.contents?.package_file_count ?? -1) !== files?.length) {
    issues.push('package_file_inventory_count_mismatch');
  }

  return {
    ok: issues.length === 0,
    issues,
    git_commit: build?.source?.git_commit ?? null,
    git_dirty: build?.source?.git_dirty ?? null,
    source_root: build?.source?.root ?? null,
    source_date_epoch: build?.build?.timestamp_unix_seconds ?? null,
    package_file_count: Array.isArray(files) ? files.length : 0,
  };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const manifest = readManifest(args.manifest);
  const result = verifyReleaseIdentity(manifest, {
    commit: args.expectedCommit,
    sourceRoot: args.expectedSourceRoot,
    sourceDateEpoch: args.expectedSourceDateEpoch,
  });
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  if (!result.ok) process.exitCode = 1;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`release package identity verification failed: ${error.message}\n`);
    process.exitCode = 1;
  }
}
