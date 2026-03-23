import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
@MainActor
struct SupervisorCalendarConversationCueTests {

    @Test
    func progressReportNaturallyAppendsMeetingCue() throws {
        let now = try #require(isoDate("2026-03-20T09:47:00+08:00"))
        let meeting = makeMeeting(
            id: "meeting-1",
            title: "Phoenix weekly sync",
            start: try #require(isoDate("2026-03-20T10:10:00+08:00")),
            end: try #require(isoDate("2026-03-20T10:40:00+08:00"))
        )
        defer { resetCalendarOverrides() }
        let manager = makeManager(now: now, meetings: [meeting])

        let reply = try #require(manager.directSupervisorReplyIfApplicableForTesting("说下现在进度"))

        #expect(reply.contains("⚠️ Hub Brief 暂不可用 · Calendar Cue Project"))
        #expect(reply.contains("按当前 fail-closed 规则，我先不在 XT 本地即兴拼接 Supervisor brief。"))
        #expect(reply.contains("哦，对了，23 分钟后你有一个Phoenix weekly sync的会议"))
    }

    @Test
    func fallbackStatusQueryAlsoUsesHubBriefFailClosedGuardAndKeepsMeetingCue() throws {
        let now = try #require(isoDate("2026-03-20T09:47:00+08:00"))
        let meeting = makeMeeting(
            id: "meeting-1b",
            title: "Phoenix staff",
            start: try #require(isoDate("2026-03-20T10:10:00+08:00")),
            end: try #require(isoDate("2026-03-20T10:40:00+08:00"))
        )
        defer { resetCalendarOverrides() }
        let manager = makeManager(now: now, meetings: [meeting])

        let reply = manager.fallbackSupervisorResponseForTesting("说下现在进度")

        #expect(reply.contains("⚠️ Hub Brief 暂不可用 · Calendar Cue Project"))
        #expect(reply.contains("按当前 fail-closed 规则，我先不在 XT 本地即兴拼接 Supervisor brief。"))
        #expect(reply.contains("哦，对了，23 分钟后你有一个Phoenix staff的会议"))
    }

    @Test
    func fallbackCasualConversationAlsoAppendsMeetingCue() throws {
        let now = try #require(isoDate("2026-03-20T09:47:00+08:00"))
        let meeting = makeMeeting(
            id: "meeting-2",
            title: "Design review",
            start: try #require(isoDate("2026-03-20T10:10:00+08:00")),
            end: try #require(isoDate("2026-03-20T10:40:00+08:00"))
        )
        defer { resetCalendarOverrides() }
        let manager = makeManager(now: now, meetings: [meeting])

        let reply = manager.fallbackSupervisorResponseForTesting("你最近怎么样")

        #expect(reply.contains("可以，现在由"))
        #expect(reply.contains("哦，对了，23 分钟后你有一个Design review的会议"))
    }

    @Test
    func conciseVoiceReplyKeepsMeetingCueLine() throws {
        let now = try #require(isoDate("2026-03-20T09:47:00+08:00"))
        let meeting = makeMeeting(
            id: "meeting-3",
            title: "Roadmap sync",
            start: try #require(isoDate("2026-03-20T10:10:00+08:00")),
            end: try #require(isoDate("2026-03-20T10:40:00+08:00"))
        )
        defer { resetCalendarOverrides() }
        let manager = makeManager(now: now, meetings: [meeting])
        let reply = try #require(manager.directSupervisorReplyIfApplicableForTesting("说下现在进度"))

        let script = manager.conciseVoiceReplyScriptForTesting(reply)

        #expect(script.count >= 2)
        #expect(script.contains { $0.contains("哦，对了，23 分钟后你有一个Roadmap sync的会议") })
    }

    @Test
    func finalizedGeneratedReplyAlsoAppendsMeetingCue() throws {
        let now = try #require(isoDate("2026-03-20T09:47:00+08:00"))
        let meeting = makeMeeting(
            id: "meeting-remote-1",
            title: "Remote sync",
            start: try #require(isoDate("2026-03-20T10:10:00+08:00")),
            end: try #require(isoDate("2026-03-20T10:40:00+08:00"))
        )
        defer { resetCalendarOverrides() }
        let manager = makeManager(now: now, meetings: [meeting])

        let reply = manager.finalizeSupervisorModelResponseForTesting(
            "主线这边我继续盯着，阻塞没有新的变化。",
            userMessage: "说下现在进度"
        )

        #expect(reply.contains("主线这边我继续盯着"))
        #expect(reply.contains("哦，对了，23 分钟后你有一个Remote sync的会议"))
    }

