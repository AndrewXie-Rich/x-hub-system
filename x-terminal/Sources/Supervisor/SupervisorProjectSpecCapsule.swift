import Foundation

enum SupervisorProjectSpecDecisionDefaultMode: String, Codable, Sendable {
    case proposalOnly = "proposal_only"
    case proposalWithTimeoutEscalation = "proposal_with_timeout_escalation"
    case autoAdoptIfPolicyAllows = "auto_adopt_if_policy_allows"
}

enum SupervisorProjectSpecRiskProfile: String, Codable, Sendable {
    case low
    case medium
    case high
}

enum SupervisorProjectSpecStatus: String, Codable, Sendable {
    case planned
    case active
    case blocked
    case completed
    case archived
}

enum SupervisorProjectSpecField: String, CaseIterable, Codable, Sendable {
    case goal
    case mvpDefinition = "mvp_definition"
    case nonGoals = "non_goals"
    case approvedTechStack = "approved_tech_stack"
    case milestones

    var summaryToken: String {
        switch self {
        case .goal:
            return "goal"
        case .mvpDefinition:
            return "mvp_definition"
        case .nonGoals:
            return "non_goals"
        case .approvedTechStack:
            return "tech_stack"
        case .milestones:
            return "milestones"
        }
    }
}

struct SupervisorProjectSpecModule: Equatable, Codable, Sendable {
    var moduleId: String
    var title: String
    var status: SupervisorProjectSpecStatus
    var dependsOn: [String]

    enum CodingKeys: String, CodingKey {
        case moduleId = "module_id"
        case title
        case status
        case dependsOn = "depends_on"
    }
}

struct SupervisorProjectSpecMilestone: Equatable, Codable, Sendable {
    var milestoneId: String
    var title: String
    var status: SupervisorProjectSpecStatus

    enum CodingKeys: String, CodingKey {
        case milestoneId = "milestone_id"
        case title
        case status
    }
}

struct SupervisorProjectSpecCapsuleAnswers: Equatable, Codable, Sendable {
    var goal: String
    var mvpDefinition: String
    var nonGoals: [String]
    var approvedTechStack: [String]
    var milestones: [SupervisorProjectSpecMilestone]

    enum CodingKeys: String, CodingKey {
        case goal
        case mvpDefinition = "mvp_definition"
        case nonGoals = "non_goals"
        case approvedTechStack = "approved_tech_stack"
        case milestones
    }
}

enum SupervisorProjectSpecCapsuleMergeError: Error, Equatable {
    case schemaVersionMismatch
    case projectMismatch
}

struct SupervisorProjectSpecCapsule: Equatable, Codable, Sendable {
    static let schemaVersion = "xt.supervisor_project_spec_capsule.v1"

