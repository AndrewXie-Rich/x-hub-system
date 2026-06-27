import SwiftUI
import AppKit
import RELFlowHubCore

extension SettingsSheetView {
@ViewBuilder
    func diagnosticsLaunchBriefingCard(
        snapshot: HubLaunchStatusSnapshot?,
        rootCauseText: String,
        blockedCapabilities: [String]
    ) -> some View {
        let fixAction = recommendedFixAction(snapshot: snapshot)
        let primaryDisabled = fixNowIsRunning || diagnosticsActionIsRunning
        let retryDisabled = diagnosticsActionIsRunning || fixNowIsRunning
        let exportDisabled = diagnosticsBundleIsExporting

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(headerLaunchTint.opacity(0.14))
                    Image(systemName: hubStatusPresentation.systemName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(headerLaunchTint)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(HubUIStrings.Settings.Diagnostics.launchStatus)
                            .font(.subheadline.weight(.semibold))
                        Text(hubStatusBadgeText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(headerLaunchTint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(headerLaunchTint.opacity(0.10))
                            .clipShape(Capsule())
                    }

                    Text(hubStatusActionSummaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if hubStatusPresentation.needsActionHint {
                        Text(hubStatusPresentation.actionDetail)
                            .font(.caption2)
                            .foregroundStyle(headerLaunchTint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 132), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                diagnosticsBriefingMetricTile(
                    title: "更新时间",
                    value: diagnosticsBriefingUpdatedAtText(snapshot),
                    detail: "launch status",
                    tint: .blue
                )
                diagnosticsBriefingMetricTile(
                    title: "Root Cause",
                    value: diagnosticsBriefingRootCauseValue(rootCauseText),
                    detail: diagnosticsBriefingRootCauseDetail(rootCauseText),
                    tint: rootCauseText.isEmpty ? .green : .orange
                )
                diagnosticsBriefingMetricTile(
                    title: "Capability",
                    value: blockedCapabilities.isEmpty ? "无受阻" : "\(blockedCapabilities.count) 项",
                    detail: diagnosticsBriefingBlockedDetail(blockedCapabilities),
                    tint: blockedCapabilities.isEmpty ? .green : .red
                )
            }

            HStack(spacing: 10) {
                if fixAction != nil {
                    Button {
                        fixNow(snapshot: snapshot)
                    } label: {
                        settingsActionChipLabel(
                            title: fixNowIsRunning
                                ? HubUIStrings.Settings.Diagnostics.fixingInProgress
                                : HubUIStrings.Settings.Diagnostics.fixNow,
                            systemName: "wrench.and.screwdriver",
                            tint: headerLaunchTint,
                            disabled: primaryDisabled
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(primaryDisabled)
                } else {
                    Button {
                        retryLaunchDiagnosis()
                    } label: {
                        settingsActionChipLabel(
                            title: diagnosticsActionIsRunning
                                ? HubUIStrings.Settings.Diagnostics.actionInProgress
                                : HubUIStrings.Settings.Diagnostics.retryLaunch,
                            systemName: "arrow.clockwise",
                            tint: headerLaunchTint,
                            disabled: retryDisabled
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(retryDisabled)
                }

                Button {
                    exportDiagnosticsBundle()
                } label: {
                    settingsActionChipLabel(
                        title: diagnosticsBundleIsExporting
                            ? HubUIStrings.Settings.Diagnostics.exportInProgress
                            : HubUIStrings.Settings.Diagnostics.exportBundle,
                        systemName: "square.and.arrow.up",
                        tint: .secondary,
                        disabled: exportDisabled
                    )
                }
                .buttonStyle(.plain)
                .disabled(exportDisabled)

                Button {
                    copyIssueSnippetToClipboard(snapshot: snapshot)
                } label: {
                    settingsActionChipLabel(
                        title: HubUIStrings.Settings.Diagnostics.copyIssueSummary,
                        systemName: "doc.on.doc",
                        tint: .secondary
                    )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            headerLaunchTint.opacity(0.10),
                            Color.primary.opacity(0.025)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(headerLaunchTint.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func diagnosticsBriefingUpdatedAtText(_ snapshot: HubLaunchStatusSnapshot?) -> String {
        guard let snapshot, snapshot.updatedAtMs > 0 else { return "等待状态" }
        return formatEpochMs(snapshot.updatedAtMs)
    }

    private func diagnosticsBriefingRootCauseValue(_ rootCauseText: String) -> String {
        rootCauseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "无" : "有记录"
    }

    private func diagnosticsBriefingRootCauseDetail(_ rootCauseText: String) -> String {
        let cleaned = rootCauseText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "当前没有 root cause" }
        return diagnosticsBriefingSnippet(cleaned, limit: 54)
    }

    private func diagnosticsBriefingBlockedDetail(_ blockedCapabilities: [String]) -> String {
        guard !blockedCapabilities.isEmpty else { return "fail-closed 正常" }
        return diagnosticsBriefingSnippet(blockedCapabilities.prefix(3).joined(separator: " / "), limit: 54)
    }

    private func diagnosticsBriefingSnippet(_ raw: String, limit: Int) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(max(0, limit - 1))).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    @ViewBuilder
    private func diagnosticsBriefingMetricTile(
        title: String,
        value: String,
        detail: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
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
        .padding(10)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
