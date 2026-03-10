import assert from 'node:assert/strict';

import {
  analyzeLongtermMarkdownFindings,
  normalizeReviewDecision,
  normalizeSecretHandling,
  sanitizeLongtermMarkdown,
} from './memory_markdown_review.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

run('W4-08/analyze detects credential and secret findings', () => {
  const text = 'token sk-abcDEF123456789 and <private>hidden</private>';
  const out = analyzeLongtermMarkdownFindings(text);
  assert.equal(out.has_credential, true);
  assert.equal(out.has_secret, true);
  assert.ok(Array.isArray(out.findings));
  assert.ok(out.findings.length >= 2);
});

run('W4-08/sanitize redacts sensitive content', () => {
  const text = 'Bearer abcdefghijklmnopqrstuvwxyz and [private] + sk-abcDEF123456789';
  const out = sanitizeLongtermMarkdown(text);
  assert.ok(out.redacted_count >= 2);
  assert.equal(String(out.markdown || '').includes('sk-abcDEF123456789'), false);
  assert.equal(String(out.markdown || '').includes('[private]'), false);
});

run('W4-08/normalizers fail closed', () => {
  assert.equal(normalizeReviewDecision('approve'), 'approve');
  assert.equal(normalizeReviewDecision('bad'), '');
  assert.equal(normalizeSecretHandling('sanitize'), 'sanitize');
  assert.equal(normalizeSecretHandling('unknown'), '');
});

