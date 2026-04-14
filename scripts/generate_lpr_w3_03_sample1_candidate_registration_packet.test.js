#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const cp = require("node:child_process");

const {
  buildProposedCatalogEntry,
  buildRegistrationPacket,
  buildTargetCatalogPaths,
} = require("./generate_lpr_w3_03_sample1_candidate_registration_packet.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

run("sample1 candidate registration packet stays fail-closed until exact-path validation passes", () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "xhub-lpr-registration-unit-"));
  try {
    const modelDir = path.join(tempDir, "quantized-embed");
    fs.mkdirSync(modelDir, { recursive: true });
    const catalogPath = path.join(tempDir, "models_catalog.json");
    fs.writeFileSync(
      catalogPath,
      `${JSON.stringify({
        models: [
          {
            id: "hf-embed-qwen",
            name: "Qwen Embed",
            backend: "transformers",
            modelPath: modelDir,
            taskKinds: ["embedding"],
          },
        ],
      }, null, 2)}\n`,
      "utf8"
    );

    const proposedCatalogEntry = buildProposedCatalogEntry({
      normalizedModelDir: modelDir,
      taskKind: "embedding",
      backend: "transformers",
      existingCatalogRefs: [
        {
          catalog_path: catalogPath,
          model_id: "hf-embed-qwen",
          model_name: "Qwen Embed",
          backend: "transformers",
          task_kinds: ["embedding"],
          model_path: modelDir,
          model_dir: modelDir,
        },
      ],
    });

    const targetCatalogPaths = buildTargetCatalogPaths({
      catalogPaths: [catalogPath],
      normalizedModelDir: modelDir,
      proposedModelEntry: proposedCatalogEntry,
      validationReport: {
        machine_decision: {
          gate_verdict: "NO_GO(sample1_candidate_validation_failed_closed)",
        },
      },
    });

    const packet = buildRegistrationPacket({
      requestedModelPath: modelDir,
      normalizedModelDir: modelDir,
      expectedTaskKind: "embedding",
      validationReport: {
        machine_decision: {
          gate_verdict: "NO_GO(sample1_candidate_validation_failed_closed)",
          candidate_usable_for_sample1: false,
          top_recommended_action: {
            action_id: "source_different_native_embedding_model_dir",
            action_summary: "This dir is not sample1-ready.",
            next_step: "source_native_dir",
          },
        },
        runtime_resolution: {
          runtime_ready: true,
        },
        candidate_checks: {
          requested_path_exists: true,
          model_dir_looks_like_model: true,
          task_kind_status: "confirmed_by_local_metadata",
          inferred_task_hint: "embedding",
        },
        loadability: {
          verdict: "partially_loadable_metadata_only",
          blocker_reason: "unsupported_quantization_config",
        },
      },
      proposedCatalogEntry,
      targetCatalogPaths,
      existingCatalogRefs: [
        {
          catalog_path: catalogPath,
          model_id: "hf-embed-qwen",
          model_name: "Qwen Embed",
          backend: "transformers",
          task_kinds: ["embedding"],
          model_path: modelDir,
        },
      ],
      acceptanceContract: {
        required_gate_verdict: "PASS(sample1_candidate_native_loadable_for_real_execution)",
        required_loadability_verdict: "native_loadable",
        expected_task_kind: "embedding",
        expected_provider: "transformers",
      },
      artifactRefs: {
        candidate_validation_report: "build/reports/validation.json",
      },
    });

    assert.equal(packet.machine_decision.catalog_write_allowed_now, false);
    assert.equal(packet.machine_decision.already_registered_in_catalog, true);
    assert.equal(packet.candidate_validation.loadability_blocker, "unsupported_quantization_config");
    assert.equal(packet.target_catalog_paths[0].recommended_action, "existing_entry_still_requires_validator_pass");
    assert.equal(packet.proposed_catalog_entry_payload.id, "hf-embed-qwen");
    assert.equal(
      packet.search_recovery_plan.exact_path_shortlist_refresh_command.includes(`--model-path ${modelDir}`),
      true
    );
    assert.equal(
      packet.search_recovery_plan.wide_shortlist_search_command.includes("--wide-common-user-roots"),
      true
    );
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
});

