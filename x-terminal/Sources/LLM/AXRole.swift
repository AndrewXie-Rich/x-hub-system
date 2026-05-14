import Foundation

enum AXRole: String, Codable, CaseIterable, Identifiable {
    case coder
    case coarse
    case refine
    case reviewer
    case advisor
    case supervisor

    var id: String { rawValue }

    static let allCases: [AXRole] = [.supervisor, .coder, .reviewer]

    static let modelAssignmentHelpText =
        "supervisor / coder / reviewer（也支持：主管 / 开发者 / 审查；旧别名 coarse / refine / advisor 仍兼容）"

    var primaryRole: AXRole {
        switch self {
        case .supervisor, .advisor:
            return .supervisor
        case .coder, .coarse, .refine:
            return .coder
        case .reviewer:
            return .reviewer
        }
    }

    var isPrimaryVisibleRole: Bool {
        Self.allCases.contains(self)
    }

    static func resolveModelAssignmentToken(_ token: String) -> AXRole? {
        let normalized = token
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty else { return nil }

        if let exact = AXRole(rawValue: normalized) {
            return exact.primaryRole
        }

        switch normalized {
        case "supervisor", "主管", "监督", "总控":
            return .supervisor
        case "developer", "dev", "开发者", "开发", "编程", "编码":
            return .coder
        case "draft", "粗编", "粗稿", "初稿":
            return .coder
        case "refiner", "polish", "精编", "精修", "润色":
            return .coder
        case "review", "审查", "审阅", "评审":
            return .reviewer
        case "advisor", "顾问", "建议":
            return .supervisor
        default:
            return nil
        }
    }
    
    var displayName: String {
        switch self {
        case .coder:
            return "编程助手"
        case .coarse:
            return "粗略生成"
        case .refine:
            return "精炼优化"
        case .reviewer:
            return "代码审查"
        case .advisor:
            return "顾问建议"
        case .supervisor:
            return "Supervisor"
        }
    }
}
