#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");

const FIXTURE_SCHEMA_VERSION = "xterminal.skills_xt_l1_contract_fixture.v1";
const CONTRACT_SCHEMA = "xterminal.skills_xt_l1_contract.v1";
const CONTRACT_VERSION = "1";

const REQUIRED_WORK_ORDER_IDS = ["SKC-W1-02", "SKC-W2-05", "SKC-W4-11"];
const REQUIRED_CASE_IDS = [
  "search_import_pin_project_success",
  "preflight_missing_bin_env_config",
  "capability_missing_grant_pending",
  "hot_update_failure_rollback",
  "runner_network_or_path_violation"
];
const REQUIRED_GATES = ["SKC-G1", "SKC-G3", "SKC-G4"];
const REQUIRED_CHAIN = ["ingress", "risk_classify", "policy", "grant", "execute", "audit"];

const ALLOWED_RISK_TIERS = new Set(["low", "medium", "high"]);
const ALLOWED_PREFLIGHT_STATUS = new Set(["pass", "fail"]);
const ALLOWED_BIN_ENV_CONFIG_STATUS = new Set(["pass", "fail"]);
const ALLOWED_CAPABILITY_STATUS = new Set(["pass", "fail", "grant_pending"]);
const ALLOWED_RUNNER_NETWORK_POLICY = new Set(["hub_only", "blocked_all", "allow_internal"]);
const ALLOWED_CAPABILITY_MODE = new Set(["enforced"]);
const ALLOWED_FINAL_STATES = new Set(["pass", "blocked", "rollback_applied"]);

const SECRET_PATTERNS = [
  /sk-[A-Za-z0-9]{10,}/,
  /AKIA[0-9A-Z]{16}/,
  /AIza[0-9A-Za-z\-_]{20,}/
];

