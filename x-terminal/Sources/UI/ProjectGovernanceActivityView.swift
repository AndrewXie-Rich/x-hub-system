import Foundation
import SwiftUI

struct ProjectGovernanceActivityPresentation: Equatable {
    struct ReviewSummary: Equatable, Identifiable {
        var reviewID: String
        var createdAtText: String
        var triggerText: String
        var reviewLevelText: String
        var verdictText: String
        var deliveryModeText: String
        var ackText: String
        var effectiveSupervisorTierText: String
        var workOrderDepthText: String
        var projectAIStrengthText: String
        var workOrderRef: String
        var summary: String
        var anchorGoal: String
        var anchorDoneDefinition: String
        var anchorConstraintsText: String
        var currentState: String
        var nextStep: String
        var blocker: String
        var recommendedActions: [String]
        var auditRef: String

        var id: String { reviewID }
    }

    struct GuidanceSummary: Equatable, Identifiable {
        var injectionID: String
        var reviewID: String
        var injectedAtText: String
        var deliveryModeText: String
        var interventionText: String
        var safePointText: String
        var lifecycleText: String
        var ackText: String
        var ackStatus: SupervisorGuidanceAckStatus
        var ackRequired: Bool
        var effectiveSupervisorTierText: String
        var workOrderDepthText: String
        var workOrderRef: String
        var guidanceText: String
        var ackUpdatedAtText: String
        var ackNote: String
        var auditRef: String

        var id: String { injectionID }
    }

    struct ScheduleSummary: Equatable {
        var lastHeartbeatText: String
        var nextHeartbeatText: String
        var lastPulseReviewText: String
        var nextPulseReviewText: String
        var lastBrainstormReviewText: String
        var nextBrainstormReviewText: String
    }

    var reviewCount: Int
    var guidanceCount: Int
    var pendingAckCount: Int
    var followUpRhythmSummary: String
    var latestReview: ReviewSummary?
    var recentReviews: [ReviewSummary]
    var pendingGuidance: GuidanceSummary?
    var latestGuidance: GuidanceSummary?
    var recentGuidance: [GuidanceSummary]
    var schedule: ScheduleSummary

    init(
        reviewNotes: SupervisorReviewNoteSnapshot,
        guidance: SupervisorGuidanceInjectionSnapshot,
        scheduleState: SupervisorReviewScheduleState,
        resolvedGovernance: AXProjectResolvedGovernanceState? = nil,
        now: Date = Date()
    ) {
        let nowMs = Int64(now.timeIntervalSince1970 * 1000.0)
        reviewCount = reviewNotes.notes.count
        guidanceCount = guidance.items.count
        let actionableGuidance = SupervisorGuidanceInjectionStore.actionableItems(
            from: guidance.items,
            nowMs: nowMs
        )
        pendingAckCount = actionableGuidance.count
        followUpRhythmSummary = resolvedGovernance.map {
            SupervisorReviewPolicyEngine.eventFollowUpCadenceLabel(governance: $0)
        } ?? "(none)"

        recentReviews = reviewNotes.notes.prefix(5).map {
            Self.makeReviewSummary($0, nowMs: nowMs)
        }
        latestReview = recentReviews.first

        pendingGuidance = actionableGuidance.first.map {
            Self.makeGuidanceSummary($0, nowMs: nowMs)
        }
        recentGuidance = guidance.items.prefix(5).map {
            Self.makeGuidanceSummary($0, nowMs: nowMs)
        }
        latestGuidance = recentGuidance.first

        schedule = ScheduleSummary(
            lastHeartbeatText: Self.timestampText(ms: scheduleState.lastHeartbeatAtMs, nowMs: nowMs),
            nextHeartbeatText: Self.timestampText(ms: scheduleState.nextHeartbeatDueAtMs, nowMs: nowMs),
            lastPulseReviewText: Self.timestampText(ms: scheduleState.lastPulseReviewAtMs, nowMs: nowMs),
            nextPulseReviewText: Self.timestampText(ms: scheduleState.nextPulseReviewDueAtMs, nowMs: nowMs),
            lastBrainstormReviewText: Self.timestampText(ms: scheduleState.lastBrainstormReviewAtMs, nowMs: nowMs),
            nextBrainstormReviewText: Self.timestampText(ms: scheduleState.nextBrainstormReviewDueAtMs, nowMs: nowMs)
        )
    }

