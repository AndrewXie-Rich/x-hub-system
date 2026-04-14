import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class HubDiagnosticsBundleExporterTests: XCTestCase {
    func testHubRuntimeReadinessBundleNormalizesHubRuntimeStatus() {
        let report = XHubDoctorOutputReport.hubRuntimeReadinessBundle(
            status: sampleRuntimeStatus(),
            blockedCapabilities: [],
            outputPath: "/tmp/xhub_doctor_output_hub.json",
            surface: .hubUI,
            statusURL: sampleStatusURL()
        )

        XCTAssertEqual(report.schemaVersion, XHubDoctorOutputReport.currentSchemaVersion)
        XCTAssertEqual(report.contractVersion, XHubDoctorOutputReport.currentContractVersion)
        XCTAssertEqual(report.bundleKind, .providerRuntimeReadiness)
        XCTAssertEqual(report.producer, .xHub)
        XCTAssertEqual(report.surface, .hubUI)
        XCTAssertEqual(report.reportPath, "/tmp/xhub_doctor_output_hub.json")
        XCTAssertEqual(report.sourceReportSchemaVersion, "xhub.local_runtime_status.v2")
        XCTAssertEqual(report.sourceReportPath, "/Users/USER/RELFlowHub/ai_runtime_status.json")
        XCTAssertEqual(report.overallState, .degraded)
        XCTAssertEqual(report.summary.headline, "本地运行时已可用，但建议先检查诊断")
        XCTAssertTrue(report.readyForFirstTask)
        XCTAssertEqual(report.currentFailureCode, "provider_partial_readiness")
        XCTAssertEqual(report.currentFailureIssue, "provider_readiness")
        XCTAssertEqual(report.consumedContracts, [
            "xhub.doctor_output_contract.v1",
            "xhub.local_runtime_monitor.v1",
            "xhub.local_runtime_status.v2",
        ])
        XCTAssertEqual(report.checks.map(\.status), [.pass, .warn, .pass, .warn])
        XCTAssertEqual(report.nextSteps.map(\.kind), [.inspectDiagnostics, .startFirstTask])
        let monitorCheck = try! XCTUnwrap(report.checks.first { $0.checkKind == "runtime_monitor" })
        XCTAssertTrue(monitorCheck.detailLines.contains("monitor_recent_bench_result_count=1"))
        XCTAssertTrue(
            monitorCheck.detailLines.contains {
                $0.contains("provider=transformers")
                    && $0.contains("task_kind=vision_understand")
                    && $0.contains("execution_path=real_runtime")
            }
        )
    }

    func testHubRuntimeReadinessBundleTreatsLocalOnlyPostureAsHealthyWithoutCloudProvider() throws {
        let report = XHubDoctorOutputReport.hubRuntimeReadinessBundle(
            status: sampleLocalOnlyReadyStatus(),
            blockedCapabilities: [],
            outputPath: "/tmp/xhub_doctor_output_hub.json",
            surface: .hubUI,
            statusURL: sampleStatusURL()
        )

        XCTAssertEqual(report.overallState, .ready)
        XCTAssertTrue(report.readyForFirstTask)
        XCTAssertEqual(report.summary.headline, "本地运行时已准备好开始第一个任务")
        XCTAssertEqual(report.currentFailureCode, "")
        XCTAssertNil(report.currentFailureIssue)
        XCTAssertEqual(report.nextSteps.map(\.kind), [.startFirstTask])

        let providerCheck = try XCTUnwrap(report.checks.first { $0.checkKind == "provider_readiness" })
        XCTAssertEqual(providerCheck.status, .pass)
        XCTAssertEqual(providerCheck.headline, "本地 provider 就绪情况正常")
        XCTAssertTrue(providerCheck.message.contains("没有云 provider 或 API key"))
    }

    func testHubRuntimeReadinessBundleMarksMissingRuntimeAsBlocked() {
        let report = XHubDoctorOutputReport.hubRuntimeReadinessBundle(
            status: nil,
            blockedCapabilities: [],
            outputPath: "/tmp/xhub_doctor_output_hub.json",
            surface: .hubUI,
            statusURL: sampleStatusURL()
        )

        XCTAssertEqual(report.overallState, .blocked)
        XCTAssertFalse(report.readyForFirstTask)
        XCTAssertEqual(report.summary.headline, "运行时心跳已过期")
        XCTAssertEqual(report.currentFailureCode, "runtime_heartbeat_stale")
        XCTAssertEqual(report.currentFailureIssue, "runtime_heartbeat")
        XCTAssertEqual(report.checks.map(\.status), [.fail, .skip, .skip, .skip])
        XCTAssertEqual(report.nextSteps.count, 1)
        XCTAssertEqual(report.nextSteps.first?.kind, .repairRuntime)
        XCTAssertEqual(report.nextSteps.first?.destinationRef, "hub://settings/diagnostics")
    }

    func testHubRuntimeReadinessBundleSurfacesXHubLocalServiceFailureReason() throws {
        let report = XHubDoctorOutputReport.hubRuntimeReadinessBundle(
            status: sampleXHubLocalServiceStatus(
                reasonCode: "xhub_local_service_unreachable",
                processState: "launch_failed",
                startAttemptCount: 2,
                lastStartError: "health_timeout:http://127.0.0.1:50171"
            ),
            blockedCapabilities: [],
            outputPath: "/tmp/xhub_doctor_output_hub.json",
            surface: .hubUI,
            statusURL: sampleStatusURL()
        )

        XCTAssertEqual(report.overallState, .blocked)
        XCTAssertFalse(report.readyForFirstTask)
        XCTAssertEqual(report.summary.headline, "Hub 管理的本地服务不可达")
        XCTAssertEqual(report.currentFailureCode, "xhub_local_service_unreachable")

        let providerCheck = try XCTUnwrap(report.checks.first { $0.checkKind == "provider_readiness" })
        XCTAssertEqual(providerCheck.status, .fail)
        XCTAssertEqual(providerCheck.headline, "Hub 管理的本地服务不可达")
        XCTAssertTrue(providerCheck.message.contains("无法访问"))
        XCTAssertTrue(providerCheck.message.contains("Hub 已尝试托管启动"))
        XCTAssertTrue(providerCheck.detailLines.contains("managed_service_provider_count=1"))
        XCTAssertTrue(
            providerCheck.detailLines.contains {
                $0.contains("provider=transformers")
                    && $0.contains("service_state=unreachable")
                    && $0.contains("endpoint=http://127.0.0.1:50171")
                    && $0.contains("process_state=launch_failed")
                    && $0.contains("start_attempt_count=2")
            }
        )

        let repairStep = try XCTUnwrap(report.nextSteps.first { $0.kind == .repairRuntime })
        XCTAssertEqual(repairStep.label, "修复本地服务")
        XCTAssertEqual(repairStep.destinationRef, "hub://settings/diagnostics")
        XCTAssertTrue(repairStep.instruction.contains("检查托管服务快照"))
    }

    func testHubDoctorOutputStoreWritesMachineReadableReport() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("hub-doctor-output-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let reportURL = tempRoot.appendingPathComponent("xhub_doctor_output_hub.json")
        let report = XHubDoctorOutputReport.hubRuntimeReadinessBundle(
            status: sampleRuntimeStatus(),
            blockedCapabilities: ["ai.audio.local"],
            outputPath: reportURL.path,
            surface: .hubUI,
            statusURL: sampleStatusURL()
        )

        XHubDoctorOutputStore.writeReport(report, to: reportURL)

        let data = try Data(contentsOf: reportURL)
        let decoded = try JSONDecoder().decode(XHubDoctorOutputReport.self, from: data)

        XCTAssertEqual(decoded.reportPath, reportURL.path)
        XCTAssertEqual(decoded.checks.map(\.status), [.pass, .warn, .warn, .warn])
        XCTAssertEqual(decoded.nextSteps.map(\.kind), [.inspectDiagnostics, .startFirstTask])
    }

    func testWriteCurrentHubRuntimeReadinessReportPersistsRequestedSurface() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("hub-doctor-output-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let reportURL = tempRoot.appendingPathComponent("xhub_doctor_output_hub.json")
        let report = XHubDoctorOutputStore.writeCurrentHubRuntimeReadinessReport(
            status: sampleRuntimeStatus(),
            blockedCapabilities: [],
            outputURL: reportURL,
            surface: .hubUI,
            statusURL: sampleStatusURL()
        )

        let decoded = try JSONDecoder().decode(
            XHubDoctorOutputReport.self,
            from: Data(contentsOf: reportURL)
        )
        let monitorSnapshotURL = tempRoot.appendingPathComponent("local_runtime_monitor_snapshot.redacted.json")

        XCTAssertEqual(report.reportPath, reportURL.path)
        XCTAssertEqual(decoded.reportPath, reportURL.path)
        XCTAssertEqual(decoded.surface, .hubUI)
        XCTAssertEqual(decoded.bundleKind, .providerRuntimeReadiness)
        XCTAssertEqual(decoded.sourceReportPath, "/Users/USER/RELFlowHub/ai_runtime_status.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: monitorSnapshotURL.path))
    }

    func testExportUnifiedDoctorReportsWritesRuntimeAndChannelDoctorOutputs() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("hub-unified-doctor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let runtimeURL = tempRoot.appendingPathComponent("xhub_doctor_output_hub.json")
        let channelURL = tempRoot.appendingPathComponent("xhub_doctor_output_channel_onboarding.redacted.json")
        let result = await HubDiagnosticsBundleExporter.exportUnifiedDoctorReports(
            status: sampleRuntimeStatus(),
            blockedCapabilities: ["ai.audio.local"],
            statusURL: sampleStatusURL(),
            operatorChannelAdminToken: "",
            operatorChannelGRPCPort: 0,
            runtimeOutputURL: runtimeURL,
            channelOutputURL: channelURL,
            surface: .hubUI
        )

        XCTAssertEqual(result.runtimeReportPath, runtimeURL.path)
        XCTAssertEqual(result.channelOnboardingReportPath, channelURL.path)
        XCTAssertEqual(
            result.localServiceSnapshotPath,
            tempRoot.appendingPathComponent("xhub_local_service_snapshot.redacted.json").path
        )
        XCTAssertEqual(
            result.localServiceRecoveryGuidancePath,
            tempRoot.appendingPathComponent("xhub_local_service_recovery_guidance.redacted.json").path
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.runtimeReportPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.channelOnboardingReportPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.localServiceSnapshotPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.localServiceRecoveryGuidancePath))

        let channelRaw = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: channelURL)) as? [String: Any]
        )
        XCTAssertEqual(channelRaw["bundle_kind"] as? String, "channel_onboarding_readiness")
        XCTAssertEqual(channelRaw["source_report_path"] as? String, "hub://admin/operator-channels")
        XCTAssertEqual(channelRaw["overall_state"] as? String, "degraded")
        let checks = try XCTUnwrap(channelRaw["checks"] as? [[String: Any]])
        XCTAssertEqual(checks.map { $0["status"] as? String }, ["warn", "warn", "warn"])
    }

    func testWriteCurrentHubRuntimeReadinessReportPersistsLocalServiceSnapshotSidecar() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("hub-doctor-output-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let reportURL = tempRoot.appendingPathComponent("xhub_doctor_output_hub.json")
        _ = XHubDoctorOutputStore.writeCurrentHubRuntimeReadinessReport(
            status: sampleXHubLocalServiceStatus(reasonCode: "xhub_local_service_unreachable"),
            blockedCapabilities: [],
            outputURL: reportURL,
            surface: .hubUI,
            statusURL: sampleStatusURL()
        )

        let snapshotURL = tempRoot.appendingPathComponent("xhub_local_service_snapshot.redacted.json")
        let raw = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: snapshotURL)) as? [String: Any]
        )

        XCTAssertEqual(raw["schema_version"] as? String, "xhub_local_service_snapshot_export.v1")
        let doctorProjection = try XCTUnwrap(raw["doctor_projection"] as? [String: Any])
        XCTAssertEqual(doctorProjection["current_failure_code"] as? String, "xhub_local_service_unreachable")
        XCTAssertEqual(doctorProjection["provider_check_status"] as? String, "fail")
    }

    func testWriteCurrentHubRuntimeReadinessReportPersistsLocalServiceRecoveryGuidanceSidecar() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("hub-doctor-output-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let reportURL = tempRoot.appendingPathComponent("xhub_doctor_output_hub.json")
        _ = XHubDoctorOutputStore.writeCurrentHubRuntimeReadinessReport(
            status: sampleXHubLocalServiceStatus(
                reasonCode: "xhub_local_service_unreachable",
                processState: "launch_failed",
                startAttemptCount: 2,
                lastStartError: "spawn_exit_1"
            ),
            blockedCapabilities: ["ai.embed.local"],
            outputURL: reportURL,
            surface: .hubUI,
            statusURL: sampleStatusURL()
        )

        let guidanceURL = tempRoot.appendingPathComponent("xhub_local_service_recovery_guidance.redacted.json")
        let raw = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: guidanceURL)) as? [String: Any]
        )

        XCTAssertEqual(raw["schema_version"] as? String, "xhub_local_service_recovery_guidance_export.v1")
        XCTAssertEqual(raw["guidance_present"] as? Bool, true)
        XCTAssertEqual(raw["action_category"] as? String, "repair_managed_launch_failure")
        XCTAssertEqual(raw["current_failure_code"] as? String, "xhub_local_service_unreachable")
        XCTAssertEqual(raw["managed_process_state"] as? String, "launch_failed")
        XCTAssertEqual(raw["managed_last_start_error"] as? String, "spawn_exit_1")
        let blockedCapabilities = try XCTUnwrap(raw["blocked_capabilities"] as? [String])
        XCTAssertEqual(blockedCapabilities, ["ai.embed.local"])
        let actions = try XCTUnwrap(raw["recommended_actions"] as? [[String: Any]])
        XCTAssertEqual(actions.first?["action_id"] as? String, "inspect_managed_launch_error")
        let faq = try XCTUnwrap(raw["support_faq"] as? [[String: Any]])
        XCTAssertEqual(faq.count, 3)
    }

    func testProviderSummaryReportIncludesRuntimeMonitorSection() {
        let report = HubDiagnosticsBundleExporter.localRuntimeProviderSummaryReport(
            status: sampleRuntimeStatus(),
            blockedCapabilities: ["ai.audio.local"],
            statusURL: sampleStatusURL()
        )

        XCTAssertTrue(report.contains("schema_version: xhub_local_runtime_provider_summary.v2"))
        XCTAssertTrue(report.contains("blocked_capabilities:\nai.audio.local"))
        XCTAssertTrue(report.contains("operator_summary:"))
        XCTAssertTrue(report.contains("runtime_monitor:"))
        XCTAssertTrue(report.contains("monitor_provider_count=1"))
        XCTAssertTrue(report.contains("recent_bench_result_count=1"))
        XCTAssertTrue(report.contains("provider_pack_count=2"))
        XCTAssertTrue(report.contains("runtime_source=user_python_venv"))
        XCTAssertTrue(report.contains("最近一次快速评审路由显示，transformers 执行了 vision_understand，模型为 glm4v-local，执行路径为 real_runtime，并携带了 1 张图片。"))
        XCTAssertTrue(report.contains("task_kind=vision_understand model_id=glm4v-local execution_path=real_runtime"))
        XCTAssertTrue(report.contains("provider=transformers installed=1 enabled=1 state=installed engine=hf-transformers version=builtin-2026-03-16"))
    }

    func testLocalRuntimeMonitorSummaryReportIncludesKeyTelemetry() {
        let report = HubDiagnosticsBundleExporter.localRuntimeMonitorSummaryReport(
            status: sampleRuntimeStatus(),
            models: sampleBenchModels(),
            pairedProfilesSnapshot: samplePairedProfilesSnapshot(),
            targetPreferencesSnapshot: LocalModelRuntimeTargetPreferencesSnapshot.empty(),
            statusURL: sampleStatusURL()
        )

        XCTAssertTrue(report.contains("schema_version: xhub_local_runtime_monitor_summary.v1"))
        XCTAssertTrue(report.contains("status_source: /Users/USER/RELFlowHub/ai_runtime_status.json"))
        XCTAssertTrue(report.contains("monitor_schema_version=xhub.local_runtime_monitor.v1"))
        XCTAssertTrue(report.contains("monitor_active_task_count=1"))
        XCTAssertTrue(report.contains("monitor_recent_bench_result_count=1"))
        XCTAssertTrue(report.contains("provider=transformers ok=1 reason=fallback_ready runtime_source=user_python_venv runtime_state=user_runtime_fallback"))
        XCTAssertTrue(report.contains("provider=transformers task_kind=vision_understand model_id=glm4v-local execution_path=real_runtime"))
        XCTAssertTrue(report.contains("provider=mlx severity=error code=import_error message=missing mlx"))
        XCTAssertTrue(report.contains("runtime_ops_summary:"))
        XCTAssertTrue(report.contains("loaded_summary=1 个已加载实例"))
        XCTAssertTrue(report.contains("provider=transformers state=fallback queue=1 个执行中 · 2 个排队中 detail=已加载 1 个 · 回退 转写"))
        XCTAssertTrue(report.contains("loaded_instances:"))
        XCTAssertTrue(report.contains("model_id=bge-small model_name=BGE Small provider=transformers"))
        XCTAssertTrue(report.contains("load=ctx 8192 · ttl 600s · par 2 · 加载配置 \(sampleBenchLoadProfileHash().prefix(8))"))
        XCTAssertTrue(report.contains("detail=transformers · resident · mps · 配置 diag-a"))
        XCTAssertTrue(report.contains("current_target=配对目标"))
    }

    func testLocalRuntimeConsoleClipboardReportIncludesTargetsAndTaskHints() {
        let report = HubDiagnosticsBundleExporter.localRuntimeConsoleClipboardReport(
            status: sampleRuntimeStatus(),
            models: sampleBenchModels(),
            pairedProfilesSnapshot: samplePairedProfilesSnapshot()
        )

        XCTAssertTrue(report.contains("schema_version: xhub_local_runtime_console_clipboard.v1"))
        XCTAssertTrue(report.contains("monitor_recent_bench_results:"))
        XCTAssertTrue(report.contains("provider=transformers task_kind=vision_understand model_id=glm4v-local execution_path=real_runtime"))
        XCTAssertTrue(report.contains("current_targets:"))
        XCTAssertTrue(report.contains("model_id=bge-small model_name=BGE Small provider=transformers route=pinned"))
        XCTAssertTrue(report.contains("target=Target: terminal-a · ctx 8192 · ttl 600s · par 2 · resident"))
        XCTAssertTrue(report.contains("hint=在首选运行时路径恢复前，请求可能会先落到回退链路。"))
        XCTAssertTrue(report.contains("active_tasks:"))
        XCTAssertTrue(report.contains("request_id=req-a"))
        XCTAssertTrue(report.contains("instance_ref=\(sampleBenchLoadProfileHash().prefix(8))"))
        XCTAssertTrue(report.contains("summary=正在通过 TRANSFORMERS 运行 · 目标设备在线 · 正在使用常驻实例 · 后面还有 2 个排队任务 · 当前走回退链路"))
        XCTAssertTrue(report.contains("hint=这个运行包后面还有排队任务，所以完成时间可能会被拉长。"))
    }

    func testLocalRuntimeMonitorSnapshotExportDataBuildsStructuredEnvelope() throws {
        let data = try XCTUnwrap(
            HubDiagnosticsBundleExporter.localRuntimeMonitorSnapshotExportData(
                status: sampleRuntimeStatus(),
                models: sampleBenchModels(),
                pairedProfilesSnapshot: samplePairedProfilesSnapshot(),
                targetPreferencesSnapshot: LocalModelRuntimeTargetPreferencesSnapshot.empty(),
                statusURL: sampleStatusURL(),
                hostMetrics: sampleHostMetrics()
            )
        )
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(raw["schema_version"] as? String, "xhub_local_runtime_monitor_export.v1")
        XCTAssertEqual(raw["runtime_alive"] as? Bool, true)
        XCTAssertEqual(raw["status_source"] as? String, "/Users/USER/RELFlowHub/ai_runtime_status.json")

        let summary = raw["monitor_summary"] as? String ?? ""
        XCTAssertTrue(summary.contains("monitor_provider_count=1"))
        XCTAssertTrue(summary.contains("monitor_recent_bench_result_count=1"))
        XCTAssertTrue(summary.contains("host_load_severity=high"))
        XCTAssertTrue(summary.contains("cpu_percent=91.5"))

        let snapshot = try XCTUnwrap(raw["monitor_snapshot"] as? [String: Any])
        XCTAssertEqual(snapshot["schemaVersion"] as? String, "xhub.local_runtime_monitor.v1")
        let recentBenchResults = try XCTUnwrap(snapshot["recentBenchResults"] as? [[String: Any]])
        XCTAssertEqual(recentBenchResults.count, 1)
        let routeTraceSummary = try XCTUnwrap(recentBenchResults.first?["routeTraceSummary"] as? [String: Any])
        XCTAssertEqual(routeTraceSummary["selectedTaskKind"] as? String, "vision_understand")
        XCTAssertEqual(routeTraceSummary["executionPath"] as? String, "real_runtime")
        XCTAssertEqual(recentBenchResults.first?["loadConfigHash"] as? String, "vision8192")
        XCTAssertEqual(recentBenchResults.first?["currentContextLength"] as? Int, 8192)
        let recentBenchLoadConfig = try XCTUnwrap(recentBenchResults.first?["loadConfig"] as? [String: Any])
        XCTAssertEqual(recentBenchLoadConfig["parallel"] as? Int, 2)

        let providers = try XCTUnwrap(snapshot["providers"] as? [[String: Any]])
        XCTAssertEqual(providers.count, 1)
        XCTAssertEqual(providers.first?["provider"] as? String, "transformers")
        let activeTasks = try XCTUnwrap(snapshot["activeTasks"] as? [[String: Any]])
        XCTAssertEqual(activeTasks.count, 1)
        XCTAssertEqual(activeTasks.first?["loadConfigHash"] as? String, sampleBenchLoadProfileHash())
        XCTAssertEqual(activeTasks.first?["currentContextLength"] as? Int, 8192)
        XCTAssertEqual(activeTasks.first?["maxContextLength"] as? Int, 16384)
        XCTAssertEqual(activeTasks.first?["leaseTtlSec"] as? Int, 120)
        XCTAssertEqual(activeTasks.first?["leaseRemainingTtlSec"] as? Int, 118)
        XCTAssertNotNil(activeTasks.first?["expiresAt"] as? Double)

        let runtimeOperations = try XCTUnwrap(raw["runtime_operations"] as? [String: Any])
        XCTAssertEqual(runtimeOperations["loaded_summary"] as? String, "1 个已加载实例")

        let hostMetrics = try XCTUnwrap(raw["host_metrics"] as? [String: Any])
        XCTAssertEqual(hostMetrics["severity"] as? String, "high")
        XCTAssertEqual(hostMetrics["thermal_state"] as? String, "serious")
        XCTAssertEqual(hostMetrics["cpu_usage_percent"] as? Double, 91.5)
        XCTAssertEqual(hostMetrics["memory_pressure"] as? String, "high")
        let detailLines = try XCTUnwrap(hostMetrics["detail_lines"] as? [String])
        XCTAssertTrue(detailLines.contains(where: { $0.contains("host_memory_bytes") }))

        let currentTargets = try XCTUnwrap(runtimeOperations["current_targets"] as? [[String: Any]])
        XCTAssertEqual(currentTargets.count, 1)
        XCTAssertEqual(currentTargets.first?["model_id"] as? String, "bge-small")
        XCTAssertEqual(currentTargets.first?["load_summary"] as? String, "ctx=8192 · ttl=600s · par=2 · id=diag-a")
        let currentTargetPayload = try XCTUnwrap(currentTargets.first?["target"] as? [String: Any])
        XCTAssertEqual(currentTargetPayload["effectiveContextLength"] as? Int, 8192)
        XCTAssertEqual(currentTargetPayload["source"] as? String, "loaded_instance_preferred_profile")

        let loadedInstances = try XCTUnwrap(runtimeOperations["loaded_instances"] as? [[String: Any]])
        XCTAssertEqual(loadedInstances.count, 1)
        XCTAssertEqual(loadedInstances.first?["model_id"] as? String, "bge-small")
        XCTAssertEqual(loadedInstances.first?["is_current_target"] as? Bool, true)
        XCTAssertEqual(loadedInstances.first?["current_target_summary"] as? String, "配对目标")
        let loadedInstancePayload = try XCTUnwrap(loadedInstances.first?["loaded_instance"] as? [String: Any])
        XCTAssertEqual(loadedInstancePayload["loadConfigHash"] as? String, sampleBenchLoadProfileHash())
        XCTAssertEqual(loadedInstancePayload["currentContextLength"] as? Int, 8192)
        XCTAssertEqual(loadedInstancePayload["effectiveContextLength"] as? Int, 8192)
        XCTAssertEqual(loadedInstancePayload["ttl"] as? Int, 600)
        let loadConfig = try XCTUnwrap(loadedInstancePayload["loadConfig"] as? [String: Any])
        XCTAssertEqual(loadConfig["ttl"] as? Int, 600)
        let effectiveLoadProfile = try XCTUnwrap(loadedInstancePayload["effectiveLoadProfile"] as? [String: Any])
        XCTAssertEqual(effectiveLoadProfile["parallel"] as? Int, 2)
    }

    func testRuntimeCaptureWritesW9C1ProviderTruthEvidenceWhenRequested() throws {
        guard let captureDir = ProcessInfo.processInfo.environment["XHUB_W9_C1_CAPTURE_DIR"], !captureDir.isEmpty else {
            return
        }

        let status = sampleRuntimeStatus()
        let models = sampleBenchModels()
        let pairedProfiles = samplePairedProfilesSnapshot()
        let currentTargetsByModelID = Dictionary(
            uniqueKeysWithValues: models.map { model in
                (
                    model.id,
                    LocalModelRuntimeRequestContextResolver.resolve(
                        model: model,
                        runtimeStatus: status,
                        pairedProfilesSnapshot: pairedProfiles,
                        targetPreference: nil
                    )
                )
            }
        )
        let runtimeOps = LocalRuntimeOperationsSummaryBuilder.build(
            status: status,
            models: models,
            currentTargetsByModelID: currentTargetsByModelID
        )
        let doctorReport = XHubDoctorOutputReport.hubRuntimeReadinessBundle(
            status: status,
            blockedCapabilities: ["ai.audio.local"],
            outputPath: "/tmp/xhub_doctor_output_hub.json",
            surface: .hubUI,
            statusURL: sampleStatusURL()
        )
        let monitorReport = HubDiagnosticsBundleExporter.localRuntimeMonitorSummaryReport(
            status: status,
            models: models,
            pairedProfilesSnapshot: pairedProfiles,
            targetPreferencesSnapshot: LocalModelRuntimeTargetPreferencesSnapshot.empty(),
            statusURL: sampleStatusURL()
        )
        let repairSummary = try XCTUnwrap(
            LocalRuntimeRepairSurfaceSummaryBuilder.build(status: status)
        )
        let diagnoses = status.providerDiagnoses(ttl: AIRuntimeStatus.recommendedHeartbeatTTL)
        let readyProviders = diagnoses.filter { $0.state == .ready }.map(\.provider).sorted()
        let downProviders = diagnoses.filter { $0.state == .down }.map(\.provider).sorted()
        let monitor = try XCTUnwrap(status.monitorSnapshot)
        let evidence = W9C1ProviderTruthSurfaceEvidence(
            schemaVersion: "w9_c1_provider_truth_surface_evidence.v1",
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            status: "delivered",
            claimScope: ["W9-C1"],
            claim: "Hub now exposes provider truth consistently across Runtime Monitor, Models -> Runtime, and doctor/export instead of hiding local runtime state behind raw telemetry.",
            settingsRuntimeMonitor: SettingsRuntimeMonitorSurface(
                runtimeAlive: status.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL),
                readyProviders: readyProviders,
                downProviders: downProviders,
                queueActive: monitor.queue.activeTaskCount,
                queueQueued: monitor.queue.queuedTaskCount,
                recentBenchResultCount: monitor.recentBenchResults.count,
                lastErrorCodes: monitor.lastErrors.map(\.code),
                fallbackReadyProviderCount: monitor.fallbackCounters.fallbackReadyProviderCount,
                repairReasonCode: repairSummary.reasonCode,
                repairDestinationRef: repairSummary.repairDestinationRef,
                monitorSummaryReport: monitorReport
            ),
            modelsRuntime: ModelsRuntimeSurface(
                runtimeSummary: runtimeOps.runtimeSummary,
                queueSummary: runtimeOps.queueSummary,
                loadedSummary: runtimeOps.loadedSummary,
                providerRows: runtimeOps.providerRows.map {
                    ModelsRuntimeProviderRow(
                        providerID: $0.providerID,
                        stateLabel: $0.stateLabel,
                        queueSummary: $0.queueSummary,
                        detailSummary: $0.detailSummary
                    )
                },
                instanceRows: runtimeOps.instanceRows.map {
                    ModelsRuntimeInstanceRow(
                        providerID: $0.providerID,
                        modelID: $0.modelID,
                        isCurrentTarget: $0.isCurrentTarget,
                        currentTargetSummary: $0.currentTargetSummary,
                        loadSummary: $0.loadSummary
                    )
                }
            ),
            doctorExport: DoctorExportSurface(
                overallState: doctorReport.overallState.rawValue,
                readyForFirstTask: doctorReport.readyForFirstTask,
                currentFailureCode: doctorReport.currentFailureCode,
                currentFailureIssue: doctorReport.currentFailureIssue ?? "",
                summaryHeadline: doctorReport.summary.headline,
                nextStepDestinations: doctorReport.nextSteps.compactMap(\.destinationRef),
                checkStatuses: doctorReport.checks.map {
                    DoctorCheckStatus(
                        checkID: $0.checkID,
                        checkKind: $0.checkKind,
                        status: $0.status.rawValue,
                        repairDestinationRef: $0.repairDestinationRef ?? ""
                    )
                }
            ),
            verificationResults: makeW9C1VerificationResults(
                readyProviders: readyProviders,
                downProviders: downProviders,
                runtimeOps: runtimeOps,
                repairSummary: repairSummary,
                doctorReport: doctorReport,
                monitorReport: monitorReport,
                monitor: monitor
            ),
            sourceRefs: [
                "x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift:1391",
                "x-hub/macos/RELFlowHub/Sources/RELFlowHub/MainPanelView.swift:1294",
                "x-hub/macos/RELFlowHub/Sources/RELFlowHub/LocalRuntimeOperationsSummary.swift:39",
                "x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubDiagnosticsBundleExporter.swift:792",
                "x-hub/macos/RELFlowHub/Sources/RELFlowHub/XHubDoctorOutputHub.swift:474",
                "x-hub/macos/RELFlowHub/Tests/RELFlowHubAppTests/HubDiagnosticsBundleExporterTests.swift:5"
            ]
        )

        let fileName = "w9_c1_provider_truth_surface_evidence.v1.json"
        for destination in evidenceDestinations(captureBase: URL(fileURLWithPath: captureDir), fileName: fileName) {
            try writeJSON(evidence, to: destination)
            XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testXHubLocalServiceSnapshotExportDataCapturesEndpointAndReason() throws {
        let data = try XCTUnwrap(
            HubDiagnosticsBundleExporter.xhubLocalServiceSnapshotExportData(
                status: sampleXHubLocalServiceStatus(reasonCode: "xhub_local_service_starting"),
                statusURL: sampleStatusURL()
            )
        )
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(raw["schema_version"] as? String, "xhub_local_service_snapshot_export.v1")
        XCTAssertEqual(raw["runtime_alive"] as? Bool, true)
        XCTAssertEqual(raw["provider_count"] as? Int, 1)
        XCTAssertEqual(raw["ready_provider_count"] as? Int, 0)
        XCTAssertEqual(raw["status_source"] as? String, "/Users/USER/RELFlowHub/ai_runtime_status.json")

        let primaryIssue = try XCTUnwrap(raw["primary_issue"] as? [String: Any])
        XCTAssertEqual(primaryIssue["reason_code"] as? String, "xhub_local_service_starting")
        XCTAssertEqual(primaryIssue["headline"] as? String, "Hub 管理的本地服务仍在启动")
        XCTAssertEqual(primaryIssue["next_step"] as? String, "等待 /health 变成 ready，或先检查预热进度，再路由真实流量。")

        let doctorProjection = try XCTUnwrap(raw["doctor_projection"] as? [String: Any])
        XCTAssertEqual(doctorProjection["overall_state"] as? String, "blocked")
        XCTAssertEqual(doctorProjection["ready_for_first_task"] as? Bool, false)
        XCTAssertEqual(doctorProjection["current_failure_code"] as? String, "xhub_local_service_starting")
        XCTAssertEqual(doctorProjection["current_failure_issue"] as? String, "provider_readiness")
        XCTAssertEqual(doctorProjection["provider_check_status"] as? String, "fail")
        XCTAssertEqual(doctorProjection["provider_check_blocking"] as? Bool, true)
        XCTAssertEqual(doctorProjection["repair_destination_ref"] as? String, "hub://settings/diagnostics")
        XCTAssertEqual(doctorProjection["headline"] as? String, "Hub 管理的本地服务仍在启动")

        let providers = try XCTUnwrap(raw["providers"] as? [[String: Any]])
        XCTAssertEqual(providers.count, 1)
        XCTAssertEqual(providers.first?["provider_id"] as? String, "transformers")
        XCTAssertEqual(providers.first?["runtime_source"] as? String, "xhub_local_service")
        XCTAssertEqual(providers.first?["runtime_reason_code"] as? String, "xhub_local_service_starting")
        XCTAssertEqual(providers.first?["service_state"] as? String, "starting")
        XCTAssertEqual(providers.first?["service_base_url"] as? String, "http://127.0.0.1:50171")
        XCTAssertEqual(providers.first?["execution_mode"] as? String, "xhub_local_service")
        XCTAssertEqual(providers.first?["queued_task_count"] as? Int, 2)
        XCTAssertEqual(providers.first?["loaded_instance_count"] as? Int, 1)
        let managed = try XCTUnwrap(providers.first?["managed_service_state"] as? [String: Any])
        XCTAssertEqual(managed["processState"] as? String, "starting")
        XCTAssertEqual(managed["pid"] as? Int, 43001)
        XCTAssertEqual(managed["startAttemptCount"] as? Int, 1)
    }

    func testXHubLocalServiceRecoveryGuidanceExportDataCapturesActionCategoryAndFAQ() throws {
        let data = try XCTUnwrap(
            HubDiagnosticsBundleExporter.xhubLocalServiceRecoveryGuidanceExportData(
                status: sampleXHubLocalServiceStatus(
                    reasonCode: "xhub_local_service_unreachable",
                    processState: "launch_failed",
                    startAttemptCount: 2,
                    lastStartError: "spawn_exit_1"
                ),
                blockedCapabilities: ["ai.embed.local"],
                statusURL: sampleStatusURL()
            )
        )
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(raw["schema_version"] as? String, "xhub_local_service_recovery_guidance_export.v1")
        XCTAssertEqual(raw["runtime_alive"] as? Bool, true)
        XCTAssertEqual(raw["guidance_present"] as? Bool, true)
        XCTAssertEqual(raw["provider_count"] as? Int, 1)
        XCTAssertEqual(raw["ready_provider_count"] as? Int, 0)
        XCTAssertEqual(raw["action_category"] as? String, "repair_managed_launch_failure")
        XCTAssertEqual(raw["severity"] as? String, "high")
        XCTAssertEqual(raw["repair_destination_ref"] as? String, "hub://settings/diagnostics")
        XCTAssertEqual(raw["managed_process_state"] as? String, "launch_failed")
        XCTAssertEqual(raw["managed_start_attempt_count"] as? Int, 2)
        XCTAssertEqual(raw["managed_last_start_error"] as? String, "spawn_exit_1")
        let primaryIssue = try XCTUnwrap(raw["primary_issue"] as? [String: Any])
        XCTAssertEqual(primaryIssue["reason_code"] as? String, "xhub_local_service_unreachable")
        let actions = try XCTUnwrap(raw["recommended_actions"] as? [[String: Any]])
        XCTAssertEqual(actions.first?["rank"] as? Int, 1)
        XCTAssertEqual(actions.first?["action_id"] as? String, "inspect_managed_launch_error")
        let faq = try XCTUnwrap(raw["support_faq"] as? [[String: Any]])
        XCTAssertEqual(faq.count, 3)
        XCTAssertEqual((raw["blocked_capabilities"] as? [String]) ?? [], ["ai.embed.local"])
    }

    func testLocalRuntimeBenchSummaryReportIncludesBenchExplanation() {
        let report = HubDiagnosticsBundleExporter.localRuntimeBenchSummaryReport(
            models: sampleBenchModels(),
            benchSnapshot: sampleBenchSnapshot(),
            status: sampleRuntimeStatus(),
            pairedProfilesSnapshot: samplePairedProfilesSnapshot(),
            targetPreferencesSnapshot: LocalModelRuntimeTargetPreferencesSnapshot.empty(),
            statusURL: sampleStatusURL(),
            benchURL: ModelBenchStorage.url()
        )

        XCTAssertTrue(report.contains("schema_version: xhub_local_runtime_bench_summary.v1"))
        XCTAssertTrue(report.contains("model_id=bge-small"))
        XCTAssertTrue(report.contains("target=Target: terminal-a"))
        XCTAssertTrue(report.contains("target_load=ctx=8192 · ttl=600s · par=2 · id=diag-a"))
        XCTAssertTrue(report.contains("target_profile=\(sampleBenchLoadProfileHash().prefix(8))"))
        XCTAssertTrue(report.contains("bench_task=embedding verdict=Balanced"))
        XCTAssertTrue(report.contains("bench_load=ctx=8192 · profile=\(sampleBenchLoadProfileHash().prefix(8))"))
        XCTAssertTrue(report.contains("bench_matches_target=1"))
        XCTAssertTrue(report.contains("bench_explanation=当前提供方队列繁忙"))
        XCTAssertTrue(report.contains("capability_headline=均衡"))
        XCTAssertTrue(report.contains("capability_tone=caution"))
        XCTAssertTrue(report.contains("capability_badges=均衡{caution}, 已常驻{success}, 2 个等待{caution}"))
        XCTAssertTrue(report.contains("适合=检索索引、重排预处理和 Memory 摄取批处理"))
        XCTAssertTrue(report.contains("不适合=提供方队列已繁忙时的并发突发请求"))
    }

    func testLocalRuntimeBenchModelReportIncludesCapabilitySnapshot() {
        let model = try! XCTUnwrap(sampleBenchModels().first)
        let requestContext = LocalModelRuntimeRequestContextResolver.resolve(
            model: model,
            runtimeStatus: sampleRuntimeStatus(),
            pairedProfilesSnapshot: samplePairedProfilesSnapshot(),
            targetPreference: nil
        )
        let benchResult = try! XCTUnwrap(sampleBenchSnapshot().results.first)
        let report = HubDiagnosticsBundleExporter.localRuntimeBenchModelReport(
            model: model,
            requestContext: requestContext,
            benchResult: benchResult,
            runtimeStatus: sampleRuntimeStatus(),
            generatedAtMs: 123
        )

        XCTAssertTrue(report.contains("schema_version: xhub_local_runtime_bench_model_report.v1"))
        XCTAssertTrue(report.contains("generated_at_ms: 123"))
        XCTAssertTrue(report.contains("model_id=bge-small"))
        XCTAssertTrue(report.contains("capability_headline=均衡"))
        XCTAssertTrue(report.contains("capability_tone=caution"))
        XCTAssertTrue(report.contains("capability_summary=当前提供方队列繁忙"))
        XCTAssertTrue(report.contains("需要预热=不需要。匹配的常驻目标已经加载。"))
    }

    func testOperatorChannelLiveTestEvidenceSummaryReportIncludesVerdictsAndFetchErrors() {
        let report = HubDiagnosticsBundleExporter.operatorChannelLiveTestEvidenceSummaryReport(
            reports: sampleOperatorChannelLiveTestReports(),
            sourceStatus: "ok",
            fetchErrors: ["ticket_detail[telegram]: timed out"],
            adminBaseURL: "http://127.0.0.1:50052",
            generatedAtMs: 456
        )

        XCTAssertTrue(report.contains("schema_version: xhub_operator_channel_live_test_summary.v1"))
        XCTAssertTrue(report.contains("generated_at_ms: 456"))
        XCTAssertTrue(report.contains("source_status: ok"))
        XCTAssertTrue(report.contains("admin_base_url: http://127.0.0.1:50052"))
        XCTAssertTrue(report.contains("fetch_errors:\nticket_detail[telegram]: timed out"))
        XCTAssertTrue(report.contains("provider_count: 2"))
        XCTAssertTrue(report.contains("provider=slack derived_status=pass verdict=passed live_test_success=1"))
        XCTAssertTrue(report.contains("provider=telegram derived_status=attention verdict=partial live_test_success=0"))
        XCTAssertTrue(report.contains("required_next_step=修复 Telegram 命令入口"))
        XCTAssertTrue(report.contains("repair_hints="))
        XCTAssertTrue(report.contains("重新加载 Telegram runtime"))
        XCTAssertTrue(report.contains("runtime_command_entry_ready=fail"))
        XCTAssertTrue(report.contains("heartbeat_governance_visible=pass"))
    }

    func testOperatorChannelLiveTestEvidenceExportDataRedactsSensitiveOnboardingFields() throws {
        let data = try XCTUnwrap(
            HubDiagnosticsBundleExporter.operatorChannelLiveTestEvidenceExportData(
                reports: [sampleOperatorChannelPassReport()],
                sourceStatus: "ok",
                fetchErrors: [],
                adminBaseURL: "http://127.0.0.1:50052",
                generatedAtMs: 789
            )
        )
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(raw["schema_version"] as? String, "xhub_operator_channel_live_test_export.v1")
        XCTAssertEqual(raw["generated_at_ms"] as? Int64, 789)
        XCTAssertEqual(raw["source_status"] as? String, "ok")
        XCTAssertEqual(raw["provider_count"] as? Int, 1)

        let reports = try XCTUnwrap(raw["reports"] as? [[String: Any]])
        XCTAssertEqual(reports.first?["provider"] as? String, "slack")
        XCTAssertEqual(reports.first?["summary"] as? String, "Slack live test passed.")

        let onboardingSnapshot = try XCTUnwrap(reports.first?["onboarding_snapshot"] as? [String: Any])
        let ticket = try XCTUnwrap(onboardingSnapshot["ticket"] as? [String: Any])
        XCTAssertEqual(ticket["external_user_id"] as? String, "[REDACTED]")
        XCTAssertEqual(ticket["conversation_id"] as? String, "[REDACTED]")
        XCTAssertEqual(ticket["first_message_preview"] as? String, "[REDACTED]")
        XCTAssertEqual(ticket["audit_ref"] as? String, "[REDACTED]")

        let latestDecision = try XCTUnwrap(onboardingSnapshot["latest_decision"] as? [String: Any])
        XCTAssertEqual(latestDecision["scope_id"] as? String, "[REDACTED]")
        XCTAssertEqual(latestDecision["approved_by_hub_user_id"] as? String, "[REDACTED]")
        XCTAssertEqual(latestDecision["preferred_device_id"] as? String, "[REDACTED]")

        let automationState = try XCTUnwrap(onboardingSnapshot["automation_state"] as? [String: Any])
        let firstSmoke = try XCTUnwrap(automationState["first_smoke"] as? [String: Any])
        XCTAssertEqual(firstSmoke["binding_id"] as? String, "[REDACTED]")
        XCTAssertEqual(firstSmoke["ack_outbox_item_id"] as? String, "[REDACTED]")
        XCTAssertEqual(firstSmoke["smoke_outbox_item_id"] as? String, "[REDACTED]")

        let outboxItems = try XCTUnwrap(automationState["outbox_items"] as? [[String: Any]])
        XCTAssertEqual(outboxItems.first?["provider_message_ref"] as? String, "[REDACTED]")
    }

    func testHubChannelOnboardingReadinessBundleSurfacesBlockingRepairs() throws {
        let runtimeRows = [
            sampleOperatorChannelRuntimeStatus(
                provider: "telegram",
                commandEntryReady: false,
                deliveryReady: false,
                runtimeState: "error",
                lastErrorCode: "signature_invalid",
                repairHints: ["重新签发 Telegram 通道签名密钥"]
            ),
        ]
        let readinessRows = [
            sampleOperatorChannelReadiness(
                provider: "telegram",
                ready: false,
                remediationHint: "清理可疑重放后重新发起 onboarding",
                repairHints: []
            ),
        ]
        let report = XHubDoctorOutputReport.hubChannelOnboardingReadinessBundle(
            readinessRows: readinessRows,
            runtimeRows: runtimeRows,
            liveTestReports: [],
            sourceStatus: "ok",
            fetchErrors: ["provider_runtime_status[telegram]: signature_invalid"]
        )

        XCTAssertEqual(report.bundleKind, .channelOnboardingReadiness)
        XCTAssertEqual(report.overallState, .blocked)
        XCTAssertFalse(report.readyForFirstTask)
        XCTAssertEqual(report.currentFailureCode, "channel_runtime_not_ready")
        XCTAssertEqual(report.currentFailureIssue, "channel_runtime")
        XCTAssertEqual(report.checks.map(\.status), [.fail, .fail, .warn])

        let runtimeCheck = try XCTUnwrap(report.checks.first { $0.checkKind == "channel_runtime" })
        XCTAssertEqual(runtimeCheck.nextStep, "重新签发 Telegram 通道签名密钥")
        XCTAssertTrue(runtimeCheck.detailLines.contains("fetch_error=provider_runtime_status[telegram]: signature_invalid"))
        XCTAssertTrue(runtimeCheck.detailLines.contains(where: { $0.contains("last_error_code=signature_invalid") }))

        let deliveryCheck = try XCTUnwrap(report.checks.first { $0.checkKind == "channel_delivery" })
        XCTAssertEqual(deliveryCheck.nextStep, "清理可疑重放后重新发起 onboarding")
        XCTAssertTrue(deliveryCheck.detailLines.contains(where: { $0.contains("provider=telegram") && $0.contains("deny_code=provider_delivery_not_configured") }))

        XCTAssertEqual(report.nextSteps.map(\.kind), [.openRepairSurface, .inspectDiagnostics])
        XCTAssertEqual(report.nextSteps.first?.destinationRef, "hub://settings/operator_channels")
    }

    func testWriteOperatorChannelOnboardingReadinessReportExportsDoctorBundle() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("hub-channel-doctor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let outputURL = try HubDiagnosticsBundleExporter.writeOperatorChannelOnboardingReadinessReport(
            readinessRows: [
                sampleOperatorChannelReadiness(
                    provider: "slack",
                    ready: true,
                    remediationHint: "保持 Slack delivery 当前配置",
                    repairHints: ["确认 Slack delivery 已就绪"]
                ),
            ],
            runtimeRows: [
                sampleOperatorChannelRuntimeStatus(
                    provider: "slack",
                    commandEntryReady: true,
                    deliveryReady: true,
                    runtimeState: "ready",
                    lastErrorCode: "",
                    repairHints: ["重新加载 Slack runtime"]
                ),
            ],
            liveTestReports: [sampleOperatorChannelPassReport()],
            sourceStatus: "ok",
            fetchErrors: [],
            adminBaseURL: "http://127.0.0.1:50052",
            generatedAtMs: 999,
            to: tempRoot
        )

        XCTAssertEqual(outputURL.lastPathComponent, "xhub_doctor_output_channel_onboarding.redacted.json")
        let raw = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: outputURL)) as? [String: Any]
        )

        XCTAssertEqual(raw["schema_version"] as? String, "xhub.doctor_output.v1")
        XCTAssertEqual(raw["bundle_kind"] as? String, "channel_onboarding_readiness")
        XCTAssertEqual(raw["generated_at_ms"] as? Int64, 999)
        XCTAssertEqual(raw["overall_state"] as? String, "ready")
        XCTAssertEqual(raw["ready_for_first_task"] as? Bool, true)
        XCTAssertEqual(raw["source_report_path"] as? String, "http://127.0.0.1:50052/admin/operator-channels")
        XCTAssertEqual(raw["report_path"] as? String, outputURL.path)

        let summary = try XCTUnwrap(raw["summary"] as? [String: Any])
        XCTAssertEqual(summary["headline"] as? String, "操作员通道接入已准备好进入受控放行")

        let checks = try XCTUnwrap(raw["checks"] as? [[String: Any]])
        XCTAssertEqual(checks.count, 3)
        XCTAssertEqual(checks.map { $0["status"] as? String }, ["pass", "pass", "pass"])

        let nextSteps = try XCTUnwrap(raw["next_steps"] as? [[String: Any]])
        XCTAssertEqual(nextSteps.count, 1)
        XCTAssertEqual(nextSteps.first?["kind"] as? String, "open_repair_surface")
        XCTAssertEqual(nextSteps.first?["destination_ref"] as? String, "hub://settings/operator_channels")

        let contracts = try XCTUnwrap(raw["consumed_contracts"] as? [String])
        XCTAssertTrue(contracts.contains("xt_w3_24_operator_channel_live_test_evidence.v1"))
    }

    func testHubChannelOnboardingReadinessBundleUsesDedicatedHeartbeatVisibilityFailureCode() {
        let readiness = sampleOperatorChannelReadiness(
            provider: "slack",
            ready: true,
            remediationHint: "保持 Slack delivery 当前配置",
            repairHints: ["确认 Slack delivery 已就绪"]
        )
        let runtimeStatus = sampleOperatorChannelRuntimeStatus(
            provider: "slack",
            commandEntryReady: true,
            deliveryReady: true,
            runtimeState: "ready",
            lastErrorCode: "",
            repairHints: ["重新加载 Slack runtime"]
        )
        let liveTestReport = HubOperatorChannelLiveTestEvidenceBuilder.build(
            provider: "slack",
            readiness: readiness,
            runtimeStatus: runtimeStatus,
            ticketDetail: sampleOperatorChannelTicketDetail(
                provider: "slack",
                approved: true,
                firstSmokeStatus: "query_executed",
                includeHeartbeatGovernanceSnapshot: false
            )
        )

        let report = XHubDoctorOutputReport.hubChannelOnboardingReadinessBundle(
            readinessRows: [readiness],
            runtimeRows: [runtimeStatus],
            liveTestReports: [liveTestReport],
            sourceStatus: "ok",
            fetchErrors: []
        )

        XCTAssertEqual(report.overallState, XHubDoctorOverallState.degraded)
        XCTAssertTrue(report.readyForFirstTask)
        XCTAssertEqual(report.currentFailureCode, "channel_live_test_heartbeat_visibility_missing")
        XCTAssertEqual(report.currentFailureIssue, "channel_live_test")
        guard let liveTestCheck = report.checks.first(where: { $0.checkKind == "channel_live_test" }) else {
            return XCTFail("missing channel_live_test check")
        }
        XCTAssertEqual(liveTestCheck.checkID, "channel_live_test_heartbeat_visibility_missing")
        XCTAssertTrue(liveTestCheck.detailLines.contains(where: { $0.contains("heartbeat_governance_visible=fail") }))
        XCTAssertEqual(
            liveTestCheck.nextStep,
            "Re-run or reload first smoke and verify it exported heartbeat governance visibility (quality band / next review)."
        )
        XCTAssertEqual(report.nextSteps.first?.kind, .inspectDiagnostics)
    }

    private func sampleStatusURL() -> URL {
        SharedPaths.realHomeDirectory()
            .appendingPathComponent("RELFlowHub", isDirectory: true)
            .appendingPathComponent("ai_runtime_status.json")
    }

    private func makeW9C1VerificationResults(
        readyProviders: [String],
        downProviders: [String],
        runtimeOps: LocalRuntimeOperationsSummary,
        repairSummary: LocalRuntimeRepairSurfaceSummary,
        doctorReport: XHubDoctorOutputReport,
        monitorReport: String,
        monitor: AIRuntimeMonitorSnapshot
    ) -> [VerificationResult] {
        [
            VerificationResult(
                name: "ready_provider_and_down_provider_visible_together",
                status: readyProviders.contains("transformers") && downProviders.contains("mlx") ? "pass" : "fail"
            ),
            VerificationResult(
                name: "models_runtime_keeps_queue_and_loaded_truth_visible",
                status: runtimeOps.queueSummary.contains("执行中") && runtimeOps.loadedSummary.contains("已加载实例") ? "pass" : "fail"
            ),
            VerificationResult(
                name: "runtime_monitor_surfaces_bench_fallback_and_last_error",
                status: monitor.recentBenchResults.count == 1
                    && monitor.fallbackCounters.fallbackReadyProviderCount == 1
                    && monitor.lastErrors.contains(where: { $0.code == "import_error" })
                    ? "pass" : "fail"
            ),
            VerificationResult(
                name: "doctor_and_repair_surface_align_on_partial_provider_state",
                status: doctorReport.currentFailureCode == "provider_partial_readiness"
                    && repairSummary.reasonCode == "provider_partial_readiness"
                    && repairSummary.repairDestinationRef == "hub://settings/doctor"
                    ? "pass" : "fail"
            ),
            VerificationResult(
                name: "doctor_still_allows_first_task_when_one_provider_is_ready",
                status: doctorReport.readyForFirstTask && doctorReport.overallState == .degraded ? "pass" : "fail"
            ),
            VerificationResult(
                name: "monitor_report_contains_status_source_and_runtime_ops_block",
                status: monitorReport.contains("status_source:")
                    && monitorReport.contains("runtime_ops_summary:")
                    && monitorReport.contains("monitor_recent_bench_result_count=1")
                    ? "pass" : "fail"
            )
        ]
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
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url)
    }

    private struct W9C1ProviderTruthSurfaceEvidence: Codable, Equatable {
        let schemaVersion: String
        let generatedAt: String
        let status: String
        let claimScope: [String]
        let claim: String
        let settingsRuntimeMonitor: SettingsRuntimeMonitorSurface
        let modelsRuntime: ModelsRuntimeSurface
        let doctorExport: DoctorExportSurface
        let verificationResults: [VerificationResult]
        let sourceRefs: [String]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case generatedAt = "generated_at"
            case status
            case claimScope = "claim_scope"
            case claim
            case settingsRuntimeMonitor = "settings_runtime_monitor"
            case modelsRuntime = "models_runtime"
            case doctorExport = "doctor_export"
            case verificationResults = "verification_results"
            case sourceRefs = "source_refs"
        }
    }

    private struct SettingsRuntimeMonitorSurface: Codable, Equatable {
        let runtimeAlive: Bool
        let readyProviders: [String]
        let downProviders: [String]
        let queueActive: Int
        let queueQueued: Int
        let recentBenchResultCount: Int
        let lastErrorCodes: [String]
        let fallbackReadyProviderCount: Int
        let repairReasonCode: String
        let repairDestinationRef: String
        let monitorSummaryReport: String

        enum CodingKeys: String, CodingKey {
            case runtimeAlive = "runtime_alive"
            case readyProviders = "ready_providers"
            case downProviders = "down_providers"
            case queueActive = "queue_active"
            case queueQueued = "queue_queued"
            case recentBenchResultCount = "recent_bench_result_count"
            case lastErrorCodes = "last_error_codes"
            case fallbackReadyProviderCount = "fallback_ready_provider_count"
            case repairReasonCode = "repair_reason_code"
            case repairDestinationRef = "repair_destination_ref"
            case monitorSummaryReport = "monitor_summary_report"
        }
    }

    private struct ModelsRuntimeSurface: Codable, Equatable {
        let runtimeSummary: String
        let queueSummary: String
        let loadedSummary: String
        let providerRows: [ModelsRuntimeProviderRow]
        let instanceRows: [ModelsRuntimeInstanceRow]

        enum CodingKeys: String, CodingKey {
            case runtimeSummary = "runtime_summary"
            case queueSummary = "queue_summary"
            case loadedSummary = "loaded_summary"
            case providerRows = "provider_rows"
            case instanceRows = "instance_rows"
        }
    }

    private struct ModelsRuntimeProviderRow: Codable, Equatable {
        let providerID: String
        let stateLabel: String
        let queueSummary: String
        let detailSummary: String

        enum CodingKeys: String, CodingKey {
            case providerID = "provider_id"
            case stateLabel = "state_label"
            case queueSummary = "queue_summary"
            case detailSummary = "detail_summary"
        }
    }

    private struct ModelsRuntimeInstanceRow: Codable, Equatable {
        let providerID: String
        let modelID: String
        let isCurrentTarget: Bool
        let currentTargetSummary: String
        let loadSummary: String

        enum CodingKeys: String, CodingKey {
            case providerID = "provider_id"
            case modelID = "model_id"
            case isCurrentTarget = "is_current_target"
            case currentTargetSummary = "current_target_summary"
            case loadSummary = "load_summary"
        }
    }

    private struct DoctorExportSurface: Codable, Equatable {
        let overallState: String
        let readyForFirstTask: Bool
        let currentFailureCode: String
        let currentFailureIssue: String
        let summaryHeadline: String
        let nextStepDestinations: [String]
        let checkStatuses: [DoctorCheckStatus]

        enum CodingKeys: String, CodingKey {
            case overallState = "overall_state"
            case readyForFirstTask = "ready_for_first_task"
            case currentFailureCode = "current_failure_code"
            case currentFailureIssue = "current_failure_issue"
            case summaryHeadline = "summary_headline"
            case nextStepDestinations = "next_step_destinations"
            case checkStatuses = "check_statuses"
        }
    }

    private struct DoctorCheckStatus: Codable, Equatable {
        let checkID: String
        let checkKind: String
        let status: String
        let repairDestinationRef: String

        enum CodingKeys: String, CodingKey {
            case checkID = "check_id"
            case checkKind = "check_kind"
            case status
            case repairDestinationRef = "repair_destination_ref"
        }
    }

    private struct VerificationResult: Codable, Equatable {
        let name: String
        let status: String
    }

    private func sampleRuntimeStatus() -> AIRuntimeStatus {
        AIRuntimeStatus(
            pid: 2048,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            runtimeVersion: "entry-v2",
            schemaVersion: "xhub.local_runtime_status.v2",
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: true,
                    reasonCode: "fallback_ready",
                    runtimeVersion: "entry-v2",
                    runtimeSource: "user_python_venv",
                    runtimeSourcePath: "/Users/test/project/.venv/bin/python3",
                    runtimeResolutionState: "user_runtime_fallback",
                    runtimeReasonCode: "ready",
                    fallbackUsed: true,
                    availableTaskKinds: ["embedding", "speech_to_text"],
                    loadedModels: ["bge-small"],
                    deviceBackend: "mps",
                    updatedAt: Date().timeIntervalSince1970,
                    loadedInstances: [
                        AIRuntimeLoadedInstance(
                            instanceKey: "transformers:bge-small:\(sampleBenchLoadProfileHash())",
                            modelId: "bge-small",
                            taskKinds: ["embedding"],
                            loadProfileHash: sampleBenchLoadProfileHash(),
                            effectiveContextLength: 8192,
                            effectiveLoadProfile: sampleBenchLoadProfile(),
                            loadedAt: Date().timeIntervalSince1970 - 20,
                            lastUsedAt: Date().timeIntervalSince1970 - 1,
                            residency: "resident",
                            residencyScope: "provider_runtime",
                            deviceBackend: "mps"
                        )
                    ]
                )
            ],
            providerPacks: [
                AIRuntimeProviderPackStatus(
                    schemaVersion: "xhub.provider_pack_manifest.v1",
                    providerId: "transformers",
                    engine: "hf-transformers",
                    version: "builtin-2026-03-16",
                    supportedFormats: ["hf_transformers"],
                    supportedDomains: ["embedding", "audio", "vision", "ocr"],
                    runtimeRequirements: AIRuntimeProviderPackRuntimeRequirements(
                        executionMode: "builtin_python",
                        pythonModules: ["transformers", "torch"]
                    ),
                    minHubVersion: "2026.03",
                    installed: true,
                    enabled: true,
                    packState: "installed",
                    reasonCode: "builtin_pack_registered"
                )
            ],
            monitorSnapshot: AIRuntimeMonitorSnapshot(
                schemaVersion: "xhub.local_runtime_monitor.v1",
                updatedAt: Date().timeIntervalSince1970,
                providers: [
                    AIRuntimeMonitorProvider(
                        provider: "transformers",
                        ok: true,
                        reasonCode: "fallback_ready",
                        runtimeSource: "user_python_venv",
                        runtimeResolutionState: "user_runtime_fallback",
                        runtimeReasonCode: "ready",
                        fallbackUsed: true,
                        availableTaskKinds: ["embedding", "speech_to_text"],
                        realTaskKinds: ["embedding"],
                        fallbackTaskKinds: ["speech_to_text"],
                        unavailableTaskKinds: ["vision_caption"],
                        deviceBackend: "mps",
                        lifecycleMode: "warmable",
                        residencyScope: "provider_runtime",
                        loadedInstanceCount: 1,
                        loadedModelCount: 1,
                        activeTaskCount: 1,
                        queuedTaskCount: 2,
                        concurrencyLimit: 2,
                        queueMode: "fifo",
                        queueingSupported: true,
                        oldestWaiterStartedAt: Date().timeIntervalSince1970 - 2,
                        oldestWaiterAgeMs: 280,
                        contentionCount: 3,
                        lastContentionAt: Date().timeIntervalSince1970 - 1,
                        activeMemoryBytes: 2048,
                        peakMemoryBytes: 4096,
                        memoryState: "ok",
                        idleEvictionPolicy: "ttl",
                        lastIdleEvictionReason: "timeout",
                        updatedAt: Date().timeIntervalSince1970
                    )
                ],
                activeTasks: [
                    AIRuntimeMonitorActiveTask(
                        provider: "transformers",
                        leaseId: "lease-a",
                        taskKind: "embedding",
                        modelId: "bge-small",
                        requestId: "req-a",
                        deviceId: "terminal-a",
                        loadProfileHash: sampleBenchLoadProfileHash(),
                        instanceKey: "transformers:bge-small:\(sampleBenchLoadProfileHash())",
                        effectiveContextLength: 8192,
                        maxContextLength: 16384,
                        leaseTtlSec: 120,
                        leaseRemainingTtlSec: 118,
                        expiresAt: Date().timeIntervalSince1970 + 119,
                        startedAt: Date().timeIntervalSince1970 - 1
                    )
                ],
                loadedInstances: [
                    AIRuntimeLoadedInstance(
                        instanceKey: "transformers:bge-small:\(sampleBenchLoadProfileHash())",
                        modelId: "bge-small",
                        taskKinds: ["embedding"],
                        loadProfileHash: sampleBenchLoadProfileHash(),
                        effectiveContextLength: 8192,
                        effectiveLoadProfile: sampleBenchLoadProfile(),
                        loadedAt: Date().timeIntervalSince1970 - 20,
                        lastUsedAt: Date().timeIntervalSince1970 - 1,
                        residency: "resident",
                        residencyScope: "provider_runtime",
                        deviceBackend: "mps"
                    )
                ],
                recentBenchResults: [
                    ModelBenchResult(
                        modelId: "glm4v-local",
                        providerID: "transformers",
                        taskKind: "vision_understand",
                        loadProfileHash: "vision8192",
                        fixtureProfile: "vision_smoke",
                        fixtureTitle: "Vision Smoke",
                        measuredAt: Date().timeIntervalSince1970 - 3,
                        ok: true,
                        reasonCode: "ready",
                        runtimeSource: "xhub_local_service",
                        runtimeResolutionState: "service_ready",
                        runtimeReasonCode: "xhub_local_service_ready",
                        effectiveContextLength: 8192,
                        loadConfig: sampleBenchLoadProfile(),
                        routeTraceSummary: AIRuntimeRouteTraceSummary(
                            schemaVersion: "xhub.local_runtime.route_trace_summary.v1",
                            requestMode: "chat_completions",
                            selectedTaskKind: "vision_understand",
                            selectionReason: "model_only_vision_understand",
                            imageCount: 1,
                            resolvedImageCount: 1,
                            executionPath: "real_runtime",
                            imageFiles: ["route_trace_fixture.png"]
                        )
                    )
                ],
                queue: AIRuntimeMonitorQueue(
                    providerCount: 1,
                    activeTaskCount: 1,
                    queuedTaskCount: 2,
                    providersBusyCount: 1,
                    providersWithQueuedTasksCount: 1,
                    maxOldestWaitMs: 280,
                    contentionCount: 3,
                    lastContentionAt: Date().timeIntervalSince1970 - 1,
                    updatedAt: Date().timeIntervalSince1970
                ),
                lastErrors: [
                    AIRuntimeMonitorLastError(
                        provider: "mlx",
                        code: "import_error",
                        message: "missing mlx",
                        severity: "error",
                        updatedAt: Date().timeIntervalSince1970
                    )
                ],
                fallbackCounters: AIRuntimeMonitorFallbackCounters(
                    providerCount: 1,
                    fallbackReadyProviderCount: 1,
                    fallbackOnlyProviderCount: 0,
                    fallbackReadyTaskCount: 1,
                    fallbackOnlyTaskCount: 0,
                    taskKindCounts: ["speech_to_text": 1]
                )
            )
        )
    }

    private func sampleLocalOnlyReadyStatus() -> AIRuntimeStatus {
        var status = sampleRuntimeStatus()
        status.mlxOk = true
        if var mlxProvider = status.providers["mlx"] {
            mlxProvider.ok = true
            mlxProvider.reasonCode = "legacy_ready"
            mlxProvider.availableTaskKinds = ["text_generate"]
            mlxProvider.importError = ""
            status.providers["mlx"] = mlxProvider
        }
        status.monitorSnapshot?.lastErrors = []
        return status
    }

    private func sampleXHubLocalServiceStatus(
        reasonCode: String,
        processState: String = "",
        startAttemptCount: Int = 1,
        lastStartError: String = ""
    ) -> AIRuntimeStatus {
        AIRuntimeStatus(
            pid: 4096,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            runtimeVersion: "entry-v2",
            schemaVersion: "xhub.local_runtime_status.v2",
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: false,
                    reasonCode: "runtime_missing",
                    runtimeVersion: "entry-v2",
                    runtimeSource: "xhub_local_service",
                    runtimeSourcePath: "http://127.0.0.1:50171",
                    runtimeResolutionState: "runtime_missing",
                    runtimeReasonCode: reasonCode,
                    fallbackUsed: false,
                    availableTaskKinds: ["embedding", "vision_understand"],
                    loadedModels: [],
                    deviceBackend: "service_proxy",
                    updatedAt: Date().timeIntervalSince1970,
                    managedServiceState: AIRuntimeManagedServiceState(
                        baseURL: "http://127.0.0.1:50171",
                        bindHost: "127.0.0.1",
                        bindPort: 50171,
                        pid: 43001,
                        processState: processState.isEmpty ? (reasonCode == "xhub_local_service_starting" ? "starting" : "down") : processState,
                        startedAtMs: 1_741_800_000_000,
                        lastProbeAtMs: 1_741_800_001_000,
                        lastProbeHTTPStatus: reasonCode == "xhub_local_service_starting" ? 200 : 0,
                        lastProbeError: reasonCode == "xhub_local_service_starting" ? "" : "ConnectionRefusedError:[Errno 61] Connection refused",
                        lastReadyAtMs: 0,
                        lastLaunchAttemptAtMs: 1_741_800_000_500,
                        startAttemptCount: startAttemptCount,
                        lastStartError: lastStartError,
                        updatedAtMs: 1_741_800_001_000
                    )
                )
            ],
            providerPacks: [
                AIRuntimeProviderPackStatus(
                    schemaVersion: "xhub.provider_pack_manifest.v1",
                    providerId: "transformers",
                    engine: "hf-transformers",
                    version: "builtin-2026-03-21",
                    supportedFormats: ["hf_transformers"],
                    supportedDomains: ["embedding", "vision", "ocr"],
                    runtimeRequirements: AIRuntimeProviderPackRuntimeRequirements(
                        executionMode: "xhub_local_service",
                        serviceBaseUrl: "http://127.0.0.1:50171",
                        notes: ["hub_managed_service"]
                    ),
                    minHubVersion: "2026.03",
                    installed: true,
                    enabled: true,
                    packState: "installed",
                    reasonCode: "hub_managed_service_pack_registered"
                )
            ],
            monitorSnapshot: AIRuntimeMonitorSnapshot(
                schemaVersion: "xhub.local_runtime_monitor.v1",
                updatedAt: Date().timeIntervalSince1970,
                providers: [
                    AIRuntimeMonitorProvider(
                        provider: "transformers",
                        ok: false,
                        reasonCode: "runtime_missing",
                        runtimeSource: "xhub_local_service",
                        runtimeResolutionState: "runtime_missing",
                        runtimeReasonCode: reasonCode,
                        fallbackUsed: false,
                        availableTaskKinds: ["embedding", "vision_understand"],
                        realTaskKinds: ["embedding"],
                        fallbackTaskKinds: [],
                        unavailableTaskKinds: ["ocr"],
                        deviceBackend: "service_proxy",
                        lifecycleMode: "warmable",
                        residencyScope: "service_runtime",
                        loadedInstanceCount: 1,
                        loadedModelCount: 0,
                        activeTaskCount: 0,
                        queuedTaskCount: 2,
                        concurrencyLimit: 1,
                        queueMode: "fifo",
                        queueingSupported: true,
                        oldestWaiterStartedAt: Date().timeIntervalSince1970 - 2,
                        oldestWaiterAgeMs: 200,
                        contentionCount: 1,
                        lastContentionAt: Date().timeIntervalSince1970 - 1,
                        activeMemoryBytes: 0,
                        peakMemoryBytes: 0,
                        memoryState: "unknown",
                        idleEvictionPolicy: "ttl",
                        lastIdleEvictionReason: "",
                        updatedAt: Date().timeIntervalSince1970
                    )
                ],
                activeTasks: [],
                loadedInstances: [
                    AIRuntimeLoadedInstance(
                        instanceKey: "transformers:embed-local:svc1234",
                        modelId: "embed-local",
                        taskKinds: ["embedding"],
                        loadProfileHash: "svc1234",
                        effectiveContextLength: 4096,
                        effectiveLoadProfile: LocalModelLoadProfile(
                            contextLength: 4096,
                            ttl: 300,
                            parallel: 1,
                            identifier: "svc-a"
                        ),
                        loadedAt: Date().timeIntervalSince1970 - 10,
                        lastUsedAt: Date().timeIntervalSince1970 - 3,
                        residency: "resident",
                        residencyScope: "service_runtime",
                        deviceBackend: "service_proxy"
                    )
                ],
                queue: AIRuntimeMonitorQueue(
                    providerCount: 1,
                    activeTaskCount: 0,
                    queuedTaskCount: 2,
                    providersBusyCount: 0,
                    providersWithQueuedTasksCount: 1,
                    maxOldestWaitMs: 200,
                    contentionCount: 1,
                    lastContentionAt: Date().timeIntervalSince1970 - 1,
                    updatedAt: Date().timeIntervalSince1970
                ),
                lastErrors: [],
                fallbackCounters: AIRuntimeMonitorFallbackCounters(
                    providerCount: 1,
                    fallbackReadyProviderCount: 0,
                    fallbackOnlyProviderCount: 0,
                    fallbackReadyTaskCount: 0,
                    fallbackOnlyTaskCount: 0,
                    taskKindCounts: [:]
                )
            )
        )
    }

    private func sampleBenchModels() -> [HubModel] {
        [
            HubModel(
                id: "bge-small",
                name: "BGE Small",
                backend: "transformers",
                quant: "fp16",
                contextLength: 8192,
                maxContextLength: 32768,
                paramsB: 0.1,
                state: .loaded,
                modelPath: "/tmp/models/bge-small",
                defaultLoadProfile: sampleBenchLoadProfile(),
                taskKinds: ["embedding"]
            ),
        ]
    }

    private func sampleBenchSnapshot() -> ModelsBenchSnapshot {
        ModelsBenchSnapshot(
            results: [
                ModelBenchResult(
                    modelId: "bge-small",
                    providerID: "transformers",
                    taskKind: "embedding",
                    loadProfileHash: sampleBenchLoadProfileHash(),
                    fixtureProfile: "embed_small_docs",
                    ok: true,
                    reasonCode: "",
                    verdict: "Balanced",
                    effectiveContextLength: 8192
                ),
            ],
            updatedAt: Date().timeIntervalSince1970
        )
    }

    private func samplePairedProfilesSnapshot() -> HubPairedTerminalLocalModelProfilesSnapshot {
        HubPairedTerminalLocalModelProfilesSnapshot(
            profiles: [
                HubPairedTerminalLocalModelProfile(
                    deviceId: "terminal-a",
                    modelId: "bge-small",
                    overrideProfile: LocalModelLoadProfileOverride(
                        contextLength: 8192,
                        ttl: 600,
                        parallel: 2,
                        identifier: "diag-a"
                    )
                ),
            ]
        )
    }

    private func sampleHostMetrics() -> XHubLocalRuntimeHostMetricsSnapshot {
        XHubLocalRuntimeHostMetricsSnapshot(
            sampledAtMs: 1_741_300_300,
            sampleWindowMs: 5_000,
            cpuUsagePercent: 91.5,
            cpuCoreCount: 8,
            loadAverage1m: 7.2,
            loadAverage5m: 6.3,
            loadAverage15m: 5.9,
            normalizedLoadAverage1m: 0.9,
            memoryPressure: "high",
            memoryUsedBytes: 24_000_000_000,
            memoryAvailableBytes: 2_000_000_000,
            memoryCompressedBytes: 3_000_000_000,
            thermalState: "serious",
            severity: "high",
            summary: "host_load_severity=high cpu_percent=91.5 load_avg=7.20/6.30/5.90 normalized_1m=0.90 memory_pressure=high thermal_state=serious",
            detailLines: [
                "host_load_severity=high cpu_percent=91.5 load_avg=7.20/6.30/5.90 normalized_1m=0.90 memory_pressure=high thermal_state=serious",
                "host_memory_bytes used=24000000000 available=2000000000 compressed=3000000000",
                "host_cpu_context cpu_cores=8 sample_window_ms=5000"
            ]
        )
    }

    private func sampleBenchLoadProfile() -> LocalModelLoadProfile {
        LocalModelLoadProfile(
            contextLength: 8192,
            ttl: 600,
            parallel: 2,
            identifier: "diag-a"
        )
    }

    private func sampleBenchLoadProfileHash() -> String {
        LocalModelRuntimeRequestContextResolver.canonicalLoadProfileHash(sampleBenchLoadProfile())
    }

    private func sampleOperatorChannelLiveTestReports() -> [HubOperatorChannelLiveTestEvidenceReport] {
        [sampleOperatorChannelPassReport(), sampleOperatorChannelAttentionReport()]
    }

    private func sampleOperatorChannelPassReport() -> HubOperatorChannelLiveTestEvidenceReport {
        let provider = "slack"
        let readiness = sampleOperatorChannelReadiness(
            provider: provider,
            ready: true,
            remediationHint: "确认 Slack delivery 已就绪",
            repairHints: ["确认 Slack delivery 已就绪"]
        )
        let runtimeStatus = sampleOperatorChannelRuntimeStatus(
            provider: provider,
            commandEntryReady: true,
            deliveryReady: true,
            runtimeState: "ready",
            lastErrorCode: "",
            repairHints: ["重新加载 Slack runtime"]
        )
        return HubOperatorChannelLiveTestEvidenceBuilder.build(
            provider: provider,
            verdict: "passed",
            summary: "Slack live test passed.",
            performedAt: Date(timeIntervalSince1970: 1_741_800_123),
            evidenceRefs: ["captures/slack-live-1.png"],
            readiness: readiness,
            runtimeStatus: runtimeStatus,
            ticketDetail: sampleOperatorChannelTicketDetail(provider: provider, approved: true, firstSmokeStatus: "query_executed"),
            adminBaseURL: "http://127.0.0.1:50052",
            outputPath: ""
        )
    }

    private func sampleOperatorChannelAttentionReport() -> HubOperatorChannelLiveTestEvidenceReport {
        let provider = "telegram"
        let readiness = sampleOperatorChannelReadiness(
            provider: provider,
            ready: false,
            remediationHint: "补齐 Telegram delivery 配置",
            repairHints: ["补齐 Telegram delivery 配置"]
        )
        let runtimeStatus = sampleOperatorChannelRuntimeStatus(
            provider: provider,
            commandEntryReady: false,
            deliveryReady: false,
            runtimeState: "blocked",
            lastErrorCode: "missing_bot_token",
            repairHints: ["修复 Telegram 命令入口", "重新加载 Telegram runtime"]
        )
        return HubOperatorChannelLiveTestEvidenceBuilder.build(
            provider: provider,
            verdict: "partial",
            summary: "Telegram live test still needs repair.",
            performedAt: Date(timeIntervalSince1970: 1_741_800_456),
            evidenceRefs: ["captures/telegram-live-1.png"],
            readiness: readiness,
            runtimeStatus: runtimeStatus,
            ticketDetail: sampleOperatorChannelTicketDetail(provider: provider, approved: false, firstSmokeStatus: "denied"),
            adminBaseURL: "http://127.0.0.1:50052",
            outputPath: "",
            requiredNextStep: "修复 Telegram 命令入口"
        )
    }

    private func sampleOperatorChannelReadiness(
        provider: String,
        ready: Bool,
        remediationHint: String,
        repairHints: [String]
    ) -> HubOperatorChannelOnboardingDeliveryReadiness {
        HubOperatorChannelOnboardingDeliveryReadiness(
            provider: provider,
            ready: ready,
            replyEnabled: ready,
            credentialsConfigured: ready,
            denyCode: ready ? "" : "provider_delivery_not_configured",
            remediationHint: remediationHint,
            repairHints: repairHints
        )
    }

    private func sampleOperatorChannelRuntimeStatus(
        provider: String,
        commandEntryReady: Bool,
        deliveryReady: Bool,
        runtimeState: String,
        lastErrorCode: String,
        repairHints: [String]
    ) -> HubOperatorChannelProviderRuntimeStatus {
        HubOperatorChannelProviderRuntimeStatus(
            provider: provider,
            label: provider.uppercased(),
            releaseStage: "validated",
            releaseBlocked: false,
            requireRealEvidence: false,
            endpointVisibility: "hub_first",
            operatorSurface: "hub",
            runtimeState: runtimeState,
            deliveryReady: deliveryReady,
            commandEntryReady: commandEntryReady,
            lastErrorCode: lastErrorCode,
            updatedAtMs: 1_741_800_900_000,
            repairHints: repairHints
        )
    }

    private func sampleOperatorChannelTicketDetail(
        provider: String,
        approved: Bool,
        firstSmokeStatus: String,
        includeHeartbeatGovernanceSnapshot: Bool = true
    ) -> HubOperatorChannelOnboardingTicketDetail {
        let ticket = HubOperatorChannelOnboardingTicket(
            schemaVersion: "xt.operator_channel_onboarding_ticket.v1",
            ticketId: "\(provider)-ticket-1",
            provider: provider,
            accountId: "\(provider)-account-1",
            externalUserId: "external-user-1",
            externalTenantId: "tenant-1",
            conversationId: "conversation-1",
            threadKey: "thread-1",
            ingressSurface: "dm",
            firstMessagePreview: "hello from operator",
            proposedScopeType: "project",
            proposedScopeId: "project-alpha",
            recommendedBindingMode: "thread_binding",
            status: approved ? "approved" : "held",
            effectiveStatus: approved ? "approved" : "held",
            eventCount: 2,
            firstSeenAtMs: 1_741_800_100_000,
            lastSeenAtMs: 1_741_800_200_000,
            createdAtMs: 1_741_800_100_000,
            updatedAtMs: 1_741_800_200_000,
            expiresAtMs: 1_741_860_000_000,
            lastRequestId: "request-1",
            auditRef: "audit-ticket-1"
        )
        let decision = approved
            ? HubOperatorChannelOnboardingApprovalDecision(
                schemaVersion: "xt.operator_channel_onboarding_decision.v1",
                decisionId: "\(provider)-decision-1",
                ticketId: ticket.ticketId,
                decision: "approve",
                approvedByHubUserId: "hub-admin",
                approvedVia: "hub_ui",
                hubUserId: "hub-user-1",
                scopeType: "project",
                scopeId: "project-alpha",
                bindingMode: "thread_binding",
                preferredDeviceId: "terminal-a",
                allowedActions: ["supervisor.status.get"],
                grantProfile: "readonly",
                note: "approved for smoke",
                createdAtMs: 1_741_800_250_000,
                auditRef: "audit-decision-1"
            )
            : nil
        let firstSmoke = HubOperatorChannelOnboardingFirstSmokeReceipt(
            schemaVersion: "xt.operator_channel_onboarding_first_smoke.v1",
            receiptId: "\(provider)-receipt-1",
            ticketId: ticket.ticketId,
            decisionId: decision?.decisionId ?? "",
            provider: provider,
            actionName: "supervisor.status.get",
            status: firstSmokeStatus,
            routeMode: approved ? "governed" : "hub_only",
            denyCode: approved ? "" : "approval_missing",
            detail: approved ? "status query executed" : "approval missing",
            remediationHint: approved ? "" : "请先完成审批",
            projectId: "project-alpha",
            bindingId: "binding-1",
            ackOutboxItemId: "ack-1",
            smokeOutboxItemId: "smoke-1",
            heartbeatGovernanceSnapshot: includeHeartbeatGovernanceSnapshot && approved && firstSmokeStatus == "query_executed"
                ? HubOperatorChannelOnboardingFirstSmokeReceipt.HeartbeatGovernanceSnapshot(
                    projectId: "project-alpha",
                    projectName: "Alpha",
                    statusDigest: "Core loop advancing",
                    latestQualityBand: "usable",
                    latestQualityScore: 74,
                    openAnomalyTypes: ["stale_repeat"],
                    weakReasons: ["evidence_thin"],
                    nextReviewDue: HubOperatorChannelOnboardingFirstSmokeReceipt.HeartbeatGovernanceNextReviewDue(
                        kind: "review_pulse",
                        due: true,
                        atMs: 1_741_800_300_000,
                        reasonCodes: ["pulse_due_window"]
                    )
                )
                : nil,
            createdAtMs: 1_741_800_260_000,
            updatedAtMs: 1_741_800_270_000,
            auditRef: "audit-smoke-1"
        )
        let outboxItem = HubOperatorChannelOutboxItem(
            schemaVersion: "xt.operator_channel_onboarding_outbox.v1",
            itemId: "\(provider)-outbox-1",
            provider: provider,
            itemKind: "onboarding_first_smoke",
            status: approved ? "delivered" : "pending",
            ticketId: ticket.ticketId,
            decisionId: decision?.decisionId ?? "",
            receiptId: firstSmoke.receiptId,
            attemptCount: approved ? 1 : 0,
            lastErrorCode: approved ? "" : "provider_delivery_not_configured",
            lastErrorMessage: approved ? "" : "delivery missing",
            providerMessageRef: "provider-msg-1",
            createdAtMs: 1_741_800_255_000,
            updatedAtMs: 1_741_800_280_000,
            deliveredAtMs: approved ? 1_741_800_281_000 : 0,
            auditRef: "audit-outbox-1"
        )
        let automationState = HubOperatorChannelOnboardingAutomationState(
            schemaVersion: "xt.operator_channel_onboarding_automation_state.v1",
            ticketId: ticket.ticketId,
            firstSmoke: firstSmoke,
            outboxItems: [outboxItem],
            outboxPendingCount: approved ? 0 : 1,
            outboxDeliveredCount: approved ? 1 : 0,
            deliveryReadiness: sampleOperatorChannelReadiness(
                provider: provider,
                ready: approved,
                remediationHint: approved ? "保持当前配置" : "补齐 delivery 配置",
                repairHints: approved ? [] : ["补齐 delivery 配置"]
            )
        )
        return HubOperatorChannelOnboardingTicketDetail(
            ticket: ticket,
            latestDecision: decision,
            automationState: automationState
        )
    }
}
