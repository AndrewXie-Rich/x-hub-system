import Foundation

struct SupervisorReviewPolicyDecision: Equatable, Sendable {
    var shouldReview: Bool
    var reviewLevel: SupervisorReviewLevel
    var reviewMemoryCeiling: XTMemoryServingProfile
    var interventionMode: SupervisorGuidanceInterventionMode
    var safePointPolicy: SupervisorGuidanceSafePointPolicy
    var ackRequired: Bool
    var policyReason: String
}

struct SupervisorHeartbeatReviewCandidate: Equatable, Sendable {
    var projectId: String
    var trigger: SupervisorReviewTrigger
    var runKind: SupervisorReviewRunKind
    var reviewLevel: SupervisorReviewLevel
    var priority: Int
    var policyReason: String
}

enum SupervisorCadenceDimension: String, Codable, CaseIterable, Sendable {
    case progressHeartbeat = "progress_heartbeat"
    case reviewPulse = "review_pulse"
    case brainstormReview = "brainstorm_review"
}

struct SupervisorCadenceDimensionExplainability: Codable, Equatable, Sendable {
    var dimension: SupervisorCadenceDimension
    var configuredSeconds: Int
    var recommendedSeconds: Int
    var effectiveSeconds: Int
    var effectiveReasonCodes: [String]
    var nextDueAtMs: Int64
    var nextDueReasonCodes: [String]
    var isDue: Bool
}

struct SupervisorCadenceExplainability: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_cadence_explainability.v1"

    var schemaVersion: String
    var progressHeartbeat: SupervisorCadenceDimensionExplainability
    var reviewPulse: SupervisorCadenceDimensionExplainability
    var brainstormReview: SupervisorCadenceDimensionExplainability
    var eventFollowUpCooldownSeconds: Int
    var reasonCodes: [String]
    var nextDueReasonCodes: [String]

    init(
        progressHeartbeat: SupervisorCadenceDimensionExplainability,
        reviewPulse: SupervisorCadenceDimensionExplainability,
        brainstormReview: SupervisorCadenceDimensionExplainability,
        eventFollowUpCooldownSeconds: Int
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.progressHeartbeat = progressHeartbeat
        self.reviewPulse = reviewPulse
        self.brainstormReview = brainstormReview
        self.eventFollowUpCooldownSeconds = eventFollowUpCooldownSeconds
        reasonCodes = Array(
            Set(
                progressHeartbeat.effectiveReasonCodes
                    + reviewPulse.effectiveReasonCodes
                    + brainstormReview.effectiveReasonCodes
            )
        ).sorted()
        nextDueReasonCodes = Array(
            Set(
                progressHeartbeat.nextDueReasonCodes
                    + reviewPulse.nextDueReasonCodes
                    + brainstormReview.nextDueReasonCodes
            )
        ).sorted()
    }
}

enum SupervisorReviewPolicyEngine {
    static func eventFollowUpCadenceLabel(
        governance: AXProjectResolvedGovernanceState
    ) -> String {
        let cooldown = eventReviewCooldownSeconds(governance: governance)
        let cadence: String
        switch cooldown {
        case ...120:
            cadence = "tight"
        case ...300:
            cadence = "active"
        case ...900:
            cadence = "balanced"
        default:
            cadence = "light"
        }

        return "cadence=\(cadence) · blocker cooldown≈\(cooldown)s"
    }

    static func eventFollowUpCadenceSummary(
        governance: AXProjectResolvedGovernanceState
    ) -> String {
        let adaptation = governance.supervisorAdaptation
        let strengthBand = adaptation.projectAIStrengthProfile?.strengthBand ?? .unknown
        return "\(eventFollowUpCadenceLabel(governance: governance)) · tier=\(governance.effectiveBundle.supervisorInterventionTier.displayName) · depth=\(adaptation.effectiveWorkOrderDepth.displayName) · strength=\(strengthBand.displayName)"
    }

    static func cadenceExplainability(
        governance: AXProjectResolvedGovernanceState,
        schedule: SupervisorReviewScheduleState,
        nowMs: Int64
    ) -> SupervisorCadenceExplainability {
        let configuredSchedule = governance.configuredBundle.schedule
        let recommendedBaseSchedule = AXProjectGovernanceBundle.recommended(
            for: governance.configuredBundle.executionTier,
            supervisorInterventionTier: governance.supervisorAdaptation.recommendedSupervisorTier
        ).schedule

        let progressHeartbeat = cadenceDimensionExplainability(
            dimension: .progressHeartbeat,
            configuredSeconds: configuredSchedule.progressHeartbeatSeconds,
            recommendedSeconds: recommendedCadenceSeconds(
                for: .progressHeartbeat,
                baseRecommendedSeconds: recommendedBaseSchedule.progressHeartbeatSeconds,
                schedule: schedule
            ),
            governance: governance,
            schedule: schedule,
            nowMs: nowMs
        )
        let reviewPulse = cadenceDimensionExplainability(
            dimension: .reviewPulse,
            configuredSeconds: configuredSchedule.reviewPulseSeconds,
            recommendedSeconds: recommendedCadenceSeconds(
                for: .reviewPulse,
                baseRecommendedSeconds: recommendedBaseSchedule.reviewPulseSeconds,
                schedule: schedule
            ),
            governance: governance,
            schedule: schedule,
            nowMs: nowMs
        )
        let brainstormReview = cadenceDimensionExplainability(
            dimension: .brainstormReview,
            configuredSeconds: configuredSchedule.brainstormReviewSeconds,
            recommendedSeconds: recommendedCadenceSeconds(
                for: .brainstormReview,
                baseRecommendedSeconds: recommendedBaseSchedule.brainstormReviewSeconds,
                schedule: schedule
            ),
            governance: governance,
            schedule: schedule,
            nowMs: nowMs
        )

        return SupervisorCadenceExplainability(
            progressHeartbeat: progressHeartbeat,
            reviewPulse: reviewPulse,
            brainstormReview: brainstormReview,
            eventFollowUpCooldownSeconds: eventReviewCooldownSeconds(governance: governance)
        )
    }

    static func runtimeOpenAnomalies(
        governance: AXProjectResolvedGovernanceState,
        schedule: SupervisorReviewScheduleState,
        nowMs: Int64,
        cadence: SupervisorCadenceExplainability? = nil
    ) -> [HeartbeatAnomalyNote] {
        var anomalies = schedule.openAnomalies
        if !anomalies.contains(where: { $0.anomalyType == .missingHeartbeat }),
           let missingHeartbeat = synthesizedMissingHeartbeatAnomaly(
                governance: governance,
                schedule: schedule,
                nowMs: nowMs,
                cadence: cadence
           ) {
            anomalies.append(missingHeartbeat)
        }

        anomalies.sort { lhs, rhs in
            if lhs.severity.rank != rhs.severity.rank {
                return lhs.severity.rank > rhs.severity.rank
            }
            if lhs.detectedAtMs != rhs.detectedAtMs {
                return lhs.detectedAtMs > rhs.detectedAtMs
            }
            return lhs.anomalyType.rawValue < rhs.anomalyType.rawValue
        }
        return anomalies
    }

