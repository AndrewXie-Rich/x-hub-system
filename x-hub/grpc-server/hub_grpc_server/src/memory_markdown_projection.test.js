import assert from 'node:assert/strict';

import { buildLongtermMarkdownExport } from './memory_markdown_projection.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

const BASE_SCOPE = {
  device_id: 'dev1',
  user_id: 'user1',
  app_id: 'app1',
  project_id: 'proj1',
  thread_id: 'thread1',
};

const BASE_ROWS = [
  {
    item_id: 'c1',
    key: 'workflow.next_step',
    value: 'Robot arrives then asks user for payment authorization.',
    updated_at_ms: 1000,
    ...BASE_SCOPE,
  },
  {
    item_id: 'c2',
    key: 'water.price',
    value: '3 USD',
    updated_at_ms: 1200,
    ...BASE_SCOPE,
  },
];

run('W4-06/markdown export is stable and replayable for same version', () => {
  const one = buildLongtermMarkdownExport({
    rows: BASE_ROWS,
    scope_filter: 'project',
    scope_ref: BASE_SCOPE,
    remote_mode: false,
  });
  const two = buildLongtermMarkdownExport({
    rows: BASE_ROWS,
    scope_filter: 'project',
    scope_ref: BASE_SCOPE,
    remote_mode: false,
  });

  assert.equal(one.doc_id, two.doc_id);
  assert.equal(one.version, two.version);
  assert.equal(one.markdown, two.markdown);
  assert.deepEqual(one.provenance_refs, two.provenance_refs);
  assert.equal(one.included_items, 2);
  assert.match(one.markdown, /source_of_truth: db\.canonical_memory/);
});

run('W4-06/remote mode denies secret shard rows fail-closed', () => {
  const rows = [
    ...BASE_ROWS,
    {
      item_id: 'c3',
      key: 'payment.api_key',
      value: 'sk-live-abcdef1234567890',
      updated_at_ms: 1300,
      ...BASE_SCOPE,
    },
  ];
  const out = buildLongtermMarkdownExport({
    rows,
    scope_filter: 'project',
    scope_ref: BASE_SCOPE,
    remote_mode: true,
    allowed_sensitivity: ['public', 'internal', 'secret'],
  });

  assert.equal(out.truncated, false);
  assert.equal(out.included_items >= 1, true);
  assert.equal(out.included_items < 3, true);
  assert.equal(out.applied_sensitivity.includes('secret'), false);
  assert.equal(out.markdown.includes('payment.api_key'), false);
});

run('W4-06/markdown export applies size clamp and truncates deterministically', () => {
  const rows = [];
  for (let i = 0; i < 40; i += 1) {
    rows.push({
      item_id: `c${i + 1}`,
      key: `k${i + 1}`,
      value: `line ${i + 1} `.repeat(8),
      updated_at_ms: 2000 - i,
      ...BASE_SCOPE,
    });
  }

  const out = buildLongtermMarkdownExport({
    rows,
    scope_filter: 'project',
    scope_ref: BASE_SCOPE,
    remote_mode: false,
    max_markdown_chars: 1800,
  });
  assert.equal(out.truncated, true);
  assert.ok(out.markdown.length <= 1800);
  assert.ok(out.included_items < 40);
  assert.ok(out.included_items >= 0);
});

run('W4-06/markdown export ignores malformed rows fail-closed', () => {
  const out = buildLongtermMarkdownExport({
    rows: [
      null,
      'bad',
      { item_id: '', key: 'x', value: 'y', ...BASE_SCOPE },
      { item_id: 'c1', key: 'ok', value: 'value', updated_at_ms: 1, ...BASE_SCOPE },
    ],
    scope_filter: 'thread',
    scope_ref: BASE_SCOPE,
    remote_mode: false,
  });
  assert.equal(out.included_items, 1);
  assert.equal(out.provenance_refs.length, 1);
  assert.ok(out.markdown.includes('ok'));
});
