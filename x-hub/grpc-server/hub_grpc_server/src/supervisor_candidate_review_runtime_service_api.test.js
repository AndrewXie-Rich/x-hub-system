import assert from 'node:assert/strict';
import fs from 'node:fs';

import { HubDB } from './db.js';
import { HubEventBus } from './event_bus.js';
import { makeServices } from './services.js';
import {
  baseEnv,
  buildCarrierEnvelope,
  cleanupDbArtifacts,
  invokeHubMemoryUnary,
  makeSupervisorClient,
  makeTmp,
  openShadowThread,
  run,
  withEnv,
} from './supervisor_memory_candidate_test_lib.js';

function invokeHubRuntimeUnary(impl, methodName, request) {
  let outErr = null;
  let outRes = null;
  impl.HubRuntime[methodName](
    {
      request,
      metadata: {
        get() {
          return [];
        },
      },
      getPeer() {
        return 'ipv4:127.0.0.1:55001';
      },
    },
    (err, res) => {
      outErr = err || null;
      outRes = res || null;
    }
  );
  return { err: outErr, res: outRes };
}

run('supervisor candidate review runtime queue returns request-level snapshot filtered by project', () => {
  const runtimeBaseDir = makeTmp('runtime');
  const dbPath = makeTmp('db', '.sqlite');
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  cleanupDbArtifacts(dbPath);

  withEnv(baseEnv(runtimeBaseDir), () => {
    const db = new HubDB({ dbPath });
    const impl = makeServices({ db, bus: new HubEventBus() });
    const client = {
      ...makeSupervisorClient(),
      project_id: 'proj-runtime-1',
    };
    const threadId = openShadowThread(impl, client);

    const appended = invokeHubMemoryUnary(impl, 'AppendTurns', {
      request_id: 'shadow-runtime-1',
      client,
      thread_id: threadId,
      messages: [
        {
          role: 'user',
          content: 'shadow_write durable_candidates scopes=project_scope count=1',
        },
        {
          role: 'assistant',
          content: JSON.stringify(buildCarrierEnvelope({
            emitted_at_ms: 1_717_100_100_000,
            summary_line: 'project_scope',
            scopes: ['project_scope'],
            candidates: [
              {
                scope: 'project_scope',
                record_type: 'project_blocker',
                confidence: 0.94,
                why_promoted: 'stable project blocker worth downstream review',
                source_ref: 'assistant_summary',
                audit_ref: 'supervisor_writeback:project_scope:project_blocker:proj-runtime-1:1717100100000',
                session_participation_class: 'scoped_write',
                write_permission_scope: 'project_scope',
                idempotency_key: 'sha256:runtime-project-blocker-1',
                payload_summary: 'project_id=proj-runtime-1;record_type=project_blocker',
              },
            ],
          })),
        },
      ],
      created_at_ms: 1_717_100_100_000,
      allow_private: false,
    });
    assert.equal(appended.err, null);

    const queue = invokeHubRuntimeUnary(impl, 'GetSupervisorCandidateReviewQueue', {
      client,
      project_id: 'proj-runtime-1',
      limit: 10,
    });
    assert.equal(queue.err, null);
    assert.ok(queue.res);
    assert.equal(Array.isArray(queue.res.items), true);
    assert.equal(queue.res.items.length, 1);
    assert.equal(String(queue.res.items[0]?.request_id || ''), 'shadow-runtime-1');
    assert.equal(String(queue.res.items[0]?.project_id || ''), 'proj-runtime-1');
    assert.equal(String(queue.res.items[0]?.review_state || ''), 'pending_review');
    assert.equal(Number(queue.res.items[0]?.candidate_count || 0), 1);
  });

  cleanupDbArtifacts(dbPath);
  try { fs.rmSync(runtimeBaseDir, { recursive: true, force: true }); } catch {}
});
