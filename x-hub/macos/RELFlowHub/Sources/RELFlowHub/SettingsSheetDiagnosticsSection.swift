import SwiftUI
import AppKit
import RELFlowHubCore

extension SettingsSheetView {
    var diagnosticsSection: some View {
        Section(HubUIStrings.Settings.Diagnostics.sectionTitle) {
            let snap = hubLaunchStatus
            let primary = HubLaunchStatusStorage.url()
            let fallback = URL(fileURLWithPath: "/tmp/RELFlowHub", isDirectory: true).appendingPathComponent(HubLaunchStatusStorage.fileName)
            let histPrimary = HubLaunchHistoryStorage.url()
            let histFallback = URL(fileURLWithPath: "/tmp/RELFlowHub", isDirectory: true).appendingPathComponent(HubLaunchHistoryStorage.fileName)
            let rootCauseText = renderRootCauseText(snap?.rootCause)
            let blocked = snap?.degraded.blockedCapabilities ?? []

            diagnosticsLaunchBriefingCard(
                snapshot: snap,
                rootCauseText: rootCauseText,
                blockedCapabilities: blocked
            )
            .id(diagnosticsLaunchSectionAnchorID)

            DisclosureGroup("启动证据") {
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
            }

            DisclosureGroup(HubUIStrings.Settings.Diagnostics.providersDisclosure) {
                if rustLocalMLAuthorityMode {
                    Text(runtimeDoctorDetailText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(rustLocalMLReadinessClipboardText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else if !store.aiRuntimeDoctorSummaryText.isEmpty {
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
                    if rustLocalMLAuthorityMode {
                        Button(HubUIStrings.Settings.Advanced.Runtime.refreshRustReadiness) {
                            refreshRustLocalMLExecutionReadiness(force: true)
                            refreshRustHubRuntimeSnapshot(force: true)
                        }
                    }
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
}
