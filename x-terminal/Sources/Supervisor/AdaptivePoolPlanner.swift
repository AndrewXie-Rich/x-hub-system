import Foundation

enum OneShotPlanDecision: String, Codable, Equatable {
    case allow
    case downgrade
    case deny
}

enum OneShotRiskSurface: String, Codable, Equatable, CaseIterable, Comparable {
    case low
    case medium
    case high
    case critical

    static func < (lhs: OneShotRiskSurface, rhs: OneShotRiskSurface) -> Bool {
        let order: [OneShotRiskSurface] = [.low, .medium, .high, .critical]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }
}

struct AdaptivePoolPlanPoolEntry: Codable, Equatable, Identifiable {
    let poolID: String
    let purpose: String
    let laneIDs: [String]
    let requiresIsolation: Bool

    var id: String { poolID }

    enum CodingKeys: String, CodingKey {
        case poolID = "pool_id"
        case purpose
        case laneIDs = "lane_ids"
        case requiresIsolation = "requires_isolation"
    }
}

struct AdaptivePoolPlanDecision: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let requestID: String
    let complexityScore: Double
    let riskSurface: OneShotRiskSurface
    let selectedProfile: OneShotSplitProfile
    let selectedParticipationMode: DeliveryParticipationMode
    let selectedInnovationLevel: SupervisorInnovationLevel
    let poolCount: Int
    let laneCount: Int
    let poolPlan: [AdaptivePoolPlanPoolEntry]
    let seatCap: Int
    let blockRiskScore: Double
    let estimatedMergeCost: Double
    let decisionExplain: [String]
    let decision: OneShotPlanDecision
    let denyCode: String
    let auditRef: String

    static let frozenFieldOrder = [
        "schema_version",
        "project_id",
        "request_id",
        "complexity_score",
        "risk_surface",
        "selected_profile",
        "selected_participation_mode",
        "selected_innovation_level",
        "pool_count",
        "lane_count",
        "pool_plan",
        "seat_cap",
        "block_risk_score",
        "estimated_merge_cost",
        "decision_explain",
        "decision",
        "deny_code",
        "audit_ref"
    ]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case requestID = "request_id"
        case complexityScore = "complexity_score"
        case riskSurface = "risk_surface"
        case selectedProfile = "selected_profile"
        case selectedParticipationMode = "selected_participation_mode"
        case selectedInnovationLevel = "selected_innovation_level"
        case poolCount = "pool_count"
        case laneCount = "lane_count"
        case poolPlan = "pool_plan"
        case seatCap = "seat_cap"
        case blockRiskScore = "block_risk_score"
        case estimatedMergeCost = "estimated_merge_cost"
        case decisionExplain = "decision_explain"
        case decision
        case denyCode = "deny_code"
        case auditRef = "audit_ref"
    }
}

struct AdaptivePoolPlanningResult: Codable, Equatable {
    let decision: AdaptivePoolPlanDecision
    let seatGovernor: OneShotSeatGovernorDecision
    let selectedLaneIDs: [String]
    let selectedPoolIDs: [String]
    let blockedIssues: [String]

    enum CodingKeys: String, CodingKey {
        case decision
        case seatGovernor = "seat_governor"
        case selectedLaneIDs = "selected_lane_ids"
        case selectedPoolIDs = "selected_pool_ids"
        case blockedIssues = "blocked_issues"
    }
}

struct XTW326AdaptivePoolPlanEvidence: Codable, Equatable {
    let schemaVersion: String
    let planning: AdaptivePoolPlanningResult
    let sourceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case planning
        case sourceRefs = "source_refs"
    }
}

struct XTW326ConcurrencyGovernorEvidence: Codable, Equatable {
    let schemaVersion: String
    let governor: OneShotSeatGovernorDecision
    let sourceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case governor
        case sourceRefs = "source_refs"
    }
}

final class AdaptivePoolPlanner {
    private let seatAllocator = CriticalPathSeatAllocator(maxActiveSeats: 3)

