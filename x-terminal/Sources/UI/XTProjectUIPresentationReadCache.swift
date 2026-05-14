import Foundation

@MainActor
enum XTProjectUIPresentationReadCache {
    private struct SessionSummaryEntry {
        let loadedAt: Date
        let value: AXSessionSummaryCapsulePresentation?
    }

    private struct UIReviewEntry {
        let loadedAt: Date
        let value: XTUIReviewPresentation?
    }

    private struct ContextDiagnosticsEntry {
        let loadedAt: Date
        let value: AXProjectContextAssemblyDiagnosticsSummary
    }

    private struct RouteRepairDigestEntry {
        let loadedAt: Date
        let value: AXRouteRepairLogDigest
    }

    private struct GovernancePresentationEntry {
        let loadedAt: Date
        let value: ProjectGovernancePresentation
    }

    private struct GovernanceTemplatePreviewEntry {
        let loadedAt: Date
        let value: AXProjectGovernanceTemplatePreview
    }

    private struct RoleExecutionSnapshotEntry {
        let loadedAt: Date
        let value: AXRoleExecutionSnapshot
    }

    private struct RecentSkillActivitiesEntry {
        let loadedAt: Date
        let value: [ProjectSkillActivityItem]
    }

    private struct LatestGovernanceInterceptionEntry {
        let loadedAt: Date
        let value: ProjectGovernanceInterceptionPresentation?
    }

    private struct ProjectConfigEntry {
        let loadedAt: Date
        let value: AXProjectConfig?
    }

    private struct LatestRouteEventEntry {
        let loadedAt: Date
        let value: AXModelRouteDiagnosticEvent?
    }

    private static let maxAgeSeconds: TimeInterval = 1.0
    private static let maxEntries = 96
    private static var sessionSummaries: [String: SessionSummaryEntry] = [:]
    private static var uiReviews: [String: UIReviewEntry] = [:]
    private static var contextDiagnostics: [String: ContextDiagnosticsEntry] = [:]
    private static var routeRepairDigests: [String: RouteRepairDigestEntry] = [:]
    private static var governancePresentations: [String: GovernancePresentationEntry] = [:]
    private static var governanceTemplatePreviews: [String: GovernanceTemplatePreviewEntry] = [:]
    private static var roleExecutionSnapshots: [String: RoleExecutionSnapshotEntry] = [:]
    private static var recentSkillActivities: [String: RecentSkillActivitiesEntry] = [:]
    private static var latestGovernanceInterceptions: [String: LatestGovernanceInterceptionEntry] = [:]
    private static var projectConfigs: [String: ProjectConfigEntry] = [:]
    private static var latestRouteEvents: [String: LatestRouteEventEntry] = [:]

    static func sessionSummary(
        for ctx: AXProjectContext,
        now: Date = Date(),
        loader: () -> AXSessionSummaryCapsulePresentation?
    ) -> AXSessionSummaryCapsulePresentation? {
        let key = contextKey(ctx)
        if let entry = sessionSummaries[key], isFresh(entry.loadedAt, now: now) {
            return entry.value
        }
        let value = loader()
        sessionSummaries[key] = SessionSummaryEntry(loadedAt: now, value: value)
        trimSessionSummaries()
        return value
    }

    static func latestUIReview(
        for ctx: AXProjectContext,
        now: Date = Date(),
        loader: () -> XTUIReviewPresentation?
    ) -> XTUIReviewPresentation? {
        let key = contextKey(ctx)
        if let entry = uiReviews[key], isFresh(entry.loadedAt, now: now) {
            return entry.value
        }
        let value = loader()
        uiReviews[key] = UIReviewEntry(loadedAt: now, value: value)
        trimUIReviews()
        return value
    }

    static func contextDiagnostics(
        for ctx: AXProjectContext,
        now: Date = Date(),
        loader: () -> AXProjectContextAssemblyDiagnosticsSummary
    ) -> AXProjectContextAssemblyDiagnosticsSummary {
        let key = contextKey(ctx)
        if let entry = contextDiagnostics[key], isFresh(entry.loadedAt, now: now) {
            return entry.value
        }
        let value = loader()
        contextDiagnostics[key] = ContextDiagnosticsEntry(loadedAt: now, value: value)
        trimContextDiagnostics()
        return value
    }

    static func routeRepairDigest(
        for ctx: AXProjectContext,
        limit: Int,
        now: Date = Date(),
        loader: () -> AXRouteRepairLogDigest
    ) -> AXRouteRepairLogDigest {
        let key = "\(contextKey(ctx))|\(limit)"
        if let entry = routeRepairDigests[key], isFresh(entry.loadedAt, now: now) {
            return entry.value
        }
        let value = loader()
        routeRepairDigests[key] = RouteRepairDigestEntry(loadedAt: now, value: value)
        trimRouteRepairDigests()
        return value
    }

