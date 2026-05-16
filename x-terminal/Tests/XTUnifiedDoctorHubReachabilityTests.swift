import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct XTUnifiedDoctorHubReachabilityTests {
    @Test
    func localPathDoesNotMaskManualRemoteHubTimeout() {
        let report = XTUnifiedDoctorBuilder.build(
            input: makeHubReachabilityDoctorInput(
                localConnected: true,
                remoteConnected: false,
                internetHost: "192.168.10.101",
                failureCode: "grpc_unavailable"
            )
        )

        let section = report.section(.hubReachability)
        #expect(section?.state == .diagnosticRequired)
        #expect(section?.headline == "本机 Hub 可达，但手填远端 Hub 当前不可达")
        #expect(section?.summary.contains("本机文件通道") == true)
        #expect(section?.detailLines.contains("active_local_path=true") == true)
        #expect(section?.detailLines.contains("remote_target_requested=true") == true)
        #expect(report.currentFailureIssue == .hubUnreachable)
        #expect(report.overallSummary.contains("Hub 可达性") == true)
        #expect(report.readyForFirstTask == false)
    }

    @Test
    func localPathStaysReadyWhenNoRemoteFailureIsActive() {
        let report = XTUnifiedDoctorBuilder.build(
            input: makeHubReachabilityDoctorInput(
                localConnected: true,
                remoteConnected: false,
                internetHost: "192.168.10.101",
                failureCode: ""
            )
        )

        let section = report.section(.hubReachability)
        #expect(section?.state == .ready)
        #expect(section?.headline == "Hub 已通过本机直连可达")
        #expect(report.currentFailureIssue == nil)
    }

    @Test
    func attachesHubContractProjectionToReachabilitySection() {
        let input = makeHubReachabilityDoctorInput(
            localConnected: true,
            remoteConnected: false,
            internetHost: "hub.example.com",
            failureCode: ""
        )
        input.hubContractProjection = sampleReadyHubContractProjectionForTests()

        let report = XTUnifiedDoctorBuilder.build(input: input)

        let section = report.section(.hubReachability)
        #expect(section?.state == .ready)
        #expect(section?.hubContractProjection?.contractReady == true)
        #expect(section?.detailLines.contains("hub_contract_schema_version=xhub.rust_hub.xt_contract.v1") == true)
        #expect(section?.detailLines.contains("hub_contract_memory_canonical_writer=hub_only") == true)
        #expect(section?.detailLines.contains("hub_contract_skills_lease_required=true") == true)
        #expect(report.consumedContracts.contains(HubContractSnapshot.currentSchemaVersion))
    }

    @Test
    func firstHubContractFetchFailureDoesNotMaskReachableHub() {
        let input = makeHubReachabilityDoctorInput(
            localConnected: true,
            remoteConnected: false,
            internetHost: "hub.example.com",
            failureCode: ""
        )
        input.hubContractProjection = .fetchFailure(
            errorCode: "network_error",
            errorMessage: "connection refused",
            observedAt: Date(timeIntervalSince1970: 1_741_300_001)
        )

        let report = XTUnifiedDoctorBuilder.build(input: input)

        let section = report.section(.hubReachability)
        #expect(section?.state == .ready)
        #expect(section?.hubContractProjection?.contractReady == false)
        #expect(section?.detailLines.contains("hub_contract_fetch_error_code=network_error") == true)
        #expect(report.consumedContracts.contains(HubContractSnapshot.currentSchemaVersion) == false)
    }
}

private func makeHubReachabilityDoctorInput(
    localConnected: Bool,
    remoteConnected: Bool,
    internetHost: String,
    failureCode: String
) -> XTUnifiedDoctorInput {
    let model = HubModel(
        id: "hub.model.local",
        name: "hub.model.local",
        backend: "mlx",
        quant: "4bit",
        contextLength: 8192,
        paramsB: 1.5,
        roles: ["chat"],
        state: .loaded,
        memoryBytes: 1_024,
        tokensPerSec: 32,
        modelPath: "/models/hub.model.local",
        note: nil
    )

    return XTUnifiedDoctorInput(
        generatedAt: Date(timeIntervalSince1970: 1_741_300_000),
        localConnected: localConnected,
        remoteConnected: remoteConnected,
        remoteRoute: remoteConnected ? .lan : .none,
        linking: false,
        pairingPort: 50053,
        grpcPort: 50052,
        internetHost: internetHost,
        configuredModelIDs: ["gpt-5.4", model.id],
        totalModelRoles: AXRole.allCases.count,
        failureCode: failureCode,
        runtime: .empty,
        runtimeStatus: AIRuntimeStatus(
            pid: 42,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: true,
            runtimeVersion: "test-runtime",
            importError: nil,
            activeMemoryBytes: nil,
            peakMemoryBytes: nil,
            loadedModelCount: 1
        ),
        modelsState: ModelStateSnapshot(
            models: [model],
            updatedAt: Date().timeIntervalSince1970
        ),
        bridgeAlive: true,
        bridgeEnabled: true,
        bridgeLastError: "",
        sessionID: nil,
        sessionTitle: nil,
        sessionRuntime: nil,
        voiceRouteDecision: .unavailable,
        voiceRuntimeState: .idle,
        voiceAuthorizationStatus: .undetermined,
        voicePermissionSnapshot: .unknown,
        voiceActiveHealthReasonCode: "",
        voiceSidecarHealth: nil,
        wakeProfileSnapshot: .empty,
        conversationSession: .idle(
            policy: .default(),
            wakeMode: .pushToTalk,
            route: .manualText
        ),
        voicePreferences: .default(),
        voicePlaybackActivity: .empty,
        calendarReminderSnapshot: .empty,
        skillsSnapshot: AXSkillsDoctorSnapshot(
            hubIndexAvailable: true,
            installedSkillCount: 0,
            compatibleSkillCount: 0,
            partialCompatibilityCount: 0,
            revokedMatchCount: 0,
            trustEnabledPublisherCount: 1,
            projectIndexEntries: [],
            globalIndexEntries: [],
            conflictWarnings: [],
            installedSkills: [],
            statusKind: .supported,
            statusLine: "skills 0/0",
            compatibilityExplain: "skills compatibility ready"
        ),
        reportPath: "/tmp/xt_unified_doctor_report.json",
        modelRouteDiagnostics: .empty,
        projectContextDiagnostics: .empty
    )
}
