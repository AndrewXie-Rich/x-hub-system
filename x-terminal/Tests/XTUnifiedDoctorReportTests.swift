import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
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
        #expect(report.section(.modelRouteReadiness)?.headline == "配对已通，但模型路由不可用")
        #expect(report.section(.modelRouteReadiness)?.nextStep.contains("Supervisor Control Center · AI 模型") == true)
        #expect(report.readyForFirstTask == false)
    }

    @Test
    func providerPartialReadinessIsCarriedIntoDoctorModelRouteCopy() {
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [],
                models: [],
                runtimeStatus: makeProviderAwareDoctorRuntimeStatus(
                    readyProviderIDs: ["transformers"],
                    providers: [
                        "mlx": ["ok": false, "reason_code": "runtime_missing"],
                        "transformers": ["ok": true, "available_task_kinds": ["text_generate"]]
                    ]
                ),
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot()
            )
        )

        let section = report.section(.modelRouteReadiness)
        #expect(section?.state == .diagnosticRequired)
        #expect(section?.headline == "本地 provider 只有部分就绪，当前模型清单可能缺项")
        #expect(section?.detailLines.contains("runtime_provider_state=provider_partial_readiness") == true)
        #expect(section?.detailLines.contains("ready_providers=transformers") == true)
    }

    @Test
    func remoteDoctorModelRouteStaysReadyButShowsNoLocalFallback() {
        let remoteModel = HubModel(
            id: "hub.remote.coder",
            name: "hub.remote.coder",
            backend: "openai",
            quant: "hosted",
            contextLength: 128_000,
            paramsB: 0,
            roles: ["coder"],
            state: .loaded,
            memoryBytes: nil,
            tokensPerSec: nil,
            modelPath: nil,
            note: nil,
            taskKinds: ["text_generate"],
            outputModalities: ["text"]
        )
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: false,
                remoteConnected: true,
                configuredModelIDs: [remoteModel.id],
                models: [remoteModel],
                runtimeStatus: makeProviderAwareDoctorRuntimeStatus(
                    readyProviderIDs: [],
                    providers: [
                        "mlx": ["ok": false, "reason_code": "runtime_missing"]
                    ]
                ),
                bridgeAlive: false,
                bridgeEnabled: false,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot()
            )
        )

        let section = report.section(.modelRouteReadiness)
        #expect(section?.state == .ready)
        #expect(section?.headline == "模型路由已就绪（当前无本地兜底）")
        #expect(section?.summary.contains("远端失联时不会有本地兜底") == true)
        #expect(section?.detailLines.contains("interactive_posture=remote_only") == true)
        #expect(section?.detailLines.contains("ready_providers=none") == true)
        #expect(report.readyForFirstTask == true)
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
        #expect(report.section(.bridgeToolReadiness)?.headline == "模型路由已通，但桥接 / 工具链路不可用")
    }

    @Test
    func remoteGrpcRouteDoesNotRequireLocalBridgeHeartbeat() {
        let model = sampleModel(id: "hub.model.coder")
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: false,
                remoteConnected: true,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: false,
                bridgeEnabled: false,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot()
            )
        )

        #expect(report.section(.modelRouteReadiness)?.state == .ready)
        #expect(report.section(.bridgeToolReadiness)?.state == .ready)
        #expect(report.section(.bridgeToolReadiness)?.headline == "远端 Hub 工具主链已就绪")
        #expect(report.section(.sessionRuntimeReadiness)?.state == .ready)
        #expect(report.readyForFirstTask == true)
    }

    @Test
    func remotePaidAccessProjectionPublishesBudgetTruthWhenReportedByPairedDevice() {
        let model = sampleModel(id: "hub.model.coder")
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: false,
                remoteConnected: true,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: false,
                bridgeEnabled: false,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                remotePaidAccessSnapshot: HubRemotePaidAccessSnapshot(
                    trustProfilePresent: true,
                    paidModelPolicyMode: "all_paid_models",
                    dailyTokenLimit: 640,
                    singleRequestTokenLimit: 256
                )
            )
        )

        #expect(report.remotePaidAccessProjection?.trustProfilePresent == true)
        #expect(report.remotePaidAccessProjection?.policyMode == "all_paid_models")
        #expect(report.remotePaidAccessProjection?.compactBudgetLine == "单次 256 tok · 当日 640 tok · 策略 全部付费模型")
    }

    @Test
    func remotePaidAccessProjectionExplainsLegacyGrantWhenTrustProfileIsMissing() {
        let projection = XTUnifiedDoctorRemotePaidAccessProjection(
            trustProfilePresent: false,
            policyMode: "legacy_grant",
            dailyTokenLimit: 0,
            singleRequestTokenLimit: 0
        )

        #expect(projection.compactBudgetLine == "仍走旧授权路径 · 策略 旧版授权")
    }

    @Test
    func localOnlyModelRouteIsReportedAsHealthyReadyPosture() {
        let model = sampleModel(id: "hub.model.coder")
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot()
            )
        )

        let section = report.section(.modelRouteReadiness)
        #expect(section?.state == .ready)
        #expect(section?.headline == "模型路由已就绪（纯本地）")
        #expect(section?.summary.contains("没有云端服务或 API key") == true)
        #expect(section?.detailLines.contains("interactive_posture=local_only") == true)
        #expect(report.readyForFirstTask == true)
        #expect(report.overallSummary.contains("当前走纯本地路径") == true)
    }

    @Test
    func readySummaryIncludesPairedRouteSetLocalReadyContext() {
        let model = sampleModel(id: "hub.model.coder")
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                pairedRouteSetSnapshot: makePairedRouteSetSnapshot(
                    readiness: .localReady,
                    summaryLine: "当前已完成同网首配，但还没有正式异网入口。"
                )
            )
        )

        #expect(report.readyForFirstTask == true)
        #expect(report.overallSummary.contains("当前已完成同网首配，但还没有正式异网入口。") == true)
    }

    @Test
    func pairingValiditySectionExplainsFormalRemoteVerificationPendingAfterSameLanFirstPair() {
        let model = sampleModel(id: "hub.model.coder")
        let stableRemoteRoute = XTPairedRouteTargetSnapshot(
            routeKind: .internet,
            host: "hub.tailnet.example",
            pairingPort: 50052,
            grpcPort: 50051,
            hostKind: "stable_named",
            source: .cachedProfileInternetHost
        )
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                firstPairCompletionProofSnapshot: makeFirstPairCompletionProofSnapshot(
                    readiness: .localReady,
                    remoteShadowSmokeStatus: .running,
                    stableRemoteRoutePresent: true,
                    remoteShadowSummary: "verifying stable remote route shadow path ..."
                ),
                pairedRouteSetSnapshot: makePairedRouteSetSnapshot(
                    readiness: .localReady,
                    summaryLine: "当前已完成同网首配，但正式异网入口仍未完成验证。",
                    stableRemoteRoute: stableRemoteRoute,
                    readinessReasonCode: "local_pairing_ready_remote_unverified"
                )
            )
        )

        let section = report.section(.pairingValidity)
        #expect(section?.state == .inProgress)
        #expect(section?.headline == "同网首配已完成，正在验证正式异网入口")
        #expect(section?.summary.contains("正式异网入口（host=hub.tailnet.example）") == true)
        #expect(section?.summary.contains("不要把状态误判成已经可以无感切网") == true)
        #expect(section?.detailLines.contains("paired_route_readiness=local_ready") == true)
        #expect(section?.detailLines.contains("first_pair_remote_shadow_status=running") == true)
    }

    @Test
    func preservesPairedRouteSetSnapshotOnUnifiedDoctorReport() {
        let model = sampleModel(id: "hub.model.coder")
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: false,
                remoteConnected: true,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: false,
                bridgeEnabled: false,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                pairedRouteSetSnapshot: makePairedRouteSetSnapshot(
                    readiness: .remoteReady,
                    summaryLine: "正式异网入口已验证，切网后可继续重连。",
                    stableRemoteRoute: XTPairedRouteTargetSnapshot(
                        routeKind: .internet,
                        host: "hub.tailnet.example",
                        pairingPort: 50052,
                        grpcPort: 50051,
                        hostKind: "stable_named",
                        source: .cachedProfileInternetHost
                    )
                )
            )
        )

        #expect(report.pairedRouteSetSnapshot?.readiness == .remoteReady)
        #expect(report.pairedRouteSetSnapshot?.summaryLine == "正式异网入口已验证，切网后可继续重连。")
        #expect(report.pairedRouteSetSnapshot?.stableRemoteRoute?.host == "hub.tailnet.example")
    }

    @Test
    func pairingValiditySectionExplainsRemoteReadyAsSwitchSafe() {
        let model = sampleModel(id: "hub.model.coder")
        let stableRemoteRoute = XTPairedRouteTargetSnapshot(
            routeKind: .internet,
            host: "hub.tailnet.example",
            pairingPort: 50052,
            grpcPort: 50051,
            hostKind: "stable_named",
            source: .cachedProfileInternetHost
        )
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: false,
                remoteConnected: true,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: false,
                bridgeEnabled: false,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                firstPairCompletionProofSnapshot: makeFirstPairCompletionProofSnapshot(
                    readiness: .remoteReady,
                    remoteShadowSmokeStatus: .passed,
                    stableRemoteRoutePresent: true,
                    remoteShadowSummary: "stable remote route was already verified by cached reconnect smoke."
                ),
                pairedRouteSetSnapshot: makePairedRouteSetSnapshot(
                    readiness: .remoteReady,
                    summaryLine: "正式异网入口已验证，切网后可继续重连。",
                    stableRemoteRoute: stableRemoteRoute,
                    readinessReasonCode: "cached_remote_reconnect_smoke_verified",
                    cachedReconnectSmokeStatus: "succeeded"
                )
            )
        )

        let section = report.section(.pairingValidity)
        #expect(section?.state == .ready)
        #expect(section?.headline == "正式异网入口已验证，切网后可继续工作")
        #expect(section?.summary.contains("切网后") == true)
        #expect(section?.detailLines.contains("paired_route_readiness=remote_ready") == true)
        #expect(section?.detailLines.contains("paired_cached_reconnect_smoke_status=succeeded") == true)
    }

    @Test
    func pairingValiditySectionExplainsRemoteDegradedAsNetworkRepairInsteadOfRePair() {
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: false,
                remoteConnected: false,
                configuredModelIDs: [],
                models: [],
                bridgeAlive: false,
                bridgeEnabled: false,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                firstPairCompletionProofSnapshot: makeFirstPairCompletionProofSnapshot(
                    readiness: .remoteDegraded,
                    remoteShadowSmokeStatus: .failed,
                    stableRemoteRoutePresent: true,
                    remoteShadowReasonCode: "grpc_unavailable",
                    remoteShadowSummary: "stable remote route shadow probe failed"
                ),
                pairedRouteSetSnapshot: makePairedRouteSetSnapshot(
                    readiness: .remoteDegraded,
                    summaryLine: "正式异网入口已存在，但最近一次异网验证未通过。",
                    stableRemoteRoute: XTPairedRouteTargetSnapshot(
                        routeKind: .internet,
                        host: "hub.tailnet.example",
                        pairingPort: 50052,
                        grpcPort: 50051,
                        hostKind: "stable_named",
                        source: .cachedProfileInternetHost
                    ),
                    readinessReasonCode: "remote_shadow_smoke_failed"
                )
            )
        )

        let section = report.section(.pairingValidity)
        #expect(section?.state == .diagnosticRequired)
        #expect(section?.headline == "正式异网入口存在，但切网续连目前不稳定")
        #expect(section?.nextStep.contains("防火墙") == true)
        #expect(section?.detailLines.contains("pairing_remote_shadow_failed=true") == true)
        #expect(section?.detailLines.contains("first_pair_remote_shadow_reason_code=grpc_unavailable") == true)
    }

    @Test
    func preservesConnectivityIncidentSnapshotOnUnifiedDoctorReport() {
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: false,
                remoteConnected: false,
                configuredModelIDs: [],
                models: [],
                bridgeAlive: false,
                bridgeEnabled: false,
                failureCode: "grpc_unavailable",
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                connectivityIncidentSnapshot: XTHubConnectivityIncidentSnapshot(
                    incidentState: .retrying,
                    reasonCode: "grpc_unavailable",
                    summaryLine: "remote route not active; retrying degraded remote route ...",
                    trigger: .backgroundKeepalive,
                    decisionReasonCode: "retry_degraded_remote_route",
                    pairedRouteReadiness: .remoteDegraded,
                    stableRemoteRouteHost: "hub.tailnet.example",
                    currentFailureCode: "grpc_unavailable",
                    currentPath: XTHubConnectivityIncidentPathSnapshot(
                        HubNetworkPathFingerprint(
                            statusKey: "satisfied",
                            usesWiFi: false,
                            usesWiredEthernet: false,
                            usesCellular: true,
                            isExpensive: true,
                            isConstrained: false
                        )
                    ),
                    lastUpdatedAtMs: 1_741_300_012_000
                )
            )
        )

        let section = report.section(.hubReachability)
        #expect(report.connectivityIncidentSnapshot?.incidentState == .retrying)
        #expect(report.connectivityIncidentSnapshot?.decisionReasonCode == "retry_degraded_remote_route")
        #expect(section?.detailLines.contains(where: { $0.contains("connectivity_incident state=retrying") }) == true)
        #expect(section?.detailLines.contains(where: { $0.contains("reason=grpc_unavailable") }) == true)
        #expect(section?.detailLines.contains("connectivity_incident_paired_route_readiness=remote_degraded") == true)
        #expect(section?.detailLines.contains(where: { $0.contains("connectivity_incident_path_status=satisfied") }) == true)
    }

    @Test
    func linkingWithFailureCodeStopsPretendingPairingIsStillInProgress() {
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: false,
                remoteConnected: false,
                configuredModelIDs: [],
                models: [],
                bridgeAlive: false,
                bridgeEnabled: false,
                failureCode: "pairing_approval_timeout",
                linking: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot()
            )
        )

        let section = report.section(.hubReachability)
        #expect(section?.state == .diagnosticRequired)
        #expect(section?.headline == "Hub 本地批准超时，首次配对没有完成")
        #expect(section?.detailLines.contains("failure_code=pairing_approval_timeout") == true)
        #expect(section?.summary.contains("安全确认链停在 Hub 本机") == true)
        #expect(report.overallSummary.contains("Hub 本地批准超时") == true)
    }

    @Test
    func linkingWithGrpcUnavailableShowsTargetAsUnreachableInsteadOfInProgress() {
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: false,
                remoteConnected: false,
                configuredModelIDs: [],
                models: [],
                bridgeAlive: false,
                bridgeEnabled: false,
                failureCode: "grpc_unavailable",
                linking: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot()
            )
        )

        let section = report.section(.hubReachability)
        #expect(section?.state == .diagnosticRequired)
        #expect(section?.headline == "Hub 配对引导已停住，正式异网入口当前不可达")
        #expect(section?.summary.contains("稳定命名入口") == true)
        #expect(section?.detailLines.contains(where: { $0.contains("target=") }) == true)
        #expect(section?.detailLines.contains("failure_code=grpc_unavailable") == true)
        #expect(section?.detailLines.contains("internet_host_kind=stable_named") == true)
    }

    @Test
    func runtimeCaptureWritesW9C3EvidenceWhenRequested() throws {
        guard let captureDir = ProcessInfo.processInfo.environment["XHUB_W9_C3_CAPTURE_DIR"], !captureDir.isEmpty else {
            return
        }

        let model = sampleModel(id: "hub.model.coder")
        let snapshot = ModelStateSnapshot(models: [model], updatedAt: 42)
        let hubDoctor = makeLocalOnlyHubDoctorReport()
        let inventory = XTModelInventoryTruthPresentation.build(
            snapshot: snapshot,
            doctorReport: hubDoctor,
            runtimeMonitor: nil
        )
        let guidance = XTModelGuidancePresentation.build(
            settings: .default(),
            snapshot: snapshot,
            doctorReport: hubDoctor,
            runtimeMonitor: nil
        )
        let xtDoctor = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot()
            )
        )

        let modelRoute = try #require(xtDoctor.section(.modelRouteReadiness))
        let providerCheck = try #require(hubDoctor.checks.first { $0.checkKind == "provider_readiness" })
        let evidence = W9C3LocalOnlyPostureEvidence(
            schemaVersion: "w9_c3_local_only_posture_evidence.v1",
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            status: "delivered",
            claimScope: ["W9-C3"],
            claim: "Local-only posture now stands as a healthy ready state across Hub doctor contract, XT model truth surfaces, and XT unified doctor guidance.",
            hubDoctor: .init(
                overallState: hubDoctor.overallState.rawValue,
                headline: hubDoctor.summary.headline,
                readyForFirstTask: hubDoctor.readyForFirstTask,
                providerHeadline: providerCheck.headline,
                providerMessage: providerCheck.message
            ),
            xtInventory: .init(
                state: inventory.state.rawValue,
                tone: inventory.tone == .neutral ? "neutral" : (inventory.tone == .caution ? "caution" : "critical"),
                headline: inventory.headline,
                summary: inventory.summary,
                detail: inventory.detail,
                requiresAttention: inventory.requiresAttention,
                showsStatusCard: inventory.showsStatusCard
            ),
            xtDoctor: .init(
                overallState: xtDoctor.overallState.rawValue,
                overallSummary: xtDoctor.overallSummary,
                readyForFirstTask: xtDoctor.readyForFirstTask,
                modelRouteHeadline: modelRoute.headline,
                modelRouteSummary: modelRoute.summary
            ),
            guidance: .init(
                inventorySummary: guidance.inventorySummary,
                localOnlyDetail: guidance.items.first(where: { $0.id == "local_only_ready" })?.detail ?? ""
            ),
            verificationResults: [
                VerificationResult(
                    name: "hub_doctor_local_only_is_ready",
                    status: hubDoctor.overallState == .ready && hubDoctor.readyForFirstTask ? "pass" : "fail"
                ),
                VerificationResult(
                    name: "xt_inventory_local_only_is_neutral_not_attention",
                    status: inventory.state == .localOnlyReady && inventory.tone == .neutral && !inventory.requiresAttention ? "pass" : "fail"
                ),
                VerificationResult(
                    name: "xt_doctor_ready_summary_mentions_local_only",
                    status: xtDoctor.readyForFirstTask && xtDoctor.overallSummary.contains("纯本地") ? "pass" : "fail"
                ),
                VerificationResult(
                    name: "guidance_explains_cloud_is_optional",
                    status: guidance.items.contains(where: { $0.id == "local_only_ready" && $0.detail.contains("不配置云 provider / API key") }) ? "pass" : "fail"
                )
            ],
            sourceRefs: [
                "x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubUIStrings.swift:5723",
                "x-hub/macos/RELFlowHub/Tests/RELFlowHubAppTests/HubDiagnosticsBundleExporterTests.swift:1",
                "x-terminal/Sources/UI/XTModelInventoryTruthPresentation.swift:1",
                "x-terminal/Sources/UI/XTSettingsGuidancePresentation.swift:1",
                "x-terminal/Sources/UI/XTUnifiedDoctor.swift:396",
                "x-terminal/Tests/XTUnifiedDoctorReportTests.swift:1"
            ]
        )

        let base = URL(fileURLWithPath: captureDir)
        let fileName = "w9_c3_local_only_posture_evidence.v1.json"
        for destination in evidenceDestinations(captureBase: base, fileName: fileName) {
            try writeJSON(evidence, to: destination)
            #expect(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    @Test
    func bridgeSectionSurfacesLastEnableDeliveryFailure() {
        let model = sampleModel(id: "hub.model.coder")
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: false,
                bridgeEnabled: false,
                bridgeLastError: "bridge_enable_command_write_failed=POSIXError: No space left on device",
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot()
            )
        )

        let section = report.section(.bridgeToolReadiness)
        #expect(section?.state == .diagnosticRequired)
        #expect(section?.summary.contains("bridge enable 请求也在链路恢复前失败了") == true)
        #expect(section?.detailLines.contains(where: { $0.contains("bridge_last_error=") }) == true)
    }

    @Test
    func hubReachabilitySectionExplainsAmbiguousDiscoveryInsteadOfGenericUnreachable() {
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: false,
                remoteConnected: false,
                configuredModelIDs: [],
                models: [],
                bridgeAlive: false,
                bridgeEnabled: false,
                failureCode: "bonjour_multiple_hubs_ambiguous",
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot()
            )
        )

        let section = report.section(.hubReachability)
        #expect(section?.state == .diagnosticRequired)
        #expect(section?.headline == "发现到多台 Hub，必须先固定目标")
        #expect(section?.summary.contains("多台候选 Hub") == true)
        #expect(section?.nextStep.contains("固定一台目标 Hub") == true)
    }

    @Test
    func hubReachabilitySectionExplainsPortConflictInsteadOfGenericUnreachable() {
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: false,
                remoteConnected: false,
                configuredModelIDs: [],
                models: [],
                bridgeAlive: false,
                bridgeEnabled: false,
                failureCode: "hub_port_conflict",
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot()
            )
        )

        let section = report.section(.hubReachability)
        #expect(section?.state == .diagnosticRequired)
        #expect(section?.headline == "Hub 端口冲突，必须先修复网络端口")
        #expect(section?.summary.contains("已被占用") == true)
        #expect(section?.nextStep.contains("切换到空闲端口") == true)
    }

    @Test
    func hubReachabilitySectionExplainsSameLanFirstPairPolicy() {
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: false,
                remoteConnected: false,
                configuredModelIDs: [],
                models: [],
                bridgeAlive: false,
                bridgeEnabled: false,
                failureCode: "first_pair_requires_same_lan",
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                internetHost: ""
            )
        )

        let section = report.section(.hubReachability)
        #expect(section?.state == .diagnosticRequired)
        #expect(section?.headline == "首次配对必须回到同一 Wi-Fi / 同一局域网")
        #expect(section?.summary.contains("同一 Wi-Fi / 同一局域网") == true)
        #expect(section?.detailLines.contains("internet_host_kind=missing") == true)
    }

    @Test
    func hubReachabilitySectionExplainsSameSSIDIsNotEnoughForPrivateLanFirstPair() {
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: false,
                remoteConnected: false,
                configuredModelIDs: [],
                models: [],
                bridgeAlive: false,
                bridgeEnabled: false,
                failureCode: "first_pair_requires_same_lan",
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                internetHost: "17.81.11.116"
            )
        )

        let section = report.section(.hubReachability)
        #expect(section?.state == .diagnosticRequired)
        #expect(section?.summary.contains("client isolation") == true)
        #expect(section?.nextStep.contains("VLAN") == true)
        #expect(section?.detailLines.contains("internet_host_scope=publicInternet") == true)
    }

    @Test
    func hubReachabilitySectionExplainsMissingFormalRemoteEntry() {
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: false,
                remoteConnected: false,
                configuredModelIDs: [],
                models: [],
                bridgeAlive: false,
                bridgeEnabled: false,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                internetHost: ""
            )
        )

        let section = report.section(.hubReachability)
        #expect(section?.state == .diagnosticRequired)
        #expect(section?.headline == "Hub 暂时不可达，而且还没有正式远端入口")
        #expect(section?.detailLines.contains("internet_host_kind=missing") == true)
    }

    @Test
    func hubReachabilitySectionExplainsLanOnlyRemoteEntry() {
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: false,
                remoteConnected: false,
                configuredModelIDs: [],
                models: [],
                bridgeAlive: false,
                bridgeEnabled: false,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                internetHost: "hub.local"
            )
        )

        let section = report.section(.hubReachability)
        #expect(section?.state == .diagnosticRequired)
        #expect(section?.headline == "Hub 暂时不可达，当前只有同网入口")
        #expect(section?.summary.contains("自动发现") == true)
        #expect(section?.detailLines.contains("internet_host_kind=lan_only") == true)
    }

    @Test
    func hubReachabilitySectionExplainsRawIPRemoteEntry() {
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: false,
                remoteConnected: false,
                configuredModelIDs: [],
                models: [],
                bridgeAlive: false,
                bridgeEnabled: false,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                internetHost: "17.81.11.116"
            )
        )

        let section = report.section(.hubReachability)
        #expect(section?.state == .diagnosticRequired)
        #expect(section?.headline == "Hub 暂时不可达，当前还是临时 raw IP 入口")
        #expect(section?.summary.contains("公网 IP") == true)
        #expect(section?.detailLines.contains("internet_host_kind=raw_ip") == true)
        #expect(section?.detailLines.contains("internet_host_scope=publicInternet") == true)
    }

    @Test
    func hubReachabilitySectionExplainsPrivateLanRawIPNeedsSameLanOrVPN() {
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: false,
                remoteConnected: false,
                configuredModelIDs: [],
                models: [],
                bridgeAlive: false,
                bridgeEnabled: false,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                internetHost: "192.168.10.109"
            )
        )

        let section = report.section(.hubReachability)
        #expect(section?.state == .diagnosticRequired)
        #expect(section?.headline == "Hub 暂时不可达，当前还是临时 raw IP 入口")
        #expect(section?.summary.contains("同一局域网") == true)
        #expect(section?.nextStep.contains("同一 VPN") == true)
        #expect(section?.detailLines.contains("internet_host_scope=privateLAN") == true)
    }

    @Test
    func hubReachabilitySectionShowsFreshPairReconnectSmokeRunning() {
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: false,
                remoteConnected: false,
                configuredModelIDs: [],
                models: [],
                bridgeAlive: false,
                bridgeEnabled: false,
                linking: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                freshPairReconnectSmokeSnapshot: XTFreshPairReconnectSmokeSnapshot(
                    source: .startupAutomaticFirstPair,
                    status: .running,
                    triggeredAtMs: 1_741_300_010_000,
                    completedAtMs: 0,
                    route: .lan,
                    reasonCode: nil,
                    summary: "verifying paired route ..."
                )
            )
        )

        let section = report.section(.hubReachability)
        #expect(section?.state == .inProgress)
        #expect(section?.headline == "首次配对已完成，正在验证缓存路由")
        #expect(section?.detailLines.contains(where: { $0.contains("fresh_pair_reconnect_smoke status=running") }) == true)
    }

    @Test
    func hubReachabilitySectionShowsFreshPairReconnectSmokeSuccessEvidence() {
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: false,
                remoteConnected: true,
                configuredModelIDs: [],
                models: [],
                bridgeAlive: false,
                bridgeEnabled: false,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                freshPairReconnectSmokeSnapshot: XTFreshPairReconnectSmokeSnapshot(
                    source: .manualOneClickSetup,
                    status: .succeeded,
                    triggeredAtMs: 1_741_300_010_000,
                    completedAtMs: 1_741_300_011_000,
                    route: .internet,
                    reasonCode: nil,
                    summary: "first pair complete; cached route verified."
                )
            )
        )

        let section = report.section(.hubReachability)
        #expect(section?.state == .ready)
        #expect(section?.summary.contains("缓存路由验证已通过") == true)
        #expect(section?.detailLines.contains("fresh_pair_reconnect_smoke_summary=first pair complete; cached route verified.") == true)
    }

    @Test
    func hubReachabilitySectionShowsFreshPairReconnectSmokeFailureEvidence() {
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: false,
                remoteConnected: false,
                configuredModelIDs: [],
                models: [],
                bridgeAlive: false,
                bridgeEnabled: false,
                failureCode: "grpc_unavailable",
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                freshPairReconnectSmokeSnapshot: XTFreshPairReconnectSmokeSnapshot(
                    source: .manualOneClickSetup,
                    status: .failed,
                    triggeredAtMs: 1_741_300_010_000,
                    completedAtMs: 1_741_300_011_000,
                    route: .none,
                    reasonCode: "grpc_unavailable",
                    summary: "grpc_unavailable"
                )
            )
        )

        let section = report.section(.hubReachability)
        #expect(section?.state == .diagnosticRequired)
        #expect(section?.summary.contains("缓存路由验证失败") == true)
        #expect(section?.detailLines.contains("fresh_pair_reconnect_smoke_reason=grpc_unavailable") == true)
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
        #expect(report.section(.sessionRuntimeReadiness)?.headline == "Bridge 已通，但会话运行时不可恢复")
    }

    @Test
    func activeSessionRuntimeUsesSettlingSummaryInsteadOfFailClosedCopy() {
        let model = sampleModel(id: "hub.model.supervisor")
        let runtime = AXSessionRuntimeSnapshot(
            schemaVersion: AXSessionRuntimeSnapshot.currentSchemaVersion,
            state: .planning,
            runID: "run-active-1",
            updatedAt: 1_741_300_000,
            startedAt: 1_741_299_980,
            completedAt: nil,
            lastRuntimeSummary: "planning next reply",
            lastToolBatchIDs: [],
            pendingToolCallCount: 0,
            lastFailureCode: nil,
            resumeToken: "run-active-1",
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
                sessionID: "session-active-1",
                skillsSnapshot: readySkillsSnapshot()
            )
        )

        #expect(report.section(.sessionRuntimeReadiness)?.state == .inProgress)
        #expect(report.readyForFirstTask == false)
        #expect(report.overallSummary.contains("当前仍在收敛") == true)
        #expect(report.overallSummary.contains("会话运行时仍在处理中") == true)
        #expect(report.overallSummary.contains("fail-closed") == false)
    }

    @Test
    func sessionRuntimeSectionIncludesProjectContextDiagnosticsWhenAvailable() {
        let model = sampleModel(id: "hub.model.coder")
        let diagnostics = AXProjectContextAssemblyDiagnosticsSummary(
            latestEvent: nil,
            detailLines: [
                "project_context_diagnostics_source=latest_coder_usage",
                "project_context_project=Snake",
                "recent_project_dialogue_profile=extended_40_pairs",
                "recent_project_dialogue_floor_satisfied=true",
                "project_context_depth=full",
                "effective_project_serving_profile=m4_full_scan",
                "project_memory_selected_serving_objects=recent_project_dialogue_window,focused_project_anchor_pack,execution_evidence",
                "project_memory_excluded_blocks=active_workflow,guidance",
                "project_memory_budget_summary=source=hub_memory_v1_grpc · used=512 · budget=2048"
            ]
        )
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                projectContextDiagnostics: diagnostics
            )
        )

        let section = report.section(.sessionRuntimeReadiness)
        let presentation = section?.projectContextPresentation
        #expect(section?.state == .ready)
        #expect(section?.detailLines.contains("project_context_project=Snake") == true)
        #expect(section?.detailLines.contains("recent_project_dialogue_profile=extended_40_pairs") == true)
        #expect(section?.detailLines.contains("project_context_depth=full") == true)
        #expect(presentation?.sourceKind == .latestCoderUsage)
        #expect(presentation?.projectLabel == "Snake")
        #expect(presentation?.dialogueMetric.contains("40 pairs") == true)
        #expect(presentation?.depthMetric.contains("Full") == true)
        #expect(presentation?.userAssemblySummary == "实际带入最近项目对话、项目锚点和执行证据")
        #expect(presentation?.userOmissionSummary == "本轮未带活动工作流和Supervisor 指导")
        #expect(presentation?.userBudgetSummary == "source Hub 快照 + 本地 overlay · used 512 tok · budget 2048 tok")
    }

    @Test
    func sessionRuntimeSectionIncludesGovernanceRuntimeReadinessWhenAvailable() throws {
        let model = sampleModel(id: "hub.model.coder")
        let root = makeProjectRoot(named: "doctor-governance-runtime-readiness")
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingTrustedAutomationBinding(
            mode: AXProjectAutomationMode.trustedAutomation,
            deviceId: "device_xt_001",
            deviceToolGroups: ["device.browser.control"],
            workspaceBindingHash: "sha256:stale-binding"
        )
        config = config.settingRuntimeSurfacePolicy(
            mode: AXProjectRuntimeSurfaceMode.trustedOpenClawMode,
            ttlSeconds: 600,
            updatedAt: Date(timeIntervalSince1970: 1_741_299_900)
        )
        config = config.settingProjectGovernance(
            executionTier: AXProjectExecutionTier.a4OpenClaw,
            supervisorInterventionTier: AXProjectSupervisorInterventionTier.s3StrategicCoach
        )
        let governance = xtResolveProjectGovernance(
            projectRoot: root,
            config: config,
            permissionReadiness: makePermissionReadiness(
                accessibility: AXTrustedAutomationPermissionStatus.granted,
                automation: AXTrustedAutomationPermissionStatus.missing,
                screenRecording: AXTrustedAutomationPermissionStatus.missing
            )
        )

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                projectGovernanceResolved: governance
            )
        )

        let section = try #require(
            report.section(XTUnifiedDoctorSectionKind.sessionRuntimeReadiness)
        )
        #expect(section.projectGovernanceRuntimeReadinessProjection?.runtimeReady == false)
        #expect(section.projectGovernanceRuntimeReadinessProjection?.state == .blocked)
        #expect(section.detailLines.contains("project_governance_runtime_ready=false"))
        #expect(section.detailLines.contains("project_governance_runtime_readiness_state=blocked"))
        #expect(section.detailLines.contains("project_governance_effective_surface_capabilities="))
        #expect(section.detailLines.contains("project_governance_runtime_component_route_ready_state=ready"))
        #expect(section.detailLines.contains("project_governance_runtime_component_capability_ready_state=blocked"))
        #expect(section.detailLines.contains("project_governance_runtime_component_grant_ready_state=blocked"))
        #expect(section.detailLines.contains("project_governance_runtime_component_checkpoint_recovery_ready_state=ready"))
        #expect(section.detailLines.contains("project_governance_runtime_component_evidence_export_ready_state=ready"))
        #expect(section.detailLines.contains(where: { $0.contains("runtime_surface_ttl_expired") }))
        #expect(section.detailLines.contains(where: { $0.contains("capability_device_tools_unavailable") }))
        #expect(section.detailLines.contains(where: { $0.contains("trusted_automation_not_ready") }))
        #expect(section.detailLines.contains(where: { $0.contains("permission_owner_not_ready") }))
    }

    @Test
    func sessionRuntimeSectionIncludesStructuredRemoteSnapshotCacheProjectionsWhenAvailable() throws {
        let model = sampleModel(id: "hub.model.coder")
        let diagnostics = AXProjectContextAssemblyDiagnosticsSummary(
            latestEvent: nil,
            detailLines: [
                "project_memory_v1_source=hub_memory_v1_grpc",
                "memory_v1_freshness=ttl_cache",
                "memory_v1_cache_hit=true",
                "memory_v1_remote_snapshot_cache_scope=mode=project_chat project_id=snake",
                "memory_v1_remote_snapshot_cached_at_ms=1774000000000",
                "memory_v1_remote_snapshot_age_ms=6000",
                "memory_v1_remote_snapshot_ttl_remaining_ms=9000",
                "memory_v1_remote_snapshot_cache_posture=continuity_safe",
                "memory_v1_remote_snapshot_invalidation_reason=route_or_model_preference_changed"
            ]
        )
        var memorySnapshot = makeSupervisorMemoryAssemblySnapshot()
        memorySnapshot.source = "hub"
        memorySnapshot.freshness = "ttl_cache"
        memorySnapshot.cacheHit = true
        memorySnapshot.remoteSnapshotCacheScope = "mode=supervisor_orchestration project_id=(none)"
        memorySnapshot.remoteSnapshotCachedAtMs = 1_774_000_005_000
        memorySnapshot.remoteSnapshotAgeMs = 3_000
        memorySnapshot.remoteSnapshotTTLRemainingMs = 12_000
        memorySnapshot.remoteSnapshotCachePosture = "continuity_safe"
        memorySnapshot.remoteSnapshotInvalidationReason = "heartbeat_anomaly_escalated"

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                projectContextDiagnostics: diagnostics,
                supervisorMemoryAssemblySnapshot: memorySnapshot
            )
        )

        let section = try #require(report.section(.sessionRuntimeReadiness))
        #expect(section.projectRemoteSnapshotCacheProjection?.source == "hub_memory_v1_grpc")
        #expect(section.projectRemoteSnapshotCacheProjection?.freshness == "ttl_cache")
        #expect(section.projectRemoteSnapshotCacheProjection?.cacheHit == true)
        #expect(section.projectRemoteSnapshotCacheProjection?.scope == "mode=project_chat project_id=snake")
        #expect(section.projectRemoteSnapshotCacheProjection?.cachedAtMs == 1_774_000_000_000)
        #expect(section.projectRemoteSnapshotCacheProjection?.ageMs == 6_000)
        #expect(section.projectRemoteSnapshotCacheProjection?.ttlRemainingMs == 9_000)
        #expect(section.projectRemoteSnapshotCacheProjection?.cachePosture == "continuity_safe")
        #expect(
            section.projectRemoteSnapshotCacheProjection?.invalidationReason
            == "route_or_model_preference_changed"
        )
        #expect(section.supervisorRemoteSnapshotCacheProjection?.source == "hub")
        #expect(section.supervisorRemoteSnapshotCacheProjection?.freshness == "ttl_cache")
        #expect(section.supervisorRemoteSnapshotCacheProjection?.cacheHit == true)
        #expect(section.supervisorRemoteSnapshotCacheProjection?.scope == "mode=supervisor_orchestration project_id=(none)")
        #expect(section.supervisorRemoteSnapshotCacheProjection?.cachedAtMs == 1_774_000_005_000)
        #expect(section.supervisorRemoteSnapshotCacheProjection?.ageMs == 3_000)
        #expect(section.supervisorRemoteSnapshotCacheProjection?.ttlRemainingMs == 12_000)
        #expect(section.supervisorRemoteSnapshotCacheProjection?.cachePosture == "continuity_safe")
        #expect(
            section.supervisorRemoteSnapshotCacheProjection?.invalidationReason
            == "heartbeat_anomaly_escalated"
        )
    }

    @Test
    func sessionRuntimeSectionIncludesHeartbeatGovernanceExplainabilityWhenAvailable() throws {
        let model = sampleModel(id: "hub.model.coder")
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                heartbeatGovernanceSnapshot: sampleHeartbeatGovernanceSnapshot()
            )
        )

        let section = try #require(report.section(.sessionRuntimeReadiness))
        let projection = try #require(section.heartbeatGovernanceProjection)
        let detailLines = section.detailLines

        #expect(section.state == .ready)
        #expect(detailLines.contains("heartbeat_quality_band=weak"))
        #expect(detailLines.contains("heartbeat_project_phase=release"))
        #expect(detailLines.contains("heartbeat_execution_status=done_candidate"))
        #expect(detailLines.contains("heartbeat_risk_tier=high"))
        #expect(detailLines.contains("heartbeat_digest_visibility=shown"))
        #expect(detailLines.contains(where: { $0.contains("heartbeat_digest_reason_codes=") && $0.contains("weak_done_claim") }))
        #expect(detailLines.contains(where: { $0.contains("heartbeat_effective_cadence progress=180s pulse=600s brainstorm=1200s") }))
        #expect(detailLines.contains(where: { $0.contains("heartbeat_next_review_due kind=review_pulse") && $0.contains("due=true") }))
        #expect(detailLines.contains(where: { $0.contains("heartbeat_recovery action=queue_strategic_review") && $0.contains("urgency=urgent") }))
        #expect(projection.projectId == "project-alpha")
        #expect(projection.projectName == "Alpha")
        #expect(projection.latestQualityBand == HeartbeatQualityBand.weak.rawValue)
        #expect(projection.digestVisibility == XTHeartbeatDigestVisibilityDecision.shown.rawValue)
        #expect(projection.digestReasonCodes.contains("weak_done_claim"))
        #expect(projection.digestWhatChangedText.contains("完成声明证据偏弱"))
        #expect(projection.digestSystemNextStepText.contains("Ship release once final review clears"))
        #expect(projection.reviewPulse.configuredSeconds == 1_200)
        #expect(projection.reviewPulse.recommendedSeconds == 600)
        #expect(projection.reviewPulse.effectiveSeconds == 600)
        #expect(projection.nextReviewDue.kind == SupervisorCadenceDimension.reviewPulse.rawValue)
        #expect(projection.nextReviewDue.due == true)
        #expect(projection.recoveryDecision?.action == HeartbeatRecoveryAction.queueStrategicReview.rawValue)
        #expect(projection.recoveryDecision?.queuedReviewLevel == SupervisorReviewLevel.r3Rescue.rawValue)
    }

    @Test
    func sessionRuntimeSectionIncludesSupervisorGuidanceContinuityProjectionWhenAvailable() throws {
        let model = sampleModel(id: "hub.model.coder")
        let memorySnapshot = makeSupervisorMemoryAssemblySnapshot(
            selectedSections: ["focused_project_anchor_pack", "context_refs"],
            latestReviewNoteAvailable: true,
            latestGuidanceAvailable: true,
            latestGuidanceAckStatus: SupervisorGuidanceAckStatus.deferred.rawValue,
            latestGuidanceAckRequired: true,
            latestGuidanceDeliveryMode: SupervisorGuidanceDeliveryMode.priorityInsert.rawValue,
            latestGuidanceInterventionMode: SupervisorGuidanceInterventionMode.suggestNextSafePoint.rawValue,
            latestGuidanceSafePointPolicy: SupervisorGuidanceSafePointPolicy.nextToolBoundary.rawValue,
            pendingAckGuidanceAvailable: true,
            pendingAckGuidanceAckStatus: SupervisorGuidanceAckStatus.pending.rawValue,
            pendingAckGuidanceAckRequired: true,
            pendingAckGuidanceDeliveryMode: SupervisorGuidanceDeliveryMode.replanRequest.rawValue,
            pendingAckGuidanceInterventionMode: SupervisorGuidanceInterventionMode.replanNextSafePoint.rawValue,
            pendingAckGuidanceSafePointPolicy: SupervisorGuidanceSafePointPolicy.nextStepBoundary.rawValue
        )

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                supervisorMemoryAssemblySnapshot: memorySnapshot
            )
        )

        let section = try #require(report.section(.sessionRuntimeReadiness))
        let projection = try #require(section.supervisorGuidanceContinuityProjection)

        #expect(projection.reviewGuidanceCarrierPresent)
        #expect(projection.latestReviewNoteAvailable)
        #expect(projection.latestReviewNoteActualized)
        #expect(projection.latestGuidanceAvailable)
        #expect(projection.latestGuidanceActualized)
        #expect(projection.latestGuidanceAckStatus == SupervisorGuidanceAckStatus.deferred.rawValue)
        #expect(projection.latestGuidanceDeliveryMode == SupervisorGuidanceDeliveryMode.priorityInsert.rawValue)
        #expect(projection.latestGuidanceInterventionMode == SupervisorGuidanceInterventionMode.suggestNextSafePoint.rawValue)
        #expect(projection.latestGuidanceSafePointPolicy == SupervisorGuidanceSafePointPolicy.nextToolBoundary.rawValue)
        #expect(projection.pendingAckGuidanceAvailable)
        #expect(projection.pendingAckGuidanceActualized)
        #expect(projection.pendingAckGuidanceAckStatus == SupervisorGuidanceAckStatus.pending.rawValue)
        #expect(projection.pendingAckGuidanceDeliveryMode == SupervisorGuidanceDeliveryMode.replanRequest.rawValue)
        #expect(projection.pendingAckGuidanceInterventionMode == SupervisorGuidanceInterventionMode.replanNextSafePoint.rawValue)
        #expect(projection.pendingAckGuidanceSafePointPolicy == SupervisorGuidanceSafePointPolicy.nextStepBoundary.rawValue)
        #expect(projection.renderedRefs == [
            "latest_review_note",
            "latest_guidance",
            "pending_ack_guidance"
        ])
        #expect(projection.summaryLine.contains("Review / Guidance：latest review carried"))
        #expect(section.detailLines.contains("supervisor_review_guidance_carrier_present=true"))
        #expect(section.detailLines.contains("supervisor_memory_latest_guidance_ack_status=deferred"))
        #expect(section.detailLines.contains("supervisor_memory_pending_ack_guidance_ack_status=pending"))
    }

    @Test
    func sessionRuntimeSectionIncludesSupervisorSafePointTimelineProjectionWhenPendingGuidanceWaitsForNextStepBoundary() throws {
        let model = sampleModel(id: "hub.model.coder")
        let root = makeProjectRoot(named: "xt-doctor-safe-point")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-safe-point-next-step",
                reviewId: "review-safe-point-next-step",
                projectId: AXProjectRegistryStore.projectId(forRoot: ctx.root),
                targetRole: .coder,
                deliveryMode: .replanRequest,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .nextStepBoundary,
                guidanceText: "下一步边界再重规划。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 200,
                ackUpdatedAtMs: 0,
                auditRef: "audit-safe-point-next-step"
            ),
            for: ctx
        )
        AXPendingActionsStore.saveToolApproval(
            AXPendingAction(
                id: "pending-safe-point-tool-approval",
                type: .toolApproval,
                createdAt: 1_741_300_010,
                status: "pending",
                projectId: AXProjectRegistryStore.projectId(forRoot: ctx.root),
                projectName: "Safe Point Project",
                reason: "awaiting_local_approval",
                preview: "git diff",
                userText: "继续",
                assistantStub: "pending",
                toolCalls: [],
                flow: AXPendingToolFlowState(
                    step: 1,
                    toolResults: [],
                    runStartedAtMs: 100,
                    dirtySinceVerify: false,
                    verifyRunIndex: 0,
                    repairAttemptsUsed: 0,
                    deferredFinal: nil,
                    finalizeOnly: false,
                    formatRetryUsed: false,
                    executionRetryUsed: false,
                    lastPromptVisibleGuidanceInjectionId: nil,
                    lastSafePointPauseInjectionId: nil
                )
            ),
            for: ctx
        )

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                doctorProjectContext: ctx
            )
        )

        let section = try #require(report.section(.sessionRuntimeReadiness))
        let projection = try #require(section.supervisorSafePointTimelineProjection)

        #expect(projection.pendingGuidanceAvailable)
        #expect(projection.pendingGuidanceInjectionId == "guidance-safe-point-next-step")
        #expect(projection.pendingGuidanceDeliveryMode == SupervisorGuidanceDeliveryMode.replanRequest.rawValue)
        #expect(projection.pendingGuidanceInterventionMode == SupervisorGuidanceInterventionMode.replanNextSafePoint.rawValue)
        #expect(projection.pendingGuidanceSafePointPolicy == SupervisorGuidanceSafePointPolicy.nextStepBoundary.rawValue)
        #expect(projection.liveStateSource == "pending_tool_approval")
        #expect(projection.flowStep == 1)
        #expect(projection.toolResultsCount == 0)
        #expect(projection.verifyRunIndex == 0)
        #expect(projection.finalizeOnly == false)
        #expect(projection.checkpointReached == false)
        #expect(projection.promptVisibleNow == false)
        #expect(projection.visibleFromPreRunMemory == false)
        #expect(projection.pauseRecorded == false)
        #expect(projection.deliverableNow == false)
        #expect(projection.shouldPauseToolBatchAfterBoundary == false)
        #expect(projection.deliveryState == "waiting_next_step_boundary")
        #expect(projection.executionGate == "normal")
        #expect(projection.summaryLine.contains("pending guidance 等待下一步边界"))
        #expect(section.detailLines.contains("supervisor_safe_point_live_state_source=pending_tool_approval"))
        #expect(section.detailLines.contains("supervisor_safe_point_delivery_state=waiting_next_step_boundary"))
    }

    @Test
    func sessionRuntimeSectionIncludesSupervisorReviewTriggerProjectionWhenGovernanceAndProjectContextAreAvailable() throws {
        let model = sampleModel(id: "hub.model.coder")
        let root = makeProjectRoot(named: "xt-doctor-review-trigger")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach
        )
        let governance = xtResolveProjectGovernance(projectRoot: root, config: config)
        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)

        try SupervisorReviewNoteStore.upsert(
            SupervisorReviewNoteBuilder.build(
                reviewId: "review-trigger-blocker-note",
                projectId: projectId,
                trigger: .blockerDetected,
                reviewLevel: .r2Strategic,
                verdict: .watch,
                targetRole: .coder,
                deliveryMode: .priorityInsert,
                ackRequired: true,
                summary: "Blocker is active and needs a strategic review.",
                recommendedActions: ["inspect the blocker before resuming"],
                anchorGoal: "Ship the current patch safely",
                anchorDoneDefinition: "Verification passes and blocker is cleared",
                anchorConstraints: ["stay inside repo scope"],
                currentState: "Repo write is blocked on a missing prerequisite.",
                nextStep: "Review blocker and replan the next safe point.",
                blocker: "Repo write blocked",
                createdAtMs: 1_741_299_800_000,
                auditRef: "audit-review-trigger-blocker-note"
            ),
            for: ctx
        )

        let heartbeatSnapshot = XTProjectHeartbeatGovernanceDoctorSnapshot(
            projectId: projectId,
            projectName: "Review Trigger Project",
            statusDigest: "blocked",
            currentStateSummary: "Execution is waiting on a blocker review",
            nextStepSummary: "Run a strategic blocker review",
            blockerSummary: "Repo write blocked",
            lastHeartbeatAtMs: 1_741_300_000_000,
            latestQualityBand: .weak,
            latestQualityScore: 52,
            weakReasons: ["execution_vitality_low"],
            openAnomalyTypes: [],
            projectPhase: .build,
            executionStatus: .blocked,
            riskTier: .medium,
            cadence: SupervisorCadenceExplainability(
                progressHeartbeat: SupervisorCadenceDimensionExplainability(
                    dimension: .progressHeartbeat,
                    configuredSeconds: 600,
                    recommendedSeconds: 600,
                    effectiveSeconds: 600,
                    effectiveReasonCodes: ["configured_equals_recommended"],
                    nextDueAtMs: 1_741_300_600_000,
                    nextDueReasonCodes: ["waiting_for_heartbeat_window"],
                    isDue: false
                ),
                reviewPulse: SupervisorCadenceDimensionExplainability(
                    dimension: .reviewPulse,
                    configuredSeconds: 1_200,
                    recommendedSeconds: 1_200,
                    effectiveSeconds: 1_200,
                    effectiveReasonCodes: ["configured_equals_recommended"],
                    nextDueAtMs: 1_741_301_200_000,
                    nextDueReasonCodes: ["waiting_for_pulse_window"],
                    isDue: false
                ),
                brainstormReview: SupervisorCadenceDimensionExplainability(
                    dimension: .brainstormReview,
                    configuredSeconds: 2_400,
                    recommendedSeconds: 2_400,
                    effectiveSeconds: 2_400,
                    effectiveReasonCodes: ["configured_equals_recommended"],
                    nextDueAtMs: 1_741_302_400_000,
                    nextDueReasonCodes: ["waiting_for_no_progress_window"],
                    isDue: false
                ),
                eventFollowUpCooldownSeconds: 300
            ),
            digestExplainability: XTHeartbeatDigestExplainability(
                visibility: .shown,
                reasonCodes: ["blocker_present", "review_candidate_active"],
                whatChangedText: "A blocker is holding the current execution run.",
                whyImportantText: "The blocker requires supervisor review before execution can safely continue.",
                systemNextStepText: "Queue a strategic blocker review before resuming."
            ),
            recoveryDecision: nil
        )

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                projectGovernanceResolved: governance,
                heartbeatGovernanceSnapshot: heartbeatSnapshot,
                doctorProjectContext: ctx
            )
        )

        let section = try #require(report.section(.sessionRuntimeReadiness))
        let projection = try #require(section.supervisorReviewTriggerProjection)

        #expect(projection.reviewPolicyMode == governance.effectiveBundle.reviewPolicyMode.rawValue)
        #expect(projection.eventDrivenReviewEnabled == true)
        #expect(projection.eventFollowUpCadenceLabel?.contains("blocker cooldown") == true)
        #expect(projection.mandatoryReviewTriggers == [
            AXProjectReviewTrigger.blockerDetected.rawValue,
            AXProjectReviewTrigger.planDrift.rawValue,
            AXProjectReviewTrigger.preDoneSummary.rawValue
        ])
        #expect(projection.effectiveEventReviewTriggers == [
            AXProjectReviewTrigger.blockerDetected.rawValue,
            AXProjectReviewTrigger.planDrift.rawValue,
            AXProjectReviewTrigger.preDoneSummary.rawValue
        ])
        #expect(projection.derivedReviewTriggers.contains(SupervisorReviewTrigger.manualRequest.rawValue))
        #expect(projection.derivedReviewTriggers.contains(SupervisorReviewTrigger.userOverride.rawValue))
        #expect(projection.derivedReviewTriggers.contains(SupervisorReviewTrigger.periodicPulse.rawValue))
        #expect(projection.derivedReviewTriggers.contains(SupervisorReviewTrigger.noProgressWindow.rawValue))
        #expect(projection.activeCandidateAvailable == true)
        #expect(projection.activeCandidateTrigger == SupervisorReviewTrigger.blockerDetected.rawValue)
        #expect(projection.activeCandidateRunKind == SupervisorReviewRunKind.eventDriven.rawValue)
        #expect(projection.activeCandidateReviewLevel == SupervisorReviewLevel.r2Strategic.rawValue)
        #expect(projection.activeCandidateQueued == true)
        #expect(projection.queuedReviewTrigger == SupervisorReviewTrigger.blockerDetected.rawValue)
        #expect(projection.queuedReviewRunKind == SupervisorReviewRunKind.eventDriven.rawValue)
        #expect(projection.queuedReviewLevel == SupervisorReviewLevel.r2Strategic.rawValue)
        #expect(projection.latestReviewSource == "review_note_store")
        #expect(projection.latestReviewTrigger == SupervisorReviewTrigger.blockerDetected.rawValue)
        #expect(projection.latestReviewLevel == SupervisorReviewLevel.r2Strategic.rawValue)
        #expect(projection.latestReviewAtMs == 1_741_299_800_000)
        #expect(projection.summaryLine.contains("Review Trigger：当前候选 blocker_detected"))
        #expect(section.detailLines.contains("supervisor_review_policy_mode=hybrid"))
        #expect(section.detailLines.contains("supervisor_review_active_candidate_trigger=blocker_detected"))
        #expect(section.detailLines.contains("supervisor_review_latest_review_source=review_note_store"))
    }

    @Test
    func sessionRuntimeSectionIncludesSuppressedHeartbeatDigestExplainabilityWhenAvailable() throws {
        let model = sampleModel(id: "hub.model.coder")
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                heartbeatGovernanceSnapshot: sampleSuppressedHeartbeatGovernanceSnapshot()
            )
        )

        let section = try #require(report.section(.sessionRuntimeReadiness))
        let projection = try #require(section.heartbeatGovernanceProjection)
        let detailLines = section.detailLines

        #expect(section.state == .ready)
        #expect(detailLines.contains("heartbeat_digest_visibility=suppressed"))
        #expect(detailLines.contains("heartbeat_digest_reason_codes=stable_runtime_update_suppressed"))
        #expect(detailLines.contains(where: { $0.contains("heartbeat_digest_system_next_step=") && $0.contains("有实质变化再生成用户 digest") }))
        #expect(projection.digestVisibility == XTHeartbeatDigestVisibilityDecision.suppressed.rawValue)
        #expect(projection.digestReasonCodes.contains("stable_runtime_update_suppressed"))
        #expect(projection.digestReasonCodes.contains("project_memory_attention"))
        #expect(projection.digestWhatChangedText == "Validation remains on track")
        #expect(projection.digestWhyImportantText.contains("digest 被压制"))
        #expect(projection.digestSystemNextStepText.contains("有实质变化再生成用户 digest"))
        #expect(projection.recoveryDecision == nil)
    }

    @Test
    func sessionRuntimeSectionIncludesStructuredMemoryPolicyProjectionsWhenAvailable() {
        let model = sampleModel(id: "hub.model.coder")
        let projectPolicy = XTProjectMemoryPolicySnapshot(
            configuredRecentProjectDialogueProfile: .deep20Pairs,
            configuredProjectContextDepth: .full,
            recommendedRecentProjectDialogueProfile: .extended40Pairs,
            recommendedProjectContextDepth: .deep,
            effectiveRecentProjectDialogueProfile: .extended40Pairs,
            effectiveProjectContextDepth: .deep,
            aTierMemoryCeiling: .m3DeepDive
        )
        let projectResolution = XTMemoryAssemblyResolution(
            role: .projectAI,
            trigger: "guided_execution",
            configuredDepth: AXProjectContextDepthProfile.full.rawValue,
            recommendedDepth: AXProjectContextDepthProfile.deep.rawValue,
            effectiveDepth: AXProjectContextDepthProfile.deep.rawValue,
            ceilingFromTier: XTMemoryServingProfile.m3DeepDive.rawValue,
            ceilingHit: true,
            selectedSlots: [
                "recent_project_dialogue_window",
                "focused_project_anchor_pack",
                "active_workflow",
                "selected_cross_link_hints",
                "guidance",
            ],
            selectedPlanes: [
                "project_dialogue_plane",
                "project_anchor_plane",
                "workflow_plane",
                "cross_link_plane",
                "guidance_plane",
            ],
            selectedServingObjects: [
                "recent_project_dialogue_window",
                "focused_project_anchor_pack",
                "active_workflow",
                "selected_cross_link_hints",
                "guidance",
            ],
            excludedBlocks: ["assistant_plane", "personal_memory", "portfolio_brief"]
        )
        let supervisorPolicy = XTSupervisorMemoryPolicySnapshot(
            configuredSupervisorRecentRawContextProfile: .autoMax,
            configuredReviewMemoryDepth: .auto,
            recommendedSupervisorRecentRawContextProfile: .extended40Pairs,
            recommendedReviewMemoryDepth: .deepDive,
            effectiveSupervisorRecentRawContextProfile: .extended40Pairs,
            effectiveReviewMemoryDepth: .deepDive,
            sTierReviewMemoryCeiling: .m4FullScan
        )
        let supervisorResolution = XTMemoryAssemblyResolution(
            role: .supervisor,
            dominantMode: SupervisorTurnMode.projectFirst.rawValue,
            trigger: "heartbeat_no_progress_review",
            configuredDepth: XTSupervisorReviewMemoryDepthProfile.auto.rawValue,
            recommendedDepth: XTSupervisorReviewMemoryDepthProfile.deepDive.rawValue,
            effectiveDepth: XTSupervisorReviewMemoryDepthProfile.deepDive.rawValue,
            ceilingFromTier: XTMemoryServingProfile.m4FullScan.rawValue,
            ceilingHit: false,
            selectedSlots: [
                "recent_raw_dialogue_window",
                "portfolio_brief",
                "focused_project_anchor_pack",
                "delta_feed",
                "conflict_set",
                "context_refs",
                "evidence_pack",
            ],
            selectedPlanes: ["continuity_lane", "project_plane", "cross_link_plane"],
            selectedServingObjects: [
                "recent_raw_dialogue_window",
                "portfolio_brief",
                "focused_project_anchor_pack",
                "delta_feed",
                "conflict_set",
                "context_refs",
                "evidence_pack",
            ],
            excludedBlocks: []
        )
        let diagnostics = AXProjectContextAssemblyDiagnosticsSummary(
            latestEvent: nil,
            detailLines: [
                "project_context_diagnostics_source=config_only",
                "project_context_project=Snake",
                "recent_project_dialogue_profile=extended_40_pairs",
                "recent_project_dialogue_selected_pairs=18",
                "recent_project_dialogue_floor_pairs=8",
                "recent_project_dialogue_floor_satisfied=true",
                "recent_project_dialogue_source=xt_cache",
                "recent_project_dialogue_low_signal_dropped=3",
                "project_context_depth=deep",
                "effective_project_serving_profile=m3_deep_dive",
                "workflow_present=true",
                "execution_evidence_present=false",
                "review_guidance_present=true",
                "cross_link_hints_selected=2",
                "personal_memory_excluded_reason=project_ai_default_scopes_to_project_memory_only",
                "project_memory_policy_json=\(compactJSONString(projectPolicy))",
                "project_memory_assembly_resolution_json=\(compactJSONString(projectResolution))",
            ]
        )
        let memorySnapshot = makeSupervisorMemoryAssemblySnapshot(
            selectedSections: [
                "dialogue_window",
                "portfolio_brief",
                "focused_project_anchor_pack",
                "cross_link_refs",
                "delta_feed",
                "context_refs"
            ],
            omittedSections: ["conflict_set", "evidence_pack"],
            servingObjectContract: [
                "dialogue_window",
                "portfolio_brief",
                "focused_project_anchor_pack",
                "cross_link_refs",
                "delta_feed",
                "conflict_set",
                "context_refs",
                "evidence_pack",
            ],
            supervisorMemoryPolicy: supervisorPolicy,
            memoryAssemblyResolution: supervisorResolution
        )

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                projectContextDiagnostics: diagnostics,
                supervisorMemoryAssemblySnapshot: memorySnapshot
            )
        )

        let section = report.section(.sessionRuntimeReadiness)
        #expect(section?.state == .ready)
        #expect(section?.projectMemoryPolicyProjection == projectPolicy)
        #expect(section?.projectMemoryReadinessProjection?.ready == false)
        #expect(section?.projectMemoryReadinessProjection?.issueCodes == ["project_memory_usage_missing"])
        #expect(section?.projectMemoryAssemblyResolutionProjection == projectResolution)
        #expect(section?.supervisorMemoryPolicyProjection == supervisorPolicy)
        #expect(section?.supervisorMemoryAssemblyResolutionProjection?.selectedServingObjects == [
            "recent_raw_dialogue_window",
            "portfolio_brief",
            "focused_project_anchor_pack",
            "cross_link_refs",
            "delta_feed",
            "context_refs"
        ])
        #expect(section?.supervisorMemoryAssemblyResolutionProjection?.excludedBlocks.contains("conflict_set") == true)
        #expect(section?.supervisorMemoryAssemblyResolutionProjection?.excludedBlocks.contains("evidence_pack") == true)
        #expect(section?.detailLines.contains("project_memory_readiness_issue_codes=project_memory_usage_missing") == true)
    }

    @Test
    func sessionRuntimeSectionFeedsProjectMemoryReadinessIntoHeartbeatProjection() throws {
        let model = sampleModel(id: "hub.model.coder")
        let diagnostics = AXProjectContextAssemblyDiagnosticsSummary(
            latestEvent: nil,
            detailLines: [
                "project_context_diagnostics_source=config_only",
                "project_context_project=Snake",
                "project_context_diagnostics=no_recent_coder_usage"
            ]
        )

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                projectContextDiagnostics: diagnostics,
                heartbeatGovernanceSnapshot: sampleHeartbeatGovernanceSnapshot()
            )
        )

        let section = try #require(report.section(.sessionRuntimeReadiness))
        let projection = try #require(section.heartbeatGovernanceProjection)

        #expect(projection.projectMemoryReady == false)
        #expect(projection.projectMemoryIssueCodes == ["project_memory_usage_missing"])
        #expect(projection.digestReasonCodes.contains("project_memory_attention"))
        #expect(projection.projectMemoryTopIssueSummary?.contains("最近一次 memory 装配真相") == true)
        #expect(section.detailLines.contains("heartbeat_project_memory_ready=false"))
        #expect(section.detailLines.contains("heartbeat_project_memory_issue_codes=project_memory_usage_missing"))
    }

    @Test
    func sessionRuntimeSectionIncludesDurableCandidateMirrorProjectionWhenAvailable() {
        let model = sampleModel(id: "hub.model.coder")
        let mirrorSnapshot = makeSupervisorMemoryAssemblySnapshot(
            durableCandidateMirrorStatus: .localOnly,
            durableCandidateMirrorTarget: XTSupervisorDurableCandidateMirror.mirrorTarget,
            durableCandidateMirrorAttempted: true,
            durableCandidateMirrorErrorCode: "remote_route_not_preferred",
            durableCandidateLocalStoreRole: XTSupervisorDurableCandidateMirror.localStoreRole,
            localPersonalMemoryWriteIntent: SupervisorPersonalMemoryStoreWriteIntent.manualEditBufferCommit.rawValue,
            localCrossLinkWriteIntent: SupervisorCrossLinkStoreWriteIntent.afterTurnCacheRefresh.rawValue,
            localPersonalReviewWriteIntent: SupervisorPersonalReviewNoteStoreWriteIntent.derivedRefresh.rawValue
        )

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                supervisorMemoryAssemblySnapshot: mirrorSnapshot
            )
        )

        let section = report.section(.sessionRuntimeReadiness)
        #expect(section?.state == .ready)
        #expect(section?.detailLines.contains(where: {
            $0.contains("durable_candidate_mirror status=local_only")
                && $0.contains("reason=remote_route_not_preferred")
                && $0.contains("local_store_role=\(XTSupervisorDurableCandidateMirror.localStoreRole)")
        }) == true)
        #expect(section?.detailLines.contains(where: {
            $0.contains("xt_local_store_writes")
                && $0.contains("personal_memory=\(SupervisorPersonalMemoryStoreWriteIntent.manualEditBufferCommit.rawValue)")
                && $0.contains("cross_link=\(SupervisorCrossLinkStoreWriteIntent.afterTurnCacheRefresh.rawValue)")
                && $0.contains("personal_review=\(SupervisorPersonalReviewNoteStoreWriteIntent.derivedRefresh.rawValue)")
        }) == true)
        #expect(section?.durableCandidateMirrorProjection?.status == .localOnly)
        #expect(section?.durableCandidateMirrorProjection?.target == XTSupervisorDurableCandidateMirror.mirrorTarget)
        #expect(section?.durableCandidateMirrorProjection?.attempted == true)
        #expect(section?.durableCandidateMirrorProjection?.errorCode == "remote_route_not_preferred")
        #expect(section?.durableCandidateMirrorProjection?.localStoreRole == XTSupervisorDurableCandidateMirror.localStoreRole)
        #expect(section?.localStoreWriteProjection?.personalMemoryIntent == SupervisorPersonalMemoryStoreWriteIntent.manualEditBufferCommit.rawValue)
        #expect(section?.localStoreWriteProjection?.crossLinkIntent == SupervisorCrossLinkStoreWriteIntent.afterTurnCacheRefresh.rawValue)
        #expect(section?.localStoreWriteProjection?.personalReviewIntent == SupervisorPersonalReviewNoteStoreWriteIntent.derivedRefresh.rawValue)
    }

    @Test
    func sessionRuntimeSectionIncludesSupervisorTurnContextDetailLineWhenAvailable() {
        let model = sampleModel(id: "hub.model.coder")
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                supervisorLatestTurnContextAssembly: makeSupervisorTurnContextAssembly()
            )
        )

        let section = report.section(.sessionRuntimeReadiness)
        #expect(section?.state == .ready)
        #expect(section?.detailLines.contains(where: {
            $0.contains("supervisor_turn_context")
                && $0.contains("turn_mode=hybrid")
                && $0.contains("dominant_plane=assistant_plane+project_plane")
                && $0.contains("continuity_depth=full")
                && $0.contains("assistant_depth=medium")
                && $0.contains("project_depth=medium")
                && $0.contains("cross_link_depth=full")
                && $0.contains("selected_slots=dialogue_window,personal_capsule,focused_project_capsule,portfolio_brief,cross_link_refs,evidence_pack")
        }) == true)
    }

    @Test
    func builderPublishesFrozenSourceReportContractInConsumedContracts() {
        let model = sampleModel(id: "hub.model.coder")
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot()
            )
        )

        #expect(report.consumedContracts.contains(XTUnifiedDoctorReportContract.frozen.schemaVersion))
        #expect(!report.consumedContracts.contains(XTUnifiedDoctorReport.currentSchemaVersion))
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
        #expect(decoded.section(.wakeProfileReadiness) != nil)
        #expect(decoded.section(.talkLoopReadiness) != nil)
        #expect(decoded.sections.count == XTUnifiedDoctorSectionKind.allCases.count)
    }

    @Test
    func fallsBackToNonAtomicOverwriteWhenAtomicWriteRunsOutOfSpace() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-unified-doctor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let capture = XTUnifiedDoctorStoreTestCapture()
        let reportURL = XTUnifiedDoctorStore.defaultReportURL(workspaceRoot: tempRoot)
        try FileManager.default.createDirectory(
            at: reportURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{\"stale\":true}\n".utf8).write(to: reportURL)

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [sampleModel(id: "hub.model.coder").id],
                models: [sampleModel(id: "hub.model.coder")],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                reportPath: reportURL.path
            )
        )

        XTUnifiedDoctorStore.installWriteAttemptOverrideForTesting { data, url, options in
            capture.appendWriteOption(options)
            if options.contains(.atomic) {
                throw NSError(domain: NSPOSIXErrorDomain, code: 28)
            }
            try data.write(to: url, options: options)
        }
        XTUnifiedDoctorStore.installLogSinkForTesting { line in
            capture.appendLogLine(line)
        }
        defer { XTUnifiedDoctorStore.resetWriteBehaviorForTesting() }

        XTUnifiedDoctorStore.writeReport(report, to: reportURL)

        let decoded = try JSONDecoder().decode(
            XTUnifiedDoctorReport.self,
            from: Data(contentsOf: reportURL)
        )
        let options = capture.writeOptionsSnapshot()
        #expect(options.count == 2)
        #expect(options[0].contains(.atomic))
        #expect(options[1].isEmpty)
        #expect(capture.logLinesSnapshot().isEmpty)
        #expect(decoded.reportPath == reportURL.path)
    }

    @Test
    func suppressesRepeatedWriteFailureLogsDuringCooldown() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-unified-doctor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let capture = XTUnifiedDoctorStoreTestCapture()
        let reportURL = XTUnifiedDoctorStore.defaultReportURL(workspaceRoot: tempRoot)
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [sampleModel(id: "hub.model.coder").id],
                models: [sampleModel(id: "hub.model.coder")],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                reportPath: reportURL.path
            )
        )

        XTUnifiedDoctorStore.installNowProviderForTesting {
            Date(timeIntervalSince1970: 1_741_300_000)
        }
        XTUnifiedDoctorStore.installWriteAttemptOverrideForTesting { _, _, options in
            capture.appendWriteOption(options)
            throw NSError(domain: NSPOSIXErrorDomain, code: 28)
        }
        XTUnifiedDoctorStore.installLogSinkForTesting { line in
            capture.appendLogLine(line)
        }
        defer { XTUnifiedDoctorStore.resetWriteBehaviorForTesting() }

        XTUnifiedDoctorStore.writeReport(report, to: reportURL)
        XTUnifiedDoctorStore.writeReport(report, to: reportURL)

        let logLines = capture.logLinesSnapshot()
        #expect(logLines.count == 1)
        #expect(logLines[0].contains("XTUnifiedDoctor write report failed"))
        #expect(capture.writeOptionsSnapshot().count == 2)
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
        #expect(report.readyForFirstTask == true)
        #expect(report.overallSummary != "配对、模型路由、工具链路和会话运行时已在同一路径验证通过")
        #expect(report.overallSummary.contains("仍需修复") == true)
        #expect(section?.state == .inProgress)
        #expect(section?.headline == "默认技能基线还不完整")
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

    @Test
    func skillsSectionKeepsBuiltinGovernedSkillsVisibleWhenHubIndexIsUnavailable() {
        let model = sampleModel(id: "hub.model.coder")
        var skills = readySkillsSnapshot()
        skills.hubIndexAvailable = false
        skills.statusKind = .unavailable
        skills.statusLine = "skills?"
        skills.compatibilityExplain = "skills compatibility unavailable"
        skills.builtinGovernedSkills = defaultBuiltinGovernedSkills()

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: false,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: false,
                bridgeEnabled: false,
                sessionRuntime: nil,
                skillsSnapshot: skills
            )
        )

        let section = report.section(.skillsCompatibilityReadiness)
        #expect(section?.detailLines.contains("xt_builtin_governed_skills=1") == true)
        #expect(section?.detailLines.contains("xt_builtin_governed_preview=supervisor-voice") == true)
        #expect(section?.detailLines.contains("xt_builtin_supervisor_voice=available") == true)
        #expect(section?.summary.contains("XT 原生内置技能仍可用") == true)
    }

    @Test
    func skillsSectionElevatesTypedSkillDoctorTruthWhenBlockedSkillsRemain() throws {
        let model = sampleModel(id: "hub.model.coder")
        let projection = sampleSkillDoctorTruthProjection()

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                skillDoctorTruthProjection: projection
            )
        )

        let section = try #require(report.section(.skillsCompatibilityReadiness))
        #expect(section.state == .diagnosticRequired)
        #expect(section.headline == "技能 doctor truth 已发现不可运行项")
        #expect(section.skillDoctorTruthProjection?.effectiveProfileSnapshot.projectId == "project-alpha")
        #expect(section.skillDoctorTruthProjection?.grantRequiredSkillCount == 1)
        #expect(section.skillDoctorTruthProjection?.approvalRequiredSkillCount == 1)
        #expect(section.skillDoctorTruthProjection?.blockedSkillCount == 1)
        #expect(section.detailLines.contains("skill_doctor_truth_present=true") == true)
        #expect(section.detailLines.contains("skill_readiness_blocked_skills=1") == true)
        #expect(section.detailLines.contains("skill_profile_grant_required_profiles=browser_research") == true)
    }

    @Test
    func modelRouteSectionSurfacesRecentProjectIncidentsWithoutPretendingHubIsMissing() {
        let model = sampleModel(id: "hub.model.coder")
        let diagnostics = AXModelRouteDiagnosticsSummary(
            recentEventCount: 1,
            recentFailureCount: 1,
            recentRemoteRetryRecoveryCount: 0,
            latestEvent: AXModelRouteDiagnosticEvent(
                schemaVersion: AXModelRouteDiagnosticEvent.currentSchemaVersion,
                createdAt: 1_741_300_020,
                projectId: "project-alpha",
                projectDisplayName: "Alpha",
                role: "coder",
                stage: "chat_plan",
                requestedModelId: "openai/gpt-5.4",
                actualModelId: "qwen3-14b-mlx",
                runtimeProvider: "Hub (Local)",
                executionPath: "hub_downgraded_to_local",
                fallbackReasonCode: "downgrade_to_local",
                remoteRetryAttempted: false,
                remoteRetryFromModelId: "",
                remoteRetryToModelId: "",
                remoteRetryReasonCode: ""
            ),
            detailLines: [
                "recent_route_events_24h=1",
                "recent_route_failures_24h=1",
                "route_event_1=project=Alpha role=coder path=hub_downgraded_to_local requested=openai/gpt-5.4 actual=qwen3-14b-mlx reason=downgrade_to_local provider=Hub (Local)"
            ]
        )

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                modelRouteDiagnostics: diagnostics
            )
        )

        let section = report.section(.modelRouteReadiness)
        #expect(section?.state == .ready)
        #expect(section?.headline == "模型路由已就绪，但最近有项目链路退化")
        #expect(section?.nextStep.contains("/route diagnose") == true)
        #expect(section?.nextStep.contains("自动改试上次稳定远端") == true)
        #expect(section?.nextStep.contains("只有你想把模型固定下来时") == true)
        #expect(section?.nextStep.contains("Supervisor Control Center · AI 模型") == true)
        #expect(section?.detailLines.contains("recent_route_failures_24h=1") == true)
        #expect(section?.detailLines.contains(where: { $0.contains("hub_downgraded_to_local") }) == true)
        #expect(section?.memoryRouteTruthProjection?.projectionSource == "xt_model_route_diagnostics_summary")
        #expect(section?.memoryRouteTruthProjection?.routeResult.routeSource == "hub_downgraded_to_local")
        #expect(section?.memoryRouteTruthProjection?.winningBinding.modelID == "qwen3-14b-mlx")
    }

    @Test
    func modelRouteSectionExplainsRemoteGrpcDowngradeAsHubSideNotXTSilentRewrite() {
        let model = sampleModel(id: "hub.model.coder")
        let diagnostics = AXModelRouteDiagnosticsSummary(
            recentEventCount: 1,
            recentFailureCount: 1,
            recentRemoteRetryRecoveryCount: 0,
            latestEvent: AXModelRouteDiagnosticEvent(
                schemaVersion: AXModelRouteDiagnosticEvent.currentSchemaVersion,
                createdAt: 1_741_300_020,
                projectId: "project-alpha",
                projectDisplayName: "Alpha",
                role: "coder",
                stage: "chat_plan",
                requestedModelId: "openai/gpt-5.4",
                actualModelId: "qwen3-14b-mlx",
                runtimeProvider: "Hub (Local)",
                executionPath: "hub_downgraded_to_local",
                fallbackReasonCode: "downgrade_to_local",
                remoteRetryAttempted: false,
                remoteRetryFromModelId: "",
                remoteRetryToModelId: "",
                remoteRetryReasonCode: ""
            ),
            detailLines: [
                "recent_route_events_24h=1",
                "recent_route_failures_24h=1",
                "route_event_1=project=Alpha role=coder path=hub_downgraded_to_local requested=openai/gpt-5.4 actual=qwen3-14b-mlx reason=downgrade_to_local provider=Hub (Local)"
            ]
        )

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: false,
                remoteConnected: true,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                modelRouteDiagnostics: diagnostics
            )
        )

        let section = report.section(.modelRouteReadiness)
        #expect(section?.summary.contains("当前传输已经是远端 gRPC") == true)
        #expect(section?.summary.contains("不是 XT 把模型静默改成了本地") == true)
        #expect(section?.nextStep.contains("ai.generate.downgraded_to_local") == true)
        #expect(section?.nextStep.contains("不要先怀疑 XT 设置页偷偷改了模型") == true)
        #expect(section?.detailLines.contains("route_truth_grpc_hint=hub_downgrade_not_xt_rewrite") == true)
    }

    @Test
    func modelRouteSectionSeparatesSupervisorRoutePlaneBlockersFromModelIssues() {
        let model = sampleModel(id: "hub.model.coder")
        let diagnostics = AXModelRouteDiagnosticsSummary(
            recentEventCount: 1,
            recentFailureCount: 1,
            recentRemoteRetryRecoveryCount: 0,
            latestEvent: AXModelRouteDiagnosticEvent(
                schemaVersion: AXModelRouteDiagnosticEvent.currentSchemaVersion,
                createdAt: 1_741_300_020,
                projectId: "project-alpha",
                projectDisplayName: "Alpha",
                role: "coder",
                stage: "chat_plan",
                requestedModelId: "openai/gpt-5.4",
                actualModelId: "",
                runtimeProvider: "Hub",
                executionPath: "remote_error",
                fallbackReasonCode: "preferred_device_offline",
                auditRef: "route-audit-supervisor-1",
                remoteRetryAttempted: false,
                remoteRetryFromModelId: "",
                remoteRetryToModelId: "",
                remoteRetryReasonCode: ""
            ),
            detailLines: [
                "recent_route_events_24h=1",
                "recent_route_failures_24h=1",
                "route_event_1=project=Alpha role=coder path=remote_error requested=openai/gpt-5.4 actual=(none) reason=preferred_device_offline provider=Hub audit_ref=route-audit-supervisor-1"
            ]
        )

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: true,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                modelRouteDiagnostics: diagnostics
            )
        )

        let section = report.section(.modelRouteReadiness)
        #expect(section?.headline == "Supervisor route 还没就绪")
        #expect(section?.summary.contains("首选 XT 设备当前离线") == true)
        #expect(section?.nextStep.contains("/route diagnose") == true)
        #expect(section?.detailLines.contains("route_truth_supervisor_component=route_ready") == true)
        #expect(section?.detailLines.contains("route_truth_deny_code=preferred_device_offline") == true)
    }

    @Test
    func modelRouteSectionSurfacesModelNotReadyIssueFromRecentRouteTruth() {
        let model = sampleModel(id: "hub.model.coder")
        let diagnostics = AXModelRouteDiagnosticsSummary(
            recentEventCount: 1,
            recentFailureCount: 1,
            recentRemoteRetryRecoveryCount: 0,
            latestEvent: AXModelRouteDiagnosticEvent(
                schemaVersion: AXModelRouteDiagnosticEvent.currentSchemaVersion,
                createdAt: 1_741_300_020,
                projectId: "project-alpha",
                projectDisplayName: "Alpha",
                role: "coder",
                stage: "chat_plan",
                requestedModelId: "openai/gpt-5.4",
                actualModelId: "",
                runtimeProvider: "OpenAI",
                executionPath: "remote_error",
                fallbackReasonCode: "provider_not_ready",
                auditRef: "route-audit-1",
                remoteRetryAttempted: false,
                remoteRetryFromModelId: "",
                remoteRetryToModelId: "",
                remoteRetryReasonCode: ""
            ),
            detailLines: [
                "recent_route_events_24h=1",
                "recent_route_failures_24h=1",
                "route_event_1=project=Alpha role=coder path=remote_error requested=openai/gpt-5.4 reason=provider_not_ready provider=OpenAI audit_ref=route-audit-1"
            ]
        )

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                modelRouteDiagnostics: diagnostics
            )
        )

        let section = report.section(.modelRouteReadiness)
        #expect(section?.state == .blockedWaitingUpstream)
        #expect(section?.headline == "模型提供方尚未就绪")
        #expect(section?.summary.contains("提供方未就绪") == true)
        #expect(section?.nextStep.contains("Supervisor Control Center · AI 模型") == true)
        #expect(section?.nextStep.contains("REL Flow Hub → 模型与付费访问") == true)
        #expect(section?.repairEntry == .xtChooseModel)
        #expect(section?.detailLines.contains("route_truth_issue=model_not_ready") == true)
        #expect(section?.detailLines.contains("route_truth_primary_code=provider_not_ready") == true)
        #expect(report.readyForFirstTask == false)
        #expect(report.overallSummary.contains("模型提供方尚未就绪") == true)
    }

    @Test
    func modelRouteSectionSurfacesConnectorScopeBlockedFromRecentRouteTruth() {
        let model = sampleModel(id: "hub.model.coder")
        let diagnostics = AXModelRouteDiagnosticsSummary(
            recentEventCount: 1,
            recentFailureCount: 1,
            recentRemoteRetryRecoveryCount: 0,
            latestEvent: AXModelRouteDiagnosticEvent(
                schemaVersion: AXModelRouteDiagnosticEvent.currentSchemaVersion,
                createdAt: 1_741_300_020,
                projectId: "project-alpha",
                projectDisplayName: "Alpha",
                role: "coder",
                stage: "chat_plan",
                requestedModelId: "openai/gpt-5.4",
                actualModelId: "qwen3-14b-mlx",
                runtimeProvider: "Hub (Local)",
                executionPath: "hub_downgraded_to_local",
                fallbackReasonCode: "grant_required;deny_code=remote_export_blocked",
                auditRef: "route-audit-2",
                denyCode: "remote_export_blocked",
                remoteRetryAttempted: false,
                remoteRetryFromModelId: "",
                remoteRetryToModelId: "",
                remoteRetryReasonCode: ""
            ),
            detailLines: [
                "recent_route_events_24h=1",
                "recent_route_failures_24h=1",
                "route_event_1=project=Alpha role=coder path=hub_downgraded_to_local requested=openai/gpt-5.4 actual=qwen3-14b-mlx reason=grant_required;deny_code=remote_export_blocked deny_code=remote_export_blocked provider=Hub (Local) audit_ref=route-audit-2"
            ]
        )

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                modelRouteDiagnostics: diagnostics
            )
        )

        let section = report.section(.modelRouteReadiness)
        #expect(section?.state == .diagnosticRequired)
        #expect(section?.headline == "远端导出被 Hub 导出开关拦住")
        #expect(section?.summary.contains("这不是模型缺失，也不是连接 Hub 没连上") == true)
        #expect(section?.nextStep.contains("REL Flow Hub → 诊断与恢复") == true)
        #expect(section?.nextStep.contains("REL Flow Hub → 安全边界") == true)
        #expect(section?.repairEntry == .hubDiagnostics)
        #expect(section?.detailLines.contains("route_truth_issue=connector_scope_blocked") == true)
        #expect(section?.detailLines.contains("route_truth_primary_code=grant_required;deny_code=remote_export_blocked") == true)
        #expect(section?.detailLines.contains("route_truth_deny_code=remote_export_blocked") == true)
        #expect(report.readyForFirstTask == false)
        #expect(report.overallSummary.contains("远端导出被 Hub 导出开关拦住") == true)
    }

    @Test
    func modelRouteSectionExplainsRemoteGrpcExportGateAsHubSideNotXTSilentRewrite() {
        let model = sampleModel(id: "hub.model.coder")
        let diagnostics = AXModelRouteDiagnosticsSummary(
            recentEventCount: 1,
            recentFailureCount: 1,
            recentRemoteRetryRecoveryCount: 0,
            latestEvent: AXModelRouteDiagnosticEvent(
                schemaVersion: AXModelRouteDiagnosticEvent.currentSchemaVersion,
                createdAt: 1_741_300_020,
                projectId: "project-alpha",
                projectDisplayName: "Alpha",
                role: "coder",
                stage: "chat_plan",
                requestedModelId: "openai/gpt-5.4",
                actualModelId: "qwen3-14b-mlx",
                runtimeProvider: "Hub (Local)",
                executionPath: "hub_downgraded_to_local",
                fallbackReasonCode: "grant_required;deny_code=remote_export_blocked",
                auditRef: "route-audit-2",
                denyCode: "remote_export_blocked",
                remoteRetryAttempted: false,
                remoteRetryFromModelId: "",
                remoteRetryToModelId: "",
                remoteRetryReasonCode: ""
            ),
            detailLines: [
                "recent_route_events_24h=1",
                "recent_route_failures_24h=1",
                "route_event_1=project=Alpha role=coder path=hub_downgraded_to_local requested=openai/gpt-5.4 actual=qwen3-14b-mlx reason=grant_required;deny_code=remote_export_blocked deny_code=remote_export_blocked provider=Hub (Local) audit_ref=route-audit-2"
            ]
        )

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: false,
                remoteConnected: true,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                modelRouteDiagnostics: diagnostics
            )
        )

        let section = report.section(.modelRouteReadiness)
        #expect(section?.summary.contains("当前传输已经是远端 gRPC") == true)
        #expect(section?.summary.contains("Hub 的远端导出闸门或策略把付费远端调用挡住了") == true)
        #expect(section?.summary.contains("不是 XT 把模型静默改成了本地") == true)
        #expect(section?.nextStep.contains("拒绝原因") == true)
        #expect(section?.detailLines.contains("route_truth_grpc_hint=remote_export_gate_not_xt_rewrite") == true)
    }

    @Test
    func modelRouteSectionSurfacesPaidModelAccessBlockedFromRecentRouteTruth() {
        let model = sampleModel(id: "hub.model.coder")
        let diagnostics = AXModelRouteDiagnosticsSummary(
            recentEventCount: 1,
            recentFailureCount: 1,
            recentRemoteRetryRecoveryCount: 0,
            latestEvent: AXModelRouteDiagnosticEvent(
                schemaVersion: AXModelRouteDiagnosticEvent.currentSchemaVersion,
                createdAt: 1_741_300_020,
                projectId: "project-alpha",
                projectDisplayName: "Alpha",
                role: "coder",
                stage: "chat_plan",
                requestedModelId: "openai/gpt-5.4",
                actualModelId: "",
                runtimeProvider: "OpenAI",
                executionPath: "remote_error",
                fallbackReasonCode: "device_paid_model_not_allowed",
                auditRef: "route-audit-3",
                remoteRetryAttempted: false,
                remoteRetryFromModelId: "",
                remoteRetryToModelId: "",
                remoteRetryReasonCode: ""
            ),
            detailLines: [
                "recent_route_events_24h=1",
                "recent_route_failures_24h=1",
                "route_event_1=project=Alpha role=coder path=remote_error requested=openai/gpt-5.4 reason=device_paid_model_not_allowed provider=OpenAI audit_ref=route-audit-3"
            ]
        )

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                modelRouteDiagnostics: diagnostics
            )
        )

        let section = report.section(.modelRouteReadiness)
        #expect(section?.state == .diagnosticRequired)
        #expect(section?.headline == "当前设备不允许使用付费模型")
        #expect(section?.summary.contains("付费模型白名单") == true)
        #expect(section?.nextStep.contains("REL Flow Hub → 配对与设备信任") == true)
        #expect(section?.nextStep.contains("REL Flow Hub → 模型与付费访问") == true)
        #expect(section?.repairEntry == .xtChooseModel)
        #expect(section?.detailLines.contains("route_truth_issue=paid_model_access_blocked") == true)
        #expect(section?.detailLines.contains("route_truth_primary_code=device_paid_model_not_allowed") == true)
        #expect(report.readyForFirstTask == false)
        #expect(report.overallSummary.contains("当前设备不允许使用付费模型") == true)
    }

    @Test
    func writesStructuredMemoryRouteProjectionIntoMachineReadableReport() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-unified-doctor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let reportURL = XTUnifiedDoctorStore.defaultReportURL(workspaceRoot: tempRoot)
        let model = sampleModel(id: "hub.model.coder")
        let diagnostics = AXModelRouteDiagnosticsSummary(
            recentEventCount: 1,
            recentFailureCount: 1,
            recentRemoteRetryRecoveryCount: 0,
            latestEvent: AXModelRouteDiagnosticEvent(
                schemaVersion: AXModelRouteDiagnosticEvent.currentSchemaVersion,
                createdAt: 1_741_300_020,
                projectId: "project-alpha",
                projectDisplayName: "Alpha",
                role: "coder",
                stage: "chat_plan",
                requestedModelId: "openai/gpt-5.4",
                actualModelId: "qwen3-14b-mlx",
                runtimeProvider: "Hub (Local)",
                executionPath: "hub_downgraded_to_local",
                fallbackReasonCode: "downgrade_to_local",
                remoteRetryAttempted: false,
                remoteRetryFromModelId: "",
                remoteRetryToModelId: "",
                remoteRetryReasonCode: ""
            ),
            detailLines: [
                "recent_route_events_24h=1",
                "recent_route_failures_24h=1"
            ]
        )

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                reportPath: reportURL.path,
                modelRouteDiagnostics: diagnostics
            )
        )
        XTUnifiedDoctorStore.writeReport(report, to: reportURL)

        let data = try Data(contentsOf: reportURL)
        let decoded = try JSONDecoder().decode(XTUnifiedDoctorReport.self, from: data)
        let projection = decoded.section(.modelRouteReadiness)?.memoryRouteTruthProjection

        #expect(projection?.projectionSource == "xt_model_route_diagnostics_summary")
        #expect(projection?.routeResult.routeSource == "hub_downgraded_to_local")
        #expect(projection?.routeResult.routeReasonCode == "downgrade_to_local")
        #expect(projection?.winningBinding.provider == "Hub (Local)")
    }

    @Test
    func writesStructuredProjectContextPresentationIntoMachineReadableReport() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-unified-doctor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let reportURL = XTUnifiedDoctorStore.defaultReportURL(workspaceRoot: tempRoot)
        let model = sampleModel(id: "hub.model.coder")
        let diagnostics = AXProjectContextAssemblyDiagnosticsSummary(
            latestEvent: nil,
            detailLines: [
                "project_context_diagnostics_source=latest_coder_usage",
                "project_context_project=Structured Project",
                "recent_project_dialogue_profile=extended_40_pairs",
                "recent_project_dialogue_selected_pairs=18",
                "recent_project_dialogue_floor_pairs=8",
                "recent_project_dialogue_floor_satisfied=true",
                "recent_project_dialogue_source=xt_cache",
                "recent_project_dialogue_low_signal_dropped=1",
                "project_context_depth=full",
                "effective_project_serving_profile=m4_full_scan",
                "workflow_present=true",
                "execution_evidence_present=true",
                "review_guidance_present=false",
                "cross_link_hints_selected=2",
                "project_memory_selected_planes=project_dialogue_plane,project_anchor_plane,evidence_plane"
            ]
        )

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                reportPath: reportURL.path,
                projectContextDiagnostics: diagnostics
            )
        )
        XTUnifiedDoctorStore.writeReport(report, to: reportURL)

        let data = try Data(contentsOf: reportURL)
        let decoded = try JSONDecoder().decode(XTUnifiedDoctorReport.self, from: data)
        let presentation = decoded.section(.sessionRuntimeReadiness)?.projectContextPresentation

        #expect(presentation?.sourceKind == .latestCoderUsage)
        #expect(presentation?.projectLabel == "Structured Project")
        #expect(presentation?.sourceBadge == "Latest Usage")
        #expect(presentation?.dialogueMetric.contains("40 pairs") == true)
        #expect(presentation?.depthMetric.contains("Full") == true)
        #expect(presentation?.coverageMetric == "wf yes · ev yes · gd no · xlink 2")
        #expect(presentation?.planeLine == "Active Planes：项目对话面、项目锚点面和证据面")
    }

    @Test
    func writesStructuredHubMemoryPromptProjectionIntoMachineReadableReport() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-unified-doctor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let reportURL = XTUnifiedDoctorStore.defaultReportURL(workspaceRoot: tempRoot)
        let model = sampleModel(id: "hub.model.coder")
        let diagnostics = AXProjectContextAssemblyDiagnosticsSummary(
            latestEvent: nil,
            detailLines: [
                "project_context_diagnostics_source=latest_coder_usage",
                "hub_memory_prompt_projection_projection_source=hub_generate_done_metadata",
                "hub_memory_prompt_projection_canonical_item_count=3",
                "hub_memory_prompt_projection_working_set_turn_count=8",
                "hub_memory_prompt_projection_runtime_truth_item_count=2",
                "hub_memory_prompt_projection_runtime_truth_source_kinds=guidance_injection,heartbeat_projection"
            ]
        )

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                reportPath: reportURL.path,
                projectContextDiagnostics: diagnostics
            )
        )
        XTUnifiedDoctorStore.writeReport(report, to: reportURL)

        let data = try Data(contentsOf: reportURL)
        let decoded = try JSONDecoder().decode(XTUnifiedDoctorReport.self, from: data)
        let projection = decoded.section(.sessionRuntimeReadiness)?.hubMemoryPromptProjection

        #expect(projection?.projectionSource == "hub_generate_done_metadata")
        #expect(projection?.canonicalItemCount == 3)
        #expect(projection?.workingSetTurnCount == 8)
        #expect(projection?.runtimeTruthItemCount == 2)
        #expect(projection?.runtimeTruthSourceKinds == ["guidance_injection", "heartbeat_projection"])
    }

    @Test
    func decodesLegacyHeartbeatGovernanceProjectionWhenProjectMemoryFieldsAreMissing() throws {
        let model = sampleModel(id: "hub.model.coder")
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                heartbeatGovernanceSnapshot: sampleHeartbeatGovernanceSnapshot()
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(report)
        var payload = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var sections = try #require(payload["sections"] as? [[String: Any]])
        let sectionIndex = try #require(
            sections.firstIndex(where: { $0["kind"] as? String == XTUnifiedDoctorSectionKind.sessionRuntimeReadiness.rawValue })
        )
        var sessionSection = sections[sectionIndex]
        var heartbeatProjection = try #require(
            sessionSection["heartbeatGovernanceProjection"] as? [String: Any]
        )
        heartbeatProjection.removeValue(forKey: "projectMemoryReady")
        heartbeatProjection.removeValue(forKey: "projectMemoryStatusLine")
        heartbeatProjection.removeValue(forKey: "projectMemoryIssueCodes")
        heartbeatProjection.removeValue(forKey: "projectMemoryTopIssueSummary")
        sessionSection["heartbeatGovernanceProjection"] = heartbeatProjection
        sections[sectionIndex] = sessionSection
        payload["sections"] = sections

        let legacyData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let decoded = try JSONDecoder().decode(XTUnifiedDoctorReport.self, from: legacyData)
        let decodedProjection = try #require(
            decoded.section(.sessionRuntimeReadiness)?.heartbeatGovernanceProjection
        )

        #expect(decodedProjection.projectMemoryReady == nil)
        #expect(decodedProjection.projectMemoryStatusLine == nil)
        #expect(decodedProjection.projectMemoryIssueCodes.isEmpty)
        #expect(decodedProjection.projectMemoryTopIssueSummary == nil)
    }

    @Test
    func heartbeatGovernanceProjectionCarriesProjectMemoryTruthIntoDoctorStatusAndDetails() throws {
        let model = sampleModel(id: "hub.model.coder")
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                heartbeatGovernanceSnapshot: sampleHeartbeatGovernanceSnapshotWithProjectMemoryContext()
            )
        )

        let section = try #require(report.section(.sessionRuntimeReadiness))
        let projection = try #require(section.heartbeatGovernanceProjection)

        #expect(section.detailLines.contains("heartbeat_project_memory_source=latest_coder_usage"))
        #expect(section.detailLines.contains(where: {
            $0.contains("heartbeat_project_memory_actual_resolution")
                && $0.contains("effective_depth=deep")
        }))
        #expect(projection.projectMemoryStatusLine?.contains("latest coder usage") == true)
        #expect(projection.projectMemoryStatusLine?.contains("effective depth=deep") == true)
        #expect(projection.projectMemoryStatusLine?.contains("heartbeat digest 已在 Project AI working set 中") == true)
    }

    @Test
    func decodesLegacyHubMemoryPromptProjectionWhenNestedKeysUseCamelCase() throws {
        let model = sampleModel(id: "hub.model.coder")
        let diagnostics = AXProjectContextAssemblyDiagnosticsSummary(
            latestEvent: nil,
            detailLines: [
                "project_context_diagnostics_source=latest_coder_usage",
                "hub_memory_prompt_projection_projection_source=hub_generate_done_metadata",
                "hub_memory_prompt_projection_canonical_item_count=3",
                "hub_memory_prompt_projection_working_set_turn_count=18",
                "hub_memory_prompt_projection_runtime_truth_item_count=2",
                "hub_memory_prompt_projection_runtime_truth_source_kinds=guidance_injection,heartbeat_projection"
            ]
        )

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                projectContextDiagnostics: diagnostics
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(report)
        var payload = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var sections = try #require(payload["sections"] as? [[String: Any]])
        let sectionIndex = try #require(
            sections.firstIndex(where: { $0["kind"] as? String == XTUnifiedDoctorSectionKind.sessionRuntimeReadiness.rawValue })
        )
        var sessionSection = sections[sectionIndex]
        let projection = try #require(sessionSection["hubMemoryPromptProjection"] as? [String: Any])
        sessionSection["hubMemoryPromptProjection"] = [
            "projectionSource": projection["projection_source"] as Any,
            "canonicalItemCount": projection["canonical_item_count"] as Any,
            "workingSetTurnCount": projection["working_set_turn_count"] as Any,
            "runtimeTruthItemCount": projection["runtime_truth_item_count"] as Any,
            "runtimeTruthSourceKinds": projection["runtime_truth_source_kinds"] as Any,
        ]
        sections[sectionIndex] = sessionSection
        payload["sections"] = sections

        let legacyData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let decoded = try JSONDecoder().decode(XTUnifiedDoctorReport.self, from: legacyData)
        let decodedProjection = try #require(
            decoded.section(.sessionRuntimeReadiness)?.hubMemoryPromptProjection
        )

        #expect(decodedProjection.projectionSource == "hub_generate_done_metadata")
        #expect(decodedProjection.canonicalItemCount == 3)
        #expect(decodedProjection.workingSetTurnCount == 18)
        #expect(decodedProjection.runtimeTruthItemCount == 2)
        #expect(decodedProjection.runtimeTruthSourceKinds == ["guidance_injection", "heartbeat_projection"])
    }

    @Test
    func summarizesProjectAutomationVerificationContractsForDoctorCard() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-unified-doctor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let reportURL = XTUnifiedDoctorStore.defaultReportURL(workspaceRoot: tempRoot)
        let model = sampleModel(id: "hub.model.coder")
        let diagnostics = AXProjectContextAssemblyDiagnosticsSummary(
            latestEvent: nil,
            detailLines: [
                "project_memory_automation_context_source=checkpoint+execution_report+retry_package",
                "project_memory_v1_source=hub_snapshot_plus_local_overlay",
                "memory_v1_freshness=ttl_cache",
                "project_memory_automation_run_id=run-automation-1",
                "project_memory_automation_run_state=blocked",
                "project_memory_automation_current_step_title=Verify focused smoke tests",
                "project_memory_automation_current_step_state=retry_wait",
                "project_memory_automation_verification_present=true",
                "project_memory_automation_blocker_present=true",
                "project_memory_automation_retry_reason_present=true",
                #"project_memory_automation_verification_contract_json={"expected_state":"post_change_verification_passes","verify_method":"project_verify_commands","retry_policy":"retry_failed_verify_commands_within_budget","hold_policy":"hold_for_retry_or_replan","evidence_required":true,"trigger_action_ids":["action-verify"],"verify_commands":["swift test --filter SmokeTests"]}"#,
                #"project_memory_automation_retry_verification_contract_json={"expected_state":"post_change_verification_passes","verify_method":"project_verify_commands_override","retry_policy":"manual_retry_or_replan","hold_policy":"hold_for_retry_or_replan","evidence_required":false,"trigger_action_ids":["retry-action-verify"],"verify_commands":["swift test --filter RetrySmokeTests"]}"#
            ]
        )

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                reportPath: reportURL.path,
                projectContextDiagnostics: diagnostics
            )
        )
        XTUnifiedDoctorStore.writeReport(report, to: reportURL)

        let data = try Data(contentsOf: reportURL)
        let decoded = try JSONDecoder().decode(XTUnifiedDoctorReport.self, from: data)
        let section = try #require(decoded.section(.sessionRuntimeReadiness))
        let summary = XTDoctorProjectAutomationContinuityPresentation.summary(detailLines: section.detailLines)

        #expect(summary?.title == "自动续跑连续性")
        #expect(summary?.lines.contains(where: { $0.contains("验证合同：项目校验命令") }) == true)
        #expect(summary?.lines.contains(where: { $0.contains("重试验证合同：覆写校验命令") }) == true)
        #expect(summary?.lines.contains(where: { $0.contains("当前运行：run-automation-1") }) == true)
    }

    @Test
    func writesStructuredMemoryPolicyProjectionsIntoMachineReadableReport() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-unified-doctor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let reportURL = XTUnifiedDoctorStore.defaultReportURL(workspaceRoot: tempRoot)
        let model = sampleModel(id: "hub.model.coder")
        let projectPolicy = XTProjectMemoryPolicySnapshot(
            configuredRecentProjectDialogueProfile: .floor8Pairs,
            configuredProjectContextDepth: .balanced,
            recommendedRecentProjectDialogueProfile: .deep20Pairs,
            recommendedProjectContextDepth: .deep,
            effectiveRecentProjectDialogueProfile: .deep20Pairs,
            effectiveProjectContextDepth: .deep,
            aTierMemoryCeiling: .m3DeepDive
        )
        let projectResolution = XTMemoryAssemblyResolution(
            role: .projectAI,
            trigger: "execution_evidence_present",
            configuredDepth: AXProjectContextDepthProfile.balanced.rawValue,
            recommendedDepth: AXProjectContextDepthProfile.deep.rawValue,
            effectiveDepth: AXProjectContextDepthProfile.deep.rawValue,
            ceilingFromTier: XTMemoryServingProfile.m3DeepDive.rawValue,
            ceilingHit: false,
            selectedSlots: ["recent_project_dialogue_window", "focused_project_anchor_pack", "execution_evidence"],
            selectedPlanes: ["project_dialogue_plane", "project_anchor_plane", "evidence_plane"],
            selectedServingObjects: ["recent_project_dialogue_window", "focused_project_anchor_pack", "execution_evidence"],
            excludedBlocks: ["guidance"]
        )
        let supervisorPolicy = XTSupervisorMemoryPolicySnapshot(
            configuredSupervisorRecentRawContextProfile: .autoMax,
            configuredReviewMemoryDepth: .auto,
            recommendedSupervisorRecentRawContextProfile: .deep20Pairs,
            recommendedReviewMemoryDepth: .planReview,
            effectiveSupervisorRecentRawContextProfile: .deep20Pairs,
            effectiveReviewMemoryDepth: .planReview,
            sTierReviewMemoryCeiling: .m2PlanReview
        )
        let supervisorResolution = XTMemoryAssemblyResolution(
            role: .supervisor,
            dominantMode: SupervisorTurnMode.projectFirst.rawValue,
            trigger: "heartbeat_periodic_pulse_review",
            configuredDepth: XTSupervisorReviewMemoryDepthProfile.auto.rawValue,
            recommendedDepth: XTSupervisorReviewMemoryDepthProfile.compact.rawValue,
            effectiveDepth: XTSupervisorReviewMemoryDepthProfile.planReview.rawValue,
            ceilingFromTier: XTMemoryServingProfile.m2PlanReview.rawValue,
            ceilingHit: false,
            selectedSlots: ["recent_raw_dialogue_window", "focused_project_anchor_pack", "delta_feed", "conflict_set"],
            selectedPlanes: ["continuity_lane", "project_plane", "cross_link_plane"],
            selectedServingObjects: ["recent_raw_dialogue_window", "focused_project_anchor_pack", "delta_feed", "conflict_set"],
            excludedBlocks: ["portfolio_brief"]
        )
        let memorySnapshot = makeSupervisorMemoryAssemblySnapshot(
            selectedSections: [
                "dialogue_window",
                "focused_project_anchor_pack",
                "delta_feed",
                "conflict_set",
            ],
            omittedSections: [
                "portfolio_brief",
                "cross_link_refs",
                "context_refs",
                "evidence_pack",
            ],
            servingObjectContract: [
                "dialogue_window",
                "portfolio_brief",
                "focused_project_anchor_pack",
                "delta_feed",
                "conflict_set",
                "context_refs",
                "evidence_pack",
            ],
            supervisorMemoryPolicy: supervisorPolicy,
            memoryAssemblyResolution: supervisorResolution
        )
        let expectedSupervisorResolution = try #require(memorySnapshot.actualizedMemoryAssemblyResolution)

        var report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                reportPath: reportURL.path,
                supervisorMemoryAssemblySnapshot: memorySnapshot
            )
        )
        let sessionIndex = try #require(
            report.sections.firstIndex(where: { $0.kind == .sessionRuntimeReadiness })
        )
        report.sections[sessionIndex].projectMemoryPolicyProjection = projectPolicy
        report.sections[sessionIndex].projectMemoryReadinessProjection = XTProjectMemoryAssemblyReadiness(
            ready: false,
            statusLine: "attention:project_memory_usage_missing",
            issues: [
                XTProjectMemoryAssemblyIssue(
                    code: "project_memory_usage_missing",
                    severity: .warning,
                    summary: "尚未捕获 Project AI 的最近一次 memory 装配真相",
                    detail: "Doctor 当前只能看到配置基线，还没有 recent coder usage 来证明 Project AI 最近一轮真正吃到了哪些 memory objects / planes。"
                )
            ]
        )
        report.sections[sessionIndex].projectMemoryAssemblyResolutionProjection = projectResolution

        XTUnifiedDoctorStore.writeReport(report, to: reportURL)

        let data = try Data(contentsOf: reportURL)
        let decoded = try JSONDecoder().decode(XTUnifiedDoctorReport.self, from: data)
        let section = decoded.section(.sessionRuntimeReadiness)

        #expect(section?.projectMemoryPolicyProjection == projectPolicy)
        #expect(section?.projectMemoryReadinessProjection?.issueCodes == ["project_memory_usage_missing"])
        #expect(section?.projectMemoryAssemblyResolutionProjection == projectResolution)
        #expect(section?.supervisorMemoryPolicyProjection == supervisorPolicy)
        #expect(section?.supervisorMemoryAssemblyResolutionProjection == expectedSupervisorResolution)
    }

    @Test
    func writesStructuredDurableCandidateMirrorProjectionIntoMachineReadableReport() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-unified-doctor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let reportURL = XTUnifiedDoctorStore.defaultReportURL(workspaceRoot: tempRoot)
        let model = sampleModel(id: "hub.model.coder")
        let mirrorSnapshot = makeSupervisorMemoryAssemblySnapshot(
            durableCandidateMirrorStatus: .mirroredToHub,
            durableCandidateMirrorTarget: XTSupervisorDurableCandidateMirror.mirrorTarget,
            durableCandidateMirrorAttempted: true,
            durableCandidateMirrorErrorCode: nil,
            durableCandidateLocalStoreRole: XTSupervisorDurableCandidateMirror.localStoreRole
        )

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                reportPath: reportURL.path,
                supervisorMemoryAssemblySnapshot: mirrorSnapshot
            )
        )
        XTUnifiedDoctorStore.writeReport(report, to: reportURL)

        let data = try Data(contentsOf: reportURL)
        let decoded = try JSONDecoder().decode(XTUnifiedDoctorReport.self, from: data)
        let projection = decoded.section(.sessionRuntimeReadiness)?.durableCandidateMirrorProjection

        #expect(projection?.status == .mirroredToHub)
        #expect(projection?.target == XTSupervisorDurableCandidateMirror.mirrorTarget)
        #expect(projection?.attempted == true)
        #expect(projection?.errorCode == nil)
        #expect(projection?.localStoreRole == XTSupervisorDurableCandidateMirror.localStoreRole)
    }

    @Test
    func writesStructuredLocalStoreWriteProjectionIntoMachineReadableReport() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-unified-doctor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let reportURL = XTUnifiedDoctorStore.defaultReportURL(workspaceRoot: tempRoot)
        let model = sampleModel(id: "hub.model.coder")
        let mirrorSnapshot = makeSupervisorMemoryAssemblySnapshot(
            localPersonalMemoryWriteIntent: SupervisorPersonalMemoryStoreWriteIntent.manualEditBufferCommit.rawValue,
            localCrossLinkWriteIntent: SupervisorCrossLinkStoreWriteIntent.afterTurnCacheRefresh.rawValue,
            localPersonalReviewWriteIntent: SupervisorPersonalReviewNoteStoreWriteIntent.derivedRefresh.rawValue
        )

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                reportPath: reportURL.path,
                supervisorMemoryAssemblySnapshot: mirrorSnapshot
            )
        )
        XTUnifiedDoctorStore.writeReport(report, to: reportURL)

        let data = try Data(contentsOf: reportURL)
        let decoded = try JSONDecoder().decode(XTUnifiedDoctorReport.self, from: data)
        let projection = decoded.section(.sessionRuntimeReadiness)?.localStoreWriteProjection

        #expect(projection?.personalMemoryIntent == SupervisorPersonalMemoryStoreWriteIntent.manualEditBufferCommit.rawValue)
        #expect(projection?.crossLinkIntent == SupervisorCrossLinkStoreWriteIntent.afterTurnCacheRefresh.rawValue)
        #expect(projection?.personalReviewIntent == SupervisorPersonalReviewNoteStoreWriteIntent.derivedRefresh.rawValue)
    }

    @Test
    func voicePlaybackSectionSurfacesHubVoicePackFallbackDetails() {
        let model = sampleModel(id: "hub.model.coder")
        var preferences = VoiceRuntimePreferences.default()
        preferences.playbackPreference = .hubVoicePack
        preferences.preferredHubVoicePackID = "hub.voice.zh.warm"

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                voicePreferences: preferences
            )
        )

        let section = report.section(.voicePlaybackReadiness)
        #expect(section?.state == .inProgress)
        #expect(section?.headline == "首选 Hub 语音包暂未就绪")
        #expect(section?.detailLines.contains("requested_playback_source=hub_voice_pack") == true)
        #expect(section?.detailLines.contains("resolved_playback_source=system_speech") == true)
        #expect(section?.detailLines.contains("preferred_voice_pack_id=hub.voice.zh.warm") == true)
        #expect(section?.detailLines.contains("fallback_from=hub_voice_pack") == true)
    }

    @Test
    func voicePlaybackSectionPrefersRecentFallbackPlaybackTruth() {
        let model = sampleModel(id: "hub.model.coder")
        var preferences = VoiceRuntimePreferences.default()
        preferences.playbackPreference = .hubVoicePack
        preferences.preferredHubVoicePackID = "hub.voice.zh.warm"

        let playbackActivity = VoicePlaybackActivity(
            state: .fallbackPlayed,
            configuredResolution: VoicePlaybackResolution(
                requestedPreference: .hubVoicePack,
                resolvedSource: .systemSpeech,
                preferredHubVoicePackID: "hub.voice.zh.warm",
                resolvedHubVoicePackID: "",
                reasonCode: "preferred_hub_voice_pack_unavailable",
                fallbackFrom: .hubVoicePack
            ),
            actualSource: .systemSpeech,
            reasonCode: "hub_voice_pack_runtime_failed",
            detail: "",
            provider: "hub_voice_pack",
            modelID: "hub.voice.zh.warm",
            engineName: "",
            speakerId: "",
            deviceBackend: "system_speech",
            nativeTTSUsed: nil,
            fallbackMode: "hub_voice_pack_unavailable",
            fallbackReasonCode: "hub_voice_pack_runtime_failed",
            audioFormat: "",
            voiceName: "",
            updatedAt: 42
        )

        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                voicePreferences: preferences,
                voicePlaybackActivity: playbackActivity
            )
        )

        let section = report.section(.voicePlaybackReadiness)
        #expect(section?.state == .inProgress)
        #expect(section?.headline == "最近一次播放已回退到系统语音")
        #expect(section?.summary.contains("播放已从 Hub 语音包 回退到 系统语音。") == true)
        #expect(
            section?.nextStep
                == "如果你想恢复 Hub 语音包，请打开 Supervisor 设置，检查语音包是否仍在 Hub Library，且本机 Hub IPC 已报告 ready。"
        )
        #expect(section?.repairEntry == .homeSupervisor)
        #expect(section?.detailLines.contains("recent_playback_state=fallback_played") == true)
        #expect(section?.detailLines.contains("recent_playback_output=system_speech") == true)
        #expect(section?.detailLines.contains("recent_playback_reason=hub_voice_pack_runtime_failed") == true)
        #expect(
            section?.detailLines.contains(where: { line in
                line.contains("voice_playback state=fallback_played")
                    && line.contains("output=system_speech")
                    && line.contains("fallback_from=hub_voice_pack")
                    && line.contains("provider=hub_voice_pack")
            }) == true
        )
    }

    @Test
    func doctorIncludesPermissionSpecificWakeAndTalkVoiceSections() {
        let model = sampleModel(id: "hub.model.coder")
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                voiceAuthorizationStatus: .denied,
                voicePermissionSnapshot: VoicePermissionSnapshot(
                    microphone: .authorized,
                    speechRecognition: .denied
                )
            )
        )

        let wakeSection = report.section(.wakeProfileReadiness)
        let talkSection = report.section(.talkLoopReadiness)

        #expect(report.readyForFirstTask == true)
        #expect(report.overallSummary.contains("唤醒配置就绪 仍需修复") == true)
        #expect(report.overallSummary.contains("唤醒配置被语音识别权限阻塞") == true)
        #expect(wakeSection?.state == .permissionDenied)
        #expect(wakeSection?.headline == "唤醒配置被语音识别权限阻塞")
        #expect(wakeSection?.nextStep == "请先在 macOS 系统设置中授予语音识别权限，然后刷新语音运行时。")
        #expect(talkSection?.state == .permissionDenied)
        #expect(talkSection?.headline == "对话链路被语音识别权限阻塞")
        #expect(talkSection?.nextStep == "请先在 macOS 系统设置中授予语音识别权限，然后刷新语音运行时。")
    }

    @Test
    func doctorProjectsWakeVoiceSmokeFailureIntoWakeSection() {
        let model = sampleModel(id: "hub.model.coder")
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                supervisorVoiceSmokeReport: makeSupervisorVoiceSmokeReport(
                    failedCheckID: "wake_prompt_spoken",
                    failedDetail: "wake follow-up prompt missing"
                )
            )
        )

        let wakeSection = report.section(.wakeProfileReadiness)
        let talkSection = report.section(.talkLoopReadiness)

        #expect(report.readyForFirstTask == true)
        #expect(report.overallSummary.contains("唤醒配置就绪 仍需修复") == true)
        #expect(report.overallSummary.contains("唤醒阶段未通过") == true)
        #expect(wakeSection?.state == .diagnosticRequired)
        #expect(wakeSection?.headline == "Supervisor 语音自检显示：唤醒阶段未通过")
        #expect(wakeSection?.detailLines.contains("voice_smoke_phase=wake") == true)
        #expect(wakeSection?.detailLines.contains("voice_smoke_phase_status=failed") == true)
        #expect(talkSection?.detailLines.contains("voice_smoke_phase=grant") == true)
        #expect(talkSection?.detailLines.contains("voice_smoke_phase_status=not_reached") == true)
        #expect(talkSection?.state == .inProgress)
    }

    @Test
    func doctorProjectsGrantVoiceSmokeFailureIntoTalkLoopSection() {
        let model = sampleModel(id: "hub.model.coder")
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                supervisorVoiceSmokeReport: makeSupervisorVoiceSmokeReport(
                    failedCheckID: "voice_grant_challenge_issued",
                    failedDetail: "challenge not emitted"
                )
            )
        )

        let section = report.section(.talkLoopReadiness)
        #expect(section?.state == .diagnosticRequired)
        #expect(section?.headline == "Supervisor 语音自检显示：授权挑战阶段未通过")
        #expect(section?.detailLines.contains("voice_smoke_phase_status=failed") == true)
        #expect(section?.detailLines.contains("voice_smoke_failed_check=voice_grant_challenge_issued") == true)
        #expect(report.overallSummary.contains("对话链路就绪 仍需修复") == true)
    }

    @Test
    func doctorProjectsBriefVoiceSmokeFailureIntoPlaybackSection() {
        let model = sampleModel(id: "hub.model.coder")
        let report = XTUnifiedDoctorBuilder.build(
            input: makeDoctorInput(
                localConnected: true,
                remoteConnected: false,
                configuredModelIDs: [model.id],
                models: [model],
                bridgeAlive: true,
                bridgeEnabled: true,
                sessionRuntime: nil,
                skillsSnapshot: readySkillsSnapshot(),
                supervisorVoiceSmokeReport: makeSupervisorVoiceSmokeReport(
                    failedCheckID: "brief_resumed_listening",
                    failedDetail: "listening did not resume"
                )
            )
        )

        let section = report.section(.voicePlaybackReadiness)
        #expect(section?.state == .diagnosticRequired)
        #expect(section?.headline == "Supervisor 语音自检显示：Hub 简报播报阶段未通过")
        #expect(section?.detailLines.contains("voice_smoke_phase=brief_playback") == true)
        #expect(section?.detailLines.contains("voice_smoke_phase_status=failed") == true)
        #expect(report.overallSummary.contains("语音播放就绪 仍需修复") == true)
    }
}

private final class XTUnifiedDoctorStoreTestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var writeOptions: [Data.WritingOptions] = []
    private var logLines: [String] = []

    func appendWriteOption(_ option: Data.WritingOptions) {
        lock.lock()
        defer { lock.unlock() }
        writeOptions.append(option)
    }

    func appendLogLine(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        logLines.append(line)
    }

    func writeOptionsSnapshot() -> [Data.WritingOptions] {
        lock.lock()
        defer { lock.unlock() }
        return writeOptions
    }

    func logLinesSnapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return logLines
    }
}

private func makeDoctorInput(
    localConnected: Bool,
    remoteConnected: Bool,
    configuredModelIDs: [String],
    models: [HubModel],
    runtimeStatus: AIRuntimeStatus? = nil,
    bridgeAlive: Bool,
    bridgeEnabled: Bool,
    bridgeLastError: String = "",
    failureCode: String = "",
    linking: Bool = false,
    sessionRuntime: AXSessionRuntimeSnapshot?,
    sessionID: String? = nil,
    skillsSnapshot: AXSkillsDoctorSnapshot,
    voicePreferences: VoiceRuntimePreferences = .default(),
    voicePlaybackActivity: VoicePlaybackActivity = .empty,
    voiceAuthorizationStatus: VoiceTranscriberAuthorizationStatus = .undetermined,
    voicePermissionSnapshot: VoicePermissionSnapshot = .unknown,
    supervisorVoiceSmokeReport: XTSupervisorVoiceSmokeReportSummary? = nil,
    skillDoctorTruthProjection: XTUnifiedDoctorSkillDoctorTruthProjection? = nil,
    reportPath: String = "/tmp/xt_unified_doctor_report.json",
    modelRouteDiagnostics: AXModelRouteDiagnosticsSummary = .empty,
    projectContextDiagnostics: AXProjectContextAssemblyDiagnosticsSummary = .empty,
    projectGovernanceResolved: AXProjectResolvedGovernanceState? = nil,
    heartbeatGovernanceSnapshot: XTProjectHeartbeatGovernanceDoctorSnapshot? = nil,
    supervisorMemoryAssemblySnapshot: SupervisorMemoryAssemblySnapshot? = nil,
    supervisorLatestTurnContextAssembly: SupervisorTurnContextAssemblyResult? = nil,
    doctorProjectContext: AXProjectContext? = nil,
    remotePaidAccessSnapshot: HubRemotePaidAccessSnapshot? = nil,
    internetHost: String? = nil,
    freshPairReconnectSmokeSnapshot: XTFreshPairReconnectSmokeSnapshot? = nil,
    firstPairCompletionProofSnapshot: XTFirstPairCompletionProofSnapshot? = nil,
    pairedRouteSetSnapshot: XTPairedRouteSetSnapshot? = nil,
    connectivityIncidentSnapshot: XTHubConnectivityIncidentSnapshot? = nil
) -> XTUnifiedDoctorInput {
    XTUnifiedDoctorInput(
        generatedAt: Date(timeIntervalSince1970: 1_741_300_000),
        localConnected: localConnected,
        remoteConnected: remoteConnected,
        remoteRoute: .none,
        remotePaidAccessSnapshot: remotePaidAccessSnapshot,
        linking: linking,
        pairingPort: 50052,
        grpcPort: 50051,
        internetHost: internetHost ?? (localConnected ? "10.0.0.8" : "hub.example.test"),
        configuredModelIDs: configuredModelIDs,
        totalModelRoles: AXRole.allCases.count,
        failureCode: failureCode,
        runtime: .empty,
        runtimeStatus: runtimeStatus ?? AIRuntimeStatus(
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
        bridgeLastError: bridgeLastError,
        sessionID: sessionID,
        sessionTitle: sessionID == nil ? nil : "Doctor Session",
        sessionRuntime: sessionRuntime,
        voiceAuthorizationStatus: voiceAuthorizationStatus,
        voicePermissionSnapshot: voicePermissionSnapshot,
        voicePreferences: voicePreferences,
        voicePlaybackActivity: voicePlaybackActivity,
        skillsSnapshot: skillsSnapshot,
        skillDoctorTruthProjection: skillDoctorTruthProjection,
        reportPath: reportPath,
        modelRouteDiagnostics: modelRouteDiagnostics,
        projectContextDiagnostics: projectContextDiagnostics,
        projectGovernanceResolved: projectGovernanceResolved,
        heartbeatGovernanceSnapshot: heartbeatGovernanceSnapshot,
        supervisorMemoryAssemblySnapshot: supervisorMemoryAssemblySnapshot,
        supervisorLatestTurnContextAssembly: supervisorLatestTurnContextAssembly,
        doctorProjectContext: doctorProjectContext,
        supervisorVoiceSmokeReport: supervisorVoiceSmokeReport,
        freshPairReconnectSmokeSnapshot: freshPairReconnectSmokeSnapshot,
        firstPairCompletionProofSnapshot: firstPairCompletionProofSnapshot,
        pairedRouteSetSnapshot: pairedRouteSetSnapshot,
        connectivityIncidentSnapshot: connectivityIncidentSnapshot
    )
}

private func makeProviderAwareDoctorRuntimeStatus(
    updatedAt: Double = Date().timeIntervalSince1970,
    readyProviderIDs: [String],
    providers: [String: [String: Any]]
) -> AIRuntimeStatus {
    let providerStatuses = providers.reduce(into: [String: AIRuntimeProviderStatus]()) { partial, entry in
        partial[entry.key] = AIRuntimeProviderStatus(
            providerIDHint: entry.key,
            jsonObject: ["provider": entry.key] + entry.value
        )
    }
    return AIRuntimeStatus(
        pid: 42,
        updatedAt: updatedAt,
        mlxOk: false,
        runtimeVersion: "test-runtime",
        importError: nil,
        activeMemoryBytes: nil,
        peakMemoryBytes: nil,
        loadedModelCount: nil,
        schemaVersion: "xhub.local_runtime_status.v2",
        localRuntimeEntryVersion: "2026-03-12-local-provider-runtime-v1",
        runtimeAlive: true,
        providerIDs: providers.keys.sorted(),
        readyProviderIDs: readyProviderIDs,
        providerPacks: [],
        providers: providerStatuses,
        loadedInstances: [],
        loadedInstanceCount: nil
    )
}

private func + (lhs: [String: Any], rhs: [String: Any]) -> [String: Any] {
    var merged = lhs
    rhs.forEach { merged[$0.key] = $0.value }
    return merged
}

private func makeProjectRoot(named name: String) -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func makePermissionReadiness(
    accessibility: AXTrustedAutomationPermissionStatus,
    automation: AXTrustedAutomationPermissionStatus,
    screenRecording: AXTrustedAutomationPermissionStatus
) -> AXTrustedAutomationPermissionOwnerReadiness {
    AXTrustedAutomationPermissionOwnerReadiness(
        schemaVersion: AXTrustedAutomationPermissionOwnerReadiness.currentSchemaVersion,
        ownerID: "test-owner",
        ownerType: "test",
        bundleID: "com.xterminal.tests",
        installState: "installed",
        mode: "test",
        accessibility: accessibility,
        automation: automation,
        screenRecording: screenRecording,
        fullDiskAccess: .granted,
        inputMonitoring: .granted,
        canPromptUser: false,
        managedByMDM: false,
        overallState: "ready",
        openSettingsActions: [],
        auditRef: "audit-xt-unified-doctor-report-tests"
    )
}

private func sampleHeartbeatGovernanceSnapshot() -> XTProjectHeartbeatGovernanceDoctorSnapshot {
    XTProjectHeartbeatGovernanceDoctorSnapshot(
        projectId: "project-alpha",
        projectName: "Alpha",
        statusDigest: "done candidate",
        currentStateSummary: "Validation is wrapping up for release",
        nextStepSummary: "Ship release once final review clears",
        blockerSummary: "Pending pre-done review",
        lastHeartbeatAtMs: 1_741_300_000_000,
        latestQualityBand: .weak,
        latestQualityScore: 38,
        weakReasons: ["evidence_weak", "completion_confidence_low"],
        openAnomalyTypes: [.weakDoneClaim],
        projectPhase: .release,
        executionStatus: .doneCandidate,
        riskTier: .high,
        cadence: SupervisorCadenceExplainability(
            progressHeartbeat: SupervisorCadenceDimensionExplainability(
                dimension: .progressHeartbeat,
                configuredSeconds: 600,
                recommendedSeconds: 180,
                effectiveSeconds: 180,
                effectiveReasonCodes: ["adjusted_for_project_phase_release"],
                nextDueAtMs: 1_741_300_120_000,
                nextDueReasonCodes: ["waiting_for_heartbeat_window"],
                isDue: false
            ),
            reviewPulse: SupervisorCadenceDimensionExplainability(
                dimension: .reviewPulse,
                configuredSeconds: 1_200,
                recommendedSeconds: 600,
                effectiveSeconds: 600,
                effectiveReasonCodes: ["adjusted_for_project_phase_release", "tightened_for_done_candidate_status"],
                nextDueAtMs: 1_741_299_980_000,
                nextDueReasonCodes: ["pulse_review_window_elapsed"],
                isDue: true
            ),
            brainstormReview: SupervisorCadenceDimensionExplainability(
                dimension: .brainstormReview,
                configuredSeconds: 2_400,
                recommendedSeconds: 1_200,
                effectiveSeconds: 1_200,
                effectiveReasonCodes: ["adjusted_for_project_phase_release"],
                nextDueAtMs: 1_741_300_300_000,
                nextDueReasonCodes: ["waiting_for_no_progress_window"],
                isDue: false
            ),
                eventFollowUpCooldownSeconds: 600
        ),
        digestExplainability: XTHeartbeatDigestExplainability(
            visibility: .shown,
            reasonCodes: ["weak_done_claim", "quality_weak", "review_candidate_active"],
            whatChangedText: "项目已接近完成，但完成声明证据偏弱。",
            whyImportantText: "完成声明证据偏弱，系统不能把“快做完了”直接当成真实完成。",
            systemNextStepText: "Ship release once final review clears"
        ),
        recoveryDecision: HeartbeatRecoveryDecision(
            action: .queueStrategicReview,
            urgency: .urgent,
            reasonCode: "heartbeat_or_lane_signal_requires_governance_review",
            summary: "Queue a deeper governance review before resuming autonomous execution.",
            sourceSignals: [
                "anomaly:weak_done_claim",
                "review_candidate:pre_done_summary:r3_rescue:event_driven"
            ],
            anomalyTypes: [.weakDoneClaim],
            blockedLaneReasons: [],
            blockedLaneCount: 0,
            stalledLaneCount: 0,
            failedLaneCount: 0,
            recoveringLaneCount: 0,
            requiresUserAction: false,
            queuedReviewTrigger: .preDoneSummary,
            queuedReviewLevel: .r3Rescue,
            queuedReviewRunKind: .eventDriven
        )
    )
}

private func sampleHeartbeatGovernanceSnapshotWithProjectMemoryContext() -> XTProjectHeartbeatGovernanceDoctorSnapshot {
    var snapshot = sampleHeartbeatGovernanceSnapshot()
    snapshot.projectMemoryContext = XTHeartbeatProjectMemoryContextSnapshot(
        diagnosticsSource: "latest_coder_usage",
        projectMemoryPolicy: nil,
        policyMemoryAssemblyResolution: XTMemoryAssemblyResolution(
            role: .projectAI,
            trigger: "heartbeat_governance_review_due",
            configuredDepth: "balanced",
            recommendedDepth: "deep",
            effectiveDepth: "deep",
            ceilingFromTier: "m3_deep_dive",
            ceilingHit: false,
            selectedSlots: ["recent_project_dialogue_window", "focused_project_anchor_pack"],
            selectedPlanes: ["project_dialogue_plane", "project_anchor_plane"],
            selectedServingObjects: ["recent_project_dialogue_window", "focused_project_anchor_pack"],
            excludedBlocks: []
        ),
        memoryAssemblyResolution: XTMemoryAssemblyResolution(
            role: .projectAI,
            trigger: "review_guidance_follow_up",
            configuredDepth: "balanced",
            recommendedDepth: "deep",
            effectiveDepth: "deep",
            ceilingFromTier: "m3_deep_dive",
            ceilingHit: false,
            selectedSlots: ["recent_project_dialogue_window", "focused_project_anchor_pack", "workflow_summary"],
            selectedPlanes: ["project_dialogue_plane", "project_anchor_plane", "workflow_plane"],
            selectedServingObjects: ["recent_project_dialogue_window", "focused_project_anchor_pack", "workflow_summary"],
            excludedBlocks: []
        ),
        heartbeatDigestWorkingSetPresent: true,
        heartbeatDigestVisibility: "shown",
        heartbeatDigestReasonCodes: ["review_candidate_active", "weak_done_claim"]
    )
    return snapshot
}

private func sampleSuppressedHeartbeatGovernanceSnapshot() -> XTProjectHeartbeatGovernanceDoctorSnapshot {
    XTProjectHeartbeatGovernanceDoctorSnapshot(
        projectId: "project-beta",
        projectName: "Beta",
        statusDigest: "stable",
        currentStateSummary: "Validation remains on track",
        nextStepSummary: "Wait for a meaningful project delta before notifying the user",
        blockerSummary: "",
        lastHeartbeatAtMs: 1_741_300_060_000,
        latestQualityBand: .usable,
        latestQualityScore: 82,
        weakReasons: [],
        openAnomalyTypes: [],
        projectPhase: .verify,
        executionStatus: .active,
        riskTier: .medium,
        cadence: SupervisorCadenceExplainability(
            progressHeartbeat: SupervisorCadenceDimensionExplainability(
                dimension: .progressHeartbeat,
                configuredSeconds: 600,
                recommendedSeconds: 300,
                effectiveSeconds: 300,
                effectiveReasonCodes: ["adjusted_for_verification_phase"],
                nextDueAtMs: 1_741_300_360_000,
                nextDueReasonCodes: ["waiting_for_heartbeat_window"],
                isDue: false
            ),
            reviewPulse: SupervisorCadenceDimensionExplainability(
                dimension: .reviewPulse,
                configuredSeconds: 1_200,
                recommendedSeconds: 1_200,
                effectiveSeconds: 1_200,
                effectiveReasonCodes: ["configured_equals_recommended"],
                nextDueAtMs: 1_741_300_900_000,
                nextDueReasonCodes: ["waiting_for_pulse_window"],
                isDue: false
            ),
            brainstormReview: SupervisorCadenceDimensionExplainability(
                dimension: .brainstormReview,
                configuredSeconds: 2_400,
                recommendedSeconds: 2_400,
                effectiveSeconds: 2_400,
                effectiveReasonCodes: ["configured_equals_recommended"],
                nextDueAtMs: 1_741_301_800_000,
                nextDueReasonCodes: ["waiting_for_no_progress_window"],
                isDue: false
            ),
            eventFollowUpCooldownSeconds: 600
        ),
        digestExplainability: XTHeartbeatDigestExplainability(
            visibility: .suppressed,
            reasonCodes: ["stable_runtime_update_suppressed"],
            whatChangedText: "Validation remains on track",
            whyImportantText: "当前没有新的高风险或高优先级治理信号，所以这条 digest 被压制。",
            systemNextStepText: "系统会继续观察当前项目，有实质变化再生成用户 digest。"
        ),
        recoveryDecision: nil
    )
}

private func makePairedRouteSetSnapshot(
    readiness: XTPairedRouteReadiness,
    summaryLine: String,
    stableRemoteRoute: XTPairedRouteTargetSnapshot? = nil,
    readinessReasonCode: String? = nil,
    cachedReconnectSmokeStatus: String? = nil
) -> XTPairedRouteSetSnapshot {
    XTPairedRouteSetSnapshot(
        readiness: readiness,
        readinessReasonCode: readinessReasonCode ?? readiness.rawValue,
        summaryLine: summaryLine,
        hubInstanceID: "hub_test_123",
        activeRoute: nil,
        lanRoute: XTPairedRouteTargetSnapshot(
            routeKind: .lan,
            host: "192.168.0.10",
            pairingPort: 50052,
            grpcPort: 50051,
            hostKind: "raw_ip",
            source: .cachedProfileHost
        ),
        stableRemoteRoute: stableRemoteRoute,
        lastKnownGoodRoute: stableRemoteRoute,
        cachedReconnectSmokeStatus: cachedReconnectSmokeStatus,
        cachedReconnectSmokeReasonCode: nil,
        cachedReconnectSmokeSummary: nil
    )
}

private func makeFirstPairCompletionProofSnapshot(
    readiness: XTPairedRouteReadiness,
    remoteShadowSmokeStatus: XTFirstPairRemoteShadowSmokeStatus,
    stableRemoteRoutePresent: Bool,
    remoteShadowReasonCode: String? = nil,
    remoteShadowSummary: String? = nil
) -> XTFirstPairCompletionProofSnapshot {
    XTFirstPairCompletionProofSnapshot(
        generatedAtMs: 1_741_300_000_000,
        readiness: readiness,
        sameLanVerified: true,
        ownerLocalApprovalVerified: true,
        pairingMaterialIssued: true,
        cachedReconnectSmokePassed: remoteShadowSmokeStatus == .passed,
        stableRemoteRoutePresent: stableRemoteRoutePresent,
        remoteShadowSmokePassed: remoteShadowSmokeStatus == .passed,
        remoteShadowSmokeStatus: remoteShadowSmokeStatus,
        remoteShadowSmokeSource: remoteShadowSmokeStatus == .notRun ? nil : .dedicatedStableRemoteProbe,
        remoteShadowTriggeredAtMs: remoteShadowSmokeStatus == .notRun ? nil : 1_741_300_100_000,
        remoteShadowCompletedAtMs: remoteShadowSmokeStatus == .running ? nil : 1_741_300_120_000,
        remoteShadowRoute: stableRemoteRoutePresent ? .internet : nil,
        remoteShadowReasonCode: remoteShadowReasonCode,
        remoteShadowSummary: remoteShadowSummary,
        summaryLine: "first pair proof test summary"
    )
}

private func makeSupervisorVoiceSmokeReport(
    failedCheckID: String? = nil,
    failedDetail: String = ""
) -> XTSupervisorVoiceSmokeReportSummary {
    let orderedCheckIDs = [
        "wake_armed_ready",
        "wake_prompt_spoken",
        "wake_prompt_resumed_listening",
        "voice_grant_challenge_issued",
        "grant_prompt_resumed_listening",
        "grant_approved_and_brief_emitted",
        "brief_resumed_listening",
        "approve_callback_recorded",
        "brief_projection_callback_recorded",
    ]
    let checks = orderedCheckIDs.map { id in
        XTSupervisorVoiceSmokeReportSummary.Check(
            id: id,
            passed: id != failedCheckID,
            detail: id == failedCheckID ? failedDetail : "ok"
        )
    }
    return XTSupervisorVoiceSmokeReportSummary(
        schemaVersion: XTSupervisorVoiceSmokeReportSummary.currentSchemaVersion,
        outputPath: "/tmp/xt_supervisor_voice_smoke.runtime.json",
        voiceRoute: VoiceRouteMode.funasrStreaming.rawValue,
        error: nil,
        checks: checks
    )
}

private func makeSupervisorMemoryAssemblySnapshot(
    selectedSections: [String] = ["focused_project_anchor_pack"],
    omittedSections: [String] = [],
    servingObjectContract: [String] = [],
    durableCandidateMirrorStatus: SupervisorDurableCandidateMirrorStatus = .notNeeded,
    durableCandidateMirrorTarget: String? = nil,
    durableCandidateMirrorAttempted: Bool = false,
    durableCandidateMirrorErrorCode: String? = nil,
    durableCandidateLocalStoreRole: String = XTSupervisorDurableCandidateMirror.localStoreRole,
    localPersonalMemoryWriteIntent: String? = nil,
    localCrossLinkWriteIntent: String? = nil,
    localPersonalReviewWriteIntent: String? = nil,
    latestReviewNoteAvailable: Bool = false,
    latestGuidanceAvailable: Bool = false,
    latestGuidanceAckStatus: String = "",
    latestGuidanceAckRequired: Bool? = nil,
    latestGuidanceDeliveryMode: String = "",
    latestGuidanceInterventionMode: String = "",
    latestGuidanceSafePointPolicy: String = "",
    pendingAckGuidanceAvailable: Bool = false,
    pendingAckGuidanceAckStatus: String = "",
    pendingAckGuidanceAckRequired: Bool? = nil,
    pendingAckGuidanceDeliveryMode: String = "",
    pendingAckGuidanceInterventionMode: String = "",
    pendingAckGuidanceSafePointPolicy: String = "",
    supervisorMemoryPolicy: XTSupervisorMemoryPolicySnapshot? = nil,
    memoryAssemblyResolution: XTMemoryAssemblyResolution? = nil
) -> SupervisorMemoryAssemblySnapshot {
    SupervisorMemoryAssemblySnapshot(
        source: "xt_unified_doctor_test",
        resolutionSource: "xt_doctor_projection",
        updatedAt: 1_741_300_000,
        reviewLevelHint: "strategic",
        requestedProfile: "project_ai_default",
        profileFloor: "project_ai_default",
        resolvedProfile: "project_ai_default",
        attemptedProfiles: ["project_ai_default"],
        progressiveUpgradeCount: 0,
        focusedProjectId: "project-alpha",
        selectedSections: selectedSections,
        omittedSections: omittedSections,
        servingObjectContract: servingObjectContract,
        contextRefsSelected: 1,
        contextRefsOmitted: 0,
        evidenceItemsSelected: 1,
        evidenceItemsOmitted: 0,
        budgetTotalTokens: 1_024,
        usedTotalTokens: 512,
        truncatedLayers: [],
        freshness: "fresh_local_ipc",
        cacheHit: true,
        denyCode: nil,
        downgradeCode: nil,
        reasonCode: nil,
        compressionPolicy: "progressive_disclosure",
        durableCandidateMirrorStatus: durableCandidateMirrorStatus,
        durableCandidateMirrorTarget: durableCandidateMirrorTarget,
        durableCandidateMirrorAttempted: durableCandidateMirrorAttempted,
        durableCandidateMirrorErrorCode: durableCandidateMirrorErrorCode,
        durableCandidateLocalStoreRole: durableCandidateLocalStoreRole,
        localPersonalMemoryWriteIntent: localPersonalMemoryWriteIntent,
        localCrossLinkWriteIntent: localCrossLinkWriteIntent,
        localPersonalReviewWriteIntent: localPersonalReviewWriteIntent,
        latestReviewNoteAvailable: latestReviewNoteAvailable,
        latestGuidanceAvailable: latestGuidanceAvailable,
        latestGuidanceAckStatus: latestGuidanceAckStatus,
        latestGuidanceAckRequired: latestGuidanceAckRequired,
        latestGuidanceDeliveryMode: latestGuidanceDeliveryMode,
        latestGuidanceInterventionMode: latestGuidanceInterventionMode,
        latestGuidanceSafePointPolicy: latestGuidanceSafePointPolicy,
        pendingAckGuidanceAvailable: pendingAckGuidanceAvailable,
        pendingAckGuidanceAckStatus: pendingAckGuidanceAckStatus,
        pendingAckGuidanceAckRequired: pendingAckGuidanceAckRequired,
        pendingAckGuidanceDeliveryMode: pendingAckGuidanceDeliveryMode,
        pendingAckGuidanceInterventionMode: pendingAckGuidanceInterventionMode,
        pendingAckGuidanceSafePointPolicy: pendingAckGuidanceSafePointPolicy,
        supervisorMemoryPolicy: supervisorMemoryPolicy,
        memoryAssemblyResolution: memoryAssemblyResolution
    )
}

private func makeSupervisorTurnContextAssembly() -> SupervisorTurnContextAssemblyResult {
    SupervisorTurnContextAssemblyResult(
        turnMode: .hybrid,
        focusPointers: SupervisorFocusPointerState.ActivePointers(
            currentProjectId: "project-alpha",
            currentPersonName: "Alex",
            currentCommitmentId: nil,
            lastTurnMode: .hybrid
        ),
        requestedSlots: [.dialogueWindow, .personalCapsule, .focusedProjectCapsule, .portfolioBrief, .crossLinkRefs, .evidencePack],
        requestedRefs: ["dialogue_window", "personal_capsule", "focused_project_capsule", "portfolio_brief", "cross_link_refs", "evidence_pack"],
        selectedSlots: [.dialogueWindow, .personalCapsule, .focusedProjectCapsule, .portfolioBrief, .crossLinkRefs, .evidencePack],
        selectedRefs: ["dialogue_window", "personal_capsule", "focused_project_capsule", "portfolio_brief", "cross_link_refs", "evidence_pack"],
        omittedSlots: [],
        assemblyReason: ["hybrid_requires_cross_link_refs"],
        dominantPlane: "assistant_plane + project_plane",
        supportingPlanes: ["cross_link_plane", "portfolio_brief"],
        continuityLaneDepth: .full,
        assistantPlaneDepth: .medium,
        projectPlaneDepth: .medium,
        crossLinkPlaneDepth: .full
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

private func defaultBuiltinGovernedSkills() -> [AXBuiltinGovernedSkillSummary] {
    [
        AXBuiltinGovernedSkillSummary(
            skillID: "supervisor-voice",
            displayName: "Supervisor Voice",
            summary: "Inspect, preview, speak, or stop the Supervisor playback path.",
            capabilitiesRequired: ["supervisor.voice.playback"],
            sideEffectClass: "local_side_effect",
            riskLevel: "low",
            policyScope: "xt_builtin"
        )
    ]
}

private func sampleSkillDoctorTruthProjection() -> XTUnifiedDoctorSkillDoctorTruthProjection {
    XTUnifiedDoctorSkillDoctorTruthProjection(
        effectiveProfileSnapshot: sampleEffectiveSkillProfileSnapshot(),
        governanceEntries: [
            sampleSkillGovernanceEntry(
                skillID: "find-skills",
                executionReadiness: XTSkillExecutionReadinessState.ready.rawValue,
                capabilityProfiles: ["observe_only"],
                capabilityFamilies: ["skills.discover"]
            ),
            sampleSkillGovernanceEntry(
                skillID: "tavily-websearch",
                executionReadiness: XTSkillExecutionReadinessState.grantRequired.rawValue,
                whyNotRunnable: "grant floor readonly still pending",
                grantFloor: XTSkillGrantFloor.readonly.rawValue,
                approvalFloor: XTSkillApprovalFloor.hubGrant.rawValue,
                capabilityProfiles: ["browser_research"],
                capabilityFamilies: ["web.live"],
                unblockActions: ["request_hub_grant"]
            ),
            sampleSkillGovernanceEntry(
                skillID: "browser-operator",
                executionReadiness: XTSkillExecutionReadinessState.localApprovalRequired.rawValue,
                whyNotRunnable: "local approval still pending",
                grantFloor: XTSkillGrantFloor.none.rawValue,
                approvalFloor: XTSkillApprovalFloor.localApproval.rawValue,
                capabilityProfiles: ["browser_operator"],
                capabilityFamilies: ["browser.interact"],
                unblockActions: ["request_local_approval"]
            ),
            sampleSkillGovernanceEntry(
                skillID: "delivery-runner",
                executionReadiness: XTSkillExecutionReadinessState.policyClamped.rawValue,
                whyNotRunnable: "project capability bundle blocks repo.delivery",
                grantFloor: XTSkillGrantFloor.privileged.rawValue,
                approvalFloor: XTSkillApprovalFloor.hubGrantPlusLocalApproval.rawValue,
                capabilityProfiles: ["delivery"],
                capabilityFamilies: ["repo.delivery"],
                unblockActions: ["raise_execution_tier"]
            )
        ]
    )
}

private func sampleEffectiveSkillProfileSnapshot() -> XTProjectEffectiveSkillProfileSnapshot {
    XTProjectEffectiveSkillProfileSnapshot(
        schemaVersion: XTProjectEffectiveSkillProfileSnapshot.currentSchemaVersion,
        projectId: "project-alpha",
        projectName: "Alpha",
        source: "xt_project_governance+hub_skill_registry",
        executionTier: "a4_openclaw",
        runtimeSurfaceMode: "paired_hub",
        hubOverrideMode: "inherit",
        legacyToolProfile: "openclaw",
        discoverableProfiles: [
            "observe_only",
            "browser_research",
            "browser_operator",
            "delivery"
        ],
        installableProfiles: [
            "observe_only",
            "browser_research",
            "browser_operator",
            "delivery"
        ],
        requestableProfiles: [
            "observe_only",
            "browser_research",
            "browser_operator"
        ],
        runnableNowProfiles: [
            "observe_only"
        ],
        grantRequiredProfiles: [
            "browser_research"
        ],
        approvalRequiredProfiles: [
            "browser_operator"
        ],
        blockedProfiles: [
            XTProjectEffectiveSkillBlockedProfile(
                profileID: "delivery",
                reasonCode: "policy_clamped",
                state: XTSkillExecutionReadinessState.policyClamped.rawValue,
                source: "project_governance",
                unblockActions: ["raise_execution_tier"]
            )
        ],
        ceilingCapabilityFamilies: [
            "skills.discover",
            "web.live",
            "browser.interact"
        ],
        runnableCapabilityFamilies: [
            "skills.discover"
        ],
        localAutoApproveEnabled: false,
        trustedAutomationReady: true,
        profileEpoch: "epoch-1",
        trustRootSetHash: "trust-root-1",
        revocationEpoch: "revocation-1",
        officialChannelSnapshotID: "channel-1",
        runtimeSurfaceHash: "surface-1",
        auditRef: "audit-xt-skill-profile-alpha"
    )
}

private func sampleSkillGovernanceEntry(
    skillID: String,
    executionReadiness: String,
    whyNotRunnable: String = "",
    grantFloor: String = XTSkillGrantFloor.none.rawValue,
    approvalFloor: String = XTSkillApprovalFloor.none.rawValue,
    capabilityProfiles: [String],
    capabilityFamilies: [String],
    unblockActions: [String] = []
) -> AXSkillGovernanceSurfaceEntry {
    let readinessState = XTSkillCapabilityProfileSupport.readinessState(from: executionReadiness)
    let tone: AXSkillGovernanceTone = {
        switch readinessState {
        case .ready:
            return .ready
        case .grantRequired, .localApprovalRequired, .degraded:
            return .warning
        default:
            return .blocked
        }
    }()

    return AXSkillGovernanceSurfaceEntry(
        skillID: skillID,
        name: skillID,
        version: "1.0.0",
        riskLevel: "medium",
        packageSHA256: "sha-\(skillID)",
        publisherID: "publisher.test",
        sourceID: "source.test",
        policyScope: "project",
        tone: tone,
        stateLabel: XTSkillCapabilityProfileSupport.readinessLabel(executionReadiness),
        intentFamilies: ["test.intent"],
        capabilityFamilies: capabilityFamilies,
        capabilityProfiles: capabilityProfiles,
        grantFloor: grantFloor,
        approvalFloor: approvalFloor,
        discoverabilityState: "discoverable",
        installabilityState: "installable",
        requestabilityState: "requestable",
        executionReadiness: executionReadiness,
        whyNotRunnable: whyNotRunnable,
        unblockActions: unblockActions,
        trustRootValue: "trusted",
        pinnedVersionValue: "1.0.0",
        runnerRequirementValue: "xt_builtin",
        compatibilityStatusValue: "compatible",
        preflightResultValue: "ready",
        note: "",
        installHint: ""
    )
}

private func makeLocalOnlyHubDoctorReport() -> XHubDoctorOutputReport {
    let providerCheck = XHubDoctorOutputCheckResult(
        checkID: "provider_readiness_ok",
        checkKind: "provider_readiness",
        status: .pass,
        severity: .info,
        blocking: false,
        headline: "本地 provider 就绪情况正常",
        message: "Hub 至少有一个可用 provider 可以处理本地运行时任务。即使没有云 provider 或 API key，本地路径也可以独立工作。",
        nextStep: "继续观察，或直接开始第一个本地任务。",
        repairDestinationRef: "hub://settings/doctor",
        detailLines: [
            "ready_providers=transformers",
            "provider_count=1",
            "managed_service_provider_count=0",
            "managed_service_ready_count=0"
        ],
        observedAtMs: 1
    )

    return XHubDoctorOutputReport(
        schemaVersion: XHubDoctorOutputReport.currentSchemaVersion,
        contractVersion: XHubDoctorOutputReport.currentContractVersion,
        reportID: "w9-c3-local-only",
        bundleKind: .providerRuntimeReadiness,
        producer: .xHub,
        surface: .hubUI,
        overallState: .ready,
        summary: XHubDoctorOutputSummary(
            headline: "本地运行时已准备好开始第一个任务",
            passed: 4,
            failed: 0,
            warned: 0,
            skipped: 0
        ),
        readyForFirstTask: true,
        checks: [
            XHubDoctorOutputCheckResult(
                checkID: "runtime_heartbeat_ok",
                checkKind: "runtime_heartbeat",
                status: .pass,
                severity: .info,
                blocking: false,
                headline: "运行时心跳正常",
                message: "Hub 已拿到较新的本地运行时状态快照。",
                nextStep: "继续检查 provider 就绪情况。",
                repairDestinationRef: "hub://settings/diagnostics",
                detailLines: ["runtime_alive=true"],
                observedAtMs: 1
            ),
            providerCheck,
            XHubDoctorOutputCheckResult(
                checkID: "capability_gates_clear",
                checkKind: "capability_gates",
                status: .pass,
                severity: .info,
                blocking: false,
                headline: "能力闸门正常",
                message: "当前没有 Hub 启动状态在阻断本地运行时能力。",
                nextStep: "继续观察，或开始工作。",
                repairDestinationRef: "hub://settings/doctor",
                detailLines: ["blocked_capabilities=none"],
                observedAtMs: 1
            ),
            XHubDoctorOutputCheckResult(
                checkID: "runtime_monitor_ok",
                checkKind: "runtime_monitor",
                status: .pass,
                severity: .info,
                blocking: false,
                headline: "运行时监控快照可用",
                message: "Hub 已拿到本地运行时的队列、已加载实例和 provider 遥测。",
                nextStep: "开始第一个任务，或继续观察运行时活动。",
                repairDestinationRef: "hub://settings/doctor",
                detailLines: ["monitor_last_error_count=0"],
                observedAtMs: 1
            )
        ],
        nextSteps: [
            XHubDoctorOutputNextStep(
                stepID: "start_first_task",
                kind: .startFirstTask,
                label: "开始第一个任务",
                owner: .user,
                blocking: false,
                destinationRef: "hub://settings/doctor",
                instruction: "继续执行一个真实的本地运行时任务，并把这份 doctor 输出当作诊断上下文保留。"
            )
        ],
        routeSnapshot: nil,
        generatedAtMs: 1,
        reportPath: "/tmp/w9-c3-local-only.json",
        sourceReportSchemaVersion: "xhub.local_runtime_status.v2",
        sourceReportPath: "/tmp/ai_runtime_status.json",
        currentFailureCode: "",
        currentFailureIssue: nil,
        consumedContracts: [
            "xhub.doctor_output_contract.v1",
            "xhub.local_runtime_monitor.v1",
            "xhub.local_runtime_status.v2"
        ]
    )
}

private func evidenceDestinations(captureBase: URL, fileName: String) -> [URL] {
    let canonical = workspaceRoot().appendingPathComponent("build/reports").appendingPathComponent(fileName)
    let requested = captureBase.appendingPathComponent(fileName)
    var seen: Set<String> = []
    return [requested, canonical].filter { url in
        seen.insert(url.standardizedFileURL.path).inserted
    }
}

private func workspaceRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    try data.write(to: url)
}

private func compactJSONString<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    let data = try! encoder.encode(value)
    return String(data: data, encoding: .utf8)!
}

private struct W9C3LocalOnlyPostureEvidence: Codable, Equatable {
    let schemaVersion: String
    let generatedAt: String
    let status: String
    let claimScope: [String]
    let claim: String
    let hubDoctor: HubDoctorSnapshot
    let xtInventory: XTInventorySnapshot
    let xtDoctor: XTDoctorSnapshot
    let guidance: GuidanceSnapshot
    let verificationResults: [VerificationResult]
    let sourceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case status
        case claimScope = "claim_scope"
        case claim
        case hubDoctor = "hub_doctor"
        case xtInventory = "xt_inventory"
        case xtDoctor = "xt_doctor"
        case guidance
        case verificationResults = "verification_results"
        case sourceRefs = "source_refs"
    }
}

