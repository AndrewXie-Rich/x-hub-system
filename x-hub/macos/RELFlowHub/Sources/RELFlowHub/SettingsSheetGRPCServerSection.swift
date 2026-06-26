import SwiftUI
import AppKit
import RELFlowHubCore

extension SettingsSheetView {
    var grpcServerSection: some View {
        Section(HubUIStrings.Settings.GRPC.sectionTitle) {
            grpcServerPrimaryBlock()
            grpcAdvancedSettingsBlock()
            grpcAllowedDevicesBlock()
            grpcRemoteAccessBlock()
        }
    }

    @ViewBuilder
    func grpcServerPrimaryBlock() -> some View {
        Toggle(HubUIStrings.Settings.GRPC.enableLAN, isOn: $grpc.autoStart)

        HStack {
            Text(HubUIStrings.Settings.GRPC.status)
            Spacer()
            Text(grpc.statusText)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }

        if !grpc.lastError.isEmpty {
            Text(grpc.lastError)
                .font(.caption2)
                .foregroundStyle(.red)
        }

        if !grpc.autoPortSwitchMessage.isEmpty {
            Text(grpc.autoPortSwitchMessage)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 6) {
            Text(HubUIStrings.Settings.GRPC.pairingInfoTitle)
                .font(.caption.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text(HubUIStrings.Settings.GRPC.externalAddress)
                        .foregroundStyle(.secondary)
                    Text(grpc.xtTerminalInternetHost ?? HubUIStrings.Settings.GRPC.noReachableHost)
                        .font(.caption.monospaced())
                        .foregroundStyle(grpc.xtTerminalInternetHost == nil ? .secondary : .primary)
                        .textSelection(.enabled)
                }
                GridRow {
                    Text(HubUIStrings.Settings.GRPC.pairingPort)
                        .foregroundStyle(.secondary)
                    Text(HubUIStrings.Settings.numericValue(grpc.xtTerminalPairingPort))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                GridRow {
                    Text(HubUIStrings.Settings.GRPC.grpcPort)
                        .foregroundStyle(.secondary)
                    Text(HubUIStrings.Settings.numericValue(grpc.port))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
            .font(.caption)

            Text(HubUIStrings.Settings.GRPC.setupHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        if !grpc.lanAddresses.isEmpty {
            Text(grpc.lanAddresses.joined(separator: "\n"))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }

        HStack(spacing: 10) {
            Button(HubUIStrings.Settings.GRPC.copyConnectionVars) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(grpc.connectionGuide, forType: .string)
            }
            Button(HubUIStrings.Settings.FirstRun.copyBootstrap) { grpc.copyBootstrapCommandToClipboard() }
            Button(HubUIStrings.Settings.FirstRun.addDevice) { showAddGRPCClient = true }
            Button(HubUIStrings.Settings.FirstRun.refresh) { grpc.refresh() }
            Spacer()
        }
        .font(.caption)

        if !grpc.connectionGuide.isEmpty {
            Text(grpc.connectionGuide)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    func grpcAdvancedSettingsBlock() -> some View {
        DisclosureGroup(HubUIStrings.Settings.GRPC.advancedSettings) {
            VStack(alignment: .leading, spacing: 6) {
                Text(HubUIStrings.Settings.GRPC.externalHostOverride)
                    .font(.caption.weight(.semibold))
                TextField(HubUIStrings.Settings.GRPC.externalHostPlaceholder, text: $grpc.internetHostOverride)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                Text(HubUIStrings.Settings.GRPC.externalHostHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text(HubUIStrings.Settings.GRPC.noDomainAccessTitle)
                        .font(.caption.weight(.semibold))
                    if let noDomainHost = noDomainPrivateRemoteHost {
                        Text(HubUIStrings.Settings.GRPC.noDomainAccessDetected(noDomainHost))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Button(isUsingNoDomainPrivateRemoteHost
                                   ? HubUIStrings.Settings.GRPC.noDomainPrivateHostApplied
                                   : HubUIStrings.Settings.GRPC.useNoDomainPrivateHost) {
                                if grpc.applyNoDomainPrivateRemoteHost(noDomainHost) {
                                    remoteRouteProbe.refresh(host: grpc.xtTerminalInternetHost, force: true)
                                }
                            }
                            .disabled(isUsingNoDomainPrivateRemoteHost)
                            Text(HubUIStrings.Settings.GRPC.noDomainAccessMTLSHint)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(noDomainPrivateRemoteHostSourceText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Button(HubUIStrings.Settings.FirstRun.refresh) {
                                refreshRustHubRemoteEntryCandidates(force: true)
                            }
                            .disabled(rustHubRemoteEntryRefreshing)
                        }
                    } else {
                        Text(HubUIStrings.Settings.GRPC.noDomainAccessMissing)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(HubUIStrings.Settings.GRPC.externalInviteTitle)
                    .font(.caption.weight(.semibold))
                Text(HubUIStrings.Settings.GRPC.externalHubAlias)
                    .font(.caption.weight(.semibold))
                TextField(HubUIStrings.Settings.GRPC.externalHubAliasPlaceholder, text: $grpc.externalHubAlias)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                Text(HubUIStrings.Settings.GRPC.externalHubAliasHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text(HubUIStrings.Settings.GRPC.externalInviteToken)
                            .foregroundStyle(.secondary)
                        Text(grpc.externalInviteTokenPreview.isEmpty
                             ? HubUIStrings.Settings.GRPC.inviteTokenNotIssued
                             : grpc.externalInviteTokenPreview)
                            .font(.caption.monospaced())
                            .foregroundStyle(grpc.externalInviteTokenPreview.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                    }
                }
                .font(.caption)

                HStack(spacing: 10) {
                    Button(HubUIStrings.Settings.GRPC.copyLocalPairingLink) {
                        _ = grpc.copyLocalPairingInviteLinkToClipboard()
                    }
                    .disabled(!grpc.canProvisionLocalPairingInvite)
                    Button(HubUIStrings.Settings.GRPC.copySecureRemoteSetupPack) {
                        _ = grpc.copySecureRemoteSetupPackToClipboard()
                    }
                    .disabled(!grpc.canProvisionSecureRemoteSetupPack)
                    Button(grpc.hasExternalInviteToken
                           ? HubUIStrings.Settings.GRPC.rotateInviteToken
                           : HubUIStrings.Settings.GRPC.issueInviteToken) {
                        grpc.rotateExternalInviteToken()
                    }
                    .disabled(!grpc.canProvisionExternalInvite)
                    Button(HubUIStrings.Settings.GRPC.copyInviteLink) {
                        _ = grpc.copyInviteLinkToClipboard()
                    }
                    .disabled(!grpc.canProvisionExternalInvite)
                    if grpc.hasExternalInviteToken {
                        Button(HubUIStrings.Settings.GRPC.clearInviteToken) {
                            grpc.clearExternalInviteToken()
                        }
                    }
                    Spacer()
                }
                .font(.caption)

                Text(HubUIStrings.Settings.GRPC.secureRemoteSetupPackHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(HubUIStrings.Settings.GRPC.localPairingLinkHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if !grpc.localPairingInviteLinkText.isEmpty {
                    Text(grpc.localPairingInviteLinkText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if !grpc.externalInviteLinkText.isEmpty {
                    Text(grpc.externalInviteLinkText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if let qrImage = grpc.externalInviteQRCodeImage {
                        VStack(alignment: .leading, spacing: 6) {
                            Image(nsImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 156, height: 156)
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                                )
                            Text(HubUIStrings.Settings.GRPC.inviteQRCodeHint)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text(grpc.externalInviteUnavailableReason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(HubUIStrings.Settings.GRPC.externalInviteTokenHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(HubUIStrings.Settings.GRPC.transportSecurity)
                    .font(.caption.weight(.semibold))
                Picker(HubUIStrings.Settings.GRPC.transportMode, selection: $grpc.tlsMode) {
                    Text(HubUIStrings.Settings.GRPC.insecure).tag("insecure")
                    Text(HubUIStrings.Settings.GRPC.tls).tag("tls")
                    Text(HubUIStrings.Settings.GRPC.mtls).tag("mtls")
                }
                .pickerStyle(.segmented)
                .font(.caption)

                Text(HubUIStrings.Settings.GRPC.transportHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Text(HubUIStrings.Settings.GRPC.port)
                Spacer()
                TextField(
                    "50051",
                    value: $grpc.port,
                    formatter: {
                        let f = NumberFormatter()
                        f.allowsFloats = false
                        f.minimum = 1
                        f.maximum = 65535
                        return f
                    }()
                )
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .frame(width: 120)
            }

            HStack(spacing: 10) {
                Button(HubUIStrings.Settings.GRPC.openLog) { grpc.openLog() }
                Button(HubUIStrings.Settings.GRPC.rotateDeviceToken) { grpc.regenerateClientToken() }
                Spacer()
            }
            .font(.caption)

            HStack(spacing: 10) {
                Button(HubUIStrings.Settings.FirstRun.openQuotaSettings) { grpc.openQuotaConfig() }
                Spacer()
            }
            .font(.caption)

            Text(HubUIStrings.Settings.GRPC.quotaFile(grpc.quotaConfigURL().path))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Divider()
        }
    }

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

    @ViewBuilder
    func grpcRemoteAccessBlock() -> some View {
        let remoteHealth = grpcRemoteAccessHealthSummary
        let routeSnapshot = remoteRouteProbe.snapshot

        Text(HubUIStrings.Settings.GRPC.deviceFile(grpc.clientsConfigURL().path))
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)

        Text(HubUIStrings.Settings.GRPC.enabledDeviceFileHint)
            .font(.caption2)
            .foregroundStyle(.secondary)

        Divider()

        VStack(alignment: .leading, spacing: 6) {
            Text(HubUIStrings.Settings.GRPC.RemoteHealth.title)
                .font(.caption.weight(.semibold))

            HStack(spacing: 6) {
                grpcClientNetworkPill(remoteHealth.badgeText, color: grpcRemoteHealthColor(remoteHealth.state))
                Spacer()
            }

            Text(remoteHealth.headline)
                .font(.caption.weight(.semibold))

            Text(remoteHealth.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(remoteHealth.accessScopeText)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(remoteHealth.operatorHintText)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let nextStep = remoteHealth.nextStep,
               !nextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(HubUIStrings.Settings.GRPC.RemoteHealth.nextStep(nextStep))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }

        Divider()

        VStack(alignment: .leading, spacing: 6) {
            Text(HubUIStrings.Settings.GRPC.RemoteRoute.title)
                .font(.caption.weight(.semibold))

            HStack(spacing: 6) {
                grpcClientNetworkPill(routeSnapshot.statusText, color: grpcRemoteRouteColor(routeSnapshot.state))
                Spacer()
            }

            Text(routeSnapshot.detailText)
                .font(.caption2)
                .foregroundStyle(routeSnapshot.state == .failed ? .red : .secondary)

            if !routeSnapshot.addresses.isEmpty {
                Text(routeSnapshot.addresses.joined(separator: "\n"))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }

        Divider()

        DisclosureGroup(HubUIStrings.Settings.GRPC.remoteAccessDisclosure) {
            Text(HubUIStrings.Settings.GRPC.remoteAccessMethodsIntro)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(HubUIStrings.Settings.GRPC.remoteAccessHint)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(HubUIStrings.Settings.GRPC.remoteHardeningHint)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(HubUIStrings.Settings.GRPC.remoteAdminHint)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button(HubUIStrings.Settings.GRPC.copyRemoteAccessGuide) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Self.remoteModeGuideText, forType: .string)
            }
            .font(.caption)

            Text(Self.remoteModeGuideText)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }

        Divider()

        Toggle(HubUIStrings.Settings.GRPC.ServingPower.keepSystemAwake, isOn: $servingPower.keepSystemAwakeWhileServing)

        Text(HubUIStrings.Settings.GRPC.ServingPower.keepSystemAwakeHint)
            .font(.caption2)
            .foregroundStyle(.secondary)

        Toggle(HubUIStrings.Settings.GRPC.ServingPower.keepDisplayAwake, isOn: $servingPower.keepDisplayAwakeWhileServing)
            .disabled(!servingPower.keepSystemAwakeWhileServing)

        Text(HubUIStrings.Settings.GRPC.ServingPower.keepDisplayAwakeHint)
            .font(.caption2)
            .foregroundStyle(servingPower.keepSystemAwakeWhileServing ? .secondary : .tertiary)

        HStack {
            Text(HubUIStrings.Settings.GRPC.ServingPower.status)
            Spacer()
            Text(servingPower.statusText)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.caption)

        Text(servingPower.detailText)
            .font(.caption2)
            .foregroundStyle(.secondary)

        if !servingPower.lastError.isEmpty {
            Text(servingPower.lastError)
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }
}
