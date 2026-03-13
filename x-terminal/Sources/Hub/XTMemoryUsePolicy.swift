import Foundation

enum XTMemoryRequesterRole: String, CaseIterable, Sendable {
    case chat
    case session
    case supervisor
    case tool
    case lane
    case remoteExport
}

enum XTMemoryLayer: String, CaseIterable, Sendable {
    case l0Constitution = "l0_constitution"
    case l1Canonical = "l1_canonical"
    case l2Observations = "l2_observations"
    case l3WorkingSet = "l3_working_set"
    case l4RawEvidence = "l4_raw_evidence"
}

enum XTMemoryFreshnessPolicy: String, Sendable {
    case allowShortTTLCache = "allow_short_ttl_cache"
    case requireFreshRemoteSnapshot = "require_fresh_remote_snapshot"
    case refsOnly = "refs_only"
}

enum XTMemoryUserMemoryPolicy: String, Sendable {
    case defaultOff = "default_off"
    case explicitGrantRequired = "explicit_grant_required"
    case denied = "denied"
}

enum XTMemoryLongtermPolicy: String, Sendable {
    case summaryOnly = "summary_only"
    case progressiveDisclosureRequired = "progressive_disclosure_required"
    case denied = "denied"
}

enum XTMemoryRemoteExportPolicy: String, Sendable {
    case localOnly = "local_only"
    case sanitizedOnly = "sanitized_only"
    case refsOnly = "refs_only"
}

enum XTMemoryUseDenyCode: String, Sendable {
    case memoryLayerNotAllowedForMode = "memory_layer_not_allowed_for_mode"
    case userMemoryGrantRequired = "user_memory_grant_required"
    case crossScopeMemoryDenied = "cross_scope_memory_denied"
    case longtermFulltextPDRequired = "longterm_fulltext_pd_required"
    case rawEvidenceRemoteExportDenied = "raw_evidence_remote_export_denied"
    case memorySnapshotStaleForHighRiskAct = "memory_snapshot_stale_for_high_risk_act"
    case laneHandoffFulltextDenied = "lane_handoff_fulltext_denied"
    case memoryModeContractMissing = "memory_mode_contract_missing"
    case memoryRoutePolicyMismatch = "memory_route_policy_mismatch"
}

enum XTMemoryUseMode: String, CaseIterable, Sendable {
    case projectChat = "project_chat"
    case sessionResume = "session_resume"
    case supervisorOrchestration = "supervisor_orchestration"
    case toolPlan = "tool_plan"
    case toolActLowRisk = "tool_act_low_risk"
    case toolActHighRisk = "tool_act_high_risk"
    case laneHandoff = "lane_handoff"
    case remotePromptBundle = "remote_prompt_bundle"

    static func parse(_ raw: String?) -> XTMemoryUseMode? {
        let token = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !token.isEmpty else { return .projectChat }
        if let mode = XTMemoryUseMode(rawValue: token) {
            return mode
        }
        switch token {
        case "project":
            return .projectChat
        case "supervisor":
            return .supervisorOrchestration
        case "session":
            return .sessionResume
        case "tool":
            return .toolPlan
        default:
            return nil
        }
    }
}

enum XTMemoryServingProfile: String, CaseIterable, Sendable {
    case m0Heartbeat = "m0_heartbeat"
    case m1Execute = "m1_execute"
    case m2PlanReview = "m2_plan_review"
    case m3DeepDive = "m3_deep_dive"
    case m4FullScan = "m4_full_scan"

    var rank: Int {
        switch self {
        case .m0Heartbeat:
            return 0
        case .m1Execute:
            return 1
        case .m2PlanReview:
            return 2
        case .m3DeepDive:
            return 3
        case .m4FullScan:
            return 4
        }
    }

