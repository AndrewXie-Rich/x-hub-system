import assert from 'node:assert/strict';

import {
  MEMORY_METRICS_SCHEMA_VERSION,
  attachMemoryMetrics,
  buildMemoryMetricsPayload,
} from './memory_metrics_schema.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

run('metrics schema provides stable default envelope', () => {
  const out = buildMemoryMetricsPayload({
    event_kind: 'memory.route.applied',
    op: 'memory_route',
    channel: 'remote',
    remote_mode: true,
  });
  assert.equal(out.schema_version, MEMORY_METRICS_SCHEMA_VERSION);
  assert.equal(out.event_kind, 'memory.route.applied');
  assert.equal(out.job_type, 'memory_route');
  assert.equal(out.op, 'memory_route');
  assert.equal(out.channel, 'remote');
  assert.equal(out.remote_mode, true);
  assert.deepEqual(Object.keys(out), [
    'schema_version',
    'event_kind',
    'job_type',
    'op',
    'channel',
    'remote_mode',
    'scope',
    'latency',
    'quality',
    'cost',
    'freshness',
    'security',
  ]);
  assert.equal(out.latency.duration_ms, null);
  assert.equal(out.quality.result_count, null);
  assert.equal(out.cost.total_tokens, null);
  assert.equal(out.scope.kind, '');
  assert.equal(out.security.blocked, false);
  assert.equal(out.security.deny_code, '');
  assert.equal(out.security.deny_reason, '');
});

run('metrics schema clamps out-of-range values and normalizes deny code', () => {
  const out = buildMemoryMetricsPayload({
    event_kind: ' memory.route.applied ',
    op: 'memory_route',
    channel: 'REMOTE',
    remote_mode: 1,
    scope: {
      kind: 'thread',
      device_id: ' dev-1 ',
      user_id: 'user-1',
      app_id: 'app-1',
      project_id: 'proj-1',
      thread_id: 'thread-1',
    },
    latency: {
      duration_ms: -11,
      queue_wait_ms: '11.9',
      first_token_ms: 'invalid',
      wall_time_ms: 99999999999999999,
    },
    quality: {
      recall_at_k: 1.9,
      precision_at_k: -0.2,
      ndcg_at_k: 0.3456789123,
      result_count: -1,
      total_items: 8.8,
      included_items: 5.2,
    },
    cost: {
      prompt_tokens: 12.4,
      completion_tokens: -3,
      total_tokens: 19.8,
      cost_usd_estimate: 999999999999,
    },
    freshness: {
      snapshot_version: 'v1\nbad',
      exported_at_ms: '2000',
    },
    security: {
      blocked: true,
      deny_code: 'query_pattern:/reveal.*(secret|token)/',
      downgraded: 1,
    },
  });

  assert.equal(out.channel, 'remote');
  assert.equal(out.job_type, 'memory_route');
  assert.equal(out.scope.kind, 'thread');
  assert.equal(out.scope.device_id, 'dev-1');
  assert.equal(out.scope.project_id, 'proj-1');
  assert.equal(out.latency.duration_ms, 0);
  assert.equal(out.latency.queue_wait_ms, 11);
  assert.equal(out.latency.first_token_ms, null);
  assert.equal(out.latency.wall_time_ms, 9007199254740991);
  assert.equal(out.quality.recall_at_k, 1);
  assert.equal(out.quality.precision_at_k, 0);
  assert.equal(out.quality.ndcg_at_k, 0.345679);
  assert.equal(out.quality.result_count, 0);
  assert.equal(out.quality.total_items, 8);
  assert.equal(out.quality.included_items, 5);
  assert.equal(out.cost.prompt_tokens, 12);
  assert.equal(out.cost.completion_tokens, 0);
  assert.equal(out.cost.total_tokens, 19);
  assert.equal(out.cost.cost_usd_estimate, 1000000000);
  assert.equal(out.freshness.snapshot_version, '');
  assert.equal(out.freshness.exported_at_ms, 2000);
  assert.equal(out.security.blocked, true);
  assert.equal(out.security.downgraded, true);
  assert.equal(out.security.deny_code, 'query_pattern');
  assert.equal(out.security.deny_reason, 'query_pattern:/reveal.*(secret|token)/');
});

run('metrics schema fail-closed for invalid codes and blocked fallback', () => {
  const out = buildMemoryMetricsPayload({
    event_kind: 'memory.route.applied',
    op: 'memory_route',
    security: {
      blocked: true,
      deny_code: 'contains spaces and \n breaks',
    },
  });
  assert.equal(out.security.blocked, true);
  assert.equal(out.security.deny_code, 'unknown');
  assert.equal(out.security.deny_reason, 'contains spaces and breaks');
});

run('attachMemoryMetrics keeps existing fields and backfills queue_wait_ms', () => {
  const out = attachMemoryMetrics(
    {
      created_at_ms: 100,
      queue_depth: 3,
      prompt: 'sensitive text should not be copied into metrics',
    },
    {
      event_kind: 'ai.generate.failed',
      op: 'generate',
      channel: 'remote',
      remote_mode: true,
      scope: { kind: 'project', project_id: 'proj1' },
      latency: { queue_wait_ms: 44 },
      security: { blocked: true, deny_code: 'bridge_disabled' },
    }
  );

  assert.equal(out.created_at_ms, 100);
  assert.equal(out.queue_depth, 3);
  assert.equal(out.queue_wait_ms, 44);
  assert.equal(out.metrics.schema_version, MEMORY_METRICS_SCHEMA_VERSION);
  assert.equal(out.metrics.event_kind, 'ai.generate.failed');
  assert.equal(out.metrics.job_type, 'generate');
  assert.equal(out.metrics.scope.kind, 'project');
  assert.equal(out.metrics.scope.project_id, 'proj1');
  assert.equal(out.metrics.security.deny_code, 'bridge_disabled');
  assert.equal(out.metrics.security.deny_reason, 'bridge_disabled');
  assert.equal(out.metrics.quality.result_count, null);
  assert.equal(out.metrics.quality.findings_count, null);
  assert.equal(typeof out.metrics.prompt, 'undefined');
});
