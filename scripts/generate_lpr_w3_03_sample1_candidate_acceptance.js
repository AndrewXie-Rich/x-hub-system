#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");

const {
  readCaptureBundle,
  resolveReportsDir,
  writeJSON,
} = require("./lpr_w3_03_require_real_bundle_lib.js");
const {
  findFocusSample,
  readJSON,
  renderFinalizeCommand,
  renderPrepareCommand,
} = require("./lpr_w3_03_require_real_status.js");

const defaultOutputPath = path.join(
  resolveReportsDir(),
  "lpr_w3_03_sample1_candidate_acceptance.v1.json"
);

function isoNow() {
  return new Date().toISOString();
}

function normalizeString(value) {
  return String(value || "").trim();
}

function dedupeStrings(values = []) {
  const out = [];
  const seen = new Set();
  for (const value of values) {
    const text = normalizeString(value);
    if (!text || seen.has(text)) continue;
    seen.add(text);
    out.push(text);
  }
  return out;
}

function readJSONIfExists(filePath) {
  try {
    if (!fs.existsSync(filePath)) return null;
    return readJSON(filePath);
  } catch {
    return null;
  }
}

function parseArgs(argv) {
  const out = {
    outJson: defaultOutputPath,
  };

  for (let i = 2; i < argv.length; i += 1) {
    const token = normalizeString(argv[i]);
    switch (token) {
      case "--out-json":
        out.outJson = path.resolve(normalizeString(argv[++i]));
        break;
      case "--help":
      case "-h":
        printUsage(0);
        break;
      default:
        throw new Error(`unknown arg: ${token}`);
    }
  }
  return out;
}

function printUsage(exitCode) {
  const message = [
    "usage:",
    "  node scripts/generate_lpr_w3_03_sample1_candidate_acceptance.js",
    "  node scripts/generate_lpr_w3_03_sample1_candidate_acceptance.js --out-json build/reports/lpr_w3_03_sample1_candidate_acceptance.v1.json",
    "",
  ].join("\n");
  if (exitCode === 0) process.stdout.write(message);
  else process.stderr.write(message);
  process.exit(exitCode);
}

function buildDirectoryChecklist() {
  return [
    {
      check_id: "dir_exists",
      type: "required",
      description: "The candidate path must exist on disk and resolve to a directory.",
    },
    {
      check_id: "config_json_present",
      type: "required",
      description: "The directory must include `config.json`.",
    },
    {
      check_id: "tokenizer_or_weights_present",
      type: "required",
      description: "The directory must include tokenizer metadata and at least one local weight file such as `.safetensors` or `.bin`.",
    },
    {
      check_id: "task_kind_not_mismatch",
      type: "required",
      description: "The candidate must not resolve to `task_kind_status=mismatch` against `embedding`.",
    },
    {
      check_id: "runtime_ready",
      type: "required",
      description: "A ready torch/transformers runtime must be available on this machine.",
    },
    {
      check_id: "native_loadable",
      type: "required",
      description: "The exact path must pass `AutoConfig + AutoTokenizer + AutoModel/AutoModelForCausalLM` native loading on the selected runtime.",
    },
  ];
}

function buildRejectSignals() {
  return [
    {
      signal: "task_kind_status=mismatch",
      reason: "This model is for another task kind and must not be used for sample1 embedding execution.",
    },
    {
      signal: "loadability_blocker=unsupported_quantization_config",
      reason: "This layout looks like LM Studio / MLX quantized output and is not acceptable as a native transformers embedding dir.",
    },
    {
      signal: "loadability_reasons include `quantization_config_missing_quant_method`",
      reason: "Quantization metadata is incomplete for native transformers loading.",
    },
    {
      signal: "loadability_reasons include `.scales` or `.biases` sidecar markers",
      reason: "The directory is likely a provider-specific quantized artifact rather than a plain native-loadable HF model dir.",
    },
    {
      signal: "runtime_ready=false",
      reason: "Even a good model dir cannot be accepted until the runtime itself is ready.",
    },
  ];
}

