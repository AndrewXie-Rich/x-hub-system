import Foundation
import Testing
@testable import XTerminal

struct UIFirstRunJourneyTests {
    @Test
    func firstRunJourneyKeepsFrozenStepOrderAndSharedStateContracts() {
        let plan = UIFirstRunJourneyPlanner.plan(
            for: HubSetupWizardState(
                localConnected: false,
                remoteConnected: false,
                linking: false,
                configuredModelRoles: 0,
                totalModelRoles: AXRole.allCases.count,
                failureCode: "hub_unreachable",
                runtime: .empty
            )
        )

        #expect(plan.badge == .validatedMainlineOnly)
        #expect(plan.steps.map(\.kind) == [.pairHub, .chooseModel, .resolveGrant, .runSmoke, .verifyReadiness, .startFirstTask])
        #expect(plan.steps[0].state == .blockedWaitingUpstream)
        #expect(plan.steps[2].state == .ready)
        #expect(plan.steps[3].state == .blockedWaitingUpstream)
        #expect(plan.steps[4].state == .blockedWaitingUpstream)
        #expect(plan.primaryStatus.state == .diagnosticRequired)
        #expect(plan.currentFailureIssue == .hubUnreachable)
        #expect(plan.actions.map(\.id) == ["pair_hub", "run_smoke", "open_repair_entry"])
        #expect(plan.consumedFrozenFields.contains("xt.ui_surface_state_contract.v1"))
        #expect(plan.consumedFrozenFields.contains("xt.ui_release_scope_badge.v1"))
    }

    @Test
    func connectedJourneyReusesReleaseBadgeAndBecomesSmokeReady() {
        let plan = UIFirstRunJourneyPlanner.plan(
            for: HubSetupWizardState(
                localConnected: true,
                remoteConnected: false,
                linking: false,
                configuredModelRoles: 2,
                totalModelRoles: AXRole.allCases.count,
                failureCode: "",
                runtime: .empty
            )
        )

        #expect(plan.badge.badgeText == XTUIReleaseScopeBadgeContract.frozen.badgeText)
        #expect(plan.badge.validatedPaths == XTUIReleaseScopeBadgeContract.frozen.validatedPaths)
        #expect(plan.primaryStatus.state == .ready)
        #expect(plan.releaseStatus.state == .releaseFrozen)
        #expect(plan.steps[0].state == .ready)
        #expect(plan.steps[1].state == .ready)
        #expect(plan.steps[3].state == .ready)
        #expect(plan.steps[4].state == .ready)
        #expect(plan.steps[5].state == .ready)
        #expect(plan.smokeReady)
    }

    @Test
    func runtimeContractsDriveFailClosedFirstRunGating() {
        let plan = UIFirstRunJourneyPlanner.plan(
            for: HubSetupWizardState(
                localConnected: true,
                remoteConnected: false,
                linking: false,
                configuredModelRoles: 2,
                totalModelRoles: AXRole.allCases.count,
                failureCode: "",
                runtime: sampleRuntimeSnapshot()
            )
        )

        #expect(plan.currentFailureIssue == .grantRequired)
        #expect(plan.primaryStatus.state == .grantRequired)
        #expect(plan.primaryStatus.machineStatusRef.contains("scope_decision=no_go"))
        #expect(plan.releaseStatus.state == .blockedWaitingUpstream)
        #expect(plan.releaseStatus.highlights.contains(where: { $0.contains("allowed_statement=") }))
        #expect(plan.actions.first(where: { $0.id == "run_smoke" })?.subtitle == "replay fail-closed；先看 denyCode / diagnostics")
        #expect(plan.actions.first(where: { $0.id == "open_repair_entry" })?.subtitle?.contains("resume baton") == true)
        #expect(plan.steps[2].state == .grantRequired)
        #expect(plan.steps[3].state == .diagnosticRequired)
        #expect(plan.steps[4].state == .diagnosticRequired)
        #expect(plan.steps[5].state == .blockedWaitingUpstream)
        #expect(plan.consumedFrozenFields.contains("xt.unblock_baton.v1"))
        #expect(plan.consumedFrozenFields.contains("xt.one_shot_replay_regression.v1"))
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
            evidenceRefs: ["build/reports/xt_w3_27_first_run_journey_evidence.v1.json"]
        )
    )
}
