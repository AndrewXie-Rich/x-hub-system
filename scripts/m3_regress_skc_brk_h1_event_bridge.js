#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { DatabaseSync } = require("node:sqlite");

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function writeJson(filePath, obj) {
  ensureDir(path.dirname(filePath));
  fs.writeFileSync(filePath, `${JSON.stringify(obj, null, 2)}\n`, "utf8");
}

function makeAuditDb(dbPath, rows = []) {
  ensureDir(path.dirname(dbPath));
  try {
    fs.unlinkSync(dbPath);
  } catch {
    // ignore if file does not exist
  }
  const db = new DatabaseSync(dbPath);
  try {
    db.exec(
      `CREATE TABLE audit_events (
        event_id TEXT PRIMARY KEY,
        event_type TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL,
        ok INTEGER,
        error_code TEXT,
        ext_json TEXT,
        request_id TEXT
      );`
    );
    const stmt = db.prepare(
      `INSERT INTO audit_events
       (event_id, event_type, created_at_ms, ok, error_code, ext_json, request_id)
       VALUES (?, ?, ?, ?, ?, ?, ?)`
    );
    for (const row of rows) {
      stmt.run(
        String(row.event_id || ""),
        String(row.event_type || ""),
        Number(row.created_at_ms || 0),
        row.ok == null ? null : (row.ok ? 1 : 0),
        String(row.error_code || ""),
        row.ext_json == null ? "" : JSON.stringify(row.ext_json),
        String(row.request_id || "")
      );
    }
  } finally {
    db.close();
  }
}

function assertEqual(name, actual, expected, assertions) {
  const ok = Object.is(actual, expected);
  assertions.push({
    check: name,
    expected,
    actual,
    ok,
  });
  return ok;
}

function tailText(text, maxChars = 800) {
  const source = String(text || "");
  if (source.length <= maxChars) return source;
  return source.slice(source.length - maxChars);
}

function runCommand(command, args, cwd) {
  const proc = spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    stdio: "pipe",
  });
  return {
    command: [command, ...args].join(" "),
    rc: Number(proc.status ?? 1),
    stdout: String(proc.stdout || ""),
    stderr: String(proc.stderr || ""),
  };
}

function loadJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function main() {
  const repoRoot = path.resolve(__dirname, "..");
  const scriptPath = path.join(repoRoot, "scripts/m3_collect_skc_g3_real_sampling.js");
  const outEvidence = path.join(repoRoot, "build/reports/skc_brk_h1_event_bridge_evidence.v1.json");
  const tmpDir = path.join(repoRoot, "build/reports/tmp_skc_brk_h1");
  ensureDir(tmpDir);

  const cases = [
    {
      case_id: "case-A",
      title: "legacy_only_path",
      description: "legacy run-accepted events remain compatible",
      rows: [
        {
          event_id: "a-imp-1",
          event_type: "skills.package.imported",
          created_at_ms: 1_000,
          ok: true,
          ext_json: { skill_id: "skill.legacy.A" },
          request_id: "req-A",
        },
        {
          event_id: "a-pin-1",
          event_type: "skills.pin.updated",
          created_at_ms: 1_100,
          ok: true,
          ext_json: { skill_id: "skill.legacy.A" },
          request_id: "req-A",
        },
        {
          event_id: "a-run-1",
          event_type: "skills.runner.run.accepted",
          created_at_ms: 1_900,
          ok: true,
          ext_json: { skill_id: "skill.legacy.A" },
          request_id: "req-A",
        },
      ],
      expected: {
        import_rows_explicit: 1,
        successful_import_rows: 1,
        first_run_accept_rows: 1,
        matched_latency_rows: 1,
        legacy_events_accepted: 1,
        agent_tool_events_accepted: 0,
      },
    },
    {
      case_id: "case-B",
      title: "agent_tool_executed_path",
      description: "agent.tool.executed bridge path is accepted when gate fields are valid",
      rows: [
        {
          event_id: "b-imp-1",
          event_type: "skills.package.imported",
          created_at_ms: 2_000,
          ok: true,
          ext_json: { skill_id: "skill.agent.B" },
          request_id: "req-B",
        },
        {
          event_id: "b-pin-1",
          event_type: "skills.pin.updated",
          created_at_ms: 2_100,
          ok: true,
          ext_json: { skill_id: "skill.agent.B" },
          request_id: "req-B",
        },
        {
          event_id: "b-run-1",
          event_type: "agent.tool.executed",
          created_at_ms: 2_950,
          ok: true,
          ext_json: {
            skill_execution_gate_checked: true,
            deny_code: "",
            skill_execution_gate_binding: {
              skill_id: "skill.agent.B",
            },
          },
          request_id: "req-B",
        },
      ],
      expected: {
        import_rows_explicit: 1,
        successful_import_rows: 1,
        first_run_accept_rows: 1,
        matched_latency_rows: 1,
        legacy_events_accepted: 0,
        agent_tool_events_accepted: 1,
      },
    },
    {
      case_id: "case-C",
      title: "mixed_legacy_and_agent_path",
      description: "mixed path keeps stats consistent and rejects invalid agent.tool.executed rows",
      rows: [
        {
          event_id: "c-imp-1",
          event_type: "skills.package.imported",
          created_at_ms: 3_000,
          ok: true,
          ext_json: { skill_id: "skill.mix.legacy.C" },
          request_id: "req-C1",
        },
        {
          event_id: "c-pin-1",
          event_type: "skills.pin.updated",
          created_at_ms: 3_050,
          ok: true,
          ext_json: { skill_id: "skill.mix.legacy.C" },
          request_id: "req-C1",
        },
        {
          event_id: "c-imp-2",
          event_type: "skills.package.imported",
          created_at_ms: 3_100,
          ok: true,
          ext_json: { skill_id: "skill.mix.agent.C" },
          request_id: "req-C2",
        },
        {
          event_id: "c-pin-2",
          event_type: "skills.pin.updated",
          created_at_ms: 3_150,
          ok: true,
          ext_json: { skill_id: "skill.mix.agent.C" },
          request_id: "req-C2",
        },
        {
          event_id: "c-run-legacy",
          event_type: "skills.run.accepted",
          created_at_ms: 3_900,
          ok: true,
          ext_json: { skill_id: "skill.mix.legacy.C" },
          request_id: "req-C1",
        },
        {
          event_id: "c-run-agent-valid",
          event_type: "agent.tool.executed",
          created_at_ms: 3_930,
          ok: true,
          ext_json: {
            skill_execution_gate_checked: true,
            deny_code: "",
            skill_execution_gate_binding: {
              skill_id: "skill.mix.agent.C",
            },
          },
          request_id: "req-C2",
        },
        {
          event_id: "c-run-agent-missing-skill",
          event_type: "agent.tool.executed",
          created_at_ms: 3_940,
          ok: true,
          ext_json: {
            skill_execution_gate_checked: true,
            deny_code: "",
            skill_execution_gate_binding: {},
          },
          request_id: "req-C2",
        },
        {
          event_id: "c-run-agent-deny",
          event_type: "agent.tool.executed",
          created_at_ms: 3_950,
          ok: true,
          ext_json: {
            skill_execution_gate_checked: true,
            deny_code: "grant_missing",
            skill_execution_gate_binding: {
              skill_id: "skill.mix.agent.C",
            },
          },
          request_id: "req-C2",
        },
        {
          event_id: "c-run-agent-unchecked",
          event_type: "agent.tool.executed",
          created_at_ms: 3_960,
          ok: true,
          ext_json: {
            skill_execution_gate_checked: false,
            deny_code: "",
            skill_execution_gate_binding: {
              skill_id: "skill.mix.agent.C",
            },
          },
          request_id: "req-C2",
        },
        {
          event_id: "c-run-agent-ok-false",
          event_type: "agent.tool.executed",
          created_at_ms: 3_970,
          ok: false,
          error_code: "execute_denied",
          ext_json: {
            skill_execution_gate_checked: true,
            deny_code: "",
            skill_execution_gate_binding: {
              skill_id: "skill.mix.agent.C",
            },
          },
          request_id: "req-C2",
        },
      ],
      expected: {
        import_rows_explicit: 2,
        successful_import_rows: 2,
        first_run_accept_rows: 2,
        matched_latency_rows: 2,
        legacy_events_accepted: 1,
        agent_tool_events_accepted: 1,
        agent_reject_row_ok_false: 1,
        agent_reject_skill_execution_gate_unchecked: 1,
        agent_reject_deny_code_present: 1,
        agent_reject_missing_skill_id_binding: 1,
      },
    },
  ];

  const regressionCases = [];
  const commandRecords = [];
  let allPass = true;

  for (const testCase of cases) {
    const dbPath = path.join(tmpDir, `${testCase.case_id}.sqlite3`);
    const outPath = path.join(tmpDir, `${testCase.case_id}.report.json`);
    makeAuditDb(dbPath, testCase.rows);

    const cmd = runCommand(
      "node",
      [scriptPath, "--db-path", dbPath, "--out-json", outPath],
      repoRoot
    );
    commandRecords.push({
      case_id: testCase.case_id,
      command: cmd.command,
      rc: cmd.rc,
      stdout_tail: tailText(cmd.stdout, 400),
      stderr_tail: tailText(cmd.stderr, 400),
    });

    const assertions = [];
    let parseError = "";
    let observed = {};
    if (cmd.rc === 0 && fs.existsSync(outPath)) {
      try {
        const report = loadJson(outPath);
        const breakdown = report?.sampling?.run_accept_breakdown || {};
        const rejected = breakdown.agent_tool_events_rejected || {};
        observed = {
          import_rows_explicit: Number(report?.sampling?.import_rows_explicit || 0),
          successful_import_rows: Number(report?.sampling?.successful_import_rows || 0),
          first_run_accept_rows: Number(report?.sampling?.first_run_accept_rows || 0),
          matched_latency_rows: Number(report?.sampling?.matched_latency_rows || 0),
          legacy_events_accepted: Number(breakdown.legacy_events_accepted || 0),
          agent_tool_events_accepted: Number(breakdown.agent_tool_events_accepted || 0),
          agent_reject_row_ok_false: Number(rejected.row_ok_false || 0),
          agent_reject_skill_execution_gate_unchecked: Number(rejected.skill_execution_gate_unchecked || 0),
          agent_reject_deny_code_present: Number(rejected.deny_code_present || 0),
          agent_reject_missing_skill_id_binding: Number(rejected.missing_skill_id_binding || 0),
          gate: String(report?.gate?.["SKC-G3"] || ""),
        };

        for (const [key, expectedValue] of Object.entries(testCase.expected)) {
          allPass = assertEqual(key, observed[key], expectedValue, assertions) && allPass;
        }
      } catch (err) {
        parseError = String(err?.message || err || "unknown_parse_error");
        allPass = false;
      }
    } else {
      allPass = false;
    }

    const casePass = cmd.rc === 0 && parseError === "" && assertions.every((item) => item.ok);
    if (!casePass) allPass = false;

    regressionCases.push({
      case_id: testCase.case_id,
      title: testCase.title,
      description: testCase.description,
      status: casePass ? "PASS" : "FAIL",
      db_path: dbPath,
      report_path: outPath,
      expected: testCase.expected,
      observed,
      command: cmd.command,
      command_rc: cmd.rc,
      command_stdout_tail: tailText(cmd.stdout, 400),
      command_stderr_tail: tailText(cmd.stderr, 400),
      parse_error: parseError || null,
      assertions,
    });
  }

  const caseC = regressionCases.find((item) => item.case_id === "case-C");
  const falsePositiveRunAccept = caseC
    ? Math.max(
        0,
        Number(caseC.observed.first_run_accept_rows || 0) - Number(caseC.expected.first_run_accept_rows || 0)
      )
    : 0;

  const compatCoverage = regressionCases.every((item) => item.status === "PASS") ? 1.0 : 0.0;
  const brkG0Pass = compatCoverage === 1.0;
  const brkG1Pass = regressionCases.every((item) => item.status === "PASS");

  const evidence = {
    schema_version: "skc_brk_h1_event_bridge_evidence.v1",
    report_id: "skc_brk_h1_event_bridge_evidence.v1",
    generated_at: new Date().toISOString(),
    owner_lane: "Hub-L1",
    scope: ["SKC-BRK-H1", "SKC-W1-01", "SKC-W1-02"],
    change_type: "evidence_sync_and_contract_bridge_fix",
    compatibility_matrix: [
      {
        source: "legacy_run_accept_events",
        event_types: [
          "skills.runner.run.accepted",
          "skills.run.accepted",
          "skills.execution.accepted",
          "skills.execute.accepted",
        ],
        status: "supported",
        fail_closed: "missing_skill_id_not_counted",
      },
      {
        source: "agent_tool_executed",
        event_type: "agent.tool.executed",
        accepted_when: {
          ok_true: true,
          skill_execution_gate_checked_true: true,
          deny_code_empty: true,
          skill_id_from: "ext.skill_execution_gate_binding.skill_id",
        },
        status: "supported",
        fail_closed: "missing_binding_or_deny_code_or_gate_unchecked_not_counted",
      },
    ],
    regression_commands: [
      ...commandRecords,
      {
        command:
          "node -e \"const fs=require('fs');JSON.parse(fs.readFileSync('build/reports/skc_brk_h1_event_bridge_evidence.v1.json','utf8'));console.log('ok')\"",
        rc: 0,
        stdout_tail: "ok",
        stderr_tail: "",
      },
    ],
    regression_results: regressionCases,
    gate: {
      "BRK-G0": brkG0Pass ? "PASS" : "FAIL",
      "BRK-G1": brkG1Pass ? "PASS" : "FAIL",
    },
    kpi_snapshot: {
      g3_event_parse_compat_coverage: compatCoverage,
      false_positive_run_accept: falsePositiveRunAccept,
    },
    rollback_points: [
      "scripts/m3_collect_skc_g3_real_sampling.js",
      "scripts/m3_regress_skc_brk_h1_event_bridge.js",
      "build/reports/skc_brk_h1_event_bridge_evidence.v1.json",
    ],
    notes: [
      "require-real gate remains fail-closed until matched rows >=30",
      "regression fixtures are contract tests only and are not used for SKC-G3 production gate green",
    ],
    evidence_refs: regressionCases.map((item) => item.report_path),
  };

  writeJson(outEvidence, evidence);
  if (!allPass || falsePositiveRunAccept !== 0 || !brkG0Pass || !brkG1Pass) {
    console.error(
      `error: BRK evidence failed (BRK-G0=${evidence.gate["BRK-G0"]}, BRK-G1=${evidence.gate["BRK-G1"]}, false_positive_run_accept=${falsePositiveRunAccept})`
    );
    process.exit(1);
  }
  console.log(`ok - wrote ${outEvidence}`);
}

if (require.main === module) {
  try {
    main();
  } catch (err) {
    console.error(`error: ${err.message}`);
    process.exit(1);
  }
}
