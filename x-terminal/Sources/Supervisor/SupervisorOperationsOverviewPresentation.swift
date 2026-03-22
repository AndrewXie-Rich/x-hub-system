import Foundation

enum SupervisorSignalCenterOverviewAction: Equatable {
    case scrollToBoard(String)
}

struct SupervisorSignalCenterOverviewActionDescriptor: Equatable {
    var action: SupervisorSignalCenterOverviewAction
    var label: String
    var tone: SupervisorHeaderControlTone
}

typealias SupervisorOperationsOverviewAction = SupervisorSignalCenterOverviewAction
typealias SupervisorOperationsOverviewActionDescriptor = SupervisorSignalCenterOverviewActionDescriptor

struct SupervisorSignalCenterOverviewPresentation: Equatable {
    var priority: SupervisorHeartbeatPriority
    var priorityText: String
    var priorityTone: SupervisorHeaderControlTone
    var headlineText: String
    var detailText: String
    var metadataText: String
    var focusAction: SupervisorSignalCenterOverviewActionDescriptor?

    var shouldPulseHeader: Bool {
        priority != .stable
    }

    var signalFingerprint: String {
        [
            String(priority.rawValue),
            priorityTone.rawValue,
            headlineText,
            detailText,
            metadataText,
            focusAction?.label ?? "",
            focusActionFingerprint
        ]
        .joined(separator: "|")
    }

    private var focusActionFingerprint: String {
        guard let focusAction else { return "none" }
        switch focusAction.action {
        case .scrollToBoard(let anchorID):
            return "scrollToBoard:\(anchorID):\(focusAction.tone.rawValue)"
        }
    }
}

typealias SupervisorOperationsOverviewPresentation = SupervisorSignalCenterOverviewPresentation

enum SupervisorSignalCenterOverviewPresentationMapper {
    static func map(
        pendingHubGrantPresentation: SupervisorPendingHubGrantBoardPresentation,
        pendingSkillApprovalPresentation: SupervisorPendingSkillApprovalBoardPresentation,
        runtimeActivityPresentation: SupervisorRuntimeActivityBoardPresentation,
        automationPresentation: SupervisorAutomationRuntimePresentation,
        laneHealthPresentation: SupervisorLaneHealthBoardPresentation
    ) -> SupervisorSignalCenterOverviewPresentation {
        if let firstGrant = pendingHubGrantPresentation.rows.first {
            return SupervisorSignalCenterOverviewPresentation(
                priority: .immediate,
                priorityText: SupervisorHeartbeatPriority.immediate.label,
                priorityTone: .warning,
                headlineText: "Hub 待处理授权",
                detailText: firstGrant.nextActionText ?? firstGrant.summary,
                metadataText: [
                    "\(pendingHubGrantPresentation.rows.count) 项待处理",
                    pendingHubGrantPresentation.snapshotText,
                    firstGrant.ageText
                ]
                .filter { !$0.isEmpty }
                .joined(separator: " · "),
                focusAction: SupervisorSignalCenterOverviewActionDescriptor(
                    action: .scrollToBoard(SupervisorFocusPresentation.pendingHubGrantBoardAnchorID),
                    label: "查看授权板",
                    tone: .warning
                )
            )
        }

        if let firstApproval = pendingSkillApprovalPresentation.rows.first {
            return SupervisorSignalCenterOverviewPresentation(
                priority: .immediate,
                priorityText: SupervisorHeartbeatPriority.immediate.label,
                priorityTone: .warning,
                headlineText: "待审批技能",
                detailText: firstApproval.nextStepText ?? firstApproval.summary,
                metadataText: [
                    "\(pendingSkillApprovalPresentation.rows.count) 项待处理",
                    pendingSkillApprovalPresentation.modeText,
                    firstApproval.ageText,
                    trimmedRuntimeValue(firstApproval.routingExplanationText)
                ]
                .compactMap { $0 }
                .joined(separator: " · "),
                focusAction: SupervisorSignalCenterOverviewActionDescriptor(
                    action: .scrollToBoard(
                        SupervisorFocusPresentation.pendingSupervisorSkillApprovalBoardAnchorID
                    ),
                    label: "查看技能审批",
                    tone: .warning
                )
            )
        }

        if let automationOverview = automationOverviewIfNeeded(
            automationPresentation: automationPresentation
        ) {
            return automationOverview
        }

        switch automationPresentation.iconTone {
        case .danger:
            return automationOverview(
                priority: .immediate,
                priorityTone: .danger,
                headlineText: "自动化执行失败",
                automationPresentation: automationPresentation
            )
        case .warning:
            return automationOverview(
                priority: .attention,
                priorityTone: .warning,
                headlineText: "自动化执行需要关注",
                automationPresentation: automationPresentation
            )
        case .accent, .success, .neutral:
            break
        }

        if let laneHealthOverview = laneHealthOverviewIfNeeded(
            laneHealthPresentation: laneHealthPresentation
        ) {
            return laneHealthOverview
        }

        if let firstRuntimeEvent = runtimeActivityPresentation.rows.first {
            let runtimeDetail = trimmedRuntimeValue(firstRuntimeEvent.contractText)
                ?? trimmedRuntimeValue(firstRuntimeEvent.text)
            return SupervisorSignalCenterOverviewPresentation(
                priority: .watch,
                priorityText: SupervisorHeartbeatPriority.watch.label,
                priorityTone: .accent,
                headlineText: "运行动态有新事件",
                detailText: runtimeDetail ?? "运行动态已更新",
                metadataText: [
                    runtimeActivityPresentation.countText,
                    firstRuntimeEvent.timeText,
                    trimmedRuntimeValue(firstRuntimeEvent.nextSafeActionText),
                    runtimeDetail == trimmedRuntimeValue(firstRuntimeEvent.text)
                        ? nil
                        : trimmedRuntimeValue(firstRuntimeEvent.text)
                ]
                .compactMap { $0 }
                .joined(separator: " · "),
                focusAction: SupervisorSignalCenterOverviewActionDescriptor(
                    action: .scrollToBoard(SupervisorFocusPresentation.runtimeActivityBoardAnchorID),
                    label: "查看运行动态",
                    tone: .accent
                )
            )
        }

        return SupervisorSignalCenterOverviewPresentation(
            priority: .stable,
            priorityText: SupervisorHeartbeatPriority.stable.label,
            priorityTone: .neutral,
            headlineText: "信号中心空闲",
            detailText: "当前没有待处理授权、待批技能或新的运行动态，信号中心主要保持待命。",
            metadataText: automationMetadata(automationPresentation),
            focusAction: nil
        )
    }

