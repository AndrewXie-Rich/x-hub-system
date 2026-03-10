#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const ROOT = path.resolve(__dirname, "..");
const OUT_DIR = path.resolve(ROOT, "build/reports");
const TIMEZONE = process.env.TZ || "Asia/Shanghai";
const NODE_BIN = process.execPath;

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

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function writeText(filePath, content) {
  ensureDir(path.dirname(filePath));
  fs.writeFileSync(filePath, String(content || ""), "utf8");
}

function writeJson(filePath, payload) {
  writeText(filePath, `${JSON.stringify(payload, null, 2)}\n`);
}

function readText(filePath) {
  return String(fs.readFileSync(filePath, "utf8") || "");
}

function rel(filePath) {
  return path.relative(ROOT, filePath).split(path.sep).join("/");
}

function isoNow() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
}

function countMatches(text, pattern) {
  const matches = String(text || "").match(pattern);
  return Array.isArray(matches) ? matches.length : 0;
}

const TESTS = {
  memory_agent_capsule: {
    id: "memory_agent_capsule",
    relPath: "x-hub/grpc-server/hub_grpc_server/src/memory_agent_capsule.test.js",
    logName: "xt_w3_hub_memory_agent_capsule.test.v1.log",
  },
  memory_project_lineage: {
    id: "memory_project_lineage",
    relPath: "x-hub/grpc-server/hub_grpc_server/src/memory_project_lineage.test.js",
    logName: "xt_w3_hub_memory_project_lineage.test.v1.log",
  },
  memory_markdown_view_matrix: {
    id: "memory_markdown_view_matrix",
    relPath: "x-hub/grpc-server/hub_grpc_server/src/memory_markdown_view_matrix.test.js",
    logName: "xt_w3_hub_memory_markdown_view_matrix.test.v1.log",
  },
  memory_remote_export_gate: {
    id: "memory_remote_export_gate",
    relPath: "x-hub/grpc-server/hub_grpc_server/src/memory_remote_export_gate.test.js",
    logName: "xt_w3_hub_memory_remote_export_gate.test.v1.log",
  },
  connector_ingress_authorizer: {
    id: "connector_ingress_authorizer",
    relPath: "x-hub/grpc-server/hub_grpc_server/src/connector_ingress_authorizer.test.js",
    logName: "xt_w3_hub_connector_ingress_authorizer.test.v1.log",
  },
  pairing_http_preauth_replay: {
    id: "pairing_http_preauth_replay",
    relPath: "x-hub/grpc-server/hub_grpc_server/src/pairing_http_preauth_replay.test.js",
    logName: "xt_w3_hub_pairing_http_preauth_replay.test.v1.log",
  },
  memory_agent_grant_chain: {
    id: "memory_agent_grant_chain",
    relPath: "x-hub/grpc-server/hub_grpc_server/src/memory_agent_grant_chain.test.js",
    logName: "xt_w3_hub_memory_agent_grant_chain.test.v1.log",
  },
};

