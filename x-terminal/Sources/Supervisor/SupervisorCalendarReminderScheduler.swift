import Combine
import Foundation

enum SupervisorCalendarReminderPhase: String, Codable, CaseIterable, Equatable, Sendable {
    case headsUp = "heads_up"
    case finalCall = "final_call"
    case startNow = "start_now"
}

struct SupervisorCalendarReminder: Codable, Equatable, Sendable {
    static let schemaVersion = "xt.supervisor_calendar_reminder.v1"

    var schemaVersion: String = SupervisorCalendarReminder.schemaVersion
    var eventID: String
    var eventTitle: String
    var phase: SupervisorCalendarReminderPhase
    var fireAt: TimeInterval
    var validUntil: TimeInterval
    var eventStartAt: TimeInterval
    var dedupeKey: String
    var notificationIdentifier: String

    var fireDate: Date {
        Date(timeIntervalSince1970: fireAt)
    }

    var validUntilDate: Date {
        Date(timeIntervalSince1970: validUntil)
    }

    var eventStartDate: Date {
        Date(timeIntervalSince1970: eventStartAt)
    }
}

struct SupervisorCalendarReminderLedger: Codable, Equatable, Sendable {
    static let schemaVersion = "xt.supervisor_calendar_reminder_ledger.v1"
    private static let retentionWindow: TimeInterval = 14 * 24 * 60 * 60

    var schemaVersion: String
    var deliveredAtByDedupeKey: [String: TimeInterval]

    static func `default`() -> SupervisorCalendarReminderLedger {
        SupervisorCalendarReminderLedger(
            schemaVersion: schemaVersion,
            deliveredAtByDedupeKey: [:]
        )
    }

    func normalized(now: Date = Date()) -> SupervisorCalendarReminderLedger {
        let cutoff = now.timeIntervalSince1970 - Self.retentionWindow
        return SupervisorCalendarReminderLedger(
            schemaVersion: schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? Self.schemaVersion
                : schemaVersion,
            deliveredAtByDedupeKey: deliveredAtByDedupeKey.filter { $0.value >= cutoff }
        )
    }

    func contains(_ dedupeKey: String) -> Bool {
        normalized().deliveredAtByDedupeKey[dedupeKey] != nil
    }

    func recording(
        _ reminder: SupervisorCalendarReminder,
        at now: Date
    ) -> SupervisorCalendarReminderLedger {
        var next = normalized(now: now)
        next.deliveredAtByDedupeKey[reminder.dedupeKey] = now.timeIntervalSince1970
        return next
    }
}

enum SupervisorCalendarReminderLedgerStore {
    private static let defaultsKey = "xterminal_supervisor_calendar_reminder_ledger_v1"

    static func load(
        userDefaults: UserDefaults = .standard
    ) -> SupervisorCalendarReminderLedger {
        guard let data = userDefaults.data(forKey: defaultsKey),
              let ledger = try? JSONDecoder().decode(
                SupervisorCalendarReminderLedger.self,
                from: data
              ) else {
            return .default()
        }
        return ledger.normalized()
    }

    static func save(
        _ ledger: SupervisorCalendarReminderLedger,
        userDefaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(ledger.normalized()) else {
            return
        }
        userDefaults.set(data, forKey: defaultsKey)
    }
}

@MainActor
final class SupervisorCalendarReminderScheduler: ObservableObject {
    @Published private(set) var statusLine: String = "Calendar reminders are off"
    @Published private(set) var lastRunAt: TimeInterval = 0

    private let accessController: XTCalendarAccessController
    private let eventStore: XTCalendarEventStore
    private let voiceBridge: SupervisorCalendarVoiceBridge
    private let reminderStateStore: SupervisorCalendarReminderStateStore
    private let nowProvider: () -> Date
    private let lookaheadHours: Int
    private let tickInterval: TimeInterval
    private var settingsStore: SettingsStore?
    private var settingsSubscription: AnyCancellable?
    private var ticker: Timer?
    private var ledger: SupervisorCalendarReminderLedger