    static let empty = ProjectGovernanceActivityPresentation(
        reviewNotes: SupervisorReviewNoteSnapshot(
            schemaVersion: SupervisorReviewNoteSnapshot.currentSchemaVersion,
            updatedAtMs: 0,
            notes: []
        ),
        guidance: SupervisorGuidanceInjectionSnapshot(
            schemaVersion: SupervisorGuidanceInjectionSnapshot.currentSchemaVersion,
            updatedAtMs: 0,
            items: []
        ),
        scheduleState: SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: "",
            updatedAtMs: 0,
            lastHeartbeatAtMs: 0,
            lastObservedProgressAtMs: 0,
            lastPulseReviewAtMs: 0,
            lastBrainstormReviewAtMs: 0,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: 0,
            nextPulseReviewDueAtMs: 0,
            nextBrainstormReviewDueAtMs: 0
        ),
        now: Date(timeIntervalSince1970: 0)
    )

    private static func timestampText(ms: Int64, nowMs: Int64) -> String {
        guard ms > 0 else { return "(none)" }
        let absolute = governanceActivityTimestampFormatter.string(
            from: Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        )
        return "\(absolute) · \(relativeOffsetText(targetMs: ms, nowMs: nowMs))"
    }

    private static func relativeOffsetText(targetMs: Int64, nowMs: Int64) -> String {
        let deltaSeconds = (targetMs - nowMs) / 1000
        if deltaSeconds == 0 { return "now" }

        let isFuture = deltaSeconds > 0
        let absoluteSeconds = abs(deltaSeconds)
        if absoluteSeconds < 60 {
            return isFuture ? "in <1m" : "<1m ago"
        }

        let absoluteMinutes = absoluteSeconds / 60
        if absoluteMinutes < 60 {
            return isFuture ? "in \(absoluteMinutes)m" : "\(absoluteMinutes)m ago"
        }

        let absoluteHours = absoluteMinutes / 60
        if absoluteHours < 48 {
            let restMinutes = absoluteMinutes % 60
            if restMinutes == 0 {
                return isFuture ? "in \(absoluteHours)h" : "\(absoluteHours)h ago"
            }
            return isFuture
                ? "in \(absoluteHours)h \(restMinutes)m"
                : "\(absoluteHours)h \(restMinutes)m ago"
        }

        let absoluteDays = absoluteHours / 24
        let restHours = absoluteHours % 24
        if restHours == 0 {
            return isFuture ? "in \(absoluteDays)d" : "\(absoluteDays)d ago"
        }
        return isFuture
            ? "in \(absoluteDays)d \(restHours)h"
            : "\(absoluteDays)d \(restHours)h ago"
    }

    private static func guidanceAckText(
        status: SupervisorGuidanceAckStatus,
        required: Bool
    ) -> String {
        "\(status.displayName) · \(required ? "required" : "optional")"
    }

    private static func makeReviewSummary(
        _ record: SupervisorReviewNoteRecord,
        nowMs: Int64
    ) -> ReviewSummary {
        ReviewSummary(
            reviewID: record.reviewId,
            createdAtText: Self.timestampText(ms: record.createdAtMs, nowMs: nowMs),
            triggerText: record.trigger.displayName,
            reviewLevelText: record.reviewLevel.displayName,
            verdictText: record.verdict.displayName,
            deliveryModeText: record.deliveryMode.displayName,
            ackText: record.ackRequired ? "required" : "optional",
            effectiveSupervisorTierText: record.effectiveSupervisorTier?.displayName ?? "(none)",
            workOrderDepthText: record.effectiveWorkOrderDepth?.displayName ?? "(none)",
            projectAIStrengthText: strengthText(
                band: record.projectAIStrengthBand,
                confidence: record.projectAIStrengthConfidence
            ),
            workOrderRef: Self.orNone(record.workOrderRef ?? ""),
            summary: Self.orNone(record.summary),
            anchorGoal: Self.orNone(record.anchorGoal),
            anchorDoneDefinition: Self.orNone(record.anchorDoneDefinition),
            anchorConstraintsText: Self.listText(record.anchorConstraints),
            currentState: Self.orNone(record.currentState),
            nextStep: Self.orNone(record.nextStep),
            blocker: Self.orNone(record.blocker),
            recommendedActions: record.recommendedActions,
            auditRef: Self.orNone(record.auditRef)
        )
    }

    private static func makeGuidanceSummary(
        _ record: SupervisorGuidanceInjectionRecord,
        nowMs: Int64
    ) -> GuidanceSummary {
        GuidanceSummary(
            injectionID: record.injectionId,
            reviewID: Self.orNone(record.reviewId),
            injectedAtText: Self.timestampText(ms: record.injectedAtMs, nowMs: nowMs),
            deliveryModeText: record.deliveryMode.displayName,
            interventionText: record.interventionMode.displayName,
            safePointText: record.safePointPolicy.displayName,
            lifecycleText: SupervisorGuidanceInjectionStore.lifecycleSummary(for: record, nowMs: nowMs),
            ackText: Self.guidanceAckText(status: record.ackStatus, required: record.ackRequired),
            ackStatus: record.ackStatus,
            ackRequired: record.ackRequired,
            effectiveSupervisorTierText: record.effectiveSupervisorTier?.displayName ?? "(none)",
            workOrderDepthText: record.effectiveWorkOrderDepth?.displayName ?? "(none)",
            workOrderRef: Self.orNone(record.workOrderRef ?? ""),
            guidanceText: Self.orNone(record.guidanceText),
            ackUpdatedAtText: Self.timestampText(ms: record.ackUpdatedAtMs, nowMs: nowMs),
            ackNote: Self.orNone(record.ackNote),
            auditRef: Self.orNone(record.auditRef)
        )
    }

    private static func orNone(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(none)" : trimmed
    }

    private static func listText(_ values: [String]) -> String {
        let filtered = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return filtered.isEmpty ? "(none)" : filtered.joined(separator: " | ")
    }

    private static func strengthText(
        band: AXProjectAIStrengthBand?,
        confidence: Double?
    ) -> String {
        guard let band else { return "(none)" }
        guard let confidence else { return band.displayName }
        return "\(band.displayName) · conf=\(String(format: "%.2f", max(0, min(1, confidence))))"
    }
}

