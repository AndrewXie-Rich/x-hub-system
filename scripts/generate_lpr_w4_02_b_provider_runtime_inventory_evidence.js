#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");
const { pathToFileURL } = require("node:url");

const repoRoot = path.resolve(__dirname, "..");
const defaultOutputPath = path.join(
  repoRoot,
  "build/reports/lpr_w4_02_b_provider_runtime_inventory_evidence.v1.json"
);
const allowedRuntimeResolutionStates = [
  "pack_runtime_ready",
  "user_runtime_fallback",
  "runtime_missing",
];

function isoNow() {
  return new Date().toISOString();
}

function normalizeString(value, fallback = "") {
  const trimmed = String(value ?? "").trim();
  return trimmed || fallback;
}

function normalizeBoolean(value) {
  return value === true;
}

function normalizeArray(value) {
  return Array.isArray(value) ? value : [];
}

function normalizeObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function uniqueStrings(values = []) {
  const seen = new Set();
  const out = [];
  for (const value of values) {
    const normalized = normalizeString(value);
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);
    out.push(normalized);
  }
  return out;
}

function writeJSON(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function parseArgs(argv) {
  const out = {
    runtimeBaseDir: "",
    maxAgeMs: 86_400_000,
    outputPath: defaultOutputPath,
  };

  for (let i = 2; i < argv.length; i += 1) {
    const token = normalizeString(argv[i]);
    switch (token) {
      case "--runtime-base-dir":
        out.runtimeBaseDir = path.resolve(normalizeString(argv[++i]));
        break;
      case "--max-age-ms":
        out.maxAgeMs = Math.max(1, Math.floor(Number(argv[++i] || 0) || 0));
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

function printUsage(exitCode) {
  const message = [
    "usage:",
    "  node scripts/generate_lpr_w4_02_b_provider_runtime_inventory_evidence.js",
    "  node scripts/generate_lpr_w4_02_b_provider_runtime_inventory_evidence.js \\",
    "    --runtime-base-dir ~/Library/Containers/com.rel.flowhub/Data/RELFlowHub \\",
    "    --max-age-ms 86400000 \\",
    "    --out build/reports/lpr_w4_02_b_provider_runtime_inventory_evidence.v1.json",
    "",
  ].join("\n");
  if (exitCode === 0) process.stdout.write(message);
  else process.stderr.write(message);
  process.exit(exitCode);
}

function classifyProviderAction(entry = {}) {
  if (entry.pack_state === "not_installed") {
    return {
      action_id: "install_provider_pack",
      severity: "blocker",
      summary: `Install the ${entry.provider_id} provider pack before relying on this runtime path.`,
    };
  }
  if (entry.pack_state === "disabled") {
    return {
      action_id: "enable_provider_pack",
      severity: "blocker",
      summary: `Re-enable the ${entry.provider_id} provider pack in the registry before retrying runtime resolution.`,
    };
  }
  if (entry.runtime_resolution_state === "runtime_missing") {
    return {
      action_id: "restore_pack_owned_runtime",
      severity: "blocker",
      summary: `Restore the ${entry.provider_id} pack-owned runtime or required dependencies so resolution can reach pack_runtime_ready.`,
    };
  }
  if (entry.runtime_resolution_state === "user_runtime_fallback") {
    return {
      action_id: "move_off_user_python",
      severity: "drift",
      summary: `Move ${entry.provider_id} off user-managed Python and back onto a Hub-managed runtime bundle to avoid per-machine drift.`,
    };
  }
  return {
    action_id: "observe_pack_runtime_ready",
    severity: "ready",
    summary: `${entry.provider_id} already resolves through a pack-owned runtime.`,
  };
}

function compactProviderRuntimeEntry(providerId, provider = {}, pack = null) {
  const normalizedProviderId = normalizeString(providerId).toLowerCase();
  const normalizedProvider = normalizeObject(provider);
  const normalizedPack = normalizeObject(pack);
  const entry = {
    provider_id: normalizedProviderId,
    ok: normalizeBoolean(normalizedProvider.ok),
    reason_code: normalizeString(normalizedProvider.reason_code),
    pack_id: normalizeString(
      normalizedPack.provider_id || normalizedProvider.pack_id,
      normalizedProviderId
    ).toLowerCase(),
    pack_engine: normalizeString(normalizedPack.engine || normalizedProvider.pack_engine),
    pack_version: normalizeString(normalizedPack.version || normalizedProvider.pack_version),
    pack_installed:
      normalizedPack.installed === true || normalizedProvider.pack_installed === true,
    pack_enabled:
      normalizedPack.enabled === true || normalizedProvider.pack_enabled === true,
    pack_state: normalizeString(
      normalizedPack.pack_state || normalizedProvider.pack_state,
      "missing"
    ).toLowerCase(),
    pack_reason_code: normalizeString(
      normalizedPack.reason_code || normalizedProvider.pack_reason_code
    ),
    runtime_source: normalizeString(normalizedProvider.runtime_source).toLowerCase(),
    runtime_source_path: normalizeString(normalizedProvider.runtime_source_path),
    runtime_resolution_state: normalizeString(
      normalizedProvider.runtime_resolution_state,
      "missing"
    ).toLowerCase(),
    runtime_reason_code: normalizeString(normalizedProvider.runtime_reason_code),
    fallback_used: normalizeBoolean(normalizedProvider.fallback_used),
    runtime_hint: normalizeString(normalizedProvider.runtime_hint),
    runtime_missing_requirements: normalizeArray(
      normalizedProvider.runtime_missing_requirements
    ).map((value) => normalizeString(value).toLowerCase()).filter(Boolean),
    runtime_missing_optional_requirements: normalizeArray(
      normalizedProvider.runtime_missing_optional_requirements
    ).map((value) => normalizeString(value).toLowerCase()).filter(Boolean),
    available_task_kinds: normalizeArray(normalizedProvider.available_task_kinds)
      .map((value) => normalizeString(value).toLowerCase())
      .filter(Boolean),
  };
  return {
    ...entry,
    recommended_action: classifyProviderAction(entry),
  };
}

function buildInventoryFieldGap(entry = {}) {
  const missing = [];
  if (!normalizeString(entry.pack_state)) missing.push("pack_state");
  if (!normalizeString(entry.pack_reason_code)) missing.push("pack_reason_code");
  if (!normalizeString(entry.runtime_source)) missing.push("runtime_source");
  if (!normalizeString(entry.runtime_resolution_state)) missing.push("runtime_resolution_state");
  if (!normalizeString(entry.runtime_reason_code)) missing.push("runtime_reason_code");
  return missing.length > 0
    ? `provider=${entry.provider_id}:missing=${missing.join(",")}`
    : "";
}

function buildPackConsistencyGap(entry = {}) {
  if (!normalizeString(entry.pack_id)) {
    return `provider=${entry.provider_id}:pack_id_missing`;
  }
  if (entry.pack_id !== entry.provider_id) {
    return `provider=${entry.provider_id}:pack_id_mismatch(${entry.pack_id})`;
  }
  if (
    entry.pack_state === "missing" ||
    entry.pack_state === "legacy_unreported" ||
    entry.pack_reason_code === "runtime_status_missing_provider_pack_inventory"
  ) {
    return `provider=${entry.provider_id}:pack_inventory_not_materialized`;
  }
  return "";
}

function buildProviderRuntimeInventoryEvidence(snapshot, options = {}) {
  const generatedAt = normalizeString(options.generatedAt, isoNow());
  const runtimeBaseDir = normalizeString(options.runtimeBaseDir);
  const maxAgeMs = Math.max(1, Math.floor(Number(options.maxAgeMs || 0) || 0));
  const runtimeStatusPath = runtimeBaseDir
    ? path.join(runtimeBaseDir, "ai_runtime_status.json")
    : "";
  const normalizedSnapshot = normalizeObject(snapshot);
  const snapshotOK = normalizedSnapshot.ok === true;
  const snapshotAlive = normalizedSnapshot.is_alive === true;
  const providerIds = snapshotOK
    ? normalizeArray(normalizedSnapshot.provider_ids)
        .map((value) => normalizeString(value).toLowerCase())
        .filter(Boolean)
    : [];
  const packMap = Object.fromEntries(
    normalizeArray(normalizedSnapshot.provider_packs)
      .map((pack) => normalizeObject(pack))
      .filter((pack) => normalizeString(pack.provider_id || pack.providerId).toLowerCase())
      .map((pack) => [normalizeString(pack.provider_id || pack.providerId).toLowerCase(), pack])
  );
  const providerMap = normalizeObject(normalizedSnapshot.providers);
  const providers = providerIds.map((providerId) =>
    compactProviderRuntimeEntry(providerId, providerMap[providerId], packMap[providerId])
  );

  const inventoryFieldGaps = uniqueStrings(
    providers.map((entry) => buildInventoryFieldGap(entry)).filter(Boolean)
  );
  const packConsistencyGaps = uniqueStrings(
    providers.map((entry) => buildPackConsistencyGap(entry)).filter(Boolean)
  );
  const observedRuntimeResolutionStates = uniqueStrings(
    providers.map((entry) => entry.runtime_resolution_state)
  );
  const allowedRuntimeStatesOnly = observedRuntimeResolutionStates.every((state) =>
    allowedRuntimeResolutionStates.includes(state)
  );
  const providerPackInventoryVisibleForAll = providers.every(
    (entry) =>
      normalizeString(entry.pack_state)
      && normalizeString(entry.pack_reason_code)
      && entry.pack_state !== "legacy_unreported"
  );
  const runtimeResolutionVisibleForAll = providers.every(
    (entry) =>
      normalizeString(entry.runtime_source)
      && normalizeString(entry.runtime_resolution_state)
      && normalizeString(entry.runtime_reason_code)
  );

  let status = "PASS(provider_runtime_inventory_contract_captured)";
  if (!snapshotOK) status = "FAIL(runtime_status_snapshot_missing)";
  else if (!snapshotAlive) status = "FAIL(runtime_status_snapshot_stale)";
  else if (providers.length === 0) status = "FAIL(provider_runtime_inventory_empty)";
  else if (inventoryFieldGaps.length > 0) status = "FAIL(provider_runtime_inventory_fields_missing)";
  else if (!allowedRuntimeStatesOnly) status = "FAIL(runtime_resolution_state_out_of_contract)";
  else if (packConsistencyGaps.length > 0) status = "FAIL(provider_pack_inventory_not_materialized)";

  const readyProviders = providers.filter((entry) => entry.ok).map((entry) => entry.provider_id);
  const packRuntimeReadyProviders = providers
    .filter((entry) => entry.runtime_resolution_state === "pack_runtime_ready")
    .map((entry) => entry.provider_id);
  const userRuntimeFallbackProviders = providers
    .filter((entry) => entry.runtime_resolution_state === "user_runtime_fallback")
    .map((entry) => entry.provider_id);
  const runtimeMissingProviders = providers
    .filter((entry) => entry.runtime_resolution_state === "runtime_missing")
    .map((entry) => entry.provider_id);
  const disabledPackProviders = providers
    .filter((entry) => entry.pack_state === "disabled" || entry.pack_enabled === false)
    .map((entry) => entry.provider_id);
  const notInstalledPackProviders = providers
    .filter((entry) => entry.pack_state === "not_installed" || entry.pack_installed === false)
    .map((entry) => entry.provider_id);

  const recommendedActions = [];
  const seenActionKeys = new Set();
  for (const entry of providers) {
    const action = normalizeObject(entry.recommended_action);
    if (!normalizeString(action.action_id) || normalizeString(action.severity) === "ready") continue;
    const dedupeKey = `${entry.provider_id}:${action.action_id}`;
    if (seenActionKeys.has(dedupeKey)) continue;
    seenActionKeys.add(dedupeKey);
    recommendedActions.push({
      provider_id: entry.provider_id,
      action_id: normalizeString(action.action_id),
      severity: normalizeString(action.severity),
      summary: normalizeString(action.summary),
      runtime_resolution_state: entry.runtime_resolution_state,
      pack_state: entry.pack_state,
    });
  }

  const currentBlockers = uniqueStrings([
    !snapshotOK ? "runtime_status_snapshot_missing" : "",
    snapshotOK && !snapshotAlive ? "runtime_status_snapshot_stale" : "",
    ...runtimeMissingProviders.map((providerId) => `runtime_missing:${providerId}`),
    ...disabledPackProviders.map((providerId) => `provider_pack_disabled:${providerId}`),
    ...notInstalledPackProviders.map((providerId) => `provider_pack_not_installed:${providerId}`),
    ...inventoryFieldGaps,
    ...packConsistencyGaps,
  ]);

  return {
    schema_version: "xhub.lpr_w4_02_b_provider_runtime_inventory_evidence.v1",
    generated_at_utc: generatedAt,
    work_order_id: "LPR-W4-02-B",
    title: "Provider-specific Runtime Resolution / Runtime Inventory",
    status,
    gate_readiness: {
      "LPR-G7":
        status.startsWith("PASS(")
          ? "candidate_pass(provider_runtime_inventory_contract_captured)"
          : "not_ready(provider_runtime_inventory_contract_incomplete)",
    },
    runtime_inventory_contract: {
      allowed_runtime_resolution_states: allowedRuntimeResolutionStates,
      do_not_conflate_with_runtime_readiness: true,
      note:
        "This evidence validates machine-readable visibility and consistency of runtime resolution. It does not require every provider on the current machine to be ready.",
    },
    summary: {
      runtime_status_snapshot_present: snapshotOK,
      runtime_status_snapshot_alive: snapshotAlive,
      provider_count: providers.length,
      ready_provider_count: readyProviders.length,
      pack_runtime_ready_count: packRuntimeReadyProviders.length,
      user_runtime_fallback_count: userRuntimeFallbackProviders.length,
      runtime_missing_count: runtimeMissingProviders.length,
      provider_pack_inventory_visible_for_all: providerPackInventoryVisibleForAll,
      runtime_resolution_visible_for_all: runtimeResolutionVisibleForAll,
      provider_pack_runtime_consistent: packConsistencyGaps.length === 0,
      allowed_runtime_states_only: allowedRuntimeStatesOnly,
    },
    machine_decision: {
      snapshot_age_ms: Number(normalizedSnapshot.age_ms || 0) || 0,
      ready_providers: readyProviders,
      pack_runtime_ready_providers: packRuntimeReadyProviders,
      user_runtime_fallback_providers: userRuntimeFallbackProviders,
      runtime_missing_providers: runtimeMissingProviders,
      disabled_pack_providers: disabledPackProviders,
      not_installed_pack_providers: notInstalledPackProviders,
      observed_runtime_resolution_states: observedRuntimeResolutionStates,
      inventory_field_gaps: inventoryFieldGaps,
      pack_consistency_gaps: packConsistencyGaps,
      current_blockers: currentBlockers,
    },
    runtime_snapshot: {
      base_dir: runtimeBaseDir,
      status_path: runtimeStatusPath,
      max_age_ms: maxAgeMs,
      snapshot_ok: snapshotOK,
      snapshot_alive: snapshotAlive,
      schema_version: normalizeString(normalizedSnapshot.schema_version),
      runtime_version: normalizeString(normalizedSnapshot.runtime_version),
      loaded_instance_count: Number(normalizedSnapshot.loaded_instance_count || 0) || 0,
    },
    providers,
    recommended_actions: recommendedActions,
    evidence_refs: [
      runtimeStatusPath,
      "x-hub/python-runtime/python_service/provider_pack_registry.py",
      "x-hub/python-runtime/python_service/provider_runtime_resolver.py",
      "x-hub/python-runtime/python_service/relflowhub_local_runtime.py",
      "x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.js",
      "scripts/generate_lpr_w4_02_b_provider_runtime_inventory_evidence.js",
    ],
  };
}

async function readRuntimeInventorySnapshot({ runtimeBaseDir = "", maxAgeMs = 86_400_000 } = {}) {
  const moduleURL = pathToFileURL(
    path.join(
      repoRoot,
      "x-hub",
      "grpc-server",
      "hub_grpc_server",
      "src",
      "local_runtime_ipc.js"
    )
  ).href;
  const runtimeIPC = await import(moduleURL);
  const resolvedRuntimeBaseDir = normalizeString(runtimeBaseDir) || runtimeIPC.resolveRuntimeBaseDir();
  return {
    runtimeBaseDir: resolvedRuntimeBaseDir,
    snapshot: runtimeIPC.readRuntimeStatusSnapshot(resolvedRuntimeBaseDir, maxAgeMs),
  };
}

async function main() {
  const args = parseArgs(process.argv);
  const { runtimeBaseDir, snapshot } = await readRuntimeInventorySnapshot({
    runtimeBaseDir: args.runtimeBaseDir,
    maxAgeMs: args.maxAgeMs,
  });
  const report = buildProviderRuntimeInventoryEvidence(snapshot, {
    generatedAt: isoNow(),
    runtimeBaseDir,
    maxAgeMs: args.maxAgeMs,
  });
  writeJSON(args.outputPath, report);
  process.stdout.write(`${args.outputPath}\n`);
}

module.exports = {
  allowedRuntimeResolutionStates,
  buildProviderRuntimeInventoryEvidence,
  compactProviderRuntimeEntry,
  parseArgs,
  readRuntimeInventorySnapshot,
};

if (require.main === module) {
  main().catch((error) => {
    process.stderr.write(`${String(error && error.stack ? error.stack : error)}\n`);
    process.exit(1);
  });
}