    func plan(
        request: SupervisorOneShotIntakeRequest,
        buildResult: SplitProposalBuildResult
    ) -> AdaptivePoolPlanningResult {
        let orderedLanesOrNil = topologicallyOrderedLanes(buildResult.proposal.lanes)
        let complexityScore = normalizedComplexityScore(buildResult.proposal.complexityScore)
        let riskSurface = deriveRiskSurface(request: request, buildResult: buildResult)
        let selectedProfile = resolveSelectedProfile(
            request.preferredSplitProfile,
            riskSurface: riskSurface,
            complexityScore: complexityScore,
            budgetClass: request.tokenBudgetClass,
            participationMode: request.participationMode
        )

        guard let orderedLanes = orderedLanesOrNil else {
            let governor = OneShotSeatGovernorDecision.denied(
                requestedLaneCount: buildResult.proposal.lanes.count,
                requestedPoolCount: 0,
                seatCap: seatAllocator.maxActiveSeats,
                blockRiskScore: 1,
                riskSurface: riskSurface,
                tokenBudgetClass: request.tokenBudgetClass,
                selectedProfile: selectedProfile,
                selectedParticipationMode: request.participationMode,
                denyCode: "lane_dependency_cycle_detected",
                explain: ["lane_dependency_cycle_detected", "fail_closed"]
            )
            let decision = deniedDecision(
                request: request,
                complexityScore: complexityScore,
                riskSurface: riskSurface,
                selectedProfile: selectedProfile,
                explain: governor.decisionExplain,
                denyCode: governor.denyCode
            )
            return AdaptivePoolPlanningResult(
                decision: decision,
                seatGovernor: governor,
                selectedLaneIDs: [],
                selectedPoolIDs: [],
                blockedIssues: [governor.denyCode]
            )
        }

        let requestedPoolPlan = requestedPoolPlan(for: orderedLanes, profile: selectedProfile, riskSurface: riskSurface)
        let crossPoolCycleDetected = hasCrossPoolCycle(poolPlan: requestedPoolPlan, lanes: orderedLanes)
        let blockRiskScore = computeBlockRiskScore(
            riskSurface: riskSurface,
            complexityScore: complexityScore,
            lanes: orderedLanes
        )
        let validationIssues = buildResult.validation.blockingIssues.map(\ .code).sorted()
        let governor = seatAllocator.govern(
            requestedLaneCount: orderedLanes.count,
            requestedPoolCount: requestedPoolPlan.count,
            blockRiskScore: blockRiskScore,
            riskSurface: riskSurface,
            tokenBudgetClass: request.tokenBudgetClass,
            selectedProfile: selectedProfile,
            selectedParticipationMode: request.participationMode,
            allowAutoLaunchRequested: request.allowAutoLaunch,
            requiresHumanAuthorizationTypes: request.requiresHumanAuthorizationTypes,
            hasBlockingValidationIssues: !validationIssues.isEmpty,
            crossPoolCycleDetected: crossPoolCycleDetected
        )

        guard governor.decision != .deny else {
            let explain = buildExplain(
                request: request,
                orderedLanes: orderedLanes,
                selectedProfile: selectedProfile,
                riskSurface: riskSurface,
                requestedPoolPlan: requestedPoolPlan,
                governor: governor,
                validationIssues: validationIssues,
                crossPoolCycleDetected: crossPoolCycleDetected
            )
            let decision = deniedDecision(
                request: request,
                complexityScore: complexityScore,
                riskSurface: riskSurface,
                selectedProfile: selectedProfile,
                explain: explain,
                denyCode: governor.denyCode
            )
            return AdaptivePoolPlanningResult(
                decision: decision,
                seatGovernor: governor,
                selectedLaneIDs: [],
                selectedPoolIDs: [],
                blockedIssues: validationIssues + (crossPoolCycleDetected ? ["cross_pool_cycle_detected"] : [])
            )
        }

        let selectedLanes = Array(orderedLanes.prefix(governor.approvedLaneCount))
        let selectedPoolPlan = approvedPoolPlan(
            from: selectedLanes,
            requestedPoolPlan: requestedPoolPlan,
            approvedPoolCount: governor.approvedPoolCount,
            selectedProfile: selectedProfile,
            riskSurface: riskSurface
        )
        let explain = buildExplain(
            request: request,
            orderedLanes: selectedLanes,
            selectedProfile: selectedProfile,
            riskSurface: riskSurface,
            requestedPoolPlan: requestedPoolPlan,
            governor: governor,
            validationIssues: validationIssues,
            crossPoolCycleDetected: crossPoolCycleDetected
        )
        let estimatedMergeCost = computeEstimatedMergeCost(
            poolPlan: selectedPoolPlan,
            selectedLaneCount: selectedLanes.count,
            complexityScore: complexityScore,
            dependencyDensity: dependencyDensity(for: selectedLanes)
        )
        let decision = AdaptivePoolPlanDecision(
            schemaVersion: "xt.adaptive_pool_plan_decision.v1",
            projectID: request.projectID,
            requestID: request.requestID,
            complexityScore: complexityScore,
            riskSurface: riskSurface,
            selectedProfile: selectedProfile,
            selectedParticipationMode: request.participationMode,
            selectedInnovationLevel: request.innovationLevel,
            poolCount: selectedPoolPlan.count,
            laneCount: selectedLanes.count,
            poolPlan: selectedPoolPlan,
            seatCap: governor.seatCap,
            blockRiskScore: blockRiskScore,
            estimatedMergeCost: estimatedMergeCost,
            decisionExplain: explain,
            decision: governor.decision,
            denyCode: governor.denyCode,
            auditRef: request.auditRef
        )

        return AdaptivePoolPlanningResult(
            decision: decision,
            seatGovernor: governor,
            selectedLaneIDs: selectedLanes.map(\ .laneId),
            selectedPoolIDs: selectedPoolPlan.map(\ .poolID),
            blockedIssues: []
        )
    }

