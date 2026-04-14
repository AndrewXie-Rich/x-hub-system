import Foundation

enum XTHubConnectivityDecisionTrigger: String, Codable, Equatable, Sendable {
    case networkChanged = "network_changed"
    case backgroundKeepalive = "background_keepalive"
    case appBecameActive = "app_became_active"
    case systemWoke = "system_woke"
    case hubReachabilityChanged = "hub_reachability_changed"
}

struct XTHubConnectivityDecisionInput: Sendable {
    var trigger: XTHubConnectivityDecisionTrigger
    var currentPath: HubNetworkPathFingerprint?
    var pairedRouteSetSnapshot: XTPairedRouteSetSnapshot
    var localConnected: Bool
    var remoteConnected: Bool
    var remoteRoute: HubRemoteRoute
    var repairLedgerSnapshot: XTConnectivityRepairLedgerSnapshot = .empty
    var now: Date = Date()
}

struct XTHubConnectivityDecision: Equatable, Sendable {
    var shouldAttemptReconnect: Bool
    var allowBootstrap: Bool
    var summaryLine: String
    var reasonCode: String
    var selectedRoute: XTHubRouteCandidate?
    var candidatesTried: [XTHubRouteCandidate]
    var handoffReason: String?
    var cooldownApplied: Bool
    var routeStatuses: [XTHubConnectivityRouteStatusSnapshot]
}

