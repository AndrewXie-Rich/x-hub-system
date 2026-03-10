import assert from 'node:assert/strict';

import {
  buildLongtermMarkdownPatchCandidate,
  computeLongtermMarkdownVersion,
  normalizeMarkdownPatchMode,
} from './memory_markdown_edit.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

const SESSION = {
  edit_session_id: 'medit_1',
  doc_id: 'longterm:dev1:user1:app1:proj1:project:~',
  base_version: 'lmv1_base123',
  working_version: 'lmv1_base123',
  scope_filter: 'project',
  scope_ref: {
    device_id: 'dev1',
    user_id: 'user1',
    app_id: 'app1',
    project_id: 'proj1',
    thread_id: '',
  },
  route_policy: {
    remote_mode: false,
    allow_untrusted: false,
    allowed_sensitivity: ['public', 'internal'],
  },
  working_markdown: '# Doc\n\nold',
};

run('W4-07/normalize patch mode fail-closed', () => {
  assert.equal(normalizeMarkdownPatchMode('replace'), 'replace');
  assert.equal(normalizeMarkdownPatchMode('REPLACE'), 'replace');
  assert.equal(normalizeMarkdownPatchMode('diff'), '');
});

run('W4-07/build patch candidate computes new version and stats', () => {
  const candidate = buildLongtermMarkdownPatchCandidate({
    session: SESSION,
    patch_mode: 'replace',
    patch_markdown: '# Doc\n\nnew text',
    patch_note: 'fix typo',
    max_patch_chars: 2000,
    max_patch_lines: 200,
  });
  assert.equal(candidate.patch_mode, 'replace');
  assert.equal(candidate.patch_size_chars, '# Doc\n\nnew text'.length);
  assert.equal(candidate.patch_line_count, 3);
  assert.equal(candidate.from_version, SESSION.working_version);
  assert.ok(String(candidate.to_version || '').startsWith('lmv1_'));
  assert.equal(candidate.patch_sha256.length, 64);
});

run('W4-07/version is deterministic for same content', () => {
  const one = computeLongtermMarkdownVersion({
    doc_id: SESSION.doc_id,
    scope_filter: SESSION.scope_filter,
    scope_ref: SESSION.scope_ref,
    route_policy: SESSION.route_policy,
    markdown: '# Doc\nsame',
  });
  const two = computeLongtermMarkdownVersion({
    doc_id: SESSION.doc_id,
    scope_filter: SESSION.scope_filter,
    scope_ref: SESSION.scope_ref,
    route_policy: SESSION.route_policy,
    markdown: '# Doc\nsame',
  });
  assert.equal(one, two);
});

run('W4-07/patch limit exceed fails closed', () => {
  assert.throws(
    () => buildLongtermMarkdownPatchCandidate({
      session: SESSION,
      patch_mode: 'replace',
      patch_markdown: 'x'.repeat(5000),
      max_patch_chars: 10,
      max_patch_lines: 100,
    }),
    /patch_limit_exceeded:chars/
  );
});

