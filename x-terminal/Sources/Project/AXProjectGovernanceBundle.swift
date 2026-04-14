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

enum AXProjectGovernanceRuntimeReadinessState: String, Codable, Equatable, Sendable {
    case notRequired = "not_required"
    case ready
    case blocked
}

enum AXProjectGovernanceRuntimeReadinessComponentKey: String, Codable, CaseIterable, Sendable {
    case routeReady = "route_ready"
    case capabilityReady = "capability_ready"
    case grantReady = "grant_ready"
    case checkpointRecoveryReady = "checkpoint_recovery_ready"
    case evidenceExportReady = "evidence_export_ready"

    var displayName: String {
        switch self {
        case .routeReady:
            return "route ready"
        case .capabilityReady:
            return "capability ready"
        case .grantReady:
            return "grant ready"
        case .checkpointRecoveryReady:
            return "checkpoint/recovery ready"
        case .evidenceExportReady:
            return "evidence/export ready"
        }
    }
}

enum AXProjectGovernanceRuntimeReadinessComponentState: String, Codable, Equatable, Sendable {
    case notRequired = "not_required"
    case ready
    case blocked
    case notReported = "not_reported"

    var displayName: String {
        switch self {
        case .notRequired:
            return "不要求"
        case .ready:
            return "已就绪"
        case .blocked:
            return "未就绪"
        case .notReported:
            return "未接线"
        }
    }
}

struct AXProjectGovernanceRuntimeReadinessComponentProjection: Codable, Equatable, Sendable {
    var key: AXProjectGovernanceRuntimeReadinessComponentKey
    var state: AXProjectGovernanceRuntimeReadinessComponentState
    var missingReasonCodes: [String]
    var summaryLine: String

    func detailLines() -> [String] {
        let prefix = "project_governance_runtime_component_\(key.rawValue)"
        var lines = [
            "\(prefix)_state=\(state.rawValue)",
            "\(prefix)_summary=\(summaryLine)"
        ]
        if !missingReasonCodes.isEmpty {
            lines.append("\(prefix)_missing=\(missingReasonCodes.joined(separator: ","))")
        }
        return lines
    }
}

