import Foundation

struct SupervisorPersonalReviewNoteRecord: Identifiable, Equatable, Codable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_personal_review_note.v1"

    var schemaVersion: String
    var reviewId: String
    var reviewType: SupervisorPersonalReviewType
    var reviewAnchor: String
    var scheduledAtMs: Int64
    var generatedAtMs: Int64
    var overdue: Bool
    var summary: String
    var recommendedActions: [String]
    var auditRef: String

    var id: String { reviewId }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case reviewId = "review_id"
        case reviewType = "review_type"
        case reviewAnchor = "review_anchor"
        case scheduledAtMs = "scheduled_at_ms"
        case generatedAtMs = "generated_at_ms"
        case overdue
        case summary
        case recommendedActions = "recommended_actions"
        case auditRef = "audit_ref"
    }

    func normalized() -> SupervisorPersonalReviewNoteRecord {
        let normalizedAnchor = normalizedPersonalReviewScalar(reviewAnchor)
        let normalizedID = normalizedPersonalReviewToken(
            reviewId,
            fallback: "personal_review:\(reviewType.rawValue):\(normalizedAnchor)"
        )
        let normalizedGeneratedAt = max(generatedAtMs, scheduledAtMs, 0)
        return SupervisorPersonalReviewNoteRecord(
            schemaVersion: Self.currentSchemaVersion,
            reviewId: normalizedID,
            reviewType: reviewType,
            reviewAnchor: normalizedAnchor,
            scheduledAtMs: max(0, scheduledAtMs),
            generatedAtMs: normalizedGeneratedAt,
            overdue: overdue,
            summary: normalizedPersonalReviewScalar(summary),
            recommendedActions: orderedUniquePersonalReviewScalars(recommendedActions),
            auditRef: normalizedPersonalReviewScalar(
                auditRef.isEmpty
                    ? "supervisor_personal_review:\(reviewType.rawValue):\(normalizedAnchor)"
                    : auditRef
            )
        )
    }
}

struct SupervisorPersonalReviewNoteSnapshot: Equatable, Codable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_personal_review_note_snapshot.v1"

    var schemaVersion: String
    var updatedAtMs: Int64
    var completionState: SupervisorPersonalReviewCompletionState
    var notes: [SupervisorPersonalReviewNoteRecord]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case updatedAtMs = "updated_at_ms"
        case completionState = "completion_state"
        case notes
    }

    static let empty = SupervisorPersonalReviewNoteSnapshot(
        schemaVersion: currentSchemaVersion,
        updatedAtMs: 0,
        completionState: .default(),
        notes: []
    )

    func normalized() -> SupervisorPersonalReviewNoteSnapshot {
        var seen = Set<String>()
        let normalizedNotes = notes
            .map { $0.normalized() }
            .filter { note in
                !note.summary.isEmpty && seen.insert(note.reviewId).inserted
            }
            .sorted { lhs, rhs in
                if lhs.generatedAtMs != rhs.generatedAtMs {
                    return lhs.generatedAtMs > rhs.generatedAtMs
                }
                return lhs.reviewId > rhs.reviewId
            }

        let updatedAt = max(
            max(0, updatedAtMs),
            normalizedNotes.map(\.generatedAtMs).max() ?? 0
        )

        return SupervisorPersonalReviewNoteSnapshot(
            schemaVersion: Self.currentSchemaVersion,
            updatedAtMs: updatedAt,
            completionState: completionState.normalized(),
            notes: normalizedNotes
        )
    }

    func upserting(_ note: SupervisorPersonalReviewNoteRecord, maxNotes: Int) -> SupervisorPersonalReviewNoteSnapshot {
        var next = normalized()
        let normalizedNote = note.normalized()
        if let index = next.notes.firstIndex(where: { $0.reviewId == normalizedNote.reviewId }) {
            next.notes[index] = normalizedNote
        } else {
            next.notes.append(normalizedNote)
        }
        next.notes.sort { lhs, rhs in
            if lhs.generatedAtMs != rhs.generatedAtMs {
                return lhs.generatedAtMs > rhs.generatedAtMs
            }
            return lhs.reviewId > rhs.reviewId
        }
        if next.notes.count > maxNotes {
            next.notes = Array(next.notes.prefix(maxNotes))
        }
        next.updatedAtMs = max(next.updatedAtMs, normalizedNote.generatedAtMs)
        return next.normalized()
    }

    func markingCompleted(
        type: SupervisorPersonalReviewType,
        anchor: String,
        completedAtMs: Int64
    ) -> SupervisorPersonalReviewNoteSnapshot {
        var next = normalized()
        next.completionState.lastCompletedAnchorByType[type.rawValue] = normalizedPersonalReviewScalar(anchor)
        next.updatedAtMs = max(next.updatedAtMs, completedAtMs, 0)
        return next.normalized()
    }
}

