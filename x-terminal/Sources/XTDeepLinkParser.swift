import Foundation

enum XTDeepLinkOpenTarget: Equatable {
    case supervisor
    case supervisorSettings
}

enum XTDeepLinkFocusTarget: Equatable {
    case grant
    case approval
    case candidateReview
    case skillRecord
    case projectCreationBoard
    case toolApproval
    case routeDiagnose
}

struct XTDeepLinkSupervisorRoute: Equatable {
    var projectId: String?
    var focusTarget: XTDeepLinkFocusTarget?
    var requestId: String?
    var grantRequestId: String?
    var grantCapability: String?
    var grantReason: String?
}

struct XTHubSetupRoute: Equatable {
    var sectionId: String?
    var title: String?
    var detail: String?
    var refreshAction: XTSectionRefreshAction? = nil
    var refreshReason: String? = nil
    var pairingPrefill: XTHubPairingInvitePrefill? = nil
}

struct XTSettingsRoute: Equatable {
    var sectionId: String?
    var title: String?
    var detail: String?
    var refreshAction: XTSectionRefreshAction? = nil
    var refreshReason: String? = nil
}

struct XTSupervisorModelSettingsRoute: Equatable {
    var title: String?
    var detail: String?
}

struct XTDeepLinkProjectRoute: Equatable {
    var projectId: String?
    var pane: AXProjectPane?
    var openTarget: XTDeepLinkOpenTarget?
    var focusTarget: XTDeepLinkFocusTarget?
    var requestId: String?
    var grantRequestId: String?
    var grantCapability: String?
    var grantReason: String?
    var resumeRequested: Bool
    var governanceDestination: XTProjectGovernanceDestination? = nil
}

enum XTDeepLinkRoute: Equatable {
    case supervisor(XTDeepLinkSupervisorRoute)
    case hubSetup(XTHubSetupRoute)
    case settings(XTSettingsRoute)
    case supervisorSettings
    case supervisorModelSettings(XTSupervisorModelSettingsRoute)
    case resume(projectId: String?)
    case project(XTDeepLinkProjectRoute)
}

enum XTDeepLinkParser {
    static func parse(_ url: URL) -> XTDeepLinkRoute? {
        let scheme = normalized(url.scheme)?.lowercased() ?? ""
        guard scheme == "xterminal" || scheme == "x-terminal" else {
            return nil
        }

        let host = normalized(url.host)?.lowercased() ?? ""
        let pathSegments = url.path
            .split(separator: "/")
            .map { String($0) }
        let lowercasedSegments = pathSegments.map { $0.lowercased() }
        let query = queryItems(url)
        let requestId = normalized(query["request_id"])
        let grantRequestId = normalized(query["grant_request_id"])
        let grantCapability = normalized(query["grant_capability"])
        let grantReason = normalized(query["grant_reason"])
        let focusTarget = focusTargetValue(
            raw: query["focus"],
            requestId: requestId,
            grantRequestId: grantRequestId,
            grantCapability: grantCapability
        )

        if host == "supervisor" || lowercasedSegments == ["supervisor"] {
            return .supervisor(
                XTDeepLinkSupervisorRoute(
                    projectId: projectID(host: host, pathSegments: pathSegments, query: query, token: "supervisor"),
                    focusTarget: focusTarget,
                    requestId: requestId,
                    grantRequestId: grantRequestId,
                    grantCapability: grantCapability,
                    grantReason: grantReason
                )
            )
        }
        if host == "hub-setup" || host == "pair-hub" || lowercasedSegments == ["hub-setup"] || lowercasedSegments == ["pair-hub"] {
            let pairingPrefill = pairingPrefillValue(query)
            return .hubSetup(
                XTHubSetupRoute(
                    sectionId: normalized(query["section_id"] ?? query["section"])
                        ?? (host == "pair-hub" || lowercasedSegments == ["pair-hub"] ? "pair_hub" : nil),
                    title: normalized(query["title"]),
                    detail: normalized(query["detail"]),
                    refreshAction: refreshActionValue(query["refresh_action"]),
                    refreshReason: normalized(query["refresh_reason"]),
                    pairingPrefill: pairingPrefill
                )
            )
        }
        if host == "settings" || lowercasedSegments == ["settings"] {
            return .settings(
                XTSettingsRoute(
                    sectionId: normalized(query["section_id"] ?? query["section"]),
                    title: normalized(query["title"]),
                    detail: normalized(query["detail"]),
                    refreshAction: refreshActionValue(query["refresh_action"]),
                    refreshReason: normalized(query["refresh_reason"])
                )
            )
        }
        if host == "supervisor-settings" || lowercasedSegments == ["supervisor-settings"] {
            return .supervisorSettings
        }
        if host == "supervisor-model-settings" || lowercasedSegments == ["supervisor-model-settings"] {
            return .supervisorModelSettings(
                XTSupervisorModelSettingsRoute(
                    title: normalized(query["title"]),
                    detail: normalized(query["detail"])
                )
            )
        }
        if host == "resume" || lowercasedSegments.first == "resume" {
            return .resume(projectId: projectID(host: host, pathSegments: pathSegments, query: query, token: "resume"))
        }
        if host == "project" || lowercasedSegments.first == "project" {
            let openValue = normalized(query["open"])?.lowercased() ?? ""
            let actionValue = normalized(query["action"])?.lowercased() ?? ""
            return .project(
                XTDeepLinkProjectRoute(
                    projectId: projectID(host: host, pathSegments: pathSegments, query: query, token: "project"),
                    pane: paneValue(query["pane"]),
                    openTarget: openTargetValue(openValue),
                    focusTarget: focusTarget,
                    requestId: requestId,
                    grantRequestId: grantRequestId,
                    grantCapability: grantCapability,
                    grantReason: grantReason,
                    resumeRequested: resumeRequested(
                        actionValue: actionValue,
                        openValue: openValue,
                        resumeValue: normalized(query["resume"])
                    ),
                    governanceDestination: XTProjectGovernanceDestination.parse(
                        query["governance_destination"]
                            ?? query["governance"]
                            ?? query["section_id"]
                            ?? query["section"]
                    )
                )
            )
        }
        return nil
    }

