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

        let modelGuide = UITroubleshootKnowledgeBase.guide(for: .modelNotReady)
        #expect(modelGuide.steps.first?.destination == .xtChooseModel)
        #expect(modelGuide.steps.map(\.destination).contains(.hubModels))
        #expect(modelGuide.steps.last?.destination == .xtDiagnostics)

        let connectorGuide = UITroubleshootKnowledgeBase.guide(for: .connectorScopeBlocked)
        #expect(connectorGuide.steps.first?.destination == .xtDiagnostics)
        #expect(connectorGuide.steps.map(\.destination).contains(.hubDiagnostics))
        #expect(connectorGuide.steps.last?.destination == .hubSecurity)

        let ambiguousGuide = UITroubleshootKnowledgeBase.guide(for: .multipleHubsAmbiguous)
        #expect(ambiguousGuide.steps.first?.destination == .xtPairHub)
        #expect(ambiguousGuide.steps.map(\.destination).contains(.hubLAN))

        let portConflictGuide = UITroubleshootKnowledgeBase.guide(for: .hubPortConflict)
        #expect(portConflictGuide.steps.first?.destination == .xtPairHub)
        #expect(portConflictGuide.steps.map(\.destination).contains(.hubLAN))

        let reachabilityGuide = UITroubleshootKnowledgeBase.guide(for: .hubUnreachable)
        #expect(reachabilityGuide.steps.first?.destination == .xtPairHub)
        #expect(reachabilityGuide.steps.map(\.destination).contains(.hubLAN))
        #expect(reachabilityGuide.steps.last?.destination == .hubDiagnostics)
    }

    @Test
    func troubleshootingCopyKeepsGrantLanguageTaskOriented() {
        let grantGuide = UITroubleshootKnowledgeBase.guide(for: .grantRequired)
        let permissionGuide = UITroubleshootKnowledgeBase.guide(for: .permissionDenied)
        let paidGuide = UITroubleshootKnowledgeBase.guide(for: .paidModelAccessBlocked)
        let modelGuide = UITroubleshootKnowledgeBase.guide(for: .modelNotReady)
        let connectorGuide = UITroubleshootKnowledgeBase.guide(for: .connectorScopeBlocked)

        #expect(grantGuide.summary.contains("能力范围与配额"))
        #expect(grantGuide.steps[1].instruction.contains("能力范围"))
        #expect(permissionGuide.summary.contains("安全边界"))
        #expect(permissionGuide.steps[1].instruction.contains("本地网络"))
        #expect(permissionGuide.steps[1].instruction.contains("client isolation"))
        #expect(paidGuide.summary.contains("设备信任、模型和预算"))
        #expect(modelGuide.steps[1].instruction.contains("REL Flow Hub → 模型与付费访问"))
        #expect(paidGuide.steps[2].instruction.contains("REL Flow Hub → 模型与付费访问"))
        #expect(connectorGuide.summary.contains("远端导出开关"))
        #expect(connectorGuide.steps[1].instruction.contains("REL Flow Hub → 诊断与恢复"))
    }

    @Test
    func hubUnreachableGuideExplainsMissingFormalRemoteEntry() {
        let guide = UITroubleshootKnowledgeBase.guide(
            for: .hubUnreachable,
            internetHost: ""
        )

        #expect(guide.summary.contains("没有正式远端入口"))
        #expect(guide.steps[0].instruction.contains("同一 Wi‑Fi"))
        #expect(guide.steps[1].instruction.contains("稳定主机名"))
        #expect(guide.steps.last?.destination == .hubDiagnostics)
    }

    @Test
    func hubUnreachableGuideExplainsLanOnlyAndRawIPEntriesDifferently() {
        let lanOnlyGuide = UITroubleshootKnowledgeBase.guide(
            for: .hubUnreachable,
            internetHost: "hub.local"
        )
        let rawIPGuide = UITroubleshootKnowledgeBase.guide(
            for: .hubUnreachable,
            internetHost: "17.81.11.116"
        )

        #expect(lanOnlyGuide.summary.contains("当前只有同网入口"))
        #expect(lanOnlyGuide.steps[0].instruction.contains("hub.local"))
        #expect(lanOnlyGuide.steps[1].instruction.contains(".local / localhost"))

        #expect(rawIPGuide.summary.contains("临时 raw IP"))
        #expect(rawIPGuide.steps[0].instruction.contains("17.81.11.116"))
        #expect(rawIPGuide.steps[1].instruction.contains("稳定命名入口"))
    }

    @Test
    func hubUnreachableGuideExplainsStableNamedEntryAsServiceOrForwardingFailure() {
        let guide = UITroubleshootKnowledgeBase.guide(
            for: .hubUnreachable,
            internetHost: "hub.tailnet.example"
        )

        #expect(guide.summary.contains("正式异网入口"))
        #expect(guide.steps[0].instruction.contains("hub.tailnet.example"))
        #expect(guide.steps[1].instruction.contains("没休眠"))
        #expect(guide.steps[1].instruction.contains("NAT"))
    }

    @Test
    func hubUnreachableGuideUsesProofToExplainLocalReadyRemoteVerificationPending() throws {
        let guide = UITroubleshootKnowledgeBase.guide(
            for: .hubUnreachable,
            internetHost: "",
            pairingContext: sampleTroubleshootPairingContext(
                readiness: .localReady,
                remoteShadowSmokeStatus: .running
            )
        )

        #expect(guide.summary.contains("同网首配已经完成"))
        #expect(guide.summary.contains("正在补跑正式异网验证"))
        #expect(guide.steps[0].instruction.contains("不要先清空当前配对"))
        #expect(guide.steps[1].instruction.contains("relay / tailnet / DNS"))
        #expect(guide.steps.last?.destination == .hubDiagnostics)
    }

    @Test
    func hubUnreachableGuideUsesProofToExplainRemoteDegradedAfterShadowFailure() throws {
        let guide = UITroubleshootKnowledgeBase.guide(
            for: .hubUnreachable,
            internetHost: "",
            pairingContext: sampleTroubleshootPairingContext(
                readiness: .remoteDegraded,
                remoteShadowSmokeStatus: .failed,
                remoteShadowReasonCode: "grpc_unavailable"
            )
        )

        #expect(guide.summary.contains("最近一次正式异网验证失败"))
        #expect(guide.summary.contains("grpc_unavailable"))
        #expect(guide.steps[0].instruction.contains("先保留现有配对资料"))
        #expect(guide.steps[1].instruction.contains("防火墙、NAT 或 relay"))
        #expect(guide.steps.last?.instruction.contains("reason code") == true)
    }

    @Test
    func pairingRepairGuideUsesProofToExplainRemoteBlockedByIdentityBoundary() throws {
        let guide = UITroubleshootKnowledgeBase.guide(
            for: .pairingRepairRequired,
            pairingContext: sampleTroubleshootPairingContext(
                readiness: .remoteBlocked,
                remoteShadowSmokeStatus: .failed,
                remoteShadowReasonCode: "unauthenticated"
            )
        )

        #expect(guide.summary.contains("pairing / identity 边界"))
        #expect(guide.steps[0].instruction.contains("清除配对后重连"))
        #expect(guide.steps[1].instruction.contains("删除旧设备条目"))
        #expect(guide.steps[2].instruction.contains("身份错误消失"))
    }

    @Test
    func repairEntryDetailUsesProofAwareRemoteDegradedRouting() throws {
        let detail = UITroubleshootKnowledgeBase.repairEntryDetail(
            for: .hubUnreachable,
            runtime: .empty,
            pairingContext: sampleTroubleshootPairingContext(
                readiness: .remoteDegraded,
                remoteShadowSmokeStatus: .failed,
                remoteShadowReasonCode: "grpc_unavailable"
            )
        )

        #expect(detail.contains("保留现有配对"))
        #expect(detail.contains("正式异网验证"))
    }

    @Test
    func troubleshootingRoutesAmbiguousDiscoveryAndPortConflictToDedicatedIssues() {
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "bonjour_multiple_hubs_ambiguous") == .multipleHubsAmbiguous)
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "lan_multiple_hubs_ambiguous") == .multipleHubsAmbiguous)
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "hub_port_conflict") == .hubPortConflict)
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "address already in use") == .hubPortConflict)
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "grpc_unavailable") == .hubUnreachable)
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "tcp_timeout") == .hubUnreachable)
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "connection_refused") == .hubUnreachable)
    }

    @Test
    func troubleshootingRoutesModelReadinessFailuresToDedicatedIssue() {
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "blocked_waiting_upstream") == .modelNotReady)
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "provider_not_ready") == .modelNotReady)
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "model_not_found") == .modelNotReady)
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "remote_model_not_found") == .modelNotReady)
    }

    @Test
    func troubleshootingRoutesConnectorScopeFailuresToDedicatedIssue() {
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "remote_export_blocked") == .connectorScopeBlocked)
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "device_remote_export_denied") == .connectorScopeBlocked)
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "policy_remote_denied") == .connectorScopeBlocked)
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "budget_remote_denied") == .connectorScopeBlocked)
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "remote_disabled_by_user_pref") == .connectorScopeBlocked)
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "grant_required;deny_code=remote_export_blocked") == .connectorScopeBlocked)
    }

    @Test
    func modelReadinessIssueUsesSharedRepairActionsAcrossWizardAndSettings() {
        let doctor = XTUnifiedDoctorBuilder.build(
            input: makeTroubleshootingDoctorInput(failureCode: "provider_not_ready")
        )
        let wizardPlan = UIFirstRunJourneyPlanner.plan(
            for: HubSetupWizardState(
                localConnected: true,
                remoteConnected: false,
                linking: false,
                configuredModelRoles: 1,
                totalModelRoles: AXRole.allCases.count,
                failureCode: "provider_not_ready",
                runtime: .empty,
                doctor: doctor
            )
        )
        let settingsState = XTSettingsSurfaceState(
            hubConnected: true,
            remoteConnected: false,
            linking: false,
            localServerEnabled: true,
            serverRunning: true,
            failureCode: "provider_not_ready",
            runtime: .empty,
            doctor: doctor
        )
        let settingsActions = XTSettingsSurfacePlanner.quickActions(for: settingsState)

        #expect(wizardPlan.currentFailureIssue == .modelNotReady)
        #expect(wizardPlan.primaryStatus.state == .diagnosticRequired)
        #expect(wizardPlan.steps[2].state == .diagnosticRequired)
        #expect(wizardPlan.steps[2].repairEntry == .xtChooseModel)
        #expect(wizardPlan.actions.first?.id == "connect_hub")
        #expect(wizardPlan.actions.first?.title == "连接 Hub")
        #expect(wizardPlan.actions.first?.subtitle == "Hub 已连通；需要重试或改参数时看下方连接进度")
        #expect(wizardPlan.actions.last?.id == "open_repair_entry")
        #expect(wizardPlan.actions.last?.title == "查看授权与排障")
        #expect(wizardPlan.actions.last?.subtitle == "模型未就绪；先打开排障入口")

        #expect(settingsActions.first?.id == "connect_hub")
        #expect(settingsActions.first?.title == "连接 Hub")
        #expect(settingsActions.first?.subtitle == "Hub 已连通；需要改参数或修复时看下方连接区")
        #expect(settingsActions.last?.id == "open_repair_entry")
        #expect(settingsActions.last?.title == "查看授权与排障")
        #expect(settingsActions.last?.subtitle == "模型未就绪；先打开排障入口")
        #expect(UITroubleshootDestination.hubModels.label == "REL Flow Hub → 模型与付费访问")
        #expect(UITroubleshootDestination.hubLAN.label == "REL Flow Hub → 网络连接")
        #expect(UITroubleshootDestination.hubPairing.label == "REL Flow Hub → 配对与设备信任")
        #expect(UITroubleshootDestination.hubGrants.label == "REL Flow Hub → 授权与权限")
        #expect(UITroubleshootDestination.homeSupervisor.label == "首页 / Supervisor → 开始第一个任务")
        #expect(
            UITroubleshootKnowledgeBase.repairEntryDetail(
                for: .modelNotReady,
                runtime: .empty
            ).contains("REL Flow Hub 检查模型清单和提供方状态")
        )
    }

    @Test
    func connectorScopeIssueUsesSharedRepairActionsAcrossWizardAndSettings() {
        let doctor = XTUnifiedDoctorBuilder.build(
            input: makeTroubleshootingDoctorInput(failureCode: "grant_required;deny_code=remote_export_blocked")
        )
        let wizardPlan = UIFirstRunJourneyPlanner.plan(
            for: HubSetupWizardState(
                localConnected: true,
                remoteConnected: true,
                linking: false,
                configuredModelRoles: 1,
                totalModelRoles: AXRole.allCases.count,
                failureCode: "grant_required;deny_code=remote_export_blocked",
                runtime: .empty,
                doctor: doctor
            )
        )
        let settingsState = XTSettingsSurfaceState(
            hubConnected: true,
            remoteConnected: true,
            linking: false,
            localServerEnabled: true,
            serverRunning: true,
            failureCode: "grant_required;deny_code=remote_export_blocked",
            runtime: .empty,
            doctor: doctor
        )
        let settingsActions = XTSettingsSurfacePlanner.quickActions(for: settingsState)

        #expect(wizardPlan.currentFailureIssue == .connectorScopeBlocked)
        #expect(wizardPlan.primaryStatus.state == .diagnosticRequired)
        #expect(wizardPlan.steps[2].state == .diagnosticRequired)
        #expect(wizardPlan.steps[2].repairEntry == .hubDiagnostics)
        #expect(wizardPlan.actions.first?.id == "connect_hub")
        #expect(wizardPlan.actions.first?.title == "连接 Hub")
        #expect(wizardPlan.actions.first?.subtitle == "Hub 已连通；需要重试或改参数时看下方连接进度")
        #expect(wizardPlan.actions.last?.id == "open_repair_entry")
        #expect(wizardPlan.actions.last?.title == "查看授权与排障")
        #expect(wizardPlan.actions.last?.subtitle == "XT 诊断与核对记下实际路由记录 / 审计编号 / 拒绝原因 -> Hub 排障查看远端导出开关 -> 按安全边界或预算入口修复")

        #expect(settingsActions.first?.id == "connect_hub")
        #expect(settingsActions.first?.title == "连接 Hub")
        #expect(settingsActions.first?.subtitle == "Hub 已连通；需要改参数或修复时看下方连接区")
        #expect(settingsActions.last?.id == "open_repair_entry")
        #expect(settingsActions.last?.title == "查看授权与排障")
        #expect(settingsActions.last?.subtitle == "XT 诊断与核对记下实际路由记录 / 审计编号 / 拒绝原因 -> Hub 排障查看远端导出开关 -> 按安全边界或预算入口修复")
    }

    @Test
    func localNetworkBlockedPermissionStatusExplainsDualFailureAcrossWizardAndSettings() {
        XTHubLaunchStatusStore.installLoadOverrideForTesting { _ in
            XTHubLaunchStatusSnapshot(
                state: "DEGRADED_SERVING",
                degraded: XTHubLaunchStatusSnapshot.Degraded(
                    blockedCapabilities: ["ai.generate.paid", "web.fetch"],
                    isDegraded: true
                ),
                rootCause: XTHubLaunchStatusSnapshot.RootCause(
                    component: "bridge",
                    detail: "Bridge 心跳已过期或当前不可用",
                    errorCode: "XHUB_BRIDGE_UNAVAILABLE"
                )
            )
        }
        defer { XTHubLaunchStatusStore.installLoadOverrideForTesting(nil) }

        let failureCode = "local_network_discovery_blocked"
        let doctor = XTUnifiedDoctorBuilder.build(
            input: makeTroubleshootingDoctorInput(failureCode: failureCode)
        )
        let wizardPlan = UIFirstRunJourneyPlanner.plan(
            for: HubSetupWizardState(
                localConnected: true,
                remoteConnected: false,
                linking: false,
                configuredModelRoles: 1,
                totalModelRoles: AXRole.allCases.count,
                failureCode: failureCode,
                runtime: .empty,
                doctor: doctor
            )
        )
        let settingsState = XTSettingsSurfaceState(
            hubConnected: true,
            remoteConnected: false,
            linking: false,
            localServerEnabled: true,
            serverRunning: true,
            failureCode: failureCode,
            runtime: .empty,
            doctor: doctor
        )
        let settingsStatus = XTSettingsSurfacePlanner.status(for: settingsState)
        let settingsActions = XTSettingsSurfacePlanner.quickActions(for: settingsState)

        #expect(wizardPlan.primaryStatus.state == .permissionDenied)
        #expect(wizardPlan.primaryStatus.headline.contains("loopback Hub"))
        #expect(wizardPlan.primaryStatus.whyItHappened.contains("XHUB_BRIDGE_UNAVAILABLE"))
        #expect(wizardPlan.primaryStatus.highlights.contains("remote_lan_blocked=true"))
        #expect(wizardPlan.primaryStatus.highlights.contains("local_hub_root_cause=XHUB_BRIDGE_UNAVAILABLE"))
        #expect(wizardPlan.primaryStatus.highlights.contains("local_hub_blocked_capabilities=ai.generate.paid,web.fetch"))

        #expect(settingsStatus.state == .permissionDenied)
        #expect(settingsStatus.headline.contains("loopback Hub"))
        #expect(settingsStatus.whyItHappened.contains("XHUB_BRIDGE_UNAVAILABLE"))
        #expect(settingsStatus.highlights.contains("local_hub_root_cause=XHUB_BRIDGE_UNAVAILABLE"))
        #expect(settingsActions.last?.subtitle?.contains("Diagnostics & Recovery") == true)
        #expect(settingsActions.last?.subtitle?.contains("ai.generate.paid,web.fetch") == true)
    }

    @Test
    func connectedRouteSummaryFeedsWizardAndSettingsTopLevelCopy() {
        let summary = "当前已完成同网首配，但正式异网入口仍未完成验证。"
        let doctor = makeTroubleshootingDoctorWithPairedRouteSummary(
            summaryLine: summary,
            readiness: .localReady,
            localConnected: true,
            remoteConnected: false
        )
        let wizardPlan = UIFirstRunJourneyPlanner.plan(
            for: HubSetupWizardState(
                localConnected: true,
                remoteConnected: false,
                linking: false,
                configuredModelRoles: 1,
                totalModelRoles: AXRole.allCases.count,
                failureCode: "",
                runtime: .empty,
                doctor: doctor
            )
        )
        let settingsState = XTSettingsSurfaceState(
            hubConnected: true,
            remoteConnected: false,
            linking: false,
            localServerEnabled: true,
            serverRunning: true,
            failureCode: "",
            runtime: .empty,
            doctor: doctor
        )
        let settingsStatus = XTSettingsSurfacePlanner.status(for: settingsState)
        let settingsActions = XTSettingsSurfacePlanner.quickActions(for: settingsState)

        #expect(wizardPlan.primaryStatus.headline == summary)
        #expect(wizardPlan.actions.first?.subtitle == summary)
        #expect(settingsStatus.headline == summary)
        #expect(settingsActions.first?.subtitle == summary)
    }

    @Test
    func highFrequencyTroubleshootCatalogIncludesNewFailClosedIssueTypes() {
        let issues = UITroubleshootIssue.highFrequencyIssues

        #expect(issues.contains(.modelNotReady))
        #expect(issues.contains(.connectorScopeBlocked))
        #expect(issues.contains(.paidModelAccessBlocked))
        #expect(issues.contains(.hubUnreachable))
        #expect(Set(issues).count == issues.count)
    }

    @Test
    func pairingRepairClosuresStayAlignedAcrossGuideWizardSettingsAndDoctor() throws {
        var scenarios: [PairingRepairClosureScenarioEvidence] = []
        for spec in pairingRepairClosureScenarioSpecs() {
            let mappedIssue = UITroubleshootKnowledgeBase.issue(forFailureCode: spec.failureCode)
            #expect(mappedIssue == spec.expectedIssue)

            let guide = UITroubleshootKnowledgeBase.guide(for: spec.expectedIssue)
            let doctor = XTUnifiedDoctorBuilder.build(
                input: makeTroubleshootingDoctorInput(failureCode: spec.failureCode)
            )
            let wizardPlan = UIFirstRunJourneyPlanner.plan(
                for: HubSetupWizardState(
                    localConnected: false,
                    remoteConnected: false,
                    linking: false,
                    configuredModelRoles: 0,
                    totalModelRoles: AXRole.allCases.count,
                    failureCode: spec.failureCode,
                    runtime: .empty,
                    doctor: doctor
                )
            )
            let settingsState = XTSettingsSurfaceState(
                hubConnected: false,
                remoteConnected: false,
                linking: false,
                localServerEnabled: true,
                serverRunning: false,
                failureCode: spec.failureCode,
                runtime: .empty,
                doctor: doctor
            )
            let settingsActions = XTSettingsSurfacePlanner.quickActions(for: settingsState)
            let doctorSection = try #require(doctor.section(.hubReachability))
            let wizardPrimaryAction = try #require(wizardPlan.actions.first)
            let settingsPrimaryAction = try #require(settingsActions.first)
            let wizardRepairAction = try #require(wizardPlan.actions.last)
            let settingsRepairAction = try #require(settingsActions.last)
            let expectedRepairEntryDetail = UITroubleshootKnowledgeBase.repairEntryDetail(
                for: spec.expectedIssue,
                runtime: .empty
            )

            #expect(guide.steps.map(\.destination.rawValue) == spec.expectedGuideDestinations)
            #expect(wizardPlan.currentFailureIssue == spec.expectedIssue)
            #expect(wizardPrimaryAction.id == spec.expectedPrimaryActionID)
            #expect(wizardPrimaryAction.title == spec.expectedPrimaryActionTitle)
            #expect(settingsPrimaryAction.id == spec.expectedPrimaryActionID)
            #expect(settingsPrimaryAction.title == spec.expectedPrimaryActionTitle)
            #expect(wizardRepairAction.id == spec.expectedRepairActionID)
            #expect(settingsRepairAction.id == spec.expectedRepairActionID)
            #expect(wizardRepairAction.title == spec.expectedRepairActionTitle)
            #expect(settingsRepairAction.title == spec.expectedRepairActionTitle)
            #expect(wizardRepairAction.subtitle == .some(expectedRepairEntryDetail))
            #expect(settingsRepairAction.subtitle == .some(expectedRepairEntryDetail))
            #expect(doctorSection.headline == spec.expectedDoctorHeadline)
            #expect(doctorSection.nextStep.contains(spec.expectedDoctorNextStepSubstring))

            scenarios.append(PairingRepairClosureScenarioEvidence(
                failureCode: spec.failureCode,
                mappedIssue: spec.expectedIssue.rawValue,
                guideDestinations: guide.steps.map(\.destination.rawValue),
                wizardPrimaryActionID: wizardPrimaryAction.id,
                wizardPrimaryActionTitle: wizardPrimaryAction.title,
                settingsPrimaryActionID: settingsPrimaryAction.id,
                settingsPrimaryActionTitle: settingsPrimaryAction.title,
                repairEntryTitle: wizardRepairAction.title,
                repairEntryDetail: expectedRepairEntryDetail,
                doctorHeadline: doctorSection.headline,
                doctorNextStep: doctorSection.nextStep,
                doctorRepairEntry: doctorSection.repairEntry.rawValue
            ))
        }

        guard let captureDir = ProcessInfo.processInfo.environment["XHUB_DOCTOR_XT_PAIRING_REPAIR_CAPTURE_DIR"],
              !captureDir.isEmpty else {
            return
        }

        let base = URL(fileURLWithPath: captureDir, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let evidence = PairingRepairClosureEvidence(
            schemaVersion: "xt.doctor_pairing_repair_closure_evidence.v1",
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            status: "pass",
            scenarios: scenarios
        )
        let destination = base.appendingPathComponent("xt_doctor_pairing_repair_closure_evidence.v1.json")
        try writeTroubleshootingJSON(evidence, to: destination)
        #expect(FileManager.default.fileExists(atPath: destination.path))
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
        #expect(XTSettingsCenterManifest.sections[1].title == "AI 模型主入口")
        #expect(XTSettingsCenterManifest.sections[1].summary.contains("Supervisor Control Center · AI 模型"))
        #expect(XTSettingsCenterManifest.sections[1].repairEntry == "Supervisor Control Center → AI 模型")
        #expect(XTSettingsCenterManifest.consumedFrozenFields.contains("xt.ui_information_architecture.v1"))
        #expect(XTSettingsCenterManifest.consumedFrozenFields.contains("xt.delivery_scope_freeze.v1.validated_scope"))
        #expect(XTSettingsCenterManifest.consumedFrozenFields.contains("xt.unblock_baton.v1"))
        #expect(XTSettingsCenterManifest.consumedFrozenFields.contains("xt.one_shot_replay_regression.v1"))

        let workspaceRoot = monorepoTestRepoRoot()
        let hubSettingsPath = workspaceRoot
            .appendingPathComponent("x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift")
        let hubStringsPath = workspaceRoot
            .appendingPathComponent("x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubUIStrings.swift")
        let hubCardPath = workspaceRoot
            .appendingPathComponent("x-hub/macos/RELFlowHub/Sources/RELFlowHub/UI/HubSectionCard.swift")

        let hubSettingsSource = try String(contentsOf: hubSettingsPath, encoding: .utf8)
        #expect(hubSettingsSource.contains("Section(HubUIStrings.Settings.Overview.sectionTitle)"))
        #expect(hubSettingsSource.contains("Section(HubUIStrings.Settings.FirstRun.sectionTitle)"))
        #expect(hubSettingsSource.contains("Section(HubUIStrings.Settings.Troubleshoot.sectionTitle)"))

        let hubStringsSource = try String(contentsOf: hubStringsPath, encoding: .utf8)
        #expect(hubStringsSource.contains("static let sectionTitle = \"设置总览\""))
        #expect(hubStringsSource.contains("static let sectionTitle = \"首次上手路径\""))
        #expect(hubStringsSource.contains("static let sectionTitle = \"三步排障\""))
        #expect(hubStringsSource.contains("static let title = \"配对 Hub\""))
        #expect(hubStringsSource.contains("static let title = \"模型与付费访问\""))
        #expect(hubStringsSource.contains("static let title = \"授权与权限\""))
        #expect(hubStringsSource.contains("static let title = \"安全边界\""))
        #expect(hubStringsSource.contains("static let title = \"诊断与恢复\""))
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
        #expect(actions.map(\.id) == ["connect_hub", "run_smoke", "open_repair_entry"])
        #expect(actions.first(where: { $0.id == "run_smoke" })?.subtitle == "自检没通过；先看回放结果和诊断")
        #expect(actions.first(where: { $0.id == "open_repair_entry" })?.subtitle?.contains("grant_required") == true)
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

private func sampleTroubleshootPairingContext(
    readiness: XTPairedRouteReadiness,
    remoteShadowSmokeStatus: XTFirstPairRemoteShadowSmokeStatus,
    stableRemoteHost: String = "hub.tailnet.example",
    remoteShadowReasonCode: String? = nil
) -> UITroubleshootPairingContext {
    UITroubleshootPairingContext(
        firstPairCompletionProofSnapshot: XTFirstPairCompletionProofSnapshot(
            generatedAtMs: 1_741_300_000_000,
            readiness: readiness,
            sameLanVerified: true,
            ownerLocalApprovalVerified: true,
            pairingMaterialIssued: true,
            cachedReconnectSmokePassed: true,
            stableRemoteRoutePresent: true,
            remoteShadowSmokePassed: remoteShadowSmokeStatus == .passed,
            remoteShadowSmokeStatus: remoteShadowSmokeStatus,
            remoteShadowSmokeSource: remoteShadowSmokeStatus == .notRun ? nil : .dedicatedStableRemoteProbe,
            remoteShadowTriggeredAtMs: remoteShadowSmokeStatus == .notRun ? nil : 1_741_300_100_000,
            remoteShadowCompletedAtMs: remoteShadowSmokeStatus == .running ? nil : 1_741_300_120_000,
            remoteShadowRoute: remoteShadowSmokeStatus == .notRun ? nil : .internet,
            remoteShadowReasonCode: remoteShadowReasonCode,
            remoteShadowSummary: remoteShadowReasonCode.map { "verification failed with \($0)" },
            summaryLine: "pairing proof"
        ),
        pairedRouteSetSnapshot: XTPairedRouteSetSnapshot(
            readiness: readiness,
            readinessReasonCode: readiness.rawValue,
            summaryLine: "paired route set",
            hubInstanceID: "hub-1",
            activeRoute: nil,
            lanRoute: XTPairedRouteTargetSnapshot(
                routeKind: .lan,
                host: "10.0.0.8",
                pairingPort: 50052,
                grpcPort: 50051,
                hostKind: "private_ipv4",
                source: .cachedProfileHost
            ),
            stableRemoteRoute: XTPairedRouteTargetSnapshot(
                routeKind: .internet,
                host: stableRemoteHost,
                pairingPort: 50052,
                grpcPort: 50051,
                hostKind: "stable_named",
                source: .cachedProfileInternetHost
            ),
            lastKnownGoodRoute: nil,
            cachedReconnectSmokeStatus: "succeeded",
            cachedReconnectSmokeReasonCode: nil,
            cachedReconnectSmokeSummary: "cached route verified"
        )
    )!
}

private struct PairingRepairClosureScenarioSpec {
    let failureCode: String
    let expectedIssue: UITroubleshootIssue
    let expectedGuideDestinations: [String]
    let expectedPrimaryActionID: String
    let expectedPrimaryActionTitle: String
    let expectedRepairActionID: String
    let expectedRepairActionTitle: String
    let expectedDoctorHeadline: String
    let expectedDoctorNextStepSubstring: String
}

private struct PairingRepairClosureScenarioEvidence: Codable, Equatable {
    let failureCode: String
    let mappedIssue: String
    let guideDestinations: [String]
    let wizardPrimaryActionID: String
    let wizardPrimaryActionTitle: String
    let settingsPrimaryActionID: String
    let settingsPrimaryActionTitle: String
    let repairEntryTitle: String
    let repairEntryDetail: String
    let doctorHeadline: String
    let doctorNextStep: String
    let doctorRepairEntry: String

    enum CodingKeys: String, CodingKey {
        case failureCode = "failure_code"
        case mappedIssue = "mapped_issue"
        case guideDestinations = "guide_destinations"
        case wizardPrimaryActionID = "wizard_primary_action_id"
        case wizardPrimaryActionTitle = "wizard_primary_action_title"
        case settingsPrimaryActionID = "settings_primary_action_id"
        case settingsPrimaryActionTitle = "settings_primary_action_title"
        case repairEntryTitle = "repair_entry_title"
        case repairEntryDetail = "repair_entry_detail"
        case doctorHeadline = "doctor_headline"
        case doctorNextStep = "doctor_next_step"
        case doctorRepairEntry = "doctor_repair_entry"
    }
}

private struct PairingRepairClosureEvidence: Codable, Equatable {
    let schemaVersion: String
    let generatedAt: String
    let status: String
    let scenarios: [PairingRepairClosureScenarioEvidence]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case status
        case scenarios
    }
}

private func pairingRepairClosureScenarioSpecs() -> [PairingRepairClosureScenarioSpec] {
    [
        PairingRepairClosureScenarioSpec(
            failureCode: "discovery_failed",
            expectedIssue: .hubUnreachable,
            expectedGuideDestinations: [
                UITroubleshootDestination.xtPairHub.rawValue,
                UITroubleshootDestination.hubLAN.rawValue,
                UITroubleshootDestination.hubDiagnostics.rawValue
            ],
            expectedPrimaryActionID: "connect_hub",
            expectedPrimaryActionTitle: "连接 Hub",
            expectedRepairActionID: "open_repair_entry",
            expectedRepairActionTitle: "查看授权与排障",
            expectedDoctorHeadline: "Hub 暂时不可达，但正式异网入口已配置",
            expectedDoctorNextStepSubstring: "防火墙"
        ),
        PairingRepairClosureScenarioSpec(
            failureCode: "pairing_health_failed",
            expectedIssue: .pairingRepairRequired,
            expectedGuideDestinations: [
                UITroubleshootDestination.xtPairHub.rawValue,
                UITroubleshootDestination.hubPairing.rawValue,
                UITroubleshootDestination.hubDiagnostics.rawValue
            ],
            expectedPrimaryActionID: "connect_hub",
            expectedPrimaryActionTitle: "连接 Hub",
            expectedRepairActionID: "open_repair_entry",
            expectedRepairActionTitle: "查看授权与排障",
            expectedDoctorHeadline: "现有配对档案已失效，需要清理并重配",
            expectedDoctorNextStepSubstring: "清除配对后重连"
        ),
        PairingRepairClosureScenarioSpec(
            failureCode: "discover_failed_using_cached_profile",
            expectedIssue: .pairingRepairRequired,
            expectedGuideDestinations: [
                UITroubleshootDestination.xtPairHub.rawValue,
                UITroubleshootDestination.hubPairing.rawValue,
                UITroubleshootDestination.hubDiagnostics.rawValue
            ],
            expectedPrimaryActionID: "connect_hub",
            expectedPrimaryActionTitle: "连接 Hub",
            expectedRepairActionID: "open_repair_entry",
            expectedRepairActionTitle: "查看授权与排障",
            expectedDoctorHeadline: "现有配对档案已失效，需要清理并重配",
            expectedDoctorNextStepSubstring: "清除配对后重连"
        ),
        PairingRepairClosureScenarioSpec(
            failureCode: "hub_port_conflict",
            expectedIssue: .hubPortConflict,
            expectedGuideDestinations: [
                UITroubleshootDestination.xtPairHub.rawValue,
                UITroubleshootDestination.hubLAN.rawValue,
                UITroubleshootDestination.xtDiagnostics.rawValue
            ],
            expectedPrimaryActionID: "connect_hub",
            expectedPrimaryActionTitle: "连接 Hub",
            expectedRepairActionID: "open_repair_entry",
            expectedRepairActionTitle: "查看授权与排障",
            expectedDoctorHeadline: "Hub 端口冲突，必须先修复网络端口",
            expectedDoctorNextStepSubstring: "空闲端口"
        ),
        PairingRepairClosureScenarioSpec(
            failureCode: "bonjour_multiple_hubs_ambiguous",
            expectedIssue: .multipleHubsAmbiguous,
            expectedGuideDestinations: [
                UITroubleshootDestination.xtPairHub.rawValue,
                UITroubleshootDestination.hubLAN.rawValue,
                UITroubleshootDestination.xtDiagnostics.rawValue
            ],
            expectedPrimaryActionID: "connect_hub",
            expectedPrimaryActionTitle: "连接 Hub",
            expectedRepairActionID: "open_repair_entry",
            expectedRepairActionTitle: "查看授权与排障",
            expectedDoctorHeadline: "发现到多台 Hub，必须先固定目标",
            expectedDoctorNextStepSubstring: "固定一台目标 Hub"
        )
    ]
}

private func makeTroubleshootingDoctorInput(failureCode: String) -> XTUnifiedDoctorInput {
    XTUnifiedDoctorInput(
        generatedAt: Date(timeIntervalSince1970: 1_741_300_000),
        localConnected: false,
        remoteConnected: false,
        remoteRoute: .none,
        linking: false,
        pairingPort: 50052,
        grpcPort: 50051,
        internetHost: "hub.example.test",
        configuredModelIDs: [],
        totalModelRoles: AXRole.allCases.count,
        failureCode: failureCode,
        runtime: .empty,
        runtimeStatus: nil,
        modelsState: ModelStateSnapshot.empty(),
        bridgeAlive: false,
        bridgeEnabled: false,
        sessionID: nil,
        sessionTitle: nil,
        sessionRuntime: nil,
        skillsSnapshot: .empty
    )
}

private func makeTroubleshootingDoctorWithPairedRouteSummary(
    summaryLine: String,
    readiness: XTPairedRouteReadiness,
    localConnected: Bool,
    remoteConnected: Bool
) -> XTUnifiedDoctorReport {
    let lanRoute = localConnected
        ? XTPairedRouteTargetSnapshot(
            routeKind: .lan,
            host: "10.0.0.8",
            pairingPort: 50052,
            grpcPort: 50051,
            hostKind: "private_ipv4",
            source: .cachedProfileHost
        )
        : nil
    let stableRemoteRoute = XTPairedRouteTargetSnapshot(
        routeKind: .internet,
        host: "hub.tailnet.example",
        pairingPort: 50052,
        grpcPort: 50051,
        hostKind: "stable_named",
        source: .cachedProfileInternetHost
    )

    return XTUnifiedDoctorBuilder.build(
        input: XTUnifiedDoctorInput(
            generatedAt: Date(timeIntervalSince1970: 1_741_300_000),
            localConnected: localConnected,
            remoteConnected: remoteConnected,
            remoteRoute: remoteConnected ? .internet : .none,
            linking: false,
            pairingPort: 50052,
            grpcPort: 50051,
            internetHost: stableRemoteRoute.host,
            configuredModelIDs: [],
            totalModelRoles: AXRole.allCases.count,
            failureCode: "",
            runtime: .empty,
            runtimeStatus: nil,
            modelsState: ModelStateSnapshot.empty(),
            bridgeAlive: false,
            bridgeEnabled: false,
            sessionID: nil,
            sessionTitle: nil,
            sessionRuntime: nil,
            skillsSnapshot: .empty,
            pairedRouteSetSnapshot: XTPairedRouteSetSnapshot(
                readiness: readiness,
                readinessReasonCode: readiness.rawValue,
                summaryLine: summaryLine,
                hubInstanceID: "hub-1",
                activeRoute: localConnected ? lanRoute : stableRemoteRoute,
                lanRoute: lanRoute,
                stableRemoteRoute: stableRemoteRoute,
                lastKnownGoodRoute: localConnected ? lanRoute : stableRemoteRoute,
                cachedReconnectSmokeStatus: localConnected ? "succeeded" : "not_run",
                cachedReconnectSmokeReasonCode: nil,
                cachedReconnectSmokeSummary: localConnected ? "same-LAN path verified" : nil
            )
        )
    )
}

private func writeTroubleshootingJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: url, options: .atomic)
}
