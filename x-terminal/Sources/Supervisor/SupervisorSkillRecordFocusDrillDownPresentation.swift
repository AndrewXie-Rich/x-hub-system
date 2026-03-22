import Foundation

enum SupervisorSkillRecordFocusDrillDownPresentation {
    enum Outcome: Equatable {
        case recentActivity(SupervisorManager.SupervisorRecentSkillActivity)
        case fallbackRecord(projectId: String, projectName: String, record: SupervisorSkillFullRecord)
        case refreshNeeded
        case noMatch
    }

    static func resolve(
        resolution: SupervisorFocusPresentation.SkillRecordResolution,
        fallbackProjectName: String?,
        fallbackRecord: SupervisorSkillFullRecord?
    ) -> Outcome {
        if let matchedActivity = resolution.matchedActivity {
            return .recentActivity(matchedActivity)
        }

        if let fallbackProjectId = normalizedScalar(resolution.fallbackProjectId),
           let fallbackRecord {
            let projectName = normalizedScalar(fallbackProjectName) ?? fallbackProjectId
            return .fallbackRecord(
                projectId: fallbackProjectId,
                projectName: projectName,
                record: fallbackRecord
            )
        }

        if resolution.refreshRecentSkillActivities {
            return .refreshNeeded
        }

        return .noMatch
    }

    private static func normalizedScalar(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
