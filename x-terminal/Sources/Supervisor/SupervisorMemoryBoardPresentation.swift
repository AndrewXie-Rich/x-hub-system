import Foundation

struct SupervisorMemoryFollowUpPresentation: Equatable {
    var iconName: String
    var tone: SupervisorHeaderControlTone
    var title: String
    var questionText: String
    var hintText: String
}

struct SupervisorMemoryIssuePresentation: Equatable, Identifiable {
    var id: String
    var severityText: String
    var severityTone: SupervisorHeaderControlTone
    var summary: String
    var detail: String
}

struct SupervisorMemorySkillRegistryRowPresentation: Equatable, Identifiable {
    var id: String
    var displayName: String
    var skillId: String
    var badgeText: String
    var badgeTone: SupervisorHeaderControlTone
    var metadataText: String
    var routingHintText: String?
    var descriptionText: String?
}

struct SupervisorMemoryDigestRowPresentation: Equatable, Identifiable {
    var id: String
    var displayName: String
    var runtimeState: String
    var recentText: String
    var updatedText: String
    var sourceText: String
    var goalText: String
    var nextText: String
    var blockerText: String?
}

struct SupervisorMemoryAfterTurnPresentation: Equatable {
    var iconName: String
    var tone: SupervisorHeaderControlTone
    var title: String
    var statusLine: String
    var detailLines: [String]
}

struct SupervisorTurnMemoryExplainabilityPresentation: Equatable {
    var iconName: String
    var tone: SupervisorHeaderControlTone
    var title: String
    var statusLine: String
    var detailLines: [String]
}

struct SupervisorTaskRouteExplainabilityPresentation: Equatable {
    var iconName: String
    var tone: SupervisorHeaderControlTone
    var title: String
    var statusLine: String
    var detailLines: [String]
}

struct SupervisorMemoryBoardPresentation: Equatable {
    var iconName: String
    var iconTone: SupervisorHeaderControlTone
    var title: String
    var statusLine: String
    var modeSourceText: String
    var continuityStatusLine: String
    var continuityDetailLine: String?
    var continuityDrillDownLines: [String]
    var turnExplainability: SupervisorTurnMemoryExplainabilityPresentation?
    var modelRoute: SupervisorTaskRouteExplainabilityPresentation?
    var afterTurn: SupervisorMemoryAfterTurnPresentation?
    var readinessIconName: String
    var readinessTone: SupervisorHeaderControlTone
    var readinessHeadline: String
    var readinessStatusLine: String
    var assemblyStatusLine: String
    var followUp: SupervisorMemoryFollowUpPresentation?
    var assemblyDetailLine: String?
    var issueSectionTitle: String?
    var issues: [SupervisorMemoryIssuePresentation]
    var skillRegistryStatusLine: String
    var skillRegistrySectionTitle: String?
    var skillRegistryRows: [SupervisorMemorySkillRegistryRowPresentation]
    var emptyStateText: String?
    var digestRows: [SupervisorMemoryDigestRowPresentation]
    var previewExcerpt: String?

    var isEmpty: Bool {
        digestRows.isEmpty
    }
}

