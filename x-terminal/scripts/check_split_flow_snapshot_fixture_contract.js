#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");

const FIXTURE_SCHEMA_VERSION = "xterminal.split_flow_snapshot_fixture.v1";
const SNAPSHOT_SCHEMA = "xterminal.split_flow_snapshot";
const SNAPSHOT_VERSION = "1";
const STATE_MACHINE_VERSION = "xterminal.split_flow_state_machine.v1";

const FLOW_STATES = [
  "idle",
  "proposing",
  "proposed",
  "overridden",
  "confirmed",
  "rejected",
  "blocked"
];

const PROMPT_STATUSES = ["ready", "rejected"];
const AUDIT_EVENT_TYPES = [
  "supervisor.split.proposed",
  "supervisor.prompt.compiled",
  "supervisor.split.confirmed",
  "supervisor.split.overridden",
  "supervisor.prompt.rejected",
  "supervisor.split.rejected"
];

const REQUIRED_FLOW_STATES = ["proposed", "overridden", "blocked", "confirmed"];

const ALLOWED_TRANSITIONS = {
  idle: ["proposing"],
  proposing: ["proposed", "blocked"],
  proposed: ["overridden", "confirmed", "rejected", "blocked", "idle"],
  overridden: ["overridden", "proposed", "confirmed", "rejected", "blocked", "idle"],
  confirmed: ["idle"],
  rejected: ["idle"],
  blocked: ["blocked", "proposed", "overridden", "confirmed", "rejected", "idle"]
};

function parseArgs(argv) {
  const options = {
    fixturePath: path.resolve(
      __dirname,
      "fixtures",
      "split_flow_snapshot.sample.json"
    ),
    outJson: ""
  };

  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--fixture") {
      i += 1;
      options.fixturePath = path.resolve(argv[i] || "");
    } else if (arg === "--out-json") {
      i += 1;
      options.outJson = path.resolve(argv[i] || "");
    } else if (arg === "--help" || arg === "-h") {
      options.help = true;
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return options;
}

function readJSON(filePath) {
  const raw = fs.readFileSync(filePath, "utf8");
  return JSON.parse(raw);
}

function isPlainObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function isString(value) {
  return typeof value === "string";
}

function isNonNegativeInteger(value) {
  return Number.isInteger(value) && value >= 0;
}

