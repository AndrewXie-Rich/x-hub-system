import Foundation

enum MessageTimelineFocusPresentation {
    static let projectSkillActivitySectionAnchorID = "project-skill-activity-section"

    static func normalizedRequestID(_ requestID: String?) -> String? {
        guard let trimmed = requestID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    static func projectSkillActivityAnchorID(requestID: String) -> String {
        let normalized = normalizedRequestID(requestID) ?? requestID
        return "project-skill-activity-\(normalized)"
    }

    static func mergedRecentSkillActivities(
        items: [ProjectSkillActivityItem],
        focusedItem: ProjectSkillActivityItem?
    ) -> [ProjectSkillActivityItem] {
        var latestByRequestID: [String: ProjectSkillActivityItem] = [:]

        func merge(_ item: ProjectSkillActivityItem) {
            let requestID = item.requestID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !requestID.isEmpty else { return }

            if let existing = latestByRequestID[requestID] {
                if item.createdAt > existing.createdAt
                    || (item.createdAt == existing.createdAt && item.requestID > existing.requestID) {
                    latestByRequestID[requestID] = item
                }
            } else {
                latestByRequestID[requestID] = item
            }
        }

        for item in items {
            merge(item)
        }
        if let focusedItem {
            merge(focusedItem)
        }

        return latestByRequestID.values.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.requestID > rhs.requestID
        }
    }

    static func projectSkillActivityAnchor(
        requestID: String?,
        in items: [ProjectSkillActivityItem]
    ) -> String? {
        guard !items.isEmpty else { return nil }
        guard let normalizedRequestID = normalizedRequestID(requestID) else {
            return projectSkillActivitySectionAnchorID
        }
        if items.contains(where: { $0.requestID == normalizedRequestID }) {
            return projectSkillActivityAnchorID(requestID: normalizedRequestID)
        }
        return projectSkillActivitySectionAnchorID
    }
}