    @Test
    func finalizedGeneratedReplyDoesNotDuplicateExistingMeetingCue() throws {
        let now = try #require(isoDate("2026-03-20T09:47:00+08:00"))
        let meeting = makeMeeting(
            id: "meeting-remote-2",
            title: "Architecture review",
            start: try #require(isoDate("2026-03-20T10:10:00+08:00")),
            end: try #require(isoDate("2026-03-20T10:40:00+08:00"))
        )
        defer { resetCalendarOverrides() }
        let manager = makeManager(now: now, meetings: [meeting])
        let cueLine = "哦，对了，23 分钟后你有一个Architecture review的会议。你可以先准备一下，这里我来盯着。"

        let reply = manager.finalizeSupervisorModelResponseForTesting(
            """
这边进度正常，release 继续推进。

\(cueLine)
""",
            userMessage: "说下现在进度"
        )

        #expect(reply.components(separatedBy: "哦，对了，").count == 2)
        let followUp = manager.fallbackSupervisorResponseForTesting("你最近怎么样")
        #expect(followUp.contains("哦，对了，") == false)
    }

    @Test
    func relativeMeetingReminderRequestReschedulesCueToRequestedLeadWindow() throws {
        let now = try #require(isoDate("2026-03-20T09:47:00+08:00"))
        let meeting = makeMeeting(
            id: "meeting-5",
            title: "Weekly staff",
            start: try #require(isoDate("2026-03-20T10:10:00+08:00")),
            end: try #require(isoDate("2026-03-20T10:40:00+08:00"))
        )
        defer { resetCalendarOverrides() }
        let manager = makeManager(now: now, meetings: [meeting])

        let ack = try #require(
            manager.directSupervisorActionIfApplicableForTesting("你在开会前5分钟提醒我一下")
        )
        #expect(ack.contains("开始前 5 分钟提醒你"))

        manager.installSupervisorAfterTurnNowOverrideForTesting {
            now.addingTimeInterval(17 * 60)
        }
        let beforeWindow = manager.fallbackSupervisorResponseForTesting("你最近怎么样")
        #expect(beforeWindow.contains("哦，对了，") == false)

