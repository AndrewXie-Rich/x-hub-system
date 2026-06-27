import SwiftUI

extension SettingsSheetView {
    var advancedSection: some View {
        Section(HubUIStrings.Settings.Advanced.sectionTitle) {
            DisclosureGroup(HubUIStrings.Settings.Advanced.Runtime.title) {
                if store.rustLocalMLExecutionAuthorityActiveForUI {
                    rustLocalMLExecutionAuthorityControls
                } else {
                    legacyAIRuntimeAdvancedControls
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

    @ViewBuilder
    var legacyAIRuntimeAdvancedControls: some View {
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

    @ViewBuilder
    var rustLocalMLExecutionAuthorityControls: some View {
        let snapshot = rustLocalMLExecutionReadinessSnapshot
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(HubUIStrings.Settings.Advanced.Runtime.rustAuthorityTitle, systemImage: "cpu")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(HubUIStrings.Settings.Advanced.Runtime.rustAuthorityBadge)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(rustLocalMLExecutionReadinessTint.opacity(0.14))
                    .clipShape(Capsule())
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                runtimeMonitorMetricCard(
                    title: HubUIStrings.Settings.Advanced.Runtime.rustReadinessStatus,
                    value: snapshot.statusText,
                    detail: snapshot.schemaVersion.isEmpty ? "schema unknown" : snapshot.schemaVersion
                )
                runtimeMonitorMetricCard(
                    title: HubUIStrings.Settings.Advanced.Runtime.rustAuthority,
                    value: snapshot.authorityText,
                    detail: snapshot.executionAuthorityInRust ? "execution_authority_in_rust=1" : "execution_authority_in_rust=0"
                )
                runtimeMonitorMetricCard(
                    title: HubUIStrings.Settings.Advanced.Runtime.rustEngine,
                    value: snapshot.engineText,
                    detail: snapshot.bridgeHTTP ? "bridge_http=1" : "bridge_http=0"
                )
                runtimeMonitorMetricCard(
                    title: HubUIStrings.Settings.Advanced.Runtime.rustCommandProxy,
                    value: snapshot.commandProxyText,
                    detail: snapshot.commandProxyReady ? "resident runtime reachable" : "direct launch/fallback"
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                rustLocalMLReadinessPathLine(
                    title: HubUIStrings.Settings.Advanced.Runtime.rustRuntimeBaseDir,
                    path: snapshot.runtimeBaseDir,
                    exists: snapshot.runtimeBaseDirExists
                )
                rustLocalMLReadinessPathLine(
                    title: HubUIStrings.Settings.Advanced.Runtime.rustScript,
                    path: snapshot.scriptPath,
                    exists: snapshot.scriptExists
                )
                rustLocalMLReadinessPathLine(
                    title: HubUIStrings.Settings.Advanced.Runtime.rustPython,
                    path: snapshot.pythonText,
                    exists: snapshot.pythonAvailable
                )
            }

            if !snapshot.blocker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label(snapshot.blocker, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }

            HStack(spacing: 10) {
                HubNeutralActionChipButton(
                    title: rustLocalMLExecutionReadinessRefreshing
                        ? "刷新中"
                        : HubUIStrings.Settings.Advanced.Runtime.refreshRustReadiness,
                    systemName: "arrow.clockwise",
                    width: nil,
                    help: nil
                ) {
                    refreshRustLocalMLExecutionReadiness(force: true)
                    refreshRustHubRuntimeSnapshot(force: true)
                }
                Button(HubUIStrings.Settings.Advanced.Runtime.openLog) { store.openAIRuntimeLog() }
                Spacer()
            }

            Text(rustLocalMLExecutionReadinessUpdatedText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(HubUIStrings.Settings.Advanced.Runtime.rustSwiftShellBoundary)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    func rustLocalMLReadinessPathLine(title: String, path: String, exists: Bool) -> some View {
        let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(exists ? "OK" : "Missing")
                    .font(.caption2.monospaced())
                    .foregroundStyle(exists ? Color.secondary : Color.orange)
                Text(normalized)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
        }
    }

    var rustLocalMLExecutionReadinessTint: Color {
        let snapshot = rustLocalMLExecutionReadinessSnapshot
        if snapshot.ready { return .green }
        if snapshot.enabled { return .orange }
        if snapshot.ok { return .secondary }
        return .red
    }

    var rustLocalMLExecutionReadinessUpdatedText: String {
        let updatedAt = rustLocalMLExecutionReadinessSnapshot.updatedAtMs
        if updatedAt <= 0 {
            return HubUIStrings.Settings.Advanced.Runtime.rustAwaitingRefresh
        }
        return "\(HubUIStrings.Settings.Advanced.Runtime.rustLastUpdated) \(formatEpochMs(updatedAt))"
    }
}