struct ProjectGovernanceActivityView: View {
    let ctx: AXProjectContext

    @State private var presentation: ProjectGovernanceActivityPresentation = .empty
    @State private var refreshedAt: Date?
    @State private var pendingAckNoteDraft: String = ""
    @State private var pendingAckInjectionID: String?
    @State private var ackInlineMessage: String = ""
    @State private var ackInlineMessageIsError = false

    var body: some View {
        GroupBox("Governance Activity") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("展示当前 project 最近一次 supervisor review、guidance 注入、ack 状态，以及下次 heartbeat / review 的计划时间。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    if presentation.pendingAckCount > 0 {
                        Text("Pending Ack × \(presentation.pendingAckCount)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.12))
                            )
                    }

                    Button("Reload") {
                        reload()
                    }
                }

                Text("snapshot: reviews=\(presentation.reviewCount) · guidance=\(presentation.guidanceCount) · refreshed_at=\(refreshedAtText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Divider()

                latestReviewSection

                Divider()

                pendingGuidanceSection

                Divider()

                latestGuidanceSection

                Divider()

                recentActivitySection

                Divider()

                scheduleSection
            }
            .padding(8)
        }
        .task(id: ctx.root.path) {
            reload()
        }
    }

    private var latestReviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Latest Review")
                .font(.caption.weight(.semibold))

            if let review = presentation.latestReview {
                GovernanceActivityRow(label: "review_id", value: review.reviewID)
                GovernanceActivityRow(label: "created_at", value: review.createdAtText)
                GovernanceActivityRow(label: "trigger", value: review.triggerText)
                GovernanceActivityRow(label: "level", value: review.reviewLevelText)
                GovernanceActivityRow(label: "verdict", value: review.verdictText)
                GovernanceActivityRow(label: "delivery", value: review.deliveryModeText)
                GovernanceActivityRow(label: "ack", value: review.ackText)
                GovernanceActivityRow(label: "supervisor_tier", value: review.effectiveSupervisorTierText)
                GovernanceActivityRow(label: "work_order_depth", value: review.workOrderDepthText)
                GovernanceActivityRow(label: "project_ai_strength", value: review.projectAIStrengthText)
                if presentation.followUpRhythmSummary != "(none)" {
                    GovernanceActivityRow(label: "follow_up_rhythm", value: presentation.followUpRhythmSummary)
                }
                GovernanceActivityRow(label: "work_order_ref", value: review.workOrderRef)
                GovernanceActivityRow(label: "summary", value: review.summary)
                GovernanceActivityRow(label: "anchor_goal", value: review.anchorGoal)
                GovernanceActivityRow(label: "done_definition", value: review.anchorDoneDefinition)
                GovernanceActivityRow(label: "constraints", value: review.anchorConstraintsText)
                GovernanceActivityRow(label: "current_state", value: review.currentState)
                GovernanceActivityRow(label: "next_step", value: review.nextStep)
                GovernanceActivityRow(label: "blocker", value: review.blocker)

                if !review.recommendedActions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("recommended_actions")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        ForEach(review.recommendedActions, id: \.self) { action in
                            Text("• \(action)")
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.leading, 2)
                }

                GovernanceActivityRow(label: "audit_ref", value: review.auditRef)
            } else {
                Text("还没有 supervisor review note。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var latestGuidanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Latest Guidance")
                .font(.caption.weight(.semibold))

            if let guidance = presentation.latestGuidance {
                if guidance.injectionID == presentation.pendingGuidance?.injectionID {
                    Text("最新 guidance 就是上面这条待确认 guidance。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    GovernanceActivityRow(label: "injection_id", value: guidance.injectionID)
                    GovernanceActivityRow(label: "review_id", value: guidance.reviewID)
                    GovernanceActivityRow(label: "injected_at", value: guidance.injectedAtText)
                    GovernanceActivityRow(label: "delivery", value: guidance.deliveryModeText)
                    GovernanceActivityRow(label: "intervention", value: guidance.interventionText)
                    GovernanceActivityRow(label: "safe_point", value: guidance.safePointText)
                    GovernanceActivityRow(label: "lifecycle", value: guidance.lifecycleText)
                    GovernanceActivityRow(label: "supervisor_tier", value: guidance.effectiveSupervisorTierText)
                    GovernanceActivityRow(label: "work_order_depth", value: guidance.workOrderDepthText)
                    GovernanceActivityRow(label: "work_order_ref", value: guidance.workOrderRef)
                    GovernanceActivityRow(
                        label: "ack",
                        value: guidance.ackText,
                        accent: guidance.ackRequired
                            && (guidance.ackStatus == .pending || guidance.lifecycleText == "retry due now")
                            ? .orange
                            : .secondary
                    )
                    GovernanceActivityRow(label: "guidance", value: guidance.guidanceText)
                    GovernanceActivityRow(label: "ack_updated_at", value: guidance.ackUpdatedAtText)
                    GovernanceActivityRow(label: "ack_note", value: guidance.ackNote)
                    GovernanceActivityRow(label: "audit_ref", value: guidance.auditRef)
                }
            } else {
                Text("还没有 guidance injection。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pendingGuidanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pending Guidance Ack")
                .font(.caption.weight(.semibold))

            if let guidance = presentation.pendingGuidance {
                Text("这条 guidance 还没确认。你可以在这里直接接受、暂缓或拒绝，结果会回写到治理审计和 ack 状态。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                GovernanceActivityRow(label: "injection_id", value: guidance.injectionID)
                GovernanceActivityRow(label: "review_id", value: guidance.reviewID)
                GovernanceActivityRow(label: "injected_at", value: guidance.injectedAtText)
                GovernanceActivityRow(label: "delivery", value: guidance.deliveryModeText)
                GovernanceActivityRow(label: "intervention", value: guidance.interventionText)
                GovernanceActivityRow(label: "safe_point", value: guidance.safePointText)
                GovernanceActivityRow(label: "lifecycle", value: guidance.lifecycleText)
                GovernanceActivityRow(label: "supervisor_tier", value: guidance.effectiveSupervisorTierText)
                GovernanceActivityRow(label: "work_order_depth", value: guidance.workOrderDepthText)
                GovernanceActivityRow(label: "work_order_ref", value: guidance.workOrderRef)
                GovernanceActivityRow(label: "guidance", value: guidance.guidanceText, accent: .primary)

                TextField("optional ack note / reject reason", text: $pendingAckNoteDraft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    Button("Accept") {
                        acknowledgePendingGuidance(.accepted)
                    }

                    Button("Defer") {
                        acknowledgePendingGuidance(.deferred)
                    }

                    Button("Reject") {
                        acknowledgePendingGuidance(.rejected)
                    }

                    Spacer()
                }
            } else {
                Text("当前没有待确认 guidance。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !ackInlineMessage.isEmpty {
                Text(ackInlineMessage)
                    .font(.caption)
                    .foregroundStyle(ackInlineMessageIsError ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Review Schedule")
                .font(.caption.weight(.semibold))

            GovernanceActivityRow(label: "last_heartbeat", value: presentation.schedule.lastHeartbeatText)
            GovernanceActivityRow(label: "next_heartbeat", value: presentation.schedule.nextHeartbeatText)
            GovernanceActivityRow(label: "last_pulse_review", value: presentation.schedule.lastPulseReviewText)
            GovernanceActivityRow(label: "next_pulse_review", value: presentation.schedule.nextPulseReviewText)
            GovernanceActivityRow(label: "last_brainstorm_review", value: presentation.schedule.lastBrainstormReviewText)
            GovernanceActivityRow(label: "next_brainstorm_review", value: presentation.schedule.nextBrainstormReviewText)
        }
    }

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.caption.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Reviews")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if presentation.recentReviews.isEmpty {
                    Text("还没有 review 历史。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(presentation.recentReviews) { review in
                        GovernanceHistoryCard(
                            title: "\(review.verdictText) · \(review.reviewLevelText)",
                            subtitle: "\(review.createdAtText) · \(review.triggerText)",
                            bodyText: review.summary,
                            footnote: governanceHistoryFootnote(
                                "next_step: \(review.nextStep)",
                                "depth: \(review.workOrderDepthText)",
                                "strength: \(review.projectAIStrengthText)",
                                "work_order: \(review.workOrderRef)"
                            )
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Guidance")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if presentation.recentGuidance.isEmpty {
                    Text("还没有 guidance 历史。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(presentation.recentGuidance) { guidance in
                        GovernanceHistoryCard(
                            title: "\(guidance.ackText) · \(guidance.interventionText)",
                            subtitle: "\(guidance.injectedAtText) · \(guidance.safePointText)",
                            bodyText: guidance.guidanceText,
                            footnote: governanceHistoryFootnote(
                                "delivery: \(guidance.deliveryModeText)",
                                "depth: \(guidance.workOrderDepthText)",
                                "work_order: \(guidance.workOrderRef)"
                            )
                        )
                    }
                }
            }
        }
    }

    private var refreshedAtText: String {
        guard let refreshedAt else { return "(not loaded)" }
        return governanceActivityTimestampFormatter.string(from: refreshedAt)
    }

    private func reload() {
        let reviewNotes = SupervisorReviewNoteStore.load(for: ctx)
        let guidance = SupervisorGuidanceInjectionStore.load(for: ctx)
        let schedule = SupervisorReviewScheduleStore.load(for: ctx)
        let config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: ctx.root)
        let adaptationPolicy = AXProjectSupervisorAdaptationPolicy.default
        let strengthProfile = AXProjectAIStrengthAssessor.assess(
            ctx: ctx,
            adaptationPolicy: adaptationPolicy
        )
        let resolvedGovernance = xtResolveProjectGovernance(
            projectRoot: ctx.root,
            config: config,
            projectAIStrengthProfile: strengthProfile,
            adaptationPolicy: adaptationPolicy,
            permissionReadiness: .current()
        )
        let nextPresentation = ProjectGovernanceActivityPresentation(
            reviewNotes: reviewNotes,
            guidance: guidance,
            scheduleState: schedule,
            resolvedGovernance: resolvedGovernance,
            now: Date()
        )
        let nextPendingInjectionID = nextPresentation.pendingGuidance?.injectionID
        if nextPendingInjectionID != pendingAckInjectionID {
            pendingAckInjectionID = nextPendingInjectionID
            pendingAckNoteDraft = ""
        }
        presentation = nextPresentation
        refreshedAt = Date()
    }

    private func acknowledgePendingGuidance(_ status: SupervisorGuidanceAckStatus) {
        guard let guidance = presentation.pendingGuidance else {
            ackInlineMessage = "当前没有待确认 guidance。"
            ackInlineMessageIsError = true
            return
        }

        do {
            let updated = try ProjectGovernanceGuidanceAckAction.acknowledge(
                ctx: ctx,
                injectionId: guidance.injectionID,
                status: status,
                note: pendingAckNoteDraft,
                source: "project_settings_governance_activity"
            )
            pendingAckNoteDraft = ""
            ackInlineMessage = "已更新 guidance ack：\(updated.injectionId) -> \(updated.ackStatus.displayName)"
            ackInlineMessageIsError = false
            reload()
        } catch {
            ackInlineMessage = "更新 guidance ack 失败：\(error.localizedDescription)"
            ackInlineMessageIsError = true
        }
    }
}

private func governanceHistoryFootnote(_ parts: String...) -> String {
    let filtered = parts
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && !$0.contains("(none)") }
    return filtered.isEmpty ? "(none)" : filtered.joined(separator: " · ")
}

