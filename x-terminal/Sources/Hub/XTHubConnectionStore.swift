import Combine
import Foundation

struct XTHubConnectionSnapshot: Equatable, Sendable {
    var localConnected: Bool
    var remoteConnected: Bool
    var remoteLinking: Bool
    var remoteRoute: HubRemoteRoute
    var remoteSummary: String
    var lastError: String?
    var remotePaidAccessSnapshot: HubRemotePaidAccessSnapshot?

    init(
        localConnected: Bool,
        remoteConnected: Bool,
        remoteLinking: Bool,
        remoteRoute: HubRemoteRoute,
        remoteSummary: String,
        lastError: String?,
        remotePaidAccessSnapshot: HubRemotePaidAccessSnapshot? = nil
    ) {
        self.localConnected = localConnected
        self.remoteConnected = remoteConnected
        self.remoteLinking = remoteLinking
        self.remoteRoute = remoteRoute
        self.remoteSummary = remoteSummary
        self.lastError = lastError
        self.remotePaidAccessSnapshot = remotePaidAccessSnapshot
    }

    static let disconnected = XTHubConnectionSnapshot(
        localConnected: false,
        remoteConnected: false,
        remoteLinking: false,
        remoteRoute: .none,
        remoteSummary: "",
        lastError: nil
    )

    var interactive: Bool {
        localConnected || remoteConnected
    }
}

@MainActor
final class XTHubConnectionStore: ObservableObject {
    @Published private(set) var snapshot: XTHubConnectionSnapshot

    init(snapshot: XTHubConnectionSnapshot = .disconnected) {
        self.snapshot = snapshot
    }

    func update(_ nextSnapshot: XTHubConnectionSnapshot) {
        guard snapshot != nextSnapshot else { return }
        snapshot = nextSnapshot
    }
}

enum XTHubConnectionTone: Equatable {
    case localReady
    case remoteReady
    case linking
    case offline
}

enum XTHubConnectionPresentation {
    static func statusLabel(for snapshot: XTHubConnectionSnapshot) -> String {
        if snapshot.localConnected {
            return "local"
        }
        if snapshot.remoteConnected {
            return "remote"
        }
        if snapshot.remoteLinking {
            return "linking"
        }
        return "off"
    }

    static func statusTone(for snapshot: XTHubConnectionSnapshot) -> XTHubConnectionTone {
        if snapshot.localConnected {
            return .localReady
        }
        if snapshot.remoteConnected {
            return .remoteReady
        }
        if snapshot.remoteLinking {
            return .linking
        }
        return .offline
    }

    static func controlButtonIconName(for snapshot: XTHubConnectionSnapshot) -> String {
        snapshot.interactive ? "slider.horizontal.3" : "link.badge.plus"
    }

    static func controlButtonTitle(for snapshot: XTHubConnectionSnapshot) -> String {
        if snapshot.localConnected {
            return "Control · Hub Local"
        }
        if snapshot.remoteConnected {
            return "Control · Hub Remote"
        }
        if snapshot.remoteLinking {
            return "Control · Linking"
        }
        return "Control · Connect Hub"
    }

    static func controlButtonHelp(for snapshot: XTHubConnectionSnapshot) -> String {
        if snapshot.interactive {
            return "打开 Control Center，查看 Hub、模型、技能和诊断。"
        }
        return "打开 Control Center；Hub 还没接入时会优先处理连接主链。"
    }

    static func menuCommandTitle(for snapshot: XTHubConnectionSnapshot) -> String {
        if snapshot.localConnected {
            return "Hub Connected"
        }
        if snapshot.remoteLinking {
            return "Hub Linking..."
        }
        if snapshot.remoteConnected {
            switch snapshot.remoteRoute {
            case .lan:
                return "Hub Relay (LAN)"
            case .internet:
                return "Hub Relay (Internet)"
            case .internetTunnel:
                return "Hub Relay (Tunnel)"
            case .none:
                return "Hub Relay"
            }
        }
        return "One-Click Connect to Hub"
    }
}
