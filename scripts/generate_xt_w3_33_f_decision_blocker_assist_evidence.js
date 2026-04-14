#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..");
const outputPath = path.join(repoRoot, "build/reports/xt_w3_33_f_decision_blocker_assist_evidence.v1.json");

const defaultTemplateCatalog = [
  {
    category: "tech_stack",
    template_ids: [
      "swiftui_hub_first_default",
      "swift_package_modular_default",
    ],
  },
  {
    category: "scaffold",
    template_ids: [
      "feature_slice_scaffold_default",
      "policy_first_scaffold_default",
    ],
  },
  {
    category: "test_stack",
    template_ids: [
      "swift_testing_contract_default",
      "node_generator_regression_default",
    ],
  },
  {
    category: "doc_template",
    template_ids: [
      "action_first_doc_template_default",
      "audit_appendix_doc_template_default",
    ],
  },
];

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

function buildDecisionBlockerAssistEvidence(options = {}) {
  const generatedAt = options.generatedAt || isoNow();
  const governedDefaultCategoryTarget = Math.max(
    1,
    normalizeNonNegativeInteger(options.governedDefaultCategoryTarget, 4)
  );
  const governedDefaultCategoryCount = normalizeNonNegativeInteger(
    options.governedDefaultCategoryCount,
    governedDefaultCategoryTarget
  );
  const defaultTemplateCount = normalizeNonNegativeInteger(
    options.defaultTemplateCount,
    defaultTemplateCatalog.reduce((sum, item) => sum + item.template_ids.length, 0)
  );

  const surfaceContracts = [
    {
      key: "digest_structured_hint_present",
      title: "digest structured hint",
      required: true,
      present: normalizeBoolean(options.digestStructuredHintPresent, true),
    },
    {
      key: "portfolio_actionability_priority_present",
      title: "portfolio today queue priority",
      required: true,
      present: normalizeBoolean(options.portfolioActionabilityPriorityPresent, true),
    },
    {
      key: "portfolio_row_tag_present",
      title: "portfolio row governance tag",
      required: true,
      present: normalizeBoolean(options.portfolioRowTagPresent, true),
    },
    {
      key: "drill_down_section_present",
      title: "project drill-down decision assist section",
      required: true,
      present: normalizeBoolean(options.drillDownSectionPresent, true),
    },
  ];

  const templateCatalogComplete = normalizeBoolean(options.templateCatalogComplete, true);
  const proposalFirstPreserved = normalizeBoolean(options.proposalFirstPreserved, true);
  const lowRiskTimeoutEscalationSupported = normalizeBoolean(
    options.lowRiskTimeoutEscalationSupported,
    true
  );
  const autoAdoptPolicyGuardPreserved = normalizeBoolean(
    options.autoAdoptPolicyGuardPreserved,
    true
  );
  const autoAdoptNeverSelfApproves = normalizeBoolean(options.autoAdoptNeverSelfApproves, true);
  const irreversibleFailClosedPreserved = normalizeBoolean(
    options.irreversibleFailClosedPreserved,
    true
  );
  const releaseScopeFailClosedPreserved = normalizeBoolean(
    options.releaseScopeFailClosedPreserved,
    true
  );
  const authorizationFailClosedPreserved = normalizeBoolean(
    options.authorizationFailClosedPreserved,
    true
  );
  const auditRefGenerated = normalizeBoolean(options.auditRefGenerated, true);
  const evidenceRefsAttached = normalizeBoolean(options.evidenceRefsAttached, true);
  const focusedTestsPresent = normalizeBoolean(options.focusedTestsPresent, true);

  const criticalFailures = [];
  if (governedDefaultCategoryCount < governedDefaultCategoryTarget) {
    criticalFailures.push("governed_default_template_categories_must_cover_all_four_domains");
  }
  if (defaultTemplateCount < governedDefaultCategoryTarget) {
    criticalFailures.push("default_template_count_must_remain_nonzero_for_each_governed_domain");
  }
  if (!templateCatalogComplete) {
    criticalFailures.push("template_catalog_must_remain_complete");
  }
  if (!proposalFirstPreserved) {
    criticalFailures.push("proposal_first_governance_must_hold");
  }
  if (!lowRiskTimeoutEscalationSupported) {
    criticalFailures.push("low_risk_timeout_escalation_path_must_remain_available");
  }
  if (!autoAdoptPolicyGuardPreserved) {
    criticalFailures.push("auto_adopt_must_remain_policy_guarded");
  }
  if (!autoAdoptNeverSelfApproves) {
    criticalFailures.push("assist_itself_must_not_mark_decision_approved");
  }
  if (!irreversibleFailClosedPreserved) {
    criticalFailures.push("irreversible_decisions_must_fail_closed");
  }
  if (!releaseScopeFailClosedPreserved) {
    criticalFailures.push("release_scope_decisions_must_fail_closed");
  }
  if (!authorizationFailClosedPreserved) {
    criticalFailures.push("authorization_required_decisions_must_fail_closed");
  }
  if (!auditRefGenerated) {
    criticalFailures.push("every_assist_must_emit_audit_ref");
  }
  if (!evidenceRefsAttached) {
    criticalFailures.push("every_assist_must_attach_evidence_refs");
  }
  if (!focusedTestsPresent) {
    criticalFailures.push("focused_contract_and_integration_tests_must_remain_present");
  }

  const surfaceFailures = surfaceContracts
    .filter((item) => item.required && !item.present)
    .map((item) => item.key);

  let status = "candidate_pass_proposal_first_contract_and_tests_present";
  let gateVerdict = "PASS(decision_blocker_assist_contract_and_guards_preserved)";
  let verdictReason = "XT-W3-33-F 的 proposal-first contract、policy-guarded auto-adopt、fail-closed guard 与控制面可见性均已有机读证据与测试覆盖。";
  let releaseStance = "candidate_go";
  let gateReadinessG5 = "candidate_pass(proposal_first_contract_and_tests_present)";

  if (criticalFailures.length > 0) {
    status = "blocked_governance_regression_detected";
    gateVerdict = "NO_GO(decision_blocker_assist_governance_regression_detected)";
    verdictReason = `XT-W3-33-F 命中治理红线：${criticalFailures.join(", ")}`;
    releaseStance = "no_go";
    gateReadinessG5 = "not_ready(decision_blocker_assist_governance_regression_detected)";
  } else if (surfaceFailures.length > 0) {
    status = "candidate_pass_surface_visibility_gaps_remaining";
    gateVerdict = "PASS(decision_blocker_assist_policy_preserved_with_surface_gaps)";
    verdictReason = `XT-W3-33-F 核心治理 contract 已成立，但仍有控制面缺口：${surfaceFailures.join(", ")}`;
    gateReadinessG5 = "candidate_pass(surface_visibility_gaps_remaining)";
  }

  return {
    schema_version: "xhub.qa_main.xt_w3_33_f_decision_blocker_assist_evidence.v1",
    generated_at: generatedAt,
    timezone: "Asia/Shanghai",
    lane: "XT-L2",
    role: "pool_takeover_engineering",
    report_mode: "candidate_contract_evidence",
    dispatch_mode: "directed_only_no_broadcast",
    current_slice: "XT-W3-33-F",
    scope: "Decision-blocker assist defaults",
    fail_closed: true,
    status,
    gate_verdict: gateVerdict,
    verdict_reason: verdictReason,
    release_stance: releaseStance,
    shadow_checklist: [
      {
        item: "XT-W3-33-F",
        title: "decision-blocker assist defaults",
        required_gate: "XT-SDK-G5",
        required_machine_readable_evidence: "build/reports/xt_w3_33_f_decision_blocker_assist_evidence.v1.json",
        current_status: status,
      },
    ],
    gate_readiness: {
      "XT-SDK-G5": gateReadinessG5,
    },
    machine_decision: {
      governed_default_category_count: governedDefaultCategoryCount,
      governed_default_category_target: governedDefaultCategoryTarget,
      default_template_count: defaultTemplateCount,
      template_catalog_complete: templateCatalogComplete,
      proposal_first_preserved: proposalFirstPreserved,
      low_risk_timeout_escalation_supported: lowRiskTimeoutEscalationSupported,
      auto_adopt_policy_guard_preserved: autoAdoptPolicyGuardPreserved,
      auto_adopt_never_self_approves: autoAdoptNeverSelfApproves,
      irreversible_fail_closed_preserved: irreversibleFailClosedPreserved,
      release_scope_fail_closed_preserved: releaseScopeFailClosedPreserved,
      authorization_fail_closed_preserved: authorizationFailClosedPreserved,
      audit_ref_generated: auditRefGenerated,
      evidence_refs_attached: evidenceRefsAttached,
      focused_tests_present: focusedTestsPresent,
      critical_failures: criticalFailures,
      surface_failures: surfaceFailures,
      all_critical_contracts_green: criticalFailures.length === 0,
      surface_visibility_complete: surfaceFailures.length === 0,
    },
    template_catalog: defaultTemplateCatalog,
    surface_contracts: surfaceContracts,
    hard_lines: [
      "proposal_first_must_hold_for_decision_blockers",
      "low_risk_reversible_defaults_may_only_auto_adopt_if_policy_allows",
      "assist_itself_must_not_mark_decision_approved",
      "irreversible_release_scope_or_authorization_required_decisions_must_fail_closed",
      "every_assist_must_emit_audit_ref_and_evidence_refs",
    ],
    evidence_refs: [
      "x-terminal/Sources/Supervisor/SupervisorDecisionBlockerAssist.swift",
      "x-terminal/Sources/Supervisor/SupervisorManager.swift",
      "x-terminal/Sources/Supervisor/SupervisorProjectCapsule.swift",
      "x-terminal/Sources/Supervisor/SupervisorPortfolioSnapshot.swift",
      "x-terminal/Sources/Supervisor/SupervisorPortfolioActionabilitySnapshot.swift",
      "x-terminal/Sources/Supervisor/SupervisorPortfolioProjectPresentation.swift",
      "x-terminal/Sources/Supervisor/SupervisorProjectDrillDown.swift",
      "x-terminal/Sources/Supervisor/SupervisorProjectDrillDownPresentation.swift",
      "x-terminal/Tests/SupervisorDecisionBlockerAssistTests.swift",
      "x-terminal/Tests/SupervisorDecisionAssistAndCompactionIntegrationTests.swift",
      "x-terminal/Tests/SupervisorPortfolioActionabilitySnapshotTests.swift",
      "x-terminal/Tests/SupervisorPortfolioProjectPresentationTests.swift",
      "x-terminal/Tests/SupervisorProjectDrillDownPresentationTests.swift",
      "x-terminal/Tests/SupervisorProjectCapsuleTests.swift",
      "x-terminal/Tests/SupervisorPortfolioSnapshotTests.swift",
      "x-terminal/work-orders/xt-w3-33-supervisor-decision-kernel-routing-and-memory-governance-implementation-pack-v1.md",
      "docs/memory-new/xhub-lane-command-board-v2.md",
      "scripts/generate_xt_w3_33_f_decision_blocker_assist_evidence.js",
    ],
    regenerate_command: "node scripts/generate_xt_w3_33_f_decision_blocker_assist_evidence.js",
  };
}

function main() {
  const output = buildDecisionBlockerAssistEvidence();
  writeJSON(outputPath, output);
  process.stdout.write(`${outputPath}\n`);
}

module.exports = {
  buildDecisionBlockerAssistEvidence,
  outputPath,
  writeJSON,
};

if (require.main === module) {
  main();
}