    static func parse(_ raw: String?) -> XTMemoryServingProfile? {
        let token = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !token.isEmpty else { return nil }
        if let profile = XTMemoryServingProfile(rawValue: token) {
            return profile
        }
        switch token {
        case "m0", "heartbeat":
            return .m0Heartbeat
        case "m1", "execute", "default":
            return .m1Execute
        case "m2", "plan_review", "planreview", "review":
            return .m2PlanReview
        case "m3", "deep_dive", "deepdive":
            return .m3DeepDive
        case "m4", "full_scan", "fullscan":
            return .m4FullScan
        default:
            return nil
        }
    }
}

struct XTMemoryServingProfileContract: Sendable {
    var budgetScale: Double
    var maxTotalTokens: Int
    var constitutionScale: Double
    var canonicalScale: Double
    var observationsScale: Double
    var workingSetScale: Double
    var rawEvidenceScale: Double
    var lineScale: Double
}

struct XTMemoryUseContract: Sendable {
    var mode: XTMemoryUseMode
    var allowedRequesterRoles: Set<XTMemoryRequesterRole>
    var allowedLayers: Set<XTMemoryLayer>
    var freshnessPolicy: XTMemoryFreshnessPolicy
    var userMemoryPolicy: XTMemoryUserMemoryPolicy
    var longtermPolicy: XTMemoryLongtermPolicy
    var remoteExportPolicy: XTMemoryRemoteExportPolicy
    var constitutionMaxChars: Int
    var canonicalMaxChars: Int
    var observationsMaxChars: Int
    var workingSetMaxChars: Int
    var rawEvidenceMaxChars: Int
    var lineCap: Int
    var budgetCap: HubIPCClient.MemoryContextBudgets?
    var directUseDenyCode: XTMemoryUseDenyCode?

    var bypassRemoteCache: Bool {
        freshnessPolicy == .requireFreshRemoteSnapshot
    }
}

struct XTMemoryRouteDecision: Sendable {
    var contract: XTMemoryUseContract
    var servingProfile: XTMemoryServingProfile
    var payload: HubIPCClient.MemoryContextPayload
    var denyCode: XTMemoryUseDenyCode?
    var downgradeCode: XTMemoryUseDenyCode?
    var bypassRemoteCache: Bool
}

enum XTMemoryRoleScopedRouter {
    static func route(
        role: XTMemoryRequesterRole,
        mode: XTMemoryUseMode,
        payload: HubIPCClient.MemoryContextPayload,
        remoteExportRequested: Bool = false
    ) -> XTMemoryRouteDecision {
        let selectedProfile = resolveServingProfile(
            role: role,
            mode: mode,
            payload: payload
        )
        let contract = adjustedContract(
            contract(for: mode),
            for: mode,
            servingProfile: selectedProfile
        )

        if let directUseDenyCode = contract.directUseDenyCode {
            return XTMemoryRouteDecision(
                contract: contract,
                servingProfile: selectedProfile,
                payload: payload,
                denyCode: directUseDenyCode,
                downgradeCode: nil,
                bypassRemoteCache: contract.bypassRemoteCache
            )
        }

        guard contract.allowedRequesterRoles.contains(role) else {
            return XTMemoryRouteDecision(
                contract: contract,
                servingProfile: selectedProfile,
                payload: payload,
                denyCode: .memoryRoutePolicyMismatch,
                downgradeCode: nil,
                bypassRemoteCache: contract.bypassRemoteCache
            )
        }

        if remoteExportRequested, contract.remoteExportPolicy == .localOnly {
            return XTMemoryRouteDecision(
                contract: contract,
                servingProfile: selectedProfile,
                payload: payload,
                denyCode: .rawEvidenceRemoteExportDenied,
                downgradeCode: nil,
                bypassRemoteCache: contract.bypassRemoteCache
            )
        }

        var sanitized = payload
        sanitized.mode = mode.rawValue
        sanitized.servingProfile = selectedProfile.rawValue
        sanitized.constitutionHint = allowed(contract.allowedLayers, .l0Constitution)
            ? XTMemorySanitizer.sanitizeText(
                payload.constitutionHint,
                maxChars: contract.constitutionMaxChars,
                lineCap: contract.lineCap
            )
            : nil
        sanitized.canonicalText = allowed(contract.allowedLayers, .l1Canonical)
            ? XTMemorySanitizer.sanitizeText(
                payload.canonicalText,
                maxChars: contract.canonicalMaxChars,
                lineCap: contract.lineCap
            )
            : nil
        sanitized.observationsText = allowed(contract.allowedLayers, .l2Observations)
            ? XTMemorySanitizer.sanitizeText(
                payload.observationsText,
                maxChars: contract.observationsMaxChars,
                lineCap: contract.lineCap
            )
            : nil
        sanitized.workingSetText = allowed(contract.allowedLayers, .l3WorkingSet)
            ? XTMemorySanitizer.sanitizeText(
                payload.workingSetText,
                maxChars: contract.workingSetMaxChars,
                lineCap: contract.lineCap
            )
            : nil
        sanitized.rawEvidenceText = allowed(contract.allowedLayers, .l4RawEvidence) && contract.rawEvidenceMaxChars > 0
            ? XTMemorySanitizer.sanitizeRawEvidenceSummary(
                payload.rawEvidenceText,
                maxChars: contract.rawEvidenceMaxChars,
                lineCap: contract.lineCap
            )
            : nil
        sanitized.latestUser = XTMemorySanitizer.sanitizeText(
            payload.latestUser,
            maxChars: 400,
            lineCap: 10
        ) ?? "(none)"
        sanitized.budgets = cappedBudgets(payload.budgets, cap: contract.budgetCap)

        return XTMemoryRouteDecision(
            contract: contract,
            servingProfile: selectedProfile,
            payload: sanitized,
            denyCode: nil,
            downgradeCode: nil,
            bypassRemoteCache: contract.bypassRemoteCache
        )
    }

