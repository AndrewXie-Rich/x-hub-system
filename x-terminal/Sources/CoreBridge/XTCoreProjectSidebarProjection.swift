import Combine
import Foundation

struct XTCoreProjectSidebarProjection: Codable, Equatable, Sendable {
    var revision: UInt64
    var selectedProjectId: String?
    var projectCountText: String
    var rows: [XTCoreProjectSidebarRowProjection]

    enum CodingKeys: String, CodingKey {
        case revision
        case selectedProjectId = "selected_project_id"
        case projectCountText = "project_count_text"
        case rows
    }

    static let empty = XTCoreProjectSidebarProjection(
        revision: 0,
        selectedProjectId: nil,
        projectCountText: "0",
        rows: []
    )

    init(
        revision: UInt64,
        selectedProjectId: String?,
        projectCountText: String,
        rows: [XTCoreProjectSidebarRowProjection]
    ) {
        self.revision = revision
        self.selectedProjectId = selectedProjectId
        self.projectCountText = projectCountText
        self.rows = rows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        revision = (try? container.decode(UInt64.self, forKey: .revision)) ?? 0
        selectedProjectId = try container.decodeIfPresent(String.self, forKey: .selectedProjectId)
        projectCountText = (try? container.decode(String.self, forKey: .projectCountText)) ?? "0"
        rows = (try? container.decode([XTCoreProjectSidebarRowProjection].self, forKey: .rows)) ?? []
    }
}

struct XTCoreProjectSidebarRowProjection: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var displayName: String
    var rootPath: String
    var isSelected: Bool
    var statusDigest: String?
    var resumeBadgeText: String?
    var resumeHelpText: String?
    var governance: XTCoreProjectSidebarGovernanceProjection?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case rootPath = "root_path"
        case isSelected = "is_selected"
        case statusDigest = "status_digest"
        case resumeBadgeText = "resume_badge_text"
        case resumeHelpText = "resume_help_text"
        case governance
    }
}

struct XTCoreProjectSidebarGovernanceProjection: Codable, Equatable, Sendable {
    var executionTier: AXProjectExecutionTier
    var executionTierToken: String
    var executionTierLabel: String
    var executionTierHelp: String
    var supervisorTier: AXProjectSupervisorInterventionTier
    var supervisorTierToken: String
    var supervisorTierLabel: String
    var supervisorTierHelp: String

    enum CodingKeys: String, CodingKey {
        case executionTier = "execution_tier"
        case executionTierToken = "execution_tier_token"
        case executionTierLabel = "execution_tier_label"
        case executionTierHelp = "execution_tier_help"
        case supervisorTier = "supervisor_tier"
        case supervisorTierToken = "supervisor_tier_token"
        case supervisorTierLabel = "supervisor_tier_label"
        case supervisorTierHelp = "supervisor_tier_help"
    }
}

struct XTCoreProjectSidebarProjectionInput: Encodable, Equatable, Sendable {
    var revision: UInt64
    var selectedProjectId: String?
    var projects: [XTCoreProjectSidebarProjectInput]
    var selectedSupplemental: XTCoreProjectSidebarSelectedSupplementalInput?

    enum CodingKeys: String, CodingKey {
        case revision
        case selectedProjectId = "selected_project_id"
        case projects
        case selectedSupplemental = "selected_supplemental"
    }
}

struct XTCoreProjectSidebarProjectInput: Encodable, Equatable, Sendable {
    var id: String
    var displayName: String
    var rootPath: String
    var statusDigest: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case rootPath = "root_path"
        case statusDigest = "status_digest"
    }
}

struct XTCoreProjectSidebarSelectedSupplementalInput: Encodable, Equatable, Sendable {
    var projectId: String
    var resumeBadgeText: String?
    var resumeHelpText: String?
    var governance: XTCoreProjectSidebarGovernanceInput?

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case resumeBadgeText = "resume_badge_text"
        case resumeHelpText = "resume_help_text"
        case governance
    }
}

struct XTCoreProjectSidebarGovernanceInput: Encodable, Equatable, Sendable {
    var executionTier: String
    var executionTierToken: String
    var executionTierLabel: String
    var executionTierHelp: String
    var supervisorTier: String
    var supervisorTierToken: String
    var supervisorTierLabel: String
    var supervisorTierHelp: String

