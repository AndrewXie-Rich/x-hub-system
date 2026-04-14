import Foundation

enum SupervisorProjectDrillDownLineTone: Equatable {
    case primary
    case secondary
    case warning
}

struct SupervisorProjectDrillDownScopeOptionPresentation: Equatable, Identifiable {
    var scope: SupervisorProjectDrillDownScope
    var title: String

    var id: String { scope.rawValue }
}

struct SupervisorProjectDrillDownLinePresentation: Equatable, Identifiable {
    var id: String
    var text: String
    var tone: SupervisorProjectDrillDownLineTone
    var monospaced: Bool = false
    var lineLimit: Int? = 2
}

struct SupervisorProjectDrillDownSectionPresentation: Equatable, Identifiable {
    var id: String
    var title: String?
    var lines: [SupervisorProjectDrillDownLinePresentation]
}

struct SupervisorProjectDrillDownPresentation: Equatable {
    var title: String
    var projectId: String
    var projectName: String
    var scopeOptions: [SupervisorProjectDrillDownScopeOptionPresentation]
    var statusLine: String
    var governanceTags: [SupervisorPortfolioTagPresentation]
    var runtimeSummary: String?
    var scopeRestrictionText: String?
    var latestUIReview: XTUIReviewPresentation?
    var sections: [SupervisorProjectDrillDownSectionPresentation]
}

enum SupervisorProjectDrillDownPresentationMapper {
    static func map(
        snapshot: SupervisorProjectDrillDownSnapshot,
        allowedScopes: [SupervisorProjectDrillDownScope],
        selectedScope: SupervisorProjectDrillDownScope,
        governanceTags: [SupervisorPortfolioTagPresentation],
        runtimeSummary: String?,
        latestUIReview: XTUIReviewPresentation?,
        governanceNowMs: Int64
    ) -> SupervisorProjectDrillDownPresentation {
        SupervisorProjectDrillDownPresentation(
            title: "项目细看",
            projectId: snapshot.projectId,
            projectName: snapshot.projectName,
            scopeOptions: [
                SupervisorProjectDrillDownScopeOptionPresentation(
                    scope: .capsuleOnly,
                    title: "项目摘要"
                ),
                SupervisorProjectDrillDownScopeOptionPresentation(
                    scope: .capsulePlusRecent,
                    title: "摘要+最近对话"
                ),
            ],
            statusLine: statusLine(for: snapshot),
            governanceTags: governanceTags,
            runtimeSummary: nonEmpty(runtimeSummary),
            scopeRestrictionText: allowedScopes.contains(.capsulePlusRecent)
                ? nil
                : "这个项目当前只开放“项目摘要”，最近对话视图暂未开放。",
            latestUIReview: latestUIReview,
            sections: sections(
                snapshot: snapshot,
                selectedScope: selectedScope,
                governanceNowMs: governanceNowMs
            )
        )
    }

    static func sections(
        snapshot: SupervisorProjectDrillDownSnapshot,
        selectedScope: SupervisorProjectDrillDownScope,
        governanceNowMs: Int64
    ) -> [SupervisorProjectDrillDownSectionPresentation] {
        switch snapshot.status {
        case .allowed:
            return allowedSections(
                snapshot: snapshot,
                selectedScope: selectedScope,
                governanceNowMs: governanceNowMs
            )
        case .deniedProjectInvisible, .deniedScope, .projectNotFound:
            return [
                SupervisorProjectDrillDownSectionPresentation(
                    id: "denied",
                    title: nil,
                    lines: [
                        line(
                            id: "denied-reason",
                            text: snapshot.denyReason ?? snapshot.status.rawValue,
                            tone: .warning,
                            lineLimit: 3
                        )
                    ]
                )
            ]
        }
    }

