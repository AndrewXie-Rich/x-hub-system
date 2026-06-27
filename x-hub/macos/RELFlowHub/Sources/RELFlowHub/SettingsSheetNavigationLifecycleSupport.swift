import Foundation
import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    func pairedTerminalLocalModels() -> [ModelCatalogEntry] {
        ModelCatalogStorage.load().models
            .filter { !$0.modelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { lhs, rhs in
                let lhsKey = (lhs.name.isEmpty ? lhs.id : lhs.name).localizedLowercase
                let rhsKey = (rhs.name.isEmpty ? rhs.id : rhs.name).localizedLowercase
                if lhsKey != rhsKey {
                    return lhsKey < rhsKey
                }
                return lhs.id.localizedLowercase < rhs.id.localizedLowercase
            }
    }

    func pairedTerminalLocalModelProfiles(
        deviceId: String,
        localModels: [ModelCatalogEntry]
    ) -> [String: HubPairedTerminalLocalModelProfile] {
        var profiles: [String: HubPairedTerminalLocalModelProfile] = [:]
        for model in localModels {
            guard let profile = grpc.pairedTerminalLocalModelProfile(deviceId: deviceId, modelId: model.id) else {
                continue
            }
            profiles[model.id] = profile
        }
        return profiles
    }

    func handleSettingsNavigationTarget(_ target: HubSettingsNavigationTarget?) {
        guard let target else { return }
        switch target {
        case .pairedDevices(let deviceID, let capabilityKey):
            selectedSettingsPage = .access
            grpcClientListFilter = .all
            if let normalizedDeviceID = deviceID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !normalizedDeviceID.isEmpty {
                let client = grpc.allowedClients.first(where: { entry in
                    entry.deviceId == normalizedDeviceID
                })
                presentGRPCClientEditor(client, capabilityFocusKey: capabilityKey)
            } else {
                editingGRPCClientFocusCapabilityKey = hubNormalizedPairedDeviceCapabilityFocusKey(capabilityKey)
                editingGRPCClient = nil
            }
            store.consumeSettingsNavigationTarget(target)
        case .providerKeys(let sourceRef):
            selectedSettingsPage = .models
            providerQuotaOperationsExpanded = true
            let normalizedSourceRef = hubNormalizedProviderKeySourceRef(sourceRef)
            highlightedProviderKeySourceRef = normalizedSourceRef
            providerImportSourcesExpanded = true
            let anchorID = providerKeyImportSourceAnchorID(sourceRef: normalizedSourceRef)
                ?? providerKeySectionAnchorID
            settingsScrollTarget = nil
            DispatchQueue.main.async {
                settingsScrollTarget = anchorID
            }
            scheduleProviderKeyHighlightClear(normalizedSourceRef)
            store.consumeSettingsNavigationTarget(target)
        case .diagnostics:
            selectedSettingsPage = .diagnostics
            diagnosticsLaunchExpanded = true
            settingsScrollTarget = nil
            DispatchQueue.main.async {
                settingsScrollTarget = diagnosticsLaunchSectionAnchorID
            }
            store.consumeSettingsNavigationTarget(target)
        }
    }

    func scrollToSettingsTargetIfNeeded(_ proxy: ScrollViewProxy) {
        guard let settingsScrollTarget else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(settingsScrollTarget, anchor: .top)
            }
        }
    }

    private func scheduleProviderKeyHighlightClear(_ sourceRef: String?) {
        guard let sourceRef else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            if highlightedProviderKeySourceRef == sourceRef {
                highlightedProviderKeySourceRef = nil
            }
        }
    }

    private func scheduleProviderKeyVendorHighlightClear(_ vendorKey: String?) {
        guard let vendorKey else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            if highlightedProviderKeyVendorKey == vendorKey {
                highlightedProviderKeyVendorKey = nil
            }
        }
    }

    var providerKeySectionAnchorID: String {
        "provider_keys_section"
    }

    func providerKeyVendorAnchorID(_ vendorKey: String) -> String {
        "provider_key_vendor_" + providerKeyCanonicalVendorKey(vendorKey)
    }

    var providerKeyUserLedgerAnchorID: String {
        "provider_key_user_ledger"
    }

    var providerKeyConsumerLedgerAnchorID: String {
        "provider_key_consumer_ledger"
    }

    var terminalAccessSectionAnchorID: String {
        "terminal_access_section"
    }

    var diagnosticsLaunchSectionAnchorID: String {
        "diagnostics_launch_section"
    }

    func providerKeyImportSourceAnchorID(
        _ source: ProviderKeyImportSourceStatus
    ) -> String {
        providerKeyImportSourceAnchorID(
            sourceRef: hubNormalizedProviderKeySourceRef(source.sourceRef)
        ) ?? providerKeySectionAnchorID
    }

    func providerKeyImportSourceAnchorID(sourceRef: String?) -> String? {
        guard let normalizedSourceRef = hubNormalizedProviderKeySourceRef(sourceRef) else { return nil }
        return "provider_key_source::\(normalizedSourceRef)"
    }

    func presentGRPCClientEditor(
        _ client: HubGRPCClientEntry?,
        capabilityFocusKey: String? = nil
    ) {
        editingGRPCClientFocusCapabilityKey = hubNormalizedPairedDeviceCapabilityFocusKey(capabilityFocusKey)
        editingGRPCClient = client
    }

    func presentRemoteQuotaConsumerManager(
        _ consumer: RemoteQuotaCenterClientProjection
    ) {
        if let client = consumer.grpcClient {
            selectedSettingsPage = .access
            presentGRPCClientEditor(client, capabilityFocusKey: "ai.generate.paid")
            return
        }

        guard let accessKey = consumer.terminalAccessKey else { return }
        selectedSettingsPage = .access
        terminalAccessErrorText = ""
        terminalAccessActionText = "已定位到 \(accessKey.resolvedName)。可在这里轮换、撤销或重新签发普通 terminal API key。"
        settingsScrollTarget = nil
        DispatchQueue.main.async {
            settingsScrollTarget = terminalAccessSectionAnchorID
        }
    }

    func presentRemoteQuotaUserManager(
        _ user: RemoteQuotaCenterUserProjection
    ) {
        if user.consumers.count == 1, let consumer = user.consumers.first {
            presentRemoteQuotaConsumerManager(consumer)
            return
        }

        if user.xtConsumerCount == user.consumerCount {
            remoteQuotaConsumerFilter = .xt
        } else if user.terminalConsumerCount == user.consumerCount {
            remoteQuotaConsumerFilter = .terminal
        } else {
            remoteQuotaConsumerFilter = .all
        }

        selectedSettingsPage = .models
        providerQuotaOperationsExpanded = true
        providerConsumerLedgerExpanded = true
        settingsScrollTarget = nil
        DispatchQueue.main.async {
            settingsScrollTarget = providerKeyConsumerLedgerAnchorID
        }
    }

    func selectSettingsPage(_ page: HubSettingsPage) {
        selectedSettingsPage = page
        settingsScrollTarget = nil
    }

    func openCLIProxyOAuthInventoryManager() {
        let normalizedSourceRef = CLIProxyOAuthSourceSupport.normalizedBaseURLString(
            cliproxyOAuthSettings.baseURL
        )
        let anchorID = providerKeyImportSourceAnchorID(sourceRef: normalizedSourceRef)
            ?? providerKeySectionAnchorID
        selectedSettingsPage = .models
        providerQuotaOperationsExpanded = true
        providerImportSourcesExpanded = true
        settingsScrollTarget = nil
        DispatchQueue.main.async {
            settingsScrollTarget = anchorID
        }
    }

    func focusProviderKeyVendor(
        _ rawVendorKey: String,
        displayName: String? = nil
    ) {
        let vendorKey = providerKeyCanonicalVendorKey(rawVendorKey)
        let normalizedDisplayName = displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let vendorDisplayName = normalizedDisplayName.isEmpty
            ? providerKeyVendorDisplayName(vendorKey)
            : normalizedDisplayName
        let hasVendor = providerKeyDerivedSnapshot.keyPools.contains { pool in
            providerKeyCanonicalVendorKey(pool.supplierKey) == vendorKey
        }

        selectedSettingsPage = .models
        providerQuotaOperationsExpanded = true
        remoteQuotaVendorFilter = .all
        remoteQuotaFocusedVendorKey = vendorKey
        highlightedProviderKeyVendorKey = vendorKey
        providerVendorLedgerExpanded = true
        expandedProviderKeyVendorIDs.insert(vendorKey)
        settingsScrollTarget = nil
        remoteQuotaErrorText = ""
        remoteQuotaActionText = hasVendor
            ? "已定位到 \(vendorDisplayName) 厂家账本。这里可以继续看库存、覆盖预算和热点池。"
            : "\(vendorDisplayName) 当前还没有同步进 Hub 厂家总账。先点“同步到 Hub”再看库存与额度分配。"

        DispatchQueue.main.async {
            settingsScrollTarget = hasVendor
                ? providerKeyVendorAnchorID(vendorKey)
                : providerKeySectionAnchorID
        }
        scheduleProviderKeyVendorHighlightClear(vendorKey)
    }

    func focusProviderKeyVendorUser(
        _ user: RemoteQuotaCenterUserProjection,
        vendor: ProviderKeyVendorInventorySummary
    ) {
        let vendorKey = providerKeyCanonicalVendorKey(vendor.vendorKey)

        selectedSettingsPage = .models
        providerQuotaOperationsExpanded = true
        remoteQuotaVendorFilter = .all
        remoteQuotaUserFilter = .all
        remoteQuotaConsumerFilter = .all
        remoteQuotaFocusedVendorKey = vendorKey
        remoteQuotaFocusedUserGroupingKey = user.groupingKey
        highlightedProviderKeyVendorKey = vendorKey
        providerVendorLedgerExpanded = true
        providerUserLedgerExpanded = true
        expandedProviderKeyVendorIDs.insert(vendorKey)
        settingsScrollTarget = nil
        remoteQuotaErrorText = ""
        remoteQuotaActionText =
            "已锁定 \(vendor.displayName) / \(user.displayName)。下面的家族、用户和消费者台账都会收窄到这条配额链路。"

        DispatchQueue.main.async {
            settingsScrollTarget = providerKeyUserLedgerAnchorID
        }
        scheduleProviderKeyVendorHighlightClear(vendorKey)
    }

    func reloadSettingsSurfaceData() {
        remoteRouteProbe.refresh(host: grpc.xtTerminalInternetHost)
        rebuildLocalModelSnapshot()
        reloadProviderKeySnapshot()
        reloadRemoteModels()
        reloadNetworkPolicies()
        reloadCLIProxyRuntimeConfiguration()
        reloadCLIProxyOAuthConfiguration()
        reloadAXConstitutionStatus()
        refreshRustHubRuntimeSnapshot(force: true)
        refreshRustLocalMLExecutionReadiness(force: true)
        refreshRustLocalModelRepairPlan(force: true)
        refreshRustLocalModelRepairJobs(force: true)
        refreshRustHubRemoteEntryCandidates(force: true)
        Task { await reloadOperatorChannelProviderReadiness() }
        Task { await reloadTerminalAccessKeys() }
        Task { await refreshCLIProxyRuntimeStatus() }
        Task { await refreshCLIProxyOAuthRemoteAuths() }
    }

    func rebuildLocalModelSnapshot() {
        localModelSnapshot = SettingsLocalModelSnapshot.build(
            from: modelStore.snapshot.models
        )
    }

    func refreshVisibleSettingsPageIfNeeded(now: Date = Date()) {
        switch selectedSettingsPage {
        case .overview:
            grpcDevicesStatus = GRPCDevicesStatusStorage.load()
            grpcDeniedAttempts = GRPCDeniedAttemptsStorage.load()
            hubLaunchStatus = HubLaunchStatusStorage.load()
            remoteRouteProbe.refresh(host: grpc.xtTerminalInternetHost)
            refreshRustHubRemoteEntryCandidates()
            Task { await maybeAutoSyncCLIProxyOAuthAccounts() }
        case .access:
            grpcDevicesStatus = GRPCDevicesStatusStorage.load()
            grpcDeniedAttempts = GRPCDeniedAttemptsStorage.load()
            remoteRouteProbe.refresh(host: grpc.xtTerminalInternetHost)
            refreshRustHubRemoteEntryCandidates()
        case .models:
            refreshModelsPageIfNeeded(now: now)
            if providerOAuthExpanded || providerQuotaOperationsExpanded {
                Task { await maybeAutoSyncCLIProxyOAuthAccounts() }
            }
        case .runtime:
            hubLaunchStatus = HubLaunchStatusStorage.load()
            refreshRustHubRuntimeSnapshot()
            refreshRustLocalMLExecutionReadiness()
            refreshRustLocalModelRepairPlan()
            refreshRustLocalModelRepairJobs()
            Task { await maybeRefreshCLIProxyRuntimeStatus() }
        case .integrations:
            skillsIndex = HubSkillsStoreStorage.loadSkillsIndex()
            skillsPins = HubSkillsStoreStorage.loadSkillPins()
            skillsSources = HubSkillsStoreStorage.loadSkillSources()
            Task { await reloadOperatorChannelProviderReadiness() }
        case .diagnostics:
            grpcDeniedAttempts = GRPCDeniedAttemptsStorage.load()
            hubLaunchStatus = HubLaunchStatusStorage.load()
            hubLaunchHistory = HubLaunchHistoryStorage.load()
            reloadAXConstitutionStatus()
        }

        if !cliproxyOAuthActiveState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Task { await pollCLIProxyOAuthLogin() }
        }
    }

    private func refreshModelsPageIfNeeded(now: Date = Date()) {
        guard selectedSettingsPage == .models else { return }

        if now.timeIntervalSince(lastProviderKeyPeriodicRefreshAt) >= 12 {
            lastProviderKeyPeriodicRefreshAt = now
            reloadProviderKeySnapshot(rebuildProjection: providerQuotaOperationsExpanded)
        }

        guard providerQuotaOperationsExpanded else { return }
        if now.timeIntervalSince(lastRemoteQuotaProjectionPeriodicRefreshAt) >= 6 {
            lastRemoteQuotaProjectionPeriodicRefreshAt = now
            grpcDevicesStatus = GRPCDevicesStatusStorage.load()
            rebuildRemoteQuotaProjectionSnapshot()
        }
    }


}
