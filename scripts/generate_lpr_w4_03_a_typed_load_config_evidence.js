#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");
const { pathToFileURL } = require("node:url");

const repoRoot = path.resolve(__dirname, "..");
const defaultOutputPath = path.join(
  repoRoot,
  "build/reports/lpr_w4_03_a_typed_load_config_evidence.v1.json"
);
const loadConfigSchemaVersion = "xhub.load_config.v1";

function isoNow() {
  return new Date().toISOString();
}

function normalizeString(value, fallback = "") {
  const trimmed = String(value ?? "").trim();
  return trimmed || fallback;
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
    "  node scripts/generate_lpr_w4_03_a_typed_load_config_evidence.js",
    "  node scripts/generate_lpr_w4_03_a_typed_load_config_evidence.js \\",
    "    --runtime-base-dir ~/Library/Containers/com.rel.flowhub/Data/RELFlowHub \\",
    "    --max-age-ms 86400000 \\",
    "    --out build/reports/lpr_w4_03_a_typed_load_config_evidence.v1.json",
    "",
  ].join("\n");
  if (exitCode === 0) process.stdout.write(message);
  else process.stderr.write(message);
  process.exit(exitCode);
}

function compactModelEntry(model = {}) {
  const row = normalizeObject(model);
  const defaultLoadConfig = normalizeObject(
    row.default_load_config || row.defaultLoadConfig || row.default_load_profile || row.defaultLoadProfile
  );
  const defaultContextLength = Math.max(
    0,
    Math.floor(
      Number(
        row.default_context_length
        || row.defaultContextLength
        || defaultLoadConfig.context_length
        || defaultLoadConfig.contextLength
        || 0
      ) || 0
    )
  );
  return {
    model_id: normalizeString(row.model_id || row.modelId),
    backend: normalizeString(row.backend).toLowerCase(),
    runtime_provider_id: normalizeString(
      row.runtime_provider_id || row.runtimeProviderId
    ).toLowerCase(),
    task_kinds: normalizeArray(row.task_kinds || row.taskKinds)
      .map((value) => normalizeString(value).toLowerCase())
      .filter(Boolean),
    default_context_length: defaultContextLength,
    max_context_length: Math.max(
      defaultContextLength,
      Math.floor(Number(row.max_context_length || row.maxContextLength || 0) || 0)
    ),
    default_load_config:
      Object.keys(defaultLoadConfig).length > 0 ? defaultLoadConfig : null,
  };
}

function buildModelGap(entry = {}) {
  const missing = [];
  if (!normalizeString(entry.model_id)) missing.push("model_id");
  if (entry.default_context_length <= 0) missing.push("default_context_length");
  if (entry.max_context_length <= 0) missing.push("max_context_length");
  if (!entry.default_load_config) {
    missing.push("default_load_config");
  } else {
    if (normalizeString(entry.default_load_config.schema_version) !== loadConfigSchemaVersion) {
      missing.push("default_load_config.schema_version");
    }
    const configContextLength = Math.max(
      0,
      Math.floor(Number(entry.default_load_config.context_length || 0) || 0)
    );
    if (configContextLength <= 0) missing.push("default_load_config.context_length");
    if (
      entry.default_context_length > 0
      && configContextLength > 0
      && entry.default_context_length !== configContextLength
    ) {
      missing.push("default_context_length_mismatch");
    }
  }
  if (
    entry.max_context_length > 0
    && entry.default_context_length > 0
    && entry.max_context_length < entry.default_context_length
  ) {
    missing.push("max_context_lt_default_context");
  }
  return missing.length > 0
    ? `model=${entry.model_id || "unknown"}:missing=${missing.join(",")}`
    : "";
}

function compactLoadedInstance(entry = {}) {
  const row = normalizeObject(entry);
  const loadConfig = normalizeObject(
    row.load_config || row.loadConfig || row.effective_load_profile || row.effectiveLoadProfile
  );
  return {
    provider: normalizeString(row.provider).toLowerCase(),
    instance_key: normalizeString(row.instance_key || row.instanceKey),
    model_id: normalizeString(row.model_id || row.modelId),
    load_config_hash: normalizeString(
      row.load_config_hash || row.loadConfigHash || row.load_profile_hash || row.loadProfileHash
    ),
    current_context_length: Math.max(
      0,
      Math.floor(
        Number(
          row.current_context_length
          || row.currentContextLength
          || row.effective_context_length
          || row.effectiveContextLength
          || 0
        ) || 0
      )
    ),
    max_context_length: Math.max(
      0,
      Math.floor(Number(row.max_context_length || row.maxContextLength || 0) || 0)
    ),
    load_config: Object.keys(loadConfig).length > 0 ? loadConfig : null,
    residency: normalizeString(row.residency).toLowerCase(),
    last_used_at_ms: Math.max(
      0,
      Math.floor(Number(row.last_used_at_ms || row.lastUsedAtMs || 0) || 0)
    ),
  };
}

