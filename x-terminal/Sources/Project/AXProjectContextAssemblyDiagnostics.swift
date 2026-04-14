import Foundation

private func xtProjectMemoryCompactJSONString<T: Encodable>(_ value: T) -> String? {
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(value),
          let text = String(data: data, encoding: .utf8) else {
        return nil
    }
    return text
}

private func xtProjectMemoryDecodeJSONObject<T: Decodable>(_ value: Any?) -> T? {
    guard let value else { return nil }
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value) else {
        return nil
    }
    return try? JSONDecoder().decode(T.self, from: data)
}

private func xtProjectMemoryDetailValue(
    _ key: String,
    from detailLines: [String]
) -> String? {
    guard let line = detailLines.first(where: { $0.hasPrefix("\(key)=") }) else {
        return nil
    }
    return String(line.dropFirst(key.count + 1))
}

private func xtProjectMemoryDecodeJSONString<T: Decodable>(
    _ type: T.Type,
    jsonString: String?
) -> T? {
    guard let jsonString,
          let data = jsonString.data(using: .utf8) else {
        return nil
    }
    return try? JSONDecoder().decode(T.self, from: data)
}

struct AXProjectContextAssemblyDiagnosticEvent: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = "xt.project_context_assembly_diagnostic_event.v6"

    var schemaVersion: String
    var createdAt: Double
    var projectId: String
    var projectDisplayName: String
    var role: String
    var stage: String
    var roleAwareMemoryMode: String
    var projectMemoryResolutionTrigger: String
    var memoryV1Source: String
    var memoryV1Freshness: String = ""
    var memoryV1CacheHit: Bool? = nil
    var remoteSnapshotCacheScope: String = ""
    var remoteSnapshotCachedAtMs: Int64? = nil
    var remoteSnapshotAgeMs: Int? = nil
    var remoteSnapshotTTLRemainingMs: Int? = nil
    var remoteSnapshotCachePosture: String = ""
    var remoteSnapshotInvalidationReason: String = ""
    var configuredRecentProjectDialogueProfile: String
    var recommendedRecentProjectDialogueProfile: String
    var effectiveRecentProjectDialogueProfile: String
    var recentProjectDialogueProfile: String
    var recentProjectDialogueSelectedPairs: Int
    var recentProjectDialogueFloorPairs: Int
    var recentProjectDialogueFloorSatisfied: Bool
    var recentProjectDialogueSource: String
    var recentProjectDialogueLowSignalDropped: Int
    var configuredProjectContextDepth: String
    var recommendedProjectContextDepth: String
    var effectiveProjectContextDepth: String
    var projectContextDepth: String
    var effectiveProjectServingProfile: String
    var aTierMemoryCeiling: String
    var projectMemoryCeilingHit: Bool
    var workflowPresent: Bool
    var executionEvidencePresent: Bool
    var reviewGuidancePresent: Bool
    var crossLinkHintsSelected: Int
    var personalMemoryExcludedReason: String
    var projectMemoryPolicy: XTProjectMemoryPolicySnapshot? = nil
    var policyMemoryAssemblyResolution: XTMemoryAssemblyResolution? = nil
    var memoryAssemblyResolution: XTMemoryAssemblyResolution? = nil
    var hubMemoryPromptProjection: HubMemoryPromptProjectionSnapshot? = nil
    var memoryAssemblyIssueCodes: [String] = []
    var memoryResolutionProjectionDriftDetail: String = ""
    var heartbeatDigestWorkingSetPresent: Bool = false
    var heartbeatDigestVisibility: String = ""
    var heartbeatDigestReasonCodes: [String] = []
    var automationContextSource: String = ""
    var automationRunID: String = ""
    var automationRunState: String = ""
    var automationAttempt: Int? = nil
    var automationRetryAfterSeconds: Int? = nil
    var automationRecoverySelection: String = ""
    var automationRecoveryReason: String = ""
    var automationRecoveryDecision: String = ""
    var automationRecoveryHoldReason: String = ""
    var automationRecoveryRetryAfterRemainingSeconds: Int? = nil
    var automationCurrentStepPresent: Bool = false
    var automationCurrentStepID: String = ""
    var automationCurrentStepTitle: String = ""
    var automationCurrentStepState: String = ""
    var automationCurrentStepSummary: String = ""
    var automationVerificationPresent: Bool = false
    var automationVerificationRequired: Bool? = nil
    var automationVerificationExecuted: Bool? = nil
    var automationVerificationCommandCount: Int? = nil
    var automationVerificationPassedCommandCount: Int? = nil
    var automationVerificationHoldReason: String = ""
    var automationVerificationContract: XTAutomationVerificationContract? = nil
    var automationBlockerPresent: Bool = false
    var automationBlockerCode: String = ""
    var automationBlockerSummary: String = ""
    var automationBlockerStage: String = ""
    var automationRetryReasonPresent: Bool = false
    var automationRetryReasonCode: String = ""
    var automationRetryReasonSummary: String = ""
    var automationRetryReasonStrategy: String = ""
    var automationRetryVerificationContract: XTAutomationVerificationContract? = nil

    var id: String {
        [
            projectId,
            role,
            stage,
            String(Int((createdAt * 1000).rounded()))
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ":")
    }

    func doctorDetailLines(includeProject: Bool) -> [String] {
        var lines: [String] = []
        if includeProject {
            lines.append("project_context_project=\(projectDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? projectId : projectDisplayName)")
        }
        let normalizedMemorySource = memoryV1Source.isEmpty ? "unknown" : memoryV1Source
        let normalizedRecentDialogueSource = recentProjectDialogueSource.isEmpty ? "unknown" : recentProjectDialogueSource
        lines.append("project_context_diagnostics_source=latest_coder_usage")
        if !role.isEmpty {
            lines.append("project_context_last_role=\(role)")
        }
        if !stage.isEmpty {
            lines.append("project_context_last_stage=\(stage)")
        }
        if !roleAwareMemoryMode.isEmpty {
            lines.append("role_aware_memory_mode=\(roleAwareMemoryMode)")
        }
        if !projectMemoryResolutionTrigger.isEmpty {
            lines.append("project_memory_resolution_trigger=\(projectMemoryResolutionTrigger)")
        }
        lines.append("project_memory_v1_source=\(normalizedMemorySource)")
        lines.append("project_memory_v1_source_label=\(XTMemorySourceTruthPresentation.label(normalizedMemorySource))")
        lines.append("project_memory_v1_source_class=\(XTMemorySourceTruthPresentation.sourceClass(normalizedMemorySource))")
        if !memoryV1Freshness.isEmpty {
            lines.append("memory_v1_freshness=\(memoryV1Freshness)")
        }
        if let memoryV1CacheHit {
            lines.append("memory_v1_cache_hit=\(memoryV1CacheHit)")
        }
        if !remoteSnapshotCacheScope.isEmpty {
            lines.append("memory_v1_remote_snapshot_cache_scope=\(remoteSnapshotCacheScope)")
        }
        if let remoteSnapshotCachedAtMs {
            lines.append("memory_v1_remote_snapshot_cached_at_ms=\(remoteSnapshotCachedAtMs)")
        }
        if let remoteSnapshotAgeMs {
            lines.append("memory_v1_remote_snapshot_age_ms=\(remoteSnapshotAgeMs)")
        }
        if let remoteSnapshotTTLRemainingMs {
            lines.append("memory_v1_remote_snapshot_ttl_remaining_ms=\(remoteSnapshotTTLRemainingMs)")
        }
        if !remoteSnapshotCachePosture.isEmpty {
            lines.append("memory_v1_remote_snapshot_cache_posture=\(remoteSnapshotCachePosture)")
        }
        if !remoteSnapshotInvalidationReason.isEmpty {
            lines.append("memory_v1_remote_snapshot_invalidation_reason=\(remoteSnapshotInvalidationReason)")
        }
        if !configuredRecentProjectDialogueProfile.isEmpty {
            lines.append("configured_recent_project_dialogue_profile=\(configuredRecentProjectDialogueProfile)")
        }
        if !recommendedRecentProjectDialogueProfile.isEmpty {
            lines.append("recommended_recent_project_dialogue_profile=\(recommendedRecentProjectDialogueProfile)")
        }
        if !effectiveRecentProjectDialogueProfile.isEmpty {
            lines.append("effective_recent_project_dialogue_profile=\(effectiveRecentProjectDialogueProfile)")
        }
        lines.append("recent_project_dialogue_profile=\(recentProjectDialogueProfile)")
        lines.append("recent_project_dialogue_selected_pairs=\(recentProjectDialogueSelectedPairs)")
        lines.append("recent_project_dialogue_floor_pairs=\(recentProjectDialogueFloorPairs)")
        lines.append("recent_project_dialogue_floor_satisfied=\(recentProjectDialogueFloorSatisfied)")
        lines.append("recent_project_dialogue_source=\(normalizedRecentDialogueSource)")
        lines.append("recent_project_dialogue_source_label=\(XTMemorySourceTruthPresentation.label(normalizedRecentDialogueSource))")
        lines.append("recent_project_dialogue_source_class=\(XTMemorySourceTruthPresentation.sourceClass(normalizedRecentDialogueSource))")
        lines.append("recent_project_dialogue_low_signal_dropped=\(recentProjectDialogueLowSignalDropped)")
        if !configuredProjectContextDepth.isEmpty {
            lines.append("configured_project_context_depth=\(configuredProjectContextDepth)")
        }
        if !recommendedProjectContextDepth.isEmpty {
            lines.append("recommended_project_context_depth=\(recommendedProjectContextDepth)")
        }
        if !effectiveProjectContextDepth.isEmpty {
            lines.append("effective_project_context_depth=\(effectiveProjectContextDepth)")
        }
        lines.append("project_context_depth=\(projectContextDepth)")
        lines.append("effective_project_serving_profile=\(effectiveProjectServingProfile)")
        if !aTierMemoryCeiling.isEmpty {
            lines.append("a_tier_memory_ceiling=\(aTierMemoryCeiling)")
            lines.append("project_memory_ceiling_hit=\(projectMemoryCeilingHit)")
        }
        lines.append("workflow_present=\(workflowPresent)")
        lines.append("execution_evidence_present=\(executionEvidencePresent)")
        lines.append("review_guidance_present=\(reviewGuidancePresent)")
        lines.append("cross_link_hints_selected=\(crossLinkHintsSelected)")
        if !personalMemoryExcludedReason.isEmpty {
            lines.append("personal_memory_excluded_reason=\(personalMemoryExcludedReason)")
        }
        if let projectMemoryPolicy {
            lines.append("project_memory_policy_schema_version=\(projectMemoryPolicy.schemaVersion)")
            if let json = xtProjectMemoryCompactJSONString(projectMemoryPolicy) {
                lines.append("project_memory_policy_json=\(json)")
            }
            if let auditRef = projectMemoryPolicy.auditRef,
               !auditRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("project_memory_policy_audit_ref=\(auditRef)")
            }
        }
        if let policyMemoryAssemblyResolution {
            lines.append("project_memory_policy_resolution_schema_version=\(policyMemoryAssemblyResolution.schemaVersion)")
            if let json = xtProjectMemoryCompactJSONString(policyMemoryAssemblyResolution) {
                lines.append("project_memory_policy_resolution_json=\(json)")
            }
        }
        if let memoryAssemblyResolution {
            lines.append("project_memory_resolution_schema_version=\(memoryAssemblyResolution.schemaVersion)")
            if let json = xtProjectMemoryCompactJSONString(memoryAssemblyResolution) {
                lines.append("project_memory_assembly_resolution_json=\(json)")
            }
            if !memoryAssemblyResolution.selectedPlanes.isEmpty {
                lines.append(
                    "project_memory_selected_planes=\(memoryAssemblyResolution.selectedPlanes.joined(separator: ","))"
                )
            }
            if !memoryAssemblyResolution.selectedSlots.isEmpty {
                lines.append(
                    "project_memory_selected_slots=\(memoryAssemblyResolution.selectedSlots.joined(separator: ","))"
                )
            }
            if !memoryAssemblyResolution.selectedServingObjects.isEmpty {
                lines.append(
                    "project_memory_selected_serving_objects=\(memoryAssemblyResolution.selectedServingObjects.joined(separator: ","))"
                )
            }
            if !memoryAssemblyResolution.excludedBlocks.isEmpty {
                lines.append(
                    "project_memory_excluded_blocks=\(memoryAssemblyResolution.excludedBlocks.joined(separator: ","))"
                )
            }
            if let budgetSummary = memoryAssemblyResolution.budgetSummary,
               !budgetSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("project_memory_budget_summary=\(budgetSummary)")
            }
            if let auditRef = memoryAssemblyResolution.auditRef,
               !auditRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("project_memory_resolution_audit_ref=\(auditRef)")
            }
        }
        if let hubMemoryPromptProjection {
            lines += hubMemoryPromptProjection.doctorDetailLines()
        }
        if !memoryAssemblyIssueCodes.isEmpty {
            lines.append("project_memory_issue_codes=\(memoryAssemblyIssueCodes.joined(separator: ","))")
        }
        if !memoryResolutionProjectionDriftDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(
                "project_memory_issue_memory_resolution_projection_drift=\(memoryResolutionProjectionDriftDetail)"
            )
        }
        lines.append("project_memory_heartbeat_digest_present=\(heartbeatDigestWorkingSetPresent)")
        if !heartbeatDigestVisibility.isEmpty {
            lines.append("project_memory_heartbeat_digest_visibility=\(heartbeatDigestVisibility)")
        }
        if !heartbeatDigestReasonCodes.isEmpty {
            lines.append(
                "project_memory_heartbeat_digest_reason_codes=\(heartbeatDigestReasonCodes.joined(separator: ","))"
            )
        }
        lines.append("project_memory_automation_current_step_present=\(automationCurrentStepPresent)")
        lines.append("project_memory_automation_verification_present=\(automationVerificationPresent)")
        lines.append("project_memory_automation_blocker_present=\(automationBlockerPresent)")
        lines.append("project_memory_automation_retry_reason_present=\(automationRetryReasonPresent)")
        if !automationContextSource.isEmpty {
            lines.append("project_memory_automation_context_source=\(automationContextSource)")
        }
        if !automationRunID.isEmpty {
            lines.append("project_memory_automation_run_id=\(automationRunID)")
        }
        if !automationRunState.isEmpty {
            lines.append("project_memory_automation_run_state=\(automationRunState)")
        }
        if let automationAttempt {
            lines.append("project_memory_automation_attempt=\(automationAttempt)")
        }
        if let automationRetryAfterSeconds {
            lines.append("project_memory_automation_retry_after_seconds=\(automationRetryAfterSeconds)")
        }
        if !automationRecoverySelection.isEmpty {
            lines.append("project_memory_automation_recovery_selection=\(automationRecoverySelection)")
        }
        if !automationRecoveryReason.isEmpty {
            lines.append("project_memory_automation_recovery_reason=\(automationRecoveryReason)")
        }
        if !automationRecoveryDecision.isEmpty {
            lines.append("project_memory_automation_recovery_decision=\(automationRecoveryDecision)")
        }
        if !automationRecoveryHoldReason.isEmpty {
            lines.append("project_memory_automation_recovery_hold_reason=\(automationRecoveryHoldReason)")
        }
        if let automationRecoveryRetryAfterRemainingSeconds {
            lines.append(
                "project_memory_automation_recovery_retry_after_remaining_seconds=\(automationRecoveryRetryAfterRemainingSeconds)"
            )
        }
        if automationCurrentStepPresent {
            if !automationCurrentStepID.isEmpty {
                lines.append("project_memory_automation_current_step_id=\(automationCurrentStepID)")
            }
            if !automationCurrentStepTitle.isEmpty {
                lines.append("project_memory_automation_current_step_title=\(automationCurrentStepTitle)")
            }
            if !automationCurrentStepState.isEmpty {
                lines.append("project_memory_automation_current_step_state=\(automationCurrentStepState)")
            }
            if !automationCurrentStepSummary.isEmpty {
                lines.append("project_memory_automation_current_step_summary=\(automationCurrentStepSummary)")
            }
        }
        if automationVerificationPresent {
            if let automationVerificationRequired {
                lines.append("project_memory_automation_verification_required=\(automationVerificationRequired)")
            }
            if let automationVerificationExecuted {
                lines.append("project_memory_automation_verification_executed=\(automationVerificationExecuted)")
            }
            if let automationVerificationCommandCount {
                lines.append(
                    "project_memory_automation_verification_command_count=\(automationVerificationCommandCount)"
                )
            }
            if let automationVerificationPassedCommandCount {
                lines.append(
                    "project_memory_automation_verification_passed_command_count=\(automationVerificationPassedCommandCount)"
                )
            }
            if !automationVerificationHoldReason.isEmpty {
                lines.append(
                    "project_memory_automation_verification_hold_reason=\(automationVerificationHoldReason)"
                )
            }
        }
        if let automationVerificationContract,
           let json = xtProjectMemoryCompactJSONString(automationVerificationContract) {
            lines.append("project_memory_automation_verification_contract_json=\(json)")
        }
        if automationBlockerPresent {
            if !automationBlockerCode.isEmpty {
                lines.append("project_memory_automation_blocker_code=\(automationBlockerCode)")
            }
            if !automationBlockerSummary.isEmpty {
                lines.append("project_memory_automation_blocker_summary=\(automationBlockerSummary)")
            }
            if !automationBlockerStage.isEmpty {
                lines.append("project_memory_automation_blocker_stage=\(automationBlockerStage)")
            }
        }
        if automationRetryReasonPresent {
            if !automationRetryReasonCode.isEmpty {
                lines.append("project_memory_automation_retry_reason_code=\(automationRetryReasonCode)")
            }
            if !automationRetryReasonSummary.isEmpty {
                lines.append("project_memory_automation_retry_reason_summary=\(automationRetryReasonSummary)")
            }
            if !automationRetryReasonStrategy.isEmpty {
                lines.append(
                    "project_memory_automation_retry_reason_strategy=\(automationRetryReasonStrategy)"
                )
            }
        }
        if let automationRetryVerificationContract,
           let json = xtProjectMemoryCompactJSONString(automationRetryVerificationContract) {
            lines.append("project_memory_automation_retry_verification_contract_json=\(json)")
        }
        return lines
    }
}

