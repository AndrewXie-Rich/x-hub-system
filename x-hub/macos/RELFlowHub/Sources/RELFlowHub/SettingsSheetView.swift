import SwiftUI
import AppKit
import RELFlowHubCore

struct SettingsSheetView: View {
    @EnvironmentObject var store: HubStore
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var grpc = HubGRPCServerSupport.shared
    @ObservedObject var modelStore = ModelStore.shared
    @ObservedObject var servingPower = HubServingPowerManager.shared
    @ObservedObject var remoteRouteProbe = HubRemoteAccessRouteProbe.shared

    @State var remoteModels: [RemoteModelEntry] = sortedRemoteModels(RemoteModelStorage.load().models)
    @State var providerKeySnapshot: ProviderKeyStoreSnapshot = ProviderKeyStorage.load()
    @State var providerKeyDerivedSnapshot: ProviderKeyStoreDerivedSnapshot = ProviderKeyStorage.derivedSnapshot(
        from: ProviderKeyStorage.load()
    )
    @State var localModelSnapshot: SettingsLocalModelSnapshot = SettingsLocalModelSnapshot.build(
        from: ModelStore.shared.snapshot.models
    )
    @State var showDiscoverModels: Bool = false
    @State var showAddModel: Bool = false
    @State var showAddRemoteModel: Bool = false
    @State var showImportRemoteCatalog: Bool = false
    @State var editingRemoteModelGroup: RemoteModelKeyGroup? = nil
    @State var networkPolicies: [HubNetworkPolicyRule] = HubNetworkPolicyStorage.load().policies
    @State var showAddNetworkPolicy: Bool = false
    @State var showAddGRPCClient: Bool = false
    @State var editingGRPCClient: HubGRPCClientEntry? = nil
    @State var editingGRPCClientFocusCapabilityKey: String? = nil
    @State var deletingGRPCClient: HubGRPCClientEntry? = nil
    @State var grpcClientListFilter: GRPCClientListFilter = .all
    @State var grpcDevicesStatus: GRPCDevicesStatusSnapshot = GRPCDevicesStatusStorage.load()
    @State var grpcDeniedAttempts: GRPCDeniedAttemptsSnapshot = GRPCDeniedAttemptsStorage.load()
    @State var hubLaunchStatus: HubLaunchStatusSnapshot? = HubLaunchStatusStorage.load()
    @State private var hubLaunchHistory: HubLaunchHistorySnapshot = HubLaunchHistoryStorage.load()
    @State private var diagnosticsBundleIsExporting: Bool = false
    @State private var diagnosticsBundleArchivePath: String = ""
    @State private var diagnosticsBundleManifestPath: String = ""
    @State private var diagnosticsBundleMissingFiles: [String] = []
    @State private var diagnosticsBundleError: String = ""
    @State private var unifiedDoctorReportIsExporting: Bool = false
    @State private var unifiedDoctorReportPath: String = ""
    @State private var unifiedDoctorChannelReportPath: String = ""
    @State private var unifiedDoctorReportError: String = ""
    @State private var fixNowIsRunning: Bool = false
    @State private var fixNowResultText: String = ""
    @State private var fixNowErrorText: String = ""
    @State private var diagnosticsActionIsRunning: Bool = false
    @State private var diagnosticsActionResultText: String = ""
    @State private var diagnosticsActionErrorText: String = ""
    @State private var settingsScrollTarget: String? = nil
    @State var highlightedProviderKeySourceRef: String? = nil
    @State var highlightedProviderKeyVendorKey: String? = nil
    @State private var expandedProviderKeyPoolIssueIDs: Set<String> = []
    @State private var expandedProviderKeyMemberIssueIDs: Set<String> = []
    @State var remoteQuotaActionText: String = ""
    @State var remoteQuotaErrorText: String = ""

    @State var skillsIndex: HubSkillsStoreStorage.SkillsIndexSnapshot = HubSkillsStoreStorage.loadSkillsIndex()
    @State var skillsPins: HubSkillsStoreStorage.SkillPinsSnapshot = HubSkillsStoreStorage.loadSkillPins()
    @State var skillsSources: HubSkillsStoreStorage.SkillSourcesSnapshot = HubSkillsStoreStorage.loadSkillSources()
    @State var skillsSearchQuery: String = ""
    @State var skillsResolveUserId: String = ""
    @State var skillsResolveProjectId: String = ""
    @State var skillsLastActionText: String = ""
    @State var skillsLastErrorText: String = ""
    @State var axConstitutionVersion: String = ""
    @State var axConstitutionEnabledClauseIds: [String] = []
    @State var axConstitutionErrorText: String = ""
    @State private var operatorChannelProviderReadiness: [HubOperatorChannelOnboardingDeliveryReadiness] = []
    @State private var operatorChannelProviderRuntimeStatus: [HubOperatorChannelProviderRuntimeStatus] = []
    @State private var operatorChannelProviderReadinessError: String = ""
    @State private var operatorChannelProviderReadinessInFlight: Bool = false
    @State private var operatorChannelProviderReadinessActionText: String = ""
    @State var terminalAccessKeys: [HubTerminalAccessKey] = []
    @State var terminalAccessDraft: HubTerminalAccessKeyDraft = .init()
    @State var terminalAccessLastSecret: HubTerminalAccessKeySecretEnvelope? = nil
    @State var terminalAccessActionText: String = ""
    @State var terminalAccessErrorText: String = ""
    @State var terminalAccessReloadInFlight: Bool = false
    @State var terminalAccessMutationInFlight: Bool = false
    @State var terminalAccessPendingRevokeAccessKeyID: String = ""
    @State var terminalAccessExampleKind: TerminalAccessExampleKind = .python
    @State var cliproxyRuntimeSettings: CLIProxyRuntimeSupport.Settings = CLIProxyRuntimeSupport.loadSettings()
    @State var cliproxyRuntimeProbe: CLIProxyRuntimeSupport.Probe = .init()
    @State var cliproxyRuntimeRefreshing: Bool = false
    @State var cliproxyRuntimeLaunching: Bool = false
    @State var cliproxyRuntimeConfigApplying: Bool = false
    @State var cliproxyRuntimeKeyRotating: Bool = false
    @State var cliproxyRuntimeConfigAudit: CLIProxyRuntimeSupport.ConfigAudit = .empty
    @State var cliproxyRuntimeActionText: String = ""
    @State var cliproxyRuntimeErrorText: String = ""
    @State var cliproxyRuntimeLastProbeAtMs: Int64 = 0
    @State private var cliproxyRuntimeFastProbeUntilMs: Int64 = 0
    @State var rustHubRuntimeSnapshot: RustHubRuntimeSnapshot = RustHubRuntimeSupport.localSnapshot()
    @State var rustHubRuntimeRefreshing: Bool = false
    @State private var rustHubRuntimeLastRefreshAt: Date = .distantPast
    @State var rustLocalModelRepairPlan: RustLocalModelRepairPlan? = nil
    @State private var rustLocalModelRepairPlanRefreshing: Bool = false
    @State private var rustLocalModelRepairPlanLastRefreshAt: Date = .distantPast
    @State private var rustLocalModelRepairApplyDialogPresented: Bool = false
    @State private var rustLocalModelRepairApplyPendingPlan: RustLocalModelRepairPlan? = nil
    @State var rustLocalModelRepairApplyInFlight: Bool = false
    @State var rustLocalModelRepairApplyResult: RustLocalModelRepairApplyResult? = nil
    @State var rustLocalModelRepairExecutorInFlight: Bool = false
    @State var rustLocalModelRepairExecutorResult: RustLocalModelRepairExecutorResult? = nil
    @State var rustLocalModelRepairApplyErrorText: String = ""
    @State var rustLocalModelRepairJobsSnapshot: RustLocalModelRepairJobsSnapshot = .empty
    @State private var rustLocalModelRepairJobsRefreshing: Bool = false
    @State private var rustLocalModelRepairJobsLastRefreshAt: Date = .distantPast
    @State private var rustHubRemoteEntryCandidates: RustHubRemoteEntryCandidates = .empty
    @State var rustHubRemoteEntryRefreshing: Bool = false
    @State private var rustHubRemoteEntryLastRefreshAt: Date = .distantPast
    @State var cliproxyOAuthSettings: CLIProxyOAuthSourceSupport.Settings = CLIProxyOAuthSourceSupport.loadSettings()
    @State var cliproxyOAuthManagementKey: String = CLIProxyOAuthSourceSupport.loadManagementKey(
        baseURL: CLIProxyOAuthSourceSupport.loadSettings().baseURL
    )
    @State var cliproxyOAuthRemoteAuths: [CLIProxyOAuthSourceSupport.RemoteAuthFile] = []
    @State var cliproxyOAuthActionText: String = ""
    @State var cliproxyOAuthErrorText: String = ""
    @State var cliproxyOAuthRefreshing: Bool = false
    @State var cliproxyOAuthSyncing: Bool = false
    @State var cliproxyOAuthActiveState: String = ""
    @State var cliproxyOAuthActiveProvider: HubProviderOAuthHTTPClient.Provider? = nil
    @State var cliproxyOAuthLastRemoteFetchAtMs: Int64 = 0
    @State private var cliproxyOAuthLastAutoSyncAtMs: Int64 = 0
    @State private var remoteQuotaBudgetEditorTarget: RemoteQuotaBudgetEditorTarget? = nil
    @State var remoteQuotaFocusedUserGroupingKey: String = ""
    @State var remoteQuotaFocusedVendorKey: String = ""
    @State var remoteQuotaVendorFilter: RemoteQuotaVendorFilter = .all
    @State var remoteQuotaUserFilter: RemoteQuotaUserFilter = .all
    @State var remoteQuotaConsumerFilter: RemoteQuotaConsumerFilter = .all
    @State private var selectedSettingsPage: HubSettingsPage = .overview
    @State var modelCatalogDetailsExpanded: Bool = false
    @State var modelsAutoScanExpanded: Bool = false
    @State var providerQuotaOperationsExpanded: Bool = false
    @State var runtimeRoutingExpanded: Bool = false
    @State private var integrationsAuxExpanded: Bool = false
    @State private var diagnosticsLaunchExpanded: Bool = false
    @State private var diagnosticsNetworkExpanded: Bool = false
    @State private var diagnosticsAdvancedExpanded: Bool = false
    @State var expandedGRPCClientDetailIDs: Set<String> = []
    @State var expandedTerminalAccessKeyDetailIDs: Set<String> = []
    @State var expandedProviderKeyVendorIDs: Set<String> = []
    @State var expandedProviderKeyPoolIDs: Set<String> = []
    @State var terminalAccessIssueExpanded: Bool = false
    @State var terminalAccessLastSecretExpanded: Bool = false
    @State var expandedRemoteModelGroupIDs: Set<String> = []
    @State var remoteModelCatalogExpanded: Bool = false
    @State private var remoteModelGroupsSnapshot: [RemoteModelKeyGroup] = []
    @State var providerImportSourcesExpanded: Bool = false
    @State var providerVendorLedgerExpanded: Bool = false
    @State var providerFamilyLedgerExpanded: Bool = false
    @State var providerPhysicalPoolsExpanded: Bool = false
    @State var providerUserLedgerExpanded: Bool = false
    @State var providerConsumerLedgerExpanded: Bool = false
    @State var providerOAuthExpanded: Bool = false
    @State var providerFlowExpanded: Bool = false
    @State var providerTrendExpanded: Bool = false
    @State private var remoteModelGroupsBuildTask: Task<Void, Never>? = nil
    @State private var providerKeyReloadTask: Task<Void, Never>? = nil
    @State private var remoteQuotaProjectionSnapshot: RemoteQuotaCenterProjection = Self.emptyRemoteQuotaProjection()
    @State private var remoteQuotaProjectionBuildTask: Task<Void, Never>? = nil
    @State var providerKeySectionSnapshot: ProviderKeySectionSnapshot = Self.emptyProviderKeySectionSnapshot()
    @State private var lastProviderKeyPeriodicRefreshAt: Date = .distantPast
    @State private var lastRemoteQuotaProjectionPeriodicRefreshAt: Date = .distantPast

    var axTrusted: Bool {
        DockBadgeReader.ensureAccessibilityTrusted(prompt: false)
    }

    var xhubLocalServiceRecoveryGuidance: XHubLocalServiceRecoveryGuidance? {
        XHubLocalServiceRecoveryGuidanceBuilder.build(
            status: store.aiRuntimeStatusSnapshot,
            blockedCapabilities: hubLaunchStatus?.degraded.blockedCapabilities ?? []
        )
    }

    private var runtimeRepairSurfaceSummary: LocalRuntimeRepairSurfaceSummary? {
        LocalRuntimeRepairSurfaceSummaryBuilder.build(
            status: store.aiRuntimeStatusSnapshot,
            blockedCapabilities: hubLaunchStatus?.degraded.blockedCapabilities ?? []
        )
    }

    private var rustLocalModelRepairSurfaceSummary: LocalRuntimeRepairSurfaceSummary? {
        LocalRuntimeRepairSurfaceSummaryBuilder.build(rustRepairPlan: rustLocalModelRepairPlan)
    }

    var effectiveRuntimeRepairSurfaceSummary: LocalRuntimeRepairSurfaceSummary? {
        rustLocalModelRepairSurfaceSummary ?? runtimeRepairSurfaceSummary
    }

    var grpcRemoteAccessHealthSummary: HubRemoteAccessHealthSummary {
        HubRemoteAccessHealthSummaryBuilder.build(
            autoStartEnabled: grpc.autoStart,
            serverRunning: grpc.isServingAvailable,
            externalHost: grpc.xtTerminalInternetHost,
            hasInviteToken: grpc.hasExternalInviteToken,
            keepSystemAwakeWhileServing: servingPower.keepSystemAwakeWhileServing,
            allowPrivateVPNIP: grpc.allowsPrivateVPNIPForSecureRemoteSetupPack
        )
    }

    var noDomainPrivateRemoteHost: String? {
        rustHubRemoteEntryCandidates.preferredNoDomainPrivateHost
            ?? grpc.noDomainPrivateRemoteHost
    }

    var noDomainPrivateRemoteHostSourceText: String {
        if rustHubRemoteEntryCandidates.preferredNoDomainPrivateHost != nil {
            return HubUIStrings.Settings.GRPC.noDomainRustCoreSource
        }
        return HubUIStrings.Settings.GRPC.noDomainSwiftFallbackSource
    }

    var isUsingNoDomainPrivateRemoteHost: Bool {
        grpc.isUsingNoDomainPrivateRemoteHost(noDomainPrivateRemoteHost)
    }

    private var remoteQuotaProjection: RemoteQuotaCenterProjection {
        remoteQuotaProjectionSnapshot
    }

    func quitApp() {
        // Some LSUIElement apps can get into a state where `terminate` is ignored.
        // Use forceTerminate as a fallback so users don't need Terminal.
        let app = NSRunningApplication.current
        // Stop the AI runtime so upgrades don't inherit a stale long-lived worker.
        store.stopAIRuntime()
        dismiss()
        NSApp.terminate(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if !app.isTerminated {
                _ = app.forceTerminate()
            }
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    headerLaunchTint.opacity(0.08),
                    Color(nsColor: .underPageBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                header
                formContent
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .frame(
            minWidth: 920,
            idealWidth: 1088,
            maxWidth: .infinity,
            minHeight: 620,
            idealHeight: 700,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .onAppear {
            reloadSettingsSurfaceData()
            grpcDevicesStatus = GRPCDevicesStatusStorage.load()
            grpcDeniedAttempts = GRPCDeniedAttemptsStorage.load()
            hubLaunchStatus = HubLaunchStatusStorage.load()
            hubLaunchHistory = HubLaunchHistoryStorage.load()
            skillsIndex = HubSkillsStoreStorage.loadSkillsIndex()
            skillsPins = HubSkillsStoreStorage.loadSkillPins()
            skillsSources = HubSkillsStoreStorage.loadSkillSources()
            handleSettingsNavigationTarget(store.settingsNavigationTarget)
        }
        .onChange(of: store.settingsNavigationTarget) { target in
            handleSettingsNavigationTarget(target)
        }
        .onChange(of: selectedSettingsPage) { _ in
            maybeRebuildProviderKeySectionSnapshot()
            if selectedSettingsPage == .runtime {
                refreshRustHubRuntimeSnapshot(force: true)
                refreshRustLocalModelRepairPlan(force: true)
                refreshRustLocalModelRepairJobs(force: true)
            }
            if selectedSettingsPage == .access || selectedSettingsPage == .overview {
                refreshRustHubRemoteEntryCandidates(force: true)
            }
        }
        .onChange(of: modelStore.snapshot.updatedAt) { _ in
            rebuildLocalModelSnapshot()
        }
        .onChange(of: providerQuotaOperationsExpanded) { expanded in
            guard expanded else { return }
            rebuildRemoteQuotaProjectionSnapshot()
        }
        .onChange(of: remoteQuotaFocusedUserGroupingKey) { _ in
            maybeRebuildProviderKeySectionSnapshot()
        }
        .onChange(of: remoteQuotaFocusedVendorKey) { _ in
            maybeRebuildProviderKeySectionSnapshot()
        }
        .onChange(of: remoteQuotaVendorFilter) { _ in
            maybeRebuildProviderKeySectionSnapshot()
        }
        .onChange(of: remoteQuotaUserFilter) { _ in
            maybeRebuildProviderKeySectionSnapshot()
        }
        .onChange(of: remoteQuotaConsumerFilter) { _ in
            maybeRebuildProviderKeySectionSnapshot()
        }
        .onChange(of: providerFlowExpanded) { _ in
            maybeRebuildProviderKeySectionSnapshot()
        }
        .onChange(of: providerTrendExpanded) { _ in
            maybeRebuildProviderKeySectionSnapshot()
        }
        .onChange(of: providerVendorLedgerExpanded) { _ in
            maybeRebuildProviderKeySectionSnapshot()
        }
        .onReceive(Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()) { _ in
            refreshVisibleSettingsPageIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .relflowhubRemoteModelsChanged)) { _ in
            reloadRemoteModels()
        }
        .onReceive(NotificationCenter.default.publisher(for: .relflowhubRemoteKeyHealthChanged)) { _ in
            rebuildRemoteModelGroupsSnapshot()
            reloadProviderKeySnapshot()
        }
        .onDisappear {
            remoteModelGroupsBuildTask?.cancel()
            remoteModelGroupsBuildTask = nil
            providerKeyReloadTask?.cancel()
            providerKeyReloadTask = nil
            remoteQuotaProjectionBuildTask?.cancel()
            remoteQuotaProjectionBuildTask = nil
        }
        .sheet(isPresented: $showAddRemoteModel) {
            AddRemoteModelSheet { entries in
                upsertRemoteModels(entries)
            }
        }
        .sheet(isPresented: $showDiscoverModels) {
            DiscoverModelsSheet()
        }
        .sheet(isPresented: $showAddModel) {
            AddModelSheet()
        }
        .sheet(isPresented: $showImportRemoteCatalog) {
            ImportRemoteCatalogSheet { result in
                importRemoteCatalog(result)
            }
        }
        .sheet(item: $editingRemoteModelGroup) { group in
            EditRemoteModelGroupDisplayNameSheet(group: group) { displayName in
                updateRemoteModelGroupDisplayName(group, displayName: displayName)
            }
        }
        .sheet(isPresented: $showAddNetworkPolicy) {
            AddNetworkPolicySheet { rule in
                _ = HubNetworkPolicyStorage.upsert(rule)
                reloadNetworkPolicies()
                store.reloadNetworkPolicySnapshot()
            }
        }
        .sheet(isPresented: $showAddGRPCClient) {
            AddGRPCClientSheet { deviceName in
                let entry = grpc.createClient(name: deviceName)
                grpc.copyConnectVars(for: entry)
            }
        }
        .sheet(item: $remoteQuotaBudgetEditorTarget) { target in
            RemoteQuotaBudgetEditorSheet(target: target) { dailyTokenLimit in
                applyRemoteQuotaBudgetEdit(target, dailyTokenLimit: dailyTokenLimit)
            }
        }
        .sheet(
            item: $editingGRPCClient,
            onDismiss: {
                editingGRPCClientFocusCapabilityKey = nil
            }
        ) { client in
            let localModels = pairedTerminalLocalModels()
            EditGRPCClientSheet(
                client: client,
                serverPort: grpc.port,
                localModels: localModels,
                routingSettings: store.routingSettings,
                existingLocalModelProfiles: pairedTerminalLocalModelProfiles(
                    deviceId: client.deviceId,
                    localModels: localModels
                ),
                suggestedLANAllowedCidrs: grpc.currentLANDefaultAllowedCidrs(),
                initialCapabilityFocusKey: editingGRPCClientFocusCapabilityKey,
                onSave: { updated in
                    grpc.upsertClient(updated)
                },
                onSaveRoutingSettings: { settings in
                    store.saveRoutingSettings(settings)
                },
                onUpsertLocalModelProfile: { profile in
                    grpc.upsertPairedTerminalLocalModelProfile(profile)
                },
                onRemoveLocalModelProfile: { deviceId, modelId in
                    grpc.removePairedTerminalLocalModelProfile(deviceId: deviceId, modelId: modelId)
                },
                onRotateToken: { deviceId in
                    grpc.rotateClientToken(deviceId: deviceId)
                },
                onCopyVars: { tok in
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(grpc.connectionGuideOverride(token: tok, deviceId: client.deviceId), forType: .string)
                }
            )
        }
        .alert(
            deletingGRPCClient == nil
                ? HubUIStrings.Settings.GRPC.deleteDeviceTitle
                : HubUIStrings.Settings.GRPC.deleteDeviceTitleConfirm,
            isPresented: Binding(
                get: { deletingGRPCClient != nil },
                set: { newValue in
                    if !newValue {
                        deletingGRPCClient = nil
                    }
                }
            ),
            presenting: deletingGRPCClient
        ) { client in
            Button(HubUIStrings.Settings.GRPC.delete, role: .destructive) {
                if editingGRPCClient?.deviceId == client.deviceId {
                    editingGRPCClientFocusCapabilityKey = nil
                    editingGRPCClient = nil
                }
                grpc.removeClient(deviceId: client.deviceId)
                deletingGRPCClient = nil
            }
            Button(HubUIStrings.Settings.GRPC.cancel, role: .cancel) {
                deletingGRPCClient = nil
            }
        } message: { client in
            Text(deleteClientConfirmationMessage(client))
        }
        .confirmationDialog(
            HubUIStrings.Models.Runtime.LocalServiceRecovery.queueRustRepairDialogTitle,
            isPresented: $rustLocalModelRepairApplyDialogPresented,
            titleVisibility: .visible
        ) {
            Button(HubUIStrings.Models.Runtime.LocalServiceRecovery.queueRustRepairDialogConfirm) {
                if let plan = rustLocalModelRepairApplyPendingPlan {
                    applyRustLocalModelRepair(plan)
                }
            }
            Button(HubUIStrings.Models.Runtime.LocalServiceRecovery.queueRustRepairDialogCancel, role: .cancel) {
                rustLocalModelRepairApplyPendingPlan = nil
            }
        } message: {
            let plan = rustLocalModelRepairApplyPendingPlan
            Text(
                HubUIStrings.Models.Runtime.LocalServiceRecovery.queueRustRepairDialogMessage(
                    action: plan?.resolved.action ?? "",
                    taskKind: plan?.target.taskKind.isEmpty == false ? plan?.target.taskKind ?? "" : plan?.resolved.taskKind ?? "",
                    requiresNetwork: plan?.requiresNetwork ?? false
                )
            )
        }
    }

    private func pairedTerminalLocalModels() -> [ModelCatalogEntry] {
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

    private func pairedTerminalLocalModelProfiles(
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

    private func handleSettingsNavigationTarget(_ target: HubSettingsNavigationTarget?) {
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
        }
    }

    private func scrollToSettingsTargetIfNeeded(_ proxy: ScrollViewProxy) {
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

    private func openCLIProxyOAuthInventoryManager() {
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

    private func reloadSettingsSurfaceData() {
        remoteRouteProbe.refresh(host: grpc.xtTerminalInternetHost)
        rebuildLocalModelSnapshot()
        reloadProviderKeySnapshot()
        reloadRemoteModels()
        reloadNetworkPolicies()
        reloadCLIProxyRuntimeConfiguration()
        reloadCLIProxyOAuthConfiguration()
        reloadAXConstitutionStatus()
        refreshRustHubRuntimeSnapshot(force: true)
        refreshRustLocalModelRepairPlan(force: true)
        refreshRustLocalModelRepairJobs(force: true)
        refreshRustHubRemoteEntryCandidates(force: true)
        Task { await reloadOperatorChannelProviderReadiness() }
        Task { await reloadTerminalAccessKeys() }
        Task { await refreshCLIProxyRuntimeStatus() }
        Task { await refreshCLIProxyOAuthRemoteAuths() }
    }

    private func rebuildLocalModelSnapshot() {
        localModelSnapshot = SettingsLocalModelSnapshot.build(
            from: modelStore.snapshot.models
        )
    }

    private func refreshVisibleSettingsPageIfNeeded(now: Date = Date()) {
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

    func refreshRustHubRuntimeSnapshot(force: Bool = false) {
        let now = Date()
        if rustHubRuntimeRefreshing { return }
        if !force && now.timeIntervalSince(rustHubRuntimeLastRefreshAt) < 10.0 { return }
        rustHubRuntimeRefreshing = true
        Task {
            let snapshot = await RustHubRuntimeSupport.loadSnapshot()
            await MainActor.run {
                rustHubRuntimeSnapshot = snapshot
                rustHubRuntimeLastRefreshAt = Date()
                rustHubRuntimeRefreshing = false
            }
        }
    }

    func refreshRustLocalModelRepairPlan(force: Bool = false) {
        let now = Date()
        if rustLocalModelRepairPlanRefreshing { return }
        if !force && now.timeIntervalSince(rustLocalModelRepairPlanLastRefreshAt) < 10.0 { return }
        rustLocalModelRepairPlanRefreshing = true
        Task {
            let plan = await RustHubRuntimeSupport.loadLocalModelRepairPlan()
            await MainActor.run {
                rustLocalModelRepairPlan = plan
                rustLocalModelRepairPlanLastRefreshAt = Date()
                rustLocalModelRepairPlanRefreshing = false
            }
        }
    }

    func refreshRustLocalModelRepairJobs(force: Bool = false) {
        let now = Date()
        if rustLocalModelRepairJobsRefreshing { return }
        if !force && now.timeIntervalSince(rustLocalModelRepairJobsLastRefreshAt) < 5.0 { return }
        rustLocalModelRepairJobsRefreshing = true
        Task {
            let snapshot = await RustHubRuntimeSupport.loadLocalModelRepairJobs()
            await MainActor.run {
                rustLocalModelRepairJobsSnapshot = snapshot
                rustLocalModelRepairJobsLastRefreshAt = Date()
                rustLocalModelRepairJobsRefreshing = false
            }
        }
    }

    func presentRustLocalModelRepairApplyDialog() {
        guard !rustLocalModelRepairApplyInFlight,
              let plan = rustLocalModelRepairPlan,
              plan.isActionableRepair else {
            return
        }
        rustLocalModelRepairApplyPendingPlan = plan
        rustLocalModelRepairApplyErrorText = ""
        rustLocalModelRepairApplyDialogPresented = true
    }

    private func applyRustLocalModelRepair(_ plan: RustLocalModelRepairPlan) {
        guard !rustLocalModelRepairApplyInFlight else { return }
        rustLocalModelRepairApplyInFlight = true
        rustLocalModelRepairApplyErrorText = ""
        rustLocalModelRepairApplyResult = nil
        rustLocalModelRepairExecutorResult = nil
        rustLocalModelRepairApplyDialogPresented = false
        Task {
            let result = await RustHubRuntimeSupport.applyLocalModelRepair(plan: plan)
            await MainActor.run {
                rustLocalModelRepairApplyInFlight = false
                rustLocalModelRepairApplyPendingPlan = nil
                if let result {
                    rustLocalModelRepairApplyResult = result
                    if result.accepted {
                        refreshRustLocalModelRepairPlan(force: true)
                        refreshRustLocalModelRepairJobs(force: true)
                        refreshRustHubRuntimeSnapshot(force: true)
                        startRustLocalModelRepairExecutor()
                    }
                } else {
                    rustLocalModelRepairApplyErrorText = HubUIStrings.Models.Runtime.LocalServiceRecovery.rustRepairApplyFailed
                }
            }
        }
    }

    private func startRustLocalModelRepairExecutor() {
        guard !rustLocalModelRepairExecutorInFlight else { return }
        rustLocalModelRepairExecutorInFlight = true
        Task {
            let result = await RustHubRuntimeSupport.runLocalModelRepairExecutor()
            await MainActor.run {
                rustLocalModelRepairExecutorInFlight = false
                if let result {
                    rustLocalModelRepairExecutorResult = result
                } else {
                    rustLocalModelRepairApplyErrorText = HubUIStrings.Models.Runtime.LocalServiceRecovery.rustRepairExecutorFailed
                }
                refreshRustLocalModelRepairPlan(force: true)
                refreshRustLocalModelRepairJobs(force: true)
                refreshRustHubRuntimeSnapshot(force: true)
            }
        }
    }

    func refreshRustHubRemoteEntryCandidates(force: Bool = false) {
        let now = Date()
        if rustHubRemoteEntryRefreshing { return }
        if !force && now.timeIntervalSince(rustHubRemoteEntryLastRefreshAt) < 10.0 { return }
        rustHubRemoteEntryRefreshing = true
        Task {
            let candidates = await RustHubRuntimeSupport.loadRemoteEntryCandidates()
            await MainActor.run {
                rustHubRemoteEntryCandidates = candidates
                rustHubRemoteEntryLastRefreshAt = Date()
                rustHubRemoteEntryRefreshing = false
            }
        }
    }

    private func maybeRebuildProviderKeySectionSnapshot() {
        guard selectedSettingsPage == .models, providerQuotaOperationsExpanded else { return }
        rebuildProviderKeySectionSnapshot()
    }

    private func rebuildProviderKeySectionSnapshot() {
        providerKeySectionSnapshot = makeProviderKeySectionSnapshot()
    }

    private func makeProviderKeySectionSnapshot() -> ProviderKeySectionSnapshot {
        let keyPools = providerKeyDerivedSnapshot.keyPools
        let quotaProjection = remoteQuotaProjection
        let users = quotaProjection.users
        let focusedUser = providerKeyFocusedUser(users)
        let focusedVendorFamilyKeys = providerKeyFocusedVendorFamilyKeys(quotaProjection)
        let scopedUsers = providerKeyVendorScopedUsers(
            providerKeyScopedUsers(users),
            focusedVendorFamilyKeys: focusedVendorFamilyKeys
        )
        let scopedConsumers = providerKeyVendorScopedConsumers(
            providerKeyScopedConsumers(quotaProjection),
            focusedVendorFamilyKeys: focusedVendorFamilyKeys
        )
        let filteredFamilies = providerKeyFamilyInventorySummaries(
            quotaProjection,
            scopedUsers: scopedUsers,
            scopedConsumers: scopedConsumers,
            focusedVendorFamilyKeys: focusedVendorFamilyKeys
        )
        let vendorSummaries = providerKeyVendorInventorySummaries(
            keyPools,
            familySummaries: filteredFamilies,
            scopedUsers: scopedUsers,
            scopedConsumers: scopedConsumers,
            includeSpotlights: providerVendorLedgerExpanded
        )
        let focusedVendor = providerKeyFocusedVendor(vendorSummaries)
        let filteredVendors = providerKeyFilteredVendors(
            vendorSummaries,
            focusedVendor: focusedVendor
        )
        let filteredUsers = providerKeyFilteredUsers(
            users,
            focusedVendorFamilyKeys: focusedVendorFamilyKeys
        )
        let filteredConsumers = providerKeyFilteredConsumers(
            quotaProjection,
            focusedVendorFamilyKeys: focusedVendorFamilyKeys
        )
        let scopeOverview = providerKeyScopeOverview(
            focusedUser: focusedUser,
            focusedVendorDisplayName: focusedVendor?.displayName,
            scopedUsers: scopedUsers,
            scopedConsumers: scopedConsumers,
            families: filteredFamilies
        )
        let riskVendorCount = filteredVendors.filter(providerKeyVendorAtRisk(_:)).count
        let riskFamilyCount = filteredFamilies.filter(providerKeyFamilyAtRisk(_:)).count

        let flowChains: [ProviderKeyFlowChainSummary] = {
            guard providerFlowExpanded else { return [] }
            let flowChainVendors = focusedVendor == nil ? vendorSummaries : filteredVendors
            return providerKeyFlowChains(
                vendors: flowChainVendors,
                users: scopedUsers,
                consumers: scopedConsumers,
                focusedVendor: focusedVendor
            )
        }()

        let overallTrendCard: ProviderKeyTrendCardSummary?
        let vendorTrendCards: [ProviderKeyTrendCardSummary]
        let familyTrendCards: [ProviderKeyTrendCardSummary]
        let userTrendCards: [ProviderKeyTrendCardSummary]
        let consumerTrendCards: [ProviderKeyTrendCardSummary]
        let trendCardCount: Int

        if providerTrendExpanded {
            overallTrendCard = providerKeyOverallTrendCard(
                scopeOverview: scopeOverview,
                consumers: scopedConsumers,
                focusedVendor: focusedVendor
            )
            vendorTrendCards = providerKeyVendorTrendCards(
                vendorSummaries,
                scopedConsumers: scopedConsumers,
                focusedVendor: focusedVendor
            )
            familyTrendCards = providerKeyFamilyTrendCards(filteredFamilies)
            userTrendCards = providerKeyUserTrendCards(
                filteredUsers,
                focusedVendor: focusedVendor
            )
            consumerTrendCards = providerKeyConsumerTrendCards(
                filteredConsumers,
                focusedVendor: focusedVendor
            )
            trendCardCount = providerKeyTrendCardCount(
                overallTrendCard: overallTrendCard,
                vendorTrendCards: vendorTrendCards,
                familyTrendCards: familyTrendCards,
                userTrendCards: userTrendCards,
                consumerTrendCards: consumerTrendCards
            )
        } else {
            overallTrendCard = nil
            vendorTrendCards = []
            familyTrendCards = []
            userTrendCards = []
            consumerTrendCards = []
            trendCardCount = 0
        }

        return ProviderKeySectionSnapshot(
            keyPools: keyPools,
            overview: quotaProjection.overview,
            totalFamilyCount: quotaProjection.families.count,
            totalConsumerCount: quotaProjection.consumers.count,
            consumerLedgerTotalCount: focusedUser == nil ? quotaProjection.consumers.count : scopedConsumers.count,
            users: users,
            focusedUser: focusedUser,
            scopedUsers: scopedUsers,
            scopedConsumers: scopedConsumers,
            vendorSummaries: vendorSummaries,
            filteredVendors: filteredVendors,
            filteredFamilies: filteredFamilies,
            filteredUsers: filteredUsers,
            filteredConsumers: filteredConsumers,
            focusedVendor: focusedVendor,
            flowChains: flowChains,
            scopeOverview: scopeOverview,
            riskVendorCount: riskVendorCount,
            riskFamilyCount: riskFamilyCount,
            overallTrendCard: overallTrendCard,
            vendorTrendCards: vendorTrendCards,
            familyTrendCards: familyTrendCards,
            userTrendCards: userTrendCards,
            consumerTrendCards: consumerTrendCards,
            trendCardCount: trendCardCount,
            operationalTint: providerKeyOperationalTint(
                focusedUser: focusedUser,
                focusedVendor: focusedVendor,
                riskVendorCount: riskVendorCount,
                riskFamilyCount: riskFamilyCount
            )
        )
    }

    private var blockedCapabilityCount: Int {
        hubLaunchStatus?.degraded.blockedCapabilities.count ?? 0
    }

    private var settingsIssueCount: Int {
        var count = blockedCapabilityCount
        if !grpc.lastError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            count += 1
        }
        if !store.aiRuntimeLastError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            count += 1
        }
        if !grpcDeniedAttempts.attempts.isEmpty {
            count += 1
        }
        if !operatorChannelProviderReadinessError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            count += 1
        }
        return count
    }

    private var readyRuntimeProviderCount: Int {
        if let monitor = store.aiRuntimeStatusSnapshot?.monitorSnapshot {
            return monitor.providers.filter(\.ok).count
        }
        return store.aiRuntimeStatusSnapshot?.providers.values.filter(\.ok).count ?? 0
    }

    private var totalRuntimeProviderCount: Int {
        if let monitor = store.aiRuntimeStatusSnapshot?.monitorSnapshot {
            return monitor.providers.count
        }
        return store.aiRuntimeStatusSnapshot?.providers.count ?? 0
    }

    var loadedRuntimeInstanceCount: Int {
        store.aiRuntimeStatusSnapshot?.monitorSnapshot?.loadedInstances.count ?? 0
    }

    var localCatalogModels: [HubModel] {
        localModelSnapshot.models
    }

    var localCatalogModelCount: Int {
        localCatalogModels.count
    }

    var loadedLocalModelCount: Int {
        localModelSnapshot.loadedCount
    }

    private var localModelHealthSummary: LocalModelHealthSectionSummaryPresentation? {
        LocalModelHealthSectionSummarySupport.presentation(
            models: localCatalogModels,
            healthSnapshot: store.localModelHealthSnapshot,
            scanningModelIDs: store.localModelHealthScanningModelIDs
        )
    }

    var localAvailableModelCount: Int {
        localModelHealthSummary?.availableCount ?? 0
    }

    private var localReviewModelCount: Int {
        localModelHealthSummary?.reviewCount ?? 0
    }

    private var localDiscouragedModelCount: Int {
        localModelHealthSummary?.discouragedCount ?? 0
    }

    private var localUnscannedModelCount: Int {
        localModelHealthSummary?.unscannedCount ?? 0
    }

    private var localScanningModelCount: Int {
        localModelHealthSummary?.scanningCount ?? 0
    }

    var localPendingModelCount: Int {
        localReviewModelCount + localDiscouragedModelCount + localUnscannedModelCount
    }

    private var quotaPoolCount: Int {
        providerKeyDerivedSnapshot.quotaPools.count
    }

    private var operatorReadyCount: Int {
        operatorChannelProviderReadiness.filter(\.ready).count
    }

    var runtimeHeartbeatText: String {
        guard let status = store.aiRuntimeStatusSnapshot else {
            return "等待心跳"
        }
        return status.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ? "在线" : "心跳过期"
    }

    private var headerLaunchTint: Color {
        switch hubLaunchStatus?.state {
        case .serving:
            return .green
        case .degradedServing:
            return .orange
        case .failed:
            return .red
        default:
            return .blue
        }
    }

    private var cliproxyOAuthInventoryAuths: [CLIProxyOAuthSourceSupport.RemoteAuthFile] {
        cliproxyOAuthRemoteAuths.filter { !$0.runtimeOnly }
    }

    private var cliproxyOAuthInventoryCount: Int {
        cliproxyOAuthInventoryAuths.count
    }

    private var cliproxyOAuthRuntimeOnlyCount: Int {
        cliproxyOAuthRemoteAuths.filter(\.runtimeOnly).count
    }

    private var cliproxyOAuthReadyCount: Int {
        cliproxyOAuthInventoryAuths.filter {
            cliproxyOAuthInventoryState($0) == .ready
        }.count
    }

    private var cliproxyOAuthCoolingCount: Int {
        cliproxyOAuthInventoryAuths.filter {
            cliproxyOAuthInventoryState($0) == .cooling
        }.count
    }

    private var cliproxyOAuthBlockedCount: Int {
        cliproxyOAuthInventoryAuths.filter {
            cliproxyOAuthInventoryState($0) == .blocked
        }.count
    }

    private var cliproxyOAuthDisabledCount: Int {
        cliproxyOAuthInventoryAuths.filter {
            cliproxyOAuthInventoryState($0) == .disabled
        }.count
    }

    private var cliproxyOAuthRefreshingCount: Int {
        cliproxyOAuthInventoryAuths.filter {
            cliproxyOAuthInventoryState($0) == .refreshing
        }.count
    }

    private var cliproxyOAuthWaitingCount: Int {
        cliproxyOAuthInventoryAuths.filter {
            cliproxyOAuthInventoryState($0) == .waiting
        }.count
    }

    private var cliproxyOAuthQuotaExceededCount: Int {
        cliproxyOAuthInventoryAuths.filter(\.quota.exceeded).count
    }

    private var cliproxyOAuthProviderCount: Int {
        cliproxyOAuthProviderSummaries.count
    }

    private var cliproxyOAuthNextRefreshAtMs: Int64 {
        cliproxyOAuthInventoryAuths
            .map(\.nextRefreshAtMs)
            .filter { $0 > 0 }
            .min() ?? 0
    }

    private var cliproxyOAuthNextRecoverAtMs: Int64 {
        cliproxyOAuthInventoryAuths
            .compactMap { auth in
                minimumPositiveTimestamp(
                    auth.nextRetryAtMs,
                    auth.quota.nextRecoverAtMs
                )
            }
            .min() ?? 0
    }

    private var cliproxyOAuthProviderSummaries: [CLIProxyOAuthProviderInventorySummary] {
        Dictionary(grouping: cliproxyOAuthInventoryAuths) { auth in
            cliproxyOAuthCanonicalProviderKey(auth.provider)
        }
        .map { providerKey, auths in
            CLIProxyOAuthProviderInventorySummary(
                providerKey: providerKey,
                displayName: cliproxyOAuthProviderDisplayName(providerKey),
                totalCount: auths.count,
                readyCount: auths.filter { cliproxyOAuthInventoryState($0) == .ready }.count,
                coolingCount: auths.filter { cliproxyOAuthInventoryState($0) == .cooling }.count,
                blockedCount: auths.filter { cliproxyOAuthInventoryState($0) == .blocked }.count,
                disabledCount: auths.filter { cliproxyOAuthInventoryState($0) == .disabled }.count,
                refreshingCount: auths.filter { cliproxyOAuthInventoryState($0) == .refreshing }.count,
                waitingCount: auths.filter { cliproxyOAuthInventoryState($0) == .waiting }.count
            )
        }
        .sorted { lhs, rhs in
            let leftOrder = cliproxyOAuthProviderSortIndex(lhs.providerKey)
            let rightOrder = cliproxyOAuthProviderSortIndex(rhs.providerKey)
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            if lhs.readyCount != rhs.readyCount {
                return lhs.readyCount > rhs.readyCount
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private var cliproxyOAuthProviderCoverageText: String {
        let names = cliproxyOAuthProviderSummaries.map(\.displayName)
        guard !names.isEmpty else {
            return "还没有 OAuth 厂家库存"
        }
        if names.count <= 3 {
            return names.joined(separator: " / ")
        }
        return names.prefix(3).joined(separator: " / ") + " +\(names.count - 3)"
    }

    private var cliproxyOAuthOverviewSummaryText: String {
        var parts: [String] = []

        if cliproxyOAuthRemoteAuths.isEmpty {
            parts.append("当前还没有从 CLIProxy 拉到已认证账号")
        } else {
            parts.append("已发现 \(cliproxyOAuthRemoteAuths.count) 个认证文件")
            if cliproxyOAuthInventoryCount > 0 {
                parts.append("\(cliproxyOAuthInventoryCount) 个可并入 Hub")
            }
            if cliproxyOAuthRuntimeOnlyCount > 0 {
                parts.append("\(cliproxyOAuthRuntimeOnlyCount) 个 runtime-only")
            }
            if cliproxyOAuthProviderCount > 0 {
                parts.append("覆盖 \(cliproxyOAuthProviderCount) 家厂商")
            }
        }

        if cliproxyOAuthSettings.lastSyncAtMs > 0 {
            parts.append("上次同步 \(formattedProviderKeyImportSourceTime(cliproxyOAuthSettings.lastSyncAtMs))")
        } else if cliproxyOAuthLastRemoteFetchAtMs > 0 {
            parts.append("列表刷新 \(formattedProviderKeyImportSourceTime(cliproxyOAuthLastRemoteFetchAtMs))")
        } else if cliproxyOAuthManagementKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("填写 management key 后可自动并入 Hub 额度池")
        } else {
            parts.append("已连接 management key，等待第一次同步")
        }

        return HubUIStrings.Settings.RemoteModels.sectionSummary(parts)
    }

    private var cliproxyOAuthOverviewNoticeText: String {
        let trimmedError = cliproxyOAuthErrorText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedError.isEmpty {
            return trimmedError
        }

        if let provider = cliproxyOAuthActiveProvider,
           !cliproxyOAuthActiveState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(provider.title) OAuth 正在等待浏览器完成登录，完成后 Hub 会自动导入凭证并并入额度池。"
        }

        if cliproxyOAuthManagementKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "新账号可直接走 Hub 原生 OAuth；只有导入旧 CLIProxy 账号时才需要 management key。"
        }

        if cliproxyOAuthRemoteAuths.isEmpty {
            return "CLIProxy 已接通，但还没有旧认证账号。新登录会直接进入 Hub Provider Key 额度池。"
        }

        if cliproxyOAuthInventoryCount == 0 && cliproxyOAuthRuntimeOnlyCount > 0 {
            return "当前拉到的账号全部是 runtime-only，暂时不会并入 Hub 额度池。"
        }

        if cliproxyOAuthBlockedCount > 0 {
            if cliproxyOAuthNextRecoverAtMs > 0 {
                return "当前有 \(cliproxyOAuthBlockedCount) 个账号阻断，最早 \(formattedProviderKeyImportSourceTime(cliproxyOAuthNextRecoverAtMs)) 可恢复或重试。"
            }
            return "当前有 \(cliproxyOAuthBlockedCount) 个账号阻断，建议去模型页看具体 provider / key 状态。"
        }

        if cliproxyOAuthCoolingCount > 0 {
            let limitedText = cliproxyOAuthQuotaExceededCount > 0
                ? "\(cliproxyOAuthQuotaExceededCount) 个已触发免费额度上限"
                : "\(cliproxyOAuthCoolingCount) 个正在冷却"
            if cliproxyOAuthNextRecoverAtMs > 0 {
                return "当前有 \(limitedText)，最早 \(formattedProviderKeyImportSourceTime(cliproxyOAuthNextRecoverAtMs)) 恢复。"
            }
            return "当前有 \(limitedText)，等待 CLIProxy 恢复可用额度。"
        }

        if cliproxyOAuthRefreshingCount > 0 || cliproxyOAuthWaitingCount > 0 {
            var parts: [String] = []
            if cliproxyOAuthRefreshingCount > 0 {
                parts.append("刷新中 \(cliproxyOAuthRefreshingCount)")
            }
            if cliproxyOAuthWaitingCount > 0 {
                parts.append("等待中 \(cliproxyOAuthWaitingCount)")
            }
            return "库存正在滚动维护：\(HubUIStrings.Settings.RemoteModels.sectionSummary(parts))。"
        }

        if cliproxyOAuthNextRefreshAtMs > 0 {
            return "库存当前可用，下次刷新 \(formattedProviderKeyImportSourceTime(cliproxyOAuthNextRefreshAtMs))。"
        }

        return "库存当前可用，可以继续给 XT 或普通 terminal 分配 Hub access key + URL。"
    }

    var cliproxyOAuthOverviewNoticeTint: Color {
        let trimmedRuntimeError = cliproxyRuntimeErrorText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedRuntimeError.isEmpty {
            return .red
        }
        let trimmedError = cliproxyOAuthErrorText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedError.isEmpty {
            return .red
        }
        if cliproxyRuntimeLaunching || cliproxyRuntimeRefreshing {
            return .blue
        }
        if !cliproxyOAuthActiveState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .blue
        }
        if cliproxyOAuthManagementKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || cliproxyOAuthRemoteAuths.isEmpty {
            return .indigo
        }
        if cliproxyOAuthBlockedCount > 0 {
            return .red
        }
        if cliproxyOAuthCoolingCount > 0 {
            return .orange
        }
        if cliproxyOAuthRefreshingCount > 0 || cliproxyOAuthWaitingCount > 0 {
            return .blue
        }
        return .green
    }

    private var cliproxyOAuthOverviewNoticeSystemName: String {
        let trimmedError = cliproxyOAuthErrorText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedError.isEmpty {
            return "exclamationmark.triangle"
        }
        if !cliproxyOAuthActiveState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "person.badge.key"
        }
        if cliproxyOAuthManagementKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || cliproxyOAuthRemoteAuths.isEmpty {
            return "info.circle"
        }
        if cliproxyOAuthBlockedCount > 0 {
            return "xmark.octagon"
        }
        if cliproxyOAuthCoolingCount > 0 {
            return "timer"
        }
        if cliproxyOAuthRefreshingCount > 0 || cliproxyOAuthWaitingCount > 0 {
            return "arrow.triangle.2.circlepath"
        }
        return "checkmark.seal"
    }

    private var cliproxyOAuthOverviewMetrics: [HubSettingsMetric] {
        let refreshValue: String
        if cliproxyOAuthNextRefreshAtMs > 0 {
            refreshValue = formattedProviderKeyImportSourceTime(cliproxyOAuthNextRefreshAtMs)
        } else if cliproxyOAuthRefreshing || cliproxyOAuthSyncing {
            refreshValue = "进行中"
        } else if cliproxyOAuthSettings.lastSyncAtMs > 0 {
            refreshValue = "已同步"
        } else {
            refreshValue = "待同步"
        }

        let refreshDetail: String
        if cliproxyOAuthLastRemoteFetchAtMs > 0 {
            refreshDetail = "列表刷新 \(formattedProviderKeyImportSourceTime(cliproxyOAuthLastRemoteFetchAtMs))"
        } else if cliproxyOAuthSettings.lastSyncAtMs > 0 {
            refreshDetail = "上次同步 \(formattedProviderKeyImportSourceTime(cliproxyOAuthSettings.lastSyncAtMs))"
        } else {
            refreshDetail = "还没有 CLIProxy 远端拉取记录"
        }

        return [
            HubSettingsMetric(
                title: "可用账号",
                value: cliproxyOAuthInventoryCount == 0 ? "0" : "\(cliproxyOAuthReadyCount)/\(cliproxyOAuthInventoryCount)",
                detail: cliproxyOAuthRuntimeOnlyCount > 0
                    ? "另有 \(cliproxyOAuthRuntimeOnlyCount) 个 runtime-only 未并入 Hub"
                    : "已就绪 / 可导入的 CLIProxy 账号",
                tint: cliproxyOAuthReadyCount > 0 ? .green : .secondary
            ),
            HubSettingsMetric(
                title: "冷却 / 恢复",
                value: "\(cliproxyOAuthCoolingCount)",
                detail: cliproxyOAuthNextRecoverAtMs > 0
                    ? "最早恢复 \(formattedProviderKeyImportSourceTime(cliproxyOAuthNextRecoverAtMs))"
                    : "当前没有额度冷却",
                tint: cliproxyOAuthCoolingCount > 0 ? .orange : .green
            ),
            HubSettingsMetric(
                title: "阻断 / 停用",
                value: "\(cliproxyOAuthBlockedCount + cliproxyOAuthDisabledCount)",
                detail: HubUIStrings.Settings.RemoteModels.sectionSummary([
                    "阻断 \(cliproxyOAuthBlockedCount)",
                    "停用 \(cliproxyOAuthDisabledCount)"
                ]),
                tint: cliproxyOAuthBlockedCount > 0 ? .red : (cliproxyOAuthDisabledCount > 0 ? .gray : .green)
            ),
            HubSettingsMetric(
                title: "下次刷新",
                value: refreshValue,
                detail: refreshDetail,
                tint: cliproxyOAuthRefreshing || cliproxyOAuthSyncing ? .blue : .indigo
            ),
            HubSettingsMetric(
                title: "覆盖厂家",
                value: cliproxyOAuthProviderCount == 0 ? "未接入" : "\(cliproxyOAuthProviderCount)",
                detail: cliproxyOAuthProviderCoverageText,
                tint: cliproxyOAuthProviderCount > 0 ? .teal : .secondary
            )
        ]
    }

    private var cliproxyOAuthHubRoutingStatusText: String {
        let snapshot = providerKeySnapshot
        let derived = providerKeyDerivedSnapshot
        guard snapshot.totalAccounts > 0 else {
            return "Hub 账号池为空：同步 CLIProxy OAuth 或发起 Hub OAuth 后会在这里显示可路由库存。"
        }

        let blockedLikeAccounts = derived.blockedAccounts
            + derived.disabledPoolAccounts
            + derived.staleAccounts
        let strategies = Array(Set(derived.keyPools.map(\.routingStrategy).filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })).sorted()
        let strategyText = strategies.isEmpty
            ? snapshot.globalRoutingStrategy
            : strategies.joined(separator: " / ")

        return HubUIStrings.Settings.RemoteModels.sectionSummary([
            "Hub 账号池 \(derived.readyAccounts)/\(derived.totalAccounts) 可路由",
            "\(derived.keyPools.count) 个物理池",
            "\(derived.quotaPools.count) 个额度池",
            derived.cooldownAccounts > 0 ? "冷却 \(derived.cooldownAccounts)" : "",
            blockedLikeAccounts > 0 ? "阻断/停用/过期 \(blockedLikeAccounts)" : "",
            "策略 \(strategyText)"
        ])
    }

    private var cliproxyOAuthHubRoutingStatusTint: Color {
        if providerKeyDerivedSnapshot.readyAccounts > 0 {
            return providerKeyDerivedSnapshot.cooldownAccounts > 0 ? .orange : .green
        }
        if providerKeyDerivedSnapshot.totalAccounts > 0 {
            return .red
        }
        return .indigo
    }

    private var cliproxyOAuthHubRoutingStatusSystemName: String {
        if providerKeyDerivedSnapshot.readyAccounts > 0 {
            return "point.3.connected.trianglepath.dotted"
        }
        if providerKeyDerivedSnapshot.totalAccounts > 0 {
            return "exclamationmark.triangle"
        }
        return "tray.and.arrow.down"
    }

    private func cliproxyOAuthSyncActionText(
        summary: CLIProxyOAuthSourceSupport.SyncSummary,
        snapshot: ProviderKeyStoreSnapshot,
        partial: Bool
    ) -> String {
        let blockedLikeAccounts = snapshot.blockedAccounts
            + snapshot.disabledPoolAccounts
            + snapshot.staleAccounts
        var parts = ["写入 \(summary.importedCount) 个账号"]
        if summary.prunedCount > 0 {
            parts.append("清理 \(summary.prunedCount) 个旧账号")
        }
        if snapshot.totalAccounts > 0 {
            parts.append("Hub 账号池 \(snapshot.readyAccounts)/\(snapshot.totalAccounts) 可路由")
        }
        if snapshot.keyPools.count > 0 {
            parts.append("\(snapshot.keyPools.count) 个物理池")
        }
        if snapshot.quotaPools.count > 0 {
            parts.append("\(snapshot.quotaPools.count) 个额度池")
        }
        if snapshot.cooldownAccounts > 0 {
            parts.append("冷却 \(snapshot.cooldownAccounts)")
        }
        if blockedLikeAccounts > 0 {
            parts.append("阻断/停用/过期 \(blockedLikeAccounts)")
        }
        if partial {
            parts.append("\(summary.errorMessages.count) 个同步失败")
            return "已部分同步：\(HubUIStrings.Settings.RemoteModels.sectionSummary(parts))，旧账号不会被误删。"
        }
        return "同步完成：\(HubUIStrings.Settings.RemoteModels.sectionSummary(parts))。"
    }

    private var cliproxyOAuthHeaderMetric: HubSettingsMetric {
        let managementKey = cliproxyOAuthManagementKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if let provider = cliproxyOAuthActiveProvider,
           !cliproxyOAuthActiveState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return HubSettingsMetric(
                title: "CLIProxy OAuth",
                value: "\(provider.title) 登录中",
                detail: "浏览器完成后会自动同步到 Hub",
                tint: .blue
            )
        }

        if cliproxyOAuthInventoryCount > 0 {
            return HubSettingsMetric(
                title: "CLIProxy OAuth",
                value: "\(cliproxyOAuthReadyCount)/\(cliproxyOAuthInventoryCount)",
                detail: HubUIStrings.Settings.RemoteModels.sectionSummary([
                    "\(cliproxyOAuthProviderCount) 家厂商",
                    cliproxyOAuthCoolingCount > 0 ? "冷却 \(cliproxyOAuthCoolingCount)" : "",
                    cliproxyOAuthBlockedCount > 0 ? "阻断 \(cliproxyOAuthBlockedCount)" : "",
                    cliproxyOAuthRuntimeOnlyCount > 0 ? "runtime-only \(cliproxyOAuthRuntimeOnlyCount)" : ""
                ]),
                tint: cliproxyOAuthBlockedCount > 0 ? .red : (cliproxyOAuthCoolingCount > 0 ? .orange : .green)
            )
        }

        if managementKey.isEmpty {
            return HubSettingsMetric(
                title: "CLIProxy OAuth",
                value: "未接入",
                detail: "接入后可把免费额度账号直接并入 Hub",
                tint: .gray
            )
        }

        if cliproxyOAuthRemoteAuths.isEmpty {
            return HubSettingsMetric(
                title: "CLIProxy OAuth",
                value: "待登录",
                detail: "CLIProxy 已连通，等待已认证账号",
                tint: .indigo
            )
        }

        return HubSettingsMetric(
            title: "CLIProxy OAuth",
            value: "0",
            detail: cliproxyOAuthRuntimeOnlyCount > 0
                ? "当前全是 runtime-only 账号"
                : "等待 CLIProxy 返回可导入账号",
            tint: .orange
        )
    }

    private var headerMetrics: [HubSettingsMetric] {
        [
            HubSettingsMetric(
                title: "Hub 状态",
                value: currentLaunchStateLabel,
                detail: settingsIssueCount > 0 ? "\(settingsIssueCount) 个待处理问题" : "当前服务链路稳定",
                tint: headerLaunchTint
            ),
            HubSettingsMetric(
                title: "XT 设备",
                value: "\(grpc.allowedClients.count)",
                detail: grpcDeniedAttempts.attempts.isEmpty ? "没有新的拒绝记录" : "最近有 \(grpcDeniedAttempts.attempts.count) 条拒绝记录",
                tint: .teal
            ),
            HubSettingsMetric(
                title: "远端模型",
                value: "\(activeRemoteModelCount)",
                detail: "\(providerKeyDerivedSnapshot.totalAccounts) 个 key · \(quotaPoolCount) 个额度池",
                tint: .indigo
            ),
            cliproxyOAuthHeaderMetric,
            HubSettingsMetric(
                title: "本地运行时",
                value: runtimeHeartbeatText,
                detail: totalRuntimeProviderCount > 0
                    ? "\(readyRuntimeProviderCount)/\(totalRuntimeProviderCount) 个 provider 就绪"
                    : "等待 provider 心跳",
                tint: .orange
            )
        ]
    }

    var routingSummaryText: String {
        let defaults = store.routingSettings.hubDefaultModelIdByTaskKind
            .values
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
        let overrides = store.routingSettings.devicePreferredModelIdByTaskKind
            .values
            .reduce(0) { partialResult, deviceMap in
                partialResult + deviceMap.values.filter {
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }.count
            }

        if defaults == 0 && overrides == 0 {
            return "当前没有显式任务路由映射，Hub 会按默认模型解析。"
        }
        return "Hub 默认映射 \(defaults) 条，终端覆写 \(overrides) 条。这里只在你想强制指定任务模型时才需要展开。"
    }

    private var modelHealthAutoScanSummaryText: String {
        [
            autoScanScheduleSummaryText(
                label: "本地",
                schedule: store.localModelHealthAutoScanSchedule,
                nextRunText: nextLocalModelHealthAutoScanText()
            ),
            autoScanScheduleSummaryText(
                label: "远端",
                schedule: store.remoteKeyHealthAutoScanSchedule,
                nextRunText: nextRemoteKeyHealthAutoScanText()
            )
        ]
        .joined(separator: " · ")
    }

    private var integrationsAuxSummaryText: String {
        let operatorSummary = operatorChannelProviderReadiness.isEmpty
            ? "Operator 待检测"
            : "Operator \(operatorReadyCount)/\(operatorChannelProviderReadiness.count) 就绪"
        return [
            operatorSummary,
            "\(skillsIndex.skills.count) 个 skills",
            "日历 \(store.calendarStatus)",
            "浮窗 \(store.floatingMode.title)"
        ]
        .joined(separator: " · ") + "。这些都属于低频维护项，默认折叠更利于扫读。"
    }

    private var diagnosticsLaunchSummaryText: String {
        var parts: [String] = [currentLaunchStateLabel]
        if blockedCapabilityCount > 0 {
            parts.append("\(blockedCapabilityCount) 项 capability 受阻")
        }
        let rootCauseText = settingsSummarySnippet(renderRootCauseText(hubLaunchStatus?.rootCause), limit: 110)
        if !rootCauseText.isEmpty {
            parts.append(rootCauseText)
        } else {
            parts.append("这里可查看 root cause、provider 摘要和 launch history。")
        }
        return parts.joined(separator: " · ")
    }

    private var diagnosticsNetworkSummaryText: String {
        var parts: [String] = []
        if store.pendingNetworkRequests.isEmpty {
            parts.append("当前没有待授权网络请求")
        } else {
            parts.append("\(store.pendingNetworkRequests.count) 个网络请求待处理")
        }
        parts.append(networkPolicies.isEmpty ? "没有项目级网络策略" : "\(networkPolicies.count) 条项目级网络策略")
        parts.append(store.bridge.bridgeStatusText)
        return parts.joined(separator: " · ")
    }

    private var diagnosticsAdvancedSummaryText: String {
        let pythonText = settingsCompactPathDisplay(store.aiRuntimePython)
        let constitutionVersion = axConstitutionVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            store.aiRuntimeAutoStart ? "运行时自动启动" : "运行时手动启动",
            pythonText.isEmpty ? "Python 走自动发现" : "Python \(pythonText)",
            constitutionVersion.isEmpty ? "宪章版本未读取" : "宪章 \(constitutionVersion)"
        ]
        .joined(separator: " · ")
    }

    private func autoScanScheduleSummaryText(
        label: String,
        schedule: ModelHealthAutoScanSchedule,
        nextRunText: String?
    ) -> String {
        let modeText: String
        switch schedule.mode {
        case .disabled:
            modeText = "关闭"
        case .interval:
            modeText = "每 \(schedule.intervalHours) 小时"
        case .dailyTime:
            modeText = "每日 \(formattedClockTime(minuteOfDay: schedule.dailyMinuteOfDay))"
        }

        if let nextRunText, !nextRunText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(label) \(modeText) · 下次 \(nextRunText)"
        }
        return "\(label) \(modeText)"
    }

    private func formattedClockTime(minuteOfDay: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: clockDate(for: minuteOfDay))
    }

    private func settingsSummarySnippet(_ raw: String, limit: Int) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard trimmed.count > limit else { return trimmed }
        let prefix = String(trimmed.prefix(max(0, limit - 1))).trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix + "…"
    }

    private func settingsCompactPathDisplay(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let url = URL(fileURLWithPath: trimmed)
        let last = url.lastPathComponent
        let parent = url.deletingLastPathComponent().lastPathComponent
        if parent.isEmpty {
            return last
        }
        return "\(parent)/\(last)"
    }

    func expansionBinding(
        _ id: String,
        in set: Binding<Set<String>>
    ) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(id) },
            set: { expanded in
                var values = set.wrappedValue
                if expanded {
                    values.insert(id)
                } else {
                    values.remove(id)
                }
                set.wrappedValue = values
            }
        )
    }

    func grpcClientDetailSummary(_ status: GRPCDeviceStatusEntry?) -> String {
        guard let status else {
            return "未收到设备状态快照"
        }

        var parts: [String] = [grpcClientPresencePillTitle(status)]
        if status.dailyTokenCap > 0 {
            parts.append("\(Int(max(0, status.dailyTokenUsed)))/\(Int(max(0, status.dailyTokenCap)))")
        } else if status.dailyTokenUsed > 0 {
            parts.append("今日已用 \(Int(max(0, status.dailyTokenUsed)))")
        }
        if status.requestsToday > 0 {
            parts.append("请求 \(status.requestsToday)")
        }
        if status.blockedToday > 0 {
            parts.append("阻断 \(status.blockedToday)")
        }
        return parts.joined(separator: " · ")
    }

    func terminalAccessDetailSummary(
        _ accessKey: HubTerminalAccessKey,
        remaining: Int64,
        hasSecret: Bool
    ) -> String {
        var parts: [String] = []
        if accessKey.lastUsedAtMs > 0 {
            parts.append("最近使用 \(formatEpochMs(accessKey.lastUsedAtMs))")
        }
        parts.append("轮换 \(accessKey.rotationCount)")
        parts.append("剩余 \(terminalAccessIntText(remaining))")
        parts.append(hasSecret ? "含最新 Secret" : "仅模板")
        return parts.joined(separator: " · ")
    }

    func providerKeyPoolMemberDisclosureSummary(_ pool: ProviderKeyPoolSnapshot) -> String {
        let totalMembers = pool.members.count
        let riskCount = pool.members.filter { member in
            let state = member.state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return state == "blocked" || state == "cooldown" || state == "stale"
        }.count

        var parts: [String] = ["\(totalMembers) 个成员"]
        if riskCount > 0 {
            parts.append("\(riskCount) 个需关注")
        } else {
            parts.append("当前成员整体稳定")
        }
        return parts.joined(separator: " · ")
    }

    func remoteModelGroupDisclosureSummary(_ group: RemoteModelKeyGroup) -> String {
        var parts: [String] = ["\(group.models.count) 个模型"]
        if group.loadedCount > 0 {
            parts.append("\(group.loadedCount) 已加载")
        }
        if group.availableCount > 0 {
            parts.append("\(group.availableCount) 可执行")
        }
        if group.needsSetupCount > 0 {
            parts.append("\(group.needsSetupCount) 待补齐")
        }
        return parts.joined(separator: " · ")
    }

    func providerKeyImportSourcesSummaryText(
        _ sources: [ProviderKeyImportSourceStatus]
    ) -> String {
        let readyCount = sources.filter { $0.state == "ready" }.count
        let issueCount = sources.filter { $0.state != "ready" || $0.lastErrorCount > 0 }.count
        let importedCount = sources.reduce(0) { $0 + max(0, $1.lastImportedCount) }
        var parts: [String] = ["\(sources.count) 个来源"]
        if readyCount > 0 {
            parts.append("\(readyCount) 已同步")
        }
        if importedCount > 0 {
            parts.append("导入 \(importedCount)")
        }
        if issueCount > 0 {
            parts.append("\(issueCount) 需处理")
        }
        return parts.joined(separator: " · ")
    }

    func providerKeyVendorLedgerSummaryText(
        _ vendors: [ProviderKeyVendorInventorySummary],
        focusedUser: RemoteQuotaCenterUserProjection?,
        focusedVendor: ProviderKeyVendorInventorySummary?
    ) -> String {
        let readyAccounts = vendors.reduce(0) { $0 + max(0, $1.readyAccounts) }
        let totalAccounts = vendors.reduce(0) { $0 + max(0, $1.totalAccounts) }
        let riskCount = vendors.filter(providerKeyVendorAtRisk(_:)).count
        var parts: [String] = ["\(vendors.count) 家厂家"]
        if totalAccounts > 0 {
            parts.append("\(readyAccounts)/\(totalAccounts) Ready")
        }
        if riskCount > 0 {
            parts.append("\(riskCount) 家需关注")
        }
        if let focusedVendor {
            parts.append("已锁定 \(focusedVendor.displayName)")
        } else if let focusedUser {
            parts.append("按 \(focusedUser.displayName) 视角重算")
        }
        return parts.joined(separator: " · ")
    }

    func providerKeyFamilyLedgerSummaryText(
        _ families: [ProviderKeyFamilyInventorySummary],
        focusedUser: RemoteQuotaCenterUserProjection?
    ) -> String {
        let oversubscribedCount = families.filter(\.isOversubscribed).count
        let readyCount = families.filter { family in
            family.quotaPool.state == "ready" || family.quotaPool.state == "mixed"
        }.count
        var parts: [String] = ["\(families.count) 个家族"]
        if readyCount > 0 {
            parts.append("\(readyCount) 个可供路由")
        }
        if oversubscribedCount > 0 {
            parts.append("\(oversubscribedCount) 个超配")
        }
        if let focusedUser {
            parts.append("按 \(focusedUser.displayName) 视角重算")
        }
        return parts.joined(separator: " · ")
    }

    func providerKeyPhysicalPoolsSummaryText(
        _ keyPools: [ProviderKeyPoolSnapshot]
    ) -> String {
        let readyAccounts = keyPools.reduce(0) { $0 + max(0, $1.readyAccounts) }
        let blockedAccounts = keyPools.reduce(0) { $0 + max(0, $1.blockedAccounts) }
        let cooldownAccounts = keyPools.reduce(0) { $0 + max(0, $1.cooldownAccounts) }
        var parts: [String] = ["\(keyPools.count) 个物理池"]
        if readyAccounts > 0 {
            parts.append("\(readyAccounts) 个就绪")
        }
        if blockedAccounts > 0 {
            parts.append("\(blockedAccounts) 个阻塞")
        }
        if cooldownAccounts > 0 {
            parts.append("\(cooldownAccounts) 个冷却")
        }
        return parts.joined(separator: " · ")
    }

    var cliproxyOAuthDisclosureSummaryText: String {
        let runtimeSegment = cliproxyRuntimeDisclosureSummarySegment.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [
            runtimeSegment,
            cliproxyOAuthOverviewSummaryText,
            cliproxyOAuthOverviewNoticeText
        ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return settingsSummarySnippet(
            HubUIStrings.Settings.RemoteModels.sectionSummary(parts),
            limit: 132
        )
    }

    func providerKeyUserLedgerDisclosureSummary(
        _ users: [RemoteQuotaCenterUserProjection],
        totalUsers: Int,
        focusedUser: RemoteQuotaCenterUserProjection?
    ) -> String {
        let riskCount = users.filter(providerKeyUserAtRisk(_:)).count
        let connectedCount = users.filter { $0.connectedConsumerCount > 0 }.count
        var parts: [String] = ["\(users.count)/\(max(totalUsers, users.count)) 个用户"]
        if riskCount > 0 {
            parts.append("\(riskCount) 个风险")
        }
        if connectedCount > 0 {
            parts.append("\(connectedCount) 个在线")
        }
        if let focusedUser {
            parts.append("已锁定 \(focusedUser.displayName)")
        }
        return parts.joined(separator: " · ")
    }

    func providerKeyFlowSummaryText(
        flowChains: [ProviderKeyFlowChainSummary],
        focusedUser: RemoteQuotaCenterUserProjection?,
        focusedVendor: ProviderKeyVendorInventorySummary?
    ) -> String {
        guard !flowChains.isEmpty else {
            if let focusedVendor, let focusedUser {
                return "当前还没有 \(focusedVendor.displayName) -> \(focusedUser.displayName) 的清晰配额链路。"
            }
            if let focusedVendor {
                return "当前还没有 \(focusedVendor.displayName) 的清晰配额链路。"
            }
            if let focusedUser {
                return "当前还没有 \(focusedUser.displayName) 的清晰配额链路。"
            }
            return "当前还没有足够清晰的厂家 -> 用户 -> consumer 配额链路。"
        }

        let riskCount = flowChains.filter { chain in
            providerKeyVendorAtRisk(chain.vendor)
                || providerKeyUserAtRisk(chain.user)
                || providerKeyConsumerAtRisk(chain.consumer)
        }.count

        var parts: [String] = ["\(flowChains.count) 条链路"]
        if riskCount > 0 {
            parts.append("\(riskCount) 条需关注")
        }
        if let focusedVendor {
            parts.append("锁定 \(focusedVendor.displayName)")
        }
        if let focusedUser {
            parts.append("锁定 \(focusedUser.displayName)")
        }
        return parts.joined(separator: " · ")
    }

    private func providerKeyTrendCardCount(
        overallTrendCard: ProviderKeyTrendCardSummary?,
        vendorTrendCards: [ProviderKeyTrendCardSummary],
        familyTrendCards: [ProviderKeyTrendCardSummary],
        userTrendCards: [ProviderKeyTrendCardSummary],
        consumerTrendCards: [ProviderKeyTrendCardSummary]
    ) -> Int {
        (overallTrendCard == nil ? 0 : 1)
            + vendorTrendCards.count
            + familyTrendCards.count
            + userTrendCards.count
            + consumerTrendCards.count
    }

    func providerKeyTrendSummaryText(
        focusedUser: RemoteQuotaCenterUserProjection?,
        focusedVendor: ProviderKeyVendorInventorySummary?,
        overallTrendCard: ProviderKeyTrendCardSummary?,
        vendorTrendCards: [ProviderKeyTrendCardSummary],
        familyTrendCards: [ProviderKeyTrendCardSummary],
        userTrendCards: [ProviderKeyTrendCardSummary],
        consumerTrendCards: [ProviderKeyTrendCardSummary]
    ) -> String {
        let totalCardCount = providerKeyTrendCardCount(
            overallTrendCard: overallTrendCard,
            vendorTrendCards: vendorTrendCards,
            familyTrendCards: familyTrendCards,
            userTrendCards: userTrendCards,
            consumerTrendCards: consumerTrendCards
        )

        guard totalCardCount > 0 else {
            if let focusedVendor, let focusedUser {
                return "当前还没有 \(focusedUser.displayName) 在 \(focusedVendor.displayName) 视角下的 5m 趋势数据。"
            }
            if let focusedVendor {
                return "当前还没有 \(focusedVendor.displayName) 的 5m 趋势数据。"
            }
            if let focusedUser {
                return "当前还没有 \(focusedUser.displayName) 的 5m 趋势数据。"
            }
            return "当前还没有足够的 5m token series 数据。"
        }

        var parts: [String] = ["\(totalCardCount) 张趋势图"]
        if overallTrendCard != nil {
            parts.append("含总曲线")
        }
        if let focusedVendor {
            parts.append("围绕 \(focusedVendor.displayName)")
        }
        if let focusedUser {
            parts.append("围绕 \(focusedUser.displayName)")
        }
        return parts.joined(separator: " · ")
    }

    func providerKeyOperationalBadgeText(
        focusedUser: RemoteQuotaCenterUserProjection?,
        focusedVendor: ProviderKeyVendorInventorySummary?
    ) -> String {
        if focusedUser != nil && focusedVendor != nil {
            return "叠加视角"
        }
        if focusedVendor != nil {
            return "厂家视角"
        }
        if focusedUser != nil {
            return "用户视角"
        }
        return "全局视角"
    }

    func providerKeyOperationalSummaryText(
        scopeOverview: ProviderKeyScopeOverview,
        overview: RemoteQuotaCenterOverview,
        focusedUser: RemoteQuotaCenterUserProjection?,
        focusedVendor: ProviderKeyVendorInventorySummary?
    ) -> String {
        var parts: [String] = [
            "\(scopeOverview.userCount) 用户 / \(scopeOverview.consumerCount) 消费者",
            "\(overview.quotaPoolCount) 个额度池 / \(overview.keyPoolCount) 个物理池",
            "Ready key \(overview.readyKeys)/\(overview.totalKeys)"
        ]
        if let focusedVendor {
            parts.append("锁定 \(focusedVendor.displayName)")
        }
        if let focusedUser {
            parts.append("锁定 \(focusedUser.displayName)")
        }
        return parts.joined(separator: " · ")
    }

    func providerKeyOperationalTint(
        focusedUser: RemoteQuotaCenterUserProjection?,
        focusedVendor: ProviderKeyVendorInventorySummary?,
        riskVendorCount: Int,
        riskFamilyCount: Int
    ) -> Color {
        if riskVendorCount > 0 || riskFamilyCount > 0 {
            return riskFamilyCount > 0 ? .red : .orange
        }
        if focusedVendor != nil {
            return .indigo
        }
        if focusedUser != nil {
            return .teal
        }
        return .blue
    }

    func providerKeyConsumerLedgerDisclosureSummary(
        _ consumers: [RemoteQuotaCenterClientProjection],
        totalConsumers: Int,
        focusedUser: RemoteQuotaCenterUserProjection?
    ) -> String {
        let xtCount = consumers.filter { $0.consumerKind == .pairedXT }.count
        let terminalCount = consumers.filter { $0.consumerKind == .terminalAccess }.count
        let riskCount = consumers.filter(providerKeyConsumerAtRisk(_:)).count
        var parts: [String] = ["\(consumers.count)/\(max(totalConsumers, consumers.count)) 个消费者"]
        if xtCount > 0 {
            parts.append("XT \(xtCount)")
        }
        if terminalCount > 0 {
            parts.append("Terminal \(terminalCount)")
        }
        if riskCount > 0 {
            parts.append("\(riskCount) 个风险")
        }
        if let focusedUser {
            parts.append("已锁定 \(focusedUser.displayName)")
        }
        return parts.joined(separator: " · ")
    }

    var terminalAccessDraftSummaryText: String {
        let name = terminalAccessDraft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let userID = terminalAccessDraft.userID.trimmingCharacters(in: .whitespacesAndNewlines)
        let appID = terminalAccessDraft.appID.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        parts.append(name.isEmpty ? "未命名 access key" : name)
        if !userID.isEmpty {
            parts.append("user \(userID)")
        }
        if !appID.isEmpty {
            parts.append("app \(appID)")
        }
        parts.append("预算 \(terminalAccessIntText(Int64(max(1, terminalAccessDraft.dailyTokenLimit))))/day")
        parts.append(terminalAccessDraft.ttlHours == 0 ? "不过期" : "TTL \(terminalAccessDraft.ttlHours)h")
        parts.append(terminalAccessDraft.allowPaidModels ? "付费模型开" : "付费模型关")
        parts.append(terminalAccessDraft.defaultWebFetchEnabled ? "web.fetch 开" : "web.fetch 关")
        return parts.joined(separator: " · ")
    }

    func terminalAccessLastSecretSummaryText(_ secret: HubTerminalAccessKeySecretEnvelope) -> String {
        let deliveryPack = secret.deliveryPack
        var parts: [String] = [secret.accessKey.resolvedName]
        if !deliveryPack.authDisplayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(deliveryPack.authDisplayText)
        }
        if !secret.openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(settingsSummarySnippet(secret.openAIBaseURL, limit: 42))
        }
        parts.append("离开此页前请先完成分发")
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    func settingsActionChipLabel(
        title: String,
        systemName: String,
        tint: Color,
        disabled: Bool = false
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .imageScale(.small)
            Text(title)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(disabled ? .secondary : tint)
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(tint.opacity(disabled ? 0.05 : 0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(tint.opacity(disabled ? 0.10 : 0.24), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    @ViewBuilder
    func settingsOperationsPanelCard<Content: View>(
        systemName: String,
        title: String,
        summary: String,
        badge: String,
        tint: Color,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    tint.opacity(0.18),
                                    tint.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: systemName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(badge)
                            .font(.caption2.monospaced())
                            .foregroundStyle(tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(tint.opacity(0.10))
                            .clipShape(Capsule())
                    }

                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }

            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(0.09),
                            Color.primary.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    func settingsInlineDisclosureLabel(
        systemName: String,
        title: String,
        summary: String,
        badge: String,
        tint: Color,
        isExpanded: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.12))
                Image(systemName: isExpanded ? "chevron.down.circle.fill" : systemName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(badge)
                        .font(.caption2.monospaced())
                        .foregroundStyle(tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(tint.opacity(0.10))
                        .clipShape(Capsule())
                }
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(isExpanded ? "收起详情" : "展开详情")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
            }

            Spacer(minLength: 8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        )
    }

    @ViewBuilder
    func settingsInlineDisclosureGroup<Content: View>(
        systemName: String,
        title: String,
        summary: String,
        badge: String,
        tint: Color,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            content()
                .padding(.top, 6)
        } label: {
            settingsInlineDisclosureLabel(
                systemName: systemName,
                title: title,
                summary: summary,
                badge: badge,
                tint: tint,
                isExpanded: isExpanded.wrappedValue
            )
        }
    }

    @ViewBuilder
    func settingsCollapsedSectionCard(
        title: String,
        summary: String,
        badge: String,
        tint: Color,
        isExpanded: Binding<Bool>
    ) -> some View {
        Section {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(tint.opacity(0.12))
                        Image(systemName: isExpanded.wrappedValue ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(badge)
                                .font(.caption2.monospaced())
                                .foregroundStyle(tint)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(tint.opacity(0.10))
                                .clipShape(Capsule())
                        }
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(isExpanded.wrappedValue ? "收起详细配置" : "展开详细配置")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(tint)
                    }

                    Spacer(minLength: 8)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(tint.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(tint.opacity(0.16), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func settingsSidebarBadge(for page: HubSettingsPage) -> String {
        switch page {
        case .overview:
            return currentLaunchStateLabel
        case .access:
            return "\(grpc.allowedClients.count) XT"
        case .models:
            if localCatalogModelCount == 0 && remoteModels.isEmpty && providerKeyDerivedSnapshot.totalAccounts == 0 {
                return "未配置"
            }
            return "本地 \(localCatalogModelCount) · 付费 \(remoteModels.count)"
        case .runtime:
            return totalRuntimeProviderCount > 0 ? "\(readyRuntimeProviderCount)/\(totalRuntimeProviderCount) 就绪" : "等待心跳"
        case .integrations:
            return "\(skillsIndex.skills.count) skills"
        case .diagnostics:
            return settingsIssueCount > 0 ? "\(settingsIssueCount) 项" : "稳定"
        }
    }

    private func settingsSidebarDetail(for page: HubSettingsPage) -> String {
        switch page {
        case .overview:
            return "查看当前健康度、配置完成度和关键风险。"
        case .access:
            return "谁能连接 Hub，以及如何连接。"
        case .models:
            return "本地模型能力、付费模型能力与共享额度。"
        case .runtime:
            return "Provider、队列、实例与路由排障。"
        case .integrations:
            return "Operator、Skills、Calendar 与浮窗。"
        case .diagnostics:
            return "排障、日志、恢复动作与底层参数。"
        }
    }

    private func settingsPageMetrics(for page: HubSettingsPage) -> [HubSettingsMetric] {
        switch page {
        case .overview:
            return headerMetrics
        case .access:
            return [
                HubSettingsMetric(
                    title: "XT 设备",
                    value: "\(grpc.allowedClients.count)",
                    detail: grpc.statusText,
                    tint: .teal
                ),
                HubSettingsMetric(
                    title: "Terminal Key",
                    value: terminalAccessKeys.isEmpty ? "未签发" : "\(terminalAccessReadyCount)/\(terminalAccessKeys.count)",
                    detail: terminalAccessKeys.isEmpty ? "还没有普通 terminal key" : "可直接导出给普通 terminal",
                    tint: .blue
                ),
                HubSettingsMetric(
                    title: "远程接入",
                    value: grpcRemoteAccessHealthSummary.badgeText,
                    detail: grpcRemoteAccessHealthSummary.accessScopeText,
                    tint: grpcRemoteAccessHealthSummary.state == .ready ? .green : .orange
                ),
                HubSettingsMetric(
                    title: "Pairing",
                    value: "\(grpc.xtTerminalPairingPort)",
                    detail: grpc.xtTerminalInternetHost ?? "当前没有稳定外部地址",
                    tint: .indigo
                )
            ]
        case .models:
            let providerDerived = providerKeyDerivedSnapshot
            let importIssueCount = providerKeySnapshot.importSources.filter { source in
                source.state != "ready" || source.lastErrorCount > 0
            }.count
            return [
                HubSettingsMetric(
                    title: "本地模型",
                    value: localCatalogModelCount == 0 ? "未发现" : "\(loadedLocalModelCount)/\(localCatalogModelCount)",
                    detail: localCatalogModelCount == 0
                        ? "当前还没有发现可由 Hub 管理的本地模型"
                        : "已加载 / 全部 · 预检可用 \(localAvailableModelCount) · 待复核 \(localPendingModelCount)",
                    tint: localModelsCapabilityTint
                ),
                HubSettingsMetric(
                    title: "付费模型",
                    value: remoteModels.isEmpty
                        ? (providerDerived.totalAccounts > 0 ? "待编目" : "未配置")
                        : "\(loadedRemoteModelCount)/\(remoteModels.count)",
                    detail: remoteModels.isEmpty
                        ? (providerDerived.totalAccounts > 0
                            ? "已导入 \(providerDerived.totalAccounts) 个 key，可继续编入可执行付费模型"
                            : "当前还没有配置任何付费 / 远端模型")
                        : "已加载 / 全部 · 可执行 \(availableRemoteModelCount) · 待补齐 \(needsSetupRemoteModelCount)",
                    tint: needsSetupRemoteModelCount > 0 ? .orange : (loadedRemoteModelCount > 0 ? .green : .indigo)
                ),
                HubSettingsMetric(
                    title: "Key 健康",
                    value: "\(providerDerived.readyAccounts)/\(providerDerived.totalAccounts)",
                    detail: importIssueCount > 0
                        ? "就绪 / 全部 · 阻塞 \(providerDerived.blockedAccounts) · 导入源异常 \(importIssueCount)"
                        : "就绪 / 全部 · 阻塞 \(providerDerived.blockedAccounts)",
                    tint: providerDerived.blockedAccounts > 0 ? .orange : .green
                ),
                HubSettingsMetric(
                    title: "额度池",
                    value: "\(quotaPoolCount)",
                    detail: "按模型家族聚合后的共享库存",
                    tint: .blue
                ),
                HubSettingsMetric(
                    title: "物理池",
                    value: "\(providerDerived.keyPools.count)",
                    detail: "冷却 \(providerDerived.cooldownAccounts) · 阻塞 \(providerDerived.blockedAccounts)",
                    tint: .purple
                ),
                cliproxyOAuthHeaderMetric
            ]
        case .runtime:
            return [
                HubSettingsMetric(
                    title: "Runtime",
                    value: runtimeHeartbeatText,
                    detail: totalRuntimeProviderCount > 0 ? "\(readyRuntimeProviderCount)/\(totalRuntimeProviderCount) 个 provider 可用" : "等待 runtime 状态上报",
                    tint: runtimeHeartbeatText == "在线" ? .green : .orange
                ),
                HubSettingsMetric(
                    title: "已加载模型",
                    value: "\(loadedLocalModelCount)",
                    detail: "本地模型库里当前标记为 loaded 的条目",
                    tint: .orange
                ),
                HubSettingsMetric(
                    title: "驻留实例",
                    value: "\(loadedRuntimeInstanceCount)",
                    detail: "当前 runtime 里可直接复用的实例",
                    tint: .blue
                ),
                HubSettingsMetric(
                    title: "默认路由",
                    value: "\(store.routingSettings.hubDefaultModelIdByTaskKind.count)",
                    detail: "Hub 级 task-kind 默认模型覆盖",
                    tint: .indigo
                )
            ]
        case .integrations:
            return [
                HubSettingsMetric(
                    title: "Operator",
                    value: operatorChannelProviderReadiness.isEmpty ? "待检测" : "\(operatorReadyCount)/\(operatorChannelProviderReadiness.count)",
                    detail: operatorChannelProviderReadinessError.isEmpty ? "渠道投递 readiness 快照" : operatorChannelProviderReadinessError,
                    tint: operatorChannelProviderReadinessError.isEmpty ? .green : .orange
                ),
                HubSettingsMetric(
                    title: "Skills",
                    value: "\(skillsIndex.skills.count)",
                    detail: "当前可解析的技能包数量",
                    tint: .green
                ),
                HubSettingsMetric(
                    title: "Calendar",
                    value: store.calendarStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未配置" : store.calendarStatus,
                    detail: "日历与本地提醒接入状态",
                    tint: .blue
                ),
                HubSettingsMetric(
                    title: "Floating",
                    value: store.floatingMode.title,
                    detail: "当前浮窗展示模式",
                    tint: .teal
                )
            ]
        case .diagnostics:
            return [
                HubSettingsMetric(
                    title: "启动状态",
                    value: currentLaunchStateLabel,
                    detail: hubLaunchStatus?.rootCause?.errorCode ?? "没有 root cause",
                    tint: headerLaunchTint
                ),
                HubSettingsMetric(
                    title: "阻塞能力",
                    value: "\(blockedCapabilityCount)",
                    detail: blockedCapabilityCount == 0 ? "当前没有被降级的 capability" : "当前有 capability 被 fail-closed",
                    tint: blockedCapabilityCount > 0 ? .orange : .green
                ),
                HubSettingsMetric(
                    title: "拒绝记录",
                    value: "\(grpcDeniedAttempts.attempts.count)",
                    detail: grpcDeniedAttempts.attempts.isEmpty ? "最近没有新的 grant 拒绝" : "最近存在安全拒绝或权限问题",
                    tint: grpcDeniedAttempts.attempts.isEmpty ? .green : .orange
                ),
                HubSettingsMetric(
                    title: "诊断历史",
                    value: "\(hubLaunchHistory.launches.count)",
                    detail: "已保留的启动 / 降级历史条目",
                    tint: .red
                )
            ]
        }
    }

    private func settingsPageSections(for page: HubSettingsPage) -> some View {
        Group {
            switch page {
            case .overview:
                setupCenterSection
                cliproxyOAuthOverviewSection
                firstRunFastPathSection
                quickTroubleshootSection
            case .access:
                grpcServerSection
                terminalAccessSection
            case .models:
                modelResourcePoolsSection
                settingsCollapsedSectionCard(
                    title: "模型编目与运行明细",
                    summary: "导入本地模型、维护付费模型目录、运行快速预检和健康扫描。",
                    badge: modelCatalogDetailsExpanded
                        ? "已展开"
                        : "本地 \(localCatalogModelCount) · 付费 \(remoteModels.count)",
                    tint: .indigo,
                    isExpanded: $modelCatalogDetailsExpanded
                )
                if modelCatalogDetailsExpanded {
                    localModelsCapabilitySection
                    remoteModelsSection
                }
                settingsCollapsedSectionCard(
                    title: "高级配额运营",
                    summary: providerQuotaOperationsSummaryText,
                    badge: providerQuotaOperationsExpanded ? "已展开" : providerQuotaOperationsBadgeText,
                    tint: providerQuotaOperationsTint,
                    isExpanded: $providerQuotaOperationsExpanded
                )
                if providerQuotaOperationsExpanded {
                    providerKeySection
                }
                settingsCollapsedSectionCard(
                    title: "自动扫描与保活策略",
                    summary: modelHealthAutoScanSummaryText,
                    badge: modelsAutoScanExpanded ? "已展开" : "低频项",
                    tint: .indigo,
                    isExpanded: $modelsAutoScanExpanded
                )
                if modelsAutoScanExpanded {
                    modelHealthAutoScanSection
                }
            case .runtime:
                rustHubKernelSection
                runtimeMonitorSection
                settingsCollapsedSectionCard(
                    title: "任务路由映射",
                    summary: routingSummaryText,
                    badge: runtimeRoutingExpanded ? "已展开" : "按需配置",
                    tint: .orange,
                    isExpanded: $runtimeRoutingExpanded
                )
                if runtimeRoutingExpanded {
                    routingSection
                }
            case .integrations:
                operatorChannelReadinessSection
                settingsCollapsedSectionCard(
                    title: "扩展接入与低频维护",
                    summary: integrationsAuxSummaryText,
                    badge: integrationsAuxExpanded ? "已展开" : "低频项",
                    tint: .green,
                    isExpanded: $integrationsAuxExpanded
                )
                if integrationsAuxExpanded {
                    operatorChannelOnboardingSection
                    skillsSection
                    calendarSection
                    floatingModeSection
                }
            case .diagnostics:
                doctorSection
                settingsCollapsedSectionCard(
                    title: "启动链路明细",
                    summary: diagnosticsLaunchSummaryText,
                    badge: currentLaunchStateLabel,
                    tint: headerLaunchTint,
                    isExpanded: $diagnosticsLaunchExpanded
                )
                if diagnosticsLaunchExpanded {
                    diagnosticsSection
                }
                settingsCollapsedSectionCard(
                    title: "网络授权与桥接",
                    summary: diagnosticsNetworkSummaryText,
                    badge: diagnosticsNetworkExpanded
                        ? "已展开"
                        : (store.pendingNetworkRequests.isEmpty ? "干净" : "\(store.pendingNetworkRequests.count) 待处理"),
                    tint: store.pendingNetworkRequests.isEmpty ? .teal : .orange,
                    isExpanded: $diagnosticsNetworkExpanded
                )
                if diagnosticsNetworkExpanded {
                    networkPoliciesSection
                    networkingSection
                }
                settingsCollapsedSectionCard(
                    title: "高级参数",
                    summary: diagnosticsAdvancedSummaryText,
                    badge: diagnosticsAdvancedExpanded ? "已展开" : "专家项",
                    tint: .secondary,
                    isExpanded: $diagnosticsAdvancedExpanded
                )
                if diagnosticsAdvancedExpanded {
                    advancedSection
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(HubUIStrings.Settings.title)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text(HubUIStrings.Settings.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    Text(HubUIStrings.Settings.validationChain)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(headerLaunchTint.opacity(0.12))
                        .foregroundStyle(headerLaunchTint)
                        .clipShape(Capsule())
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(headerMetrics) { metric in
                    settingsMetricCard(metric, compact: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .controlBackgroundColor),
                            headerLaunchTint.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var formContent: some View {
        HStack(alignment: .top, spacing: 18) {
            settingsSidebar
            settingsPageSurface
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Control Center")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ForEach(HubSettingsPage.allCases) { page in
                Button {
                    selectSettingsPage(page)
                } label: {
                    settingsSidebarRow(page)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 10) {
                Text("App")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                let ver = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
                let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
                Text(HubUIStrings.Settings.Quit.version(ver, build))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Button(HubUIStrings.Settings.Quit.quitApp) {
                    quitApp()
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(18)
        .frame(width: 252, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func settingsSidebarRow(_ page: HubSettingsPage) -> some View {
        let isSelected = selectedSettingsPage == page
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(page.tint.opacity(isSelected ? 0.22 : 0.12))
                Image(systemName: page.systemName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(page.tint)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(page.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Text(settingsSidebarBadge(for: page))
                        .font(.caption2.monospaced())
                        .foregroundStyle(isSelected ? page.tint : .secondary)
                }
                Text(settingsSidebarDetail(for: page))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? page.tint.opacity(0.10) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? page.tint.opacity(0.35) : Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private var settingsPageSurface: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    settingsPageHero(selectedSettingsPage)
                    settingsPageSections(for: selectedSettingsPage)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
            .id(selectedSettingsPage.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear {
                scrollToSettingsTargetIfNeeded(proxy)
            }
            .onChange(of: settingsScrollTarget) { _ in
                scrollToSettingsTargetIfNeeded(proxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func settingsPageHero(_ page: HubSettingsPage) -> some View {
        let metrics = settingsPageMetrics(for: page)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    page.tint.opacity(0.22),
                                    page.tint.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: page.systemName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(page.tint)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 5) {
                    Text(page.title)
                        .font(.title3.weight(.semibold))
                    Text(page.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(settingsSidebarBadge(for: page))
                    .font(.caption.monospaced())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(page.tint.opacity(0.12))
                    .foregroundStyle(page.tint)
                    .clipShape(Capsule())
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(metrics) { metric in
                    settingsMetricCard(metric, compact: false)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            page.tint.opacity(0.12),
                            Color.primary.opacity(0.025)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    func settingsMetricCard(_ metric: HubSettingsMetric, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            Text(metric.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(metric.value)
                .font(compact ? .subheadline.weight(.semibold) : .title3.weight(.semibold))
            Text(metric.detail)
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(.secondary)
                .lineLimit(compact ? 2 : 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 12 : 14)
        .background(metric.tint.opacity(compact ? 0.08 : 0.10))
        .clipShape(RoundedRectangle(cornerRadius: compact ? 16 : 18, style: .continuous))
    }

    private var setupCenterSection: some View {
        Section(HubUIStrings.Settings.Overview.sectionTitle) {
            HubSectionCard(
                systemImage: "link.badge.plus",
                title: HubUIStrings.Settings.Overview.PairHub.title,
                summary: HubUIStrings.Settings.Overview.PairHub.summary,
                badge: grpc.isRunning ? HubUIStrings.Settings.Overview.PairHub.readyBadge : HubUIStrings.Settings.Overview.PairHub.needsStartBadge,
                highlights: [
                    HubUIStrings.Settings.Overview.PairHub.allowedClients(grpc.allowedClients.count),
                    HubUIStrings.Settings.Overview.PairHub.pairingPort(grpc.xtTerminalPairingPort),
                    grpc.statusText
                ]
            )

            HubSectionCard(
                systemImage: "cpu",
                title: HubUIStrings.Settings.Overview.Models.title,
                summary: HubUIStrings.Settings.Overview.Models.summary,
                badge: activeRemoteModelCount > 0 ? HubUIStrings.Settings.Overview.Models.enabledBadge(activeRemoteModelCount) : HubUIStrings.Settings.Overview.Models.localOnlyBadge,
                highlights: HubUIStrings.Settings.Overview.Models.highlights
            )

            HubSectionCard(
                systemImage: "checkmark.shield",
                title: HubUIStrings.Settings.Overview.Grants.title,
                summary: HubUIStrings.Settings.Overview.Grants.summary,
                badge: grpcDeniedAttempts.attempts.isEmpty ? HubUIStrings.Settings.Overview.Grants.clearBadge : HubUIStrings.Settings.Overview.Grants.blockedBadge(grpcDeniedAttempts.attempts.count),
                highlights: HubUIStrings.Settings.Overview.Grants.highlights
            )

            HubSectionCard(
                systemImage: "lock.shield",
                title: HubUIStrings.Settings.Overview.Security.title,
                summary: HubUIStrings.Settings.Overview.Security.summary,
                badge: networkPolicies.isEmpty ? HubUIStrings.Settings.Overview.Security.defaultBadge : HubUIStrings.Settings.Overview.Security.rulesBadge(networkPolicies.count),
                highlights: HubUIStrings.Settings.Overview.Security.highlights
            )

            HubSectionCard(
                systemImage: "stethoscope",
                title: HubUIStrings.Settings.Overview.Diagnostics.title,
                summary: HubUIStrings.Settings.Overview.Diagnostics.summary,
                badge: currentLaunchStateLabel,
                highlights: HubUIStrings.Settings.Overview.Diagnostics.highlights
            )
        }
    }

    private var cliproxyOAuthOverviewSection: some View {
        Section("CLIProxy 库存雷达") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CLIProxy Free Tier Radar")
                            .font(.headline)
                        Text("把 CLIProxy 管理页里已经认证成功的账号，直接抬到总览层看库存健康、冷却恢复和厂家覆盖。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Text(cliproxyOAuthStatusBadgeText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(cliproxyOAuthStatusTint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(cliproxyOAuthStatusTint.opacity(0.12))
                        .clipShape(Capsule())
                }

                Text(cliproxyOAuthOverviewSummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 168), spacing: 10)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(cliproxyOAuthOverviewMetrics) { metric in
                        settingsMetricCard(metric, compact: false)
                    }
                }

                terminalAccessFeedbackBanner(
                    text: cliproxyOAuthOverviewNoticeText,
                    tint: cliproxyOAuthOverviewNoticeTint,
                    systemName: cliproxyOAuthOverviewNoticeSystemName
                )

                if !cliproxyOAuthProviderSummaries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("厂家库存条带")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("点任一厂家可直达模型页对应的厂家经营总账。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 180), spacing: 10)],
                            alignment: .leading,
                            spacing: 10
                        ) {
                            ForEach(cliproxyOAuthProviderSummaries) { summary in
                                cliproxyOAuthProviderOverviewCard(summary)
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    cliproxyOAuthActionButton(
                        title: "管理库存",
                        systemName: "slider.horizontal.3",
                        tint: .indigo
                    ) {
                        openCLIProxyOAuthInventoryManager()
                    }

                    cliproxyOAuthActionButton(
                        title: "打开管理页",
                        systemName: "globe",
                        tint: .teal
                    ) {
                        openCLIProxyOAuthManagementConsole()
                    }

                    cliproxyOAuthActionButton(
                        title: cliproxyOAuthSyncing ? "同步中" : "同步到 Hub",
                        systemName: "shippingbox.and.arrow.backward",
                        tint: .green,
                        disabled: cliproxyOAuthSyncing
                    ) {
                        Task { await syncCLIProxyOAuthAccounts(manual: true) }
                    }
                }
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [
                        Color.teal.opacity(0.12),
                        Color.blue.opacity(0.08),
                        Color.mint.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.teal.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var firstRunFastPathSection: some View {
        Section(HubUIStrings.Settings.FirstRun.sectionTitle) {
            VStack(alignment: .leading, spacing: 10) {
                Text(HubUIStrings.Settings.FirstRun.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                firstRunStepRow(
                    index: 1,
                    title: HubUIStrings.Settings.FirstRun.step1Title,
                    summary: HubUIStrings.Settings.FirstRun.step1Summary
                ) {
                    Button(HubUIStrings.Settings.FirstRun.copyBootstrap) { grpc.copyBootstrapCommandToClipboard() }
                    Button(HubUIStrings.Settings.FirstRun.addDevice) { showAddGRPCClient = true }
                    Button(HubUIStrings.Settings.FirstRun.refresh) { grpc.refresh() }
                }

                firstRunStepRow(
                    index: 2,
                    title: HubUIStrings.Settings.FirstRun.step2Title,
                    summary: HubUIStrings.Settings.FirstRun.step2Summary
                ) {
                    Button(HubUIStrings.Settings.FirstRun.addPaidModel) { showAddRemoteModel = true }
                    Button(HubUIStrings.Settings.FirstRun.openQuotaSettings) { grpc.openQuotaConfig() }
                }

                firstRunStepRow(
                    index: 3,
                    title: HubUIStrings.Settings.FirstRun.step3Title,
                    summary: HubUIStrings.Settings.FirstRun.step3Summary
                ) {
                    if let preferredClientForRepair {
                        Button(HubUIStrings.Settings.FirstRun.editDevice) {
                            presentGRPCClientEditor(preferredClientForRepair)
                        }
                    } else {
                        Button(HubUIStrings.Settings.FirstRun.openDeviceList) { grpc.openClientsConfig() }
                    }
                    Button(HubUIStrings.Settings.FirstRun.openAccessibility) { SystemSettingsLinks.openAccessibilityPrivacy() }
                    Button(HubUIStrings.Settings.FirstRun.openQuotaSettings) { grpc.openQuotaConfig() }
                }

                firstRunStepRow(
                    index: 4,
                    title: HubUIStrings.Settings.FirstRun.step4Title,
                    summary: HubUIStrings.Settings.FirstRun.step4Summary
                ) {
                    Button(HubUIStrings.Settings.FirstRun.fixNow) { fixNow(snapshot: hubLaunchStatus) }
                    Button(HubUIStrings.Settings.FirstRun.openLog) { grpc.openLog() }
                    Button(HubUIStrings.Settings.FirstRun.refresh) { grpc.refresh() }
                }
            }
        }
    }

    private var quickTroubleshootSection: some View {
        Section(HubUIStrings.Settings.Troubleshoot.sectionTitle) {
            VStack(alignment: .leading, spacing: 10) {
                quickFixCard(
                    title: HubUIStrings.Settings.Troubleshoot.grantTitle,
                    summary: HubUIStrings.Settings.Troubleshoot.grantSummary,
                    steps: HubUIStrings.Settings.Troubleshoot.grantSteps
                ) {
                    Button(HubUIStrings.Settings.Troubleshoot.addModel) { showAddRemoteModel = true }
                    Button(HubUIStrings.Settings.FirstRun.openQuotaSettings) { grpc.openQuotaConfig() }
                }

                quickFixCard(
                    title: HubUIStrings.Settings.Troubleshoot.permissionTitle,
                    summary: HubUIStrings.Settings.Troubleshoot.permissionSummary,
                    steps: HubUIStrings.Settings.Troubleshoot.permissionSteps
                ) {
                    Button(HubUIStrings.Settings.FirstRun.openAccessibility) { SystemSettingsLinks.openAccessibilityPrivacy() }
                    if let preferredClientForRepair {
                        Button(HubUIStrings.Settings.FirstRun.editDevice) {
                            presentGRPCClientEditor(preferredClientForRepair)
                        }
                    }
                }

                quickFixCard(
                    title: HubUIStrings.Settings.Troubleshoot.hubOfflineTitle,
                    summary: HubUIStrings.Settings.Troubleshoot.hubOfflineSummary,
                    steps: HubUIStrings.Settings.Troubleshoot.hubOfflineSteps
                ) {
                    Button(HubUIStrings.Settings.FirstRun.fixNow) { fixNow(snapshot: hubLaunchStatus) }
                    Button(HubUIStrings.Settings.FirstRun.openLog) { grpc.openLog() }
                    Button(HubUIStrings.Settings.FirstRun.refresh) { grpc.refresh() }
                }

                if let denied = grpcDeniedAttempts.attempts.first {
                    Text(HubUIStrings.Settings.Troubleshoot.latestDenied(denied.clientName.isEmpty ? denied.deviceId : denied.clientName, reason: denied.reason))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var activeRemoteModelCount: Int {
        remoteModels.filter { $0.enabled }.count
    }

    var localModelsCapabilitySummaryText: String {
        guard localCatalogModelCount > 0 else {
            return "先扫描并导入本地模型。这里和付费模型并列管理本地文本、多模态、OCR 与 TTS 能力。"
        }

        var parts: [String] = ["\(localCatalogModelCount) 个模型", "\(loadedLocalModelCount) 已加载"]
        if let summary = localModelHealthSummary?.text,
           !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(summary)
        }
        if totalRuntimeProviderCount > 0 {
            parts.append("\(readyRuntimeProviderCount)/\(totalRuntimeProviderCount) 个 runtime provider 就绪")
        } else {
            parts.append("等待 runtime 心跳")
        }
        return parts.joined(separator: " · ")
    }

    var localModelsCapabilityBadgeText: String {
        guard localCatalogModelCount > 0 else { return "未发现" }
        if store.localModelHealthScanInFlight || localScanningModelCount > 0 {
            return "扫描中"
        }
        if runtimeHeartbeatText != "在线" && loadedLocalModelCount == 0 {
            return "等待 runtime"
        }
        if loadedLocalModelCount > 0 {
            return "\(loadedLocalModelCount) 已加载"
        }
        if localAvailableModelCount > 0 {
            return "\(localAvailableModelCount) 可用"
        }
        if localPendingModelCount > 0 {
            return "\(localPendingModelCount) 待复核"
        }
        return "待准备"
    }

    var localModelsCapabilityTint: Color {
        guard localCatalogModelCount > 0 else { return .secondary }
        if runtimeHeartbeatText != "在线" && loadedLocalModelCount == 0 {
            return .orange
        }
        if store.localModelHealthScanInFlight || localScanningModelCount > 0 {
            return .teal
        }
        if loadedLocalModelCount > 0 {
            return .green
        }
        if localAvailableModelCount > 0 {
            return .indigo
        }
        if localPendingModelCount > 0 {
            return .orange
        }
        return .secondary
    }

    var localModelsCapabilityMetrics: [HubSettingsMetric] {
        [
            HubSettingsMetric(
                title: "模型库",
                value: "\(localCatalogModelCount)",
                detail: localCatalogModelCount == 0 ? "当前没有本地模型" : "只统计本地模型，不含付费 / 远端入口",
                tint: localCatalogModelCount > 0 ? .indigo : .secondary
            ),
            HubSettingsMetric(
                title: "已加载",
                value: "\(loadedLocalModelCount)",
                detail: localCatalogModelCount == 0 ? "等待导入本地模型" : "当前可直接复用的本地加载态模型",
                tint: loadedLocalModelCount > 0 ? .green : .secondary
            ),
            HubSettingsMetric(
                title: "预检可用",
                value: "\(localAvailableModelCount)",
                detail: HubUIStrings.Settings.RemoteModels.sectionSummary([
                    localReviewModelCount > 0 ? "复核 \(localReviewModelCount)" : nil,
                    localDiscouragedModelCount > 0 ? "风险 \(localDiscouragedModelCount)" : nil,
                    localUnscannedModelCount > 0 ? "未扫描 \(localUnscannedModelCount)" : nil
                ].compactMap { $0 }.isEmpty
                    ? ["当前没有待复核或未扫描模型"]
                    : [
                        localReviewModelCount > 0 ? "复核 \(localReviewModelCount)" : nil,
                        localDiscouragedModelCount > 0 ? "风险 \(localDiscouragedModelCount)" : nil,
                        localUnscannedModelCount > 0 ? "未扫描 \(localUnscannedModelCount)" : nil
                    ].compactMap { $0 }),
                tint: localAvailableModelCount > 0 ? .blue : .secondary
            ),
            HubSettingsMetric(
                title: "Runtime",
                value: totalRuntimeProviderCount == 0 ? "待连接" : "\(readyRuntimeProviderCount)/\(totalRuntimeProviderCount)",
                detail: runtimeHeartbeatText == "在线"
                    ? "provider 心跳正常，可继续承接本地任务"
                    : "provider 心跳未就绪，本地任务可能无法稳定执行",
                tint: runtimeHeartbeatText == "在线" ? .orange : .red
            )
        ]
    }

    var localModelsCapabilityNoticeText: String? {
        guard localCatalogModelCount > 0 else { return nil }
        if runtimeHeartbeatText != "在线" {
            return "当前本地 runtime \(runtimeHeartbeatText)，本地模型暂时不能稳定承接任务。先到“运行时基础设施”恢复 provider 心跳和实例。"
        }
        if localDiscouragedModelCount > 0 {
            return "当前有 \(localDiscouragedModelCount) 个本地模型被标记为高风险，先修复兼容、依赖或快速评审结果，再给 XT 默认路由。"
        }
        if localUnscannedModelCount > 0 {
            return "当前还有 \(localUnscannedModelCount) 个本地模型尚未做快速评审，建议先扫一轮再暴露给 XT。"
        }
        if loadedLocalModelCount == 0 && localAvailableModelCount > 0 {
            return "当前没有常驻本地模型，但已有 \(localAvailableModelCount) 个模型通过快速评审，可按需自动加载。"
        }
        if loadedLocalModelCount > 0 {
            return "当前已有 \(loadedLocalModelCount) 个本地模型处于加载态，可直接承接本地文本或多模态任务。"
        }
        return nil
    }

    var localModelsCapabilityNoticeTint: Color {
        if runtimeHeartbeatText != "在线" {
            return .orange
        }
        if localDiscouragedModelCount > 0 || localUnscannedModelCount > 0 {
            return .orange
        }
        if loadedLocalModelCount > 0 {
            return .green
        }
        return .blue
    }

    var localModelsCapabilityNoticeSystemName: String {
        if runtimeHeartbeatText != "在线" {
            return "exclamationmark.triangle"
        }
        if localDiscouragedModelCount > 0 || localUnscannedModelCount > 0 {
            return "shield.lefthalf.filled.badge.exclamationmark"
        }
        if loadedLocalModelCount > 0 {
            return "checkmark.seal"
        }
        return "sparkles"
    }

    private var loadedRemoteModelCount: Int {
        remoteModelGroups.reduce(0) { $0 + $1.loadedCount }
    }

    private var availableRemoteModelCount: Int {
        remoteModelGroups.reduce(0) { $0 + $1.availableCount }
    }

    private var needsSetupRemoteModelCount: Int {
        remoteModelGroups.reduce(0) { $0 + $1.needsSetupCount }
    }

    var remoteModelGroupCount: Int {
        remoteModelGroups.count
    }

    private var remoteModelEndpointHostCount: Int {
        Set(remoteModels.compactMap { remoteModelEndpointHost($0) }).count
    }

    var remoteModelsSectionSummaryText: String {
        guard !remoteModels.isEmpty else {
            return "先接入可执行的 provider / model，再用这里统一管理远端文本、多模态和专用入口。"
        }

        var parts: [String] = ["\(remoteModelGroupCount) 个组"]
        parts.append("\(loadedRemoteModelCount) 已加载")
        if availableRemoteModelCount > 0 {
            parts.append("\(availableRemoteModelCount) 可执行")
        }
        if needsSetupRemoteModelCount > 0 {
            parts.append("\(needsSetupRemoteModelCount) 待补齐")
        }
        if remoteModelEndpointHostCount > 0 {
            parts.append("\(remoteModelEndpointHostCount) 个 host")
        }
        return parts.joined(separator: " · ")
    }

    var remoteModelsAttentionBannerText: String? {
        guard !remoteModels.isEmpty else { return nil }
        if needsSetupRemoteModelCount > 0 {
            return "当前还有 \(needsSetupRemoteModelCount) 个远端模型待补齐 auth / 兼容 / provider 健康，修完后才适合给 XT 稳定路由。"
        }
        if loadedRemoteModelCount == 0 && availableRemoteModelCount > 0 {
            return "当前没有已加载远端模型，但已有 \(availableRemoteModelCount) 个入口可直接执行。需要时可以在下面按组加载。"
        }
        if loadedRemoteModelCount > 0 {
            return "当前已有 \(loadedRemoteModelCount) 个远端模型处于加载态，可直接复用；其余模型按需加载即可。"
        }
        return nil
    }

    var remoteModelsOverviewBadgeText: String {
        if remoteModels.isEmpty {
            return "未配置"
        }
        if needsSetupRemoteModelCount > 0 {
            return "\(needsSetupRemoteModelCount) 待补齐"
        }
        if loadedRemoteModelCount > 0 {
            return "\(loadedRemoteModelCount) 已加载"
        }
        if availableRemoteModelCount > 0 {
            return "\(availableRemoteModelCount) 可执行"
        }
        return "待加载"
    }

    var remoteModelsOverviewTint: Color {
        if needsSetupRemoteModelCount > 0 {
            return .orange
        }
        if loadedRemoteModelCount > 0 {
            return .green
        }
        if availableRemoteModelCount > 0 {
            return .indigo
        }
        return .secondary
    }

    var remoteModelsOverviewMetrics: [HubSettingsMetric] {
        [
            HubSettingsMetric(
                title: "模型组",
                value: "\(remoteModelGroupCount)",
                detail: remoteModelGroupCount == 0 ? "还没有聚合出的远端执行组" : "按 provider / key 聚合后的入口",
                tint: remoteModelGroupCount > 0 ? .indigo : .secondary
            ),
            HubSettingsMetric(
                title: "已加载",
                value: "\(loadedRemoteModelCount)",
                detail: remoteModels.isEmpty ? "等待配置远端模型" : "当前可直接复用的远端入口",
                tint: loadedRemoteModelCount > 0 ? .green : .secondary
            ),
            HubSettingsMetric(
                title: "可执行",
                value: "\(availableRemoteModelCount)",
                detail: remoteModels.isEmpty ? "等待 provider / auth" : "已通过基础执行前置条件",
                tint: availableRemoteModelCount > 0 ? .blue : .secondary
            ),
            HubSettingsMetric(
                title: "执行面",
                value: remoteModelEndpointHostCount == 0 ? "未接入" : "\(remoteModelEndpointHostCount) host",
                detail: remoteModels.isEmpty ? "还没有远端 endpoint" : "启用 \(activeRemoteModelCount) 个入口 · 待补齐 \(needsSetupRemoteModelCount)",
                tint: remoteModelEndpointHostCount > 0 ? .purple : .secondary
            )
        ]
    }

    var remoteModelsAttentionBannerTint: Color {
        if needsSetupRemoteModelCount > 0 {
            return .orange
        }
        if loadedRemoteModelCount > 0 {
            return .green
        }
        return .blue
    }

    var remoteModelsAttentionBannerSystemName: String {
        if needsSetupRemoteModelCount > 0 {
            return "exclamationmark.triangle"
        }
        if loadedRemoteModelCount > 0 {
            return "checkmark.seal"
        }
        return "sparkles"
    }

    private var providerQuotaOperationsImportIssueCount: Int {
        providerKeySnapshot.importSources.filter { source in
            source.state != "ready" || source.lastErrorCount > 0
        }.count
    }

    private var providerQuotaOperationsSummaryText: String {
        let derived = providerKeyDerivedSnapshot
        if derived.totalAccounts == 0
            && providerKeySnapshot.importSources.isEmpty
            && derived.keyPools.isEmpty {
            return "这里管理 provider key、共享额度池、导入源、CLIProxy OAuth 和各类配额台账。按需展开，避免切页时卡住。"
        }

        var parts: [String] = []
        if derived.totalAccounts > 0 {
            parts.append("\(derived.readyAccounts)/\(derived.totalAccounts) 个 key 就绪")
        }
        if quotaPoolCount > 0 {
            parts.append("\(quotaPoolCount) 个额度池")
        }
        if !derived.keyPools.isEmpty {
            parts.append("\(derived.keyPools.count) 个物理池")
        }
        if providerQuotaOperationsImportIssueCount > 0 {
            parts.append("\(providerQuotaOperationsImportIssueCount) 个导入源异常")
        }
        if derived.blockedAccounts > 0 {
            parts.append("\(derived.blockedAccounts) 个 key 阻塞")
        }
        return parts.joined(separator: " · ")
    }

    private var providerQuotaOperationsBadgeText: String {
        let derived = providerKeyDerivedSnapshot
        if !remoteQuotaErrorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "异常"
        }
        if derived.totalAccounts == 0
            && providerKeySnapshot.importSources.isEmpty
            && derived.keyPools.isEmpty {
            return "未配置"
        }
        if derived.blockedAccounts > 0 || providerQuotaOperationsImportIssueCount > 0 {
            return "需处理"
        }
        if derived.readyAccounts > 0 {
            return "\(derived.readyAccounts) 就绪"
        }
        return "按需展开"
    }

    private var providerQuotaOperationsTint: Color {
        let derived = providerKeyDerivedSnapshot
        if !remoteQuotaErrorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .red
        }
        if derived.blockedAccounts > 0 || providerQuotaOperationsImportIssueCount > 0 {
            return .orange
        }
        if derived.readyAccounts > 0 || quotaPoolCount > 0 {
            return .blue
        }
        return .secondary
    }

    private func launchStateLabel(_ state: HubLaunchState?) -> String {
        switch state {
        case .bootStart:
            return HubUIStrings.Settings.Diagnostics.stateBootStart
        case .envValidate:
            return HubUIStrings.Settings.Diagnostics.stateEnvValidate
        case .startGRPCServer, .waitGRPCReady:
            return HubUIStrings.Settings.Diagnostics.statePrepareGRPC
        case .startBridge, .waitBridgeReady:
            return HubUIStrings.Settings.Diagnostics.statePrepareBridge
        case .startRuntime, .waitRuntimeReady:
            return HubUIStrings.Settings.Diagnostics.statePrepareRuntime
        case .serving:
            return HubUIStrings.Settings.Diagnostics.stateServing
        case .degradedServing:
            return HubUIStrings.Settings.Diagnostics.stateDegradedServing
        case .failed:
            return HubUIStrings.Settings.Diagnostics.stateFailed
        case nil:
            return HubUIStrings.Settings.Diagnostics.stateUnknown
        }
    }

    private var currentLaunchStateLabel: String {
        launchStateLabel(hubLaunchStatus?.state)
    }

    private var operatorChannelRuntimeSnapshotText: String {
        guard let snapshot = hubLaunchStatus else {
            return HubUIStrings.Settings.OperatorChannels.snapshotUnavailable
        }
        let updatedText = snapshot.updatedAtMs > 0
            ? formatEpochMs(snapshot.updatedAtMs)
            : HubUIStrings.Settings.OperatorChannels.unknownTime
        return HubUIStrings.Settings.OperatorChannels.snapshotSummary(
            state: launchStateLabel(snapshot.state),
            updatedText: updatedText
        )
    }

    private var operatorChannelReadinessSection: some View {
        Section(HubUIStrings.Settings.OperatorChannels.sectionTitle) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(HubUIStrings.Settings.OperatorChannels.unifiedSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(HubUIStrings.Settings.OperatorChannels.onboardingHint)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(
                        diagnosticsActionIsRunning
                            ? HubUIStrings.Settings.OperatorChannels.restarting
                            : HubUIStrings.Settings.OperatorChannels.restartAndRefresh
                    ) {
                        Task { await restartOperatorChannelRuntimeAndRefresh() }
                    }
                    .disabled(operatorChannelProviderReadinessInFlight || diagnosticsActionIsRunning)
                    .font(.caption)
                    Button(
                        operatorChannelProviderReadinessInFlight
                            ? HubUIStrings.Settings.OperatorChannels.refreshingReadiness
                            : HubUIStrings.Settings.OperatorChannels.refreshReadiness
                    ) {
                        Task { await reloadOperatorChannelProviderReadiness(forceMessage: true) }
                    }
                    .disabled(operatorChannelProviderReadinessInFlight || diagnosticsActionIsRunning)
                    .font(.caption)
                }

                Text(operatorChannelRuntimeSnapshotText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if !operatorChannelProviderReadinessActionText.isEmpty {
                    Text(operatorChannelProviderReadinessActionText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !operatorChannelProviderReadinessError.isEmpty {
                    Text(operatorChannelProviderReadinessError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                ForEach(HubOperatorChannelProviderSetupGuide.supportedProviders, id: \.self) { provider in
                    let readiness = providerReadiness(for: provider)
                    let runtimeStatus = providerRuntimeStatus(for: provider)
                    let guide = HubOperatorChannelProviderSetupGuide.guide(
                        for: provider,
                        readiness: readiness,
                        runtimeStatus: runtimeStatus
                    )
                    operatorChannelReadinessCard(
                        guide: guide,
                        readiness: readiness,
                        runtimeStatus: runtimeStatus,
                        pendingTickets: pendingOnboardingTicketCount(for: provider)
                    )
                }
            }
        }
    }

    private var operatorChannelOnboardingSection: some View {
        Section(HubUIStrings.Settings.OperatorChannels.onboardingSectionTitle) {
            OperatorChannelsOnboardingView()
                .environmentObject(store)
        }
    }

    private var calendarSection: some View {
        Section(HubUIStrings.Settings.Calendar.sectionTitle) {
            LabeledContent(HubUIStrings.Settings.Calendar.status, value: store.calendarStatus)

            Text(HubUIStrings.Settings.Calendar.localAccessHint)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(HubUIStrings.Settings.Calendar.supervisorHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var preferredClientForRepair: HubGRPCClientEntry? {
        if let denied = grpcDeniedAttempts.attempts.first,
           let client = grpc.allowedClients.first(where: { $0.deviceId == denied.deviceId }) {
            return client
        }
        return grpc.allowedClients.first
    }

    @ViewBuilder
    private func firstRunStepRow<Actions: View>(index: Int, title: String, summary: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(HubUIStrings.Settings.numberedItem(index, title: title))
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                actions()
                Spacer()
            }
            .font(.caption)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func quickFixCard<Actions: View>(title: String, summary: String, steps: [String], @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(HubUIStrings.Settings.Troubleshoot.threeSteps)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(steps, id: \.self) { step in
                Text(step)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                actions()
                Spacer()
            }
            .font(.caption)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func operatorChannelReadinessCard(
        guide: HubOperatorChannelProviderSetupGuide,
        readiness: HubOperatorChannelOnboardingDeliveryReadiness?,
        runtimeStatus: HubOperatorChannelProviderRuntimeStatus?,
        pendingTickets: Int
    ) -> some View {
        let flow = guide.firstUseFlow(readiness: readiness, runtimeStatus: runtimeStatus)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(guide.title)
                        .font(.subheadline.weight(.semibold))
                    Text(guide.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                operatorChannelReadinessBadge(readiness)
            }

            Text(guide.statusSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let runtimeStatus {
                let runtimeTint: Color = runtimeStatus.commandEntryReady ? .secondary : .orange
                Text(operatorChannelRuntimeStatusSummary(runtimeStatus))
                    .font(.caption2.monospaced())
                    .foregroundStyle(runtimeTint)
                if !runtimeStatus.lastErrorCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(HubUIStrings.Settings.OperatorChannels.runtimeError(runtimeStatus.lastErrorCode))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.orange)
                }
            }

            if pendingTickets > 0 {
                Text(HubUIStrings.Settings.OperatorChannels.pendingTickets(pendingTickets))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.orange)
            }

            if !guide.checklist.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(HubUIStrings.Settings.OperatorChannels.minimalChecklistTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(guide.checklist) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.key)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            Text(item.note)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !guide.nextStep.isEmpty {
                Text(HubUIStrings.Settings.OperatorChannels.nextStep(guide.nextStep))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            OperatorChannelFirstUseFlowView(flow: flow)

            if !guide.liveTestSteps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(HubUIStrings.Settings.OperatorChannels.liveTestTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(Array(guide.liveTestSteps.enumerated()), id: \.offset) { index, step in
                        Text(HubUIStrings.Settings.numberedItem(index + 1, title: step))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !guide.securityNotes.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(HubUIStrings.Settings.OperatorChannels.securityNotesTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(Array(guide.securityNotes.enumerated()), id: \.offset) { _, note in
                        Text(HubUIStrings.Settings.OperatorChannels.securityNoteBullet(note))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 10) {
                Button(HubUIStrings.Settings.OperatorChannels.copySetupPack) {
                    copyOperatorChannelSetupPack(guide, flow: flow)
                }
                .font(.caption)
                Spacer()
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func operatorChannelReadinessBadge(_ readiness: HubOperatorChannelOnboardingDeliveryReadiness?) -> some View {
        let title: String
        let tint: Color
        if let readiness {
            if readiness.ready {
                title = HubUIStrings.Settings.OperatorChannels.readyBadge
                tint = .green
            } else if !readiness.replyEnabled {
                title = HubUIStrings.Settings.OperatorChannels.disabledBadge
                tint = .orange
            } else if !readiness.credentialsConfigured {
                title = HubUIStrings.Settings.OperatorChannels.needsConfigBadge
                tint = .orange
            } else {
                title = HubUIStrings.Settings.OperatorChannels.blockedBadge
                tint = .red
            }
        } else {
            title = HubUIStrings.Settings.OperatorChannels.unknownBadge
            tint = .secondary
        }
        return Text(title)
            .font(.caption.monospaced())
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    private func providerReadiness(for provider: String) -> HubOperatorChannelOnboardingDeliveryReadiness? {
        operatorChannelProviderReadiness.first { row in
            row.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == provider
        }
    }

    private func providerRuntimeStatus(for provider: String) -> HubOperatorChannelProviderRuntimeStatus? {
        operatorChannelProviderRuntimeStatus.first { row in
            row.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == provider
        }
    }

    private func operatorChannelRuntimeStatusSummary(_ row: HubOperatorChannelProviderRuntimeStatus) -> String {
        let runtimeState = row.runtimeState.trimmingCharacters(in: .whitespacesAndNewlines)
        let commandEntry = row.commandEntryReady
            ? HubUIStrings.Settings.OperatorChannels.readyStatus
            : HubUIStrings.Settings.OperatorChannels.blockedStatus
        let delivery = row.deliveryReady
            ? HubUIStrings.Settings.OperatorChannels.readyStatus
            : HubUIStrings.Settings.OperatorChannels.blockedStatus
        return HubUIStrings.Settings.OperatorChannels.runtimeStatusSummary(
            runtimeState: runtimeState.isEmpty ? HubUIStrings.Settings.OperatorChannels.unknown : runtimeState,
            commandEntry: commandEntry,
            delivery: delivery
        )
    }

    private func pendingOnboardingTicketCount(for provider: String) -> Int {
        let normalized = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.pendingOperatorChannelOnboardingTickets.filter { ticket in
            ticket.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized && ticket.isOpen
        }.count
    }

    private func copyOperatorChannelSetupPack(_ guide: HubOperatorChannelProviderSetupGuide, flow: HubOperatorChannelFirstUseFlow) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(guide.setupPackText(flow: flow), forType: .string)
        operatorChannelProviderReadinessActionText = HubUIStrings.Settings.OperatorChannels.copiedSetupPack(guide.title)
    }

    private func reloadOperatorChannelProviderReadiness(forceMessage: Bool = false) async {
        if operatorChannelProviderReadinessInFlight { return }
        operatorChannelProviderReadinessInFlight = true
        defer { operatorChannelProviderReadinessInFlight = false }
        do {
            async let readinessRows = OperatorChannelsOnboardingHTTPClient.listProviderReadiness(
                adminToken: grpc.localAdminToken(),
                grpcPort: grpc.port
            )
            async let runtimeRows = OperatorChannelsOnboardingHTTPClient.listProviderRuntimeStatus(
                adminToken: grpc.localAdminToken(),
                grpcPort: grpc.port
            )
            let (rows, runtimeStatusRows) = try await (readinessRows, runtimeRows)
            operatorChannelProviderReadiness = rows
            operatorChannelProviderRuntimeStatus = runtimeStatusRows
            operatorChannelProviderReadinessError = ""
            persistOperatorChannelDoctorReport(
                readinessRows: rows,
                runtimeRows: runtimeStatusRows,
                sourceStatus: "ok",
                fetchErrors: []
            )
            if forceMessage {
                operatorChannelProviderReadinessActionText = HubUIStrings.Settings.OperatorChannels.refreshedStatus
            }
        } catch {
            let errorDescription = (error as NSError).localizedDescription
            operatorChannelProviderReadiness = []
            operatorChannelProviderRuntimeStatus = []
            operatorChannelProviderReadinessError = errorDescription
            persistOperatorChannelDoctorReport(
                readinessRows: [],
                runtimeRows: [],
                sourceStatus: "unavailable",
                fetchErrors: [errorDescription]
            )
        }
    }

    private func persistOperatorChannelDoctorReport(
        readinessRows: [HubOperatorChannelOnboardingDeliveryReadiness],
        runtimeRows: [HubOperatorChannelProviderRuntimeStatus],
        sourceStatus: String,
        fetchErrors: [String]
    ) {
        let grpcPort = grpc.port
        let adminBaseURL = grpcPort > 0
            ? "http://127.0.0.1:\(OperatorChannelsOnboardingHTTPClient.pairingPort(grpcPort: grpcPort))"
            : ""
        Task.detached(priority: .utility) {
            XHubDoctorOutputStore.writeHubChannelOnboardingReadinessReport(
                readinessRows: readinessRows,
                runtimeRows: runtimeRows,
                sourceStatus: sourceStatus,
                fetchErrors: fetchErrors,
                adminBaseURL: adminBaseURL,
                surface: .hubUI
            )
        }
    }

    @MainActor
    private func restartOperatorChannelRuntimeAndRefresh() async {
        if diagnosticsActionIsRunning {
            operatorChannelProviderReadinessActionText = HubUIStrings.Settings.OperatorChannels.restartInProgress
            return
        }

        operatorChannelProviderReadinessActionText = HubUIStrings.Settings.OperatorChannels.restartingComponents
        await restartComponentsForDiagnosticsAsync()
        try? await Task.sleep(nanoseconds: 900_000_000)
        hubLaunchStatus = HubLaunchStatusStorage.load()
        await reloadOperatorChannelProviderReadiness(forceMessage: false)

        if operatorChannelProviderReadinessError.isEmpty {
            operatorChannelProviderReadinessActionText = HubUIStrings.Settings.OperatorChannels.restartedAndUpdated
        } else {
            operatorChannelProviderReadinessActionText = HubUIStrings.Settings.OperatorChannels.restartCompletedRefreshFailed
        }
    }

    var terminalAccessSortedKeys: [HubTerminalAccessKey] {
        terminalAccessKeys.sorted { left, right in
            if left.updatedAtMs != right.updatedAtMs {
                return left.updatedAtMs > right.updatedAtMs
            }
            if left.createdAtMs != right.createdAtMs {
                return left.createdAtMs > right.createdAtMs
            }
            return left.resolvedName.localizedCaseInsensitiveCompare(right.resolvedName) == .orderedAscending
        }
    }

    var terminalAccessReadyCount: Int {
        terminalAccessKeys.filter { $0.status.lowercased() == "ready" }.count
    }

    var terminalAccessCurrentBaseURL: String {
        if let resolved = terminalAccessKeys
            .compactMap({ $0.openAICompat?.baseURL.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return resolved
        }
        let host = (grpc.xtTerminalInternetHost ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedHost = host.isEmpty ? "127.0.0.1" : host
        let pairingPort = TerminalAccessKeyHTTPClient.pairingPort(grpcPort: grpc.port)
        if resolvedHost.contains(":") {
            return "http://\(resolvedHost)/v1"
        }
        return "http://\(resolvedHost):\(pairingPort)/v1"
    }

    var terminalAccessSectionSummaryText: String {
        let blocked = max(0, terminalAccessKeys.count - terminalAccessReadyCount)
        let baseURL = terminalAccessCurrentBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return "keys \(terminalAccessKeys.count) • ready \(terminalAccessReadyCount) • blocked \(blocked) • daily quota \(terminalAccessIntText(terminalAccessOverviewQuotaTotal)) • \(baseURL)"
    }

    var terminalAccessOverviewQuotaTotal: Int64 {
        terminalAccessSortedKeys.reduce(Int64(0)) { partialResult, item in
            partialResult + terminalAccessQuotaLimit(for: item, deviceStatus: terminalAccessDeviceStatus(for: item))
        }
    }

    var terminalAccessOverviewUsedTotal: Int64 {
        terminalAccessSortedKeys.reduce(Int64(0)) { partialResult, item in
            partialResult + terminalAccessQuotaUsed(deviceStatus: terminalAccessDeviceStatus(for: item))
        }
    }

    var terminalAccessOverviewRemainingTotal: Int64 {
        terminalAccessSortedKeys.reduce(Int64(0)) { partialResult, item in
            let status = terminalAccessDeviceStatus(for: item)
            let limit = terminalAccessQuotaLimit(for: item, deviceStatus: status)
            let used = terminalAccessQuotaUsed(deviceStatus: status)
            return partialResult + terminalAccessQuotaRemaining(limit: limit, used: used, deviceStatus: status)
        }
    }

    var terminalAccessPendingRevokeAccessKey: HubTerminalAccessKey? {
        terminalAccessKeys.first { $0.accessKeyID == terminalAccessPendingRevokeAccessKeyID }
    }

    var terminalAccessRevokeDialogPresented: Binding<Bool> {
        Binding(
            get: { !terminalAccessPendingRevokeAccessKeyID.isEmpty },
            set: { presented in
                if !presented {
                    terminalAccessPendingRevokeAccessKeyID = ""
                }
            }
        )
    }

    func terminalAccessBaseURL(for accessKey: HubTerminalAccessKey) -> String {
        accessKey.openAICompat?.baseURL.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func terminalAccessStatusTint(_ accessKey: HubTerminalAccessKey) -> Color {
        switch accessKey.status.lowercased() {
        case "ready":
            return .green
        case "revoked":
            return .red
        case "expired", "disabled":
            return .orange
        default:
            return .blue
        }
    }

    func terminalAccessStatusIcon(_ accessKey: HubTerminalAccessKey) -> String {
        switch accessKey.status.lowercased() {
        case "ready":
            return "checkmark.shield.fill"
        case "revoked":
            return "xmark.shield.fill"
        case "expired":
            return "clock.badge.exclamationmark.fill"
        case "disabled":
            return "pause.circle.fill"
        default:
            return "key.fill"
        }
    }

    func terminalAccessSecretEnvelope(for accessKey: HubTerminalAccessKey) -> HubTerminalAccessKeySecretEnvelope? {
        guard let lastSecret = terminalAccessLastSecret else { return nil }
        return lastSecret.accessKey.accessKeyID == accessKey.accessKeyID ? lastSecret : nil
    }

    func terminalAccessDeliveryPack(for accessKey: HubTerminalAccessKey) -> HubTerminalAccessDeliveryPack {
        if let secret = terminalAccessSecretEnvelope(for: accessKey) {
            return secret.deliveryPack
        }
        return accessKey.deliveryPack()
    }

    func terminalAccessExampleText(for deliveryPack: HubTerminalAccessDeliveryPack) -> String {
        switch terminalAccessExampleKind {
        case .shell:
            return deliveryPack.shellExports
        case .python:
            return deliveryPack.pythonSnippet
        case .node:
            return deliveryPack.nodeSnippet
        case .curl:
            return deliveryPack.curlCommand
        }
    }

    func terminalAccessDeviceStatus(for accessKey: HubTerminalAccessKey) -> GRPCDeviceStatusEntry? {
        grpcDevicesStatus.devices.first { row in
            row.deviceId.trimmingCharacters(in: .whitespacesAndNewlines) == accessKey.deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func terminalAccessQuotaLimit(
        for accessKey: HubTerminalAccessKey,
        deviceStatus: GRPCDeviceStatusEntry?
    ) -> Int64 {
        let snapshotLimit = max(0, deviceStatus?.dailyTokenLimit ?? 0)
        if snapshotLimit > 0 {
            return snapshotLimit
        }
        return Int64(max(0, accessKey.dailyTokenLimit))
    }

    func terminalAccessQuotaUsed(deviceStatus: GRPCDeviceStatusEntry?) -> Int64 {
        max(0, deviceStatus?.dailyTokenUsed ?? 0)
    }

    func terminalAccessQuotaRemaining(
        limit: Int64,
        used: Int64,
        deviceStatus: GRPCDeviceStatusEntry?
    ) -> Int64 {
        let explicitRemaining = max(
            max(0, deviceStatus?.remainingDailyTokenBudget ?? 0),
            max(0, deviceStatus?.dailyTokenRemaining ?? 0)
        )
        if explicitRemaining > 0 || (deviceStatus != nil && used > 0) {
            return explicitRemaining
        }
        if limit <= 0 {
            return 0
        }
        return max(0, limit - used)
    }

    func terminalAccessSummaryLine(_ accessKey: HubTerminalAccessKey, quotaLimit: Int64) -> String {
        let paidModelText = accessKey.paidModelSelectionMode == .off ? "paid off" : "paid on"
        let webFetchText = accessKey.defaultWebFetchEnabled ? "web.fetch on" : "web.fetch off"
        let userText = accessKey.userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "anonymous" : accessKey.userID
        return [
            "user \(userText)",
            "quota \(terminalAccessIntText(quotaLimit))/day",
            paidModelText,
            webFetchText,
            accessKey.tokenRedacted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : accessKey.tokenRedacted,
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
    }

    func terminalAccessLiveUsageLine(_ deviceStatus: GRPCDeviceStatusEntry) -> String {
        let topModel = deviceStatus.topModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let topModelSuffix = topModel.isEmpty ? "" : " • top \(topModel)"
        return [
            deviceStatus.connected ? "connected" : "offline",
            "requests \(deviceStatus.requestsToday)",
            "blocked \(deviceStatus.blockedToday)",
            "remaining \(terminalAccessIntText(max(0, deviceStatus.remainingDailyTokenBudget)))",
        ].joined(separator: " • ") + topModelSuffix
    }

    func terminalAccessIntText(_ value: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: NSNumber(value: max(0, value))) ?? String(max(0, value))
    }

    func terminalAccessIntegerFormatter(minimum: Int, maximum: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.allowsFloats = false
        formatter.minimum = NSNumber(value: minimum)
        formatter.maximum = NSNumber(value: maximum)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }

    func terminalAccessCopyToPasteboard(_ text: String, successText: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)
        terminalAccessErrorText = ""
        terminalAccessActionText = successText
    }

    @MainActor
    private func ensureTerminalAccessGatewayReady() async throws {
        let firstHealth = await TerminalAccessKeyHTTPClient.gatewayHealth(grpcPort: grpc.port)
        if firstHealth?.isPairingGateway == true {
            return
        }
        if let firstHealth {
            let endpoint = TerminalAccessKeyHTTPClient.gatewayBaseURLText(grpcPort: grpc.port)
            throw TerminalAccessKeyHTTPClient.ClientError.gatewayUnavailable(
                message: "普通 Terminal Gateway 端口不正确：\(endpoint)/health 返回 \(firstHealth.diagnosticSummary)，不是 service=pairing。请不要把普通 terminal URL 指到 Rust kernel 的 HTTP 端口。"
            )
        }

        grpc.restart()
        var lastHealth: TerminalAccessGatewayHealth? = nil
        for _ in 0..<8 {
            try await Task.sleep(nanoseconds: 350_000_000)
            let health = await TerminalAccessKeyHTTPClient.gatewayHealth(grpcPort: grpc.port)
            lastHealth = health
            if health?.isPairingGateway == true {
                return
            }
        }

        let endpoint = TerminalAccessKeyHTTPClient.gatewayBaseURLText(grpcPort: grpc.port)
        let observed = lastHealth?.diagnosticSummary ?? "no response"
        let message = """
        普通 Terminal Gateway 还没有就绪：\(endpoint)/health 返回 \(observed)。这通常说明 Node pairing gateway 没启动，或当前端口指到了 Rust kernel。请先在 Hub 设置里重启 gRPC/Pairing sidecar，再重新签发；系统不会返回一个会 404/not_found 的 Key + URL。
        """
        throw TerminalAccessKeyHTTPClient.ClientError.gatewayUnavailable(message: message)
    }

    @MainActor
    func reloadTerminalAccessKeys(forceMessage: Bool = false) async {
        if terminalAccessReloadInFlight { return }
        terminalAccessReloadInFlight = true
        defer { terminalAccessReloadInFlight = false }

        do {
            try await ensureTerminalAccessGatewayReady()
            let rows = try await TerminalAccessKeyHTTPClient.list(
                adminToken: grpc.localAdminToken(),
                grpcPort: grpc.port
            )
            terminalAccessKeys = rows
            rebuildRemoteQuotaProjectionSnapshot()
            terminalAccessErrorText = ""
            if forceMessage {
                terminalAccessActionText = "已刷新普通 terminal access key 列表。"
            }
        } catch {
            terminalAccessErrorText = error.localizedDescription
            if forceMessage {
                terminalAccessActionText = ""
            }
        }
    }

    @MainActor
    func issueTerminalAccessKey() async {
        if terminalAccessMutationInFlight { return }
        terminalAccessMutationInFlight = true
        defer { terminalAccessMutationInFlight = false }

        do {
            try await ensureTerminalAccessGatewayReady()
            let secret = try await TerminalAccessKeyHTTPClient.issue(
                draft: terminalAccessDraft,
                adminToken: grpc.localAdminToken(),
                grpcPort: grpc.port
            )
            terminalAccessLastSecret = secret
            terminalAccessIssueExpanded = false
            terminalAccessLastSecretExpanded = true
            terminalAccessErrorText = ""
            terminalAccessActionText = "已签发 \(secret.accessKey.resolvedName)，已返回普通 terminal 的 URL + API key。"
            await reloadTerminalAccessKeys(forceMessage: false)
        } catch {
            terminalAccessErrorText = error.localizedDescription
        }
    }

    @MainActor
    func rotateTerminalAccessKey(_ accessKey: HubTerminalAccessKey) async {
        if terminalAccessMutationInFlight { return }
        terminalAccessMutationInFlight = true
        defer { terminalAccessMutationInFlight = false }

        do {
            try await ensureTerminalAccessGatewayReady()
            let secret = try await TerminalAccessKeyHTTPClient.rotate(
                accessKeyID: accessKey.accessKeyID,
                note: accessKey.note,
                adminToken: grpc.localAdminToken(),
                grpcPort: grpc.port
            )
            terminalAccessLastSecret = secret
            terminalAccessLastSecretExpanded = true
            terminalAccessErrorText = ""
            terminalAccessActionText = "已轮换 \(secret.accessKey.resolvedName)，新的普通 terminal API key 已返回。"
            await reloadTerminalAccessKeys(forceMessage: false)
        } catch {
            terminalAccessErrorText = error.localizedDescription
        }
    }

    @MainActor
    private func setTerminalAccessKeyDailyBudget(
        _ accessKey: HubTerminalAccessKey,
        dailyTokenLimit: Int
    ) async {
        guard accessKey.supportsDirectBudgetAdjustment else {
            let message = "普通 terminal 预算设定只支持启用新策略档案且未撤销的 access key。"
            terminalAccessActionText = ""
            terminalAccessErrorText = message
            remoteQuotaActionText = ""
            remoteQuotaErrorText = message
            return
        }
        if terminalAccessMutationInFlight { return }

        let updatedLimit = max(1, dailyTokenLimit)

        terminalAccessMutationInFlight = true
        defer { terminalAccessMutationInFlight = false }

        do {
            try await ensureTerminalAccessGatewayReady()
            let updated = try await TerminalAccessKeyHTTPClient.updateDailyBudget(
                accessKeyID: accessKey.accessKeyID,
                dailyTokenLimit: updatedLimit,
                note: accessKey.note,
                adminToken: grpc.localAdminToken(),
                grpcPort: grpc.port
            )

            if let index = terminalAccessKeys.firstIndex(where: { $0.accessKeyID == updated.accessKeyID }) {
                terminalAccessKeys[index] = updated
            }
            if let secret = terminalAccessLastSecret,
               secret.accessKey.accessKeyID == updated.accessKeyID {
                terminalAccessLastSecret = HubTerminalAccessKeySecretEnvelope(
                    clientToken: secret.clientToken,
                    accessKey: updated
                )
            }

            let actionText = "\(updated.resolvedName) 日预算已调整为 \(terminalAccessIntText(Int64(updated.dailyTokenLimit))) tokens。"
            terminalAccessErrorText = ""
            terminalAccessActionText = actionText
            remoteQuotaErrorText = ""
            remoteQuotaActionText = actionText
            await reloadTerminalAccessKeys(forceMessage: false)
        } catch {
            let message = error.localizedDescription
            terminalAccessActionText = ""
            terminalAccessErrorText = message
            remoteQuotaActionText = ""
            remoteQuotaErrorText = message
        }
    }

    @MainActor
    func adjustTerminalAccessKeyDailyBudget(
        _ accessKey: HubTerminalAccessKey,
        delta: Int
    ) async {
        let currentLimit = max(1, accessKey.dailyTokenLimit)
        let updatedLimit = max(1, currentLimit + delta)
        guard updatedLimit != currentLimit else { return }
        await setTerminalAccessKeyDailyBudget(accessKey, dailyTokenLimit: updatedLimit)
    }

    func presentRemoteQuotaBudgetEditor(
        _ consumer: RemoteQuotaCenterClientProjection
    ) {
        guard providerKeyCanQuickAdjustBudget(consumer) else {
            remoteQuotaActionText = ""
            remoteQuotaErrorText = "当前消费者还不支持精确设预算。"
            return
        }
        remoteQuotaBudgetEditorTarget = RemoteQuotaBudgetEditorTarget(
            consumerKind: consumer.consumerKind,
            referenceID: consumer.referenceID,
            title: consumer.name,
            subtitle: providerKeyBudgetClientReferenceSummary(consumer),
            currentDailyTokenLimit: max(1, Int(consumer.dailyTokenLimit)),
            todayUsed: consumer.dailyTokenUsed
        )
    }

    func presentRemoteQuotaBudgetEditor(
        _ accessKey: HubTerminalAccessKey
    ) {
        guard accessKey.supportsDirectBudgetAdjustment else {
            remoteQuotaActionText = ""
            remoteQuotaErrorText = "当前 terminal access key 还不支持精确设预算。"
            return
        }
        let subtitle = [
            "key \(accessKey.accessKeyID)",
            accessKey.userID.isEmpty ? "" : "user \(accessKey.userID)",
            accessKey.appID.isEmpty ? "" : "app \(accessKey.appID)",
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " • ")
        remoteQuotaBudgetEditorTarget = RemoteQuotaBudgetEditorTarget(
            consumerKind: .terminalAccess,
            referenceID: accessKey.accessKeyID,
            title: accessKey.resolvedName,
            subtitle: subtitle,
            currentDailyTokenLimit: max(1, accessKey.dailyTokenLimit),
            todayUsed: Int64(max(0, terminalAccessQuotaUsed(deviceStatus: terminalAccessDeviceStatus(for: accessKey))))
        )
    }

    private func applyRemoteQuotaBudgetEdit(
        _ target: RemoteQuotaBudgetEditorTarget,
        dailyTokenLimit: Int
    ) {
        let updatedLimit = max(1, dailyTokenLimit)
        guard let consumer = remoteQuotaProjection.consumers.first(where: {
            $0.consumerKind == target.consumerKind && $0.referenceID == target.referenceID
        }) else {
            remoteQuotaActionText = ""
            remoteQuotaErrorText = "目标消费者已刷新，请重新打开预算设置。"
            return
        }

        if let client = consumer.grpcClient {
            grpcSetDailyBudget(client, dailyTokenLimit: updatedLimit)
            return
        }
        guard let accessKey = consumer.terminalAccessKey else {
            remoteQuotaActionText = ""
            remoteQuotaErrorText = "当前 terminal access key 无法定位，请刷新后重试。"
            return
        }
        Task { await setTerminalAccessKeyDailyBudget(accessKey, dailyTokenLimit: updatedLimit) }
    }

    @MainActor
    func revokeTerminalAccessKey(_ accessKey: HubTerminalAccessKey) async {
        if terminalAccessMutationInFlight { return }
        terminalAccessMutationInFlight = true
        defer { terminalAccessMutationInFlight = false }

        do {
            try await ensureTerminalAccessGatewayReady()
            _ = try await TerminalAccessKeyHTTPClient.revoke(
                accessKeyID: accessKey.accessKeyID,
                note: "revoked from hub settings",
                adminToken: grpc.localAdminToken(),
                grpcPort: grpc.port
            )
            if terminalAccessLastSecret?.accessKey.accessKeyID == accessKey.accessKeyID {
                terminalAccessLastSecret = nil
                terminalAccessLastSecretExpanded = false
            }
            terminalAccessPendingRevokeAccessKeyID = ""
            terminalAccessErrorText = ""
            terminalAccessActionText = "已撤销 \(accessKey.resolvedName)。"
            await reloadTerminalAccessKeys(forceMessage: false)
        } catch {
            terminalAccessPendingRevokeAccessKeyID = ""
            terminalAccessErrorText = error.localizedDescription
        }
    }

    private var diagnosticsSection: some View {
        Section(HubUIStrings.Settings.Diagnostics.sectionTitle) {
            let snap = hubLaunchStatus
            let primary = HubLaunchStatusStorage.url()
            let fallback = URL(fileURLWithPath: "/tmp/RELFlowHub", isDirectory: true).appendingPathComponent(HubLaunchStatusStorage.fileName)
            let histPrimary = HubLaunchHistoryStorage.url()
            let histFallback = URL(fileURLWithPath: "/tmp/RELFlowHub", isDirectory: true).appendingPathComponent(HubLaunchHistoryStorage.fileName)

            HStack {
                Text(HubUIStrings.Settings.Diagnostics.launchStatus)
                Spacer()
                Text(currentLaunchStateLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let snap, snap.updatedAtMs > 0 {
                HStack {
                    Text(HubUIStrings.Settings.Diagnostics.lastUpdated)
                    Spacer()
                    Text(formatEpochMs(snap.updatedAtMs))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let id = snap?.launchId.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
                HStack {
                    Text(HubUIStrings.Settings.Diagnostics.launchID)
                    Spacer()
                    Text(id)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }

            let rootCauseText = renderRootCauseText(snap?.rootCause)
            if !rootCauseText.isEmpty {
                Text(HubUIStrings.Settings.Diagnostics.rootCauseTitle)
                    .font(.caption.weight(.semibold))
                Text(rootCauseText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text(HubUIStrings.Settings.Diagnostics.rootCauseEmpty)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            let blocked = snap?.degraded.blockedCapabilities ?? []
            if !blocked.isEmpty {
                Text(HubUIStrings.Settings.Diagnostics.blockedCapabilitiesTitle)
                    .font(.caption.weight(.semibold))
                Text(blocked.joined(separator: "\n"))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text(HubUIStrings.Settings.Diagnostics.blockedCapabilitiesEmpty)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup(HubUIStrings.Settings.Diagnostics.providersDisclosure) {
                if !store.aiRuntimeDoctorSummaryText.isEmpty {
                    Text(store.aiRuntimeDoctorSummaryText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Text(
                    store.aiRuntimeProviderSummaryText.isEmpty
                        ? HubUIStrings.Settings.Diagnostics.providerSummaryUnavailable
                        : store.aiRuntimeProviderSummaryText
                )
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                HStack(spacing: 10) {
                    Button(HubUIStrings.Settings.Diagnostics.copyProviderSummary) {
                        copyLocalProviderSummaryToClipboard(snapshot: snap)
                    }
                    Button(HubUIStrings.Settings.Diagnostics.openRuntimeLog) {
                        store.openAIRuntimeLog()
                    }
                    Spacer()
                }
                .font(.caption)
            }

            HStack(spacing: 10) {
                Button(
                    diagnosticsActionIsRunning
                        ? HubUIStrings.Settings.Diagnostics.actionInProgress
                        : HubUIStrings.Settings.Diagnostics.retryLaunch
                ) {
                    retryLaunchDiagnosis()
                }
                .disabled(diagnosticsActionIsRunning || fixNowIsRunning)

                Button(HubUIStrings.Settings.Diagnostics.restartComponents) {
                    restartComponentsForDiagnostics()
                }
                .disabled(diagnosticsActionIsRunning || fixNowIsRunning)

                Button(HubUIStrings.Settings.Diagnostics.resetVolatileCaches) {
                    resetVolatileCachesForDiagnostics()
                }
                .disabled(diagnosticsActionIsRunning || fixNowIsRunning)

                Spacer()
            }
            .font(.caption)

            HStack(spacing: 10) {
                Button(HubUIStrings.Settings.Diagnostics.repairDBSafe) {
                    repairDBSafeForDiagnostics()
                }
                .disabled(diagnosticsActionIsRunning || fixNowIsRunning)
                Spacer()
            }
            .font(.caption)

            if !diagnosticsActionErrorText.isEmpty {
                Text(diagnosticsActionErrorText)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if !diagnosticsActionResultText.isEmpty {
                Text(diagnosticsActionResultText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if !hubLaunchHistory.launches.isEmpty {
                DisclosureGroup(HubUIStrings.Settings.Diagnostics.launchHistoryDisclosure) {
                    HStack(spacing: 10) {
                        Button(HubUIStrings.Settings.Diagnostics.copyHistory) {
                            copyLaunchHistoryToClipboard(snapshot: hubLaunchHistory)
                        }
                        Button(HubUIStrings.Settings.Diagnostics.openHistoryFile) {
                            openLaunchStatusFile(primary: histPrimary, fallback: histFallback)
                        }
                        Spacer()
                    }
                    .font(.caption)

                    Text(renderLaunchHistory(hubLaunchHistory.launches))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            let fixAction = recommendedFixAction(snapshot: snap)
            let fixSummary = fixAction?.summary ?? ""
            if !fixSummary.isEmpty {
                HStack(spacing: 10) {
                    Button(
                        fixNowIsRunning
                            ? HubUIStrings.Settings.Diagnostics.fixingInProgress
                            : HubUIStrings.Settings.Diagnostics.fixNow
                    ) {
                        fixNow(snapshot: snap)
                    }
                    .disabled(fixNowIsRunning || diagnosticsActionIsRunning)
                    if fixAction == .restartRuntime || fixAction == .clearPythonAndRestartRuntime || fixAction == .unlockRuntimeLockHolders {
                        Button(HubUIStrings.Settings.Diagnostics.openRuntimeLog) {
                            store.openAIRuntimeLog()
                        }
                    }
                    if fixAction == .unlockRuntimeLockHolders {
                        Button(
                            fixNowIsRunning
                                ? HubUIStrings.Settings.Diagnostics.fixingInProgress
                                : HubUIStrings.Settings.Diagnostics.runLsofKill
                        ) {
                            runLsofKillAndRestart()
                        }
                        .disabled(fixNowIsRunning || diagnosticsActionIsRunning)
                        Button(HubUIStrings.Settings.Diagnostics.copyLsofKill) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(store.aiRuntimeLockKillCommandHint(), forType: .string)
                        }
                    }
                    Text(fixSummary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .font(.caption)

                if !fixNowErrorText.isEmpty {
                    Text(fixNowErrorText)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                } else if !fixNowResultText.isEmpty {
                    Text(fixNowResultText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            HStack(spacing: 10) {
                Button(HubUIStrings.Settings.Diagnostics.copyRootCauseAndBlocked) {
                    copyLaunchRootCauseAndBlockedToClipboard(snapshot: snap)
                }
                Button(HubUIStrings.Settings.Diagnostics.openFile) {
                    openLaunchStatusFile(primary: primary, fallback: fallback)
                }
                Spacer()
            }
            .font(.caption)

            HStack(spacing: 10) {
                Button(
                    diagnosticsBundleIsExporting
                        ? HubUIStrings.Settings.Diagnostics.exportInProgress
                        : HubUIStrings.Settings.Diagnostics.exportBundle
                ) {
                    exportDiagnosticsBundle()
                }
                .disabled(diagnosticsBundleIsExporting)

                if !diagnosticsBundleArchivePath.isEmpty {
                    Button(HubUIStrings.Settings.Diagnostics.revealInFinder) {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: diagnosticsBundleArchivePath)])
                    }
                    Button(HubUIStrings.Settings.Diagnostics.copyPath) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(diagnosticsBundleArchivePath, forType: .string)
                    }
                    Button(HubUIStrings.Settings.Diagnostics.copyIssueSummary) {
                        copyIssueSnippetToClipboard(snapshot: snap)
                    }
                }
                Spacer()
            }
            .font(.caption)

            if !diagnosticsBundleError.isEmpty {
                Text(diagnosticsBundleError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if !diagnosticsBundleArchivePath.isEmpty {
                Text(diagnosticsBundleArchivePath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text(HubUIStrings.Settings.Diagnostics.bundleHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button(
                    unifiedDoctorReportIsExporting
                        ? HubUIStrings.Settings.Diagnostics.exportInProgress
                        : HubUIStrings.Settings.Diagnostics.exportUnifiedReport
                ) {
                    exportUnifiedDoctorReport()
                }
                .disabled(unifiedDoctorReportIsExporting)

                if !unifiedDoctorRevealURLs().isEmpty {
                    Button(HubUIStrings.Settings.Diagnostics.revealInFinder) {
                        NSWorkspace.shared.activateFileViewerSelecting(unifiedDoctorRevealURLs())
                    }
                    Button(HubUIStrings.Settings.Diagnostics.copyPath) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(unifiedDoctorReportSummaryForClipboard(), forType: .string)
                    }
                }
                Spacer()
            }
            .font(.caption)

            if !unifiedDoctorReportError.isEmpty {
                Text(unifiedDoctorReportError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if !unifiedDoctorReportPath.isEmpty || !unifiedDoctorChannelReportPath.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    let companionPaths = self.hubDoctorCompanionPaths(for: unifiedDoctorReportPath)
                    Text(HubUIStrings.Settings.Diagnostics.companionFiles(
                        runtimeReportPath: unifiedDoctorReportPath.isEmpty ? HubUIStrings.Settings.Diagnostics.missingField : unifiedDoctorReportPath,
                        snapshotPath: companionPaths.snapshotPath,
                        recoveryGuidancePath: companionPaths.recoveryGuidancePath,
                        channelOnboardingPath: unifiedDoctorChannelReportPath.isEmpty ? HubUIStrings.Settings.Diagnostics.missingField : unifiedDoctorChannelReportPath
                    ))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                }
            } else {
                Text(HubUIStrings.Settings.Diagnostics.unifiedReportHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !diagnosticsBundleMissingFiles.isEmpty {
                DisclosureGroup(HubUIStrings.Settings.Diagnostics.missingFilesDisclosure) {
                    Text(diagnosticsBundleMissingFiles.joined(separator: "\n"))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            DisclosureGroup(HubUIStrings.Settings.Diagnostics.pathsDisclosure) {
                Text(pathLine(HubUIStrings.Settings.Diagnostics.primaryPath, url: primary))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(pathLine(HubUIStrings.Settings.Diagnostics.fallbackPath, url: fallback))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(pathLine(HubUIStrings.Settings.Diagnostics.historyPath, url: histPrimary))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(pathLine(HubUIStrings.Settings.Diagnostics.historyFallbackPath, url: histFallback))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let snap, !snap.steps.isEmpty {
                DisclosureGroup(HubUIStrings.Settings.Diagnostics.stepsDisclosure) {
                    Text(renderLaunchSteps(snap.steps))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    func formatEpochMs(_ ms: Int64) -> String {
        let d = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        let f = DateFormatter()
        f.dateFormat = HubUIStrings.Formatting.dateTimeWithSeconds
        return f.string(from: d)
    }

    private func renderRootCauseText(_ rc: HubLaunchRootCause?) -> String {
        guard let rc else { return "" }
        return HubUIStrings.Settings.Diagnostics.rootCauseSummary(
            component: rc.component.rawValue,
            code: rc.errorCode,
            detail: rc.detail
        )
    }

    private func renderLaunchHistory(_ launches: [HubLaunchStatusSnapshot], limit: Int = 12) -> String {
        let maxN = max(1, min(50, limit))
        let rows = launches.prefix(maxN).map { s in
            let ts = s.updatedAtMs > 0 ? formatEpochMs(s.updatedAtMs) : HubUIStrings.Settings.Diagnostics.unknownTime
            let state = s.state.rawValue
            let degraded = s.degraded.isDegraded ? "1" : "0"
            let id = s.launchId.trimmingCharacters(in: .whitespacesAndNewlines)
            let root = renderRootCauseText(s.rootCause).replacingOccurrences(of: "\n", with: " | ")
            let rootText = root.isEmpty ? HubUIStrings.Settings.Diagnostics.noneField : root
            let blocked = s.degraded.blockedCapabilities
            let blockedText = blocked.isEmpty ? HubUIStrings.Settings.Diagnostics.noneField : blocked.joined(separator: ",")
            return HubUIStrings.Settings.Diagnostics.launchHistoryEntry(
                timestamp: ts,
                state: state,
                degraded: degraded,
                launchID: id,
                root: rootText,
                blocked: blockedText
            )
        }
        return rows.joined(separator: HubUIStrings.Settings.Diagnostics.launchHistorySeparator)
    }

    private func copyLaunchHistoryToClipboard(snapshot: HubLaunchHistorySnapshot) {
        let updated = snapshot.updatedAtMs > 0 ? formatEpochMs(snapshot.updatedAtMs) : HubUIStrings.Settings.Diagnostics.unknownTime
        let header = HubUIStrings.Settings.Diagnostics.launchHistoryHeader(updated: updated, maxEntries: snapshot.maxEntries)
        let body = renderLaunchHistory(snapshot.launches, limit: snapshot.maxEntries)
        let out = HubDiagnosticsBundleExporter.redactTextForSharing(header + "\n\n" + body)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    private enum FixNowAction {
        case restartGRPC
        case switchGRPCPortAndRestart
        case restartBridge
        case restartRuntime
        case clearPythonAndRestartRuntime
        case unlockRuntimeLockHolders
        case repairDBAndRestartGRPC
        case repairInstallLocation
        case openNodeInstall
        case openPermissionsSettings

        var summary: String {
            switch self {
            case .restartGRPC:
                return HubUIStrings.Settings.Diagnostics.FixNow.restartGRPC
            case .switchGRPCPortAndRestart:
                return HubUIStrings.Settings.Diagnostics.FixNow.switchGRPCPortAndRestart
            case .restartBridge:
                return HubUIStrings.Settings.Diagnostics.FixNow.restartBridge
            case .restartRuntime:
                return HubUIStrings.Settings.Diagnostics.FixNow.restartRuntime
            case .clearPythonAndRestartRuntime:
                return HubUIStrings.Settings.Diagnostics.FixNow.clearPythonAndRestartRuntime
            case .unlockRuntimeLockHolders:
                return HubUIStrings.Settings.Diagnostics.FixNow.unlockRuntimeLockHolders
            case .repairDBAndRestartGRPC:
                return HubUIStrings.Settings.Diagnostics.FixNow.repairDBAndRestartGRPC
            case .repairInstallLocation:
                return HubUIStrings.Settings.Diagnostics.FixNow.repairInstallLocation
            case .openNodeInstall:
                return HubUIStrings.Settings.Diagnostics.FixNow.openNodeInstall
            case .openPermissionsSettings:
                return HubUIStrings.Settings.Diagnostics.FixNow.openPermissionsSettings
            }
        }
    }

    private struct FixNowOutcome {
        var ok: Bool
        var code: String
        var detail: String

        func render() -> String {
            HubUIStrings.Settings.Diagnostics.FixNow.renderOutcome(code: code, ok: ok, detail: detail)
        }
    }

    private func recommendedFixSummary(snapshot: HubLaunchStatusSnapshot?) -> String {
        guard let act = recommendedFixAction(snapshot: snapshot) else { return "" }
        return act.summary
    }

    private func recommendedRuntimeFixAction() -> FixNowAction? {
        // The launch state machine only captures startup-time failures. The AI runtime can still
        // exit later (lock-busy / python misconfig / import errors). Surface a quick fix here so
        // Diagnostics remains useful after "SERVING".
        let err = store.aiRuntimeLastError.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = err.lowercased()
        if !err.isEmpty {
            if lower.contains("lock busy") || lower.contains("ai_runtime.lock") || lower.contains("runtime exited immediately (code 0)") {
                return .unlockRuntimeLockHolders
            }
            if lower.contains("python path") || lower.contains("xcrun stub") || lower.contains("not executable") {
                return .clearPythonAndRestartRuntime
            }
            if lower.contains("script is missing") || lower.contains("failed to install runtime script") {
                return .repairInstallLocation
            }
            return .restartRuntime
        }

        // Lock can remain busy with empty lastError (e.g. after relaunch). Prefer lock fix first.
        if store.aiRuntimeLockBusyNow() {
            return .unlockRuntimeLockHolders
        }

        // Even if lastError is empty (common for code=0 exits), we can still detect an unhealthy
        // runtime via the status text and offer a restart. Do NOT gate on auto-start here; Fix Now
        // is user-initiated and should prioritize core AI health over integrations permissions.
        let status = store.aiRuntimeStatusText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isRunning = status.contains("runtime: running")
            || status.contains(HubUIStrings.Settings.Advanced.Runtime.statusRunningToken.lowercased())
        let wantsRefresh = status.contains("needs refresh")
            || status.contains(HubUIStrings.Settings.Advanced.Runtime.refreshNeededKeyword)
        if wantsRefresh {
            return .restartRuntime
        }
        let looksStopped = status.contains("stale")
            || status.contains(HubUIStrings.Settings.Advanced.Runtime.staleKeyword)
            || status.contains("not running")
            || status.contains(HubUIStrings.Settings.Advanced.Runtime.notRunningKeyword)
            || status.contains("stopped")
            || status.contains(HubUIStrings.Settings.Advanced.Runtime.stoppedKeyword)
            || status.contains("error")
            || status.contains(HubUIStrings.Settings.Advanced.Runtime.errorKeyword)
        if !isRunning, looksStopped {
            return .restartRuntime
        }

        return nil
    }

    private func recommendedFixAction(snapshot: HubLaunchStatusSnapshot?) -> FixNowAction? {
        if let rc = snapshot?.rootCause {
            let code = rc.errorCode.trimmingCharacters(in: .whitespacesAndNewlines)

            // Install-location issues are common root causes for "weird" behavior (TCC prompts / AppTranslocation).
            if code == "XHUB_ENV_INVALID", AppInstallDoctor.shouldWarn() {
                return .repairInstallLocation
            }

            switch code {
        case "XHUB_GRPC_PORT_IN_USE":
            return .switchGRPCPortAndRestart
        case "XHUB_GRPC_NODE_MISSING":
            return .openNodeInstall
        case "XHUB_GRPC_SERVER_EXITED":
            return .restartGRPC
        case "XHUB_BRIDGE_UNAVAILABLE":
            return .restartBridge
        case "XHUB_RT_PYTHON_INVALID":
            return .clearPythonAndRestartRuntime
        case "XHUB_RT_LOCK_BUSY":
            return .unlockRuntimeLockHolders
        case "XHUB_RT_IMPORT_ERROR":
            return .restartRuntime
        case "XHUB_RT_SCRIPT_MISSING":
            return .repairInstallLocation
        case "XHUB_DB_OPEN_FAILED", "XHUB_DB_INTEGRITY_FAILED":
            return .repairDBAndRestartGRPC
        case "XHUB_ENV_INVALID":
            return AppInstallDoctor.shouldWarn() ? .repairInstallLocation : .openPermissionsSettings
        default:
            switch rc.component {
            case .grpc:
                return .restartGRPC
            case .bridge:
                return .restartBridge
            case .runtime:
                return .restartRuntime
            case .env, .db:
                return AppInstallDoctor.shouldWarn() ? .repairInstallLocation : .openPermissionsSettings
            }
            }
        }

        // No launch root-cause fix. If the runtime is unhealthy (common after launch), prioritize
        // self-healing over unrelated permissions prompts.
        if let act = recommendedRuntimeFixAction() {
            return act
        }

        let needsAXForIntegrations = store.integrationSlackEnabled || store.integrationMessagesEnabled
        if needsAXForIntegrations, !axTrusted {
            return .openPermissionsSettings
        }
        if AppInstallDoctor.shouldWarn() {
            return .repairInstallLocation
        }
        return nil
    }

    private func fixNow(snapshot: HubLaunchStatusSnapshot?) {
        Task { await fixNowAsync(snapshot: snapshot) }
    }

    private func runLsofKillAndRestart() {
        Task { await runLsofKillAndRestartAsync() }
    }

    private func retryLaunchDiagnosis() {
        Task { await retryLaunchDiagnosisAsync() }
    }

    private func restartComponentsForDiagnostics() {
        Task { await restartComponentsForDiagnosticsAsync() }
    }

    private func resetVolatileCachesForDiagnostics() {
        Task { await resetVolatileCachesForDiagnosticsAsync() }
    }

    private func repairDBSafeForDiagnostics() {
        Task { await repairDBSafeForDiagnosticsAsync() }
    }

    private func runtimeAliveSnapshot() -> (alive: Bool, pid: Int, localReady: Bool, providerSummary: String, runtimeVersion: String, ageSec: Double) {
        guard let st = AIRuntimeStatusStorage.load() else {
            return (false, 0, false, "none", "", 0)
        }
        let age = max(0.0, Date().timeIntervalSince1970 - st.updatedAt)
        let ver = (st.runtimeVersion ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            st.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL),
            st.pid,
            st.hasReadyProvider(ttl: AIRuntimeStatus.recommendedHeartbeatTTL),
            st.providerSummary(ttl: AIRuntimeStatus.recommendedHeartbeatTTL),
            ver,
            age
        )
    }

    private struct RuntimeUnlockRestartOutcome {
        var ok: Bool
        var code: String
        var detail: String
        var error: String
    }

    private func runtimeLockIssueLikely(snapshot: HubLaunchStatusSnapshot?) -> Bool {
        if snapshot?.rootCause?.errorCode == "XHUB_RT_LOCK_BUSY" {
            return true
        }
        if store.aiRuntimeLockBusyNow() {
            return true
        }
        let err = store.aiRuntimeLastError.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if err.isEmpty { return false }
        return err.contains("lock busy") || err.contains("ai_runtime.lock") || err.contains("runtime exited immediately (code 0)")
    }

    private func grpcPortConflictLikely(snapshot: HubLaunchStatusSnapshot?) -> Bool {
        if snapshot?.rootCause?.errorCode == "XHUB_GRPC_PORT_IN_USE" {
            return true
        }
        let err = store.grpc.lastError.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if err.isEmpty { return false }
        return err.contains("port") && err.contains("already in use")
    }

    @MainActor
    private func repairGRPCPortConflictAsync() async -> FixNowOutcome {
        let oldPort = store.grpc.port
        if let free = HubGRPCServerSupport.diagnosticsFindAvailablePort(startingAt: oldPort + 1) {
            store.grpc.port = free
            store.grpc.start()
            return await verifyGRPCAfterFix(
                successCode: "FIX_GRPC_PORT_SWITCH_OK",
                failureCode: "FIX_GRPC_PORT_SWITCH_FAILED",
                actionSummary: HubUIStrings.Settings.Diagnostics.FixNow.requestedPortSwitch(oldPort: oldPort, newPort: free)
            )
        }

        store.grpc.restart()
        return await verifyGRPCAfterFix(
            successCode: "FIX_GRPC_RESTART_OK",
            failureCode: "FIX_GRPC_RESTART_FAILED",
            actionSummary: HubUIStrings.Settings.Diagnostics.FixNow.requestedRestartOnSamePort(oldPort)
        )
    }

    @MainActor
    private func unlockRuntimeLockAndRestartResult(allowNonRuntimeHolders: Bool, autoEscalateToForce: Bool) async -> RuntimeUnlockRestartOutcome {
        // First ask runtime to stop via its marker file; this clears most stale-lock cases.
        store.stopAIRuntime()
        try? await Task.sleep(nanoseconds: 600_000_000)

        var r = store.forceUnlockAIRuntimeLockByLsof(allowNonRuntimeHolders: allowNonRuntimeHolders)
        var forcedMode = allowNonRuntimeHolders
        if !r.lockReleased && !allowNonRuntimeHolders && autoEscalateToForce {
            let allCandidatesSkipped = !r.holderPids.isEmpty && Set(r.holderPids) == Set(r.skippedPids)
            let lower = r.detail.lowercased()
            if allCandidatesSkipped || lower.contains("lsof is blocked by sandbox") {
                // User already clicked Fix Now: retry once in force mode to avoid manual Terminal kills.
                r = store.forceUnlockAIRuntimeLockByLsof(allowNonRuntimeHolders: true)
                forcedMode = true
            }
        }

        if !r.lockReleased {
            let hint = HubUIStrings.Settings.Diagnostics.FixNow.terminalRetryHint(command: r.command)
            return RuntimeUnlockRestartOutcome(
                ok: false,
                code: "FIX_RT_LOCK_STILL_BUSY",
                detail: "",
                error: (r.detail.isEmpty ? HubUIStrings.Settings.Diagnostics.FixNow.runtimeLockStillBusy : r.detail) + hint
            )
        }

        // Lock is now free; immediately restart runtime and verify.
        store.startAIRuntime()
        try? await Task.sleep(nanoseconds: 1_300_000_000)
        let rt = runtimeAliveSnapshot()
        if rt.alive {
            let ok = rt.localReady ? "local_ready=1" : "local_ready=0"
            let providers = "providers=\(rt.providerSummary)"
            let ver = rt.runtimeVersion.isEmpty ? "" : " version=\(rt.runtimeVersion)"
            let killed = r.killedPids.isEmpty ? "" : " killed=\(r.killedPids.map(String.init).joined(separator: ","))"
            return RuntimeUnlockRestartOutcome(
                ok: true,
                code: forcedMode ? "FIX_RT_LOCK_FORCE_CLEAR_RESTART_OK" : "FIX_RT_LOCK_CLEAR_RESTART_OK",
                detail: HubUIStrings.Settings.Diagnostics.FixNow.runtimeLockClearedAndRestarted(
                    forced: forcedMode,
                    pid: rt.pid,
                    localReady: ok,
                    providers: providers,
                    version: ver,
                    killed: killed
                ),
                error: ""
            )
        }

        let err = store.aiRuntimeLastError.trimmingCharacters(in: .whitespacesAndNewlines)
        if err.isEmpty {
            return RuntimeUnlockRestartOutcome(
                ok: false,
                code: "FIX_RT_RESTART_AFTER_LOCK_CLEAR_FAILED",
                detail: "",
                error: HubUIStrings.Settings.Diagnostics.FixNow.runtimeLockClearedButNotStarted(command: r.command)
            )
        }
        return RuntimeUnlockRestartOutcome(
            ok: false,
            code: classifyRuntimeFailureCode(err, fallback: "FIX_RT_RESTART_AFTER_LOCK_CLEAR_FAILED"),
            detail: "",
            error: err
        )
    }

    @MainActor
    private func unlockRuntimeLockAndRestart(allowNonRuntimeHolders: Bool) async {
        let out = await unlockRuntimeLockAndRestartResult(
            allowNonRuntimeHolders: allowNonRuntimeHolders,
            autoEscalateToForce: !allowNonRuntimeHolders
        )
        let outcome = FixNowOutcome(
            ok: out.ok,
            code: out.code,
            detail: out.ok ? out.detail : out.error
        )
        applyFixNowOutcome(outcome)
        rerunLaunchDiagnosisSoon(delayNs: 1_350_000_000)
    }

    @MainActor
    private func runLsofKillAndRestartAsync() async {
        guard !fixNowIsRunning else { return }
        fixNowIsRunning = true
        fixNowResultText = ""
        fixNowErrorText = ""
        defer { fixNowIsRunning = false }

        HubDiagnostics.log("diagnostics.fix action=unlock_runtime_lock_holders_force")
        await unlockRuntimeLockAndRestart(allowNonRuntimeHolders: true)
    }

    @MainActor
    private func retryLaunchDiagnosisAsync() async {
        guard !diagnosticsActionIsRunning else { return }
        diagnosticsActionIsRunning = true
        diagnosticsActionResultText = ""
        diagnosticsActionErrorText = ""
        defer { diagnosticsActionIsRunning = false }

        HubDiagnostics.log("diagnostics.action action=retry_start")
        HubLaunchStateMachine.shared.start(bridgeStarted: true)
        try? await Task.sleep(nanoseconds: 450_000_000)
        hubLaunchStatus = HubLaunchStatusStorage.load()
        hubLaunchHistory = HubLaunchHistoryStorage.load()
        diagnosticsActionResultText = HubUIStrings.Settings.Diagnostics.FixNow.retryDiagnosisRequested
    }

    @MainActor
    private func restartComponentsForDiagnosticsAsync() async {
        guard !diagnosticsActionIsRunning else { return }
        diagnosticsActionIsRunning = true
        diagnosticsActionResultText = ""
        diagnosticsActionErrorText = ""
        defer { diagnosticsActionIsRunning = false }

        HubDiagnostics.log("diagnostics.action action=restart_components")

        // Restart embedded Bridge first so status heartbeats resume quickly.
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.restartEmbeddedBridgeForDiagnostics()
        }
        store.bridge.refresh()

        // Restart gRPC server (best-effort; may fail if Node is missing / port conflict).
        store.grpc.restart()

        // Restart AI runtime (best-effort; lock-holder issues are handled by Fix Now).
        store.stopAIRuntime()
        try? await Task.sleep(nanoseconds: 900_000_000)
        store.startAIRuntime()

        // Re-run attribution to update root-cause + blocked capabilities.
        HubLaunchStateMachine.shared.start(bridgeStarted: true)
        try? await Task.sleep(nanoseconds: 650_000_000)
        hubLaunchStatus = HubLaunchStatusStorage.load()
        hubLaunchHistory = HubLaunchHistoryStorage.load()

        diagnosticsActionResultText = HubUIStrings.Settings.Diagnostics.FixNow.restartComponentsRequested
    }

    @MainActor
    private func resetVolatileCachesForDiagnosticsAsync() async {
        guard !diagnosticsActionIsRunning else { return }
        diagnosticsActionIsRunning = true
        diagnosticsActionResultText = ""
        diagnosticsActionErrorText = ""
        defer { diagnosticsActionIsRunning = false }

        HubDiagnostics.log("diagnostics.action action=reset_volatile_caches")

        let base = SharedPaths.ensureHubDirectory()
        let dirs: [URL] = [
            base.appendingPathComponent("ai_requests", isDirectory: true),
            base.appendingPathComponent("ai_responses", isDirectory: true),
            base.appendingPathComponent("ipc_events", isDirectory: true),
            base.appendingPathComponent("ipc_responses", isDirectory: true),
            base.appendingPathComponent("bridge_commands", isDirectory: true),
            base.appendingPathComponent("bridge_requests", isDirectory: true),
            base.appendingPathComponent("bridge_responses", isDirectory: true),
        ]

        let fm = FileManager.default
        var removedCount = 0
        var failedCount = 0

        for dir in dirs {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
                for u in files {
                    do {
                        try fm.removeItem(at: u)
                        removedCount += 1
                    } catch {
                        failedCount += 1
                    }
                }
            } catch {
                failedCount += 1
            }
        }

        HubLaunchStateMachine.shared.start(bridgeStarted: true)
        try? await Task.sleep(nanoseconds: 650_000_000)
        hubLaunchStatus = HubLaunchStatusStorage.load()
        hubLaunchHistory = HubLaunchHistoryStorage.load()

        diagnosticsActionResultText = HubUIStrings.Settings.Diagnostics.FixNow.resetVolatileCaches(
            removed: removedCount,
            failed: failedCount
        )
    }

    @MainActor
    private func repairDBSafeForDiagnosticsAsync() async {
        guard !diagnosticsActionIsRunning else { return }
        diagnosticsActionIsRunning = true
        diagnosticsActionResultText = ""
        diagnosticsActionErrorText = ""
        defer { diagnosticsActionIsRunning = false }

        HubDiagnostics.log("diagnostics.action action=repair_db_safe")

        let res = await repairGRPCDBSafeAndRestart()

        HubLaunchStateMachine.shared.start(bridgeStarted: true)
        try? await Task.sleep(nanoseconds: 650_000_000)
        hubLaunchStatus = HubLaunchStatusStorage.load()
        hubLaunchHistory = HubLaunchHistoryStorage.load()

        if res.ok {
            diagnosticsActionResultText = res.render()
        } else {
            diagnosticsActionErrorText = res.render()
        }
    }

    @MainActor
    private func repairGRPCDBSafeAndRestart() async -> FixNowOutcome {
        // Stop gRPC first to reduce chances of DB locks during checkpoint/check.
        store.grpc.stop()

        let base = SharedPaths.ensureHubDirectory()
        let dbDir = base.appendingPathComponent("hub_grpc", isDirectory: true)
        let db = dbDir.appendingPathComponent("hub.sqlite3")

        do {
            try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)

            // Fix a common crash-loop case: a zero-byte DB file.
            if FileManager.default.fileExists(atPath: db.path),
               let attrs = try? FileManager.default.attributesOfItem(atPath: db.path),
               let size = attrs[.size] as? NSNumber,
               size.int64Value == 0 {
                try? FileManager.default.removeItem(at: db)
            }

            // Backup (best-effort) before touching WAL/checkpoint.
            if FileManager.default.fileExists(atPath: db.path) {
                let ts = Int(Date().timeIntervalSince1970)
                let bak = dbDir.appendingPathComponent("hub.sqlite3.bak_\(ts)")
                if !FileManager.default.fileExists(atPath: bak.path) {
                    try? FileManager.default.copyItem(at: db, to: bak)
                }
            }

            // Best-effort: checkpoint WAL (safe) to reduce "stuck WAL" and shrink temporary files.
            _ = runSQLite(dbPath: db.path, readonly: false, sql: "PRAGMA busy_timeout=1500; PRAGMA wal_checkpoint(TRUNCATE);")

            // Quick check for corruption/locking.
            let qc = runSQLite(dbPath: db.path, readonly: true, sql: "PRAGMA busy_timeout=1500; PRAGMA quick_check;")
            let out = qc.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let ok = qc.exitCode == 0 && (out.lowercased() == "ok" || out.lowercased().hasSuffix("\nok"))

            store.grpc.start()

            if ok {
                return await verifyGRPCAfterFix(
                    successCode: "FIX_GRPC_DB_REPAIR_OK",
                    failureCode: "FIX_GRPC_DB_REPAIR_RESTART_FAILED",
                    actionSummary: HubUIStrings.Settings.Diagnostics.FixNow.databaseRepairQuickCheckPassed
                )
            }

            let err = (qc.stderr + "\n" + qc.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
            let msg = err.isEmpty
                ? HubUIStrings.Settings.Diagnostics.FixNow.databaseRepairQuickCheckFailed(exitCode: qc.exitCode)
                : HubUIStrings.Settings.Diagnostics.FixNow.databaseRepairQuickCheckFailed(errorText: err)
            return FixNowOutcome(ok: false, code: "FIX_GRPC_DB_REPAIR_CHECK_FAILED", detail: msg)
        } catch {
            store.grpc.start()
            return FixNowOutcome(
                ok: false,
                code: "FIX_GRPC_DB_REPAIR_EXCEPTION",
                detail: HubUIStrings.Settings.Diagnostics.FixNow.databaseRepairException(error.localizedDescription)
            )
        }
    }

    private struct SQLiteRunResult {
        var exitCode: Int32
        var stdout: String
        var stderr: String
    }

    private func grpcLogTail(maxBytes: Int = 64 * 1024) -> String {
        let base = SharedPaths.appGroupDirectory() ?? SharedPaths.ensureHubDirectory()
        let logURL = base.appendingPathComponent("hub_grpc.log")
        guard let data = try? Data(contentsOf: logURL), !data.isEmpty else {
            return ""
        }
        let tail = data.suffix(max(2048, min(maxBytes, 512 * 1024)))
        return String(data: tail, encoding: .utf8) ?? ""
    }

    private func grpcLikelyTLSPEMFailure() -> Bool {
        let lower = grpcLogTail().lowercased()
        if lower.isEmpty { return false }
        let pemNoStartLine =
            lower.contains("err_ossl_pem_no_start_line") ||
            lower.contains("pem routines::no start line") ||
            (lower.contains("node:internal/tls/secure-context") && lower.contains("setcert"))
        let opensslSerialWriteDenied =
            (lower.contains("openssl x509 -req") && lower.contains("-cacreateserial") && lower.contains(".srl: operation not permitted")) ||
            (lower.contains("getting ca private key") && lower.contains(".srl: operation not permitted"))
        return
            pemNoStartLine ||
            opensslSerialWriteDenied
    }

    private func runSQLite(dbPath: String, readonly: Bool, sql: String) -> SQLiteRunResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        var args: [String] = []
        if readonly {
            args.append("-readonly")
        }
        args.append(contentsOf: ["-batch", dbPath, sql])
        p.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return SQLiteRunResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return SQLiteRunResult(
            exitCode: p.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    private func applyFixNowOutcome(_ outcome: FixNowOutcome) {
        let rendered = outcome.render()
        if outcome.ok {
            fixNowErrorText = ""
            fixNowResultText = rendered
        } else {
            fixNowResultText = ""
            fixNowErrorText = rendered
        }
        let compact = outcome.detail
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " | ")
        HubDiagnostics.log("diagnostics.fix result code=\(outcome.code) ok=\(outcome.ok ? 1 : 0) detail=\(compact)")
    }

    private struct GRPCFixSnapshot {
        var running: Bool
        var statusText: String
        var lastError: String
    }

    private func grpcFixSnapshot() -> GRPCFixSnapshot {
        store.grpc.refresh()
        let status = store.grpc.statusText.trimmingCharacters(in: .whitespacesAndNewlines)
        let err = store.grpc.lastError.trimmingCharacters(in: .whitespacesAndNewlines)
        let running = status.lowercased().contains("grpc: running")
        return GRPCFixSnapshot(running: running, statusText: status, lastError: err)
    }

    @MainActor
    private func waitForGRPCFixSnapshot(timeoutNs: UInt64 = 3_500_000_000, pollNs: UInt64 = 250_000_000) async -> GRPCFixSnapshot {
        let start = Date().timeIntervalSince1970
        let timeoutSec = Double(timeoutNs) / 1_000_000_000.0
        var snap = grpcFixSnapshot()
        while !snap.running && (Date().timeIntervalSince1970 - start) < timeoutSec {
            try? await Task.sleep(nanoseconds: pollNs)
            snap = grpcFixSnapshot()
        }
        return snap
    }

    private func classifyGRPCFailureCode(_ errorOrStatus: String, fallback: String) -> String {
        let lower = errorOrStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.isEmpty { return fallback }
        if lower.contains("already in use") || lower.contains("eaddrinuse") {
            return "FIX_GRPC_PORT_IN_USE"
        }
        if lower.contains("node not found") || lower.contains("node missing") {
            return "FIX_GRPC_NODE_MISSING"
        }
        if lower.contains("pem") || lower.contains("certificate") || lower.contains("tls") || lower.contains("secure-context") || lower.contains(".srl") {
            return "FIX_GRPC_TLS_INVALID"
        }
        if lower.contains("db") {
            return "FIX_GRPC_DB_ERROR"
        }
        if lower.contains("exited") {
            return "FIX_GRPC_EXITED"
        }
        return fallback
    }

    @MainActor
    private func verifyGRPCAfterFix(successCode: String, failureCode: String, actionSummary: String) async -> FixNowOutcome {
        let snap = await waitForGRPCFixSnapshot()
        if snap.running {
            return FixNowOutcome(ok: true, code: successCode, detail: actionSummary)
        }
        let failureText = !snap.lastError.isEmpty
            ? snap.lastError
            : (!snap.statusText.isEmpty ? snap.statusText : HubUIStrings.Settings.Diagnostics.grpcStillNotRunning)
        let code = classifyGRPCFailureCode(failureText, fallback: failureCode)
        return FixNowOutcome(
            ok: false,
            code: code,
            detail: "\(actionSummary)\n\n\(failureText)"
        )
    }

    private struct BridgeFixSnapshot {
        var alive: Bool
        var updatedAt: Double
    }

    private func bridgeFixSnapshot() -> BridgeFixSnapshot {
        store.bridge.refresh()
        let st = BridgeSupport.shared.statusSnapshot()
        return BridgeFixSnapshot(alive: st.alive, updatedAt: st.updatedAt)
    }

    @MainActor
    private func waitForBridgeFixSnapshot(timeoutNs: UInt64 = 2_800_000_000, pollNs: UInt64 = 250_000_000) async -> BridgeFixSnapshot {
        let start = Date().timeIntervalSince1970
        let timeoutSec = Double(timeoutNs) / 1_000_000_000.0
        var snap = bridgeFixSnapshot()
        while !snap.alive && (Date().timeIntervalSince1970 - start) < timeoutSec {
            try? await Task.sleep(nanoseconds: pollNs)
            snap = bridgeFixSnapshot()
        }
        return snap
    }

    @MainActor
    private func verifyBridgeAfterFix(successCode: String, failureCode: String, actionSummary: String) async -> FixNowOutcome {
        let snap = await waitForBridgeFixSnapshot()
        if snap.alive {
            return FixNowOutcome(ok: true, code: successCode, detail: actionSummary)
        }
        let ageSec: Int = {
            if snap.updatedAt <= 0 { return -1 }
            return Int(max(0.0, Date().timeIntervalSince1970 - snap.updatedAt))
        }()
        let staleInfo = ageSec < 0
            ? HubUIStrings.Settings.Diagnostics.FixNow.bridgeHeartbeatMissing
            : HubUIStrings.Settings.Diagnostics.FixNow.bridgeHeartbeatExpired(ageSec: ageSec)
        return FixNowOutcome(
            ok: false,
            code: failureCode,
            detail: "\(actionSummary)\n\n\(staleInfo)"
        )
    }

    private func classifyRuntimeFailureCode(_ errorText: String, fallback: String) -> String {
        let lower = errorText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.isEmpty { return fallback }
        if lower.contains("lock busy") || lower.contains("ai_runtime.lock") || lower.contains("runtime exited immediately (code 0)") {
            return "FIX_RT_LOCK_BUSY"
        }
        if lower.contains("python path") || lower.contains("xcrun stub") || lower.contains("not executable") {
            return "FIX_RT_PYTHON_INVALID"
        }
        if lower.contains("script is missing") || lower.contains("failed to install runtime script") {
            return "FIX_RT_SCRIPT_MISSING"
        }
        if lower.contains("mlx is unavailable") || lower.contains("import") {
            return "FIX_RT_IMPORT_ERROR"
        }
        return fallback
    }

    @MainActor
    private func waitForRuntimeFixSnapshot(timeoutNs: UInt64 = 4_500_000_000, pollNs: UInt64 = 250_000_000) async -> (alive: Bool, pid: Int, localReady: Bool, providerSummary: String, runtimeVersion: String, ageSec: Double) {
        let start = Date().timeIntervalSince1970
        let timeoutSec = Double(timeoutNs) / 1_000_000_000.0
        var snap = runtimeAliveSnapshot()
        while !snap.alive && (Date().timeIntervalSince1970 - start) < timeoutSec {
            try? await Task.sleep(nanoseconds: pollNs)
            snap = runtimeAliveSnapshot()
        }
        return snap
    }

    @MainActor
    private func verifyRuntimeAfterFix(successCode: String, failureCode: String, actionSummary: String) async -> FixNowOutcome {
        let rt = await waitForRuntimeFixSnapshot()
        if rt.alive {
            let ok = rt.localReady ? "local_ready=1" : "local_ready=0"
            let providers = "providers=\(rt.providerSummary)"
            let ver = rt.runtimeVersion.isEmpty ? "" : " version=\(rt.runtimeVersion)"
            return FixNowOutcome(
                ok: true,
                code: successCode,
                detail: HubUIStrings.Settings.Diagnostics.FixNow.runtimeRunningDetail(
                    actionSummary: actionSummary,
                    pid: rt.pid,
                    localReady: ok,
                    providers: providers,
                    version: ver
                )
            )
        }
        let err = store.aiRuntimeLastError.trimmingCharacters(in: .whitespacesAndNewlines)
        let msg = err.isEmpty ? HubUIStrings.Settings.Diagnostics.FixNow.runtimeNotStartedOpenLog : err
        let code = classifyRuntimeFailureCode(msg, fallback: failureCode)
        return FixNowOutcome(
            ok: false,
            code: code,
            detail: "\(actionSummary)\n\n\(msg)"
        )
    }

    @MainActor
    private func fixNowAsync(snapshot: HubLaunchStatusSnapshot?) async {
        guard let action = recommendedFixAction(snapshot: snapshot), !fixNowIsRunning else { return }
        fixNowIsRunning = true
        fixNowResultText = ""
        fixNowErrorText = ""
        defer { fixNowIsRunning = false }

        let lockIssue = runtimeLockIssueLikely(snapshot: snapshot)
        let portIssue = grpcPortConflictLikely(snapshot: snapshot)
        if lockIssue && portIssue {
            HubDiagnostics.log("diagnostics.fix action=stabilize_runtime_and_grpc")
            let runtimeRaw = await unlockRuntimeLockAndRestartResult(
                allowNonRuntimeHolders: false,
                autoEscalateToForce: true
            )
            let runtime = FixNowOutcome(
                ok: runtimeRaw.ok,
                code: runtimeRaw.code,
                detail: runtimeRaw.ok ? runtimeRaw.detail : runtimeRaw.error
            )
            let grpc = await repairGRPCPortConflictAsync()
            let bothOk = runtime.ok && grpc.ok
            let bothFail = !runtime.ok && !grpc.ok
            let combinedCode: String = {
                if bothOk { return "FIX_STABILIZE_RUNTIME_GRPC_OK" }
                if bothFail { return "FIX_STABILIZE_RUNTIME_GRPC_FAILED" }
                return "FIX_STABILIZE_RUNTIME_GRPC_PARTIAL"
            }()
            let combined = FixNowOutcome(
                ok: bothOk,
                code: combinedCode,
                detail:
                    """
                    \(HubUIStrings.Settings.Diagnostics.FixNow.combinedRuntimeOutcome(
                        code: runtime.code,
                        ok: runtime.ok,
                        detail: runtime.detail
                    ))

                    \(HubUIStrings.Settings.Diagnostics.FixNow.combinedGRPCOutcome(
                        code: grpc.code,
                        ok: grpc.ok,
                        detail: grpc.detail
                    ))
                    """
            )
            applyFixNowOutcome(combined)
            rerunLaunchDiagnosisSoon(delayNs: 1_500_000_000)
            return
        }

        switch action {
        case .restartGRPC:
            HubDiagnostics.log("diagnostics.fix action=restart_grpc")
            if grpcLikelyTLSPEMFailure(), store.grpc.tlsMode != "insecure" {
                let oldMode = store.grpc.tlsMode
                // Self-heal common crash-loop: malformed TLS PEM files.
                // Reliability first: downgrade to insecure so gRPC can boot.
                store.grpc.tlsMode = "insecure"
                store.grpc.start()
                let outcome = await verifyGRPCAfterFix(
                    successCode: "FIX_GRPC_TLS_DOWNGRADE_RESTART_OK",
                    failureCode: "FIX_GRPC_TLS_DOWNGRADE_RESTART_FAILED",
                    actionSummary: HubUIStrings.Settings.Diagnostics.FixNow.tlsDowngradeRestart(oldMode: oldMode)
                )
                applyFixNowOutcome(outcome)
                rerunLaunchDiagnosisSoon(delayNs: 650_000_000)
                return
            }
            store.grpc.restart()
            let outcome = await verifyGRPCAfterFix(
                successCode: "FIX_GRPC_RESTART_OK",
                failureCode: "FIX_GRPC_RESTART_FAILED",
                actionSummary: HubUIStrings.Settings.Diagnostics.FixNow.requestedRestartGRPC
            )
            applyFixNowOutcome(outcome)
            rerunLaunchDiagnosisSoon()

        case .switchGRPCPortAndRestart:
            HubDiagnostics.log("diagnostics.fix action=switch_grpc_port")
            let res = await repairGRPCPortConflictAsync()
            applyFixNowOutcome(res)
            rerunLaunchDiagnosisSoon()

        case .restartBridge:
            HubDiagnostics.log("diagnostics.fix action=restart_bridge")
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.restartEmbeddedBridgeForDiagnostics()
                store.bridge.refresh()
                let outcome = await verifyBridgeAfterFix(
                    successCode: "FIX_BRIDGE_RESTART_OK",
                    failureCode: "FIX_BRIDGE_RESTART_FAILED",
                    actionSummary: HubUIStrings.Settings.Diagnostics.FixNow.requestedRestartBridge
                )
                applyFixNowOutcome(outcome)
                rerunLaunchDiagnosisSoon()
            } else {
                applyFixNowOutcome(
                    FixNowOutcome(
                        ok: false,
                        code: "FIX_BRIDGE_RESTART_UNAVAILABLE",
                        detail: HubUIStrings.Settings.Diagnostics.FixNow.bridgeRestartUnavailable
                    )
                )
            }

        case .restartRuntime:
            HubDiagnostics.log("diagnostics.fix action=restart_runtime")
            store.stopAIRuntime()
            let stopErr = store.aiRuntimeLastError.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stopErr.isEmpty {
                // Stop can fail if the lock holder is a different/orphaned process. Surface that
                // guidance instead of immediately clearing it by starting again.
                applyFixNowOutcome(
                    FixNowOutcome(
                        ok: false,
                        code: classifyRuntimeFailureCode(stopErr, fallback: "FIX_RT_STOP_FAILED"),
                        detail: stopErr
                    )
                )
                return
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
            store.startAIRuntime()
            let outcome = await verifyRuntimeAfterFix(
                successCode: "FIX_RT_RESTART_OK",
                failureCode: "FIX_RT_RESTART_FAILED",
                actionSummary: HubUIStrings.Settings.Diagnostics.FixNow.requestedRestartRuntime
            )
            applyFixNowOutcome(outcome)
            rerunLaunchDiagnosisSoon(delayNs: 1_350_000_000)

        case .clearPythonAndRestartRuntime:
            HubDiagnostics.log("diagnostics.fix action=clear_python_restart_runtime")
            store.stopAIRuntime()
            store.aiRuntimePython = "" // allow auto-detection in startAIRuntime()
            let stopErr = store.aiRuntimeLastError.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stopErr.isEmpty {
                applyFixNowOutcome(
                    FixNowOutcome(
                        ok: false,
                        code: classifyRuntimeFailureCode(stopErr, fallback: "FIX_RT_STOP_FAILED"),
                        detail: stopErr
                    )
                )
                return
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            store.startAIRuntime()
            let outcome = await verifyRuntimeAfterFix(
                successCode: "FIX_RT_CLEAR_PYTHON_RESTART_OK",
                failureCode: "FIX_RT_CLEAR_PYTHON_RESTART_FAILED",
                actionSummary: HubUIStrings.Settings.Diagnostics.FixNow.requestedClearPythonAndRestartRuntime
            )
            applyFixNowOutcome(outcome)
            rerunLaunchDiagnosisSoon(delayNs: 1_350_000_000)

        case .unlockRuntimeLockHolders:
            HubDiagnostics.log("diagnostics.fix action=unlock_runtime_lock_holders")
            await unlockRuntimeLockAndRestart(allowNonRuntimeHolders: false)

        case .repairDBAndRestartGRPC:
            HubDiagnostics.log("diagnostics.fix action=repair_db_restart_grpc")
            let res = await repairGRPCDBSafeAndRestart()
            applyFixNowOutcome(res)
            rerunLaunchDiagnosisSoon()

        case .repairInstallLocation:
            HubDiagnostics.log("diagnostics.fix action=repair_install_location")
            NSApp.activate(ignoringOtherApps: true)
            if AppInstallDoctor.shouldWarn() {
                AppInstallDoctor.showInstallAlertIfNeeded()
                applyFixNowOutcome(
                    FixNowOutcome(
                        ok: true,
                        code: "FIX_INSTALL_GUIDE_OPENED",
                        detail: HubUIStrings.Settings.Diagnostics.FixNow.openedInstallGuide
                    )
                )
            } else {
                // Best-effort: if the "install doctor" doesn't apply, at least reveal the app bundle
                // so users can confirm what they're running (common issue: multiple copies).
                NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                applyFixNowOutcome(
                    FixNowOutcome(
                        ok: true,
                        code: "FIX_APP_BUNDLE_REVEALED",
                        detail: HubUIStrings.Settings.Diagnostics.FixNow.revealedCurrentAppBundle
                    )
                )
            }

        case .openNodeInstall:
            HubDiagnostics.log("diagnostics.fix action=open_node_install")
            if let u = URL(string: "https://nodejs.org/en/download"), NSWorkspace.shared.open(u) {
                applyFixNowOutcome(
                    FixNowOutcome(
                        ok: true,
                        code: "FIX_NODE_INSTALL_PAGE_OPENED",
                        detail: HubUIStrings.Settings.Diagnostics.FixNow.openedNodeDownloadPage
                    )
                )
            } else {
                applyFixNowOutcome(
                    FixNowOutcome(
                        ok: false,
                        code: "FIX_NODE_INSTALL_PAGE_OPEN_FAILED",
                        detail: HubUIStrings.Settings.Diagnostics.FixNow.openNodeDownloadPageFailed
                    )
                )
            }

        case .openPermissionsSettings:
            HubDiagnostics.log("diagnostics.fix action=open_permissions")
            if !axTrusted {
                SystemSettingsLinks.openAccessibilityPrivacy()
                applyFixNowOutcome(
                    FixNowOutcome(
                        ok: true,
                        code: "FIX_OPEN_SETTINGS_ACCESSIBILITY",
                        detail: HubUIStrings.Settings.Diagnostics.FixNow.openedAccessibilitySettings
                    )
                )
            } else {
                SystemSettingsLinks.openSystemSettings()
                applyFixNowOutcome(
                    FixNowOutcome(
                        ok: true,
                        code: "FIX_OPEN_SETTINGS_GENERAL",
                        detail: HubUIStrings.Settings.Diagnostics.FixNow.openedSystemSettings
                    )
                )
            }
        }
    }

    private func rerunLaunchDiagnosisSoon(delayNs: UInt64 = 350_000_000) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNs)
            HubLaunchStateMachine.shared.start(bridgeStarted: true)
            hubLaunchStatus = HubLaunchStatusStorage.load()
        }
    }

    private func renderLaunchSteps(_ steps: [HubLaunchStep]) -> String {
        // Compact, grep-friendly one-line format:
        //   <elapsed_ms> <STATE> ok=<0|1> code=<...> hint=<...>
        let out = steps.map { st in
            HubUIStrings.Settings.Diagnostics.launchStepLine(
                elapsedMs: st.elapsedMs,
                state: st.state.rawValue,
                ok: st.ok,
                code: st.errorCode,
                hint: st.errorHint
            )
        }
        return out.joined(separator: "\n")
    }

    private func copyLaunchRootCauseAndBlockedToClipboard(snapshot: HubLaunchStatusSnapshot?) {
        let state = snapshot?.state.rawValue ?? "unknown"
        let root = renderRootCauseText(snapshot?.rootCause)
        let blocked = snapshot?.degraded.blockedCapabilities ?? []

        var lines: [String] = []
        lines.append(HubUIStrings.Settings.Diagnostics.Export.stateLine(state))
        if let id = snapshot?.launchId.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.launchIDLine(id))
        }
        if let snapshot, snapshot.updatedAtMs > 0 {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.updatedAtLine(formatEpochMs(snapshot.updatedAtMs)))
        }
        lines.append(HubUIStrings.Settings.Diagnostics.Export.rootCauseBlock(root.isEmpty ? HubUIStrings.Settings.Diagnostics.noneField : root))
        lines.append(
            HubUIStrings.Settings.Diagnostics.Export.blockedCapabilitiesBlock(
                blocked.isEmpty ? HubUIStrings.Settings.Diagnostics.noneField : blocked.joined(separator: "\n")
            )
        )
        lines.append(
            HubUIStrings.Settings.Diagnostics.Export.remoteAccessBlock(
                remoteAccessDiagnosticsSummaryForClipboard()
            )
        )

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n\n"), forType: .string)
    }

    func copyLocalProviderSummaryToClipboard(snapshot: HubLaunchStatusSnapshot?) {
        let blocked = snapshot?.degraded.blockedCapabilities ?? []
        let rtStatus = store.aiRuntimeStatusText.trimmingCharacters(in: .whitespacesAndNewlines)
        let doctor = store.aiRuntimeDoctorSummaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let installHints = store.aiRuntimeInstallHintsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let providerSummary = store.aiRuntimeProviderSummaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let pythonCandidates = store.aiRuntimePythonCandidatesText.trimmingCharacters(in: .whitespacesAndNewlines)
        let monitorSummary = store.aiRuntimeStatusSnapshot?.runtimeMonitorOperatorSummary(ttl: AIRuntimeStatus.recommendedHeartbeatTTL)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var lines: [String] = []
        if !rtStatus.isEmpty {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.runtimeStatusBlock(rtStatus))
        }
        if !doctor.isEmpty {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.runtimeDoctorBlock(doctor))
        }
        if !installHints.isEmpty {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.runtimeInstallHintsBlock(installHints))
        }
        if let guidance = xhubLocalServiceRecoveryGuidance {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.localServiceRecoveryBlock(guidance.clipboardText))
        }
        lines.append(
            HubUIStrings.Settings.Diagnostics.Export.blockedCapabilitiesBlock(
                blocked.isEmpty ? HubUIStrings.Settings.Diagnostics.noneField : blocked.joined(separator: "\n")
            )
        )
        lines.append(
            HubUIStrings.Settings.Diagnostics.Export.providerSummaryBlock(
                providerSummary.isEmpty ? HubUIStrings.Settings.Diagnostics.noneField : providerSummary
            )
        )
        lines.append(
            HubUIStrings.Settings.Diagnostics.Export.remoteAccessBlock(
                remoteAccessDiagnosticsSummaryForClipboard()
            )
        )
        if !pythonCandidates.isEmpty {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.pythonCandidatesBlock(pythonCandidates))
        }
        if !monitorSummary.isEmpty {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.runtimeMonitorBlock(monitorSummary))
        }

        let out = HubDiagnosticsBundleExporter.redactTextForSharing(lines.joined(separator: "\n\n"))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    func copyRuntimeMonitorSummaryToClipboard(status: AIRuntimeStatus) {
        let text = status.runtimeMonitorOperatorSummary(ttl: AIRuntimeStatus.recommendedHeartbeatTTL)
        let out = HubDiagnosticsBundleExporter.redactTextForSharing(text)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    func copyRuntimeMonitorActiveTasksToClipboard(monitor: AIRuntimeMonitorSnapshot) {
        let body = monitor.activeTasks.isEmpty
            ? HubUIStrings.Settings.RuntimeMonitor.noneField
            : monitor.activeTasks.map(runtimeMonitorActiveTaskLine).joined(separator: "\n")
        let out = HubDiagnosticsBundleExporter.redactTextForSharing(
            HubUIStrings.Settings.Diagnostics.Export.activeTasksBlock(body)
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    func copyRuntimeMonitorLoadedInstancesToClipboard(summary: LocalRuntimeOperationsSummary) {
        let body = summary.instanceRows.isEmpty
            ? HubUIStrings.Settings.RuntimeMonitor.noneField
            : summary.instanceRows.map(runtimeMonitorLoadedInstanceLine).joined(separator: "\n")
        let out = HubDiagnosticsBundleExporter.redactTextForSharing(
            HubUIStrings.Settings.Diagnostics.Export.loadedInstancesBlock(body)
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    func copyRuntimeMonitorCurrentTargetsToClipboard(
        _ currentTargets: [(HubModel, LocalModelRuntimeRequestContext)]
    ) {
        let body = currentTargets.isEmpty
            ? HubUIStrings.Settings.RuntimeMonitor.noneField
            : currentTargets.map { runtimeMonitorCurrentTargetLine(model: $0.0, requestContext: $0.1) }.joined(separator: "\n")
        let out = HubDiagnosticsBundleExporter.redactTextForSharing(
            HubUIStrings.Settings.Diagnostics.Export.currentTargetsBlock(body)
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    func copyRuntimeMonitorErrorsToClipboard(monitor: AIRuntimeMonitorSnapshot) {
        let body = monitor.lastErrors.isEmpty
            ? HubUIStrings.Settings.RuntimeMonitor.noneField
            : monitor.lastErrors.map(runtimeMonitorErrorLine).joined(separator: "\n")
        let out = HubDiagnosticsBundleExporter.redactTextForSharing(
            HubUIStrings.Settings.Diagnostics.Export.lastErrorsBlock(body)
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    func copyRuntimePythonCandidatesToClipboard() {
        let body = store.aiRuntimePythonCandidatesText.trimmingCharacters(in: .whitespacesAndNewlines)
        let out = HubDiagnosticsBundleExporter.redactTextForSharing(
            HubUIStrings.Settings.Diagnostics.Export.pythonCandidatesBlock(
                body.isEmpty ? HubUIStrings.Settings.Diagnostics.noneField : body
            )
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    func copyXHubLocalServiceRecoveryToClipboard(_ guidance: XHubLocalServiceRecoveryGuidance) {
        let out = HubDiagnosticsBundleExporter.redactTextForSharing(guidance.clipboardText)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    func copyLocalRuntimeRepairSummary(_ summary: LocalRuntimeRepairSurfaceSummary) {
        let out = HubDiagnosticsBundleExporter.redactTextForSharing(summary.clipboardText)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    private func copyIssueSnippetToClipboard(snapshot: HubLaunchStatusSnapshot?) {
        let state = snapshot?.state.rawValue ?? "unknown"
        let root = renderRootCauseText(snapshot?.rootCause)
        let blocked = snapshot?.degraded.blockedCapabilities ?? []
        let rtErr = store.aiRuntimeLastError.trimmingCharacters(in: .whitespacesAndNewlines)
        let rtStatus = store.aiRuntimeStatusText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rtDoctor = store.aiRuntimeDoctorSummaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rtInstallHints = store.aiRuntimeInstallHintsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rtProviders = store.aiRuntimeProviderSummaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rtPythonCandidates = store.aiRuntimePythonCandidatesText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rtMonitor = store.aiRuntimeStatusSnapshot?.runtimeMonitorOperatorSummary(ttl: AIRuntimeStatus.recommendedHeartbeatTTL)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var lines: [String] = []
        lines.append(HubUIStrings.Settings.Diagnostics.Export.stateLine(state))
        if let id = snapshot?.launchId.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.launchIDLine(id))
        }
        if let snapshot, snapshot.updatedAtMs > 0 {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.updatedAtLine(formatEpochMs(snapshot.updatedAtMs)))
        }
        lines.append(HubUIStrings.Settings.Diagnostics.Export.rootCauseBlock(root.isEmpty ? HubUIStrings.Settings.Diagnostics.noneField : root))
        lines.append(
            HubUIStrings.Settings.Diagnostics.Export.blockedCapabilitiesBlock(
                blocked.isEmpty ? HubUIStrings.Settings.Diagnostics.noneField : blocked.joined(separator: "\n")
            )
        )
        if !rtStatus.isEmpty {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.runtimeStatusBlock(rtStatus))
        }
        if !rtDoctor.isEmpty {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.runtimeDoctorBlock(rtDoctor))
        }
        if !rtInstallHints.isEmpty {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.runtimeInstallHintsBlock(rtInstallHints))
        }
        if let guidance = xhubLocalServiceRecoveryGuidance {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.localServiceRecoveryBlock(guidance.clipboardText))
        }
        if !rtProviders.isEmpty {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.runtimeProvidersBlock(rtProviders))
        }
        if !rtPythonCandidates.isEmpty {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.runtimePythonCandidatesBlock(rtPythonCandidates))
        }
        if !rtMonitor.isEmpty {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.runtimeMonitorBlock(rtMonitor))
        }
        if !rtErr.isEmpty {
            lines.append(HubUIStrings.Settings.Diagnostics.Export.runtimeLastErrorBlock(rtErr))
        }
        lines.append(
            HubUIStrings.Settings.Diagnostics.Export.remoteAccessBlock(
                remoteAccessDiagnosticsSummaryForClipboard()
            )
        )
        lines.append(
            HubUIStrings.Settings.Diagnostics.Export.unifiedDoctorReportBlock(
                unifiedDoctorReportSummaryForClipboard()
            )
        )
        lines.append(
            HubUIStrings.Settings.Diagnostics.Export.diagnosticsBundleBlock(
                diagnosticsBundleArchivePath.isEmpty ? HubUIStrings.Settings.Diagnostics.missingField : diagnosticsBundleArchivePath
            )
        )

        let out = HubDiagnosticsBundleExporter.redactTextForSharing(lines.joined(separator: "\n\n"))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    func localServiceRecoverySeverityColor(_ severity: String) -> Color {
        switch severity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "high":
            return .red
        case "medium":
            return .orange
        default:
            return .secondary
        }
    }

    private func exportDiagnosticsBundle() {
        Task { await exportDiagnosticsBundleAsync() }
    }

    private func exportUnifiedDoctorReport() {
        Task { await exportUnifiedDoctorReportAsync() }
    }

    func reloadAXConstitutionStatus() {
        axConstitutionErrorText = ""
        axConstitutionVersion = ""
        axConstitutionEnabledClauseIds = []

        let url = store.axConstitutionURL()
        guard let data = try? Data(contentsOf: url) else {
            // Missing is common before the first runtime start.
            return
        }
        do {
            let raw = try JSONSerialization.jsonObject(with: data, options: [])
            guard let obj = raw as? [String: Any] else {
                axConstitutionErrorText = HubUIStrings.Settings.Advanced.Constitution.invalidJSONShape
                return
            }
            if let v = obj["version"] as? String {
                axConstitutionVersion = v
            } else {
                axConstitutionVersion = ""
            }

            var enabled: [String] = []
            if let clauses = obj["clauses"] as? [Any] {
                for item in clauses {
                    guard let c = item as? [String: Any] else { continue }
                    guard let cid = c["id"] as? String else { continue }
                    if (c["default"] as? Bool) == true {
                        enabled.append(cid)
                    }
                }
            }
            enabled.sort()
            axConstitutionEnabledClauseIds = enabled
        } catch {
            axConstitutionErrorText = error.localizedDescription
        }
    }

    func copyAXConstitutionSummaryToClipboard() {
        let url = store.axConstitutionURL()
        let ver = axConstitutionVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let enabled = axConstitutionEnabledClauseIds

        var lines: [String] = []
        lines.append(HubUIStrings.Settings.Advanced.Constitution.summaryPath(url.path))
        lines.append(
            HubUIStrings.Settings.Advanced.Constitution.summaryVersion(
                ver.isEmpty ? HubUIStrings.Settings.Advanced.Constitution.unknown : ver
            )
        )
        lines.append(
            HubUIStrings.Settings.Advanced.Constitution.summaryEnabledDefaultClauses(
                enabled.isEmpty ? HubUIStrings.Settings.Advanced.Constitution.none : enabled.joined(separator: ",")
            )
        )

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    @MainActor
    private func exportDiagnosticsBundleAsync() async {
        if diagnosticsBundleIsExporting { return }
        diagnosticsBundleIsExporting = true
        diagnosticsBundleError = ""
        diagnosticsBundleArchivePath = ""
        diagnosticsBundleManifestPath = ""
        diagnosticsBundleMissingFiles = []
        defer { diagnosticsBundleIsExporting = false }

        let adminToken = grpc.localAdminToken()
        let grpcPort = grpc.port

        do {
            let res: HubDiagnosticsBundleExporter.ExportResult = try await Task.detached(priority: .utility) {
                try await HubDiagnosticsBundleExporter.exportDiagnosticsBundle(
                    redactTokens: true,
                    operatorChannelAdminToken: adminToken,
                    operatorChannelGRPCPort: grpcPort
                )
            }.value

            diagnosticsBundleArchivePath = res.archivePath
            diagnosticsBundleManifestPath = res.manifestPath
            diagnosticsBundleMissingFiles = res.missingFiles

            // Copy the archive path for quick sharing in GitHub issues/Slack.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(res.archivePath, forType: .string)
        } catch {
            diagnosticsBundleError = error.localizedDescription
        }
    }

    @MainActor
    private func exportUnifiedDoctorReportAsync() async {
        if unifiedDoctorReportIsExporting { return }
        unifiedDoctorReportIsExporting = true
        unifiedDoctorReportError = ""
        unifiedDoctorReportPath = ""
        unifiedDoctorChannelReportPath = ""
        defer { unifiedDoctorReportIsExporting = false }

        let blockedCapabilities = hubLaunchStatus?.degraded.blockedCapabilities ?? []
        let adminToken = grpc.localAdminToken()
        let grpcPort = grpc.port
        let result: HubDiagnosticsBundleExporter.UnifiedDoctorReportsResult = await Task.detached(priority: .utility) {
            await HubDiagnosticsBundleExporter.exportUnifiedDoctorReports(
                status: AIRuntimeStatusStorage.load(),
                blockedCapabilities: blockedCapabilities,
                statusURL: AIRuntimeStatusStorage.url(),
                operatorChannelAdminToken: adminToken,
                operatorChannelGRPCPort: grpcPort,
                surface: .hubUI
            )
        }.value

        unifiedDoctorReportPath = result.runtimeReportPath
        unifiedDoctorChannelReportPath = result.channelOnboardingReportPath

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(unifiedDoctorReportSummaryForClipboard(), forType: .string)
    }

    private func openLaunchStatusFile(primary: URL, fallback: URL) {
        let fm = FileManager.default
        if fm.fileExists(atPath: primary.path) {
            NSWorkspace.shared.activateFileViewerSelecting([primary])
            return
        }
        if fm.fileExists(atPath: fallback.path) {
            NSWorkspace.shared.activateFileViewerSelecting([fallback])
            return
        }
        // No file found yet; open the primary directory so users can see where to look.
        NSWorkspace.shared.open(primary.deletingLastPathComponent())
    }

    private func pathLine(_ label: String, url: URL) -> String {
        let fm = FileManager.default
        let exists = fm.fileExists(atPath: url.path)
        return HubUIStrings.Settings.Diagnostics.pathLine(label: label, path: url.path, exists: exists)
    }

    private func hubDoctorCompanionPaths(for reportPath: String) -> (snapshotPath: String, recoveryGuidancePath: String) {
        let normalized = reportPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return (
                snapshotPath: HubUIStrings.Settings.Diagnostics.missingField,
                recoveryGuidancePath: HubUIStrings.Settings.Diagnostics.missingField
            )
        }
        let baseURL = URL(fileURLWithPath: normalized, isDirectory: false).deletingLastPathComponent()
        return (
            snapshotPath: baseURL.appendingPathComponent("xhub_local_service_snapshot.redacted.json").path,
            recoveryGuidancePath: baseURL.appendingPathComponent("xhub_local_service_recovery_guidance.redacted.json").path
        )
    }

    private func unifiedDoctorReportSummaryForClipboard() -> String {
        let companionPaths = hubDoctorCompanionPaths(for: unifiedDoctorReportPath)
        let companionSummary = HubUIStrings.Settings.Diagnostics.companionFiles(
            runtimeReportPath: unifiedDoctorReportPath.isEmpty ? HubUIStrings.Settings.Diagnostics.missingField : unifiedDoctorReportPath,
            snapshotPath: companionPaths.snapshotPath,
            recoveryGuidancePath: companionPaths.recoveryGuidancePath,
            channelOnboardingPath: unifiedDoctorChannelReportPath.isEmpty ? HubUIStrings.Settings.Diagnostics.missingField : unifiedDoctorChannelReportPath
        )
        return [
            companionSummary,
            HubUIStrings.Settings.Diagnostics.Export.remoteAccessBlock(remoteAccessDiagnosticsSummaryForClipboard()),
        ].joined(separator: "\n\n")
    }

    private func remoteAccessDiagnosticsSummaryForClipboard() -> String {
        let health = grpcRemoteAccessHealthSummary
        let route = remoteRouteProbe.snapshot
        let host = grpc.xtTerminalInternetHost?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let routeAddresses = route.addresses.isEmpty
            ? HubUIStrings.Settings.Diagnostics.noneField
            : route.addresses.joined(separator: ", ")
        let securePackState = grpc.secureRemoteSetupPackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "unavailable"
            : "ready"

        let lines: [String] = [
            "external_host: \(host.isEmpty ? HubUIStrings.Settings.Diagnostics.noneField : host)",
            "grpc_auto_start: \(grpc.autoStart ? "on" : "off")",
            "grpc_serving: \(grpc.isServingAvailable ? "on" : "off")",
            "invite_token: \(grpc.hasExternalInviteToken ? "issued" : "missing")",
            "keep_system_awake: \(servingPower.keepSystemAwakeWhileServing ? "on" : "off")",
            "keep_display_awake: \(servingPower.keepDisplayAwakeWhileServing ? "on" : "off")",
            "health_status: \(health.badgeText)",
            "health_headline: \(health.headline)",
            "health_detail: \(health.detail)",
            "health_access_scope: \(health.accessScopeText)",
            "health_operator_hint: \(health.operatorHintText)",
            "route_status: \(route.statusText)",
            "route_detail: \(route.detailText)",
            "route_addresses: \(routeAddresses)",
            "secure_remote_setup_pack: \(securePackState)",
        ]
        return lines.joined(separator: "\n")
    }

    private func unifiedDoctorRevealURLs() -> [URL] {
        var urls: [URL] = []
        let runtimePath = unifiedDoctorReportPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !runtimePath.isEmpty {
            urls.append(URL(fileURLWithPath: runtimePath))
        }
        let channelPath = unifiedDoctorChannelReportPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !channelPath.isEmpty {
            urls.append(URL(fileURLWithPath: channelPath))
        }
        return urls
    }

    private func deleteClientConfirmationMessage(_ client: HubGRPCClientEntry) -> String {
        let displayName = client.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? client.deviceId
            : client.name
        return HubUIStrings.Settings.GRPC.deleteClientConfirmation(displayName: displayName, deviceID: client.deviceId)
    }

    func grpcClientSecuritySummary(_ c: HubGRPCClientEntry) -> String {
        let caps = c.capabilities
        let cidrs = c.allowedCidrs
        let user = c.userId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cert = c.certSha256.trimmingCharacters(in: .whitespacesAndNewlines)

        let policyText: String = {
            if c.policyMode == .legacyGrant {
                return HubUIStrings.Settings.GRPC.DeviceList.legacyPolicyMode
            }
            guard let profile = c.approvedTrustProfile else {
                return HubUIStrings.Settings.GRPC.DeviceList.newProfileMissing
            }
            let paid = paidPolicyModeLabel(profile.paidModelPolicy.mode.rawValue)
            let web = HubUIStrings.Settings.GRPC.DeviceList.currentWebState(profile.networkPolicy.defaultWebFetchEnabled)
            let daily = HubUIStrings.Settings.GRPC.DeviceList.currentDailyBudget(profile.budgetPolicy.dailyTokenLimit)
            return HubUIStrings.Settings.GRPC.DeviceList.policyProfileSummary(paid: paid, web: web, daily: daily)
        }()
        let capsText = HubUIStrings.Settings.GRPC.DeviceList.capabilities(caps)
        let cidrText = HubUIStrings.Settings.GRPC.DeviceList.sourceIPs(cidrs)
        let certText = HubUIStrings.Settings.GRPC.DeviceList.mtlsFingerprint(cert)
        let userText = HubUIStrings.Settings.GRPC.DeviceList.user(user)
        return HubUIStrings.Settings.GRPC.DeviceList.securitySummary(
            policy: policyText,
            user: userText,
            caps: capsText,
            cidr: cidrText,
            cert: certText
        )
    }

    func grpcClientPaidPolicySummary(_ client: HubGRPCClientEntry) -> String {
        if client.policyMode == .legacyGrant {
            let paidEnabled = client.capabilities.contains { cap in
                cap.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ai.generate.paid"
            }
            return paidEnabled
                ? HubUIStrings.Settings.GRPC.DeviceList.paidRouteLegacyOn
                : HubUIStrings.Settings.GRPC.DeviceList.paidRouteLegacyOff
        }

        guard let profile = client.approvedTrustProfile else {
            return HubUIStrings.Settings.GRPC.DeviceList.paidRouteProfileMissing
        }

        switch profile.paidModelPolicy.mode {
        case .off:
            return HubUIStrings.Settings.GRPC.DeviceList.paidRouteOff
        case .allPaidModels:
            return HubUIStrings.Settings.GRPC.DeviceList.paidRouteAll
        case .customSelectedModels:
            let models = profile.paidModelPolicy.allowedModelIds
            if models.isEmpty {
                return HubUIStrings.Settings.GRPC.DeviceList.paidRouteCustomEmpty
            }
            let preview = models.prefix(3).joined(separator: ", ")
            return HubUIStrings.Settings.GRPC.DeviceList.paidRouteCustom(
                count: models.count,
                preview: preview,
                extraCount: max(0, models.count - 3)
            )
        }
    }

    struct GRPCClientNetworkAccessSnapshot {
        var clientEnabled: Bool
        var paidEnabled: Bool
        var webEnabled: Bool
        var usesPolicyProfile: Bool

        var policyGrantsNetwork: Bool {
            paidEnabled || webEnabled
        }

        var canNetwork: Bool {
            clientEnabled && policyGrantsNetwork
        }
    }

    func grpcClientNetworkAccessSnapshot(_ client: HubGRPCClientEntry) -> GRPCClientNetworkAccessSnapshot {
        if client.policyMode == .newProfile, let profile = client.approvedTrustProfile {
            return GRPCClientNetworkAccessSnapshot(
                clientEnabled: client.enabled,
                paidEnabled: profile.paidModelPolicy.mode != .off,
                webEnabled: profile.networkPolicy.defaultWebFetchEnabled,
                usesPolicyProfile: true
            )
        }
        let caps = Set(client.capabilities.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        return GRPCClientNetworkAccessSnapshot(
            clientEnabled: client.enabled,
            paidEnabled: caps.contains("ai.generate.paid"),
            webEnabled: caps.contains("web.fetch"),
            usesPolicyProfile: false
        )
    }

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

    private func grpcClientHasBlockedState(_ status: GRPCDeviceStatusEntry?) -> Bool {
        guard let status else { return false }
        if status.blockedToday > 0 {
            return true
        }
        if !status.lastBlockedReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return !status.lastDenyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func grpcPairingRepairDeniedAttempts(limit: Int) -> [GRPCDeniedAttemptEntry] {
        grpcDeniedAttempts.attempts
            .filter { attempt in
                grpcDeniedAttemptLooksLikePairingRepair(attempt.reason)
                    || grpcDeniedAttemptLooksLikePairingRepair(attempt.message)
            }
            .sorted { lhs, rhs in
                if lhs.lastSeenAtMs != rhs.lastSeenAtMs {
                    return lhs.lastSeenAtMs > rhs.lastSeenAtMs
                }
                return lhs.count > rhs.count
            }
            .prefix(limit)
            .map { $0 }
    }

    private func grpcPairingRepairCandidateClients(
        _ clients: [HubGRPCClientEntry],
        statusById: [String: GRPCDeviceStatusEntry]
    ) -> [HubGRPCClientEntry] {
        clients.filter { client in
            client.deviceId != "terminal_device" && grpcClientPresenceCountsAsStale(statusById[client.deviceId])
        }
    }

    @ViewBuilder
    func grpcPairingRepairCard(statusById: [String: GRPCDeviceStatusEntry]) -> some View {
        let staleClients = grpcPairingRepairCandidateClients(grpc.allowedClients, statusById: statusById)
        let pairingRepairDeniedAttempts = grpcPairingRepairDeniedAttempts(limit: 3)
        let singleRepairCandidate = staleClients.count == 1 ? staleClients.first : nil

        if !staleClients.isEmpty || !pairingRepairDeniedAttempts.isEmpty {
            quickFixCard(
                title: HubUIStrings.Settings.GRPC.pairingRepairTitle,
                summary: grpcPairingRepairSummary(
                    staleClients: staleClients,
                    deniedAttempts: pairingRepairDeniedAttempts
                ),
                steps: [
                    HubUIStrings.Settings.GRPC.pairingRepairStepClearXT,
                    HubUIStrings.Settings.GRPC.pairingRepairStepDeleteHub,
                    HubUIStrings.Settings.GRPC.pairingRepairStepReconnect,
                ]
            ) {
                if !staleClients.isEmpty {
                    Button(HubUIStrings.Settings.GRPC.filterStaleOnly) {
                        grpcClientListFilter = .stale
                    }
                }
                if let singleRepairCandidate {
                    Button(HubUIStrings.Settings.GRPC.deleteOldDevice) {
                        deletingGRPCClient = singleRepairCandidate
                    }
                    .foregroundStyle(.red)
                }
                Button(HubUIStrings.Settings.GRPC.openDeviceListFile) {
                    grpc.openClientsConfig()
                }
            }
        }
    }

    private func grpcDeniedAttemptLooksLikePairingRepair(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return false }
        return text.contains("unauthenticated")
            || text.contains("mtls_client_certificate_required")
            || text.contains("certificate_required")
            || text.contains("pairing_health_failed")
            || text.contains("bootstrap_refresh_failed")
            || text.contains("missing_pairing_secret")
            || text.contains("discover_failed_using_cached_profile")
    }

    private func grpcPairingRepairSummary(
        staleClients: [HubGRPCClientEntry],
        deniedAttempts: [GRPCDeniedAttemptEntry]
    ) -> String {
        var parts: [String] = []
        if !staleClients.isEmpty {
            let names = staleClients.prefix(2).map(grpcClientDisplayName)
            if staleClients.count == 1, let name = names.first {
                parts.append(HubUIStrings.Settings.GRPC.pairingRepairFoundOne(name))
            } else {
                let preview = names.joined(separator: "、")
                parts.append(HubUIStrings.Settings.GRPC.pairingRepairFoundMany(count: staleClients.count, preview: preview))
            }
        }
        if !deniedAttempts.isEmpty {
            let names = deniedAttempts.prefix(2).map(grpcDeniedAttemptDisplayName)
            parts.append(HubUIStrings.Settings.GRPC.pairingRepairDenied(names.joined(separator: "、")))
        }
        if parts.isEmpty {
            return HubUIStrings.Settings.GRPC.pairingRepairDefaultSummary
        }
        parts.append(HubUIStrings.Settings.GRPC.pairingRepairClosing)
        return parts.joined(separator: " ")
    }

    func grpcClientDisplayName(_ client: HubGRPCClientEntry) -> String {
        let name = client.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? client.deviceId : name
    }

    private func grpcDeniedAttemptDisplayName(_ attempt: GRPCDeniedAttemptEntry) -> String {
        let name = attempt.clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let device = attempt.deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return name
        }
        if !device.isEmpty {
            return device
        }
        return HubUIStrings.Settings.GRPC.DeviceList.unknownDevice
    }

    func grpcClientQuickActionHint(_ snapshot: GRPCClientNetworkAccessSnapshot) -> String {
        if !snapshot.clientEnabled {
            return HubUIStrings.Settings.GRPC.DeviceList.quickActionEnableFirst
        }
        if snapshot.policyGrantsNetwork {
            return HubUIStrings.Settings.GRPC.DeviceList.quickActionCutOffOnly
        }
        return HubUIStrings.Settings.GRPC.DeviceList.quickActionRestoreWebOnly
    }

    @ViewBuilder
    func grpcClientNetworkPill(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.monospaced())
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    func grpcRemoteHealthColor(_ state: HubRemoteAccessHealthSummary.State) -> Color {
        switch state {
        case .ready:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }

    func grpcRemoteRouteColor(_ state: HubRemoteAccessRouteProbeSnapshot.State) -> Color {
        switch state {
        case .idle, .skipped:
            return .secondary
        case .resolving:
            return .blue
        case .resolved:
            return .green
        case .failed:
            return .red
        }
    }

    func grpcCutOffNetworkAccess(_ client: HubGRPCClientEntry) {
        var updated = client
        if client.policyMode == .newProfile, var profile = client.approvedTrustProfile {
            profile.paidModelPolicy = HubPairedTerminalPaidModelPolicy(mode: .off, allowedModelIds: [])
            profile.networkPolicy = HubPairedTerminalNetworkPolicy(defaultWebFetchEnabled: false)
            profile.capabilities = HubGRPCClientEntry.derivedCapabilities(
                requestedCapabilities: profile.capabilities,
                paidModelSelectionMode: .off,
                defaultWebFetchEnabled: false
            )
            updated.approvedTrustProfile = profile
            updated.capabilities = profile.capabilities
        } else {
            updated.capabilities = client.capabilities.filter {
                let lowered = $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return lowered != "ai.generate.paid" && lowered != "web.fetch"
            }
        }
        grpc.upsertClient(updated)
    }

    func grpcSetWebFetchEnabled(_ client: HubGRPCClientEntry, enabled: Bool) {
        var updated = client
        if client.policyMode == .newProfile, var profile = client.approvedTrustProfile {
            profile.networkPolicy = HubPairedTerminalNetworkPolicy(defaultWebFetchEnabled: enabled)
            profile.capabilities = HubGRPCClientEntry.derivedCapabilities(
                requestedCapabilities: profile.capabilities,
                paidModelSelectionMode: profile.paidModelPolicy.mode,
                defaultWebFetchEnabled: enabled
            )
            updated.approvedTrustProfile = profile
            updated.capabilities = profile.capabilities
        } else {
            var caps = client.capabilities.filter {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "web.fetch"
            }
            if enabled {
                caps.append("web.fetch")
            }
            updated.capabilities = HubGRPCClientEntry.normalizedStrings(caps)
        }
        grpc.upsertClient(updated)
    }

    private func grpcSetDailyBudget(
        _ client: HubGRPCClientEntry,
        dailyTokenLimit: Int
    ) {
        guard client.policyMode == .newProfile, var profile = client.approvedTrustProfile else {
            remoteQuotaActionText = ""
            remoteQuotaErrorText = "预算设定当前只支持已启用新策略档案的 XT。"
            return
        }

        let currentLimit = max(1, profile.budgetPolicy.dailyTokenLimit)
        let updatedLimit = max(1, dailyTokenLimit)
        guard updatedLimit != currentLimit else { return }

        profile.budgetPolicy = HubPairedTerminalBudgetPolicy(
            dailyTokenLimit: updatedLimit,
            singleRequestTokenLimit: max(1, profile.budgetPolicy.singleRequestTokenLimit)
        )

        var updated = client
        updated.approvedTrustProfile = profile
        grpc.upsertClient(updated)

        remoteQuotaErrorText = ""
        remoteQuotaActionText = "\(client.name.isEmpty ? client.deviceId : client.name) 日预算已调整为 \(terminalAccessIntText(Int64(updatedLimit))) tokens。"
    }

    func grpcAdjustDailyBudget(
        _ client: HubGRPCClientEntry,
        delta: Int
    ) {
        let currentLimit = max(1, client.approvedTrustProfile?.budgetPolicy.dailyTokenLimit ?? 1)
        grpcSetDailyBudget(client, dailyTokenLimit: currentLimit + delta)
    }

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

    private func grpcClientPresenceSortRank(_ status: GRPCDeviceStatusEntry?) -> Int {
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

    private static let grpcClientPresenceSnapshotStaleMs: Int64 = 15_000
    private static let grpcClientPresenceStaleMs: Int64 = 12 * 60 * 60 * 1000


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

    private enum GRPCClientExecutionState {
        case remoteCompleted
        case localCompleted
        case downgradedToLocal
        case denied
        case failed
        case canceled
        case unknown
    }

    private func grpcClientExecutionState(_ st: GRPCDeviceStatusEntry) -> GRPCClientExecutionState {
        guard let activity = st.lastActivity else { return .unknown }
        let eventType = activity.eventType.trimmingCharacters(in: .whitespacesAndNewlines)
        switch eventType {
        case "ai.generate.downgraded_to_local":
            return .downgradedToLocal
        case "ai.generate.completed":
            return activity.networkAllowed ? .remoteCompleted : .localCompleted
        case "ai.generate.denied":
            return .denied
        case "ai.generate.failed":
            return .failed
        case "ai.generate.canceled":
            return .canceled
        default:
            return .unknown
        }
    }

    func grpcClientExecutionPillTitle(_ st: GRPCDeviceStatusEntry) -> String {
        switch grpcClientExecutionState(st) {
        case .remoteCompleted:
            return HubUIStrings.Settings.GRPC.DeviceList.executionRemote
        case .localCompleted:
            return HubUIStrings.Settings.GRPC.DeviceList.executionLocal
        case .downgradedToLocal:
            return HubUIStrings.Settings.GRPC.DeviceList.executionDowngraded
        case .denied:
            return HubUIStrings.Settings.GRPC.DeviceList.executionDenied
        case .failed:
            return HubUIStrings.Settings.GRPC.DeviceList.executionFailed
        case .canceled:
            return HubUIStrings.Settings.GRPC.DeviceList.executionCanceled
        case .unknown:
            return HubUIStrings.Settings.GRPC.DeviceList.executionUnknown
        }
    }

    func grpcClientExecutionPillColor(_ st: GRPCDeviceStatusEntry) -> Color {
        switch grpcClientExecutionState(st) {
        case .remoteCompleted:
            return .green
        case .localCompleted:
            return .secondary
        case .downgradedToLocal:
            return .orange
        case .denied, .failed:
            return .red
        case .canceled:
            return .orange
        case .unknown:
            return .secondary
        }
    }

    func grpcClientActualExecutionSummary(_ st: GRPCDeviceStatusEntry) -> String {
        guard let activity = st.lastActivity else {
            let topModel = st.topModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !topModel.isEmpty {
                return HubUIStrings.Settings.GRPC.DeviceList.executionSummaryWithTopModel(topModel)
            }
            return HubUIStrings.Settings.GRPC.DeviceList.actualExecutionNoDetail
        }

        let model = activity.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = activity.errorCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = activity.errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModel = model.isEmpty ? HubUIStrings.Settings.GRPC.DeviceList.noReportedModel : model

        switch grpcClientExecutionState(st) {
        case .remoteCompleted:
            return HubUIStrings.Settings.GRPC.DeviceList.actualExecutionRemote(resolvedModel)
        case .localCompleted:
            return HubUIStrings.Settings.GRPC.DeviceList.actualExecutionLocal(resolvedModel)
        case .downgradedToLocal:
            let reason = !code.isEmpty ? code : (!message.isEmpty ? message : HubUIStrings.Settings.GRPC.DeviceList.downgradedFallback)
            return HubUIStrings.Settings.GRPC.DeviceList.actualExecutionDowngraded(model: resolvedModel, reason: reason)
        case .denied:
            let reason = !code.isEmpty ? code : (!message.isEmpty ? message : HubUIStrings.Settings.GRPC.DeviceList.deniedFallback)
            return HubUIStrings.Settings.GRPC.DeviceList.actualExecutionDenied(reason)
        case .failed:
            let reason = !code.isEmpty ? code : (!message.isEmpty ? message : HubUIStrings.Settings.GRPC.DeviceList.failedFallback)
            return HubUIStrings.Settings.GRPC.DeviceList.actualExecutionFailed(reason)
        case .canceled:
            return HubUIStrings.Settings.GRPC.DeviceList.actualExecutionCanceled
        case .unknown:
            let eventType = activity.eventType.trimmingCharacters(in: .whitespacesAndNewlines)
            if eventType.isEmpty {
                return HubUIStrings.Settings.GRPC.DeviceList.actualExecutionIncomplete
            }
            return HubUIStrings.Settings.GRPC.DeviceList.actualExecutionUnknown(eventType: eventType, model: resolvedModel)
        }
    }

    func grpcClientLastBlockedSummary(_ st: GRPCDeviceStatusEntry) -> String {
        let reason = st.lastBlockedReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = st.lastDenyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if reason.isEmpty && code.isEmpty { return HubUIStrings.Settings.GRPC.DeviceList.lastBlockedNone }
        if reason.isEmpty { return HubUIStrings.Settings.GRPC.DeviceList.lastBlocked(code) }
        if code.isEmpty { return HubUIStrings.Settings.GRPC.DeviceList.lastBlocked(reason) }
        return HubUIStrings.Settings.GRPC.DeviceList.lastBlocked(reason: reason, code: code)
    }

    func grpcClientModelBreakdownSummary(_ row: GRPCDeviceModelBreakdownEntry) -> String {
        var parts: [String] = [row.modelId]
        parts.append(HubUIStrings.Settings.GRPC.DeviceList.tokenUsage(row.totalTokens))
        parts.append(HubUIStrings.Settings.GRPC.DeviceList.requests(row.requestCount))
        if row.blockedCount > 0 { parts.append(HubUIStrings.Settings.GRPC.DeviceList.blocked(row.blockedCount)) }
        if row.lastUsedAtMs > 0 { parts.append(HubUIStrings.Settings.GRPC.DeviceList.recent(formatMs(row.lastUsedAtMs))) }
        if row.lastBlockedAtMs > 0 {
            let code = row.lastDenyCode.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append(code.isEmpty ? HubUIStrings.Settings.GRPC.DeviceList.denyRecorded : HubUIStrings.Settings.GRPC.DeviceList.denyCode(code))
        }
        return HubUIStrings.Settings.GRPC.DeviceList.summary(parts)
    }

    private func paidPolicyModeLabel(_ raw: String) -> String {
        HubUIStrings.Settings.GRPC.DeviceList.policyModeLabel(raw)
    }

    func grpcClientLastActivitySummary(_ a: GRPCDeviceLastActivity) -> String {
        let model = a.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cap = a.capability.trimmingCharacters(in: .whitespacesAndNewlines)
        let at = a.createdAtMs > 0 ? formatMs(a.createdAtMs) : ""
        let eventType = a.eventType.trimmingCharacters(in: .whitespacesAndNewlines)

        var parts: [String] = []
        if !eventType.isEmpty {
            parts.append(HubUIStrings.Settings.GRPC.DeviceList.audit(eventType))
        } else if !model.isEmpty {
            parts.append(HubUIStrings.Settings.GRPC.DeviceList.audit(model))
        } else {
            parts.append(HubUIStrings.Settings.GRPC.DeviceList.auditUnknown)
        }

        if !model.isEmpty { parts.append(HubUIStrings.Settings.GRPC.DeviceList.model(model)) }
        if !cap.isEmpty { parts.append(cap) }
        parts.append(HubUIStrings.Settings.GRPC.DeviceList.network(a.networkAllowed))
        if a.totalTokens > 0 { parts.append(HubUIStrings.Settings.GRPC.DeviceList.tokenUsage(a.totalTokens)) }
        parts.append(HubUIStrings.Settings.GRPC.DeviceList.ok(a.ok))
        if !at.isEmpty { parts.append(at) }
        if !a.ok {
            let code = a.errorCode.trimmingCharacters(in: .whitespacesAndNewlines)
            if !code.isEmpty { parts.append(code) }
        }
        return HubUIStrings.Settings.GRPC.DeviceList.summary(parts)
    }

    func formatMs(_ ms: Int64) -> String {
        let secs = Double(ms) / 1000.0
        let d = Date(timeIntervalSince1970: secs)
        let f = DateFormatter()
        f.dateFormat = HubUIStrings.Formatting.dateTimeWithSeconds
        return f.string(from: d)
    }

    static let remoteModeGuideText = HubUIStrings.Settings.GRPC.remoteAccessGuideChecklist

    private func providerKeyFlowLinkKind(
        _ consumer: RemoteQuotaCenterClientProjection,
        vendorFamilyKeys: Set<String>,
        matchedFamilyCount: Int
    ) -> ProviderKeyFlowLinkKind {
        if consumer.allowsAllFamilies {
            return .elastic
        }
        let consumerFamilyKeys = Set(consumer.familyKeys)
        if matchedFamilyCount > 0 && consumerFamilyKeys.isSubset(of: vendorFamilyKeys) {
            return .dedicated
        }
        return .shared
    }

    private func providerKeyFlowChains(
        vendors: [ProviderKeyVendorInventorySummary],
        users: [RemoteQuotaCenterUserProjection],
        consumers: [RemoteQuotaCenterClientProjection],
        focusedVendor: ProviderKeyVendorInventorySummary?
    ) -> [ProviderKeyFlowChainSummary] {
        let userByConsumerID = Dictionary(
            uniqueKeysWithValues: users.flatMap { user in
                user.consumers.map { consumer in
                    (consumer.id, user)
                }
            }
        )

        func makeChains(relaxed: Bool) -> [ProviderKeyFlowChainSummary] {
            var chains: [ProviderKeyFlowChainSummary] = []

            for vendor in vendors {
                let vendorFamilyKeys = Set(vendor.familyKeys)
                guard !vendorFamilyKeys.isEmpty else { continue }

                for consumer in consumers {
                    let matchedFamilyCount: Int = {
                        if consumer.allowsAllFamilies {
                            return vendorFamilyKeys.count
                        }
                        return Set(consumer.familyKeys).intersection(vendorFamilyKeys).count
                    }()

                    guard matchedFamilyCount > 0 else { continue }
                    guard let user = userByConsumerID[consumer.id] else { continue }

                    let linkKind = providerKeyFlowLinkKind(
                        consumer,
                        vendorFamilyKeys: vendorFamilyKeys,
                        matchedFamilyCount: matchedFamilyCount
                    )
                    let vendorObservedDailyTokensUsed = providerKeyVendorObservedDailyTokensUsed(
                        consumer,
                        familyKeys: vendorFamilyKeys
                    )
                    let hasBudgetSignal = consumer.dailyTokenLimit > 0 || user.allocatedDailyTokenBudget > 0
                    let hasRiskSignal = providerKeyConsumerAtRisk(consumer) || providerKeyUserAtRisk(user)
                    let shouldInclude: Bool = {
                        if vendorObservedDailyTokensUsed > 0 { return true }
                        if hasRiskSignal { return true }
                        if linkKind == .dedicated && hasBudgetSignal { return true }
                        if relaxed && hasBudgetSignal { return true }
                        if relaxed && focusedVendor != nil { return true }
                        return false
                    }()

                    guard shouldInclude else { continue }

                    chains.append(
                        ProviderKeyFlowChainSummary(
                            vendor: vendor,
                            user: user,
                            consumer: consumer,
                            linkKind: linkKind,
                            matchedFamilyCount: matchedFamilyCount,
                            vendorObservedDailyTokensUsed: vendorObservedDailyTokensUsed
                        )
                    )
                }
            }

            return chains.sorted { lhs, rhs in
                let leftRisk = providerKeyVendorAtRisk(lhs.vendor)
                    || providerKeyUserAtRisk(lhs.user)
                    || providerKeyConsumerAtRisk(lhs.consumer)
                let rightRisk = providerKeyVendorAtRisk(rhs.vendor)
                    || providerKeyUserAtRisk(rhs.user)
                    || providerKeyConsumerAtRisk(rhs.consumer)
                if leftRisk != rightRisk {
                    return leftRisk && !rightRisk
                }
                if lhs.vendorObservedDailyTokensUsed != rhs.vendorObservedDailyTokensUsed {
                    return lhs.vendorObservedDailyTokensUsed > rhs.vendorObservedDailyTokensUsed
                }
                if lhs.linkKind != rhs.linkKind {
                    return lhs.linkKind < rhs.linkKind
                }
                if lhs.matchedFamilyCount != rhs.matchedFamilyCount {
                    return lhs.matchedFamilyCount > rhs.matchedFamilyCount
                }
                if lhs.vendor.allocationHeadroom != rhs.vendor.allocationHeadroom {
                    return lhs.vendor.allocationHeadroom < rhs.vendor.allocationHeadroom
                }
                if lhs.consumer.dailyTokenLimit != rhs.consumer.dailyTokenLimit {
                    return lhs.consumer.dailyTokenLimit > rhs.consumer.dailyTokenLimit
                }
                return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
            }
        }

        let preferred = makeChains(relaxed: false)
        if !preferred.isEmpty {
            return Array(preferred.prefix(6))
        }
        return Array(makeChains(relaxed: true).prefix(6))
    }

    private func providerKeyScopeOverview(
        focusedUser: RemoteQuotaCenterUserProjection?,
        focusedVendorDisplayName: String?,
        scopedUsers: [RemoteQuotaCenterUserProjection],
        scopedConsumers: [RemoteQuotaCenterClientProjection],
        families: [ProviderKeyFamilyInventorySummary]
    ) -> ProviderKeyScopeOverview {
        ProviderKeyScopeOverview(
            focusedUser: focusedUser,
            focusedVendorDisplayName: focusedVendorDisplayName,
            userCount: scopedUsers.count,
            consumerCount: scopedConsumers.count,
            connectedConsumerCount: scopedConsumers.filter(\.connected).count,
            xtConsumerCount: scopedConsumers.filter { $0.consumerKind == .pairedXT }.count,
            terminalConsumerCount: scopedConsumers.filter { $0.consumerKind == .terminalAccess }.count,
            allocatedDailyTokenBudget: scopedConsumers.reduce(Int64(0)) { $0 + max(Int64(0), $1.dailyTokenLimit) },
            unlimitedBudgetConsumerCount: scopedConsumers.filter { $0.dailyTokenLimit <= 0 }.count,
            observedConsumerTokensUsed: scopedConsumers.reduce(Int64(0)) { $0 + max(Int64(0), $1.dailyTokenUsed) },
            oversubscribedFamilyCount: families.filter(\.isOversubscribed).count
        )
    }

    private func providerKeyFamilyInventorySummaries(
        _ projection: RemoteQuotaCenterProjection,
        scopedUsers: [RemoteQuotaCenterUserProjection],
        scopedConsumers: [RemoteQuotaCenterClientProjection],
        focusedVendorFamilyKeys: Set<String>
    ) -> [ProviderKeyFamilyInventorySummary] {
        let scopedConsumerIDs = Set(scopedConsumers.map(\.id))
        let focusedUser = providerKeyFocusedUser(projection.users)
        let summaries = projection.families.map { family in
            let assignedConsumers = focusedUser == nil
                ? family.assignedConsumers
                : family.assignedConsumers.filter { scopedConsumerIDs.contains($0.id) }
            let assignedConsumerIDs = Set(assignedConsumers.map(\.id))
            let coveredUserCount = scopedUsers.filter { user in
                user.consumers.contains(where: { assignedConsumerIDs.contains($0.id) })
            }.count
            let observedDailyTokensUsed = scopedConsumers.reduce(Int64(0)) { partial, consumer in
                partial + consumer.observedDailyTokens(for: family.familyKey)
            }
            return ProviderKeyFamilyInventorySummary(
                familyProjection: family,
                coveredUserCount: coveredUserCount,
                assignedConsumers: assignedConsumers,
                assignedDailyTokenBudget: assignedConsumers.reduce(Int64(0)) { partial, consumer in
                    partial + max(Int64(0), consumer.dailyTokenLimit)
                },
                unlimitedBudgetConsumerCount: assignedConsumers.filter { $0.dailyTokenLimit <= 0 }.count,
                connectedAssignedConsumerCount: assignedConsumers.filter(\.connected).count,
                observedDailyTokensUsed: observedDailyTokensUsed
            )
        }

        let visibleSummaries: [ProviderKeyFamilyInventorySummary]
        if providerKeyHasFocusedVendor {
            visibleSummaries = summaries.filter { summary in
                focusedVendorFamilyKeys.contains(summary.familyKey)
                    && (!summary.assignedConsumers.isEmpty || summary.observedDailyTokensUsed > 0 || focusedUser == nil)
            }
        } else if focusedUser != nil {
            visibleSummaries = summaries.filter { !$0.assignedConsumers.isEmpty || $0.observedDailyTokensUsed > 0 }
        } else {
            visibleSummaries = summaries
        }

        return visibleSummaries.sorted(by: providerKeySortFamilyInventorySummary(_:_:))
    }

    private func providerKeyOverallTrendCard(
        scopeOverview: ProviderKeyScopeOverview,
        consumers: [RemoteQuotaCenterClientProjection],
        focusedVendor: ProviderKeyVendorInventorySummary?
    ) -> ProviderKeyTrendCardSummary? {
        if let focusedVendor {
            guard let aggregate = RemoteQuotaTrendSupport.aggregateEstimatedFamilyTrend(
                consumers: consumers,
                familyKeys: Set(focusedVendor.familyKeys)
            ) else {
                return nil
            }

            let title = scopeOverview.focusedUser == nil
                ? "\(focusedVendor.displayName) 下游趋势"
                : "\(scopeOverview.focusedUser?.displayName ?? "") · \(focusedVendor.displayName)"
            let subtitle = scopeOverview.focusedUser == nil
                ? "最近 1 小时命中该厂家家族的下游用量"
                : "当前用户最近 1 小时命中该厂家家族的用量"
            let footnote = aggregate.estimatedConsumerCount > 0
                ? "其中 \(aggregate.estimatedConsumerCount) 个 multi-family consumer 按今日家族命中占比估算，只用于判断 \(focusedVendor.displayName) 的热度变化。"
                : "这张总曲线只看 \(focusedVendor.displayName) 相关家族，便于判断这家现在是否还能继续发额度。"

            return ProviderKeyTrendCardSummary(
                id: "overall.vendor.\(focusedVendor.id)",
                title: title,
                subtitle: subtitle,
                footnote: footnote,
                systemName: scopeOverview.focusedUser == nil ? "building.2.crop.circle.fill" : "person.crop.circle.badge.clock",
                tint: providerKeyVendorAtRisk(focusedVendor) ? .orange : .indigo,
                aggregate: aggregate
            )
        }

        guard let aggregate = RemoteQuotaTrendSupport.aggregateConsumers(consumers) else {
            return nil
        }

        let title = scopeOverview.focusedUser == nil
            ? "全局下游趋势"
            : "\(scopeOverview.focusedUser?.displayName ?? "") 用量趋势"
        let subtitle = scopeOverview.focusedUser == nil
            ? "全部 XT / Terminal 最近 1 小时远端用量"
            : "当前用户相关 XT / Terminal 最近 1 小时远端用量"
        let footnote = scopeOverview.focusedUser == nil
            ? "这张总曲线只看下游消费者的真实 5m usage 桶，便于判断全局发额度的节奏。"
            : "先看这个用户整体是否在放量，再往下看家族和具体 consumer。"

        return ProviderKeyTrendCardSummary(
            id: "overall",
            title: title,
            subtitle: subtitle,
            footnote: footnote,
            systemName: scopeOverview.focusedUser == nil ? "waveform.path.ecg" : "person.crop.circle.badge.clock",
            tint: scopeOverview.focusedUser == nil ? .indigo : .teal,
            aggregate: aggregate
        )
    }

    private func providerKeyVendorTrendCards(
        _ vendors: [ProviderKeyVendorInventorySummary],
        scopedConsumers: [RemoteQuotaCenterClientProjection],
        focusedVendor: ProviderKeyVendorInventorySummary?
    ) -> [ProviderKeyTrendCardSummary] {
        guard focusedVendor == nil else { return [] }
        return vendors.compactMap { vendor in
            guard let aggregate = RemoteQuotaTrendSupport.aggregateEstimatedFamilyTrend(
                consumers: scopedConsumers,
                familyKeys: Set(vendor.familyKeys)
            ) else {
                return nil
            }

            let budgetSummary = vendor.assignedDailyTokenBudget > 0
                ? "覆盖预算 \(HubUIStrings.Settings.ProviderKeys.tokenCount(vendor.assignedDailyTokenBudget))"
                : (vendor.coveredUnlimitedConsumerCount > 0 ? "含弹性 consumer \(vendor.coveredUnlimitedConsumerCount)" : "当前无固定预算")
            let footnote = aggregate.estimatedConsumerCount > 0
                ? "其中 \(aggregate.estimatedConsumerCount) 个 multi-family consumer 按今日家族命中占比分摊到厂家，只用于判断热度变化。"
                : "全部来自该厂家相关 consumer 的真实 5m usage 桶。"

            return ProviderKeyTrendCardSummary(
                id: "vendor:\(vendor.id)",
                title: vendor.displayName,
                subtitle: "\(vendor.coveredUserCount) 用户 / \(vendor.coveredConsumerCount) consumer · \(budgetSummary)",
                footnote: footnote,
                systemName: "building.2.crop.circle",
                tint: providerKeyVendorAtRisk(vendor) ? .orange : .indigo,
                aggregate: aggregate
            )
        }
        .sorted(by: providerKeySortTrendCardSummary(_:_:))
    }

    private func providerKeyFamilyTrendCards(
        _ families: [ProviderKeyFamilyInventorySummary]
    ) -> [ProviderKeyTrendCardSummary] {
        return families.compactMap { family in
            guard let aggregate = RemoteQuotaTrendSupport.aggregateEstimatedFamilyTrend(
                consumers: family.assignedConsumers,
                familyKeys: [family.familyKey]
            ) else {
                return nil
            }

            let budgetSummary = family.assignedDailyTokenBudget > 0
                ? "覆盖预算 \(HubUIStrings.Settings.ProviderKeys.tokenCount(family.assignedDailyTokenBudget))"
                : (family.unlimitedBudgetConsumerCount > 0 ? "含弹性 consumer \(family.unlimitedBudgetConsumerCount)" : "当前无固定预算")
            let footnote = aggregate.estimatedConsumerCount > 0
                ? "其中 \(aggregate.estimatedConsumerCount) 个 multi-family consumer 按今日家族命中占比估算，适合用来看池子升温。"
                : "全部来自这个家族相关 consumer 的真实 5m usage 桶。"

            return ProviderKeyTrendCardSummary(
                id: "family:\(family.id)",
                title: family.displayName,
                subtitle: "\(family.coveredUserCount) 用户 / \(family.assignedClientCount) consumer · \(budgetSummary)",
                footnote: footnote,
                systemName: "square.stack.3d.up.fill",
                tint: providerKeyPoolStateColor(family.quotaPool.state),
                aggregate: aggregate
            )
        }
        .sorted(by: providerKeySortTrendCardSummary(_:_:))
    }

    private func providerKeyUserTrendCards(
        _ users: [RemoteQuotaCenterUserProjection],
        focusedVendor: ProviderKeyVendorInventorySummary?
    ) -> [ProviderKeyTrendCardSummary] {
        return users.compactMap { user -> ProviderKeyTrendCardSummary? in
            let focusedVendorName = focusedVendor?.displayName ?? ""
            let aggregate: RemoteQuotaTrendAggregate?
            if let focusedVendor {
                aggregate = RemoteQuotaTrendSupport.aggregateEstimatedFamilyTrend(
                    consumers: user.consumers,
                    familyKeys: Set(focusedVendor.familyKeys)
                )
            } else {
                aggregate = RemoteQuotaTrendSupport.aggregateConsumers(user.consumers)
            }

            guard let aggregate else {
                return nil
            }

            let remainingText: String = {
                if user.allocatedDailyTokenBudget > 0 {
                    let base = HubUIStrings.Settings.ProviderKeys.tokenCount(max(Int64(0), user.remainingDailyTokenBudget))
                    return user.hasUnlimitedBudget ? "\(base) +" : base
                }
                return user.hasUnlimitedBudget ? "弹性" : "0"
            }()

            return ProviderKeyTrendCardSummary(
                id: "user:\(user.id)",
                title: user.displayName,
                subtitle: focusedVendor == nil
                    ? "\(user.consumerCount) consumer · 剩余 \(remainingText)"
                    : "\(user.consumerCount) consumer · \(focusedVendorName) 相关剩余 \(remainingText)",
                footnote: focusedVendor == nil
                    ? providerKeyBudgetUserScopeSummary(user)
                    : providerKeyBudgetUserScopeSummary(user) + " · 趋势仅统计 \(focusedVendorName) 相关家族",
                systemName: user.isStandaloneConsumer ? "person.crop.circle.badge.questionmark" : "person.crop.circle",
                tint: providerKeyUserAtRisk(user) ? .orange : providerKeyUserTint(user),
                aggregate: aggregate
            )
        }
        .sorted(by: providerKeySortTrendCardSummary(_:_:))
    }

    private func providerKeyConsumerTrendCards(
        _ consumers: [RemoteQuotaCenterClientProjection],
        focusedVendor: ProviderKeyVendorInventorySummary?
    ) -> [ProviderKeyTrendCardSummary] {
        return consumers.compactMap { consumer -> ProviderKeyTrendCardSummary? in
            let focusedVendorName = focusedVendor?.displayName ?? ""
            let aggregate: RemoteQuotaTrendAggregate?
            if let focusedVendor {
                aggregate = RemoteQuotaTrendSupport.aggregateEstimatedFamilyTrend(
                    consumers: [consumer],
                    familyKeys: Set(focusedVendor.familyKeys)
                )
            } else {
                aggregate = RemoteQuotaTrendSupport.aggregateConsumers([consumer])
            }

            guard let aggregate else {
                return nil
            }

            let budgetText = consumer.dailyTokenLimit > 0
                ? "预算 \(HubUIStrings.Settings.ProviderKeys.tokenCount(consumer.dailyTokenLimit))"
                : "弹性预算"
            let familyText = consumer.familyDisplayNames.isEmpty
                ? "当前未解析到家族"
                : "家族 \(providerKeyPreviewList(consumer.familyDisplayNames))"

            return ProviderKeyTrendCardSummary(
                id: "consumer:\(consumer.id)",
                title: consumer.name,
                subtitle: focusedVendor == nil
                    ? "\(consumer.kindTitle) · \(budgetText)"
                    : "\(consumer.kindTitle) · \(focusedVendorName) 相关 · \(budgetText)",
                footnote: focusedVendor == nil
                    ? "\(familyText) · \(providerKeyBudgetClientReferenceSummary(consumer))"
                    : "\(familyText) · \(providerKeyBudgetClientReferenceSummary(consumer)) · 仅统计 \(focusedVendorName) 命中",
                systemName: consumer.isTerminalAccess ? "terminal.fill" : "display.2",
                tint: providerKeyConsumerAtRisk(consumer) ? .orange : providerKeyConsumerKindColor(consumer.consumerKind),
                aggregate: aggregate
            )
        }
        .sorted(by: providerKeySortTrendCardSummary(_:_:))
    }

    private func providerKeySortTrendCardSummary(
        _ lhs: ProviderKeyTrendCardSummary,
        _ rhs: ProviderKeyTrendCardSummary
    ) -> Bool {
        let leftRecent = lhs.aggregate.recentTokens15m
        let rightRecent = rhs.aggregate.recentTokens15m
        if leftRecent != rightRecent {
            return leftRecent > rightRecent
        }
        if lhs.aggregate.totalTokens1h != rhs.aggregate.totalTokens1h {
            return lhs.aggregate.totalTokens1h > rhs.aggregate.totalTokens1h
        }
        if lhs.aggregate.peakBucketTokens != rhs.aggregate.peakBucketTokens {
            return lhs.aggregate.peakBucketTokens > rhs.aggregate.peakBucketTokens
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func providerKeyVendorObservedDailyTokensUsed(
        _ consumer: RemoteQuotaCenterClientProjection,
        familyKeys: Set<String>
    ) -> Int64 {
        guard !familyKeys.isEmpty else { return 0 }
        return familyKeys.reduce(Int64(0)) { partial, familyKey in
            partial + max(Int64(0), consumer.observedDailyTokens(for: familyKey))
        }
    }

    private func providerKeyVendorObservedDailyTokensUsed(
        _ user: RemoteQuotaCenterUserProjection,
        familyKeys: Set<String>
    ) -> Int64 {
        user.consumers.reduce(Int64(0)) { partial, consumer in
            partial + providerKeyVendorObservedDailyTokensUsed(consumer, familyKeys: familyKeys)
        }
    }

    private func providerKeyVendorSpotlightUsers(
        _ users: [RemoteQuotaCenterUserProjection],
        familyKeys: Set<String>
    ) -> [ProviderKeyVendorUserSpotlight] {
        let spotlight = users.map { user in
            ProviderKeyVendorUserSpotlight(
                user: user,
                vendorObservedDailyTokensUsed: providerKeyVendorObservedDailyTokensUsed(
                    user,
                    familyKeys: familyKeys
                )
            )
        }
        let sorted = spotlight.sorted { lhs, rhs in
            let leftRisk = providerKeyUserAtRisk(lhs.user)
            let rightRisk = providerKeyUserAtRisk(rhs.user)
            if leftRisk != rightRisk {
                return leftRisk && !rightRisk
            }
            if lhs.vendorObservedDailyTokensUsed != rhs.vendorObservedDailyTokensUsed {
                return lhs.vendorObservedDailyTokensUsed > rhs.vendorObservedDailyTokensUsed
            }
            if lhs.user.allocatedDailyTokenBudget != rhs.user.allocatedDailyTokenBudget {
                return lhs.user.allocatedDailyTokenBudget > rhs.user.allocatedDailyTokenBudget
            }
            if lhs.user.connectedConsumerCount != rhs.user.connectedConsumerCount {
                return lhs.user.connectedConsumerCount > rhs.user.connectedConsumerCount
            }
            return lhs.user.displayName.localizedCaseInsensitiveCompare(rhs.user.displayName) == .orderedAscending
        }

        let preferred = sorted.filter { spotlight in
            spotlight.vendorObservedDailyTokensUsed > 0
                || spotlight.user.allocatedDailyTokenBudget > 0
                || spotlight.user.hasUnlimitedBudget
                || providerKeyUserAtRisk(spotlight.user)
        }
        return Array((preferred.isEmpty ? sorted : preferred).prefix(3))
    }

    private func providerKeyVendorSpotlightConsumers(
        _ consumers: [RemoteQuotaCenterClientProjection],
        familyKeys: Set<String>
    ) -> [ProviderKeyVendorConsumerSpotlight] {
        let spotlight = consumers.map { consumer in
            ProviderKeyVendorConsumerSpotlight(
                consumer: consumer,
                vendorObservedDailyTokensUsed: providerKeyVendorObservedDailyTokensUsed(
                    consumer,
                    familyKeys: familyKeys
                )
            )
        }
        let sorted = spotlight.sorted { lhs, rhs in
            let leftRisk = providerKeyConsumerAtRisk(lhs.consumer)
            let rightRisk = providerKeyConsumerAtRisk(rhs.consumer)
            if leftRisk != rightRisk {
                return leftRisk && !rightRisk
            }
            if lhs.vendorObservedDailyTokensUsed != rhs.vendorObservedDailyTokensUsed {
                return lhs.vendorObservedDailyTokensUsed > rhs.vendorObservedDailyTokensUsed
            }
            if lhs.consumer.dailyTokenLimit != rhs.consumer.dailyTokenLimit {
                return lhs.consumer.dailyTokenLimit > rhs.consumer.dailyTokenLimit
            }
            if lhs.consumer.connected != rhs.consumer.connected {
                return lhs.consumer.connected && !rhs.consumer.connected
            }
            return lhs.consumer.name.localizedCaseInsensitiveCompare(rhs.consumer.name) == .orderedAscending
        }

        let preferred = sorted.filter { spotlight in
            spotlight.vendorObservedDailyTokensUsed > 0
                || spotlight.consumer.dailyTokenLimit > 0
                || spotlight.consumer.allowsAllFamilies
                || providerKeyConsumerAtRisk(spotlight.consumer)
        }
        return Array((preferred.isEmpty ? sorted : preferred).prefix(3))
    }

    private func providerKeyVendorInventorySummaries(
        _ pools: [ProviderKeyPoolSnapshot],
        familySummaries: [ProviderKeyFamilyInventorySummary],
        scopedUsers: [RemoteQuotaCenterUserProjection],
        scopedConsumers: [RemoteQuotaCenterClientProjection],
        includeSpotlights: Bool = true
    ) -> [ProviderKeyVendorInventorySummary] {
        let grouped = Dictionary(grouping: pools) { pool in
            providerKeyCanonicalVendorKey(pool.supplierKey)
        }

        return grouped.compactMap { vendorKey, vendorPools in
            guard let firstPool = vendorPools.first else { return nil }
            let sortedVendorPools = vendorPools.sorted(by: providerKeySortVendorPools(_:_:))
            let distinctSupplierKeys = providerKeyDistinctPreviewStrings(vendorPools.map(\.supplierKey))
            let supplierDisplayName = firstPool.supplierDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = distinctSupplierKeys.count > 1
                ? providerKeyVendorDisplayName(vendorKey)
                : (supplierDisplayName.isEmpty ? providerKeyVendorDisplayName(vendorKey) : supplierDisplayName)
            let familyKeys = providerKeyDistinctPreviewStrings(vendorPools.flatMap(\.supportedFamilyKeys))
            let familyKeySet = Set(familyKeys)
            let relatedFamilies = familySummaries.filter { familyKeySet.contains($0.familyKey) }
            let coveredConsumers = scopedConsumers.filter { consumer in
                consumer.allowsAllFamilies || !familyKeySet.isDisjoint(with: Set(consumer.familyKeys))
            }
            let coveredConsumerIDs = Set(coveredConsumers.map(\.id))
            let coveredUsers = scopedUsers.filter { user in
                user.consumers.contains(where: { coveredConsumerIDs.contains($0.id) })
            }
            let spotlightUsers = includeSpotlights
                ? providerKeyVendorSpotlightUsers(coveredUsers, familyKeys: familyKeySet)
                : []
            let spotlightConsumers = includeSpotlights
                ? providerKeyVendorSpotlightConsumers(coveredConsumers, familyKeys: familyKeySet)
                : []
            let assignedDailyTokenBudget = relatedFamilies.reduce(Int64(0)) { partial, family in
                partial + max(Int64(0), family.assignedDailyTokenBudget)
            }
            let observedFamilyTokensUsed = relatedFamilies.reduce(Int64(0)) { partial, family in
                partial + max(Int64(0), family.observedDailyTokensUsed)
            }
            let totalDailyTokenCap = vendorPools.reduce(Int64(0)) { $0 + max(Int64(0), $1.totalDailyTokenCap) }
            return ProviderKeyVendorInventorySummary(
                vendorKey: vendorKey,
                displayName: displayName,
                pools: sortedVendorPools,
                spotlightUsers: spotlightUsers,
                spotlightConsumers: spotlightConsumers,
                providerDisplayNames: providerKeyDistinctPreviewStrings(vendorPools.map(\.providerDisplayName)),
                providerHosts: providerKeyDistinctPreviewStrings(vendorPools.map(\.providerHost)),
                familyKeys: familyKeys,
                familyDisplayNames: providerKeyDistinctPreviewStrings(
                    relatedFamilies.isEmpty
                        ? vendorPools.flatMap(\.supportedFamilyDisplayNames)
                        : relatedFamilies.map(\.displayName)
                ),
                coveredUserCount: coveredUsers.count,
                coveredConsumerCount: coveredConsumers.count,
                coveredUnlimitedConsumerCount: coveredConsumers.filter { $0.dailyTokenLimit <= 0 }.count,
                coveredFamilyCount: relatedFamilies.count,
                poolCount: vendorPools.count,
                totalAccounts: vendorPools.reduce(0) { $0 + $1.totalAccounts },
                readyAccounts: vendorPools.reduce(0) { $0 + $1.readyAccounts },
                cooldownAccounts: vendorPools.reduce(0) { $0 + $1.cooldownAccounts },
                blockedAccounts: vendorPools.reduce(0) { $0 + $1.blockedAccounts },
                disabledAccounts: vendorPools.reduce(0) { $0 + $1.disabledAccounts },
                staleAccounts: vendorPools.reduce(0) { $0 + $1.staleAccounts },
                totalDailyTokenCap: totalDailyTokenCap,
                totalDailyTokensUsed: vendorPools.reduce(Int64(0)) { $0 + max(Int64(0), $1.totalDailyTokensUsed) },
                totalDailyTokensRemaining: vendorPools.reduce(Int64(0)) { $0 + max(Int64(0), $1.totalDailyTokensRemaining) },
                totalTokensUsed: vendorPools.reduce(Int64(0)) { $0 + max(Int64(0), $1.totalTokensUsed) },
                assignedDailyTokenBudget: assignedDailyTokenBudget,
                observedFamilyTokensUsed: observedFamilyTokensUsed,
                allocationHeadroom: totalDailyTokenCap > 0 ? (totalDailyTokenCap - assignedDailyTokenBudget) : 0,
                oversubscribedFamilyCount: relatedFamilies.filter(\.isOversubscribed).count,
                hotPoolCount: vendorPools.filter(providerKeyPoolNeedsAttention(_:)).count
            )
        }
        .sorted { lhs, rhs in
            if lhs.oversubscribedFamilyCount != rhs.oversubscribedFamilyCount {
                return lhs.oversubscribedFamilyCount > rhs.oversubscribedFamilyCount
            }
            if lhs.blockedAccounts != rhs.blockedAccounts {
                return lhs.blockedAccounts > rhs.blockedAccounts
            }
            if lhs.assignedDailyTokenBudget != rhs.assignedDailyTokenBudget {
                return lhs.assignedDailyTokenBudget > rhs.assignedDailyTokenBudget
            }
            if lhs.totalAccounts != rhs.totalAccounts {
                return lhs.totalAccounts > rhs.totalAccounts
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    @ViewBuilder
    func providerKeyVendorSpotlightMetric(
        _ title: String,
        tint: Color
    ) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tint.opacity(0.10))
            .clipShape(Capsule())
    }

    func providerKeyUserRemainingBudgetPreviewText(
        _ user: RemoteQuotaCenterUserProjection
    ) -> String {
        if user.allocatedDailyTokenBudget > 0 {
            let base = HubUIStrings.Settings.ProviderKeys.tokenCount(user.remainingDailyTokenBudget)
            return user.hasUnlimitedBudget ? "\(base) +" : base
        }
        return user.hasUnlimitedBudget ? "弹性" : "0"
    }

    func providerKeyConsumerRemainingBudgetPreviewText(
        _ consumer: RemoteQuotaCenterClientProjection
    ) -> String {
        consumer.dailyTokenLimit > 0
            ? HubUIStrings.Settings.ProviderKeys.tokenCount(consumer.remainingDailyTokenBudget)
            : "弹性"
    }

    @ViewBuilder
    func providerKeyHeatStrip(
        value: Double,
        tint: Color,
        segments: Int = 14
    ) -> some View {
        let normalized = max(0, min(1, value))
        HStack(spacing: 4) {
            ForEach(0..<segments, id: \.self) { index in
                let threshold = Double(index + 1) / Double(segments)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(threshold <= normalized ? tint.opacity(0.9) : tint.opacity(0.12))
                    .frame(maxWidth: .infinity, minHeight: 8, maxHeight: 8)
            }
        }
    }

    func providerKeyUsageHeatTint(
        fraction: Double,
        hasBlockingRisk: Bool
    ) -> Color {
        if hasBlockingRisk {
            return .red
        }
        switch fraction {
        case let value where value >= 0.9:
            return .orange
        case let value where value >= 0.65:
            return .yellow
        case let value where value > 0:
            return .blue
        default:
            return .green
        }
    }

    private func providerKeyPoolNeedsAttention(
        _ pool: ProviderKeyPoolSnapshot
    ) -> Bool {
        if pool.blockedAccounts > 0 || pool.cooldownAccounts > 0 || !pool.issueSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return providerKeyUsageFraction(
            used: pool.totalDailyTokensUsed,
            cap: pool.totalDailyTokenCap
        ) >= 0.8
    }

    private func providerKeySortVendorPools(
        _ lhs: ProviderKeyPoolSnapshot,
        _ rhs: ProviderKeyPoolSnapshot
    ) -> Bool {
        let leftHot = providerKeyPoolNeedsAttention(lhs)
        let rightHot = providerKeyPoolNeedsAttention(rhs)
        if leftHot != rightHot {
            return leftHot && !rightHot
        }
        if lhs.blockedAccounts != rhs.blockedAccounts {
            return lhs.blockedAccounts > rhs.blockedAccounts
        }
        if lhs.cooldownAccounts != rhs.cooldownAccounts {
            return lhs.cooldownAccounts > rhs.cooldownAccounts
        }
        if lhs.totalAccounts != rhs.totalAccounts {
            return lhs.totalAccounts > rhs.totalAccounts
        }
        return providerKeyPoolTitle(lhs).localizedCaseInsensitiveCompare(providerKeyPoolTitle(rhs)) == .orderedAscending
    }

    func providerKeyVendorPoolDisclosureSummary(
        _ vendor: ProviderKeyVendorInventorySummary
    ) -> String {
        var parts: [String] = [
            "\(vendor.pools.count) 个池",
            "\(vendor.totalAccounts) 把 key"
        ]

        if vendor.cooldownAccounts > 0 {
            parts.append("冷却 \(vendor.cooldownAccounts)")
        }
        if vendor.blockedAccounts > 0 {
            parts.append("阻断 \(vendor.blockedAccounts)")
        }

        let earliestRetryAtMs = vendor.pools
            .map(\.earliestRetryAtMs)
            .filter { $0 > 0 }
            .min() ?? 0
        if earliestRetryAtMs > 0 {
            parts.append("最早重试 \(formattedProviderKeyImportSourceTime(earliestRetryAtMs))")
        }
        return HubUIStrings.Settings.RemoteModels.sectionSummary(parts)
    }

    private func providerKeyDistinctPreviewStrings(
        _ values: [String]
    ) -> [String] {
        var out: [String] = []
        var seen: Set<String> = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = trimmed.lowercased()
            guard !trimmed.isEmpty, seen.insert(normalized).inserted else { continue }
            out.append(trimmed)
        }
        return out
    }

    func providerKeyCanonicalVendorKey(_ rawVendorKey: String) -> String {
        let normalized = rawVendorKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "chatgpt", "codex", "openai_compatible":
            return "openai"
        case "anthropic":
            return "claude"
        case "moonshot":
            return "kimi"
        default:
            return normalized
        }
    }

    func providerKeyVendorDisplayName(_ vendorKey: String) -> String {
        switch providerKeyCanonicalVendorKey(vendorKey) {
        case "openai":
            return "OpenAI / Codex"
        case "claude":
            return "Claude"
        case "gemini":
            return "Gemini"
        case "antigravity":
            return "Antigravity"
        case "kimi":
            return "Kimi"
        default:
            let normalized = providerKeyCanonicalVendorKey(vendorKey)
            return normalized.isEmpty ? "Unknown" : normalized.capitalized
        }
    }

    func providerKeyVendorSummaryText(
        _ vendor: ProviderKeyVendorInventorySummary
    ) -> String {
        var parts: [String] = []
        if !vendor.familyDisplayNames.isEmpty {
            parts.append("家族 \(providerKeyPreviewList(vendor.familyDisplayNames))")
        }
        if !vendor.providerHosts.isEmpty {
            parts.append("host \(providerKeyPreviewList(vendor.providerHosts, maxCount: 2))")
        } else if !vendor.providerDisplayNames.isEmpty {
            parts.append(providerKeyPreviewList(vendor.providerDisplayNames))
        }
        parts.append("\(vendor.coveredUserCount) 个用户 / \(vendor.coveredConsumerCount) 个 consumer")
        parts.append("\(vendor.poolCount) 个池 / \(vendor.totalAccounts) 把 key")
        return HubUIStrings.Settings.RemoteModels.sectionSummary(parts)
    }

    @ViewBuilder
    func providerKeyLedgerSectionHeader(
        title: String,
        summary: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    func providerKeyLedgerMetricTile(
        title: String,
        value: String,
        detail: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    func providerKeyFocusUserTitle(
        _ user: RemoteQuotaCenterUserProjection
    ) -> String {
        if user.isStandaloneConsumer {
            return "\(user.displayName) · 单 consumer"
        }
        return "\(user.displayName) · \(user.consumerCount) consumer"
    }

    func providerKeyFocusVendorTitle(
        _ vendor: ProviderKeyVendorInventorySummary
    ) -> String {
        "\(vendor.displayName) · \(vendor.readyAccounts)/\(vendor.totalAccounts) Ready"
    }

    func providerKeyFocusedUser(
        _ users: [RemoteQuotaCenterUserProjection]
    ) -> RemoteQuotaCenterUserProjection? {
        let focusKey = remoteQuotaFocusedUserGroupingKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !focusKey.isEmpty else { return nil }
        return users.first(where: { $0.groupingKey == focusKey })
    }

    var providerKeyNormalizedFocusedVendorKey: String {
        let focusKey = remoteQuotaFocusedVendorKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !focusKey.isEmpty else { return "" }
        return providerKeyCanonicalVendorKey(focusKey)
    }

    var providerKeyHasFocusedVendor: Bool {
        !providerKeyNormalizedFocusedVendorKey.isEmpty
    }

    func providerKeyFocusedVendor(
        _ vendors: [ProviderKeyVendorInventorySummary]
    ) -> ProviderKeyVendorInventorySummary? {
        let focusKey = providerKeyNormalizedFocusedVendorKey
        guard !focusKey.isEmpty else { return nil }
        return vendors.first { vendor in
            providerKeyCanonicalVendorKey(vendor.vendorKey) == focusKey
        }
    }

    private func providerKeyFocusedVendorFamilyKeys(
        _ projection: RemoteQuotaCenterProjection
    ) -> Set<String> {
        let focusKey = providerKeyNormalizedFocusedVendorKey
        guard !focusKey.isEmpty else { return [] }

        let familyKeysFromProjection = projection.families.compactMap { family -> String? in
            let supplierKeys = Set(family.quotaPool.supplierKeys.map(providerKeyCanonicalVendorKey(_:)))
            return supplierKeys.contains(focusKey) ? family.familyKey : nil
        }

        if !familyKeysFromProjection.isEmpty {
            return Set(familyKeysFromProjection)
        }

        let fallbackFamilyKeys = providerKeyDerivedSnapshot.keyPools
            .filter { pool in
                providerKeyCanonicalVendorKey(pool.supplierKey) == focusKey
            }
            .flatMap(\.supportedFamilyKeys)
        return Set(fallbackFamilyKeys)
    }

    private func providerKeyConsumerMatchesFocusedVendor(
        _ consumer: RemoteQuotaCenterClientProjection,
        focusedVendorFamilyKeys: Set<String>
    ) -> Bool {
        guard providerKeyHasFocusedVendor else { return true }
        guard !focusedVendorFamilyKeys.isEmpty else { return false }
        if consumer.allowsAllFamilies {
            return true
        }
        return !focusedVendorFamilyKeys.isDisjoint(with: Set(consumer.familyKeys))
    }

    private func providerKeyUserMatchesFocusedVendor(
        _ user: RemoteQuotaCenterUserProjection,
        focusedVendorFamilyKeys: Set<String>
    ) -> Bool {
        guard providerKeyHasFocusedVendor else { return true }
        guard !focusedVendorFamilyKeys.isEmpty else { return false }
        if !focusedVendorFamilyKeys.isDisjoint(with: Set(user.familyKeys)) {
            return true
        }
        return user.consumers.contains { consumer in
            providerKeyConsumerMatchesFocusedVendor(
                consumer,
                focusedVendorFamilyKeys: focusedVendorFamilyKeys
            )
        }
    }

    private func providerKeyVendorScopedUsers(
        _ users: [RemoteQuotaCenterUserProjection],
        focusedVendorFamilyKeys: Set<String>
    ) -> [RemoteQuotaCenterUserProjection] {
        guard providerKeyHasFocusedVendor else { return users }
        return users.filter { user in
            providerKeyUserMatchesFocusedVendor(
                user,
                focusedVendorFamilyKeys: focusedVendorFamilyKeys
            )
        }
    }

    private func providerKeyVendorScopedConsumers(
        _ consumers: [RemoteQuotaCenterClientProjection],
        focusedVendorFamilyKeys: Set<String>
    ) -> [RemoteQuotaCenterClientProjection] {
        guard providerKeyHasFocusedVendor else { return consumers }
        return consumers.filter { consumer in
            providerKeyConsumerMatchesFocusedVendor(
                consumer,
                focusedVendorFamilyKeys: focusedVendorFamilyKeys
            )
        }
    }

    private func providerKeyScopedUsers(
        _ users: [RemoteQuotaCenterUserProjection]
    ) -> [RemoteQuotaCenterUserProjection] {
        if let focused = providerKeyFocusedUser(users) {
            return [focused]
        }
        return users
    }

    private func providerKeyScopedConsumers(
        _ projection: RemoteQuotaCenterProjection
    ) -> [RemoteQuotaCenterClientProjection] {
        let scopedUsers = providerKeyScopedUsers(projection.users)
        let scopedConsumerIDs = Set(scopedUsers.flatMap { $0.consumers.map(\.id) })
        guard providerKeyFocusedUser(projection.users) != nil, !scopedConsumerIDs.isEmpty else {
            return projection.consumers
        }
        return projection.consumers.filter { scopedConsumerIDs.contains($0.id) }
    }

    private func providerKeyFilteredUsers(
        _ users: [RemoteQuotaCenterUserProjection],
        focusedVendorFamilyKeys: Set<String>
    ) -> [RemoteQuotaCenterUserProjection] {
        let scoped = providerKeyVendorScopedUsers(
            providerKeyScopedUsers(users),
            focusedVendorFamilyKeys: focusedVendorFamilyKeys
        )
        switch remoteQuotaUserFilter {
        case .all:
            return scoped
        case .risk:
            return scoped.filter(providerKeyUserAtRisk(_:))
        }
    }

    private func providerKeyFilteredFamilies(
        _ families: [ProviderKeyFamilyInventorySummary],
        focusedVendorFamilyKeys: Set<String>
    ) -> [ProviderKeyFamilyInventorySummary] {
        guard providerKeyHasFocusedVendor else { return families }
        guard !focusedVendorFamilyKeys.isEmpty else { return [] }
        return families.filter { family in
            focusedVendorFamilyKeys.contains(family.familyKey)
        }
    }

    private func providerKeyFilteredVendors(
        _ vendors: [ProviderKeyVendorInventorySummary],
        focusedVendor: ProviderKeyVendorInventorySummary?
    ) -> [ProviderKeyVendorInventorySummary] {
        if providerKeyHasFocusedVendor, focusedVendor == nil {
            return []
        }
        if let focusedVendor {
            return [focusedVendor]
        }
        switch remoteQuotaVendorFilter {
        case .all:
            return vendors
        case .risk:
            return vendors.filter(providerKeyVendorAtRisk(_:))
        }
    }

    private func providerKeySortFamilyInventorySummary(
        _ lhs: ProviderKeyFamilyInventorySummary,
        _ rhs: ProviderKeyFamilyInventorySummary
    ) -> Bool {
        if lhs.isOversubscribed != rhs.isOversubscribed {
            return lhs.isOversubscribed && !rhs.isOversubscribed
        }
        if lhs.quotaPool.blockedAccounts != rhs.quotaPool.blockedAccounts {
            return lhs.quotaPool.blockedAccounts > rhs.quotaPool.blockedAccounts
        }
        if lhs.assignedDailyTokenBudget != rhs.assignedDailyTokenBudget {
            return lhs.assignedDailyTokenBudget > rhs.assignedDailyTokenBudget
        }
        if lhs.observedDailyTokensUsed != rhs.observedDailyTokensUsed {
            return lhs.observedDailyTokensUsed > rhs.observedDailyTokensUsed
        }
        if lhs.combinedDailyTokenCap != rhs.combinedDailyTokenCap {
            return lhs.combinedDailyTokenCap > rhs.combinedDailyTokenCap
        }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    func providerKeyVendorAtRisk(
        _ vendor: ProviderKeyVendorInventorySummary
    ) -> Bool {
        if vendor.oversubscribedFamilyCount > 0 || vendor.blockedAccounts > 0 {
            return true
        }
        if vendor.allocationHeadroom < 0 {
            return true
        }
        if vendor.cooldownAccounts > 0 && vendor.totalAccounts <= max(1, vendor.readyAccounts) {
            return true
        }
        guard vendor.totalDailyTokenCap > 0 else { return vendor.hotPoolCount > 0 }
        return vendor.totalDailyTokensRemaining <= max(Int64(50_000), vendor.totalDailyTokenCap / 10)
    }

    private func providerKeyFamilyAtRisk(
        _ family: ProviderKeyFamilyInventorySummary
    ) -> Bool {
        if family.isOversubscribed || family.quotaPool.blockedAccounts > 0 {
            return true
        }
        if family.quotaPool.cooldownAccounts > 0 && family.quotaPool.readyAccounts <= 1 {
            return true
        }
        guard family.combinedDailyTokenCap > 0 else { return false }
        return family.combinedDailyTokensRemaining <= max(Int64(50_000), family.combinedDailyTokenCap / 10)
    }

    func providerKeyScopeSummary(
        focusedUser: RemoteQuotaCenterUserProjection?,
        focusedVendor: ProviderKeyVendorInventorySummary?,
        vendors: [ProviderKeyVendorInventorySummary],
        families: [ProviderKeyFamilyInventorySummary],
        users: [RemoteQuotaCenterUserProjection],
        consumers: [RemoteQuotaCenterClientProjection]
    ) -> String {
        let allocatedBudget = consumers.reduce(Int64(0)) { $0 + max(Int64(0), $1.dailyTokenLimit) }
        let observedUsage = consumers.reduce(Int64(0)) { $0 + max(Int64(0), $1.dailyTokenUsed) }
        let unlimitedCount = consumers.filter { $0.dailyTokenLimit <= 0 }.count
        var parts: [String] = []
        if let focusedUser {
            parts.append("当前按 \(focusedUser.displayName) 视角查看")
        } else {
            parts.append("当前是全局视角")
        }
        if let focusedVendor {
            parts.append("已锁定 \(focusedVendor.displayName) 厂家")
        } else if providerKeyHasFocusedVendor {
            parts.append("已锁定 \(providerKeyVendorDisplayName(providerKeyNormalizedFocusedVendorKey)) 厂家")
        }
        parts.append("厂家 \(vendors.count)")
        parts.append("家族 \(families.count)")
        parts.append("用户 \(users.count)")
        parts.append("消费者 \(consumers.count)")
        if allocatedBudget > 0 {
            parts.append("覆盖预算 \(HubUIStrings.Settings.ProviderKeys.tokenCount(allocatedBudget))")
            let remainingBudget = HubUIStrings.Settings.ProviderKeys.tokenCount(max(Int64(0), allocatedBudget - observedUsage))
            parts.append(unlimitedCount > 0 ? "剩余 \(remainingBudget) +" : "剩余 \(remainingBudget)")
        } else if unlimitedCount > 0 {
            parts.append("弹性 consumer \(unlimitedCount)")
        }
        if observedUsage > 0 {
            parts.append("今日已用 \(HubUIStrings.Settings.ProviderKeys.tokenCount(observedUsage))")
        }
        return parts.joined(separator: " · ")
    }

    func providerKeyVendorFilterSummary(
        _ vendors: [ProviderKeyVendorInventorySummary],
        totalVendors: Int,
        focusedUser: RemoteQuotaCenterUserProjection?,
        focusedVendor: ProviderKeyVendorInventorySummary?
    ) -> String {
        if let focusedVendor {
            if let focusedUser {
                return "当前已锁定 \(focusedVendor.displayName) 厂家，并叠加 \(focusedUser.displayName) 视角。这里只看这位用户实际命中的 \(vendors.count)/\(totalVendors) 家厂家。"
            }
            return "当前已锁定 \(focusedVendor.displayName) 厂家。这里保留该厂家全局库存与覆盖预算，便于继续往下看家族与热点用户。"
        } else if providerKeyHasFocusedVendor {
            return "当前已锁定 \(providerKeyVendorDisplayName(providerKeyNormalizedFocusedVendorKey)) 厂家，但 Hub 账本里还没有这家可展示的库存。先同步后再看。"
        }
        switch remoteQuotaVendorFilter {
        case .all:
            if let focusedUser {
                return "当前只显示与 \(focusedUser.displayName) 相关的 \(vendors.count)/\(totalVendors) 家厂家。上游库存与 key 健康仍是厂家全局账，覆盖预算和今日用量已按当前用户重算。"
            }
            return "显示全部 \(vendors.count) 家厂家，覆盖库存、预算缓冲和健康态势。"
        case .risk:
            return vendors.isEmpty
                ? "当前视角下没有库存缓冲偏低、超配或阻塞明显的厂家。"
                : "风险视图共 \(vendors.count)/\(totalVendors) 家，按超配、缓冲不足或 key 阻塞筛出。"
        }
    }

    func providerKeyUserFilterSummary(
        _ users: [RemoteQuotaCenterUserProjection],
        totalUsers: Int,
        focusedUser: RemoteQuotaCenterUserProjection?
    ) -> String {
        switch remoteQuotaUserFilter {
        case .all:
            if let focusedUser {
                return "当前只显示 \(focusedUser.displayName) 这一位用户主体。"
            }
            return providerKeyUserLedgerSummary(users)
        case .risk:
            return users.isEmpty
                ? "当前视角下没有逼近上限、已触顶或出现阻断记录的用户主体。"
                : "风险用户共 \(users.count)/\(totalUsers) 个，按 consumer 风险和剩余额度偏低筛出。"
        }
    }

    private func providerKeyUserLedgerSummary(
        _ users: [RemoteQuotaCenterUserProjection]
    ) -> String {
        let standaloneCount = users.filter(\.isStandaloneConsumer).count
        let riskCount = users.filter(providerKeyUserAtRisk(_:)).count
        var parts: [String] = ["共 \(users.count) 个用户主体"]
        if riskCount > 0 {
            parts.append("\(riskCount) 个存在预算风险")
        }
        if standaloneCount > 0 {
            parts.append("\(standaloneCount) 个未绑定 user_id，已按单 consumer 独立记账")
        }
        return parts.joined(separator: " · ")
    }

    func providerKeyUserTint(
        _ user: RemoteQuotaCenterUserProjection
    ) -> Color {
        if user.isStandaloneConsumer {
            return .gray
        }
        return user.terminalConsumerCount > 0 && user.xtConsumerCount > 0 ? .blue : .indigo
    }

    func providerKeyUserAtRisk(
        _ user: RemoteQuotaCenterUserProjection
    ) -> Bool {
        if user.consumers.contains(where: providerKeyConsumerAtRisk(_:)) {
            return true
        }
        guard user.allocatedDailyTokenBudget > 0 else { return false }
        return user.remainingDailyTokenBudget <= max(Int64(5_000), user.allocatedDailyTokenBudget / 10)
    }

    func providerKeyBudgetUserIdentitySummary(
        _ user: RemoteQuotaCenterUserProjection
    ) -> String {
        var parts: [String] = []
        switch user.groupingKind {
        case .userID:
            parts.append("user_id \(user.groupingValue)")
        case .standaloneConsumer:
            parts.append("未设置 user_id，按单个 consumer 独立记账")
        }
        if !user.appIds.isEmpty {
            parts.append("app \(providerKeyPreviewList(user.appIds))")
        }
        return parts.joined(separator: " • ")
    }

    func providerKeyBudgetUserScopeSummary(
        _ user: RemoteQuotaCenterUserProjection
    ) -> String {
        var parts: [String] = []
        if !user.familyDisplayNames.isEmpty {
            parts.append("家族 \(providerKeyPreviewList(user.familyDisplayNames))")
        } else {
            parts.append("当前还没有解析到模型家族")
        }
        parts.append("\(user.consumerCount) 个消费者")
        if user.connectedConsumerCount > 0 {
            parts.append("在线 \(user.connectedConsumerCount)")
        }
        return HubUIStrings.Settings.RemoteModels.sectionSummary(parts)
    }

    func providerKeyBudgetUserConsumerPreview(
        _ user: RemoteQuotaCenterUserProjection
    ) -> String {
        let preview = user.consumers.prefix(3).map { consumer in
            "\(consumer.name)(\(consumer.kindTitle))"
        }
        guard !preview.isEmpty else { return "" }
        let suffix = user.consumerCount > preview.count
            ? " 等另外 \(user.consumerCount - preview.count) 个"
            : ""
        return "消费者：\(preview.joined(separator: "、"))\(suffix)"
    }

    private func providerKeyPreviewList(
        _ values: [String],
        maxCount: Int = 3
    ) -> String {
        let trimmed = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmed.isEmpty else { return "" }
        let preview = Array(trimmed.prefix(maxCount))
        let suffix = trimmed.count > preview.count ? " 等 \(trimmed.count) 项" : ""
        return preview.joined(separator: " / ") + suffix
    }

    private func providerKeyFilteredConsumers(
        _ projection: RemoteQuotaCenterProjection,
        focusedVendorFamilyKeys: Set<String>
    ) -> [RemoteQuotaCenterClientProjection] {
        let scopedUsers = providerKeyScopedUsers(projection.users)
        let scopedConsumerIDs = Set(scopedUsers.flatMap { $0.consumers.map(\.id) })
        let baseConsumers: [RemoteQuotaCenterClientProjection]
        if providerKeyFocusedUser(projection.users) != nil, !scopedConsumerIDs.isEmpty {
            baseConsumers = projection.consumers.filter { scopedConsumerIDs.contains($0.id) }
        } else {
            baseConsumers = projection.consumers
        }

        let vendorScopedConsumers = providerKeyVendorScopedConsumers(
            baseConsumers,
            focusedVendorFamilyKeys: focusedVendorFamilyKeys
        )

        return vendorScopedConsumers.filter { consumer in
            switch remoteQuotaConsumerFilter {
            case .all:
                return true
            case .xt:
                return consumer.consumerKind == .pairedXT
            case .terminal:
                return consumer.consumerKind == .terminalAccess
            case .risk:
                return providerKeyConsumerAtRisk(consumer)
            }
        }
    }

    func providerKeyConsumerFilterSummary(
        _ consumers: [RemoteQuotaCenterClientProjection],
        totalConsumers: Int,
        focusedUser: RemoteQuotaCenterUserProjection?
    ) -> String {
        let xtCount = consumers.filter { $0.consumerKind == .pairedXT }.count
        let terminalCount = consumers.filter { $0.consumerKind == .terminalAccess }.count

        switch remoteQuotaConsumerFilter {
        case .all:
            if let focusedUser {
                return "当前显示 \(focusedUser.displayName) 相关的全部 \(consumers.count)/\(totalConsumers) 个消费者，其中 XT \(xtCount) 个，Terminal \(terminalCount) 个。"
            }
            return "显示全部 \(consumers.count) 个消费者，其中 XT \(xtCount) 个，Terminal \(terminalCount) 个。"
        case .xt:
            return "显示 \(consumers.count)/\(totalConsumers) 个 XT 消费者。"
        case .terminal:
            return "显示 \(consumers.count)/\(totalConsumers) 个普通 terminal access key 消费者。"
        case .risk:
            return consumers.isEmpty
                ? "当前没有逼近上限或出现阻断的消费者。"
                : "风险视图共 \(consumers.count) 个，按剩余额度偏低、已触顶或有阻断记录筛出。"
        }
    }

    func providerKeyConsumerKindColor(
        _ kind: RemoteQuotaCenterConsumerKind
    ) -> Color {
        switch kind {
        case .pairedXT:
            return .indigo
        case .terminalAccess:
            return .teal
        }
    }

    func providerKeyConsumerAtRisk(
        _ consumer: RemoteQuotaCenterClientProjection
    ) -> Bool {
        if let status = consumer.deviceStatus, status.blockedToday > 0 {
            return true
        }
        guard consumer.dailyTokenLimit > 0 else { return false }
        if consumer.dailyTokenUsed >= consumer.dailyTokenLimit {
            return true
        }
        return consumer.remainingDailyTokenBudget <= max(Int64(5_000), consumer.dailyTokenLimit / 10)
    }

    func providerKeyBudgetClientReferenceSummary(
        _ clientProjection: RemoteQuotaCenterClientProjection
    ) -> String {
        var parts: [String] = []
        if clientProjection.isTerminalAccess {
            parts.append("key \(clientProjection.referenceID)")
        } else {
            parts.append("device \(clientProjection.deviceId)")
        }
        if !clientProjection.appId.isEmpty {
            parts.append("app \(clientProjection.appId)")
        }
        if !clientProjection.userId.isEmpty {
            parts.append("user \(clientProjection.userId)")
        }
        return parts.joined(separator: " • ")
    }

    private func reloadCLIProxyRuntimeConfiguration() {
        cliproxyRuntimeSettings = CLIProxyRuntimeSupport.loadSettings()
        cliproxyRuntimeConfigAudit = CLIProxyRuntimeSupport.auditConfig(settings: cliproxyRuntimeSettings)
    }

    func persistCLIProxyRuntimeConfiguration() {
        cliproxyRuntimeSettings = cliproxyRuntimeSettings.normalized()
        _ = CLIProxyRuntimeSupport.saveSettings(cliproxyRuntimeSettings)
        cliproxyRuntimeConfigAudit = CLIProxyRuntimeSupport.auditConfig(settings: cliproxyRuntimeSettings)
    }

    func detectCLIProxyRuntimePackage() {
        if let detectedURL = CLIProxyRuntimeSupport.detectPackageDirectoryURL() {
            cliproxyRuntimeSettings.packageDirectoryPath = detectedURL.path
            cliproxyRuntimeSettings.preferDetectedPackage = true
            persistCLIProxyRuntimeConfiguration()
            cliproxyRuntimeActionText = "已自动定位 CLIProxy 发行包：\(settingsSummarySnippet(detectedURL.path, limit: 62))"
            cliproxyRuntimeErrorText = ""
            Task { await refreshCLIProxyRuntimeStatus(manual: false) }
            return
        }

        cliproxyRuntimeErrorText = "自动探测没有找到 CLIProxy 发行包。默认会查找 ~/Documents/AX/source/CLIProxyAPI-main。"
    }

    @MainActor
    func refreshCLIProxyRuntimeStatus(manual: Bool = false) async {
        guard !cliproxyRuntimeRefreshing else { return }

        cliproxyRuntimeRefreshing = true
        persistCLIProxyRuntimeConfiguration()
        if manual {
            cliproxyRuntimeActionText = "正在检查本地 CLIProxy 节点…"
            cliproxyRuntimeErrorText = ""
        }

        defer {
            cliproxyRuntimeRefreshing = false
        }

        let probe = await CLIProxyRuntimeSupport.probe(
            baseURL: cliproxyOAuthSettings.baseURL,
            managementKey: cliproxyOAuthManagementKey,
            settings: cliproxyRuntimeSettings
        )
        cliproxyRuntimeConfigAudit = CLIProxyRuntimeSupport.auditConfig(settings: cliproxyRuntimeSettings)
        cliproxyRuntimeProbe = probe
        cliproxyRuntimeLastProbeAtMs = probe.probedAtMs

        guard manual else { return }

        let trimmedSummary = cliproxyRuntimeSummaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch probe.packageStatus {
        case .notFound where !probe.serviceRunning:
            cliproxyRuntimeErrorText = "还没有发现 CLIProxy 发行包目录。可点“自动探测”，或手动填写发行包目录。"
            cliproxyRuntimeActionText = ""
        case .missingExecutable:
            cliproxyRuntimeErrorText = "选中的目录里缺少 cli-proxy-api 可执行文件。"
            cliproxyRuntimeActionText = ""
        case .missingConfig:
            cliproxyRuntimeErrorText = "选中的目录里缺少 config.yaml。"
            cliproxyRuntimeActionText = ""
        default:
            switch probe.managementStatus {
            case .keyInvalid:
                cliproxyRuntimeErrorText = "CLIProxy 已运行，但 management key 不正确。"
                cliproxyRuntimeActionText = ""
            case .unavailable:
                cliproxyRuntimeErrorText = "CLIProxy 服务已启动，但管理接口当前不可用。"
                cliproxyRuntimeActionText = ""
            case .error(let detail):
                cliproxyRuntimeErrorText = detail.isEmpty
                    ? "CLIProxy 管理接口检查失败。"
                    : "CLIProxy 管理接口检查失败：\(detail)"
                cliproxyRuntimeActionText = ""
            default:
                cliproxyRuntimeActionText = trimmedSummary
                cliproxyRuntimeErrorText = ""
            }
        }
    }

    @MainActor
    private func maybeRefreshCLIProxyRuntimeStatus() async {
        guard selectedSettingsPage == .models else { return }
        guard !cliproxyRuntimeRefreshing, !cliproxyRuntimeLaunching, !cliproxyRuntimeKeyRotating else { return }

        let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        let intervalMs: Int64 = nowMs < cliproxyRuntimeFastProbeUntilMs ? 4_000 : 20_000
        guard cliproxyRuntimeLastProbeAtMs == 0 || nowMs - cliproxyRuntimeLastProbeAtMs >= intervalMs else {
            return
        }

        await refreshCLIProxyRuntimeStatus(manual: false)
    }

    @MainActor
    func startCLIProxyRuntime() async {
        guard !cliproxyRuntimeLaunching else { return }

        persistCLIProxyRuntimeConfiguration()
        persistCLIProxyOAuthConfiguration()
        cliproxyRuntimeLaunching = true
        cliproxyRuntimeActionText = "正在启动本地 CLIProxy 节点…"
        cliproxyRuntimeErrorText = ""

        defer {
            cliproxyRuntimeLaunching = false
        }

        do {
            let result = try await CLIProxyRuntimeSupport.startServer(
                baseURL: cliproxyOAuthSettings.baseURL,
                settings: cliproxyRuntimeSettings
            )
            cliproxyRuntimeFastProbeUntilMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded()) + 20_000
            await refreshCLIProxyRuntimeStatus(manual: false)

            if result.alreadyRunning {
                cliproxyRuntimeActionText = "CLIProxy 已在运行，Hub 已切换到托管检查模式。"
            } else if result.healthConfirmed {
                cliproxyRuntimeActionText = "本地 CLIProxy 已启动（pid \(result.pid)），Hub 已探测到服务。"
            } else {
                cliproxyRuntimeActionText = "CLIProxy 启动请求已发出（pid \(result.pid)），服务仍在预热，Hub 会继续探测。"
            }

            if !cliproxyOAuthManagementKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await refreshCLIProxyOAuthRemoteAuths(manual: false)
                if cliproxyOAuthSettings.autoSync {
                    await syncCLIProxyOAuthAccounts(manual: false)
                }
            }
        } catch {
            cliproxyRuntimeErrorText = error.localizedDescription
        }
    }

    @MainActor
    func applyCLIProxyRuntimeConfigRecommendations() async {
        guard !cliproxyRuntimeConfigApplying else { return }

        persistCLIProxyRuntimeConfiguration()
        cliproxyRuntimeConfigApplying = true
        cliproxyRuntimeActionText = "正在把推荐项写入 CLIProxy config.yaml…"
        cliproxyRuntimeErrorText = ""

        defer {
            cliproxyRuntimeConfigApplying = false
        }

        do {
            let result = try CLIProxyRuntimeSupport.applyRecommendedConfigFixes(settings: cliproxyRuntimeSettings)
            cliproxyRuntimeConfigAudit = CLIProxyRuntimeSupport.auditConfig(settings: cliproxyRuntimeSettings)

            if result.changedCount == 0 {
                cliproxyRuntimeActionText = "config.yaml 已经符合当前推荐项，没有额外改动。"
            } else {
                let updatedTitles = result.updatedKinds.map(\.title).joined(separator: "、")
                let restartHint = cliproxyRuntimeProbe.serviceRunning ? "CLIProxy 当前正在运行，重启后这些改动会完全生效。" : "下次从 Hub 启动本地节点时会直接按新配置运行。"
                let backupHint = result.backupPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? ""
                    : " 已生成备份：\(settingsSummarySnippet(result.backupPath, limit: 54))。"
                cliproxyRuntimeActionText =
                    "已修正 \(result.changedCount) 项：\(updatedTitles)。\(restartHint)\(backupHint)"
            }

            await refreshCLIProxyRuntimeStatus(manual: false)
        } catch {
            cliproxyRuntimeErrorText = error.localizedDescription
        }
    }

    @MainActor
    func rotateCLIProxyRuntimeManagementKey() async {
        guard !cliproxyRuntimeKeyRotating else { return }

        persistCLIProxyRuntimeConfiguration()
        persistCLIProxyOAuthConfiguration()
        cliproxyRuntimeKeyRotating = true
        cliproxyRuntimeActionText = "正在轮换 CLIProxy management key…"
        cliproxyRuntimeErrorText = ""
        cliproxyOAuthErrorText = ""

        defer {
            cliproxyRuntimeKeyRotating = false
        }

        do {
            let result = try CLIProxyRuntimeSupport.rotateManagementKey(settings: cliproxyRuntimeSettings)
            cliproxyOAuthManagementKey = result.newKey
            persistCLIProxyOAuthConfiguration()
            cliproxyRuntimeFastProbeUntilMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded()) + 20_000
            cliproxyRuntimeConfigAudit = CLIProxyRuntimeSupport.auditConfig(settings: cliproxyRuntimeSettings)

            let backupHint = result.backupPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? ""
                : " 已生成备份：\(settingsSummarySnippet(result.backupPath, limit: 54))。"

            if cliproxyRuntimeProbe.serviceRunning {
                let activated = await waitForCLIProxyRuntimeManagementKeyActivation(result.newKey)
                if activated {
                    cliproxyRuntimeActionText =
                        "已轮换 management key，Hub 和运行中 CLIProxy 已完成切换。\(backupHint)"
                    await refreshCLIProxyOAuthRemoteAuths(manual: false)
                    if cliproxyOAuthSettings.autoSync {
                        await syncCLIProxyOAuthAccounts(manual: false)
                    }
                } else {
                    cliproxyRuntimeActionText =
                        "新 management key 已写入 config.yaml 并同步到 Hub keychain；运行中 CLIProxy 还在切换，若稍后仍未接通可重启本地节点。\(backupHint)"
                }
            } else {
                cliproxyRuntimeActionText =
                    "已轮换 management key。下次从 Hub 启动本地节点时会直接使用新 key。\(backupHint)"
                await refreshCLIProxyRuntimeStatus(manual: false)
            }
        } catch {
            cliproxyRuntimeErrorText = error.localizedDescription
        }
    }

    @MainActor
    private func waitForCLIProxyRuntimeManagementKeyActivation(
        _ managementKey: String,
        timeoutSec: Double = 8.0
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSec)
        while Date() < deadline {
            let probe = await CLIProxyRuntimeSupport.probe(
                baseURL: cliproxyOAuthSettings.baseURL,
                managementKey: managementKey,
                settings: cliproxyRuntimeSettings
            )
            cliproxyRuntimeProbe = probe
            cliproxyRuntimeLastProbeAtMs = probe.probedAtMs
            cliproxyRuntimeConfigAudit = CLIProxyRuntimeSupport.auditConfig(settings: cliproxyRuntimeSettings)

            guard probe.serviceRunning else { return false }

            switch probe.managementStatus {
            case .keyValid:
                return true
            case .keyInvalid, .waitingForKey, .unavailable, .unknown, .error:
                break
            }

            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        return false
    }

    func openCLIProxyRuntimePackageDirectory() {
        let settings = cliproxyRuntimeSettings
        let packageURL = CLIProxyRuntimeSupport.packageDirectoryURL(for: settings)
        guard let packageURL else {
            cliproxyRuntimeErrorText = "还没有可打开的 CLIProxy 发行包目录。"
            return
        }
        _ = NSWorkspace.shared.open(packageURL)
    }

    func openCLIProxyRuntimeConfigFile() {
        let settings = cliproxyRuntimeSettings
        guard let configURL = CLIProxyRuntimeSupport.configURL(for: settings) else {
            cliproxyRuntimeErrorText = "还没有找到可打开的 CLIProxy config.yaml。"
            return
        }
        _ = NSWorkspace.shared.open(configURL)
    }

    private func reloadCLIProxyOAuthConfiguration() {
        let settings = CLIProxyOAuthSourceSupport.loadSettings()
        cliproxyOAuthSettings = settings
        cliproxyOAuthManagementKey = CLIProxyOAuthSourceSupport.loadManagementKey(baseURL: settings.baseURL)
    }

    func persistCLIProxyOAuthConfiguration() {
        cliproxyOAuthSettings.baseURL = CLIProxyOAuthSourceSupport.normalizedBaseURLString(
            cliproxyOAuthSettings.baseURL
        )
        _ = CLIProxyOAuthSourceSupport.saveSettings(cliproxyOAuthSettings)
        _ = CLIProxyOAuthSourceSupport.saveManagementKey(
            cliproxyOAuthManagementKey,
            baseURL: cliproxyOAuthSettings.baseURL
        )
    }

    @MainActor
    func refreshCLIProxyOAuthRemoteAuths(manual: Bool = false) async {
        guard !cliproxyOAuthRefreshing, !cliproxyOAuthSyncing else { return }

        persistCLIProxyOAuthConfiguration()
        let managementKey = cliproxyOAuthManagementKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if managementKey.isEmpty {
            if manual {
                cliproxyOAuthErrorText = "请先填写 CLIProxy management key。"
            }
            return
        }

        cliproxyOAuthRefreshing = true
        if manual {
            cliproxyOAuthActionText = "正在读取 CLIProxy 已认证账号列表…"
            cliproxyOAuthErrorText = ""
        }

        defer {
            cliproxyOAuthRefreshing = false
        }

        do {
            let auths = try await CLIProxyOAuthSourceSupport.listRemoteAuths(
                baseURL: cliproxyOAuthSettings.baseURL,
                managementKey: managementKey
            )
            cliproxyOAuthRemoteAuths = auths
            cliproxyOAuthLastRemoteFetchAtMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
            if manual {
                cliproxyOAuthActionText = auths.isEmpty
                    ? "CLIProxy 当前还没有已认证账号。"
                    : "已刷新 \(auths.count) 个 CLIProxy OAuth 账号。"
            }
        } catch {
            if manual || cliproxyOAuthRemoteAuths.isEmpty {
                cliproxyOAuthErrorText = error.localizedDescription
            }
        }
    }

    @MainActor
    func syncCLIProxyOAuthAccounts(manual: Bool = true) async {
        guard !cliproxyOAuthSyncing else { return }

        persistCLIProxyOAuthConfiguration()
        let managementKey = cliproxyOAuthManagementKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if managementKey.isEmpty {
            cliproxyOAuthErrorText = "请先填写 CLIProxy management key。"
            return
        }

        cliproxyOAuthSyncing = true
        cliproxyOAuthErrorText = ""
        cliproxyOAuthActionText = manual
            ? "正在把 CLIProxy OAuth 账号同步进 Hub 额度池…"
            : "CLIProxy OAuth 自动同步中…"

        defer {
            cliproxyOAuthSyncing = false
        }

        do {
            let summary = try await CLIProxyOAuthSourceSupport.syncAccounts(
                baseURL: cliproxyOAuthSettings.baseURL,
                managementKey: managementKey
            )
            cliproxyOAuthRemoteAuths = summary.remoteAuths
            cliproxyOAuthLastRemoteFetchAtMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
            cliproxyOAuthLastAutoSyncAtMs = cliproxyOAuthLastRemoteFetchAtMs
            let snapshot = await Task.detached(priority: .utility) {
                await Self.loadProviderKeySnapshotWithBootstrapBackground()
            }.value
            providerKeySnapshot = snapshot
            lastProviderKeyPeriodicRefreshAt = Date()
            rebuildRemoteQuotaProjectionSnapshot()
            if summary.errorMessages.isEmpty {
                cliproxyOAuthSettings.lastSyncAtMs = CLIProxyOAuthSourceSupport.loadSettings().lastSyncAtMs
                cliproxyOAuthActionText = cliproxyOAuthSyncActionText(
                    summary: summary,
                    snapshot: snapshot,
                    partial: false
                )
            } else {
                cliproxyOAuthActionText = cliproxyOAuthSyncActionText(
                    summary: summary,
                    snapshot: snapshot,
                    partial: true
                )
                cliproxyOAuthErrorText = summary.errorMessages.prefix(3).joined(separator: " | ")
            }
        } catch {
            cliproxyOAuthErrorText = error.localizedDescription
        }
    }

    @MainActor
    func startCLIProxyOAuth(_ provider: HubProviderOAuthHTTPClient.Provider) async {
        guard cliproxyOAuthActiveState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            cliproxyOAuthErrorText = "已有 Provider OAuth 登录在进行中。"
            return
        }

        cliproxyOAuthErrorText = ""
        cliproxyOAuthActionText = "正在向 Hub 发起 \(provider.title) OAuth…"

        do {
            let launch = try await HubProviderOAuthHTTPClient.startLogin(
                provider: provider,
                adminToken: grpc.localAdminToken(),
                grpcPort: grpc.port
            )
            guard let authURL = URL(string: launch.authURL),
                  let redirectURL = URL(string: launch.redirectURI) else {
                throw HubProviderOAuthHTTPClient.ClientError.apiError("invalid_oauth_login_payload")
            }

            let callbackServer = try HubProviderOAuthLoopbackCallbackServer(redirectURI: redirectURL)
            cliproxyOAuthActiveState = launch.state
            cliproxyOAuthActiveProvider = provider
            cliproxyOAuthActionText = "\(provider.title) OAuth 已打开浏览器，等待登录回调…"

            async let callbackURL = callbackServer.waitForCallback(
                timeout: oauthCallbackTimeoutSeconds(launch.expiresAtMs)
            )
            guard NSWorkspace.shared.open(authURL) else {
                cliproxyOAuthActiveState = ""
                cliproxyOAuthActiveProvider = nil
                throw HubProviderOAuthHTTPClient.ClientError.apiError("failed_to_open_browser")
            }

            let returnedURL = try await callbackURL
            cliproxyOAuthActionText = "Hub 正在导入 \(provider.title) OAuth 凭证…"
            let submit = try await HubProviderOAuthHTTPClient.submitCallback(
                provider: launch.provider.isEmpty ? provider.rawValue : launch.provider,
                state: launch.state,
                redirectURL: returnedURL.absoluteString,
                adminToken: grpc.localAdminToken(),
                grpcPort: grpc.port
            )
            guard submit.ok else {
                throw HubProviderOAuthHTTPClient.ClientError.apiError(submit.error)
            }
            await pollCLIProxyOAuthLogin()
        } catch {
            cliproxyOAuthErrorText = error.localizedDescription
            cliproxyOAuthActionText = ""
            cliproxyOAuthActiveState = ""
            cliproxyOAuthActiveProvider = nil
        }
    }

    @MainActor
    private func pollCLIProxyOAuthLogin() async {
        let activeState = cliproxyOAuthActiveState.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !activeState.isEmpty else { return }

        do {
            let status = try await HubProviderOAuthHTTPClient.status(
                state: activeState,
                adminToken: grpc.localAdminToken(),
                grpcPort: grpc.port
            )
            switch status.status {
            case "pending", "processing":
                break
            case "ok":
                let providerTitle = cliproxyOAuthActiveProvider?.title ?? "Hub"
                cliproxyOAuthActiveState = ""
                cliproxyOAuthActiveProvider = nil
                let detail = [status.email, status.accountKey]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
                cliproxyOAuthActionText = detail.isEmpty
                    ? "\(providerTitle) OAuth 已完成并导入 Hub 额度池。"
                    : "\(providerTitle) OAuth 已完成并导入 Hub 额度池：\(detail)"
                reloadProviderKeySnapshot()
            case "error", "expired", "unknown":
                let providerTitle = cliproxyOAuthActiveProvider?.title ?? "Hub"
                cliproxyOAuthActiveState = ""
                cliproxyOAuthActiveProvider = nil
                let message = status.error.isEmpty
                    ? (status.statusMessage.isEmpty ? status.status : status.statusMessage)
                    : status.error
                cliproxyOAuthErrorText = "\(providerTitle) OAuth 失败：\(message)"
            default:
                break
            }
        } catch {
            cliproxyOAuthErrorText = error.localizedDescription
            cliproxyOAuthActiveState = ""
            cliproxyOAuthActiveProvider = nil
        }
    }

    private func oauthCallbackTimeoutSeconds(_ expiresAtMs: Int64) -> TimeInterval {
        guard expiresAtMs > 0 else { return 300 }
        let remaining = max(15, (Double(expiresAtMs) / 1000.0) - Date().timeIntervalSince1970)
        return min(remaining, 600)
    }

    @MainActor
    private func maybeAutoSyncCLIProxyOAuthAccounts() async {
        guard cliproxyOAuthSettings.autoSync else { return }
        guard cliproxyOAuthActiveState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !cliproxyOAuthSyncing, !cliproxyOAuthRefreshing else { return }
        guard !cliproxyOAuthManagementKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        let baseline = max(cliproxyOAuthLastAutoSyncAtMs, cliproxyOAuthSettings.lastSyncAtMs)
        guard baseline == 0 || nowMs - baseline >= 60_000 else { return }
        cliproxyOAuthLastAutoSyncAtMs = nowMs
        await syncCLIProxyOAuthAccounts(manual: false)
    }

    func openCLIProxyOAuthManagementConsole() {
        persistCLIProxyOAuthConfiguration()
        guard cliproxyRuntimeProbe.serviceRunning else {
            cliproxyOAuthErrorText = "CLIProxy 管理页当前没有运行。Hub 原生 OAuth 可直接用“发起 OAuth”，不需要打开 CLIProxy 管理页；如果要维护旧 CLIProxy 账号，请先启动本地节点。"
            return
        }
        guard let url = CLIProxyOAuthSourceSupport.managementConsoleURL(
            baseURL: cliproxyOAuthSettings.baseURL
        ) else {
            cliproxyOAuthErrorText = "CLIProxy 地址无效。"
            return
        }
        _ = NSWorkspace.shared.open(url)
    }

    @ViewBuilder
    var cliproxyOAuthSourceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hub OAuth")
                        .font(.subheadline.weight(.semibold))
                    Text("直接从 Hub 发起 Codex / Claude / Gemini / Antigravity OAuth，登录完成后凭证会进入 Hub Provider Key 额度池。CLIProxy 只保留为旧账号导入来源。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text(cliproxyOAuthStatusBadgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(cliproxyOAuthStatusTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(cliproxyOAuthStatusTint.opacity(0.12))
                    .clipShape(Capsule())
            }

            cliproxyRuntimeControlPanel

            Rectangle()
                .fill(Color.indigo.opacity(0.08))
                .frame(height: 1)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CLIProxy 地址")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("http://127.0.0.1:8317", text: $cliproxyOAuthSettings.baseURL)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Management Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("Bearer 管理 key", text: $cliproxyOAuthManagementKey)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack(spacing: 12) {
                Toggle("自动同步", isOn: $cliproxyOAuthSettings.autoSync)
                    .toggleStyle(.switch)

                if cliproxyOAuthSettings.lastSyncAtMs > 0 {
                    Text("上次成功同步 \(formattedProviderKeyImportSourceTime(cliproxyOAuthSettings.lastSyncAtMs))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("还没有成功同步记录")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            terminalAccessFeedbackBanner(
                text: cliproxyOAuthHubRoutingStatusText,
                tint: cliproxyOAuthHubRoutingStatusTint,
                systemName: cliproxyOAuthHubRoutingStatusSystemName
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("常用动作")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        cliproxyOAuthActionButton(
                            title: "保存",
                            systemName: "square.and.arrow.down",
                            tint: .blue
                        ) {
                            persistCLIProxyRuntimeConfiguration()
                            persistCLIProxyOAuthConfiguration()
                            cliproxyOAuthActionText = "CLIProxy 接入设置已保存。"
                            cliproxyOAuthErrorText = ""
                        }

                        cliproxyOAuthActionButton(
                            title: cliproxyOAuthSyncing ? "同步中" : "同步到 Hub",
                            systemName: "shippingbox.and.arrow.backward",
                            tint: .green,
                            disabled: cliproxyOAuthSyncing
                        ) {
                            Task { await syncCLIProxyOAuthAccounts(manual: true) }
                        }

                        Menu {
                            ForEach(HubProviderOAuthHTTPClient.Provider.allCases) { provider in
                                Button(provider.title) {
                                    Task { await startCLIProxyOAuth(provider) }
                                }
                            }
                        } label: {
                            settingsActionChipLabel(
                                title: "发起 OAuth",
                                systemName: "person.badge.key",
                                tint: .indigo,
                                disabled: cliproxyOAuthSyncing
                            )
                        }
                        .disabled(cliproxyOAuthSyncing)

                        Menu {
                            Button("打开管理页") {
                                openCLIProxyOAuthManagementConsole()
                            }
                            Button(cliproxyOAuthRefreshing ? "刷新中" : "刷新账号") {
                                Task { await refreshCLIProxyOAuthRemoteAuths(manual: true) }
                            }
                            .disabled(cliproxyOAuthRefreshing || cliproxyOAuthSyncing)
                        } label: {
                            settingsActionChipLabel(
                                title: "维护",
                                systemName: "ellipsis.circle",
                                tint: .secondary
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            cliproxyOAuthActionButton(
                                title: "保存",
                                systemName: "square.and.arrow.down",
                                tint: .blue
                            ) {
                                persistCLIProxyRuntimeConfiguration()
                                persistCLIProxyOAuthConfiguration()
                                cliproxyOAuthActionText = "CLIProxy 接入设置已保存。"
                                cliproxyOAuthErrorText = ""
                            }

                            cliproxyOAuthActionButton(
                                title: cliproxyOAuthSyncing ? "同步中" : "同步到 Hub",
                                systemName: "shippingbox.and.arrow.backward",
                                tint: .green,
                                disabled: cliproxyOAuthSyncing
                            ) {
                                Task { await syncCLIProxyOAuthAccounts(manual: true) }
                            }
                        }

                        HStack(spacing: 8) {
                            Menu {
                                ForEach(HubProviderOAuthHTTPClient.Provider.allCases) { provider in
                                    Button(provider.title) {
                                        Task { await startCLIProxyOAuth(provider) }
                                    }
                                }
                            } label: {
                                settingsActionChipLabel(
                                    title: "发起 OAuth",
                                    systemName: "person.badge.key",
                                    tint: .indigo,
                                    disabled: cliproxyOAuthSyncing
                                )
                            }
                            .disabled(cliproxyOAuthSyncing)

                            Menu {
                                Button("打开管理页") {
                                    openCLIProxyOAuthManagementConsole()
                                }
                                Button(cliproxyOAuthRefreshing ? "刷新中" : "刷新账号") {
                                    Task { await refreshCLIProxyOAuthRemoteAuths(manual: true) }
                                }
                                .disabled(cliproxyOAuthRefreshing || cliproxyOAuthSyncing)
                            } label: {
                                settingsActionChipLabel(
                                    title: "维护",
                                    systemName: "ellipsis.circle",
                                    tint: .secondary
                                )
                            }
                        }
                    }
                }

                Text("新登录直接由 Hub 接管；保存、同步、刷新和管理页只用于旧 CLIProxy 账号导入。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !cliproxyOAuthActionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                terminalAccessFeedbackBanner(
                    text: cliproxyOAuthActionText,
                    tint: .blue,
                    systemName: "person.crop.circle.badge.checkmark"
                )
            }

            if !cliproxyOAuthErrorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                terminalAccessFeedbackBanner(
                    text: cliproxyOAuthErrorText,
                    tint: .red,
                    systemName: "exclamationmark.triangle"
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("已认证账号")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    if cliproxyOAuthLastRemoteFetchAtMs > 0 {
                        Text("列表刷新 \(formattedProviderKeyImportSourceTime(cliproxyOAuthLastRemoteFetchAtMs))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if cliproxyOAuthRemoteAuths.isEmpty {
                    Text("当前还没有旧 CLIProxy 已认证账号。新账号直接点上面的 OAuth 按钮由 Hub 接管。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(cliproxyOAuthRemoteAuths) { auth in
                        cliproxyOAuthAuthRow(auth)
                    }
                }
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    Color.indigo.opacity(0.10),
                    Color.blue.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.indigo.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    var cliproxyOAuthStatusBadgeText: String {
        if cliproxyOAuthSyncing {
            return "同步中"
        }
        if cliproxyOAuthRefreshing {
            return "刷新中"
        }
        if let provider = cliproxyOAuthActiveProvider,
           !cliproxyOAuthActiveState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(provider.title) 登录中"
        }
        if cliproxyOAuthSettings.autoSync {
            return "自动同步开"
        }
        return "手动同步"
    }

    private var cliproxyOAuthStatusTint: Color {
        if cliproxyOAuthSyncing || cliproxyOAuthRefreshing {
            return .blue
        }
        if !cliproxyOAuthActiveState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .orange
        }
        return cliproxyOAuthSettings.autoSync ? .green : .secondary
    }

    private func cliproxyOAuthProviderTint(
        _ provider: CLIProxyOAuthSourceSupport.OAuthProvider
    ) -> Color {
        switch provider {
        case .claude:
            return .orange
        case .codex:
            return .blue
        case .gemini:
            return .mint
        case .antigravity:
            return .purple
        case .kimi:
            return .red
        }
    }

    func cliproxyOAuthActionButton(
        title: String,
        systemName: String,
        tint: Color,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            settingsActionChipLabel(
                title: title,
                systemName: systemName,
                tint: tint,
                disabled: disabled
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func cliproxyOAuthProviderOverviewCard(
        _ summary: CLIProxyOAuthProviderInventorySummary
    ) -> some View {
        let tint = cliproxyOAuthProviderSummaryTint(summary)
        let readyFraction = summary.totalCount > 0
            ? CGFloat(summary.readyCount) / CGFloat(summary.totalCount)
            : 0

        return Button {
            focusProviderKeyVendor(
                cliproxyOAuthProviderVendorKey(summary.providerKey),
                displayName: summary.displayName
            )
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(summary.displayName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text("\(summary.readyCount)/\(summary.totalCount)")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(tint)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(tint.opacity(0.14))

                        Capsule()
                            .fill(tint.opacity(0.78))
                            .frame(
                                width: readyFraction > 0
                                    ? max(12, proxy.size.width * readyFraction)
                                    : 0
                            )
                    }
                }
                .frame(height: 7)

                Text(cliproxyOAuthProviderSummaryText(summary))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(12)
        .background(tint.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .buttonStyle(.plain)
    }

    private func cliproxyOAuthProviderSummaryTint(
        _ summary: CLIProxyOAuthProviderInventorySummary
    ) -> Color {
        if summary.blockedCount > 0 {
            return .red
        }
        if summary.coolingCount > 0 {
            return .orange
        }
        if summary.readyCount > 0 {
            return cliproxyOAuthProviderTintKey(summary.providerKey)
        }
        if summary.disabledCount == summary.totalCount {
            return .gray
        }
        return .secondary
    }

    private func cliproxyOAuthProviderSummaryText(
        _ summary: CLIProxyOAuthProviderInventorySummary
    ) -> String {
        HubUIStrings.Settings.RemoteModels.sectionSummary([
            summary.readyCount > 0 ? "可用 \(summary.readyCount)" : "",
            summary.coolingCount > 0 ? "冷却 \(summary.coolingCount)" : "",
            summary.blockedCount > 0 ? "阻断 \(summary.blockedCount)" : "",
            summary.refreshingCount > 0 ? "刷新 \(summary.refreshingCount)" : "",
            summary.waitingCount > 0 ? "等待 \(summary.waitingCount)" : "",
            summary.disabledCount > 0 ? "停用 \(summary.disabledCount)" : ""
        ])
    }

    private func cliproxyOAuthInventoryState(
        _ auth: CLIProxyOAuthSourceSupport.RemoteAuthFile
    ) -> CLIProxyOAuthInventoryState {
        if auth.disabled {
            return .disabled
        }
        if auth.quota.exceeded || auth.nextRetryAtMs > 0 {
            return .cooling
        }
        if auth.unavailable {
            return .blocked
        }

        let normalized = auth.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "active", "ok", "ready":
            return .ready
        case "refreshing":
            return .refreshing
        case "pending", "wait":
            return .waiting
        case "error", "blocked", "failed":
            return .blocked
        default:
            if normalized.contains("refresh") {
                return .refreshing
            }
            if normalized.contains("wait") || normalized.contains("pending") {
                return .waiting
            }
            if normalized.contains("error")
                || normalized.contains("block")
                || normalized.contains("fail") {
                return .blocked
            }
            return normalized.isEmpty ? .waiting : .blocked
        }
    }

    private func cliproxyOAuthCanonicalProviderKey(_ rawProvider: String) -> String {
        let normalized = rawProvider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "anthropic", "claude":
            return "claude"
        case "chatgpt", "openai", "codex", "openai_compatible":
            return "codex"
        case "gemini", "gemini-cli", "google":
            return "gemini"
        case "antigravity":
            return "antigravity"
        case "kimi", "moonshot":
            return "kimi"
        default:
            return normalized.isEmpty ? "unknown" : normalized
        }
    }

    private func cliproxyOAuthProviderVendorKey(_ providerKey: String) -> String {
        switch cliproxyOAuthCanonicalProviderKey(providerKey) {
        case "codex":
            return "openai"
        default:
            return cliproxyOAuthCanonicalProviderKey(providerKey)
        }
    }

    private func cliproxyOAuthProviderDisplayName(_ providerKey: String) -> String {
        switch providerKey {
        case "claude":
            return "Claude"
        case "codex":
            return "Codex"
        case "gemini":
            return "Gemini"
        case "antigravity":
            return "Antigravity"
        case "kimi":
            return "Kimi"
        default:
            return providerKey.isEmpty ? "Unknown" : providerKey.capitalized
        }
    }

    private func cliproxyOAuthProviderSortIndex(_ providerKey: String) -> Int {
        switch providerKey {
        case "claude":
            return 0
        case "codex":
            return 1
        case "gemini":
            return 2
        case "antigravity":
            return 3
        case "kimi":
            return 4
        default:
            return 99
        }
    }

    private func cliproxyOAuthProviderTintKey(_ providerKey: String) -> Color {
        switch providerKey {
        case "claude":
            return .orange
        case "codex":
            return .blue
        case "gemini":
            return .mint
        case "antigravity":
            return .purple
        case "kimi":
            return .red
        default:
            return .secondary
        }
    }

    private func minimumPositiveTimestamp(_ lhs: Int64, _ rhs: Int64) -> Int64? {
        let values = [lhs, rhs].filter { $0 > 0 }
        return values.min()
    }

    @ViewBuilder
    private func cliproxyOAuthAuthRow(
        _ auth: CLIProxyOAuthSourceSupport.RemoteAuthFile
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(cliproxyOAuthAuthStateColor(auth))
                .frame(width: 8, height: 8)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(cliproxyOAuthAuthTitle(auth))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)

                    Text(cliproxyOAuthAuthStateText(auth))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(cliproxyOAuthAuthStateColor(auth))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(cliproxyOAuthAuthStateColor(auth).opacity(0.12))
                        .clipShape(Capsule())

                    if auth.quota.exceeded {
                        Text("额度受限")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    if auth.runtimeOnly {
                        Text("runtime-only")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                Text(cliproxyOAuthAuthMetaText(auth))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                let timingText = cliproxyOAuthAuthTimingText(auth)
                if !timingText.isEmpty {
                    Text(timingText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !auth.statusMessage.isEmpty && auth.statusMessage != auth.quota.reason {
                    Text(auth.statusMessage)
                        .font(.caption2)
                        .foregroundStyle(cliproxyOAuthAuthStateColor(auth))
                        .fixedSize(horizontal: false, vertical: true)
                } else if !auth.quota.reason.isEmpty {
                    Text(auth.quota.reason)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(cliproxyOAuthAuthStateColor(auth).opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func cliproxyOAuthAuthTitle(
        _ auth: CLIProxyOAuthSourceSupport.RemoteAuthFile
    ) -> String {
        if !auth.email.isEmpty {
            return auth.email
        }
        if !auth.label.isEmpty {
            return auth.label
        }
        return auth.name
    }

    private func cliproxyOAuthAuthStateText(
        _ auth: CLIProxyOAuthSourceSupport.RemoteAuthFile
    ) -> String {
        if auth.disabled {
            return "禁用"
        }
        if auth.quota.exceeded || auth.nextRetryAtMs > 0 {
            return "冷却中"
        }

        switch auth.status.lowercased() {
        case "active", "ok", "ready":
            return "可用"
        case "refreshing":
            return "刷新中"
        case "pending", "wait":
            return "等待中"
        case "error":
            return "异常"
        default:
            return auth.status.isEmpty ? "未知" : auth.status
        }
    }

    private func cliproxyOAuthAuthStateColor(
        _ auth: CLIProxyOAuthSourceSupport.RemoteAuthFile
    ) -> Color {
        if auth.disabled {
            return .gray
        }
        if auth.quota.exceeded || auth.nextRetryAtMs > 0 {
            return .orange
        }
        switch auth.status.lowercased() {
        case "active", "ok", "ready":
            return .green
        case "refreshing":
            return .blue
        case "pending", "wait":
            return .yellow
        case "error":
            return .red
        default:
            return .secondary
        }
    }

    private func cliproxyOAuthAuthMetaText(
        _ auth: CLIProxyOAuthSourceSupport.RemoteAuthFile
    ) -> String {
        HubUIStrings.Settings.RemoteModels.sectionSummary([
            auth.provider.uppercased(),
            !auth.accountType.isEmpty && !auth.account.isEmpty ? "\(auth.accountType) \(auth.account)" : "",
            !auth.accountType.isEmpty && auth.account.isEmpty ? auth.accountType : "",
            !auth.account.isEmpty && auth.accountType.isEmpty ? auth.account : "",
            !auth.runtimeAuthIndex.isEmpty ? "runtime \(String(auth.runtimeAuthIndex.prefix(10)))" : "",
            auth.name
        ])
    }

    private func cliproxyOAuthAuthTimingText(
        _ auth: CLIProxyOAuthSourceSupport.RemoteAuthFile
    ) -> String {
        var parts: [String] = []
        if auth.lastRefreshAtMs > 0 {
            parts.append("上次刷新 \(formattedProviderKeyImportSourceTime(auth.lastRefreshAtMs))")
        }
        if auth.nextRefreshAtMs > 0 {
            parts.append("下次刷新 \(formattedProviderKeyImportSourceTime(auth.nextRefreshAtMs))")
        }
        if auth.nextRetryAtMs > 0 {
            parts.append("重试 \(formattedProviderKeyImportSourceTime(auth.nextRetryAtMs))")
        }
        if auth.quota.nextRecoverAtMs > 0 {
            parts.append("额度恢复 \(formattedProviderKeyImportSourceTime(auth.quota.nextRecoverAtMs))")
        }
        return HubUIStrings.Settings.RemoteModels.sectionSummary(parts)
    }

    func providerKeyPoolTitle(_ pool: ProviderKeyPoolSnapshot) -> String {
        if pool.providerHost.isEmpty {
            return pool.supplierDisplayName
        }
        return "\(pool.supplierDisplayName) · \(pool.providerHost)"
    }

    func providerKeyPoolDetail(_ pool: ProviderKeyPoolSnapshot) -> String {
        HubUIStrings.Settings.RemoteModels.sectionSummary([
            pool.poolID,
            pool.wireAPI == "default" ? "" : pool.wireAPI,
            pool.lastRefreshAtMs > 0 ? "上次刷新 \(formattedProviderKeyImportSourceTime(pool.lastRefreshAtMs))" : ""
        ])
    }

    func providerKeyPoolQuotaSummary(_ pool: ProviderKeyPoolSnapshot) -> String {
        HubUIStrings.Settings.RemoteModels.sectionSummary([
            HubUIStrings.Settings.ProviderKeys.dailyUsageText(
                used: pool.totalDailyTokensUsed,
                cap: pool.totalDailyTokenCap
            ),
            pool.totalTokensUsed > 0
                ? "累计 \(HubUIStrings.Settings.ProviderKeys.tokenCount(pool.totalTokensUsed))"
                : ""
        ])
    }

    @ViewBuilder
    func providerKeyPoolIssueSummaryView(_ pool: ProviderKeyPoolSnapshot) -> some View {
        let summary = pool.issueSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = pool.issueDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        let isExpanded = expandedProviderKeyPoolIssueIDs.contains(pool.id)
        let tint = providerKeyPoolStateColor(pool.state)

        if !summary.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(tint)
                        .fixedSize(horizontal: false, vertical: true)

                    if !detail.isEmpty {
                        Button {
                            if isExpanded {
                                expandedProviderKeyPoolIssueIDs.remove(pool.id)
                            } else {
                                expandedProviderKeyPoolIssueIDs.insert(pool.id)
                            }
                        } label: {
                            Image(systemName: isExpanded ? "chevron.up.circle.fill" : "info.circle")
                                .imageScale(.small)
                                .foregroundStyle(tint)
                        }
                        .buttonStyle(.plain)
                        .help(isExpanded ? "收起详细错误" : "展开详细错误")
                    }
                }

                if isExpanded && !detail.isEmpty {
                    Text(detail)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    func providerKeyPoolRetrySummary(_ pool: ProviderKeyPoolSnapshot) -> String {
        if let retryText = pool.members
            .map({ $0.account.errorState.retryAtText.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return HubUIStrings.Settings.ProviderKeys.nextRetry(retryText)
        }
        guard pool.earliestRetryAtMs > 0 else {
            return HubUIStrings.Settings.ProviderKeys.nextRetryUnknown
        }
        return HubUIStrings.Settings.ProviderKeys.nextRetry(
            formattedProviderKeyImportSourceTime(pool.earliestRetryAtMs)
        )
    }

    func providerKeyPoolStateColor(_ state: String) -> Color {
        switch state {
        case "ready":
            return .green
        case "cooldown":
            return .orange
        case "blocked":
            return .red
        case "disabled":
            return .gray
        case "mixed":
            return .yellow
        default:
            return .secondary
        }
    }

    func providerKeyPoolStateText(_ state: String) -> String {
        switch state {
        case "ready":
            return HubUIStrings.Settings.ProviderKeys.ready
        case "cooldown":
            return HubUIStrings.Settings.ProviderKeys.cooldown
        case "blocked":
            return HubUIStrings.Settings.ProviderKeys.blocked
        case "disabled":
            return HubUIStrings.Settings.ProviderKeys.disabled
        case "stale":
            return HubUIStrings.Settings.ProviderKeys.stale
        case "degraded":
            return HubUIStrings.Settings.ProviderKeys.degraded
        case "mixed":
            return HubUIStrings.Settings.ProviderKeys.mixed
        default:
            return state
        }
    }

    func providerKeyMemberStateColor(_ member: ProviderKeyPoolMemberState) -> Color {
        switch member.state {
        case "ready":
            return .green
        case "degraded":
            return .yellow
        case "cooldown":
            return .orange
        case "blocked":
            return .red
        case "stale":
            return .red.opacity(0.75)
        case "disabled":
            return .gray
        default:
            return .secondary
        }
    }

    func providerKeyMemberTitle(_ member: ProviderKeyPoolMemberState) -> String {
        let account = member.account
        return account.email.isEmpty ? account.apiKeyRedacted : account.email
    }

    func providerKeyMemberSourceText(_ account: ProviderKeyAccount) -> String {
        let sourceRef = account.sourceRef.isEmpty ? "" : URL(fileURLWithPath: account.sourceRef).lastPathComponent
        return HubUIStrings.Settings.RemoteModels.sectionSummary([
            !account.accountId.isEmpty ? "id \(account.accountId)" : "",
            !account.sourceType.isEmpty ? account.sourceType : "",
            !sourceRef.isEmpty ? sourceRef : "",
            !account.runtimeAuthIndex.isEmpty ? "runtime \(String(account.runtimeAuthIndex.prefix(10)))" : "",
            account.authType == "oauth" && account.expiresAtMs > 0
                ? "过期 \(formattedProviderKeyImportSourceTime(account.expiresAtMs))"
                : ""
        ])
    }

    func providerKeyDisplayUsageWindows(_ account: ProviderKeyAccount) -> [ProviderKeyUsageWindow] {
        let windows = account.quota.usageWindows
        guard !windows.isEmpty else { return [] }

        let rateLimitWindows = windows.filter {
            $0.source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "rate_limit"
        }
        let preferredRateLimitWindows = rateLimitWindows.filter {
            $0.limitWindowSeconds == 5 * 60 * 60 || $0.limitWindowSeconds == 7 * 24 * 60 * 60
        }
        let selected: [ProviderKeyUsageWindow]
        if !preferredRateLimitWindows.isEmpty {
            selected = preferredRateLimitWindows
        } else if !rateLimitWindows.isEmpty {
            selected = Array(rateLimitWindows.prefix(2))
        } else {
            selected = Array(windows.prefix(2))
        }

        return selected.sorted {
            let lhsRank = providerKeyUsageWindowRank($0)
            let rhsRank = providerKeyUsageWindowRank($1)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return $0.limitWindowSeconds < $1.limitWindowSeconds
        }
    }

    func providerKeyPoolDisplayUsageWindows(_ pool: ProviderKeyPoolSnapshot) -> [ProviderKeyUsageWindow] {
        var groupedWindows: [String: ProviderKeyUsageWindow] = [:]

        for member in pool.members {
            for window in providerKeyDisplayUsageWindows(member.account) {
                let groupKey = providerKeyUsageWindowGroupKey(window)
                var normalizedWindow = window
                normalizedWindow.key = "pool:\(pool.id):\(groupKey)"

                guard var existingWindow = groupedWindows[groupKey] else {
                    groupedWindows[groupKey] = normalizedWindow
                    continue
                }

                var selectedWindow = providerKeyMoreConstrainedUsageWindow(
                    existingWindow,
                    normalizedWindow
                )
                selectedWindow.key = "pool:\(pool.id):\(groupKey)"
                selectedWindow.limited = existingWindow.limited || normalizedWindow.limited || selectedWindow.limited
                selectedWindow.resetAtMs = providerKeyEarliestPositiveTimestamp(
                    existingWindow.resetAtMs,
                    normalizedWindow.resetAtMs
                )
                selectedWindow.updatedAtMs = max(existingWindow.updatedAtMs, normalizedWindow.updatedAtMs)
                existingWindow = selectedWindow
                groupedWindows[groupKey] = existingWindow
            }
        }

        return groupedWindows.values.sorted {
            let lhsRank = providerKeyUsageWindowRank($0)
            let rhsRank = providerKeyUsageWindowRank($1)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if $0.limitWindowSeconds != $1.limitWindowSeconds {
                return $0.limitWindowSeconds < $1.limitWindowSeconds
            }
            return $0.key < $1.key
        }
    }

    private func providerKeyUsageWindowGroupKey(_ window: ProviderKeyUsageWindow) -> String {
        let source = window.source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let windowKey = window.windowKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedSource = source.isEmpty ? "usage" : source
        let normalizedWindowKey = windowKey.isEmpty ? "window" : windowKey

        if window.limitWindowSeconds > 0 {
            return "\(normalizedSource):\(normalizedWindowKey):\(window.limitWindowSeconds)"
        }

        let rawKey = window.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(normalizedSource):\(normalizedWindowKey):\(rawKey.isEmpty ? "unknown" : rawKey)"
    }

    private func providerKeyMoreConstrainedUsageWindow(
        _ lhs: ProviderKeyUsageWindow,
        _ rhs: ProviderKeyUsageWindow
    ) -> ProviderKeyUsageWindow {
        if lhs.limited != rhs.limited {
            return rhs.limited ? rhs : lhs
        }

        let lhsPercent = providerKeyUsageWindowPercent(lhs)
        let rhsPercent = providerKeyUsageWindowPercent(rhs)
        if lhsPercent != rhsPercent {
            return rhsPercent > lhsPercent ? rhs : lhs
        }

        if lhs.resetAtMs != rhs.resetAtMs {
            return providerKeyEarliestPositiveTimestamp(lhs.resetAtMs, rhs.resetAtMs) == rhs.resetAtMs ? rhs : lhs
        }
        return lhs.key <= rhs.key ? lhs : rhs
    }

    private func providerKeyEarliestPositiveTimestamp(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        if lhs <= 0 { return max(0, rhs) }
        if rhs <= 0 { return lhs }
        return min(lhs, rhs)
    }

    func providerKeyUsageWindowRank(_ window: ProviderKeyUsageWindow) -> Int {
        switch window.limitWindowSeconds {
        case 5 * 60 * 60:
            return 0
        case 7 * 24 * 60 * 60:
            return 1
        default:
            return 10
        }
    }

    func providerKeyUsageWindowTitle(_ window: ProviderKeyUsageWindow) -> String {
        switch window.limitWindowSeconds {
        case 5 * 60 * 60:
            return "5 小时额度"
        case 7 * 24 * 60 * 60:
            return "7 天额度"
        case let seconds where seconds >= 24 * 60 * 60:
            let days = max(1, Int((Double(seconds) / Double(24 * 60 * 60)).rounded()))
            return "\(days) 天额度"
        case let seconds where seconds >= 60 * 60:
            let hours = max(1, Int((Double(seconds) / Double(60 * 60)).rounded()))
            return "\(hours) 小时额度"
        default:
            let label = window.label.trimmingCharacters(in: .whitespacesAndNewlines)
            return label.isEmpty ? "额度窗口" : label
        }
    }

    func providerKeyUsageWindowPercent(_ window: ProviderKeyUsageWindow) -> Double {
        let percent = window.usedPercent > 0
            ? window.usedPercent
            : Double(max(0, min(10_000, window.usedBasisPoints))) / 100.0
        return max(0, min(100, percent))
    }

    func providerKeyUsageWindowPercentText(_ window: ProviderKeyUsageWindow) -> String {
        String(format: "%.1f%%", providerKeyUsageWindowPercent(window))
    }

    func providerKeyUsageWindowResetText(_ window: ProviderKeyUsageWindow) -> String {
        guard window.resetAtMs > 0 else { return "" }
        return "重置 \(formattedProviderKeyImportSourceTime(window.resetAtMs))"
    }

    func providerKeyUsageWindowTint(_ window: ProviderKeyUsageWindow) -> Color {
        if window.limited {
            return .red
        }
        switch providerKeyUsageWindowPercent(window) {
        case let value where value >= 95:
            return .red
        case let value where value >= 80:
            return .orange
        case let value where value >= 45:
            return .yellow
        default:
            return .green
        }
    }

    func providerKeyMemberQuotaText(_ account: ProviderKeyAccount) -> String {
        var parts: [String] = []
        if account.quota.usageWindows.isEmpty,
           account.quota.dailyTokensUsed > 0 || account.quota.dailyTokenCap > 0 {
            parts.append(
                HubUIStrings.Settings.ProviderKeys.dailyUsageText(
                    used: account.quota.dailyTokensUsed,
                    cap: account.quota.dailyTokenCap
                )
            )
        }
        if account.quota.totalTokensUsed > 0 {
            parts.append("累计 \(HubUIStrings.Settings.ProviderKeys.tokenCount(account.quota.totalTokensUsed))")
        }
        if !account.quota.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(account.quota.reason)
        }
        if let nextRecover = providerKeyTimestampSummary(
            max(account.quota.nextRecoverAtMs, account.quota.cooldownUntilMs),
            prefix: "恢复"
        ) {
            parts.append(nextRecover)
        }
        if let nextRefresh = providerKeyTimestampSummary(
            account.refreshState.nextRefreshAtMs,
            prefix: "下次刷新"
        ) {
            parts.append(nextRefresh)
        }
        return HubUIStrings.Settings.RemoteModels.sectionSummary(parts)
    }

    func providerKeyMemberHeatLabel(_ account: ProviderKeyAccount) -> String {
        let fraction = providerKeyUsageFraction(
            used: account.quota.dailyTokensUsed,
            cap: account.quota.dailyTokenCap
        )
        switch fraction {
        case let value where value >= 0.95:
            return "热度 见底"
        case let value where value >= 0.8:
            return "热度 高"
        case let value where value >= 0.45:
            return "热度 中"
        case let value where value > 0:
            return "热度 低"
        default:
            return "热度 空闲"
        }
    }

    func providerKeyPoolRemainingSummary(_ pool: ProviderKeyPoolSnapshot) -> String {
        var parts: [String] = []
        if pool.totalDailyTokenCap > 0 {
            parts.append(
                "剩余 \(HubUIStrings.Settings.ProviderKeys.tokenCount(max(Int64(0), pool.totalDailyTokensRemaining))) / \(HubUIStrings.Settings.ProviderKeys.tokenCount(pool.totalDailyTokenCap)) tokens"
            )
        } else if pool.totalDailyTokensRemaining > 0 {
            parts.append("剩余 \(HubUIStrings.Settings.ProviderKeys.tokenCount(pool.totalDailyTokensRemaining)) tokens")
        }
        if let lastUsed = providerKeyTimestampSummary(
            pool.members.map(\.account.quota.lastUsedAtMs).max() ?? 0,
            prefix: "最近使用"
        ) {
            parts.append(lastUsed)
        }
        return HubUIStrings.Settings.RemoteModels.sectionSummary(parts)
    }

    func providerKeyMemberUsageMetaText(_ account: ProviderKeyAccount) -> String {
        var parts: [String] = []
        if account.quota.usageWindows.isEmpty {
            if account.quota.dailyTokenCap > 0 {
                parts.append(
                    "剩余 \(HubUIStrings.Settings.ProviderKeys.tokenCount(max(Int64(0), account.quota.dailyTokensRemaining))) / \(HubUIStrings.Settings.ProviderKeys.tokenCount(account.quota.dailyTokenCap)) tokens"
                )
            } else if account.quota.dailyTokensRemaining > 0 {
                parts.append("剩余 \(HubUIStrings.Settings.ProviderKeys.tokenCount(account.quota.dailyTokensRemaining)) tokens")
            }
        }
        if let lastUsed = providerKeyTimestampSummary(account.quota.lastUsedAtMs, prefix: "最近使用") {
            parts.append(lastUsed)
        }
        if let lastRefresh = providerKeyTimestampSummary(
            max(account.lastRefreshAtMs, account.refreshState.lastSuccessAtMs),
            prefix: "上次刷新"
        ) {
            parts.append(lastRefresh)
        }
        if account.refreshState.failureCount > 0 {
            parts.append("刷新失败 \(account.refreshState.failureCount) 次")
        }
        if !account.refreshState.status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           account.refreshState.status != "idle" {
            parts.append("刷新状态 \(account.refreshState.status)")
        }
        return HubUIStrings.Settings.RemoteModels.sectionSummary(parts)
    }

    func providerKeyFamilyQuotaSummary(_ family: ProviderKeyFamilyInventorySummary) -> String {
        var parts: [String] = []
        if family.combinedDailyTokenCap > 0 {
            parts.append(
                "上游今日 \(HubUIStrings.Settings.ProviderKeys.tokenCount(family.combinedDailyTokensUsed)) / \(HubUIStrings.Settings.ProviderKeys.tokenCount(family.combinedDailyTokenCap)) tokens"
            )
            parts.append("剩余 \(HubUIStrings.Settings.ProviderKeys.tokenCount(family.combinedDailyTokensRemaining))")
        } else if family.combinedDailyTokensUsed > 0 {
            parts.append("上游今日已用 \(HubUIStrings.Settings.ProviderKeys.tokenCount(family.combinedDailyTokensUsed)) tokens")
        }
        if family.quotaPool.sharedSources > 0 {
            parts.append(
                HubUIStrings.Settings.ProviderKeys.sharedSourceSummary(
                    count: family.quotaPool.sharedSources,
                    sharedFamilies: family.quotaPool.sharedWithFamilyDisplayNames.joined(separator: ", ")
                )
            )
        }
        return HubUIStrings.Settings.RemoteModels.sectionSummary(parts)
    }

    func providerKeyFamilyBudgetSummary(_ family: ProviderKeyFamilyInventorySummary) -> String {
        var parts: [String] = []
        if family.assignedClientCount > 0 {
            parts.append("覆盖 \(family.coveredUserCount) 个用户 / \(family.assignedClientCount) 个消费者")
        }
        if family.connectedAssignedConsumerCount > 0 {
            parts.append("在线 \(family.connectedAssignedConsumerCount)")
        }
        if family.assignedDailyTokenBudget > 0 {
            parts.append("覆盖预算 \(HubUIStrings.Settings.ProviderKeys.tokenCount(family.assignedDailyTokenBudget))")
        }
        if family.unlimitedBudgetConsumerCount > 0 {
            parts.append("\(family.unlimitedBudgetConsumerCount) 个未设硬预算")
        }
        if family.observedDailyTokensUsed > 0 {
            parts.append("今日已用 \(HubUIStrings.Settings.ProviderKeys.tokenCount(family.observedDailyTokensUsed))")
        }
        if parts.isEmpty {
            parts.append("当前还没有消费者显式使用这个家族")
        }
        return HubUIStrings.Settings.RemoteModels.sectionSummary(parts)
    }

    func providerKeyFamilyClientPreview(_ family: ProviderKeyFamilyInventorySummary) -> String {
        let previewNames = family.assignedClients.prefix(3).map(\.name)
        guard !previewNames.isEmpty else { return "" }
        let suffix = family.assignedClients.count > previewNames.count
            ? " 等另外 \(family.assignedClients.count - previewNames.count) 个"
            : ""
        return "消费者：\(previewNames.joined(separator: "、"))\(suffix)"
    }

    func providerKeyFamilyRetrySummary(_ family: ProviderKeyFamilyInventorySummary) -> String {
        if let retryText = family.quotaPool.sources
            .flatMap(\.members)
            .map({ $0.account.errorState.retryAtText.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return HubUIStrings.Settings.ProviderKeys.nextRetry(retryText)
        }
        guard family.quotaPool.earliestRetryAtMs > 0 else {
            return HubUIStrings.Settings.ProviderKeys.nextRetryUnknown
        }
        return HubUIStrings.Settings.ProviderKeys.nextRetry(
            formattedProviderKeyImportSourceTime(family.quotaPool.earliestRetryAtMs)
        )
    }

    func providerKeyBudgetClientScopeSummary(_ clientProjection: RemoteQuotaCenterClientProjection) -> String {
        var parts: [String] = []
        if clientProjection.allowsAllFamilies {
            parts.append("允许所有已知付费家族")
        } else if !clientProjection.familyDisplayNames.isEmpty {
            parts.append("家族 \(clientProjection.familyDisplayNames.joined(separator: " / "))")
        } else {
            parts.append("当前还没有解析到模型家族")
        }
        if clientProjection.paidModelCount > 0 {
            parts.append("模型白名单 \(clientProjection.paidModelCount) 个")
        }
        if !clientProjection.appId.isEmpty {
            parts.append("app \(clientProjection.appId)")
        }
        return HubUIStrings.Settings.RemoteModels.sectionSummary(parts)
    }

    func providerKeyBudgetClientActivitySummary(_ clientProjection: RemoteQuotaCenterClientProjection) -> String {
        var parts: [String] = []
        if !clientProjection.topModel.isEmpty {
            parts.append(HubUIStrings.Settings.GRPC.DeviceList.topModel(clientProjection.topModel))
        }
        if let status = clientProjection.deviceStatus {
            if status.requestsToday > 0 {
                parts.append(HubUIStrings.Settings.GRPC.DeviceList.requests(status.requestsToday))
            }
            if status.blockedToday > 0 {
                parts.append(HubUIStrings.Settings.GRPC.DeviceList.blocked(status.blockedToday))
            }
            if let lastUsed = providerKeyTimestampSummary(
                status.modelBreakdown.map(\.lastUsedAtMs).max() ?? 0,
                prefix: "最近命中"
                ) {
                parts.append(lastUsed)
            }
        } else if let accessKey = clientProjection.terminalAccessKey {
            if let lastUsed = providerKeyTimestampSummary(accessKey.lastUsedAtMs, prefix: "最近使用") {
                parts.append(lastUsed)
            }
        }
        return HubUIStrings.Settings.RemoteModels.sectionSummary(parts)
    }

    func providerKeyUsageFraction(used: Int64, cap: Int64) -> Double {
        guard cap > 0 else { return 0 }
        let normalizedUsed = max(Double(used), 0)
        let normalizedCap = max(Double(cap), 1)
        return max(0, min(1, normalizedUsed / normalizedCap))
    }

    func providerKeySignedTokenCount(_ value: Int64) -> String {
        let magnitude = HubUIStrings.Settings.ProviderKeys.tokenCount(abs(value))
        if value > 0 { return "+\(magnitude)" }
        if value < 0 { return "-\(magnitude)" }
        return magnitude
    }

    func providerKeyTrendWindowSummary(
        _ aggregate: RemoteQuotaTrendAggregate
    ) -> String {
        let bucketMinutes = max(Int64(1), aggregate.bucketMs / (60 * 1000))
        let windowMinutes = max(Int64(1), aggregate.windowMs / (60 * 1000))
        if windowMinutes >= 60 {
            return "1h / \(bucketMinutes)m"
        }
        return "\(windowMinutes)m / \(bucketMinutes)m"
    }

    func providerKeyTrendMomentumText(
        _ aggregate: RemoteQuotaTrendAggregate
    ) -> String {
        if aggregate.recentTokens15m <= 0 && aggregate.previousTokens15m <= 0 {
            return "近 30 分钟基本无明显远端流量。"
        }
        if aggregate.previousTokens15m <= 0 {
            return "最近 15 分钟刚开始放量。"
        }
        guard let momentum = aggregate.momentumRatio else {
            return "最近 30 分钟流量稳定。"
        }
        let percent = Int((abs(momentum) * 100).rounded())
        if percent < 8 {
            return "较前 15 分钟基本持平。"
        }
        if momentum > 0 {
            return "较前 15 分钟提升 \(percent)%。"
        }
        return "较前 15 分钟回落 \(percent)%。"
    }

    func providerKeyTrendMomentumColor(
        _ aggregate: RemoteQuotaTrendAggregate
    ) -> Color {
        guard let momentum = aggregate.momentumRatio else {
            return aggregate.recentTokens15m > 0 ? .teal : .secondary
        }
        if abs(momentum) < 0.08 {
            return .secondary
        }
        return momentum > 0 ? .orange : .teal
    }

    private func providerKeyTimestampSummary(_ timestampMs: Int64, prefix: String) -> String? {
        guard timestampMs > 0 else { return nil }
        return "\(prefix) \(formattedProviderKeyImportSourceTime(timestampMs))"
    }

    @ViewBuilder
    func providerKeyMemberIssueSummaryView(_ member: ProviderKeyPoolMemberState) -> some View {
        let summary = member.reasonMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = member.detailMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let isExpanded = expandedProviderKeyMemberIssueIDs.contains(member.id)
        let tint = providerKeyMemberStateColor(member)

        if !summary.isEmpty && member.state != "ready" {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(tint)
                        .fixedSize(horizontal: false, vertical: true)

                    if !detail.isEmpty {
                        Button {
                            if isExpanded {
                                expandedProviderKeyMemberIssueIDs.remove(member.id)
                            } else {
                                expandedProviderKeyMemberIssueIDs.insert(member.id)
                            }
                        } label: {
                            Image(systemName: isExpanded ? "chevron.up.circle.fill" : "info.circle")
                                .imageScale(.small)
                                .foregroundStyle(tint)
                        }
                        .buttonStyle(.plain)
                        .help(isExpanded ? "收起详细错误" : "展开详细错误")
                    }
                }

                if isExpanded && !detail.isEmpty {
                    Text(detail)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    func providerKeyMemberRetryText(_ member: ProviderKeyPoolMemberState) -> String? {
        let explicitText = member.account.errorState.retryAtText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitText.isEmpty {
            return HubUIStrings.Settings.ProviderKeys.nextRetry(explicitText)
        }
        guard member.nextRetryAtMs > 0 else { return nil }
        return HubUIStrings.Settings.ProviderKeys.nextRetry(
            formattedProviderKeyImportSourceTime(member.nextRetryAtMs)
        )
    }

    func accountStatusColor(_ account: ProviderKeyAccount) -> Color {
        if !account.enabled { return .gray }
        switch account.errorState.status {
        case "healthy": return .green
        case "degraded": return .yellow
        case "rate_limited": return .orange
        case "auth_failed": return .red
        case "disabled": return .gray
        default: return .secondary
        }
    }

    func errorStateDescription(_ state: ProviderKeyErrorState) -> String {
        switch state.status {
        case "healthy": return HubUIStrings.Settings.ProviderKeys.healthy
        case "degraded": return HubUIStrings.Settings.ProviderKeys.degraded
        case "rate_limited":
            if state.lastErrorCode == "429" {
                return HubUIStrings.Settings.ProviderKeys.rateLimited
            }
            return "\(HubUIStrings.Settings.ProviderKeys.rateLimited) (\(state.lastErrorCode))"
        case "auth_failed":
            return "\(HubUIStrings.Settings.ProviderKeys.authFailed) (\(state.lastErrorCode))"
        case "disabled":
            return HubUIStrings.Settings.ProviderKeys.disabled
        default: return state.status
        }
    }

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

    private static func sortedRemoteModels(_ models: [RemoteModelEntry]) -> [RemoteModelEntry] {
        RemoteModelPresentationSupport.sorted(models)
    }

    nonisolated private static func emptyRemoteQuotaProjection() -> RemoteQuotaCenterProjection {
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

    nonisolated private static func emptyProviderKeySectionSnapshot() -> ProviderKeySectionSnapshot {
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

    nonisolated private static func loadProviderKeySnapshotWithBootstrapBackground() async -> ProviderKeyStoreSnapshot {
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

    nonisolated private static func makeRemoteModelGroupsSnapshot(
        from models: [RemoteModelEntry],
        healthSnapshot: RemoteKeyHealthSnapshot
    ) -> [RemoteModelKeyGroup] {
        RemoteModelPresentationSupport.groups(
            from: models,
            healthSnapshot: healthSnapshot
        )
        .map { group in
            RemoteModelKeyGroup(
                id: group.id,
                keyReference: group.keyReference,
                title: group.title,
                detail: group.detail,
                models: group.models,
                loadedCount: group.loadedCount,
                availableCount: group.availableCount,
                needsSetupCount: group.needsSetupCount,
                enabledCount: group.enabledCount
            )
        }
    }

    private func rebuildRemoteModelGroupsSnapshot() {
        let models = remoteModels
        let healthSnapshot = store.remoteKeyHealthSnapshot
        remoteModelGroupsBuildTask?.cancel()
        remoteModelGroupsBuildTask = Task { @MainActor in
            let groups = await Task.detached(priority: .utility) {
                Self.makeRemoteModelGroupsSnapshot(
                    from: models,
                    healthSnapshot: healthSnapshot
                )
            }.value
            guard !Task.isCancelled else { return }
            remoteModelGroupsSnapshot = groups
        }
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

    private func rebuildRemoteQuotaProjectionSnapshot() {
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

    private func reloadRemoteModels() {
        remoteModels = Self.sortedRemoteModels(RemoteModelStorage.load().models)
        rebuildRemoteModelGroupsSnapshot()
        if selectedSettingsPage == .models && providerQuotaOperationsExpanded {
            rebuildRemoteQuotaProjectionSnapshot()
        }
    }

    private func upsertRemoteModel(_ entry: RemoteModelEntry) {
        upsertRemoteModels([entry])
    }

    private func upsertRemoteModels(_ entries: [RemoteModelEntry]) {
        guard !entries.isEmpty else { return }
        for entry in entries {
            _ = RemoteModelStorage.upsert(entry)
        }
        remoteModels = Self.sortedRemoteModels(RemoteModelStorage.load().models)
        rebuildRemoteModelGroupsSnapshot()
        ModelStore.shared.refresh()
    }

    func removeRemoteModel(id: String) {
        let snap = RemoteModelStorage.remove(id: id)
        remoteModels = Self.sortedRemoteModels(snap.models)
        rebuildRemoteModelGroupsSnapshot()
        ModelStore.shared.refresh()
    }

    func removeRemoteModelGroup(_ group: RemoteModelKeyGroup) {
        let snap = RemoteModelStorage.remove(ids: group.models.map(\.id))
        remoteModels = Self.sortedRemoteModels(snap.models)
        rebuildRemoteModelGroupsSnapshot()
        ModelStore.shared.refresh()
    }

    private func updateRemoteModelGroupDisplayName(_ group: RemoteModelKeyGroup, displayName: String) {
        let normalized = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelIDs = Set(group.models.map(\.id))
        guard !modelIDs.isEmpty else { return }

        for index in remoteModels.indices where modelIDs.contains(remoteModels[index].id) {
            remoteModels[index].groupDisplayName = normalized.isEmpty ? nil : normalized
        }
        remoteModels = Self.sortedRemoteModels(remoteModels)
        rebuildRemoteModelGroupsSnapshot()
        persistRemoteModels()
    }

    func setRemoteModelsEnabled(_ modelIDs: [String], enabled: Bool) {
        let ids = Set(modelIDs)
        guard !ids.isEmpty else { return }

        var updated = remoteModels
        var changed = false
        for index in updated.indices where ids.contains(updated[index].id) {
            if enabled {
                var candidate = updated[index]
                candidate.enabled = true
                guard RemoteModelStorage.isExecutionReadyRemoteModel(candidate) else { continue }
            }

            if updated[index].enabled != enabled {
                updated[index].enabled = enabled
                changed = true
            }
        }

        guard changed else { return }
        remoteModels = Self.sortedRemoteModels(updated)
        rebuildRemoteModelGroupsSnapshot()
        persistRemoteModels()
    }

    private func persistRemoteModels() {
        let snap = RemoteModelSnapshot(models: remoteModels, updatedAt: Date().timeIntervalSince1970)
        RemoteModelStorage.save(snap)
        ModelStore.shared.refresh()
    }

    private func importRemoteCatalog(_ result: ImportRemoteCatalogResult) {
        let apiKey = result.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { return }

        let apiKeyRef = "remote_catalog:default"

        let baseURL = RemoteCatalogClient.defaultBaseURL.absoluteString
        let idPrefix = normalizeModelPrefix(result.idPrefix)

        var imported: [RemoteModelEntry] = []
        for raw in result.modelIds {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let baseModelId = normalizeRemoteCatalogModelID(trimmed)
            if baseModelId.isEmpty { continue }

            let fullId: String = {
                if idPrefix.isEmpty { return baseModelId }
                let a = baseModelId.lowercased()
                let p = idPrefix.lowercased()
                if a.hasPrefix(p) { return baseModelId }
                return idPrefix + baseModelId
            }()

            let entry = RemoteModelEntry(
                id: fullId,
                name: remoteCatalogDisplayName(modelId: baseModelId),
                backend: "remote_catalog",
                contextLength: remoteCatalogContextLength(modelId: baseModelId),
                enabled: result.enabled,
                baseURL: baseURL,
                apiKeyRef: apiKeyRef,
                upstreamModelId: baseModelId,
                apiKey: apiKey,
                note: HubUIStrings.Settings.RemoteModels.remoteCatalogNote,
                knownContextLength: remoteCatalogContextLength(modelId: baseModelId),
                knownContextSource: .catalogEstimate
            )
            imported.append(entry)
        }

        if imported.isEmpty {
            return
        }

        var updated = remoteModels
        if result.replaceExisting {
            updated.removeAll { RemoteProviderEndpoints.isRemoteCatalogBackend($0.backend) }
        }
        for m in imported {
            if let idx = updated.firstIndex(where: { $0.id == m.id }) {
                updated[idx] = m
            } else {
                updated.append(m)
            }
        }
        remoteModels = Self.sortedRemoteModels(updated)
        rebuildRemoteModelGroupsSnapshot()
        persistRemoteModels()
    }

    private func normalizeModelPrefix(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "" }
        // Normalize to "provider/".
        if !s.hasSuffix("/") {
            s += "/"
        }
        return s
    }

    private func normalizeRemoteCatalogModelID(_ raw: String) -> String {
        RemoteProviderEndpoints.stripModelRef(raw)
    }

    private func remoteCatalogDisplayName(modelId: String) -> String {
        let t = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }
        let map: [String: String] = [
            "gpt-5.1-codex": "GPT-5.1 Codex",
            "gpt-5.1-codex-mini": "GPT-5.1 Codex Mini",
            "gpt-5.1-codex-max": "GPT-5.1 Codex Max",
            "gpt-5.2": "GPT-5.2",
            "gpt-5.1": "GPT-5.1",
            "claude-opus-4-5": "Claude Opus 4.5",
            "gemini-3-pro": "Gemini 3 Pro",
            "gemini-3-flash": "Gemini 3 Flash",
            "glm-4.7": "GLM-4.7",
        ]
        if let v = map[t.lowercased()] {
            return v
        }
        return t
    }

    private func remoteCatalogContextLength(modelId: String) -> Int {
        let t = modelId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return 128_000 }
        let map: [String: Int] = [
            "gpt-5.1-codex": 400_000,
            "gpt-5.1-codex-mini": 400_000,
            "gpt-5.1-codex-max": 400_000,
            "gpt-5.2": 400_000,
            "gpt-5.1": 400_000,
            "claude-opus-4-5": 200_000,
            "gemini-3-pro": 1_048_576,
            "gemini-3-flash": 1_048_576,
            "glm-4.7": 204_800,
        ]
        return map[t] ?? 128_000
    }

    private func reloadNetworkPolicies() {
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

    var remoteModelGroups: [RemoteModelKeyGroup] {
        remoteModelGroupsSnapshot
    }
}
