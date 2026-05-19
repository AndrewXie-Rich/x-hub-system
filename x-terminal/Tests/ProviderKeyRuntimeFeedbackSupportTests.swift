import Foundation
import Testing
@testable import XTerminal

struct ProviderKeyRuntimeFeedbackSupportTests {
    @Test
    func failureFeedbackNormalizesMissingScopeAsAuthError() {
        let error = NSError(
            domain: "xterminal",
            code: 403,
            userInfo: [
                NSLocalizedDescriptionKey: "Provider 权限不足，缺少生成 scope:api.responses.write。"
            ]
        )

        let feedback = ProviderKeyRuntimeFeedbackSupport.failureFeedback(
            accountKey: "openai:test",
            modelID: "gpt-5.4",
            error: error
        )

        #expect(feedback.accountKey == "openai:test")
        #expect(feedback.modelID == "gpt-5.4")
        #expect(feedback.outcome == "auth_error")
        #expect(feedback.httpStatus == 403)
        #expect(feedback.reasonCode == "missing_scope")
    }

    @Test
    func failureFeedbackNormalizesInvalidAPIKeyNoticeAsAuthError() {
        let error = NSError(
            domain: "xterminal",
            code: 401,
            userInfo: [
                NSLocalizedDescriptionKey: "Provider API Key 无效或已被撤销（status=401）。请重新粘贴有效的 Provider API Key，或在服务商后台轮换后再导入。"
            ]
        )

        let feedback = ProviderKeyRuntimeFeedbackSupport.failureFeedback(
            accountKey: "openai:test",
            modelID: "gpt-5.4",
            error: error
        )

        #expect(feedback.outcome == "auth_error")
        #expect(feedback.httpStatus == 401)
        #expect(feedback.reasonCode == "invalid_api_key")
    }

    @Test
    func failureFeedbackNormalizesTimeoutAsNetworkError() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorTimedOut,
            userInfo: [
                NSLocalizedDescriptionKey: "The request timed out."
            ]
        )

        let feedback = ProviderKeyRuntimeFeedbackSupport.failureFeedback(
            accountKey: "openai:test",
            modelID: "gpt-4o",
            error: error
        )

        #expect(feedback.outcome == "network_error")
        #expect(feedback.reasonCode == "provider_timeout")
    }

    @Test
    func matchesRedactedKeyUsesPrefixAndSuffixOnly() {
        #expect(
            ProviderKeyRuntimeFeedbackSupport.matchesRedactedKey(
                "sk-1234567890abcdef",
                redacted: "sk-1...cdef"
            )
        )
        #expect(
            !ProviderKeyRuntimeFeedbackSupport.matchesRedactedKey(
                "sk-1234567890abcdef",
                redacted: "sk-9...ffff"
            )
        )
    }
}
