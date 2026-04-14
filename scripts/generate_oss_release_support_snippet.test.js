#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const {
  buildReleaseSupportSnippet,
} = require("./generate_oss_release_support_snippet.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

function makePacket(overrides = {}) {
  return {
    generated_at: "2026-03-24T10:00:00Z",
    operator_handoff: {
      primary_issue_reason_code: "xhub_local_service_unreachable",
      managed_process_state: "running",
      top_recommended_action: {
        action_id: "inspect_managed_service_snapshot",
        title: "Inspect managed service snapshot before retry",
        command_or_ref: "build/reports/xhub_doctor_xt_source_smoke_evidence.v1.json",
      },
      next_commands: [
        "bash scripts/ci/xhub_doctor_source_gate.sh",
        "node scripts/generate_xhub_operator_channel_recovery_report.js",
      ],
      runbook_refs: [
        "docs/WORKING_INDEX.md",
        "docs/open-source/OSS_RELEASE_CHECKLIST_v1.md",
      ],
      channel_onboarding_focus: {
        support_ready: true,
        current_failure_code: "channel_runtime_missing",
        current_failure_issue: "channel_runtime",
        heartbeat_governance_visibility_gap: false,
        channel_focus_highlight: "",
        action_category: "restore_channel_admin_surface",
        top_recommended_action: {
          action_id: "restore_channel_admin_surface",
          title: "Restore operator channel admin surface",
          command_or_ref: "hub://settings/operator_channels",
        },
      },
      require_real_focus: {
        handoff_state: "blocked",
        blocker_class: "current_embedding_dirs_incompatible_with_native_transformers_load",
        top_recommended_action: {
          action_id: "source_native_loadable_embedding_model_dir",
          action_summary: "Source one native-loadable real embedding model dir first.",
        },
      },
    },
    release_handoff: {
      external_status_line:
        "Structured xhub_local_service doctor/export/recovery truth is integrated, but release remains blocked until require-real closure reaches candidate_go.",
      remote_channel_status_line:
        "Structured operator-channel onboarding doctor truth is available, but this surface remains preview-working rather than validated.",
      boundary_status: "delivered(validated_mainline_release_oss_boundary_ready)",
      oss_release_stance: "GO",
      release_blockers: ["require-real evidence still missing"],
      refresh_bundle_ready: true,
    },
    ...overrides,
  };
}

run("release support snippet keeps operator-channel wording in preview/support lane", () => {
  const snippet = buildReleaseSupportSnippet(makePacket(), {
    packetRef: "build/reports/lpr_w4_09_c_product_exit_packet.v1.json",
  });

  assert.match(snippet.markdown, /preview-working rather than validated/);
  assert.match(snippet.markdown, /do not present it as a validated release claim/i);
  assert.match(snippet.markdown, /Channel action category: restore_channel_admin_surface/);
  assert.match(snippet.markdown, /Channel governance visibility gap: no/);
  assert.match(snippet.markdown, /Channel focus highlight: none/);
  assert.match(snippet.markdown, /Restore operator channel admin surface -> hub:\/\/settings\/operator_channels/);
  assert.match(snippet.markdown, /Sample1 blocker class: current_embedding_dirs_incompatible_with_native_transformers_load/);
  assert.match(snippet.markdown, /Local-service recovery and require-real closure remain the release-gating truth/);
});

run("release support snippet surfaces heartbeat governance visibility gaps for operator handoff", () => {
  const snippet = buildReleaseSupportSnippet(
    makePacket({
      operator_handoff: {
        ...makePacket().operator_handoff,
        channel_onboarding_focus: {
          support_ready: true,
          current_failure_code: "channel_live_test_heartbeat_visibility_missing",
          current_failure_issue: "channel_live_test",
          heartbeat_governance_visibility_gap: true,
          channel_focus_highlight:
            "First smoke proof still lacks heartbeat governance visibility.",
          action_category: "restore_heartbeat_governance_visibility",
          top_recommended_action: {
            action_id: "restore_heartbeat_governance_visibility",
            title: "Inspect operator channel diagnostics",
            command_or_ref: "hub://settings/diagnostics",
          },
        },
      },
    }),
    {
      packetRef: "build/reports/lpr_w4_09_c_product_exit_packet.v1.json",
    }
  );

  assert.match(snippet.markdown, /Channel governance visibility gap: yes/);
  assert.match(
    snippet.markdown,
    /Channel focus highlight: First smoke proof still lacks heartbeat governance visibility\./
  );
  assert.match(
    snippet.markdown,
    /Channel next action: Inspect operator channel diagnostics -> hub:\/\/settings\/diagnostics/
  );
});

run("release support snippet fails soft when operator-channel support is absent", () => {
  const packet = makePacket({
    operator_handoff: {
      primary_issue_reason_code: "xhub_local_service_unreachable",
      managed_process_state: "down",
      top_recommended_action: null,
      next_commands: [],
      runbook_refs: [],
      channel_onboarding_focus: null,
      require_real_focus: null,
    },
    release_handoff: {
      external_status_line: "",
      remote_channel_status_line: "",
      boundary_status: "",
      oss_release_stance: "",
      release_blockers: [],
      refresh_bundle_ready: false,
    },
  });
  const snippet = buildReleaseSupportSnippet(packet, {
    packetRef: "build/reports/lpr_w4_09_c_product_exit_packet.v1.json",
  });

  assert.match(snippet.markdown, /Structured operator-channel onboarding recovery wording is not available/);
  assert.match(snippet.markdown, /Channel support ready: unknown/);
  assert.match(snippet.markdown, /Channel next action: not available/);
  assert.match(snippet.markdown, /- none$/m);
});

run("cli writes the markdown artifact", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "xhub-release-support-snippet-"));
  try {
    const packetPath = path.join(root, "packet.json");
    const outputPath = path.join(root, "snippet.md");
    fs.writeFileSync(packetPath, `${JSON.stringify(makePacket(), null, 2)}\n`, "utf8");

    const result = spawnSync(
      "node",
      [
        path.join(__dirname, "generate_oss_release_support_snippet.js"),
        "--packet",
        packetPath,
        "--out",
        outputPath,
      ],
      {
        cwd: root,
        encoding: "utf8",
      }
    );

    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.match(result.stdout, /snippet\.md/);
    const markdown = fs.readFileSync(outputPath, "utf8");
    assert.match(markdown, /# OSS Release Support Snippet v1/);
    assert.match(markdown, /## Internal Operator Handoff/);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
