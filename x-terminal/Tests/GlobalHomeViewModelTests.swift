import Foundation
import Testing
@testable import XTerminal

struct GlobalHomeViewModelTests {
    @Test
    func frozenContractsAndActionsMatchXTW327AB() {
        let architecture = XTUIInformationArchitectureContract.frozen
        #expect(architecture.surfaces.contains("xt.global_home"))
        #expect(architecture.primaryActions["xt.global_home"] == ["resume_project", "pair_hub", "model_status"])
        #expect(architecture.diagnosticEntrypoints.contains("model_status"))

        let tokens = XTUIDesignTokenBundleContract.frozen
        #expect(tokens.colorSemantics.success == "verified_green")
        #expect(tokens.colorSemantics.warning == "grant_amber")
        #expect(tokens.surfaceTokens.cardRadius == 18)
        #expect(tokens.surfaceTokens.sectionSpacing == 20)
        #expect(tokens.motionPolicy == "subtle_stateful_only")

        let stateContract = XTUISurfaceStateContract.frozen
        #expect(stateContract.requiredFields.contains("headline"))
        #expect(stateContract.requiredFields.contains("machine_status_ref"))
        #expect(stateContract.mustNotHide.contains("grant_fail_closed"))
        #expect(stateContract.mustNotHide.contains("scope_not_validated"))
    }

