import Foundation
import Testing
@testable import XTerminal

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
}
