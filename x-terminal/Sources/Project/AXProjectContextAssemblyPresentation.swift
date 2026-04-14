import Foundation

enum AXProjectContextAssemblyPresentationSourceKind: String, Codable, Equatable, Sendable {
    case latestCoderUsage = "latest_coder_usage"
    case configOnly = "config_only"
    case unknown
}

struct AXProjectContextAssemblyCompactSummary: Equatable, Sendable {
    var headlineText: String
    var detailText: String?
    var helpText: String
}

struct AXProjectContextAssemblyPresentation: Codable, Equatable, Sendable {
    var sourceKind: AXProjectContextAssemblyPresentationSourceKind
    var projectLabel: String?
    var sourceBadge: String
    var statusLine: String
    var recentDialogueSource: String? = nil
    var recentDialogueSourceLabel: String? = nil
    var recentDialogueSourceClass: String? = nil
    var memorySource: String? = nil
    var memorySourceLabel: String? = nil
    var memorySourceClass: String? = nil
    var dialogueMetric: String
    var depthMetric: String
    var dialogueLine: String
    var depthLine: String
    var executionMetric: String? = nil
    var executionLine: String? = nil
    var coverageMetric: String?
    var coverageLine: String?
    var boundaryMetric: String?
    var boundaryLine: String?
    var planeLine: String? = nil
    var assemblyLine: String? = nil
    var omissionLine: String? = nil
    var budgetLine: String? = nil
    var userSourceBadge: String
    var userStatusLine: String
    var userDialogueMetric: String
    var userDepthMetric: String
    var userExecutionSummary: String? = nil
    var userCoverageSummary: String?
    var heartbeatDigestLine: String? = nil
    var userHeartbeatSummary: String? = nil
    var userBoundarySummary: String?
    var userPlaneSummary: String? = nil
    var userAssemblySummary: String? = nil
    var userOmissionSummary: String? = nil
    var userBudgetSummary: String? = nil
    var userDialogueLine: String
    var userDepthLine: String

    static func from(summary: AXProjectContextAssemblyDiagnosticsSummary) -> AXProjectContextAssemblyPresentation? {
        from(detailLines: summary.detailLines)
    }

    static func from(detailLines: [String]) -> AXProjectContextAssemblyPresentation? {
        let values = keyValueMap(detailLines)
        let sourceRaw = values["project_context_diagnostics_source"]?.lowercased() ?? ""
        let sourceKind = AXProjectContextAssemblyPresentationSourceKind(rawValue: sourceRaw) ?? .unknown

        let hasLatestUsage = !values["recent_project_dialogue_profile", default: ""].isEmpty
            || !values["project_context_depth", default: ""].isEmpty
        let hasConfigOnly = !values["configured_recent_project_dialogue_profile", default: ""].isEmpty
            || !values["configured_project_context_depth", default: ""].isEmpty
        guard sourceKind != .unknown || hasLatestUsage || hasConfigOnly else { return nil }

        let projectLabel = trimmed(values["project_context_project"])
        switch sourceKind {
        case .latestCoderUsage:
            return latestUsagePresentation(values: values, projectLabel: projectLabel)
        case .configOnly:
            return configOnlyPresentation(values: values, projectLabel: projectLabel)
        case .unknown:
            if hasLatestUsage {
                return latestUsagePresentation(values: values, projectLabel: projectLabel)
            }
            if hasConfigOnly {
                return configOnlyPresentation(values: values, projectLabel: projectLabel)
            }
            return nil
        }
    }

