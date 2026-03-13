#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");

const DEFAULT_CONTRACT_JSON = "docs/memory-new/schema/xhub_multimodal_supervisor_control_plane_contract.v1.json";
const DEFAULT_PROTO = "protocol/hub_protocol_v1.proto";
const DEFAULT_PROTOCOL_MD = "protocol/hub_protocol_v1.md";
const REPO_ROOT = path.resolve(__dirname, "..");

const EXPECTED_SCHEMA_VERSION = "xhub.multimodal_supervisor_control_plane_contract.v1";
const REQUIRED_OBJECTS = [
  "xhub.supervisor_surface_ingress.v1",
  "xhub.supervisor_route_decision.v1",
  "xhub.supervisor_brief_projection.v1",
  "xhub.supervisor_guidance_resolution.v1",
  "xhub.supervisor_checkpoint_challenge.v1",
];
const REQUIRED_ROUTE_DECISIONS = ["hub_only", "hub_to_xt", "hub_to_runner", "fail_closed"];
const REQUIRED_DENY_CODES = [
  "identity_unbound",
  "project_not_bound",
  "ambiguous_target",
  "scope_expansion_detected",
  "xt_offline",
  "runner_not_ready",
  "trusted_automation_project_not_bound",
  "remote_posture_insufficient",
  "grant_required",
  "voice_only_not_allowed",
  "policy_denied",
  "challenge_expired",
  "device_not_bound",
  "runtime_error",
];
const REQUIRED_PROTO_MESSAGES = [
  "SupervisorTargetScope",
  "SupervisorSurfaceIngress",
  "IngestSupervisorSurfaceRequest",
  "IngestSupervisorSurfaceResponse",
  "SupervisorRouteDecision",
  "ResolveSupervisorRouteRequest",
  "ResolveSupervisorRouteResponse",
  "SupervisorBriefProjection",
  "GetSupervisorBriefProjectionRequest",
  "GetSupervisorBriefProjectionResponse",
  "SupervisorGuidanceResolution",
  "ResolveSupervisorGuidanceRequest",
  "ResolveSupervisorGuidanceResponse",
  "SupervisorCheckpointChallenge",
  "IssueSupervisorCheckpointChallengeRequest",
  "IssueSupervisorCheckpointChallengeResponse",
];
const REQUIRED_SUPERVISOR_RPCS = [
  "IngestSupervisorSurface",
  "ResolveSupervisorRoute",
  "GetSupervisorBriefProjection",
  "ResolveSupervisorGuidance",
  "IssueSupervisorCheckpointChallenge",
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

function readText(filePath) {
  return String(fs.readFileSync(filePath, "utf8") || "");
}

function readJson(filePath) {
  return JSON.parse(readText(filePath));
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

function extractProtoMessages(protoText = "") {
  return toSet(Array.from(String(protoText || "").matchAll(/^message\s+([A-Za-z0-9_]+)\s*\{/gm)).map((m) => m[1]));
}

function extractProtoServiceRpcMap(protoText = "") {
  const text = String(protoText || "");
  const services = {};
  const serviceMatcher = /^service\s+([A-Za-z0-9_]+)\s*\{/gm;
  let match = serviceMatcher.exec(text);
  while (match) {
    const serviceName = String(match[1] || "").trim();
    const bodyStart = serviceMatcher.lastIndex;
    let depth = 1;
    let idx = bodyStart;
    while (idx < text.length && depth > 0) {
      const ch = text[idx];
      if (ch === "{") depth += 1;
      if (ch === "}") depth -= 1;
      idx += 1;
    }
    const body = text.slice(bodyStart, Math.max(bodyStart, idx - 1));
    const rpcs = Array.from(body.matchAll(/rpc\s+([A-Za-z0-9_]+)\s*\(/g)).map((m) => String(m[1] || "").trim());
    services[serviceName] = toSet(rpcs);
    match = serviceMatcher.exec(text);
  }
  return services;
}

function checkContractJson(doc = {}) {
  const errors = [];
  const warnings = [];

  const schemaVersion = String(doc.schema_version || "").trim();
  if (schemaVersion !== EXPECTED_SCHEMA_VERSION) {
    errors.push(`schema_version mismatch: expected ${EXPECTED_SCHEMA_VERSION}, got ${schemaVersion || "(empty)"}`);
  }

  const executionChain = Array.isArray(doc.execution_chain) ? doc.execution_chain.map((x) => String(x || "").trim()).filter(Boolean) : [];
  const expectedChain = [
    "ingress",
    "identity_bind",
    "normalize",
    "project_bind",
    "risk_classify",
    "route_decide",
    "policy",
    "grant",
    "execute",
    "audit",
    "memory_project",
  ];
  if (executionChain.length !== expectedChain.length || executionChain.some((item, idx) => item !== expectedChain[idx])) {
    errors.push(`execution_chain mismatch: expected ${expectedChain.join(" -> ")}`);
  }

  const objects = doc.objects && typeof doc.objects === "object" ? doc.objects : {};
  for (const objectName of REQUIRED_OBJECTS) {
    if (!Object.prototype.hasOwnProperty.call(objects, objectName)) {
      errors.push(`missing object contract: ${objectName}`);
    }
  }

  const routeDecisionEnum = toSet(Array.isArray(doc.route_decision_enum) ? doc.route_decision_enum : []);
  for (const decision of REQUIRED_ROUTE_DECISIONS) {
    if (!routeDecisionEnum.has(decision)) {
      errors.push(`route_decision_enum missing required value: ${decision}`);
    }
  }

  const denyCodes = toSet(
    Array.isArray(doc.deny_code_dictionary)
      ? doc.deny_code_dictionary.map((item) => (item && typeof item === "object" ? item.deny_code : ""))
      : []
  );
  for (const denyCode of REQUIRED_DENY_CODES) {
    if (!denyCodes.has(denyCode)) {
      errors.push(`deny_code_dictionary missing required code: ${denyCode}`);
    }
  }

  const checkpointObject = objects["xhub.supervisor_checkpoint_challenge.v1"] || {};
  const checkpointRules = Array.isArray(checkpointObject.rules) ? checkpointObject.rules.map((x) => String(x || "").trim()) : [];
  if (!checkpointRules.some((line) => line.includes("High and critical risk default to requires_mobile_confirm=true"))) {
    errors.push("checkpoint challenge rules missing high-risk mobile confirm guard");
  }

  const memoryBoundary = doc.memory_write_boundary && typeof doc.memory_write_boundary === "object" ? doc.memory_write_boundary : {};
  const denyDefault = toSet(Array.isArray(memoryBoundary.deny_default) ? memoryBoundary.deny_default : []);
  for (const item of ["raw_audio", "external_attachment_body", "unredacted_transcript"]) {
    if (!denyDefault.has(item)) {
      errors.push(`memory_write_boundary.deny_default missing: ${item}`);
    }
  }

  const allowLongterm = toSet(Array.isArray(memoryBoundary.allow_longterm) ? memoryBoundary.allow_longterm : []);
  if (!allowLongterm.has("brief_projection_summary")) {
    warnings.push("memory_write_boundary.allow_longterm missing brief_projection_summary");
  }

  return { errors, warnings };
}

function checkProto(protoText = "") {
  const errors = [];
  const messages = extractProtoMessages(protoText);
  const services = extractProtoServiceRpcMap(protoText);

  for (const messageName of REQUIRED_PROTO_MESSAGES) {
    if (!messages.has(messageName)) {
      errors.push(`proto missing message: ${messageName}`);
    }
  }

  if (!Object.prototype.hasOwnProperty.call(services, "HubSupervisor")) {
    errors.push("proto missing service: HubSupervisor");
  } else {
    const rpcSet = services.HubSupervisor;
    for (const rpcName of REQUIRED_SUPERVISOR_RPCS) {
      if (!rpcSet.has(rpcName)) {
        errors.push(`HubSupervisor missing rpc: ${rpcName}`);
      }
    }
  }

  return { errors };
}

function checkProtocolMarkdown(markdown = "") {
  const errors = [];
  const text = String(markdown || "");

  if (!/##\s+13\)\s+Multimodal Supervisor Control Plane\b/.test(text)) {
    errors.push("protocol md missing section heading: ## 13) Multimodal Supervisor Control Plane");
  }
  if (!/See `service HubSupervisor`/.test(text)) {
    errors.push("protocol md missing HubSupervisor service anchor");
  }
  for (const rpcName of REQUIRED_SUPERVISOR_RPCS) {
    if (!new RegExp(`-\\s+\`${rpcName}\``).test(text)) {
      errors.push(`protocol md missing rpc bullet: ${rpcName}`);
    }
  }
  if (!/IssueVoiceGrantChallenge \/ VerifyVoiceGrantResponse/.test(text)) {
    errors.push("protocol md missing delegated voice grant chain reference");
  }
  if (!/CreatePaymentIntent \/ IssuePaymentChallenge \/ ConfirmPaymentIntent/.test(text)) {
    errors.push("protocol md missing delegated payment chain reference");
  }

  return { errors };
}

function checkMultimodalSupervisorControlPlaneContract({
  contractJson = {},
  protoText = "",
  protocolMarkdown = "",
} = {}) {
  const jsonCheck = checkContractJson(contractJson);
  const protoCheck = checkProto(protoText);
  const mdCheck = checkProtocolMarkdown(protocolMarkdown);
  const errors = [...jsonCheck.errors, ...protoCheck.errors, ...mdCheck.errors];
  const warnings = [...jsonCheck.warnings];

  return {
    ok: errors.length === 0,
    errors,
    warnings,
    summary: {
      required_object_total: REQUIRED_OBJECTS.length,
      required_proto_message_total: REQUIRED_PROTO_MESSAGES.length,
      required_supervisor_rpc_total: REQUIRED_SUPERVISOR_RPCS.length,
      required_deny_code_total: REQUIRED_DENY_CODES.length,
    },
  };
}

function main() {
  const args = parseArgs(process.argv);
  const contractJsonPath = path.resolve(REPO_ROOT, args["contract-json"] || DEFAULT_CONTRACT_JSON);
  const protoPath = path.resolve(REPO_ROOT, args.proto || DEFAULT_PROTO);
  const protocolMdPath = path.resolve(REPO_ROOT, args["protocol-md"] || DEFAULT_PROTOCOL_MD);

  const report = checkMultimodalSupervisorControlPlaneContract({
    contractJson: readJson(contractJsonPath),
    protoText: readText(protoPath),
    protocolMarkdown: readText(protocolMdPath),
  });

  const output = {
    ok: report.ok,
    contract_json: path.relative(REPO_ROOT, contractJsonPath),
    proto: path.relative(REPO_ROOT, protoPath),
    protocol_md: path.relative(REPO_ROOT, protocolMdPath),
    errors: report.errors,
    warnings: report.warnings,
    summary: report.summary,
  };

  if (args["out-json"]) {
    const outJsonPath = path.resolve(REPO_ROOT, args["out-json"]);
    writeText(outJsonPath, `${JSON.stringify(output, null, 2)}\n`);
  }

  console.log(JSON.stringify(output, null, 2));
  if (!report.ok) process.exit(1);
}

if (require.main === module) {
  main();
}

module.exports = {
  checkMultimodalSupervisorControlPlaneContract,
  extractProtoMessages,
  extractProtoServiceRpcMap,
};