    static func contract(for mode: XTMemoryUseMode) -> XTMemoryUseContract {
        switch mode {
        case .projectChat:
            return XTMemoryUseContract(
                mode: mode,
                allowedRequesterRoles: [.chat, .tool],
                allowedLayers: [.l0Constitution, .l1Canonical, .l2Observations, .l3WorkingSet, .l4RawEvidence],
                freshnessPolicy: .allowShortTTLCache,
                userMemoryPolicy: .defaultOff,
                longtermPolicy: .summaryOnly,
                remoteExportPolicy: .localOnly,
                constitutionMaxChars: 300,
                canonicalMaxChars: 3_200,
                observationsMaxChars: 1_800,
                workingSetMaxChars: 2_600,
                rawEvidenceMaxChars: 1_100,
                lineCap: 28,
                budgetCap: nil,
                directUseDenyCode: nil
            )
        case .sessionResume:
            return XTMemoryUseContract(
                mode: mode,
                allowedRequesterRoles: [.session, .tool],
                allowedLayers: [.l0Constitution, .l1Canonical, .l2Observations, .l3WorkingSet],
                freshnessPolicy: .allowShortTTLCache,
                userMemoryPolicy: .defaultOff,
                longtermPolicy: .summaryOnly,
                remoteExportPolicy: .localOnly,
                constitutionMaxChars: 240,
                canonicalMaxChars: 2_400,
                observationsMaxChars: 1_000,
                workingSetMaxChars: 1_600,
                rawEvidenceMaxChars: 0,
                lineCap: 20,
                budgetCap: HubIPCClient.MemoryContextBudgets(
                    totalTokens: 1_200,
                    l0Tokens: 70,
                    l1Tokens: 420,
                    l2Tokens: 180,
                    l3Tokens: 530,
                    l4Tokens: 60
                ),
                directUseDenyCode: nil
            )
        case .supervisorOrchestration:
            return XTMemoryUseContract(
                mode: mode,
                allowedRequesterRoles: [.supervisor, .tool],
                allowedLayers: [.l0Constitution, .l1Canonical, .l2Observations, .l3WorkingSet],
                freshnessPolicy: .allowShortTTLCache,
                userMemoryPolicy: .denied,
                longtermPolicy: .summaryOnly,
                remoteExportPolicy: .localOnly,
                constitutionMaxChars: 280,
                canonicalMaxChars: 2_200,
                observationsMaxChars: 1_400,
                workingSetMaxChars: 1_400,
                rawEvidenceMaxChars: 0,
                lineCap: 22,
                budgetCap: HubIPCClient.MemoryContextBudgets(
                    totalTokens: 1_300,
                    l0Tokens: 80,
                    l1Tokens: 420,
                    l2Tokens: 240,
                    l3Tokens: 500,
                    l4Tokens: 60
                ),
                directUseDenyCode: nil
            )
        case .toolPlan:
            return XTMemoryUseContract(
                mode: mode,
                allowedRequesterRoles: [.tool],
                allowedLayers: [.l0Constitution, .l1Canonical, .l2Observations, .l3WorkingSet, .l4RawEvidence],
                freshnessPolicy: .allowShortTTLCache,
                userMemoryPolicy: .defaultOff,
                longtermPolicy: .summaryOnly,
                remoteExportPolicy: .localOnly,
                constitutionMaxChars: 240,
                canonicalMaxChars: 2_400,
                observationsMaxChars: 1_400,
                workingSetMaxChars: 1_800,
                rawEvidenceMaxChars: 700,
                lineCap: 20,
                budgetCap: HubIPCClient.MemoryContextBudgets(
                    totalTokens: 1_300,
                    l0Tokens: 70,
                    l1Tokens: 430,
                    l2Tokens: 210,
                    l3Tokens: 450,
                    l4Tokens: 140
                ),
                directUseDenyCode: nil
            )
        case .toolActLowRisk:
            return XTMemoryUseContract(
                mode: mode,
                allowedRequesterRoles: [.tool],
                allowedLayers: [.l0Constitution, .l1Canonical, .l2Observations, .l3WorkingSet, .l4RawEvidence],
                freshnessPolicy: .allowShortTTLCache,
                userMemoryPolicy: .defaultOff,
                longtermPolicy: .summaryOnly,
                remoteExportPolicy: .localOnly,
                constitutionMaxChars: 220,
                canonicalMaxChars: 2_000,
                observationsMaxChars: 1_200,
                workingSetMaxChars: 1_300,
                rawEvidenceMaxChars: 500,
                lineCap: 18,
                budgetCap: HubIPCClient.MemoryContextBudgets(
                    totalTokens: 1_100,
                    l0Tokens: 70,
                    l1Tokens: 360,
                    l2Tokens: 180,
                    l3Tokens: 350,
                    l4Tokens: 140
                ),
                directUseDenyCode: nil
            )
        case .toolActHighRisk:
            return XTMemoryUseContract(
                mode: mode,
                allowedRequesterRoles: [.tool],
                allowedLayers: [.l0Constitution, .l1Canonical, .l2Observations, .l3WorkingSet],
                freshnessPolicy: .requireFreshRemoteSnapshot,
                userMemoryPolicy: .defaultOff,
                longtermPolicy: .summaryOnly,
                remoteExportPolicy: .localOnly,
                constitutionMaxChars: 220,
                canonicalMaxChars: 1_800,
                observationsMaxChars: 900,
                workingSetMaxChars: 900,
                rawEvidenceMaxChars: 0,
                lineCap: 14,
                budgetCap: HubIPCClient.MemoryContextBudgets(
                    totalTokens: 950,
                    l0Tokens: 70,
                    l1Tokens: 340,
                    l2Tokens: 180,
                    l3Tokens: 300,
                    l4Tokens: 60
                ),
                directUseDenyCode: nil
            )
        case .laneHandoff:
            return XTMemoryUseContract(
                mode: mode,
                allowedRequesterRoles: [.lane],
                allowedLayers: [],
                freshnessPolicy: .refsOnly,
                userMemoryPolicy: .denied,
                longtermPolicy: .denied,
                remoteExportPolicy: .refsOnly,
                constitutionMaxChars: 0,
                canonicalMaxChars: 0,
                observationsMaxChars: 0,
                workingSetMaxChars: 0,
                rawEvidenceMaxChars: 0,
                lineCap: 0,
                budgetCap: nil,
                directUseDenyCode: .laneHandoffFulltextDenied
            )
        case .remotePromptBundle:
            return XTMemoryUseContract(
                mode: mode,
                allowedRequesterRoles: [.remoteExport],
                allowedLayers: [.l0Constitution, .l1Canonical, .l2Observations, .l3WorkingSet],
                freshnessPolicy: .allowShortTTLCache,
                userMemoryPolicy: .defaultOff,
                longtermPolicy: .summaryOnly,
                remoteExportPolicy: .sanitizedOnly,
                constitutionMaxChars: 180,
                canonicalMaxChars: 1_400,
                observationsMaxChars: 900,
                workingSetMaxChars: 900,
                rawEvidenceMaxChars: 0,
                lineCap: 12,
                budgetCap: HubIPCClient.MemoryContextBudgets(
                    totalTokens: 900,
                    l0Tokens: 70,
                    l1Tokens: 300,
                    l2Tokens: 160,
                    l3Tokens: 310,
                    l4Tokens: 60
                ),
                directUseDenyCode: nil
            )
        }
    }

