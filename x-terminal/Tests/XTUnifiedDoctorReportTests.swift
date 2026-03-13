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

    @Test
    func skillsSectionRequiresDefaultBaselineWhenMissing() {
        let model = sampleModel(id: "hub.model.coder")
        var skills = readySkillsSnapshot()
        skills.statusKind = .partial
        skills.missingBaselineSkillIDs = ["find-skills", "agent-browser"]
        skills.baselineRecommendedSkills = [
            AXDefaultAgentBaselineSkill(skillID: "find-skills", displayName: "Find Skills", summary: ""),
            AXDefaultAgentBaselineSkill(skillID: "agent-browser", displayName: "Agent Browser", summary: ""),
            AXDefaultAgentBaselineSkill(skillID: "self-improving-agent", displayName: "Self Improving Agent", summary: ""),
            AXDefaultAgentBaselineSkill(skillID: "summarize", displayName: "Summarize", summary: ""),
        ]
        skills.statusLine = "skills~ 0/0 b2/4"
        skills.compatibilityExplain = "baseline_missing=find-skills,agent-browser"

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: skills
            )
        )

        let section = report.section(.skillsCompatibilityReadiness)
        #expect(section?.state == .inProgress)
        #expect(section?.headline == "Default Agent baseline is incomplete")
        #expect(section?.nextStep.contains("find-skills") == true)
        #expect(section?.nextStep.contains("agent-browser") == true)
    }

    @Test
    func skillsSectionShowsLocalDevPublisherCoverageWhenActive() {
        let model = sampleModel(id: "hub.model.coder")
        var skills = readySkillsSnapshot()
        skills.installedSkillCount = 4
        skills.compatibleSkillCount = 4
        skills.baselineRecommendedSkills = defaultBaselineSkills()
        skills.installedSkills = defaultBaselineSkillEntries(publisherID: AXSkillsDoctorSnapshot.localDevPublisherID)
        skills.statusLine = "skills 4/4 b4/4"

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: skills
            )
        )

        let section = report.section(.skillsCompatibilityReadiness)
        #expect(section?.state == .ready)
        #expect(section?.detailLines.contains("active_publishers=xhub.local.dev") == true)
        #expect(section?.detailLines.contains("local_dev_publisher_active=yes") == true)
        #expect(section?.detailLines.contains("baseline_publishers=xhub.local.dev") == true)
        #expect(section?.detailLines.contains("baseline_local_dev=4/4") == true)
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

private func defaultBaselineSkills() -> [AXDefaultAgentBaselineSkill] {
    [
        AXDefaultAgentBaselineSkill(skillID: "find-skills", displayName: "Find Skills", summary: ""),
        AXDefaultAgentBaselineSkill(skillID: "agent-browser", displayName: "Agent Browser", summary: ""),
        AXDefaultAgentBaselineSkill(skillID: "self-improving-agent", displayName: "Self Improving Agent", summary: ""),
        AXDefaultAgentBaselineSkill(skillID: "summarize", displayName: "Summarize", summary: ""),
    ]
}

private func defaultBaselineSkillEntries(publisherID: String) -> [AXHubSkillCompatibilityEntry] {
    [
        AXHubSkillCompatibilityEntry(
            skillID: "find-skills",
            name: "Find Skills",
            version: "1.1.0",
            publisherID: publisherID,
            sourceID: "builtin:catalog",
            packageSHA256: "a100000000000000000000000000000000000000000000000000000000000001",
            abiCompatVersion: "skills_abi_compat.v1",
            compatibilityState: .supported,
            canonicalManifestSHA256: "b100000000000000000000000000000000000000000000000000000000000001",
            installHint: "",
            mappingAliasesUsed: [],
            defaultsApplied: [],
            pinnedScopes: ["project"],
            revoked: false
        ),
        AXHubSkillCompatibilityEntry(
            skillID: "agent-browser",
            name: "Agent Browser",
            version: "1.0.0",
            publisherID: publisherID,
            sourceID: "builtin:catalog",
            packageSHA256: "a100000000000000000000000000000000000000000000000000000000000002",
            abiCompatVersion: "skills_abi_compat.v1",
            compatibilityState: .supported,
            canonicalManifestSHA256: "b100000000000000000000000000000000000000000000000000000000000002",
            installHint: "",
            mappingAliasesUsed: [],
            defaultsApplied: [],
            pinnedScopes: ["project"],
            revoked: false
        ),
        AXHubSkillCompatibilityEntry(
            skillID: "self-improving-agent",
            name: "Self Improving Agent",
            version: "1.0.0",
            publisherID: publisherID,
            sourceID: "builtin:catalog",
            packageSHA256: "a100000000000000000000000000000000000000000000000000000000000003",
            abiCompatVersion: "skills_abi_compat.v1",
            compatibilityState: .supported,
            canonicalManifestSHA256: "b100000000000000000000000000000000000000000000000000000000000003",
            installHint: "",
            mappingAliasesUsed: [],
            defaultsApplied: [],
            pinnedScopes: ["project"],
            revoked: false
        ),
        AXHubSkillCompatibilityEntry(
            skillID: "summarize",
            name: "Summarize",
            version: "1.1.0",
            publisherID: publisherID,
            sourceID: "builtin:catalog",
            packageSHA256: "a100000000000000000000000000000000000000000000000000000000000004",
            abiCompatVersion: "skills_abi_compat.v1",
            compatibilityState: .supported,
            canonicalManifestSHA256: "b100000000000000000000000000000000000000000000000000000000000004",
            installHint: "",
            mappingAliasesUsed: [],
            defaultsApplied: [],
            pinnedScopes: ["project"],
            revoked: false
        ),
    ]
}
