import assert from 'node:assert/strict';

import { buildMemoryScoreExplainPayload } from './memory_score_explain.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

run('includes text/recency/risk components and respects limit', () => {
  const payload = buildMemoryScoreExplainPayload({
    limit: 2,
    retrieval: {
      blocked: false,
      deny_reason: '',
      results: [
        {
          rank: 1,
          id: 'a',
          title: 'A',
          sensitivity: 'public',
          trust_level: 'trusted',
          lexical_score: 0.88,
          recency_score: 0.5,
          relevance_score: 0.823,
          risk_penalty: 0.1,
          final_score: 0.723,
          risk_level: 'medium',
          risk_factors: ['query:medium_risk', 'trust:untrusted', 'x', 'y', 'z'],
        },
        {
          rank: 2,
          id: 'b',
          title: 'B',
          lexical_score: 0.4,
          recency_score: 0.2,
          relevance_score: 0.37,
          risk_penalty: 0,
          final_score: 0.37,
          risk_level: 'low',
          risk_factors: [],
        },
        {
          rank: 3,
          id: 'c',
          title: 'C',
          lexical_score: 0.2,
          recency_score: 0.1,
          relevance_score: 0.185,
          risk_penalty: 0,
          final_score: 0.185,
          risk_level: 'low',
        },
      ],
    },
  });

  assert.equal(payload.schema_version, 'xhub.memory.score_explain.v1');
  assert.equal(payload.items.length, 2);
  assert.equal(payload.items[0].components.vector_score, 0);
  assert.equal(payload.items[0].components.mmr_score, 0);
  assert.equal(payload.items[0].components.text_score, 0.88);
  assert.equal(payload.items[0].components.recency_score, 0.5);
  assert.equal(payload.items[0].components.risk_penalty, 0.1);
  assert.equal(payload.items[0].risk_factors.length, 4);
});

run('blocked retrieval keeps deny reason and no items', () => {
  const payload = buildMemoryScoreExplainPayload({
    retrieval: {
      blocked: true,
      deny_reason: 'remote_secret_denied',
      results: [],
    },
  });
  assert.equal(payload.blocked, true);
  assert.equal(payload.deny_reason, 'remote_secret_denied');
  assert.equal(payload.result_total, 0);
  assert.equal(payload.items.length, 0);
});

run('trace output is controlled by include_trace', () => {
  const retrieval = {
    blocked: false,
    deny_reason: '',
    results: [],
    pipeline_stage_trace: [
      { stage: 'scope_filter', in_count: 10, out_count: 9 },
      { stage: 'gate', in_count: 2, out_count: 0, blocked: true, reason: 'x' },
    ],
  };
  const off = buildMemoryScoreExplainPayload({ retrieval, include_trace: false });
  const on = buildMemoryScoreExplainPayload({ retrieval, include_trace: true });
  assert.equal(off.stage_trace.length, 0);
  assert.equal(on.stage_trace.length, 2);
  assert.equal(on.stage_trace[1].stage, 'gate');
  assert.equal(on.stage_trace[1].blocked, true);
});
