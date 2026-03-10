import Foundation

enum AXRole: String, Codable, CaseIterable, Identifiable {
    case coder
    case coarse
    case refine
    case reviewer
    case advisor
    case supervisor

    var id: String { rawValue }
    
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
