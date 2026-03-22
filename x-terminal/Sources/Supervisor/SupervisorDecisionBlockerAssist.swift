import Foundation

enum SupervisorDecisionBlockerCategory: String, Codable, Sendable, CaseIterable {
    case techStack = "tech_stack"
    case scaffold
    case testStack = "test_stack"
    case docTemplate = "doc_template"
    case security
    case releaseScope = "release_scope"
    case irreversibleOperation = "irreversible_operation"
    case other
}

enum SupervisorDecisionBlockerRiskLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case low
    case medium
    case high
    case critical

    private var rank: Int {
        switch self {
        case .low:
            return 0
        case .medium:
            return 1
        case .high:
            return 2
        case .critical:
            return 3
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rank < rhs.rank
    }
}

enum SupervisorDecisionBlockerGovernanceMode: String, Codable, Sendable, CaseIterable {
    case proposalOnly = "proposal_only"
    case proposalWithTimeoutEscalation = "proposal_with_timeout_escalation"
    case autoAdoptIfPolicyAllows = "auto_adopt_if_policy_allows"
}

enum SupervisorDecisionBlockerApprovalState: String, Codable, Sendable {
    case proposalPending = "proposal_pending"
    case approved
    case denied
}

struct SupervisorDecisionProposalTemplate: Identifiable, Equatable, Codable, Sendable {
    var id: String
    var category: SupervisorDecisionBlockerCategory
    var title: String
    var summary: String
    var reversible: Bool
    var evidenceRefs: [String]
}

struct SupervisorDecisionBlockerContext: Equatable, Sendable {
    var projectId: String
    var blockerId: String
    var blockerType: String
    var category: SupervisorDecisionBlockerCategory
    var reversible: Bool
    var riskLevel: SupervisorDecisionBlockerRiskLevel
    var touchesSecurity: Bool
    var touchesReleaseScope: Bool
    var requiresHubAuthorization: Bool
    var explicitApprovalGranted: Bool
    var allowAutoAdoptWhenPolicyAllows: Bool
    var timeoutEscalationAfterMs: Int64?
    var evidenceRefs: [String]

    init(
        projectId: String,
        blockerId: String,
        blockerType: String = "decision",
        category: SupervisorDecisionBlockerCategory,
        reversible: Bool,
        riskLevel: SupervisorDecisionBlockerRiskLevel,
        touchesSecurity: Bool = false,
        touchesReleaseScope: Bool = false,
        requiresHubAuthorization: Bool = false,
        explicitApprovalGranted: Bool = false,
        allowAutoAdoptWhenPolicyAllows: Bool = false,
        timeoutEscalationAfterMs: Int64? = nil,
        evidenceRefs: [String] = []
    ) {
        self.projectId = projectId
        self.blockerId = blockerId
        self.blockerType = blockerType
        self.category = category
        self.reversible = reversible
        self.riskLevel = riskLevel
        self.touchesSecurity = touchesSecurity
        self.touchesReleaseScope = touchesReleaseScope
        self.requiresHubAuthorization = requiresHubAuthorization
        self.explicitApprovalGranted = explicitApprovalGranted
        self.allowAutoAdoptWhenPolicyAllows = allowAutoAdoptWhenPolicyAllows
        self.timeoutEscalationAfterMs = timeoutEscalationAfterMs
        self.evidenceRefs = evidenceRefs
    }
}

struct SupervisorDecisionBlockerAssist: Equatable, Codable, Sendable {
    static let schemaVersion = "xt.supervisor_decision_blocker_assist.v1"

    var schemaVersion: String
    var projectId: String
    var blockerId: String
    var blockerType: String
    var blockerCategory: SupervisorDecisionBlockerCategory
    var templateCandidates: [String]
    var recommendedOption: String?
    var reversible: Bool
    var riskLevel: SupervisorDecisionBlockerRiskLevel
    var governanceMode: SupervisorDecisionBlockerGovernanceMode
    var timeoutEscalationAfterMs: Int64?
    var autoAdoptAllowed: Bool
    var requiresUserDecision: Bool
    var approvalState: SupervisorDecisionBlockerApprovalState
    var failClosed: Bool
    var policyReasons: [String]
    var explanation: String
    var auditRef: String
    var evidenceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectId = "project_id"
        case blockerId = "blocker_id"
        case blockerType = "blocker_type"
        case blockerCategory = "blocker_category"
        case templateCandidates = "template_candidates"
        case recommendedOption = "recommended_option"
        case reversible
        case riskLevel = "risk_level"
        case governanceMode = "governance_mode"
        case timeoutEscalationAfterMs = "timeout_escalation_after_ms"
        case autoAdoptAllowed = "auto_adopt_allowed"
        case requiresUserDecision = "requires_user_decision"
        case approvalState = "approval_state"
        case failClosed = "fail_closed"
        case policyReasons = "policy_reasons"
        case explanation
        case auditRef = "audit_ref"
        case evidenceRefs = "evidence_refs"
    }
}