enum SupervisorMemoryBoardPresentationMapper {
    static func map(
        statusLine: String,
        memorySource: String,
        replyExecutionMode: String,
        requestedModelId: String,
        actualModelId: String,
        failureReasonCode: String,
        readiness: SupervisorMemoryAssemblyReadiness,
        rawAssemblyStatusLine: String,
        afterTurnSummary: SupervisorManager.SupervisorAfterTurnDerivedSummary?,
        pendingFollowUpQuestion: String,
        assemblySnapshot: SupervisorMemoryAssemblySnapshot?,
        skillRegistryStatusLine: String,
        skillRegistrySnapshot: SupervisorSkillRegistrySnapshot?,
        turnRoutingDecision: SupervisorTurnRoutingDecision? = nil,
        turnContextAssembly: SupervisorTurnContextAssemblyResult? = nil,
        writebackClassification: SupervisorAfterTurnWritebackClassification? = nil,
        modelRouteContext: SupervisorModelRouteContext? = nil,
        digests: [SupervisorManager.SupervisorMemoryProjectDigest],
        preview: String,
        mode: XTMemoryUseMode = .supervisorOrchestration,
        maxIssueRows: Int = 3,
        maxSkillRows: Int = 4,
        maxDigestRows: Int = 8,
        previewLimit: Int = 800
    ) -> SupervisorMemoryBoardPresentation {
        let trimmedQuestion = normalizedScalar(pendingFollowUpQuestion)
        let registryItems = skillRegistrySnapshot?.items ?? []
        let registryRows = Array(registryItems.prefix(maxSkillRows)).map {
            skillRegistryRow($0, registryItems: registryItems)
        }
        let digestRows = Array(digests.prefix(maxDigestRows)).map(digestRow)
        let continuitySummaryLine = continuityStatusLine(
            replyExecutionMode: replyExecutionMode
        )
        let continuitySummaryDetailLine = continuityDetailLine(
            memorySource: memorySource,
            replyExecutionMode: replyExecutionMode,
            requestedModelId: requestedModelId,
            actualModelId: actualModelId,
            failureReasonCode: failureReasonCode,
            assemblySnapshot: assemblySnapshot
        )
        let continuityDrillDownDetailLines = continuityDrillDownLines(
            assemblySnapshot: assemblySnapshot,
            failureReasonCode: failureReasonCode
        )

        return SupervisorMemoryBoardPresentation(
            iconName: digests.isEmpty ? "memorychip" : "internaldrive.fill",
            iconTone: digests.isEmpty ? .neutral : .accent,
            title: "Supervisor 记忆",
            statusLine: boardStatusLine(
                rawStatusLine: statusLine,
                memorySource: memorySource,
                projectCount: digestRows.count
            ),
            modeSourceText: "当前记忆来源：\(memorySourceLabel(memorySource)) · 用途：\(memoryUseModeLabel(mode))",
            continuityStatusLine: continuitySummaryLine,
            continuityDetailLine: continuitySummaryDetailLine,
            continuityDrillDownLines: continuityDrillDownDetailLines,
            turnExplainability: turnExplainabilityPresentation(
                decision: turnRoutingDecision,
                assembly: turnContextAssembly,
                writeback: writebackClassification
            ),
            modelRoute: modelRoutePresentation(modelRouteContext),
            afterTurn: afterTurnPresentation(afterTurnSummary),
            readinessIconName: readinessIconName(readiness),
            readinessTone: readinessTone(readiness),
            readinessHeadline: readinessHeadline(readiness),
            readinessStatusLine: readinessStatusLine(readiness),
            assemblyStatusLine: assemblyStatusLine(
                rawAssemblyStatusLine,
                snapshot: assemblySnapshot
            ),
            followUp: trimmedQuestion.isEmpty
                ? nil
                : SupervisorMemoryFollowUpPresentation(
                    iconName: "text.bubble.fill",
                    tone: .warning,
                    title: "待补背景",
                    questionText: "还缺这项项目背景：\(trimmedQuestion)",
                    hintText: "你可以直接继续说事实，我会接着补进项目记忆。"
                ),
            assemblyDetailLine: assemblyDetailLine(assemblySnapshot),
            issueSectionTitle: readiness.issues.isEmpty ? nil : "需要补的背景",
            issues: Array(readiness.issues.prefix(maxIssueRows)).map(issueRow),
            skillRegistryStatusLine: skillRegistryStatusLine,
            skillRegistrySectionTitle: registryRows.isEmpty ? nil : "当前项目技能表",
            skillRegistryRows: registryRows,
            emptyStateText: digestRows.isEmpty
                ? "当前还没有可展示的项目记忆摘要。创建项目或等待系统完成第一次记忆同步后，这里会显示项目总览。"
                : nil,
            digestRows: digestRows,
            previewExcerpt: previewExcerpt(preview, maxChars: previewLimit)
        )
    }

    static func readinessIconName(
        _ readiness: SupervisorMemoryAssemblyReadiness
    ) -> String {
        if readiness.ready { return "checkmark.seal.fill" }
        if readiness.blockingCount > 0 { return "exclamationmark.triangle.fill" }
        return "exclamationmark.circle.fill"
    }

    static func readinessTone(
        _ readiness: SupervisorMemoryAssemblyReadiness
    ) -> SupervisorHeaderControlTone {
        if readiness.ready { return .success }
        if readiness.blockingCount > 0 { return .danger }
        return .warning
    }

    static func readinessHeadline(
        _ readiness: SupervisorMemoryAssemblyReadiness
    ) -> String {
        if readiness.ready {
            return "战略复盘记忆已就绪"
        }
        return "战略复盘记忆还差 \(readiness.issues.count) 项"
    }

    static func continuityStatusLine(
        replyExecutionMode: String
    ) -> String {
        switch normalizedScalar(replyExecutionMode) {
        case "remote_model":
            return "本轮已接上连续对话与背景记忆"
        case "local_fallback_after_remote_error":
            return "远端失败后，已带着记忆回退到本地回复"
        case "local_preflight":
            return "本轮先走本地预检，暂未送进主模型"
        case "local_direct_reply":
            return "本轮走本地直答，没有调用远端模型"
        case "local_direct_action":
            return "本轮走本地动作执行，没有调用远端模型"
        case "hub_brief_projection":
            return "当前展示的是 Hub 侧同步过来的摘要视图"
        default:
            return "当前没有新的连续对话装配"
        }
    }