    private static func allowed(_ layers: Set<XTMemoryLayer>, _ layer: XTMemoryLayer) -> Bool {
        layers.contains(layer)
    }

    private static func resolveServingProfile(
        role: XTMemoryRequesterRole,
        mode: XTMemoryUseMode,
        payload: HubIPCClient.MemoryContextPayload
    ) -> XTMemoryServingProfile {
        let explicit = XTMemoryServingProfile.parse(payload.servingProfile)
        let inferred = explicit ?? defaultServingProfile(
            role: role,
            mode: mode,
            latestUser: payload.latestUser
        )
        return clampedServingProfile(inferred, for: mode)
    }

    private static func defaultServingProfile(
        role: XTMemoryRequesterRole,
        mode: XTMemoryUseMode,
        latestUser: String
    ) -> XTMemoryServingProfile {
        switch mode {
        case .laneHandoff:
            return .m0Heartbeat
        case .remotePromptBundle:
            return reviewPlanRequestSignals(latestUser) ? .m1Execute : .m0Heartbeat
        case .supervisorOrchestration:
            if fullScanRequestSignals(latestUser) {
                return .m3DeepDive
            }
            if reviewPlanRequestSignals(latestUser) {
                return .m2PlanReview
            }
            return .m1Execute
        case .toolActHighRisk:
            if reviewPlanRequestSignals(latestUser) {
                return .m2PlanReview
            }
            return .m1Execute
        default:
            if fullScanRequestSignals(latestUser) && role != .remoteExport {
                return .m3DeepDive
            }
            if reviewPlanRequestSignals(latestUser) {
                return .m2PlanReview
            }
            return .m1Execute
        }
    }

