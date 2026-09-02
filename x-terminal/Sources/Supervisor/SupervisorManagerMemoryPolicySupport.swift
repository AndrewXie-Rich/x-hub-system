import Foundation

extension SupervisorManager {
    func resolveSupervisorMemoryPolicyForAssembly(
        reviewLevelHint: SupervisorReviewLevel,
        dominantMode: SupervisorTurnMode,
        focusedProjectSelected: Bool,
        crossLinkContextAvailable: Bool,
        userMessage: String,
        triggerSource: SupervisorCommandTriggerSource,
        governanceReviewTrigger: SupervisorReviewTrigger?,
        governanceReviewRunKind: SupervisorReviewRunKind?,
        reviewMemoryCeiling: XTMemoryServingProfile?,
        assemblyPurpose: XTSupervisorMemoryAssemblyPurpose,
        projectMemoryBinding: SupervisorProjectMemoryBindingDecision
    ) -> XTSupervisorMemoryPolicy {
        XTRoleAwareMemoryPolicyResolver.resolveSupervisor(
            configuredSupervisorRecentRawContextProfile: appModel?.settingsStore.settings.supervisorRecentRawContextProfile
                ?? .defaultProfile,
            configuredReviewMemoryDepth: appModel?.settingsStore.settings.supervisorReviewMemoryDepthProfile
                ?? .defaultProfile,
            reviewLevelHint: reviewLevelHint,
            dominantMode: dominantMode,
            focusedProjectSelected: focusedProjectSelected,
            crossLinkContextAvailable: crossLinkContextAvailable,
            userMessage: userMessage,
            triggerSource: triggerSource.rawValue,
            governanceReviewTrigger: governanceReviewTrigger,
            governanceReviewRunKind: governanceReviewRunKind,
            reviewMemoryCeiling: reviewMemoryCeiling,
            privacyMode: currentSupervisorPrivacyMode,
            assemblyPurpose: assemblyPurpose,
            projectMemoryBindingStrength: projectMemoryBinding.strength,
            projectMemorySuppressedForPureChat: projectMemoryBinding.projectMemorySuppressedForPureChat,
            suppressionReason: projectMemoryBinding.suppressionReason
        )
    }

    func preferredSupervisorMemoryServingProfile(
        userMessage: String,
        focusedProjectSelected: Bool
    ) -> XTMemoryServingProfile {
        let reviewLevelHint = preferredSupervisorReviewLevelHintForMemory(userMessage: userMessage)
        let preferred = XTMemoryServingProfileSelector.preferredSupervisorProfile(userMessage: userMessage)
            ?? .m1Execute
        let floor = minimumSupervisorServingProfile(
            for: reviewLevelHint,
            focusedProjectSelected: focusedProjectSelected,
            assemblyPurpose: .governanceReview
        )
        return preferred.rank >= floor.rank ? preferred : floor
    }

    func preferredSupervisorReviewLevelHintForMemory(
        userMessage: String
    ) -> SupervisorReviewLevel {
        explicitSupervisorReviewLevelHint(in: userMessage)
            ?? inferredSupervisorReviewLevelHintForMemory(userMessage: userMessage)
    }

    func supervisorMemoryGovernanceReviewTrigger(
        triggerSource: SupervisorCommandTriggerSource,
        assemblyPurpose: XTSupervisorMemoryAssemblyPurpose,
        explicitTrigger: SupervisorReviewTrigger?,
        userMessage: String
    ) -> SupervisorReviewTrigger? {
        guard assemblyPurpose == .governanceReview || assemblyPurpose == .portfolioReview else {
            return nil
        }
        if let explicitTrigger {
            return explicitTrigger
        }
        guard triggerSource != .userTurn else {
            return nil
        }
        return inferredSupervisorReviewTrigger(
            userMessage: userMessage,
            triggerSource: triggerSource
        )
    }

