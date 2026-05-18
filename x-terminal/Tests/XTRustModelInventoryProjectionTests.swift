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
        #expect(!XTRustModelInventoryProjection.consumedFieldNames.contains("api_key"))
        #expect(!XTRustModelInventoryProjection.consumedFieldNames.contains("refresh_token"))
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
