#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");

const {
  readCaptureBundle,
  repoRoot,
  resolveReportsDir,
} = require("./xt_w3_24_n_whatsapp_cloud_require_real_bundle_lib.js");
const {
  exampleValueForField,
  findFocusSample,
  recommendedCompletionNotePath,
  recommendedEvidenceDir,
  recommendedTemplatePath,
  renderFinalizeCommand,
  renderPrepareCommand,
  renderUpdateCommand,
} = require("./xt_w3_24_n_whatsapp_cloud_require_real_status.js");

function parseArgs(argv) {
  const out = {
    sampleId: "",
    force: false,
    json: false,
    reportsDir: "",
    bundlePath: "",
  };

  for (let i = 2; i < argv.length; i += 1) {
    const token = String(argv[i] || "").trim();
    switch (token) {
      case "--sample-id":
        out.sampleId = String(argv[++i] || "").trim();
        break;
      case "--force":
        out.force = true;
        break;
      case "--json":
        out.json = true;
        break;
      case "--reports-dir":
        out.reportsDir = String(argv[++i] || "").trim();
        break;
      case "--bundle-path":
        out.bundlePath = String(argv[++i] || "").trim();
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
    "  node scripts/prepare_xt_w3_24_n_whatsapp_cloud_require_real_sample.js",
    "  node scripts/prepare_xt_w3_24_n_whatsapp_cloud_require_real_sample.js --sample-id xt_w3_24_n_rr_03_deploy_plan_routes_project_first_to_preferred_xt",
    "  node scripts/prepare_xt_w3_24_n_whatsapp_cloud_require_real_sample.js --force",
    "  node scripts/prepare_xt_w3_24_n_whatsapp_cloud_require_real_sample.js --json",
    "",
  ].join("\n");
  if (exitCode === 0) process.stdout.write(message);
  else process.stderr.write(message);
  process.exit(exitCode);
}

function placeholderValue(sample, fieldName) {
  const raw = exampleValueForField(sample, fieldName);
  if (/^(true|false|null|-?\d+(\.\d+)?)$/.test(raw)) {
    try {
      return JSON.parse(raw);
    } catch {
      return raw;
    }
  }
  if ((raw.startsWith("{") && raw.endsWith("}")) || (raw.startsWith("[") && raw.endsWith("]"))) {
    try {
      return JSON.parse(raw);
    } catch {
      return raw;
    }
  }
  return raw;
}

function manifestForSample(sample) {
  const fields = Array.isArray(sample.machine_readable_fields_to_record)
    ? sample.machine_readable_fields_to_record
    : [];
  const template = {};
  for (const field of fields) {
    const key = String(field || "").trim();
    if (!key) continue;
    template[key] = placeholderValue(sample, key);
  }

  return {
    schema_version: "xhub.xt_w3_24_n_whatsapp_cloud_require_real_sample_scaffold.v1",
    sample_id: sample.sample_id,
    status: sample.status,
    expected_result_summary: sample.expected_result_summary || "",
    precondition: sample.precondition || "",
    expected_result: sample.expected_result || "",
    what_to_capture: Array.isArray(sample.what_to_capture) ? sample.what_to_capture : [],
    required_checks: Array.isArray(sample.required_checks) ? sample.required_checks : [],
    machine_readable_fields_to_record: fields,
    machine_readable_template: template,
  };
}

function relativeOrAbsolute(targetPath) {
  const relative = path.relative(repoRoot, targetPath);
  if (!relative.startsWith("..") && !path.isAbsolute(relative)) {
    return relative || ".";
  }
  return targetPath;
}

function writeFileMaybe(filePath, contents, force) {
  if (!force && fs.existsSync(filePath)) {
    return "skipped_existing";
  }
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, contents, "utf8");
  return "written";
}

