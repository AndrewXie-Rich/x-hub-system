#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..");
const defaultSourceGateSummaryPath = path.join(
  repoRoot,
  "build/reports/xhub_doctor_source_gate_summary.v1.json"
);
const defaultAllSmokeEvidencePath = path.join(
  repoRoot,
  "build/reports/xhub_doctor_all_source_smoke_evidence.v1.json"
);
const defaultOutputPath = path.join(
  repoRoot,
  "build/reports/xhub_operator_channel_recovery_report.v1.json"
);

function isoNow() {
  return new Date().toISOString();
}

function readJSON(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function readJSONIfExists(filePath) {
  try {
    if (!fs.existsSync(filePath)) return null;
    return readJSON(filePath);
  } catch {
    return null;
  }
}

function writeJSON(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function normalizeString(value, fallback = "") {
  const trimmed = String(value ?? "").trim();
  return trimmed || fallback;
}

function normalizeArray(value) {
  return Array.isArray(value) ? value : [];
}

function normalizeBoolean(value) {
  return value === true;
}

function printUsage(exitCode) {
  const message = [
    "usage:",
    "  node scripts/generate_xhub_operator_channel_recovery_report.js",
    "  node scripts/generate_xhub_operator_channel_recovery_report.js \\",
    "    --summary build/reports/xhub_doctor_source_gate_summary.v1.json \\",
    "    --all-smoke-evidence build/reports/xhub_doctor_all_source_smoke_evidence.v1.json \\",
    "    --out build/reports/xhub_operator_channel_recovery_report.v1.json",
    "",
  ].join("\n");
  if (exitCode === 0) process.stdout.write(message);
  else process.stderr.write(message);
  process.exit(exitCode);
}

function parseArgs(argv) {
  const out = {
    summaryPath: defaultSourceGateSummaryPath,
    allSmokeEvidencePath: defaultAllSmokeEvidencePath,
    outputPath: defaultOutputPath,
  };

  for (let i = 2; i < argv.length; i += 1) {
    const token = normalizeString(argv[i]);
    switch (token) {
      case "--summary":
        out.summaryPath = path.resolve(normalizeString(argv[++i]));
        break;
      case "--all-smoke-evidence":
        out.allSmokeEvidencePath = path.resolve(normalizeString(argv[++i]));
        break;
      case "--out":
        out.outputPath = path.resolve(normalizeString(argv[++i]));
        break;
      case "--help":
      case "-h":
        printUsage(0);
        break;
      default:
        throw new Error(`unknown arg: ${token}`);
    }
  }
  return out;
}

function normalizeStep(payload) {
  if (!payload || typeof payload !== "object") return null;
  const stepID = normalizeString(payload.step_id || payload.stepID, "");
  const label = normalizeString(payload.label, "");
  const destinationRef = normalizeString(payload.destination_ref || payload.destinationRef, "");
  const instruction = normalizeString(payload.instruction, "");
  if (!stepID && !label && !destinationRef && !instruction) {
    return null;
  }
  return {
    step_id: stepID,
    kind: normalizeString(payload.kind, ""),
    label,
    owner: normalizeString(payload.owner, ""),
    blocking: normalizeBoolean(payload.blocking),
    destination_ref: destinationRef,
    instruction,
  };
}

function parseDetailLines(detailLines) {
  const providers = [];
  const errorCodes = [];
  const fetchErrors = [];
  const requiredNextSteps = [];

  for (const rawLine of normalizeArray(detailLines)) {
    const line = normalizeString(rawLine);
    if (!line) continue;
    if (line.startsWith("fetch_error=")) {
      fetchErrors.push(line.slice("fetch_error=".length));
    }
    if (line.includes("required_next_step=")) {
      const requiredNextStep = normalizeString(line.split("required_next_step=", 2)[1]);
      if (requiredNextStep && requiredNextStep !== "none" && !requiredNextSteps.includes(requiredNextStep)) {
        requiredNextSteps.push(requiredNextStep);
      }
    }
    const parsed = {};
    for (const token of line.split(" ")) {
      if (!token.includes("=")) continue;
      const idx = token.indexOf("=");
      const key = token.slice(0, idx);
      const value = token.slice(idx + 1);
      parsed[key] = value;
    }
    const provider = normalizeString(parsed.provider);
    if (provider && !providers.includes(provider)) providers.push(provider);
    for (const key of ["last_error_code", "deny_code"]) {
      const value = normalizeString(parsed[key]);
      if (value && value !== "none" && !errorCodes.includes(value)) errorCodes.push(value);
    }
  }

  return {
    provider_ids: providers,
    error_codes: errorCodes,
    fetch_errors: fetchErrors,
    required_next_steps: requiredNextSteps,
  };
}

function normalizeCheck(payload) {
  if (!payload || typeof payload !== "object") return null;
  const detailProjection = parseDetailLines(payload.detail_lines);
  const providerIDs = uniqueStrings([
    ...normalizeArray(payload.provider_ids || payload.providerIDs),
    ...detailProjection.provider_ids,
  ]);
  const errorCodes = uniqueStrings([
    ...normalizeArray(payload.error_codes || payload.errorCodes),
    ...detailProjection.error_codes,
  ]);
  const fetchErrors = uniqueStrings([
    ...normalizeArray(payload.fetch_errors || payload.fetchErrors),
    ...detailProjection.fetch_errors,
  ]);
  const requiredNextSteps = uniqueStrings([
    ...normalizeArray(payload.required_next_steps || payload.requiredNextSteps),
    ...detailProjection.required_next_steps,
  ]);
  return {
    check_id: normalizeString(payload.check_id || payload.checkID, ""),
    check_kind: normalizeString(payload.check_kind || payload.checkKind, ""),
    status: normalizeString(payload.status, ""),
    severity: normalizeString(payload.severity, ""),
    blocking: normalizeBoolean(payload.blocking),
    headline: normalizeString(payload.headline, ""),
    message: normalizeString(payload.message, ""),
    next_step: normalizeString(payload.next_step || payload.nextStep, ""),
    repair_destination_ref: normalizeString(payload.repair_destination_ref || payload.repairDestinationRef, ""),
    provider_ids: providerIDs,
    error_codes: errorCodes,
    fetch_errors: fetchErrors,
    required_next_steps: requiredNextSteps,
  };
}

function uniqueStrings(values) {
  const out = [];
  const seen = new Set();
  for (const item of normalizeArray(values)) {
    const normalized = normalizeString(item);
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);
    out.push(normalized);
  }
  return out;
}

function compactDetailedChannelReport(payload) {
  if (!payload || typeof payload !== "object") return null;
  const checks = normalizeArray(payload.checks);
  const currentFailureIssue = normalizeString(payload.current_failure_issue || payload.currentFailureIssue, "");
  let primaryCheck = null;
  if (currentFailureIssue) {
    primaryCheck = checks.find((item) =>
      normalizeString(item?.check_kind || item?.checkKind) === currentFailureIssue
    ) || null;
  }
  if (!primaryCheck) {
    primaryCheck = checks.find((item) => normalizeString(item?.status) === "fail")
      || checks.find((item) => normalizeString(item?.status) === "warn")
      || null;
  }
  const nextSteps = normalizeArray(payload.next_steps || payload.nextSteps);
  return {
    bundle_kind: normalizeString(payload.bundle_kind || payload.bundleKind, ""),
    surface: normalizeString(payload.surface, ""),
    overall_state: normalizeString(payload.overall_state || payload.overallState, ""),
    ready_for_first_task: normalizeBoolean(payload.ready_for_first_task || payload.readyForFirstTask),
    current_failure_code: normalizeString(payload.current_failure_code || payload.currentFailureCode, ""),
    current_failure_issue: currentFailureIssue,
    summary_headline: normalizeString(payload.summary?.headline, ""),
    summary_failed: payload.summary?.failed ?? 0,
    summary_warned: payload.summary?.warned ?? 0,
    summary_passed: payload.summary?.passed ?? 0,
    summary_skipped: payload.summary?.skipped ?? 0,
    primary_check: normalizeCheck(primaryCheck),
    blocking_next_step: normalizeStep(nextSteps.find((item) => item?.blocking === true) || null),
    advisory_next_step: normalizeStep(nextSteps.find((item) => item?.blocking !== true) || null),
    report_path: normalizeString(payload.report_path || payload.reportPath, ""),
    source_report_path: normalizeString(payload.source_report_path || payload.sourceReportPath, ""),
  };
}

function normalizeCompactChannelReport(payload) {
  if (!payload || typeof payload !== "object") return null;
  const primaryCheck = normalizeCheck(payload.primary_check || payload.primaryCheck);
  return {
    bundle_kind: normalizeString(payload.bundle_kind || payload.bundleKind, ""),
    surface: normalizeString(payload.surface, ""),
    overall_state: normalizeString(payload.overall_state || payload.overallState, ""),
    ready_for_first_task: normalizeBoolean(payload.ready_for_first_task || payload.readyForFirstTask),
    current_failure_code: normalizeString(payload.current_failure_code || payload.currentFailureCode, ""),
    current_failure_issue: normalizeString(payload.current_failure_issue || payload.currentFailureIssue, ""),
    summary_headline: normalizeString(payload.summary_headline || payload.summary?.headline, ""),
    summary_failed: payload.summary_failed ?? payload.summary?.failed ?? 0,
    summary_warned: payload.summary_warned ?? payload.summary?.warned ?? 0,
    summary_passed: payload.summary_passed ?? payload.summary?.passed ?? 0,
    summary_skipped: payload.summary_skipped ?? payload.summary?.skipped ?? 0,
    primary_check: primaryCheck,
    blocking_next_step: normalizeStep(payload.blocking_next_step || payload.blockingNextStep),
    advisory_next_step: normalizeStep(payload.advisory_next_step || payload.advisoryNextStep),
    report_path: normalizeString(payload.report_path || payload.reportPath, ""),
    source_report_path: normalizeString(payload.source_report_path || payload.sourceReportPath, ""),
  };
}

function normalizeCliSummary(payload) {
  if (!payload || typeof payload !== "object") return null;
  const channel = payload.channel || {};
  return {
    channel: {
      output_path: normalizeString(channel.output_path || channel.outputPath, ""),
      current_failure_code: normalizeString(channel.current_failure_code || channel.currentFailureCode, ""),
      current_failure_issue: normalizeString(channel.current_failure_issue || channel.currentFailureIssue, ""),
      primary_next_step: normalizeStep(channel.primary_next_step || channel.primaryNextStep),
      blocking_next_step: normalizeStep(channel.blocking_next_step || channel.blockingNextStep),
      advisory_next_step: normalizeStep(channel.advisory_next_step || channel.advisoryNextStep),
    },
  };
}

function extractChannelTruth(sourceGateSummary, allSmokeEvidence) {
  const support = sourceGateSummary?.hub_channel_onboarding_support || {};
  const compactReport = normalizeCompactChannelReport(support.hub_channel_onboarding_report);
  const compactCli = normalizeCliSummary(support.hub_doctor_cli_summary);
  const detailedReport = compactDetailedChannelReport(allSmokeEvidence?.hub_channel_onboarding_report);
  const detailedCli = normalizeCliSummary(allSmokeEvidence?.hub_doctor_cli_summary);

  const report = compactReport && compactReport.current_failure_code ? compactReport : detailedReport;
  const cli = compactCli && compactCli.channel?.current_failure_code ? compactCli : detailedCli;
  const source = report === compactReport
    ? "source_gate_summary"
    : report === detailedReport
      ? "all_source_smoke_evidence"
      : "missing";
  const primaryCheck = report?.primary_check || null;

  return {
    source,
    source_gate_overall_status: normalizeString(sourceGateSummary?.overall_status, "missing"),
    all_source_smoke_status: normalizeString(support.all_source_smoke_status || allSmokeEvidence?.status, "missing"),
    support_ready: !!(report && normalizeString(report.current_failure_code)),
    overall_state: normalizeString(report?.overall_state, ""),
    ready_for_first_task: normalizeBoolean(report?.ready_for_first_task),
    current_failure_code: normalizeString(
      report?.current_failure_code || cli?.channel?.current_failure_code,
      ""
    ),
    current_failure_issue: normalizeString(
      report?.current_failure_issue || cli?.channel?.current_failure_issue,
      ""
    ),
    summary_headline: normalizeString(report?.summary_headline, ""),
    summary_failed: report?.summary_failed ?? 0,
    summary_warned: report?.summary_warned ?? 0,
    summary_passed: report?.summary_passed ?? 0,
    summary_skipped: report?.summary_skipped ?? 0,
    primary_check_kind: normalizeString(primaryCheck?.check_kind, ""),
    primary_check_status: normalizeString(primaryCheck?.status, ""),
    primary_check_blocking: normalizeBoolean(primaryCheck?.blocking),
    primary_check_headline: normalizeString(primaryCheck?.headline, ""),
    primary_check_message: normalizeString(primaryCheck?.message, ""),
    primary_check_next_step: normalizeString(primaryCheck?.next_step, ""),
    repair_destination_ref: normalizeString(primaryCheck?.repair_destination_ref, ""),
    provider_ids: normalizeArray(primaryCheck?.provider_ids).map((item) => normalizeString(item)).filter(Boolean),
    error_codes: normalizeArray(primaryCheck?.error_codes).map((item) => normalizeString(item)).filter(Boolean),
    fetch_errors: normalizeArray(primaryCheck?.fetch_errors).map((item) => normalizeString(item)).filter(Boolean),
    required_next_steps: normalizeArray(primaryCheck?.required_next_steps).map((item) => normalizeString(item)).filter(Boolean),
    primary_next_step: normalizeStep(
      cli?.channel?.primary_next_step || report?.blocking_next_step || report?.advisory_next_step
    ),
    blocking_next_step: normalizeStep(
      cli?.channel?.blocking_next_step || report?.blocking_next_step
    ),
    advisory_next_step: normalizeStep(
      cli?.channel?.advisory_next_step || report?.advisory_next_step
    ),
    report_path: normalizeString(report?.report_path, ""),
    source_report_path: normalizeString(report?.source_report_path, ""),
    cli_output_path: normalizeString(cli?.channel?.output_path, ""),
  };
}

function stepToAction(step, fallbackID, fallbackTitle, fallbackWhy) {
  const normalized = normalizeStep(step);
  if (!normalized) return null;
  return {
    action_id: normalizeString(normalized.step_id, fallbackID),
    title: normalizeString(normalized.label, fallbackTitle),
    why: normalizeString(fallbackWhy, "Follow the machine-readable doctor next step."),
    command_or_ref: normalizeString(normalized.destination_ref || normalized.instruction, ""),
  };
}

function uniqueActions(actions) {
  const out = [];
  const seen = new Set();
  for (const item of actions) {
    if (!item || typeof item !== "object") continue;
    const actionID = normalizeString(item.action_id);
    const title = normalizeString(item.title);
    const commandOrRef = normalizeString(item.command_or_ref);
    if (!actionID && !title && !commandOrRef) continue;
    const key = `${actionID}::${title}::${commandOrRef}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({
      action_id: actionID,
      title,
      why: normalizeString(item.why),
      command_or_ref: commandOrRef,
    });
  }
  return out;
}

function includesHeartbeatGovernanceVisibilityGap(value) {
  const normalized = normalizeString(value).toLowerCase();
  if (!normalized) return false;
  return normalized.includes("heartbeat governance visibility")
    || normalized.includes("heartbeat_governance_snapshot")
    || normalized.includes("heartbeat_visibility")
    || normalized.includes("quality band / next review")
    || normalized.includes("heartbeat quality")
    || (normalized.includes("heartbeat") && normalized.includes("next review"));
}

function hasHeartbeatGovernanceVisibilityGap(truth) {
  return [
    truth.current_failure_code,
    truth.current_failure_issue,
    truth.primary_check_kind,
    truth.primary_check_headline,
    truth.primary_check_message,
    truth.primary_check_next_step,
    truth.repair_destination_ref,
    ...normalizeArray(truth.required_next_steps),
  ].some((value) => includesHeartbeatGovernanceVisibilityGap(value));
}

function classifyRecovery(truth) {
  const codes = [
    truth.current_failure_code,
    ...truth.error_codes,
  ].map((value) => normalizeString(value).toLowerCase()).filter(Boolean);
  const replayCodes = new Set(["replay_detected", "webhook_replay_detected", "replay_guard_error"]);
  const signatureCodes = new Set([
    "signature_missing",
    "signature_invalid",
    "webhook_signature_invalid",
    "signature_timestamp_missing",
    "request_timestamp_out_of_range",
    "verification_token_missing",
    "verification_token_missing_in_payload",
    "verify_token_missing",
    "verify_token_invalid",
    "signing_secret_missing",
    "app_secret_missing",
  ]);
  const credentialCodes = new Set([
    "connector_token_missing",
    "unauthenticated",
    "bot_token_missing",
    "slack_bot_token_missing",
    "tenant_access_token_missing",
    "feishu_app_secret_missing",
    "reply_credentials_missing",
    "provider_delivery_not_configured",
  ]);
  const revokedCodes = new Set(["revoked", "binding_revoked", "channel_revoked"]);
  const preferredProvider = truth.provider_ids[0] || "operator_channel";
  const rerunAction = {
    action_id: "rerun_doctor_source_gate",
    title: "Rerun cross-surface doctor source gate",
    why: "Refresh the Hub runtime doctor, channel onboarding doctor, XT doctor, and the aggregate evidence from one command.",
    command_or_ref: "bash scripts/ci/xhub_doctor_source_gate.sh",
  };

  if (hasHeartbeatGovernanceVisibilityGap(truth)) {
    return {
      actionCategory: "restore_heartbeat_governance_visibility",
      severity: "medium",
      installHint: "Re-run or reload first smoke until heartbeat governance quality / next-review visibility is exported; do not treat onboarding proof as complete before that.",
      recommendedActions: uniqueActions([
        {
          action_id: "restore_heartbeat_governance_visibility",
          title: "Restore heartbeat governance visibility",
          why: "The first live-test proof exists, but heartbeat quality / next-review visibility did not survive into the governed onboarding evidence chain.",
          command_or_ref: truth.required_next_steps[0] || truth.primary_check_next_step || truth.repair_destination_ref || "hub://settings/operator_channels",
        },
        stepToAction(
          truth.primary_next_step || truth.blocking_next_step || truth.advisory_next_step,
          "inspect_operator_channel_diagnostics",
          "Inspect operator channel diagnostics",
          "Verify the first-smoke projection exported heartbeat quality and next-review truth before retrying release wording."
        ),
        rerunAction,
      ]),
    };
  }

  if (truth.current_failure_code === "channel_status_unavailable" || truth.fetch_errors.length > 0) {
    return {
      actionCategory: "restore_channel_admin_surface",
      severity: "high",
      installHint: "Restore the Hub admin/onboarding surface before trusting any remote channel readiness snapshot.",
      recommendedActions: uniqueActions([
        {
          action_id: "restore_channel_admin_surface",
          title: "Restore operator channel admin surface",
          why: "The Hub doctor could not fetch current operator-channel onboarding/runtime truth, so governed remote approval must fail closed.",
          command_or_ref: truth.repair_destination_ref || "hub://settings/operator_channels",
        },
        stepToAction(
          truth.primary_next_step,
          "open_operator_channel_repair_surface",
          "Open operator channel repair surface",
          "Use the doctor-reported repair surface before retrying external traffic."
        ),
        rerunAction,
      ]),
    };
  }

  if (codes.some((code) => replayCodes.has(code))) {
    return {
      actionCategory: "repair_replay_protection",
      severity: "high",
      installHint: "Repair replay protection first, then ask the operator to send a fresh message instead of replaying the old payload.",
      recommendedActions: uniqueActions([
        {
          action_id: "repair_replay_protection",
          title: "Repair replay protection and request a fresh message",
          why: "Hub already marked this channel event path as replay-suspect or replay-guard-failed, so old payloads must not be trusted.",
          command_or_ref: truth.primary_check_next_step || truth.repair_destination_ref || "hub://settings/operator_channels",
        },
        stepToAction(
          truth.blocking_next_step || truth.primary_next_step,
          "open_operator_channel_repair_surface",
          "Open operator channel repair surface",
          "Use the repair surface that the doctor already pointed to."
        ),
        rerunAction,
      ]),
    };
  }

  if (codes.some((code) => signatureCodes.has(code))) {
    return {
      actionCategory: "repair_signature_or_webhook_verification",
      severity: "high",
      installHint: "Repair webhook signature or verification-token validation before re-enabling external ingress.",
      recommendedActions: uniqueActions([
        {
          action_id: "repair_signature_or_webhook_verification",
          title: "Repair webhook signature or verification token",
          why: `The ${preferredProvider} ingress path is failing fail-closed verification, so remote requests cannot be treated as trusted input yet.`,
          command_or_ref: truth.primary_check_next_step || truth.repair_destination_ref || "hub://settings/operator_channels",
        },
        stepToAction(
          truth.blocking_next_step || truth.primary_next_step,
          "open_operator_channel_repair_surface",
          "Open operator channel repair surface",
          "Use the channel repair surface to fix the provider webhook configuration."
        ),
        rerunAction,
      ]),
    };
  }

  if (codes.some((code) => credentialCodes.has(code))
      || truth.current_failure_code === "channel_delivery_not_ready"
      || truth.current_failure_code === "channel_delivery_partially_ready") {
    return {
      actionCategory: "repair_channel_credentials",
      severity: "high",
      installHint: "Repair reply credentials or connector tokens in the running Hub process before retrying delivery or governed approval.",
      recommendedActions: uniqueActions([
        {
          action_id: "repair_channel_credentials",
          title: "Repair channel credentials or connector token",
          why: `The ${preferredProvider} provider is not fully ready for governed delivery, so Hub must stay fail-closed until credentials are fixed.`,
          command_or_ref: truth.primary_check_next_step || truth.repair_destination_ref || "hub://settings/operator_channels",
        },
        stepToAction(
          truth.primary_next_step,
          "refresh_provider_readiness",
          "Refresh provider readiness",
          "Re-run readiness only after the provider credentials are reloaded."
        ),
        rerunAction,
      ]),
    };
  }

  if (codes.some((code) => revokedCodes.has(code)) || truth.current_failure_code.includes("revoked")) {
    return {
      actionCategory: "reissue_onboarding_after_revocation",
      severity: "high",
      installHint: "Treat revoked channel bindings as permanently invalid; only proceed by creating a new governed onboarding ticket.",
      recommendedActions: uniqueActions([
        {
          action_id: "reissue_onboarding_after_revocation",
          title: "Create a new governed onboarding ticket",
          why: "A revoked channel binding must not be silently reactivated or reused.",
          command_or_ref: truth.repair_destination_ref || "hub://settings/operator_channels",
        },
        rerunAction,
      ]),
    };
  }

  if (truth.primary_check_kind === "channel_live_test" || truth.current_failure_code.startsWith("channel_live_test")) {
    return {
      actionCategory: "complete_first_live_test",
      severity: "medium",
      installHint: "Finish the governed first live test and only treat the provider as ready after the report turns pass.",
      recommendedActions: uniqueActions([
        {
          action_id: "complete_first_live_test",
          title: "Complete governed first live test",
          why: "The provider has not yet closed the onboarding proof chain that Hub requires before treating it as a stable remote approval surface.",
          command_or_ref: truth.primary_check_next_step || truth.repair_destination_ref || "hub://settings/operator_channels",
        },
        stepToAction(
          truth.primary_next_step,
          "inspect_operator_channel_diagnostics",
          "Inspect operator channel diagnostics",
          "Use the live-test evidence path that the doctor already reported."
        ),
        rerunAction,
      ]),
    };
  }

  if (truth.current_failure_code === "channel_runtime_missing" || truth.current_failure_code === "channel_delivery_missing") {
    return {
      actionCategory: "refresh_channel_readiness_snapshot",
      severity: "medium",
      installHint: "Refresh the channel runtime/readiness snapshot before making a governed approval decision.",
      recommendedActions: uniqueActions([
        {
          action_id: "refresh_channel_readiness_snapshot",
          title: "Refresh channel runtime and readiness snapshot",
          why: "Hub has not yet observed enough operator-channel runtime truth to authorize external ingress confidently.",
          command_or_ref: truth.primary_check_next_step || truth.repair_destination_ref || "hub://settings/operator_channels",
        },
        rerunAction,
      ]),
    };
  }

  if (truth.current_failure_code === "channel_runtime_not_ready" || truth.current_failure_code === "channel_runtime_partially_ready") {
    return {
      actionCategory: "repair_blocking_channel_provider",
      severity: truth.primary_check_blocking ? "high" : "medium",
      installHint: "Repair the blocking channel runtime state before allowing governed external requests through this provider.",
      recommendedActions: uniqueActions([
        {
          action_id: "repair_blocking_channel_provider",
          title: "Repair blocking channel runtime state",
          why: `The ${preferredProvider} runtime still reports blocked or degraded operator-channel state.`,
          command_or_ref: truth.primary_check_next_step || truth.repair_destination_ref || "hub://settings/operator_channels",
        },
        stepToAction(
          truth.blocking_next_step || truth.primary_next_step,
          "open_operator_channel_repair_surface",
          "Open operator channel repair surface",
          "Use the Hub repair surface before retrying any remote approval path."
        ),
        rerunAction,
      ]),
    };
  }

  return {
    actionCategory: "inspect_channel_onboarding_report",
    severity: "medium",
    installHint: "Inspect the unified channel onboarding doctor report before allowing external requests into Hub-governed flows.",
    recommendedActions: uniqueActions([
      {
        action_id: "inspect_channel_onboarding_report",
        title: "Inspect channel onboarding doctor report",
        why: "The current issue did not map to a narrower recovery category, so the machine-readable doctor report remains the source of truth.",
        command_or_ref: truth.report_path || truth.repair_destination_ref || "hub://settings/operator_channels",
      },
      stepToAction(
        truth.primary_next_step,
        "inspect_operator_channel_diagnostics",
        "Inspect operator channel diagnostics",
        "Follow the doctor-reported next step before retrying remote ingress."
      ),
      rerunAction,
    ]),
  };
}

function buildSupportFAQ(truth, recovery) {
  return [
    {
      faq_id: "why_fail_closed",
      question: "Why is Hub still fail-closed for this remote channel?",
      answer: truth.current_failure_code
        ? `Because the current doctor truth is ${truth.current_failure_code}, and governed remote approval must not proceed while onboarding evidence is incomplete or degraded.`
        : "Because Hub could not confirm a complete operator-channel onboarding truth chain.",
    },
    {
      faq_id: "current_primary_issue",
      question: "What is the current primary operator-channel issue?",
      answer: normalizeString(
        `${truth.primary_check_headline}. ${truth.primary_check_message}`.trim(),
        "The machine-readable doctor report did not include a primary headline/message."
      ),
    },
    {
      faq_id: "next_operator_move",
      question: "What should the operator do next?",
      answer: recovery.recommendedActions[0]
        ? `${recovery.recommendedActions[0].title}. ${recovery.recommendedActions[0].why}`
        : normalizeString(truth.primary_check_next_step, "Inspect the operator-channel doctor output before retrying."),
    },
  ];
}

function buildReleaseWording(truth, supportReady) {
  const heartbeatVisibilityGap = hasHeartbeatGovernanceVisibilityGap(truth);
  return {
    capability_matrix_status: supportReady ? "preview-working" : "implementation-in-progress",
    external_status_line: supportReady
      ? "Structured operator-channel onboarding doctor truth is available, but this surface remains preview-working rather than validated."
      : "Structured operator-channel onboarding recovery truth is incomplete, so remote onboarding claims must stay conservative.",
    allowed_claims: supportReady
      ? [
          "Hub doctor exports machine-readable operator-channel current failure, repair destination, and next steps.",
          "Source-gate evidence now carries channel onboarding repair truth alongside XT and Hub runtime doctor outputs.",
          "Support/operator tooling can reuse one governed onboarding diagnosis instead of reverse-parsing UI text.",
        ]
      : [],
    blocked_claims: [
      "Do not describe operator-channel onboarding as fully polished or validated while capability matrix status remains below validated.",
      "Do not allow external requests to bypass Hub because a single provider appears partially ready.",
      `Do not downplay the current primary issue (${normalizeString(truth.current_failure_code, "missing_issue")}) as a cosmetic warning.`,
      ...(heartbeatVisibilityGap
        ? ["Do not treat first smoke as complete while heartbeat governance visibility (quality band / next review) is missing from the evidence chain."]
        : []),
    ],
  };
}

function buildOperatorChannelRecoveryReport(inputs = {}) {
  const generatedAt = inputs.generatedAt || isoNow();
  const timezone = inputs.timezone || "Asia/Shanghai";
  const sourceGateSummary = inputs.sourceGateSummary || null;
  const allSmokeEvidence = inputs.allSmokeEvidence || null;
  const truth = extractChannelTruth(sourceGateSummary, allSmokeEvidence);
  const supportReady = truth.support_ready && truth.all_source_smoke_status === "pass";
  const recovery = classifyRecovery(truth);
  const gateVerdict = supportReady
    ? "PASS(channel_onboarding_recovery_report_generated_from_structured_doctor_truth)"
    : "NO_GO(hub_channel_onboarding_support_missing)";
  const verdictReason = supportReady
    ? `Structured operator-channel onboarding truth is available for ${normalizeString(truth.current_failure_code, "unknown_issue")}, so operator/support wording can reuse one machine-readable diagnosis.`
    : "Structured operator-channel onboarding truth is missing or stale, so recovery/reporting must fail closed.";

  return {
    schema_version: "xhub.operator.channel_onboarding_recovery_report.v1",
    generated_at: generatedAt,
    timezone,
    scope: "operator channel onboarding / governed remote approval / repair path",
    fail_closed: true,
    gate_verdict: gateVerdict,
    verdict_reason: verdictReason,
    release_stance: supportReady ? "preview_working" : "no_go",
    machine_decision: {
      support_ready: supportReady,
      source: truth.source,
      source_gate_status: truth.source_gate_overall_status,
      all_source_smoke_status: truth.all_source_smoke_status,
      overall_state: truth.overall_state,
      ready_for_first_task: truth.ready_for_first_task,
      current_failure_code: truth.current_failure_code,
      current_failure_issue: truth.current_failure_issue,
      action_category: recovery.actionCategory,
    },
    onboarding_truth: {
      overall_state: truth.overall_state,
      ready_for_first_task: truth.ready_for_first_task,
      current_failure_code: truth.current_failure_code,
      current_failure_issue: truth.current_failure_issue,
      summary_headline: truth.summary_headline,
      summary_failed: truth.summary_failed,
      summary_warned: truth.summary_warned,
      summary_passed: truth.summary_passed,
      summary_skipped: truth.summary_skipped,
      primary_check_kind: truth.primary_check_kind,
      primary_check_status: truth.primary_check_status,
      primary_check_blocking: truth.primary_check_blocking,
      primary_check_headline: truth.primary_check_headline,
      primary_check_message: truth.primary_check_message,
      primary_check_next_step: truth.primary_check_next_step,
      repair_destination_ref: truth.repair_destination_ref,
      provider_ids: truth.provider_ids,
      error_codes: truth.error_codes,
      fetch_errors: truth.fetch_errors,
      required_next_steps: truth.required_next_steps,
      report_path: truth.report_path,
      source_report_path: truth.source_report_path,
      cli_output_path: truth.cli_output_path,
    },
    recovery_classification: {
      action_category: recovery.actionCategory,
      severity: recovery.severity,
      install_hint: recovery.installHint,
    },
    recommended_actions: recovery.recommendedActions.map((action, index) => ({
      rank: index + 1,
      ...action,
    })),
    support_faq: buildSupportFAQ(truth, recovery),
    release_wording: buildReleaseWording(truth, supportReady),
    evidence_refs: [
      "build/reports/xhub_doctor_source_gate_summary.v1.json",
      "build/reports/xhub_doctor_all_source_smoke_evidence.v1.json",
      "scripts/generate_xhub_operator_channel_recovery_report.js",
    ],
    inputs: {
      source_gate_summary_present: !!sourceGateSummary,
      all_source_smoke_evidence_present: !!allSmokeEvidence,
      source_gate_summary_ref: "build/reports/xhub_doctor_source_gate_summary.v1.json",
      all_source_smoke_evidence_ref: "build/reports/xhub_doctor_all_source_smoke_evidence.v1.json",
    },
  };
}

function main() {
  const args = parseArgs(process.argv);
  const sourceGateSummary = readJSONIfExists(args.summaryPath);
  const allSmokeEvidence = readJSONIfExists(args.allSmokeEvidencePath);
  const report = buildOperatorChannelRecoveryReport({
    sourceGateSummary,
    allSmokeEvidence,
  });
  writeJSON(args.outputPath, report);
  process.stdout.write(`${args.outputPath}\n`);
}

if (require.main === module) {
  main();
}

module.exports = {
  buildOperatorChannelRecoveryReport,
  classifyRecovery,
  extractChannelTruth,
  parseArgs,
};
