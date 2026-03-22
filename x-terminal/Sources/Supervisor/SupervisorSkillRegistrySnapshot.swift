import Foundation

enum SupervisorSkillRiskLevel: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
    case critical
}

struct SupervisorGovernedSkillDispatch: Codable, Equatable, Sendable {
    var tool: String
    var fixedArgs: [String: JSONValue]
    var passthroughArgs: [String]
    var argAliases: [String: [String]]
    var requiredAny: [[String]]
    var exactlyOneOf: [[String]]

    enum CodingKeys: String, CodingKey {
        case tool
        case fixedArgs = "fixed_args"
        case passthroughArgs = "passthrough_args"
        case argAliases = "arg_aliases"
        case requiredAny = "required_any"
        case exactlyOneOf = "exactly_one_of"
    }
}

struct SupervisorGovernedSkillDispatchVariant: Codable, Equatable, Sendable {
    var actions: [String]
    var dispatch: SupervisorGovernedSkillDispatch
    var actionArg: String
    var actionMap: [String: String]

    enum CodingKeys: String, CodingKey {
        case actions
        case dispatch
        case actionArg = "action_arg"
        case actionMap = "action_map"
    }
}

struct SupervisorSkillRegistryItem: Identifiable, Codable, Equatable, Sendable {
    var skillId: String
    var displayName: String
    var description: String
    var capabilitiesRequired: [String]
    var governedDispatch: SupervisorGovernedSkillDispatch?
    var governedDispatchVariants: [SupervisorGovernedSkillDispatchVariant]
    var governedDispatchNotes: [String]
    var inputSchemaRef: String
    var outputSchemaRef: String
    var sideEffectClass: String
    var riskLevel: SupervisorSkillRiskLevel
    var requiresGrant: Bool
    var policyScope: String
    var timeoutMs: Int
    var maxRetries: Int
    var available: Bool

    var id: String { skillId }

    enum CodingKeys: String, CodingKey {
        case skillId = "skill_id"
        case displayName = "display_name"
        case description
        case capabilitiesRequired = "capabilities_required"
        case governedDispatch = "governed_dispatch"
        case governedDispatchVariants = "governed_dispatch_variants"
        case governedDispatchNotes = "governed_dispatch_notes"
        case inputSchemaRef = "input_schema_ref"
        case outputSchemaRef = "output_schema_ref"
        case sideEffectClass = "side_effect_class"
        case riskLevel = "risk_level"
        case requiresGrant = "requires_grant"
        case policyScope = "policy_scope"
        case timeoutMs = "timeout_ms"
        case maxRetries = "max_retries"
        case available
    }
}

extension SupervisorSkillRegistryItem {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        skillId = try container.decode(String.self, forKey: .skillId)
        displayName = try container.decode(String.self, forKey: .displayName)
        description = try container.decode(String.self, forKey: .description)
        capabilitiesRequired = try container.decodeIfPresent([String].self, forKey: .capabilitiesRequired) ?? []
        governedDispatch = try container.decodeIfPresent(SupervisorGovernedSkillDispatch.self, forKey: .governedDispatch)
        governedDispatchVariants = try container.decodeIfPresent([SupervisorGovernedSkillDispatchVariant].self, forKey: .governedDispatchVariants) ?? []
        governedDispatchNotes = try container.decodeIfPresent([String].self, forKey: .governedDispatchNotes) ?? []
        inputSchemaRef = try container.decode(String.self, forKey: .inputSchemaRef)
        outputSchemaRef = try container.decode(String.self, forKey: .outputSchemaRef)
        sideEffectClass = try container.decode(String.self, forKey: .sideEffectClass)
        riskLevel = try container.decode(SupervisorSkillRiskLevel.self, forKey: .riskLevel)
        requiresGrant = try container.decode(Bool.self, forKey: .requiresGrant)
        policyScope = try container.decode(String.self, forKey: .policyScope)
        timeoutMs = try container.decode(Int.self, forKey: .timeoutMs)
        maxRetries = try container.decode(Int.self, forKey: .maxRetries)
        available = try container.decode(Bool.self, forKey: .available)
    }
}

struct SupervisorSkillRegistrySnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_skill_registry_view.v1"

    var schemaVersion: String
    var projectId: String
    var projectName: String?
    var updatedAtMs: Int64
    var memorySource: String
    var items: [SupervisorSkillRegistryItem]
    var auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectId = "project_id"
        case projectName = "project_name"
        case updatedAtMs = "updated_at_ms"
        case memorySource = "memory_source"
        case items
        case auditRef = "audit_ref"
    }
}

extension SupervisorSkillRegistrySnapshot {
    var statusLine: String {
        let projectLabel = (projectName ?? projectId).trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceLabel = memorySource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : memorySource
        return "skills=\(items.count) · project=\(projectLabel) · source=\(sourceLabel)"
    }

