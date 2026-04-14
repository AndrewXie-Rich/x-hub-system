#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");

const {
  allowedRuntimeResolutionStates,
  buildProviderRuntimeInventoryEvidence,
} = require("./generate_lpr_w4_02_b_provider_runtime_inventory_evidence.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

run("LPR-W4-02 runtime inventory evidence passes when provider pack/runtime truth is visible", () => {
  const report = buildProviderRuntimeInventoryEvidence({
    ok: true,
    is_alive: true,
    age_ms: 123,
    schema_version: "xhub.local_runtime_status.v2",
    runtime_version: "2026-03-23-provider-runtime-inventory-v1",
    loaded_instance_count: 1,
    provider_ids: ["mlx", "transformers"],
    provider_packs: [
      {
        provider_id: "mlx",
        engine: "mlx-llm",
        version: "builtin-2026-03-16",
        installed: true,
        enabled: true,
        pack_state: "installed",
        reason_code: "builtin_pack_registered",
      },
      {
        provider_id: "transformers",
        engine: "hf-transformers",
        version: "builtin-2026-03-16",
        installed: true,
        enabled: true,
        pack_state: "installed",
        reason_code: "builtin_pack_registered",
      },
    ],
    providers: {
      mlx: {
        ok: true,
        reason_code: "ready",
        pack_id: "mlx",
        pack_engine: "mlx-llm",
        pack_version: "builtin-2026-03-16",
        pack_installed: true,
        pack_enabled: true,
        pack_state: "installed",
        pack_reason_code: "builtin_pack_registered",
        runtime_source: "user_python_custom",
        runtime_source_path: "/Users/test/python3",
        runtime_resolution_state: "user_runtime_fallback",
        runtime_reason_code: "ready",
        fallback_used: true,
        runtime_hint: "mlx is running from user Python /Users/test/python3.",
        runtime_missing_requirements: [],
        runtime_missing_optional_requirements: [],
        available_task_kinds: ["text_generate"],
      },
      transformers: {
        ok: false,
        reason_code: "no_registered_models",
        pack_id: "transformers",
        pack_engine: "hf-transformers",
        pack_version: "builtin-2026-03-16",
        pack_installed: true,
        pack_enabled: true,
        pack_state: "installed",
        pack_reason_code: "builtin_pack_registered",
        runtime_source: "hub_py_deps",
        runtime_source_path: "/Users/test/RELFlowHub/ai_runtime",
        runtime_resolution_state: "runtime_missing",
        runtime_reason_code: "missing_runtime",
        fallback_used: false,
        runtime_hint: "transformers runtime is missing required dependencies (python_module:torch).",
        runtime_missing_requirements: ["python_module:torch"],
        runtime_missing_optional_requirements: [],
        available_task_kinds: [],
      },
    },
  }, {
    generatedAt: "2026-03-23T02:00:00Z",
    runtimeBaseDir: "/Users/test/RELFlowHub",
    maxAgeMs: 86400000,
  });

  assert.equal(report.status, "PASS(provider_runtime_inventory_contract_captured)");
  assert.equal(report.summary.provider_pack_inventory_visible_for_all, true);
  assert.equal(report.summary.runtime_resolution_visible_for_all, true);
  assert.deepEqual(report.machine_decision.user_runtime_fallback_providers, ["mlx"]);
  assert.deepEqual(report.machine_decision.runtime_missing_providers, ["transformers"]);
  assert.deepEqual(report.machine_decision.observed_runtime_resolution_states, [
    "user_runtime_fallback",
    "runtime_missing",
  ]);
  assert.deepEqual(report.runtime_inventory_contract.allowed_runtime_resolution_states, allowedRuntimeResolutionStates);
  assert.ok(report.machine_decision.current_blockers.includes("runtime_missing:transformers"));
  assert.equal(report.recommended_actions[0].provider_id, "mlx");
  assert.equal(report.recommended_actions[0].action_id, "move_off_user_python");
  assert.equal(report.recommended_actions[1].provider_id, "transformers");
  assert.equal(report.recommended_actions[1].action_id, "restore_pack_owned_runtime");
});

run("LPR-W4-02 runtime inventory evidence fails closed when runtime snapshot is missing", () => {
  const report = buildProviderRuntimeInventoryEvidence({
    ok: false,
    is_alive: false,
    provider_ids: [],
    provider_packs: [],
    providers: {},
  }, {
    runtimeBaseDir: "/Users/test/RELFlowHub",
    maxAgeMs: 86400000,
  });

  assert.equal(report.status, "FAIL(runtime_status_snapshot_missing)");
  assert.deepEqual(report.machine_decision.current_blockers, ["runtime_status_snapshot_missing"]);
});

run("LPR-W4-02 runtime inventory evidence detects provider pack/runtime consistency gaps", () => {
  const report = buildProviderRuntimeInventoryEvidence({
    ok: true,
    is_alive: true,
    provider_ids: ["transformers"],
    provider_packs: [
      {
        provider_id: "transformers",
        engine: "hf-transformers",
        version: "builtin-2026-03-16",
        installed: true,
        enabled: true,
        pack_state: "legacy_unreported",
        reason_code: "runtime_status_missing_provider_pack_inventory",
      },
    ],
    providers: {
      transformers: {
        ok: true,
        reason_code: "ready",
        pack_id: "transformers",
        pack_engine: "hf-transformers",
        pack_version: "builtin-2026-03-16",
        pack_installed: true,
        pack_enabled: true,
        pack_state: "installed",
        pack_reason_code: "builtin_pack_registered",
        runtime_source: "xhub_local_service",
        runtime_source_path: "http://127.0.0.1:50053",
        runtime_resolution_state: "pack_runtime_ready",
        runtime_reason_code: "xhub_local_service_ready",
        fallback_used: false,
        runtime_hint: "service-hosted Python modules are reachable.",
        runtime_missing_requirements: [],
        runtime_missing_optional_requirements: [],
      },
    },
  }, {
    runtimeBaseDir: "/Users/test/RELFlowHub",
    maxAgeMs: 86400000,
  });

  assert.equal(report.status, "FAIL(provider_pack_inventory_not_materialized)");
  assert.deepEqual(report.machine_decision.pack_consistency_gaps, [
    "provider=transformers:pack_inventory_not_materialized",
  ]);
});
