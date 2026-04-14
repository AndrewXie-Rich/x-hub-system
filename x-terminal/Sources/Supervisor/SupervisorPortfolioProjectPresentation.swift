import Foundation

struct SupervisorPortfolioTagPresentation: Equatable, Identifiable {
    var id: String
    var title: String
    var tone: SupervisorHeaderControlTone
}

struct SupervisorPortfolioProjectRowPresentation: Equatable, Identifiable {
    var id: String
    var displayName: String
    var stateText: String
    var stateTone: SupervisorHeaderControlTone
    var freshnessText: String
    var freshnessTone: SupervisorHeaderControlTone
    var recentText: String
    var selectionButtonTitle: String
    var isSelected: Bool
    var actionabilityTags: [SupervisorPortfolioTagPresentation]
    var governanceTags: [SupervisorPortfolioTagPresentation]
    var priorityLine: String? = nil
    var priorityTone: SupervisorHeaderControlTone? = nil
    var uiReviewSummaryLine: String?
    var uiReviewTone: SupervisorHeaderControlTone?
    var actionLine: String
    var nextLine: String
    var blockerLine: String?
}

enum SupervisorPortfolioProjectRowPresentationMapper {
    static func map(
        card: SupervisorPortfolioProjectCard,
        actionabilityItems: [SupervisorPortfolioActionabilityItem],
        isSelected: Bool,
        governed: AXProjectGovernedAuthorityPresentation?,
        templatePreview: AXProjectGovernanceTemplatePreview?,
        latestUIReview: XTUIReviewPresentation?
    ) -> SupervisorPortfolioProjectRowPresentation {
        SupervisorPortfolioProjectRowPresentation(
            id: card.projectId,
            displayName: card.displayName,
            stateText: stateText(card.projectState),
            stateTone: stateTone(card.projectState),
            freshnessText: freshnessText(card.memoryFreshness),
            freshnessTone: freshnessTone(card.memoryFreshness),
            recentText: "最近 \(card.recentMessageCount) 条",
            selectionButtonTitle: isSelected ? "已选中" : "查看",
            isSelected: isSelected,
            actionabilityTags: actionabilityItems.map(actionabilityTag),
            governanceTags: governanceTags(
                card: card,
                governed: governed,
                templatePreview: templatePreview
            ),
            priorityLine: priorityLine(card),
            priorityTone: priorityTone(card),
            uiReviewSummaryLine: latestUIReview?.compactStatusText,
            uiReviewTone: latestUIReview.map(uiReviewTone),
            actionLine: "当前动作：\(card.currentAction)",
            nextLine: "下一步：\(card.nextStep)",
            blockerLine: normalizedBlockerLine(card.topBlocker)
        )
    }

    static func actionabilityTag(
        _ item: SupervisorPortfolioActionabilityItem
    ) -> SupervisorPortfolioTagPresentation {
        SupervisorPortfolioTagPresentation(
            id: item.id,
            title: SupervisorPortfolioOverviewPresentationMapper.actionabilityLabel(item.kind),
            tone: actionabilityTone(item.kind)
        )
    }

