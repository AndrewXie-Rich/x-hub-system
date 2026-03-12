import Foundation

enum ProviderKind: String, Codable, CaseIterable, Identifiable {
    case hub
    case openai_compatible
    case anthropic
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hub: return "Hub"
        case .openai_compatible: return "OpenAI"
        case .anthropic: return "Claude"
        case .gemini: return "Gemini"
        }
    }
}

struct RoleProviderAssignment: Codable, Equatable {
    var role: AXRole
    var providerKind: ProviderKind
    var model: String?
}

struct OpenAICompatibleConfig: Codable, Equatable {
    var baseURL: String
    var model: String
}

struct AnthropicConfig: Codable, Equatable {
    var baseURL: String
    var model: String
}

struct GeminiConfig: Codable, Equatable {
    var baseURL: String
    var model: String
}

struct XTerminalSettings: Codable, Equatable {
    static let currentSchemaVersion = 4

    var schemaVersion: Int

    // Role -> provider selection.
    var assignments: [RoleProviderAssignment]

    // Provider configs.
    var openAICompatible: OpenAICompatibleConfig
    var anthropic: AnthropicConfig
    var gemini: GeminiConfig
    var voice: VoiceRuntimePreferences
    var supervisorPrompt: SupervisorPromptPreferences

    init(
        schemaVersion: Int,
        assignments: [RoleProviderAssignment],
        openAICompatible: OpenAICompatibleConfig,
        anthropic: AnthropicConfig,
        gemini: GeminiConfig,
        voice: VoiceRuntimePreferences,
        supervisorPrompt: SupervisorPromptPreferences
    ) {
        self.schemaVersion = schemaVersion
        self.assignments = assignments
        self.openAICompatible = openAICompatible
        self.anthropic = anthropic
        self.gemini = gemini
        self.voice = voice
        self.supervisorPrompt = supervisorPrompt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? c.decode(Int.self, forKey: .schemaVersion)) ?? Self.currentSchemaVersion
        assignments = (try? c.decode([RoleProviderAssignment].self, forKey: .assignments)) ?? []
        openAICompatible = (try? c.decode(OpenAICompatibleConfig.self, forKey: .openAICompatible)) ?? OpenAICompatibleConfig(baseURL: "https://api.openai.com/", model: "gpt-4o-mini")
        anthropic = (try? c.decode(AnthropicConfig.self, forKey: .anthropic)) ?? AnthropicConfig(baseURL: "https://api.anthropic.com/", model: "claude-3-5-sonnet-latest")
        gemini = (try? c.decode(GeminiConfig.self, forKey: .gemini)) ?? GeminiConfig(baseURL: "https://generativelanguage.googleapis.com/", model: "gemini-1.5-pro")
        voice = (try? c.decode(VoiceRuntimePreferences.self, forKey: .voice)) ?? .default()
        supervisorPrompt = ((try? c.decode(SupervisorPromptPreferences.self, forKey: .supervisorPrompt)) ?? .default()).normalized()

        // Ensure all roles have an assignment.
        for r in AXRole.allCases {
            if !assignments.contains(where: { $0.role == r }) {
                assignments.append(RoleProviderAssignment(role: r, providerKind: .hub, model: nil))
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case assignments
        case openAICompatible
        case anthropic
        case gemini
        case voice
        case supervisorPrompt
    }

    static func `default`() -> XTerminalSettings {
        XTerminalSettings(
            schemaVersion: currentSchemaVersion,
            assignments: [
                RoleProviderAssignment(role: .coder, providerKind: .hub, model: nil),
                RoleProviderAssignment(role: .coarse, providerKind: .hub, model: nil),
                RoleProviderAssignment(role: .refine, providerKind: .hub, model: nil),
                RoleProviderAssignment(role: .reviewer, providerKind: .hub, model: nil),
                RoleProviderAssignment(role: .advisor, providerKind: .hub, model: nil),
                RoleProviderAssignment(role: .supervisor, providerKind: .hub, model: nil),
            ],
            openAICompatible: OpenAICompatibleConfig(baseURL: "https://api.openai.com/", model: "gpt-4o-mini"),
            anthropic: AnthropicConfig(baseURL: "https://api.anthropic.com/", model: "claude-3-5-sonnet-latest"),
            gemini: GeminiConfig(baseURL: "https://generativelanguage.googleapis.com/", model: "gemini-1.5-pro"),
            voice: .default(),
            supervisorPrompt: .default()
        )
    }

    func assignment(for role: AXRole) -> RoleProviderAssignment {
        assignments.first(where: { $0.role == role }) ?? RoleProviderAssignment(role: role, providerKind: .hub, model: nil)
    }

    func setting(role: AXRole, providerKind: ProviderKind, model: String?) -> XTerminalSettings {
        var s = self
        s.schemaVersion = Self.currentSchemaVersion
        var arr = s.assignments
        if let idx = arr.firstIndex(where: { $0.role == role }) {
            arr[idx] = RoleProviderAssignment(role: role, providerKind: providerKind, model: model)
        } else {
            arr.append(RoleProviderAssignment(role: role, providerKind: providerKind, model: model))
        }
        s.assignments = arr
        return s
    }

    func setting(voice: VoiceRuntimePreferences) -> XTerminalSettings {
        var s = self
        s.schemaVersion = Self.currentSchemaVersion
        s.voice = voice
        return s
    }

    func setting(supervisorPrompt: SupervisorPromptPreferences) -> XTerminalSettings {
        var s = self
        s.schemaVersion = Self.currentSchemaVersion
        s.supervisorPrompt = supervisorPrompt.normalized()
        return s
    }
}
