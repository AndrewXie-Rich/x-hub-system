#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORT_DIR="${XT_W3_40_REAL_SMOKE_REPORT_DIR:-${ROOT_DIR}/build/reports}"
TEMPLATE_FILE="${XT_W3_40_REAL_SMOKE_TEMPLATE_FILE:-${REPORT_DIR}/xt_w3_40_real_device_smoke_evidence.template.v1.json}"
FINAL_REPORT_FILE="${XT_W3_40_REAL_SMOKE_REPORT_FILE:-${REPORT_DIR}/xt_w3_40_real_device_smoke_evidence.v1.json}"

mkdir -p "${REPORT_DIR}"

TEMPLATE_FILE="${TEMPLATE_FILE}" FINAL_REPORT_FILE="${FINAL_REPORT_FILE}" node <<'NODE'
const fs = require("fs");

const templateFile = process.env.TEMPLATE_FILE;
const finalReportFile = process.env.FINAL_REPORT_FILE;
const now = new Date().toISOString();
const placeholder = "fill_me";

const requiredSteps = [
  {
    id: "preview_voice_heads_up",
    action: "Set Preview Phase = Heads Up and run Preview Voice Reminder once",
    expected_result: "Supervisor plays the heads-up reminder line through the current XT playback path"
  },
  {
    id: "preview_voice_final_call",
    action: "Set Preview Phase = Final Call and run Preview Voice Reminder once",
    expected_result: "Supervisor plays the final-call reminder line through the current XT playback path"
  },
  {
    id: "preview_voice_start_now",
    action: "Set Preview Phase = Start Now and run Preview Voice Reminder once",
    expected_result: "Supervisor plays the start-now reminder line through the current XT playback path"
  },
  {
    id: "notification_fallback",
    action: "Run Test Notification Fallback for at least one preview phase",
    expected_result: "Local notification fallback can trigger without depending on a separate fake TTS path"
  },
  {
    id: "simulate_live_delivery",
    action: "Run Simulate Live Delivery for at least one preview phase",
    expected_result: "Smoke result reflects the real XT route decision and current reminder runtime state"
  },
  {
    id: "refresh_meetings_after_calendar_grant",
    action: "Grant Calendar permission to X-Terminal and run Refresh Meetings",
    expected_result: "Upcoming Meeting Snapshot shows at least one local near-term meeting from this XT device"
  },
  {
    id: "real_heads_up_delivery",
    action: "Create a near-term meeting and observe the real heads-up reminder delivery",
    expected_result: "Real scheduler delivers the heads-up phase for the created test meeting"
  },
  {
    id: "real_final_call_delivery",
    action: "Observe the real final-call reminder delivery for the same test meeting",
    expected_result: "Real scheduler delivers the final-call phase for the created test meeting"
  },
  {
    id: "real_start_now_delivery",
    action: "Observe the real start-now reminder delivery for the same test meeting",
    expected_result: "Real scheduler delivers the start-now phase for the created test meeting"
  },
  {
    id: "active_conversation_behavior",
    action: "Trigger a reminder while XT has an active conversation session",
    expected_result: "Reminder follows the designed active-conversation defer behavior instead of interrupting incorrectly"
  },
  {
    id: "quiet_hours_behavior",
    action: "Trigger a reminder during quiet hours or a configured equivalent window",
    expected_result: "Reminder follows the designed quiet-hours fallback or defer behavior"
  }
];

const report = {
  schema_version: "xt_w3_40_real_device_smoke_evidence.v1",
  generated_at: now,
  status: "pending",
  claim:
    "X-Terminal is the only personal calendar permission owner and can deliver XT-local Supervisor meeting reminders on a real device without routing raw calendar events back through Hub.",
  claim_scope: ["XT-W3-40", "XT-CALENDAR-REAL-DEVICE"],
  contract_evidence_refs: [
    "build/reports/xt_w3_40_calendar_boundary_evidence.v1.json"
  ],
  operator_run_context: {
    device_label: placeholder,
    operator: placeholder,
    xt_app_path: "build/X-Terminal.app",
    xt_app_version: placeholder,
    xt_app_build: placeholder,
    macos_version: placeholder,
    timezone: placeholder,
    run_started_at: placeholder,
    run_finished_at: placeholder
  },
  permission_snapshot: {
    calendar: placeholder,
    notifications: placeholder,
    microphone: "optional_not_checked",
    speech_recognition: "optional_not_checked"
  },
  smoke_steps: requiredSteps.map((step) => ({
    id: step.id,
    required: true,
    status: "pending",
    action: step.action,
    expected_result: step.expected_result,
    evidence_refs: [],
    detail: placeholder
  })),
  summary: {
    required_step_count: requiredSteps.length,
    passed_required_step_count: 0,
    human_summary:
      "Pending real-device smoke on X-Terminal.app. Fill this report after running section 9.3 of XT-W3-40."
  },
  bounded_gaps: [],
  notes: [
    `Copy this template to ${finalReportFile} after filling operator context, step results, and evidence refs.`
  ]
};

fs.writeFileSync(templateFile, `${JSON.stringify(report, null, 2)}\n`, "utf8");
console.log(templateFile);
NODE
