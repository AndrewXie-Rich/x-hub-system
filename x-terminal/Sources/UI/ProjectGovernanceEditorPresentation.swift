import Foundation

enum ProjectGovernanceStatusBadgeTone: Equatable, Sendable {
    case current
    case configured
    case effective
    case recommended
    case safeFloor
    case belowSafeFloor
}

struct ProjectGovernanceStatusBadge: Equatable, Sendable {
    let label: String
    let tone: ProjectGovernanceStatusBadgeTone
}

struct ProjectExecutionTierCardPresentation: Equatable, Sendable {
    let statusBadges: [ProjectGovernanceStatusBadge]
    let accessibilityStateLabel: String

    init(
        tier: AXProjectExecutionTier,
        configuredTier: AXProjectExecutionTier,
        effectiveTier: AXProjectExecutionTier
    ) {
        if configuredTier == tier && effectiveTier == tier {
            statusBadges = [
                ProjectGovernanceStatusBadge(label: "Current", tone: .current)
            ]
        } else {
            var badges: [ProjectGovernanceStatusBadge] = []
            if configuredTier == tier {
                badges.append(ProjectGovernanceStatusBadge(label: "Configured", tone: .configured))
            }
            if effectiveTier == tier {
                badges.append(ProjectGovernanceStatusBadge(label: "Effective", tone: .effective))
            }
            statusBadges = badges
        }

        switch (configuredTier == tier, effectiveTier == tier) {
        case (true, true):
            accessibilityStateLabel = "current"
        case (true, false):
            accessibilityStateLabel = "configured"
        case (false, true):
            accessibilityStateLabel = "effective"
        default:
            accessibilityStateLabel = "available"
        }
    }
}

struct ProjectSupervisorTierCardPresentation: Equatable, Sendable {
    let statusBadges: [ProjectGovernanceStatusBadge]
    let accessibilityStateLabel: String

    init(
        tier: AXProjectSupervisorInterventionTier,
        currentExecutionTier: AXProjectExecutionTier,
        configuredTier: AXProjectSupervisorInterventionTier,
        effectiveTier: AXProjectSupervisorInterventionTier
    ) {
        var badges: [ProjectGovernanceStatusBadge] = []

        if configuredTier == tier && effectiveTier == tier {
            badges.append(ProjectGovernanceStatusBadge(label: "Current", tone: .current))
        } else {
            if configuredTier == tier {
                badges.append(ProjectGovernanceStatusBadge(label: "Configured", tone: .configured))
            }
            if effectiveTier == tier {
                badges.append(ProjectGovernanceStatusBadge(label: "Effective", tone: .effective))
            }
        }

        if tier == currentExecutionTier.defaultSupervisorInterventionTier {
            badges.append(ProjectGovernanceStatusBadge(label: "Recommended", tone: .recommended))
        }
        if tier == currentExecutionTier.minimumSafeSupervisorTier {
            badges.append(ProjectGovernanceStatusBadge(label: "Safe Floor", tone: .safeFloor))
        } else if tier < currentExecutionTier.minimumSafeSupervisorTier {
            badges.append(ProjectGovernanceStatusBadge(label: "Below Safe Floor", tone: .belowSafeFloor))
        }

        statusBadges = badges

        switch (configuredTier == tier, effectiveTier == tier) {
        case (true, true):
            accessibilityStateLabel = "current"
        case (true, false):
            accessibilityStateLabel = "configured"
        case (false, true):
            accessibilityStateLabel = "effective"
        default:
            accessibilityStateLabel = "available"
        }
    }
}

struct ProjectHeartbeatReviewBaselineInput: Equatable, Sendable {
    let trigger: SupervisorReviewTrigger
    let reviewLevel: SupervisorReviewLevel
    let runKind: SupervisorReviewRunKind
    let reason: String
}

struct ProjectHeartbeatReviewEditorPresentation: Equatable, Sendable {
    let mandatoryTriggers: [AXProjectReviewTrigger]
    let optionalTriggers: [AXProjectReviewTrigger]
    let derivedTriggers: [AXProjectReviewTrigger]
    let baselineDecisionInput: ProjectHeartbeatReviewBaselineInput
    let baselineDecision: SupervisorReviewPolicyDecision
    let baselineDecisionSummary: String

    init(
        configuredExecutionTier: AXProjectExecutionTier,
        configuredReviewPolicyMode: AXProjectReviewPolicyMode,
        reviewPulseSeconds: Int,
        brainstormReviewSeconds: Int,
        resolvedGovernance: AXProjectResolvedGovernanceState
    ) {
        let mandatory = configuredExecutionTier.mandatoryReviewTriggers
        mandatoryTriggers = mandatory
        optionalTriggers = AXProjectReviewTrigger.governanceOptionalSelectableCases.filter {
            !mandatory.contains($0)
        }

        var derived: [AXProjectReviewTrigger] = [.manualRequest, .userOverride]
        if configuredReviewPolicyMode.supportsPulseCadence && reviewPulseSeconds > 0 {
            derived.append(.periodicPulse)
        }
        if configuredReviewPolicyMode.supportsBrainstormCadence && brainstormReviewSeconds > 0 {
            derived.append(.noProgressWindow)
        }
        derivedTriggers = AXProjectReviewTrigger.normalizedList(derived)

        if configuredReviewPolicyMode.supportsBrainstormCadence && brainstormReviewSeconds > 0 {
            baselineDecisionInput = ProjectHeartbeatReviewBaselineInput(
                trigger: .noProgressWindow,
                reviewLevel: .r2Strategic,
                runKind: .brainstorm,
                reason: "brainstorm cadence"
            )
        } else if configuredReviewPolicyMode.supportsPulseCadence && reviewPulseSeconds > 0 {
            baselineDecisionInput = ProjectHeartbeatReviewBaselineInput(
                trigger: .periodicPulse,
                reviewLevel: .r1Pulse,
                runKind: .pulse,
                reason: "pulse cadence"
            )
        } else {
            baselineDecisionInput = ProjectHeartbeatReviewBaselineInput(
                trigger: .manualRequest,
                reviewLevel: .r1Pulse,
                runKind: .manual,
                reason: "manual review"
            )
        }

        baselineDecision = SupervisorReviewPolicyEngine.resolve(
            governance: resolvedGovernance,
            trigger: baselineDecisionInput.trigger,
            requestedReviewLevel: baselineDecisionInput.reviewLevel,
            verdict: .watch,
            requestedDeliveryMode: .contextAppend,
            requestedAckRequired: false,
            runKind: baselineDecisionInput.runKind
        )
        baselineDecisionSummary =
            "\(baselineDecisionInput.reason) -> \(baselineDecisionInput.trigger.displayName) · \(baselineDecision.reviewLevel.displayName) · \(baselineDecision.policyReason)"
    }
}