    static func resolve(
        governance: AXProjectResolvedGovernanceState,
        trigger: SupervisorReviewTrigger,
        requestedReviewLevel: SupervisorReviewLevel,
        verdict: SupervisorReviewVerdict,
        requestedDeliveryMode: SupervisorGuidanceDeliveryMode,
        requestedAckRequired: Bool,
        runKind: SupervisorReviewRunKind
    ) -> SupervisorReviewPolicyDecision {
        guard triggerAllowed(governance: governance, trigger: trigger, runKind: runKind) else {
            return SupervisorReviewPolicyDecision(
                shouldReview: false,
                reviewLevel: requestedReviewLevel,
                reviewMemoryCeiling: governance.supervisorReviewMemoryCeiling,
                interventionMode: .observeOnly,
                safePointPolicy: .nextToolBoundary,
                ackRequired: false,
                policyReason: "trigger_not_enabled_by_review_policy"
            )
        }

        let effectiveWorkOrderDepth = governance.supervisorAdaptation.effectiveWorkOrderDepth
        let resolvedReviewLevel = max(
            requestedReviewLevel,
            minimumReviewLevel(
                for: governance.effectiveBundle.supervisorInterventionTier,
                runKind: runKind,
                trigger: trigger
            ),
            minimumReviewLevel(
                for: effectiveWorkOrderDepth,
                runKind: runKind,
                trigger: trigger
            )
        )
        let ackRequired = requestedAckRequired
            || (governance.effectiveBundle.supervisorInterventionTier.defaultAckRequired && resolvedReviewLevel != .r1Pulse)
            || (effectiveWorkOrderDepth >= .executionReady && resolvedReviewLevel != .r1Pulse)
            || effectiveWorkOrderDepth == .stepLockedRescue
        let interventionMode = resolvedInterventionMode(
            deliveryMode: requestedDeliveryMode,
            supervisorTier: governance.effectiveBundle.supervisorInterventionTier,
            workOrderDepth: effectiveWorkOrderDepth,
            reviewLevel: resolvedReviewLevel,
            verdict: verdict,
            ackRequired: ackRequired
        )
        let safePointPolicy = resolvedSafePointPolicy(
            deliveryMode: requestedDeliveryMode,
            interventionMode: interventionMode,
            reviewLevel: resolvedReviewLevel,
            workOrderDepth: effectiveWorkOrderDepth
        )

        return SupervisorReviewPolicyDecision(
            shouldReview: true,
            reviewLevel: resolvedReviewLevel,
            reviewMemoryCeiling: governance.supervisorReviewMemoryCeiling,
            interventionMode: interventionMode,
            safePointPolicy: safePointPolicy,
            ackRequired: ackRequired,
            policyReason: "governance_review_policy_resolved:tier=\(governance.effectiveBundle.supervisorInterventionTier.rawValue):depth=\(effectiveWorkOrderDepth.rawValue)"
        )
    }

    static func heartbeatCandidate(
        governance: AXProjectResolvedGovernanceState,
        schedule: SupervisorReviewScheduleState,
        blockerDetected: Bool,
        nowMs: Int64
    ) -> SupervisorHeartbeatReviewCandidate? {
        let triggers = Set(governance.effectiveBundle.schedule.eventReviewTriggers)
        let cooldownMs = Int64(eventReviewCooldownSeconds(governance: governance)) * 1000
        let effectiveWorkOrderDepth = governance.supervisorAdaptation.effectiveWorkOrderDepth
        let cadence = cadenceExplainability(
            governance: governance,
            schedule: schedule,
            nowMs: nowMs
        )
        let openAnomalies = runtimeOpenAnomalies(
            governance: governance,
            schedule: schedule,
            nowMs: nowMs,
            cadence: cadence
        )
        let qualityReason = heartbeatQualityReason(
            schedule: schedule,
            openAnomalies: openAnomalies
        )

        if governance.effectiveBundle.schedule.eventDrivenReviewEnabled,
           triggers.contains(.preDoneSummary),
           hasPendingWeakDoneClaim(openAnomalies: openAnomalies),
           !reviewedRecently(
               schedule: schedule,
               trigger: .preDoneSummary,
               nowMs: nowMs,
               cooldownMs: max(Int64(60_000), cooldownMs / 2)
           ) {
            return SupervisorHeartbeatReviewCandidate(
                projectId: governance.projectId,
                trigger: .preDoneSummary,
                runKind: .eventDriven,
                reviewLevel: max(
                    minimumReviewLevel(
                        for: governance.effectiveBundle.supervisorInterventionTier,
                        runKind: .eventDriven,
                        trigger: .preDoneSummary
                    ),
                    minimumReviewLevel(
                        for: effectiveWorkOrderDepth,
                        runKind: .eventDriven,
                        trigger: .preDoneSummary
                    )
                ),
                priority: effectiveWorkOrderDepth == .stepLockedRescue ? 380 : 340,
                policyReason: "heartbeat_anomaly=weak_done_claim\(qualityReason) depth=\(effectiveWorkOrderDepth.rawValue)"
            )
        }

        let blockerEscalationAnomaly = pendingBlockerEscalationAnomaly(openAnomalies: openAnomalies)
        let anomalyEscalatesToBlocker = blockerEscalationAnomaly != nil

        if (blockerDetected || anomalyEscalatesToBlocker),
           governance.effectiveBundle.schedule.eventDrivenReviewEnabled,
           triggers.contains(.blockerDetected),
           !reviewedRecently(schedule: schedule, trigger: .blockerDetected, nowMs: nowMs, cooldownMs: cooldownMs) {
            return SupervisorHeartbeatReviewCandidate(
                projectId: governance.projectId,
                trigger: .blockerDetected,
                runKind: .eventDriven,
                reviewLevel: max(
                    minimumReviewLevel(
                        for: governance.effectiveBundle.supervisorInterventionTier,
                        runKind: .eventDriven,
                        trigger: .blockerDetected
                    ),
                    minimumReviewLevel(
                        for: effectiveWorkOrderDepth,
                        runKind: .eventDriven,
                        trigger: .blockerDetected
                    )
                ),
                priority: effectiveWorkOrderDepth == .stepLockedRescue ? 360 : 310,
                policyReason: (anomalyEscalatesToBlocker
                               ? "heartbeat_anomaly=\(blockerEscalationAnomaly?.rawValue ?? HeartbeatAnomalyType.queueStall.rawValue)\(qualityReason)"
                               : "event_trigger=blocker_detected\(qualityReason)") + " depth=\(effectiveWorkOrderDepth.rawValue)"
            )
        }

        if shouldRunBrainstorm(
            governance: governance,
            schedule: schedule,
            cadence: cadence,
            openAnomalies: openAnomalies
        ) {
            let reasonPrefix = pendingBrainstormEscalationAnomaly(openAnomalies: openAnomalies).map {
                "heartbeat_anomaly=\($0.rawValue)"
            } ?? "brainstorm_review_due"
            return SupervisorHeartbeatReviewCandidate(
                projectId: governance.projectId,
                trigger: .noProgressWindow,
                runKind: .brainstorm,
                reviewLevel: max(
                    minimumReviewLevel(
                        for: governance.effectiveBundle.supervisorInterventionTier,
                        runKind: .brainstorm,
                        trigger: .noProgressWindow
                    ),
                    minimumReviewLevel(
                        for: effectiveWorkOrderDepth,
                        runKind: .brainstorm,
                        trigger: .noProgressWindow
                    )
                ),
                priority: effectiveWorkOrderDepth >= .executionReady ? 230 : 210,
                policyReason: "\(reasonPrefix)\(qualityReason) depth=\(effectiveWorkOrderDepth.rawValue)"
            )
        }

        if shouldRunPulse(
            governance: governance,
            schedule: schedule,
            cadence: cadence,
            openAnomalies: openAnomalies
        ) {
            let reasonPrefix = pendingPulseEscalationAnomaly(
                schedule: schedule,
                openAnomalies: openAnomalies
            ).map {
                "heartbeat_anomaly=\($0.rawValue)"
            } ?? (hasPendingPulseEscalation(
                schedule: schedule,
                openAnomalies: openAnomalies
            )
                ? "heartbeat_quality_degraded"
                : "pulse_review_due"
            )
            return SupervisorHeartbeatReviewCandidate(
                projectId: governance.projectId,
                trigger: .periodicPulse,
                runKind: .pulse,
                reviewLevel: max(
                    minimumReviewLevel(
                        for: governance.effectiveBundle.supervisorInterventionTier,
                        runKind: .pulse,
                        trigger: .periodicPulse
                    ),
                    minimumReviewLevel(
                        for: effectiveWorkOrderDepth,
                        runKind: .pulse,
                        trigger: .periodicPulse
                    )
                ),
                priority: effectiveWorkOrderDepth >= .executionReady ? 120 : 100,
                policyReason: "\(reasonPrefix)\(qualityReason) depth=\(effectiveWorkOrderDepth.rawValue)"
            )
        }

        return nil
    }

