import Foundation
import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    static let routingTaskTypes: [String] = [
        "supervisor",
        "coder",
        "reviewer",
    ]

    func routingTaskTypeLabel(_ taskType: String) -> String {
        switch taskType {
        case "supervisor":
            return HubUIStrings.Models.TaskType.supervisor
        case "coder":
            return HubUIStrings.Models.TaskType.coder
        case "reviewer":
            return HubUIStrings.Models.TaskType.reviewer
        default:
            return taskType
        }
    }

    func bindingRoutingModelId(_ taskType: String) -> Binding<String> {
        Binding(
            get: { store.routingPreferredModelIdByTask[taskType] ?? "" },
            set: { s in
                let v = s.trimmingCharacters(in: .whitespacesAndNewlines)
                store.setRoutingPreferredModel(taskType: taskType, modelId: v.isEmpty ? nil : v)
            }
        )
    }

    nonisolated static func emptyRemoteQuotaProjection() -> RemoteQuotaCenterProjection {
        RemoteQuotaCenterProjection(
            overview: RemoteQuotaCenterOverview(
                quotaPoolCount: 0,
                keyPoolCount: 0,
                totalKeys: 0,
                readyKeys: 0,
                cooldownKeys: 0,
                blockedKeys: 0,
                knownQuotaKeys: 0,
                totalDailyTokenCap: 0,
                totalDailyTokensUsed: 0,
                totalDailyTokensRemaining: 0,
                userCount: 0,
                consumerCount: 0,
                connectedConsumerCount: 0,
                xtConsumerCount: 0,
                terminalConsumerCount: 0,
                allocatedDailyTokenBudget: 0,
                unlimitedBudgetConsumerCount: 0,
                observedConsumerTokensUsed: 0,
                oversubscribedFamilyCount: 0
            ),
            users: [],
            families: [],
            consumers: []
        )
    }

    nonisolated static func emptyProviderKeySectionSnapshot() -> ProviderKeySectionSnapshot {
        ProviderKeySectionSnapshot(
            keyPools: [],
            overview: Self.emptyRemoteQuotaProjection().overview,
            totalFamilyCount: 0,
            totalConsumerCount: 0,
            consumerLedgerTotalCount: 0,
            users: [],
            focusedUser: nil,
            scopedUsers: [],
            scopedConsumers: [],
            vendorSummaries: [],
            filteredVendors: [],
            filteredFamilies: [],
            filteredUsers: [],
            filteredConsumers: [],
            focusedVendor: nil,
            flowChains: [],
            scopeOverview: ProviderKeyScopeOverview(
                focusedUser: nil,
                focusedVendorDisplayName: nil,
                userCount: 0,
                consumerCount: 0,
                connectedConsumerCount: 0,
                xtConsumerCount: 0,
                terminalConsumerCount: 0,
                allocatedDailyTokenBudget: 0,
                unlimitedBudgetConsumerCount: 0,
                observedConsumerTokensUsed: 0,
                oversubscribedFamilyCount: 0
            ),
            riskVendorCount: 0,
            riskFamilyCount: 0,
            overallTrendCard: nil,
            vendorTrendCards: [],
            familyTrendCards: [],
            userTrendCards: [],
            consumerTrendCards: [],
            trendCardCount: 0,
            operationalTint: .blue
        )
    }

    nonisolated static func loadProviderKeySnapshotWithBootstrapBackground() async -> ProviderKeyStoreSnapshot {
        RemoteProviderKeyBootstrapper.bootstrapIfNeeded()
        if let rustSnapshot = await RustProviderKeySnapshotSupport.loadSnapshot() {
            return rustSnapshot
        }
        return ProviderKeyStorage.load()
    }

    nonisolated private static func loadProviderKeyStateWithBootstrapBackground() async -> (
        snapshot: ProviderKeyStoreSnapshot,
        derived: ProviderKeyStoreDerivedSnapshot
    ) {
        let snapshot = await loadProviderKeySnapshotWithBootstrapBackground()
        return (
            snapshot: snapshot,
            derived: ProviderKeyStorage.derivedSnapshot(from: snapshot)
        )
    }

    nonisolated private static func makeRemoteQuotaProjectionSnapshot(
        providerKeySnapshot: ProviderKeyStoreSnapshot,
        remoteModels: [RemoteModelEntry],
        clients: [HubGRPCClientEntry],
        terminalAccessKeys: [HubTerminalAccessKey],
        deviceStatusSnapshot: GRPCDevicesStatusSnapshot
    ) -> RemoteQuotaCenterProjection {
        RemoteQuotaCenterSupport.projection(
            providerKeySnapshot: providerKeySnapshot,
            remoteModels: remoteModels,
            clients: clients,
            terminalAccessKeys: terminalAccessKeys,
            deviceStatusSnapshot: deviceStatusSnapshot
        )
    }

    func reloadProviderKeySnapshot(rebuildProjection: Bool? = nil) {
        providerKeyReloadTask?.cancel()
        providerKeyReloadTask = Task { @MainActor in
            let state = await Task.detached(priority: .utility) {
                await Self.loadProviderKeyStateWithBootstrapBackground()
            }.value
            guard !Task.isCancelled else { return }
            providerKeySnapshot = state.snapshot
            providerKeyDerivedSnapshot = state.derived
            lastProviderKeyPeriodicRefreshAt = Date()
            let shouldRebuildProjection = rebuildProjection
                ?? (selectedSettingsPage == .models && providerQuotaOperationsExpanded)
            if shouldRebuildProjection {
                rebuildRemoteQuotaProjectionSnapshot()
            }
        }
    }

    func rebuildRemoteQuotaProjectionSnapshot() {
        let providerKeySnapshot = providerKeySnapshot
        let remoteModels = remoteModels
        let clients = grpc.allowedClients
        let terminalAccessKeys = terminalAccessKeys
        let deviceStatusSnapshot = grpcDevicesStatus
        remoteQuotaProjectionBuildTask?.cancel()
        remoteQuotaProjectionBuildTask = Task { @MainActor in
            let projection = await Task.detached(priority: .utility) {
                Self.makeRemoteQuotaProjectionSnapshot(
                    providerKeySnapshot: providerKeySnapshot,
                    remoteModels: remoteModels,
                    clients: clients,
                    terminalAccessKeys: terminalAccessKeys,
                    deviceStatusSnapshot: deviceStatusSnapshot
                )
            }.value
            guard !Task.isCancelled else { return }
            remoteQuotaProjectionSnapshot = projection
            lastRemoteQuotaProjectionPeriodicRefreshAt = Date()
            maybeRebuildProviderKeySectionSnapshot()
        }
    }

    func reloadNetworkPolicies() {
        let list = HubNetworkPolicyStorage.load().policies
        networkPolicies = list.sorted {
            if $0.appId != $1.appId { return $0.appId < $1.appId }
            return $0.projectId < $1.projectId
        }
    }

    func updatePolicy(_ rule: HubNetworkPolicyRule, mode: HubNetworkPolicyMode?, maxSeconds: Int?) {
        var r = rule
        if let m = mode { r.mode = m }
        r.maxSeconds = maxSeconds
        r.updatedAt = Date().timeIntervalSince1970
        _ = HubNetworkPolicyStorage.upsert(r)
        reloadNetworkPolicies()
        store.reloadNetworkPolicySnapshot()
    }

    func removePolicy(_ rule: HubNetworkPolicyRule) {
        _ = HubNetworkPolicyStorage.remove(id: rule.id)
        reloadNetworkPolicies()
        store.reloadNetworkPolicySnapshot()
    }

    func policyModeText(_ mode: HubNetworkPolicyMode) -> String {
        switch mode {
        case .manual: return HubUIStrings.Settings.NetworkPolicies.manual
        case .autoApprove: return HubUIStrings.Settings.NetworkPolicies.autoApprove
        case .alwaysOn: return HubUIStrings.Settings.NetworkPolicies.alwaysAllow
        case .deny: return HubUIStrings.Settings.NetworkPolicies.alwaysDeny
        }
    }

    func policyLimitText(_ maxSeconds: Int?) -> String {
        guard let s = maxSeconds, s > 0 else { return HubUIStrings.Settings.NetworkPolicies.defaultLimit }
        let mins = max(1, s / 60)
        if mins >= 60 {
            let hours = max(1, mins / 60)
            return HubUIStrings.Settings.NetworkPolicies.hours(hours)
        }
        return HubUIStrings.Settings.NetworkPolicies.minutes(mins)
    }
}
