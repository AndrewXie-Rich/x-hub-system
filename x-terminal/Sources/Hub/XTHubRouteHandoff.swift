import Foundation

enum XTHubRouteCandidate: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case lanDirect = "lan_direct"
    case stableNamedRemote = "stable_named_remote"
    case managedTunnelFallback = "managed_tunnel_fallback"

    var progressDetail: String {
        switch self {
        case .lanDirect:
            return "lan"
        case .stableNamedRemote:
            return "internet"
        case .managedTunnelFallback:
            return "tunnel"
        }
    }

    var routeLabel: String {
        switch self {
        case .lanDirect:
            return "LAN"
        case .stableNamedRemote:
            return "stable_remote"
        case .managedTunnelFallback:
            return "managed_tunnel"
        }
    }

    var remoteRoute: HubRemoteRoute {
        switch self {
        case .lanDirect:
            return .lan
        case .stableNamedRemote:
            return .internet
        case .managedTunnelFallback:
            return .internetTunnel
        }
    }

    static func from(remoteRoute: HubRemoteRoute) -> XTHubRouteCandidate? {
        switch remoteRoute {
        case .lan:
            return .lanDirect
        case .internet:
            return .stableNamedRemote
        case .internetTunnel:
            return .managedTunnelFallback
        case .none:
            return nil
        }
    }
}

struct XTHubConnectivityRouteStatusSnapshot: Codable, Equatable, Sendable {
    var route: XTHubRouteCandidate
    var healthScore: Int
    var cooldownUntilMs: Int64?
    var recentSuccessCount: Int
    var recentFailureCount: Int

    func isCoolingDown(at nowMs: Int64) -> Bool {
        guard let cooldownUntilMs else { return false }
        return cooldownUntilMs > nowMs
    }
}