    private static func clampedServingProfile(
        _ profile: XTMemoryServingProfile,
        for mode: XTMemoryUseMode
    ) -> XTMemoryServingProfile {
        switch mode {
        case .laneHandoff:
            return .m0Heartbeat
        case .remotePromptBundle:
            return profile.rank > XTMemoryServingProfile.m1Execute.rank ? .m1Execute : profile
        case .toolActHighRisk:
            return profile.rank > XTMemoryServingProfile.m2PlanReview.rank ? .m2PlanReview : profile
        default:
            return profile
        }
    }

    private static func adjustedContract(
        _ contract: XTMemoryUseContract,
        for mode: XTMemoryUseMode,
        servingProfile: XTMemoryServingProfile
    ) -> XTMemoryUseContract {
        let profile = servingProfileContract(for: servingProfile)
        var adjusted = contract
        adjusted.constitutionMaxChars = scaledPositive(
            contract.constitutionMaxChars,
            scale: profile.constitutionScale,
            floor: contract.constitutionMaxChars > 0 ? min(120, contract.constitutionMaxChars) : 0
        )
        adjusted.canonicalMaxChars = scaledPositive(
            contract.canonicalMaxChars,
            scale: profile.canonicalScale,
            floor: contract.canonicalMaxChars > 0 ? min(400, contract.canonicalMaxChars) : 0
        )
        adjusted.observationsMaxChars = scaledPositive(
            contract.observationsMaxChars,
            scale: profile.observationsScale,
            floor: contract.observationsMaxChars > 0 ? min(320, contract.observationsMaxChars) : 0
        )
        adjusted.workingSetMaxChars = scaledPositive(
            contract.workingSetMaxChars,
            scale: profile.workingSetScale,
            floor: contract.workingSetMaxChars > 0 ? min(320, contract.workingSetMaxChars) : 0
        )
        adjusted.rawEvidenceMaxChars = scaledPositive(
            contract.rawEvidenceMaxChars,
            scale: profile.rawEvidenceScale,
            floor: contract.rawEvidenceMaxChars > 0 ? min(180, contract.rawEvidenceMaxChars) : 0
        )
        adjusted.lineCap = scaledPositive(
            contract.lineCap,
            scale: profile.lineScale,
            floor: contract.lineCap > 0 ? min(8, contract.lineCap) : 0
        )
        adjusted.budgetCap = scaledBudgetCap(
            baseBudgetCap(for: mode, contract: contract),
            scale: profile.budgetScale,
            maxTotalTokens: profile.maxTotalTokens
        )
        return adjusted
    }

