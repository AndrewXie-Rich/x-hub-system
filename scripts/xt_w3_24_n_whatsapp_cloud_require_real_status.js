#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");
const {
  readCaptureBundle,
  resolveBundlePath,
  resolveRequireRealEvidencePath,
} = require("./xt_w3_24_n_whatsapp_cloud_require_real_bundle_lib.js");

const repoRoot = path.resolve(__dirname, "..");

function readJSON(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
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
    json: false,
    all: false,
    sampleId: "",
  };

  for (let i = 2; i < argv.length; i += 1) {
    const token = String(argv[i] || "").trim();
    switch (token) {
      case "--json":
        out.json = true;
        break;
      case "--all":
        out.all = true;
        break;
      case "--sample-id":
        out.sampleId = String(argv[++i] || "").trim();
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
    "  node scripts/xt_w3_24_n_whatsapp_cloud_require_real_status.js",
    "  node scripts/xt_w3_24_n_whatsapp_cloud_require_real_status.js --all",
    "  node scripts/xt_w3_24_n_whatsapp_cloud_require_real_status.js --sample-id xt_w3_24_n_rr_03_deploy_plan_routes_project_first_to_preferred_xt",
    "  node scripts/xt_w3_24_n_whatsapp_cloud_require_real_status.js --json",
    "",
  ].join("\n");

  if (exitCode === 0) process.stdout.write(message);
  else process.stderr.write(message);
  process.exit(exitCode);
}

function isExecuted(sample) {
  return typeof sample.performed_at === "string" && sample.performed_at.trim() !== "";
}

function hasEvidence(sample) {
  return Array.isArray(sample.evidence_refs) && sample.evidence_refs.length > 0;
}

function isPassed(sample) {
  return isExecuted(sample) && sample.success_boolean === true && hasEvidence(sample);
}

function findFocusSample(samples, sampleId) {
  if (sampleId) {
    return samples.find((sample) => String(sample.sample_id || "").trim() === sampleId) || null;
  }
  return samples.find((sample) => !isPassed(sample)) || samples[0] || null;
}

function recommendedEvidenceDir(sample) {
  return `build/reports/xt_w3_24_n_whatsapp_cloud_require_real/${sample.sample_id}`;
}

function recommendedTemplatePath(sample) {
  return `${recommendedEvidenceDir(sample)}/machine_readable_template.v1.json`;
}

function recommendedCompletionNotePath(sample) {
  return `${recommendedEvidenceDir(sample)}/completion_notes.txt`;
}

function exampleValueForField(sample, fieldName) {
  const checks = Array.isArray(sample.required_checks) ? sample.required_checks : [];
  const directCheck = checks.find((check) => String(check.field || "").trim() === fieldName) || null;

  if (directCheck) {
    if (Object.prototype.hasOwnProperty.call(directCheck, "equals")) {
      return typeof directCheck.equals === "string" ? directCheck.equals : JSON.stringify(directCheck.equals);
    }
    if (Array.isArray(directCheck.one_of) && directCheck.one_of.length > 0) {
      const first = directCheck.one_of[0];
      return typeof first === "string" ? first : JSON.stringify(first);
    }
    if (Array.isArray(directCheck.contains_all) && directCheck.contains_all.length > 0) {
      return JSON.stringify(directCheck.contains_all);
    }
    if (typeof directCheck.min === "number") {
      return String(directCheck.min);
    }
    if (typeof directCheck.max === "number") {
      return String(directCheck.max);
    }
    if (Object.prototype.hasOwnProperty.call(directCheck, "not_equals")) {
      return typeof directCheck.not_equals === "string" && directCheck.not_equals === ""
        ? `<${fieldName}>`
        : JSON.stringify(directCheck.not_equals);
    }
  }

  const currentValue = sample[fieldName];
  if (typeof currentValue === "boolean") return JSON.stringify(currentValue);
  if (typeof currentValue === "number") return String(currentValue);
  if (Array.isArray(currentValue)) return JSON.stringify(currentValue);
  if (fieldName.endsWith("_id")) return `<${fieldName}>`;
  return `<${fieldName}>`;
}

function renderUpdateCommand(sample) {
  return [
    "node scripts/update_xt_w3_24_n_whatsapp_cloud_require_real_capture_bundle.js",
    `  --scaffold-dir ${recommendedEvidenceDir(sample)}`,
    "  --status passed",
    "  --success true",
    "  --note <operator_notes>",
  ].join(" \\\n");
}

function renderFinalizeCommand(sample) {
  return [
    "node scripts/finalize_xt_w3_24_n_whatsapp_cloud_require_real_sample.js",
    `  --scaffold-dir ${recommendedEvidenceDir(sample)}`,
  ].join(" \\\n");
}

