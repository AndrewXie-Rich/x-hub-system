import Foundation
import Testing
@testable import XTerminal

struct XTerminalGateSmokeRunnerTests {
    @Test
    func unifiedDoctorExportWritesGenericBundleAndReturnsReadyExitCode() throws {
        let workspace = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("xt_unified_doctor_export_test_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: workspace)
        }

        let sourceURL = XTUnifiedDoctorStore.defaultReportURL(workspaceRoot: workspace)
        let outputURL = workspace
            .appendingPathComponent(".axcoder/reports", isDirectory: true)
            .appendingPathComponent("doctor_export.runtime.json")
        let report = XTUnifiedDoctorReport(
            schemaVersion: XTUnifiedDoctorReport.currentSchemaVersion,
            generatedAtMs: 1_741_300_123,
            overallState: .ready,
            overallSummary: "Ready for first task",
            readyForFirstTask: true,
            currentFailureCode: "",
            currentFailureIssue: nil,
            configuredModelRoles: 4,
            availableModelCount: 1,
            loadedModelCount: 1,
            currentSessionID: "session-ready",
            currentRoute: XTUnifiedDoctorRouteSnapshot(
                transportMode: "local",
                routeLabel: "paired-local",
                pairingPort: 50052,
                grpcPort: 50051,
                internetHost: "127.0.0.1"
            ),
            sections: [
                XTUnifiedDoctorSection(
                    kind: .hubReachability,
                    state: .ready,
                    headline: "Hub reachability is ready",
                    summary: "Hub pairing and gRPC are reachable.",
                    nextStep: "Start the first task.",
                    repairEntry: .homeSupervisor,
                    detailLines: ["route=paired-local"]
                )
            ],
            consumedContracts: ["xt.ui_surface_state_contract.v1", XTUnifiedDoctorReportContract.frozen.schemaVersion],
            reportPath: sourceURL.path
        )
        XTUnifiedDoctorStore.writeReport(report, to: sourceURL)

        let args = [
            "XTerminal",
            XTerminalGateSmokeRunner.unifiedDoctorExportFlag,
            XTerminalGateSmokeRunner.projectRootFlag,
            workspace.path,
            XTerminalGateSmokeRunner.outJSONFlag,
            outputURL.path,
        ]

        let code = XTerminalGateSmokeRunner.runIfRequested(arguments: args)
        #expect(code == 0)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))

        let data = try Data(contentsOf: outputURL)
        let decoded = try JSONDecoder().decode(XHubDoctorOutputReport.self, from: data)
        #expect(decoded.surface == .xtExport)
        #expect(decoded.reportPath == outputURL.path)
        #expect(decoded.sourceReportPath == sourceURL.path)
        #expect(decoded.summary.failed == 0)
        #expect(decoded.readyForFirstTask == true)
    }

    @Test
    func unifiedDoctorExportReturnsMissingSourceExitCode() throws {
        let workspace = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("xt_unified_doctor_export_missing_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: workspace)
        }

        let args = [
            "XTerminal",
            XTerminalGateSmokeRunner.unifiedDoctorExportFlag,
            XTerminalGateSmokeRunner.projectRootFlag,
            workspace.path,
        ]

        let code = XTerminalGateSmokeRunner.runIfRequested(arguments: args)
        #expect(code == 2)
        #expect(
            !FileManager.default.fileExists(
                atPath: XHubDoctorOutputStore.defaultXTReportURL(workspaceRoot: workspace).path
            )
        )
    }

    @Test
    func releaseEvidenceSmokeWritesRuntimeAndSecretsArtifacts() throws {
        let workspace = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("xt_release_evidence_test_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: workspace)
        }

        let args = [
            "XTerminal",
            XTerminalGateSmokeRunner.releaseEvidenceSmokeFlag,
            XTerminalGateSmokeRunner.projectRootFlag,
            workspace.path,
        ]

        let code = XTerminalGateSmokeRunner.runIfRequested(arguments: args)
        #expect(code == 0)

        let runtimeEventsURL = workspace
            .appendingPathComponent(".axcoder/reports", isDirectory: true)
            .appendingPathComponent("xt_ready_incident_events.runtime.json")
        let secretsPlanURL = workspace
            .appendingPathComponent(".axcoder/secrets", isDirectory: true)
            .appendingPathComponent("secrets_apply_dry_run.json")

        #expect(FileManager.default.fileExists(atPath: runtimeEventsURL.path))
        #expect(FileManager.default.fileExists(atPath: secretsPlanURL.path))

        let runtimeData = try Data(contentsOf: runtimeEventsURL)
        let runtimeJSON = try #require(JSONSerialization.jsonObject(with: runtimeData) as? [String: Any])
        let summary = try #require(runtimeJSON["summary"] as? [String: Any])
        #expect((summary["non_message_ingress_policy_coverage"] as? Int) == 1)

        let events = try #require(runtimeJSON["events"] as? [[String: Any]])
        #expect(events.count >= 4)
        #expect(events.contains(where: { ($0["incident_code"] as? String) == "grant_pending" }))
        #expect(events.contains(where: { ($0["incident_code"] as? String) == "awaiting_instruction" }))
        #expect(events.contains(where: { ($0["incident_code"] as? String) == "runtime_error" }))

        let source = try #require(runtimeJSON["source"] as? [String: Any])
        #expect((source["generated_by"] as? String) == "xt_release_evidence_smoke")

        let secretsData = try Data(contentsOf: secretsPlanURL)
        let secretsJSON = try #require(JSONSerialization.jsonObject(with: secretsData) as? [String: Any])
        #expect((secretsJSON["allowedModes"] as? [String])?.contains("0600") == true)
        let items = try #require(secretsJSON["items"] as? [[String: Any]])
        #expect(items.count == 1)
        #expect((items[0]["targetPath"] as? String) == ".axcoder/secrets/ws_shared_token.env")
    }

    @Test
    func runIfRequestedReturnsNilForNormalLaunchArguments() {
        let args = ["XTerminal", "--no-smoke"]
        #expect(XTerminalGateSmokeRunner.runIfRequested(arguments: args) == nil)
    }

    @Test
    func splitFlowFixtureSmokeWritesRuntimeFixtureArtifact() throws {
        let workspace = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("xt_split_flow_fixture_test_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: workspace)
        }

        let outputURL = workspace
            .appendingPathComponent(".axcoder/reports", isDirectory: true)
            .appendingPathComponent("split_flow_snapshot.runtime.json")

        let args = [
            "XTerminal",
            XTerminalGateSmokeRunner.splitFlowFixtureSmokeFlag,
            XTerminalGateSmokeRunner.projectRootFlag,
            workspace.path,
            XTerminalGateSmokeRunner.outJSONFlag,
            outputURL.path,
        ]

        let code = XTerminalGateSmokeRunner.runIfRequested(arguments: args)
        #expect(code == 0)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))

        let data = try Data(contentsOf: outputURL)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((json["schema_version"] as? String) == "xterminal.split_flow_snapshot_fixture.v1")

        let snapshots = try #require(json["snapshots"] as? [[String: Any]])
        #expect(snapshots.count == 4)
        let flowStates = snapshots.compactMap { item -> String? in
            guard let snapshot = item["snapshot"] as? [String: Any] else { return nil }
            return snapshot["flowState"] as? String
        }
        #expect(flowStates == ["proposed", "overridden", "blocked", "confirmed"])
    }
}
