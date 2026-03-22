import Foundation

enum SupervisorProjectJurisdictionRole: String, Codable, Sendable, CaseIterable {
    case owner
    case observer
    case triageOnly = "triage_only"

    fileprivate var maxDrillDownScope: SupervisorProjectDrillDownScope {
        switch self {
        case .owner:
            return .capsulePlusRecent
        case .observer, .triageOnly:
            return .capsuleOnly
        }
    }

    fileprivate func allowsVisibility(for state: SupervisorPortfolioProjectState) -> Bool {
        switch self {
        case .owner, .observer:
            return true
        case .triageOnly:
            return state == .blocked || state == .awaitingAuthorization
        }
    }
}

enum SupervisorProjectDrillDownScope: String, Codable, Sendable, CaseIterable {
    case capsuleOnly = "capsule_only"
    case capsulePlusRecent = "capsule_plus_recent"
    case rawEvidence = "raw_evidence"

    var rank: Int {
        switch self {
        case .capsuleOnly:
            return 0
        case .capsulePlusRecent:
            return 1
        case .rawEvidence:
            return 2
        }
    }
}

struct SupervisorProjectJurisdictionEntry: Identifiable, Equatable, Codable, Sendable {
    var projectId: String
    var displayName: String
    var role: SupervisorProjectJurisdictionRole
    var updatedAt: Double

    var id: String { projectId }
}

struct SupervisorJurisdictionRegistry: Equatable, Codable, Sendable {
    static let currentVersion = "xt.supervisor_jurisdiction_registry.v1"

    var version: String
    var updatedAt: Double
    var defaultRole: SupervisorProjectJurisdictionRole
    var entries: [SupervisorProjectJurisdictionEntry]

    static func ownerDefault(now: Double = Date().timeIntervalSince1970) -> SupervisorJurisdictionRegistry {
        SupervisorJurisdictionRegistry(
            version: currentVersion,
            updatedAt: now,
            defaultRole: .owner,
            entries: []
        )
    }

    static func ownerAll(
        for projects: [AXProjectEntry],
        now: Double = Date().timeIntervalSince1970
    ) -> SupervisorJurisdictionRegistry {
        ownerDefault(now: now).normalized(for: projects, now: now)
    }

    var summaryLine: String {
        let counts = entries.reduce(into: [SupervisorProjectJurisdictionRole: Int]()) { partial, entry in
            partial[entry.role, default: 0] += 1
        }
        return "owner=\(counts[.owner, default: 0]) · observer=\(counts[.observer, default: 0]) · triage=\(counts[.triageOnly, default: 0])"
    }

    func role(for projectId: String) -> SupervisorProjectJurisdictionRole {
        entries.first(where: { $0.projectId == projectId })?.role ?? defaultRole
    }

    func filteredProjects(_ projects: [AXProjectEntry]) -> [AXProjectEntry] {
        projects.filter(allowsProjectVisibility)
    }

    func filteredDigests(
        _ digests: [SupervisorManager.SupervisorMemoryProjectDigest]
    ) -> [SupervisorManager.SupervisorMemoryProjectDigest] {
        digests.filter(allowsPortfolioVisibility)
    }

    func filteredEvents(_ events: [SupervisorProjectActionEvent]) -> [SupervisorProjectActionEvent] {
        events.filter(allowsEventVisibility)
    }

    func allowsProjectVisibility(_ project: AXProjectEntry) -> Bool {
        let state = SupervisorPortfolioSnapshotBuilder.projectState(from: project)
        return role(for: project.projectId).allowsVisibility(for: state)
    }

    func allowsPortfolioVisibility(_ digest: SupervisorManager.SupervisorMemoryProjectDigest) -> Bool {
        let state = SupervisorPortfolioSnapshotBuilder.projectState(from: digest)
        return role(for: digest.projectId).allowsVisibility(for: state)
    }