    init(
        accessController: XTCalendarAccessController? = nil,
        eventStore: XTCalendarEventStore? = nil,
        voiceBridge: SupervisorCalendarVoiceBridge? = nil,
        reminderStateStore: SupervisorCalendarReminderStateStore? = nil,
        nowProvider: @escaping () -> Date = Date.init,
        lookaheadHours: Int = 12,
        tickInterval: TimeInterval = 30,
        ledger: SupervisorCalendarReminderLedger? = nil
    ) {
        self.accessController = accessController ?? .shared
        self.eventStore = eventStore ?? .shared
        self.voiceBridge = voiceBridge ?? .live()
        self.reminderStateStore = reminderStateStore ?? .shared
        self.nowProvider = nowProvider
        self.lookaheadHours = max(2, lookaheadHours)
        self.tickInterval = max(15, tickInterval)
        self.ledger = (ledger ?? SupervisorCalendarReminderLedgerStore.load()).normalized()
    }

    deinit {
        ticker?.invalidate()
        settingsSubscription?.cancel()
    }

    static var shouldAutoStartInCurrentProcess: Bool {
        if ProcessInfo.processInfo.isRunningUnderAutomatedTests {
            return false
        }
        return ProcessInfo.processInfo.environment["XTERMINAL_ENABLE_STARTUP_CALENDAR_REMINDERS"] == "1"
    }

    func bind(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        settingsSubscription?.cancel()
        settingsSubscription = settingsStore.$settings
            .sink { [weak self] settings in
                self?.handleSettingsUpdate(settings)
            }
        handleSettingsUpdate(settingsStore.settings)
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        settingsSubscription?.cancel()
        settingsSubscription = nil
        statusLine = "Calendar reminders are off"
    }

    func refresh(now: Date? = nil) {
        guard let settingsStore else {
            statusLine = "Calendar reminder scheduler is not bound"
            return
        }
        evaluate(settings: settingsStore.settings, now: now ?? nowProvider())
    }

    private func handleSettingsUpdate(_ settings: XTerminalSettings) {
        let preferences = settings.supervisorCalendarReminders.normalized()
        guard preferences.enabled else {
            ticker?.invalidate()
            ticker = nil
            eventStore.clearSnapshot()
            statusLine = "Calendar reminders are off"
            return
        }

        startTickerIfNeeded()
        evaluate(settings: settings, now: nowProvider())
    }

    private func evaluate(settings: XTerminalSettings, now: Date) {
        lastRunAt = now.timeIntervalSince1970
        ledger = ledger.normalized(now: now)
        let preferences = settings.supervisorCalendarReminders.normalized()

        guard preferences.enabled else {
            eventStore.clearSnapshot()
            statusLine = "Calendar reminders are off"
            return
        }

        accessController.refreshAuthorizationStatus()
        guard accessController.authorizationStatus.canReadEvents else {
            eventStore.clearSnapshot(reason: accessController.authorizationStatus.guidanceText)
            statusLine = accessController.authorizationStatus.guidanceText
            return
        }

        eventStore.refreshUpcomingMeetings(now: now, lookaheadHours: lookaheadHours)
        let deliveredDedupeKeys = Set(ledger.deliveredAtByDedupeKey.keys)
        let reminders = Self.dueReminders(
            now: now,
            upcomingMeetings: eventStore.upcomingMeetings,
            preferences: preferences,
            deliveredDedupeKeys: deliveredDedupeKeys
        ).filter { reminder in
            !reminderStateStore.suppressesReminderDelivery(for: reminder, now: now)
        }

        guard !reminders.isEmpty else {
            if reminderStateStore.pendingInlineCueCount > 0 {
                statusLine = "Calendar reminder queued for the next conversation turn"
                return
            }
            statusLine = eventStore.statusLine
            return
        }

        var deliveredCount = 0
        for reminder in reminders {
            let outcome = voiceBridge.deliver(
                reminder: reminder,
                settings: settings,
                now: now
            )
            if outcome.recordsDelivery {
                ledger = ledger.recording(reminder, at: now)
                deliveredCount += 1
            }
        }

        if deliveredCount > 0 {
            SupervisorCalendarReminderLedgerStore.save(ledger)
            statusLine = "Delivered \(deliveredCount) calendar reminder(s)"
        } else if reminderStateStore.pendingInlineCueCount > 0 {
            statusLine = "Calendar reminder queued for the next conversation turn"
        } else {
            statusLine = "Calendar reminder waiting for safe delivery"
        }
    }

