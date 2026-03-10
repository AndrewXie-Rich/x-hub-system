import Foundation

/// Split flow 快照接口（供 AI-XT-2 / UI / Gate 以稳定字段读取当前提案态）
struct SplitFlowSnapshot: Codable, Equatable {
    static let schema = "xterminal.split_flow_snapshot"
    static let version = "1"

    var schema: String = Self.schema
    var version: String = Self.version
    var stateMachineVersion: String = SplitProposalFlowState.stateMachineVersion

    var splitPlanId: UUID?
    var flowState: SplitProposalFlowState
    var laneCount: Int
    var recommendedConcurrency: Int?
    var tokenBudgetTotal: Int?

    var splitBlockingIssueCodes: [String]
    var promptStatus: PromptCompilationStatus?
    var promptCoverage: Double?
    var promptBlockingLintCodes: [String]

    var overrideCount: Int
    var overrideLaneIDs: [String]
    var replayConsistent: Bool?

    var lastAuditEventType: SplitAuditEventType?
    var lastAuditAt: Date?
}

@MainActor
extension SupervisorOrchestrator {
    /// AI-XT-2 消费入口：导出当前 split/confirm/override 流程的稳定快照。
    func splitFlowSnapshot() -> SplitFlowSnapshot {
        let splitBlockingIssueCodes = (splitProposalValidation?.blockingIssues.map(\.code) ?? []).sorted()
        let promptBlockingLintCodes = (promptCompilationResult?.lintResult.blockingIssues.map(\.code) ?? []).sorted()

        let overrideLaneIDs = Array(Set(splitOverrideHistory.map(\.laneId))).sorted()
        let promptCoverage = promptCompilationResult?.coverage

        return SplitFlowSnapshot(
            splitPlanId: activeSplitProposal?.splitPlanId,
            flowState: splitProposalState,
            laneCount: activeSplitProposal?.lanes.count ?? 0,
            recommendedConcurrency: activeSplitProposal?.recommendedConcurrency,
            tokenBudgetTotal: activeSplitProposal?.tokenBudgetTotal,
            splitBlockingIssueCodes: splitBlockingIssueCodes,
            promptStatus: promptCompilationResult?.status,
            promptCoverage: promptCoverage,
            promptBlockingLintCodes: promptBlockingLintCodes,
            overrideCount: splitOverrideHistory.count,
            overrideLaneIDs: overrideLaneIDs,
            replayConsistent: splitOverrideReplayConsistent,
            lastAuditEventType: splitAuditTrail.last?.eventType,
            lastAuditAt: splitAuditTrail.last?.at
        )
    }
}
