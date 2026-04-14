import Foundation
import Testing
@testable import XTerminal

struct SupervisorEventLoopActionPresentationTests {

    @Test
    func requestDrivenActivitiesRouteToSkillRecord() throws {
        let activity = SupervisorManager.SupervisorEventLoopActivity(
            id: "evt-1",
            createdAt: 10,
            updatedAt: 20,
            triggerSource: "grant_resolution",
            status: "queued",
            reasonCode: "grant_pending",
            dedupeKey: "grant_resolution:req-123:grant_approved",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            triggerSummary: "grant approved",
            resultSummary: "",
            policySummary: ""
        )

        let action = try #require(SupervisorEventLoopActionPresentation.action(for: activity))
        let url = URL(string: action.url)
        let route = try #require(url.flatMap(XTDeepLinkParser.parse))

        #expect(action.label == "打开记录")
        #expect(action.requestId == "req-123")
        #expect(
            route == .project(
                XTDeepLinkProjectRoute(
                    projectId: "project-alpha",
                    pane: .chat,
                    openTarget: .supervisor,
                    focusTarget: .skillRecord,
                    requestId: "req-123",
                    grantRequestId: nil,
                    grantCapability: nil,
                    grantReason: nil,
                    resumeRequested: false
                )
            )
        )
    }

    @Test
    func projectScopedIncidentFallsBackToProject() throws {
        let activity = SupervisorManager.SupervisorEventLoopActivity(
            id: "evt-2",
            createdAt: 10,
            updatedAt: 20,
            triggerSource: "incident",
            status: "completed",
            reasonCode: "runtime_error",
            dedupeKey: "incident:lane-2:runtime_error",
            projectId: "project-beta",
            projectName: "Project Beta",
            triggerSummary: "runtime error handled",
            resultSummary: "recovered",
            policySummary: ""
        )

        let action = try #require(SupervisorEventLoopActionPresentation.action(for: activity))
        let url = URL(string: action.url)
        let route = try #require(url.flatMap(XTDeepLinkParser.parse))

        #expect(action.label == "打开项目")
        #expect(action.requestId == nil)
        #expect(
            route == .project(
                XTDeepLinkProjectRoute(
                    projectId: "project-beta",
                    pane: .chat,
                    openTarget: nil,
                    focusTarget: nil,
                    requestId: nil,
                    grantRequestId: nil,
                    grantCapability: nil,
                    grantReason: nil,
                    resumeRequested: false
                )
            )
        )
    }

    @Test
    func officialChannelFallsBackToSupervisor() throws {
        let activity = SupervisorManager.SupervisorEventLoopActivity(
            id: "evt-3",
            createdAt: 10,
            updatedAt: 20,
            triggerSource: "official_skills_channel",
            status: "completed",
            reasonCode: "ok",
            dedupeKey: "official_skills_channel:failed:healthy",
            projectId: "",
            projectName: "Official Skills Channel",
            triggerSummary: "status changed",
            resultSummary: "handled",
            policySummary: ""
        )

        let action = try #require(SupervisorEventLoopActionPresentation.action(for: activity))
        let url = URL(string: action.url)
        let route = try #require(url.flatMap(XTDeepLinkParser.parse))

        #expect(action.label == "打开 Supervisor")
        #expect(route == .supervisor(XTDeepLinkSupervisorRoute(
            projectId: nil,
            focusTarget: nil,
            requestId: nil,
            grantRequestId: nil,
            grantCapability: nil,
            grantReason: nil
        )))
    }

    @Test
    func uiReviewSafeNextActionPrefersProjectUIReviewRouteOverRecord() throws {
        let activity = SupervisorManager.SupervisorEventLoopActivity(
            id: "evt-4",
            createdAt: 10,
            updatedAt: 20,
            triggerSource: "skill_callback",
            status: "completed",
            reasonCode: "ok",
            dedupeKey: "skill_callback:req-456:completed:periodic_pulse",
            projectId: "project-gamma",
            projectName: "Project Gamma",
            triggerSummary: "Critical action missing",
            resultSummary: "",
            policySummary: "review=Periodic Pulse · next=open_ui_review"
        )

        let action = try #require(SupervisorEventLoopActionPresentation.action(for: activity))
        let url = URL(string: action.url)
        let route = try #require(url.flatMap(XTDeepLinkParser.parse))

        #expect(action.label == "打开 UI 审查")
        #expect(action.requestId == nil)
        #expect(
            route == .project(
                XTDeepLinkProjectRoute(
                    projectId: "project-gamma",
                    pane: .chat,
                    openTarget: nil,
                    focusTarget: nil,
                    requestId: nil,
                    grantRequestId: nil,
                    grantCapability: nil,
                    grantReason: nil,
                    resumeRequested: false,
                    governanceDestination: .uiReview
                )
            )
        )
    }

    @Test
    func hiddenProjectRecoveryIssueFallsBackToDiagnostics() throws {
        let activity = SupervisorManager.SupervisorEventLoopActivity(
            id: "evt-5",
            createdAt: 10,
            updatedAt: 20,
            triggerSource: "incident",
            status: "completed",
            reasonCode: "memory_scoped_hidden_project_recovery_missing",
            dedupeKey: "memory_assembly:hidden_project_scoped_recovery:abc123",
            projectId: "",
            projectName: "Memory Assembly",
            triggerSummary: "blocker_detected · 显式 hidden project 聚焦后，项目范围记忆没有补回。",
            resultSummary: "open diagnostics",
            policySummary: "review=Blocker Detected · next=open_diagnostics"
        )

        let action = try #require(SupervisorEventLoopActionPresentation.action(for: activity))

        #expect(action.label == "打开诊断")
        #expect(action.requestId == nil)
        #expect(action.url.contains("section_id=diagnostics"))
        #expect(action.url.contains("refresh_reason=supervisor_event_loop_hidden_project_scoped_recovery"))
    }

    @Test
    func heartbeatGrantRecoveryRoutesToGrantFocusWhenGrantMetadataIsPresent() throws {
        let activity = SupervisorManager.SupervisorEventLoopActivity(
            id: "evt-6",
            createdAt: 10,
            updatedAt: 20,
            triggerSource: "heartbeat",
            status: "completed",
            reasonCode: "grant_follow_up_required",
            dedupeKey: "heartbeat_recovery_follow_up:project-theta:request_grant_follow_up:grant_follow_up_required",
            projectId: "project-theta",
            projectName: "Project Theta",
            triggerSummary: "Project Theta 需要 grant / 授权跟进",
            resultSummary: "已为《Project Theta》排队 grant / 授权跟进。",
            policySummary: "cadence=active",
            grantRequestId: "grant-heartbeat-1",
            grantCapability: "ai.generate.paid"
        )

        let action = try #require(SupervisorEventLoopActionPresentation.action(for: activity))
        let url = URL(string: action.url)
        let route = try #require(url.flatMap(XTDeepLinkParser.parse))

        #expect(action.label == "打开授权")
        #expect(action.requestId == nil)
        #expect(
            route == .project(
                XTDeepLinkProjectRoute(
                    projectId: "project-theta",
                    pane: .chat,
                    openTarget: .supervisor,
                    focusTarget: .grant,
                    requestId: nil,
                    grantRequestId: "grant-heartbeat-1",
                    grantCapability: "ai.generate.paid",
                    grantReason: nil,
                    resumeRequested: false
                )
            )
        )
    }
}
