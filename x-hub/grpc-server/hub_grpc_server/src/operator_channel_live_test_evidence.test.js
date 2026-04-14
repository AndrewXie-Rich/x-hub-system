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
      repair_hints: [],
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
      repair_hints: [],
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
          heartbeat_governance_snapshot: {
            project_id: 'project_alpha',
            project_name: 'Alpha',
            status_digest: 'Core loop advancing',
            latest_quality_band: 'usable',
            latest_quality_score: 74,
            open_anomaly_types: ['stale_repeat'],
            weak_reasons: ['evidence_thin'],
            next_review_due: {
              kind: 'review_pulse',
              due: true,
              at_ms: 1710000600000,
              reason_codes: ['pulse_due_window'],
            },
          },
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
  assert.deepEqual(report.repair_hints, []);
  assert.equal(report.onboarding_snapshot?.ticket?.ticket_id, 'ticket_live_1');
  assert.equal(
    report.onboarding_snapshot?.automation_state?.first_smoke?.heartbeat_governance_snapshot?.project_id,
    'project_alpha'
  );
  assert.equal(
    report.onboarding_snapshot?.automation_state?.first_smoke?.heartbeat_governance_snapshot?.latest_quality_band,
    'usable'
  );
  assert.equal(
    report.onboarding_snapshot?.automation_state?.first_smoke?.heartbeat_governance_snapshot?.next_review_due?.kind,
    'review_pulse'
  );
  assert.equal(report.provider_release_context?.release_blocked, false);
  assert.equal(deriveOperatorChannelLiveTestStatus(checks), 'pass');
  assert.equal(checks.every((check) => check.status === 'pass'), true);
  assert.equal(checks[6]?.name, 'heartbeat_governance_visible');
  assert.equal(String(checks[6]?.detail || '').includes('heartbeat_quality=usable'), true);
  assert.equal(String(checks[6]?.detail || '').includes('next_review=review_pulse'), true);
});

run('XT-W3-24-S/live test evidence fails when first smoke exists but heartbeat governance visibility is missing', () => {
  const fixtures = createPassFixtures('slack');
  delete fixtures.ticketDetail.automation_state.first_smoke.heartbeat_governance_snapshot;

  const report = buildOperatorChannelLiveTestEvidenceReport({
    provider: 'slack',
    verdict: 'passed',
    summary: 'Slack first smoke ran, but heartbeat governance projection was not exported.',
    readiness: fixtures.readiness,
    runtimeStatus: fixtures.runtimeStatus,
    ticketDetail: fixtures.ticketDetail,
  });

  assert.equal(report.derived_status, 'attention');
  assert.equal(report.live_test_success, false);
  assert.equal(report.checks[5]?.name, 'first_smoke_executed');
  assert.equal(report.checks[5]?.status, 'pass');
  assert.equal(report.checks[6]?.name, 'heartbeat_governance_visible');
  assert.equal(report.checks[6]?.status, 'fail');
  assert.equal(
    report.required_next_step,
    'Re-run or reload first smoke and verify it exported heartbeat governance visibility (quality band / next review).'
  );
});