private struct HubDoctorSnapshot: Codable, Equatable {
    let overallState: String
    let headline: String
    let readyForFirstTask: Bool
    let providerHeadline: String
    let providerMessage: String

    enum CodingKeys: String, CodingKey {
        case overallState = "overall_state"
        case headline
        case readyForFirstTask = "ready_for_first_task"
        case providerHeadline = "provider_headline"
        case providerMessage = "provider_message"
    }
}

private struct XTInventorySnapshot: Codable, Equatable {
    let state: String
    let tone: String
    let headline: String
    let summary: String
    let detail: String
    let requiresAttention: Bool
    let showsStatusCard: Bool

    enum CodingKeys: String, CodingKey {
        case state
        case tone
        case headline
        case summary
        case detail
        case requiresAttention = "requires_attention"
        case showsStatusCard = "shows_status_card"
    }
}

private struct XTDoctorSnapshot: Codable, Equatable {
    let overallState: String
    let overallSummary: String
    let readyForFirstTask: Bool
    let modelRouteHeadline: String
    let modelRouteSummary: String

    enum CodingKeys: String, CodingKey {
        case overallState = "overall_state"
        case overallSummary = "overall_summary"
        case readyForFirstTask = "ready_for_first_task"
        case modelRouteHeadline = "model_route_headline"
        case modelRouteSummary = "model_route_summary"
    }
}

private struct GuidanceSnapshot: Codable, Equatable {
    let inventorySummary: String
    let localOnlyDetail: String

    enum CodingKeys: String, CodingKey {
        case inventorySummary = "inventory_summary"
        case localOnlyDetail = "local_only_detail"
    }
}

private struct VerificationResult: Codable, Equatable {
    let name: String
    let status: String
}
