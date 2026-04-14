import Foundation
import SwiftUI

struct ProjectGovernanceActivityPresentation: Equatable {
    struct ConfigUpdateSummary: Equatable, Identifiable {
        var updateID: String
        var updatedAtText: String
        var configuredGovernanceText: String
        var effectiveGovernanceText: String
        var effectiveWorkOrderDepthText: String
        var reviewPolicyText: String
        var cadenceText: String
        var eventReviewText: String
        var runtimeSurfaceText: String
        var governanceTruthText: String
        var validationText: String

        var id: String { updateID }
    }

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
        var guidanceSummaryText: String
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
        var heartbeatQualityBandText: String
        var heartbeatQualityScoreText: String
        var heartbeatOpenAnomaliesText: String
    }

    struct AutomationSummary: Equatable {
        var runID: String
        var stateText: String
        var stepText: String
        var verificationText: String
        var verificationContractText: String?
        var blockerText: String
        var retryText: String
        var retryVerificationContractText: String?
        var recoveryText: String
        var handoffText: String
        var auditRef: String
    }

    struct AutomationEventSummary: Equatable, Identifiable {
        var eventID: String
        var createdAtText: String
        var eventTypeText: String
        var runID: String
        var stateText: String
        var stepText: String
        var verificationText: String
        var verificationContractText: String?
        var blockerText: String
        var retryText: String
        var retryVerificationContractText: String?
        var detailText: String
        var auditRef: String

        var id: String { eventID }
    }

    struct AutomationSnapshot: Equatable {
        var latest: AutomationSummary?
        var recentEvents: [AutomationEventSummary]
    }

    var reviewCount: Int
    var guidanceCount: Int
    var pendingAckCount: Int
    var followUpRhythmSummary: String
    var cadenceExplainability: SupervisorCadenceExplainability?
    var latestConfigUpdate: ConfigUpdateSummary?
    var recentConfigUpdates: [ConfigUpdateSummary]
    var latestReview: ReviewSummary?
    var recentReviews: [ReviewSummary]
    var pendingGuidance: GuidanceSummary?
    var latestGuidance: GuidanceSummary?
    var recentGuidance: [GuidanceSummary]
    var schedule: ScheduleSummary
    var latestAutomation: AutomationSummary?
    var recentAutomationEvents: [AutomationEventSummary]

    init(
        reviewNotes: SupervisorReviewNoteSnapshot,
        guidance: SupervisorGuidanceInjectionSnapshot,
        scheduleState: SupervisorReviewScheduleState,
        configUpdates: [ConfigUpdateSummary] = [],
        automation: AutomationSnapshot? = nil,
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
        cadenceExplainability = resolvedGovernance.map {
            SupervisorReviewPolicyEngine.cadenceExplainability(
                governance: $0,
                schedule: scheduleState,
                nowMs: nowMs
            )
        }
        followUpRhythmSummary = resolvedGovernance.map {
            SupervisorReviewPolicyEngine.eventFollowUpCadenceLabel(governance: $0)
        } ?? "(none)"
        recentConfigUpdates = Array(configUpdates.prefix(5))
        latestConfigUpdate = recentConfigUpdates.first

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
            nextHeartbeatText: Self.timestampText(
                ms: cadenceExplainability?.progressHeartbeat.nextDueAtMs ?? scheduleState.nextHeartbeatDueAtMs,
                nowMs: nowMs
            ),
            lastPulseReviewText: Self.timestampText(ms: scheduleState.lastPulseReviewAtMs, nowMs: nowMs),
            nextPulseReviewText: Self.timestampText(
                ms: cadenceExplainability?.reviewPulse.nextDueAtMs ?? scheduleState.nextPulseReviewDueAtMs,
                nowMs: nowMs
            ),
            lastBrainstormReviewText: Self.timestampText(ms: scheduleState.lastBrainstormReviewAtMs, nowMs: nowMs),
            nextBrainstormReviewText: Self.timestampText(
                ms: cadenceExplainability?.brainstormReview.nextDueAtMs ?? scheduleState.nextBrainstormReviewDueAtMs,
                nowMs: nowMs
            ),
            heartbeatQualityBandText: scheduleState.latestQualitySnapshot?.overallBand.displayName ?? "(none)",
            heartbeatQualityScoreText: scheduleState.latestQualitySnapshot.map { "\($0.overallScore) / 100" } ?? "(none)",
            heartbeatOpenAnomaliesText: Self.heartbeatAnomalySummaryText(scheduleState.openAnomalies)
        )
        latestAutomation = automation?.latest
        recentAutomationEvents = automation?.recentEvents ?? []
    }

    private static func heartbeatAnomalySummaryText(
        _ anomalies: [HeartbeatAnomalyNote]
    ) -> String {
        guard !anomalies.isEmpty else { return "(none)" }
        let typeText = anomalies
            .prefix(3)
            .map { $0.anomalyType.displayName }
            .joined(separator: ", ")
        return "\(anomalies.count) open · \(typeText)"
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
        let configUpdates = AXProjectSkillActivityStore
            .loadTailRawLogText(ctx: ctx)
            .map { parseConfigUpdates(from: $0, now: now) } ?? []
        let automation = Self.automationSnapshot(for: ctx, now: now)

        return ProjectGovernanceActivityPresentation(
            reviewNotes: reviewNotes,
            guidance: guidance,
            scheduleState: schedule,
            configUpdates: configUpdates,
            automation: automation,
            resolvedGovernance: resolvedGovernance ?? resolvedGovernanceState(for: ctx),
            now: now
        )
    }

    private static func parseConfigUpdates(
        from raw: String,
        limit: Int = 5,
        now: Date
    ) -> [ConfigUpdateSummary] {
        guard limit > 0 else { return [] }
        let nowMs = Int64(now.timeIntervalSince1970 * 1000.0)

        let updates: [(createdAt: Double, lineIndex: Int, summary: ConfigUpdateSummary)] = raw
            .split(separator: "\n", omittingEmptySubsequences: true)
            .enumerated()
            .compactMap { lineIndex, line in
                guard let data = String(line).data(using: .utf8),
                      let value = try? JSONDecoder().decode(JSONValue.self, from: data),
                      case .object(let object) = value,
                      Self.stringValue(object["type"]) == "project_governance_bundle" else {
                    return nil
                }

                return (
                    createdAt: Self.numberValue(object["created_at"]) ?? 0,
                    lineIndex: lineIndex,
                    summary: Self.makeConfigUpdateSummary(
                        object,
                        lineIndex: lineIndex,
                        nowMs: nowMs
                    )
                )
            }

        return updates
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.lineIndex > rhs.lineIndex
            }
            .prefix(limit)
            .map(\.summary)
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
            guidanceSummaryText: Self.guidanceSummaryText(record.guidanceText),
            ackUpdatedAtText: Self.timestampText(ms: record.ackUpdatedAtMs, nowMs: nowMs),
            ackNote: Self.orNone(record.ackNote),
            auditRef: Self.orNone(record.auditRef),
            contractSummary: SupervisorGuidanceContractResolver.resolve(
                guidance: record,
                reviewNote: reviewNote
            )
        )
    }

    private static func guidanceSummaryText(
        _ raw: String
    ) -> String {
        let summary = SupervisorGuidanceTextPresentation.summary(raw, maxChars: 320)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty {
            return summary
        }
        return Self.orNone(raw)
    }

    private static func makeConfigUpdateSummary(
        _ object: [String: JSONValue],
        lineIndex: Int,
        nowMs: Int64
    ) -> ConfigUpdateSummary {
        let createdAtMs = Int64((Self.numberValue(object["created_at"]) ?? 0) * 1000.0)
        let configuredExecutionTier = Self.stringValue(
            Self.preferredJSONValue(
                object["configured_execution_tier"],
                object["execution_tier"]
            )
        )
        let effectiveExecutionTier = Self.stringValue(
            Self.preferredJSONValue(
                object["effective_execution_tier"],
                object["execution_tier"]
            )
        )
        let configuredSupervisorTier = Self.stringValue(
            Self.preferredJSONValue(
                object["configured_supervisor_tier"],
                object["supervisor_intervention_tier"]
            )
        )
        let effectiveSupervisorTier = Self.stringValue(
            Self.preferredJSONValue(
                object["effective_supervisor_tier"],
                object["effective_supervisor_intervention_tier"],
                object["supervisor_intervention_tier"]
            )
        )
        let reviewPolicyMode = Self.stringValue(object["review_policy_mode"])
        let progressHeartbeatSeconds = Self.intValue(object["progress_heartbeat_sec"])
        let reviewPulseSeconds = Self.intValue(object["review_pulse_sec"])
        let brainstormReviewSeconds = Self.intValue(object["brainstorm_review_sec"])
        let compatSource = Self.stringValue(
            Self.preferredJSONValue(
                object["governance_compat_source"],
                object["compat_source"]
            )
        )

        let governanceTruth = Self.stringValue(object["governance_truth"])
            ?? XTGovernanceTruthPresentation.truthLine(
                configuredExecutionTier: configuredExecutionTier,
                effectiveExecutionTier: effectiveExecutionTier,
                configuredSupervisorTier: configuredSupervisorTier,
                effectiveSupervisorTier: effectiveSupervisorTier,
                reviewPolicyMode: reviewPolicyMode,
                progressHeartbeatSeconds: progressHeartbeatSeconds,
                reviewPulseSeconds: reviewPulseSeconds,
                brainstormReviewSeconds: brainstormReviewSeconds,
                compatSource: compatSource
            )

        let summaryId: String
        if createdAtMs > 0 {
            summaryId = "governance-update-\(createdAtMs)-\(lineIndex)"
        } else {
            summaryId = "governance-update-line-\(lineIndex)"
        }

        return ConfigUpdateSummary(
            updateID: summaryId,
            updatedAtText: Self.timestampText(ms: createdAtMs, nowMs: nowMs),
            configuredGovernanceText: Self.governanceTierPairText(
                executionTier: configuredExecutionTier,
                supervisorTier: configuredSupervisorTier
            ),
            effectiveGovernanceText: Self.governanceTierPairText(
                executionTier: effectiveExecutionTier,
                supervisorTier: effectiveSupervisorTier
            ),
            effectiveWorkOrderDepthText: Self.workOrderDepthText(
                rawValue: Self.stringValue(object["effective_supervisor_work_order_depth"])
            ),
            reviewPolicyText: Self.reviewPolicyText(rawValue: reviewPolicyMode),
            cadenceText: Self.cadenceText(
                progressHeartbeatSeconds: progressHeartbeatSeconds,
                reviewPulseSeconds: reviewPulseSeconds,
                brainstormReviewSeconds: brainstormReviewSeconds
            ),
            eventReviewText: Self.eventReviewText(
                enabled: Self.boolValue(object["event_driven_review_enabled"]),
                triggers: Self.stringArrayValue(object["event_review_triggers"])
            ),
            runtimeSurfaceText: Self.runtimeSurfaceText(from: object),
            governanceTruthText: governanceTruth.map(XTGovernanceTruthPresentation.displayText) ?? "(none)",
            validationText: Self.validationText(from: object)
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

    private static func governanceTierPairText(
        executionTier: String?,
        supervisorTier: String?
    ) -> String {
        let parts = [
            executionTier.flatMap(localizedExecutionTierLabel),
            supervisorTier.flatMap(localizedSupervisorTierLabel)
        ]
        .compactMap { $0 }
        return parts.isEmpty ? "(none)" : parts.joined(separator: " · ")
    }

    private static func localizedExecutionTierLabel(_ rawValue: String) -> String? {
        AXProjectExecutionTier(rawValue: rawValue)?.localizedDisplayLabel
    }

    private static func localizedSupervisorTierLabel(_ rawValue: String) -> String? {
        AXProjectSupervisorInterventionTier(rawValue: rawValue)?.localizedDisplayLabel
    }

    private static func workOrderDepthText(rawValue: String?) -> String {
        guard let rawValue,
              let depth = AXProjectSupervisorWorkOrderDepth(rawValue: rawValue) else {
            return "(none)"
        }

        let english: String
        switch depth {
        case .none:
            english = "None"
        case .brief:
            english = "Brief"
        case .milestoneContract:
            english = "Milestone Contract"
        case .executionReady:
            english = "Execution Ready"
        case .stepLockedRescue:
            english = "Step-Locked Rescue"
        }
        return ProjectGovernanceActivityDisplay.displayValue(label: "work_order_depth", value: english)
    }

    private static func reviewPolicyText(rawValue: String?) -> String {
        guard let rawValue,
              let mode = AXProjectReviewPolicyMode(rawValue: rawValue) else {
            return "(none)"
        }
        return "审查 \(mode.localizedShortLabel)"
    }

    private static func cadenceText(
        progressHeartbeatSeconds: Int?,
        reviewPulseSeconds: Int?,
        brainstormReviewSeconds: Int?
    ) -> String {
        var parts: [String] = []
        if let progressHeartbeatSeconds {
            parts.append("心跳 \(durationText(progressHeartbeatSeconds))")
        }
        if let reviewPulseSeconds {
            parts.append("脉冲 \(durationText(reviewPulseSeconds))")
        }
        if let brainstormReviewSeconds {
            parts.append("脑暴 \(durationText(brainstormReviewSeconds))")
        }
        return parts.isEmpty ? "(none)" : parts.joined(separator: " / ")
    }

    private static func durationText(_ seconds: Int) -> String {
        guard seconds > 0 else { return "关闭" }
        if seconds % 3600 == 0 {
            return "\(seconds / 3600)小时"
        }
        if seconds % 60 == 0 {
            return "\(seconds / 60)分钟"
        }
        return "\(seconds)秒"
    }

    private static func eventReviewText(
        enabled: Bool?,
        triggers: [String]
    ) -> String {
        guard enabled == true else { return "关闭" }
        let normalizedTriggers = triggers
            .map(localizedReviewTriggerLabel)
            .filter { !$0.isEmpty }
        guard !normalizedTriggers.isEmpty else { return "开启" }
        return "开启 · " + normalizedTriggers.joined(separator: " | ")
    }

    private static func localizedReviewTriggerLabel(_ rawValue: String) -> String {
        switch AXProjectReviewTrigger(rawValue: rawValue) {
        case .periodicHeartbeat:
            return "周期心跳"
        case .periodicPulse:
            return "周期脉冲审查"
        case .failureStreak:
            return "连续失败"
        case .noProgressWindow:
            return "进展停滞"
        case .blockerDetected:
            return "发现阻塞"
        case .planDrift:
            return "计划漂移"
        case .preHighRiskAction:
            return "高风险前审查"
        case .preDoneSummary:
            return "完成前审查"
        case .manualRequest:
            return "手动请求"
        case .userOverride:
            return "用户覆盖"
        case nil:
            return rawValue
        }
    }

    private static func runtimeSurfaceText(
        from object: [String: JSONValue]
    ) -> String {
        let configuredMode = runtimeSurfaceModeText(
            stringValue(
                preferredJSONValue(
                    object["runtime_surface_configured"],
                    object["runtime_surface_preset"]
                )
            )
        )
        let effectiveMode = runtimeSurfaceModeText(
            stringValue(object["effective_runtime_surface"])
        )
        let hubOverride = runtimeSurfaceOverrideText(
            stringValue(object["runtime_surface_hub_override"])
        )
        let remoteOverride = runtimeSurfaceOverrideText(
            stringValue(object["runtime_surface_remote_override"])
        )
        let remoteSource = stringValue(object["runtime_surface_remote_override_source"])
        let ttlSeconds = intValue(object["runtime_surface_ttl_sec"])
        let remainingSeconds = intValue(object["runtime_surface_remaining_sec"])
        let expired = boolValue(object["runtime_surface_expired"]) ?? false
        let killSwitchEngaged = boolValue(object["runtime_surface_kill_switch_engaged"]) ?? false

        var parts: [String] = []
        if configuredMode != "(none)" && effectiveMode != "(none)" && configuredMode != effectiveMode {
            parts.append("执行面 \(configuredMode) -> \(effectiveMode)")
        } else if effectiveMode != "(none)" {
            parts.append("执行面 \(effectiveMode)")
        } else if configuredMode != "(none)" {
            parts.append("执行面 \(configuredMode)")
        }

        if hubOverride != "无" && hubOverride != "(none)" {
            parts.append("Hub 收束 \(hubOverride)")
        }
        if remoteOverride != "无" && remoteOverride != "(none)" {
            if let remoteSource {
                parts.append("远端收束 \(remoteOverride) @ \(remoteSource)")
            } else {
                parts.append("远端收束 \(remoteOverride)")
            }
        }
        if let ttlSeconds {
            parts.append("TTL \(durationText(ttlSeconds))")
        }
        if let remainingSeconds {
            parts.append("剩余 \(durationText(max(0, remainingSeconds)))")
        }
        if expired {
            parts.append("已过期")
        }
        if killSwitchEngaged {
            parts.append("紧急回收")
        }

        return parts.isEmpty ? "(none)" : parts.joined(separator: " · ")
    }

    private static func runtimeSurfaceModeText(_ rawValue: String?) -> String {
        guard let rawValue,
              let mode = AXProjectRuntimeSurfaceMode(rawValue: rawValue) else {
            return "(none)"
        }
        return mode.displayName
    }

    private static func runtimeSurfaceOverrideText(_ rawValue: String?) -> String {
        guard let rawValue,
              let mode = AXProjectRuntimeSurfaceHubOverrideMode(rawValue: rawValue) else {
            return "(none)"
        }
        return mode.displayName
    }

    private static func validationText(from object: [String: JSONValue]) -> String {
        let invalidReasons = stringArrayValue(object["invalid_reasons"])
        let warningReasons = stringArrayValue(object["warning_reasons"])
        let shouldFailClosed = boolValue(object["should_fail_closed"]) ?? false

        var parts: [String] = []
        if shouldFailClosed {
            parts.append("保护性收束")
        }
        if !invalidReasons.isEmpty {
            parts.append("无效原因: \(invalidReasons.joined(separator: ", "))")
        }
        if !warningReasons.isEmpty {
            parts.append("警告原因: \(warningReasons.joined(separator: ", "))")
        }
        return parts.isEmpty ? "无" : parts.joined(separator: " · ")
    }

    private static func automationSnapshot(
        for ctx: AXProjectContext,
        now: Date
    ) -> AutomationSnapshot {
        let rows = xtAutomationReadRawLogRows(for: ctx)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000.0)
        let recentEvents = parseAutomationEvents(from: rows, nowMs: nowMs)
        guard let checkpointSummary = xtAutomationLatestPersistedCheckpointSummary(from: rows) else {
            return AutomationSnapshot(latest: nil, recentEvents: recentEvents)
        }

        let checkpoint = checkpointSummary.checkpoint
        let projectID = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        let report = xtAutomationLoadExecutionReport(for: checkpoint.runID, ctx: ctx)
        let retryPackage = xtAutomationLoadRetryPackage(
            forRetryRunID: checkpoint.runID,
            projectID: projectID,
            ctx: ctx
        )
        let blocker = report?.structuredBlocker
            ?? retryPackage?.sourceBlocker
            ?? xtAutomationStructuredBlocker(
                finalState: checkpoint.state,
                holdReason: report?.holdReason ?? "",
                detail: report?.detail ?? "",
                verificationReport: report?.verificationReport,
                currentStepID: checkpoint.currentStepID,
                currentStepTitle: checkpoint.currentStepTitle,
                currentStepState: checkpoint.currentStepState,
                currentStepSummary: checkpoint.currentStepSummary
            )
        let recoveryCandidate = xtAutomationLatestRecoveryCandidateSummary(
            from: rows,
            preferredRunID: checkpoint.runID,
            now: now.timeIntervalSince1970
        )

        return AutomationSnapshot(
            latest: AutomationSummary(
                runID: checkpoint.runID,
                stateText: localizedAutomationRunState(checkpoint.state),
                stepText: automationStepText(
                    stepID: checkpoint.currentStepID,
                    stepTitle: checkpoint.currentStepTitle,
                    stepState: checkpoint.currentStepState,
                    stepSummary: checkpoint.currentStepSummary
                ),
                verificationText: automationVerificationText(report?.verificationReport),
                verificationContractText: automationVerificationContractText(report?.verificationReport?.contract),
                blockerText: blocker.map(automationBlockerText) ?? "(none)",
                retryText: automationRetryText(retryPackage),
                retryVerificationContractText: automationRetryVerificationContractText(
                    retryPackage?.revisedVerificationContract
                        ?? retryPackage?.runtimePatchOverlay.flatMap {
                            XTAutomationVerificationContractSupport.contract(
                                from: $0.normalized().mergePatch["verification_contract"]
                            )
                        }
                ),
                recoveryText: automationRecoveryText(
                    candidate: recoveryCandidate,
                    checkpoint: checkpoint
                ),
                handoffText: report?.handoffArtifactPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? report!.handoffArtifactPath!
                    : ProjectGovernanceActivityDisplay.noneText,
                auditRef: report?.auditRef.isEmpty == false ? report!.auditRef : checkpoint.auditRef
            ),
            recentEvents: recentEvents
        )
    }

    private static func parseAutomationEvents(
        from rows: [[String: Any]],
        limit: Int = 5,
        nowMs: Int64
    ) -> [AutomationEventSummary] {
        guard limit > 0 else { return [] }
        let events = rows.enumerated().compactMap { index, row -> (createdAt: Double, index: Int, summary: AutomationEventSummary)? in
            guard let type = rawString(row["type"]) else { return nil }
            switch type {
            case "automation_execution", "automation_retry", "automation_checkpoint", "automation_run_launch", "automation_verification":
                break
            default:
                return nil
            }
            let createdAt = rawDouble(row["created_at"]) ?? 0
            return (
                createdAt: createdAt,
                index: index,
                summary: makeAutomationEventSummary(
                    row: row,
                    rowIndex: index,
                    nowMs: nowMs
                )
            )
        }

        return events
            .sorted {
                if $0.createdAt != $1.createdAt {
                    return $0.createdAt > $1.createdAt
                }
                return $0.index > $1.index
            }
            .prefix(limit)
            .map(\.summary)
    }

    private static func makeAutomationEventSummary(
        row: [String: Any],
        rowIndex: Int,
        nowMs: Int64
    ) -> AutomationEventSummary {
        let type = rawString(row["type"]) ?? "automation"
        let createdAtMs = Int64((rawDouble(row["created_at"]) ?? 0) * 1000.0)
        let runID = rawString(row["run_id"])
            ?? rawString(row["retry_run_id"])
            ?? rawString(row["source_run_id"])
            ?? "(none)"
        let stepText = automationStepText(
            stepID: rawString(row["current_step_id"]),
            stepTitle: rawString(row["current_step_title"]),
            stepState: rawString(row["current_step_state"]).flatMap(XTAutomationRunStepState.init(rawValue:)),
            stepSummary: rawString(row["current_step_summary"])
        )
        let verificationText = automationVerificationText(from: row) ?? "(none)"
        let verificationContractText = automationVerificationContractText(from: row)
        let blocker = rawDict(row["blocker"]).flatMap(automationBlockerText)
            ?? rawDict(row["source_blocker"]).flatMap(automationBlockerText)
            ?? rawString(row["blocker_summary"])
            ?? rawString(row["blocker_code"])
            ?? "(none)"
        let retryText = rawDict(row["retry_reason_descriptor"]).flatMap(automationRetryText)
            ?? xtAutomationFirstNonEmpty([
                rawString(row["retry_reason"]),
                rawString(row["retry_strategy"])
            ]) ?? "(none)"
        let retryVerificationContractText = automationRetryVerificationContractText(from: row)
        let detailText = xtAutomationFirstNonEmpty([
            rawString(row["detail"]),
            rawString(row["planning_summary"]),
            rawString(row["hold_reason"])
        ]) ?? "(none)"

        return AutomationEventSummary(
            eventID: "automation-\(type)-\(createdAtMs)-\(rowIndex)",
            createdAtText: timestampText(ms: createdAtMs, nowMs: nowMs),
            eventTypeText: localizedAutomationEventType(row),
            runID: runID,
            stateText: localizedAutomationEventState(row),
            stepText: stepText,
            verificationText: verificationText,
            verificationContractText: verificationContractText,
            blockerText: blocker,
            retryText: retryText,
            retryVerificationContractText: retryVerificationContractText,
            detailText: detailText,
            auditRef: rawString(row["audit_ref"]) ?? "(none)"
        )
    }

    private static func localizedAutomationRunState(_ state: XTAutomationRunState) -> String {
        switch state {
        case .queued:
            return "排队中"
        case .running:
            return "运行中"
        case .blocked:
            return "受阻"
        case .takeover:
            return "等待接管"
        case .delivered:
            return "已交付"
        case .failed:
            return "失败"
        case .downgraded:
            return "已降级"
        }
    }

    private static func localizedAutomationEventType(_ row: [String: Any]) -> String {
        let type = rawString(row["type"]) ?? "automation"
        switch type {
        case "automation_run_launch":
            return "启动运行"
        case "automation_checkpoint":
            return "写入检查点"
        case "automation_verification":
            return "验证完成"
        case "automation_execution":
            return (rawString(row["phase"]) == "completed") ? "执行完成" : "执行开始"
        case "automation_retry":
            switch rawString(row["status"]) ?? "" {
            case "scheduled":
                return "已排队重试"
            case "pending":
                return "等待自动重试"
            case "failed":
                return "重试调度失败"
            case "suppressed":
                return "重试被抑制"
            default:
                return "重试事件"
            }
        default:
            return type
        }
    }

    private static func localizedAutomationEventState(_ row: [String: Any]) -> String {
        if (rawString(row["type"]) ?? "") == "automation_verification",
           let verificationState = automationVerificationStateText(from: row) {
            return verificationState
        }
        if let finalState = rawString(row["final_state"]).flatMap(XTAutomationRunState.init(rawValue:)) {
            return localizedAutomationRunState(finalState)
        }
        if let state = rawString(row["state"]).flatMap(XTAutomationRunState.init(rawValue:)) {
            return localizedAutomationRunState(state)
        }
        if let status = rawString(row["status"]) {
            switch status {
            case "scheduled":
                return "已排队"
            case "pending":
                return "待继续"
            case "failed":
                return "失败"
            case "suppressed":
                return "已抑制"
            default:
                return status
            }
        }
        return "(none)"
    }

    private static func automationStepText(
        stepID: String?,
        stepTitle: String?,
        stepState: XTAutomationRunStepState?,
        stepSummary: String?
    ) -> String {
        let title = xtAutomationFirstNonEmpty([stepTitle, stepID]) ?? ""
        let summary = stepSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let state = stepState?.displayName ?? ""
        let parts = [title, state, summary].filter { !$0.isEmpty }
        return parts.isEmpty ? "(none)" : parts.joined(separator: " · ")
    }

    private static func automationBlockerText(
        _ blocker: XTAutomationBlockerDescriptor
    ) -> String {
        xtAutomationFirstNonEmpty([blocker.summary, blocker.code]) ?? "(none)"
    }

    private static func automationBlockerText(
        _ blocker: [String: Any]
    ) -> String? {
        xtAutomationFirstNonEmpty([
            rawString(blocker["summary"]),
            rawString(blocker["code"])
        ])
    }

    private static func automationRetryText(
        _ retryPackage: XTAutomationRetryPackage?
    ) -> String {
        guard let retryPackage else { return "(none)" }
        if let descriptor = retryPackage.retryReasonDescriptor {
            return automationRetryText([
                "summary": descriptor.summary,
                "strategy": descriptor.strategy,
                "code": descriptor.code
            ]) ?? "(none)"
        }
        return xtAutomationFirstNonEmpty([
            retryPackage.planningSummary,
            retryPackage.retryReason,
            retryPackage.retryStrategy
        ]) ?? "(none)"
    }

    private static func automationRetryText(
        _ descriptor: [String: Any]
    ) -> String? {
        xtAutomationFirstNonEmpty([
            rawString(descriptor["summary"]),
            rawString(descriptor["code"]),
            rawString(descriptor["strategy"])
        ])
    }

    private static func automationVerificationText(
        _ report: XTAutomationVerificationReport?
    ) -> String {
        guard let report else { return "(none)" }
        return automationVerificationText(
            required: report.required,
            executed: report.executed,
            commandCount: report.commandCount,
            passedCommandCount: report.passedCommandCount,
            holdReason: report.holdReason,
            detail: report.detail
        ) ?? "(none)"
    }

    private static func automationVerificationText(
        from row: [String: Any]
    ) -> String? {
        if let verification = rawDict(row["verification"]) {
            return automationVerificationText(
                required: rawBool(verification["required"]) ?? true,
                executed: rawBool(verification["executed"]) ?? false,
                commandCount: rawInt(verification["command_count"]) ?? 0,
                passedCommandCount: rawInt(verification["passed_command_count"]) ?? 0,
                holdReason: rawString(verification["hold_reason"]),
                detail: rawString(verification["detail"])
            )
        }
        guard (rawString(row["type"]) ?? "") == "automation_verification" else {
            return nil
        }
        return automationVerificationText(
            required: rawBool(row["required"]) ?? true,
            executed: rawBool(row["executed"]) ?? false,
            commandCount: rawInt(row["command_count"]) ?? 0,
            passedCommandCount: rawInt(row["passed_command_count"]) ?? 0,
            holdReason: rawString(row["hold_reason"]),
            detail: rawString(row["detail"])
        )
    }

    private static func automationVerificationContractText(
        _ contract: XTAutomationVerificationContract?
    ) -> String? {
        guard let contract else { return nil }
        return XTAutomationVerificationContractSupport.presentationText(
            contract,
            includePrefix: false
        )
    }

    private static func automationVerificationContractText(
        from row: [String: Any]
    ) -> String? {
        if let verification = rawDict(row["verification"]),
           let contract = XTAutomationVerificationContractSupport.contract(
                from: verification["verification_contract"]
           ) {
            return automationVerificationContractText(contract)
        }
        return automationVerificationContractText(
            XTAutomationVerificationContractSupport.contract(from: row["verification_contract"])
        )
    }

    private static func automationRetryVerificationContractText(
        _ contract: XTAutomationVerificationContract?
    ) -> String? {
        automationVerificationContractText(contract)
    }

    private static func automationRetryVerificationContractText(
        from row: [String: Any]
    ) -> String? {
        automationRetryVerificationContractText(
            XTAutomationVerificationContractSupport.contract(
                from: row["revised_verification_contract"] ?? row["verification_contract"]
            )
        )
    }

    private static func automationVerificationStateText(
        from row: [String: Any]
    ) -> String? {
        let required: Bool
        let executed: Bool
        let commandCount: Int
        let passedCommandCount: Int
        let holdReason: String?

        if let verification = rawDict(row["verification"]) {
            required = rawBool(verification["required"]) ?? true
            executed = rawBool(verification["executed"]) ?? false
            commandCount = rawInt(verification["command_count"]) ?? 0
            passedCommandCount = rawInt(verification["passed_command_count"]) ?? 0
            holdReason = rawString(verification["hold_reason"])
        } else if (rawString(row["type"]) ?? "") == "automation_verification" {
            required = rawBool(row["required"]) ?? true
            executed = rawBool(row["executed"]) ?? false
            commandCount = rawInt(row["command_count"]) ?? 0
            passedCommandCount = rawInt(row["passed_command_count"]) ?? 0
            holdReason = rawString(row["hold_reason"])
        } else {
            return nil
        }

        if !required {
            return "未要求"
        }
        if !executed {
            return "未执行"
        }

        let normalizedHoldReason = holdReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if normalizedHoldReason.isEmpty,
           commandCount > 0,
           passedCommandCount >= commandCount {
            return "已通过"
        }
        if normalizedHoldReason.isEmpty, commandCount == 0 {
            return "已执行"
        }
        return "失败"
    }

    private static func automationVerificationText(
        required: Bool,
        executed: Bool,
        commandCount: Int,
        passedCommandCount: Int,
        holdReason: String?,
        detail: String?
    ) -> String? {
        if !required {
            return "未要求验证"
        }

        let countsText = commandCount > 0 ? "\(passedCommandCount)/\(commandCount)" : nil
        let normalizedHoldReason = holdReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let headline: String
        if !executed {
            headline = "验证未执行"
        } else if normalizedHoldReason.isEmpty,
                  commandCount > 0,
                  passedCommandCount >= commandCount {
            headline = "验证通过\(countsText.map { " \($0)" } ?? "")"
        } else if normalizedHoldReason.isEmpty,
                  commandCount == 0 {
            headline = "验证已执行"
        } else {
            headline = "验证失败\(countsText.map { " \($0)" } ?? "")"
        }

        if let detailText = xtAutomationFirstNonEmpty([detail]),
           detailText != headline {
            return "\(headline) · \(detailText)"
        }
        return headline
    }

    private static func automationRecoveryText(
        candidate: XTAutomationPersistedRecoveryCandidateSummary?,
        checkpoint: XTAutomationRunCheckpoint
    ) -> String {
        guard let candidate else {
            if checkpoint.state == .blocked && checkpoint.retryAfterSeconds > 0 {
                return "等待 \(checkpoint.retryAfterSeconds) 秒后恢复"
            }
            return "(none)"
        }

        switch candidate.reason {
        case .latestVisibleRetryWait:
            return "等待重试窗口"
        case .latestVisibleRetryBudgetExhausted:
            return "重试额度已用尽"
        case .latestVisibleRecoverable:
            return "可恢复"
        case .latestVisibleStaleRecoverable:
            return "待回收旧运行"
        case .latestVisibleStableIdentityFailed:
            return "身份校验失败"
        case .latestVisibleActiveRun:
            return "当前有进行中运行"
        case .latestVisibleCancelled:
            return "已手动取消"
        case .latestVisibleSuperseded:
            return "已被后续运行替代"
        case .latestVisibleNotRecoverable:
            return "当前状态不可恢复"
        case .noRecoverableUnsupersededRun:
            return "没有可恢复运行"
        }
    }

    private static func rawString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func rawDouble(_ value: Any?) -> Double? {
        if let number = value as? Double {
            return number
        }
        if let number = value as? Int {
            return Double(number)
        }
        if let string = value as? String {
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func rawInt(_ value: Any?) -> Int? {
        if let number = value as? Int {
            return number
        }
        if let number = value as? Double {
            return Int(number)
        }
        if let string = value as? String {
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func rawBool(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        if let number = value as? Int {
            return number != 0
        }
        if let number = value as? Double {
            return number != 0
        }
        if let string = value as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1":
                return true
            case "false", "0":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private static func rawDict(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private static func preferredJSONValue(_ candidates: JSONValue?...) -> JSONValue? {
        candidates
            .compactMap { $0 }
            .first(where: isMeaningful)
    }

    private static func isMeaningful(_ value: JSONValue?) -> Bool {
        switch value {
        case .string(let raw)?:
            return !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .number?, .bool?, .array?, .object?:
            return true
        default:
            return false
        }
    }

    private static func stringValue(_ value: JSONValue?) -> String? {
        guard let trimmed = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func numberValue(_ value: JSONValue?) -> Double? {
        switch value {
        case .number(let number):
            return number
        case .string(let raw):
            return Double(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func intValue(_ value: JSONValue?) -> Int? {
        switch value {
        case .number(let number):
            return Int(number)
        case .string(let raw):
            return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func boolValue(_ value: JSONValue?) -> Bool? {
        switch value {
        case .bool(let value):
            return value
        case .string(let raw):
            let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch lowered {
            case "true", "1":
                return true
            case "false", "0":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private static func stringArrayValue(_ value: JSONValue?) -> [String] {
        guard case .array(let items)? = value else { return [] }
        return items.compactMap { item in
            stringValue(item)
        }
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
                    Text("展示当前项目最近一次治理配置更新、Supervisor 审查、指导注入、确认状态，以及下一次心跳 / 审查的计划时间。")
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

                latestConfigUpdateSection

                Divider()

                latestReviewSection

                Divider()

                pendingGuidanceSection

                Divider()

                latestGuidanceSection

                Divider()

                latestAutomationSection

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

    private var latestConfigUpdateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最新治理设置")
                .font(.caption.weight(.semibold))

            Text("这些设置只作用于当前项目，来自当前项目 `/.xterminal/config.json` 写入的治理 bundle 记录。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let update = presentation.latestConfigUpdate {
                GovernanceActivityRow(label: "updated_at", value: update.updatedAtText)
                GovernanceActivityRow(label: "configured_governance", value: update.configuredGovernanceText)
                GovernanceActivityRow(label: "effective_governance", value: update.effectiveGovernanceText)
                GovernanceActivityRow(label: "effective_work_order_depth", value: update.effectiveWorkOrderDepthText)
                GovernanceActivityRow(label: "review_policy_mode", value: update.reviewPolicyText)
                GovernanceActivityRow(label: "cadence", value: update.cadenceText)
                GovernanceActivityRow(label: "event_review", value: update.eventReviewText)
                GovernanceActivityRow(label: "runtime_surface", value: update.runtimeSurfaceText)
                GovernanceActivityRow(label: "governance_truth", value: update.governanceTruthText)
                GovernanceActivityRow(label: "validation", value: update.validationText)
            } else {
                Text("还没有治理设置变更记录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
                        GovernanceActivityRow(label: "next_safe_action", value: contract.userVisibleNextSafeActionText)
                        if let actions = contract.userVisibleRecommendedActionsText {
                            GovernanceActivityRow(label: "recommended_actions", value: actions)
                        }
                    }
                    GovernanceActivityRow(label: "guidance", value: guidance.guidanceSummaryText)
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

    private var latestAutomationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最新自动推进")
                .font(.caption.weight(.semibold))

            if let automation = presentation.latestAutomation {
                GovernanceActivityRow(label: "run_id", value: automation.runID)
                GovernanceActivityRow(label: "automation_state", value: automation.stateText)
                GovernanceActivityRow(label: "automation_step", value: automation.stepText)
                GovernanceActivityRow(label: "automation_verification", value: automation.verificationText)
                if let verificationContractText = automation.verificationContractText {
                    GovernanceActivityRow(
                        label: "automation_verification_contract",
                        value: verificationContractText
                    )
                }
                GovernanceActivityRow(label: "automation_blocker", value: automation.blockerText)
                GovernanceActivityRow(label: "automation_retry", value: automation.retryText)
                if let retryVerificationContractText = automation.retryVerificationContractText {
                    GovernanceActivityRow(
                        label: "automation_retry_verification_contract",
                        value: retryVerificationContractText
                    )
                }
                GovernanceActivityRow(label: "automation_recovery", value: automation.recoveryText)
                GovernanceActivityRow(label: "automation_handoff", value: automation.handoffText)
                GovernanceActivityRow(label: "audit_ref", value: automation.auditRef)
            } else {
                Text("还没有自动推进运行记录。")
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
                    GovernanceActivityRow(label: "next_safe_action", value: contract.userVisibleNextSafeActionText)
                    if let actions = contract.userVisibleRecommendedActionsText {
                        GovernanceActivityRow(label: "recommended_actions", value: actions)
                    }
                }
                GovernanceActivityRow(label: "guidance", value: guidance.guidanceSummaryText, accent: .primary)

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
            Text("Heartbeat / Review 时间线")
                .font(.caption.weight(.semibold))

            GovernanceActivityRow(label: "last_heartbeat", value: presentation.schedule.lastHeartbeatText)
            GovernanceActivityRow(label: "next_heartbeat", value: presentation.schedule.nextHeartbeatText)
            GovernanceActivityRow(label: "last_pulse_review", value: presentation.schedule.lastPulseReviewText)
            GovernanceActivityRow(label: "next_pulse_review", value: presentation.schedule.nextPulseReviewText)
            GovernanceActivityRow(label: "last_brainstorm_review", value: presentation.schedule.lastBrainstormReviewText)
            GovernanceActivityRow(label: "next_brainstorm_review", value: presentation.schedule.nextBrainstormReviewText)
            if let cadence = presentation.cadenceExplainability {
                GovernanceActivityRow(label: "configured_cadence", value: cadenceSummaryText(cadence, selector: \.configuredSeconds))
                GovernanceActivityRow(label: "recommended_cadence", value: cadenceSummaryText(cadence, selector: \.recommendedSeconds))
                GovernanceActivityRow(label: "effective_cadence", value: cadenceSummaryText(cadence, selector: \.effectiveSeconds))
                GovernanceActivityRow(label: "cadence_reason", value: cadenceReasonSummaryText(cadence))
                GovernanceActivityRow(label: "next_due_reason", value: cadenceDueReasonSummaryText(cadence))
            }
            GovernanceActivityRow(label: "heartbeat_quality_band", value: presentation.schedule.heartbeatQualityBandText)
            GovernanceActivityRow(label: "heartbeat_quality_score", value: presentation.schedule.heartbeatQualityScoreText)
            GovernanceActivityRow(label: "heartbeat_open_anomalies", value: presentation.schedule.heartbeatOpenAnomaliesText)
        }
    }

    private func cadenceSummaryText(
        _ cadence: SupervisorCadenceExplainability,
        selector: KeyPath<SupervisorCadenceDimensionExplainability, Int>
    ) -> String {
        [
            "心跳 \(governanceDisplayDurationLabel(cadence.progressHeartbeat[keyPath: selector]))",
            "脉冲 \(governanceDisplayDurationLabel(cadence.reviewPulse[keyPath: selector]))",
            "脑暴 \(governanceDisplayDurationLabel(cadence.brainstormReview[keyPath: selector]))"
        ].joined(separator: " · ")
    }

    private func cadenceReasonSummaryText(
        _ cadence: SupervisorCadenceExplainability
    ) -> String {
        [
            cadenceDimensionReasonLine("心跳", dimension: cadence.progressHeartbeat),
            cadenceDimensionReasonLine("脉冲", dimension: cadence.reviewPulse),
            cadenceDimensionReasonLine("脑暴", dimension: cadence.brainstormReview)
        ].joined(separator: " | ")
    }

    private func cadenceDueReasonSummaryText(
        _ cadence: SupervisorCadenceExplainability
    ) -> String {
        [
            cadenceDimensionDueLine("心跳", dimension: cadence.progressHeartbeat),
            cadenceDimensionDueLine("脉冲", dimension: cadence.reviewPulse),
            cadenceDimensionDueLine("脑暴", dimension: cadence.brainstormReview)
        ].joined(separator: " | ")
    }

    private func cadenceDimensionReasonLine(
        _ title: String,
        dimension: SupervisorCadenceDimensionExplainability
    ) -> String {
        "\(title)：\(localizedCadenceReasonCodes(dimension.effectiveReasonCodes))"
    }

    private func cadenceDimensionDueLine(
        _ title: String,
        dimension: SupervisorCadenceDimensionExplainability
    ) -> String {
        let state = dimension.isDue ? "已到期" : "未到期"
        return "\(title)：\(state)，\(localizedCadenceReasonCodes(dimension.nextDueReasonCodes))"
    }

    private func localizedCadenceReasonCodes(_ codes: [String]) -> String {
        HeartbeatGovernanceUserFacingText.cadenceReasonSummary(codes, empty: "无")
    }

    private func localizedCadenceReasonCode(_ code: String) -> String {
        HeartbeatGovernanceUserFacingText.cadenceReasonText(code) ?? code
    }

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近动态")
                .font(.caption.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("最近自动推进")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if presentation.recentAutomationEvents.isEmpty {
                    Text("还没有自动推进时间线。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(presentation.recentAutomationEvents) { event in
                        GovernanceHistoryCard(
                            title: "\(event.eventTypeText) · \(event.stateText)",
                            subtitle: "\(event.createdAtText) · run=\(event.runID)",
                            bodyText: event.detailText,
                            footnote: governanceHistoryFootnote(
                                ProjectGovernanceActivityDisplay.fieldLine("automation_step", value: event.stepText),
                                ProjectGovernanceActivityDisplay.fieldLine("automation_verification", value: event.verificationText),
                                event.verificationContractText.flatMap { text in
                                    ProjectGovernanceActivityDisplay.fieldLine(
                                        "automation_verification_contract",
                                        value: text
                                    )
                                },
                                ProjectGovernanceActivityDisplay.fieldLine("automation_blocker", value: event.blockerText),
                                ProjectGovernanceActivityDisplay.fieldLine("automation_retry", value: event.retryText),
                                event.retryVerificationContractText.flatMap { text in
                                    ProjectGovernanceActivityDisplay.fieldLine(
                                        "automation_retry_verification_contract",
                                        value: text
                                    )
                                },
                                ProjectGovernanceActivityDisplay.fieldLine("audit_ref", value: event.auditRef)
                            )
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("最近治理设置")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if presentation.recentConfigUpdates.isEmpty {
                    Text("还没有治理设置变更历史。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(presentation.recentConfigUpdates) { update in
                        GovernanceHistoryCard(
                            title: "\(ProjectGovernanceActivityDisplay.displayValue(label: "effective_governance", value: update.effectiveGovernanceText)) · \(ProjectGovernanceActivityDisplay.displayValue(label: "review_policy_mode", value: update.reviewPolicyText))",
                            subtitle: "\(ProjectGovernanceActivityDisplay.displayValue(label: "updated_at", value: update.updatedAtText)) · \(ProjectGovernanceActivityDisplay.displayValue(label: "runtime_surface", value: update.runtimeSurfaceText))",
                            bodyText: update.governanceTruthText,
                            footnote: governanceHistoryFootnote(
                                ProjectGovernanceActivityDisplay.fieldLine("configured_governance", value: update.configuredGovernanceText),
                                ProjectGovernanceActivityDisplay.fieldLine("cadence", value: update.cadenceText),
                                ProjectGovernanceActivityDisplay.fieldLine("event_review", value: update.eventReviewText),
                                ProjectGovernanceActivityDisplay.fieldLine("validation", value: update.validationText)
                            )
                        )
                    }
                }
            }

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
                            subtitle: "\(ProjectGovernanceActivityDisplay.displayValue(label: "created_at", value: review.createdAtText)) · \(ProjectGovernanceActivityDisplay.displayValue(label: "trigger", value: review.triggerText))",
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
                            subtitle: "\(ProjectGovernanceActivityDisplay.displayValue(label: "injected_at", value: guidance.injectedAtText)) · \(ProjectGovernanceActivityDisplay.displayValue(label: "safe_point", value: guidance.safePointText))",
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

private func governanceHistoryFootnote(_ parts: String?...) -> String {
    let filtered = parts
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !ProjectGovernanceActivityDisplay.isEmptyDisplayText($0) }
    return filtered.isEmpty ? ProjectGovernanceActivityDisplay.noneText : filtered.joined(separator: " · ")
}

private func governanceGuidanceBodyText(
    _ guidance: ProjectGovernanceActivityPresentation.GuidanceSummary
) -> String {
    guard let contract = guidance.contractSummary else {
        return guidance.guidanceSummaryText
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

    if contract.userVisibleNextSafeActionText != "(none)" {
        lines.append(ProjectGovernanceActivityDisplay.fieldLine("next_safe_action", value: contract.userVisibleNextSafeActionText))
    }

    return lines.joined(separator: "\n")
}

private func governanceGuidanceFootnote(
    _ guidance: ProjectGovernanceActivityPresentation.GuidanceSummary
) -> String {
    guard let contract = guidance.contractSummary else { return "" }
    return governanceHistoryFootnote(
        ProjectGovernanceActivityDisplay.fieldLine("contract_kind", value: contract.kindText),
        contract.userVisibleRecommendedActionsText.map {
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
    static let noneText = "无"

    static func fieldLabel(_ raw: String) -> String {
        switch raw {
        case "updated_at":
            return "更新时间"
        case "configured_governance":
            return "预设治理档"
        case "effective_governance":
            return "生效治理档"
        case "effective_work_order_depth":
            return "生效工单深度"
        case "review_policy_mode":
            return "审查模式"
        case "cadence":
            return "Heartbeat / Review 节奏"
        case "event_review":
            return "事件驱动审查"
        case "runtime_surface":
            return "执行面"
        case "governance_truth":
            return "治理真相"
        case "validation":
            return "治理校验"
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
        case "run_id":
            return "运行 ID"
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
        case "configured_cadence":
            return "已配置节奏"
        case "recommended_cadence":
            return "协议建议节奏"
        case "effective_cadence":
            return "当前生效节奏"
        case "cadence_reason":
            return "节奏生效原因"
        case "next_due_reason":
            return "到期判断"
        case "heartbeat_quality_band":
            return "最新质量档"
        case "heartbeat_quality_score":
            return "最新质量分"
        case "heartbeat_open_anomalies":
            return "打开异常"
        case "automation_state":
            return "运行状态"
        case "automation_step":
            return "当前步骤"
        case "automation_verification":
            return "验证状态"
        case "automation_verification_contract":
            return "验证合同"
        case "automation_blocker":
            return "自动推进阻塞"
        case "automation_retry":
            return "重试策略"
        case "automation_retry_verification_contract":
            return "重试验证合同"
        case "automation_recovery":
            return "恢复状态"
        case "automation_handoff":
            return "交接产物"
        default:
            return raw
        }
    }

    static func displayValue(label: String, value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return value }
        if trimmed == "(none)" {
            return noneText
        }

        switch label {
        case "updated_at",
             "created_at",
             "injected_at",
             "ack_updated_at",
             "last_heartbeat",
             "next_heartbeat",
             "last_pulse_review",
             "next_pulse_review",
             "last_brainstorm_review",
             "next_brainstorm_review":
            return localizedTimestampText(trimmed)
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

    static func isEmptyDisplayText(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return trimmed == "(none)"
            || trimmed == noneText
            || trimmed.hasSuffix("：(none)")
            || trimmed.hasSuffix("：\(noneText)")
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

    private static func localizedTimestampText(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return value }
        if trimmed == "(none)" {
            return noneText
        }

        let parts = trimmed.components(separatedBy: " · ")
        guard parts.count >= 2 else {
            return localizedRelativeTime(trimmed)
        }

        let absolute = parts.dropLast().joined(separator: " · ")
        let relative = parts.last ?? ""
        return "\(absolute) · \(localizedRelativeTime(relative))"
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
                if part.hasSuffix("d"), let days = Int(part.dropLast()) {
                    return "\(days)天"
                }
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