    private static func automationOverviewIfNeeded(
        automationPresentation: SupervisorAutomationRuntimePresentation
    ) -> SupervisorSignalCenterOverviewPresentation? {
        let contractDetail = trimmedRuntimeValue(automationPresentation.contractText)
        let nextSafeAction = trimmedRuntimeValue(automationPresentation.nextSafeActionText)

        if let contractDetail {
            let priorityTone: SupervisorHeaderControlTone
            let priority: SupervisorHeartbeatPriority

            switch automationPresentation.iconTone {
            case .danger:
                priorityTone = .danger
                priority = .immediate
            case .warning:
                priorityTone = .warning
                priority = .attention
            case .accent, .success, .neutral:
                priorityTone = .warning
                priority = .attention
            }

            return SupervisorSignalCenterOverviewPresentation(
                priority: priority,
                priorityText: priority.label,
                priorityTone: priorityTone,
                headlineText: "自动化执行需要关注",
                detailText: contractDetail,
                metadataText: [
                    nextSafeAction,
                    trimmedRuntimeValue(automationPresentation.statusLine),
                    automationMetadata(automationPresentation)
                ]
                .compactMap { $0 }
                .joined(separator: " · "),
                focusAction: SupervisorSignalCenterOverviewActionDescriptor(
                    action: .scrollToBoard(SupervisorFocusPresentation.automationRuntimeBoardAnchorID),
                    label: "查看自动化执行",
                    tone: priorityTone
                )
            )
        }

        return nil
    }

    private static func automationOverview(
        priority: SupervisorHeartbeatPriority,
        priorityTone: SupervisorHeaderControlTone,
        headlineText: String,
        automationPresentation: SupervisorAutomationRuntimePresentation
    ) -> SupervisorSignalCenterOverviewPresentation {
        SupervisorSignalCenterOverviewPresentation(
            priority: priority,
            priorityText: priority.label,
            priorityTone: priorityTone,
            headlineText: headlineText,
            detailText: automationPresentation.statusLine,
            metadataText: automationMetadata(automationPresentation),
            focusAction: SupervisorSignalCenterOverviewActionDescriptor(
                action: .scrollToBoard(SupervisorFocusPresentation.automationRuntimeBoardAnchorID),
                label: "查看自动化执行",
                tone: priorityTone
            )
        )
    }

    private static func laneHealthOverviewIfNeeded(
        laneHealthPresentation: SupervisorLaneHealthBoardPresentation
    ) -> SupervisorSignalCenterOverviewPresentation? {
        let priorityTone: SupervisorHeaderControlTone
        let priority: SupervisorHeartbeatPriority

        switch laneHealthPresentation.iconTone {
        case .danger:
            priorityTone = .danger
            priority = .immediate
        case .warning:
            priorityTone = .warning
            priority = .attention
        case .neutral, .success, .info:
            return nil
        }

        let firstAbnormalRow = laneHealthPresentation.rows.first {
            $0.statusTone == .danger || $0.statusTone == .warning
        }
        let detailText = trimmedRuntimeValue(firstAbnormalRow?.contractText)
            ?? trimmedRuntimeValue(firstAbnormalRow?.reasonLine)
            ?? laneHealthPresentation.summaryLine

        return SupervisorSignalCenterOverviewPresentation(
            priority: priority,
            priorityText: priority.label,
            priorityTone: priorityTone,
            headlineText: "泳道健康需要关注",
            detailText: detailText,
            metadataText: [
                trimmedRuntimeValue(firstAbnormalRow?.nextSafeActionText),
                trimmedRuntimeValue(firstAbnormalRow?.title),
                laneHealthPresentation.summaryLine
            ]
            .compactMap { $0 }
            .joined(separator: " · "),
            focusAction: SupervisorSignalCenterOverviewActionDescriptor(
                action: .scrollToBoard(SupervisorFocusPresentation.laneHealthBoardAnchorID),
                label: "查看泳道健康",
                tone: priorityTone
            )
        )
    }

    private static func automationMetadata(
        _ automationPresentation: SupervisorAutomationRuntimePresentation
    ) -> String {
        [
            trimmedAutomationLine(automationPresentation.projectLine?.text),
            trimmedAutomationLine(automationPresentation.recipeLine?.text)
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private static func trimmedAutomationLine(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func trimmedRuntimeValue(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

typealias SupervisorOperationsOverviewPresentationMapper = SupervisorSignalCenterOverviewPresentationMapper
