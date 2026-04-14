import Foundation
import Testing
@testable import XTerminal

struct HubAIClientErrorPresentationTests {
    @Test
    func rawGRPCUnavailableReasonGetsFriendlyGuidance() {
        let error = HubAIError.responseDoneNotOk(
            HubAIResponseFailureContext(
                reason: "14_UNAVAILABLE:_No_connection_established._Last_error:_null._Resolution_note:",
                deviceName: "Andrew Mac",
                modelId: "qwen3-14b-mlx"
            )
        )

        let description = error.errorDescription ?? ""
        #expect(description.contains("Hub gRPC is unavailable"))
        #expect(description.contains("/hub route auto"))
    }

    @Test
    func providerTokenExpiredGetsFriendlyGuidance() {
        let error = HubAIError.responseDoneNotOk(
            HubAIResponseFailureContext(
                reason: "provider_token_expired",
                deviceName: "Andrew Mac",
                modelId: "openai/gpt-5.3-codex"
            )
        )

        let description = error.errorDescription ?? ""
        #expect(description.contains("Remote model access token is expired"))
        #expect(description.contains("Remote Models / Models & Paid Access"))
    }
}
