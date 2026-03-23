import Foundation

struct XTDeepLinkGrantPrefillIntent: Equatable {
    var projectId: String
    var grantRequestId: String
    var capability: String?
    var reason: String?
}

enum XTDeepLinkFocusIntent: Equatable {
    case supervisorGrant(projectId: String?, grantRequestId: String?, capability: String?)
    case supervisorApproval(projectId: String?, requestId: String?)
    case supervisorSkillRecord(projectId: String?, requestId: String?)
    case projectToolApproval(projectId: String?, requestId: String?)
    case projectRouteDiagnose(projectId: String?)
}

struct XTDeepLinkProjectPaneIntent: Equatable {
    var projectId: String
    var pane: AXProjectPane
}

struct XTDeepLinkActionPlan: Equatable {
    var selectProjectId: String?
    var projectPaneIntent: XTDeepLinkProjectPaneIntent?
    var openSupervisorIntent: XTSupervisorWindowOpenIntent?
    var prefillGrantContext: XTDeepLinkGrantPrefillIntent?
    var focusIntent: XTDeepLinkFocusIntent?
}

enum XTDeepLinkActionPlanner {
    static func plan(for route: XTDeepLinkSupervisorRoute) -> XTDeepLinkActionPlan {
        let projectId = normalized(route.projectId)
        return XTDeepLinkActionPlan(
            selectProjectId: projectId,
            projectPaneIntent: nil,
            openSupervisorIntent: XTSupervisorWindowOpenPolicy.intent(for: route),
            prefillGrantContext: prefillIntent(
                projectId: projectId,
                grantRequestId: route.grantRequestId,
                capability: route.grantCapability,
                reason: route.grantReason
            ),
            focusIntent: focusIntent(
                projectId: projectId,
                focusTarget: route.focusTarget,
                requestId: route.requestId,
                grantRequestId: route.grantRequestId,
                grantCapability: route.grantCapability
            )
        )
    }

    static func plan(for route: XTDeepLinkProjectRoute) -> XTDeepLinkActionPlan {
        let projectId = normalized(route.projectId)
        var selectProjectId: String?
        var projectPaneIntent: XTDeepLinkProjectPaneIntent?

        if let projectId, !route.resumeRequested {
            selectProjectId = projectId
            if let pane = route.pane {
                projectPaneIntent = XTDeepLinkProjectPaneIntent(
                    projectId: projectId,
                    pane: pane
                )
            }
        }

        if route.focusTarget == .toolApproval || route.focusTarget == .routeDiagnose {
            if let projectId {
                projectPaneIntent = XTDeepLinkProjectPaneIntent(
                    projectId: projectId,
                    pane: .chat
                )
                if route.openTarget == nil {
                    selectProjectId = projectId
                }
            }
        }

        return XTDeepLinkActionPlan(
            selectProjectId: selectProjectId,
            projectPaneIntent: projectPaneIntent,
            openSupervisorIntent: XTSupervisorWindowOpenPolicy.intent(for: route),
            prefillGrantContext: prefillIntent(
                projectId: projectId,
                grantRequestId: route.grantRequestId,
                capability: route.grantCapability,
                reason: route.grantReason
            ),
            focusIntent: focusIntent(
                projectId: projectId,
                focusTarget: route.focusTarget,
                requestId: route.requestId,
                grantRequestId: route.grantRequestId,
                grantCapability: route.grantCapability
            )
        )
    }

    private static func prefillIntent(
        projectId: String?,
        grantRequestId: String?,
        capability: String?,
        reason: String?
    ) -> XTDeepLinkGrantPrefillIntent? {
        guard let projectId,
              let grantRequestId = normalized(grantRequestId) else {
            return nil
        }
        return XTDeepLinkGrantPrefillIntent(
            projectId: projectId,
            grantRequestId: grantRequestId,
            capability: normalized(capability),
            reason: normalized(reason)
        )
    }

    private static func focusIntent(
        projectId: String?,
        focusTarget: XTDeepLinkFocusTarget?,
        requestId: String?,
        grantRequestId: String?,
        grantCapability: String?
    ) -> XTDeepLinkFocusIntent? {
        switch focusTarget {
        case .grant:
            let normalizedGrantRequestId = normalized(grantRequestId)
            let normalizedGrantCapability = normalized(grantCapability)
            guard normalizedGrantRequestId != nil || normalizedGrantCapability != nil else { return nil }
            return .supervisorGrant(
                projectId: projectId,
                grantRequestId: normalizedGrantRequestId,
                capability: normalizedGrantCapability
            )
        case .approval:
            guard let requestId = normalized(requestId) else { return nil }
            return .supervisorApproval(projectId: projectId, requestId: requestId)
        case .skillRecord:
            guard let requestId = normalized(requestId) else { return nil }
            return .supervisorSkillRecord(projectId: projectId, requestId: requestId)
        case .toolApproval:
            guard let projectId else { return nil }
            return .projectToolApproval(
                projectId: projectId,
                requestId: normalized(requestId)
            )
        case .routeDiagnose:
            guard let projectId else { return nil }
            return .projectRouteDiagnose(projectId: projectId)
        case nil:
            return nil
        }
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
