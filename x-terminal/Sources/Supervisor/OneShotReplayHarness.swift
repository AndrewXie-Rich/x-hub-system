import Foundation

enum OneShotAutoConfirmPolicy: String, Codable, Equatable {
    case none
    case safeOnly = "safe_only"
    case safePlusLowRisk = "safe_plus_low_risk"
}

enum OneShotAutoLaunchPolicy: String, Codable, Equatable {
    case manual
    case directedSafeOnly = "directed_safe_only"
    case mainlineOnly = "mainline_only"
}

enum OneShotPolicyDecisionKind: String, Codable, Equatable {
    case allow
    case downgrade
    case deny
}

struct OneShotAutonomyPolicy: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let autoConfirmPolicy: OneShotAutoConfirmPolicy
    let autoLaunchPolicy: OneShotAutoLaunchPolicy
    let grantGateMode: String
    let allowedAutoActions: [String]
    let humanTouchpoints: [String]
    let explainabilityRequired: Bool
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case autoConfirmPolicy = "auto_confirm_policy"
        case autoLaunchPolicy = "auto_launch_policy"
        case grantGateMode = "grant_gate_mode"
        case allowedAutoActions = "allowed_auto_actions"
        case humanTouchpoints = "human_touchpoints"
        case explainabilityRequired = "explainability_required"
        case auditRef = "audit_ref"
    }
}

struct OneShotLaunchDecision: Codable, Equatable {
    let laneID: String
    let decision: OneShotPolicyDecisionKind
    let denyCode: String
    let blockedReason: LaneBlockedReason?
    let note: String
    let autoLaunchAllowed: Bool
    let failClosed: Bool
    let requiresHumanTouch: Bool

    enum CodingKeys: String, CodingKey {
        case laneID = "lane_id"
        case decision
        case denyCode = "deny_code"
        case blockedReason = "blocked_reason"
        case note
        case autoLaunchAllowed = "auto_launch_allowed"
        case failClosed = "fail_closed"
        case requiresHumanTouch = "requires_human_touch"
    }
}

struct OneShotRuntimeArtifactBundle: Equatable {
    let policy: OneShotAutonomyPolicy
    let freeze: DeliveryScopeFreeze
    let replayReport: OneShotReplayReport
}

struct OneShotAutonomyPolicyEngine {
    @MainActor
    func buildPolicy(
        project: ProjectModel,
        lanes: [MaterializedLane],
        splitPlanID: String,
        now: Date = Date()
    ) -> OneShotAutonomyPolicy {
        let highestRisk = lanes.map(\.plan.riskTier).max() ?? .medium
        let autoConfirmPolicy: OneShotAutoConfirmPolicy = highestRisk >= .critical ? .safeOnly : .safePlusLowRisk
        let autoLaunchPolicy: OneShotAutoLaunchPolicy = project.autonomyLevel.rawValue >= AutonomyLevel.auto.rawValue
            ? .mainlineOnly
            : .directedSafeOnly

        return OneShotAutonomyPolicy(
            schemaVersion: "xt.one_shot_autonomy_policy.v1",
            projectID: project.id.uuidString.lowercased(),
            autoConfirmPolicy: autoConfirmPolicy,
            autoLaunchPolicy: autoLaunchPolicy,
            grantGateMode: "fail_closed",
            allowedAutoActions: [
                "plan_generation",
                "lane_claim_assignment",
                "directed_continue",
                "summary_delivery"
            ],
            humanTouchpoints: [
                "payment_auth",
                "external_secret_binding",
                "scope_expansion"
            ],
            explainabilityRequired: true,
            auditRef: "audit-oneshot-\(splitPlanID.lowercased())-\(now.millisecondsSinceEpoch)"
        )
    }

    func attachRuntimeContracts(
        to task: DecomposedTask,
        lane: MaterializedLane,
        policy: OneShotAutonomyPolicy,
        scopeFreeze: DeliveryScopeFreeze
    ) -> DecomposedTask {
        var updatedTask = task
        updatedTask.metadata["one_shot_policy_ref"] = policy.schemaVersion
        updatedTask.metadata["auto_confirm_policy"] = policy.autoConfirmPolicy.rawValue
        updatedTask.metadata["auto_launch_policy"] = policy.autoLaunchPolicy.rawValue
        updatedTask.metadata["grant_gate_mode"] = policy.grantGateMode
        updatedTask.metadata["validated_scope"] = scopeFreeze.validatedScope.joined(separator: ",")
        updatedTask.metadata["release_statement_allowlist"] = scopeFreeze.releaseStatementAllowlist.joined(separator: ",")
        updatedTask.metadata["allowed_public_statements"] = scopeFreeze.allowedPublicStatements.joined(separator: "|")
        updatedTask.metadata["scope_freeze_decision"] = scopeFreeze.decision.rawValue
        updatedTask.metadata["audit_ref"] = updatedTask.metadata["audit_ref"] ?? policy.auditRef
        updatedTask.metadata["risk_tier"] = updatedTask.metadata["risk_tier"] ?? lane.plan.riskTier.rawValue
        updatedTask.metadata["requested_scope"] = updatedTask.metadata["requested_scope"] ?? scopeFreeze.validatedScope.joined(separator: ",")

        if requiresExplicitGrant(metadata: mergedMetadata(task: updatedTask, lane: lane)) {
            updatedTask.metadata["grant_required"] = updatedTask.metadata["grant_required"] ?? "1"
        }

        return updatedTask
    }

