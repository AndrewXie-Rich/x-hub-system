#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const cp = require("node:child_process");

const {
  buildCatalogPatchPlan,
} = require("./generate_lpr_w3_03_sample1_candidate_catalog_patch_plan.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

function writeJSON(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

run("catalog patch plan stays fail-closed until validator PASS and groups files by runtime base", () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "xhub-catalog-plan-unit-"));
  try {
    const baseDir = path.join(tempDir, "RELFlowHub");
    const catalogPath = path.join(baseDir, "models_catalog.json");
    const statePath = path.join(baseDir, "models_state.json");
    writeJSON(catalogPath, {
      updatedAt: 1,
      models: [
        {
          id: "mlx-chat",
          name: "MLX Chat",
          backend: "mlx",
          modelPath: "/models/mlx-chat",
          note: "catalog",
        },
      ],
    });
    writeJSON(statePath, {
      updatedAt: 1,
      models: [
        {
          id: "mlx-chat",
          name: "MLX Chat",
          backend: "mlx",
          modelPath: "/models/mlx-chat",
          state: "available",
          taskKinds: ["text_generate"],
          inputModalities: ["text"],
          outputModalities: ["text"],
        },
      ],
    });

    const plan = buildCatalogPatchPlan({
      registrationPacket: {
        requested_model_path: "/models/quantized-embed",
        normalized_model_dir: "/models/quantized-embed",
        acceptance_contract: {
          expected_provider: "transformers",
          expected_task_kind: "embedding",
          required_gate_verdict: "PASS(sample1_candidate_native_loadable_for_real_execution)",
          required_loadability_verdict: "native_loadable",
        },
        candidate_validation: {
          gate_verdict: "NO_GO(sample1_candidate_validation_failed_closed)",
          loadability_blocker: "unsupported_quantization_config",
        },
        proposed_catalog_entry_payload: {
          id: "hf-embed-qwen",
          name: "Qwen Embed",
          backend: "transformers",
          runtimeProviderId: "transformers",
          modelPath: "/models/quantized-embed",
          taskKinds: ["embedding"],
          inputModalities: ["text"],
          outputModalities: ["embedding"],
          modelFormat: "huggingface",
        },
        machine_decision: {
          top_recommended_action: {
            action_id: "source_different_native_embedding_model_dir",
          },
        },
        target_catalog_paths: [
          { catalog_path: catalogPath },
          { catalog_path: statePath },
        ],
      },
      sourceRegistrationPacketRef: "build/reports/lpr_w3_03_sample1_candidate_registration_packet.v1.json",
    });

    assert.equal(plan.machine_decision.manual_patch_allowed_now, false);
    assert.equal(plan.machine_decision.blocked_reason, "validator_not_pass");
    assert.equal(plan.target_base_plans.length, 1);
    assert.equal(plan.target_base_plans[0].patch_allowed_now, false);
    assert.equal(plan.target_base_plans[0].files.length, 2);
    assert.equal(plan.target_base_plans[0].files[0].root_patch_plan[0].path, "updatedAt");
    assert.equal(
      plan.target_base_plans[0].files[0].model_patch_plan.operation,
      "blocked_until_validator_pass"
    );
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
});