    static func governanceTags(
        card: SupervisorPortfolioProjectCard,
        governed: AXProjectGovernedAuthorityPresentation?,
        templatePreview: AXProjectGovernanceTemplatePreview?
    ) -> [SupervisorPortfolioTagPresentation] {
        var tags: [SupervisorPortfolioTagPresentation] = []

        if let templatePreview {
            tags.append(
                SupervisorPortfolioTagPresentation(
                    id: "profile:\(templatePreview.configuredProfile.rawValue)",
                    title: templatePreview.configuredProfile.displayName,
                    tone: profileTone(templatePreview.configuredProfile)
                )
            )
            if templatePreview.hasConfiguredEffectiveDrift {
                tags.append(
                    SupervisorPortfolioTagPresentation(
                        id: "runtime-profile:\(templatePreview.effectiveProfile.rawValue)",
                        title: "运行时 \(templatePreview.effectiveProfile.displayName)",
                        tone: profileTone(templatePreview.effectiveProfile)
                    )
                )
            }
            tags.append(
                SupervisorPortfolioTagPresentation(
                    id: "device-authority:\(templatePreview.effectiveDeviceAuthorityPosture.rawValue)",
                    title: templatePreview.effectiveDeviceAuthorityPosture.displayName,
                    tone: .success
                )
            )
            tags.append(
                SupervisorPortfolioTagPresentation(
                    id: "grant-posture:\(templatePreview.effectiveGrantPosture.rawValue)",
                    title: templatePreview.effectiveGrantPosture.displayName,
                    tone: .warning
                )
            )
            if governed?.localAutoApproveConfigured == true {
                tags.append(
                    SupervisorPortfolioTagPresentation(
                        id: "local-auto-approve",
                        title: "本地自动批",
                        tone: .warning
                    )
                )
            }
            if let count = governed?.governedReadableRootCount, count > 0 {
                tags.append(
                    SupervisorPortfolioTagPresentation(
                        id: "readable-roots:\(count)",
                        title: "可读路径 \(count)",
                        tone: .accent
                    )
                )
            }
            tags.append(contentsOf: memoryCompactionTags(card))
            tags.append(contentsOf: decisionRailTags(card))
            tags.append(contentsOf: decisionAssistTags(card))
            return tags
        }

        if let governed, governed.hasAnyVisibleSignal, governed.governedReadableRootCount > 0 {
            tags.append(
                SupervisorPortfolioTagPresentation(
                    id: "readable-roots:\(governed.governedReadableRootCount)",
                    title: "可读路径 \(governed.governedReadableRootCount)",
                    tone: .accent
                )
            )
        }

        tags.append(contentsOf: memoryCompactionTags(card))
        tags.append(contentsOf: decisionRailTags(card))
        tags.append(contentsOf: decisionAssistTags(card))
        return tags
    }

    static func stateTone(
        _ state: SupervisorPortfolioProjectState
    ) -> SupervisorHeaderControlTone {
        switch state {
        case .active:
            return .accent
        case .blocked:
            return .warning
        case .awaitingAuthorization:
            return .danger
        case .completed:
            return .success
        case .idle:
            return .neutral
        }
    }

    static func freshnessTone(
        _ freshness: SupervisorPortfolioMemoryFreshness
    ) -> SupervisorHeaderControlTone {
        switch freshness {
        case .fresh:
            return .success
        case .ttlCached:
            return .warning
        case .stale:
            return .danger
        }
    }

    static func stateText(
        _ state: SupervisorPortfolioProjectState
    ) -> String {
        switch state {
        case .active:
            return "进行中"
        case .blocked:
            return "阻塞"
        case .awaitingAuthorization:
            return "待授权"
        case .completed:
            return "已完成"
        case .idle:
            return "暂停中"
        }
    }

    static func freshnessText(
        _ freshness: SupervisorPortfolioMemoryFreshness
    ) -> String {
        switch freshness {
        case .fresh:
            return "新鲜"
        case .ttlCached:
            return "缓存"
        case .stale:
            return "过期"
        }
    }

    static func actionabilityTone(
        _ kind: SupervisorPortfolioActionabilityKind
    ) -> SupervisorHeaderControlTone {
        switch kind {
        case .decisionAssist:
            return .warning
        case .decisionBlocker:
            return .danger
        case .specGap, .decisionRail, .missingNextStep, .stalled:
            return .warning
        case .zombie:
            return .neutral
        case .activeFollowUp:
            return .accent
        }
    }

    static func profileTone(
        _ profile: AXProjectGovernanceTemplate
    ) -> SupervisorHeaderControlTone {
        switch profile {
        case .prototype, .legacyObserve:
            return .neutral
        case .feature:
            return .success
        case .largeProject, .inception:
            return .accent
        case .highGovernance:
            return .warning
        case .custom:
            return .accent
        }
    }

    static func uiReviewTone(
        _ review: XTUIReviewPresentation
    ) -> SupervisorHeaderControlTone {
        switch review.verdict {
        case .ready:
            return .success
        case .attentionNeeded:
            return .warning
        case .insufficientEvidence:
            return .danger
        }
    }