    private static func servingProfileContract(
        for profile: XTMemoryServingProfile
    ) -> XTMemoryServingProfileContract {
        switch profile {
        case .m0Heartbeat:
            return XTMemoryServingProfileContract(
                budgetScale: 0.6,
                maxTotalTokens: 1_200,
                constitutionScale: 0.8,
                canonicalScale: 0.7,
                observationsScale: 0.65,
                workingSetScale: 0.7,
                rawEvidenceScale: 0.5,
                lineScale: 0.7
            )
        case .m1Execute:
            return XTMemoryServingProfileContract(
                budgetScale: 1.0,
                maxTotalTokens: 1_800,
                constitutionScale: 1.0,
                canonicalScale: 1.0,
                observationsScale: 1.0,
                workingSetScale: 1.0,
                rawEvidenceScale: 1.0,
                lineScale: 1.0
            )
        case .m2PlanReview:
            return XTMemoryServingProfileContract(
                budgetScale: 1.8,
                maxTotalTokens: 3_600,
                constitutionScale: 1.1,
                canonicalScale: 1.8,
                observationsScale: 1.9,
                workingSetScale: 1.7,
                rawEvidenceScale: 1.5,
                lineScale: 1.45
            )
        case .m3DeepDive:
            return XTMemoryServingProfileContract(
                budgetScale: 2.8,
                maxTotalTokens: 6_400,
                constitutionScale: 1.2,
                canonicalScale: 2.7,
                observationsScale: 3.0,
                workingSetScale: 2.5,
                rawEvidenceScale: 2.2,
                lineScale: 1.9
            )
        case .m4FullScan:
            return XTMemoryServingProfileContract(
                budgetScale: 4.0,
                maxTotalTokens: 12_000,
                constitutionScale: 1.3,
                canonicalScale: 3.4,
                observationsScale: 3.8,
                workingSetScale: 3.2,
                rawEvidenceScale: 2.8,
                lineScale: 2.4
            )
        }
    }

    private static func baseBudgetCap(
        for mode: XTMemoryUseMode,
        contract: XTMemoryUseContract
    ) -> HubIPCClient.MemoryContextBudgets {
        if let budget = contract.budgetCap {
            return budget
        }
        switch mode {
        case .projectChat:
            return HubIPCClient.MemoryContextBudgets(
                totalTokens: 1_600,
                l0Tokens: 80,
                l1Tokens: 480,
                l2Tokens: 320,
                l3Tokens: 520,
                l4Tokens: 200
            )
        case .laneHandoff:
            return HubIPCClient.MemoryContextBudgets(
                totalTokens: 400,
                l0Tokens: 40,
                l1Tokens: 120,
                l2Tokens: 80,
                l3Tokens: 120,
                l4Tokens: 40
            )
        default:
            return HubIPCClient.MemoryContextBudgets(
                totalTokens: 1_300,
                l0Tokens: 70,
                l1Tokens: 420,
                l2Tokens: 240,
                l3Tokens: 510,
                l4Tokens: 60
            )
        }
    }

