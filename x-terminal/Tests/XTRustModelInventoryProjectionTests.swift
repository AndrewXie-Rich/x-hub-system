import Foundation
import Testing
@testable import XTerminal

struct XTRustModelInventoryProjectionTests {

    @Test
    func projectionDocumentsExactConsumedRustInventoryFields() {
        #expect(XTRustModelInventoryProjection.consumedFieldNames.contains("remote_models.blocking_reason_code"))
        #expect(XTRustModelInventoryProjection.consumedFieldNames.contains("remote_models.next_retry_at_ms"))
        #expect(XTRustModelInventoryProjection.consumedFieldNames.contains("local_models.runtime_preflight.blocking_reason_code"))
        #expect(XTRustModelInventoryProjection.consumedFieldNames.contains("local_models.runtime_preflight.runtime_missing_requirements"))
        #expect(XTRustModelInventoryProjection.consumedFieldNames.contains("local_capability_summary.by_task.*.repair_action"))
        #expect(XTRustModelInventoryProjection.consumedFieldNames.contains("local_capability_summary.coverage_state"))
        #expect(!XTRustModelInventoryProjection.consumedFieldNames.contains("api_key"))
        #expect(!XTRustModelInventoryProjection.consumedFieldNames.contains("refresh_token"))
    }

    @Test
    func repairPlanProjectionCarriesProviderPackStepsWithoutSecrets() throws {
        #expect(XTRustModelRepairPlanProjection.consumedFieldNames.contains("resolved.action"))
        #expect(XTRustModelRepairPlanProjection.consumedFieldNames.contains("steps.*.requires_user_approval"))
        #expect(!XTRustModelRepairPlanProjection.consumedFieldNames.contains("api_key"))

        let raw = """
        {
          "schema_version": "xhub.model_local_runtime_repair_plan.v1",
          "ok": true,
          "state": "repair_required",
          "safe_to_auto_apply": false,
          "requires_user_approval": true,
          "requires_network": true,
          "requires_download": true,
          "secret_fields_included": false,
          "summary": "Install or repair Hub local provider pack `mlx_vlm` before XT uses local model tasks.",
          "resolved": {
            "action": "install_provider_pack:mlx_vlm",
            "task_kind": "vision_understand",
            "provider_id": "mlx_vlm",
            "source": "request_task_kind"
          },
          "target": {
            "kind": "provider_pack",
            "provider_id": "mlx_vlm",
            "task_kind": "vision_understand"
          },
          "requirements": {
            "engine": "mlx-vlm",
            "execution_mode": "builtin_python",
            "install_target": "hub_managed_python_runtime",
            "python_import_modules": ["mlx", "mlx_lm", "mlx_vlm", "transformers", "PIL"],
            "python_packages": ["mlx", "mlx-lm", "mlx-vlm", "transformers", "Pillow"],
            "supported_domains": ["vision", "ocr"],
            "expected_task_kinds": ["vision_understand", "ocr"]
          },
          "missing_requirements": ["python_module:mlx_vlm"],
          "steps": [
            {
              "step_id": "confirm_provider_pack_repair",
              "action_kind": "request_user_approval",
              "title": "Confirm provider pack repair",
              "description": "Hub or XT UI must ask the user before installing runtime dependencies.",
              "requires_user_approval": true,
              "requires_network": false
            },
            {
              "step_id": "install_provider_pack_dependencies",
              "action_kind": "install_provider_pack",
              "title": "Install Hub-managed provider dependencies",
              "description": "Install the required Python modules into Hub's managed runtime.",
              "requires_user_approval": true,
              "requires_network": true
            }
          ]
        }
        """

        let projection = try XTRustModelRepairPlanProjection.decode(from: Data(raw.utf8))

        #expect(projection.schemaVersion == "xhub.model_local_runtime_repair_plan.v1")
        #expect(projection.resolved.action == "install_provider_pack:mlx_vlm")
        #expect(projection.target.providerID == "mlx_vlm")
        #expect(projection.target.taskKind == "vision_understand")
        #expect(projection.safeToAutoApply == false)
        #expect(projection.requiresUserApproval == true)
        #expect(projection.secretFieldsIncluded == false)
        #expect(projection.requirements.pythonImportModules.contains("mlx_vlm"))
        #expect(projection.missingRequirements == ["python_module:mlx_vlm"])
        #expect(projection.steps.last?.actionKind == "install_provider_pack")
    }

