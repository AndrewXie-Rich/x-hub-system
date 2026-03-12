import Foundation

enum AXAgentBaselineInstallScope: Equatable, Sendable {
    case global
    case project(projectId: String, projectName: String?)

    var hubScope: String {
        switch self {
        case .global:
            return "global"
        case .project:
            return "project"
        }
    }

    var projectId: String? {
        switch self {
        case .global:
            return nil
        case .project(let projectId, _):
            let trimmed = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    var displayLabel: String {
        switch self {
        case .global:
            return "Global"
        case .project(_, let projectName):
            let trimmed = (projectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Current Project"
            }
            return "Project: \(trimmed)"
        }
    }

    var noteTag: String {
        switch self {
        case .global:
            return "xt_default_agent_baseline:global"
        case .project(let projectId, _):
            let suffix = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
            return "xt_default_agent_baseline:project:\(suffix)"
        }
    }
}

struct AXDefaultAgentBaselineInstallableCandidate: Equatable, Sendable, Identifiable {
    var skillID: String
    var displayName: String
    var version: String
    var sourceID: String
    var packageSHA256: String
    var installHint: String

    var id: String { "\(skillID)::\(packageSHA256)" }
}

struct AXDefaultAgentBaselineMissingPackage: Equatable, Sendable, Identifiable {
    var skillID: String
    var displayName: String
    var installHint: String

    var id: String { skillID }
}

struct AXDefaultAgentBaselineInstallPlan: Equatable, Sendable {
    var scope: AXAgentBaselineInstallScope
    var totalBaselineCount: Int
    var alreadyResolvedSkillIDs: [String]
    var installableCandidates: [AXDefaultAgentBaselineInstallableCandidate]
    var missingPackageSkills: [AXDefaultAgentBaselineMissingPackage]
}

enum AXDefaultAgentBaselineInstaller {
    static func makePlan(
        scope: AXAgentBaselineInstallScope,
        baseline: [AXDefaultAgentBaselineSkill],
        resolvedSkills: [HubIPCClient.ResolvedSkillEntry],
        searchResultsBySkillID: [String: [HubIPCClient.SkillCatalogEntry]]
    ) -> AXDefaultAgentBaselineInstallPlan {
        let resolvedIDs = Set(
            resolvedSkills.map { $0.skill.skillID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )

        var alreadyResolved: [String] = []
        var installable: [AXDefaultAgentBaselineInstallableCandidate] = []
        var missingPackages: [AXDefaultAgentBaselineMissingPackage] = []

        for baselineSkill in baseline {
            let skillID = baselineSkill.skillID.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedSkillID = skillID.lowercased()
            if resolvedIDs.contains(normalizedSkillID) {
                alreadyResolved.append(skillID)
                continue
            }

            let searchResults = searchResultsBySkillID[skillID] ?? []
            if let candidate = selectInstallableCandidate(skillID: skillID, searchResults: searchResults) {
                installable.append(candidate)
                continue
            }

            let fallbackHint = selectFallbackInstallHint(
                displayName: baselineSkill.displayName,
                baselineSummary: baselineSkill.summary,
                searchResults: searchResults
            )
            missingPackages.append(
                AXDefaultAgentBaselineMissingPackage(
                    skillID: skillID,
                    displayName: baselineSkill.displayName,
                    installHint: fallbackHint
                )
            )
        }

        return AXDefaultAgentBaselineInstallPlan(
            scope: scope,
            totalBaselineCount: baseline.count,
            alreadyResolvedSkillIDs: alreadyResolved.sorted(),
            installableCandidates: installable,
            missingPackageSkills: missingPackages
        )
    }

    private static func selectInstallableCandidate(
        skillID: String,
        searchResults: [HubIPCClient.SkillCatalogEntry]
    ) -> AXDefaultAgentBaselineInstallableCandidate? {
        let normalizedSkillID = skillID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let exactMatches = searchResults.filter { result in
            result.skillID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedSkillID
        }
        let uploaded = exactMatches.first { result in
            !result.packageSHA256.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard let uploaded else { return nil }

        let displayName = uploaded.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? skillID
            : uploaded.name
        return AXDefaultAgentBaselineInstallableCandidate(
            skillID: uploaded.skillID,
            displayName: displayName,
            version: uploaded.version,
            sourceID: uploaded.sourceID,
            packageSHA256: uploaded.packageSHA256,
            installHint: uploaded.installHint
        )
    }

    private static func selectFallbackInstallHint(
        displayName: String,
        baselineSummary: String,
        searchResults: [HubIPCClient.SkillCatalogEntry]
    ) -> String {
        if let firstHint = searchResults
            .map(\.installHint)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return firstHint
        }

        let summary = baselineSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty {
            return summary
        }
        return "\(displayName) is recommended for the default Agent baseline, but Hub has no uploadable package yet."
    }
}