enum XTHubConnectivityDecisionBuilder {
    static func build(input: XTHubConnectivityDecisionInput) -> XTHubConnectivityDecision {
        let snapshot = input.pairedRouteSetSnapshot
        let hasStableRemoteRoute = snapshot.stableRemoteRoute != nil
        let hasLanRoute = snapshot.lanRoute != nil
        let lanCapable = isLikelyLANCapable(path: input.currentPath)
        let routeStatuses = XTConnectivityRepairLedgerStore.routeStatusSnapshots(
            input.repairLedgerSnapshot,
            now: input.now
        )
        let routeStatusMap = Dictionary(
            uniqueKeysWithValues: routeStatuses.map { ($0.route, $0) }
        )
        let nowMs = Int64((input.now.timeIntervalSince1970 * 1000).rounded())

        if input.localConnected {
            return XTHubConnectivityDecision(
                shouldAttemptReconnect: false,
                allowBootstrap: false,
                summaryLine: "",
                reasonCode: "local_hub_active",
                selectedRoute: nil,
                candidatesTried: [],
                handoffReason: nil,
                cooldownApplied: false,
                routeStatuses: routeStatuses
            )
        }

        if let currentPath = input.currentPath,
           !currentPath.isSatisfied {
            return XTHubConnectivityDecision(
                shouldAttemptReconnect: false,
                allowBootstrap: false,
                summaryLine: "network unavailable",
                reasonCode: "network_unavailable",
                selectedRoute: nil,
                candidatesTried: [],
                handoffReason: nil,
                cooldownApplied: false,
                routeStatuses: routeStatuses
            )
        }

        if input.trigger == .backgroundKeepalive,
           input.remoteConnected,
           input.remoteRoute != .none {
            return XTHubConnectivityDecision(
                shouldAttemptReconnect: false,
                allowBootstrap: false,
                summaryLine: "",
                reasonCode: "remote_route_already_active",
                selectedRoute: nil,
                candidatesTried: [],
                handoffReason: nil,
                cooldownApplied: false,
                routeStatuses: routeStatuses
            )
        }

        let candidateRoutes = availableCandidateRoutes(
            snapshot: snapshot,
            lanCapable: lanCapable,
            preferredRoute: preferredRoute(
                snapshot: snapshot,
                hasStableRemoteRoute: hasStableRemoteRoute,
                hasLanRoute: hasLanRoute,
                lanCapable: lanCapable
            )
        )

        switch snapshot.readiness {
        case .remoteReady:
            return finalizedDecision(
                base: BaseDecision(
                    shouldAttemptReconnect: true,
                    allowBootstrap: false,
                    summaryLine: summaryLine(
                        trigger: input.trigger,
                        networkChanged: "network changed; refreshing validated remote route ...",
                        backgroundKeepalive: "remote route not active; reconnecting validated remote route ..."
                    ),
                    reasonCode: "refresh_validated_remote_route",
                    defaultRoute: hasStableRemoteRoute ? .stableNamedRemote : nil
                ),
                candidateRoutes: candidateRoutes,
                trigger: input.trigger,
                routeStatuses: routeStatuses,
                routeStatusMap: routeStatusMap,
                nowMs: nowMs
            )
        case .remoteDegraded:
            return finalizedDecision(
                base: BaseDecision(
                    shouldAttemptReconnect: true,
                    allowBootstrap: false,
                    summaryLine: summaryLine(
                        trigger: input.trigger,
                        networkChanged: "network changed; retrying degraded remote route ...",
                        backgroundKeepalive: "remote route not active; retrying degraded remote route ..."
                    ),
                    reasonCode: "retry_degraded_remote_route",
                    defaultRoute: hasStableRemoteRoute ? .stableNamedRemote : nil
                ),
                candidateRoutes: candidateRoutes,
                trigger: input.trigger,
                routeStatuses: routeStatuses,
                routeStatusMap: routeStatusMap,
                nowMs: nowMs
            )
        case .remoteBlocked:
            return XTHubConnectivityDecision(
                shouldAttemptReconnect: false,
                allowBootstrap: false,
                summaryLine: "saved remote route is blocked by pairing/identity repair; waiting for repair.",
                reasonCode: "remote_route_blocked_waiting_for_repair",
                selectedRoute: nil,
                candidatesTried: candidateRoutes,
                handoffReason: nil,
                cooldownApplied: false,
                routeStatuses: routeStatuses
            )
        case .localReady:
            if hasStableRemoteRoute {
                return finalizedDecision(
                    base: BaseDecision(
                        shouldAttemptReconnect: true,
                        allowBootstrap: false,
                        summaryLine: summaryLine(
                            trigger: input.trigger,
                            networkChanged: "network changed; verifying saved formal remote route ...",
                            backgroundKeepalive: "remote route not active; verifying saved formal remote route ..."
                        ),
                        reasonCode: "verify_formal_remote_route",
                        defaultRoute: .stableNamedRemote
                    ),
                    candidateRoutes: candidateRoutes,
                    trigger: input.trigger,
                    routeStatuses: routeStatuses,
                    routeStatusMap: routeStatusMap,
                    nowMs: nowMs
                )
            }

            if hasLanRoute && lanCapable {
                return finalizedDecision(
                    base: BaseDecision(
                        shouldAttemptReconnect: true,
                        allowBootstrap: false,
                        summaryLine: summaryLine(
                            trigger: input.trigger,
                            networkChanged: "network changed; retrying same-LAN paired route ...",
                            backgroundKeepalive: "remote route not active; retrying same-LAN paired route ..."
                        ),
                        reasonCode: "retry_same_lan_paired_route",
                        defaultRoute: .lanDirect
                    ),
                    candidateRoutes: candidateRoutes,
                    trigger: input.trigger,
                    routeStatuses: routeStatuses,
                    routeStatusMap: routeStatusMap,
                    nowMs: nowMs
                )
            }

            if hasLanRoute {
                return XTHubConnectivityDecision(
                    shouldAttemptReconnect: false,
                    allowBootstrap: false,
                    summaryLine: "current network is not same-LAN; waiting to return to LAN or add a formal remote route.",
                    reasonCode: "waiting_for_same_lan_or_formal_remote_route",
                    selectedRoute: nil,
                    candidatesTried: candidateRoutes,
                    handoffReason: nil,
                    cooldownApplied: false,
                    routeStatuses: routeStatuses
                )
            }

            return XTHubConnectivityDecision(
                shouldAttemptReconnect: false,
                allowBootstrap: false,
                summaryLine: "paired route is local-only; waiting for LAN or a formal remote route.",
                reasonCode: "local_pairing_only_waiting_for_route",
                selectedRoute: nil,
                candidatesTried: candidateRoutes,
                handoffReason: nil,
                cooldownApplied: false,
                routeStatuses: routeStatuses
            )
        case .unknown:
            return finalizedDecision(
                base: BaseDecision(
                    shouldAttemptReconnect: true,
                    allowBootstrap: true,
                    summaryLine: summaryLine(
                        trigger: input.trigger,
                        networkChanged: "network changed; probing paired hub route ...",
                        backgroundKeepalive: "remote route not active; probing paired hub route ..."
                    ),
                    reasonCode: "probe_paired_route",
                    defaultRoute: nil
                ),
                candidateRoutes: candidateRoutes,
                trigger: input.trigger,
                routeStatuses: routeStatuses,
                routeStatusMap: routeStatusMap,
                nowMs: nowMs
            )
        }
    }

    private struct BaseDecision {
        var shouldAttemptReconnect: Bool
        var allowBootstrap: Bool
        var summaryLine: String
        var reasonCode: String
        var defaultRoute: XTHubRouteCandidate?
    }