    static func continuityDetailLine(
        memorySource: String,
        replyExecutionMode: String,
        requestedModelId: String,
        actualModelId: String,
        failureReasonCode: String,
        assemblySnapshot: SupervisorMemoryAssemblySnapshot?
    ) -> String? {
        let mode = normalizedScalar(replyExecutionMode)
        let memoryUsedThisTurn = mode == "remote_model" || mode == "local_fallback_after_remote_error"
        let failure = normalizedScalar(failureReasonCode)
        var parts: [String] = []

        if memoryUsedThisTurn {
            parts.append("本轮从\(memorySourceLabel(memorySource))带入连续对话与背景记忆。")
            if let snapshot = assemblySnapshot {
                let floorText = snapshot.continuityFloorSatisfied
                    ? "已满足至少 \(snapshot.rawWindowFloorPairs) 组的连续性底线"
                    : "还未达到至少 \(snapshot.rawWindowFloorPairs) 组的连续性底线"
                parts.append(
                    "最近原始对话保留 \(snapshot.rawWindowSelectedPairs) 组，\(floorText)，背景深度为 \(profileLabel(snapshot.resolvedProfile))."
                )
            }
        } else {
            parts.append("这一轮没有把连续对话记忆送进主模型。")
            if let snapshot = assemblySnapshot {
                parts.append("最近一次成功装配的背景深度是 \(profileLabel(snapshot.resolvedProfile)).")
            }
        }

        if !failure.isEmpty {
            parts.append("异常原因：\(failureReasonLabel(failure)).")
        } else if !normalizedScalar(requestedModelId).isEmpty,
                  !normalizedScalar(actualModelId).isEmpty,
                  normalizedScalar(requestedModelId) != normalizedScalar(actualModelId) {
            parts.append("本轮实际运行模型与请求模型不同，系统已自动切到可用模型。")
        }

        let merged = parts
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return merged.isEmpty ? nil : merged
    }

    static func afterTurnPresentation(
        _ summary: SupervisorManager.SupervisorAfterTurnDerivedSummary?
    ) -> SupervisorMemoryAfterTurnPresentation? {
        guard let summary else { return nil }
        return SupervisorMemoryAfterTurnPresentation(
            iconName: afterTurnIconName(summary),
            tone: afterTurnTone(summary),
            title: "回合后整理",
            statusLine: summary.statusLine,
            detailLines: summary.detailLines
        )
    }

    static func turnExplainabilityPresentation(
        decision: SupervisorTurnRoutingDecision?,
        assembly: SupervisorTurnContextAssemblyResult?,
        writeback: SupervisorAfterTurnWritebackClassification?
    ) -> SupervisorTurnMemoryExplainabilityPresentation? {
        guard decision != nil || assembly != nil || writeback != nil else { return nil }

        let primaryDomain = decision?.primaryMemoryDomain ?? "unresolved"
        let supportingDomains = decision?.supportingMemoryDomains ?? []
        let focusedProject = nonEmpty(decision?.focusedProjectName)
        let focusedPerson = nonEmpty(decision?.focusedPersonName)
        let writebackSummary = writebackStatusLine(writeback)

        var detailLines: [String] = [
            "主要参考：\(memoryDomainLabel(primaryDomain))",
            "辅助参考：\(supportingDomains.isEmpty ? "（无）" : supportingDomains.map(memoryDomainLabel).joined(separator: "、"))",
            "预计写回：\(writebackSummaryLabel(writebackSummary))"
        ]

        if let focusedProject {
            detailLines.append("聚焦项目：\(focusedProject)")
        }
        if let focusedPerson {
            detailLines.append("聚焦对象：\(focusedPerson)")
        }
        if let assembly {
            detailLines.append("对话模式：\(turnModeLabel(assembly.turnMode))")
            detailLines.append("背景重心：\(planeLabel(assembly.dominantPlane))")
            detailLines.append(
                "辅助背景：\(assembly.supportingPlanes.isEmpty ? "（无）" : assembly.supportingPlanes.map(planeLabel).joined(separator: "、"))"
            )
            detailLines.append(
                "背景深度：连续对话 \(planeDepthLabel(assembly.continuityLaneDepth)) · 个人 \(planeDepthLabel(assembly.assistantPlaneDepth)) · 项目 \(planeDepthLabel(assembly.projectPlaneDepth)) · 关联 \(planeDepthLabel(assembly.crossLinkPlaneDepth))"
            )
            detailLines.append(
                "已带入：\(assembly.selectedSlots.isEmpty ? "（无）" : assembly.selectedSlots.map(slotLabel).joined(separator: "、"))"
            )
        }

        if let candidates = writebackCandidatesLine(writeback) {
            detailLines.append(candidates)
        }
        if let mirrorStatus = writebackMirrorStatusLine(writeback) {
            detailLines.append(mirrorStatus)
        }
        if let localStoreRole = writebackLocalStoreRoleLine(writeback) {
            detailLines.append(localStoreRole)
        }

        return SupervisorTurnMemoryExplainabilityPresentation(
            iconName: turnExplainabilityIconName(decision),
            tone: turnExplainabilityTone(decision, writeback: writeback),
            title: "本轮记忆装配",
            statusLine: turnExplainabilityStatusLine(
                primaryDomain: primaryDomain,
                focusedProject: focusedProject,
                focusedPerson: focusedPerson,
                writebackSummary: writebackSummary
            ),
            detailLines: detailLines
        )
    }

