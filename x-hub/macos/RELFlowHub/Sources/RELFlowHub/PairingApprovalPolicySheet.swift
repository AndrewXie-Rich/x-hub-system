import SwiftUI

struct PairingApprovalPolicySheet: View {
    let req: HubPairingRequest
    let onApprove: (HubPairingApprovalDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedPreset: HubPairingApprovalPreset
    @State private var deviceName: String
    @State private var paidModelSelectionMode: HubPaidModelSelectionMode
    @State private var allowedPaidModelsText: String
    @State private var defaultWebFetchEnabled: Bool
    @State private var dailyTokenLimitText: String

    init(req: HubPairingRequest, onApprove: @escaping (HubPairingApprovalDraft) -> Void) {
        self.req = req
        self.onApprove = onApprove
        let suggested = HubPairingApprovalDraft.recommended(for: req)
        _selectedPreset = State(initialValue: .recommendedMinimal)
        _deviceName = State(initialValue: suggested.deviceName)
        _paidModelSelectionMode = State(initialValue: suggested.paidModelSelectionMode)
        _allowedPaidModelsText = State(initialValue: "")
        _defaultWebFetchEnabled = State(initialValue: suggested.defaultWebFetchEnabled)
        _dailyTokenLimitText = State(initialValue: String(suggested.dailyTokenLimit))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(HubUIStrings.MainPanel.PairingApproval.title)
                            .font(.headline)
                        Text("先看推荐接入，再决定是否需要在首配阶段放开更多能力。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(HubUIStrings.MainPanel.PairingApproval.cancel) {
                        dismiss()
                    }
                    Button(approveButtonTitle) {
                        onApprove(currentDraft)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canApprove)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(HubUIStrings.MainPanel.PairingApproval.appLine(req.appId))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("批准前仍会先触发 Touch ID / Face ID / 本机密码验证，验证通过后才真正发放首配 token 和 profile。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !req.claimedDeviceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(HubUIStrings.MainPanel.PairingApproval.claimedDeviceLine(req.claimedDeviceId))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if !requestedScopesText.isEmpty {
                        Text(HubUIStrings.MainPanel.PairingApproval.requestedScopesLine(requestedScopesText))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                approvalSummaryCard
                presetSection
                advancedSection
            }
            .padding(16)
        }
        .frame(width: 560, height: 760)
        .onChange(of: deviceName) { _ in
            syncPresetFromCurrentDraft()
        }
        .onChange(of: paidModelSelectionMode) { _ in
            syncPresetFromCurrentDraft()
        }
        .onChange(of: allowedPaidModelsText) { _ in
            syncPresetFromCurrentDraft()
        }
        .onChange(of: defaultWebFetchEnabled) { _ in
            syncPresetFromCurrentDraft()
        }
        .onChange(of: dailyTokenLimitText) { _ in
            syncPresetFromCurrentDraft()
        }
    }

    private var approvalSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(HubUIStrings.MainPanel.PairingApproval.summaryTitle)
                .font(.callout.weight(.semibold))

