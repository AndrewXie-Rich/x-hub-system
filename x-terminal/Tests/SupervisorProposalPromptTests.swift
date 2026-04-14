import Foundation
import Testing
@testable import XTerminal

private enum SplitAuditFixtureError: Error {
    case invalidJSON
    case missingSchemaVersion
    case unsupportedSchemaVersion(String)
    case malformedEvent
}

private func loadSplitAuditFixtureEvents(
    named fixtureName: String = "split_audit_payload_events.sample.json",
    expectedSchemaVersion: String = "xterminal.split_audit_fixture.v1"
) throws -> [SplitAuditEvent] {
    let testFileURL = URL(fileURLWithPath: #filePath)
    let packageRoot = testFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let fixtureURL = packageRoot.appendingPathComponent("scripts/fixtures/\(fixtureName)")

    let data = try Data(contentsOf: fixtureURL)
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw SplitAuditFixtureError.invalidJSON
    }
    guard let schemaVersion = root["schema_version"] as? String else {
        throw SplitAuditFixtureError.missingSchemaVersion
    }
    guard schemaVersion == expectedSchemaVersion else {
        throw SplitAuditFixtureError.unsupportedSchemaVersion(schemaVersion)
    }
    guard let eventItems = root["events"] as? [[String: Any]] else {
        throw SplitAuditFixtureError.invalidJSON
    }

    return try eventItems.map { item in
        guard let eventTypeRaw = item["event_type"] as? String,
              let eventType = SplitAuditEventType(rawValue: eventTypeRaw),
              let payloadRaw = item["payload"] as? [String: Any] else {
            throw SplitAuditFixtureError.malformedEvent
        }

        var payload: [String: String] = [:]
        payloadRaw.forEach { key, value in
            if let stringValue = value as? String {
                payload[key] = stringValue
            } else if let numberValue = value as? NSNumber {
                payload[key] = numberValue.stringValue
            }
        }

        let splitPlanId: UUID = {
            if let raw = item["split_plan_id"] as? String,
               let uuid = UUID(uuidString: raw) {
                return uuid
            }
            return UUID()
        }()

        let detail = (item["detail"] as? String) ?? "fixture_event"
        return SplitAuditEvent(
            eventType: eventType,
            splitPlanId: splitPlanId,
            detail: detail,
            payload: payload
        )
    }
}

struct SplitProposalEngineTests {

    @MainActor
    @Test
    func buildProposalIncludesDagLaneRiskBudgetAndDoD() throws {
        let rootTask = DecomposedTask(
            description: "Build multi-lane supervisor flow",
            type: .planning,
            complexity: .veryComplex,
            estimatedEffort: 18_000
        )
        let laneOneTask = DecomposedTask(
            description: "Design split strategy",
            type: .design,
            complexity: .moderate,
            estimatedEffort: 3_600
        )
        let laneTwoTask = DecomposedTask(
            description: "Implement execution wiring",
            type: .development,
            complexity: .complex,
            estimatedEffort: 7_200,
            dependencies: [laneOneTask.id]
        )

        let graph = DependencyGraph(tasks: [rootTask, laneOneTask, laneTwoTask])
        let analysis = TaskAnalysis(
            originalDescription: rootTask.description,
            keywords: ["split", "proposal", "lane"],
            verbs: ["设计", "实现"],
            objects: ["supervisor"],
            constraints: ["high quality"],
            type: .planning,
            complexity: .veryComplex,
            estimatedEffort: 18_000,
            requiredSkills: ["planning", "coding"],
            riskLevel: .high,
            suggestedSubtasks: [laneOneTask.description, laneTwoTask.description],
            potentialDependencies: ["design -> implementation"]
        )

        let decomposition = DecompositionResult(
            rootTask: rootTask,
            subtasks: [laneOneTask, laneTwoTask],
            allTasks: [rootTask, laneOneTask, laneTwoTask],
            dependencyGraph: graph,
            analysis: analysis
        )

        let engine = SplitProposalEngine()
        let result = engine.buildProposal(from: decomposition, rootProjectId: UUID(), planVersion: 1)

        #expect(result.proposal.lanes.count == 2)
        #expect(result.validation.hasBlockingIssues == false)

        let laneOne = try #require(result.proposal.lanes.first(where: { $0.laneId == "lane-1" }))
        let laneTwo = try #require(result.proposal.lanes.first(where: { $0.laneId == "lane-2" }))

        #expect(laneOne.dependsOn.isEmpty)
        #expect(laneTwo.dependsOn == ["lane-1"])
        #expect(laneOne.dodChecklist.isEmpty == false)
        #expect(laneTwo.dodChecklist.isEmpty == false)
        #expect(laneOne.verificationContract?.verifyMethod == .artifactConsistencyReview)
        #expect(laneTwo.verificationContract?.verifyMethod == .targetedChecksAndDiffReview)
        #expect(laneTwo.verificationContract?.verificationChecklist.isEmpty == false)
        #expect(result.proposal.complexityScore > 0)
        #expect(result.proposal.tokenBudgetTotal > 0)
    }