    enum CodingKeys: String, CodingKey {
        case executionTier = "execution_tier"
        case executionTierToken = "execution_tier_token"
        case executionTierLabel = "execution_tier_label"
        case executionTierHelp = "execution_tier_help"
        case supervisorTier = "supervisor_tier"
        case supervisorTierToken = "supervisor_tier_token"
        case supervisorTierLabel = "supervisor_tier_label"
        case supervisorTierHelp = "supervisor_tier_help"
    }
}

enum XTCoreProjectSidebarProjectionInputBuilder {
    static func build(
        projectListSnapshot: XTProjectListSnapshot,
        workSurfaceSnapshot: XTWorkSurfaceSnapshot,
        revision: UInt64,
        governancePresentation: (AXProjectEntry) -> ProjectGovernancePresentation?,
        sessionSummaryPresentation: (AXProjectEntry) -> AXSessionSummaryCapsulePresentation?
    ) -> XTCoreProjectSidebarProjectionInput {
        let selectedProjectId = normalizedNonEmpty(projectListSnapshot.selectedProjectId)
        let selectedSupplementalProjectId = workSurfaceSnapshot.selectedProjectId == selectedProjectId
            ? selectedProjectId
            : nil
        let selectedProject = selectedSupplementalProjectId.flatMap { projectId in
            projectListSnapshot.projects.first { $0.projectId == projectId }
        }
        let supplemental = selectedProject.map { project in
            let summary = sessionSummaryPresentation(project)
            return XTCoreProjectSidebarSelectedSupplementalInput(
                projectId: project.projectId,
                resumeBadgeText: normalizedNonEmpty(summary?.badgeText),
                resumeHelpText: normalizedNonEmpty(summary?.helpText),
                governance: governancePresentation(project).map(governanceInput(from:))
            )
        }

        return XTCoreProjectSidebarProjectionInput(
            revision: revision,
            selectedProjectId: selectedProjectId,
            projects: projectListSnapshot.projects.map { project in
                XTCoreProjectSidebarProjectInput(
                    id: project.projectId,
                    displayName: project.displayName,
                    rootPath: project.rootPath,
                    statusDigest: normalizedNonEmpty(project.statusDigest)
                )
            },
            selectedSupplemental: supplemental
        )
    }