    var schemaVersion: String
    var projectId: String
    var goal: String
    var mvpDefinition: String
    var nonGoals: [String]
    var approvedTechStack: [String]
    var techStackBlacklist: [String]
    var moduleMap: [SupervisorProjectSpecModule]
    var milestoneMap: [SupervisorProjectSpecMilestone]
    var decisionDefaults: [String: SupervisorProjectSpecDecisionDefaultMode]
    var riskProfile: SupervisorProjectSpecRiskProfile
    var updatedAtMs: Int64
    var sourceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectId = "project_id"
        case goal
        case mvpDefinition = "mvp_definition"
        case nonGoals = "non_goals"
        case approvedTechStack = "approved_tech_stack"
        case techStackBlacklist = "tech_stack_blacklist"
        case moduleMap = "module_map"
        case milestoneMap = "milestone_map"
        case decisionDefaults = "decision_defaults"
        case riskProfile = "risk_profile"
        case updatedAtMs = "updated_at_ms"
        case sourceRefs = "source_refs"
    }

    var missingRequiredFields: [SupervisorProjectSpecField] {
        var fields: [SupervisorProjectSpecField] = []
        if goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.append(.goal)
        }
        if mvpDefinition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.append(.mvpDefinition)
        }
        if nonGoals.isEmpty {
            fields.append(.nonGoals)
        }
        if approvedTechStack.isEmpty {
            fields.append(.approvedTechStack)
        }
        if milestoneMap.isEmpty {
            fields.append(.milestones)
        }
        return fields
    }

    var machineReadableAnswers: SupervisorProjectSpecCapsuleAnswers? {
        guard missingRequiredFields.isEmpty else { return nil }
        return SupervisorProjectSpecCapsuleAnswers(
            goal: goal,
            mvpDefinition: mvpDefinition,
            nonGoals: nonGoals,
            approvedTechStack: approvedTechStack,
            milestones: milestoneMap
        )
    }

    func decisionDefault(for category: SupervisorDecisionCategory) -> SupervisorProjectSpecDecisionDefaultMode? {
        decisionDefaults[category.rawValue]
    }

    func merged(with incoming: SupervisorProjectSpecCapsule) throws -> SupervisorProjectSpecCapsule {
        guard schemaVersion == Self.schemaVersion, incoming.schemaVersion == Self.schemaVersion else {
            throw SupervisorProjectSpecCapsuleMergeError.schemaVersionMismatch
        }
        guard normalizedProjectID(projectId) == normalizedProjectID(incoming.projectId) else {
            throw SupervisorProjectSpecCapsuleMergeError.projectMismatch
        }

        let preferIncoming = incoming.updatedAtMs >= updatedAtMs
        let primary = preferIncoming ? incoming : self
        let secondary = preferIncoming ? self : incoming

        var mergedDecisionDefaults = decisionDefaults
        for (key, value) in incoming.decisionDefaults {
            let normalizedKey = normalizedDomainToken(key)
            guard !normalizedKey.isEmpty else { continue }
            mergedDecisionDefaults[normalizedKey] = value
        }

        return SupervisorProjectSpecCapsule(
            schemaVersion: Self.schemaVersion,
            projectId: preferredScalar(primary.projectId, secondary.projectId),
            goal: preferredScalar(primary.goal, secondary.goal),
            mvpDefinition: preferredScalar(primary.mvpDefinition, secondary.mvpDefinition),
            nonGoals: orderedUnique(primary.nonGoals + secondary.nonGoals),
            approvedTechStack: orderedUnique(primary.approvedTechStack + secondary.approvedTechStack),
            techStackBlacklist: orderedUnique(primary.techStackBlacklist + secondary.techStackBlacklist),
            moduleMap: mergeModules(base: secondary.moduleMap, incoming: primary.moduleMap),
            milestoneMap: mergeMilestones(base: secondary.milestoneMap, incoming: primary.milestoneMap),
            decisionDefaults: mergedDecisionDefaults,
            riskProfile: preferIncoming ? incoming.riskProfile : riskProfile,
            updatedAtMs: max(updatedAtMs, incoming.updatedAtMs),
            sourceRefs: orderedUnique(sourceRefs + incoming.sourceRefs)
        )
    }
}

enum SupervisorProjectSpecCapsuleBuilder {
    static func build(
        projectId: String,
        goal: String,
        mvpDefinition: String,
        nonGoals: [String],
        approvedTechStack: [String],
        techStackBlacklist: [String] = [],
        moduleMap: [SupervisorProjectSpecModule] = [],
        milestoneMap: [SupervisorProjectSpecMilestone],
        decisionDefaults: [SupervisorDecisionCategory: SupervisorProjectSpecDecisionDefaultMode] = [:],
        riskProfile: SupervisorProjectSpecRiskProfile = .medium,
        updatedAtMs: Int64 = SupervisorProjectSpecCapsuleBuilder.currentTimeMs(),
        sourceRefs: [String] = []
    ) -> SupervisorProjectSpecCapsule {
        var serializedDefaults: [String: SupervisorProjectSpecDecisionDefaultMode] = [:]
        for (category, policy) in decisionDefaults {
            let key = normalizedDomainToken(category.rawValue)
            guard !key.isEmpty else { continue }
            serializedDefaults[key] = policy
        }

        return SupervisorProjectSpecCapsule(
            schemaVersion: SupervisorProjectSpecCapsule.schemaVersion,
            projectId: normalizedProjectID(projectId),
            goal: normalizedScalar(goal),
            mvpDefinition: normalizedScalar(mvpDefinition),
            nonGoals: orderedUnique(nonGoals),
            approvedTechStack: orderedUnique(approvedTechStack),
            techStackBlacklist: orderedUnique(techStackBlacklist),
            moduleMap: mergeModules(base: [], incoming: moduleMap),
            milestoneMap: mergeMilestones(base: [], incoming: milestoneMap),
            decisionDefaults: serializedDefaults,
            riskProfile: riskProfile,
            updatedAtMs: max(0, updatedAtMs),
            sourceRefs: orderedUnique(sourceRefs)
        )
    }