struct AXProjectContextAssemblyDiagnosticsSummary: Equatable, Sendable {
    static let empty = AXProjectContextAssemblyDiagnosticsSummary(
        latestEvent: nil,
        detailLines: []
    )

    var latestEvent: AXProjectContextAssemblyDiagnosticEvent?
    var detailLines: [String]
}

extension AXProjectContextAssemblyDiagnosticsSummary {
    var presentation: AXProjectContextAssemblyPresentation? {
        AXProjectContextAssemblyPresentation.from(summary: self)
    }

    var compactSummary: AXProjectContextAssemblyCompactSummary? {
        presentation?.compactSummary
    }

    var projectMemoryPolicy: XTProjectMemoryPolicySnapshot? {
        latestEvent?.projectMemoryPolicy ?? xtProjectMemoryDecodeJSONString(
            XTProjectMemoryPolicySnapshot.self,
            jsonString: xtProjectMemoryDetailValue(
                "project_memory_policy_json",
                from: detailLines
            )
        )
    }

    var policyMemoryAssemblyResolution: XTMemoryAssemblyResolution? {
        latestEvent?.policyMemoryAssemblyResolution ?? xtProjectMemoryDecodeJSONString(
            XTMemoryAssemblyResolution.self,
            jsonString: xtProjectMemoryDetailValue(
                "project_memory_policy_resolution_json",
                from: detailLines
            )
        )
    }