    private static func allowedSections(
        snapshot: SupervisorProjectDrillDownSnapshot,
        selectedScope: SupervisorProjectDrillDownScope,
        governanceNowMs: Int64
    ) -> [SupervisorProjectDrillDownSectionPresentation] {
        var sections: [SupervisorProjectDrillDownSectionPresentation] = []

        if let capsule = snapshot.capsule {
            var lines = [
                line(id: "capsule-action", text: "当前动作：\(capsule.currentAction)", tone: .primary),
                line(id: "capsule-next", text: "下一步：\(capsule.nextStep)", tone: .secondary),
            ]
            if let blocker = nonEmpty(capsule.topBlocker) {
                if let blockerLine = SupervisorBlockerPresentation.blockerLine(blocker) {
                    lines.append(
                        line(
                            id: "capsule-blocker",
                            text: blockerLine,
                            tone: .warning
                        )
                    )
                }
            }
            sections.append(
                SupervisorProjectDrillDownSectionPresentation(
                    id: "capsule",
                    title: nil,
                    lines: lines
                )
            )
        }

        if let spec = snapshot.specCapsule {
            sections.append(
                SupervisorProjectDrillDownSectionPresentation(
                    id: "spec-capsule",
                    title: "规格摘要",
                    lines: specCapsuleLines(spec)
                )
            )
        }

        if let rails = snapshot.decisionRails {
            let railLines = decisionRailLines(rails)
            if !railLines.isEmpty {
                sections.append(
                    SupervisorProjectDrillDownSectionPresentation(
                        id: "decision-rails",
                        title: "已确认决策",
                        lines: railLines
                    )
                )
            }
        }

        if let assist = snapshot.capsule?.decisionAssist {
            let assistLines = decisionAssistLines(assist)
            if !assistLines.isEmpty {
                sections.append(
                    SupervisorProjectDrillDownSectionPresentation(
                        id: "decision-assist",
                        title: "决策建议",
                        lines: assistLines
                    )
                )
            }
        }

        if let rollup = snapshot.memoryCompactionRollup {
            let rollupLines = memoryCompactionLines(rollup)
            if !rollupLines.isEmpty {
                sections.append(
                    SupervisorProjectDrillDownSectionPresentation(
                        id: "memory-compaction",
                        title: "记忆收口",
                        lines: rollupLines
                    )
                )
            }
        }

        let governanceLines = governanceLines(snapshot: snapshot, governanceNowMs: governanceNowMs)
        if !governanceLines.isEmpty {
            sections.append(
                SupervisorProjectDrillDownSectionPresentation(
                    id: "governance",
                    title: "最新治理",
                    lines: governanceLines
                )
            )
        }

        if let workflow = snapshot.workflow,
           let activeJob = workflow.activeJob {
            var lines = [
                line(id: "workflow-job", text: "job: \(activeJob.goal)", tone: .primary),
                line(id: "workflow-status", text: "status: \(activeJob.status.rawValue)", tone: .secondary),
            ]
            if let activePlan = workflow.activePlan {
                lines.append(
                    line(
                        id: "workflow-plan-status",
                        text: "plan: \(activePlan.status.rawValue)",
                        tone: .secondary
                    )
                )
                let stepLines = activePlan.steps
                    .sorted { lhs, rhs in
                        if lhs.orderIndex != rhs.orderIndex {
                            return lhs.orderIndex < rhs.orderIndex
                        }
                        return lhs.stepId < rhs.stepId
                    }
                    .prefix(3)
                    .map { step in
                        line(
                            id: "workflow-step-\(step.stepId)",
                            text: "\(step.orderIndex + 1). \(step.title)",
                            tone: .secondary
                        )
                    }
                lines.append(contentsOf: stepLines)
            }
            sections.append(
                SupervisorProjectDrillDownSectionPresentation(
                    id: "active-workflow",
                    title: "当前工作流",
                    lines: lines
                )
            )
        }

        if snapshot.recentMessages.isEmpty {
            let emptyText = selectedScope == .capsuleOnly
                ? "当前只展示项目摘要；切到“摘要+最近对话”后可查看最近对话。"
                : "当前还没有可展示的最近对话。"
            sections.append(
                SupervisorProjectDrillDownSectionPresentation(
                    id: "recent-empty",
                    title: nil,
                    lines: [
                        line(
                            id: "recent-empty-line",
                            text: emptyText,
                            tone: .secondary
                        )
                    ]
                )
            )
        } else {
            sections.append(
                SupervisorProjectDrillDownSectionPresentation(
                    id: "recent-short-context",
                    title: "最近对话",
                    lines: snapshot.recentMessages.enumerated().map { offset, message in
                        line(
                            id: "recent-message-\(offset)",
                            text: "\(message.role): \(message.content)",
                            tone: message.role == "assistant" ? .secondary : .primary
                        )
                    }
                )
            )
        }

        if !snapshot.refs.isEmpty {
            sections.append(
                SupervisorProjectDrillDownSectionPresentation(
                    id: "scope-safe-refs",
                    title: "关联引用",
                    lines: Array(snapshot.refs.prefix(4).enumerated()).map { offset, ref in
                        line(
                            id: "ref-\(offset)",
                            text: ref,
                            tone: .secondary,
                            monospaced: true,
                            lineLimit: 1
                        )
                    }
                )
            )
        }

        return sections
    }