run('XT-W3-24-S/live test evidence fails closed for WhatsApp Cloud until require-real release evidence clears the block', () => {
  const fixtures = createPassFixtures('whatsapp_cloud_api');
  fixtures.runtimeStatus = {
    ...fixtures.runtimeStatus,
    label: 'WhatsApp Cloud Ops',
    release_stage: 'p1',
    release_blocked: true,
    require_real_evidence: true,
    operator_surface: 'hub_supervisor_facade',
    repair_hints: [
      'Keep WhatsApp Cloud API in designed/wired mode until real live evidence clears the release block.',
    ],
  };

  const report = buildOperatorChannelLiveTestEvidenceReport({
    provider: 'whatsapp_cloud_api',
    verdict: 'passed',
    summary: 'WhatsApp Cloud smoke path responded, but release wording must stay blocked.',
    readiness: fixtures.readiness,
    runtimeStatus: fixtures.runtimeStatus,
    ticketDetail: fixtures.ticketDetail,
  });

  assert.equal(report.operator_verdict, 'passed');
  assert.equal(report.derived_status, 'attention');
  assert.equal(report.live_test_success, false);
  assert.equal(report.provider_release_context?.release_blocked, true);
  assert.equal(report.provider_release_context?.require_real_evidence, true);
  assert.equal(report.checks[2]?.name, 'release_ready_boundary');
  assert.equal(report.checks[2]?.status, 'fail');
  assert.equal(
    report.checks[2]?.remediation,
    'Keep WhatsApp Cloud API in designed/wired mode until real live evidence clears the release block.'
  );
  assert.deepEqual(report.repair_hints, [
    'Keep WhatsApp Cloud API in designed/wired mode until real live evidence clears the release block.',
  ]);
  assert.equal(
    report.required_next_step,
    'Keep WhatsApp Cloud API in designed/wired mode until real live evidence clears the release block.'
  );
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
  assert.equal(report.checks[6]?.name, 'heartbeat_governance_visible');
  assert.equal(report.checks[6]?.status, 'pending');
  assert.equal(
    report.required_next_step,
    'Confirm the local-only connector worker is running and reload operator channel runtime status.'
  );
});