function prepareSampleScaffold(sample, options = {}) {
  const reportsDir = resolveReportsDir(options);
  const evidenceDir = path.join(reportsDir, "xt_w3_24_n_whatsapp_cloud_require_real", sample.sample_id);
  fs.mkdirSync(evidenceDir, { recursive: true });

  const recommendedDir = recommendedEvidenceDir(sample);
  const templatePath = recommendedTemplatePath(sample);
  const completionNotePath = recommendedCompletionNotePath(sample);
  const manifest = manifestForSample(sample);
  const finalizeCommand = renderFinalizeCommand(sample);
  const updateCommand = renderUpdateCommand(sample);
  const prepareCommand = renderPrepareCommand(sample);
  const readme = [
    `# ${sample.sample_id}`,
    "",
    `status: ${sample.status}`,
    `expected_result_summary: ${sample.expected_result_summary || ""}`,
    `recommended_evidence_dir: ${recommendedDir}`,
    `recommended_template_path: ${templatePath}`,
    "",
    "## Precondition",
    sample.precondition || "",
    "",
    "## Expected Result",
    sample.expected_result || "",
    "",
    "## What To Capture",
    ...(Array.isArray(sample.what_to_capture) ? sample.what_to_capture.map((item) => `- ${item}`) : []),
    "",
    "## Required Checks",
    ...(Array.isArray(sample.required_checks) ? sample.required_checks.map((check) => `- \`${JSON.stringify(check)}\``) : []),
    "",
    "## Machine-readable Fields",
    ...(Array.isArray(sample.machine_readable_fields_to_record)
      ? sample.machine_readable_fields_to_record.map((field) => `- \`${field}\``)
      : []),
    "",
    "## Prepare Command",
    "```bash",
    prepareCommand,
    "```",
    "",
    "## Finalize Command",
    "在填完 `machine_readable_template.v1.json`、放入真实证据文件、补充 `completion_notes.txt` 后执行：",
    "```bash",
    finalizeCommand,
    "```",
    "",
    "## Suggested Update Command",
    "低层回填命令，仅在需要覆盖默认 finalize 行为时使用：",
    "```bash",
    updateCommand,
    "```",
    "",
    "## Scaffold Rules",
    "- 把模板里的 `<...>` 占位符替换成真实运行值，否则 fail-closed 校验会拒绝通过。",
    "- `completion_notes.txt` 里的 `#` 注释行会被忽略；保留空文件也可以。",
    "- `README.md` / `completion_notes.txt` / `*.command.txt` / `sample_manifest.v1.json` / `machine_readable_template.v1.json` 都不会被当成运行证据。",
    "",
    "## Expected Evidence Files",
    `- \`${recommendedDir}/capture-1.png\``,
    `- \`${recommendedDir}/capture-2.log\``,
    "",
  ].join("\n");

  const targets = [
    {
      path: path.join(evidenceDir, "README.md"),
      contents: `${readme}\n`,
    },
    {
      path: path.join(evidenceDir, "sample_manifest.v1.json"),
      contents: `${JSON.stringify(manifest, null, 2)}\n`,
    },
    {
      path: path.join(evidenceDir, "machine_readable_template.v1.json"),
      contents: `${JSON.stringify(manifest.machine_readable_template, null, 2)}\n`,
    },
    {
      path: path.join(evidenceDir, "completion_notes.txt"),
      contents: [
        "# 填写本次真实执行的结论、异常和关键观察。",
        "# finalize helper 会忽略以 # 开头的提示行。",
        "",
      ].join("\n"),
    },
    {
      path: path.join(evidenceDir, "finalize_sample.command.txt"),
      contents: `${finalizeCommand}\n`,
    },
    {
      path: path.join(evidenceDir, "update_bundle.command.txt"),
      contents: `${updateCommand}\n`,
    },
  ];

  const files = targets.map((target) => ({
    path: relativeOrAbsolute(target.path),
    status: writeFileMaybe(target.path, target.contents, !!options.force),
  }));

  return {
    sample_id: sample.sample_id,
    evidence_dir: relativeOrAbsolute(evidenceDir),
    recommended_evidence_dir: recommendedDir,
    recommended_template_path: templatePath,
    recommended_completion_note_path: completionNotePath,
    files,
    prepare_command: prepareCommand,
    finalize_command: finalizeCommand,
    regenerate_command: "node scripts/generate_xt_w3_24_n_whatsapp_cloud_require_real_report.js",
    suggested_update_command: updateCommand,
  };
}

function main() {
  try {
    const args = parseArgs(process.argv);
    const bundle = readCaptureBundle({
      reportsDir: args.reportsDir,
      bundlePath: args.bundlePath,
    });
    const sample = findFocusSample(Array.isArray(bundle.samples) ? bundle.samples : [], args.sampleId);
    if (!sample) {
      throw new Error(args.sampleId ? `sample not found: ${args.sampleId}` : "no sample found in capture bundle");
    }

    const output = prepareSampleScaffold(sample, {
      force: args.force,
      reportsDir: args.reportsDir,
      bundlePath: args.bundlePath,
    });

    if (args.json) {
      process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
      return;
    }

    const lines = [
      `sample_id: ${output.sample_id}`,
      `evidence_dir: ${output.evidence_dir}`,
      `recommended_evidence_dir: ${output.recommended_evidence_dir}`,
      `recommended_template_path: ${output.recommended_template_path}`,
      `recommended_completion_note_path: ${output.recommended_completion_note_path}`,
      "files:",
      ...output.files.map((file) => `  - ${file.status}: ${file.path}`),
      `prepare_command: ${output.prepare_command}`,
      `finalize_command: ${output.finalize_command}`,
      "suggested_update_command:",
      output.suggested_update_command,
      `regenerate_command: ${output.regenerate_command}`,
    ];
    process.stdout.write(`${lines.join("\n")}\n`);
  } catch (error) {
    process.stderr.write(`${String(error.message || error)}\n`);
    printUsage(1);
  }
}

module.exports = {
  manifestForSample,
  parseArgs,
  placeholderValue,
  prepareSampleScaffold,
};

if (require.main === module) {
  main();
}
