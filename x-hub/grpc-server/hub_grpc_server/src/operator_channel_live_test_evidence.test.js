import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { main as runLiveTestEvidenceCli } from '../scripts/generate_operator_channel_live_test_evidence_report.js';
import {
  OPERATOR_CHANNEL_LIVE_TEST_EVIDENCE_SCHEMA,
  buildOperatorChannelLiveTestEvidenceReport,
  deriveOperatorChannelLiveTestStatus,
  evaluateOperatorChannelLiveTestChecks,
  operatorChannelLiveTestProviderRow,
} from './operator_channel_live_test_evidence.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const CLI_PATH = path.join(HERE, '../scripts/generate_operator_channel_live_test_evidence_report.js');

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

async function runAsync(name, fn) {
  try {
    await fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

function makeTmpFile(label, suffix = '.json') {
  const token = `${label}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  return path.join(os.tmpdir(), `operator_channel_live_test_${token}${suffix}`);
}

function cleanupFile(filePath) {
  try { fs.rmSync(filePath, { force: true }); } catch { /* ignore */ }
}

function createPassFixtures(provider = 'slack') {
  return {
    readiness: {
      provider,
      ready: true,
      reply_enabled: true,
      credentials_configured: true,
      deny_code: '',
      remediation_hint: '',
    },
    runtimeStatus: {
      provider,
      label: 'Slack Ops',
      release_stage: 'wave1',
      release_blocked: false,
      require_real_evidence: false,
      endpoint_visibility: 'relay_only',
      operator_surface: 'thread',
      runtime_state: 'ready',
      delivery_ready: true,
      command_entry_ready: true,
      updated_at_ms: 1710000005000,
      last_error_code: '',
    },
    ticketDetail: {
      ticket: {
        ticket_id: 'ticket_live_1',
        provider,
        conversation_id: 'C_ops',
        thread_key: '171.42',
        ingress_surface: 'group',
        status: 'approved',
        first_message_preview: 'status',
        updated_at_ms: 1710000005100,
      },
      latest_decision: {
        decision_id: 'decision_live_1',
        decision: 'approve',
        approved_by_hub_user_id: 'hub_admin',
        hub_user_id: 'ops_alice',
        scope_type: 'project',
        scope_id: 'project_alpha',
        binding_mode: 'thread_binding',
        grant_profile: 'low_risk_readonly',
        created_at_ms: 1710000005200,
      },
      automation_state: {
        first_smoke: {
          receipt_id: 'receipt_live_1',
          action_name: 'supervisor.status.get',
          status: 'query_executed',
          route_mode: 'hub_to_xt',
          detail: 'prepared and returned',
          remediation_hint: '',
          updated_at_ms: 1710000005300,
        },
        outbox_pending_count: 0,
        outbox_delivered_count: 2,
        outbox_items: [
          {
            item_id: 'outbox_delivered_1',
            item_kind: 'onboarding_ack',
            status: 'delivered',
          },
        ],
      },
    },
  };
}

run('XT-W3-24-S/live test evidence report resolves full pass state and de-duplicates evidence refs', () => {
  const fixtures = createPassFixtures('slack');
  const readinessSnapshot = {
    providers: [
      fixtures.readiness,
      { provider: 'telegram', ready: false },
    ],
  };
  const runtimeSnapshot = {
    providers: [
      fixtures.runtimeStatus,
      { provider: 'feishu', runtime_state: 'not_configured' },
    ],
  };

  const readiness = operatorChannelLiveTestProviderRow(readinessSnapshot, 'slack');
  const runtimeStatus = operatorChannelLiveTestProviderRow(runtimeSnapshot, 'slack');
  const checks = evaluateOperatorChannelLiveTestChecks({
    provider: 'slack',
    readiness,
    runtimeStatus,
    ticketDetail: fixtures.ticketDetail,
  });
  const report = buildOperatorChannelLiveTestEvidenceReport({
    provider: 'slack',
    verdict: 'passed',
    summary: 'Slack onboarding completed with first live reply.',
    performedAt: '2026-03-15T09:30:00Z',
    evidenceRefs: ['captures/slack-thread-1.png', 'captures/slack-thread-1.png', 'captures/slack-thread-2.png'],
    readiness,
    runtimeStatus,
    ticketDetail: fixtures.ticketDetail,
    adminBaseUrl: 'http://127.0.0.1:50052',
    outputPath: 'x-terminal/build/reports/xt_w3_24_s_slack_live_test_evidence.v1.json',
  });

  assert.equal(String(report.schema_version || ''), OPERATOR_CHANNEL_LIVE_TEST_EVIDENCE_SCHEMA);
  assert.equal(report.provider, 'slack');
  assert.equal(report.operator_verdict, 'passed');
  assert.equal(report.derived_status, 'pass');
  assert.equal(report.live_test_success, true);
  assert.equal(report.required_next_step, 'All key operator channel live-test checks passed.');
  assert.deepEqual(report.evidence_refs, ['captures/slack-thread-1.png', 'captures/slack-thread-2.png']);
  assert.equal(report.runtime_snapshot?.command_entry_ready, true);
  assert.equal(report.readiness_snapshot?.ready, true);
  assert.equal(report.onboarding_snapshot?.ticket?.ticket_id, 'ticket_live_1');
  assert.equal(report.provider_release_context?.release_blocked, false);
  assert.equal(deriveOperatorChannelLiveTestStatus(checks), 'pass');
  assert.equal(checks.every((check) => check.status === 'pass'), true);
});

run('XT-W3-24-S/live test evidence stays pending when runtime and onboarding proof are missing', () => {
  const report = buildOperatorChannelLiveTestEvidenceReport({
    provider: 'feishu',
    summary: 'Feishu connector not tested yet.',
  });

  assert.equal(report.provider, 'feishu');
  assert.equal(report.operator_verdict, 'pending');
  assert.equal(report.derived_status, 'pending');
  assert.equal(report.live_test_success, false);
  assert.equal(report.runtime_snapshot, null);
  assert.equal(report.readiness_snapshot, null);
  assert.equal(report.onboarding_snapshot?.ticket, null);
  assert.equal(report.checks[0]?.name, 'runtime_command_entry_ready');
  assert.equal(report.checks[0]?.status, 'pending');
  assert.equal(
    report.required_next_step,
    'Confirm the local-only connector worker is running and reload operator channel runtime status.'
  );
});

run('XT-W3-24-S/live test evidence fails closed into attention when approval or smoke state regresses', () => {
  const report = buildOperatorChannelLiveTestEvidenceReport({
    provider: 'telegram',
    readiness: {
      provider: 'telegram',
      ready: false,
      reply_enabled: true,
      credentials_configured: false,
      deny_code: 'provider_delivery_not_configured',
      remediation_hint: 'load bot token',
    },
    runtimeStatus: {
      provider: 'telegram',
      label: 'Telegram Ops',
      release_stage: 'wave1',
      release_blocked: false,
      require_real_evidence: false,
      endpoint_visibility: 'outbound_only',
      operator_surface: 'dm',
      runtime_state: 'degraded',
      delivery_ready: false,
      command_entry_ready: false,
      last_error_code: 'bot_token_missing',
      updated_at_ms: 1710000005400,
    },
    ticketDetail: {
      ticket: {
        ticket_id: 'ticket_live_telegram_1',
        provider: 'telegram',
        conversation_id: '12345',
        thread_key: '',
        ingress_surface: 'dm',
        status: 'reviewed',
        first_message_preview: 'deploy plan',
        updated_at_ms: 1710000005500,
      },
      latest_decision: {
        decision_id: 'decision_live_telegram_1',
        decision: 'reject',
        approved_by_hub_user_id: 'hub_admin',
        hub_user_id: 'ops_bob',
        scope_type: 'project',
        scope_id: 'project_beta',
        binding_mode: 'dm_binding',
        grant_profile: 'low_risk_readonly',
        created_at_ms: 1710000005600,
      },
      automation_state: {
        first_smoke: {
          receipt_id: 'receipt_live_telegram_1',
          action_name: 'supervisor.status.get',
          status: 'denied',
          route_mode: 'hub_only',
          remediation_hint: 'approve first',
          updated_at_ms: 1710000005700,
        },
        outbox_pending_count: 1,
        outbox_delivered_count: 0,
        outbox_items: [
          {
            item_id: 'outbox_pending_1',
            item_kind: 'onboarding_first_smoke',
            status: 'pending',
            last_error_code: 'provider_delivery_not_configured',
          },
        ],
      },
    },
  });

  assert.equal(report.operator_verdict, 'pending');
  assert.equal(report.derived_status, 'attention');
  assert.equal(report.live_test_success, false);
  assert.equal(report.checks[0]?.name, 'runtime_command_entry_ready');
  assert.equal(report.checks[0]?.status, 'fail');
  assert.equal(report.checks[3]?.name, 'approval_recorded');
  assert.equal(report.checks[3]?.status, 'fail');
  assert.equal(report.checks[4]?.name, 'first_smoke_executed');
  assert.equal(report.checks[4]?.status, 'fail');
  assert.equal(report.required_next_step.includes('Telegram polling worker'), true);
});

await runAsync('XT-W3-24-S/live test evidence CLI exports a report from local admin-only snapshots', async () => {
  const fixtures = createPassFixtures('slack');
  const outputPath = makeTmpFile('cli');
  const stdout = [];
  const fetchCalls = [];

  try {
    const baseUrl = 'http://127.0.0.1:50052';
    const fetchImpl = async (url, options = {}) => {
      const target = new URL(String(url));
      fetchCalls.push({
        pathname: target.pathname,
        authorization: String(options.headers?.authorization || ''),
      });

      let body = null;
      if (target.pathname === '/admin/operator-channels/readiness') {
        body = {
          ok: true,
          providers: [fixtures.readiness],
        };
      } else if (target.pathname === '/admin/operator-channels/runtime-status') {
        body = {
          ok: true,
          providers: [fixtures.runtimeStatus],
        };
      } else if (target.pathname === `/admin/operator-channels/onboarding/tickets/${fixtures.ticketDetail.ticket.ticket_id}`) {
        body = {
          ok: true,
          ...fixtures.ticketDetail,
        };
      } else {
        body = {
          ok: false,
          error: {
            code: 'not_found',
            message: target.pathname,
          },
        };
      }

      return {
        ok: !!body.ok,
        status: body.ok ? 200 : 404,
        async text() {
          return JSON.stringify(body);
        },
      };
    };

    const result = await runLiveTestEvidenceCli([
      '--provider', 'slack',
      '--ticket-id', fixtures.ticketDetail.ticket.ticket_id,
      '--verdict', 'passed',
      '--summary', 'Slack first live test succeeded.',
      '--performed-at', '2026-03-15T11:00:00Z',
      '--evidence-ref', 'captures/slack-live-1.png',
      '--evidence-ref', 'captures/slack-live-1.png',
      '--output', outputPath,
      '--base-url', baseUrl,
      '--admin-token', 'admin-token-live-test',
    ], {
      env: { ...process.env },
      fetchImpl,
      stdout: {
        write(chunk) {
          stdout.push(String(chunk));
        },
      },
    });

    assert.equal(result.report.provider, 'slack');
    assert.equal(result.report.operator_verdict, 'passed');
    assert.equal(result.report.derived_status, 'pass');
    assert.equal(result.report.live_test_success, true);
    assert.equal(result.report.admin_base_url, baseUrl);
    assert.equal(result.outputPath, outputPath);

    const report = JSON.parse(fs.readFileSync(outputPath, 'utf8'));
    assert.equal(report.provider, 'slack');
    assert.equal(report.operator_verdict, 'passed');
    assert.equal(report.derived_status, 'pass');
    assert.equal(report.live_test_success, true);
    assert.equal(report.admin_base_url, baseUrl);
    assert.equal(report.machine_readable_evidence_path, outputPath);
    assert.deepEqual(report.evidence_refs, ['captures/slack-live-1.png']);
    assert.equal(stdout.join('').includes('derived_status=pass'), true);
    assert.equal(stdout.join('').includes(`output=${outputPath}`), true);
    assert.deepEqual(
      fetchCalls.map((item) => item.pathname),
      [
        '/admin/operator-channels/readiness',
        '/admin/operator-channels/runtime-status',
        `/admin/operator-channels/onboarding/tickets/${fixtures.ticketDetail.ticket.ticket_id}`,
      ]
    );
    assert.equal(
      fetchCalls.every((item) => item.authorization === 'Bearer admin-token-live-test'),
      true
    );
  } finally {
    cleanupFile(outputPath);
  }
});

run('XT-W3-24-S/live test evidence CLI direct-run help stays available', () => {
  const proc = spawnSync('node', [CLI_PATH, '--help'], {
    cwd: path.join(HERE, '..'),
    encoding: 'utf8',
    env: { ...process.env },
  });

  assert.equal(proc.status, 0, proc.stderr);
  assert.equal(String(proc.stdout || '').includes('generate_operator_channel_live_test_evidence_report.js'), true);
  assert.equal(String(proc.stdout || '').includes('--provider slack|telegram|feishu|whatsapp_cloud_api'), true);
});
