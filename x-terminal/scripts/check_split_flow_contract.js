#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const XT_ROOT = path.resolve(__dirname, "..");

function parseArgs(argv) {
  const args = {
    snapshotSource: path.join(XT_ROOT, "Sources/Supervisor/SplitFlowSnapshotContract.swift"),
    stateSource: path.join(XT_ROOT, "Sources/Supervisor/TaskDecomposition/Task.swift"),
    outJson: null
  };

  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    switch (token) {
      case "--snapshot-source":
        args.snapshotSource = path.resolve(argv[++i]);
        break;
      case "--state-source":
        args.stateSource = path.resolve(argv[++i]);
        break;
      case "--out-json":
        args.outJson = path.resolve(argv[++i]);
        break;
      case "--help":
      case "-h":
        printHelp();
        process.exit(0);
      default:
        throw new Error(`unknown argument: ${token}`);
    }
  }

  return args;
}

function printHelp() {
  console.log(
    "Usage: node scripts/check_split_flow_contract.js [options]\n\n" +
      "Options:\n" +
      "  --snapshot-source <path>  SplitFlowSnapshot source file\n" +
      "  --state-source <path>     SplitProposalFlowState source file\n" +
      "  --out-json <path>         Write machine-readable report\n" +
      "  -h, --help                Show this help\n"
  );
}

function readFileOrThrow(filePath) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`missing file: ${filePath}`);
  }
  return fs.readFileSync(filePath, "utf8");
}

function runChecks(snapshotSource, stateSource) {
  const checks = [];

  const checkContains = (source, pattern, id, message) => {
    const ok = source.includes(pattern);
    checks.push({ id, ok, message, pattern });
    return ok;
  };

  checkContains(
    snapshotSource,
    'static let schema = "xterminal.split_flow_snapshot"',
    "snapshot_schema",
    "SplitFlowSnapshot schema is pinned"
  );
  checkContains(
    snapshotSource,
    'static let version = "1"',
    "snapshot_version",
    "SplitFlowSnapshot version is pinned"
  );
  checkContains(
    stateSource,
    'static let stateMachineVersion = "xterminal.split_flow_state_machine.v1"',
    "state_machine_version",
    "SplitProposalFlowState state machine version is pinned"
  );

  const requiredSnapshotFields = [
    "var splitPlanId: UUID?",
    "var flowState: SplitProposalFlowState",
    "var laneCount: Int",
    "var recommendedConcurrency: Int?",
    "var tokenBudgetTotal: Int?",
    "var splitBlockingIssueCodes: [String]",
    "var promptStatus: PromptCompilationStatus?",
    "var promptCoverage: Double?",
    "var promptBlockingLintCodes: [String]",
    "var overrideCount: Int",
    "var overrideLaneIDs: [String]",
    "var replayConsistent: Bool?",
    "var lastAuditEventType: SplitAuditEventType?",
    "var lastAuditAt: Date?"
  ];

  for (const field of requiredSnapshotFields) {
    checkContains(
      snapshotSource,
      field,
      `snapshot_field_${field.replace(/[^a-zA-Z0-9]+/g, "_").toLowerCase()}`,
      `SplitFlowSnapshot exposes field: ${field}`
    );
  }

  const requiredTransitions = [
    ".idle: [.proposing]",
    ".proposing: [.proposed, .blocked]",
    ".proposed: [.overridden, .confirmed, .rejected, .blocked, .idle]",
    ".overridden: [.overridden, .proposed, .confirmed, .rejected, .blocked, .idle]",
    ".confirmed: [.idle]",
    ".rejected: [.idle]",
    ".blocked: [.blocked, .proposed, .overridden, .confirmed, .rejected, .idle]"
  ];

  for (const transition of requiredTransitions) {
    checkContains(
      stateSource,
      transition,
      `state_transition_${transition.replace(/[^a-zA-Z0-9]+/g, "_").toLowerCase()}`,
      `SplitProposalFlowState transition exists: ${transition}`
    );
  }

  checkContains(
    snapshotSource,
    "func splitFlowSnapshot() -> SplitFlowSnapshot",
    "snapshot_export_method",
    "SupervisorOrchestrator exposes splitFlowSnapshot()"
  );

  checkContains(
    snapshotSource,
    "return SplitFlowSnapshot(",
    "snapshot_builder",
    "splitFlowSnapshot() returns SplitFlowSnapshot"
  );

  return {
    checks,
    requiredSnapshotFieldCount: requiredSnapshotFields.length,
    requiredTransitionCount: requiredTransitions.length
  };
}

function renderConsoleSummary(report) {
  const passCount = report.checks.filter((item) => item.ok).length;
  const failCount = report.checks.length - passCount;
  const status = failCount === 0 ? "PASS" : "FAIL";

  console.log(
    `[split-flow-contract] ${status} checks=${report.checks.length} pass=${passCount} fail=${failCount}`
  );

  if (failCount > 0) {
    for (const item of report.checks.filter((candidate) => !candidate.ok)) {
      console.error(`[split-flow-contract] missing: ${item.message}`);
    }
  }
}

function writeJsonReport(outputPath, report) {
  const payload = {
    schema_version: "split_flow_contract_report.v1",
    checked_at: new Date().toISOString(),
    status: report.checks.every((item) => item.ok) ? "pass" : "fail",
    snapshot_source: report.snapshotSource,
    state_source: report.stateSource,
    summary: {
      snapshot_schema: "xterminal.split_flow_snapshot",
      snapshot_version: "1",
      state_machine_version: "xterminal.split_flow_state_machine.v1",
      required_snapshot_field_count: report.requiredSnapshotFieldCount,
      required_state_transition_count: report.requiredTransitionCount,
      pass_count: report.checks.filter((item) => item.ok).length,
      fail_count: report.checks.filter((item) => !item.ok).length
    },
    checks: report.checks.map((item) => ({
      id: item.id,
      status: item.ok ? "pass" : "fail",
      message: item.message
    }))
  };

  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const snapshotSource = readFileOrThrow(args.snapshotSource);
  const stateSource = readFileOrThrow(args.stateSource);

  const result = runChecks(snapshotSource, stateSource);
  const report = {
    snapshotSource: args.snapshotSource,
    stateSource: args.stateSource,
    ...result
  };

  renderConsoleSummary(report);
  if (args.outJson) {
    writeJsonReport(args.outJson, report);
  }

  const ok = report.checks.every((item) => item.ok);
  process.exit(ok ? 0 : 1);
}

try {
  main();
} catch (error) {
  console.error(`[split-flow-contract] fatal: ${error.message}`);
  process.exit(2);
}
