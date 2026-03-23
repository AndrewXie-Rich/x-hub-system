import Foundation

enum XTSupervisorRecentRawContextProfile: String, Codable, CaseIterable, Identifiable, Sendable {
    case floor8Pairs = "floor_8_pairs"
    case standard12Pairs = "standard_12_pairs"
    case deep20Pairs = "deep_20_pairs"
    case extended40Pairs = "extended_40_pairs"
    case autoMax = "auto_max"

    static let hardFloorPairs = 8
    static let defaultProfile: XTSupervisorRecentRawContextProfile = .standard12Pairs

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .floor8Pairs:
            return "Floor"
        case .standard12Pairs:
            return "Standard"
        case .deep20Pairs:
            return "Deep"
        case .extended40Pairs:
            return "Extended"
        case .autoMax:
            return "Auto Max"
        }
    }

    var shortLabel: String {
        switch self {
        case .autoMax:
            return "Auto Max"
        default:
            return "\(windowCeilingPairs ?? Self.hardFloorPairs) pairs"
        }
    }

    var windowCeilingPairs: Int? {
        switch self {
        case .floor8Pairs:
            return 8
        case .standard12Pairs:
            return 12
        case .deep20Pairs:
            return 20
        case .extended40Pairs:
            return 40
        case .autoMax:
            return nil
        }
    }

    var summary: String {
        switch self {
        case .floor8Pairs:
            return "保留硬底线 8 个来回，最省预算，但 continuity 不会掉到 8 以下。"
        case .standard12Pairs:
            return "默认档；通常能覆盖最近一段正常对话，又不会把窗口吃得太满。"
        case .deep20Pairs:
            return "适合连续策划、代词多、需要反复引用最近承诺或约束的对话。"
        case .extended40Pairs:
            return "适合长链条个人助理对话、复杂 brainstorm、需要更强 continuity 的场景。"
        case .autoMax:
            return "在当前模型窗口允许范围内尽量保留更多 recent raw dialogue，但仍受预算和治理约束。"
        }
    }
}

enum AXProjectRecentDialogueProfile: String, Codable, CaseIterable, Identifiable, Sendable {
    case floor8Pairs = "floor_8_pairs"
    case standard12Pairs = "standard_12_pairs"
    case deep20Pairs = "deep_20_pairs"
    case extended40Pairs = "extended_40_pairs"
    case autoMax = "auto_max"

    static let hardFloorPairs = 8
    static let defaultProfile: AXProjectRecentDialogueProfile = .standard12Pairs

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .floor8Pairs:
            return "Floor"
        case .standard12Pairs:
            return "Standard"
        case .deep20Pairs:
            return "Deep"
        case .extended40Pairs:
            return "Extended"
        case .autoMax:
            return "Auto Max"
        }
    }

    var shortLabel: String {
        switch self {
        case .autoMax:
            return "Auto Max"
        default:
            return "\(windowCeilingPairs ?? Self.hardFloorPairs) pairs"
        }
    }

    var windowCeilingPairs: Int? {
        switch self {
        case .floor8Pairs:
            return 8
        case .standard12Pairs:
            return 12
        case .deep20Pairs:
            return 20
        case .extended40Pairs:
            return 40
        case .autoMax:
            return nil
        }
    }

    var summary: String {
        switch self {
        case .floor8Pairs:
            return "只保留项目 continuity 的硬底线 8 个来回，适合最省窗口的执行场景。"
        case .standard12Pairs:
            return "默认档；通常足够承接“继续刚才那步”“刚才那个 blocker”这类项目对话。"
        case .deep20Pairs:
            return "适合连续调试、review 来回多、需要反复引用近期执行证据的项目。"
        case .extended40Pairs:
            return "适合长链条 refactor / rescue / 复杂交付，保留更长的项目原始对话。"
        case .autoMax:
            return "让 coder 尽量多带 recent project dialogue，但仍受模型窗口和预算约束。"
        }
    }
}

enum AXProjectContextDepthProfile: String, Codable, CaseIterable, Identifiable, Sendable {
    case lean
    case balanced
    case deep
    case full
    case auto

    static let defaultProfile: AXProjectContextDepthProfile = .balanced

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lean:
            return "Lean"
        case .balanced:
            return "Balanced"
        case .deep:
            return "Deep"
        case .full:
            return "Full"
        case .auto:
            return "Auto"
        }
    }

    var summary: String {
        switch self {
        case .lean:
            return "只带 focused project anchor、当前 workflow、最新 blocker / next step，加上 recent project dialogue。"
        case .balanced:
            return "默认档；在 Lean 基础上加入最新 review / guidance、精选 build/test 摘要和 cross-link hints。"
        case .deep:
            return "在 Balanced 基础上扩展 active plan、执行证据引用、selected longterm outline 和 drift summary。"
        case .full:
            return "在 Deep 基础上加入更大的 retrieval pack、更多执行证据片段和更广的决策 lineage。"
        case .auto:
            return "根据模型窗口、任务风险和预算，自适应选择上下文厚度。"
        }
    }
}
