#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");

const {
  buildDecisionBlockerAssistEvidence,
} = require("./generate_xt_w3_33_f_decision_blocker_assist_evidence.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

run("XT-W3-33-F evidence defaults to candidate pass with proposal-first guards intact", () => {
  const report = buildDecisionBlockerAssistEvidence({
    generatedAt: "2026-03-21T12:00:00Z",
  });

  assert.equal(report.status, "candidate_pass_proposal_first_contract_and_tests_present");
  assert.equal(report.gate_verdict, "PASS(decision_blocker_assist_contract_and_guards_preserved)");
  assert.equal(report.release_stance, "candidate_go");
  assert.equal(report.gate_readiness["XT-SDK-G5"], "candidate_pass(proposal_first_contract_and_tests_present)");
  assert.equal(report.machine_decision.governed_default_category_count, 4);
  assert.equal(report.machine_decision.auto_adopt_never_self_approves, true);
  assert.equal(report.machine_decision.all_critical_contracts_green, true);
  assert.equal(report.machine_decision.surface_visibility_complete, true);
});

run("XT-W3-33-F evidence degrades to candidate pass when drill-down visibility is missing", () => {
  const report = buildDecisionBlockerAssistEvidence({
    drillDownSectionPresent: false,
  });

  assert.equal(report.status, "candidate_pass_surface_visibility_gaps_remaining");
  assert.equal(report.gate_verdict, "PASS(decision_blocker_assist_policy_preserved_with_surface_gaps)");
  assert.ok(report.machine_decision.surface_failures.includes("drill_down_section_present"));
  assert.equal(report.machine_decision.all_critical_contracts_green, true);
});

run("XT-W3-33-F evidence fails closed when proposal-first or fail-closed guards regress", () => {
  const report = buildDecisionBlockerAssistEvidence({
    proposalFirstPreserved: false,
    releaseScopeFailClosedPreserved: false,
    autoAdoptNeverSelfApproves: false,
  });

  assert.equal(report.status, "blocked_governance_regression_detected");
  assert.equal(report.gate_verdict, "NO_GO(decision_blocker_assist_governance_regression_detected)");
  assert.equal(report.release_stance, "no_go");
  assert.equal(report.gate_readiness["XT-SDK-G5"], "not_ready(decision_blocker_assist_governance_regression_detected)");
  assert.ok(report.machine_decision.critical_failures.includes("proposal_first_governance_must_hold"));
  assert.ok(report.machine_decision.critical_failures.includes("release_scope_decisions_must_fail_closed"));
  assert.ok(report.machine_decision.critical_failures.includes("assist_itself_must_not_mark_decision_approved"));
});