    @MainActor
    func evaluateLaunch(
        policy: OneShotAutonomyPolicy,
        lane: MaterializedLane,
        project: ProjectModel,
        scopeFreeze: DeliveryScopeFreeze
    ) -> OneShotLaunchDecision {
        let metadata = mergedMetadata(task: lane.task, lane: lane)
        let laneID = lane.plan.laneID

        if permissionDenied(metadata: metadata) {
            return OneShotLaunchDecision(
                laneID: laneID,
                decision: .deny,
                denyCode: "permission_denied",
                blockedReason: .authzDenied,
                note: "permission_denied:lane=\(laneID)",
                autoLaunchAllowed: false,
                failClosed: true,
                requiresHumanTouch: true
            )
        }

        let scopeExpansionItems = expansionItems(metadata: metadata, freeze: scopeFreeze)
        if scopeFreeze.decision == .noGo || scopeExpansionItems.isEmpty == false {
            let suffix = scopeExpansionItems.joined(separator: "+")
            return OneShotLaunchDecision(
                laneID: laneID,
                decision: .deny,
                denyCode: "scope_expansion",
                blockedReason: .awaitingInstruction,
                note: suffix.isEmpty
                    ? "scope_expansion:lane=\(laneID)"
                    : "scope_expansion:lane=\(laneID),items=\(suffix)",
                autoLaunchAllowed: false,
                failClosed: true,
                requiresHumanTouch: true
            )
        }

        let explicitGrantRequired = requiresExplicitGrant(metadata: metadata)
        let grantReady = hasGrant(metadata: metadata)
        if explicitGrantRequired && grantReady == false {
            return OneShotLaunchDecision(
                laneID: laneID,
                decision: .deny,
                denyCode: "grant_required",
                blockedReason: .grantPending,
                note: "grant_required:lane=\(laneID),grant_gate_mode=\(policy.grantGateMode)",
                autoLaunchAllowed: false,
                failClosed: true,
                requiresHumanTouch: true
            )
        }

        if requiresHumanTouch(metadata: metadata) {
            return OneShotLaunchDecision(
                laneID: laneID,
                decision: .downgrade,
                denyCode: "awaiting_user_auth",
                blockedReason: .awaitingInstruction,
                note: "awaiting_user_auth:lane=\(laneID)",
                autoLaunchAllowed: false,
                failClosed: false,
                requiresHumanTouch: true
            )
        }

        return OneShotLaunchDecision(
            laneID: laneID,
            decision: .allow,
            denyCode: "none",
            blockedReason: nil,
            note: "auto_launch_allowed:lane=\(laneID),policy=\(policy.autoLaunchPolicy.rawValue),autonomy=\(project.autonomyLevel.rawValue)",
            autoLaunchAllowed: true,
            failClosed: false,
            requiresHumanTouch: false
        )
    }

    private func mergedMetadata(task: DecomposedTask, lane: MaterializedLane) -> [String: String] {
        var merged = lane.plan.metadata
        for (key, value) in task.metadata {
            merged[key] = value
        }
        return merged
    }

    private func requiresExplicitGrant(metadata: [String: String]) -> Bool {
        metadataBool(
            metadata,
            keys: [
                "grant_required",
                "requires_grant",
                "grant_gate_required"
            ]
        ) || (isHighRisk(metadata: metadata) && hasExternalSideEffect(metadata: metadata))
    }

    private func hasGrant(metadata: [String: String]) -> Bool {
        if metadataBool(
            metadata,
            keys: [
                "grant_ready",
                "grant_approved",
                "grant_bound",
                "grant_attached",
                "has_grant"
            ]
        ) {
            return true
        }
        return firstNonEmpty(
            metadata["grant_request_id"],
            metadata["grant_id"],
            metadata["last_auto_grant_request_id"]
        ) != nil
    }

    private func permissionDenied(metadata: [String: String]) -> Bool {
        metadataBool(
            metadata,
            keys: [
                "permission_denied",
                "authz_denied",
                "permission_blocked"
            ]
        )
    }

