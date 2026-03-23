import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct XTUnifiedDoctorCalendarReminderReadinessTests {
    @Test
    func reportsXtOwnedCalendarLineAsReadyWhenReminderToggleIsOffByChoice() {
        let report = XTUnifiedDoctorBuilder.build(
            input: makeCalendarDoctorInput(
                calendarSnapshot: XTUnifiedDoctorCalendarReminderSnapshot(
                    enabled: false,
                    headsUpMinutes: 15,
                    finalCallMinutes: 3,
                    notificationFallbackEnabled: true,
                    authorizationStatus: .notDetermined,
                    authorizationGuidanceText: XTCalendarAuthorizationStatus.notDetermined.guidanceText,
                    schedulerStatusLine: "Calendar reminders are off",
                    schedulerLastRunAtMs: 0,
                    eventStoreStatusLine: "Calendar reminders are off",
                    eventStoreLastRefreshedAtMs: 0,
                    upcomingMeetingCount: 0,
                    upcomingMeetingPreviewLines: []
                )
            )
        )

        let section = report.section(.calendarReminderReadiness)
        #expect(section?.state == .ready)
        #expect(section?.headline == "XT 自管的日历提醒当前按你的设置保持关闭")
        #expect(section?.summary.contains("Hub 已不再请求 Calendar 权限") == true)
        #expect(section?.detailLines.contains("calendar_permission_owner=xt_device_local") == true)
        #expect(section?.detailLines.contains("calendar_reminders_enabled=false") == true)
        #expect(report.readyForFirstTask == true)
    }

    @Test
    func reportsPermissionDeniedWhenXtCannotReadCalendarEvents() {
        let report = XTUnifiedDoctorBuilder.build(
            input: makeCalendarDoctorInput(
                calendarSnapshot: XTUnifiedDoctorCalendarReminderSnapshot(
                    enabled: true,
                    headsUpMinutes: 15,
                    finalCallMinutes: 3,
                    notificationFallbackEnabled: true,
                    authorizationStatus: .denied,
                    authorizationGuidanceText: XTCalendarAuthorizationStatus.denied.guidanceText,
                    schedulerStatusLine: "Calendar access is denied",
                    schedulerLastRunAtMs: 1_741_300_000_000,
                    eventStoreStatusLine: XTCalendarAuthorizationStatus.denied.guidanceText,
                    eventStoreLastRefreshedAtMs: 0,
                    upcomingMeetingCount: 0,
                    upcomingMeetingPreviewLines: []
                )
            )
        )

        let section = report.section(.calendarReminderReadiness)
        #expect(section?.state == .permissionDenied)
        #expect(section?.repairEntry == .systemPermissions)
        #expect(section?.summary.contains("Calendar access is denied") == true)
        #expect(section?.detailLines.contains("calendar_authorization=denied") == true)
        #expect(section?.detailLines.contains("calendar_authorization_can_read=false") == true)
    }

    @Test
    func reportsReadyWhenXtHasAuthorizedMeetingsAndSchedulerSnapshot() {
        let report = XTUnifiedDoctorBuilder.build(
            input: makeCalendarDoctorInput(
                calendarSnapshot: XTUnifiedDoctorCalendarReminderSnapshot(
                    enabled: true,
                    headsUpMinutes: 15,
                    finalCallMinutes: 3,
                    notificationFallbackEnabled: true,
                    authorizationStatus: .authorized,
                    authorizationGuidanceText: XTCalendarAuthorizationStatus.authorized.guidanceText,
                    schedulerStatusLine: "Delivered 1 calendar reminder(s)",
                    schedulerLastRunAtMs: 1_741_300_000_000,
                    eventStoreStatusLine: "2 upcoming meetings in the next 12h",
                    eventStoreLastRefreshedAtMs: 1_741_299_940_000,
                    upcomingMeetingCount: 2,
                    upcomingMeetingPreviewLines: [
                        "Phoenix weekly sync | 15m",
                        "Board prep | 42m"
                    ]
                )
            )
        )

        let section = report.section(.calendarReminderReadiness)
        #expect(section?.state == .ready)
        #expect(section?.headline == "XT 日历提醒已就绪，并拿到了本地会议快照")
        #expect(section?.detailLines.contains("calendar_upcoming_meeting_count=2") == true)
        #expect(section?.detailLines.contains("calendar_meeting_1=Phoenix weekly sync | 15m") == true)
        #expect(section?.detailLines.contains("hub_calendar_permission=request_blocked") == true)
        #expect(report.readyForFirstTask == true)
    }
}

private func makeCalendarDoctorInput(
    calendarSnapshot: XTUnifiedDoctorCalendarReminderSnapshot
) -> XTUnifiedDoctorInput {
    let model = HubModel(
        id: "hub.model.coder",
        name: "hub.model.coder",
        backend: "mlx",
        quant: "4bit",
        contextLength: 32768,
        paramsB: 7.0,
        roles: ["coder"],
        state: .loaded,
        memoryBytes: 1_024,
        tokensPerSec: 42,
        modelPath: "/models/hub.model.coder",
        note: nil
    )

    return XTUnifiedDoctorInput(
        generatedAt: Date(timeIntervalSince1970: 1_741_300_000),
        localConnected: true,
        remoteConnected: false,
        remoteRoute: .none,
        linking: false,
        pairingPort: 50052,
        grpcPort: 50051,
        internetHost: "10.0.0.8",
        configuredModelIDs: [model.id],
        totalModelRoles: AXRole.allCases.count,
        failureCode: "",
        runtime: .empty,
        runtimeStatus: AIRuntimeStatus(
            pid: 42,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: true,
            runtimeVersion: "test-runtime",
            importError: nil,
            activeMemoryBytes: nil,
            peakMemoryBytes: nil,
            loadedModelCount: 1
        ),
        modelsState: ModelStateSnapshot(
            models: [model],
            updatedAt: Date().timeIntervalSince1970
        ),
        bridgeAlive: true,
        bridgeEnabled: true,
        bridgeLastError: "",
        sessionID: nil,
        sessionTitle: nil,
        sessionRuntime: nil,
        voiceRouteDecision: .unavailable,
        voiceRuntimeState: .idle,
        voiceAuthorizationStatus: .undetermined,
        voicePermissionSnapshot: .unknown,
        voiceActiveHealthReasonCode: "",
        voiceSidecarHealth: nil,
        wakeProfileSnapshot: .empty,
        conversationSession: .idle(
            policy: .default(),
            wakeMode: .pushToTalk,
            route: .manualText
        ),
        voicePreferences: .default(),
        calendarReminderSnapshot: calendarSnapshot,
        skillsSnapshot: AXSkillsDoctorSnapshot(
            hubIndexAvailable: true,
            installedSkillCount: 0,
            compatibleSkillCount: 0,
            partialCompatibilityCount: 0,
            revokedMatchCount: 0,
            trustEnabledPublisherCount: 1,
            projectIndexEntries: [],
            globalIndexEntries: [],
            conflictWarnings: [],
            installedSkills: [],
            statusKind: .supported,
            statusLine: "skills 0/0",
            compatibilityExplain: "skills compatibility ready"
        ),
        reportPath: "/tmp/xt_unified_doctor_report.json",
        modelRouteDiagnostics: .empty,
        projectContextDiagnostics: .empty
    )
}
