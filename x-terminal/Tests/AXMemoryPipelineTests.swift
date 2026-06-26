import Foundation
import Testing
@testable import XTerminal

actor MemoryWritebackCandidateExtractRecorder {
    private var requests: [(HubIPCClient.MemoryWritebackCandidateExtractPayload, Double)] = []

    func append(_ payload: HubIPCClient.MemoryWritebackCandidateExtractPayload, timeoutSec: Double) {
        requests.append((payload, timeoutSec))
    }

    func snapshot() -> [(HubIPCClient.MemoryWritebackCandidateExtractPayload, Double)] {
        requests
    }
}

struct AXMemoryPipelineTests {
    @Test
    func effectiveFailureReasonCodePrefersFallbackReason() {
        let usage = LLMUsage(
            promptTokens: 10,
            completionTokens: 20,
            fallbackReasonCode: "model_not_found",
            denyCode: "remote_export_blocked"
        )

        #expect(AXMemoryPipeline.effectiveFailureReasonCode(for: usage) == "model_not_found")
    }

    @Test
    func effectiveFailureReasonCodeFallsBackToDenyCode() {
        let usage = LLMUsage(
            promptTokens: 10,
            completionTokens: 20,
            fallbackReasonCode: nil,
            denyCode: "remote export blocked"
        )

        #expect(AXMemoryPipeline.effectiveFailureReasonCode(for: usage) == "remote_export_blocked")
    }

    @Test
    func effectiveFailureReasonCodeReturnsEmptyWhenUsageHasNoFailureReason() {
        let usage = LLMUsage(promptTokens: 10, completionTokens: 20)

        #expect(AXMemoryPipeline.effectiveFailureReasonCode(for: usage).isEmpty)
        #expect(AXMemoryPipeline.effectiveFailureReasonCode(for: nil).isEmpty)
    }

    @Test
    func memoryWritebackCandidatePayloadEncodesAXMemoryDeltaForRustExtractor() throws {
        let root = try makeProjectRoot(named: "memory-candidate-payload")
        let ctx = AXProjectContext(root: root)
        var delta = AXMemoryDelta.empty()
        delta.goalUpdate = "Move AXMemory writeback through Rust candidates."
        delta.decisionsAdd = ["Candidate extraction remains approval-gated."]
        delta.nextStepsAdd = ["Wire the Swift caller to the Rust extractor."]

        let payload = AXMemoryPipeline.memoryWritebackCandidateExtractPayload(
            ctx: ctx,
            delta: delta,
            deltaSource: "coarse_model_json",
            createdAt: 1_778_464_922.215
        )

        #expect(payload.projectId == AXProjectRegistryStore.projectId(forRoot: root))
        #expect(payload.actor == "x_terminal")
        #expect(payload.source == "xt_axmemory_pipeline")
        #expect(payload.auditRef.hasPrefix("xt_axmemory_delta_candidate_extract:"))
        #expect(payload.evidenceRefs == ["xt_axmemory_delta:coarse_model_json:1778464922215"])
        #expect(payload.delta.goalUpdate == "Move AXMemory writeback through Rust candidates.")

        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]
        let encoded = try #require(object)
        let encodedDelta = try #require(encoded["delta"] as? [String: Any])
        #expect(encoded["project_id"] as? String == payload.projectId)
        #expect(encoded["source"] as? String == "xt_axmemory_pipeline")
        #expect(encodedDelta["goalUpdate"] as? String == delta.goalUpdate)
        #expect(encodedDelta["decisionsAdd"] as? [String] == delta.decisionsAdd)
    }

    @Test
    func emitMemoryWritebackCandidatesCallsRustExtractorAndLogsCandidateOnlyResult() async throws {
        let root = try makeProjectRoot(named: "memory-candidate-emit")
        let ctx = AXProjectContext(root: root)
        var delta = AXMemoryDelta.empty()
        delta.requirementsAdd = ["Keep writeback candidate-only until Hub approval."]
        delta.risksAdd = ["Do not let XT become a second memory authority."]
        let recorder = MemoryWritebackCandidateExtractRecorder()

        HubIPCClient.installMemoryWritebackCandidateExtractOverrideForTesting { payload, timeoutSec in
            await recorder.append(payload, timeoutSec: timeoutSec)
            return HubIPCClient.MemoryWritebackCandidateExtractResult(
                ok: true,
                source: "rust_http",
                status: "ok",
                projectId: payload.projectId,
                applied: true,
                candidateCount: 2,
                createdCount: 2,
                plannedCreateCount: 2,
                duplicateCount: 0,
                blockingCount: 0,
                candidateWriteback: HubIPCClient.MemoryWritebackCandidateWriteback(
                    enabled: true,
                    authority: "rust_policy_gated_candidate_queue",
                    requiresApproval: true,
                    activeWrite: false,
                    productionAuthorityChange: false
                )
            )
        }
        defer { HubIPCClient.resetMemoryWritebackCandidateExtractOverrideForTesting() }

        let result = await AXMemoryPipeline.emitMemoryWritebackCandidates(
            ctx: ctx,
            delta: delta,
            deltaSource: "runtime_fallback",
            createdAt: 1_778_464_922.215,
            timeoutSec: 0.25
        )

        #expect(result.ok)
        #expect(result.candidateWriteback?.activeWrite == false)
        #expect(result.candidateWriteback?.productionAuthorityChange == false)
        let requests = await recorder.snapshot()
        #expect(requests.count == 1)
        #expect(requests.first?.0.projectId == AXProjectRegistryStore.projectId(forRoot: root))
        #expect(requests.first?.0.delta.requirementsAdd == delta.requirementsAdd)
        #expect(requests.first?.0.delta.risksAdd == delta.risksAdd)
        #expect(requests.first?.1 == 0.25)

        let log = try String(contentsOf: ctx.rawLogURL, encoding: .utf8)
        #expect(log.contains("\"type\":\"memory_writeback_candidate_extract\""))
        #expect(log.contains("\"active_write\":false"))
        #expect(log.contains("\"production_authority_change\":false"))
        #expect(log.contains("\"requires_approval\":true"))
    }

    @Test
    func memoryDeltaHasCandidateContentIgnoresRemovalOnlyDelta() {
        var removalOnly = AXMemoryDelta.empty()
        removalOnly.requirementsRemove = ["obsolete local-only note"]
        removalOnly.nextStepsRemove = ["old step"]

        #expect(AXMemoryPipeline.memoryDeltaHasCandidateContent(removalOnly) == false)

        var candidate = AXMemoryDelta.empty()
        candidate.openQuestionsAdd = ["Should this become a governed Hub candidate?"]
        #expect(AXMemoryPipeline.memoryDeltaHasCandidateContent(candidate))
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
