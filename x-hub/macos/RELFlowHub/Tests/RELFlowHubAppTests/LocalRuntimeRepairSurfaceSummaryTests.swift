import Foundation
import XCTest
@testable import RELFlowHub
import RELFlowHubCore

final class LocalRuntimeRepairSurfaceSummaryTests: XCTestCase {
    func testBuildReturnsStaleHeartbeatSummaryWhenHeartbeatExpired() throws {
        let status = AIRuntimeStatus(
            pid: 41,
            updatedAt: Date().timeIntervalSince1970 - 30,
            mlxOk: false,
            providers: [
                "transformers": AIRuntimeProviderStatus(provider: "transformers", ok: true)
            ]
        )

        let summary = try XCTUnwrap(
            LocalRuntimeRepairSurfaceSummaryBuilder.build(status: status)
        )

        XCTAssertEqual(summary.reasonCode, "runtime_heartbeat_stale")
        XCTAssertEqual(summary.severity, .critical)
        XCTAssertEqual(summary.destinationLabel, "Hub 设置 -> Diagnostics")
    }

    func testBuildReturnsNoReadyProviderSummaryWhenRuntimeAliveButNoProviderReady() throws {
        let status = AIRuntimeStatus(
            pid: 52,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            providers: [
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: false,
                    reasonCode: "runtime_missing",
                    availableTaskKinds: ["embedding"]
                )
            ]
        )

        let summary = try XCTUnwrap(
            LocalRuntimeRepairSurfaceSummaryBuilder.build(status: status)
        )