    private static func latestUsagePresentation(
        values: [String: String],
        projectLabel: String?
    ) -> AXProjectContextAssemblyPresentation {
        let configuredRecentProfile = recentDialogueProfile(
            values["configured_recent_project_dialogue_profile"],
            fallback: values["recent_project_dialogue_profile"]
        )
        let recommendedRecentProfile = recentDialogueProfile(
            values["recommended_recent_project_dialogue_profile"],
            fallback: values["recent_project_dialogue_profile"]
        )
        let recentProfile = recentDialogueProfile(
            values["effective_recent_project_dialogue_profile"],
            fallback: values["recent_project_dialogue_profile"]
        )
        let selectedPairs = int(values["recent_project_dialogue_selected_pairs"])
        let floorPairs = max(AXProjectRecentDialogueProfile.hardFloorPairs, int(values["recent_project_dialogue_floor_pairs"]))
        let floorSatisfied = bool(values["recent_project_dialogue_floor_satisfied"])
        let lowSignalDropped = int(values["recent_project_dialogue_low_signal_dropped"])
        let recentSource = trimmed(values["recent_project_dialogue_source"]) ?? "unknown"
        let recentSourceLabel = XTMemorySourceTruthPresentation.label(recentSource)
        let configuredDepthProfile = contextDepthProfile(
            values["configured_project_context_depth"],
            fallback: values["project_context_depth"]
        )
        let recommendedDepthProfile = contextDepthProfile(
            values["recommended_project_context_depth"],
            fallback: values["project_context_depth"]
        )
        let depthProfile = contextDepthProfile(
            values["effective_project_context_depth"],
            fallback: values["project_context_depth"]
        )
        let servingProfile = XTMemoryServingProfile.parse(values["effective_project_serving_profile"])
        let aTierMemoryCeiling = XTMemoryServingProfile.parse(values["a_tier_memory_ceiling"])
        let ceilingHit = bool(values["project_memory_ceiling_hit"])
        let resolutionTrigger = trimmed(values["project_memory_resolution_trigger"])
        let workflowPresent = bool(values["workflow_present"])
        let evidencePresent = bool(values["execution_evidence_present"])
        let guidancePresent = bool(values["review_guidance_present"])
        let crossLinks = int(values["cross_link_hints_selected"])
        let memorySource = trimmed(values["project_memory_v1_source"]) ?? "unknown"
        let memorySourceLabel = XTMemorySourceTruthPresentation.label(memorySource)
        let explainableMemorySourceLabel = XTMemorySourceTruthPresentation.explainableLabel(memorySource)
        let memoryFreshness = trimmed(values["memory_v1_freshness"])
        let memoryCacheHit = values["memory_v1_cache_hit"] == nil ? nil : bool(values["memory_v1_cache_hit"])
        let remoteSnapshotCacheScope = trimmed(values["memory_v1_remote_snapshot_cache_scope"])
        let remoteSnapshotAgeMs = optionalInt(values["memory_v1_remote_snapshot_age_ms"])
        let remoteSnapshotTTLRemainingMs = optionalInt(values["memory_v1_remote_snapshot_ttl_remaining_ms"])
        let boundaryReason = trimmed(values["personal_memory_excluded_reason"])
        let selectedPlanes = csvValues(values["project_memory_selected_planes"])
        let selectedServingObjects = csvValues(values["project_memory_selected_serving_objects"])
        let excludedBlocks = csvValues(values["project_memory_excluded_blocks"])
        let budgetSummary = trimmed(values["project_memory_budget_summary"])
        let heartbeatDigestPresent = bool(values["project_memory_heartbeat_digest_present"])
        let heartbeatDigestVisibility = trimmed(values["project_memory_heartbeat_digest_visibility"])
        let heartbeatDigestReasonCodes = csvValues(values["project_memory_heartbeat_digest_reason_codes"])
        let automationCurrentStepPresent = bool(values["project_memory_automation_current_step_present"])
        let automationCurrentStepTitle = trimmed(values["project_memory_automation_current_step_title"])
        let automationCurrentStepState = trimmed(values["project_memory_automation_current_step_state"])
        let automationCurrentStepSummary = trimmed(values["project_memory_automation_current_step_summary"])
        let automationRecoveryReason = trimmed(values["project_memory_automation_recovery_reason"])
        let automationRecoveryHoldReason = trimmed(values["project_memory_automation_recovery_hold_reason"])
        let automationRecoveryRetryAfterRemainingSeconds = optionalInt(
            values["project_memory_automation_recovery_retry_after_remaining_seconds"]
        )
        let automationVerificationPresent = bool(values["project_memory_automation_verification_present"])
        let automationVerificationRequired = values["project_memory_automation_verification_required"] == nil
            ? nil
            : bool(values["project_memory_automation_verification_required"])
        let automationVerificationExecuted = values["project_memory_automation_verification_executed"] == nil
            ? nil
            : bool(values["project_memory_automation_verification_executed"])
        let automationVerificationCommandCount = optionalInt(
            values["project_memory_automation_verification_command_count"]
        )
        let automationVerificationPassedCommandCount = optionalInt(
            values["project_memory_automation_verification_passed_command_count"]
        )
        let automationVerificationHoldReason = trimmed(
            values["project_memory_automation_verification_hold_reason"]
        )
        let automationBlockerPresent = bool(values["project_memory_automation_blocker_present"])
        let automationBlockerSummary = trimmed(values["project_memory_automation_blocker_summary"])
        let automationBlockerStage = trimmed(values["project_memory_automation_blocker_stage"])
        let automationRetryReasonPresent = bool(values["project_memory_automation_retry_reason_present"])
        let automationRetryReasonSummary = trimmed(values["project_memory_automation_retry_reason_summary"])
        let automationRetryReasonStrategy = trimmed(values["project_memory_automation_retry_reason_strategy"])
        let remoteSnapshotStatus = remoteSnapshotStatusSummary(
            memorySource: memorySource,
            freshness: memoryFreshness,
            cacheHit: memoryCacheHit,
            scope: remoteSnapshotCacheScope,
            ageMs: remoteSnapshotAgeMs,
            ttlRemainingMs: remoteSnapshotTTLRemainingMs
        )

        let dialogueMetric = [
            recentProfile.map { "\($0.displayName) · \($0.shortLabel)" } ?? fallbackDialogueProfile(values["recent_project_dialogue_profile"]),
            selectedPairs > 0 ? "selected \(selectedPairs)p" : "selected 0p"
        ]
        .joined(separator: " · ")

        let depthMetric = [
            depthProfile?.displayName ?? fallbackDepthProfile(values["project_context_depth"]),
            servingProfile?.rawValue ?? trimmed(values["effective_project_serving_profile"]) ?? "unknown",
            memorySourceLabel
        ]
        .joined(separator: " · ")

        let dialogueLine = [
            "Recent Project Dialogue：configured \(configuredRecentProfile.map { "\($0.displayName) · \($0.shortLabel)" } ?? fallbackDialogueProfile(values["configured_recent_project_dialogue_profile"]))",
            "recommended \(recommendedRecentProfile.map { "\($0.displayName) · \($0.shortLabel)" } ?? fallbackDialogueProfile(values["recommended_recent_project_dialogue_profile"]))",
            "effective \(recentProfile.map { "\($0.displayName) · \($0.shortLabel)" } ?? fallbackDialogueProfile(values["effective_recent_project_dialogue_profile"]))",
            "本轮选中 \(selectedPairs) pairs",
            "floor \(floorPairs) \(floorSatisfied ? "已满足" : "未满足")",
            "source \(recentSourceLabel)",
            "low-signal drop \(lowSignalDropped)"
        ]
        .joined(separator: " · ")

        var depthParts = [
            "Project Context Depth：configured \(configuredDepthProfile?.displayName ?? fallbackDepthProfile(values["configured_project_context_depth"]))",
            "recommended \(recommendedDepthProfile?.displayName ?? fallbackDepthProfile(values["recommended_project_context_depth"]))",
            "effective \(depthProfile?.displayName ?? fallbackDepthProfile(values["effective_project_context_depth"]))",
            "serving \(servingProfile?.rawValue ?? trimmed(values["effective_project_serving_profile"]) ?? "unknown")",
            "memory \(memorySourceLabel)"
        ]
        if let aTierMemoryCeiling {
            depthParts.insert("ceiling \(aTierMemoryCeiling.rawValue)", at: 3)
        }
        if ceilingHit {
            depthParts.append("ceiling hit")
        }
        let depthLine = depthParts.joined(separator: " · ")

        let coverageMetric = "wf \(yesNo(workflowPresent)) · ev \(yesNo(evidencePresent)) · gd \(yesNo(guidancePresent)) · xlink \(crossLinks)"
        let coverageLine = "Coverage：workflow \(yesNoWord(workflowPresent)) · evidence \(yesNoWord(evidencePresent)) · guidance \(yesNoWord(guidancePresent)) · cross-link hints \(crossLinks)"
        let boundaryMetric = boundaryReason == nil ? nil : "personal excluded"
        let boundaryLine = boundaryReason.map {
            "Boundary：personal memory excluded · \($0)"
        }
        let planeLine = planeDetailLine(selectedPlanes)
        let assemblyLine = assemblyDetailLine(selectedServingObjects)
        let omissionLine = omissionDetailLine(excludedBlocks)
        let budgetLine = budgetSummary.map { "Budget：\(projectMemoryBudgetSummaryLine($0))" }
        let userCoverageSummary = userCoverageSummary(
            workflowPresent: workflowPresent,
            evidencePresent: evidencePresent,
            guidancePresent: guidancePresent,
            crossLinks: crossLinks
        )
        let userPlaneSummary = userPlaneSummary(selectedPlanes)
        let userAssemblySummary = userAssemblySummary(selectedServingObjects)
        let userOmissionSummary = userOmissionSummary(excludedBlocks)
        let userBudgetSummary = budgetSummary.map(projectMemoryBudgetSummaryLine)
        let heartbeatDigestLine = Self.heartbeatDigestLine(
            present: heartbeatDigestPresent,
            visibility: heartbeatDigestVisibility,
            reasonCodes: heartbeatDigestReasonCodes
        )
        let executionMetricSummary = Self.executionMetric(
            currentStepPresent: automationCurrentStepPresent,
            verificationPresent: automationVerificationPresent,
            blockerPresent: automationBlockerPresent,
            retryReasonPresent: automationRetryReasonPresent,
            recoveryPresent: automationRecoveryReason != nil || automationRecoveryHoldReason != nil
        )
        let executionDetailLine = Self.executionLine(
            currentStepPresent: automationCurrentStepPresent,
            currentStepTitle: automationCurrentStepTitle,
            currentStepState: automationCurrentStepState,
            currentStepSummary: automationCurrentStepSummary,
            recoveryReason: automationRecoveryReason,
            recoveryHoldReason: automationRecoveryHoldReason,
            recoveryRetryAfterRemainingSeconds: automationRecoveryRetryAfterRemainingSeconds,
            verificationPresent: automationVerificationPresent,
            verificationRequired: automationVerificationRequired,
            verificationExecuted: automationVerificationExecuted,
            verificationPassedCommandCount: automationVerificationPassedCommandCount,
            verificationCommandCount: automationVerificationCommandCount,
            verificationHoldReason: automationVerificationHoldReason,
            blockerPresent: automationBlockerPresent,
            blockerSummary: automationBlockerSummary,
            blockerStage: automationBlockerStage,
            retryReasonPresent: automationRetryReasonPresent,
            retryReasonSummary: automationRetryReasonSummary,
            retryReasonStrategy: automationRetryReasonStrategy
        )
        let userExecutionSummaryLine = Self.userExecutionSummary(
            currentStepPresent: automationCurrentStepPresent,
            currentStepTitle: automationCurrentStepTitle,
            currentStepState: automationCurrentStepState,
            recoveryReason: automationRecoveryReason,
            recoveryHoldReason: automationRecoveryHoldReason,
            recoveryRetryAfterRemainingSeconds: automationRecoveryRetryAfterRemainingSeconds,
            verificationPresent: automationVerificationPresent,
            verificationRequired: automationVerificationRequired,
            verificationExecuted: automationVerificationExecuted,
            verificationPassedCommandCount: automationVerificationPassedCommandCount,
            verificationCommandCount: automationVerificationCommandCount,
            blockerPresent: automationBlockerPresent,
            blockerStage: automationBlockerStage,
            retryReasonPresent: automationRetryReasonPresent
        )
        let userHeartbeatSummary = Self.userHeartbeatSummary(
            present: heartbeatDigestPresent,
            visibility: heartbeatDigestVisibility,
            reasonCodes: heartbeatDigestReasonCodes
        )
        let userDepthLine = userDepthLine(
            configuredDepth: configuredDepthProfile,
            recommendedDepth: recommendedDepthProfile,
            effectiveDepth: depthProfile,
            ceiling: aTierMemoryCeiling,
            ceilingHit: ceilingHit
        )
        let userDialogueLine = userDialogueLine(
            configuredRecent: configuredRecentProfile,
            recommendedRecent: recommendedRecentProfile,
            effectiveRecent: recentProfile,
            selectedPairs: selectedPairs
        )

        return AXProjectContextAssemblyPresentation(
            sourceKind: .latestCoderUsage,
            projectLabel: projectLabel,
            sourceBadge: "Latest Usage",
            statusLine: latestUsageStatusLine(
                resolutionTrigger: resolutionTrigger,
                ceilingHit: ceilingHit
            ),
            recentDialogueSource: recentSource,
            recentDialogueSourceLabel: recentSourceLabel,
            recentDialogueSourceClass: XTMemorySourceTruthPresentation.sourceClass(recentSource),
            memorySource: memorySource,
            memorySourceLabel: memorySourceLabel,
            memorySourceClass: XTMemorySourceTruthPresentation.sourceClass(memorySource),
            dialogueMetric: dialogueMetric,
            depthMetric: depthMetric,
            dialogueLine: dialogueLine,
            depthLine: depthLine,
            executionMetric: executionMetricSummary,
            executionLine: executionDetailLine,
            coverageMetric: coverageMetric,
            coverageLine: coverageLine,
            boundaryMetric: boundaryMetric,
            boundaryLine: boundaryLine,
            planeLine: planeLine,
            assemblyLine: assemblyLine,
            omissionLine: omissionLine,
            budgetLine: budgetLine,
            userSourceBadge: "实际运行",
            userStatusLine: runtimeUserStatusLine(
                memorySourceLabel: explainableMemorySourceLabel,
                remoteSnapshotStatus: remoteSnapshotStatus
            ),
            userDialogueMetric: recentProfile.map { "\($0.displayName) · \($0.shortLabel)" }
                ?? fallbackDialogueProfile(values["recent_project_dialogue_profile"]),
            userDepthMetric: depthProfile?.displayName
                ?? fallbackDepthProfile(values["project_context_depth"]),
            userExecutionSummary: userExecutionSummaryLine,
            userCoverageSummary: userCoverageSummary,
            heartbeatDigestLine: heartbeatDigestLine,
            userHeartbeatSummary: userHeartbeatSummary,
            userBoundarySummary: boundaryReason == nil ? nil : "默认不读取你的个人记忆",
            userPlaneSummary: userPlaneSummary,
            userAssemblySummary: userAssemblySummary,
            userOmissionSummary: userOmissionSummary,
            userBudgetSummary: userBudgetSummary,
            userDialogueLine: userDialogueLine,
            userDepthLine: userDepthLine
        )
    }