const TASKS = [
  {
    taskId: "XT-W3-23",
    reportName: "xt_w3_23_hub_dependency_readiness.v1.json",
    gateVector:
      "XT-MEM-G1:hub_dependency_candidate_pass,XT-MEM-G2:hub_dependency_candidate_pass,XT-MEM-G4:hub_dependency_candidate_pass,XT-MEM-G5:hub_dependency_candidate_pass",
    statusSuffix: "hub_memory_truth_source_ready_for_xt_adapter",
    testIds: [
      "memory_agent_capsule",
      "memory_project_lineage",
      "memory_markdown_view_matrix",
      "memory_remote_export_gate",
    ],
    contractChecks: [
      {
        relPath: "x-terminal/work-orders/xt-w3-23-memory-ux-adapter-implementation-pack-v1.md",
        patterns: [
          "xt.memory_context_capsule.v1",
          "xt.memory_channel_selector.v1",
          "xt.memory_operation_request.v1",
          "xt.memory_injection_policy.v1",
          "xt.supervisor_memory_bus_event.v1",
          '"source_of_truth": "hub"',
        ],
      },
      {
        relPath: "X_MEMORY.md",
        patterns: [
          "默认 Mode 2（AI + Connectors）",
          "唯一可信核心",
        ],
      },
    ],
    dependencyDelta(results, contractOk) {
      return {
        hub_memory_capsule_api: results.memory_agent_capsule.ok ? "pass" : "fail",
        project_scope_lineage_guard: results.memory_project_lineage.ok ? "pass" : "fail",
        memory_ops_writeback_rollback_audit_chain: results.memory_markdown_view_matrix.ok ? "pass" : "fail",
        remote_export_secret_gate: results.memory_remote_export_gate.ok ? "pass" : "fail",
        contract_anchor_freeze: contractOk ? "pass" : "fail",
      };
    },
    nextAction:
      "XT-L2 may claim XT-W3-23 and wire session capsule/channel selector/memory ops/min-exposure guard to Hub APIs without creating local truth store",
    summaryText:
      "Hub memory truth-source, scope lineage, writeback/rollback audit chain, and remote export fail-closed gate are ready for XT adapter consumption.",
    evidenceAnchors: [
      "x-hub/grpc-server/hub_grpc_server/src/services.js",
      "x-hub/grpc-server/hub_grpc_server/src/db.js",
      "x-terminal/work-orders/xt-w3-23-memory-ux-adapter-implementation-pack-v1.md",
      "X_MEMORY.md",
    ],
  },
  {
    taskId: "XT-W3-24",
    reportName: "xt_w3_24_hub_dependency_readiness.v1.json",
    gateVector:
      "XT-CHAN-G2:hub_dependency_candidate_pass,XT-CHAN-G5:hub_dependency_candidate_pass,XT-MEM-G2:hub_dependency_candidate_pass,SI-G1:hub_dependency_candidate_pass,SI-G2:hub_dependency_candidate_pass,SI-G4:hub_dependency_candidate_pass",
    statusSuffix: "hub_channel_boundary_ready_for_xt_gateway_productization",
    testIds: ["connector_ingress_authorizer", "pairing_http_preauth_replay"],
    contractChecks: [
      {
        relPath: "x-terminal/work-orders/xt-w3-24-multichannel-gateway-productization-implementation-pack-v1.md",
        patterns: [
          "xt.channel_gateway_manifest.v1",
          "xt.channel_hub_boundary_policy.v1",
          '"source_of_truth": "hub"',
          "requires_grant_for_side_effects",
        ],
      },
      {
        relPath: "docs/xhub-client-modes-and-connectors-v1.md",
        patterns: [
          "默认启用 Mode 2（AI + Connectors）",
          "唯一可信核心",
          "外部动作走 Hub Connectors",
        ],
      },
    ],
    dependencyDelta(results, contractOk) {
      return {
        connector_ingress_authorizer: results.connector_ingress_authorizer.ok ? "pass" : "fail",
        replay_guard_allow_from_scope_gate: results.pairing_http_preauth_replay.ok ? "pass" : "fail",
        audit_fail_closed_and_gate_snapshot: results.connector_ingress_authorizer.ok && results.pairing_http_preauth_replay.ok ? "pass" : "fail",
        mode2_connector_boundary_anchor: contractOk ? "pass" : "fail",
      };
    },
    nextAction:
      "XT-L2/XT-L1 may claim XT-W3-24 and reuse Hub connector ingress, replay, allow_from, audit, and boundary policy baselines instead of building a second backend",
    summaryText:
      "Hub connector ingress authorizer, replay/allow_from/scope guard, and audit-backed gate snapshot are ready for channel gateway integration.",
    evidenceAnchors: [
      "x-hub/grpc-server/hub_grpc_server/src/connector_ingress_authorizer.js",
      "x-hub/grpc-server/hub_grpc_server/src/pairing_http.js",
      "x-terminal/work-orders/xt-w3-24-multichannel-gateway-productization-implementation-pack-v1.md",
      "docs/xhub-client-modes-and-connectors-v1.md",
    ],
  },
  {
    taskId: "XT-W3-25",
    reportName: "xt_w3_25_hub_dependency_readiness.v1.json",
    gateVector:
      "XT-AUTO-G2:hub_dependency_candidate_pass,XT-AUTO-G3:hub_dependency_candidate_pass,XT-AUTO-G4:hub_dependency_candidate_pass,XT-AUTO-G5:hub_dependency_candidate_pass,SI-G1:hub_dependency_candidate_pass,SI-G2:hub_dependency_candidate_pass,SI-G4:hub_dependency_candidate_pass",
    statusSuffix: "hub_automation_boundary_ready_for_xt_runner_and_takeover",
    testIds: [
      "memory_agent_grant_chain",
      "connector_ingress_authorizer",
      "pairing_http_preauth_replay",
    ],
    contractChecks: [
      {
        relPath: "x-terminal/work-orders/xt-w3-25-automation-product-gap-closure-implementation-pack-v1.md",
        patterns: [
          "Hub as sole truth source",
          "xt.automation_trigger_envelope.v1",
          "xt.automation_run_timeline.v1",
          "xt.automation_takeover_decision.v1",
          '"requires_grant": true',
        ],
      },
      {
        relPath: "docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md",
        patterns: [
          "grant_pending",
          "awaiting_instruction",
          "runtime_error",
          "audit_ref",
          "require-real",
        ],
      },
      {
        relPath: "docs/xhub-client-modes-and-connectors-v1.md",
        patterns: [
          "外部动作走 Hub Connectors",
          "Mode 2（AI+Connectors）",
        ],
      },
    ],
    dependencyDelta(results, contractOk) {
      return {
        grants_and_request_tamper_fail_closed: results.memory_agent_grant_chain.ok ? "pass" : "fail",
        connector_event_replay_and_scope_guard: results.pairing_http_preauth_replay.ok ? "pass" : "fail",
        audit_backed_ingress_gate_snapshot: results.connector_ingress_authorizer.ok ? "pass" : "fail",
        automation_truth_source_and_incident_contract: contractOk ? "pass" : "fail",
      };
    },
    nextAction:
      "XT-L2 may claim XT-W3-25-A/B/C/F and bind recipe/event/takeover/timeline flows to existing Hub grants/connectors/audit/policy truth-source rails",
    summaryText:
      "Hub grants, replay guard, audit_ref-bearing incident handling, and governed connector boundaries are ready for XT automation productization.",
    evidenceAnchors: [
      "x-hub/grpc-server/hub_grpc_server/src/memory_agent_grant_chain.test.js",
      "x-hub/grpc-server/hub_grpc_server/src/connector_ingress_authorizer.js",
      "x-hub/grpc-server/hub_grpc_server/src/pairing_http.js",
      "docs/memory-new/xhub-hub-to-xterminal-capability-gate-v1.md",
      "x-terminal/work-orders/xt-w3-25-automation-product-gap-closure-implementation-pack-v1.md",
    ],
  },
];