    private static func availableCandidateRoutes(
        snapshot: XTPairedRouteSetSnapshot,
        lanCapable: Bool,
        preferredRoute: XTHubRouteCandidate?
    ) -> [XTHubRouteCandidate] {
        var candidates: [XTHubRouteCandidate] = []
        if snapshot.lanRoute != nil && lanCapable {
            candidates.append(.lanDirect)
        }
        if snapshot.stableRemoteRoute != nil {
            candidates.append(.stableNamedRemote)
        }
        if let preferredRoute,
           let preferredIndex = candidates.firstIndex(of: preferredRoute),
           preferredIndex > 0 {
            let prioritizedRoute = candidates.remove(at: preferredIndex)
            candidates.insert(prioritizedRoute, at: 0)
        }
        return candidates
    }

    private static func preferredRoute(
        snapshot: XTPairedRouteSetSnapshot,
        hasStableRemoteRoute: Bool,
        hasLanRoute: Bool,
        lanCapable: Bool
    ) -> XTHubRouteCandidate? {
        switch snapshot.readiness {
        case .remoteReady, .remoteDegraded:
            return hasStableRemoteRoute ? .stableNamedRemote : (hasLanRoute && lanCapable ? .lanDirect : nil)
        case .localReady:
            if hasStableRemoteRoute {
                return .stableNamedRemote
            }
            return hasLanRoute && lanCapable ? .lanDirect : nil
        case .remoteBlocked, .unknown:
            return nil
        }
    }

    private static func finalizedDecision(
        base: BaseDecision,
        candidateRoutes: [XTHubRouteCandidate],
        trigger: XTHubConnectivityDecisionTrigger,
        routeStatuses: [XTHubConnectivityRouteStatusSnapshot],
        routeStatusMap: [XTHubRouteCandidate: XTHubConnectivityRouteStatusSnapshot],
        nowMs: Int64
    ) -> XTHubConnectivityDecision {
        guard base.shouldAttemptReconnect else {
            return XTHubConnectivityDecision(
                shouldAttemptReconnect: false,
                allowBootstrap: base.allowBootstrap,
                summaryLine: base.summaryLine,
                reasonCode: base.reasonCode,
                selectedRoute: nil,
                candidatesTried: candidateRoutes,
                handoffReason: nil,
                cooldownApplied: false,
                routeStatuses: routeStatuses
            )
        }

        guard !candidateRoutes.isEmpty else {
            return XTHubConnectivityDecision(
                shouldAttemptReconnect: true,
                allowBootstrap: base.allowBootstrap,
                summaryLine: base.summaryLine,
                reasonCode: base.reasonCode,
                selectedRoute: nil,
                candidatesTried: [],
                handoffReason: nil,
                cooldownApplied: false,
                routeStatuses: routeStatuses
            )
        }

        let selectedRoute = candidateRoutes.first { route in
            routeStatusMap[route]?.isCoolingDown(at: nowMs) != true
        }

        if let selectedRoute {
            var handoffReason: String?
            var cooldownApplied = false
            var summaryLine = base.summaryLine

            if let firstCandidate = candidateRoutes.first,
               firstCandidate != selectedRoute {
                handoffReason = "\(firstCandidate.rawValue)_cooldown"
                cooldownApplied = true
                summaryLine = cooldownHandoffSummary(
                    trigger: trigger,
                    selectedRoute: selectedRoute,
                    skippedRoute: firstCandidate
                )
            } else if let defaultRoute = base.defaultRoute,
                      defaultRoute != selectedRoute {
                handoffReason = handoffReasonForRouteSelection(
                    selectedRoute: selectedRoute,
                    defaultRoute: defaultRoute
                )
                summaryLine = preferredRouteSummary(
                    trigger: trigger,
                    selectedRoute: selectedRoute,
                    defaultRoute: defaultRoute
                )
            }

            return XTHubConnectivityDecision(
                shouldAttemptReconnect: true,
                allowBootstrap: base.allowBootstrap,
                summaryLine: summaryLine,
                reasonCode: base.reasonCode,
                selectedRoute: selectedRoute,
                candidatesTried: candidateRoutes,
                handoffReason: handoffReason,
                cooldownApplied: cooldownApplied,
                routeStatuses: routeStatuses
            )
        }

        let primaryRoute = candidateRoutes.first
        let summaryLine = cooldownWaitSummary(
            trigger: trigger,
            route: primaryRoute,
            cooldownUntilMs: primaryRoute.flatMap { routeStatusMap[$0]?.cooldownUntilMs },
            nowMs: nowMs
        )

        return XTHubConnectivityDecision(
            shouldAttemptReconnect: false,
            allowBootstrap: base.allowBootstrap,
            summaryLine: summaryLine,
            reasonCode: base.reasonCode,
            selectedRoute: primaryRoute,
            candidatesTried: candidateRoutes,
            handoffReason: "all_candidates_in_cooldown",
            cooldownApplied: true,
            routeStatuses: routeStatuses
        )
    }