    private static func statusLine(
        for snapshot: SupervisorProjectDrillDownSnapshot
    ) -> String {
        let scopeLabel = scopeTitle(snapshot.grantedScope ?? snapshot.requestedScope)
        let reasonLabel = openedReasonLabel(snapshot.openedReason)
        let refCount = snapshot.refs.count
        if refCount > 0 {
            return "当前显示：\(scopeLabel) · \(reasonLabel) · \(refCount) 条关联引用"
        }
        return "当前显示：\(scopeLabel) · \(reasonLabel)"
    }

    private static func decisionRailLines(
        _ rails: SupervisorProjectDecisionRails
    ) -> [SupervisorProjectDrillDownLinePresentation] {
        var lines: [SupervisorProjectDrillDownLinePresentation] = []

        for decision in rails.decisionTrack.prefix(3) {
            lines.append(
                line(
                    id: "decision-\(decision.id)",
                    text: "已批准\(localizedDecisionCategory(decision.category))：\(decision.statement)",
                    tone: .primary
                )
            )
        }

        for resolution in rails.resolutions.prefix(3) {
            if let note = resolution.preferredBackgroundNote {
                lines.append(
                    line(
                        id: "background-\(resolution.domain.rawValue)-preferred",
                        text: "背景偏好·\(localizedBackgroundDomain(resolution.domain)) [\(localizedBackgroundStrength(note.strength))]：\(note.statement)",
                        tone: .secondary
                    )
                )
                if note.mustNotPromoteWithoutDecision {
                    lines.append(
                        line(
                            id: "background-\(resolution.domain.rawValue)-guard",
                            text: "保护规则·\(localizedBackgroundDomain(resolution.domain))：在正式决策前仅作弱约束",
                            tone: .warning
                        )
                    )
                }
            } else if let note = resolution.shadowedBackgroundNotes.first {
                let shadowedCount = resolution.shadowedBackgroundNotes.count
                lines.append(
                    line(
                        id: "background-\(resolution.domain.rawValue)-precedence",
                        text: "决策优先·\(localizedBackgroundDomain(resolution.domain))：正式决策覆盖\(backgroundNoteCountText(shadowedCount))",
                        tone: .warning
                    )
                )
                lines.append(
                    line(
                        id: "background-\(resolution.domain.rawValue)-shadowed",
                        text: "被覆盖背景·\(localizedBackgroundDomain(resolution.domain)) [\(localizedBackgroundStrength(note.strength))]：\(note.statement)",
                        tone: .secondary
                    )
                )
            }
        }

        return lines
    }

    private static func decisionAssistLines(
        _ assist: SupervisorDecisionBlockerAssist
    ) -> [SupervisorProjectDrillDownLinePresentation] {
        let recommendation = assist.recommendedOption ?? assist.templateCandidates.first ?? "(none)"
        var lines = [
            line(
                id: "assist-proposal",
                text: "proposal \(assist.blockerCategory.rawValue): \(recommendation)",
                tone: .primary
            ),
            line(
                id: "assist-mode",
                text: "mode: \(assist.governanceMode.rawValue)",
                tone: .secondary
            ),
            line(
                id: "assist-status",
                text: "status: \(assist.approvalState.rawValue)",
                tone: .secondary
            )
        ]

        if let timeoutMs = assist.timeoutEscalationAfterMs, timeoutMs > 0 {
            lines.append(
                line(
                    id: "assist-timeout",
                    text: "escalate after: \(decisionAssistTimeoutText(timeoutMs))",
                    tone: .secondary
                )
            )
        }

        lines.append(
            line(
                id: "assist-why",
                text: "why: \(assist.explanation)",
                tone: .secondary,
                lineLimit: 3
            )
        )
        lines.append(
            line(
                id: "assist-guard",
                text: decisionAssistGuardText(assist),
                tone: .warning,
                lineLimit: 3
            )
        )

        return lines
    }

