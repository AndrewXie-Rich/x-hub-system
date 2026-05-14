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

    @Test
    func remoteHTML504BadJSONGetsFriendlyGuidance() {
        let error = HubAIError.responseDoneNotOk(
            HubAIResponseFailureContext(
                reason: """
                bad_json:<!DOCTYPE html>
                <html lang="en-US">
                <head><title>picfix.pro | 504: Gateway time-out</title></head>
                <body><h1>Gateway time-out</h1><span>Error code 504</span></body>
                </html>
                """,
                deviceName: "Andrew Mac",
                modelId: "openai/gpt-5.4"
            )
        )

        let description = error.errorDescription ?? ""
        #expect(description.contains("HTML 504 Gateway Time-out page"))
        #expect(description.contains("Remote Models"))
        #expect(!description.contains("<!DOCTYPE html>"))
    }
}
