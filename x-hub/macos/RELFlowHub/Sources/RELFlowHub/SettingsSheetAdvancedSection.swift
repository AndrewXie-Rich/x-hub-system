import SwiftUI

extension SettingsSheetView {
    var advancedSection: some View {
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
}