    private static func normalizedBlockerLine(_ blocker: String) -> String? {
        SupervisorBlockerPresentation.blockerLine(blocker)
    }

    private static func priorityLine(
        _ card: SupervisorPortfolioProjectCard
    ) -> String? {
        guard let priority = card.prioritySnapshot,
              priority.priorityBand == .critical || priority.priorityBand == .high else {
            return nil
        }
        return "优先级：\(priority.priorityBand.displayName) · \(SupervisorPortfolioSnapshotBuilder.priorityWhyText(for: card))"
    }

    private static func priorityTone(
        _ card: SupervisorPortfolioProjectCard
    ) -> SupervisorHeaderControlTone? {
        guard let band = card.prioritySnapshot?.priorityBand,
              band == .critical || band == .high else {
            return nil
        }
        switch band {
        case .critical:
            return .danger
        case .high:
            return .warning
        case .normal, .low:
            return nil
        }
    }

    private static func decisionRailTags(
        _ card: SupervisorPortfolioProjectCard
    ) -> [SupervisorPortfolioTagPresentation] {
        var tags: [SupervisorPortfolioTagPresentation] = []

        if card.shadowedBackgroundNoteCount > 0 {
            tags.append(
                SupervisorPortfolioTagPresentation(
                    id: "decision-wins:\(card.projectId)",
                    title: card.shadowedBackgroundNoteCount == 1
                        ? "正式决策优先"
                        : "正式决策优先 \(card.shadowedBackgroundNoteCount)",
                    tone: .warning
                )
            )
        }

        if card.weakOnlyBackgroundNoteCount > 0 {
            tags.append(
                SupervisorPortfolioTagPresentation(
                    id: "weak-only:\(card.projectId)",
                    title: card.weakOnlyBackgroundNoteCount == 1
                        ? "弱约束"
                        : "弱约束 \(card.weakOnlyBackgroundNoteCount)",
                    tone: .neutral
                )
            )
        }

        return tags
    }

    private static func memoryCompactionTags(
        _ card: SupervisorPortfolioProjectCard
    ) -> [SupervisorPortfolioTagPresentation] {
        guard let signal = card.memoryCompactionSignal else { return [] }

        if signal.archiveCandidate {
            return [
                SupervisorPortfolioTagPresentation(
                    id: "memory-compaction-archive:\(card.projectId)",
                    title: signal.archivedCount > 0
                        ? "归档候选 \(signal.archivedCount)"
                        : "归档候选",
                    tone: .warning
                )
            ]
        }

        guard signal.rolledUpCount > 0 else { return [] }
        return [
            SupervisorPortfolioTagPresentation(
                id: "memory-compaction-rollup:\(card.projectId)",
                title: "已收口 \(signal.rolledUpCount)",
                tone: .accent
            )
        ]
    }

    private static func decisionAssistTags(
        _ card: SupervisorPortfolioProjectCard
    ) -> [SupervisorPortfolioTagPresentation] {
        guard let assist = card.decisionAssist else { return [] }
        return [
            SupervisorPortfolioTagPresentation(
                id: "decision-assist:\(card.projectId)",
                title: decisionAssistTagTitle(assist),
                tone: assist.failClosed ? .danger : .warning
            )
        ]
    }

    private static func decisionAssistTagTitle(
        _ assist: SupervisorDecisionBlockerAssist
    ) -> String {
        switch assist.blockerCategory {
        case .techStack:
            return assist.failClosed ? "技术栈需审批" : "技术栈建议"
        case .scaffold:
            return assist.failClosed ? "脚手架需审批" : "脚手架建议"
        case .testStack:
            return assist.failClosed ? "测试栈需审批" : "测试栈建议"
        case .docTemplate:
            return assist.failClosed ? "文档模板需审批" : "文档模板建议"
        case .security:
            return "安全需审批"
        case .releaseScope:
            return "发版需审批"
        case .irreversibleOperation:
            return "不可逆需审批"
        case .other:
            return assist.failClosed ? "决策需审批" : "决策建议"
        }
    }
}