    private static func memoryCompactionLines(
        _ rollup: SupervisorMemoryCompactionRollup
    ) -> [SupervisorProjectDrillDownLinePresentation] {
        var lines: [SupervisorProjectDrillDownLinePresentation] = [
            line(
                id: "memory-compaction-summary",
                text: "summary: \(rollup.rollupSummary)",
                tone: .primary,
                lineLimit: 3
            ),
            line(
                id: "memory-compaction-mode",
                text: rollup.archiveCandidate
                    ? "mode: archive candidate"
                    : "mode: rollup only",
                tone: rollup.archiveCandidate ? .warning : .secondary
            )
        ]

        if !rollup.rolledUpNodeIds.isEmpty {
            lines.append(
                line(
                    id: "memory-compaction-rolled-up",
                    text: "rolled up: \(summarizedIDs(rollup.rolledUpNodeIds))",
                    tone: .secondary,
                    lineLimit: 3
                )
            )
        }

        if !rollup.archivedNodeIds.isEmpty {
            lines.append(
                line(
                    id: "memory-compaction-archived",
                    text: "archived: \(summarizedIDs(rollup.archivedNodeIds))",
                    tone: .secondary,
                    lineLimit: 3
                )
            )
        }

        if !rollup.keptDecisionIds.isEmpty {
            lines.append(
                line(
                    id: "memory-compaction-decisions",
                    text: "kept decisions: \(summarizedIDs(rollup.keptDecisionIds))",
                    tone: .secondary,
                    lineLimit: 3
                )
            )
        }

        if !rollup.keptMilestoneIds.isEmpty {
            lines.append(
                line(
                    id: "memory-compaction-milestones",
                    text: "kept milestones: \(summarizedIDs(rollup.keptMilestoneIds))",
                    tone: .secondary,
                    lineLimit: 3
                )
            )
        }

        if !rollup.keptReleaseGateRefs.isEmpty {
            lines.append(
                line(
                    id: "memory-compaction-release-refs",
                    text: "release refs: \(summarizedIDs(rollup.keptReleaseGateRefs))",
                    tone: .secondary,
                    monospaced: true,
                    lineLimit: 2
                )
            )
        }

        if !rollup.keptAuditRefs.isEmpty {
            lines.append(
                line(
                    id: "memory-compaction-audit-refs",
                    text: "audit refs: \(summarizedIDs(rollup.keptAuditRefs))",
                    tone: .secondary,
                    monospaced: true,
                    lineLimit: 2
                )
            )
        }

        return lines
    }

    private static func specCapsuleLines(
        _ spec: SupervisorProjectSpecCapsule
    ) -> [SupervisorProjectDrillDownLinePresentation] {
        let missingFields = spec.missingRequiredFields
        var lines = [
            line(
                id: "spec-goal",
                text: "目标：\(specScalar(spec.goal))",
                tone: scalarTone(spec.goal, primaryTone: .primary)
            ),
            line(
                id: "spec-mvp",
                text: "MVP：\(specScalar(spec.mvpDefinition))",
                tone: scalarTone(spec.mvpDefinition, primaryTone: .secondary)
            ),
            line(
                id: "spec-non-goals",
                text: "非目标：\(listSummary(spec.nonGoals))",
                tone: spec.nonGoals.isEmpty ? .warning : .secondary,
                lineLimit: 3
            ),
            line(
                id: "spec-tech-stack",
                text: "技术栈：\(listSummary(spec.approvedTechStack))",
                tone: spec.approvedTechStack.isEmpty ? .warning : .secondary,
                lineLimit: 3
            ),
            line(
                id: "spec-milestones",
                text: "里程碑：\(milestoneSummary(spec.milestoneMap))",
                tone: spec.milestoneMap.isEmpty ? .warning : .secondary,
                lineLimit: 3
            )
        ]

        if !missingFields.isEmpty {
            lines.append(
                line(
                    id: "spec-gap",
                    text: "规格缺口：\(missingFields.map(localizedSpecField).joined(separator: " / "))",
                    tone: .warning,
                    lineLimit: 3
                )
            )
        }

        return lines
    }