    func memorySummary(maxItems: Int = 6, maxChars: Int = 1_000) -> String {
        let projectLabel = (projectName ?? projectId).trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = ["project=\(projectLabel) id=\(projectId)"]
        for (index, item) in promptDiscoveryItems().prefix(max(1, maxItems)).enumerated() {
            let block = promptDiscoverySummaryBlock(for: item, index: index + 1)
            let candidate = (lines + block).joined(separator: "\n")
            if candidate.count > maxChars {
                break
            }
            lines.append(contentsOf: block)
        }
        return lines.joined(separator: "\n")
    }

    private func promptDiscoveryItems() -> [SupervisorSkillRegistryItem] {
        items.sorted { lhs, rhs in
            let leftPriority = promptDiscoveryPriority(lhs)
            let rightPriority = promptDiscoveryPriority(rhs)
            if leftPriority != rightPriority {
                return leftPriority < rightPriority
            }
            return lhs.skillId.localizedCaseInsensitiveCompare(rhs.skillId) == .orderedAscending
        }
    }

    private func promptDiscoveryPriority(_ item: SupervisorSkillRegistryItem) -> Int {
        switch AXSkillsLibrary.canonicalSupervisorSkillID(item.skillId).lowercased() {
        case "guarded-automation":
            return 0
        case "supervisor-voice":
            return 1
        default:
            break
        }

        switch item.policyScope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "project":
            return 10
        case "global":
            return 11
        case "memory_core":
            return 12
        case "xt_builtin":
            return 13
        default:
            return 20
        }
    }

    private func promptPreferredUse(_ item: SupervisorSkillRegistryItem) -> String? {
        switch AXSkillsLibrary.canonicalSupervisorSkillID(item.skillId).lowercased() {
        case "guarded-automation":
            return "trusted_automation_readiness, governed_browser_actions"
        case "supervisor-voice":
            return "supervisor_playback_status, preview, speak, stop"
        default:
            return nil
        }
    }

    private func promptDiscoverySummaryBlock(
        for item: SupervisorSkillRegistryItem,
        index: Int
    ) -> [String] {
        let grant = item.requiresGrant ? "grant=yes" : "grant=no"
        let dispatchTool = item.governedDispatch?.tool.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let dispatchSegment = dispatchTool.isEmpty ? "" : " | dispatch=\(dispatchTool)"
        let displayName = item.displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        var lines = [
            "\(index). \(item.skillId) | risk=\(item.riskLevel.rawValue) | \(grant) | scope=\(item.policyScope)\(dispatchSegment)"
        ]

        if !displayName.isEmpty,
           displayName.caseInsensitiveCompare(item.skillId) != .orderedSame {
            lines.append("   display: \(displayName)")
        }

        if let preferredUse = promptPreferredUse(item) {
            lines.append("   preferred_for: \(preferredUse)")
        }

        if let routingHint = promptRoutingHint(item) {
            lines.append("   routing: \(routingHint)")
        }

        let capabilities = promptCapabilityPreview(item)
        if !capabilities.isEmpty {
            lines.append("   caps: \(capabilities.joined(separator: ", "))")
        }

        for variant in promptVariantPreview(item) {
            if let summary = variant.variantSummary() {
                lines.append("   variant: \(summary)")
            }
        }

        if let payloadContract = promptPayloadPreview(item) {
            lines.append("   payload: \(payloadContract)")
        }

        return lines
    }

    private func promptCapabilityPreview(_ item: SupervisorSkillRegistryItem) -> [String] {
        let capabilityLimit: Int
        switch AXSkillsLibrary.canonicalSupervisorSkillID(item.skillId).lowercased() {
        case "guarded-automation", "agent-browser":
            capabilityLimit = 3
        default:
            capabilityLimit = 2
        }
        return Array(item.capabilitiesRequired.prefix(capabilityLimit))
    }

    private func promptVariantPreview(_ item: SupervisorSkillRegistryItem) -> [SupervisorGovernedSkillDispatchVariant] {
        let limit: Int
        switch AXSkillsLibrary.canonicalSupervisorSkillID(item.skillId).lowercased() {
        case "guarded-automation":
            limit = 3
        default:
            limit = 1
        }
        return Array(item.governedDispatchVariants.prefix(limit))
    }

    private func promptPayloadPreview(_ item: SupervisorSkillRegistryItem) -> String? {
        guard let dispatch = item.governedDispatch else { return nil }
        switch AXSkillsLibrary.canonicalSupervisorSkillID(item.skillId).lowercased() {
        case "supervisor-voice":
            return nil
        default:
            break
        }
        return dispatch.payloadContractSummary(maxChars: 140)
    }

    private func promptRoutingHint(_ item: SupervisorSkillRegistryItem) -> String? {
        switch SupervisorSkillRoutingCompatibilityHint.resolve(
            skillId: item.skillId,
            registryItems: items
        ) {
        case .alias(let raw, let canonical):
            return "alias \(raw) -> \(canonical)"
        case .preferredBuiltin(let builtin, let action):
            if let action {
                return "prefers_builtin=\(builtin) action=\(action)"
            }
            return "prefers_builtin=\(builtin)"
        case .compatibleBuiltin(let builtin):
            return "compatible_builtin=\(builtin)"
        case .compatibleEntrypoints(let entries):
            return "entrypoints=\(entries.joined(separator: ", "))"
        case nil:
            return nil
        }
    }
}

