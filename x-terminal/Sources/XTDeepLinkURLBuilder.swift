import Foundation

enum XTDeepLinkURLBuilder {
    static func hubSetupURL(
        sectionId: String? = nil,
        title: String? = nil,
        detail: String? = nil,
        refreshAction: XTSectionRefreshAction? = nil,
        refreshReason: String? = nil
    ) -> URL? {
        let normalizedSectionId = normalized(sectionId)
        let normalizedTitle = normalized(title)
        let normalizedDetail = normalized(detail)
        let normalizedRefreshReason = normalized(refreshReason)

        var components = URLComponents()
        components.scheme = "xterminal"
        components.host = "hub-setup"

        var queryItems: [URLQueryItem] = []
        if let sectionId = normalizedSectionId {
            queryItems.append(URLQueryItem(name: "section_id", value: sectionId))
        }
        if let title = normalizedTitle {
            queryItems.append(URLQueryItem(name: "title", value: title))
        }
        if let detail = normalizedDetail {
            queryItems.append(URLQueryItem(name: "detail", value: detail))
        }
        if let refreshAction {
            queryItems.append(URLQueryItem(name: "refresh_action", value: refreshAction.rawValue))
        }
        if let refreshReason = normalizedRefreshReason {
            queryItems.append(URLQueryItem(name: "refresh_reason", value: refreshReason))
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }

    static func settingsURL(
        sectionId: String? = nil,
        title: String? = nil,
        detail: String? = nil,
        refreshAction: XTSectionRefreshAction? = nil,
        refreshReason: String? = nil
    ) -> URL? {
        let normalizedSectionId = normalized(sectionId)
        let normalizedTitle = normalized(title)
        let normalizedDetail = normalized(detail)
        let normalizedRefreshReason = normalized(refreshReason)

        var components = URLComponents()
        components.scheme = "xterminal"
        components.host = "settings"

        var queryItems: [URLQueryItem] = []
        if let sectionId = normalizedSectionId {
            queryItems.append(URLQueryItem(name: "section_id", value: sectionId))
        }
        if let title = normalizedTitle {
            queryItems.append(URLQueryItem(name: "title", value: title))
        }
        if let detail = normalizedDetail {
            queryItems.append(URLQueryItem(name: "detail", value: detail))
        }
        if let refreshAction {
            queryItems.append(URLQueryItem(name: "refresh_action", value: refreshAction.rawValue))
        }
        if let refreshReason = normalizedRefreshReason {
            queryItems.append(URLQueryItem(name: "refresh_reason", value: refreshReason))
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }

    static func projectURL(
        projectId: String,
        pane: AXProjectPane = .chat,
        openTarget: XTDeepLinkOpenTarget? = nil,
        resumeRequested: Bool = false,
        focusTarget: XTDeepLinkFocusTarget? = nil,
        governanceDestination: XTProjectGovernanceDestination? = nil,
        requestId: String? = nil,
        grantRequestId: String? = nil,
        grantCapability: String? = nil,
        grantReason: String? = nil
    ) -> URL? {
        let projectToken = normalized(projectId)
        guard let projectToken else { return nil }
        let normalizedRequestId = normalized(requestId)
        let normalizedGrantRequestId = normalized(grantRequestId)
        let normalizedGrantCapability = normalized(grantCapability)
        let normalizedGrantReason = normalized(grantReason)
        let resolvedFocusTarget = resolvedFocusTarget(
            explicit: focusTarget,
            requestId: normalizedRequestId,
            grantRequestId: normalizedGrantRequestId,
            grantCapability: normalizedGrantCapability
        )

        var components = URLComponents()
        components.scheme = "xterminal"
        components.host = "project"

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "project_id", value: projectToken),
            URLQueryItem(name: "pane", value: pane.rawValue),
        ]
        if resumeRequested {
            queryItems.append(URLQueryItem(name: "resume", value: "1"))
        }
        if let openTarget {
            queryItems.append(URLQueryItem(name: "open", value: openTargetQueryValue(openTarget)))
        }
        if let resolvedFocusTarget {
            queryItems.append(URLQueryItem(name: "focus", value: focusTargetQueryValue(resolvedFocusTarget)))
        }
        if let governanceDestination {
            queryItems.append(
                URLQueryItem(
                    name: "governance_destination",
                    value: governanceDestination.rawValue
                )
            )
        }
        if let requestId = normalizedRequestId {
            queryItems.append(URLQueryItem(name: "request_id", value: requestId))
        }
        if let grantRequestId = normalizedGrantRequestId {
            queryItems.append(URLQueryItem(name: "grant_request_id", value: grantRequestId))
        }
        if let grantCapability = normalizedGrantCapability {
            queryItems.append(URLQueryItem(name: "grant_capability", value: grantCapability))
        }
        if let grantReason = normalizedGrantReason {
            queryItems.append(URLQueryItem(name: "grant_reason", value: grantReason))
        }
        components.queryItems = queryItems
        return components.url
    }