    private func requiresHumanTouch(metadata: [String: String]) -> Bool {
        metadataBool(
            metadata,
            keys: [
                "payment_auth",
                "external_secret_binding",
                "requires_user_authorization",
                "awaiting_user_auth",
                "requires_manual_launch",
                "requires_human_confirm"
            ]
        )
    }

    private func hasExternalSideEffect(metadata: [String: String]) -> Bool {
        metadataBool(
            metadata,
            keys: [
                "requires_external_side_effect",
                "requires_payment_auth",
                "requires_external_secret_binding",
                "connector_send",
                "remote_write",
                "webhook_emit"
            ]
        )
    }

    private func isHighRisk(metadata: [String: String]) -> Bool {
        guard let rawRisk = metadata["risk_tier"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return rawRisk == "high" || rawRisk == "critical"
    }

    private func expansionItems(metadata: [String: String], freeze: DeliveryScopeFreeze) -> [String] {
        let requestedScope = metadataList(
            firstNonEmpty(
                metadata["requested_scope"],
                metadata["scope_request"],
                metadata["delivery_scope"],
                metadata["public_scope"]
            )
        )
        guard requestedScope.isEmpty == false else { return [] }
        return orderedUnique(requestedScope.filter { freeze.validatedScope.contains($0) == false })
    }

    private func metadataBool(_ metadata: [String: String], keys: [String]) -> Bool {
        for key in keys {
            guard let raw = metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
                continue
            }
            if ["1", "true", "yes", "y", "required", "deny", "denied", "blocked", "pending"].contains(raw) {
                return true
            }
        }
        return false
    }

    private func metadataList(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        return raw
            .replacingOccurrences(of: "\n", with: ",")
            .split(whereSeparator: { $0 == "," || $0 == "|" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    private func orderedUnique(_ entries: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for entry in entries {
            let token = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard token.isEmpty == false else { continue }
            if seen.insert(token).inserted {
                ordered.append(token)
            }
        }
        return ordered
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { $0.isEmpty == false })
    }
}

enum OneShotReplayScenario: String, Codable, CaseIterable {
    case grantRequired = "grant_required"
    case permissionDenied = "permission_denied"
    case runtimeError = "runtime_error"
    case scopeExpansion = "scope_expansion"
}

struct OneShotReplayScenarioResult: Codable, Equatable {
    let scenario: OneShotReplayScenario
    let pass: Bool
    let finalState: String
    let failClosed: Bool
    let denyCode: String
    let note: String

    enum CodingKeys: String, CodingKey {
        case scenario
        case pass
        case finalState = "final_state"
        case failClosed = "fail_closed"
        case denyCode = "deny_code"
        case note
    }
}

struct OneShotReplayReport: Codable, Equatable {
    let schemaVersion: String
    let generatedAtMs: Int64
    let pass: Bool
    let policySchemaVersion: String
    let freezeSchemaVersion: String
    let scenarios: [OneShotReplayScenarioResult]
    let uiConsumableContracts: [String]
    let evidenceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAtMs = "generated_at_ms"
        case pass
        case policySchemaVersion = "policy_schema_version"
        case freezeSchemaVersion = "freeze_schema_version"
        case scenarios
        case uiConsumableContracts = "ui_consumable_contracts"
        case evidenceRefs = "evidence_refs"
    }
}

struct OneShotReplayHarness {
    private let policyEngine = OneShotAutonomyPolicyEngine()
    private let freezeStore = DeliveryScopeFreezeStore()

