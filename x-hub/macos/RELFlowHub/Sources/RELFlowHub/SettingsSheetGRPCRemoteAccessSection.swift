import SwiftUI
import AppKit
import RELFlowHubCore

extension SettingsSheetView {
@ViewBuilder
    func grpcRemoteAccessBlock() -> some View {
        let remoteHealth = grpcRemoteAccessHealthSummary
        let routeSnapshot = remoteRouteProbe.snapshot

        Text(HubUIStrings.Settings.GRPC.deviceFile(grpc.clientsConfigURL().path))
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .id(remoteAccessSectionAnchorID)

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
