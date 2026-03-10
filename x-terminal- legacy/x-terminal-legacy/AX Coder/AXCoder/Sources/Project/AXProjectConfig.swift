import Foundation

struct AXProjectConfig: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int

    // Per-role model overrides (role rawValue -> model id).
    var roleModelOverrides: [String: String]

    // Verification commands to run after changes (in order).
    // Examples:
    // - swift test
    // - npm test
    // - python -m pytest
    var verifyCommands: [String]

    // If true, X-Terminal will suggest/trigger verification automatically in the tool loop.
    // Actual execution still follows the tool confirmation policy.
    var verifyAfterChanges: Bool

    // Tool policy (Openclaw-style): profile + additive allow/deny tokens.
    // profile: minimal|coding|full
    // allow/deny tokens support tool names, group:*, and all/*
    var toolProfile: String
    var toolAllow: [String]
    var toolDeny: [String]

    static func `default`(forProjectRoot root: URL) -> AXProjectConfig {
        // Heuristic: pick something sensible to reduce setup friction.
        let cmds = AXProjectStackDetector.recommendedVerifyCommands(forProjectRoot: root)

        return AXProjectConfig(
            schemaVersion: currentSchemaVersion,
            roleModelOverrides: [:],
            verifyCommands: cmds,
            verifyAfterChanges: true,
            toolProfile: ToolPolicy.defaultProfile.rawValue,
            toolAllow: [],
            toolDeny: []
        )
    }

    func modelOverride(for role: AXRole) -> String? {
        let v = (roleModelOverrides[role.rawValue] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    mutating func setModelOverride(role: AXRole, modelId: String?) {
        let v = (modelId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty {
            roleModelOverrides.removeValue(forKey: role.rawValue)
        } else {
            roleModelOverrides[role.rawValue] = v
        }
    }

    func settingModelOverride(role: AXRole, modelId: String?) -> AXProjectConfig {
        var out = self
        out.setModelOverride(role: role, modelId: modelId)
        return out
    }

    func settingToolPolicy(profile: String? = nil, allow: [String]? = nil, deny: [String]? = nil) -> AXProjectConfig {
        var out = self
        if let profile {
            let parsed = ToolPolicy.parseProfile(profile)
            out.toolProfile = parsed.rawValue
        }
        if let allow {
            out.toolAllow = ToolPolicy.normalizePolicyTokens(allow)
        }
        if let deny {
            out.toolDeny = ToolPolicy.normalizePolicyTokens(deny)
        }
        return out
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case roleModelOverrides
        case verifyCommands
        case verifyAfterChanges
        case toolProfile
        case toolAllow
        case toolDeny
    }

    init(
        schemaVersion: Int,
        roleModelOverrides: [String: String],
        verifyCommands: [String],
        verifyAfterChanges: Bool,
        toolProfile: String,
        toolAllow: [String],
        toolDeny: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.roleModelOverrides = roleModelOverrides
        self.verifyCommands = verifyCommands
        self.verifyAfterChanges = verifyAfterChanges
        self.toolProfile = ToolPolicy.parseProfile(toolProfile).rawValue
        self.toolAllow = ToolPolicy.normalizePolicyTokens(toolAllow)
        self.toolDeny = ToolPolicy.normalizePolicyTokens(toolDeny)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? c.decode(Int.self, forKey: .schemaVersion)) ?? AXProjectConfig.currentSchemaVersion
        roleModelOverrides = (try? c.decode([String: String].self, forKey: .roleModelOverrides)) ?? [:]
        verifyCommands = (try? c.decode([String].self, forKey: .verifyCommands)) ?? []
        verifyAfterChanges = (try? c.decode(Bool.self, forKey: .verifyAfterChanges)) ?? true
        let rawProfile = (try? c.decode(String.self, forKey: .toolProfile)) ?? ToolPolicy.defaultProfile.rawValue
        toolProfile = ToolPolicy.parseProfile(rawProfile).rawValue
        toolAllow = ToolPolicy.normalizePolicyTokens((try? c.decode([String].self, forKey: .toolAllow)) ?? [])
        toolDeny = ToolPolicy.normalizePolicyTokens((try? c.decode([String].self, forKey: .toolDeny)) ?? [])
    }
}