    private static func queryItems(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var query: [String: String] = [:]
        for item in items {
            query[item.name.lowercased()] = item.value ?? ""
        }
        return query
    }

    private static func projectID(
        host: String,
        pathSegments: [String],
        query: [String: String],
        token: String
    ) -> String? {
        if let explicit = normalized(query["project_id"]) {
            return explicit
        }
        if host == token {
            return normalized(pathSegments.first)
        }
        guard pathSegments.count >= 2,
              pathSegments[0].lowercased() == token else {
            return nil
        }
        return normalized(pathSegments[1])
    }

    private static func paneValue(_ raw: String?) -> AXProjectPane? {
        let pane = normalized(raw)?.lowercased() ?? ""
        switch pane {
        case AXProjectPane.chat.rawValue:
            return .chat
        case AXProjectPane.terminal.rawValue:
            return .terminal
        default:
            return nil
        }
    }

    private static func pairingPrefillValue(_ query: [String: String]) -> XTHubPairingInvitePrefill? {
        let internetHost = normalized(query["hub_host"] ?? query["internet_host"] ?? query["host"])
        let pairingPort = portValue(query["pairing_port"])
        let grpcPort = portValue(query["grpc_port"])
        let hubAlias = normalized(query["hub_alias"] ?? query["alias"])
        let inviteToken = normalized(query["invite_token"] ?? query["token"])
        let hubInstanceID = normalized(query["hub_instance_id"])

        if internetHost == nil,
           pairingPort == nil,
           grpcPort == nil,
           hubAlias == nil,
           inviteToken == nil,
           hubInstanceID == nil {
            return nil
        }

        return XTHubPairingInvitePrefill(
            hubAlias: hubAlias,
            internetHost: internetHost,
            pairingPort: pairingPort,
            grpcPort: grpcPort,
            inviteToken: inviteToken,
            hubInstanceID: hubInstanceID
        )
    }

    private static func portValue(_ raw: String?) -> Int? {
        guard let value = normalized(raw),
              let port = Int(value),
              (1...65_535).contains(port) else {
            return nil
        }
        return port
    }

    private static func openTargetValue(_ raw: String) -> XTDeepLinkOpenTarget? {
        switch raw {
        case "supervisor":
            return .supervisor
        case "supervisor_settings":
            return .supervisorSettings
        default:
            return nil
        }
    }

    private static func focusTargetValue(
        raw: String?,
        requestId: String?,
        grantRequestId: String?,
        grantCapability: String?
    ) -> XTDeepLinkFocusTarget? {
        let focus = normalized(raw)?.lowercased() ?? ""
        switch focus {
        case "grant":
            return .grant
        case "approval", "local_approval", "supervisor_skill_approval":
            return .approval
        case "candidate_review", "candidatereview", "supervisor_candidate_review":
            return .candidateReview
        case "skill_record", "skillrecord", "record":
            return .skillRecord
        case "project_creation_board", "projectcreationboard", "project_creation":
            return .projectCreationBoard
        case "tool_approval", "toolapproval", "pending_tool_approval":
            return .toolApproval
        case "route_diagnose", "routediagnose", "model_route_diagnose":
            return .routeDiagnose
        default:
            break
        }

        if grantRequestId != nil || grantCapability != nil {
            return .grant
        }
        if requestId != nil {
            return .approval
        }
        return nil
    }

    private static func resumeRequested(
        actionValue: String,
        openValue: String,
        resumeValue: String?
    ) -> Bool {
        if ["resume", "resume_project", "resume_brief", "handoff"].contains(actionValue) {
            return true
        }
        if openValue == "resume" {
            return true
        }
        let resumeToken = normalized(resumeValue)?.lowercased() ?? ""
        return ["1", "true", "yes", "y", "resume"].contains(resumeToken)
    }

    private static func refreshActionValue(_ raw: String?) -> XTSectionRefreshAction? {
        guard let normalized = normalized(raw)?.lowercased() else {
            return nil
        }
        return XTSectionRefreshAction(rawValue: normalized)
    }

    private static func normalized(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
