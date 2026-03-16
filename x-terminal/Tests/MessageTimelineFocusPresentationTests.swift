import Foundation
import Testing
@testable import XTerminal

struct MessageTimelineFocusPresentationTests {

    @Test
    func anchorUsesFocusedActivityWhenPresent() {
        let items = [
            activityItem(requestID: "req-1", createdAt: 20),
            activityItem(requestID: "req-2", createdAt: 10)
        ]

        let anchor = MessageTimelineFocusPresentation.projectSkillActivityAnchor(
            requestID: "req-1",
            in: items
        )

        #expect(anchor == "project-skill-activity-req-1")
    }

    @Test
    func anchorFallsBackToSectionWhenFocusedActivityMissingOrBlank() {
        let items = [
            activityItem(requestID: "req-1", createdAt: 20)
        ]

        let blankAnchor = MessageTimelineFocusPresentation.projectSkillActivityAnchor(
            requestID: "   ",
            in: items
        )
        let missingAnchor = MessageTimelineFocusPresentation.projectSkillActivityAnchor(
            requestID: "req-404",
            in: items
        )

        #expect(blankAnchor == MessageTimelineFocusPresentation.projectSkillActivitySectionAnchorID)
        #expect(missingAnchor == MessageTimelineFocusPresentation.projectSkillActivitySectionAnchorID)
    }

    @Test
    func mergedRecentActivitiesIncludesFocusedItemOutsideRecentWindow() {
        let baseItems = (0..<8).map { index in
            activityItem(
                requestID: "recent-\(index)",
                createdAt: Double(100 - index)
            )
        }
        let focusedItem = activityItem(requestID: "older-focus", createdAt: 1)

        let merged = MessageTimelineFocusPresentation.mergedRecentSkillActivities(
            items: baseItems,
            focusedItem: focusedItem
        )

        #expect(merged.count == 9)
        #expect(merged.contains(where: { $0.requestID == "older-focus" }))
        #expect(merged.first?.requestID == "recent-0")
        #expect(merged.last?.requestID == "older-focus")
    }

    @Test
    func mergedRecentActivitiesDeduplicatesFocusedItemByRequestID() {
        let baseItem = activityItem(requestID: "req-1", createdAt: 10, detail: "older")
        let focusedItem = activityItem(requestID: "req-1", createdAt: 20, detail: "newer")

        let merged = MessageTimelineFocusPresentation.mergedRecentSkillActivities(
            items: [baseItem],
            focusedItem: focusedItem
        )

        #expect(merged.count == 1)
        #expect(merged.first?.requestID == "req-1")
        #expect(merged.first?.detail == "newer")
    }

    private func activityItem(
        requestID: String,
        createdAt: Double,
        detail: String = ""
    ) -> ProjectSkillActivityItem {
        ProjectSkillActivityItem(
            requestID: requestID,
            skillID: "skill.demo",
            toolName: "run_command",
            status: "awaiting_approval",
            createdAt: createdAt,
            resolutionSource: "local",
            toolArgs: [:],
            resultSummary: "",
            detail: detail,
            denyCode: "",
            authorizationDisposition: "pending",
            policySource: "",
            policyReason: ""
        )
    }
}