    var memoryAssemblyResolution: XTMemoryAssemblyResolution? {
        latestEvent?.memoryAssemblyResolution ?? xtProjectMemoryDecodeJSONString(
            XTMemoryAssemblyResolution.self,
            jsonString: xtProjectMemoryDetailValue(
                "project_memory_assembly_resolution_json",
                from: detailLines
            )
        )
    }

    var hubMemoryPromptProjection: HubMemoryPromptProjectionSnapshot? {
        latestEvent?.hubMemoryPromptProjection
            ?? HubMemoryPromptProjectionSnapshot.fromDoctorDetailLines(detailLines)
    }

    var memoryAssemblyReadiness: XTProjectMemoryAssemblyReadiness {
        XTProjectMemoryAssemblyDiagnostics.evaluate(summary: self)
    }
}

enum XTProjectMemoryAssemblyIssueSeverity: String, Codable, Sendable {
    case warning
    case blocking
}

struct XTProjectMemoryAssemblyIssue: Codable, Equatable, Identifiable, Sendable {
    var id: String { code }
    var code: String
    var severity: XTProjectMemoryAssemblyIssueSeverity
    var summary: String
    var detail: String
}

struct XTProjectMemoryAssemblyReadiness: Codable, Equatable, Sendable {
    var ready: Bool
    var statusLine: String
    var issues: [XTProjectMemoryAssemblyIssue]