    static func modelRoutePresentation(
        _ context: SupervisorModelRouteContext?
    ) -> SupervisorTaskRouteExplainabilityPresentation? {
        guard let context else { return nil }

        let decision = context.decision
        var detailLines = [
            "任务角色：\(taskRoleLabel(decision.role))",
            "命中角色标签：\(matchedRouteTagsLabel(decision))",
            "优先模型类：\(modelClassListLabel(decision.preferredModelClasses))",
            "回退顺序：\(modelClassListLabel(decision.fallbackOrder))",
            "授权策略：\(grantPolicyLabel(decision.grantPolicy))"
        ]

        if let projectName = nonEmpty(context.projectName) {
            detailLines.insert("项目：\(projectName)", at: 1)
        }
        if !decision.projectModelHints.isEmpty {
            detailLines.append("项目模型提示：\(decision.projectModelHints.joined(separator: "、"))")
        }
        detailLines.append("Hub 裁决：XT 只提供角色意图与模型类偏好，具体模型仍由 Hub 结合 AI registry、grant、budget、trust 最终仲裁")

        return SupervisorTaskRouteExplainabilityPresentation(
            iconName: taskRouteIconName(decision.role),
            tone: taskRouteTone(decision.grantPolicy),
            title: "本轮任务路由",
            statusLine: taskRouteStatusLine(context),
            detailLines: detailLines
        )
    }

    static func afterTurnIconName(
        _ summary: SupervisorManager.SupervisorAfterTurnDerivedSummary
    ) -> String {
        if summary.hasOverdueItems { return "clock.badge.exclamationmark" }
        switch summary.trend {
        case .idle, .stable:
            return "arrow.triangle.branch"
        case .initialized:
            return "arrow.triangle.branch"
        case .increased:
            return "arrow.up.right.circle.fill"
        case .reduced:
            return "arrow.down.right.circle.fill"
        case .cleared:
            return "checkmark.circle.fill"
        }
    }

    static func afterTurnTone(
        _ summary: SupervisorManager.SupervisorAfterTurnDerivedSummary
    ) -> SupervisorHeaderControlTone {
        if summary.hasOverdueItems { return .warning }
        switch summary.trend {
        case .idle, .stable:
            return .neutral
        case .initialized:
            return .accent
        case .increased:
            return .warning
        case .reduced, .cleared:
            return .success
        }
    }

    static func previewExcerpt(
        _ raw: String,
        maxChars: Int = 800
    ) -> String? {
        let trimmed = normalizedScalar(raw)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count > maxChars else { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: maxChars)
        return String(trimmed[..<idx]) + "…"
    }

    static func updatedText(_ timestamp: TimeInterval) -> String {
        guard timestamp > 0 else { return "updated=(none)" }
        return "updated=\(Int(timestamp))"
    }

    static func issueRow(
        _ issue: SupervisorMemoryAssemblyIssue
    ) -> SupervisorMemoryIssuePresentation {
        SupervisorMemoryIssuePresentation(
            id: issue.id,
            severityText: issue.severity.rawValue.uppercased(),
            severityTone: issue.severity == .blocking ? .danger : .warning,
            summary: issue.summary,
            detail: issue.detail
        )
    }

    static func skillRegistryRow(
        _ item: SupervisorSkillRegistryItem,
        registryItems: [SupervisorSkillRegistryItem] = []
    ) -> SupervisorMemorySkillRegistryRowPresentation {
        SupervisorMemorySkillRegistryRowPresentation(
            id: item.id,
            displayName: item.displayName,
            skillId: item.skillId,
            badgeText: item.requiresGrant ? "grant" : item.riskLevel.rawValue,
            badgeTone: item.requiresGrant ? .warning : .neutral,
            metadataText: "\(item.policyScope) · \(item.sideEffectClass) · timeout \(item.timeoutMs)ms · retry \(item.maxRetries)",
            routingHintText: skillRegistryRoutingHint(item, registryItems: registryItems),
            descriptionText: nonEmpty(item.description)
        )
    }

    static func skillRegistryRoutingHint(
        _ item: SupervisorSkillRegistryItem,
        registryItems: [SupervisorSkillRegistryItem] = []
    ) -> String? {
        switch SupervisorSkillRoutingCompatibilityHint.resolve(
            skillId: item.skillId,
            registryItems: registryItems
        ) {
        case .alias(let raw, let canonical):
            return "别名归一：\(raw) -> \(canonical)"
        case .preferredBuiltin(let builtin, let action):
            if let action {
                return "优先内建：\(builtin) · action=\(action)"
            }
            return "优先内建：\(builtin)"
        case .compatibleBuiltin(let builtin):
            return "兼容内建：\(builtin)"
        case .compatibleEntrypoints(let entries):
            return "兼容入口：\(entries.joined(separator: " / "))"
        case nil:
            return nil
        }
    }

    static func digestRow(
        _ digest: SupervisorManager.SupervisorMemoryProjectDigest
    ) -> SupervisorMemoryDigestRowPresentation {
        let blocker = normalizedScalar(digest.blocker)
        return SupervisorMemoryDigestRowPresentation(
            id: digest.id,
            displayName: digest.displayName,
            runtimeState: runtimeStateLabel(digest.runtimeState),
            recentText: "最近 \(digest.recentMessageCount) 条",
            updatedText: updatedDigestText(digest.updatedAt),
            sourceText: "记忆来源：\(memorySourceLabel(digest.source))",
            goalText: "目标：\(digest.goal)",
            nextText: "下一步：\(digest.nextStep)",
            blockerText: blocker == "(无)" || blocker.isEmpty ? nil : "阻塞：\(blocker)"
        )
    }

