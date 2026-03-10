#!/usr/bin/env node
"use strict";

const path = require("node:path");

const {
  validateSplitFlowSnapshotFixture,
  readJSON
} = require("./check_split_flow_snapshot_fixture_contract.js");

function parseArgs(argv) {
  const rootDir = path.resolve(__dirname, "..");
  const options = {
    generated: path.resolve(rootDir, ".axcoder/reports/split_flow_snapshot.runtime.json"),
    sample: path.resolve(rootDir, "scripts/fixtures/split_flow_snapshot.sample.json")
  };

  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--generated") {
      i += 1;
      options.generated = path.resolve(argv[i] || "");
    } else if (arg === "--sample") {
      i += 1;
      options.sample = path.resolve(argv[i] || "");
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
      "  node ./scripts/check_split_flow_snapshot_generation_regression.js [options]",
      "",
      "Options:",
      "  --generated <path>   Generated runtime fixture",
      "  --sample <path>      Canonical sample fixture",
      "  -h, --help           Show this help"
    ].join("\n")
  );
}

function normalize(doc) {
  const snapshots = Array.isArray(doc && doc.snapshots) ? doc.snapshots : [];
  return snapshots.map((item) => {
    const snapshot = (item && item.snapshot) || {};
    const promptStatus = snapshot.promptStatus === undefined ? null : snapshot.promptStatus;
    return {
      flowState: snapshot.flowState || null,
      promptStatus,
      promptCoveragePresent: snapshot.promptCoverage !== null && snapshot.promptCoverage !== undefined,
      promptBlockingLintCount: Array.isArray(snapshot.promptBlockingLintCodes)
        ? snapshot.promptBlockingLintCodes.length
        : -1,
      splitBlockingIssueCount: Array.isArray(snapshot.splitBlockingIssueCodes)
        ? snapshot.splitBlockingIssueCodes.length
        : -1,
      overrideCount: Number.isInteger(snapshot.overrideCount) ? snapshot.overrideCount : -1,
      overrideLaneCount: Array.isArray(snapshot.overrideLaneIDs) ? snapshot.overrideLaneIDs.length : -1,
      auditType: snapshot.lastAuditEventType || null,
      replayConsistent: snapshot.replayConsistent === undefined ? null : snapshot.replayConsistent
    };
  });
}

function compareNormalized(generatedNormalized, sampleNormalized) {
  const generatedRaw = JSON.stringify(generatedNormalized);
  const sampleRaw = JSON.stringify(sampleNormalized);
  if (generatedRaw === sampleRaw) {
    return { ok: true, message: "normalized runtime fixture matches sample" };
  }

  return {
    ok: false,
    message: [
      "normalized runtime fixture mismatch",
      `generated=${generatedRaw}`,
      `sample=${sampleRaw}`
    ].join(" :: ")
  };
}

function main() {
  let options;
  try {
    options = parseArgs(process.argv);
  } catch (error) {
    console.error(`[split-flow-gen-regression] ${error.message}`);
    process.exit(2);
  }

  if (options.help) {
    printHelp();
    process.exit(0);
  }

  const generatedDoc = readJSON(options.generated);
  const sampleDoc = readJSON(options.sample);

  const generatedValidation = validateSplitFlowSnapshotFixture(generatedDoc);
  const sampleValidation = validateSplitFlowSnapshotFixture(sampleDoc);
  if (!generatedValidation.ok) {
    console.error("[split-flow-gen-regression] generated fixture is invalid");
    generatedValidation.errors.forEach((line) => {
      console.error(`- ${line}`);
    });
    process.exit(1);
  }
  if (!sampleValidation.ok) {
    console.error("[split-flow-gen-regression] sample fixture is invalid");
    sampleValidation.errors.forEach((line) => {
      console.error(`- ${line}`);
    });
    process.exit(1);
  }

  const generatedNormalized = normalize(generatedDoc);
  const sampleNormalized = normalize(sampleDoc);
  const compareResult = compareNormalized(generatedNormalized, sampleNormalized);

  if (!compareResult.ok) {
    console.error(`[split-flow-gen-regression] ${compareResult.message}`);
    process.exit(1);
  }

  console.log(
    `[split-flow-gen-regression] ok generated=${options.generated} sample=${options.sample}`
  );
}

if (require.main === module) {
  main();
}
