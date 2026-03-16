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

        if blockerDetected,
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
                priority: effectiveWorkOrderDepth == .stepLockedRescue ? 350 : 300,
                policyReason: "event_trigger=blocker_detected depth=\(effectiveWorkOrderDepth.rawValue)"
            )
        }

        if shouldRunBrainstorm(governance: governance, schedule: schedule, nowMs: nowMs) {
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
                priority: effectiveWorkOrderDepth >= .executionReady ? 220 : 200,
                policyReason: "brainstorm_review_due depth=\(effectiveWorkOrderDepth.rawValue)"
            )
        }

        if shouldRunPulse(governance: governance, schedule: schedule, nowMs: nowMs) {
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
                policyReason: "pulse_review_due depth=\(effectiveWorkOrderDepth.rawValue)"
            )
        }

        return nil
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
            return governance.effectiveBundle.schedule.progressHeartbeatSeconds > 0
        case .periodicPulse:
            return shouldRunPulse(governance: governance, schedule: nil, nowMs: 0)
        case .failureStreak, .noProgressWindow, .blockerDetected, .planDrift, .preHighRiskAction, .preDoneSummary:
            if runKind == .brainstorm {
                return shouldRunBrainstorm(governance: governance, schedule: nil, nowMs: 0)
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
        nowMs: Int64
    ) -> Bool {
        guard governance.effectiveBundle.schedule.reviewPulseSeconds > 0 else { return false }
        switch governance.effectiveBundle.reviewPolicyMode {
        case .periodic, .hybrid, .aggressive:
            break
        case .off, .milestoneOnly:
            return false
        }
        guard let schedule else { return true }
        return schedule.nextPulseReviewDueAtMs > 0 && nowMs >= schedule.nextPulseReviewDueAtMs
    }

    private static func shouldRunBrainstorm(
        governance: AXProjectResolvedGovernanceState,
        schedule: SupervisorReviewScheduleState?,
        nowMs: Int64
    ) -> Bool {
        guard governance.effectiveBundle.schedule.brainstormReviewSeconds > 0 else { return false }
        switch governance.effectiveBundle.reviewPolicyMode {
        case .hybrid, .aggressive:
            break
        case .off, .milestoneOnly, .periodic:
            return false
        }
        guard let schedule else { return true }
        return schedule.nextBrainstormReviewDueAtMs > 0 && nowMs >= schedule.nextBrainstormReviewDueAtMs
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
        switch executionTier {
        case .a0Observe, .a1Plan:
            return [.preDoneSummary]
        case .a2RepoAuto:
            return [.blockerDetected, .preDoneSummary]
        case .a3DeliverAuto:
            return [.blockerDetected, .planDrift, .preDoneSummary]
        case .a4OpenClaw:
            return [.blockerDetected, .preHighRiskAction, .preDoneSummary]
        }
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
