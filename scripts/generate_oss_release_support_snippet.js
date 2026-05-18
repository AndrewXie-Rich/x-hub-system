#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const DEFAULT_PACKET_REF = "build/reports/lpr_w4_09_c_product_exit_packet.v1.json";
const DEFAULT_OUTPUT_REF = "build/reports/oss_release_support_snippet.v1.md";

function isoNow() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
}

function normalizeString(value, fallback = "") {
  const trimmed = String(value ?? "").trim();
  return trimmed || fallback;
}

function normalizeArray(value) {
  return Array.isArray(value) ? value.filter((item) => item !== null && item !== undefined) : [];
}

function resolveRef(refOrPath) {
  const raw = normalizeString(refOrPath);
  if (!raw) return "";
  return path.isAbsolute(raw) ? raw : path.join(ROOT, raw);
}

function readJSON(refOrPath) {
  return JSON.parse(fs.readFileSync(resolveRef(refOrPath), "utf8"));
}

function writeText(refOrPath, content) {
  const filePath = resolveRef(refOrPath);
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, String(content || ""), "utf8");
}

function printUsage(exitCode = 0) {
  const usage = [
    "usage:",
    "  node scripts/generate_oss_release_support_snippet.js",
    "  node scripts/generate_oss_release_support_snippet.js \\",
    "    --packet build/reports/lpr_w4_09_c_product_exit_packet.v1.json \\",
    "    --out build/reports/oss_release_support_snippet.v1.md",
    "",
  ].join("\n");
  if (exitCode === 0) process.stdout.write(usage);
  else process.stderr.write(usage);
  process.exit(exitCode);
}

function parseArgs(argv) {
  const args = {
    packetPath: DEFAULT_PACKET_REF,
    outputPath: DEFAULT_OUTPUT_REF,
  };
  for (let i = 2; i < argv.length; i += 1) {
    const token = normalizeString(argv[i]);
    if (!token) continue;
    if (token === "--help" || token === "-h") printUsage(0);
    if (token === "--packet") {
      i += 1;
      args.packetPath = normalizeString(argv[i]);
      if (!args.packetPath) throw new Error("--packet requires a value");
      continue;
    }
    if (token === "--out") {
      i += 1;
      args.outputPath = normalizeString(argv[i]);
      if (!args.outputPath) throw new Error("--out requires a value");
      continue;
    }
    throw new Error(`unknown arg: ${token}`);
  }
  return args;
}

function yesNoUnknown(value) {
  if (value === true) return "yes";
  if (value === false) return "no";
  return "unknown";
}

function firstAction(action, fallbackActions = []) {
  if (action && typeof action === "object") return action;
  return normalizeArray(fallbackActions).find((item) => item && typeof item === "object") || null;
}

function formatAction(action) {
  if (!action || typeof action !== "object") return "not available";
  const title = normalizeString(
    action.title || action.action_summary || action.label || action.action_id,
    "not available"
  );
  const target = normalizeString(action.command_or_ref || action.next_step || action.command);
  return target ? `${title} -> ${target}` : title;
}

function formatIssue(code, issue) {
  const normalizedCode = normalizeString(code, "missing");
  const normalizedIssue = normalizeString(issue, "missing");
  return `${normalizedCode} (${normalizedIssue})`;
}

function formatProviderKeyRoute(focus) {
  if (!focus || typeof focus !== "object" || focus.support_ready !== true) {
    return "not available";
  }
  const modelId = normalizeString(focus.requested_model_id, "missing_model");
  const selectedAccount = normalizeString(focus.selected_account_key, "unselected");
  const wireAPI = normalizeString(focus.selected_wire_api, "");
  return wireAPI
    ? `${modelId} -> ${selectedAccount} via ${wireAPI}`
    : `${modelId} -> ${selectedAccount}`;
}

function formatProviderKeyRetry(focus) {
  if (!focus || typeof focus !== "object" || focus.support_ready !== true) {
    return "not available";
  }
  const retryAtMs = Number.isFinite(focus.next_retry_at_ms) ? focus.next_retry_at_ms : null;
  if (!retryAtMs || retryAtMs <= 0) return "not scheduled";
  const retryAtISO = normalizeString(focus.next_retry_at_iso, "");
  const retryAccount = normalizeString(focus.next_retry_account_key, "");
  const retryReason = normalizeString(focus.next_retry_reason_code, "");
  const headline = retryAccount
    ? `${retryAccount} at ${retryAtISO || retryAtMs}`
    : `${retryAtISO || retryAtMs}`;
  return retryReason ? `${headline} reason=${retryReason}` : headline;
}

function formatProviderKeyCandidateHealth(focus) {
  if (!focus || typeof focus !== "object" || focus.support_ready !== true) {
    return "not available";
  }
  return `total=${Number.isFinite(focus.candidate_count) ? focus.candidate_count : 0}; cooldown=${
    Number.isFinite(focus.cooldown_candidate_count) ? focus.cooldown_candidate_count : 0
  }; stale=${Number.isFinite(focus.stale_candidate_count) ? focus.stale_candidate_count : 0}; blocked=${
    Number.isFinite(focus.blocked_candidate_count) ? focus.blocked_candidate_count : 0
  }`;
}

function renderBulletList(values, fallback = "none") {
  const items = normalizeArray(values)
    .map((value) => normalizeString(value))
    .filter(Boolean);
  if (items.length === 0) return [`- ${fallback}`];
  return items.map((item) => `- ${item}`);
}