function runNodeTest(testConfig) {
  const absPath = path.resolve(ROOT, testConfig.relPath);
  const logPath = path.resolve(OUT_DIR, testConfig.logName);
  const startedAt = Date.now();
  const proc = spawnSync(NODE_BIN, [absPath], {
    cwd: ROOT,
    encoding: "utf8",
    env: { ...process.env, TZ: TIMEZONE },
    maxBuffer: 32 * 1024 * 1024,
  });
  const finishedAt = Date.now();
  const stdout = String(proc.stdout || "");
  const stderr = String(proc.stderr || "");
  const combined = [stdout.trimEnd(), stderr.trimEnd()].filter(Boolean).join("\n\n--- stderr ---\n\n");
  writeText(logPath, `${combined}\n`);
  return {
    id: testConfig.id,
    file: rel(absPath),
    log_ref: rel(logPath),
    ok: proc.status === 0,
    exit_code: Number.isInteger(proc.status) ? proc.status : -1,
    signal: proc.signal ? String(proc.signal) : "",
    ok_count: countMatches(stdout, /^ok - /gm),
    not_ok_count: countMatches(`${stdout}\n${stderr}`, /^not ok - /gm),
    duration_ms: Math.max(0, finishedAt - startedAt),
  };
}

function runContractCheck(check) {
  const absPath = path.resolve(ROOT, check.relPath);
  if (!fs.existsSync(absPath)) {
    return {
      file: rel(absPath),
      ok: false,
      patterns: Array.isArray(check.patterns) ? check.patterns : [],
      missing_patterns: Array.isArray(check.patterns) ? check.patterns.slice() : ["missing_file"],
    };
  }
  const text = readText(absPath);
  const patterns = Array.isArray(check.patterns) ? check.patterns : [];
  const missing = patterns.filter((pattern) => !text.includes(String(pattern)));
  return {
    file: rel(absPath),
    ok: missing.length === 0,
    patterns,
    missing_patterns: missing,
  };
}

function collectMinimalGaps(testResults, contractChecks) {
  const gaps = [];
  for (const result of Object.values(testResults)) {
    if (!result.ok) gaps.push(`hub_test_failed:${result.id}(rc=${result.exit_code})`);
  }
  for (const item of contractChecks) {
    if (!item.ok) {
      gaps.push(`contract_anchor_missing:${item.file}:${item.missing_patterns.join("|")}`);
    }
  }
  return gaps;
}

