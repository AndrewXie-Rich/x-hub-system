import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorConversationQuickIntentSupportTests {

    @Test
    func guidedProgressBuildsContinuityProjectTodayAndHubIntents() {
        let intents = SupervisorConversationQuickIntentSupport.build(
            context: SupervisorConversationQuickIntentContext(
                workMode: .guidedProgress,
                selectedProject: .init(projectId: "p1", displayName: "X-Terminal"),
                resumeProject: .init(
                    projectId: "p1",
                    projectDisplayName: "X-Terminal",
                    reasonLabel: "切 AI",
                    relativeText: "刚刚"
                ),
                todayFocus: .init(
                    projectId: "p2",
                    projectName: "X-Hub",
                    reasonSummary: "blocked by missing route repair",
                    recommendedNextAction: "repair Hub route",
                    kindLabel: "Decision blocker"
                ),
                awaitingAuthorizationProject: nil,
                awaitingAuthorizationCount: 0,
                hubInteractive: true,
                hubRemoteConnected: true,
                lastReplyExecutionMode: "remote_model",
                lastRemoteFailureReasonCode: ""
            )
        )

        #expect(intents.map(\.id) == [
            "resume",
            "current_project:p1",
            "today_focus",
            "hub_status"
        ])
        #expect(intents[0].title == "接上次进度")
        #expect(intents[1].title == "继续当前项目")
        #expect(intents[2].helpText.contains("X-Hub"))
        #expect(intents[3].tone == .neutral)
    }

    @Test
    func conversationOnlyUsesAnswerStyleProjectPrompt() {
        let intents = SupervisorConversationQuickIntentSupport.build(
            context: SupervisorConversationQuickIntentContext(
                workMode: .conversationOnly,
                selectedProject: .init(projectId: "p1", displayName: "Alpha"),
                resumeProject: nil,
                todayFocus: nil,
                awaitingAuthorizationProject: nil,
                awaitingAuthorizationCount: 0,
                hubInteractive: true,
                hubRemoteConnected: false,
                lastReplyExecutionMode: "idle",
                lastRemoteFailureReasonCode: ""
            )
        )

        #expect(intents.map(\.title) == ["看当前项目", "检查 Hub 状态"])
        #expect(intents[0].prompt.contains("直接告诉我现在做到哪"))
    }

    @Test
    func automationModeStrengthensCurrentProjectPrompt() {
        let intents = SupervisorConversationQuickIntentSupport.build(
            context: SupervisorConversationQuickIntentContext(
                workMode: .governedAutomation,
                selectedProject: .init(projectId: "p1", displayName: "Alpha"),
                resumeProject: nil,
                todayFocus: nil,
                awaitingAuthorizationProject: nil,
                awaitingAuthorizationCount: 0,
                hubInteractive: true,
                hubRemoteConnected: true,
                lastReplyExecutionMode: "remote_model",
                lastRemoteFailureReasonCode: ""
            )
        )

        #expect(intents.first?.title == "推进当前项目")
        #expect(intents.first?.prompt.contains("治理边界、授权和运行时都允许") == true)
    }

    @Test
    func awaitingAuthorizationAndFallbackSurfaceDiagnosticIntents() {
        let intents = SupervisorConversationQuickIntentSupport.build(
            context: SupervisorConversationQuickIntentContext(
                workMode: .guidedProgress,
                selectedProject: nil,
                resumeProject: nil,
                todayFocus: nil,
                awaitingAuthorizationProject: .init(projectId: "p-auth", displayName: "Billing"),
                awaitingAuthorizationCount: 2,
                hubInteractive: true,
                hubRemoteConnected: true,
                lastReplyExecutionMode: "local_fallback_after_remote_error",
                lastRemoteFailureReasonCode: "hub_downgraded_to_local"
            )
        )

        #expect(intents.map(\.id) == ["awaiting_authorization", "hub_status"])
        #expect(intents[0].tone == .caution)
        #expect(intents[1].tone == .diagnostic)
        #expect(intents[1].helpText.contains("hub downgraded to local"))
    }
}