    func supervisorMemoryGovernanceReviewRunKind(
        triggerSource: SupervisorCommandTriggerSource,
        assemblyPurpose: XTSupervisorMemoryAssemblyPurpose,
        trigger: SupervisorReviewTrigger?,
        explicitRunKind: SupervisorReviewRunKind?
    ) -> SupervisorReviewRunKind? {
        guard assemblyPurpose == .governanceReview || assemblyPurpose == .portfolioReview else {
            return nil
        }
        if let explicitRunKind {
            return explicitRunKind
        }
        guard let trigger, triggerSource != .userTurn else {
            return nil
        }
        return defaultSupervisorReviewRunKind(
            triggerSource: triggerSource,
            trigger: trigger
        )
    }

    func resolvedSupervisorProjectMemoryBinding(
        triggerSource: SupervisorCommandTriggerSource,
        userMessage: String,
        routingDecision: SupervisorTurnRoutingDecision,
        selection: SupervisorFocusedProjectSelection?
    ) -> SupervisorProjectMemoryBindingDecision {
        guard let selection else {
            return SupervisorProjectMemoryBindingDecision(
                strength: .none,
                effectiveSelection: nil,
                projectMemorySuppressedForPureChat: false,
                suppressionReason: nil
            )
        }

        switch triggerSource {
        case .heartbeat, .guidanceAck, .automationSafePoint, .incident, .externalTriggerIngress,
             .grantResolution, .approvalResolution, .officialSkillsChannel, .skillCallback:
            return SupervisorProjectMemoryBindingDecision(
                strength: .strong,
                effectiveSelection: selection,
                projectMemorySuppressedForPureChat: false,
                suppressionReason: nil
            )
        case .userTurn:
            break
        }

        if routingDecision.projectMemoryBindingStrength.requiresProjectTruth {
            return SupervisorProjectMemoryBindingDecision(
                strength: routingDecision.projectMemoryBindingStrength,
                effectiveSelection: selection,
                projectMemorySuppressedForPureChat: false,
                suppressionReason: nil
            )
        }

        switch selection.source {
        case "selected_project", "current_task", "single_project":
            if supervisorAmbientProjectTruthSignals(userMessage) {
                return SupervisorProjectMemoryBindingDecision(
                    strength: .strong,
                    effectiveSelection: selection,
                    projectMemorySuppressedForPureChat: false,
                    suppressionReason: nil
                )
            }
            return SupervisorProjectMemoryBindingDecision(
                strength: .none,
                effectiveSelection: nil,
                projectMemorySuppressedForPureChat: true,
                suppressionReason: "ambient_project_selection_without_project_truth_need"
            )
        default:
            return SupervisorProjectMemoryBindingDecision(
                strength: routingDecision.projectMemoryBindingStrength,
                effectiveSelection: nil,
                projectMemorySuppressedForPureChat: routingDecision.projectMemoryBindingStrength != .none,
                suppressionReason: routingDecision.projectMemoryBindingReason
            )
        }
    }

    func supervisorAmbientProjectTruthSignals(
        _ userMessage: String
    ) -> Bool {
        let normalized = normalizedSupervisorIntentText(userMessage)
        let normalizedKey = normalizedLookupKey(userMessage)
        guard !normalized.isEmpty || !normalizedKey.isEmpty else { return false }

        let tokens = [
            "继续",
            "接着",
            "按这个继续",
            "继续推进",
            "继续做",
            "下一步",
            "怎么推进",
            "进度",
            "状态",
            "blocker",
            "卡点",
            "阻塞",
            "工单",
            "步骤",
            "step",
            "build",
            "test",
            "repo",
            "代码",
            "文件",
            "编译",
            "修复",
            "fix",
            "patch",
            "bug",
            "报错",
            "错误",
            "日志",
            "log",
            "验证",
            "verify",
            "证据",
            "evidence",
            "交付",
            "done",
            "恢复",
            "重试"
        ]
        return containsAny(normalized, tokens) || normalizedContainsAny(normalizedKey, tokens)
    }

