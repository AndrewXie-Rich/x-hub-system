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

extension AXProjectReviewTrigger {
    static var governanceOptionalSelectableCases: [AXProjectReviewTrigger] {
        [
            .failureStreak,
            .blockerDetected,
            .planDrift,
            .preHighRiskAction,
            .preDoneSummary
        ]
    }

    static func normalizedSelectionForExecutionTierTransition(
        to executionTier: AXProjectExecutionTier,
        preserving current: [AXProjectReviewTrigger]
    ) -> [AXProjectReviewTrigger] {
        let optionalTriggers = current.filter {
            governanceOptionalSelectableCases.contains($0)
                && !executionTier.mandatoryReviewTriggers.contains($0)
        }
        let defaultExtras = executionTier.defaultEventReviewTriggers.filter {
            !executionTier.mandatoryReviewTriggers.contains($0)
        }
        return normalizedList(
            executionTier.mandatoryReviewTriggers + optionalTriggers + defaultExtras
        )
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
        effectiveRuntimeSurface: AXProjectRuntimeSurfaceEffectivePolicy,
        trustedAutomationStatus: AXTrustedAutomationProjectStatus
    ) -> AXProjectCapabilityBundle {
        var out = self
        out.allowBrowserRuntime = out.allowBrowserRuntime && effectiveRuntimeSurface.allowBrowserRuntime
        out.allowDeviceTools = out.allowDeviceTools
            && effectiveRuntimeSurface.allowDeviceTools
            && trustedAutomationStatus.trustedAutomationReady
            && trustedAutomationStatus.permissionOwnerReady
        out.allowConnectorActions = out.allowConnectorActions && effectiveRuntimeSurface.allowConnectorActions
        out.allowExtensions = out.allowExtensions && effectiveRuntimeSurface.allowExtensions
        out.allowAutoLocalApproval = out.allowAutoLocalApproval && out.allowDeviceTools
        return out
    }

