import SwiftUI
import AppKit
import RELFlowHubCore

extension SettingsSheetView {
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
}