run("sample1 candidate registration packet becomes ready after PASS and surfaces manual catalog append", () => {
  const proposedCatalogEntry = buildProposedCatalogEntry({
    normalizedModelDir: "/models/native-embed",
    taskKind: "embedding",
    backend: "transformers",
    requestedModelId: "hf-embed-native",
    requestedModelName: "Native Embed",
  });

  const packet = buildRegistrationPacket({
    requestedModelPath: "/models/native-embed",
    normalizedModelDir: "/models/native-embed",
    expectedTaskKind: "embedding",
    validationReport: {
      machine_decision: {
        gate_verdict: "PASS(sample1_candidate_native_loadable_for_real_execution)",
        candidate_usable_for_sample1: true,
        top_recommended_action: {
          action_id: "use_candidate_for_sample1_real_run",
          action_summary: "Use this exact candidate.",
          next_step: "prepare_and_execute_sample1_real_run",
        },
      },
      runtime_resolution: {
        runtime_ready: true,
      },
      candidate_checks: {
        requested_path_exists: true,
        model_dir_looks_like_model: true,
        task_kind_status: "confirmed_by_local_metadata",
        inferred_task_hint: "embedding",
      },
      loadability: {
        verdict: "native_loadable",
        blocker_reason: "",
      },
    },
    proposedCatalogEntry,
    targetCatalogPaths: [
      {
        catalog_path: "/catalog/models_catalog.json",
        present: true,
        exact_model_dir_registered: false,
        proposed_model_id_conflict: false,
        catalog_write_allowed_now: true,
        recommended_action: "manual_append_proposed_entry_after_validator_pass",
      },
    ],
    existingCatalogRefs: [],
    acceptanceContract: {
      required_gate_verdict: "PASS(sample1_candidate_native_loadable_for_real_execution)",
      required_loadability_verdict: "native_loadable",
      expected_task_kind: "embedding",
      expected_provider: "transformers",
    },
    catalogPatchPlanSummary: {
      artifact_ref: "build/reports/patch-plan.json",
      manual_patch_scope:
        "choose_one_target_runtime_base_and_keep_models_catalog_and_models_state_in_sync",
      manual_patch_allowed_now: true,
      blocked_reason: "",
      eligible_target_base_count: 1,
      blocked_target_base_count: 0,
      target_base_plans: [
        {
          base_dir: "/catalog",
          base_label: "custom_runtime_base",
          patch_allowed_now: true,
          blocked_reasons: [],
          recommended_action: "patch_catalog_and_state_as_pair_after_validator_pass",
          files: [
            {
              catalog_path: "/catalog/models_catalog.json",
              file_kind: "models_catalog",
              shape_family: "legacy_minimal",
              target_eligible_now: true,
              blocked_reason: "",
              model_patch_operation: "append_new_entry",
            },
          ],
        },
      ],
    },
    focusSample: {
      sample_id: "lpr_rr_01_embedding_real_model_dir_executes",
    },
  });

  assert.equal(packet.machine_decision.catalog_write_allowed_now, true);
  assert.equal(packet.machine_decision.catalog_patch_plan_required_before_manual_write, true);
  assert.equal(packet.machine_decision.top_recommended_action.action_id, "append_proposed_catalog_entry_after_validator_pass");
  assert.equal(packet.proposed_catalog_entry_payload.id, "hf-embed-native");
  assert.equal(packet.catalog_patch_plan_summary.manual_patch_allowed_now, true);
  assert.equal(
    packet.search_recovery_plan.explicit_model_path_validation_command_template.includes(
      "--model-path <absolute_model_dir>"
    ),
    true
  );
  assert.ok(packet.operator_workflow.some((row) => row.step_id === "manual_catalog_write_after_pass" && row.allowed_now === true));
  assert.ok(
    packet.command_refs.some((item) =>
      String(item || "").includes("generate_lpr_w3_03_sample1_candidate_catalog_patch_plan.js")
    )
  );
  assert.ok(
    packet.command_refs.some((item) =>
      String(item || "").includes("--wide-common-user-roots")
    )
  );
});

run("generate_lpr_w3_03_sample1_candidate_registration_packet writes a fail-closed artifact for a missing path", () => {
  const reportsDir = fs.mkdtempSync(path.join(os.tmpdir(), "xhub-lpr-registration-"));
  try {
    const outputPath = path.join(reportsDir, "custom_registration.json");
    const result = cp.spawnSync(
      process.execPath,
      [
        path.join(__dirname, "generate_lpr_w3_03_sample1_candidate_registration_packet.js"),
        "--model-path",
        "/definitely/missing/model-dir",
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
    assert.equal(payload.schema_version, "xhub.lpr_w3_03_sample1_candidate_registration_packet.v1");
    assert.equal(payload.machine_decision.catalog_write_allowed_now, false);
    assert.equal(payload.machine_decision.catalog_patch_plan_required_before_manual_write, true);
    assert.equal(payload.requested_model_path, "/definitely/missing/model-dir");
    assert.equal(payload.catalog_patch_plan_summary.manual_patch_allowed_now, false);
    assert.equal(Boolean(payload.catalog_patch_plan_summary.artifact_ref), true);
    assert.equal(payload.search_recovery_plan.exact_path_exists, false);
    assert.equal(
      payload.search_recovery_plan.custom_scan_root_shortlist_command_template.includes("--scan-root <absolute_search_root>"),
      true
    );
    const patchPlanPath = path.isAbsolute(payload.catalog_patch_plan_summary.artifact_ref)
      ? payload.catalog_patch_plan_summary.artifact_ref
      : path.join(path.dirname(outputPath), payload.catalog_patch_plan_summary.artifact_ref);
    assert.equal(fs.existsSync(patchPlanPath), true);
  } finally {
    fs.rmSync(reportsDir, { recursive: true, force: true });
  }
});
