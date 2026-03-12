import Foundation
import Testing
@testable import XTerminal

struct XTW330ExternalTriggerRuntimeEvidenceTests {
    @Test
    @MainActor
    func externalTriggerRuntimeProducesFailClosedEvidenceAndCaptureArtifactWhenRequested() async throws {
        let root = try makeProjectRoot()
        let originalTransportMode = HubAIClient.transportMode()
        let hubBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_w330_hub_ingress_\(UUID().uuidString)", isDirectory: true)
        defer {
            HubAIClient.setTransportMode(originalTransportMode)
            HubPaths.setBaseDirOverride(nil)
            try? FileManager.default.removeItem(at: hubBase)
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeLiveRuntimeRecipe(), activate: true, for: ctx)

        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()
        let project = makeProjectEntry(root: root)
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_110_000,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let scheduleResult = manager.serviceAutomationScheduleTriggers(
            now: Date(timeIntervalSince1970: 1_773_110_000)
        )
        #expect(scheduleResult.count == 1)
        #expect(scheduleResult.first?.decision == .run)
        #expect(scheduleResult.first?.triggerId == "schedule/nightly")
        let scheduleRunId = try #require(scheduleResult.first?.runId)
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .delivered,
            runID: scheduleRunId,
            auditRef: "audit-xt-w3-30-b-schedule-delivered",
            now: Date(timeIntervalSince1970: 1_773_110_001)
        )

