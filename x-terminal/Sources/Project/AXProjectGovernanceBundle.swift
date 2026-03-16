import Foundation

enum AXProjectReviewPolicyMode: String, Codable, CaseIterable, Sendable {
    case off
    case milestoneOnly = "milestone_only"
    case periodic
    case hybrid
    case aggressive
}

enum AXProjectReviewTrigger: String, Codable, CaseIterable, Sendable {
    case periodicHeartbeat = "periodic_heartbeat"
    case periodicPulse = "periodic_pulse"
    case failureStreak = "failure_streak"
    case noProgressWindow = "no_progress_window"
    case blockerDetected = "blocker_detected"
    case planDrift = "plan_drift"
    case preHighRiskAction = "pre_high_risk_action"
    case preDoneSummary = "pre_done_summary"
    case manualRequest = "manual_request"
    case userOverride = "user_override"

    static func normalizedList(_ values: [AXProjectReviewTrigger]) -> [AXProjectReviewTrigger] {
        var seen = Set<AXProjectReviewTrigger>()
        var ordered: [AXProjectReviewTrigger] = []
        for value in values where seen.insert(value).inserted {
            ordered.append(value)
        }
        return ordered
    }
}

enum AXProjectGovernanceCompatSource: String, Codable, CaseIterable, Sendable {
    case explicitDualDial = "explicit_dual_dial"
    case legacyAutonomyLevel = "legacy_autonomy_level"
    case legacyAutonomyMode = "legacy_autonomy_mode"
    case defaultConservative = "default_conservative"
}

struct AXProjectGovernanceSchedule: Codable, Equatable, Sendable {
    var progressHeartbeatSeconds: Int
    var reviewPulseSeconds: Int
    var brainstormReviewSeconds: Int
    var eventDrivenReviewEnabled: Bool
    var eventReviewTriggers: [AXProjectReviewTrigger]

    func normalized(
        for executionTier: AXProjectExecutionTier,
        reviewPolicyMode: AXProjectReviewPolicyMode
    ) -> AXProjectGovernanceSchedule {
        var out = self
        out.progressHeartbeatSeconds = max(60, out.progressHeartbeatSeconds)
        out.reviewPulseSeconds = max(0, out.reviewPulseSeconds)
        out.brainstormReviewSeconds = max(0, out.brainstormReviewSeconds)
        out.eventReviewTriggers = AXProjectReviewTrigger.normalizedList(out.eventReviewTriggers)

        if reviewPolicyMode == .off || reviewPolicyMode == .milestoneOnly {
            out.reviewPulseSeconds = 0
            out.brainstormReviewSeconds = 0
        }

        if out.reviewPulseSeconds == 0 && reviewPolicyMode != .off && reviewPolicyMode != .milestoneOnly {
            out.reviewPulseSeconds = executionTier.defaultReviewPulseSeconds
        }
        if out.brainstormReviewSeconds == 0 && executionTier.defaultBrainstormReviewSeconds > 0 {
            out.brainstormReviewSeconds = executionTier.defaultBrainstormReviewSeconds
        }
        return out
    }
}

struct AXProjectGovernanceBundle: Codable, Equatable, Sendable {
    var executionTier: AXProjectExecutionTier
    var supervisorInterventionTier: AXProjectSupervisorInterventionTier
    var reviewPolicyMode: AXProjectReviewPolicyMode
    var schedule: AXProjectGovernanceSchedule

    func normalized() -> AXProjectGovernanceBundle {
        var out = self
        out.schedule = schedule.normalized(for: executionTier, reviewPolicyMode: reviewPolicyMode)
        return out
    }

    func applyingExecutionTierPreservingReviewConfiguration(
        _ executionTier: AXProjectExecutionTier
    ) -> AXProjectGovernanceBundle {
        var out = self
        out.executionTier = executionTier
        out.supervisorInterventionTier = max(
            out.supervisorInterventionTier,
            executionTier.minimumSafeSupervisorTier
        )
        return out
    }

    static func recommended(
        for executionTier: AXProjectExecutionTier,
        supervisorInterventionTier: AXProjectSupervisorInterventionTier? = nil
    ) -> AXProjectGovernanceBundle {
        let selectedSupervisorTier = supervisorInterventionTier ?? executionTier.defaultSupervisorInterventionTier
        return AXProjectGovernanceBundle(
            executionTier: executionTier,
            supervisorInterventionTier: selectedSupervisorTier,
            reviewPolicyMode: executionTier.defaultReviewPolicyMode,
            schedule: AXProjectGovernanceSchedule(
                progressHeartbeatSeconds: executionTier.defaultProgressHeartbeatSeconds,
                reviewPulseSeconds: executionTier.defaultReviewPulseSeconds,
                brainstormReviewSeconds: executionTier.defaultBrainstormReviewSeconds,
                eventDrivenReviewEnabled: executionTier.defaultEventDrivenReviewEnabled,
                eventReviewTriggers: executionTier.defaultEventReviewTriggers
            )
        ).normalized()
    }

