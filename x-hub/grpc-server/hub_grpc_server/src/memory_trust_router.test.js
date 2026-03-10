import assert from 'node:assert/strict';

import {
  TRUST_SHARD_ORDER,
  buildTrustShardHitStats,
  normalizeSensitivity,
  normalizeTrust,
  routeMemoryByTrustShards,
} from './memory_trust_router.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

run('normalize helpers are stable', () => {
  assert.equal(normalizeSensitivity('SECRET'), 'secret');
  assert.equal(normalizeSensitivity('x'), 'public');
  assert.equal(normalizeTrust('untrusted'), 'untrusted');
  assert.equal(normalizeTrust(''), 'trusted');
  assert.deepEqual(TRUST_SHARD_ORDER, ['public', 'internal', 'secret']);
});

run('remote mode enforces secret shard deny fail-closed', () => {
  const docs = [
    { id: 'p1', sensitivity: 'public', trust_level: 'trusted' },
    { id: 'i1', sensitivity: 'internal', trust_level: 'trusted' },
    { id: 's1', sensitivity: 'secret', trust_level: 'trusted' },
  ];

  const out = routeMemoryByTrustShards({
    documents: docs,
    remote_mode: true,
    allow_untrusted: true,
    allowed_sensitivity: ['public', 'internal', 'secret'],
  });

  assert.equal(out.policy.forced_secret_remote_deny, true);
  assert.deepEqual(out.policy.allowed_sensitivity, ['public', 'internal']);
  assert.deepEqual(out.documents.map((d) => d.id).sort(), ['i1', 'p1']);
  assert.equal(out.stats.dropped_secret_remote, 1);
  assert.equal(out.stats.routed_by_shard.secret, 0);
});

run('untrusted docs are filtered unless allow_untrusted=true', () => {
  const docs = [
    { id: 'a', sensitivity: 'public', trust_level: 'trusted' },
    { id: 'b', sensitivity: 'public', trust_level: 'untrusted' },
  ];

  const strict = routeMemoryByTrustShards({
    documents: docs,
    remote_mode: false,
    allow_untrusted: false,
  });
  assert.deepEqual(strict.documents.map((d) => d.id), ['a']);
  assert.equal(strict.stats.dropped_untrusted, 1);

  const loose = routeMemoryByTrustShards({
    documents: docs,
    remote_mode: false,
    allow_untrusted: true,
  });
  assert.deepEqual(loose.documents.map((d) => d.id).sort(), ['a', 'b']);
});

run('hit stats are computed by shard with per-shard hit-rate', () => {
  const route = routeMemoryByTrustShards({
    documents: [
      { id: 'p1', sensitivity: 'public', trust_level: 'trusted' },
      { id: 'p2', sensitivity: 'public', trust_level: 'trusted' },
      { id: 'i1', sensitivity: 'internal', trust_level: 'trusted' },
      { id: 's1', sensitivity: 'secret', trust_level: 'trusted' },
    ],
    remote_mode: true,
    allow_untrusted: true,
  });

  const stats = buildTrustShardHitStats({
    routeResult: route,
    retrievalResults: [
      { id: 'p1', sensitivity: 'public' },
      { id: 'i1', sensitivity: 'internal' },
      { id: 'i2', sensitivity: 'internal' },
    ],
  });

  assert.equal(stats.hit_total, 3);
  assert.deepEqual(stats.hit_by_shard, { public: 1, internal: 2, secret: 0 });
  assert.equal(stats.hit_rate_by_shard.public, 0.5);
  assert.equal(stats.hit_rate_by_shard.internal, 2);
  assert.equal(stats.hit_rate_by_shard.secret, 0);
});
