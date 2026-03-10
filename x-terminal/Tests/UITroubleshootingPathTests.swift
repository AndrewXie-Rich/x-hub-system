import Foundation
import Testing
@testable import XTerminal

struct UITroubleshootingPathTests {
    @Test
    func commonTroubleshootingPathsStayWithinThreeFixSteps() {
        for issue in UITroubleshootIssue.allCases {
            let guide = UITroubleshootKnowledgeBase.guide(for: issue)
            #expect(guide.maxFixSteps <= 3)
            #expect(guide.steps.count == 3)
        }

        let grantGuide = UITroubleshootKnowledgeBase.guide(for: .grantRequired)
        #expect(grantGuide.steps.map(\.destination).contains(.hubGrants))
        #expect(grantGuide.steps.first?.destination == .xtChooseModel)

        let permissionGuide = UITroubleshootKnowledgeBase.guide(for: .permissionDenied)
        #expect(permissionGuide.steps.map(\.destination).contains(.systemPermissions))

        let reachabilityGuide = UITroubleshootKnowledgeBase.guide(for: .hubUnreachable)
        #expect(reachabilityGuide.steps.first?.destination == .xtPairHub)
        #expect(reachabilityGuide.steps.last?.destination == .hubPairing)
    }

    @Test
    func settingsIaStaysTaskOrientedAndConsumesFrozenFields() throws {
        #expect(XTSettingsCenterManifest.sections.map(\.id) == [
            "pair_hub",
            "choose_model",
            "grant_permissions",
            "security_runtime",
            "diagnostics"
        ])
        #expect(XTSettingsCenterManifest.consumedFrozenFields.contains("xt.ui_information_architecture.v1"))
        #expect(XTSettingsCenterManifest.consumedFrozenFields.contains("xt.delivery_scope_freeze.v1.validated_scope"))
        #expect(XTSettingsCenterManifest.consumedFrozenFields.contains("xt.unblock_baton.v1"))
        #expect(XTSettingsCenterManifest.consumedFrozenFields.contains("xt.one_shot_replay_regression.v1"))

        let xTerminalRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let workspaceRoot = xTerminalRoot.deletingLastPathComponent()
        let hubSettingsPath = workspaceRoot
            .appendingPathComponent("x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift")
        let hubCardPath = workspaceRoot
            .appendingPathComponent("x-hub/macos/RELFlowHub/Sources/RELFlowHub/UI/HubSectionCard.swift")

        let hubSettingsSource = try String(contentsOf: hubSettingsPath, encoding: .utf8)
        #expect(hubSettingsSource.contains("Section(\"Setup Center\")"))
        #expect(hubSettingsSource.contains("Section(\"First Run Path\")"))
        #expect(hubSettingsSource.contains("Section(\"Troubleshoot In 3 Steps\")"))
        #expect(hubSettingsSource.contains("Pair Hub"))
        #expect(hubSettingsSource.contains("Models & Paid Access"))
        #expect(hubSettingsSource.contains("Grants & Permissions"))
        #expect(hubSettingsSource.contains("Security Boundary"))
        #expect(hubSettingsSource.contains("Diagnostics & Recovery"))
        #expect(FileManager.default.fileExists(atPath: hubCardPath.path))
    }

    @Test
    func settingsPlannerConsumesRuntimeContractsWithoutDriftingActionIDs() {
        let state = XTSettingsSurfaceState(
            hubConnected: true,
            remoteConnected: false,
            linking: false,
            localServerEnabled: true,
            serverRunning: false,
            failureCode: "",
            runtime: sampleRuntimeSnapshot()
        )

        let status = XTSettingsSurfacePlanner.status(for: state)
        let actions = XTSettingsSurfacePlanner.quickActions(for: state)
        let diagnostics = XTSettingsSurfacePlanner.diagnosticsLines(for: state)

        #expect(status.state == .grantRequired)
        #expect(status.machineStatusRef.contains("launch_deny=grant_required"))
        #expect(actions.map(\.id) == ["pair_hub", "run_smoke", "review_grants"])
        #expect(actions.first(where: { $0.id == "run_smoke" })?.subtitle == "replay fail-closed；先看 denyCode / diagnostics")
        #expect(actions.first(where: { $0.id == "review_grants" })?.subtitle?.contains("resume baton") == true)
        #expect(diagnostics.contains(where: { $0.contains("allowed_public_statements=") }))
        #expect(diagnostics.contains(where: { $0.contains("resume_baton=continue_current_task_only") }))
        #expect(diagnostics.contains(where: { $0.contains("replay=") }))
    }
}

