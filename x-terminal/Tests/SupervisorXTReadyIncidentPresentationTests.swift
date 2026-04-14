import Foundation
import Testing
@testable import XTerminal

struct SupervisorXTReadyIncidentPresentationTests {

    @Test
    func mapBuildsHealthyExportPresentation() {
        let snapshot = SupervisorManager.XTReadyIncidentExportSnapshot(
            autoExportEnabled: true,
            ledgerIncidentCount: 12,
            requiredIncidentEventCount: 12,
            missingIncidentCodes: [],
            memoryAssemblyReady: true,
            memoryAssemblyIssues: [],
            memoryAssemblyStatusLine: "ready",
            strictE2EReady: true,
            strictE2EIssues: [],
            status: "ok",
            reportPath: "/tmp/xt-ready.json"
        )

        let presentation = SupervisorXTReadyIncidentPresentationMapper.map(snapshot: snapshot)

        #expect(presentation.iconName == "waveform.path.ecg.rectangle")
        #expect(presentation.iconTone == .success)
        #expect(presentation.summaryLine == "必需事件=12 · 已记录=12")
        #expect(presentation.statusLine.text == "状态：正常")
        #expect(presentation.statusLine.tone == .success)
        #expect(presentation.strictE2ELine.tone == .success)
        #expect(presentation.missingIncidentLine.text == "缺少事件编码：无")
        #expect(presentation.strictIssueLine.text == "严格端到端问题：无")
        #expect(presentation.memoryAssemblyLine.tone == .success)
        #expect(presentation.memoryAssemblyIssueLine == nil)
        #expect(presentation.memoryAssemblyDetailLine == nil)
        #expect(presentation.canonicalRetryStatusLine == nil)
        #expect(presentation.reportLine.text == "报告：/tmp/xt-ready.json")
        #expect(presentation.canOpenReport)
    }

