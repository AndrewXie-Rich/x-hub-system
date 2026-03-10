#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");

const FIXTURE_SCHEMA_VERSION = "xterminal.split_audit_fixture.v1";
const PAYLOAD_SCHEMA = "xterminal.split_audit_payload";
const PAYLOAD_VERSION = "1";
const REQUIRED_EVENT_TYPES = [
  "supervisor.split.proposed",
  "supervisor.prompt.compiled",
  "supervisor.split.confirmed",
  "supervisor.split.overridden",
  "supervisor.prompt.rejected",
  "supervisor.split.rejected"
];

const EVENT_STATE_RULES = {
  "supervisor.split.proposed": ["proposed", "blocked"],
  "supervisor.prompt.compiled": ["confirmed"],
  "supervisor.split.confirmed": ["confirmed"],
  "supervisor.split.overridden": ["overridden", "blocked"],
  "supervisor.prompt.rejected": ["blocked"],
  "supervisor.split.rejected": ["rejected"]
};

const EVENT_PAYLOAD_RULES = {
  "supervisor.split.proposed": [
    ["lane_count", false],
    ["recommended_concurrency", false],
    ["blocking_issue_count", false],
    ["blocking_issue_codes", true]
  ],
  "supervisor.prompt.compiled": [
    ["expected_lane_count", false],
    ["contract_count", false],
    ["coverage", false],
    ["can_launch", false],
    ["lint_issue_count", false]
  ],
  "supervisor.split.confirmed": [
    ["user_decision", false],
    ["lane_count", false]
  ],
  "supervisor.split.overridden": [
    ["override_count", false],
    ["override_lane_ids", false],
    ["reason", false],
    ["blocking_issue_count", false],
    ["blocking_issue_codes", true],
    ["high_risk_hard_to_soft_confirmed_count", false],
    ["high_risk_hard_to_soft_confirmed_lane_ids", true],
    ["is_replay", false]
  ],
  "supervisor.prompt.rejected": [
    ["expected_lane_count", false],
    ["contract_count", false],
    ["blocking_lint_count", false],
    ["blocking_lint_codes", false]
  ],
  "supervisor.split.rejected": [
    ["user_decision", false],
    ["reason", false]
  ]
};