    func preferredSupervisorMemoryAssemblyPurpose(
        triggerSource: SupervisorCommandTriggerSource,
        userMessage: String,
        reviewLevelHint: SupervisorReviewLevel,
        dominantMode: SupervisorTurnMode,
        focusedProjectSelected: Bool,
        projectMemoryBindingStrength: SupervisorProjectMemoryBindingStrength
    ) -> XTSupervisorMemoryAssemblyPurpose {
        if dominantMode == .portfolioReview {
            return .portfolioReview
        }

        switch triggerSource {
        case .heartbeat, .guidanceAck, .automationSafePoint, .incident, .externalTriggerIngress,
             .grantResolution, .approvalResolution, .officialSkillsChannel:
            return .governanceReview
        case .userTurn, .skillCallback:
            break
        }

        if XTMemoryServingProfileSelector.fullScanRequestSignals(userMessage) {
            return .governanceReview
        }
        if projectMemoryBindingStrength.requiresProjectTruth
            && XTMemoryServingProfileSelector.reviewPlanRequestSignals(userMessage) {
            return .governanceReview
        }
        if projectMemoryBindingStrength.requiresProjectTruth && reviewLevelHint == .r3Rescue {
            return .governanceReview
        }
        if projectMemoryBindingStrength.requiresProjectTruth && focusedProjectSelected {
            return .projectAssist
        }
        return .conversation
    }

    func inferredSupervisorReviewLevelHintForMemory(
        userMessage: String
    ) -> SupervisorReviewLevel {
        let normalized = normalizedSupervisorIntentText(userMessage)
        if containsAny(
            normalized,
            [
                "高风险", "上线", "发布", "验收", "停止", "暂停", "rescue",
                "incident", "紧急", "事故", "回滚", "授权"
            ]
        ) {
            return .r3Rescue
        }
        if containsAny(
            normalized,
            [
                "review", "审查", "审阅", "评审", "brainstorm", "blocker",
                "阻塞", "drift", "跑偏", "纠偏", "architecture", "架构",
                "方向", "重构", "better path", "更好的", "方案", "计划"
            ]
        ) {
            return .r2Strategic
        }
        return .r1Pulse
    }

    func minimumSupervisorServingProfile(
        for reviewLevelHint: SupervisorReviewLevel,
        focusedProjectSelected: Bool,
        assemblyPurpose: XTSupervisorMemoryAssemblyPurpose
    ) -> XTMemoryServingProfile {
        switch assemblyPurpose {
        case .conversation:
            return .m1Execute
        case .projectAssist:
            return .m1Execute
        case .governanceReview, .portfolioReview:
            break
        }
        switch reviewLevelHint {
        case .r1Pulse:
            return .m1Execute
        case .r2Strategic:
            return focusedProjectSelected ? .m3DeepDive : .m2PlanReview
        case .r3Rescue:
            return .m3DeepDive
        }
    }

    func supervisorServingGovernorSection(
        servingProfile: XTMemoryServingProfile,
        reviewLevelHint: SupervisorReviewLevel,
        focusedProjectSelected: Bool,
        assemblyPurpose: XTSupervisorMemoryAssemblyPurpose,
        reviewMemoryCeiling: XTMemoryServingProfile? = nil
    ) -> String {
        let metadata = supervisorServingGovernorMetadata(
            servingProfile: servingProfile,
            reviewLevelHint: reviewLevelHint,
            focusedProjectSelected: focusedProjectSelected,
            assemblyPurpose: assemblyPurpose,
            reviewMemoryCeiling: reviewMemoryCeiling
        )

        return """
[SERVING_GOVERNOR]
review_level_hint: \(reviewLevelHint.rawValue)
profile_floor: \(metadata.profileFloor.rawValue)
minimum_pack: \(metadata.minimumPack.isEmpty ? "(none)" : metadata.minimumPack.joined(separator: ", "))
compression_policy: \(metadata.compressionPolicy)
[/SERVING_GOVERNOR]
"""
    }