    static func recoveryDecision(
        schedule: SupervisorReviewScheduleState,
        laneSnapshot: SupervisorLaneHealthSnapshot?,
        reviewCandidate: SupervisorHeartbeatReviewCandidate? = nil,
        openAnomalies: [HeartbeatAnomalyNote]? = nil
    ) -> HeartbeatRecoveryDecision? {
        let anomalyTypes = uniqueSorted((openAnomalies ?? schedule.openAnomalies).map(\.anomalyType))
        let blockedReasons = uniqueSorted((laneSnapshot?.lanes ?? []).compactMap(\.blockedReason))
        let blockedCount = laneSnapshot?.summary.blocked ?? 0
        let stalledCount = laneSnapshot?.summary.stalled ?? 0
        let failedCount = laneSnapshot?.summary.failed ?? 0
        let recoveringCount = laneSnapshot?.summary.recovering ?? 0
        let strategyCandidate = reviewCandidate.flatMap { candidate in
            candidate.reviewLevel == .r1Pulse ? nil : candidate
        }

        let hasAnomalySignal = !anomalyTypes.isEmpty
        let hasLaneVitalitySignal = blockedCount > 0 || stalledCount > 0 || failedCount > 0 || recoveringCount > 0
        guard hasAnomalySignal || hasLaneVitalitySignal || strategyCandidate != nil else {
            return nil
        }

        let grantFollowUpReasons: Set<LaneBlockedReason> = [
            .grantPending,
            .skillGrantPending,
            .authzDenied,
            .authChallengeLoop
        ]
        let userHoldReasons: Set<LaneBlockedReason> = [
            .awaitingInstruction
        ]
        let routeRepairReasons: Set<LaneBlockedReason> = [
            .routeOriginUnavailable,
            .webhookUnhealthy,
            .dispatchIdleTimeout
        ]
        let contextRepairReasons: Set<LaneBlockedReason> = [
            .contextOverflow
        ]

        let requiresUserAction =
            blockedReasons.contains(where: grantFollowUpReasons.contains)
            || blockedReasons.contains(where: userHoldReasons.contains)
        let hasGrantFollowUpSignal = blockedReasons.contains(where: grantFollowUpReasons.contains)
        let hasInstructionHoldSignal = blockedReasons.contains(where: userHoldReasons.contains)
        let hasRouteRepairSignal =
            anomalyTypes.contains(.routeFlaky)
            || blockedReasons.contains(where: routeRepairReasons.contains)
        let hasContextRepairSignal =
            anomalyTypes.contains(.staleRepeat)
            || anomalyTypes.contains(.hollowProgress)
            || blockedReasons.contains(where: contextRepairReasons.contains)
        let hasReplayFollowUpSignal =
            anomalyTypes.contains(.queueStall)
            || blockedReasons.contains(.queueStarvation)
            || blockedReasons.contains(.restartDrain)
        let hasResumeSignal =
            stalledCount > 0
            || failedCount > 0
            || anomalyTypes.contains(.missingHeartbeat)
            || anomalyTypes.contains(.silentLane)
            || anomalyTypes.contains(.queueStall)

        let action: HeartbeatRecoveryAction
        let reasonCode: String
        let summary: String

        if hasInstructionHoldSignal {
            action = .holdForUser
            reasonCode = "awaiting_user_or_operator_instruction"
            summary = "Hold recovery until the user or operator provides the missing instruction."
        } else if hasGrantFollowUpSignal {
            let needsAuthorizationFollowUp =
                blockedReasons.contains(.authzDenied)
                || blockedReasons.contains(.authChallengeLoop)
            action = .requestGrantFollowUp
            reasonCode = needsAuthorizationFollowUp
                ? "authorization_follow_up_required"
                : "grant_follow_up_required"
            summary = needsAuthorizationFollowUp
                ? "Request the required authorization follow-up before resuming autonomous execution."
                : "Request the required grant follow-up before resuming autonomous execution."
        } else if hasRouteRepairSignal {
            action = .repairRoute
            reasonCode = anomalyTypes.contains(.routeFlaky)
                ? "route_flaky_requires_repair"
                : "route_or_dispatch_repair_required"
            summary = "Repair route or runtime dispatch readiness before attempting resume."
        } else if hasContextRepairSignal {
            action = .rehydrateContext
            reasonCode = blockedReasons.contains(.contextOverflow)
                ? "context_window_overflow_requires_rehydrate"
                : "heartbeat_hollow_progress_requires_context_rehydrate"
            summary = "Rehydrate project context before the next execution attempt."
        } else if hasReplayFollowUpSignal {
            action = .replayFollowUp
            reasonCode = blockedReasons.contains(.restartDrain)
                ? "restart_drain_requires_follow_up_replay"
                : "follow_up_queue_stall_requires_replay"
            summary = blockedReasons.contains(.restartDrain)
                ? "Replay the pending follow-up or recovery chain after the current drain finishes."
                : "Replay the pending follow-up or recovery chain because queue progress stalled."
        } else if strategyCandidate != nil {
            action = .queueStrategicReview
            reasonCode = "heartbeat_or_lane_signal_requires_governance_review"
            summary = "Queue a deeper governance review before resuming autonomous execution."
        } else if hasResumeSignal {
            action = .resumeRun
            reasonCode = failedCount > 0
                ? "lane_failure_requires_controlled_resume"
                : "lane_vitality_degraded_resume_candidate"
            summary = "Attempt a controlled resume because lane vitality degraded without a stronger boundary signal."
        } else {
            return nil
        }

        let urgency = recoveryUrgency(
            action: action,
            failedCount: failedCount,
            stalledCount: stalledCount,
            strategyCandidate: strategyCandidate
        )

        return HeartbeatRecoveryDecision(
            action: action,
            urgency: urgency,
            reasonCode: reasonCode,
            summary: summary,
            sourceSignals: recoverySourceSignals(
                anomalyTypes: anomalyTypes,
                blockedReasons: blockedReasons,
                blockedCount: blockedCount,
                stalledCount: stalledCount,
                failedCount: failedCount,
                recoveringCount: recoveringCount,
                reviewCandidate: strategyCandidate
            ),
            anomalyTypes: anomalyTypes,
            blockedLaneReasons: blockedReasons,
            blockedLaneCount: blockedCount,
            stalledLaneCount: stalledCount,
            failedLaneCount: failedCount,
            recoveringLaneCount: recoveringCount,
            requiresUserAction: requiresUserAction,
            queuedReviewTrigger: strategyCandidate?.trigger,
            queuedReviewLevel: strategyCandidate?.reviewLevel,
            queuedReviewRunKind: strategyCandidate?.runKind
        )
    }

