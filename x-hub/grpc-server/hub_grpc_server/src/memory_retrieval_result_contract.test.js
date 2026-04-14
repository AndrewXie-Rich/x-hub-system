import assert from 'node:assert/strict';

import { buildXTMemoryRetrievalResultV1 } from './services.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

run('maps remote retrieval rows into xt.memory_retrieval_result.v1 shape', () => {
  const documentsById = new Map([
    ['canonical:project:goal:1', {
      id: 'canonical:project:goal:1',
      source_type: 'canonical',
      title: 'goal',
      text: 'Goal is to keep governed retrieval consistent across XT and Hub.',
      source_payload: { key: 'goal', value: 'keep retrieval consistent' },
    }],
    ['turn:123:1', {
      id: 'turn:123:1',
      source_type: 'turn',
      title: 'assistant',
      text: 'We previously discussed the supervisor review loop.',
      source_payload: { role: 'assistant', content: 'We previously discussed the supervisor review loop.' },
    }],
  ]);

  const out = buildXTMemoryRetrievalResultV1({
    requestId: 'req-remote-1',
    retrieval: {
      blocked: false,
      deny_reason: '',
      pipeline_stage_trace: [
        { stage: 'rerank', in_count: 5, out_count: 5 },
        { stage: 'gate', in_count: 5, out_count: 2, blocked: false, reason: 'allow' },
      ],
      results: [
        { id: 'canonical:project:goal:1', title: 'goal', final_score: 0.91 },
        { id: 'turn:123:1', title: 'assistant', final_score: 0.52 },
      ],
    },
    documentsById,
    auditRef: 'audit-memory-route-1',
  });

  assert.equal(out.schema_version, 'xt.memory_retrieval_result.v1');
  assert.equal(out.request_id, 'req-remote-1');
  assert.equal(out.status, 'truncated');
  assert.equal(out.resolved_scope, 'current_project');
  assert.equal(out.source, 'hub_memory_retrieval_grpc_v1');
  assert.equal(out.audit_ref, 'audit-memory-route-1');
  assert.equal(out.truncated, true);
  assert.equal(out.results.length, 2);
  assert.equal(out.results[0].source_kind, 'canonical_memory');
  assert.equal(out.results[0].summary, 'goal');
  assert.equal(out.results[0].score, 0.91);
  assert.equal(out.results[1].source_kind, 'recent_context');
  assert.equal(out.results[1].score, 0.52);
  assert.ok(out.budget_used_chars > 0);
});

run('blocked retrieval becomes denied result with empty items', () => {
  const out = buildXTMemoryRetrievalResultV1({
    requestId: 'req-remote-2',
    retrieval: {
      blocked: true,
      deny_reason: 'remote_secret_denied',
      results: [],
    },
  });

  assert.equal(out.status, 'denied');
  assert.equal(out.deny_code, 'remote_secret_denied');
  assert.equal(out.reason_code, 'remote_secret_denied');
  assert.equal(out.results.length, 0);
  assert.equal(out.truncated, false);
  assert.equal(out.budget_used_chars, 0);
});

run('preserves governed coding runtime source kinds in v1 result rows', () => {
  const documentsById = new Map([
    ['runtime:guidance_injection:abc123', {
      id: 'runtime:guidance_injection:abc123',
      source_type: 'guidance_injection',
      title: 'Guidance pending',
      text: 'guidance_summary: Pause and reduce verify scope before retry.',
      source_payload: { injection_id: 'guidance-1' },
    }],
    ['runtime:heartbeat_projection:def456', {
      id: 'runtime:heartbeat_projection:def456',
      source_type: 'heartbeat_projection',
      title: 'Heartbeat projection blocked',
      text: 'status_digest: Blocked on smoke tests',
      source_payload: { created_at_ms: 950 },
    }],
  ]);

  const out = buildXTMemoryRetrievalResultV1({
    requestId: 'req-remote-runtime-kinds',
    retrieval: {
      blocked: false,
      deny_reason: '',
      pipeline_stage_trace: [],
      results: [
        { id: 'runtime:guidance_injection:abc123', title: 'Guidance pending', final_score: 0.88 },
        { id: 'runtime:heartbeat_projection:def456', title: 'Heartbeat projection blocked', final_score: 0.61 },
      ],
    },
    documentsById,
    auditRef: 'audit-memory-route-runtime-kinds',
  });

  assert.equal(out.status, 'ok');
  assert.equal(out.results.length, 2);
  assert.equal(out.results[0].source_kind, 'guidance_injection');
  assert.equal(out.results[1].source_kind, 'heartbeat_projection');
});