function buildLoadedInstanceGap(entry = {}, modelById = {}) {
  const missing = [];
  if (!normalizeString(entry.instance_key)) missing.push("instance_key");
  if (!normalizeString(entry.model_id)) missing.push("model_id");
  if (!normalizeString(entry.load_config_hash)) missing.push("load_config_hash");
  if (entry.current_context_length <= 0) missing.push("current_context_length");
  if (entry.max_context_length <= 0) missing.push("max_context_length");
  if (
    entry.max_context_length > 0
    && entry.current_context_length > 0
    && entry.max_context_length < entry.current_context_length
  ) {
    missing.push("max_context_lt_current_context");
  }
  if (!entry.load_config) {
    missing.push("load_config");
  } else {
    if (normalizeString(entry.load_config.schema_version) !== loadConfigSchemaVersion) {
      missing.push("load_config.schema_version");
    }
    const configContextLength = Math.max(
      0,
      Math.floor(Number(entry.load_config.context_length || 0) || 0)
    );
    if (configContextLength <= 0) missing.push("load_config.context_length");
    if (
      entry.current_context_length > 0
      && configContextLength > 0
      && entry.current_context_length !== configContextLength
    ) {
      missing.push("current_context_length_mismatch");
    }
  }
  const model = modelById[entry.model_id];
  if (
    model
    && model.max_context_length > 0
    && entry.max_context_length > 0
    && entry.max_context_length > model.max_context_length
  ) {
    missing.push("instance_max_context_gt_model_max_context");
  }
  return missing.length > 0
    ? `instance=${entry.instance_key || "unknown"}:missing=${missing.join(",")}`
    : "";
}