    func allowsEventVisibility(_ event: SupervisorProjectActionEvent) -> Bool {
        switch role(for: event.projectId) {
        case .owner, .observer:
            return true
        case .triageOnly:
            return event.eventType == .blocked ||
                event.eventType == .awaitingAuthorization ||
                event.severity == .authorizationRequired ||
                event.severity == .interruptNow
        }
    }

    func allowsDrillDown(projectId: String, requestedScope: SupervisorProjectDrillDownScope) -> Bool {
        role(for: projectId).maxDrillDownScope.rank >= requestedScope.rank
    }

    func allowedDrillDownScopes(projectId: String) -> [SupervisorProjectDrillDownScope] {
        SupervisorProjectDrillDownScope.allCases.filter {
            allowsDrillDown(projectId: projectId, requestedScope: $0)
        }
    }

    func normalized(
        for projects: [AXProjectEntry],
        now: Double = Date().timeIntervalSince1970
    ) -> SupervisorJurisdictionRegistry {
        guard !projects.isEmpty else {
            let normalized = SupervisorJurisdictionRegistry(
                version: Self.currentVersion,
                updatedAt: now,
                defaultRole: defaultRole,
                entries: entries
            )
            if normalized.version == version {
                return self
            }
            return normalized
        }

        let existing = Dictionary(uniqueKeysWithValues: entries.map { ($0.projectId, $0) })
        let normalizedEntries = projects.map { project -> SupervisorProjectJurisdictionEntry in
            if var current = existing[project.projectId] {
                if current.displayName != project.displayName {
                    current.displayName = project.displayName
                    current.updatedAt = now
                }
                return current
            }
            return SupervisorProjectJurisdictionEntry(
                projectId: project.projectId,
                displayName: project.displayName,
                role: defaultRole,
                updatedAt: now
            )
        }

        let normalized = SupervisorJurisdictionRegistry(
            version: Self.currentVersion,
            updatedAt: now,
            defaultRole: defaultRole,
            entries: normalizedEntries
        )
        if normalized.version == version &&
            normalized.defaultRole == defaultRole &&
            normalized.entries == entries {
            return self
        }
        return normalized
    }

    func upserting(
        projectId: String,
        displayName: String,
        role: SupervisorProjectJurisdictionRole,
        now: Double = Date().timeIntervalSince1970
    ) -> SupervisorJurisdictionRegistry {
        var nextEntries = entries
        if let index = nextEntries.firstIndex(where: { $0.projectId == projectId }) {
            nextEntries[index].displayName = displayName
            nextEntries[index].role = role
            nextEntries[index].updatedAt = now
        } else {
            nextEntries.append(
                SupervisorProjectJurisdictionEntry(
                    projectId: projectId,
                    displayName: displayName,
                    role: role,
                    updatedAt: now
                )
            )
        }

        return SupervisorJurisdictionRegistry(
            version: Self.currentVersion,
            updatedAt: now,
            defaultRole: defaultRole,
            entries: nextEntries
        )
    }
}

enum SupervisorJurisdictionRegistryStore {
    private static let fileName = "supervisor_jurisdiction_registry.json"

    static func url() -> URL {
        AXProjectRegistryStore.baseDir().appendingPathComponent(fileName)
    }

    static func load() -> SupervisorJurisdictionRegistry {
        let fileURL = url()
        guard let data = try? Data(contentsOf: fileURL) else {
            return .ownerDefault()
        }
        guard var decoded = try? JSONDecoder().decode(SupervisorJurisdictionRegistry.self, from: data) else {
            return .ownerDefault()
        }
        if decoded.version.isEmpty {
            decoded.version = SupervisorJurisdictionRegistry.currentVersion
        }
        return decoded
    }

    static func save(_ registry: SupervisorJurisdictionRegistry) {
        var current = registry
        current.version = SupervisorJurisdictionRegistry.currentVersion
        current.updatedAt = Date().timeIntervalSince1970
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(current) else { return }
        try? SupervisorStoreWriteSupport.writeSnapshotData(data, to: url())
    }
}