    @MainActor
    @Test
    func validateDetectsDagCycle() {
        let laneOne = SplitLaneProposal(
            laneId: "lane-1",
            goal: "lane one",
            dependsOn: ["lane-2"],
            riskTier: .medium,
            budgetClass: .standard,
            createChildProject: false,
            expectedArtifacts: ["artifact-1"],
            dodChecklist: ["done"],
            estimatedEffortMs: 2_000,
            tokenBudget: 2_000,
            sourceTaskId: nil,
            notes: []
        )
        let laneTwo = SplitLaneProposal(
            laneId: "lane-2",
            goal: "lane two",
            dependsOn: ["lane-1"],
            riskTier: .medium,
            budgetClass: .standard,
            createChildProject: false,
            expectedArtifacts: ["artifact-2"],
            dodChecklist: ["done"],
            estimatedEffortMs: 2_000,
            tokenBudget: 2_000,
            sourceTaskId: nil,
            notes: []
        )

        let proposal = SplitProposal(
            splitPlanId: UUID(),
            rootProjectId: UUID(),
            planVersion: 1,
            complexityScore: 60,
            lanes: [laneOne, laneTwo],
            recommendedConcurrency: 2,
            tokenBudgetTotal: 4_000,
            estimatedWallTimeMs: 4_000,
            sourceTaskDescription: "cycle case",
            createdAt: Date()
        )

        let engine = SplitProposalEngine()
        let validation = engine.validate(proposal)

        #expect(validation.hasBlockingIssues)
        #expect(validation.blockingIssues.contains(where: { $0.code == "dag_cycle_detected" }))
    }

    @MainActor
    @Test
    func overrideHardToSoftOnHighRiskAddsWarning() {
        let lane = SplitLaneProposal(
            laneId: "lane-1",
            goal: "high risk release",
            dependsOn: [],
            riskTier: .high,
            budgetClass: .premium,
            createChildProject: true,
            expectedArtifacts: ["release_plan"],
            dodChecklist: ["done"],
            estimatedEffortMs: 5_000,
            tokenBudget: 8_000,
            sourceTaskId: nil,
            notes: []
        )
        let proposal = SplitProposal(
            splitPlanId: UUID(),
            rootProjectId: UUID(),
            planVersion: 1,
            complexityScore: 70,
            lanes: [lane],
            recommendedConcurrency: 1,
            tokenBudgetTotal: 8_000,
            estimatedWallTimeMs: 5_000,
            sourceTaskDescription: "override case",
            createdAt: Date()
        )

        let engine = SplitProposalEngine()
        let result = engine.applyOverrides(
            [
                SplitLaneOverride(
                    laneId: "lane-1",
                    createChildProject: false,
                    note: "force soft",
                    confirmHighRiskHardToSoft: true
                )
            ],
            to: proposal
        )

        #expect(result.proposal.lanes.first?.createChildProject == false)
        #expect(result.validation.issues.contains(where: { $0.code == "high_risk_hard_to_soft_override" }))
        #expect(result.appliedOverrides.count == 1)
        #expect(result.appliedOverrides.first?.before.createChildProject == true)
        #expect(result.appliedOverrides.first?.after.createChildProject == false)
    }

    @MainActor
    @Test
    func overrideHardToSoftOnHighRiskRequiresExplicitConfirmation() {
        let lane = SplitLaneProposal(
            laneId: "lane-1",
            goal: "high risk release",
            dependsOn: [],
            riskTier: .critical,
            budgetClass: .burst,
            createChildProject: true,
            expectedArtifacts: ["release_plan"],
            dodChecklist: ["done"],
            estimatedEffortMs: 7_000,
            tokenBudget: 12_000,
            sourceTaskId: nil,
            notes: []
        )
        let proposal = SplitProposal(
            splitPlanId: UUID(),
            rootProjectId: UUID(),
            planVersion: 1,
            complexityScore: 85,
            lanes: [lane],
            recommendedConcurrency: 1,
            tokenBudgetTotal: 12_000,
            estimatedWallTimeMs: 7_000,
            sourceTaskDescription: "override confirmation case",
            createdAt: Date()
        )

        let engine = SplitProposalEngine()
        let result = engine.applyOverrides(
            [SplitLaneOverride(laneId: "lane-1", createChildProject: false, note: "missing_confirm")],
            to: proposal
        )

        #expect(result.validation.hasBlockingIssues)
        #expect(result.validation.blockingIssues.contains(where: { $0.code == "high_risk_hard_to_soft_confirmation_required" }))
        #expect(result.proposal.lanes.first?.createChildProject == true)
    }

