import SwiftUI
import AppKit
import RELFlowHubCore

private struct RemoteModelSignalVisual: Identifiable {
    let title: String
    let systemName: String
    let tint: Color

    var id: String { title }
}

struct SettingsSheetView: View {
    @EnvironmentObject var store: HubStore
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var grpc = HubGRPCServerSupport.shared
    @ObservedObject private var modelStore = ModelStore.shared
    @ObservedObject private var servingPower = HubServingPowerManager.shared
    @ObservedObject private var remoteRouteProbe = HubRemoteAccessRouteProbe.shared

    @State private var remoteModels: [RemoteModelEntry] = sortedRemoteModels(RemoteModelStorage.load().models)
    @State private var showAddRemoteModel: Bool = false
    @State private var showImportRemoteCatalog: Bool = false
    @State private var editingRemoteModelGroup: RemoteModelKeyGroup? = nil
    @State private var networkPolicies: [HubNetworkPolicyRule] = HubNetworkPolicyStorage.load().policies
    @State private var showAddNetworkPolicy: Bool = false
    @State private var showAddGRPCClient: Bool = false
    @State private var editingGRPCClient: HubGRPCClientEntry? = nil
    @State private var editingGRPCClientFocusCapabilityKey: String? = nil
    @State private var deletingGRPCClient: HubGRPCClientEntry? = nil
    @State private var grpcClientListFilter: GRPCClientListFilter = .all
    @State private var grpcDevicesStatus: GRPCDevicesStatusSnapshot = GRPCDevicesStatusStorage.load()
    @State private var grpcDeniedAttempts: GRPCDeniedAttemptsSnapshot = GRPCDeniedAttemptsStorage.load()
    @State private var hubLaunchStatus: HubLaunchStatusSnapshot? = HubLaunchStatusStorage.load()
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

    @State private var skillsIndex: HubSkillsStoreStorage.SkillsIndexSnapshot = HubSkillsStoreStorage.loadSkillsIndex()
    @State private var skillsPins: HubSkillsStoreStorage.SkillPinsSnapshot = HubSkillsStoreStorage.loadSkillPins()
    @State private var skillsSources: HubSkillsStoreStorage.SkillSourcesSnapshot = HubSkillsStoreStorage.loadSkillSources()
    @State private var skillsSearchQuery: String = ""
    @State private var skillsResolveUserId: String = ""
    @State private var skillsResolveProjectId: String = ""
    @State private var skillsLastActionText: String = ""
    @State private var skillsLastErrorText: String = ""
    @State private var axConstitutionVersion: String = ""
    @State private var axConstitutionEnabledClauseIds: [String] = []
    @State private var axConstitutionErrorText: String = ""
    @State private var operatorChannelProviderReadiness: [HubOperatorChannelOnboardingDeliveryReadiness] = []
    @State private var operatorChannelProviderRuntimeStatus: [HubOperatorChannelProviderRuntimeStatus] = []
    @State private var operatorChannelProviderReadinessError: String = ""
    @State private var operatorChannelProviderReadinessInFlight: Bool = false
    @State private var operatorChannelProviderReadinessActionText: String = ""

    private var axTrusted: Bool {
        DockBadgeReader.ensureAccessibilityTrusted(prompt: false)
    }