    private static func governanceLines(
        snapshot: SupervisorProjectDrillDownSnapshot,
        governanceNowMs: Int64
    ) -> [SupervisorProjectDrillDownLinePresentation] {
        var lines: [SupervisorProjectDrillDownLinePresentation] = []

        if let followUp = nonEmpty(snapshot.followUpRhythmSummary) {
            lines.append(
                line(
                    id: "governance-follow-up",
                    text: "跟进节奏：\(ProjectGovernanceActivityDisplay.displayValue(label: "follow_up_rhythm", value: followUp))",
                    tone: .secondary,
                    lineLimit: 3
                )
            )
        }

        if let cadence = snapshot.cadenceExplainability {
            lines.append(
                line(
                    id: "governance-cadence-configured",
                    text: "已配置节奏：\(cadenceSummaryText(cadence, selector: \.configuredSeconds))",
                    tone: .secondary,
                    lineLimit: 3
                )
            )
            lines.append(
                line(
                    id: "governance-cadence-recommended",
                    text: "建议节奏：\(cadenceSummaryText(cadence, selector: \.recommendedSeconds))",
                    tone: .secondary,
                    lineLimit: 3
                )
            )
            lines.append(
                line(
                    id: "governance-cadence-effective",
                    text: "生效节奏：\(cadenceSummaryText(cadence, selector: \.effectiveSeconds))",
                    tone: .secondary,
                    lineLimit: 3
                )
            )
            lines.append(
                line(
                    id: "governance-cadence-reason",
                    text: "节奏原因：\(cadenceReasonSummaryText(cadence))",
                    tone: .secondary,
                    lineLimit: 4
                )
            )
            lines.append(
                line(
                    id: "governance-cadence-due",
                    text: "到期判断：\(cadenceDueSummaryText(cadence))",
                    tone: .secondary,
                    lineLimit: 4
                )
            )
        }

        if let review = snapshot.latestReview {
            lines.append(
                line(
                    id: "review-headline",
                    text: "审查：\(ProjectGovernanceActivityDisplay.displayValue(label: "verdict", value: review.verdict.displayName)) · \(ProjectGovernanceActivityDisplay.displayValue(label: "level", value: review.reviewLevel.displayName)) · \(ProjectGovernanceActivityDisplay.displayValue(label: "trigger", value: review.trigger.displayName))",
                    tone: .primary
                )
            )
            lines.append(
                line(
                    id: "review-tier",
                    text: "层级：\(ProjectGovernanceActivityDisplay.displayValue(label: "supervisor_tier", value: (review.effectiveSupervisorTier?.displayName) ?? "(none)")) · 工单深度：\(ProjectGovernanceActivityDisplay.displayValue(label: "work_order_depth", value: (review.effectiveWorkOrderDepth?.displayName) ?? "(none)")) · AI 强度：\(ProjectGovernanceActivityDisplay.displayValue(label: "project_ai_strength", value: projectAIStrengthText(band: review.projectAIStrengthBand, confidence: review.projectAIStrengthConfidence)))",
                    tone: .secondary
                )
            )
            lines.append(
                line(
                    id: "review-summary",
                    text: "摘要：\(governanceScalar(review.summary))",
                    tone: .secondary
                )
            )
            if let action = nonEmpty(review.recommendedActions.first) {
                lines.append(
                    line(
                        id: "review-next",
                        text: "下一步：\(action)",
                        tone: .secondary
                    )
                )
            }
            let workOrderRef = governanceScalar(review.workOrderRef)
            if workOrderRef != "(none)" {
                lines.append(
                    line(
                        id: "review-work-order",
                        text: "工单：\(workOrderRef)",
                        tone: .secondary,
                        monospaced: true,
                        lineLimit: 1
                    )
                )
            }
        }

        if let guidance = snapshot.pendingAckGuidance {
            lines.append(
                line(
                    id: "pending-guidance-headline",
                    text: "待确认指导：\(ProjectGovernanceActivityDisplay.displayValue(label: "delivery", value: guidance.deliveryMode.displayName)) · \(ProjectGovernanceActivityDisplay.displayValue(label: "intervention", value: guidance.interventionMode.displayName))",
                    tone: .warning
                )
            )
            lines.append(
                line(
                    id: "pending-guidance-ack",
                    text: "确认：\(ProjectGovernanceActivityDisplay.displayValue(label: "ack", value: guidanceAckText(guidance))) · 安全点：\(ProjectGovernanceActivityDisplay.displayValue(label: "safe_point", value: guidance.safePointPolicy.displayName)) · 生命周期：\(ProjectGovernanceActivityDisplay.displayValue(label: "lifecycle", value: SupervisorGuidanceInjectionStore.lifecycleSummary(for: guidance, nowMs: governanceNowMs)))",
                    tone: .warning
                )
            )
            lines.append(
                line(
                    id: "pending-guidance-tier",
                    text: "层级：\(ProjectGovernanceActivityDisplay.displayValue(label: "supervisor_tier", value: (guidance.effectiveSupervisorTier?.displayName) ?? "(none)")) · 工单深度：\(ProjectGovernanceActivityDisplay.displayValue(label: "work_order_depth", value: (guidance.effectiveWorkOrderDepth?.displayName) ?? "(none)")) · 工单：\(governanceScalar(guidance.workOrderRef))",
                    tone: .secondary
                )
            )
            lines.append(contentsOf:
                structuredGuidanceLines(
                    prefix: "pending-guidance",
                    guidance: guidance,
                    review: guidanceReview(snapshot: snapshot, guidance: guidance),
                    primaryTone: .warning
                )
            )
        }

        if let guidance = snapshot.latestGuidance,
           guidance.injectionId != snapshot.pendingAckGuidance?.injectionId {
            lines.append(
                line(
                    id: "latest-guidance-headline",
                    text: "最新指导：\(ProjectGovernanceActivityDisplay.displayValue(label: "delivery", value: guidance.deliveryMode.displayName)) · \(ProjectGovernanceActivityDisplay.displayValue(label: "intervention", value: guidance.interventionMode.displayName))",
                    tone: .primary
                )
            )
            lines.append(
                line(
                    id: "latest-guidance-ack",
                    text: "确认：\(ProjectGovernanceActivityDisplay.displayValue(label: "ack", value: guidanceAckText(guidance))) · 安全点：\(ProjectGovernanceActivityDisplay.displayValue(label: "safe_point", value: guidance.safePointPolicy.displayName)) · 生命周期：\(ProjectGovernanceActivityDisplay.displayValue(label: "lifecycle", value: SupervisorGuidanceInjectionStore.lifecycleSummary(for: guidance, nowMs: governanceNowMs)))",
                    tone: .secondary
                )
            )
            lines.append(contentsOf:
                structuredGuidanceLines(
                    prefix: "latest-guidance",
                    guidance: guidance,
                    review: guidanceReview(snapshot: snapshot, guidance: guidance),
                    primaryTone: .secondary
                )
            )
        }

        return lines
    }

