import Foundation

struct XTAutomationRecipeAction: Codable, Equatable, Identifiable, Sendable {
    var actionID: String
    var title: String
    var tool: ToolName
    var args: [String: JSONValue]
    var continueOnFailure: Bool
    var successBodyContains: String
    var requiresVerification: Bool

    var id: String { actionID }

    enum CodingKeys: String, CodingKey {
        case actionID = "action_id"
        case title
        case tool
        case args
        case continueOnFailure = "continue_on_failure"
        case successBodyContains = "success_body_contains"
        case requiresVerification = "requires_verification"
    }

    init(
        actionID: String = "",
        title: String = "",
        tool: ToolName,
        args: [String: JSONValue] = [:],
        continueOnFailure: Bool = false,
        successBodyContains: String = "",
        requiresVerification: Bool = false
    ) {
        self.actionID = actionID
        self.title = title
        self.tool = tool
        self.args = args
        self.continueOnFailure = continueOnFailure
        self.successBodyContains = successBodyContains
        self.requiresVerification = requiresVerification
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        actionID = (try? c.decode(String.self, forKey: .actionID)) ?? ""
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        tool = try c.decode(ToolName.self, forKey: .tool)
        args = (try? c.decode([String: JSONValue].self, forKey: .args)) ?? [:]
        continueOnFailure = (try? c.decode(Bool.self, forKey: .continueOnFailure)) ?? false
        successBodyContains = (try? c.decode(String.self, forKey: .successBodyContains)) ?? ""
        requiresVerification = (try? c.decode(Bool.self, forKey: .requiresVerification)) ?? false
    }

    func normalized(defaultActionID: String) -> XTAutomationRecipeAction {
        var out = self
        out.actionID = xtAutomationActionToken(
            actionID.trimmingCharacters(in: .whitespacesAndNewlines),
            fallback: defaultActionID
        )
        out.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        out.successBodyContains = successBodyContains.trimmingCharacters(in: .whitespacesAndNewlines)
        out.args = out.args.reduce(into: [:]) { partial, item in
            let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            partial[key] = item.value
        }
        return out
    }

    func effectiveRequiresVerification(projectVerifyAfterChanges: Bool) -> Bool {
        if requiresVerification {
            return true
        }
        guard projectVerifyAfterChanges else { return false }
        return xtAutomationDefaultVerificationTriggerTools.contains(tool)
    }
}

func xtAutomationActionToken(_ raw: String, fallback: String) -> String {
    let source = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : raw
    let lowered = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !lowered.isEmpty else { return "action" }

    var buffer = ""
    var previousWasUnderscore = false
    for scalar in lowered.unicodeScalars {
        if CharacterSet.alphanumerics.contains(scalar) {
            buffer.unicodeScalars.append(scalar)
            previousWasUnderscore = false
        } else if !previousWasUnderscore {
            buffer.append("_")
            previousWasUnderscore = true
        }
    }
    let trimmed = buffer.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    return trimmed.isEmpty ? "action" : trimmed
}

private let xtAutomationDefaultVerificationTriggerTools: Set<ToolName> = [
    .write_file,
    .git_apply,
]
