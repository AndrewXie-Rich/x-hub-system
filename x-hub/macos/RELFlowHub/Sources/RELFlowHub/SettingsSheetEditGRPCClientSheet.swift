import SwiftUI
import AppKit
import RELFlowHubCore

struct EditGRPCClientSheet: View {
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

    @State var name: String
    @State var userId: String
    @State var enabled: Bool
    @State var token: String
    @State var createdAtMs: Int64
    @State var allowAnySourceIP: Bool
    @State var allowedCidrs: [String]
    @State var allowedCidrsBackup: [String]
    @State var addCidrText: String
    @State var caps: Set<String>
    @State var certSha256: String
    @State var policyMode: HubGRPCClientPolicyMode
    @State var paidModelSelectionMode: HubPaidModelSelectionMode
    @State var allowedPaidModelsText: String
    @State var defaultWebFetchEnabled: Bool
    @State var dailyTokenLimitText: String
    @State var localTaskRoutingExpanded: Bool
    @State var localModelOverridesExpanded: Bool
    @State var routingSettingsDraft: RoutingSettings
    @State var localModelContextOverrideTextById: [String: String]
    @State var localModelTTLTextById: [String: String]
    @State var localModelParallelTextById: [String: String]
    @State var localModelIdentifierById: [String: String]
    @State var localModelVisionImageMaxDimensionTextById: [String: String]
    @State var localModelAdvancedExpandedById: [String: Bool]
    @State var localModelNoteById: [String: String]

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

}
