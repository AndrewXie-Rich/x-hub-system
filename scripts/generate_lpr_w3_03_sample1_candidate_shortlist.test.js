#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");
const os = require("node:os");
const path = require("node:path");

const {
  buildDiscoveryInputs,
  buildSample1CandidateShortlistReport,
  commonUserWideScanRoots,
  parseArgs,
} = require("./generate_lpr_w3_03_sample1_candidate_shortlist.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

run("sample1 candidate shortlist prefers PASS candidates when one is available", () => {
  const report = buildSample1CandidateShortlistReport({
    expectedTaskKind: "embedding",
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
    discoveryInputs: {
      scan_roots: ["/models"],
      catalog_paths: ["/catalog/models_catalog.json"],
    },
    candidateRows: [
      {
        candidate_rank: 1,
        matches_expected_task_kind: false,
        normalized_model_dir: "/models/native-text",
        requested_model_paths: ["/models/native-text"],
        explicit_path_supplied: false,
        discovery_sources: ["scan_root:/models"],
        candidate_validation: {
          gate_verdict: "NO_GO(sample1_candidate_validation_failed_closed)",
          candidate_usable_for_sample1: false,
          runtime_ready: true,
          task_kind_status: "mismatch",
          inferred_task_hint: "text_generate",
          task_hint_sources: ["catalog_task_kind:text_generate"],
          model_dir_looks_like_model: true,
          loadability_verdict: "native_loadable",
          loadability_blocker: "",
          top_recommended_action: {
            action_id: "source_embedding_model_dir_matching_sample1",
            action_summary: "This text model should not be used for sample1.",
            next_step: "source_embedding_model_dir",
          },
        },
        command_refs: [
          "node scripts/generate_lpr_w3_03_sample1_candidate_validation.js --model-path /models/native-text --task-kind embedding",
        ],
      },
      {
        candidate_rank: 2,
        normalized_model_dir: "/models/native-embed",
        requested_model_paths: ["/models/native-embed"],
        explicit_path_supplied: false,
        matches_expected_task_kind: true,
        discovery_sources: ["scan_root:/models"],
        candidate_validation: {
          gate_verdict: "PASS(sample1_candidate_native_loadable_for_real_execution)",
          candidate_usable_for_sample1: true,
          runtime_ready: true,
          task_kind_status: "confirmed_by_local_metadata",
          inferred_task_hint: "embedding",
          task_hint_sources: ["catalog_task_kind:embedding"],
          model_dir_looks_like_model: true,
          loadability_verdict: "native_loadable",
          loadability_blocker: "",
          top_recommended_action: {
            action_id: "use_candidate_for_sample1_real_run",
            action_summary: "Use this exact candidate.",
            next_step: "prepare_and_execute_sample1_real_run",
          },
        },
        command_refs: [
          "node scripts/generate_lpr_w3_03_sample1_candidate_validation.js --model-path /models/native-embed --task-kind embedding",
        ],
      },
      {
        candidate_rank: 3,
        normalized_model_dir: "/models/quantized-embed",
        requested_model_paths: ["/models/quantized-embed"],
        explicit_path_supplied: false,
        matches_expected_task_kind: true,
        discovery_sources: ["scan_root:/models"],
        candidate_validation: {
          gate_verdict: "NO_GO(sample1_candidate_validation_failed_closed)",
          candidate_usable_for_sample1: false,
          runtime_ready: true,
          task_kind_status: "confirmed_by_local_metadata",
          inferred_task_hint: "embedding",
          task_hint_sources: ["catalog_task_kind:embedding"],
          model_dir_looks_like_model: true,
          loadability_verdict: "partially_loadable_metadata_only",
          loadability_blocker: "unsupported_quantization_config",
          top_recommended_action: {
            action_id: "source_different_native_embedding_model_dir",
            action_summary: "Do not use the quantized candidate.",
            next_step: "source_different_candidate",
          },
        },
        command_refs: [
          "node scripts/generate_lpr_w3_03_sample1_candidate_validation.js --model-path /models/quantized-embed --task-kind embedding",
        ],
      },
    ],
  });

  assert.equal(report.summary.search_outcome, "ready_candidate_found");
  assert.equal(report.summary.pass_candidate_count, 1);
  assert.equal(report.summary.top_candidate_model_path, "/models/native-embed");
  assert.equal(report.summary.top_recommended_action.action_id, "use_best_shortlisted_candidate_for_sample1");
  assert.equal(report.summary.filtered_out_task_mismatch_count, 1);
  assert.equal(report.candidates.length, 2);
  assert.equal(
    report.search_recovery.top_candidate_exact_path_validation_command.includes("--model-path /models/native-embed"),
    true
  );
});

run("sample1 candidate shortlist stays fail-closed when only unsupported quantized candidates are found", () => {
  const report = buildSample1CandidateShortlistReport({
    expectedTaskKind: "embedding",
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
    discoveryInputs: {
      scan_roots: ["/models"],
      catalog_paths: [],
    },
    candidateRows: [
      {
        candidate_rank: 1,
        normalized_model_dir: "/models/quantized-embed",
        requested_model_paths: ["/models/quantized-embed"],
        explicit_path_supplied: false,
        matches_expected_task_kind: true,
        discovery_sources: ["scan_root:/models"],
        candidate_validation: {
          gate_verdict: "NO_GO(sample1_candidate_validation_failed_closed)",
          candidate_usable_for_sample1: false,
          runtime_ready: true,
          task_kind_status: "confirmed_by_local_metadata",
          inferred_task_hint: "embedding",
          task_hint_sources: ["catalog_task_kind:embedding"],
          model_dir_looks_like_model: true,
          loadability_verdict: "partially_loadable_metadata_only",
          loadability_blocker: "unsupported_quantization_config",
          top_recommended_action: {
            action_id: "source_different_native_embedding_model_dir",
            action_summary: "Do not use the quantized candidate.",
            next_step: "source_different_candidate",
          },
        },
        command_refs: [
          "node scripts/generate_lpr_w3_03_sample1_candidate_validation.js --model-path /models/quantized-embed --task-kind embedding",
        ],
      },
    ],
  });

  assert.equal(report.summary.search_outcome, "searched_no_pass_candidate");
  assert.equal(report.summary.pass_candidate_count, 0);
  assert.equal(
    report.summary.top_recommended_action.action_id,
    "source_or_import_different_native_embedding_model_dir"
  );
  assert.equal(
    report.search_recovery.explicit_model_path_shortlist_command_template.includes("--model-path <absolute_model_dir>"),
    true
  );
  assert.equal(
    report.search_recovery.wide_shortlist_search_command.includes("--wide-common-user-roots"),
    true
  );
});

run("sample1 candidate shortlist exposes scan profile and root-level scan_roots for wide scans", () => {
  const report = buildSample1CandidateShortlistReport({
    expectedTaskKind: "embedding",
    wideCommonUserRoots: true,
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
    discoveryInputs: {
      scan_roots: ["/models", ...commonUserWideScanRoots],
      catalog_paths: [],
    },
    candidateRows: [],
  });

  assert.equal(report.scan_profile, "default_roots_plus_common_user_roots");
  assert.equal(Array.isArray(report.scan_roots), true);
  assert.equal(report.scan_roots.length, 4);
  assert.ok(
    report.command_refs.some((item) =>
      String(item || "").includes("--wide-common-user-roots")
    )
  );
  assert.equal(Array.isArray(report.search_recovery.common_user_root_candidates), true);
  assert.equal(report.search_recovery.common_user_root_candidates.length, 3);
});

run("buildDiscoveryInputs appends common user roots when wide scan flag is enabled", () => {
  const discoveryInputs = buildDiscoveryInputs([], { wideCommonUserRoots: true });
  assert.ok(discoveryInputs.scan_roots.includes(path.join(os.homedir(), "models")));
  for (const root of commonUserWideScanRoots) {
    assert.ok(discoveryInputs.scan_roots.includes(root));
  }
});

run("parseArgs accepts the wide common user roots flag", () => {
  const args = parseArgs([
    "node",
    "script",
    "--wide-common-user-roots",
    "--scan-root",
    "/tmp/models",
  ]);

  assert.equal(args.wideCommonUserRoots, true);
  assert.deepEqual(args.scanRoots, ["/tmp/models"]);
});