private struct GovernanceActivityRow: View {
    let label: String
    let value: String
    var accent: Color = .secondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)

            Text(value)
                .font(.caption)
                .foregroundStyle(accent)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

private struct GovernanceHistoryCard: View {
    let title: String
    let subtitle: String
    let bodyText: String
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text(bodyText)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)

            Text(footnote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.06))
        )
    }
}

enum ProjectGovernanceGuidanceAckAction {
    enum AckError: LocalizedError {
        case injectionNotFound(String)

        var errorDescription: String? {
            switch self {
            case .injectionNotFound(let injectionId):
                return "找不到 guidance injection：\(injectionId)"
            }
        }
    }

    @discardableResult
    static func acknowledge(
        ctx: AXProjectContext,
        injectionId: String,
        status: SupervisorGuidanceAckStatus,
        note: String,
        source: String
    ) throws -> SupervisorGuidanceInjectionRecord {
        let normalizedInjectionID = injectionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedInjectionID.isEmpty else {
            throw AckError.injectionNotFound(injectionId)
        }

        let snapshot = SupervisorGuidanceInjectionStore.load(for: ctx)
        guard let current = snapshot.items.first(where: { $0.injectionId == normalizedInjectionID }) else {
            throw AckError.injectionNotFound(normalizedInjectionID)
        }

        let normalizedNote = normalizedAckNote(note, status: status)
        let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())