struct AXProjectGovernanceRuntimeReadinessSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xhub.project_governance_runtime_readiness.v1"

    var schemaVersion: String
    var configuredExecutionTier: String
    var effectiveExecutionTier: String
    var configuredRuntimeSurfaceMode: String
    var effectiveRuntimeSurfaceMode: String
    var runtimeSurfaceOverrideMode: String
    var trustedAutomationState: String
    var requiresA4RuntimeReady: Bool
    var runtimeReady: Bool
    var state: AXProjectGovernanceRuntimeReadinessState
    var missingReasonCodes: [String]
    var effectiveSurfaceCapabilityLabels: [String]?
    var summaryLine: String
    var missingSummaryLine: String?

    init(resolved: AXProjectResolvedGovernanceState) {
        let configuredExecutionTier = resolved.configuredBundle.executionTier
        let effectiveExecutionTier = resolved.effectiveBundle.executionTier
        let runtimeSurface = resolved.effectiveRuntimeSurface
        let trustedAutomationStatus = resolved.trustedAutomationStatus
        let requiresA4RuntimeReady = configuredExecutionTier == .a4OpenClaw
        let missingReasonCodes = requiresA4RuntimeReady
            ? Self.normalizedReasonCodes(
                Self.routeMissingReasonCodes(
                    configuredRuntimeSurfaceMode: runtimeSurface.configuredMode,
                    runtimeSurfaceOverrideMode: runtimeSurface.hubOverrideMode
                )
                + Self.capabilityMissingReasonCodes(
                    effectiveSurfaceCapabilityLabels: runtimeSurface.allowedSurfaceLabels,
                    trustedAutomationReady: trustedAutomationStatus.trustedAutomationReady,
                    permissionOwnerReady: trustedAutomationStatus.permissionOwnerReady
                )
                + Self.grantMissingReasonCodes(
                    shouldFailClosed: resolved.validation.shouldFailClosed,
                    expired: runtimeSurface.expired,
                    killSwitchEngaged: runtimeSurface.killSwitchEngaged
                )
            )
            : []

        let runtimeReady = !requiresA4RuntimeReady || missingReasonCodes.isEmpty
        let state: AXProjectGovernanceRuntimeReadinessState
        if !requiresA4RuntimeReady {
            state = .notRequired
        } else if runtimeReady {
            state = .ready
        } else {
            state = .blocked
        }

        self.schemaVersion = Self.currentSchemaVersion
        self.configuredExecutionTier = configuredExecutionTier.rawValue
        self.effectiveExecutionTier = effectiveExecutionTier.rawValue
        self.configuredRuntimeSurfaceMode = runtimeSurface.configuredMode.rawValue
        self.effectiveRuntimeSurfaceMode = runtimeSurface.effectiveMode.rawValue
        self.runtimeSurfaceOverrideMode = runtimeSurface.hubOverrideMode.rawValue
        self.trustedAutomationState = trustedAutomationStatus.state.rawValue
        self.requiresA4RuntimeReady = requiresA4RuntimeReady
        self.runtimeReady = runtimeReady
        self.state = state
        self.missingReasonCodes = missingReasonCodes
        self.effectiveSurfaceCapabilityLabels = runtimeSurface.allowedSurfaceLabels

        switch state {
        case .notRequired:
            summaryLine = "\(configuredExecutionTier.displayName) 当前不要求 A4 execution-surface runtime ready。"
            missingSummaryLine = nil
        case .ready:
            summaryLine = "A4 Agent 已配置，runtime ready 已就绪。"
            missingSummaryLine = nil
        case .blocked:
            summaryLine = "A4 Agent 已配置，但 runtime ready 还没完成。"
            missingSummaryLine = "缺口：\(Self.reasonSummary(missingReasonCodes))"
        }
    }

    init?(
        detailLines: [String]
    ) {
        func value(_ key: String) -> String? {
            let prefix = "\(key)="
            guard let line = detailLines.first(where: { $0.hasPrefix(prefix) }) else {
                return nil
            }
            let value = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        func listValue(_ key: String) -> [String]? {
            let prefix = "\(key)="
            guard let line = detailLines.first(where: { $0.hasPrefix(prefix) }) else {
                return nil
            }
            let raw = String(line.dropFirst(prefix.count))
            return raw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        func boolValue(_ key: String) -> Bool? {
            switch value(key)?.lowercased() {
            case "true":
                return true
            case "false":
                return false
            default:
                return nil
            }
        }

        guard let stateRaw = value("project_governance_runtime_readiness_state"),
              let state = AXProjectGovernanceRuntimeReadinessState(rawValue: stateRaw),
              let configuredExecutionTier = value("project_governance_configured_execution_tier"),
              let effectiveExecutionTier = value("project_governance_effective_execution_tier"),
              let configuredRuntimeSurfaceMode = value("project_governance_configured_runtime_surface_mode"),
              let effectiveRuntimeSurfaceMode = value("project_governance_effective_runtime_surface_mode"),
              let runtimeSurfaceOverrideMode = value("project_governance_runtime_surface_override_mode"),
              let trustedAutomationState = value("project_governance_trusted_automation_state"),
              let requiresA4RuntimeReady = boolValue("project_governance_requires_a4_runtime_ready"),
              let runtimeReady = boolValue("project_governance_runtime_ready"),
              let summaryLine = value("project_governance_runtime_readiness_summary") else {
            return nil
        }

        self.schemaVersion = value("project_governance_runtime_readiness_schema_version")
            ?? Self.currentSchemaVersion
        self.configuredExecutionTier = configuredExecutionTier
        self.effectiveExecutionTier = effectiveExecutionTier
        self.configuredRuntimeSurfaceMode = configuredRuntimeSurfaceMode
        self.effectiveRuntimeSurfaceMode = effectiveRuntimeSurfaceMode
        self.runtimeSurfaceOverrideMode = runtimeSurfaceOverrideMode
        self.trustedAutomationState = trustedAutomationState
        self.requiresA4RuntimeReady = requiresA4RuntimeReady
        self.runtimeReady = runtimeReady
        self.state = state
        self.missingReasonCodes = Self.normalizedReasonCodes(
            listValue("project_governance_missing_readiness") ?? []
        )
        self.effectiveSurfaceCapabilityLabels = listValue(
            "project_governance_effective_surface_capabilities"
        )
        self.summaryLine = summaryLine
        self.missingSummaryLine = value("project_governance_runtime_readiness_missing_summary")
    }

    func detailLines() -> [String] {
        var lines = [
            "project_governance_runtime_readiness_schema_version=\(schemaVersion)",
            "project_governance_configured_execution_tier=\(configuredExecutionTier)",
            "project_governance_effective_execution_tier=\(effectiveExecutionTier)",
            "project_governance_configured_runtime_surface_mode=\(configuredRuntimeSurfaceMode)",
            "project_governance_effective_runtime_surface_mode=\(effectiveRuntimeSurfaceMode)",
            "project_governance_runtime_surface_override_mode=\(runtimeSurfaceOverrideMode)",
            "project_governance_trusted_automation_state=\(trustedAutomationState)",
            "project_governance_requires_a4_runtime_ready=\(requiresA4RuntimeReady)",
            "project_governance_runtime_ready=\(runtimeReady)",
            "project_governance_runtime_readiness_state=\(state.rawValue)",
            "project_governance_effective_surface_capabilities=\(effectiveSurfaceCapabilityLabelsResolved.joined(separator: ","))",
            "project_governance_runtime_readiness_summary=\(summaryLine)"
        ]
        if !missingReasonCodes.isEmpty {
            lines.append("project_governance_missing_readiness=\(missingReasonCodes.joined(separator: ","))")
        }
        if let missingSummaryLine, !missingSummaryLine.isEmpty {
            lines.append("project_governance_runtime_readiness_missing_summary=\(missingSummaryLine)")
        }
        for component in componentProjections {
            lines += component.detailLines()
        }
        return lines
    }

    var runtimeReadyLine: String {
        switch state {
        case .notRequired:
            return "runtime ready：当前档位不要求"
        case .ready:
            return "runtime ready：已就绪"
        case .blocked:
            return "runtime ready：未就绪"
        }
    }

    var effectiveSurfaceCapabilityLabelsResolved: [String] {
        if let effectiveSurfaceCapabilityLabels {
            return Self.normalizedSurfaceLabels(effectiveSurfaceCapabilityLabels)
        }
        return Self.defaultEffectiveSurfaceCapabilityLabels(
            for: effectiveRuntimeSurfaceMode
        )
    }

    var componentProjections: [AXProjectGovernanceRuntimeReadinessComponentProjection] {
        [
            routeComponentProjection,
            capabilityComponentProjection,
            grantComponentProjection,
            checkpointRecoveryComponentProjection,
            evidenceExportComponentProjection
        ]
    }

    static func reasonText(_ code: String) -> String {
        switch code {
        case "governance_fail_closed":
            return "治理冲突触发 fail-closed"
        case "runtime_surface_not_configured_full":
            return "完整执行面还没配置到 trusted_openclaw_mode"
        case "runtime_surface_kill_switch":
            return "kill-switch 已生效"
        case "runtime_surface_ttl_expired":
            return "runtime surface TTL 已过期"
        case "runtime_surface_clamped_guided":
            return "执行面被收束到 guided"
        case "runtime_surface_clamped_manual":
            return "执行面被收束到 manual"
        case "trusted_automation_not_ready":
            return "受治理自动化未就绪"
        case "permission_owner_not_ready":
            return "权限宿主未就绪"
        case "capability_device_tools_unavailable":
            return "A4 基线 device tools 未打开"
        case "checkpoint_recovery_contract_not_ready":
            return "checkpoint / recovery 合同还没就绪"
        case "evidence_export_contract_not_ready":
            return "evidence / export 合同还没就绪"
        case "preferred_device_offline":
            return "首选 XT 设备当前离线"
        case "preferred_device_missing":
            return "首选 XT 设备不存在"
        case "preferred_device_project_scope_mismatch":
            return "首选 XT 设备不在当前 project scope"
        case "xt_device_missing":
            return "没有可路由的 XT 设备"
        case "runner_device_missing":
            return "没有可路由的 runner 设备"
        case "xt_route_ambiguous":
            return "XT 路由目标不唯一"
        case "runner_route_ambiguous":
            return "runner 路由目标不唯一"
        case "supervisor_intent_unknown":
            return "Supervisor 意图无法判定"
        case "project_id_required":
            return "当前动作缺少 project 绑定"
        default:
            return code.replacingOccurrences(of: "_", with: " ")
        }
    }

    static func reasonSummary(_ codes: [String]) -> String {
        let normalized = codes.map(reasonText)
        return normalized.isEmpty ? "无" : normalized.joined(separator: " / ")
    }

    private var routeComponentProjection: AXProjectGovernanceRuntimeReadinessComponentProjection {
        guard requiresA4RuntimeReady else {
            return AXProjectGovernanceRuntimeReadinessComponentProjection(
                key: .routeReady,
                state: .notRequired,
                missingReasonCodes: [],
                summaryLine: "当前执行档位不要求 A4 route readiness。"
            )
        }

        let routeMissingReasonCodes = Self.routeMissingReasonCodes(
            configuredRuntimeSurfaceMode: configuredRuntimeSurfaceMode,
            runtimeSurfaceOverrideMode: runtimeSurfaceOverrideMode
        )
        if routeMissingReasonCodes.isEmpty {
            return AXProjectGovernanceRuntimeReadinessComponentProjection(
                key: .routeReady,
                state: .ready,
                missingReasonCodes: [],
                summaryLine: "A4 执行面路由已指向 trusted_openclaw_mode。"
            )
        }

        return AXProjectGovernanceRuntimeReadinessComponentProjection(
            key: .routeReady,
            state: .blocked,
            missingReasonCodes: routeMissingReasonCodes,
            summaryLine: "当前还缺 \(Self.reasonSummary(routeMissingReasonCodes))；实际执行面 \(effectiveRuntimeSurfaceMode)。"
        )
    }

    private var capabilityComponentProjection: AXProjectGovernanceRuntimeReadinessComponentProjection {
        guard requiresA4RuntimeReady else {
            return AXProjectGovernanceRuntimeReadinessComponentProjection(
                key: .capabilityReady,
                state: .notRequired,
                missingReasonCodes: [],
                summaryLine: "当前执行档位不要求 A4 capability readiness。"
            )
        }

        let capabilityMissingReasonCodes = Self.capabilityMissingReasonCodes(
            effectiveSurfaceCapabilityLabels: effectiveSurfaceCapabilityLabelsResolved
        )
        let surfaceSummary = Self.surfaceCapabilitySummary(
            effectiveSurfaceCapabilityLabelsResolved
        )
        if capabilityMissingReasonCodes.isEmpty {
            return AXProjectGovernanceRuntimeReadinessComponentProjection(
                key: .capabilityReady,
                state: .ready,
                missingReasonCodes: [],
                summaryLine: "A4 基线执行能力已打开；当前 surface：\(surfaceSummary)。"
            )
        }

        return AXProjectGovernanceRuntimeReadinessComponentProjection(
            key: .capabilityReady,
            state: .blocked,
            missingReasonCodes: capabilityMissingReasonCodes,
            summaryLine: "当前还缺 \(Self.reasonSummary(capabilityMissingReasonCodes))；当前 surface：\(surfaceSummary)。"
        )
    }

    private var grantComponentProjection: AXProjectGovernanceRuntimeReadinessComponentProjection {
        guard requiresA4RuntimeReady else {
            return AXProjectGovernanceRuntimeReadinessComponentProjection(
                key: .grantReady,
                state: .notRequired,
                missingReasonCodes: [],
                summaryLine: "当前执行档位不要求高治理放行窗口。"
            )
        }

        let grantMissingReasonCodes = Self.grantMissingReasonCodes(
            missingReasonCodes: missingReasonCodes
        )
        if grantMissingReasonCodes.isEmpty {
            return AXProjectGovernanceRuntimeReadinessComponentProjection(
                key: .grantReady,
                state: .ready,
                missingReasonCodes: [],
                summaryLine: "当前没有 fail-closed / TTL / kill-switch 阻断。"
            )
        }

        return AXProjectGovernanceRuntimeReadinessComponentProjection(
            key: .grantReady,
            state: .blocked,
            missingReasonCodes: grantMissingReasonCodes,
            summaryLine: "当前还缺 \(Self.reasonSummary(grantMissingReasonCodes))。"
        )
    }

    private var checkpointRecoveryComponentProjection: AXProjectGovernanceRuntimeReadinessComponentProjection {
        guard requiresA4RuntimeReady else {
            return AXProjectGovernanceRuntimeReadinessComponentProjection(
                key: .checkpointRecoveryReady,
                state: .notRequired,
                missingReasonCodes: [],
                summaryLine: "当前执行档位不要求 checkpoint / recovery readiness。"
            )
        }

        let missingReasonCodes = Self.checkpointRecoveryMissingReasonCodes(
            effectiveExecutionTier: effectiveExecutionTier
        )
        if missingReasonCodes.isEmpty {
            return AXProjectGovernanceRuntimeReadinessComponentProjection(
                key: .checkpointRecoveryReady,
                state: .ready,
                missingReasonCodes: [],
                summaryLine: "checkpoint / recovery 预算与自动恢复能力已就绪。"
            )
        }

        return AXProjectGovernanceRuntimeReadinessComponentProjection(
            key: .checkpointRecoveryReady,
            state: .blocked,
            missingReasonCodes: missingReasonCodes,
            summaryLine: "当前还缺 \(Self.reasonSummary(missingReasonCodes))。"
        )
    }

    private var evidenceExportComponentProjection: AXProjectGovernanceRuntimeReadinessComponentProjection {
        guard requiresA4RuntimeReady else {
            return AXProjectGovernanceRuntimeReadinessComponentProjection(
                key: .evidenceExportReady,
                state: .notRequired,
                missingReasonCodes: [],
                summaryLine: "当前执行档位不要求 evidence / export readiness。"
            )
        }

        let missingReasonCodes = Self.evidenceExportMissingReasonCodes(
            effectiveExecutionTier: effectiveExecutionTier
        )
        if missingReasonCodes.isEmpty {
            return AXProjectGovernanceRuntimeReadinessComponentProjection(
                key: .evidenceExportReady,
                state: .ready,
                missingReasonCodes: [],
                summaryLine: "evidence / export 合同已要求证据闭环与 pre-done 收口。"
            )
        }

        return AXProjectGovernanceRuntimeReadinessComponentProjection(
            key: .evidenceExportReady,
            state: .blocked,
            missingReasonCodes: missingReasonCodes,
            summaryLine: "当前还缺 \(Self.reasonSummary(missingReasonCodes))。"
        )
    }

    private static func routeMissingReasonCodes(
        configuredRuntimeSurfaceMode: AXProjectRuntimeSurfaceMode,
        runtimeSurfaceOverrideMode: AXProjectRuntimeSurfaceHubOverrideMode
    ) -> [String] {
        var codes: [String] = []
        if configuredRuntimeSurfaceMode != .trustedOpenClawMode {
            codes.append("runtime_surface_not_configured_full")
        }
        switch runtimeSurfaceOverrideMode {
        case .clampGuided:
            codes.append("runtime_surface_clamped_guided")
        case .clampManual:
            codes.append("runtime_surface_clamped_manual")
        case .killSwitch, .none:
            break
        }
        return normalizedReasonCodes(codes)
    }

    private static func routeMissingReasonCodes(
        configuredRuntimeSurfaceMode: String,
        runtimeSurfaceOverrideMode: String
    ) -> [String] {
        let configuredMode = AXProjectRuntimeSurfaceMode(rawValue: configuredRuntimeSurfaceMode)
        let overrideMode = AXProjectRuntimeSurfaceHubOverrideMode(rawValue: runtimeSurfaceOverrideMode)

        var codes: [String] = []
        if configuredMode != .trustedOpenClawMode {
            codes.append("runtime_surface_not_configured_full")
        }
        switch overrideMode {
        case .clampGuided?:
            codes.append("runtime_surface_clamped_guided")
        case .clampManual?:
            codes.append("runtime_surface_clamped_manual")
        case .killSwitch?, .some(.none), nil:
            break
        }
        return normalizedReasonCodes(codes)
    }

    private static func capabilityMissingReasonCodes(
        effectiveSurfaceCapabilityLabels: [String]
    ) -> [String] {
        let labels = Set(normalizedSurfaceLabels(effectiveSurfaceCapabilityLabels))
        var codes: [String] = []
        if !labels.contains("device") {
            codes.append("capability_device_tools_unavailable")
        }
        return normalizedReasonCodes(codes)
    }

    private static func capabilityMissingReasonCodes(
        effectiveSurfaceCapabilityLabels: [String],
        trustedAutomationReady: Bool,
        permissionOwnerReady: Bool
    ) -> [String] {
        var codes = capabilityMissingReasonCodes(
            effectiveSurfaceCapabilityLabels: effectiveSurfaceCapabilityLabels
        )
        if !trustedAutomationReady {
            codes.append("trusted_automation_not_ready")
        }
        if !permissionOwnerReady {
            codes.append("permission_owner_not_ready")
        }
        return normalizedReasonCodes(codes)
    }

    private static func grantMissingReasonCodes(
        shouldFailClosed: Bool,
        expired: Bool,
        killSwitchEngaged: Bool
    ) -> [String] {
        var codes: [String] = []
        if shouldFailClosed {
            codes.append("governance_fail_closed")
        }
        if killSwitchEngaged {
            codes.append("runtime_surface_kill_switch")
        }
        if expired {
            codes.append("runtime_surface_ttl_expired")
        }
        return normalizedReasonCodes(codes)
    }

    private static func grantMissingReasonCodes(
        missingReasonCodes: [String]
    ) -> [String] {
        let allowed = Set([
            "governance_fail_closed",
            "trusted_automation_not_ready",
            "permission_owner_not_ready",
            "runtime_surface_kill_switch",
            "runtime_surface_ttl_expired"
        ])
        return normalizedReasonCodes(
            missingReasonCodes.filter { allowed.contains($0) }
        )
    }

    private static func checkpointRecoveryMissingReasonCodes(
        effectiveExecutionTier: String
    ) -> [String] {
        guard let tier = AXProjectExecutionTier(rawValue: effectiveExecutionTier) else {
            return ["checkpoint_recovery_contract_not_ready"]
        }
        let budget = tier.defaultExecutionBudget
        let capabilityBundle = tier.baseCapabilityBundle
        let ready = budget.maxRetryDepth > 0 && capabilityBundle.allowManagedProcesses
        return ready ? [] : ["checkpoint_recovery_contract_not_ready"]
    }

    private static func evidenceExportMissingReasonCodes(
        effectiveExecutionTier: String
    ) -> [String] {
        guard let tier = AXProjectExecutionTier(rawValue: effectiveExecutionTier) else {
            return ["evidence_export_contract_not_ready"]
        }
        let budget = tier.defaultExecutionBudget
        let ready = budget.preDoneReviewRequired && budget.doneRequiresEvidence
        return ready ? [] : ["evidence_export_contract_not_ready"]
    }

    private static func normalizedReasonCodes(_ codes: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for raw in codes {
            let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, seen.insert(token).inserted else { continue }
            ordered.append(token)
        }
        return ordered
    }

    private static func normalizedSurfaceLabels(_ labels: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for raw in labels {
            let token = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !token.isEmpty, seen.insert(token).inserted else { continue }
            ordered.append(token)
        }
        return ordered
    }

    private static func defaultEffectiveSurfaceCapabilityLabels(for rawMode: String) -> [String] {
        guard let mode = AXProjectRuntimeSurfaceMode(rawValue: rawMode) else {
            return []
        }

        switch mode {
        case .manual:
            return []
        case .guided:
            return ["browser"]
        case .trustedOpenClawMode:
            return ["device", "browser", "connector", "extension"]
        }
    }

    private static func surfaceCapabilitySummary(_ labels: [String]) -> String {
        let normalized = normalizedSurfaceLabels(labels)
        return normalized.isEmpty ? "无" : normalized.joined(separator: " / ")
    }
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

    var runtimeReadinessSnapshot: AXProjectGovernanceRuntimeReadinessSnapshot {
        AXProjectGovernanceRuntimeReadinessSnapshot(resolved: self)
    }

    func debugSnapshot() -> [String: JSONValue] {
        let runtimeSurface = effectiveRuntimeSurface
        let projectAIStrengthProfile = supervisorAdaptation.projectAIStrengthProfile
        let schedule = effectiveBundle.schedule
        let runtimeReadiness = runtimeReadinessSnapshot
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
        snapshot["project_governance_runtime_ready"] = .bool(runtimeReadiness.runtimeReady)
        snapshot["project_governance_runtime_readiness_state"] = .string(runtimeReadiness.state.rawValue)
        snapshot["project_governance_requires_a4_runtime_ready"] = .bool(runtimeReadiness.requiresA4RuntimeReady)
        snapshot["project_governance_runtime_readiness_summary"] = .string(runtimeReadiness.summaryLine)
        snapshot["project_governance_runtime_readiness_missing_summary"] = .string(
            runtimeReadiness.missingSummaryLine ?? ""
        )
        snapshot["project_governance_effective_surface_capabilities"] = .array(
            runtimeReadiness.effectiveSurfaceCapabilityLabelsResolved.map(JSONValue.string)
        )
        snapshot["project_governance_missing_readiness"] = .array(
            runtimeReadiness.missingReasonCodes.map(JSONValue.string)
        )
        for component in runtimeReadiness.componentProjections {
            snapshot["project_governance_runtime_component_\(component.key.rawValue)_state"] = .string(component.state.rawValue)
            snapshot["project_governance_runtime_component_\(component.key.rawValue)_summary"] = .string(component.summaryLine)
            snapshot["project_governance_runtime_component_\(component.key.rawValue)_missing"] = .array(
                component.missingReasonCodes.map(JSONValue.string)
            )
        }
        snapshot["project_governance_runtime_readiness_components"] = .object(
            Dictionary(uniqueKeysWithValues: runtimeReadiness.componentProjections.map { component in
                (
                    component.key.rawValue,
                    .object([
                        "state": .string(component.state.rawValue),
                        "missing_reason_codes": .array(component.missingReasonCodes.map(JSONValue.string)),
                        "summary": .string(component.summaryLine)
                    ])
                )
            })
        )
        snapshot["allowed_capabilities"] = .array(capabilityBundle.allowedCapabilityLabels.map(JSONValue.string))
        return snapshot
    }
}
