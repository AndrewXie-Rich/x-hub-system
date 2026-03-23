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
        var contractSummary: SupervisorGuidanceContractSummary? = nil

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

        let reviewById = Dictionary(reviewNotes.notes.map { ($0.reviewId, $0) }, uniquingKeysWith: { first, _ in first })
        pendingGuidance = actionableGuidance.first.map {
            Self.makeGuidanceSummary(
                $0,
                reviewNote: reviewById[$0.reviewId],
                nowMs: nowMs
            )
        }
        recentGuidance = guidance.items.prefix(5).map {
            Self.makeGuidanceSummary(
                $0,
                reviewNote: reviewById[$0.reviewId],
                nowMs: nowMs
            )
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

    static func load(
        for ctx: AXProjectContext,
        resolvedGovernance: AXProjectResolvedGovernanceState? = nil,
        now: Date = Date()
    ) -> ProjectGovernanceActivityPresentation {
        let reviewNotes = SupervisorReviewNoteStore.load(for: ctx)
        let guidance = SupervisorGuidanceInjectionStore.load(for: ctx)
        let schedule = SupervisorReviewScheduleStore.load(for: ctx)

        return ProjectGovernanceActivityPresentation(
            reviewNotes: reviewNotes,
            guidance: guidance,
            scheduleState: schedule,
            resolvedGovernance: resolvedGovernance ?? resolvedGovernanceState(for: ctx),
            now: now
        )
    }

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
        reviewNote: SupervisorReviewNoteRecord?,
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
            auditRef: Self.orNone(record.auditRef),
            contractSummary: SupervisorGuidanceContractResolver.resolve(
                guidance: record,
                reviewNote: reviewNote
            )
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

    private static func resolvedGovernanceState(
        for ctx: AXProjectContext
    ) -> AXProjectResolvedGovernanceState {
        let config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: ctx.root)
        let adaptationPolicy = AXProjectSupervisorAdaptationPolicy.default
        let strengthProfile = AXProjectAIStrengthAssessor.assess(
            ctx: ctx,
            adaptationPolicy: adaptationPolicy
        )
        return xtResolveProjectGovernance(
            projectRoot: ctx.root,
            config: config,
            projectAIStrengthProfile: strengthProfile,
            adaptationPolicy: adaptationPolicy,
            permissionReadiness: .current()
        )
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
        GroupBox("治理动态") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("展示当前项目最近一次 Supervisor 审查、指导注入、确认状态，以及下一次心跳 / 审查的计划时间。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    if presentation.pendingAckCount > 0 {
                        Text("待确认 × \(presentation.pendingAckCount)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.12))
                            )
                    }

                    Button("刷新") {
                        reload()
                    }
                }

                Text("快照：审查 \(presentation.reviewCount) · 指导 \(presentation.guidanceCount) · 刷新于 \(refreshedAtText)")
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
            Text("最新审查")
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
                        Text(ProjectGovernanceActivityDisplay.fieldLabel("recommended_actions"))
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
                Text("还没有 supervisor 审查记录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var latestGuidanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最新指导")
                .font(.caption.weight(.semibold))

            if let guidance = presentation.latestGuidance {
                if guidance.injectionID == presentation.pendingGuidance?.injectionID {
                    Text("最新指导就是上面这条待确认记录。")
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
                    if let contract = guidance.contractSummary {
                        GovernanceActivityRow(label: "contract_kind", value: contract.kindText)
                        GovernanceActivityRow(label: "contract_summary", value: contract.summaryText)
                        if let uiReview = contract.uiReviewRepair {
                            GovernanceActivityRow(
                                label: "repair_action",
                                value: uiReview.repairAction.isEmpty ? "(none)" : uiReview.repairAction
                            )
                            GovernanceActivityRow(
                                label: "repair_focus",
                                value: uiReview.repairFocus.isEmpty ? "(none)" : uiReview.repairFocus
                            )
                        } else {
                            GovernanceActivityRow(label: "primary_blocker", value: contract.primaryFocusText)
                        }
                        GovernanceActivityRow(label: "next_safe_action", value: contract.nextSafeActionText)
                        if let actions = contract.recommendedActionsText {
                            GovernanceActivityRow(label: "recommended_actions", value: actions)
                        }
                    }
                    GovernanceActivityRow(label: "guidance", value: guidance.guidanceText)
                    GovernanceActivityRow(label: "ack_updated_at", value: guidance.ackUpdatedAtText)
                    GovernanceActivityRow(label: "ack_note", value: guidance.ackNote)
                    GovernanceActivityRow(label: "audit_ref", value: guidance.auditRef)
                }
            } else {
                Text("还没有指导注入记录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pendingGuidanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("待确认指导")
                .font(.caption.weight(.semibold))

            if let guidance = presentation.pendingGuidance {
                Text("这条指导还没确认。你可以在这里直接接受、暂缓或拒绝，结果会回写到治理审计和确认状态。")
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
                if let contract = guidance.contractSummary {
                    GovernanceActivityRow(label: "contract_kind", value: contract.kindText)
                    GovernanceActivityRow(label: "contract_summary", value: contract.summaryText)
                    if let uiReview = contract.uiReviewRepair {
                        GovernanceActivityRow(
                            label: "repair_action",
                            value: uiReview.repairAction.isEmpty ? "(none)" : uiReview.repairAction
                        )
                        GovernanceActivityRow(
                            label: "repair_focus",
                            value: uiReview.repairFocus.isEmpty ? "(none)" : uiReview.repairFocus
                        )
                    } else {
                        GovernanceActivityRow(label: "primary_blocker", value: contract.primaryFocusText)
                    }
                    GovernanceActivityRow(label: "next_safe_action", value: contract.nextSafeActionText)
                    if let actions = contract.recommendedActionsText {
                        GovernanceActivityRow(label: "recommended_actions", value: actions)
                    }
                }
                GovernanceActivityRow(label: "guidance", value: guidance.guidanceText, accent: .primary)

                TextField("可选：确认备注 / 拒绝原因", text: $pendingAckNoteDraft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    Button("接受") {
                        acknowledgePendingGuidance(.accepted)
                    }

                    Button("暂缓") {
                        acknowledgePendingGuidance(.deferred)
                    }

                    Button("拒绝") {
                        acknowledgePendingGuidance(.rejected)
                    }

                    Spacer()
                }
            } else {
                Text("当前没有待确认指导。")
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
            Text("审查节奏")
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
            Text("最近动态")
                .font(.caption.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("最近审查")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if presentation.recentReviews.isEmpty {
                    Text("还没有审查历史。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(presentation.recentReviews) { review in
                        GovernanceHistoryCard(
                            title: "\(ProjectGovernanceActivityDisplay.displayValue(label: "verdict", value: review.verdictText)) · \(ProjectGovernanceActivityDisplay.displayValue(label: "level", value: review.reviewLevelText))",
                            subtitle: "\(review.createdAtText) · \(ProjectGovernanceActivityDisplay.displayValue(label: "trigger", value: review.triggerText))",
                            bodyText: review.summary,
                            footnote: governanceHistoryFootnote(
                                ProjectGovernanceActivityDisplay.fieldLine("next_step", value: review.nextStep),
                                ProjectGovernanceActivityDisplay.fieldLine("work_order_depth", value: review.workOrderDepthText),
                                ProjectGovernanceActivityDisplay.fieldLine("project_ai_strength", value: review.projectAIStrengthText),
                                ProjectGovernanceActivityDisplay.fieldLine("work_order_ref", value: review.workOrderRef)
                            )
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("最近指导")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if presentation.recentGuidance.isEmpty {
                    Text("还没有指导历史。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(presentation.recentGuidance) { guidance in
                        GovernanceHistoryCard(
                            title: "\(ProjectGovernanceActivityDisplay.displayValue(label: "ack", value: guidance.ackText)) · \(ProjectGovernanceActivityDisplay.displayValue(label: "intervention", value: guidance.interventionText))",
                            subtitle: "\(guidance.injectedAtText) · \(ProjectGovernanceActivityDisplay.displayValue(label: "safe_point", value: guidance.safePointText))",
                            bodyText: governanceGuidanceBodyText(guidance),
                            footnote: governanceHistoryFootnote(
                                ProjectGovernanceActivityDisplay.fieldLine("delivery", value: guidance.deliveryModeText),
                                ProjectGovernanceActivityDisplay.fieldLine("work_order_depth", value: guidance.workOrderDepthText),
                                ProjectGovernanceActivityDisplay.fieldLine("work_order_ref", value: guidance.workOrderRef),
                                governanceGuidanceFootnote(guidance)
                            )
                        )
                    }
                }
            }
        }
    }

    private var refreshedAtText: String {
        guard let refreshedAt else { return "未加载" }
        return governanceActivityTimestampFormatter.string(from: refreshedAt)
    }

    private func reload() {
        let nextPresentation = ProjectGovernanceActivityPresentation.load(for: ctx, now: Date())
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
            ackInlineMessage = "当前没有待确认指导。"
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
            ackInlineMessage = "已更新指导确认：\(updated.injectionId) -> \(ProjectGovernanceActivityDisplay.ackStatusLabel(updated.ackStatus))"
            ackInlineMessageIsError = false
            reload()
        } catch {
            ackInlineMessage = "更新指导确认失败：\(error.localizedDescription)"
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

private func governanceGuidanceBodyText(
    _ guidance: ProjectGovernanceActivityPresentation.GuidanceSummary
) -> String {
    guard let contract = guidance.contractSummary else {
        return guidance.guidanceText
    }

    var lines: [String] = [contract.summaryText]
    if let uiReview = contract.uiReviewRepair {
        if !uiReview.repairAction.isEmpty || !uiReview.repairFocus.isEmpty {
            let repair = [
                uiReview.repairAction.isEmpty ? nil : ProjectGovernanceActivityDisplay.fieldLine("repair_action", value: uiReview.repairAction),
                uiReview.repairFocus.isEmpty ? nil : ProjectGovernanceActivityDisplay.fieldLine("repair_focus", value: uiReview.repairFocus)
            ]
            .compactMap { $0 }
            .joined(separator: " · ")
            if !repair.isEmpty {
                lines.append(repair)
            }
        }
    } else if !contract.primaryBlocker.isEmpty {
        lines.append(ProjectGovernanceActivityDisplay.fieldLine("primary_blocker", value: contract.primaryBlocker))
    }

    if contract.nextSafeActionText != "(none)" {
        lines.append(ProjectGovernanceActivityDisplay.fieldLine("next_safe_action", value: contract.nextSafeActionText))
    }

    return lines.joined(separator: "\n")
}

private func governanceGuidanceFootnote(
    _ guidance: ProjectGovernanceActivityPresentation.GuidanceSummary
) -> String {
    guard let contract = guidance.contractSummary else { return "" }
    return governanceHistoryFootnote(
        ProjectGovernanceActivityDisplay.fieldLine("contract_kind", value: contract.kindText),
        contract.recommendedActionsText.map {
            ProjectGovernanceActivityDisplay.fieldLine("recommended_actions", value: $0)
        } ?? ""
    )
}

private struct GovernanceActivityRow: View {
    let label: String
    let value: String
    var accent: Color = .secondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(ProjectGovernanceActivityDisplay.fieldLabel(label))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)

            Text(ProjectGovernanceActivityDisplay.displayValue(label: label, value: value))
                .font(.caption)
                .foregroundStyle(accent)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

enum ProjectGovernanceActivityDisplay {
    static func fieldLabel(_ raw: String) -> String {
        switch raw {
        case "review_id":
            return "审查 ID"
        case "created_at":
            return "创建时间"
        case "trigger":
            return "触发原因"
        case "level":
            return "审查层级"
        case "verdict":
            return "结论"
        case "delivery":
            return "交付方式"
        case "ack":
            return "确认状态"
        case "ack_status":
            return "确认状态"
        case "supervisor_tier":
            return "Supervisor 层级"
        case "work_order_depth":
            return "工单深度"
        case "project_ai_strength":
            return "项目 AI 强度"
        case "follow_up_rhythm":
            return "跟进节奏"
        case "work_order_ref":
            return "工单引用"
        case "summary":
            return "摘要"
        case "anchor_goal":
            return "锚定目标"
        case "done_definition":
            return "完成定义"
        case "constraints":
            return "约束"
        case "current_state":
            return "当前状态"
        case "next_step":
            return "下一步"
        case "blocker":
            return "阻塞点"
        case "recommended_actions":
            return "建议动作"
        case "audit_ref":
            return "审计引用"
        case "injection_id":
            return "指导 ID"
        case "injected_at":
            return "注入时间"
        case "intervention":
            return "干预方式"
        case "safe_point":
            return "安全点"
        case "lifecycle":
            return "生命周期"
        case "contract_kind":
            return "指导合同类型"
        case "contract_summary":
            return "指导合同摘要"
        case "repair_action":
            return "修复动作"
        case "repair_focus":
            return "修复焦点"
        case "primary_blocker":
            return "主要阻塞点"
        case "next_safe_action":
            return "下一个安全动作"
        case "guidance":
            return "指导内容"
        case "ack_updated_at":
            return "确认更新时间"
        case "ack_note":
            return "确认备注"
        case "expires_at_ms":
            return "过期时间(ms)"
        case "retry_at_ms":
            return "重试时间(ms)"
        case "retry_count":
            return "重试次数"
        case "last_heartbeat":
            return "上次心跳"
        case "next_heartbeat":
            return "下次心跳"
        case "last_pulse_review":
            return "上次脉冲审查"
        case "next_pulse_review":
            return "下次脉冲审查"
        case "last_brainstorm_review":
            return "上次脑暴审查"
        case "next_brainstorm_review":
            return "下次脑暴审查"
        default:
            return raw
        }
    }

    static func displayValue(label: String, value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return value }

        switch label {
        case "trigger":
            return localizedReviewTrigger(trimmed)
        case "level":
            return localizedReviewLevel(trimmed)
        case "verdict":
            return localizedVerdict(trimmed)
        case "delivery":
            return localizedDeliveryMode(trimmed)
        case "intervention":
            return localizedInterventionMode(trimmed)
        case "safe_point":
            return localizedSafePoint(trimmed)
        case "ack":
            return localizedAckText(trimmed)
        case "ack_status":
            return localizedAckText(trimmed)
        case "lifecycle":
            return localizedLifecycleText(trimmed)
        case "supervisor_tier":
            return localizedSupervisorTier(trimmed)
        case "work_order_depth":
            return localizedWorkOrderDepth(trimmed)
        case "project_ai_strength":
            return localizedProjectAIStrength(trimmed)
        case "follow_up_rhythm":
            return localizedFollowUpRhythm(trimmed)
        default:
            return trimmed
        }
    }

    static func fieldLine(_ label: String, value: String) -> String {
        "\(fieldLabel(label))：\(displayValue(label: label, value: value))"
    }

    static func ackStatusLabel(_ status: SupervisorGuidanceAckStatus) -> String {
        switch status {
        case .pending:
            return "待确认"
        case .accepted:
            return "已接受"
        case .deferred:
            return "已暂缓"
        case .rejected:
            return "已拒绝"
        }
    }

    private static func localizedAckText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "Pending", with: "待确认")
            .replacingOccurrences(of: "Accepted", with: "已接受")
            .replacingOccurrences(of: "Deferred", with: "已暂缓")
            .replacingOccurrences(of: "Rejected", with: "已拒绝")
            .replacingOccurrences(of: "required", with: "需要确认")
            .replacingOccurrences(of: "optional", with: "可选")
    }

    private static func localizedLifecycleText(_ value: String) -> String {
        let lowered = value.lowercased()
        switch lowered {
        case "active":
            return "生效中"
        case "retry due now":
            return "现在可重试"
        case "expired":
            return "已过期"
        case "settled":
            return "已结束"
        case "deferred":
            return "已暂缓"
        case "retry budget exhausted":
            return "重试额度已用尽"
        default:
            if lowered.hasPrefix("expires ") {
                let offset = String(value.dropFirst("expires ".count))
                return "将在\(localizedRelativeTime(offset))过期"
            }
            if lowered.hasPrefix("retry ") {
                let offset = String(value.dropFirst("retry ".count))
                return "将在\(localizedRelativeTime(offset))重试"
            }
            return value
        }
    }

    private static func localizedRelativeTime(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        switch lowered {
        case "now":
            return "现在"
        case "in <1m":
            return "1分钟内"
        case "<1m ago":
            return "不到1分钟前"
        default:
            break
        }

        if lowered.hasPrefix("in ") {
            let future = String(trimmed.dropFirst(3))
            return "\(localizedDurationParts(future))后"
        }

        if lowered.hasSuffix(" ago") {
            let past = String(trimmed.dropLast(4))
            return "\(localizedDurationParts(past))前"
        }

        return trimmed
    }

    private static func localizedDurationParts(_ value: String) -> String {
        let parts = value
            .split(separator: " ")
            .map(String.init)
            .map { part -> String in
                if part.hasSuffix("h"), let hours = Int(part.dropLast()) {
                    return "\(hours)小时"
                }
                if part.hasSuffix("m"), let minutes = Int(part.dropLast()) {
                    return "\(minutes)分钟"
                }
                return part
            }
        return parts.joined()
    }

    private static func localizedReviewTrigger(_ value: String) -> String {
        switch value.lowercased() {
        case "periodic heartbeat":
            return "周期心跳"
        case "periodic pulse":
            return "周期脉冲审查"
        case "failure streak":
            return "连续失败"
        case "no progress window":
            return "进展停滞"
        case "blocker detected":
            return "发现阻塞"
        case "plan drift":
            return "计划漂移"
        case "pre-high-risk":
            return "高风险前审查"
        case "pre-done":
            return "完成前审查"
        case "manual request":
            return "手动请求"
        case "user override":
            return "用户覆盖"
        default:
            return value
        }
    }

    private static func localizedReviewLevel(_ value: String) -> String {
        switch value.lowercased() {
        case "r1 pulse":
            return "R1 脉冲"
        case "r2 strategic":
            return "R2 战略"
        case "r3 rescue":
            return "R3 救援"
        default:
            return value
        }
    }

    private static func localizedVerdict(_ value: String) -> String {
        switch value.lowercased() {
        case "on track":
            return "进展正常"
        case "watch":
            return "需要关注"
        case "better path found":
            return "发现更优路径"
        case "wrong direction":
            return "方向错误"
        case "high risk":
            return "高风险"
        default:
            return value
        }
    }

    private static func localizedDeliveryMode(_ value: String) -> String {
        switch value.lowercased() {
        case "context append":
            return "上下文追加"
        case "priority insert":
            return "优先插入"
        case "replan request":
            return "请求重规划"
        case "stop signal":
            return "停止信号"
        default:
            return value
        }
    }

    private static func localizedInterventionMode(_ value: String) -> String {
        switch value.lowercased() {
        case "observe only":
            return "仅观察"
        case "suggest at safe point":
            return "在安全点建议"
        case "replan at safe point":
            return "在安全点重规划"
        case "stop immediately":
            return "立即停止"
        default:
            return value
        }
    }

    private static func localizedSafePoint(_ value: String) -> String {
        switch value.lowercased() {
        case "next tool boundary":
            return "下一个工具边界"
        case "next step boundary":
            return "下一步边界"
        case "checkpoint boundary":
            return "检查点边界"
        case "immediate":
            return "立即执行"
        default:
            return value
        }
    }

    private static func localizedSupervisorTier(_ value: String) -> String {
        value
            .replacingOccurrences(of: "S0 Silent Audit", with: "S0 静默审计")
            .replacingOccurrences(of: "S1 Milestone Review", with: "S1 里程碑审查")
            .replacingOccurrences(of: "S2 Periodic Review", with: "S2 周期审查")
            .replacingOccurrences(of: "S3 Strategic Coach", with: "S3 战略教练")
            .replacingOccurrences(of: "S4 Tight Supervision", with: "S4 紧密监督")
    }

    private static func localizedWorkOrderDepth(_ value: String) -> String {
        value
            .replacingOccurrences(of: "Execution Ready", with: "执行就绪")
            .replacingOccurrences(of: "Milestone Contract", with: "里程碑合同")
            .replacingOccurrences(of: "Step-Locked Rescue", with: "锁步救援")
            .replacingOccurrences(of: "Brief", with: "简要")
            .replacingOccurrences(of: "None", with: "无")
    }

    private static func localizedProjectAIStrength(_ value: String) -> String {
        value
            .replacingOccurrences(of: "Unknown", with: "未知")
            .replacingOccurrences(of: "Weak", with: "弱")
            .replacingOccurrences(of: "Developing", with: "成长中")
            .replacingOccurrences(of: "Capable", with: "可胜任")
            .replacingOccurrences(of: "Strong", with: "强")
            .replacingOccurrences(of: "conf=", with: "置信度=")
    }

    private static func localizedFollowUpRhythm(_ value: String) -> String {
        let localized = value
            .replacingOccurrences(of: "cadence=tight", with: "节奏=紧凑")
            .replacingOccurrences(of: "cadence=active", with: "节奏=活跃")
            .replacingOccurrences(of: "cadence=balanced", with: "节奏=平衡")
            .replacingOccurrences(of: "cadence=light", with: "节奏=轻量")
            .replacingOccurrences(of: "blocker cooldown≈", with: "阻塞冷却≈")
        return localized.replacingOccurrences(
            of: #"(\d+)s\b"#,
            with: "$1秒",
            options: .regularExpression
        )
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
                return "找不到指导注入记录：\(injectionId)"
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
