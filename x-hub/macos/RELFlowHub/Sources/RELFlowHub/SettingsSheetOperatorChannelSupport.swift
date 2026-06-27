import Foundation
import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    var operatorChannelOnboardingSection: some View {
        Section(HubUIStrings.Settings.OperatorChannels.onboardingSectionTitle) {
            OperatorChannelsOnboardingView()
                .environmentObject(store)
        }
    }

    var calendarSection: some View {
        Section(HubUIStrings.Settings.Calendar.sectionTitle) {
            LabeledContent(HubUIStrings.Settings.Calendar.status, value: store.calendarStatus)

            Text(HubUIStrings.Settings.Calendar.localAccessHint)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(HubUIStrings.Settings.Calendar.supervisorHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    func reloadOperatorChannelProviderReadiness(forceMessage: Bool = false) async {
        if operatorChannelProviderReadinessInFlight { return }
        operatorChannelProviderReadinessInFlight = true
        defer { operatorChannelProviderReadinessInFlight = false }
        do {
            async let readinessRows = OperatorChannelsOnboardingHTTPClient.listProviderReadiness(
                adminToken: grpc.localAdminToken(),
                grpcPort: grpc.port
            )
            async let runtimeRows = OperatorChannelsOnboardingHTTPClient.listProviderRuntimeStatus(
                adminToken: grpc.localAdminToken(),
                grpcPort: grpc.port
            )
            let (rows, runtimeStatusRows) = try await (readinessRows, runtimeRows)
            operatorChannelProviderReadiness = rows
            operatorChannelProviderRuntimeStatus = runtimeStatusRows
            operatorChannelProviderReadinessError = ""
            persistOperatorChannelDoctorReport(
                readinessRows: rows,
                runtimeRows: runtimeStatusRows,
                sourceStatus: "ok",
                fetchErrors: []
            )
            if forceMessage {
                operatorChannelProviderReadinessActionText = HubUIStrings.Settings.OperatorChannels.refreshedStatus
            }
        } catch {
            let errorDescription = (error as NSError).localizedDescription
            operatorChannelProviderReadiness = []
            operatorChannelProviderRuntimeStatus = []
            operatorChannelProviderReadinessError = errorDescription
            persistOperatorChannelDoctorReport(
                readinessRows: [],
                runtimeRows: [],
                sourceStatus: "unavailable",
                fetchErrors: [errorDescription]
            )
        }
    }

    private func persistOperatorChannelDoctorReport(
        readinessRows: [HubOperatorChannelOnboardingDeliveryReadiness],
        runtimeRows: [HubOperatorChannelProviderRuntimeStatus],
        sourceStatus: String,
        fetchErrors: [String]
    ) {
        let grpcPort = grpc.port
        let adminBaseURL = grpcPort > 0
            ? "http://127.0.0.1:\(OperatorChannelsOnboardingHTTPClient.pairingPort(grpcPort: grpcPort))"
            : ""
        Task.detached(priority: .utility) {
            XHubDoctorOutputStore.writeHubChannelOnboardingReadinessReport(
                readinessRows: readinessRows,
                runtimeRows: runtimeRows,
                sourceStatus: sourceStatus,
                fetchErrors: fetchErrors,
                adminBaseURL: adminBaseURL,
                surface: .hubUI
            )
        }
    }

    @MainActor
    func restartOperatorChannelRuntimeAndRefresh() async {
        if diagnosticsActionIsRunning {
            operatorChannelProviderReadinessActionText = HubUIStrings.Settings.OperatorChannels.restartInProgress
            return
        }

        operatorChannelProviderReadinessActionText = HubUIStrings.Settings.OperatorChannels.restartingComponents
        await restartComponentsForDiagnosticsAsync()
        try? await Task.sleep(nanoseconds: 900_000_000)
        hubLaunchStatus = HubLaunchStatusStorage.load()
        await reloadOperatorChannelProviderReadiness(forceMessage: false)

        if operatorChannelProviderReadinessError.isEmpty {
            operatorChannelProviderReadinessActionText = HubUIStrings.Settings.OperatorChannels.restartedAndUpdated
        } else {
            operatorChannelProviderReadinessActionText = HubUIStrings.Settings.OperatorChannels.restartCompletedRefreshFailed
        }
    }


}