    static let conservativeFallback = AXProjectGovernanceBundle.recommended(for: .a0Observe)
}

struct AXProjectCapabilityBundle: Equatable, Sendable {
    var allowJobPlanAuto: Bool
    var allowRepoWrite: Bool
    var allowRepoDeleteMove: Bool
    var allowRepoBuild: Bool
    var allowRepoTest: Bool
    var allowGitApply: Bool
    var allowManagedProcesses: Bool
    var allowProcessAutoRestart: Bool
    var allowGitCommit: Bool
    var allowGitPush: Bool
    var allowPRCreate: Bool
    var allowCIRead: Bool
    var allowCITrigger: Bool
    var allowBrowserRuntime: Bool
    var allowDeviceTools: Bool
    var allowConnectorActions: Bool
    var allowExtensions: Bool
    var allowAutoLocalApproval: Bool

    static let observeOnly = AXProjectCapabilityBundle(
        allowJobPlanAuto: false,
        allowRepoWrite: false,
        allowRepoDeleteMove: false,
        allowRepoBuild: false,
        allowRepoTest: false,
        allowGitApply: false,
        allowManagedProcesses: false,
        allowProcessAutoRestart: false,
        allowGitCommit: false,
        allowGitPush: false,
        allowPRCreate: false,
        allowCIRead: false,
        allowCITrigger: false,
        allowBrowserRuntime: false,
        allowDeviceTools: false,
        allowConnectorActions: false,
        allowExtensions: false,
        allowAutoLocalApproval: false
    )

    func applying(
        effectiveAutonomy: AXProjectAutonomyEffectivePolicy,
        trustedAutomationStatus: AXTrustedAutomationProjectStatus
    ) -> AXProjectCapabilityBundle {
        var out = self
        out.allowBrowserRuntime = out.allowBrowserRuntime && effectiveAutonomy.allowBrowserRuntime
        out.allowDeviceTools = out.allowDeviceTools
            && effectiveAutonomy.allowDeviceTools
            && trustedAutomationStatus.trustedAutomationReady
            && trustedAutomationStatus.permissionOwnerReady
        out.allowConnectorActions = out.allowConnectorActions && effectiveAutonomy.allowConnectorActions
        out.allowExtensions = out.allowExtensions && effectiveAutonomy.allowExtensions
        out.allowAutoLocalApproval = out.allowAutoLocalApproval && out.allowDeviceTools
        return out
    }

    var allowedCapabilityLabels: [String] {
        var labels: [String] = []
        if allowJobPlanAuto { labels.append("job.create") }
        if allowJobPlanAuto { labels.append("plan.upsert") }
        if allowRepoWrite { labels.append("repo.write") }
        if allowRepoDeleteMove { labels.append("repo.delete_move") }
        if allowRepoBuild { labels.append("repo.build") }
        if allowRepoTest { labels.append("repo.test") }
        if allowGitApply { labels.append("git.apply") }
        if allowManagedProcesses { labels.append("process.manage") }
        if allowProcessAutoRestart { labels.append("process.autorestart") }
        if allowGitCommit { labels.append("git.commit") }
        if allowGitPush { labels.append("git.push") }
        if allowPRCreate { labels.append("pr.create") }
        if allowCIRead { labels.append("ci.read") }
        if allowCITrigger { labels.append("ci.trigger") }
        if allowBrowserRuntime { labels.append("browser.runtime") }
        if allowDeviceTools { labels.append("device.tools") }
        if allowConnectorActions { labels.append("connector.actions") }
        if allowExtensions { labels.append("extensions.run") }
        if allowAutoLocalApproval { labels.append("local.auto_approve") }
        return labels
    }
}

struct AXProjectExecutionBudget: Equatable, Sendable {
    var maxContinuousRunMinutes: Int
    var maxToolCallsPerRun: Int
    var maxRetryDepth: Int
    var maxCostUSDSoft: Double
    var preDoneReviewRequired: Bool
    var doneRequiresEvidence: Bool
}

struct AXProjectGovernanceValidation: Equatable, Sendable {
    var minimumSafeSupervisorTier: AXProjectSupervisorInterventionTier
    var recommendedSupervisorTier: AXProjectSupervisorInterventionTier
    var invalidReasons: [String]
    var warningReasons: [String]