    private static func triggerAllowed(
        governance: AXProjectResolvedGovernanceState,
        trigger: SupervisorReviewTrigger,
        runKind: SupervisorReviewRunKind
    ) -> Bool {
        if mandatoryTriggers(for: governance.effectiveBundle.executionTier).contains(trigger) {
            return true
        }

        switch trigger {
        case .manualRequest, .userOverride:
            return true
        case .periodicHeartbeat:
            return resolvedCadenceSeconds(for: .progressHeartbeat, governance: governance) > 0
        case .periodicPulse:
            return resolvedCadenceSeconds(for: .reviewPulse, governance: governance) > 0
        case .failureStreak, .noProgressWindow, .blockerDetected, .planDrift, .preHighRiskAction, .preDoneSummary:
            if runKind == .brainstorm {
                return resolvedCadenceSeconds(for: .brainstormReview, governance: governance) > 0
            }
            guard governance.effectiveBundle.schedule.eventDrivenReviewEnabled else { return false }
            return governance.effectiveBundle.schedule.eventReviewTriggers.contains(trigger.projectTrigger)
                || (governance.effectiveBundle.reviewPolicyMode == .aggressive
                    && (trigger == .failureStreak || trigger == .noProgressWindow))
        }
    }

    private static func shouldRunPulse(
        governance: AXProjectResolvedGovernanceState,
        schedule: SupervisorReviewScheduleState?,
        cadence: SupervisorCadenceExplainability?,
        openAnomalies: [HeartbeatAnomalyNote]
    ) -> Bool {
        guard resolvedCadenceSeconds(for: .reviewPulse, governance: governance) > 0 else { return false }
        guard let schedule else { return true }
        if hasPendingPulseEscalation(schedule: schedule, openAnomalies: openAnomalies),
           latestHeartbeatAssessmentAtMs(schedule: schedule, openAnomalies: openAnomalies) > schedule.lastPulseReviewAtMs {
            return true
        }
        guard let cadence else { return false }
        return cadence.reviewPulse.nextDueAtMs > 0 && cadence.reviewPulse.isDue
    }

    private static func shouldRunBrainstorm(
        governance: AXProjectResolvedGovernanceState,
        schedule: SupervisorReviewScheduleState?,
        cadence: SupervisorCadenceExplainability?,
        openAnomalies: [HeartbeatAnomalyNote]
    ) -> Bool {
        guard resolvedCadenceSeconds(for: .brainstormReview, governance: governance) > 0 else { return false }
        guard let schedule else { return true }
        if hasPendingBrainstormEscalation(openAnomalies: openAnomalies),
           latestHeartbeatAssessmentAtMs(schedule: schedule, openAnomalies: openAnomalies) > schedule.lastBrainstormReviewAtMs {
            return true
        }
        guard let cadence else { return false }
        return cadence.brainstormReview.nextDueAtMs > 0 && cadence.brainstormReview.isDue
    }

    private static func latestHeartbeatAssessmentAtMs(
        schedule: SupervisorReviewScheduleState,
        openAnomalies: [HeartbeatAnomalyNote]? = nil
    ) -> Int64 {
        max(
            schedule.latestQualitySnapshot?.computedAtMs ?? 0,
            (openAnomalies ?? schedule.openAnomalies).map(\.detectedAtMs).max() ?? 0
        )
    }

    private static func hasPendingWeakDoneClaim(
        openAnomalies: [HeartbeatAnomalyNote]
    ) -> Bool {
        openAnomalies.contains {
            $0.anomalyType == .weakDoneClaim && $0.severity.rank >= HeartbeatAnomalySeverity.high.rank
        }
    }

    private static func hasPendingBlockerEscalation(
        schedule: SupervisorReviewScheduleState
    ) -> Bool {
        pendingBlockerEscalationAnomaly(openAnomalies: schedule.openAnomalies) != nil
    }

    private static func pendingBlockerEscalationAnomaly(
        openAnomalies: [HeartbeatAnomalyNote]
    ) -> HeartbeatAnomalyType? {
        openAnomalies.first(where: {
            switch $0.anomalyType {
            case .queueStall:
                return $0.severity.rank >= HeartbeatAnomalySeverity.concern.rank
            case .weakBlocker:
                switch $0.recommendedEscalation {
                case .strategicReview, .rescueReview, .replan, .stop:
                    return true
                case .observe, .pulseReview:
                    return false
                }
            default:
                return false
            }
        })?.anomalyType
    }

    private static func hasPendingBrainstormEscalation(
        openAnomalies: [HeartbeatAnomalyNote]
    ) -> Bool {
        pendingBrainstormEscalationAnomaly(openAnomalies: openAnomalies) != nil
    }

    private static func pendingBrainstormEscalationAnomaly(
        openAnomalies: [HeartbeatAnomalyNote]
    ) -> HeartbeatAnomalyType? {
        openAnomalies.first(where: {
            switch $0.anomalyType {
            case .staleRepeat, .hollowProgress:
                return $0.severity.rank >= HeartbeatAnomalySeverity.concern.rank
            case .missingHeartbeat, .driftSuspected:
                switch $0.recommendedEscalation {
                case .strategicReview, .rescueReview, .replan, .stop:
                    return true
                case .observe, .pulseReview:
                    return false
                }
            default:
                return false
            }
        })?.anomalyType
    }

    private static func hasPendingPulseEscalation(
        schedule: SupervisorReviewScheduleState,
        openAnomalies: [HeartbeatAnomalyNote]
    ) -> Bool {
        pendingPulseEscalationAnomaly(
            schedule: schedule,
            openAnomalies: openAnomalies
        ) != nil || schedule.latestQualitySnapshot?.overallBand == .hollow
    }

    private static func pendingPulseEscalationAnomaly(
        schedule: SupervisorReviewScheduleState,
        openAnomalies: [HeartbeatAnomalyNote]
    ) -> HeartbeatAnomalyType? {
        if hasPendingBrainstormEscalation(openAnomalies: openAnomalies) {
            return pendingBrainstormEscalationAnomaly(openAnomalies: openAnomalies)
        }
        return openAnomalies.first(where: { $0.recommendedEscalation == .pulseReview })?.anomalyType
    }

    private static func heartbeatQualityReason(
        schedule: SupervisorReviewScheduleState,
        openAnomalies: [HeartbeatAnomalyNote]
    ) -> String {
        let band = schedule.latestQualitySnapshot?.overallBand.rawValue ?? "unknown"
        let anomalyTypes = openAnomalies.map(\.anomalyType.rawValue)
        let anomalyToken = anomalyTypes.isEmpty ? "none" : anomalyTypes.joined(separator: ",")
        let repeatCount = max(0, schedule.lastHeartbeatRepeatCount)
        return " quality=\(band) anomalies=\(anomalyToken) repeat=\(repeatCount)"
    }

