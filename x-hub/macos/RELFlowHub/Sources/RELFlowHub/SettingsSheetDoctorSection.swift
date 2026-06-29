import SwiftUI
import AppKit

extension SettingsSheetView {
    var floatingModeSection: some View {
        Section(HubUIStrings.Settings.FloatingMode.sectionTitle) {
            Picker(HubUIStrings.Settings.FloatingMode.mode, selection: $store.floatingMode) {
                ForEach(FloatingMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if store.floatingMode == .orb {
                Picker(HubUIStrings.Settings.FloatingMode.particleDensity, selection: $store.orbParticleDensity) {
                    ForEach(OrbParticleDensity.allCases, id: \.self) { density in
                        Text(density.title).tag(density)
                    }
                }
                .pickerStyle(.segmented)

                Picker(HubUIStrings.Settings.FloatingMode.particleSize, selection: $store.orbParticleSize) {
                    ForEach(OrbParticleSize.allCases, id: \.self) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)
            }

            Text(HubUIStrings.Settings.FloatingMode.displayHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    var legacyCountsOnlyIntegrationsEnabled: Bool {
        store.integrationMailEnabled || store.integrationMessagesEnabled || store.integrationSlackEnabled
    }

    var doctorSection: some View {
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
                Text(rustLocalMLAuthorityMode ? "Rust 本地模型执行" : HubUIStrings.Settings.Doctor.localRuntime)
                Spacer()
                Text(rustLocalMLAuthorityMode ? runtimeHeartbeatText : store.aiRuntimeStatusText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !runtimeDoctorDetailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(runtimeDoctorDetailText)
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
                if rustLocalMLAuthorityMode {
                    Button(HubUIStrings.Settings.Advanced.Runtime.refreshRustReadiness) {
                        refreshRustLocalMLExecutionReadiness(force: true)
                        refreshRustHubRuntimeSnapshot(force: true)
                    }
                }
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
        .id(doctorSectionAnchorID)
    }

    func disableLegacyCountsOnlyIntegrations() {
        store.integrationMailEnabled = false
        store.integrationMessagesEnabled = false
        store.integrationSlackEnabled = false
    }
}
