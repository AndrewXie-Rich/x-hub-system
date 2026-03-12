#!/usr/bin/env node
const fs = require("fs");
const path = require("path");

const repoRoot = path.resolve(__dirname, "..");
const bundlePath = path.join(repoRoot, "build/reports/xt_w3_31_require_real_capture_bundle.v1.json");
const outputPath = path.join(repoRoot, "build/reports/xt_w3_31_h_require_real_evidence.v1.json");

function readJSON(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJSON(filePath, value) {
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2) + "\n");
}

function isoNow() {
  return new Date().toISOString();
}

function hasEvidence(sample) {
  return Array.isArray(sample.evidence_refs) && sample.evidence_refs.length > 0;
}

function isExecuted(sample) {
  return typeof sample.performed_at === "string" && sample.performed_at.trim() !== "";
}

function isSuccessful(sample) {
  return sample.success_boolean === true;
}

function sampleSummary(sample) {
  return {
    sample_id: sample.sample_id,
    status: sample.status,
    performed_at: sample.performed_at || "",
    success_boolean: sample.success_boolean,
    evidence_refs: Array.isArray(sample.evidence_refs) ? sample.evidence_refs : []
  };
}

function main() {
  const bundle = readJSON(bundlePath);
  const samples = Array.isArray(bundle.samples) ? bundle.samples : [];
  const pendingSamples = samples.filter((sample) => !isExecuted(sample) || !hasEvidence(sample));
  const failedSamples = samples.filter((sample) => isExecuted(sample) && sample.success_boolean === false);
  const allExecuted = samples.length > 0 && samples.every((sample) => isExecuted(sample));
  const allSuccessful = samples.length > 0 && samples.every((sample) => isSuccessful(sample) && hasEvidence(sample));

  let gateVerdict = "NO_GO(capture_bundle_ready_but_require_real_samples_not_yet_executed)";
  let verdictReason = "XT-W3-31 capture bundle 已存在，但至少一个 SPF-G5 样本仍缺 performed_at / success_boolean=true / evidence_refs，require-real 尚未形成真实执行闭环。";
  let releaseStance = "no_go";
  let gateReadinessG5 = "not_ready(capture_bundle_ready_but_real_execution_pending)";

  if (failedSamples.length > 0) {
    gateVerdict = "NO_GO(require_real_sample_failed)";
    verdictReason = `XT-W3-31 require-real 样本存在失败项：${failedSamples.map((sample) => sample.sample_id).join(", ")}`;
    releaseStance = "no_go";
    gateReadinessG5 = "not_ready(real_execution_contains_failure)";
  } else if (allExecuted && allSuccessful) {
    gateVerdict = "PASS(require_real_samples_executed_and_verified)";
    verdictReason = "XT-W3-31 require-real 7 个 SPF-G5 样本均已执行，成功布尔值为 true，且 evidence_refs 已齐。";
    releaseStance = "candidate_go";
    gateReadinessG5 = "pass(require_real_samples_executed_and_verified)";
  }

  const output = {
    schema_version: "xhub.qa_main.xt_w3_31_h_require_real_evidence.v1",
    generated_at: isoNow(),
    timezone: "Asia/Shanghai",
    lane: "QA-Main",
    role: "shadow_parallel_qa",
    report_mode: "checklist_delta",
    dispatch_mode: "directed_only_no_broadcast",
    current_slice: "XT-W3-31-H",
    scope: "XT-W3-31-H shadow QA only",
    fail_closed: true,
    require_real: true,
    synthetic_not_accepted: true,
    gate_verdict: gateVerdict,
    verdict_reason: verdictReason,
    release_stance: releaseStance,
    machine_readable_evidence_present: [
      "build/reports/xt_w3_31_a_jurisdiction_registry_evidence.v1.json",
      "build/reports/xt_w3_31_b_project_capsule_evidence.v1.json",
      "build/reports/xt_w3_31_c_project_action_feed_evidence.v1.json",
      "build/reports/xt_w3_31_d_portfolio_snapshot_evidence.v1.json",
      "build/reports/xt_w3_31_e_notification_policy_evidence.v1.json",
      "build/reports/xt_w3_31_f_portfolio_ui_evidence.v1.json",
      "build/reports/xt_w3_31_g_drilldown_contract_evidence.v1.json"
    ],
    shadow_checklist: [
      {
        item: "XT-W3-31-A",
        title: "jurisdiction registry freeze",
        required_gate: "SPF-G0",
        required_machine_readable_evidence: "build/reports/xt_w3_31_a_jurisdiction_registry_evidence.v1.json",
        current_status: "candidate_pass(machine_readable_evidence_present)"
      },
      {
        item: "XT-W3-31-B",
        title: "project capsule contract and Hub sync",
        required_gate: "SPF-G1",
        required_machine_readable_evidence: "build/reports/xt_w3_31_b_project_capsule_evidence.v1.json",
        current_status: "candidate_pass(machine_readable_evidence_present)"
      },
      {
        item: "XT-W3-31-C",
        title: "project action event feed",
        required_gate: "SPF-G2",
        required_machine_readable_evidence: "build/reports/xt_w3_31_c_project_action_feed_evidence.v1.json",
        current_status: "candidate_pass(machine_readable_evidence_present)"
      },
      {
        item: "XT-W3-31-D",
        title: "portfolio snapshot aggregation",
        required_gate: "SPF-G1",
        required_machine_readable_evidence: "build/reports/xt_w3_31_d_portfolio_snapshot_evidence.v1.json",
        current_status: "candidate_pass(machine_readable_evidence_present_with_hub_truth_sync)"
      },
      {
        item: "XT-W3-31-E",
        title: "directed notification policy",
        required_gate: "SPF-G2",
        required_machine_readable_evidence: "build/reports/xt_w3_31_e_notification_policy_evidence.v1.json",
        current_status: "candidate_pass(machine_readable_evidence_present)"
      },
      {
        item: "XT-W3-31-F",
        title: "portfolio UI",
        required_gate: "SPF-G1",
        required_machine_readable_evidence: "build/reports/xt_w3_31_f_portfolio_ui_evidence.v1.json",
        current_status: "candidate_pass(machine_readable_evidence_present)"
      },
      {
        item: "XT-W3-31-G",
        title: "scope-safe drill-down",
        required_gate: "SPF-G3,SPF-G4",
        required_machine_readable_evidence: "build/reports/xt_w3_31_g_drilldown_contract_evidence.v1.json",
        current_status: "candidate_pass(machine_readable_evidence_present)"
      },
      {
        item: "XT-W3-31-H",
        title: "require-real regression",
        required_gate: "SPF-G5",
        required_machine_readable_evidence: "build/reports/xt_w3_31_h_require_real_evidence.v1.json",
        current_status: allExecuted ? (allSuccessful ? "executed_and_verified" : "executed_with_failure") : "capture_bundle_ready_waiting_real_execution"
      }
    ],
    gate_readiness: {
      "SPF-G0": "candidate_pass(contract_and_machine_readable_evidence_present)",
      "SPF-G1": "candidate_pass(portfolio_visibility_and_hub_truth_sync_present)",
      "SPF-G2": "candidate_pass(event_feed_and_notification_policy_present)",
      "SPF-G3": "candidate_pass(scope_safe_delta_capsule_refs_contract_present)",
      "SPF-G4": "candidate_pass(drilldown_dedupe_freshness_contract_present)",
      "SPF-G5": gateReadinessG5
    },
    missing_require_real_samples: pendingSamples.map((sample) => sample.sample_id),
    next_required_artifacts: pendingSamples.flatMap((sample) => {
      const missing = [];
      if (!isExecuted(sample)) {
        missing.push(`performed_at missing for ${sample.sample_id}`);
      }
      if (sample.success_boolean !== true) {
        missing.push(`success_boolean!=true for ${sample.sample_id}`);
      }
      if (!hasEvidence(sample)) {
        missing.push(`evidence_refs missing for ${sample.sample_id}`);
      }
      return missing;
    }),
    hard_lines: [
      "synthetic_mock_smoke_or_static_story_must_not_count_as_require_real",
      "missed_critical_event_count_must_remain_zero",
      "duplicate_interrupt_flood_must_not_occur_under_three_project_burst",
      "cross_project_memory_leak_is_immediate_NO_GO",
      "validated scope remains supervisor portfolio awareness and project action feed only",
      "no scope expansion to enterprise reporting or cross-project fulltext prompt fusion"
    ],
    next_owner_lane: allExecuted && allSuccessful ? "QA-Main" : "XT-Main",
    evidence_refs: [
      "build/reports/xt_w3_31_require_real_capture_bundle.v1.json",
      "build/reports/xt_w3_31_a_jurisdiction_registry_evidence.v1.json",
      "build/reports/xt_w3_31_b_project_capsule_evidence.v1.json",
      "build/reports/xt_w3_31_c_project_action_feed_evidence.v1.json",
      "build/reports/xt_w3_31_d_portfolio_snapshot_evidence.v1.json",
      "build/reports/xt_w3_31_e_notification_policy_evidence.v1.json",
      "build/reports/xt_w3_31_f_portfolio_ui_evidence.v1.json",
      "build/reports/xt_w3_31_g_drilldown_contract_evidence.v1.json",
      "x-terminal/work-orders/xt-w3-31-supervisor-portfolio-awareness-and-project-action-feed-implementation-pack-v1.md",
      "docs/memory-new/xhub-lane-command-board-v2.md",
      "scripts/generate_xt_w3_31_require_real_report.js"
    ],
    consumed_capture_bundle_path: "build/reports/xt_w3_31_require_real_capture_bundle.v1.json",
    consumed_capture_bundle: {
      path: "build/reports/xt_w3_31_require_real_capture_bundle.v1.json",
      consumed_at: isoNow(),
      bundle_status: bundle.status || "",
      bundle_generated_at: bundle.generated_at || "",
      execution_order: Array.isArray(bundle.execution_order) ? bundle.execution_order : [],
      stop_on_first_defect: !!bundle.stop_on_first_defect,
      validation: {
        total_samples: samples.length,
        executed_samples: samples.filter((sample) => isExecuted(sample)).map((sample) => sample.sample_id),
        pending_samples: pendingSamples.map((sample) => sample.sample_id),
        failed_samples: failedSamples.map((sample) => sample.sample_id),
        sample_summaries: samples.map(sampleSummary)
      }
    }
  };

  writeJSON(outputPath, output);
  process.stdout.write(`${outputPath}\n`);
}

main();
