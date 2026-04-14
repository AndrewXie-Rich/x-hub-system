#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const {
  repoRoot,
  reportsDir,
  writeJSON,
} = require("./lpr_w3_03_require_real_bundle_lib.js");

const summaryPath = path.join(
  reportsDir,
  "lpr_w3_03_prerequisite_evidence_rebuild.v1.json"
);

function isoNow() {
  return new Date().toISOString();
}

function relPath(filePath) {
  return path.relative(repoRoot, filePath).split(path.sep).join("/");
}

function readText(filePath) {
  return fs.readFileSync(filePath, "utf8");
}

function trimOutput(text, maxChars = 4000) {
  const normalized = String(text || "").trim();
  if (!normalized) return "";
  if (normalized.length <= maxChars) return normalized;
  return `${normalized.slice(0, maxChars)}\n...[truncated]`;
}

function shellJoin(parts) {
  return parts
    .map((part) => {
      const text = String(part);
      if (/^[A-Za-z0-9_./:@=-]+$/.test(text)) return text;
      return `'${text.replace(/'/g, `'\\''`)}'`;
    })
    .join(" ");
}

function runCommand(definition) {
  const cwd = path.join(repoRoot, definition.cwd || ".");
  const startedAt = Date.now();
  const child = spawnSync(definition.command, definition.args || [], {
    cwd,
    encoding: "utf8",
    maxBuffer: 32 * 1024 * 1024,
  });
  const finishedAt = Date.now();
  const combined = [child.stdout || "", child.stderr || ""].filter(Boolean).join("\n").trim();
  return {
    id: definition.id,
    label: definition.label,
    command: shellJoin([definition.command, ...(definition.args || [])]),
    cwd: relPath(cwd),
    exit_code: Number.isInteger(child.status) ? child.status : -1,
    signal: child.signal || "",
    started_at_utc: new Date(startedAt).toISOString(),
    finished_at_utc: new Date(finishedAt).toISOString(),
    duration_ms: Math.max(0, finishedAt - startedAt),
    ok: child.status === 0,
    output_excerpt: trimOutput(combined),
  };
}

function checkSource(check) {
  const absolutePath = path.join(repoRoot, check.file);
  const exists = fs.existsSync(absolutePath);
  const text = exists ? readText(absolutePath) : "";
  const tokenChecks = (check.tokens || []).map((token) => ({
    token,
    present: exists && text.includes(token),
  }));
  return {
    id: check.id,
    file: check.file,
    exists,
    ok: exists && tokenChecks.every((entry) => entry.present),
    token_checks: tokenChecks,
  };
}

function indexById(rows) {
  const out = {};
  for (const row of rows) {
    out[row.id] = row;
  }
  return out;
}

function pickCommandResults(commandIndex, ids) {
  return ids.map((id) => commandIndex[id]).filter(Boolean);
}

function pickSourceResults(sourceIndex, ids) {
  return ids.map((id) => sourceIndex[id]).filter(Boolean);
}

function allOk(rows) {
  return rows.length > 0 && rows.every((row) => row.ok === true);
}

const COMMAND_DEFINITIONS = [
  {
    id: "node_local_embeddings",
    label: "Node embedding contract tests",
    command: "node",
    args: ["x-hub/grpc-server/hub_grpc_server/src/local_embeddings.test.js"],
  },
  {
    id: "node_local_audio",
    label: "Node audio contract tests",
    command: "node",
    args: ["x-hub/grpc-server/hub_grpc_server/src/local_audio.test.js"],
  },
  {
    id: "node_local_vision",
    label: "Node vision contract tests",
    command: "node",
    args: ["x-hub/grpc-server/hub_grpc_server/src/local_vision.test.js"],
  },
  {
    id: "node_local_runtime_ipc",
    label: "Node runtime IPC routing tests",
    command: "node",
    args: ["x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js"],
  },
  {
    id: "python_local_provider_runtime_compat",
    label: "Python local provider runtime compatibility tests",
    command: "python3",
    args: ["x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py"],
  },
  {
    id: "bench_fixture_pack_generator",
    label: "Bench fixture pack evidence generator",
    command: "node",
    args: ["scripts/generate_lpr_w3_06_d_bench_fixture_pack_evidence.js"],
  },
];

const SOURCE_DEFINITIONS = [
  {
    id: "embedding_js_contract",
    file: "x-hub/grpc-server/hub_grpc_server/src/local_embeddings.js",
    tokens: [
      "route_source: safeString(modelSelection.route_source)",
      "resolved_model_id: safeString(modelSelection.resolved_model_id)",
      "vector_count: embeddedDocs.length + (queryVector.length ? 1 : 0)",
    ],
  },
  {
    id: "embedding_python_contract",
    file: "x-hub/python-runtime/python_service/providers/transformers_provider.py",
    tokens: [
      "def _run_real_embedding(",
      "\"embedding_runtime_failed\"",
      "\"unsupported_quantization_config\"",
    ],
  },
  {
    id: "asr_js_contract",
    file: "x-hub/grpc-server/hub_grpc_server/src/local_audio.js",
    tokens: [
      "const ASR_TASK_KIND = 'speech_to_text';",
      "rawDenyCode: 'audio_duration_too_long'",
      "segments: Array.isArray(response.segments) ? response.segments : []",
    ],
  },
  {
    id: "asr_python_contract",
    file: "x-hub/python-runtime/python_service/providers/transformers_provider.py",
    tokens: [
      "ASR_TASK_KIND = \"speech_to_text\"",
      "\"speech_to_text_runtime_failed\"",
      "\"timestampsRequested\": bool(validated.get(\"timestamps\"))",
    ],
  },
  {
    id: "vision_js_contract",
    file: "x-hub/grpc-server/hub_grpc_server/src/local_vision.js",
    tokens: [
      "const VISION_TASK_KIND = 'vision_understand';",
      "const OCR_TASK_KIND = 'ocr';",
      "message: `unsupported_image_format:${ext || 'unknown'}`",
    ],
  },
  {
    id: "vision_python_contract",
    file: "x-hub/python-runtime/python_service/providers/transformers_provider.py",
    tokens: [
      "VISION_TASK_KIND = \"vision_understand\"",
      "OCR_TASK_KIND = \"ocr\"",
      "\"fallbackMode\": \"image_hash_preview\"",
    ],
  },
  {
    id: "resident_runtime_python_control_plane",
    file: "x-hub/python-runtime/python_service/relflowhub_local_runtime.py",
    tokens: [
      "LOCAL_RUNTIME_COMMAND_IPC_VERSION = \"xhub.local_runtime_command_ipc.v1\"",
      "if cmd == \"run-local-bench\":",
      "if cmd in {\"manage-local-model\", \"warmup-local-model\", \"unload-local-model\", \"evict-local-instance\"}:",
    ],
  },
  {
    id: "resident_runtime_daemon_writer",
    file: "x-hub/python-runtime/python_service/relflowhub_mlx_runtime.py",
    tokens: [
      "'localCommandIpcVersion': str(LOCAL_RUNTIME_COMMAND_IPC_VERSION)",
      "resident_transformers=True",
      "'residencyScope': 'legacy_runtime'",
    ],
  },
  {
    id: "resident_runtime_transformers_scope",
    file: "x-hub/python-runtime/python_service/providers/transformers_provider.py",
    tokens: [
      "return \"runtime_process\" if self._resident_runtime_mode else \"process_local\"",
      "def set_resident_runtime_mode(self, enabled: bool) -> None:",
      "self._resident_runtime_mode = bool(enabled)",
      "\"residencyScope\": self.residency_scope()",
    ],
  },
  {
    id: "resident_runtime_swift_planner",
    file: "x-hub/macos/RELFlowHub/Sources/RELFlowHub/ModelStore.swift",
    tokens: [
      "command: \"run-local-bench\"",
      "command: \"manage-local-model\"",
      "let scope = residencyScope.isEmpty ? \"process_local\" : residencyScope",
    ],
  },
  {
    id: "monitor_export_swift_source",
    file: "x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubDiagnosticsBundleExporter.swift",
    tokens: [
      "local_runtime_monitor_summary.txt",
      "local_runtime_monitor_snapshot.redacted.json",
      "schemaVersion: \"xhub_local_runtime_monitor_export.v1\"",
    ],
  },
  {
    id: "monitor_export_settings_copy",
    file: "x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift",
    tokens: [
      "lines.append(\"runtime_monitor:\\n\" + monitorSummary)",
      "lines.append(\"runtime_monitor:\\n\\(rtMonitor)\")",
      "HubDiagnosticsBundleExporter.redactTextForSharing",
    ],
  },
  {
    id: "monitor_export_swift_tests",
    file: "x-hub/macos/RELFlowHub/Tests/RELFlowHubAppTests/HubDiagnosticsBundleExporterTests.swift",
    tokens: [
      "runtime_monitor:",
      "xhub_local_runtime_monitor_summary.v1",
      "xhub_local_runtime_monitor_export.v1",
    ],
  },
  {
    id: "routing_runtime_ipc_source",
    file: "x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.js",
    tokens: [
      "export function resolveLocalTaskModelRecord({",
      "reason_code: 'routed_model_not_registered'",
      "reason_code: 'routed_model_task_mismatch'",
    ],
  },
  {
    id: "routing_service_audit_source",
    file: "x-hub/grpc-server/hub_grpc_server/src/services.js",
    tokens: [
      "route_source: String(localEmbeddingOutcome?.route_source || '')",
      "resolved_model_id: String(localEmbeddingOutcome?.resolved_model_id || '')",
      "vector_count: Math.max(0, Number(localEmbeddingOutcome?.vector_count || 0))",
    ],
  },
  {
    id: "routing_embedding_surface",
    file: "x-hub/grpc-server/hub_grpc_server/src/local_embeddings.js",
    tokens: [
      "route_source: safeString(modelSelection.route_source)",
      "resolved_model_id: safeString(modelSelection.resolved_model_id) || safeString(model?.model_id)",
      "route_reason_code: safeString(modelSelection.reason_code)",
    ],
  },
  {
    id: "routing_audio_surface",
    file: "x-hub/grpc-server/hub_grpc_server/src/local_audio.js",
    tokens: [
      "route_source: safeString(modelSelection.route_source)",
      "resolved_model_id: safeString(modelSelection.resolved_model_id) || safeString(response.modelId) || safeString(model.model_id)",
      "segments: Array.isArray(response.segments) ? response.segments : []",
    ],
  },
  {
    id: "routing_vision_surface",
    file: "x-hub/grpc-server/hub_grpc_server/src/local_vision.js",
    tokens: [
      "route_source: safeString(modelSelection.route_source)",
      "resolved_model_id: safeString(modelSelection.resolved_model_id) || safeString(response.modelId) || safeString(model.model_id)",
      "export async function ocrLocalImage(options = {}) {",
    ],
  },
];

const COMMON_DOCS = [
  "docs/memory-new/xhub-local-provider-runtime-transformers-implementation-pack-v1.md",
  "docs/memory-new/xhub-local-provider-runtime-transformers-work-orders-v1.md",
];

const ARTIFACT_DEFINITIONS = [
  {
    output: "build/reports/lpr_w2_01_a_embedding_contract_evidence.v1.json",
    schema_version: "xhub.lpr_w2_01_a_embedding_contract_evidence.v1",
    work_order_id: "LPR-W2-01-A",
    title: "Embedding Task Contract",
    gate: "LPR-G2",
    command_ids: ["node_local_embeddings", "python_local_provider_runtime_compat"],
    source_ids: ["embedding_js_contract", "embedding_python_contract", "routing_service_audit_source"],
    files: [
      ...COMMON_DOCS,
      "x-hub/grpc-server/hub_grpc_server/src/local_embeddings.js",
      "x-hub/grpc-server/hub_grpc_server/src/local_embeddings.test.js",
      "x-hub/grpc-server/hub_grpc_server/src/services.js",
      "x-hub/python-runtime/python_service/providers/transformers_provider.py",
      "x-hub/python-runtime/python_service/relflowhub_local_runtime.py",
      "x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py",
    ],
    summary(commandIndex, sourceIndex) {
      return {
        node_embedding_contract_passed: commandIndex.node_local_embeddings.ok,
        python_embedding_contract_passed: commandIndex.python_local_provider_runtime_compat.ok,
        embedding_route_trace_source_present: sourceIndex.embedding_js_contract.ok,
        embedding_audit_route_snapshot_present: sourceIndex.routing_service_audit_source.ok,
        embedding_runtime_fail_closed_reason_present: sourceIndex.embedding_python_contract.ok,
      };
    },
    limitations() {
      return [];
    },
  },
  {
    output: "build/reports/lpr_w2_02_a_asr_contract_evidence.v1.json",
    schema_version: "xhub.lpr_w2_02_a_asr_contract_evidence.v1",
    work_order_id: "LPR-W2-02-A",
    title: "Speech-to-Text Task Contract",
    gate: "LPR-G3",
    command_ids: ["node_local_audio", "python_local_provider_runtime_compat"],
    source_ids: ["asr_js_contract", "asr_python_contract", "routing_audio_surface"],
    files: [
      ...COMMON_DOCS,
      "x-hub/grpc-server/hub_grpc_server/src/local_audio.js",
      "x-hub/grpc-server/hub_grpc_server/src/local_audio.test.js",
      "x-hub/python-runtime/python_service/providers/transformers_provider.py",
      "x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py",
    ],
    summary(commandIndex, sourceIndex) {
      return {
        node_asr_contract_passed: commandIndex.node_local_audio.ok,
        python_asr_contract_passed: commandIndex.python_local_provider_runtime_compat.ok,
        asr_duration_guard_source_present: sourceIndex.asr_js_contract.ok,
        asr_machine_readable_segments_present: sourceIndex.asr_python_contract.ok,
        asr_route_trace_source_present: sourceIndex.routing_audio_surface.ok,
      };
    },
    limitations() {
      return [];
    },
  },
  {
    output: "build/reports/lpr_w3_01_a_vision_preview_contract_evidence.v1.json",
    schema_version: "xhub.lpr_w3_01_a_vision_preview_contract_evidence.v1",
    work_order_id: "LPR-W3-01-A",
    title: "Vision/OCR Preview Contract",
    gate: "LPR-G4",
    command_ids: ["node_local_vision", "python_local_provider_runtime_compat"],
    source_ids: ["vision_js_contract", "vision_python_contract", "routing_vision_surface"],
    files: [
      ...COMMON_DOCS,
      "x-hub/grpc-server/hub_grpc_server/src/local_vision.js",
      "x-hub/grpc-server/hub_grpc_server/src/local_vision.test.js",
      "x-hub/python-runtime/python_service/providers/transformers_provider.py",
      "x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py",
    ],
    summary(commandIndex, sourceIndex) {
      return {
        node_vision_contract_passed: commandIndex.node_local_vision.ok,
        python_vision_contract_passed: commandIndex.python_local_provider_runtime_compat.ok,
        image_guard_and_preview_source_present: sourceIndex.vision_js_contract.ok,
        preview_fallback_reason_source_present: sourceIndex.vision_python_contract.ok,
        vision_route_trace_source_present: sourceIndex.routing_vision_surface.ok,
      };
    },
    limitations() {
      return [];
    },
  },
  {
    output: "build/reports/lpr_w3_05_d_resident_runtime_proxy_evidence.v1.json",
    schema_version: "xhub.lpr_w3_05_d_resident_runtime_proxy_evidence.v1",
    work_order_id: "LPR-W3-05-D",
    title: "Resident Daemon Proxy / Warmable Lifecycle Activation",
    gate: "LPR-G5",
    command_ids: ["node_local_runtime_ipc", "python_local_provider_runtime_compat"],
    source_ids: [
      "resident_runtime_python_control_plane",
      "resident_runtime_daemon_writer",
      "resident_runtime_transformers_scope",
      "resident_runtime_swift_planner",
    ],
    files: [
      ...COMMON_DOCS,
      "docs/memory-new/README-local-provider-runtime-productization-v1.md",
      "x-hub/python-runtime/python_service/relflowhub_local_runtime.py",
      "x-hub/python-runtime/python_service/relflowhub_mlx_runtime.py",
      "x-hub/python-runtime/python_service/providers/transformers_provider.py",
      "x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py",
      "x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.js",
      "x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js",
      "x-hub/macos/RELFlowHub/Sources/RELFlowHub/ModelStore.swift",
      "x-hub/macos/RELFlowHub/Tests/RELFlowHubAppTests/LocalModelRuntimeActionPlannerTests.swift",
    ],
    summary(commandIndex, sourceIndex) {
      return {
        python_resident_proxy_contract_passed: commandIndex.python_local_provider_runtime_compat.ok,
        node_runtime_ipc_contract_passed: commandIndex.node_local_runtime_ipc.ok,
        daemon_command_proxy_source_present: sourceIndex.resident_runtime_python_control_plane.ok,
        daemon_status_writer_source_present: sourceIndex.resident_runtime_daemon_writer.ok,
        runtime_process_residency_source_present: sourceIndex.resident_runtime_transformers_scope.ok,
        swift_planner_surface_present: sourceIndex.resident_runtime_swift_planner.ok,
      };
    },
    limitations() {
      return [
        "Swift package filters are not re-run by this rebuild script; verify RELFlowHub package health separately when the workspace test target is green again.",
      ];
    },
  },
  {
    output: "build/reports/lpr_w3_07_c_monitor_export_evidence.v1.json",
    schema_version: "xhub.lpr_w3_07_c_monitor_export_evidence.v1",
    work_order_id: "LPR-W3-07-C",
    title: "Operator / Diagnostics Export",
    gate: "LPR-G5",
    command_ids: ["python_local_provider_runtime_compat"],
    source_ids: ["monitor_export_swift_source", "monitor_export_settings_copy", "monitor_export_swift_tests"],
    files: [
      ...COMMON_DOCS,
      "x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubDiagnosticsBundleExporter.swift",
      "x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift",
      "x-hub/macos/RELFlowHub/Tests/RELFlowHubAppTests/HubDiagnosticsBundleExporterTests.swift",
      "x-hub/python-runtime/python_service/test_local_provider_runtime_compat.py",
    ],
    summary(commandIndex, sourceIndex) {
      return {
        python_monitor_snapshot_contract_passed: commandIndex.python_local_provider_runtime_compat.ok,
        diagnostics_bundle_monitor_export_source_present: sourceIndex.monitor_export_swift_source.ok,
        settings_monitor_copy_surface_present: sourceIndex.monitor_export_settings_copy.ok,
        swift_monitor_export_tests_present: sourceIndex.monitor_export_swift_tests.ok,
      };
    },
    limitations() {
      return [
        "This rebuild confirms monitor snapshot contract and export source surfaces; rerun targeted RELFlowHub Swift filters once unrelated package test blockers are cleared.",
      ];
    },
  },
  {
    output: "build/reports/lpr_w3_08_c_task_resolution_evidence.v1.json",
    schema_version: "xhub.lpr_w3_08_c_task_resolution_evidence.v1",
    work_order_id: "LPR-W3-08-C",
    title: "Node / Runtime Local Task Resolution",
    gate: "LPR-G5",
    command_ids: [
      "node_local_runtime_ipc",
      "node_local_embeddings",
      "node_local_audio",
      "node_local_vision",
    ],
    source_ids: [
      "routing_runtime_ipc_source",
      "routing_service_audit_source",
      "routing_embedding_surface",
      "routing_audio_surface",
      "routing_vision_surface",
    ],
    files: [
      ...COMMON_DOCS,
      "x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.js",
      "x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.test.js",
      "x-hub/grpc-server/hub_grpc_server/src/local_embeddings.js",
      "x-hub/grpc-server/hub_grpc_server/src/local_embeddings.test.js",
      "x-hub/grpc-server/hub_grpc_server/src/local_audio.js",
      "x-hub/grpc-server/hub_grpc_server/src/local_audio.test.js",
      "x-hub/grpc-server/hub_grpc_server/src/local_vision.js",
      "x-hub/grpc-server/hub_grpc_server/src/local_vision.test.js",
      "x-hub/grpc-server/hub_grpc_server/src/services.js",
    ],
    summary(commandIndex, sourceIndex) {
      return {
        node_runtime_ipc_resolution_passed: commandIndex.node_local_runtime_ipc.ok,
        node_embedding_route_surface_passed: commandIndex.node_local_embeddings.ok,
        node_audio_route_surface_passed: commandIndex.node_local_audio.ok,
        node_vision_route_surface_passed: commandIndex.node_local_vision.ok,
        shared_routing_resolver_source_present: sourceIndex.routing_runtime_ipc_source.ok,
        service_route_audit_source_present: sourceIndex.routing_service_audit_source.ok,
      };
    },
    limitations() {
      return [];
    },
  },
];

function buildArtifact(definition, generatedAt, commandIndex, sourceIndex) {
  const commandResults = pickCommandResults(commandIndex, definition.command_ids);
  const sourceResults = pickSourceResults(sourceIndex, definition.source_ids);
  const summary = definition.summary(commandIndex, sourceIndex);
  const readiness = allOk(commandResults) && allOk(sourceResults)
    ? "candidate_pass"
    : "candidate_fail";
  return {
    schema_version: definition.schema_version,
    generated_at_utc: generatedAt,
    evidence_status: "reconstructed_from_repo_state",
    rebuild_method: "repo_state_plus_targeted_contract_revalidation",
    work_order_id: definition.work_order_id,
    title: definition.title,
    gate: definition.gate,
    reconstructed_gate_readiness: readiness,
    summary,
    validation_commands: commandResults,
    source_checks: sourceResults,
    files: definition.files,
    limitations: definition.limitations(),
  };
}

function main() {
  const generatedAt = isoNow();
  const commandResults = COMMAND_DEFINITIONS.map(runCommand);
  const sourceResults = SOURCE_DEFINITIONS.map(checkSource);
  const commandIndex = indexById(commandResults);
  const sourceIndex = indexById(sourceResults);

  const generatedArtifacts = [];
  for (const definition of ARTIFACT_DEFINITIONS) {
    const payload = buildArtifact(definition, generatedAt, commandIndex, sourceIndex);
    const absoluteOutput = path.join(repoRoot, definition.output);
    writeJSON(absoluteOutput, payload);
    generatedArtifacts.push({
      work_order_id: definition.work_order_id,
      output: definition.output,
      reconstructed_gate_readiness: payload.reconstructed_gate_readiness,
    });
  }

  const benchEvidencePath = path.join(
    repoRoot,
    "build/reports/lpr_w3_06_d_bench_fixture_pack_evidence.v1.json"
  );
  const summary = {
    schema_version: "xhub.lpr_w3_03_prerequisite_evidence_rebuild.v1",
    generated_at_utc: generatedAt,
    scope: "Regenerate prerequisite machine-readable evidence after build/reports cleanup for LPR-W3-03 require-real QA.",
    command_results: commandResults,
    source_checks: sourceResults,
    generated_artifacts: generatedArtifacts,
    existing_generator_outputs: [
      {
        work_order_id: "LPR-W3-06-D",
        output: relPath(benchEvidencePath),
        present: fs.existsSync(benchEvidencePath),
        generator_command_ok: !!commandIndex.bench_fixture_pack_generator?.ok,
      },
    ],
    notes: [
      "This rebuild restores prerequisite evidence files so LPR-W3-03 QA can move from missing-prerequisite state back to require-real sample tracking.",
      "Swift-specific surfaces are recorded from source presence here; any package-level Swift revalidation should be tracked separately when unrelated test target blockers are cleared.",
    ],
  };

  writeJSON(summaryPath, summary);
  process.stdout.write(`${relPath(summaryPath)}\n`);
  for (const artifact of generatedArtifacts) {
    process.stdout.write(`${artifact.output}\n`);
  }
  if (!allOk(commandResults)) {
    process.exitCode = 1;
  }
}

if (require.main === module) {
  main();
}