function buildReleaseSupportSnippet(packet, options = {}) {
  const payload = packet && typeof packet === "object" ? packet : {};
  const generatedAt = normalizeString(options.generatedAt || payload.generated_at, isoNow());
  const packetRef = normalizeString(options.packetRef, DEFAULT_PACKET_REF);
  const releaseHandoff =
    payload.release_handoff && typeof payload.release_handoff === "object"
      ? payload.release_handoff
      : {};
  const operatorHandoff =
    payload.operator_handoff && typeof payload.operator_handoff === "object"
      ? payload.operator_handoff
      : {};
  const channelFocus =
    operatorHandoff.channel_onboarding_focus &&
    typeof operatorHandoff.channel_onboarding_focus === "object"
      ? operatorHandoff.channel_onboarding_focus
      : null;
  const requireRealFocus =
    operatorHandoff.require_real_focus && typeof operatorHandoff.require_real_focus === "object"
      ? operatorHandoff.require_real_focus
      : null;
  const providerKeyFocus =
    operatorHandoff.provider_key_selection_focus
    && typeof operatorHandoff.provider_key_selection_focus === "object"
      ? operatorHandoff.provider_key_selection_focus
      : null;
  const localServiceAction = firstAction(
    operatorHandoff.top_recommended_action,
    operatorHandoff.recommended_actions
  );
  const channelAction = firstAction(
    channelFocus?.top_recommended_action,
    channelFocus?.recommended_actions
  );
  const releaseBlockers = renderBulletList(releaseHandoff.release_blockers);
  const rerunCommands = renderBulletList(operatorHandoff.next_commands, "none recorded");
  const runbookRefs = renderBulletList(operatorHandoff.runbook_refs, "none recorded");
  const publicLocalLine = normalizeString(
    releaseHandoff.external_status_line,
    "Structured local-service recovery wording is not available."
  );
  const publicChannelLine = normalizeString(
    releaseHandoff.remote_channel_status_line,
    "Structured operator-channel onboarding recovery wording is not available."
  );
  const lines = [
    "# OSS Release Support Snippet v1",
    "",
    `Generated at: ${generatedAt}`,
    `Source packet: ${packetRef}`,
    "",
    "## Public-Safe Wording",
    "",
    "Use these lines only in support/status lanes. They do not expand the validated public release slice.",
    "",
    `- Local-service recovery: ${publicLocalLine}`,
    `- Operator-channel onboarding: ${publicChannelLine}`,
    "",
    "Optional copy-paste operator-channel line:",
    "",
    `> ${publicChannelLine}`,
    "",
    "Guardrail:",
    "- Keep the operator-channel line in preview/support wording only; do not present it as a validated release claim.",
    "- Keep remote provider-key routing details in the internal operator handoff only; do not expose selected account keys in public status wording.",
    "- Local-service recovery and require-real closure remain the release-gating truth.",
    "",
    "## Release Operator Snapshot",
    "",
    `- OSS release stance: ${normalizeString(releaseHandoff.oss_release_stance, "missing")}`,
    `- Boundary status: ${normalizeString(releaseHandoff.boundary_status, "missing")}`,
    `- Refresh bundle ready: ${yesNoUnknown(releaseHandoff.refresh_bundle_ready)}`,
    "Release blockers:",
    ...releaseBlockers,
    "",
    "## Internal Operator Handoff",
    "",
    `- Local-service primary issue: ${normalizeString(operatorHandoff.primary_issue_reason_code, "unknown")}`,
    `- Local-service managed process state: ${normalizeString(operatorHandoff.managed_process_state, "unknown")}`,
    `- Local-service next action: ${formatAction(localServiceAction)}`,
    `- Channel support ready: ${yesNoUnknown(channelFocus?.support_ready)}`,
    `- Channel current failure: ${formatIssue(
      channelFocus?.current_failure_code,
      channelFocus?.current_failure_issue
    )}`,
    `- Channel governance visibility gap: ${yesNoUnknown(
      channelFocus?.heartbeat_governance_visibility_gap
    )}`,
    `- Channel focus highlight: ${normalizeString(
      channelFocus?.channel_focus_highlight,
      "none"
    )}`,
    `- Channel action category: ${normalizeString(channelFocus?.action_category, "missing")}`,
    `- Channel next action: ${formatAction(channelAction)}`,
    `- Remote provider-key support ready: ${yesNoUnknown(providerKeyFocus?.support_ready)}`,
    `- Remote provider-key route: ${formatProviderKeyRoute(providerKeyFocus)}`,
    `- Remote provider-key next retry: ${formatProviderKeyRetry(providerKeyFocus)}`,
    `- Remote provider-key candidate health: ${formatProviderKeyCandidateHealth(providerKeyFocus)}`,
  ];

  if (requireRealFocus) {
    lines.push(
      "",
      "## Require-Real Focus",
      "",
      `- Sample1 handoff state: ${normalizeString(requireRealFocus.handoff_state, "missing")}`,
      `- Sample1 blocker class: ${normalizeString(requireRealFocus.blocker_class, "missing")}`,
      `- Sample1 next action: ${formatAction(requireRealFocus.top_recommended_action)}`
    );
  }

  lines.push(
    "",
    "## Rerun Commands",
    "",
    ...rerunCommands,
    "",
    "## Runbook Refs",
    "",
    ...runbookRefs,
    ""
  );

  return {
    generated_at: generatedAt,
    packet_ref: packetRef,
    markdown: `${lines.join("\n")}\n`,
  };
}

function main() {
  const args = parseArgs(process.argv);
  const packet = readJSON(args.packetPath);
  const snippet = buildReleaseSupportSnippet(packet, {
    packetRef: args.packetPath,
  });
  writeText(args.outputPath, snippet.markdown);
  process.stdout.write(`${args.outputPath}\n`);
}

if (require.main === module) {
  main();
}

module.exports = {
  buildReleaseSupportSnippet,
  parseArgs,
};