    var issueCodes: [String] {
        issues.map(\.code)
    }

    var topIssue: XTProjectMemoryAssemblyIssue? {
        issues.first
    }

    func detailLines(prefix: String = "project_memory_readiness") -> [String] {
        var lines = [
            "\(prefix)_ready=\(ready)",
            "\(prefix)_status_line=\(statusLine)"
        ]
        if !issueCodes.isEmpty {
            lines.append("\(prefix)_issue_codes=\(issueCodes.joined(separator: ","))")
        }
        if let topIssue {
            lines.append("\(prefix)_top_issue_code=\(topIssue.code)")
            lines.append("\(prefix)_top_issue_summary=\(topIssue.summary)")
            lines.append("\(prefix)_top_issue_detail=\(topIssue.detail)")
        }
        return lines
    }

    static func from(
        detailLines: [String],
        prefix: String = "project_memory_readiness"
    ) -> XTProjectMemoryAssemblyReadiness? {
        let ready = boolValue(
            xtProjectMemoryDetailValue("\(prefix)_ready", from: detailLines)
        )
        let statusLine = xtProjectMemoryDetailValue("\(prefix)_status_line", from: detailLines)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let issueCodes = csvTokens(
            xtProjectMemoryDetailValue("\(prefix)_issue_codes", from: detailLines)
        )
        let topIssueCode = xtProjectMemoryDetailValue("\(prefix)_top_issue_code", from: detailLines)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let topIssueSummary = xtProjectMemoryDetailValue("\(prefix)_top_issue_summary", from: detailLines)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let topIssueDetail = xtProjectMemoryDetailValue("\(prefix)_top_issue_detail", from: detailLines)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard ready != nil
                || !statusLine.isEmpty
                || !issueCodes.isEmpty
                || !topIssueCode.isEmpty
                || !topIssueSummary.isEmpty
                || !topIssueDetail.isEmpty else {
            return nil
        }

        var issues: [XTProjectMemoryAssemblyIssue] = []
        if !topIssueCode.isEmpty || !topIssueSummary.isEmpty || !topIssueDetail.isEmpty {
            let code = !topIssueCode.isEmpty
                ? topIssueCode
                : (issueCodes.first ?? "project_memory_attention_required")
            issues.append(
                XTProjectMemoryAssemblyIssue(
                    code: code,
                    severity: .warning,
                    summary: topIssueSummary.isEmpty
                        ? XTProjectMemoryAssemblyDiagnostics.summary(for: code)
                        : topIssueSummary,
                    detail: topIssueDetail.isEmpty
                        ? XTProjectMemoryAssemblyDiagnostics.detailFallback(for: code)
                        : topIssueDetail
                )
            )
        }

        for code in issueCodes where !issues.contains(where: { $0.code == code }) {
            issues.append(
                XTProjectMemoryAssemblyIssue(
                    code: code,
                    severity: .warning,
                    summary: XTProjectMemoryAssemblyDiagnostics.summary(for: code),
                    detail: XTProjectMemoryAssemblyDiagnostics.detailFallback(for: code)
                )
            )
        }

        return XTProjectMemoryAssemblyReadiness(
            ready: ready ?? issues.isEmpty,
            statusLine: statusLine.isEmpty
                ? (issues.isEmpty ? "ready" : "attention:\(issues.map(\.code).joined(separator: ","))")
                : statusLine,
            issues: issues
        )
    }