function isUUIDString(value) {
  if (!isString(value)) {
    return false;
  }
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function isISODateString(value) {
  if (!isString(value) || value.trim().length === 0) {
    return false;
  }
  const parsed = Date.parse(value);
  return Number.isFinite(parsed);
}

function createSummary() {
  return {
    snapshot_count: 0,
    flow_state_counts: {},
    prompt_status_counts: {
      ready: 0,
      rejected: 0,
      null: 0
    },
    override_total: 0,
    blocking_snapshot_count: 0,
    unique_override_lane_id_count: 0
  };
}

function validateStringArray(value, pathLabel, errors) {
  if (!Array.isArray(value)) {
    errors.push(`${pathLabel}: must be an array`);
    return [];
  }
  const normalized = [];
  value.forEach((item, index) => {
    if (!isString(item) || item.trim().length === 0) {
      errors.push(`${pathLabel}[${index}]: must be non-empty string`);
      return;
    }
    normalized.push(item.trim());
  });
  return normalized;
}

function validateSnapshot(snapshot, pathLabel, errors, summary, uniqueLaneIDs) {
  if (!isPlainObject(snapshot)) {
    errors.push(`${pathLabel}: snapshot must be object`);
    return null;
  }

  if (snapshot.schema !== SNAPSHOT_SCHEMA) {
    errors.push(`${pathLabel}: schema must be '${SNAPSHOT_SCHEMA}'`);
  }
  if (snapshot.version !== SNAPSHOT_VERSION) {
    errors.push(`${pathLabel}: version must be '${SNAPSHOT_VERSION}'`);
  }
  if (snapshot.stateMachineVersion !== STATE_MACHINE_VERSION) {
    errors.push(`${pathLabel}: stateMachineVersion must be '${STATE_MACHINE_VERSION}'`);
  }

  if (!(snapshot.splitPlanId === null || isUUIDString(snapshot.splitPlanId))) {
    errors.push(`${pathLabel}: splitPlanId must be null or UUID string`);
  }

  if (!FLOW_STATES.includes(snapshot.flowState)) {
    errors.push(`${pathLabel}: flowState must be one of ${FLOW_STATES.join("|")}`);
  }

  if (!isNonNegativeInteger(snapshot.laneCount)) {
    errors.push(`${pathLabel}: laneCount must be non-negative integer`);
  }

  if (!(snapshot.recommendedConcurrency === null || isNonNegativeInteger(snapshot.recommendedConcurrency))) {
    errors.push(`${pathLabel}: recommendedConcurrency must be null or non-negative integer`);
  }

  if (!(snapshot.tokenBudgetTotal === null || isNonNegativeInteger(snapshot.tokenBudgetTotal))) {
    errors.push(`${pathLabel}: tokenBudgetTotal must be null or non-negative integer`);
  }

  const splitBlockingIssueCodes = validateStringArray(
    snapshot.splitBlockingIssueCodes,
    `${pathLabel}.splitBlockingIssueCodes`,
    errors
  );

  const promptStatus = Object.prototype.hasOwnProperty.call(snapshot, "promptStatus")
    ? snapshot.promptStatus
    : null;
  if (!(promptStatus === null || PROMPT_STATUSES.includes(promptStatus))) {
    errors.push(`${pathLabel}: promptStatus must be null|ready|rejected`);
  }

  const promptCoverage = Object.prototype.hasOwnProperty.call(snapshot, "promptCoverage")
    ? snapshot.promptCoverage
    : null;
  if (!(promptCoverage === null || (typeof promptCoverage === "number" && promptCoverage >= 0 && promptCoverage <= 1))) {
    errors.push(`${pathLabel}: promptCoverage must be null or number in [0,1]`);
  }

  const promptBlockingLintCodes = validateStringArray(
    snapshot.promptBlockingLintCodes,
    `${pathLabel}.promptBlockingLintCodes`,
    errors
  );

  if (!isNonNegativeInteger(snapshot.overrideCount)) {
    errors.push(`${pathLabel}: overrideCount must be non-negative integer`);
  }

  const overrideLaneIDs = validateStringArray(
    snapshot.overrideLaneIDs,
    `${pathLabel}.overrideLaneIDs`,
    errors
  );

  if (isNonNegativeInteger(snapshot.overrideCount) && snapshot.overrideCount !== overrideLaneIDs.length) {
    errors.push(
      `${pathLabel}: overrideCount (${snapshot.overrideCount}) must match overrideLaneIDs count (${overrideLaneIDs.length})`
    );
  }

  if (!(snapshot.replayConsistent === null || typeof snapshot.replayConsistent === "boolean")) {
    errors.push(`${pathLabel}: replayConsistent must be null or boolean`);
  }

  if (!(snapshot.lastAuditEventType === null || AUDIT_EVENT_TYPES.includes(snapshot.lastAuditEventType))) {
    errors.push(`${pathLabel}: lastAuditEventType must be null or known split audit event type`);
  }

  if (!(snapshot.lastAuditAt === null || isISODateString(snapshot.lastAuditAt))) {
    errors.push(`${pathLabel}: lastAuditAt must be null or ISO8601 datetime string`);
  }

  if (promptStatus === "rejected" && snapshot.flowState !== "blocked") {
    errors.push(`${pathLabel}: promptStatus=rejected requires flowState=blocked`);
  }

  if (promptStatus === "ready" && snapshot.flowState === "blocked") {
    errors.push(`${pathLabel}: promptStatus=ready must not keep flowState=blocked`);
  }

  if (snapshot.flowState === "confirmed" && promptStatus !== "ready") {
    errors.push(`${pathLabel}: flowState=confirmed requires promptStatus=ready`);
  }

  if (promptStatus === "rejected" && promptBlockingLintCodes.length === 0) {
    errors.push(`${pathLabel}: promptStatus=rejected requires promptBlockingLintCodes`);
  }

  if (promptStatus === "ready" && promptBlockingLintCodes.length > 0) {
    errors.push(`${pathLabel}: promptStatus=ready must not contain promptBlockingLintCodes`);
  }

  if (promptStatus === null && promptCoverage !== null) {
    errors.push(`${pathLabel}: promptCoverage must be null when promptStatus is null`);
  }

  if (promptStatus !== null && promptCoverage === null) {
    errors.push(`${pathLabel}: promptCoverage must be present when promptStatus is not null`);
  }

  if (splitBlockingIssueCodes.length > 0 && snapshot.flowState !== "blocked") {
    errors.push(`${pathLabel}: splitBlockingIssueCodes requires flowState=blocked`);
  }

  if (snapshot.flowState === "overridden" && snapshot.overrideCount === 0) {
    errors.push(`${pathLabel}: flowState=overridden requires overrideCount>0`);
  }

  summary.snapshot_count += 1;
  summary.flow_state_counts[snapshot.flowState] = (summary.flow_state_counts[snapshot.flowState] || 0) + 1;
  if (promptStatus === null) {
    summary.prompt_status_counts.null += 1;
  } else if (promptStatus === "ready") {
    summary.prompt_status_counts.ready += 1;
  } else if (promptStatus === "rejected") {
    summary.prompt_status_counts.rejected += 1;
  }
  if (isNonNegativeInteger(snapshot.overrideCount)) {
    summary.override_total += snapshot.overrideCount;
  }
  if (splitBlockingIssueCodes.length > 0) {
    summary.blocking_snapshot_count += 1;
  }
  overrideLaneIDs.forEach((laneID) => {
    uniqueLaneIDs.add(laneID);
  });

  return snapshot;
}

function validateTransitions(validSnapshots, errors) {
  for (let index = 1; index < validSnapshots.length; index += 1) {
    const previous = validSnapshots[index - 1];
    const current = validSnapshots[index];
    const allowed = ALLOWED_TRANSITIONS[previous.flowState] || [];
    if (!allowed.includes(current.flowState)) {
      errors.push(
        `snapshots[${index - 1} -> ${index}]: transition ${previous.flowState} -> ${current.flowState} is not allowed`
      );
    }
  }
}

function validateSplitFlowSnapshotFixture(doc) {
  const errors = [];
  const summary = createSummary();

  if (!isPlainObject(doc)) {
    errors.push("root: fixture must be a JSON object");
    return buildResult(doc, errors, summary);
  }

  if (doc.schema_version !== FIXTURE_SCHEMA_VERSION) {
    errors.push(
      `root: schema_version must be '${FIXTURE_SCHEMA_VERSION}', got '${String(doc.schema_version || "")}'`
    );
  }

  if (!Array.isArray(doc.snapshots)) {
    errors.push("root: snapshots must be an array");
    return buildResult(doc, errors, summary);
  }

  const uniqueLaneIDs = new Set();
  const validatedSnapshots = [];

  doc.snapshots.forEach((item, index) => {
    const pathLabel = `snapshots[${index}]`;
    if (!isPlainObject(item)) {
      errors.push(`${pathLabel}: item must be object`);
      return;
    }

    if (!isString(item.case_id) || item.case_id.trim().length === 0) {
      errors.push(`${pathLabel}: case_id must be non-empty string`);
    }

    const validated = validateSnapshot(
      item.snapshot,
      `${pathLabel}.snapshot`,
      errors,
      summary,
      uniqueLaneIDs
    );

    if (validated && FLOW_STATES.includes(validated.flowState)) {
      validatedSnapshots.push(validated);
    }
  });

  validateTransitions(validatedSnapshots, errors);

  REQUIRED_FLOW_STATES.forEach((requiredState) => {
    if (!summary.flow_state_counts[requiredState]) {
      errors.push(`root: missing required flowState '${requiredState}' in snapshots`);
    }
  });

  summary.unique_override_lane_id_count = uniqueLaneIDs.size;

  return buildResult(doc, errors, summary);
}

function buildResult(doc, errors, summary) {
  const snapshotCount = Array.isArray(doc && doc.snapshots) ? doc.snapshots.length : 0;
  return {
    ok: errors.length === 0,
    schema_version: doc && doc.schema_version ? String(doc.schema_version) : "",
    snapshot_count: snapshotCount,
    error_count: errors.length,
    summary: summary || createSummary(),
    errors
  };
}

function printHelp() {
  console.log(
    [
      "Usage:",
      "  node ./scripts/check_split_flow_snapshot_fixture_contract.js [--fixture <path>] [--out-json <path>]",
      "",
      "Defaults:",
      "  --fixture ./scripts/fixtures/split_flow_snapshot.sample.json"
    ].join("\n")
  );
}

function main() {
  let options;
  try {
    options = parseArgs(process.argv);
  } catch (error) {
    console.error(`[split-flow-snapshot-contract] ${error.message}`);
    process.exit(2);
  }

  if (options.help) {
    printHelp();
    process.exit(0);
  }

  let doc;
  try {
    doc = readJSON(options.fixturePath);
  } catch (error) {
    console.error(`[split-flow-snapshot-contract] failed to read fixture: ${error.message}`);
    process.exit(2);
  }

  const result = validateSplitFlowSnapshotFixture(doc);
  if (options.outJson) {
    fs.mkdirSync(path.dirname(options.outJson), { recursive: true });
    fs.writeFileSync(options.outJson, JSON.stringify(result, null, 2) + "\n", "utf8");
  }

  if (!result.ok) {
    console.error(`[split-flow-snapshot-contract] fixture invalid: ${options.fixturePath}`);
    result.errors.forEach((line) => {
      console.error(`- ${line}`);
    });
    process.exit(1);
  }

  const flowStateCounts = result.summary && result.summary.flow_state_counts
    ? result.summary.flow_state_counts
    : {};
  console.log(
    `[split-flow-snapshot-contract] ok schema=${result.schema_version} snapshots=${result.snapshot_count} ` +
      `states=${JSON.stringify(flowStateCounts)} override_total=${result.summary.override_total} ` +
      `file=${options.fixturePath}`
  );
}

if (require.main === module) {
  main();
}

module.exports = {
  FIXTURE_SCHEMA_VERSION,
  SNAPSHOT_SCHEMA,
  SNAPSHOT_VERSION,
  STATE_MACHINE_VERSION,
  REQUIRED_FLOW_STATES,
  validateSplitFlowSnapshotFixture,
  readJSON
};