function parseArgs(argv) {
  const options = {
    fixturePath: path.resolve(
      __dirname,
      "fixtures",
      "split_audit_payload_events.sample.json"
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

function isString(value) {
  return typeof value === "string";
}

function validateStringField({
  payload,
  key,
  allowEmpty,
  pathLabel,
  errors
}) {
  if (!Object.prototype.hasOwnProperty.call(payload, key)) {
    errors.push(`${pathLabel}: missing payload key '${key}'`);
    return;
  }
  const value = payload[key];
  if (!isString(value)) {
    errors.push(`${pathLabel}: payload key '${key}' must be string`);
    return;
  }
  if (!allowEmpty && value.trim().length === 0) {
    errors.push(`${pathLabel}: payload key '${key}' must not be empty`);
  }
}

function parseNonNegativeInt(raw) {
  if (!isString(raw)) {
    return null;
  }
  if (!/^\d+$/.test(raw.trim())) {
    return null;
  }
  return Number(raw.trim());
}

function parseCSV(raw) {
  if (!isString(raw)) {
    return [];
  }
  return raw
    .split(",")
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
}

function parseBoolLike(raw) {
  if (!isString(raw)) {
    return null;
  }
  const normalized = raw.trim().toLowerCase();
  if (normalized === "1" || normalized === "true" || normalized === "yes") {
    return true;
  }
  if (normalized === "0" || normalized === "false" || normalized === "no") {
    return false;
  }
  return null;
}

function createSummary() {
  return {
    event_type_counts: {},
    split_overridden: {
      event_count: 0,
      override_count_total: 0,
      blocking_issue_total: 0,
      blocking_event_count: 0,
      high_risk_hard_to_soft_confirmed_total: 0,
      replay_event_count: 0
    }
  };
}

function accumulateSplitOverriddenSummary(payload, summary) {
  summary.split_overridden.event_count += 1;

  const overrideCount = parseNonNegativeInt(payload.override_count);
  if (overrideCount !== null) {
    summary.split_overridden.override_count_total += overrideCount;
  }

  const blockingIssueCount = parseNonNegativeInt(payload.blocking_issue_count);
  if (blockingIssueCount !== null) {
    summary.split_overridden.blocking_issue_total += blockingIssueCount;
    if (blockingIssueCount > 0) {
      summary.split_overridden.blocking_event_count += 1;
    }
  }

  const highRiskConfirmedCount = parseNonNegativeInt(
    payload.high_risk_hard_to_soft_confirmed_count
  );
  if (highRiskConfirmedCount !== null) {
    summary.split_overridden.high_risk_hard_to_soft_confirmed_total += highRiskConfirmedCount;
  }

  const replay = parseBoolLike(payload.is_replay);
  if (replay === true) {
    summary.split_overridden.replay_event_count += 1;
  }
}

function validateSplitOverriddenPayload({
  payload,
  pathLabel,
  errors
}) {
  const overrideCount = parseNonNegativeInt(payload.override_count);
  const blockingIssueCount = parseNonNegativeInt(payload.blocking_issue_count);
  const highRiskConfirmedCount = parseNonNegativeInt(
    payload.high_risk_hard_to_soft_confirmed_count
  );
  const overrideLaneIds = parseCSV(payload.override_lane_ids);
  const blockingIssueCodes = parseCSV(payload.blocking_issue_codes);
  const highRiskConfirmedLaneIds = parseCSV(
    payload.high_risk_hard_to_soft_confirmed_lane_ids
  );

  if (overrideCount === null) {
    errors.push(`${pathLabel}: payload.override_count must be non-negative integer string`);
  } else if (overrideCount !== overrideLaneIds.length) {
    errors.push(
      `${pathLabel}: payload.override_count (${overrideCount}) must match override_lane_ids count (${overrideLaneIds.length})`
    );
  }

  if (blockingIssueCount === null) {
    errors.push(`${pathLabel}: payload.blocking_issue_count must be non-negative integer string`);
  } else if (blockingIssueCount !== blockingIssueCodes.length) {
    errors.push(
      `${pathLabel}: payload.blocking_issue_count (${blockingIssueCount}) must match blocking_issue_codes count (${blockingIssueCodes.length})`
    );
  }

  if (highRiskConfirmedCount === null) {
    errors.push(`${pathLabel}: payload.high_risk_hard_to_soft_confirmed_count must be non-negative integer string`);
  } else if (highRiskConfirmedCount !== highRiskConfirmedLaneIds.length) {
    errors.push(
      `${pathLabel}: payload.high_risk_hard_to_soft_confirmed_count (${highRiskConfirmedCount}) must match high_risk_hard_to_soft_confirmed_lane_ids count (${highRiskConfirmedLaneIds.length})`
    );
  }

  const replayRaw = payload.is_replay;
  if (!isString(replayRaw) || replayRaw.trim().length === 0) {
    errors.push(`${pathLabel}: payload.is_replay must be non-empty string`);
  } else {
    const normalized = replayRaw.trim().toLowerCase();
    const allowed = new Set(["0", "1", "false", "true", "no", "yes"]);
    if (!allowed.has(normalized)) {
      errors.push(`${pathLabel}: payload.is_replay must be one of 0|1|false|true|no|yes`);
    }
  }
}

function validateSplitAuditFixture(doc) {
  const errors = [];
  const summary = createSummary();
  if (!doc || typeof doc !== "object" || Array.isArray(doc)) {
    errors.push("root: fixture must be a JSON object");
    return buildResult(doc, errors, summary);
  }

  if (doc.schema_version !== FIXTURE_SCHEMA_VERSION) {
    errors.push(
      `root: schema_version must be '${FIXTURE_SCHEMA_VERSION}', got '${String(doc.schema_version || "")}'`
    );
  }

  if (!Array.isArray(doc.events)) {
    errors.push("root: events must be an array");
    return buildResult(doc, errors, summary);
  }

  const seenEventTypes = new Set();

  doc.events.forEach((event, index) => {
    const pathLabel = `events[${index}]`;
    if (!event || typeof event !== "object" || Array.isArray(event)) {
      errors.push(`${pathLabel}: event must be an object`);
      return;
    }

    const eventType = event.event_type;
    if (!isString(eventType)) {
      errors.push(`${pathLabel}: event_type must be string`);
      return;
    }
    if (!REQUIRED_EVENT_TYPES.includes(eventType)) {
      errors.push(`${pathLabel}: unsupported event_type '${eventType}'`);
      return;
    }
    seenEventTypes.add(eventType);
    summary.event_type_counts[eventType] = (summary.event_type_counts[eventType] || 0) + 1;

    const payload = event.payload;
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
      errors.push(`${pathLabel}: payload must be object`);
      return;
    }

    if (eventType === "supervisor.split.overridden") {
      accumulateSplitOverriddenSummary(payload, summary);
    }

    if (payload.payload_schema !== PAYLOAD_SCHEMA) {
      errors.push(`${pathLabel}: payload_schema must be '${PAYLOAD_SCHEMA}'`);
    }
    if (payload.payload_version !== PAYLOAD_VERSION) {
      errors.push(`${pathLabel}: payload_version must be '${PAYLOAD_VERSION}'`);
    }
    if (payload.event_type !== eventType) {
      errors.push(`${pathLabel}: payload.event_type must match event_type`);
    }

    const state = payload.state;
    const allowedStates = EVENT_STATE_RULES[eventType] || [];
    if (!isString(state) || state.trim().length === 0) {
      errors.push(`${pathLabel}: payload.state must be non-empty string`);
    } else if (!allowedStates.includes(state)) {
      errors.push(
        `${pathLabel}: payload.state '${state}' not allowed for event_type '${eventType}'`
      );
    }

    const payloadRules = EVENT_PAYLOAD_RULES[eventType] || [];
    payloadRules.forEach(([key, allowEmpty]) => {
      validateStringField({
        payload,
        key,
        allowEmpty,
        pathLabel,
        errors
      });
    });

    if (eventType === "supervisor.split.overridden") {
      validateSplitOverriddenPayload({
        payload,
        pathLabel,
        errors
      });
    }
  });

  REQUIRED_EVENT_TYPES.forEach((requiredType) => {
    if (!seenEventTypes.has(requiredType)) {
      errors.push(`root: missing required event_type '${requiredType}'`);
    }
  });

  return buildResult(doc, errors, summary);
}

function buildResult(doc, errors, summary) {
  const eventCount = Array.isArray(doc && doc.events) ? doc.events.length : 0;
  return {
    ok: errors.length === 0,
    schema_version: doc && doc.schema_version ? String(doc.schema_version) : "",
    event_count: eventCount,
    error_count: errors.length,
    summary: summary || createSummary(),
    errors
  };
}

function printHelp() {
  console.log(
    [
      "Usage:",
      "  node ./scripts/check_split_audit_fixture_contract.js [--fixture <path>] [--out-json <path>]",
      "",
      "Defaults:",
      "  --fixture ./scripts/fixtures/split_audit_payload_events.sample.json"
    ].join("\n")
  );
}

function main() {
  let options;
  try {
    options = parseArgs(process.argv);
  } catch (error) {
    console.error(`[split-audit-contract] ${error.message}`);
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
    console.error(`[split-audit-contract] failed to read fixture: ${error.message}`);
    process.exit(2);
  }

  const result = validateSplitAuditFixture(doc);
  if (options.outJson) {
    fs.mkdirSync(path.dirname(options.outJson), { recursive: true });
    fs.writeFileSync(options.outJson, JSON.stringify(result, null, 2) + "\n", "utf8");
  }

  if (!result.ok) {
    console.error(`[split-audit-contract] fixture invalid: ${options.fixturePath}`);
    result.errors.forEach((line) => {
      console.error(`- ${line}`);
    });
    process.exit(1);
  }

  const splitOverriddenSummary = result.summary && result.summary.split_overridden
    ? result.summary.split_overridden
    : {
        event_count: 0,
        override_count_total: 0,
        blocking_issue_total: 0,
        high_risk_hard_to_soft_confirmed_total: 0,
        replay_event_count: 0
      };

  console.log(
    `[split-audit-contract] ok schema=${result.schema_version} events=${result.event_count} ` +
    `split_overridden={events:${splitOverriddenSummary.event_count},override_total:${splitOverriddenSummary.override_count_total},` +
    `blocking_total:${splitOverriddenSummary.blocking_issue_total},high_risk_confirmed_total:${splitOverriddenSummary.high_risk_hard_to_soft_confirmed_total},` +
    `replay_events:${splitOverriddenSummary.replay_event_count}} file=${options.fixturePath}`
  );
}

if (require.main === module) {
  main();
}

module.exports = {
  FIXTURE_SCHEMA_VERSION,
  PAYLOAD_SCHEMA,
  PAYLOAD_VERSION,
  REQUIRED_EVENT_TYPES,
  validateSplitAuditFixture,
  readJSON
};
