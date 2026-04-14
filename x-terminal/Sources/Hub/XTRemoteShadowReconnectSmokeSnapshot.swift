import Foundation

enum XTRemoteShadowReconnectSmokeSource: String, Codable, Equatable, Sendable {
    case cachedRemoteReconnectEvidence = "cached_remote_reconnect_evidence"
    case liveRemoteRoute = "live_remote_route"
    case dedicatedStableRemoteProbe = "dedicated_stable_remote_probe"

    var doctorLabel: String {
        switch self {
        case .cachedRemoteReconnectEvidence:
            return "缓存远端复连证据"
        case .liveRemoteRoute:
            return "当前远端活链路"
        case .dedicatedStableRemoteProbe:
            return "稳定远端 shadow probe"
        }
    }
}

enum XTRemoteShadowReconnectSmokeStatus: String, Codable, Equatable, Sendable {
    case running
    case succeeded
    case failed
}

struct XTRemoteShadowReconnectSmokeSnapshot: Codable, Equatable, Sendable {
    var source: XTRemoteShadowReconnectSmokeSource
    var status: XTRemoteShadowReconnectSmokeStatus
    var triggeredAtMs: Int64
    var completedAtMs: Int64
    var route: HubRemoteRoute
    var reasonCode: String?
    var summary: String
}
