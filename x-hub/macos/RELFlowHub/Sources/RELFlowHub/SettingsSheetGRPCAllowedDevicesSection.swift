import SwiftUI
import AppKit
import RELFlowHubCore

extension SettingsSheetView {
@ViewBuilder
    func grpcAllowedDevicesBlock() -> some View {
        Text(HubUIStrings.Settings.GRPC.allowedDevicesTitle)
            .font(.caption.weight(.semibold))

        HStack(spacing: 10) {
            Button(HubUIStrings.Settings.GRPC.add) { showAddGRPCClient = true }
            Button(HubUIStrings.Settings.GRPC.openDeviceList) { grpc.openClientsConfig() }
            Spacer()
        }
        .font(.caption)

        let ipDenied = grpcDeniedAttempts.attempts
            .filter { a in
                a.reason.trimmingCharacters(in: .whitespacesAndNewlines) == "source_ip_not_allowed"
                    && !a.peerIp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .prefix(6)
        if !ipDenied.isEmpty {
            Divider()
            Text(HubUIStrings.Settings.GRPC.DeviceList.deniedSourceIPTitle)
                .font(.caption.weight(.semibold))
            ForEach(ipDenied) { a in
                VStack(alignment: .leading, spacing: 4) {
                    let title = !a.clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? a.clientName
                        : (
                            a.deviceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? HubUIStrings.Settings.GRPC.DeviceList.unknownDevice
                                : a.deviceId
                        )
                    let lastText = a.lastSeenAtMs > 0 ? formatMs(a.lastSeenAtMs) : HubUIStrings.Settings.GRPC.DeviceList.unknownSeen

                    Text(title)
                        .font(.caption.weight(.semibold))

                    Text(HubUIStrings.Settings.GRPC.DeviceList.deniedLine(ip: a.peerIp, count: a.count, lastText: lastText))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    if !a.expectedAllowedCidrs.isEmpty {
                        Text(HubUIStrings.Settings.GRPC.DeviceList.allowedSources(a.expectedAllowedCidrs))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }

                    let did = a.deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !did.isEmpty, grpc.allowedClients.contains(where: { $0.deviceId == did }) {
                        HStack(spacing: 10) {
                            Button(HubUIStrings.Settings.GRPC.DeviceList.addIPToDevice) {
                                grpc.addAllowedCidr(deviceId: did, value: a.peerIp)
                            }
                            .font(.caption)
                            Button(HubUIStrings.Settings.GRPC.DeviceList.edit) {
                                if let c = grpc.allowedClients.first(where: { $0.deviceId == did }) {
                                    presentGRPCClientEditor(c)
                                }
                            }
                            .font(.caption)
                            Spacer()
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }

        if grpc.allowedClients.isEmpty {
            Text(HubUIStrings.Settings.GRPC.DeviceList.noPairedDevices)
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            let statusById: [String: GRPCDeviceStatusEntry] = Dictionary(
                uniqueKeysWithValues: grpcDevicesStatus.devices.map { ($0.deviceId, $0) }
            )
            let summary = grpcClientListSummary(grpc.allowedClients, statusById: statusById)
            let visibleClients = grpcVisibleClients(grpc.allowedClients, statusById: statusById)

            grpcAllowedClientsHeader(statusById: statusById, summary: summary, visibleClients: visibleClients)

            grpcAllowedClientsRows(visibleClients, statusById: statusById)
        }
    }

    @ViewBuilder
    func grpcAllowedClientsHeader(
        statusById: [String: GRPCDeviceStatusEntry],
        summary: GRPCClientListSummary,
        visibleClients: [HubGRPCClientEntry]
    ) -> some View {
        grpcPairingRepairCard(statusById: statusById)

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                grpcClientNetworkPill(HubUIStrings.Settings.GRPC.DeviceList.totalDevices(summary.total), color: .secondary)
                grpcClientNetworkPill(HubUIStrings.Settings.GRPC.DeviceList.enabledDevices(summary.enabled), color: .green)
                grpcClientNetworkPill(HubUIStrings.Settings.GRPC.DeviceList.connectedDevices(summary.connected), color: .accentColor)
                grpcClientNetworkPill(HubUIStrings.Settings.GRPC.DeviceList.staleDevices(summary.stale), color: .orange)
                grpcClientNetworkPill(HubUIStrings.Settings.GRPC.DeviceList.networkEnabledDevices(summary.networkEnabled), color: .blue)
                grpcClientNetworkPill(HubUIStrings.Settings.GRPC.DeviceList.paidEnabledDevices(summary.paidEnabled), color: .purple)
                grpcClientNetworkPill(HubUIStrings.Settings.GRPC.DeviceList.webEnabledDevices(summary.webEnabled), color: .teal)
                grpcClientNetworkPill(HubUIStrings.Settings.GRPC.DeviceList.blockedDevices(summary.blocked), color: .red)
            }
            .padding(.vertical, 2)
        }

        HStack(spacing: 10) {
            Text(HubUIStrings.Settings.GRPC.DeviceList.filter)
                .font(.caption.weight(.semibold))

            Picker(HubUIStrings.Settings.GRPC.DeviceList.filter, selection: $grpcClientListFilter) {
                ForEach(GRPCClientListFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .font(.caption)

            Spacer()

            Text(HubUIStrings.Settings.GRPC.DeviceList.visibleDevices(visibleClients.count, summary.total))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        Text(HubUIStrings.Settings.GRPC.DeviceList.sortHint)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    func grpcAllowedClientsRows(
        _ visibleClients: [HubGRPCClientEntry],
        statusById: [String: GRPCDeviceStatusEntry]
    ) -> some View {
        ForEach(visibleClients) { client in
            grpcAllowedClientRow(client, status: statusById[client.deviceId])
        }
    }

    @ViewBuilder
    func grpcAllowedClientRow(_ client: HubGRPCClientEntry, status: GRPCDeviceStatusEntry?) -> some View {
        let network = grpcClientNetworkAccessSnapshot(client)
        let detailBinding = expansionBinding(client.deviceId, in: $expandedGRPCClientDetailIDs)

        VStack(alignment: .leading, spacing: 6) {
            grpcAllowedClientRowHeader(client)
            grpcAllowedClientRowPills(client, network: network, status: status)
            grpcAllowedClientRowActions(client, network: network)
            DisclosureGroup(isExpanded: detailBinding) {
                VStack(alignment: .leading, spacing: 6) {
                    grpcAllowedClientRowMetadata(client)
                    grpcAllowedClientRowStatus(status)
                }
                .padding(.top, 6)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("诊断 / 用量 / 安全明细")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(grpcClientDetailSummary(status))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.035))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    func grpcAllowedClientRowHeader(_ client: HubGRPCClientEntry) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(grpcClientDisplayName(client))
                    .font(.caption.weight(.semibold))
                Text(client.deviceId)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(HubUIStrings.Settings.GRPC.DeviceList.edit) {
                presentGRPCClientEditor(client)
            }
            .font(.caption)

            Button(HubUIStrings.Settings.GRPC.DeviceList.copyVars) {
                grpc.copyConnectVars(for: client)
            }
            .font(.caption)

            Button(client.enabled ? HubUIStrings.Settings.GRPC.DeviceList.disable : HubUIStrings.Settings.GRPC.DeviceList.enable) {
                grpc.setClientEnabled(deviceId: client.deviceId, enabled: !client.enabled)
            }
            .font(.caption)

            if client.deviceId != "terminal_device" {
                Button(HubUIStrings.Settings.GRPC.DeviceList.delete) {
                    deletingGRPCClient = client
                }
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    func grpcAllowedClientRowPills(
        _ client: HubGRPCClientEntry,
        network: GRPCClientNetworkAccessSnapshot,
        status: GRPCDeviceStatusEntry?
    ) -> some View {
        HStack(spacing: 6) {
            grpcClientNetworkPill(
                HubUIStrings.Settings.GRPC.DeviceList.deviceEnabledPill(client.enabled),
                color: client.enabled ? .green : .secondary
            )
            grpcClientNetworkPill(
                HubUIStrings.Settings.GRPC.DeviceList.networkEnabledPill(network.canNetwork),
                color: network.canNetwork ? .green : .secondary
            )
            grpcClientNetworkPill(
                HubUIStrings.Settings.GRPC.DeviceList.paidEnabledPill(network.paidEnabled),
                color: network.paidEnabled ? .orange : .secondary
            )
            grpcClientNetworkPill(
                network.webEnabled ? HubUIStrings.Settings.GRPC.DeviceList.webOn : HubUIStrings.Settings.GRPC.DeviceList.webOff,
                color: network.webEnabled ? .blue : .secondary
            )
            grpcClientNetworkPill(
                network.usesPolicyProfile ? HubUIStrings.Settings.GRPC.DeviceList.policyNew : HubUIStrings.Settings.GRPC.DeviceList.policyLegacy,
                color: network.usesPolicyProfile ? .purple : .secondary
            )

            if let status {
                grpcClientNetworkPill(
                    grpcClientPresencePillTitle(status),
                    color: grpcClientPresencePillColor(status)
                )
                grpcClientNetworkPill(
                    grpcClientExecutionPillTitle(status),
                    color: grpcClientExecutionPillColor(status)
                )
            }

            Spacer()
        }
    }

    @ViewBuilder
    func grpcAllowedClientRowActions(
        _ client: HubGRPCClientEntry,
        network: GRPCClientNetworkAccessSnapshot
    ) -> some View {
        HStack(spacing: 10) {
            Button(HubUIStrings.Settings.GRPC.DeviceList.toggleWeb(network.webEnabled)) {
                grpcSetWebFetchEnabled(client, enabled: !network.webEnabled)
            }
            .font(.caption)

            Button(HubUIStrings.Settings.GRPC.DeviceList.adoptCurrentSuggestedRange) {
                grpc.adoptCurrentLANDefaults(deviceId: client.deviceId)
                if editingGRPCClient?.deviceId == client.deviceId,
                   let refreshed = grpc.allowedClients.first(where: { $0.deviceId == client.deviceId }) {
                    presentGRPCClientEditor(
                        refreshed,
                        capabilityFocusKey: editingGRPCClientFocusCapabilityKey
                    )
                }
            }
            .font(.caption)

            if network.policyGrantsNetwork {
                Button(HubUIStrings.Settings.GRPC.DeviceList.cutOffNetwork) {
                    grpcCutOffNetworkAccess(client)
                }
                .font(.caption)
            }

            Text(grpcClientQuickActionHint(network))
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    @ViewBuilder
    func grpcAllowedClientRowMetadata(_ client: HubGRPCClientEntry) -> some View {
        Text(grpcClientSecuritySummary(client))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .textSelection(.enabled)

        Text(grpcClientPaidPolicySummary(client))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .textSelection(.enabled)
    }

    @ViewBuilder
    func grpcAllowedClientRowStatus(_ status: GRPCDeviceStatusEntry?) -> some View {
        if let status {
            Text(grpcClientStatusSummary(status))
                .font(.caption2)
                .foregroundStyle(grpcClientPresencePillColor(status))
                .lineLimit(2)
                .textSelection(.enabled)

            Text(grpcClientPolicyUsageSummary(status))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)

            Text(grpcClientActualExecutionSummary(status))
                .font(.caption2)
                .foregroundStyle(grpcClientExecutionPillColor(status))
                .lineLimit(3)
                .textSelection(.enabled)

            if let activity = status.lastActivity {
                Text(grpcClientLastActivitySummary(activity))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            if grpcClientPresenceCountsAsStale(status) {
                Text(HubUIStrings.Settings.GRPC.DeviceList.staleRepairHint)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !status.lastBlockedReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !status.lastDenyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(grpcClientLastBlockedSummary(status))
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            if let series = status.tokenSeries5m1h, !series.points.isEmpty {
                TokenSparkline(
                    points: series.points,
                    strokeColor: grpcClientPresenceState(status) == .connected ? .accentColor : Color.gray.opacity(0.7),
                    lineWidth: 1.5
                )
                .frame(height: 18)
            }

            if status.dailyTokenCap > 0 {
                ProgressView(value: Double(status.dailyTokenUsed), total: Double(status.dailyTokenCap))
                    .progressViewStyle(.linear)
                Text(
                    HubUIStrings.Settings.GRPC.DeviceList.dailyTokenUsage(
                        day: status.quotaDay,
                        used: Int(status.dailyTokenUsed),
                        cap: Int(status.dailyTokenCap),
                        remaining: Int(max(0, status.remainingDailyTokenBudget))
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else if status.dailyTokenUsed > 0 {
                Text(HubUIStrings.Settings.GRPC.DeviceList.dailyTokenUsageUnlimited(day: status.quotaDay, used: Int(status.dailyTokenUsed)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !status.modelBreakdown.isEmpty {
                DisclosureGroup(HubUIStrings.Settings.GRPC.DeviceList.usageDetails) {
                    ForEach(Array(status.modelBreakdown.prefix(3))) { row in
                        Text(grpcClientModelBreakdownSummary(row))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .font(.caption2)
            }
        } else {
            Text(HubUIStrings.Settings.GRPC.DeviceList.statusUnknownNoEvents)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