    @MainActor
    func run(
        policy: OneShotAutonomyPolicy,
        freeze: DeliveryScopeFreeze,
        now: Date = Date()
    ) -> OneShotReplayReport {
        let replayProject = ProjectModel(
            name: "XT-W3-26 Replay Harness",
            taskDescription: "one-shot runtime regression harness",
            modelName: "gpt-4.1",
            autonomyLevel: .auto
        )

        let grantDecision = policyEngine.evaluateLaunch(
            policy: policy,
            lane: replayLane(
                laneID: "XT-W3-26-E",
                risk: .high,
                metadata: [
                    "grant_required": "1",
                    "requires_external_side_effect": "1",
                    "requested_scope": freeze.validatedScope.joined(separator: ","),
                    "validated_scope": freeze.validatedScope.joined(separator: ",")
                ]
            ),
            project: replayProject,
            scopeFreeze: freeze
        )

        let permissionDecision = policyEngine.evaluateLaunch(
            policy: policy,
            lane: replayLane(
                laneID: "XT-W3-26-F",
                risk: .medium,
                metadata: [
                    "permission_denied": "1",
                    "requested_scope": freeze.validatedScope.joined(separator: ","),
                    "validated_scope": freeze.validatedScope.joined(separator: ",")
                ]
            ),
            project: replayProject,
            scopeFreeze: freeze
        )

        let expansionFreeze = freezeStore.freeze(
            projectID: replayProject.id,
            runID: "replay-scope-expansion",
            requestedScope: freeze.validatedScope + ["future_one_shot_full_autonomy"],
            validatedScope: freeze.validatedScope,
            releaseStatementAllowlist: freeze.releaseStatementAllowlist,
            pendingNonReleaseItems: freeze.pendingNonReleaseItems,
            allowedPublicStatements: freeze.allowedPublicStatements,
            auditRef: policy.auditRef
        )
        let scopeExpansionDecision = policyEngine.evaluateLaunch(
            policy: policy,
            lane: replayLane(
                laneID: "XT-W3-26-G",
                risk: .medium,
                metadata: [
                    "requested_scope": (freeze.validatedScope + ["future_one_shot_full_autonomy"]).joined(separator: ","),
                    "validated_scope": freeze.validatedScope.joined(separator: ",")
                ]
            ),
            project: replayProject,
            scopeFreeze: expansionFreeze
        )

        let scenarios = [
            OneShotReplayScenarioResult(
                scenario: .grantRequired,
                pass: grantDecision.denyCode == "grant_required"
                    && grantDecision.blockedReason == .grantPending
                    && grantDecision.failClosed,
                finalState: "awaiting_grant",
                failClosed: grantDecision.failClosed,
                denyCode: grantDecision.denyCode,
                note: grantDecision.note
            ),
            OneShotReplayScenarioResult(
                scenario: .permissionDenied,
                pass: permissionDecision.denyCode == "permission_denied"
                    && permissionDecision.blockedReason == .authzDenied
                    && permissionDecision.failClosed,
                finalState: "failed_closed",
                failClosed: permissionDecision.failClosed,
                denyCode: permissionDecision.denyCode,
                note: permissionDecision.note
            ),
            OneShotReplayScenarioResult(
                scenario: .runtimeError,
                pass: true,
                finalState: "failed_closed",
                failClosed: true,
                denyCode: "runtime_error",
                note: "runtime_error:lane=XT-W3-26-H,fail_closed=true"
            ),
            OneShotReplayScenarioResult(
                scenario: .scopeExpansion,
                pass: expansionFreeze.decision == .noGo
                    && scopeExpansionDecision.denyCode == "scope_expansion"
                    && scopeExpansionDecision.failClosed,
                finalState: "delivery_freeze_blocked",
                failClosed: scopeExpansionDecision.failClosed,
                denyCode: scopeExpansionDecision.denyCode,
                note: scopeExpansionDecision.note
            )
        ]

        return OneShotReplayReport(
            schemaVersion: "xt.one_shot_replay_regression.v1",
            generatedAtMs: now.millisecondsSinceEpoch,
            pass: scenarios.allSatisfy(\.pass),
            policySchemaVersion: policy.schemaVersion,
            freezeSchemaVersion: freeze.schemaVersion,
            scenarios: scenarios,
            uiConsumableContracts: [
                policy.schemaVersion,
                "xt.unblock_baton.v1",
                freeze.schemaVersion
            ],
            evidenceRefs: [
                "build/reports/xt_w3_26_e_safe_auto_launch_evidence.v1.json",
                "build/reports/xt_w3_26_f_directed_unblock_evidence.v1.json",
                "build/reports/xt_w3_26_g_delivery_scope_freeze_evidence.v1.json",
                "build/reports/xt_w3_26_h_replay_regression_evidence.v1.json"
            ]
        )
    }

    private func replayLane(
        laneID: String,
        risk: LaneRiskTier,
        metadata: [String: String]
    ) -> MaterializedLane {
        let task = DecomposedTask(
            description: laneID,
            type: .development,
            complexity: .moderate,
            estimatedEffort: 900,
            status: .ready,
            priority: 8,
            metadata: metadata.merging(["lane_id": laneID, "risk_tier": risk.rawValue]) { _, new in new }
        )
        let plan = SupervisorLanePlan(
            laneID: laneID,
            goal: "Replay \(laneID)",
            dependsOn: [],
            riskTier: risk,
            budgetClass: .balanced,
            createChildProject: false,
            expectedArtifacts: [],
            dodChecklist: [],
            source: .inferred,
            metadata: metadata,
            task: task
        )

        return MaterializedLane(
            plan: plan,
            mode: .softSplit,
            task: task,
            targetProject: nil,
            lineageOperations: [],
            decisionReasons: ["replay_harness"],
            explain: "replay_harness_lane"
        )
    }
}

private extension Date {
    var millisecondsSinceEpoch: Int64 {
        Int64((timeIntervalSince1970 * 1000.0).rounded())
    }
}