    private static func configOnlyPresentation(
        values: [String: String],
        projectLabel: String?
    ) -> AXProjectContextAssemblyPresentation {
        let recentProfile = AXProjectRecentDialogueProfile(rawValue: values["configured_recent_project_dialogue_profile"] ?? "")
        let recommendedRecentProfile = recentDialogueProfile(
            values["recommended_recent_project_dialogue_profile"],
            fallback: values["configured_recent_project_dialogue_profile"]
        )
        let effectiveRecentProfile = recentDialogueProfile(
            values["effective_recent_project_dialogue_profile"],
            fallback: values["configured_recent_project_dialogue_profile"]
        )
        let depthProfile = AXProjectContextDepthProfile(rawValue: values["configured_project_context_depth"] ?? "")
        let recommendedDepthProfile = contextDepthProfile(
            values["recommended_project_context_depth"],
            fallback: values["configured_project_context_depth"]
        )
        let effectiveDepthProfile = contextDepthProfile(
            values["effective_project_context_depth"],
            fallback: values["configured_project_context_depth"]
        )
        let aTierMemoryCeiling = XTMemoryServingProfile.parse(values["a_tier_memory_ceiling"])
        let ceilingHit = bool(values["project_memory_ceiling_hit"])
        let dialogueMetric = recentProfile.map { "\($0.displayName) · \($0.shortLabel)" }
            ?? fallbackDialogueProfile(values["configured_recent_project_dialogue_profile"])
        let depthMetric = depthProfile?.displayName
            ?? fallbackDepthProfile(values["configured_project_context_depth"])
        return AXProjectContextAssemblyPresentation(
            sourceKind: .configOnly,
            projectLabel: projectLabel,
            sourceBadge: "Config Only",
            statusLine: configOnlyStatusLine(
                configuredDepth: depthProfile,
                effectiveDepth: effectiveDepthProfile,
                ceilingHit: ceilingHit
            ),
            dialogueMetric: dialogueMetric,
            depthMetric: depthMetric,
            dialogueLine: "Recent Project Dialogue：configured \(dialogueMetric) · recommended \(recommendedRecentProfile.map { "\($0.displayName) · \($0.shortLabel)" } ?? fallbackDialogueProfile(values["recommended_recent_project_dialogue_profile"])) · effective \(effectiveRecentProfile.map { "\($0.displayName) · \($0.shortLabel)" } ?? fallbackDialogueProfile(values["effective_recent_project_dialogue_profile"]))",
            depthLine: configOnlyDepthLine(
                configuredDepth: depthProfile,
                recommendedDepth: recommendedDepthProfile,
                effectiveDepth: effectiveDepthProfile,
                ceiling: aTierMemoryCeiling,
                ceilingHit: ceilingHit
            ),
            coverageMetric: nil,
            coverageLine: nil,
            boundaryMetric: nil,
            boundaryLine: nil,
            userSourceBadge: "配置基线",
            userStatusLine: "项目还没有实际运行记录，这里先显示当前配置会怎样喂给 project AI。",
            userDialogueMetric: dialogueMetric,
            userDepthMetric: depthMetric,
            userCoverageSummary: nil,
            userBoundarySummary: nil,
            userDialogueLine: "如果现在开始执行，最近项目对话会按 configured / recommended / effective 三值解析后再真正组装当前项目对话。",
            userDepthLine: userDepthLine(
                configuredDepth: depthProfile,
                recommendedDepth: recommendedDepthProfile,
                effectiveDepth: effectiveDepthProfile,
                ceiling: aTierMemoryCeiling,
                ceilingHit: ceilingHit
            )
        )
    }