    private static func turnExplainabilityIconName(
        _ decision: SupervisorTurnRoutingDecision?
    ) -> String {
        switch decision?.mode {
        case .personalFirst:
            return "person.crop.circle.fill"
        case .projectFirst:
            return "folder.fill.badge.person.crop"
        case .hybrid:
            return "link.circle.fill"
        case .portfolioReview:
            return "square.grid.2x2.fill"
        case nil:
            return "memorychip"
        }
    }

    private static func turnExplainabilityTone(
        _ decision: SupervisorTurnRoutingDecision?,
        writeback: SupervisorAfterTurnWritebackClassification?
    ) -> SupervisorHeaderControlTone {
        let scopes = Set(writeback?.candidates.map(\.scope) ?? [])
        if scopes.contains(.crossLinkScope) {
            return .warning
        }
        if scopes.contains(.projectScope) || scopes.contains(.userScope) {
            return .accent
        }
        switch decision?.mode {
        case .hybrid:
            return .warning
        case .projectFirst, .personalFirst:
            return .accent
        case .portfolioReview, nil:
            return .neutral
        }
    }

    private static func turnExplainabilityStatusLine(
        primaryDomain: String,
        focusedProject: String?,
        focusedPerson: String?,
        writebackSummary: String
    ) -> String {
        var parts = ["主要参考：\(memoryDomainLabel(primaryDomain))"]
        if let focusedProject {
            parts.append("聚焦项目：\(focusedProject)")
        }
        if let focusedPerson {
            parts.append("聚焦对象：\(focusedPerson)")
        }
        parts.append("预计写回：\(writebackSummaryLabel(writebackSummary))")
        return parts.joined(separator: " · ")
    }

    private static func writebackStatusLine(
        _ writeback: SupervisorAfterTurnWritebackClassification?
    ) -> String {
        guard let writeback else { return "(none)" }
        let scopes = orderedUniqueScalars(writeback.candidates.map(\.scope.rawValue))
        return scopes.isEmpty ? "(none)" : scopes.joined(separator: ", ")
    }

    private static func writebackCandidatesLine(
        _ writeback: SupervisorAfterTurnWritebackClassification?
    ) -> String? {
        guard let writeback else { return nil }
        let candidates = writeback.candidates.prefix(3).map { candidate in
            "\(writebackScopeLabel(candidate.scope))（\(recordTypeLabel(candidate.recordType))）"
        }
        guard !candidates.isEmpty else { return nil }
        return "优先写回候选：\(candidates.joined(separator: "、"))"
    }

    private static func writebackMirrorStatusLine(
        _ writeback: SupervisorAfterTurnWritebackClassification?
    ) -> String? {
        guard let writeback else { return nil }
        guard !writeback.durableCandidates.isEmpty || writeback.mirrorAttempted else { return nil }

        var line = "Hub mirror：\(writebackMirrorStatusLabel(writeback.mirrorStatus))"
        if let target = writebackMirrorTargetLabel(writeback.mirrorTarget) {
            line += " -> \(target)"
        }
        if let error = nonEmpty(writeback.mirrorErrorCode),
           writeback.mirrorStatus != .mirroredToHub {
            line += " · reason=\(error)"
        }
        return line
    }

    private static func writebackLocalStoreRoleLine(
        _ writeback: SupervisorAfterTurnWritebackClassification?
    ) -> String? {
        guard let writeback else { return nil }
        guard !writeback.durableCandidates.isEmpty || writeback.mirrorAttempted else { return nil }
        let role = nonEmpty(writeback.localStoreRole) ?? XTSupervisorDurableCandidateMirror.localStoreRole
        return "本地 store 角色：\(role)"
    }

    private static func writebackMirrorStatusLabel(
        _ status: SupervisorDurableCandidateMirrorStatus
    ) -> String {
        switch status {
        case .notNeeded:
            return "不需要镜像"
        case .pending:
            return "镜像排队中"
        case .mirroredToHub:
            return "已镜像到 Hub"
        case .localOnly:
            return "仅保留本地 fallback"
        case .hubMirrorFailed:
            return "Hub 镜像失败"
        }
    }

    private static func writebackMirrorTargetLabel(_ raw: String?) -> String? {
        guard let raw = nonEmpty(raw) else { return nil }
        switch raw {
        case XTSupervisorDurableCandidateMirror.mirrorTarget:
            return "Hub candidate carrier（shadow thread）"
        default:
            return raw
        }
    }

    private static func taskRouteIconName(_ role: SupervisorTaskRole) -> String {
        switch role {
        case .planner:
            return "list.clipboard.fill"
        case .coder:
            return "curlybraces.square.fill"
        case .reviewer:
            return "checkmark.shield.fill"
        case .doc:
            return "doc.text.fill"
        case .ops:
            return "bolt.horizontal.circle.fill"
        }
    }

    private static func taskRouteTone(
        _ grantPolicy: SupervisorRouteGrantPolicy
    ) -> SupervisorHeaderControlTone {
        switch grantPolicy {
        case .lowRiskOK:
            return .accent
        case .projectPolicyRequired:
            return .warning
        case .hubPolicyRequired:
            return .danger
        }
    }

    private static func taskRouteStatusLine(
        _ context: SupervisorModelRouteContext
    ) -> String {
        let decision = context.decision
        var parts = ["任务路由：\(taskRoleLabel(decision.role))"]
        if let projectName = nonEmpty(context.projectName) {
            parts.append("项目：\(projectName)")
        }
        parts.append("授权：\(grantPolicyLabel(decision.grantPolicy))")
        parts.append("Hub 决定具体模型")
        return parts.joined(separator: " · ")
    }

