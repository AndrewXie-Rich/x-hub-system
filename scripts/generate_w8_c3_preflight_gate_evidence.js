#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");

const REPO_ROOT = path.resolve(__dirname, "..");
const DEFAULT_OUTPUT_PATH = path.join(REPO_ROOT, "build", "reports", "w8_c3_preflight_gate_evidence.v1.json");

const SOURCE_REFS = {
  manager: "x-terminal/Sources/Supervisor/SupervisorManager.swift",
  gate: "x-terminal/Sources/Supervisor/SupervisorSkillPreflightGate.swift",
  surface: "x-terminal/Sources/Project/AXSkillGovernanceSurface.swift",
  guardrail: "x-terminal/Sources/Tools/XTGuardrailMessagePresentation.swift",
};

function safeString(value) {
  return String(value == null ? "" : value).trim();
}

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
    const current = safeString(argv[index]);
    if (!current.startsWith("--")) continue;
    const key = current.slice(2);
    const next = argv[index + 1];
    if (next && !safeString(next).startsWith("--")) {
      out[key] = String(next);
      index += 1;
    } else {
      out[key] = "1";
    }
  }
  return out;
}

function countMatches(text, pattern) {
  const matches = String(text).match(pattern);
  return Array.isArray(matches) ? matches.length : 0;
}

function includesAll(text, patterns) {
  return patterns.every((pattern) => pattern.test(text));
}

function buildRows(sources) {
  const manager = sources.manager;
  const gate = sources.gate;
  const surface = sources.surface;
  const guardrail = sources.guardrail;

  const preflightGateCount = countMatches(
    manager,
    /SupervisorSkillPreflightGate\.evaluate\(/g
  );
  const repairRouteReady = includesAll(guardrail, [
    /cleanedDenyCode == "preflight_failed" \|\| cleanedDenyCode == "preflight_quarantined"/,
    /buttonTitle: "查看技能治理"/,
    /trust root、pinned version、runner、compatibility 和 preflight/,
  ]);

  return [
    {
      case_id: "missing_bin_env_config",
      deny_code: "preflight_failed",
      gate_count: preflightGateCount,
      checks: {
        preflight_fail_closed_mainline: preflightGateCount >= 3
          && includesAll(manager, [
            /if preflightVerdict\.isBlocked \{/,
            /policySource: "skill_preflight"/,
            /status: \.blocked/,
          ]),
        missing_prereq_reason_can_flow_to_user: includesAll(gate, [
          /denyCode: "preflight_failed"/,
          /缺少可执行的包级 preflight 真相/,
          /fail-closed 阻断/,
          /parts\.append\(installHint\)/,
        ]),
        repair_surface_visible: repairRouteReady
          && includesAll(guardrail, [
            /case "preflight_failed":/,
            /这个技能的执行前检查还没通过/,
          ]),
      },
      evidence: {
        trigger_path: "CALL_SKILL -> preflight -> blocked",
        detail_channel: "preflight_result + installHint",
        repair_destination: "project_settings.skill_governance_overview",
      },
    },
    {
      case_id: "capability_grant_missing",
      deny_code: "grant_required",
      gate_count: preflightGateCount,
      checks: {
        preflight_classifies_grant_before_run: includesAll(gate, [
          /decision: \.grantRequired/,
          /denyCode: "grant_required"/,
          /运行前仍需 capability \/ grant/,
        ]),
        governance_surface_marks_grant_before_run: includesAll(surface, [
          /return \("grant required before run", \.blocked, "grant required"\)/,
          /return \("grant required before run", \.warning, "grant required"\)/,
        ]),
        guardrail_explains_grant_path: includesAll(guardrail, [
          /case "grant_required":/,
          /仍然需要先通过 Hub 授权/,
          /先在 Hub 或 Supervisor 里批准授权，再重试/,
        ]),
      },
      evidence: {
        trigger_path: "CALL_SKILL -> preflight grant required -> governed approval",
        detail_channel: "grant_required stays on governed dispatch path",
        repair_destination: "hub_or_supervisor_grant_approval",
      },
    },
    {
      case_id: "skill_quarantined",
      deny_code: "preflight_quarantined",
      gate_count: preflightGateCount,
      checks: {
        quarantine_reason_code_stable: includesAll(gate, [
          /denyCode: "preflight_quarantined"/,
          /normalizedPreflight\.contains\("quarantined"\)/,
          /summary: blockedSummary\(/,
        ]),
        governance_surface_marks_quarantine: includesAll(surface, [
          /if packageState == "quarantined" \{/,
          /return \("quarantined", \.blocked, "quarantined"\)/,
        ]),
        repair_card_visible: repairRouteReady
          && includesAll(guardrail, [
            /case "preflight_quarantined":/,
            /这个技能当前处于 quarantine，不能执行/,
            /先修复技能包或解除隔离/,
          ]),
      },
      evidence: {
        trigger_path: "CALL_SKILL / retry -> preflight quarantine -> blocked",
        detail_channel: "quarantine verdict + governance repair card",
        repair_destination: "project_settings.skill_governance_overview",
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
  const sources = {
    manager: readText(SOURCE_REFS.manager),
    gate: readText(SOURCE_REFS.gate),
    surface: readText(SOURCE_REFS.surface),
    guardrail: readText(SOURCE_REFS.guardrail),
  };
  const rows = buildRows(sources);
  const categories = {
    missing_bin_env_config: rows.some((row) => row.case_id === "missing_bin_env_config" && row.ready),
    high_risk_capability_grant_missing: rows.some((row) => row.case_id === "capability_grant_missing" && row.ready),
    skill_quarantined: rows.some((row) => row.case_id === "skill_quarantined" && row.ready),
    execute_path_preflight_gate: countMatches(sources.manager, /SupervisorSkillPreflightGate\.evaluate\(/g) >= 3,
  };
  const ready = Object.values(categories).every(Boolean);

  const payload = {
    schema_version: "xhub.w8_c3_preflight_gate_evidence.v1",
    generated_at: new Date().toISOString(),
    status: ready ? "ready" : "blocked",
    claim_scope: ["W8-C3"],
    claim: ready
      ? "Preflight is now a mandatory governed gate before first execution and retry, with fail-closed reason codes and visible repair routing."
      : "W8-C3 is still incomplete: preflight gate, reason codes, or repair routing are not yet fully wired.",
    categories,
    rows,
    source_refs: Object.values(SOURCE_REFS),
    machine_verdict: ready
      ? "PASS(preflight_gate_fail_closed_with_visible_repair)"
      : "NO_GO(preflight_gate_or_visible_repair_missing)",
  };

  writeJson(outputPath, payload);
  console.log(JSON.stringify({
    ok: ready,
    out: path.relative(REPO_ROOT, outputPath),
    rows: rows.length,
  }));
}

main();