function parseArgs(argv) {
  const options = {
    fixturePath: path.resolve(__dirname, "fixtures", "skills_xt_l1_contract.sample.json"),
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
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function isPlainObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function isNonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function normalizeString(value) {
  return isNonEmptyString(value) ? value.trim() : "";
}

function uniqueStrings(value, pathLabel, errors) {
  if (!Array.isArray(value)) {
    errors.push(`${pathLabel}: must be an array`);
    return [];
  }
  const output = [];
  const seen = new Set();
  value.forEach((item, index) => {
    if (!isNonEmptyString(item)) {
      errors.push(`${pathLabel}[${index}]: must be non-empty string`);
      return;
    }
    const normalized = item.trim();
    if (seen.has(normalized)) {
      errors.push(`${pathLabel}[${index}]: duplicated value '${normalized}'`);
      return;
    }
    seen.add(normalized);
    output.push(normalized);
  });
  return output;
}

function validateThresholds(contract, errors) {
  const thresholds = contract.kpi_thresholds;
  if (!isPlainObject(thresholds)) {
    errors.push("contract.kpi_thresholds: must be object");
    return null;
  }

  const importP95 = Number(thresholds.import_to_first_run_p95_ms);
  const firstRunSuccess = Number(thresholds.skill_first_run_success_rate);
  const preflightFpr = Number(thresholds.preflight_false_positive_rate);

  if (!Number.isFinite(importP95) || importP95 <= 0) {
    errors.push("contract.kpi_thresholds.import_to_first_run_p95_ms: must be positive number");
  }
  if (!Number.isFinite(firstRunSuccess) || firstRunSuccess < 0 || firstRunSuccess > 1) {
    errors.push("contract.kpi_thresholds.skill_first_run_success_rate: must be number in [0,1]");
  }
  if (!Number.isFinite(preflightFpr) || preflightFpr < 0 || preflightFpr > 1) {
    errors.push("contract.kpi_thresholds.preflight_false_positive_rate: must be number in [0,1]");
  }

  return {
    import_to_first_run_p95_ms: importP95,
    skill_first_run_success_rate: firstRunSuccess,
    preflight_false_positive_rate: preflightFpr
  };
}

function validateContract(doc, errors) {
  if (!isPlainObject(doc.contract)) {
    errors.push("contract: must be object");
    return null;
  }
  const contract = doc.contract;

  if (contract.schema !== CONTRACT_SCHEMA) {
    errors.push(`contract.schema: must be '${CONTRACT_SCHEMA}'`);
  }
  if (contract.version !== CONTRACT_VERSION) {
    errors.push(`contract.version: must be '${CONTRACT_VERSION}'`);
  }
  if (normalizeString(contract.lane_owner) !== "XT-L1") {
    errors.push("contract.lane_owner: must be 'XT-L1'");
  }

  const workOrderIDs = uniqueStrings(contract.work_order_ids, "contract.work_order_ids", errors);
  REQUIRED_WORK_ORDER_IDS.forEach((id) => {
    if (!workOrderIDs.includes(id)) {
      errors.push(`contract.work_order_ids: missing required work order '${id}'`);
    }
  });

  const requiredChain = uniqueStrings(contract.required_chain, "contract.required_chain", errors);
  REQUIRED_CHAIN.forEach((stage, index) => {
    if (requiredChain[index] !== stage) {
      errors.push(`contract.required_chain: must keep canonical order '${REQUIRED_CHAIN.join(" -> ")}'`);
    }
  });

  const featureFlags = uniqueStrings(contract.feature_flags, "contract.feature_flags", errors);
  if (featureFlags.length < 4) {
    errors.push("contract.feature_flags: must include import/preflight/runner/hot_reload flags");
  }

  if (!isPlainObject(contract.runner_policy_snapshot)) {
    errors.push("contract.runner_policy_snapshot: must be object");
  } else {
    if (!isNonEmptyString(contract.runner_policy_snapshot.path)) {
      errors.push("contract.runner_policy_snapshot.path: must be non-empty string");
    }
    if (!isNonEmptyString(contract.runner_policy_snapshot.rollback_switch)) {
      errors.push("contract.runner_policy_snapshot.rollback_switch: must be non-empty string");
    }
  }

  const thresholds = validateThresholds(contract, errors);

  return {
    thresholds,
    requiredChain,
    workOrderIDs
  };
}

function validateGateAssertions(doc, errors) {
  if (!Array.isArray(doc.gate_assertions)) {
    errors.push("gate_assertions: must be an array");
    return { allPass: false };
  }

  const gateMap = new Map();
  doc.gate_assertions.forEach((item, index) => {
    const pathLabel = `gate_assertions[${index}]`;
    if (!isPlainObject(item)) {
      errors.push(`${pathLabel}: must be object`);
      return;
    }
    const gate = normalizeString(item.gate);
    const status = normalizeString(item.status);
    const evidence = normalizeString(item.evidence);

    if (!isNonEmptyString(gate)) {
      errors.push(`${pathLabel}.gate: must be non-empty string`);
      return;
    }
    if (!isNonEmptyString(status)) {
      errors.push(`${pathLabel}.status: must be non-empty string`);
      return;
    }
    if (!isNonEmptyString(evidence)) {
      errors.push(`${pathLabel}.evidence: must be non-empty string`);
    }

    if (gateMap.has(gate)) {
      errors.push(`${pathLabel}.gate: duplicated gate '${gate}'`);
    }
    gateMap.set(gate, status);
  });

  let allPass = true;
  REQUIRED_GATES.forEach((gate) => {
    const status = gateMap.get(gate);
    if (!status) {
      errors.push(`gate_assertions: missing required gate '${gate}'`);
      allPass = false;
      return;
    }
    if (status !== "pass") {
      errors.push(`gate_assertions: gate '${gate}' must be pass, got '${status}'`);
      allPass = false;
    }
  });

  return { allPass };
}

function validatePreflightChecks(checks, pathLabel, errors) {
  if (!isPlainObject(checks)) {
    errors.push(`${pathLabel}: must be object`);
    return null;
  }

  const bin = normalizeString(checks.bin);
  const env = normalizeString(checks.env);
  const config = normalizeString(checks.config);
  const capabilities = normalizeString(checks.capabilities);

  if (!ALLOWED_BIN_ENV_CONFIG_STATUS.has(bin)) {
    errors.push(`${pathLabel}.bin: must be pass|fail`);
  }
  if (!ALLOWED_BIN_ENV_CONFIG_STATUS.has(env)) {
    errors.push(`${pathLabel}.env: must be pass|fail`);
  }
  if (!ALLOWED_BIN_ENV_CONFIG_STATUS.has(config)) {
    errors.push(`${pathLabel}.config: must be pass|fail`);
  }
  if (!ALLOWED_CAPABILITY_STATUS.has(capabilities)) {
    errors.push(`${pathLabel}.capabilities: must be pass|fail|grant_pending`);
  }

  return { bin, env, config, capabilities };
}

function validateFixCards(fixCards, pathLabel, errors) {
  if (!Array.isArray(fixCards)) {
    errors.push(`${pathLabel}: must be an array`);
    return [];
  }

  const kinds = [];

  fixCards.forEach((card, index) => {
    const cardPath = `${pathLabel}[${index}]`;
    if (!isPlainObject(card)) {
      errors.push(`${cardPath}: must be object`);
      return;
    }

    const id = normalizeString(card.id);
    const kind = normalizeString(card.kind);
    const title = normalizeString(card.title);
    const shellCommand = normalizeString(card.shell_command);

    if (!isNonEmptyString(id)) {
      errors.push(`${cardPath}.id: must be non-empty string`);
    }
    if (!isNonEmptyString(kind)) {
      errors.push(`${cardPath}.kind: must be non-empty string`);
    }
    if (!isNonEmptyString(title)) {
      errors.push(`${cardPath}.title: must be non-empty string`);
    }
    if (!isNonEmptyString(shellCommand)) {
      errors.push(`${cardPath}.shell_command: must be non-empty string`);
    }

    if (!Array.isArray(card.expected_exit_codes) || card.expected_exit_codes.length === 0) {
      errors.push(`${cardPath}.expected_exit_codes: must be non-empty array`);
    } else {
      card.expected_exit_codes.forEach((code, codeIndex) => {
        if (!Number.isInteger(code)) {
          errors.push(`${cardPath}.expected_exit_codes[${codeIndex}]: must be integer`);
        }
      });
    }

    if (typeof card.requires_secret_input !== "boolean") {
      errors.push(`${cardPath}.requires_secret_input: must be boolean`);
    }

    if (normalizeString(card.redaction_policy) !== "mask_secrets") {
      errors.push(`${cardPath}.redaction_policy: must be 'mask_secrets'`);
    }

    SECRET_PATTERNS.forEach((pattern) => {
      if (pattern.test(shellCommand)) {
        errors.push(`${cardPath}.shell_command: secret-like token detected, must be redacted`);
      }
    });

    if (kind) {
      kinds.push(kind);
    }
  });

  return kinds;
}

function validateRunnerConstraints(runnerConstraints, pathLabel, errors) {
  if (!isPlainObject(runnerConstraints)) {
    errors.push(`${pathLabel}: must be object`);
    return null;
  }

  const networkPolicy = normalizeString(runnerConstraints.network_policy);
  const capabilityMode = normalizeString(runnerConstraints.capability_mode);

  if (!ALLOWED_RUNNER_NETWORK_POLICY.has(networkPolicy)) {
    errors.push(`${pathLabel}.network_policy: unsupported value '${networkPolicy}'`);
  }
  if (!ALLOWED_CAPABILITY_MODE.has(capabilityMode)) {
    errors.push(`${pathLabel}.capability_mode: must be 'enforced'`);
  }

  const allowedWorkdirs = uniqueStrings(runnerConstraints.allowed_workdirs, `${pathLabel}.allowed_workdirs`, errors);
  const deniedPaths = uniqueStrings(runnerConstraints.denied_paths, `${pathLabel}.denied_paths`, errors);

  if (allowedWorkdirs.length === 0) {
    errors.push(`${pathLabel}.allowed_workdirs: must not be empty`);
  }
  if (deniedPaths.length === 0) {
    errors.push(`${pathLabel}.denied_paths: must not be empty`);
  }

  return { networkPolicy, capabilityMode };
}

function validateTrace(trace, pathLabel, errors) {
  if (!Array.isArray(trace)) {
    errors.push(`${pathLabel}: must be an array`);
    return {
      executeDecision: "",
      grantDecision: "",
      policyDecision: "",
      stageMap: new Map()
    };
  }

  const stageMap = new Map();

  trace.forEach((step, index) => {
    const stepPath = `${pathLabel}[${index}]`;
    if (!isPlainObject(step)) {
      errors.push(`${stepPath}: must be object`);
      return;
    }
    const stage = normalizeString(step.stage);
    const decision = normalizeString(step.decision);
    const evidenceRef = normalizeString(step.evidence_ref);

    if (!isNonEmptyString(stage)) {
      errors.push(`${stepPath}.stage: must be non-empty string`);
      return;
    }
    if (!isNonEmptyString(decision)) {
      errors.push(`${stepPath}.decision: must be non-empty string`);
    }
    if (!isNonEmptyString(evidenceRef)) {
      errors.push(`${stepPath}.evidence_ref: must be non-empty string`);
    }

    if (stageMap.has(stage)) {
      errors.push(`${stepPath}.stage: duplicated stage '${stage}'`);
      return;
    }

    stageMap.set(stage, {
      index,
      decision,
      denyCode: step.deny_code == null ? null : normalizeString(step.deny_code)
    });
  });

  let previousIndex = -1;
  REQUIRED_CHAIN.forEach((stage) => {
    const entry = stageMap.get(stage);
    if (!entry) {
      errors.push(`${pathLabel}: missing required stage '${stage}'`);
      return;
    }
    if (entry.index <= previousIndex) {
      errors.push(`${pathLabel}: stage order mismatch, must follow ${REQUIRED_CHAIN.join(" -> ")}`);
      return;
    }
    previousIndex = entry.index;
  });

  return {
    executeDecision: stageMap.get("execute") ? stageMap.get("execute").decision : "",
    grantDecision: stageMap.get("grant") ? stageMap.get("grant").decision : "",
    policyDecision: stageMap.get("policy") ? stageMap.get("policy").decision : "",
    stageMap
  };
}

function validateExplainableError(value, pathLabel, errors) {
  if (value === null) {
    return true;
  }
  if (!isPlainObject(value)) {
    errors.push(`${pathLabel}: must be object or null`);
    return false;
  }

  ["code", "user_message", "machine_reason", "suggested_action"].forEach((key) => {
    if (!isNonEmptyString(value[key])) {
      errors.push(`${pathLabel}.${key}: must be non-empty string`);
    }
  });
  return true;
}

function validateExpected(expected, pathLabel, errors) {
  if (!isPlainObject(expected)) {
    errors.push(`${pathLabel}: must be object`);
    return null;
  }

  const finalState = normalizeString(expected.final_state);
  const denyCode = expected.deny_code == null ? null : normalizeString(expected.deny_code);

  if (!ALLOWED_FINAL_STATES.has(finalState)) {
    errors.push(`${pathLabel}.final_state: unsupported value '${finalState}'`);
  }
  if (finalState === "blocked" && !isNonEmptyString(denyCode || "")) {
    errors.push(`${pathLabel}.deny_code: blocked state requires deny_code`);
  }

  validateExplainableError(expected.explainable_error, `${pathLabel}.explainable_error`, errors);

  const auditEvents = uniqueStrings(expected.audit_events, `${pathLabel}.audit_events`, errors);
  if (auditEvents.length === 0) {
    errors.push(`${pathLabel}.audit_events: must not be empty`);
  }

  if (!isPlainObject(expected.rollback)) {
    errors.push(`${pathLabel}.rollback: must be object`);
  } else {
    if (typeof expected.rollback.required !== "boolean") {
      errors.push(`${pathLabel}.rollback.required: must be boolean`);
    }
    if (!isNonEmptyString(expected.rollback.point)) {
      errors.push(`${pathLabel}.rollback.point: must be non-empty string`);
    }
    if (!isNonEmptyString(expected.rollback.policy_snapshot)) {
      errors.push(`${pathLabel}.rollback.policy_snapshot: must be non-empty string`);
    }
  }

  return {
    finalState,
    denyCode,
    auditEvents
  };
}

function validateKpiProbe(kpiProbe, pathLabel, errors) {
  if (!isPlainObject(kpiProbe)) {
    errors.push(`${pathLabel}: must be object`);
    return null;
  }
  const importToFirstRun = Number(kpiProbe.import_to_first_run_ms);
  if (!Number.isFinite(importToFirstRun) || importToFirstRun < 0) {
    errors.push(`${pathLabel}.import_to_first_run_ms: must be number >= 0`);
  }
  if (typeof kpiProbe.first_run_success !== "boolean") {
    errors.push(`${pathLabel}.first_run_success: must be boolean`);
  }
  if (typeof kpiProbe.preflight_false_positive !== "boolean") {
    errors.push(`${pathLabel}.preflight_false_positive: must be boolean`);
  }

  return {
    importToFirstRun,
    firstRunSuccess: Boolean(kpiProbe.first_run_success),
    preflightFalsePositive: Boolean(kpiProbe.preflight_false_positive)
  };
}

function validateCaseSpecificRules(caseItem, context, errors) {
  const caseID = caseItem.case_id;
  const preflightChecks = context.preflightChecks;
  const fixCardKinds = context.fixCardKinds;
  const expected = context.expected;
  const trace = context.trace;

  if (caseID === "search_import_pin_project_success") {
    if (!caseItem.work_order_ids.includes("SKC-W1-02")) {
      errors.push("case search_import_pin_project_success: missing SKC-W1-02 work order binding");
    }
    if (context.preflightStatus !== "pass") {
      errors.push("case search_import_pin_project_success: preflight must pass");
    }
    if (expected.finalState !== "pass") {
      errors.push("case search_import_pin_project_success: expected.final_state must be pass");
    }
  }

  if (caseID === "preflight_missing_bin_env_config") {
    if (context.preflightStatus !== "fail") {
      errors.push("case preflight_missing_bin_env_config: preflight.status must be fail");
    }
    if (!(preflightChecks && preflightChecks.bin === "fail" && preflightChecks.env === "fail" && preflightChecks.config === "fail")) {
      errors.push("case preflight_missing_bin_env_config: bin/env/config must all fail");
    }
    ["bin", "env", "config"].forEach((kind) => {
      if (!fixCardKinds.includes(kind)) {
        errors.push(`case preflight_missing_bin_env_config: missing fix card kind '${kind}'`);
      }
    });
    if (expected.denyCode !== "preflight_failed") {
      errors.push("case preflight_missing_bin_env_config: expected.deny_code must be preflight_failed");
    }
  }

  if (caseID === "capability_missing_grant_pending") {
    if (!(preflightChecks && preflightChecks.capabilities === "grant_pending")) {
      errors.push("case capability_missing_grant_pending: capabilities check must be grant_pending");
    }
    if (trace.grantDecision !== "grant_pending") {
      errors.push("case capability_missing_grant_pending: grant stage must be grant_pending");
    }
    if (trace.executeDecision !== "blocked") {
      errors.push("case capability_missing_grant_pending: execute must be blocked");
    }
    if (expected.denyCode !== "grant_pending") {
      errors.push("case capability_missing_grant_pending: expected.deny_code must be grant_pending");
    }
  }

  if (caseID === "hot_update_failure_rollback") {
    if (!caseItem.work_order_ids.includes("SKC-W4-11")) {
      errors.push("case hot_update_failure_rollback: missing SKC-W4-11 work order binding");
    }
    if (expected.finalState !== "rollback_applied") {
      errors.push("case hot_update_failure_rollback: expected.final_state must be rollback_applied");
    }
    if (!isPlainObject(caseItem.hot_update)) {
      errors.push("case hot_update_failure_rollback.hot_update: must be object");
    } else {
      if (caseItem.hot_update.attempted !== true) {
        errors.push("case hot_update_failure_rollback.hot_update.attempted: must be true");
      }
      if (normalizeString(caseItem.hot_update.result) !== "rollback_applied") {
        errors.push("case hot_update_failure_rollback.hot_update.result: must be rollback_applied");
      }
      if (
        normalizeString(caseItem.hot_update.previous_snapshot_id) !== normalizeString(caseItem.hot_update.active_snapshot_id_after)
      ) {
        errors.push("case hot_update_failure_rollback: active snapshot after failure must equal previous snapshot");
      }
    }
    if (expected.finalState === "rollback_applied" && expected.denyCode !== null) {
      errors.push("case hot_update_failure_rollback: rollback_applied should not expose deny_code");
    }
    if (expected.finalState === "rollback_applied" && caseItem.expected.stale_snapshot_incident !== false) {
      errors.push("case hot_update_failure_rollback: stale_snapshot_incident must be false");
    }
  }

  if (caseID === "runner_network_or_path_violation") {
    if (trace.policyDecision !== "deny") {
      errors.push("case runner_network_or_path_violation: policy stage must deny");
    }
    if (trace.executeDecision !== "blocked") {
      errors.push("case runner_network_or_path_violation: execute must be blocked");
    }
    if (!["direct_network_forbidden", "path_not_allowed", "runner_policy_violation"].includes(expected.denyCode)) {
      errors.push("case runner_network_or_path_violation: expected.deny_code must describe runner policy violation");
    }
    if (!caseItem.expected.explainable_error || normalizeString(caseItem.expected.explainable_error.code) !== expected.denyCode) {
      errors.push("case runner_network_or_path_violation: explainable_error.code must match expected.deny_code");
    }
  }
}

function validateCases(doc, errors) {
  if (!Array.isArray(doc.cases)) {
    errors.push("cases: must be an array");
    return {
      caseIDs: [],
      summary: emptySummary()
    };
  }

  const caseIDs = [];
  const uniqueCaseIDs = new Set();
  const summary = emptySummary();

  doc.cases.forEach((caseItem, index) => {
    const casePath = `cases[${index}]`;
    if (!isPlainObject(caseItem)) {
      errors.push(`${casePath}: must be object`);
      return;
    }

    const caseID = normalizeString(caseItem.case_id);
    if (!isNonEmptyString(caseID)) {
      errors.push(`${casePath}.case_id: must be non-empty string`);
      return;
    }
    if (uniqueCaseIDs.has(caseID)) {
      errors.push(`${casePath}.case_id: duplicated case_id '${caseID}'`);
      return;
    }
    uniqueCaseIDs.add(caseID);
    caseIDs.push(caseID);

    const workOrderIDs = uniqueStrings(caseItem.work_order_ids, `${casePath}.work_order_ids`, errors);
    workOrderIDs.forEach((workOrderID) => {
      if (!REQUIRED_WORK_ORDER_IDS.includes(workOrderID)) {
        errors.push(`${casePath}.work_order_ids: unsupported work order '${workOrderID}'`);
      }
    });

    const riskTier = normalizeString(caseItem.risk_tier);
    if (!ALLOWED_RISK_TIERS.has(riskTier)) {
      errors.push(`${casePath}.risk_tier: must be low|medium|high`);
    }

    if (!isPlainObject(caseItem.scenario)) {
      errors.push(`${casePath}.scenario: must be object`);
    } else {
      if (!isNonEmptyString(caseItem.scenario.title)) {
        errors.push(`${casePath}.scenario.title: must be non-empty string`);
      }
      if (!isNonEmptyString(caseItem.scenario.description)) {
        errors.push(`${casePath}.scenario.description: must be non-empty string`);
      }
    }

    const uiAssertions = Array.isArray(caseItem.ui_assertions) ? caseItem.ui_assertions : null;
    if (!uiAssertions || uiAssertions.length === 0) {
      errors.push(`${casePath}.ui_assertions: must be non-empty array`);
    } else {
      uiAssertions.forEach((item, assertionIndex) => {
        const assertionPath = `${casePath}.ui_assertions[${assertionIndex}]`;
        if (!isPlainObject(item)) {
          errors.push(`${assertionPath}: must be object`);
          return;
        }
        if (!isNonEmptyString(item.id)) {
          errors.push(`${assertionPath}.id: must be non-empty string`);
        }
        if (!isNonEmptyString(item.assertion)) {
          errors.push(`${assertionPath}.assertion: must be non-empty string`);
        }
        if (normalizeString(item.severity) !== "must") {
          errors.push(`${assertionPath}.severity: must be 'must'`);
        }
      });
    }

    if (!isPlainObject(caseItem.preflight)) {
      errors.push(`${casePath}.preflight: must be object`);
      return;
    }

    if (caseItem.preflight.required !== true) {
      errors.push(`${casePath}.preflight.required: must be true`);
    }

    const preflightStatus = normalizeString(caseItem.preflight.status);
    if (!ALLOWED_PREFLIGHT_STATUS.has(preflightStatus)) {
      errors.push(`${casePath}.preflight.status: must be pass|fail`);
    }

    const preflightChecks = validatePreflightChecks(caseItem.preflight.checks, `${casePath}.preflight.checks`, errors);
    const fixCardKinds = validateFixCards(caseItem.preflight.fix_cards, `${casePath}.preflight.fix_cards`, errors);

    if (preflightStatus === "fail" && fixCardKinds.length === 0) {
      errors.push(`${casePath}.preflight.fix_cards: must provide actionable fix cards when preflight fails`);
    }

    validateRunnerConstraints(caseItem.runner_constraints, `${casePath}.runner_constraints`, errors);
    const trace = validateTrace(caseItem.trace, `${casePath}.trace`, errors);

    if (preflightStatus !== "pass" && trace.executeDecision !== "blocked") {
      errors.push(`${casePath}: preflight fail must block execute`);
    }

    if (riskTier === "high" && trace.grantDecision === "grant_pending" && trace.executeDecision !== "blocked") {
      errors.push(`${casePath}: high risk grant_pending must block execute`);
    }

    const expected = validateExpected(caseItem.expected, `${casePath}.expected`, errors);
    const kpiProbe = validateKpiProbe(caseItem.kpi_probe, `${casePath}.kpi_probe`, errors);

    if (expected && expected.finalState === "blocked" && !expected.denyCode) {
      errors.push(`${casePath}: blocked expected state must include deny_code`);
    }

    if (expected && expected.finalState !== "blocked" && caseItem.expected.explainable_error === null && caseID !== "search_import_pin_project_success") {
      errors.push(`${casePath}: non-success fallback paths must provide explainable_error`);
    }

    validateCaseSpecificRules(
      caseItem,
      {
        preflightStatus,
        preflightChecks,
        fixCardKinds,
        expected,
        trace
      },
      errors
    );

    summary.case_count += 1;
    if (expected && expected.finalState === "pass") {
      summary.pass_case_count += 1;
    }
    if (expected && expected.finalState === "blocked") {
      summary.blocked_case_count += 1;
    }
    if (expected && expected.finalState === "rollback_applied") {
      summary.rollback_case_count += 1;
    }
    if (preflightStatus === "fail") {
      summary.preflight_failed_case_count += 1;
    }
    if (trace.grantDecision === "grant_pending") {
      summary.grant_pending_case_count += 1;
    }
    if (kpiProbe) {
      if (kpiProbe.importToFirstRun > 0) {
        summary.import_to_first_run_samples_ms.push(kpiProbe.importToFirstRun);
      }
      if (kpiProbe.firstRunSuccess) {
        summary.first_run_success_count += 1;
      }
      if (kpiProbe.preflightFalsePositive) {
        summary.preflight_false_positive_count += 1;
      }
    }
  });

  REQUIRED_CASE_IDS.forEach((requiredCaseID) => {
    if (!uniqueCaseIDs.has(requiredCaseID)) {
      errors.push(`cases: missing required regression case '${requiredCaseID}'`);
    }
  });

  return {
    caseIDs,
    summary
  };
}

function percentile(values, p) {
  if (!Array.isArray(values) || values.length === 0) {
    return 0;
  }
  const sorted = values.slice().sort((a, b) => a - b);
  const rank = Math.max(0, Math.ceil(p * sorted.length) - 1);
  return sorted[rank];
}

function emptySummary() {
  return {
    case_count: 0,
    pass_case_count: 0,
    blocked_case_count: 0,
    rollback_case_count: 0,
    preflight_failed_case_count: 0,
    grant_pending_case_count: 0,
    import_to_first_run_samples_ms: [],
    first_run_success_count: 0,
    preflight_false_positive_count: 0
  };
}

function validateKpiSnapshot(doc, thresholds, summary, errors) {
  if (!isPlainObject(doc.kpi_snapshot)) {
    errors.push("kpi_snapshot: must be object");
    return {
      pass: false,
      snapshot: null,
      computed: null
    };
  }

  const snapshot = {
    import_to_first_run_p95_ms: Number(doc.kpi_snapshot.import_to_first_run_p95_ms),
    skill_first_run_success_rate: Number(doc.kpi_snapshot.skill_first_run_success_rate),
    preflight_false_positive_rate: Number(doc.kpi_snapshot.preflight_false_positive_rate)
  };

  [
    ["import_to_first_run_p95_ms", snapshot.import_to_first_run_p95_ms],
    ["skill_first_run_success_rate", snapshot.skill_first_run_success_rate],
    ["preflight_false_positive_rate", snapshot.preflight_false_positive_rate]
  ].forEach(([name, value]) => {
    if (!Number.isFinite(value)) {
      errors.push(`kpi_snapshot.${name}: must be numeric`);
    }
  });

  const computed = {
    import_to_first_run_p95_ms: percentile(summary.import_to_first_run_samples_ms, 0.95),
    skill_first_run_success_rate:
      summary.case_count > 0 ? summary.first_run_success_count / summary.case_count : 0,
    preflight_false_positive_rate:
      summary.case_count > 0 ? summary.preflight_false_positive_count / summary.case_count : 0
  };

  const thresholdFailures = [];

  if (Number.isFinite(snapshot.import_to_first_run_p95_ms) && Number.isFinite(thresholds.import_to_first_run_p95_ms)) {
    if (snapshot.import_to_first_run_p95_ms > thresholds.import_to_first_run_p95_ms) {
      thresholdFailures.push(
        `kpi_snapshot.import_to_first_run_p95_ms exceeds threshold (${snapshot.import_to_first_run_p95_ms} > ${thresholds.import_to_first_run_p95_ms})`
      );
    }
  }

  if (Number.isFinite(snapshot.skill_first_run_success_rate) && Number.isFinite(thresholds.skill_first_run_success_rate)) {
    if (snapshot.skill_first_run_success_rate < thresholds.skill_first_run_success_rate) {
      thresholdFailures.push(
        `kpi_snapshot.skill_first_run_success_rate below threshold (${snapshot.skill_first_run_success_rate} < ${thresholds.skill_first_run_success_rate})`
      );
    }
  }

  if (Number.isFinite(snapshot.preflight_false_positive_rate) && Number.isFinite(thresholds.preflight_false_positive_rate)) {
    if (snapshot.preflight_false_positive_rate >= thresholds.preflight_false_positive_rate) {
      thresholdFailures.push(
        `kpi_snapshot.preflight_false_positive_rate must be < threshold (${snapshot.preflight_false_positive_rate} >= ${thresholds.preflight_false_positive_rate})`
      );
    }
  }

  thresholdFailures.forEach((failure) => errors.push(failure));

  return {
    pass: thresholdFailures.length === 0,
    snapshot,
    computed
  };
}

function validateSkillsXTl1ContractFixture(doc) {
  const errors = [];

  if (!isPlainObject(doc)) {
    return {
      ok: false,
      schema_version: "",
      error_count: 1,
      summary: emptySummary(),
      computed_kpi: null,
      errors: ["root: fixture must be JSON object"]
    };
  }

  if (doc.schema_version !== FIXTURE_SCHEMA_VERSION) {
    errors.push(`schema_version: must be '${FIXTURE_SCHEMA_VERSION}'`);
  }

  const contractInfo = validateContract(doc, errors);
  const gates = validateGateAssertions(doc, errors);
  const { caseIDs, summary } = validateCases(doc, errors);

  const kpi = validateKpiSnapshot(
    doc,
    contractInfo && contractInfo.thresholds
      ? contractInfo.thresholds
      : {
          import_to_first_run_p95_ms: 0,
          skill_first_run_success_rate: 1,
          preflight_false_positive_rate: 0
        },
    summary,
    errors
  );

  return {
    ok: errors.length === 0,
    schema_version: normalizeString(doc.schema_version),
    gate_pass: gates.allPass,
    case_count: summary.case_count,
    required_case_count: REQUIRED_CASE_IDS.length,
    case_ids: caseIDs,
    summary: {
      case_count: summary.case_count,
      pass_case_count: summary.pass_case_count,
      blocked_case_count: summary.blocked_case_count,
      rollback_case_count: summary.rollback_case_count,
      preflight_failed_case_count: summary.preflight_failed_case_count,
      grant_pending_case_count: summary.grant_pending_case_count,
      import_to_first_run_p95_ms: kpi.computed ? kpi.computed.import_to_first_run_p95_ms : 0,
      skill_first_run_success_rate: kpi.computed ? kpi.computed.skill_first_run_success_rate : 0,
      preflight_false_positive_rate: kpi.computed ? kpi.computed.preflight_false_positive_rate : 0
    },
    kpi_snapshot: kpi.snapshot,
    computed_kpi: kpi.computed,
    error_count: errors.length,
    errors
  };
}

function printHelp() {
  console.log(
    [
      "Usage:",
      "  node ./scripts/check_skills_xt_l1_contract.js [--fixture <path>] [--out-json <path>]",
      "",
      "Defaults:",
      "  --fixture ./scripts/fixtures/skills_xt_l1_contract.sample.json"
    ].join("\n")
  );
}

function main() {
  let options;
  try {
    options = parseArgs(process.argv);
  } catch (error) {
    console.error(`[skills-xt-l1-contract] ${error.message}`);
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
    console.error(`[skills-xt-l1-contract] failed to read fixture: ${error.message}`);
    process.exit(2);
  }

  const result = validateSkillsXTl1ContractFixture(doc);

  if (options.outJson) {
    fs.mkdirSync(path.dirname(options.outJson), { recursive: true });
    fs.writeFileSync(options.outJson, `${JSON.stringify(result, null, 2)}\n`, "utf8");
  }

  if (!result.ok) {
    console.error(`[skills-xt-l1-contract] fixture invalid: ${options.fixturePath}`);
    result.errors.forEach((line) => {
      console.error(`- ${line}`);
    });
    process.exit(1);
  }

  console.log(
    `[skills-xt-l1-contract] ok schema=${result.schema_version} cases=${result.case_count} ` +
      `blocked=${result.summary.blocked_case_count} rollback=${result.summary.rollback_case_count} ` +
      `p95=${result.summary.import_to_first_run_p95_ms}ms first_run=${result.summary.skill_first_run_success_rate.toFixed(3)} ` +
      `preflight_fp=${result.summary.preflight_false_positive_rate.toFixed(3)} file=${options.fixturePath}`
  );
}

if (require.main === module) {
  main();
}

module.exports = {
  FIXTURE_SCHEMA_VERSION,
  CONTRACT_SCHEMA,
  CONTRACT_VERSION,
  REQUIRED_CASE_IDS,
  REQUIRED_CHAIN,
  validateSkillsXTl1ContractFixture,
  readJSON
};
