import Foundation
import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
func grpcPairingRepairDeniedAttempts(limit: Int) -> [GRPCDeniedAttemptEntry] {
        grpcDeniedAttempts.attempts
            .filter { attempt in
                grpcDeniedAttemptLooksLikePairingRepair(attempt.reason)
                    || grpcDeniedAttemptLooksLikePairingRepair(attempt.message)
            }
            .sorted { lhs, rhs in
                if lhs.lastSeenAtMs != rhs.lastSeenAtMs {
                    return lhs.lastSeenAtMs > rhs.lastSeenAtMs
                }
                return lhs.count > rhs.count
            }
            .prefix(limit)
            .map { $0 }
    }

    func grpcPairingRepairCandidateClients(
        _ clients: [HubGRPCClientEntry],
        statusById: [String: GRPCDeviceStatusEntry]
    ) -> [HubGRPCClientEntry] {
        clients.filter { client in
            client.deviceId != "terminal_device" && grpcClientPresenceCountsAsStale(statusById[client.deviceId])
        }
    }

    @ViewBuilder
    func grpcPairingRepairCard(statusById: [String: GRPCDeviceStatusEntry]) -> some View {
        let staleClients = grpcPairingRepairCandidateClients(grpc.allowedClients, statusById: statusById)
        let pairingRepairDeniedAttempts = grpcPairingRepairDeniedAttempts(limit: 3)
        let singleRepairCandidate = staleClients.count == 1 ? staleClients.first : nil

        if !staleClients.isEmpty || !pairingRepairDeniedAttempts.isEmpty {
            quickFixCard(
                title: HubUIStrings.Settings.GRPC.pairingRepairTitle,
                summary: grpcPairingRepairSummary(
                    staleClients: staleClients,
                    deniedAttempts: pairingRepairDeniedAttempts
                ),
                steps: [
                    HubUIStrings.Settings.GRPC.pairingRepairStepClearXT,
                    HubUIStrings.Settings.GRPC.pairingRepairStepDeleteHub,
                    HubUIStrings.Settings.GRPC.pairingRepairStepReconnect,
                ]
            ) {
                if !staleClients.isEmpty {
                    Button(HubUIStrings.Settings.GRPC.filterStaleOnly) {
                        grpcClientListFilter = .stale
                    }
                }
                if let singleRepairCandidate {
                    Button(HubUIStrings.Settings.GRPC.deleteOldDevice) {
                        deletingGRPCClient = singleRepairCandidate
                    }
                    .foregroundStyle(.red)
                }
                Button(HubUIStrings.Settings.GRPC.openDeviceListFile) {
                    grpc.openClientsConfig()
                }
            }
        }
    }

    func grpcDeniedAttemptLooksLikePairingRepair(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return false }
        return text.contains("unauthenticated")
            || text.contains("mtls_client_certificate_required")
            || text.contains("certificate_required")
            || text.contains("pairing_health_failed")
            || text.contains("bootstrap_refresh_failed")
            || text.contains("missing_pairing_secret")
            || text.contains("discover_failed_using_cached_profile")
    }

    func grpcPairingRepairSummary(
        staleClients: [HubGRPCClientEntry],
        deniedAttempts: [GRPCDeniedAttemptEntry]
    ) -> String {
        var parts: [String] = []
        if !staleClients.isEmpty {
            let names = staleClients.prefix(2).map(grpcClientDisplayName)
            if staleClients.count == 1, let name = names.first {
                parts.append(HubUIStrings.Settings.GRPC.pairingRepairFoundOne(name))
            } else {
                let preview = names.joined(separator: "、")
                parts.append(HubUIStrings.Settings.GRPC.pairingRepairFoundMany(count: staleClients.count, preview: preview))
            }
        }
        if !deniedAttempts.isEmpty {
            let names = deniedAttempts.prefix(2).map(grpcDeniedAttemptDisplayName)
            parts.append(HubUIStrings.Settings.GRPC.pairingRepairDenied(names.joined(separator: "、")))
        }
        if parts.isEmpty {
            return HubUIStrings.Settings.GRPC.pairingRepairDefaultSummary
        }
        parts.append(HubUIStrings.Settings.GRPC.pairingRepairClosing)
        return parts.joined(separator: " ")
    }

    func grpcClientDisplayName(_ client: HubGRPCClientEntry) -> String {
        let name = client.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? client.deviceId : name
    }

    func grpcDeniedAttemptDisplayName(_ attempt: GRPCDeniedAttemptEntry) -> String {
        let name = attempt.clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let device = attempt.deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return name
        }
        if !device.isEmpty {
            return device
        }
        return HubUIStrings.Settings.GRPC.DeviceList.unknownDevice
    }
}