    private static func cadenceSummaryText(
        _ cadence: SupervisorCadenceExplainability,
        selector: KeyPath<SupervisorCadenceDimensionExplainability, Int>
    ) -> String {
        [
            "心跳 \(governanceDisplayDurationLabel(cadence.progressHeartbeat[keyPath: selector]))",
            "脉冲 \(governanceDisplayDurationLabel(cadence.reviewPulse[keyPath: selector]))",
            "脑暴 \(governanceDisplayDurationLabel(cadence.brainstormReview[keyPath: selector]))"
        ].joined(separator: " · ")
    }

    private static func cadenceReasonSummaryText(
        _ cadence: SupervisorCadenceExplainability
    ) -> String {
        [
            cadenceDimensionReasonSummary("心跳", dimension: cadence.progressHeartbeat),
            cadenceDimensionReasonSummary("脉冲", dimension: cadence.reviewPulse),
            cadenceDimensionReasonSummary("脑暴", dimension: cadence.brainstormReview)
        ].joined(separator: " | ")
    }

    private static func cadenceDueSummaryText(
        _ cadence: SupervisorCadenceExplainability
    ) -> String {
        [
            cadenceDimensionDueSummary("心跳", dimension: cadence.progressHeartbeat),
            cadenceDimensionDueSummary("脉冲", dimension: cadence.reviewPulse),
            cadenceDimensionDueSummary("脑暴", dimension: cadence.brainstormReview)
        ].joined(separator: " | ")
    }

    private static func cadenceDimensionReasonSummary(
        _ title: String,
        dimension: SupervisorCadenceDimensionExplainability
    ) -> String {
        "\(title)：\(localizedCadenceReasonCodes(dimension.effectiveReasonCodes))"
    }