    private var xhubLocalServiceRecoveryGuidance: XHubLocalServiceRecoveryGuidance? {
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

    private var grpcRemoteAccessHealthSummary: HubRemoteAccessHealthSummary {
        HubRemoteAccessHealthSummaryBuilder.build(
            autoStartEnabled: grpc.autoStart,
            serverRunning: grpc.isServingAvailable,
            externalHost: grpc.xtTerminalInternetHost,
            hasInviteToken: grpc.hasExternalInviteToken,
            keepSystemAwakeWhileServing: servingPower.keepSystemAwakeWhileServing
        )
    }

    private func quitApp() {
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
        VStack(alignment: .leading, spacing: 12) {
            header
            formContent
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 620, height: 640)
        .onAppear {
            remoteRouteProbe.refresh(host: grpc.xtTerminalInternetHost)
            handleSettingsNavigationTarget(store.settingsNavigationTarget)
        }
        .onChange(of: store.settingsNavigationTarget) { target in
            handleSettingsNavigationTarget(target)
        }
        .onReceive(Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()) { _ in
            // Lightweight status snapshot exported by Node server for device presence/quotas.
            grpcDevicesStatus = GRPCDevicesStatusStorage.load()
            grpcDeniedAttempts = GRPCDeniedAttemptsStorage.load()
            hubLaunchStatus = HubLaunchStatusStorage.load()
            hubLaunchHistory = HubLaunchHistoryStorage.load()
            skillsIndex = HubSkillsStoreStorage.loadSkillsIndex()
            skillsPins = HubSkillsStoreStorage.loadSkillPins()
            skillsSources = HubSkillsStoreStorage.loadSkillSources()
            reloadAXConstitutionStatus()
            Task { await reloadOperatorChannelProviderReadiness() }
            remoteRouteProbe.refresh(host: grpc.xtTerminalInternetHost)
        }
        .onReceive(NotificationCenter.default.publisher(for: .relflowhubRemoteModelsChanged)) { _ in
            reloadRemoteModels()
        }
        .sheet(isPresented: $showAddRemoteModel) {
            AddRemoteModelSheet { entries in
                upsertRemoteModels(entries)
            }
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
        }
    }

    private func presentGRPCClientEditor(
        _ client: HubGRPCClientEntry?,
        capabilityFocusKey: String? = nil
    ) {
        editingGRPCClientFocusCapabilityKey = hubNormalizedPairedDeviceCapabilityFocusKey(capabilityFocusKey)
        editingGRPCClient = client
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(HubUIStrings.Settings.title)
                        .font(.headline)
                    Text(HubUIStrings.Settings.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(HubUIStrings.Settings.done) { dismiss() }
            }
            Text(HubUIStrings.Settings.validationChain)
                .font(.caption.monospaced())
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var formContent: some View {
        Form {
            setupCenterSection
            firstRunFastPathSection
            quickTroubleshootSection
            grpcServerSection
            operatorChannelReadinessSection
            operatorChannelOnboardingSection
            routingSection
            remoteModelsSection
            modelHealthAutoScanSection
            calendarSection
            doctorSection
            runtimeMonitorSection
            diagnosticsSection
            networkPoliciesSection
            networkingSection
            floatingModeSection
            skillsSection
            advancedSection
            quitSection
        }
        .formStyle(.grouped)
        .onAppear {
            reloadRemoteModels()
            reloadNetworkPolicies()
            reloadAXConstitutionStatus()
            Task { await reloadOperatorChannelProviderReadiness() }
        }
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

    private var floatingModeSection: some View {
        Section(HubUIStrings.Settings.FloatingMode.sectionTitle) {
            Picker(HubUIStrings.Settings.FloatingMode.mode, selection: $store.floatingMode) {
                ForEach(FloatingMode.allCases, id: \.self) { m in
                    Text(m.title).tag(m)
                }
            }
            .pickerStyle(.segmented)

            Text(HubUIStrings.Settings.FloatingMode.reminderHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var legacyCountsOnlyIntegrationsEnabled: Bool {
        store.integrationMailEnabled || store.integrationMessagesEnabled || store.integrationSlackEnabled
    }

    private var doctorSection: some View {
        Section(HubUIStrings.Settings.Doctor.sectionTitle) {
            HStack {
                Text(HubUIStrings.Settings.Doctor.accessibility)
                Spacer()
                Text(axTrusted ? HubUIStrings.Settings.Doctor.authorized : HubUIStrings.Settings.Doctor.unauthorized)
                    .foregroundStyle(.secondary)
            }
            if !axTrusted {
                HStack(spacing: 10) {
                    Button(HubUIStrings.Settings.Doctor.requestAccess) {
                        NSApp.activate(ignoringOtherApps: true)
                        _ = DockBadgeReader.ensureAccessibilityTrusted(prompt: true)
                        SystemSettingsLinks.openAccessibilityPrivacy()
                    }
                    Button(HubUIStrings.Settings.Doctor.openSettings) { SystemSettingsLinks.openAccessibilityPrivacy() }
                    Spacer()
                }
            }

            if legacyCountsOnlyIntegrationsEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text(HubUIStrings.Settings.Doctor.legacyCountsEnabled)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(HubUIStrings.Settings.Doctor.legacyCountsHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if !store.integrationsStatusText.isEmpty || !store.integrationsDebugText.isEmpty {
                        DisclosureGroup(HubUIStrings.Settings.Doctor.legacyDetails) {
                            if !store.integrationsStatusText.isEmpty {
                                Text(store.integrationsStatusText)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(
                                store.integrationsDebugText.isEmpty
                                    ? HubUIStrings.Settings.Doctor.debugInfoEmpty
                                    : store.integrationsDebugText
                            )
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                HStack(spacing: 10) {
                    Button(HubUIStrings.Settings.Doctor.disableLegacyCounts) {
                        disableLegacyCountsOnlyIntegrations()
                    }
                    Spacer()
                }
            }

            HStack {
                Text(HubUIStrings.Settings.Doctor.localRuntime)
                Spacer()
                Text(store.aiRuntimeStatusText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !store.aiRuntimeDoctorSummaryText.isEmpty {
                Text(store.aiRuntimeDoctorSummaryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let guidance = xhubLocalServiceRecoveryGuidance {
                DisclosureGroup(HubUIStrings.Settings.Doctor.recoveryDisclosure) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(HubUIStrings.Settings.Doctor.actionCategory)
                            Spacer()
                            Text(guidance.actionCategory)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        HStack {
                            Text(HubUIStrings.Settings.Doctor.severity)
                            Spacer()
                            Text(guidance.severity.uppercased())
                                .font(.caption2.monospaced())
                                .foregroundStyle(localServiceRecoverySeverityColor(guidance.severity))
                                .textSelection(.enabled)
                        }
                        HStack {
                            Text(HubUIStrings.Settings.Doctor.primaryIssueCode)
                            Spacer()
                            Text(guidance.primaryIssue.reasonCode)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        if !guidance.serviceBaseURL.isEmpty {
                            HStack {
                                Text(HubUIStrings.Settings.Doctor.serviceBaseURL)
                                Spacer()
                                Text(guidance.serviceBaseURL)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        Text(guidance.primaryIssue.headline)
                            .font(.caption.weight(.semibold))
                        Text(guidance.primaryIssue.message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text(HubUIStrings.Settings.Doctor.installHintTitle)
                            .font(.caption.weight(.semibold))
                        Text(guidance.installHint)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)

                        if !guidance.recommendedActions.isEmpty {
                            Text(HubUIStrings.Settings.Doctor.recommendedActionsTitle)
                                .font(.caption.weight(.semibold))
                            let rankedActions = Array(guidance.recommendedActions.enumerated())
                            ForEach(rankedActions, id: \.offset) { item in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(HubUIStrings.Settings.numberedItem(item.offset + 1, title: item.element.title))
                                        .font(.caption)
                                    Text(item.element.why)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    if !item.element.commandOrReference.isEmpty {
                                        Text(item.element.commandOrReference)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if !guidance.supportFAQ.isEmpty {
                            Text(HubUIStrings.Settings.Doctor.supportFAQTitle)
                                .font(.caption.weight(.semibold))
                            ForEach(guidance.supportFAQ) { item in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.question)
                                        .font(.caption)
                                    Text(item.answer)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        HStack(spacing: 10) {
                            Button(HubUIStrings.Settings.Doctor.copyRecoverySummary) {
                                copyXHubLocalServiceRecoveryToClipboard(guidance)
                            }
                            Spacer()
                        }
                        .font(.caption)
                    }
                    .padding(.top, 4)
                }
            }
            HStack(spacing: 10) {
                Button(HubUIStrings.Settings.RuntimeMonitor.copyProviderSummary) {
                    copyLocalProviderSummaryToClipboard(snapshot: hubLaunchStatus)
                }
                Button(HubUIStrings.Settings.RuntimeMonitor.openLog) {
                    store.openAIRuntimeLog()
                }
                Spacer()
            }
            .font(.caption)
        }
    }

    private func disableLegacyCountsOnlyIntegrations() {
        store.integrationMailEnabled = false
        store.integrationMessagesEnabled = false
        store.integrationSlackEnabled = false
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

    private var runtimeMonitorSection: some View {
        Section(HubUIStrings.Settings.RuntimeMonitor.sectionTitle) {
            if let summary = runtimeRepairSurfaceSummary {
                LocalRuntimeRepairEntryCard(
                    summary: summary,
                    onCopySummary: { copyLocalRuntimeRepairSummary(summary) },
                    onOpenLog: { store.openAIRuntimeLog() }
                )
            }

            if let status = store.aiRuntimeStatusSnapshot,
               let monitor = status.monitorSnapshot {
                let runtimeOpsSummary = LocalRuntimeOperationsSummaryBuilder.build(
                    status: status,
                    models: modelStore.snapshot.models,
                    currentTargetsByModelID: modelStore.currentLocalRuntimeRequestContextByModelId
                )
                let currentTargets = modelStore.snapshot.models.compactMap { model -> (HubModel, LocalModelRuntimeRequestContext)? in
                    guard let requestContext = modelStore.currentLocalRuntimeRequestContextByModelId[model.id] else {
                        return nil
                    }
                    return (model, requestContext)
                }
                .sorted {
                    let lhsName = ($0.0.name.isEmpty ? $0.0.id : $0.0.name)
                    let rhsName = ($1.0.name.isEmpty ? $1.0.id : $1.0.name)
                    let nameOrder = lhsName.localizedCaseInsensitiveCompare(rhsName)
                    if nameOrder != .orderedSame {
                        return nameOrder == .orderedAscending
                    }
                    return $0.0.id.localizedCaseInsensitiveCompare($1.0.id) == .orderedAscending
                }
                VStack(alignment: .leading, spacing: 12) {
                    if !status.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) {
                        Text(HubUIStrings.Settings.RuntimeMonitor.staleHeartbeat)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 130), spacing: 8)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        runtimeMonitorMetricCard(
                            title: HubUIStrings.Settings.RuntimeMonitor.Metric.providersTitle,
                            value: HubUIStrings.Settings.RuntimeMonitor.Metric.providersValue(
                                ready: monitor.providers.filter(\.ok).count,
                                total: monitor.providers.count
                            ),
                            detail: HubUIStrings.Settings.RuntimeMonitor.Metric.providersDetail(
                                hasProviders: !monitor.providers.isEmpty
                            )
                        )
                        runtimeMonitorMetricCard(
                            title: HubUIStrings.Settings.RuntimeMonitor.Metric.queueTitle,
                            value: HubUIStrings.Settings.RuntimeMonitor.Metric.queueValue(
                                active: monitor.queue.activeTaskCount,
                                queued: monitor.queue.queuedTaskCount
                            ),
                            detail: HubUIStrings.Settings.RuntimeMonitor.Metric.queueDetail(
                                busy: monitor.queue.providersBusyCount,
                                maxOldestWaitMs: monitor.queue.maxOldestWaitMs
                            )
                        )
                        runtimeMonitorMetricCard(
                            title: HubUIStrings.Settings.RuntimeMonitor.Metric.instancesTitle,
                            value: HubUIStrings.Settings.RuntimeMonitor.Metric.instancesValue(monitor.loadedInstances.count),
                            detail: HubUIStrings.Settings.RuntimeMonitor.Metric.instancesDetail(
                                taskCount: monitor.activeTasks.count
                            )
                        )
                        runtimeMonitorMetricCard(
                            title: HubUIStrings.Settings.RuntimeMonitor.Metric.fallbackTitle,
                            value: HubUIStrings.Settings.RuntimeMonitor.Metric.fallbackValue(
                                providerCount: monitor.fallbackCounters.fallbackReadyProviderCount
                            ),
                            detail: HubUIStrings.Settings.RuntimeMonitor.Metric.fallbackDetail(
                                taskCount: monitor.fallbackCounters.fallbackReadyTaskCount
                            )
                        )
                        runtimeMonitorMetricCard(
                            title: HubUIStrings.Settings.RuntimeMonitor.Metric.errorsTitle,
                            value: "\(monitor.lastErrors.count)",
                            detail: HubUIStrings.Settings.RuntimeMonitor.Metric.errorsDetail(
                                hasErrors: !monitor.lastErrors.isEmpty
                            )
                        )
                        runtimeMonitorMetricCard(
                            title: HubUIStrings.Settings.RuntimeMonitor.Metric.updatedAtTitle,
                            value: formatEpochSeconds(monitor.updatedAt),
                            detail: HubUIStrings.Settings.RuntimeMonitor.updatedAtDetail
                        )
                    }

                    Text(HubUIStrings.Settings.RuntimeMonitor.metricsExplainer)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        HubNeutralActionChipButton(
                            title: HubUIStrings.Settings.RuntimeMonitor.copySummary,
                            systemName: "doc.on.doc",
                            width: nil,
                            help: nil
                        ) {
                            copyRuntimeMonitorSummaryToClipboard(status: status)
                        }
                        if !monitor.activeTasks.isEmpty {
                            HubNeutralActionChipButton(
                                title: HubUIStrings.Settings.RuntimeMonitor.copyActiveTasks,
                                systemName: "list.bullet.rectangle",
                                width: nil,
                                help: nil
                            ) {
                                copyRuntimeMonitorActiveTasksToClipboard(monitor: monitor)
                            }
                        }
                        if !monitor.loadedInstances.isEmpty {
                            HubNeutralActionChipButton(
                                title: HubUIStrings.Settings.RuntimeMonitor.copyLoadedInstances,
                                systemName: "shippingbox",
                                width: nil,
                                help: nil
                            ) {
                                copyRuntimeMonitorLoadedInstancesToClipboard(summary: runtimeOpsSummary)
                            }
                        }
                        if !currentTargets.isEmpty {
                            HubNeutralActionChipButton(
                                title: HubUIStrings.Settings.RuntimeMonitor.copyCurrentTargets,
                                systemName: "scope",
                                width: nil,
                                help: nil
                            ) {
                                copyRuntimeMonitorCurrentTargetsToClipboard(currentTargets)
                            }
                        }
                        if !monitor.lastErrors.isEmpty {
                            HubNeutralActionChipButton(
                                title: HubUIStrings.Settings.RuntimeMonitor.copyLastErrors,
                                systemName: "exclamationmark.bubble",
                                width: nil,
                                help: nil
                            ) {
                                copyRuntimeMonitorErrorsToClipboard(monitor: monitor)
                            }
                        }
                        HubNeutralActionChipButton(
                            title: HubUIStrings.Settings.RuntimeMonitor.openLog,
                            systemName: "doc.text.magnifyingglass",
                            width: nil,
                            help: nil
                        ) {
                            store.openAIRuntimeLog()
                        }
                        Spacer()
                    }

                    if monitor.providers.isEmpty {
                        Text(HubUIStrings.Settings.RuntimeMonitor.noProviderRecords)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(monitor.providers, id: \.provider) { provider in
                            runtimeMonitorProviderCard(provider)
                        }
                    }

                    DisclosureGroup(HubUIStrings.Settings.RuntimeMonitor.currentTargetsDisclosure(currentTargets.count)) {
                        if currentTargets.isEmpty {
                            Text(HubUIStrings.Settings.RuntimeMonitor.currentTargetsEmpty)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(currentTargets.enumerated()), id: \.offset) { entry in
                                    let model = entry.element.0
                                    let requestContext = entry.element.1
                                    Text(runtimeMonitorCurrentTargetLine(model: model, requestContext: requestContext))
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }

                    DisclosureGroup(HubUIStrings.Settings.RuntimeMonitor.activeTasksDisclosure(monitor.activeTasks.count)) {
                        if monitor.activeTasks.isEmpty {
                            Text(HubUIStrings.Settings.RuntimeMonitor.activeTasksEmpty)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            let activeTasks = Array(monitor.activeTasks.enumerated())
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(activeTasks, id: \.offset) { entry in
                                    let task = entry.element
                                    Text(runtimeMonitorActiveTaskLine(task))
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }

                    DisclosureGroup(
                        HubUIStrings.Settings.RuntimeMonitor.loadedInstancesDisclosure(runtimeOpsSummary.instanceRows.count)
                    ) {
                        if runtimeOpsSummary.instanceRows.isEmpty {
                            Text(HubUIStrings.Settings.RuntimeMonitor.loadedInstancesEmpty)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(runtimeOpsSummary.instanceRows) { row in
                                    Text(runtimeMonitorLoadedInstanceLine(row))
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }

                    DisclosureGroup(HubUIStrings.Settings.RuntimeMonitor.lastErrorsDisclosure(monitor.lastErrors.count)) {
                        if monitor.lastErrors.isEmpty {
                            Text(HubUIStrings.Settings.RuntimeMonitor.lastErrorsEmpty)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            let lastErrors = Array(monitor.lastErrors.enumerated())
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(lastErrors, id: \.offset) { entry in
                                    let error = entry.element
                                    Text(runtimeMonitorErrorLine(error))
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
            } else {
                Text(HubUIStrings.Settings.RuntimeMonitor.waitingForHeartbeat)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    HubNeutralActionChipButton(
                        title: HubUIStrings.Settings.RuntimeMonitor.copyProviderSummary,
                        systemName: "doc.on.doc",
                        width: nil,
                        help: nil
                    ) {
                        copyLocalProviderSummaryToClipboard(snapshot: hubLaunchStatus)
                    }
                    HubNeutralActionChipButton(
                        title: HubUIStrings.Settings.RuntimeMonitor.openLog,
                        systemName: "doc.text.magnifyingglass",
                        width: nil,
                        help: nil
                    ) {
                        store.openAIRuntimeLog()
                    }
                    Spacer()
                }
            }
        }
    }

    private var networkingSection: some View {
        Section(HubUIStrings.Settings.Networking.sectionTitle) {
            HStack {
                Text(HubUIStrings.Settings.Networking.bridgeStatus)
                Spacer()
                Text(store.bridge.bridgeStatusText)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button(HubUIStrings.Settings.Networking.restoreNetwork) {
                    store.bridge.restore(seconds: 30 * 60)
                }
                Button(HubUIStrings.Settings.Networking.refreshStatus) { store.bridge.refresh() }
                Spacer()
            }

            Text(HubUIStrings.Settings.Networking.defaultHint)
                .font(.caption2)
                .foregroundStyle(.secondary)

            DisclosureGroup(HubUIStrings.Settings.Networking.emergencyDisclosure) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(HubUIStrings.Settings.Networking.emergencyHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button(HubUIStrings.Settings.Networking.cutOffGlobal) {
                            store.bridge.disable()
                        }
                        .tint(.red)
                        Button(HubUIStrings.Settings.Networking.restoreGlobal) {
                            store.bridge.restore(seconds: 30 * 60)
                        }
                        Spacer()
                    }
                }
                .padding(.top, 4)
            }

            if store.pendingNetworkRequests.isEmpty {
                Text(HubUIStrings.Settings.Networking.noPendingRequests)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.pendingNetworkRequests) { req in
                    networkRequestCard(req)
                }
            }
        }
    }

    private func formatEpochMs(_ ms: Int64) -> String {
        let d = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        let f = DateFormatter()
        f.dateFormat = HubUIStrings.Formatting.dateTimeWithSeconds
        return f.string(from: d)
    }

    private func formatEpochSeconds(_ seconds: Double) -> String {
        guard seconds > 0 else { return HubUIStrings.Settings.RuntimeMonitor.unknown }
        return formatEpochMs(Int64(seconds * 1000.0))
    }

    private func formatRuntimeMemoryBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .memory)
    }

    private func runtimeMonitorTaskKindsText(_ values: [String]) -> String {
        HubUIStrings.Settings.RuntimeMonitor.taskKinds(values)
    }

    private func runtimeMonitorMemoryText(_ provider: AIRuntimeMonitorProvider) -> String {
        return HubUIStrings.Settings.RuntimeMonitor.memorySummary(
            memoryState: provider.memoryState,
            current: formatRuntimeMemoryBytes(provider.activeMemoryBytes),
            peak: formatRuntimeMemoryBytes(provider.peakMemoryBytes)
        )
    }

    @ViewBuilder
    private func runtimeMonitorMetricCard(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func runtimeMonitorProviderCard(_ provider: AIRuntimeMonitorProvider) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(provider.provider.uppercased())
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(HubUIStrings.Settings.RuntimeMonitor.providerStatus(ok: provider.ok))
                    .font(.caption.monospaced())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((provider.ok ? Color.green : Color.red).opacity(0.14))
                    .clipShape(Capsule())
                if provider.queuedTaskCount > 0 {
                    Text(HubUIStrings.Settings.RuntimeMonitor.queuedCount(provider.queuedTaskCount))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Text(
                HubUIStrings.Settings.RuntimeMonitor.reasonBackend(
                    reason: provider.reasonCode.isEmpty ? HubUIStrings.Settings.RuntimeMonitor.none : provider.reasonCode,
                    backend: provider.deviceBackend.isEmpty ? HubUIStrings.Settings.RuntimeMonitor.unknown : provider.deviceBackend
                )
            )
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text(
                HubUIStrings.Settings.RuntimeMonitor.taskKindsSummary(
                    real: runtimeMonitorTaskKindsText(provider.realTaskKinds),
                    fallback: runtimeMonitorTaskKindsText(provider.fallbackTaskKinds),
                    unavailable: runtimeMonitorTaskKindsText(provider.unavailableTaskKinds)
                )
            )
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text(
                HubUIStrings.Settings.RuntimeMonitor.providerLoadSummary(
                    activeTaskCount: provider.activeTaskCount,
                    concurrencyLimit: provider.concurrencyLimit,
                    queuedTaskCount: provider.queuedTaskCount,
                    loadedInstanceCount: provider.loadedInstanceCount,
                    loadedModelCount: provider.loadedModelCount
                )
            )
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text(
                HubUIStrings.Settings.RuntimeMonitor.queueSummary(
                    mode: provider.queueMode.isEmpty ? HubUIStrings.Settings.RuntimeMonitor.unknown : provider.queueMode,
                    oldestWaiterAgeMs: provider.oldestWaiterAgeMs,
                    contentionCount: provider.contentionCount,
                    memory: runtimeMonitorMemoryText(provider)
                )
            )
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if !provider.lastIdleEvictionReason.isEmpty || !provider.importError.isEmpty {
                Text(
                    HubUIStrings.Settings.RuntimeMonitor.idleEvictionSummary(
                        policy: provider.idleEvictionPolicy.isEmpty ? HubUIStrings.Settings.RuntimeMonitor.unknown : provider.idleEvictionPolicy,
                        lastEviction: provider.lastIdleEvictionReason.isEmpty ? HubUIStrings.Settings.RuntimeMonitor.none : provider.lastIdleEvictionReason,
                        importError: provider.importError.isEmpty ? HubUIStrings.Settings.RuntimeMonitor.none : provider.importError
                    )
                )
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            let providerHint = (store.aiRuntimeProviderHelpTextByProvider[provider.provider] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !providerHint.isEmpty {
                Text(providerHint)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func runtimeMonitorActiveTaskLine(_ task: AIRuntimeMonitorActiveTask) -> String {
        HubUIStrings.Settings.RuntimeMonitor.activeTaskLine(
            provider: task.provider,
            taskKind: task.taskKind,
            modelID: task.modelId,
            requestID: task.requestId,
            deviceID: task.deviceId,
            instanceKey: task.instanceKey,
            loadConfigHash: task.loadConfigHash,
            currentContextLength: task.currentContextLength,
            maxContextLength: task.maxContextLength > task.currentContextLength ? task.maxContextLength : nil,
            leaseTtlSec: task.leaseTtlSec
        )
    }

    private func runtimeMonitorLoadedInstanceLine(_ instance: AIRuntimeLoadedInstance) -> String {
        HubUIStrings.Settings.RuntimeMonitor.loadedInstanceLine(
            modelID: instance.modelId,
            taskKinds: runtimeMonitorTaskKindsText(instance.taskKinds),
            instanceKey: instance.instanceKey,
            loadConfigHash: instance.loadConfigHash,
            currentContextLength: instance.currentContextLength,
            maxContextLength: instance.maxContextLength,
            ttl: instance.ttl ?? instance.loadConfig?.ttl,
            residency: instance.residency,
            backend: instance.deviceBackend,
            lastUsedAt: formatEpochSeconds(instance.lastUsedAt)
        )
    }

    private func runtimeMonitorLoadedInstanceLine(_ row: LocalRuntimeOperationsSummary.InstanceRow) -> String {
        HubUIStrings.Settings.RuntimeMonitor.loadedInstanceRowLine(
            modelID: row.modelID,
            modelName: row.modelName,
            providerID: row.providerID,
            instanceKey: row.shortInstanceKey.isEmpty ? row.instanceKey : row.shortInstanceKey,
            taskSummary: row.taskSummary,
            loadSummary: row.loadSummary,
            detailSummary: row.detailSummary,
            currentTargetSummary: row.isCurrentTarget ? row.currentTargetSummary : nil
        )
    }

    private func runtimeMonitorCurrentTargetLine(
        model: HubModel,
        requestContext: LocalModelRuntimeRequestContext
    ) -> String {
        let modelName = model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? model.id : model.name
        return HubUIStrings.Settings.RuntimeMonitor.currentTargetLine(
            modelID: model.id,
            modelName: modelName,
            providerID: requestContext.providerID,
            target: requestContext.uiSummary,
            detail: requestContext.technicalSummary
        )
    }

    private func runtimeMonitorErrorLine(_ error: AIRuntimeMonitorLastError) -> String {
        HubUIStrings.Settings.RuntimeMonitor.errorLine(
            provider: error.provider,
            severity: error.severity,
            code: error.code,
            message: error.message
        )
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

    private func reloadSkillsSnapshots() {
        skillsIndex = HubSkillsStoreStorage.loadSkillsIndex()
        skillsPins = HubSkillsStoreStorage.loadSkillPins()
        skillsSources = HubSkillsStoreStorage.loadSkillSources()
    }

    private func shortSha(_ sha: String) -> String {
        let s = sha.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count <= 12 { return s }
        return "\(s.prefix(8))…\(s.suffix(4))"
    }

    private func renderResolvedSkills(_ resolved: [HubSkillsStoreStorage.ResolvedSkill]) -> String {
        let uid = skillsResolveUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = skillsResolveProjectId.trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = []
        lines.append(HubUIStrings.Settings.Skills.resolvedUserID(uid.isEmpty ? HubUIStrings.Settings.Skills.resolvedEmptyValue : uid))
        lines.append(HubUIStrings.Settings.Skills.resolvedProjectID(pid.isEmpty ? HubUIStrings.Settings.Skills.resolvedEmptyValue : pid))
        lines.append(HubUIStrings.Settings.Skills.resolvedPrecedence)
        lines.append("")

        for r in resolved {
            let sid = r.pin.skillId.trimmingCharacters(in: .whitespacesAndNewlines)
            let sha = r.pin.packageSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let ver = r.meta?.version.trimmingCharacters(in: .whitespacesAndNewlines) ?? HubUIStrings.Settings.Diagnostics.missingField
            let src = r.meta?.sourceId.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            lines.append(
                HubUIStrings.Settings.Skills.resolvedSkillLine(
                    scopeLabel: r.scope.shortLabel,
                    skillID: sid,
                    version: ver,
                    packageSHA256: sha,
                    sourceID: src
                )
            )
        }

        return HubDiagnosticsBundleExporter.redactTextForSharing(lines.joined(separator: "\n"))
    }

    private func openSkillManifest(packageSha256: String) {
        let sha = packageSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !sha.isEmpty else { return }
        let url = HubSkillsStoreStorage.skillManifestURL(packageSha256: sha)
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    private func revealSkillPackage(packageSha256: String) {
        let sha = packageSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !sha.isEmpty else { return }
        let url = HubSkillsStoreStorage.skillPackageURL(packageSha256: sha)
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
        }
    }

    private func updateSkillPin(
        scope: HubSkillsStoreStorage.PinScope,
        skillId: String,
        packageSha256: String,
        userIdOverride: String? = nil,
        projectIdOverride: String? = nil
    ) {
        skillsLastActionText = ""
        skillsLastErrorText = ""

        let uid = (userIdOverride ?? skillsResolveUserId).trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = (projectIdOverride ?? skillsResolveProjectId).trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let userForScope: String? = {
                if scope == .memoryCore { return nil }
                return uid.isEmpty ? nil : uid
            }()
            let projectForScope: String? = {
                if scope != .project { return nil }
                return pid.isEmpty ? nil : pid
            }()

            let res = try HubSkillsStoreStorage.setPin(
                scope: scope,
                userId: userForScope,
                projectId: projectForScope,
                skillId: skillId,
                packageSha256: packageSha256,
                note: nil
            )
            skillsPins = HubSkillsStoreStorage.loadSkillPins()

            let newSha = packageSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if newSha.isEmpty {
                skillsLastActionText = HubUIStrings.Settings.Skills.pinActionUnpinned(
                    skillID: skillId,
                    scopeLabel: scope.displayLabel
                )
            } else {
                let prev = res.previousSha.trimmingCharacters(in: .whitespacesAndNewlines)
                skillsLastActionText = HubUIStrings.Settings.Skills.pinActionPinned(
                    skillID: skillId,
                    scopeLabel: scope.displayLabel,
                    shortSHA: shortSha(newSha),
                    previousShortSHA: prev.isEmpty ? nil : shortSha(prev)
                )
            }
        } catch {
            skillsLastErrorText = error.localizedDescription
        }
    }

    private func sortedPins(_ pins: [HubSkillsStoreStorage.SkillPin]) -> [HubSkillsStoreStorage.SkillPin] {
        pins.sorted { a, b in
            let am = a.updatedAtMs ?? 0
            let bm = b.updatedAtMs ?? 0
            if am != bm { return am > bm }
            return a.skillId.localizedCaseInsensitiveCompare(b.skillId) == .orderedAscending
        }
    }

    @ViewBuilder
    private func skillResolvedRow(_ r: HubSkillsStoreStorage.ResolvedSkill) -> some View {
        let sid = r.pin.skillId.trimmingCharacters(in: .whitespacesAndNewlines)
        let sha = r.pin.packageSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ver = (r.meta?.version ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (r.meta?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = HubUIStrings.Settings.Skills.skillTitle(skillID: sid, version: ver)

        VStack(alignment: .leading, spacing: 2) {
            Text(HubUIStrings.Settings.Skills.scopeAndTitle(scopeLabel: r.scope.displayLabel, title: title))
                .font(.callout.weight(.semibold))
            if !name.isEmpty, name != sid {
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if r.meta == nil {
                Text(HubUIStrings.Settings.Skills.packageMissing(shortSha(sha)))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else {
                Text(HubUIStrings.Settings.Skills.packageSHA(shortSha(sha)))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 10) {
                if !sha.isEmpty {
                    Button(HubUIStrings.Settings.Skills.openManifest) { openSkillManifest(packageSha256: sha) }
                    Button(HubUIStrings.Settings.Skills.showPackageDirectory) { revealSkillPackage(packageSha256: sha) }
                }
                Spacer()
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func skillPinRow(_ p: HubSkillsStoreStorage.SkillPin, scope: HubSkillsStoreStorage.PinScope) -> some View {
        let sid = p.skillId.trimmingCharacters(in: .whitespacesAndNewlines)
        let sha = p.packageSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let uid = (p.userId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = (p.projectId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let scopeDetail = [
            uid.isEmpty ? nil : HubUIStrings.Settings.Skills.scopeUserID(uid),
            pid.isEmpty ? nil : HubUIStrings.Settings.Skills.scopeProjectID(pid),
        ]
            .compactMap { $0 }
        let scopeDetailText = HubUIStrings.Formatting.middleDotSeparated(scopeDetail)

        let meta = skillsIndex.skills.first(where: { $0.packageSha256.lowercased() == sha })?.toMeta()
        let ver = (meta?.version ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = HubUIStrings.Settings.Skills.skillTitle(skillID: sid, version: ver)

        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.callout.weight(.semibold))
            if !scopeDetailText.isEmpty {
                Text(scopeDetailText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            Text(HubUIStrings.Settings.Skills.packageSHA(shortSha(sha)))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: 10) {
                if !sha.isEmpty {
                    Button(HubUIStrings.Settings.Skills.openManifest) { openSkillManifest(packageSha256: sha) }
                    Button(HubUIStrings.Settings.Skills.showPackageDirectory) { revealSkillPackage(packageSha256: sha) }
                }
                Button(HubUIStrings.Settings.Skills.unpin) {
                    updateSkillPin(scope: scope, skillId: sid, packageSha256: "", userIdOverride: uid, projectIdOverride: pid)
                }
                Spacer()
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func skillMetaRow(_ meta: HubSkillsStoreStorage.SkillMeta) -> some View {
        let sid = meta.skillId.trimmingCharacters(in: .whitespacesAndNewlines)
        let ver = meta.version.trimmingCharacters(in: .whitespacesAndNewlines)
        let sha = meta.packageSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let desc = meta.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let caps = meta.capabilitiesRequired
        let capsText = caps.isEmpty ? HubUIStrings.Settings.Skills.empty : caps.joined(separator: ", ")
        let hint = meta.installHint.trimmingCharacters(in: .whitespacesAndNewlines)

        let canPin = !sha.isEmpty
        let uid = skillsResolveUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = skillsResolveProjectId.trimmingCharacters(in: .whitespacesAndNewlines)

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(HubUIStrings.Settings.Skills.skillTitle(skillID: sid, version: ver))
                    .font(.callout.weight(.semibold))
                Spacer()
                if sha.isEmpty {
                    Text(HubUIStrings.Settings.Skills.notInstalled)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(shortSha(sha))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            if !desc.isEmpty {
                Text(desc)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text(HubUIStrings.Settings.Skills.publisherSourceCapabilities(
                publisherID: meta.publisherId,
                sourceID: meta.sourceId,
                capabilities: capsText
            ))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !hint.isEmpty {
                Text(HubUIStrings.Settings.Skills.installHint(hint))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            HStack(spacing: 10) {
                Menu(HubUIStrings.Settings.Skills.pinTo) {
                    Button(HubUIStrings.Settings.Skills.pinMemoryCore) { updateSkillPin(scope: .memoryCore, skillId: sid, packageSha256: sha) }
                        .disabled(!canPin)
                    Button(HubUIStrings.Settings.Skills.pinGlobal) { updateSkillPin(scope: .global, skillId: sid, packageSha256: sha, userIdOverride: uid) }
                        .disabled(!canPin || uid.isEmpty)
                    Button(HubUIStrings.Settings.Skills.pinProject) {
                        updateSkillPin(scope: .project, skillId: sid, packageSha256: sha, userIdOverride: uid, projectIdOverride: pid)
                    }
                    .disabled(!canPin || uid.isEmpty || pid.isEmpty)

                    Divider()

                    Button(HubUIStrings.Settings.Skills.unpinMemoryCore()) { updateSkillPin(scope: .memoryCore, skillId: sid, packageSha256: "") }
                    Button(HubUIStrings.Settings.Skills.unpinGlobal()) { updateSkillPin(scope: .global, skillId: sid, packageSha256: "", userIdOverride: uid) }
                        .disabled(uid.isEmpty)
                    Button(HubUIStrings.Settings.Skills.unpinProject()) {
                        updateSkillPin(scope: .project, skillId: sid, packageSha256: "", userIdOverride: uid, projectIdOverride: pid)
                    }
                    .disabled(uid.isEmpty || pid.isEmpty)
                }

                if !sha.isEmpty {
                    Button(HubUIStrings.Settings.Skills.openManifest) { openSkillManifest(packageSha256: sha) }
                    Button(HubUIStrings.Settings.Skills.showPackageDirectory) { revealSkillPackage(packageSha256: sha) }
                }
                Spacer()
            }
            .font(.caption)
        }
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

    private func copyLocalProviderSummaryToClipboard(snapshot: HubLaunchStatusSnapshot?) {
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

    private func copyRuntimeMonitorSummaryToClipboard(status: AIRuntimeStatus) {
        let text = status.runtimeMonitorOperatorSummary(ttl: AIRuntimeStatus.recommendedHeartbeatTTL)
        let out = HubDiagnosticsBundleExporter.redactTextForSharing(text)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    private func copyRuntimeMonitorActiveTasksToClipboard(monitor: AIRuntimeMonitorSnapshot) {
        let body = monitor.activeTasks.isEmpty
            ? HubUIStrings.Settings.RuntimeMonitor.noneField
            : monitor.activeTasks.map(runtimeMonitorActiveTaskLine).joined(separator: "\n")
        let out = HubDiagnosticsBundleExporter.redactTextForSharing(
            HubUIStrings.Settings.Diagnostics.Export.activeTasksBlock(body)
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    private func copyRuntimeMonitorLoadedInstancesToClipboard(summary: LocalRuntimeOperationsSummary) {
        let body = summary.instanceRows.isEmpty
            ? HubUIStrings.Settings.RuntimeMonitor.noneField
            : summary.instanceRows.map(runtimeMonitorLoadedInstanceLine).joined(separator: "\n")
        let out = HubDiagnosticsBundleExporter.redactTextForSharing(
            HubUIStrings.Settings.Diagnostics.Export.loadedInstancesBlock(body)
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    private func copyRuntimeMonitorCurrentTargetsToClipboard(
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

    private func copyRuntimeMonitorErrorsToClipboard(monitor: AIRuntimeMonitorSnapshot) {
        let body = monitor.lastErrors.isEmpty
            ? HubUIStrings.Settings.RuntimeMonitor.noneField
            : monitor.lastErrors.map(runtimeMonitorErrorLine).joined(separator: "\n")
        let out = HubDiagnosticsBundleExporter.redactTextForSharing(
            HubUIStrings.Settings.Diagnostics.Export.lastErrorsBlock(body)
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    private func copyRuntimePythonCandidatesToClipboard() {
        let body = store.aiRuntimePythonCandidatesText.trimmingCharacters(in: .whitespacesAndNewlines)
        let out = HubDiagnosticsBundleExporter.redactTextForSharing(
            HubUIStrings.Settings.Diagnostics.Export.pythonCandidatesBlock(
                body.isEmpty ? HubUIStrings.Settings.Diagnostics.noneField : body
            )
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    private func copyXHubLocalServiceRecoveryToClipboard(_ guidance: XHubLocalServiceRecoveryGuidance) {
        let out = HubDiagnosticsBundleExporter.redactTextForSharing(guidance.clipboardText)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
    }

    private func copyLocalRuntimeRepairSummary(_ summary: LocalRuntimeRepairSurfaceSummary) {
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

    private func localServiceRecoverySeverityColor(_ severity: String) -> Color {
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

    private func reloadAXConstitutionStatus() {
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

    private func copyAXConstitutionSummaryToClipboard() {
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

    private var grpcServerSection: some View {
        Section(HubUIStrings.Settings.GRPC.sectionTitle) {
            grpcServerPrimaryBlock()
            grpcAdvancedSettingsBlock()
            grpcAllowedDevicesBlock()
            grpcRemoteAccessBlock()
        }
    }

    @ViewBuilder
    private func grpcServerPrimaryBlock() -> some View {
        Toggle(HubUIStrings.Settings.GRPC.enableLAN, isOn: $grpc.autoStart)

        HStack {
            Text(HubUIStrings.Settings.GRPC.status)
            Spacer()
            Text(grpc.statusText)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }

        if !grpc.lastError.isEmpty {
            Text(grpc.lastError)
                .font(.caption2)
                .foregroundStyle(.red)
        }

        if !grpc.autoPortSwitchMessage.isEmpty {
            Text(grpc.autoPortSwitchMessage)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 6) {
            Text(HubUIStrings.Settings.GRPC.pairingInfoTitle)
                .font(.caption.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text(HubUIStrings.Settings.GRPC.externalAddress)
                        .foregroundStyle(.secondary)
                    Text(grpc.xtTerminalInternetHost ?? HubUIStrings.Settings.GRPC.noReachableHost)
                        .font(.caption.monospaced())
                        .foregroundStyle(grpc.xtTerminalInternetHost == nil ? .secondary : .primary)
                        .textSelection(.enabled)
                }
                GridRow {
                    Text(HubUIStrings.Settings.GRPC.pairingPort)
                        .foregroundStyle(.secondary)
                    Text(HubUIStrings.Settings.numericValue(grpc.xtTerminalPairingPort))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                GridRow {
                    Text(HubUIStrings.Settings.GRPC.grpcPort)
                        .foregroundStyle(.secondary)
                    Text(HubUIStrings.Settings.numericValue(grpc.port))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
            .font(.caption)

            Text(HubUIStrings.Settings.GRPC.setupHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        if !grpc.lanAddresses.isEmpty {
            Text(grpc.lanAddresses.joined(separator: "\n"))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }

        HStack(spacing: 10) {
            Button(HubUIStrings.Settings.GRPC.copyConnectionVars) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(grpc.connectionGuide, forType: .string)
            }
            Button(HubUIStrings.Settings.FirstRun.copyBootstrap) { grpc.copyBootstrapCommandToClipboard() }
            Button(HubUIStrings.Settings.FirstRun.addDevice) { showAddGRPCClient = true }
            Button(HubUIStrings.Settings.FirstRun.refresh) { grpc.refresh() }
            Spacer()
        }
        .font(.caption)

        if !grpc.connectionGuide.isEmpty {
            Text(grpc.connectionGuide)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func grpcAdvancedSettingsBlock() -> some View {
        DisclosureGroup(HubUIStrings.Settings.GRPC.advancedSettings) {
            VStack(alignment: .leading, spacing: 6) {
                Text(HubUIStrings.Settings.GRPC.externalHostOverride)
                    .font(.caption.weight(.semibold))
                TextField(HubUIStrings.Settings.GRPC.externalHostPlaceholder, text: $grpc.internetHostOverride)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                Text(HubUIStrings.Settings.GRPC.externalHostHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(HubUIStrings.Settings.GRPC.externalInviteTitle)
                    .font(.caption.weight(.semibold))
                Text(HubUIStrings.Settings.GRPC.externalHubAlias)
                    .font(.caption.weight(.semibold))
                TextField(HubUIStrings.Settings.GRPC.externalHubAliasPlaceholder, text: $grpc.externalHubAlias)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                Text(HubUIStrings.Settings.GRPC.externalHubAliasHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text(HubUIStrings.Settings.GRPC.externalInviteToken)
                            .foregroundStyle(.secondary)
                        Text(grpc.externalInviteTokenPreview.isEmpty
                             ? HubUIStrings.Settings.GRPC.inviteTokenNotIssued
                             : grpc.externalInviteTokenPreview)
                            .font(.caption.monospaced())
                            .foregroundStyle(grpc.externalInviteTokenPreview.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                    }
                }
                .font(.caption)

                HStack(spacing: 10) {
                    Button(HubUIStrings.Settings.GRPC.copySecureRemoteSetupPack) {
                        _ = grpc.copySecureRemoteSetupPackToClipboard()
                    }
                    .disabled(!grpc.canProvisionSecureRemoteSetupPack)
                    Button(grpc.hasExternalInviteToken
                           ? HubUIStrings.Settings.GRPC.rotateInviteToken
                           : HubUIStrings.Settings.GRPC.issueInviteToken) {
                        grpc.rotateExternalInviteToken()
                    }
                    .disabled(!grpc.canProvisionExternalInvite)
                    Button(HubUIStrings.Settings.GRPC.copyInviteLink) {
                        _ = grpc.copyInviteLinkToClipboard()
                    }
                    .disabled(!grpc.canProvisionExternalInvite)
                    if grpc.hasExternalInviteToken {
                        Button(HubUIStrings.Settings.GRPC.clearInviteToken) {
                            grpc.clearExternalInviteToken()
                        }
                    }
                    Spacer()
                }
                .font(.caption)

                Text(HubUIStrings.Settings.GRPC.secureRemoteSetupPackHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if !grpc.externalInviteLinkText.isEmpty {
                    Text(grpc.externalInviteLinkText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if let qrImage = grpc.externalInviteQRCodeImage {
                        VStack(alignment: .leading, spacing: 6) {
                            Image(nsImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 156, height: 156)
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                                )
                            Text(HubUIStrings.Settings.GRPC.inviteQRCodeHint)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text(grpc.externalInviteUnavailableReason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(HubUIStrings.Settings.GRPC.externalInviteTokenHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(HubUIStrings.Settings.GRPC.transportSecurity)
                    .font(.caption.weight(.semibold))
                Picker(HubUIStrings.Settings.GRPC.transportMode, selection: $grpc.tlsMode) {
                    Text(HubUIStrings.Settings.GRPC.insecure).tag("insecure")
                    Text(HubUIStrings.Settings.GRPC.tls).tag("tls")
                    Text(HubUIStrings.Settings.GRPC.mtls).tag("mtls")
                }
                .pickerStyle(.segmented)
                .font(.caption)

                Text(HubUIStrings.Settings.GRPC.transportHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Text(HubUIStrings.Settings.GRPC.port)
                Spacer()
                TextField(
                    "50051",
                    value: $grpc.port,
                    formatter: {
                        let f = NumberFormatter()
                        f.allowsFloats = false
                        f.minimum = 1
                        f.maximum = 65535
                        return f
                    }()
                )
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .frame(width: 120)
            }

            HStack(spacing: 10) {
                Button(HubUIStrings.Settings.GRPC.openLog) { grpc.openLog() }
                Button(HubUIStrings.Settings.GRPC.rotateDeviceToken) { grpc.regenerateClientToken() }
                Spacer()
            }
            .font(.caption)

            HStack(spacing: 10) {
                Button(HubUIStrings.Settings.FirstRun.openQuotaSettings) { grpc.openQuotaConfig() }
                Spacer()
            }
            .font(.caption)

            Text(HubUIStrings.Settings.GRPC.quotaFile(grpc.quotaConfigURL().path))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Divider()
        }
    }

    @ViewBuilder
    private func grpcAllowedDevicesBlock() -> some View {
        Text(HubUIStrings.Settings.GRPC.allowedDevicesTitle)
            .font(.caption.weight(.semibold))

        HStack(spacing: 10) {
            Button(HubUIStrings.Settings.GRPC.add) { showAddGRPCClient = true }
            Button(HubUIStrings.Settings.GRPC.openDeviceList) { grpc.openClientsConfig() }
            Spacer()
        }
        .font(.caption)

        let ipDenied = grpcDeniedAttempts.attempts
            .filter { a in
                a.reason.trimmingCharacters(in: .whitespacesAndNewlines) == "source_ip_not_allowed"
                    && !a.peerIp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .prefix(6)
        if !ipDenied.isEmpty {
            Divider()
            Text(HubUIStrings.Settings.GRPC.DeviceList.deniedSourceIPTitle)
                .font(.caption.weight(.semibold))
            ForEach(ipDenied) { a in
                VStack(alignment: .leading, spacing: 4) {
                    let title = !a.clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? a.clientName
                        : (
                            a.deviceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? HubUIStrings.Settings.GRPC.DeviceList.unknownDevice
                                : a.deviceId
                        )
                    let lastText = a.lastSeenAtMs > 0 ? formatMs(a.lastSeenAtMs) : HubUIStrings.Settings.GRPC.DeviceList.unknownSeen

                    Text(title)
                        .font(.caption.weight(.semibold))

                    Text(HubUIStrings.Settings.GRPC.DeviceList.deniedLine(ip: a.peerIp, count: a.count, lastText: lastText))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    if !a.expectedAllowedCidrs.isEmpty {
                        Text(HubUIStrings.Settings.GRPC.DeviceList.allowedSources(a.expectedAllowedCidrs))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }

                    let did = a.deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !did.isEmpty, grpc.allowedClients.contains(where: { $0.deviceId == did }) {
                        HStack(spacing: 10) {
                            Button(HubUIStrings.Settings.GRPC.DeviceList.addIPToDevice) {
                                grpc.addAllowedCidr(deviceId: did, value: a.peerIp)
                            }
                            .font(.caption)
                            Button(HubUIStrings.Settings.GRPC.DeviceList.edit) {
                                if let c = grpc.allowedClients.first(where: { $0.deviceId == did }) {
                                    presentGRPCClientEditor(c)
                                }
                            }
                            .font(.caption)
                            Spacer()
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }

        if grpc.allowedClients.isEmpty {
            Text(HubUIStrings.Settings.GRPC.DeviceList.noPairedDevices)
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            let statusById: [String: GRPCDeviceStatusEntry] = Dictionary(
                uniqueKeysWithValues: grpcDevicesStatus.devices.map { ($0.deviceId, $0) }
            )
            let summary = grpcClientListSummary(grpc.allowedClients, statusById: statusById)
            let visibleClients = grpcVisibleClients(grpc.allowedClients, statusById: statusById)

            grpcAllowedClientsHeader(statusById: statusById, summary: summary, visibleClients: visibleClients)

            grpcAllowedClientsRows(visibleClients, statusById: statusById)
        }
    }

    @ViewBuilder
    private func grpcAllowedClientsHeader(
        statusById: [String: GRPCDeviceStatusEntry],
        summary: GRPCClientListSummary,
        visibleClients: [HubGRPCClientEntry]
    ) -> some View {
        grpcPairingRepairCard(statusById: statusById)

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                grpcClientNetworkPill(HubUIStrings.Settings.GRPC.DeviceList.totalDevices(summary.total), color: .secondary)
                grpcClientNetworkPill(HubUIStrings.Settings.GRPC.DeviceList.enabledDevices(summary.enabled), color: .green)
                grpcClientNetworkPill(HubUIStrings.Settings.GRPC.DeviceList.connectedDevices(summary.connected), color: .accentColor)
                grpcClientNetworkPill(HubUIStrings.Settings.GRPC.DeviceList.staleDevices(summary.stale), color: .orange)
                grpcClientNetworkPill(HubUIStrings.Settings.GRPC.DeviceList.networkEnabledDevices(summary.networkEnabled), color: .blue)
                grpcClientNetworkPill(HubUIStrings.Settings.GRPC.DeviceList.paidEnabledDevices(summary.paidEnabled), color: .purple)
                grpcClientNetworkPill(HubUIStrings.Settings.GRPC.DeviceList.webEnabledDevices(summary.webEnabled), color: .teal)
                grpcClientNetworkPill(HubUIStrings.Settings.GRPC.DeviceList.blockedDevices(summary.blocked), color: .red)
            }
            .padding(.vertical, 2)
        }

        HStack(spacing: 10) {
            Text(HubUIStrings.Settings.GRPC.DeviceList.filter)
                .font(.caption.weight(.semibold))

            Picker(HubUIStrings.Settings.GRPC.DeviceList.filter, selection: $grpcClientListFilter) {
                ForEach(GRPCClientListFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .font(.caption)

            Spacer()

            Text(HubUIStrings.Settings.GRPC.DeviceList.visibleDevices(visibleClients.count, summary.total))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        Text(HubUIStrings.Settings.GRPC.DeviceList.sortHint)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func grpcAllowedClientsRows(
        _ visibleClients: [HubGRPCClientEntry],
        statusById: [String: GRPCDeviceStatusEntry]
    ) -> some View {
        ForEach(visibleClients) { client in
            grpcAllowedClientRow(client, status: statusById[client.deviceId])
        }
    }

    @ViewBuilder
    private func grpcAllowedClientRow(_ client: HubGRPCClientEntry, status: GRPCDeviceStatusEntry?) -> some View {
        let network = grpcClientNetworkAccessSnapshot(client)

        VStack(alignment: .leading, spacing: 6) {
            grpcAllowedClientRowHeader(client)
            grpcAllowedClientRowPills(client, network: network, status: status)
            grpcAllowedClientRowActions(client, network: network)
            grpcAllowedClientRowMetadata(client)
            grpcAllowedClientRowStatus(status)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func grpcAllowedClientRowHeader(_ client: HubGRPCClientEntry) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(grpcClientDisplayName(client))
                    .font(.caption.weight(.semibold))
                Text(client.deviceId)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(HubUIStrings.Settings.GRPC.DeviceList.edit) {
                presentGRPCClientEditor(client)
            }
            .font(.caption)

            Button(HubUIStrings.Settings.GRPC.DeviceList.copyVars) {
                grpc.copyConnectVars(for: client)
            }
            .font(.caption)

            Button(client.enabled ? HubUIStrings.Settings.GRPC.DeviceList.disable : HubUIStrings.Settings.GRPC.DeviceList.enable) {
                grpc.setClientEnabled(deviceId: client.deviceId, enabled: !client.enabled)
            }
            .font(.caption)

            if client.deviceId != "terminal_device" {
                Button(HubUIStrings.Settings.GRPC.DeviceList.delete) {
                    deletingGRPCClient = client
                }
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func grpcAllowedClientRowPills(
        _ client: HubGRPCClientEntry,
        network: GRPCClientNetworkAccessSnapshot,
        status: GRPCDeviceStatusEntry?
    ) -> some View {
        HStack(spacing: 6) {
            grpcClientNetworkPill(
                HubUIStrings.Settings.GRPC.DeviceList.deviceEnabledPill(client.enabled),
                color: client.enabled ? .green : .secondary
            )
            grpcClientNetworkPill(
                HubUIStrings.Settings.GRPC.DeviceList.networkEnabledPill(network.canNetwork),
                color: network.canNetwork ? .green : .secondary
            )
            grpcClientNetworkPill(
                HubUIStrings.Settings.GRPC.DeviceList.paidEnabledPill(network.paidEnabled),
                color: network.paidEnabled ? .orange : .secondary
            )
            grpcClientNetworkPill(
                network.webEnabled ? HubUIStrings.Settings.GRPC.DeviceList.webOn : HubUIStrings.Settings.GRPC.DeviceList.webOff,
                color: network.webEnabled ? .blue : .secondary
            )
            grpcClientNetworkPill(
                network.usesPolicyProfile ? HubUIStrings.Settings.GRPC.DeviceList.policyNew : HubUIStrings.Settings.GRPC.DeviceList.policyLegacy,
                color: network.usesPolicyProfile ? .purple : .secondary
            )

            if let status {
                grpcClientNetworkPill(
                    grpcClientPresencePillTitle(status),
                    color: grpcClientPresencePillColor(status)
                )
                grpcClientNetworkPill(
                    grpcClientExecutionPillTitle(status),
                    color: grpcClientExecutionPillColor(status)
                )
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func grpcAllowedClientRowActions(
        _ client: HubGRPCClientEntry,
        network: GRPCClientNetworkAccessSnapshot
    ) -> some View {
        HStack(spacing: 10) {
            Button(HubUIStrings.Settings.GRPC.DeviceList.toggleWeb(network.webEnabled)) {
                grpcSetWebFetchEnabled(client, enabled: !network.webEnabled)
            }
            .font(.caption)

            Button(HubUIStrings.Settings.GRPC.DeviceList.adoptCurrentSuggestedRange) {
                grpc.adoptCurrentLANDefaults(deviceId: client.deviceId)
                if editingGRPCClient?.deviceId == client.deviceId,
                   let refreshed = grpc.allowedClients.first(where: { $0.deviceId == client.deviceId }) {
                    presentGRPCClientEditor(
                        refreshed,
                        capabilityFocusKey: editingGRPCClientFocusCapabilityKey
                    )
                }
            }
            .font(.caption)

            if network.policyGrantsNetwork {
                Button(HubUIStrings.Settings.GRPC.DeviceList.cutOffNetwork) {
                    grpcCutOffNetworkAccess(client)
                }
                .font(.caption)
            }

            Text(grpcClientQuickActionHint(network))
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    @ViewBuilder
    private func grpcAllowedClientRowMetadata(_ client: HubGRPCClientEntry) -> some View {
        Text(grpcClientSecuritySummary(client))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .textSelection(.enabled)

        Text(grpcClientPaidPolicySummary(client))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .textSelection(.enabled)
    }

    @ViewBuilder
    private func grpcAllowedClientRowStatus(_ status: GRPCDeviceStatusEntry?) -> some View {
        if let status {
            Text(grpcClientStatusSummary(status))
                .font(.caption2)
                .foregroundStyle(grpcClientPresencePillColor(status))
                .lineLimit(2)
                .textSelection(.enabled)

            Text(grpcClientPolicyUsageSummary(status))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)

            Text(grpcClientActualExecutionSummary(status))
                .font(.caption2)
                .foregroundStyle(grpcClientExecutionPillColor(status))
                .lineLimit(3)
                .textSelection(.enabled)

            if let activity = status.lastActivity {
                Text(grpcClientLastActivitySummary(activity))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            if grpcClientPresenceCountsAsStale(status) {
                Text(HubUIStrings.Settings.GRPC.DeviceList.staleRepairHint)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !status.lastBlockedReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !status.lastDenyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(grpcClientLastBlockedSummary(status))
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            if let series = status.tokenSeries5m1h, !series.points.isEmpty {
                TokenSparkline(
                    points: series.points,
                    strokeColor: grpcClientPresenceState(status) == .connected ? .accentColor : Color.gray.opacity(0.7),
                    lineWidth: 1.5
                )
                .frame(height: 18)
            }

            if status.dailyTokenCap > 0 {
                ProgressView(value: Double(status.dailyTokenUsed), total: Double(status.dailyTokenCap))
                    .progressViewStyle(.linear)
                Text(
                    HubUIStrings.Settings.GRPC.DeviceList.dailyTokenUsage(
                        day: status.quotaDay,
                        used: Int(status.dailyTokenUsed),
                        cap: Int(status.dailyTokenCap),
                        remaining: Int(max(0, status.remainingDailyTokenBudget))
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else if status.dailyTokenUsed > 0 {
                Text(HubUIStrings.Settings.GRPC.DeviceList.dailyTokenUsageUnlimited(day: status.quotaDay, used: Int(status.dailyTokenUsed)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !status.modelBreakdown.isEmpty {
                DisclosureGroup(HubUIStrings.Settings.GRPC.DeviceList.usageDetails) {
                    ForEach(Array(status.modelBreakdown.prefix(3))) { row in
                        Text(grpcClientModelBreakdownSummary(row))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .font(.caption2)
            }
        } else {
            Text(HubUIStrings.Settings.GRPC.DeviceList.statusUnknownNoEvents)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func grpcRemoteAccessBlock() -> some View {
        let remoteHealth = grpcRemoteAccessHealthSummary
        let routeSnapshot = remoteRouteProbe.snapshot

        Text(HubUIStrings.Settings.GRPC.deviceFile(grpc.clientsConfigURL().path))
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)

        Text(HubUIStrings.Settings.GRPC.enabledDeviceFileHint)
            .font(.caption2)
            .foregroundStyle(.secondary)

        Divider()

        VStack(alignment: .leading, spacing: 6) {
            Text(HubUIStrings.Settings.GRPC.RemoteHealth.title)
                .font(.caption.weight(.semibold))

            HStack(spacing: 6) {
                grpcClientNetworkPill(remoteHealth.badgeText, color: grpcRemoteHealthColor(remoteHealth.state))
                Spacer()
            }

            Text(remoteHealth.headline)
                .font(.caption.weight(.semibold))

            Text(remoteHealth.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(remoteHealth.accessScopeText)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(remoteHealth.operatorHintText)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let nextStep = remoteHealth.nextStep,
               !nextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(HubUIStrings.Settings.GRPC.RemoteHealth.nextStep(nextStep))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }

        Divider()

        VStack(alignment: .leading, spacing: 6) {
            Text(HubUIStrings.Settings.GRPC.RemoteRoute.title)
                .font(.caption.weight(.semibold))

            HStack(spacing: 6) {
                grpcClientNetworkPill(routeSnapshot.statusText, color: grpcRemoteRouteColor(routeSnapshot.state))
                Spacer()
            }

            Text(routeSnapshot.detailText)
                .font(.caption2)
                .foregroundStyle(routeSnapshot.state == .failed ? .red : .secondary)

            if !routeSnapshot.addresses.isEmpty {
                Text(routeSnapshot.addresses.joined(separator: "\n"))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }

        Divider()

        DisclosureGroup(HubUIStrings.Settings.GRPC.remoteAccessDisclosure) {
            Text(HubUIStrings.Settings.GRPC.remoteAccessHint)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(HubUIStrings.Settings.GRPC.remoteHardeningHint)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(HubUIStrings.Settings.GRPC.remoteAdminHint)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button(HubUIStrings.Settings.GRPC.copyRemoteAccessGuide) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Self.remoteModeGuideText, forType: .string)
            }
            .font(.caption)

            Text(Self.remoteModeGuideText)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }

        Divider()

        Toggle(HubUIStrings.Settings.GRPC.ServingPower.keepSystemAwake, isOn: $servingPower.keepSystemAwakeWhileServing)

        Text(HubUIStrings.Settings.GRPC.ServingPower.keepSystemAwakeHint)
            .font(.caption2)
            .foregroundStyle(.secondary)

        Toggle(HubUIStrings.Settings.GRPC.ServingPower.keepDisplayAwake, isOn: $servingPower.keepDisplayAwakeWhileServing)
            .disabled(!servingPower.keepSystemAwakeWhileServing)

        Text(HubUIStrings.Settings.GRPC.ServingPower.keepDisplayAwakeHint)
            .font(.caption2)
            .foregroundStyle(servingPower.keepSystemAwakeWhileServing ? .secondary : .tertiary)

        HStack {
            Text(HubUIStrings.Settings.GRPC.ServingPower.status)
            Spacer()
            Text(servingPower.statusText)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.caption)

        Text(servingPower.detailText)
            .font(.caption2)
            .foregroundStyle(.secondary)

        if !servingPower.lastError.isEmpty {
            Text(servingPower.lastError)
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }

    private func deleteClientConfirmationMessage(_ client: HubGRPCClientEntry) -> String {
        let displayName = client.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? client.deviceId
            : client.name
        return HubUIStrings.Settings.GRPC.deleteClientConfirmation(displayName: displayName, deviceID: client.deviceId)
    }

    private func grpcClientSecuritySummary(_ c: HubGRPCClientEntry) -> String {
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

    private func grpcClientPaidPolicySummary(_ client: HubGRPCClientEntry) -> String {
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

    private struct GRPCClientNetworkAccessSnapshot {
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

    private func grpcClientNetworkAccessSnapshot(_ client: HubGRPCClientEntry) -> GRPCClientNetworkAccessSnapshot {
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

    private enum GRPCClientListFilter: String, CaseIterable, Identifiable {
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

    private struct GRPCClientListSummary {
        var total: Int = 0
        var enabled: Int = 0
        var connected: Int = 0
        var stale: Int = 0
        var networkEnabled: Int = 0
        var paidEnabled: Int = 0
        var webEnabled: Int = 0
        var blocked: Int = 0
    }

    private func grpcClientListSummary(
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

    private func grpcVisibleClients(
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
    private func grpcPairingRepairCard(statusById: [String: GRPCDeviceStatusEntry]) -> some View {
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

    private func grpcClientDisplayName(_ client: HubGRPCClientEntry) -> String {
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

    private func grpcClientQuickActionHint(_ snapshot: GRPCClientNetworkAccessSnapshot) -> String {
        if !snapshot.clientEnabled {
            return HubUIStrings.Settings.GRPC.DeviceList.quickActionEnableFirst
        }
        if snapshot.policyGrantsNetwork {
            return HubUIStrings.Settings.GRPC.DeviceList.quickActionCutOffOnly
        }
        return HubUIStrings.Settings.GRPC.DeviceList.quickActionRestoreWebOnly
    }

    @ViewBuilder
    private func grpcClientNetworkPill(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.monospaced())
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func grpcRemoteHealthColor(_ state: HubRemoteAccessHealthSummary.State) -> Color {
        switch state {
        case .ready:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }

    private func grpcRemoteRouteColor(_ state: HubRemoteAccessRouteProbeSnapshot.State) -> Color {
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

    private func grpcCutOffNetworkAccess(_ client: HubGRPCClientEntry) {
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

    private func grpcSetWebFetchEnabled(_ client: HubGRPCClientEntry, enabled: Bool) {
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

    private func grpcClientStatusSummary(_ st: GRPCDeviceStatusEntry) -> String {
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

    private enum GRPCClientPresenceState {
        case connected
        case offlineRecent
        case stale
        case neverSeen
        case unknown
    }

    private func grpcClientPresenceState(_ status: GRPCDeviceStatusEntry?) -> GRPCClientPresenceState {
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

    private func grpcClientPresenceCountsAsStale(_ status: GRPCDeviceStatusEntry?) -> Bool {
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

    private func grpcClientPresencePillTitle(_ status: GRPCDeviceStatusEntry?) -> String {
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

    private func grpcClientPresencePillColor(_ status: GRPCDeviceStatusEntry?) -> Color {
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


    private func grpcClientPolicyUsageSummary(_ st: GRPCDeviceStatusEntry) -> String {
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

    private func grpcClientExecutionPillTitle(_ st: GRPCDeviceStatusEntry) -> String {
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

    private func grpcClientExecutionPillColor(_ st: GRPCDeviceStatusEntry) -> Color {
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

    private func grpcClientActualExecutionSummary(_ st: GRPCDeviceStatusEntry) -> String {
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

    private func grpcClientLastBlockedSummary(_ st: GRPCDeviceStatusEntry) -> String {
        let reason = st.lastBlockedReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = st.lastDenyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if reason.isEmpty && code.isEmpty { return HubUIStrings.Settings.GRPC.DeviceList.lastBlockedNone }
        if reason.isEmpty { return HubUIStrings.Settings.GRPC.DeviceList.lastBlocked(code) }
        if code.isEmpty { return HubUIStrings.Settings.GRPC.DeviceList.lastBlocked(reason) }
        return HubUIStrings.Settings.GRPC.DeviceList.lastBlocked(reason: reason, code: code)
    }

    private func grpcClientModelBreakdownSummary(_ row: GRPCDeviceModelBreakdownEntry) -> String {
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

    private func grpcClientLastActivitySummary(_ a: GRPCDeviceLastActivity) -> String {
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

    private func formatMs(_ ms: Int64) -> String {
        let secs = Double(ms) / 1000.0
        let d = Date(timeIntervalSince1970: secs)
        let f = DateFormatter()
        f.dateFormat = HubUIStrings.Formatting.dateTimeWithSeconds
        return f.string(from: d)
    }

    private static let remoteModeGuideText = HubUIStrings.Settings.GRPC.remoteAccessGuideChecklist

    private var networkPoliciesSection: some View {
        Section(HubUIStrings.Settings.NetworkPolicies.sectionTitle) {
            HStack {
                Text(HubUIStrings.Settings.NetworkPolicies.policy)
                Spacer()
                Button(HubUIStrings.Settings.NetworkPolicies.add) { showAddNetworkPolicy = true }
            }

            if networkPolicies.isEmpty {
                Text(HubUIStrings.Settings.NetworkPolicies.empty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(networkPolicies) { p in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(HubUIStrings.Settings.NetworkPolicies.policyTitle(appID: p.appId, projectID: p.projectId))
                            .font(.callout.weight(.semibold))
                        Text(HubUIStrings.Settings.NetworkPolicies.summary(mode: policyModeText(p.mode), limit: policyLimitText(p.maxSeconds)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Menu(HubUIStrings.Settings.NetworkPolicies.modeMenu) {
                                Button(HubUIStrings.Settings.NetworkPolicies.manual) { updatePolicy(p, mode: .manual, maxSeconds: nil) }
                                Button(HubUIStrings.Settings.NetworkPolicies.autoApprove) { updatePolicy(p, mode: .autoApprove, maxSeconds: p.maxSeconds) }
                                Button(HubUIStrings.Settings.NetworkPolicies.alwaysAllow) { updatePolicy(p, mode: .alwaysOn, maxSeconds: p.maxSeconds) }
                                Button(HubUIStrings.Settings.NetworkPolicies.alwaysDeny) { updatePolicy(p, mode: .deny, maxSeconds: nil) }
                            }
                            Menu(HubUIStrings.Settings.NetworkPolicies.durationMenu) {
                                Button(HubUIStrings.Settings.NetworkPolicies.noLimit) { updatePolicy(p, mode: nil, maxSeconds: nil) }
                                Button(HubUIStrings.Settings.NetworkPolicies.fifteenMinutes) { updatePolicy(p, mode: nil, maxSeconds: 15 * 60) }
                                Button(HubUIStrings.Settings.NetworkPolicies.thirtyMinutes) { updatePolicy(p, mode: nil, maxSeconds: 30 * 60) }
                                Button(HubUIStrings.Settings.NetworkPolicies.sixtyMinutes) { updatePolicy(p, mode: nil, maxSeconds: 60 * 60) }
                                Button(HubUIStrings.Settings.NetworkPolicies.oneHundredTwentyMinutes) { updatePolicy(p, mode: nil, maxSeconds: 120 * 60) }
                                Button(HubUIStrings.Settings.NetworkPolicies.eightHours) { updatePolicy(p, mode: nil, maxSeconds: 8 * 60 * 60) }
                            }
                            Button(HubUIStrings.Settings.NetworkPolicies.remove) { removePolicy(p) }
                            Spacer()
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var routingSection: some View {
        Section(HubUIStrings.Settings.Routing.sectionTitle) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.routingTaskTypes, id: \.self) { t in
                    HStack {
                        Text(t)
                            .font(.caption.monospaced())
                        Spacer()
                        TextField(HubUIStrings.Settings.Routing.modelIDPlaceholder, text: bindingRoutingModelId(t))
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .frame(width: 320)
                    }
                }
                Text(HubUIStrings.Settings.Routing.truthHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var remoteModelsSection: some View {
        Section(HubUIStrings.Settings.RemoteModels.sectionTitle) {
            HStack {
                Text(HubUIStrings.Settings.RemoteModels.title)
                Spacer()
                Button(
                    store.remoteKeyHealthScanInFlight
                        ? HubUIStrings.Settings.RemoteModels.healthCheckingBadge
                        : HubUIStrings.Settings.RemoteModels.scanAll
                ) {
                    store.scanAllRemoteKeyHealth()
                }
                .disabled(store.remoteKeyHealthScanInFlight || remoteModels.isEmpty)
                Button(HubUIStrings.Settings.RemoteModels.importCatalog) { showImportRemoteCatalog = true }
                Button(HubUIStrings.Settings.RemoteModels.add) { showAddRemoteModel = true }
            }
            if remoteModels.isEmpty {
                Text(HubUIStrings.Settings.RemoteModels.empty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(remoteModelGroups) { group in
                    remoteModelGroupCard(group)
                }
            }
            Text(HubUIStrings.Settings.RemoteModels.syncHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var modelHealthAutoScanSection: some View {
        Section(HubUIStrings.Settings.ModelHealthAutoScan.sectionTitle) {
            Text(HubUIStrings.Settings.ModelHealthAutoScan.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            modelHealthAutoScanCard(
                title: HubUIStrings.Settings.ModelHealthAutoScan.localTitle,
                schedule: store.localModelHealthAutoScanSchedule,
                hint: HubUIStrings.Settings.ModelHealthAutoScan.localHint,
                nextRunText: nextLocalModelHealthAutoScanText(),
                modeBinding: localModelHealthAutoScanModeBinding(),
                intervalBinding: localModelHealthAutoScanIntervalBinding(),
                dailyTimeBinding: localModelHealthAutoScanDailyTimeBinding()
            )

            modelHealthAutoScanCard(
                title: HubUIStrings.Settings.ModelHealthAutoScan.remoteTitle,
                schedule: store.remoteKeyHealthAutoScanSchedule,
                hint: HubUIStrings.Settings.ModelHealthAutoScan.remoteHint,
                nextRunText: nextRemoteKeyHealthAutoScanText(),
                modeBinding: remoteKeyHealthAutoScanModeBinding(),
                intervalBinding: remoteKeyHealthAutoScanIntervalBinding(),
                dailyTimeBinding: remoteKeyHealthAutoScanDailyTimeBinding()
            )
        }
    }

    @ViewBuilder
    private func modelHealthAutoScanCard(
        title: String,
        schedule: ModelHealthAutoScanSchedule,
        hint: String,
        nextRunText: String?,
        modeBinding: Binding<ModelHealthAutoScanMode>,
        intervalBinding: Binding<Int>,
        dailyTimeBinding: Binding<Date>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.callout.weight(.semibold))

            Picker(HubUIStrings.Settings.ModelHealthAutoScan.mode, selection: modeBinding) {
                Text(HubUIStrings.Settings.ModelHealthAutoScan.disabled).tag(ModelHealthAutoScanMode.disabled)
                Text(HubUIStrings.Settings.ModelHealthAutoScan.interval).tag(ModelHealthAutoScanMode.interval)
                Text(HubUIStrings.Settings.ModelHealthAutoScan.dailyTime).tag(ModelHealthAutoScanMode.dailyTime)
            }
            .pickerStyle(.segmented)

            switch schedule.mode {
            case .disabled:
                EmptyView()
            case .interval:
                Stepper(value: intervalBinding, in: 1...(24 * 14)) {
                    Text(HubUIStrings.Settings.ModelHealthAutoScan.everyHours(schedule.intervalHours))
                        .font(.caption)
                }
            case .dailyTime:
                HStack {
                    Text(HubUIStrings.Settings.ModelHealthAutoScan.dailyAt)
                        .font(.caption)
                    Spacer()
                    DatePicker(
                        "",
                        selection: dailyTimeBinding,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .datePickerStyle(.field)
                }

                Text(HubUIStrings.Settings.ModelHealthAutoScan.dailyTimeHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(hint)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let nextRunText {
                Text(HubUIStrings.Settings.ModelHealthAutoScan.nextRun(nextRunText))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func localModelHealthAutoScanModeBinding() -> Binding<ModelHealthAutoScanMode> {
        Binding(
            get: { store.localModelHealthAutoScanSchedule.mode },
            set: { newValue in
                store.updateLocalModelHealthAutoScanSchedule(
                    reconfiguredModelHealthAutoScanSchedule(from: store.localModelHealthAutoScanSchedule) {
                        $0.mode = newValue
                    }
                )
            }
        )
    }

    private func localModelHealthAutoScanIntervalBinding() -> Binding<Int> {
        Binding(
            get: { store.localModelHealthAutoScanSchedule.intervalHours },
            set: { newValue in
                store.updateLocalModelHealthAutoScanSchedule(
                    reconfiguredModelHealthAutoScanSchedule(from: store.localModelHealthAutoScanSchedule) {
                        $0.intervalHours = newValue
                    }
                )
            }
        )
    }

    private func localModelHealthAutoScanDailyTimeBinding() -> Binding<Date> {
        Binding(
            get: { clockDate(for: store.localModelHealthAutoScanSchedule.dailyMinuteOfDay) },
            set: { newValue in
                store.updateLocalModelHealthAutoScanSchedule(
                    reconfiguredModelHealthAutoScanSchedule(from: store.localModelHealthAutoScanSchedule) {
                        $0.dailyMinuteOfDay = minuteOfDay(from: newValue)
                    }
                )
            }
        )
    }

    private func remoteKeyHealthAutoScanModeBinding() -> Binding<ModelHealthAutoScanMode> {
        Binding(
            get: { store.remoteKeyHealthAutoScanSchedule.mode },
            set: { newValue in
                store.updateRemoteKeyHealthAutoScanSchedule(
                    reconfiguredModelHealthAutoScanSchedule(from: store.remoteKeyHealthAutoScanSchedule) {
                        $0.mode = newValue
                    }
                )
            }
        )
    }

    private func remoteKeyHealthAutoScanIntervalBinding() -> Binding<Int> {
        Binding(
            get: { store.remoteKeyHealthAutoScanSchedule.intervalHours },
            set: { newValue in
                store.updateRemoteKeyHealthAutoScanSchedule(
                    reconfiguredModelHealthAutoScanSchedule(from: store.remoteKeyHealthAutoScanSchedule) {
                        $0.intervalHours = newValue
                    }
                )
            }
        )
    }

    private func remoteKeyHealthAutoScanDailyTimeBinding() -> Binding<Date> {
        Binding(
            get: { clockDate(for: store.remoteKeyHealthAutoScanSchedule.dailyMinuteOfDay) },
            set: { newValue in
                store.updateRemoteKeyHealthAutoScanSchedule(
                    reconfiguredModelHealthAutoScanSchedule(from: store.remoteKeyHealthAutoScanSchedule) {
                        $0.dailyMinuteOfDay = minuteOfDay(from: newValue)
                    }
                )
            }
        )
    }

    private func nextLocalModelHealthAutoScanText() -> String? {
        guard store.localModelHealthAutoScanSchedule.isEnabled else { return nil }
        let localModels = modelStore.snapshot.models.filter { !LocalModelRuntimeActionPlanner.isRemoteModel($0) }
        guard !localModels.isEmpty else { return nil }

        let healthByModelID = Dictionary(
            uniqueKeysWithValues: store.localModelHealthSnapshot.records.map { ($0.modelId, $0) }
        )
        let dueAt = localModels.compactMap { model in
            store.localModelHealthAutoScanSchedule.nextDueAt(
                lastCheckedAt: healthByModelID[model.id]?.lastCheckedAt
            )
        }
        .min()

        return formattedAutoScanTime(dueAt)
    }

    private func nextRemoteKeyHealthAutoScanText() -> String? {
        guard store.remoteKeyHealthAutoScanSchedule.isEnabled else { return nil }
        let groups = RemoteKeyHealthScanner.groups(from: remoteModels)
        guard !groups.isEmpty else { return nil }

        let healthByKey = Dictionary(
            uniqueKeysWithValues: store.remoteKeyHealthSnapshot.records.map { ($0.keyReference, $0) }
        )
        let dueAt = groups.compactMap { group in
            store.remoteKeyHealthAutoScanSchedule.nextDueAt(
                lastCheckedAt: healthByKey[group.keyReference]?.lastCheckedAt
            )
        }
        .min()

        return formattedAutoScanTime(dueAt)
    }

    private func reconfiguredModelHealthAutoScanSchedule(
        from current: ModelHealthAutoScanSchedule,
        update: (inout ModelHealthAutoScanSchedule) -> Void
    ) -> ModelHealthAutoScanSchedule {
        var updated = current
        update(&updated)
        let now = Date().timeIntervalSince1970
        updated.configuredAt = now
        return updated.normalized(now: now)
    }

    private func clockDate(for minuteOfDay: Int) -> Date {
        let calendar = Calendar.autoupdatingCurrent
        let startOfDay = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .minute, value: minuteOfDay, to: startOfDay) ?? Date()
    }

    private func minuteOfDay(from date: Date) -> Int {
        let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func formattedAutoScanTime(_ raw: TimeInterval?) -> String? {
        guard let raw, raw > 0 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: raw))
    }

    @ViewBuilder
    private func remoteModelGroupCard(_ group: RemoteModelKeyGroup) -> some View {
        let usageLimitNotice = remoteKeyUsageLimitNotice(for: group)
        let healthPresentation = remoteKeyHealthPresentation(for: group, usageLimitNotice: usageLimitNotice)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(group.title)
                            .font(.callout.weight(.semibold))
                        if let healthPresentation {
                            remoteModelStatusBadge(healthPresentation.badgeText, tint: healthPresentation.tint)
                        }
                    }
                    Text(group.summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let detail = group.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let healthPresentation {
                        Text(healthPresentation.detailText)
                            .font(.caption2)
                            .foregroundStyle(healthPresentation.tint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    keychainStatusLine(model: group.primaryModel)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 8) {
                        Button(HubUIStrings.Settings.RemoteModels.loadAll) {
                            setRemoteModelsEnabled(group.loadableModelIDs, enabled: true)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(group.loadableModelIDs.isEmpty)

                        Button(HubUIStrings.Settings.RemoteModels.unloadAll) {
                            setRemoteModelsEnabled(group.enabledModelIDs, enabled: false)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(group.enabledModelIDs.isEmpty)
                    }

                    HStack(spacing: 8) {
                        Button(HubUIStrings.Settings.RemoteModels.rescan) {
                            store.scanRemoteKeyHealth(for: [group.keyReference])
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(store.remoteKeyHealthScanInFlight)

                        Button(group.renameActionTitle) {
                            editingRemoteModelGroup = group
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button(HubUIStrings.Settings.RemoteModels.removeKeyGroup) {
                            removeRemoteModelGroup(group)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .controlSize(.small)
                    }
                }
            }

            ForEach(group.models) { model in
                remoteModelRow(model)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func remoteModelRow(_ model: RemoteModelEntry) -> some View {
        let loadState = RemoteModelPresentationSupport.state(for: model)
        let statusText = remoteModelStatusText(loadState)
        let statusTint = remoteModelStatusTint(loadState)
        let title = model.nestedDisplayName
        let signals = remoteModelSignals(for: model)
        let metadataTags = remoteModelMetadataTags(for: model)
        let subtitle = remoteModelSubtitle(model)
        let detailLine = remoteModelDetailLine(model)
        let canLoad = loadState == .available
        let isEnabled = model.enabled

        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(remoteModelGlyphTint(for: model).opacity(0.16))
                Image(systemName: remoteModelGlyphName(for: model))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(remoteModelGlyphTint(for: model))
            }
            .frame(width: 30, height: 30)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)

                    remoteModelStatusBadge(statusText, tint: statusTint)
                }

                Text(model.id)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)

                if !signals.isEmpty || !metadataTags.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            ForEach(signals) { signal in
                                remoteModelSignalBadge(signal)
                            }
                            ForEach(metadataTags, id: \.self) { tag in
                                remoteModelChip(tag, tint: .secondary)
                            }
                        }

                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                if let detailLine {
                    Text(detailLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 8) {
                if isEnabled {
                    Button(HubUIStrings.Settings.RemoteModels.unload) {
                        setRemoteModelsEnabled([model.id], enabled: false)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button(HubUIStrings.Settings.RemoteModels.load) {
                        setRemoteModelsEnabled([model.id], enabled: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!canLoad)
                }

                Button(HubUIStrings.Settings.RemoteModels.remove) {
                    removeRemoteModel(id: model.id)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
            }
            .frame(width: 92, alignment: .trailing)
        }
        .padding(10)
        .background(isEnabled ? Color.white.opacity(0.04) : Color.white.opacity(0.025))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isEnabled ? Color.white.opacity(0.08) : Color.white.opacity(0.05), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func remoteModelStatusText(_ state: RemoteModelLoadState) -> String {
        switch state {
        case .loaded:
            return HubUIStrings.Settings.RemoteModels.loaded
        case .available:
            return HubUIStrings.Settings.RemoteModels.available
        case .needsSetup:
            return HubUIStrings.Settings.RemoteModels.needsSetup
        }
    }

    private func remoteModelStatusTint(_ state: RemoteModelLoadState) -> Color {
        switch state {
        case .loaded:
            return .green
        case .available:
            return .secondary
        case .needsSetup:
            return .orange
        }
    }

    @ViewBuilder
    private func remoteModelChip(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func remoteModelSignalBadge(_ signal: RemoteModelSignalVisual) -> some View {
        HStack(spacing: 5) {
            Image(systemName: signal.systemName)
                .imageScale(.small)
            Text(signal.title)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(signal.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(signal.tint.opacity(0.12))
        .overlay(
            Capsule()
                .stroke(signal.tint.opacity(0.24), lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func remoteModelStatusBadge(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    private var skillsSection: some View {
        Section(HubUIStrings.Settings.Skills.sectionTitle) {
            let storeDir = HubSkillsStoreStorage.skillsStoreDir()

            HStack {
                Text(HubUIStrings.Settings.Skills.store)
                Spacer()
                Button(HubUIStrings.Settings.Skills.showInFinder) {
                    try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([storeDir])
                }
                Button(HubUIStrings.Settings.Skills.reload) {
                    reloadSkillsSnapshots()
                }
            }

            Text(storeDir.path)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)

            HStack {
                Text(HubUIStrings.Settings.Skills.installedPackages)
                Spacer()
                Text(HubUIStrings.Settings.countBadge(skillsIndex.skills.count))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(HubUIStrings.Settings.Skills.pins)
                Spacer()
                Text(HubUIStrings.Settings.Skills.pinsSummary(
                    memoryCore: skillsPins.memoryCorePins.count,
                    global: skillsPins.globalPins.count,
                    project: skillsPins.projectPins.count
                ))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !skillsLastErrorText.isEmpty {
                Text(skillsLastErrorText)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if !skillsLastActionText.isEmpty {
                Text(skillsLastActionText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text(HubUIStrings.Settings.Skills.storageHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(HubUIStrings.Settings.Skills.userIDLabel)
                        .font(.caption.monospaced())
                    Spacer()
                    TextField(HubUIStrings.Settings.Skills.userIDPlaceholder, text: $skillsResolveUserId)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(width: 320)
                }

                HStack {
                    Text(HubUIStrings.Settings.Skills.projectIDLabel)
                        .font(.caption.monospaced())
                    Spacer()
                    TextField(HubUIStrings.Settings.Skills.projectIDPlaceholder, text: $skillsResolveProjectId)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(width: 320)
                }

                Text(HubUIStrings.Settings.Skills.priorityHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup(HubUIStrings.Settings.Skills.resolvedResults) {
                let resolved = HubSkillsStoreStorage.resolvedSkills(
                    index: skillsIndex,
                    pins: skillsPins,
                    userId: skillsResolveUserId,
                    projectId: skillsResolveProjectId
                )

                HStack(spacing: 10) {
                    Button(HubUIStrings.Settings.Skills.copyResolvedResults) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(renderResolvedSkills(resolved), forType: .string)
                    }
                    Button(HubUIStrings.Settings.Skills.openPinsFile) {
                        let url = HubSkillsStoreStorage.skillsPinsURL()
                        let fm = FileManager.default
                        if !fm.fileExists(atPath: url.path) {
                            // Create an empty pins file so users can inspect/edit it directly.
                            let empty = HubSkillsStoreStorage.SkillPinsSnapshot(
                                schemaVersion: "skills_pins.v1",
                                updatedAtMs: 0,
                                memoryCorePins: [],
                                globalPins: [],
                                projectPins: []
                            )
                            try? HubSkillsStoreStorage.saveSkillPins(empty)
                        }
                        if fm.fileExists(atPath: url.path) {
                            NSWorkspace.shared.open(url)
                        } else {
                            NSWorkspace.shared.open(url.deletingLastPathComponent())
                        }
                    }
                    Spacer()
                }
                .font(.caption)

                if resolved.isEmpty {
                    Text(HubUIStrings.Settings.Skills.emptyResolvedResults)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(resolved) { r in
                        skillResolvedRow(r)
                            .padding(.vertical, 3)
                    }
                }
            }

            DisclosureGroup(HubUIStrings.Settings.Skills.pins) {
                Text(HubUIStrings.Settings.Skills.memoryCorePins)
                    .font(.caption.weight(.semibold))
                if skillsPins.memoryCorePins.isEmpty {
                    Text(HubUIStrings.Settings.Skills.empty)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedPins(skillsPins.memoryCorePins)) { p in
                        skillPinRow(p, scope: .memoryCore)
                            .padding(.vertical, 3)
                    }
                }

                Divider()

                Text(HubUIStrings.Settings.Skills.globalPins)
                    .font(.caption.weight(.semibold))
                let uid = skillsResolveUserId.trimmingCharacters(in: .whitespacesAndNewlines)
                let globals = uid.isEmpty ? sortedPins(skillsPins.globalPins) : sortedPins(skillsPins.globalPins.filter { ($0.userId ?? "") == uid })
                if globals.isEmpty {
                    Text(HubUIStrings.Settings.Skills.emptyGlobalPins(needsUserID: uid.isEmpty))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(globals) { p in
                        skillPinRow(p, scope: .global)
                            .padding(.vertical, 3)
                    }
                }

                Divider()

                Text(HubUIStrings.Settings.Skills.projectPins)
                    .font(.caption.weight(.semibold))
                let pid = skillsResolveProjectId.trimmingCharacters(in: .whitespacesAndNewlines)
                let projects = (!uid.isEmpty && !pid.isEmpty)
                    ? sortedPins(skillsPins.projectPins.filter { ($0.userId ?? "") == uid && ($0.projectId ?? "") == pid })
                    : sortedPins(skillsPins.projectPins)
                if projects.isEmpty {
                    Text(HubUIStrings.Settings.Skills.emptyProjectPins(needsProjectFilter: uid.isEmpty || pid.isEmpty))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(projects) { p in
                        skillPinRow(p, scope: .project)
                            .padding(.vertical, 3)
                    }
                }
            }

            DisclosureGroup(HubUIStrings.Settings.Skills.search) {
                TextField(HubUIStrings.Settings.Skills.searchPlaceholder, text: $skillsSearchQuery)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)

                let results = HubSkillsStoreStorage.searchSkills(index: skillsIndex, sources: skillsSources, query: skillsSearchQuery, limit: 30)
                if results.isEmpty {
                    Text(
                        skillsSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? HubUIStrings.Settings.Skills.emptySkills
                            : HubUIStrings.Settings.Skills.noMatchingResults
                    )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(results) { meta in
                        skillMetaRow(meta)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var advancedSection: some View {
        Section(HubUIStrings.Settings.Advanced.sectionTitle) {
            DisclosureGroup(HubUIStrings.Settings.Advanced.Runtime.title) {
                Toggle(HubUIStrings.Settings.Advanced.Runtime.autoStart, isOn: $store.aiRuntimeAutoStart)

                HStack {
                    Text(HubUIStrings.Settings.Advanced.Runtime.status)
                    Spacer()
                    Text(store.aiRuntimeStatusText)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

            if !store.aiRuntimeLastError.isEmpty {
                Text(store.aiRuntimeLastError)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            if !store.aiRuntimeInstallHintsText.isEmpty {
                Text(store.aiRuntimeInstallHintsText)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }

            HStack(spacing: 10) {
                Button(HubUIStrings.Settings.Advanced.Runtime.start) { store.startAIRuntime() }
                Button(HubUIStrings.Settings.Advanced.Runtime.stop) { store.stopAIRuntime() }
                Button(HubUIStrings.Settings.Advanced.Runtime.openLog) { store.openAIRuntimeLog() }
                    Spacer()
                }

                DisclosureGroup(HubUIStrings.Settings.Advanced.Runtime.configuration) {
                    HStack {
                        Text(HubUIStrings.Settings.Advanced.Runtime.pythonPath)
                        Spacer()
                        TextField(HubUIStrings.Settings.Advanced.Runtime.pythonPathPlaceholder, text: $store.aiRuntimePython)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                    }
                    Text(HubUIStrings.Settings.Advanced.Runtime.packagedScriptHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !store.aiRuntimePythonCandidatesText.isEmpty {
                    DisclosureGroup(HubUIStrings.Settings.Advanced.Runtime.pythonCandidates) {
                        Text(store.aiRuntimePythonCandidatesText)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        HStack(spacing: 10) {
                            Button(HubUIStrings.Settings.Advanced.Runtime.copyPythonCandidates) {
                                copyRuntimePythonCandidatesToClipboard()
                            }
                            Spacer()
                        }
                        .font(.caption)
                    }
                }
            }

            DisclosureGroup(HubUIStrings.Settings.Advanced.Constitution.title) {
                HStack {
                    Text(HubUIStrings.Settings.Advanced.Constitution.policyFile)
                    Spacer()
                    Button(HubUIStrings.Settings.Advanced.Constitution.reload) { reloadAXConstitutionStatus() }
                    Button(HubUIStrings.Settings.Advanced.Constitution.open) { store.openAXConstitutionFile() }
                }
                let ver = axConstitutionVersion.trimmingCharacters(in: .whitespacesAndNewlines)
                HStack {
                    Text(HubUIStrings.Settings.Advanced.Constitution.version)
                    Spacer()
                    Text(ver.isEmpty ? HubUIStrings.Settings.Advanced.Constitution.unknown : ver)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                let clauseSummary = axConstitutionEnabledClauseIds.isEmpty
                    ? HubUIStrings.Settings.Advanced.Constitution.none
                    : axConstitutionEnabledClauseIds.joined(separator: ", ")
                Text(HubUIStrings.Settings.Advanced.Constitution.enabledClauses(clauseSummary))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                HStack(spacing: 10) {
                    Button(HubUIStrings.Settings.Advanced.Constitution.copySummary) { copyAXConstitutionSummaryToClipboard() }
                    Spacer()
                }
                Text(store.axConstitutionURL().path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                if !axConstitutionErrorText.isEmpty {
                    Text(axConstitutionErrorText)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                Text(HubUIStrings.Settings.Advanced.Constitution.bootstrapHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // FA Tracker launcher settings removed for teammate-facing builds.
        }
    }

    private var quitSection: some View {
        Section(HubUIStrings.Settings.Quit.sectionTitle) {
            HStack(spacing: 10) {
                Button(HubUIStrings.Settings.Quit.quitApp) { quitApp() }
                Spacer()
            }
            let ver = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
            let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
            Text(HubUIStrings.Settings.Quit.version(ver, build))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func networkRequestCard(_ req: HubNetworkRequest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(HubUIStrings.Settings.Networking.requestSource(req.source ?? HubUIStrings.Settings.Networking.unknown))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let p = req.rootPath, !p.isEmpty {
                Text(p)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            if let r = req.reason, !r.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(r)
                    .font(.caption)
            }

            let secs = req.requestedSeconds ?? 900
            HStack(spacing: 10) {
                Button(HubUIStrings.Settings.Networking.approveFiveMinutes) { store.approveNetworkRequest(req, seconds: 5 * 60) }
                Button(HubUIStrings.Settings.Networking.approveThirtyMinutes) { store.approveNetworkRequest(req, seconds: 30 * 60) }
                Button(HubUIStrings.Settings.Networking.approveSuggested(max(1, secs / 60))) { store.approveNetworkRequest(req, seconds: secs) }
                Button(HubUIStrings.Settings.Networking.dismiss) { store.dismissNetworkRequest(req) }
                Menu(HubUIStrings.Settings.Networking.policyMenu) {
                    Button(HubUIStrings.Settings.Networking.allowProjectAlways) {
                        // No explicit limit: "always on" will be kept alive automatically by Hub.
                        store.setNetworkPolicy(for: req, mode: .alwaysOn, maxSeconds: nil)
                        let requested = max(10, req.requestedSeconds ?? 900)
                        let secs = max(requested, 8 * 60 * 60)
                        store.approveNetworkRequest(req, seconds: secs)
                    }
                    Button(HubUIStrings.Settings.Networking.autoApproveProject) {
                        let maxSecs = max(10, req.requestedSeconds ?? 900)
                        store.setNetworkPolicy(for: req, mode: .autoApprove, maxSeconds: maxSecs)
                        store.approveNetworkRequest(req, seconds: maxSecs)
                    }
                    Button(HubUIStrings.Settings.Networking.denyProjectAlways) {
                        store.setNetworkPolicy(for: req, mode: .deny, maxSeconds: nil)
                        store.dismissNetworkRequest(req)
                    }
                }
                Spacer()
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func keychainStatusLine(model: RemoteModelEntry) -> some View {
        let status = keychainStatus(model: model)
        Text(status.text)
            .font(.caption2)
            .foregroundStyle(status.color)
    }

    private static let routingTaskTypes: [String] = [
        "assist",
        "review",
        "advisor",
        "x_terminal_coarse",
        "x_terminal_refine",
        "ax_coder_coarse",
        "ax_coder_refine",
    ]

    private func bindingRoutingModelId(_ taskType: String) -> Binding<String> {
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

    private func reloadRemoteModels() {
        remoteModels = Self.sortedRemoteModels(RemoteModelStorage.load().models)
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
        ModelStore.shared.refresh()
    }

    private func removeRemoteModel(id: String) {
        let snap = RemoteModelStorage.remove(id: id)
        remoteModels = Self.sortedRemoteModels(snap.models)
        ModelStore.shared.refresh()
    }

    private func removeRemoteModelGroup(_ group: RemoteModelKeyGroup) {
        let snap = RemoteModelStorage.remove(ids: group.models.map(\.id))
        remoteModels = Self.sortedRemoteModels(snap.models)
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
        persistRemoteModels()
    }

    private func setRemoteModelsEnabled(_ modelIDs: [String], enabled: Bool) {
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

    private func updatePolicy(_ rule: HubNetworkPolicyRule, mode: HubNetworkPolicyMode?, maxSeconds: Int?) {
        var r = rule
        if let m = mode { r.mode = m }
        r.maxSeconds = maxSeconds
        r.updatedAt = Date().timeIntervalSince1970
        _ = HubNetworkPolicyStorage.upsert(r)
        reloadNetworkPolicies()
        store.reloadNetworkPolicySnapshot()
    }

    private func removePolicy(_ rule: HubNetworkPolicyRule) {
        _ = HubNetworkPolicyStorage.remove(id: rule.id)
        reloadNetworkPolicies()
        store.reloadNetworkPolicySnapshot()
    }

    private func policyModeText(_ mode: HubNetworkPolicyMode) -> String {
        switch mode {
        case .manual: return HubUIStrings.Settings.NetworkPolicies.manual
        case .autoApprove: return HubUIStrings.Settings.NetworkPolicies.autoApprove
        case .alwaysOn: return HubUIStrings.Settings.NetworkPolicies.alwaysAllow
        case .deny: return HubUIStrings.Settings.NetworkPolicies.alwaysDeny
        }
    }

    private func policyLimitText(_ maxSeconds: Int?) -> String {
        guard let s = maxSeconds, s > 0 else { return HubUIStrings.Settings.NetworkPolicies.defaultLimit }
        let mins = max(1, s / 60)
        if mins >= 60 {
            let hours = max(1, mins / 60)
            return HubUIStrings.Settings.NetworkPolicies.hours(hours)
        }
        return HubUIStrings.Settings.NetworkPolicies.minutes(mins)
    }

    private func remoteModelGlyphName(for model: RemoteModelEntry) -> String {
        let haystack = remoteModelSearchText(model)
        if remoteModelLooksEmbedding(haystack) {
            return "point.3.connected.trianglepath.dotted"
        }
        if remoteModelLooksVoice(haystack) {
            return "speaker.wave.2.fill"
        }
        if remoteModelLooksAudio(haystack) {
            return "waveform"
        }
        if remoteModelLooksVision(haystack) {
            return "photo.on.rectangle"
        }
        if remoteModelLooksCode(haystack) {
            return "curlybraces"
        }
        return "cloud"
    }

    private func remoteModelGlyphTint(for model: RemoteModelEntry) -> Color {
        let haystack = remoteModelSearchText(model)
        if remoteModelLooksEmbedding(haystack) {
            return .green
        }
        if remoteModelLooksVoice(haystack) {
            return .mint
        }
        if remoteModelLooksAudio(haystack) {
            return .pink
        }
        if remoteModelLooksVision(haystack) {
            return .orange
        }
        if remoteModelLooksCode(haystack) {
            return .blue
        }
        return .secondary
    }

    private func remoteModelSignals(for model: RemoteModelEntry) -> [RemoteModelSignalVisual] {
        let haystack = remoteModelSearchText(model)
        var signals: [RemoteModelSignalVisual] = [
            RemoteModelSignalVisual(title: ModelCapabilityPresentation.localizedTitle(for: "hosted"), systemName: "cloud", tint: .blue)
        ]

        if remoteModelLooksReasoning(haystack) {
            signals.append(RemoteModelSignalVisual(title: ModelCapabilityPresentation.localizedTitle(for: "reasoning"), systemName: "sparkles", tint: .secondary))
        }
        if remoteModelLooksCode(haystack) {
            signals.append(RemoteModelSignalVisual(title: ModelCapabilityPresentation.localizedTitle(for: "code"), systemName: "curlybraces", tint: .blue))
        }
        if remoteModelLooksVision(haystack) {
            signals.append(RemoteModelSignalVisual(title: ModelCapabilityPresentation.localizedTitle(for: "vision"), systemName: "photo.on.rectangle", tint: .orange))
        }
        if remoteModelLooksEmbedding(haystack) {
            signals.append(RemoteModelSignalVisual(title: ModelCapabilityPresentation.localizedTitle(for: "embedding"), systemName: "point.3.connected.trianglepath.dotted", tint: .green))
        }
        if remoteModelLooksAudio(haystack) {
            signals.append(RemoteModelSignalVisual(title: ModelCapabilityPresentation.localizedTitle(for: "audio"), systemName: "waveform", tint: .pink))
        }
        if remoteModelLooksVoice(haystack) {
            signals.append(RemoteModelSignalVisual(title: ModelCapabilityPresentation.localizedTitle(for: "voice"), systemName: "speaker.wave.2.fill", tint: .mint))
        }

        var seen: Set<String> = []
        return signals.filter { seen.insert($0.title).inserted }
    }

    private func remoteModelMetadataTags(for model: RemoteModelEntry) -> [String] {
        var tags: [String] = []
        let backend = RemoteProviderEndpoints.canonicalBackend(model.backend).uppercased()
        if !backend.isEmpty {
            tags.append(backend)
        }
        if model.contextLength > 0 {
            tags.append(
                HubUIStrings.Settings.RemoteModels.configuredContextTag(
                    remoteModelContextSummary(model.contextLength)
                )
            )
        }
        if let knownContextLength = model.knownContextLength, knownContextLength > 0 {
            let summary = remoteModelContextSummary(knownContextLength)
            switch model.knownContextSource {
            case .providerReported:
                tags.append(HubUIStrings.Settings.RemoteModels.providerReportedContextTag(summary))
            case .catalogEstimate:
                tags.append(HubUIStrings.Settings.RemoteModels.catalogEstimatedContextTag(summary))
            case nil:
                break
            }
        }
        if let upstream = model.upstreamModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !upstream.isEmpty,
           upstream != model.id {
            tags.append(HubUIStrings.Settings.RemoteModels.aliasTag)
        }
        let normalized = Array(NSOrderedSet(array: tags)) as? [String] ?? tags
        return Array(normalized.prefix(3))
    }

    private func remoteModelDetailLine(_ model: RemoteModelEntry) -> String? {
        var parts: [String] = []
        if let host = remoteModelEndpointHost(model) {
            parts.append(HubUIStrings.Settings.RemoteModels.endpoint(host))
        }
        if let upstream = model.upstreamModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !upstream.isEmpty,
           upstream != model.id {
            parts.append(HubUIStrings.Settings.RemoteModels.upstreamModel(upstream))
        }
        let note = (model.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            parts.append(note)
        }
        if model.knownContextLength == nil {
            parts.append(HubUIStrings.Settings.RemoteModels.providerContextUnknown)
        } else if model.knownContextSource == .catalogEstimate {
            parts.append(HubUIStrings.Settings.RemoteModels.catalogEstimateHint)
        }
        guard !parts.isEmpty else { return nil }
        return HubUIStrings.Settings.RemoteModels.detailSummary(parts)
    }

    private func remoteModelSubtitle(_ model: RemoteModelEntry) -> String {
        let upstream = (model.upstreamModelId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let keyRef = RemoteModelStorage.keyReference(for: model)
        let backend = RemoteProviderEndpoints.canonicalBackend(model.backend)
        let context = HubUIStrings.Settings.RemoteModels.detailSummary(
            remoteModelContextSummaryParts(for: model)
        )
        if upstream.isEmpty || upstream == model.id {
            return HubUIStrings.Settings.RemoteModels.subtitleNoUpstream(
                modelID: model.id,
                backend: backend,
                context: context,
                keyRef: keyRef
            )
        }
        return HubUIStrings.Settings.RemoteModels.subtitleWithUpstream(
            modelID: model.id,
            upstream: upstream,
            backend: backend,
            context: context,
            keyRef: keyRef
        )
    }

    private func remoteModelContextSummary(_ contextLength: Int) -> String {
        HubUIStrings.Settings.RemoteModels.contextLength(contextLength)
    }

    private func remoteModelContextSummaryParts(for model: RemoteModelEntry) -> [String] {
        var parts: [String] = []
        if model.contextLength > 0 {
            parts.append(
                HubUIStrings.Settings.RemoteModels.configuredContext(
                    remoteModelContextSummary(model.contextLength)
                )
            )
        }
        if let knownContextLength = model.knownContextLength, knownContextLength > 0 {
            let summary = remoteModelContextSummary(knownContextLength)
            switch model.knownContextSource {
            case .providerReported:
                parts.append(HubUIStrings.Settings.RemoteModels.providerReportedContext(summary))
            case .catalogEstimate:
                parts.append(HubUIStrings.Settings.RemoteModels.catalogEstimatedContext(summary))
            case nil:
                break
            }
        } else if model.contextLength > 0 {
            parts.append(HubUIStrings.Settings.RemoteModels.providerContextUnknown)
        }
        return parts
    }

    private func remoteModelEndpointHost(_ model: RemoteModelEntry) -> String? {
        guard let raw = model.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let url = URL(string: raw) else {
            return nil
        }
        return url.host ?? url.absoluteString
    }

    private func remoteModelSearchText(_ model: RemoteModelEntry) -> String {
        [
            model.id,
            model.name,
            model.backend,
            model.upstreamModelId ?? "",
            model.note ?? "",
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private func remoteModelLooksReasoning(_ haystack: String) -> Bool {
        if remoteModelLooksEmbedding(haystack) || remoteModelLooksAudio(haystack) || remoteModelLooksVoice(haystack) {
            return false
        }
        return remoteModelContainsAny(
            haystack,
            needles: ["gpt", "claude", "gemini", "reason", "think", "sonnet", "opus", "o1", "o3", "o4", "r1", "qwq", "kimi", "qwen"]
        )
    }

    private func remoteModelLooksCode(_ haystack: String) -> Bool {
        remoteModelContainsAny(
            haystack,
            needles: ["coder", "codex", "codestral", "codegemma", "deepseek-coder", "qwen2.5-coder", "codeqwen"]
        )
    }

    private func remoteModelLooksVision(_ haystack: String) -> Bool {
        remoteModelContainsAny(
            haystack,
            needles: ["vision", "image", "vl", "llava", "pixtral", "moondream", "gpt-4o", "gemini", "claude", "see", "omni"]
        )
    }

    private func remoteModelLooksEmbedding(_ haystack: String) -> Bool {
        remoteModelContainsAny(
            haystack,
            needles: ["embedding", "embed", "text-embedding", "bge", "gte", "e5"]
        )
    }

    private func remoteModelLooksAudio(_ haystack: String) -> Bool {
        remoteModelContainsAny(
            haystack,
            needles: ["audio", "speech", "stt", "asr", "whisper", "transcribe"]
        )
    }

    private func remoteModelLooksVoice(_ haystack: String) -> Bool {
        remoteModelContainsAny(
            haystack,
            needles: ["tts", "voice", "text-to-speech"]
        )
    }

    private func remoteModelContainsAny(_ haystack: String, needles: [String]) -> Bool {
        needles.contains(where: { haystack.contains($0) })
    }

    private func keychainStatus(model: RemoteModelEntry) -> (text: String, color: Color) {
        let inMemory = (model.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !inMemory.isEmpty {
            if KeychainStore.hasSharedAccessGroup {
                return (HubUIStrings.Settings.RemoteModels.apiKeySetKeychainEncrypted, .secondary)
            }
            return (HubUIStrings.Settings.RemoteModels.apiKeySetEncrypted, .secondary)
        }

        let hasEncrypted = !(model.apiKeyCiphertext ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let acct = RemoteModelStorage.keyReference(for: model)

        // Avoid triggering repeated Keychain prompts in ad-hoc/dev builds (no shared access group).
        if !KeychainStore.hasSharedAccessGroup {
            if hasEncrypted {
                return (HubUIStrings.Settings.RemoteModels.apiKeySetEncryptedLocked, .orange)
            }
            return (HubUIStrings.Settings.RemoteModels.apiKeyUnset, .red)
        }

        switch KeychainStore.read(account: acct) {
        case .value:
            return (HubUIStrings.Settings.RemoteModels.apiKeySetKeychain, .secondary)
        case .notFound:
            if hasEncrypted {
                return (HubUIStrings.Settings.RemoteModels.apiKeySetEncryptedLocked, .orange)
            }
            return (HubUIStrings.Settings.RemoteModels.apiKeyUnset, .red)
        case .error(let msg):
            if hasEncrypted {
                return (HubUIStrings.Settings.RemoteModels.apiKeySetEncryptedKeychainError, .orange)
            }
            return (HubUIStrings.Settings.RemoteModels.apiKeyKeychainError(msg), .red)
        }
    }

    private func remoteKeyUsageLimitNotice(for group: RemoteModelKeyGroup) -> RemoteKeyUsageLimitNotice? {
        RemoteModelTrialIssueSupport.latestUsageLimitNotice(
            in: group.models.compactMap { store.remoteModelTrialStatus(for: $0.id) }
        )
    }

    private func remoteKeyHealthPresentation(
        for group: RemoteModelKeyGroup,
        usageLimitNotice: RemoteKeyUsageLimitNotice?
    ) -> RemoteKeyHealthPresentation? {
        RemoteKeyHealthPresentationSupport.presentation(
            health: store.remoteKeyHealth(for: group.keyReference),
            usageLimitNotice: usageLimitNotice,
            isScanning: store.isRemoteKeyHealthScanInProgress(for: group.keyReference)
        )
    }

    private var remoteModelGroups: [RemoteModelKeyGroup] {
        RemoteModelPresentationSupport.groups(
            from: remoteModels,
            healthSnapshot: store.remoteKeyHealthSnapshot
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
}

private struct RemoteModelKeyGroup: Identifiable {
    let id: String
    let keyReference: String
    let title: String
    let detail: String?
    let models: [RemoteModelEntry]
    let loadedCount: Int
    let availableCount: Int
    let needsSetupCount: Int
    let enabledCount: Int

    var primaryModel: RemoteModelEntry {
        models[0]
    }

    var loadableModelIDs: [String] {
        models
            .filter { RemoteModelPresentationSupport.state(for: $0) == .available }
            .map(\.id)
    }

    var enabledModelIDs: [String] {
        models.filter(\.enabled).map(\.id)
    }

    var renameActionTitle: String {
        primaryModel.effectiveGroupDisplayName == nil
            ? HubUIStrings.Settings.RemoteModels.setGroupName
            : HubUIStrings.Settings.RemoteModels.renameGroup
    }

    var summary: String {
        var parts = [HubUIStrings.Settings.RemoteModels.keyGroupSummary(count: models.count, enabled: enabledCount)]
        if loadedCount > 0 {
            parts.append("\(loadedCount) \(HubUIStrings.Settings.RemoteModels.loaded)")
        }
        if availableCount > 0 {
            parts.append("\(availableCount) \(HubUIStrings.Settings.RemoteModels.available)")
        }
        if needsSetupCount > 0 {
            parts.append("\(needsSetupCount) \(HubUIStrings.Settings.RemoteModels.needsSetup)")
        }
        return HubUIStrings.Settings.RemoteModels.detailSummary(parts)
    }
}

private struct EditRemoteModelGroupDisplayNameSheet: View {
    let group: RemoteModelKeyGroup
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftName: String

    init(group: RemoteModelKeyGroup, onSave: @escaping (String) -> Void) {
        self.group = group
        self.onSave = onSave
        _draftName = State(initialValue: group.primaryModel.effectiveGroupDisplayName ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(HubUIStrings.Settings.RemoteModels.editGroupNameTitle)
                .font(.headline)

            Text(HubUIStrings.Settings.RemoteModels.editGroupNameSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(HubUIStrings.Settings.RemoteModels.editGroupNamePlaceholder, text: $draftName)
                .textFieldStyle(.roundedBorder)

            if group.primaryModel.effectiveGroupDisplayName == nil {
                Text(HubUIStrings.Settings.RemoteModels.fallbackGroupTitle(group.title))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                Button(HubUIStrings.Settings.RemoteModels.cancel) {
                    dismiss()
                }
                Spacer()
                Button(HubUIStrings.Settings.RemoteModels.editGroupNameSave) {
                    onSave(draftName)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 420, height: 190)
    }
}

private struct AddGRPCClientSheet: View {
    let onAdd: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(HubUIStrings.Settings.GRPC.AddDeviceSheet.title)
                .font(.headline)

            TextField(HubUIStrings.Settings.GRPC.AddDeviceSheet.namePlaceholder, text: $name)
                .textFieldStyle(.roundedBorder)

            Text(HubUIStrings.Settings.GRPC.AddDeviceSheet.hint)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button(HubUIStrings.Settings.GRPC.AddDeviceSheet.cancel) { dismiss() }
                Button(HubUIStrings.Settings.GRPC.AddDeviceSheet.createAndCopy) {
                    onAdd(name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}

private struct EditGRPCClientSheet: View {
    let client: HubGRPCClientEntry
    let serverPort: Int
    let localModels: [ModelCatalogEntry]
    let existingLocalModelProfiles: [String: HubPairedTerminalLocalModelProfile]
    let suggestedLANAllowedCidrs: [String]
    let initialCapabilityFocusKey: String?
    let onSave: (HubGRPCClientEntry) -> Void
    let onSaveRoutingSettings: (RoutingSettings) -> Void
    let onUpsertLocalModelProfile: (HubPairedTerminalLocalModelProfile) -> Void
    let onRemoveLocalModelProfile: (String, String) -> Void
    let onRotateToken: (String) -> String?
    let onCopyVars: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var userId: String
    @State private var enabled: Bool
    @State private var token: String
    @State private var createdAtMs: Int64
    @State private var allowAnySourceIP: Bool
    @State private var allowedCidrs: [String]
    @State private var allowedCidrsBackup: [String]
    @State private var addCidrText: String
    @State private var caps: Set<String>
    @State private var certSha256: String
    @State private var policyMode: HubGRPCClientPolicyMode
    @State private var paidModelSelectionMode: HubPaidModelSelectionMode
    @State private var allowedPaidModelsText: String
    @State private var defaultWebFetchEnabled: Bool
    @State private var dailyTokenLimitText: String
    @State private var localTaskRoutingExpanded: Bool
    @State private var localModelOverridesExpanded: Bool
    @State private var routingSettingsDraft: RoutingSettings
    @State private var localModelContextOverrideTextById: [String: String]
    @State private var localModelTTLTextById: [String: String]
    @State private var localModelParallelTextById: [String: String]
    @State private var localModelIdentifierById: [String: String]
    @State private var localModelVisionImageMaxDimensionTextById: [String: String]
    @State private var localModelAdvancedExpandedById: [String: Bool]
    @State private var localModelNoteById: [String: String]

    init(
        client: HubGRPCClientEntry,
        serverPort: Int,
        localModels: [ModelCatalogEntry],
        routingSettings: RoutingSettings,
        existingLocalModelProfiles: [String: HubPairedTerminalLocalModelProfile],
        suggestedLANAllowedCidrs: [String],
        initialCapabilityFocusKey: String? = nil,
        onSave: @escaping (HubGRPCClientEntry) -> Void,
        onSaveRoutingSettings: @escaping (RoutingSettings) -> Void,
        onUpsertLocalModelProfile: @escaping (HubPairedTerminalLocalModelProfile) -> Void,
        onRemoveLocalModelProfile: @escaping (String, String) -> Void,
        onRotateToken: @escaping (String) -> String?,
        onCopyVars: @escaping (String) -> Void
    ) {
        self.client = client
        self.serverPort = serverPort
        self.localModels = localModels
        self.existingLocalModelProfiles = existingLocalModelProfiles
        self.suggestedLANAllowedCidrs = Self.orderedAllowedCidrs(Self.normalizeAllowedCidrs(suggestedLANAllowedCidrs))
        self.initialCapabilityFocusKey = hubNormalizedPairedDeviceCapabilityFocusKey(initialCapabilityFocusKey)
        self.onSave = onSave
        self.onSaveRoutingSettings = onSaveRoutingSettings
        self.onUpsertLocalModelProfile = onUpsertLocalModelProfile
        self.onRemoveLocalModelProfile = onRemoveLocalModelProfile
        self.onRotateToken = onRotateToken
        self.onCopyVars = onCopyVars

        _name = State(initialValue: client.name)
        _userId = State(initialValue: client.userId)
        _enabled = State(initialValue: client.enabled)
        _token = State(initialValue: client.token)
        _createdAtMs = State(initialValue: client.createdAtMs)
        let initialCidrs = Self.normalizeAllowedCidrs(client.allowedCidrs)
        let allowAny = initialCidrs.isEmpty
        _allowAnySourceIP = State(initialValue: allowAny)
        // When allow-any is enabled, keep a safe restore set so users can flip back without rebuilding rules.
        let backup = allowAny ? ["private", "loopback"] : initialCidrs
        _allowedCidrs = State(initialValue: backup)
        _allowedCidrsBackup = State(initialValue: backup)
        _addCidrText = State(initialValue: "")
        _caps = State(initialValue: Set(client.capabilities))
        _certSha256 = State(initialValue: client.certSha256)
        let profile = client.approvedTrustProfile
        let legacyPaidEnabled = client.capabilities.contains("ai.generate.paid")
        let legacyWebFetchEnabled = client.capabilities.contains("web.fetch")
        _policyMode = State(initialValue: client.policyMode)
        _paidModelSelectionMode = State(initialValue: profile?.paidModelPolicy.mode ?? (legacyPaidEnabled ? .allPaidModels : .off))
        _allowedPaidModelsText = State(initialValue: (profile?.paidModelPolicy.allowedModelIds ?? []).joined(separator: ", "))
        _defaultWebFetchEnabled = State(initialValue: profile?.networkPolicy.defaultWebFetchEnabled ?? legacyWebFetchEnabled)
        let initialDailyTokenLimit = profile?.budgetPolicy.dailyTokenLimit ?? HubTrustProfileDefaults.dailyTokenLimit
        _dailyTokenLimitText = State(initialValue: String(max(1, initialDailyTokenLimit)))
        _localTaskRoutingExpanded = State(initialValue: true)
        _localModelOverridesExpanded = State(initialValue: !localModels.isEmpty)
        _routingSettingsDraft = State(initialValue: routingSettings)

        var contextOverrideTextById: [String: String] = [:]
        var ttlTextById: [String: String] = [:]
        var parallelTextById: [String: String] = [:]
        var identifierById: [String: String] = [:]
        var visionImageMaxDimensionTextById: [String: String] = [:]
        var advancedExpandedById: [String: Bool] = [:]
        var noteById: [String: String] = [:]
        for model in localModels {
            let existingProfile = existingLocalModelProfiles[model.id]
            contextOverrideTextById[model.id] = existingProfile?.overrideProfile.contextLength.map(String.init) ?? ""
            ttlTextById[model.id] = existingProfile?.overrideProfile.ttl.map(String.init) ?? ""
            parallelTextById[model.id] = existingProfile?.overrideProfile.parallel.map(String.init) ?? ""
            identifierById[model.id] = existingProfile?.overrideProfile.identifier ?? ""
            visionImageMaxDimensionTextById[model.id] = existingProfile?.overrideProfile.vision?.imageMaxDimension.map(String.init) ?? ""
            advancedExpandedById[model.id] = Self.localModelProfileHasAdvancedFields(existingProfile?.overrideProfile)
            noteById[model.id] = existingProfile?.note ?? ""
        }
        _localModelContextOverrideTextById = State(initialValue: contextOverrideTextById)
        _localModelTTLTextById = State(initialValue: ttlTextById)
        _localModelParallelTextById = State(initialValue: parallelTextById)
        _localModelIdentifierById = State(initialValue: identifierById)
        _localModelVisionImageMaxDimensionTextById = State(initialValue: visionImageMaxDimensionTextById)
        _localModelAdvancedExpandedById = State(initialValue: advancedExpandedById)
        _localModelNoteById = State(initialValue: noteById)
    }

    private struct CapSpec: Identifiable {
        var key: String
        var title: String
        var detail: String
        var id: String { key }
    }

    private static let capSpecs: [CapSpec] = [
        CapSpec(key: "models", title: HubUIStrings.Settings.GRPC.EditDeviceSheet.capModelsTitle, detail: HubUIStrings.Settings.GRPC.EditDeviceSheet.capModelsDetail),
        CapSpec(key: "events", title: HubUIStrings.Settings.GRPC.EditDeviceSheet.capEventsTitle, detail: HubUIStrings.Settings.GRPC.EditDeviceSheet.capEventsDetail),
        CapSpec(key: "memory", title: HubUIStrings.Settings.GRPC.EditDeviceSheet.capMemoryTitle, detail: HubUIStrings.Settings.GRPC.EditDeviceSheet.capMemoryDetail),
        CapSpec(key: "skills", title: HubUIStrings.Settings.GRPC.EditDeviceSheet.capSkillsTitle, detail: HubUIStrings.Settings.GRPC.EditDeviceSheet.capSkillsDetail),
        CapSpec(key: "ai.generate.local", title: HubUIStrings.Settings.GRPC.EditDeviceSheet.capLocalAITitle, detail: HubUIStrings.Settings.GRPC.EditDeviceSheet.capLocalAIDetail),
        CapSpec(key: "ai.generate.paid", title: HubUIStrings.Settings.GRPC.EditDeviceSheet.capPaidAITitle, detail: HubUIStrings.Settings.GRPC.EditDeviceSheet.capPaidAIDetail),
        CapSpec(key: "web.fetch", title: HubUIStrings.Settings.GRPC.EditDeviceSheet.capWebFetchTitle, detail: HubUIStrings.Settings.GRPC.EditDeviceSheet.capWebFetchDetail),
    ]

    private static func capSpec(for key: String?) -> CapSpec? {
        let normalizedKey = hubNormalizedPairedDeviceCapabilityFocusKey(key)
        return capSpecs.first(where: { $0.key == normalizedKey })
    }

    private static func localModelProfileHasAdvancedFields(_ profile: LocalModelLoadProfileOverride?) -> Bool {
        guard let profile else { return false }
        return profile.ttl != nil
            || profile.parallel != nil
            || !(profile.identifier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || !(profile.vision?.isEmpty ?? true)
            || profile.gpuOffloadRatio != nil
            || profile.ropeFrequencyBase != nil
            || profile.ropeFrequencyScale != nil
            || profile.evalBatchSize != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.title)
                        .font(.headline)
                    Spacer()
                    Button(HubUIStrings.Settings.GRPC.EditDeviceSheet.cancel) { dismiss() }
                    Button(HubUIStrings.Settings.GRPC.EditDeviceSheet.save) {
                        var out = client
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let effectiveName = trimmedName.isEmpty ? client.deviceId : trimmedName
                        out.name = effectiveName
                        out.userId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
                        out.enabled = enabled
                        out.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
                        out.createdAtMs = createdAtMs
                        out.allowedCidrs = allowAnySourceIP ? [] : orderedAllowedCidrs(allowedCidrs)
                        out.certSha256 = certSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        if policyMode == .newProfile {
                            let profile = HubGRPCClientEntry.buildApprovedTrustProfile(
                                deviceId: client.deviceId,
                                deviceName: effectiveName,
                                requestedCapabilities: orderedCaps(Array(caps)),
                                paidModelSelectionMode: paidModelSelectionMode,
                                allowedPaidModels: parseList(allowedPaidModelsText),
                                defaultWebFetchEnabled: defaultWebFetchEnabled,
                                dailyTokenLimit: parsedDailyTokenLimit ?? HubTrustProfileDefaults.dailyTokenLimit,
                                auditRef: client.deviceId
                            )
                            out.policyMode = .newProfile
                            out.approvedTrustProfile = profile
                            out.capabilities = profile.capabilities
                        } else {
                            out.policyMode = .legacyGrant
                            out.approvedTrustProfile = nil
                            out.capabilities = orderedCaps(Array(caps))
                        }
                        onSaveRoutingSettings(routingSettingsDraft)
                        persistLocalModelProfiles()
                        onSave(out)
                        dismiss()
                    }
                    .disabled(!allowedCidrsConfigIsValid || !policyProfileIsValid || !localModelOverridesAreValid)
                    .keyboardShortcut(.defaultAction)
                }

                if let focusedCapabilitySpec {
                    focusedGrantBanner(focusedCapabilitySpec)
                }

                VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.deviceID)
                    Spacer()
                    Text(client.deviceId)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Toggle(HubUIStrings.Settings.GRPC.EditDeviceSheet.enabled, isOn: $enabled)
                TextField(HubUIStrings.Settings.GRPC.EditDeviceSheet.displayNamePlaceholder, text: $name)
                    .textFieldStyle(.roundedBorder)
                TextField(HubUIStrings.Settings.GRPC.EditDeviceSheet.userIDPlaceholder, text: $userId)
                    .textFieldStyle(.roundedBorder)
            }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.policyMode)
                    .font(.callout.weight(.semibold))
                Picker(HubUIStrings.Settings.GRPC.EditDeviceSheet.policyMode, selection: $policyMode) {
                    ForEach(HubGRPCClientPolicyMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if policyMode == .newProfile {
                    Picker(HubUIStrings.Settings.GRPC.EditDeviceSheet.paidModels, selection: $paidModelSelectionMode) {
                        ForEach(HubPaidModelSelectionMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    if focusedCapabilityKey == "ai.generate.paid" {
                        focusedGrantMarker()
                    }

                    if paidModelSelectionMode == .customSelectedModels {
                        TextField(HubUIStrings.Settings.GRPC.EditDeviceSheet.customPaidModelsPlaceholder, text: $allowedPaidModelsText)
                            .textFieldStyle(.roundedBorder)
                        if parseList(allowedPaidModelsText).isEmpty {
                            Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.customPaidModelsError)
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }

                    Toggle(HubUIStrings.Settings.GRPC.EditDeviceSheet.defaultAllowWebFetch, isOn: $defaultWebFetchEnabled)
                    if focusedCapabilityKey == "web.fetch" {
                        focusedGrantMarker()
                    }

                    TextField(HubUIStrings.Settings.GRPC.EditDeviceSheet.dailyTokenLimit, text: $dailyTokenLimitText)
                        .textFieldStyle(.roundedBorder)
                    if parsedDailyTokenLimit == nil {
                        Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.dailyTokenLimitError)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    } else {
                        Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.saveHint)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.legacyHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.capabilities)
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Button(HubUIStrings.Settings.GRPC.EditDeviceSheet.localOnly) {
                        caps = Set(["models", "events", "memory", "skills", "ai.generate.local"])
                    }
                    .font(.caption)
                    Button(HubUIStrings.Settings.GRPC.EditDeviceSheet.allowAll) {
                        caps = Set(["models", "events", "memory", "skills", "ai.generate.local", "ai.generate.paid", "web.fetch"])
                    }
                    .font(.caption)
                }

                ForEach(Self.capSpecs) { spec in
                    capabilityToggleRow(spec)
                }

                if policyMode == .newProfile {
                    Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.policyProfileCapabilitiesHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if caps.isEmpty {
                    Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.emptyCapabilitiesWarning)
                        .font(.caption2)
                        .foregroundStyle(.red)
                } else {
                    Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.capabilitiesHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.allowedSources)
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Button(HubUIStrings.Settings.GRPC.EditDeviceSheet.adoptSuggestedRange) {
                        let defaults = suggestedLANAllowedCidrs.isEmpty ? ["private", "loopback"] : suggestedLANAllowedCidrs
                        allowAnySourceIP = false
                        allowedCidrs = defaults
                        allowedCidrsBackup = defaults
                    }
                        .font(.caption)
                    Button(HubUIStrings.Settings.GRPC.EditDeviceSheet.lanOnly) {
                        allowAnySourceIP = false
                        allowedCidrs = ["private", "loopback"]
                        allowedCidrsBackup = allowedCidrs
                    }
                        .font(.caption)
                    Button(HubUIStrings.Settings.GRPC.EditDeviceSheet.anySource) { allowAnySourceIP = true }
                        .font(.caption)
                }

                Toggle(
                    HubUIStrings.Settings.GRPC.EditDeviceSheet.allowAnySourceIP,
                    isOn: Binding(
                        get: { allowAnySourceIP },
                        set: { on in
                            if on {
                                allowedCidrsBackup = orderedAllowedCidrs(allowedCidrs)
                                allowAnySourceIP = true
                            } else {
                                allowAnySourceIP = false
                                let restore = orderedAllowedCidrs(allowedCidrsBackup)
                                allowedCidrs = restore.isEmpty ? ["private", "loopback"] : restore
                            }
                        }
                    )
                )

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(HubUIStrings.Settings.GRPC.EditDeviceSheet.allowPrivate, isOn: bindingAllowedCidrRule("private"))
                    Toggle(HubUIStrings.Settings.GRPC.EditDeviceSheet.allowLoopback, isOn: bindingAllowedCidrRule("loopback"))

                    let customs = allowedCidrsCustomItems
                    if !customs.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.customSources)
                                .font(.caption.weight(.semibold))
                            ForEach(customs, id: \.self) { v in
                                HStack(spacing: 8) {
                                    Text(v)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                    Spacer()
                                    Button(HubUIStrings.Settings.GRPC.EditDeviceSheet.remove) { removeAllowedCidrValue(v) }
                                        .font(.caption)
                                }
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        TextField(HubUIStrings.Settings.GRPC.EditDeviceSheet.addCIDROrIPPlaceholder, text: $addCidrText)
                            .textFieldStyle(.roundedBorder)
                        Button(HubUIStrings.Settings.GRPC.EditDeviceSheet.add) { addAllowedCidrsFromText(addCidrText) }
                            .font(.caption)
                            .disabled(addCidrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .disabled(allowAnySourceIP)

                if allowAnySourceIP {
                    Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.anySourceWarning)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else if !allowedCidrsConfigIsValid {
                    Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.invalidRestrictedSources)
                        .font(.caption2)
                        .foregroundStyle(.red)
                } else {
                    Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.supportedSourcesHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if !suggestedLANAllowedCidrs.isEmpty {
                        Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.suggestedLANRanges(suggestedLANAllowedCidrs.joined(separator: ", ")))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

                if hasLocalTaskRoutingSection {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.localTaskRoutingTitle)
                                .font(.callout.weight(.semibold))
                            Spacer()
                            Button(localTaskRoutingExpanded ? HubUIStrings.Settings.GRPC.EditDeviceSheet.collapse : HubUIStrings.Settings.GRPC.EditDeviceSheet.expand) {
                                localTaskRoutingExpanded.toggle()
                            }
                            .font(.caption)
                        }

                        Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.localTaskRoutingHint)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if localTaskRoutingExpanded {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(LocalTaskRoutingCatalog.descriptors) { descriptor in
                                    pairedTerminalLocalTaskRoutingCard(descriptor)
                                }
                            }
                        } else {
                            Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.localTaskRoutingCount(LocalTaskRoutingCatalog.descriptors.count))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !localModels.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.localModelOverridesTitle)
                                .font(.callout.weight(.semibold))
                            Spacer()
                            Button(localModelOverridesExpanded ? HubUIStrings.Settings.GRPC.EditDeviceSheet.collapse : HubUIStrings.Settings.GRPC.EditDeviceSheet.expand) {
                                localModelOverridesExpanded.toggle()
                            }
                            .font(.caption)
                        }

                        Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.localModelOverridesHint)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if localModelOverridesExpanded {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(localModels) { model in
                                    pairedTerminalLocalModelOverrideCard(model)
                                }
                            }
                        } else {
                            Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.localModelOverridesCount(localModels.count))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.mtlsFingerprint)
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Button(HubUIStrings.Settings.GRPC.EditDeviceSheet.clear) { certSha256 = "" }
                        .font(.caption)
                }
                TextField(HubUIStrings.Settings.GRPC.EditDeviceSheet.certFingerprintPlaceholder, text: $certSha256)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption2.monospaced())
                Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.certFingerprintHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

                Divider()

                HStack(spacing: 10) {
                Button(HubUIStrings.Settings.GRPC.EditDeviceSheet.copyLANVars) { onCopyVars(token) }
                    .font(.caption)
                Button(HubUIStrings.Settings.GRPC.EditDeviceSheet.copyRemoteVars) {
                    let p = max(1, min(65535, serverPort))
                    let snippet = """
HUB_HOST=<hub_vpn_ip_or_tunnel>
HUB_PORT=\(p)
HUB_CLIENT_TOKEN='\(token)'
"""
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(snippet, forType: .string)
                }
                .font(.caption)
                Button(HubUIStrings.Settings.GRPC.rotateDeviceToken) {
                    if let newToken = onRotateToken(client.deviceId) {
                        token = newToken
                        createdAtMs = Int64(Date().timeIntervalSince1970 * 1000.0)
                    }
                }
                .font(.caption)
                Spacer()
                }

                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(width: 560, height: 760)
    }

    private func bindingCap(_ key: String) -> Binding<Bool> {
        Binding(
            get: { caps.contains(key) },
            set: { on in
                if on { caps.insert(key) } else { caps.remove(key) }
            }
        )
    }

    private var focusedCapabilityKey: String? {
        hubNormalizedPairedDeviceCapabilityFocusKey(initialCapabilityFocusKey)
    }

    private var focusedCapabilitySpec: CapSpec? {
        Self.capSpec(for: focusedCapabilityKey)
    }

    @ViewBuilder
    private func focusedGrantBanner(_ spec: CapSpec) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(HubUIStrings.Settings.GRPC.EditDeviceSheet.focusedGrantTitle, systemImage: "exclamationmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.focusedGrantSummary(spec.title))
                .font(.caption)
            Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.focusedGrantNextStep(spec.title))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.09))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func focusedGrantMarker() -> some View {
        Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.focusedGrantMarker)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func capabilityToggleRow(_ spec: CapSpec) -> some View {
        let isFocused = spec.key == focusedCapabilityKey
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: bindingCap(spec.key)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(spec.title)
                        .font(.caption.weight(.semibold))
                    Text(spec.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if isFocused {
                focusedGrantMarker()
            }
        }
        .padding(isFocused ? 10 : 0)
        .background(isFocused ? Color.orange.opacity(0.08) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isFocused ? Color.orange.opacity(0.28) : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var parsedDailyTokenLimit: Int? {
        let trimmed = dailyTokenLimitText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    private var policyProfileIsValid: Bool {
        guard policyMode == .newProfile else { return true }
        guard parsedDailyTokenLimit != nil else { return false }
        if paidModelSelectionMode == .customSelectedModels {
            return !parseList(allowedPaidModelsText).isEmpty
        }
        return true
    }

    private var allowedCidrsConfigIsValid: Bool {
        // Empty allowed_cidrs means "allow any source IP" on the server, which is only intended when
        // allowAnySourceIP is enabled. In restricted mode, enforce at least one rule so the UI intent matches reality.
        if allowAnySourceIP { return true }
        return !orderedAllowedCidrs(allowedCidrs).isEmpty
    }

    private var localModelOverridesAreValid: Bool {
        localModels.allSatisfy { localModelValidationMessages(for: $0).isEmpty }
    }

    private var hasLocalTaskRoutingSection: Bool {
        if !localModels.isEmpty {
            return true
        }
        return LocalTaskRoutingCatalog.descriptors.contains { descriptor in
            let binding = routingBindingDraft(for: descriptor.taskKind)
            return !binding.hubDefaultModelId.isEmpty || !binding.deviceOverrideModelId.isEmpty
        }
    }

    private func routingBindingDraft(for taskKind: String) -> HubResolvedRoutingBinding {
        let normalizedTaskKind = taskKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let resolved = routingSettingsDraft.resolvedModelId(taskKind: normalizedTaskKind, deviceId: client.deviceId)
        let normalizedDeviceId = client.deviceId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return HubResolvedRoutingBinding(
            taskType: normalizedTaskKind,
            taskLabel: LocalTaskRoutingCatalog.title(for: normalizedTaskKind),
            effectiveModelId: resolved.modelId,
            source: resolved.source,
            hubDefaultModelId: routingSettingsDraft.hubDefaultModelIdByTaskKind[normalizedTaskKind] ?? "",
            deviceOverrideModelId: routingSettingsDraft.devicePreferredModelIdByTaskKind[normalizedDeviceId]?[normalizedTaskKind] ?? ""
        )
    }

    private func localModelsSupportingTaskKind(_ taskKind: String) -> [ModelCatalogEntry] {
        let normalizedTaskKind = taskKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return localModels.filter { model in
            LocalTaskRoutingCatalog.supportedTaskKinds(in: model.taskKinds).contains(normalizedTaskKind)
        }
    }

    private func routingModelDisplayName(_ modelId: String) -> String {
        let trimmed = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return HubUIStrings.Settings.GRPC.EditDeviceSheet.automatic }
        if let model = localModels.first(where: { $0.id == trimmed }) {
            return model.name.isEmpty ? model.id : model.name
        }
        return HubUIStrings.Settings.GRPC.EditDeviceSheet.missingModel(trimmed)
    }

    private func routingSourceLabel(_ source: String) -> String {
        switch source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "request_override":
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.requestOverride
        case "device_override":
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.deviceOverride
        case "hub_default":
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.hubDefault
        case "auto_selected":
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.autoSelected
        default:
            return source.isEmpty ? HubUIStrings.Settings.GRPC.EditDeviceSheet.autoSelected : source
        }
    }

    private func localModelContextSourceLabel(_ source: String) -> String {
        switch source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "hub_default":
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.hubDefault
        case "device_override":
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.deviceOverride
        case "runtime_clamped":
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.runtimeClamped
        default:
            return source.isEmpty ? HubUIStrings.Settings.GRPC.EditDeviceSheet.hubDefault : source
        }
    }

    private func pairedTerminalLocalTaskRoutingCard(_ descriptor: LocalTaskRoutingDescriptor) -> some View {
        let binding = routingBindingDraft(for: descriptor.taskKind)
        let compatibleModels = localModelsSupportingTaskKind(descriptor.taskKind)
        let hubDefaultDisplay = routingModelDisplayName(binding.hubDefaultModelId)
        let deviceOverrideDisplay = binding.deviceOverrideModelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (
                binding.hubDefaultModelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? HubUIStrings.Settings.GRPC.EditDeviceSheet.automatic
                : HubUIStrings.Settings.GRPC.EditDeviceSheet.hubDefault
            )
            : routingModelDisplayName(binding.deviceOverrideModelId)
        let effectiveDisplay = routingModelDisplayName(binding.effectiveModelId)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(descriptor.title)
                        .font(.caption.weight(.semibold))
                    Text(descriptor.taskKind)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(routingSourceLabel(binding.source))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.inheritHubDefault)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(hubDefaultDisplay)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack {
                Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.deviceOverride)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button(HubUIStrings.Settings.GRPC.EditDeviceSheet.useHubDefault) {
                        routingSettingsDraft.setModelId(nil, for: descriptor.taskKind, deviceId: client.deviceId)
                    }
                    Divider()
                    ForEach(compatibleModels) { model in
                        Button(model.name.isEmpty ? model.id : model.name) {
                            routingSettingsDraft.setModelId(model.id, for: descriptor.taskKind, deviceId: client.deviceId)
                        }
                    }
                } label: {
                    Text(deviceOverrideDisplay)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                .controlSize(.mini)
            }

            HStack {
                Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.effectiveFinal)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(
                    HubUIStrings.Settings.GRPC.EditDeviceSheet.effectiveSummary(
                        display: effectiveDisplay,
                        source: routingSourceLabel(binding.source)
                    )
                )
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if compatibleModels.isEmpty {
                Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.noCompatibleLocalModels(descriptor.shortTitle))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.compatibleModels(
                    compatibleModels.map { $0.name.isEmpty ? $0.id : $0.name }.joined(separator: ", ")
                ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var allowedCidrsCustomItems: [String] {
        let norm = Self.normalizeAllowedCidrs(allowedCidrs)
        return norm.filter { v in
            let lower = v.lowercased()
            return lower != "private" && lower != "loopback"
        }
    }

    private func bindingAllowedCidrRule(_ rule: String) -> Binding<Bool> {
        let key = rule.lowercased()
        return Binding(
            get: { Self.normalizeAllowedCidrs(allowedCidrs).contains(where: { $0.lowercased() == key }) },
            set: { on in
                if on { addAllowedCidrValue(key) } else { removeAllowedCidrValue(key) }
            }
        )
    }

    private func addAllowedCidrsFromText(_ text: String) {
        let parts = text
            .split(whereSeparator: { ch in
                ch == "," || ch == "\n" || ch == ";" || ch == "\t"
            })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return }
        for p in parts {
            addAllowedCidrValue(p)
        }
        addCidrText = ""
    }

    private func addAllowedCidrValue(_ value: String) {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        // Treat allow-all aliases as "Any" mode for clarity.
        let lower = cleaned.lowercased()
        if lower == "any" || lower == "*" {
            allowAnySourceIP = true
            return
        }
        allowAnySourceIP = false

        var cur = Self.normalizeAllowedCidrs(allowedCidrs)
        let canon: String = {
            if lower == "localhost" { return "loopback" }
            if lower == "loopback" { return "loopback" }
            if lower == "private" { return "private" }
            return cleaned
        }()
        if cur.contains(where: { $0.lowercased() == canon.lowercased() }) {
            allowedCidrs = orderedAllowedCidrs(cur)
            return
        }
        cur.append(canon)
        allowedCidrs = orderedAllowedCidrs(cur)
        allowedCidrsBackup = orderedAllowedCidrs(cur)
    }

    private func removeAllowedCidrValue(_ value: String) {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return }
        var cur = Self.normalizeAllowedCidrs(allowedCidrs)
        cur.removeAll { $0.lowercased() == key }
        allowedCidrs = orderedAllowedCidrs(cur)
        allowedCidrsBackup = orderedAllowedCidrs(cur)
    }

    private func orderedAllowedCidrs(_ list: [String]) -> [String] {
        Self.orderedAllowedCidrs(list)
    }

    private static func orderedAllowedCidrs(_ list: [String]) -> [String] {
        let clean = Self.normalizeAllowedCidrs(list)
        if clean.isEmpty { return [] }

        // Keep stable order but pull well-known rules to the front.
        let order = ["private", "loopback"]
        var out: [String] = []
        for k in order {
            if clean.contains(where: { $0.lowercased() == k }) { out.append(k) }
        }
        out.append(contentsOf: clean.filter { v in
            let lower = v.lowercased()
            return !order.contains(lower)
        })
        return out
    }

    private static func normalizeAllowedCidrs(_ list: [String]) -> [String] {
        let raw = list
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if raw.contains(where: { s in
            let lower = s.lowercased()
            return lower == "any" || lower == "*"
        }) {
            return []
        }

        // De-dup while preserving order.
        var seen = Set<String>()
        var out: [String] = []
        for s in raw {
            let lower = s.lowercased()
            let canon: String = {
                if lower == "localhost" { return "loopback" }
                if lower == "loopback" { return "loopback" }
                if lower == "private" { return "private" }
                return s
            }()
            let key = canon.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(canon)
        }
        return out
    }

    private func orderedCaps(_ list: [String]) -> [String] {
        let clean = list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if clean.isEmpty { return [] }

        let order = Self.capSpecs.map { $0.key }
        let known = clean.filter { order.contains($0) }
        let unknown = clean.filter { !order.contains($0) }

        var out: [String] = []
        for k in order {
            if known.contains(k) { out.append(k) }
        }
        // Keep unknowns stable-ish.
        out.append(contentsOf: unknown.sorted())

        // De-dup while preserving out order.
        var seen = Set<String>()
        var uniq: [String] = []
        for c in out {
            if seen.contains(c) { continue }
            seen.insert(c)
            uniq.append(c)
        }
        return uniq
    }

    private func pairedTerminalLocalModelOverrideCard(_ model: ModelCatalogEntry) -> some View {
        let effective = localModelEffectiveLoadProfile(for: model)
        let source = localModelEffectiveContextSource(for: model)
        let validationMessages = localModelValidationMessages(for: model)
        let draftText = localModelContextOverrideDraftText(for: model.id)
        let hasHiddenFields = localModelHasHiddenNonContextFields(model.id)
        let advancedSummary = localModelAdvancedSummary(for: effective)
        let sourceLabel = localModelContextSourceLabel(source)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name.isEmpty ? model.id : model.name)
                        .font(.caption.weight(.semibold))
                    Text(model.id)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Text(model.backend.uppercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.contextLimit(model.maxContextLength))
                Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.defaultContext(model.defaultLoadProfile.contextLength))
                Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.effectiveContext(effective.contextLength))
                Spacer()
                Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.sourceSummary(sourceLabel))
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField(
                    HubUIStrings.Settings.GRPC.EditDeviceSheet.contextOverridePlaceholder,
                    text: localModelContextOverrideBinding(for: model.id)
                )
                .textFieldStyle(.roundedBorder)

                Button(HubUIStrings.Settings.GRPC.EditDeviceSheet.restoreHubDefault) {
                    localModelContextOverrideTextById[model.id] = ""
                }
                .font(.caption)

                Button(HubUIStrings.Settings.GRPC.EditDeviceSheet.useMaximum) {
                    localModelContextOverrideTextById[model.id] = String(model.maxContextLength)
                }
                .font(.caption)
            }

            DisclosureGroup(
                isExpanded: localModelAdvancedExpandedBinding(for: model.id),
                content: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            TextField(HubUIStrings.Settings.GRPC.EditDeviceSheet.ttlSecondsPlaceholder, text: localModelTTLBinding(for: model.id))
                                .textFieldStyle(.roundedBorder)
                            TextField(HubUIStrings.Settings.GRPC.EditDeviceSheet.parallelismPlaceholder, text: localModelParallelBinding(for: model.id))
                                .textFieldStyle(.roundedBorder)
                        }

                        TextField(HubUIStrings.Settings.GRPC.EditDeviceSheet.identifierPlaceholder, text: localModelIdentifierBinding(for: model.id))
                            .textFieldStyle(.roundedBorder)

                        TextField(
                            HubUIStrings.Settings.GRPC.EditDeviceSheet.visionImageMaxDimensionPlaceholder,
                            text: localModelVisionImageMaxDimensionBinding(for: model.id)
                        )
                        .textFieldStyle(.roundedBorder)

                        HStack(spacing: 10) {
                            Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.effective)
                            Text(advancedSummary)
                            Spacer()
                            Button(HubUIStrings.Settings.GRPC.EditDeviceSheet.clearAdvanced) {
                                localModelTTLTextById[model.id] = ""
                                localModelParallelTextById[model.id] = ""
                                localModelIdentifierById[model.id] = ""
                                localModelVisionImageMaxDimensionTextById[model.id] = ""
                            }
                            .font(.caption)
                        }
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)

                        Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.advancedOptionsHint)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                },
                label: {
                    HStack(spacing: 8) {
                        Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.advancedOptions)
                            .font(.caption.weight(.semibold))
                        Text(advancedSummary)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            )

            TextField(HubUIStrings.Settings.GRPC.EditDeviceSheet.notePlaceholder, text: localModelNoteBinding(for: model.id))
                .textFieldStyle(.roundedBorder)

            if !validationMessages.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(validationMessages, id: \.self) { message in
                        Text(message)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            } else if source == "runtime_clamped", let requested = Int(draftText) {
                Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.runtimeClampedWarning(
                    requested: requested,
                    effective: effective.contextLength
                ))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else {
                Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.finalResolutionHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if hasHiddenFields {
                Text(HubUIStrings.Settings.GRPC.EditDeviceSheet.hiddenMachineFieldsHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func localModelContextOverrideBinding(for modelId: String) -> Binding<String> {
        Binding(
            get: { localModelContextOverrideDraftText(for: modelId) },
            set: { localModelContextOverrideTextById[modelId] = $0 }
        )
    }

    private func localModelTTLBinding(for modelId: String) -> Binding<String> {
        Binding(
            get: { localModelTTLDraftText(for: modelId) },
            set: { localModelTTLTextById[modelId] = $0 }
        )
    }

    private func localModelParallelBinding(for modelId: String) -> Binding<String> {
        Binding(
            get: { localModelParallelDraftText(for: modelId) },
            set: { localModelParallelTextById[modelId] = $0 }
        )
    }

    private func localModelIdentifierBinding(for modelId: String) -> Binding<String> {
        Binding(
            get: { localModelIdentifierDraftText(for: modelId) },
            set: { localModelIdentifierById[modelId] = $0 }
        )
    }

    private func localModelVisionImageMaxDimensionBinding(for modelId: String) -> Binding<String> {
        Binding(
            get: { localModelVisionImageMaxDimensionDraftText(for: modelId) },
            set: { localModelVisionImageMaxDimensionTextById[modelId] = $0 }
        )
    }

    private func localModelAdvancedExpandedBinding(for modelId: String) -> Binding<Bool> {
        Binding(
            get: { localModelAdvancedExpandedById[modelId] ?? false },
            set: { localModelAdvancedExpandedById[modelId] = $0 }
        )
    }

    private func localModelNoteBinding(for modelId: String) -> Binding<String> {
        Binding(
            get: { localModelNoteById[modelId] ?? "" },
            set: { localModelNoteById[modelId] = $0 }
        )
    }

    private func localModelContextOverrideDraftText(for modelId: String) -> String {
        localModelContextOverrideTextById[modelId] ?? ""
    }

    private func localModelTTLDraftText(for modelId: String) -> String {
        localModelTTLTextById[modelId] ?? ""
    }

    private func localModelParallelDraftText(for modelId: String) -> String {
        localModelParallelTextById[modelId] ?? ""
    }

    private func localModelIdentifierDraftText(for modelId: String) -> String {
        localModelIdentifierById[modelId] ?? ""
    }

    private func localModelVisionImageMaxDimensionDraftText(for modelId: String) -> String {
        localModelVisionImageMaxDimensionTextById[modelId] ?? ""
    }

    private func localModelContextValidationError(for model: ModelCatalogEntry) -> String? {
        let trimmed = localModelContextOverrideDraftText(for: model.id)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Int(trimmed) else {
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.contextLengthMustBeInteger
        }
        if value < 512 {
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.contextLengthMinimum(512)
        }
        if value > model.maxContextLength {
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.contextLengthMaximum(model.maxContextLength)
        }
        return nil
    }

    private func localModelValidationMessages(for model: ModelCatalogEntry) -> [String] {
        var messages: [String] = []
        if let contextError = localModelContextValidationError(for: model) {
            messages.append(contextError)
        }
        if let ttlError = localModelPositiveIntegerValidationError(
            localModelTTLDraftText(for: model.id),
            field: HubUIStrings.Settings.GRPC.EditDeviceSheet.ttlField,
            minimum: 1
        ) {
            messages.append(ttlError)
        }
        if let parallelError = localModelPositiveIntegerValidationError(
            localModelParallelDraftText(for: model.id),
            field: HubUIStrings.Settings.GRPC.EditDeviceSheet.parallelismField,
            minimum: 1
        ) {
            messages.append(parallelError)
        }
        if let imageDimensionError = localModelPositiveIntegerValidationError(
            localModelVisionImageMaxDimensionDraftText(for: model.id),
            field: HubUIStrings.Settings.GRPC.EditDeviceSheet.visionImageMaxDimensionField,
            minimum: 32,
            maximum: 16_384
        ) {
            messages.append(imageDimensionError)
        }
        return messages
    }

    private func localModelPositiveIntegerValidationError(
        _ rawText: String,
        field: String,
        minimum: Int,
        maximum: Int? = nil
    ) -> String? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Int(trimmed) else {
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.integerFieldError(field: field)
        }
        if value < minimum {
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.minimumFieldError(field: field, minimum: minimum)
        }
        if let maximum, value > maximum {
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.maximumFieldError(field: field, maximum: maximum)
        }
        return nil
    }

    private func localModelDraftOverrideProfile(for model: ModelCatalogEntry) -> LocalModelLoadProfileOverride? {
        var draft = existingLocalModelProfiles[model.id]?.overrideProfile ?? LocalModelLoadProfileOverride()
        let trimmed = localModelContextOverrideDraftText(for: model.id)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            draft.contextLength = nil
        } else if let value = Int(trimmed) {
            draft.contextLength = value
        }

        let ttlTrimmed = localModelTTLDraftText(for: model.id)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if ttlTrimmed.isEmpty {
            draft.ttl = nil
        } else if let value = Int(ttlTrimmed), value > 0 {
            draft.ttl = value
        }

        let parallelTrimmed = localModelParallelDraftText(for: model.id)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if parallelTrimmed.isEmpty {
            draft.parallel = nil
        } else if let value = Int(parallelTrimmed), value > 0 {
            draft.parallel = value
        }

        let identifierTrimmed = localModelIdentifierDraftText(for: model.id)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        draft.identifier = identifierTrimmed.isEmpty ? nil : identifierTrimmed

        let imageMaxDimensionTrimmed = localModelVisionImageMaxDimensionDraftText(for: model.id)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if imageMaxDimensionTrimmed.isEmpty {
            draft.vision = nil
        } else if let value = Int(imageMaxDimensionTrimmed), value >= 32, value <= 16_384 {
            draft.vision = LocalModelVisionLoadProfile(imageMaxDimension: value)
        }

        return draft.isEmpty ? nil : draft
    }

    private func localModelEffectiveLoadProfile(for model: ModelCatalogEntry) -> LocalModelLoadProfile {
        model.defaultLoadProfile.merged(
            with: localModelDraftOverrideProfile(for: model),
            maxContextLength: model.maxContextLength
        )
    }

    private func localModelEffectiveContextSource(for model: ModelCatalogEntry) -> String {
        let trimmed = localModelContextOverrideDraftText(for: model.id)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "hub_default" }
        guard let requested = Int(trimmed) else { return "device_override" }
        let effective = localModelEffectiveLoadProfile(for: model)
        if effective.contextLength != requested {
            return "runtime_clamped"
        }
        return "device_override"
    }

    private func localModelHasHiddenNonContextFields(_ modelId: String) -> Bool {
        guard let overrideProfile = existingLocalModelProfiles[modelId]?.overrideProfile else { return false }
        return overrideProfile.gpuOffloadRatio != nil
            || overrideProfile.ropeFrequencyBase != nil
            || overrideProfile.ropeFrequencyScale != nil
            || overrideProfile.evalBatchSize != nil
    }

    private func localModelAdvancedSummary(for profile: LocalModelLoadProfile) -> String {
        var parts: [String] = []
        if let ttl = profile.ttl {
            parts.append(HubUIStrings.Settings.GRPC.EditDeviceSheet.advancedTTL(ttl))
        }
        if let parallel = profile.parallel {
            parts.append(HubUIStrings.Settings.GRPC.EditDeviceSheet.advancedParallel(parallel))
        }
        if let identifier = profile.identifier,
           !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(HubUIStrings.Settings.GRPC.EditDeviceSheet.advancedIdentifier(identifier))
        }
        if let imageMaxDimension = profile.vision?.imageMaxDimension {
            parts.append(HubUIStrings.Settings.GRPC.EditDeviceSheet.advancedImage(imageMaxDimension))
        }
        return parts.isEmpty
            ? HubUIStrings.Settings.GRPC.EditDeviceSheet.inheritDefaults
            : HubUIStrings.Settings.GRPC.EditDeviceSheet.advancedSummary(parts)
    }

    private func persistLocalModelProfiles() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        for model in localModels {
            var overrideProfile = existingLocalModelProfiles[model.id]?.overrideProfile ?? LocalModelLoadProfileOverride()
            let contextText = localModelContextOverrideDraftText(for: model.id)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            overrideProfile.contextLength = Int(contextText)
            let ttlText = localModelTTLDraftText(for: model.id)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            overrideProfile.ttl = Int(ttlText)
            let parallelText = localModelParallelDraftText(for: model.id)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            overrideProfile.parallel = Int(parallelText)
            let identifierText = localModelIdentifierDraftText(for: model.id)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            overrideProfile.identifier = identifierText.isEmpty ? nil : identifierText
            let imageDimensionText = localModelVisionImageMaxDimensionDraftText(for: model.id)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = Int(imageDimensionText), value >= 32, value <= 16_384 {
                overrideProfile.vision = LocalModelVisionLoadProfile(imageMaxDimension: value)
            } else {
                overrideProfile.vision = nil
            }

            let note = (localModelNoteById[model.id] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let existing = existingLocalModelProfiles[model.id]
            let normalizedProfile = overrideProfile.isEmpty ? nil : overrideProfile

            if let normalizedProfile {
                let next = HubPairedTerminalLocalModelProfile(
                    deviceId: client.deviceId,
                    modelId: model.id,
                    overrideProfile: normalizedProfile,
                    updatedAtMs: nowMs,
                    updatedBy: "hub_settings",
                    note: note
                )
                let needsUpsert = existing?.overrideProfile != normalizedProfile
                    || existing?.note != note
                    || existing == nil
                if needsUpsert {
                    onUpsertLocalModelProfile(next)
                }
            } else if existing != nil {
                onRemoveLocalModelProfile(client.deviceId, model.id)
            }
        }
    }

    private func parseList(_ text: String) -> [String] {
        let raw = text
            .split(whereSeparator: { ch in
                ch == "," || ch == "\n" || ch == ";" || ch == "\t"
            })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if raw.isEmpty { return [] }

        // De-dup while preserving order.
        var seen = Set<String>()
        var out: [String] = []
        for s in raw {
            if seen.contains(s) { continue }
            seen.insert(s)
            out.append(s)
        }
        return out
    }
}

extension SettingsSheetView {
    private func badgeDetailText(dedupeKey: String, isEnabled: Bool) -> String {
        // Dock badge integrations require Accessibility.
        if isEnabled, (dedupeKey == "mail_unread" || dedupeKey == "messages_unread" || dedupeKey == "slack_updates"),
           !DockBadgeReader.ensureAccessibilityTrusted(prompt: false) {
            return HubUIStrings.Notifications.Unread.accessibilityRequired
        }
        if let n = store.notifications.first(where: { $0.dedupeKey == dedupeKey }) {
            let c = firstInt(in: n.title) ?? firstInt(in: n.body) ?? 0
            if c > 0 {
                return HubUIStrings.Notifications.Unread.count(c)
            }
            return HubUIStrings.Notifications.Unread.noUnread
        }
        return HubUIStrings.Notifications.Unread.noUnread
    }

    private func firstInt(in s: String) -> Int? {
        var digits = ""
        for ch in s {
            if ch.isNumber {
                digits.append(ch)
            } else if !digits.isEmpty {
                break
            }
        }
        return digits.isEmpty ? nil : Int(digits)
    }
}

private struct IntegrationToggleRow: View {
    let systemImage: String
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}