        try SupervisorGuidanceInjectionStore.acknowledge(
            injectionId: normalizedInjectionID,
            status: status,
            note: normalizedNote,
            atMs: nowMs,
            for: ctx
        )

        AXProjectStore.appendRawLog(
            [
                "type": "supervisor_guidance_ack",
                "action": "manual_ack",
                "source": source,
                "project_id": current.projectId,
                "review_id": current.reviewId,
                "injection_id": current.injectionId,
                "ack_status": status.rawValue,
                "ack_note": normalizedNote,
                "ack_required": current.ackRequired,
                "timestamp_ms": nowMs
            ],
            for: ctx
        )

        guard let updated = SupervisorGuidanceInjectionStore.load(for: ctx).items.first(where: {
            $0.injectionId == normalizedInjectionID
        }) else {
            throw AckError.injectionNotFound(normalizedInjectionID)
        }

        Task { @MainActor in
            AXEventBus.shared.publish(.supervisorGuidanceAck(updated))
        }

        return updated
    }

    private static func normalizedAckNote(
        _ note: String,
        status: SupervisorGuidanceAckStatus
    ) -> String {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            switch status {
            case .accepted:
                return "manual_accept_from_project_settings"
            case .deferred:
                return "manual_defer_from_project_settings"
            case .rejected:
                return "manual_reject_from_project_settings"
            case .pending:
                return "manual_pending_from_project_settings"
            }
        }
        return trimmed
    }
}