        manager.installSupervisorAfterTurnNowOverrideForTesting {
            now.addingTimeInterval(18 * 60)
        }
        let onWindow = manager.fallbackSupervisorResponseForTesting("你最近怎么样")
        #expect(onWindow.contains("哦，对了，5 分钟后你有一个Weekly staff的会议"))
    }

    @Test
    func startNowInterruptRequestMarksReminderForConversationBreakIn() throws {
        let now = try #require(isoDate("2026-03-20T09:47:00+08:00"))
        let meeting = makeMeeting(
            id: "meeting-6",
            title: "Launch room",
            start: try #require(isoDate("2026-03-20T10:10:00+08:00")),
            end: try #require(isoDate("2026-03-20T10:40:00+08:00"))
        )
        let stateStore = SupervisorCalendarReminderStateStore()
        defer { resetCalendarOverrides() }
        let manager = makeManager(
            now: now,
            meetings: [meeting],
            stateStore: stateStore
        )

        let ack = try #require(
            manager.directSupervisorActionIfApplicableForTesting("到点直接打断我")
        )
        #expect(ack.contains("一到点我就直接叫你"))

        let reminder = makeReminder(
            meeting: meeting,
            phase: .startNow,
            fireOffsetMinutes: 0,
            validUntilMinutes: 1
        )
        #expect(
            stateStore.shouldInterruptConversation(
                for: reminder,
                now: meeting.startDate
            ) == true
        )
    }

    @Test
    func snoozeRequestAcknowledgesAndDefersCueUntilDelayPasses() throws {
        let now = try #require(isoDate("2026-03-20T09:47:00+08:00"))
        let meeting = makeMeeting(
            id: "meeting-4",
            title: "Board prep",
            start: try #require(isoDate("2026-03-20T10:10:00+08:00")),
            end: try #require(isoDate("2026-03-20T10:40:00+08:00"))
        )
        defer { resetCalendarOverrides() }
        let manager = makeManager(now: now, meetings: [meeting])

        let ack = try #require(
            manager.directSupervisorActionIfApplicableForTesting("你等10分钟后再提醒我一下")
        )
        #expect(ack.contains("10 分钟后我再提醒你一次"))

        let duringSnooze = manager.fallbackSupervisorResponseForTesting("你最近怎么样")
        #expect(duringSnooze.contains("哦，对了，") == false)

        manager.installSupervisorAfterTurnNowOverrideForTesting {
            now.addingTimeInterval(11 * 60)
        }
        let resumed = manager.fallbackSupervisorResponseForTesting("你最近怎么样")
        #expect(resumed.contains("哦，对了，12 分钟后你有一个Board prep的会议"))
    }

    private func makeManager(
        now: Date,
        meetings: [XTCalendarEventSummary],
        stateStore: SupervisorCalendarReminderStateStore? = nil
    ) -> SupervisorManager {
        let manager = SupervisorManager.makeForTesting(
            supervisorCalendarReminderStateStore: stateStore ?? SupervisorCalendarReminderStateStore()
        )
        let appModel = AppModel()
        appModel.settingsStore.settings = enabledSettings()
        appModel.registry = sampleRegistry(now: now)
        appModel.selectedProjectId = "project-calendar-cue"
        manager.setAppModel(appModel)
        manager.installSupervisorAfterTurnNowOverrideForTesting { now }
        XTCalendarAccessController.shared.installAuthorizationStatusOverrideForTesting(.authorized)
        XTCalendarEventStore.shared.installUpcomingMeetingsOverrideForTesting(meetings)
        XTCalendarEventStore.shared.refreshUpcomingMeetings(now: now, lookaheadHours: 12)
        return manager
    }

    private func makeReminder(
        meeting: XTCalendarEventSummary,
        phase: SupervisorCalendarReminderPhase,
        fireOffsetMinutes: Int,
        validUntilMinutes: Int
    ) -> SupervisorCalendarReminder {
        SupervisorCalendarReminder(
            eventID: meeting.id,
            eventTitle: meeting.title,
            phase: phase,
            fireAt: meeting.startDate.addingTimeInterval(Double(fireOffsetMinutes) * 60.0).timeIntervalSince1970,
            validUntil: meeting.startDate.addingTimeInterval(Double(validUntilMinutes) * 60.0).timeIntervalSince1970,
            eventStartAt: meeting.startAt,
            dedupeKey: "\(meeting.id):\(Int64(round(meeting.startAt * 1000.0))):\(phase.rawValue)",
            notificationIdentifier: "x_terminal_supervisor_calendar_\(meeting.id)_\(phase.rawValue)"
        )
    }

    private func sampleRegistry(now: Date) -> AXProjectRegistry {
        AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: now.timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: true,
            lastSelectedProjectId: "project-calendar-cue",
            projects: [
                AXProjectEntry(
                    projectId: "project-calendar-cue",
                    rootPath: "/tmp/project-calendar-cue",
                    displayName: "Calendar Cue Project",
                    lastOpenedAt: now.timeIntervalSince1970,
                    manualOrderIndex: 0,
                    pinned: false,
                    statusDigest: "今天继续推进提醒体验",
                    currentStateSummary: "进行中",
                    nextStepSummary: "把自然提醒收口并验证",
                    blockerSummary: nil,
                    lastSummaryAt: now.timeIntervalSince1970 - 120,
                    lastEventAt: now.timeIntervalSince1970 - 60
                )
            ]
        )
    }

    private func resetCalendarOverrides() {
        XTCalendarEventStore.shared.installUpcomingMeetingsOverrideForTesting(nil)
        XTCalendarEventStore.shared.clearSnapshot()
        XTCalendarAccessController.shared.installAuthorizationStatusOverrideForTesting(nil)
    }

    private func enabledSettings() -> XTerminalSettings {
        XTerminalSettings.default().setting(
            supervisorCalendarReminders: SupervisorCalendarReminderPreferences(
                enabled: true,
                headsUpMinutes: 15,
                finalCallMinutes: 3,
                notificationFallbackEnabled: true
            )
        )
    }

    private func makeMeeting(
        id: String,
        title: String,
        start: Date,
        end: Date
    ) -> XTCalendarEventSummary {
        XTCalendarEventSummary(
            id: id,
            source: "eventkit",
            title: title,
            startAt: start.timeIntervalSince1970,
            endAt: end.timeIntervalSince1970,
            location: "Zoom",
            joinURL: "https://zoom.example.com/\(id)",
            isMeeting: true,
            isAllDay: false
        )
    }

    private func isoDate(_ raw: String) -> Date? {
        ISO8601DateFormatter().date(from: raw)
    }
}
