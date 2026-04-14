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
        let grantRequestId = normalizedScalar(activity.grantRequestId)
        let grantCapability = normalizedScalar(activity.grantCapability)

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

        if requestId(for: activity) == nil,
           (!grantRequestId.isEmpty || !grantCapability.isEmpty) {
            if !projectId.isEmpty,
               let url = XTDeepLinkURLBuilder.projectURL(
                    projectId: projectId,
                    pane: .chat,
                    openTarget: .supervisor,
                    grantRequestId: grantRequestId.isEmpty ? nil : grantRequestId,
                    grantCapability: grantCapability.isEmpty ? nil : grantCapability
               )?.absoluteString {
                return SupervisorEventLoopActionPresentation(
                    label: "打开授权",
                    url: url,
                    requestId: nil
                )
            }
            if let url = XTDeepLinkURLBuilder.supervisorURL(
                grantRequestId: grantRequestId.isEmpty ? nil : grantRequestId,
                grantCapability: grantCapability.isEmpty ? nil : grantCapability
            )?.absoluteString {
                return SupervisorEventLoopActionPresentation(
                    label: "打开授权",
                    url: url,
                    requestId: nil
                )
            }
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

        if normalizedScalar(activity.reasonCode).lowercased() == "memory_scoped_hidden_project_recovery_missing",
           let url = XTDeepLinkURLBuilder.settingsURL(
                sectionId: "diagnostics",
                title: "补回 hidden project 上下文",
                detail: "打开诊断，检查 explicit hidden project focus 是否补回项目范围上下文。",
                refreshReason: "supervisor_event_loop_hidden_project_scoped_recovery"
           )?.absoluteString {
            return SupervisorEventLoopActionPresentation(
                label: "打开诊断",
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
