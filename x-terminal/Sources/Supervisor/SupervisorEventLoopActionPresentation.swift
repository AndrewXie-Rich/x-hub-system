import Foundation

struct SupervisorEventLoopActionPresentation: Equatable {
    var label: String
    var url: String
    var requestId: String?

    static func action(
        for activity: SupervisorManager.SupervisorEventLoopActivity
    ) -> SupervisorEventLoopActionPresentation? {
        let triggerSource = normalizedScalar(activity.triggerSource).lowercased()
        let projectId = normalizedScalar(activity.projectId)

        if actionRequestsUIReview(activity),
           !projectId.isEmpty,
           let url = XTDeepLinkURLBuilder.projectURL(
                projectId: projectId,
                pane: .chat,
                governanceDestination: .uiReview
           )?.absoluteString {
            return SupervisorEventLoopActionPresentation(
                label: "打开 UI 审查",
                url: url,
                requestId: nil
            )
        }

        if let requestId = requestId(for: activity) {
            if !projectId.isEmpty,
               let url = XTDeepLinkURLBuilder.projectURL(
                    projectId: projectId,
                    pane: .chat,
                    openTarget: .supervisor,
                    focusTarget: .skillRecord,
                    requestId: requestId
               )?.absoluteString {
                return SupervisorEventLoopActionPresentation(
                    label: "打开记录",
                    url: url,
                    requestId: requestId
                )
            }
            if let url = XTDeepLinkURLBuilder.supervisorURL(
                focusTarget: .skillRecord,
                requestId: requestId
            )?.absoluteString {
                return SupervisorEventLoopActionPresentation(
                    label: "打开记录",
                    url: url,
                    requestId: requestId
                )
            }
        }

        if !projectId.isEmpty,
           let url = XTDeepLinkURLBuilder.projectURL(
                projectId: projectId,
                pane: .chat
           )?.absoluteString {
            return SupervisorEventLoopActionPresentation(
                label: "打开项目",
                url: url,
                requestId: nil
            )
        }

        if triggerSource == "official_skills_channel",
           let url = XTDeepLinkURLBuilder.supervisorURL()?.absoluteString {
            return SupervisorEventLoopActionPresentation(
                label: "打开 Supervisor",
                url: url,
                requestId: nil
            )
        }

        return nil
    }

    static func requestId(
        for activity: SupervisorManager.SupervisorEventLoopActivity
    ) -> String? {
        let dedupeKey = normalizedScalar(activity.dedupeKey)
        guard !dedupeKey.isEmpty else { return nil }

        let parts = dedupeKey.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }

        switch parts[0].lowercased() {
        case "skill_callback", "grant_resolution", "approval_resolution":
            let token = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            return token.isEmpty ? nil : token
        default:
            return nil
        }
    }

    private static func normalizedScalar(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func actionRequestsUIReview(
        _ activity: SupervisorManager.SupervisorEventLoopActivity
    ) -> Bool {
        normalizedScalar(activity.policySummary).lowercased().contains("next=open_ui_review")
    }
}