extension SupervisorReviewTrigger {
    var displayName: String {
        switch self {
        case .periodicHeartbeat:
            return "Periodic Heartbeat"
        case .periodicPulse:
            return "Periodic Pulse"
        case .failureStreak:
            return "Failure Streak"
        case .noProgressWindow:
            return "No Progress Window"
        case .blockerDetected:
            return "Blocker Detected"
        case .planDrift:
            return "Plan Drift"
        case .preHighRiskAction:
            return "Pre-High-Risk"
        case .preDoneSummary:
            return "Pre-Done"
        case .manualRequest:
            return "Manual Request"
        case .userOverride:
            return "User Override"
        }
    }
}

extension SupervisorReviewLevel {
    var displayName: String {
        switch self {
        case .r1Pulse:
            return "R1 Pulse"
        case .r2Strategic:
            return "R2 Strategic"
        case .r3Rescue:
            return "R3 Rescue"
        }
    }
}

extension SupervisorReviewVerdict {
    var displayName: String {
        switch self {
        case .onTrack:
            return "On Track"
        case .watch:
            return "Watch"
        case .betterPathFound:
            return "Better Path Found"
        case .wrongDirection:
            return "Wrong Direction"
        case .highRisk:
            return "High Risk"
        }
    }
}

extension SupervisorGuidanceDeliveryMode {
    var displayName: String {
        switch self {
        case .contextAppend:
            return "Context Append"
        case .priorityInsert:
            return "Priority Insert"
        case .replanRequest:
            return "Replan Request"
        case .stopSignal:
            return "Stop Signal"
        }
    }
}

extension SupervisorGuidanceSafePointPolicy {
    var displayName: String {
        switch self {
        case .nextToolBoundary:
            return "Next Tool Boundary"
        case .nextStepBoundary:
            return "Next Step Boundary"
        case .checkpointBoundary:
            return "Checkpoint Boundary"
        case .immediate:
            return "Immediate"
        }
    }
}

extension SupervisorGuidanceAckStatus {
    var displayName: String {
        switch self {
        case .pending:
            return "Pending"
        case .accepted:
            return "Accepted"
        case .deferred:
            return "Deferred"
        case .rejected:
            return "Rejected"
        }
    }
}

private let governanceActivityTimestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter
}()