function buildTaskReport(task, allTestResults) {
  const pickedResults = {};
  for (const testId of task.testIds) {
    pickedResults[testId] = allTestResults[testId];
  }
  const contractChecks = task.contractChecks.map(runContractCheck);
  const contractOk = contractChecks.every((item) => item.ok);
  const minimalGaps = collectMinimalGaps(pickedResults, contractChecks);
  const status = minimalGaps.length === 0
    ? `delivered(${task.statusSuffix})`
    : `blocked(${task.statusSuffix}_with_minimal_gaps)`;
  const reportPath = path.resolve(OUT_DIR, task.reportName);
  const evidenceRefs = [
    ...task.testIds.map((testId) => allTestResults[testId].log_ref),
    ...task.evidenceAnchors,
  ];
  const payload = {
    schema_version: `xhub.${task.reportName.replace(/\.json$/, "").replace(/\./g, "_")}`,
    generated_at: isoNow(),
    timezone: TIMEZONE,
    lane: "Hub-L5",
    task_id: task.taskId,
    report_mode: "dependency_readiness",
    fail_closed: true,
    board_mutation: "none",
    gate_vector: task.gateVector,
    status,
    dependency_delta: task.dependencyDelta(pickedResults, contractOk),
    summary: task.summaryText,
    test_results: task.testIds.map((testId) => allTestResults[testId]),
    contract_checks: contractChecks,
    minimal_gaps: minimalGaps,
    next_owner_lane: "XT-L2",
    next_action: task.nextAction,
    evidence_refs: evidenceRefs,
  };
  writeJson(reportPath, payload);
  return {
    path: reportPath,
    report: payload,
  };
}

function buildAggregateReport(taskOutputs) {
  const allClear = taskOutputs.every((item) => Array.isArray(item.report.minimal_gaps) && item.report.minimal_gaps.length === 0);
  const payload = {
    schema_version: "xhub.hub_l5_xt_w3_dependency_delta_3line.v1",
    generated_at: isoNow(),
    timezone: TIMEZONE,
    lane: "Hub-L5",
    mode: "delta_3line_only",
    status: allClear
      ? "delivered(xt_w3_23_24_25_hub_dependencies_ready_for_xt_main)"
      : "blocked(xt_w3_hub_dependency_pack_contains_minimal_gaps)",
    dependency_delta: {
      "XT-W3-23": String(taskOutputs[0]?.report?.status || "unknown"),
      "XT-W3-24": String(taskOutputs[1]?.report?.status || "unknown"),
      "XT-W3-25": String(taskOutputs[2]?.report?.status || "unknown"),
    },
    next_action: allClear
      ? "XT-Main continues vertical_slice_first: XT-W3-23 -> XT-W3-24 -> XT-W3-25, consuming the three Hub dependency readiness reports as upstream evidence"
      : "Hub-L5 fixes remaining minimal_gaps before XT-Main consumes the dependency pack",
    evidence_refs: taskOutputs.map((item) => rel(item.path)),
    fail_closed: true,
    board_mutation: "none",
  };
  const outPath = path.resolve(OUT_DIR, "hub_l5_xt_w3_dependency_delta_3line.v1.json");
  writeJson(outPath, payload);
  return {
    path: outPath,
    report: payload,
  };
}

function main(argv = process.argv) {
  parseArgs(argv);
  ensureDir(OUT_DIR);
  const executed = {};
  for (const testConfig of Object.values(TESTS)) {
    console.log(`running ${testConfig.relPath}`);
    executed[testConfig.id] = runNodeTest(testConfig);
    console.log(
      `${executed[testConfig.id].ok ? "ok" : "not ok"} - ${testConfig.id} rc=${executed[testConfig.id].exit_code} log=${executed[testConfig.id].log_ref}`
    );
  }

  const taskOutputs = TASKS.map((task) => buildTaskReport(task, executed));
  const aggregate = buildAggregateReport(taskOutputs);

  console.log(`wrote ${rel(aggregate.path)}`);
  for (const item of taskOutputs) {
    console.log(`wrote ${rel(item.path)}`);
  }
}

if (require.main === module) {
  try {
    main(process.argv);
  } catch (err) {
    console.error(`error: ${err.message}`);
    process.exit(1);
  }
}

module.exports = {
  TASKS,
  TESTS,
  buildAggregateReport,
  buildTaskReport,
  collectMinimalGaps,
  parseArgs,
  runContractCheck,
  runNodeTest,
};