enum SupervisorDecisionBlockerAssistEngine {
    private static let defaultProposalTimeoutMs: Int64 = 4 * 60 * 60 * 1_000

    static func build(
        context: SupervisorDecisionBlockerContext,
        nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
    ) -> SupervisorDecisionBlockerAssist {
        let templates = templateCatalog(for: context.category)
        let recommendedTemplate = templates.first?.id
        let lowRiskReversible = context.reversible
            && context.riskLevel == .low
            && !context.touchesSecurity
            && !context.touchesReleaseScope
        let failClosedReasons = failClosedReasons(for: context)
        let failClosed = !failClosedReasons.isEmpty

        let governanceMode: SupervisorDecisionBlockerGovernanceMode
        if failClosed {
            governanceMode = .proposalOnly
        } else if lowRiskReversible && context.allowAutoAdoptWhenPolicyAllows {
            governanceMode = .autoAdoptIfPolicyAllows
        } else if lowRiskReversible {
            governanceMode = .proposalWithTimeoutEscalation
        } else {
            governanceMode = .proposalOnly
        }

        let timeoutEscalationAfterMs: Int64?
        switch governanceMode {
        case .proposalWithTimeoutEscalation:
            timeoutEscalationAfterMs = max(context.timeoutEscalationAfterMs ?? defaultProposalTimeoutMs, 1)
        case .proposalOnly, .autoAdoptIfPolicyAllows:
            timeoutEscalationAfterMs = nil
        }

        var policyReasons = failClosedReasons
        if lowRiskReversible {
            policyReasons.append("low_risk_reversible_default_available")
        } else {
            policyReasons.append("manual_review_required_for_non_low_risk_or_non_reversible_decision")
        }
        switch governanceMode {
        case .proposalOnly:
            policyReasons.append("proposal_first_governance")
        case .proposalWithTimeoutEscalation:
            policyReasons.append("proposal_timeout_escalation_enabled")
        case .autoAdoptIfPolicyAllows:
            policyReasons.append("policy_may_auto_adopt_after_separate_governed_execution")
        }
        let uniqueReasons = dedupe(policyReasons)
        let autoAdoptAllowed = governanceMode == .autoAdoptIfPolicyAllows && !failClosed
        let requiresUserDecision = failClosed || governanceMode != .autoAdoptIfPolicyAllows

        return SupervisorDecisionBlockerAssist(
            schemaVersion: SupervisorDecisionBlockerAssist.schemaVersion,
            projectId: context.projectId,
            blockerId: context.blockerId,
            blockerType: context.blockerType,
            blockerCategory: context.category,
            templateCandidates: templates.map(\.id),
            recommendedOption: recommendedTemplate,
            reversible: context.reversible,
            riskLevel: context.riskLevel,
            governanceMode: governanceMode,
            timeoutEscalationAfterMs: timeoutEscalationAfterMs,
            autoAdoptAllowed: autoAdoptAllowed,
            requiresUserDecision: requiresUserDecision,
            approvalState: .proposalPending,
            failClosed: failClosed,
            policyReasons: uniqueReasons,
            explanation: explanation(
                context: context,
                recommendedTemplate: recommendedTemplate,
                governanceMode: governanceMode,
                failClosedReasons: failClosedReasons
            ),
            auditRef: auditRef(projectId: context.projectId, blockerId: context.blockerId, nowMs: nowMs),
            evidenceRefs: dedupe(context.evidenceRefs + templates.flatMap(\.evidenceRefs))
        )
    }

