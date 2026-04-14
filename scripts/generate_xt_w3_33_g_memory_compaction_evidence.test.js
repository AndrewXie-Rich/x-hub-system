#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");

const {
  buildMemoryCompactionEvidence,
} = require("./generate_xt_w3_33_g_memory_compaction_evidence.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

run("XT-W3-33-G evidence defaults to candidate pass with zero-loss invariants", () => {
  const report = buildMemoryCompactionEvidence({
    generatedAt: "2026-03-21T10:00:00Z",
  });

  assert.equal(report.status, "candidate_pass_traceability_contract_and_tests_present");
  assert.equal(report.gate_verdict, "PASS(memory_compaction_contract_and_traceability_preserved)");
  assert.equal(report.release_stance, "candidate_go");
  assert.equal(report.gate_readiness["XT-SDK-G6"], "candidate_pass(compaction_traceability_contract_and_tests_present)");
  assert.equal(report.machine_decision.decision_node_loss_after_compaction, 0);
  assert.equal(report.machine_decision.traceability_ref_loss_after_compaction, 0);
  assert.equal(report.machine_decision.surface_visibility_complete, true);
  assert.equal(report.machine_decision.all_critical_contracts_green, true);
});

run("XT-W3-33-G evidence degrades to candidate pass with surface gaps when close-out queue is missing", () => {
  const report = buildMemoryCompactionEvidence({
    closeOutQueuePresent: false,
  });

  assert.equal(report.status, "candidate_pass_surface_visibility_gaps_remaining");
  assert.equal(report.gate_verdict, "PASS(memory_compaction_traceability_preserved_with_surface_gaps)");
  assert.ok(report.machine_decision.surface_failures.includes("close_out_queue_present"));
  assert.equal(report.machine_decision.all_critical_contracts_green, true);
});

run("XT-W3-33-G evidence fails closed when decision or traceability loss is detected", () => {
  const report = buildMemoryCompactionEvidence({
    decisionNodeLossAfterCompaction: 1,
    traceabilityRefLossAfterCompaction: 2,
  });

  assert.equal(report.status, "blocked_traceability_regression_detected");
  assert.equal(report.gate_verdict, "NO_GO(compaction_traceability_regression_detected)");
  assert.equal(report.release_stance, "no_go");
  assert.equal(report.gate_readiness["XT-SDK-G6"], "not_ready(compaction_traceability_regression_detected)");
  assert.ok(report.machine_decision.critical_failures.includes("decision_node_loss_after_compaction_must_remain_zero"));
  assert.ok(report.machine_decision.critical_failures.includes("traceability_ref_loss_after_compaction_must_remain_zero"));
  assert.equal(report.machine_decision.all_critical_contracts_green, false);
});
