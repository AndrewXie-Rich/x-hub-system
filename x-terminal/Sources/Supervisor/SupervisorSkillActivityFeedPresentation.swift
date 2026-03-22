import Foundation

struct SupervisorSkillActivityFeedPresentation: Equatable {
    var summaryLine: String
    var items: [SupervisorManager.SupervisorRecentSkillActivity]
    var actionableCount: Int

    var isEmpty: Bool {
        items.isEmpty
    }

    static func map(
        items: [SupervisorManager.SupervisorRecentSkillActivity],
        limit: Int? = nil
    ) -> SupervisorSkillActivityFeedPresentation {
        let sorted = items.sorted { lhs, rhs in
            let leftPriority = sortPriority(for: lhs)
            let rightPriority = sortPriority(for: rhs)
            if leftPriority != rightPriority { return leftPriority < rightPriority }

            let leftUpdated = lhs.updatedAt ?? 0
            let rightUpdated = rhs.updatedAt ?? 0
            if leftUpdated != rightUpdated { return leftUpdated > rightUpdated }

            let leftCreated = lhs.createdAt ?? 0
            let rightCreated = rhs.createdAt ?? 0
            if leftCreated != rightCreated { return leftCreated > rightCreated }

            if lhs.projectName != rhs.projectName {
                return lhs.projectName.localizedCaseInsensitiveCompare(rhs.projectName) == .orderedAscending
            }
            if lhs.skillId != rhs.skillId {
                return lhs.skillId.localizedCaseInsensitiveCompare(rhs.skillId) == .orderedAscending
            }
            return lhs.requestId.localizedCaseInsensitiveCompare(rhs.requestId) == .orderedAscending
        }

        let displayedItems: [SupervisorManager.SupervisorRecentSkillActivity]
        if let limit, limit > 0 {
            displayedItems = Array(sorted.prefix(limit))
        } else {
            displayedItems = sorted
        }

        let localApprovalCount = items.filter(isAwaitingLocalApproval).count
        let hubGrantCount = items.filter(isAwaitingHubGrant).count
        let recoveryCount = items.filter(isRecoveryCandidate).count
        let runningCount = items.filter { normalizedStatus($0.status) == "running" }.count
        let queuedCount = items.filter { normalizedStatus($0.status) == "queued" }.count
        let completedCount = items.filter { normalizedStatus($0.status) == "completed" }.count
        let actionableCount = localApprovalCount + hubGrantCount + recoveryCount

        var tokens: [String] = []
        if actionableCount > 0 {
            tokens.append("可处理 \(actionableCount)")
        }
        if localApprovalCount > 0 {
            tokens.append("本地审批 \(localApprovalCount)")
        }
        if hubGrantCount > 0 {
            tokens.append("Hub 授权 \(hubGrantCount)")
        }
        if recoveryCount > 0 {
            tokens.append("待恢复 \(recoveryCount)")
        }
        if runningCount > 0 {
            tokens.append("进行中 \(runningCount)")
        }

        if tokens.isEmpty {
            if queuedCount > 0 {
                tokens.append("排队中 \(queuedCount)")
            }
            if completedCount > 0 {
                tokens.append("已完成 \(completedCount)")
            }
        }

        return SupervisorSkillActivityFeedPresentation(
            summaryLine: tokens.isEmpty ? "最近活动" : tokens.joined(separator: " · "),
            items: displayedItems,
            actionableCount: actionableCount
        )
    }

    private static func sortPriority(
        for item: SupervisorManager.SupervisorRecentSkillActivity
    ) -> Int {
        if isAwaitingLocalApproval(item) { return 0 }
        if isAwaitingHubGrant(item) { return 1 }

        switch normalizedStatus(item.status) {
        case "failed":
            return 2
        case "blocked":
            return 3
        case "canceled":
            return 4
        case "running":
            return 5
        case "queued":
            return 6
        case "completed":
            return 7
        default:
            return 8
        }
    }

    private static func isAwaitingLocalApproval(
        _ item: SupervisorManager.SupervisorRecentSkillActivity
    ) -> Bool {
        normalizedStatus(item.status) == "awaiting_authorization"
            && item.requiredCapability.isEmpty
    }

    private static func isAwaitingHubGrant(
        _ item: SupervisorManager.SupervisorRecentSkillActivity
    ) -> Bool {
        normalizedStatus(item.status) == "awaiting_authorization"
            && !item.requiredCapability.isEmpty
    }

    private static func isRecoveryCandidate(
        _ item: SupervisorManager.SupervisorRecentSkillActivity
    ) -> Bool {
        switch normalizedStatus(item.status) {
        case "failed", "blocked", "canceled":
            return true
        default:
            return false
        }
    }

    private static func normalizedStatus(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