    static func templateCatalog(for category: SupervisorDecisionBlockerCategory) -> [SupervisorDecisionProposalTemplate] {
        let sharedRefs = [
            "x-terminal/work-orders/xt-w3-33-supervisor-decision-kernel-routing-and-memory-governance-implementation-pack-v1.md",
            "docs/memory-new/xhub-lane-command-board-v2.md"
        ]
        switch category {
        case .techStack:
            return [
                SupervisorDecisionProposalTemplate(
                    id: "swiftui_hub_first_default",
                    category: .techStack,
                    title: "默认采用 SwiftUI + Hub 优先控制面",
                    summary: "默认采用 SwiftUI 界面、Hub 治理记忆和基于角色的路由，作为 XT 的基线技术栈。",
                    reversible: true,
                    evidenceRefs: sharedRefs
                ),
                SupervisorDecisionProposalTemplate(
                    id: "swift_package_modular_default",
                    category: .techStack,
                    title: "默认采用 Swift Package 模块化",
                    summary: "在引入新的运行时依赖前，优先按 Swift Package 级别拆出隔离模块。",
                    reversible: true,
                    evidenceRefs: sharedRefs
                )
            ]
        case .scaffold:
            return [
                SupervisorDecisionProposalTemplate(
                    id: "feature_slice_scaffold_default",
                    category: .scaffold,
                    title: "按功能切片搭脚手架",
                    summary: "每个受治理切片默认配一份源码、一份测试和一份证据产物。",
                    reversible: true,
                    evidenceRefs: sharedRefs
                ),
                SupervisorDecisionProposalTemplate(
                    id: "policy_first_scaffold_default",
                    category: .scaffold,
                    title: "先契约后接线",
                    summary: "先补 contract 和 harness 文件，再接入运行时或界面 wiring。",
                    reversible: true,
                    evidenceRefs: sharedRefs
                )
            ]
        case .testStack:
            return [
                SupervisorDecisionProposalTemplate(
                    id: "swift_testing_contract_default",
                    category: .testStack,
                    title: "默认用 Swift Testing 覆盖契约",
                    summary: "纯策略路径优先用 Swift Testing 覆盖，保持无运行时依赖且断言稳定可复现。",
                    reversible: true,
                    evidenceRefs: sharedRefs
                ),
                SupervisorDecisionProposalTemplate(
                    id: "node_generator_regression_default",
                    category: .testStack,
                    title: "默认补 Node 生成器回归",
                    summary: "用机器可读的 Node 测试和 fail-closed fixture 校验 require-real 报告生成。",
                    reversible: true,
                    evidenceRefs: sharedRefs
                )
            ]
        case .docTemplate:
            return [
                SupervisorDecisionProposalTemplate(
                    id: "action_first_doc_template_default",
                    category: .docTemplate,
                    title: "行动优先文档模板",
                    summary: "文档优先写范围、改动、验证、产物、风险和下一步，而不是叙述式状态汇报。",
                    reversible: true,
                    evidenceRefs: sharedRefs
                ),
                SupervisorDecisionProposalTemplate(
                    id: "audit_appendix_doc_template_default",
                    category: .docTemplate,
                    title: "默认追加审计附录",
                    summary: "把审计和证据引用集中放在报告尾部，而不是混进正文。",
                    reversible: true,
                    evidenceRefs: sharedRefs
                )
            ]
        case .security, .releaseScope, .irreversibleOperation, .other:
            return []
        }
    }

    private static func failClosedReasons(for context: SupervisorDecisionBlockerContext) -> [String] {
        var reasons: [String] = []
        if !context.reversible {
            reasons.append("irreversible_decision_requires_manual_approval")
        }
        if context.riskLevel >= .high {
            reasons.append("high_risk_decision_requires_manual_approval")
        }
        if context.touchesSecurity || context.category == .security {
            reasons.append("security_scope_must_fail_closed")
        }
        if context.touchesReleaseScope || context.category == .releaseScope {
            reasons.append("release_scope_change_must_fail_closed")
        }
        if context.requiresHubAuthorization && !context.explicitApprovalGranted {
            reasons.append("hub_or_user_authorization_missing")
        }
        return reasons
    }

    private static func explanation(
        context: SupervisorDecisionBlockerContext,
        recommendedTemplate: String?,
        governanceMode: SupervisorDecisionBlockerGovernanceMode,
        failClosedReasons: [String]
    ) -> String {
        if !failClosedReasons.isEmpty {
            return "Generated proposal-only assist because \(failClosedReasons.joined(separator: ", ")). Recommended option stays unapproved: \(recommendedTemplate ?? "none")."
        }
        switch governanceMode {
        case .proposalOnly:
            return "Generated proposal-only assist because the blocker is outside the low-risk reversible default set."
        case .proposalWithTimeoutEscalation:
            return "Generated reversible low-risk proposal with timeout escalation; the recommendation remains pending until an explicit governed adoption step occurs."
        case .autoAdoptIfPolicyAllows:
            return "Generated reversible low-risk proposal that may be auto-adopted by a separate governed executor, but this assist itself does not mark the decision approved."
        }
    }

    private static func auditRef(projectId: String, blockerId: String, nowMs: Int64) -> String {
        "supervisor_decision_blocker_assist:\(normalizedToken(projectId)):\(normalizedToken(blockerId)):\(max(nowMs, 0))"
    }

    private static func normalizedToken(_ raw: String) -> String {
        let filtered = raw.lowercased().map { character -> Character in
            if character.isLetter || character.isNumber {
                return character
            }
            return "_"
        }
        return String(filtered).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private static func dedupe(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else {
                continue
            }
            ordered.append(trimmed)
        }
        return ordered
    }
}