    @MainActor
    @Test
    func overrideRecordsCanReplayDeterministically() {
        let lane = SplitLaneProposal(
            laneId: "lane-1",
            goal: "implementation lane",
            dependsOn: [],
            riskTier: .medium,
            budgetClass: .standard,
            createChildProject: false,
            expectedArtifacts: ["patch"],
            dodChecklist: ["tests_passed"],
            estimatedEffortMs: 3_000,
            tokenBudget: 4_000,
            sourceTaskId: nil,
            notes: []
        )
        let proposal = SplitProposal(
            splitPlanId: UUID(),
            rootProjectId: UUID(),
            planVersion: 1,
            complexityScore: 45,
            lanes: [lane],
            recommendedConcurrency: 1,
            tokenBudgetTotal: 4_000,
            estimatedWallTimeMs: 3_000,
            sourceTaskDescription: "replay case",
            createdAt: Date()
        )

        let engine = SplitProposalEngine()
        let firstPass = engine.applyOverrides(
            [
                SplitLaneOverride(
                    laneId: "lane-1",
                    createChildProject: true,
                    budgetClass: .premium,
                    note: "replay_override"
                )
            ],
            to: proposal,
            reason: "unit_test_override"
        )
        let replayed = engine.replayOverrides(firstPass.appliedOverrides, baseProposal: proposal)

        #expect(firstPass.proposal == replayed.proposal)
        #expect(replayed.validation.hasBlockingIssues == false)
    }
}

struct PromptFactoryTests {

    @MainActor
    @Test
    func compileContractsRejectsLaneMissingDoD() {
        let lane = SplitLaneProposal(
            laneId: "lane-1",
            goal: "deliver feature",
            dependsOn: [],
            riskTier: .medium,
            budgetClass: .standard,
            createChildProject: false,
            expectedArtifacts: ["patch"],
            dodChecklist: [],
            estimatedEffortMs: 1_500,
            tokenBudget: 4_000,
            sourceTaskId: nil,
            notes: []
        )

        let proposal = SplitProposal(
            splitPlanId: UUID(),
            rootProjectId: UUID(),
            planVersion: 1,
            complexityScore: 40,
            lanes: [lane],
            recommendedConcurrency: 1,
            tokenBudgetTotal: 4_000,
            estimatedWallTimeMs: 1_500,
            sourceTaskDescription: "prompt lint case",
            createdAt: Date()
        )

        let factory = PromptFactory()
        let result = factory.compileContracts(for: proposal)

        #expect(result.status == .rejected)
        #expect(result.lintResult.hasBlockingErrors)
        #expect(result.lintResult.blockingIssues.contains(where: { $0.code == "missing_dod" }))
    }

    @MainActor
    @Test
    func lintDetectsMissingRiskRefusalAndRollbackSections() {
        let contract = PromptContract(
            laneId: "lane-1",
            goal: "valid goal",
            boundaries: ["scope only"],
            inputs: ["input-a"],
            outputs: ["output-a"],
            dodChecklist: ["done"],
            riskBoundaries: [],
            rollbackPoints: [],
            refusalSemantics: [],
            compiledPrompt: "prompt",
            tokenBudget: 2_000
        )

        let factory = PromptFactory()
        let issues = factory.lint(contract)
        let codes = Set(issues.map { $0.code })

        #expect(codes.contains("missing_risk_boundary"))
        #expect(codes.contains("missing_prohibitions"))
        #expect(codes.contains("missing_refusal_semantics"))
        #expect(codes.contains("missing_rollback_points"))
    }

    @MainActor
    @Test
    func compileContractsCanLaunchWhenLintPasses() {
        let lane = SplitLaneProposal(
            laneId: "lane-1",
            goal: "implement endpoint",
            dependsOn: [],
            riskTier: .low,
            budgetClass: .compact,
            createChildProject: false,
            expectedArtifacts: ["endpoint_code"],
            dodChecklist: ["tests_or_checks_passed"],
            verificationContract: LaneVerificationContract(
                expectedState: "Endpoint works and targeted checks pass.",
                verifyMethod: .targetedChecksAndDiffReview,
                retryPolicy: .boundedRetryThenHold,
                holdPolicy: .holdOnMismatch,
                evidenceRequired: ["endpoint_code", "targeted_check_result"],
                verificationChecklist: ["expected_state_confirmed", "evidence_attached", "tests_or_checks_passed"]
            ),
            estimatedEffortMs: 2_000,
            tokenBudget: 2_000,
            sourceTaskId: nil,
            notes: []
        )

        let proposal = SplitProposal(
            splitPlanId: UUID(),
            rootProjectId: UUID(),
            planVersion: 1,
            complexityScore: 20,
            lanes: [lane],
            recommendedConcurrency: 1,
            tokenBudgetTotal: 2_000,
            estimatedWallTimeMs: 2_000,
            sourceTaskDescription: "happy path",
            createdAt: Date()
        )

        let factory = PromptFactory()
        let result = factory.compileContracts(for: proposal)

        #expect(result.status == .ready)
        #expect(result.lanePromptCoverageComplete)
        #expect(result.canLaunch)
        #expect(result.contracts.first?.verificationContract?.verifyMethod == .targetedChecksAndDiffReview)
        #expect(result.contracts.first?.compiledPrompt.contains("[Verification Contract]") == true)
        #expect(result.contracts.first?.compiledPrompt.contains("targeted checks + diff review") == true)
    }
}

