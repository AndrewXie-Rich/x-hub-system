import SwiftUI
import AppKit
import RELFlowHubCore

extension Notification.Name {
    static let relflowhubOpenMain = Notification.Name("relflowhub.openMain")
}

struct FloatingRootView: View {
    @EnvironmentObject var store: HubStore
    @State private var grpcDevicesStatus: GRPCDevicesStatusSnapshot = .empty()
    @State private var grpcDevicesStatusRefreshInFlight: Bool = false
    @StateObject private var clientStore = ClientStore.shared

    var body: some View {
        Group {
            if store.suppressFloatingContent {
                Color.clear
            } else {
                switch store.floatingMode {
                case .hidden:
                    Color.clear
                case .orb:
                    OrbFloatingView(
                        alert: store.topAlert(),
                        devices: grpcDevicesStatus.devices,
                        pairedSurfaceClients: pairedSurfaceClients,
                        snapshotUpdatedAtMs: grpcDevicesStatus.updatedAtMs,
                        particleDensity: store.orbParticleDensity,
                        particleSize: store.orbParticleSize
                    )
                        .onTapGesture {
                            // Orb should not react to hover; only a single click action is supported.
                            NotificationCenter.default.post(name: .relflowhubOpenMain, object: nil)
                        }
                case .card:
                    CardFloatingView(summary: SummaryStorage.load())
                }
            }
        }
        .onAppear {
            refreshGRPCDevicesStatus()
        }
        .onReceive(Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()) { _ in
            refreshGRPCDevicesStatus()
        }
    }

    private var pairedSurfaceClients: [HubClientHeartbeat] {
        clientStore.liveClients().filter { client in
            let appID = client.appId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !appID.isEmpty else { return false }
            if appID.hasPrefix("sys_") { return false }
            if appID == "hub" || appID == "relflowhub" { return false }
            return true
        }
    }

    private func refreshGRPCDevicesStatus() {
        guard !grpcDevicesStatusRefreshInFlight else { return }
        grpcDevicesStatusRefreshInFlight = true

        Task.detached(priority: .utility) {
            let snapshot = GRPCDevicesStatusStorage.load()
            await MainActor.run {
                grpcDevicesStatus = snapshot
                grpcDevicesStatusRefreshInFlight = false
            }
        }
    }
}
