import Foundation

enum AXRole: String, Codable, CaseIterable, Identifiable {
    case coder
    case coarse
    case refine
    case reviewer
    case advisor
    case supervisor

    var id: String { rawValue }

    static let modelAssignmentHelpText =
        "coder / coarse / refine / reviewer / advisor（也支持：开发者 / 粗编 / 精修 / 审查 / 顾问）"

    static func resolveModelAssignmentToken(_ token: String) -> AXRole? {
        let normalized = token
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty else { return nil }

        if let exact = AXRole(rawValue: normalized) {
            switch exact {
            case .coder, .coarse, .refine, .reviewer, .advisor:
                return exact
            case .supervisor:
                return nil
            }
        }

        switch normalized {
        case "developer", "dev", "开发者", "开发", "编程", "编码":
            return .coder
        case "draft", "粗编", "粗稿", "初稿":
            return .coarse
        case "refiner", "polish", "精编", "精修", "润色":
            return .refine
        case "review", "审查", "审阅", "评审":
            return .reviewer
        case "顾问":
            return .advisor
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
