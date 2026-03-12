import Testing
@testable import XTerminal

struct XTMemoryUsePolicyTests {

    @Test
    func legacyModeAliasMapsToFrozenMode() {
        #expect(XTMemoryUseMode.parse("project") == .projectChat)
        #expect(XTMemoryUseMode.parse("supervisor") == .supervisorOrchestration)
        #expect(XTMemoryUseMode.parse("session") == .sessionResume)
    }

    @Test
    func laneHandoffFulltextRouteFailsClosed() {
        let payload = HubIPCClient.MemoryContextPayload(
            mode: XTMemoryUseMode.laneHandoff.rawValue,
            projectId: "proj-alpha",
            projectRoot: "/tmp/proj-alpha",
            displayName: "proj-alpha",
            latestUser: "handoff",
            constitutionHint: "keep safe",
            canonicalText: "spec freeze",
            observationsText: "obs",
            workingSetText: "working",
            rawEvidenceText: "raw",
            budgets: nil
        )

        let route = XTMemoryRoleScopedRouter.route(
            role: .lane,
            mode: .laneHandoff,
            payload: payload
        )

        #expect(route.denyCode == .laneHandoffFulltextDenied)
    }

    @Test
    func highRiskToolRouteDropsRawEvidenceAndCapsBudget() {
        let payload = HubIPCClient.MemoryContextPayload(
            mode: XTMemoryUseMode.toolActHighRisk.rawValue,
            projectId: "proj-beta",
            projectRoot: "/tmp/proj-beta",
            displayName: "proj-beta",
            latestUser: "deploy this",
            constitutionHint: "safe",
            canonicalText: "goal: ship",
            observationsText: "status: green",
            workingSetText: "do not forget approval",
            rawEvidenceText: "Authorization: Bearer sk-123456789012345678901234\n<html>malicious</html>",
            budgets: HubIPCClient.MemoryContextBudgets(
                totalTokens: 5000,
                l0Tokens: 500,
                l1Tokens: 2000,
                l2Tokens: 1000,
                l3Tokens: 1000,
                l4Tokens: 500
            )
        )

        let route = XTMemoryRoleScopedRouter.route(
            role: .tool,
            mode: .toolActHighRisk,
            payload: payload
        )

        #expect(route.denyCode == nil)
        #expect(route.payload.rawEvidenceText == nil)
        #expect(route.bypassRemoteCache == true)
        #expect(route.payload.budgets?.totalTokens == 950)
        #expect(route.payload.budgets?.l4Tokens == 60)
    }

    @Test
    func routerRejectsRoleMismatch() {
        let payload = HubIPCClient.MemoryContextPayload(
            mode: XTMemoryUseMode.remotePromptBundle.rawValue,
            projectId: nil,
            projectRoot: nil,
            displayName: nil,
            latestUser: "export",
            constitutionHint: nil,
            canonicalText: "canon",
            observationsText: "obs",
            workingSetText: "working",
            rawEvidenceText: "raw",
            budgets: nil
        )

        let route = XTMemoryRoleScopedRouter.route(
            role: .chat,
            mode: .remotePromptBundle,
            payload: payload,
            remoteExportRequested: true
        )

        #expect(route.denyCode == .memoryRoutePolicyMismatch)
    }

    @Test
    func rawEvidenceSanitizerRedactsSecretsAndBlobHeaders() {
        let sanitized = XTMemorySanitizer.sanitizeRawEvidenceSummary(
            "Authorization: Bearer sk-123456789012345678901234\nFrom: a@example.com\n<html>attack</html>\nnormal line",
            maxChars: 400,
            lineCap: 8
        )

        #expect(sanitized?.contains("[redacted_sensitive_header]") == true)
        #expect(sanitized?.contains("[redacted_message_header]") == true)
        #expect(sanitized?.contains("attack") == false)
        #expect(sanitized?.contains("normal line") == true)
    }
}