    var shouldFailClosed: Bool { !invalidReasons.isEmpty }
}

struct AXProjectResolvedGovernanceState: Equatable {
    var projectId: String
    var configuredBundle: AXProjectGovernanceBundle
    var effectiveBundle: AXProjectGovernanceBundle
    var supervisorAdaptation: AXProjectSupervisorAdaptationSnapshot
    var compatSource: AXProjectGovernanceCompatSource
    var projectMemoryCeiling: XTMemoryServingProfile
    var supervisorReviewMemoryCeiling: XTMemoryServingProfile
    var capabilityBundle: AXProjectCapabilityBundle
    var executionBudget: AXProjectExecutionBudget
    var validation: AXProjectGovernanceValidation
    var effectiveAutonomy: AXProjectAutonomyEffectivePolicy
    var trustedAutomationStatus: AXTrustedAutomationProjectStatus

    func debugSnapshot() -> [String: JSONValue] {
        [
            "project_id": .string(projectId),
            "compat_source": .string(compatSource.rawValue),
            "execution_tier": .string(configuredBundle.executionTier.rawValue),
            "effective_execution_tier": .string(effectiveBundle.executionTier.rawValue),
            "supervisor_intervention_tier": .string(configuredBundle.supervisorInterventionTier.rawValue),
            "recommended_supervisor_intervention_tier": .string(supervisorAdaptation.recommendedSupervisorTier.rawValue),
            "effective_supervisor_intervention_tier": .string(effectiveBundle.supervisorInterventionTier.rawValue),
            "recommended_supervisor_work_order_depth": .string(supervisorAdaptation.recommendedWorkOrderDepth.rawValue),
            "effective_supervisor_work_order_depth": .string(supervisorAdaptation.effectiveWorkOrderDepth.rawValue),
            "supervisor_adaptation_mode": .string(supervisorAdaptation.adaptationPolicy.adaptationMode.rawValue),
            "supervisor_escalation_reasons": .array(supervisorAdaptation.escalationReasons.map(JSONValue.string)),
            "project_ai_strength_band": .string(supervisorAdaptation.projectAIStrengthProfile?.strengthBand.rawValue ?? AXProjectAIStrengthBand.unknown.rawValue),
            "project_ai_strength_confidence": .number(supervisorAdaptation.projectAIStrengthProfile?.confidence ?? 0),
            "project_ai_strength_reasons": .array((supervisorAdaptation.projectAIStrengthProfile?.reasons ?? []).map(JSONValue.string)),
            "project_ai_strength_audit_ref": .string(supervisorAdaptation.projectAIStrengthProfile?.auditRef ?? ""),
            "review_policy_mode": .string(effectiveBundle.reviewPolicyMode.rawValue),
            "project_memory_ceiling": .string(projectMemoryCeiling.rawValue),
            "supervisor_review_memory_ceiling": .string(supervisorReviewMemoryCeiling.rawValue),
            "progress_heartbeat_sec": .number(Double(effectiveBundle.schedule.progressHeartbeatSeconds)),
            "review_pulse_sec": .number(Double(effectiveBundle.schedule.reviewPulseSeconds)),
            "brainstorm_review_sec": .number(Double(effectiveBundle.schedule.brainstormReviewSeconds)),
            "event_driven_review_enabled": .bool(effectiveBundle.schedule.eventDrivenReviewEnabled),
            "event_review_triggers": .array(effectiveBundle.schedule.eventReviewTriggers.map { .string($0.rawValue) }),
            "invalid_reasons": .array(validation.invalidReasons.map(JSONValue.string)),
            "warning_reasons": .array(validation.warningReasons.map(JSONValue.string)),
            "should_fail_closed": .bool(validation.shouldFailClosed),
            "effective_autonomy_mode": .string(effectiveAutonomy.effectiveMode.rawValue),
            "hub_override_mode": .string(effectiveAutonomy.hubOverrideMode.rawValue),
            "autonomy_ttl_sec": .number(Double(effectiveAutonomy.ttlSeconds)),
            "autonomy_remaining_sec": .number(Double(effectiveAutonomy.remainingSeconds)),
            "autonomy_expired": .bool(effectiveAutonomy.expired),
            "kill_switch_engaged": .bool(effectiveAutonomy.killSwitchEngaged),
            "trusted_automation_state": .string(trustedAutomationStatus.state.rawValue),
            "trusted_automation_ready": .bool(trustedAutomationStatus.trustedAutomationReady),
            "permission_owner_ready": .bool(trustedAutomationStatus.permissionOwnerReady),
            "allowed_capabilities": .array(capabilityBundle.allowedCapabilityLabels.map(JSONValue.string))
        ]
    }
}