function buildTypedLoadConfigEvidence(inputs = {}, options = {}) {
  const generatedAt = normalizeString(options.generatedAt, isoNow());
  const runtimeBaseDir = normalizeString(options.runtimeBaseDir);
  const maxAgeMs = Math.max(1, Math.floor(Number(options.maxAgeMs || 0) || 0));
  const runtimeStatusPath = runtimeBaseDir
    ? path.join(runtimeBaseDir, "ai_runtime_status.json")
    : "";
  const modelsStatePath = runtimeBaseDir
    ? path.join(runtimeBaseDir, "models_state.json")
    : "";
  const snapshot = normalizeObject(inputs.snapshot);
  const modelRecords = normalizeArray(inputs.modelRecords);
  const snapshotOK = snapshot.ok === true;
  const snapshotAlive = snapshot.is_alive === true;
  const models = modelRecords.map((entry) => compactModelEntry(entry)).filter((entry) => entry.model_id);
  const modelById = Object.fromEntries(models.map((entry) => [entry.model_id, entry]));
  const loadedInstances = normalizeArray(snapshot.loaded_instances)
    .map((entry) => compactLoadedInstance(entry))
    .filter((entry) => entry.instance_key);

  const modelInfoGaps = uniqueStrings(models.map((entry) => buildModelGap(entry)).filter(Boolean));
  const loadedInstanceGaps = uniqueStrings(
    loadedInstances.map((entry) => buildLoadedInstanceGap(entry, modelById)).filter(Boolean)
  );

  const modelInfoLoadConfigVisibleForAll = models.length > 0 && modelInfoGaps.length === 0;
  const loadedInstanceContractObserved = loadedInstances.length > 0;
  const loadedInstanceLoadConfigVisibleForAllObserved =
    loadedInstances.length > 0 && loadedInstanceGaps.length === 0;
  const loadConfigHashVisibleForAllLoadedInstances =
    loadedInstances.length > 0
      ? loadedInstances.every((entry) => normalizeString(entry.load_config_hash))
      : false;
  const currentVsMaxContextVisibleForAllLoadedInstances =
    loadedInstances.length > 0
      ? loadedInstances.every(
          (entry) => entry.current_context_length > 0 && entry.max_context_length >= entry.current_context_length
        )
      : false;

  let status = "PASS(typed_load_config_contract_captured)";
  if (!snapshotOK) status = "FAIL(runtime_status_snapshot_missing)";
  else if (!snapshotAlive) status = "FAIL(runtime_status_snapshot_stale)";
  else if (models.length === 0) status = "FAIL(model_catalog_empty)";
  else if (modelInfoGaps.length > 0) status = "FAIL(model_info_load_config_incomplete)";
  else if (loadedInstances.length === 0) {
    status = "PASS(model_info_load_config_contract_captured_no_loaded_instances)";
  } else if (loadedInstanceGaps.length > 0) {
    status = "FAIL(loaded_instance_load_config_incomplete)";
  }

  const currentBlockers = uniqueStrings([
    !snapshotOK ? "runtime_status_snapshot_missing" : "",
    snapshotOK && !snapshotAlive ? "runtime_status_snapshot_stale" : "",
    models.length === 0 ? "model_catalog_empty" : "",
    ...modelInfoGaps,
    ...loadedInstanceGaps,
  ]);

  return {
    schema_version: "xhub.lpr_w4_03_a_typed_load_config_evidence.v1",
    generated_at_utc: generatedAt,
    work_order_id: "LPR-W4-03-A",
    title: "Typed Load Config / ModelInfo vs LoadedInstanceInfo",
    status,
    gate_readiness: {
      "LPR-G8":
        status.startsWith("PASS(")
          ? "candidate_pass(typed_load_config_contract_captured)"
          : "not_ready(typed_load_config_contract_incomplete)",
    },
    typed_load_config_contract: {
      load_config_schema_version: loadConfigSchemaVersion,
      model_info_fields: [
        "default_context_length",
        "max_context_length",
        "default_load_config",
      ],
      loaded_instance_fields: [
        "current_context_length",
        "max_context_length",
        "load_config_hash",
        "load_config",
        "last_used_at_ms",
      ],
      note:
        "This evidence validates typed load-config visibility on model info and loaded instance info. It does not require every optional load-config knob to be non-empty on the current machine.",
    },
    summary: {
      runtime_status_snapshot_present: snapshotOK,
      runtime_status_snapshot_alive: snapshotAlive,
      model_record_count: models.length,
      model_info_load_config_visible_for_all: modelInfoLoadConfigVisibleForAll,
      loaded_instance_count: loadedInstances.length,
      loaded_instance_contract_observed: loadedInstanceContractObserved,
      loaded_instance_load_config_visible_for_all_observed:
        loadedInstanceLoadConfigVisibleForAllObserved,
      load_config_hash_visible_for_all_loaded_instances:
        loadConfigHashVisibleForAllLoadedInstances,
      current_vs_max_context_visible_for_all_loaded_instances:
        currentVsMaxContextVisibleForAllLoadedInstances,
    },
    machine_decision: {
      snapshot_age_ms: Math.max(0, Math.floor(Number(snapshot.age_ms || 0) || 0)),
      observed_model_ids: models.map((entry) => entry.model_id),
      observed_loaded_instance_ids: loadedInstances.map((entry) => entry.instance_key),
      model_info_gaps: modelInfoGaps,
      loaded_instance_gaps: loadedInstanceGaps,
      current_blockers: currentBlockers,
    },
    model_records: models,
    loaded_instances: loadedInstances,
    runtime_snapshot: {
      base_dir: runtimeBaseDir,
      status_path: runtimeStatusPath,
      models_state_path: modelsStatePath,
      max_age_ms: maxAgeMs,
      snapshot_ok: snapshotOK,
      snapshot_alive: snapshotAlive,
      schema_version: normalizeString(snapshot.schema_version),
      runtime_version: normalizeString(snapshot.runtime_version),
    },
    evidence_refs: [
      runtimeStatusPath,
      modelsStatePath,
      "x-hub/python-runtime/python_service/relflowhub_local_runtime.py",
      "x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.js",
      "x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js",
      "x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/LocalModelLoadProfile.swift",
      "x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/AIRuntimeStatus.swift",
      "scripts/generate_lpr_w4_03_a_typed_load_config_evidence.js",
    ],
  };
}

async function readTypedLoadConfigInputs({ runtimeBaseDir = "", maxAgeMs = 86_400_000 } = {}) {
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
    modelRecords: runtimeIPC.listRuntimeModelRecords(resolvedRuntimeBaseDir),
  };
}

async function main() {
  const args = parseArgs(process.argv);
  const { runtimeBaseDir, snapshot, modelRecords } = await readTypedLoadConfigInputs({
    runtimeBaseDir: args.runtimeBaseDir,
    maxAgeMs: args.maxAgeMs,
  });
  const report = buildTypedLoadConfigEvidence(
    { snapshot, modelRecords },
    {
      generatedAt: isoNow(),
      runtimeBaseDir,
      maxAgeMs: args.maxAgeMs,
    }
  );
  writeJSON(args.outputPath, report);
  process.stdout.write(`${args.outputPath}\n`);
}

module.exports = {
  buildLoadedInstanceGap,
  buildModelGap,
  buildTypedLoadConfigEvidence,
  compactLoadedInstance,
  compactModelEntry,
  loadConfigSchemaVersion,
  parseArgs,
  readTypedLoadConfigInputs,
};

if (require.main === module) {
  main().catch((error) => {
    process.stderr.write(`${String(error && error.stack ? error.stack : error)}\n`);
    process.exit(1);
  });
}
