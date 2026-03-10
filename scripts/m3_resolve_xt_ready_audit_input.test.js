#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const {
  resolveXtReadyAuditInput,
} = require("./m3_resolve_xt_ready_audit_input.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (err) {
    console.error(`not ok - ${name}`);
    throw err;
  }
}

function makeTmpDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "xt_ready_resolve_input_"));
}

function writeJson(filePath, payload = {}) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
}

run("resolver falls back to sample fixture when real audit export is missing", () => {
  const tmp = makeTmpDir();
  const samplePath = path.join(tmp, "fixtures/xt_ready_audit_events.sample.json");
  const buildPath = path.join(tmp, "build/xt_ready_audit_export.json");
  writeJson(samplePath, { events: [] });

  const out = resolveXtReadyAuditInput(
    {
      env_var: "XT_READY_AUDIT_EXPORT_JSON",
      build_audit_json: buildPath,
      sample_audit_json: samplePath,
    },
    {}
  );
  assert.equal(out.selected_source, "sample_fixture");
  assert.equal(out.selected_audit_json, samplePath);
});

run("resolver prefers env audit export over build and sample", () => {
  const tmp = makeTmpDir();
  const envPath = path.join(tmp, "real/xt_ready_audit_export_env.json");
  const buildPath = path.join(tmp, "build/xt_ready_audit_export.json");
  const samplePath = path.join(tmp, "fixtures/xt_ready_audit_events.sample.json");
  writeJson(envPath, { events: [] });
  writeJson(buildPath, { events: [] });
  writeJson(samplePath, { events: [] });

  const out = resolveXtReadyAuditInput(
    {
      env_var: "XT_READY_AUDIT_EXPORT_JSON",
      build_audit_json: buildPath,
      sample_audit_json: samplePath,
    },
    { XT_READY_AUDIT_EXPORT_JSON: envPath }
  );
  assert.equal(out.selected_source, "real_audit_export_env");
  assert.equal(out.selected_audit_json, envPath);
});

run("resolver fails closed when require-real is enabled and only sample exists", () => {
  const tmp = makeTmpDir();
  const samplePath = path.join(tmp, "fixtures/xt_ready_audit_events.sample.json");
  writeJson(samplePath, { events: [] });
  assert.throws(
    () => resolveXtReadyAuditInput(
      {
        env_var: "XT_READY_AUDIT_EXPORT_JSON",
        build_audit_json: path.join(tmp, "build/missing.json"),
        sample_audit_json: samplePath,
        require_real: true,
      },
      {}
    ),
    /require-real enabled/
  );
});

run("resolver CLI writes selection report and github output", () => {
  const tmp = makeTmpDir();
  const samplePath = path.join(tmp, "fixtures/xt_ready_audit_events.sample.json");
  const outJson = path.join(tmp, "build/xt_ready_evidence_source.json");
  const githubOutput = path.join(tmp, "build/github_output.txt");
  writeJson(samplePath, { events: [] });

  const proc = spawnSync(
    process.execPath,
    [
      path.resolve(__dirname, "m3_resolve_xt_ready_audit_input.js"),
      "--sample-audit-json", samplePath,
      "--build-audit-json", path.join(tmp, "build/missing.json"),
      "--out-json", outJson,
      "--github-output", githubOutput,
    ],
    { encoding: "utf8", env: { ...process.env } }
  );
  assert.equal(proc.status, 0, proc.stderr || proc.stdout);

  const selection = JSON.parse(fs.readFileSync(outJson, "utf8"));
  assert.equal(selection.selected_source, "sample_fixture");
  assert.equal(selection.selected_audit_json, samplePath);

  const ghText = String(fs.readFileSync(githubOutput, "utf8") || "");
  assert.ok(ghText.includes(`selected_audit_json=${samplePath}`));
  assert.ok(ghText.includes("selected_source=sample_fixture"));
});
