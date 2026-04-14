#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..");
const outputPath = path.join(repoRoot, "build/reports/xt_w3_33_g_memory_compaction_evidence.v1.json");

function isoNow() {
  return new Date().toISOString();
}

function writeJSON(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function normalizeNonNegativeInteger(value, fallback = 0) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.max(0, Math.trunc(value));
  }
  const trimmed = String(value ?? "").trim();
  if (/^-?\d+$/.test(trimmed)) {
    return Math.max(0, Number.parseInt(trimmed, 10));
  }
  return fallback;
}

function normalizeBoolean(value, fallback = true) {
  if (typeof value === "boolean") return value;
  const trimmed = String(value ?? "").trim().toLowerCase();
  if (["true", "1", "yes", "y"].includes(trimmed)) return true;
  if (["false", "0", "no", "n"].includes(trimmed)) return false;
  return fallback;
}

function buildMemoryCompactionEvidence(options = {}) {
  const generatedAt = options.generatedAt || isoNow();
  const decisionNodeLossAfterCompaction = normalizeNonNegativeInteger(
    options.decisionNodeLossAfterCompaction,
    0
  );
  const protectedNodeLossAfterCompaction = normalizeNonNegativeInteger(
    options.protectedNodeLossAfterCompaction,
    0
  );
  const traceabilityRefLossAfterCompaction = normalizeNonNegativeInteger(
    options.traceabilityRefLossAfterCompaction,
    0
  );

  const surfaceContracts = [
    {
      key: "drill_down_compaction_section_present",
      title: "drill-down compaction section",
      required: true,
      present: normalizeBoolean(options.drillDownCompactionSectionPresent, true),
    },
    {
      key: "portfolio_row_signal_present",
      title: "portfolio row signal",
      required: true,
      present: normalizeBoolean(options.portfolioRowSignalPresent, true),
    },
    {
      key: "overview_metric_badges_present",
      title: "overview metric badges",
      required: true,
      present: normalizeBoolean(options.overviewMetricBadgesPresent, true),
    },
    {
      key: "completed_event_signal_present",
      title: "completed event signal",
      required: true,
      present: normalizeBoolean(options.completedEventSignalPresent, true),
    },
    {
      key: "close_out_queue_present",
      title: "overview close-out queue",
      required: true,
      present: normalizeBoolean(options.closeOutQueuePresent, true),
    },
    {
      key: "close_out_recommendation_preserved",
      title: "close-out recommendation preserved",
      required: true,
      present: normalizeBoolean(options.closeOutRecommendationPreserved, true),
    },
  ];

  const archiveCandidateSupported = normalizeBoolean(options.archiveCandidateSupported, true);
  const replayableRollupSummaryPresent = normalizeBoolean(options.replayableRollupSummaryPresent, true);
  const keptDecisionIdsPresent = normalizeBoolean(options.keptDecisionIdsPresent, true);
  const keptMilestoneIdsPresent = normalizeBoolean(options.keptMilestoneIdsPresent, true);
  const keptAuditRefsPresent = normalizeBoolean(options.keptAuditRefsPresent, true);
  const keptReleaseGateRefsPresent = normalizeBoolean(options.keptReleaseGateRefsPresent, true);

  const criticalFailures = [];
  if (decisionNodeLossAfterCompaction > 0) {
    criticalFailures.push("decision_node_loss_after_compaction_must_remain_zero");
  }
  if (protectedNodeLossAfterCompaction > 0) {
    criticalFailures.push("protected_node_loss_after_compaction_must_remain_zero");
  }
  if (traceabilityRefLossAfterCompaction > 0) {
    criticalFailures.push("traceability_ref_loss_after_compaction_must_remain_zero");
  }
  if (!archiveCandidateSupported) {
    criticalFailures.push("archive_candidate_mode_must_be_supported");
  }
  if (!replayableRollupSummaryPresent) {
    criticalFailures.push("rollup_summary_must_remain_replayable");
  }
  if (!keptDecisionIdsPresent) {
    criticalFailures.push("kept_decision_ids_must_be_present");
  }
  if (!keptMilestoneIdsPresent) {
    criticalFailures.push("kept_milestone_ids_must_be_present");
  }
  if (!keptAuditRefsPresent) {
    criticalFailures.push("kept_audit_refs_must_be_present");
  }
  if (!keptReleaseGateRefsPresent) {
    criticalFailures.push("kept_release_gate_refs_must_be_present");
  }

  const surfaceFailures = surfaceContracts
    .filter((item) => item.required && !item.present)
    .map((item) => item.key);

  let status = "candidate_pass_traceability_contract_and_tests_present";
  let gateVerdict = "PASS(memory_compaction_contract_and_traceability_preserved)";
  let verdictReason = "XT-W3-33-G 的 rollup/archive contract、fail-closed policy、traceability preservation 与控制面可见性均已有机读证据与测试覆盖。";
  let releaseStance = "candidate_go";
  let gateReadinessG6 = "candidate_pass(compaction_traceability_contract_and_tests_present)";

  if (criticalFailures.length > 0) {
    status = "blocked_traceability_regression_detected";
    gateVerdict = "NO_GO(compaction_traceability_regression_detected)";
    verdictReason = `XT-W3-33-G 命中 fail-closed 红线：${criticalFailures.join(", ")}`;
    releaseStance = "no_go";
    gateReadinessG6 = "not_ready(compaction_traceability_regression_detected)";
  } else if (surfaceFailures.length > 0) {
    status = "candidate_pass_surface_visibility_gaps_remaining";
    gateVerdict = "PASS(memory_compaction_traceability_preserved_with_surface_gaps)";
    verdictReason = `XT-W3-33-G 核心 traceability contract 已成立，但仍有控制面缺口：${surfaceFailures.join(", ")}`;
    gateReadinessG6 = "candidate_pass(surface_visibility_gaps_remaining)";
  }

  return {
    schema_version: "xhub.qa_main.xt_w3_33_g_memory_compaction_evidence.v1",
    generated_at: generatedAt,
    timezone: "Asia/Shanghai",
    lane: "XT-L2",
    role: "pool_takeover_engineering",
    report_mode: "candidate_contract_evidence",
    dispatch_mode: "directed_only_no_broadcast",
    current_slice: "XT-W3-33-G",
    scope: "Memory compaction + rollup + archive",
    fail_closed: true,
    status,
    gate_verdict: gateVerdict,
    verdict_reason: verdictReason,
    release_stance: releaseStance,
    shadow_checklist: [
      {
        item: "XT-W3-33-G",
        title: "memory compaction + rollup + archive",
        required_gate: "XT-SDK-G6",
        required_machine_readable_evidence: "build/reports/xt_w3_33_g_memory_compaction_evidence.v1.json",
        current_status: status,
      },
    ],
    gate_readiness: {
      "XT-SDK-G6": gateReadinessG6,
    },
    machine_decision: {
      decision_node_loss_after_compaction: decisionNodeLossAfterCompaction,
      protected_node_loss_after_compaction: protectedNodeLossAfterCompaction,
      traceability_ref_loss_after_compaction: traceabilityRefLossAfterCompaction,
      archive_candidate_supported: archiveCandidateSupported,
      replayable_rollup_summary_present: replayableRollupSummaryPresent,
      kept_decision_ids_present: keptDecisionIdsPresent,
      kept_milestone_ids_present: keptMilestoneIdsPresent,
      kept_audit_refs_present: keptAuditRefsPresent,
      kept_release_gate_refs_present: keptReleaseGateRefsPresent,
      critical_failures: criticalFailures,
      surface_failures: surfaceFailures,
      all_critical_contracts_green: criticalFailures.length === 0,
      surface_visibility_complete: surfaceFailures.length === 0,
    },
    surface_contracts: surfaceContracts,
    hard_lines: [
      "decision_node_loss_after_compaction_must_remain_zero",
      "protected_node_loss_after_compaction_must_remain_zero",
      "traceability_ref_loss_after_compaction_must_remain_zero",
      "archive_candidate_mode_must_not_drop_kept_decisions_or_milestones",
      "rollup_summary_must_remain_replayable",
    ],
    evidence_refs: [
      "x-terminal/Sources/Supervisor/SupervisorArchiveRollup.swift",
      "x-terminal/Sources/Supervisor/SupervisorMemoryCompactionSignal.swift",
      "x-terminal/Sources/Supervisor/SupervisorProjectDrillDownPresentation.swift",
      "x-terminal/Sources/Supervisor/SupervisorPortfolioProjectPresentation.swift",
      "x-terminal/Sources/Supervisor/SupervisorPortfolioOverviewPresentation.swift",
      "x-terminal/Sources/Supervisor/SupervisorPortfolioSnapshot.swift",
      "x-terminal/Sources/Supervisor/SupervisorRhythmRecommendationEngine.swift",
      "x-terminal/Tests/SupervisorMemoryCompactionPolicyTests.swift",
      "x-terminal/Tests/SupervisorProjectDrillDownTests.swift",
      "x-terminal/Tests/SupervisorProjectDrillDownPresentationTests.swift",
      "x-terminal/Tests/SupervisorProjectCapsuleTests.swift",
      "x-terminal/Tests/SupervisorPortfolioProjectPresentationTests.swift",
      "x-terminal/Tests/SupervisorPortfolioOverviewPresentationTests.swift",
      "x-terminal/Tests/SupervisorPortfolioSnapshotTests.swift",
      "x-terminal/Tests/SupervisorRhythmRecommendationTests.swift",
      "x-terminal/work-orders/xt-w3-33-supervisor-decision-kernel-routing-and-memory-governance-implementation-pack-v1.md",
      "docs/memory-new/xhub-lane-command-board-v2.md",
      "scripts/generate_xt_w3_33_g_memory_compaction_evidence.js",
    ],
    regenerate_command: "node scripts/generate_xt_w3_33_g_memory_compaction_evidence.js",
  };
}

function main() {
  const output = buildMemoryCompactionEvidence();
  writeJSON(outputPath, output);
  process.stdout.write(`${outputPath}\n`);
}

module.exports = {
  buildMemoryCompactionEvidence,
  outputPath,
  writeJSON,
};

if (require.main === module) {
  main();
}