    private func deniedDecision(
        request: SupervisorOneShotIntakeRequest,
        complexityScore: Double,
        riskSurface: OneShotRiskSurface,
        selectedProfile: OneShotSplitProfile,
        explain: [String],
        denyCode: String
    ) -> AdaptivePoolPlanDecision {
        AdaptivePoolPlanDecision(
            schemaVersion: "xt.adaptive_pool_plan_decision.v1",
            projectID: request.projectID,
            requestID: request.requestID,
            complexityScore: complexityScore,
            riskSurface: riskSurface,
            selectedProfile: selectedProfile,
            selectedParticipationMode: request.participationMode,
            selectedInnovationLevel: request.innovationLevel,
            poolCount: 0,
            laneCount: 0,
            poolPlan: [],
            seatCap: 0,
            blockRiskScore: 1,
            estimatedMergeCost: 1,
            decisionExplain: explain,
            decision: .deny,
            denyCode: denyCode,
            auditRef: request.auditRef
        )
    }

    private func normalizedComplexityScore(_ raw: Double) -> Double {
        let normalized = raw > 1 ? raw / 100.0 : raw
        return max(0, min(1, normalized))
    }

    private func resolveSelectedProfile(
        _ requestedProfile: OneShotSplitProfile,
        riskSurface: OneShotRiskSurface,
        complexityScore: Double,
        budgetClass: OneShotTokenBudgetClass,
        participationMode: DeliveryParticipationMode
    ) -> OneShotSplitProfile {
        switch requestedProfile {
        case .conservative, .balanced:
            return requestedProfile
        case .aggressive:
            if riskSurface >= .high || budgetClass == .tight || participationMode == .criticalTouch {
                return .balanced
            }
            return .aggressive
        case .auto:
            if riskSurface >= .high || budgetClass == .tight || participationMode == .criticalTouch {
                return .conservative
            }
            if complexityScore >= 0.75 && budgetClass == .priorityDelivery {
                return .aggressive
            }
            return .balanced
        }
    }

    private func deriveRiskSurface(
        request: SupervisorOneShotIntakeRequest,
        buildResult: SplitProposalBuildResult
    ) -> OneShotRiskSurface {
        var risk = mapAnalysisRisk(buildResult.decomposition.analysis.riskLevel)
        if request.requiresHumanAuthorizationTypes.contains(.payment) {
            risk = max(risk, .critical)
        }
        if request.requiresHumanAuthorizationTypes.contains(.secretBinding) || request.requiresHumanAuthorizationTypes.contains(.connectorBinding) {
            risk = max(risk, .high)
        }
        if request.requiresHumanAuthorizationTypes.contains(.externalSideEffect) || request.allowAutoLaunch {
            risk = max(risk, .high)
        }
        if buildResult.proposal.lanes.contains(where: { $0.riskTier == .critical }) {
            risk = .critical
        }
        return risk
    }

    private func mapAnalysisRisk(_ risk: RiskLevel) -> OneShotRiskSurface {
        switch risk {
        case .low:
            return .low
        case .medium:
            return .medium
        case .high:
            return .high
        case .critical:
            return .critical
        }
    }

