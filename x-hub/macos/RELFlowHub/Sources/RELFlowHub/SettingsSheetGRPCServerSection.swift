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
        .id(grpcServerSectionAnchorID)
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
}