    @Test
    func globalHomePresentationPrioritizesProjectSummaryAndFailClosedStates() {
        let disconnected = GlobalHomePresentation.map(
            input: GlobalHomePresentationInput(
                hubInteractive: false,
                projectCount: 0,
                runningProjectCount: 0,
                pendingGrantCount: 0,
                highlightedProjectName: nil
            )
        )
        #expect(disconnected.primaryStatus.state == .blockedWaitingUpstream)
        #expect(disconnected.primaryStatus.userAction.contains("连接 Hub"))
        #expect(disconnected.actions.first?.id == "pair_hub")
        #expect(disconnected.badge.badgeText == "Validated mainline only")

        let grantRequired = GlobalHomePresentation.map(
            input: GlobalHomePresentationInput(
                hubInteractive: true,
                projectCount: 2,
                runningProjectCount: 0,
                pendingGrantCount: 2,
                highlightedProjectName: "Atlas"
            )
        )
        #expect(grantRequired.primaryStatus.state == .grantRequired)
        #expect(grantRequired.primaryStatus.hardLine == "授权完成前，不自动继续")
        #expect(grantRequired.actions.first?.id == "resume_project")

        let ready = GlobalHomePresentation.map(
            input: GlobalHomePresentationInput(
                hubInteractive: true,
                projectCount: 1,
                runningProjectCount: 0,
                pendingGrantCount: 0,
                highlightedProjectName: "Helios"
            )
        )
        #expect(ready.primaryStatus.state == .ready)
        #expect(ready.primaryStatus.headline.contains("项目总览已同步"))
        #expect(ready.actions.first?.id == "resume_project")
        #expect(
            ready.actions.first(where: { $0.id == "model_status" })?.title
                == "打开 Supervisor"
        )
        #expect(
            ready.actions.first(where: { $0.id == "model_status" })?.subtitle
                == "统一查看 AI 模型、项目状态和真实可用视图"
        )
        #expect(ready.releaseStatus.state == .ready)
        #expect(ready.consumedFrozenFields.contains("xt.ui_release_scope_badge.v1.badge_text"))
    }

    @Test
    func globalHomeProjectRowsBindGovernanceSummaryToWatchlistConfiguration() {
        let configuration = ProjectGovernanceCompactSummarySurfaceConfiguration.watchlist
        #expect(configuration.showAxisLegend)
        #expect(configuration.displayStyle == .watchlist)

        let steadyPresentation = ProjectGovernancePresentation(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 900,
            reviewPulseSeconds: 1800,
            brainstormReviewSeconds: 0,
            eventDrivenReviewEnabled: true
        )
        let steadyItems = ProjectGovernanceCompactMetaResolver.items(
            context: ProjectGovernanceCompactMetaResolver.context(
                presentation: steadyPresentation,
                displayStyle: configuration.displayStyle
            ),
            showAxisLegend: configuration.showAxisLegend,
            showCallout: true,
            displayStyle: configuration.displayStyle
        )

        #expect(steadyItems.map(\.kind) == [.axisLegend, .truthLine])
        #expect(steadyItems[0].text == "三轴：A 管执行，S 管监督，节奏管 review")
        #expect(steadyItems[1].text.contains("当前生效 A2/S2"))

        let highRiskPresentation = ProjectGovernancePresentation(
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s1MilestoneReview,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1200,
            brainstormReviewSeconds: 2400,
            eventDrivenReviewEnabled: true
        )
        let highRiskItems = ProjectGovernanceCompactMetaResolver.items(
            context: ProjectGovernanceCompactMetaResolver.context(
                presentation: highRiskPresentation,
                displayStyle: configuration.displayStyle
            ),
            showAxisLegend: configuration.showAxisLegend,
            showCallout: true,
            displayStyle: configuration.displayStyle
        )

        #expect(highRiskItems.map(\.kind) == [.axisLegend, .callout])
        #expect(highRiskItems[1].text.contains("高风险组合"))
    }

    @Test
    func denseGovernanceSummarySurfacesExposeLatestGovernedRuntimeModelLine() {
        let presentation = ProjectGovernancePresentation(
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s3StrategicCoach,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1200,
            brainstormReviewSeconds: 2400,
            eventDrivenReviewEnabled: true
        )

        let items = ProjectGovernanceCompactMetaResolver.items(
            context: ProjectGovernanceCompactMetaResolver.context(
                presentation: presentation,
                displayStyle: .dense
            ),
            showAxisLegend: true,
            showCallout: true,
            displayStyle: .dense
        )

        #expect(items.first?.kind == .axisLegend)
        #expect(items[1].kind == .governanceModel)
        #expect(items[1].text.contains("双环治理"))
        #expect(items[1].text.contains("角色记忆"))
    }

    @Test
    func runtimeContractsMapPermissionDenyScopeFreezeAndReplay() {
        let presentation = GlobalHomePresentation.map(
            input: GlobalHomePresentationInput(
                hubInteractive: true,
                projectCount: 2,
                runningProjectCount: 1,
                pendingGrantCount: 0,
                highlightedProjectName: "Atlas",
                autoConfirmPolicy: "safe_plus_low_risk",
                autoLaunchPolicy: "mainline_only",
                grantGateMode: "fail_closed",
                directedUnblockBatonCount: 1,
                nextDirectedResumeAction: "continue_current_task_only",
                nextDirectedResumeLane: "XT-W3-26-F",
                scopeFreezeDecision: "no_go",
                scopeFreezeValidatedScope: ["XT-W3-23", "XT-W3-24", "XT-W3-25"],
                allowedPublicStatementCount: 3,
                scopeFreezeBlockedExpansionItems: ["future_ui_productization"],
                scopeFreezeNextActions: ["drop_scope_expansion"],
                deniedLaunchCount: 1,
                topLaunchDenyCode: "permission_denied",
                replayPass: false,
                replayScenarioCount: 4,
                replayFailClosedScenarioCount: 4,
                replayEvidenceRefs: ["build/reports/xt_w3_26_h_replay_regression_evidence.v1.json"]
            )
        )

        #expect(presentation.primaryStatus.state == .permissionDenied)
        #expect(presentation.primaryStatus.headline.contains("权限拒绝"))
        #expect(presentation.primaryStatus.userAction.contains("continue_current_task_only"))
        #expect(presentation.releaseStatus.state == .permissionDenied)
        #expect(presentation.releaseStatus.machineStatusRef.contains("freeze=no_go"))
        #expect(presentation.primaryStatus.highlights.contains("top_launch_issue=permission_denied"))
        #expect(presentation.consumedFrozenFields.contains("xt.unblock_baton.v1.next_action"))
        #expect(presentation.consumedFrozenFields.contains("xt.one_shot_autonomy_policy.v1.auto_launch_policy"))
        #expect(presentation.consumedFrozenFields.contains("xt.one_shot_replay_regression.v1.scenarios"))
    }

    @Test
    func launchDenyTaxonomyKeepsHomeFailClosedForModelConnectorPaidAndConnectivityIssues() {
        let modelNotReady = GlobalHomePresentation.map(
            input: GlobalHomePresentationInput(
                hubInteractive: true,
                projectCount: 1,
                runningProjectCount: 0,
                pendingGrantCount: 0,
                highlightedProjectName: "Atlas",
                deniedLaunchCount: 1,
                topLaunchDenyCode: "provider_not_ready"
            )
        )
        #expect(modelNotReady.primaryStatus.state == .diagnosticRequired)
        #expect(modelNotReady.primaryStatus.headline.contains("还没 ready"))
        #expect(modelNotReady.primaryStatus.userAction.contains("Supervisor"))
        #expect(modelNotReady.primaryStatus.hardLine == "模型链路恢复前，不继续推进")

        let connectorScopeBlocked = GlobalHomePresentation.map(
            input: GlobalHomePresentationInput(
                hubInteractive: true,
                projectCount: 1,
                runningProjectCount: 0,
                pendingGrantCount: 0,
                highlightedProjectName: "Atlas",
                deniedLaunchCount: 1,
                topLaunchDenyCode: "grant_required;deny_code=remote_export_blocked"
            )
        )
        #expect(connectorScopeBlocked.primaryStatus.state == .diagnosticRequired)
        #expect(connectorScopeBlocked.primaryStatus.headline.contains("安全边界"))
        #expect(connectorScopeBlocked.primaryStatus.userAction.contains("XT 设置 → 诊断"))
        #expect(connectorScopeBlocked.primaryStatus.hardLine == "安全边界解除前，不继续放行")

        let paidModelBlocked = GlobalHomePresentation.map(
            input: GlobalHomePresentationInput(
                hubInteractive: true,
                projectCount: 1,
                runningProjectCount: 0,
                pendingGrantCount: 0,
                highlightedProjectName: "Atlas",
                deniedLaunchCount: 1,
                topLaunchDenyCode: "device_paid_model_not_allowed"
            )
        )
        #expect(paidModelBlocked.primaryStatus.state == .diagnosticRequired)
        #expect(paidModelBlocked.primaryStatus.headline.contains("付费模型访问受阻"))
        #expect(paidModelBlocked.primaryStatus.userAction.contains("模型与付费访问"))
        #expect(paidModelBlocked.primaryStatus.hardLine == "付费模型访问恢复前，不继续放行")

        let connectivityBlocked = GlobalHomePresentation.map(
            input: GlobalHomePresentationInput(
                hubInteractive: true,
                projectCount: 1,
                runningProjectCount: 0,
                pendingGrantCount: 0,
                highlightedProjectName: "Atlas",
                deniedLaunchCount: 1,
                topLaunchDenyCode: "grpc_unavailable"
            )
        )
        #expect(connectivityBlocked.primaryStatus.state == .blockedWaitingUpstream)
        #expect(connectivityBlocked.primaryStatus.headline.contains("先修连接"))
        #expect(connectivityBlocked.primaryStatus.userAction.contains("XT 设置 → 连接 Hub"))
        #expect(connectivityBlocked.primaryStatus.hardLine == "连接恢复前，不继续推进")
    }

    @Test
    func projectHomeEntryControlsRouteThroughApprovalOrSupervisorOnly() {
        let pendingApproval = ProjectHomeEntryControlPresentation.make(
            pendingCount: 2,
            hubInteractive: true
        )
        #expect(pendingApproval.opensPendingApproval)
        #expect(pendingApproval.primaryActionTitle == "打开审批")
        #expect(pendingApproval.message.contains("不再直接发送新指令"))

        let connectedIdle = ProjectHomeEntryControlPresentation.make(
            pendingCount: 0,
            hubInteractive: true
        )
        #expect(!connectedIdle.opensPendingApproval)
        #expect(connectedIdle.primaryActionTitle == "去 Supervisor 建任务")
        #expect(connectedIdle.message.contains("统一从 Supervisor 发起"))

        let disconnectedIdle = ProjectHomeEntryControlPresentation.make(
            pendingCount: 0,
            hubInteractive: false
        )
        #expect(!disconnectedIdle.opensPendingApproval)
        #expect(disconnectedIdle.primaryActionTitle == "去 Supervisor 建任务")
        #expect(disconnectedIdle.message.contains("Hub 未连接"))
    }

    @Test
    func runtimeCaptureWritesXTW327ABCEvidenceWhenRequested() throws {
        guard let captureDir = ProcessInfo.processInfo.environment["XT_W3_27_CAPTURE_DIR"], !captureDir.isEmpty else {
            return
        }

        let base = URL(fileURLWithPath: captureDir)
        let presentationInput = GlobalHomePresentationInput(
            hubInteractive: true,
            projectCount: 2,
            runningProjectCount: 1,
            pendingGrantCount: 0,
            highlightedProjectName: "Helios"
        )
        let presentation = GlobalHomePresentation.map(input: presentationInput)

        let iaEvidence = XTW327AIAFreezeEvidence(
            claim: "XT-W3-27-A",
            informationArchitecture: XTUIInformationArchitectureContract.frozen,
            releaseScopeBadge: XTUIReleaseScopeBadgeContract.frozen,
            consumedFrozenFields: presentation.consumedFrozenFields
        )
        let tokenEvidence = XTW327BDesignTokensEvidence(
            claim: "XT-W3-27-B",
            designTokens: XTUIDesignTokenBundleContract.frozen,
            surfaceStateContract: XTUISurfaceStateContract.frozen,
            releaseScopeBadge: XTUIReleaseScopeBadgeContract.frozen
        )
        let homeEvidence = XTW327CGlobalHomeEvidence(
            claim: "XT-W3-27-C",
            input: presentationInput,
            presentation: presentation
        )

        try writeJSON(iaEvidence, to: base.appendingPathComponent("xt_w3_27_a_ia_freeze_evidence.v1.json"))
        try writeJSON(tokenEvidence, to: base.appendingPathComponent("xt_w3_27_b_design_tokens_evidence.v1.json"))
        try writeJSON(homeEvidence, to: base.appendingPathComponent("xt_w3_27_c_global_home_evidence.v1.json"))

        #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent("xt_w3_27_a_ia_freeze_evidence.v1.json").path))
        #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent("xt_w3_27_b_design_tokens_evidence.v1.json").path))
        #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent("xt_w3_27_c_global_home_evidence.v1.json").path))
    }

    private struct XTW327AIAFreezeEvidence: Codable, Equatable {
        let claim: String
        let informationArchitecture: XTUIInformationArchitectureContract
        let releaseScopeBadge: XTUIReleaseScopeBadgeContract
        let consumedFrozenFields: [String]

        enum CodingKeys: String, CodingKey {
            case claim
            case informationArchitecture = "information_architecture"
            case releaseScopeBadge = "release_scope_badge"
            case consumedFrozenFields = "consumed_frozen_fields"
        }
    }

    private struct XTW327BDesignTokensEvidence: Codable, Equatable {
        let claim: String
        let designTokens: XTUIDesignTokenBundleContract
        let surfaceStateContract: XTUISurfaceStateContract
        let releaseScopeBadge: XTUIReleaseScopeBadgeContract

        enum CodingKeys: String, CodingKey {
            case claim
            case designTokens = "design_tokens"
            case surfaceStateContract = "surface_state_contract"
            case releaseScopeBadge = "release_scope_badge"
        }
    }

    private struct XTW327CGlobalHomeEvidence: Codable, Equatable {
        let claim: String
        let input: GlobalHomePresentationInput
        let presentation: GlobalHomePresentation
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url)
    }
}
