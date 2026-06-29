import Foundation

extension SupervisorManager {
    struct BlockerSignal {
        var streak: Int
        var escalated: Bool
        var cooldownRemainingSec: Int
    }

    enum HeartbeatAutoProgressKind: String {
        case recover
        case start
    }

    struct HeartbeatAutoProgressAction {
        var kind: HeartbeatAutoProgressKind
        var projectId: String
        var projectName: String
        var detail: String
        var runId: String?

        var summaryLine: String {
            switch kind {
            case .recover:
                if let runId, !runId.isEmpty {
                    return "• 主动恢复：\(projectName) — \(detail)（run_id=\(runId)）"
                }
                return "• 主动恢复：\(projectName) — \(detail)"
            case .start:
                if let runId, !runId.isEmpty {
                    return "• 主动启动：\(projectName) — \(detail)（run_id=\(runId)）"
                }
                return "• 主动启动：\(projectName) — \(detail)"
            }
        }
    }

    struct ProjectQueueSignal {
        var project: AXProjectEntry
        var inFlight: Int
        var queued: Int
        var oldestQueuedMs: Int
    }

    struct PendingGrantIngressContext {
        var provider: String
        var ingress: String
        var receiptId: String
    }

    enum PermissionSignalKind: String {
        case toolApproval = "tool_approval"
        case hubGrant = "hub_grant"
        case supervisorSkillApproval = "supervisor_skill_approval"
    }

    struct ProjectPermissionSignal {
        var projectId: String
        var projectName: String
        var kind: PermissionSignalKind
        var summary: String
        var createdAt: TimeInterval?
        var grantRequestId: String?
        var capability: String?
        var actionURL: String?
    }

    struct ProjectGovernanceRepairSignal {
        var projectId: String
        var projectName: String
        var summary: String
        var destination: XTProjectGovernanceDestination
        var blockedSummary: String?
        var policyReason: String?
        var governanceReason: String?
        var governanceTruth: String?
        var updatedAt: TimeInterval?
        var actionURL: String?
    }
}