    private static func synthesizedMissingHeartbeatAnomaly(
        governance: AXProjectResolvedGovernanceState,
        schedule: SupervisorReviewScheduleState,
        nowMs: Int64,
        cadence: SupervisorCadenceExplainability?
    ) -> HeartbeatAnomalyNote? {
        guard schedule.lastHeartbeatAtMs > 0 else { return nil }

        let cadenceExplainability = cadence ?? Self.cadenceExplainability(
            governance: governance,
            schedule: schedule,
            nowMs: nowMs
        )
        let heartbeatCadence = cadenceExplainability.progressHeartbeat
        guard heartbeatCadence.effectiveSeconds > 0 else { return nil }
        guard heartbeatCadence.nextDueAtMs > 0, nowMs >= heartbeatCadence.nextDueAtMs else {
            return nil
        }

        let overdueMs = max(0, nowMs - heartbeatCadence.nextDueAtMs)
        let effectiveWindowMs = Int64(heartbeatCadence.effectiveSeconds) * 1_000
        let severity: HeartbeatAnomalySeverity
        let confidence: Double
        let escalation: HeartbeatAnomalyEscalation
        switch overdueMs {
        case ..<effectiveWindowMs:
            severity = .watch
            confidence = 0.66
            escalation = .observe
        case ..<(effectiveWindowMs * 2):
            severity = .concern
            confidence = 0.78
            escalation = .pulseReview
        case ..<(effectiveWindowMs * 4):
            severity = .high
            confidence = 0.86
            escalation = .strategicReview
        default:
            severity = .critical
            confidence = 0.92
            escalation = .rescueReview
        }

        let projectId = schedule.projectId.isEmpty ? governance.projectId : schedule.projectId
        let detectedAtMs = heartbeatCadence.nextDueAtMs
        return HeartbeatAnomalyNote(
            anomalyId: "hb-runtime:\(projectId):\(HeartbeatAnomalyType.missingHeartbeat.rawValue):\(max(0, detectedAtMs))",
            projectId: projectId,
            anomalyType: .missingHeartbeat,
            severity: severity,
            confidence: confidence,
            reason: "No fresh project heartbeat arrived after the effective heartbeat window elapsed.",
            evidenceRefs: [
                "heartbeat_due:\(projectId):\(max(0, heartbeatCadence.nextDueAtMs))",
                "last_heartbeat:\(projectId):\(max(0, schedule.lastHeartbeatAtMs))"
            ],
            detectedAtMs: detectedAtMs,
            recommendedEscalation: escalation
        )
    }

    private static func cadenceDimensionExplainability(
        dimension: SupervisorCadenceDimension,
        configuredSeconds: Int,
        recommendedSeconds: Int,
        governance: AXProjectResolvedGovernanceState,
        schedule: SupervisorReviewScheduleState,
        nowMs: Int64
    ) -> SupervisorCadenceDimensionExplainability {
        let effective = effectiveCadenceResolution(
            for: dimension,
            configuredSeconds: configuredSeconds,
            recommendedSeconds: recommendedSeconds,
            governance: governance,
            schedule: schedule
        )
        let due = dueResolution(
            for: dimension,
            effectiveSeconds: effective.seconds,
            schedule: schedule,
            nowMs: nowMs
        )

        return SupervisorCadenceDimensionExplainability(
            dimension: dimension,
            configuredSeconds: configuredSeconds,
            recommendedSeconds: recommendedSeconds,
            effectiveSeconds: effective.seconds,
            effectiveReasonCodes: effective.reasonCodes,
            nextDueAtMs: due.nextDueAtMs,
            nextDueReasonCodes: due.reasonCodes,
            isDue: due.isDue
        )
    }

    private static func resolvedCadenceSeconds(
        for dimension: SupervisorCadenceDimension,
        governance: AXProjectResolvedGovernanceState
    ) -> Int {
        let configuredSchedule = governance.configuredBundle.schedule
        let recommendedBaseSchedule = AXProjectGovernanceBundle.recommended(
            for: governance.configuredBundle.executionTier,
            supervisorInterventionTier: governance.supervisorAdaptation.recommendedSupervisorTier
        ).schedule

        switch dimension {
        case .progressHeartbeat:
            return effectiveCadenceResolution(
                for: dimension,
                configuredSeconds: configuredSchedule.progressHeartbeatSeconds,
                recommendedSeconds: recommendedCadenceSeconds(
                    for: dimension,
                    baseRecommendedSeconds: recommendedBaseSchedule.progressHeartbeatSeconds,
                    schedule: nil
                ),
                governance: governance,
                schedule: nil
            ).seconds
        case .reviewPulse:
            return effectiveCadenceResolution(
                for: dimension,
                configuredSeconds: configuredSchedule.reviewPulseSeconds,
                recommendedSeconds: recommendedCadenceSeconds(
                    for: dimension,
                    baseRecommendedSeconds: recommendedBaseSchedule.reviewPulseSeconds,
                    schedule: nil
                ),
                governance: governance,
                schedule: nil
            ).seconds
        case .brainstormReview:
            return effectiveCadenceResolution(
                for: dimension,
                configuredSeconds: configuredSchedule.brainstormReviewSeconds,
                recommendedSeconds: recommendedCadenceSeconds(
                    for: dimension,
                    baseRecommendedSeconds: recommendedBaseSchedule.brainstormReviewSeconds,
                    schedule: nil
                ),
                governance: governance,
                schedule: nil
            ).seconds
        }
    }

    private static func recommendedCadenceSeconds(
        for dimension: SupervisorCadenceDimension,
        baseRecommendedSeconds: Int,
        schedule: SupervisorReviewScheduleState?
    ) -> Int {
        var recommendedSeconds = max(0, baseRecommendedSeconds)
        guard recommendedSeconds > 0, let schedule else {
            return recommendedSeconds
        }

        if let phase = schedule.latestProjectPhase {
            let phaseTarget = phaseRecommendedCadenceSeconds(
                for: dimension,
                phase: phase
            )
            if phaseTarget > 0 {
                switch phase {
                case .explore, .plan:
                    recommendedSeconds = maximumPositive(recommendedSeconds, phaseTarget)
                case .build, .verify, .release:
                    recommendedSeconds = minimumPositive(recommendedSeconds, phaseTarget)
                }
            }
        }

        if let riskTier = schedule.latestRiskTier {
            let riskTarget = riskTightenedCadenceSeconds(
                for: dimension,
                riskTier: riskTier
            )
            if riskTarget > 0 {
                recommendedSeconds = minimumPositive(recommendedSeconds, riskTarget)
            }
        }

        return recommendedSeconds
    }