    private static func boolValue(_ raw: String?) -> Bool? {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }

    private static func csvTokens(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        return raw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

enum XTProjectMemoryAssemblyDiagnostics {
    static func evaluate(
        summary: AXProjectContextAssemblyDiagnosticsSummary
    ) -> XTProjectMemoryAssemblyReadiness {
        guard let latestEvent = summary.latestEvent else {
            let issue = XTProjectMemoryAssemblyIssue(
                code: "project_memory_usage_missing",
                severity: .warning,
                summary: "尚未捕获 Project AI 的最近一次 memory 装配真相",
                detail: "Doctor 当前只能看到配置基线，还没有 recent coder usage 来证明 Project AI 最近一轮真正吃到了哪些 memory objects / planes。"
            )
            return XTProjectMemoryAssemblyReadiness(
                ready: false,
                statusLine: "attention:\(issue.code)",
                issues: [issue]
            )
        }

        var issues: [XTProjectMemoryAssemblyIssue] = []

        if !latestEvent.recentProjectDialogueFloorSatisfied {
            issues.append(
                XTProjectMemoryAssemblyIssue(
                    code: "project_recent_dialogue_floor_not_met",
                    severity: .warning,
                    summary: "Project recent dialogue continuity 没达到最低底线",
                    detail: """
selected_pairs=\(latestEvent.recentProjectDialogueSelectedPairs) floor_pairs=\(latestEvent.recentProjectDialogueFloorPairs) profile=\(latestEvent.recentProjectDialogueProfile) source=\(latestEvent.recentProjectDialogueSource.isEmpty ? "unknown" : latestEvent.recentProjectDialogueSource) low_signal_dropped=\(latestEvent.recentProjectDialogueLowSignalDropped)
"""
                )
            )
        }

        if latestEvent.memoryAssemblyResolution == nil {
            issues.append(
                XTProjectMemoryAssemblyIssue(
                    code: "project_memory_resolution_missing",
                    severity: .warning,
                    summary: "Project memory assembly resolution 缺失",
                    detail: "latest coder usage 没有留下 machine-readable memory_assembly_resolution，Doctor 无法确认本轮 Project AI 实际拿到了哪些 memory objects / planes。"
                )
            )
        }

        if latestEvent.memoryAssemblyIssueCodes.contains("memory_resolution_projection_drift") {
            issues.append(
                XTProjectMemoryAssemblyIssue(
                    code: "memory_resolution_projection_drift",
                    severity: .warning,
                    summary: Self.summary(for: "memory_resolution_projection_drift"),
                    detail: latestEvent.memoryResolutionProjectionDriftDetail
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                        ? detailFallback(for: "memory_resolution_projection_drift")
                        : latestEvent.memoryResolutionProjectionDriftDetail
                )
            )
        }

        return XTProjectMemoryAssemblyReadiness(
            ready: issues.isEmpty,
            statusLine: issues.isEmpty
                ? "ready"
                : "attention:\(issues.map(\.code).joined(separator: ","))",
            issues: issues
        )
    }

    static func summary(for code: String) -> String {
        switch code {
        case "project_memory_usage_missing":
            return "尚未捕获 Project AI 的最近一次 memory 装配真相"
        case "project_recent_dialogue_floor_not_met":
            return "Project recent dialogue continuity 没达到最低底线"
        case "project_memory_resolution_missing":
            return "Project memory assembly resolution 缺失"
        case "memory_resolution_projection_drift":
            return "Project memory explainability 与实际 served prompt 不一致"
        default:
            return XTMemorySourceTruthPresentation.humanizeToken(code)
        }
    }

    static func detailFallback(for code: String) -> String {
        switch code {
        case "project_memory_usage_missing":
            return "Doctor 当前只有配置基线，没有 recent coder usage 可用于验证真实 memory 装配。"
        case "project_recent_dialogue_floor_not_met":
            return "Project AI 最近原始对话窗口没有达到 continuity floor，连续推进可能出现短期上下文掉失。"
        case "project_memory_resolution_missing":
            return "Project AI 最新 usage 记录没有提供 machine-readable resolution，Doctor 无法确认最终 prompt 实际带入了哪些 project-memory objects / planes。"
        case "memory_resolution_projection_drift":
            return "policy-level resolution 和最终 served MEMORY_V1 在 selected_planes / selected_serving_objects / excluded_blocks 上出现了漂移。"
        default:
            return XTMemorySourceTruthPresentation.humanizeToken(code)
        }
    }
}

enum AXProjectContextAssemblyDiagnosticsStore {
    static func latestEvent(for ctx: AXProjectContext) -> AXProjectContextAssemblyDiagnosticEvent? {
        recentEvents(for: ctx, limit: 1).first
    }

    static func doctorSummary(
        for ctx: AXProjectContext?,
        config: AXProjectConfig? = nil
    ) -> AXProjectContextAssemblyDiagnosticsSummary {
        guard let ctx else { return .empty }

        if let latest = latestEvent(for: ctx) {
            return AXProjectContextAssemblyDiagnosticsSummary(
                latestEvent: latest,
                detailLines: latest.doctorDetailLines(includeProject: true)
            )
        }

        let projectName = resolvedProjectDisplayName(for: ctx)
        let resolvedConfig = config ?? .default(forProjectRoot: ctx.root)
        let policy = XTRoleAwareMemoryPolicyResolver.resolveProject(
            config: resolvedConfig,
            governance: resolvedGovernanceState(for: ctx, config: resolvedConfig),
            userText: "",
            shouldExpandRecent: false,
            executionEvidencePresent: false,
            reviewGuidancePresent: false
        )
        return AXProjectContextAssemblyDiagnosticsSummary(
            latestEvent: nil,
            detailLines: [
                "project_context_diagnostics_source=config_only",
                "project_context_project=\(projectName)",
                "role_aware_memory_mode=\(policy.resolution.role.rawValue)",
                "project_memory_resolution_trigger=config_only_baseline",
                "configured_recent_project_dialogue_profile=\(policy.configuredRecentProjectDialogueProfile.rawValue)",
                "recommended_recent_project_dialogue_profile=\(policy.recommendedRecentProjectDialogueProfile.rawValue)",
                "effective_recent_project_dialogue_profile=\(policy.effectiveRecentProjectDialogueProfile.rawValue)",
                "configured_project_context_depth=\(policy.configuredProjectContextDepth.rawValue)",
                "recommended_project_context_depth=\(policy.recommendedProjectContextDepth.rawValue)",
                "effective_project_context_depth=\(policy.effectiveProjectContextDepth.rawValue)",
                "a_tier_memory_ceiling=\(policy.aTierMemoryCeiling.rawValue)",
                "project_memory_ceiling_hit=\(policy.ceilingHit)",
                "project_memory_policy_schema_version=\(policy.snapshot.schemaVersion)",
                "project_memory_policy_json=\(xtProjectMemoryCompactJSONString(policy.snapshot) ?? "{}")",
                "project_memory_policy_resolution_schema_version=\(policy.resolution.schemaVersion)",
                "project_memory_policy_resolution_json=\(xtProjectMemoryCompactJSONString(policy.resolution) ?? "{}")",
                "project_memory_resolution_schema_version=\(policy.resolution.schemaVersion)",
                "project_memory_assembly_resolution_json=\(xtProjectMemoryCompactJSONString(policy.resolution) ?? "{}")",
                "project_memory_selected_planes=\(policy.resolution.selectedPlanes.joined(separator: ","))",
                "project_memory_selected_slots=\(policy.resolution.selectedSlots.joined(separator: ","))",
                "project_memory_selected_serving_objects=\(policy.resolution.selectedServingObjects.joined(separator: ","))",
                "project_memory_excluded_blocks=\(policy.resolution.excludedBlocks.joined(separator: ","))",
                "project_context_diagnostics=no_recent_coder_usage"
            ]
        )
    }

    private static func recentEvents(
        for ctx: AXProjectContext,
        limit: Int
    ) -> [AXProjectContextAssemblyDiagnosticEvent] {
        guard FileManager.default.fileExists(atPath: ctx.usageLogURL.path),
              let data = try? Data(contentsOf: ctx.usageLogURL),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }

        return Array(
            text
                .split(separator: "\n", omittingEmptySubsequences: true)
                .compactMap { line in
                    guard let data = line.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        return nil
                    }
                    return event(from: obj, ctx: ctx)
                }
                .sorted { lhs, rhs in
                    if lhs.createdAt != rhs.createdAt {
                        return lhs.createdAt > rhs.createdAt
                    }
                    return lhs.id > rhs.id
                }
                .prefix(limit)
        )
    }

