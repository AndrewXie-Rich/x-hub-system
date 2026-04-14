import Foundation
import Testing
@testable import XTerminal

struct XTModelInventoryTruthPresentationTests {

    @Test
    func localOnlyReadyStateExplainsOnlyLocalInteractiveModelsAreLoaded() {
        let presentation = XTModelInventoryTruthPresentation.build(
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(
                        id: "qwen3-14b-mlx",
                        backend: "mlx",
                        state: .loaded,
                        modelPath: "/models/qwen3"
                    ),
                    makeModel(
                        id: "bge-small",
                        backend: "transformers",
                        state: .loaded,
                        modelPath: "/models/bge",
                        taskKinds: ["embedding"]
                    )
                ],
                updatedAt: 42
            )
        )

        #expect(presentation.state == .localOnlyReady)
        #expect(presentation.summary.contains("正常的纯本地姿态"))
        #expect(presentation.detail.contains("不配置云 provider / API key"))
        #expect(presentation.localInteractiveLoadedCount == 1)
        #expect(presentation.supportLoadedCount == 1)
        #expect(presentation.tone == .neutral)
        #expect(presentation.requiresAttention == false)
        #expect(presentation.showsStatusCard == true)
    }

    @Test
    func noReadyProviderStateExplainsWhyInventoryCannotOfferLocalModels() {
        let presentation = XTModelInventoryTruthPresentation.build(
            snapshot: .empty(),
            doctorReport: makeDoctorReport(
                failureCode: "no_ready_provider",
                headline: "没有可用的就绪 provider",
                message: "Hub 能看到运行时进程，但当前没有 provider 可以处理本地任务。",
                nextStep: "检查 provider pack 和导入失败原因，然后重启或刷新运行时。",
                overallState: .blocked,
                checkStatus: .fail,
                severity: .critical,
                blocking: true,
                checkKind: "provider_readiness",
                stepKind: .repairRuntime,
                destinationRef: "hub://settings/diagnostics"
            ),
            runtimeMonitor: makeRuntimeMonitor(
                runtimeSummary: "还没有就绪 provider",
                queueSummary: "0 个执行中 · 0 个排队中",
                loadedSummary: "0 个已加载实例"
            )
        )

        #expect(presentation.state == .noReadyProvider)
        #expect(presentation.headline == "没有可用的就绪 provider")
        #expect(presentation.summary.contains("没有任何就绪的本地 provider"))
        #expect(presentation.detail.contains("检查 provider pack"))
        #expect(presentation.detail.contains("运行时：还没有就绪 provider"))
        #expect(presentation.tone == .critical)
    }

    @Test
    func runtimeHeartbeatStaleStateMarksSnapshotAsUntrusted() {
        let presentation = XTModelInventoryTruthPresentation.build(
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(
                        id: "gpt-oss-20b",
                        backend: "transformers",
                        state: .loaded,
                        modelPath: "/models/gpt-oss"
                    )
                ],
                updatedAt: 42
            ),
            doctorReport: makeDoctorReport(
                failureCode: "runtime_heartbeat_stale",
                headline: "运行时心跳已过期",
                message: "由于运行时心跳已过期或缺失，Hub 不能信任当前本地运行时快照。",
                nextStep: "去 Hub 设置里重启运行时组件，然后刷新诊断。",
                overallState: .blocked,
                checkStatus: .fail,
                severity: .critical,
                blocking: true,
                checkKind: "runtime_heartbeat",
                stepKind: .repairRuntime,
                destinationRef: "hub://settings/diagnostics"
            ),
            runtimeMonitor: makeRuntimeMonitor(
                runtimeSummary: "上一次心跳已失效",
                queueSummary: nil,
                loadedSummary: "1 个已加载实例"
            )
        )

        #expect(presentation.state == .runtimeHeartbeatStale)
        #expect(presentation.headline == "运行时心跳已过期")
        #expect(presentation.summary.contains("不应继续当成可信状态"))
        #expect(presentation.detail.contains("重启运行时组件"))
        #expect(presentation.tone == .critical)
    }

    @Test
    func providerPartialReadinessKeepsLoadedModelsVisibleButWarnsCoverageIsIncomplete() {
        let presentation = XTModelInventoryTruthPresentation.build(
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(
                        id: "qwen3-14b-mlx",
                        backend: "mlx",
                        state: .loaded,
                        modelPath: "/models/qwen3"
                    )
                ],
                updatedAt: 42
            ),
            doctorReport: makeDoctorReport(
                failureCode: "provider_partial_readiness",
                headline: "本地 provider 就绪情况不完整",
                message: "至少有一个 provider 已就绪，但 Hub 同时发现了不可用 provider，本地任务覆盖面可能受限。",
                nextStep: "如果你需要更完整的本地能力覆盖，请检查失败的 provider。",
                overallState: .degraded,
                checkStatus: .warn,
                severity: .warning,
                blocking: false,
                checkKind: "provider_readiness",
                stepKind: .inspectDiagnostics,
                destinationRef: "hub://settings/doctor",
                readyForFirstTask: true
            ),
            runtimeMonitor: makeRuntimeMonitor(
                runtimeSummary: "已就绪：transformers",
                queueSummary: "1 个执行中 · 2 个排队中",
                loadedSummary: "1 个已加载实例"
            )
        )

        #expect(presentation.state == .providerPartialReadiness)
        #expect(presentation.summary.contains("只有一部分已就绪"))
        #expect(presentation.detail.contains("已就绪：transformers"))
        #expect(presentation.detail.contains("检查失败的 provider"))
        #expect(presentation.tone == .caution)
    }

    @Test
    func snapshotMissingPointsToSupervisorControlCenterModelInventory() {
        let presentation = XTModelInventoryTruthPresentation.build(
            snapshot: .empty()
        )

        #expect(presentation.state == .snapshotMissing)
        #expect(presentation.detail.contains("Supervisor 控制中心 · AI 模型"))
        #expect(presentation.detail.contains("真实可执行列表"))
    }

    @Test
    func noInteractiveLoadedPointsToSupervisorControlCenterModelInventory() {
        let presentation = XTModelInventoryTruthPresentation.build(
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(
                        id: "bge-small",
                        backend: "transformers",
                        state: .loaded,
                        modelPath: "/models/bge",
                        taskKinds: ["embedding"]
                    )
                ],
                updatedAt: 42
            )
        )

        #expect(presentation.state == .noInteractiveLoaded)
        #expect(presentation.detail.contains("Supervisor 控制中心 · AI 模型"))
        #expect(presentation.detail.contains("真实可执行列表"))
    }

    @Test
    func runtimeCaptureWritesW9C2EvidenceWhenRequested() throws {
        guard let captureDir = ProcessInfo.processInfo.environment["XHUB_W9_C2_CAPTURE_DIR"], !captureDir.isEmpty else {
            return
        }

        let base = URL(fileURLWithPath: captureDir)
        let scenarios = capturedScenarios()
        let evidence = W9C2Evidence(
            schemaVersion: "w9_c2_xt_local_provider_truth_evidence.v1",
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            status: "delivered",
            claimScope: ["W9-C2"],
            claim: "XT model surfaces now explain local provider truth instead of collapsing to a generic empty-model message.",
            scenarios: scenarios,
            verificationResults: [
                VerificationResult(
                    name: "covered_required_states",
                    status: Set(scenarios.map(\.state)).isSuperset(of: [
                        XTModelInventoryTruthState.inventoryReady.rawValue,
                        XTModelInventoryTruthState.localOnlyReady.rawValue,
                        XTModelInventoryTruthState.runtimeHeartbeatStale.rawValue,
                        XTModelInventoryTruthState.noReadyProvider.rawValue,
                        XTModelInventoryTruthState.providerPartialReadiness.rawValue
                    ]) ? "pass" : "fail"
                ),
                VerificationResult(
                    name: "blocking_states_have_non_generic_copy",
                    status: scenarios
                        .filter { $0.state == XTModelInventoryTruthState.runtimeHeartbeatStale.rawValue || $0.state == XTModelInventoryTruthState.noReadyProvider.rawValue }
                        .allSatisfy { !$0.detail.contains("没有可用的模型") } ? "pass" : "fail"
                ),
                VerificationResult(
                    name: "degraded_state_keeps_runtime_summary",
                    status: scenarios.first(where: { $0.state == XTModelInventoryTruthState.providerPartialReadiness.rawValue })?.detail.contains("已就绪：transformers") == true ? "pass" : "fail"
                ),
                VerificationResult(
                    name: "ready_state_keeps_inventory_counts",
                    status: scenarios.first(where: { $0.state == XTModelInventoryTruthState.inventoryReady.rawValue })?.summary.contains("远端对话 1 个") == true ? "pass" : "fail"
                )
            ],
            sourceRefs: [
                "x-terminal/Sources/UI/XTModelInventoryTruthPresentation.swift:1",
                "x-terminal/Sources/UI/XTSettingsGuidancePresentation.swift:1",
                "x-terminal/Sources/UI/Components/HubModelRoutingPicker.swift:1",
                "x-terminal/Tests/XTModelInventoryTruthPresentationTests.swift:1",
                "build/reports/w9_c1_provider_truth_surface_evidence.v1.json",
                "build/reports/w9_c4_runtime_repair_entry_evidence.v1.json"
            ]
        )

        let fileName = "w9_c2_xt_local_provider_truth_evidence.v1.json"
        for destination in evidenceDestinations(captureBase: base, fileName: fileName) {
            try writeJSON(evidence, to: destination)
            #expect(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    private func capturedScenarios() -> [CapturedScenario] {
        [
            CapturedScenario(
                name: "inventory_ready_mixed",
                presentation: XTModelInventoryTruthPresentation.build(
                    snapshot: ModelStateSnapshot(
                        models: [
                            makeModel(id: "openai/gpt-5.4", backend: "openai", state: .loaded),
                            makeModel(
                                id: "qwen3-14b-mlx",
                                backend: "mlx",
                                state: .loaded,
                                modelPath: "/models/qwen3"
                            ),
                            makeModel(
                                id: "bge-small",
                                backend: "transformers",
                                state: .loaded,
                                modelPath: "/models/bge",
                                taskKinds: ["embedding"]
                            )
                        ],
                        updatedAt: 1
                    )
                )
            ),
            CapturedScenario(
                name: "local_only_ready",
                presentation: XTModelInventoryTruthPresentation.build(
                    snapshot: ModelStateSnapshot(
                        models: [
                            makeModel(
                                id: "qwen3-14b-mlx",
                                backend: "mlx",
                                state: .loaded,
                                modelPath: "/models/qwen3"
                            )
                        ],
                        updatedAt: 2
                    )
                )
            ),
            CapturedScenario(
                name: "runtime_heartbeat_stale",
                presentation: XTModelInventoryTruthPresentation.build(
                    snapshot: .empty(),
                    doctorReport: makeDoctorReport(
                        failureCode: "runtime_heartbeat_stale",
                        headline: "运行时心跳已过期",
                        message: "由于运行时心跳已过期或缺失，Hub 不能信任当前本地运行时快照。",
                        nextStep: "去 Hub 设置里重启运行时组件，然后刷新诊断。",
                        overallState: .blocked,
                        checkStatus: .fail,
                        severity: .critical,
                        blocking: true,
                        checkKind: "runtime_heartbeat",
                        stepKind: .repairRuntime,
                        destinationRef: "hub://settings/diagnostics"
                    ),
                    runtimeMonitor: makeRuntimeMonitor(
                        runtimeSummary: "上一次心跳已失效",
                        queueSummary: nil,
                        loadedSummary: "0 个已加载实例"
                    )
                )
            ),
            CapturedScenario(
                name: "no_ready_provider",
                presentation: XTModelInventoryTruthPresentation.build(
                    snapshot: .empty(),
                    doctorReport: makeDoctorReport(
                        failureCode: "no_ready_provider",
                        headline: "没有可用的就绪 provider",
                        message: "Hub 能看到运行时进程，但当前没有 provider 可以处理本地任务。",
                        nextStep: "检查 provider pack 和导入失败原因，然后重启或刷新运行时。",
                        overallState: .blocked,
                        checkStatus: .fail,
                        severity: .critical,
                        blocking: true,
                        checkKind: "provider_readiness",
                        stepKind: .repairRuntime,
                        destinationRef: "hub://settings/diagnostics"
                    ),
                    runtimeMonitor: makeRuntimeMonitor(
                        runtimeSummary: "还没有就绪 provider",
                        queueSummary: "0 个执行中 · 0 个排队中",
                        loadedSummary: "0 个已加载实例"
                    )
                )
            ),
            CapturedScenario(
                name: "provider_partial_readiness",
                presentation: XTModelInventoryTruthPresentation.build(
                    snapshot: ModelStateSnapshot(
                        models: [
                            makeModel(
                                id: "qwen3-14b-mlx",
                                backend: "mlx",
                                state: .loaded,
                                modelPath: "/models/qwen3"
                            )
                        ],
                        updatedAt: 3
                    ),
                    doctorReport: makeDoctorReport(
                        failureCode: "provider_partial_readiness",
                        headline: "本地 provider 就绪情况不完整",
                        message: "至少有一个 provider 已就绪，但 Hub 同时发现了不可用 provider，本地任务覆盖面可能受限。",
                        nextStep: "如果你需要更完整的本地能力覆盖，请检查失败的 provider。",
                        overallState: .degraded,
                        checkStatus: .warn,
                        severity: .warning,
                        blocking: false,
                        checkKind: "provider_readiness",
                        stepKind: .inspectDiagnostics,
                        destinationRef: "hub://settings/doctor",
                        readyForFirstTask: true
                    ),
                    runtimeMonitor: makeRuntimeMonitor(
                        runtimeSummary: "已就绪：transformers",
                        queueSummary: "1 个执行中 · 2 个排队中",
                        loadedSummary: "1 个已加载实例"
                    )
                )
            )
        ]
    }

    private func makeDoctorReport(
        failureCode: String,
        headline: String,
        message: String,
        nextStep: String,
        overallState: XHubDoctorOverallState,
        checkStatus: XHubDoctorCheckStatus,
        severity: XHubDoctorSeverity,
        blocking: Bool,
        checkKind: String,
        stepKind: XHubDoctorNextStepKind,
        destinationRef: String,
        readyForFirstTask: Bool = false
    ) -> XHubDoctorOutputReport {
        let check = XHubDoctorOutputCheckResult(
            checkID: failureCode,
            checkKind: checkKind,
            status: checkStatus,
            severity: severity,
            blocking: blocking,
            headline: headline,
            message: message,
            nextStep: nextStep,
            repairDestinationRef: destinationRef,
            detailLines: [],
            observedAtMs: 1
        )
        return XHubDoctorOutputReport(
            schemaVersion: XHubDoctorOutputReport.currentSchemaVersion,
            contractVersion: XHubDoctorOutputReport.currentContractVersion,
            reportID: "w9-c2-\(failureCode)",
            bundleKind: .providerRuntimeReadiness,
            producer: .xHub,
            surface: .hubUI,
            overallState: overallState,
            summary: XHubDoctorOutputSummary(
                headline: headline,
                passed: 0,
                failed: checkStatus == .fail ? 1 : 0,
                warned: checkStatus == .warn ? 1 : 0,
                skipped: 0
            ),
            readyForFirstTask: readyForFirstTask,
            checks: [check],
            nextSteps: [
                XHubDoctorOutputNextStep(
                    stepID: "\(failureCode)-step",
                    kind: stepKind,
                    label: "下一步",
                    owner: .user,
                    blocking: blocking,
                    destinationRef: destinationRef,
                    instruction: nextStep
                )
            ],
            routeSnapshot: nil,
            generatedAtMs: 1,
            reportPath: "/tmp/\(failureCode).json",
            sourceReportSchemaVersion: "xhub.local_runtime_status.v2",
            sourceReportPath: "/tmp/ai_runtime_status.json",
            currentFailureCode: failureCode,
            currentFailureIssue: checkKind,
            consumedContracts: ["xhub.doctor_output_contract.v1"]
        )
    }

    private func makeRuntimeMonitor(
        runtimeSummary: String,
        queueSummary: String?,
        loadedSummary: String?
    ) -> XHubLocalRuntimeMonitorSnapshotReport {
        XHubLocalRuntimeMonitorSnapshotReport(
            schemaVersion: "xhub_local_runtime_monitor_snapshot_export.v1",
            generatedAtMs: 1,
            statusSource: "/tmp/ai_runtime_status.json",
            runtimeAlive: true,
            monitorSummary: runtimeSummary,
            runtimeOperations: XHubLocalRuntimeMonitorOperationsReport(
                runtimeSummary: runtimeSummary,
                queueSummary: queueSummary ?? "0 个执行中 · 0 个排队中",
                loadedSummary: loadedSummary ?? "0 个已加载实例",
                currentTargets: [],
                loadedInstances: []
            )
        )
    }

    private func makeModel(
        id: String,
        backend: String,
        state: HubModelState,
        modelPath: String? = nil,
        taskKinds: [String]? = nil
    ) -> HubModel {
        HubModel(
            id: id,
            name: id,
            backend: backend,
            quant: "bf16",
            contextLength: 8_192,
            paramsB: 14,
            state: state,
            modelPath: modelPath,
            taskKinds: taskKinds
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

    private struct W9C2Evidence: Codable, Equatable {
        let schemaVersion: String
        let generatedAt: String
        let status: String
        let claimScope: [String]
        let claim: String
        let scenarios: [CapturedScenario]
        let verificationResults: [VerificationResult]
        let sourceRefs: [String]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case generatedAt = "generated_at"
            case status
            case claimScope = "claim_scope"
            case claim
            case scenarios
            case verificationResults = "verification_results"
            case sourceRefs = "source_refs"
        }
    }

    private struct CapturedScenario: Codable, Equatable {
        let name: String
        let state: String
        let headline: String
        let summary: String
        let detail: String
        let tone: String

        init(name: String, presentation: XTModelInventoryTruthPresentation) {
            self.name = name
            self.state = presentation.state.rawValue
            self.headline = presentation.headline
            self.summary = presentation.summary
            self.detail = presentation.detail
            switch presentation.tone {
            case .neutral:
                self.tone = "neutral"
            case .caution:
                self.tone = "caution"
            case .critical:
                self.tone = "critical"
            }
        }
    }

    private struct VerificationResult: Codable, Equatable {
        let name: String
        let status: String
    }
}
