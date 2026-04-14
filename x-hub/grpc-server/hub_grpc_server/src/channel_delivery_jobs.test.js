import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { HubDB } from './db.js';
import {
  CHANNEL_DELIVERY_JOB_SCHEMA,
  claimChannelDeliveryJobs,
  enqueueChannelDeliveryJob,
  getChannelDeliveryJobById,
  listChannelDeliveryJobRuntimeRows,
  recordChannelDeliveryJobAttempt,
  retryChannelDeliveryJobManual,
} from './channel_delivery_jobs.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

function makeTmp(label, suffix = '') {
  const token = `${label}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  return path.join(os.tmpdir(), `channel_delivery_jobs_${token}${suffix}`);
}

function cleanupDbArtifacts(dbPath) {
  try { fs.rmSync(dbPath, { force: true }); } catch {}
  try { fs.rmSync(`${dbPath}-wal`, { force: true }); } catch {}
  try { fs.rmSync(`${dbPath}-shm`, { force: true }); } catch {}
}

run('XT-W3-24-M/delivery jobs enqueue with schema freeze and dedupe by dedupe_key', () => {
  const dbPath = makeTmp('db', '.db');
  const db = new HubDB({ dbPath });
  try {
    const first = enqueueChannelDeliveryJob(db, {
      request_id: 'delivery-job-enqueue-1',
      audit: {
        device_id: 'hub-supervisor',
        app_id: 'hub_runtime_operator_channels',
      },
      job: {
        provider: 'tg',
        account_id: 'telegram_ops_bot',
        conversation_id: '-1001234567890',
        thread_key: 'topic:42',
        delivery_class: 'alert',
        payload_ref: 'local://channel-payloads/alert-001.json',
        dedupe_key: 'sha256:alert-001',
        audit_ref: 'audit-delivery-001',
      },
    });
    assert.equal(!!first.ok, true);
    assert.equal(!!first.created, true);
    assert.equal(String(first.job?.schema_version || ''), CHANNEL_DELIVERY_JOB_SCHEMA);
    assert.equal(String(first.job?.provider || ''), 'telegram');

    const duplicate = enqueueChannelDeliveryJob(db, {
      request_id: 'delivery-job-enqueue-2',
      audit: {
        device_id: 'hub-supervisor',
        app_id: 'hub_runtime_operator_channels',
      },
      job: {
        provider: 'telegram',
        account_id: 'telegram_ops_bot',
        conversation_id: '-1001234567890',
        delivery_class: 'alert',
        payload_ref: 'local://channel-payloads/alert-001-b.json',
        dedupe_key: 'sha256:alert-001',
        audit_ref: 'audit-delivery-001-dup',
      },
    });
    assert.equal(!!duplicate.ok, true);
    assert.equal(!!duplicate.created, false);
    assert.equal(String(duplicate.job?.job_id || ''), String(first.job?.job_id || ''));
  } finally {
    db.close();
    cleanupDbArtifacts(dbPath);
  }
});

run('XT-W3-24-M/provider backoff gates all due jobs on the same provider account', () => {
  const dbPath = makeTmp('db', '.db');
  const db = new HubDB({ dbPath });
  try {
    const baseNow = Date.now();
    const first = enqueueChannelDeliveryJob(db, {
      job: {
        provider: 'slack',
        account_id: 'ops-slack',
        conversation_id: 'C123',
        delivery_class: 'heartbeat',
        payload_ref: 'local://channel-payloads/heartbeat-1.json',
        dedupe_key: 'sha256:heartbeat-1',
        audit_ref: 'audit-heartbeat-1',
      },
    });
    const second = enqueueChannelDeliveryJob(db, {
      job: {
        provider: 'slack',
        account_id: 'ops-slack',
        conversation_id: 'C123',
        delivery_class: 'cron_summary',
        payload_ref: 'local://channel-payloads/cron-1.json',
        dedupe_key: 'sha256:cron-1',
        audit_ref: 'audit-cron-1',
      },
    });
    assert.equal(!!first.ok, true);
    assert.equal(!!second.ok, true);

    const claimStart = Math.max(
      Number(first.job?.created_at_ms || 0),
      Number(second.job?.created_at_ms || 0)
    ) + 10;
    const claimedFirst = claimChannelDeliveryJobs(db, {
      provider: 'slack',
      account_id: 'ops-slack',
      now_ms: claimStart,
      limit: 1,
    });
    assert.equal(claimedFirst.length, 1);
    assert.equal(String(claimedFirst[0]?.job_id || ''), String(first.job?.job_id || ''));

    const failed = recordChannelDeliveryJobAttempt(db, {
      job_id: first.job?.job_id,
      delivered: false,
      deny_code: 'slack_rate_limited',
      error_message: 'slack_rate_limited',
      retry_after_ms: 1200,
      provider_backoff_ms: 2000,
      now_ms: claimStart,
    });
    assert.equal(!!failed.ok, true);
    assert.equal(String(failed.job?.state || ''), 'failed');
    assert.equal(Number(failed.job?.next_attempt_at_ms || 0), claimStart + 1200);
    assert.equal(Number(failed.job?.provider_backoff_until_ms || 0), claimStart + 2000);

    const secondJobWhileBackoff = getChannelDeliveryJobById(db, {
      job_id: second.job?.job_id,
    });
    assert.equal(Number(secondJobWhileBackoff?.provider_backoff_until_ms || 0), claimStart + 2000);

    const deniedDuringBackoff = claimChannelDeliveryJobs(db, {
      provider: 'slack',
      account_id: 'ops-slack',
      now_ms: claimStart + 1500,
      limit: 10,
    });
    assert.equal(deniedDuringBackoff.length, 0);

    const claimedAfterBackoff = claimChannelDeliveryJobs(db, {
      provider: 'slack',
      account_id: 'ops-slack',
      now_ms: claimStart + 2001,
      limit: 10,
    });
    assert.equal(claimedAfterBackoff.length, 2);
  } finally {
    db.close();
    cleanupDbArtifacts(dbPath);
  }
});

run('XT-W3-24-M/dead-letter and manual retry surface explicit runtime degradation', () => {
  const dbPath = makeTmp('db', '.db');
  const db = new HubDB({ dbPath });
  try {
    const baseNow = Date.now();
    const queued = enqueueChannelDeliveryJob(db, {
      request_id: 'delivery-job-dead-letter-1',
      audit: {
        device_id: 'hub-supervisor',
        app_id: 'hub_runtime_operator_channels',
      },
      job: {
        provider: 'slack',
        account_id: 'ops-slack',
        conversation_id: 'C123',
        delivery_class: 'approval_request',
        payload_ref: 'local://channel-payloads/approval-1.json',
        dedupe_key: 'sha256:approval-1',
        audit_ref: 'audit-approval-1',
        incident_ref: 'incident-42',
        max_attempts: 1,
      },
    });
    assert.equal(!!queued.ok, true);

    const claimStart = Number(queued.job?.created_at_ms || baseNow) + 10;
    const claimed = claimChannelDeliveryJobs(db, {
      provider: 'slack',
      account_id: 'ops-slack',
      now_ms: claimStart,
      limit: 5,
    });
    assert.equal(claimed.length, 1);

    const failed = recordChannelDeliveryJobAttempt(db, {
      job_id: queued.job?.job_id,
      delivered: false,
      deny_code: 'slack_api_timeout',
      error_message: 'slack_api_timeout',
      retry_after_ms: 5000,
      provider_backoff_ms: 5000,
      now_ms: claimStart + 200,
    });
    assert.equal(!!failed.ok, true);
    assert.equal(String(failed.job?.state || ''), 'dead_letter');
    assert.equal(!!failed.job?.manual_retry_available, true);

    const projection = listChannelDeliveryJobRuntimeRows(db, {
      provider: 'slack',
      account_id: 'ops-slack',
      now_ms: claimStart + 300,
    });
    assert.equal(projection.length, 1);
    assert.equal(Number(projection[0]?.delivery_dead_letter_count || 0), 1);
    assert.equal(!!projection[0]?.manual_retry_available, true);
    assert.equal(!!projection[0]?.delivery_circuit_open, true);
    assert.equal(String(projection[0]?.last_delivery_error_code || ''), 'slack_api_timeout');

    const retried = retryChannelDeliveryJobManual(db, {
      job_id: queued.job?.job_id,
      request_id: 'delivery-job-manual-retry-1',
      audit: {
        device_id: 'hub-supervisor',
        app_id: 'hub_runtime_operator_channels',
      },
      now_ms: claimStart + 1000,
    });
    assert.equal(!!retried.ok, true);
    assert.equal(String(retried.job?.state || ''), 'queued');
    assert.equal(!!retried.job?.manual_retry_available, false);

    const afterRetryProjection = listChannelDeliveryJobRuntimeRows(db, {
      provider: 'slack',
      account_id: 'ops-slack',
      now_ms: claimStart + 1000,
    });
    assert.equal(Number(afterRetryProjection[0]?.delivery_dead_letter_count || 0), 0);
    assert.equal(!!afterRetryProjection[0]?.manual_retry_available, false);
    assert.equal(!!afterRetryProjection[0]?.delivery_circuit_open, false);

    const auditRows = db.listAuditEvents({ request_id: 'delivery-job-manual-retry-1' });
    assert.equal(
      auditRows.some((row) => String(row?.event_type || '') === 'channel.delivery_job.manual_retry_queued'),
      true
    );
  } finally {
    db.close();
    cleanupDbArtifacts(dbPath);
  }
});
