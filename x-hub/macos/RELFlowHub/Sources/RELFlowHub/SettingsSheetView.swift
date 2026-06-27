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
    @State var hubLaunchHistory: HubLaunchHistorySnapshot = HubLaunchHistoryStorage.load()
    @State var diagnosticsBundleIsExporting: Bool = false
    @State var diagnosticsBundleArchivePath: String = ""
    @State var diagnosticsBundleManifestPath: String = ""
    @State var diagnosticsBundleMissingFiles: [String] = []
    @State var diagnosticsBundleError: String = ""
    @State var unifiedDoctorReportIsExporting: Bool = false
    @State var unifiedDoctorReportPath: String = ""
    @State var unifiedDoctorChannelReportPath: String = ""
    @State var unifiedDoctorReportError: String = ""
    @State var fixNowIsRunning: Bool = false
    @State var fixNowResultText: String = ""
    @State var fixNowErrorText: String = ""
    @State var diagnosticsActionIsRunning: Bool = false
    @State var diagnosticsActionResultText: String = ""
    @State var diagnosticsActionErrorText: String = ""
    @State var settingsScrollTarget: String? = nil
    @State var highlightedProviderKeySourceRef: String? = nil
    @State var highlightedProviderKeyVendorKey: String? = nil
    @State var expandedProviderKeyPoolIssueIDs: Set<String> = []
    @State var expandedProviderKeyMemberIssueIDs: Set<String> = []
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
    @State var operatorChannelProviderReadiness: [HubOperatorChannelOnboardingDeliveryReadiness] = []
    @State var operatorChannelProviderRuntimeStatus: [HubOperatorChannelProviderRuntimeStatus] = []
    @State var operatorChannelProviderReadinessError: String = ""
    @State var operatorChannelProviderReadinessInFlight: Bool = false
    @State var operatorChannelProviderReadinessActionText: String = ""
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
    @State var cliproxyRuntimeFastProbeUntilMs: Int64 = 0
    @State var rustHubRuntimeSnapshot: RustHubRuntimeSnapshot = RustHubRuntimeSupport.localSnapshot()
    @State var rustHubRuntimeRefreshing: Bool = false
    @State var rustHubRuntimeLastRefreshAt: Date = .distantPast
    @State var rustLocalMLExecutionReadinessSnapshot: RustLocalMLExecutionReadinessSnapshot = .empty
    @State var rustLocalMLExecutionReadinessRefreshing: Bool = false
    @State var rustLocalMLExecutionReadinessLastRefreshAt: Date = .distantPast
    @State var rustLocalModelRepairPlan: RustLocalModelRepairPlan? = nil
    @State var rustLocalModelRepairPlanRefreshing: Bool = false
    @State var rustLocalModelRepairPlanLastRefreshAt: Date = .distantPast
    @State var rustLocalModelRepairApplyDialogPresented: Bool = false
    @State var rustLocalModelRepairApplyPendingPlan: RustLocalModelRepairPlan? = nil
    @State var rustLocalModelRepairApplyInFlight: Bool = false
    @State var rustLocalModelRepairApplyResult: RustLocalModelRepairApplyResult? = nil
    @State var rustLocalModelRepairExecutorInFlight: Bool = false
    @State var rustLocalModelRepairExecutorResult: RustLocalModelRepairExecutorResult? = nil
    @State var rustLocalModelRepairApplyErrorText: String = ""
    @State var rustLocalModelRepairJobsSnapshot: RustLocalModelRepairJobsSnapshot = .empty
    @State var rustLocalModelRepairJobsRefreshing: Bool = false
    @State var rustLocalModelRepairJobsLastRefreshAt: Date = .distantPast
    @State var rustHubRemoteEntryCandidates: RustHubRemoteEntryCandidates = .empty
    @State var rustHubRemoteEntryRefreshing: Bool = false
    @State var rustHubRemoteEntryLastRefreshAt: Date = .distantPast
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
    @State var cliproxyOAuthLastAutoSyncAtMs: Int64 = 0
    @State var remoteQuotaBudgetEditorTarget: RemoteQuotaBudgetEditorTarget? = nil
    @State var remoteQuotaFocusedUserGroupingKey: String = ""
    @State var remoteQuotaFocusedVendorKey: String = ""
    @State var remoteQuotaVendorFilter: RemoteQuotaVendorFilter = .all
    @State var remoteQuotaUserFilter: RemoteQuotaUserFilter = .all
    @State var remoteQuotaConsumerFilter: RemoteQuotaConsumerFilter = .all
    @State var selectedSettingsPage: HubSettingsPage = .overview
    @State var modelCatalogDetailsExpanded: Bool = false
    @State var modelsAutoScanExpanded: Bool = false
    @State var providerQuotaOperationsExpanded: Bool = false
    @State var runtimeRoutingExpanded: Bool = false
    @State var integrationsAuxExpanded: Bool = false
    @State var diagnosticsLaunchExpanded: Bool = false
    @State var diagnosticsNetworkExpanded: Bool = false
    @State var diagnosticsAdvancedExpanded: Bool = false
    @State var expandedGRPCClientDetailIDs: Set<String> = []
    @State var expandedTerminalAccessKeyDetailIDs: Set<String> = []
    @State var expandedProviderKeyVendorIDs: Set<String> = []
    @State var expandedProviderKeyPoolIDs: Set<String> = []
    @State var terminalAccessIssueExpanded: Bool = false
    @State var terminalAccessLastSecretExpanded: Bool = false
    @State var expandedRemoteModelGroupIDs: Set<String> = []
    @State var remoteModelCatalogExpanded: Bool = false
    @State var remoteModelGroupsSnapshot: [RemoteModelKeyGroup] = []
    @State var providerImportSourcesExpanded: Bool = false
    @State var providerKeyImportSourceRemovalTarget: ProviderKeyImportSourceRemovalTarget? = nil
    @State var providerVendorLedgerExpanded: Bool = false
    @State var providerFamilyLedgerExpanded: Bool = false
    @State var providerPhysicalPoolsExpanded: Bool = false
    @State var providerUserLedgerExpanded: Bool = false
    @State var providerConsumerLedgerExpanded: Bool = false
    @State var providerOAuthExpanded: Bool = false
    @State var providerFlowExpanded: Bool = false
    @State var providerTrendExpanded: Bool = false
    @State var remoteModelGroupsBuildTask: Task<Void, Never>? = nil
    @State var providerKeyReloadTask: Task<Void, Never>? = nil
    @State var remoteQuotaProjectionSnapshot: RemoteQuotaCenterProjection = Self.emptyRemoteQuotaProjection()
    @State var remoteQuotaProjectionBuildTask: Task<Void, Never>? = nil
    @State var providerKeySectionSnapshot: ProviderKeySectionSnapshot = Self.emptyProviderKeySectionSnapshot()
    @State var lastProviderKeyPeriodicRefreshAt: Date = .distantPast
    @State var lastRemoteQuotaProjectionPeriodicRefreshAt: Date = .distantPast

    var axTrusted: Bool {
        DockBadgeReader.ensureAccessibilityTrusted(prompt: false)
    }

    var xhubLocalServiceRecoveryGuidance: XHubLocalServiceRecoveryGuidance? {
        if rustLocalMLAuthorityMode {
            return nil
        }
        return XHubLocalServiceRecoveryGuidanceBuilder.build(
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
        if rustLocalMLAuthorityMode {
            return rustLocalModelRepairSurfaceSummary
        }
        return rustLocalModelRepairSurfaceSummary ?? runtimeRepairSurfaceSummary
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

    var remoteQuotaProjection: RemoteQuotaCenterProjection {
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
                refreshRustLocalMLExecutionReadiness(force: true)
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
        .alert(
            providerKeyImportSourceRemovalTitle(providerKeyImportSourceRemovalTarget),
            isPresented: Binding(
                get: { providerKeyImportSourceRemovalTarget != nil },
                set: { newValue in
                    if !newValue {
                        providerKeyImportSourceRemovalTarget = nil
                    }
                }
            ),
            presenting: providerKeyImportSourceRemovalTarget
        ) { target in
            Button(providerKeyImportSourceRemovalConfirmTitle(target), role: .destructive) {
                removeProviderKeyImportSource(target)
            }
            Button(HubUIStrings.Settings.GRPC.cancel, role: .cancel) {
                providerKeyImportSourceRemovalTarget = nil
            }
        } message: { target in
            Text(providerKeyImportSourceRemovalMessage(target))
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


}