    @available(*, deprecated, message: "Use applying(effectiveRuntimeSurface:trustedAutomationStatus:)")
    func applying(
        effectiveAutonomy: AXProjectAutonomyEffectivePolicy,
        trustedAutomationStatus: AXTrustedAutomationProjectStatus
    ) -> AXProjectCapabilityBundle {
        applying(
            effectiveRuntimeSurface: effectiveAutonomy,
            trustedAutomationStatus: trustedAutomationStatus
        )
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
    var effectiveRuntimeSurface: AXProjectRuntimeSurfaceEffectivePolicy
    var trustedAutomationStatus: AXTrustedAutomationProjectStatus

    @available(*, deprecated, message: "Use effectiveRuntimeSurface")
    var effectiveAutonomy: AXProjectAutonomyEffectivePolicy {
        get { effectiveRuntimeSurface }
        set { effectiveRuntimeSurface = newValue }
    }

    func debugSnapshot() -> [String: JSONValue] {
        let runtimeSurface = effectiveRuntimeSurface
        let projectAIStrengthProfile = supervisorAdaptation.projectAIStrengthProfile
        let schedule = effectiveBundle.schedule
        var snapshot: [String: JSONValue] = [:]
        snapshot["project_id"] = .string(projectId)
        snapshot["compat_source"] = .string(compatSource.rawValue)
        snapshot["execution_tier"] = .string(configuredBundle.executionTier.rawValue)
        snapshot["effective_execution_tier"] = .string(effectiveBundle.executionTier.rawValue)
        snapshot["supervisor_intervention_tier"] = .string(configuredBundle.supervisorInterventionTier.rawValue)
        snapshot["recommended_supervisor_intervention_tier"] = .string(supervisorAdaptation.recommendedSupervisorTier.rawValue)
        snapshot["effective_supervisor_intervention_tier"] = .string(effectiveBundle.supervisorInterventionTier.rawValue)
        snapshot["recommended_supervisor_work_order_depth"] = .string(supervisorAdaptation.recommendedWorkOrderDepth.rawValue)
        snapshot["effective_supervisor_work_order_depth"] = .string(supervisorAdaptation.effectiveWorkOrderDepth.rawValue)
        snapshot["supervisor_adaptation_mode"] = .string(supervisorAdaptation.adaptationPolicy.adaptationMode.rawValue)
        snapshot["supervisor_escalation_reasons"] = .array(supervisorAdaptation.escalationReasons.map(JSONValue.string))
        snapshot["project_ai_strength_band"] = .string(projectAIStrengthProfile?.strengthBand.rawValue ?? AXProjectAIStrengthBand.unknown.rawValue)
        snapshot["project_ai_strength_confidence"] = .number(projectAIStrengthProfile?.confidence ?? 0)
        snapshot["project_ai_strength_reasons"] = .array((projectAIStrengthProfile?.reasons ?? []).map(JSONValue.string))
        snapshot["project_ai_strength_audit_ref"] = .string(projectAIStrengthProfile?.auditRef ?? "")
        snapshot["review_policy_mode"] = .string(effectiveBundle.reviewPolicyMode.rawValue)
        snapshot["project_memory_ceiling"] = .string(projectMemoryCeiling.rawValue)
        snapshot["supervisor_review_memory_ceiling"] = .string(supervisorReviewMemoryCeiling.rawValue)
        snapshot["progress_heartbeat_sec"] = .number(Double(schedule.progressHeartbeatSeconds))
        snapshot["review_pulse_sec"] = .number(Double(schedule.reviewPulseSeconds))
        snapshot["brainstorm_review_sec"] = .number(Double(schedule.brainstormReviewSeconds))
        snapshot["event_driven_review_enabled"] = .bool(schedule.eventDrivenReviewEnabled)
        snapshot["event_review_triggers"] = .array(schedule.eventReviewTriggers.map { .string($0.rawValue) })
        snapshot["invalid_reasons"] = .array(validation.invalidReasons.map(JSONValue.string))
        snapshot["warning_reasons"] = .array(validation.warningReasons.map(JSONValue.string))
        snapshot["should_fail_closed"] = .bool(validation.shouldFailClosed)
        snapshot["runtime_surface_effective_mode"] = .string(runtimeSurface.effectiveMode.rawValue)
        snapshot["runtime_surface_hub_override_mode"] = .string(runtimeSurface.hubOverrideMode.rawValue)
        snapshot["runtime_surface_ttl_sec"] = .number(Double(runtimeSurface.ttlSeconds))
        snapshot["runtime_surface_remaining_sec"] = .number(Double(runtimeSurface.remainingSeconds))
        snapshot["runtime_surface_expired"] = .bool(runtimeSurface.expired)
        snapshot["runtime_surface_kill_switch_engaged"] = .bool(runtimeSurface.killSwitchEngaged)
        snapshot["effective_autonomy_mode"] = .string(runtimeSurface.effectiveMode.rawValue)
        snapshot["hub_override_mode"] = .string(runtimeSurface.hubOverrideMode.rawValue)
        snapshot["autonomy_ttl_sec"] = .number(Double(runtimeSurface.ttlSeconds))
        snapshot["autonomy_remaining_sec"] = .number(Double(runtimeSurface.remainingSeconds))
        snapshot["autonomy_expired"] = .bool(runtimeSurface.expired)
        snapshot["kill_switch_engaged"] = .bool(runtimeSurface.killSwitchEngaged)
        snapshot["trusted_automation_state"] = .string(trustedAutomationStatus.state.rawValue)
        snapshot["trusted_automation_ready"] = .bool(trustedAutomationStatus.trustedAutomationReady)
        snapshot["permission_owner_ready"] = .bool(trustedAutomationStatus.permissionOwnerReady)
        snapshot["allowed_capabilities"] = .array(capabilityBundle.allowedCapabilityLabels.map(JSONValue.string))
        return snapshot
    }
}