    private static func isLikelyLANCapable(path: HubNetworkPathFingerprint?) -> Bool {
        guard let path else { return true }
        guard path.isSatisfied else { return false }
        if path.usesWiFi || path.usesWiredEthernet {
            return true
        }
        if path.usesCellular && !path.usesWiFi && !path.usesWiredEthernet {
            return false
        }
        return true
    }

    private static func summaryLine(
        trigger: XTHubConnectivityDecisionTrigger,
        networkChanged: String,
        backgroundKeepalive: String
    ) -> String {
        switch trigger {
        case .networkChanged:
            return networkChanged
        case .backgroundKeepalive:
            return backgroundKeepalive
        case .appBecameActive:
            return networkChanged.replacingOccurrences(
                of: "network changed",
                with: "app resumed in foreground"
            )
        case .systemWoke:
            return networkChanged.replacingOccurrences(
                of: "network changed",
                with: "system woke from sleep"
            )
        case .hubReachabilityChanged:
            return networkChanged.replacingOccurrences(
                of: "network changed",
                with: "local hub availability changed"
            )
        }
    }

    private static func handoffReasonForRouteSelection(
        selectedRoute: XTHubRouteCandidate,
        defaultRoute: XTHubRouteCandidate
    ) -> String {
        switch (selectedRoute, defaultRoute) {
        case (.lanDirect, .stableNamedRemote), (.lanDirect, .managedTunnelFallback):
            return "prefer_lan_direct_on_current_network"
        case (.stableNamedRemote, .managedTunnelFallback):
            return "prefer_stable_named_remote"
        default:
            return "route_priority_selected_\(selectedRoute.rawValue)"
        }
    }

    private static func preferredRouteSummary(
        trigger: XTHubConnectivityDecisionTrigger,
        selectedRoute: XTHubRouteCandidate,
        defaultRoute: XTHubRouteCandidate
    ) -> String {
        switch (selectedRoute, defaultRoute) {
        case (.lanDirect, .stableNamedRemote), (.lanDirect, .managedTunnelFallback):
            return summaryLine(
                trigger: trigger,
                networkChanged: "network changed; LAN route is preferred on the current network, reconnecting same-LAN paired route ...",
                backgroundKeepalive: "remote route not active; LAN route is preferred on the current network, retrying same-LAN paired route ..."
            )
        case (.stableNamedRemote, .managedTunnelFallback):
            return summaryLine(
                trigger: trigger,
                networkChanged: "network changed; stable named remote route is preferred, reconnecting stable remote route ...",
                backgroundKeepalive: "remote route not active; stable named remote route is preferred, reconnecting stable remote route ..."
            )
        default:
            return summaryLine(
                trigger: trigger,
                networkChanged: "network changed; refreshing preferred paired route ...",
                backgroundKeepalive: "remote route not active; refreshing preferred paired route ..."
            )
        }
    }

    private static func cooldownHandoffSummary(
        trigger: XTHubConnectivityDecisionTrigger,
        selectedRoute: XTHubRouteCandidate,
        skippedRoute: XTHubRouteCandidate
    ) -> String {
        summaryLine(
            trigger: trigger,
            networkChanged: "network changed; \(skippedRoute.routeLabel) route is cooling down, handing off to \(selectedRoute.routeLabel) ...",
            backgroundKeepalive: "remote route not active; \(skippedRoute.routeLabel) route is cooling down, handing off to \(selectedRoute.routeLabel) ..."
        )
    }

    private static func cooldownWaitSummary(
        trigger: XTHubConnectivityDecisionTrigger,
        route: XTHubRouteCandidate?,
        cooldownUntilMs: Int64?,
        nowMs: Int64
    ) -> String {
        let remainingSeconds: Int
        if let cooldownUntilMs {
            remainingSeconds = max(1, Int((cooldownUntilMs - nowMs + 999) / 1000))
        } else {
            remainingSeconds = 30
        }
        let routeLabel = route?.routeLabel ?? "saved"
        return summaryLine(
            trigger: trigger,
            networkChanged: "network changed; \(routeLabel) route is cooling down, waiting \(remainingSeconds)s before retry ...",
            backgroundKeepalive: "remote route not active; \(routeLabel) route is cooling down, waiting \(remainingSeconds)s before retry ..."
        )
    }
}