struct OrchestratorAuditPayloadTests {
    private func assertEnvelope(
        _ event: SplitAuditEvent,
        expectedType: SplitAuditEventType,
        expectedState: SplitProposalFlowState
    ) {
        #expect(event.payload[SplitAuditPayloadKeys.Common.schema] == SplitAuditPayloadContract.schema)
        #expect(event.payload[SplitAuditPayloadKeys.Common.version] == SplitAuditPayloadContract.version)
        #expect(event.payload[SplitAuditPayloadKeys.Common.eventType] == expectedType.rawValue)
        #expect(event.payload[SplitAuditPayloadKeys.Common.state] == expectedState.rawValue)
    }

    @MainActor
    @Test
    func confirmFlowEmitsMachineReadablePayloads() async throws {
        let supervisor = SupervisorModel()
        let orchestrator = supervisor.orchestrator!

        let proposalResult = await orchestrator.proposeSplit(for: "设计并实现一个复杂服务，包含测试与文档交付")
        let splitProposed = try #require(orchestrator.splitAuditTrail.first(where: { $0.eventType == .splitProposed }))
        #expect(splitProposed.payload[SplitAuditPayloadKeys.SplitProposed.laneCount] == "\(proposalResult.proposal.lanes.count)")
        #expect(splitProposed.payload[SplitAuditPayloadKeys.SplitProposed.recommendedConcurrency] == "\(proposalResult.proposal.recommendedConcurrency)")
        assertEnvelope(splitProposed, expectedType: .splitProposed, expectedState: .proposed)

        let decodedSplitProposed = try #require(SplitAuditPayloadDecoder.decode(splitProposed))
        if case .splitProposed(let payload) = decodedSplitProposed {
            #expect(payload.laneCount == proposalResult.proposal.lanes.count)
            #expect(payload.recommendedConcurrency == proposalResult.proposal.recommendedConcurrency)
            #expect(payload.state == .proposed)
        } else {
            Issue.record("Unexpected decoded payload kind for splitProposed event")
        }

        let compilation = try #require(orchestrator.confirmActiveSplitProposal(globalContext: "integration_test"))
        #expect(compilation.status == .ready)

        let promptCompiled = try #require(orchestrator.splitAuditTrail.first(where: { $0.eventType == .promptCompiled }))
        #expect(promptCompiled.payload[SplitAuditPayloadKeys.PromptCompiled.contractCount] == "\(compilation.contracts.count)")
        #expect(promptCompiled.payload[SplitAuditPayloadKeys.PromptCompiled.expectedLaneCount] == "\(compilation.expectedLaneCount)")
        #expect(promptCompiled.payload[SplitAuditPayloadKeys.PromptCompiled.canLaunch] == "1")
        assertEnvelope(promptCompiled, expectedType: .promptCompiled, expectedState: .confirmed)

        let decodedPromptCompiled = try #require(SplitAuditPayloadDecoder.decode(promptCompiled))
        if case .promptCompiled(let payload) = decodedPromptCompiled {
            #expect(payload.contractCount == compilation.contracts.count)
            #expect(payload.expectedLaneCount == compilation.expectedLaneCount)
            #expect(payload.canLaunch)
            #expect(payload.state == .confirmed)
        } else {
            Issue.record("Unexpected decoded payload kind for promptCompiled event")
        }

        let splitConfirmed = try #require(orchestrator.splitAuditTrail.first(where: { $0.eventType == .splitConfirmed }))
        #expect(splitConfirmed.payload[SplitAuditPayloadKeys.SplitConfirmed.userDecision] == "confirm")
        #expect(splitConfirmed.payload[SplitAuditPayloadKeys.Common.state] == SplitProposalFlowState.confirmed.rawValue)
        assertEnvelope(splitConfirmed, expectedType: .splitConfirmed, expectedState: .confirmed)

        let decodedSplitConfirmed = try #require(SplitAuditPayloadDecoder.decode(splitConfirmed))
        if case .splitConfirmed(let payload) = decodedSplitConfirmed {
            #expect(payload.userDecision == "confirm")
            #expect(payload.state == .confirmed)
        } else {
            Issue.record("Unexpected decoded payload kind for splitConfirmed event")
        }
    }