    private static func normalizedScalar(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func boardStatusLine(
        rawStatusLine: String,
        memorySource: String,
        projectCount: Int
    ) -> String {
        if projectCount > 0 {
            return "已接入 \(projectCount) 个项目摘要 · 来源 \(memorySourceLabel(memorySource))"
        }
        if normalizedScalar(rawStatusLine).isEmpty {
            return "当前还没有项目记忆摘要"
        }
        return "当前记忆来源：\(memorySourceLabel(memorySource))"
    }

    private static func readinessStatusLine(
        _ readiness: SupervisorMemoryAssemblyReadiness
    ) -> String {
        if readiness.ready {
            return "当前背景已经足够支持 Supervisor 做战略复盘。"
        }
        return "当前还有 \(readiness.issues.count) 个关键背景缺口，先补齐再做深度复盘会更稳。"
    }

    private static func assemblyStatusLine(
        _ rawStatusLine: String,
        snapshot: SupervisorMemoryAssemblySnapshot?
    ) -> String {
        guard let snapshot else {
            return normalizedScalar(rawStatusLine).isEmpty
                ? "这轮还没有完成背景装配。"
                : "这轮还没有可用的背景装配结果。"
        }

        var parts: [String] = []
        if let focusedProject = nonEmpty(snapshot.focusedProjectId) {
            parts.append("当前聚焦项目：\(focusedProject)")
        }
        parts.append("已带入 \(snapshot.selectedSections.count) 个背景分区")
        if snapshot.contextRefsSelected > 0 {
            parts.append("\(snapshot.contextRefsSelected) 条关联引用")
        }
        if snapshot.evidenceItemsSelected > 0 {
            parts.append("\(snapshot.evidenceItemsSelected) 条执行证据")
        }
        return parts.joined(separator: " · ")
    }

    private static func assemblyDetailLine(
        _ snapshot: SupervisorMemoryAssemblySnapshot?
    ) -> String? {
        guard let snapshot else { return nil }

        var parts: [String] = []
        if !snapshot.omittedSections.isEmpty {
            parts.append("未带入：\(snapshot.omittedSections.map(sectionLabel).joined(separator: "、"))")
        }
        if let usedTotalTokens = snapshot.usedTotalTokens,
           let budgetTotalTokens = snapshot.budgetTotalTokens,
           budgetTotalTokens > 0 {
            parts.append("上下文预算：\(usedTotalTokens)/\(budgetTotalTokens) tokens")
        }
        let merged = parts.joined(separator: " · ").trimmingCharacters(in: .whitespacesAndNewlines)
        return merged.isEmpty ? nil : merged
    }

    private static func updatedDigestText(_ timestamp: TimeInterval) -> String {
        guard timestamp > 0 else { return "刚刚更新：未知" }
        return "更新时间 \(Int(timestamp))"
    }

    private static func memoryUseModeLabel(_ mode: XTMemoryUseMode) -> String {
        switch mode {
        case .projectChat:
            return "项目对话"
        case .sessionResume:
            return "会话续接"
        case .supervisorOrchestration:
            return "Supervisor 编排"
        case .toolPlan:
            return "工具规划"
        case .toolActLowRisk:
            return "低风险工具执行"
        case .toolActHighRisk:
            return "高风险工具执行"
        case .laneHandoff:
            return "lane handoff"
        case .remotePromptBundle:
            return "远端提示词打包"
        }
    }

    private static func memorySourceLabel(_ raw: String) -> String {
        XTMemorySourceTruthPresentation.label(raw)
    }

    private static func profileLabel(_ raw: String) -> String {
        switch normalizedScalar(raw) {
        case "balanced":
            return "Balanced"
        case XTMemoryServingProfile.m0Heartbeat.rawValue:
            return "Heartbeat"
        case XTMemoryServingProfile.m1Execute.rawValue:
            return "Execute"
        case XTMemoryServingProfile.m2PlanReview.rawValue:
            return "Plan Review"
        case XTMemoryServingProfile.m3DeepDive.rawValue:
            return "Deep Dive"
        case XTMemoryServingProfile.m4FullScan.rawValue:
            return "Full"
        default:
            return humanizeToken(raw)
        }
    }

    private static func failureReasonLabel(_ raw: String) -> String {
        switch normalizedScalar(raw) {
        case "runtime_not_running":
            return "远端模型当前未运行"
        case "remote_route_not_preferred":
            return "当前策略没有选择远端模型"
        case "memory_assembly_unavailable":
            return "本轮未拿到可用记忆装配"
        default:
            return humanizeToken(raw)
        }
    }

    private static func sectionLabel(_ raw: String) -> String {
        switch normalizedScalar(raw) {
        case "l1_canonical":
            return "标准视图"
        case "l2_observations":
            return "近期观察"
        case "l3_working_set":
            return "当前工作集"
        case "dialogue_window":
            return "最近对话"
        case "personal_capsule":
            return "个人摘要"
        case "focused_project_anchor_pack", "focused_project_capsule":
            return "当前项目摘要"
        case "portfolio_brief":
            return "项目总览"
        case "cross_link_refs":
            return "关联线索"
        case "evidence_pack":
            return "执行证据"
        default:
            return humanizeToken(raw)
        }
    }

    private static func continuityDrillDownLines(
        assemblySnapshot: SupervisorMemoryAssemblySnapshot?,
        failureReasonCode: String
    ) -> [String] {
        guard let snapshot = assemblySnapshot else {
            let failure = normalizedScalar(failureReasonCode)
            return failure.isEmpty ? [] : ["异常原因：\(failureReasonLabel(failure))."]
        }

        var lines: [String] = []
        let floorLine = snapshot.continuityFloorSatisfied
            ? "最近原始对话保留 \(snapshot.rawWindowSelectedPairs) 组，已满足至少 \(snapshot.rawWindowFloorPairs) 组的连续性底线。"
            : "最近原始对话保留 \(snapshot.rawWindowSelectedPairs) 组，还没达到至少 \(snapshot.rawWindowFloorPairs) 组的连续性底线。"
        lines.append(floorLine)

        var coverageParts = ["带入 \(snapshot.selectedSections.count) 个背景分区"]
        if snapshot.contextRefsSelected > 0 {
            coverageParts.append("\(snapshot.contextRefsSelected) 条关联引用")
        }
        if snapshot.evidenceItemsSelected > 0 {
            coverageParts.append("\(snapshot.evidenceItemsSelected) 条执行证据")
        }
        lines.append(coverageParts.joined(separator: "，") + "。")

        var hygieneParts: [String] = []
        if snapshot.lowSignalDroppedMessages > 0 {
            hygieneParts.append("过滤了 \(snapshot.lowSignalDroppedMessages) 条低信号寒暄")
        }
        if snapshot.rollingDigestPresent {
            hygieneParts.append("保留了滚动摘要")
        }
        if snapshot.truncationAfterFloor {
            hygieneParts.append("在满足底线后继续做了截断")
        }
        if let mirrorLine = continuityMirrorLine(snapshot) {
            hygieneParts.append(mirrorLine)
        }
        let failure = normalizedScalar(failureReasonCode)
        if !failure.isEmpty {
            hygieneParts.append("异常原因：\(failureReasonLabel(failure))")
        }
        if !hygieneParts.isEmpty {
            lines.append(hygieneParts.joined(separator: "，") + "。")
        }

        return Array(lines.prefix(3))
    }

    private static func continuityMirrorLine(
        _ snapshot: SupervisorMemoryAssemblySnapshot
    ) -> String? {
        guard snapshot.durableCandidateMirrorAttempted
                || snapshot.durableCandidateMirrorStatus != .notNeeded else {
            return nil
        }

        var line = "Hub durable candidate mirror：\(writebackMirrorStatusLabel(snapshot.durableCandidateMirrorStatus))"
        if let target = writebackMirrorTargetLabel(snapshot.durableCandidateMirrorTarget) {
            line += " -> \(target)"
        }
        if let error = nonEmpty(snapshot.durableCandidateMirrorErrorCode),
           snapshot.durableCandidateMirrorStatus != .mirroredToHub {
            line += "（reason=\(error)）"
        }
        return line
    }

    private static func memoryDomainLabel(_ raw: String) -> String {
        switch normalizedScalar(raw) {
        case "personal_memory":
            return "个人记忆"
        case "project_memory":
            return "项目记忆"
        case "personal_memory + project_memory":
            return "个人记忆 + 项目记忆"
        case "portfolio_brief":
            return "项目总览"
        case "project_memory_if_relevant":
            return "必要时补项目记忆"
        case "focused_project_capsule_if_needed":
            return "必要时补当前项目摘要"
        case "cross_link_refs":
            return "关联线索"
        default:
            return humanizeToken(raw)
        }
    }

    private static func turnModeLabel(_ mode: SupervisorTurnMode) -> String {
        switch mode {
        case .personalFirst:
            return "个人优先"
        case .projectFirst:
            return "项目优先"
        case .hybrid:
            return "个人 + 项目混合"
        case .portfolioReview:
            return "项目总览复盘"
        }
    }

    private static func planeLabel(_ raw: String) -> String {
        switch normalizedScalar(raw) {
        case "assistant_plane":
            return "个人背景主导"
        case "project_plane":
            return "项目背景主导"
        case "assistant_plane + project_plane":
            return "个人与项目背景并重"
        case "project_plane(portfolio_brief)":
            return "项目总览主导"
        case "cross_link_plane":
            return "关联线索"
        case "cross_link_plane(on_demand)":
            return "关联线索（按需）"
        case "cross_link_plane(selected)":
            return "关联线索（按选中项）"
        case "portfolio_brief":
            return "项目总览"
        default:
            return humanizeToken(raw)
        }
    }

    private static func planeDepthLabel(_ depth: SupervisorTurnContextPlaneDepth) -> String {
        switch depth {
        case .off:
            return "关闭"
        case .onDemand:
            return "按需"
        case .light:
            return "轻量"
        case .medium:
            return "中等"
        case .full:
            return "完整"
        case .selected:
            return "按选中项"
        case .portfolioFirst:
            return "总览优先"
        }
    }

    private static func slotLabel(_ slot: SupervisorTurnContextSlot) -> String {
        switch slot {
        case .dialogueWindow:
            return "最近对话"
        case .personalCapsule:
            return "个人摘要"
        case .focusedProjectCapsule:
            return "当前项目摘要"
        case .portfolioBrief:
            return "项目总览"
        case .crossLinkRefs:
            return "关联线索"
        case .evidencePack:
            return "执行证据"
        }
    }

    private static func taskRoleLabel(_ role: SupervisorTaskRole) -> String {
        switch role {
        case .planner:
            return "规划 / 策略"
        case .coder:
            return "编码 / 实现"
        case .reviewer:
            return "评审 / 回归"
        case .doc:
            return "文档 / 说明"
        case .ops:
            return "运维 / 执行"
        }
    }

    private static func matchedRouteTagsLabel(
        _ decision: SupervisorModelRouteDecision
    ) -> String {
        guard !decision.matchedRouteTags.isEmpty else {
            return "无显式标签（按 fail-closed 规则归到\(taskRoleLabel(decision.role))）"
        }
        return decision.matchedRouteTags.joined(separator: "、")
    }

    private static func modelClassListLabel(
        _ classes: [SupervisorPreferredModelClass]
    ) -> String {
        let labels = classes.map(modelClassLabel)
        return labels.isEmpty ? "暂无" : labels.joined(separator: "、")
    }

    private static func modelClassLabel(
        _ modelClass: SupervisorPreferredModelClass
    ) -> String {
        switch modelClass {
        case .localReasoner:
            return "本地推理"
        case .paidPlanner:
            return "付费规划"
        case .paidGeneral:
            return "付费通用"
        case .paidCoder:
            return "付费编码"
        case .localCodegen:
            return "本地代码生成"
        case .paidReviewer:
            return "付费评审"
        case .paidWriter:
            return "付费写作"
        case .localWriter:
            return "本地写作"
        case .paidOps:
            return "付费运维"
        }
    }

    private static func grantPolicyLabel(
        _ grantPolicy: SupervisorRouteGrantPolicy
    ) -> String {
        switch grantPolicy {
        case .lowRiskOK:
            return "低风险可直行"
        case .projectPolicyRequired:
            return "需项目治理"
        case .hubPolicyRequired:
            return "需 Hub 授权"
        }
    }

    private static func writebackSummaryLabel(_ raw: String) -> String {
        let labels = orderedUniqueScalars(raw.components(separatedBy: ","))
            .map { writebackScopeLabel(rawValue: $0) }
        return labels.isEmpty ? "暂无" : labels.joined(separator: "、")
    }

    private static func writebackScopeLabel(_ scope: SupervisorAfterTurnWritebackScope) -> String {
        writebackScopeLabel(rawValue: scope.rawValue)
    }

    private static func writebackScopeLabel(rawValue: String) -> String {
        switch normalizedScalar(rawValue) {
        case SupervisorAfterTurnWritebackScope.userScope.rawValue:
            return "个人长期记忆"
        case SupervisorAfterTurnWritebackScope.projectScope.rawValue:
            return "项目记忆"
        case SupervisorAfterTurnWritebackScope.crossLinkScope.rawValue:
            return "跨域关联"
        case SupervisorAfterTurnWritebackScope.workingSetOnly.rawValue:
            return "仅保留在当前工作集中"
        case SupervisorAfterTurnWritebackScope.dropAsNoise.rawValue:
            return "作为噪声丢弃"
        default:
            return humanizeToken(rawValue)
        }
    }

    private static func recordTypeLabel(_ raw: String) -> String {
        switch normalizedScalar(raw) {
        case "preferred_user_name", "preferred_name":
            return "偏好称呼"
        case "personal_preference":
            return "个人偏好"
        case "person_waiting_on_project":
            return "人物依赖项目"
        case "commitment_depends_on_project":
            return "承诺依赖项目"
        case "project_blocker":
            return "项目阻塞"
        case "project_goal_or_constraint":
            return "项目目标/约束"
        case "project_plan_change":
            return "项目计划变化"
        case "transient_turn_note":
            return "临时对话记录"
        case "small_talk":
            return "寒暄噪声"
        default:
            return humanizeToken(raw)
        }
    }

    private static func runtimeStateLabel(_ raw: String) -> String {
        switch normalizedScalar(raw) {
        case "active":
            return "进行中"
        case "running":
            return "运行中"
        case "blocked":
            return "阻塞"
        case "idle":
            return "暂停中"
        case "planning":
            return "规划中"
        case "completed":
            return "已完成"
        default:
            return humanizeToken(raw)
        }
    }

    private static func humanizeToken(_ raw: String) -> String {
        let trimmed = normalizedScalar(raw)
        guard !trimmed.isEmpty else { return "暂无" }
        return trimmed.replacingOccurrences(of: "_", with: " ")
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        let trimmed = normalizedScalar(raw ?? "")
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func orderedUniqueScalars(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for item in raw {
            let normalized = normalizedScalar(item)
            guard !normalized.isEmpty else { continue }
            guard seen.insert(normalized).inserted else { continue }
            output.append(normalized)
        }
        return output
    }
}