    private static func scaledBudgetCap(
        _ base: HubIPCClient.MemoryContextBudgets,
        scale: Double,
        maxTotalTokens: Int
    ) -> HubIPCClient.MemoryContextBudgets {
        let l0 = scaledPositive(base.l0Tokens ?? 0, scale: scale, floor: 24)
        let l1 = scaledPositive(base.l1Tokens ?? 0, scale: scale, floor: 40)
        let l2 = scaledPositive(base.l2Tokens ?? 0, scale: scale, floor: 40)
        let l3 = scaledPositive(base.l3Tokens ?? 0, scale: scale, floor: 80)
        let l4 = scaledPositive(base.l4Tokens ?? 0, scale: scale, floor: 60)
        let scaledTotal = scaledPositive(base.totalTokens ?? 0, scale: scale, floor: 400)
        let sum = l0 + l1 + l2 + l3 + l4
        let total = min(maxTotalTokens, max(scaledTotal, sum))
        return HubIPCClient.MemoryContextBudgets(
            totalTokens: total,
            l0Tokens: l0,
            l1Tokens: l1,
            l2Tokens: l2,
            l3Tokens: l3,
            l4Tokens: l4
        )
    }

    private static func scaledPositive(
        _ value: Int,
        scale: Double,
        floor: Int
    ) -> Int {
        guard value > 0 else { return 0 }
        return max(floor, Int((Double(value) * scale).rounded()))
    }

    private static func reviewPlanRequestSignals(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        let keywords = [
            "审查", "审阅", "review", "上下文记忆", "项目记忆", "执行方案",
            "重构建议", "方案评审", "规划", "计划", "梳理", "全貌", "背景信息",
            "设计建议", "refactor", "architecture review", "planning", "deep dive"
        ]
        return keywords.contains { normalized.contains($0) }
    }

    private static func fullScanRequestSignals(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        let keywords = [
            "全局", "全仓", "仓库级", "整个仓库", "完整上下文", "全部背景",
            "全量背景", "portfolio", "repo-wide", "full scan", "system-wide",
            "全面审查", "全面评审", "从全局看", "完整背景", "通读"
        ]
        return keywords.contains { normalized.contains($0) }
    }

    private static func cappedBudgets(
        _ explicit: HubIPCClient.MemoryContextBudgets?,
        cap: HubIPCClient.MemoryContextBudgets?
    ) -> HubIPCClient.MemoryContextBudgets? {
        guard let cap else {
            return explicit
        }

        let base = explicit ?? cap
        return HubIPCClient.MemoryContextBudgets(
            totalTokens: minPositive(base.totalTokens, cap.totalTokens),
            l0Tokens: minPositive(base.l0Tokens, cap.l0Tokens),
            l1Tokens: minPositive(base.l1Tokens, cap.l1Tokens),
            l2Tokens: minPositive(base.l2Tokens, cap.l2Tokens),
            l3Tokens: minPositive(base.l3Tokens, cap.l3Tokens),
            l4Tokens: minPositive(base.l4Tokens, cap.l4Tokens)
        )
    }

    private static func minPositive(_ lhs: Int?, _ rhs: Int?) -> Int? {
        switch (lhs, rhs) {
        case let (l?, r?):
            return max(1, min(l, r))
        case let (l?, nil):
            return max(1, l)
        case let (nil, r?):
            return max(1, r)
        case (nil, nil):
            return nil
        }
    }
}

