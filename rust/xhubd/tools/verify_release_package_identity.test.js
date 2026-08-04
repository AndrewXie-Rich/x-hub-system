import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { verifyReleaseIdentity } from './verify_release_package_identity.js';

const commit = '0123456789012345678901234567890123456789';

function fixture(sourceRoot) {
  return {
    schema_version: 'xhub.rust_hub.package_provenance.v2',
    ok: true,
    build_provenance: {
      metadata_complete: true,
      source: {
        git_commit: commit,
        git_dirty: false,
        root: sourceRoot,
      },
      build: {
        timestamp_source: 'SOURCE_DATE_EPOCH',
        timestamp_unix_seconds: 1_700_000_000,
      },
    },
    contents: {
      package_file_count: 1,
      package_files: [{
        relative_path: 'tools/run_rust_hub.command',
        sha256: 'a'.repeat(64),
        bytes: 42,
      }],
    },
  };
}

test('accepts an exact clean commit, source root, epoch, and closed inventory', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-release-identity-'));
  try {
    const result = verifyReleaseIdentity(fixture(root), {
      commit,
      sourceRoot: root,
      sourceDateEpoch: '1700000000',
    });
    assert.equal(result.ok, true);
    assert.deepEqual(result.issues, []);
    assert.equal(result.package_file_count, 1);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('fails closed on cached dirty identity, wrong commit, epoch, root, or inventory', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-release-identity-'));
  const otherRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-release-identity-other-'));
  try {
    const manifest = fixture(otherRoot);
    manifest.build_provenance.source.git_dirty = true;
    manifest.build_provenance.source.git_commit = 'f'.repeat(40);
    manifest.build_provenance.build.timestamp_unix_seconds = 1;
    manifest.contents.package_file_count = 2;
    const result = verifyReleaseIdentity(manifest, {
      commit,
      sourceRoot: root,
      sourceDateEpoch: '1700000000',
    });
    assert.equal(result.ok, false);
    for (const issue of [
      'git_commit_mismatch',
      'git_dirty_not_false',
      'build_timestamp_mismatch',
      'source_root_mismatch',
      'package_file_inventory_count_mismatch',
    ]) {
      assert.ok(result.issues.includes(issue), `missing ${issue}`);
    }
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
    fs.rmSync(otherRoot, { recursive: true, force: true });
  }
});