    private static func effectiveCadenceResolution(
        for dimension: SupervisorCadenceDimension,
        configuredSeconds: Int,
        recommendedSeconds: Int,
        governance: AXProjectResolvedGovernanceState,
        schedule: SupervisorReviewScheduleState?
    ) -> (seconds: Int, reasonCodes: [String]) {
        let baseEffectiveSeconds: Int
        switch dimension {
        case .progressHeartbeat:
            baseEffectiveSeconds = governance.effectiveBundle.schedule.progressHeartbeatSeconds
        case .reviewPulse:
            baseEffectiveSeconds = governance.effectiveBundle.schedule.reviewPulseSeconds
        case .brainstormReview:
            baseEffectiveSeconds = governance.effectiveBundle.schedule.brainstormReviewSeconds
        }

        var effectiveSeconds = max(0, baseEffectiveSeconds)
        var reasonCodes: [String] = []

        if governance.validation.shouldFailClosed || governance.supervisorAdaptation.escalationReasons.contains("validation_fail_closed") {
            reasonCodes.append("clamped_by_fail_closed_governance")
        } else if effectiveSeconds != max(0, configuredSeconds) {
            reasonCodes.append("clamped_by_effective_governance_bundle")
        }

        switch dimension {
        case .reviewPulse:
            switch governance.effectiveBundle.reviewPolicyMode {
            case .off, .milestoneOnly:
                return (0, reasonCodes + ["disabled_by_review_policy_\(governance.effectiveBundle.reviewPolicyMode.rawValue)"])
            case .periodic, .hybrid, .aggressive:
                break
            }
        case .brainstormReview:
            switch governance.effectiveBundle.reviewPolicyMode {
            case .off, .milestoneOnly, .periodic:
                return (0, reasonCodes + ["disabled_by_review_policy_\(governance.effectiveBundle.reviewPolicyMode.rawValue)"])
            case .hybrid, .aggressive:
                break
            }
        case .progressHeartbeat:
            break
        }

        if let phase = schedule?.latestProjectPhase {
            let phaseTarget = phaseRecommendedCadenceSeconds(
                for: dimension,
                phase: phase
            )
            if phaseTarget > 0 {
                switch phase {
                case .explore, .plan:
                    if canRelaxForProjectPhase(
                        governance: governance,
                        schedule: schedule
                    ) {
                        let relaxed = maximumPositive(effectiveSeconds, phaseTarget)
                        if relaxed != effectiveSeconds {
                            effectiveSeconds = relaxed
                            reasonCodes.append("adjusted_for_project_phase_\(phase.rawValue)")
                        }
                    }
                case .build, .verify, .release:
                    let tightened = minimumPositive(effectiveSeconds, phaseTarget)
                    if tightened != effectiveSeconds {
                        effectiveSeconds = tightened
                        reasonCodes.append("adjusted_for_project_phase_\(phase.rawValue)")
                    }
                }
            }
        }

        if shouldClampToRecommended(governance: governance, schedule: schedule) {
            let clamped = minimumPositive(effectiveSeconds, recommendedSeconds)
            if clamped != effectiveSeconds {
                effectiveSeconds = clamped
                reasonCodes.append("clamped_to_protocol_recommended")
            }
        }

        if shouldTightenForLowConfidence(governance: governance, schedule: schedule) {
            let tightened = minimumPositive(
                effectiveSeconds,
                lowConfidenceTightenedCadenceSeconds(
                    for: dimension,
                    recommendedSeconds: recommendedSeconds
                )
            )
            if tightened != effectiveSeconds {
                effectiveSeconds = tightened
                reasonCodes.append("tightened_for_low_execution_confidence")
            }
        }

        if shouldTightenForRescue(governance: governance, schedule: schedule) {
            let tightened = minimumPositive(
                effectiveSeconds,
                rescueTightenedCadenceSeconds(
                    for: dimension,
                    recommendedSeconds: recommendedSeconds
                )
            )
            if tightened != effectiveSeconds {
                effectiveSeconds = tightened
                reasonCodes.append("tightened_for_rescue_or_high_anomaly")
            }
        }

        if let riskTier = schedule?.latestRiskTier {
            let tightened = minimumPositive(
                effectiveSeconds,
                riskTightenedCadenceSeconds(
                    for: dimension,
                    riskTier: riskTier
                )
            )
            if tightened != effectiveSeconds {
                effectiveSeconds = tightened
                reasonCodes.append(
                    riskTier == .critical
                        ? "tightened_for_critical_project_risk"
                        : "tightened_for_high_project_risk"
                )
            }
        }

        if let executionStatus = schedule?.latestExecutionStatus,
           let statusTarget = executionStatusTightenedCadenceSeconds(
                for: dimension,
                executionStatus: executionStatus
           ) {
            let tightened = minimumPositive(effectiveSeconds, statusTarget)
            if tightened != effectiveSeconds {
                effectiveSeconds = tightened
                switch executionStatus {
                case .active:
                    break
                case .blocked:
                    reasonCodes.append("tightened_for_blocked_execution_status")
                case .stalled:
                    reasonCodes.append("tightened_for_stalled_execution_status")
                case .doneCandidate:
                    reasonCodes.append("tightened_for_done_candidate_status")
                }
            }
        }

        if reasonCodes.isEmpty {
            reasonCodes.append("preserve_current_runtime_cadence")
        }

        return (effectiveSeconds, reasonCodes)
    }

    private static func shouldClampToRecommended(
        governance: AXProjectResolvedGovernanceState,
        schedule: SupervisorReviewScheduleState?
    ) -> Bool {
        if governance.supervisorAdaptation.effectiveWorkOrderDepth >= .executionReady
            || governance.effectiveBundle.supervisorInterventionTier >= .s3StrategicCoach
            || governance.effectiveBundle.reviewPolicyMode == .aggressive {
            return true
        }
        guard let schedule else { return false }
        let qualityBand = schedule.latestQualitySnapshot?.overallBand ?? .usable
        return qualityBand.rank <= HeartbeatQualityBand.weak.rank
    }

    private static func canRelaxForProjectPhase(
        governance: AXProjectResolvedGovernanceState,
        schedule: SupervisorReviewScheduleState?
    ) -> Bool {
        guard let schedule else { return false }
        let phase = schedule.latestProjectPhase ?? .build
        guard phase == .explore || phase == .plan else { return false }
        let qualityBand = schedule.latestQualitySnapshot?.overallBand ?? .usable
        let riskTier = schedule.latestRiskTier ?? .medium
        return qualityBand == .strong
            && schedule.openAnomalies.isEmpty
            && riskTier == .low
            && governance.effectiveBundle.supervisorInterventionTier <= .s1MilestoneReview
            && governance.supervisorAdaptation.effectiveWorkOrderDepth < .executionReady
    }

    private static func shouldTightenForLowConfidence(
        governance: AXProjectResolvedGovernanceState,
        schedule: SupervisorReviewScheduleState?
    ) -> Bool {
        let strengthBand = governance.supervisorAdaptation.projectAIStrengthProfile?.strengthBand ?? .unknown
        if governance.supervisorAdaptation.effectiveWorkOrderDepth >= .executionReady,
           strengthBand <= .developing {
            return true
        }
        guard let schedule else { return false }
        return schedule.latestQualitySnapshot?.overallBand.rank ?? HeartbeatQualityBand.usable.rank
            <= HeartbeatQualityBand.weak.rank
    }

    private static func shouldTightenForRescue(
        governance: AXProjectResolvedGovernanceState,
        schedule: SupervisorReviewScheduleState?
    ) -> Bool {
        if governance.supervisorAdaptation.effectiveWorkOrderDepth == .stepLockedRescue {
            return true
        }
        guard let schedule else { return false }
        return schedule.openAnomalies.contains {
            $0.severity.rank >= HeartbeatAnomalySeverity.high.rank
                || $0.recommendedEscalation == .rescueReview
                || $0.recommendedEscalation == .replan
                || $0.recommendedEscalation == .stop
        }
    }

    private static func lowConfidenceTightenedCadenceSeconds(
        for dimension: SupervisorCadenceDimension,
        recommendedSeconds: Int
    ) -> Int {
        switch dimension {
        case .progressHeartbeat:
            return maximumPositive(300, recommendedSeconds / 2)
        case .reviewPulse:
            return maximumPositive(900, recommendedSeconds / 2)
        case .brainstormReview:
            return maximumPositive(1800, recommendedSeconds / 2)
        }
    }

    private static func rescueTightenedCadenceSeconds(
        for dimension: SupervisorCadenceDimension,
        recommendedSeconds: Int
    ) -> Int {
        switch dimension {
        case .progressHeartbeat:
            return maximumPositive(180, recommendedSeconds / 2)
        case .reviewPulse:
            return maximumPositive(600, recommendedSeconds / 2)
        case .brainstormReview:
            return maximumPositive(1200, recommendedSeconds / 2)
        }
    }