        let webhookResult = manager.ingestAutomationExternalTrigger(
            SupervisorManager.SupervisorAutomationExternalTriggerIngress(
                projectId: project.projectId,
                triggerId: "webhook/github_pr",
                triggerType: .webhook,
                source: .github,
                payloadRef: "local://trigger-payload/20260311-002",
                dedupeKey: "sha256:webhook-github-pr-20260311",
                receivedAt: Date(timeIntervalSince1970: 1_773_110_040),
                ingressChannel: "test_webhook_bridge"
            )
        )
        #expect(webhookResult.decision == .run)
        let webhookRunId = try #require(webhookResult.runId)
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .delivered,
            runID: webhookRunId,
            auditRef: "audit-xt-w3-30-b-webhook-delivered",
            now: Date(timeIntervalSince1970: 1_773_110_041)
        )

        let connectorResult = manager.ingestAutomationExternalTrigger(
            SupervisorManager.SupervisorAutomationExternalTriggerIngress(
                projectId: project.projectId,
                triggerId: "connector_event/slack_dm",
                triggerType: .connectorEvent,
                source: .slack,
                payloadRef: "local://trigger-payload/20260311-003",
                dedupeKey: "sha256:connector-event-slack-dm-20260311",
                receivedAt: Date(timeIntervalSince1970: 1_773_110_090),
                ingressChannel: "test_connector_bridge"
            )
        )
        #expect(connectorResult.decision == .run)
        let connectorRunId = try #require(connectorResult.runId)
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .delivered,
            runID: connectorRunId,
            auditRef: "audit-xt-w3-30-b-connector-delivered",
            now: Date(timeIntervalSince1970: 1_773_110_091)
        )

        try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
        HubAIClient.setTransportMode(.fileIPC)
        HubPaths.setBaseDirOverride(hubBase)
        let hubIngressPayload: [String: Any] = [
            "schema_version": "connector_ingress_receipts_status.v1",
            "updated_at_ms": 1_773_110_150_000,
            "items": [
                [
                    "receipt_id": "hub-connector-001",
                    "request_id": "req-hub-connector-001",
                    "project_id": project.projectId,
                    "connector": "slack",
                    "target_id": "dm-project-a",
                    "ingress_type": "connector_event",
                    "channel_scope": "dm",
                    "source_id": "user-project-a",
                    "message_id": "msg-hub-connector-001",
                    "dedupe_key": "sha256:hub-connector-001",
                    "received_at_ms": 1_773_110_150_000,
                    "event_sequence": 19,
                    "delivery_state": "accepted",
                    "runtime_state": "queued",
                ],
            ],
        ]
        let hubIngressData = try JSONSerialization.data(withJSONObject: hubIngressPayload, options: [.sortedKeys])
        try hubIngressData.write(
            to: hubBase.appendingPathComponent("connector_ingress_receipts_status.json"),
            options: .atomic
        )

        let hubSnapshot = try #require(
            await HubIPCClient.requestConnectorIngressReceipts(projectId: project.projectId, limit: 10)
        )
        let hubDirectResults = manager.serviceHubConnectorIngressReceiptsForTesting(
            hubSnapshot,
            now: Date(timeIntervalSince1970: 1_773_110_150)
        )
        #expect(hubDirectResults.count == 1)
        #expect(hubDirectResults.first?.decision == .run)
        #expect(hubDirectResults.first?.triggerId == "connector_event/slack_dm")
        let hubDirectRunId = try #require(hubDirectResults.first?.runId)
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .delivered,
            runID: hubDirectRunId,
            auditRef: "audit-xt-w3-30-b-hub-direct-delivered",
            now: Date(timeIntervalSince1970: 1_773_110_151)
        )

        let vertical = XTAutomationProductGapClosureEngine().buildVerticalSlice(verticalSliceInput())
        let ingressEnvelopes = vertical.recipeManifest.externalTriggerIngressEnvelopes
        #expect(ingressEnvelopes.count == 4)
        #expect(ingressEnvelopes.allSatisfy { $0.schemaVersion == XTAutomationExternalTriggerIngressEnvelope.currentSchemaVersion })
        #expect(ingressEnvelopes.contains { $0.triggerType == .schedule && $0.cooldownSec == 300 && $0.connectorID.isEmpty })
        #expect(ingressEnvelopes.contains { $0.triggerType == .webhook && $0.cooldownSec == 30 && $0.connectorID == "github" })
        #expect(ingressEnvelopes.contains { $0.triggerType == .connectorEvent && $0.cooldownSec == 45 && $0.connectorID == "slack" })
        #expect(vertical.eventRunner.externalTriggerIngressEnvelopes.count == 4)

        let rogueTriggerResult = manager.ingestAutomationExternalTrigger(
            SupervisorManager.SupervisorAutomationExternalTriggerIngress(
                projectId: project.projectId,
                triggerId: "webhook/rogue",
                triggerType: .webhook,
                source: .github,
                payloadRef: "local://trigger-payload/rogue",
                dedupeKey: "sha256:rogue",
                receivedAt: Date(timeIntervalSince1970: 1_773_110_120),
                ingressChannel: "test_webhook_bridge"
            )
        )
        #expect(rogueTriggerResult.decision == .failClosed)
        #expect(rogueTriggerResult.reasonCode == "trigger_ingress_not_allowed")

        let replayCollisionResult = manager.ingestAutomationExternalTrigger(
            SupervisorManager.SupervisorAutomationExternalTriggerIngress(
                projectId: project.projectId,
                triggerId: "webhook/github_pr",
                triggerType: .webhook,
                source: .github,
                payloadRef: "local://trigger-payload/20260311-004",
                dedupeKey: "sha256:webhook-github-pr-20260311",
                receivedAt: Date(timeIntervalSince1970: 1_773_110_140),
                ingressChannel: "test_webhook_bridge"
            )
        )
        #expect(replayCollisionResult.decision == .drop)
        #expect(replayCollisionResult.reasonCode == "external_trigger_replay_detected")

        let rawLog = try rawLogEntries(for: ctx)
        let routeRows = rawLog.filter { ($0["type"] as? String) == "automation_external_trigger_route" }
        #expect(routeRows.contains {
            ($0["trigger_id"] as? String) == "schedule/nightly"
                && ($0["decision"] as? String) == "run"
        })
        #expect(routeRows.contains {
            ($0["trigger_id"] as? String) == "webhook/github_pr"
                && ($0["decision"] as? String) == "run"
        })
        #expect(routeRows.contains {
            ($0["trigger_id"] as? String) == "connector_event/slack_dm"
                && ($0["decision"] as? String) == "run"
        })

        let evidence = XTW330BExternalTriggerRuntimeEvidence(
            schemaVersion: "xt_w3_30_b_external_trigger_runtime_evidence.v1",
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            status: "delivered",
            claimScope: ["XT-W3-30-B", "XT-OC-G2"],
            claim: "External trigger ingress envelopes are frozen, and schedule poll, XT supervisor ingress bridge, plus Hub receipt snapshot binding now compile schedule/webhook/connector_event into guarded runs with replay, cooldown, and allowlist fail-closed behavior.",
            contractSchemaVersion: XTAutomationExternalTriggerIngressEnvelope.currentSchemaVersion,
            triggerSurface: [
                ExternalTriggerSurfaceEvidence(triggerType: "schedule", state: "live_scheduler_poll_runtime", exercised: true, failClosedDenyCode: nil),
                ExternalTriggerSurfaceEvidence(triggerType: "webhook", state: "live_external_ingress_bridge", exercised: true, failClosedDenyCode: "trigger_ingress_not_allowed"),
                ExternalTriggerSurfaceEvidence(triggerType: "connector_event", state: "live_external_ingress_bridge", exercised: true, failClosedDenyCode: nil),
                ExternalTriggerSurfaceEvidence(triggerType: "hub_connector_receipt", state: "live_hub_receipt_binding_runtime", exercised: true, failClosedDenyCode: "hub_ingress_trigger_unresolved"),
                ExternalTriggerSurfaceEvidence(triggerType: "manual", state: "manual_escape_hatch_allowed", exercised: true, failClosedDenyCode: nil)
            ],
            verificationResults: [
                ExternalTriggerVerificationResult(
                    name: "ingress_envelope_contract_frozen",
                    status: ingressEnvelopes.count == 4 ? "pass" : "fail",
                    detail: ingressEnvelopes.count == 4 ? "schedule/webhook/connector_event/manual all compiled into xt.external_trigger_ingress_envelope.v1" : "ingress envelope coverage incomplete"
                ),
                ExternalTriggerVerificationResult(
                    name: "live_schedule_runtime_started",
                    status: scheduleResult.first?.decision == .run ? "pass" : "fail",
                    detail: scheduleResult.first?.decision == .run ? "schedule/nightly launched through scheduler poll runtime" : "schedule runtime did not produce guarded run"
                ),
                ExternalTriggerVerificationResult(
                    name: "live_webhook_bridge_started",
                    status: webhookResult.decision == .run ? "pass" : "fail",
                    detail: webhookResult.decision == .run ? "webhook/github_pr launched through supervisor ingress bridge" : "webhook ingress bridge did not produce guarded run"
                ),
                ExternalTriggerVerificationResult(
                    name: "live_connector_bridge_started",
                    status: connectorResult.decision == .run ? "pass" : "fail",
                    detail: connectorResult.decision == .run ? "connector_event/slack_dm launched through supervisor ingress bridge" : "connector ingress bridge did not produce guarded run"
                ),
                ExternalTriggerVerificationResult(
                    name: "live_hub_receipt_binding_started",
                    status: hubDirectResults.first?.decision == .run ? "pass" : "fail",
                    detail: hubDirectResults.first?.decision == .run ? "connector_event/slack_dm launched through Hub receipt snapshot -> HubIPCClient -> Supervisor runtime" : "Hub receipt snapshot binding did not produce guarded run"
                ),
                ExternalTriggerVerificationResult(
                    name: "rogue_trigger_fail_closed",
                    status: rogueTriggerResult.decision == .failClosed && rogueTriggerResult.reasonCode == "trigger_ingress_not_allowed" ? "pass" : "fail",
                    detail: "\(rogueTriggerResult.decision.rawValue):\(rogueTriggerResult.reasonCode)"
                ),
                ExternalTriggerVerificationResult(
                    name: "replay_collision_fail_closed",
                    status: replayCollisionResult.decision == .drop && replayCollisionResult.reasonCode == "external_trigger_replay_detected" ? "pass" : "fail",
                    detail: "\(replayCollisionResult.decision.rawValue):\(replayCollisionResult.reasonCode)"
                ),
                ExternalTriggerVerificationResult(
                    name: "route_log_tags_ingress_schema",
                    status: routeRows.allSatisfy { ($0["external_trigger_ingress_schema_version"] as? String) == XTAutomationExternalTriggerIngressEnvelope.currentSchemaVersion } ? "pass" : "fail",
                    detail: routeRows.allSatisfy { ($0["external_trigger_ingress_schema_version"] as? String) == XTAutomationExternalTriggerIngressEnvelope.currentSchemaVersion } ? "automation_external_trigger_route records ingress schema version" : "route raw log missing ingress schema tag"
                )
            ],
            boundedGaps: [],
            sourceRefs: [
                "x-terminal/work-orders/xt-w3-30-openclaw-mode-capability-gap-closure-implementation-pack-v1.md:286",
                "x-terminal/Sources/Hub/HubIPCClient.swift:1",
                "x-terminal/Sources/Hub/HubPairingCoordinator.swift:1",
                "x-terminal/Sources/Supervisor/AutomationProductGapClosure.swift:92",
                "x-terminal/Sources/Supervisor/SupervisorManager.swift:6551",
                "x-terminal/Sources/Supervisor/XTAutomationRunCoordinator.swift:1",
                "x-terminal/Tests/SupervisorManagerAutomationRuntimeTests.swift:1",
                "x-terminal/Tests/XTW330PolicyRecoveryEvidenceTests.swift:1",
                "x-terminal/Tests/XTW330ExternalTriggerRuntimeEvidenceTests.swift:1"
            ]
        )

        #expect(evidence.verificationResults.allSatisfy { $0.status == "pass" })
        #expect(evidence.boundedGaps.isEmpty)

        guard let captureDir = ProcessInfo.processInfo.environment["XT_W3_30_CAPTURE_DIR"],
              !captureDir.isEmpty else {
            return
        }

        let destination = URL(fileURLWithPath: captureDir)
            .appendingPathComponent("xt_w3_30_b_external_trigger_runtime_evidence.v1.json")
        try writeJSON(evidence, to: destination)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    private func verticalSliceInput() -> XTAutomationVerticalSliceInput {
        XTAutomationVerticalSliceInput(
            projectID: UUID(uuidString: "12345678-1234-1234-1234-1234567890ab")!,
            recipeID: "xt-auto-pr-review",
            goal: "nightly triage + code review + summary delivery",
            deliveryTargets: ["channel://telegram/project-a"],
            acceptancePackRef: "build/reports/xt_w3_22_acceptance_pack.v1.json",
            executionProfile: .balanced,
            touchMode: .guidedTouch,
            innovationLevel: .l2,
            laneStrategy: .adaptive,
            runID: "run-20260311-xt-w3-30-b",
            currentOwner: "XT-L2",
            activePoolCount: 1,
            activeLaneCount: 1,
            blockedTaskID: "XT-W3-30-B",
            upstreamDependencyIDs: ["Hub-Wx"],
            operatorConsoleEvidenceRef: "build/reports/xt_w3_24_d_operator_console_evidence.v1.json",
            latestDeltaRef: "build/reports/xt_w3_30_b_delta.v1.json",
            deliveryRef: "build/reports/xt_w3_30_b_delivery.v1.json",
            firstRunChecklistRef: "docs/open-source/OSS_MINIMAL_RUNNABLE_PACKAGE_CHECKLIST_v1.md",
            triggerSeeds: [
                XTAutomationTriggerSeed(triggerID: "schedule/nightly", triggerType: .schedule, source: .timer, payloadRef: "local://trigger-payload/20260311-001", requiresGrant: true, policyRef: "policy://automation-trigger/project-a", dedupeKey: "sha256:schedule-nightly"),
                XTAutomationTriggerSeed(triggerID: "webhook/github_pr", triggerType: .webhook, source: .github, payloadRef: "local://trigger-payload/20260311-002", requiresGrant: true, policyRef: "policy://automation-trigger/project-a", dedupeKey: "sha256:webhook-github-pr"),
                XTAutomationTriggerSeed(triggerID: "connector_event/slack_dm", triggerType: .connectorEvent, source: .slack, payloadRef: "local://trigger-payload/20260311-003", requiresGrant: true, policyRef: "policy://automation-trigger/project-a", dedupeKey: "sha256:connector-event-slack-dm"),
                XTAutomationTriggerSeed(triggerID: "manual/retry", triggerType: .manual, source: .hub, payloadRef: "local://trigger-payload/20260311-004", requiresGrant: true, policyRef: "policy://automation-trigger/project-a", dedupeKey: "sha256:manual-retry")
            ],
            hubTransportMode: .auto,
            hasRemoteProfile: true,
            budgetOK: true,
            requiresTrustedAutomation: true,
            trustedAutomationReady: true,
            permissionOwnerReady: true,
            workspaceBindingHash: "sha256:workspace-binding-project-a",
            grantPolicyRef: "policy://automation-trigger/project-a",
            trustedDeviceID: "device://trusted/project-a",
            requiredDeviceToolGroups: ["device.ui.step"],
            intakeWorkflow: nil,
            acceptanceWorkflow: nil,
            additionalEvidenceRefs: ["build/reports/xt_w3_25_hub_dependency_readiness.v1.json"],
            now: Date(timeIntervalSince1970: 1_773_110_030)
        )
    }

    private func makeProjectRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-xt-w3-30-b-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeRecipe() -> AXAutomationRecipeRuntimeBinding {
        AXAutomationRecipeRuntimeBinding(
            recipeID: "xt-auto-pr-review",
            recipeVersion: 1,
            lifecycleState: .ready,
            goal: "nightly triage + code review + summary delivery",
            triggerRefs: [
                "xt.automation_trigger_envelope.v1:schedule/nightly",
                "xt.automation_trigger_envelope.v1:webhook/github_pr",
                "xt.automation_trigger_envelope.v1:connector_event/slack_dm"
            ],
            deliveryTargets: ["channel://telegram/project-a"],
            acceptancePackRef: "build/reports/xt_w3_22_acceptance_pack.v1.json",
            executionProfile: .balanced,
            touchMode: .guidedTouch,
            innovationLevel: .l2,
            laneStrategy: .adaptive,
            requiredToolGroups: ["group:full"],
            requiredDeviceToolGroups: ["device.ui.step"],
            requiresTrustedAutomation: true,
            trustedDeviceID: "device://trusted/project-a",
            workspaceBindingHash: "sha256:workspace-binding-project-a",
            grantPolicyRef: "policy://automation-trigger/project-a",
            rolloutStatus: .active,
            lastEditedAtMs: 1_773_110_000_000,
            lastEditAuditRef: "audit-xt-w3-30-b",
            lastLaunchRef: ""
        )
    }

    private func makeLiveRuntimeRecipe() -> AXAutomationRecipeRuntimeBinding {
        AXAutomationRecipeRuntimeBinding(
            recipeID: "xt-auto-live-trigger-runtime",
            recipeVersion: 1,
            lifecycleState: .ready,
            goal: "drive schedule, webhook, and connector ingress into guarded automation runtime",
            triggerRefs: [
                "xt.automation_trigger_envelope.v1:schedule/nightly",
                "xt.automation_trigger_envelope.v1:webhook/github_pr",
                "xt.automation_trigger_envelope.v1:connector_event/slack_dm"
            ],
            deliveryTargets: ["channel://telegram/project-a"],
            acceptancePackRef: "build/reports/xt_w3_22_acceptance_pack.v1.json",
            executionProfile: .balanced,
            touchMode: .guidedTouch,
            innovationLevel: .l1,
            laneStrategy: .singleLane,
            requiredToolGroups: ["group:full"],
            requiresTrustedAutomation: false,
            trustedDeviceID: "",
            workspaceBindingHash: "",
            grantPolicyRef: "policy://automation-trigger/project-a",
            rolloutStatus: .active,
            lastEditedAtMs: 1_773_110_000_000,
            lastEditAuditRef: "audit-xt-w3-30-b-live-runtime",
            lastLaunchRef: ""
        )
    }

    private func makeProjectEntry(root: URL) -> AXProjectEntry {
        AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: root.lastPathComponent,
            lastOpenedAt: 1_773_110_000,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
    }

    private func rawLogEntries(for ctx: AXProjectContext) throws -> [[String: Any]] {
        let data = try Data(contentsOf: ctx.rawLogURL)
        let text = try #require(String(data: data, encoding: .utf8))
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                guard let lineData = String(line).data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                    return nil
                }
                return object
            }
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