function renderPrepareCommand(sample) {
  return `node scripts/prepare_xt_w3_24_n_whatsapp_cloud_require_real_sample.js --sample-id ${sample.sample_id}`;
}

function buildSummary(bundle, qa, focusSample, allSamples) {
  const samples = Array.isArray(bundle.samples) ? bundle.samples : [];
  const resolvedBundlePath = resolveBundlePath();
  const resolvedQAPath = resolveRequireRealEvidencePath();
  const executedSamples = samples.filter(isExecuted);
  const passedSamples = samples.filter(isPassed);
  const failedSamples = samples.filter((sample) => isExecuted(sample) && sample.success_boolean === false);
  const pendingSamples = samples.filter((sample) => !isPassed(sample));

  return {
    bundle_path: path.relative(repoRoot, resolvedBundlePath),
    qa_path: path.relative(repoRoot, resolvedQAPath),
    bundle_status: String(bundle.status || "").trim() || "unknown",
    qa_gate_verdict: qa ? (String(qa.gate_verdict || "").trim() || "unknown") : "missing(run_generate_first)",
    qa_release_stance: qa ? (String(qa.release_stance || "").trim() || "unknown") : "missing(run_generate_first)",
    total_samples: samples.length,
    executed_count: executedSamples.length,
    passed_count: passedSamples.length,
    failed_count: failedSamples.length,
    pending_count: pendingSamples.length,
    channel_release_freeze: qa && Array.isArray(qa.channel_release_freeze) ? qa.channel_release_freeze : [],
    next_pending_sample_id: focusSample ? focusSample.sample_id : "",
    next_pending_sample: focusSample
      ? {
          sample_id: focusSample.sample_id,
          status: focusSample.status,
          expected_result_summary: focusSample.expected_result_summary || "",
          precondition: focusSample.precondition || "",
          expected_result: focusSample.expected_result || "",
          what_to_capture: Array.isArray(focusSample.what_to_capture) ? focusSample.what_to_capture : [],
          required_checks: Array.isArray(focusSample.required_checks) ? focusSample.required_checks : [],
          machine_readable_fields_to_record: Array.isArray(focusSample.machine_readable_fields_to_record)
            ? focusSample.machine_readable_fields_to_record
            : [],
          recommended_evidence_dir: recommendedEvidenceDir(focusSample),
          recommended_template_path: recommendedTemplatePath(focusSample),
          recommended_completion_note_path: recommendedCompletionNotePath(focusSample),
          prepare_command: renderPrepareCommand(focusSample),
          suggested_finalize_command: renderFinalizeCommand(focusSample),
          suggested_update_command: renderUpdateCommand(focusSample),
          regenerate_command: "node scripts/generate_xt_w3_24_n_whatsapp_cloud_require_real_report.js",
        }
      : null,
    all_sample_details: allSamples
      ? samples.map((sample) => ({
          sample_id: sample.sample_id,
          status: sample.status,
          expected_result_summary: sample.expected_result_summary || "",
          precondition: sample.precondition || "",
          expected_result: sample.expected_result || "",
          what_to_capture: Array.isArray(sample.what_to_capture) ? sample.what_to_capture : [],
          required_checks: Array.isArray(sample.required_checks) ? sample.required_checks : [],
          machine_readable_fields_to_record: Array.isArray(sample.machine_readable_fields_to_record)
            ? sample.machine_readable_fields_to_record
            : [],
          recommended_evidence_dir: recommendedEvidenceDir(sample),
          recommended_template_path: recommendedTemplatePath(sample),
          recommended_completion_note_path: recommendedCompletionNotePath(sample),
          prepare_command: renderPrepareCommand(sample),
          suggested_finalize_command: renderFinalizeCommand(sample),
          suggested_update_command: renderUpdateCommand(sample),
          regenerate_command: "node scripts/generate_xt_w3_24_n_whatsapp_cloud_require_real_report.js",
          performed_at: sample.performed_at || "",
          success_boolean: sample.success_boolean,
          evidence_ref_count: Array.isArray(sample.evidence_refs) ? sample.evidence_refs.length : 0,
        }))
      : undefined,
    sample_statuses: allSamples
      ? samples.map((sample) => ({
          sample_id: sample.sample_id,
          status: sample.status,
          performed_at: sample.performed_at || "",
          success_boolean: sample.success_boolean,
          evidence_ref_count: Array.isArray(sample.evidence_refs) ? sample.evidence_refs.length : 0,
        }))
      : undefined,
  };
}

