#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");

const DEFAULT_CONTRACT_JSON = "docs/memory-new/schema/xhub_skills_capability_grant_chain_contract.v1.json";
const EXPECTED_SCHEMA_VERSION = "xhub.skills_grant_chain_contract.v1";
const REQUIRED_INCIDENTS = {
  grant_pending: {
    supervisor_event_type: "supervisor.incident.grant_pending.handled",
    deny_code: "grant_pending",
  },
  awaiting_instruction: {
    supervisor_event_type: "supervisor.incident.awaiting_instruction.handled",
    deny_code: "awaiting_instruction",
  },
  runtime_error: {
    supervisor_event_type: "supervisor.incident.runtime_error.handled",
    deny_code: "runtime_error",
  },
};
const REQUIRED_CAPABILITIES = [
  "ai.generate.local",
  "ai.generate.paid",
  "web.fetch",
  "terminal.exec",
  "filesystem.write",
  "payment.intent.confirm",
];
const ALLOWED_SCOPES = new Set(["readonly", "privileged", "critical"]);
const ALLOWED_RISK_FLOORS = new Set(["low", "medium", "high", "critical"]);
const REQUIRED_BINDING_DENY_CODES = [
  "approval_binding_invalid",
  "approval_cwd_invalid",
  "approval_argv_mismatch",
  "approval_cwd_mismatch",
  "approval_identity_mismatch",
];
const REQUIRED_GRANT_DENY_CODES = [
  "grant_missing",
  "grant_expired",
  "request_tampered",
];

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

function readJson(filePath) {
  return JSON.parse(String(fs.readFileSync(filePath, "utf8") || "{}"));
}

function writeText(filePath, content) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, String(content || ""), "utf8");
}

function toSet(values = []) {
  const set = new Set();
  for (const item of values) {
    const key = String(item || "").trim();
    if (!key) continue;
    set.add(key);
  }
  return set;
}

function indexBy(list = [], keyName = "") {
  const out = new Map();
  for (const item of Array.isArray(list) ? list : []) {
    if (!item || typeof item !== "object") continue;
    const key = String(item[keyName] || "").trim();
    if (!key) continue;
    out.set(key, item);
  }
  return out;
}