    @MainActor
    @Test
    func confirmFlowLintBlockEmitsPromptRejectedPayload() async throws {
        let supervisor = SupervisorModel()
        let orchestrator = supervisor.orchestrator!

        _ = await orchestrator.proposeSplit(for: " ")
        let compilation = try #require(orchestrator.confirmActiveSplitProposal(globalContext: "lint_block_case"))
        #expect(compilation.status == .rejected)
        #expect(compilation.lintResult.hasBlockingErrors)
        #expect(compilation.lintResult.blockingIssues.contains(where: { $0.code == "missing_goal" }))
        #expect(orchestrator.splitProposalState == .blocked)

        let promptRejected = try #require(orchestrator.splitAuditTrail.last(where: { $0.eventType == .promptRejected }))
        #expect(promptRejected.payload[SplitAuditPayloadKeys.PromptRejected.expectedLaneCount] == "\(compilation.expectedLaneCount)")
        #expect(promptRejected.payload[SplitAuditPayloadKeys.PromptRejected.contractCount] == "\(compilation.contracts.count)")
        assertEnvelope(promptRejected, expectedType: .promptRejected, expectedState: .blocked)

        let decodedPromptRejected = try #require(SplitAuditPayloadDecoder.decode(promptRejected))
        if case .promptRejected(let payload) = decodedPromptRejected {
            #expect(payload.expectedLaneCount == compilation.expectedLaneCount)
            #expect(payload.contractCount == compilation.contracts.count)
            #expect(payload.blockingLintCount >= 1)
            #expect(payload.blockingLintCodes.contains("missing_goal"))
            #expect(payload.state == .blocked)
        } else {
            Issue.record("Unexpected decoded payload kind for promptRejected event")
        }
    }

    @MainActor
    @Test
    func rejectFlowEmitsMachineReadableReasonPayload() async throws {
        let supervisor = SupervisorModel()
        let orchestrator = supervisor.orchestrator!

        _ = await orchestrator.proposeSplit(for: "准备一个拆分提案用于拒绝测试")
        orchestrator.rejectActiveSplitProposal(reason: "user_cancelled_for_test")

        let rejected = try #require(orchestrator.splitAuditTrail.last(where: { $0.eventType == .splitRejected }))
        #expect(rejected.payload[SplitAuditPayloadKeys.SplitRejected.userDecision] == "reject")
        #expect(rejected.payload[SplitAuditPayloadKeys.SplitRejected.reason] == "user_cancelled_for_test")
        #expect(rejected.payload[SplitAuditPayloadKeys.Common.state] == SplitProposalFlowState.rejected.rawValue)
        assertEnvelope(rejected, expectedType: .splitRejected, expectedState: .rejected)

        let decodedRejected = try #require(SplitAuditPayloadDecoder.decode(rejected))
        if case .splitRejected(let payload) = decodedRejected {
            #expect(payload.userDecision == "reject")
            #expect(payload.reason == "user_cancelled_for_test")
            #expect(payload.state == .rejected)
        } else {
            Issue.record("Unexpected decoded payload kind for splitRejected event")
        }
    }

    @MainActor
    @Test
    func overrideFlowEmitsMachineReadableLaneListPayload() async throws {
        let supervisor = SupervisorModel()
        let orchestrator = supervisor.orchestrator!

        let buildResult = await orchestrator.proposeSplit(for: "生成多条 lane 并覆盖模式")
        let laneId = try #require(buildResult.proposal.lanes.first?.laneId)

        _ = orchestrator.overrideActiveSplitProposal(
            [
                SplitLaneOverride(
                    laneId: laneId,
                    createChildProject: false,
                    note: "test_override",
                    confirmHighRiskHardToSoft: true
                )
            ],
            reason: "integration_override_test"
        )

        let overridden = try #require(orchestrator.splitAuditTrail.last(where: { $0.eventType == .splitOverridden }))
        #expect(overridden.payload[SplitAuditPayloadKeys.SplitOverridden.overrideCount] == "1")
        #expect(overridden.payload[SplitAuditPayloadKeys.SplitOverridden.overrideLaneIDs] == laneId)
        #expect(overridden.payload[SplitAuditPayloadKeys.SplitOverridden.reason] == "integration_override_test")
        #expect(overridden.payload[SplitAuditPayloadKeys.SplitOverridden.highRiskHardToSoftConfirmedCount] != nil)
        #expect(overridden.payload[SplitAuditPayloadKeys.SplitOverridden.highRiskHardToSoftConfirmedLaneIDs] != nil)
        #expect(overridden.payload[SplitAuditPayloadKeys.SplitOverridden.isReplay] == "0")
        assertEnvelope(overridden, expectedType: .splitOverridden, expectedState: .overridden)

        let decodedOverridden = try #require(SplitAuditPayloadDecoder.decode(overridden))
        if case .splitOverridden(let payload) = decodedOverridden {
            #expect(payload.overrideCount == 1)
            #expect(payload.overrideLaneIDs == [laneId])
            #expect(payload.reason == "integration_override_test")
            #expect(payload.blockingIssueCount == 0)
            #expect(payload.blockingIssueCodes.isEmpty)
            #expect(payload.highRiskHardToSoftConfirmedCount == payload.highRiskHardToSoftConfirmedLaneIDs.count)
            #expect(payload.isReplay == false)
        } else {
            Issue.record("Unexpected decoded payload kind for splitOverridden event")
        }
    }