private func sampleRuntimeSnapshot() -> UIFailClosedRuntimeSnapshot {
    UIFailClosedRuntimeSnapshot.capture(
        policy: OneShotAutonomyPolicy(
            schemaVersion: "xt.one_shot_autonomy_policy.v1",
            projectID: "project-1",
            autoConfirmPolicy: .safeOnly,
            autoLaunchPolicy: .mainlineOnly,
            grantGateMode: "fail_closed",
            allowedAutoActions: ["plan_generation", "directed_continue"],
            humanTouchpoints: ["scope_expansion"],
            explainabilityRequired: true,
            auditRef: "audit-policy-1"
        ),
        freeze: DeliveryScopeFreeze(
            schemaVersion: "xt.delivery_scope_freeze.v1",
            projectID: "project-1",
            runID: "run-1",
            validatedScope: ["XT-W3-23", "XT-W3-24", "XT-W3-25"],
            releaseStatementAllowlist: ["validated_mainline_only"],
            pendingNonReleaseItems: ["future_ui_productization"],
            decision: .noGo,
            auditRef: "audit-freeze-1",
            allowedPublicStatements: [
                "XT memory UX adapter backed by Hub truth-source",
                "Hub-governed multi-channel gateway"
            ],
            nextActions: ["drop_scope_expansion", "recompute_delivery_scope_freeze"],
            blockedExpansionItems: ["XT-W3-27-extra-surface"]
        ),
        launchDecisions: [
            OneShotLaunchDecision(
                laneID: "XT-W3-27-H",
                decision: .deny,
                denyCode: "grant_required",
                blockedReason: nil,
                note: "paid_model_requires_grant",
                autoLaunchAllowed: false,
                failClosed: true,
                requiresHumanTouch: true
            )
        ],
        directedUnblockBatons: [
            DirectedUnblockBaton(
                schemaVersion: "xt.unblock_baton.v1",
                projectID: "project-1",
                edgeID: "EDGE-HUB-1",
                blockedLane: "XT-W3-27-H",
                resolvedBy: "Hub",
                resolvedFact: "dependency_resolved",
                resumeScope: .continueCurrentTaskOnly,
                deadlineHintUTC: "2026-03-07T03:00:00Z",
                mustNotDo: ["scope_expand"],
                evidenceRefs: ["build/reports/xt_w3_27_h_ui_regression_evidence.v1.json"],
                emittedAtMs: 1_741_312_000_000,
                nextAction: "continue_current_task_only"
            )
        ],
        replayReport: OneShotReplayReport(
            schemaVersion: "xt.one_shot_replay_regression.v1",
            generatedAtMs: 1_741_312_000_001,
            pass: false,
            policySchemaVersion: "xt.one_shot_autonomy_policy.v1",
            freezeSchemaVersion: "xt.delivery_scope_freeze.v1",
            scenarios: [
                OneShotReplayScenarioResult(
                    scenario: .grantRequired,
                    pass: false,
                    finalState: "grant_required",
                    failClosed: true,
                    denyCode: "grant_required",
                    note: "grant gate closed"
                ),
                OneShotReplayScenarioResult(
                    scenario: .scopeExpansion,
                    pass: false,
                    finalState: "no_go",
                    failClosed: true,
                    denyCode: "scope_expansion",
                    note: "delivery scope freeze"
                )
            ],
            uiConsumableContracts: [
                "xt.one_shot_autonomy_policy.v1",
                "xt.delivery_scope_freeze.v1",
                "xt.one_shot_replay_regression.v1"
            ],
            evidenceRefs: ["build/reports/xt_w3_27_h_ui_regression_evidence.v1.json"]
        )
    )
}