    private func requestedPoolPlan(
        for lanes: [SplitLaneProposal],
        profile: OneShotSplitProfile,
        riskSurface: OneShotRiskSurface
    ) -> [AdaptivePoolPlanPoolEntry] {
        var mainline: [SplitLaneProposal] = []
        var isolated: [SplitLaneProposal] = []

        for lane in lanes {
            if shouldIsolateLane(lane, profile: profile, riskSurface: riskSurface) {
                isolated.append(lane)
            } else {
                mainline.append(lane)
            }
        }

        var pools: [AdaptivePoolPlanPoolEntry] = []
        if !mainline.isEmpty {
            pools.append(
                AdaptivePoolPlanPoolEntry(
                    poolID: "xt-main",
                    purpose: "mainline_delivery",
                    laneIDs: mainline.map(\ .laneId),
                    requiresIsolation: false
                )
            )
        }
        if !isolated.isEmpty {
            let poolID = pools.isEmpty ? "xt-main" : "xt-risk-isolation"
            pools.append(
                AdaptivePoolPlanPoolEntry(
                    poolID: poolID,
                    purpose: pools.isEmpty ? "isolated_mainline_delivery" : "risk_isolation",
                    laneIDs: isolated.map(\ .laneId),
                    requiresIsolation: true
                )
            )
        }
        return pools
    }

    private func approvedPoolPlan(
        from lanes: [SplitLaneProposal],
        requestedPoolPlan: [AdaptivePoolPlanPoolEntry],
        approvedPoolCount: Int,
        selectedProfile: OneShotSplitProfile,
        riskSurface: OneShotRiskSurface
    ) -> [AdaptivePoolPlanPoolEntry] {
        guard approvedPoolCount > 0 else { return [] }
        if approvedPoolCount == 1 {
            return [
                AdaptivePoolPlanPoolEntry(
                    poolID: "xt-main",
                    purpose: "mainline_delivery",
                    laneIDs: lanes.map(\ .laneId),
                    requiresIsolation: false
                )
            ]
        }
        let laneIDs = Set(lanes.map(\ .laneId))
        let filtered = requestedPoolPlan.compactMap { pool -> AdaptivePoolPlanPoolEntry? in
            let selectedIDs = pool.laneIDs.filter { laneIDs.contains($0) }
            guard !selectedIDs.isEmpty else { return nil }
            return AdaptivePoolPlanPoolEntry(
                poolID: pool.poolID,
                purpose: pool.purpose,
                laneIDs: selectedIDs,
                requiresIsolation: pool.requiresIsolation
            )
        }
        if filtered.isEmpty {
            return self.requestedPoolPlan(for: lanes, profile: selectedProfile, riskSurface: riskSurface)
        }
        return Array(filtered.prefix(approvedPoolCount))
    }

    private func shouldIsolateLane(
        _ lane: SplitLaneProposal,
        profile: OneShotSplitProfile,
        riskSurface: OneShotRiskSurface
    ) -> Bool {
        if lane.createChildProject || lane.riskTier >= .high {
            return true
        }
        if riskSurface >= .high && lane.riskTier >= .medium {
            return true
        }
        if profile == .aggressive && lane.budgetClass >= .premium {
            return true
        }
        return false
    }

    private func computeBlockRiskScore(
        riskSurface: OneShotRiskSurface,
        complexityScore: Double,
        lanes: [SplitLaneProposal]
    ) -> Double {
        let baseRisk: Double
        switch riskSurface {
        case .low:
            baseRisk = 0.18
        case .medium:
            baseRisk = 0.36
        case .high:
            baseRisk = 0.68
        case .critical:
            baseRisk = 0.92
        }
        let dependencyScore = dependencyDensity(for: lanes)
        let widthPenalty = min(0.15, Double(max(0, lanes.count - 3)) * 0.04)
        return max(0, min(1, baseRisk * 0.5 + complexityScore * 0.3 + dependencyScore * 0.2 + widthPenalty))
    }

    private func computeEstimatedMergeCost(
        poolPlan: [AdaptivePoolPlanPoolEntry],
        selectedLaneCount: Int,
        complexityScore: Double,
        dependencyDensity: Double
    ) -> Double {
        let poolPenalty = min(0.4, Double(max(0, poolPlan.count - 1)) * 0.2)
        let lanePenalty = min(0.25, Double(max(0, selectedLaneCount - 2)) * 0.05)
        return max(0, min(1, complexityScore * 0.4 + dependencyDensity * 0.35 + poolPenalty + lanePenalty))
    }

    private func dependencyDensity(for lanes: [SplitLaneProposal]) -> Double {
        guard lanes.count > 1 else { return 0 }
        let dependencyCount = lanes.reduce(0) { $0 + $1.dependsOn.count }
        let denominator = max(1, lanes.count * (lanes.count - 1))
        return min(1, Double(dependencyCount) / Double(denominator))
    }