    @Test
    func mapBuildsWarningPresentationWhenCodesOrMemoryIssuesRemain() {
        let snapshot = SupervisorManager.XTReadyIncidentExportSnapshot(
            autoExportEnabled: true,
            ledgerIncidentCount: 10,
            requiredIncidentEventCount: 14,
            missingIncidentCodes: ["grant_missing", "memory_gap"],
            memoryAssemblyReady: false,
            memoryAssemblyIssues: ["missing_l2", "stale_l4"],
            memoryAssemblyDetailLines: [
                "missing_l2: context_refs=0 evidence_items=0",
                "stale_l4: longterm checkpoint is 12h old"
            ],
            memoryAssemblyStatusLine: "underfed",
            strictE2EReady: true,
            strictE2EIssues: ["follow_up_missing"],
            status: "warming",
            reportPath: " "
        )

        let presentation = SupervisorXTReadyIncidentPresentationMapper.map(snapshot: snapshot)

        #expect(presentation.iconTone == .warning)
        #expect(presentation.statusLine.tone == .warning)
        #expect(presentation.missingIncidentLine.text == "缺少事件编码：grant_missing,memory_gap")
        #expect(presentation.missingIncidentLine.tone == .warning)
        #expect(presentation.strictIssueLine.text == "严格端到端问题：follow_up_missing")
        #expect(presentation.strictIssueLine.tone == .warning)
        #expect(presentation.memoryAssemblyLine.tone == .warning)
        #expect(presentation.memoryAssemblyIssueLine?.text == "记忆装配问题：missing_l2,stale_l4")
        #expect(
            presentation.memoryAssemblyDetailLine?.text ==
                "记忆装配详情：missing_l2: context_refs=0 evidence_items=0 || stale_l4: longterm checkpoint is 12h old"
        )
        #expect(presentation.memoryAssemblyDetailLine?.isSelectable == true)
        #expect(presentation.canonicalRetryStatusLine == nil)
        #expect(presentation.canOpenReport == false)
        #expect(presentation.reportLine.text == "报告：无")
    }

    @Test
    func mapBuildsDangerPresentationWhenStrictReadinessFails() {
        let snapshot = SupervisorManager.XTReadyIncidentExportSnapshot(
            autoExportEnabled: false,
            ledgerIncidentCount: 0,
            requiredIncidentEventCount: 3,
            missingIncidentCodes: [],
            memoryAssemblyReady: false,
            memoryAssemblyIssues: [],
            memoryAssemblyStatusLine: "disabled",
            strictE2EReady: false,
            strictE2EIssues: ["incident_export_missing", "policy_gap", "memory_gap", "grant_gap", "ignored_extra"],
            status: "failed_export",
            reportPath: "/tmp/failure.json"
        )

        let presentation = SupervisorXTReadyIncidentPresentationMapper.map(snapshot: snapshot)

        #expect(presentation.iconTone == .danger)
        #expect(presentation.statusLine.tone == .danger)
        #expect(presentation.strictE2ELine.text == "严格端到端：未通过")
        #expect(presentation.strictE2ELine.tone == .danger)
        #expect(presentation.strictIssueLine.text == "严格端到端问题：incident_export_missing,policy_gap,memory_gap,grant_gap")
        #expect(presentation.memoryAssemblyDetailLine == nil)
        #expect(presentation.canonicalRetryStatusLine == nil)
        #expect(presentation.canOpenReport)
    }

    @Test
    func mapBuildsWarningPresentationWhenOnlySameLANPairingIsReady() {
        let snapshot = SupervisorManager.XTReadyIncidentExportSnapshot(
            autoExportEnabled: true,
            ledgerIncidentCount: 3,
            requiredIncidentEventCount: 3,
            missingIncidentCodes: [],
            memoryAssemblyReady: true,
            memoryAssemblyIssues: [],
            memoryAssemblyStatusLine: "ready",
            strictE2EReady: true,
            strictE2EIssues: [],
            pairedRouteSetSnapshot: XHubDoctorOutputPairedRouteSetSnapshot(
                schemaVersion: XTPairedRouteSetSnapshot.currentSchemaVersion,
                readiness: XTPairedRouteReadiness.localReady.rawValue,
                readinessReasonCode: "local_pairing_ready",
                summaryLine: "当前已完成同网首配，但还没有正式异网入口。",
                hubInstanceID: nil,
                pairingProfileEpoch: nil,
                routePackVersion: nil,
                activeRoute: XHubDoctorOutputPairedRouteTargetSnapshot(
                    routeKind: XTPairedRouteTargetKind.lan.rawValue,
                    host: "192.168.0.10",
                    pairingPort: 50054,
                    grpcPort: 50053,
                    hostKind: "raw_ip",
                    source: XTPairedRouteTargetSource.cachedProfileHost.rawValue
                ),
                lanRoute: nil,
                stableRemoteRoute: nil,
                lastKnownGoodRoute: nil,
                cachedReconnectSmokeStatus: nil,
                cachedReconnectSmokeReasonCode: nil,
                cachedReconnectSmokeSummary: nil
            ),
            status: "ok",
            reportPath: "/tmp/xt-ready.json"
        )

        let presentation = SupervisorXTReadyIncidentPresentationMapper.map(snapshot: snapshot)

        #expect(presentation.iconTone == .warning)
        #expect(presentation.statusLine.tone == .warning)
        #expect(presentation.pairedRouteStatusLine?.text == "已配对路径：当前已完成同网首配，但还没有正式异网入口。")
        #expect(presentation.pairedRouteStatusLine?.tone == .warning)
    }

    @Test
    func mapSurfacesCanonicalRetryFeedback() {
        let snapshot = SupervisorManager.XTReadyIncidentExportSnapshot(
            autoExportEnabled: true,
            ledgerIncidentCount: 2,
            requiredIncidentEventCount: 2,
            missingIncidentCodes: [],
            memoryAssemblyReady: true,
            memoryAssemblyIssues: [],
            memoryAssemblyStatusLine: "ready",
            strictE2EReady: true,
            strictE2EIssues: [],
            status: "ok",
            reportPath: "/tmp/xt-ready.json"
        )
        let feedback = SupervisorManager.CanonicalMemoryRetryFeedback(
            statusLine: "canonical_sync_retry: partial ok=1 · failed=1 · waiting=0",
            detailLine: "failed: project:project-alpha(Alpha) reason=project_canonical_memory_write_failed detail=no space left",
            metaLine: "attempt: 刚刚 · last_status: 刚刚",
            tone: .warning
        )

        let presentation = SupervisorXTReadyIncidentPresentationMapper.map(
            snapshot: snapshot,
            canonicalRetryFeedback: feedback
        )

        #expect(presentation.canonicalRetryStatusLine?.text == "canonical_sync_retry: partial ok=1 · failed=1 · waiting=0")
        #expect(presentation.canonicalRetryStatusLine?.tone == .warning)
        #expect(presentation.canonicalRetryMetaLine?.text == "attempt: 刚刚 · last_status: 刚刚")
        #expect(presentation.canonicalRetryMetaLine?.tone == .neutral)
        #expect(
            presentation.canonicalRetryDetailLine?.text ==
                "failed: project:project-alpha(Alpha) reason=project_canonical_memory_write_failed detail=no space left"
        )
        #expect(presentation.canonicalRetryDetailLine?.isSelectable == true)
    }

    @Test
    func mapSurfacesHubRuntimeDiagnosis() {
        let snapshot = SupervisorManager.XTReadyIncidentExportSnapshot(
            autoExportEnabled: true,
            ledgerIncidentCount: 3,
            requiredIncidentEventCount: 3,
            missingIncidentCodes: [],
            memoryAssemblyReady: true,
            memoryAssemblyIssues: [],
            memoryAssemblyStatusLine: "ready",
            strictE2EReady: false,
            strictE2EIssues: ["hub_runtime:xhub_local_service_unreachable"],
            hubRuntimeDiagnosis: .init(
                overallState: XHubDoctorOverallState.blocked.rawValue,
                readyForFirstTask: false,
                failureCode: "xhub_local_service_unreachable",
                headline: "Hub-managed local service is unreachable",
                detailLines: [
                    "managed_service_ready_count=0",
                    "current_target=bge-small provider=transformers load_summary=ctx=8192 · ttl=600s · par=2 · id=diag-a",
                    "provider=local-chat service_state=unreachable ready=0 runtime_reason=xhub_local_service_unreachable endpoint=http://127.0.0.1:50171 execution_mode=xhub_local_service loaded_instances=0 queued=2"
                ],
                nextStep: "Start xhub_local_service or fix the configured endpoint, then refresh diagnostics.",
                actionCategory: "inspect_health_payload",
                installHint: "Inspect the local /health payload and stderr log to confirm why xhub_local_service never reached ready.",
                recommendedAction: "Inspect the local /health payload | Open Hub Diagnostics and compare /health with stderr.",
                loadConfigSummaryLine: "current_target=bge-small provider=transformers load_summary=ctx=8192 · ttl=600s · par=2 · id=diag-a"
            ),
            status: "strict_risk:hub_runtime:xhub_local_service_unreachable",
            reportPath: "/tmp/xt-ready.json"
        )

        let presentation = SupervisorXTReadyIncidentPresentationMapper.map(snapshot: snapshot)

        #expect(presentation.iconTone == .danger)
        #expect(presentation.hubRuntimeLine?.text == "Hub 运行时：阻塞 · xhub_local_service_unreachable")
        #expect(presentation.hubRuntimeLine?.tone == .danger)
        #expect(presentation.hubRuntimeIssueLine?.text == "Hub 运行时问题：Hub-managed local service is unreachable")
        #expect(
            presentation.hubRuntimeLoadConfigLine?.text ==
                "Hub 运行时加载配置：current_target=bge-small provider=transformers load_summary=ctx=8192 · ttl=600s · par=2 · id=diag-a"
        )
        #expect(presentation.hubRuntimeLoadConfigLine?.isSelectable == true)
        #expect(
            presentation.hubRuntimeDetailLine?.text ==
                "Hub 运行时详情：managed_service_ready_count=0 || provider=local-chat service_state=unreachable ready=0 runtime_reason=xhub_local_service_unreachable endpoint=http://127.0.0.1:50171 execution_mode=xhub_local_service loaded_instances=0 queued=2"
        )
        #expect(presentation.hubRuntimeDetailLine?.isSelectable == true)
        #expect(
            presentation.hubRuntimeNextLine?.text ==
                "Hub 运行时下一步：Start xhub_local_service or fix the configured endpoint, then refresh diagnostics."
        )
        #expect(presentation.hubRuntimeNextLine?.tone == .accent)
        #expect(
            presentation.hubRuntimeInstallHintLine?.text ==
                "Hub 安装提示：Inspect the local /health payload and stderr log to confirm why xhub_local_service never reached ready."
        )
        #expect(presentation.hubRuntimeInstallHintLine?.tone == .warning)
        #expect(
            presentation.hubRuntimeRecommendedActionLine?.text ==
                "Hub 建议动作：Inspect the local /health payload | Open Hub Diagnostics and compare /health with stderr."
        )
        #expect(presentation.hubRuntimeRecommendedActionLine?.tone == .accent)
    }

    @Test
    func mapSurfacesFreshPairReconnectSmoke() {
        let snapshot = SupervisorManager.XTReadyIncidentExportSnapshot(
            autoExportEnabled: true,
            ledgerIncidentCount: 3,
            requiredIncidentEventCount: 3,
            missingIncidentCodes: [],
            memoryAssemblyReady: true,
            memoryAssemblyIssues: [],
            memoryAssemblyStatusLine: "ready",
            strictE2EReady: true,
            strictE2EIssues: [],
            freshPairReconnectSmokeSnapshot: .init(
                source: XTFreshPairReconnectSmokeSource.manualOneClickSetup.rawValue,
                status: XTFreshPairReconnectSmokeStatus.failed.rawValue,
                route: HubRemoteRoute.internetTunnel.rawValue,
                triggeredAtMs: 1_741_300_010_000,
                completedAtMs: 1_741_300_011_000,
                reasonCode: "grpc_unavailable",
                summary: "first pair complete, but cached reconnect verification failed."
            ),
            status: "ok",
            reportPath: "/tmp/xt-ready.json"
        )

        let presentation = SupervisorXTReadyIncidentPresentationMapper.map(snapshot: snapshot)

        #expect(presentation.iconTone == .warning)
        #expect(
            presentation.freshPairReconnectSmokeLine?.text ==
                "首配后复连验证：失败 · 手动一键连接 · 路由 互联网隧道"
        )
        #expect(presentation.freshPairReconnectSmokeLine?.tone == .warning)
        #expect(
            presentation.freshPairReconnectSmokeDetailLine?.text ==
                "首配后复连详情：first pair complete, but cached reconnect verification failed. || reason=grpc_unavailable"
        )
        #expect(presentation.freshPairReconnectSmokeDetailLine?.isSelectable == true)
    }

    @Test
    func mapSurfacesFirstPairCompletionProof() {
        let snapshot = SupervisorManager.XTReadyIncidentExportSnapshot(
            autoExportEnabled: true,
            ledgerIncidentCount: 3,
            requiredIncidentEventCount: 3,
            missingIncidentCodes: [],
            memoryAssemblyReady: true,
            memoryAssemblyIssues: [],
            memoryAssemblyStatusLine: "ready",
            strictE2EReady: true,
            strictE2EIssues: [],
            firstPairCompletionProofSnapshot: .init(
                readiness: XTPairedRouteReadiness.remoteDegraded.rawValue,
                sameLanVerified: true,
                ownerLocalApprovalVerified: true,
                pairingMaterialIssued: true,
                cachedReconnectSmokePassed: true,
                stableRemoteRoutePresent: true,
                remoteShadowSmokePassed: false,
                remoteShadowSmokeStatus: XTFirstPairRemoteShadowSmokeStatus.failed.rawValue,
                remoteShadowSmokeSource: XTRemoteShadowReconnectSmokeSource.dedicatedStableRemoteProbe.rawValue,
                remoteShadowTriggeredAtMs: 1_741_300_020_000,
                remoteShadowCompletedAtMs: 1_741_300_021_000,
                remoteShadowRoute: HubRemoteRoute.internet.rawValue,
                remoteShadowReasonCode: "grpc_unavailable",
                remoteShadowSummary: "stable remote route shadow verification failed.",
                summaryLine: "first pair reached local readiness, but stable remote route verification is degraded.",
                generatedAtMs: 1_741_300_021_000
            ),
            status: "ok",
            reportPath: "/tmp/xt-ready.json"
        )

        let presentation = SupervisorXTReadyIncidentPresentationMapper.map(snapshot: snapshot)

        #expect(presentation.iconTone == .warning)
        #expect(
            presentation.firstPairCompletionProofLine?.text ==
                "首配完成证明：异网降级 · 同网已验证 · 缓存复连已通过 · remote shadow 失败"
        )
        #expect(presentation.firstPairCompletionProofLine?.tone == .warning)
        #expect(
            presentation.firstPairCompletionProofDetailLine?.text ==
                "首配完成详情：first pair reached local readiness, but stable remote route verification is degraded. || stable remote route shadow verification failed. || route=互联网直连 || source=稳定远端 shadow probe || reason=grpc_unavailable"
        )
        #expect(presentation.firstPairCompletionProofDetailLine?.isSelectable == true)
    }

    @Test
    func mapSurfacesPairedRouteStatusAndEntryPosture() {
        let snapshot = SupervisorManager.XTReadyIncidentExportSnapshot(
            autoExportEnabled: true,
            ledgerIncidentCount: 3,
            requiredIncidentEventCount: 3,
            missingIncidentCodes: [],
            memoryAssemblyReady: true,
            memoryAssemblyIssues: [],
            memoryAssemblyStatusLine: "ready",
            strictE2EReady: true,
            strictE2EIssues: [],
            pairedRouteSetSnapshot: XHubDoctorOutputPairedRouteSetSnapshot(
                schemaVersion: XTPairedRouteSetSnapshot.currentSchemaVersion,
                readiness: XTPairedRouteReadiness.remoteReady.rawValue,
                readinessReasonCode: "cached_remote_reconnect_smoke_verified",
                summaryLine: "正式异网入口已验证，切网后可继续重连。",
                hubInstanceID: "hub_test_123",
                pairingProfileEpoch: 7,
                routePackVersion: "v1",
                activeRoute: XHubDoctorOutputPairedRouteTargetSnapshot(
                    routeKind: XTPairedRouteTargetKind.internet.rawValue,
                    host: "hub.example.com",
                    pairingPort: 50054,
                    grpcPort: 50053,
                    hostKind: "stable_named",
                    source: XTPairedRouteTargetSource.activeConnection.rawValue
                ),
                lanRoute: nil,
                stableRemoteRoute: XHubDoctorOutputPairedRouteTargetSnapshot(
                    routeKind: XTPairedRouteTargetKind.internet.rawValue,
                    host: "hub.example.com",
                    pairingPort: 50054,
                    grpcPort: 50053,
                    hostKind: "stable_named",
                    source: XTPairedRouteTargetSource.cachedProfileInternetHost.rawValue
                ),
                lastKnownGoodRoute: nil,
                cachedReconnectSmokeStatus: "succeeded",
                cachedReconnectSmokeReasonCode: nil,
                cachedReconnectSmokeSummary: "remote reconnect succeeded"
            ),
            pairedRouteSnapshot: XHubDoctorOutputRouteSnapshot(
                transportMode: "grpc",
                routeLabel: "remote gRPC (internet)",
                pairingPort: 50054,
                grpcPort: 50053,
                internetHost: "hub.example.com"
            ),
            status: "ok",
            reportPath: "/tmp/xt-ready.json"
        )

        let presentation = SupervisorXTReadyIncidentPresentationMapper.map(snapshot: snapshot)

        #expect(presentation.pairedRouteStatusLine?.text == "已配对路径：正式异网入口已验证，切网后可继续重连。")
        #expect(presentation.pairedRouteStatusLine?.tone == .success)
        #expect(presentation.pairedRouteLine?.text == "当前连接路径：互联网直连 · gRPC · host=hub.example.com")
        #expect(presentation.pairedRouteLine?.tone == .success)
        #expect(presentation.pairedRouteLine?.isSelectable == true)
        #expect(presentation.pairedRemoteEntryLine?.text == "远端入口：正式异网入口 · host=hub.example.com")
        #expect(presentation.pairedRemoteEntryLine?.tone == .success)
        #expect(presentation.pairedRemoteEntryLine?.isSelectable == true)
    }

    @Test
    func mapSurfacesConnectivityIncidentHistory() {
        let snapshot = SupervisorManager.XTReadyIncidentExportSnapshot(
            autoExportEnabled: true,
            ledgerIncidentCount: 4,
            requiredIncidentEventCount: 4,
            missingIncidentCodes: [],
            memoryAssemblyReady: true,
            memoryAssemblyIssues: [],
            memoryAssemblyStatusLine: "ready",
            strictE2EReady: true,
            strictE2EIssues: [],
            connectivityIncidentHistory: XHubDoctorOutputConnectivityIncidentHistoryReport(
                entries: [
                    XHubDoctorOutputConnectivityIncidentSnapshot(
                        schemaVersion: XTHubConnectivityIncidentSnapshot.currentSchemaVersion,
                        incidentState: XTHubConnectivityIncidentState.retrying.rawValue,
                        reasonCode: "grpc_unavailable",
                        summaryLine: "remote route not active; retrying degraded remote route ...",
                        trigger: XTHubConnectivityDecisionTrigger.backgroundKeepalive.rawValue,
                        decisionReasonCode: "retry_degraded_remote_route",
                        pairedRouteReadiness: XTPairedRouteReadiness.remoteDegraded.rawValue,
                        stableRemoteRouteHost: "hub.tailnet.example",
                        currentFailureCode: "grpc_unavailable",
                        currentPath: nil,
                        lastUpdatedAtMs: 1_741_300_020_000
                    ),
                    XHubDoctorOutputConnectivityIncidentSnapshot(
                        schemaVersion: XTHubConnectivityIncidentSnapshot.currentSchemaVersion,
                        incidentState: XTHubConnectivityIncidentState.none.rawValue,
                        reasonCode: "remote_route_active",
                        summaryLine: "validated remote route is active; no connectivity repair is needed.",
                        trigger: XTHubConnectivityDecisionTrigger.backgroundKeepalive.rawValue,
                        decisionReasonCode: "remote_route_already_active",
                        pairedRouteReadiness: XTPairedRouteReadiness.remoteReady.rawValue,
                        stableRemoteRouteHost: "hub.tailnet.example",
                        currentFailureCode: nil,
                        currentPath: nil,
                        lastUpdatedAtMs: 1_741_300_021_000
                    )
                ]
            ),
            status: "ok",
            reportPath: "/tmp/xt-ready.json"
        )

        let presentation = SupervisorXTReadyIncidentPresentationMapper.map(snapshot: snapshot)

        #expect(
            presentation.connectivityIncidentHistoryLine?.text ==
                "最近连接轨迹：最近 2 次 · 重试中(grpc_unavailable) -> 已恢复(remote_route_active)"
        )
        #expect(presentation.connectivityIncidentHistoryLine?.tone == .success)
        #expect(presentation.connectivityIncidentHistoryLine?.isSelectable == true)
    }

    @Test
    func mapSurfacesConnectivityRepairLedger() {
        let snapshot = SupervisorManager.XTReadyIncidentExportSnapshot(
            autoExportEnabled: true,
            ledgerIncidentCount: 4,
            requiredIncidentEventCount: 4,
            missingIncidentCodes: [],
            memoryAssemblyReady: true,
            memoryAssemblyIssues: [],
            memoryAssemblyStatusLine: "ready",
            strictE2EReady: true,
            strictE2EIssues: [],
            connectivityRepairLedger: XTConnectivityRepairLedgerSnapshot(
                schemaVersion: XTConnectivityRepairLedgerSnapshot.currentSchemaVersion,
                updatedAtMs: 1_741_300_027_000,
                entries: [
                    XTConnectivityRepairLedgerEntry(
                        schemaVersion: XTConnectivityRepairLedgerEntry.currentSchemaVersion,
                        entryID: "entry-1",
                        recordedAtMs: 1_741_300_026_000,
                        trigger: .backgroundKeepalive,
                        failureCode: "local_pairing_ready",
                        reasonFamily: "route_connectivity",
                        action: .waitForRouteReady,
                        owner: .xtRuntime,
                        result: .deferred,
                        verifyResult: "local_pairing_ready",
                        finalRoute: HubRemoteRoute.none.rawValue,
                        decisionReasonCode: "waiting_for_same_lan_or_formal_remote_route",
                        incidentReasonCode: "local_pairing_ready",
                        summaryLine: "waiting to return to LAN or add a formal remote route."
                    ),
                    XTConnectivityRepairLedgerEntry(
                        schemaVersion: XTConnectivityRepairLedgerEntry.currentSchemaVersion,
                        entryID: "entry-2",
                        recordedAtMs: 1_741_300_027_000,
                        trigger: .backgroundKeepalive,
                        failureCode: "grpc_unavailable",
                        reasonFamily: "route_connectivity",
                        action: .remoteReconnect,
                        owner: .xtRuntime,
                        result: .failed,
                        verifyResult: "retrying_remote_route",
                        finalRoute: HubRemoteRoute.none.rawValue,
                        decisionReasonCode: "retry_degraded_remote_route",
                        incidentReasonCode: "grpc_unavailable",
                        summaryLine: "remote route retry failed"
                    )
                ]
            ),
            status: "ok",
            reportPath: "/tmp/xt-ready.json"
        )

        let presentation = SupervisorXTReadyIncidentPresentationMapper.map(snapshot: snapshot)

        #expect(
            presentation.connectivityRepairLine?.text ==
                "连接修复：最近 2 次 · XT 自动修复 · 远端重连 · 失败 · 验证 retrying_remote_route · 路由 未建立"
        )
        #expect(presentation.connectivityRepairLine?.tone == .danger)
        #expect(
            presentation.connectivityRepairDetailLine?.text ==
                "连接修复轨迹：等待正式路由 待处理 -> 远端重连 失败"
        )
        #expect(presentation.connectivityRepairDetailLine?.isSelectable == true)
    }

    @Test
    func mapSurfacesSupervisorVoiceDiagnosis() {
        let headline = "Supervisor 语音自检显示：Hub 简报播报阶段未通过"
        let message = "最近一次 Supervisor 语音自检卡在Hub 简报播报阶段：简报播报后没有恢复监听。"
        let nextStep = "先在 XT Diagnostics 重跑 Supervisor 语音自检；如果仍卡在 Hub 简报播报阶段，再核对 brief projection、TTS 播报和播报后恢复监听的链路。"
        let snapshot = SupervisorManager.XTReadyIncidentExportSnapshot(
            autoExportEnabled: true,
            ledgerIncidentCount: 3,
            requiredIncidentEventCount: 3,
            missingIncidentCodes: [],
            memoryAssemblyReady: true,
            memoryAssemblyIssues: [],
            memoryAssemblyStatusLine: "ready",
            strictE2EReady: true,
            strictE2EIssues: [],
            supervisorVoiceDiagnosis: .init(
                status: XHubDoctorCheckStatus.fail.rawValue,
                headline: headline,
                message: message,
                detailLines: [
                    "voice_smoke_phase=brief_playback",
                    "voice_smoke_phase_status=failed",
                    "voice_smoke_failed_check=brief_resumed_listening"
                ],
                nextStep: nextStep,
                repairDestinationRef: UITroubleshootDestination.xtDiagnostics.rawValue,
                generatedAtMs: 1_741_300_123
            ),
            status: "ok",
            reportPath: "/tmp/xt-ready.json"
        )

        let presentation = SupervisorXTReadyIncidentPresentationMapper.map(snapshot: snapshot)
        let expectedActionURL = XTDeepLinkURLBuilder.settingsURL(
            sectionId: "diagnostics",
            title: headline,
            detail: "\(message)\n\(nextStep)"
        )?.absoluteString

        #expect(presentation.iconTone == .danger)
        #expect(presentation.statusLine.tone == .danger)
        #expect(presentation.supervisorVoiceLine?.text == "Supervisor 语音：失败 · Supervisor 语音自检显示：Hub 简报播报阶段未通过")
        #expect(presentation.supervisorVoiceLine?.tone == .danger)
        #expect(presentation.supervisorVoiceFreshnessLine?.text.contains("Supervisor 语音时效：最近一次语音自检已过期（") == true)
        #expect(presentation.supervisorVoiceFreshnessLine?.tone == .warning)
        #expect(
            presentation.supervisorVoiceDetailLine?.text ==
                "Supervisor 语音详情：最近一次 Supervisor 语音自检卡在Hub 简报播报阶段：简报播报后没有恢复监听。"
        )
        #expect(presentation.supervisorVoiceDetailLine?.isSelectable == true)
        #expect(
            presentation.supervisorVoiceNextLine?.text ==
                "Supervisor 语音下一步：先在 XT Diagnostics 重跑 Supervisor 语音自检；如果仍卡在 Hub 简报播报阶段，再核对 brief projection、TTS 播报和播报后恢复监听的链路。"
        )
        #expect(presentation.supervisorVoiceNextLine?.tone == .accent)
        #expect(presentation.supervisorVoiceActionLabel == "打开 XT Diagnostics")
        #expect(presentation.supervisorVoiceActionURL == expectedActionURL)
    }
}
