import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    var setupCenterSection: some View {
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

    var firstRunFastPathSection: some View {
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

    var quickTroubleshootSection: some View {
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

    private var preferredClientForRepair: HubGRPCClientEntry? {
        if let denied = grpcDeniedAttempts.attempts.first,
           let client = grpc.allowedClients.first(where: { $0.deviceId == denied.deviceId }) {
            return client
        }
        return grpc.allowedClients.first
    }

    @ViewBuilder
    private func firstRunStepRow<Actions: View>(
        index: Int,
        title: String,
        summary: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
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
    func quickFixCard<Actions: View>(
        title: String,
        summary: String,
        steps: [String],
        @ViewBuilder actions: () -> Actions
    ) -> some View {
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
}