function buildAcceptanceReport({
  generatedAt = isoNow(),
  focusSample = null,
  shortlist = null,
  handoff = null,
} = {}) {
  const shortlistPayload = shortlist && typeof shortlist === "object" ? shortlist : {};
  const handoffPayload = handoff && typeof handoff === "object" ? handoff : {};
  const candidates = Array.isArray(shortlistPayload.candidates) ? shortlistPayload.candidates : [];
  const topCandidate = candidates[0] || null;
  const filteredOut = Array.isArray(shortlistPayload.filtered_out_task_mismatch)
    ? shortlistPayload.filtered_out_task_mismatch
    : [];
  const runtimeReady =
    shortlistPayload.runtime_resolution && shortlistPayload.runtime_resolution.runtime_ready === true;
  const topRecommendedAction =
    shortlistPayload.summary && shortlistPayload.summary.top_recommended_action
      ? shortlistPayload.summary.top_recommended_action
      : {
          action_id: "inspect_sample1_candidate_acceptance",
          action_summary: "Inspect the current machine state and candidate acceptance contract.",
          next_step: "review_acceptance_packet",
        };
  const nativeExecutionContract =
    handoffPayload.native_execution_contract && typeof handoffPayload.native_execution_contract === "object"
      ? handoffPayload.native_execution_contract
      : {
          provider: "transformers",
          task_kind: "embedding",
          must_pass: [],
          reject_if: [],
        };

  return {
    schema_version: "xhub.lpr_w3_03_sample1_candidate_acceptance.v1",
    generated_at: generatedAt,
    scope: "Operator-facing hard acceptance contract for sample1 embedding model directories.",
    fail_closed: true,
    sample_id: "lpr_rr_01_embedding_real_model_dir_executes",
    current_machine_state: {
      runtime_ready: runtimeReady,
      search_outcome: normalizeString(shortlistPayload.summary && shortlistPayload.summary.search_outcome),
      handoff_state: normalizeString(handoffPayload.handoff_state),
      blocker_class: normalizeString(handoffPayload.blocker_class),
      top_recommended_action: topRecommendedAction,
      candidates_considered: Number(shortlistPayload.summary && shortlistPayload.summary.candidates_considered || 0),
      filtered_out_task_mismatch_count: Number(
        shortlistPayload.summary && shortlistPayload.summary.filtered_out_task_mismatch_count || 0
      ),
    },
    acceptance_contract: {
      expected_provider: "transformers",
      expected_task_kind: "embedding",
      accepted_task_kind_statuses: [
        "confirmed_by_local_metadata",
        "operator_asserted_only(explicit_model_path_only_and_validator_must_still_PASS)",
      ],
      required_gate_verdict: "PASS(sample1_candidate_native_loadable_for_real_execution)",
      required_loadability_verdict: "native_loadable",
      directory_checklist: buildDirectoryChecklist(),
      native_execution_contract: nativeExecutionContract,
      reject_signals: buildRejectSignals(),
    },
    current_no_go_example: topCandidate
      ? {
          normalized_model_dir: normalizeString(topCandidate.normalized_model_dir),
          gate_verdict: normalizeString(topCandidate.candidate_validation && topCandidate.candidate_validation.gate_verdict),
          task_kind_status: normalizeString(
            topCandidate.candidate_validation && topCandidate.candidate_validation.task_kind_status
          ),
          inferred_task_hint: normalizeString(
            topCandidate.candidate_validation && topCandidate.candidate_validation.inferred_task_hint
          ),
          loadability_verdict: normalizeString(
            topCandidate.candidate_validation && topCandidate.candidate_validation.loadability_verdict
          ),
          loadability_blocker: normalizeString(
            topCandidate.candidate_validation && topCandidate.candidate_validation.loadability_blocker
          ),
          task_hint_sources: dedupeStrings(
            topCandidate.candidate_validation && topCandidate.candidate_validation.task_hint_sources || []
          ),
        }
      : null,
    filtered_out_examples: filteredOut.slice(0, 3).map((row) => ({
      normalized_model_dir: normalizeString(row.normalized_model_dir),
      task_kind_status: normalizeString(row.candidate_validation && row.candidate_validation.task_kind_status),
      inferred_task_hint: normalizeString(row.candidate_validation && row.candidate_validation.inferred_task_hint),
    })),
    sample_evidence_contract: focusSample
      ? {
          recommended_evidence_dir: `build/reports/lpr_w3_03_require_real/${focusSample.sample_id}`,
          required_capture: Array.isArray(focusSample.what_to_capture) ? focusSample.what_to_capture : [],
          required_machine_fields: Array.isArray(focusSample.machine_readable_fields_to_record)
            ? focusSample.machine_readable_fields_to_record
            : [],
          required_checks: Array.isArray(focusSample.required_checks) ? focusSample.required_checks : [],
        }
      : null,
    operator_workflow: [
      {
        step_id: "review_acceptance_contract",
        description: "Review the hard accept/reject contract before importing or validating a new model dir.",
        command: "node scripts/generate_lpr_w3_03_sample1_candidate_acceptance.js",
      },
      {
        step_id: "build_registration_packet",
        description: "Normalize the exact dir and preview the proposed catalog payload before any manual catalog write.",
        command: "node scripts/generate_lpr_w3_03_sample1_candidate_registration_packet.js --model-path <absolute_model_dir>",
      },
      {
        step_id: "inspect_catalog_patch_plan",
        description:
          "Inspect the shape-aware patch plan so any later manual patch keeps one chosen runtime base's models_catalog.json + models_state.json aligned as a pair.",
        command: "node scripts/generate_lpr_w3_03_sample1_candidate_catalog_patch_plan.js",
      },
      {
        step_id: "scan_or_register_candidates",
        description: "See which local dirs were searched and which ones are already NO_GO or PASS.",
        command: "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js",
      },
      {
        step_id: "widen_search_common_user_roots",
        description:
          "If the default shortlist still shows no usable candidate, widen the search across common user download locations while keeping the search machine-readable.",
        command:
          "node scripts/generate_lpr_w3_03_sample1_candidate_shortlist.js --wide-common-user-roots",
      },
      {
        step_id: "validate_exact_path",
        description: "Validate the exact candidate directory you want to try for sample1.",
        command: "node scripts/generate_lpr_w3_03_sample1_candidate_validation.js --model-path <absolute_model_dir>",
      },
      {
        step_id: "prepare_sample",
        description: "Only after PASS, prepare the sample1 scaffold.",
        command: focusSample ? renderPrepareCommand(focusSample) : "",
      },
      {
        step_id: "finalize_sample",
        description: "After a real run with real evidence, finalize the sample and regenerate QA.",
        command: focusSample ? renderFinalizeCommand(focusSample) : "",
      },
      {
        step_id: "regenerate_qa",
        description: "Refresh require-real QA and confirm the gate moves with real evidence only.",
        command: "node scripts/generate_lpr_w3_03_a_require_real_evidence.js",
      },
    ].filter((row) => !!normalizeString(row.command)),
    artifact_refs: {
      shortlist_report: "build/reports/lpr_w3_03_sample1_candidate_shortlist.v1.json",
      handoff_report: "build/reports/lpr_w3_03_sample1_operator_handoff.v1.json",
    },
    notes: [
      "This packet is an acceptance contract, not a green light. Only the exact-path validator PASS can unlock sample1 execution.",
      "If you already have an exact candidate dir, generate the registration packet before manual catalog edits so the normalized dir and proposed payload stay machine-readable.",
      "If the validator passes later, inspect the catalog patch plan before touching any external models_catalog.json / models_state.json pair.",
      "If a new candidate lives outside the default scan roots, pass it via `--model-path` or `--scan-root` so the search remains machine-readable.",
      "Current machine truth still says no native-loadable embedding dir is available locally.",
    ],
  };
}

function main() {
  try {
    const args = parseArgs(process.argv);
    const bundle = readCaptureBundle();
    const samples = Array.isArray(bundle.samples) ? bundle.samples : [];
    const focusSample = findFocusSample(samples, "lpr_rr_01_embedding_real_model_dir_executes");
    const reportsDir = resolveReportsDir();
    const shortlist = readJSONIfExists(path.join(reportsDir, "lpr_w3_03_sample1_candidate_shortlist.v1.json"));
    const handoff = readJSONIfExists(path.join(reportsDir, "lpr_w3_03_sample1_operator_handoff.v1.json"));
    const report = buildAcceptanceReport({
      focusSample,
      shortlist,
      handoff,
    });
    writeJSON(args.outJson, report);
    process.stdout.write(`${args.outJson}\n`);
  } catch (error) {
    process.stderr.write(`${String(error.message || error)}\n`);
    printUsage(1);
  }
}

module.exports = {
  buildAcceptanceReport,
  parseArgs,
};

if (require.main === module) {
  main();
}