    private func startTickerIfNeeded() {
        guard ticker == nil else { return }
        let timer = Timer(
            timeInterval: tickInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        ticker = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    nonisolated static func dueReminders(
        now: Date,
        upcomingMeetings: [XTCalendarEventSummary],
        preferences: SupervisorCalendarReminderPreferences,
        deliveredDedupeKeys: Set<String>
    ) -> [SupervisorCalendarReminder] {
        let normalizedPreferences = preferences.normalized()
        return upcomingMeetings
            .filter { meeting in
                meeting.isMeeting && !meeting.isAllDay && meeting.endDate > now
            }
            .flatMap { meeting in
                reminderCandidates(for: meeting, preferences: normalizedPreferences)
            }
            .filter { reminder in
                now >= reminder.fireDate &&
                    now < reminder.validUntilDate &&
                    !deliveredDedupeKeys.contains(reminder.dedupeKey)
            }
            .sorted { lhs, rhs in
                if lhs.fireAt == rhs.fireAt {
                    return lhs.dedupeKey < rhs.dedupeKey
                }
                return lhs.fireAt < rhs.fireAt
            }
    }

    private nonisolated static func reminderCandidates(
        for meeting: XTCalendarEventSummary,
        preferences: SupervisorCalendarReminderPreferences
    ) -> [SupervisorCalendarReminder] {
        let start = meeting.startDate
        let end = max(meeting.endDate.timeIntervalSince1970, start.addingTimeInterval(60).timeIntervalSince1970)
        let headsUpFireAt = start.addingTimeInterval(-Double(preferences.headsUpMinutes) * 60.0)
        let finalCallFireAt = start.addingTimeInterval(-Double(preferences.finalCallMinutes) * 60.0)
        let startNowValidUntil = min(end, start.addingTimeInterval(60).timeIntervalSince1970)

        return [
            buildReminder(
                meeting: meeting,
                phase: .headsUp,
                fireDate: headsUpFireAt,
                validUntil: finalCallFireAt
            ),
            buildReminder(
                meeting: meeting,
                phase: .finalCall,
                fireDate: finalCallFireAt,
                validUntil: start
            ),
            buildReminder(
                meeting: meeting,
                phase: .startNow,
                fireDate: start,
                validUntil: Date(timeIntervalSince1970: startNowValidUntil)
            ),
        ].compactMap { $0 }
    }

    private nonisolated static func buildReminder(
        meeting: XTCalendarEventSummary,
        phase: SupervisorCalendarReminderPhase,
        fireDate: Date,
        validUntil: Date
    ) -> SupervisorCalendarReminder? {
        guard validUntil > fireDate else { return nil }
        let normalizedStartAtMs = Int64(round(meeting.startAt * 1000.0))
        let dedupeKey = "\(meeting.id):\(normalizedStartAtMs):\(phase.rawValue)"
        let notificationIdentifier = "x_terminal_supervisor_calendar_\(sanitizedIdentifierFragment(dedupeKey))"
        return SupervisorCalendarReminder(
            eventID: meeting.id,
            eventTitle: meeting.title,
            phase: phase,
            fireAt: fireDate.timeIntervalSince1970,
            validUntil: validUntil.timeIntervalSince1970,
            eventStartAt: meeting.startAt,
            dedupeKey: dedupeKey,
            notificationIdentifier: notificationIdentifier
        )
    }

    private nonisolated static func sanitizedIdentifierFragment(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = raw.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let sanitized = String(scalars)
        if sanitized.count <= 96 {
            return sanitized
        }
        let idx = sanitized.index(sanitized.startIndex, offsetBy: 96)
        return String(sanitized[..<idx])
    }
}