run("catalog patch plan surfaces pair-safe append plan after PASS", () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "xhub-catalog-plan-pass-"));
  try {
    const baseDir = path.join(
      tempDir,
      "Library",
      "Containers",
      "com.rel.flowhub",
      "Data",
      "RELFlowHub"
    );
    const catalogPath = path.join(baseDir, "models_catalog.json");
    const statePath = path.join(baseDir, "models_state.json");
    writeJSON(catalogPath, {
      updatedAt: 1,
      models: [
        {
          id: "mlx-chat",
          name: "MLX Chat",
          backend: "mlx",
          modelPath: "/models/mlx-chat",
          trustProfile: {
            allowRemoteExport: false,
            allowSecretInput: false,
          },
          roles: ["general"],
          inputModalities: ["text"],
          processorRequirements: {
            tokenizerRequired: true,
            processorRequired: false,
            featureExtractorRequired: false,
          },
          taskKinds: ["text_generate"],
          note: "managed_copy",
          modelFormat: "mlx",
          outputModalities: ["text"],
          offlineReady: true,
        },
      ],
    });
    writeJSON(statePath, {
      updatedAt: 1,
      models: [
        {
          id: "mlx-chat",
          name: "MLX Chat",
          backend: "mlx",
          modelPath: "/models/mlx-chat",
          trustProfile: {
            allowRemoteExport: false,
            allowSecretInput: false,
          },
          roles: ["general"],
          inputModalities: ["text"],
          processorRequirements: {
            tokenizerRequired: true,
            processorRequired: false,
            featureExtractorRequired: false,
          },
          taskKinds: ["text_generate"],
          note: "managed_copy",
          modelFormat: "mlx",
          outputModalities: ["text"],
          offlineReady: true,
          state: "available",
        },
      ],
    });

    const plan = buildCatalogPatchPlan({
      registrationPacket: {
        requested_model_path: "/models/native-embed",
        normalized_model_dir: "/models/native-embed",
        acceptance_contract: {
          expected_provider: "transformers",
          expected_task_kind: "embedding",
        },
        candidate_validation: {
          gate_verdict: "PASS(sample1_candidate_native_loadable_for_real_execution)",
          loadability_blocker: "",
        },
        proposed_catalog_entry_payload: {
          id: "hf-embed-native",
          name: "Native Embed",
          backend: "transformers",
          runtimeProviderId: "transformers",
          modelPath: "/models/native-embed",
          taskKinds: ["embedding"],
          inputModalities: ["text"],
          outputModalities: ["embedding"],
          modelFormat: "huggingface",
        },
        target_catalog_paths: [
          { catalog_path: catalogPath },
          { catalog_path: statePath },
        ],
      },
    });

    assert.equal(plan.machine_decision.manual_patch_allowed_now, true);
    assert.equal(plan.machine_decision.eligible_target_base_count, 1);
    assert.equal(plan.target_base_plans[0].patch_allowed_now, true);
    assert.equal(
      plan.target_base_plans[0].recommended_action,
      "patch_catalog_and_state_as_pair_after_validator_pass"
    );
    const catalogPlan = plan.target_base_plans[0].files.find((item) => item.file_kind === "models_catalog");
    const statePlan = plan.target_base_plans[0].files.find((item) => item.file_kind === "models_state");
    assert.equal(catalogPlan.target_eligible_now, true);
    assert.equal(catalogPlan.shape_family, "managed_enriched");
    assert.deepEqual(catalogPlan.payload_preview.shape_preserving_payload.taskKinds, ["embedding"]);
    assert.equal(statePlan.model_patch_plan.operation, "append_new_entry");
    assert.equal(statePlan.payload_preview.runtime_safe_minimum_payload.state, "available");
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
});

run("catalog patch plan CLI reads a registration packet and writes a report", () => {
  const reportsDir = fs.mkdtempSync(path.join(os.tmpdir(), "xhub-catalog-plan-cli-"));
  try {
    const registrationPath = path.join(reportsDir, "registration.json");
    const outPath = path.join(reportsDir, "catalog_patch_plan.json");
    writeJSON(registrationPath, {
      requested_model_path: "/models/native-embed",
      normalized_model_dir: "/models/native-embed",
      candidate_validation: {
        gate_verdict: "NO_GO(sample1_candidate_validation_failed_closed)",
      },
      proposed_catalog_entry_payload: {
        id: "hf-embed-native",
        name: "Native Embed",
        backend: "transformers",
        runtimeProviderId: "transformers",
        modelPath: "/models/native-embed",
        taskKinds: ["embedding"],
        inputModalities: ["text"],
        outputModalities: ["embedding"],
        modelFormat: "huggingface",
      },
      target_catalog_paths: [],
    });

    const result = cp.spawnSync(
      process.execPath,
      [
        path.join(__dirname, "generate_lpr_w3_03_sample1_candidate_catalog_patch_plan.js"),
        "--registration-json",
        registrationPath,
        "--out-json",
        outPath,
      ],
      {
        cwd: path.join(__dirname, ".."),
        encoding: "utf8",
      }
    );

    assert.equal(result.status, 0, result.stderr || result.stdout);
    const payload = JSON.parse(fs.readFileSync(outPath, "utf8"));
    assert.equal(payload.schema_version, "xhub.lpr_w3_03_sample1_candidate_catalog_patch_plan.v1");
    assert.equal(payload.machine_decision.manual_patch_allowed_now, false);
    assert.equal(payload.source_registration_packet_ref, registrationPath);
  } finally {
    fs.rmSync(reportsDir, { recursive: true, force: true });
  }
});