    @MainActor
    @Test
    func orchestratorExposesLatestDecodedSplitAuditPayload() async throws {
        let supervisor = SupervisorModel()
        let orchestrator = supervisor.orchestrator!

        _ = await orchestrator.proposeSplit(for: "latest payload helper test")
        orchestrator.rejectActiveSplitProposal(reason: "latest_payload_test")

        let latest = try #require(orchestrator.latestDecodedSplitAuditPayload())
        if case .splitRejected(let payload) = latest {
            #expect(payload.reason == "latest_payload_test")
            #expect(payload.userDecision == "reject")
        } else {
            Issue.record("Unexpected decoded payload kind for latest payload helper")
        }
    }

    @MainActor
    @Test
    func orchestratorExposesLatestDecodedSplitAuditResult() async throws {
        let supervisor = SupervisorModel()
        let orchestrator = supervisor.orchestrator!

        _ = await orchestrator.proposeSplit(for: "latest decode result helper")
        orchestrator.rejectActiveSplitProposal(reason: "latest_result_test")

        let latest = try #require(orchestrator.latestDecodedSplitAuditResult())
        if case .success(let payload) = latest {
            if case .splitRejected(let splitRejected) = payload {
                #expect(splitRejected.reason == "latest_result_test")
                #expect(splitRejected.userDecision == "reject")
            } else {
                Issue.record("Unexpected decoded payload kind for latest result helper")
            }
        } else {
            Issue.record("Expected decodeResult success for latest result helper")
        }
    }

    @MainActor
    @Test
    func latestDecodedSplitAuditResultIsNilWhenNoEvents() {
        let supervisor = SupervisorModel()
        let orchestrator = supervisor.orchestrator!
        #expect(orchestrator.latestDecodedSplitAuditResult() == nil)
    }

    @MainActor
    @Test
    func decoderRejectsIncompatibleEnvelopeButAcceptsLegacyPayload() throws {
        let splitPlanId = UUID()
        let basePayload: [String: String] = [
            SplitAuditPayloadKeys.PromptCompiled.expectedLaneCount: "1",
            SplitAuditPayloadKeys.PromptCompiled.contractCount: "1",
            SplitAuditPayloadKeys.PromptCompiled.coverage: "1.00",
            SplitAuditPayloadKeys.PromptCompiled.canLaunch: "1",
            SplitAuditPayloadKeys.PromptCompiled.lintIssueCount: "0",
            SplitAuditPayloadKeys.Common.state: SplitProposalFlowState.confirmed.rawValue,
            SplitAuditPayloadKeys.Common.schema: SplitAuditPayloadContract.schema,
            SplitAuditPayloadKeys.Common.version: SplitAuditPayloadContract.version,
            SplitAuditPayloadKeys.Common.eventType: SplitAuditEventType.promptCompiled.rawValue
        ]

        var wrongSchemaPayload = basePayload
        wrongSchemaPayload[SplitAuditPayloadKeys.Common.schema] = "xterminal.split_audit_payload.v2"
        let wrongSchemaEvent = SplitAuditEvent(
            eventType: .promptCompiled,
            splitPlanId: splitPlanId,
            detail: "wrong schema",
            payload: wrongSchemaPayload
        )
        #expect(SplitAuditPayloadDecoder.decode(wrongSchemaEvent) == nil)

        var wrongVersionPayload = basePayload
        wrongVersionPayload[SplitAuditPayloadKeys.Common.version] = "2"
        let wrongVersionEvent = SplitAuditEvent(
            eventType: .promptCompiled,
            splitPlanId: splitPlanId,
            detail: "wrong version",
            payload: wrongVersionPayload
        )
        #expect(SplitAuditPayloadDecoder.decode(wrongVersionEvent) == nil)

        var wrongEventTypePayload = basePayload
        wrongEventTypePayload[SplitAuditPayloadKeys.Common.eventType] = SplitAuditEventType.splitConfirmed.rawValue
        let wrongEventTypeEvent = SplitAuditEvent(
            eventType: .promptCompiled,
            splitPlanId: splitPlanId,
            detail: "wrong event type",
            payload: wrongEventTypePayload
        )
        #expect(SplitAuditPayloadDecoder.decode(wrongEventTypeEvent) == nil)

        var legacyPayload = basePayload
        legacyPayload.removeValue(forKey: SplitAuditPayloadKeys.Common.schema)
        legacyPayload.removeValue(forKey: SplitAuditPayloadKeys.Common.version)
        legacyPayload.removeValue(forKey: SplitAuditPayloadKeys.Common.eventType)
        let legacyEvent = SplitAuditEvent(
            eventType: .promptCompiled,
            splitPlanId: splitPlanId,
            detail: "legacy payload",
            payload: legacyPayload
        )
        let decodedLegacy = try #require(SplitAuditPayloadDecoder.decode(legacyEvent))
        if case .promptCompiled(let payload) = decodedLegacy {
            #expect(payload.expectedLaneCount == 1)
            #expect(payload.contractCount == 1)
            #expect(payload.canLaunch)
            #expect(payload.state == .confirmed)
        } else {
            Issue.record("Unexpected decoded payload kind for legacy promptCompiled event")
        }
    }