private extension SupervisorGovernedSkillDispatch {
    func payloadContractSummary(maxChars: Int = 180) -> String? {
        var parts: [String] = []

        let fixed = fixedArgs
            .sorted { lhs, rhs in lhs.key < rhs.key }
            .compactMap { key, value -> String? in
                guard let rendered = renderScalar(value) else { return nil }
                return "\(key)=\(rendered)"
            }
        if !fixed.isEmpty {
            parts.append("fixed=\(fixed.joined(separator: ", "))")
        }

        let required = renderFieldGroups(requiredAny)
        if !required.isEmpty {
            parts.append("required_any=\(required)")
        }

        let exactlyOne = renderFieldGroups(exactlyOneOf)
        if !exactlyOne.isEmpty {
            parts.append("one_of=\(exactlyOne)")
        }

        let passthrough = orderedUnique(passthroughArgs)
        if !passthrough.isEmpty {
            parts.append("args=\(passthrough.joined(separator: ", "))")
        }

        let aliases = renderAliases(argAliases)
        if !aliases.isEmpty {
            parts.append("aliases=\(aliases)")
        }

        guard !parts.isEmpty else { return nil }
        let summary = parts.joined(separator: " | ")
        guard summary.count > maxChars else { return summary }
        let end = summary.index(summary.startIndex, offsetBy: maxChars)
        return String(summary[..<end]) + "..."
    }

    func renderScalar(_ value: JSONValue) -> String? {
        switch value {
        case .string(let string):
            let cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        case .number(let number):
            if number.rounded() == number {
                return String(Int(number))
            }
            return String(number)
        case .bool(let flag):
            return flag ? "true" : "false"
        default:
            return nil
        }
    }

    func renderFieldGroups(_ groups: [[String]]) -> String {
        orderedUnique(groups.compactMap { group -> String? in
            let cleaned = orderedUnique(
                group.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
            guard !cleaned.isEmpty else { return nil }
            return cleaned.joined(separator: "/")
        }).joined(separator: ", ")
    }

    func renderAliases(_ aliases: [String: [String]]) -> String {
        aliases.keys.sorted().compactMap { key -> String? in
            let canonical = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !canonical.isEmpty else { return nil }
            let values = orderedUnique(
                (aliases[key] ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
            guard !values.isEmpty else { return nil }
            return "\(canonical)<=\(values.joined(separator: "/"))"
        }
        .joined(separator: ", ")
    }

    func orderedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, seen.insert(cleaned).inserted else { continue }
            result.append(cleaned)
        }
        return result
    }
}

extension SupervisorGovernedSkillDispatchVariant {
    func matches(action: String) -> Bool {
        let normalized = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return actions.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized }
    }

    func resolvedActionOverride(for requestedAction: String) -> (key: String, value: String)? {
        let cleanedKey = actionArg.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedKey.isEmpty else { return nil }
        let normalizedAction = requestedAction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedAction.isEmpty else { return nil }
        let mapped = actionMap.first(where: {
            $0.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedAction
        })?.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = {
            let token = mapped ?? ""
            return token.isEmpty ? requestedAction : token
        }()
        guard !resolved.isEmpty else { return nil }
        return (cleanedKey, resolved)
    }

    func variantSummary(maxChars: Int = 220) -> String? {
        let cleanedActions = actions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleanedActions.isEmpty else { return nil }

        var parts = ["actions=\(cleanedActions.joined(separator: "/")) -> \(dispatch.tool)"]
        let actionMapping = actionMappingSummary()
        if !actionMapping.isEmpty {
            parts.append(actionMapping)
        }
        if let payloadSummary = dispatch.payloadContractSummary(maxChars: 140) {
            parts.append(payloadSummary)
        }

        let summary = parts.joined(separator: " | ")
        guard summary.count > maxChars else { return summary }
        let end = summary.index(summary.startIndex, offsetBy: maxChars)
        return String(summary[..<end]) + "..."
    }

    func actionMappingSummary() -> String {
        let cleanedArg = actionArg.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedArg.isEmpty, !actionMap.isEmpty else { return "" }

        let grouped = Dictionary(grouping: actionMap.compactMap { key, value -> (String, String)? in
            let action = key.trimmingCharacters(in: .whitespacesAndNewlines)
            let mapped = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !action.isEmpty, !mapped.isEmpty else { return nil }
            return (mapped, action)
        }, by: \.0)

        let segments = grouped.keys.sorted().compactMap { mapped -> String? in
            let aliases = grouped[mapped]?
                .map(\.1)
                .sorted() ?? []
            guard !aliases.isEmpty else { return nil }
            return "\(aliases.joined(separator: "/"))=>\(cleanedArg)=\(mapped)"
        }
        return segments.isEmpty ? "" : "map=\(segments.joined(separator: ", "))"
    }
}
