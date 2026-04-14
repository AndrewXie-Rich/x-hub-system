#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

function loadFresh(relativePath) {
  const resolved = require.resolve(relativePath);
  delete require.cache[resolved];
  return require(relativePath);
}

function withTempDir(fn) {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "xt_w3_33_update_scaffold_test."));
  try {
    fn(tempDir);
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

run("XT-W3-33 updater collects evidence refs from scaffold dirs while excluding metadata files", () => {
  withTempDir((tempDir) => {
    const updater = loadFresh("./update_xt_w3_33_require_real_capture_bundle.js");
    const scaffoldDir = path.join(tempDir, "sample");
    fs.mkdirSync(path.join(scaffoldDir, "nested"), { recursive: true });

    fs.writeFileSync(path.join(scaffoldDir, "README.md"), "readme\n", "utf8");
    fs.writeFileSync(path.join(scaffoldDir, "completion_notes.txt"), "# notes\n", "utf8");
    fs.writeFileSync(path.join(scaffoldDir, "finalize_sample.command.txt"), "cmd\n", "utf8");
    fs.writeFileSync(path.join(scaffoldDir, "sample_manifest.v1.json"), "{}\n", "utf8");
    fs.writeFileSync(path.join(scaffoldDir, "machine_readable_template.v1.json"), "{}\n", "utf8");
    fs.writeFileSync(path.join(scaffoldDir, "update_bundle.command.txt"), "cmd\n", "utf8");
    fs.writeFileSync(path.join(scaffoldDir, ".DS_Store"), "junk\n", "utf8");
    fs.writeFileSync(path.join(scaffoldDir, "capture-1.png"), "png\n", "utf8");
    fs.writeFileSync(path.join(scaffoldDir, "nested", "runtime.log"), "log\n", "utf8");

    const refs = updater.collectEvidenceRefsFromDir(scaffoldDir);
    assert.equal(refs.length, 2);
    assert.ok(refs.some((item) => String(item).endsWith("capture-1.png")));
    assert.ok(refs.some((item) => String(item).endsWith(path.join("nested", "runtime.log"))));
    assert.ok(!refs.some((item) => String(item).endsWith("sample_manifest.v1.json")));
  });
});

run("XT-W3-33 updater can derive sample id, template and evidence refs from scaffold dir", () => {
  withTempDir((tempDir) => {
    const updater = loadFresh("./update_xt_w3_33_require_real_capture_bundle.js");
    const scaffoldDir = path.join(tempDir, "sample");
    fs.mkdirSync(scaffoldDir, { recursive: true });

    fs.writeFileSync(path.join(scaffoldDir, "sample_manifest.v1.json"), JSON.stringify({
      sample_id: "xt_w3_33_rr_01_formal_tech_stack_decision_track_persists",
    }, null, 2), "utf8");
    fs.writeFileSync(path.join(scaffoldDir, "machine_readable_template.v1.json"), JSON.stringify({
      evidence_origin: "real_runtime",
      synthetic_runtime_evidence: false,
      synthetic_markers: [],
    }, null, 2), "utf8");
    fs.writeFileSync(path.join(scaffoldDir, "capture-1.png"), "png\n", "utf8");

    const applied = updater.applyScaffoldDirArgs({
      sampleId: "",
      scaffoldDir,
      evidenceDir: "",
      fromJson: "",
      evidenceRefs: [],
      setFields: {},
    });

    assert.equal(applied.sampleId, "xt_w3_33_rr_01_formal_tech_stack_decision_track_persists");
    assert.equal(applied.fromJson, path.join(scaffoldDir, "machine_readable_template.v1.json"));
    assert.ok(applied.evidenceRefs.some((item) => String(item).endsWith("capture-1.png")));
  });
});

run("XT-W3-33 updater keeps native JSON field types and rejects placeholder scaffold values", () => {
  withTempDir((tempDir) => {
    const updater = loadFresh("./update_xt_w3_33_require_real_capture_bundle.js");
    const bundle = {
      schema_version: "xhub.xt_w3_33_require_real_capture_bundle.v1",
      generated_at: "2026-03-22T10:00:00Z",
      updated_at: "2026-03-22T10:00:00Z",
      status: "ready_for_execution",
      stop_on_first_defect: true,
      execution_order: ["xt_w3_33_rr_01_formal_tech_stack_decision_track_persists"],
      samples: [
        {
          sample_id: "xt_w3_33_rr_01_formal_tech_stack_decision_track_persists",
          status: "pending",
          performed_at: "",
          success_boolean: null,
          evidence_refs: [],
          operator_notes: "",
          machine_readable_fields_to_record: [
            "decision_track_written",
            "decision_status",
            "decision_category",
            "decision_audit_ref",
            "spec_capsule_sync",
            "evidence_origin",
            "synthetic_runtime_evidence",
            "synthetic_markers",
          ],
          required_checks: [
            { field: "decision_track_written", equals: true },
            { field: "decision_status", equals: "approved" },
            { field: "decision_category", equals: "tech_stack" },
            { field: "decision_audit_ref", not_equals: "" },
            { field: "spec_capsule_sync", equals: true },
          ],
          synthetic_runtime_evidence: false,
          synthetic_markers: [],
        },
      ],
    };

    assert.throws(() => updater.updateBundle(bundle, {
      sampleId: "xt_w3_33_rr_01_formal_tech_stack_decision_track_persists",
      status: "passed",
      success: true,
      performedAt: "2026-03-22T10:05:00Z",
      evidenceRefs: ["build/reports/proof.png"],
      setFields: {
        decision_track_written: true,
        decision_status: "approved",
        decision_category: "tech_stack",
        decision_audit_ref: "<decision_audit_ref>",
        spec_capsule_sync: true,
        evidence_origin: "real_runtime",
        synthetic_runtime_evidence: false,
        synthetic_markers: [],
      },
    }, "2026-03-22T10:05:00Z"), /machine_readable_field_placeholder:decision_audit_ref/);

    const result = updater.updateBundle(bundle, {
      sampleId: "xt_w3_33_rr_01_formal_tech_stack_decision_track_persists",
      status: "passed",
      success: true,
      performedAt: "2026-03-22T10:06:00Z",
      evidenceRefs: ["build/reports/proof.png"],
      setFields: {
        decision_track_written: true,
        decision_status: "approved",
        decision_category: "tech_stack",
        decision_audit_ref: "audit_ref_01",
        spec_capsule_sync: true,
        evidence_origin: "real_runtime",
        synthetic_runtime_evidence: false,
        synthetic_markers: [],
      },
    }, "2026-03-22T10:06:00Z");

    assert.equal(result.sample.decision_track_written, true);
    assert.equal(result.sample.spec_capsule_sync, true);
    assert.deepEqual(result.sample.synthetic_markers, []);
  });
});
