import Foundation
import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
func grpcClientStatusSummary(_ st: GRPCDeviceStatusEntry) -> String {
        let ip = st.peerIp.trimmingCharacters(in: .whitespacesAndNewlines)
        let streams = max(0, st.activeEventSubscriptions)
        switch grpcClientPresenceState(st) {
        case .connected:
            return HubUIStrings.Settings.GRPC.DeviceList.connectedStatus(
                ip: ip.isEmpty ? nil : ip,
                streams: streams
            )
        case .offlineRecent:
            let lastSeen = st.lastSeenAtMs > 0
                ? HubUIStrings.Settings.GRPC.DeviceList.lastSeen(formatMs(st.lastSeenAtMs))
                : HubUIStrings.Settings.GRPC.DeviceList.lastSeenUnknown
            return HubUIStrings.Settings.GRPC.DeviceList.offlineRecentStatus(
                lastSeen: lastSeen,
                ip: ip.isEmpty ? nil : ip
            )
        case .stale:
            if st.connected {
                let snapshotText = grpcDevicesStatus.updatedAtMs > 0
                    ? HubUIStrings.Settings.GRPC.DeviceList.snapshotAt(formatMs(grpcDevicesStatus.updatedAtMs))
                    : HubUIStrings.Settings.GRPC.DeviceList.snapshotMissing
                return HubUIStrings.Settings.GRPC.DeviceList.staleStatus(
                    reference: snapshotText,
                    ip: ip.isEmpty ? nil : ip
                )
            }
            let lastSeen = st.lastSeenAtMs > 0
                ? HubUIStrings.Settings.GRPC.DeviceList.lastSeen(formatMs(st.lastSeenAtMs))
                : HubUIStrings.Settings.GRPC.DeviceList.neverSeen
            return HubUIStrings.Settings.GRPC.DeviceList.staleStatus(
                reference: lastSeen,
                ip: ip.isEmpty ? nil : ip
            )
        case .neverSeen:
            return HubUIStrings.Settings.GRPC.DeviceList.statusNeverSeen
        case .unknown:
            return HubUIStrings.Settings.GRPC.DeviceList.statusUnknown
        }
    }

    enum GRPCClientPresenceState {
        case connected
        case offlineRecent
        case stale
        case neverSeen
        case unknown
    }

    func grpcClientPresenceState(_ status: GRPCDeviceStatusEntry?) -> GRPCClientPresenceState {
        guard let status else { return .unknown }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        let snapshotAgeMs: Int64 = {
            let updatedAtMs = grpcDevicesStatus.updatedAtMs
            guard updatedAtMs > 0 else { return Int64.max }
            return max(0, nowMs - updatedAtMs)
        }()

        if status.connected {
            return snapshotAgeMs > Self.grpcClientPresenceSnapshotStaleMs ? .stale : .connected
        }
        guard status.lastSeenAtMs > 0 else { return .neverSeen }
        let lastSeenAgeMs = max(0, nowMs - status.lastSeenAtMs)
        return lastSeenAgeMs > Self.grpcClientPresenceStaleMs ? .stale : .offlineRecent
    }

    func grpcClientPresenceCountsAsStale(_ status: GRPCDeviceStatusEntry?) -> Bool {
        switch grpcClientPresenceState(status) {
        case .stale, .neverSeen:
            return true
        case .connected, .offlineRecent, .unknown:
            return false
        }
    }

    func grpcClientPresenceSortRank(_ status: GRPCDeviceStatusEntry?) -> Int {
        switch grpcClientPresenceState(status) {
        case .connected:
            return 0
        case .offlineRecent:
            return 1
        case .stale:
            return 2
        case .neverSeen:
            return 3
        case .unknown:
            return 4
        }
    }

    func grpcClientPresencePillTitle(_ status: GRPCDeviceStatusEntry?) -> String {
        switch grpcClientPresenceState(status) {
        case .connected:
            return HubUIStrings.Settings.GRPC.DeviceList.filterConnected
        case .offlineRecent:
            return HubUIStrings.Settings.GRPC.DeviceList.presenceOffline
        case .stale:
            return HubUIStrings.Settings.GRPC.DeviceList.filterStale
        case .neverSeen:
            return HubUIStrings.Settings.GRPC.DeviceList.presenceNew
        case .unknown:
            return HubUIStrings.Settings.GRPC.DeviceList.presenceUnknown
        }
    }

    func grpcClientPresencePillColor(_ status: GRPCDeviceStatusEntry?) -> Color {
        switch grpcClientPresenceState(status) {
        case .connected:
            return .green
        case .offlineRecent:
            return .secondary
        case .stale:
            return .orange
        case .neverSeen, .unknown:
            return .secondary
        }
    }

    static let grpcClientPresenceSnapshotStaleMs: Int64 = 15_000
    static let grpcClientPresenceStaleMs: Int64 = 12 * 60 * 60 * 1000

    func grpcClientPolicyUsageSummary(_ st: GRPCDeviceStatusEntry) -> String {
        var parts: [String] = []
        let mode = st.paidModelPolicyMode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !mode.isEmpty {
            parts.append(HubUIStrings.Settings.GRPC.DeviceList.policyUsageMode(paidPolicyModeLabel(mode)))
        }
        parts.append(HubUIStrings.Settings.GRPC.DeviceList.webStateShort(st.defaultWebFetchEnabled))
        if st.dailyTokenCap > 0 {
            parts.append(HubUIStrings.Settings.GRPC.DeviceList.budgetUsage(used: st.dailyTokenUsed, cap: st.dailyTokenCap))
            parts.append(HubUIStrings.Settings.GRPC.DeviceList.remainingBudget(max(0, st.remainingDailyTokenBudget)))
        }
        if !st.topModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(HubUIStrings.Settings.GRPC.DeviceList.topModel(st.topModel))
        }
        if st.requestsToday > 0 { parts.append(HubUIStrings.Settings.GRPC.DeviceList.requests(st.requestsToday)) }
        if st.blockedToday > 0 { parts.append(HubUIStrings.Settings.GRPC.DeviceList.blocked(st.blockedToday)) }
        return HubUIStrings.Settings.GRPC.DeviceList.summary(parts)
    }
}