    private static func event(
        from obj: [String: Any],
        ctx: AXProjectContext
    ) -> AXProjectContextAssemblyDiagnosticEvent? {
        guard text(obj["type"]) == "ai_usage" else { return nil }

        let recentDialogueProfile = text(obj["recent_project_dialogue_profile"])
        let projectContextDepth = text(obj["project_context_depth"])
        guard !recentDialogueProfile.isEmpty || !projectContextDepth.isEmpty else { return nil }

        let selectedPairs = int(obj["recent_project_dialogue_selected_pairs"])
        let floorPairs = max(AXProjectRecentDialogueProfile.hardFloorPairs, int(obj["recent_project_dialogue_floor_pairs"]))
        let floorSatisfied = bool(obj["recent_project_dialogue_floor_satisfied"])
            ?? (selectedPairs >= floorPairs)
        return AXProjectContextAssemblyDiagnosticEvent(
            schemaVersion: AXProjectContextAssemblyDiagnosticEvent.currentSchemaVersion,
            createdAt: number(obj["created_at"]),
            projectId: AXProjectRegistryStore.projectId(forRoot: ctx.root),
            projectDisplayName: resolvedProjectDisplayName(for: ctx),
            role: text(obj["role"]),
            stage: text(obj["stage"]),
            roleAwareMemoryMode: text(obj["role_aware_memory_mode"]),
            projectMemoryResolutionTrigger: text(obj["project_memory_resolution_trigger"]),
            memoryV1Source: text(obj["memory_v1_source"]),
            memoryV1Freshness: text(obj["memory_v1_freshness"]),
            memoryV1CacheHit: bool(obj["memory_v1_cache_hit"]),
            remoteSnapshotCacheScope: text(obj["memory_v1_remote_snapshot_cache_scope"]),
            remoteSnapshotCachedAtMs: int64(obj["memory_v1_remote_snapshot_cached_at_ms"]),
            remoteSnapshotAgeMs: optionalInt(obj["memory_v1_remote_snapshot_age_ms"]),
            remoteSnapshotTTLRemainingMs: optionalInt(obj["memory_v1_remote_snapshot_ttl_remaining_ms"]),
            remoteSnapshotCachePosture: text(obj["memory_v1_remote_snapshot_cache_posture"]),
            remoteSnapshotInvalidationReason: text(obj["memory_v1_remote_snapshot_invalidation_reason"]),
            configuredRecentProjectDialogueProfile: fallbackText(
                obj["configured_recent_project_dialogue_profile"],
                fallback: recentDialogueProfile
            ),
            recommendedRecentProjectDialogueProfile: fallbackText(
                obj["recommended_recent_project_dialogue_profile"],
                fallback: recentDialogueProfile
            ),
            effectiveRecentProjectDialogueProfile: fallbackText(
                obj["effective_recent_project_dialogue_profile"],
                fallback: recentDialogueProfile
            ),
            recentProjectDialogueProfile: recentDialogueProfile,
            recentProjectDialogueSelectedPairs: selectedPairs,
            recentProjectDialogueFloorPairs: floorPairs,
            recentProjectDialogueFloorSatisfied: floorSatisfied,
            recentProjectDialogueSource: text(obj["recent_project_dialogue_source"]),
            recentProjectDialogueLowSignalDropped: int(obj["recent_project_dialogue_low_signal_dropped"]),
            configuredProjectContextDepth: fallbackText(
                obj["configured_project_context_depth"],
                fallback: projectContextDepth
            ),
            recommendedProjectContextDepth: fallbackText(
                obj["recommended_project_context_depth"],
                fallback: projectContextDepth
            ),
            effectiveProjectContextDepth: fallbackText(
                obj["effective_project_context_depth"],
                fallback: projectContextDepth
            ),
            projectContextDepth: projectContextDepth,
            effectiveProjectServingProfile: text(obj["effective_project_serving_profile"]),
            aTierMemoryCeiling: text(obj["a_tier_memory_ceiling"]),
            projectMemoryCeilingHit: bool(obj["project_memory_ceiling_hit"]) ?? false,
            workflowPresent: bool(obj["workflow_present"]) ?? false,
            executionEvidencePresent: bool(obj["execution_evidence_present"]) ?? false,
            reviewGuidancePresent: bool(obj["review_guidance_present"]) ?? false,
            crossLinkHintsSelected: int(obj["cross_link_hints_selected"]),
            personalMemoryExcludedReason: text(obj["personal_memory_excluded_reason"]),
            projectMemoryPolicy: xtProjectMemoryDecodeJSONObject(obj["project_memory_policy"]),
            policyMemoryAssemblyResolution: xtProjectMemoryDecodeJSONObject(
                obj["project_memory_policy_resolution"]
            ),
            memoryAssemblyResolution: xtProjectMemoryDecodeJSONObject(obj["memory_assembly_resolution"]),
            hubMemoryPromptProjection: xtProjectMemoryDecodeJSONObject(obj["hub_memory_prompt_projection"]),
            memoryAssemblyIssueCodes: stringArray(obj["project_memory_issue_codes"]),
            memoryResolutionProjectionDriftDetail: text(
                obj["project_memory_issue_memory_resolution_projection_drift"]
            ),
            heartbeatDigestWorkingSetPresent: bool(obj["project_memory_heartbeat_digest_present"]) ?? false,
            heartbeatDigestVisibility: text(obj["project_memory_heartbeat_digest_visibility"]),
            heartbeatDigestReasonCodes: stringArray(obj["project_memory_heartbeat_digest_reason_codes"]),
            automationContextSource: text(obj["project_memory_automation_context_source"]),
            automationRunID: text(obj["project_memory_automation_run_id"]),
            automationRunState: text(obj["project_memory_automation_run_state"]),
            automationAttempt: optionalInt(obj["project_memory_automation_attempt"]),
            automationRetryAfterSeconds: optionalInt(obj["project_memory_automation_retry_after_seconds"]),
            automationRecoverySelection: text(obj["project_memory_automation_recovery_selection"]),
            automationRecoveryReason: text(obj["project_memory_automation_recovery_reason"]),
            automationRecoveryDecision: text(obj["project_memory_automation_recovery_decision"]),
            automationRecoveryHoldReason: text(obj["project_memory_automation_recovery_hold_reason"]),
            automationRecoveryRetryAfterRemainingSeconds: optionalInt(
                obj["project_memory_automation_recovery_retry_after_remaining_seconds"]
            ),
            automationCurrentStepPresent: bool(obj["project_memory_automation_current_step_present"]) ?? false,
            automationCurrentStepID: text(obj["project_memory_automation_current_step_id"]),
            automationCurrentStepTitle: text(obj["project_memory_automation_current_step_title"]),
            automationCurrentStepState: text(obj["project_memory_automation_current_step_state"]),
            automationCurrentStepSummary: text(obj["project_memory_automation_current_step_summary"]),
            automationVerificationPresent: bool(obj["project_memory_automation_verification_present"]) ?? false,
            automationVerificationRequired: bool(obj["project_memory_automation_verification_required"]),
            automationVerificationExecuted: bool(obj["project_memory_automation_verification_executed"]),
            automationVerificationCommandCount: optionalInt(
                obj["project_memory_automation_verification_command_count"]
            ),
            automationVerificationPassedCommandCount: optionalInt(
                obj["project_memory_automation_verification_passed_command_count"]
            ),
            automationVerificationHoldReason: text(
                obj["project_memory_automation_verification_hold_reason"]
            ),
            automationVerificationContract: xtProjectMemoryDecodeJSONObject(
                obj["project_memory_automation_verification_contract"]
            ),
            automationBlockerPresent: bool(obj["project_memory_automation_blocker_present"]) ?? false,
            automationBlockerCode: text(obj["project_memory_automation_blocker_code"]),
            automationBlockerSummary: text(obj["project_memory_automation_blocker_summary"]),
            automationBlockerStage: text(obj["project_memory_automation_blocker_stage"]),
            automationRetryReasonPresent: bool(obj["project_memory_automation_retry_reason_present"]) ?? false,
            automationRetryReasonCode: text(obj["project_memory_automation_retry_reason_code"]),
            automationRetryReasonSummary: text(obj["project_memory_automation_retry_reason_summary"]),
            automationRetryReasonStrategy: text(obj["project_memory_automation_retry_reason_strategy"]),
            automationRetryVerificationContract: xtProjectMemoryDecodeJSONObject(
                obj["project_memory_automation_retry_verification_contract"]
            )
        )
    }

