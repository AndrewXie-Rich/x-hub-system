#!/usr/bin/env node
const fs = require("fs");
const path = require("path");

const repoRoot = path.resolve(__dirname, "..");
const bundlePath = path.join(repoRoot, "build/reports/xt_w3_31_require_real_capture_bundle.v1.json");
const qaPath = path.join(repoRoot, "build/reports/xt_w3_31_h_require_real_evidence.v1.json");

function readJSON(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function parseArgs(argv) {
  const out = {
    json: false,
    all: false,
    sampleId: ""
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
    "  node scripts/xt_w3_31_require_real_status.js",
    "  node scripts/xt_w3_31_require_real_status.js --all",
    "  node scripts/xt_w3_31_require_real_status.js --sample-id xt_spf_rr_01_new_project_visible_within_3s",
    "  node scripts/xt_w3_31_require_real_status.js --json",
    ""
  ].join("\n");
  if (exitCode === 0) {
    process.stdout.write(message);
  } else {
    process.stderr.write(message);
  }
  process.exit(exitCode);
}

function isExecuted(sample) {
  return typeof sample.performed_at === "string" && sample.performed_at.trim() !== "";
}

function hasEvidence(sample) {
  return Array.isArray(sample.evidence_refs) && sample.evidence_refs.length > 0;
}

function findFocusSample(samples, sampleId) {
  if (sampleId) {
    return samples.find((sample) => String(sample.sample_id || "").trim() === sampleId) || null;
  }
  return samples.find((sample) => !isExecuted(sample) || sample.success_boolean !== true || !hasEvidence(sample)) || samples[0] || null;
}

function recommendedEvidenceDir(sample) {
  return `build/reports/xt_w3_31_require_real/${sample.sample_id}`;
}

function renderUpdateCommand(sample) {
  const evidenceDir = recommendedEvidenceDir(sample);
  return [
    "node scripts/update_xt_w3_31_require_real_capture_bundle.js",
    `  --sample-id ${sample.sample_id}`,
    "  --status passed",
    "  --success true",
    "  --performed-at <ISO8601>",
    `  --evidence-ref ${evidenceDir}/capture-1.png`,
    `  --evidence-ref ${evidenceDir}/capture-2.log`,
    "  --set observed_result=<observed_result>",
    "  --note <operator_notes>",
    ...requiredSetFieldHints(sample)
  ].join(" \\\n");
}

function requiredSetFieldHints(sample) {
  const skip = new Set([
    "sample_id",
    "status",
    "precondition",
    "hub_machine_actions",
    "xt_machine_actions",
    "expected_result",
    "observed_result",
    "what_to_capture",
    "machine_readable_fields_to_record",
    "performed_at",
    "success_boolean",
    "evidence_refs",
    "operator_notes",
    "expected_result_summary"
  ]);

  const fields = Array.isArray(sample.machine_readable_fields_to_record)
    ? sample.machine_readable_fields_to_record
    : [];
  const hints = [];
  for (const field of fields) {
    const key = String(field || "").trim();
    if (!key || skip.has(key)) continue;
    hints.push(`  --set ${key}=<${key}>`);
  }
  return hints;
}

function buildSummary(bundle, qa, focusSample, allSamples) {
  const samples = Array.isArray(bundle.samples) ? bundle.samples : [];
  const executedSamples = samples.filter(isExecuted);
  const passedSamples = samples.filter((sample) => isExecuted(sample) && sample.success_boolean === true && hasEvidence(sample));
  const failedSamples = samples.filter((sample) => isExecuted(sample) && sample.success_boolean === false);
  const pendingSamples = samples.filter((sample) => !isExecuted(sample) || sample.success_boolean !== true || !hasEvidence(sample));

  return {
    bundle_path: path.relative(repoRoot, bundlePath),
    qa_path: path.relative(repoRoot, qaPath),
    bundle_status: String(bundle.status || "").trim() || "unknown",
    qa_gate_verdict: String(qa.gate_verdict || "").trim() || "unknown",
    qa_release_stance: String(qa.release_stance || "").trim() || "unknown",
    total_samples: samples.length,
    executed_count: executedSamples.length,
    passed_count: passedSamples.length,
    failed_count: failedSamples.length,
    pending_count: pendingSamples.length,
    next_pending_sample_id: focusSample ? focusSample.sample_id : "",
    next_pending_sample: focusSample
      ? {
          sample_id: focusSample.sample_id,
          status: focusSample.status,
          expected_result_summary: focusSample.expected_result_summary || "",
          precondition: focusSample.precondition || "",
          expected_result: focusSample.expected_result || "",
          what_to_capture: Array.isArray(focusSample.what_to_capture) ? focusSample.what_to_capture : [],
          machine_readable_fields_to_record: Array.isArray(focusSample.machine_readable_fields_to_record)
            ? focusSample.machine_readable_fields_to_record
            : [],
          recommended_evidence_dir: recommendedEvidenceDir(focusSample),
          suggested_update_command: renderUpdateCommand(focusSample),
          regenerate_command: "node scripts/generate_xt_w3_31_require_real_report.js"
        }
      : null,
    sample_statuses: allSamples
      ? samples.map((sample) => ({
          sample_id: sample.sample_id,
          status: sample.status,
          performed_at: sample.performed_at || "",
          success_boolean: sample.success_boolean,
          evidence_ref_count: Array.isArray(sample.evidence_refs) ? sample.evidence_refs.length : 0
        }))
      : undefined
  };
}

function printHuman(summary) {
  const lines = [];
  lines.push("XT-W3-31 require-real status");
  lines.push(`bundle_status: ${summary.bundle_status}`);
  lines.push(`qa_gate_verdict: ${summary.qa_gate_verdict}`);
  lines.push(`qa_release_stance: ${summary.qa_release_stance}`);
  lines.push(
    `progress: executed=${summary.executed_count}/${summary.total_samples}, passed=${summary.passed_count}, failed=${summary.failed_count}, pending=${summary.pending_count}`
  );
  if (!summary.next_pending_sample) {
    lines.push("next_sample: none");
    process.stdout.write(lines.join("\n") + "\n");
    return;
  }

  const sample = summary.next_pending_sample;
  lines.push(`next_sample: ${sample.sample_id}`);
  lines.push(`expected_result_summary: ${sample.expected_result_summary}`);
  lines.push(`precondition: ${sample.precondition}`);
  lines.push(`expected_result: ${sample.expected_result}`);
  lines.push(`recommended_evidence_dir: ${sample.recommended_evidence_dir}`);
  lines.push("what_to_capture:");
  for (const item of sample.what_to_capture) {
    lines.push(`  - ${item}`);
  }
  lines.push("machine_readable_fields_to_record:");
  for (const item of sample.machine_readable_fields_to_record) {
    lines.push(`  - ${item}`);
  }
  lines.push("suggested_update_command:");
  lines.push(sample.suggested_update_command);
  lines.push(`regenerate_command: ${sample.regenerate_command}`);
  process.stdout.write(lines.join("\n") + "\n");
}

function main() {
  try {
    const args = parseArgs(process.argv);
    const bundle = readJSON(bundlePath);
    const qa = readJSON(qaPath);
    const samples = Array.isArray(bundle.samples) ? bundle.samples : [];
    const focusSample = findFocusSample(samples, args.sampleId);
    if (args.sampleId && !focusSample) {
      throw new Error(`sample not found: ${args.sampleId}`);
    }

    const summary = buildSummary(bundle, qa, focusSample, args.all);
    if (args.json) {
      process.stdout.write(JSON.stringify(summary, null, 2) + "\n");
      return;
    }
    printHuman(summary);
  } catch (error) {
    process.stderr.write(`${String(error.message || error)}\n`);
    printUsage(1);
  }
}

main();