    private static func cadenceDimensionDueSummary(
        _ title: String,
        dimension: SupervisorCadenceDimensionExplainability
    ) -> String {
        let state = dimension.isDue ? "已到期" : "未到期"
        return "\(title)：\(state)，\(localizedCadenceReasonCodes(dimension.nextDueReasonCodes))"
    }

    private static func localizedCadenceReasonCodes(_ codes: [String]) -> String {
        HeartbeatGovernanceUserFacingText.cadenceReasonSummary(codes, empty: "无")
    }

    private static func localizedCadenceReasonCode(_ code: String) -> String {
        HeartbeatGovernanceUserFacingText.cadenceReasonText(code) ?? code
    }

    private static func guidanceReview(
        snapshot: SupervisorProjectDrillDownSnapshot,
        guidance: SupervisorGuidanceInjectionRecord
    ) -> SupervisorReviewNoteRecord? {
        guard let review = snapshot.latestReview,
              review.reviewId == guidance.reviewId else {
            return nil
        }
        return review
    }

    private static func structuredGuidanceLines(
        prefix: String,
        guidance: SupervisorGuidanceInjectionRecord,
        review: SupervisorReviewNoteRecord?,
        primaryTone: SupervisorProjectDrillDownLineTone
    ) -> [SupervisorProjectDrillDownLinePresentation] {
        guard let contract = SupervisorGuidanceContractResolver.resolve(
            guidance: guidance,
            reviewNote: review
        ) else {
            return [
                line(
                    id: "\(prefix)-text",
                    text: "指导：\(governanceScalar(SupervisorGuidanceTextPresentation.summary(guidance.guidanceText, maxChars: 220)))",
                    tone: .secondary,
                    lineLimit: 3
                )
            ]
        }

        var lines: [SupervisorProjectDrillDownLinePresentation] = [
            line(
                id: "\(prefix)-contract",
                text: "指导合同：\(contract.kindText)",
                tone: primaryTone
            ),
            line(
                id: "\(prefix)-summary",
                text: "摘要：\(contract.summaryText)",
                tone: .secondary,
                lineLimit: 3
            )
        ]

        if let uiReview = contract.uiReviewRepair {
            lines.append(
                line(
                    id: "\(prefix)-repair",
                    text: "修复：\(uiReview.repairAction.isEmpty ? "(none)" : uiReview.repairAction) · 焦点：\(uiReview.repairFocus.isEmpty ? "(none)" : uiReview.repairFocus)",
                    tone: primaryTone,
                    lineLimit: 3
                )
            )
            if !uiReview.instruction.isEmpty {
                lines.append(
                    line(
                        id: "\(prefix)-instruction",
                        text: "说明：\(uiReview.instruction)",
                        tone: .secondary,
                        lineLimit: 3
                    )
                )
            }
        } else if !contract.primaryBlocker.isEmpty {
            if let blockerLine = SupervisorBlockerPresentation.blockerLine(contract.primaryBlocker) {
                lines.append(
                    line(
                        id: "\(prefix)-blocker",
                        text: blockerLine,
                        tone: primaryTone,
                        lineLimit: 3
                    )
                )
            }
        }

        lines.append(
            line(
                id: "\(prefix)-next-safe-action",
                text: "下一个安全动作：\(contract.userVisibleNextSafeActionText)",
                tone: .secondary
            )
        )

        if let actions = contract.userVisibleRecommendedActionsText {
            lines.append(
                line(
                    id: "\(prefix)-recommended-actions",
                    text: "建议动作：\(actions)",
                    tone: .secondary,
                    lineLimit: 3
                )
            )
        }

        return lines
    }

    private static func projectAIStrengthText(
        band: AXProjectAIStrengthBand?,
        confidence: Double?
    ) -> String {
        guard let band else { return "无" }
        guard let confidence else { return band.displayName }
        let normalized = max(0, min(1, confidence))
        return "\(band.displayName) · conf=\(Int((normalized * 100).rounded()))%"
    }

    private static func guidanceAckText(_ record: SupervisorGuidanceInjectionRecord) -> String {
        "\(record.ackStatus.displayName) · \(record.ackRequired ? "required" : "optional")"
    }

