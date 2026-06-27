import SwiftUI
import AppKit

extension SettingsSheetView {
    var operatorChannelRuntimeSnapshotText: String {
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

    var operatorChannelReadinessSection: some View {
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

    func operatorChannelReadinessCard(
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

    func operatorChannelReadinessBadge(_ readiness: HubOperatorChannelOnboardingDeliveryReadiness?) -> some View {
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

    func providerReadiness(for provider: String) -> HubOperatorChannelOnboardingDeliveryReadiness? {
        operatorChannelProviderReadiness.first { row in
            row.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == provider
        }
    }

    func providerRuntimeStatus(for provider: String) -> HubOperatorChannelProviderRuntimeStatus? {
        operatorChannelProviderRuntimeStatus.first { row in
            row.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == provider
        }
    }

    func operatorChannelRuntimeStatusSummary(_ row: HubOperatorChannelProviderRuntimeStatus) -> String {
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

    func pendingOnboardingTicketCount(for provider: String) -> Int {
        let normalized = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.pendingOperatorChannelOnboardingTickets.filter { ticket in
            ticket.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized && ticket.isOpen
        }.count
    }

    func copyOperatorChannelSetupPack(
        _ guide: HubOperatorChannelProviderSetupGuide,
        flow: HubOperatorChannelFirstUseFlow
    ) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(guide.setupPackText(flow: flow), forType: .string)
        operatorChannelProviderReadinessActionText = HubUIStrings.Settings.OperatorChannels.copiedSetupPack(guide.title)
    }
}
