import assert from 'node:assert/strict';

import { stripPrivateTagsFailClosed } from './private_tags.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

run('keeps plain text untouched', () => {
  const out = stripPrivateTagsFailClosed('hello world');
  assert.equal(out.text, 'hello world');
  assert.equal(out.had_private, false);
  assert.equal(out.malformed, false);
  assert.equal(out.redacted_count, 0);
});

run('redacts closed private block', () => {
  const out = stripPrivateTagsFailClosed('a <private>secret</private> b');
  assert.equal(out.text, 'a [PRIVATE] b');
  assert.equal(out.had_private, true);
  assert.equal(out.malformed, false);
  assert.equal(out.redacted_count, 1);
});

run('redacts unclosed private block (fail-closed)', () => {
  const out = stripPrivateTagsFailClosed('token=<private>abc123');
  assert.equal(out.text, 'token=[PRIVATE]');
  assert.equal(out.had_private, true);
  assert.equal(out.malformed, true);
  assert.equal(out.redacted_count, 1);
});

run('treats nested private tags as private with malformed=true', () => {
  const out = stripPrivateTagsFailClosed('x <private>a <private>b</private> c</private> y');
  assert.equal(out.text, 'x [PRIVATE] y');
  assert.equal(out.had_private, true);
  assert.equal(out.malformed, true);
  assert.equal(out.redacted_count, 1);
});

run('stray close tag is redacted (fail-closed)', () => {
  const out = stripPrivateTagsFailClosed('prefix </private> suffix');
  assert.equal(out.text, 'prefix [PRIVATE] suffix');
  assert.equal(out.had_private, true);
  assert.equal(out.malformed, true);
  assert.equal(out.redacted_count, 1);
});

run('accepts case-insensitive tags', () => {
  const out = stripPrivateTagsFailClosed('a <PRIVATE>sec</PrIvAtE> b');
  assert.equal(out.text, 'a [PRIVATE] b');
  assert.equal(out.had_private, true);
  assert.equal(out.malformed, false);
  assert.equal(out.redacted_count, 1);
});

run('does not treat <privately> as private tag', () => {
  const out = stripPrivateTagsFailClosed('a <privately>note</privately> b');
  assert.equal(out.text, 'a <privately>note</privately> b');
  assert.equal(out.had_private, false);
  assert.equal(out.malformed, false);
  assert.equal(out.redacted_count, 0);
});