    @MainActor
    @Test
    func decodeResultReturnsActionableErrorCodes() throws {
        let splitPlanId = UUID()
        let wrongSchemaEvent = SplitAuditEvent(
            eventType: .promptCompiled,
            splitPlanId: splitPlanId,
            detail: "wrong schema",
            payload: [
                SplitAuditPayloadKeys.Common.schema: "xterminal.split_audit_payload.v2",
                SplitAuditPayloadKeys.Common.version: SplitAuditPayloadContract.version,
                SplitAuditPayloadKeys.Common.eventType: SplitAuditEventType.promptCompiled.rawValue,
                SplitAuditPayloadKeys.Common.state: SplitProposalFlowState.confirmed.rawValue,
                SplitAuditPayloadKeys.PromptCompiled.expectedLaneCount: "1",
                SplitAuditPayloadKeys.PromptCompiled.contractCount: "1",
                SplitAuditPayloadKeys.PromptCompiled.coverage: "1.00",
                SplitAuditPayloadKeys.PromptCompiled.canLaunch: "1",
                SplitAuditPayloadKeys.PromptCompiled.lintIssueCount: "0"
            ]
        )

        let wrongSchemaResult = SplitAuditPayloadDecoder.decodeResult(wrongSchemaEvent)
        if case .failure(let error) = wrongSchemaResult {
            #expect(error == .schemaMismatch(expected: SplitAuditPayloadContract.schema, actual: "xterminal.split_audit_payload.v2"))
        } else {
            Issue.record("Expected schema mismatch error for wrongSchemaEvent")
        }

        let badIntegerEvent = SplitAuditEvent(
            eventType: .splitConfirmed,
            splitPlanId: splitPlanId,
            detail: "invalid lane_count",
            payload: [
                SplitAuditPayloadKeys.Common.schema: SplitAuditPayloadContract.schema,
                SplitAuditPayloadKeys.Common.version: SplitAuditPayloadContract.version,
                SplitAuditPayloadKeys.Common.eventType: SplitAuditEventType.splitConfirmed.rawValue,
                SplitAuditPayloadKeys.Common.state: SplitProposalFlowState.confirmed.rawValue,
                SplitAuditPayloadKeys.SplitConfirmed.userDecision: "confirm",
                SplitAuditPayloadKeys.SplitConfirmed.laneCount: "NaN"
            ]
        )

        let badIntegerResult = SplitAuditPayloadDecoder.decodeResult(badIntegerEvent)
        if case .failure(let error) = badIntegerResult {
            #expect(error == .invalidFieldValue(key: SplitAuditPayloadKeys.SplitConfirmed.laneCount, value: "NaN"))
        } else {
            Issue.record("Expected invalid field value error for badIntegerEvent")
        }

        let missingFieldEvent = SplitAuditEvent(
            eventType: .splitRejected,
            splitPlanId: splitPlanId,
            detail: "missing reason",
            payload: [
                SplitAuditPayloadKeys.Common.schema: SplitAuditPayloadContract.schema,
                SplitAuditPayloadKeys.Common.version: SplitAuditPayloadContract.version,
                SplitAuditPayloadKeys.Common.eventType: SplitAuditEventType.splitRejected.rawValue,
                SplitAuditPayloadKeys.Common.state: SplitProposalFlowState.rejected.rawValue,
                SplitAuditPayloadKeys.SplitRejected.userDecision: "reject"
            ]
        )

        let missingFieldResult = SplitAuditPayloadDecoder.decodeResult(missingFieldEvent)
        if case .failure(let error) = missingFieldResult {
            #expect(error == .missingField(SplitAuditPayloadKeys.SplitRejected.reason))
        } else {
            Issue.record("Expected missing field error for missingFieldEvent")
        }
    }

    @MainActor
    @Test
    func decodeAndDecodeResultStayConsistentForFixtureEvents() throws {
        let events = try loadSplitAuditFixtureEvents()
        #expect(events.isEmpty == false)

        for event in events {
            let legacy = SplitAuditPayloadDecoder.decode(event)
            let detailed = SplitAuditPayloadDecoder.decodeResult(event)

            #expect(legacy != nil)
            if case .success(let payload) = detailed {
                #expect(payload == legacy)
            } else {
                Issue.record("Expected decodeResult success for fixture event \(event.eventType.rawValue)")
            }
        }
    }

