import Foundation
import Testing
@testable import XTerminal

struct XTStaleProfileRepairEvidenceTests {
    @Test
    func staleProfileRepairStaysFailClosedAcrossCoordinatorDoctorAndRouteTruth() async throws {
        let discoveryCandidates = [
            "hub_instance_mismatch",
            "pairing_profile_epoch_stale",
            "route_pack_outdated",
            "unauthenticated",
        ]
        let discoveryFailClosedReasonCodes = discoveryCandidates.filter {
            HubPairingCoordinator.shouldFailClosedOnDiscoveryReasonForTesting($0)
        }
        #expect(discoveryFailClosedReasonCodes == [
            "hub_instance_mismatch",
            "pairing_profile_epoch_stale",
            "route_pack_outdated",
        ])

        let connectBoundaryCandidates = [
            "invite_token_required",
            "invite_token_invalid",
            "pairing_token_invalid",
            "bootstrap_token_invalid",
            "pairing_token_expired",
            "bootstrap_token_expired",
            "unauthenticated",
            "mtls_client_certificate_required",
            "certificate_required",
            "hub_instance_mismatch",
            "pairing_profile_epoch_stale",
            "route_pack_outdated",
            "grpc_unavailable",
        ]
        let connectRefreshSkipReasonCodes = connectBoundaryCandidates.filter {
            HubPairingCoordinator.shouldSkipBootstrapRefreshAfterConnectFailureForTesting($0)
        }
        #expect(connectRefreshSkipReasonCodes == [
            "invite_token_required",
            "invite_token_invalid",
            "pairing_token_invalid",
            "bootstrap_token_invalid",
            "pairing_token_expired",
            "bootstrap_token_expired",
            "unauthenticated",
            "mtls_client_certificate_required",
            "certificate_required",
            "hub_instance_mismatch",
            "pairing_profile_epoch_stale",
            "route_pack_outdated",
        ])

        let staleEpochProbe = try await runEnsureConnectedProbe(
            prefix: "stale_epoch",
            pairingEnv: """
            AXHUB_APP_ID='x_terminal'
            AXHUB_DEVICE_NAME='X-Terminal'
            AXHUB_PAIRING_PROFILE_EPOCH='7'
            AXHUB_ROUTE_PACK_VERSION='route_pack_live'
            """,
            discoverOutput: """
            host: hub.test.invalid
            pairing_port: 50052
            grpc_port: 50051
            internet_host: hub.test.invalid
            pairing_profile_epoch: 9
            route_pack_version: route_pack_live
            """,
            expectedReasonCode: "pairing_profile_epoch_stale"
        )
        let mismatchProbe = try await runEnsureConnectedProbe(
            prefix: "hub_instance_mismatch",
            pairingEnv: """
            AXHUB_APP_ID='x_terminal'
            AXHUB_DEVICE_NAME='X-Terminal'
            AXHUB_HUB_INSTANCE_ID='hub_cached'
            AXHUB_PAIRING_PROFILE_EPOCH='7'
            AXHUB_ROUTE_PACK_VERSION='route_pack_live'
            """,
            discoverOutput: """
            host: hub.test.invalid
            pairing_port: 50052
            grpc_port: 50051
            internet_host: hub.test.invalid
            hub_instance_id: hub_live
            pairing_profile_epoch: 9
            route_pack_version: route_pack_live
            """,
            expectedReasonCode: "hub_instance_mismatch"
        )
        let routePackProbe = try await runDetectPortsProbe(
            pairingEnv: """
            AXHUB_APP_ID='x_terminal'
            AXHUB_DEVICE_NAME='X-Terminal'
            AXHUB_ROUTE_PACK_VERSION='route_pack_old'
            """,
            discoverOutput: """
            host: hub.test.invalid
            pairing_port: 50055
            grpc_port: 50056
            internet_host: hub.test.invalid
            route_pack_version: route_pack_live
            """,
            expectedReasonCode: "route_pack_outdated"
        )
        let inviteProbe = try await runConnectBoundaryProbe(
            connectOutput: """
            [error] invite_token_invalid: invite token no longer matches current pairing profile
            """,
            expectedReasonCode: "invite_token_invalid"
        )
        let unauthenticatedProbe = try await runConnectBoundaryProbe(
            connectOutput: """
            [error] unauthenticated: token no longer matches current pairing profile
            """,
            expectedReasonCode: "unauthenticated"
        )
        let certificateProbe = try await runConnectBoundaryProbe(
            connectOutput: """
            [error] certificate_required: paired client certificate no longer matches current hub identity
            """,
            expectedReasonCode: "certificate_required"
        )

        let probesByFailureCode = Dictionary(
            uniqueKeysWithValues: [
                ("invite_token_invalid", inviteProbe),
                ("certificate_required", certificateProbe),
                ("hub_instance_mismatch", mismatchProbe),
                ("pairing_profile_epoch_stale", staleEpochProbe),
                ("route_pack_outdated", routePackProbe),
                ("unauthenticated", unauthenticatedProbe),
            ]
        )

        let scenarioFailureCodes = [
            "invite_token_invalid",
            "unauthenticated",
            "certificate_required",
            "hub_instance_mismatch",
            "pairing_profile_epoch_stale",
            "route_pack_outdated",
        ]
        let cases = try scenarioFailureCodes.map { failureCode in
            try makeCaseEvidence(
                failureCode: failureCode,
                shouldFailClosedOnDiscovery: HubPairingCoordinator.shouldFailClosedOnDiscoveryReasonForTesting(
                    failureCode
                ),
                shouldSkipBootstrapRefreshAfterConnectFailure: HubPairingCoordinator.shouldSkipBootstrapRefreshAfterConnectFailureForTesting(
                    failureCode
                ),
                probe: probesByFailureCode[failureCode]
            )
        }

        guard let captureDir = ProcessInfo.processInfo.environment["XHUB_DOCTOR_XT_STALE_PROFILE_REPAIR_CAPTURE_DIR"],
              !captureDir.isEmpty else {
            return
        }

        let base = URL(fileURLWithPath: captureDir, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let evidence = XTStaleProfileRepairCaptureEvidence(
            schemaVersion: "xt.stale_profile_repair_capture.v1",
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            status: "pass",
            discoveryFailClosedReasonCodes: discoveryFailClosedReasonCodes,
            connectRefreshSkipReasonCodes: connectRefreshSkipReasonCodes,
            cases: cases
        )
        let destination = base.appendingPathComponent("xt_stale_profile_repair_capture.v1.json")
        try writeEvidenceJSON(evidence, to: destination)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    private func makeCaseEvidence(
        failureCode: String,
        shouldFailClosedOnDiscovery: Bool,
        shouldSkipBootstrapRefreshAfterConnectFailure: Bool,
        probe: XTStaleProfileRepairProbeEvidence?
    ) throws -> XTStaleProfileRepairCaseEvidence {
        let issue = try #require(UITroubleshootKnowledgeBase.issue(forFailureCode: failureCode))
        #expect(issue == .pairingRepairRequired)

        let repairContext = AppModel.automaticFirstPairRepairContext(
            for: failureCode,
            internetHost: "hub.tailnet.example"
        )
        #expect(repairContext.title.isEmpty == false)
        #expect(repairContext.detail.isEmpty == false)

        let doctor = XTUnifiedDoctorBuilder.build(
            input: makeTroubleshootingDoctorInput(failureCode: failureCode)
        )
        let doctorSection = try #require(doctor.section(.hubReachability))
        #expect(doctorSection.headline.isEmpty == false)
        #expect(doctorSection.nextStep.isEmpty == false)

        let routeSnapshot = XTPairedRouteSetSnapshotBuilder.build(
            input: makePairedRouteSetBuildInput(
                cachedProfile: HubAIClient.CachedRemoteProfile(
                    host: "192.168.0.10",
                    internetHost: "hub.tailnet.example",
                    pairingPort: 50052,
                    grpcPort: 50051,
                    hubInstanceID: "hub_cached",
                    lanDiscoveryName: "axhub-lan",
                    pairingProfileEpoch: 7,
                    routePackVersion: "route_pack_old"
                ),
                failureCode: failureCode
            )
        )
        #expect(routeSnapshot.readiness == .remoteBlocked)
        #expect(routeSnapshot.readinessReasonCode == "remote_pairing_or_identity_blocked")
        #expect(routeSnapshot.stableRemoteRoute?.host == "hub.tailnet.example")

        return XTStaleProfileRepairCaseEvidence(
            failureCode: failureCode,
            mappedIssue: issue.rawValue,
            repairTitle: repairContext.title,
            repairDetail: repairContext.detail,
            doctorHeadline: doctorSection.headline,
            doctorNextStep: doctorSection.nextStep,
            doctorRepairEntry: doctorSection.repairEntry.rawValue,
            pairedRouteReadiness: routeSnapshot.readiness.rawValue,
            pairedRouteReasonCode: routeSnapshot.readinessReasonCode,
            pairedRouteSummaryLine: routeSnapshot.summaryLine,
            stableRemoteHost: routeSnapshot.stableRemoteRoute?.host ?? "",
            shouldFailClosedOnDiscovery: shouldFailClosedOnDiscovery,
            shouldSkipBootstrapRefreshAfterConnectFailure: shouldSkipBootstrapRefreshAfterConnectFailure,
            probeStage: probe?.stage ?? "contract_only",
            probeReasonCode: probe?.reasonCode,
            probeSummary: probe?.summary,
            probeInvocations: probe?.invocations ?? [],
            probeConnectAttempted: probe?.connectAttempted,
            probeBootstrapAttempted: probe?.bootstrapAttempted,
            probeLogContainsSkipRefresh: probe?.logContainsSkipRefresh
        )
    }

    private func runEnsureConnectedProbe(
        prefix: String,
        pairingEnv: String,
        discoverOutput: String,
        expectedReasonCode: String
    ) async throws -> XTStaleProfileRepairProbeEvidence {
        let stateDir = try makeTempStateDir(prefix: "xt_stale_profile_\(prefix)")
        defer { try? FileManager.default.removeItem(at: stateDir) }

        try writeFile(stateDir.appendingPathComponent("pairing.env"), pairingEnv)
        try writeFile(
            stateDir.appendingPathComponent("hub.env"),
            """
            export HUB_CLIENT_TOKEN='tok_current'
            """
        )
        let fakeAxhubctl = try writeFakeAxhubctl(
            in: stateDir,
            discoverOutput: discoverOutput
        )

        let report = await HubPairingCoordinator.shared.ensureConnected(
            options: HubRemoteConnectOptions(
                grpcPort: 50051,
                pairingPort: 50052,
                deviceName: "X-Terminal",
                internetHost: "hub.test.invalid",
                inviteToken: "",
                axhubctlPath: fakeAxhubctl.path,
                stateDir: stateDir
            ),
            allowBootstrap: true
        )

        let invocations = readAxhubctlInvocationLog(from: stateDir)
        #expect(report.ok == false)
        #expect(report.reasonCode == expectedReasonCode)
        #expect(report.summary == expectedReasonCode)
        #expect(invocations == ["discover"])

        return XTStaleProfileRepairProbeEvidence(
            stage: "discover",
            reasonCode: report.reasonCode ?? "",
            summary: report.summary,
            invocations: invocations,
            connectAttempted: invocations.contains("connect"),
            bootstrapAttempted: invocations.contains("bootstrap"),
            logContainsSkipRefresh: report.logText.contains("skip refresh")
        )
    }

    private func runDetectPortsProbe(
        pairingEnv: String,
        discoverOutput: String,
        expectedReasonCode: String
    ) async throws -> XTStaleProfileRepairProbeEvidence {
        let stateDir = try makeTempStateDir(prefix: "xt_stale_profile_route_pack")
        defer { try? FileManager.default.removeItem(at: stateDir) }

        try writeFile(stateDir.appendingPathComponent("pairing.env"), pairingEnv)
        try writeFile(
            stateDir.appendingPathComponent("hub.env"),
            """
            export HUB_CLIENT_TOKEN='tok_current'
            """
        )
        let fakeAxhubctl = try writeFakeAxhubctl(
            in: stateDir,
            discoverOutput: discoverOutput
        )

        let result = await HubPairingCoordinator.shared.detectPorts(
            options: HubRemoteConnectOptions(
                grpcPort: 50051,
                pairingPort: 50052,
                deviceName: "X-Terminal",
                internetHost: "hub.test.invalid",
                inviteToken: "",
                axhubctlPath: fakeAxhubctl.path,
                stateDir: stateDir
            ),
            candidates: [50052]
        )

        let invocations = readAxhubctlInvocationLog(from: stateDir)
        #expect(result.ok == false)
        #expect(result.reasonCode == expectedReasonCode)
        #expect(invocations == ["discover"])

        return XTStaleProfileRepairProbeEvidence(
            stage: "port_detect",
            reasonCode: result.reasonCode ?? "",
            summary: result.reasonCode ?? "",
            invocations: invocations,
            connectAttempted: invocations.contains("connect"),
            bootstrapAttempted: invocations.contains("bootstrap"),
            logContainsSkipRefresh: result.logText.contains("skip refresh")
        )
    }

    private func runConnectBoundaryProbe(
        connectOutput: String,
        expectedReasonCode: String
    ) async throws -> XTStaleProfileRepairProbeEvidence {
        let stateDir = try makeTempStateDir(prefix: "xt_stale_profile_connect_boundary")
        defer { try? FileManager.default.removeItem(at: stateDir) }

        try writeFile(
            stateDir.appendingPathComponent("pairing.env"),
            """
            AXHUB_APP_ID='x_terminal'
            AXHUB_DEVICE_NAME='X-Terminal'
            """
        )
        try writeFile(
            stateDir.appendingPathComponent("hub.env"),
            """
            export HUB_CLIENT_TOKEN='tok_current'
            """
        )
        let fakeAxhubctl = try writeFakeAxhubctl(
            in: stateDir,
            discoverOutput: """
            host: hub.test.invalid
            pairing_port: 50052
            grpc_port: 50051
            internet_host: hub.test.invalid
            """,
            connectOutput: connectOutput,
            connectExitCode: 1
        )

        let report = await HubPairingCoordinator.shared.ensureConnected(
            options: HubRemoteConnectOptions(
                grpcPort: 50051,
                pairingPort: 50052,
                deviceName: "X-Terminal",
                internetHost: "hub.test.invalid",
                inviteToken: "",
                axhubctlPath: fakeAxhubctl.path,
                stateDir: stateDir
            ),
            allowBootstrap: true,
            preferredRoute: .stableNamedRemote,
            candidateRoutes: [.stableNamedRemote]
        )

        let invocations = readAxhubctlInvocationLog(from: stateDir)
        #expect(report.ok == false)
        #expect(report.reasonCode == expectedReasonCode)
        #expect(invocations.contains("discover"))
        #expect(invocations.contains("connect"))
        #expect(invocations.contains("bootstrap") == false)
        #expect(report.logText.contains("skip refresh") == true)

        return XTStaleProfileRepairProbeEvidence(
            stage: "connect_failure",
            reasonCode: report.reasonCode ?? "",
            summary: report.summary,
            invocations: invocations,
            connectAttempted: invocations.contains("connect"),
            bootstrapAttempted: invocations.contains("bootstrap"),
            logContainsSkipRefresh: report.logText.contains("skip refresh")
        )
    }

    private func makeTempStateDir(prefix: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(prefix, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeFile(_ url: URL, _ contents: String) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeFakeAxhubctl(
        in directory: URL,
        discoverOutput: String,
        connectOutput: String? = nil,
        connectExitCode: Int = 91
    ) throws -> URL {
        let scriptURL = directory.appendingPathComponent("fake_axhubctl.sh")
        let trimmedOutput = discoverOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConnectOutput = connectOutput?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        try writeFile(
            scriptURL,
            """
            #!/bin/sh
            set -eu
            script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
            log_file="$script_dir/axhubctl_calls.log"
            cmd="${1:-}"
            printf '%s\\n' "$cmd" >> "$log_file"
            case "$cmd" in
              discover)
                cat <<'EOF'
            \(trimmedOutput)
            EOF
                exit 0
                ;;
              connect)
                if [ -n "\(trimmedConnectOutput)" ]; then
                  cat <<'EOF' >&2
            \(trimmedConnectOutput)
            EOF
                  exit \(connectExitCode)
                fi
                echo "connect_should_not_run" >&2
                exit 91
                ;;
              bootstrap)
                echo "bootstrap_should_not_run" >&2
                exit 92
                ;;
              install-client)
                echo "install_client_should_not_run" >&2
                exit 93
                ;;
              *)
                echo "unsupported:$cmd" >&2
                exit 64
                ;;
            esac
            """
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private func readAxhubctlInvocationLog(from directory: URL) -> [String] {
        let logURL = directory.appendingPathComponent("axhubctl_calls.log")
        guard let contents = try? String(contentsOf: logURL, encoding: .utf8) else { return [] }
        return contents
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
            internetHost: "hub.tailnet.example",
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

    private func makePairedRouteSetBuildInput(
        cachedProfile: HubAIClient.CachedRemoteProfile,
        failureCode: String
    ) -> XTPairedRouteSetBuildInput {
        XTPairedRouteSetBuildInput(
            cachedProfile: cachedProfile,
            configuredInternetHost: "",
            configuredHubInstanceID: cachedProfile.hubInstanceID,
            pairingPort: cachedProfile.pairingPort ?? 50052,
            grpcPort: cachedProfile.grpcPort ?? 50051,
            localConnected: false,
            remoteConnected: false,
            remoteRoute: .none,
            linking: false,
            failureCode: failureCode,
            freshPairReconnectSmokeSnapshot: nil,
            remoteShadowReconnectSmokeSnapshot: nil
        )
    }

    private func writeEvidenceJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url)
    }
}

private struct XTStaleProfileRepairProbeEvidence: Codable, Equatable {
    let stage: String
    let reasonCode: String
    let summary: String
    let invocations: [String]
    let connectAttempted: Bool
    let bootstrapAttempted: Bool
    let logContainsSkipRefresh: Bool

    enum CodingKeys: String, CodingKey {
        case stage
        case reasonCode = "reason_code"
        case summary
        case invocations
        case connectAttempted = "connect_attempted"
        case bootstrapAttempted = "bootstrap_attempted"
        case logContainsSkipRefresh = "log_contains_skip_refresh"
    }
}

private struct XTStaleProfileRepairCaseEvidence: Codable, Equatable {
    let failureCode: String
    let mappedIssue: String
    let repairTitle: String
    let repairDetail: String
    let doctorHeadline: String
    let doctorNextStep: String
    let doctorRepairEntry: String
    let pairedRouteReadiness: String
    let pairedRouteReasonCode: String
    let pairedRouteSummaryLine: String
    let stableRemoteHost: String
    let shouldFailClosedOnDiscovery: Bool
    let shouldSkipBootstrapRefreshAfterConnectFailure: Bool
    let probeStage: String
    let probeReasonCode: String?
    let probeSummary: String?
    let probeInvocations: [String]
    let probeConnectAttempted: Bool?
    let probeBootstrapAttempted: Bool?
    let probeLogContainsSkipRefresh: Bool?

    enum CodingKeys: String, CodingKey {
        case failureCode = "failure_code"
        case mappedIssue = "mapped_issue"
        case repairTitle = "repair_title"
        case repairDetail = "repair_detail"
        case doctorHeadline = "doctor_headline"
        case doctorNextStep = "doctor_next_step"
        case doctorRepairEntry = "doctor_repair_entry"
        case pairedRouteReadiness = "paired_route_readiness"
        case pairedRouteReasonCode = "paired_route_reason_code"
        case pairedRouteSummaryLine = "paired_route_summary_line"
        case stableRemoteHost = "stable_remote_host"
        case shouldFailClosedOnDiscovery = "should_fail_closed_on_discovery"
        case shouldSkipBootstrapRefreshAfterConnectFailure = "should_skip_bootstrap_refresh_after_connect_failure"
        case probeStage = "probe_stage"
        case probeReasonCode = "probe_reason_code"
        case probeSummary = "probe_summary"
        case probeInvocations = "probe_invocations"
        case probeConnectAttempted = "probe_connect_attempted"
        case probeBootstrapAttempted = "probe_bootstrap_attempted"
        case probeLogContainsSkipRefresh = "probe_log_contains_skip_refresh"
    }
}

private struct XTStaleProfileRepairCaptureEvidence: Codable, Equatable {
    let schemaVersion: String
    let generatedAt: String
    let status: String
    let discoveryFailClosedReasonCodes: [String]
    let connectRefreshSkipReasonCodes: [String]
    let cases: [XTStaleProfileRepairCaseEvidence]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case status
        case discoveryFailClosedReasonCodes = "discovery_fail_closed_reason_codes"
        case connectRefreshSkipReasonCodes = "connect_refresh_skip_reason_codes"
        case cases
    }
}