    private static func phaseRecommendedCadenceSeconds(
        for dimension: SupervisorCadenceDimension,
        phase: HeartbeatProjectPhase
    ) -> Int {
        switch (phase, dimension) {
        case (.explore, .progressHeartbeat):
            return 1_800
        case (.explore, .reviewPulse):
            return 5_400
        case (.explore, .brainstormReview):
            return 10_800
        case (.plan, .progressHeartbeat):
            return 1_200
        case (.plan, .reviewPulse):
            return 3_600
        case (.plan, .brainstormReview):
            return 7_200
        case (.build, .progressHeartbeat):
            return 600
        case (.build, .reviewPulse):
            return 1_800
        case (.build, .brainstormReview):
            return 3_600
        case (.verify, .progressHeartbeat):
            return 300
        case (.verify, .reviewPulse):
            return 1_200
        case (.verify, .brainstormReview):
            return 2_400
        case (.release, .progressHeartbeat):
            return 180
        case (.release, .reviewPulse):
            return 600
        case (.release, .brainstormReview):
            return 1_200
        }
    }

    private static func riskTightenedCadenceSeconds(
        for dimension: SupervisorCadenceDimension,
        riskTier: HeartbeatRiskTier
    ) -> Int {
        switch riskTier {
        case .low, .medium:
            return 0
        case .high:
            switch dimension {
            case .progressHeartbeat:
                return 300
            case .reviewPulse:
                return 900
            case .brainstormReview:
                return 1_800
            }
        case .critical:
            switch dimension {
            case .progressHeartbeat:
                return 180
            case .reviewPulse:
                return 600
            case .brainstormReview:
                return 1_200
            }
        }
    }

    private static func executionStatusTightenedCadenceSeconds(
        for dimension: SupervisorCadenceDimension,
        executionStatus: HeartbeatExecutionStatus
    ) -> Int? {
        switch executionStatus {
        case .active:
            return nil
        case .blocked:
            switch dimension {
            case .progressHeartbeat:
                return 300
            case .reviewPulse:
                return 900
            case .brainstormReview:
                return 1_800
            }
        case .stalled:
            switch dimension {
            case .progressHeartbeat:
                return 300
            case .reviewPulse:
                return 1_200
            case .brainstormReview:
                return 1_800
            }
        case .doneCandidate:
            switch dimension {
            case .progressHeartbeat:
                return 300
            case .reviewPulse:
                return 900
            case .brainstormReview:
                return 1_800
            }
        }
    }

    private static func dueResolution(
        for dimension: SupervisorCadenceDimension,
        effectiveSeconds: Int,
        schedule: SupervisorReviewScheduleState,
        nowMs: Int64
    ) -> (nextDueAtMs: Int64, isDue: Bool, reasonCodes: [String]) {
        guard effectiveSeconds > 0 else {
            return (0, false, ["cadence_disabled"])
        }

        let anchorMs: Int64
        let waitingCode: String
        let dueCode: String

        switch dimension {
        case .progressHeartbeat:
            anchorMs = schedule.lastHeartbeatAtMs
            waitingCode = "waiting_for_heartbeat_window"
            dueCode = "heartbeat_window_elapsed"
        case .reviewPulse:
            anchorMs = schedule.lastPulseReviewAtMs > 0
                ? schedule.lastPulseReviewAtMs
                : schedule.lastHeartbeatAtMs
            waitingCode = schedule.lastPulseReviewAtMs > 0
                ? "waiting_for_pulse_window"
                : "awaiting_first_pulse_window"
            dueCode = "pulse_review_window_elapsed"
        case .brainstormReview:
            anchorMs = schedule.lastObservedProgressAtMs > 0
                ? schedule.lastObservedProgressAtMs
                : schedule.lastHeartbeatAtMs
            waitingCode = "waiting_for_no_progress_window"
            dueCode = "no_progress_window_reached"
        }

        guard anchorMs > 0 else {
            switch dimension {
            case .progressHeartbeat, .reviewPulse:
                return (0, false, ["awaiting_first_heartbeat"])
            case .brainstormReview:
                return (0, false, ["awaiting_progress_observation"])
            }
        }

        let nextDueAtMs = anchorMs + Int64(effectiveSeconds) * 1000
        return (
            nextDueAtMs,
            nowMs >= nextDueAtMs,
            [nowMs >= nextDueAtMs ? dueCode : waitingCode]
        )
    }

    private static func minimumPositive(_ lhs: Int, _ rhs: Int) -> Int {
        guard lhs > 0 else { return max(0, rhs) }
        guard rhs > 0 else { return lhs }
        return min(lhs, rhs)
    }

    private static func maximumPositive(_ lhs: Int, _ rhs: Int) -> Int {
        if lhs <= 0 { return max(0, rhs) }
        if rhs <= 0 { return lhs }
        return max(lhs, rhs)
    }

    private static func minimumReviewLevel(
        for supervisorTier: AXProjectSupervisorInterventionTier,
        runKind: SupervisorReviewRunKind,
        trigger: SupervisorReviewTrigger
    ) -> SupervisorReviewLevel {
        switch trigger {
        case .preHighRiskAction, .preDoneSummary:
            return .r3Rescue
        case .blockerDetected, .planDrift, .failureStreak:
            return supervisorTier >= .s3StrategicCoach ? .r2Strategic : .r1Pulse
        case .noProgressWindow:
            return runKind == .brainstorm || supervisorTier >= .s3StrategicCoach ? .r2Strategic : .r1Pulse
        case .periodicPulse, .periodicHeartbeat, .manualRequest, .userOverride:
            if runKind == .brainstorm {
                return supervisorTier >= .s3StrategicCoach ? .r2Strategic : .r1Pulse
            }
            return supervisorTier >= .s4TightSupervision ? .r2Strategic : .r1Pulse
        }
    }

    private static func minimumReviewLevel(
        for workOrderDepth: AXProjectSupervisorWorkOrderDepth,
        runKind: SupervisorReviewRunKind,
        trigger: SupervisorReviewTrigger
    ) -> SupervisorReviewLevel {
        switch workOrderDepth {
        case .none, .brief:
            switch trigger {
            case .preHighRiskAction, .preDoneSummary:
                return .r3Rescue
            default:
                return .r1Pulse
            }
        case .milestoneContract:
            switch trigger {
            case .preHighRiskAction, .preDoneSummary:
                return .r3Rescue
            case .blockerDetected, .planDrift, .failureStreak, .noProgressWindow:
                return .r2Strategic
            case .periodicPulse, .periodicHeartbeat, .manualRequest, .userOverride:
                return runKind == .brainstorm ? .r2Strategic : .r1Pulse
            }
        case .executionReady:
            switch trigger {
            case .preHighRiskAction, .preDoneSummary:
                return .r3Rescue
            case .blockerDetected, .planDrift, .failureStreak, .noProgressWindow:
                return .r2Strategic
            case .periodicPulse, .periodicHeartbeat, .manualRequest, .userOverride:
                return .r2Strategic
            }
        case .stepLockedRescue:
            switch trigger {
            case .preHighRiskAction, .preDoneSummary, .blockerDetected, .planDrift, .failureStreak, .noProgressWindow:
                return .r3Rescue
            case .periodicPulse, .periodicHeartbeat, .manualRequest, .userOverride:
                return .r2Strategic
            }
        }
    }

