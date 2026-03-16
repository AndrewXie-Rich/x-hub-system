import Foundation
import Testing
@testable import XTerminal

struct SupervisorDoctorTests {

    @Test
    func allowlistEmptyBlocksAndReturnsActionableSuggestion() {
        var config = SupervisorDoctorConfig.conservativeDefault()
        config.dmPolicy = "allowlist"
        config.allowFrom = []

        let workspace = URL(fileURLWithPath: "/tmp/xterminal_doctor_test", isDirectory: true)
        let input = SupervisorDoctorInputBundle(
            workspaceRoot: workspace,
            config: config,
            configSource: "unit_test",
            secretsPlan: SupervisorSecretsDryRunPlan(
                allowedRoots: [workspace.appendingPathComponent(".axcoder/secrets").path],
                allowedModes: ["0600"],
                items: []
            ),
            secretsPlanSource: "unit_test",
            reportURL: workspace.appendingPathComponent("doctor_report.json"),
            memoryAssemblySnapshot: nil
        )

        let report = SupervisorDoctorChecker.run(input: input)

        #expect(report.ok == false)
        #expect(report.findings.contains(where: { $0.code == "dm_allowlist_empty" }))
        #expect(report.suggestions.contains(where: { $0.findingCode == "dm_allowlist_empty" && !$0.actions.isEmpty }))
    }

    @Test
    func secretsOutOfScopePathIsBlocked() {
        let workspace = URL(fileURLWithPath: "/tmp/xterminal_doctor_test", isDirectory: true)
        let safeRoot = workspace.appendingPathComponent(".axcoder/secrets", isDirectory: true).path
        let plan = SupervisorSecretsDryRunPlan(
            allowedRoots: [safeRoot],
            allowedModes: ["0600"],
            items: [
                .init(
                    name: "prod token",
                    targetPath: "/etc/xterminal/secret.env",
                    requiredVariables: ["API_TOKEN"],
                    providedVariables: ["API_TOKEN"],
                    mode: "0600"
                )
            ]
        )

        let input = SupervisorDoctorInputBundle(
            workspaceRoot: workspace,
            config: .conservativeDefault(),
            configSource: "unit_test",
            secretsPlan: plan,
            secretsPlanSource: "unit_test",
            reportURL: workspace.appendingPathComponent("doctor_report.json"),
            memoryAssemblySnapshot: nil
        )

        let report = SupervisorDoctorChecker.run(input: input)

        #expect(report.ok == false)
        #expect(report.summary.secretsPathOutOfScopeCount == 1)
        #expect(report.findings.contains(where: { $0.code == "secrets_target_path_out_of_scope" }))
    }

    @Test
    func missingReportNeverPassesReleaseGate() {
        let decision = SupervisorDoctorGateEvaluator.evaluate(report: nil)
        #expect(decision.pass == false)
        #expect(decision.releaseBlockedByDoctorWithoutReport == 1)
        #expect(decision.reason == "missing_supervisor_doctor_report")
    }

