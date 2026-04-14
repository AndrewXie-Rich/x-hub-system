#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const cp = require("node:child_process");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

run("generate_lpr_w3_03_sample1_operator_handoff writes a handoff artifact", () => {
  const reportsDir = fs.mkdtempSync(path.join(os.tmpdir(), "xhub-lpr-handoff-"));
  try {
    fs.writeFileSync(
      path.join(reportsDir, "lpr_w3_03_sample1_candidate_shortlist.v1.json"),
      `${JSON.stringify({
        scan_roots: [
          { path: "/models", present: true },
          { path: "/Users/demo/Downloads", present: true },
        ],
      }, null, 2)}\n`,
      "utf8"
    );
    fs.writeFileSync(
      path.join(reportsDir, "lpr_w3_03_sample1_candidate_shortlist.wide_scan.v1.json"),
      `${JSON.stringify({
        scan_profile: "default_roots_plus_common_user_roots",
        scan_roots: [
          { path: "/models", present: true },
          { path: "/Users/demo/Downloads", present: true },
          { path: "/Users/demo/Desktop", present: true },
        ],
      }, null, 2)}\n`,
      "utf8"
    );
    fs.writeFileSync(
      path.join(reportsDir, "lpr_w3_03_sample1_helper_local_service_recovery.v1.json"),
      `${JSON.stringify({
        top_recommended_action: {
          action_id: "enable_lm_studio_local_service",
          action_summary: "Turn local service on first.",
          next_step: "turn_on_local_service_then_rerun_helper_probe",
        },
        helper_route_contract: {
          helper_route_ready_verdict:
            "NO_GO(helper_bridge_not_ready_for_secondary_reference_route)",
        },
      }, null, 2)}\n`,
      "utf8"
    );
    fs.writeFileSync(
      path.join(reportsDir, "lpr_w3_03_sample1_candidate_acceptance.v1.json"),
      `${JSON.stringify({
        acceptance_contract: {
          required_gate_verdict: "PASS(sample1_candidate_native_loadable_for_real_execution)",
          required_loadability_verdict: "native_loadable",
        },
      }, null, 2)}\n`,
      "utf8"
    );
    fs.writeFileSync(
      path.join(reportsDir, "lpr_w3_03_sample1_candidate_registration_packet.v1.json"),
      `${JSON.stringify({
        requested_model_path: "/models/qwen-embed",
        normalized_model_dir: "/models/qwen-embed",
        candidate_validation: {
          gate_verdict: "NO_GO(sample1_candidate_validation_failed_closed)",
          loadability_blocker: "unsupported_quantization_config",
        },
        search_recovery_plan: {
          exact_path_known: true,
          exact_path_exists: true,
          exact_path_shortlist_refresh_command:
            "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js \\\n  --task-kind embedding \\\n  --model-path /models/qwen-embed",
          exact_path_validation_command:
            "node scripts/generate_lpr_w3_03_sample1_candidate_validation.js \\\n  --model-path /models/qwen-embed \\\n  --task-kind embedding",
          explicit_model_path_shortlist_command_template:
            "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js \\\n  --task-kind embedding \\\n  --model-path <absolute_model_dir>",
          explicit_model_path_validation_command_template:
            "node scripts/generate_lpr_w3_03_sample1_candidate_validation.js \\\n  --model-path <absolute_model_dir> \\\n  --task-kind embedding",
          wide_shortlist_search_command:
            "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js \\\n  --task-kind embedding \\\n  --wide-common-user-roots",
          custom_scan_root_shortlist_command_template:
            "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js \\\n  --task-kind embedding \\\n  --scan-root <absolute_search_root>",
          preferred_next_step: "refresh_or_widen_machine_readable_search_then_revalidate_exact_path",
        },
        proposed_catalog_entry_payload: {
          id: "hf-embed-qwen",
          backend: "transformers",
          modelPath: "/models/qwen-embed",
          taskKinds: ["embedding"],
        },
        catalog_patch_plan_summary: {
          artifact_ref: "build/reports/lpr_w3_03_sample1_candidate_catalog_patch_plan.v1.json",
          manual_patch_scope:
            "choose_one_target_runtime_base_and_keep_models_catalog_and_models_state_in_sync",
          manual_patch_allowed_now: false,
          blocked_reason: "validator_not_pass",
          eligible_target_base_count: 0,
          blocked_target_base_count: 1,
          target_base_plans: [
            {
              base_dir: "/catalog",
              base_label: "custom_runtime_base",
              patch_allowed_now: false,
              blocked_reasons: ["validator_not_pass"],
              recommended_action: "do_not_patch_base_until_validator_pass",
              files: [
                {
                  catalog_path: "/catalog/models_catalog.json",
                  file_kind: "models_catalog",
                  shape_family: "legacy_minimal",
                  target_eligible_now: false,
                  blocked_reason: "validator_not_pass",
                  model_patch_operation: "blocked_until_validator_pass",
                },
              ],
            },
          ],
        },
        machine_decision: {
          catalog_write_allowed_now: false,
        },
      }, null, 2)}\n`,
      "utf8"
    );
    const outputPath = path.join(reportsDir, "custom_handoff.json");
    const result = cp.spawnSync(
      process.execPath,
      [
        path.join(__dirname, "generate_lpr_w3_03_sample1_operator_handoff.js"),
        "--out-json",
        outputPath,
      ],
      {
        cwd: path.join(__dirname, ".."),
        env: {
          ...process.env,
          LPR_W3_03_REQUIRE_REAL_REPORTS_DIR: reportsDir,
        },
        encoding: "utf8",
      }
    );

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(fs.existsSync(outputPath), true);
    const payload = JSON.parse(fs.readFileSync(outputPath, "utf8"));
    assert.equal(payload.schema_version, "xhub.lpr_w3_03_sample1_operator_handoff.v1");
    assert.equal(payload.sample_id, "lpr_rr_01_embedding_real_model_dir_executes");
    assert.equal(
      payload.candidate_acceptance.acceptance_contract.required_gate_verdict,
      "PASS(sample1_candidate_native_loadable_for_real_execution)"
    );
    assert.equal(
      payload.candidate_registration.machine_decision.catalog_write_allowed_now,
      false
    );
    assert.equal(
      payload.candidate_registration.catalog_patch_plan_summary.blocked_reason,
      "validator_not_pass"
    );
    assert.equal(payload.search_recovery.exact_path_known, true);
    assert.equal(
      payload.search_recovery.wide_shortlist_search_command.includes("--wide-common-user-roots"),
      true
    );
    assert.equal(
      payload.candidate_registration.search_recovery_plan.exact_path_validation_command.includes("--model-path /models/qwen-embed"),
      true
    );
    assert.equal(
      payload.helper_local_service_recovery.top_recommended_action.action_id,
      "enable_lm_studio_local_service"
    );
    assert.deepEqual(payload.checked_sources.scan_roots, [
      { path: "/models", present: true },
      { path: "/Users/demo/Downloads", present: true },
      { path: "/Users/demo/Desktop", present: true },
    ]);
  } finally {
    fs.rmSync(reportsDir, { recursive: true, force: true });
  }
});