    private static func governanceScalar(_ value: String?) -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "无" : trimmed
    }

    private static func specScalar(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "（缺失）" : trimmed
    }

    private static func scalarTone(
        _ value: String,
        primaryTone: SupervisorProjectDrillDownLineTone
    ) -> SupervisorProjectDrillDownLineTone {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .warning : primaryTone
    }

    private static func listSummary(_ values: [String]) -> String {
        let normalized = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return "（缺失）" }
        return normalized.joined(separator: ", ")
    }

    private static func milestoneSummary(
        _ milestones: [SupervisorProjectSpecMilestone]
    ) -> String {
        let titles = milestones
            .map(\.title)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !titles.isEmpty else { return "（缺失）" }

        let visible = Array(titles.prefix(3))
        if titles.count > visible.count {
            return visible.joined(separator: ", ") + " +\(titles.count - visible.count)项"
        }
        return visible.joined(separator: ", ")
    }

    private static func summarizedIDs(_ values: [String], maxVisible: Int = 3) -> String {
        let normalized = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return "无" }

        let visible = Array(normalized.prefix(maxVisible))
        if normalized.count > visible.count {
            return visible.joined(separator: ", ") + " +\(normalized.count - visible.count)项"
        }
        return visible.joined(separator: ", ")
    }

    private static func backgroundNoteCountText(_ count: Int) -> String {
        "\(count) 条背景偏好"
    }

    private static func localizedDecisionCategory(_ category: SupervisorDecisionCategory) -> String {
        switch category {
        case .techStack:
            return "技术栈"
        case .scopeFreeze:
            return "范围冻结"
        case .riskPosture:
            return "风险策略"
        case .approvalResult:
            return "审批结果"
        case .uiStyle:
            return "界面风格"
        default:
            return category.rawValue.replacingOccurrences(of: "_", with: " ")
        }
    }

    private static func localizedBackgroundDomain(_ domain: SupervisorBackgroundPreferenceDomain) -> String {
        switch domain {
        case .techStack:
            return "技术栈"
        case .uxStyle:
            return "界面风格"
        default:
            return domain.rawValue.replacingOccurrences(of: "_", with: " ")
        }
    }

    private static func localizedBackgroundStrength(_ strength: SupervisorBackgroundPreferenceStrength) -> String {
        switch strength {
        case .weak:
            return "弱"
        case .medium:
            return "中"
        case .strong:
            return "强"
        }
    }

    private static func localizedSpecField(_ field: SupervisorProjectSpecField) -> String {
        switch field {
        case .goal:
            return "目标"
        case .mvpDefinition:
            return "MVP 定义"
        case .nonGoals:
            return "非目标"
        case .approvedTechStack:
            return "技术栈"
        case .milestones:
            return "里程碑"
        }
    }

    private static func decisionAssistTimeoutText(_ timeoutMs: Int64) -> String {
        let seconds = max(1, timeoutMs / 1_000)
        if seconds % 3_600 == 0 {
            return "\(seconds / 3_600)h"
        }
        if seconds % 60 == 0 {
            return "\(seconds / 60)m"
        }
        return "\(seconds)s"
    }

    private static func decisionAssistGuardText(
        _ assist: SupervisorDecisionBlockerAssist
    ) -> String {
        if assist.failClosed {
            return "guard: fail-closed until explicit approval"
        }
        if assist.governanceMode == .autoAdoptIfPolicyAllows {
            return "guard: stays proposal-only until a separate governed executor adopts it"
        }
        return "guard: remains pending until governed adoption"
    }

    private static func scopeTitle(_ scope: SupervisorProjectDrillDownScope) -> String {
        switch scope {
        case .capsuleOnly:
            return "项目摘要"
        case .capsulePlusRecent:
            return "摘要+最近对话"
        case .rawEvidence:
            return "原始证据"
        }
    }

    private static func openedReasonLabel(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "explicit_portfolio_drilldown":
            return "从项目看板打开"
        case "explicit_project_detail":
            return "从项目详情打开"
        case "manual_request":
            return "手动查看"
        default:
            return "已打开"
        }
    }

    private static func line(
        id: String,
        text: String,
        tone: SupervisorProjectDrillDownLineTone,
        monospaced: Bool = false,
        lineLimit: Int? = 2
    ) -> SupervisorProjectDrillDownLinePresentation {
        SupervisorProjectDrillDownLinePresentation(
            id: id,
            text: text,
            tone: tone,
            monospaced: monospaced,
            lineLimit: lineLimit
        )
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