        XCTAssertEqual(summary.reasonCode, "no_ready_provider")
        XCTAssertEqual(summary.severity, .critical)
        XCTAssertEqual(summary.headline, "当前没有可用的本地 provider")
        XCTAssertEqual(summary.repairDestinationRef, "hub://settings/diagnostics")
        XCTAssertTrue(summary.message.contains("当前不可用"))
    }

    func testBuildReturnsPartialProviderSummaryWhenSomeProvidersRemainDown() throws {
        let status = AIRuntimeStatus(
            pid: 63,
            updatedAt: Date().timeIntervalSince1970,
            mlxOk: false,
            providers: [
                "mlx": AIRuntimeProviderStatus(
                    provider: "mlx",
                    ok: true,
                    availableTaskKinds: ["text_generate"]
                ),
                "transformers": AIRuntimeProviderStatus(
                    provider: "transformers",
                    ok: false,
                    reasonCode: "runtime_missing",
                    availableTaskKinds: ["embedding"]
                )
            ]
        )

        let summary = try XCTUnwrap(
            LocalRuntimeRepairSurfaceSummaryBuilder.build(status: status)
        )

        XCTAssertEqual(summary.reasonCode, "provider_partial_readiness")
        XCTAssertEqual(summary.severity, .warning)
        XCTAssertEqual(summary.repairDestinationRef, "hub://settings/doctor")
        XCTAssertEqual(summary.actions.first?.actionID, "review_partial_provider_failure")
    }

    func testBuildReturnsManagedServiceLaunchFailureSummaryWhenHostedProviderCrashIsDetected() throws {
        let summary = try XCTUnwrap(
            LocalRuntimeRepairSurfaceSummaryBuilder.build(status: sampleManagedServiceLaunchFailureStatus())
        )

        XCTAssertEqual(summary.reasonCode, "xhub_local_service_unreachable")
        XCTAssertEqual(summary.severity, .critical)
        XCTAssertEqual(summary.repairDestinationRef, "hub://settings/diagnostics")
        XCTAssertEqual(summary.actions.first?.actionID, "inspect_managed_launch_error")
        XCTAssertEqual(summary.headline, "Hub 管理的本地服务不可达")
        XCTAssertTrue(summary.message.contains("无法访问"))
    }

    func testRuntimeCaptureWritesW9C4EvidenceWhenRequested() throws {
        guard let captureDir = ProcessInfo.processInfo.environment["XHUB_W9_C4_CAPTURE_DIR"], !captureDir.isEmpty else {
            return
        }

        let base = URL(fileURLWithPath: captureDir)
        let scenarios = try makeEvidenceScenarios().map(captureScenario)
        let evidence = W9C4RuntimeRepairEntryEvidence(
            schemaVersion: "w9_c4_runtime_repair_entry_evidence.v1",
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            status: "delivered",
            claimScope: ["W9-C4"],
            claim: "Hub now exposes one shared repair surface for stale heartbeat, no ready provider, managed-service launch failure, and provider down/partial readiness states across Runtime Monitor and Models -> Runtime.",
            uiSurfaces: [
                "settings.runtime_monitor",
                "models.runtime_operations_card"
            ],
            scenarios: scenarios,
            verificationResults: makeVerificationResults(scenarios: scenarios),
            sourceRefs: [
                "x-hub/macos/RELFlowHub/Sources/RELFlowHub/LocalRuntimeRepairSurface.swift:17",
                "x-hub/macos/RELFlowHub/Sources/RELFlowHub/XHubLocalServiceRecoveryGuidance.swift:99",
                "x-hub/macos/RELFlowHub/Sources/RELFlowHub/MainPanelView.swift:2481",
                "x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift:5434",
                "x-hub/macos/RELFlowHub/Sources/RELFlowHub/XHubDoctorOutputHub.swift:462",
                "x-hub/macos/RELFlowHub/Tests/RELFlowHubAppTests/LocalRuntimeRepairSurfaceSummaryTests.swift:6"
            ]
        )

        let fileName = "w9_c4_runtime_repair_entry_evidence.v1.json"
        for destination in evidenceDestinations(captureBase: base, fileName: fileName) {
            try writeJSON(evidence, to: destination)
            XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    private func makeEvidenceScenarios() -> [EvidenceScenario] {
        [
            EvidenceScenario(
                name: "runtime_heartbeat_stale",
                status: AIRuntimeStatus(
                    pid: 410,
                    updatedAt: Date().timeIntervalSince1970 - 30,
                    mlxOk: false,
                    providers: [
                        "transformers": AIRuntimeProviderStatus(
                            provider: "transformers",
                            ok: true,
                            availableTaskKinds: ["embedding", "text_generate"]
                        )
                    ]
                )
            ),
            EvidenceScenario(
                name: "no_ready_provider",
                status: AIRuntimeStatus(
                    pid: 520,
                    updatedAt: Date().timeIntervalSince1970,
                    mlxOk: false,
                    providers: [
                        "transformers": AIRuntimeProviderStatus(
                            provider: "transformers",
                            ok: false,
                            reasonCode: "runtime_missing",
                            availableTaskKinds: ["embedding"]
                        )
                    ]
                )
            ),
            EvidenceScenario(
                name: "provider_partial_readiness",
                status: AIRuntimeStatus(
                    pid: 630,
                    updatedAt: Date().timeIntervalSince1970,
                    mlxOk: false,
                    providers: [
                        "mlx": AIRuntimeProviderStatus(
                            provider: "mlx",
                            ok: true,
                            availableTaskKinds: ["text_generate"]
                        ),
                        "transformers": AIRuntimeProviderStatus(
                            provider: "transformers",
                            ok: false,
                            reasonCode: "runtime_missing",
                            availableTaskKinds: ["embedding", "vision_understand"]
                        )
                    ]
                )
            ),
            EvidenceScenario(
                name: "managed_service_launch_failed",
                status: sampleManagedServiceLaunchFailureStatus()
            )
        ]
    }

    private func captureScenario(_ scenario: EvidenceScenario) throws -> CapturedScenario {
        let summary = try XCTUnwrap(
            LocalRuntimeRepairSurfaceSummaryBuilder.build(status: scenario.status),
            "Expected shared repair surface summary for scenario \(scenario.name)"
        )
        let report = XHubDoctorOutputReport.hubRuntimeReadinessBundle(
            status: scenario.status,
            blockedCapabilities: [],
            outputPath: "/tmp/\(scenario.name).json",
            surface: .hubUI,
            statusURL: sampleStatusURL()
        )
        let matchingCheck = try XCTUnwrap(
            report.checks.first(where: { $0.checkID == summary.reasonCode }),
            "Expected doctor check aligned with summary reason code \(summary.reasonCode)"
        )

        return CapturedScenario(
            name: scenario.name,
            summary: CapturedSummary(
                reasonCode: summary.reasonCode,
                severity: summary.severity.rawValue,
                headline: summary.headline,
                nextStep: summary.nextStep,
                repairDestinationRef: summary.repairDestinationRef,
                destinationLabel: summary.destinationLabel,
                actionIDs: summary.actions.map(\.actionID),
                clipboardText: summary.clipboardText
            ),
            doctorCheck: CapturedDoctorCheck(
                checkID: matchingCheck.checkID,
                checkKind: matchingCheck.checkKind,
                status: matchingCheck.status.rawValue,
                headline: matchingCheck.headline,
                nextStep: matchingCheck.nextStep,
                repairDestinationRef: matchingCheck.repairDestinationRef ?? ""
            ),
            alignment: CapturedAlignment(
                reasonCodeMatches: matchingCheck.checkID == summary.reasonCode,
                headlineMatches: matchingCheck.headline == summary.headline,
                nextStepMatches: matchingCheck.nextStep == summary.nextStep,
                repairDestinationMatches: matchingCheck.repairDestinationRef == summary.repairDestinationRef
            )
        )
    }

    private func makeVerificationResults(
        scenarios: [CapturedScenario]
    ) -> [VerificationResult] {
        let codes = Set(scenarios.map(\.summary.reasonCode))
        return [
            VerificationResult(
                name: "covers_required_failure_states",
                status: codes == ["runtime_heartbeat_stale", "no_ready_provider", "provider_partial_readiness", "xhub_local_service_unreachable"] ? "pass" : "fail"
            ),
            VerificationResult(
                name: "doctor_checks_match_shared_surface_reason_codes",
                status: scenarios.allSatisfy(\.alignment.reasonCodeMatches) ? "pass" : "fail"
            ),
            VerificationResult(
                name: "doctor_checks_match_next_steps_and_destinations",
                status: scenarios.allSatisfy { $0.alignment.nextStepMatches && $0.alignment.repairDestinationMatches } ? "pass" : "fail"
            ),
            VerificationResult(
                name: "repair_surface_always_explains_next_step",
                status: scenarios.allSatisfy { !$0.summary.nextStep.isEmpty && !$0.summary.headline.isEmpty } ? "pass" : "fail"
            ),
            VerificationResult(
                name: "critical_failures_route_to_diagnostics",
                status: scenarios
                    .filter { $0.summary.severity == "critical" }
                    .allSatisfy { $0.summary.repairDestinationRef == "hub://settings/diagnostics" } ? "pass" : "fail"
            ),
            VerificationResult(
                name: "partial_provider_routes_to_doctor",
                status: scenarios.contains {
                    $0.summary.reasonCode == "provider_partial_readiness"
                        && $0.summary.severity == "warning"
                        && $0.summary.repairDestinationRef == "hub://settings/doctor"
                } ? "pass" : "fail"
            ),
            VerificationResult(
                name: "managed_service_launch_failure_routes_to_diagnostics",
                status: scenarios.contains {
                    $0.summary.reasonCode == "xhub_local_service_unreachable"
                        && $0.summary.severity == "critical"
                        && $0.summary.repairDestinationRef == "hub://settings/diagnostics"
                        && $0.summary.actionIDs.contains("inspect_managed_launch_error")
                } ? "pass" : "fail"
            )
        ]
    }

    private func evidenceDestinations(captureBase: URL, fileName: String) -> [URL] {
        let requested = captureBase.appendingPathComponent(fileName)
        var seen: Set<String> = []
        var candidates = [requested]
        if let workspaceRoot = workspaceRoot() {
            candidates.append(
                workspaceRoot
                    .appendingPathComponent("build/reports")
                    .appendingPathComponent(fileName)
            )
        }
        return candidates.filter { url in
            seen.insert(url.standardizedFileURL.path).inserted
        }
    }

    private func workspaceRoot() -> URL? {
        var current = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while current.path != "/" {
            if current.lastPathComponent == "x-hub-system" {
                return current
            }
            current.deleteLastPathComponent()
        }
        return nil
    }

    private func sampleStatusURL() -> URL {
        URL(fileURLWithPath: "/Users/USER/RELFlowHub/ai_runtime_status.json")
    }

    private func sampleManagedServiceLaunchFailureStatus() -> AIRuntimeStatus {
        AIRuntimeStatus(
            pid: 731,
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
                    runtimeReasonCode: "xhub_local_service_unreachable",
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
                        processState: "launch_failed",
                        startedAtMs: 1_741_800_000_000,
                        lastProbeAtMs: 1_741_800_001_000,
                        lastProbeHTTPStatus: 0,
                        lastProbeError: "ConnectionRefusedError:[Errno 61] Connection refused",
                        lastReadyAtMs: 0,
                        lastLaunchAttemptAtMs: 1_741_800_000_500,
                        startAttemptCount: 2,
                        lastStartError: "spawn_exit_1",
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
                    supportedDomains: ["embedding", "vision"],
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
            ]
        )
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url)
    }

    private struct EvidenceScenario {
        let name: String
        let status: AIRuntimeStatus
    }

    private struct W9C4RuntimeRepairEntryEvidence: Codable, Equatable {
        let schemaVersion: String
        let generatedAt: String
        let status: String
        let claimScope: [String]
        let claim: String
        let uiSurfaces: [String]
        let scenarios: [CapturedScenario]
        let verificationResults: [VerificationResult]
        let sourceRefs: [String]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case generatedAt = "generated_at"
            case status
            case claimScope = "claim_scope"
            case claim
            case uiSurfaces = "ui_surfaces"
            case scenarios
            case verificationResults = "verification_results"
            case sourceRefs = "source_refs"
        }
    }

    private struct CapturedScenario: Codable, Equatable {
        let name: String
        let summary: CapturedSummary
        let doctorCheck: CapturedDoctorCheck
        let alignment: CapturedAlignment

        enum CodingKeys: String, CodingKey {
            case name
            case summary
            case doctorCheck = "doctor_check"
            case alignment
        }
    }

    private struct CapturedSummary: Codable, Equatable {
        let reasonCode: String
        let severity: String
        let headline: String
        let nextStep: String
        let repairDestinationRef: String
        let destinationLabel: String
        let actionIDs: [String]
        let clipboardText: String

        enum CodingKeys: String, CodingKey {
            case reasonCode = "reason_code"
            case severity
            case headline
            case nextStep = "next_step"
            case repairDestinationRef = "repair_destination_ref"
            case destinationLabel = "destination_label"
            case actionIDs = "action_ids"
            case clipboardText = "clipboard_text"
        }
    }

    private struct CapturedDoctorCheck: Codable, Equatable {
        let checkID: String
        let checkKind: String
        let status: String
        let headline: String
        let nextStep: String
        let repairDestinationRef: String

        enum CodingKeys: String, CodingKey {
            case checkID = "check_id"
            case checkKind = "check_kind"
            case status
            case headline
            case nextStep = "next_step"
            case repairDestinationRef = "repair_destination_ref"
        }
    }

    private struct CapturedAlignment: Codable, Equatable {
        let reasonCodeMatches: Bool
        let headlineMatches: Bool
        let nextStepMatches: Bool
        let repairDestinationMatches: Bool

        enum CodingKeys: String, CodingKey {
            case reasonCodeMatches = "reason_code_matches"
            case headlineMatches = "headline_matches"
            case nextStepMatches = "next_step_matches"
            case repairDestinationMatches = "repair_destination_matches"
        }
    }

    private struct VerificationResult: Codable, Equatable {
        let name: String
        let status: String
    }
}