struct SupervisorPersonalReviewPreview: Equatable {
    var scheduleSummary: String
    var dueCount: Int
    var overdueCount: Int
    var statusLine: String
    var dueNotes: [SupervisorPersonalReviewNoteRecord]
    var recentNotes: [SupervisorPersonalReviewNoteRecord]
    var promptContext: String
}

enum SupervisorPersonalReviewNoteBuilder {
    private static let maxRecentNotes = 6

    static func preview(
        snapshot: SupervisorPersonalReviewNoteSnapshot,
        policy: SupervisorPersonalPolicy,
        personalMemory: SupervisorPersonalMemorySnapshot,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        locale: Locale = .current,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> SupervisorPersonalReviewPreview {
        let normalizedSnapshot = snapshot.normalized()
        let context = derivedContext(
            snapshot: normalizedSnapshot,
            policy: policy,
            personalMemory: personalMemory,
            now: now,
            timeZone: timeZone,
            locale: locale,
            calendar: calendar
        )
        let dueIDs = Set(context.dueNotes.map(\.reviewId))
        let recentNotes = normalizedSnapshot.notes
            .filter { !dueIDs.contains($0.reviewId) }
            .prefix(maxRecentNotes)
            .map { $0 }
        let overdueCount = context.dueNotes.filter(\.overdue).count
        let statusLine: String
        if context.dueNotes.isEmpty {
            statusLine = "No personal reviews are due right now. Schedule: \(context.scheduleSummary)."
        } else {
            let overdueLabel = overdueCount > 0 ? " · \(overdueCount) overdue" : ""
            statusLine = "\(context.dueNotes.count) personal reviews due\(overdueLabel) · \(context.scheduleSummary)"
        }

        return SupervisorPersonalReviewPreview(
            scheduleSummary: context.scheduleSummary,
            dueCount: context.dueNotes.count,
            overdueCount: overdueCount,
            statusLine: statusLine,
            dueNotes: context.dueNotes,
            recentNotes: recentNotes,
            promptContext: promptContext(
                scheduleSummary: context.scheduleSummary,
                dueNotes: context.dueNotes,
                recentNotes: recentNotes
            )
        )
    }

    static func refreshedSnapshot(
        snapshot: SupervisorPersonalReviewNoteSnapshot,
        policy: SupervisorPersonalPolicy,
        personalMemory: SupervisorPersonalMemorySnapshot,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        locale: Locale = .current,
        calendar: Calendar = Calendar(identifier: .gregorian),
        maxNotes: Int = 48
    ) -> SupervisorPersonalReviewNoteSnapshot {
        let normalizedSnapshot = snapshot.normalized()
        let context = derivedContext(
            snapshot: normalizedSnapshot,
            policy: policy,
            personalMemory: personalMemory,
            now: now,
            timeZone: timeZone,
            locale: locale,
            calendar: calendar
        )
        return context.dueNotes.reduce(normalizedSnapshot) { partial, note in
            partial.upserting(note, maxNotes: maxNotes)
        }
    }

    private struct DerivedContext {
        var scheduleSummary: String
        var dueNotes: [SupervisorPersonalReviewNoteRecord]
    }

    private static func derivedContext(
        snapshot: SupervisorPersonalReviewNoteSnapshot,
        policy: SupervisorPersonalPolicy,
        personalMemory: SupervisorPersonalMemorySnapshot,
        now: Date,
        timeZone: TimeZone,
        locale: Locale,
        calendar: Calendar
    ) -> DerivedContext {
        let dueItems = SupervisorPersonalReviewScheduler.dueItems(
            now: now,
            timeZone: timeZone,
            policy: policy,
            completionState: snapshot.completionState,
            calendar: calendar
        )
        let memorySummary = SupervisorPersonalMemorySummaryBuilder.build(
            snapshot: personalMemory,
            now: now,
            timeZone: timeZone,
            locale: locale
        )
        let followUpLedger = SupervisorFollowUpLedgerBuilder.build(
            from: personalMemory,
            now: now
        )
        let followUpSummary = SupervisorFollowUpLedgerBuilder.summary(
            from: followUpLedger,
            timeZone: timeZone,
            locale: locale
        )
        let reminderQueue = SupervisorReminderQueueBuilder.build(from: followUpLedger)

        let dueNotes = dueItems.map { item in
            buildNote(
                dueItem: item,
                policy: policy.normalized(),
                memorySummary: memorySummary,
                followUpSummary: followUpSummary,
                reminderQueue: reminderQueue,
                now: now,
                timeZone: timeZone,
                calendar: calendar
            )
        }

        return DerivedContext(
            scheduleSummary: SupervisorPersonalReviewScheduler.scheduleSummary(policy: policy),
            dueNotes: dueNotes
        )
    }

    private static func buildNote(
        dueItem: SupervisorPersonalReviewDueItem,
        policy: SupervisorPersonalPolicy,
        memorySummary: SupervisorPersonalMemorySummary,
        followUpSummary: SupervisorFollowUpLedgerSummary,
        reminderQueue: SupervisorReminderQueueSnapshot,
        now: Date,
        timeZone: TimeZone,
        calendar: Calendar
    ) -> SupervisorPersonalReviewNoteRecord {
        let anchor = SupervisorPersonalReviewScheduler.completionAnchor(
            for: dueItem.type,
            at: dueItem.scheduledAt,
            timeZone: timeZone,
            calendar: calendar
        )
        let summary = reviewSummary(
            type: dueItem.type,
            memorySummary: memorySummary,
            followUpSummary: followUpSummary
        )
        let recommendedActions = reviewActions(
            type: dueItem.type,
            policy: policy,
            memorySummary: memorySummary,
            followUpSummary: followUpSummary,
            reminderQueue: reminderQueue
        )

        return SupervisorPersonalReviewNoteRecord(
            schemaVersion: SupervisorPersonalReviewNoteRecord.currentSchemaVersion,
            reviewId: "personal_review:\(dueItem.type.rawValue):\(anchor)",
            reviewType: dueItem.type,
            reviewAnchor: anchor,
            scheduledAtMs: ms(dueItem.scheduledAt),
            generatedAtMs: ms(now),
            overdue: dueItem.overdue,
            summary: summary,
            recommendedActions: recommendedActions,
            auditRef: "supervisor_personal_review:\(dueItem.type.rawValue):\(anchor)"
        ).normalized()
    }

    private static func reviewSummary(
        type: SupervisorPersonalReviewType,
        memorySummary: SupervisorPersonalMemorySummary,
        followUpSummary: SupervisorFollowUpLedgerSummary
    ) -> String {
        switch type {
        case .morningBrief:
            let parts = [
                followUpSummary.overdueCount > 0 ? "\(followUpSummary.overdueCount) overdue follow-ups" : nil,
                followUpSummary.dueSoonCount > 0 ? "\(followUpSummary.dueSoonCount) due soon" : nil,
                memorySummary.activeCommitmentCount > 0 ? "\(memorySummary.activeCommitmentCount) open commitments" : nil,
                followUpSummary.peopleWaitingCount > 0 ? "\(followUpSummary.peopleWaitingCount) people waiting" : nil
            ].compactMap { $0 }
            if parts.isEmpty {
                return "Start the day with a quick priority reset and protect the first focus block."
            }
            return "Start the day with \(parts.joined(separator: ", "))."
        case .eveningWrapUp:
            let parts = [
                followUpSummary.overdueCount > 0 ? "\(followUpSummary.overdueCount) overdue follow-ups still open" : nil,
                followUpSummary.openCount > 0 ? "\(followUpSummary.openCount) follow-ups still queued" : nil,
                memorySummary.activeCommitmentCount > 0 ? "\(memorySummary.activeCommitmentCount) active commitments to reset" : nil
            ].compactMap { $0 }
            if parts.isEmpty {
                return "Wrap the day by clearing loose ends and naming tomorrow's first move."
            }
            return "Close the day with \(parts.joined(separator: ", "))."
        case .weeklyReview:
            let parts = [
                followUpSummary.overdueCount > 0 ? "\(followUpSummary.overdueCount) overdue follow-ups" : nil,
                followUpSummary.peopleWaitingCount > 0 ? "\(followUpSummary.peopleWaitingCount) people waiting" : nil,
                memorySummary.activeCommitmentCount > 0 ? "\(memorySummary.activeCommitmentCount) commitments to re-rank" : nil
            ].compactMap { $0 }
            if parts.isEmpty {
                return "Use the weekly review to reset commitments, follow-through, and next week's operating rhythm."
            }
            return "Reset the coming week around \(parts.joined(separator: ", "))."
        }
    }

    private static func reviewActions(
        type: SupervisorPersonalReviewType,
        policy: SupervisorPersonalPolicy,
        memorySummary: SupervisorPersonalMemorySummary,
        followUpSummary: SupervisorFollowUpLedgerSummary,
        reminderQueue: SupervisorReminderQueueSnapshot
    ) -> [String] {
        let reminderActions = reminderQueue.items.map(\.recommendedNextAction)
        var actions: [String] = []
        let targetCount: Int
        switch policy.briefingStyle {
        case .concise:
            targetCount = 2
        case .balanced:
            targetCount = 3
        case .proactive:
            targetCount = 4
        }

        actions.append(contentsOf: reminderActions.prefix(type == .weeklyReview ? 3 : 2))

        switch type {
        case .morningBrief:
            if memorySummary.activeCommitmentCount > 0 {
                actions.append("Pick the one commitment that must visibly move before noon.")
            }
            actions.append("Protect the first focused block before personal admin starts expanding.")
        case .eveningWrapUp:
            actions.append("Either close or explicitly reschedule the riskiest personal open loop before wrap-up.")
            actions.append("Name tomorrow's first personal follow-up so the morning starts clean.")
        case .weeklyReview:
            actions.append("Choose the stalest commitment and either clear it or renegotiate it this week.")
            actions.append("Re-rank the people and obligations that most affect next week's focus.")
        }

        if followUpSummary.peopleWaitingCount > 0 {
            let waiting = followUpSummary.waitingPeople.prefix(2).joined(separator: ", ")
            actions.append("Decide who should hear from you first: \(waiting).")
        }
        if followUpSummary.overdueCount == 0 && reminderActions.isEmpty {
            actions.append("Do a quick scan for silent drift before assuming everything is clear.")
        }

        return Array(orderedUniquePersonalReviewScalars(actions).prefix(targetCount))
    }

    private static func promptContext(
        scheduleSummary: String,
        dueNotes: [SupervisorPersonalReviewNoteRecord],
        recentNotes: [SupervisorPersonalReviewNoteRecord]
    ) -> String {
        var lines: [String] = []
        lines.append("- Personal review schedule: \(scheduleSummary)")
        if dueNotes.isEmpty {
            lines.append("- No personal reviews are currently due.")
        } else {
            let dueSummary = dueNotes.prefix(3).map { note in
                let dueState = note.overdue ? "overdue" : "due"
                let actions = note.recommendedActions.prefix(2).joined(separator: " | ")
                if actions.isEmpty {
                    return "\(note.reviewType.displayName) (\(dueState)): \(note.summary)"
                }
                return "\(note.reviewType.displayName) (\(dueState)): \(note.summary) Actions: \(actions)"
            }.joined(separator: " || ")
            lines.append("- Due personal reviews: \(dueSummary)")
        }
        if !recentNotes.isEmpty {
            let recentSummary = recentNotes.prefix(2).map { note in
                "\(note.reviewType.displayName): \(note.summary)"
            }.joined(separator: " | ")
            lines.append("- Recent personal review notes: \(recentSummary)")
        }
        return lines.joined(separator: "\n")
    }

    private static func ms(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000.0).rounded())
    }
}

