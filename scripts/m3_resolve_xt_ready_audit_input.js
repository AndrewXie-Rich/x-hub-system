#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");

const DEFAULT_ENV_VAR = "XT_READY_AUDIT_EXPORT_JSON";
const DEFAULT_BUILD_AUDIT_JSON = "./build/xt_ready_audit_export.json";
const DEFAULT_SAMPLE_AUDIT_JSON = "./scripts/fixtures/xt_ready_audit_events.sample.json";

function parseArgs(argv) {
  const out = {};
  for (let i = 2; i < argv.length; i += 1) {
    const cur = String(argv[i] || "");
    if (!cur.startsWith("--")) continue;
    const key = cur.slice(2);
    const nxt = argv[i + 1];
    if (nxt && !String(nxt).startsWith("--")) {
      out[key] = String(nxt);
      i += 1;
    } else {
      out[key] = "1";
    }
  }
  return out;
}

function writeText(filePath, content) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, String(content || ""), "utf8");
}

function appendGithubOutput(filePath, selection = {}) {
  const outPath = String(filePath || "").trim();
  if (!outPath) return;
  const selectedAuditJson = String(selection.selected_audit_json || "").trim();
  const selectedSource = String(selection.selected_source || "").trim();
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.appendFileSync(
    outPath,
    `selected_audit_json=${selectedAuditJson}\nselected_source=${selectedSource}\n`,
    "utf8"
  );
}

function resolveXtReadyAuditInput(opts = {}, env = process.env) {
  const envVar = String(opts.env_var || DEFAULT_ENV_VAR).trim() || DEFAULT_ENV_VAR;
  const envCandidate = String(env[envVar] || "").trim();
  const buildCandidate = String(opts.build_audit_json || DEFAULT_BUILD_AUDIT_JSON).trim();
  const sampleCandidate = String(opts.sample_audit_json || DEFAULT_SAMPLE_AUDIT_JSON).trim();
  const requireReal = !!opts.require_real;

  const candidates = [
    { source: "real_audit_export_env", candidate_path: envCandidate },
    { source: "real_audit_export_build", candidate_path: buildCandidate },
    { source: "sample_fixture", candidate_path: sampleCandidate },
  ].map((row) => {
    const candidatePath = String(row.candidate_path || "").trim();
    const resolvedPath = candidatePath ? path.resolve(candidatePath) : "";
    const exists = resolvedPath ? fs.existsSync(resolvedPath) : false;
    return {
      source: row.source,
      candidate_path: candidatePath,
      resolved_path: resolvedPath,
      exists,
    };
  });

  const selected = candidates.find((row) => row.exists && row.candidate_path);
  if (!selected) {
    throw new Error(
      `no XT-Ready audit input found (env ${envVar}, build ${buildCandidate}, sample ${sampleCandidate})`
    );
  }
  if (requireReal && selected.source === "sample_fixture") {
    throw new Error(
      `require-real enabled but selected source is sample fixture (${selected.candidate_path})`
    );
  }

  return {
    schema_version: "xt_ready_audit_input_selection.v1",
    env_var: envVar,
    require_real_audit: requireReal,
    selected_source: selected.source,
    selected_audit_json: selected.candidate_path,
    selected_audit_json_resolved: selected.resolved_path,
    candidates,
    selected_at_ms: Date.now(),
  };
}

function runCli(argv = process.argv, env = process.env) {
  const args = parseArgs(argv);
  const outJsonPath = String(args["out-json"] || "").trim();
  if (!outJsonPath) throw new Error("missing --out-json");

  const selection = resolveXtReadyAuditInput(
    {
      env_var: args["env-var"] || DEFAULT_ENV_VAR,
      build_audit_json: args["build-audit-json"] || DEFAULT_BUILD_AUDIT_JSON,
      sample_audit_json: args["sample-audit-json"] || DEFAULT_SAMPLE_AUDIT_JSON,
      require_real: String(args["require-real"] || "").trim() !== "",
    },
    env
  );

  const githubOutputPath = String(args["github-output"] || "").trim();
  writeText(path.resolve(outJsonPath), `${JSON.stringify(selection, null, 2)}\n`);
  appendGithubOutput(githubOutputPath, selection);

  console.log(
    `ok - XT-Ready audit input resolved (source=${selection.selected_source}, audit_json=${selection.selected_audit_json}, require_real=${selection.require_real_audit ? "yes" : "no"}, out=${outJsonPath})`
  );
  return selection;
}

if (require.main === module) {
  try {
    runCli(process.argv, process.env);
  } catch (err) {
    console.error(`error: ${err.message}`);
    process.exit(1);
  }
}

module.exports = {
  appendGithubOutput,
  parseArgs,
  resolveXtReadyAuditInput,
  runCli,
};
