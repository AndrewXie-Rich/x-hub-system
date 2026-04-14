#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");

const {
  buildHelperLocalServiceRecoveryReport,
} = require("./generate_lpr_w3_03_sample1_helper_local_service_recovery.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

run("sample1 helper local-service recovery report exposes enableLocalService blocker and next action", () => {
  const report = buildHelperLocalServiceRecoveryReport({
    helperProbe: {
      helper_binary_path: "/Users/demo/.lmstudio/bin/lms",
      helper_server_base_url: "http://127.0.0.1:1234",
      summary: {
        helper_binary_found: true,
        daemon_probe_before: "helper_local_service_disabled",
        daemon_probe_after: "helper_local_service_disabled",
        server_result_reason: "helper_local_service_disabled",
        server_models_endpoint_ok: false,
        primary_blocker:
          "helper_local_service_disabled_before_probe;probe_after=helper_local_service_disabled",
        recommended_next_step:
          "enable_lm_studio_local_service_or_complete_first_launch_then_rerun_helper_bridge_probe",
        lmstudio_environment: {
          settings_found: true,
          settings_path: "/Users/demo/.lmstudio/settings.json",
          enable_local_service: false,
          cli_installed: false,
          app_first_load: true,
          attempted_install_lms_cli_on_startup: true,
          llmster_pid_lock_path: "/Users/demo/.lmstudio/.internal/llmster-pid.lock",
          llmster_pid_lock_value: "12345",
        },
      },
      artifact_refs: {
        python_probe_before_meta: "build/reports/helper/python_probe_before.meta.json",
      },
    },
  });

  assert.equal(
    report.helper_route_contract.helper_route_ready_verdict,
    "NO_GO(helper_bridge_not_ready_for_secondary_reference_route)"
  );
  assert.equal(report.current_machine_state.enable_local_service, false);
  assert.equal(report.top_recommended_action.action_id, "enable_lm_studio_local_service");
  assert.equal(
    report.top_recommended_action.next_step,
    "turn_on_local_service_then_rerun_helper_probe"
  );
  assert.ok(
    report.operator_workflow.some((item) =>
      String(item.command_or_ref || "").includes("Local Service")
    )
  );
  assert.ok(
    report.command_refs.some((item) => item.includes("generate_lpr_w3_03_d_helper_bridge_probe.js"))
  );
});

run("sample1 helper local-service recovery report flips PASS when helper route is ready", () => {
  const report = buildHelperLocalServiceRecoveryReport({
    helperProbe: {
      helper_binary_path: "/Users/demo/.lmstudio/bin/lms",
      helper_server_base_url: "http://127.0.0.1:1234",
      summary: {
        helper_binary_found: true,
        daemon_probe_before: "helper_bridge_ready",
        daemon_probe_after: "helper_bridge_ready",
        server_result_reason: "",
        server_models_endpoint_ok: true,
        primary_blocker: "",
        recommended_next_step: "helper_bridge_is_ready_try_loading_embedding_model_via_helper_route",
        lmstudio_environment: {
          settings_found: true,
          settings_path: "/Users/demo/.lmstudio/settings.json",
          enable_local_service: true,
          cli_installed: true,
          app_first_load: false,
        },
      },
    },
  });

  assert.equal(
    report.helper_route_contract.helper_route_ready_verdict,
    "PASS(helper_bridge_ready_for_secondary_reference_route)"
  );
  assert.equal(report.top_recommended_action.action_id, "keep_helper_route_secondary_only");
  assert.equal(report.current_machine_state.server_models_endpoint_ok, true);
});