            HStack(spacing: 8) {
                summaryPill(HubUIStrings.MainPanel.PairingApproval.baseAccessIncluded, tint: .blue)
                summaryPill(currentDraft.paidModelSummaryText, tint: currentDraft.paidModelSelectionMode == .off ? .secondary : .orange)
                summaryPill(currentDraft.webFetchSummaryText, tint: currentDraft.defaultWebFetchEnabled ? .teal : .secondary)
                summaryPill(currentDraft.dailyBudgetSummaryText, tint: .purple)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(HubUIStrings.MainPanel.PairingApproval.recommendationTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(selectedPreset.recommendationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(HubUIStrings.MainPanel.PairingApproval.nextStepTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(selectedPreset.nextStepText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.blue.opacity(0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.blue.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(HubUIStrings.MainPanel.PairingApproval.presetTitle)
                    .font(.callout.weight(.semibold))
                Spacer()
                if selectedPreset == .custom {
                    Button(HubUIStrings.MainPanel.PairingApproval.restoreRecommended) {
                        applyPreset(.recommendedMinimal)
                    }
                    .font(.caption)
                }
            }

            ForEach(HubPairingApprovalPreset.visibleCases, id: \.rawValue) { preset in
                Button {
                    applyPreset(preset)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(preset.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if let badge = preset.badgeText {
                                    Text(badge)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.green)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.green.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                            }
                            Text(preset.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: selectedPreset == preset ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedPreset == preset ? Color.accentColor : .secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(selectedPreset == preset ? Color.accentColor.opacity(0.10) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(selectedPreset == preset ? Color.accentColor.opacity(0.28) : Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(HubUIStrings.MainPanel.PairingApproval.advancedTitle)
                .font(.callout.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text(HubUIStrings.MainPanel.PairingApproval.deviceNameTitle)
                    .font(.callout.weight(.semibold))
                TextField(HubUIStrings.MainPanel.PairingApproval.deviceNamePlaceholder, text: $deviceName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(HubUIStrings.MainPanel.PairingApproval.paidModelAccessTitle)
                    .font(.callout.weight(.semibold))
                Picker(HubUIStrings.MainPanel.PairingApproval.paidModelAccessPicker, selection: $paidModelSelectionMode) {
                    ForEach(HubPaidModelSelectionMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if paidModelSelectionMode == .customSelectedModels {
                    TextField(HubUIStrings.MainPanel.PairingApproval.customPaidModelsPlaceholder, text: $allowedPaidModelsText)
                        .textFieldStyle(.roundedBorder)
                    if normalizedAllowedPaidModels.isEmpty {
                        Text(HubUIStrings.MainPanel.PairingApproval.customPaidModelsError)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                } else if paidModelSelectionMode == .allPaidModels {
                    Text(HubUIStrings.MainPanel.PairingApproval.allPaidModelsHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(HubUIStrings.MainPanel.PairingApproval.noPaidModelsHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle(HubUIStrings.MainPanel.PairingApproval.defaultAllowWebFetch, isOn: $defaultWebFetchEnabled)
                Text(
                    defaultWebFetchEnabled
                    ? HubUIStrings.MainPanel.PairingApproval.webFetchOnHint
                    : HubUIStrings.MainPanel.PairingApproval.webFetchOffHint
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(HubUIStrings.MainPanel.PairingApproval.dailyTokenLimitTitle)
                    .font(.callout.weight(.semibold))
                TextField(HubUIStrings.MainPanel.PairingApproval.dailyTokenLimitPlaceholder, text: $dailyTokenLimitText)
                    .textFieldStyle(.roundedBorder)
                if parsedDailyTokenLimit == nil {
                    Text(HubUIStrings.MainPanel.PairingApproval.dailyTokenLimitError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                } else {
                    Text(HubUIStrings.MainPanel.PairingApproval.saveHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(HubUIStrings.MainPanel.PairingApproval.saveHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func summaryPill(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.10))
            .clipShape(Capsule())
    }

    private var normalizedDeviceName: String {
        HubGRPCClientEntry.normalizedStrings([deviceName]).first
        ?? HubUIStrings.MainPanel.PairingApproval.defaultDeviceName
    }

    private var normalizedAllowedPaidModels: [String] {
        allowedPaidModelsText
            .split(whereSeparator: { ch in
                ch == "," || ch == "\n" || ch == ";" || ch == "\t"
            })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { partial, item in
                if !partial.contains(item) {
                    partial.append(item)
                }
            }
    }

    private var parsedDailyTokenLimit: Int? {
        let trimmed = dailyTokenLimitText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    private var canApprove: Bool {
        guard !normalizedDeviceName.isEmpty else { return false }
        guard parsedDailyTokenLimit != nil else { return false }
        if paidModelSelectionMode == .customSelectedModels {
            return !normalizedAllowedPaidModels.isEmpty
        }
        return true
    }

    private var currentDraft: HubPairingApprovalDraft {
        HubPairingApprovalDraft(
            deviceName: normalizedDeviceName,
            paidModelSelectionMode: paidModelSelectionMode,
            allowedPaidModels: normalizedAllowedPaidModels,
            defaultWebFetchEnabled: defaultWebFetchEnabled,
            dailyTokenLimit: parsedDailyTokenLimit ?? HubTrustProfileDefaults.dailyTokenLimit
        )
    }

    private var approveButtonTitle: String {
        selectedPreset == .recommendedMinimal
            ? HubUIStrings.MainPanel.PairingRequest.approveRecommended
            : HubUIStrings.MainPanel.PairingApproval.approveCurrent
    }

    private var requestedScopesText: String {
        req.requestedScopes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private func applyPreset(_ preset: HubPairingApprovalPreset) {
        let draft = HubPairingApprovalDraft.preset(preset, for: req)
        selectedPreset = preset
        deviceName = draft.deviceName
        paidModelSelectionMode = draft.paidModelSelectionMode
        allowedPaidModelsText = draft.normalizedAllowedPaidModels.joined(separator: ", ")
        defaultWebFetchEnabled = draft.defaultWebFetchEnabled
        dailyTokenLimitText = String(draft.dailyTokenLimit)
    }

    private func syncPresetFromCurrentDraft() {
        selectedPreset = currentDraft.matchedPreset
    }
}