    private static func resolvedGovernanceState(
        for ctx: AXProjectContext,
        config: AXProjectConfig
    ) -> AXProjectResolvedGovernanceState {
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

    private static func resolvedProjectDisplayName(for ctx: AXProjectContext) -> String {
        AXProjectRegistryStore.displayName(
            forRoot: ctx.root,
            preferredDisplayName: ctx.projectName()
        )
    }

    private static func text(_ raw: Any?) -> String {
        (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func fallbackText(_ raw: Any?, fallback: String) -> String {
        let direct = text(raw)
        return direct.isEmpty ? fallback : direct
    }

    private static func number(_ raw: Any?) -> Double {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? Int64 { return Double(value) }
        if let value = raw as? NSNumber { return value.doubleValue }
        if let value = raw as? String, let parsed = Double(value) { return parsed }
        return 0
    }

    private static func int(_ raw: Any?) -> Int {
        if let value = raw as? Int { return value }
        if let value = raw as? Int64 { return Int(value) }
        if let value = raw as? Double { return Int(value) }
        if let value = raw as? NSNumber { return value.intValue }
        if let value = raw as? String, let parsed = Int(value) { return parsed }
        return 0
    }

    private static func optionalInt(_ raw: Any?) -> Int? {
        guard raw != nil else { return nil }
        if let value = raw as? String,
           value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        return int(raw)
    }

    private static func int64(_ raw: Any?) -> Int64? {
        if let value = raw as? Int64 { return value }
        if let value = raw as? Int { return Int64(value) }
        if let value = raw as? Double { return Int64(value.rounded()) }
        if let value = raw as? NSNumber { return value.int64Value }
        if let value = raw as? String, let parsed = Int64(value) { return parsed }
        return nil
    }

    private static func bool(_ raw: Any?) -> Bool? {
        if let value = raw as? Bool { return value }
        if let value = raw as? NSNumber { return value.boolValue }
        if let value = raw as? String {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes":
                return true
            case "0", "false", "no":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private static func stringArray(_ raw: Any?) -> [String] {
        if let values = raw as? [String] {
            return values
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        if let values = raw as? [Any] {
            return values.compactMap { value in
                if let string = value as? String {
                    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
                return nil
            }
        }
        if let text = raw as? String {
            return text
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return []
    }
}