    static func currentTimeMs() -> Int64 {
        max(0, Int64((Date().timeIntervalSince1970 * 1000.0).rounded()))
    }
}

enum SupervisorProjectSpecCapsuleStore {
    private static let fileName = "supervisor_project_spec_capsule.json"

    static func load(for ctx: AXProjectContext) -> SupervisorProjectSpecCapsule? {
        try? ctx.ensureDirs()
        guard let data = try? Data(contentsOf: url(for: ctx)) else { return nil }
        return try? JSONDecoder().decode(SupervisorProjectSpecCapsule.self, from: data)
    }

    @discardableResult
    static func upsert(_ capsule: SupervisorProjectSpecCapsule, for ctx: AXProjectContext) throws -> SupervisorProjectSpecCapsule {
        try ctx.ensureDirs()
        let merged: SupervisorProjectSpecCapsule
        if let existing = load(for: ctx) {
            merged = try existing.merged(with: capsule)
        } else {
            merged = capsule
        }
        try save(merged, for: ctx)
        return merged
    }

    static func save(_ capsule: SupervisorProjectSpecCapsule, for ctx: AXProjectContext) throws {
        try ctx.ensureDirs()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(capsule)
        let target = url(for: ctx)
        try SupervisorStoreWriteSupport.writeSnapshotData(data, to: target)
    }

    private static func url(for ctx: AXProjectContext) -> URL {
        ctx.xterminalDir.appendingPathComponent(fileName)
    }
}

private func mergeModules(
    base: [SupervisorProjectSpecModule],
    incoming: [SupervisorProjectSpecModule]
) -> [SupervisorProjectSpecModule] {
    mergeIdentifiedRecords(
        base: base,
        incoming: incoming,
        id: { normalizedDomainToken($0.moduleId) }
    ) { raw in
        SupervisorProjectSpecModule(
            moduleId: normalizedDomainToken(raw.moduleId),
            title: normalizedScalar(raw.title),
            status: raw.status,
            dependsOn: orderedUnique(raw.dependsOn)
        )
    }
}

private func mergeMilestones(
    base: [SupervisorProjectSpecMilestone],
    incoming: [SupervisorProjectSpecMilestone]
) -> [SupervisorProjectSpecMilestone] {
    mergeIdentifiedRecords(
        base: base,
        incoming: incoming,
        id: { normalizedDomainToken($0.milestoneId) }
    ) { raw in
        SupervisorProjectSpecMilestone(
            milestoneId: normalizedDomainToken(raw.milestoneId),
            title: normalizedScalar(raw.title),
            status: raw.status
        )
    }
}

private func mergeIdentifiedRecords<Record>(
    base: [Record],
    incoming: [Record],
    id: (Record) -> String,
    normalize: (Record) -> Record
) -> [Record] {
    var ordered: [Record] = []
    var indexByID: [String: Int] = [:]

    for record in base + incoming {
        let normalized = normalize(record)
        let key = id(normalized)
        guard !key.isEmpty else { continue }
        if let index = indexByID[key] {
            ordered[index] = normalized
        } else {
            indexByID[key] = ordered.count
            ordered.append(normalized)
        }
    }

    return ordered
}

private func orderedUnique(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var ordered: [String] = []

    for raw in values {
        let normalized = normalizedScalar(raw)
        guard !normalized.isEmpty else { continue }
        if seen.insert(normalized).inserted {
            ordered.append(normalized)
        }
    }

    return ordered
}

private func preferredScalar(_ primary: String, _ fallback: String) -> String {
    let normalizedPrimary = normalizedScalar(primary)
    if !normalizedPrimary.isEmpty {
        return normalizedPrimary
    }
    return normalizedScalar(fallback)
}

private func normalizedProjectID(_ raw: String) -> String {
    normalizedScalar(raw).lowercased()
}

private func normalizedDomainToken(_ raw: String) -> String {
    let trimmed = raw
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "-", with: "_")
        .replacingOccurrences(of: " ", with: "_")
    let pieces = trimmed
        .split(separator: "_")
        .map(String.init)
        .filter { !$0.isEmpty }
    return pieces.joined(separator: "_")
}

private func normalizedScalar(_ raw: String) -> String {
    raw
        .replacingOccurrences(of: "\r\n", with: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
