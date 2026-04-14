const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const {
  DEFAULT_OUTPUT_PATH,
  buildSafeOnboardingReleaseEvidenceReport,
  main,
} = require("./generate_xt_w3_24_s_safe_onboarding_release_evidence.js");

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

function makeTmpFile(label, suffix = ".json") {
  const token = `${label}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  return path.join(os.tmpdir(), `xt_w3_24_s_evidence_${token}${suffix}`);
}

run("XT-W3-24-S generator builds preview-working report with bounded gaps and test commands", () => {
  const report = buildSafeOnboardingReleaseEvidenceReport({
    generatedAt: "2026-03-26T06:01:02Z",
  });

  assert.equal(report.schema_version, "xt_w3_24_s_safe_onboarding_release_evidence.v1");
  assert.equal(report.status, "preview-working");
  assert.equal(report.verification_results.length >= 4, true);
  assert.equal(report.bounded_gaps.length >= 3, true);
  assert.equal(
    report.test_commands.includes("bash x-hub-system/scripts/ci/xt_w3_24_s_safe_onboarding_gate.sh"),
    true
  );
  assert.equal(
    report.test_commands.includes("node x-hub-system/x-hub/grpc-server/hub_grpc_server/src/channel_onboarding_admin_http.test.js"),
    true
  );
  assert.equal(
    report.test_commands.includes("node x-hub-system/scripts/generate_xhub_operator_channel_recovery_report.test.js"),
    true
  );
  assert.equal(
    report.verification_results.some((item) => item.name === "operator_channel_recovery_report_highlights_missing_heartbeat_governance_visibility"),
    true
  );
});

run("XT-W3-24-S generator writes the tracked evidence packet to the requested path", () => {
  const outputPath = makeTmpFile("tracked");
  const stdout = [];

  try {
    const result = main([
      "node",
      "generate_xt_w3_24_s_safe_onboarding_release_evidence.js",
      "--out",
      outputPath,
      "--generated-at",
      "2026-03-26T06:01:02Z",
    ], {
      stdout: {
        write(chunk) {
          stdout.push(String(chunk));
        },
      },
    });

    assert.equal(path.resolve(result.outputPath), path.resolve(outputPath));
    assert.equal(path.resolve(DEFAULT_OUTPUT_PATH).endsWith("docs/open-source/evidence/xt_w3_24_s_safe_onboarding_release_evidence.v1.json"), true);
    const report = JSON.parse(fs.readFileSync(outputPath, "utf8"));
    assert.equal(report.generated_at, "2026-03-26T06:01:02Z");
    assert.equal(report.status, "preview-working");
    assert.equal(report.bounded_gaps.some((item) => item.name === "preview_support_scope_must_remain_narrow"), true);
    assert.equal(stdout.join("").includes("xt_w3_24_s_safe_onboarding_release_evidence.v1"), true);
  } finally {
    try { fs.rmSync(outputPath, { force: true }); } catch { /* ignore */ }
  }
});
