#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");

const {
  buildSample1CandidateValidationReport,
} = require("./generate_lpr_w3_03_sample1_candidate_validation.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

run("sample1 candidate validation passes when a candidate is native-loadable and task kind matches", () => {
  const report = buildSample1CandidateValidationReport({
    generatedAt: "2026-03-23T02:00:00Z",
    requestedModelPath: "/models/native-embed",
    normalizedModelDir: "/models/native-embed",
    expectedTaskKind: "embedding",
    requestedPathExists: true,
    normalizedDirExists: true,
    modelDirLooksLikeModel: true,
    runtimeSelection: {
      best: {
        candidate: {
          runtime_id: "lmstudio_cpython311_combo_transformers",
          label: "LM Studio combo runtime",
          command: "/python3",
        },
      },
      probes: [{ ready: true }],
    },
    staticMarkers: {
      format_assessment: {
        task_hint: "embedding",
        task_hint_sources: ["path_name:native-embed"],
      },
    },
    loadability: {
      verdict: "native_loadable",
      blocker_reason: "",
      reasons: [],
      auto_config_ok: true,
      auto_tokenizer_ok: true,
      auto_model_ok: true,
      auto_model_for_causal_lm_ok: false,
    },
    artifactRefs: {
      native_loadability_meta: "build/reports/meta.json",
    },
  });

  assert.equal(
    report.machine_decision.gate_verdict,
    "PASS(sample1_candidate_native_loadable_for_real_execution)"
  );
  assert.equal(report.machine_decision.candidate_usable_for_sample1, true);
  assert.equal(report.candidate_checks.task_kind_status, "confirmed_by_local_metadata");
  assert.equal(report.machine_decision.top_recommended_action.action_id, "use_candidate_for_sample1_real_run");
  assert.equal(
    report.search_recovery.exact_path_shortlist_refresh_command.includes("--model-path /models/native-embed"),
    true
  );
});

run("sample1 candidate validation fails closed on task kind mismatch even if loadability looks good", () => {
  const report = buildSample1CandidateValidationReport({
    requestedModelPath: "/models/native-text",
    normalizedModelDir: "/models/native-text",
    expectedTaskKind: "embedding",
    requestedPathExists: true,
    normalizedDirExists: true,
    modelDirLooksLikeModel: true,
    runtimeSelection: {
      best: {
        candidate: {
          runtime_id: "lmstudio_cpython311_combo_transformers",
          label: "LM Studio combo runtime",
          command: "/python3",
        },
      },
      probes: [{ ready: true }],
    },
    staticMarkers: {
      format_assessment: {
        task_hint: "text_generate",
        task_hint_sources: ["catalog_task_kind:text_generate"],
      },
    },
    loadability: {
      verdict: "native_loadable",
      blocker_reason: "",
      reasons: [],
      auto_config_ok: true,
      auto_tokenizer_ok: true,
      auto_model_ok: true,
      auto_model_for_causal_lm_ok: true,
    },
  });

  assert.equal(report.machine_decision.candidate_usable_for_sample1, false);
  assert.equal(report.candidate_checks.task_kind_status, "mismatch");
  assert.equal(
    report.machine_decision.top_recommended_action.action_id,
    "source_embedding_model_dir_matching_sample1"
  );
});

run("sample1 candidate validation rejects unsupported quantization layouts", () => {
  const report = buildSample1CandidateValidationReport({
    requestedModelPath: "/models/quantized-embed",
    normalizedModelDir: "/models/quantized-embed",
    expectedTaskKind: "embedding",
    requestedPathExists: true,
    normalizedDirExists: true,
    modelDirLooksLikeModel: true,
    runtimeSelection: {
      best: {
        candidate: {
          runtime_id: "lmstudio_cpython311_combo_transformers",
          label: "LM Studio combo runtime",
          command: "/python3",
        },
      },
      probes: [{ ready: true }],
    },
    staticMarkers: {
      format_assessment: {
        task_hint: "embedding",
        task_hint_sources: ["path_name:quantized-embed"],
      },
    },
    loadability: {
      verdict: "partially_loadable_metadata_only",
      blocker_reason: "unsupported_quantization_config",
      reasons: ["quantization_config_missing_quant_method"],
      auto_config_ok: true,
      auto_tokenizer_ok: true,
      auto_model_ok: false,
      auto_model_for_causal_lm_ok: false,
    },
  });

  assert.equal(report.machine_decision.candidate_usable_for_sample1, false);
  assert.equal(
    report.machine_decision.top_recommended_action.action_id,
    "source_different_native_embedding_model_dir"
  );
  assert.equal(report.loadability.blocker_reason, "unsupported_quantization_config");
  assert.equal(
    report.search_recovery.wide_shortlist_search_command.includes("--wide-common-user-roots"),
    true
  );
});

run("sample1 candidate validation keeps exact-path flows machine-readable when task hint is missing", () => {
  const report = buildSample1CandidateValidationReport({
    requestedModelPath: "/models/operator-picked-embed",
    normalizedModelDir: "/models/operator-picked-embed",
    expectedTaskKind: "embedding",
    requestedPathExists: true,
    normalizedDirExists: true,
    modelDirLooksLikeModel: true,
    runtimeSelection: {
      best: {
        candidate: {
          runtime_id: "lmstudio_cpython311_combo_transformers",
          label: "LM Studio combo runtime",
          command: "/python3",
        },
      },
      probes: [{ ready: true }],
    },
    staticMarkers: {
      format_assessment: {
        task_hint: "",
        task_hint_sources: [],
      },
    },
    loadability: {
      verdict: "partially_loadable_metadata_only",
      blocker_reason: "",
      reasons: ["auto_model_failed"],
      auto_config_ok: true,
      auto_tokenizer_ok: true,
      auto_model_ok: false,
      auto_model_for_causal_lm_ok: false,
    },
  });

  assert.equal(report.candidate_checks.task_kind_status, "operator_asserted_only");
  assert.equal(
    report.search_recovery.explicit_model_path_validation_command_template.includes(
      "--model-path <absolute_model_dir>"
    ),
    true
  );
});