function printHuman(summary) {
  const lines = [];
  lines.push("XT-W3-24-N WhatsApp Cloud require-real status");
  lines.push(`bundle_status: ${summary.bundle_status}`);
  lines.push(`qa_gate_verdict: ${summary.qa_gate_verdict}`);
  lines.push(`qa_release_stance: ${summary.qa_release_stance}`);
  for (const row of summary.channel_release_freeze) {
    lines.push(`${row.provider}: ${row.release_stage_current}`);
  }
  lines.push(
    `progress: executed=${summary.executed_count}/${summary.total_samples}, passed=${summary.passed_count}, failed=${summary.failed_count}, pending=${summary.pending_count}`
  );

  if (Array.isArray(summary.all_sample_details) && summary.all_sample_details.length > 0) {
    lines.push("samples:");
    for (const sample of summary.all_sample_details) {
      lines.push(`sample_id: ${sample.sample_id}`);
      lines.push(`status: ${sample.status}`);
      lines.push(`performed_at: ${sample.performed_at}`);
      lines.push(`success_boolean: ${sample.success_boolean}`);
      lines.push(`evidence_ref_count: ${sample.evidence_ref_count}`);
      lines.push(`expected_result_summary: ${sample.expected_result_summary}`);
      lines.push(`precondition: ${sample.precondition}`);
      lines.push(`expected_result: ${sample.expected_result}`);
      lines.push(`recommended_evidence_dir: ${sample.recommended_evidence_dir}`);
      lines.push(`recommended_template_path: ${sample.recommended_template_path}`);
      lines.push(`recommended_completion_note_path: ${sample.recommended_completion_note_path}`);
      lines.push("what_to_capture:");
      for (const item of sample.what_to_capture) {
        lines.push(`  - ${item}`);
      }
      lines.push("required_checks:");
      for (const check of sample.required_checks) {
        lines.push(`  - ${JSON.stringify(check)}`);
      }
      lines.push("machine_readable_fields_to_record:");
      for (const field of sample.machine_readable_fields_to_record) {
        lines.push(`  - ${field}`);
      }
      lines.push(`prepare_command: ${sample.prepare_command}`);
      lines.push("suggested_finalize_command:");
      lines.push(sample.suggested_finalize_command);
      lines.push("suggested_update_command:");
      lines.push(sample.suggested_update_command);
      lines.push(`regenerate_command: ${sample.regenerate_command}`);
      lines.push("---");
    }
    process.stdout.write(`${lines.join("\n")}\n`);
    return;
  }

  if (!summary.next_pending_sample) {
    lines.push("next_sample: none");
    process.stdout.write(`${lines.join("\n")}\n`);
    return;
  }

  const sample = summary.next_pending_sample;
  lines.push(`next_sample: ${sample.sample_id}`);
  lines.push(`expected_result_summary: ${sample.expected_result_summary}`);
  lines.push(`precondition: ${sample.precondition}`);
  lines.push(`expected_result: ${sample.expected_result}`);
  lines.push(`recommended_evidence_dir: ${sample.recommended_evidence_dir}`);
  lines.push(`recommended_template_path: ${sample.recommended_template_path}`);
  lines.push(`recommended_completion_note_path: ${sample.recommended_completion_note_path}`);
  lines.push("what_to_capture:");
  for (const item of sample.what_to_capture) {
    lines.push(`  - ${item}`);
  }
  lines.push("required_checks:");
  for (const check of sample.required_checks) {
    lines.push(`  - ${JSON.stringify(check)}`);
  }
  lines.push("machine_readable_fields_to_record:");
  for (const field of sample.machine_readable_fields_to_record) {
    lines.push(`  - ${field}`);
  }
  lines.push(`prepare_command: ${sample.prepare_command}`);
  lines.push("suggested_finalize_command:");
  lines.push(sample.suggested_finalize_command);
  lines.push("suggested_update_command:");
  lines.push(sample.suggested_update_command);
  lines.push(`regenerate_command: ${sample.regenerate_command}`);
  process.stdout.write(`${lines.join("\n")}\n`);
}

function main() {
  try {
    const args = parseArgs(process.argv);
    const bundle = readCaptureBundle();
    const qa = readJSONIfExists(resolveRequireRealEvidencePath());
    const samples = Array.isArray(bundle.samples) ? bundle.samples : [];
    const focusSample = findFocusSample(samples, args.sampleId);

    if (args.sampleId && !focusSample) {
      throw new Error(`sample not found: ${args.sampleId}`);
    }

    const summary = buildSummary(bundle, qa, focusSample, args.all);
    if (args.json) {
      process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
      return;
    }
    printHuman(summary);
  } catch (error) {
    process.stderr.write(`${String(error.message || error)}\n`);
    printUsage(1);
  }
}

module.exports = {
  buildSummary,
  exampleValueForField,
  findFocusSample,
  parseArgs,
  printHuman,
  readJSON,
  recommendedCompletionNotePath,
  recommendedEvidenceDir,
  recommendedTemplatePath,
  renderFinalizeCommand,
  renderPrepareCommand,
  renderUpdateCommand,
};

if (require.main === module) {
  main();
}
