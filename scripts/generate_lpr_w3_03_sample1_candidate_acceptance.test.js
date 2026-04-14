#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");

const {
  buildAcceptanceReport,
} = require("./generate_lpr_w3_03_sample1_candidate_acceptance.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

run("sample1 acceptance report exposes hard reject signals and current no-go example", () => {
  const report = buildAcceptanceReport({
    focusSample: {
      sample_id: "lpr_rr_01_embedding_real_model_dir_executes",
      what_to_capture: ["真实输入文本工件", "runtime monitor / diagnostics export"],
      machine_readable_fields_to_record: ["provider", "task_kind", "model_path"],
      required_checks: [{ field: "provider", equals: "transformers" }],
    },
    shortlist: {
      runtime_resolution: {
        runtime_ready: true,
      },
      summary: {
        search_outcome: "searched_no_pass_candidate",
        candidates_considered: 1,
        filtered_out_task_mismatch_count: 2,
        top_recommended_action: {
          action_id: "source_or_import_different_native_embedding_model_dir",
          action_summary: "Need a different dir.",
          next_step: "source_native_dir",
        },
      },
      candidates: [
        {
          normalized_model_dir: "/models/quantized-embed",
          candidate_validation: {
            gate_verdict: "NO_GO(sample1_candidate_validation_failed_closed)",
            task_kind_status: "confirmed_by_local_metadata",
            inferred_task_hint: "embedding",
            loadability_verdict: "partially_loadable_metadata_only",
            loadability_blocker: "unsupported_quantization_config",
            task_hint_sources: ["catalog_task_kind:embedding"],
          },
        },
      ],
      filtered_out_task_mismatch: [
        {
          normalized_model_dir: "/models/text-model",
          candidate_validation: {
            task_kind_status: "mismatch",
            inferred_task_hint: "text_generate",
          },
        },
      ],
    },
    handoff: {
      handoff_state: "blocked",
      blocker_class: "current_embedding_dirs_incompatible_with_native_transformers_load",
      native_execution_contract: {
        provider: "transformers",
        task_kind: "embedding",
        must_pass: ["AutoConfig", "AutoTokenizer", "AutoModel"],
        reject_if: ["helper_only"],
      },
    },
  });

  assert.equal(report.current_machine_state.runtime_ready, true);
  assert.equal(report.current_machine_state.blocker_class, "current_embedding_dirs_incompatible_with_native_transformers_load");
  assert.equal(report.current_no_go_example.loadability_blocker, "unsupported_quantization_config");
  assert.ok(report.acceptance_contract.reject_signals.some((item) => item.signal.includes("unsupported_quantization_config")));
  assert.equal(report.filtered_out_examples.length, 1);
  assert.ok(
    report.operator_workflow.some((item) =>
      String(item.command || "").includes("generate_lpr_w3_03_sample1_candidate_registration_packet.js")
    )
  );
  assert.ok(
    report.operator_workflow.some((item) =>
      String(item.command || "").includes("generate_lpr_w3_03_sample1_candidate_catalog_patch_plan.js")
    )
  );
  assert.ok(
    report.operator_workflow.some((item) =>
      String(item.command || "").includes("--wide-common-user-roots")
    )
  );
});
