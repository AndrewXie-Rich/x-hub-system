import Foundation
import Testing
@testable import XTerminal

struct HubAIPaidModelAccessExplainabilityTests {
    private let deviceName = "Andrew-MBP-XT"
    private let modelId = "openai/gpt-4.1"

    @Test
    func paidModelAccessResolutionCoversAllRequiredStates() {
        let scenarios = makeScenarios()
        #expect(scenarios.count == 6)

        let states = Set(scenarios.map(\.resolution.state))
        #expect(states.contains(.allowedByDevicePolicy))
        #expect(states.contains(.blockedPaidModelDisabled))
        #expect(states.contains(.blockedModelNotInCustomAllowlist))
        #expect(states.contains(.blockedDailyBudgetExceeded))
        #expect(states.contains(.blockedSingleRequestBudgetExceeded))
        #expect(states.contains(.legacyGrantFlowRequired))

        for scenario in scenarios {
            #expect(!scenario.resolution.headline.isEmpty)
            #expect(!scenario.resolution.whyItHappened.isEmpty)
            #expect(!scenario.resolution.nextAction.isEmpty)
            #expect(scenario.resolution.deviceName == deviceName)
            #expect(scenario.resolution.modelId == modelId)
            #expect(scenario.resolution.renderedExplanation.contains("device_name=\(deviceName)"))
            #expect(scenario.resolution.renderedExplanation.contains("model_id=\(modelId)"))
            #expect(scenario.resolution.renderedExplanation.contains("why_it_happened="))
            #expect(scenario.resolution.renderedExplanation.contains("next_action="))
        }
    }

    @Test
    func newProfileMessagesStayOutOfLegacyGrantDeadEnds() {
        let blockedStates = makeScenarios().filter { $0.resolution.policyMode == "new_profile" }
        #expect(!blockedStates.isEmpty)

        for scenario in blockedStates {
            let text = scenario.resolution.renderedExplanation.lowercased()
            #expect(!text.contains("global home"))
            #expect(!text.contains("pending grant"))
            #expect(!text.contains("permission denied"))
            #expect(text.contains("policy_mode=new_profile"))
        }

        let legacyText = makeLegacyErrorDescription(rawReason: "grant_required")
        #expect(legacyText.contains("policy_mode=legacy_grant"))
        #expect(legacyText.contains("device_name=\(deviceName)"))
        #expect(legacyText.contains("model_id=\(modelId)"))
    }

    @Test
    func hubAIErrorUsesContextualPaidModelResolution() {
        let error = HubAIError.responseDoneNotOk(
            HubAIResponseFailureContext(
                reason: "device_paid_model_not_allowed;policy_mode=new_profile;device_name=\(deviceName);model_id=\(modelId)",
                deviceName: deviceName,
                modelId: modelId
            )
        )

        let text = error.errorDescription ?? ""
        #expect(text.contains("当前模型不在这台设备的 paid model 白名单中"))
        #expect(text.contains("device_name=\(deviceName)"))
        #expect(text.contains("model_id=\(modelId)"))
        #expect(text.contains("policy_mode=new_profile"))
        #expect(!text.lowercased().contains("permission denied"))
    }

    @Test
    func legacyGrantResolutionNeverMasqueradesAsNewProfile() {
        let rawReason = """
        {"access_resolution":{"deny_code":"grant_required","policy_mode":"new_profile","device_name":"\(deviceName)","model_id":"\(modelId)","policy_ref":"schema=xt.paid_model_access_resolution.v1;policy_mode=new_profile;resolution_state=legacy_grant_flow_required;deny_code=grant_required"}}
        """

        let resolution = requireResolution(rawReason)
        #expect(resolution.state == .legacyGrantFlowRequired)
        #expect(resolution.policyMode == "legacy_grant")
        #expect(resolution.policyRef.contains("policy_mode=legacy_grant"))
        #expect(!resolution.policyRef.contains("policy_mode=new_profile"))
        #expect(resolution.renderedExplanation.contains("policy_mode=legacy_grant"))
    }

