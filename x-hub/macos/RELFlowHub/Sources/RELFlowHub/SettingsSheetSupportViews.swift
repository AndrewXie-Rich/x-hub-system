import SwiftUI
import AppKit
import RELFlowHubCore

struct RemoteQuotaBudgetEditorSheet: View {
    let target: RemoteQuotaBudgetEditorTarget
    let onSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftLimit: Int

    init(target: RemoteQuotaBudgetEditorTarget, onSave: @escaping (Int) -> Void) {
        self.target = target
        self.onSave = onSave
        _draftLimit = State(initialValue: max(1, target.currentDailyTokenLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("精确设置日预算")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text(target.title)
                    .font(.callout.weight(.semibold))
                if !target.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(target.subtitle)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            HStack(spacing: 8) {
                metricCard(
                    title: "当前额度",
                    value: Self.tokenFormatter.string(from: NSNumber(value: target.currentDailyTokenLimit)) ?? "\(target.currentDailyTokenLimit)",
                    tint: .purple
                )
                metricCard(
                    title: "今日已用",
                    value: Self.tokenFormatter.string(from: NSNumber(value: target.todayUsed)) ?? "\(target.todayUsed)",
                    tint: .teal
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("目标 daily budget")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField(
                    "每日 token 额度",
                    value: $draftLimit,
                    formatter: Self.tokenFormatter
                )
                .textFieldStyle(.roundedBorder)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 72), spacing: 8),
                        GridItem(.flexible(minimum: 72), spacing: 8),
                        GridItem(.flexible(minimum: 72), spacing: 8),
                        GridItem(.flexible(minimum: 72), spacing: 8),
                    ],
                    spacing: 8
                ) {
                    presetButton(100_000, title: "100k")
                    presetButton(200_000, title: "200k")
                    presetButton(500_000, title: "500k")
                    presetButton(1_000_000, title: "1M")
                }
            }

            Text("保存后会立刻刷新 Hub 台账；XT 和普通 terminal 共用这套 daily budget 语义。")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 10) {
                Button("取消") {
                    dismiss()
                }

                Spacer()

                Button("保存额度") {
                    onSave(max(1, draftLimit))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draftLimit < 1 || draftLimit == target.currentDailyTokenLimit)
            }
        }
        .padding(16)
        .frame(width: 420, height: 300)
    }

    private static let tokenFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    @ViewBuilder
    private func metricCard(
        title: String,
        value: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func presetButton(_ value: Int, title: String) -> some View {
        Button(title) {
            draftLimit = value
        }
        .buttonStyle(.borderless)
        .font(.caption.weight(.semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background((draftLimit == value ? Color.indigo : Color.gray).opacity(draftLimit == value ? 0.14 : 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct RemoteModelKeyGroup: Identifiable {
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

struct EditRemoteModelGroupDisplayNameSheet: View {
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

struct AddGRPCClientSheet: View {
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

struct IntegrationToggleRow: View {
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
