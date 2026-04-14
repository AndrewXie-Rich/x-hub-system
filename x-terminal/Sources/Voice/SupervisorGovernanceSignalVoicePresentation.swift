import Foundation

struct SupervisorGovernanceSignalVoicePresentation: Equatable {
    var trigger: SupervisorVoiceJobTrigger
    var headlineText: String
    var detailText: String
    var metadataText: String
    var actionText: String?
    var fingerprint: String
}

enum SupervisorGovernanceSignalVoicePresentationMapper {
    static func map(
        overview: SupervisorSignalCenterOverviewPresentation?
    ) -> SupervisorGovernanceSignalVoicePresentation? {
        guard let overview,
              overview.priority != .stable else {
            return nil
        }

        return SupervisorGovernanceSignalVoicePresentation(
            trigger: trigger(for: overview),
            headlineText: overview.headlineText,
            detailText: overview.detailText,
            metadataText: sanitizedMetadataText(for: overview),
            actionText: actionText(for: overview),
            fingerprint: overview.signalFingerprint
        )
    }

    private static func trigger(
        for overview: SupervisorSignalCenterOverviewPresentation
    ) -> SupervisorVoiceJobTrigger {
        if let focusAction = overview.focusAction {
            switch focusAction.action {
            case .scrollToBoard(let anchorID):
                if anchorID == SupervisorFocusPresentation.pendingHubGrantBoardAnchorID ||
                    anchorID == SupervisorFocusPresentation.pendingSupervisorSkillApprovalBoardAnchorID {
                    return .authorization
                }
            }
        }

        switch overview.priority {
        case .immediate, .attention:
            return .blocked
        case .watch, .stable:
            return .completed
        }
    }

    private static func trimmedNonEmpty(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func actionText(
        for overview: SupervisorSignalCenterOverviewPresentation
    ) -> String? {
        if isProjectCreationOverview(overview) {
            return projectCreationActionText(for: overview)
        }
        if let doctorTruthAction = doctorTruthActionText(for: overview) {
            return doctorTruthAction
        }
        return trimmedNonEmpty(overview.focusAction?.label)
    }

    private static func sanitizedMetadataText(
        for overview: SupervisorSignalCenterOverviewPresentation
    ) -> String {
        let segments = overview.metadataText
            .split(separator: "·")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { segment in
                let normalized = normalizedSegment(segment)
                return !normalized.isEmpty
                    && !normalized.hasPrefix(normalizedSegment("诊断码："))
                    && !normalized.hasPrefix(normalizedSegment("diagnostic code:"))
                    && !normalized.hasPrefix(normalizedSegment("reason code:"))
            }
        return segments.joined(separator: " · ")
    }

    private static func isProjectCreationOverview(
        _ overview: SupervisorSignalCenterOverviewPresentation
    ) -> Bool {
        guard let focusAction = overview.focusAction else { return false }
        switch focusAction.action {
        case .scrollToBoard(let anchorID):
            return anchorID == SupervisorFocusPresentation.projectCreationBoardAnchorID
        }
    }

    private static func projectCreationActionText(
        for overview: SupervisorSignalCenterOverviewPresentation
    ) -> String? {
        let headline = normalizedSegment(overview.headlineText)
        if headline.contains(normalizedSegment("项目创建差一句触发")) {
            return "直接说立项，或说创建一个project"
        }
        if headline.contains(normalizedSegment("项目创建待确认")) {
            return "直接说立项，或说就按这个建"
        }
        if headline.contains(normalizedSegment("项目已创建待补目标")) {
            return "直接说我要用默认的MVP，或说第一版先做成最小可运行版本"
        }
        if headline.contains(normalizedSegment("项目创建缺目标")) {
            return "直接给项目名，或先补一句要做什么"
        }
        if headline.contains(normalizedSegment("项目创建处理中")) {
            return "等这轮创建完成"
        }
        return trimmedNonEmpty(overview.focusAction?.label)
    }

    private static func doctorTruthActionText(
        for overview: SupervisorSignalCenterOverviewPresentation
    ) -> String? {
        guard let focusAction = overview.focusAction else { return nil }
        switch focusAction.action {
        case .scrollToBoard(let anchorID):
            guard anchorID == SupervisorFocusPresentation.doctorBoardAnchorID else {
                return nil
            }
        }

        let detail = normalizedSegment(overview.detailText)
        if detail.contains(normalizedSegment("当前不可运行"))
            || detail.contains(normalizedSegment("当前阻塞")) {
            return "打开体检，先处理技能 doctor truth 阻塞项"
        }
        if detail.contains(normalizedSegment("待hubgrant"))
            || detail.contains(normalizedSegment("待本地确认")) {
            return "打开体检，先补技能 doctor truth 授权和确认"
        }
        return "打开体检，先处理技能 doctor truth"
    }

    private static func normalizedSegment(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }
}