enum XTMemorySanitizer {
    static func sanitizeText(_ raw: String?, maxChars: Int, lineCap: Int) -> String? {
        guard maxChars > 0, lineCap > 0 else { return nil }
        let normalized = normalize(raw)
        guard !normalized.isEmpty else { return nil }
        let redacted = redactSecrets(in: normalized)
        let bounded = limitLines(redacted, maxLines: lineCap)
        return capText(bounded, maxChars: maxChars)
    }

    static func sanitizeRawEvidenceSummary(_ raw: String?, maxChars: Int, lineCap: Int) -> String? {
        guard maxChars > 0, lineCap > 0 else { return nil }
        let normalized = normalize(raw)
        guard !normalized.isEmpty else { return nil }

        let redacted = redactSecrets(in: normalized)
        let rawLines = redacted.split(separator: "\n", omittingEmptySubsequences: false)
        var sanitized: [String] = []
        sanitized.reserveCapacity(min(lineCap, rawLines.count))
        var droppedBlob = false

        for rawLine in rawLines {
            if sanitized.count >= lineCap { break }
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let lower = line.lowercased()
            if lower.hasPrefix("<!doctype") || lower.hasPrefix("<html") || lower.hasPrefix("<body") ||
                lower.contains("</html") || lower.contains("<script") || lower.contains("<style") {
                droppedBlob = true
                continue
            }
            if lower.hasPrefix("authorization:") || lower.hasPrefix("cookie:") || lower.hasPrefix("set-cookie:") {
                sanitized.append("[redacted_sensitive_header]")
                continue
            }
            if lower.hasPrefix("from:") || lower.hasPrefix("to:") || lower.hasPrefix("cc:") ||
                lower.hasPrefix("bcc:") || lower.hasPrefix("reply-to:") || lower.hasPrefix("delivered-to:") {
                sanitized.append("[redacted_message_header]")
                continue
            }
            if line.count > 260 && !line.contains(" ") {
                droppedBlob = true
                continue
            }
            sanitized.append(capText(line, maxChars: 220))
        }

        if sanitized.isEmpty {
            sanitized.append("[sanitized_raw_evidence_omitted]")
        } else if droppedBlob {
            sanitized.append("[sanitized_raw_evidence_truncated]")
        }

        return capText(sanitized.joined(separator: "\n"), maxChars: maxChars)
    }

    private static func normalize(_ raw: String?) -> String {
        (raw ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func limitLines(_ text: String, maxLines: Int) -> String {
        guard maxLines > 0 else { return "" }
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if lines.count <= maxLines {
            return lines.joined(separator: "\n")
        }
        return lines.prefix(maxLines).joined(separator: "\n") + "\n[sanitized_truncated]"
    }

    private static func capText(_ text: String, maxChars: Int) -> String {
        guard maxChars > 0 else { return "" }
        guard text.count > maxChars else { return text }
        let idx = text.index(text.startIndex, offsetBy: maxChars)
        return String(text[..<idx]) + "…"
    }

    private static func redactSecrets(in input: String) -> String {
        var text = input
        let replacements: [(String, String)] = [
            ("(?is)<private\\b[^>]*>.*?</private\\s*>", "[private omitted]"),
            ("(?i)</?private\\b[^>]*>", "[private omitted]"),
            ("(?is)-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?-----END [A-Z0-9 ]*PRIVATE KEY-----", "[redacted_private_key]"),
            ("sk-[A-Za-z0-9]{20,}", "[redacted_api_key]"),
            ("sk-ant-[A-Za-z0-9_-]{20,}", "[redacted_api_key]"),
            ("gh[pousr]_[A-Za-z0-9]{20,}", "[redacted_token]"),
            ("eyJ[A-Za-z0-9_-]{6,}\\.[A-Za-z0-9_-]{6,}\\.[A-Za-z0-9_-]{6,}", "[redacted_jwt]"),
            ("(?i)bearer\\s+[A-Za-z0-9._-]{16,}", "Bearer [redacted_token]"),
            ("(?i)(password|passwd|pwd|api[_-]?key|secret)\\s*[:=]\\s*[^\\s,;]{4,}", "$1=[redacted]")
        ]
        for (pattern, replacement) in replacements {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
        }
        return text
    }
}
