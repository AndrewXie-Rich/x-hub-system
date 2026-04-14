#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");

const {
  buildOperatorChannelRecoveryReport,
} = require("./generate_xhub_operator_channel_recovery_report.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

function makeSummary(overrides = {}) {
  return {
    overall_status: "pass",
    hub_channel_onboarding_support: {
      all_source_smoke_status: "pass",
      hub_channel_onboarding_report: {
        bundle_kind: "channel_onboarding_readiness",
        surface: "hub_cli",
        overall_state: "blocked",
        ready_for_first_task: false,
        current_failure_code: "channel_runtime_not_ready",
        current_failure_issue: "channel_runtime",
        summary_headline: "Operator channel runtime is blocked",
        summary_failed: 1,
        summary_warned: 0,
        summary_passed: 2,
        summary_skipped: 0,
        primary_check: {
          check_id: "channel_runtime_not_ready",
          check_kind: "channel_runtime",
          status: "fail",
          severity: "error",
          blocking: true,
          headline: "Operator channel runtime is blocked",
          message: "Slack runtime is not ready for governed remote approval.",
          next_step: "Repair the runtime before retrying remote approval.",
          repair_destination_ref: "hub://settings/operator_channels",
          provider_ids: ["slack"],
          error_codes: ["webhook_replay_detected"],
          fetch_errors: [],
          required_next_steps: [],
        },
        blocking_next_step: {
          step_id: "open_operator_channel_repair_surface",
          kind: "open_repair_surface",
          label: "Open operator channel repair surface",
          owner: "user",
          blocking: true,
          destination_ref: "hub://settings/operator_channels",
          instruction: "Repair the runtime before retrying remote approval.",
        },
        advisory_next_step: null,
      },
      hub_doctor_cli_summary: {
        channel: {
          output_path: "/tmp/xhub_doctor_output_channel_onboarding.redacted.json",
          current_failure_code: "channel_runtime_not_ready",
          current_failure_issue: "channel_runtime",
          primary_next_step: {
            step_id: "open_operator_channel_repair_surface",
            kind: "open_repair_surface",
            label: "Open operator channel repair surface",
            owner: "user",
            blocking: true,
            destination_ref: "hub://settings/operator_channels",
            instruction: "Repair the runtime before retrying remote approval.",
          },
          blocking_next_step: {
            step_id: "open_operator_channel_repair_surface",
            kind: "open_repair_surface",
            label: "Open operator channel repair surface",
            owner: "user",
            blocking: true,
            destination_ref: "hub://settings/operator_channels",
            instruction: "Repair the runtime before retrying remote approval.",
          },
          advisory_next_step: null,
        },
      },
    },
    ...overrides,
  };
}

function makeAllSmokeEvidence(overrides = {}) {
  return {
    status: "pass",
    hub_channel_onboarding_report: {
      schema_version: "xhub.doctor_output.v1",
      bundle_kind: "channel_onboarding_readiness",
      surface: "hub_cli",
      overall_state: "degraded",
      ready_for_first_task: true,
      current_failure_code: "channel_delivery_partially_ready",
      current_failure_issue: "channel_delivery",
      summary: {
        headline: "Delivery is partially ready",
        failed: 0,
        warned: 1,
        passed: 2,
        skipped: 0,
      },
      checks: [
        {
          check_id: "channel_delivery_partially_ready",
          check_kind: "channel_delivery",
          status: "warn",
          severity: "warning",
          blocking: false,
          headline: "Delivery is partially ready",
          message: "Telegram reply credentials are not fully configured.",
          next_step: "Repair the Telegram bot token first.",
          repair_destination_ref: "hub://settings/operator_channels",
          detail_lines: [
            "provider=telegram ready=0 reply_enabled=1 credentials_configured=0 deny_code=bot_token_missing",
          ],
        },
      ],
      next_steps: [
        {
          step_id: "inspect_operator_channel_diagnostics",
          kind: "inspect_diagnostics",
          label: "Inspect operator channel diagnostics",
          owner: "user",
          blocking: false,
          destination_ref: "hub://settings/diagnostics",
          instruction: "Repair the Telegram bot token first.",
        },
      ],
      report_path: "/tmp/xhub_doctor_output_channel_onboarding.redacted.json",
      source_report_path: "hub://admin/operator-channels",
    },
    hub_doctor_cli_summary: {
      channel: {
        output_path: "/tmp/xhub_doctor_output_channel_onboarding.redacted.json",
        current_failure_code: "channel_delivery_partially_ready",
        current_failure_issue: "channel_delivery",
        primary_next_step: {
          step_id: "inspect_operator_channel_diagnostics",
          kind: "inspect_diagnostics",
          label: "Inspect operator channel diagnostics",
          owner: "user",
          blocking: false,
          destination_ref: "hub://settings/diagnostics",
          instruction: "Repair the Telegram bot token first.",
        },
        blocking_next_step: null,
        advisory_next_step: {
          step_id: "inspect_operator_channel_diagnostics",
          kind: "inspect_diagnostics",
          label: "Inspect operator channel diagnostics",
          owner: "user",
          blocking: false,
          destination_ref: "hub://settings/diagnostics",
          instruction: "Repair the Telegram bot token first.",
        },
      },
    },
    ...overrides,
  };
}

run("operator channel recovery report classifies replay protection failures", () => {
  const report = buildOperatorChannelRecoveryReport({
    generatedAt: "2026-03-24T12:00:00Z",
    sourceGateSummary: makeSummary(),
  });

  assert.equal(
    report.gate_verdict,
    "PASS(channel_onboarding_recovery_report_generated_from_structured_doctor_truth)"
  );
  assert.equal(report.release_stance, "preview_working");
  assert.equal(report.machine_decision.current_failure_code, "channel_runtime_not_ready");
  assert.equal(report.recovery_classification.action_category, "repair_replay_protection");
  assert.equal(report.onboarding_truth.provider_ids[0], "slack");
  assert.equal(report.onboarding_truth.error_codes[0], "webhook_replay_detected");
  assert.equal(report.recommended_actions[0].action_id, "repair_replay_protection");
  assert.equal(
    report.support_faq[0].answer.includes("channel_runtime_not_ready"),
    true
  );
});

run("operator channel recovery report falls back to all-source smoke evidence when summary is stale", () => {
  const report = buildOperatorChannelRecoveryReport({
    sourceGateSummary: { overall_status: "pass" },
    allSmokeEvidence: makeAllSmokeEvidence(),
  });

  assert.equal(report.machine_decision.source, "all_source_smoke_evidence");
  assert.equal(report.machine_decision.current_failure_code, "channel_delivery_partially_ready");
  assert.equal(report.onboarding_truth.provider_ids[0], "telegram");
  assert.equal(report.onboarding_truth.error_codes[0], "bot_token_missing");
  assert.equal(report.recovery_classification.action_category, "repair_channel_credentials");
  assert.equal(report.recommended_actions[0].action_id, "repair_channel_credentials");
  assert.equal(
    report.release_wording.external_status_line.includes("preview-working"),
    true
  );
});

run("operator channel recovery report elevates heartbeat governance visibility gaps into dedicated recovery guidance", () => {
  const summary = makeSummary();
  summary.hub_channel_onboarding_support.hub_channel_onboarding_report.current_failure_code =
    "channel_live_test_heartbeat_visibility_missing";
  summary.hub_channel_onboarding_support.hub_channel_onboarding_report.current_failure_issue =
    "channel_live_test";
  summary.hub_channel_onboarding_support.hub_channel_onboarding_report.summary_headline =
    "First live test proof is missing heartbeat governance visibility";
  summary.hub_channel_onboarding_support.hub_channel_onboarding_report.primary_check = {
    check_id: "channel_live_test_heartbeat_visibility_missing",
    check_kind: "channel_live_test",
    status: "fail",
    severity: "error",
    blocking: false,
    headline: "First smoke proof is incomplete",
    message: "The onboarding proof chain still needs one more governance export before release wording can proceed.",
    next_step: "Inspect operator channel diagnostics and refresh the proof chain.",
    repair_destination_ref: "hub://settings/operator_channels",
    provider_ids: ["slack"],
    error_codes: [],
    fetch_errors: [],
    required_next_steps: [],
  };
  summary.hub_channel_onboarding_support.hub_channel_onboarding_report.blocking_next_step = null;
  summary.hub_channel_onboarding_support.hub_channel_onboarding_report.advisory_next_step = {
    step_id: "inspect_operator_channel_diagnostics",
    kind: "inspect_diagnostics",
    label: "Inspect operator channel diagnostics",
    owner: "user",
    blocking: false,
    destination_ref: "hub://settings/diagnostics",
    instruction: "Verify heartbeat quality and next-review visibility before retrying release wording.",
  };
  summary.hub_channel_onboarding_support.hub_doctor_cli_summary.channel.current_failure_code =
    "channel_live_test_heartbeat_visibility_missing";
  summary.hub_channel_onboarding_support.hub_doctor_cli_summary.channel.current_failure_issue =
    "channel_live_test";
  summary.hub_channel_onboarding_support.hub_doctor_cli_summary.channel.primary_next_step = {
    step_id: "inspect_operator_channel_diagnostics",
    kind: "inspect_diagnostics",
    label: "Inspect operator channel diagnostics",
    owner: "user",
    blocking: false,
    destination_ref: "hub://settings/diagnostics",
    instruction: "Verify heartbeat quality and next-review visibility before retrying release wording.",
  };
  summary.hub_channel_onboarding_support.hub_doctor_cli_summary.channel.blocking_next_step = null;
  summary.hub_channel_onboarding_support.hub_doctor_cli_summary.channel.advisory_next_step =
    summary.hub_channel_onboarding_support.hub_doctor_cli_summary.channel.primary_next_step;

  const report = buildOperatorChannelRecoveryReport({
    generatedAt: "2026-04-01T02:03:04Z",
    sourceGateSummary: summary,
  });

  assert.equal(report.recovery_classification.action_category, "restore_heartbeat_governance_visibility");
  assert.equal(report.recommended_actions[0].action_id, "restore_heartbeat_governance_visibility");
  assert.equal(String(report.recommended_actions[0].command_or_ref || ""), "Inspect operator channel diagnostics and refresh the proof chain.");
  assert.equal(
    report.release_wording.blocked_claims.some((item) => String(item || "").includes("heartbeat governance visibility")),
    true
  );
});

run("operator channel recovery report fails closed when support artifacts are missing", () => {
  const report = buildOperatorChannelRecoveryReport({
    sourceGateSummary: { overall_status: "fail" },
    allSmokeEvidence: null,
  });

  assert.equal(report.gate_verdict, "NO_GO(hub_channel_onboarding_support_missing)");
  assert.equal(report.release_stance, "no_go");
  assert.equal(report.machine_decision.support_ready, false);
  assert.equal(report.recommended_actions[0].action_id, "inspect_channel_onboarding_report");
  assert.equal(
    report.release_wording.external_status_line.includes("incomplete"),
    true
  );
});