@MainActor
final class SupervisorPersonalReviewNoteStore: ObservableObject {
    static let shared = SupervisorPersonalReviewNoteStore()

    @Published private(set) var snapshot: SupervisorPersonalReviewNoteSnapshot

    private let url: URL
    private let maxNotes = 48

    init(
        url: URL? = nil,
        seededSnapshot: SupervisorPersonalReviewNoteSnapshot? = nil
    ) {
        let fm = FileManager.default
        let resolvedURL: URL = {
            if let url { return url }
            let supportBase = fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
            let base = supportBase.appendingPathComponent("X-Terminal", isDirectory: true)
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
            return base.appendingPathComponent("supervisor_personal_reviews.json")
        }()
        self.url = resolvedURL

        if let seededSnapshot {
            snapshot = seededSnapshot.normalized()
        } else if let data = try? Data(contentsOf: resolvedURL),
                  let decoded = try? JSONDecoder().decode(SupervisorPersonalReviewNoteSnapshot.self, from: data) {
            snapshot = decoded.normalized()
        } else {
            snapshot = .empty
        }
    }

    func preview(
        policy: SupervisorPersonalPolicy,
        personalMemory: SupervisorPersonalMemorySnapshot,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        locale: Locale = .current,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> SupervisorPersonalReviewPreview {
        SupervisorPersonalReviewNoteBuilder.preview(
            snapshot: snapshot,
            policy: policy,
            personalMemory: personalMemory,
            now: now,
            timeZone: timeZone,
            locale: locale,
            calendar: calendar
        )
    }

    func syncDerivedNotes(
        policy: SupervisorPersonalPolicy,
        personalMemory: SupervisorPersonalMemorySnapshot,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        locale: Locale = .current,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        snapshot = SupervisorPersonalReviewNoteBuilder.refreshedSnapshot(
            snapshot: snapshot,
            policy: policy,
            personalMemory: personalMemory,
            now: now,
            timeZone: timeZone,
            locale: locale,
            calendar: calendar,
            maxNotes: maxNotes
        )
        persist()
    }

    func markCompleted(
        type: SupervisorPersonalReviewType,
        at date: Date = Date(),
        timeZone: TimeZone = .current,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        let anchor = SupervisorPersonalReviewScheduler.completionAnchor(
            for: type,
            at: date,
            timeZone: timeZone,
            calendar: calendar
        )
        snapshot = snapshot.markingCompleted(
            type: type,
            anchor: anchor,
            completedAtMs: Int64((date.timeIntervalSince1970 * 1000.0).rounded())
        )
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot.normalized()) else { return }
        try? SupervisorStoreWriteSupport.writeSnapshotData(data, to: url)
    }
}

private func normalizedPersonalReviewScalar(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func normalizedPersonalReviewToken(_ value: String, fallback: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
}

private func orderedUniquePersonalReviewScalars(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var output: [String] = []
    for value in values {
        let normalized = normalizedPersonalReviewScalar(value)
        guard !normalized.isEmpty else { continue }
        let key = normalized.lowercased()
        guard seen.insert(key).inserted else { continue }
        output.append(normalized)
    }
    return output
}
