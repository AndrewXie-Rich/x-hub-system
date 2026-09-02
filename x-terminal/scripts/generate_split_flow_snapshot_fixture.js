#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const cp = require("node:child_process");

function parseArgs(argv) {
  const rootDir = path.resolve(__dirname, "..");
  const options = {
    projectRoot: rootDir,
    output: path.resolve(rootDir, ".axcoder/reports/split_flow_snapshot.runtime.json"),
    xterminalBin: "",
    copyToSample: false,
    samplePath: path.resolve(rootDir, "scripts/fixtures/split_flow_snapshot.sample.json")
  };

  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--project-root") {
      i += 1;
      options.projectRoot = path.resolve(argv[i] || "");
    } else if (arg === "--out-json") {
      i += 1;
      options.output = path.resolve(argv[i] || "");
    } else if (arg === "--xterminal-bin") {
      i += 1;
      options.xterminalBin = path.resolve(argv[i] || "");
    } else if (arg === "--copy-to-sample") {
      options.copyToSample = true;
    } else if (arg === "--sample-path") {
      i += 1;
      options.samplePath = path.resolve(argv[i] || "");
    } else if (arg === "--help" || arg === "-h") {
      options.help = true;
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return options;
}

function printHelp() {
  console.log(
    [
      "Usage:",
      "  node ./scripts/generate_split_flow_snapshot_fixture.js [options]",
      "",
      "Options:",
      "  --project-root <path>   Workspace root passed to XTerminal",
      "  --out-json <path>       Runtime fixture output path",
      "  --xterminal-bin <path>  Use prebuilt XTerminal binary instead of `swift run`",
      "  --copy-to-sample        Canonicalize runtime fixture and overwrite sample fixture",
      "  --sample-path <path>    Sample fixture path when using --copy-to-sample",
      "  -h, --help              Show this help"
    ].join("\n")
  );
}

function resolveXTerminalCommand(options) {
  if (options.xterminalBin) {
    return {
      command: options.xterminalBin,
      args: []
    };
  }

  const localBins = [
    path.join(options.projectRoot, ".build/debug/XTerminal"),
    path.join(options.projectRoot, ".build/arm64-apple-macosx/debug/XTerminal"),
    path.join(options.projectRoot, ".build/x86_64-apple-macosx/debug/XTerminal")
  ];
  for (const candidate of localBins) {
    if (fs.existsSync(candidate)) {
      return {
        command: candidate,
        args: []
      };
    }
  }

  return {
    command: "swift",
    args: ["run", "XTerminal"]
  };
}

function runGenerator(options) {
  const commandSpec = resolveXTerminalCommand(options);
  const args = [
    ...commandSpec.args,
    "--xt-split-flow-fixture-smoke",
    "--project-root",
    options.projectRoot,
    "--out-json",
    options.output
  ];

  fs.mkdirSync(path.dirname(options.output), { recursive: true });
  const run = cp.spawnSync(commandSpec.command, args, {
    cwd: options.projectRoot,
    stdio: "inherit",
    env: process.env
  });

  if (run.status !== 0) {
    throw new Error(`split-flow fixture generation failed (exit=${String(run.status)})`);
  }
}

function readJSON(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function canonicalizeFixture(doc) {
  const snapshots = Array.isArray(doc && doc.snapshots) ? doc.snapshots : [];
  const laneMapping = new Map();
  let laneCounter = 2;

  function normalizeLaneID(raw) {
    if (typeof raw !== "string" || raw.trim().length === 0) {
      return raw;
    }
    const key = raw.trim();
    if (!laneMapping.has(key)) {
      laneMapping.set(key, `lane-${laneCounter}`);
      laneCounter += 1;
    }
    return laneMapping.get(key);
  }

  const normalizedSnapshots = snapshots.map((item, index) => {
    const snapshot = item && typeof item === "object" ? { ...(item.snapshot || {}) } : {};
    const flowState = typeof snapshot.flowState === "string" ? snapshot.flowState : "unknown";
    const promptStatus = snapshot.promptStatus === null ? null : (snapshot.promptStatus || null);
    const caseIDByState = {
      proposed: "proposed_clean",
      overridden: "overridden_with_replay",
      blocked: "blocked_by_prompt_lint",
      confirmed: "confirmed_ready"
    };

    snapshot.splitPlanId = "d1bfdb02-fc6b-4fa7-bcc6-a0328ff35083";
    snapshot.lastAuditAt = `2026-03-01T09:3${index}:00Z`;
    if (Array.isArray(snapshot.overrideLaneIDs)) {
      snapshot.overrideLaneIDs = snapshot.overrideLaneIDs.map((laneID) => normalizeLaneID(laneID));
    }
    snapshot.promptStatus = promptStatus;
    if (promptStatus === null) {
      snapshot.promptCoverage = null;
    } else if (typeof snapshot.promptCoverage !== "number") {
      snapshot.promptCoverage = 1;
    }

    return {
      case_id: caseIDByState[flowState] || `case_${index + 1}`,
      snapshot
    };
  });

  return {
    schema_version: "xterminal.split_flow_snapshot_fixture.v1",
    snapshots: normalizedSnapshots
  };
}

function writeJSON(filePath, payload) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
}

function main() {
  let options;
  try {
    options = parseArgs(process.argv);
  } catch (error) {
    console.error(`[split-flow-fixture-gen] ${error.message}`);
    process.exit(2);
  }

  if (options.help) {
    printHelp();
    process.exit(0);
  }

  try {
    runGenerator(options);
    console.log(`[split-flow-fixture-gen] runtime fixture generated: ${options.output}`);

    if (options.copyToSample) {
      const runtimeDoc = readJSON(options.output);
      const canonical = canonicalizeFixture(runtimeDoc);
      writeJSON(options.samplePath, canonical);
      console.log(`[split-flow-fixture-gen] canonical sample updated: ${options.samplePath}`);
    }
  } catch (error) {
    console.error(`[split-flow-fixture-gen] ${error.message}`);
    process.exit(1);
  }
}

if (require.main === module) {
  main();
}