run('XT-W3-24-S/live test evidence fails closed into attention when approval or smoke state regresses', () => {
  const runtimeRepairHint = 'Restart the Telegram polling worker with HUB_TELEGRAM_OPERATOR_ENABLE=1, HUB_TELEGRAM_OPERATOR_BOT_TOKEN, and HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN.';
  const readinessRepairHint = 'Load the Telegram bot token into the running Hub process and keep reply delivery enabled.';
  const report = buildOperatorChannelLiveTestEvidenceReport({
    provider: 'telegram',
    readiness: {
      provider: 'telegram',
      ready: false,
      reply_enabled: true,
      credentials_configured: false,
      deny_code: 'provider_delivery_not_configured',
      remediation_hint: 'load bot token',
      repair_hints: [readinessRepairHint],
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
      repair_hints: [runtimeRepairHint],
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
  assert.equal(report.checks[0]?.remediation, runtimeRepairHint);
  assert.equal(report.checks[1]?.remediation, readinessRepairHint);
  assert.equal(report.checks[4]?.name, 'approval_recorded');
  assert.equal(report.checks[4]?.status, 'fail');
  assert.equal(report.checks[5]?.name, 'first_smoke_executed');
  assert.equal(report.checks[5]?.status, 'fail');
  assert.equal(report.checks[6]?.name, 'heartbeat_governance_visible');
  assert.equal(report.checks[6]?.status, 'fail');
  assert.deepEqual(report.repair_hints, [runtimeRepairHint, readinessRepairHint]);
  assert.equal(report.required_next_step, runtimeRepairHint);
});

run('XT-W3-24-S/live test evidence promotes invalid-token repair hints into required next step', () => {
  const report = buildOperatorChannelLiveTestEvidenceReport({
    provider: 'feishu',
    verdict: 'partial',
    summary: 'Feishu ingress reached Hub, but token verification is still broken.',
    readiness: {
      provider: 'feishu',
      ready: false,
      reply_enabled: true,
      credentials_configured: true,
      deny_code: '',
      remediation_hint: '',
      repair_hints: [],
    },
    runtimeStatus: {
      provider: 'feishu',
      label: 'Feishu Ops',
      release_stage: 'wave1',
      release_blocked: false,
      require_real_evidence: false,
      endpoint_visibility: 'relay_only',
      operator_surface: 'group',
      runtime_state: 'ingress_ready',
      delivery_ready: false,
      command_entry_ready: false,
      last_error_code: 'verification_token_invalid',
      updated_at_ms: 1710000005800,
      repair_hints: [],
    },
    ticketDetail: {
      ticket: {
        ticket_id: 'ticket_live_feishu_invalid',
        provider: 'feishu',
        conversation_id: 'oc_room_invalid',
        thread_key: 'om_invalid',
        ingress_surface: 'group',
        status: 'reviewed',
        first_message_preview: 'status',
        updated_at_ms: 1710000005900,
      },
      latest_decision: null,
      automation_state: {
        first_smoke: null,
        outbox_pending_count: 0,
        outbox_delivered_count: 0,
        outbox_items: [],
      },
    },
  });

  assert.equal(report.derived_status, 'attention');
  assert.equal(report.live_test_success, false);
  assert.equal(
    report.repair_hints.some((item) => String(item || '').includes('HUB_FEISHU_OPERATOR_VERIFICATION_TOKEN')),
    true
  );
  assert.equal(
    String(report.required_next_step || '').includes('HUB_FEISHU_OPERATOR_VERIFICATION_TOKEN'),
    true
  );
});

run('XT-W3-24-S/live test evidence promotes signature mismatch repair hints into required next step', () => {
  const report = buildOperatorChannelLiveTestEvidenceReport({
    provider: 'slack',
    verdict: 'partial',
    summary: 'Slack ingress reached Hub, but signature verification is still failing.',
    readiness: {
      provider: 'slack',
      ready: true,
      reply_enabled: true,
      credentials_configured: true,
      deny_code: '',
      remediation_hint: '',
      repair_hints: [],
    },
    runtimeStatus: {
      provider: 'slack',
      label: 'Slack Ops',
      release_stage: 'wave1',
      release_blocked: false,
      require_real_evidence: false,
      endpoint_visibility: 'relay_only',
      operator_surface: 'thread',
      runtime_state: 'degraded',
      delivery_ready: false,
      command_entry_ready: false,
      last_error_code: 'signature_invalid',
      updated_at_ms: 1710000006000,
      repair_hints: [],
    },
    ticketDetail: {
      ticket: {
        ticket_id: 'ticket_live_slack_signature',
        provider: 'slack',
        conversation_id: 'C_signature',
        thread_key: '171.84',
        ingress_surface: 'thread',
        status: 'reviewed',
        first_message_preview: 'status',
        updated_at_ms: 1710000006100,
      },
      latest_decision: null,
      automation_state: {
        first_smoke: null,
        outbox_pending_count: 0,
        outbox_delivered_count: 0,
        outbox_items: [],
      },
    },
  });

  assert.equal(report.derived_status, 'attention');
  assert.equal(report.live_test_success, false);
  assert.equal(report.checks[0]?.name, 'runtime_command_entry_ready');
  assert.equal(report.checks[0]?.status, 'fail');
  assert.equal(
    String(report.checks[0]?.remediation || '').includes('HUB_SLACK_OPERATOR_SIGNING_SECRET'),
    true
  );
  assert.equal(
    String(report.checks[0]?.remediation || '').includes('/slack/events'),
    true
  );
  assert.equal(
    report.repair_hints.some((item) => String(item || '').includes('HUB_SLACK_OPERATOR_SIGNING_SECRET')),
    true
  );
  assert.equal(
    String(report.required_next_step || '').includes('HUB_SLACK_OPERATOR_SIGNING_SECRET'),
    true
  );
});

run('XT-W3-24-S/live test evidence promotes replay suspicion repair hints from automation delivery state', () => {
  const report = buildOperatorChannelLiveTestEvidenceReport({
    provider: 'telegram',
    verdict: 'partial',
    summary: 'Telegram channel hit replay protection and failed closed.',
    readiness: null,
    runtimeStatus: {
      provider: 'telegram',
      label: 'Telegram Ops',
      release_stage: 'wave1',
      release_blocked: false,
      require_real_evidence: false,
      endpoint_visibility: 'relay_only',
      operator_surface: 'dm',
      runtime_state: 'degraded',
      delivery_ready: false,
      command_entry_ready: true,
      last_error_code: '',
      updated_at_ms: 1710000006200,
      repair_hints: [],
    },
    ticketDetail: {
      ticket: {
        ticket_id: 'ticket_live_telegram_replay',
        provider: 'telegram',
        conversation_id: 'chat_replay',
        thread_key: '',
        ingress_surface: 'dm',
        status: 'held',
        first_message_preview: 'status',
        updated_at_ms: 1710000006300,
      },
      latest_decision: null,
      automation_state: {
        first_smoke: null,
        outbox_pending_count: 1,
        outbox_delivered_count: 0,
        delivery_readiness: {
          provider: 'telegram',
          ready: false,
          reply_enabled: true,
          credentials_configured: true,
          deny_code: 'replay_detected',
          remediation_hint: '',
          repair_hints: [],
        },
        outbox_items: [
          {
            item_id: 'outbox_pending_replay_1',
            item_kind: 'onboarding_ack',
            status: 'pending',
            last_error_code: 'replay_detected',
          },
        ],
      },
    },
  });

  assert.equal(report.derived_status, 'attention');
  assert.equal(report.live_test_success, false);
  assert.equal(report.checks[0]?.name, 'runtime_command_entry_ready');
  assert.equal(report.checks[0]?.status, 'pass');
  assert.equal(report.checks[1]?.name, 'delivery_ready');
  assert.equal(report.checks[1]?.status, 'fail');
  assert.equal(
    String(report.checks[1]?.remediation || '').includes('重新发送一条新消息'),
    true
  );
  assert.equal(
    String(report.checks[1]?.remediation || '').includes('不要直接复用旧 payload'),
    true
  );
  assert.equal(
    report.repair_hints.some((item) => String(item || '').includes('重新发送一条新消息')),
    true
  );
  assert.equal(
    String(report.required_next_step || '').includes('重新发送一条新消息'),
    true
  );
});

await runAsync('XT-W3-24-S/live test evidence CLI prefers the Hub-built evidence endpoint when available', async () => {
  const fixtures = createPassFixtures('slack');
  const outputPath = makeTmpFile('cli');
  const stdout = [];
  const fetchCalls = [];

  try {
    const baseUrl = 'http://127.0.0.1:50052';
    const serverReport = buildOperatorChannelLiveTestEvidenceReport({
      provider: 'slack',
      verdict: 'passed',
      summary: 'Slack first live test succeeded.',
      performedAt: '2026-03-15T11:00:00Z',
      evidenceRefs: ['captures/slack-live-1.png', 'captures/slack-live-1.png'],
      readiness: fixtures.readiness,
      runtimeStatus: fixtures.runtimeStatus,
      ticketDetail: fixtures.ticketDetail,
      adminBaseUrl: baseUrl,
      outputPath: '',
    });
    const fetchImpl = async (url, options = {}) => {
      const target = new URL(String(url));
      fetchCalls.push({
        pathname: target.pathname,
        search: target.search,
        authorization: String(options.headers?.authorization || ''),
      });

      let body = null;
      if (target.pathname === '/admin/operator-channels/live-test/evidence') {
        body = {
          ok: true,
          report: serverReport,
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
    assert.equal(result.report.machine_readable_evidence_path, outputPath);
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
      ['/admin/operator-channels/live-test/evidence']
    );
    assert.equal(fetchCalls[0]?.search.includes('provider=slack'), true);
    assert.equal(fetchCalls[0]?.search.includes(`ticket_id=${fixtures.ticketDetail.ticket.ticket_id}`), true);
    assert.equal(fetchCalls[0]?.search.includes('verdict=passed'), true);
    assert.equal(
      fetchCalls.every((item) => item.authorization === 'Bearer admin-token-live-test'),
      true
    );
  } finally {
    cleanupFile(outputPath);
  }
});

await runAsync('XT-W3-24-S/live test evidence CLI falls back to legacy admin-only snapshots when the Hub endpoint is unavailable', async () => {
  const fixtures = createPassFixtures('slack');
  const outputPath = makeTmpFile('cli_fallback');
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
      if (target.pathname === '/admin/operator-channels/live-test/evidence') {
        body = {
          ok: false,
          error: {
            code: 'not_found',
            message: target.pathname,
          },
        };
      } else if (target.pathname === '/admin/operator-channels/readiness') {
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
        '/admin/operator-channels/live-test/evidence',
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
