import Foundation
import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
enum GRPCClientListFilter: String, CaseIterable, Identifiable {
        case all
        case connected
        case stale
        case networkEnabled
        case networkOff
        case blocked

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:
                return HubUIStrings.Settings.GRPC.DeviceList.filterAll
            case .connected:
                return HubUIStrings.Settings.GRPC.DeviceList.filterConnected
            case .stale:
                return HubUIStrings.Settings.GRPC.DeviceList.filterStale
            case .networkEnabled:
                return HubUIStrings.Settings.GRPC.DeviceList.filterNetworkEnabled
            case .networkOff:
                return HubUIStrings.Settings.GRPC.DeviceList.filterNetworkOff
            case .blocked:
                return HubUIStrings.Settings.GRPC.DeviceList.filterBlocked
            }
        }
    }

    struct GRPCClientListSummary {
        var total: Int = 0
        var enabled: Int = 0
        var connected: Int = 0
        var stale: Int = 0
        var networkEnabled: Int = 0
        var paidEnabled: Int = 0
        var webEnabled: Int = 0
        var blocked: Int = 0
    }

    func grpcClientListSummary(
        _ clients: [HubGRPCClientEntry],
        statusById: [String: GRPCDeviceStatusEntry]
    ) -> GRPCClientListSummary {
        var summary = GRPCClientListSummary()
        summary.total = clients.count
        for client in clients {
            let network = grpcClientNetworkAccessSnapshot(client)
            let status = statusById[client.deviceId]
            if client.enabled {
                summary.enabled += 1
            }
            if grpcClientPresenceState(status) == .connected {
                summary.connected += 1
            }
            if grpcClientPresenceCountsAsStale(status) {
                summary.stale += 1
            }
            if network.canNetwork {
                summary.networkEnabled += 1
            }
            if network.paidEnabled {
                summary.paidEnabled += 1
            }
            if network.webEnabled {
                summary.webEnabled += 1
            }
            if grpcClientHasBlockedState(status) {
                summary.blocked += 1
            }
        }
        return summary
    }

    func grpcVisibleClients(
        _ clients: [HubGRPCClientEntry],
        statusById: [String: GRPCDeviceStatusEntry]
    ) -> [HubGRPCClientEntry] {
        clients
            .filter { client in
                let network = grpcClientNetworkAccessSnapshot(client)
                let status = statusById[client.deviceId]
                switch grpcClientListFilter {
                case .all:
                    return true
                case .connected:
                    return grpcClientPresenceState(status) == .connected
                case .stale:
                    return grpcClientPresenceCountsAsStale(status)
                case .networkEnabled:
                    return network.canNetwork
                case .networkOff:
                    return !network.canNetwork
                case .blocked:
                    return grpcClientHasBlockedState(status)
                }
            }
            .sorted { lhs, rhs in
                let lhsStatus = statusById[lhs.deviceId]
                let rhsStatus = statusById[rhs.deviceId]
                let lhsNetwork = grpcClientNetworkAccessSnapshot(lhs)
                let rhsNetwork = grpcClientNetworkAccessSnapshot(rhs)
                let lhsPresence = grpcClientPresenceSortRank(lhsStatus)
                let rhsPresence = grpcClientPresenceSortRank(rhsStatus)

                if lhsPresence != rhsPresence {
                    return lhsPresence < rhsPresence
                }
                if lhsNetwork.canNetwork != rhsNetwork.canNetwork {
                    return lhsNetwork.canNetwork
                }
                if lhs.enabled != rhs.enabled {
                    return lhs.enabled
                }
                let lhsName = (lhs.name.isEmpty ? lhs.deviceId : lhs.name).localizedLowercase
                let rhsName = (rhs.name.isEmpty ? rhs.deviceId : rhs.name).localizedLowercase
                if lhsName != rhsName {
                    return lhsName < rhsName
                }
                return lhs.deviceId.localizedLowercase < rhs.deviceId.localizedLowercase
            }
    }

    func grpcClientHasBlockedState(_ status: GRPCDeviceStatusEntry?) -> Bool {
        guard let status else { return false }
        if status.blockedToday > 0 {
            return true
        }
        if !status.lastBlockedReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return !status.lastDenyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