    @Test
    func projectionCarriesLocalCapabilitySummaryAndMultimodalTaskKinds() throws {
        let raw = """
        {
          "schema_version": "xhub.model_inventory.v1",
          "updated_at_ms": 1000,
          "remote_models": [],
          "local_models": [
            {
              "model_id": "local-vl",
              "display_name": "Local VL",
              "runtime_provider": "mlx_vlm",
              "availability_state": "ready",
              "capabilities": ["vision.understand", "vision.ocr", "speech.to.text", "text.to.speech"],
              "runtime_preflight": {
                "availability_state": "ready",
                "side_effect_free": true,
                "supported_format": true
              }
            }
          ],
          "local_capability_summary": {
            "schema_version": "xhub.model_local_capability_summary.v1",
            "ready": true,
            "all_tasks_ready": false,
            "coverage_state": "partial",
            "ready_task_count": 1,
            "task_count": 6,
            "by_task": {
              "vision_understand": {
                "task_kind": "vision_understand",
                "capability": "vision.describe",
                "ready": false,
                "state": "missing_runtime",
                "ready_model_count": 0,
                "candidate_model_count": 1,
                "primary_blocking_reason_code": "missing_runtime",
                "repair_action": "install_provider_pack:mlx_vlm"
              }
            },
            "providers": [
              {
                "provider_id": "mlx_vlm",
                "ok": false,
                "reason_code": "missing_runtime",
                "available_task_kinds": [],
                "runtime_missing_requirements": ["python_module:mlx_vlm"],
                "repair_action": "install_provider_pack:mlx_vlm"
              }
            ]
          }
        }
        """
        let projection = try XTRustModelInventoryProjection.decode(from: Data(raw.utf8))
        let model = try #require(projection.snapshot.models.first)

        #expect(model.taskKinds.contains("vision_understand"))
        #expect(model.taskKinds.contains("ocr"))
        #expect(model.taskKinds.contains("speech_to_text"))
        #expect(model.taskKinds.contains("text_to_speech"))
        #expect(projection.localCapabilitySummary?.task("vision_understand")?.state == "missing_runtime")
        #expect(projection.localCapabilitySummary?.coverageState == "partial")
        #expect(projection.localCapabilitySummary?.providers.first?.runtimeMissingRequirements == ["python_module:mlx_vlm"])
        #expect(projection.containsPotentialSecretMaterial == false)
    }

    @Test
    func remoteQuotaFixtureProjectsBlockedRemoteWithoutSecrets() throws {
        let projection = try loadProjectionFixture("remote_quota_blocked")
        let inventory = XTVisibleHubModelInventorySupport.build(rustInventory: projection)
        let model = try #require(inventory.model(for: "gpt-5.5"))

        #expect(projection.schemaVersion == "xhub.model_inventory.v1")
        #expect(projection.remoteModels.first?.blockingReasonCode == "quota_exhausted")
        #expect(model.state == .available)
        #expect(model.remoteEndpointHost == "api.openai.com")
        #expect(model.remoteKeyReference == "openai:free")
        #expect(model.note?.contains("quota_exhausted") == true)
        #expect(projection.containsPotentialSecretMaterial == false)

        let presentation = XTModelInventoryTruthPresentation.build(rustInventory: projection)
        #expect(presentation.state == .remoteQuotaBlocked)
        #expect(presentation.summary.contains("没有可用额度"))
        #expect(presentation.detail.contains("quota_exhausted"))
        #expect(presentation.detail.contains("next_retry_at_ms=7200000"))
    }

    @Test
    func remoteMissingScopeFixturePreservesProviderScopeBlocker() throws {
        let projection = try loadProjectionFixture("remote_missing_scope")
        let presentation = XTModelInventoryTruthPresentation.build(rustInventory: projection)

        #expect(projection.firstRemoteScopeBlocked?.blockingReasonCode == "missing_scope:api.model.read")
        #expect(presentation.state == .remoteScopeMissing)
        #expect(presentation.headline.contains("权限不足"))
        #expect(presentation.detail.contains("api.model.read"))
        #expect(!presentation.detail.contains("sk-"))
        #expect(projection.containsPotentialSecretMaterial == false)
    }

    @Test
    func localRuntimeMissingFixtureDoesNotTreatLocalModelAsReady() throws {
        let projection = try loadProjectionFixture("local_runtime_missing")
        let model = try #require(projection.snapshot.models.first)
        let presentation = XTModelInventoryTruthPresentation.build(rustInventory: projection)

        #expect(model.isLocalModel)
        #expect(model.state == .available)
        #expect(model.offlineReady == false)
        #expect(model.note?.contains("runtime_status_missing") == true)
        #expect(projection.firstLocalRuntimeMissing?.runtimePreflight.blockingReasonCode == "runtime_status_missing")
        #expect(presentation.state == .localRuntimeMissing)
        #expect(presentation.summary.contains("runtime/preflight 不可信"))
        #expect(presentation.detail.contains("runtime_status_missing"))
    }

    @Test
    func localCapabilityMismatchFixtureKeepsMissingRequirementVisible() throws {
        let projection = try loadProjectionFixture("local_capability_mismatch")
        let model = try #require(projection.snapshot.models.first)
        let presentation = XTModelInventoryTruthPresentation.build(rustInventory: projection)

        #expect(model.isLocalModel)
        #expect(model.state == .available)
        #expect(model.taskKinds == ["text_generate"])
        #expect(model.note?.contains("capability_mismatch:code.review") == true)
        #expect(projection.firstLocalCapabilityMismatch?.runtimePreflight.runtimeMissingRequirements == ["code.review"])
        #expect(presentation.state == .localCapabilityMismatch)
        #expect(presentation.detail.contains("capability_mismatch:code.review"))
        #expect(presentation.detail.contains("missing=code.review"))
    }

    private func loadProjectionFixture(_ name: String) throws -> XTRustModelInventoryProjection {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("RustModelInventory", isDirectory: true)
            .appendingPathComponent("\(name).json")
        return try XTRustModelInventoryProjection.load(from: url)
    }
}
