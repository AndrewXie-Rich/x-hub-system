#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");

const REPO_ROOT = path.resolve(__dirname, "..");
const DEFAULT_OUTPUT_PATH = path.join(REPO_ROOT, "build", "reports", "w8_c4_call_skill_retry_evidence.v1.json");

const SOURCE_REFS = {
  manager: "x-terminal/Sources/Supervisor/SupervisorManager.swift",
  tests: "x-terminal/Tests/SupervisorCommandGuardTests.swift",
};

function readText(relativePath) {
  return fs.readFileSync(path.join(REPO_ROOT, relativePath), "utf8");
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function parseArgs(argv) {
  const out = {};
  for (let index = 2; index < argv.length; index += 1) {
    const current = String(argv[index] || "").trim();
    if (!current.startsWith("--")) continue;
    const key = current.slice(2);
    const next = String(argv[index + 1] || "").trim();
    if (next && !next.startsWith("--")) {
      out[key] = next;
      index += 1;
    } else {
      out[key] = "1";
    }
  }
  return out;
}

function includesAll(text, patterns) {
  return patterns.every((pattern) => pattern.test(text));
}

function hasTestNamed(text, name) {
  return text.includes(`func ${name}(`);
}

function buildRows(manager, tests) {
  return [
    {
      case_id: "skill_registry_unavailable",
      deny_code: "skill_registry_unavailable",
      checks: {
        runtime_branch_present: includesAll(manager, [
          /Hub skill registry 当前不可用/,
          /denyCode: "skill_registry_unavailable"/,
          /persistBlockedSupervisorSkillCall\(/,
        ]),
        test_coverage_present: hasTestNamed(
          tests,
          "missingHubSkillRegistrySurfacesBlockedSkillActivityWithStableReason"
        ),
      },
      evidence: {
        user_surface: "blocked skill activity + visible system message",
        recovery_posture: "fail_closed_until_hub_registry_returns",
      },
    },
    {
      case_id: "skill_not_registered",
      deny_code: "skill_not_registered",
      checks: {
        runtime_branch_present: includesAll(manager, [
          /denyCode = hubRegistryAvailable \? "skill_not_registered" : "skill_registry_unavailable"/,
          /不在当前 project scope 的 Hub registry 中/,
          /persistBlockedSupervisorSkillCall\(/,
        ]),
        test_coverage_present: hasTestNamed(
          tests,
          "unregisteredSkillSurfacesBlockedSkillActivityWithStableReason"
        ),
      },
      evidence: {
        user_surface: "blocked skill activity + visible system message",
        recovery_posture: "fix_project_scope_or_pin_correct_skill",
      },
    },
    {
      case_id: "skill_mapping_missing",
      deny_code: "skill_mapping_missing",
      checks: {
        runtime_branch_present: includesAll(manager, [
          /blockedDenyCode = failure\.reasonCode == "unsupported_skill_id"/,
          /"skill_mapping_missing"/,
          /retry failed: skill mapping unavailable/,
        ]),
        test_coverage_present: hasTestNamed(
          tests,
          "retrySupervisorSkillActivityUsesFriendlyProjectNameWhenRemapFails"
        ),
      },
      evidence: {
        user_surface: "blocked skill activity",
        recovery_posture: "retry_stays_governed_and_fails_closed_when_remap_missing",
      },
    },
    {
      case_id: "payload_validation_failed",
      deny_code: "payload.required_args_missing",
      checks: {
        runtime_branch_present: includesAll(manager, [
          /payload\.required_args_missing/,
          /payload 校验失败/,
          /payload\.command_not_allowed/,
        ]),
        test_coverage_present: hasTestNamed(
          tests,
          "agentBrowserMissingSourceShowsRoutedFailureSummary"
        ) && hasTestNamed(
          tests,
          "repoTestRunRejectsUnsafeCommandOutsideGovernedAllowlist"
        ),
      },
      evidence: {
        user_surface: "routed failure summary + blocked activity",
        recovery_posture: "fix_payload_or_use_governed_allowlist",
      },
    },
    {
      case_id: "grant_resume_success",
      deny_code: "",
      checks: {
        runtime_branch_present: includesAll(manager, [
          /grant approved; resuming governed dispatch/,
          /allowPreviouslyApprovedAuthorization: true/,
          /取得 Hub 授权并恢复技能调用/,
        ]),
        test_coverage_present: hasTestNamed(
          tests,
          "agentBrowserExtractWaitsForHubGrantAndResumes"
        ),
      },
      evidence: {
        user_surface: "grant approved resume message",
        recovery_posture: "resume_original_dispatch_after_grant",
      },
    },
    {
      case_id: "governed_retry_context",
      deny_code: "",
      checks: {
        runtime_branch_present: includesAll(manager, [
          /var retried = resolution\.record/,
          /retried\.requestId = retryRequestId/,
          /resolvedSupervisorToolCallForRecord\(retried\)/,
          /jobId: retried\.jobId/,
          /planId: retried\.planId/,
          /stepId: retried\.stepId/,
        ]),
        test_coverage_present: hasTestNamed(
          tests,
          "retrySupervisorSkillActivityUsesFriendlyProjectNameWhenRequeued"
        ) && hasTestNamed(
          tests,
          "retrySupervisorSkillActivityFailsClosedAgainWhenSkillRemainsQuarantined"
        ),
      },
      evidence: {
        user_surface: "retry activity remains attached to original workflow step",
        recovery_posture: "retry_from_persisted_governed_dispatch",
      },
    },
  ].map((row) => ({
    ...row,
    ready: Object.values(row.checks).every(Boolean),
  }));
}

function main() {
  const args = parseArgs(process.argv);
  const outputPath = path.resolve(args.out || DEFAULT_OUTPUT_PATH);
  const manager = readText(SOURCE_REFS.manager);
  const tests = readText(SOURCE_REFS.tests);
  const rows = buildRows(manager, tests);

  const categories = {
    skill_registry_unavailable: rows.some((row) => row.case_id === "skill_registry_unavailable" && row.ready),
    skill_not_registered: rows.some((row) => row.case_id === "skill_not_registered" && row.ready),
    skill_mapping_missing: rows.some((row) => row.case_id === "skill_mapping_missing" && row.ready),
    payload_validation_failed: rows.some((row) => row.case_id === "payload_validation_failed" && row.ready),
    grant_resume_success: rows.some((row) => row.case_id === "grant_resume_success" && row.ready),
    retry_from_persisted_governed_dispatch: rows.some((row) => row.case_id === "governed_retry_context" && row.ready),
  };
  const ready = Object.values(categories).every(Boolean);

  const payload = {
    schema_version: "xhub.w8_c4_call_skill_retry_evidence.v1",
    generated_at: new Date().toISOString(),
    status: ready ? "ready" : "blocked",
    claim_scope: ["W8-C4"],
    claim: ready
      ? "CALL_SKILL common failures are visible, and retry / grant resume stay on governed dispatch with original workflow context preserved."
      : "W8-C4 remains incomplete: some CALL_SKILL failure surface or governed retry closure is missing.",
    categories,
    rows,
    source_refs: Object.values(SOURCE_REFS),
    machine_verdict: ready
      ? "PASS(call_skill_errors_and_governed_retry_closed)"
      : "NO_GO(call_skill_error_surface_or_retry_closure_missing)",
  };

  writeJson(outputPath, payload);
  console.log(JSON.stringify({
    ok: ready,
    out: path.relative(REPO_ROOT, outputPath),
    rows: rows.length,
  }));
}

main();
