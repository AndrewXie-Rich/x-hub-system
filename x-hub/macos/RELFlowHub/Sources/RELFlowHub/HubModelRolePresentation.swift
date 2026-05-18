import Foundation

enum HubModelRolePresentation {
    static func canonicalRoleToken(_ raw: String) -> String {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "assist", "advisor", "supervisor":
            return "supervisor"
        case "review", "reviewer":
            return "reviewer"
        case "translate", "summarize", "extract", "refine", "classify", "coder":
            return "coder"
        case "general":
            return "general"
        default:
            return normalized
        }
    }

    static func displayName(for role: String) -> String {
        switch role {
        case "supervisor":
            return "Supervisor"
        case "coder":
            return "Coder"
        case "reviewer":
            return "Reviewer"
        case "general":
            return "General"
        default:
            return role
        }
    }
}