    @Test
    func newProfileResolutionNeverBackslidesToLegacyGrantContext() {
        let rawReason = """
        {"access_resolution":{"deny_code":"device_paid_model_disabled","policy_mode":"legacy_grant","device_name":"\(deviceName)","model_id":"\(modelId)","policy_ref":"schema=xt.paid_model_access_resolution.v1;policy_mode=legacy_grant;resolution_state=blocked_paid_model_disabled;deny_code=device_paid_model_disabled"}}
        """

        let resolution = requireResolution(rawReason)
        #expect(resolution.state == .blockedPaidModelDisabled)
        #expect(resolution.policyMode == "new_profile")
        #expect(resolution.policyRef.contains("policy_mode=new_profile"))
        #expect(!resolution.policyRef.contains("policy_mode=legacy_grant"))
        #expect(resolution.renderedExplanation.contains("policy_mode=new_profile"))
    }

    @Test
    func runtimeCaptureWritesXTW328FEvidenceWhenRequested() throws {
        guard let captureDir = ProcessInfo.processInfo.environment["XT_W3_28_CAPTURE_DIR"], !captureDir.isEmpty else {
            return
        }

        let base = URL(fileURLWithPath: captureDir)
        let scenarios = makeScenarios().map { scenario in
            CapturedScenario(
                name: scenario.name,
                rawReasonCode: scenario.rawReasonCode,
                resolution: scenario.resolution,
                renderedExplanation: scenario.resolution.renderedExplanation
            )
        }
        let issueCodes = [
            "device_paid_model_disabled",
            "device_paid_model_not_allowed",
            "device_daily_token_budget_exceeded",
            "device_single_request_token_exceeded",
            "legacy_grant_flow_required"
        ]
        let uiBindings = issueCodes.map { code in
            CapturedUIBinding(
                failureCode: code,
                mappedIssue: UITroubleshootKnowledgeBase.issue(forFailureCode: code)?.rawValue,
                guideDestinations: UITroubleshootKnowledgeBase.issue(forFailureCode: code)
                    .map { UITroubleshootKnowledgeBase.guide(for: $0).steps.map(\.destination.rawValue) } ?? []
            )
        }
        let verificationResults = makeVerificationResults(scenarios: scenarios, uiBindings: uiBindings)
        let evidence = XTW328FXTAccessExplainabilityEvidence(
            schemaVersion: "xt_w3_28_f_xt_access_explainability_evidence.v1",
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            status: "delivered",
            claimScope: ["XT-W3-28-F"],
            claim: "XT-W3-28-F",
            contractSchemaVersion: "xt.paid_model_access_resolution.v1",
            coveredStates: scenarios.map(\.resolution.state.rawValue),
            requiredOutputs: [
                "headline",
                "why_it_happened",
                "next_action",
                "device_name",
                "model_id",
                "policy_ref"
            ],
            scenarios: scenarios,
            uiBindings: uiBindings,
            verificationResults: verificationResults,
            negativeAssertions: [
                CapturedAssertion(id: "new_profile_no_global_home_pending_grant_dead_end", passed: scenarios.filter { $0.resolution.policyMode == "new_profile" }.allSatisfy { entry in
                    let text = entry.renderedExplanation.lowercased()
                    return !text.contains("global home") && !text.contains("pending grant") && !text.contains("permission denied")
                }),
                CapturedAssertion(id: "legacy_flow_explicit_policy_mode", passed: scenarios.contains { $0.resolution.state == .legacyGrantFlowRequired && $0.renderedExplanation.contains("policy_mode=legacy_grant") })
            ],
            sourceRefs: [
                "x-terminal/work-orders/xt-w3-28-paired-terminal-trust-profile-and-budget-visibility-implementation-pack-v1.md:170",
                "x-terminal/work-orders/xt-w3-28-paired-terminal-trust-profile-and-budget-visibility-implementation-pack-v1.md:295",
                "x-terminal/Sources/Hub/HubAIClient.swift:9",
                "x-terminal/Sources/UI/Components/TroubleshootPanel.swift:3",
                "x-terminal/Tests/HubAIPaidModelAccessExplainabilityTests.swift:5"
            ]
        )

        let fileName = "xt_w3_28_f_xt_access_explainability_evidence.v1.json"
        let destinations = evidenceDestinations(captureBase: base, fileName: fileName)
        for destination in destinations {
            try writeJSON(evidence, to: destination)
            #expect(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    private func makeScenarios() -> [Scenario] {
        [
            Scenario(
                name: "allowed_by_device_policy",
                rawReasonCode: "allowed_by_device_policy;policy_mode=new_profile;device_name=\(deviceName);model_id=\(modelId)",
                resolution: XTPaidModelAccessExplainability.allowedByDevicePolicy(deviceName: deviceName, modelId: modelId)
            ),
            Scenario(
                name: "blocked_paid_model_disabled",
                rawReasonCode: "device_paid_model_disabled;policy_mode=new_profile;device_name=\(deviceName);model_id=\(modelId)",
                resolution: requireResolution("device_paid_model_disabled;policy_mode=new_profile;device_name=\(deviceName);model_id=\(modelId)")
            ),
            Scenario(
                name: "blocked_model_not_in_custom_allowlist",
                rawReasonCode: "device_paid_model_not_allowed;policy_mode=new_profile;device_name=\(deviceName);model_id=\(modelId)",
                resolution: requireResolution("device_paid_model_not_allowed;policy_mode=new_profile;device_name=\(deviceName);model_id=\(modelId)")
            ),
            Scenario(
                name: "blocked_daily_budget_exceeded",
                rawReasonCode: "device_daily_token_budget_exceeded;policy_mode=new_profile;device_name=\(deviceName);model_id=\(modelId)",
                resolution: requireResolution("device_daily_token_budget_exceeded;policy_mode=new_profile;device_name=\(deviceName);model_id=\(modelId)")
            ),
            Scenario(
                name: "blocked_single_request_budget_exceeded",
                rawReasonCode: "device_single_request_token_exceeded;policy_mode=new_profile;device_name=\(deviceName);model_id=\(modelId)",
                resolution: requireResolution("device_single_request_token_exceeded;policy_mode=new_profile;device_name=\(deviceName);model_id=\(modelId)")
            ),
            Scenario(
                name: "legacy_grant_flow_required",
                rawReasonCode: "grant_required;policy_mode=legacy_grant;device_name=\(deviceName);model_id=\(modelId)",
                resolution: requireResolution("grant_required;policy_mode=legacy_grant;device_name=\(deviceName);model_id=\(modelId)")
            )
        ]
    }

    private func requireResolution(_ rawReason: String) -> XTPaidModelAccessResolution {
        guard let resolution = XTPaidModelAccessExplainability.resolve(
            rawReasonCode: rawReason,
            deviceName: deviceName,
            modelId: modelId
        ) else {
            Issue.record("Expected paid-model access resolution for \(rawReason)")
            return XTPaidModelAccessExplainability.allowedByDevicePolicy(deviceName: deviceName, modelId: modelId)
        }
        return resolution
    }

    private func makeLegacyErrorDescription(rawReason: String) -> String {
        let error = HubAIError.responseDoneNotOk(
            HubAIResponseFailureContext(
                reason: rawReason,
                deviceName: deviceName,
                modelId: modelId
            )
        )
        return error.errorDescription ?? ""
    }

    private func makeVerificationResults(
        scenarios: [CapturedScenario],
        uiBindings: [CapturedUIBinding]
    ) -> [VerificationResult] {
        let requiredStates: Set<String> = [
            "allowed_by_device_policy",
            "blocked_paid_model_disabled",
            "blocked_model_not_in_custom_allowlist",
            "blocked_daily_budget_exceeded",
            "blocked_single_request_budget_exceeded",
            "legacy_grant_flow_required"
        ]
        let actualStates = Set(scenarios.map(\.resolution.state.rawValue))
        let outputsComplete = scenarios.allSatisfy { scenario in
            !scenario.resolution.headline.isEmpty &&
            !scenario.resolution.whyItHappened.isEmpty &&
            !scenario.resolution.nextAction.isEmpty &&
            !scenario.resolution.deviceName.isEmpty &&
            !scenario.resolution.modelId.isEmpty &&
            !scenario.resolution.policyRef.isEmpty
        }
        let newProfileNoDeadEnd = scenarios
            .filter { $0.resolution.policyMode == "new_profile" }
            .allSatisfy { entry in
                let text = entry.renderedExplanation.lowercased()
                return !text.contains("global home") && !text.contains("pending grant") && !text.contains("permission denied")
            }
        let legacyExplicit = scenarios.contains {
            $0.resolution.state == .legacyGrantFlowRequired &&
            $0.resolution.policyMode == "legacy_grant" &&
            $0.resolution.policyRef.contains("policy_mode=legacy_grant")
        }
        let uiRoutingAligned = uiBindings.allSatisfy {
            $0.mappedIssue == "paid_model_access_blocked" &&
            $0.guideDestinations == ["xt_choose_model", "hub_pairing_device_trust", "hub_models_paid_access"]
        }

        return [
            VerificationResult(name: "covered_states_complete", status: actualStates == requiredStates ? "pass" : "fail"),
            VerificationResult(name: "required_outputs_complete", status: outputsComplete ? "pass" : "fail"),
            VerificationResult(name: "new_profile_no_pending_grant_dead_end", status: newProfileNoDeadEnd ? "pass" : "fail"),
            VerificationResult(name: "legacy_grant_explicitly_labeled", status: legacyExplicit ? "pass" : "fail"),
            VerificationResult(name: "troubleshoot_routes_aligned", status: uiRoutingAligned ? "pass" : "fail")
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
    }

    private struct Scenario {
        let name: String
        let rawReasonCode: String
        let resolution: XTPaidModelAccessResolution
    }

    private struct XTW328FXTAccessExplainabilityEvidence: Codable, Equatable {
        let schemaVersion: String
        let generatedAt: String
        let status: String
        let claimScope: [String]
        let claim: String
        let contractSchemaVersion: String
        let coveredStates: [String]
        let requiredOutputs: [String]
        let scenarios: [CapturedScenario]
        let uiBindings: [CapturedUIBinding]
        let verificationResults: [VerificationResult]
        let negativeAssertions: [CapturedAssertion]
        let sourceRefs: [String]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case generatedAt = "generated_at"
            case status
            case claimScope = "claim_scope"
            case claim
            case contractSchemaVersion = "contract_schema_version"
            case coveredStates = "covered_states"
            case requiredOutputs = "required_outputs"
            case scenarios
            case uiBindings = "ui_bindings"
            case verificationResults = "verification_results"
            case negativeAssertions = "negative_assertions"
            case sourceRefs = "source_refs"
        }
    }

    private struct VerificationResult: Codable, Equatable {
        let name: String
        let status: String
    }

    private struct CapturedScenario: Codable, Equatable {
        let name: String
        let rawReasonCode: String
        let resolution: XTPaidModelAccessResolution
        let renderedExplanation: String

        enum CodingKeys: String, CodingKey {
            case name
            case rawReasonCode = "raw_reason_code"
            case resolution
            case renderedExplanation = "rendered_explanation"
        }
    }

    private struct CapturedUIBinding: Codable, Equatable {
        let failureCode: String
        let mappedIssue: String?
        let guideDestinations: [String]

        enum CodingKeys: String, CodingKey {
            case failureCode = "failure_code"
            case mappedIssue = "mapped_issue"
            case guideDestinations = "guide_destinations"
        }
    }

    private struct CapturedAssertion: Codable, Equatable {
        let id: String
        let passed: Bool
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