    static func projectPathURL(
        projectId: String,
        pane: AXProjectPane = .chat,
        openTarget: XTDeepLinkOpenTarget? = nil,
        resumeRequested: Bool = false
    ) -> URL? {
        let projectToken = normalized(projectId)
        guard let projectToken else { return nil }

        var components = URLComponents()
        components.scheme = "xterminal"
        components.host = "project"
        components.path = "/\(projectToken)"

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "pane", value: pane.rawValue),
        ]
        if resumeRequested {
            queryItems.append(URLQueryItem(name: "action", value: "resume"))
        }
        if let openTarget {
            queryItems.append(URLQueryItem(name: "open", value: openTargetQueryValue(openTarget)))
        }
        components.queryItems = queryItems
        return components.url
    }

    static func supervisorURL(
        focusTarget: XTDeepLinkFocusTarget? = nil,
        requestId: String? = nil,
        grantRequestId: String? = nil,
        grantCapability: String? = nil
    ) -> URL? {
        let normalizedRequestId = normalized(requestId)
        let normalizedGrantRequestId = normalized(grantRequestId)
        let normalizedGrantCapability = normalized(grantCapability)
        let resolvedFocusTarget = resolvedFocusTarget(
            explicit: focusTarget,
            requestId: normalizedRequestId,
            grantRequestId: normalizedGrantRequestId,
            grantCapability: normalizedGrantCapability
        )

        var components = URLComponents()
        components.scheme = "xterminal"
        components.host = "supervisor"

        var queryItems: [URLQueryItem] = []
        if let resolvedFocusTarget {
            queryItems.append(URLQueryItem(name: "focus", value: focusTargetQueryValue(resolvedFocusTarget)))
        }
        if let requestId = normalizedRequestId {
            queryItems.append(URLQueryItem(name: "request_id", value: requestId))
        }
        if let grantRequestId = normalizedGrantRequestId {
            queryItems.append(URLQueryItem(name: "grant_request_id", value: grantRequestId))
        }
        if let grantCapability = normalizedGrantCapability {
            queryItems.append(URLQueryItem(name: "grant_capability", value: grantCapability))
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }

    static func supervisorSettingsURL() -> URL? {
        var components = URLComponents()
        components.scheme = "xterminal"
        components.host = "supervisor-settings"
        return components.url
    }

    static func supervisorModelSettingsURL(
        title: String? = nil,
        detail: String? = nil
    ) -> URL? {
        let normalizedTitle = normalized(title)
        let normalizedDetail = normalized(detail)

        var components = URLComponents()
        components.scheme = "xterminal"
        components.host = "supervisor-model-settings"

        var queryItems: [URLQueryItem] = []
        if let title = normalizedTitle {
            queryItems.append(URLQueryItem(name: "title", value: title))
        }
        if let detail = normalizedDetail {
            queryItems.append(URLQueryItem(name: "detail", value: detail))
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }

    private static func openTargetQueryValue(_ target: XTDeepLinkOpenTarget) -> String {
        switch target {
        case .supervisor:
            return "supervisor"
        case .supervisorSettings:
            return "supervisor_settings"
        }
    }

    private static func focusTargetQueryValue(_ target: XTDeepLinkFocusTarget) -> String {
        switch target {
        case .grant:
            return "grant"
        case .approval:
            return "approval"
        case .candidateReview:
            return "candidate_review"
        case .skillRecord:
            return "skill_record"
        case .projectCreationBoard:
            return "project_creation_board"
        case .toolApproval:
            return "tool_approval"
        case .routeDiagnose:
            return "route_diagnose"
        }
    }

    private static func resolvedFocusTarget(
        explicit: XTDeepLinkFocusTarget?,
        requestId: String?,
        grantRequestId: String?,
        grantCapability: String?
    ) -> XTDeepLinkFocusTarget? {
        if let explicit {
            return explicit
        }
        if grantRequestId != nil || grantCapability != nil {
            return .grant
        }
        if requestId != nil {
            return .approval
        }
        return nil
    }

    private static func normalized(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