    @MainActor
    @Test
    func fixtureSampleCoversAllSplitAuditEvents() throws {
        let events = try loadSplitAuditFixtureEvents()
        #expect(events.count == 6)

        let eventTypes = Set(events.map { $0.eventType })
        #expect(eventTypes == Set([
            SplitAuditEventType.splitProposed,
            SplitAuditEventType.promptRejected,
            SplitAuditEventType.promptCompiled,
            SplitAuditEventType.splitConfirmed,
            SplitAuditEventType.splitRejected,
            SplitAuditEventType.splitOverridden
        ]))

        for event in events {
            let expectedStateRaw = try #require(event.payload[SplitAuditPayloadKeys.Common.state])
            let expectedState = try #require(SplitProposalFlowState(rawValue: expectedStateRaw))
            assertEnvelope(event, expectedType: event.eventType, expectedState: expectedState)
            let decoded = try #require(SplitAuditPayloadDecoder.decode(event))
            if event.eventType == .splitOverridden {
                if case .splitOverridden(let payload) = decoded {
                    #expect(payload.isReplay == false)
                    #expect(payload.blockingIssueCount == payload.blockingIssueCodes.count)
                    #expect(payload.highRiskHardToSoftConfirmedCount == payload.highRiskHardToSoftConfirmedLaneIDs.count)
                } else {
                    Issue.record("Expected splitOverridden payload kind for fixture splitOverridden event")
                }
            }
        }
    }

    @MainActor
    @Test
    func invalidFixtureEventsAreRejectedByDecoder() throws {
        let events = try loadSplitAuditFixtureEvents(named: "split_audit_payload_events.invalid.sample.json")
        #expect(events.isEmpty == false)
        for event in events {
            #expect(SplitAuditPayloadDecoder.decode(event) == nil)
        }
    }

    @MainActor
    @Test
    func flowStateTransitionsOverrideConfirmAndResetRemainStable() async throws {
        let supervisor = SupervisorModel()
        let orchestrator = supervisor.orchestrator!

        let proposalResult = await orchestrator.proposeSplit(for: "实现多泳道接口并补齐测试与文档")
        #expect(orchestrator.splitProposalState == .proposed)
        let laneID = try #require(proposalResult.proposal.lanes.first?.laneId)

        _ = orchestrator.overrideActiveSplitProposal(
            [SplitLaneOverride(laneId: laneID, note: "state_sequence_test")],
            reason: "state_sequence_override"
        )
        #expect(orchestrator.splitProposalState == .overridden)

        let compilation = try #require(orchestrator.confirmActiveSplitProposal(globalContext: "state_sequence"))
        #expect(compilation.status == .ready)
        #expect(orchestrator.splitProposalState == .confirmed)

        let auditTypes = orchestrator.splitAuditTrail.map(\.eventType)
        let proposedIndex = try #require(auditTypes.firstIndex(of: .splitProposed))
        let overriddenIndex = try #require(auditTypes.firstIndex(of: .splitOverridden))
        let promptCompiledIndex = try #require(auditTypes.firstIndex(of: .promptCompiled))
        let splitConfirmedIndex = try #require(auditTypes.firstIndex(of: .splitConfirmed))

        #expect(proposedIndex < overriddenIndex)
        #expect(overriddenIndex < promptCompiledIndex)
        #expect(promptCompiledIndex < splitConfirmedIndex)

        orchestrator.clearSplitProposalFlow()
        #expect(orchestrator.splitProposalState == .idle)
        #expect(orchestrator.activeSplitProposal == nil)
        #expect(orchestrator.promptCompilationResult == nil)
        #expect(orchestrator.splitProposalValidation == nil)
    }

    @MainActor
    @Test
    func orchestratorSupportsOverrideReplayFromBaseline() async throws {
        let supervisor = SupervisorModel()
        let orchestrator = supervisor.orchestrator!

        let proposalResult = await orchestrator.proposeSplit(for: "设计实现测试文档四阶段并行执行")
        let laneID = try #require(proposalResult.proposal.lanes.first?.laneId)
        _ = orchestrator.overrideActiveSplitProposal(
            [
                SplitLaneOverride(
                    laneId: laneID,
                    createChildProject: false,
                    note: "replay_check",
                    confirmHighRiskHardToSoft: true
                )
            ],
            reason: "replay_consistency_test"
        )

        #expect(orchestrator.splitOverrideHistory.isEmpty == false)
        #expect(orchestrator.splitOverrideReplayConsistent == true)

        let replayed = try #require(orchestrator.replayActiveSplitProposalOverrides())
        #expect(replayed.validation.hasBlockingIssues == false)
        #expect(replayed.proposal == orchestrator.activeSplitProposal)
        #expect(orchestrator.splitProposalState == .overridden)

        let replayEvent = try #require(orchestrator.splitAuditTrail.last(where: { $0.eventType == .splitOverridden }))
        let replayPayload = try #require(SplitAuditPayloadDecoder.decode(replayEvent))
        if case .splitOverridden(let payload) = replayPayload {
            #expect(payload.isReplay)
            #expect(payload.reason == "override_replay")
            #expect(payload.highRiskHardToSoftConfirmedCount == payload.highRiskHardToSoftConfirmedLaneIDs.count)
        } else {
            Issue.record("Unexpected payload type for replay splitOverridden event")
        }
    }
}