    static func jsonString(
        for input: XTCoreProjectSidebarProjectionInput,
        encoder: JSONEncoder = JSONEncoder()
    ) -> String? {
        guard let data = try? encoder.encode(input) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func governanceInput(
        from presentation: ProjectGovernancePresentation
    ) -> XTCoreProjectSidebarGovernanceInput {
        let executionTier = presentation.effectiveExecutionTier ?? presentation.executionTier
        let supervisorTier = presentation.effectiveSupervisorInterventionTier
            ?? presentation.supervisorInterventionTier
        return XTCoreProjectSidebarGovernanceInput(
            executionTier: executionTier.rawValue,
            executionTierToken: executionTier.shortToken,
            executionTierLabel: executionTier.localizedShortLabel,
            executionTierHelp: presentation.effectiveExecutionLabel,
            supervisorTier: supervisorTier.rawValue,
            supervisorTierToken: supervisorTier.shortToken,
            supervisorTierLabel: supervisorTier.localizedShortLabel,
            supervisorTierHelp: presentation.effectiveSupervisorLabel
        )
    }

    private static func normalizedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum XTCoreProjectSidebarProjectionBuilder {
    static func build(
        input: XTCoreProjectSidebarProjectionInput
    ) -> XTCoreProjectSidebarProjection {
        let selectedProjectId = normalizedNonEmpty(input.selectedProjectId)
        let selectedSupplemental = input.selectedSupplemental.flatMap { supplemental in
            selectedProjectId == supplemental.projectId ? supplemental : nil
        }
        let rows = input.projects.map { project in
            let isSelected = selectedProjectId == project.id
            let supplemental = isSelected && selectedSupplemental?.projectId == project.id
                ? selectedSupplemental
                : nil
            return XTCoreProjectSidebarRowProjection(
                id: project.id,
                displayName: project.displayName,
                rootPath: project.rootPath,
                isSelected: isSelected,
                statusDigest: isSelected ? normalizedNonEmpty(project.statusDigest) : nil,
                resumeBadgeText: normalizedNonEmpty(supplemental?.resumeBadgeText),
                resumeHelpText: normalizedNonEmpty(supplemental?.resumeHelpText),
                governance: supplemental?.governance.flatMap(governanceProjection(from:))
            )
        }

        return XTCoreProjectSidebarProjection(
            revision: input.revision,
            selectedProjectId: selectedProjectId,
            projectCountText: "\(input.projects.count)",
            rows: rows
        )
    }

    static func build(
        projectListSnapshot: XTProjectListSnapshot,
        workSurfaceSnapshot: XTWorkSurfaceSnapshot,
        revision: UInt64 = 0,
        governancePresentation: (AXProjectEntry) -> ProjectGovernancePresentation?,
        sessionSummaryPresentation: (AXProjectEntry) -> AXSessionSummaryCapsulePresentation?
    ) -> XTCoreProjectSidebarProjection {
        let selectedProjectId = projectListSnapshot.selectedProjectId
        let selectedSupplementalProjectId = workSurfaceSnapshot.selectedProjectId == selectedProjectId
            ? selectedProjectId
            : nil
        let rows = projectListSnapshot.projects.map { project in
            let isSelected = selectedProjectId == project.projectId
            let shouldLoadSupplemental = isSelected
                && selectedSupplementalProjectId == project.projectId
            let summary = shouldLoadSupplemental
                ? sessionSummaryPresentation(project)
                : nil
            let governance = shouldLoadSupplemental
                ? governancePresentation(project).map(governanceProjection(from:))
                : nil

            return XTCoreProjectSidebarRowProjection(
                id: project.projectId,
                displayName: project.displayName,
                rootPath: project.rootPath,
                isSelected: isSelected,
                statusDigest: isSelected ? normalizedNonEmpty(project.statusDigest) : nil,
                resumeBadgeText: summary?.badgeText,
                resumeHelpText: summary?.helpText,
                governance: governance
            )
        }

        return XTCoreProjectSidebarProjection(
            revision: revision,
            selectedProjectId: selectedProjectId,
            projectCountText: "\(projectListSnapshot.projectCount)",
            rows: rows
        )
    }

    private static func governanceProjection(
        from input: XTCoreProjectSidebarGovernanceInput
    ) -> XTCoreProjectSidebarGovernanceProjection? {
        guard let executionTier = AXProjectExecutionTier(rawValue: input.executionTier),
              let supervisorTier = AXProjectSupervisorInterventionTier(rawValue: input.supervisorTier) else {
            return nil
        }
        return XTCoreProjectSidebarGovernanceProjection(
            executionTier: executionTier,
            executionTierToken: input.executionTierToken,
            executionTierLabel: input.executionTierLabel,
            executionTierHelp: input.executionTierHelp,
            supervisorTier: supervisorTier,
            supervisorTierToken: input.supervisorTierToken,
            supervisorTierLabel: input.supervisorTierLabel,
            supervisorTierHelp: input.supervisorTierHelp
        )
    }

    private static func governanceProjection(
        from presentation: ProjectGovernancePresentation
    ) -> XTCoreProjectSidebarGovernanceProjection {
        let executionTier = presentation.effectiveExecutionTier ?? presentation.executionTier
        let supervisorTier = presentation.effectiveSupervisorInterventionTier
            ?? presentation.supervisorInterventionTier
        return XTCoreProjectSidebarGovernanceProjection(
            executionTier: executionTier,
            executionTierToken: executionTier.shortToken,
            executionTierLabel: executionTier.localizedShortLabel,
            executionTierHelp: presentation.effectiveExecutionLabel,
            supervisorTier: supervisorTier,
            supervisorTierToken: supervisorTier.shortToken,
            supervisorTierLabel: supervisorTier.localizedShortLabel,
            supervisorTierHelp: presentation.effectiveSupervisorLabel
        )
    }

    private static func normalizedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
final class XTCoreProjectSidebarProjectionStore: ObservableObject {
    @Published private(set) var snapshot: XTCoreProjectSidebarProjection

    init(snapshot: XTCoreProjectSidebarProjection = .empty) {
        self.snapshot = snapshot
    }

    func update(_ nextSnapshot: XTCoreProjectSidebarProjection) {
        guard snapshot != nextSnapshot else { return }
        snapshot = nextSnapshot
    }
}