    static func governancePresentation(
        projectId: String,
        now: Date = Date(),
        loader: () -> ProjectGovernancePresentation
    ) -> ProjectGovernancePresentation {
        let key = normalizedProjectKey(projectId)
        if let entry = governancePresentations[key], isFresh(entry.loadedAt, now: now) {
            return entry.value
        }
        let value = loader()
        governancePresentations[key] = GovernancePresentationEntry(loadedAt: now, value: value)
        trimGovernancePresentations()
        return value
    }

    static func governanceTemplatePreview(
        projectId: String,
        now: Date = Date(),
        loader: () -> AXProjectGovernanceTemplatePreview
    ) -> AXProjectGovernanceTemplatePreview {
        let key = normalizedProjectKey(projectId)
        if let entry = governanceTemplatePreviews[key], isFresh(entry.loadedAt, now: now) {
            return entry.value
        }
        let value = loader()
        governanceTemplatePreviews[key] = GovernanceTemplatePreviewEntry(loadedAt: now, value: value)
        trimGovernanceTemplatePreviews()
        return value
    }

    static func roleExecutionSnapshot(
        for ctx: AXProjectContext,
        role: AXRole,
        now: Date = Date(),
        loader: () -> AXRoleExecutionSnapshot
    ) -> AXRoleExecutionSnapshot {
        let key = "\(contextKey(ctx))|\(role.rawValue)"
        if let entry = roleExecutionSnapshots[key], isFresh(entry.loadedAt, now: now) {
            return entry.value
        }
        let value = loader()
        roleExecutionSnapshots[key] = RoleExecutionSnapshotEntry(loadedAt: now, value: value)
        trimRoleExecutionSnapshots()
        return value
    }

    static func recentSkillActivities(
        for ctx: AXProjectContext,
        limit: Int,
        now: Date = Date(),
        loader: () -> [ProjectSkillActivityItem]
    ) -> [ProjectSkillActivityItem] {
        let key = "\(contextKey(ctx))|\(limit)"
        if let entry = recentSkillActivities[key], isFresh(entry.loadedAt, now: now) {
            return entry.value
        }
        let value = loader()
        recentSkillActivities[key] = RecentSkillActivitiesEntry(loadedAt: now, value: value)
        trimRecentSkillActivities()
        return value
    }

    static func latestGovernanceInterception(
        for ctx: AXProjectContext,
        limit: Int,
        now: Date = Date(),
        loader: () -> ProjectGovernanceInterceptionPresentation?
    ) -> ProjectGovernanceInterceptionPresentation? {
        let key = "\(contextKey(ctx))|\(limit)"
        if let entry = latestGovernanceInterceptions[key], isFresh(entry.loadedAt, now: now) {
            return entry.value
        }
        let value = loader()
        latestGovernanceInterceptions[key] = LatestGovernanceInterceptionEntry(loadedAt: now, value: value)
        trimLatestGovernanceInterceptions()
        return value
    }

    static func projectConfig(
        for ctx: AXProjectContext,
        now: Date = Date(),
        loader: () -> AXProjectConfig?
    ) -> AXProjectConfig? {
        let key = contextKey(ctx)
        if let entry = projectConfigs[key], isFresh(entry.loadedAt, now: now) {
            return entry.value
        }
        let value = loader()
        projectConfigs[key] = ProjectConfigEntry(loadedAt: now, value: value)
        trimProjectConfigs()
        return value
    }

    static func latestRouteEvent(
        for ctx: AXProjectContext,
        limit: Int,
        now: Date = Date(),
        loader: () -> AXModelRouteDiagnosticEvent?
    ) -> AXModelRouteDiagnosticEvent? {
        let key = "\(contextKey(ctx))|\(limit)"
        if let entry = latestRouteEvents[key], isFresh(entry.loadedAt, now: now) {
            return entry.value
        }
        let value = loader()
        latestRouteEvents[key] = LatestRouteEventEntry(loadedAt: now, value: value)
        trimLatestRouteEvents()
        return value
    }

    private static func contextKey(_ ctx: AXProjectContext) -> String {
        ctx.root.standardizedFileURL.path
    }

    private static func normalizedProjectKey(_ projectId: String) -> String {
        let trimmed = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(unknown)" : trimmed
    }

    private static func isFresh(_ loadedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(loadedAt) < maxAgeSeconds
    }

