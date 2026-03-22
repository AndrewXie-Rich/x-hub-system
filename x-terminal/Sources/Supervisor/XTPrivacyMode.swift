import Foundation

enum XTPrivacyMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case balanced = "balanced"
    case tightenedContext = "tightened_context"

    static let defaultMode: XTPrivacyMode = .balanced

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .balanced:
            return "平衡"
        case .tightenedContext:
            return "收紧"
        }
    }

    var displayName: String {
        switch self {
        case .balanced:
            return "平衡模式"
        case .tightenedContext:
            return "收紧模式"
        }
    }

    var summary: String {
        switch self {
        case .balanced:
            return "质量优先；保持正常 recent raw dialogue continuity，同时继续使用 Hub 长期记忆和 session handoff capsules。"
        case .tightenedContext:
            return "收紧最近原始对话的直接暴露量，并优先让 Supervisor 使用摘要而不是复述原话；Hub 长期记忆和 handoff capsules 继续保留。"
        }
    }

    var runtimeBehaviorSummary: String {
        switch self {
        case .balanced:
            return "最近原始上下文 ceiling 维持你配置的档位；长期记忆、项目状态重建和 handoff summary 全部照常。"
        case .tightenedContext:
            return "最近原始上下文会收束到 Standard 或更低；长期记忆、项目状态重建和 handoff summary 不受影响。"
        }
    }

    var promptSummary: String {
        switch self {
        case .balanced:
            return "Use recent raw dialogue normally when it improves continuity, but avoid gratuitous quote dumping."
        case .tightenedContext:
            return "Preserve long-term memory and handoff capsules, but prefer concise summaries over replaying verbatim recent dialogue unless exact wording is necessary for accuracy or safety."
        }
    }

    func effectiveRecentRawContextProfile(
        _ configuredProfile: XTSupervisorRecentRawContextProfile
    ) -> XTSupervisorRecentRawContextProfile {
        switch self {
        case .balanced:
            return configuredProfile
        case .tightenedContext:
            switch configuredProfile {
            case .floor8Pairs, .standard12Pairs:
                return configuredProfile
            case .deep20Pairs, .extended40Pairs, .autoMax:
                return .standard12Pairs
            }
        }
    }

    func recentRawContextEffectSummary(
        configuredProfile: XTSupervisorRecentRawContextProfile
    ) -> String {
        let effectiveProfile = effectiveRecentRawContextProfile(configuredProfile)
        if effectiveProfile == configuredProfile {
            return "当前最近原始上下文继续按 \(configuredProfile.displayName) · \(configuredProfile.shortLabel) 执行。"
        }
        return "当前最近原始上下文会从 \(configuredProfile.displayName) · \(configuredProfile.shortLabel) 收束到 \(effectiveProfile.displayName) · \(effectiveProfile.shortLabel)。长期记忆与 session_summary_capsule 不受影响。"
    }
}
