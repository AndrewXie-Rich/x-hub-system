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

struct SupervisorProjectCreationStatusPresentation: Equatable {
    var priority: SupervisorHeartbeatPriority
    var priorityTone: SupervisorHeaderControlTone
    var reasonCode: String
    var headlineText: String
    var detailText: String
    var metadataText: String
    var projectNameText: String?
    var goalText: String?
    var trackText: String?
    var recommendedCommands: [String]
}

enum SupervisorSignalCenterOverviewPresentationMapper {
    static func map(
        pendingHubGrantPresentation: SupervisorPendingHubGrantBoardPresentation,
        pendingSkillApprovalPresentation: SupervisorPendingSkillApprovalBoardPresentation,
        candidateReviewPresentation: SupervisorCandidateReviewBoardPresentation = SupervisorCandidateReviewPresentation.board(
            items: [],
            source: "",
            hasFreshSnapshot: false,
            updatedAt: 0,
            inFlightRequestIDs: [],
            hubInteractive: false,
            projectNamesByID: [:],
                focusedRowAnchor: nil
        ),
        doctorPresentation: SupervisorDoctorBoardPresentation? = nil,
        projectCreationPresentation: SupervisorProjectCreationStatusPresentation? = nil,
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
                headlineText: SupervisorPendingSkillApprovalPresentation.overviewHeadline(
                    for: firstApproval
                ),
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
                    label: SupervisorPendingSkillApprovalPresentation.overviewFocusLabel(
                        for: firstApproval
                    ),
                    tone: .warning
                )
            )
        }

        if let projectCreationPresentation {
            return projectCreationOverview(
                projectCreationPresentation: projectCreationPresentation
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

        if let doctorTruthOverview = doctorTruthOverviewIfNeeded(
            doctorPresentation: doctorPresentation
        ) {
            return doctorTruthOverview
        }

        if let firstCandidateReview = candidateReviewPresentation.rows.first {
            return SupervisorSignalCenterOverviewPresentation(
                priority: .attention,
                priorityText: SupervisorHeartbeatPriority.attention.label,
                priorityTone: .accent,
                headlineText: "候选记忆待审查",
                detailText: firstCandidateReview.summary,
                metadataText: [
                    "\(candidateReviewPresentation.rows.count) 项待处理",
                    candidateReviewPresentation.snapshotText,
                    firstCandidateReview.reviewStateText,
                    firstCandidateReview.ageText
                ]
                .filter { !$0.isEmpty }
                .joined(separator: " · "),
                focusAction: SupervisorSignalCenterOverviewActionDescriptor(
                    action: .scrollToBoard(SupervisorFocusPresentation.candidateReviewBoardAnchorID),
                    label: "查看候选审查",
                    tone: .accent
                )
            )
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

    private static func doctorTruthOverviewIfNeeded(
        doctorPresentation: SupervisorDoctorBoardPresentation?
    ) -> SupervisorSignalCenterOverviewPresentation? {
        guard let doctorPresentation,
              let statusLine = trimmedRuntimeValue(doctorPresentation.skillDoctorTruthStatusLine),
              let detailLine = trimmedRuntimeValue(doctorPresentation.skillDoctorTruthDetailLine) else {
            return nil
        }

        let priorityTone = doctorPresentation.skillDoctorTruthTone
        let priority: SupervisorHeartbeatPriority
        switch doctorPresentation.skillDoctorTruthTone {
        case .danger:
            priority = .attention
        case .warning:
            priority = .attention
        case .accent:
            priority = .watch
        case .success, .neutral:
            return nil
        }

        return SupervisorSignalCenterOverviewPresentation(
            priority: priority,
            priorityText: priority.label,
            priorityTone: priorityTone,
            headlineText: "技能 doctor truth 需要处理",
            detailText: statusLine,
            metadataText: detailLine,
            focusAction: SupervisorSignalCenterOverviewActionDescriptor(
                action: .scrollToBoard(SupervisorFocusPresentation.doctorBoardAnchorID),
                label: "查看体检",
                tone: priorityTone
            )
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
        let detailText = sanitizedLaneHealthOverviewText(firstAbnormalRow?.reasonLine)
            ?? sanitizedLaneHealthOverviewText(laneHealthPresentation.statusLine)
            ?? laneHealthPresentation.summaryLine

        return SupervisorSignalCenterOverviewPresentation(
            priority: priority,
            priorityText: priority.label,
            priorityTone: priorityTone,
            headlineText: "泳道健康需要关注",
            detailText: detailText,
            metadataText: [
                sanitizedLaneHealthOverviewText(firstAbnormalRow?.title),
                sanitizedLaneHealthOverviewText(laneHealthPresentation.statusLine)
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

    private static func projectCreationOverview(
        projectCreationPresentation: SupervisorProjectCreationStatusPresentation
    ) -> SupervisorSignalCenterOverviewPresentation {
        let metadataText = [
            trimmedRuntimeValue(projectCreationPresentation.metadataText),
            "诊断码：\(projectCreationPresentation.reasonCode)"
        ]
        .compactMap { $0 }
        .joined(separator: " · ")

        return SupervisorSignalCenterOverviewPresentation(
            priority: projectCreationPresentation.priority,
            priorityText: projectCreationPresentation.priority.label,
            priorityTone: projectCreationPresentation.priorityTone,
            headlineText: projectCreationPresentation.headlineText,
            detailText: projectCreationPresentation.detailText,
            metadataText: metadataText,
            focusAction: SupervisorSignalCenterOverviewActionDescriptor(
                action: .scrollToBoard(SupervisorFocusPresentation.projectCreationBoardAnchorID),
                label: "查看创建状态",
                tone: projectCreationPresentation.priorityTone
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

    private static func sanitizedLaneHealthOverviewText(_ raw: String?) -> String? {
        guard let trimmed = trimmedRuntimeValue(raw) else { return nil }
        let stripped = trimmed
            .replacingOccurrences(of: #"（[a-z0-9_]+）"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }
}

typealias SupervisorOperationsOverviewPresentationMapper = SupervisorSignalCenterOverviewPresentationMapper
