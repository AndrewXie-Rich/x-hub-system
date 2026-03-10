import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorMemoryUXAdapterTests {
    private let projectID = UUID(uuidString: "12345678-1234-1234-1234-1234567890ab")!
    private let sessionID = UUID(uuidString: "87654321-4321-4321-4321-ba0987654321")!

    @Test
    func sessionContinuityBuildsHubSourcedCapsuleAndFailsClosedWhenStale() {
        let selector = XTMemoryChannelSelectorEngine().select(
            projectID: projectID,
            sessionID: sessionID,
            requestedChannels: [.project],
            reason: .execution,
            totalBudgetTokens: 1200,
            auditRef: "audit-session"
        )
        let adapter = XTMemorySessionContinuityAdapter()
        let evidence = adapter.buildEvidence(
            projectID: projectID,
            sessionID: sessionID,
            latestUser: "resume intake acceptance memory bus",
            memoryContext: stubMemoryContext(),
            selector: selector.selector,
            projectRoot: URL(fileURLWithPath: "/tmp/demo-project"),
            now: Date(timeIntervalSince1970: 1_772_100_000),
            auditRef: "audit-session"
        )

        #expect(evidence.capsule.sourceOfTruth == "hub")
        #expect(evidence.duplicateMemoryStoreCount == 0)
        #expect(evidence.validationPass)
        #expect(evidence.relevanceScore >= 0.90)
        #expect(evidence.cacheEntry.ttlSeconds == 3600)
        #expect(evidence.capsule.workingSetRefs.count == 1)

        let stale = adapter.validateCapsule(
            evidence.capsule,
            expectedProjectID: projectID.uuidString.lowercased(),
            expectedSessionID: sessionID.uuidString.lowercased(),
            now: Date(timeIntervalSince1970: 1_772_104_001),
            maxAgeSeconds: 3600
        )
        #expect(stale.pass == false)
        #expect(stale.denyCode == "capsule_stale")
    }

    @Test
    func channelSplitterAndInjectionGuardEnforceScopeAndRemoteExportPolicy() {
        let vertical = XTMemoryUXAdapterEngine().buildVerticalSlice(verticalSliceInput(remotePromptRequested: true, secretSignals: ["private token", "credential"]))

        #expect(vertical.channelSplitter.selector.requestedChannels == [.project, .user])
        #expect(vertical.channelSplitter.selector.crossScopePolicy == .requireExplicitGrant)
        #expect(vertical.channelSplitter.selector.budgetSplit.projectTokens == 1020)
        #expect(vertical.channelSplitter.selector.budgetSplit.userTokens == 180)
        #expect(vertical.injectionGuard.policy.remoteExportAllowed == false)
        #expect(vertical.injectionGuard.policy.decision == .deny)
        #expect(vertical.injectionGuard.policy.promptBundleClass == .localOnly)
        #expect(vertical.injectionGuard.remoteSecretExportViolation == 0)
    }

    @Test
    func memoryOpsConsoleRoutesAllMutationsThroughHubAudit() {
        let evidence = XTMemoryOperationsConsole().buildDefaultEvidence(
            projectID: projectID,
            sessionID: sessionID,
            targetRef: "memory://longterm/project/\(projectID.uuidString.lowercased())/doc-1",
            auditRef: "audit-ops"
        )

        #expect(evidence.plans.count == 6)
        #expect(evidence.plans.allSatisfy { $0.allowed })
        #expect(evidence.plans.allSatisfy { $0.route == .hubOnly })
        #expect(evidence.plans.allSatisfy { $0.requiresHubAudit })
        #expect(evidence.plans.allSatisfy { $0.localMutationAllowed == false })
        #expect(evidence.rollbackAuditCompleteness == 1.0)
        #expect(evidence.memoryOpsRoundtripP95Ms <= 2000)
    }

    @Test
    func supervisorMemoryBusBuildsScopeSafeRefOnlyEvents() {
        let vertical = XTMemoryUXAdapterEngine().buildVerticalSlice(verticalSliceInput(remotePromptRequested: false, secretSignals: []))
        let eventTypes = Set(vertical.supervisorMemoryBus.events.map(\.eventType))

        #expect(eventTypes.contains(.intake))
        #expect(eventTypes.contains(.bootstrap))
        #expect(eventTypes.contains(.blockedDiagnosis))
        #expect(eventTypes.contains(.resume))
        #expect(eventTypes.contains(.acceptance))
        #expect(vertical.supervisorMemoryBus.events.allSatisfy { $0.scopeSafe })
        #expect(vertical.supervisorMemoryBus.events.allSatisfy { !$0.capsuleRef.contains("[MEMORY_V1]") })
        #expect(vertical.supervisorMemoryBus.broadcastFullContextCount == 0)
        #expect(vertical.supervisorMemoryBus.resumeSuccessRate >= 0.95)
        #expect(vertical.overall.gateVector.contains("XT-MEM-G5:candidate_pass"))
    }

    @Test
    func runtimeCaptureWritesXTW323EvidenceFilesWhenRequested() throws {
        guard let captureDir = ProcessInfo.processInfo.environment["XT_W3_23_CAPTURE_DIR"], !captureDir.isEmpty else {
            return
        }
        let vertical = XTMemoryUXAdapterEngine().buildVerticalSlice(verticalSliceInput(remotePromptRequested: true, secretSignals: ["private token"]))
        let base = URL(fileURLWithPath: captureDir)

        try writeJSON(vertical.sessionContinuity, to: base.appendingPathComponent("xt_w3_23_a_session_continuity_evidence.v1.json"))
        try writeJSON(vertical.channelSplitter, to: base.appendingPathComponent("xt_w3_23_b_channel_splitter_evidence.v1.json"))
        try writeJSON(vertical.memoryOpsConsole, to: base.appendingPathComponent("xt_w3_23_c_memory_ops_console_evidence.v1.json"))
        try writeJSON(vertical.injectionGuard, to: base.appendingPathComponent("xt_w3_23_d_injection_guard_evidence.v1.json"))
        try writeJSON(vertical.supervisorMemoryBus, to: base.appendingPathComponent("xt_w3_23_e_supervisor_memory_bus_evidence.v1.json"))
        try writeJSON(vertical.overall, to: base.appendingPathComponent("xt_w3_23_memory_ux_adapter.v1.json"))

        #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent("xt_w3_23_memory_ux_adapter.v1.json").path))
        #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent("xt_w3_23_e_supervisor_memory_bus_evidence.v1.json").path))
    }

    private func verticalSliceInput(remotePromptRequested: Bool, secretSignals: [String]) -> XTMemoryVerticalSliceInput {
        let intakeWorkflow = SupervisorIntakeAcceptanceEngine().buildProjectIntakeWorkflow(
            projectID: projectID,
            documents: intakeDocuments(),
            splitProposal: splitProposal(),
            now: Date(timeIntervalSince1970: 1_772_100_000)
        )
        let acceptanceWorkflow = SupervisorIntakeAcceptanceEngine().buildAcceptanceWorkflow(
            input: AcceptanceAggregationInput(
                projectID: projectID.uuidString.lowercased(),
                completedTasks: ["XT-W3-21", "XT-W3-22"],
                gateReadings: [
                    AcceptanceGateReading(gateID: "XT-MP-G4", status: .pass),
                    AcceptanceGateReading(gateID: "XT-MP-G5", status: .pass)
                ],
                riskSummary: [
                    AcceptanceRisk(riskID: "risk-1", severity: .low, mitigation: "memory refs remain scoped to the same project")
                ],
                rollbackPoints: [
                    AcceptanceRollbackPoint(component: "memory-console", rollbackRef: "board://rollback/memory-console-v1")
                ],
                evidenceRefs: [
                    "build/reports/xt_w3_21_project_intake_manifest.v1.json",
                    "build/reports/xt_w3_22_acceptance_pack.v1.json"
                ],
                userSummaryRef: "board://delivery/summary/xt-w3-23",
                auditRef: "audit-acceptance"
            ),
            participationMode: .guidedTouch,
            now: Date(timeIntervalSince1970: 1_772_100_010)
        )
        return XTMemoryVerticalSliceInput(
            projectID: projectID,
            sessionID: sessionID,
            projectRoot: URL(fileURLWithPath: "/tmp/demo-project"),
            displayName: "XT Memory Demo",
            latestUser: "resume intake acceptance memory bus",
            requestedChannels: [.project, .user],
            reason: .delivery,
            totalBudgetTokens: 1200,
            remotePromptRequested: remotePromptRequested,
            secretSignals: secretSignals,
            memoryContext: stubMemoryContext(),
            intakeWorkflow: intakeWorkflow,
            acceptanceWorkflow: acceptanceWorkflow,
            blockedDeltaRefs: ["build/reports/xt_w3_23_blocked_diag_delta.v1.json"],
            additionalEvidenceRefs: [
                "build/reports/xt_w3_23_hub_dependency_readiness.v1.json",
                "build/reports/hub_l5_xt_w3_dependency_delta_3line.v1.json"
            ],
            now: Date(timeIntervalSince1970: 1_772_100_020)
        )
    }

    private func intakeDocuments() -> [SupervisorIntakeSourceDocument] {
        [
            SupervisorIntakeSourceDocument(
                ref: "docs/xt-memory.md",
                kind: .markdown,
                contents: """
                project_goal: Productize XT memory UX adapter on top of Hub truth source
                touch_policy: critical_touch
                innovation_level: L2
                suggestion_governance: hybrid
                risk_level: medium
                requires_user_authorization: true
                acceptance_mode: release_candidate
                token_budget_tier: balanced
                paid_ai_allowed: true

                ## in_scope
                - session continuity capsule
                - channel splitter
                - memory bus

                ## out_of_scope
                - second canonical store
                - full text memory broadcast

                ## constraints
                - fail closed on stale capsule
                - hub remains source of truth

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
            splitPlanId: UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000001")!,
            rootProjectId: projectID,
            planVersion: 1,
            complexityScore: 0.58,
            lanes: [
                SplitLaneProposal(
                    laneId: "lane-memory-adapter",
                    goal: "Build session continuity capsule",
                    dependsOn: [],
                    riskTier: .medium,
                    budgetClass: .standard,
                    createChildProject: false,
                    expectedArtifacts: ["build/reports/xt_w3_23_a_session_continuity_evidence.v1.json"],
                    dodChecklist: ["capsule_ready", "scope_safe", "rollback_ready"],
                    estimatedEffortMs: 1200,
                    tokenBudget: 2200,
                    sourceTaskId: nil,
                    notes: ["adapter"]
                ),
                SplitLaneProposal(
                    laneId: "lane-memory-bus",
                    goal: "Emit supervisor memory bus refs",
                    dependsOn: ["lane-memory-adapter"],
                    riskTier: .high,
                    budgetClass: .premium,
                    createChildProject: true,
                    expectedArtifacts: ["build/reports/xt_w3_23_e_supervisor_memory_bus_evidence.v1.json"],
                    dodChecklist: ["scope_safe_refs_only", "resume_ready", "acceptance_ready"],
                    estimatedEffortMs: 1500,
                    tokenBudget: 2600,
                    sourceTaskId: nil,
                    notes: ["memory-bus"]
                )
            ],
            recommendedConcurrency: 1,
            tokenBudgetTotal: 4800,
            estimatedWallTimeMs: 2600,
            sourceTaskDescription: "XT-W3-23 memory UX adapter",
            createdAt: Date(timeIntervalSince1970: 1_772_100_000)
        )
    }

    private func stubMemoryContext() -> HubIPCClient.MemoryContextResponsePayload {
        HubIPCClient.MemoryContextResponsePayload(
            text: """
            [MEMORY_V1]
            [L0_CONSTITUTION]
            minimal exposure and hub truth source
            [/L0_CONSTITUTION]

            [L1_CANONICAL]
            intake acceptance memory bus remains scoped to the current project
            review writeback rollback must route through hub audit
            [/L1_CANONICAL]

            [L2_OBSERVATIONS]
            longterm outline references only, no full document injection
            [/L2_OBSERVATIONS]

            [L3_WORKING_SET]
            resume intake acceptance memory bus using the latest hub capsule
            continue with scope-safe refs and evidence complete delivery summary
            [/L3_WORKING_SET]

            [L4_RAW_EVIDENCE]
            build/reports/xt_w3_23_hub_dependency_readiness.v1.json
            latest_user:
            resume intake acceptance memory bus
            [/L4_RAW_EVIDENCE]
            [/MEMORY_V1]
            """,
            source: "hub_memory_snapshot",
            budgetTotalTokens: 1200,
            usedTotalTokens: 880,
            layerUsage: [
                HubIPCClient.MemoryContextLayerUsage(layer: "l1_canonical", usedTokens: 220, budgetTokens: 300),
                HubIPCClient.MemoryContextLayerUsage(layer: "l3_working_set", usedTokens: 260, budgetTokens: 400)
            ],
            truncatedLayers: [],
            redactedItems: 0,
            privateDrops: 0
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