    private static func resolvedInterventionMode(
        deliveryMode: SupervisorGuidanceDeliveryMode,
        supervisorTier: AXProjectSupervisorInterventionTier,
        workOrderDepth: AXProjectSupervisorWorkOrderDepth,
        reviewLevel: SupervisorReviewLevel,
        verdict: SupervisorReviewVerdict,
        ackRequired: Bool
    ) -> SupervisorGuidanceInterventionMode {
        let structuredReplanPreferred = reviewLevel == .r3Rescue
            || workOrderDepth == .stepLockedRescue
            || (workOrderDepth >= .executionReady && ackRequired && reviewLevel != .r1Pulse)
        switch deliveryMode {
        case .stopSignal:
            return .stopImmediately
        case .replanRequest:
            return .replanNextSafePoint
        case .priorityInsert:
            if supervisorTier == .s4TightSupervision && reviewLevel == .r3Rescue {
                return .replanNextSafePoint
            }
            if structuredReplanPreferred && reviewLevel != .r1Pulse {
                return .replanNextSafePoint
            }
            return .suggestNextSafePoint
        case .contextAppend:
            if verdict == .highRisk {
                return .stopImmediately
            }
            if structuredReplanPreferred && reviewLevel != .r1Pulse {
                return .replanNextSafePoint
            }
            if ackRequired || reviewLevel != .r1Pulse {
                return supervisorTier == .s0SilentAudit ? .suggestNextSafePoint : .suggestNextSafePoint
            }
            return supervisorTier == .s0SilentAudit ? .observeOnly : .suggestNextSafePoint
        }
    }

    private static func resolvedSafePointPolicy(
        deliveryMode: SupervisorGuidanceDeliveryMode,
        interventionMode: SupervisorGuidanceInterventionMode,
        reviewLevel: SupervisorReviewLevel,
        workOrderDepth: AXProjectSupervisorWorkOrderDepth
    ) -> SupervisorGuidanceSafePointPolicy {
        if interventionMode == .stopImmediately {
            return .immediate
        }
        if interventionMode == .replanNextSafePoint {
            return workOrderDepth == .stepLockedRescue ? .checkpointBoundary : .nextStepBoundary
        }
        switch deliveryMode {
        case .replanRequest:
            return .nextStepBoundary
        case .priorityInsert:
            return workOrderDepth >= .executionReady ? .nextStepBoundary : .nextToolBoundary
        case .stopSignal:
            return .immediate
        case .contextAppend:
            if workOrderDepth == .stepLockedRescue || reviewLevel == .r3Rescue {
                return .checkpointBoundary
            }
            return workOrderDepth >= .executionReady ? .nextStepBoundary : .nextToolBoundary
        }
    }

    private static func mandatoryTriggers(
        for executionTier: AXProjectExecutionTier
    ) -> Set<SupervisorReviewTrigger> {
        Set(
            executionTier.mandatoryReviewTriggers.map {
                SupervisorReviewTrigger(rawValue: $0.rawValue) ?? .manualRequest
            }
        )
    }

    private static func reviewedRecently(
        schedule: SupervisorReviewScheduleState,
        trigger: SupervisorReviewTrigger,
        nowMs: Int64,
        cooldownMs: Int64
    ) -> Bool {
        guard cooldownMs > 0 else { return false }
        let last = schedule.lastTriggerReviewAtMs[trigger.rawValue] ?? 0
        return last > 0 && nowMs - last < cooldownMs
    }

    private static func eventReviewCooldownSeconds(
        governance: AXProjectResolvedGovernanceState
    ) -> Int {
        let baseCooldown = baseEventReviewCooldownSeconds(governance: governance)
        let workOrderDepth = governance.supervisorAdaptation.effectiveWorkOrderDepth
        let strengthBand = governance.supervisorAdaptation.projectAIStrengthProfile?.strengthBand ?? .unknown
        let supervisorTier = governance.effectiveBundle.supervisorInterventionTier

        if workOrderDepth == .stepLockedRescue {
            return min(baseCooldown, 90)
        }

        if workOrderDepth == .executionReady {
            switch strengthBand {
            case .strong:
                return max(baseCooldown, 360)
            case .capable:
                return max(baseCooldown, 300)
            case .developing:
                return min(baseCooldown, 180)
            case .weak, .unknown:
                return min(baseCooldown, 120)
            }
        }

        switch strengthBand {
        case .strong:
            return supervisorTier <= .s2PeriodicReview ? max(baseCooldown, 1200) : max(baseCooldown, 360)
        case .capable:
            return supervisorTier <= .s2PeriodicReview ? max(baseCooldown, 900) : max(baseCooldown, 300)
        case .developing:
            return supervisorTier >= .s3StrategicCoach ? min(baseCooldown, 240) : min(baseCooldown, 420)
        case .weak, .unknown:
            return supervisorTier >= .s3StrategicCoach ? min(baseCooldown, 180) : min(baseCooldown, 300)
        }
    }

    private static func baseEventReviewCooldownSeconds(
        governance: AXProjectResolvedGovernanceState
    ) -> Int {
        let pulse = governance.effectiveBundle.schedule.reviewPulseSeconds
        switch governance.effectiveBundle.supervisorInterventionTier {
        case .s0SilentAudit:
            return max(600, pulse)
        case .s1MilestoneReview:
            return max(600, pulse)
        case .s2PeriodicReview:
            return max(300, pulse / 2)
        case .s3StrategicCoach, .s4TightSupervision:
            return max(180, pulse / 2)
        }
    }

    private static func recoveryUrgency(
        action: HeartbeatRecoveryAction,
        failedCount: Int,
        stalledCount: Int,
        strategyCandidate: SupervisorHeartbeatReviewCandidate?
    ) -> HeartbeatRecoveryUrgency {
        if strategyCandidate?.reviewLevel == .r3Rescue || failedCount > 0 {
            return .urgent
        }

        switch action {
        case .replayFollowUp, .requestGrantFollowUp, .holdForUser, .repairRoute, .queueStrategicReview:
            return .active
        case .rehydrateContext:
            return stalledCount > 0 ? .active : .observe
        case .resumeRun:
            return (stalledCount > 0 || strategyCandidate != nil) ? .active : .observe
        }
    }

    private static func recoverySourceSignals(
        anomalyTypes: [HeartbeatAnomalyType],
        blockedReasons: [LaneBlockedReason],
        blockedCount: Int,
        stalledCount: Int,
        failedCount: Int,
        recoveringCount: Int,
        reviewCandidate: SupervisorHeartbeatReviewCandidate?
    ) -> [String] {
        var signals = anomalyTypes.map { "anomaly:\($0.rawValue)" }
        signals += blockedReasons.map { "lane_blocked_reason:\($0.rawValue)" }
        if blockedCount > 0 {
            signals.append("lane_blocked_count:\(blockedCount)")
        }
        if stalledCount > 0 {
            signals.append("lane_stalled_count:\(stalledCount)")
        }
        if failedCount > 0 {
            signals.append("lane_failed_count:\(failedCount)")
        }
        if recoveringCount > 0 {
            signals.append("lane_recovering_count:\(recoveringCount)")
        }
        if let reviewCandidate {
            signals.append(
                "review_candidate:\(reviewCandidate.trigger.rawValue):\(reviewCandidate.reviewLevel.rawValue):\(reviewCandidate.runKind.rawValue)"
            )
        }
        return Array(Set(signals)).sorted()
    }

    private static func uniqueSorted<T: Hashable & RawRepresentable>(
        _ values: [T]
    ) -> [T] where T.RawValue == String {
        Array(Set(values)).sorted { $0.rawValue < $1.rawValue }
    }
}

extension SupervisorReviewLevel: Comparable {
    public static func < (lhs: SupervisorReviewLevel, rhs: SupervisorReviewLevel) -> Bool {
        lhs.sortRank < rhs.sortRank
    }

    private var sortRank: Int {
        switch self {
        case .r1Pulse:
            return 1
        case .r2Strategic:
            return 2
        case .r3Rescue:
            return 3
        }
    }
}

private extension SupervisorReviewTrigger {
    var projectTrigger: AXProjectReviewTrigger {
        AXProjectReviewTrigger(rawValue: rawValue) ?? .manualRequest
    }
}
