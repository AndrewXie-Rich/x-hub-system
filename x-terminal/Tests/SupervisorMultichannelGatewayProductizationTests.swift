import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorMultichannelGatewayProductizationTests {
    private let projectID = UUID(uuidString: "12345678-1234-1234-1234-1234567890ab")!

    @Test
    func gatewayRegistryFreezesHubFirstManifestAndDeniesUnsupportedChannels() {
        let vertical = XTMultiChannelGatewayProductizationEngine().buildVerticalSlice(
            verticalSliceInput(requestedChannels: [.telegram, .slack, .feishu, .discord])
        )

        #expect(vertical.registry.gatewayManifest.schemaVersion == "xt.channel_gateway_manifest.v1")
        #expect(vertical.registry.gatewayManifest.sourceOfTruth == "hub")
        #expect(vertical.registry.gatewayManifest.enabledChannels == [.telegram, .slack, .feishu])
        #expect(vertical.registry.gatewayManifest.defaultTransportMode == .streaming)
        #expect(vertical.registry.gatewayManifestSchemaCoverage == 1.0)
        #expect(vertical.registry.deniedUnsupportedChannels == [.discord])
        #expect(vertical.registry.unsupportedChannelSilentFallback == 0)
        #expect(vertical.overall.gateVector.contains("XT-CHAN-G0:candidate_pass"))
    }

    @Test
    func firstWaveConnectorsKeepSessionScopeSeparatedAcrossChannels() {
        let vertical = XTMultiChannelGatewayProductizationEngine().buildVerticalSlice(verticalSliceInput())
        let projections = vertical.firstWaveConnectors.sessionProjections

        #expect(vertical.firstWaveConnectors.firstWaveChannelCoverage == "3/3")
        #expect(vertical.firstWaveConnectors.crossChannelSessionLeak == 0)
        #expect(vertical.firstWaveConnectors.channelDeliverySuccessRate >= 0.98)
        #expect(Set(projections.map(\.channelChatID)).count == 3)
        #expect(Set(projections.map(\.hubSessionID)).count == 3)
        #expect(projections.allSatisfy { $0.crossChannelResumeAllowed == false })
        #expect(vertical.firstWaveConnectors.channels.allSatisfy { $0.replayGuardEnabled && $0.signatureVerificationRequired })
    }

    @Test
    func streamingUxSanitizesVisibleLayersAndFallsBackOnDeliveryFailure() throws {
        let vertical = XTMultiChannelGatewayProductizationEngine().buildVerticalSlice(
            verticalSliceInput(forcedStreamingFailureChannels: [.telegram])
        )

        let telegram = try #require(vertical.streamingOutput.channels.first { $0.channel == .telegram })
        #expect(telegram.fallbackEngaged)
        #expect(telegram.finalDelivered)
        #expect(telegram.frames.contains { $0.layer == .progressHint && $0.delivered })
        #expect(telegram.frames.contains { $0.layer == .toolHint && $0.delivered })
        #expect(telegram.frames.contains { $0.layer == .conciseRationale && !$0.delivered && $0.redacted })
        #expect(vertical.streamingOutput.streamingFirstUpdateP95Ms <= 1500)
        #expect(vertical.streamingOutput.finalMessageLoss == 0)
        #expect(vertical.streamingOutput.rawCotLeakCount == 0)
        #expect(vertical.streamingOutput.secretLeakCount == 0)
        #expect(vertical.overall.gateVector.contains("XT-CHAN-G3:candidate_pass"))
    }

    @Test
    func operatorConsoleBootstrapAndBoundaryStayAuditableAndFailClosed() {
        let vertical = XTMultiChannelGatewayProductizationEngine().buildVerticalSlice(
            verticalSliceInput(remoteExportRequested: true)
        )

        #expect(vertical.operatorConsole.consoleState.channels.count == 3)
        #expect(vertical.operatorConsole.consoleState.channels.contains { $0.channel == .slack && $0.status == .degraded })
        #expect(vertical.operatorConsole.operatorStatusCommandSuccessRate == 1.0)
        #expect(vertical.operatorConsole.restartRecoverySuccessRate >= 0.95)
        #expect(vertical.operatorConsole.runtimeCommands.allSatisfy { !$0.rollbackRef.isEmpty })

        #expect(vertical.onboardBootstrap.variants.count == 3)
        #expect(vertical.onboardBootstrap.bootstrapMissingRequiredEnv == 0)
        #expect(vertical.onboardBootstrap.onboardToFirstMessageP95Ms <= 180_000)
        #expect(vertical.onboardBootstrap.rollbackReady)
        #expect(vertical.onboardBootstrap.bundles.allSatisfy { $0.generatedFiles.contains("AGENTS.md") })

        #expect(vertical.boundary.policy.hubIsTruthSource)
        #expect(vertical.boundary.policy.requiresGrantForSideEffects)
        #expect(vertical.boundary.policy.remoteExportSecretMode == .deny)
        #expect(vertical.boundary.policy.decision == .downgradeToLocal)
        #expect(vertical.boundary.ingressChecks.allSatisfy { $0.secretRefOnly && $0.sideEffectsDeniedWithoutGrant })
        #expect(vertical.boundary.channelSecretExposure == 0)
        #expect(vertical.boundary.unauthorizedChannelSideEffect == 0)
        #expect(vertical.overall.gateVector.contains("XT-CHAN-G4:candidate_pass"))
        #expect(vertical.overall.gateVector.contains("XT-CHAN-G5:candidate_pass"))
        #expect(vertical.overall.gateVector.contains("XT-MEM-G2:candidate_pass"))
    }

    @Test
    func runtimeCaptureWritesXTW324EvidenceFilesWhenRequested() throws {
        guard let captureDir = ProcessInfo.processInfo.environment["XT_W3_24_CAPTURE_DIR"], !captureDir.isEmpty else {
            return
        }

        let vertical = XTMultiChannelGatewayProductizationEngine().buildVerticalSlice(verticalSliceInput())
        let base = URL(fileURLWithPath: captureDir)

        try writeJSON(vertical.registry, to: base.appendingPathComponent("xt_w3_24_a_channel_gateway_registry_evidence.v1.json"))
        try writeJSON(vertical.firstWaveConnectors, to: base.appendingPathComponent("xt_w3_24_b_first_wave_channels_evidence.v1.json"))
        try writeJSON(vertical.streamingOutput, to: base.appendingPathComponent("xt_w3_24_c_streaming_output_evidence.v1.json"))
        try writeJSON(vertical.operatorConsole, to: base.appendingPathComponent("xt_w3_24_d_operator_console_evidence.v1.json"))
        try writeJSON(vertical.onboardBootstrap, to: base.appendingPathComponent("xt_w3_24_e_onboard_bootstrap_evidence.v1.json"))
        try writeJSON(vertical.boundary, to: base.appendingPathComponent("xt_w3_24_f_channel_hub_boundary_evidence.v1.json"))
        try writeJSON(vertical.overall, to: base.appendingPathComponent("xt_w3_24_multichannel_gateway_productization.v1.json"))

        #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent("xt_w3_24_multichannel_gateway_productization.v1.json").path))
    }

    private func verticalSliceInput(
        requestedChannels: [XTGatewayChannel] = [.telegram, .slack, .feishu],
        remoteExportRequested: Bool = false,
        forcedStreamingFailureChannels: [XTGatewayChannel] = []
    ) -> XTChannelGatewayVerticalSliceInput {
        let intakeWorkflow = SupervisorIntakeAcceptanceEngine().buildProjectIntakeWorkflow(
            projectID: projectID,
            documents: intakeDocuments(),
            splitProposal: splitProposal(),
            now: Date(timeIntervalSince1970: 1_772_100_000)
        )
        let acceptanceWorkflow = SupervisorIntakeAcceptanceEngine().buildAcceptanceWorkflow(
            input: AcceptanceAggregationInput(
                projectID: projectID.uuidString.lowercased(),
                completedTasks: ["XT-W3-21", "XT-W3-22", "XT-W3-23"],
                gateReadings: [
                    AcceptanceGateReading(gateID: "XT-MP-G4", status: .pass),
                    AcceptanceGateReading(gateID: "XT-MP-G5", status: .pass),
                    AcceptanceGateReading(gateID: "XT-MEM-G2", status: .pass)
                ],
                riskSummary: [
                    AcceptanceRisk(riskID: "risk-chan-1", severity: .low, mitigation: "channel sessions remain scope-bound and Hub-first")
                ],
                rollbackPoints: [
                    AcceptanceRollbackPoint(component: "channel-gateway", rollbackRef: "board://rollback/channel-gateway-v1")
                ],
                evidenceRefs: [
                    "build/reports/xt_w3_21_project_intake_manifest.v1.json",
                    "build/reports/xt_w3_22_acceptance_pack.v1.json",
                    "build/reports/xt_w3_23_memory_ux_adapter.v1.json"
                ],
                userSummaryRef: "board://delivery/summary/xt-w3-24",
                auditRef: "audit-xt-w3-24"
            ),
            participationMode: .guidedTouch,
            now: Date(timeIntervalSince1970: 1_772_100_010)
        )
        return XTChannelGatewayVerticalSliceInput(
            projectID: projectID,
            gatewayID: "xt-gateway-1",
            requestedChannels: requestedChannels,
            defaultTransportMode: .streaming,
            operatorConsoleRef: "board://xt/channel-console/demo-project",
            logTailRef: "board://xt/logs/channel-gateway",
            memoryCapsuleRef: "build/reports/xt_memory_capsule_12345678.v1.json",
            installModes: [.pip, .pkg, .source],
            intakeWorkflow: intakeWorkflow,
            acceptanceWorkflow: acceptanceWorkflow,
            remoteExportRequested: remoteExportRequested,
            forcedStreamingFailureChannels: forcedStreamingFailureChannels,
            additionalEvidenceRefs: [
                "build/reports/hub_l5_xt_w3_dependency_delta_3line.v1.json",
                "build/reports/xt_w3_23_hub_dependency_readiness.v1.json",
                "build/reports/xt_w3_24_hub_dependency_readiness.v1.json",
                "build/reports/xt_w3_23_memory_ux_adapter.v1.json"
            ],
            now: Date(timeIntervalSince1970: 1_772_100_020)
        )
    }

    private func intakeDocuments() -> [SupervisorIntakeSourceDocument] {
        [
            SupervisorIntakeSourceDocument(
                ref: "docs/xt-gateway.md",
                kind: .markdown,
                contents: """
                project_goal: Productize XT multichannel gateway on top of Hub connectors
                touch_policy: critical_touch
                innovation_level: L2
                suggestion_governance: hybrid
                risk_level: medium
                requires_user_authorization: true
                acceptance_mode: release_candidate
                token_budget_tier: balanced
                paid_ai_allowed: true

                ## in_scope
                - channel gateway registry
                - first-wave connectors
                - streaming output
                - operator console
                - onboarding bootstrap
                - channel-hub boundary

                ## out_of_scope
                - second connector backend
                - local longterm memory
                - raw chain-of-thought forwarding

                ## constraints
                - hub remains source of truth
                - all side effects require hub grant
                - secret refs stay out of prompt bundles

                ## acceptance_targets
                - gate_green
                - rollback_ready
                - evidence_complete
                """
            )
        ]
    }

    private func splitProposal() -> SplitProposal {
        SplitProposal(
            splitPlanId: UUID(uuidString: "bbbbbbbb-0000-0000-0000-000000000024")!,
            rootProjectId: projectID,
            planVersion: 1,
            complexityScore: 0.62,
            lanes: [
                SplitLaneProposal(
                    laneId: "lane-gateway-registry",
                    goal: "Freeze channel gateway manifest and registry",
                    dependsOn: [],
                    riskTier: .medium,
                    budgetClass: .standard,
                    createChildProject: false,
                    expectedArtifacts: ["build/reports/xt_w3_24_a_channel_gateway_registry_evidence.v1.json"],
                    dodChecklist: ["manifest_ready", "schema_frozen", "rollback_ready"],
                    estimatedEffortMs: 1400,
                    tokenBudget: 2600,
                    sourceTaskId: nil,
                    notes: ["gateway"]
                ),
                SplitLaneProposal(
                    laneId: "lane-channel-ops",
                    goal: "Deliver streaming, operator console, and bootstrap",
                    dependsOn: ["lane-gateway-registry"],
                    riskTier: .high,
                    budgetClass: .premium,
                    createChildProject: true,
                    expectedArtifacts: [
                        "build/reports/xt_w3_24_c_streaming_output_evidence.v1.json",
                        "build/reports/xt_w3_24_d_operator_console_evidence.v1.json",
                        "build/reports/xt_w3_24_e_onboard_bootstrap_evidence.v1.json"
                    ],
                    dodChecklist: ["stream_safe", "ops_audited", "smoke_ready"],
                    estimatedEffortMs: 2200,
                    tokenBudget: 3200,
                    sourceTaskId: nil,
                    notes: ["gateway-ops"]
                )
            ],
            recommendedConcurrency: 1,
            tokenBudgetTotal: 5800,
            estimatedWallTimeMs: 3600,
            sourceTaskDescription: "XT-W3-24 multichannel gateway productization",
            createdAt: Date(timeIntervalSince1970: 1_772_100_000)
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
}