    @Test
    func runAndPersistWritesSecretsDryRunCompatReport() throws {
        let workspace = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("xterminal_doctor_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let reportURL = workspace.appendingPathComponent(".axcoder/reports/supervisor_doctor_report.json")
        let plan = SupervisorSecretsDryRunPlan(
            allowedRoots: [workspace.appendingPathComponent(".axcoder/secrets").path],
            allowedModes: ["0600"],
            items: [
                .init(
                    name: "api",
                    targetPath: "/etc/xterminal/token.env",
                    requiredVariables: ["API_TOKEN", "API_REGION"],
                    providedVariables: ["API_TOKEN"],
                    mode: "0644"
                )
            ]
        )
        let input = SupervisorDoctorInputBundle(
            workspaceRoot: workspace,
            config: .conservativeDefault(),
            configSource: "unit_test",
            secretsPlan: plan,
            secretsPlanSource: "unit_test",
            reportURL: reportURL,
            memoryAssemblySnapshot: nil
        )

        let report = SupervisorDoctorChecker.runAndPersist(input: input)
        #expect(report.ok == false)

        let compatURL = reportURL.deletingLastPathComponent().appendingPathComponent("secrets-dry-run-report.json")
        #expect(FileManager.default.fileExists(atPath: compatURL.path))

        let data = try Data(contentsOf: compatURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect((json?["dry_run"] as? Bool) == true)
        #expect((json?["target_path_out_of_scope_count"] as? Int) == 1)
        #expect((json?["missing_variables_count"] as? Int) == 1)
        #expect((json?["permission_boundary_error_count"] as? Int) == 1)

        let doctorCompatURL = reportURL.deletingLastPathComponent().appendingPathComponent("doctor-report.json")
        #expect(FileManager.default.fileExists(atPath: doctorCompatURL.path))
        let doctorData = try Data(contentsOf: doctorCompatURL)
        let doctorJSON = try JSONSerialization.jsonObject(with: doctorData) as? [String: Any]
        let doctorSection = doctorJSON?["doctor"] as? [String: Any]
        #expect((doctorSection?["dmPolicy"] as? String) == "allowlist")
        #expect((doctorSection?["allowFrom"] as? [String])?.isEmpty == false)
        #expect((doctorSection?["ws_origin"] as? String)?.isEmpty == false)
        #expect((doctorSection?["shared_token_auth"] as? Bool) == true)
        #expect((doctorSection?["non_message_ingress_policy_coverage"] as? Int) == 1)
        #expect((doctorSection?["unauthorized_flood_drop_count"] as? Int) == 45)
    }

    @Test
    func memoryReviewFloorMissIsSurfacedAsBlockingFinding() {
        let snapshot = makeMemorySnapshot(
            profileFloor: XTMemoryServingProfile.m3DeepDive.rawValue,
            resolvedProfile: XTMemoryServingProfile.m2PlanReview.rawValue
        )
        let report = SupervisorDoctorChecker.run(input: makeInput(snapshot: snapshot))

        let finding = report.findings.first { $0.code == "memory_review_floor_not_met" }
        #expect(finding?.area == "memory_assembly")
        #expect(finding?.severity == .blocking)
        #expect(report.summary.memoryAssemblyBlockingCount == 1)
        #expect(report.summary.memoryAssemblyWarningCount == 0)
    }

    @Test
    func truncatedCoreMemoryLayerIsSurfacedAsWarning() {
        let snapshot = makeMemorySnapshot(
            truncatedLayers: ["l1_canonical"]
        )
        let report = SupervisorDoctorChecker.run(input: makeInput(snapshot: snapshot))

        let finding = report.findings.first { $0.code == "memory_core_layers_truncated" }
        #expect(finding?.area == "memory_assembly")
        #expect(finding?.severity == .warning)
        #expect(report.summary.memoryAssemblyBlockingCount == 0)
        #expect(report.summary.memoryAssemblyWarningCount == 1)
    }

    @Test
    func legacyDoctorSummaryDecodesWithoutMemoryAssemblyFields() throws {
        let legacyJSON = """
        {
          "schemaVersion": "supervisor_doctor.v1",
          "generatedAtMs": 1773000000000,
          "workspaceRoot": "/tmp/xterminal_doctor_legacy",
          "configSource": "legacy",
          "secretsPlanSource": "legacy",
          "ok": false,
          "findings": [],
          "suggestions": [],
          "summary": {
            "doctorReportPresent": 1,
            "releaseBlockedByDoctorWithoutReport": 0,
            "blockingCount": 1,
            "warningCount": 2,
            "dmAllowlistRiskCount": 0,
            "wsAuthRiskCount": 1,
            "preAuthFloodBreakerRiskCount": 0,
            "secretsPathOutOfScopeCount": 0,
            "secretsMissingVariableCount": 0,
            "secretsPermissionBoundaryCount": 0
          }
        }
        """

        let report = try JSONDecoder().decode(
            SupervisorDoctorReport.self,
            from: Data(legacyJSON.utf8)
        )

        #expect(report.summary.memoryAssemblyBlockingCount == 0)
        #expect(report.summary.memoryAssemblyWarningCount == 0)
        #expect(report.summary.blockingCount == 1)
        #expect(report.summary.warningCount == 2)
    }

    private func makeInput(
        snapshot: SupervisorMemoryAssemblySnapshot?
    ) -> SupervisorDoctorInputBundle {
        let workspace = URL(fileURLWithPath: "/tmp/xterminal_doctor_memory_test", isDirectory: true)
        return SupervisorDoctorInputBundle(
            workspaceRoot: workspace,
            config: .conservativeDefault(),
            configSource: "unit_test",
            secretsPlan: SupervisorSecretsDryRunPlan(
                allowedRoots: [workspace.appendingPathComponent(".axcoder/secrets").path],
                allowedModes: ["0600"],
                items: []
            ),
            secretsPlanSource: "unit_test",
            reportURL: workspace.appendingPathComponent("doctor_report.json"),
            memoryAssemblySnapshot: snapshot
        )
    }

    private func makeMemorySnapshot(
        reviewLevelHint: SupervisorReviewLevel = .r2Strategic,
        requestedProfile: String = XTMemoryServingProfile.m3DeepDive.rawValue,
        profileFloor: String = XTMemoryServingProfile.m3DeepDive.rawValue,
        resolvedProfile: String = XTMemoryServingProfile.m3DeepDive.rawValue,
        focusedProjectId: String? = "project-alpha",
        selectedSections: [String] = [
            "portfolio_brief",
            "focused_project_anchor_pack",
            "longterm_outline",
            "delta_feed",
            "conflict_set",
            "context_refs",
            "evidence_pack",
        ],
        omittedSections: [String] = [],
        contextRefsSelected: Int = 2,
        contextRefsOmitted: Int = 0,
        evidenceItemsSelected: Int = 2,
        evidenceItemsOmitted: Int = 0,
        truncatedLayers: [String] = []
    ) -> SupervisorMemoryAssemblySnapshot {
        SupervisorMemoryAssemblySnapshot(
            source: "unit_test",
            resolutionSource: "unit_test",
            updatedAt: 1_773_000_000,
            reviewLevelHint: reviewLevelHint.rawValue,
            requestedProfile: requestedProfile,
            profileFloor: profileFloor,
            resolvedProfile: resolvedProfile,
            attemptedProfiles: [requestedProfile, resolvedProfile],
            progressiveUpgradeCount: 0,
            focusedProjectId: focusedProjectId,
            selectedSections: selectedSections,
            omittedSections: omittedSections,
            contextRefsSelected: contextRefsSelected,
            contextRefsOmitted: contextRefsOmitted,
            evidenceItemsSelected: evidenceItemsSelected,
            evidenceItemsOmitted: evidenceItemsOmitted,
            budgetTotalTokens: 1_800,
            usedTotalTokens: 1_120,
            truncatedLayers: truncatedLayers,
            freshness: "fresh_local_ipc",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "progressive_disclosure"
        )
    }
}
