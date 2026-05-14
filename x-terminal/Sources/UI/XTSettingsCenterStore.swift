import Combine
import Foundation

struct XTSettingsCenterSnapshot: Equatable {
    var settings: XTerminalSettings
    var modelsState: ModelStateSnapshot
    var hubBaseDir: URL?
    var hubConnected: Bool
    var hubRemoteConnected: Bool
    var hubRemoteLinking: Bool
    var hubRemoteRoute: HubRemoteRoute
    var hubRemoteSummary: String
    var hubRemotePaidAccessSnapshot: HubRemotePaidAccessSnapshot?
    var hubRemoteLog: String
    var hubSetupDiscoverState: HubSetupStepState
    var hubSetupBootstrapState: HubSetupStepState
    var hubSetupConnectState: HubSetupStepState
    var hubSetupFailureCode: String
    var hubPortAutoDetectRunning: Bool
    var hubPortAutoDetectMessage: String
    var hubDiscoveredCandidates: [HubDiscoveredHubCandidateSummary]
    var hubPairingPort: Int
    var hubGrpcPort: Int
    var hubInternetHost: String
    var hubInviteToken: String
    var hubInviteAlias: String
    var hubInviteInstanceID: String
    var hubAxhubctlPath: String
    var serverRunning: Bool
    var localServerEnabled: Bool
    var localServerPort: Int
    var localServerLastError: String
    var unifiedDoctorReport: XTUnifiedDoctorReport
    var runtimeSnapshot: UIFailClosedRuntimeSnapshot
    var skillsCompatibilitySnapshot: AXSkillsDoctorSnapshot
    var officialSkillsRecheckStatusLine: String
    var historicalProjectBoundaryRepairStatusLine: String
    var supervisorVoiceSmokeRunning: Bool
    var supervisorVoiceSmokeStatusLine: String
    var supervisorVoiceSmokeDetailLine: String
    var supervisorVoiceSmokeLastPassed: Bool?
    var canOpenSupervisorVoiceSmokeReport: Bool
    var selectedProjectId: String?
    var selectedProjectName: String?
    var selectedProjectContext: AXProjectContext?
    var selectedProjectConfig: AXProjectConfig?
    var routeRepairLogLines: [String]
    var routeRepairLogDigest: AXRouteRepairLogDigest
    var currentProjectRouteWatchItem: AXRouteRepairProjectWatchItem?

    static let empty = XTSettingsCenterSnapshot(
        settings: .default(),
        modelsState: .empty(),
        hubBaseDir: nil,
        hubConnected: false,
        hubRemoteConnected: false,
        hubRemoteLinking: false,
        hubRemoteRoute: .none,
        hubRemoteSummary: "",
        hubRemotePaidAccessSnapshot: nil,
        hubRemoteLog: "",
        hubSetupDiscoverState: .idle,
        hubSetupBootstrapState: .idle,
        hubSetupConnectState: .idle,
        hubSetupFailureCode: "",
        hubPortAutoDetectRunning: false,
        hubPortAutoDetectMessage: "",
        hubDiscoveredCandidates: [],
        hubPairingPort: 50052,
        hubGrpcPort: 50051,
        hubInternetHost: "",
        hubInviteToken: "",
        hubInviteAlias: "",
        hubInviteInstanceID: "",
        hubAxhubctlPath: "",
        serverRunning: false,
        localServerEnabled: false,
        localServerPort: 8080,
        localServerLastError: "",
        unifiedDoctorReport: .empty,
        runtimeSnapshot: .empty,
        skillsCompatibilitySnapshot: .empty,
        officialSkillsRecheckStatusLine: "",
        historicalProjectBoundaryRepairStatusLine: "",
        supervisorVoiceSmokeRunning: false,
        supervisorVoiceSmokeStatusLine: "",
        supervisorVoiceSmokeDetailLine: "",
        supervisorVoiceSmokeLastPassed: nil,
        canOpenSupervisorVoiceSmokeReport: false,
        selectedProjectId: nil,
        selectedProjectName: nil,
        selectedProjectContext: nil,
        selectedProjectConfig: nil,
        routeRepairLogLines: [],
        routeRepairLogDigest: .empty,
        currentProjectRouteWatchItem: nil
    )

    var hubInteractive: Bool {
        hubConnected || hubRemoteConnected
    }
}

@MainActor
final class XTSettingsCenterStore: ObservableObject {
    @Published private(set) var snapshot: XTSettingsCenterSnapshot

    init(snapshot: XTSettingsCenterSnapshot = .empty) {
        self.snapshot = snapshot
    }

    func update(_ nextSnapshot: XTSettingsCenterSnapshot) {
        guard snapshot != nextSnapshot else { return }
        snapshot = nextSnapshot
    }
}
