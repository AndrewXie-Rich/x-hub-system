import Foundation

struct AXMemory: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int

    var projectName: String
    var projectRoot: String

    // High-level description of what the user is building.
    var goal: String

    // Requirements + scope.
    var requirements: [String]

    // Current progress / implemented pieces.
    var currentState: [String]

    // Key decisions and rationale.
    var decisions: [String]

    // Next planned work.
    var nextSteps: [String]

    // Open questions / risks.
    var openQuestions: [String]
    var risks: [String]

    // Optional: system-generated advice to revisit.
    var recommendations: [String]

    var updatedAt: Double

    static func new(projectName: String, projectRoot: String) -> AXMemory {
        AXMemory(
            schemaVersion: currentSchemaVersion,
            projectName: projectName,
            projectRoot: projectRoot,
            goal: "",
            requirements: [],
            currentState: [],
            decisions: [],
            nextSteps: [],
            openQuestions: [],
            risks: [],
            recommendations: [],
            updatedAt: Date().timeIntervalSince1970
        )
    }
}

struct AXMemoryDelta: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int

    // Additive updates. Keep them short and de-duplicated.
    var goalUpdate: String?
    var requirementsAdd: [String]
    var currentStateAdd: [String]
    var decisionsAdd: [String]
    var nextStepsAdd: [String]
    var openQuestionsAdd: [String]
    var risksAdd: [String]
    var recommendationsAdd: [String]

    // Optional: remove items that became obsolete.
    var requirementsRemove: [String]
    var currentStateRemove: [String]
    var nextStepsRemove: [String]
    var openQuestionsRemove: [String]
    var risksRemove: [String]

    static func empty() -> AXMemoryDelta {
        AXMemoryDelta(
            schemaVersion: currentSchemaVersion,
            goalUpdate: nil,
            requirementsAdd: [],
            currentStateAdd: [],
            decisionsAdd: [],
            nextStepsAdd: [],
            openQuestionsAdd: [],
            risksAdd: [],
            recommendationsAdd: [],
            requirementsRemove: [],
            currentStateRemove: [],
            nextStepsRemove: [],
            openQuestionsRemove: [],
            risksRemove: []
        )
    }
}