function checkSkillsGrantChainContract(doc = {}) {
  const errors = [];
  const warnings = [];
  const details = [];

  const schemaVersion = String(doc.schema_version || "").trim();
  if (schemaVersion !== EXPECTED_SCHEMA_VERSION) {
    errors.push(`schema_version mismatch: expected ${EXPECTED_SCHEMA_VERSION}, got ${schemaVersion || "(empty)"}`);
  }

  const chain = Array.isArray(doc.execution_chain) ? doc.execution_chain.map((v) => String(v || "").trim()).filter(Boolean) : [];
  const expectedChain = ["ingress", "risk_classify", "policy", "grant", "execute", "audit"];
  if (chain.length !== expectedChain.length || chain.some((v, idx) => v !== expectedChain[idx])) {
    errors.push(`execution_chain mismatch: expected ${expectedChain.join(" -> ")}`);
  }

  const capabilityMap = Array.isArray(doc.capability_scope_map) ? doc.capability_scope_map : [];
  if (capabilityMap.length <= 0) {
    errors.push("capability_scope_map is empty");
  }

  const capabilityIndex = indexBy(capabilityMap, "capability");
  for (const key of REQUIRED_CAPABILITIES) {
    if (!capabilityIndex.has(key)) {
      errors.push(`missing required capability mapping: ${key}`);
    }
  }

  for (const row of capabilityMap) {
    const capability = String(row?.capability || "").trim();
    const scope = String(row?.required_grant_scope || "").trim();
    const riskFloor = String(row?.risk_tier_floor || "").trim();
    const grantRequired = row?.grant_required === true;

    if (!capability) {
      errors.push("capability_scope_map item has empty capability");
      continue;
    }
    if (!ALLOWED_SCOPES.has(scope)) {
      errors.push(`capability ${capability} uses unsupported required_grant_scope: ${scope || "(empty)"}`);
    }
    if (!ALLOWED_RISK_FLOORS.has(riskFloor)) {
      errors.push(`capability ${capability} uses unsupported risk_tier_floor: ${riskFloor || "(empty)"}`);
    }
    if (!Array.isArray(row.aliases) || row.aliases.length <= 0) {
      warnings.push(`capability ${capability} has empty aliases`);
    }
    if (grantRequired === false && (scope === "privileged" || scope === "critical")) {
      errors.push(`capability ${capability} is grant_required=false but scope=${scope}`);
    }
    details.push({
      capability,
      required_grant_scope: scope,
      risk_tier_floor: riskFloor,
      grant_required: grantRequired,
    });
  }

  const incidents = Array.isArray(doc.incident_semantics) ? doc.incident_semantics : [];
  const incidentIndex = indexBy(incidents, "incident_code");
  for (const [incidentCode, expected] of Object.entries(REQUIRED_INCIDENTS)) {
    const row = incidentIndex.get(incidentCode);
    if (!row) {
      errors.push(`missing incident_semantics for ${incidentCode}`);
      continue;
    }
    if (String(row.supervisor_event_type || "") !== expected.supervisor_event_type) {
      errors.push(`incident ${incidentCode} supervisor_event_type mismatch`);
    }
    if (String(row.deny_code || "") !== expected.deny_code) {
      errors.push(`incident ${incidentCode} deny_code mismatch`);
    }
    const requiredAuditFields = Array.isArray(row.required_audit_fields) ? row.required_audit_fields.map((x) => String(x || "").trim()) : [];
    if (!requiredAuditFields.includes("ext_json.chain")) {
      errors.push(`incident ${incidentCode} missing required_audit_fields entry: ext_json.chain`);
    }
  }

  const standard = doc.skill_preflight_binding_standard && typeof doc.skill_preflight_binding_standard === "object"
    ? doc.skill_preflight_binding_standard
    : {};
  const preflightOrder = Array.isArray(standard.preflight_order) ? standard.preflight_order.map((x) => String(x || "").trim()) : [];
  if (preflightOrder.length < 5) {
    errors.push("skill_preflight_binding_standard.preflight_order is too short");
  }
  if (!preflightOrder.includes("derive_required_grant_scope_floor")) {
    errors.push("preflight_order missing derive_required_grant_scope_floor");
  }
  if (!preflightOrder.includes("persist_approval_binding")) {
    errors.push("preflight_order missing persist_approval_binding");
  }

  const bindingChecks = Array.isArray(standard.approval_binding_checks) ? standard.approval_binding_checks : [];
  const bindingDenyCodes = toSet(bindingChecks.map((it) => it && typeof it === "object" ? it.deny_code : ""));
  for (const denyCode of REQUIRED_BINDING_DENY_CODES) {
    if (!bindingDenyCodes.has(denyCode)) {
      errors.push(`approval_binding_checks missing deny_code: ${denyCode}`);
    }
  }

  const grantChecks = Array.isArray(standard.grant_checks) ? standard.grant_checks : [];
  const grantDenyCodes = toSet(grantChecks.map((it) => it && typeof it === "object" ? it.deny_code : ""));
  for (const denyCode of REQUIRED_GRANT_DENY_CODES) {
    if (!grantDenyCodes.has(denyCode)) {
      errors.push(`grant_checks missing deny_code: ${denyCode}`);
    }
  }

  const denyDict = toSet(Array.isArray(doc.deny_code_dictionary) ? doc.deny_code_dictionary : []);
  for (const denyCode of [...REQUIRED_BINDING_DENY_CODES, ...REQUIRED_GRANT_DENY_CODES, ...Object.keys(REQUIRED_INCIDENTS)]) {
    if (!denyDict.has(denyCode)) {
      errors.push(`deny_code_dictionary missing required code: ${denyCode}`);
    }
  }

  const dodTargets = doc.dod_targets && typeof doc.dod_targets === "object" ? doc.dod_targets : {};
  if (Number(dodTargets.high_risk_lane_without_grant) !== 0) {
    errors.push("DoD target mismatch: high_risk_lane_without_grant must be 0");
  }
  if (Number(dodTargets.approval_mismatch_execution) !== 0) {
    errors.push("DoD target mismatch: approval_mismatch_execution must be 0");
  }
  if (Number(dodTargets.bypass_grant_execution) !== 0) {
    errors.push("DoD target mismatch: bypass_grant_execution must be 0");
  }
  const lowRiskFalseBlock = Number(dodTargets.low_risk_false_block_rate_lt);
  if (!Number.isFinite(lowRiskFalseBlock) || lowRiskFalseBlock <= 0 || lowRiskFalseBlock >= 0.03) {
    errors.push("DoD target mismatch: low_risk_false_block_rate_lt must be < 0.03 and > 0");
  }

  const gateTargets = toSet(Array.isArray(doc.gate_targets) ? doc.gate_targets : []);
  if (!gateTargets.has("SKC-G2") || !gateTargets.has("SKC-G4")) {
    errors.push("gate_targets must contain SKC-G2 and SKC-G4");
  }

  return {
    ok: errors.length === 0,
    errors,
    warnings,
    summary: {
      capability_mapping_total: capabilityMap.length,
      incident_semantics_total: incidents.length,
      binding_check_total: bindingChecks.length,
      grant_check_total: grantChecks.length,
      deny_code_total: denyDict.size,
    },
    details,
  };
}

function main() {
  const args = parseArgs(process.argv);
  const contractJsonPath = path.resolve(args["contract-json"] || DEFAULT_CONTRACT_JSON);
  const outJsonPath = args["out-json"] ? path.resolve(String(args["out-json"])) : "";

  if (!fs.existsSync(contractJsonPath)) {
    const msg = `contract json missing: ${contractJsonPath}`;
    if (outJsonPath) {
      writeText(outJsonPath, `${JSON.stringify({ ok: false, errors: [msg] }, null, 2)}\n`);
    }
    console.error(`not ok - ${msg}`);
    process.exit(1);
  }

  let payload;
  try {
    payload = readJson(contractJsonPath);
  } catch (err) {
    const msg = `invalid json: ${contractJsonPath} (${String(err && err.message ? err.message : err)})`;
    if (outJsonPath) {
      writeText(outJsonPath, `${JSON.stringify({ ok: false, errors: [msg] }, null, 2)}\n`);
    }
    console.error(`not ok - ${msg}`);
    process.exit(1);
  }

  const report = checkSkillsGrantChainContract(payload);
  report.contract_json = contractJsonPath;
  report.checked_at = new Date().toISOString();

  if (outJsonPath) {
    writeText(outJsonPath, `${JSON.stringify(report, null, 2)}\n`);
  }

  if (!report.ok) {
    for (const line of report.errors) {
      console.error(`not ok - ${line}`);
    }
    process.exit(1);
  }

  if (report.warnings.length > 0) {
    for (const line of report.warnings) {
      console.warn(`warn - ${line}`);
    }
  }

  console.log(
    `ok - Hub-L3 skills grant chain contract passed `
      + `(capability_map=${report.summary.capability_mapping_total}, incidents=${report.summary.incident_semantics_total})`
  );
}

if (require.main === module) {
  main();
}

module.exports = {
  checkSkillsGrantChainContract,
};