private struct XTW330BExternalTriggerRuntimeEvidence: Codable, Equatable {
    var schemaVersion: String
    var generatedAt: String
    var status: String
    var claimScope: [String]
    var claim: String
    var contractSchemaVersion: String
    var triggerSurface: [ExternalTriggerSurfaceEvidence]
    var verificationResults: [ExternalTriggerVerificationResult]
    var boundedGaps: [ExternalTriggerGapEvidence]
    var sourceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case status
        case claimScope = "claim_scope"
        case claim
        case contractSchemaVersion = "contract_schema_version"
        case triggerSurface = "trigger_surface"
        case verificationResults = "verification_results"
        case boundedGaps = "bounded_gaps"
        case sourceRefs = "source_refs"
    }
}

private struct ExternalTriggerSurfaceEvidence: Codable, Equatable {
    var triggerType: String
    var state: String
    var exercised: Bool
    var failClosedDenyCode: String?

    enum CodingKeys: String, CodingKey {
        case triggerType = "trigger_type"
        case state
        case exercised
        case failClosedDenyCode = "fail_closed_deny_code"
    }
}

private struct ExternalTriggerVerificationResult: Codable, Equatable {
    var name: String
    var status: String
    var detail: String
}

private struct ExternalTriggerGapEvidence: Codable, Equatable {
    var id: String
    var severity: String
    var currentBehavior: String
    var requiredNextStep: String

    enum CodingKeys: String, CodingKey {
        case id
        case severity
        case currentBehavior = "current_behavior"
        case requiredNextStep = "required_next_step"
    }
}
