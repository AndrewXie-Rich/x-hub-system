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
    func supervisorReviewRequestAutoSelectsPlanReviewProfileAndExpandsContextBudget() {
        let longCanonical = String(repeating: "c", count: 3_000)
        let payload = HubIPCClient.MemoryContextPayload(
            mode: XTMemoryUseMode.supervisorOrchestration.rawValue,
            projectId: "proj-supervisor",
            projectRoot: "/tmp/proj-supervisor",
            displayName: "proj-supervisor",
            latestUser: "审查项目上下文记忆，给出最具体的执行方案",
            constitutionHint: "safe",
            canonicalText: longCanonical,
            observationsText: "obs",
            workingSetText: "working",
            rawEvidenceText: "raw",
            budgets: nil
        )

        let route = XTMemoryRoleScopedRouter.route(
            role: .supervisor,
            mode: .supervisorOrchestration,
            payload: payload
        )

        #expect(route.denyCode == nil)
        #expect(route.servingProfile == .m2PlanReview)
        #expect(route.payload.servingProfile == XTMemoryServingProfile.m2PlanReview.rawValue)
        #expect(route.payload.budgets?.totalTokens == 2_340)
        #expect(route.payload.canonicalText?.count == 3_000)
    }

    @Test
    func projectChatStructureReviewRequestAutoSelectsPlanReviewProfile() {
        let payload = HubIPCClient.MemoryContextPayload(
            mode: XTMemoryUseMode.projectChat.rawValue,
            projectId: "proj-chat-review",
            projectRoot: "/tmp/proj-chat-review",
            displayName: "proj-chat-review",
            latestUser: "梳理项目结构并给出重构建议",
            constitutionHint: "safe",
            canonicalText: String(repeating: "c", count: 3_500),
            observationsText: "obs",
            workingSetText: "working",
            rawEvidenceText: "raw",
            budgets: nil
        )

        let route = XTMemoryRoleScopedRouter.route(
            role: .chat,
            mode: .projectChat,
            payload: payload
        )

        #expect(route.denyCode == nil)
        #expect(route.servingProfile == .m2PlanReview)
        #expect(route.payload.canonicalText?.count == 3_500)
    }

    @Test
    func projectChatContractRequiresProgressiveDisclosure() {
        let contract = XTMemoryRoleScopedRouter.contract(for: .projectChat)

        #expect(contract.longtermPolicy == .progressiveDisclosureRequired)
    }

    @Test
    func projectChatFullScanRequestAutoSelectsDeepDiveProfile() {
        let payload = HubIPCClient.MemoryContextPayload(
            mode: XTMemoryUseMode.projectChat.rawValue,
            projectId: "proj-chat-deep-dive",
            projectRoot: "/tmp/proj-chat-deep-dive",
            displayName: "proj-chat-deep-dive",
            latestUser: "先完整通读整个仓库，再给我架构重构路径",
            constitutionHint: "safe",
            canonicalText: "goal",
            observationsText: "obs",
            workingSetText: "working",
            rawEvidenceText: "raw",
            budgets: nil
        )

        let route = XTMemoryRoleScopedRouter.route(
            role: .chat,
            mode: .projectChat,
            payload: payload
        )

        #expect(route.denyCode == nil)
        #expect(route.servingProfile == .m3DeepDive)
        #expect(route.payload.budgets?.totalTokens == 4_480)
    }

    @Test
    func highRiskToolRouteClampsFullScanProfileToPlanReview() {
        let payload = HubIPCClient.MemoryContextPayload(
            mode: XTMemoryUseMode.toolActHighRisk.rawValue,
            projectId: "proj-risk",
            projectRoot: "/tmp/proj-risk",
            displayName: "proj-risk",
            latestUser: "完整扫描所有背景再执行高风险动作",
            constitutionHint: "safe",
            canonicalText: "goal",
            observationsText: "obs",
            workingSetText: "working",
            rawEvidenceText: "raw",
            servingProfile: XTMemoryServingProfile.m4FullScan.rawValue,
            budgets: nil
        )

        let route = XTMemoryRoleScopedRouter.route(
            role: .tool,
            mode: .toolActHighRisk,
            payload: payload
        )

        #expect(route.denyCode == nil)
        #expect(route.servingProfile == .m2PlanReview)
        #expect(route.payload.servingProfile == XTMemoryServingProfile.m2PlanReview.rawValue)
        #expect(route.payload.budgets?.totalTokens == 1_710)
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