    private static func trimSessionSummaries() {
        guard sessionSummaries.count > maxEntries else { return }
        let overflow = sessionSummaries.count - maxEntries
        let staleKeys = sessionSummaries
            .sorted { $0.value.loadedAt < $1.value.loadedAt }
            .prefix(overflow)
            .map(\.key)
        for key in staleKeys {
            sessionSummaries.removeValue(forKey: key)
        }
    }

    private static func trimUIReviews() {
        guard uiReviews.count > maxEntries else { return }
        let overflow = uiReviews.count - maxEntries
        let staleKeys = uiReviews
            .sorted { $0.value.loadedAt < $1.value.loadedAt }
            .prefix(overflow)
            .map(\.key)
        for key in staleKeys {
            uiReviews.removeValue(forKey: key)
        }
    }

    private static func trimContextDiagnostics() {
        guard contextDiagnostics.count > maxEntries else { return }
        let overflow = contextDiagnostics.count - maxEntries
        let staleKeys = contextDiagnostics
            .sorted { $0.value.loadedAt < $1.value.loadedAt }
            .prefix(overflow)
            .map(\.key)
        for key in staleKeys {
            contextDiagnostics.removeValue(forKey: key)
        }
    }

    private static func trimRouteRepairDigests() {
        guard routeRepairDigests.count > maxEntries else { return }
        let overflow = routeRepairDigests.count - maxEntries
        let staleKeys = routeRepairDigests
            .sorted { $0.value.loadedAt < $1.value.loadedAt }
            .prefix(overflow)
            .map(\.key)
        for key in staleKeys {
            routeRepairDigests.removeValue(forKey: key)
        }
    }

    private static func trimGovernancePresentations() {
        guard governancePresentations.count > maxEntries else { return }
        let overflow = governancePresentations.count - maxEntries
        let staleKeys = governancePresentations
            .sorted { $0.value.loadedAt < $1.value.loadedAt }
            .prefix(overflow)
            .map(\.key)
        for key in staleKeys {
            governancePresentations.removeValue(forKey: key)
        }
    }

    private static func trimGovernanceTemplatePreviews() {
        guard governanceTemplatePreviews.count > maxEntries else { return }
        let overflow = governanceTemplatePreviews.count - maxEntries
        let staleKeys = governanceTemplatePreviews
            .sorted { $0.value.loadedAt < $1.value.loadedAt }
            .prefix(overflow)
            .map(\.key)
        for key in staleKeys {
            governanceTemplatePreviews.removeValue(forKey: key)
        }
    }

    private static func trimRoleExecutionSnapshots() {
        guard roleExecutionSnapshots.count > maxEntries else { return }
        let overflow = roleExecutionSnapshots.count - maxEntries
        let staleKeys = roleExecutionSnapshots
            .sorted { $0.value.loadedAt < $1.value.loadedAt }
            .prefix(overflow)
            .map(\.key)
        for key in staleKeys {
            roleExecutionSnapshots.removeValue(forKey: key)
        }
    }

    private static func trimRecentSkillActivities() {
        guard recentSkillActivities.count > maxEntries else { return }
        let overflow = recentSkillActivities.count - maxEntries
        let staleKeys = recentSkillActivities
            .sorted { $0.value.loadedAt < $1.value.loadedAt }
            .prefix(overflow)
            .map(\.key)
        for key in staleKeys {
            recentSkillActivities.removeValue(forKey: key)
        }
    }

    private static func trimLatestGovernanceInterceptions() {
        guard latestGovernanceInterceptions.count > maxEntries else { return }
        let overflow = latestGovernanceInterceptions.count - maxEntries
        let staleKeys = latestGovernanceInterceptions
            .sorted { $0.value.loadedAt < $1.value.loadedAt }
            .prefix(overflow)
            .map(\.key)
        for key in staleKeys {
            latestGovernanceInterceptions.removeValue(forKey: key)
        }
    }

    private static func trimProjectConfigs() {
        guard projectConfigs.count > maxEntries else { return }
        let overflow = projectConfigs.count - maxEntries
        let staleKeys = projectConfigs
            .sorted { $0.value.loadedAt < $1.value.loadedAt }
            .prefix(overflow)
            .map(\.key)
        for key in staleKeys {
            projectConfigs.removeValue(forKey: key)
        }
    }

    private static func trimLatestRouteEvents() {
        guard latestRouteEvents.count > maxEntries else { return }
        let overflow = latestRouteEvents.count - maxEntries
        let staleKeys = latestRouteEvents
            .sorted { $0.value.loadedAt < $1.value.loadedAt }
            .prefix(overflow)
            .map(\.key)
        for key in staleKeys {
            latestRouteEvents.removeValue(forKey: key)
        }
    }
}