    private static func keyValueMap(_ detailLines: [String]) -> [String: String] {
        detailLines.reduce(into: [String: String]()) { partial, line in
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = trimmedLine.firstIndex(of: "=") else { return }
            let key = String(trimmedLine[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let valueStart = trimmedLine.index(after: separator)
            let value = String(trimmedLine[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            partial[key] = value
        }
    }

    private static func csvValues(_ raw: String?) -> [String] {
        (raw ?? "")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func trimmed(_ raw: String?) -> String? {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func int(_ raw: String?) -> Int {
        guard let raw = trimmed(raw), let value = Int(raw) else { return 0 }
        return value
    }

    private static func optionalInt(_ raw: String?) -> Int? {
        guard let raw = trimmed(raw), let value = Int(raw) else { return nil }
        return value
    }

    private static func bool(_ raw: String?) -> Bool {
        switch trimmed(raw)?.lowercased() {
        case "1", "true", "yes":
            return true
        default:
            return false
        }
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }

    private static func yesNoWord(_ value: Bool) -> String {
        value ? "present" : "absent"
    }

    private static func fallbackDialogueProfile(_ raw: String?) -> String {
        trimmed(raw) ?? "unknown"
    }

    private static func fallbackDepthProfile(_ raw: String?) -> String {
        trimmed(raw) ?? "unknown"
    }

    private static func recentDialogueProfile(
        _ raw: String?,
        fallback: String?
    ) -> AXProjectRecentDialogueProfile? {
        AXProjectRecentDialogueProfile(
            rawValue: trimmed(raw) ?? trimmed(fallback) ?? ""
        )
    }

    private static func contextDepthProfile(
        _ raw: String?,
        fallback: String?
    ) -> AXProjectContextDepthProfile? {
        AXProjectContextDepthProfile(
            rawValue: trimmed(raw) ?? trimmed(fallback) ?? ""
        )
    }

    private static func userCoverageSummary(
        workflowPresent: Bool,
        evidencePresent: Bool,
        guidancePresent: Bool,
        crossLinks: Int
    ) -> String? {
        var parts: [String] = []
        if workflowPresent {
            parts.append("工作流")
        }
        if evidencePresent {
            parts.append("执行证据")
        }
        if guidancePresent {
            parts.append("review 提醒")
        }
        if crossLinks > 0 {
            parts.append("关联线索")
        }
        guard !parts.isEmpty else { return nil }
        return "已带" + localizedList(parts)
    }

    private static func executionMetric(
        currentStepPresent: Bool,
        verificationPresent: Bool,
        blockerPresent: Bool,
        retryReasonPresent: Bool,
        recoveryPresent: Bool
    ) -> String? {
        var parts: [String] = []
        if currentStepPresent {
            parts.append("step yes")
        }
        if verificationPresent {
            parts.append("verify yes")
        }
        if blockerPresent {
            parts.append("blocker yes")
        }
        if retryReasonPresent {
            parts.append("retry yes")
        }
        if recoveryPresent {
            parts.append("recovery yes")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private static func executionLine(
        currentStepPresent: Bool,
        currentStepTitle: String?,
        currentStepState: String?,
        currentStepSummary: String?,
        recoveryReason: String?,
        recoveryHoldReason: String?,
        recoveryRetryAfterRemainingSeconds: Int?,
        verificationPresent: Bool,
        verificationRequired: Bool?,
        verificationExecuted: Bool?,
        verificationPassedCommandCount: Int?,
        verificationCommandCount: Int?,
        verificationHoldReason: String?,
        blockerPresent: Bool,
        blockerSummary: String?,
        blockerStage: String?,
        retryReasonPresent: Bool,
        retryReasonSummary: String?,
        retryReasonStrategy: String?
    ) -> String? {
        var parts: [String] = []

        if currentStepPresent {
            var stepParts: [String] = []
            if let title = trimmed(currentStepTitle) {
                stepParts.append(title)
            }
            if let stateLabel = automationStepStateLabel(currentStepState) {
                stepParts.append(stateLabel)
            }
            if let summary = trimmed(currentStepSummary) {
                stepParts.append(summary)
            }
            if !stepParts.isEmpty {
                parts.append("step " + stepParts.joined(separator: " · "))
            }
        }

        if let recoveryReasonLabel = automationRecoveryReasonLabel(recoveryReason) {
            var recoveryParts = ["recovery \(recoveryReasonLabel)"]
            if let holdReason = trimmed(recoveryHoldReason) {
                recoveryParts.append("hold \(XTMemorySourceTruthPresentation.humanizeToken(holdReason))")
            }
            if let recoveryRetryAfterRemainingSeconds,
               recoveryRetryAfterRemainingSeconds >= 0 {
                recoveryParts.append("remaining \(recoveryRetryAfterRemainingSeconds)s")
            }
            parts.append(recoveryParts.joined(separator: " · "))
        }

        if verificationPresent {
            var verificationParts: [String] = []
            switch (verificationRequired, verificationExecuted) {
            case (false?, _):
                verificationParts.append("verification optional")
            case (true?, false?):
                verificationParts.append("verification pending")
            case (true?, true?):
                if let passed = verificationPassedCommandCount,
                   let total = verificationCommandCount,
                   total > 0 {
                    if passed >= total {
                        verificationParts.append("verification passed \(passed)/\(total)")
                    } else {
                        verificationParts.append("verification \(passed)/\(total) passed")
                    }
                } else {
                    verificationParts.append("verification executed")
                }
            case (nil, true?):
                verificationParts.append("verification executed")
            default:
                verificationParts.append("verification present")
            }

            if let holdReason = trimmed(verificationHoldReason) {
                verificationParts.append("hold \(XTMemorySourceTruthPresentation.humanizeToken(holdReason))")
            }

            if !verificationParts.isEmpty {
                parts.append(verificationParts.joined(separator: " · "))
            }
        }

        if blockerPresent,
           let blockerSummary = trimmed(blockerSummary) {
            if let blockerStage = automationBlockerStageLabel(blockerStage) {
                parts.append("blocker \(blockerStage): \(blockerSummary)")
            } else {
                parts.append("blocker \(blockerSummary)")
            }
        }

        if retryReasonPresent,
           let retryReasonSummary = trimmed(retryReasonSummary) {
            if let retryReasonStrategy = trimmed(retryReasonStrategy) {
                parts.append("retry \(retryReasonSummary) -> \(retryReasonStrategy)")
            } else {
                parts.append("retry \(retryReasonSummary)")
            }
        }

        guard !parts.isEmpty else { return nil }
        return "Execution State：" + parts.joined(separator: " · ")
    }

    private static func userExecutionSummary(
        currentStepPresent: Bool,
        currentStepTitle: String?,
        currentStepState: String?,
        recoveryReason: String?,
        recoveryHoldReason: String?,
        recoveryRetryAfterRemainingSeconds: Int?,
        verificationPresent: Bool,
        verificationRequired: Bool?,
        verificationExecuted: Bool?,
        verificationPassedCommandCount: Int?,
        verificationCommandCount: Int?,
        blockerPresent: Bool,
        blockerStage: String?,
        retryReasonPresent: Bool
    ) -> String? {
        var parts: [String] = []

        if currentStepPresent {
            let title = trimmed(currentStepTitle) ?? "当前步骤"
            if let stateLabel = automationStepStateLabel(currentStepState) {
                parts.append("当前停在“\(title)”（\(stateLabel)）")
            } else {
                parts.append("当前停在“\(title)”")
            }
        }

        if let recoverySummary = automationRecoveryUserSummary(
            reason: recoveryReason,
            holdReason: recoveryHoldReason,
            retryAfterRemainingSeconds: recoveryRetryAfterRemainingSeconds
        ) {
            parts.append(recoverySummary)
        }

        if verificationPresent {
            switch (verificationRequired, verificationExecuted) {
            case (false?, _):
                parts.append("这步不要求额外验证")
            case (true?, false?):
                parts.append("验证还没执行")
            case (_, true?):
                if let passed = verificationPassedCommandCount,
                   let total = verificationCommandCount,
                   total > 0 {
                    if passed >= total {
                        parts.append("验证已通过")
                    } else {
                        parts.append("验证通过 \(passed)/\(total)")
                    }
                } else {
                    parts.append("验证已执行")
                }
            default:
                parts.append("带入了验证状态")
            }
        }

        if blockerPresent {
            if let blockerStage = automationBlockerStageLabel(blockerStage) {
                parts.append("当前有\(blockerStage)阻塞")
            } else {
                parts.append("当前有结构化阻塞")
            }
        }

        if retryReasonPresent {
            parts.append("系统保留了重试原因")
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "，")
    }

    private static func automationRecoveryReasonLabel(_ raw: String?) -> String? {
        guard let raw = trimmed(raw),
              let reason = XTAutomationRecoveryCandidateReason(rawValue: raw) else {
            return trimmed(raw)
        }

        switch reason {
        case .latestVisibleRecoverable:
            return "recoverable"
        case .latestVisibleRetryWait:
            return "retry window pending"
        case .latestVisibleRetryBudgetExhausted:
            return "retry budget exhausted"
        case .latestVisibleStaleRecoverable:
            return "stale recoverable"
        case .latestVisibleStableIdentityFailed:
            return "stable identity failed"
        case .latestVisibleActiveRun:
            return "active run in progress"
        case .latestVisibleCancelled:
            return "cancelled"
        case .latestVisibleSuperseded:
            return "superseded"
        case .latestVisibleNotRecoverable:
            return "not restartable"
        case .noRecoverableUnsupersededRun:
            return "no recoverable run"
        }
    }

    private static func automationRecoveryUserSummary(
        reason: String?,
        holdReason: String?,
        retryAfterRemainingSeconds: Int?
    ) -> String? {
        guard let rawReason = trimmed(reason),
              let reason = XTAutomationRecoveryCandidateReason(rawValue: rawReason) else {
            return nil
        }

        switch reason {
        case .latestVisibleRecoverable:
            return "恢复链已可继续接上"
        case .latestVisibleRetryWait:
            if let retryAfterRemainingSeconds, retryAfterRemainingSeconds >= 0 {
                return "恢复链还在等重试窗口（剩余 \(retryAfterRemainingSeconds) 秒）"
            }
            if let holdReason = trimmed(holdReason) {
                return "恢复链暂时 hold（\(XTMemorySourceTruthPresentation.humanizeToken(holdReason))）"
            }
            return "恢复链还在等重试窗口"
        case .latestVisibleRetryBudgetExhausted:
            return "恢复链已触发重试额度上限"
        case .latestVisibleStaleRecoverable:
            return "恢复链对应的是待回收旧运行"
        case .latestVisibleStableIdentityFailed:
            return "恢复链身份校验失败，不能自动接续"
        case .latestVisibleActiveRun:
            return "当前已有进行中的运行，先看这条主链是否继续推进"
        case .latestVisibleCancelled:
            return "恢复链已被手动取消"
        case .latestVisibleSuperseded:
            return "恢复链已被后续运行替代"
        case .latestVisibleNotRecoverable:
            return "当前运行状态不可自动恢复"
        case .noRecoverableUnsupersededRun:
            return "当前没有可恢复的未替代运行"
        }
    }

    private static func automationStepStateLabel(_ raw: String?) -> String? {
        guard let raw = trimmed(raw) else { return nil }
        return XTAutomationRunStepState(rawValue: raw)?.displayName
            ?? XTMemorySourceTruthPresentation.humanizeToken(raw)
    }

    private static func automationBlockerStageLabel(_ raw: String?) -> String? {
        switch trimmed(raw) {
        case "bootstrap":
            return "启动"
        case "action":
            return "执行"
        case "verification":
            return "验证"
        case "policy":
            return "治理"
        case "recovery":
            return "恢复"
        case "runtime":
            return "运行时"
        case nil:
            return nil
        default:
            return XTMemorySourceTruthPresentation.humanizeToken(raw)
        }
    }

    private static func assemblyDetailLine(_ values: [String]) -> String? {
        let labels = assemblyObjectLabels(values)
        guard !labels.isEmpty else { return nil }
        return "Actual Assembly：\(localizedList(labels))"
    }

    private static func planeDetailLine(_ values: [String]) -> String? {
        let labels = assemblyPlaneLabels(values)
        guard !labels.isEmpty else { return nil }
        return "Active Planes：\(localizedList(labels))"
    }

    private static func omissionDetailLine(_ values: [String]) -> String? {
        let labels = assemblyObjectLabels(values)
        guard !labels.isEmpty else { return nil }
        return "Omitted Blocks：\(localizedList(labels))"
    }

    private static func userAssemblySummary(_ values: [String]) -> String? {
        let labels = assemblyObjectLabels(values)
        guard !labels.isEmpty else { return nil }
        return "实际带入" + localizedList(labels)
    }

    private static func userPlaneSummary(_ values: [String]) -> String? {
        let labels = assemblyPlaneLabels(values)
        guard !labels.isEmpty else { return nil }
        return "实际启用" + localizedList(labels)
    }

    private static func runtimeUserStatusLine(
        memorySourceLabel: String,
        remoteSnapshotStatus: String?
    ) -> String {
        var parts = [
            "这里显示的是最近一次真正喂给 project AI 的背景，不是静态配置。",
            "当前来源：\(memorySourceLabel)"
        ]
        if let remoteSnapshotStatus, !remoteSnapshotStatus.isEmpty {
            parts.append("remote snapshot：\(remoteSnapshotStatus)")
        }
        parts.append("durable truth 仍只经 Writer + Gate 写入。")
        return parts.joined(separator: "；")
    }

    private static func heartbeatDigestLine(
        present: Bool,
        visibility: String?,
        reasonCodes: [String]
    ) -> String? {
        guard let summary = userHeartbeatSummary(
            present: present,
            visibility: visibility,
            reasonCodes: reasonCodes
        ) else {
            return nil
        }
        return "Heartbeat Digest：\(summary)"
    }

    private static func userHeartbeatSummary(
        present: Bool,
        visibility: String?,
        reasonCodes: [String]
    ) -> String? {
        let normalizedVisibility = trimmed(visibility) ?? ""
        let visibilityLabel = heartbeatDigestVisibilityLabel(normalizedVisibility)
        let reasonLabel = heartbeatDigestReasonLabel(reasonCodes)

        if present {
            var parts = [
                "heartbeat digest 已作为 working-set advisory 带入本轮 Project AI 上下文"
            ]
            if let visibilityLabel {
                parts.append("visibility \(visibilityLabel)")
            }
            if let reasonLabel {
                parts.append("reason \(reasonLabel)")
            }
            return parts.joined(separator: " · ")
        }

        if let visibilityLabel {
            if let reasonLabel {
                return "heartbeat digest 本轮未进入 Project AI working set · visibility \(visibilityLabel) · reason \(reasonLabel)"
            }
            return "heartbeat digest 本轮未进入 Project AI working set · visibility \(visibilityLabel)"
        }

        guard let reasonLabel else { return nil }
        return "heartbeat digest 本轮未进入 Project AI working set · reason \(reasonLabel)"
    }

    private static func heartbeatDigestVisibilityLabel(_ raw: String) -> String? {
        switch raw {
        case "":
            return nil
        case XTHeartbeatDigestVisibilityDecision.shown.rawValue:
            return "shown"
        case XTHeartbeatDigestVisibilityDecision.suppressed.rawValue:
            return "suppressed"
        default:
            return raw
        }
    }

    private static func heartbeatDigestReasonLabel(_ codes: [String]) -> String? {
        let normalized = codes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return nil }
        return localizedList(normalized)
    }

    private static func remoteSnapshotStatusSummary(
        memorySource: String?,
        freshness: String?,
        cacheHit: Bool?,
        scope: String?,
        ageMs: Int?,
        ttlRemainingMs: Int?
    ) -> String? {
        let normalizedFreshness = trimmed(freshness) ?? ""
        let freshnessLabel: String
        switch normalizedFreshness {
        case "ttl_cache":
            freshnessLabel = "TTL cache"
        case "fresh_remote":
            freshnessLabel = "fresh remote"
        case "fresh_remote_required":
            freshnessLabel = "fresh remote required"
        case "":
            if cacheHit == true {
                freshnessLabel = "TTL cache"
            } else {
                freshnessLabel = ""
            }
        default:
            freshnessLabel = normalizedFreshness
        }

        var parts: [String] = []
        if !freshnessLabel.isEmpty {
            parts.append(freshnessLabel)
        }
        if let provenanceLabel = remoteSnapshotProvenanceLabel(
            memorySource: memorySource,
            freshness: normalizedFreshness,
            cacheHit: cacheHit
        ) {
            parts.append(provenanceLabel)
        }
        if let ageMs, ageMs >= 0 {
            parts.append("age \(durationSummary(ageMs))")
        }
        if let ttlRemainingMs, ttlRemainingMs >= 0 {
            parts.append("ttl 剩余 \(durationSummary(ttlRemainingMs))")
        }
        if let scope, !scope.isEmpty {
            parts.append(scope)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func remoteSnapshotProvenanceLabel(
        memorySource: String?,
        freshness: String,
        cacheHit: Bool?
    ) -> String? {
        guard trimmed(memorySource) == "hub_memory_v1_grpc" else { return nil }

        switch freshness {
        case "ttl_cache":
            return "Hub truth via XT cache"
        case "fresh_remote":
            return "Hub truth fresh fetch"
        case "":
            return cacheHit == true ? "Hub truth via XT cache" : nil
        default:
            return nil
        }
    }

    private static func durationSummary(_ milliseconds: Int) -> String {
        if milliseconds >= 60_000 {
            return "\(milliseconds / 60_000)m"
        }
        if milliseconds >= 1_000 {
            return "\(milliseconds / 1_000)s"
        }
        return "\(milliseconds)ms"
    }

    private static func userOmissionSummary(_ values: [String]) -> String? {
        let labels = assemblyObjectLabels(values)
        guard !labels.isEmpty else { return nil }
        return "本轮未带" + localizedList(labels)
    }

    private static func assemblyObjectLabels(_ values: [String]) -> [String] {
        values.compactMap(assemblyObjectLabel)
    }

    private static func assemblyPlaneLabels(_ values: [String]) -> [String] {
        values.compactMap(assemblyPlaneLabel)
    }

    private static func assemblyObjectLabel(_ raw: String) -> String? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "recent_project_dialogue_window":
            return "最近项目对话"
        case "focused_project_anchor_pack":
            return "项目锚点"
        case "current_step":
            return "当前步骤"
        case "verification_state":
            return "验证状态"
        case "blocker_state":
            return "结构化阻塞"
        case "retry_reason":
            return "重试原因"
        case "active_workflow":
            return "活动工作流"
        case "selected_cross_link_hints":
            return "关联线索"
        case "longterm_outline":
            return "长期轮廓"
        case "execution_evidence":
            return "执行证据"
        case "guidance":
            return "Supervisor 指导"
        default:
            return nil
        }
    }

    private static func assemblyPlaneLabel(_ raw: String) -> String? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "project_dialogue_plane":
            return "项目对话面"
        case "project_anchor_plane":
            return "项目锚点面"
        case "execution_state_plane":
            return "执行状态面"
        case "workflow_plane":
            return "工作流面"
        case "cross_link_plane":
            return "关联线索面"
        case "longterm_plane":
            return "长期轮廓面"
        case "evidence_plane":
            return "证据面"
        case "guidance_plane":
            return "Supervisor 指导面"
        default:
            return nil
        }
    }

    private static func projectMemoryBudgetSummaryLine(_ raw: String) -> String {
        let parts = raw
            .split(separator: "·")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let localized = parts.map { part -> String in
            if let value = part.split(separator: "=", maxSplits: 1).dropFirst().first,
               part.hasPrefix("source=") {
                return "source \(XTMemorySourceTruthPresentation.label(String(value)))"
            }
            if let value = part.split(separator: "=", maxSplits: 1).dropFirst().first,
               part.hasPrefix("used=") {
                return "used \(value) tok"
            }
            if let value = part.split(separator: "=", maxSplits: 1).dropFirst().first,
               part.hasPrefix("budget=") {
                return "budget \(value) tok"
            }
            if let value = part.split(separator: "=", maxSplits: 1).dropFirst().first,
               part.hasPrefix("truncated=") {
                return "truncated \(value)"
            }
            return part
        }
        return localized.joined(separator: " · ")
    }

    private static func latestUsageStatusLine(
        resolutionTrigger: String?,
        ceilingHit: Bool
    ) -> String {
        let base = "最近一次 coder context assembly 已被捕获，Doctor 现在显示的是 runtime 实际喂给 project AI 的背景，而不只是静态配置。"
        guard let resolutionTrigger = trimmed(resolutionTrigger) else {
            return ceilingHit ? base + " 当前深度命中了 A-tier ceiling。" : base
        }
        let triggerSummary = projectMemoryResolutionTriggerSummary(resolutionTrigger)
        if ceilingHit {
            return base + " 触发原因：\(triggerSummary)。当前深度命中了 A-tier ceiling。"
        }
        return base + " 触发原因：\(triggerSummary)。"
    }

    private static func projectMemoryResolutionTriggerSummary(_ raw: String) -> String {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let label: String
        switch normalized {
        case "manual_full_scan_request":
            label = "用户要求完整扫描项目上下文"
        case "manual_review_request":
            label = "用户要求先做 review / plan 梳理"
        case "resume_from_checkpoint":
            label = "本轮按 checkpoint continuity 接续"
        case "restart_recovery":
            label = "恢复链需要重新接续当前 run"
        case "retry_execution":
            label = "自动重试链继续上次执行"
        case "persistent_blocker":
            label = "当前存在结构化 blocker"
        case "verification_gap":
            label = "验证状态需要优先处理"
        case "review_guidance_follow_up":
            label = "带着 review guidance 跟进执行"
        case "guided_execution":
            label = "带着 Supervisor guidance 执行"
        case "execution_step_follow_up":
            label = "沿当前执行步骤继续"
        case "evidence_backed_execution":
            label = "基于最新执行证据继续"
        case "normal_reply", "normal_execution":
            label = "普通项目回复"
        case "config_only_baseline":
            label = "仅配置基线"
        default:
            label = XTMemorySourceTruthPresentation.humanizeToken(normalized)
        }
        return "\(label)（\(normalized)）"
    }

    private static func configOnlyStatusLine(
        configuredDepth: AXProjectContextDepthProfile?,
        effectiveDepth: AXProjectContextDepthProfile?,
        ceilingHit: Bool
    ) -> String {
        let base = "当前还没有 recent coder usage explainability，所以这里只显示配置基线；等 project AI 真正跑过一轮后，这里会切到实际 runtime assembly。"
        guard ceilingHit else { return base }
        return base + " 按当前治理，背景深度会从 \(configuredDepth?.displayName ?? "当前配置") 收束到 \(effectiveDepth?.displayName ?? "当前生效值")。"
    }

    private static func configOnlyDepthLine(
        configuredDepth: AXProjectContextDepthProfile?,
        recommendedDepth: AXProjectContextDepthProfile?,
        effectiveDepth: AXProjectContextDepthProfile?,
        ceiling: XTMemoryServingProfile?,
        ceilingHit: Bool
    ) -> String {
        var parts = [
            "Project Context Depth：configured \(configuredDepth?.displayName ?? "unknown")",
            "recommended \(recommendedDepth?.displayName ?? "unknown")",
            "effective \(effectiveDepth?.displayName ?? "unknown")"
        ]
        if let ceiling {
            parts.append("ceiling \(ceiling.rawValue)")
        }
        if ceilingHit {
            parts.append("ceiling hit")
        }
        return parts.joined(separator: " · ")
    }

    private static func userDialogueLine(
        configuredRecent: AXProjectRecentDialogueProfile?,
        recommendedRecent: AXProjectRecentDialogueProfile?,
        effectiveRecent: AXProjectRecentDialogueProfile?,
        selectedPairs: Int
    ) -> String {
        let configured = configuredRecent.map { "\($0.displayName) · \($0.shortLabel)" } ?? "当前配置"
        let recommended = recommendedRecent.map { "\($0.displayName) · \($0.shortLabel)" } ?? "系统建议"
        let effective = effectiveRecent.map { "\($0.displayName) · \($0.shortLabel)" } ?? "当前生效值"
        return "这轮最近项目对话按 configured \(configured) / recommended \(recommended) / effective \(effective) 解析，本轮实际选中 \(selectedPairs) 组对话。"
    }

    private static func userDepthLine(
        configuredDepth: AXProjectContextDepthProfile?,
        recommendedDepth: AXProjectContextDepthProfile?,
        effectiveDepth: AXProjectContextDepthProfile?,
        ceiling: XTMemoryServingProfile?,
        ceilingHit: Bool
    ) -> String {
        var parts = [
            "当前背景深度按 configured \(configuredDepth?.displayName ?? "当前配置")",
            "recommended \(recommendedDepth?.displayName ?? "系统建议")",
            "effective \(effectiveDepth?.displayName ?? "当前生效值")"
        ]
        if let ceiling {
            parts.append("A-tier ceiling \(ceiling.rawValue)")
        }
        if ceilingHit {
            parts.append("当前命中了治理 ceiling")
        }
        parts.append("这会决定这轮带入多少项目工作流、review 和执行证据。")
        return parts.joined(separator: " · ")
    }

    private static func localizedList(_ items: [String]) -> String {
        switch items.count {
        case 0:
            return ""
        case 1:
            return items[0]
        case 2:
            return "\(items[0])和\(items[1])"
        default:
            return items.dropLast().joined(separator: "、") + "和" + items.last!
        }
    }
}

extension AXProjectContextAssemblyPresentation {
    var compactSummary: AXProjectContextAssemblyCompactSummary {
        let detailCandidates = [
            compactSummaryValue(userExecutionSummary),
            compactSummaryValue(userAssemblySummary ?? userCoverageSummary),
            compactSummaryValue(userOmissionSummary ?? userBoundarySummary),
            compactSummaryValue(userHeartbeatSummary),
        ].compactMap { $0 }
        let detailText: String? = if !detailCandidates.isEmpty {
            detailCandidates.joined(separator: " · ")
        } else if sourceKind == .configOnly {
            "还没有 recent coder usage explainability，当前先按配置基线显示"
        } else {
            nil
        }

        let helpSegments = [
            compactSummaryValue(userStatusLine),
            compactSummaryValue(userExecutionSummary),
            compactSummaryValue(userHeartbeatSummary),
            compactSummaryValue(userBoundarySummary),
            compactSummaryValue(userBudgetSummary),
            "A-Tier 只提供 Project AI 的 project-memory ceiling；Recent Project Dialogue 和 Project Context Depth 仍由 role-aware resolver 单独计算。"
        ].compactMap { $0 }

        return AXProjectContextAssemblyCompactSummary(
            headlineText: "\(userSourceBadge) · \(userDialogueMetric) / \(userDepthMetric)",
            detailText: detailText,
            helpText: helpSegments.joined(separator: " ")
        )
    }

    private func compactSummaryValue(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
