import Foundation
import Testing
@testable import XTerminal

struct XTUnifiedDoctorReportTests {
    @Test
    func distinguishesPairingOkButModelRouteUnavailable() {
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [],
                models: [],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot()
            )
        )

        #expect(report.section(.pairingValidity)?.state == .ready)
        #expect(report.section(.modelRouteReadiness)?.state == .diagnosticRequired)
        #expect(report.section(.modelRouteReadiness)?.headline == "Pairing ok, but model route is unavailable")
        #expect(report.readyForFirstTask == false)
    }

    @Test
    func distinguishesModelRouteOkButBridgeUnavailable() {
        let model = sampleModel(id: "hub.model.coder")
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: false,
                bridgeEnabled: false,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot()
            )
        )

        #expect(report.section(.modelRouteReadiness)?.state == .ready)
        #expect(report.section(.bridgeToolReadiness)?.state == .diagnosticRequired)
        #expect(report.section(.bridgeToolReadiness)?.headline == "Model route ok, but bridge / tool route is unavailable")
    }

    @Test
    func distinguishesBridgeOkButRuntimeNotRecoverable() {
        let model = sampleModel(id: "hub.model.supervisor")
        let runtime = AXSessionRuntimeSnapshot(
            schemaVersion: AXSessionRuntimeSnapshot.currentSchemaVersion,
            state: .failed_recoverable,
            runID: "run-1",
            updatedAt: Date().timeIntervalSince1970,
            startedAt: Date().timeIntervalSince1970 - 20,
            completedAt: nil,
            lastRuntimeSummary: "tool batch failed",
            lastToolBatchIDs: ["batch-1"],
            pendingToolCallCount: 0,
            lastFailureCode: "runtime_recoverability_lost",
            resumeToken: nil,
            recoverable: false
        )
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: runtime,
                sessionID: "session-1",
                skillsSnapshot: readySkillsSnapshot()
            )
        )

        #expect(report.section(.bridgeToolReadiness)?.state == .ready)
        #expect(report.section(.sessionRuntimeReadiness)?.state == .diagnosticRequired)
        #expect(report.section(.sessionRuntimeReadiness)?.headline == "Bridge ok, but session runtime is not recoverable")
    }

    @Test
    func writesMachineReadableReportWithSkillsSection() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-unified-doctor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let reportURL = XTUnifiedDoctorStore.defaultReportURL(workspaceRoot: tempRoot)
        let model = sampleModel(id: "hub.model.coder")
        var skills = readySkillsSnapshot()
        skills.installedSkillCount = 1
        skills.compatibleSkillCount = 1
        skills.statusLine = "skills 1/1"

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: skills,
                reportPath: reportURL.path
            )
        )
        XTUnifiedDoctorStore.writeReport(report, to: reportURL)

        let data = try Data(contentsOf: reportURL)
        let decoded = try JSONDecoder().decode(XTUnifiedDoctorReport.self, from: data)

        #expect(decoded.schemaVersion == XTUnifiedDoctorReport.currentSchemaVersion)
        #expect(decoded.reportPath == reportURL.path)
        #expect(decoded.section(.skillsCompatibilityReadiness) != nil)
        #expect(decoded.sections.count == XTUnifiedDoctorSectionKind.allCases.count)
    }
}

private func makeDoctorInput(
    localConnected: Bool,
    remoteConnected: Bool,
    configuredModelIDs: [String],
    models: [HubModel],
    bridgeAlive: Bool,
    bridgeEnabled: Bool,
    sessionRuntime: AXSessionRuntimeSnapshot?,
    sessionID: String? = nil,
    skillsSnapshot: AXSkillsDoctorSnapshot,
    reportPath: String = "/tmp/xt_unified_doctor_report.json"
) -> XTUnifiedDoctorInput {
    XTUnifiedDoctorInput(
        generatedAt: Date(timeIntervalSince1970: 1_741_300_000),
        localConnected: localConnected,
        remoteConnected: remoteConnected,
        remoteRoute: .none,
        linking: false,
        pairingPort: 50052,
        grpcPort: 50051,
        internetHost: localConnected ? "10.0.0.8" : "hub.example.test",
        configuredModelIDs: configuredModelIDs,
        totalModelRoles: AXRole.allCases.count,
        failureCode: "",
        runtime: .empty,
        runtimeStatus: AIRuntimeStatus(
            pid: 42,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: true,
            runtimeVersion: "test-runtime",
            importError: nil,
            activeMemoryBytes: nil,
            peakMemoryBytes: nil,
            loadedModelCount: models.filter { $0.state == .loaded }.count
        ),
        modelsState: ModelStateSnapshot(models: models, updatedAt: Date().timeIntervalSince1970),
        bridgeAlive: bridgeAlive,
        bridgeEnabled: bridgeEnabled,
        sessionID: sessionID,
        sessionTitle: sessionID == nil ? nil : "Doctor Session",
        sessionRuntime: sessionRuntime,
        skillsSnapshot: skillsSnapshot,
        reportPath: reportPath
    )
}

private func sampleModel(id: String) -> HubModel {
    HubModel(
        id: id,
        name: id,
        backend: "mlx",
        quant: "4bit",
        contextLength: 32768,
        paramsB: 7.0,
        roles: ["coder"],
        state: .loaded,
        memoryBytes: 1_024,
        tokensPerSec: 42,
        modelPath: "/models/\(id)",
        note: nil
    )
}

private func readySkillsSnapshot() -> AXSkillsDoctorSnapshot {
    AXSkillsDoctorSnapshot(
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
    )
}