    private func buildExplain(
        request: SupervisorOneShotIntakeRequest,
        orderedLanes: [SplitLaneProposal],
        selectedProfile: OneShotSplitProfile,
        riskSurface: OneShotRiskSurface,
        requestedPoolPlan: [AdaptivePoolPlanPoolEntry],
        governor: OneShotSeatGovernorDecision,
        validationIssues: [String],
        crossPoolCycleDetected: Bool
    ) -> [String] {
        var explain: [String] = []
        let density = dependencyDensity(for: orderedLanes)
        if density >= 0.15 {
            explain.append("dependency_density_high")
        }
        if riskSurface >= .high || !request.requiresHumanAuthorizationTypes.isEmpty {
            explain.append("sensitive_side_effect_detected")
        }
        if requestedPoolPlan.count > 1 || orderedLanes.count >= 4 {
            explain.append("requires_parallel_contract_and_ui_tracks")
        }
        if selectedProfile != request.preferredSplitProfile && request.preferredSplitProfile != .auto {
            explain.append("preferred_profile_downgraded_for_risk")
        }
        if governor.laneExplosionPrevented {
            explain.append("lane_cap_applied")
        }
        if governor.approvedPoolCount < governor.requestedPoolCount {
            explain.append("pool_cap_applied")
        }
        if governor.unsafeAutoLaunchPrevented {
            explain.append("unsafe_auto_launch_fail_closed")
        }
        if crossPoolCycleDetected {
            explain.append("cross_pool_cycle_detected")
        }
        if !validationIssues.isEmpty {
            explain.append("split_proposal_blocking_issue")
        }
        if explain.isEmpty {
            explain.append("balanced_mainline_plan_selected")
        }
        return oneShotOrderedUniqueStrings(explain + governor.decisionExplain)
    }

    private func hasCrossPoolCycle(
        poolPlan: [AdaptivePoolPlanPoolEntry],
        lanes: [SplitLaneProposal]
    ) -> Bool {
        guard poolPlan.count > 1 else { return false }
        let poolByLaneID = Dictionary(uniqueKeysWithValues: poolPlan.flatMap { pool in
            pool.laneIDs.map { ($0, pool.poolID) }
        })
        let laneByID = Dictionary(uniqueKeysWithValues: lanes.map { ($0.laneId, $0) })
        var graph: [String: Set<String>] = [:]
        for pool in poolPlan {
            graph[pool.poolID, default: []] = []
        }

        for lane in lanes {
            guard let fromPool = poolByLaneID[lane.laneId] else { continue }
            for dependency in lane.dependsOn {
                guard let dependencyLane = laneByID[dependency], let toPool = poolByLaneID[dependencyLane.laneId] else {
                    continue
                }
                if fromPool != toPool {
                    graph[fromPool, default: []].insert(toPool)
                }
            }
        }

        var visiting: Set<String> = []
        var visited: Set<String> = []

        func dfs(_ node: String) -> Bool {
            if visiting.contains(node) {
                return true
            }
            if visited.contains(node) {
                return false
            }
            visiting.insert(node)
            for next in (graph[node] ?? []).sorted() {
                if dfs(next) {
                    return true
                }
            }
            visiting.remove(node)
            visited.insert(node)
            return false
        }

        for node in graph.keys.sorted() {
            if dfs(node) {
                return true
            }
        }
        return false
    }

    private func topologicallyOrderedLanes(_ lanes: [SplitLaneProposal]) -> [SplitLaneProposal]? {
        let laneByID = Dictionary(uniqueKeysWithValues: lanes.map { ($0.laneId, $0) })
        var inDegree = Dictionary(uniqueKeysWithValues: lanes.map { ($0.laneId, $0.dependsOn.count) })
        var dependents: [String: Set<String>] = [:]

        for lane in lanes {
            for dependency in lane.dependsOn {
                dependents[dependency, default: []].insert(lane.laneId)
            }
        }

        var queue = inDegree.filter { $0.value == 0 }.map(\ .key).sorted()
        var ordered: [SplitLaneProposal] = []

        while !queue.isEmpty {
            let nextID = queue.removeFirst()
            guard let nextLane = laneByID[nextID] else { continue }
            ordered.append(nextLane)
            for dependent in (dependents[nextID] ?? []).sorted() {
                inDegree[dependent, default: 0] -= 1
                if inDegree[dependent] == 0 {
                    queue.append(dependent)
                    queue.sort()
                }
            }
        }

        guard ordered.count == lanes.count else {
            return nil
        }
        return ordered
    }
}