    func supervisorServingGovernorMetadata(
        servingProfile: XTMemoryServingProfile,
        reviewLevelHint: SupervisorReviewLevel,
        focusedProjectSelected: Bool,
        assemblyPurpose: XTSupervisorMemoryAssemblyPurpose,
        reviewMemoryCeiling: XTMemoryServingProfile? = nil
    ) -> SupervisorServingGovernorMetadata {
        let unclampedFloor = minimumSupervisorServingProfile(
            for: reviewLevelHint,
            focusedProjectSelected: focusedProjectSelected,
            assemblyPurpose: assemblyPurpose
        )
        let profileFloor = reviewMemoryCeiling.map {
            min(unclampedFloor, $0)
        } ?? unclampedFloor
        let minimumPack = orderedSupervisorMinimumPack(
            servingProfile: servingProfile,
            reviewLevelHint: reviewLevelHint,
            focusedProjectSelected: focusedProjectSelected,
            assemblyPurpose: assemblyPurpose,
            profileFloor: profileFloor
        )
        let compressionPolicy: String
        switch reviewLevelHint {
        case .r1Pulse:
            compressionPolicy = "protect_anchor_then_delta_then_portfolio"
        case .r2Strategic:
            compressionPolicy = focusedProjectSelected
                ? "protect_anchor_longterm_decision_blocker_and_evidence_first"
                : "protect_anchor_conflict_longterm_then_refs"
        case .r3Rescue:
            compressionPolicy = "protect_anchor_conflict_and_evidence_first"
        }

        return SupervisorServingGovernorMetadata(
            profileFloor: profileFloor,
            minimumPack: minimumPack,
            compressionPolicy: compressionPolicy
        )
    }

    func orderedSupervisorMinimumPack(
        servingProfile: XTMemoryServingProfile,
        reviewLevelHint: SupervisorReviewLevel,
        focusedProjectSelected: Bool,
        assemblyPurpose: XTSupervisorMemoryAssemblyPurpose,
        profileFloor: XTMemoryServingProfile? = nil
    ) -> [String] {
        let profilePack = minimumPackForSupervisorServingProfile(servingProfile)
        let allowedReviewSections = Set(profilePack)
        let reviewPack = minimumPackForSupervisorReviewLevel(
            reviewLevelHint,
            focusedProjectSelected: focusedProjectSelected
        ).filter { allowedReviewSections.contains($0) }
        let reviewFloor = profileFloor ?? minimumSupervisorServingProfile(
            for: reviewLevelHint,
            focusedProjectSelected: focusedProjectSelected,
            assemblyPurpose: assemblyPurpose
        )
        let orderedPacks = reviewFloor.rank > servingProfile.rank
            ? [reviewPack, profilePack]
            : [profilePack, reviewPack]
        var seen = Set<String>()
        var ordered: [String] = []
        for pack in orderedPacks {
            for item in pack {
                guard seen.insert(item).inserted else { continue }
                ordered.append(item)
            }
        }
        return ordered
    }

    func minimumPackForSupervisorServingProfile(
        _ servingProfile: XTMemoryServingProfile
    ) -> [String] {
        switch servingProfile {
        case .m0Heartbeat:
            return ["portfolio_brief", "delta_feed"]
        case .m1Execute:
            return ["portfolio_brief", "focused_project_anchor_pack", "delta_feed"]
        case .m2PlanReview:
            return [
                "portfolio_brief",
                "focused_project_anchor_pack",
                "longterm_outline",
                "delta_feed",
                "conflict_set",
                "context_refs"
            ]
        case .m3DeepDive, .m4FullScan:
            return [
                "portfolio_brief",
                "focused_project_anchor_pack",
                "longterm_outline",
                "delta_feed",
                "conflict_set",
                "context_refs",
                "evidence_pack"
            ]
        }
    }

    func minimumPackForSupervisorReviewLevel(
        _ reviewLevelHint: SupervisorReviewLevel,
        focusedProjectSelected: Bool
    ) -> [String] {
        switch reviewLevelHint {
        case .r1Pulse:
            return ["portfolio_brief", "focused_project_anchor_pack", "delta_feed"]
        case .r2Strategic:
            return focusedProjectSelected ? [
                "portfolio_brief",
                "focused_project_anchor_pack",
                "longterm_outline",
                "delta_feed",
                "conflict_set",
                "context_refs",
                "evidence_pack"
            ] : [
                "portfolio_brief",
                "focused_project_anchor_pack",
                "longterm_outline",
                "delta_feed",
                "conflict_set",
                "context_refs"
            ]
        case .r3Rescue:
            return [
                "portfolio_brief",
                "focused_project_anchor_pack",
                "longterm_outline",
                "delta_feed",
                "conflict_set",
                "context_refs",
                "evidence_pack"
            ]
        }
    }
}
