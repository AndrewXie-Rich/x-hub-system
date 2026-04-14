#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");

const {
  buildTypedLoadConfigEvidence,
  loadConfigSchemaVersion,
} = require("./generate_lpr_w4_03_a_typed_load_config_evidence.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

run("LPR-W4-03 typed load config evidence passes when model and loaded-instance contracts are visible", () => {
  const report = buildTypedLoadConfigEvidence(
    {
      snapshot: {
        ok: true,
        is_alive: true,
        age_ms: 120,
        schema_version: "xhub.local_runtime_status.v2",
        runtime_version: "2026-03-23-w4-03-a",
        loaded_instances: [
          {
            provider: "transformers",
            instance_key: "transformers:glm4v:hash-a",
            model_id: "glm4v",
            load_config_hash: "hash-a",
            current_context_length: 16384,
            max_context_length: 65536,
            load_config: {
              schema_version: loadConfigSchemaVersion,
              context_length: 16384,
              ttl: 600,
              parallel: 3,
            },
            residency: "resident",
            last_used_at_ms: 10,
          },
        ],
      },
      modelRecords: [
        {
          model_id: "glm4v",
          backend: "transformers",
          task_kinds: ["vision_understand"],
          default_context_length: 16384,
          max_context_length: 65536,
          default_load_config: {
            schema_version: loadConfigSchemaVersion,
            context_length: 16384,
            ttl: 600,
            parallel: 3,
          },
        },
      ],
    },
    {
      generatedAt: "2026-03-23T03:00:00Z",
      runtimeBaseDir: "/Users/test/RELFlowHub",
      maxAgeMs: 86400000,
    }
  );

  assert.equal(report.status, "PASS(typed_load_config_contract_captured)");
  assert.equal(report.summary.model_info_load_config_visible_for_all, true);
  assert.equal(report.summary.loaded_instance_contract_observed, true);
  assert.equal(
    report.summary.loaded_instance_load_config_visible_for_all_observed,
    true
  );
  assert.equal(
    report.summary.load_config_hash_visible_for_all_loaded_instances,
    true
  );
  assert.deepEqual(report.machine_decision.current_blockers, []);
});

run("LPR-W4-03 typed load config evidence fails closed when model info lacks default load config", () => {
  const report = buildTypedLoadConfigEvidence(
    {
      snapshot: {
        ok: true,
        is_alive: true,
        loaded_instances: [],
      },
      modelRecords: [
        {
          model_id: "hf-embed",
          backend: "transformers",
          default_context_length: 8192,
          max_context_length: 8192,
          default_load_config: null,
        },
      ],
    },
    {
      runtimeBaseDir: "/Users/test/RELFlowHub",
      maxAgeMs: 86400000,
    }
  );

  assert.equal(report.status, "FAIL(model_info_load_config_incomplete)");
  assert.deepEqual(report.machine_decision.model_info_gaps, [
    "model=hf-embed:missing=default_load_config",
  ]);
});

run("LPR-W4-03 typed load config evidence fails closed when loaded instance lacks typed hash and config", () => {
  const report = buildTypedLoadConfigEvidence(
    {
      snapshot: {
        ok: true,
        is_alive: true,
        loaded_instances: [
          {
            provider: "mlx",
            instance_key: "mlx:qwen:hash-b",
            model_id: "qwen",
            current_context_length: 40960,
            max_context_length: 40960,
            load_config: null,
          },
        ],
      },
      modelRecords: [
        {
          model_id: "qwen",
          backend: "mlx",
          default_context_length: 40960,
          max_context_length: 40960,
          default_load_config: {
            schema_version: loadConfigSchemaVersion,
            context_length: 40960,
          },
        },
      ],
    },
    {
      runtimeBaseDir: "/Users/test/RELFlowHub",
      maxAgeMs: 86400000,
    }
  );

  assert.equal(report.status, "FAIL(loaded_instance_load_config_incomplete)");
  assert.deepEqual(report.machine_decision.loaded_instance_gaps, [
    "instance=mlx:qwen:hash-b:missing=load_config_hash,load_config",
  ]);
});
